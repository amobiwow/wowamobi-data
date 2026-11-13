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
--   （插件訊息不能跨陣營，聯盟的傳給聯盟的「谷阿莫」、部落的傳給部落的「阿莫比」；小幫手 1.13.1 起部落改傳公司那台的「阿莫谷 摩寧」、1.13.2 起聯盟改傳家裡那台的「阿莫谷 拉克」）。部落那邊的公會名單 upload-roster.mjs 不傳。
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
--
-- 1.5.0 看到的玩家（老闆 11/8：「我本身看到別人時有可能紀錄他的資料嗎」「資料庫只要看到新資料就更新上去就好了，不可能永遠都靠我」）：
--   小幫手 1.18.0 記下身邊看到的同陣營玩家（W1^…，格式見小幫手 Seen.lua），和物品來源一樣公會外的人也收（同一個上限）。
--   不放 inbox：收到就併進 AmobiGuildDB.seen["伺服器 - 陣營"].players[名字]，欄位和 DenizensTW 的普查名單一樣
--   （lvl、class、token、race、guild、area、first、last、seen），登出後 tools/auto_upload.py 把這份和 DenizensTW.lua
--   一起交給普查的上傳程式（site/public/assets/denizens.js 認得這個表），網站上的人口普查就會算進去。
--   只收和這台電腦登入的角色同伺服器、同陣營的：一台電腦只負責一個陣營的普查（另一個陣營在另一台），不能混進來。
--   公會是空的＝小幫手讀不到，不洗掉原本記到的公會。每個「伺服器 - 陣營」最多 40,000 人，超過刪最久沒看到的。
--   收過的編號另外記在 gotSeen（3 天；小幫手包好的最多留 3 天），不佔 got。
--
-- 1.6.0 PvP 戰績（老闆 11/8：「不可能全部人都裝我的UI 這樣好像無法有效撈取PVP資料 有其他辦法嗎」→「繼續」）：
--   小幫手 1.21.0 用「觀察」查身邊玩家的總榮譽擊殺、今天的榮譽擊殺、軍銜（R1^…，格式見小幫手 Honor.lua），和看到的玩家一起傳來，
--   公會外的人也收（同一個上限）。不放 inbox：收到就併進 AmobiGuildDB.honor["伺服器"].players[名字]
--   （fa 陣營 A／H、lvl、token、guild、v＝遊戲給的 9 個數字（36 進位，逗號分隔）、first、last、seen），同一個人留最新的。
--   兩個陣營都收（戰績是看到誰就查誰，不是普查，不會蓋掉另一個陣營），只收同伺服器的。每個伺服器最多 40,000 人。
--   登出後 tools/auto_upload.py → site/scripts/upload-honor.mjs 上傳（POST /api/pvp/honor），擊殺排行榜的「全服戰績」。
-- 1.6.1 拿掉公會外的人「一小時最多 30 筆」（老闆 11/9 看到部落一輪被擋 4,819 筆、只收 3,622 筆：「其實可以不用擋吧」）。
--   這個上限是只收榮譽擊殺時訂的；後來公會外的人也傳物品來源、看到的玩家、PvP 戰績，部落又沒有我們的公會（全部算公會外），
--   擋掉的要等對方下次登入才重傳，補很久。遊戲本身限制每個人每秒大約 1 則插件訊息，量不會爆；同時 32 KB、只收那幾種照舊。
-- 1.6.2 公會外的人傳的拍賣場物價、首領掉落也收（老闆 11/9：「也要收」；部落沒有阿莫比的公會，網站一直沒有部落的物價、掉落）：
--   公會外的人和公會成員一樣，什麼都收、同時最多 1 MB（拍賣場一次全掃描可能超過 32 KB）。小幫手 1.24.3 起公會外也會記、也會傳。
--   收件匣上限 5,000 → 20,000 筆（二號大腦提醒：拿掉上限後量變大，兩次存檔之間超過的話還沒上傳就被擠掉）。
-- 1.7.0 收資料的角色自動重新載入（老闆 11/9：「要一直 Reload 不切實際」「有辦法自動 reload?」）：
--   小幫手傳來的資料先放在遊戲記憶體，要 /reload、登出或斷線才會寫進存檔、讓自動上傳送到網站（11/9 奈特卡了 8 小時）。
--   站長收資料的角色（COLLECTORS）每 60 分鐘自己 ReloadUI() 一次；裝好後第一次在進遊戲 2 分鐘後（馬上知道遊戲讓不讓）。
--   戰鬥中、有插件限制、30 秒內還有人在傳資料片段時先等，下一分鐘再看。重新載入那幾秒剛好傳來的，小幫手沒收到「收到」會再傳。
--   遊戲擋下來（ADDON_ACTION_FORBIDDEN／BLOCKED 指名這個插件）就記 reloadBlocked、之後不再試。站長自己玩的角色不會自動重新載入。
-- 1.7.1 等空檔改成 5 秒、最多等 5 分鐘（三號大腦 11/9 查：熱門時段奈特每分鐘收齊 75 筆、最長空檔 8 秒，30 秒的空檔一整晚 0 次，
--   1.7.0 到時間後一直等不到、從沒自動重新載入過）。每 5 秒看一次；到時間 5 分鐘還等不到 5 秒空檔就照樣重新載入（沒傳完的小幫手 90 秒後再傳）。
-- 1.7.2 自己的名字接回「主名 次名」：永恆的 UnitName("player") 給 "阿莫谷", "奈特" 兩個值，1.7.0／1.7.1 只拿第一個，
--   跟 COLLECTORS 永遠對不上，所以兩台都沒自動重新載入過（1.7.1 裝好後兩台盯了 10 分鐘還是沒動）。到時間沒重新載入的原因記在 reloadWhy。
-- 1.7.3 重新載入不看 Map 限制（遊戲說明：「在會套用插件限制的地圖上」）：1.7.2 名字對了還是沒動；公會名單（read() 也先看限制）
--   每次都剛好在存檔那一秒才讀到（奈特 22:56:11／存檔 22:56:12、拉克 22:35／22:35），表示平常一直有限制、登出那一刻才解除。
--   戰鬥、首領戰、傳奇鑰石、PvP 對戰中照樣等。
-- 1.7.4 存檔不能撐爆（三號大腦 11/12 查：奈特的存檔 11/11 20:39 長到 48 MB，遊戲載入時「constant table overflow」，整份被清空，
--   首頁聯盟普查因此少了 2,331 個只被小幫手看到的人）。遊戲的 Lua 5.1 一個存檔最多 262,143 個不重複的字串＋數字，那份有 269,465 個：
--   收過的編號 gotSeen 94,680（3 天）、收件匣 83,852、PvP 戰績 42,227、got 31,484（21 天）、看到的玩家 16,184。
--   收過的編號只是擋重複：時間只記到小時（不重複的數字從幾萬個變幾十個）；got 只記 3 天、最多 20,000 個（和收件匣一樣多），
--   gotSeen 只記 1 天、最多 25,000 個（過了再收到同一筆，看到的玩家、戰績照時間合併，只有「看到幾次」多算一次；其他的網站會擋重複）。
--   每 30 分鐘在遊戲裡也清一次收過的編號（收件匣照舊只在載入時清：還沒寫進存檔的不能丟）。

