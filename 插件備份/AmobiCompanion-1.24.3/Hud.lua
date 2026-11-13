-- 阿莫比小幫手：畫面優化（1.22.0；老闆 11/8 看到別人的介面「他的ui也太好看了吧」→ 列了四項 →「四個都先優化」）
-- 示意圖：D:\魔獸網站\小幫手介面優化示意圖\之後.png
--   1. 升級預估：畫面上方一條：等級、經驗「目前／升級要的」和百分比、休息經驗；這次登入平均每小時拿多少經驗、照這個速度多久升級。
--      滿級不顯示。經驗讀 UnitXP、UnitXPMax、GetXPExhaustion（和遊戲下面那條經驗條一樣），升級時跨級的經驗也算進去。
--   2. 頭像搬到中間：分頁按鈕呼叫 Combat.lua 的 C.ApplyUnitFrames（編輯模式的版面「阿莫比 <職業>」只改你自己、目標的頭像位置）。
--   3. 戰鬥計時：進戰鬥（PLAYER_REGEN_DISABLED）開始跑秒，脫離戰鬥停住、顯示 6 秒這場打了多久。
--   4. 團隊工具列：在隊伍或團隊裡才出現：開怪倒數（Boss.lua 的 B.Countdown，和 /amobi pull 一樣 10 秒）、8 個標記
--      （標在你的目標身上，目標已經是這個標記就拿掉，和暴雪團隊管理的按鈕一樣：SetRaidTarget("target", n)）、清除目標的標記、
--      就位確認（C_PartyInfo.DoReadyCheck）。函式和暴雪自己的團隊管理（Blizzard_CompactRaidFrameManager）一樣；地面標記要安全按鈕，不做。
--      團隊裡標記、就位、倒數要隊長或助理（遊戲規定），不是的話按了會說。
-- 三個顯示的位置可以在「畫面優化」分頁解鎖後拖曳（記在設定 hudXpPos、hudTimerPos、hudRaidPos），都可以各自關掉。
-- 只顯示、按了按鈕才做那一件事，不會替你施法、選目標或移動。
-- 1.22.1（老闆看了第一版的截圖：「沒有那種框 而且我真的受不了標楷體的字了」）：字換遊戲內建的文鼎粗黑（bHEI01B）、
--   金色圓角框（像示意圖）、經驗條加框和底色；計時移到畫面正中央偏右下（原本在下面中間，和戰鬥輔助的「近戰範圍內」「DPS」疊在一起）。

local _, ns = ...
local H = {}
ns.Hud = H

local STATUSBAR = "Interface\\TargetingFrame\\UI-StatusBar"
local MARK_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local MARK_NAMES = { "星星", "圓圈", "菱形", "三角", "月亮", "方塊", "叉叉", "骷髏" }
local TIMER_LINGER = 6
local XP_W = 440
local TIMER_POS = { 160, -125 }   -- 畫面正中央往右 160、往下 125（戰鬥輔助的距離、DPS 在正中間往下，避開）

local function S() return ns.db.settings end
local function num(v) return type(v) == "number" and not ns.Secret(v) and v or nil end
local function yes(v) return not ns.Secret(v) and v and true or false end

local function comma(n)
  local s = tostring(math.floor(n + 0.5))
  local k
  repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
  return s
end

-- 秒數 → 「39 分鐘」「1 小時 23 分」「1 天 2 小時」
function H.Duration(sec)
  sec = math.max(0, math.floor(sec + 0.5))
  if sec < 60 then return "不到 1 分鐘" end
  local m = math.floor(sec / 60)
  if m < 60 then return m .. " 分鐘" end
  local h = math.floor(m / 60)
  if h < 24 then return ("%d 小時 %d 分"):format(h, m % 60) end
  return ("%d 天 %d 小時"):format(math.floor(h / 24), h % 24)
end

local function clock(sec)
  sec = math.max(0, math.floor(sec))
  if sec >= 3600 then return ("%d:%02d:%02d"):format(math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60) end
  return ("%02d:%02d"):format(math.floor(sec / 60), sec % 60)
end

local function maxLevel()
  return num(ns.Call(_G, "GetMaxLevelForPlayerExpansion")) or num(ns.Call(_G, "GetMaxPlayerLevel")) or 60
end

