-- 阿莫比小幫手：任務輔助（「任務」分頁）
--   帶路到最近的任務：任務日誌裡每個任務的距離（C_QuestLog.GetDistanceSqToQuest），最近的那個交給遊戲內建的導航
--     （C_SuperTrack.SetSuperTrackedQuestID：畫面上的箭頭帶你到任務目標或交任務的地方）。可以選「自動」：
--     完成目標、交了任務、接了新任務時，自動換到最近的
--   任務怪標記：名條上方一個黃色「!」，這隻怪和你身上的任務有關（C_QuestLog.UnitIsRelatedToActiveQuest）；
--     副本裡遊戲不讓插件在名條加東西，就不標
--   自動接任務、自動交任務（玩家打勾才開；按住 Shift 就不自動）：做的是暴雪任務視窗自己的按鈕做的事
--     （AcceptQuest、CompleteQuest、GetQuestReward；Blizzard_UIPanels_Game/Mainline/QuestFrame.lua），
--     和 NPC 對話時（GOSSIP_SHOW、QUEST_GREETING）也自動選可以接、可以交的任務。
--     有好幾個獎勵要選的、交任務要付錢的不自動，留給玩家自己按
-- 地圖上「哪裡可以接任務」的驚嘆號要有任務資料庫，遊戲檔沒有，先不做。

local _, ns = ...
local Q = {}
ns.Quest = Q

local LIST_N = 10
local AUTO_GAP = 2         -- 秒：自動帶路最快多久換一次（任務日誌更新很頻繁）

local function S() return ns.db.settings end

