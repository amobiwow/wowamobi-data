-- 阿莫比小幫手：首領掉落記錄（1.6.0；老闆 10/25：「我們的ui裡面可以先寫入撈取拍賣場跟副本boss掉落的資料，透過隱形頻道傳給我」）
--
-- 永恆的遊戲檔裡沒有首領掉落表，阿莫比網站的掉落率是玩家打副本記下來的。記法照掉落記錄插件（addon\AmobiLoot）：
--   1. 首領擊殺：ENCOUNTER_END（成功）記首領、副本、難度、人數、伺服器時間，和這場的首領生物編號（認屍體用）
--   2. 首領屍體、首領寶箱：打開拾取視窗時，GetLootSourceInfo 說每一格來自哪具屍體或寶箱，是剛打完的首領才記
--   3. 隊伍擲骰的物品（C_LootHistory）、分給隊上某人的（ENCOUNTER_LOOT_RECEIVED）：自己沒打開屍體也記得到
-- 同一具屍體、同一個寶箱只算一次；剝皮、採礦、採草、偷竊、釣魚開出來的不記；小怪的掉落不記。
-- 由 Share.lua 在阿莫比站長在線時傳過去。只有「分享給阿莫比」開著、14 天內聯絡上過站長才記（1.24.3 起不用在公會裡）；
-- 這台電腦裝了 AmobiLoot 就由它記，這裡不重複。存檔只留 30 天。
-- 只讀遊戲給的資訊：不會替你撿東西、擲骰或點任何東西。不存任何玩家的名字（誰擲骰、誰拿走都不讀）。

local _, ns = ...
local D = {}
ns.Drops = D

local KILL_SAME = 5            -- 秒：同一個首領 5 秒內的事件是同一次擊殺（ENCOUNTER_END 和 BOSS_KILL 都會來）
local CORPSE_WINDOW = 2 * 3600 -- 秒：擊殺後 2 小時內打開首領屍體都算這次
local CHEST_WINDOW = 15 * 60   -- 秒：打完首領 15 分鐘內打開的寶箱（這次還沒記到首領屍體）算首領的寶箱
local GATHER_WINDOW = 2.5      -- 秒：採集成功後這麼快打開的拾取視窗是採集出來的
local HISTORY_SLACK = 120      -- 秒：掉落紀錄裡比這次擊殺早超過 2 分鐘的是上一次的
local KEEP_DAYS = 30
local ITEM_SLOT = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1

-- 剝皮、偷竊、採草藥、採礦，和從屍體採礦、採草、拆零件的技能（永恆客戶端 1.60.1.70245 的 SpellEffect 表，同 AmobiLoot）
local GATHER = {}
for _, id in ipairs({ 8613, 8617, 8618, 10768, 1235230, 1235236, 1235244, 921, 5967,
                      2366, 2368, 2369, 2371, 3570, 11993, 1312650,
                      2575, 2576, 2577, 2578, 2579, 3564, 10248, 1264639 }) do
  GATHER[id] = true
end
D.GATHER = GATHER   -- Sources.lua 也用（採集出來的不算怪物掉落）

local db
local gatheredAt, skipWindow = -100, false
local fresh = {}

