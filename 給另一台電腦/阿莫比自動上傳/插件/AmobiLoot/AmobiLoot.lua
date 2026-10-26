-- 阿莫比掉落記錄（AmobiLoot）
--
-- 《魔獸世界：永恆》的遊戲檔裡沒有首領掉落表（地城手冊的資料表全是空的），所以由玩家打副本時記下來，
-- 彙整後放到阿莫比網站（wowamobi.com）的副本頁。這個插件只做兩件事：
--   1. 首領擊殺：首領戰成功結束（ENCOUNTER_END）時，記首領編號（遊戲 DungeonEncounter 的編號，和網站副本資料庫一樣）、
--      副本、難度、隊伍人數、伺服器時間，以及事件附上的這場首領生物編號（拿來認首領的屍體）。
--   2. 掉落：打開拾取視窗（LOOT_READY／LOOT_OPENED）時，記每一格的物品和數量。GetLootSourceInfo 會說每一格來自哪具屍體
--      或哪個寶箱（來源 GUID）：是剛打完的首領，就記成那次擊殺的掉落。
--   3. 隊伍擲骰的物品（1.1.0，老闆 10/22「開服一起記」）：自己沒打開屍體也記得到這場掉了什麼。遊戲的「掉落紀錄」
--      （C_LootHistory）照首領列出擲骰的物品；首領的東西分給隊上某人時有 ENCOUNTER_LOOT_RECEIVED（永恆的參數只有
--      首領、物品、數量）。都記在那次擊殺的 rolls／awarded，不讀誰擲骰、誰拿走。
-- 同一具屍體、同一個寶箱只算一次：用來源 GUID 去重，開幾次都一樣；之後再開只會更新數量，不會多出東西。
-- 剝皮、採礦、採草、偷竊、釣魚開出來的不記。
--
-- 只被動讀遊戲給的資訊：不會替你撿東西、擲骰、選目標、點任何東西或發話。不存任何玩家的名字。
-- 存檔：AmobiLootDB（WTF\Account\<帳號>\SavedVariables\AmobiLoot.lua）；彙整成網站的數字：tools\amobi_loot.py。
-- 指令：/amobiloot 看記了多少；/amobiloot quiet 打完首領不在聊天框說；/amobiloot loud 恢復。

local ADDON = ...

local KILL_SAME = 5            -- 秒：同一個首領、伺服器時間差 5 秒內的事件是同一次擊殺（ENCOUNTER_END 和 BOSS_KILL 都會來）
local CORPSE_WINDOW = 2 * 3600 -- 秒：擊殺後 2 小時內打開首領屍體都算這次（團隊分裝備可能拖很久）
local CHEST_WINDOW = 15 * 60   -- 秒：打完首領 15 分鐘內打開的寶箱，而且這次擊殺還沒記到首領屍體，才算首領的寶箱
local GATHER_WINDOW = 2.5      -- 秒：剝皮、採礦、採草、偷竊成功後這麼快打開的拾取視窗，是採集出來的，不記
local MAX_OTHER = 1500         -- 副本裡不是首領的屍體和寶箱：最多留 1500 筆（舊的先刪），之後分析用，網站不用
local ITEM_SLOT = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1
local HISTORY_SLACK = 120      -- 秒：掉落紀錄裡的物品要在這次擊殺前 2 分鐘以後才算（同一個首領上一次的紀錄遊戲會留著）

-- 剝皮、偷竊、採草藥、採礦，以及從屍體採礦、採草、拆零件的技能。來源：永恆客戶端 1.60.1.70245 的 SpellEffect 表，
-- 效果是剝皮（95）、偷竊（71）、開鎖類的草藥（33／2）和礦（33／3）。同名的其他等級，登入後用名稱補上。
local GATHER = {}
for _, id in ipairs({ 8613, 8617, 8618, 10768, 1235230, 1235236, 1235244, 921, 5967,
                      2366, 2368, 2369, 2371, 3570, 11993, 1312650,
                      2575, 2576, 2577, 2578, 2579, 3564, 10248, 1264639 }) do
  GATHER[id] = true
