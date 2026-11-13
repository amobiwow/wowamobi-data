-- 阿莫比小幫手：看到的玩家（1.18.0；老闆 11/8：「關於人口普查，除了用who，我本身看到別人時有可能紀錄他的資料嗎」
-- 「撈到資料後，資料庫只要看到新資料就更新上去就好了，不可能永遠都靠我」）
--
-- 網站的人口普查原本只靠站長自己按 /who（DenizensTW）。這個檔在玩家平常玩的時候，記下身邊看得到的同陣營玩家：
--   名條（有打開玩家名條時）、滑鼠指到的、目標、隊伍和團隊成員；身邊的人升級時（UNIT_LEVEL）也再記一次
-- 記：名字、等級、職業、種族、公會、你當下所在的區域（小地圖上的地名，和 /who 的區域一樣）、時間。
--   * 只記自己陣營的：插件訊息不能跨陣營，敵方陣營的普查是另一台電腦（另一個陣營的站長角色）負責，
--     站長的電腦一次是整份換掉自己那個陣營的普查，混進另一個陣營的會把那邊蓋掉。
--   * 1.18.0 只記同伺服器的；1.19.0 起不比伺服器（老闆 11/8 公司那台開了友方名條還是 0 人：名字以前的條件都沒計數，
--     伺服器那一關是其中一個無聲擋掉的；永恆的名字全地區唯一，不會混到別人），只記下讀到的伺服器名（stats.lastServer）。
--   * 每一關擋掉的都計數（stats.foe 別的陣營、noLevel、noInfo），「/amobi 看到」對目標逐項檢查。
--   * 1.19.1（公司那台用 /amobi 看到 查到的，11/8）：永恆的 UnitName(unit) 把「主名 次名」拆成兩個回傳值，次名放在原本是
--     伺服器的第二個回傳值（例：「哭哭 不平衡」回傳 "哭哭", "不平衡"）。1.18 把次名當成別的伺服器、在計數前擋掉；1.19.0 只剩主名、
--     被當成一段名字。現在第二個回傳值不是自己的伺服器名，就接回「主名 次名」（W.FullName）；是自己的伺服器名才只有主名。
--   * 名字要是「主名 次名」兩段：永恆的角色名都是兩段，/who 也是；讀到只有一段的不記，免得同一個人被算成兩個。
--   * 讀不到等級（??）、名字是秘密值（副本裡、戰鬥中可能會）就不記。
--   * 公會讀不到（沒有公會或遊戲還沒問到）傳空的：站長那邊當作「不知道」，不會把原本記到的公會洗掉。
--   * 同一個人 6 小時內傳過、等級和公會都沒變就不再傳（主城一直看到同一批人）。
-- 1.19.0 公會名單（老闆 11/8：遊戲預設不顯示友方名條，只靠看到的記不到人 →「要，加公會名單」）：
--   在公會裡的話，每 5 分鐘請伺服器更新一次公會名單（只讀名單），把在線（在線、暫離、忙碌）的成員當成「看到的人」：
--   名字、等級、職業（classID）、種族（race → C_CreatureInfo.GetRaceInfo 的名字）、公會、所在地區（公會名單的地區是大地區）。
--   公會只有同陣營的人，所以一樣只算自己陣營。手機上線（OnlineMobile）的不算。
-- 由 Share.lua 傳給阿莫比站長的角色：和物品來源一樣不用在公會裡，站長不在線就先存著（3 天）。站長的 AmobiGuild 收到後
-- 併進「看到的玩家」名單，站長的電腦自動上傳時和 /who 的普查一起算（網站上的角色名一樣換成匿名代號）。
-- 「分享資料」分頁可以關（seenShare，預設開）。只讀遊戲給的資訊，不會替你選目標、查詢或做任何事。
--
-- 1.21.0：Honor.lua（PvP 戰績）讀名字用 W.NameOf，包好的 R1 用 W.Queue 放進同一個 outbox 一起傳。
-- 一筆資料（傳給站長的內容）：W1^伺服器^陣營^一個人~一個人~…
--   一個人 名字:等級:職業代碼:職業:種族:公會:區域:時間（等級、時間是 36 進位；時間是伺服器時間；公會讀不到是空的）

local _, ns = ...
local W = {}
ns.Seen = W

