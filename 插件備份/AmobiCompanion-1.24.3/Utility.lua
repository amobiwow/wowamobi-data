-- 阿莫比小幫手：實用功能（「實用功能」分頁）
--   物品用途：物品說明框最下面加中文：這個材料哪些專業用得到（各幾個配方）、這件東西是哪個專業做的
--             （資料是網站的專業技能資料庫，Data\ItemUse.lua）
--   拾取閃光：打開遊戲內建的拾取閃光（任務要撿的東西、還有東西可撿的屍體會閃，像經典版）
--   採集圖示：打開遊戲內建的軟目標圖示（面對草藥、礦點、寶箱、可對話的 NPC 時，上面出現圖示）
--   傷害字型：打怪時怪物頭上跳的數字換字型（插件附的「阿莫比爽字」，或遊戲內建的美版字型），也能調大小
-- 原則：
--   * 說明框只用暴雪給插件的 TooltipDataProcessor（遊戲的擴充點），不 hook、不改說明框的設定；戰鬥中、有插件限制時不加字
--   * 後兩個只是遊戲設定，只在戰鬥外、玩家打勾時改；第一次改之前記下原本的值，取消打勾就改回去
--   * 傷害字型是遊戲讀的全域變數 DAMAGE_TEXT_FONT，插件載入時照設定指過去；選「遊戲原本」就完全不碰
--   * 不會替玩家撿東西、採集或互動（都還是玩家自己按）

local _, ns = ...
local U = {}
ns.Utility = U

local function S() return ns.db.settings end

local function cvar(name)
  if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
  if GetCVar then return GetCVar(name) end
end
local function setCVar(name, value)
  if C_CVar and C_CVar.SetCVar then return C_CVar.SetCVar(name, value) end
  if SetCVar then return SetCVar(name, value) end
end

-- ---------------------------------------------------------------------------- 物品用途
local TEXT = "|cffd8ccb4"
local MAX_PROFS = 3     -- 材料最多列幾個專業，更多的寫「共 N 個專業」