end
local gatherNames = {}

local frame = CreateFrame("Frame")
local db
local gatheredAt = -100   -- 上一次採集成功的時間（GetTime）
local skipWindow = false  -- 開著的這個拾取視窗是採集或釣魚來的
local fresh = {}          -- 這個拾取視窗裡才第一次記下的來源（同一個視窗裡，可以補上剛剛還沒讀到的格子）
local lastMap

local function tell(msg) print("|cffe9cb88阿莫比掉落|r " .. msg) end
local function say(msg) if not db.settings.quiet then tell(msg) end end
local function now() return GetServerTime and GetServerTime() or time() end

-- 新版客戶端在副本裡可能把某些值換成「秘密值」，插件不能比較、也不能存檔；遇到就略過，記一筆
local function hidden(v)
  if (issecretvalue and issecretvalue(v)) or (type(v) == "table" and issecrettable and issecrettable(v)) then
    db.stats.hidden = db.stats.hidden + 1
    return true
  end
  return false
end

local function has(list, v)
  for _, x in ipairs(list) do
    if x == v then return true end
  end
  return false
end

local function total(items)
  local n = 0
  for _, q in pairs(items) do n = n + q end
  return n
end

local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end

-- 來源 GUID：屍體「Creature-0-伺服器-地圖-副本分身-生物編號-流水號」，寶箱「GameObject-…-物件編號-流水號」。
-- 玩家、背包裡打開的東西（蚌殼、箱子）等等不是副本的掉落，回傳 nil。
local function parseSource(guid)
  local kind, map, copy, id = guid:match("^(%a+)%-%d+%-%d+%-(%d+)%-(%d+)%-(%d+)%-%x+$")
  if kind == "Creature" or kind == "Vehicle" then return "npc", tonumber(id), copy, tonumber(map) end
  if kind == "GameObject" then return "obj", tonumber(id), copy, tonumber(map) end
end

-- 只在副本（地城、團隊副本）裡記：回傳地圖編號、難度、人數上限、副本名稱
local function instance()
  local name, kind, diff, _, maxPlayers, _, _, map = GetInstanceInfo()
  if kind ~= "party" and kind ~= "raid" then return end
  return map, diff, maxPlayers, name
end

local function lootMethod()
  local get = C_PartyInfo and C_PartyInfo.GetLootMethod or GetLootMethod
  if not get then return end
  local ok, m = pcall(get)
  if ok and (type(m) == "number" or type(m) == "string") and not hidden(m) then return m end
end

local function killsOf(enc)
  local n = 0
  for _, k in ipairs(db.kills) do
    if k.enc == enc then n = n + 1 end
  end
  return n
end

local function nameOf(enc)
  for i = #db.kills, 1, -1 do
    if db.kills[i].enc == enc and db.kills[i].name then return db.kills[i].name end
  end
  return "#" .. enc
end

local function findKill(enc, t)
  for i = #db.kills, 1, -1 do
    local k = db.kills[i]
    if k.enc == enc and math.abs(t - k.t) <= KILL_SAME then return k end
    if t - k.t > CORPSE_WINDOW then return end
  end
end

