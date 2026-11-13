-- 阿莫比小幫手：血條美化（1.13.0）
--
-- 老闆 11/3：「我不要放別人的UI呀，我是要把它整合進來變成我們自己的UI，你開一個功能讓他們可以開啟協調美化就好了吧」。
-- LINE 社群玩家問有沒有像 EllesmereUI 的血條。程式是自己寫的，只參考外觀（Plater、EllesmereUI 的授權不能併進來）。
--
-- 血條插件通常自己重畫一份，血量、仇恨、施法、增減益都要自己處理秘密值。這裡不重畫：血條還是遊戲的，
-- 數值、顏色、施法條、增減益都照遊戲跑，只換材質和外框，所以這個檔案一個秘密值都不碰，戰鬥中、副本裡也一樣。
--
--   遊戲設定（打開時記下原值，關掉改回；之後玩家自己去遊戲設定改的不會被蓋掉）：
--     樣式「細條」（名字在血條上面）、血條裡顯示血量百分比、施法條顯示法術名稱圖示和目標、重要施法高亮、玩家職業色
--   外觀（結構照永恆客戶端 70707 的 Blizzard_NamePlates）：
--     血條換 Media\PlateBar 的直向漸層（灰階，遊戲的顏色乘上去）、加高到 16（細條 13 放不下百分比）
--     bgTexture 改成深色底，比血條大 1 格，同時是底和外框
--     selectedBorder 改成金色的整塊，壓在 bgTexture 底下、大 2 格，只露出一圈；
--     顯示不顯示還是遊戲決定（選中目標、專注目標），不用自己判斷誰是目標
--     施法條的底和血條同色、法術圖示切掉邊；施法條本身的顏色（可打斷、不可打斷）不動
--
-- 遊戲會把外觀改回去：NamePlateUnitFrameMixin:UpdateAnchors 重設材質，ApplyFrameOptions 重設目標框。
-- 不用 hooksecurefunc（會污染，測試也擋），改在叫到它的時機之後再套一次：名條出現、改遊戲設定（CVAR_UPDATE）、
-- 視窗大小改變、敵我變了（UNIT_FACTION）。後面三個放到下一個畫面才做，排在遊戲自己處理完之後。
-- UnitFrame 是共用的，換過的記在 touched，關掉之後回到畫面上的也要改回去（遊戲不會重設圖層、施法條底的位置、圖示的切邊）。
--
-- 限制：副本裡友方的名條遊戲不給（forbidden），維持原樣；裝了別的血條插件就完全不動。

local _, ns = ...
local P = {}
ns.Plates = P

local function S() return ns.db.settings end

local BAR_TEXTURE = "Interface\\AddOns\\AmobiCompanion\\Media\\PlateBar"
local BAR_FALLBACK = "Interface\\TargetingFrame\\UI-StatusBar"
local BAR_HEIGHT = 16
local DARK = { 0.05, 0.04, 0.035, 0.92 }    -- 血條、施法條的底和外框
local GOLD = { 0.91, 0.80, 0.53, 1 }        -- 選中目標的框（小幫手的金色）；專注目標遊戲會再染成橘色

local touched = setmetatable({}, { __mode = "k" })
local pending = false

local function cvar(name)
  if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
end
local function setCVar(name, value)
  if C_CVar and C_CVar.SetCVar then return C_CVar.SetCVar(name, value) end
end