-- 字型：遊戲內建的文鼎粗黑（Fonts\bHEI01B.ttf，AR Heiti Bold B5，繁中客戶端都有）；老闆 11/8 看了第一版：「我真的受不了標楷體的字了」
-- （繁中的 STANDARD_TEXT_FONT 是文鼎隸書 bLEI00D）。讀不到就退回遊戲字型。
local FONT = "Fonts\\bHEI01B.ttf"

local function shadowText(parent, size, flags)
  local t = parent:CreateFontString(nil, "OVERLAY")
  if not t:SetFont(FONT, size, flags or "OUTLINE") then t:SetFont(STANDARD_TEXT_FONT, size, flags or "OUTLINE") end
  t:SetJustifyH("LEFT")
  return t
end

-- 示意圖那種框：深色底、金色圓角邊（遊戲說明框的邊框材質）
local function goldBox(f, alpha)
  if not f.SetBackdrop then return end
  f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                  tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  f:SetBackdropColor(0.05, 0.035, 0.02, alpha or 0.86)
  f:SetBackdropBorderColor(0.91, 0.78, 0.45, 0.95)
end

-- 別的檔（Flight.lua 鳥點計時器、MapPlus.lua 地圖）也用同一套黑體字和金框
H.Text, H.GoldBox, H.FONT = shadowText, goldBox, FONT

-- 解鎖時可以拖：位置記在設定裡
local function draggable(f, key)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if not S().hudLocked then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint(1)
    if p then S()[key] = { p, rp, x, y } end
  end)
end

-- ------------------------------------------------------------------ 1. 升級預估
local xpFrame
local xp = { start = nil, gained = 0, last = nil, lastMax = nil }

-- 經驗變了：算這次拿到多少（升級時 UnitXP 歸零：上一級剩下的加上這一級的）
function H.OnXP()
  local cur, max = num(UnitXP("player")), num(UnitXPMax("player"))
  if not cur or not max or max <= 0 then return end
  if xp.last and xp.lastMax then
    if cur >= xp.last then
      xp.gained = xp.gained + (cur - xp.last)
    else
      xp.gained = xp.gained + math.max(0, xp.lastMax - xp.last) + cur
    end
  end
  xp.last, xp.lastMax = cur, max
  H.UpdateXP()
end

-- 這次登入的每小時經驗（玩了 2 分鐘以上、有拿到經驗才算）、預計多久升級
function H.XPRate()
  if not xp.start then return nil end
  local secs = GetTime() - xp.start
  if secs < 120 or xp.gained <= 0 then return nil end
  return xp.gained / secs * 3600
end

