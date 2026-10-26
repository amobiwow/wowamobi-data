-- 阿莫比小幫手：戰鬥輔助（目標距離、戰鬥中 DPS、冷卻倒數數字、目標血量）
--
-- 都只「顯示」，不替玩家做任何動作；設定在「戰鬥畫面」分頁，可以各自開關。
-- 永恆的戰鬥限制下，血量、冷卻是秘密值：插件不能比較、計算，但可以交給遊戲自己的顯示函式。所以：
--   * 目標距離：畫面中間偏下（角色腳下附近）一小塊文字，可以解鎖拖動（參考 RangeDisplay 的作法）。
--     遊戲不給到敵人的確切距離，所以用射程不同的技能和物品一起問「在不在射程內」，夾出「約 18～20 碼」：
--     自己會的職業技能（C_Spell.IsSpellInRange，射程用 C_Spell.GetSpellInfo 的 maxRange；最小射程的技能例如衝鋒不用），
--     加上一組固定射程的物品（C_Item.IsItemInRange，5／8／10／15／20／25／30／35／40 碼…，玩家不用有這些物品）。
--     物品只在戰鬥外用（正式版在戰鬥中對敵人會被擋），戰鬥中只用技能，區間變粗。/amobi range 印出每個射程的回答。
--     回答是秘密值或讀不到時，只寫「無法判斷」，不假裝有數字。
--   * 冷卻倒數數字：打開遊戲內建的設定 countdownForCooldowns（暴雪的動作條按鈕自己顯示數字），
--     插件只在戰鬥外替動作條按鈕的冷卻元件換大一點的字、設定數字格式器（C_StringUtil.CreateNumericRuleFormatter）：
--     剩幾秒用哪個顏色由遊戲照門檻自己算（3 秒內紅色帶小數、10 秒內黃色、1 分鐘內白色、更久灰色），Lua 不碰冷卻時間。
--     冷卻元件的 SetCooldown 類函式是受保護的，插件完全不呼叫。
--   * 戰鬥中的 DPS／HPS：距離下面另一小塊（一樣可以拖），暴雪傷害統計「這一場」自己那一列的每秒數值直接交給
--     SetFormattedText（秘密值不算、不比、不排名）；讀不到就只顯示戰鬥時間。打完由「打完檢討」列完整排名。
--     「開／關暴雪傷害統計」按鈕只改遊戲設定 damageMeterEnabled（戰鬥中不改）。
--   * 目標血量：用遊戲內建的「狀態文字」（遊戲設定 statusText、statusTextDisplay：數字／百分比／兩者），
--     由暴雪自己的目標頭像血條顯示（Blizzard_TextStatusBar），插件只改設定，完全不碰血量的值；
--     目標死亡時暴雪的頭像自己顯示「死亡」。關掉時把設定改回玩家原本的。
--   * 名條血量百分比：插件自己的小字掛在名條下面。UnitHealthPercent（加上 CurveConstants.ScaleTo100）直接交給
--     FontString:SetFormattedText；低血量變色用顏色曲線（C_CurveUtil.CreateColorCurve）交給 UnitHealthPercent 算。
--     只用 C_NamePlate.GetNamePlateForUnit(unit, false)（副本裡的名條是 forbidden，拿不到就不加）。
--   * 相容：偵測到其他頭像插件（ElvUI、C-Perl、Classic UI Forever、EllesmereUI、Better Blizz Frames…）就不改頭像的設定，
--     偵測到名條插件（Plater、Platynator、ElvUI…）就不加名條文字，分頁上寫出偵測到哪個。
-- 「交給遊戲顯示」的步驟都用 pcall 包起來，萬一值的形狀和文件不同，就不顯示那一項、記一筆（db.diag.skips），不會跳錯誤。

local _, ns = ...
local A = {}
ns.Assist = A

local TICK = 0.2   -- 秒：目標距離多久更新一次
local BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
               "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
local SIZES = { { 16, "一般" }, { 20, "大" }, { 24, "特大" } }
local HEALTH_MODES = { { "numeric", "數字", "NUMERIC" }, { "percent", "百分比", "PERCENT" }, { "both", "兩者", "BOTH" },
                       { "off", "關閉" } }
local RANGE_POS = { 0, -110 }   -- 距離文字的預設位置：畫面正中央往下（角色腳下附近）
local DPS_POS = { 0, -140 }     -- DPS 的預設位置：距離下面
local THREAT_POS = { 0, -170 }  -- 我的仇恨（1.4.0）：DPS 下面

-- 其他插件（資料夾名稱；後面有 * 的是開頭相同就算）
local UNITFRAME_ADDONS = {
  { "ElvUI", "ElvUI" }, { "Perl_*", "C-Perl Unit Frames" }, { "CPerl*", "C-Perl Unit Frames" },
  { "ClassicUI*", "Classic UI Forever" }, { "EllesmereUI*", "EllesmereUI" }, { "BetterBlizzFrames", "Better Blizz Frames" },
  { "ShadowedUnitFrames", "Shadowed Unit Frames" }, { "PitBull4", "PitBull" }, { "UnhaltedUnitFrames", "Unhalted Unit Frames" },
}
local NAMEPLATE_ADDONS = {
  { "Plater", "Plater" }, { "Platynator", "Platynator" }, { "ElvUI", "ElvUI" }, { "EllesmereUI*", "EllesmereUI" },
  { "Kui_Nameplates*", "KuiNameplates" }, { "TidyPlates*", "Threat Plates" }, { "NeatPlates", "NeatPlates" },
  { "BetterBlizzPlates", "Better Blizz Plates" },
}

local ranges, formatter, colorCurve = nil, nil, nil
local styled = {}            -- [冷卻元件] = { font, size, flags }（原本的字，關掉時換回去）
local plates = {}            -- [名條單位] = 我們的文字框
local pendingStyle, pendingHealth = false, false   -- 戰鬥中改了設定：脫離戰鬥再套用
local conflict = nil         -- { frames = {名稱…}, plates = {名稱…} }

