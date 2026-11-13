-- 阿莫比小幫手：戰利品查詢（像 AtlasLoot：選副本 → 首領 → 看會掉什麼）
--
-- 自己的一個大視窗（三欄：副本、首領、物品），也可以搜尋物品名稱。滑鼠指到物品顯示遊戲自己的物品說明框（GameTooltip:SetItemByID）。
-- 資料：
--   * 玩家回報的掉落：Data\Dungeons.lua（阿莫比掉落插件記的、網站彙整的；開服後才有），列在前面，寫幾次擊殺、掉落率
--   * 經典版參考：Data\Loot.lua（VMaNGOS，經典版 1.12，社群整理，GPL-2.0；不是永恆的資料，畫面上寫明），機率 1% 以上或藍色以上
-- 物品的部位、類型用 C_Item.GetItemInfoInstant（客戶端自己有的資料，不用等伺服器）；「只看裝備」＝武器和護甲。
-- 打開：「戰利品」分頁、副本小卡的「掉落」按鈕、/amobi 掉落（或 /amobi loot 熔火之心）。

local _, ns = ...
local L = {}
ns.LootBrowser = L
local DD, LD = ns.DungeonData, ns.LootData

local W, H = 780, 520
local ROW_H, ITEM_H = 24, 28
local QUALITY = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000", [6] = "e6cc80" }
local KIND = { raid = "團隊副本", dungeon = "地城" }

local win
local state = { kind = "dungeon", instance = nil, boss = nil, equipOnly = false, query = nil }

-- ---------------------------------------------------------------------------- 資料
local instList

