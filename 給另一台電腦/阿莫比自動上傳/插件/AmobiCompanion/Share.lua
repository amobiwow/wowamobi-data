-- 阿莫比小幫手：分享資料給阿莫比（1.6.0，「分享資料」分頁；老闆 10/25：「透過隱形頻道傳給我」，預設開、寫清楚）
--
-- 把 Market.lua 記的拍賣場物價、Drops.lua 記的首領掉落，用插件訊息（玩家看不到的隱形頻道）傳給阿莫比站長的角色，
-- 站長的電腦登出後自動上傳到 wowamobi.com（物品頁價格走勢、掉落率）。
--   * 只在公會裡傳：插件訊息只送得到同一個公會、同一隊的人。站長的角色裝「阿莫比公會名單」插件（AmobiGuild），
--     在線時會在公會頻道說一聲（"C"）；這邊有東西要傳時也會在公會頻道問一聲（"P"），站長回答後才開始傳。
--     站長不在線就先存著，下次看到站長在線再傳。
--   * 用密語的插件訊息一則一則傳給站長（每則最多 255 字），一秒最多一則（伺服器的限速：每個前綴先給 10 則、之後每秒 1 則）；
--     站長收齊一筆會回「收到」（"A"），沒回就之後再傳一次。戰鬥中、首領戰中不傳（遊戲會擋）。
--   * 拍賣場、首領掉落傳的只有：伺服器名稱、陣營、物品編號、數量、價格；首領、副本、難度、人數、時間、掉落物品，沒有玩家的名字。
--     站長的角色名只在這次登入時記在記憶體裡，不存進存檔。
--   * 分頁裡可以關掉；關掉就不記也不傳。
--   * 1.7.0 榮譽擊殺（PvP.lua，老闆 10/26，只針對阿莫比所在的亞服 PvP 規則伺服器，1.7.2 起聯盟、部落都收）：不用在公會裡——有記到的擊殺時，
--     直接用密語的插件訊息問 PvP.lua 寫好的、自己陣營的站長角色名（"P"），站長的 AmobiGuild 回「我在」（"C"）就開始傳
--     （只認剛問過、同伺服器的那幾個名字；這樣問到的只傳榮譽擊殺，拍賣場、首領掉落還是只在公會裡傳）；
--     站長不在線時遊戲會說「未找到名為…的線上玩家」，這幾秒內的這種系統訊息用聊天框的過濾器擋掉（遊戲用 securecallfunction
--     呼叫過濾器，不會污染聊天框），最多 10 分鐘問一次。這一筆有對方（敵對陣營玩家）的名字；回報的人是密語的寄件人。
-- 插件訊息格式（前綴 AMOBI）：P＝問站長在不在（公會，或直接密語）；C＝站長在（公會或密語）；CW＝站長在、你不在站長的公會
-- （直接密語問的回答，只傳榮譽擊殺）；D<編號>,<第幾則>,<共幾則>;<內容>＝資料（密語給站長）；
-- A<編號>＝站長收齊了（密語）。一筆資料的內容：
--   拍賣場 M1^伺服器^陣營^faction/neutral^full^開始時間^讀完時間^拍賣筆數^物品數^物品資料（Market.lua 的 36 進位格式）
--   首領   K1^伺服器^首領^地圖^難度^人數^時間^副本分身^有沒有打開屍體(1/0)^物品:數量,物品:數量（36 進位）
--   擊殺   H2^伺服器^職業^公會^時間:地圖:副本地圖:區域:對方名字:軍銜:榮譽:隊伍人數:等級,…（數字 36 進位；一筆最多 PVP_BATCH 次；
--          1.7.1 起，1.7.0 是 H1^伺服器^時間:地圖:副本地圖:對方名字:軍銜:榮譽:隊伍人數）

local _, ns = ...
local S = {}
ns.Share = S

