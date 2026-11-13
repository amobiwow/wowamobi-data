-- 阿莫比小幫手：首領提醒和仇恨（「首領仇恨」分頁）
--
-- 永恆的插件讀不到戰鬥紀錄和王的施法（秘密值），BigWigs、DBM 那種「看到王施法就跳警告」的插件做不到；
-- 暴雪改成內建的「首領時間軸」和「首領警告」（遊戲自己知道王什麼時候放技能）。這裡替玩家把它們打開、調好：
--   * 首領時間軸、首領警告的開關（encounterTimelineEnabled、encounterWarningsEnabled）
--   * 警告等級 encounterWarningsLevel：最低顯示哪一級（Enum.EncounterEventSeverity：Low 0、Medium 1、High 2；
--     Blizzard_EncounterWarnings/EncounterWarningsUtil.lua 照它決定顯不顯示）
--   * 時間軸樣式 C_EncounterTimeline.SetViewType（Enum.EncounterTimelineViewType：Timeline 1 時間軸、Bars 2 橫條）
--   * 警告收起來時也播音效 C_EncounterWarnings.SetPlayCustomSoundsWhenHidden
--   * 開怪倒數：遊戲內建的倒數 C_PartyInfo.DoCountdown（和 /countdown 一樣，隊伍裡每個人畫面上都會出現）
-- 仇恨：
--   * 目標頭像的仇恨百分比 threatShowNumeric（Blizzard_UnitFrame 的 ShowNumericThreat 讀它）
--   * 名條的仇恨顯示 nameplateThreatDisplay 是 bitfield：C_CVar.SetCVarBitfield(名稱, 值, true/false)，
--     值是 Enum.NamePlateThreatDisplay（Progressive 1 漸層、Flash 2 閃爍、HealthBarColor 3 血條變色），
--     和遊戲設定畫面（Blizzard_SettingsDefinitions_Frame/Nameplates.lua、Settings.GetCVarMask）一樣
--   * 「我的仇恨」小塊在 Assist.lua（和距離、DPS 一起解鎖拖動）
-- 改遊戲設定只在戰鬥外、玩家按的時候做；第一次改前記下原本的值（settings.bossWas），「全部改回原本」改回去。
-- 這個版本沒有的設定（讀到 nil）不顯示、不碰。

local _, ns = ...
local B = {}
ns.Boss = B

local function S() return ns.db.settings end

local function cvar(name)
  if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
  if GetCVar then return GetCVar(name) end
end
local function setCVar(name, value)
  if C_CVar and C_CVar.SetCVar then return C_CVar.SetCVar(name, value) end
  if SetCVar then return SetCVar(name, value) end
end

local function E(name) return Enum and Enum[name] or {} end

-- ---------------------------------------------------------------------------- 遊戲設定
-- 每一項：key（存原本值用）、label、has()、get()、set(v)；開關是 true/false，選擇是數字
local function cvarFlag(name)
  return {
    has = function() return cvar(name) ~= nil end,
    get = function() return tostring(cvar(name)) == "1" end,
    set = function(v) setCVar(name, v and "1" or "0") end,
  }
end
local function cvarNumber(name)
  return {
    has = function() return cvar(name) ~= nil end,
    get = function() return tonumber(cvar(name)) end,
    set = function(v) setCVar(name, tostring(v)) end,
  }
end
local function bitFlag(name, enumName, key)
  local function index() return E(enumName)[key] end
  return {
    has = function() return cvar(name) ~= nil and index() ~= nil and C_CVar and C_CVar.GetCVarBitfield ~= nil end,
    get = function() return ns.Call(C_CVar, "GetCVarBitfield", name, index()) == true end,
    set = function(v) ns.Call(C_CVar, "SetCVarBitfield", name, index(), v and true or false) end,
  }
end
local function apiValue(api, getter, setter)
  return {
    has = function() local t = _G[api]; return t ~= nil and t[getter] ~= nil and t[setter] ~= nil end,
    get = function() return ns.Call(_G[api], getter) end,
    set = function(v) ns.Call(_G[api], setter, v) end,
  }
end

local function item(key, label, impl) impl.key, impl.label = key, label; return impl end
B.ITEMS = {
  timeline = item("timeline", "首領時間軸（王接下來要放什麼技能）", cvarFlag("encounterTimelineEnabled")),
  warnings = item("warnings", "首領警告（畫面上方的大字警告）", cvarFlag("encounterWarningsEnabled")),
  level = item("level", "警告等級", cvarNumber("encounterWarningsLevel")),
  view = item("view", "時間軸樣式", apiValue("C_EncounterTimeline", "GetViewType", "SetViewType")),
  sound = item("sound", "警告收起來時也播音效", apiValue("C_EncounterWarnings", "GetPlayCustomSoundsWhenHidden", "SetPlayCustomSoundsWhenHidden")),
  numeric = item("numeric", "目標頭像顯示仇恨百分比", cvarFlag("threatShowNumeric")),
  plateColor = item("plateColor", "名條：仇恨高的怪血條變色", bitFlag("nameplateThreatDisplay", "NamePlateThreatDisplay", "HealthBarColor")),
  plateProgressive = item("plateProgressive", "名條：仇恨越高顏色越深", bitFlag("nameplateThreatDisplay", "NamePlateThreatDisplay", "Progressive")),
  plateFlash = item("plateFlash", "名條：快要被怪打的時候閃爍", bitFlag("nameplateThreatDisplay", "NamePlateThreatDisplay", "Flash")),
}
B.LEVELS = { { 0, "全部" }, { 1, "中等以上" }, { 2, "只有最危險的" } }
B.VIEWS = { { "Timeline", "時間軸" }, { "Bars", "橫條" } }
B.COUNTDOWNS = { 5, 10, 15 }

