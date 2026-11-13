-- 阿莫比小幫手：功能總覽（1.12.0，第一個分頁；老闆 10/31 選企劃的 A 版：功能總覽-UI企劃.md、功能總覽示意圖\）
--
-- LINE 群玩家：「阿莫比ui會參考其他ui設置統整介面讓玩家選擇需要哪些就使用哪些ui功能嗎？」「讓玩家自行選擇需要的ui不會讓畫面太亂」。
-- 小幫手所有功能排成 31 格（24 個開關、7 個工具），打勾馬上生效（叫各功能自己分頁的勾同一個套用函式，不用重新載入；
-- 傷害字型遊戲本來就要回角色選擇畫面才換）。上面搜尋、分類、四個方案，下面全部開／全部關；點一格，說明區寫這個功能在做什麼。
-- 方案和全部開／全部關不動「分享資料」三格（分享是玩家自己選的）、傷害字型和血條美化；自動接交任務每個方案都關（會替你按接受）。
-- 只用遊戲內建的零件：紅色按鈕、勾選框、輸入框、技能和物品圖示。只改小幫手自己的設定，不碰遊戲的框架。

local _, ns = ...
local O = {}
ns.Overview = O

local ICON = "Interface\\Icons\\"
local COLS, ROWS, TW, TH, GAP = 3, 11, 140, 26, 3
local CATS = { "全部", "戰鬥", "副本", "任務地圖", "介面", "PvP", "分享資料" }

local function S() return ns.db.settings end

-- 一般的開關：設定值 true/false，改了叫 apply 馬上套用
local function flag(key, apply)
  return function() return S()[key] and true or false end,
         function(v) S()[key] = v; if apply then ns.Try("overview:" .. key, apply, v) end end
end

-- 預設開、存成 false 才算關的（分享資料）
local function share(key)
  return function() return S()[key] ~= false end,
         function(v) ns.Share.SetShare(key, v) end
end

-- 幾種模式的（目標血量數字、打完檢討）：關＝off，開＝上次開著的模式
local function mode(key, off, default, apply)
  return function() return S()[key] ~= nil and S()[key] ~= off end,
         function(v)
           local s = S()
           if v then
             s[key] = s[key .. "On"] or default
           else
             if s[key] ~= off then s[key .. "On"] = s[key] end
             s[key] = off
           end
           if apply then ns.Try("overview:" .. key, apply) end
         end
end

-- PvP 警報的三格：打開任何一格就把 PvP 警報整個打開
local function pvp(key)
  return function() return S().pvpAlert ~= false and S()[key] and true or false end,
         function(v)
           S()[key] = v
           if v then S().pvpAlert = true end
           ns.PvPAlert.RefreshCds()
           ns.PvPAlert.RefreshNear()
         end
end

local function tab(key) return function() ns.UI.Open(key) end end

