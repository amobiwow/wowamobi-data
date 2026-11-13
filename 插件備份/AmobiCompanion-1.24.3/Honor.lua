-- 阿莫比小幫手：身邊玩家的 PvP 戰績（1.21.0；老闆 11/8：「問題是不可能全部人都裝我的UI 這樣好像無法有效撈取PVP資料
-- 有其他辦法嗎」→「繼續」）
--
-- 擊殺排行榜原本只收裝了小幫手的人自己拿到的榮譽擊殺（PvP.lua）。這個檔在你平常玩的時候，用遊戲的「觀察」（和在別人頭像上
-- 按右鍵「觀察」一樣，只是不打開視窗）查身邊玩家的 PvP 戰績：總榮譽擊殺、今天的榮譽擊殺、軍銜和軍銜進度
-- （永恆的觀察視窗 PvP 分頁顯示的那幾個數字：Blizzard_InspectUI/Camelot/InspectPVPFrame.lua 的 GetInspectHonorData）。
-- 對方不用裝小幫手：一個裝了的人走過主城，就能查到身邊幾十個人的戰績（和「看到的玩家」一樣的道理）。
--   * 誰：目標、滑鼠指到的、名條、隊伍和團隊成員；聯盟、部落都查（遊戲不讓觀察的 CanInspect 會說不行，就跳過）。
--   * 多久查一次：一次只查一個人、兩次至少隔 3 秒（伺服器會擋太快的觀察）；同一個人查到後 1 小時內不再查；
--     5 秒沒回覆（太遠、對方走掉）的 2 分鐘後才再試。
--   * 戰鬥中、有插件限制的時候不查；你自己打開觀察視窗（或正在等它打開）的時候不查，免得把你要看的人換掉。
--   * 只讀 INSPECT_HONOR_UPDATE 之後的數字（之前讀到的可能是上一個人的）；這段時間別的插件也觀察了別人
--     （INSPECT_READY 是別人的）就不算。
--   * 遊戲給的 9 個數字原樣傳（36 進位），網站照觀察視窗的用法解：第 1 個今天的榮譽擊殺、第 5 個總榮譽擊殺、
--     第 7 個軍銜、第 8、9 個軍銜進度（目前、下一級要多少）；其他幾個先存著，等開服實測知道是什麼。
--   * 「分享資料」的「看到的玩家」那一格關掉，這個也不查（同一個開關 seenShare）。
-- 每 10 分鐘包成一筆交給 Seen.lua 的 outbox（Share.lua 和看到的玩家一起密語傳給站長；站長自己的電腦直接交給 AmobiGuild）。
-- 同一個人 6 小時內數字都沒變就不再傳。
--
-- 一筆（傳給站長的內容）：R1^伺服器^你的陣營^一個人~一個人~…
--   一個人 名字:陣營（A／H）:等級:職業代碼:公會:時間:數字1,數字2,…,數字9（等級、時間、數字都是 36 進位；讀不到的空著）
-- 「/amobi 戰績」：馬上查目標一次、印出遊戲給的數字，和這個功能查了多少、沒查到的原因。

local _, ns = ...
local H = {}
ns.Honor = H