-- 首領戰結束（ENCOUNTER_END）或首領被殺（BOSS_KILL）。units 是 ENCOUNTER_END 附上的這場首領 { creatureID = … }，
-- 打輸也記住這些生物是哪個首領（之後沒收到首領戰結束，也認得出屍體）；打贏才記一次擊殺。
local function encounterEnd(enc, name, diff, size, success, units)
  if type(enc) ~= "number" or hidden(enc) then return end
  local map, idiff, maxPlayers, inst = instance()
  if not map then return end
  local npcs = {}
  if type(units) == "table" and not hidden(units) then
    for _, u in ipairs(units) do
      local id = type(u) == "table" and u.creatureID
      if type(id) == "number" and not hidden(id) then
        npcs[#npcs + 1] = id
        db.bosses[id] = enc
      end
    end
  end
  if not success then return end
  local t = now()
  local k = findKill(enc, t)
  if k then                          -- 同一次擊殺的另一個事件：補上缺的
    for _, id in ipairs(npcs) do
      if not has(k.npcs, id) then k.npcs[#k.npcs + 1] = id end
    end
    if diff then k.diff = diff end
    if size then k.size = size end
    return
  end
  if type(name) ~= "string" or hidden(name) then name = nil end
  k = { enc = enc, name = name, map = map, inst = inst, diff = diff or idiff, size = size or maxPlayers,
        members = GetNumGroupMembers and GetNumGroupMembers() or nil, t = t, realm = GetRealmName(),
        npcs = npcs, method = lootMethod() }
  db.kills[#db.kills + 1] = k
  say(("記下首領擊殺：%s（這個首領第 %d 次）。打開屍體或寶箱看一眼，就會記下掉落。"):format(name or nameOf(enc), killsOf(enc)))
end

-- 這個首領最近一次（2 小時內）的擊殺；沒有的話（例如剛 /reload 沒收到首領戰結束）在副本裡補一筆 implied
local function killFor(enc, t)
  for i = #db.kills, 1, -1 do
    local k = db.kills[i]
    if t - k.t > CORPSE_WINDOW then break end
    if k.enc == enc then return k end
  end
  local map, diff, maxPlayers, inst = instance()
  if not map then return end
  local k = { enc = enc, name = nameOf(enc), map = map, inst = inst, diff = diff, size = maxPlayers, t = t,
              realm = GetRealmName(), npcs = {}, method = lootMethod(), implied = true }
  if k.name:sub(1, 1) == "#" then k.name = nil end
  db.kills[#db.kills + 1] = k
  return k
end

local function itemOf(link)
  if type(link) ~= "string" or hidden(link) then return end
  return tonumber(link:match("|Hitem:(%d+)"))
end

-- 遊戲的掉落紀錄：這個首領的每一件擲骰物品（lootListKey 是這件的編號，同一件只算一次）。
-- 掉落紀錄會留著同一個首領上一次的東西，所以用 startTime 和 GetLootHistoryTime 算這件是多久以前掉的，
-- 比這次擊殺早超過 HISTORY_SLACK 的不算
local function onHistory(enc)
  if type(enc) ~= "number" or hidden(enc) then return end
  local api = C_LootHistory
  if not (api and api.GetSortedDropsForEncounter) then return end
  local ok, drops = pcall(api.GetSortedDropsForEncounter, enc)
  if not ok or type(drops) ~= "table" or hidden(drops) then return end
  local histNow
  if api.GetLootHistoryTime then
    local ok2, v = pcall(api.GetLootHistoryTime)
    if ok2 and type(v) == "number" and not hidden(v) then histNow = v end
  end
  local t, k, added = now(), nil, 0
  for _, d in ipairs(drops) do
    if type(d) == "table" and not hidden(d) then
      local key, id, start = d.lootListKey, itemOf(d.itemHyperlink), d.startTime
      if type(key) == "number" and not hidden(key) and id then
        local age = 0
        if histNow and type(start) == "number" and not hidden(start) then age = math.max(0, histNow - start) end
        k = k or killFor(enc, t)
        if not k then return end
        if t - age >= k.t - HISTORY_SLACK then
          k.rollKeys = k.rollKeys or {}
          if not k.rollKeys[key] then
            k.rollKeys[key] = true
            k.rolls = k.rolls or {}
            k.rolls[id] = (k.rolls[id] or 0) + 1
            added = added + 1
          end
        end
      end
    end
  end
  if added > 0 then
    say(("記下%s的擲骰物品：%d 件。"):format(k.name or nameOf(enc), added))
  end
end

-- 首領的東西分給隊上某人（ENCOUNTER_LOOT_RECEIVED）：同一件物品記最大的數量
local function onReceived(enc, itemID, quantity)
  if type(enc) ~= "number" or hidden(enc) or type(itemID) ~= "number" or hidden(itemID) then return end
  local k = killFor(enc, now())
  if not k then return end
  local n = (type(quantity) == "number" and not hidden(quantity) and quantity > 0) and quantity or 1
  k.awarded = k.awarded or {}
  if n > (k.awarded[itemID] or 0) then k.awarded[itemID] = n end
end

-- 拾取視窗裡的每一格：物品編號、數量，分到各自的來源（範圍拾取時，一格可能來自好幾具屍體）
local function readLoot()
  local per, order = {}, {}
  for slot = 1, GetNumLootItems() do
    if GetLootSlotType(slot) == ITEM_SLOT then
      local _, name, _, _, quality, _, isQuest, questID = GetLootSlotInfo(slot)
      local link = GetLootSlotLink(slot)
      local id = type(link) == "string" and not hidden(link) and tonumber(link:match("|Hitem:(%d+)"))
      if id then
        if not db.items[id] and type(name) == "string" and not hidden(name) then
          db.items[id] = { name, type(quality) == "number" and not hidden(quality) and quality or nil }
        end
        local bag = (isQuest or questID) and "quest" or "items"
        local src = { GetLootSourceInfo(slot) }
        if #src == 0 then db.stats.nosource = db.stats.nosource + 1 end
        for i = 1, #src - 1, 2 do
          local guid, n = src[i], src[i + 1]
          if type(guid) == "string" and type(n) == "number" and not hidden(guid) and not hidden(n) then
            local got = per[guid]
            if not got then
              got = { items = {}, quest = {} }
              per[guid] = got
              order[#order + 1] = guid
            end
            got[bag][id] = (got[bag][id] or 0) + n
          end
        end
      else
        db.stats.nolink = db.stats.nolink + 1
      end
    end
  end
  return per, order
end

-- 同一個來源又讀了一次：數量取大的。這個視窗才第一次記的來源（剛剛有格子還沒讀到）才可以補上新的物品；
-- 以前就記過的屍體再開，多出來的東西不是首領掉的（例如剝皮），不加
local function mergeInto(dst, src, addNew)
  for id, n in pairs(src) do
    if dst[id] then
      if n > dst[id] then dst[id] = n end
    elseif addNew then
      dst[id] = n
    end
  end
end

-- 這具屍體或這個寶箱是哪一次首領擊殺的：
--   屍體：生物編號是某次擊殺（同一個副本分身、2 小時內）的首領；認得是首領但沒有那次擊殺 → "implied"
--   寶箱：最近一次擊殺（同一個副本分身、15 分鐘內），而且那次還沒記到首領屍體、也還沒有別的寶箱
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

local function remember(guid, got, map, t)
  local what, id, copy, gmap = parseSource(guid)
  if not what then return end
  local rec = db.loot[guid]
  if rec then
    mergeInto(rec.items, got.items, fresh[guid])
    if next(got.quest) then
      rec.quest = rec.quest or {}
      mergeInto(rec.quest, got.quest, fresh[guid])
    end
    return
  end
  fresh[guid] = true
  map = gmap or map
  rec = { t = t, map = map, copy = copy, items = got.items, quest = next(got.quest) and got.quest or nil }
  rec[what] = id
  db.loot[guid] = rec
  local k, how = attribute(what, id, copy, map, t)
  if how == "implied" then           -- 認得的首領屍體，但沒收到這次的首領戰結束（例如那時在讀取畫面、剛 /reload）
    local _, diff, maxPlayers, inst = instance()
    local enc = db.bosses[id]
    k = { enc = enc, name = nameOf(enc), map = map, inst = inst, diff = diff, size = maxPlayers, t = t,
          realm = GetRealmName(), npcs = { id }, method = lootMethod(), implied = true }
    if k.name:sub(1, 1) == "#" then k.name = nil end
    db.kills[#db.kills + 1] = k
    how = "boss"
  end
  if k then
    rec.enc, rec.kt, rec.how = k.enc, k.t, how
    if how == "boss" then
      k.corpse, k.copy = true, k.copy or copy
    else
      k.chest = true
    end
    say(("記下%s的掉落：%d 件%s。"):format(k.name or nameOf(k.enc), total(rec.items), how == "chest" and "（寶箱）" or ""))
    return
  end
  -- 不是首領的：留著之後分析（小怪掉落、認出漏掉的首領），網站不用；最多 MAX_OTHER 筆
  local last = db.kills[#db.kills]
  if last and last.map == map and t - last.t <= CHEST_WINDOW then rec.after, rec.dt = last.enc, t - last.t end
  db.others[#db.others + 1] = guid
  local extra = #db.others - MAX_OTHER
  if extra > 0 then
    local keep = {}
    for i = 1, #db.others do
      if i <= extra then db.loot[db.others[i]] = nil else keep[#keep + 1] = db.others[i] end
    end
    db.others = keep
  end
end

local function onLoot(fromItem)
  if fromItem or skipWindow then return end
  if GetTime() - gatheredAt <= GATHER_WINDOW or (IsFishingLoot and IsFishingLoot()) then
    skipWindow = true
    db.stats.gathered = db.stats.gathered + 1
    return
  end
  local map = instance()
  if not map or not GetLootSourceInfo then return end
  local per, order = readLoot()
  local t = now()
  for _, guid in ipairs(order) do
    if next(per[guid].items) then remember(guid, per[guid], map, t) end
  end
end

local function noteCast(spellID)
  if type(spellID) ~= "number" or hidden(spellID) then return end
  if GATHER[spellID] or gatherNames[spellName(spellID) or ""] then gatheredAt = GetTime() end
end

local function status()
  local bosses, nb, looted = {}, 0, 0
  for _, k in ipairs(db.kills) do
    if not bosses[k.enc] then bosses[k.enc], nb = true, nb + 1 end
    if k.corpse or k.chest or k.rolls or k.awarded then looted = looted + 1 end
  end
  tell(("記了 %d 次首領擊殺（%d 個首領），其中 %d 次記到掉落。"):format(#db.kills, nb, looted))
  local k = db.kills[#db.kills]
  if k then
    local items = 0
    for _, rec in pairs(db.loot) do
      if rec.enc == k.enc and rec.kt == k.t then items = items + total(rec.items) end
    end
    tell(("最近一次：%s%s，%s%s。"):format(k.inst and (k.inst .. "・") or "", k.name or nameOf(k.enc), date("%m/%d %H:%M", k.t),
      (k.corpse or k.chest) and ("，掉落 " .. items .. " 件") or k.rolls and "，記到隊伍擲骰的物品" or "，還沒記到掉落（打開屍體或寶箱看一眼）"))
  end
  if #db.kills > 0 then
    tell("要回報給阿莫比：/reload 或登出後，到 wowamobi.com/report 上傳存檔 AmobiLoot.lua。")
  end
  if db.settings.quiet then tell("目前打完首領不會在聊天框說，但照樣會記（/amobiloot loud 恢復）。") end
  if db.stats.errors > 0 then
    tell(("插件出過 %d 次錯：%s。請把存檔交給阿莫比。"):format(db.stats.errors, db.stats.lastError or "?"))
  end
end

local function hello()
  for id in pairs(GATHER) do
    local n = spellName(id)
    if type(n) == "string" and n ~= "" then gatherNames[n] = true end
  end
  if #db.kills == 0 then
    say("已載入：打副本時開著就好。打完首領會自動記下擊殺和隊伍擲骰的物品，打開屍體或寶箱看一眼會記得更完整。/amobiloot 看記了多少。")
  else
    say(("已載入：記了 %d 次首領擊殺。/amobiloot 看記了多少。"):format(#db.kills))
  end
  if not GetLootSourceInfo then
    tell("這個遊戲版本沒有 GetLootSourceInfo，認不出東西是哪具屍體掉的：只會記首領擊殺。請告訴阿莫比。")
  end
end

local function enterWorld()
  local map, _, _, inst = instance()
  if map and map ~= lastMap then
    say(("在%s：打完首領打開屍體或寶箱看一眼，就會記下擊殺和掉落。"):format(inst or "副本裡"))
  end
  lastMap = map
end

local function init()
  AmobiLootDB = type(AmobiLootDB) == "table" and AmobiLootDB or {}
  db = AmobiLootDB
  db.version = 1
  for _, key in ipairs({ "kills", "loot", "others", "bosses", "items", "settings", "stats" }) do
    if type(db[key]) ~= "table" then db[key] = {} end
  end
  for _, key in ipairs({ "hidden", "nosource", "nolink", "gathered", "errors" }) do
    db.stats[key] = db.stats[key] or 0
  end
  local version, build, _, interface = GetBuildInfo()
  local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  db.client = { version = version, build = build, interface = interface, locale = GetLocale(),
                addon = meta and meta(ADDON, "Version") or nil }
end

-- 插件自己出錯時不跳錯誤視窗、不打擾玩遊戲：記在存檔裡，/amobiloot 會說
local function safely(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    db.stats.errors = db.stats.errors + 1
    db.stats.lastError = tostring(err):sub(1, 200)
  end
end

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    frame:UnregisterEvent("ADDON_LOADED")
    init()
    for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ENCOUNTER_END", "BOSS_KILL",
                         "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CHANGED", "LOOT_CLOSED" }) do
      frame:RegisterEvent(e)
    end
    -- 隊伍擲骰的物品（舊版客戶端沒有這些事件，註冊不了就算了）
    for _, e in ipairs({ "LOOT_HISTORY_UPDATE_ENCOUNTER", "LOOT_HISTORY_UPDATE_DROP", "ENCOUNTER_LOOT_RECEIVED" }) do
      pcall(frame.RegisterEvent, frame, e)
    end
    if frame.RegisterUnitEvent then
      frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    else
      frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    end
  elseif not db then
    return
  elseif event == "ENCOUNTER_END" then
    local enc, name, diff, size, success, units = ...
    safely(encounterEnd, enc, name, diff, size, success == 1 or success == true, units)
  elseif event == "BOSS_KILL" then
    local enc, name = ...
    safely(encounterEnd, enc, name, nil, nil, true, nil)
  elseif event == "LOOT_READY" or event == "LOOT_SLOT_CHANGED" then
    safely(onLoot, false)
  elseif event == "LOOT_OPENED" then
    local _, fromItem = ...
    safely(onLoot, fromItem)
  elseif event == "LOOT_CLOSED" then
    skipWindow = false
    wipe(fresh)
  elseif event == "LOOT_HISTORY_UPDATE_ENCOUNTER" or event == "LOOT_HISTORY_UPDATE_DROP" then
    local enc = ...
    safely(onHistory, enc)
  elseif event == "ENCOUNTER_LOOT_RECEIVED" then
    local enc, itemID, _, quantity = ...
    safely(onReceived, enc, itemID, quantity)
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local unit, _, spellID = ...
    if unit == "player" then safely(noteCast, spellID) end
  elseif event == "PLAYER_LOGIN" then
    safely(hello)
  elseif event == "PLAYER_ENTERING_WORLD" then
    safely(enterWorld)
  end
end)
frame:RegisterEvent("ADDON_LOADED")

SLASH_AMOBILOOT1, SLASH_AMOBILOOT2 = "/amobiloot", "/aml"
SlashCmdList.AMOBILOOT = function(msg)
  if not db then return end
  msg = strtrim(msg or ""):lower()
  if msg == "quiet" then
    db.settings.quiet = true
    tell("好，之後打完首領不在聊天框說（還是照樣記）。/amobiloot loud 恢復。")
  elseif msg == "loud" then
    db.settings.quiet = false
    tell("好，打完首領、記到掉落都會在聊天框說一聲。")
  elseif msg == "help" then
    tell("/amobiloot 看記了多少；/amobiloot quiet 打完首領不在聊天框說；/amobiloot loud 恢復。")
  else
    status()
  end
end