-- id、名稱、分類、圖示、說明、示意的一句、設定在哪個分頁、get、set（工具：open）
O.FEATURES = {
  { id = "range", name = "目標距離", cat = "戰鬥", icon = "INV_Misc_Spyglass_02", tab = "combat", demo = "約 8～20 碼",
    desc = "畫面中間偏下顯示和目標的距離。遊戲不給確切距離，用你的技能和物品的射程夾出來。",
    flag("range", function() ns.Assist.UpdateTarget() end) },
  { id = "dps", name = "戰鬥中 DPS", cat = "戰鬥", icon = "Ability_DualWield", tab = "combat", demo = "DPS 1,234",
    desc = "戰鬥中在距離下面顯示你的每秒傷害（或治療）和戰鬥時間，用暴雪傷害統計的資料。",
    flag("dps", function() ns.Assist.EnsureMeter(true); ns.Assist.ShowDps() end) },
  { id = "cd", name = "冷卻數字", cat = "戰鬥", icon = "INV_Misc_PocketWatch_01", tab = "combat", demo = "12",
    desc = "快捷列的冷卻倒數數字放大，快好了變紅。",
    flag("cdText", function() ns.Assist.StyleCooldowns() end) },
  { id = "health", name = "目標血量數字", cat = "戰鬥", icon = "INV_Potion_51", tab = "combat", demo = "8,420  70%",
    desc = "目標頭像的血條上顯示血量數字和百分比（遊戲內建的狀態文字，自己的頭像也會一起顯示）。",
    mode("healthMode", "off", "both", function() ns.Assist.ApplyHealthMode() end) },
  { id = "plate", name = "名條血量", cat = "戰鬥", icon = "Spell_Holy_Renew", tab = "combat", demo = "65%",
    desc = "敵人名條上顯示血量百分比（副本裡的名條遊戲不讓插件加）。",
    flag("plateHealth", function() ns.Assist.RefreshPlates() end) },

  { id = "card", name = "副本小卡", cat = "副本", icon = "INV_Misc_Map_01", tab = "dungeon", demo = "首領 1／6",
    desc = "進地城、團隊副本時畫面右邊出現小卡：首領出場順序、進入和建議等級、記到的掉落。",
    flag("card", function() ns.Dungeon.Check() end) },
  { id = "review", name = "打完檢討", cat = "副本", icon = "INV_Scroll_03", tab = "review", demo = "第 2 名",
    desc = "打完首領跳出這場的輸出、治療摘要：打多久、每秒多少、隊上第幾名、打最多的技能。",
    mode("review", "off", "boss") },
  { id = "threat", name = "我的仇恨", cat = "副本", icon = "Ability_Warrior_Sunder", tab = "boss", demo = "仇恨 82%",
    desc = "組隊打怪時在距離、DPS 下面顯示你的仇恨百分比。",
    flag("threat", function() ns.Assist.ShowThreat() end) },
  { id = "boss", name = "首領提醒設定", cat = "副本", icon = "INV_Misc_Head_Dragon_01", tool = tab("boss"), tab = "boss", demo = "首領警告",
    desc = "一鍵打開、調好暴雪內建的首領時間軸和首領警告。" },
  { id = "pull", name = "開怪倒數", cat = "副本", icon = "INV_Misc_PocketWatch_02", tool = tab("boss"), tab = "boss", demo = "10",
    desc = "遊戲內建的開怪倒數，隊伍裡每個人畫面上都會出現；也可以打 /amobi pull 10。" },
  { id = "combat", name = "戰鬥畫面設定", cat = "副本", icon = "Trade_Engineering", tool = tab("combat"), tab = "combat", demo = "一鍵擺好",
    desc = "把暴雪的冷卻監控、首領時間軸、傷害統計打開，擺到適合你職業的位置。" },

  { id = "coords", name = "小地圖座標", cat = "任務地圖", icon = "INV_Misc_Map02", tab = "nav", demo = "52.3, 47.1",
    desc = "小地圖下面顯示座標和這一區的等級。",
    flag("coords", function() ns.Navigate.ShowCoords() end) },
  { id = "questgo", name = "自動帶路任務", cat = "任務地圖", icon = "Ability_Tracking", tab = "quest", demo = "120 碼",
    desc = "完成目標、交任務、接新任務時，自動用遊戲的箭頭帶你去最近的任務。",
    flag("questNearest", function(v) if v then ns.Quest.AutoNearest() end end) },
  { id = "questmark", name = "名條任務怪", cat = "任務地圖", icon = "INV_Misc_QuestionMark", tab = "quest", demo = "!",
    desc = "任務要打的怪，名條上標黃色的「!」。",
    flag("questPlates", function() ns.Quest.RefreshMarks() end) },
  { id = "questauto", name = "自動接交任務", cat = "任務地圖", icon = "INV_Letter_15", tab = "quest", demo = "自動接受",
    desc = "跟 NPC 說話時自動接任務、交任務。按住 Shift 不自動；要選獎勵、要付錢的留給你。",
    flag("questAuto") },
  { id = "nav", name = "地圖導航", cat = "任務地圖", icon = "INV_Misc_Spyglass_03", tool = tab("nav"), tab = "nav", demo = "去 52 47",
    desc = "用遊戲的箭頭帶你去最近的飛行點、旅店、副本入口、銀行，或打座標。" },
  { id = "dquests", name = "副本任務", cat = "任務地圖", icon = "INV_Misc_Note_01", tool = tab("dquests"), tab = "dquests", demo = "18 級可接",
    desc = "每個副本有哪些任務、幾級可以接、誰接，按「帶路」帶你去（經典版參考）。" },

  { id = "itemuse", name = "物品中文用途", cat = "介面", icon = "INV_Misc_Book_09", tab = "utility", demo = "裁縫 12 個配方",
    desc = "物品說明框加上中文：這個材料哪些專業用得到、這件東西哪個專業做的。",
    flag("itemUse") },
  { id = "sparkle", name = "拾取閃光", cat = "介面", icon = "Spell_Holy_HolyBolt", tab = "utility", demo = "閃閃發亮",
    desc = "任務物品、還有東西可撿的屍體會閃（像經典版）。這是遊戲設定，取消後要重開遊戲才完全消失。",
    flag("sparkle", function() ns.Utility.Apply("sparkle") end) },
  { id = "gather", name = "採集圖示", cat = "介面", icon = "INV_Misc_Herb_07", tab = "utility", demo = "草藥",
    desc = "面對草藥、礦點、寶箱時，上面出現遊戲內建的圖示，比較容易看到。",
    flag("gather", function() ns.Utility.Apply("gather") end) },
  { id = "font", name = "傷害字型", cat = "介面", icon = "INV_Misc_Book_11", tab = "utility", demo = "12,345", relog = true,
    desc = "打怪跳的數字換成粗斜的「阿莫比爽字」。要回到角色選擇畫面再進來才會換。",
    mode("dmgFont", "game", "amobi") },
  { id = "platestyle", name = "血條美化", cat = "介面", icon = "INV_Misc_Gem_Variety_01", tab = "combat", demo = "金色目標框",
    desc = "名條換成阿莫比的樣式：細框、質感血條、血量百分比、金色目標框，玩家照職業上色，施法條顯示法術和目標。不用另外裝插件，取消就改回來。副本裡友方的名條遊戲不讓改。",
    flag("plateBeauty", function()
      local _, msg = ns.Plates.Apply()
      if msg and O.page then O.page.msg:SetText(msg) end
    end) },
  { id = "buffs", name = "增益提醒", cat = "介面", icon = "INV_Misc_Food_15", tab = "buffs", demo = "快到期",
    desc = "食物、睡袋、藥劑和卷軸的增益快到期、到期時，畫面上方大字＋音效提醒你。",
    flag("buffRemind", function() ns.Reminder.Tick() end) },
  { id = "talent", name = "天賦一鍵套用", cat = "介面", icon = "INV_Misc_Book_07", tool = tab("talent"), tab = "talent", demo = "AMOBI1",
    desc = "網站的天賦模擬器、傳承樹配好，複製代碼，進遊戲貼上就幫你點好。" },
  { id = "loot", name = "戰利品查詢", cat = "介面", icon = "INV_Misc_Bag_08", tool = function() ns.LootBrowser.Open() end, tab = "loot",
    demo = "熔火之心", desc = "像 AtlasLoot：選副本、首領看會掉什麼，可以搜尋物品名稱。" },

  { id = "pvpvoice", name = "控場語音播報", cat = "PvP", icon = "Spell_Nature_Polymorph", tab = "pvpalert", demo = "「變羊」",
    desc = "敵人施放變羊、恐懼術、死亡纏繞這類控場技能時，用中文語音唸出來，畫面上方也跳大字。預設只唸目標、專注目標和正對著你的敵人。",
    pvp("pvpCast") },
  { id = "pvpcd", name = "敵方技能冷卻", cat = "PvP", icon = "Spell_Shadow_PsychicScream", tab = "pvpalert", demo = "心靈尖嘯 23",
    desc = "看到敵人施放就開始算他的技能冷卻，好了用語音提醒。",
    pvp("pvpCd") },
  { id = "pvpnear", name = "附近敵人警示", cat = "PvP", icon = "Ability_Hunter_EagleEye", tab = "pvpalert", demo = "附近敵人 3",
    desc = "附近有敵方陣營玩家時跳出名字和人數，可以設必殺名單。",
    pvp("pvpNearby") },

  { id = "sharemarket", name = "分享物價掉落", cat = "分享資料", icon = "INV_Misc_Coin_01", tab = "share", demo = "價格走勢",
    desc = "在阿莫比的公會裡，把拍賣場物價、首領掉落傳給阿莫比網站的物品頁（沒有玩家名字）。",
    share("share") },
  { id = "sharepvp", name = "分享榮譽擊殺", cat = "分享資料", icon = "INV_Jewelry_TrinketPVP_01", tab = "share", demo = "擊殺排行榜",
    desc = "亞服 PvP 規則：你拿到的榮譽擊殺傳給阿莫比，做網站的擊殺排行榜。",
    share("pvpShare") },
  { id = "sharesrc", name = "分享物品來源", cat = "分享資料", icon = "INV_Misc_Bag_10", tab = "share", demo = "怎麼取得",
    desc = "商人、任務獎勵、怪物和寶箱的掉落傳給阿莫比網站，物品頁就有「怎麼取得」。",
    share("srcShare") },
}
for _, f in ipairs(O.FEATURES) do f.get, f.set = f[1], f[2] end

