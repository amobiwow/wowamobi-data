-- 阿莫比小幫手：副本任務（1.10.0，「副本任務」分頁；玩家許願、老闆 10/26：「副本任務先用經典版參考做：小幫手加『副本任務』分頁
-- （照我的等級、陣營，按一下帶路），網站副本頁也放同一份，標清楚不是永恆的資料；開服後再用小幫手記永恆的真資料補上」）
--
-- 每個副本有哪些任務、幾級可以接、誰接、在哪裡接；按「帶路」用遊戲內建的導航點（Navigate.lua）帶你去接任務的人。
-- 資料 Data/DungeonQuests.lua 是經典版參考（VMaNGOS 社群整理的經典版 1.12 資料，GPL-2.0），不是永恆的資料：
-- 只收任務編號在永恆遊戲檔裡的；名字有台服譯名的寫中文，沒有的寫英文。永恆新地城沒有經典版資料。
-- 只列你的陣營、職業接得到的；你做過、身上有的用遊戲自己的任務紀錄看（C_QuestLog）。不會替你接任務、不會移動。

local _, ns = ...
local DQ = {}
ns.DQ = DQ

local DATA = ns.DungeonQuests or { dungeons = {}, quests = {}, noData = {} }
local SIDE_ZH = { Alliance = "聯盟", Horde = "部落" }
local CLASS_ZH = { WARRIOR = "戰士", PALADIN = "聖騎士", HUNTER = "獵人", ROGUE = "盜賊", PRIEST = "牧師", SHAMAN = "薩滿",
                   MAGE = "法師", WARLOCK = "術士", DRUID = "德魯伊" }
local state = { map = nil }

local function S() return ns.db.settings end
local function myLevel()
  local l = UnitLevel("player")
  return type(l) == "number" and not ns.Secret(l) and l or 1
end
local function myFaction() return UnitFactionGroup("player") end
local function myClass() local _, t = UnitClass("player"); return t end

-- 遊戲自己的任務紀錄：做過 done、身上有 active
function DQ.Status(id)
  if C_QuestLog then
    if C_QuestLog.IsQuestFlaggedCompleted and ns.Call(C_QuestLog, "IsQuestFlaggedCompleted", id) == true then return "done" end
    if C_QuestLog.IsOnQuest and ns.Call(C_QuestLog, "IsOnQuest", id) == true then return "active" end
  end
  if GetQuestLogIndexByID then
    local ok, i = pcall(GetQuestLogIndexByID, id)
    if ok and type(i) == "number" and not ns.Secret(i) and i > 0 then return "active" end
  end
end

-- 你的陣營、職業接得到嗎
function DQ.ForMe(q)
  if q.side and q.side ~= myFaction() then return false end
  if q.cls then
    local mine = myClass()
    for _, c in ipairs(q.cls) do if c == mine then return true end end
    return false
  end
  return true
end