local ADDON = ...
local frame = CreateFrame("Frame")
local pending, retrying = false, false
local asked = -1000
local read
local RESTRICT = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map" }
local PREFIX = "AMOBI"
local MAX_PER_SENDER = 1024 * 1024   -- 一個人同時最多收 1 MB
local STALE = 10 * 60                -- 秒：10 分鐘沒傳完的丟掉
local KEEP_DAYS = 21                 -- 收件匣只留 21 天（自動上傳每次登出都會傳）
local MAX_INBOX = 20000              -- 1.6.2 起（原本 5,000）
local GOT_DAYS = 3                   -- 1.7.4：收過的編號（got）記幾天（原本和收件匣一樣 21 天）
local GOT_MAX = 20000                -- 1.7.4：got 最多幾個（和收件匣一樣多：編號和收件匣裡的共用），超過刪最舊的那幾個小時
local SEEN_MAX = 40000               -- 看到的玩家：每個「伺服器 - 陣營」最多記幾人
local SEEN_GOT_DAYS = 1              -- 看到的玩家、戰績：收過的編號記幾天（1.7.4 起 1 天，原本 3 天）
local SEEN_GOT_MAX = 25000           -- 1.7.4：gotSeen 最多幾個
local PRUNE_EVERY = 30 * 60          -- 1.7.4：秒：遊戲裡多久清一次收過的編號
local HONOR_MAX = 40000              -- PvP 戰績：每個伺服器最多記幾人
local buffers, replied = {}, {}
local COLLECTORS = { ["阿莫谷 奈特"] = true, ["阿莫谷 摩寧"] = true }   -- 1.7.0：會自動重新載入的角色（小幫手 PvP.lua 的 COLLECTORS）
local RELOAD_EVERY = 60 * 60         -- 秒：多久自動重新載入一次
local FIRST_RELOAD = 120             -- 秒：從來沒自動重新載入過時，進遊戲後多久試第一次
local BUSY_GAP = 5                   -- 秒：這麼久內有人傳資料片段就先等（1.7.0 是 30 秒，熱門時段等不到）
local MAX_WAIT = 5 * 60              -- 秒：到時間後最多等這麼久，之後有人在傳也照樣重新載入
local RELOAD_TICK = 5                -- 秒：多久看一次該不該重新載入
local RELOAD_RESTRICT = { "Combat", "Encounter", "ChallengeMode", "PvPMatch" }   -- 1.7.3：重新載入只看這些，不看 Map（永恆一直開著）
local loadedAt, lastTry, lastPiece = 0, nil, -1000