-- ---------------------------------------------------------------------------- 任務日誌、距離
-- { id, title, ready（可以交了）, d（碼，nil＝不在這塊大陸） }，照距離排（可以交的、在這塊大陸的在前面）
function Q.List()
  local api = C_QuestLog
  local out = {}
  local n = ns.Call(api, "GetNumQuestLogEntries") or 0
  if ns.Secret(n) then return out end
  for i = 1, n do
    local info = ns.Call(api, "GetInfo", i)
    if type(info) == "table" and not ns.Secret(info) and not info.isHeader and not info.isHidden and info.questID then
      local id = info.questID
      local dsq, onContinent = ns.Call(api, "GetDistanceSqToQuest", id)
      local d = (type(dsq) == "number" and not ns.Secret(dsq) and onContinent == true) and math.sqrt(dsq) or nil
      local ready = ns.Call(api, "ReadyForTurnIn", id) == true or ns.Call(api, "IsComplete", id) == true
      out[#out + 1] = { id = id, title = info.title or ns.Call(api, "GetTitleForQuestID", id) or ("任務 " .. id), ready = ready, d = d }
    end
  end
  table.sort(out, function(a, b)
    if (a.d ~= nil) ~= (b.d ~= nil) then return a.d ~= nil end
    if a.d and b.d and a.d ~= b.d then return a.d < b.d end
    return a.title < b.title
  end)
  return out
end

function Q.Track(q)
  if not (C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID) then return false, "這個遊戲版本沒有任務導航。" end
  ns.Call(C_SuperTrack, "SetSuperTrackedQuestID", q.id)
  return true, ("帶路到任務「%s」%s%s，畫面上會出現箭頭。"):format(q.title, q.ready and "（可以交了）" or "",
    q.d and ("，約 %d 碼"):format(math.floor(q.d + 0.5)) or "")
end

-- 帶路到最近的任務；回傳 true, 訊息 或 false, 原因
function Q.GoNearest()
  local list = Q.List()
  if #list == 0 then return false, "任務日誌裡沒有任務。" end
  local q = list[1]
  if not q.d then return false, "身上的任務都不在這塊大陸（或遊戲算不出距離）。" end
  return Q.Track(q)
end

local lastAuto = 0
local function autoNearest()
  if not S().questNearest or ns.Restricted() then return end
  local now = GetTime()
  if now - lastAuto < AUTO_GAP then return end
  lastAuto = now
  local list = Q.List()
  local q = list[1]
  if q and q.d then
    local cur = ns.Call(C_SuperTrack, "GetSuperTrackedQuestID")
    if cur ~= q.id then ns.Call(C_SuperTrack, "SetSuperTrackedQuestID", q.id) end
  end
end
Q.AutoNearest = autoNearest

-- ---------------------------------------------------------------------------- 名條的任務怪標記
local marks, pool = {}, {}

local function plateFor(unit)
  local plate = ns.Call(C_NamePlate, "GetNamePlateForUnit", unit, false)
  if not plate then return nil end
  local okF, forbidden = pcall(plate.IsForbidden, plate)
  if not okF or forbidden then return nil end
  return plate
end

local function related(unit)
  local v = ns.Call(C_QuestLog, "UnitIsRelatedToActiveQuest", unit)
  return v == true and not ns.Secret(v)
end

local function unmark(unit)
  local f = marks[unit]
  if not f then return end
  marks[unit] = nil
  f:Hide()
  f:ClearAllPoints()
  f:SetParent(UIParent)
  table.insert(pool, f)
end

function Q.Mark(unit)
  if type(unit) ~= "string" then return end
  if not (S().questPlates and related(unit)) then return unmark(unit) end
  local plate = plateFor(unit)
  if not plate then return unmark(unit) end
  local f = marks[unit] or table.remove(pool)
  if not f then
    f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(20, 20)
    f.text = ns.UI.Text(f, "GameFontNormalLarge", "|cffffd100!|r")
    f.text:SetPoint("CENTER")
    f.text:SetJustifyH("CENTER")
  end
  f:SetParent(plate)
  f:ClearAllPoints()
  f:SetPoint("BOTTOM", plate, "TOP", 0, 2)
  f:Show()
  marks[unit] = f
end
Q.marks = marks

function Q.RefreshMarks()
  for unit in pairs(marks) do Q.Mark(unit) end
  for i = 1, 40 do
    local unit = "nameplate" .. i
    if UnitExists(unit) then Q.Mark(unit) end
  end
end

-- ---------------------------------------------------------------------------- 自動接、交任務
local function autoOK()
  return S().questAuto and not IsShiftKeyDown() and not ns.Restricted()
end
Q.counts = { accepted = 0, completed = 0, rewarded = 0 }

local function onDetail()
  if not autoOK() or not AcceptQuest then return end
  if QuestGetAutoAccept and QuestGetAutoAccept() then return end   -- 遊戲自己已經接了
  AcceptQuest()
  Q.counts.accepted = Q.counts.accepted + 1
end

local function onProgress()
  if not autoOK() or not CompleteQuest then return end
  if IsQuestCompletable and IsQuestCompletable() then
    CompleteQuest()
    Q.counts.completed = Q.counts.completed + 1
  end
end

local function onComplete()
  if not autoOK() or not GetQuestReward then return end
  local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
  if ns.Secret(choices) or choices > 1 then return end            -- 要選獎勵的留給玩家
  local money = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
  if ns.Secret(money) or money > 0 then return end                -- 交任務要付錢的不自動
  GetQuestReward(choices == 1 and 1 or 0)
  Q.counts.rewarded = Q.counts.rewarded + 1
end

local function onGossip()
  if not autoOK() then return end
  local api = C_GossipInfo
  for _, q in ipairs(ns.Call(api, "GetActiveQuests") or {}) do
    if q.isComplete and q.questID then return ns.Call(api, "SelectActiveQuest", q.questID) end
  end
  for _, q in ipairs(ns.Call(api, "GetAvailableQuests") or {}) do
    if q.questID then return ns.Call(api, "SelectAvailableQuest", q.questID) end
  end
end

local function onGreeting()
  if not autoOK() or not (GetActiveTitle and SelectActiveQuest and SelectAvailableQuest) then return end
  for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
    local _, complete = GetActiveTitle(i)
    if complete then return SelectActiveQuest(i) end
  end
  if (GetNumAvailableQuests and GetNumAvailableQuests() or 0) > 0 then SelectAvailableQuest(1) end
end

function Q.Init()
  ns.On("NAME_PLATE_UNIT_ADDED", function(unit) Q.Mark(unit) end)
  ns.On("NAME_PLATE_UNIT_REMOVED", unmark)
  ns.On("UNIT_QUEST_LOG_CHANGED", function() Q.RefreshMarks() end)
  ns.On("QUEST_LOG_UPDATE", function()
    Q.RefreshMarks()
    autoNearest()
  end)
  ns.On("QUEST_ACCEPTED", function() lastAuto = 0; C_Timer.After(0.5, function() ns.Try("quest-auto", autoNearest) end) end)
  ns.On("QUEST_TURNED_IN", function() lastAuto = 0; C_Timer.After(0.5, function() ns.Try("quest-auto", autoNearest) end) end)
  ns.On("QUEST_DETAIL", onDetail)
  ns.On("QUEST_PROGRESS", onProgress)
  ns.On("QUEST_COMPLETE", onComplete)
  ns.On("GOSSIP_SHOW", onGossip)
  ns.On("QUEST_GREETING", onGreeting)
end
ns.Register(Q)

-- ---------------------------------------------------------------------------- 分頁
local page = {}

local function say(msg, ok)
  if page.status then page.status:SetText((ok == false and "|cffff6060" or "") .. (msg or "") .. (ok == false and "|r" or "")) end
end

local function showList()
  local list = Q.List()
  for i, row in ipairs(page.rows) do
    local q = list[i]
    if q then
      row.text:SetText(q.title .. (q.ready and "  |cff60d060可以交了|r" or ""))
      row.dist:SetText(q.d and ("約 %d 碼"):format(math.floor(q.d + 0.5)) or "|cff9d9d9d不在這塊大陸|r")
      row.go.quest = q
      row:Show()
    else
      row:Hide()
    end
  end
  page.empty:SetText(#list == 0 and "任務日誌裡沒有任務。" or "")
end

local function build(p)
  local intro = ns.UI.Text(p, "GameFontHighlightSmall",
    "遊戲本來就會在地圖上畫任務範圍、在畫面右邊追蹤任務。小幫手再幫你：帶路到最近的任務、標出任務怪、自動接任務和交任務。", 430)
  intro:SetPoint("TOPLEFT", 0, 0)
  local go = ns.UI.Button(p, "帶我去最近的任務", 150, 26, function()
    local ok, msg = Q.GoNearest()
    say(msg, ok)
  end)
  go:SetPoint("TOPLEFT", 0, -38)
  page.checks = {}
  local function check(label, key, y, after)
    local c = ns.UI.Check(p, label, function() return S()[key] end, function(v)
      S()[key] = v
      if after then after(v) end
      for _, x in ipairs(page.checks) do x:Refresh() end
    end)
    c:SetPoint("TOPLEFT", 0, y)
    page.checks[#page.checks + 1] = c
    return c
  end
  check("自動帶路到最近的任務（完成目標、交任務、接新任務時換）", "questNearest", -72, function(v) if v then lastAuto = 0; autoNearest() end end)
  check("名條上標出任務怪（黃色 !）", "questPlates", -96, function() Q.RefreshMarks() end)
  check("自動接任務、自動交任務", "questAuto", -120)
  local autoNote = ns.UI.Text(p, "GameFontDisableSmall",
    "按住 Shift 和 NPC 說話就不自動。有好幾個獎勵要選的、交任務要付錢的不會自動，留給你自己按。", 400)
  autoNote:SetPoint("TOPLEFT", 28, -144)

  local h = ns.UI.Text(p, "GameFontNormal", "身上的任務（近的在前面）")
  h:SetPoint("TOPLEFT", 0, -180)
  page.rows = {}
  for i = 1, LIST_N do
    local row = CreateFrame("Frame", nil, p)
    row:SetSize(430, 24)
    row:SetPoint("TOPLEFT", 0, -200 - (i - 1) * 26)
    row.text = ns.UI.Text(row, "GameFontHighlightSmall", "", 270)
    row.text:SetPoint("LEFT", 0, 0)
    row.dist = ns.UI.Text(row, "GameFontDisableSmall", "")
    row.dist:SetPoint("RIGHT", -62, 0)
    row.go = ns.UI.Button(row, "帶路", 56, 20, function(self)
      if self.quest then say(select(2, Q.Track(self.quest))) end
    end)
    row.go:SetPoint("RIGHT", 0, 0)
    row:Hide()
    page.rows[i] = row
  end
  page.empty = ns.UI.Text(p, "GameFontDisableSmall", "", 430)
  page.empty:SetPoint("TOPLEFT", 0, -204)
  local mapNote = ns.UI.Text(p, "GameFontDisableSmall",
    "地圖上「哪裡可以接任務」的驚嘆號要有任務資料庫，遊戲檔裡沒有，等開服後再看能不能做。", 430)
  mapNote:SetPoint("TOPLEFT", 0, -200 - LIST_N * 26 - 4)
  page.status = ns.UI.Text(p, "GameFontHighlightSmall", "", 430)
  page.status:SetPoint("TOPLEFT", 0, -200 - LIST_N * 26 - 30)
  Q.page = page
end

local function refresh()
  for _, c in ipairs(page.checks) do c:Refresh() end
  showList()
end

ns.UI.AddTab("quest", "任務", build, refresh)
