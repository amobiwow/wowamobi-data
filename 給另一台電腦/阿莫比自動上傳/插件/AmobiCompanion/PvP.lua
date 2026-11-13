-- 阿莫比小幫手：榮譽擊殺記錄（1.7.0；1.7.1 多記職業、等級、公會、區域；1.7.2 部落也收；老闆 10/26）
--
-- 「只要安裝 ui，他們不需要主動幹嘛」「不用抓誰被殺，只抓殺了誰」；只針對阿莫比所在的亞服 PvP 規則伺服器：
-- 拿到榮譽擊殺時，記下對方是誰，傳給阿莫比站長的角色（聯盟傳聯盟的、部落傳部落的：插件訊息不能跨陣營），
-- 站長的電腦（阿莫比公會名單插件 AmobiGuild）收進存檔，登出後自動上傳到網站（tools/auto_upload.py → POST /api/pvp）。
-- 1.7.2 老闆 10/26 晚：「其實我那個號可以接手部落資料自動上傳，你可以改ui。部落的資料傳到 大名『阿莫比』小名『阿莫』。這樣就全面了」。
--
-- 怎麼知道拿到榮譽擊殺：遊戲的榮譽訊息（CHAT_MSG_COMBAT_HONOR_GAIN，聊天框那行「X死亡（榮譽擊殺：軍銜）。你獲得N點榮譽值。」）。
--   * 戰鬥紀錄（COMBAT_LOG_EVENT_UNFILTERED）永恆對插件有限制、死亡回顧也沒有欄位，所以只看這行字。
--   * 樣式照遊戲自己的字串（COMBATLOG_HONORGAIN、沒有軍銜的、有加成的），不寫死中文；文字是秘密值就不讀（記一筆 missed）。
--   * 這行不會寫是誰補最後一刀，整隊都會收到：所以記的是「拿到榮譽擊殺」，同一個擊殺會有好幾個人回報，網站合併。
-- 每筆：伺服器時間、伺服器名稱、地圖（C_Map 的地圖編號、在戰場或副本裡另記副本地圖編號）、區域名稱、對方名字、軍銜、榮譽、
--   隊伍人數，和自己的職業（英文代號）、等級、公會名（1.7.1，排行用職業顏色和公會榜；老闆 10/26：排行顯示真名）。
--   回報的人是誰，站長那邊從密語的寄件人知道（插件不另外寫自己的名字）。
--   存檔是整個帳號共用的：每筆記下是哪個角色（UnitGUID），只傳現在登入的這個角色記的，寄件人才對得上。
-- 聯盟、部落都記（陣營寫在每一批的開頭）；分享資料分頁可以關（預設開）。不會替你做任何事：只讀這一行訊息。
-- 傳法在 Share.lua：不管有沒有公會，都用密語的插件訊息傳給下面寫好的站長角色名；站長不在線就先存著，之後再問。

local _, ns = ...
local P = {}
ns.PvP = P

-- 站長的角色，照陣營（老闆 10/26：聯盟名字「谷阿莫」、次要名字「阿莫」，10/28 搶先創角後確認）。
-- 部落 1.13.1 起改傳公司那台電腦的「阿莫谷」（次要名字「摩寧」；老闆 11/5：「部落那邊的資料都是傳回給這個角色」），原本是「阿莫比」。
-- 次要名字（阿莫、摩寧）不是另一個角色：只問第一段名字。永恆的名字有兩段，密語要不要寫次要名字開服再確認；
-- 回答的寄件人寫成「名字 次要名字-伺服器」也認（只比第一段）。可以多放幾個備用的角色，照順序問。
P.COLLECTORS = { Alliance = { "谷阿莫" }, Horde = { "阿莫谷" } }

-- 這個陣營的站長角色（沒有的陣營不記）
function P.Collectors() return P.COLLECTORS[UnitFactionGroup("player") or ""] or {} end

local KEEP = 14 * 86400       -- 秒：沒傳出去的最多留 14 天
local KEEP_SENT = 3 * 86400   -- 秒：傳出去（站長回「收到」）的留 3 天就刪
local MAX_KILLS = 3000

local db
local formats

local function now() return GetServerTime and GetServerTime() or time() end
function P.On() return ns.db.settings.pvpShare ~= false end

