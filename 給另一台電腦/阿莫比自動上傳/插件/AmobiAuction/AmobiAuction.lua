-- 阿莫比拍賣場物價（AmobiAuction）
--
-- 遊戲裡只看得到拍賣場「現在」的價格，看不到以前的。這個插件把物價記下來，彙整後放到阿莫比網站（wowamobi.com）的物品頁，
-- 畫成價格走勢。兩種記法：
--   1. 全掃描：打開拍賣場時自動向伺服器要一次全部的拍賣清單（1.1.0，老闆 10/24：「每天打開拍賣場就能撈到」；
--      /amobiah auto off 可以關掉），也可以按「掃描全部」或打 /amobiah scan。C_AuctionHouse.ReplicateItems，伺服器規定 15 分鐘一次，
--      插件自己記時間。資料到了分批讀完（一個畫面讀 1000 筆，遊戲不會卡），每件物品記：上架數量、拍賣筆數、最低一口價（單價）、
--      中位數，和價格分布（照數量算的第 10、25、75 百分位：最便宜的 10%、25% 在多少錢以下，最貴的 25% 在多少錢以上）。
--      自動掃描如果伺服器 1 分鐘沒回應（可能要玩家親手按），15 分鐘的等待不算，可以馬上按「掃描全部」；
--      如果遊戲擋下來（ADDON_ACTION_FORBIDDEN），之後就不再自動，改回親手按。
--   2. 瀏覽：玩家平常在拍賣場點分類、搜尋、點進某件物品時，遊戲顯示的結果順便記下來（只讀畫面上已經有的資料，不另外送查詢）。
--      分類清單有每件物品的總數量和最低價；點進物品看到全部拍賣時，也算得出中位數。每次打開拍賣場到關掉算一次。
-- 單價＝一口價 ÷ 這筆的數量（四捨五入到銅）；中位數照數量算（一疊 20 個算 20 個），只有競標、沒有一口價的不算價格。
--
-- 只被動讀資料：除了全掃描（打開拍賣場時自動一次、或玩家按），不會替你搜尋、翻頁、買、出價、上架、取消，也不存任何賣家、出價者的名字。
-- 存檔：AmobiAuctionDB（WTF\Account\<帳號>\SavedVariables\AmobiAuction.lua）；彙整成網站的資料：tools\amobi_auction.py。
-- 指令：/amobiah 看記了多少；/amobiah scan 掃描全部（要先打開拍賣場）；/amobiah auto on／off 打開拍賣場自動掃描；
--       /amobiah quiet、loud 掃完要不要在聊天框說。

local ADDON = ...

local FULL_COOLDOWN = 15 * 60  -- 秒：全掃描之後要等 15 分鐘才能再掃（伺服器的限制）
local REPLY_TIMEOUT = 60       -- 秒：按下去之後這麼久都沒收到清單，就當伺服器這次不給
local BATCH = 1000             -- 一個畫面讀幾筆（幾萬筆一次讀完，遊戲會頓一下）
local MAX_SCANS = 200          -- 存檔最多留幾次掃描（舊的先刪）
local KEEP_DAYS = 45           -- 超過 45 天的掃描刪掉
local SAMPLE = 6               -- 全掃描時各留幾筆有疊、沒疊的原始數字，用來核對一口價是「整筆」還是「單價」
local OTHER_GAP = 10 * 60      -- 秒：沒按按鈕卻收到全部清單（別的插件要的）時，離上次讀不到 10 分鐘就不重讀
local SETTLE = 2               -- 秒：讀到清單尾巴時，伺服器要安靜這麼久（沒有再傳）才算讀完；清單可能分幾次到
local AUTO_DELAY = 1           -- 秒：打開拍賣場後等這麼久再自動掃描（拍賣場視窗先載好）
-- 中立拍賣場所在的地方（AreaTable 的藏寶海灣、加基森、永望鎮；永恆客戶端 1.60.1.70450）。名稱登入後用遊戲的翻譯
local NEUTRAL_AREAS = { 35, 976, 2255 }
local FACTION_ZH = { Alliance = "聯盟", Horde = "部落" }

