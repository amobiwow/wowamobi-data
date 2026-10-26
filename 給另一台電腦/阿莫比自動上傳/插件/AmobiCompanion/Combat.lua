-- 阿莫比小幫手：戰鬥畫面一鍵設定
--
-- 永恆內建了暴雪的冷卻監控（CooldownViewer）、首領時間軸和首領警告（EncounterEvents）、傷害統計（DamageMeter），
-- 戰鬥中插件讀不到 buff、冷卻和傷害數字（秘密值），所以這個插件不自己做這些，而是替玩家把暴雪的打開、擺好：
--   1. 打開這幾個功能（遊戲設定 cooldownViewerEnabled、encounterTimelineEnabled、encounterWarningsEnabled、damageMeterEnabled）
--   2. 在編輯模式新增（或更新）一個角色專用的版面「阿莫比 <職業>」：以目前的版面為底，只改這幾個元件的位置和大小，
--      依職業的打法（近戰、遠程、法系、混合）調整；之後玩家可以在編輯模式照常微調、存檔
--   3. 分享：目前的版面轉成暴雪自己的版面代碼（C_EditMode.ConvertLayoutInfoToString），別人可以貼進小幫手或暴雪的「匯入版面」
-- 寫版面的作法照暴雪編輯模式自己新增版面的流程（Blizzard_EditMode：SaveLayouts 傳「預設版面＋自己的版面」，再 OnLayoutAdded）；
-- 只用 C_EditMode 的函式，不碰 EditModeManagerFrame（碰了會污染編輯模式，戰鬥中動作條就可能被擋）。
-- 改之前把每個自己的版面存一份代碼在存檔裡（db.layoutBackup），出問題可以貼回暴雪的「匯入版面」。只在戰鬥外做。
-- 建議放進冷卻監控的技能：Data\Combat.lua（網站職業技能的資料），只列玩家等級學得到的。

local _, ns = ...
local C = {}
ns.Combat = C
local CD = ns.CombatData

local CVARS = {
  { "cooldownViewerEnabled", "冷卻監控" },
  { "encounterTimelineEnabled", "首領時間軸" },
  { "encounterWarningsEnabled", "首領警告" },
  { "damageMeterEnabled", "傷害統計" },
}

-- 各打法的推薦位置（相對畫面下方中間）和大小。大小是編輯模式的格數：圖示 5＝100%、6＝110%、7＝120%；
-- 傷害統計寬高是「比最小多幾」：寬 200＋n、高 120＋n
local STYLE_NAME = { melee = "近戰", ranged = "遠程", caster = "法系", hybrid = "混合（會補也會打）" }
local PROFILE = {
  melee  = { ess = { 0, 285, 7 }, uti = { 0, 236, 5 }, buff = { 0, 352, 6 }, meter = { 60, 60 } },
  ranged = { ess = { 0, 255, 6 }, uti = { 0, 210, 5 }, buff = { 0, 318, 6 }, meter = { 60, 60 } },
  caster = { ess = { 0, 255, 6 }, uti = { 0, 210, 5 }, buff = { 0, 318, 6 }, meter = { 60, 60 } },
  hybrid = { ess = { 0, 255, 6 }, uti = { 0, 210, 5 }, buff = { 0, 318, 6 }, meter = { 60, 120 } },
}

local function E(name) return Enum and Enum[name] or {} end

local function anchor(point, relPoint, x, y)
  return { point = point, relativeTo = "UIParent", relativePoint = relPoint, offsetX = x, offsetY = y }
end