local function S() return ns.db.settings end

local function skip()
  local d = ns.db and ns.db.diag
  if d then d.skips = (d.skips or 0) + 1 end
end

-- 只用來包「把值交給遊戲顯示」的步驟：值的形狀和文件不同時不顯示，不跳錯誤
local function safe(fn, ...)
  local ok = pcall(fn, ...)
  if not ok then skip() end
  return ok
end

local function cvar(name)
  if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
  if GetCVar then return GetCVar(name) end
end
local function setCVar(name, value)
  if C_CVar and C_CVar.SetCVar then return C_CVar.SetCVar(name, value) end
  if SetCVar then return SetCVar(name, value) end
end

-- ---------------------------------------------------------------------------- 其他插件
local function loadedAddons()
  local out = {}
  local n = ns.Call(C_AddOns, "GetNumAddOns") or 0
  for i = 1, n do
    local name = ns.Call(C_AddOns, "GetAddOnInfo", i)
    if type(name) == "string" and ns.Call(C_AddOns, "IsAddOnLoaded", name) then out[#out + 1] = name end
  end
  return out
end

local function match(list, names)
  local found, seen = {}, {}
  for _, entry in ipairs(list) do
    local pat, label = entry[1], entry[2]
    for _, name in ipairs(names) do
      local hit
      if pat:sub(-1) == "*" then hit = name:sub(1, #pat - 1) == pat:sub(1, -2) else hit = name == pat end
      if hit and not seen[label] then
        seen[label] = true
        found[#found + 1] = label
      end
    end
  end
  return found
end

function A.Conflicts()
  if not conflict then
    local names = loadedAddons()
    conflict = { frames = match(UNITFRAME_ADDONS, names), plates = match(NAMEPLATE_ADDONS, names) }
  end
  return conflict
end

-- ---------------------------------------------------------------------------- 目標距離
-- 會的技能裡，有射程、沒有最小射程的：{ spell, range（近戰算 5）, melee, harm, help }，照射程排
local function buildRanges()
  ranges = {}
  local token = ns.PlayerClass()
  local cls = ns.CombatData.classes[token]
  local seen = {}
  for _, id in ipairs(cls and cls.spells or {}) do
    local known = ns.Call(C_SpellBook, "IsSpellKnown", id, (Enum.SpellBookSpellBank or {}).Player or 0)
    local si = known and ns.Call(C_Spell, "GetSpellInfo", id)
    if type(si) == "table" and not ns.Secret(si.maxRange) and not ns.Secret(si.minRange) then
      local maxR, minR = si.maxRange or 0, si.minRange or 0
      local harm = ns.Call(C_Spell, "IsSpellHarmful", id) == true
      local help = ns.Call(C_Spell, "IsSpellHelpful", id) == true
      local key = maxR .. (harm and "h" or "") .. (help and "f" or "")
      if minR == 0 and (harm or help) and not seen[key] then
        seen[key] = true
        ranges[#ranges + 1] = { spell = id, range = math.max(maxR, 5), melee = maxR <= 5, harm = harm, help = help }
      end
    end
  end
  table.sort(ranges, function(a, b) return a.range < b.range end)
end
A.BuildRanges = buildRanges

-- 固定射程的物品（永恆封測客戶端 1.60.1.70450 查的：物品的使用技能 ItemEffect → SpellMisc.RangeIndex → SpellRange.RangeMax，
-- 最小射程 0；harm 是技能目標為敵人的、help 是目標為友方的）。玩家不用有這些物品，C_Item.IsItemInRange 只看射程。
-- 每個射程放幾個備用，用第一個回答得出來的。重新查：tools/find_range_items.py。
local RANGE_ITEMS = {
  harm = {
    { 5, { 9283, 11914, 3912 } }, { 8, { 260829 } }, { 10, { 9606, 10699, 9618 } }, { 15, { 275347 } },
    { 20, { 1191, 4388, 13892 } }, { 25, { 274414 } }, { 30, { 835, 1434 } }, { 35, { 1399, 1402 } },
    { 40, { 4945, 8348 } },
  },
  help = {
    { 5, { 8149, 1970, 16991 } }, { 10, { 11590, 21267 } }, { 15, { 1251, 2581 } }, { 20, { 21519, 17757 } },
    { 25, { 13289 } }, { 30, { 954, 955 } }, { 35, { 18904 } }, { 40, { 5323, 11562, 5205 } }, { 45, { 221316 } },
    { 50, { 274093 } }, { 100, { 23715 } },
  },
}
A.RANGE_ITEMS = RANGE_ITEMS

-- 物品測距只在戰鬥外、沒有插件限制時用（正式版的物品測距在戰鬥中對敵人會被擋，戰鬥中就只用技能，區間變粗）
local function itemsAllowed()
  return C_Item ~= nil and C_Item.IsItemInRange ~= nil and not InCombatLockdown() and not ns.Restricted()
end

local function state(ok, v)
  if not ok then return "error" end
  if ns.Secret(v) then return "secret" end
  if v == true then return "in" end
  if v == false then return "out" end
  return "invalid"
end

-- 問一輪：回傳 { { range, src = "spell"／"item", id, melee, result = in／out／invalid／secret／error／blocked } … }, 是不是敵人, 有沒有用物品
function A.Probe(unit)
  if not ranges then buildRanges() end
  local enemy = UnitCanAttack("player", unit) == true
  local useItems = itemsAllowed()
  local checks = {}
  for _, r in ipairs(ranges) do
    if (enemy and r.harm) or (not enemy and r.help) then
      local ok, v = pcall(C_Spell.IsSpellInRange, r.spell, unit)
      checks[#checks + 1] = { range = r.range, src = "spell", id = r.spell, melee = r.melee, result = state(ok, v) }
    end
  end
  for _, e in ipairs(RANGE_ITEMS[enemy and "harm" or "help"]) do
    local c = { range = e[1], src = "item", id = e[2][1], result = "blocked" }
    if useItems then
      c.result = "invalid"
      for _, id in ipairs(e[2]) do
        local st = state(pcall(C_Item.IsItemInRange, id, unit))
        if st == "in" or st == "out" then
          c.result, c.id = st, id
          break
        elseif st == "secret" then
          c.result = "secret"
        end
      end
    end
    checks[#checks + 1] = c
  end
  return checks, enemy, useItems
end

-- 回傳 文字, 顏色（green 近戰內、yellow 你的技能射程內、red 你的技能打不到、gray 無法判斷）；沒目標、目標死了、問不出來回傳 nil
-- 遊戲不給到敵人的確切距離：用射程不同的技能和物品一起問「在不在射程內」，最近的「在」和最遠的「不在」夾出「約 18～20 碼」。
-- maxOnly：只寫最大距離（「約 20 碼內」）
function A.Range(unit, maxOnly)
  unit = unit or "target"
  if not UnitExists(unit) or UnitIsDeadOrGhost(unit) then return nil end
  local checks = A.Probe(unit)
  local inside, melee, valid, secret, reach = nil, false, 0, false, 0
  for _, c in ipairs(checks) do
    if c.result == "in" or c.result == "out" then
      valid = valid + 1
      if c.src == "spell" and c.range > reach then reach = c.range end
    end
    if c.result == "in" then
      if c.melee or c.range <= 5 then melee = true end
      if not inside or c.range < inside then inside = c.range end
    elseif c.result == "secret" then
      secret = true
    end
  end
  -- 最遠的「不在」：只算比最近的「在」更近的（視線被擋時遠近的回答可能互相矛盾）
  local outside
  for _, c in ipairs(checks) do
    if c.result == "out" and (not inside or c.range < inside) and (not outside or c.range > outside) then outside = c.range end
  end
  if valid == 0 then
    if secret then return "距離：無法判斷", "gray" end
    return nil
  end
  if melee then return "近戰範圍內", "green" end
  if inside then
    local color = (reach > 0 and inside > reach) and "red" or "yellow"
    if not maxOnly and outside then return ("約 %d～%d 碼"):format(outside, inside), color end
    return ("約 %d 碼內"):format(inside), color
  end
  if not outside or outside <= 5 then return "近戰範圍外", "red" end
  return ("%d 碼外"):format(outside), "red"
end

-- /amobi range：印出這一輪用了哪些射程、各自的回答、物品有沒有被停用
local RESULT = { ["in"] = "在射程內", out = "不在射程內", invalid = "問不出來", secret = "秘密值", error = "出錯",
                 blocked = "戰鬥中不用（會被擋）" }
function A.DiagnoseRange()
  if not UnitExists("target") then return ns.Print("先選一個目標再打 /amobi range。") end
  if UnitIsDeadOrGhost("target") then return ns.Print("目標已經死了，選一個活的再打 /amobi range。") end
  local checks, enemy, useItems = A.Probe("target")
  ns.Print(("距離診斷：目標是%s；戰鬥中 %s；插件限制 %s；物品測距 %s"):format(enemy and "敵人" or "友方",
    InCombatLockdown() and "是" or "否", ns.Restricted() or "沒有",
    useItems and "有用" or "沒用（戰鬥中或有限制時正式版會擋，只用技能）"))
  table.sort(checks, function(a, b) return a.range < b.range end)
  for _, c in ipairs(checks) do
    local name
    if c.src == "spell" then
      name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(c.id)) or ("#" .. c.id)
    else
      name = ns.Call(C_Item, "GetItemNameByID", c.id) or ("物品 #" .. c.id)
    end
    ns.Print(("  %d 碼｜%s %s｜%s"):format(c.range, c.src == "spell" and "技能" or "物品", name, RESULT[c.result] or c.result))
  end
  local text = A.Range("target", S().rangeMaxOnly)
  ns.Print("顯示：" .. (text or "（沒有）"))
end

local COLOR = { green = { 0.4, 1, 0.4 }, yellow = { 1, 0.85, 0.2 }, red = { 1, 0.35, 0.35 }, gray = { 0.7, 0.7, 0.7 } }

-- ---------------------------------------------------------------------------- 可以拖動的小塊（距離、DPS 共用）
-- 位置存成相對畫面正中央；預設鎖定（滑鼠點得穿過去），「解鎖拖動」時兩塊都變亮、沒資料也顯示提示字，可以拖。
local blocks = {}   -- [代號] = 小塊

local function placeBlock(b)
  b:ClearAllPoints()
  local pos = S()[b.posKey] or (type(b.defaultPos) == "function" and b.defaultPos()) or b.defaultPos
  b:SetPoint("CENTER", UIParent, "CENTER", pos[1], pos[2])
end

local function paintBlock(b)
  local unlocked = not S().rangeLocked
  b:EnableMouse(unlocked)
  if b.SetBackdropColor then
    if unlocked then
      b:SetBackdropColor(0.91, 0.80, 0.53, 0.35)
    elseif S().rangeBg then
      b:SetBackdropColor(0, 0, 0, 0.5)
    else
      b:SetBackdropColor(0, 0, 0, 0)
    end
  end
end

-- tick：每幾秒呼叫 update 一次（小塊顯示著才會跑）
local function makeBlock(key, posKey, defaultPos, width, tick, update)
  local b = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  b:SetSize(width, 26)
  b:SetFrameStrata("MEDIUM")
  b:SetClampedToScreen(true)
  b:SetMovable(true)
  b.posKey, b.defaultPos = posKey, defaultPos
  if b.SetBackdrop then b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }) end
  b.text = ns.UI.Text(b, "GameFontNormalLarge", "")
  b.text:SetPoint("CENTER")
  b.text:SetJustifyH("CENTER")
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(self) if not S().rangeLocked then self:StartMoving() end end)
  b:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local ok, x, y = pcall(function()
      local cx, cy = self:GetCenter()
      local ux, uy = UIParent:GetCenter()
      if ns.Secret(cx) or ns.Secret(cy) or ns.Secret(ux) or ns.Secret(uy) then return nil end
      return cx - ux, cy - uy
    end)
    if ok and x and y then S()[posKey] = { math.floor(x + 0.5), math.floor(y + 0.5) } end
    placeBlock(self)
  end)
  b.elapsed = tick
  b:SetScript("OnUpdate", function(self, dt)
    self.elapsed = self.elapsed + dt
    if self.elapsed < tick then return end
    self.elapsed = 0
    ns.Try(key, update)
  end)
  placeBlock(b)
  paintBlock(b)
  b:Hide()
  blocks[key] = b
  return b
end
A.MakeBlock = makeBlock   -- 地圖導航的座標也用同一種小塊（一起解鎖拖動、重設位置）

-- ---------------------------------------------------------------------------- 目標距離的小塊
local rangeFrame

function A.UpdateRange()
  if not rangeFrame then return end
  local text, color = A.Range("target", S().rangeMaxOnly)
  -- 沒有距離可以顯示（目標死了、沒有能用的技能）：先變透明，框留著繼續更新
  rangeFrame:SetAlpha((text or not S().rangeLocked) and 1 or 0)
  rangeFrame.text:SetText(text or "目標距離（拖曳移動）")
  local c = COLOR[color or "gray"]
  rangeFrame.text:SetTextColor(c[1], c[2], c[3])
end

-- 有目標、或解鎖拖動中才顯示
function A.UpdateTarget()
  local s = S()
  local want = s.range and (UnitExists("target") or not s.rangeLocked)
  if not want then
    if rangeFrame then rangeFrame:Hide() end
    return
  end
  if not rangeFrame then
    rangeFrame = makeBlock("range", "rangePos", RANGE_POS, 140, TICK, A.UpdateRange)
    A.rangeFrame = rangeFrame
  end
  rangeFrame:Show()
  A.UpdateRange()
end

-- ---------------------------------------------------------------------------- 戰鬥中的 DPS／HPS
-- 暴雪傷害統計「這一場」（C_DamageMeter.GetCombatSessionFromType(Current, 傷害或治療)）裡自己那一列（isLocalPlayer 永遠不是秘密值）
-- 的 amountPerSecond：戰鬥中是秘密值，直接交給 SetFormattedText 顯示，不比較、不計算、不排名。
-- 戰鬥時間用 C_DamageMeter.GetSessionDurationSeconds（文件沒有秘密值）；讀不到就用自己記的開打時間。
-- 讀不到自己那一列（傷害統計關著、還沒打到東西、資料形狀不同）就只顯示戰鬥時間。打完就收起來，由「打完檢討」顯示完整排名。
local dpsFrame, fightStart, dpsHideAt = nil, nil, nil
local DPS_TICK, DPS_LINGER = 0.5, 8

-- 在一場的資料裡找自己那一列；回傳每秒數值（可能是秘密值）, 原因代號
local function rowIn(sess)
  if sess == nil then return nil, "nosession" end
  if ns.Secret(sess) then return nil, "secretsession" end
  local sources = sess.combatSources
  if sources == nil then return nil, "nosources" end
  if ns.Secret(sources) then return nil, "secretsources" end
  for _, src in ipairs(sources) do
    if src.isLocalPlayer == true then return src.amountPerSecond, "ok" end
  end
  return nil, "norow"
end

-- 自己這一場的每秒數值：先問「目前這一場」（Current），沒有自己那一列就問最新的一場（GetAvailableCombatSessions 裡編號最大的）
local function myRate(kind)
  local api = C_DamageMeter
  if not (api and api.GetCombatSessionFromType) then return nil, "noapi" end
  local value, why = nil, "error"
  safe(function()
    value, why = rowIn(api.GetCombatSessionFromType((Enum.DamageMeterSessionType or {}).Current or 1, kind))
    if value ~= nil or not api.GetAvailableCombatSessions then return end
    local list = api.GetAvailableCombatSessions()
    if list == nil or ns.Secret(list) then return end
    local best
    for _, info in ipairs(list) do
      local id = info.sessionID
      if not ns.Secret(id) and (not best or id > best) then best = id end
    end
    if best then
      local v2, w2 = rowIn(api.GetCombatSessionFromID(best, kind))
      if v2 ~= nil then value, why = v2, w2 end
    end
  end)
  return value, why
end
A.MyRate = myRate

-- /amobi dps：把讀 DPS 的每一步印在聊天框（給實測回報用；秘密值只寫「秘密值」，不印出數字）
local WHY = { ok = "有", nosession = "沒有這一場", secretsession = "整場是秘密值（插件讀不到裡面）", nosources = "這一場沒有來源清單",
              secretsources = "來源清單是秘密值", norow = "清單裡沒有自己那一列", noapi = "沒有傷害統計的函式", error = "讀的時候出錯" }
function A.DiagnoseDps()
  local api = C_DamageMeter
  local function yes(v) return v and "是" or "否" end
  local function show(v)
    if v == nil then return "沒有" end
    if ns.Secret(v) then return "秘密值" end
    return tostring(v)
  end
  local hps = S().dpsKind == "hps"
  local DMT = Enum and Enum.DamageMeterType or {}
  local kind = hps and (DMT.HealingDone or 2) or (DMT.DamageDone or 0)
  ns.Print(("DPS 診斷（%s）：戰鬥中 %s，插件限制 %s，DPS 開關 %s"):format(hps and "HPS" or "DPS", yes(InCombatLockdown()),
    ns.Restricted() or "沒有", yes(S().dps)))
  if not api then return ns.Print("這個版本沒有 C_DamageMeter（暴雪傷害統計）。") end
  local ok, avail, reason = pcall(api.IsDamageMeterAvailable)
  ns.Print(("IsDamageMeterAvailable：%s%s；damageMeterEnabled＝%s"):format(ok and show(avail) or "出錯",
    (ok and type(reason) == "string" and reason ~= "") and ("（" .. reason .. "）") or "", show(cvar("damageMeterEnabled"))))
  local okL, list = pcall(api.GetAvailableCombatSessions)
  local n, latest = 0, nil
  if okL and type(list) == "table" and not ns.Secret(list) then
    for _, info in ipairs(list) do
      n = n + 1
      if not ns.Secret(info.sessionID) and (not latest or info.sessionID > latest) then latest = info.sessionID end
    end
  end
  local okD, dur = pcall(api.GetSessionDurationSeconds, (Enum.DamageMeterSessionType or {}).Current or 1)
  ns.Print(("場次：%d 場（最新 %s）；這一場的時間：%s 秒"):format(n, show(latest), okD and show(dur) or "出錯"))
  for _, t in ipairs({ { "Current", "這一場" }, { "Overall", "全部" } }) do
    local okS, sess = pcall(api.GetCombatSessionFromType, (Enum.DamageMeterSessionType or {})[t[1]] or (t[1] == "Current" and 1 or 0), kind)
    if not okS then
      ns.Print(t[2] .. "（" .. t[1] .. "）：讀的時候出錯")
    else
      local value, why = nil, "error"
      pcall(function() value, why = rowIn(sess) end)
      ns.Print(("%s（%s）：%s%s"):format(t[2], t[1], WHY[why] or why,
        why == "ok" and ("，每秒數值" .. (ns.Secret(value) and "是秘密值（只能顯示）" or ("＝" .. show(value)))) or ""))
    end
  end
  local value, why = myRate(kind)
  ns.Print(("小幫手實際用到的：%s%s"):format(WHY[why] or why, value ~= nil and (ns.Secret(value) and "（秘密值，直接交給遊戲顯示）" or "") or ""))
end

-- DPS 要用暴雪傷害統計的資料：DPS 開著、玩家沒有自己關掉傷害統計時，戰鬥外自動打開（damageMeterEnabled）
function A.EnsureMeter(quiet)
  local s = S()
  if not s.dps or s.meterOff or ns.Restricted() then return false end
  local v = cvar("damageMeterEnabled")
  if v == nil or tostring(v) == "1" then return false end
  setCVar("damageMeterEnabled", "1")
  if not quiet then ns.Print("已打開暴雪的傷害統計：戰鬥中的 DPS 要用它的資料（不想看到視窗的話，可以在編輯模式改成只在戰鬥中顯示）。") end
  return true
end

local function fightClock()
  local d = ns.Call(C_DamageMeter, "GetSessionDurationSeconds", (Enum.DamageMeterSessionType or {}).Current or 1)
  if type(d) ~= "number" or ns.Secret(d) then d = fightStart and (GetTime() - fightStart) or 0 end
  d = math.floor(d)
  return ("%d:%02d"):format(math.floor(d / 60), d % 60)
end

function A.UpdateDps()
  if not dpsFrame then return end
  if dpsHideAt and GetTime() >= dpsHideAt then
    dpsHideAt = nil
    if S().rangeLocked then dpsFrame:Hide() end
    return
  end
  if not fightStart and not dpsHideAt then
    dpsFrame.text:SetText(S().rangeLocked and "" or "DPS（拖曳移動）")
    return
  end
  local hps = S().dpsKind == "hps"
  local DMT = Enum and Enum.DamageMeterType or {}
  local value = myRate(hps and (DMT.HealingDone or 2) or (DMT.DamageDone or 0))
  local label, clock = hps and "HPS" or "DPS", fightClock()
  dpsFrame.text:SetTextColor(1, 0.82, 0.2)
  if value ~= nil and safe(dpsFrame.text.SetFormattedText, dpsFrame.text, "%s %.0f  |cffbbbbbb%s|r", label, value, clock) then
    return
  end
  -- 讀不到這一場的數字：只顯示戰鬥時間；傷害統計關著就提醒
  local off = tostring(cvar("damageMeterEnabled") or "1") ~= "1"
  dpsFrame.text:SetText("戰鬥 " .. clock .. (off and "  |cffff9050傷害統計沒開|r" or ""))
end

local function showDps()
  local s = S()
  local want = s.dps and (fightStart or dpsHideAt or not s.rangeLocked)
  if not want then
    if dpsFrame then dpsFrame:Hide() end
    return
  end
  if not dpsFrame then
    dpsFrame = makeBlock("dps", "dpsPos", DPS_POS, 170, DPS_TICK, A.UpdateDps)
    A.dpsFrame = dpsFrame
  end
  dpsFrame:Show()
  A.UpdateDps()
end
A.ShowDps = showDps

-- ---------------------------------------------------------------------------- 我的仇恨（「首領仇恨」分頁的開關，1.4.0）
-- UnitDetailedThreatSituation("player", "target")：坦怪中、狀態、仇恨百分比（scaledPercentage）。
-- 遊戲限制仇恨數值時（SecretWhenUnitThreatValuesRestricted，例如副本首領戰）百分比是秘密值：直接交給 SetFormattedText 顯示，
-- 不比較、不計算；狀態也是秘密值時就不上色。看不出全隊誰最高，只顯示自己的。組隊時、戰鬥中、目標是敵人才顯示。
local threatFrame
local THREAT_TICK = 0.3

function A.UpdateThreat()
  if not threatFrame then return end
  local t = threatFrame.text
  if not (UnitExists("target") and UnitCanAttack("player", "target")) then
    t:SetText(S().rangeLocked and "" or "我的仇恨（拖曳移動）")
    t:SetTextColor(1, 0.82, 0.2)
    return
  end
  local ok, tanking, status, pct = pcall(UnitDetailedThreatSituation, "player", "target")
  if not ok then return end
  if ns.Secret(pct) then
    t:SetTextColor(1, 1, 1)
    safe(t.SetFormattedText, t, "仇恨 %.0f%%", pct)
    return
  end
  if pct == nil then
    t:SetText("仇恨 0%")
    t:SetTextColor(0.7, 0.7, 0.7)
    return
  end
  local r, g, b = 1, 1, 1
  if not ns.Secret(status) and status ~= nil and GetThreatStatusColor then
    local okC, cr, cg, cb = pcall(GetThreatStatusColor, status)
    if okC and type(cr) == "number" then r, g, b = cr, cg, cb end
  end
  t:SetTextColor(r, g, b)
  local tank = (not ns.Secret(tanking)) and tanking == true
  t:SetFormattedText("仇恨 %.0f%%%s", pct, tank and "  坦怪中" or "")
end

local function showThreat()
  local s = S()
  local enemy = UnitExists("target") and UnitCanAttack("player", "target")
  local want = s.threat and ((enemy and InCombatLockdown() and (s.threatSolo or IsInGroup())) or not s.rangeLocked)
  if not want then
    if threatFrame then threatFrame:Hide() end
    return
  end
  if not threatFrame then
    threatFrame = makeBlock("threat", "threatPos", THREAT_POS, 170, THREAT_TICK, A.UpdateThreat)
    A.threatFrame = threatFrame
  end
  threatFrame:Show()
  A.UpdateThreat()
end
A.ShowThreat = showThreat

-- ---------------------------------------------------------------------------- 小塊的設定
function A.SetRangeLocked(locked)
  S().rangeLocked = locked
  for _, b in pairs(blocks) do paintBlock(b) end
  A.UpdateTarget()
  showDps()
  showThreat()
end

function A.ResetRangePosition()
  S().rangePos, S().dpsPos, S().threatPos, S().coordsPos = nil, nil, nil, nil
  for _, b in pairs(blocks) do placeBlock(b) end
end

function A.RefreshRangeStyle()
  for _, b in pairs(blocks) do paintBlock(b) end
  A.UpdateTarget()
  showDps()
end

-- 打開或關上暴雪內建的傷害統計（遊戲設定 damageMeterEnabled；戰鬥中不改）
function A.ToggleMeter()
  local why = ns.Restricted()
  if why then return false, why .. "不能改設定；傷害統計開著的話，打完可以直接看。" end
  local on = tostring(cvar("damageMeterEnabled") or "0") == "1"
  setCVar("damageMeterEnabled", on and "0" or "1")
  S().meterOff = on or nil          -- 玩家自己關掉：之後不再自動打開
  return true, on and "已關上暴雪的傷害統計（戰鬥中的 DPS 也會讀不到）。" or "已打開暴雪的傷害統計（在編輯模式可以移動、改顯示方式）。"
end


-- ---------------------------------------------------------------------------- 目標血量（遊戲內建的狀態文字）
local function modeCVar(mode)
  for _, m in ipairs(HEALTH_MODES) do
    if m[1] == mode then return m[3] end
  end
end

-- 照 settings.healthMode 改遊戲設定；回傳 true，或 false, 原因
function A.ApplyHealthMode()
  local s = S()
  local c = A.Conflicts()
  if #c.frames > 0 then return false, "偵測到 " .. table.concat(c.frames, "、") .. "，不改頭像的設定。" end
  local why = ns.Restricted()
  if why then
    pendingHealth = true
    return false, why .. "，打完會自動套用。"
  end
  pendingHealth = false
  local want = modeCVar(s.healthMode)
  if want then
    if not s.statusWas then
      s.statusWas = { text = cvar("statusText") or "0", display = cvar("statusTextDisplay") or "NONE" }
    end
    setCVar("statusText", "1")
    setCVar("statusTextDisplay", want)
  elseif s.statusWas then      -- 關閉：改回玩家原本的
    setCVar("statusText", s.statusWas.text)
    setCVar("statusTextDisplay", s.statusWas.display)
    s.statusWas = nil
  end
  s.healthApplied = s.healthMode
  return true
end

-- ---------------------------------------------------------------------------- 名條血量百分比
local function curves()
  if colorCurve ~= nil then return colorCurve end
  colorCurve = false
  if C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor then
    safe(function()
      local c = C_CurveUtil.CreateColorCurve()
      if Enum.LuaCurveType and c.SetType then c:SetType(Enum.LuaCurveType.Step) end
      c:AddPoint(0, CreateColor(1, 0.3, 0.3, 1))      -- 不到 20%：紅
      c:AddPoint(0.2, CreateColor(1, 0.82, 0.2, 1))   -- 20%～50%：黃
      c:AddPoint(0.5, CreateColor(1, 1, 1, 1))        -- 一半以上：白
      colorCurve = c
    end)
  end
  return colorCurve
end

-- 把 unit 的血量百分比寫進 fs。值直接交給遊戲顯示，不在 Lua 裡算；死了寫「死亡」
function A.PercentText(fs, unit)
  if not UnitExists(unit) then fs:SetText(""); return end
  if UnitIsDeadOrGhost(unit) then
    fs:SetText("死亡")
    fs:SetTextColor(0.6, 0.6, 0.6)
    return
  end
  local scale = CurveConstants and CurveConstants.ScaleTo100
  local ok = safe(function() fs:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, scale)) end)
  if not ok then fs:SetText("") return end
  local curve = curves()
  if curve then
    safe(function()
      local c = UnitHealthPercent(unit, true, curve)
      fs:SetTextColor(c:GetRGB())
    end)
  end