local SETTLE = 10 * 60        -- 秒：最早記到的人已經 10 分鐘才包起來傳（同一段時間看到的一起傳）
local MAX_BODY = 2000         -- 一筆大約多大就換下一筆（約 10 則插件訊息、二三十個人）
local MAX_PENDING = 400       -- 還沒包的最多幾個人，再多就先包起來
local RESEND = 6 * 3600       -- 秒：同一個人 6 小時內傳過、等級公會都沒變就不再傳
local KEEP = 3 * 86400        -- 秒：包好沒傳出去的最多留 3 天
local SENT_KEEP = 2 * 86400   -- 秒：「傳過誰」記 2 天
local MAX_OUTBOX = 200
local LOOK_GAP = 60           -- 秒：同一個人一分鐘內只讀一次（主城的名條很多）
local ROSTER_EVERY = 5 * 60   -- 秒：最多 5 分鐘請伺服器更新一次公會名單、讀一次
local ROSTER_READ_GAP = 60    -- 秒：公會名單更新的事件很多，最多一分鐘讀一次
local GROUP_UNITS = {}
for i = 1, 4 do GROUP_UNITS[#GROUP_UNITS + 1] = "party" .. i end
for i = 1, 40 do GROUP_UNITS[#GROUP_UNITS + 1] = "raid" .. i end

local db
local looked = {}             -- [名字] = GetTime()（只放記憶體）
local groupSoon = false
local rosterAsked, rosterRead = -1e9, -1e9

local function now() return GetServerTime and GetServerTime() or time() end
local function str(v) return type(v) == "string" and not ns.Secret(v) and v ~= "" and v or nil end
local function num(v) return type(v) == "number" and not ns.Secret(v) and v or nil end
local function yes(v) return not ns.Secret(v) and v and true or false end
local function B36(n) return ns.Market.B36(n) end
local function isCollector() return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("AmobiGuild") end

function W.On() return ns.db.settings.seenShare ~= false end
-- 這個陣營有站長的角色才記（傳得出去）
function W.Active() return W.On() and ns.PvP ~= nil and #ns.PvP.Collectors() > 0 end

-- 傳送用的分隔符號拿掉；最多 60 位元組，不在中文字中間切
local function clean(s)
  s = tostring(s or ""):gsub("[%^~:|]", "")
  if #s > 60 then
    local j = 60
    while j > 0 and s:byte(j + 1) >= 0x80 and s:byte(j + 1) < 0xC0 do j = j - 1 end
    s = s:sub(1, j)
  end
  return s
end

local function realm() return clean(str(GetRealmName and GetRealmName()) or "") end
local function faction() return str(UnitFactionGroup("player")) end

local function count(key)
  db.stats[key] = (db.stats[key] or 0) + 1
end

-- UnitName 的兩個回傳值 → 「主名 次名」（永恆：第二個是次名；正式版的跨伺服器才是伺服器名）
function W.FullName(name, second)
  name, second = str(name), str(second)
  if not name then return nil end
  if second and second ~= str(GetNormalizedRealmName and GetNormalizedRealmName()) and second ~= str(GetRealmName and GetRealmName())
     and not name:find(" ", 1, true) then
    return name .. " " .. second
  end
  return name
end

-- 一個玩家單位的「主名 次名」；讀不到或只有一段回傳 nil（1.21.0 Honor.lua 用：讀名字只在這個檔）
function W.NameOf(unit)
  local name = W.FullName(UnitName(unit))
  return name and name:find(" ", 1, true) and name or nil
end

-- 記一個人（看到的、公會名單的共用）
-- t 是最後看到的時間（傳出去的）；t0 是第一次放進來的時間（10 分鐘包一次用它算：一直看到同一個人也要包得出去，1.18 的錯）
local function add(name, level, token, cls, race, guild, area, mine)
  local e = db.pending[name]
  if not e then count("people") end
  db.pending[name] = { l = level, k = clean(token), c = clean(cls or ""), r = clean(race), g = clean(guild or ""), a = clean(area or ""),
                       t = now(), t0 = e and (e.t0 or e.t) or now(), f = mine, rl = realm() }
end

-- 讀一個單位，回傳 記了沒有, 原因（「/amobi 看到」用）。force：身邊的人剛升級，不管一分鐘內讀過沒有
function W.Look(unit, force)
  if not W.Active() then return false, "「分享資料」的看到的玩家關著，或這個陣營沒有站長角色" end
  if type(unit) ~= "string" then return false, "沒有單位" end
  if not yes(UnitIsPlayer(unit)) then return false, "不是玩家" end
  if yes(UnitIsUnit(unit, "player")) then return false, "是你自己" end
  count("players")
  local mine, theirs = faction(), str(UnitFactionGroup(unit))
  if not mine or theirs ~= mine then count("foe"); return false, "不是你的陣營（" .. tostring(theirs) .. "）" end
  local name = W.FullName(UnitName(unit))
  if not name then count("secret"); return false, "名字讀不到（秘密值）" end
  if not name:find(" ", 1, true) then count("short"); return false, "名字只有一段（" .. name .. "）" end
  local t = GetTime()
  if not force and looked[name] and t - looked[name] < LOOK_GAP then return false, "一分鐘內讀過" end
  local level = num(UnitLevel(unit))
  if not level or level <= 0 then count("noLevel"); return false, "讀不到等級" end
  local cls, token = UnitClass(unit)
  cls, token = str(cls), str(token)
  local race = str((UnitRace(unit)))
  if not token or not race then count("noInfo"); return false, "讀不到職業或種族" end
  looked[name] = t
  local guild = str((GetGuildInfo(unit))) or ""
  local area = str(GetMinimapZoneText and GetMinimapZoneText()) or str(GetRealZoneText and GetRealZoneText()) or ""
  add(name, level, token, cls, race, guild, area, mine)
  ns.UI.Refresh("share")
  return true, "記下來了"
end

-- ------------------------------------------------------------------ 公會名單（1.19.0）
local function online(p)
  local E = Enum and Enum.ClubMemberPresence
  if E then return p == E.Online or p == E.Away or p == E.Busy end
  return p == 1 or p == 4 or p == 5
end

-- 讀公會名單裡在線的人；回傳記了幾人（讀不到回傳 nil）
function W.ReadRoster()
  if not W.Active() or ns.Restricted() or not (IsInGuild and IsInGuild()) then return nil end
  local mine = faction()
  if not mine then return nil end
  local clubId = ns.Call(C_Club, "GetGuildClubId")
  if clubId == nil or ns.Secret(clubId) then return nil end
  local ids = ns.Call(C_Club, "GetClubMembers", clubId)
  if type(ids) ~= "table" or ns.Secret(ids) then return nil end
  rosterRead = GetTime()
  local guild = str((GetGuildInfo("player"))) or ""
  local n = 0
  for _, mid in ipairs(ids) do
    local info = ns.Call(C_Club, "GetMemberInfo", clubId, mid)
    if type(info) == "table" and not ns.Secret(info) and online(num(info.presence)) then
      local name = str(info.name)
      name = name and (name:gsub("%-.*$", ""))
      local level, classID, raceID = num(info.level), num(info.classID), num(info.race)
      if name and name:find(" ", 1, true) and level and level > 0 and classID and raceID then
        local cls, token = GetClassInfo(classID)
        local r = C_CreatureInfo and ns.Call(C_CreatureInfo, "GetRaceInfo", raceID)
        local race = type(r) == "table" and not ns.Secret(r) and str(r.raceName)
        if str(token) and race then
          add(name, level, str(token), str(cls), race, guild, str(info.zone) or "", mine)
          n = n + 1
        end
      end
    end
  end
  count("roster")
  db.stats.rosterLast = n
  if n > 0 then ns.UI.Refresh("share") end
  return n
end

-- 請伺服器更新公會名單（只讀名單；GUILD_ROSTER_UPDATE 到了再讀），5 秒後沒等到事件也讀一次
local function askRoster()
  if not W.Active() or ns.Restricted() or not (IsInGuild and IsInGuild()) then return end
  if GetTime() - rosterAsked < ROSTER_EVERY then return end
  rosterAsked = GetTime()
  ns.Call(C_GuildInfo, "GuildRoster")
  C_Timer.After(5, function()
    if GetTime() - rosterRead > 5 then ns.Try("seen:roster", W.ReadRoster) end
  end)
end

-- 「/amobi 看到」：對目標（沒有目標就滑鼠指著的）逐項檢查，印出這個功能記到多少、擋掉多少
function W.Check()
  local s = db.stats
  local unit = yes(UnitExists("target")) and "target" or (yes(UnitExists("mouseover")) and "mouseover" or nil)
  if unit then
    local main, second = UnitName(unit)
    ns.Print(("看到的玩家：%s｜遊戲給的名字「%s」「%s」｜玩家 %s｜他的陣營 %s、你的 %s｜你的伺服器「%s」｜等級 %s｜種族 %s"):format(
      tostring(W.FullName(main, second) or "（名字是秘密值）"), ns.Secret(main) and "秘密值" or tostring(main),
      ns.Secret(second) and "秘密值" or tostring(second or ""), tostring(yes(UnitIsPlayer(unit))),
      tostring(str(UnitFactionGroup(unit))), tostring(faction()),
      tostring(str(GetRealmName and GetRealmName())), tostring(num(UnitLevel(unit))), tostring(str((UnitRace(unit))))))
    local ok, why = W.Look(unit, true)
    ns.Print("看到的玩家：" .. (ok and "|cff60ff60記下來了|r" or ("|cffff6060沒記：|r" .. why)))
  else
    ns.Print("看到的玩家：先選一個玩家當目標（或滑鼠指著），再打一次 /amobi 看到。")
  end
  ns.Print(("看到的玩家：這個帳號讀到玩家 %d 次、記了 %d 人次、傳了 %d 人次；沒記的：別的陣營 %d、名字只有一段 %d、名字讀不到 %d、讀不到等級 %d、"
    .. "讀不到職業種族 %d；公會名單讀了 %d 次（上次 %d 人在線）"):format(
    s.players or 0, s.people or 0, s.sent or 0, s.foe or 0, s.short or 0, s.secret or 0, s.noLevel or 0, s.noInfo or 0,
    s.roster or 0, s.rosterLast or 0))
end

local function lookGroup()
  groupSoon = false
  for _, u in ipairs(GROUP_UNITS) do
    if yes(UnitExists(u)) then W.Look(u) end
  end
end

-- ------------------------------------------------------------------ 包起來、交給 Share.lua
local function prune()
  local keep, t = {}, now()
  for _, o in ipairs(db.outbox) do
    if type(o) == "table" and type(o.t) == "number" and t - o.t < KEEP then keep[#keep + 1] = o end
  end
  while #keep > MAX_OUTBOX do table.remove(keep, 1) end
  db.outbox = keep
  for name, e in pairs(db.pending) do
    if type(e) ~= "table" or type(e.t) ~= "number" or t - e.t >= KEEP then db.pending[name] = nil end
  end
  for name, s in pairs(db.sent) do
    if type(s) ~= "table" or type(s.t) ~= "number" or t - s.t >= SENT_KEEP then db.sent[name] = nil end
  end
end

local function here(e, mine, rl) return e.f == mine and e.rl == rl end

-- 站長自己的電腦（裝了 AmobiGuild）：包好的直接併進公會名單插件，不用傳
local function storeHere()
  if not (isCollector() and type(AmobiGuild_Store) == "function") then return end
  for _, o in ipairs(W.Outbox(true)) do
    local ok, stored = pcall(AmobiGuild_Store, o.body)
    if ok and stored then W.MarkSent(o) end
  end
end

-- 這個陣營、伺服器記到的、最早一個已經 10 分鐘（或人很多、force）：包成幾筆 W1 放進 outbox。回傳包了幾筆
function W.Seal(force)
  local mine, rl = faction(), realm()
  if not mine then return 0 end
  local names, oldest = {}, nil
  for name, e in pairs(db.pending) do
    if here(e, mine, rl) then
      names[#names + 1] = name
      local t0 = e.t0 or e.t
      oldest = math.min(oldest or t0, t0)
    end
  end
  if #names == 0 or (not force and now() - oldest < SETTLE and #names < MAX_PENDING) then return 0 end
  table.sort(names)
  local head = "W1^" .. rl .. "^" .. mine .. "^"
  local parts, size, made = {}, 0, 0
  local function flush()
    if #parts == 0 then return end
    local body = head .. table.concat(parts, "~")
    table.insert(db.outbox, { id = ns.Share.Hash(body), body = body, t = now(), f = mine, rl = rl })
    parts, size, made = {}, 0, made + 1
  end
  for _, name in ipairs(names) do
    local e = db.pending[name]
    db.pending[name] = nil
    local s = db.sent[name]
    local same = s and s.l == e.l and (e.g == "" or s.g == e.g) and now() - s.t < RESEND
    if not same then
      local text = table.concat({ name, B36(e.l), e.k, e.c, e.r, e.g, e.a, B36(e.t) }, ":")
      if size > 0 and size + #text + 1 > MAX_BODY then flush() end
      parts[#parts + 1] = text
      size = size + #text + 1
      db.sent[name] = { l = e.l, g = e.g ~= "" and e.g or (s and s.g) or "", t = now() }
      count("sent")
    end
  end
  flush()
  prune()
  storeHere()
  return made
end

-- 別的功能包好的一筆（1.21.0 Honor.lua 的 PvP 戰績 R1），放進同一個 outbox 和看到的玩家一起傳
function W.Queue(body)
  local mine, rl = faction(), realm()
  if not mine or type(body) ~= "string" then return end
  table.insert(db.outbox, { id = ns.Share.Hash(body), body = body, t = now(), f = mine, rl = rl })
  prune()
  storeHere()
end

-- 這個陣營、伺服器包好、還沒傳出去的（Share.lua 用；先看要不要包）
function W.Outbox(noSeal)
  if not noSeal then W.Seal(false) end
  local mine, rl, out = faction(), realm(), {}
  for _, o in ipairs(db.outbox) do
    if here(o, mine, rl) then out[#out + 1] = o end
  end
  return out
end

function W.MarkSent(o)
  for i = #db.outbox, 1, -1 do
    if db.outbox[i] == o or db.outbox[i].id == o.id then table.remove(db.outbox, i) end
  end
  db.sentN = (db.sentN or 0) + 1
  ns.UI.Refresh("share")
end

function W.Waiting()
  local mine, rl, n = faction(), realm(), 0
  for _, e in pairs(db.pending) do if here(e, mine, rl) then n = n + 1 end end
  return n, #W.Outbox(true)
end

function W.Status()
  local pend, box = W.Waiting()
  local honor = ns.Honor and ns.Honor.Count() or 0
  return ("這個帳號記了 %d 人次、傳了 %d 人次%s%s"):format(db.stats.people or 0, db.stats.sent or 0,
    honor > 0 and ("、查到 %d 次 PvP 戰績"):format(honor) or "",
    (pend + box) > 0 and ("；%d 人還沒包、%d 筆包好了等著傳"):format(pend, box) or "")
end

function W.Init()
  ns.db.seen = type(ns.db.seen) == "table" and ns.db.seen or {}
  db = ns.db.seen
  for _, k in ipairs({ "pending", "outbox", "sent", "stats" }) do
    if type(db[k]) ~= "table" then db[k] = {} end
  end
  prune()
  ns.On("NAME_PLATE_UNIT_ADDED", function(unit) W.Look(unit) end)
  ns.On("UPDATE_MOUSEOVER_UNIT", function() W.Look("mouseover") end)
  ns.On("PLAYER_TARGET_CHANGED", function() W.Look("target") end)
  ns.On("UNIT_LEVEL", function(unit) W.Look(unit, true) end)
  ns.On("GUILD_ROSTER_UPDATE", function()
    if GetTime() - rosterRead >= ROSTER_READ_GAP then ns.Try("seen:roster", W.ReadRoster) end
  end)
  ns.On("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(20, function() ns.Try("seen:askroster", askRoster) end)
  end)
  ns.On("GROUP_ROSTER_UPDATE", function()
    if groupSoon then return end
    groupSoon = true
    C_Timer.After(2, function() ns.Try("seen:group", lookGroup) end)
  end)
  C_Timer.NewTicker(60, function()
    ns.Try("seen:tick", function()
      askRoster()
      if W.Active() and W.Seal(false) > 0 and ns.Share then ns.Share.Kick2() end
    end)
  end)
  -- 很久沒用到的「一分鐘內讀過」清掉（只放記憶體）
  C_Timer.NewTicker(10 * 60, function()
    local t = GetTime()
    for name, at in pairs(looked) do if t - at > LOOK_GAP then looked[name] = nil end end
  end)
end

ns.Register(W)
