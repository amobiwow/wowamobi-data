-- 阿莫比小幫手：視窗的共用零件和主視窗（分頁：天賦、副本、戰鬥畫面、首領仇恨、打完檢討、實用功能…）
-- 全部是插件自己的一般視窗（不用安全範本、不掛到暴雪的視窗上），戰鬥中開關、拖動都不會被擋。
-- 主視窗第一次打開才建立；每個分頁由功能檔用 UI.AddTab(代號, 名稱, 建立函式, 顯示時更新函式) 加進來。
-- 分頁按鈕排在左邊一直列（1.4.0 起，分頁變多了）；右邊的內容區和以前一樣寬（約 430），各分頁不用改。

local _, ns = ...
local UI = {}
ns.UI = UI

local tabs, win = {}, nil
local TAB_W, PAGE_W = 96, 432
local W, H = 14 + TAB_W + 12 + PAGE_W + 14, 690

function UI.Panel(parent, w, h, strata)
  local f = CreateFrame("Frame", nil, parent or UIParent, "BackdropTemplate")
  f:SetSize(w, h)
  if strata then f:SetFrameStrata(strata) end
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0.05, 0.05, 0.07, 0.94)
    f:SetBackdropBorderColor(0.91, 0.80, 0.53, 0.55)
  end
  return f
end

function UI.Text(parent, font, text, width)
  local s = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  s:SetJustifyH("LEFT")
  s:SetJustifyV("TOP")
  if width then s:SetWidth(width) end
  s:SetText(text or "")
  return s
end

function UI.Button(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 120, h or 24)
  b:SetText(text)
  b:SetScript("OnClick", function(self) ns.Try("button:" .. text, onClick, self) end)
  return b
end

function UI.Edit(parent, w, h)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(w, h or 22)
  e:SetAutoFocus(false)
  e:SetMaxLetters(0)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return e
end

-- 唯讀的網址框：點一下全選，玩家按 Ctrl+C 複製（插件不能直接放進剪貼簿）
function UI.CopyBox(parent, w)
  local e = UI.Edit(parent, w)
  e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  e:SetScript("OnMouseUp", function(self) self:SetFocus(); self:HighlightText() end)
  e:SetScript("OnTextChanged", function(self, user)
    if user and self.fixed then self:SetText(self.fixed); self:HighlightText() end
  end)
  function e:SetURL(text)
    self.fixed = text
    self:SetText(text)
    self:SetFocus()
    self:HighlightText()
  end
  return e
end

function UI.Check(parent, label, get, set)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(24, 24)
  local t = UI.Text(parent, "GameFontHighlightSmall", label)
  t:SetPoint("LEFT", c, "RIGHT", 2, 0)
  c.label = t
  c:SetChecked(get() and true or false)
  c:SetScript("OnClick", function(self) ns.Try("check", set, self:GetChecked() and true or false) end)
  function c:Refresh() self:SetChecked(get() and true or false) end
  return c
end

-- 讓視窗可以拖、記住位置（key 存在設定裡）
function UI.Movable(f, key, handle)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  handle = handle or f
  handle:EnableMouse(true)
  handle:RegisterForDrag("LeftButton")
  handle:SetScript("OnDragStart", function() f:StartMoving() end)
  handle:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local p, _, rp, x, y = f:GetPoint(1)
    if p and ns.db then ns.db.settings[key] = { p, rp, x, y } end
  end)
end

function UI.Place(f, key, ...)
  local pos = ns.db and ns.db.settings[key]
  f:ClearAllPoints()
  if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint(...) end
end

function UI.AddTab(key, title, build, refresh)
  tabs[#tabs + 1] = { key = key, title = title, build = build, refresh = refresh }
end

local function showTab(key)
  for _, t in ipairs(tabs) do
    local on = t.key == key
    if t.page then
      if on then t.page:Show() else t.page:Hide() end
    end
    if t.button then
      t.button:SetAlpha(on and 1 or 0.6)
    end
    if on then
      if not t.page then
        t.page = CreateFrame("Frame", nil, win)
        t.page:SetPoint("TOPLEFT", 14 + TAB_W + 12, -40)
        t.page:SetPoint("BOTTOMRIGHT", -14, 12)
        ns.Try("build:" .. key, t.build, t.page)
      end
      t.page:Show()
      if t.refresh then ns.Try("refresh:" .. key, t.refresh, t.page) end
    end
  end
  win.current = key
end

local function build()
  win = UI.Panel(UIParent, W, H, "DIALOG")
  UI.Place(win, "winPos", "CENTER", UIParent, "CENTER", 0, 40)
  UI.Movable(win, "winPos")
  local title = UI.Text(win, "GameFontNormalLarge", ns.GOLD .. "阿莫比小幫手|r")
  title:SetPoint("TOPLEFT", 14, -12)
  local site = UI.Text(win, "GameFontDisableSmall", "wowamobi.com")
  site:SetPoint("LEFT", title, "RIGHT", 8, -1)
  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() win:Hide() end)
  local y = -40
  for _, t in ipairs(tabs) do                                   -- 分頁按鈕：左邊一直列
    local b = UI.Button(win, t.title, TAB_W, 26, function() showTab(t.key) end)
    b:SetPoint("TOPLEFT", 14, y)
    y = y - 30
    t.button = b
  end
  win:Hide()
end

function UI.Open(key)
  if not win then build() end
  win:Show()
  showTab(key or win.current or tabs[1].key)
end

function UI.Toggle()
  if win and win:IsShown() then win:Hide() else UI.Open() end
end

function UI.Refresh(key)
  if not (win and win:IsShown() and win.current == key) then return end
  for _, t in ipairs(tabs) do
    if t.key == key and t.refresh and t.page then ns.Try("refresh:" .. key, t.refresh, t.page) end
  end
end

-- 確認視窗（自己做的，不用暴雪的 StaticPopup，避免污染）：標題、內容幾行、確定／取消
local dialog
function UI.Confirm(title, lines, okText, onOK)
  if not dialog then
    dialog = UI.Panel(UIParent, 400, 300, "FULLSCREEN_DIALOG")
    dialog:SetPoint("CENTER", 0, 60)
    dialog:EnableMouse(true)
    dialog.title = UI.Text(dialog, "GameFontNormalLarge", "")
    dialog.title:SetPoint("TOPLEFT", 16, -14)
    dialog.body = UI.Text(dialog, "GameFontHighlight", "", 368)
    dialog.body:SetPoint("TOPLEFT", 16, -42)
    dialog.ok = UI.Button(dialog, "確定", 120, 26, function()
      dialog:Hide()
      if dialog.onOK then dialog.onOK() end
    end)
    dialog.ok:SetPoint("BOTTOMRIGHT", -16, 14)
    dialog.cancel = UI.Button(dialog, "取消", 100, 26, function() dialog:Hide() end)
    dialog.cancel:SetPoint("RIGHT", dialog.ok, "LEFT", -8, 0)
  end
  dialog.title:SetText(title)
  dialog.body:SetText(table.concat(lines, "\n"))
  dialog.ok:SetText(okText or "確定")
  dialog.onOK = onOK
  local h = (dialog.body.GetStringHeight and dialog.body:GetStringHeight()) or 0
  dialog:SetHeight(math.max(160, math.min(560, h + 100)))
  dialog:Show()
  ns.UI.dialog = dialog
  return dialog
end