end

local platePool = {}

local function platesOn()
  return S().plateHealth and #A.Conflicts().plates == 0
end

local function plateFor(unit)
  local plate = ns.Call(C_NamePlate, "GetNamePlateForUnit", unit, false)
  if not plate then return nil end
  local okF, forbidden = pcall(plate.IsForbidden, plate)
  if not okF or forbidden then return nil end
  return plate
end

local function plateAdded(unit)
  if not platesOn() or type(unit) ~= "string" then return end
  local plate = plateFor(unit)
  if not plate then return end
  local f = plates[unit] or table.remove(platePool)
  if not f then
    f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(60, 12)
    f.text = ns.UI.Text(f, "GameFontHighlightSmall", "")
    f.text:SetPoint("CENTER")
    f.text:SetJustifyH("CENTER")
  end
  f:SetParent(plate)
  f:ClearAllPoints()
  f:SetPoint("TOP", plate, "BOTTOM", 0, 2)
  f:Show()
  plates[unit] = f
  A.PercentText(f.text, unit)
end

local function plateRemoved(unit)
  local f = plates[unit]
  if not f then return end
  plates[unit] = nil
  f:Hide()
  f:ClearAllPoints()
  f:SetParent(UIParent)
  table.insert(platePool, f)
end

local function refreshPlates()
  for unit in pairs(plates) do plateRemoved(unit) end
  if not platesOn() then return end
  for i = 1, 40 do
    local unit = "nameplate" .. i
    if UnitExists(unit) then plateAdded(unit) end
  end
