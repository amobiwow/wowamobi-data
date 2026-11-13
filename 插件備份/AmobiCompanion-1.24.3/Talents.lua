-- 阿莫比小幫手：天賦一鍵套用
--
-- 玩家在 wowamobi.com 的天賦模擬器（/talents）或傳承樹（/legacy）配好點數，按「複製到小幫手」，進遊戲貼上就套用。
-- 代碼（和天賦模擬器講好的格式）：
--   天賦   AMOBI1:T:<職業>:<節點>-<級數>,<節點>-<級數>,…   例：AMOBI1:T:MAGE:105958-3,105957-5
--   傳承樹 AMOBI1:L:<節點>-<級數>,…
--   節點是遊戲的 TraitNode 編號（網站 talents.json／legacy.json 的 talents[].id），順序照網站的分頁、層、欄。
-- 也接受直接貼網站網址：/talents?c=MAGE&b=…&t=…、/legacy?b=…（b 用 Data\Talents.lua 打包的天賦順序解）。
--
-- 套用的作法和遊戲自己的天賦視窗一樣（Blizzard_PlayerSpells、Blizzard_LegacySystem，camelot 版）：
--   1. 先算好計畫：每個天賦目前幾級、要到幾級、要花幾點、點數夠不夠；有要降級的天賦就整棵先重置（遊戲的重置按鈕也是這樣，免費）
--   2. 跳確認視窗，列出會點哪些、要花多少點；玩家按「套用」才動手
--   3. C_Traits.PurchaseRank 一點一點排進去（照節點條件：先點完前面的層，前置天賦先點），全部排好才一次送出
--      （職業天賦 C_ClassTalents.CommitConfig、傳承樹 C_Traits.CommitConfig），遊戲回 TRAIT_CONFIG_UPDATED 才算成功
--   4. 有任何一點排不進去（條件不符）就整個取消（RollbackConfig），不會留下半套
-- 只在戰鬥外、沒有插件限制時做；這些都不是受保護的函式。
-- 匯出：讀目前每個天賦的級數，照網站的編法組成網址（t＝傳承樹「天分」點了幾階）。

local _, ns = ...
local T = {}
ns.Talents = T
local TD = ns.TalentData

local COMMIT_WAIT = 15    -- 秒：送出後等遊戲回覆多久
local LEGACY_GAP = 0.25   -- 秒：傳承樹分好幾棵分開送出時，等上一棵送完再送下一棵

