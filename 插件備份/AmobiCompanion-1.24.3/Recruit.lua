-- 阿莫比小幫手：公會招募（1.14.0，老闆 11/5：「有人密我說『公會++』就自動發公會邀請給他」）
--   有人密你關鍵字（預設「公會++」；全形＋＋、中間有空白也算，密語裡有這幾個字就算）
--   → 畫面跳出「公會招募」小視窗記下他的名字 → 按「複製名字」→ 你按 Ctrl+C，自己送公會邀請。
--
-- 為什麼不幫你送：永恆的公會邀請（C_GuildInfo.Invite）只准暴雪自己的介面送，11/5 老闆實測：
--   1.14.0／1.14.1 插件按鈕直接叫 → ADDON_ACTION_FORBIDDEN「AmobiCompanion 嘗試進行 Blizzard UI 專屬動作，遭到封鎖」
--   1.14.2 遊戲的安全巨集按鈕放 /公會邀請 → MACRO_ACTION_FORBIDDEN「巨集指令被 Blizzard UI 有效動作封鎖」
--   1.14.3 聊天框幫你打好 /公會邀請 名字、你按 Enter → 也不行
--   老闆：「刪掉吧」「用ui幫我紀錄誰邀請我就行，然後讓我按複製名字，我再自己邀請」→ 1.14.4 只記名字、給你複製。
--   複製：插件不能直接放進剪貼簿（CopyToClipboard 也有限制），所以名字放進一個選好的輸入框，你按 Ctrl+C。
-- 原則：
--   * 打勾才開（預設關）；這隻角色不在公會、公會沒給邀請權限就不跳（說一次為什麼）
--   * 密語內容、名字是秘密值（副本、首領戰時遊戲會藏起來）就不看
--   * 名字只放在這次上線的清單裡，不存檔、不傳出去；不會回密語（不替你發話）
--   * 同一個人已經在清單上，再密不重複列（時間改成最新的）

local _, ns = ...
local R = {}
ns.Recruit = R

local DEFAULT_WORD = "公會++"
local MAX = 20          -- 清單最多記幾個人（更多的話最早的先拿掉）
local ROWS = 6          -- 小視窗最多顯示幾列，其他寫「還有 N 人」
local ROW_H = 24

local queue = {}
local told = false
local pop

local function S() return ns.db.settings end

-- 比對用：全形＋換半形、拿掉空白（半形、全形）
function R.Normalize(s)
  s = tostring(s or "")
  s = s:gsub("＋", "+"):gsub("　", ""):gsub("%s", "")
  return s
end

function R.Word()
  local w = R.Normalize(S().guildInviteWord)
  if w == "" then return R.Normalize(DEFAULT_WORD) end
  return w
end

function R.Matches(text)
  if type(text) ~= "string" or ns.Secret(text) then return false end
  return R.Normalize(text):find(R.Word(), 1, true) ~= nil
end

-- 同伺服器的人拿掉「-伺服器」（遊戲的邀請用同伺服器的全名會找不到人）
function R.ShortName(full)
  local n, realm = full:match("^(.-)%-(.+)$")
  if n and n ~= "" then
    local mine = GetNormalizedRealmName and GetNormalizedRealmName()
    if mine and not ns.Secret(mine) and realm == mine then return n end
  end
  return full
end

-- 這隻角色能不能邀請：回傳 true，或 false, 原因
function R.CanInvite()
  if not IsInGuild() then return false, "這隻角色不在公會裡" end
  local can = ns.Call(_G, "CanGuildInvite")
  if not ns.Secret(can) and can == false then return false, "公會沒給這隻角色邀請權限" end
  return true
end

-- 遊戲的公會邀請指令（說明用）：繁中有「/公會邀請」就寫它，沒有就寫遊戲的第一個（/ginvite）
function R.Slash()
  for i = 1, 6 do
    local c = _G["SLASH_GUILD_INVITE" .. i]
    if type(c) == "string" and c:find("[\128-\255]") then return c end
  end
  local c = _G.SLASH_GUILD_INVITE1
  if type(c) ~= "string" or c == "" then c = "/ginvite" end
  return c
end

function R.List() return queue end

local function find(name)
  for i, q in ipairs(queue) do
    if q.name == name then return i end
  end
end

local function remove(name)
  local i = find(name)
  if i then table.remove(queue, i) end
end