local function now() return GetServerTime and GetServerTime() or time() end
local function secret(v) return ns.Secret(v) end
local function has(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end

local function standalone() return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("AmobiLoot") end

function D.Active()
  if standalone() or ns.db.settings.share == false then return false end
  return ns.Share and ns.Share.Reachable() or false
end

local function parseSource(guid)
  local kind, map, copy, id = guid:match("^(%a+)%-%d+%-%d+%-(%d+)%-(%d+)%-(%d+)%-%x+$")
  if kind == "Creature" or kind == "Vehicle" then return "npc", tonumber(id), copy, tonumber(map) end
  if kind == "GameObject" then return "obj", tonumber(id), copy, tonumber(map) end
end

local function instance()
  local _, kind, diff, _, maxPlayers, _, _, map = GetInstanceInfo()
  if kind ~= "party" and kind ~= "raid" then return end
  return map, diff, maxPlayers
end

local function findKill(enc, t)
  for i = #db.kills, 1, -1 do
    local k = db.kills[i]
    if k.enc == enc and math.abs(t - k.t) <= KILL_SAME then return k end
    if t - k.t > CORPSE_WINDOW then return end
  end
end

local function prune()
  local oldest = now() - KEEP_DAYS * 86400
  local keep = {}
  for _, k in ipairs(db.kills) do
    if k.t >= oldest then keep[#keep + 1] = k end
  end
  db.kills = keep
  for guid, rec in pairs(db.loot) do
    if rec.t < oldest then db.loot[guid] = nil end
  end
end

local function encounterEnd(enc, diff, size, success, units)
  if type(enc) ~= "number" or secret(enc) then return end
  local map, idiff, maxPlayers = instance()
  if not map then return end
  local npcs = {}
  if type(units) == "table" and not secret(units) then
    for _, u in ipairs(units) do
      local id = type(u) == "table" and u.creatureID
      if type(id) == "number" and not secret(id) then
        npcs[#npcs + 1] = id
        db.bosses[id] = enc
      end
    end
  end
  if not success then return end
  local t = now()
  local k = findKill(enc, t)
  if k then
    for _, id in ipairs(npcs) do
      if not has(k.npcs, id) then k.npcs[#k.npcs + 1] = id end
    end
    if diff then k.diff = diff end
    if size then k.size = size end
    return
  end
  db.kills[#db.kills + 1] = { enc = enc, map = map, diff = diff or idiff, size = size or maxPlayers, t = t,
                              realm = GetRealmName(), npcs = npcs }
  prune()
  if ns.Share then ns.Share.Kick() end
end

local function killFor(enc, t)
  for i = #db.kills, 1, -1 do
    local k = db.kills[i]
    if t - k.t > CORPSE_WINDOW then break end
    if k.enc == enc then return k end
  end
  local map, diff, maxPlayers = instance()
  if not map then return end
  local k = { enc = enc, map = map, diff = diff, size = maxPlayers, t = t, realm = GetRealmName(), npcs = {}, implied = true }
  db.kills[#db.kills + 1] = k
  return k
end

local function itemOf(link)
  if type(link) ~= "string" or secret(link) then return end
  return tonumber(link:match("|Hitem:(%d+)"))
end

local function onHistory(enc)
  if type(enc) ~= "number" or secret(enc) then return end
  local api = C_LootHistory
  if not (api and api.GetSortedDropsForEncounter) then return end
  local ok, drops = pcall(api.GetSortedDropsForEncounter, enc)
  if not ok or type(drops) ~= "table" or secret(drops) then return end
  local histNow
  if api.GetLootHistoryTime then
    local ok2, v = pcall(api.GetLootHistoryTime)
    if ok2 and type(v) == "number" and not secret(v) then histNow = v end
  end
  local t, k = now(), nil
  for _, d in ipairs(drops) do
    if type(d) == "table" and not secret(d) then
      local key, id, start = d.lootListKey, itemOf(d.itemHyperlink), d.startTime
      if type(key) == "number" and not secret(key) and id then
        local age = 0
        if histNow and type(start) == "number" and not secret(start) then age = math.max(0, histNow - start) end
        k = k or killFor(enc, t)
        if not k then return end
        if t - age >= k.t - HISTORY_SLACK then
          k.rollKeys = k.rollKeys or {}
          if not k.rollKeys[key] then
            k.rollKeys[key] = true
            k.rolls = k.rolls or {}
            k.rolls[id] = (k.rolls[id] or 0) + 1
          end
        end
      end
    end
  end
end

local function onReceived(enc, itemID, quantity)
  if type(enc) ~= "number" or secret(enc) or type(itemID) ~= "number" or secret(itemID) then return end
  local k = killFor(enc, now())
  if not k then return end
  local n = (type(quantity) == "number" and not secret(quantity) and quantity > 0) and quantity or 1
  k.awarded = k.awarded or {}
  if n > (k.awarded[itemID] or 0) then k.awarded[itemID] = n end
end

local function readLoot()
  local per, order = {}, {}
  for slot = 1, GetNumLootItems() do
    if GetLootSlotType(slot) == ITEM_SLOT then
      local _, _, _, _, _, _, isQuest, questID = GetLootSlotInfo(slot)
      local id = itemOf(GetLootSlotLink(slot))
      if id and not (isQuest or questID) then
        local src = { GetLootSourceInfo(slot) }
        for i = 1, #src - 1, 2 do
          local guid, n = src[i], src[i + 1]
          if type(guid) == "string" and type(n) == "number" and not secret(guid) and not secret(n) then
            local got = per[guid]
            if not got then got = {}; per[guid] = got; order[#order + 1] = guid end
            got[id] = (got[id] or 0) + n
          end
        end
      end
    end
  end
  return per, order
end

local function mergeInto(dst, src, addNew)
  for id, n in pairs(src) do
    if dst[id] then
      if n > dst[id] then dst[id] = n end
    elseif addNew then
      dst[id] = n
    end
  end
end

local function attribute(what, id, copy, map, t)
  if what == "npc" then
    for i = #db.kills, 1, -1 do
      local k = db.kills[i]
      if t - k.t > CORPSE_WINDOW then break end
      if k.map == map and (not k.copy or k.copy == copy) and has(k.npcs, id) then return k, "boss" end
    end
    if db.bosses[id] then return nil, "implied" end
    return
  end
  for i = #db.kills, 1, -1 do
    local k = db.kills[i]
    if t - k.t > CHEST_WINDOW then return end
    if k.map == map and (not k.copy or k.copy == copy) then
      if not k.corpse and not k.chest then return k, "chest" end
      return
    end
  end
end

-- 只記首領屍體和首領寶箱（小怪的不記，存檔不會越來越大）
local function remember(guid, items, map, t)
  local what, id, copy, gmap = parseSource(guid)
  if not what then return end
  local rec = db.loot[guid]
  if rec then
    mergeInto(rec.items, items, fresh[guid])
    return
  end
  map = gmap or map
  local k, how = attribute(what, id, copy, map, t)
  if how == "implied" then           -- 認得的首領屍體，但沒收到這次的首領戰結束（例如剛 /reload）
    local _, diff, maxPlayers = instance()
    k = { enc = db.bosses[id], map = map, diff = diff, size = maxPlayers, t = t, realm = GetRealmName(), npcs = { id }, implied = true }
    db.kills[#db.kills + 1] = k
    how = "boss"
  end
  if not k then return end
  fresh[guid] = true
  db.loot[guid] = { t = t, map = map, copy = copy, items = items, enc = k.enc, kt = k.t, how = how }
  if how == "boss" then k.corpse, k.copy = true, k.copy or copy else k.chest = true end
  if ns.Share then ns.Share.Kick() end
end

local function onLoot(fromItem)
  if fromItem or skipWindow or not D.Active() then return end
  if GetTime() - gatheredAt <= GATHER_WINDOW or (IsFishingLoot and IsFishingLoot()) then
    skipWindow = true
    return
  end
  local map = instance()
  if not map or not GetLootSourceInfo then return end
  local per, order = readLoot()
  local t = now()
  for _, guid in ipairs(order) do
    if next(per[guid]) then remember(guid, per[guid], map, t) end
  end
end

-- 給 Share.lua：一次擊殺整理成網站上傳用的樣子（和 /report 上傳頁的 extractLoot 一樣）
-- 回傳 {enc, map, diff, size, t, realm, copy, full, items = {[物品]=數量}}
function D.Summaries(src)
  src = src or db
  local attached = {}
  for _, rec in pairs(src.loot or {}) do
    if type(rec) == "table" and (rec.how == "boss" or rec.how == "chest") and rec.enc and rec.kt then
      local key = rec.enc .. "|" .. rec.kt
      attached[key] = attached[key] or {}
      table.insert(attached[key], rec)
    end
  end
  local out = {}
  for _, k in ipairs(src.kills or {}) do
    if type(k) == "table" and type(k.enc) == "number" and type(k.t) == "number" then
      local recs = attached[k.enc .. "|" .. k.t] or {}
      local items = {}
      for _, rec in ipairs(recs) do
        for id, n in pairs(rec.items or {}) do items[id] = (items[id] or 0) + n end
      end
      for _, t in ipairs({ k.rolls or {}, k.awarded or {} }) do
        for id, n in pairs(t) do if n > (items[id] or 0) then items[id] = n end end
      end
      local copy = k.copy
      if copy == nil then for _, rec in ipairs(recs) do copy = copy or rec.copy end end
      out[#out + 1] = { enc = k.enc, map = k.map, diff = k.diff, size = k.size, t = math.floor(k.t), realm = k.realm or "",
                        copy = copy, full = #recs > 0, items = items }
    end
  end
  return out
end

function D.Status()
  if standalone() then return "這台電腦裝了阿莫比掉落記錄插件（AmobiLoot），由它記，這裡不重複記。" end
  local n, looted = #db.kills, 0
  for _, k in ipairs(db.kills) do
    if k.corpse or k.chest or k.rolls or k.awarded then looted = looted + 1 end
  end
  if n == 0 then return "還沒記到首領擊殺。" end
  return ("記了 %d 次首領擊殺，其中 %d 次記到掉落。"):format(n, looted)
end

function D.Init()
  ns.db.drops = type(ns.db.drops) == "table" and ns.db.drops or {}
  db = ns.db.drops
  for _, k in ipairs({ "kills", "loot", "bosses" }) do
    if type(db[k]) ~= "table" then db[k] = {} end
  end
  prune()
  local function on(event, fn)
    ns.On(event, function(...) if D.Active() then fn(...) end end)
  end
  on("ENCOUNTER_END", function(enc, _, diff, size, success, units) encounterEnd(enc, diff, size, success == 1 or success == true, units) end)
  on("BOSS_KILL", function(enc) encounterEnd(enc, nil, nil, true, nil) end)
  on("LOOT_READY", function() onLoot(false) end)
  on("LOOT_SLOT_CHANGED", function() onLoot(false) end)
  on("LOOT_OPENED", function(_, fromItem) onLoot(fromItem) end)
  ns.On("LOOT_CLOSED", function() skipWindow = false; wipe(fresh) end)
  on("LOOT_HISTORY_UPDATE_ENCOUNTER", onHistory)
  on("LOOT_HISTORY_UPDATE_DROP", onHistory)
  on("ENCOUNTER_LOOT_RECEIVED", function(enc, itemID, _, quantity) onReceived(enc, itemID, quantity) end)
  on("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit == "player" and type(spellID) == "number" and not secret(spellID) and GATHER[spellID] then gatheredAt = GetTime() end
  end)
end

ns.Register(D)
