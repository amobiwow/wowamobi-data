-- 阿莫比小幫手（AmobiCompanion）
--
-- 阿莫比網站（wowamobi.com）的遊戲小幫手。四個功能各在一個檔案：
--   Overview.lua 功能總覽（第一個分頁）：所有功能一格一格，打勾馬上開關、搜尋、分類、方案（1.12.0）
--   Talents.lua  天賦一鍵套用：貼上網站「複製到小幫手」的代碼（或網站網址）→ 確認視窗列出會點哪些、要花幾點 → 套用；
--                也能把目前的配點匯出成網站網址
--   Dungeon.lua  副本小卡：進副本自動顯示首領出場順序、進入等級、建議等級、記到的掉落；打首領時自動收起來
--   Combat.lua   戰鬥畫面一鍵設定：打開暴雪內建的冷卻監控、首領警告、傷害統計，擺到推薦位置（編輯模式裡的一個版面）
--   Review.lua   打完檢討：首領戰（或一場戰鬥）結束後，用暴雪傷害統計的資料顯示這場的輸出、治療摘要
--   Assist.lua   戰鬥輔助：目標距離、快捷列冷卻倒數數字、目標頭像血條的狀態文字、名條血量、我的仇恨；只顯示，秘密值直接交給遊戲顯示
--   Plates.lua   血條美化：遊戲內建的名條換成阿莫比的外觀（1.13.0，打勾才開；血量、施法都照遊戲跑，一個秘密值都不碰）
--   Quest.lua    任務：帶路到最近的任務、名條標出任務怪、自動接交任務（打勾才開）
--   PvPAlert.lua PvP 警報：敵方控場技能中文語音播報、冷卻倒數、附近敵方玩家和必殺名單（1.9.0；只看目標、專注目標、名條）
--   DungeonQuests.lua 副本任務：每個副本的任務、幾級可接、誰接、帶路（經典版參考，1.10.0）
--   LootBrowser.lua 戰利品查詢：選副本、首領看會掉什麼，搜尋物品（玩家回報的＋經典版參考）
--   Navigate.lua 地圖導航：座標和區域等級、遊戲內建的導航點（/amobi 去 x y）、最近的飛行點、旅店、副本入口
--   Boss.lua     首領仇恨：暴雪內建的首領時間軸、首領警告的開關和等級，開怪倒數，仇恨百分比、名條仇恨顯示
--   Utility.lua  實用功能：物品說明框的中文用途（材料、製作）、拾取閃光、草藥礦點寶箱的圖示（遊戲內建的效果，只幫忙開關）
--   Reminder.lua 增益提醒：食物、睡袋（充分休息）、藥劑和卷軸快到期／到期時提醒（只在戰鬥外讀增益）
--   Market.lua   拍賣場物價記錄：打開拍賣場時全掃描一次（只在阿莫比的公會裡）
--   Drops.lua    首領掉落記錄：首領擊殺、首領屍體和寶箱、隊伍擲骰的物品（只在阿莫比的公會裡）
--   PvP.lua      榮譽擊殺：聯盟角色拿到榮譽擊殺時記下對方名字、軍銜、榮譽（亞服 PvP 聯盟限定，可以關）
--   Sources.lua  物品來源：商人賣什麼、任務給什麼、怪物和寶箱掉什麼、在哪裡（1.11.0；只有 NPC 的名字，可以關）
--   Share.lua    分享資料：上面幾樣用插件訊息傳給阿莫比站長的角色（拍賣場、掉落沒有玩家名字；擊殺有對方名字；可以關）
-- 這個檔：共用的事件、設定、限制檢查、指令和診斷；UI.lua 是視窗的共用零件和主視窗。資料在 Data\（tools\build_companion_data.py 產生）。
--
-- 永恆的插件限制：戰鬥中、打首領、挑戰模式時，buff、冷卻、戰鬥紀錄、傷害數字會變成「秘密值」，插件不能拿來比較、計算。
-- 這個插件的原則：
--   * 不呼叫任何受保護的函式、不改暴雪的介面框架（只用 C_ 開頭的遊戲函式和自己的視窗），所以不會造成 ADDON_ACTION_BLOCKED
--     （例外：Assist.lua 換快捷列冷卻數字的字型，Plates.lua 打勾才換名條的材質和顏色；都只換外觀，不碰數值）
--   * 會改東西的（天賦、版面、設定）只在戰鬥外、玩家按按鈕時才做
--   * 讀到秘密值就不算，改成告訴玩家去看暴雪自己的視窗
--   * 不會替玩家施法、選目標、移動、撿東西或發話（Share.lua 的插件訊息玩家看不到，不是說話）
-- 指令：/amobi（或 /amb、/阿莫比）開視窗；/amobi 檢查 看有沒有出錯。

