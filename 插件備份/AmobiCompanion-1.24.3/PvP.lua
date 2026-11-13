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
--
-- 1.20.0（老闆 11/8：兩台存檔的擊殺都是 0，連自己殺的都沒記；「就參考剛剛阿，要能先撈到人」＝照看到的玩家那樣先查出卡在哪）：
--   * 每一關都計數（db.stats：lines 收到榮譽訊息、matched、unmatched、kb 最後一擊…），對不上的訊息原文留最後 5 句（db.unmatched），
--     「/amobi 擊殺」印出來，在遊戲裡殺一個人就知道卡在哪一關。
--   * 比對前先拿掉聊天框的顏色碼、玩家連結（|Hplayer:…|h[名字]|h），名字外面的 [ ] 也拿掉。
--   * 第二個來源：PARTY_KILL（UnitDocumentation：attackerGUID、targetGUID）——你打出最後一擊、死的是玩家，就用
--     GetPlayerInfoByGUID 讀對方的名字（永恆的名字分兩段給：主名、次名，接回「主名 次名」，見 P.JoinName）。
--     只算自己打的（隊友有裝小幫手會自己回報）。和榮譽訊息是同一個擊殺（30 秒內、主名一樣）就合併成一筆，不會算兩次。
--   * PLAYER_PVP_KILLS_CHANGED：遊戲的榮譽擊殺數變了，計數、讀 GetPVPSessionStats（這次登入幾個）給「/amobi 擊殺」看。

local _, ns = ...
local P = {}
ns.PvP = P

-- 站長的角色，照陣營。聯盟 1.13.2 起改傳家裡那台的「阿莫谷」（次要名字「拉克」；老闆 11/5 開服玩的是這隻，問了說「改成阿莫谷」），原本是「谷阿莫」。
-- 部落 1.13.1 起改傳公司那台電腦的「阿莫谷」（次要名字「摩寧」；老闆 11/5：「部落那邊的資料都是傳回給這個角色」），原本是「阿莫比」。
-- 1.18.1 改寫全名（大名＋空白＋次名）：永恆的角色名是「大名 次名」整串（公會名單、插件訊息的寄件人都是這樣，中間是半形空白），
-- 兩隻站長角色大名都叫「阿莫谷」、同一個伺服器，只密「阿莫谷」遊戲對不到人：開服到 11/8 部落一筆都沒進網站
-- （amobi-site 查 D1 和 AmobiGuild 存檔；老闆 11/8：「好，請它改」）。可以多放幾個備用的角色，照順序問。
-- 1.24.2 聯盟改傳「阿莫谷 奈特」：家裡那台另開一個帳號專門收（老闆 11/9：「把阿莫谷拉克改過去」），拉克拿到別台電腦玩、不裝 AmobiGuild。
-- 公會裡的人不看名字（站長在公會頻道說一聲就認），所以舊版的公會成員也會自動改傳奈特；這個名單只管不在公會、直接密語問的。
P.COLLECTORS = { Alliance = { "阿莫谷 奈特" }, Horde = { "阿莫谷 摩寧" } }

-- 這個陣營的站長角色（沒有的陣營不記）
function P.Collectors() return P.COLLECTORS[UnitFactionGroup("player") or ""] or {} end

local KEEP = 14 * 86400       -- 秒：沒傳出去的最多留 14 天
local KEEP_SENT = 3 * 86400   -- 秒：傳出去（站長回「收到」）的留 3 天就刪
local MAX_KILLS = 3000

local db
local formats
local recent = {}              -- [主名] = { k = 擊殺, at = GetTime() }：榮譽訊息和最後一擊是同一個擊殺時合併
local MERGE_SECS = 30
local MAX_UNMATCHED = 5

local function now() return GetServerTime and GetServerTime() or time() end
local function str(v) return type(v) == "string" and not ns.Secret(v) and v or nil end
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

-- 聊天框的格式碼拿掉：顏色（|cAARRGGBB …|r）、連結（|H…|h顯示的字|h）
function P.Plain(text)
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"))
end

-- 永恆的 UnitName／GetPlayerInfoByGUID 把「主名 次名」分兩個值給（次名在原本伺服器的位置）：接回來；是自己的伺服器名才不接
function P.JoinName(name, second)
  name, second = str(name), str(second)
  if not name or name == "" then return nil end
  if second and second ~= "" and not name:find(" ", 1, true) and second ~= str(GetNormalizedRealmName and GetNormalizedRealmName())
     and second ~= str(GetRealmName and GetRealmName()) then
    return name .. " " .. second
  end
  return name
end

-- 一行榮譽訊息 → { name, rank, honor }；不是榮譽擊殺回傳 nil
function P.Parse(text)
  if not formats then buildFormats() end
  text = P.Plain(text)
  for _, f in ipairs(formats) do
    local caps = { text:match(f.pattern) }
    if caps[1] then
      local k = {}
      for i, field in ipairs(f.order) do
        if field then k[field] = caps[i] end
      end
      local name = clean((k.name or ""):gsub("^%[(.*)%]$", "%1"))
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

local function stat(key) db.stats[key] = (db.stats[key] or 0) + 1 end

-- 記一筆擊殺（榮譽訊息、最後一擊共用）：補上時間、地點、自己的職業等級公會，交給 Share.lua
local function addKill(k, faction)
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
  recent[P.MainName(k.name) or k.name] = { k = k, at = GetTime() }
  if ns.Share and ns.Share.KillAdded then ns.Share.KillAdded(k) end
  ns.UI.Refresh("share")
end

