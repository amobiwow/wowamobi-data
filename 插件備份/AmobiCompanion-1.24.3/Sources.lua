-- 阿莫比小幫手：物品來源記錄（1.11.0；老闆 10/27：「物品的資料 能補他們來源的單位跟地圖座標嗎」
-- 「有些是特定商人或是其他專業的配方 光這樣看 可能找不到怎麼做」，問過「小幫手加記商人、任務獎勵、怪物掉落和座標」→「一起做」）
--
-- 永恆的遊戲檔沒有掉落表、商人和任務獎勵，網站物品頁的「怎麼取得」只有經典版參考。這個檔在玩家平常玩的時候記下永恆真正的來源：
--   商人：打開商人視窗時，賣哪些東西、價錢（或要用什麼換）、限不限量，商人是誰、在哪裡
--   任務：任務說明（接任務）、選獎勵（交任務）的畫面：任務編號、名稱、給的獎勵，誰給（誰收）、在哪裡
--   怪物、寶箱：打開屍體、寶箱的拾取視窗時，是哪一種怪物（物件）、掉了什麼、在哪裡（同一種照地圖累計開了幾具屍體）
--   訓練師（1.16.0，老闆 11/7：遊戲內建的小地圖追蹤「不太完整，像烹飪是找旅館裡的NPC」→「要，照這樣做」）：打開訓練師視窗時，
--         是誰、在哪裡、是哪一種（C_Trainer.GetTrainerType：職業／專業技能）、教的技能屬於哪個技能線（例如「烹飪」）、你是什麼職業；
--         網站世界地圖畫成「玩家記到的訓練師」
--   任務內容（1.17.0，老闆 11/7 看到別人的網站「有所有任務歸納」→ 做任務資料庫「我們利用玩家來收集」）：任務說明的畫面上，
--         任務目標、任務說明、給多少經驗和錢、建議幾個人、任務等級、你接的時候幾級；網站任務頁 /quests/<編號> 用
--         （說明裡出現你的角色名字會換成 $N，不傳你的名字）
-- 剝皮、採草採礦、偷竊、釣魚開出來的、打開背包裡的物品不記；首領不記（Drops.lua 在公會裡記，網站另外算掉落率）。
-- 只讀遊戲給的資訊，不會替你買、撿、接任何東西；記的名字是 NPC 的（商人、給任務的人、怪物），不記任何玩家的名字。
-- 由 Share.lua 傳給阿莫比站長的角色：和榮譽擊殺一樣不用在公會裡，站長不在線就先存著（14 天）；站長的電腦登出後自動上傳到網站。
-- 「分享資料」分頁可以關（srcShare，預設開）。存檔是整個帳號共用的：每項記下是哪個角色記的，只傳現在登入的角色記的（寄件人才對得上）。
--
-- 一筆資料（傳給站長的內容）：S1^伺服器^陣營^一項~一項~…（數字 36 進位；座標是地圖上的 0～1000，副本裡沒有座標）
--   商人 v:時間:商人:地圖:x:y:區域:名字:物品.價錢.一組幾個.限量(1/0).換購,…（換購：i物品*數量、t貨幣名稱*數量（讀不到名稱寫 c貨幣編號*數量），用 + 連起來；用錢買的是空的）
--   任務 q:時間:任務:a(接)/c(交):給的人(n生物/o物件，讀不到是空的):地圖:x:y:區域:名字:任務名稱:選一件的獎勵:一定給的獎勵（物品.數量,…）
--   怪物 m:時間:生物:地圖:副本地圖:區域:名字:開了幾具屍體:位置(x.y,…，最多 6 個):物品.幾具有掉.總數量,…
--   寶箱 o:時間:物件:地圖:副本地圖:區域::開了幾次:位置:物品.幾次有掉.總數量,…
--   訓練師 t:時間:生物:地圖:x:y:區域:名字:類型:你的職業編號:技能線名稱+技能線名稱（最多 3 個）
--         （訓練師自己包成一筆：1.15 以前的網站上傳程式看不懂 t，整筆都是 t 的話會留在站長的存檔裡等新版程式，不會被當成傳過）
--   任務內容 d:時間:任務:目標:說明:經驗:金錢:建議人數:你的等級:任務等級（目標、說明裡的 % : ~ ^ | 換行寫成 %XX；和 t 一起包成自己的一筆）
--   （時間是第一次記到的伺服器時間；地圖是 C_Map 的地圖編號，副本地圖是 GetInstanceInfo 的，野外是 0）