end

-- ---------------------------------------------------------------------------- 冷卻倒數數字
local function makeFormatter()
  if formatter ~= nil then return formatter end
  formatter = false
  if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return formatter end
  safe(function()
    local up = (Enum.NumericRuleFormatRounding or {}).Up or 1
    local f = C_StringUtil.CreateNumericRuleFormatter()
    f:SetBreakpoints({
      { threshold = 0, step = 0.1, rounding = up, format = "|cffff4040%.1f|r" },             -- 3 秒內：紅，帶小數
      { threshold = 3, step = 1, rounding = up, format = "|cffffd100%d|r" },                 -- 3～10 秒：黃
      { threshold = 10, step = 1, rounding = up, format = "|cffffffff%d|r" },                -- 10 秒～1 分：白
      { threshold = 60, format = "|cffbbbbbb%d分|r", components = { { div = 60, step = 1, rounding = up } } },
      { threshold = 3600, format = "|cff999999%d時|r", components = { { div = 3600, step = 1, rounding = up } } },
    })
    formatter = f
  end)
  return formatter
end

local function eachCooldown(fn)
  for _, prefix in ipairs(BARS) do
    for i = 1, 12 do
      local b = _G[prefix .. i]
      local cd = b and b.cooldown
      if cd then fn(cd) end
    end
  end
