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
--   * 1.24.1（老闆 11/8：「找不到我就找不到，你不能這樣子一直洗大家，因為我們難免會斷線的」）：站長斷線後，大家的小幫手還在
--     一秒一則傳資料，每一則都跳一次「未找到」。改成：小幫手 30 秒內密過的名字的「未找到」都擋掉；一找不到站長、或公會說站長下線了，
--     馬上停、正在傳的放掉，30 分鐘內不再直接密語問（公會裡的人等站長上線在公會頻道說一聲就再傳）。
--   * 1.11.0 物品來源（Sources.lua，老闆 10/27「一起做」；1.16.0 加訓練師）：商人賣什麼、任務給什麼、怪物和寶箱掉什麼、訓練師教什麼、在哪裡，和榮譽擊殺一樣
--     不用在公會裡，直接密語問站長（站長回 "C" 或 "CW" 都傳）。只有 NPC 的名字，沒有玩家的名字。
--   * 1.18.0 看到的玩家（Seen.lua，老闆 11/8「不可能永遠都靠我」）：身邊看到的同陣營玩家的名字、等級、職業、種族、公會、區域，
--     和物品來源一樣不用在公會裡、直接密語問站長；站長的 AmobiGuild 併進人口普查。
--   * 1.21.0 PvP 戰績（Honor.lua，老闆 11/8「不可能全部人都裝我的UI…有其他辦法嗎」）：用「觀察」查身邊玩家（兩個陣營）的
--     總榮譽擊殺、今天的榮譽擊殺、軍銜，包成 R1 放進看到的玩家的 outbox 一起傳（同一個開關 seenShare）。
--   * 1.24.3 拍賣場、首領掉落也不用在公會裡（老闆 11/9：公會外的拍賣場和首領掉落「也要收」；部落沒有阿莫比的公會，網站一直沒有部落的物價、掉落）：
--     直接密語問到站長（回 "CW"）也全部傳；「14 天內看過站長」改成公會裡、直接密語都算（Reachable 不再要求在公會裡）；
--     只有拍賣場、首領掉落要傳的人也會直接密語問站長。站長那邊要 AmobiGuild 1.6.2 起才收公會外的拍賣場、首領掉落。
-- 插件訊息格式（前綴 AMOBI）：P＝問站長在不在（公會，或直接密語）；C＝站長在（公會或密語）；CW＝站長在、你不在站長的公會
-- （直接密語問的回答，只傳榮譽擊殺和物品來源）；D<編號>,<第幾則>,<共幾則>;<內容>＝資料（密語給站長）；
-- A<編號>＝站長收齊了（密語）。一筆資料的內容：
--   拍賣場 M1^伺服器^陣營^faction/neutral^full^開始時間^讀完時間^拍賣筆數^物品數^物品資料（Market.lua 的 36 進位格式）
--   首領   K1^伺服器^首領^地圖^難度^人數^時間^副本分身^有沒有打開屍體(1/0)^物品:數量,物品:數量（36 進位）
--   擊殺   H2^伺服器^職業^公會^時間:地圖:副本地圖:區域:對方名字:軍銜:榮譽:隊伍人數:等級,…（數字 36 進位；一筆最多 PVP_BATCH 次；
--          1.7.1 起，1.7.0 是 H1^伺服器^時間:地圖:副本地圖:對方名字:軍銜:榮譽:隊伍人數）
--   來源   S1^伺服器^陣營^一項~一項~…（商人、任務、怪物、寶箱；格式寫在 Sources.lua 最上面）
--   玩家   W1^伺服器^陣營^一個人~一個人~…（格式寫在 Seen.lua 最上面）
--   戰績   R1^伺服器^陣營^一個人~一個人~…（格式寫在 Honor.lua 最上面）

local _, ns = ...
local S = {}
ns.Share = S

local PREFIX = "AMOBI"
local TICK = 1.05            -- 秒：一則一則送，比伺服器每秒回 1 則慢一點
local PING_EVERY = 15 * 60   -- 秒：有東西要傳（或很久沒看到站長）時，最多 15 分鐘問一次
local SEEN_DAYS = 14         -- 14 天內聯絡上過站長（公會裡或直接密語），才記拍賣場、首領掉落（找不到站長就不白做）
local ACK_WAIT = 90          -- 秒：最後一則送出後這麼久沒收到「收到」，之後再傳一次
local MAX_TRIES = 3          -- 這次登入同一筆最多試幾次
local MAX_INFLIGHT = 3       -- 最多幾筆送完在等「收到」
local CHUNK = 220            -- 每則的資料長度（加上前面的編號不超過 255）
local KILL_SETTLE = 10 * 60  -- 秒：擊殺 10 分鐘後才傳（屍體、擲骰的東西記得比較齊；之後又多記到的會再傳一次）
local MARKET_DAYS = 3        -- 只傳 3 天內的拍賣場掃描；每天每個拍賣場最多傳一次
local PVP_BATCH = 15         -- 一筆最多幾次榮譽擊殺（約 4 則）
local DIRECT_EVERY = 10 * 60 -- 秒：有擊殺要傳、站長不在線時，最多 10 分鐘直接密語問一次
local NOT_FOUND_WINDOW = 30  -- 秒：密完（問站長、傳資料）這麼久內的「未找到名為…的線上玩家」是自己密出來的，擋掉
local GONE_WAIT = 30 * 60    -- 秒：找不到站長（斷線、下線）後這麼久內不再直接密語問（1.24.1，老闆 11/8：「找不到我就找不到，
                             -- 你不能這樣子一直洗大家，因為我們難免會斷線的」）；公會裡的人等站長上線在公會頻道說一聲就會再傳