local _, ns = ...
local R = {}
ns.Sources = R

local SETTLE = 10 * 60        -- 秒：最早的一項記了 10 分鐘才包起來傳（同一種怪多打幾隻一起傳）
local MAX_BODY = 1500         -- 一筆大約多大就換下一筆（約 7 則插件訊息；一個商人賣很多東西時可以超過）
local MAX_PENDING = 300       -- 還沒包的最多幾項，再多就先包起來
local KEEP = 14 * 86400       -- 秒：沒傳出去的最多留 14 天
local SEEN_DAYS = 14          -- 同一個商人、任務 14 天內記過一樣的就不再記
local MAX_OUTBOX = 200
local MAX_PTS = 6
local MAX_ITEMS = 200         -- 一個商人最多記幾樣
local GATHER_WINDOW = 2.5     -- 秒：採集、剝皮、偷竊成功後這麼快打開的拾取視窗是採集出來的
local LOOTED_KEEP = 2 * 3600  -- 秒：記住開過的屍體多久（同一具屍體關掉再開不重算；只放記憶體）
local ITEM_SLOT = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1

local db
local gatheredAt, skipWindow = -100, false
local looted, fresh = {}, {}          -- [GUID] = 開的時間；這個拾取視窗裡已經算過的 [GUID] = {物品 = 數量}
local vendorSoonAt, trainerSoonAt = false, false
local MAX_SKILLS = 3          -- 訓練師教的技能最多記幾個技能線
local NEW_KINDS = { t = true, d = true }   -- 1.16 以後才有的種類：自己包成一筆（舊版網站上傳程式看不懂，整筆留著等新版）
local MAX_OBJ, MAX_DESC = 450, 1500        -- 位元組：任務目標、任務說明最多記多長

local function now() return GetServerTime and GetServerTime() or time() end
local function secret(v) return ns.Secret(v) end
local function str(v) return type(v) == "string" and not secret(v) and v or nil end
local function num(v) return type(v) == "number" and not secret(v) and v or nil end
local function B36(n) return ns.Market.B36(n) end

function R.On() return ns.db.settings.srcShare ~= false end
-- 這個陣營有站長的角色才記（傳得出去）
function R.Active() return R.On() and ns.PvP ~= nil and #ns.PvP.Collectors() > 0 end
local function me() return ns.PvP.Me() end
local function mine(e) return e.who == nil or e.who == me() end
local function isCollector() return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("AmobiGuild") end

-- 名字、區域、任務名稱裡不能有傳送用的分隔符號；最多 60 位元組，不在中文字中間切
local function clean(s)
  s = tostring(s or ""):gsub("[%^~:,%.|%*%+]", "")
  if #s > 60 then
    local j = 60
    while j > 0 and s:byte(j + 1) >= 0x80 and s:byte(j + 1) < 0xC0 do j = j - 1 end
    s = s:sub(1, j)
  end
  return s
end

local function itemOf(link)
  link = str(link)
  return link and tonumber(link:match("|Hitem:(%d+)"))
end

-- 「Creature-0-伺服器-副本-分身-編號-生成」→ "m"／"o", 編號
local function parse(guid)
  local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
  if kind == "Creature" or kind == "Vehicle" then return "m", tonumber(id) end
  if kind == "GameObject" then return "o", tonumber(id) end
end

local function unitSource(unit)
  local guid = str(UnitGUID(unit))
  if not guid then return end
  return parse(guid)
end

local function unitName(unit) return clean(str(UnitName(unit)) or "") end

-- 自己在哪：地圖編號, x, y（0～1000，副本裡沒有）, 副本地圖, 區域名稱
local function here()
  local map, x, y = ns.Navigate.Where()
  local _, kind, _, _, _, _, _, inst = GetInstanceInfo()
  if secret(inst) or type(inst) ~= "number" or kind == "none" or kind == nil then inst = 0 end
  local zone = str(GetRealZoneText and GetRealZoneText()) or (map and ns.Navigate.ZoneName(map)) or ""
  if x then x, y = math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5) end
  return map or 0, x, y, inst, clean(zone)
