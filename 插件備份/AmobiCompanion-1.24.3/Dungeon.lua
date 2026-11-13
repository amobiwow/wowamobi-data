-- 阿莫比小幫手：副本小卡
--
-- 進副本（地城、團隊副本）時自動在畫面右邊顯示一張小卡：副本名稱、人數、進入等級、建議等級（分區副本每區列出）、
-- 首領出場順序（打完的打勾）、阿莫比掉落插件記到的掉落（有記錄的首領才列）。
-- 資料：Data\Dungeons.lua（網站副本資料庫和掉落記錄，tools\build_companion_data.py 轉的），用 GetInstanceInfo 的地圖編號查。
-- 打首領（ENCOUNTER_START）或進入戰鬥時自動收成一條標題列，不擋畫面；點標題列的「＋」展開，拖標題列移動，「×」這次先關掉。
-- 首領打勾：這次在副本裡收到 ENCOUNTER_END（成功），首領編號和網站資料一樣（DungeonEncounter）。

local _, ns = ...
local D = {}
ns.Dungeon = D
local DD = ns.DungeonData

local WIDTH = 250
local card, mapID, dismissed, killed, killedFor = nil, nil, {}, {}, nil

local KIND = { raid = "團隊副本", dungeon = "地城" }

local function levelText(rec)
  local parts = {}
  if rec.entry then parts[#parts + 1] = ("進入 %d 級"):format(rec.entry) end
  if rec.lo then
    parts[#parts + 1] = rec.lo == rec.hi and ("建議 %d 級"):format(rec.lo) or ("建議 %d–%d 級"):format(rec.lo, rec.hi)
  end
  return table.concat(parts, "‧")
end

local function pct(r)
  if r >= 0.995 then return "100%" end
  if r < 0.01 then return "不到 1%" end
  return ("%d%%"):format(math.floor(r * 100 + 0.5))
end

-- 小卡的內容（一行一行的文字），也給測試看
function D.Lines(id)
  local rec = DD.instances[id]
  if not rec then return nil end
  local lines = {}
  local sub = (KIND[rec.kind] or rec.kind) .. "‧" .. rec.players .. " 人" .. (rec.new and "‧永恆新副本" or "")
  lines[#lines + 1] = "|cffbbbbbb" .. sub .. "|r"
  local lv = levelText(rec)
  if lv ~= "" then
    local mine = UnitLevel("player") or 0
    local warn = (rec.entry and mine < rec.entry) and "  |cffff6060你的等級還不能進入|r" or ""
    lines[#lines + 1] = lv .. warn
  end
  for _, w in ipairs(rec.wings or {}) do
    lines[#lines + 1] = ("  |cffbbbbbb%s %d–%d|r"):format(w.name, w.lo, w.hi)
  end
  if rec.reset and rec.reset ~= "" and rec.kind == "raid" then lines[#lines + 1] = "|cffbbbbbb重置：" .. rec.reset .. "|r" end
  lines[#lines + 1] = " "
  lines[#lines + 1] = ns.GOLD .. "首領（出場順序）|r"
  local looted = false
  for i, b in ipairs(rec.bosses) do
    local done = killed[b.id] and "|cff60ff60√|r " or ""
    lines[#lines + 1] = ("%s%d. %s"):format(done, i, b.name)
    if b.items and #b.items > 0 then
      looted = true
      local shown = {}
      for k = 1, math.min(3, #b.items) do
        local it = b.items[k]
        shown[#shown + 1] = it.name .. " " .. pct(it.rate)
      end
      lines[#lines + 1] = "    |cffa0a0a0" .. table.concat(shown, "、") .. "|r"
    end
  end
  if looted then lines[#lines + 1] = "|cff808080掉落是玩家用阿莫比掉落插件記的，次數少時只供參考。|r" end
  lines[#lines + 1] = " "
  lines[#lines + 1] = "|cff808080更多：wowamobi.com/dungeons/" .. id .. "|r"
  return lines
end

local function paint()
  if not card or not mapID then return end
  local rec = DD.instances[mapID]
  card.title:SetText(ns.GOLD .. rec.name .. "|r")
  local collapsed = ns.db.settings.cardCollapsed
  card.toggle:SetText(collapsed and "+" or "-")
  if collapsed then
    card.body:Hide()
    card:SetHeight(26)
  else
    card.body:SetText(table.concat(D.Lines(mapID), "\n"))
    card.body:Show()
    local h = (card.body.GetStringHeight and card.body:GetStringHeight()) or 0
    card:SetHeight(math.max(60, h + 36))
  end
end

local function build()
  card = ns.UI.Panel(UIParent, WIDTH, 120, "MEDIUM")
  ns.UI.Place(card, "cardPos", "TOPRIGHT", UIParent, "TOPRIGHT", -24, -250)
  local bar = CreateFrame("Frame", nil, card)
  bar:SetPoint("TOPLEFT")
  bar:SetPoint("TOPRIGHT")
  bar:SetHeight(26)
  ns.UI.Movable(card, "cardPos", bar)
  card.title = ns.UI.Text(bar, "GameFontNormal", "", WIDTH - 158)   -- 右邊有四個按鈕，副本名字太長就截掉
  card.title:SetPoint("LEFT", 10, 0)
  if card.title.SetWordWrap then card.title:SetWordWrap(false) end
  local close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
  close:SetSize(22, 22)
  close:SetPoint("RIGHT", -2, 0)
  close:SetScript("OnClick", function()
    if mapID then dismissed[mapID] = true end
    card:Hide()
    ns.Print("副本小卡這次先關掉；打 /amobi 副本 可以再打開。")
  end)
  card.toggle = ns.UI.Button(bar, "-", 22, 20, function()
    ns.db.settings.cardCollapsed = not ns.db.settings.cardCollapsed
    paint()
  end)
  card.toggle:SetPoint("RIGHT", close, "LEFT", -2, 0)
  card.loot = ns.UI.Button(bar, "掉落", 44, 20, function()      -- 打開戰利品查詢的這個副本（1.4.0）
    if mapID then ns.LootBrowser.Open(mapID) end
  end)
  card.loot:SetPoint("RIGHT", card.toggle, "LEFT", -2, 0)
  card.quests = ns.UI.Button(bar, "任務", 44, 20, function()  -- 打開副本任務的這個副本（1.10.0，經典版參考）
    if mapID then ns.DQ.Open(mapID) end
  end)
  card.quests:SetPoint("RIGHT", card.loot, "LEFT", -2, 0)
  card.body = ns.UI.Text(card, "GameFontHighlightSmall", "", WIDTH - 20)
  card.body:SetPoint("TOPLEFT", 10, -30)
  card:Hide()
  D.card = card
end

function D.Show(id)
  if not card then build() end
  mapID = id
  paint()
  card:Show()
end

function D.Hide()
  if card then card:Hide() end
end

-- 現在在哪個副本：有資料的地城、團隊副本才顯示
local function where()
  local _, kind, _, _, _, _, _, id = GetInstanceInfo()
  if (kind == "party" or kind == "raid") and not ns.Secret(id) and DD.instances[id] then return id end
end

function D.Check()
  local id = where()
  if id and id ~= killedFor then killed, killedFor = {}, id end   -- 換了副本才清掉打勾（死掉跑屍回來不清）
  if not id then
    mapID = nil
    return D.Hide()
  end
  if not ns.db.settings.card or dismissed[id] then
    mapID = id
    return D.Hide()
  end
  D.Show(id)
end

function D.Toggle()
  local id = where()
  if not id then return ns.Print("你現在不在有資料的副本裡。副本小卡會在進地城、團隊副本時自動出現。") end
  if card and card:IsShown() then
    dismissed[id] = true
    D.Hide()
  else
    dismissed[id] = nil
    D.Show(id)
  end
end

local function fold()
  if ns.db.settings.cardFold and card and card:IsShown() and not ns.db.settings.cardCollapsed then
    ns.db.settings.cardCollapsed = true
    paint()
  end
end

function D.Init()
  ns.On("PLAYER_ENTERING_WORLD", function() C_Timer.After(1, function() ns.Try("card", D.Check) end) end)
  ns.On("ZONE_CHANGED_NEW_AREA", function() C_Timer.After(0.5, function() ns.Try("card", D.Check) end) end)
  ns.On("ENCOUNTER_START", fold)
  ns.On("PLAYER_REGEN_DISABLED", fold)
  ns.On("ENCOUNTER_END", function(enc, _, _, _, success)
    if ns.Secret(enc) or ns.Secret(success) then return end
    if (success == 1 or success == true) and mapID then
      killed[enc] = true
      paint()
    end
  end)
end
ns.Register(D)

-- ---------------------------------------------------------------------------- 分頁（設定和目前副本的預覽）
local function buildTab(p)
  local tip = ns.UI.Text(p, "GameFontHighlightSmall",
    "進地城、團隊副本時，畫面右邊會自動出現小卡：首領出場順序、進入等級、建議等級、我們記到的掉落。打首領時會自動收起來。", 430)
  tip:SetPoint("TOPLEFT", 0, 0)
  local c1 = ns.UI.Check(p, "進副本自動顯示小卡", function() return ns.db.settings.card end,
    function(v) ns.db.settings.card = v; D.Check() end)
  c1:SetPoint("TOPLEFT", 0, -44)
  local c2 = ns.UI.Check(p, "打首領、進入戰鬥時自動收起來", function() return ns.db.settings.cardFold end,
    function(v) ns.db.settings.cardFold = v end)
  c2:SetPoint("TOPLEFT", 0, -70)
  p.checks = { c1, c2 }
  p.now = ns.UI.Text(p, "GameFontHighlightSmall", "", 430)
  p.now:SetPoint("TOPLEFT", 0, -106)
  local show = ns.UI.Button(p, "顯示／關閉小卡", 130, 24, function() D.Toggle() end)
  show:SetPoint("TOPLEFT", 0, -150)
end

local function refreshTab(p)
  for _, c in ipairs(p.checks) do c:Refresh() end
  local id = where()
  local n = 0
  for _ in pairs(DD.instances) do n = n + 1 end
  p.now:SetText(id and ("你現在在「" .. DD.instances[id].name .. "」。") or
    ("插件裡有 %d 個副本的資料（永恆 %s）。"):format(n, DD.version or "?"))
end

ns.UI.AddTab("dungeon", "副本", buildTab, refreshTab)