end

-- 戰鬥外才做；回傳 true，或 false, 原因
function A.StyleCooldowns()
  local why = ns.Restricted()
  if why then
    pendingStyle = true
    return false, why .. "，打完會自動套用。"
  end
  pendingStyle = false
  local s = S()
  if s.cdText then
    if cvar("countdownForCooldowns") ~= nil and tostring(cvar("countdownForCooldowns")) ~= "1" then
      if s.cdWasOff == nil then s.cdWasOff = true end
      setCVar("countdownForCooldowns", "1")
    end
    local fmt = makeFormatter()
    local size = s.cdSize or 20
    local n = 0
    eachCooldown(function(cd)
      local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
      if fs then
        if not styled[cd] then
          local font, h, flags = fs:GetFont()
          styled[cd] = { font = font, size = h, flags = flags }
        end
        local font = styled[cd].font or STANDARD_TEXT_FONT
        if font then safe(fs.SetFont, fs, font, size, "OUTLINE") end
      end
      if fmt and cd.SetCountdownFormatter then safe(cd.SetCountdownFormatter, cd, fmt) end
      n = n + 1
    end)
    return true, n
  end
  -- 關掉：換回原本的字和格式，遊戲設定改回原本的
  for cd, orig in pairs(styled) do
    local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
    if fs and orig.font then safe(fs.SetFont, fs, orig.font, orig.size, orig.flags) end
    if cd.SetCountdownFormatter then safe(cd.SetCountdownFormatter, cd, nil) end
  end
  styled = {}
  if s.cdWasOff then
    setCVar("countdownForCooldowns", "0")
    s.cdWasOff = nil
  end
  return true, 0
