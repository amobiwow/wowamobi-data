-- 阿莫比公會名單（老闆 10/25：競拍場「開單限公會成員」，「判斷要登錄的人的名字在我的工會，就可以使用了」）
--   只裝在老闆自己的兩台電腦（tools/build_auto_upload_kit.py 的安裝包），不放網站下載：
--   公開的阿莫比小幫手不讀公會名單（它只記榮譽擊殺的對方名字，1.7.0），所以讀公會名單另外做成這個小插件。
-- 讀遊戲自己的公會視窗用的名單（C_Club：離線的成員也有），存進 AmobiGuildDB.guild；
-- 登出後 tools/auto_upload.py → site/scripts/upload-roster.mjs 把名字加密（HMAC）後才傳到網站。
-- 戰鬥中、有插件限制時遊戲會把名單變成讀不到的秘密值：只在登入後、公會名單更新、脫離戰鬥時讀；
-- 請伺服器更新名單（C_GuildInfo.GuildRoster）最多 30 秒一次，跟遊戲的公會視窗一樣。只讀名單，不會替你做任何事。
--
-- 1.1.0 收資料（老闆 10/25：「我這一端是不是要寫一個接收的辦法？然後跟那份人口普查的資料一起自動上傳吧」）：
--   公會成員的阿莫比小幫手（Share.lua）記下的拍賣場物價、首領掉落，用插件訊息（玩家看不到）傳到這裡。
--   登入後在公會頻道說一聲「我在」（"C"）；小幫手有東西要傳時會在公會頻道問（"P"），這邊用密語回「我在」。
--   小幫手用密語一則一則傳過來（D<編號>,<第幾則>,<共幾則>;<內容>），收齊、核對編號（內容的雜湊）後存進
--   AmobiGuildDB.inbox，回「收到」（A<編號>）。只收公會名單上的人傳的；一個人同時最多收 1 MB，10 分鐘沒傳完的丟掉。
--   登出後 tools/auto_upload.py 把拍賣場的交給 amobi_auction.py、首領的交給 upload-loot.mjs，和自己記的一起上傳。
--   存檔裡記得是誰傳的（掉落要算幾個人回報），上傳時只送加密後的代號，不送名字。
--
-- 1.2.0 榮譽擊殺（老闆 10/26：「只要安裝 ui，他們不需要主動幹嘛」，只針對阿莫比所在的亞服 PvP 規則聯盟）：
--   小幫手 1.7.0 起的角色記下拿到的榮譽擊殺（H1^…、H2^…、H3^…，格式見小幫手 PvP.lua），不管有沒有公會都直接密語問站長的角色名，
--   所以這邊也回答密語的「P」（同一個人一分鐘一次；公會外的人回 "CW"，小幫手就只傳榮譽擊殺），也收公會外的人傳來的——
--   但只收 H1／H2／H3，一個人同時最多 32 KB、一小時最多 30 筆。
--   1.2.2（老闆 10/26 晚：部落的資料傳到 大名「阿莫比」小名「阿莫」）：部落帳號也裝這個插件，收部落玩家的榮譽擊殺
--   （插件訊息不能跨陣營，聯盟的傳給聯盟的「谷阿莫」、部落的傳給部落的「阿莫比」；小幫手 1.13.1 起部落改傳公司那台的「阿莫谷 摩寧」）。部落那邊的公會名單 upload-roster.mjs 不傳。
--   站長自己這台的小幫手記到的，直接呼叫 AmobiGuild_Store(內容) 存進來（寄件人是自己）。
--   登出後 tools/auto_upload.py → site/scripts/upload-pvp.mjs 上傳（POST /api/pvp；網站合併同一個擊殺的多人回報）。
--
-- 1.3.0 物品來源（老闆 10/27：「物品的資料 能補他們來源的單位跟地圖座標嗎」→ 小幫手 1.11.0「一起做」）：
--   小幫手記下商人賣什麼、任務給什麼、怪物和寶箱掉什麼、在哪裡（S1^…，格式見小幫手 Sources.lua），和榮譽擊殺一樣
--   公會外的人也收（同一個上限：一個人同時最多 32 KB、一小時最多 30 筆）。站長自己這台的小幫手記到的也用 AmobiGuild_Store 存進來
--   （標 own：網站算站長自己記的）。登出後 tools/auto_upload.py → site/scripts/upload-sources.mjs 上傳（POST /api/sources）。
--
-- 1.4.0 公會名單多記職業（老闆 10/31：Discord 名字改成「大名＋次名丨職業」，「後方的職業同等遊戲職業」才給「正式公會成員」）：
--   AmobiGuildDB.guild.classes[名字] = 職業編號（classID：1 戰士、2 聖騎士…），upload-roster.mjs 跟著加密後的名字一起傳。