local ADDON, ns = ...
ns.ADDON = ADDON
ns.SITE = "https://wowamobi.com"
ns.GOLD = "|cffe9cb88"

local frame = CreateFrame("Frame")
local handlers = {}

local DEFAULTS = {
  card = true,             -- 進副本顯示副本小卡
  cardCollapsed = false,   -- 小卡收起來（只剩標題列）
  cardFold = true,         -- 首領戰、進入戰鬥時自動收起小卡
  review = "boss",         -- 打完檢討：boss 首領戰結束、all 每場戰鬥（夠長的）、off 不顯示
  reviewMin = 20,          -- 秒：一般戰鬥至少打這麼久才顯示
  range = true,            -- 戰鬥輔助：目標距離（畫面中間偏下的一小塊文字）
  rangeLocked = true,      -- 距離、DPS 小塊鎖定（解鎖才能拖）
  rangeMaxOnly = false,    -- 距離只寫最大值（「30 碼內」）
  rangeBg = false,         -- 距離、DPS 小塊加底色
  dps = true,              -- 戰鬥輔助：戰鬥中顯示自己的 DPS（或 HPS）
  dpsKind = "dps",         -- dps 輸出、hps 治療
  cdText = true,           -- 戰鬥輔助：快捷列冷卻倒數數字（放大、變色）
  cdSize = 20,             -- 冷卻數字大小
  healthMode = "both",     -- 目標頭像血條的狀態文字：numeric 數字、percent 百分比、both 兩者、off 不改
  plateHealth = true,      -- 戰鬥輔助：名條血量百分比
  plateBeauty = false,     -- 血條美化（玩家打勾才開；改遊戲設定和名條的材質）
  itemUse = true,          -- 實用功能：物品說明框加中文用途（只加字）
  buffRemind = true,       -- 增益提醒：食物、睡袋、藥劑和卷軸快到期／到期時提醒
  buffFood = true,
  buffRested = true,
  buffElixir = true,
  buffSound = true,
  sparkle = false,         -- 實用功能：拾取閃光（改遊戲設定，玩家打勾才開）
  gather = false,          -- 實用功能：草藥、礦點、寶箱上面的圖示（改遊戲設定，玩家打勾才開）
  threat = true,           -- 首領仇恨：戰鬥中顯示我的仇恨（組隊時、目標是敵人）
  threatSolo = false,      -- 首領仇恨：一個人打怪也顯示我的仇恨
  coords = true,           -- 地圖導航：小地圖下面顯示座標和區域等級
  questNearest = false,    -- 任務：自動帶路到最近的任務
  questPlates = true,      -- 任務：名條上標出任務怪
  questAuto = false,       -- 任務：自動接任務、自動交任務（玩家打勾才開）
  share = true,            -- 分享資料：記拍賣場物價、首領掉落，傳給阿莫比站長（老闆 10/25：預設開、寫清楚）
  pvpShare = true,         -- 分享資料：聯盟角色的榮譽擊殺傳給阿莫比站長（老闆 10/26：亞服 PvP 聯盟限定、預設開、可以關）
  srcShare = true,         -- 分享資料：物品來源（商人、任務獎勵、怪物和寶箱的掉落、位置）傳給阿莫比站長（老闆 10/27「一起做」，預設開、可以關）
  pvpAlert = true,         -- PvP 警報（老闆 10/26）：敵方控場技能語音播報、冷卻倒數、附近敵人（只讀、只唸、只顯示）
  pvpCast = true,          -- 敵方控場技能語音播報
  pvpCC = true, pvpInterrupt = true, pvpDefense = true,   -- 播報哪幾種：控場、打斷、保命
  pvpCastAll = false,      -- 看得到的敵人全部唸（關：只唸目標、專注目標和對著我的）
  pvpCd = true,            -- 敵方技能冷卻倒數
  pvpCdVoice = true,       -- 冷卻好了用語音提醒
  pvpNearby = true,        -- 附近敵方陣營玩家警示
  pvpNearbyVoice = true,   -- 新出現的敵人唸「敵人」
  pvpSecretCast = false,   -- 讀不到是什麼技能時，唸目標正在施放的法術（會比較吵）
  pvpSpeak = true,         -- 用遊戲的文字轉語音（不勾只跳大字）
  dmgFont = "game",        -- 實用功能：打怪跳的傷害數字字型：game 遊戲原本、amobi 阿莫比爽字、us 美版（Utility.lua 的 U.FONTS）
  -- dmgScale：傷害數字大小（1.5、2 倍），nil＝不改遊戲設定
}