-- 副本清單：照建議等級排（沒有的照進入等級）
function L.Instances(kind)
  if not instList then
    instList = {}
    for id, rec in pairs(DD.instances) do
      instList[#instList + 1] = { id = id, rec = rec, lv = rec.lo or rec.entry or 99 }
    end
    table.sort(instList, function(a, b)
      if a.lv ~= b.lv then return a.lv < b.lv end
      return a.rec.name < b.rec.name
    end)
  end
  local out = {}
  for _, e in ipairs(instList) do
    if not kind or e.rec.kind == kind then out[#out + 1] = e end
  end
  return out
end

local function info(id)
  local _, itemType, subType, equipLoc, _, classID = ns.Call(C_Item, "GetItemInfoInstant", id)
  local slot = (type(equipLoc) == "string" and equipLoc ~= "" and _G[equipLoc]) or nil
  local kind = subType or itemType
  local text = slot and kind and kind ~= slot and (kind .. "‧" .. slot) or slot or kind or ""
  return text, classID
end
L.ItemInfo = info

-- 一個首領的物品：{ id, name, q, icon, text（掉落率或次數）, src = "report"／"classic" }
function L.Items(bossRow, equipOnly)
  local out, seen = {}, {}
  local function add(e)
    if equipOnly then
      local _, classID = info(e.id)
      if classID ~= 2 and classID ~= 4 then return end
    end
    out[#out + 1] = e
    seen[e.id] = true
  end
  for _, it in ipairs(bossRow.items or {}) do       -- 玩家回報的
    local r = it.rate or 0
    add({ id = it.id, name = it.name, q = it.q or 1, icon = 0, src = "report",
          text = ("回報 %d 次‧%s"):format(it.n or 0, r >= 0.995 and "100%" or ("%d%%"):format(math.floor(r * 100 + 0.5))) })
  end
  local flat = LD.bosses[bossRow.id]
  if flat then
    for i = 1, #flat, 5 do
      local id = flat[i]
      if not seen[id] then
        local pm = flat[i + 3]
        add({ id = id, q = flat[i + 1], icon = flat[i + 2], name = flat[i + 4], src = "classic",
              text = pm >= 995 and "100%" or pm < 10 and "不到 1%" or ("%d%%"):format(math.floor(pm / 10 + 0.5)) })
      end
    end
  end
  return out
end

-- 搜尋物品名稱：{ 物品, 首領, 副本 }
function L.Search(query, equipOnly)
  query = strtrim(query or "")
  if query == "" then return {} end
  local out = {}
  for _, e in ipairs(L.Instances()) do
    for _, b in ipairs(e.rec.bosses) do
      for _, it in ipairs(L.Items(b, equipOnly)) do
        if it.name and it.name:find(query, 1, true) then
          out[#out + 1] = { item = it, boss = b, inst = e }
          if #out >= 300 then return out end
        end
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------------------- 一欄可以捲動的清單
local function list(parent, x, y, w, rowH, n, makeRow, fill)
  local o = { offset = 0, items = {}, rows = {}, n = n }
  local function scroll(_, delta)
    local max = math.max(0, #o.items - n)
    o.offset = math.max(0, math.min(max, o.offset - delta * 3))
    o:Refresh()
  end
  for i = 1, n do
    local r = makeRow(parent, w, rowH)
    r:SetPoint("TOPLEFT", x, y - (i - 1) * rowH)
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", scroll)
    o.rows[i] = r
  end
  local area = CreateFrame("Frame", nil, parent)
  area:SetPoint("TOPLEFT", x, y)
  area:SetSize(w, rowH * n)
  area:EnableMouseWheel(true)
  area:SetScript("OnMouseWheel", scroll)
  local up = ns.UI.Button(parent, "▲", 24, 18, function() scroll(nil, 1) end)
  up:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + w, y + 20)
  local down = ns.UI.Button(parent, "▼", 24, 18, function() scroll(nil, -1) end)
  down:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + w, y - rowH * n - 2)
  o.page = ns.UI.Text(parent, "GameFontDisableSmall", "")
  o.page:SetPoint("RIGHT", down, "LEFT", -6, 0)
  function o:Set(items, keep)
    self.items = items or {}
    if not keep then self.offset = 0 end
    self:Refresh()
  end
  function o:Refresh()
    for i, r in ipairs(self.rows) do
      local it = self.items[self.offset + i]
      if it then fill(r, it); r:Show() else r:Hide() end
    end
    local total = #self.items
    self.page:SetText(total > n and ("%d–%d／%d"):format(self.offset + 1, math.min(total, self.offset + n), total) or "")
  end
  o.Scroll = scroll
  return o
end
L.List = list            -- 副本任務（DungeonQuests.lua）也用這個清單

local function textRow(parent, w, h)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  b.text = ns.UI.Text(b, "GameFontHighlightSmall", "", w - 8)
  b.text:SetPoint("LEFT", 4, 0)
  b.hl = b:CreateTexture(nil, "BACKGROUND")
  b.hl:SetAllPoints()
  b.hl:SetColorTexture(0.91, 0.80, 0.53, 0.18)
  b.hl:Hide()
  b:SetScript("OnClick", function(self) if self.onPick then ns.Try("loot-pick", self.onPick, self) end end)
  return b
end

local function itemRow(parent, w, h)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(h - 4, h - 4)
  b.icon:SetPoint("LEFT", 2, 0)
  b.name = ns.UI.Text(b, "GameFontHighlightSmall", "", w - 110)
  b.name:SetPoint("TOPLEFT", h + 4, -2)
  b.sub = ns.UI.Text(b, "GameFontDisableSmall", "", w - 110)
  b.sub:SetPoint("TOPLEFT", h + 4, -14)
  b.rate = ns.UI.Text(b, "GameFontHighlightSmall", "")
  b.rate:SetPoint("RIGHT", -4, 0)
  b.rate:SetJustifyH("RIGHT")
  b:SetScript("OnEnter", function(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.itemID)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self) if self.onPick then ns.Try("loot-pick", self.onPick, self) end end)
  return b
end

-- ---------------------------------------------------------------------------- 視窗
local cols = {}
L.cols = cols   -- 三欄（測試也讀這裡）

local function fillItem(r, it)
  local e = it.item or it
  r.itemID = e.id
  if e.icon and e.icon > 0 then r.icon:SetTexture(e.icon) else r.icon:SetTexture(ns.Call(C_Item, "GetItemIconByID", e.id) or 134400) end
  r.name:SetText(("|cff%s%s|r"):format(QUALITY[e.q or 1] or "ffffff", e.name or ("物品 " .. e.id)))
  local slot = info(e.id)
  if it.boss then
    r.sub:SetText(it.boss.name .. "（" .. it.inst.rec.name .. "）" .. (slot ~= "" and ("　" .. slot) or ""))
  else
    r.sub:SetText(slot)
  end
  r.rate:SetText((e.src == "report" and "|cff60d060" or "|cffb7a98c") .. e.text .. "|r")
  r.onPick = it.boss and function() L.Open(it.inst.id, it.boss.id) end or nil
end

local function showItems()
  if state.query then
    local res = L.Search(state.query, state.equipOnly)
    win.itemHead:SetText(("搜尋「%s」：%d 件%s"):format(state.query, #res, #res >= 300 and "（只列前 300）" or ""))
    cols.items:Set(res)
    return
  end
  local inst = state.instance and DD.instances[state.instance]
  local boss
  for _, b in ipairs(inst and inst.bosses or {}) do
    if b.id == state.boss then boss = b end
  end
  if not boss then
    win.itemHead:SetText(inst and "選一個首領" or "")
    cols.items:Set({})
    return
  end
  local items = L.Items(boss, state.equipOnly)
  local reported = boss.looted and boss.looted > 0
  win.itemHead:SetText(ns.GOLD .. boss.name .. "|r" .. (reported and ("　|cff60d060玩家回報 %d 次擊殺|r"):format(boss.kills or 0) or "")
    .. (#items == 0 and "　|cff9d9d9d還沒有掉落資料|r" or ""))
  cols.items:Set(items)
end

local function showBosses()
  local inst = state.instance and DD.instances[state.instance]
  local rows = {}
  for i, b in ipairs(inst and inst.bosses or {}) do rows[#rows + 1] = { i = i, b = b } end
  cols.bosses:Set(rows)
  win.bossHead:SetText(inst and (ns.GOLD .. inst.name .. "|r") or "選一個副本")
end

local function showInstances(keep)
  cols.inst:Set(L.Instances(state.kind), keep)
  for _, b in ipairs(win.kindButtons) do b:SetAlpha(b.kind == state.kind and 1 or 0.55) end
end

local function build()
  win = ns.UI.Panel(UIParent, W, H, "DIALOG")
  ns.UI.Place(win, "lootPos", "CENTER", UIParent, "CENTER", 0, 30)
  local bar = CreateFrame("Frame", nil, win)
  bar:SetPoint("TOPLEFT")
  bar:SetPoint("TOPRIGHT")
  bar:SetHeight(32)
  ns.UI.Movable(win, "lootPos", bar)
  local title = ns.UI.Text(bar, "GameFontNormalLarge", ns.GOLD .. "阿莫比 戰利品查詢|r")
  title:SetPoint("LEFT", 14, -2)
  local close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() win:Hide() end)

  win.box = ns.UI.Edit(win, 180)
  win.box:SetPoint("TOPRIGHT", -150, -8)
  win.box:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    L.SearchFor(self:GetText())
  end)
  local find = ns.UI.Button(win, "搜尋物品", 80, 22, function() L.SearchFor(win.box:GetText()) end)
  find:SetPoint("LEFT", win.box, "RIGHT", 6, 0)

  win.kindButtons = {}
  local kx = 14
  for _, k in ipairs({ { "dungeon", "地城" }, { "raid", "團隊副本" } }) do
    local b = ns.UI.Button(win, k[2], 96, 22, function()
      state.kind = k[1]
      showInstances()
    end)
    b.kind = k[1]
    b:SetPoint("TOPLEFT", kx, -40)
    kx = kx + 100
    win.kindButtons[#win.kindButtons + 1] = b
  end

  cols.inst = list(win, 14, -86, 210, ROW_H, 15, textRow, function(r, e)
    local rec = e.rec
    local lv = rec.lo and (rec.lo == rec.hi and tostring(rec.lo) or (rec.lo .. "–" .. rec.hi)) or (rec.entry and ("進入 " .. rec.entry)) or ""
    r.text:SetText(rec.name .. (lv ~= "" and ("  |cff9d9d9d" .. lv .. "|r") or "") .. (rec.new and "  |cffe9cb88新|r" or ""))
    r.hl:SetShown(e.id == state.instance)
    r.onPick = function()
      state.instance, state.boss, state.query = e.id, nil, nil
      cols.inst:Refresh()
      showBosses()
      local first = DD.instances[e.id].bosses[1]
      if first then state.boss = first.id end
      cols.bosses:Refresh()
      showItems()
    end
  end)
  win.bossHead = ns.UI.Text(win, "GameFontHighlight", "", 180)
  win.bossHead:SetPoint("TOPLEFT", 240, -64)
  cols.bosses = list(win, 240, -86, 180, ROW_H, 15, textRow, function(r, e)
    local has = (LD.bosses[e.b.id] ~= nil) or (e.b.looted and e.b.looted > 0)
    r.text:SetText(("%d. %s%s"):format(e.i, e.b.name, has and "" or "  |cff9d9d9d沒有資料|r"))
    r.hl:SetShown(e.b.id == state.boss and not state.query)
    r.onPick = function()
      state.boss, state.query = e.b.id, nil
      cols.bosses:Refresh()
      showItems()
    end
  end)
  win.itemHead = ns.UI.Text(win, "GameFontHighlight", "", 330)
  win.itemHead:SetPoint("TOPLEFT", 436, -64)
  cols.items = list(win, 436, -86, 330, ITEM_H, 13, itemRow, fillItem)

  local eq = ns.UI.Check(win, "只看裝備（武器、護甲）", function() return state.equipOnly end, function(v)
    state.equipOnly = v
    showItems()
  end)
  eq:SetPoint("BOTTOMLEFT", 14, 40)
  win.eq = eq
  local note = ns.UI.Text(win, "GameFontDisableSmall",
    "|cff60d060綠字|r是玩家用阿莫比掉落插件記到的（開服後才有）；|cffb7a98c黃褐字|r是經典版 1.12 的參考掉落率（" .. LD.source .. "），不是永恆的資料。滑鼠指到物品看說明。", W - 28)
  note:SetPoint("BOTTOMLEFT", 14, 12)
  win:Hide()
  L.win = win
end

-- 打開：可以指定副本（地圖編號）和首領
function L.Open(instance, boss)
  if not win then build() end
  if instance and DD.instances[instance] then
    state.kind = DD.instances[instance].kind == "raid" and "raid" or "dungeon"
    state.instance, state.query = instance, nil
    state.boss = boss or (DD.instances[instance].bosses[1] or {}).id
  end
  win:Show()
  showInstances(true)
  showBosses()
  showItems()
end

function L.SearchFor(query)
  query = strtrim(query or "")
  if not win then build() end
  if query == "" then
    state.query = nil
  else
    state.query = query
    win.box:SetText(query)
  end
  win:Show()
  showInstances(true)
  showBosses()
  showItems()
end

function L.Toggle()
  if win and win:IsShown() then win:Hide() else L.Open() end
end

-- /amobi 掉落 [副本或物品名稱]：副本名稱就打開那個副本，否則當物品搜尋
function L.Slash(rest)
  rest = strtrim(rest or "")
  if rest == "" then return L.Open() end
  for _, e in ipairs(L.Instances()) do
    if e.rec.name == rest or e.rec.name:find(rest, 1, true) == 1 then return L.Open(e.id) end
  end
  L.SearchFor(rest)
end

-- ---------------------------------------------------------------------------- 分頁
local function buildTab(p)
  local tip = ns.UI.Text(p, "GameFontHighlightSmall",
    "像 AtlasLoot：選副本、首領，看會掉什麼；也可以搜尋物品名稱。遊戲檔裡沒有掉落表，先用經典版 1.12 的參考掉落率（不是永恆的），開服後換上玩家用阿莫比掉落插件記到的。", 430)
  tip:SetPoint("TOPLEFT", 0, 0)
  local open = ns.UI.Button(p, "打開戰利品查詢", 140, 26, function() L.Open() end)
  open:SetPoint("TOPLEFT", 0, -50)
  local box = ns.UI.Edit(p, 200)
  box:SetPoint("TOPLEFT", 6, -92)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); L.SearchFor(self:GetText()) end)
  local find = ns.UI.Button(p, "搜尋物品", 84, 22, function() L.SearchFor(box:GetText()) end)
  find:SetPoint("LEFT", box, "RIGHT", 8, 0)
  local hint = ns.UI.Text(p, "GameFontDisableSmall", "例如「熔岩」「火焰之心」。聊天框也可以打 /amobi 掉落 熔火之心。進副本時，副本小卡的「掉落」按鈕會直接打開那個副本。", 430)
  hint:SetPoint("TOPLEFT", 0, -122)
  local n, b = 0, 0
  for _ in pairs(DD.instances) do n = n + 1 end
  for _ in pairs(LD.bosses) do b = b + 1 end
  local count = ns.UI.Text(p, "GameFontHighlightSmall", ("插件裡有 %d 個副本，其中 %d 個首領有經典版參考掉落。"):format(n, b), 430)
  count:SetPoint("TOPLEFT", 0, -160)
end

ns.UI.AddTab("loot", "戰利品", buildTab)