-- 方案（企劃的表）：列到的格子開或關；沒列到的（分享資料、傷害字型、血條美化：看喜好的外觀）不動
local LIGHT = { range = true, cd = true, health = true, coords = true, itemuse = true }
local function plan(on)
  local out = {}
  for _, f in ipairs(O.FEATURES) do
    if f.get and f.cat ~= "分享資料" and f.id ~= "font" and f.id ~= "platestyle" then out[f.id] = on[f.id] == true end
  end
  for id in pairs(LIGHT) do out[id] = true end
  return out
end
O.PRESETS = {
  { name = "新手精簡", set = plan({ card = true, questmark = true, buffs = true }) },
  { name = "團隊副本", set = plan({ dps = true, plate = true, card = true, review = true, threat = true, buffs = true }) },
  { name = "PvP", set = plan({ dps = true, plate = true, pvpvoice = true, pvpcd = true, pvpnear = true }) },
  { name = "全部開", set = plan({ dps = true, plate = true, card = true, review = true, threat = true, questmark = true, buffs = true,
                                pvpvoice = true, pvpcd = true, pvpnear = true, questgo = true, sparkle = true, gather = true }) },
}
local ALL_OFF = plan({})
for id in pairs(LIGHT) do ALL_OFF[id] = false end

-- 套用一組（方案、全部開關）：回傳開了幾個、關了幾個
function O.Apply(set)
  local on, off = 0, 0
  for _, f in ipairs(O.FEATURES) do
    local want = set[f.id]
    if want ~= nil and f.set and f.get() ~= want then
      f.set(want)
      if want then on = on + 1 else off = off + 1 end
    end
  end
  return on, off