local GAP = 3                 -- 秒：兩次觀察至少隔 3 秒
local WAIT = 5                -- 秒：5 秒沒回覆就算了
local AGAIN = 3600            -- 秒：查到的人 1 小時內不再查
local RETRY = 120             -- 秒：沒回覆的 2 分鐘後再試
local CANT_AGAIN = 600        -- 秒：遊戲說不能觀察的 10 分鐘後再試
local MAX_CAND = 30           -- 等著查的最多幾個人
local SETTLE = 10 * 60        -- 秒：最早查到的已經 10 分鐘才包起來
local MAX_PENDING = 200
local MAX_BODY = 2000
local RESEND = 6 * 3600       -- 秒：6 小時內數字都沒變就不再傳
local SENT_KEEP = 2 * 86400
local KEEP = 3 * 86400
local NUMS = 9
local GROUP_UNITS = {}
for i = 1, 4 do GROUP_UNITS[#GROUP_UNITS + 1] = "party" .. i end
for i = 1, 40 do GROUP_UNITS[#GROUP_UNITS + 1] = "raid" .. i end

local db
local cand = {}               -- 等著查的：{ unit, guid, name, pri, at, l, k, g, fa }
local asked = {}              -- [名字] = 下一次可以再查的 GetTime()（只放記憶體）
local inflight                -- 正在等回覆的那一個
local lastAsk = -1e9
local ready                   -- 最近一次 INSPECT_READY：{ guid, at }
local groupSoon = false

local function now() return GetServerTime and GetServerTime() or time() end
local function str(v) return type(v) == "string" and not ns.Secret(v) and v ~= "" and v or nil end
local function num(v) return type(v) == "number" and not ns.Secret(v) and v or nil end
local function yes(v) return not ns.Secret(v) and v and true or false end
local function B36(n) return ns.Market.B36(n) end
local function count(key) db.stats[key] = (db.stats[key] or 0) + 1 end

local function clean(s)
  s = tostring(s or ""):gsub("[%^~:|,]", "")
  if #s > 60 then
    local j = 60
    while j > 0 and s:byte(j + 1) >= 0x80 and s:byte(j + 1) < 0xC0 do j = j - 1 end
    s = s:sub(1, j)
  end
  return s
end

local function realm() return clean(str(GetRealmName and GetRealmName()) or "") end
local function faction() return str(UnitFactionGroup("player")) end

function H.On() return ns.Seen ~= nil and ns.Seen.Active() end

-- 你自己打開了觀察視窗（或按了觀察、正在等它打開）：不查，免得把你要看的人換掉
local function userInspecting()
  local f = _G.InspectFrame
  if not f then return false end
  local ok, shown = pcall(f.IsShown, f)
  return (ok and shown == true) or f.unit ~= nil
end

local function busy()
  return ns.Restricted() ~= nil or userInspecting()
end

-- 一個玩家單位進到視線：記下來等著查。回傳 有沒有放進去, 原因（「/amobi 戰績」用）
function H.Consider(unit, pri, force)
  if not H.On() then return false, "「分享資料」的看到的玩家關著，或這個陣營沒有站長角色" end
  if type(unit) ~= "string" or not yes(UnitIsPlayer(unit)) then return false, "不是玩家" end
  if yes(UnitIsUnit(unit, "player")) then return false, "是你自己" end
  local guid = str(UnitGUID(unit))
  if not guid then return false, "讀不到這個人的編號" end
  local name = ns.Seen.NameOf(unit)
  if not name then return false, "名字讀不到或只有一段" end
  if not force and asked[name] and GetTime() < asked[name] then return false, "剛查過" end
  local theirs = str(UnitFactionGroup(unit))
  local fa = theirs == "Alliance" and "A" or theirs == "Horde" and "H" or nil
  if not fa then return false, "讀不到陣營" end
  local _, token = UnitClass(unit)
  local level = num(UnitLevel(unit))
  local c = { unit = unit, guid = guid, name = name, pri = pri, at = GetTime(), fa = fa, k = str(token) or "",
              l = level and level > 0 and level or 0, g = str((GetGuildInfo(unit))) or "", force = force }
  for i = #cand, 1, -1 do
    if cand[i].guid == guid or cand[i].unit == unit then table.remove(cand, i) end
  end
  table.insert(cand, c)
  if #cand > MAX_CAND then
    table.sort(cand, function(a, b) if a.pri ~= b.pri then return a.pri > b.pri end return a.at > b.at end)
    while #cand > MAX_CAND do table.remove(cand) end
  end
  return true, "等著查"
end

-- 下一個要查的：優先順序高的、最近看到的；單位已經換人的丟掉
local function pick()
  table.sort(cand, function(a, b) if a.pri ~= b.pri then return a.pri > b.pri end return a.at > b.at end)
  while #cand > 0 do
    local c = table.remove(cand, 1)
    if str(UnitGUID(c.unit)) == c.guid and (c.force or not asked[c.name] or GetTime() >= asked[c.name]) then
      if ns.Call(_G, "CanInspect", c.unit, false) then return c end
      count("cant")
      asked[c.name] = GetTime() + CANT_AGAIN
      if c.force then ns.Print("戰績：遊戲說不能觀察 " .. c.name .. "（太遠、敵對陣營或對方不讓人觀察）。") end
    end
  end
end

local function done(ok)
  local c = inflight
  inflight = nil
  if c then asked[c.name] = GetTime() + (ok and AGAIN or RETRY) end
end

local function vstr(v)
  local out = {}
  for i = 1, NUMS do out[i] = v[i] and B36(v[i]) or "" end
  return table.concat(out, ",")
end

-- INSPECT_HONOR_UPDATE：讀遊戲給的數字
local function read()
  local c = inflight
  if not c then return end
  count("honorEvent")
  if ready and ready.at >= c.asked and ready.guid ~= c.guid then        -- 這段時間別的插件觀察了別人
    count("other")
    return done(false)
  end
  local r = { ns.Call(_G, "GetInspectHonorData") }
  local v, any = {}, false
  for i = 1, NUMS do
    local x = r[i]
    if ns.Secret(x) then count("secret"); return done(false) end
    if type(x) == "number" and x >= 0 and x == math.floor(x) then v[i] = x; any = true end
  end
  if not any or v[5] == nil then count("noData"); return done(false) end
  count("got")
  local e = db.pending[c.name]
  if not e then count("people") end
  db.pending[c.name] = { fa = c.fa, l = c.l, k = clean(c.k), g = clean(c.g), v = vstr(v), t = now(),
                         t0 = e and (e.t0 or e.t) or now(), f = faction(), rl = realm() }
  db.last = { n = c.name, v = vstr(v), t = now() }
  if c.force then
    local raw = {}
    for i = 1, math.max(#r, NUMS) do raw[i] = tostring(r[i]) end
    ns.Print(("戰績：%s｜總榮譽擊殺 %d、今天 %d、軍銜 %d 級（進度 %d／%d）｜遊戲給的數字：%s"):format(
      c.name, v[5] or 0, v[1] or 0, v[7] or 0, v[8] or 0, v[9] or 0, table.concat(raw, ", ")))
  end
  done(true)
  ns.UI.Refresh("share")
end

-- 每秒：等太久的算了；沒有在等、隔夠久、沒在忙，就查下一個
local function pump()
  if not db then return end
  local t = GetTime()
  if inflight then
    if t - inflight.asked < WAIT then return end
    count("noReply")
    if inflight.force then ns.Print("戰績：" .. inflight.name .. " 5 秒沒有回覆（太遠或走掉了），站近一點再試。") end
    done(false)
  end
  if #cand == 0 or t - lastAsk < GAP or not H.On() or busy() then return end
  local c = pick()
  if not c then return end
  lastAsk, c.asked = t, t
  inflight = c
  count("asked")
  ns.Call(_G, "NotifyInspect", c.unit)
  ns.Call(_G, "RequestInspectHonorData")                                 -- 經典版要另外要；永恆沒有這個函式就跳過
end

local function lookGroup()
  groupSoon = false
  for _, u in ipairs(GROUP_UNITS) do
    if yes(UnitExists(u)) then H.Consider(u, 2) end
  end
end

-- ------------------------------------------------------------------ 包起來，交給 Seen.lua 和看到的玩家一起傳
local function prune()
  local t = now()
  for name, e in pairs(db.pending) do
    if type(e) ~= "table" or type(e.t) ~= "number" or t - e.t >= KEEP then db.pending[name] = nil end
  end
  for name, s in pairs(db.sent) do
    if type(s) ~= "table" or type(s.t) ~= "number" or t - s.t >= SENT_KEEP then db.sent[name] = nil end
  end
end

function H.Seal(force)
  local mine, rl = faction(), realm()
  if not mine then return 0 end
  local names, oldest = {}, nil
  for name, e in pairs(db.pending) do
    if e.f == mine and e.rl == rl then
      names[#names + 1] = name
      local t0 = e.t0 or e.t
      oldest = math.min(oldest or t0, t0)
    end
  end
  if #names == 0 or (not force and now() - oldest < SETTLE and #names < MAX_PENDING) then return 0 end
  table.sort(names)
  local head = "R1^" .. rl .. "^" .. mine .. "^"
  local parts, size, made = {}, 0, 0
  local function flush()
    if #parts == 0 then return end
    ns.Seen.Queue(head .. table.concat(parts, "~"))
    parts, size, made = {}, 0, made + 1
  end
  for _, name in ipairs(names) do
    local e = db.pending[name]
    db.pending[name] = nil
    local s = db.sent[name]
    if not (s and s.v == e.v and now() - s.t < RESEND) then
      local text = table.concat({ name, e.fa, B36(e.l or 0), e.k, e.g, B36(e.t), e.v }, ":")
      if size > 0 and size + #text + 1 > MAX_BODY then flush() end
      parts[#parts + 1] = text
      size = size + #text + 1
      db.sent[name] = { v = e.v, t = now() }
      count("sent")
    end
  end
  flush()
  prune()
  return made
end

function H.Count() return db and db.stats.got or 0 end

-- 「/amobi 戰績」
function H.Check()
  local s = db.stats
  if yes(UnitExists("target")) and yes(UnitIsPlayer("target")) then
    local ok, why = H.Consider("target", 9, true)
    if ok and inflight and inflight.guid == str(UnitGUID("target")) then
      inflight.force = true                                             -- 正在查的就是目標：回覆到了印出來
      for i = #cand, 1, -1 do if cand[i].guid == inflight.guid then table.remove(cand, i) end end
      ns.Print("戰績：查目標中，等遊戲回覆（幾秒）…")
    elseif ok and inflight then
      ns.Print("戰績：正在等上一個人的回覆，幾秒後查目標。")
    elseif ok then
      ns.Print("戰績：查目標中，等遊戲回覆（幾秒）…")
    else
      ns.Print("戰績：沒有查目標：" .. why)
    end
    if ok and busy() then ns.Print("戰績：現在不能查（" .. (ns.Restricted() or "你的觀察視窗開著") .. "），等一下會自己查。") end
  else
    ns.Print("戰績：先選一個玩家當目標，再打一次 /amobi 戰績。")
  end
  ns.Print(("戰績：這個帳號觀察了 %d 次、查到 %d 次（%d 人）、傳了 %d 人次；沒查到的：沒回覆 %d、遊戲說不能觀察 %d、沒有數字 %d、"
    .. "秘密值 %d、被別的觀察插隊 %d；收到戰績事件 %d 次")
    :format(s.asked or 0, s.got or 0, s.people or 0, s.sent or 0, s.noReply or 0, s.cant or 0, s.noData or 0, s.secret or 0,
            s.other or 0, s.honorEvent or 0))
  if db.last then
    ns.Print(("戰績：上一個查到的是 %s（%s）：%s"):format(db.last.n, date("%H:%M", db.last.t), db.last.v))
  end
end

function H.Init()
  ns.db.honor = type(ns.db.honor) == "table" and ns.db.honor or {}
  db = ns.db.honor
  for _, k in ipairs({ "pending", "sent", "stats" }) do
    if type(db[k]) ~= "table" then db[k] = {} end
  end
  prune()
  ns.On("PLAYER_TARGET_CHANGED", function() H.Consider("target", 3) end)
  ns.On("UPDATE_MOUSEOVER_UNIT", function() H.Consider("mouseover", 2) end)
  ns.On("NAME_PLATE_UNIT_ADDED", function(unit) H.Consider(unit, 1) end)
  ns.On("GROUP_ROSTER_UPDATE", function()
    if groupSoon then return end
    groupSoon = true
    C_Timer.After(2, function() ns.Try("honor:group", lookGroup) end)
  end)
  ns.On("INSPECT_READY", function(guid)
    if type(guid) == "string" and not ns.Secret(guid) then ready = { guid = guid, at = GetTime() } end
  end)
  ns.On("INSPECT_HONOR_UPDATE", function() read() end)
  C_Timer.NewTicker(1, function() ns.Try("honor:pump", pump) end)
  C_Timer.NewTicker(60, function()
    ns.Try("honor:tick", function()
      if H.On() and H.Seal(false) > 0 and ns.Share then ns.Share.Kick2() end
    end)
  end)
end

ns.Register(H)