function ns.Print(msg) print(ns.GOLD .. "阿莫比小幫手|r " .. msg) end

-- 秘密值：插件不能比較、計算，也不能拿來當條件；遇到就當作讀不到
function ns.Secret(v)
  if issecretvalue and issecretvalue(v) then return true end
  if type(v) == "table" and issecrettable and issecrettable(v) then return true end
  return false
end

-- 出錯時記下來（/amobi 檢查 看得到），第一次在聊天框說一聲；不讓一個功能的錯誤影響別的功能
function ns.Fail(where, err)
  local d = ns.db and ns.db.diag
  if d then
    d.errors = d.errors + 1
    table.insert(d.last, 1, { t = time(), where = where, err = tostring(err):sub(1, 300) })
    while #d.last > 10 do table.remove(d.last) end
  end
  if not ns.toldError then
    ns.toldError = true
    ns.Print("|cffff6060出了一點錯（" .. tostring(where) .. "），已記下來。打 /amobi 檢查 可以看。|r")
  end
end

function ns.Try(where, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then ns.Fail(where, err) end
  return ok, err
end

-- 遊戲函式不存在或出錯都回傳 nil（永恆和正式版的函式不完全一樣）
function ns.Call(tbl, name, ...)
  local fn = tbl and tbl[name]
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  return unpack(r, 2, table.maxn(r))
end

function ns.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    if not pcall(frame.RegisterEvent, frame, event) then return end   -- 這個版本沒有這個事件
  end
  table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
  for _, fn in ipairs(handlers[event] or {}) do
    ns.Try(event, fn, ...)
  end
end)

-- 插件限制：回傳現在不能改東西的原因（戰鬥中、首領戰中…），沒有限制回傳 nil
local RESTRICT = {
  { "Combat", "戰鬥中" }, { "Encounter", "首領戰中" }, { "ChallengeMode", "挑戰模式中" },
  { "PvPMatch", "PvP 對戰中" }, { "Map", "這張地圖限制插件" },
}
function ns.Restricted()
  if InCombatLockdown() then return "戰鬥中" end
  local api, enum = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
  if api and api.IsAddOnRestrictionActive and enum then
    for _, r in ipairs(RESTRICT) do
      local t = enum[r[1]]
      if t ~= nil then
        local ok, on = pcall(api.IsAddOnRestrictionActive, t)
        if ok and not ns.Secret(on) and on == true then return r[2] end
      end
    end
  end
  return nil
end

function ns.ClassName(token)
  local t = ns.TalentData and ns.TalentData.classes[token]
  if t then return t.name end
  return token or "?"
end

function ns.PlayerClass()
  local _, token = UnitClass("player")
  return token
end

local function mergeDefaults(db)
  db.settings = db.settings or {}
  for k, v in pairs(DEFAULTS) do
    if db.settings[k] == nil then db.settings[k] = v end
  end
  db.diag = db.diag or {}
  db.diag.errors = db.diag.errors or 0
  db.diag.blocked = db.diag.blocked or 0
  db.diag.last = db.diag.last or {}
  db.history = db.history or {}
  db.version = 1
end

ns.On("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  AmobiCompanionDB = AmobiCompanionDB or {}
  ns.db = AmobiCompanionDB
  mergeDefaults(ns.db)
  for _, m in ipairs(ns.modules or {}) do
    if m.Init then ns.Try("Init", m.Init) end
  end
end)

-- 自己檢查：遊戲說這個插件做了被擋的動作（理論上不會發生），記下來給 /amobi 檢查
local function blocked(event, who, func)
  if ns.Secret(who) or who ~= ADDON then return end
  local d = ns.db and ns.db.diag
  if not d then return end
  d.blocked = d.blocked + 1
  d.blockedLast = { t = time(), event = event, func = (not ns.Secret(func)) and tostring(func) or "?" }
end
ns.On("ADDON_ACTION_BLOCKED", function(...) blocked("ADDON_ACTION_BLOCKED", ...) end)
ns.On("ADDON_ACTION_FORBIDDEN", function(...) blocked("ADDON_ACTION_FORBIDDEN", ...) end)

function ns.Register(module)
  ns.modules = ns.modules or {}
  table.insert(ns.modules, module)
end