local db
local collector              -- 站長的角色名（只放記憶體）
local viaGuild = false       -- 站長是在公會裡回答的（1.24.3 起傳的東西一樣；只差「站長下線」要靠密語找不到還是公會說下線）
local queue, current, inflight = {}, nil, {}
local ticker, lastPing, lastDirect, pausedUntil = nil, -1e9, -1e9, 0
local quietUntil = 0         -- 找不到站長後，這個時間前不直接密語問（GONE_WAIT）
local pingedAt = {}          -- [站長角色名] = 上次直接密語問的時間（認回答用）
local whisperedAt = {}       -- [全名（去掉「-伺服器」）] = 上次密語（問站長、傳資料）的時間（擋「找不到玩家」、認出站長不在用）
local tries = {}
local known = {}             -- [編號] = 這次登入排過的資料（站長的「收到」晚到也找得到）

local function now() return GetServerTime and GetServerTime() or time() end
local function on() return ns.db.settings.share ~= false end           -- 拍賣場、首領掉落
local function pvpOn() return ns.PvP ~= nil and ns.PvP.On() end           -- 榮譽擊殺
local function srcOn() return ns.Sources ~= nil and ns.Sources.Active() end -- 物品來源
local function seenOn() return ns.Seen ~= nil and ns.Seen.Active() end     -- 看到的玩家（人口普查）
local function anyOn() return on() or pvpOn() or srcOn() or seenOn() end
local function directOn() return anyOn() end                               -- 1.24.3 起每一樣都可以直接密語問站長（不用在公會裡）
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
  if not on() or isCollector() then return false end   -- 1.24.3 起不用在公會裡
  return db and db.seenAt and now() - db.seenAt < SEEN_DAYS * 86400 or false
end

local function twDay(t) return math.floor((t + 8 * 3600) / 86400) end

