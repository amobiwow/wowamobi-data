-- 阿莫比小幫手：打完檢討
--
-- 首領戰結束（ENCOUNTER_END）或一場戰鬥結束（PLAYER_REGEN_ENABLED，打夠久的）後，跳一張小卡：
-- 這場打了多久、我的輸出（總量、每秒、隊上第幾名、占全隊幾成、打最多的三個技能）、治療（有補才列）。
-- 數字來自暴雪內建的傷害統計（C_DamageMeter）：戰鬥中是秘密值（文件標 SecretWhenInCombat），戰鬥結束、插件限制解除後才讀；
-- 讀之前先問 C_RestrictedActions，讀到的值再用 issecretvalue 檢查，只要有一個是秘密值就不算，
-- 改成「打開暴雪傷害統計看這一場」的捷徑（只會打開傷害統計的設定，不碰暴雪的傷害統計視窗）。
-- 全隊排名只顯示在畫面上（名字是秘密值就寫「?」），不存進存檔。

local _, ns = ...
local R = {}
ns.Review = R

local RETRY, TRIES = 2, 8      -- 插件限制還沒解除：每 2 秒再試，最多 8 次
local last, card = nil, nil
local fightStart, encounter = nil, nil

local function wan(n)
  if n >= 1e8 then return ("%.2f億"):format(n / 1e8) end
  if n >= 1e4 then return ("%.1f萬"):format(n / 1e4) end
  return tostring(math.floor(n + 0.5))
end
R.Wan = wan

local function clock(sec)
  sec = math.floor(sec + 0.5)
  if sec >= 60 then return ("%d分%02d秒"):format(math.floor(sec / 60), sec % 60) end
  return sec .. "秒"
end

local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  if GetSpellInfo then return (GetSpellInfo(id)) end
end