function ns.Diagnose()
  local d = ns.db.diag
  ns.Print(("版本 %s。出錯 %d 次、被遊戲擋下 %d 次。"):format(
    (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "?", d.errors, d.blocked))
  if d.blockedLast then
    ns.Print(("最後一次被擋：%s %s（%s）"):format(d.blockedLast.event, d.blockedLast.func, date("%m/%d %H:%M", d.blockedLast.t)))
  end
  for i = 1, math.min(3, #d.last) do
    local e = d.last[i]
    ns.Print(("錯誤 %d：%s｜%s｜%s"):format(i, date("%m/%d %H:%M", e.t), e.where, e.err))
  end
  local r = ns.Restricted()
  ns.Print("現在" .. (r and ("有插件限制：" .. r) or "沒有插件限制") .. "。")
  if d.errors == 0 and d.blocked == 0 then ns.Print("|cff60ff60一切正常。|r") end
end

local function slash(msg)
  msg = strtrim(msg or "")
  local cmd = msg:lower()
  if cmd == "" then
    ns.UI.Toggle()
  elseif cmd == "overview" or cmd == "總覽" or cmd == "功能" then
    ns.Overview.Open()
  elseif cmd == "talent" or cmd == "天賦" then
    ns.UI.Open("talent")
  elseif cmd == "combat" or cmd == "戰鬥" then
    ns.UI.Open("combat")
  elseif cmd == "buffs" or cmd == "增益" or cmd == "提醒" then
    ns.UI.Open("buffs")
  elseif cmd == "utility" or cmd == "實用" then
    ns.UI.Open("utility")
  elseif cmd == "share" or cmd == "分享" then
    ns.UI.Open("share")
  elseif msg:match("^副本任務") or cmd:match("^dquest") then
    ns.DQ.Slash((msg:gsub("^%S+%s*", "")))
  elseif cmd == "card" or cmd == "副本" then
    ns.Dungeon.Toggle()
  elseif cmd == "review" or cmd == "檢討" then
    ns.Review.ShowLast()
  elseif cmd == "check" or cmd == "檢查" then
    ns.Diagnose()
  elseif cmd == "dps" then
    ns.Assist.DiagnoseDps()
  elseif cmd == "range" or cmd == "距離" then
    ns.Assist.DiagnoseRange()
  elseif cmd == "font" or cmd == "字型" then
    ns.Utility.DiagnoseFont()
  elseif cmd == "boss" or cmd == "首領" or cmd == "仇恨" then
    ns.UI.Open("boss")
  elseif cmd == "nav" or cmd == "地圖" or cmd == "導航" then
    ns.UI.Open("nav")
  elseif cmd == "quest" or cmd == "任務" then
    ns.UI.Open("quest")
  elseif cmd == "pvp" or cmd == "警報" then
    ns.UI.Open("pvpalert")
  elseif msg:match("^必殺") or cmd:match("^kill") then
    local name = strtrim((msg:gsub("^%S+%s*", "")))
    if name == "" then ns.UI.Open("pvpalert") else ns.PvPAlert.ToggleKill(name) end
  elseif cmd == "任務帶路" or cmd == "questgo" then
    ns.Print(select(2, ns.Quest.GoNearest()))
  elseif cmd:match("^loot") or msg:match("^掉落") or msg:match("^戰利品") then
    ns.LootBrowser.Slash((msg:gsub("^%S+%s*", "")))
  elseif cmd == "clear" or cmd == "清除導航" or cmd == "清除" then
    ns.Print(select(2, ns.Navigate.Clear()))
  elseif cmd:match("^way") or cmd:match("^go ") or msg:match("^去") then
    ns.Navigate.Slash((msg:gsub("^%S+%s*", "")))
  elseif cmd:match("^pull") or cmd:match("^倒數") then
    ns.Boss.Slash(msg:match("(%d+)"))
  else
    ns.Print("指令：/amobi 開視窗｜/amobi 天賦｜/amobi 副本 開關副本小卡｜/amobi 戰鬥｜/amobi 首領｜/amobi pull 10 開怪倒數｜/amobi 去 52.3 47.1 導航｜/amobi 清除導航｜/amobi 掉落 熔火之心 戰利品查詢｜/amobi 任務帶路 最近的任務｜/amobi 實用｜/amobi 分享 分享資料給網站｜/amobi 檢討 看上一場｜/amobi dps 檢查 DPS 讀不讀得到｜/amobi range 看距離怎麼夾的｜/amobi 字型 看傷害字型有沒有換｜/amobi 檢查 看有沒有出錯")
  end
end

SLASH_AMOBI1, SLASH_AMOBI2, SLASH_AMOBI3 = "/amobi", "/amb", "/阿莫比"
SlashCmdList.AMOBI = function(msg) ns.Try("slash", slash, msg) end

-- 插件選單（小地圖旁的插件按鈕）點這個插件時打開視窗
function AmobiCompanion_OnAddonCompartmentClick()
  ns.Try("compartment", ns.UI.Toggle)
end