-- 這件物品要加的幾行字（沒有資料回傳 nil）
function U.ItemLines(id)
  local d = ns.ItemUseData
  if not d then return nil end
  local out = {}
  local used = d.used[id]
  if used then
    local parts, n = {}, #used / 2
    for i = 1, math.min(n, MAX_PROFS) do
      parts[#parts + 1] = d.profs[used[i * 2 - 1]] .. " " .. used[i * 2]
    end
    local more = n > MAX_PROFS and ("，共 " .. n .. " 個專業") or ""   -- 例：材料：鍛造 51、工程學 11、採礦 2 個配方用到
    out[#out + 1] = ns.GOLD .. "阿莫比|r " .. TEXT .. "材料：" .. table.concat(parts, "、") .. " 個配方用到" .. more .. "|r"
  end
  local made = d.made[id]
  if made then
    local parts = {}
    for i = 1, #made, 2 do
      local req = made[i + 1]
      parts[#parts + 1] = d.profs[made[i]] .. ((req and req > 0) and ("（技能 " .. req .. "）") or "")
    end
    out[#out + 1] = ns.GOLD .. "阿莫比|r " .. TEXT .. "製作：" .. table.concat(parts, "、") .. "|r"
  end
  if #out == 0 then return nil end
  return out
end

local function onItemTooltip(tooltip, data)
  if not (ns.db and S().itemUse) then return end
  if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end   -- 比較裝備的小框不加
  if ns.Restricted() then return end
  if data == nil or ns.Secret(data) then return end
  local id = data.id
  if ns.Secret(id) or type(id) ~= "number" then return end
  local lines = U.ItemLines(id)
  if not lines then return end
  for _, text in ipairs(lines) do tooltip:AddLine(text, 1, 1, 1, true) end
end

-- ---------------------------------------------------------------------------- 拾取閃光、採集圖示（遊戲設定）
-- 拾取閃光要關掉「外框模式」才會出現（遊戲設定的名字就是「外框關掉時顯示拾取效果」）
local SPARKLE = {
  { "outlineModeShowLootEffectWhenDisabled", "1" },
  { "graphicsOutlineMode", "0" }, { "OutlineEngineMode", "0" },
  { "raidGraphicsOutlineMode", "0" }, { "RAIDOutlineEngineMode", "0" },
}
-- 軟目標：面前可以互動的東西（草藥、礦點、寶箱、NPC）上面出現圖示
local GATHER = {
  { "SoftTargetInteract", "3" }, { "SoftTargetIconGameObject", "1" }, { "SoftTargetIconInteract", "1" },
  { "SoftTargetLowPriorityIcons", "1" }, { "SoftTargetInteractArc", "2" }, { "SoftTargetInteractRange", "30" },
  { "SoftTargetInteractOnlyInRange", "0" },
}
local FEATURES = {
  sparkle = { list = SPARKLE, backup = "sparkleWas",
              on = "已打開拾取閃光。滑鼠指到東西時的外框會一起關掉。",
              off = "已改回你原本的設定。閃光要重開遊戲才會完全消失。" },
  gather = { list = GATHER, backup = "gatherWas",
             on = "已打開。面對草藥、礦點、寶箱時，上面會出現圖示。",
             off = "已改回你原本的設定。" },
}
local pending = {}

-- 照設定打開或改回；回傳 true, 訊息，或 false, 原因（戰鬥中先記著，打完自動做）
function U.Apply(key)
  local f = FEATURES[key]
  local s = S()
  local why = ns.Restricted()
  if why then
    pending[key] = true
    return false, why .. "，打完會自動套用。"
  end
  pending[key] = nil
  if s[key] then
    if not s[f.backup] then          -- 第一次打開：記下原本的值（這個版本沒有的設定讀到 nil，就不碰）
      local was = {}
      for _, c in ipairs(f.list) do was[c[1]] = cvar(c[1]) end
      s[f.backup] = was
    end
    for _, c in ipairs(f.list) do
      local v = cvar(c[1])
      if v ~= nil and tostring(v) ~= c[2] then setCVar(c[1], c[2]) end
    end
    return true, f.on
  elseif s[f.backup] then
    for name, v in pairs(s[f.backup]) do
      if tostring(cvar(name)) ~= tostring(v) then setCVar(name, v) end
    end
    s[f.backup] = nil
    return true, f.off
  end
  return true
end

-- ---------------------------------------------------------------------------- 傷害字型（打怪時怪物頭上跳的數字）
-- 遊戲進入世界時讀全域變數 DAMAGE_TEXT_FONT 決定這些數字的字型（繁中預設是 Fonts\bKAI00M.ttf 文鼎楷書），
-- 所以插件載入時（ADDON_LOADED）照設定指過去；換了要回到角色選擇畫面再進來（或重開遊戲）才會生效。
-- 阿莫比爽字＝Bangers 的數字＋思源黑體的中文（tools/build_damage_font.py 合成，兩個都是 SIL OFL 授權），
-- 繁中打怪也會跳「吸收」「閃躲」這些字，只換英文字型的話會變空白，所以合成在一起。
local FONT_DIR = "Interface\\AddOns\\" .. ns.ADDON .. "\\Fonts\\"
U.FONTS = {
  { key = "game", name = "遊戲原本（楷書）" },
  { key = "amobi", name = "阿莫比爽字（粗斜數字＋黑體中文）", path = FONT_DIR .. "AmobiDamage.ttf" },
  { key = "us", name = "美版字型（「吸收」「閃躲」等中文字會空白）", path = "Fonts\\FRIZQT__.TTF" },
}
-- 大小：遊戲設定（各版本名字不同，有哪個改哪個）；nil＝不碰
local SCALE_CVARS = { "WorldTextScale", "WorldTextScale_v2" }
U.SCALES = { { nil, "原本大小" }, { 1.5, "1.5 倍" }, { 2, "2 倍" } }

local function fontOf(key)
  for _, f in ipairs(U.FONTS) do
    if f.key == key then return f end
  end
  return U.FONTS[1]
end
U.FontOf = fontOf

-- 載入時：記下遊戲原本的字型，照設定換掉；選「遊戲原本」就不碰
function U.ApplyFont()
  U.gameFont = DAMAGE_TEXT_FONT
  local f = fontOf(S().dmgFont)
  if f.path then DAMAGE_TEXT_FONT = f.path end
  U.fontNow = f.key
end

-- 預覽用的字型（自己視窗裡的字，選了馬上看得到；遊戲原本的就照它本來的設定）
function U.PreviewPath(key)
  local f = fontOf(key)
  if f.path then return f.path end
  if U.gameFont then return U.gameFont end
  local ct = _G.CombatTextFont
  local path = ct and ct.GetFont and ct:GetFont()
  return path or "Fonts\\bKAI00M.ttf"
end

local function scaleCVars()
  local out = {}
  for _, name in ipairs(SCALE_CVARS) do
    if cvar(name) ~= nil then out[#out + 1] = name end
  end
  return out
end
U.ScaleCVars = scaleCVars

-- 照設定改數字大小；回傳 true, 訊息，或 false, 原因（戰鬥中先記著，打完自動做）
function U.ApplyScale()
  local s = S()
  local names = scaleCVars()
  if #names == 0 then return false, "這個遊戲版本沒有調整傷害數字大小的設定。" end
  local why = ns.Restricted()
  if why then
    pending.scale = true
    return false, why .. "，打完會自動套用。"
  end
  pending.scale = nil
  if s.dmgScale then
    if not s.dmgScaleWas then
      local was = {}
      for _, name in ipairs(names) do was[name] = cvar(name) end
      s.dmgScaleWas = was
    end
    for _, name in ipairs(names) do
      if tonumber(cvar(name)) ~= s.dmgScale then setCVar(name, tostring(s.dmgScale)) end
    end
    return true, ("傷害數字改成 %s 倍大。"):format(s.dmgScale)
  elseif s.dmgScaleWas then
    for name, v in pairs(s.dmgScaleWas) do
      if tostring(cvar(name)) ~= tostring(v) then setCVar(name, v) end
    end
    s.dmgScaleWas = nil
    return true, "傷害數字大小改回你原本的設定。"
  end
  return true
end

-- 說明：現在用哪個、選了哪個、要不要重新進遊戲、遊戲有沒有開傷害數字
function U.FontStatus()
  local s = S()
  local chosen, now = fontOf(s.dmgFont), fontOf(U.fontNow)
  local lines = {}
  if chosen.key ~= now.key then
    lines[#lines + 1] = ("已選「%s」。回到角色選擇畫面再進入遊戲（或重開遊戲）才會換。"):format(chosen.name)
  else
    lines[#lines + 1] = ("現在用的是「%s」。"):format(now.name)
  end
  if cvar("floatingCombatTextCombatDamage") == "0" then
    lines[#lines + 1] = "遊戲設定把傷害數字關掉了，打 /console floatingCombatTextCombatDamage 1 可以打開。"
  end
  return table.concat(lines, "\n")
end

function U.DiagnoseFont()
  local s = S()
  ns.Print(("傷害字型：選了「%s」，這次進遊戲用「%s」。"):format(fontOf(s.dmgFont).name, fontOf(U.fontNow).name))
  ns.Print(("遊戲原本的字型：%s；現在：%s"):format(tostring(U.gameFont or "（遊戲內建）"), tostring(DAMAGE_TEXT_FONT or "（遊戲內建）")))
  U.probeFrame = U.probeFrame or CreateFrame("Frame")
  local probe = U.probe or U.probeFrame:CreateFontString(nil, "OVERLAY")
  U.probe = probe
  for _, f in ipairs(U.FONTS) do
    if f.path then
      local ok = probe:SetFont(f.path, 20, "OUTLINE")
      ns.Print(("「%s」字型檔：%s"):format(f.name, ok and "|cff60ff60讀得到|r" or "|cffff6060讀不到|r"))
    end
  end
  local parts = {}
  for _, name in ipairs(SCALE_CVARS) do parts[#parts + 1] = name .. "=" .. tostring(cvar(name)) end
  parts[#parts + 1] = "floatingCombatTextCombatDamage=" .. tostring(cvar("floatingCombatTextCombatDamage"))
  ns.Print("遊戲設定：" .. table.concat(parts, "，"))
end

-- ---------------------------------------------------------------------------- 事件
function U.Init()
  ns.Try("damage-font", U.ApplyFont)
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
      ns.Try("itemuse", onItemTooltip, tooltip, data)
    end)
    U.tooltipReady = true
  end
  -- 每次讀完地圖再套一次（改了畫面設定，遊戲可能把外框模式改回來）
  ns.On("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(2.5, function()
      for key, f in pairs(FEATURES) do
        if S()[key] or S()[f.backup] then ns.Try("utility-" .. key, U.Apply, key) end
      end
      if S().dmgScale or S().dmgScaleWas then ns.Try("utility-scale", U.ApplyScale) end
    end)
  end)
  ns.On("PLAYER_REGEN_ENABLED", function()
    for key in pairs(pending) do
      if key == "scale" then
        C_Timer.After(0.7, function() ns.Try("utility-scale", U.ApplyScale) end)
      else
        C_Timer.After(0.7, function() ns.Try("utility-" .. key, U.Apply, key) end)
      end
    end
  end)
end
ns.Register(U)

-- ---------------------------------------------------------------------------- 分頁
local function build(p)
  local tip = ns.UI.Text(p, "GameFontHighlightSmall",
    "這裡都是遊戲本來就有的效果，小幫手只幫你打開、關掉。改遊戲設定只在戰鬥外做；取消打勾會改回你原本的設定。", 430)
  tip:SetPoint("TOPLEFT", 0, 0)
  local status = ns.UI.Text(p, "GameFontHighlightSmall", "", 430)
  p.checks = {}
  local function row(y, label, key, note, after)
    local c = ns.UI.Check(p, label, function() return S()[key] end, function(v)
      S()[key] = v
      local msg
      if after then msg = select(2, after()) end
      status:SetText(msg or "")
      for _, x in ipairs(p.checks) do x:Refresh() end
    end)
    c:SetPoint("TOPLEFT", 0, y)
    p.checks[#p.checks + 1] = c
    local n = ns.UI.Text(p, "GameFontDisableSmall", note, 400)
    n:SetPoint("TOPLEFT", 28, y - 24)
  end
  row(-44, "物品說明框加上中文用途", "itemUse",
    "材料寫哪些專業會用到、各幾個配方；成品寫哪個專業做的。資料是阿莫比網站的專業技能資料庫。戰鬥中不加。")
  row(-112, "任務物品、可拾取的東西發亮", "sparkle",
    "像經典版一樣，任務要撿的東西和還有東西可撿的屍體會閃。會一起關掉滑鼠指到東西時的外框。取消打勾後，要重開遊戲閃光才會完全消失。",
    function() return U.Apply("sparkle") end)
  row(-192, "草藥、礦點、寶箱上面出現圖示", "gather",
    "面對草藥、礦點、寶箱、可對話的 NPC 時，上面會出現遊戲內建的圖示（遊戲的「軟目標」），比較容易看到。小地圖上的採集點請用遊戲的「尋找草藥」「尋找礦物」。",
    function() return U.Apply("gather") end)
  status:SetPoint("TOPLEFT", 0, -272)
  p.status = status

  -- 傷害字型：三選一（打勾當單選用）、預覽一行、大小三個按鈕
  local head = ns.UI.Text(p, "GameFontNormal", ns.GOLD .. "打怪時跳的傷害數字|r")
  head:SetPoint("TOPLEFT", 0, -312)
  local fontNote = ns.UI.Text(p, "GameFontDisableSmall",
    "怪物頭上跳的數字換字型、調大小。字型要回到角色選擇畫面再進入遊戲才會換，下面這行是預覽。", 430)
  fontNote:SetPoint("TOPLEFT", 0, -332)
  local fontStatus = ns.UI.Text(p, "GameFontHighlightSmall", "", 430)
  local preview = p:CreateFontString(nil, "OVERLAY")
  preview:SetJustifyH("LEFT")
  p.preview = preview
  p.fontChecks = {}
  local function showPreview()
    preview:SetFont(U.PreviewPath(S().dmgFont), 26, "OUTLINE")
    preview:SetText("|cffffe14a32071|r  14622  |cff5ef05a+17227|r  吸收")
  end
  p.showPreview = showPreview
  for i, f in ipairs(U.FONTS) do
    local c = ns.UI.Check(p, f.name, function() return S().dmgFont == f.key end, function()
      S().dmgFont = f.key
      for _, x in ipairs(p.fontChecks) do x:Refresh() end
      showPreview()
      fontStatus:SetText(U.FontStatus())
    end)
    c:SetPoint("TOPLEFT", 0, -360 - (i - 1) * 26)
    p.fontChecks[i] = c
  end
  preview:SetPoint("TOPLEFT", 6, -448)
  local sizeLabel = ns.UI.Text(p, "GameFontHighlightSmall", "數字大小")
  sizeLabel:SetPoint("TOPLEFT", 0, -498)
  p.scaleButtons = {}
  for i, o in ipairs(U.SCALES) do
    local b = ns.UI.Button(p, o[2], 96, 22, function()
      S().dmgScale = o[1]
      local _, msg = U.ApplyScale()
      for _, x in ipairs(p.scaleButtons) do x:SetAlpha(x.scale == S().dmgScale and 1 or 0.6) end
      fontStatus:SetText(U.FontStatus() .. (msg and ("\n" .. msg) or ""))
    end)
    b.scale = o[1]
    b:SetPoint("TOPLEFT", 60 + (i - 1) * 104, -494)
    p.scaleButtons[i] = b
  end
  fontStatus:SetPoint("TOPLEFT", 0, -528)
  p.fontStatus = fontStatus
  U.page = p
end

local function refresh(p)
  for _, c in ipairs(p.checks) do c:Refresh() end
  if not U.tooltipReady then p.status:SetText("這個遊戲版本不讓插件在物品說明框加字，物品用途用不了。") end
  for _, c in ipairs(p.fontChecks) do c:Refresh() end
  for _, b in ipairs(p.scaleButtons) do b:SetAlpha(b.scale == S().dmgScale and 1 or 0.6) end
  p.showPreview()
  local extra = (#U.ScaleCVars() == 0) and "\n這個遊戲版本沒有調整傷害數字大小的設定。" or ""
  p.fontStatus:SetText(U.FontStatus() .. extra)
end

ns.UI.AddTab("utility", "實用功能", build, refresh)