-- 一種統計（傷害或治療）的摘要；有秘密值回傳 "secret"，沒資料回傳 nil
local function summarize(sessionID, kind)
  local api = C_DamageMeter
  local sess
  if sessionID then
    sess = ns.Call(api, "GetCombatSessionFromID", sessionID, kind)
  else
    sess = ns.Call(api, "GetCombatSessionFromType", (Enum.DamageMeterSessionType or {}).Current or 1, kind)
  end
  if type(sess) ~= "table" then return nil end
  if ns.Secret(sess) or ns.Secret(sess.totalAmount) or ns.Secret(sess.combatSources) then return "secret" end
  local me, list, rows = nil, {}, {}
  for _, s in ipairs(sess.combatSources or {}) do
    if ns.Secret(s.totalAmount) or ns.Secret(s.amountPerSecond) then return "secret" end
    list[#list + 1] = s.totalAmount
    if s.isLocalPlayer then me = s end
    -- 排名用（只顯示在畫面上，不存）：名字是秘密值就寫「?」
    local name = (s.isLocalPlayer and "你") or ((not ns.Secret(s.name) and type(s.name) == "string") and s.name) or "?"
    rows[#rows + 1] = { name = name, total = s.totalAmount, ps = s.amountPerSecond, me = s.isLocalPlayer == true,
                        class = (not ns.Secret(s.classFilename)) and s.classFilename or nil }
  end
  table.sort(rows, function(a, b) return a.total > b.total end)
  if not me or me.totalAmount <= 0 then return nil end
  local rank = 1
  for _, v in ipairs(list) do if v > me.totalAmount then rank = rank + 1 end end
  local out = { total = me.totalAmount, ps = me.amountPerSecond, rank = rank, n = #list, rows = rows,
                share = (sess.totalAmount and sess.totalAmount > 0) and (me.totalAmount / sess.totalAmount) or nil,
                duration = (not ns.Secret(sess.durationSeconds)) and sess.durationSeconds or nil, spells = {} }
  local guid = UnitGUID and UnitGUID("player")
  local src = sessionID and ns.Call(api, "GetCombatSessionSourceFromID", sessionID, kind, guid)
  if type(src) == "table" and not ns.Secret(src.combatSpells) then
    local spells = {}
    for _, sp in ipairs(src.combatSpells or {}) do
      if ns.Secret(sp.totalAmount) or ns.Secret(sp.spellID) then spells = {}; break end
      spells[#spells + 1] = sp
    end
    table.sort(spells, function(a, b) return a.totalAmount > b.totalAmount end)
    for i = 1, math.min(3, #spells) do
      local sp = spells[i]
      out.spells[#out.spells + 1] = { name = spellName(sp.spellID) or ("#" .. sp.spellID), share = sp.totalAmount / me.totalAmount }
    end
  end
  return out
end

local function latestSession()
  local list = ns.Call(C_DamageMeter, "GetAvailableCombatSessions")
  if type(list) ~= "table" or ns.Secret(list) then return nil end
  local best
  for _, s in ipairs(list) do
    if type(s) == "table" and not ns.Secret(s.sessionID) and (not best or s.sessionID > best.sessionID) then best = s end
  end
  return best
end

-- 讀這一場：回傳 { title, lines } 或 { title, secret = true }
function R.Read(title)
  local DMT = Enum and Enum.DamageMeterType or {}
  local sess = latestSession()
  local id = sess and sess.sessionID
  local dmg = summarize(id, DMT.DamageDone or 0)
  local heal = summarize(id, DMT.HealingDone or 2)
  if dmg == "secret" or heal == "secret" then return { title = title, secret = true } end
  local lines = {}
  local dur = (dmg and dmg.duration) or (heal and heal.duration) or (sess and not ns.Secret(sess.durationSeconds) and sess.durationSeconds)
  if dur then lines[#lines + 1] = "時間 " .. clock(dur) end
  local function block(label, s, unit)
    if not s then return end
    local where = s.n > 1 and ("‧隊上第 %d／%d"):format(s.rank, s.n) or ""
    local share = (s.share and s.n > 1) and ("‧占 %d%%"):format(math.floor(s.share * 100 + 0.5)) or ""
    lines[#lines + 1] = ("%s%s|r %s（每秒 %s）%s%s"):format(ns.GOLD, label, wan(s.total), wan(s.ps), where, share)
    if #s.spells > 0 then
      local parts = {}
      for _, sp in ipairs(s.spells) do parts[#parts + 1] = ("%s %d%%"):format(sp.name, math.floor(sp.share * 100 + 0.5)) end
      lines[#lines + 1] = "  |cffbbbbbb" .. table.concat(parts, "、") .. "|r"
    end
  end
  block("輸出", dmg)
  block("治療", heal)
  -- 全隊排名（打完才讀得到數字）：輸出前 5 名，你不在前 5 也列出你
  if dmg and dmg.n > 1 then
    lines[#lines + 1] = ns.GOLD .. "輸出排名|r"
    for i, r in ipairs(dmg.rows) do
      if i <= 5 or r.me then
        local color = r.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[r.class]
        local name = color and color.colorStr and ("|c" .. color.colorStr .. r.name .. "|r") or r.name
        lines[#lines + 1] = ("  %s%d. %s  %s（每秒 %s）|r"):format(r.me and "|cffffffff" or "|cffbbbbbb", i, name, wan(r.total), wan(r.ps))
      end
    end
  end
  if not dmg and not heal then
    lines[#lines + 1] = "這場沒有記到你的輸出或治療。"
    local v = (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("damageMeterEnabled")) or (GetCVar and GetCVar("damageMeterEnabled"))
    if v ~= nil and tostring(v) ~= "1" then
      lines[#lines + 1] = "|cffff9050暴雪傷害統計沒開，讀不到數字：到「戰鬥畫面」分頁按「開／關暴雪傷害統計」。|r"
    end
  end
  return { title = title, lines = lines }
end

-- ---------------------------------------------------------------------------- 小卡
local function meterOn()
  local v = (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("damageMeterEnabled")) or (GetCVar and GetCVar("damageMeterEnabled"))
  return v == nil or tostring(v) ~= "0"
end

local function build()
  card = ns.UI.Panel(UIParent, 300, 140, "MEDIUM")
  ns.UI.Place(card, "reviewPos", "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -320, 220)
  ns.UI.Movable(card, "reviewPos")
  card.title = ns.UI.Text(card, "GameFontNormal", "")
  card.title:SetPoint("TOPLEFT", 10, -8)
  local close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
  close:SetSize(22, 22)
  close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() card:Hide() end)
  card.body = ns.UI.Text(card, "GameFontHighlightSmall", "", 280)
  card.body:SetPoint("TOPLEFT", 10, -30)
  card.meter = ns.UI.Button(card, "打開傷害統計", 110, 22, function()
    if ns.Restricted() then return ns.Print("戰鬥中不能改設定，打完再按。") end
    if C_CVar and C_CVar.SetCVar then C_CVar.SetCVar("damageMeterEnabled", "1") elseif SetCVar then SetCVar("damageMeterEnabled", "1") end
    R.Paint()
  end)
  card.meter:SetPoint("BOTTOMLEFT", 10, 8)
  card:Hide()
  R.card = card
end

function R.Paint()
  if not card or not last then return end
  card.title:SetText(ns.GOLD .. "打完檢討|r  " .. (last.title or ""))
  local lines = last.lines
  if last.secret then
    lines = { "這場的數字遊戲還不給插件讀（首領戰的插件限制）。",
              meterOn() and "請看暴雪的傷害統計視窗：在視窗上方的場次選單選剛才那一場。"
                         or "暴雪的傷害統計目前關著：按下面的按鈕打開，再選剛才那一場。" }
  end
  card.body:SetText(table.concat(lines, "\n"))
  if last.secret and not meterOn() then card.meter:Show() else card.meter:Hide() end
  local h = (card.body.GetStringHeight and card.body:GetStringHeight()) or 0
  card:SetHeight(math.max(80, h + (card.meter:IsShown() and 70 or 42)))
end

function R.Show(result)
  last = result
  R.last = result
  if not card then build() end
  R.Paint()
  card:Show()
end

-- 手動看上一場（/amobi 檢討、「看上一場」按鈕）：沒有插件限制就重新讀暴雪傷害統計最新的一場（野外的戰鬥也可以看），
-- 還在限制中就顯示上次自動跳出的那張
function R.ShowLast()
  if not ns.Restricted() then
    local sess = latestSession()
    local name = sess and not ns.Secret(sess.name) and type(sess.name) == "string" and sess.name ~= "" and sess.name or nil
    return R.Show(R.Read("上一場" .. (name and ("：" .. name) or "")))
  end
  if not last then return ns.Print("還沒有打完的戰鬥可以看（戰鬥中讀不到，打完再看）。") end
  R.Show(last)
end

-- 戰鬥結束後讀數字：插件限制還在就等一下再試，試完還不行就顯示捷徑
local function attempt(title, tries)
  if ns.Restricted() then
    if tries < TRIES then
      C_Timer.After(RETRY, function() ns.Try("review", attempt, title, tries + 1) end)
      return
    end
    return R.Show({ title = title, secret = true })
  end
  R.Show(R.Read(title))
end

local function due(title)
  C_Timer.After(1.5, function() ns.Try("review", attempt, title, 0) end)
end

function R.Init()
  ns.On("PLAYER_REGEN_DISABLED", function()
    fightStart = GetTime()
    if card and card:IsShown() then card:Hide() end
  end)
  ns.On("ENCOUNTER_START", function(enc, name)
    encounter = { name = (not ns.Secret(name) and type(name) == "string") and name or nil }
  end)
  ns.On("ENCOUNTER_END", function(enc, name, _, _, success)
    local mode = ns.db.settings.review
    local title = encounter and encounter.name or ((not ns.Secret(name) and type(name) == "string") and name) or "首領戰"
    encounter = nil
    if mode == "off" then return end
    local won = (not ns.Secret(success)) and (success == 1 or success == true)
    due(title .. (won and "（擊殺）" or "（滅團）"))
    R.bossDone = GetTime()
  end)
  ns.On("PLAYER_REGEN_ENABLED", function()
    local started = fightStart
    fightStart = nil
    if ns.db.settings.review ~= "all" or not started then return end
    if R.bossDone and GetTime() - R.bossDone < 10 then return end      -- 首領戰已經跳過了
    if GetTime() - started < (ns.db.settings.reviewMin or 20) then return end
    due("戰鬥")
  end)
end
ns.Register(R)

-- ---------------------------------------------------------------------------- 分頁
local function buildTab(p)
  local tip = ns.UI.Text(p, "GameFontHighlightSmall",
    "打完一場，跳出這場的輸出、治療摘要（時間、每秒、隊上第幾名、打最多的技能、輸出排名）。數字來自暴雪內建的傷害統計（要開著）。預設只有首領戰結束會自動跳出；野外打怪後想看，按「看上一場」或打 /amobi 檢討。", 430)
  tip:SetPoint("TOPLEFT", 0, 0)
  local modes = { { "boss", "首領戰結束後" }, { "all", "每場戰鬥結束後（打超過 20 秒的）" }, { "off", "不要跳出來" } }
  p.checks = {}
  for i, m in ipairs(modes) do
    local c = ns.UI.Check(p, m[2], function() return ns.db.settings.review == m[1] end, function()
      ns.db.settings.review = m[1]
      for _, x in ipairs(p.checks) do x:Refresh() end
    end)
    c:SetPoint("TOPLEFT", 0, -48 - (i - 1) * 26)
    p.checks[i] = c
  end
  local again = ns.UI.Button(p, "看上一場", 110, 24, function() R.ShowLast() end)
  again:SetPoint("TOPLEFT", 0, -136)
end

local function refreshTab(p)
  for _, c in ipairs(p.checks) do c:Refresh() end
end

ns.UI.AddTab("review", "打完檢討", buildTab, refreshTab)