end

-- ---------------------------------------------------------------------------- 事件
function A.Init()
  local s = S()
  if s.health == false and not s.healthApplied then s.healthMode = "off" end   -- 1.1.0 的開關
  s.health, s.infoPos = nil, nil                                                -- 1.1.0 自己畫的血量條已經拿掉
  for _, kind in pairs(RANGE_ITEMS) do               -- 測距物品的資料先向伺服器要（沒載入的物品問不出射程）
    for _, e in ipairs(kind) do
      for _, id in ipairs(e[2]) do ns.Call(C_Item, "RequestLoadItemDataByID", id) end
    end
  end
  ns.On("PLAYER_ENTERING_WORLD", function()
    ranges = nil
    C_Timer.After(2, function()
      ns.Try("assist-meter", A.EnsureMeter)
      ns.Try("assist-style", A.StyleCooldowns)
      if S().healthApplied ~= S().healthMode then ns.Try("assist-health", A.ApplyHealthMode) end
    end)
    ns.Try("assist-target", A.UpdateTarget)
  end)
  ns.On("PLAYER_TARGET_CHANGED", function() A.UpdateTarget(); showThreat() end)
  ns.On("GROUP_ROSTER_UPDATE", function() showThreat() end)
  ns.On("UNIT_HEALTH", function(unit)
    local f = plates[unit]
    if f then A.PercentText(f.text, unit) end
  end)
  ns.On("NAME_PLATE_UNIT_ADDED", plateAdded)
  ns.On("NAME_PLATE_UNIT_REMOVED", plateRemoved)
  ns.On("SPELLS_CHANGED", function() ranges = nil end)
  ns.On("PLAYER_LEVEL_UP", function() ranges = nil end)
  ns.On("PLAYER_REGEN_DISABLED", function()
    fightStart, dpsHideAt = GetTime(), nil
    showDps()
    showThreat()
  end)
  ns.On("PLAYER_REGEN_ENABLED", function()
    C_Timer.After(0.1, function() ns.Try("assist-threat", showThreat) end)   -- 戰鬥鎖定解除後才判斷（事件當下 InCombatLockdown 可能還是 true）
    if fightStart then
      fightStart, dpsHideAt = nil, GetTime() + DPS_LINGER   -- 打完留 8 秒最後的數字（已經不是秘密值），之後交給「打完檢討」
      A.UpdateDps()
    end
    if pendingStyle then C_Timer.After(0.5, function() ns.Try("assist-style", A.StyleCooldowns) end) end
    if pendingHealth then C_Timer.After(0.6, function() ns.Try("assist-health", A.ApplyHealthMode) end) end
  end)