end

-- 這個帳號同一個商人、同一個任務 14 天內記過一樣的就不再記（記過但內容變了會再記一次）
local function already(key, sig)
  local h = ns.Share.Hash(sig)
  local s = db.seen[key]
  if s and s.h == h and now() - s.t < SEEN_DAYS * 86400 then return true end
  db.seen[key] = { h = h, t = now() }
  return false
end

local function add(key, e)
  key = key .. "|" .. (me() or "")
  if not db.pending[key] then db.stats[e.k] = (db.stats[e.k] or 0) + 1 end
  e.who, e.t = me(), (db.pending[key] and db.pending[key].t) or now()
  db.pending[key] = e
  ns.UI.Refresh("share")
end

-- ------------------------------------------------------------------ 商人
local function costOf(i)
  local n = num(ns.Call(_G, "GetMerchantItemCostInfo", i))
  if not n or n <= 0 then return "" end
  local parts = {}
  for j = 1, math.min(n, 5) do
    local _, value, link, currency = ns.Call(_G, "GetMerchantItemCostItem", i, j)
    value, link = num(value), str(link)
    if value and value > 0 then
      local item = link and tonumber(link:match("|Hitem:(%d+)"))
      local cur = link and tonumber(link:match("|Hcurrency:(%d+)"))
      local cname = clean(str(currency) or "")
      if item then parts[#parts + 1] = "i" .. B36(item) .. "*" .. B36(value)
      elseif cname ~= "" then parts[#parts + 1] = "t" .. cname .. "*" .. B36(value)   -- 貨幣：網站沒有貨幣表，寫名字
      elseif cur then parts[#parts + 1] = "c" .. B36(cur) .. "*" .. B36(value) end
    end
  end
  return table.concat(parts, "+")
end

function R.ReadVendor()
  if not R.Active() then return end
  local kind, npc = unitSource("npc")
  if kind ~= "m" or not npc then return end
  local n = num(ns.Call(_G, "GetMerchantNumItems"))
  if not n or n <= 0 then return end
  local items = {}
  for i = 1, math.min(n, MAX_ITEMS) do
    local id = num(ns.Call(_G, "GetMerchantItemID", i)) or itemOf(ns.Call(_G, "GetMerchantItemLink", i))
    local info = ns.Call(C_MerchantFrame, "GetItemInfo", i)
    if id and type(info) == "table" and not secret(info) then
      local avail = num(info.numAvailable)
      local cost = info.hasExtendedCost == true and costOf(i) or ""
      items[#items + 1] = table.concat({ B36(id), B36(num(info.price) or 0), B36(num(info.stackCount) or 1),
                                         (avail and avail >= 0) and 1 or 0, cost }, ".")
    end
  end
  if #items == 0 then return end
  local list = table.concat(items, ",")
  if already("v|" .. npc, list) then return end
  local map, x, y, _, zone = here()
  add("v|" .. npc, { k = "v", id = npc, map = map, x = x, y = y, zone = zone, name = unitName("npc"), items = list })
end

-- 商品資料可能晚一點才到（MERCHANT_UPDATE）：等 1 秒再讀，之後有更新再讀一次
local function vendorSoon()
  if vendorSoonAt or not R.Active() then return end
  vendorSoonAt = true
  C_Timer.After(1, function()
    vendorSoonAt = false
    ns.Try("sources:vendor", R.ReadVendor)
  end)
end

-- ------------------------------------------------------------------ 訓練師（1.16.0）
function R.ReadTrainer()
  if not R.Active() then return end
  local kind, npc = unitSource("npc")
  if kind ~= "m" or not npc then return end
  local ttype = num(ns.Call(C_Trainer, "GetTrainerType"))
  if not ttype then return end
  local skills, seen = {}, {}
  for i = 1, math.min(num(ns.Call(_G, "GetNumTrainerServices")) or 0, 300) do
    local line = clean(str(ns.Call(_G, "GetTrainerServiceSkillLine", i)) or "")
    if line ~= "" and not seen[line] then
      seen[line] = true
      skills[#skills + 1] = line
      if #skills >= MAX_SKILLS then break end
    end
  end
  local cls = num(select(3, UnitClass("player"))) or 0
  local list = table.concat(skills, "+")
  if already("t|" .. npc, table.concat({ ttype, cls, list }, "|")) then return end
  local map, x, y, _, zone = here()
  add("t|" .. npc, { k = "t", id = npc, map = map, x = x, y = y, zone = zone, name = unitName("npc"), ttype = ttype, cls = cls, skills = list })
end

-- 技能清單可能晚一點才到（TRAINER_UPDATE）：等 1 秒再讀
local function trainerSoon()
  if trainerSoonAt or not R.Active() then return end
  trainerSoonAt = true
  C_Timer.After(1, function()
    trainerSoonAt = false
    ns.Try("sources:trainer", R.ReadTrainer)
  end)
end

-- ------------------------------------------------------------------ 任務內容（1.17.0）
-- 最多 n 位元組，不在中文字中間切
local function cut(s, n)
  if #s <= n then return s end
  local j = n
  while j > 0 and s:byte(j + 1) and s:byte(j + 1) >= 0x80 and s:byte(j + 1) < 0xC0 do j = j - 1 end
  return s:sub(1, j)
end
-- 傳送用的分隔符號寫成 %XX（網站上傳程式換回來）
local function escText(s)
  return (s:gsub("[%%:~%^|\r\n]", function(c) return ("%%%02X"):format(c:byte()) end))
end
-- 任務目標、說明：你的角色名字換成 $N（遊戲會把 $N 換成看的人的名字）
function R.QuestText(v, n)
  local s = str(v)
  if not s or s == "" then return "" end
  local me = str(UnitName("player"))
  if me and me ~= "" then
    local i = 1
    while true do
      local a, b = s:find(me, i, true)
      if not a then break end
      s = s:sub(1, a - 1) .. "$N" .. s:sub(b + 1)
      i = a + 2
    end
  end
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return escText(cut(s, n))
end

function R.ReadQuestText()
  if not R.Active() then return end
  local qid = num(ns.Call(_G, "GetQuestID"))
  if not qid or qid <= 0 then return end
  local obj = R.QuestText(ns.Call(_G, "GetObjectiveText"), MAX_OBJ)
  local desc = R.QuestText(ns.Call(_G, "GetQuestText"), MAX_DESC)
  if obj == "" and desc == "" then return end
  local xp = math.max(0, num(ns.Call(_G, "GetRewardXP")) or 0)
  local money = math.max(0, num(ns.Call(_G, "GetRewardMoney")) or 0)
  local group = math.max(0, num(ns.Call(_G, "GetSuggestedGroupSize")) or 0)
  local qlv = math.max(0, num(ns.Call(C_QuestLog, "GetQuestDifficultyLevel", qid)) or 0)
  if already("d|" .. qid, table.concat({ obj, desc, xp, money, group }, "|")) then return end
  add("d|" .. qid, { k = "d", id = qid, obj = obj, desc = desc, xp = xp, money = money, group = group,
                     plv = math.max(0, num(UnitLevel("player")) or 0), qlv = qlv })
end

-- 接了任務：任務日誌裡有任務等級（說明畫面讀不到的時候補上）
local function onAccepted(a, b)
  local qid = num(b) or num(a)
  local e = qid and db.pending["d|" .. qid .. "|" .. (me() or "")]
  if not e or (e.qlv or 0) > 0 then return end
  local idx = num(ns.Call(C_QuestLog, "GetLogIndexForQuestID", qid))
  local info = idx and ns.Call(C_QuestLog, "GetInfo", idx)
  local lv = type(info) == "table" and not secret(info) and num(info.level)
  if lv and lv > 0 then e.qlv = lv end
end

-- ------------------------------------------------------------------ 任務
local function questItems(kind, n)
  local out = {}
  for i = 1, math.min(num(n) or 0, 10) do
    local _, _, count, _, _, id = ns.Call(_G, "GetQuestItemInfo", kind, i)
    id = num(id) or itemOf(ns.Call(_G, "GetQuestItemLink", kind, i))
    if id then out[#out + 1] = B36(id) .. "." .. B36(math.max(1, num(count) or 1)) end
  end
  return table.concat(out, ",")
end

-- step：a 任務說明（接任務的畫面）、c 選獎勵（交任務的畫面）
function R.ReadQuest(step)
  if not R.Active() then return end
  local qid = num(ns.Call(_G, "GetQuestID"))
  if not qid or qid <= 0 then return end
  local title = clean(str(ns.Call(_G, "GetTitleText")) or "")
  local choices = questItems("choice", ns.Call(_G, "GetNumQuestChoices"))
  local rewards = questItems("reward", ns.Call(_G, "GetNumQuestRewards"))
  local gk, gid = unitSource("npc")
  local giver = gk and ((gk == "m" and "n" or "o") .. B36(gid)) or ""
  local key = "q|" .. qid .. "|" .. step
  if already(key, table.concat({ title, giver, choices, rewards }, "|")) then return end
  local map, x, y, _, zone = here()
  add(key, { k = "q", id = qid, step = step, giver = giver, map = map, x = x, y = y, zone = zone,
             name = gk and unitName("npc") or "", title = title, choices = choices, rewards = rewards })
end

-- ------------------------------------------------------------------ 怪物、寶箱
-- 怪物的名字：屍體還是某個單位（目標、滑鼠指著的…）時才讀得到
local function nameOf(guid)
  local unit = str(ns.Call(_G, "UnitTokenFromGUID", guid))
  if not unit then
    for _, u in ipairs({ "target", "mouseover" }) do
      local g = str(UnitGUID(u))
      if g and g == guid then unit = u break end
    end
  end
  return unit and unitName(unit) or ""
end

local function count(e, items, sign)
  for item, n in pairs(items) do
    local it = e.items[item]
    if not it then it = { 0, 0 }; e.items[item] = it end
    if sign then it[1] = it[1] + 1 end
    it[2] = it[2] + n
  end
end

local function corpse(kind, id, guid, items, where)
  local map, x, y, inst, zone = unpack(where)
  local key = table.concat({ kind, id, map, inst }, "|") .. "|" .. (me() or "")
  local e = db.pending[key]
  if not e then
    db.stats[kind] = (db.stats[kind] or 0) + 1
    e = { k = kind, id = id, map = map, inst = inst, zone = zone, name = "", n = 0, pts = {}, items = {}, t = now(), who = me() }
    db.pending[key] = e
  end
  e.n = e.n + 1
  if kind == "m" and e.name == "" then e.name = nameOf(guid) end
  if x and #e.pts < MAX_PTS then e.pts[#e.pts + 1] = B36(x) .. "." .. B36(y) end
  count(e, items, true)
  fresh[guid] = { key = key, items = items }
end

local function readLoot()
  local per, order = {}, {}
  for slot = 1, GetNumLootItems() do
    local id = GetLootSlotType(slot) == ITEM_SLOT and itemOf(GetLootSlotLink(slot)) or nil
    local src = { GetLootSourceInfo(slot) }
    for i = 1, #src - 1, 2 do
      local guid, n = src[i], src[i + 1]
      if type(guid) == "string" and not secret(guid) then
        local got = per[guid]
        if not got then got = {}; per[guid] = got; order[#order + 1] = guid end
        if id and type(n) == "number" and not secret(n) and n > 0 then got[id] = (got[id] or 0) + n end
      end
    end
  end
  return per, order
end

-- LOOT_OPENED 才知道是不是打開背包裡的物品，所以在 LOOT_OPENED 才開始算；之後的 LOOT_SLOT_CHANGED 只補這個視窗晚到的物品
local function onLoot(fromItem, mergeOnly)
  if fromItem then skipWindow = true end
  if skipWindow or not R.Active() or not GetLootSourceInfo then return end
  if GetTime() - gatheredAt <= GATHER_WINDOW or (IsFishingLoot and IsFishingLoot()) then
    skipWindow = true
    return
  end
  local per, order = readLoot()
  local where
  for _, guid in ipairs(order) do
    local f = fresh[guid]
    if f then                                   -- 同一個拾取視窗又來一次（物品資料晚到）：只補多出來的
      local e = db.pending[f.key]
      if e then
        local more = {}
        for item, n in pairs(per[guid]) do
          local had = f.items[item] or 0
          if n > had then
            more[item] = n - had
            if had == 0 then e.items[item] = e.items[item] or { 0, 0 }; e.items[item][1] = e.items[item][1] + 1 end
            f.items[item] = n
          end
        end
        count(e, more, false)
      end
    elseif not looted[guid] and not mergeOnly then   -- 同一具屍體關掉再開不重算
      looted[guid] = GetTime()
      local kind, id = parse(guid)
      if kind and not (kind == "m" and (db.bosses[id] or (ns.db.drops and ns.db.drops.bosses and ns.db.drops.bosses[id]))) then
        where = where or { here() }
        local items = {}
        for item, n in pairs(per[guid]) do items[item] = n end
        corpse(kind, id, guid, items, where)
      end
    end
  end
  ns.UI.Refresh("share")
end

-- ------------------------------------------------------------------ 包起來、交給 Share.lua
local function list(items)
  local ids = {}
  for id in pairs(items) do ids[#ids + 1] = id end
  table.sort(ids)
  local out = {}
  for _, id in ipairs(ids) do out[#out + 1] = B36(id) .. "." .. B36(items[id][1]) .. "." .. B36(items[id][2]) end
  return table.concat(out, ",")
end

local function opt(n) return n and B36(n) or "" end

function R.EntryText(e)
  local T = B36(e.t)
  if e.k == "v" then
    return table.concat({ "v", T, B36(e.id), B36(e.map), opt(e.x), opt(e.y), e.zone, e.name, e.items }, ":")
  elseif e.k == "q" then
    return table.concat({ "q", T, B36(e.id), e.step, e.giver, B36(e.map), opt(e.x), opt(e.y), e.zone, e.name, e.title,
                          e.choices, e.rewards }, ":")
  elseif e.k == "t" then
    return table.concat({ "t", T, B36(e.id), B36(e.map), opt(e.x), opt(e.y), e.zone, e.name, B36(e.ttype), B36(e.cls), e.skills or "" }, ":")
  elseif e.k == "d" then
    return table.concat({ "d", T, B36(e.id), e.obj or "", e.desc or "", B36(e.xp or 0), B36(e.money or 0), B36(e.group or 0),
                          B36(e.plv or 0), B36(e.qlv or 0) }, ":")
  end
  return table.concat({ e.k, T, B36(e.id), B36(e.map), B36(e.inst), e.zone, e.name or "", B36(e.n),
                        table.concat(e.pts, ","), list(e.items) }, ":")
end

local function prune()
  local keep, t = {}, now()
  for _, o in ipairs(db.outbox) do
    if type(o) == "table" and type(o.t) == "number" and t - o.t < KEEP then keep[#keep + 1] = o end
  end
  while #keep > MAX_OUTBOX do table.remove(keep, 1) end
  db.outbox = keep
  for key, e in pairs(db.pending) do
    if type(e) ~= "table" or type(e.t) ~= "number" or t - e.t >= KEEP then db.pending[key] = nil end
  end
  for key, s in pairs(db.seen) do
    if type(s) ~= "table" or type(s.t) ~= "number" or t - s.t >= SEEN_DAYS * 86400 then db.seen[key] = nil end
  end
end

-- 這個角色記的、最早一項已經 10 分鐘（或項目很多、force）：包成幾筆 S1 放進 outbox。回傳包了幾筆
function R.Seal(force)
  local keys, oldest = {}, nil
  for key, e in pairs(db.pending) do
    if mine(e) then
      keys[#keys + 1] = key
      oldest = math.min(oldest or e.t, e.t)
    end
  end
  if #keys == 0 or (not force and now() - oldest < SETTLE and #keys < MAX_PENDING) then return 0 end
  -- 訓練師、任務內容排在最後、自己包成一筆（最上面的說明：舊版網站上傳程式看不懂 t、d）
  table.sort(keys, function(a, b)
    local ta, tb = NEW_KINDS[db.pending[a].k] == true, NEW_KINDS[db.pending[b].k] == true
    if ta ~= tb then return tb end
    return a < b
  end)
  local head = "S1^" .. clean(GetRealmName()) .. "^" .. (str(UnitFactionGroup("player")) or "") .. "^"
  local parts, size, made, lastT = {}, 0, 0, nil
  local function flush()
    if #parts == 0 then return end
    local body = head .. table.concat(parts, "~")
    table.insert(db.outbox, { id = ns.Share.Hash(body), body = body, t = now(), who = me() })
    parts, size, made = {}, 0, made + 1
  end
  for _, key in ipairs(keys) do
    local isT = NEW_KINDS[db.pending[key].k] == true
    if lastT ~= nil and isT ~= lastT then flush() end
    lastT = isT
    local text = R.EntryText(db.pending[key])
    if size > 0 and size + #text + 1 > MAX_BODY then flush() end
    parts[#parts + 1] = text
    size = size + #text + 1
    db.pending[key] = nil
  end
  flush()
  prune()
  -- 站長自己的電腦（裝了 AmobiGuild）：直接存進公會名單插件，不用傳
  if isCollector() and type(AmobiGuild_Store) == "function" then
    for _, o in ipairs(R.Outbox(true)) do
      local ok, stored = pcall(AmobiGuild_Store, o.body)
      if ok and stored then R.MarkSent(o) end
    end
  end
  return made
end

-- 這個角色包好、還沒傳出去的（Share.lua 用；先看要不要包）
function R.Outbox(noSeal)
  if not noSeal then R.Seal(false) end
  local out = {}
  for _, o in ipairs(db.outbox) do
    if mine(o) then out[#out + 1] = o end
  end
  return out
end

function R.MarkSent(o)
  for i = #db.outbox, 1, -1 do
    if db.outbox[i] == o or db.outbox[i].id == o.id then table.remove(db.outbox, i) end
  end
  db.sentN = (db.sentN or 0) + 1
  ns.UI.Refresh("share")
end

function R.Waiting()
  local n = 0
  for _, e in pairs(db.pending) do if mine(e) then n = n + 1 end end
  return n, #R.Outbox(true)
end

function R.Status()
  local s = db.stats
  local pend, box = R.Waiting()
  return ("這個帳號記了 %d 個商人、%d 個任務畫面、%d 種怪物、%d 種寶箱、%d 個訓練師、%d 個任務說明%s"):format(s.v or 0, s.q or 0, s.m or 0, s.o or 0, s.t or 0, s.d or 0,
    (pend + box) > 0 and ("；%d 項還沒傳（%d 筆包好了）"):format(pend, box) or "")
end

function R.Init()
  ns.db.sources = type(ns.db.sources) == "table" and ns.db.sources or {}
  db = ns.db.sources
  for _, k in ipairs({ "pending", "outbox", "seen", "bosses", "stats" }) do
    if type(db[k]) ~= "table" then db[k] = {} end
  end
  prune()
  ns.On("MERCHANT_SHOW", vendorSoon)
  ns.On("MERCHANT_UPDATE", vendorSoon)
  ns.On("TRAINER_SHOW", trainerSoon)
  ns.On("TRAINER_UPDATE", trainerSoon)
  ns.On("QUEST_DETAIL", function() R.ReadQuest("a"); ns.Try("sources:questtext", R.ReadQuestText) end)
  ns.On("QUEST_ACCEPTED", function(a, b) ns.Try("sources:accepted", function() onAccepted(a, b) end) end)
  ns.On("QUEST_COMPLETE", function() R.ReadQuest("c") end)
  ns.On("LOOT_OPENED", function(_, fromItem) onLoot(fromItem == true, false) end)
  ns.On("LOOT_SLOT_CHANGED", function() onLoot(false, true) end)
  ns.On("LOOT_CLOSED", function() skipWindow = false; wipe(fresh) end)
  ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit == "player" and num(spellID) and ns.Drops.GATHER[spellID] then gatheredAt = GetTime() end
  end)
  -- 首領：首領戰結束時遊戲給的生物編號（不管在不在公會；Drops.lua 只在公會裡記）
  ns.On("ENCOUNTER_END", function(_, _, _, _, _, units)
    if type(units) ~= "table" or secret(units) then return end
    for _, u in ipairs(units) do
      local id = type(u) == "table" and num(u.creatureID)
      if id then db.bosses[id] = true end
    end
  end)
  C_Timer.NewTicker(60, function()
    ns.Try("sources:tick", function()
      for guid, t in pairs(looted) do
        if GetTime() - t > LOOTED_KEEP then looted[guid] = nil end
      end
      if R.Active() and R.Seal(false) > 0 and ns.Share then ns.Share.Kick2() end
    end)
  end)
end

ns.Register(R)