-- 這個職業的推薦：{ system, index, anchor, settings = { [設定] = 值 } }
function C.Recommend(token)
  local cls = CD.classes[token] or {}
  local style = cls.style or "hybrid"
  local p = PROFILE[style]
  local SYS, CV, CVS = E("EditModeSystem"), E("EditModeCooldownViewerSystemIndices"), E("EditModeCooldownViewerSetting")
  local EE, EES, DMS = E("EditModeEncounterEventsSystemIndices"), E("EditModeEncounterEventsSetting"), E("EditModeDamageMeterSetting")
  local list = {
    { SYS.CooldownViewer, CV.Essential, anchor("BOTTOM", "BOTTOM", p.ess[1], p.ess[2]), { [CVS.IconSize] = p.ess[3] } },
    { SYS.CooldownViewer, CV.Utility, anchor("BOTTOM", "BOTTOM", p.uti[1], p.uti[2]), { [CVS.IconSize] = p.uti[3] } },
    { SYS.CooldownViewer, CV.BuffIcon, anchor("BOTTOM", "BOTTOM", p.buff[1], p.buff[2]), { [CVS.IconSize] = p.buff[3] } },
    { SYS.EncounterEvents, EE.Timeline, anchor("BOTTOMRIGHT", "BOTTOM", -330, 300), { [EES.IconSize] = 6 } },
    { SYS.EncounterEvents, EE.CriticalWarnings, anchor("TOP", "TOP", 0, -150), {} },
    { SYS.EncounterEvents, EE.MediumWarnings, anchor("TOP", "TOP", 0, -200), {} },
    { SYS.EncounterEvents, EE.NormalWarnings, anchor("TOP", "TOP", 0, -240), {} },
    { SYS.DamageMeter, nil, anchor("BOTTOMRIGHT", "BOTTOMRIGHT", -40, 240),
      { [DMS.FrameWidth] = p.meter[1], [DMS.FrameHeight] = p.meter[2] } },
  }
  local out = {}
  for _, r in ipairs(list) do
    if r[1] ~= nil and (r[1] == SYS.DamageMeter or r[2] ~= nil) then
      out[#out + 1] = { system = r[1], index = r[2], anchor = r[3], settings = r[4] }
    end
  end
  return out, style
end

local function copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = copy(v) end
  return o
end

local function findSystem(layout, system, index)
  for _, s in ipairs(layout.systems or {}) do
    if s.system == system and (index == nil or s.systemIndex == index) then return s end
  end
end

-- 把推薦套到一個版面（複製出來的表）上
function C.ApplyTo(layout, recs)
  layout.systems = layout.systems or {}
  for _, r in ipairs(recs) do
    local s = findSystem(layout, r.system, r.index)
    if not s then
      s = { system = r.system, systemIndex = r.index, settings = {} }
      table.insert(layout.systems, s)
    end
    s.anchorInfo = copy(r.anchor)
    s.anchorInfo2 = nil
    s.isInDefaultPosition = false
    s.settings = s.settings or {}
    for setting, value in pairs(r.settings) do
      local found = false
      for _, kv in ipairs(s.settings) do
        if kv.setting == setting then kv.value, found = value, true end
      end
      if not found then table.insert(s.settings, { setting = setting, value = value }) end
    end
  end
  return layout
end

-- ---------------------------------------------------------------------------- 編輯模式的版面
local function presets()
  local m = EditModePresetLayoutManager
  if m and m.GetCopyOfPresetLayouts then
    local ok, list = pcall(m.GetCopyOfPresetLayouts, m)
    if ok and type(list) == "table" then return list end
  end
  return nil
end

local function maxPerType()
  return Constants and Constants.EditModeConsts and Constants.EditModeConsts.EditModeMaxLayoutsPerType or 5
end

-- 目前的版面資料：{ presets, saved, active }；讀不到回傳 nil, 原因
local function current()
  if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts) then return nil, "這個版本沒有編輯模式的版面功能。" end
  local info = ns.Call(C_EditMode, "GetLayouts")
  local pre = presets()
  if type(info) ~= "table" or type(info.layouts) ~= "table" or not pre then return nil, "讀不到編輯模式的版面，請 /reload 後再試。" end
  return { presets = pre, saved = info.layouts, active = info.activeLayout or 1 }