-- 一個副本的任務（接得到的）：{ id, q, status, can, why }
function DQ.List(map, onlyNow)
  local out, lv = {}, myLevel()
  for _, d in ipairs(DATA.dungeons) do
    if d.map == map then
      for _, id in ipairs(d.quests) do
        local q = DATA.quests[id]
        if q and DQ.ForMe(q) then
          local st = DQ.Status(id)
          local prevDone = not q.prev or DQ.Status(q.prev) == "done"
          local can = not st and q.min <= lv and prevDone
          local why = st == "done" and "做過了" or st == "active" and "身上有" or q.min > lv and ("要 " .. q.min .. " 級")
            or not prevDone and ("要先做「" .. ((DATA.quests[q.prev] or {}).t or q.prevT or "前一個任務") .. "」") or nil
          if not onlyNow or can then out[#out + 1] = { id = id, q = q, status = st, can = can, why = why } end
        end
      end
    end
  end
  return out
end

function DQ.Dungeons()
  local out = {}
  for _, d in ipairs(DATA.dungeons) do
    out[#out + 1] = { map = d.map, name = d.name, kind = d.kind, levels = d.levels, n = #DQ.List(d.map), now = #DQ.List(d.map, true) }
  end
  return out
end

-- 一開始選哪個副本：在副本裡就是那個；不然是建議等級包含你等級的第一個
function DQ.Pick()
  local _, kind, _, _, _, _, _, inst = GetInstanceInfo()
  if kind ~= "none" and not ns.Secret(inst) then
    for _, d in ipairs(DATA.dungeons) do if d.map == inst then return inst end end
  end
  local lv = myLevel()
  for _, d in ipairs(DATA.dungeons) do
    local l = d.levels
    if l and l[1] and lv >= l[1] - 2 and lv <= (l[2] or l[1]) + 2 and #DQ.List(d.map) > 0 then return d.map end
  end
  return DATA.dungeons[1] and DATA.dungeons[1].map
end

-- 帶路到接任務的人
function DQ.Go(id)
  local q = DATA.quests[id]
  local g = q and q.g
  if not g then return false, "這個任務經典版資料沒有寫誰接。" end
  if g.k == "item" then return false, "這個任務是撿到「" .. g.n .. "」開始的，不用找人接。" end
  if not g.nav then
    return false, g.inside and ("接任務的「" .. g.n .. "」在" .. (g.where or "副本") .. "裡面，進去才找得到。")
      or ("「" .. g.n .. "」的位置這張地圖小幫手沒有資料。")
  end
  return ns.Navigate.Go(g.nav[1], g.nav[2], g.nav[3], g.n)
end

-- ---------------------------------------------------------------------------- 分頁
local function who(p)
  if not p then return "（經典版資料沒有寫）" end
  local kind = p.k == "obj" and "（物品）" or ""
  if p.k == "item" then return "撿到「" .. p.n .. "」開始" end
  return p.n .. kind .. (p.where and p.where ~= "" and ("，" .. p.where) or "")
end

local function dungeonRow(parent, w, h)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  b.text = ns.UI.Text(b, "GameFontHighlightSmall", "", w - 6)
  b.text:SetPoint("LEFT", 3, 0)
  if b.text.SetWordWrap then b.text:SetWordWrap(false) end
  b.hl = b:CreateTexture(nil, "BACKGROUND")
  b.hl:SetAllPoints()
  b.hl:SetColorTexture(0.91, 0.80, 0.53, 0.18)
  b.hl:Hide()
  b:SetScript("OnClick", function(self)
    if self.map then state.map = self.map; ns.UI.Refresh("dquests") end
  end)
  return b
end

local function fillDungeon(b, d)
  b.map = d.map
  local lv = d.levels and d.levels[1] and (" |cff9d9d9d" .. d.levels[1] .. (d.levels[2] and d.levels[2] ~= d.levels[1] and ("–" .. d.levels[2]) or "") .. "|r") or ""
  b.text:SetText((d.now > 0 and "|cff60d060" or d.n > 0 and "|cffffffff" or "|cff808080") .. d.name .. "|r" .. lv)
  if d.map == state.map then b.hl:Show() else b.hl:Hide() end
end

local function questRow(parent, w, h)
  local b = CreateFrame("Frame", nil, parent)
  b:SetSize(w, h)
  b.title = ns.UI.Text(b, "GameFontHighlightSmall", "", w - 54)
  b.title:SetPoint("TOPLEFT", 2, -2)
  if b.title.SetWordWrap then b.title:SetWordWrap(false) end
  b.sub = ns.UI.Text(b, "GameFontDisableSmall", "", w - 54)
  b.sub:SetPoint("TOPLEFT", 2, -16)
  if b.sub.SetWordWrap then b.sub:SetWordWrap(false) end
  b.go = ns.UI.Button(b, "帶路", 46, 20, function(self)
    local row = self.row
    if row and row.id then
      local _, msg = DQ.Go(row.id)
      DQ.page.msg:SetText(msg or "")
    end
  end)
  b.go:SetPoint("RIGHT", -2, 0)
  b.go.row = b
  return b
end

local function fillQuest(b, it)
  local q = it.q
  b.id = it.id
  local color = it.status == "done" and "808080" or it.status == "active" and "ffd040" or it.can and "60d060" or "ff7040"
  local tags = {}
  if q.side then tags[#tags + 1] = SIDE_ZH[q.side] end
  if q.cls then
    local names = {}
    for _, c in ipairs(q.cls) do names[#names + 1] = CLASS_ZH[c] or c end
    tags[#tags + 1] = table.concat(names, "、")
  end
  b.title:SetText(("|cff%s%d 級|r %s%s%s"):format(color, q.min, q.t, q.en and " |cff9d9d9d（英文）|r" or "",
    #tags > 0 and (" |cff9d9d9d" .. table.concat(tags, " ") .. "|r") or ""))
  b.sub:SetText("接：" .. who(q.g) .. (it.why and ("  |cffff9a40" .. it.why .. "|r") or ""))
  if q.g and q.g.nav then b.go:Show() else b.go:Hide() end
end

local function build(p)
  DQ.page = p
  local note = ns.UI.Text(p, "GameFontDisableSmall",
    "經典版參考（VMaNGOS 社群整理的經典版 1.12 資料），不是永恆的資料：永恆可能改過任務、等級和接任務的人。" ..
    "只列你的陣營、職業接得到的；綠色是現在就能接的。開服後小幫手會記永恆的真資料補上。", 430)
  note:SetPoint("TOPLEFT", 0, 0)
  p.only = ns.UI.Check(p, "只列我現在能接的（等級夠、還沒做、前置做完）", function() return S().dqOnlyNow end, function(v)
    S().dqOnlyNow = v
    ns.UI.Refresh("dquests")
  end)
  p.only:SetPoint("TOPLEFT", -4, -34)
  p.dlist = ns.LootBrowser.List(p, 0, -84, 126, 20, 25, dungeonRow, fillDungeon)
  p.qlist = ns.LootBrowser.List(p, 134, -84, 298, 36, 14, questRow, fillQuest)
  p.head = ns.UI.Text(p, "GameFontNormal", "")
  p.head:SetPoint("TOPLEFT", 134, -62)
  p.msg = ns.UI.Text(p, "GameFontHighlightSmall", "", 430)
  p.msg:SetPoint("TOPLEFT", 0, -600)
end

local function refresh(p)
  p.only:Refresh()
  state.map = state.map or DQ.Pick()
  p.dlist:Set(DQ.Dungeons(), true)
  local list = DQ.List(state.map, S().dqOnlyNow)
  p.qlist:Set(list)
  local name
  for _, d in ipairs(DATA.dungeons) do if d.map == state.map then name = d.name end end
  p.head:SetText(ns.GOLD .. (name or "") .. "|r" .. (name and ("  " .. #list .. " 個任務") or ""))
  if name and #list == 0 then
    p.msg:SetText(S().dqOnlyNow and "這個副本現在沒有你能接的任務（把上面的勾拿掉看全部）。" or "這個副本沒有你的陣營、職業接得到的任務。")
  elseif #(DATA.noData or {}) > 0 and p.msg:GetText() == "" then
    p.msg:SetText("|cff9d9d9d永恆新地城（" .. table.concat(DATA.noData, "、") .. "）沒有經典版資料，開服後再補。|r")
  end
end

-- 打開這個分頁，選這個副本（副本小卡的「任務」按鈕、/amobi 副本任務 名字）
function DQ.Open(map)
  if map then state.map = map end
  ns.UI.Open("dquests")
end

function DQ.Slash(rest)
  rest = strtrim(rest or "")
  if rest ~= "" then
    for _, d in ipairs(DATA.dungeons) do
      if d.name == rest or d.name:find(rest, 1, true) then return DQ.Open(d.map) end
    end
    ns.Print("找不到「" .. rest .. "」：副本名字打對了嗎？（永恆新地城沒有資料）")
  end
  DQ.Open()
end

ns.UI.AddTab("dquests", "副本任務", build, refresh)
