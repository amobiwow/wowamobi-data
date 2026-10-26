-- 阿莫比小幫手：增益到期提醒（「增益提醒」分頁）
--
-- 吃的東西（進食充分等）、睡袋（舒適的睡袋放好躺一分鐘給的「充分休息」）、藥劑和卷軸給的增益，
-- 快到期時提醒一次（畫面上方一行大字＋聊天框＋音效），到期（消失）時再提醒一次。只提醒你身上有過的增益，不會催你吃。
-- 要看哪些增益：Data\Buffs.lua（tools\extract_buffs.py 從永恆客戶端整理：食物和飲料、藥劑、精煉藥劑、卷軸的使用效果、睡袋的充分休息）。
-- 永恆的插件限制：戰鬥中、打首領時，身上的增益是秘密值，插件讀不到（C_UnitAuras 文件：有插件限制時是秘密值）。
--   所以只在戰鬥外每 5 秒看一次身上的增益；戰鬥中到期的，打完第一次看的時候才提醒。讀到的值有秘密值就整輪跳過。
-- 死掉時增益會一起消失，不算到期；換吃別的食物、補喝藥劑（同名的還在）也不算。
-- 只讀增益、只顯示：不會替你吃東西、喝藥劑或放睡袋。

local _, ns = ...
local B = {}
ns.Reminder = B

local TICK = 5
local KINDS = {   -- 類別、設定開關、名稱、剩幾秒提醒
  { key = "food", setting = "buffFood", label = "食物", warnAt = 60 },
  { key = "rested", setting = "buffRested", label = "睡袋", warnAt = 300 },
  { key = "elixir", setting = "buffElixir", label = "藥劑和卷軸", warnAt = 120 },
}
local KIND = {}
for _, k in ipairs(KINDS) do KIND[k.key] = k end

local watch                 -- [技能編號] = 類別
local tracked = {}          -- [技能編號] = { name, kind, expires, warned }
local banner

local function S() return ns.db.settings end

local function buildWatch()
  watch = {}
  for kind, list in pairs((ns.BuffData or {}).kinds or {}) do
    for id in pairs(list) do watch[id] = kind end
  end
end

local function clock(sec)
  sec = math.max(0, math.floor(sec + 0.5))
  if sec >= 3600 then return ("%d 小時 %d 分"):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
  if sec >= 60 then return ("%d 分 %02d 秒"):format(math.floor(sec / 60), sec % 60) end
  return sec .. " 秒"
end
B.Clock = clock

-- 身上要看的增益：{ [技能編號] = { name, kind, expires, stacks } }；戰鬥中、有限制、死了、讀到秘密值回傳 nil（這輪不判斷）
function B.Scan()
  if ns.Restricted() or UnitIsDeadOrGhost("player") then return nil end
  if not watch then buildWatch() end
  local api = C_UnitAuras
  if not (api and api.GetAuraDataByIndex) then return nil end
  local seen = {}
  for i = 1, 40 do
    local ok, a = pcall(api.GetAuraDataByIndex, "player", i, "HELPFUL")
    if not ok then return nil end
    if a == nil then break end
    if ns.Secret(a) then return nil end
    local id = a.spellId
    if ns.Secret(id) then return nil end
    local kind = watch[id]
    if kind and S()[KIND[kind].setting] then
      local expires, name = a.expirationTime, a.name
      if ns.Secret(expires) or ns.Secret(name) then return nil end
      if type(expires) == "number" and expires > 0 then
        local stacks = (not ns.Secret(a.applications)) and a.applications or nil
        seen[id] = { name = (type(name) == "string" and name ~= "") and name or ns.BuffData.kinds[kind][id], kind = kind,
                     expires = expires, stacks = stacks }
      end
    end
  end
  return seen
end

-- ---------------------------------------------------------------------------- 提醒
local function buildBanner()
  banner = CreateFrame("Frame", nil, UIParent)
  banner:SetSize(600, 40)
  banner:SetFrameStrata("HIGH")
  banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  banner.text:SetPoint("CENTER")
  banner.text:SetJustifyH("CENTER")
  banner:SetPoint("TOP", UIParent, "TOP", 0, -170)
  banner:Hide()
  banner:SetScript("OnUpdate", function(self)
    if self.hideAt and GetTime() >= self.hideAt then self:Hide() end
  end)
  B.banner = banner
end

-- kind：soon 快到期（黃）、gone 到期（橘）
function B.Alert(text, kind)
  if not banner then buildBanner() end
  banner.text:SetText(text)
  if kind == "gone" then banner.text:SetTextColor(1, 0.55, 0.25) else banner.text:SetTextColor(1, 0.85, 0.2) end
  banner.hideAt = GetTime() + 8
  banner:Show()
  ns.Print(text)
  if S().buffSound and PlaySound then
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
  end
  B.lastAlert = text
end

-- 這個增益消失了，但同類（食物、睡袋）或同名（藥劑）的還在：換吃、補喝，不算到期
local function stillCovered(seen, t)
  for _, cur in pairs(seen) do
    if t.kind == "elixir" then
      if cur.name == t.name then return true end
    elseif cur.kind == t.kind then
      return true
    end
  end
  return false