local frame = CreateFrame("Frame")
local db
local ahOpen = false
local job                      -- 進行中的全掃描
local panel
local neutralNames
local startFull
local autoScan, onForbidden

local function tell(msg) print("|cffe9cb88阿莫比拍賣場|r " .. msg) end
local function say(msg) if not db.settings.quiet then tell(msg) end end
local function now() return GetServerTime and GetServerTime() or time() end

-- 新版客戶端可能把某些值換成「秘密值」，插件不能比較、也不能存檔；遇到就略過，記一筆
local function hidden(v)
  if (issecretvalue and issecretvalue(v)) or (type(v) == "table" and issecrettable and issecrettable(v)) then
    db.stats.hidden = db.stats.hidden + 1
    return true
  end
  return false
end

local function num(v) return type(v) == "number" and not hidden(v) end

local function commas(n)
  local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (s:gsub("^,", ""))
end

local function clock(secs)
  secs = math.ceil(secs)
  return ("%d:%02d"):format(math.floor(secs / 60), secs % 60)
end

-- 插件自己出錯時不跳錯誤視窗、不打擾玩遊戲：記在存檔裡，/amobiah 會說
local function safely(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    db.stats.errors = db.stats.errors + 1
    db.stats.lastError = tostring(err):sub(1, 200)
  end
end

-- 這是哪個伺服器、哪個陣營、哪一種拍賣場（陣營的，或藏寶海灣、加基森、永望鎮的中立拍賣場）
local function where()
  if not neutralNames then
    neutralNames = {}
    for _, id in ipairs(NEUTRAL_AREAS) do
      local name = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(id)
      if type(name) == "string" and name ~= "" then neutralNames[name] = true end
    end
  end
  local zone = GetSubZoneText and GetSubZoneText() or ""
  if type(zone) ~= "string" or hidden(zone) then zone = "" end
  local mini = GetMinimapZoneText and GetMinimapZoneText()
  local ah = (neutralNames[zone] or (type(mini) == "string" and neutralNames[mini])) and "neutral" or "faction"
  local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  return GetRealmName(), UnitFactionGroup("player"), ah, zone, num(map) and map or nil
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

-- 一件物品的數字：拍賣（{單價, 數量}，沒有一口價的單價是 nil）→ 上架數量、筆數、最低一口價、中位數，
-- 和第 10、25、75 百分位（都照數量算：一疊 20 個算 20 份；第 10 百分位＝由便宜往貴數到第 10% 個的單價）
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
  local function at(num, den)               -- 第 num/den 位：累計數量 × den ≥ 總數 × num 的第一筆
    local seen = 0
    for _, a in ipairs(priced) do
      seen = seen + a[2]
      if seen * den >= units * num then return a[1] end
    end
    return priced[#priced][1]
  end
  return q, #list, priced[1][1], at(1, 2), at(1, 10), at(1, 4), at(3, 4)
end

-- 存檔裡一次掃描的物品：「編號,數量,筆數,最低一口價,中位數,第10,第25,第75百分位;…」（不知道的欄位空著；1.0.0 只有前 5 欄）。
-- 比一件一個表格小很多，幾萬件也讀得快
local function encode(per)
  local ids = {}
  for id in pairs(per) do ids[#ids + 1] = id end
  table.sort(ids)
  local out = {}
  for _, id in ipairs(ids) do
    local p = per[id]
    out[#out + 1] = id .. "," .. p.q .. "," .. (p.n or "") .. "," .. (p.min or "") .. "," .. (p.med or "")
      .. "," .. (p.p10 or "") .. "," .. (p.p25 or "") .. "," .. (p.p75 or "")
  end
  return table.concat(out, ";"), #ids
end

local function unit(total, count) return math.floor(total / count + 0.5) end

-- ------------------------------------------------------------------ 面板（拍賣場視窗下面的一小條）
local refresh

local function buildPanel()
  panel = CreateFrame("Frame", "AmobiAuctionPanel", UIParent)
  panel:SetSize(330, 54)
  panel:SetFrameStrata("HIGH")
  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.78)
  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", 10, -7)
  title:SetText("|cffe9cb88阿莫比|r 拍賣場物價")
  panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  panel.status:SetPoint("RIGHT", panel, "RIGHT", -112, 0)
  panel.status:SetJustifyH("LEFT")
  panel.scan = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  panel.scan:SetSize(96, 24)
  panel.scan:SetPoint("RIGHT", -10, 0)
  panel.scan:SetText("掃描全部")
  panel.scan:SetScript("OnClick", function() safely(startFull, "button") end)
  local acc = 0
  panel:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc >= 1 then
      acc = 0
      safely(refresh)
    end
  end)
  panel:Hide()
end

local function lastFull()
  local realm = GetRealmName()
  for i = #db.scans, 1, -1 do
    local s = db.scans[i]
    if s.kind == "full" and s.realm == realm then return s end
  end
end

refresh = function()
  if not panel or not panel:IsShown() then return end
  local text, ready
  if job and job.state == "waiting" then
    text = "已送出，等伺服器傳清單（最多 1 分鐘）"
  elseif job then
    text = ("讀取中：%s／%s 筆"):format(commas(job.i), commas(job.n))
  else
    local left, s = cooldownLeft(), lastFull()
    if left > 0 then
      text = ("伺服器 15 分鐘只給掃一次，還要 %s"):format(clock(left))
    elseif s then
      text, ready = ("上次全掃描 %s，%s 種物品"):format(date("%m/%d %H:%M", s.t), commas(s.items or 0)), true
    else
      text, ready = "這個伺服器還沒掃過：按右邊開始", true
    end
    if ready and db.settings.autoBlocked then text = text .. "（遊戲要你親手按）" end
  end
  local v = db.open
  if v and v.n and v.n > 0 then text = text .. ("\n點分類、物品時記到 %d 種"):format(v.n) end
  panel.status:SetText(text)
  panel.ready = ready and true or false
  if ready then panel.scan:Enable() else panel.scan:Disable() end
end

local function showPanel()
  if not panel then buildPanel() end
  panel:ClearAllPoints()
  if AuctionHouseFrame then
    panel:SetPoint("TOPRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", 0, -2)
  else
    panel:SetPoint("TOP", UIParent, "TOP", 0, -100)
  end
  panel:Show()
  refresh()
end

-- ------------------------------------------------------------------ 全掃描
local function finishFull(j, partial)
  job = nil
  local rec = j.rec
  if j.n == 0 and not partial then
    db.stats.empty = db.stats.empty + 1
    tell("伺服器給的清單是空的，沒有記。15 分鐘後可以再試一次。")
    refresh()
    return
  end
  for _, per in pairs(j.per) do
    per.q, per.n, per.min, per.med, per.p10, per.p25, per.p75 = summarize(per.list)
    per.list = nil
  end
  rec.data, rec.items = encode(j.per)
  rec.auctions, rec.listed, rec.nobuyout, rec.sold, rec.bad = j.count, j.n, j.nobuy, j.sold, j.bad
  rec.secs = math.floor(GetTime() - j.started + 0.5)
  rec.done = now()                                -- 讀完的時間（網站顯示這個）
  if partial then rec.partial = true end
  addScan(rec)
  db.lastRead = rec.t
  local rows = {}
  for _, r in ipairs(j.stack) do rows[#rows + 1] = r end
  for _, r in ipairs(j.single) do rows[#rows + 1] = r end
  db.sample = { t = rec.t, rows = rows }
  if partial then
    tell(("清單讀到一半就沒了（拍賣場關掉或斷線）：讀到 %s／%s 筆，先記下來，網站不會用這次的數字。")
      :format(commas(j.i - 1), commas(j.n)))
  else
    say(("全掃描完成：%s 筆拍賣、%s 種物品，花了 %d 秒。登出或 /reload 時會寫進存檔。")
      :format(commas(j.count), commas(rec.items), rec.secs))
  end
  refresh()
end

local function readBatch(j)
  if job ~= j then return end
  local get = C_AuctionHouse.GetReplicateItemInfo
  local stop = math.min(j.n, j.i + BATCH)
  while j.i < stop do
    local index = j.i
    j.i = j.i + 1
    -- 只拿數量、一口價、狀態、物品編號（和留樣本用的出價）；賣家、出價者的名字不拿
    local _, _, count, _, _, _, _, minBid, _, buyout, bid, _, _, _, _, status, id = get(index)
    if count == nil and id == nil then return finishFull(j, true) end
    if not (num(id) and num(count) and id > 0 and count > 0) or (buyout ~= nil and not num(buyout)) then
      j.bad = j.bad + 1
    elseif num(status) and status ~= 0 then
      j.sold = j.sold + 1                      -- 已賣出（Enum.AuctionStatus.Sold），不是還在賣的
    else
      local per = j.per[id]
      if not per then
        per = { list = {} }
        j.per[id] = per
      end
      local priced = num(buyout) and buyout > 0
      per.list[#per.list + 1] = { priced and unit(buyout, count) or nil, count }
      j.count = j.count + 1
      if not priced then j.nobuy = j.nobuy + 1 end
      local keep = count > 1 and j.stack or j.single
      if #keep < SAMPLE then
        keep[#keep + 1] = { id, count, num(buyout) and buyout or 0, num(minBid) and minBid or 0, num(bid) and bid or 0 }
      end
    end
  end
  local wait = 0
  if j.i >= j.n then
    local n = C_AuctionHouse.GetNumReplicateItems()
    if num(n) and n > j.n then
      j.n = n                                    -- 讀的時候又到了更多
    elseif GetTime() - j.heard < SETTLE then
      wait = 0.5                                 -- 讀到尾巴了，再等一下看伺服器還有沒有要傳
    else
      return finishFull(j, false)
    end
  end
  refresh()
  C_Timer.After(wait, function() safely(readBatch, j) end)
end

local function beginRead(how)
  local realm, faction, ah, zone, map = where()
  local n = C_AuctionHouse.GetNumReplicateItems()
  job = { state = "reading", how = how, i = 0, n = num(n) and n or 0, per = {}, count = 0, nobuy = 0, sold = 0, bad = 0,
          stack = {}, single = {}, started = GetTime(), heard = GetTime(),
          rec = { kind = "full", t = now(), realm = realm, faction = faction, ah = ah, zone = zone, map = map, how = how } }
  if how == "other" then db.last[realm] = job.rec.t end   -- 別的插件要的：伺服器的 15 分鐘也從這時候算
  refresh()
  local j = job
  C_Timer.After(0, function() safely(readBatch, j) end)
end

local function checkTimeout(j)
  if job ~= j or j.state ~= "waiting" then return end
  local n = C_AuctionHouse.GetNumReplicateItems()
  if num(n) and n > 0 then return beginRead(j.how) end   -- 清單其實到了，只是沒收到通知
  job = nil
  db.stats.timeouts = db.stats.timeouts + 1
  if j.how == "auto" then
    db.last[j.realm] = j.prevLast                -- 自動的沒回應：可能要親手按，15 分鐘不算，可以馬上按
    db.stats.autoTimeouts = (db.stats.autoTimeouts or 0) + 1
    tell("自動掃描等了 1 分鐘，伺服器沒有給清單：按拍賣場下面的「掃描全部」試試看（可能要親手按）。")
  else
    tell("等了 1 分鐘，伺服器沒有給清單（可能 15 分鐘內有人用這個帳號掃過）。15 分鐘後再按一次；這段時間點分類、點物品，照樣會記下價格。")
  end
  refresh()
end

-- 玩家按「掃描全部」或打 /amobiah scan：這是唯一會向伺服器要資料的地方，而且只在玩家親手操作時
startFull = function(how)
  if job then return tell("正在掃描，等它跑完。") end
  if not ahOpen then return tell("要先打開拍賣場（跟拍賣師說話），才能掃描全部。") end
  if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems and C_AuctionHouse.GetReplicateItemInfo) then
    return tell("這個遊戲版本沒有全掃描（C_AuctionHouse.ReplicateItems）。點分類、點物品時照樣會記，請告訴阿莫比。")
  end
  local left = cooldownLeft()
  if left > 0 then
    tell(("伺服器 15 分鐘只給掃一次全部，還要 %s。這段時間點分類、點物品，照樣會記下價格。"):format(clock(left)))
    return refresh()
  end
  local realm = GetRealmName()
  job = { state = "waiting", how = how, realm = realm, prevLast = db.last[realm] }
  db.last[realm] = now()
  db.stats.asked = db.stats.asked + 1
  C_AuctionHouse.ReplicateItems()
  say((how == "auto" and "打開拍賣場，自動向伺服器要全部的拍賣清單" or "已向伺服器要全部的拍賣清單")
    .. "：資料到了會自動讀完，通常幾秒到一分鐘，這段時間可以照常逛。")
  local j = job
  C_Timer.After(REPLY_TIMEOUT, function() safely(checkTimeout, j) end)
  refresh()
end

local function onReplicate()
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

-- 打開拍賣場時自動掃描：設定沒關、遊戲沒擋過、15 分鐘到了、拍賣場還開著才做
autoScan = function()
  if not ahOpen or job or db.settings.auto == false or db.settings.autoBlocked then return end
  if cooldownLeft() > 0 then return end
  startFull("auto")
end

-- 遊戲說這個插件叫了被禁止的功能：是全掃描的話，之後不再自動（改回親手按），只說一次
onForbidden = function(addon, func)
  if addon ~= ADDON or (type(func) == "string" and not func:find("ReplicateItems", 1, true)) then return end
  if job and job.state == "waiting" and job.how == "auto" then
    db.last[job.realm] = job.prevLast
    job = nil
  end
  if not db.settings.autoBlocked then
    db.settings.autoBlocked = true
    tell("遊戲要你親手按「掃描全部」才給全部清單，之後打開拍賣場就不自動了；請按拍賣場下面的「掃描全部」。")
  end
  refresh()
end

-- ------------------------------------------------------------------ 瀏覽（點分類、搜尋、點進物品）
local function visit()
  local v = db.open
  if not v then
    local realm, faction, ah, zone, map = where()
    v = { kind = "browse", t = now(), realm = realm, faction = faction, ah = ah, zone = zone, map = map,
          keys = {}, search = {}, n = 0, ids = {} }
    db.open = v
  end
  v.last = now()
  return v
end

local function counted(v, id)
  if not v.ids[id] then
    v.ids[id] = true
    v.n = v.n + 1
  end
end

-- ItemKey → 「編號:物品等級:字尾」（同一件物品不同字尾分開算）；寵物不算
local function keyOf(k)
  if type(k) ~= "table" or hidden(k) then return end
  local id = k.itemID
  if not (num(id) and id > 0) or (num(k.battlePetSpeciesID) and k.battlePetSpeciesID ~= 0) then return end
  return id .. ":" .. (num(k.itemLevel) and k.itemLevel or 0) .. ":" .. (num(k.itemSuffix) and k.itemSuffix or 0), id
end

local function onBrowse()
  if not ahOpen then return end
  local results = C_AuctionHouse.GetBrowseResults()
  if type(results) ~= "table" or hidden(results) then return end
  for _, r in ipairs(results) do
    local key, id
    if type(r) == "table" then key, id = keyOf(r.itemKey) end
    if key and num(r.totalQuantity) and num(r.minPrice) and r.totalQuantity > 0 then
      local v = visit()
      v.keys[key] = { id = id, q = r.totalQuantity, min = r.minPrice > 0 and r.minPrice or nil }
      counted(v, id)
    end
  end
  refresh()
end

-- 點進物品看到的全部拍賣。商品（疊起來賣的）一次就是這個編號的全部；裝備這類一件一件賣的，是同一個物品等級、字尾的全部
local function remember(id, key, list, whole)
  local v = visit()
  v.search[id] = { key = key, whole = whole or nil, list = list }
  counted(v, id)
  refresh()
end

local function onCommodity(id)
  if not ahOpen or not num(id) or not C_AuctionHouse.HasFullCommoditySearchResults(id) then return end
  local list = {}
  for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(id) do
    local r = C_AuctionHouse.GetCommoditySearchResultInfo(id, i)
    if type(r) == "table" and num(r.quantity) and num(r.unitPrice) and r.quantity > 0 then
      list[#list + 1] = { r.unitPrice > 0 and r.unitPrice or nil, r.quantity }
    end
  end
  if #list > 0 then remember(id, nil, list, true) end
end

local function onItems(itemKey)
  if not ahOpen then return end
  local key, id = keyOf(itemKey)
  if not key or not C_AuctionHouse.HasFullItemSearchResults(itemKey) then return end
  local list = {}
  for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
    local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
    if type(r) == "table" and num(r.quantity) and r.quantity > 0 then
      local buyout = num(r.buyoutAmount) and r.buyoutAmount > 0 and r.buyoutAmount or nil
      list[#list + 1] = { buyout and unit(buyout, r.quantity) or nil, r.quantity }
    end
  end
  if #list > 0 then remember(id, key, list, false) end
end

-- 關掉拍賣場（或登出、/reload 之後）：這次看到的整理成一筆「瀏覽」。
-- 每件物品：分類清單的總數量和最低價；點進去看過全部拍賣、而且那就是這件物品的全部（商品，或只有一種物品等級）時，用那份算筆數和中位數
local function closeVisit()
  local v = db.open
  db.open = nil
  if not v or not v.n or v.n == 0 then return end
  local browse = {}
  for key, e in pairs(v.keys) do
    local b = browse[e.id]
    if not b then
      b = { q = 0, keys = {} }
      browse[e.id] = b
    end
    b.q = b.q + e.q
    if e.min and (not b.min or e.min < b.min) then b.min = e.min end
    b.keys[#b.keys + 1] = key
  end
  local per, searched = {}, 0
  for id in pairs(v.ids) do
    local b, s = browse[id], v.search[id]
    if s and (s.whole or not b or #b.keys <= 1) then
      local q, n, min, med, p10, p25, p75 = summarize(s.list)
      per[id] = { q = q, n = n, min = min, med = med, p10 = p10, p25 = p25, p75 = p75 }
      searched = searched + 1
    elseif b then
      per[id] = { q = b.q, min = b.min }
    end
  end
  local rec = { kind = "browse", t = v.t, last = v.last, realm = v.realm, faction = v.faction, ah = v.ah, zone = v.zone,
                map = v.map, searched = searched }
  rec.data, rec.items = encode(per)
  if rec.items > 0 then addScan(rec) end
end

-- ------------------------------------------------------------------ 指令與事件
local function status()
  local full, browse = 0, 0
  for _, s in ipairs(db.scans) do
    if s.kind == "full" then full = full + 1 else browse = browse + 1 end
  end
  tell(("存檔裡有 %d 次全掃描、%d 次瀏覽記錄（最多留 %d 天）。"):format(full, browse, KEEP_DAYS))
  local s = lastFull()
  if s then
    tell(("最近一次全掃描：%s‧%s%s‧%s，%s 筆拍賣、%s 種物品%s。"):format(s.realm, FACTION_ZH[s.faction] or s.faction or "?",
      s.ah == "neutral" and "（中立拍賣場）" or "", date("%m/%d %H:%M", s.t), commas(s.auctions or 0), commas(s.items or 0),
      s.partial and "（沒讀完）" or ""))
  end
  if job then tell(job.state == "waiting" and "正在等伺服器傳清單。" or ("正在讀：%s／%s 筆。"):format(commas(job.i), commas(job.n))) end
  local left = cooldownLeft()
  if left > 0 and not job then tell(("下一次全掃描：%s 後。"):format(clock(left))) end
  if db.settings.quiet then tell("目前掃完不會在聊天框說，但照樣會記（/amobiah loud 恢復）。") end
  if db.settings.auto == false then
    tell("打開拍賣場不會自動掃描（/amobiah auto on 打開）。")
  elseif db.settings.autoBlocked then
    tell("遊戲要你親手按「掃描全部」才給清單，所以不自動掃描了（/amobiah auto on 再試一次）。")
  else
    tell("打開拍賣場會自動掃描全部（15 分鐘最多一次）。")
  end
  if db.stats.errors > 0 then
    tell(("插件出過 %d 次錯：%s。請告訴阿莫比。"):format(db.stats.errors, db.stats.lastError or "?"))
  end
end

local function init()
  AmobiAuctionDB = type(AmobiAuctionDB) == "table" and AmobiAuctionDB or {}
  db = AmobiAuctionDB
  db.version = 1
  for _, key in ipairs({ "scans", "last", "settings", "stats" }) do
    if type(db[key]) ~= "table" then db[key] = {} end
  end
  for _, key in ipairs({ "hidden", "errors", "timeouts", "empty", "asked" }) do
    db.stats[key] = db.stats[key] or 0
  end
  local version, build, _, interface = GetBuildInfo()
  local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  db.client = { version = version, build = build, interface = interface, locale = GetLocale(),
                addon = meta and meta(ADDON, "Version") or nil }
  if type(db.open) == "table" then safely(closeVisit) end   -- 上次拍賣場還開著就 /reload、斷線：整理成一筆
  db.open = nil
end

local function hello()
  if #db.scans == 0 then
    say("已載入：打開拍賣場就會自動掃描全部（15 分鐘一次），視窗下面也有「掃描全部」。平常點分類、點物品也會順便記下價格。/amobiah 看記了多少。")
  else
    say(("已載入：存檔裡有 %d 次掃描。/amobiah 看記了多少。"):format(#db.scans))
  end
end

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    frame:UnregisterEvent("ADDON_LOADED")
    init()
    for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_LOGOUT", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
                         "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED",
                         "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
                         "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "COMMODITY_SEARCH_RESULTS_UPDATED",
                         "COMMODITY_SEARCH_RESULTS_ADDED", "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED" }) do
      frame:RegisterEvent(e)
    end
  elseif not db then
    return
  elseif event == "AUCTION_HOUSE_SHOW" then
    ahOpen = true
    safely(showPanel)
    C_Timer.After(AUTO_DELAY, function() safely(autoScan) end)
  elseif event == "AUCTION_HOUSE_CLOSED" then
    ahOpen = false
    if panel then panel:Hide() end
    safely(closeVisit)
  elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
    safely(onReplicate)
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
    safely(onBrowse)
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
    safely(onCommodity, (...))
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
    safely(onItems, (...))
  elseif event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
    safely(onForbidden, ...)
  elseif event == "PLAYER_LOGIN" then
    safely(hello)
  elseif event == "PLAYER_LOGOUT" then
    safely(closeVisit)
    if job and job.state == "reading" then safely(finishFull, job, true) end   -- 讀到一半就登出：讀到的先存
  end
end)
frame:RegisterEvent("ADDON_LOADED")

SLASH_AMOBIAH1, SLASH_AMOBIAH2 = "/amobiah", "/amah"
SlashCmdList.AMOBIAH = function(msg)
  if not db then return end
  msg = strtrim(msg or ""):lower()
  if msg == "scan" then
    safely(startFull, "slash")
  elseif msg == "auto off" then
    db.settings.auto = false
    tell("好，打開拍賣場不會自動掃描了，要掃請按「掃描全部」。/amobiah auto on 恢復。")
  elseif msg == "auto on" or msg == "auto" then
    db.settings.auto, db.settings.autoBlocked = true, nil
    tell("好，打開拍賣場會自動掃描全部（15 分鐘最多一次）。")
  elseif msg == "quiet" then
    db.settings.quiet = true
    tell("好，之後掃完不在聊天框說（還是照樣記）。/amobiah loud 恢復。")
  elseif msg == "loud" then
    db.settings.quiet = false
    tell("好，掃完會在聊天框說一聲。")
  elseif msg == "help" then
    tell("/amobiah 看記了多少；/amobiah scan 掃描全部（要先打開拍賣場，15 分鐘一次）；/amobiah auto off／on 打開拍賣場要不要自動掃描；/amobiah quiet 掃完不在聊天框說；/amobiah loud 恢復。")
  else
    status()
  end
end