local function secret(v)
  if issecretvalue and issecretvalue(v) then return true end
  if type(v) == "table" and issecrettable and issecrettable(v) then return true end
  return false
end

-- 現在有沒有插件限制：回傳是哪一種（"戰鬥中"、"Map"…），沒有回傳 false。list 不給就看 RESTRICT 全部
local function restricted(list)
  if InCombatLockdown() then return "戰鬥中" end
  local api, enum = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
  if api and api.IsAddOnRestrictionActive and enum then
    for _, r in ipairs(list or RESTRICT) do
      local t = enum[r]
      if t ~= nil then
        local ok, on = pcall(api.IsAddOnRestrictionActive, t)
        if ok and not secret(on) and on == true then return r end
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

-- 1.7.4：收過的編號只記到小時（存檔裡不重複的數字少很多）
local function hour(t) return t - t % 3600 end

-- 收過的編號：太舊的刪掉、時間改成小時；超過上限就從最舊的那個小時整批刪
local function trimIds(ids, oldest, max)
  local n, per = 0, {}
  for id, t in pairs(ids) do
    if type(t) ~= "number" or t < oldest then
      ids[id] = nil
    else
      local h = hour(t)
      if h ~= t then ids[id] = h end
      n, per[h] = n + 1, (per[h] or 0) + 1
    end
  end
  if n <= max then return end
  local hours = {}
  for h in pairs(per) do hours[#hours + 1] = h end
  table.sort(hours)
  local cut
  for _, h in ipairs(hours) do
    if n <= max then break end
    n, cut = n - per[h], h
  end
  for id, t in pairs(ids) do
    if t <= cut then ids[id] = nil end
  end
end

local function pruneIds()
  trimIds(AmobiGuildDB.got, time() - GOT_DAYS * 86400, GOT_MAX)
  trimIds(AmobiGuildDB.gotSeen, time() - SEEN_GOT_DAYS * 86400, SEEN_GOT_MAX)
end

local function prune()
  local keep, oldest = {}, time() - KEEP_DAYS * 86400
  for _, e in ipairs(AmobiGuildDB.inbox) do
    if type(e) == "table" and type(e.at) == "number" and e.at >= oldest then keep[#keep + 1] = e end
  end
  while #keep > MAX_INBOX do table.remove(keep, 1) end
  AmobiGuildDB.inbox = keep
  pruneIds()
end

local seenMerge, honorMerge
local function isSeen(body) return body:match("^W1%^") ~= nil end
local function isHonor(body) return body:match("^R1%^") ~= nil end

-- 看到的玩家、PvP 戰績：收到就併進名單，不放 inbox（收過的編號記在 gotSeen）
local function mergeOnce(id, body)
  if AmobiGuildDB.gotSeen[id] then return end
  AmobiGuildDB.gotSeen[id] = hour(time())
  if isHonor(body) then honorMerge(body) else seenMerge(body) end
end

local function store(from, id, body)
  if isSeen(body) or isHonor(body) then
    mergeOnce(id, body)
    return send("A" .. id, "WHISPER", from)
  end
  if not AmobiGuildDB.got[id] then
    AmobiGuildDB.got[id] = hour(time())
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
-- 公會外的人傳來的只收這三種（看到的玩家：小幫手 1.18.0）
local function guestOK(body) return isPvp(body) or isSrc(body) or isSeen(body) or isHonor(body) end

-- 看到的玩家（W1^伺服器^陣營^名字:等級:職業代碼:職業:種族:公會:區域:時間~…）併進 AmobiGuildDB.seen；回傳有沒有收
function seenMerge(body)
  local realm, faction, rest = body:match("^W1%^([^%^]*)%^([^%^]*)%^(.*)$")
  if not realm then return false end
  local myRealm, myFaction = GetRealmName(), UnitFactionGroup("player")
  if secret(myRealm) or secret(myFaction) or realm ~= myRealm or faction ~= myFaction then
    AmobiGuildDB.stats.seenOther = (AmobiGuildDB.stats.seenOther or 0) + 1   -- 別的伺服器、陣營的：不收
    return false
  end
  local key = realm .. " - " .. faction
  local r = AmobiGuildDB.seen[key]
  if type(r) ~= "table" or type(r.players) ~= "table" then
    r = { players = {}, count = 0 }
    AmobiGuildDB.seen[key] = r
  end
  local players, latest = r.players, time() + 3600
  for entry in (rest .. "~"):gmatch("([^~]*)~") do
    local name, lvl, token, cls, race, guild, area, t =
      entry:match("^([^:]+):(%w+):(%w+):([^:]*):([^:]+):([^:]*):([^:]*):(%w+)$")
    lvl, t = tonumber(lvl or "", 36), tonumber(t or "", 36)
    if name and name:find(" ", 1, true) and lvl and lvl >= 1 and lvl <= 100 and t and t <= latest then
      local p = players[name]
      if type(p) ~= "table" then
        p = { first = t, seen = 0 }
        players[name] = p
        r.count = (r.count or 0) + 1
      end
      if t >= (p.last or 0) then
        p.lvl, p.token, p.class, p.race, p.area, p.last = lvl, token, cls, race, area, t
        if guild ~= "" then p.guild = guild end   -- 空的＝讀不到：留著原本的
      end
      if t < (p.first or t) then p.first = t end
      p.seen = (p.seen or 0) + 1
    end
  end
  if (r.count or 0) > SEEN_MAX then                 -- 太多了：刪最久沒看到的，留九成
    local list = {}
    for name, p in pairs(players) do list[#list + 1] = { name, type(p) == "table" and p.last or 0 } end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    for i = 1, #list - math.floor(SEEN_MAX * 0.9) do players[list[i][1]] = nil end
    r.count = math.floor(SEEN_MAX * 0.9)
  end
  AmobiGuildDB.stats.seen = (AmobiGuildDB.stats.seen or 0) + 1
  return true
end

-- PvP 戰績（R1^伺服器^陣營^名字:A／H:等級:職業代碼:公會:時間:數字,…~…）併進 AmobiGuildDB.honor；回傳有沒有收
function honorMerge(body)
  local realm, rest = body:match("^R1%^([^%^]*)%^[^%^]*%^(.*)$")
  if not realm then return false end
  local myRealm = GetRealmName()
  if secret(myRealm) or realm ~= myRealm then
    AmobiGuildDB.stats.honorOther = (AmobiGuildDB.stats.honorOther or 0) + 1   -- 別的伺服器：不收
    return false
  end
  local r = AmobiGuildDB.honor[realm]
  if type(r) ~= "table" or type(r.players) ~= "table" then
    r = { players = {}, count = 0 }
    AmobiGuildDB.honor[realm] = r
  end
  local players, latest = r.players, time() + 3600
  for entry in (rest .. "~"):gmatch("([^~]*)~") do
    local name, fa, lvl, token, guild, t, v = entry:match("^([^:]+):([AH]):(%w*):(%w*):([^:]*):(%w+):([%w,]*)$")
    lvl, t = tonumber(lvl or "", 36) or 0, tonumber(t or "", 36)
    if name and name:find(" ", 1, true) and t and t <= latest and lvl <= 100 and v and v:find(",", 1, true) then
      local p = players[name]
      if type(p) ~= "table" then
        p = { first = t, seen = 0 }
        players[name] = p
        r.count = (r.count or 0) + 1
      end
      if t >= (p.last or 0) then
        p.fa, p.v, p.last = fa, v, t
        if lvl > 0 then p.lvl = lvl end
        if token ~= "" then p.token = token end
        if guild ~= "" then p.guild = guild end
      end
      if t < (p.first or t) then p.first = t end
      p.seen = (p.seen or 0) + 1
    end
  end
  if (r.count or 0) > HONOR_MAX then                -- 太多了：刪最久沒查到的，留九成
    local list = {}
    for name, p in pairs(players) do list[#list + 1] = { name, type(p) == "table" and p.last or 0 } end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    for i = 1, #list - math.floor(HONOR_MAX * 0.9) do players[list[i][1]] = nil end
    r.count = math.floor(HONOR_MAX * 0.9)
  end
  AmobiGuildDB.stats.honor = (AmobiGuildDB.stats.honor or 0) + 1
  return true
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
  lastPiece = GetTime()
  if r.n ~= n or r.parts[i] then return end
  if mine.bytes + #chunk > MAX_PER_SENDER then return end   -- 1.6.2 起公會外的人也一樣 1 MB
  r.parts[i], r.got, mine.bytes = chunk, r.got + 1, mine.bytes + #chunk
  if r.got < r.n then return end
  local body = table.concat(r.parts)
  mine.records[id], mine.bytes = nil, mine.bytes - #body
  if hash(body) ~= id then
    AmobiGuildDB.stats.bad = (AmobiGuildDB.stats.bad or 0) + 1
    return
  end
  store(sender, id, body)                          -- 1.6.2 起公會外的人什麼都收（拍賣場、首領掉落也收）
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
    -- 公會成員（或在公會頻道問的）回 "C"；公會外的人直接問的回 "CW"（1.24.2 前的小幫手收到 CW 只傳榮譽擊殺那幾種；1.24.3 起全部傳）
    send((channel == "GUILD" or member(sender)) and "C" or "CW", "WHISPER", sender)
  elseif channel == "WHISPER" and text:sub(1, 1) == "D" then
    onData(sender, text, not member(sender))
  end
end

local function hello()
  if IsInGuild and IsInGuild() then send("C", "GUILD") end
end

-- 自己的全名「主名 次名」：永恆的 UnitName 把次名放在第二個回傳值（「阿莫谷 奈特」→ "阿莫谷", "奈特"，小幫手 Seen.lua 1.19.1）。
-- 1.7.2 前只拿第一個值、跟 COLLECTORS 比永遠不一樣，1.7.0／1.7.1 一次都沒自動重新載入（11/9 兩台盯到的）。
local function myName()
  local name, second = UnitName("player")
  if type(name) ~= "string" or secret(name) or name == "" then return nil end
  if type(second) == "string" and not secret(second) and second ~= "" and not name:find(" ", 1, true)
     and second ~= GetRealmName() and not (GetNormalizedRealmName and second == GetNormalizedRealmName()) then
    return name .. " " .. second
  end
  return name
end

local function isCollector()
  return COLLECTORS[myName() or ""] == true
end

-- 1.7.0：每 5 秒看一次該不該重新載入（只有收資料的角色）。
-- 1.7.2：到時間了卻沒重新載入的原因記在 reloadWhy（下次存檔寫出去時看得到；兩台大腦 11/9 建議）
local function reloadTick()
  local db = AmobiGuildDB
  if db.reloadBlocked then return end
  if not isCollector() then db.reloadWhy = "不是收資料的角色：" .. tostring(myName()); return end
  local due = db.reloadAt and RELOAD_EVERY or FIRST_RELOAD
  local late = GetTime() - (lastTry or loadedAt) - due
  if late < 0 then return end
  local held = restricted(RELOAD_RESTRICT)
  if held then db.reloadWhy = "插件限制中：" .. held; return end
  if late < MAX_WAIT and GetTime() - lastPiece < BUSY_GAP then db.reloadWhy = "有人在傳資料"; return end
  db.reloadWhy = "呼叫 ReloadUI（Map 限制" .. (restricted({ "Map" }) and "開著" or "沒開") .. "）"
  lastTry = GetTime()
  db.reloadAt = time()
  db.stats.autoReloads = (db.stats.autoReloads or 0) + 1
  print("|cffe9cb88阿莫比公會名單|r：自動重新載入介面，把小幫手傳來的資料寫進存檔（每小時一次，自動上傳才送得到網站）。")
  ReloadUI()
end

local function onForbidden(addon, func)
  if addon ~= ADDON or not lastTry or GetTime() - lastTry > 5 then return end
  AmobiGuildDB.reloadBlocked = tostring(func or "ReloadUI")
  print("|cffe9cb88阿莫比公會名單|r：遊戲不讓插件自己重新載入介面，之後不再自動試；收到的資料要 /reload 或登出才會寫進存檔。")
end

-- 第一個參數不能叫 arg：Lua 5.1 有「...」的函式裡，arg 會被當成舊式的參數表（永遠是 nil）
frame:SetScript("OnEvent", function(_, event, a1, ...)
  if event == "ADDON_LOADED" then
    if a1 ~= ADDON then return end
    AmobiGuildDB = type(AmobiGuildDB) == "table" and AmobiGuildDB or {}
    AmobiGuildDB.v = 1
    for _, k in ipairs({ "inbox", "got", "stats", "seen", "gotSeen", "honor" }) do
      if type(AmobiGuildDB[k]) ~= "table" then AmobiGuildDB[k] = {} end
    end
    safe(prune)
    if chatOK() and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
    C_Timer.NewTicker(60, function() safe(cleanBuffers) end)
    C_Timer.NewTicker(PRUNE_EVERY, function() safe(pruneIds) end)   -- 1.7.4：收件匣不在這裡清（還沒寫進存檔）
    loadedAt = GetTime()
    C_Timer.NewTicker(RELOAD_TICK, function() safe(reloadTick) end)
  elseif event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
    local func = ...
    safe(function() onForbidden(a1, func) end)
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
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "GUILD_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "CHAT_MSG_ADDON",
                    "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" }) do
  frame:RegisterEvent(e)
end

-- 站長自己這台的小幫手記到的榮譽擊殺、物品來源：直接存進來（寄件人是自己，標 own）；看到的玩家直接併進普查名單
function AmobiGuild_Store(body)
  if type(body) ~= "string" or not guestOK(body) or type(AmobiGuildDB) ~= "table" or not AmobiGuildDB.inbox then return false end
  if isSeen(body) or isHonor(body) then
    mergeOnce(hash(body), body)
    return true
  end
  local me = myName() or "?"
  local id = hash(body)
  if not AmobiGuildDB.got[id] then
    AmobiGuildDB.got[id] = hour(time())
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
  local people = 0
  for _, r in pairs(AmobiGuildDB and AmobiGuildDB.seen or {}) do
    if type(r) == "table" and type(r.count) == "number" then people = people + r.count end
  end
  print(("|cffe9cb88阿莫比公會名單|r：小幫手看到的玩家 %d 人（收到 %d 筆）。登出後和 /who 普查一起上傳。")
    :format(people, AmobiGuildDB and AmobiGuildDB.stats.seen or 0))
  local honor = 0
  for _, r in pairs(AmobiGuildDB and AmobiGuildDB.honor or {}) do
    if type(r) == "table" and type(r.count) == "number" then honor = honor + r.count end
  end
  print(("|cffe9cb88阿莫比公會名單|r：小幫手查到 %d 人的 PvP 戰績（收到 %d 筆）。登出後上傳到擊殺排行榜。")
    :format(honor, AmobiGuildDB and AmobiGuildDB.stats.honor or 0))
  if isCollector() then
    print(("|cffe9cb88阿莫比公會名單|r：自動重新載入%s（已經 %d 次%s）。"):format(
      AmobiGuildDB.reloadBlocked and "被遊戲擋下、已停用" or "每小時一次", AmobiGuildDB.stats.autoReloads or 0,
      AmobiGuildDB.reloadAt and ("，上次 " .. date("%m/%d %H:%M", AmobiGuildDB.reloadAt)) or ""))
  end
end