-- 遊戲的格式字串 → 比對樣式：%s 對任何字、%d 對數字；位置參數（%2$s）照位置對到欄位；回傳 樣式、每個擷取是哪個欄位
local MAGIC = "[%^%$%(%)%.%[%]%*%+%-%?]"
function P.Pattern(fmt, fields)
  local function esc(x) return (x:gsub(MAGIC, "%%%0")) end
  local out, order, n, i = {}, {}, 0, 1
  while true do
    local s = fmt:find("%", i, true)
    if not s then
      out[#out + 1] = esc(fmt:sub(i))
      break
    end
    out[#out + 1] = esc(fmt:sub(i, s - 1))
    if fmt:sub(s + 1, s + 1) == "%" then          -- 「%%」是一個百分比符號
      out[#out + 1] = "%%"
      i = s + 2
    else
      local pos, dollar, spec, after = fmt:match("^(%d*)(%$?)([sd])()", s + 1)
      if spec then
        n = n + 1
        order[#order + 1] = fields[(dollar == "$" and tonumber(pos)) or n] or false
        out[#out + 1] = spec == "d" and "(%d+)" or "(.-)"
        i = after
      else
        out[#out + 1] = "%%"
        i = s + 1
      end
    end
  end
  return "^" .. table.concat(out) .. "$", order
end

local FORMATS = {   -- 長的（有加成的）先比
  { "COMBATLOG_HONORGAIN_EXHAUSTION1", { "name", "rank", "honor" } },
  { "COMBATLOG_HONORGAIN_NO_RANK_EXHAUSTION1", { "name", "honor" } },
  { "COMBATLOG_HONORGAIN", { "name", "rank", "honor" } },
  { "COMBATLOG_HONORGAIN_NO_RANK", { "name", "honor" } },
}

local function buildFormats()
  formats = {}
  for _, f in ipairs(FORMATS) do
    local fmt = _G[f[1]]
    if type(fmt) == "string" and fmt ~= "" then
      local pattern, order = P.Pattern(fmt, f[2])
      formats[#formats + 1] = { pattern = pattern, order = order }
    end
  end
end

-- 名字、軍銜、區域、公會裡不能有傳送用的分隔符號（^ , : ~ |）；最多 90 位元組，不在中文字中間切
local function clean(s)
  s = tostring(s or ""):gsub("[%^,:~|]", "")
  if #s > 90 then
    local j = 90
    while j > 0 and s:byte(j + 1) >= 0x80 and s:byte(j + 1) < 0xC0 do j = j - 1 end
    s = s:sub(1, j)
  end
  return s
end

-- 一行榮譽訊息 → { name, rank, honor }；不是榮譽擊殺回傳 nil
function P.Parse(text)
  if not formats then buildFormats() end
  for _, f in ipairs(formats) do
    local caps = { text:match(f.pattern) }
    if caps[1] then
      local k = {}
      for i, field in ipairs(f.order) do
        if field then k[field] = caps[i] end
      end
      local name = clean(k.name)
      if name ~= "" then
        return { name = name, rank = clean(k.rank), honor = tonumber(k.honor) or 0 }
      end
    end
  end
end

local function mapIDs()
  local map = ns.Call(C_Map, "GetBestMapForUnit", "player")
  if ns.Secret(map) or type(map) ~= "number" then map = 0 end
  local _, kind, _, _, _, _, _, inst = GetInstanceInfo()
  if ns.Secret(inst) or type(inst) ~= "number" or kind == "none" then inst = 0 end
  return map, inst
end

local function str(v) return type(v) == "string" and not ns.Secret(v) and v or nil end

local function zoneName(map)
  local z = str(GetRealZoneText and GetRealZoneText())
  if (not z or z == "") and map > 0 then
    local info = ns.Call(C_Map, "GetMapInfo", map)
    z = type(info) == "table" and str(info.name)
  end
  return clean(z)
end

-- 自己這個角色（存檔整個帳號共用，用 GUID 分）
function P.Me() return str(UnitGUID("player")) end

local function mine(k) return k.who == nil or k.who == P.Me() end

function P.Record(text)
  if not P.On() then return end
  if ns.Secret(text) or type(text) ~= "string" then
    db.missed = (db.missed or 0) + 1
    return
  end
  local faction = UnitFactionGroup("player")
  if not P.COLLECTORS[faction or ""] then return end                    -- 聯盟、部落（有站長角色的陣營）
  local k = P.Parse(text)
  if not k then return end
  k.faction = faction
  local size = GetNumGroupMembers and GetNumGroupMembers() or 0
  if ns.Secret(size) or type(size) ~= "number" then size = 0 end
  k.t, k.realm, k.size = now(), clean(GetRealmName()), size
  k.map, k.inst = mapIDs()
  k.zone = zoneName(k.map)
  local level = UnitLevel("player")
  k.level = type(level) == "number" and not ns.Secret(level) and level or 0
  k.class = clean(str(select(2, UnitClass("player"))))
  k.guild = clean(str(IsInGuild and IsInGuild() and GetGuildInfo("player")) or "")
  k.who = P.Me()
  table.insert(db.kills, k)
  while #db.kills > MAX_KILLS do table.remove(db.kills, 1) end
  db.total = (db.total or 0) + 1
  if ns.Share and ns.Share.KillAdded then ns.Share.KillAdded(k) end
  ns.UI.Refresh("share")
end

-- 這個角色還沒傳出去的（照時間；別的角色記的等那個角色登入再傳）
function P.Unsent()
  local out = {}
  for _, k in ipairs(db.kills) do
    if not k.sent and mine(k) then out[#out + 1] = k end
  end
  return out
end

function P.MarkSent(list)
  for _, k in ipairs(list) do k.sent = now() end
  P.Prune()
end

function P.Prune()
  local keep, t = {}, now()
  for _, k in ipairs(db.kills) do
    if type(k) == "table" and type(k.t) == "number" and t - k.t < KEEP and not (k.sent and t - k.sent > KEEP_SENT) then
      keep[#keep + 1] = k
    end
  end
  db.kills = keep
end

-- 同一批的：同伺服器、同陣營、同職業、同公會（Body 的開頭；1.7.1 以前記的沒有陣營，那時只有聯盟）
function P.Group(k)
  return (k.realm or "") .. "^" .. (k.faction or "Alliance") .. "^" .. (k.class or "") .. "^" .. (k.guild or "")
end

-- 一批擊殺的內容（傳給站長；list 是同一個 P.Group）：
--   H3^伺服器^陣營^職業^公會^時間:地圖:副本地圖:區域:對方名字:軍銜:榮譽:隊伍人數:等級,…（數字是 36 進位；
--   1.7.1 的 H2 沒有陣營、1.7.0 的 H1 還沒有職業公會區域等級，格式見 site/scripts/upload-pvp.mjs）
function P.Body(list)
  local B36 = ns.Market.B36
  local rows = {}
  for _, k in ipairs(list) do
    rows[#rows + 1] = table.concat({ B36(k.t), B36(k.map or 0), B36(k.inst or 0), k.zone or "", k.name, k.rank or "",
                                     B36(k.honor or 0), B36(k.size or 0), B36(k.level or 0) }, ":")
  end
  return "H3^" .. P.Group(list[1] or {}) .. "^" .. table.concat(rows, ",")
end

function P.Status()
  local unsent = #P.Unsent()
  return ("這個帳號記了 %d 次%s%s"):format(db.total or 0, unsent > 0 and ("，還有 %d 次等著傳"):format(unsent) or "",
    (db.missed or 0) > 0 and ("；%d 次訊息讀不到"):format(db.missed) or "")
end

-- 名字的第一段（去掉「-伺服器」和次要名字）
function P.MainName(name)
  if type(name) ~= "string" or ns.Secret(name) then return nil end
  return (name:gsub("%-.*$", "")):match("^%s*(%S+)")
end

-- 是不是這個陣營的站長角色
function P.IsCollectorName(name)
  local main = P.MainName(name)
  if not main then return false end
  for _, n in ipairs(P.Collectors()) do
    if n == main then return true end
  end
  return false
end

function P.Init()
  ns.db.pvp = type(ns.db.pvp) == "table" and ns.db.pvp or {}
  db = ns.db.pvp
  db.kills = type(db.kills) == "table" and db.kills or {}
  P.Prune()
  ns.On("CHAT_MSG_COMBAT_HONOR_GAIN", function(text) P.Record(text) end)
end
ns.Register(P)
