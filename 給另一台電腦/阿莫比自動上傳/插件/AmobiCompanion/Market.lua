-- 阿莫比小幫手：拍賣場物價記錄（1.6.0；老闆 10/25：「我們的ui裡面可以先寫入撈取拍賣場跟副本boss掉落的資料，透過隱形頻道傳給我」）
--
-- 打開拍賣場時自動向伺服器要一次全部的拍賣清單（C_AuctionHouse.ReplicateItems，伺服器規定 15 分鐘一次），
-- 整理成每件物品的數量、筆數、最低一口價、中位數和價格分布，存起來，由 Share.lua 在阿莫比站長在線時傳過去。
-- 讀法照站長自己的拍賣場插件（addon\AmobiAuction），只保留全掃描：
--   * 只在「分享給阿莫比」開著、在公會裡、而且 14 天內看過阿莫比站長在線時才自動掃（不在阿莫比公會的人掃了也傳不出去）
--   * 這台電腦也裝了 AmobiAuction（站長自己）就不做，免得掃兩次
--   * 存檔只留 7 天、最多 10 次掃描（傳完的只留摘要）
-- 只讀數量和一口價：賣家、出價者的名字不拿。不會替你搜尋、翻頁、買、出價、上架或取消。

local _, ns = ...
local M = {}
ns.Market = M

local FULL_COOLDOWN = 15 * 60  -- 秒：伺服器 15 分鐘只給掃一次全部
local REPLY_TIMEOUT = 60       -- 秒：要了之後這麼久都沒收到清單，就當這次不給
local BATCH = 1000             -- 一個畫面讀幾筆（幾萬筆一次讀完，遊戲會頓一下）
local SETTLE = 2               -- 秒：讀到尾巴後，伺服器安靜這麼久才算讀完（清單可能分幾次到）
local AUTO_DELAY = 1           -- 秒：打開拍賣場後等這麼久再自動掃描
local OTHER_GAP = 10 * 60      -- 秒：別的插件要的全部清單，離上次讀不到 10 分鐘就不重讀
local KEEP_DAYS = 7
local MAX_SCANS = 10
-- 中立拍賣場所在的地方（AreaTable 的藏寶海灣、加基森、永望鎮；永恆客戶端 1.60.1.70450）
local NEUTRAL_AREAS = { 35, 976, 2255 }

local db, job, ahOpen, panel, neutralNames

local function now() return GetServerTime and GetServerTime() or time() end
local function num(v) return type(v) == "number" and not ns.Secret(v) end

-- 36 進位：價格、數量用這個存，傳的時候短很多（網站那邊照樣解回來）
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
function M.B36(n)
  n = math.floor(n)
  if n <= 0 then return "0" end
  local s = ""
  while n > 0 do
    local r = n % 36
    s = DIGITS:sub(r + 1, r + 1) .. s
    n = (n - r) / 36
  end
  return s
end
local B36 = M.B36

-- 站長自己的拍賣場插件在跑：這邊什麼都不做
local function standalone() return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("AmobiAuction") end

function M.Active()
  if standalone() or ns.db.settings.share == false then return false end
  return ns.Share and ns.Share.Reachable() or false
end

local function where()
  if not neutralNames then
    neutralNames = {}
    for _, id in ipairs(NEUTRAL_AREAS) do
      local name = C_Map and C_Map.GetAreaInfo and ns.Call(C_Map, "GetAreaInfo", id)
      if type(name) == "string" and name ~= "" then neutralNames[name] = true end
    end
  end
  local zone = GetSubZoneText and GetSubZoneText() or ""
  if type(zone) ~= "string" or ns.Secret(zone) then zone = "" end
  local mini = GetMinimapZoneText and GetMinimapZoneText()
  local ah = (neutralNames[zone] or (type(mini) == "string" and not ns.Secret(mini) and neutralNames[mini])) and "neutral" or "faction"
  return GetRealmName(), UnitFactionGroup("player"), ah
end

local function cooldownLeft()
  local last = db.last[GetRealmName()]
  if not last then return 0 end
  local left = last + FULL_COOLDOWN - now()
  return left > 0 and left or 0
end