-- 要傳的：榮譽擊殺、物品來源、拍賣場（每天每個拍賣場最新的一次完整全掃描）、首領擊殺（10 分鐘前的；內容變了會再傳）
-- 1.24.3 起站長是直接密語問到的（不在公會裡）也全部傳，不再分
local function build(busy)
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
  if srcOn() then
    for _, o in ipairs(ns.Sources.Outbox()) do
      if db.sent[o.id] then ns.Sources.MarkSent(o) else list[#list + 1] = { id = o.id, body = o.body, src = o } end
    end
  end
  if seenOn() then
    for _, o in ipairs(ns.Seen.Outbox()) do
      if db.sent[o.id] then ns.Seen.MarkSent(o) else list[#list + 1] = { id = o.id, body = o.body, seen = o } end
    end
  end
  if not on() then return list end
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
  if kind == "WHISPER" then
    local full = ns.PvP.FullName(target)
    if full then whisperedAt[full] = GetTime() end
  end
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

-- 有東西要傳（1.24.3 起每一樣都不用在公會裡：榮譽擊殺、物品來源、看到的玩家、拍賣場、首領掉落）
local function hasKills()
  return #build() > 0
end

-- 不管有沒有公會，直接密語問寫好的站長角色名在不在（最多 10 分鐘一次）
local function pingDirect(force)
  if not directOn() or isCollector() or not chatOK() or ns.Restricted() or collector then return end
  if GetTime() < quietUntil then return end                       -- 剛找不到站長：登入時的強制問一次也不問（1.24.3）
  if not force and GetTime() - lastDirect < DIRECT_EVERY then return end
  lastDirect = GetTime()
  for _, name in ipairs(ns.PvP.Collectors()) do
    pingedAt[name] = GetTime()
    send("P", "WHISPER", name)
  end
end

-- 小幫手密出來的「未找到名為「X」的線上玩家。」：是誰（全名，去掉「-伺服器」）；不是這句、或不是小幫手 30 秒內密過的名字就是 nil
-- （1.24.1 前只認「問站長在不在」那一句：站長斷線後還在傳資料的那幾則每一則都跳一次，洗了大家的聊天框）
local notFound
local function ourNotFound(msg)
  if ns.Secret(msg) or type(msg) ~= "string" then return nil end
  if not notFound then
    if type(ERR_CHAT_PLAYER_NOT_FOUND_S) ~= "string" then return nil end
    notFound = ns.PvP.Pattern(ERR_CHAT_PLAYER_NOT_FOUND_S, { "name" })
  end
  local full = ns.PvP.FullName(msg:match(notFound))
  local at = full and whisperedAt[full]
  if at and GetTime() - at < NOT_FOUND_WINDOW then return full end
  return nil
end

-- 聊天框的過濾器：小幫手密出來的那一句不要出現在聊天框（其他照常顯示）。每個聊天框都會叫一次，這裡只判斷、不改狀態
local function notFoundFilter(_, _, msg)
  return ourNotFound(msg) ~= nil
end
S.NotFoundFilter = notFoundFilter

-- 站長不在了（密語找不到、公會說他下線了）：馬上停，不再一則一則傳；正在傳、等「收到」的都放掉（資料都還在存檔裡，
-- 下次聽到站長在線時 Kick2 重新排）；之後 30 分鐘內不直接密語問（老闆 11/8：「找不到我就找不到」）
local function collectorGone(full)
  if not full then return end
  local was = collector and ns.PvP.FullName(collector)
  if was ~= full and not ns.PvP.CollectorFor(full) then return end
  if was == full then
    collector, viaGuild = nil, false
    queue, current, inflight = {}, nil, {}
    stop()
  end
  quietUntil = GetTime() + GONE_WAIT
  db.stats.gone = (db.stats.gone or 0) + 1
  ns.UI.Refresh("share")
end

-- 系統訊息（一則只來一次）：小幫手密出來的「未找到…」、公會成員「X下線了。」（ERR_FRIEND_OFFLINE_S，斷線也會有）
local offline
local function onSystem(msg)
  if ns.Secret(msg) or type(msg) ~= "string" then return end
  local who = ourNotFound(msg)
  if who then
    db.stats.hidden = (db.stats.hidden or 0) + 1
    return collectorGone(who)
  end
  if not offline then
    if type(ERR_FRIEND_OFFLINE_S) ~= "string" then return end
    offline = ns.PvP.Pattern(ERR_FRIEND_OFFLINE_S, { "name" })
  end
  local name = msg:match(offline)
  if name then collectorGone(ns.PvP.FullName((name:gsub("|H.-|h", ""):gsub("|h", ""):gsub("[%[%]]", "")))) end
end
S.OnSystem = onSystem

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
    for _, it in ipairs(build(busy)) do
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
  if guild then viaGuild = true end
  db.seenAt = now()                  -- 「14 天內聯絡上過站長」才記拍賣場、首領掉落（1.24.3 起直接密語問到的也算）
  S.Kick2()
  ns.UI.Refresh("share")
end

-- 直接密語問到的回答：是自己陣營寫好的站長角色（全名「大名 次名」）、剛問過、同一個伺服器（名字後面的「-伺服器」和自己的一樣）
local function directReply(sender)
  local c = ns.PvP.CollectorFor(sender)
  if not c then return false end
  local realm = sender:match("%-([^%s%-]*)$") or ""
  local at = pingedAt[c]
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
    if item.src then ns.Sources.MarkSent(item.src) end
    if item.seen then ns.Seen.MarkSent(item.seen) end
    ns.UI.Refresh("share")
  end
end

-- 分享資料的開關（分頁的勾、功能總覽都叫這個）：share 拍賣場和首領掉落、pvpShare 榮譽擊殺、srcShare 物品來源、seenShare 看到的玩家
function S.SetShare(key, v)
  ns.db.settings[key] = v and true or false
  if not anyOn() then queue, current, inflight = {}, nil, {}; stop() else S.Kick2() end
  ns.UI.Refresh("share")
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
  page.check = ns.UI.Check(page, "把拍賣場物價、首領掉落傳給阿莫比網站",
    function() return on() end,
    function(v)
      S.SetShare("share", v)
    end)
  page.check:SetPoint("TOPLEFT", -4, y)
  y = y - 30
  line("打開拍賣場時自動掃一次全部的物價（15 分鐘一次）、打完首領記下這場掉了什麼，" ..
       "等阿莫比站長在線時用玩家看不到的插件訊息傳過去，網站的物品頁就有價格走勢和掉落率。")
  line("這兩樣傳的只有物品、數量、價格、首領和副本，沒有任何玩家的名字。戰鬥中、打首領時不傳。" ..
       "不用在公會裡；14 天內聯絡上過阿莫比站長才會記，站長不在線就先存著；關掉就不記也不傳。")
  page.pvpCheck = ns.UI.Check(page, "把我拿到的榮譽擊殺傳給阿莫比（亞服 PvP 規則限定）",
    function() return pvpOn() end,
    function(v)
      S.SetShare("pvpShare", v)
    end)
  page.pvpCheck:SetPoint("TOPLEFT", -4, y)
  y = y - 30
  line("這個功能只針對阿莫比所在的亞服 PvP 規則伺服器（聯盟、部落都收）：拿到榮譽擊殺時，記下對方（敵對陣營玩家）的名字、軍銜、榮譽、" ..
       "地圖和時間，連同你的角色名字、職業、等級、公會傳給阿莫比做排行（排行顯示真名）。不用在公會裡；站長不在線就先存著，之後再傳。")
  page.srcCheck = ns.UI.Check(page, "把物品來源傳給阿莫比（商人、任務、怪物和寶箱的掉落、訓練師）",
    function() return ns.db.settings.srcShare ~= false end,
    function(v)
      S.SetShare("srcShare", v)
    end)
  page.srcCheck:SetPoint("TOPLEFT", -4, y)
  y = y - 30
  line("跟商人買東西、接任務和交任務、打開怪物屍體和寶箱、打開訓練師視窗時，記下賣什麼、給什麼、掉什麼、教什麼、任務要做什麼，連同 NPC 的名字和地圖座標，" ..
       "網站物品頁的「怎麼取得」、任務資料庫、世界地圖的訓練師就有永恆真正的資料。只記 NPC 的名字，不記玩家的名字；不用在公會裡，站長不在線就先存著。")
  page.seenCheck = ns.UI.Check(page, "把身邊看到的玩家、公會在線成員傳給阿莫比的人口普查和擊殺排行榜",
    function() return ns.db.settings.seenShare ~= false end,
    function(v)
      S.SetShare("seenShare", v)
    end)
  page.seenCheck:SetPoint("TOPLEFT", -4, y)
  y = y - 30
  line("名條、滑鼠指到的、目標、隊友裡的同陣營玩家，還有你公會裡在線的成員，記下名字、等級、職業、種族、公會和所在的區域，網站的人口普查就不用只靠站長查 /who。" ..
       "網站上的角色名字換成代號，不會公開；不用在公會裡，站長不在線就先存著。打 /amobi 看到 可以檢查。" ..
       "也用「觀察」查身邊玩家的榮譽擊殺和軍銜給擊殺排行榜（兩個陣營、顯示名字；戰鬥中不查）。打 /amobi 戰績 可以檢查。")
  page.status = line("", "GameFontHighlight", 120)
end

local function refreshTab(page)
  if page.check then page.check:Refresh() end
  if page.pvpCheck then page.pvpCheck:Refresh() end
  if page.srcCheck then page.srcCheck:Refresh() end
  if page.seenCheck then page.seenCheck:Refresh() end
  local rows = {}
  if isCollector() then
    rows[#rows + 1] = "這台電腦裝了阿莫比公會名單插件：你就是收資料的站長，這裡不用傳（你自己的榮譽擊殺、物品來源、看到的玩家直接存進公會名單插件）。"
  else
    rows[#rows + 1] = collector and "|cff60ff60阿莫比站長在線|r，有新的資料會馬上傳。"
      or db.seenAt and ("上次看到阿莫比站長在線：" .. date("%m/%d %H:%M", db.seenAt) .. "。站長下次在線時再傳。")
      or "還沒看到阿莫比站長在線。"
    if not on() then
      rows[#rows + 1] = "拍賣場、首領掉落：已經關掉，不記也不傳。"
    elseif not S.Reachable() then
      rows[#rows + 1] = "拍賣場、首領掉落：14 天內還沒聯絡上阿莫比站長，先不記（聯絡上就開始記）。"
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
    if ns.db.settings.srcShare == false then
      rows[#rows + 1] = "物品來源：已經關掉，不記也不傳。"
    elseif not srcOn() then
      rows[#rows + 1] = "物品來源：這個陣營不記（只記聯盟、部落）。"
    else
      rows[#rows + 1] = "物品來源：" .. ns.Sources.Status()
    end
    if ns.db.settings.seenShare == false then
      rows[#rows + 1] = "看到的玩家：已經關掉，不記也不傳。"
    elseif not seenOn() then
      rows[#rows + 1] = "看到的玩家：這個陣營不記（只記聯盟、部落）。"
    else
      rows[#rows + 1] = "看到的玩家：" .. ns.Seen.Status()
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
  -- 站長斷線、下線：馬上停（1.24.1）
  ns.On("CHAT_MSG_SYSTEM", onSystem)
  -- 擋掉密站長時遊戲回的「未找到名為…的線上玩家」（聊天框的過濾器；遊戲用 securecallfunction 呼叫）
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