local PREFIX = "AMOBI"
local TICK = 1.05            -- 秒：一則一則送，比伺服器每秒回 1 則慢一點
local PING_EVERY = 15 * 60   -- 秒：有東西要傳（或很久沒看到站長）時，最多 15 分鐘問一次
local SEEN_DAYS = 14         -- 14 天內看過站長在線，才記拍賣場、首領掉落（不在阿莫比公會就不白做）
local ACK_WAIT = 90          -- 秒：最後一則送出後這麼久沒收到「收到」，之後再傳一次
local MAX_TRIES = 3          -- 這次登入同一筆最多試幾次
local MAX_INFLIGHT = 3       -- 最多幾筆送完在等「收到」
local CHUNK = 220            -- 每則的資料長度（加上前面的編號不超過 255）
local KILL_SETTLE = 10 * 60  -- 秒：擊殺 10 分鐘後才傳（屍體、擲骰的東西記得比較齊；之後又多記到的會再傳一次）
local MARKET_DAYS = 3        -- 只傳 3 天內的拍賣場掃描；每天每個拍賣場最多傳一次
local PVP_BATCH = 15         -- 一筆最多幾次榮譽擊殺（約 4 則）
local DIRECT_EVERY = 10 * 60 -- 秒：有擊殺要傳、站長不在線時，最多 10 分鐘直接密語問一次
local NOT_FOUND_WINDOW = 10  -- 秒：問完這麼久內的「未找到名為…的線上玩家」是自己問出來的，擋掉

local db
local collector              -- 站長的角色名（只放記憶體）
local viaGuild = false       -- 站長是在公會裡回答的（拍賣場、首領掉落只在公會裡傳；直接密語問到的只傳榮譽擊殺）
local queue, current, inflight = {}, nil, {}
local ticker, lastPing, lastDirect, pausedUntil = nil, -1e9, -1e9, 0
local pingedAt = {}          -- [站長角色名] = 上次直接密語問的時間（擋「找不到玩家」用）
local tries = {}
local known = {}             -- [編號] = 這次登入排過的資料（站長的「收到」晚到也找得到）

local function now() return GetServerTime and GetServerTime() or time() end
local function on() return ns.db.settings.share ~= false end           -- 拍賣場、首領掉落
local function pvpOn() return ns.PvP ~= nil and ns.PvP.On() end           -- 榮譽擊殺
local function anyOn() return on() or pvpOn() end
local function chatOK() return type(C_ChatInfo) == "table" and type(C_ChatInfo.SendAddonMessage) == "function" end

-- 站長自己的電腦（裝了 AmobiGuild）：它就是收的那一端，這邊不用傳
local function isCollector() return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("AmobiGuild") end

-- 一筆資料的編號（站長那邊用同一個算法核對有沒有收齊、有沒有傳錯）
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
function S.Hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
  local out = ""
  repeat
    local r = h % 36
    out = DIGITS:sub(r + 1, r + 1) .. out
    h = (h - r) / 36
  until h == 0
  return out
end