local ADDON = ...
local frame = CreateFrame("Frame")
local pending, retrying = false, false
local asked = -1000
local read
local RESTRICT = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map" }
local PREFIX = "AMOBI"
local MAX_PER_SENDER = 1024 * 1024   -- 一個人同時最多收 1 MB
local STALE = 10 * 60                -- 秒：10 分鐘沒傳完的丟掉
local KEEP_DAYS = 21                 -- 存檔只留 21 天（自動上傳每次登出都會傳）
local MAX_INBOX = 5000
local GUEST_BYTES = 32 * 1024        -- 公會外的人（只收榮譽擊殺）同時最多收 32 KB
local GUEST_PER_HOUR = 30            -- 公會外的人一小時最多收 30 筆
local guests = {}                    -- [寄件人] = { 這一小時收到的時間… }
local buffers, replied = {}, {}

local function secret(v)
  if issecretvalue and issecretvalue(v) then return true end
  if type(v) == "table" and issecrettable and issecrettable(v) then return true end
  return false
end

local function restricted()
  if InCombatLockdown() then return true end
  local api, enum = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
  if api and api.IsAddOnRestrictionActive and enum then
    for _, r in ipairs(RESTRICT) do
      local t = enum[r]
      if t ~= nil then
        local ok, on = pcall(api.IsAddOnRestrictionActive, t)
        if ok and not secret(on) and on == true then return true end
      end
    end
  end
  return false
end

local function safe(fn)
  local ok, err = pcall(fn)
  if not ok then AmobiGuildDB.lastError = tostring(err) end
end

-- 現在讀不到（戰鬥中、首領戰……）：10 秒後再試，一直到讀得到為止（同時只排一個）
local function later()
  pending = true
  if retrying then return end
  retrying = true
  C_Timer.After(10, function()
    retrying = false
    if pending then safe(read) end
  end)
end

function read()
  if restricted() then return later() end
  if not (IsInGuild and IsInGuild()) then return end
  if not (C_Club and C_Club.GetGuildClubId and C_Club.GetClubMembers and C_Club.GetMemberInfo) then return end
  local clubId = C_Club.GetGuildClubId()
  if clubId == nil or secret(clubId) then return end
  local ids = C_Club.GetClubMembers(clubId)
  if type(ids) ~= "table" or secret(ids) then return later() end
  local names, classes, skipped = {}, {}, 0
  for _, mid in ipairs(ids) do
    local info = C_Club.GetMemberInfo(clubId, mid)
    local name = type(info) == "table" and not secret(info) and info.name
    if type(name) == "string" and not secret(name) and name ~= "" then
      names[#names + 1] = name
      local cls = info.classID
      if type(cls) == "number" and not secret(cls) then classes[name] = cls end
    else skipped = skipped + 1 end
  end
  if #names == 0 then return end
  if skipped * 2 > #ids then return later() end   -- 大半讀不到：等一下再讀，不要存一份殘缺的
  table.sort(names)
  local guild = GetGuildInfo("player")
  if secret(guild) or type(guild) ~= "string" then guild = nil end
  AmobiGuildDB.guild = { name = guild, faction = UnitFactionGroup("player"), realm = GetRealmName(),
                         at = time(), members = names, classes = classes }
  pending = false
end

local function ask()
  if restricted() then return later() end
  if C_GuildInfo and C_GuildInfo.GuildRoster and GetTime() - asked >= 30 then
    asked = GetTime()
    C_GuildInfo.GuildRoster()      -- 伺服器回 GUILD_ROSTER_UPDATE 時再讀一次
  end
  read()
end

-- ------------------------------------------------------------------ 收資料
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function hash(str)   -- 和小幫手 Share.lua 的 S.Hash 一樣
  local h = 5381
  for i = 1, #str do h = (h * 33 + str:byte(i)) % 4294967296 end
  local out = ""
  repeat
    local r = h % 36
    out = DIGITS:sub(r + 1, r + 1) .. out
    h = (h - r) / 36
  until h == 0
  return out
end

local function chatOK() return type(C_ChatInfo) == "table" and type(C_ChatInfo.SendAddonMessage) == "function" end
local function send(msg, kind, target)
  if not chatOK() then return end
  pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, kind, target)
end

local function bare(name) return type(name) == "string" and (name:gsub("%-.*$", "")) or "" end