end

function O.Preset(name)
  for _, p in ipairs(O.PRESETS) do
    if p.name == name then
      local on, off = O.Apply(p.set)
      return on + off == 0 and ("已經是「" .. name .. "」了。") or ("已套用「%s」：開了 %d 個、關了 %d 個"):format(name, on, off)
    end
  end
end

function O.AllOff()
  local _, off = O.Apply(ALL_OFF)
  return ("全部關：關了 %d 個（分享資料、傷害字型、血條美化沒動）"):format(off)
end

function O.Count()
  local on, all = 0, 0
  for _, f in ipairs(O.FEATURES) do
    if f.get then
      all = all + 1
      if f.get() then on = on + 1 end
    end
  end
  return on, all
end

-- 搜尋、分類之後看得到的格子
function O.Visible(cat, query)
  local out = {}
  query = query and strtrim(query):lower() or ""
  for _, f in ipairs(O.FEATURES) do
    local okCat = not cat or cat == "全部" or f.cat == cat
    local okQ = query == "" or f.name:lower():find(query, 1, true) or f.desc:find(query, 1, true) or f.cat:find(query, 1, true)
    if okCat and okQ then out[#out + 1] = f end
  end
  return out
end

-- ---------------------------------------------------------------------------- 分頁
local state = { cat = "全部", query = "", sel = nil }

local function backdrop(f, a, edge)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(1, 1, 1, a)
    f:SetBackdropBorderColor(0.91, 0.80, 0.53, edge)
  end
end

local function makeTile(p, f)
  local b = CreateFrame("Button", nil, p, "BackdropTemplate")
  b:SetSize(TW, TH)
  backdrop(b, 0.055, 0.25)
  b.feature = f
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(TH - 8, TH - 8)
  b.icon:SetPoint("LEFT", 4, 0)
  b.icon:SetTexture(ICON .. f.icon)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.hl = b:CreateTexture(nil, "BACKGROUND")
  b.hl:SetPoint("TOPLEFT", 1, -1)
  b.hl:SetPoint("BOTTOMRIGHT", -1, 1)
  b.hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  b.hl:SetBlendMode("ADD")
  b.hl:Hide()
  b.label = ns.UI.Text(b, "GameFontHighlightSmall", f.name, TW - TH - 30)
  b.label:SetPoint("LEFT", TH, 0)
  if b.label.SetWordWrap then b.label:SetWordWrap(false) end
  if f.tool then
    b.open = CreateFrame("Button", nil, b)
    b.open:SetSize(34, TH)
    b.open:SetPoint("RIGHT", -2, 0)
    b.open.text = ns.UI.Text(b.open, "GameFontNormalSmall", "打開")
    b.open.text:SetPoint("RIGHT", -4, 0)
    b.open:SetScript("OnClick", function() ns.Try("overview:open", f.tool) end)
  else
    b.check = CreateFrame("CheckButton", nil, b, "UICheckButtonTemplate")
    b.check:SetSize(22, 22)
    b.check:SetPoint("RIGHT", -2, 0)
    b.check:SetScript("OnClick", function(self)
      f.set(self:GetChecked() and true or false)
      if f.relog then O.page.msg:SetText("傷害字型要回到角色選擇畫面再進來才會換。") end
      state.sel = f
      ns.UI.Refresh("overview")
    end)
  end
  b:SetScript("OnClick", function() state.sel = f; ns.UI.Refresh("overview") end)
  return b
end

local function build(p)
  O.page = p
  -- 搜尋、方案
  p.search = ns.UI.Edit(p, 156, 22)
  p.search:SetPoint("TOPLEFT", 6, 0)
  p.hint = ns.UI.Text(p.search, "GameFontDisableSmall", "搜尋功能…")
  p.hint:SetPoint("LEFT", 2, 0)
  p.search:SetScript("OnTextChanged", function(self)
    state.query = self:GetText() or ""
    ns.UI.Refresh("overview")
  end)
  p.presets = {}
  for i, pr in ipairs(O.PRESETS) do
    local b = ns.UI.Button(p, pr.name, 64, 22, function()
      p.msg:SetText(O.Preset(pr.name))
      ns.UI.Refresh("overview")
    end)
    b:SetPoint("TOPLEFT", 168 + (i - 1) * 66, 0)
    p.presets[i] = b
  end
  -- 分類
  p.cats = {}
  local x = 0
  for i, cat in ipairs(CATS) do
    local b = CreateFrame("Button", nil, p)
    b.text = ns.UI.Text(b, "GameFontHighlightSmall", cat)
    b.text:SetPoint("CENTER")
    local w = (b.text.GetStringWidth and b.text:GetStringWidth() or 0)
    w = (type(w) == "number" and w > 0 and w or #cat * 4) + 14
    b:SetSize(w, 20)
    b:SetPoint("TOPLEFT", x, -30)
    b.hl = b:CreateTexture(nil, "BACKGROUND")
    b.hl:SetAllPoints()
    b.hl:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    b.hl:SetBlendMode("ADD")
    b.cat = cat
    b:SetScript("OnClick", function() state.cat = cat; ns.UI.Refresh("overview") end)
    p.cats[i] = b
    x = x + w + 4
  end
  p.count = ns.UI.Text(p, "GameFontHighlightSmall", "")
  p.count:SetPoint("TOPRIGHT", p, "TOPLEFT", 432, -34)
  p.count:SetJustifyH("RIGHT")
  -- 格子
  p.tiles = {}
  for i, f in ipairs(O.FEATURES) do p.tiles[i] = makeTile(p, f) end
  p.empty = ns.UI.Text(p, "GameFontDisableSmall", "", 300)
  p.empty:SetPoint("TOPLEFT", 4, -64)
  -- 說明
  local d = CreateFrame("Frame", nil, p, "BackdropTemplate")
  d:SetSize(432, 168)
  d:SetPoint("TOPLEFT", 0, -58 - ROWS * (TH + GAP) - 6)
  backdrop(d, 0.04, 0.35)
  p.desc = d
  d.icon = d:CreateTexture(nil, "ARTWORK")
  d.icon:SetSize(36, 36)
  d.icon:SetPoint("TOPLEFT", 10, -10)
  d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  d.name = ns.UI.Text(d, "GameFontNormalLarge", "")
  d.name:SetPoint("TOPLEFT", 54, -12)
  d.status = ns.UI.Text(d, "GameFontHighlightSmall", "")
  d.status:SetPoint("TOPLEFT", 54, -32)
  d.text = ns.UI.Text(d, "GameFontHighlightSmall", "", 250)
  d.text:SetPoint("TOPLEFT", 10, -54)
  d.go = ns.UI.Button(d, "打開設定", 110, 22, function()
    local f = state.sel
    if not f then return end
    if f.tool then f.tool() elseif f.tab then ns.UI.Open(f.tab) end
  end)
  d.go:SetPoint("BOTTOMLEFT", 10, 12)
  d.where = ns.UI.Text(d, "GameFontDisableSmall", "")
  d.where:SetPoint("LEFT", d.go, "RIGHT", 6, 0)
  d.demo = CreateFrame("Frame", nil, d, "BackdropTemplate")
  d.demo:SetSize(154, 144)
  d.demo:SetPoint("TOPRIGHT", -8, -12)
  if d.demo.SetBackdrop then
    d.demo:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    d.demo:SetBackdropColor(0.12, 0.14, 0.17, 0.95)
    d.demo:SetBackdropBorderColor(0.91, 0.80, 0.53, 0.3)
  end
  d.big = d.demo:CreateTexture(nil, "ARTWORK")
  d.big:SetSize(52, 52)
  d.big:SetPoint("TOP", 0, -18)
  d.big:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  d.example = ns.UI.Text(d.demo, "GameFontNormalLarge", "")
  d.example:SetPoint("TOP", 0, -84)
  d.example:SetJustifyH("CENTER")
  d.note = ns.UI.Text(d.demo, "GameFontDisableSmall", "示意")
  d.note:SetPoint("BOTTOM", 0, 8)
  d.empty = ns.UI.Text(d, "GameFontDisableSmall", "點一格，這裡說明這個功能在做什麼。\n打勾馬上開關；「打開」是工具，點了到那一頁。", 400)
  d.empty:SetPoint("CENTER")
  d.empty:SetJustifyH("CENTER")
  -- 底下
  p.msg = ns.UI.Text(p, "GameFontNormalSmall", "", 260)
  p.msg:SetPoint("TOPLEFT", 0, -58 - ROWS * (TH + GAP) - 6 - 168 - 12)
  local all = ns.UI.Button(p, "全部開", 78, 22, function()
    p.msg:SetText(O.Preset("全部開"))
    ns.UI.Refresh("overview")
  end)
  all:SetPoint("TOPLEFT", 432 - 160, -58 - ROWS * (TH + GAP) - 6 - 168 - 8)
  local none = ns.UI.Button(p, "全部關", 78, 22, function()
    p.msg:SetText(O.AllOff())
    ns.UI.Refresh("overview")
  end)
  none:SetPoint("TOPLEFT", 432 - 78, -58 - ROWS * (TH + GAP) - 6 - 168 - 8)
  p.allOn, p.allOff = all, none
end

local function refresh(p)
  local q = state.query or ""
  if q == "" then p.hint:Show() else p.hint:Hide() end
  for _, b in ipairs(p.cats) do
    if b.cat == state.cat then b.hl:Show(); b.text:SetTextColor(1, 0.82, 0) else b.hl:Hide(); b.text:SetTextColor(0.94, 0.94, 0.94) end
  end
  local on, all = O.Count()
  p.count:SetText(("開著 %d／%d"):format(on, all))
  local shown = {}
  for i, f in ipairs(O.Visible(state.cat, q)) do shown[f] = i end
  for _, b in ipairs(p.tiles) do
    local f, slot = b.feature, shown[b.feature]
    if slot then
      local col, row = (slot - 1) % COLS, math.floor((slot - 1) / COLS)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", col * (TW + GAP), -58 - row * (TH + GAP))
      b:Show()
      local lit = f.tool or f.get()
      if b.check then b.check:SetChecked(f.get() and true or false) end
      if lit then b.label:SetTextColor(0.94, 0.94, 0.94) else b.label:SetTextColor(0.62, 0.62, 0.62) end
      if state.sel == f then b.hl:Show(); b:SetBackdropBorderColor(1, 0.82, 0, 0.9) else b.hl:Hide(); b:SetBackdropBorderColor(0.91, 0.80, 0.53, 0.25) end
    else
      b:Hide()
    end
  end
  p.empty:SetText(next(shown) and "" or ("找不到「" .. q .. "」。"))
  local d, f = p.desc, state.sel
  if f then
    d.empty:Hide()
    d.icon:SetTexture(ICON .. f.icon); d.icon:Show()
    d.big:SetTexture(ICON .. f.icon); d.demo:Show()
    d.name:SetText(ns.GOLD .. f.name .. "|r")
    local st = f.tool and "|cffffd100工具|r" or f.get() and "|cff60d060開著|r" or "|cff9d9d9d關著|r"
    d.status:SetText(f.cat .. "　·　" .. st .. (f.relog and "　|cff9d9d9d要重進遊戲|r" or ""))
    d.text:SetText(f.desc)
    d.example:SetText(f.demo or "")
    d.go:SetText(f.tool and "打開" or "打開設定")
    d.go:Show()
    local tabName
    for _, t in ipairs({ { "combat", "戰鬥畫面" }, { "dungeon", "副本" }, { "review", "打完檢討" }, { "boss", "首領仇恨" }, { "nav", "地圖導航" },
                         { "quest", "任務" }, { "dquests", "副本任務" }, { "utility", "實用功能" }, { "buffs", "增益提醒" }, { "talent", "天賦" },
                         { "loot", "戰利品" }, { "pvpalert", "PvP 警報" }, { "share", "分享資料" } }) do
      if t[1] == f.tab then tabName = t[2] end
    end
    d.where:SetText(tabName and ("在「" .. tabName .. "」分頁") or "")
  else
    d.empty:Show()
    d.icon:Hide(); d.demo:Hide(); d.go:Hide()
    d.name:SetText(""); d.status:SetText(""); d.text:SetText(""); d.where:SetText("")
  end
  if (p.msg:GetText() or "") == "" then p.msg:SetText("|cff9d9d9d傷害字型要重進遊戲才換。|r") end
end

-- 打開功能總覽（/amobi 總覽），可以順便搜尋
function O.Open(query)
  ns.UI.Open("overview")
  if query and query ~= "" and O.page then
    O.page.search:SetText(query)
    state.query = query
    ns.UI.Refresh("overview")
  end
end

ns.UI.AddTab("overview", "功能總覽", build, refresh)