-- 拆成好幾則：不在中文字（UTF-8 的多位元組）中間切開
function S.Split(body, size)
  local parts, i, n = {}, 1, #body
  while i <= n do
    local j = math.min(n, i + size - 1)
    while j < n and j > i do
      local b = body:byte(j + 1)
      if b < 0x80 or b >= 0xC0 then break end   -- 下一個位元組是一個字的開頭：可以在這裡切
      j = j - 1
    end
    parts[#parts + 1] = body:sub(i, j)
    i = j + 1
  end
  return parts
end

function S.Reachable()
  if not on() or isCollector() or not (IsInGuild and IsInGuild()) then return false end
  return db and db.seenAt and now() - db.seenAt < SEEN_DAYS * 86400 or false
end

local function twDay(t) return math.floor((t + 8 * 3600) / 86400) end

-- 要傳的：榮譽擊殺、拍賣場（每天每個拍賣場最新的一次完整全掃描）、首領擊殺（10 分鐘前的；內容變了會再傳）
-- pvpOnly：站長是直接密語問到的（不是在公會裡），只傳榮譽擊殺
local function build(busy, pvpOnly)
  local list, done = {}, {}
  if pvpOn() then
    local byGroup, groups = {}, {}                     -- 同伺服器、同職業、同公會的一起傳
    for _, k in ipairs(ns.PvP.Unsent()) do
      if not (busy and busy[k]) then
        local g = ns.PvP.Group(k)
        if not byGroup[g] then byGroup[g] = {}; groups[#groups + 1] = g end
        table.insert(byGroup[g], k)
      end
    end
    for _, g in ipairs(groups) do
      local ks = byGroup[g]
      for i = 1, #ks, PVP_BATCH do
        local part = {}
        for j = i, math.min(#ks, i + PVP_BATCH - 1) do part[#part + 1] = ks[j] end
        local body = ns.PvP.Body(part)
        list[#list + 1] = { id = S.Hash(body), body = body, kills = part }
      end
    end
  end
  if not on() or pvpOnly then return list end
  for _, s in ipairs(ns.Market and ns.Market.Scans() or {}) do
    if s.kind == "full" and s.sent then done[s.realm .. "|" .. s.ah .. "|" .. twDay(s.t)] = true end
  end
  local best = {}
  for _, s in ipairs(ns.Market and ns.Market.Scans() or {}) do
    local key = s.realm .. "|" .. tostring(s.ah) .. "|" .. twDay(s.t)
    if s.kind == "full" and s.data and not s.partial and not s.sent and not done[key] and now() - s.t < MARKET_DAYS * 86400 then
      if not best[key] or s.t > best[key].t then best[key] = s end
    end
  end
  local drops = ns.Drops
  local src = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("AmobiLoot") and type(AmobiLootDB) == "table") and AmobiLootDB or nil
  for _, k in ipairs(drops and drops.Summaries(src) or {}) do
    if now() - k.t >= KILL_SETTLE then
      local ids = {}
      for id in pairs(k.items) do ids[#ids + 1] = id end
      table.sort(ids)
      local items = {}
      for _, id in ipairs(ids) do items[#items + 1] = ns.Market.B36(id) .. ":" .. ns.Market.B36(k.items[id]) end
      local body = table.concat({ "K1", k.realm, k.enc, k.map or "", k.diff or "", k.size or "", k.t, k.copy or "",
                                  k.full and 1 or 0, table.concat(items, ",") }, "^")
      local id = S.Hash(body)
      if not db.sent[id] then list[#list + 1] = { id = id, body = body } end
    end
  end
  for _, s in pairs(best) do
    local body = table.concat({ "M1", s.realm, s.faction or "", s.ah or "faction", "full", s.t, s.done or s.t, s.auctions or 0,
                                s.items or 0, s.data }, "^")
    local id = S.Hash(body)
    if db.sent[id] then ns.Market.MarkSent(s) else list[#list + 1] = { id = id, body = body, scan = s } end
  end
  return list
end

local function send(msg, kind, target)
  if not chatOK() then return 9 end
  local ok, r = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, kind, target)
  if not ok then return 9 end
  if r == nil or r == true then return 0 end
  return type(r) == "number" and not ns.Secret(r) and r or 9
end

local function stop()
  if ticker then ticker:Cancel(); ticker = nil end
end

local function pending()
  local n = #queue + (current and 1 or 0)
  for _ in pairs(inflight) do n = n + 1 end
  return n
end

local tick
local function start()
  if ticker or not collector then return end
  ticker = C_Timer.NewTicker(TICK, function() ns.Try("share:tick", tick) end)
end

tick = function()
  if not anyOn() or not collector then return stop() end
  if ns.Restricted() or GetTime() < pausedUntil then return end
  -- 送完沒收到「收到」的：之後再試一次
  for id, f in pairs(inflight) do
    if GetTime() - f.at > ACK_WAIT then
      inflight[id] = nil
      tries[id] = (tries[id] or 0) + 1
      if tries[id] < MAX_TRIES then table.insert(queue, f.item) end
    end
  end
  if not current then
    local n = 0
    for _ in pairs(inflight) do n = n + 1 end
    if n >= MAX_INFLIGHT then return end
    local item = table.remove(queue, 1)
    if not item then
      if n == 0 then stop() end
      return
    end
    current = { item = item, parts = S.Split(item.body, CHUNK), i = 1 }
  end
  local c = current
  local r = send("D" .. c.item.id .. "," .. c.i .. "," .. #c.parts .. ";" .. c.parts[c.i], "WHISPER", collector)
  if r == 0 then
    db.stats.bytes = (db.stats.bytes or 0) + #c.parts[c.i]
    c.i = c.i + 1
    if c.i > #c.parts then
      inflight[c.item.id] = { at = GetTime(), item = c.item }
      current = nil
    end
  elseif r == 3 or r == 8 then        -- 太快了（AddonMessageThrottle、ChannelThrottle）：等一下
    pausedUntil = GetTime() + 3
  elseif r == 11 then                 -- 遊戲限制中（AddOnMessageLockdown）
    pausedUntil = GetTime() + 15
  else                                -- 站長下線了（TargetOffline）或其他錯誤：先停，下次看到站長再傳
    if current then table.insert(queue, 1, current.item) end
    current = nil
    collector, viaGuild = nil, false
    stop()
  end
  ns.UI.Refresh("share")
end

local function ping(force)
  if not on() or isCollector() or not chatOK() or not (IsInGuild and IsInGuild()) or ns.Restricted() then return end
  if not force and GetTime() - lastPing < PING_EVERY then return end
  lastPing = GetTime()
  send("P", "GUILD")
end

local function hasKills() return pvpOn() and #ns.PvP.Unsent() > 0 end

-- 榮譽擊殺：不管有沒有公會，直接密語問寫好的站長角色名在不在（最多 10 分鐘一次）
local function pingDirect(force)
  if not pvpOn() or isCollector() or not chatOK() or ns.Restricted() or collector then return end
  if not force and GetTime() - lastDirect < DIRECT_EVERY then return end
  lastDirect = GetTime()
  for _, name in ipairs(ns.PvP.Collectors()) do
    pingedAt[name] = GetTime()
    send("P", "WHISPER", name)
  end
end

-- 問站長問出來的「未找到名為「X」的線上玩家。」不要出現在聊天框（只擋問完 10 秒內、名字是站長角色名的那一句；
-- 只比第一段名字：後面有沒有「-伺服器」、次要名字都算）
local notFound
local function notFoundFilter(_, _, msg)
  if ns.Secret(msg) or type(msg) ~= "string" then return false end
  if not notFound then
    if type(ERR_CHAT_PLAYER_NOT_FOUND_S) ~= "string" then return false end
    notFound = ns.PvP.Pattern(ERR_CHAT_PLAYER_NOT_FOUND_S, { "name" })
  end
  local who = msg:match(notFound)
  if not who then return false end
  local at = pingedAt[ns.PvP.MainName(who) or ""]
  if at and GetTime() - at < NOT_FOUND_WINDOW then
    db.stats.hidden = (db.stats.hidden or 0) + 1
    return true
  end
  return false
end
S.NotFoundFilter = notFoundFilter

-- 有新的資料（掃完拍賣場、記到擊殺）：站長在線就排進去，不在就之後問
function S.Kick()
  if not anyOn() then return end
  C_Timer.After(KILL_SETTLE + 5, function() ns.Try("share:later", S.Kick2) end)   -- 擊殺要等 10 分鐘才傳
  S.Kick2()
end
function S.Kick2()
  if not anyOn() then return end
  if collector then
    local have, busy = {}, {}
    local function mark(it)
      have[it.id] = true
      for _, k in ipairs(it.kills or {}) do busy[k] = true end
    end
    for _, it in ipairs(queue) do mark(it) end
    if current then mark(current.item) end
    for _, f in pairs(inflight) do mark(f.item) end
    for _, it in ipairs(build(busy, not viaGuild)) do
      if not have[it.id] and (tries[it.id] or 0) < MAX_TRIES then
        known[it.id] = it
        queue[#queue + 1] = it
      end
    end
    if #queue > 0 then start() end
  else
    if hasKills() then pingDirect(false) end
    if on() and #build() > 0 then ping(false) end
  end
end

-- 記到一次榮譽擊殺（PvP.lua）：站長自己的電腦直接交給 AmobiGuild；其他人站長在線就排進去，不在就之後問
function S.KillAdded(k)
  if isCollector() then
    if type(AmobiGuild_Store) == "function" then
      local ok = pcall(AmobiGuild_Store, ns.PvP.Body({ k }))
      if ok then ns.PvP.MarkSent({ k }) end
    end
    return
  end
  if collector then S.Kick2() else pingDirect(false) end
end

local function heardCollector(name, guild)
  if type(name) ~= "string" or ns.Secret(name) or name == "" then return end
  if collector ~= name then viaGuild = false end
  collector = name
  if guild then
    viaGuild = true
    db.seenAt = now()                -- 「14 天內看過站長」只算公會裡的（拍賣場、首領掉落只在公會裡記）
  end
  S.Kick2()
  ns.UI.Refresh("share")
end

-- 直接密語問到的回答：是自己陣營寫好的站長角色名（比第一段）、剛問過、同一個伺服器（名字後面的「-伺服器」和自己的一樣）
local function directReply(sender)
  if not ns.PvP.IsCollectorName(sender) then return false end
  local realm = sender:match("%-(.*)$") or ""
  local at = pingedAt[ns.PvP.MainName(sender)]
  if not at or GetTime() - at > 120 then return false end
  local mine = GetNormalizedRealmName and GetNormalizedRealmName()
  if realm ~= "" and type(mine) == "string" and not ns.Secret(mine) and mine ~= "" and realm ~= mine then return false end
  return true
end

local function onMessage(prefix, text, channel, sender)
  if prefix ~= PREFIX or ns.Secret(text) or type(text) ~= "string" or isCollector() then return end
  if ns.Secret(sender) or type(sender) ~= "string" then return end
  if (text == "C" or text == "CW") and (channel == "GUILD" or channel == "WHISPER") then
    -- "C"：公會裡的站長（公會頻道說的、剛在公會問過的回答，或站長那邊查過你在公會名單上）；
    -- "CW"：你不在站長的公會，直接密語問到的：只傳榮譽擊殺
    local direct = channel == "WHISPER" and directReply(sender)
    local guild = text == "C" and (channel == "GUILD" or GetTime() - lastPing < 120 or direct)
    if anyOn() and (guild or direct) then heardCollector(sender, guild) end
  elseif text:sub(1, 1) == "A" and channel == "WHISPER" and sender == collector then
    local id = text:sub(2)
    local item = known[id]
    if not item or db.sent[id] then return end
    db.sent[id] = now()
    inflight[id] = nil
    for i = #queue, 1, -1 do if queue[i].id == id then table.remove(queue, i) end end   -- 收到了：排著要重傳的拿掉
    if current and current.item.id == id then current = nil end
    db.stats.records = (db.stats.records or 0) + 1
    db.stats.last = now()
    if item.scan then ns.Market.MarkSent(item.scan) end
    if item.kills then ns.PvP.MarkSent(item.kills) end
    ns.UI.Refresh("share")
  end
end

-- ------------------------------------------------------------------ 「分享資料」分頁
local function buildTab(page)
  local y = 0
  local function line(text, font, gap)
    local t = ns.UI.Text(page, font or "GameFontHighlightSmall", text, 420)
    t:SetPoint("TOPLEFT", 0, y)
    local h = t:GetStringHeight()
    y = y - (gap or ((type(h) == "number" and h or 28) + 8))
    return t
  end
  line(ns.GOLD .. "分享資料給阿莫比網站|r", "GameFontNormal", 24)
  page.check = ns.UI.Check(page, "把拍賣場物價、首領掉落傳給阿莫比網站（只在阿莫比的公會裡）",
    function() return on() end,
    function(v)
      ns.db.settings.share = v
      if not anyOn() then queue, current, inflight = {}, nil, {}; stop() else S.Kick2() end
      ns.UI.Refresh("share")
    end)
  page.check:SetPoint("TOPLEFT", -4, y)
  y = y - 30
  line("打開拍賣場時自動掃一次全部的物價（15 分鐘一次）、打完首領記下這場掉了什麼，" ..
       "等阿莫比站長在線時用玩家看不到的插件訊息傳過去，網站的物品頁就有價格走勢和掉落率。")
  line("這兩樣傳的只有物品、數量、價格、首領和副本，沒有任何玩家的名字。戰鬥中、打首領時不傳。" ..
       "只有在阿莫比的公會裡、14 天內看過站長在線才會記和傳；關掉就不記也不傳。")
  page.pvpCheck = ns.UI.Check(page, "把我拿到的榮譽擊殺傳給阿莫比（亞服 PvP 規則限定）",
    function() return pvpOn() end,
    function(v)
      ns.db.settings.pvpShare = v
      if not anyOn() then queue, current, inflight = {}, nil, {}; stop() else S.Kick2() end
      ns.UI.Refresh("share")
    end)
  page.pvpCheck:SetPoint("TOPLEFT", -4, y)
  y = y - 30
  line("這個功能只針對阿莫比所在的亞服 PvP 規則伺服器（聯盟、部落都收）：拿到榮譽擊殺時，記下對方（敵對陣營玩家）的名字、軍銜、榮譽、" ..
       "地圖和時間，連同你的角色名字、職業、等級、公會傳給阿莫比做排行（排行顯示真名）。不用在公會裡；站長不在線就先存著，之後再傳。")
  page.status = line("", "GameFontHighlight", 120)
end

local function refreshTab(page)
  if page.check then page.check:Refresh() end
  if page.pvpCheck then page.pvpCheck:Refresh() end
  local rows = {}
  if isCollector() then
    rows[#rows + 1] = "這台電腦裝了阿莫比公會名單插件：你就是收資料的站長，這裡不用傳（你自己的榮譽擊殺直接存進公會名單插件）。"
  else
    rows[#rows + 1] = collector and "|cff60ff60阿莫比站長在線|r，有新的資料會馬上傳。"
      or db.seenAt and ("上次看到阿莫比站長在線：" .. date("%m/%d %H:%M", db.seenAt) .. "。站長下次在線時再傳。")
      or "還沒看到阿莫比站長在線。"
    if not on() then
      rows[#rows + 1] = "拍賣場、首領掉落：已經關掉，不記也不傳。"
    elseif not (IsInGuild and IsInGuild()) then
      rows[#rows + 1] = "拍賣場、首領掉落：你不在公會裡，不記也不傳（插件訊息只送得到同一個公會）。"
    else
      rows[#rows + 1] = "拍賣場：" .. (ns.Market and ns.Market.Status() or "")
      rows[#rows + 1] = "首領掉落：" .. (ns.Drops and ns.Drops.Status() or "")
    end
    if not pvpOn() then
      rows[#rows + 1] = "榮譽擊殺：已經關掉，不記也不傳。"
    elseif #ns.PvP.Collectors() == 0 then
      rows[#rows + 1] = "榮譽擊殺：這個陣營不記（只記聯盟、部落）。"
    else
      rows[#rows + 1] = "榮譽擊殺：" .. ns.PvP.Status()
    end
    if current then
      rows[#rows + 1] = ("正在傳：第 %d／%d 則（一秒一則）"):format(current.i, #current.parts)
    end
    local waiting = pending()
    rows[#rows + 1] = ("已傳 %d 筆%s%s"):format(db.stats.records or 0,
      db.stats.last and ("，最近一次 " .. date("%m/%d %H:%M", db.stats.last)) or "",
      waiting > 0 and ("；還有 %d 筆等著傳"):format(waiting) or "")
  end
  page.status:SetText(table.concat(rows, "\n"))
end

function S.Status() return collector and "在線" or "不在線" end

function S.Init()
  ns.db.share = type(ns.db.share) == "table" and ns.db.share or {}
  db = ns.db.share
  db.sent = type(db.sent) == "table" and db.sent or {}
  db.stats = type(db.stats) == "table" and db.stats or {}
  local oldest = now() - 45 * 86400
  for id, t in pairs(db.sent) do
    if type(t) ~= "number" or t < oldest then db.sent[id] = nil end
  end
  if chatOK() and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
  ns.On("CHAT_MSG_ADDON", onMessage)
  ns.On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
    if isLogin or isReload then
      C_Timer.After(30, function()                       -- 登入後問一聲站長在不在
        ns.Try("share:hello", ping, true)
        if hasKills() then ns.Try("share:direct", pingDirect, true) end
      end)
    end
  end)
  ns.On("PLAYER_REGEN_ENABLED", function()               -- 打完：擊殺多半是戰鬥中記到的
    C_Timer.After(2, function() ns.Try("share:after", S.Kick2) end)
  end)
  C_Timer.NewTicker(PING_EVERY, function()
    ns.Try("share:ping", function()
      if collector then S.Kick2() elseif not db.seenAt or now() - db.seenAt > 86400 or #build() > 0 then ping(false) end
    end)
  end)
  C_Timer.NewTicker(60, function()                      -- 有擊殺沒傳出去：每分鐘看一次，pingDirect 自己限 10 分鐘問一次
    ns.Try("share:direct", function() if not collector and hasKills() then pingDirect(false) end end)
  end)
  -- 擋掉直接問站長時遊戲回的「未找到名為…的線上玩家」（聊天框的過濾器；遊戲用 securecallfunction 呼叫）
  local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
  if type(addFilter) == "function" then
    pcall(addFilter, "CHAT_MSG_SYSTEM", function(...)
      local ok, hide = pcall(notFoundFilter, ...)
      return ok and hide or false
    end)
  end
  ns.UI.AddTab("share", "分享資料", buildTab, refreshTab)
end

ns.Register(S)