-- 只收公會名單上的人（名字後面的「-伺服器」不算）
local function member(name)
  local g = AmobiGuildDB.guild
  if not g or type(g.members) ~= "table" then return false end
  local want = bare(name)
  for _, n in ipairs(g.members) do
    if bare(n) == want then return true end
  end
  return false
end

local function prune()
  local keep, oldest = {}, time() - KEEP_DAYS * 86400
  for _, e in ipairs(AmobiGuildDB.inbox) do
    if type(e) == "table" and type(e.at) == "number" and e.at >= oldest then keep[#keep + 1] = e end
  end
  while #keep > MAX_INBOX do table.remove(keep, 1) end
  AmobiGuildDB.inbox = keep
  for id, t in pairs(AmobiGuildDB.got) do
    if type(t) ~= "number" or t < oldest then AmobiGuildDB.got[id] = nil end
  end
end

local function store(from, id, body)
  if not AmobiGuildDB.got[id] then
    AmobiGuildDB.got[id] = time()
    table.insert(AmobiGuildDB.inbox, { id = id, from = from, at = time(), body = body })
    AmobiGuildDB.stats.records = (AmobiGuildDB.stats.records or 0) + 1
    AmobiGuildDB.stats.last = time()
  end
  send("A" .. id, "WHISPER", from)
end

-- 榮譽擊殺（小幫手 1.7.0 是 H1，1.7.1 是 H2：多了職業、公會、區域、等級；1.7.2 起 H3：多了陣營）
local function isPvp(body) return body:match("^H[123]%^") ~= nil end
-- 物品來源（小幫手 1.11.0）
local function isSrc(body) return body:match("^S1%^") ~= nil end
-- 公會外的人傳來的只收這兩種
local function guestOK(body) return isPvp(body) or isSrc(body) end

local function guestFull(sender)
  local list, keep = guests[sender] or {}, {}
  for _, t in ipairs(list) do if time() - t < 3600 then keep[#keep + 1] = t end end
  guests[sender] = keep
  return #keep >= GUEST_PER_HOUR
end

local function onData(sender, text, guest)
  local id, i, n, chunk = text:match("^D([0-9a-z]+),(%d+),(%d+);(.*)$")
  i, n = tonumber(i), tonumber(n)
  if not id or not i or not n or i < 1 or i > n or n > 5000 then return end
  if AmobiGuildDB.got[id] then
    if i == n then send("A" .. id, "WHISPER", sender) end   -- 已經收過（對方沒收到「收到」又傳一次）
    return
  end
  local mine = buffers[sender]
  if not mine then mine = { bytes = 0, records = {} }; buffers[sender] = mine end
  local r = mine.records[id]
  if not r then r = { n = n, got = 0, parts = {} }; mine.records[id] = r end
  r.at = GetTime()
  if r.n ~= n or r.parts[i] then return end
  if mine.bytes + #chunk > (guest and GUEST_BYTES or MAX_PER_SENDER) then return end
  r.parts[i], r.got, mine.bytes = chunk, r.got + 1, mine.bytes + #chunk
  if r.got < r.n then return end
  local body = table.concat(r.parts)
  mine.records[id], mine.bytes = nil, mine.bytes - #body
  if hash(body) ~= id then
    AmobiGuildDB.stats.bad = (AmobiGuildDB.stats.bad or 0) + 1
    return
  end
  if guest then                                    -- 公會外的人只收榮譽擊殺和物品來源，而且有量的上限
    if not guestOK(body) or guestFull(sender) then
      AmobiGuildDB.stats.refused = (AmobiGuildDB.stats.refused or 0) + 1
      return
    end
    table.insert(guests[sender], time())
  end
  store(sender, id, body)
end

local function cleanBuffers()
  for sender, mine in pairs(buffers) do
    for id, r in pairs(mine.records) do
      if GetTime() - r.at > STALE then
        for _, c in pairs(r.parts) do mine.bytes = mine.bytes - #c end
        mine.records[id] = nil
      end
    end
    if not next(mine.records) then buffers[sender] = nil end
  end
end

local function onMessage(prefix, text, channel, sender)
  if prefix ~= PREFIX or type(text) ~= "string" or secret(text) or type(sender) ~= "string" or secret(sender) then return end
  if (channel == "GUILD" or channel == "WHISPER") and text == "P" then   -- 公會頻道問的、直接密語問的（榮譽擊殺）
    if replied[sender] and GetTime() - replied[sender] < 60 then return end   -- 同一個人一分鐘回一次就好
    replied[sender] = GetTime()
    -- 公會成員（或在公會頻道問的）回 "C"；公會外的人直接問的回 "CW"：小幫手只傳榮譽擊殺和物品來源過來
    send((channel == "GUILD" or member(sender)) and "C" or "CW", "WHISPER", sender)
  elseif channel == "WHISPER" and text:sub(1, 1) == "D" then
    onData(sender, text, not member(sender))
  end
end

local function hello()
  if IsInGuild and IsInGuild() then send("C", "GUILD") end
end

-- 第一個參數不能叫 arg：Lua 5.1 有「...」的函式裡，arg 會被當成舊式的參數表（永遠是 nil）
frame:SetScript("OnEvent", function(_, event, a1, ...)
  if event == "ADDON_LOADED" then
    if a1 ~= ADDON then return end
    AmobiGuildDB = type(AmobiGuildDB) == "table" and AmobiGuildDB or {}
    AmobiGuildDB.v = 1
    for _, k in ipairs({ "inbox", "got", "stats" }) do
      if type(AmobiGuildDB[k]) ~= "table" then AmobiGuildDB[k] = {} end
    end
    safe(prune)
    if chatOK() and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
    C_Timer.NewTicker(60, function() safe(cleanBuffers) end)
  elseif event == "PLAYER_ENTERING_WORLD" then
    C_Timer.After(8, function() safe(ask) end)       -- 登入後等公會資料載好
    C_Timer.After(12, function() safe(hello) end)    -- 讀完名單再跟公會說「我在」
  elseif event == "GUILD_ROSTER_UPDATE" then
    safe(read)
  elseif event == "PLAYER_REGEN_ENABLED" then
    if pending then C_Timer.After(1, function() safe(read) end) end
  elseif event == "CHAT_MSG_ADDON" then
    local text, channel, sender = ...
    safe(function() onMessage(a1, text, channel, sender) end)
  end
end)
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "GUILD_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "CHAT_MSG_ADDON" }) do
  frame:RegisterEvent(e)
end

-- 站長自己這台的小幫手記到的榮譽擊殺、物品來源：直接存進來（寄件人是自己，標 own）
function AmobiGuild_Store(body)
  if type(body) ~= "string" or not guestOK(body) or type(AmobiGuildDB) ~= "table" or not AmobiGuildDB.inbox then return false end
  local me = UnitName("player")
  if secret(me) or type(me) ~= "string" then me = "?" end
  local id = hash(body)
  if not AmobiGuildDB.got[id] then
    AmobiGuildDB.got[id] = time()
    table.insert(AmobiGuildDB.inbox, { id = id, from = me, at = time(), body = body, own = true })
    AmobiGuildDB.stats.records = (AmobiGuildDB.stats.records or 0) + 1
    AmobiGuildDB.stats.last = time()
  end
  return true
end

SLASH_AMOBIGUILD1 = "/amobiguild"
SlashCmdList.AMOBIGUILD = function()
  safe(ask)
  local g = AmobiGuildDB and AmobiGuildDB.guild
  if not g then
    print("|cffe9cb88阿莫比公會名單|r：還沒讀到公會名單（要在公會裡、戰鬥外）。")
  else
    local withClass = 0
    for _ in pairs(type(g.classes) == "table" and g.classes or {}) do withClass = withClass + 1 end
    print(("|cffe9cb88阿莫比公會名單|r：%s %d 人、%d 人有職業（%s 讀到）。登出後自動上傳到競拍場、Discord 身分組。"):format(
      g.name or "公會", #g.members, withClass, date("%m/%d %H:%M", g.at)))
  end
  local market, kills, pvp, src, people, n = 0, 0, 0, 0, {}, 0
  for _, e in ipairs(AmobiGuildDB and AmobiGuildDB.inbox or {}) do
    local kind = e.body:sub(1, 3)
    if kind == "M1^" then market = market + 1 elseif isPvp(e.body) then pvp = pvp + 1
    elseif isSrc(e.body) then src = src + 1 else kills = kills + 1 end
    if not people[bare(e.from)] then people[bare(e.from)], n = true, n + 1 end
  end
  print(("|cffe9cb88阿莫比公會名單|r：小幫手傳來 %d 次拍賣場掃描、%d 次首領擊殺%s%s（%d 個人）。登出後自動上傳到網站。")
    :format(market, kills, pvp > 0 and ("、%d 筆榮譽擊殺"):format(pvp) or "", src > 0 and ("、%d 筆物品來源"):format(src) or "", n))
end