function H.XPText()
  local level = num(UnitLevel("player"))
  local cur, max = num(UnitXP("player")), num(UnitXPMax("player"))
  if not level or not cur or not max or max <= 0 then return nil end
  local rested = num(ns.Call(_G, "GetXPExhaustion")) or 0
  local pct = cur / max * 100
  local line1 = ("%s / %s　%.1f%%"):format(comma(cur), comma(max), pct)
  local rate = H.XPRate()
  local parts = {}
  if rate then
    parts[#parts + 1] = "預計升級 " .. ns.GOLD .. H.Duration((max - cur) / rate * 3600) .. "|r"
    parts[#parts + 1] = "每小時 " .. ns.GOLD .. comma(rate) .. "|r 經驗"
  else
    parts[#parts + 1] = "打幾隻怪後算預計升級時間"
  end
  if rested > 0 then parts[#parts + 1] = ("休息經驗 |cff8fb6ff%.1f%%|r"):format(rested / max * 100) end
  return level, line1, table.concat(parts, "　"), cur / max, math.min(rested, max - cur) / max
end

local function buildXP()
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetSize(XP_W, 54)
  f:SetFrameStrata("LOW")
  goldBox(f)
  f.level = shadowText(f, 16)
  f.level:SetPoint("TOPLEFT", 11, -10)
  f.level:SetTextColor(1, 0.86, 0.5)
  f.num = shadowText(f, 14)
  f.num:SetPoint("TOPRIGHT", -11, -11)
  f.num:SetJustifyH("RIGHT")
  -- 經驗條：有框、有底色，0% 的時候也看得出一條
  f.barBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
  f.barBox:SetHeight(16)
  f.barBox:SetPoint("TOPLEFT", 82, -10)
  f.barBox:SetPoint("RIGHT", f.num, "LEFT", -10, 0)
  if f.barBox.SetBackdrop then
    f.barBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f.barBox:SetBackdropColor(0.13, 0.1, 0.16, 0.95)
    f.barBox:SetBackdropBorderColor(0.91, 0.78, 0.45, 0.6)
  end
  f.bar = CreateFrame("StatusBar", nil, f.barBox)
  f.bar:SetStatusBarTexture(STATUSBAR)
  f.bar:SetStatusBarColor(0.62, 0.36, 1)
  f.bar:SetMinMaxValues(0, 1)
  f.bar:SetPoint("TOPLEFT", 1, -1)
  f.bar:SetPoint("BOTTOMRIGHT", -1, 1)
  f.rest = f.bar:CreateTexture(nil, "ARTWORK")
  f.rest:SetColorTexture(0.31, 0.55, 1, 0.6)
  f.info = shadowText(f, 13)
  f.info:SetPoint("BOTTOMLEFT", 11, 9)
  f.hint = shadowText(f, 11)
  f.hint:SetPoint("BOTTOMRIGHT", -11, 9)
  f.hint:SetText("|cff9a9a9a拖曳移動|r")
  ns.UI.Place(f, "hudXpPos", "TOP", UIParent, "TOP", 0, -22)
  draggable(f, "hudXpPos")
  xpFrame = f
end

function H.UpdateXP()
  if not xpFrame then return end
  local s = S()
  local level, line1, line2, frac, restFrac = H.XPText()
  local atMax = level and level >= maxLevel()
  local want = s.hudXp and level and not atMax
  if not want and not (s.hudXp and not s.hudLocked) then xpFrame:Hide(); return end
  xpFrame:EnableMouse(not s.hudLocked)
  xpFrame.hint:SetShown(not s.hudLocked)
  if want then
    xpFrame.level:SetText("等級 " .. level)
    xpFrame.num:SetText(line1)
    xpFrame.info:SetText(line2)
    xpFrame.bar:SetValue(frac)
    local w = xpFrame.bar:GetWidth()
    if type(w) == "number" and w > 0 and restFrac > 0 then
      xpFrame.rest:ClearAllPoints()
      xpFrame.rest:SetPoint("TOPLEFT", xpFrame.bar, "TOPLEFT", w * frac, 0)
      xpFrame.rest:SetPoint("BOTTOMLEFT", xpFrame.bar, "BOTTOMLEFT", w * frac, 0)
      xpFrame.rest:SetWidth(math.max(1, w * restFrac))
      xpFrame.rest:Show()
    else
      xpFrame.rest:Hide()
    end
  else
    xpFrame.level:SetText("升級預估")
    xpFrame.num:SetText("")
    xpFrame.info:SetText("滿級不顯示")
    xpFrame.bar:SetValue(0)
    xpFrame.rest:Hide()
  end
  xpFrame:Show()
end

-- ------------------------------------------------------------------ 3. 戰鬥計時
local timerFrame
local fightStart, fightEnd

local function buildTimer()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(120, 46)
  f:SetFrameStrata("LOW")
  f.text = shadowText(f, 28, "THICKOUTLINE")
  f.text:SetPoint("TOP", 0, 0)
  f.text:SetJustifyH("CENTER")
  f.label = shadowText(f, 12)
  f.label:SetPoint("TOP", f.text, "BOTTOM", 0, -1)
  f.label:SetJustifyH("CENTER")
  -- 預設在畫面中央偏右下：戰鬥輔助的距離、DPS、仇恨在正中間往下 110～170（Assist.lua），第一版放在下面中間會疊在一起（老闆 11/8 截圖）
  ns.UI.Place(f, "hudTimerPos", "CENTER", UIParent, "CENTER", TIMER_POS[1], TIMER_POS[2])
  draggable(f, "hudTimerPos")
  local acc = 0
  f:SetScript("OnUpdate", function(self, el)
    acc = acc + el
    if acc < 0.2 then return end
    acc = 0
    ns.Try("hud:timer", H.UpdateTimer)
  end)
  timerFrame = f
end

function H.UpdateTimer()
  if not timerFrame then return end
  local s, t = S(), GetTime()
  if fightStart and not fightEnd then
    timerFrame.text:SetText(clock(t - fightStart))
    timerFrame.label:SetText("|cffff8a6a戰鬥中|r")
  elseif fightStart and fightEnd and t - fightEnd < TIMER_LINGER then
    timerFrame.text:SetText(clock(fightEnd - fightStart))
    timerFrame.label:SetText("|cffbfbfbf這場打了|r")
  elseif not s.hudLocked then
    timerFrame.text:SetText("00:00")
    timerFrame.label:SetText("|cff9a9a9a戰鬥計時（拖曳移動）|r")
  else
    timerFrame.text:SetText("")
    timerFrame.label:SetText("")
  end
  local want = s.hudTimer and (timerFrame.text:GetText() or "") ~= ""
  timerFrame:EnableMouse(not s.hudLocked)
  timerFrame:SetShown(want)
end

function H.TimerText() return timerFrame and timerFrame.text:GetText() or nil end

-- ------------------------------------------------------------------ 4. 團隊工具列
local raidFrame

local function leaderOrAssist()
  if not yes(IsInRaid and IsInRaid()) then return true end              -- 小隊裡每個人都能標記
  return yes(UnitIsGroupLeader("player")) or yes(UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
end

-- 標記：標在目標身上；目標已經是這個標記就拿掉。回傳 成功, 訊息
function H.Mark(i)
  if not yes(UnitExists("target")) then return false, "先選一個目標，再按標記。" end
  if not leaderOrAssist() then return false, "團隊裡要隊長或助理才能標記。" end
  local now = num(ns.Call(_G, "GetRaidTargetIndex", "target"))
  local want = (i ~= 0 and now == i) and 0 or i
  ns.Call(_G, "SetRaidTarget", "target", want)
  return true, want == 0 and "已拿掉目標的標記。" or ("已標上「" .. MARK_NAMES[want] .. "」。")
end

function H.ReadyCheck()
  if not yes(IsInGroup()) then return false, "要在隊伍裡才能發就位確認。" end
  if not (yes(UnitIsGroupLeader("player")) or yes(UnitIsGroupAssistant and UnitIsGroupAssistant("player"))) then
    return false, "要隊長或助理才能發就位確認。"
  end
  if not (C_PartyInfo and C_PartyInfo.DoReadyCheck) then return false, "這個遊戲版本沒有就位確認。" end
  ns.Call(C_PartyInfo, "DoReadyCheck")
  return true, "已發出就位確認。"
end

local function sayResult(ok, msg)
  if not ok and msg then ns.Print("|cffff6060" .. msg .. "|r") end
end

local function smallButton(parent, text, w, onClick)
  local b = ns.UI.Button(parent, text, w, 24, onClick)
  local fs = b.GetFontString and b:GetFontString()
  if fs and not fs:SetFont(FONT, 13, "") then fs:SetFont(STANDARD_TEXT_FONT, 13, "") end
  return b
end

local function buildRaid()
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetFrameStrata("LOW")
  goldBox(f)
  local x = 9
  local cd = smallButton(f, "倒數", 44, function()
    local ok, msg = ns.Boss.Countdown(10)
    sayResult(ok, msg)
  end)
  cd:SetPoint("LEFT", x, 0)
  x = x + 44 + 6
  f.marks = {}
  for i = 1, 8 do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(22, 22)
    b:SetPoint("LEFT", x, 0)
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(MARK_ICON .. i)
    b:SetHighlightTexture(MARK_ICON .. i, "ADD")
    b:SetScript("OnClick", function() ns.Try("hud:mark", function() sayResult(H.Mark(i)) end) end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:SetText(MARK_NAMES[i])
      GameTooltip:AddLine("標在你的目標身上；目標已經是這個標記就拿掉", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.marks[i] = b
    x = x + 24
  end
  x = x + 4
  local clear = smallButton(f, "清除", 44, function() sayResult(H.Mark(0)) end)
  clear:SetPoint("LEFT", x, 0)
  x = x + 44 + 4
  local ready = smallButton(f, "就位", 44, function() sayResult(H.ReadyCheck()) end)
  ready:SetPoint("LEFT", x, 0)
  x = x + 44 + 9
  f:SetSize(x, 38)
  f.hint = shadowText(f, 11)
  f.hint:SetPoint("TOP", f, "BOTTOM", 0, -2)
  f.hint:SetJustifyH("CENTER")
  f.hint:SetText("|cff9a9a9a團隊工具列（組隊才出現；拖曳移動）|r")
  ns.UI.Place(f, "hudRaidPos", "TOP", UIParent, "TOP", 0, -82)
  draggable(f, "hudRaidPos")
  raidFrame = f
end

function H.UpdateRaid()
  if not raidFrame then return end
  local s = S()
  raidFrame:EnableMouse(not s.hudLocked)
  raidFrame.hint:SetShown(not s.hudLocked)
  raidFrame:SetShown(s.hudRaid and (yes(IsInGroup()) or not s.hudLocked))
end

-- ------------------------------------------------------------------ 5. 全部的字換黑體（1.23.0）
-- 老闆 11/8：「我真的受不了標楷體的字了」→「要，全部換黑體」。繁中客戶端的介面字型大多是文鼎隸書（bLEI00D）、
-- 戰鬥數字是文鼎楷書（bKAI00M）。這裡把遊戲所有的字型物件（GetFonts 列出來的：GameFontNormal、任務、聊天框、名條…）裡
-- 用隸書或楷書的，換成遊戲內建的文鼎黑體（bHEI00M 中黑；16 以上的標題用 bHEI01B 粗黑），大小、外框照原本的。
-- 只呼叫字型物件的 SetFont（和改字型的插件一樣），不碰任何框架；後來才載入的暴雪介面（拍賣場、天賦…）載入時再換一次。
-- 頭上的名字是遊戲讀全域變數 UNIT_NAME_FONT（和傷害數字的 DAMAGE_TEXT_FONT 一樣，Utility.lua 也是這樣換），重新登入才生效。
-- 關掉：馬上換回原本的字型（頭上的名字要重新登入）。傷害數字的字型照「實用功能」那邊的設定，這裡不動。
local HEI_M, HEI_B = "Fonts\\bHEI00M.ttf", "Fonts\\bHEI01B.ttf"
local swapped = {}        -- [字型物件] = { 原本的檔, 大小, 樣式 }
local fontSoon = false

local function isKai(path)
  path = type(path) == "string" and path:lower() or ""
  return path:find("blei", 1, true) ~= nil or path:find("bkai", 1, true) ~= nil
end

local function fontObjects()
  local out = {}
  local names = ns.Call(_G, "GetFonts")
  if type(names) == "table" then
    for _, n in ipairs(names) do
      local o = type(n) == "string" and _G[n] or n
      if type(o) == "table" and type(o.GetFont) == "function" and type(o.SetFont) == "function" then out[#out + 1] = o end
    end
  end
  return out
end

-- 換一輪；回傳這次換了幾個
function H.ApplyGameFont()
  if not S().gameFontHei then return 0 end
  local n = 0
  for _, o in ipairs(fontObjects()) do
    if not swapped[o] then
      local ok, path, size, flags = pcall(o.GetFont, o)
      if ok and isKai(path) and type(size) == "number" and size > 0 then
        local new = size >= 16 and HEI_B or HEI_M
        if pcall(o.SetFont, o, new, size, flags or "") then
          swapped[o] = { path, size, flags or "" }
          n = n + 1
        end
      end
    end
  end
  return n
end

function H.RestoreGameFont()
  for o, f in pairs(swapped) do pcall(o.SetFont, o, f[1], f[2], f[3]) end
  swapped = {}
end

function H.SwappedCount()
  local n = 0
  for _ in pairs(swapped) do n = n + 1 end
  return n
end

function H.SetGameFont(on)
  S().gameFontHei = on
  if on then H.ApplyGameFont() else H.RestoreGameFont() end
end

-- 別的插件、後來才載入的暴雪介面也會建字型物件：載入後半秒再換一輪
local function fontLater()
  if fontSoon or not S().gameFontHei then return end
  fontSoon = true
  C_Timer.After(0.5, function()
    fontSoon = false
    ns.Try("hud:font", H.ApplyGameFont)
  end)
end

-- ------------------------------------------------------------------ 全部
function H.Refresh()
  H.UpdateXP()
  H.UpdateTimer()
  H.UpdateRaid()
end

function H.SetLocked(locked)
  S().hudLocked = locked
  H.Refresh()
end

function H.ResetPositions()
  S().hudXpPos, S().hudTimerPos, S().hudRaidPos = nil, nil, nil
  if xpFrame then ns.UI.Place(xpFrame, "hudXpPos", "TOP", UIParent, "TOP", 0, -22) end
  if timerFrame then ns.UI.Place(timerFrame, "hudTimerPos", "CENTER", UIParent, "CENTER", TIMER_POS[1], TIMER_POS[2]) end
  if raidFrame then ns.UI.Place(raidFrame, "hudRaidPos", "TOP", UIParent, "TOP", 0, -82) end
end

function H.Init()
  if S().gameFontHei then
    if isKai(UNIT_NAME_FONT) then UNIT_NAME_FONT = HEI_M end                -- 頭上的名字：遊戲進入世界時讀（重新登入生效）
    H.ApplyGameFont()
  end
  ns.On("ADDON_LOADED", fontLater)
  ns.On("PLAYER_LOGIN", fontLater)
  buildXP()
  buildTimer()
  buildRaid()
  ns.On("PLAYER_ENTERING_WORLD", function()
    if not xp.start then
      xp.start = GetTime()
      xp.last, xp.lastMax = num(UnitXP("player")), num(UnitXPMax("player"))
    end
    H.Refresh()
  end)
  ns.On("PLAYER_XP_UPDATE", function(unit) if unit == nil or unit == "player" then H.OnXP() end end)
  ns.On("PLAYER_LEVEL_UP", function() C_Timer.After(0.5, function() ns.Try("hud:levelup", H.OnXP) end) end)
  ns.On("UPDATE_EXHAUSTION", function() H.UpdateXP() end)
  ns.On("PLAYER_REGEN_DISABLED", function()
    fightStart, fightEnd = GetTime(), nil
    H.UpdateTimer()
  end)
  ns.On("PLAYER_REGEN_ENABLED", function()
    if fightStart and not fightEnd then fightEnd = GetTime() end
    H.UpdateTimer()
  end)
  ns.On("GROUP_ROSTER_UPDATE", function() H.UpdateRaid() end)
  C_Timer.NewTicker(30, function() ns.Try("hud:xp", H.UpdateXP) end)       -- 預計升級時間跟著時間走
  H.Refresh()
end

-- ------------------------------------------------------------------ 分頁「畫面優化」
local page = {}

local function buildTab(p)
  local y = 0
  local function line(text, font, gap)
    local t = ns.UI.Text(p, font or "GameFontHighlightSmall", text, 420)
    t:SetPoint("TOPLEFT", 0, y)
    local h = t:GetStringHeight()
    y = y - (gap or ((type(h) == "number" and h or 14) + 8))
    return t
  end
  local function check(label, key)
    local c = ns.UI.Check(p, label, function() return S()[key] end, function(v)
      S()[key] = v
      H.Refresh()
    end)
    c:SetPoint("TOPLEFT", -4, y)
    y = y - 26
    return c
  end
  line(ns.GOLD .. "畫面優化|r", "GameFontNormal", 24)
  line("都只是顯示和按鈕，不會替你做別的事；不喜歡的取消打勾就好。")
  page.checks = {
    check("升級預估（畫面上方：經驗、每小時經驗、預計多久升級、休息經驗；滿級不顯示）", "hudXp"),
    check("戰鬥計時（進戰鬥開始跑秒，打完停 6 秒）", "hudTimer"),
    check("團隊工具列（在隊伍、團隊裡才出現：倒數、8 個標記、清除、就位確認）", "hudRaid"),
  }
  y = y - 4
  page.lock = ns.UI.Button(p, "", 120, 24, function() H.SetLocked(not S().hudLocked); page.refresh() end)
  page.lock:SetPoint("TOPLEFT", 0, y)
  local reset = ns.UI.Button(p, "位置重設", 90, 24, function() H.ResetPositions(); H.Refresh() end)
  reset:SetPoint("LEFT", page.lock, "RIGHT", 8, 0)
  y = y - 34
  line("解鎖後三樣都會顯示出來，直接用滑鼠拖到想要的位置，再按「鎖定位置」。", "GameFontDisableSmall")
  y = y - 6
  page.font = ns.UI.Check(p, "全部的字換成黑體（遊戲原本的楷書、隸書都換掉）", function() return S().gameFontHei end, function(v)
    H.SetGameFont(v)
    page.say(v and ("已換成黑體（%d 種字）。人物頭上的名字要重新登入才會換。"):format(H.SwappedCount())
               or "已換回遊戲原本的字。人物頭上的名字要重新登入才會換回來。", true)
  end)
  page.font:SetPoint("TOPLEFT", -4, y)
  y = y - 30
  -- 1.24.0：滑鼠閃亮亮、鳥點計時器、M 地圖增強
  line(ns.GOLD .. "滑鼠、飛行、M 地圖|r", "GameFontNormal", 22)
  local function check2(label, key, x, after)
    local c = ns.UI.Check(p, label, function() return S()[key] ~= false end, function(v)
      S()[key] = v
      if after then after() end
    end)
    c:SetPoint("TOPLEFT", x - 4, y)
    page.checks[#page.checks + 1] = c
    return c
  end
  check2("滑鼠跟隨閃亮亮（戰鬥中不顯示）", "cursorSparkle", 0)
  check2("鳥點計時器（飛行時上方顯示還要多久到）", "flightTimer", 214, function() ns.Flight.Update() end)
  y = y - 24
  check2("M 地圖：顯示沒探索的地方", "mapReveal", 0, function() ns.MapPlus.Dirty() end)
  check2("M 地圖：建議等級、領地", "mapInfo", 214, function() ns.MapPlus.Dirty() end)
  y = y - 26
  line("M 地圖上要標的 NPC（位置是經典版參考）：", "GameFontDisableSmall")
  page.pins = {}
  for i, k in ipairs(ns.MapPlus.KINDS) do
    local c = ns.UI.Check(p, k.name, function() return ns.MapPlus.PinOn(k.key) end, function(v) ns.MapPlus.SetPin(k.key, v) end)
    c:SetPoint("TOPLEFT", ((i - 1) % 4) * 107 - 4, y - math.floor((i - 1) / 4) * 22)
    page.pins[#page.pins + 1] = c
  end
  y = y - math.ceil(#ns.MapPlus.KINDS / 4) * 22 - 10
  line(ns.GOLD .. "頭像搬到中間|r", "GameFontNormal", 22)
  line("把你和目標的頭像搬到技能列上方左右兩邊。存在編輯模式的版面「阿莫比 " .. ns.ClassName(ns.PlayerClass()) ..
       "」，原本的版面不會被改，可以在編輯模式（Esc → 編輯模式）微調。只在戰鬥外能用。")
  local apply = ns.UI.Button(p, "頭像搬到中間", 120, 26, function()
    local ok, msg = ns.Combat.ApplyUnitFrames()
    page.say(msg, ok)
    if ok then page.reload:Show() end
  end)
  apply:SetPoint("TOPLEFT", 0, y)
  page.reload = ns.UI.Button(p, "重新載入介面", 110, 26, function()
    if ns.Restricted() then return page.say("戰鬥中不能重新載入。", false) end
    ReloadUI()
  end)
  page.reload:SetPoint("LEFT", apply, "RIGHT", 8, 0)
  page.reload:Hide()
  local revert = ns.UI.Button(p, "換回原本版面", 110, 26, function()
    local ok, msg = ns.Combat.Revert()
    page.say(msg, ok)
  end)
  revert:SetPoint("LEFT", page.reload, "RIGHT", 8, 0)
  y = y - 34
  page.status = line("", "GameFontHighlightSmall", 40)
  function page.say(msg, ok)
    page.status:SetText((ok == false and "|cffff6060" or ok and "|cff60ff60" or "") .. (msg or "") .. ((ok ~= nil) and "|r" or ""))
  end
  function page.refresh()
    for _, c in ipairs(page.checks) do c:Refresh() end
    page.font:Refresh()
    for _, c in ipairs(page.pins or {}) do c:Refresh() end
    page.lock:SetText(S().hudLocked and "解鎖位置" or "鎖定位置")
  end
end

local function refreshTab()
  if page.refresh then page.refresh() end
end

ns.UI.AddTab("hud", "畫面優化", buildTab, refreshTab)
ns.Register(H)