-- 收到密語
function R.OnWhisper(text, sender)
  if not (ns.db and S().guildInvite) then return end
  if ns.Secret(sender) or type(sender) ~= "string" or sender == "" then return end
  if not R.Matches(text) then return end
  local name = R.ShortName(sender)
  local ok, why = R.CanInvite()
  if not ok then
    if not told then
      told = true
      ns.Print(("%s 密你「%s」，但%s，不能邀請。"):format(name, S().guildInviteWord or DEFAULT_WORD, why))
    end
    return
  end
  local i = find(name)
  if i then
    queue[i].at = GetTime()
    R.ShowPopup()
    return
  end
  queue[#queue + 1] = { name = name, at = GetTime() }
  while #queue > MAX do table.remove(queue, 1) end
  ns.Print(("%s 密你「%s」：小視窗按「複製名字」，再自己送公會邀請。"):format(name, S().guildInviteWord or DEFAULT_WORD))
  R.ShowPopup()
end

-- 按「複製名字」：名字放進小視窗下面的輸入框、選好，玩家按 Ctrl+C（插件不能直接放進剪貼簿）
function R.Copy(name)
  if not name then return end
  if not pop then R.ShowPopup() end
  if not pop then return end
  local q = queue[find(name) or 0]
  if q then q.copied = true end
  pop.copy:SetURL(name)
  pop.copyTip:SetText("按 Ctrl+C 複製")
  R.RefreshPopup()
end

function R.Skip(name)
  remove(name)
  R.ShowPopup()
  ns.UI.Refresh("recruit")
end

function R.Clear()
  queue = {}
  if pop then pop:Hide() end
  ns.UI.Refresh("recruit")
end

-- 試一下：清單加一個假的名字
function R.Test()
  local name = "阿莫比試試看"
  if not find(name) then queue[#queue + 1] = { name = name, at = GetTime(), test = true } end
  R.ShowPopup()
end

-- 開關：關掉時清單清空、小視窗收起來
function R.Apply(on)
  if not on then R.Clear() end
  told = false
end

-- ---------------------------------------------------------------------------- 小視窗
local function ago(at)
  local m = math.floor((GetTime() - at) / 60)
  if m < 1 then return "剛剛" end
  return m .. " 分鐘前"
end

local function buildPopup()
  pop = ns.UI.Panel(UIParent, 300, 100, "HIGH")
  ns.UI.Place(pop, "recruitPos", "TOP", UIParent, "TOP", 0, -170)
  ns.UI.Movable(pop, "recruitPos")
  pop:EnableMouse(true)
  pop.title = ns.UI.Text(pop, "GameFontNormal", "")
  pop.title:SetPoint("TOPLEFT", 10, -9)
  local close = CreateFrame("Button", nil, pop, "UIPanelCloseButton")
  close:SetSize(24, 24)
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() pop:Hide() end)
  pop.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Frame", nil, pop)
    row:SetSize(284, ROW_H - 2)
    row:SetPoint("TOPLEFT", 8, -30 - (i - 1) * ROW_H)
    row.name = ns.UI.Text(row, "GameFontHighlight", "", 100)
    row.name:SetPoint("LEFT", 2, 0)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.ago = ns.UI.Text(row, "GameFontDisableSmall", "", 58)
    row.ago:SetPoint("LEFT", 104, 0)
    if row.ago.SetWordWrap then row.ago:SetWordWrap(false) end
    row.copy = ns.UI.Button(row, "複製名字", 74, 20, function() R.Copy(row.who) end)   -- 老闆 11/5：「讓我按複製名字，我再自己邀請」
    row.copy:SetPoint("RIGHT", -48, 0)
    row.skip = ns.UI.Button(row, "移除", 44, 20, function() R.Skip(row.who) end)
    row.skip:SetPoint("RIGHT", 0, 0)
    pop.rows[i] = row
  end
  pop.more = ns.UI.Text(pop, "GameFontDisableSmall", "")
  pop.skipAll = ns.UI.Button(pop, "全部移除", 76, 20, function() R.Clear() end)
  -- 複製用的輸入框：按「複製名字」後名字在這裡、已經選好，按 Ctrl+C；按了就收起游標
  pop.copyLabel = ns.UI.Text(pop, "GameFontHighlightSmall", "名字")
  pop.copy = ns.UI.CopyBox(pop, 150)
  pop.copyTip = ns.UI.Text(pop, "GameFontNormalSmall", "", 90)
  pop.copy:SetScript("OnKeyUp", function(self, key)
    if key == "C" and IsControlKeyDown() then
      pop.copyTip:SetText("|cff60d060已複製|r")
      self:ClearFocus()
    end
  end)
  pop.hint = ns.UI.Text(pop, "GameFontDisableSmall", "", 280)
  R.popup = pop
end

function R.RefreshPopup()
  if not pop then return end
  local n = #queue
  if n == 0 then pop:Hide(); return end
  pop.title:SetText(ns.GOLD .. "公會招募|r  " .. n .. " 人想入會")
  local shown = math.min(n, ROWS)
  for i, row in ipairs(pop.rows) do
    local q = queue[i]
    if q then
      row.who = q.name
      row.name:SetText(q.name)
      row.ago:SetText(q.test and "（試試看）" or (q.copied and "|cff60d060已複製|r" or ago(q.at)))
      row:Show()
    else
      row.who = nil
      row:Hide()
    end
  end
  local y = -30 - shown * ROW_H - 4
  pop.more:ClearAllPoints()
  pop.more:SetPoint("TOPLEFT", 10, y - 4)
  pop.more:SetText(n > ROWS and ("還有 " .. (n - ROWS) .. " 人") or "")
  pop.skipAll:ClearAllPoints()
  pop.skipAll:SetPoint("TOPRIGHT", -8, y)
  if n > 1 then pop.skipAll:Show() else pop.skipAll:Hide() end
  local line = y - (n > 1 and 28 or 6)
  pop.copyLabel:ClearAllPoints()
  pop.copyLabel:SetPoint("TOPLEFT", 10, line - 5)
  pop.copy:ClearAllPoints()
  pop.copy:SetPoint("TOPLEFT", 44, line)
  pop.copyTip:ClearAllPoints()
  pop.copyTip:SetPoint("TOPLEFT", 202, line - 5)
  if (pop.copy.fixed or "") == "" then pop.copyTip:SetText("按上面「複製名字」") end   -- 遊戲字型沒有箭頭符號
  pop.hint:SetText(("複製後，聊天框打「%s 」再按 Ctrl+V、Enter，或在公會視窗按「邀請成員」貼上。"):format(R.Slash()))
  pop.hint:ClearAllPoints()
  pop.hint:SetPoint("TOPLEFT", 10, line - 28)
  pop:SetHeight(-(line - 28) + 34)
end

function R.ShowPopup()
  if #queue == 0 then
    if pop then pop:Hide() end
    return
  end
  if not pop then buildPopup() end
  pop:Show()
  R.RefreshPopup()
end

-- ---------------------------------------------------------------------------- 事件
function R.Init()
  ns.On("CHAT_MSG_WHISPER", function(text, sender) R.OnWhisper(text, sender) end)
  C_Timer.NewTicker(30, function()                       -- 「幾分鐘前」跟著走
    if pop and pop:IsShown() then ns.Try("recruit", R.RefreshPopup) end
  end)
end
ns.Register(R)

-- ---------------------------------------------------------------------------- 分頁
local function buildTab(p)
  local tip = ns.UI.Text(p, "GameFontHighlightSmall",
    "有人密你關鍵字，畫面會跳出「公會招募」小視窗記下他的名字。按「複製名字」再按 Ctrl+C，就可以自己送公會邀請。" ..
    "遊戲不讓插件、巨集送公會邀請，所以邀請要你自己送。", 430)
  tip:SetPoint("TOPLEFT", 0, 0)
  p.check = ns.UI.Check(p, "有人密我關鍵字時，跳出小視窗記下名字", function() return S().guildInvite end, function(v)
    S().guildInvite = v
    R.Apply(v)
    ns.UI.Refresh("recruit")
  end)
  p.check:SetPoint("TOPLEFT", 0, -48)
  local label = ns.UI.Text(p, "GameFontHighlightSmall", "關鍵字")
  label:SetPoint("TOPLEFT", 4, -86)
  p.word = ns.UI.Edit(p, 140)
  p.word:SetPoint("TOPLEFT", 52, -80)
  local function save(self)
    local text = strtrim(self:GetText() or "")
    S().guildInviteWord = (R.Normalize(text) == "") and DEFAULT_WORD or text
    self:SetText(S().guildInviteWord)
    self:ClearFocus()
  end
  p.word:SetScript("OnEnterPressed", save)
  p.word:SetScript("OnEditFocusLost", function(self) ns.Try("recruit-word", save, self) end)
  local wordNote = ns.UI.Text(p, "GameFontDisableSmall",
    "改完按 Enter。全形「＋＋」、中間有空白也算；密語裡有這幾個字就算，例如「請問可以公會++嗎」。", 430)
  wordNote:SetPoint("TOPLEFT", 0, -110)
  p.status = ns.UI.Text(p, "GameFontHighlightSmall", "", 430)
  p.status:SetPoint("TOPLEFT", 0, -146)
  p.open = ns.UI.Button(p, "打開小視窗", 130, 22, function() R.ShowPopup() end)
  p.open:SetPoint("TOPLEFT", 0, -176)
  local test = ns.UI.Button(p, "試一下視窗", 110, 22, function() R.Test(); ns.UI.Refresh("recruit") end)
  test:SetPoint("LEFT", p.open, "RIGHT", 8, 0)
  local note = ns.UI.Text(p, "GameFontDisableSmall",
    "副本、首領戰中遊戲會把密語內容藏起來，插件讀不到，那時候密的不會跳出來，請他晚點再密一次。\n" ..
    "小視窗可以拖。名字只放在這次上線的清單裡，不存檔、不傳出去；小幫手不會替你回密語。\n" ..
    "同一個人重複密只列一次。", 430)
  note:SetPoint("TOPLEFT", 0, -214)
  R.page = p
end

local function refreshTab(p)
  p.check:Refresh()
  p.word:SetText(S().guildInviteWord or DEFAULT_WORD)
  local ok, why = R.CanInvite()
  local lines = {}
  if not S().guildInvite then
    lines[#lines + 1] = "|cff9d9d9d現在關著：打勾才會跳出小視窗。|r"
  end
  lines[#lines + 1] = ok and "|cff60d060這隻角色可以送公會邀請。|r" or ("|cffff6060" .. why .. "，有人密你也不會跳出來。|r")
  p.status:SetText(table.concat(lines, "\n"))
  local n = #queue
  p.open:SetText(n > 0 and ("打開小視窗（" .. n .. " 人）") or "打開小視窗")
  if n > 0 then p.open:Enable() else p.open:Disable() end
end

ns.UI.AddTab("recruit", "公會招募", buildTab, refreshTab)