end

function B.Tick()
  if not S().buffRemind then tracked = {} return end
  local seen = B.Scan()
  if not seen then return end
  local now = GetTime()
  for id, cur in pairs(seen) do
    local old = tracked[id]
    local warned = old and old.warned or false
    if old and cur.expires > old.expires + 2 then warned = false end         -- 補吃、補喝了，時間變長
    local t = { name = cur.name, kind = cur.kind, expires = cur.expires, warned = warned, stacks = cur.stacks }
    tracked[id] = t
    local left = cur.expires - now
    if not t.warned and left > 0 and left <= KIND[cur.kind].warnAt then
      t.warned = true
      B.Alert(("%s 快到期了：還剩 %s"):format(t.name, clock(left)), "soon")
    end
  end
  for id, t in pairs(tracked) do
    if not seen[id] then
      tracked[id] = nil
      if not stillCovered(seen, t) then
        local tip = t.kind == "rested" and "（再放一次睡袋躺一分鐘）" or ""
        B.Alert(("%s 已經結束了%s"):format(t.name, tip), "gone")
      end
    end
  end
end

-- 「增益提醒」分頁顯示用：目前看著的增益（剩下時間由多到少）
function B.List()
  local out, now = {}, GetTime()
  for _, t in pairs(tracked) do out[#out + 1] = t end
  table.sort(out, function(a, b) return a.expires < b.expires end)
  local lines = {}
  for _, t in ipairs(out) do
    lines[#lines + 1] = ("%s（%s）：還剩 %s%s"):format(t.name, KIND[t.kind].label, clock(t.expires - now),
      (t.stacks and t.stacks > 1) and ("，" .. t.stacks .. " 層") or "")
  end
  return lines
end

function B.Init()
  buildWatch()
  ns.On("PLAYER_ENTERING_WORLD", function() ns.Try("buffs", B.Tick) end)
  ns.On("PLAYER_DEAD", function() tracked = {} end)          -- 死掉時增益一起消失，不算到期
  ns.On("PLAYER_REGEN_ENABLED", function() C_Timer.After(1, function() ns.Try("buffs", B.Tick) end) end)
  C_Timer.NewTicker(TICK, function() ns.Try("buffs", B.Tick) end)
end
ns.Register(B)

-- ---------------------------------------------------------------------------- 分頁
local function buildTab(p)
  local tip = ns.UI.Text(p, "GameFontHighlightSmall",
    "吃的東西、睡袋、藥劑和卷軸給的增益，快到期時提醒一次（畫面上方大字、聊天框、音效），到期時再提醒一次。只提醒你身上有過的增益，不會催你吃。", 430)
  tip:SetPoint("TOPLEFT", 0, 0)
  p.checks = {}
  local function check(y, x, label, key)
    local c = ns.UI.Check(p, label, function() return S()[key] end, function(v)
      S()[key] = v
      for _, c2 in ipairs(p.checks) do c2:Refresh() end
      ns.Try("buffs", B.Tick)
    end)
    c:SetPoint("TOPLEFT", x, y)
    p.checks[#p.checks + 1] = c
  end
  check(-48, 0, "增益快到期、到期時提醒", "buffRemind")
  check(-74, 20, "食物（進食充分等，剩 1 分鐘提醒）", "buffFood")
  check(-98, 20, "睡袋（充分休息，剩 5 分鐘提醒）", "buffRested")
  check(-122, 20, "藥劑和卷軸（剩 2 分鐘提醒）", "buffElixir")
  check(-146, 20, "提醒時播放音效", "buffSound")
  local test = ns.UI.Button(p, "試一下提醒", 110, 22, function() B.Alert("（試試看）進食充分 快到期了：還剩 59 秒", "soon") end)
  test:SetPoint("TOPLEFT", 0, -180)
  local head = ns.UI.Text(p, "GameFontNormal", ns.GOLD .. "現在身上看著的增益|r")
  head:SetPoint("TOPLEFT", 0, -218)
  p.list = ns.UI.Text(p, "GameFontHighlightSmall", "", 430)
  p.list:SetPoint("TOPLEFT", 0, -240)
  local note = ns.UI.Text(p, "GameFontDisableSmall",
    "戰鬥中、打首領時遊戲不讓插件讀增益，戰鬥中到期的會在打完後提醒。睡袋是「舒適的睡袋」：放好後在裡面躺一分鐘，得到「充分休息」（最多 3 層，2 小時）。", 430)
  note:SetPoint("TOPLEFT", 0, -400)
end

local function refreshTab(p)
  for _, c in ipairs(p.checks) do c:Refresh() end
  ns.Try("buffs", B.Tick)
  local lines = B.List()
  if ns.Restricted() then
    p.list:SetText("戰鬥中讀不到增益，打完再看。")
  elseif #lines == 0 then
    p.list:SetText("目前身上沒有食物、睡袋、藥劑或卷軸的增益。")
  else
    p.list:SetText(table.concat(lines, "\n"))
  end
end

ns.UI.AddTab("buffs", "增益提醒", buildTab, refreshTab)