-- 第一個是一般設定（值），後面是 bitfield 的設定（打開哪幾個位元）
local PLAIN = { { "nameplateShowClassColor", "1" }, { "nameplateShowFriendlyClassColor", "1" } }
local BITS = {
  { "nameplateInfoDisplay", "NamePlateInfoDisplay", { "CurrentHealthPercent" } },
  { "nameplateCastBarDisplay", "NamePlateCastBarDisplay",
    { "SpellName", "SpellIcon", "SpellTarget", "HighlightImportantCasts", "HighlightWhenCastTarget" } },
}
local function settingNames()
  local out = { "nameplateStyle" }
  for _, c in ipairs(PLAIN) do out[#out + 1] = c[1] end
  for _, b in ipairs(BITS) do out[#out + 1] = b[1] end
  return out
end

local function applySettings()
  local style = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Thin
  if style ~= nil then setCVar("nameplateStyle", tostring(style)) end
  for _, c in ipairs(PLAIN) do
    if cvar(c[1]) ~= nil then setCVar(c[1], c[2]) end
  end
  for _, b in ipairs(BITS) do
    local enum = Enum and Enum[b[2]]
    if enum and cvar(b[1]) ~= nil then
      for _, key in ipairs(b[3]) do
        if enum[key] ~= nil then ns.Call(C_CVar, "SetCVarBitfield", b[1], enum[key], true) end
      end
    end
  end
end

-- ---------------------------------------------------------------------------- 外觀
local function parts(uf)
  local box = uf.HealthBarsContainer
  local bar = box and box.healthBar
  if not (bar and bar.barTexture and bar.bgTexture and bar.selectedBorder) then return nil end
  return box, bar, uf.CastBarsContainer and uf.CastBarsContainer.castBar
end

local function usable(uf)
  if not uf then return false end
  local okF, forbidden = pcall(uf.IsForbidden, uf)
  if not okF or forbidden then return false end
  local okP, protected = pcall(uf.IsProtected, uf)
  return okP and not protected
end

local function style(uf)
  local setup = NamePlateSetupOptions
  if setup and setup.useClassicHealthBar then return end    -- 經典樣式有自己的外框，不換
  local box, bar, cast = parts(uf)
  if not box then return end
  touched[uf] = true
  local height = BAR_HEIGHT * (setup and setup.verticalScale or 1)
  if (setup and setup.healthBarHeight or 0) < height then box:SetHeight(height) end
  if not bar.barTexture:SetTexture(BAR_TEXTURE) then bar.barTexture:SetTexture(BAR_FALLBACK) end

  local bg = bar.bgTexture
  bg:SetTextureSliceMargins(0, 0, 0, 0)
  bg:SetColorTexture(DARK[1], DARK[2], DARK[3], DARK[4])
  bg:SetDrawLayer("BACKGROUND", -7)
  bg:ClearAllPoints()
  bg:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
  bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)

  local sel = bar.selectedBorder
  sel:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], GOLD[4])
  sel:SetDrawLayer("BACKGROUND", -8)
  sel:ClearAllPoints()
  sel:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 2)
  sel:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 2, -2)

  if cast and cast.Background then
    cast.Background:SetColorTexture(DARK[1], DARK[2], DARK[3], DARK[4])
    cast.Background:ClearAllPoints()
    cast.Background:SetPoint("TOPLEFT", cast, "TOPLEFT", -1, 1)
    cast.Background:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", 1, -1)
    if cast.Icon then cast.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  end
end

-- 照遊戲 UpdateAnchors、ApplyStyleAndAnchoring 的值改回去
local function unstyle(uf)
  touched[uf] = nil
  local box, bar, cast = parts(uf)
  if not box then return end
  local setup = NamePlateSetupOptions
  if setup and setup.healthBarHeight then box:SetHeight(setup.healthBarHeight) end
  bar.barTexture:SetAtlas("UI-HUD-CoolDownManager-Bar", true)

  local bg = bar.bgTexture
  bg:SetAtlas("UI-HUD-CoolDownManager-Bar-BG", true)
  bg:SetDrawLayer("BACKGROUND")
  bg:ClearAllPoints()
  bg:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 3)
  bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 6, -6)

  local sel = bar.selectedBorder
  local constants = NamePlateConstants or {}
  local at = constants.SELECTED_BORDER_OFFSETS or { topLeftX = -3, topLeftY = 2, bottomRightX = 0, bottomRightY = 2 }
  sel:SetAtlas(constants.SELECTED_BORDER_ATLAS or "UI-HUD-CoolDownManager-Selected-yellow", false)
  sel:SetDrawLayer("OVERLAY")
  sel:ClearAllPoints()
  sel:SetPoint("TOPLEFT", bg, "TOPLEFT", at.topLeftX, at.topLeftY)
  sel:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", at.bottomRightX, at.bottomRightY)

  if cast and cast.Background then
    cast.Background:SetAtlas("ui-castingbar-background")
    cast.Background:ClearAllPoints()
    cast.Background:SetPoint("TOPLEFT", cast, "TOPLEFT", 1, 0)
    cast.Background:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", -1, 0)
    if cast.Icon then cast.Icon:SetTexCoord(0, 1, 0, 1) end
  end