local function addScan(rec)
  local keep, oldest = {}, now() - KEEP_DAYS * 86400
  for _, s in ipairs(db.scans) do
    if s.t >= oldest then keep[#keep + 1] = s end
  end
  keep[#keep + 1] = rec
  while #keep > MAX_SCANS do table.remove(keep, 1) end
  db.scans = keep
end

-- 一件物品：拍賣（{單價, 數量}，沒有一口價的單價是 nil）→ 上架數量、筆數、最低一口價、中位數、第 10、25、75 百分位（照數量算）
local function summarize(list)
  local q, priced, units = 0, {}, 0
  for _, a in ipairs(list) do
    q = q + a[2]
    if a[1] then
      priced[#priced + 1] = a
      units = units + a[2]
    end
  end
  if #priced == 0 then return q, #list end
  table.sort(priced, function(x, y) return x[1] < y[1] end)
  local function at(n, den)
    local seen = 0
    for _, a in ipairs(priced) do
      seen = seen + a[2]
      if seen * den >= units * n then return a[1] end
    end
    return priced[#priced][1]
  end
  return q, #list, priced[1][1], at(1, 2), at(1, 10), at(1, 4), at(3, 4)
end

-- 「編號,數量,筆數,最低,中位數,第10,第25,第75;…」，每個數字都是 36 進位（不知道的空著）
local function encode(per)
  local ids = {}
  for id in pairs(per) do ids[#ids + 1] = id end
  table.sort(ids)
  local out = {}
  for _, id in ipairs(ids) do
    local p = per[id]
    local f = { B36(id), B36(p.q), p.n and B36(p.n) or "" }
    for _, k in ipairs({ "min", "med", "p10", "p25", "p75" }) do f[#f + 1] = p[k] and B36(p[k]) or "" end
    out[#out + 1] = table.concat(f, ",")
  end
  return table.concat(out, ";"), #ids
end

-- ------------------------------------------------------------------ 拍賣場上方的一小條（只有這個功能在做事時才出現）
local function refresh()
  if not panel or not panel:IsShown() then return end
  local text
  if job and job.state == "waiting" then
    text = "已向伺服器要全部的拍賣清單（最多 1 分鐘）"
  elseif job then
    text = ("讀取中：%d／%d 筆"):format(job.i, job.n)
  else
    local left = cooldownLeft()
    local s = db.scans[#db.scans]
    if left > 0 then
      text = ("記下了，阿莫比站長在線時會傳過去。15 分鐘後可以再掃（還要 %d 分）"):format(math.ceil(left / 60))
    elseif s then
      text = ("上次全掃描 %s，%d 種物品"):format(date("%m/%d %H:%M", s.t), s.items or 0)
    else
      text = "打開拍賣場會自動掃一次全部，幫阿莫比網站記物價"
    end
    if db.autoBlocked then text = text .. "（遊戲要你親手按）" end
  end
  panel.status:SetText(text)
  if job or cooldownLeft() > 0 then panel.scan:Disable() else panel.scan:Enable() end
end

local function showPanel()
  if not panel then
    panel = ns.UI.Panel(UIParent, 360, 44, "HIGH")
    ns.UI.Place(panel, "marketPos", "TOP", UIParent, "TOP", 0, -96)
    ns.UI.Movable(panel, "marketPos")
    local title = ns.UI.Text(panel, "GameFontNormalSmall", ns.GOLD .. "阿莫比|r 拍賣場物價")
    title:SetPoint("TOPLEFT", 10, -6)
    panel.status = ns.UI.Text(panel, "GameFontHighlightSmall", "", 250)
    panel.status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    panel.scan = ns.UI.Button(panel, "掃描全部", 86, 22, function() M.Start("button") end)
    panel.scan:SetPoint("RIGHT", -8, 0)
    local acc = 0
    panel:SetScript("OnUpdate", function(_, dt)
      acc = acc + dt
      if acc >= 1 then acc = 0; ns.Try("market:refresh", refresh) end
    end)
  end
  panel:Show()
  refresh()
end

-- ------------------------------------------------------------------ 全掃描
local function finish(j, partial)
  job = nil
  db.stats.reads = (db.stats.reads or 0) + 1
  if j.n == 0 and not partial then refresh() return end
  for _, per in pairs(j.per) do
    per.q, per.n, per.min, per.med, per.p10, per.p25, per.p75 = summarize(per.list)
    per.list = nil
  end
  local rec = j.rec
  rec.data, rec.items = encode(j.per)
  rec.auctions, rec.done = j.count, now()
  if partial then rec.partial = true end
  addScan(rec)
  db.lastRead = rec.t
  if ns.Share then ns.Share.Kick() end
  refresh()
end

local function readBatch(j)
  if job ~= j then return end
  local get = C_AuctionHouse.GetReplicateItemInfo
  local stop = math.min(j.n, j.i + BATCH)
  while j.i < stop do
    local index = j.i
    j.i = j.i + 1
    -- 只拿數量、一口價、狀態、物品編號；賣家、出價者的名字不拿
    local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, status, id = get(index)
    if count == nil and id == nil then return finish(j, true) end
    if num(id) and num(count) and id > 0 and count > 0 and (buyout == nil or num(buyout)) and not (num(status) and status ~= 0) then
      local per = j.per[id]
      if not per then per = { list = {} }; j.per[id] = per end
      local priced = num(buyout) and buyout > 0
      per.list[#per.list + 1] = { priced and math.floor(buyout / count + 0.5) or nil, count }
      j.count = j.count + 1
    end
  end
  local wait = 0
  if j.i >= j.n then
    local n = C_AuctionHouse.GetNumReplicateItems()
    if num(n) and n > j.n then
      j.n = n
    elseif GetTime() - j.heard < SETTLE then
      wait = 0.5
    else
      return finish(j, false)
    end
  end
  C_Timer.After(wait, function() ns.Try("market:read", readBatch, j) end)
end

local function beginRead(how)
  local realm, faction, ah = where()
  local n = C_AuctionHouse.GetNumReplicateItems()
  job = { state = "reading", i = 0, n = num(n) and n or 0, per = {}, count = 0, heard = GetTime(),
          rec = { kind = "full", t = now(), realm = realm, faction = faction, ah = ah, how = how } }
  if how == "other" then db.last[realm] = job.rec.t end
  local j = job
  C_Timer.After(0, function() ns.Try("market:read", readBatch, j) end)
  refresh()
end

local function checkTimeout(j)
  if job ~= j or j.state ~= "waiting" then return end
  local n = C_AuctionHouse.GetNumReplicateItems()
  if num(n) and n > 0 then return beginRead(j.how) end
  job = nil
  if j.how == "auto" then db.last[j.realm] = j.prevLast end   -- 自動的沒回應：可能要親手按，15 分鐘不算
  refresh()
end

-- 打開拍賣場時自動一次，或玩家按「掃描全部」
function M.Start(how)
  if job or not ahOpen or not M.Active() then return end
  if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems and C_AuctionHouse.GetReplicateItemInfo) then return end
  if cooldownLeft() > 0 then return refresh() end
  local realm = GetRealmName()
  job = { state = "waiting", how = how, realm = realm, prevLast = db.last[realm] }
  db.last[realm] = now()
  C_AuctionHouse.ReplicateItems()
  local j = job
  C_Timer.After(REPLY_TIMEOUT, function() ns.Try("market:timeout", checkTimeout, j) end)
  refresh()
end

local function onReplicate()
  if not M.Active() then return end
  local n = C_AuctionHouse.GetNumReplicateItems()
  if job and job.state == "waiting" then
    beginRead(job.how)
  elseif job then
    job.heard = GetTime()
    if num(n) and n > job.n then job.n = n end
  elseif num(n) and n > 0 and not (db.lastRead and now() - db.lastRead < OTHER_GAP) then
    beginRead("other")                           -- 別的插件要的全部清單：照樣讀一份
  end
end

-- 遊戲說要親手按才給全部清單：之後不自動，改成按拍賣場上方的「掃描全部」
local function onForbidden(addon, func)
  if ns.Secret(addon) or addon ~= ns.ADDON or (type(func) == "string" and not func:find("ReplicateItems", 1, true)) then return end
  if job and job.state == "waiting" and job.how == "auto" then
    db.last[job.realm] = job.prevLast
    job = nil
  end
  db.autoBlocked = true
  refresh()
end

-- 這次掃描傳過去了：只留摘要（存檔不要越來越大）
function M.MarkSent(rec)
  rec.sent = now()
  rec.data = nil
end

function M.Scans() return db and db.scans or {} end

function M.Status()
  if standalone() then return "這台電腦裝了阿莫比拍賣場插件（AmobiAuction），由它記，這裡不重複掃。" end
  local n, last = #db.scans, db.scans[#db.scans]
  if n == 0 then return "還沒掃過拍賣場。" end
  return ("記了 %d 次全掃描，最近一次 %s（%d 種物品）。"):format(n, date("%m/%d %H:%M", last.t), last.items or 0)
end

function M.Init()
  ns.db.market = type(ns.db.market) == "table" and ns.db.market or {}
  db = ns.db.market
  for _, k in ipairs({ "scans", "last", "stats" }) do
    if type(db[k]) ~= "table" then db[k] = {} end
  end
  ns.On("AUCTION_HOUSE_SHOW", function()
    ahOpen = true
    if not M.Active() then return end
    showPanel()
    if not db.autoBlocked then C_Timer.After(AUTO_DELAY, function() ns.Try("market:auto", M.Start, "auto") end) end
  end)
  ns.On("AUCTION_HOUSE_CLOSED", function()
    ahOpen = false
    if panel then panel:Hide() end
  end)
  ns.On("REPLICATE_ITEM_LIST_UPDATE", onReplicate)
  ns.On("ADDON_ACTION_FORBIDDEN", onForbidden)
  ns.On("ADDON_ACTION_BLOCKED", onForbidden)
  ns.On("PLAYER_LOGOUT", function()
    if job and job.state == "reading" then finish(job, true) end   -- 讀到一半就登出：讀到的先存
  end)
end

ns.Register(M)