-- 改一項：回傳 true 或 false, 原因。第一次改前記下原本的值
function B.Set(key, value)
  local it = B.ITEMS[key]
  if not (it and it.has()) then return false, "這個遊戲版本沒有這個設定。" end
  local why = ns.Restricted()
  if why then return false, why .. "不能改遊戲設定，打完再按。" end
  local s = S()
  s.bossWas = s.bossWas or {}
  if s.bossWas[key] == nil then
    local was = it.get()
    if was ~= nil then s.bossWas[key] = was end
  end
  it.set(value)
  return true, ""
end

-- 全部改回第一次改之前的值
function B.RestoreAll()
  local why = ns.Restricted()
  if why then return false, why .. "不能改遊戲設定，打完再按。" end
  local s, n = S(), 0
  for key, was in pairs(s.bossWas or {}) do
    local it = B.ITEMS[key]
    if it and it.has() then
      it.set(was)
      n = n + 1
    end
  end
  s.bossWas = nil
  return true, n > 0 and "已經改回你原本的設定。" or "沒有改過任何設定。"
end

-- 一鍵推薦：時間軸、警告都打開、全部等級、警告收起來也播音效；仇恨百分比、名條血條變色和閃爍
function B.Recommend()
  local why = ns.Restricted()
  if why then return false, why .. "不能改遊戲設定，打完再按。" end
  local want = { timeline = true, warnings = true, level = 0, sound = true, numeric = true, plateColor = true, plateFlash = true }
  local done = {}
  for key, v in pairs(want) do
    local it = B.ITEMS[key]
    if it.has() and it.get() ~= v and B.Set(key, v) then done[#done + 1] = key end
  end
  return true, #done > 0 and "已套用推薦設定。" or "推薦設定本來就都開著了。"
end

-- 開怪倒數：遊戲內建的倒數（隊伍裡每個人都看得到）；0 秒是取消
function B.Countdown(sec)
  local api = C_PartyInfo
  if not (api and api.DoCountdown) then return false, "這個遊戲版本沒有開怪倒數。" end
  local why = ns.Restricted()
  if why then return false, why .. "不能開始倒數。" end
  sec = math.max(0, math.min(60, math.floor(tonumber(sec) or 10)))
  local ok = pcall(api.DoCountdown, sec)
  if not ok then return false, "遊戲沒有開始倒數（在團隊裡要隊長或助理才能倒數）。" end
  if sec == 0 then return true, "已取消倒數。" end
  return true, ("開始 %d 秒倒數，隊伍裡每個人畫面上都看得到。"):format(sec)
end

-- /amobi pull [秒]
function B.Slash(arg)
  local sec = tonumber(arg)
  local ok, msg = B.Countdown(sec or 10)
  ns.Print((ok and "" or "|cffff6060") .. msg .. (ok and "" or "|r"))
end

-- ---------------------------------------------------------------------------- 分頁
local page = {}

local function say(msg, ok)
  if not page.status then return end
  page.status:SetText((ok == false and "|cffff6060" or "") .. (msg or "") .. (ok == false and "|r" or ""))
end

local function refreshControls()
  for _, c in ipairs(page.checks or {}) do
    c:Refresh()
    local it = B.ITEMS[c.itemKey]
    if it then c:SetAlpha(it.has() and 1 or 0.4) end
  end
  local level = B.ITEMS.level.has() and B.ITEMS.level.get()
  for _, b in ipairs(page.levelButtons or {}) do b:SetAlpha(b.value == level and 1 or 0.55) end
  local view = B.ITEMS.view.has() and B.ITEMS.view.get()
  local VT = E("EncounterTimelineViewType")
  for _, b in ipairs(page.viewButtons or {}) do b:SetAlpha(VT[b.value] ~= nil and VT[b.value] == view and 1 or 0.55) end
end

local function build(p)
  page.p = p
  page.checks = {}
  local intro = ns.UI.Text(p, "GameFontHighlightSmall",
    "永恆不讓插件讀王的施法，BigWigs、DBM 那種插件做不到；首領提醒改成暴雪內建的「首領時間軸」和「首領警告」，小幫手幫你打開、調好。位置在「戰鬥畫面」分頁一起擺好。", 430)
  intro:SetPoint("TOPLEFT", 0, 0)
  local rec = ns.UI.Button(p, "套用推薦設定", 120, 24, function()
    local ok, msg = B.Recommend()
    say(msg, ok)
    refreshControls()
  end)
  rec:SetPoint("TOPLEFT", 0, -44)
  local back = ns.UI.Button(p, "全部改回原本", 110, 24, function()
    local ok, msg = B.RestoreAll()
    say(msg, ok)
    refreshControls()
  end)
  back:SetPoint("LEFT", rec, "RIGHT", 8, 0)

  local function check(key, y, x)
    local it = B.ITEMS[key]
    local c = ns.UI.Check(p, it.label, function() return it.has() and it.get() == true end, function(v)
      local ok, msg = B.Set(key, v)
      if not ok then say(msg, false) else say("") end
      refreshControls()
    end)
    c.itemKey = key
    c:SetPoint("TOPLEFT", x or 0, y)
    page.checks[#page.checks + 1] = c
    return c
  end
  local function choice(label, list, y, onPick)
    local t = ns.UI.Text(p, "GameFontHighlightSmall", label)
    t:SetPoint("TOPLEFT", 28, y - 4)
    local out, x = {}, 110
    for _, o in ipairs(list) do
      local b = ns.UI.Button(p, o[2], o[2]:len() > 9 and 104 or 84, 22, function()
        local ok, msg = onPick(o[1])
        if not ok then say(msg, false) else say("") end
        refreshControls()
      end)
      b.value = o[1]
      b:SetPoint("TOPLEFT", x, y)
      x = x + (o[2]:len() > 9 and 108 or 88)
      out[#out + 1] = b
    end
    return out
  end

  local h1 = ns.UI.Text(p, "GameFontNormal", "首領提醒")
  h1:SetPoint("TOPLEFT", 0, -80)
  check("timeline", -100)
  check("warnings", -124)
  page.levelButtons = choice("警告等級", B.LEVELS, -150, function(v) return B.Set("level", v) end)
  page.viewButtons = choice("時間軸樣式", B.VIEWS, -176, function(v)
    local VT = E("EncounterTimelineViewType")
    if VT[v] == nil then return false, "這個遊戲版本沒有這個樣式。" end
    return B.Set("view", VT[v])
  end)
  check("sound", -202)

  local h2 = ns.UI.Text(p, "GameFontNormal", "開怪倒數")
  h2:SetPoint("TOPLEFT", 0, -238)
  local x = 0
  for _, sec in ipairs(B.COUNTDOWNS) do
    local b = ns.UI.Button(p, sec .. " 秒", 70, 22, function()
      local ok, msg = B.Countdown(sec)
      say(msg, ok)
    end)
    b:SetPoint("TOPLEFT", x, -258)
    x = x + 76
  end
  local cancel = ns.UI.Button(p, "取消倒數", 84, 22, function()
    local ok, msg = B.Countdown(0)
    say(msg, ok)
  end)
  cancel:SetPoint("TOPLEFT", x + 6, -258)
  local cdNote = ns.UI.Text(p, "GameFontDisableSmall", "用遊戲內建的倒數，隊伍裡每個人畫面上都會出現；團隊裡要隊長或助理才能倒數。也可以打 /amobi pull 10。", 430)
  cdNote:SetPoint("TOPLEFT", 0, -286)

  local h3 = ns.UI.Text(p, "GameFontNormal", "仇恨")
  h3:SetPoint("TOPLEFT", 0, -320)
  local mine = ns.UI.Check(p, "戰鬥中顯示我的仇恨（組隊時，在距離、DPS 下面）", function() return S().threat end, function(v)
    S().threat = v
    ns.Assist.ShowThreat()
    refreshControls()
  end)
  mine:SetPoint("TOPLEFT", 0, -340)
  page.checks[#page.checks + 1] = mine
  local solo = ns.UI.Check(p, "一個人打怪也顯示", function() return S().threatSolo end, function(v)
    S().threatSolo = v
    ns.Assist.ShowThreat()
    refreshControls()
  end)
  solo:SetPoint("TOPLEFT", 24, -364)
  page.checks[#page.checks + 1] = solo
  check("numeric", -390)
  check("plateColor", -414)
  check("plateProgressive", -438)
  check("plateFlash", -462)
  local tNote = ns.UI.Text(p, "GameFontDisableSmall",
    "副本裡遊戲會限制仇恨數值：插件只能「顯示」你自己的仇恨，看不出全隊誰最高（坦克請看名條顏色）。「我的仇恨」的位置在「戰鬥畫面」分頁和距離、DPS 一起解鎖拖動。", 430)
  tNote:SetPoint("TOPLEFT", 0, -490)

  page.status = ns.UI.Text(p, "GameFontHighlightSmall", "", 430)
  page.status:SetPoint("TOPLEFT", 0, -536)
  B.page = page
end

local function refresh()
  refreshControls()
end

ns.UI.AddTab("boss", "首領仇恨", build, refresh)