end

function P.Active()
  return S().plateBeauty and #ns.Assist.Conflicts().plates == 0
end

local function refreshUnit(unit)
  local plate = ns.Assist.PlateFor(unit)
  local uf = plate and plate.UnitFrame
  if not usable(uf) then return end
  if P.Active() then style(uf) elseif touched[uf] then unstyle(uf) end
end

function P.Refresh()
  for i = 1, 40 do
    local unit = "nameplate" .. i
    if UnitExists(unit) then refreshUnit(unit) end
  end
end

-- 下一個畫面再套，排在遊戲自己處理完之後；同一個畫面來好幾次只做一次
local queued = false
local function soon()
  if queued then return end
  queued = true
  C_Timer.After(0, function()
    queued = false
    ns.Try("plates-refresh", P.Refresh)
  end)
end

-- ---------------------------------------------------------------------------- 開關
-- 照設定打開或改回；回傳 true, 訊息，或 false, 原因（戰鬥中先記著，打完自動做）
function P.Apply()
  local s = S()
  local why = ns.Restricted()
  if why then
    pending = true
    return false, why .. "，打完會自動套用。"
  end
  pending = false
  if s.plateBeauty then
    local c = ns.Assist.Conflicts()
    if #c.plates > 0 then
      return false, "偵測到 " .. table.concat(c.plates, "、") .. "：兩個一起用會打架，血條美化先不動。"
    end
    if not s.plateBeautyWas then
      local was = {}
      for _, name in ipairs(settingNames()) do was[name] = cvar(name) end
      s.plateBeautyWas = was
      applySettings()
    end
    P.Refresh()
    ns.Assist.RefreshPlates()
    return true, "已打開血條美化，取消勾選就改回遊戲原本的樣子。"
  end
  P.Refresh()
  if s.plateBeautyWas then
    for name, v in pairs(s.plateBeautyWas) do setCVar(name, v) end
    s.plateBeautyWas = nil
  end
  ns.Assist.RefreshPlates()
  return true, "已改回遊戲原本的血條。"
end

function P.Init()
  ns.On("NAME_PLATE_UNIT_ADDED", function(unit)
    if type(unit) == "string" and not ns.Secret(unit) then refreshUnit(unit) end
  end)
  ns.On("CVAR_UPDATE", function() if P.Active() then soon() end end)
  ns.On("DISPLAY_SIZE_CHANGED", function() if P.Active() then soon() end end)
  ns.On("UNIT_FACTION", function(unit)
    if P.Active() and type(unit) == "string" and not ns.Secret(unit) and unit:find("^nameplate%d") then soon() end
  end)
  ns.On("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(2.5, function()
      local s = S()
      if (s.plateBeauty and not s.plateBeautyWas) or (s.plateBeautyWas and not s.plateBeauty) then
        ns.Try("plates-apply", P.Apply)
      end
    end)
  end)
  ns.On("PLAYER_REGEN_ENABLED", function()
    if pending then C_Timer.After(0.7, function() ns.Try("plates-apply", P.Apply) end) end
  end)
end
ns.Register(P)