end

local function layoutAt(cur, index)
  if index <= #cur.presets then return cur.presets[index] end
  return cur.saved[index - #cur.presets]
end

function C.ActiveName()
  local cur = current()
  if not cur then return nil end
  local l = layoutAt(cur, cur.active)
  return l and l.layoutName
end

local function backup(cur)
  local list = {}
  for _, l in ipairs(cur.saved) do
    local s = ns.Call(C_EditMode, "ConvertLayoutInfoToString", l)
    if s then list[#list + 1] = { name = l.layoutName, type = l.layoutType, code = s } end
  end
  ns.db.layoutBackup = { t = time(), active = cur.active, activeName = (layoutAt(cur, cur.active) or {}).layoutName, layouts = list }
end

-- 新增或更新一個角色專用的版面，並切換過去。照編輯模式自己的 MakeNewLayout：存「預設＋自己的」，再 OnLayoutAdded
local function saveLayout(cur, layout, name)
  local Character = (Enum.EditModeLayoutType or {}).Character or 2
  local Account = (Enum.EditModeLayoutType or {}).Account or 1
  layout.layoutName, layout.layoutType = name, Character
  local idx
  for i, l in ipairs(cur.saved) do
    if l.layoutName == name and l.layoutType == Character then idx = i end
  end
  local added = false
  if idx then
    cur.saved[idx] = layout
  else
    local mine = 0
    for _, l in ipairs(cur.saved) do if l.layoutType == Character then mine = mine + 1 end end
    if mine >= maxPerType() then
      return nil, ("這個角色的版面已經有 %d 個（上限），請先在編輯模式刪掉一個。"):format(mine)
    end
    local pos = 0
    for i, l in ipairs(cur.saved) do if l.layoutType == Character then pos = i end end
    if pos == 0 then for i, l in ipairs(cur.saved) do if l.layoutType == Account then pos = i end end end
    idx = pos + 1
    table.insert(cur.saved, idx, layout)
    added = true
  end
  local all = {}
  for _, l in ipairs(cur.presets) do all[#all + 1] = l end
  for _, l in ipairs(cur.saved) do all[#all + 1] = l end
  local index = #cur.presets + idx
  local ok, err = pcall(C_EditMode.SaveLayouts, { layouts = all, activeLayout = cur.active })
  if not ok then
    ns.Fail("SaveLayouts", err)
    return nil, "存不了版面（已記下錯誤，打 /amobi 檢查 可以看）。"
  end
  if added and C_EditMode.OnLayoutAdded then
    ns.Call(C_EditMode, "OnLayoutAdded", index, true, false)
  else
    ns.Call(C_EditMode, "SetActiveLayout", index)
  end
  return index
end

local function cvar(name)
  if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
  if GetCVar then return GetCVar(name) end
end

local function setCVar(name, value)
  if C_CVar and C_CVar.SetCVar then return C_CVar.SetCVar(name, value) end
  if SetCVar then return SetCVar(name, value) end
end

-- 打開冷卻監控、首領時間軸、首領警告、傷害統計；回傳打開了哪些
function C.EnableAll()
  local on = {}
  for _, c in ipairs(CVARS) do
    local v = cvar(c[1])
    if v ~= nil and tostring(v) == "0" then
      setCVar(c[1], "1")
      on[#on + 1] = c[2]
    end
  end
  return on
end

-- 一鍵設定：回傳 true, 訊息 或 false, 原因
function C.ApplyRecommended()
  local why = ns.Restricted()
  if why then return false, why .. "不能改介面設定，打完再試。" end
  local cur, err = current()
  if not cur then return false, err end
  local token = ns.PlayerClass()
  local base = layoutAt(cur, cur.active)
  if not base then return false, "讀不到目前的版面。" end
  backup(cur)
  local recs, style = C.Recommend(token)
  local layout = C.ApplyTo(copy(base), recs)
  local name = "阿莫比 " .. ns.ClassName(token)
  local prevName = base.layoutName
  local index, e2 = saveLayout(cur, layout, name)
  if not index then return false, e2 end
  if prevName ~= name then ns.db.prevLayout = prevName end
  local on = C.EnableAll()
  return true, ("已切換到版面「%s」（%s打法）%s。可以在編輯模式（Esc → 編輯模式）微調；位置沒有馬上變的話按「重新載入介面」。")
    :format(name, STYLE_NAME[style] or style, #on > 0 and ("，也打開了" .. table.concat(on, "、")) or "")
end

-- 換回套用前的版面（不刪任何版面）
function C.Revert()
  local why = ns.Restricted()
  if why then return false, why .. "不能改介面設定。" end
  local cur, err = current()
  if not cur then return false, err end
  local want = ns.db.prevLayout
  if not want then return false, "沒有記到套用前的版面。" end
  local idx
  for i, l in ipairs(cur.presets) do if l.layoutName == want then idx = i end end
  for i, l in ipairs(cur.saved) do if l.layoutName == want then idx = #cur.presets + i end end
  if not idx then return false, "找不到原本的版面「" .. want .. "」。" end
  ns.Call(C_EditMode, "SetActiveLayout", idx)
  return true, "已換回版面「" .. want .. "」。"
end

-- 分享：目前版面的暴雪版面代碼
function C.Export()
  local cur, err = current()
  if not cur then return nil, err end
  local l = layoutAt(cur, cur.active)
  local s = l and ns.Call(C_EditMode, "ConvertLayoutInfoToString", l)
  if not s or s == "" then return nil, "轉不出版面代碼。" end
  return s, l.layoutName
end

-- 匯入別人分享的版面代碼（暴雪格式），存成「阿莫比分享」並切換過去
function C.Import(text)
  local why = ns.Restricted()
  if why then return false, why .. "不能改介面設定，打完再試。" end
  text = strtrim(text or "")
  if text == "" then return false, "先貼上版面代碼。" end
  local layout = ns.Call(C_EditMode, "ConvertStringToLayoutInfo", text)
  if type(layout) ~= "table" then return false, "看不懂這串版面代碼，請確認整串都有複製到。" end
  local cur, err = current()
  if not cur then return false, err end
  backup(cur)
  local prev = layoutAt(cur, cur.active)
  local index, e2 = saveLayout(cur, layout, "阿莫比分享")
  if not index then return false, e2 end
  if prev and prev.layoutName ~= "阿莫比分享" then ns.db.prevLayout = prev.layoutName end
  return true, "已匯入並切換到版面「阿莫比分享」。位置沒有馬上變的話按「重新載入介面」。"
end

-- 這個職業建議放進冷卻監控的技能（只列學得到的）
function C.Spells(token, level)
  local cls = CD.classes[token]
  if not cls then return {}, {} end
  local function pick(list)
    local out = {}
    for _, s in ipairs(list) do
      if s.level <= level then out[#out + 1] = s.name end
    end
    return out
  end
  return pick(cls.essential), pick(cls.utility)
end

local function featureState()
  local parts = {}
  local function add(label, api, fn)
    local ok, why = ns.Call(api, fn)
    if ok == nil then return end
    parts[#parts + 1] = label .. (ok and "：可用" or ("：還不能用" .. ((type(why) == "string" and why ~= "") and ("（" .. why .. "）") or "")))
  end
  add("冷卻監控", C_CooldownViewer, "IsCooldownViewerAvailable")
  add("傷害統計", C_DamageMeter, "IsDamageMeterAvailable")
  add("首領時間軸", C_EncounterTimeline, "IsFeatureAvailable")
  return table.concat(parts, "　")
end

-- ---------------------------------------------------------------------------- 分頁
local page = {}

local function say(msg, ok)
  page.status:SetText((ok == false and "|cffff6060" or ok and "|cff60ff60" or "") .. (msg or "") .. ((ok ~= nil) and "|r" or ""))
end

local function build(p)
  page.p = p
  page.head = ns.UI.Text(p, "GameFontHighlightSmall", "", 430)
  page.head:SetPoint("TOPLEFT", 0, 0)
  local apply = ns.UI.Button(p, "套用推薦設定", 130, 26, function()
    local ok, msg = C.ApplyRecommended()
    say(msg, ok)
    if ok then page.reload:Show() end
  end)
  apply:SetPoint("TOPLEFT", 0, -66)
  page.reload = ns.UI.Button(p, "重新載入介面", 110, 26, function()
    if ns.Restricted() then return say("戰鬥中不能重新載入。", false) end
    ReloadUI()
  end)
  page.reload:SetPoint("LEFT", apply, "RIGHT", 8, 0)
  page.reload:Hide()
  local revert = ns.UI.Button(p, "換回原本版面", 110, 26, function()
    local ok, msg = C.Revert()
    say(msg, ok)
  end)
  revert:SetPoint("LEFT", page.reload, "RIGHT", 8, 0)
  page.status = ns.UI.Text(p, "GameFontHighlightSmall", "", 430)
  page.status:SetPoint("TOPLEFT", 0, -96)
  page.spells = ns.UI.Text(p, "GameFontHighlightSmall", "", 430)
  page.spells:SetPoint("TOPLEFT", 0, -128)

  local y = ns.Assist.BuildSettings(p, -184)

  local h2 = ns.UI.Text(p, "GameFontNormal", "分享版面")
  h2:SetPoint("TOPLEFT", 0, y - 6)
  local ex = ns.UI.Button(p, "匯出目前版面", 120, 24, function()
    local s, name = C.Export()
    if not s then return say(name, false) end
    page.box:SetText(s)
    page.box:SetFocus()
    page.box:HighlightText()
    say(("版面「%s」的代碼：按 Ctrl+C 複製。別人貼進小幫手（或暴雪編輯模式的「匯入」）就能用。"):format(name or "?"))
  end)
  ex:SetPoint("TOPLEFT", 0, y - 28)
  local im = ns.UI.Button(p, "匯入貼上的代碼", 120, 24, function()
    local ok, msg = C.Import(page.box:GetText())
    say(msg, ok)
    if ok then page.reload:Show() end
  end)
  im:SetPoint("LEFT", ex, "RIGHT", 8, 0)
  page.box = ns.UI.Edit(p, 420)
  page.box:SetPoint("TOPLEFT", 6, y - 60)
  local note = ns.UI.Text(p, "GameFontDisableSmall",
    "套用前會把你自己的版面備份在小幫手的存檔裡；不會刪掉任何版面。這些都只在戰鬥外能用。", 430)
  note:SetPoint("TOPLEFT", 0, y - 90)
end

local function refresh(p)
  if p.RefreshAssist then p.RefreshAssist() end
  local token = ns.PlayerClass()
  local cls = CD.classes[token] or {}
  page.head:SetText(("打開暴雪的冷卻監控、首領時間軸／警告、傷害統計並擺好位置（%s‧%s打法）：新增版面「阿莫比 %s」，原本的版面不會被改。\n%s")
    :format(ns.ClassName(token), STYLE_NAME[cls.style or "hybrid"] or "", ns.ClassName(token), featureState()))
  local ess, uti = C.Spells(token, UnitLevel("player") or 1)
  local function join(list) return #list > 0 and table.concat(list, "、", 1, math.min(#list, 10)) or "（等級再高一點才有）" end
  page.spells:SetText(ns.GOLD .. "建議放進冷卻監控的技能|r（在冷卻監控的設定裡拖進去）\n重要冷卻：" .. join(ess) .. "\n實用冷卻：" .. join(uti))
end

ns.UI.AddTab("combat", "戰鬥畫面", build, refresh)