-- ---------------------------------------------------------------------------- 代碼
local function parseList(list)
  local ranks, order = {}, {}
  if list == "" then return nil, "代碼裡沒有點任何天賦。" end
  for item in (list .. ","):gmatch("([^,]*),") do
    local node, rank = item:match("^(%d+)%-(%d+)$")
    node, rank = tonumber(node), tonumber(rank)
    if not node or not rank or rank < 1 or rank > 9 then return nil, "代碼不完整或被改過，請重新複製。" end
    if ranks[node] then return nil, "代碼裡同一個天賦出現兩次，請重新複製。" end
    ranks[node] = rank
    order[#order + 1] = node
  end
  return ranks, order
end

-- 網站網址的 b：每個分頁的級數（依層、欄排序）以 - 分隔
local function decodeB(tabs, b)
  local ranks, order = {}, {}
  if b ~= "" and not b:match("^[%d%-]+$") then return nil, "網址裡的配點看不懂，請重新複製。" end
  local ti = 0
  for seg in (b .. "-"):gmatch("([^%-]*)%-") do
    ti = ti + 1
    local tab = tabs[ti]
    if tab then
      for i = 1, #seg do
        local n, node = tonumber(seg:sub(i, i)), tab.nodes[i]
        if node and n > 0 then
          ranks[node] = math.min(n, tab.max[i])
          order[#order + 1] = node
        end
      end
    end
  end
  if #order == 0 then return nil, "網址裡沒有點任何天賦。" end
  return ranks, order
end

local function query(q)
  local out = {}
  for k, v in (q or ""):gmatch("([^&=]+)=([^&]*)") do out[k] = v end
  return out
end

-- 回傳 { kind = "T"／"L", class = 職業, ranks = { [節點] = 級數 }, order = { 節點… } } 或 nil, 原因
function T.Parse(text)
  text = (text or ""):gsub("%s+", "")
  if text == "" then return nil, "先貼上代碼或網址。" end
  local head = text:sub(1, 7):upper()
  if head == "AMOBI1:" then
    local kind, rest = text:sub(8):match("^([TtLl]):(.*)$")
    kind = kind and kind:upper()
    if kind == "T" then
      local token, list = rest:match("^(%a+):(.*)$")
      if not token then return nil, "代碼不完整，請重新複製。" end
      token = token:upper()
      if not TD.classes[token] then return nil, "代碼裡的職業看不懂：" .. token end
      local ranks, order = parseList(list)
      if not ranks then return nil, order end
      return { kind = "T", class = token, ranks = ranks, order = order }
    elseif kind == "L" then
      local ranks, order = parseList(rest)
      if not ranks then return nil, order end
      return { kind = "L", ranks = ranks, order = order }
    end
    return nil, "代碼不完整，請重新複製。"
  end
  if head:sub(1, 5) == "AMOBI" then return nil, "這是新版網站的代碼，請更新阿莫比小幫手。" end
  local page, q = text:match("/(%a+)%?([^#]*)")
  if page == "talents" then
    local p = query(q)
    local token = (p.c or ""):upper()
    local cls = TD.classes[token]
    if not cls then return nil, "網址裡沒有職業（c=…），請從天賦模擬器複製。" end
    local ranks, order = decodeB(cls.tabs, p.b or "")
    if not ranks then return nil, order end
    return { kind = "T", class = token, ranks = ranks, order = order, url = true }
  elseif page == "legacy" then
    local ranks, order = decodeB(TD.legacy.tabs, query(q).b or "")
    if not ranks then return nil, order end
    return { kind = "L", ranks = ranks, order = order, url = true }
  end
  return nil, "看不懂這串字：請在阿莫比網站的天賦模擬器或傳承樹按「複製到小幫手」，或貼上網址。"
end

-- ---------------------------------------------------------------------------- 遊戲裡的天賦
local function activeConfig()
  local id = ns.Call(C_ClassTalents, "GetActiveConfigID")
  if type(id) == "number" then return id end
  local group = ns.Call(C_SpecializationInfo, "GetActiveSpecGroup")
  if group then
    id = ns.Call(C_SpecializationInfo, "GetCombatConfigIDForSpecGroup", group)
    if type(id) == "number" then return id end
  end
end
T.ActiveConfig = activeConfig

local nameIndex
local function dataName(node)
  if not nameIndex then
    nameIndex = {}
    local function add(tabs)
      for _, tab in ipairs(tabs) do
        for i, n in ipairs(tab.nodes) do nameIndex[n] = tab.names[i] end
      end
    end
    for _, c in pairs(TD.classes) do add(c.tabs) end
    add(TD.legacy.tabs)
  end
  return nameIndex[node]
end

-- 天賦名稱：打包的資料（和網站一樣）；不在資料裡的（遊戲改版新加的）問遊戲
local function nodeName(configID, node, info)
  local n = dataName(node)
  if n and n ~= "" then return n end
  local entry = info and info.entryIDs and info.entryIDs[1]
  local e = entry and ns.Call(C_Traits, "GetEntryInfo", configID, entry)
  local def = e and e.definitionID and ns.Call(C_Traits, "GetDefinitionInfo", e.definitionID)
  if def then
    if def.overrideName and def.overrideName ~= "" then return def.overrideName end
    local s = def.spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(def.spellID)
    if s then return s end
  end
  return "#" .. node
end

local function rankCost(configID, node)
  local costs = ns.Call(C_Traits, "GetNodeCost", configID, node)
  local c = type(costs) == "table" and costs[1]
  if c and type(c.amount) == "number" and c.amount > 0 then return c.amount end
  return 1
end

local function currency(configID, treeID)
  local list = ns.Call(C_Traits, "GetTreeCurrencyInfo", configID, treeID, true)
  local c = type(list) == "table" and list[1]
  if not c then return nil end
  return { id = c.traitCurrencyID, unspent = c.quantity or 0, spent = c.spentInTree or c.spent or 0 }
end

-- 要套用的天賦樹：職業天賦是一棵（目前啟用的那一組天賦），傳承樹是三棵（全帳號共用）
local function groupsFor(code)
  if code.kind == "T" then
    local configID = activeConfig()
    if not configID then return nil, "讀不到你的天賦（還沒到可以點天賦的等級，或遊戲還沒載入完），等一下再試。" end
    local info = ns.Call(C_Traits, "GetConfigInfo", configID)
    local treeID = info and info.treeIDs and info.treeIDs[1] or TD.classes[code.class].tree
    return { { configID = configID, treeID = treeID } }
  end
  local groups = {}
  for _, tab in ipairs(TD.legacy.tabs) do
    local configID = ns.Call(C_Traits, "GetConfigIDByTreeID", tab.tree)
    if not configID then return nil, "讀不到你的傳承樹（第一個角色到 25 級才開放），等一下再試。" end
    groups[#groups + 1] = { configID = configID, treeID = tab.tree, name = tab.name }
  end
  return groups
end

-- 算計畫：不改任何東西。回傳 plan 或 nil, 原因
function T.Plan(code)
  local why = ns.Restricted()
  if why then return nil, why .. "不能改天賦，打完再試。" end
  if code.kind == "T" then
    local mine = ns.PlayerClass()
    if code.class ~= mine then
      return nil, ("這是%s的天賦，你現在是%s。"):format(ns.ClassName(code.class), ns.ClassName(mine))
    end
  end
  local groups, err = groupsFor(code)
  if not groups then return nil, err end

  local plan = { kind = code.kind, class = code.class, groups = groups, total = 0, refund = 0, staged = false, code = code }
  local where = {}     -- 節點 → 在哪一棵
  for _, g in ipairs(groups) do
    g.nodes, g.adds, g.reset = {}, {}, false
    for _, node in ipairs(ns.Call(C_Traits, "GetTreeNodes", g.treeID) or {}) do
      local info = ns.Call(C_Traits, "GetNodeInfo", g.configID, node)
      if info and info.ID ~= 0 then
        g.nodes[node] = info
        where[node] = g
        local want = code.ranks[node] or 0
        if (info.ranksPurchased or 0) > want then g.reset = true end
      end
    end
    if ns.Call(C_Traits, "ConfigHasStagedChanges", g.configID) then plan.staged = true end
    g.cur = currency(g.configID, g.treeID)
  end

  local missing = 0
  for _, node in ipairs(code.order) do
    local g = where[node]
    if not g then
      missing = missing + 1
    else
      local info, want = g.nodes[node], code.ranks[node]
      if want > (info.maxRanks or want) then
        return nil, ("「%s」最多只有 %d 級，代碼卻要 %d 級：網站和遊戲的版本不同，請更新插件或網站資料。"):format(
          nodeName(g.configID, node, info), info.maxRanks, want)
      end
      local from = g.reset and 0 or (info.ranksPurchased or 0)
      if want > from then
        local cost = rankCost(g.configID, node)
        g.adds[#g.adds + 1] = { node = node, name = nodeName(g.configID, node, info), from = from, to = want,
                                full = want, cost = cost, max = info.maxRanks }
      end
    end
  end
  if missing > 0 then
    return nil, ("代碼裡有 %d 個天賦不在你的%s裡：網站和遊戲的版本可能不同，請更新插件。"):format(
      missing, code.kind == "T" and "天賦樹" or "傳承樹")
  end

  -- 點數：沒用的點＋重置會退回的點；不夠就照順序點到沒點數為止，其他的升級後再套用一次
  local unspent = 0
  for _, g in ipairs(groups) do
    if g.cur then unspent = math.max(unspent, g.cur.unspent) end
    if g.reset and g.cur then plan.refund = plan.refund + g.cur.spent end
  end
  plan.available = unspent + plan.refund
  local budget, need = plan.available, 0
  for _, g in ipairs(groups) do
    for _, a in ipairs(g.adds) do
      need = need + (a.to - a.from) * a.cost
      local can = math.min(a.to - a.from, math.floor(budget / a.cost))
      if can < a.to - a.from then plan.short = true end
      a.to = a.from + math.max(0, can)
      budget = budget - (a.to - a.from) * a.cost
      plan.total = plan.total + (a.to - a.from) * a.cost
    end
  end
  plan.need = need
  plan.resets = 0
  for _, g in ipairs(groups) do if g.reset then plan.resets = plan.resets + 1 end end
  plan.changes = plan.total + plan.resets
  return plan
end

-- 確認視窗的內容
function T.Describe(plan)
  local lines = {}
  local what = plan.kind == "T" and (ns.ClassName(plan.class) .. "天賦") or "傳承樹（全帳號）"
  if plan.staged then lines[#lines + 1] = "|cffffd100天賦視窗裡還沒套用的變更會先取消。|r" end
  for _, g in ipairs(plan.groups) do
    if g.reset then
      lines[#lines + 1] = ("|cffff9050先重置%s（退回 %d 點）|r"):format(g.name and ("「" .. g.name .. "」") or "天賦",
        g.cur and g.cur.spent or 0)
    end
  end
  local shown, skipped = 0, {}
  for _, g in ipairs(plan.groups) do
    for _, a in ipairs(g.adds) do
      if a.to > a.from then
        shown = shown + 1
        if shown <= 16 then
          lines[#lines + 1] = ("  %s  %d → %d%s"):format(a.name, a.from, a.to, a.to < a.full and ("（要 " .. a.full .. "）") or "")
        end
      end
      if a.to < a.full then skipped[#skipped + 1] = a.name end
    end
  end
  if shown > 16 then lines[#lines + 1] = ("  …還有 %d 個天賦"):format(shown - 16) end
  if shown == 0 and plan.resets == 0 then lines[#lines + 1] = "你的" .. what .. "已經和代碼一樣，不用改。" end
  lines[#lines + 1] = ""
  lines[#lines + 1] = ("要花 %d 點，你現在可以用 %d 點%s。"):format(plan.total, plan.available,
    plan.refund > 0 and ("（含重置退回的 " .. plan.refund .. " 點）") or "")
  if plan.short then
    lines[#lines + 1] = ("|cffffd100點數不夠（這套要 %d 點）：先照順序點到沒點數，升級後再套用一次就會補上。|r"):format(plan.need)
    if #skipped > 0 then
      lines[#lines + 1] = "這次點不滿：" .. table.concat(skipped, "、", 1, math.min(#skipped, 6)) .. (#skipped > 6 and "…" or "")
    end
  end
  return ("套用%s？"):format(what), lines
end

-- ---------------------------------------------------------------------------- 套用
local pending   -- 等遊戲回覆的這次套用：{ configs = { [configID] = true }, left = n, done = fn }

local function finish(ok, msg)
  local p = pending
  pending = nil
  if p and p.timer then p.timer.cancelled = true end
  if p and p.done then p.done(ok, msg) end
end

ns.On("TRAIT_CONFIG_UPDATED", function(configID)
  local p = pending
  if not p or ns.Secret(configID) or not p.waiting[configID] then return end
  p.waiting[configID] = nil
  if next(p.waiting) == nil and not p.queue[1] then
    finish(true, p.okText)
  elseif next(p.waiting) == nil then
    C_Timer.After(LEGACY_GAP, function() ns.Try("commit-next", T.CommitNext) end)
  end
end)

ns.On("CONFIG_COMMIT_FAILED", function(configID)
  local p = pending
  if not p or ns.Secret(configID) or not p.waiting[configID] then return end
  ns.Call(C_Traits, "RollbackConfig", configID)
  finish(false, "遊戲沒有接受這次的天賦變更，已經復原。")
end)

-- 把一棵樹的變更排進去（還沒送出）。回傳 true，或 false, 排不進去的天賦名稱
local function stage(plan, g)
  local configID = g.configID
  if g.reset then
    local ok
    if plan.kind == "T" and g.cur and g.cur.id then
      ok = ns.Call(C_Traits, "ResetTreeByCurrency", configID, g.treeID, g.cur.id)
    end
    if not ok then ok = ns.Call(C_Traits, "ResetTree", configID, g.treeID) end
    if not ok then return false, { "重置天賦" } end
  end
  local left = {}
  for _, a in ipairs(g.adds) do
    if a.to > a.from then left[#left + 1] = { a = a, n = a.to - a.from } end
  end
  -- 照順序點；點不上的（前置或層數還沒到）等下一輪，一輪都沒進展就停
  local progress = true
  while progress do
    progress = false
    for _, w in ipairs(left) do
      while w.n > 0 and ns.Call(C_Traits, "PurchaseRank", configID, w.a.node) do
        w.n = w.n - 1
        progress = true
      end
    end
  end
  local failed = {}
  for _, w in ipairs(left) do
    if w.n > 0 then failed[#failed + 1] = w.a.name end
  end
  if #failed > 0 then return false, failed end
  return true
end

local function commit(plan, g)
  if plan.kind == "T" and C_ClassTalents and C_ClassTalents.CommitConfig then
    return ns.Call(C_ClassTalents, "CommitConfig")
  end
  return ns.Call(C_Traits, "CommitConfig", g.configID)
end

local function rollbackAll(plan)
  for _, g in ipairs(plan.groups) do ns.Call(C_Traits, "RollbackConfig", g.configID) end
end

-- 送出佇列裡的下一棵樹（傳承樹每棵分開送出；同一個設定編號的一起送）
function T.CommitNext()
  local p = pending
  if not p then return end
  local why = ns.Restricted()
  if why then
    rollbackAll(p.plan)
    return finish(false, why .. "，沒有套用完：已送出的部分保留，請打完再套用一次。")
  end
  if C_Traits.IsReadyForCommit and not ns.Call(C_Traits, "IsReadyForCommit") then
    p.tries = (p.tries or 0) + 1
    if p.tries > COMMIT_WAIT / LEGACY_GAP then return finish(false, "遊戲一直在忙，沒有套用完，請再試一次。") end
    C_Timer.After(LEGACY_GAP, function() ns.Try("commit-next", T.CommitNext) end)
    return
  end
  local batch = table.remove(p.queue, 1)
  if not batch then return finish(true, p.okText) end
  for _, g in ipairs(batch) do
    local ok, failed = stage(p.plan, g)
    if not ok then
      rollbackAll(p.plan)
      return finish(false, "有天賦點不上去（條件不符）：" .. table.concat(failed, "、") .. "。這次沒有改動。")
    end
  end
  if not ns.Call(C_Traits, "ConfigHasStagedChanges", batch[1].configID) then
    -- 沒有實際變更（例如只是重置後又點回一樣的）：直接下一批
    return T.CommitNext()
  end
  p.waiting[batch[1].configID] = true
  if not commit(p.plan, batch[1]) then
    p.waiting[batch[1].configID] = nil
    rollbackAll(p.plan)
    return finish(false, "遊戲不讓現在改天賦（可能在戰鬥中或正在讀取），已經復原，等一下再試。")
  end
end

-- 照計畫套用（玩家在確認視窗按了「套用」）。done(成功, 訊息) 會在遊戲回覆後呼叫
function T.Apply(plan, done)
  if pending then return done(false, "上一次套用還在等遊戲回覆。") end
  local why = ns.Restricted()
  if why then return done(false, why .. "不能改天賦，打完再試。") end
  if plan.kind == "T" then
    local can, _, err = ns.Call(C_ClassTalents, "CanChangeTalents")
    if can == false then return done(false, "遊戲現在不讓改天賦" .. ((type(err) == "string" and err ~= "") and ("：" .. err) or "。")) end
  end
  if plan.staged then
    -- 天賦視窗裡還沒套用的變更：先取消，再照遊戲裡已生效的天賦重新算一次（確認視窗已經說過會取消）
    rollbackAll(plan)
    local again, err = T.Plan(plan.code)
    if not again then return done(false, err) end
    plan = again
  end
  if plan.changes == 0 then return done(true, "不用改，已經一樣了。") end
  -- 同一個設定編號的樹一起送出
  local queue, byConfig = {}, {}
  for _, g in ipairs(plan.groups) do
    local list = byConfig[g.configID]
    if not list then
      list = {}
      byConfig[g.configID] = list
      queue[#queue + 1] = list
    end
    list[#list + 1] = g
  end
  local okText = plan.short and ("先點了 %d 點；升級後再套用一次會補上其他的。"):format(plan.total)
    or (plan.kind == "T" and "天賦已套用。" or "傳承樹已套用。")
  pending = { plan = plan, queue = queue, waiting = {}, done = done, okText = okText }
  local timer = { cancelled = false }
  pending.timer = timer
  C_Timer.After(COMMIT_WAIT, function()
    if not timer.cancelled and pending and pending.timer == timer then
      finish(false, "還沒收到遊戲回覆：打開天賦視窗看看有沒有套用。")
    end
  end)
  T.CommitNext()
end

-- ---------------------------------------------------------------------------- 匯出
local function encode(tabs, rankOf)
  local parts = {}
  for _, tab in ipairs(tabs) do
    local s = {}
    for _, node in ipairs(tab.nodes) do s[#s + 1] = tostring(math.min(9, rankOf(node))) end
    parts[#parts + 1] = (table.concat(s):gsub("0+$", ""))
  end
  return (table.concat(parts, "-"):gsub("%-+$", ""))
end

local function legacyRanks()
  local ranks, count = {}, 0
  for _, tab in ipairs(TD.legacy.tabs) do
    local configID = ns.Call(C_Traits, "GetConfigIDByTreeID", tab.tree)
    if configID then
      for _, node in ipairs(ns.Call(C_Traits, "GetTreeNodes", tab.tree) or {}) do
        local info = ns.Call(C_Traits, "GetNodeInfo", configID, node)
        if info and (info.ranksPurchased or 0) > 0 then
          ranks[node] = info.ranksPurchased
          count = count + 1
        end
      end
    end
  end
  return ranks, count
end

local function unknown(ranks, tabs)
  local known = {}
  for _, tab in ipairs(tabs) do for _, n in ipairs(tab.nodes) do known[n] = true end end
  local n = 0
  for node in pairs(ranks) do if not known[node] then n = n + 1 end end
  return n
end

-- 回傳網址, 提醒（可能是 nil）；或 nil, 原因
function T.ExportURL(kind)
  if kind == "L" then
    local ranks, count = legacyRanks()
    if count == 0 then return nil, "你的傳承樹還沒有點任何天賦（或還沒開放）。" end
    local b = encode(TD.legacy.tabs, function(n) return ranks[n] or 0 end)
    local miss = unknown(ranks, TD.legacy.tabs)
    return ns.SITE .. "/legacy" .. (b ~= "" and ("?b=" .. b) or ""),
      miss > 0 and ("有 %d 個天賦不在插件的資料裡，網址可能少了它們：請更新插件。"):format(miss) or nil
  end
  local token = ns.PlayerClass()
  local cls = TD.classes[token]
  if not cls then return nil, "插件的資料裡沒有你的職業。" end
  local configID = activeConfig()
  if not configID then return nil, "讀不到你的天賦，等一下再試。" end
  local info = ns.Call(C_Traits, "GetConfigInfo", configID)
  local treeID = info and info.treeIDs and info.treeIDs[1] or cls.tree
  local ranks = {}
  for _, node in ipairs(ns.Call(C_Traits, "GetTreeNodes", treeID) or {}) do
    local n = ns.Call(C_Traits, "GetNodeInfo", configID, node)
    if n and (n.ranksPurchased or 0) > 0 then ranks[node] = n.ranksPurchased end
  end
  local b = encode(cls.tabs, function(n) return ranks[n] or 0 end)
  local lr = legacyRanks()
  local t = TD.legacy.talented and lr[TD.legacy.talented] or 0
  local url = ns.SITE .. "/talents?c=" .. token .. (b ~= "" and ("&b=" .. b) or "") .. (t > 0 and ("&t=" .. t) or "")
  local miss = unknown(ranks, cls.tabs)
  return url, miss > 0 and ("有 %d 個天賦不在插件的資料裡，網址可能少了它們：請更新插件。"):format(miss) or nil
end

-- ---------------------------------------------------------------------------- 分頁
local page = {}

local function status(msg, color)
  if page.status then page.status:SetText((color or "") .. (msg or "") .. (color and "|r" or "")) end
end
T.Status = status

local function remember(plan, ok, msg)
  local h = ns.db.history
  table.insert(h, 1, { t = time(), kind = plan.kind, class = plan.class, ok = ok, points = plan.total, msg = msg })
  while #h > 20 do table.remove(h) end
end

function T.Check(text)
  local code, err = T.Parse(text)
  if not code then return status(err, "|cffff6060") end
  local plan, why = T.Plan(code)
  if not plan then return status(why, "|cffff6060") end
  local title, lines = T.Describe(plan)
  if plan.changes == 0 then return status("已經和代碼一樣，不用改。", "|cff60ff60") end
  status("請看確認視窗。")
  ns.UI.Confirm(title, lines, "套用", function()
    status("套用中…")
    T.Apply(plan, function(ok, msg)
      remember(plan, ok, msg)
      status(msg, ok and "|cff60ff60" or "|cffff6060")
      ns.Print(msg)
    end)
  end)
end

local function build(p)
  local tip = ns.UI.Text(p, "GameFontHighlightSmall",
    "在阿莫比網站的天賦模擬器（wowamobi.com/talents）或傳承樹（/legacy）配好，按「複製到小幫手」，在下面按 Ctrl+V 貼上。也可以直接貼網址。", 430)
  tip:SetPoint("TOPLEFT", 0, 0)
  page.input = ns.UI.Edit(p, 330)
  page.input:SetPoint("TOPLEFT", 6, -48)
  page.input:SetScript("OnEnterPressed", function(self) self:ClearFocus(); ns.Try("talent-check", T.Check, self:GetText()) end)
  local go = ns.UI.Button(p, "檢查並套用", 96, 24, function() T.Check(page.input:GetText()) end)
  go:SetPoint("LEFT", page.input, "RIGHT", 6, 0)
  page.status = ns.UI.Text(p, "GameFontHighlightSmall", "", 430)
  page.status:SetPoint("TOPLEFT", 0, -80)
  local note = ns.UI.Text(p, "GameFontDisableSmall",
    "套用前會跳確認視窗，列出會點哪些、要花幾點；有要降級的天賦會先重置整棵（免費）。只在戰鬥外能用。", 430)
  note:SetPoint("TOPLEFT", 0, -124)

  local h2 = ns.UI.Text(p, "GameFontNormal", "把目前的配點變成網站網址")
  h2:SetPoint("TOPLEFT", 0, -172)
  page.out = ns.UI.CopyBox(p, 420)
  page.out:SetPoint("TOPLEFT", 6, -228)
  local function export(kind)
    local url, msg = T.ExportURL(kind)
    if not url then return status(msg, "|cffff6060") end
    page.out:SetURL(url)
    status(msg or "按 Ctrl+C 複製網址，貼到瀏覽器就能在網站上看、分享給朋友。", msg and "|cffffd100" or nil)
  end
  local b1 = ns.UI.Button(p, "職業天賦網址", 120, 24, function() export("T") end)
  b1:SetPoint("TOPLEFT", 0, -194)
  local b2 = ns.UI.Button(p, "傳承樹網址", 120, 24, function() export("L") end)
  b2:SetPoint("LEFT", b1, "RIGHT", 8, 0)
end

ns.UI.AddTab("talent", "天賦", build)