end
ns.Register(A)

-- ---------------------------------------------------------------------------- 「戰鬥畫面」分頁的設定（Combat.lua 建分頁時呼叫）
function A.BuildSettings(p, y)
  local h = ns.UI.Text(p, "GameFontNormal", "戰鬥輔助（只顯示，不會替你做任何動作）")
  h:SetPoint("TOPLEFT", 0, y)
  local status = ns.UI.Text(p, "GameFontHighlightSmall", "", 190)
  local checks = {}
  local function check(label, key, dy, x, after)
    local c = ns.UI.Check(p, label, function() return S()[key] end, function(v)
      S()[key] = v
      if after then after(v) end
      for _, x2 in ipairs(checks) do x2:Refresh() end
    end)
    c:SetPoint("TOPLEFT", x or 0, y + dy)
    checks[#checks + 1] = c
    return c
  end
  local function say(ok, msg) status:SetText((not ok) and (msg or "") or "") end

  -- 目標距離
  check("目標距離（畫面中間偏下）", "range", -22, 0, function() A.UpdateTarget() end)
  local lock = ns.UI.Button(p, "", 80, 20, function() A.SetRangeLocked(not S().rangeLocked); p.RefreshAssist() end)
  lock:SetPoint("TOPLEFT", 250, y - 24)
  local reset = ns.UI.Button(p, "重設位置", 80, 20, function() A.ResetRangePosition() end)
  reset:SetPoint("LEFT", lock, "RIGHT", 6, 0)
  check("只顯示最大距離", "rangeMaxOnly", -46, 20, function() A.UpdateRange() end)
  local rangeTip = ns.UI.Text(p, "GameFontDisableSmall", "遊戲不給確切距離，只能夾出「約○～○碼」", 210)
  rangeTip:SetPoint("TOPLEFT", 250, y - 48)
  check("加底色", "rangeBg", -46, 150, function() A.RefreshRangeStyle() end)

  -- 戰鬥中的 DPS
  check("戰鬥中顯示我的", "dps", -70, 0, function() A.EnsureMeter(); showDps() end)
  local kindButtons = {}
  for i, k in ipairs({ { "dps", "DPS" }, { "hps", "HPS（治療）" } }) do
    local b = ns.UI.Button(p, k[2], i == 1 and 50 or 90, 20, function()
      S().dpsKind = k[1]
      A.UpdateDps()
      p.RefreshAssist()
    end)
    b:SetPoint("TOPLEFT", 130 + (i - 1) * 56, y - 72)
    kindButtons[i] = { b, k[1] }
  end
  local meter = ns.UI.Button(p, "開／關暴雪傷害統計", 140, 20, function()
    local ok, msg = A.ToggleMeter()
    status:SetText(msg or "")
  end)
  meter:SetPoint("TOPLEFT", 20, y - 96)
  local meterTip = ns.UI.Text(p, "GameFontDisableSmall", "DPS 要用暴雪傷害統計的資料，請保持打開；全隊排名也在那裡看", 260)
  meterTip:SetPoint("LEFT", meter, "RIGHT", 6, 0)

  -- 冷卻數字
  check("快捷列冷卻倒數數字（字放大、快好了變紅）", "cdText", -120, 0, function() say(A.StyleCooldowns()) end)
  local sizeLabel = ns.UI.Text(p, "GameFontHighlightSmall", "數字大小：")
  sizeLabel:SetPoint("TOPLEFT", 28, y - 148)
  local sizeButtons = {}
  for i, sz in ipairs(SIZES) do
    local b = ns.UI.Button(p, sz[2], 50, 20, function()
      S().cdSize = sz[1]
      say(A.StyleCooldowns())
      p.RefreshAssist()
    end)
    b:SetPoint("TOPLEFT", 90 + (i - 1) * 54, y - 144)
    sizeButtons[i] = { b, sz[1] }
  end
  status:SetPoint("TOPLEFT", 260, y - 148)

  -- 目標頭像血量
  local hl = ns.UI.Text(p, "GameFontHighlightSmall", "目標頭像血條上的血量（遊戲內建的狀態文字，自己的頭像也會一起顯示）：", 430)
  hl:SetPoint("TOPLEFT", 4, y - 172)
  local modeButtons = {}
  for i, m in ipairs(HEALTH_MODES) do
    local b = ns.UI.Button(p, m[2], 64, 20, function()
      S().healthMode = m[1]
      say(A.ApplyHealthMode())
      p.RefreshAssist()
    end)
    b:SetPoint("TOPLEFT", 20 + (i - 1) * 68, y - 188)
    modeButtons[i] = { b, m[1] }
  end
  check("名條也顯示血量百分比（副本裡的名條遊戲不讓插件加）", "plateHealth", -212, 0, function() refreshPlates() end)
  local note = ns.UI.Text(p, "GameFontDisableSmall", "", 430)
  note:SetPoint("TOPLEFT", 4, y - 238)
  A.settingsNote = note

  function p.RefreshAssist()
    for _, c in ipairs(checks) do c:Refresh() end
    lock:SetText(S().rangeLocked and "解鎖拖動" or "鎖定位置")
    for _, x in ipairs(kindButtons) do x[1]:SetAlpha((S().dpsKind or "dps") == x[2] and 1 or 0.55) end
    for _, x in ipairs(sizeButtons) do x[1]:SetAlpha((S().cdSize or 20) == x[2] and 1 or 0.55) end
    for _, x in ipairs(modeButtons) do x[1]:SetAlpha(S().healthMode == x[2] and 1 or 0.55) end
    local c = A.Conflicts()
    local parts = {}
    if #c.frames > 0 then parts[#parts + 1] = "偵測到頭像插件 " .. table.concat(c.frames, "、") .. "：不改頭像的血量設定。" end
    if #c.plates > 0 then parts[#parts + 1] = "偵測到名條插件 " .. table.concat(c.plates, "、") .. "：不加名條文字。" end
    note:SetText(table.concat(parts, "\n"))
  end
  p.RefreshAssist()
  return y - 262
end