-- 同一個人 30 秒內已經記過（另一個來源記的）
local function recentKill(name)
  local r = recent[P.MainName(name) or name]
  if r and GetTime() - r.at < MERGE_SECS then return r.k end
end

function P.Record(text)
  if not P.On() then return end
  stat("lines")
  if ns.Secret(text) or type(text) ~= "string" then
    db.missed = (db.missed or 0) + 1
    return
  end
  local faction = UnitFactionGroup("player")
  if not P.COLLECTORS[faction or ""] then return end                    -- 聯盟、部落（有站長角色的陣營）
  local k = P.Parse(text)
  if not k then
    stat("unmatched")
    local plain = P.Plain(text)
    table.insert(db.unmatched, 1, { t = now(), text = #plain > 200 and plain:sub(1, 200) or plain })
    while #db.unmatched > MAX_UNMATCHED do table.remove(db.unmatched) end
    return
  end
  stat("matched")
  local old = recentKill(k.name)
  if old and old.via == "kb" then                                       -- 最後一擊先記了：補上軍銜、榮譽
    old.rank, old.honor, old.via = k.rank, k.honor, "both"
    if #k.name > #old.name then old.name = k.name end
    ns.UI.Refresh("share")
    return
  end
  addKill(k, faction)
end

-- PARTY_KILL：自己打出最後一擊、死的是玩家
function P.PartyKill(attacker, target)
  if not P.On() then return end
  local faction = UnitFactionGroup("player")
  if not P.COLLECTORS[faction or ""] then return end
  if ns.Secret(attacker) or ns.Secret(target) then return stat("kbSecret") end
  if type(target) ~= "string" or not target:match("^Player%-") then return end   -- 怪物不算
  stat("kbPlayers")
  if attacker ~= P.Me() then return end                                 -- 隊友打的：隊友有裝小幫手會自己回報
  local _, _, _, _, _, name, second = ns.Call(_G, "GetPlayerInfoByGUID", target)
  name = P.JoinName(name, second)
  if not name then return stat("kbNoName") end
  name = clean(name)
  stat("kb")
  local old = recentKill(name)
  if old then                                                           -- 榮譽訊息先記了：名字比較完整就換
    if #name > #old.name then old.name = name end
    old.via = "both"
    return
  end
  addKill({ name = name, rank = "", honor = 0, via = "kb" }, faction)
end

-- 「/amobi 擊殺」：每一關的計數、對不上的訊息原文
function P.Check()
  local s = db.stats
  ns.Print(("榮譽擊殺：分享%s；這個陣營的站長 %s"):format(P.On() and "開著" or "關著", table.concat(P.Collectors(), "、")))
  ns.Print(("榮譽擊殺：聊天框的榮譽訊息收到 %d 次（對上 %d、對不上 %d、讀不到 %d）；你打出最後一擊殺死玩家 %d 次（隊伍裡有人殺死玩家 %d 次、讀不到 %d）")
    :format(s.lines or 0, s.matched or 0, s.unmatched or 0, db.missed or 0, s.kb or 0, s.kbPlayers or 0, (s.kbSecret or 0) + (s.kbNoName or 0)))
  ns.Print(("榮譽擊殺：遊戲的擊殺數變了 %d 次（這次登入 %s 個榮譽擊殺）；這個帳號記了 %d 次、還有 %d 次等著傳")
    :format(s.hkChanged or 0, tostring(s.sessionHK or "?"), db.total or 0, #P.Unsent()))
  for i = 1, math.min(2, #db.unmatched) do
    ns.Print("榮譽擊殺：對不上的訊息 " .. i .. "：" .. db.unmatched[i].text)
  end
  if type(COMBATLOG_HONORGAIN) == "string" then ns.Print("榮譽擊殺：遊戲的格式是「" .. COMBATLOG_HONORGAIN .. "」") end
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

-- 整個名字「大名 次名」（去掉「-伺服器」、前後空白，中間多個空白算一個）
function P.FullName(name)
  if type(name) ~= "string" or ns.Secret(name) then return nil end
  local n = (name:gsub("%-[^%s%-]*$", ""))
  n = (n:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "))
  if n == "" then return nil end
  return n
end

-- 這個名字是哪一個站長角色（回傳 COLLECTORS 裡寫的那個名字，不是就回傳 nil）：
-- 全名要一樣；名字只有一段（沒有次名）的，比大名
function P.CollectorFor(name)
  local full = P.FullName(name)
  if not full then return nil end
  local single = not full:find(" ", 1, true)
  for _, n in ipairs(P.Collectors()) do
    if n == full or (single and P.MainName(n) == full) then return n end
  end
  return nil
end

-- 是不是這個陣營的站長角色
function P.IsCollectorName(name) return P.CollectorFor(name) ~= nil end

function P.Init()
  ns.db.pvp = type(ns.db.pvp) == "table" and ns.db.pvp or {}
  db = ns.db.pvp
  db.kills = type(db.kills) == "table" and db.kills or {}
  db.stats = type(db.stats) == "table" and db.stats or {}
  db.unmatched = type(db.unmatched) == "table" and db.unmatched or {}
  P.Prune()
  ns.On("CHAT_MSG_COMBAT_HONOR_GAIN", function(text) P.Record(text) end)
  ns.On("PARTY_KILL", function(attacker, target) P.PartyKill(attacker, target) end)
  ns.On("PLAYER_PVP_KILLS_CHANGED", function(unit)
    if unit ~= "player" then return end
    stat("hkChanged")
    local hk = ns.Call(_G, "GetPVPSessionStats")
    if type(hk) == "number" and not ns.Secret(hk) then db.stats.sessionHK = hk end
  end)
end
ns.Register(P)
