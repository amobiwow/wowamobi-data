-- 阿莫比小幫手：PvP 警報（1.9.0，「PvP 警報」分頁；老闆 10/26）
--
-- 老闆：「敵方法師施放 變羊 會有語音說 變羊 這樣蠻方便的 可以提前按 末日顱骨或消失或其他技能來躲避變羊。也有像牧師 戰士的恐懼
-- 術士的死纏之類的語音通報 以及技能CD恢復…如果有UI能提示敵方重要控場技能的冷卻及語音通報 那會非常方便及可以提前預防。
-- 還有一個是附近有敵方陣營玩家會跳出警示以及人名和有幾位玩家，點他右鍵可以設 必殺名單之類的 下次遇到必殺名單裡的玩家會有其他奇特聲音警示」
--
-- 三件事：
--   1. 敵方控場技能的中文語音播報：敵人（玩家和玩家的寵物）開始施放變形術、恐懼術這類有施法時間的就唸，
--      心靈尖嘯、死亡纏繞這類立即的施放後唸。技能清單在 Data/PvPSpells.lua（tools/build_companion_data.py 的 PVP_SPELLS）。
--   2. 敵方技能的冷卻倒數：看到施放就開始算（冷卻秒數照遊戲檔），好了用語音提醒。
--   3. 附近敵方陣營玩家：跳出名字和人數；右鍵加入必殺名單，遇到名單上的人放特別的聲音。
-- 永恆不給插件讀戰鬥紀錄，所以只看得到：目標、專注目標、滑鼠指著的、看得到名條的敵人（UNIT_SPELLCAST_*、NAME_PLATE_UNIT_ADDED）。
-- 看不到的施法就沒有播報、沒有冷卻倒數。戰鬥中、戰場裡遊戲可能把技能編號、名字變成秘密值：秘密值不比對、不當成表的鍵、不存，
-- 那一次就漏掉（另外有一個預設關的選項：讀不到是什麼技能時，把目標正在施放的法術名交給遊戲的語音直接唸，插件不讀它）。
-- 語音用遊戲內建的文字轉語音（C_VoiceChat.SpeakText，用 Windows 裝好的語音，繁中 Windows 有「Microsoft Hanhan」），不用另外做音檔。
-- 不會替你施法、選目標：只讀、只唸、只顯示。名字只在小幫手裡顯示，必殺名單存在你自己的存檔。

local _, ns = ...
local A = {}
ns.PvPAlert = A

local DATA = ns.PvPSpells or { spells = {}, ids = {} }
local CLASS_ZH = { WARRIOR = "戰士", PALADIN = "聖騎士", HUNTER = "獵人", ROGUE = "盜賊", PRIEST = "牧師", SHAMAN = "薩滿",
                   MAGE = "法師", WARLOCK = "術士", DRUID = "德魯伊" }
local KIND_KEY = { cc = "pvpCC", interrupt = "pvpInterrupt", defense = "pvpDefense" }
local VOICE_HINTS = { "Taiwan", "Hanhan", "Yating", "Zhiwei", "Chinese", "中文" }

local NEAR_KEEP = 60        -- 秒：多久沒看到就從附近敵人拿掉
local NEAR_REALERT = 300    -- 秒：同一個人離開又出現，隔多久才再提醒
local NEAR_VOICE_GAP = 10   -- 秒：「敵人」最多幾秒唸一次
local KILL_REALERT = 60     -- 秒：必殺名單的人最多幾秒提醒一次
local SAME_CAST = 1         -- 秒：同一個施放（目標和名條同一個人）只算一次

local db
local function S() return ns.db.settings end
local function now() return GetTime() end
local function str(v) return type(v) == "string" and not ns.Secret(v) and v ~= "" and v or nil end
local function num(v) return type(v) == "number" and not ns.Secret(v) and v or nil end
local function yes(v) return not ns.Secret(v) and v and true or false end

-- ---------------------------------------------------------------------------- 語音
function A.Voices()
  local out = {}
  if not (C_VoiceChat and C_VoiceChat.GetTtsVoices) then return out end
  local ok, list = pcall(C_VoiceChat.GetTtsVoices)
  if not ok or type(list) ~= "table" then return out end
  for _, v in ipairs(list) do
    local id, name = num(v.voiceID), str(v.name)
    if id then out[#out + 1] = { id = id, name = name or ("語音 " .. id) } end
  end
  return out
end

-- 用哪個語音：自己選的；沒選就找名字像中文的（台灣的優先）；都沒有用第一個
function A.Voice()
  local list = A.Voices()
  local pick = S().pvpVoice
  for _, v in ipairs(list) do if v.id == pick then return v end end
  for _, hint in ipairs(VOICE_HINTS) do
    for _, v in ipairs(list) do
      if v.name:find(hint, 1, true) then return v end
    end
  end
  return list[1]
end

function A.NextVoice()
  local list, cur = A.Voices(), A.Voice()
  if #list == 0 then return nil end
  local i = 1
  for k, v in ipairs(list) do if cur and v.id == cur.id then i = k end end
  local nxt = list[i % #list + 1]
  S().pvpVoice = nxt.id
  return nxt
end

local said = {}
A.spoken = 0
-- 唸一句（同一句 1.5 秒內不重複；秘密值的文字交給遊戲直接唸，不比對）
function A.Say(text, force)
  if not S().pvpSpeak or not (C_VoiceChat and C_VoiceChat.SpeakText) then return false end
  if not ns.Secret(text) then
    if type(text) ~= "string" or text == "" then return false end
    if not force and said[text] and now() - said[text] < 1.5 then return false end
    said[text] = now()
  end
  local v = A.Voice()
  local ok = pcall(C_VoiceChat.SpeakText, v and v.id or 0, text, S().pvpRate or 0, S().pvpVolume or 100, false)
  if ok then A.spoken = A.spoken + 1 end
  return ok
end

-- ---------------------------------------------------------------------------- 大字提醒（畫面上方，3 秒淡掉）
local banner
local function Banner(text, r, g, b)
  if not banner then
    banner = CreateFrame("Frame", nil, UIParent)
    banner:SetSize(700, 40)
    banner:SetPoint("TOP", 0, -190)
    banner:SetFrameStrata("HIGH")
    banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    banner.text:SetPoint("CENTER")
  end
  banner.text:SetText(text)
  banner.text:SetTextColor(r or 1, g or 0.82, b or 0)
  banner:SetAlpha(1)
  banner:Show()
  banner.until_ = now() + 3
end
A.Banner = Banner

-- ---------------------------------------------------------------------------- 敵人是誰
local function isEnemy(unit)
  if not yes(UnitCanAttack("player", unit)) then return false end
  return yes(UnitPlayerControlled and UnitPlayerControlled(unit))      -- 玩家或玩家的寵物（地獄獵犬、魅魔）
end

local function same(a, b) return UnitIsUnit and yes(UnitIsUnit(a, b)) end

-- 跟我有關：是目標、專注目標，或它正對著我
local function related(unit)
  if unit == "target" or unit == "focus" or same(unit, "target") or same(unit, "focus") then return true end
  return yes(UnitExists(unit .. "target")) and same(unit .. "target", "player")
end

-- 敵人的全名「主名 次名」：永恆的 UnitName 把次名放在第二個回傳值（「哭哭 不平衡」→ "哭哭", "不平衡"；
-- 阿莫比工作階段 11/8 在公司那台實測），照人口普查（Seen.lua）的 FullName 接回來（1.20.0；老闆：「參考剛剛撈人口的事」）
local function fullName(unit)
  local main, second = UnitName(unit)
  if ns.Seen and ns.Seen.FullName then return ns.Seen.FullName(main, second) end
  return str(main)
end
A.FullName = fullName

local function who(unit)
  local name = fullName(unit)
  local _, token = UnitClass(unit)
  token = str(token)
  return name, token
end

local function colored(text, token)
  local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
  return c and c.colorStr and ("|c" .. c.colorStr .. text .. "|r") or text
end

local function label(unit, sp)
  local name, token = who(unit)
  return colored(name or CLASS_ZH[token or sp.class] or "敵人", token or sp.class)
end

-- ---------------------------------------------------------------------------- 施放、冷卻
local recent = {}           -- [施放的鍵] = 時間（同一次施放從目標、名條各來一次）
A.cds = {}                  -- { key, spell, sp, label, ends, related }

local function seenCast(key)
  local t = recent[key]
  recent[key] = now()
  return t and now() - t < SAME_CAST
end

local function watched(unit)
  return unit == "target" or unit == "focus" or unit == "mouseover" or unit:find("^nameplate%d") ~= nil
end

local function kindOn(sp) return S()[KIND_KEY[sp.kind] or "pvpCC"] ~= false end

function A.StartCd(unit, spell, sp, guid)
  if not S().pvpCd or (sp.cd or 0) <= 0 then return end
  local key = (guid or ("?" .. unit)) .. ":" .. sp.name
  for i = #A.cds, 1, -1 do if A.cds[i].key == key then table.remove(A.cds, i) end end
  table.insert(A.cds, { key = key, spell = spell, sp = sp, label = label(unit, sp), ends = now() + sp.cd, related = related(unit) })
  table.sort(A.cds, function(a, b) return a.ends < b.ends end)
  A.RefreshCds()
end

local function onCast(event, unit, castGUID, spellID)
  if not S().pvpAlert or type(unit) ~= "string" or ns.Secret(unit) or not watched(unit) then return end
  if not isEnemy(unit) then return end
  local spell = num(spellID)
  if not spell then
    -- 讀不到是什麼技能（秘密值）：選項打開時，目標、專注目標開始施法就把法術名交給遊戲直接唸
    if S().pvpSecretCast and event ~= "UNIT_SPELLCAST_SUCCEEDED" and (unit == "target" or unit == "focus") then
      local name = UnitCastingInfo(unit)
      if not name and event == "UNIT_SPELLCAST_CHANNEL_START" then name = UnitChannelInfo(unit) end
      if name then A.Say(name) end
    end
    A.missed = (A.missed or 0) + 1
    return
  end
  local idx = DATA.ids[spell]
  local sp = idx and DATA.spells[idx]
  if not sp then return end
  local guid = str(UnitGUID(unit))
  local castKey = (str(castGUID) or ((guid or "?") .. spell)) .. event
  if seenCast(castKey) then return end
  local start = event ~= "UNIT_SPELLCAST_SUCCEEDED"
  if event == "UNIT_SPELLCAST_SUCCEEDED" then A.StartCd(unit, spell, sp, guid) end
  if start ~= (sp.cast and true or false) then return end            -- 有施法時間的開始就唸，立即的施放後唸
  if not S().pvpCast or not kindOn(sp) then return end
  if not S().pvpCastAll and not related(unit) then return end
  A.Say(sp.voice)
  Banner(label(unit, sp) .. (start and " 正在施放 " or " 施放了 ") .. sp.name, 1, 0.3, 0.2)
  A.announced = (A.announced or 0) + 1
end

function A.TickCds()
  local t, changed = now(), false
  for i = #A.cds, 1, -1 do
    local c = A.cds[i]
    if t >= c.ends then
      table.remove(A.cds, i)
      changed = true
      if S().pvpCdVoice and c.related and kindOn(c.sp) then A.Say(c.sp.voice .. "好了") end
    end
  end
  if changed or #A.cds > 0 then A.RefreshCds() end
  if banner and banner:IsShown() and banner.until_ then
    local left = banner.until_ - t
    if left <= 0 then banner:Hide() elseif left < 1 then banner:SetAlpha(left) end
  end
end

-- ---------------------------------------------------------------------------- 附近敵人、必殺名單
A.near = {}                 -- [名字] = { name, class, level, seen }
local plates = {}           -- 看得到的名條
local alerted, lastNearVoice = {}, -1e9

-- 必殺名單的名字：全名「主名 次名」或只有主名都可以（1.20.0 前只記得到主名，舊的照認）
local function mainOf(name) return name:match("^(%S+)") end
local function clean(name)
  name = str(name)
  if not name then return nil end
  name = (name:gsub("%-[^%s%-]*$", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "))
  return name ~= "" and name or nil
end

-- 這個名字對到名單上的哪一筆：全名一樣；名單上只寫主名的，主名一樣；看到的只有主名的，名單上的主名一樣
function A.KillKey(name)
  name = clean(name)
  if not name then return nil end
  if db.kill[name] then return name end
  local main = mainOf(name)
  if main ~= name and db.kill[main] then return main end
  if main == name then
    for k in pairs(db.kill) do
      if mainOf(k) == name then return k end
    end
  end
  return nil
end

function A.IsKill(name) return A.KillKey(name) ~= nil end

function A.ToggleKill(name, class, level)
  name = clean(name)
  if not name then return nil end
  local have = A.KillKey(name)
  if have then
    db.kill[have] = nil
    ns.Print(("「%s」移出必殺名單。"):format(have))
    name = have
  else
    db.kill[name] = { t = time(), class = class, level = level }
    ns.Print(("「%s」加入必殺名單：下次遇到會有特別的聲音。"):format(name))
  end
  A.RefreshNear()
  ns.UI.Refresh("pvpalert")
  return db.kill[name] ~= nil
end

local function killAlert(e)
  if alerted["!" .. e.name] and now() - alerted["!" .. e.name] < KILL_REALERT then return end
  alerted["!" .. e.name] = now()
  if PlaySound then
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
    if C_Timer then C_Timer.After(0.35, function() pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master") end) end
  end
  A.Say("必殺 " .. e.name, true)
  Banner("必殺名單：" .. colored(e.name, e.class) .. " 出現了！", 1, 0.1, 0.1)
  A.killAlerts = (A.killAlerts or 0) + 1
end

function A.SeeUnit(unit)
  if not S().pvpAlert or not S().pvpNearby or not yes(UnitExists(unit)) then return end
  if not yes(UnitIsPlayer(unit)) then return end
  local fac, mine = str(UnitFactionGroup(unit)), str(UnitFactionGroup("player"))
  if not fac or not mine or fac == mine or not yes(UnitCanAttack("player", unit)) then return end
  local name = fullName(unit)
  if not name then A.missed = (A.missed or 0) + 1; return end     -- 名字是秘密值：這次不記
  local _, token = UnitClass(unit)
  local e = A.near[name]
  local fresh = not e
  e = e or { name = name }
  e.class, e.level, e.seen = str(token) or e.class, num(UnitLevel(unit)) or e.level, now()
  A.near[name] = e
  if fresh then
    if A.IsKill(name) then
      killAlert(e)
    elseif not alerted[name] or now() - alerted[name] > NEAR_REALERT then
      alerted[name] = now()
      local lv = e.level and e.level > 0 and (" " .. e.level) or ""
      Banner("附近有敵人：" .. colored(name, e.class) .. "（" .. (CLASS_ZH[e.class] or "") .. lv .. "）", 1, 0.55, 0.1)
      if S().pvpNearbyVoice and now() - lastNearVoice > NEAR_VOICE_GAP then
        lastNearVoice = now()
        A.Say("敵人")
      end
    end
  end
  A.RefreshNear()
end

function A.TickNear()
  for unit in pairs(plates) do
    if yes(UnitExists(unit)) then A.SeeUnit(unit) else plates[unit] = nil end
  end
  local t, changed = now(), false
  for name, e in pairs(A.near) do
    if t - e.seen > NEAR_KEEP then A.near[name] = nil; changed = true end
  end
  if changed then A.RefreshNear() end
end

function A.NearList()
  local list = {}
  for _, e in pairs(A.near) do list[#list + 1] = e end
  table.sort(list, function(a, b)
    local ka, kb = A.IsKill(a.name), A.IsKill(b.name)
    if ka ~= kb then return ka end
    return a.seen > b.seen
  end)
  return list
end

-- ---------------------------------------------------------------------------- 畫面上的兩個小框（可以拖）
local cdFrame, nearFrame
local ROWS = 8

local function smallFrame(key, title, point, x, y)
  local f = ns.UI.Panel(UIParent, 220, 24, "MEDIUM")
  ns.UI.Place(f, key, point, UIParent, point, x, y)
  ns.UI.Movable(f, key)
  f.title = ns.UI.Text(f, "GameFontNormalSmall", title)
  f.title:SetPoint("TOPLEFT", 6, -5)
  f.rows = {}
  f:Hide()
  return f
end

function A.RefreshCds()
  if not S().pvpAlert or not S().pvpCd or #A.cds == 0 then
    if cdFrame then cdFrame:Hide() end
    return
  end
  if not cdFrame then cdFrame = smallFrame("pvpCdPos", ns.GOLD .. "敵方技能冷卻|r", "RIGHT", -260, 60); A.cdFrame = cdFrame end
  local t = now()
  for i = 1, ROWS do
    local c = A.cds[i]
    local row = cdFrame.rows[i]
    if c and not row then
      row = ns.UI.Text(cdFrame, "GameFontHighlightSmall", "", 210)
      row:SetPoint("TOPLEFT", 6, -6 - 15 * i)
      cdFrame.rows[i] = row
    end
    if row then
      if c then
        row:SetText(("%s %s  |cffffd040%d|r"):format(c.label, c.sp.name, math.ceil(c.ends - t)))
        row:Show()
      else
        row:Hide()
      end
    end
  end
  cdFrame:SetHeight(24 + 15 * math.min(ROWS, #A.cds))
  cdFrame:Show()
end

function A.RefreshNear()
  local list = A.NearList()
  if not S().pvpAlert or not S().pvpNearby or #list == 0 then
    if nearFrame then nearFrame:Hide() end
    return
  end
  if not nearFrame then nearFrame = smallFrame("pvpNearPos", "", "RIGHT", -260, -80); A.nearFrame = nearFrame end
  nearFrame.title:SetText(ns.GOLD .. "附近敵人 " .. #list .. "|r  |cff9d9d9d右鍵：必殺名單|r")
  for i = 1, ROWS do
    local e = list[i]
    local row = nearFrame.rows[i]
    if e and not row then
      row = CreateFrame("Button", nil, nearFrame)
      row:SetSize(210, 14)
      row:SetPoint("TOPLEFT", 6, -6 - 15 * i)
      row.text = ns.UI.Text(row, "GameFontHighlightSmall", "", 210)
      row.text:SetPoint("LEFT")
      row:RegisterForClicks("RightButtonUp")
      row:SetScript("OnClick", function(self, button)
        if button == "RightButton" and self.entry then ns.Try("pvp-kill", A.ToggleKill, self.entry.name, self.entry.class, self.entry.level) end
      end)
      nearFrame.rows[i] = row
    end
    if row then
      if e then
        row.entry = e
        local lv = e.level and e.level > 0 and (" " .. e.level) or ""
        row.text:SetText((A.IsKill(e.name) and "|cffff2020【必殺】|r" or "") .. colored(e.name, e.class) ..
          " |cff9d9d9d" .. (CLASS_ZH[e.class] or "") .. lv .. "|r")
        row:Show()
      else
        row.entry = nil
        row:Hide()
      end
    end
  end
  nearFrame:SetHeight(24 + 15 * math.min(ROWS, #list))
  nearFrame:Show()
end

-- 目標頭像的右鍵選單加「加入必殺名單」（遊戲給插件加選單的 Menu.ModifyMenu；沒有這個功能就只用附近敵人框的右鍵）
local function hookMenu()
  if not (Menu and Menu.ModifyMenu) then return end
  pcall(Menu.ModifyMenu, "MENU_UNIT_ENEMY_PLAYER", function(_, root, context)
    local name = context and str(context.name)
    if not name or not root or not root.CreateButton then return end
    local surname = str(context.surname)                       -- 永恆的選單資料有次名（NameUtil 用 name、surname）
    if surname and not name:find(" ", 1, true) then name = name .. " " .. surname end
    name = (name:gsub("%-[^%s%-]*$", ""))
    if root.CreateDivider then root:CreateDivider() end
    root:CreateButton(A.IsKill(name) and "移出必殺名單（阿莫比）" or "加入必殺名單（阿莫比）", function()
      ns.Try("pvp-kill", A.ToggleKill, name)
    end)
  end)
end

function A.Init()
  ns.db.pvpAlert = type(ns.db.pvpAlert) == "table" and ns.db.pvpAlert or {}
  db = ns.db.pvpAlert
  db.kill = type(db.kill) == "table" and db.kill or {}
  for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_SUCCEEDED" }) do
    ns.On(e, function(unit, castGUID, spellID) onCast(e, unit, castGUID, spellID) end)
  end
  ns.On("NAME_PLATE_UNIT_ADDED", function(unit)
    if type(unit) == "string" and not ns.Secret(unit) then plates[unit] = true; A.SeeUnit(unit) end
  end)
  ns.On("NAME_PLATE_UNIT_REMOVED", function(unit) if type(unit) == "string" and not ns.Secret(unit) then plates[unit] = nil end end)
  ns.On("PLAYER_TARGET_CHANGED", function() A.SeeUnit("target") end)
  ns.On("PLAYER_FOCUS_CHANGED", function() A.SeeUnit("focus") end)
  ns.On("UPDATE_MOUSEOVER_UNIT", function() A.SeeUnit("mouseover") end)
  C_Timer.NewTicker(0.2, function() ns.Try("pvp-cd", A.TickCds) end)
  C_Timer.NewTicker(2, function() ns.Try("pvp-near", A.TickNear) end)
  hookMenu()
end
ns.Register(A)

-- ---------------------------------------------------------------------------- 分頁
local function buildTab(p)
  A.page = p
  local tip = ns.UI.Text(p, "GameFontHighlightSmall",
    "敵人施放控場技能時用中文語音唸出來、算它的冷卻，附近有敵方陣營玩家時跳出名字。永恆不給插件讀戰鬥紀錄，" ..
    "只看得到目標、專注目標、滑鼠指著的和看得到名條的敵人；戰鬥中遊戲把技能、名字藏起來時會漏掉一些。", 430)
  tip:SetPoint("TOPLEFT", 0, 0)
  p.checks = {}
  local function check(y, x, text, key)
    local c = ns.UI.Check(p, text, function() return S()[key] end, function(v)
      S()[key] = v
      for _, c2 in ipairs(p.checks) do c2:Refresh() end
      A.RefreshCds()
      A.RefreshNear()
    end)
    c:SetPoint("TOPLEFT", x, y)
    p.checks[#p.checks + 1] = c
  end
  check(-48, 0, "打開 PvP 警報", "pvpAlert")
  check(-72, 20, "敵方控場技能語音播報（變羊、恐懼、死亡纏繞…）", "pvpCast")
  check(-94, 40, "控場", "pvpCC")
  check(-94, 110, "打斷", "pvpInterrupt")
  check(-94, 180, "保命（聖盾、寒冰屏障、消失…）", "pvpDefense")
  check(-116, 40, "看得到的敵人全部唸（不勾：只唸目標、專注目標和對著我的）", "pvpCastAll")
  check(-140, 20, "敵方技能冷卻倒數（看到施放才算）", "pvpCd")
  check(-162, 40, "冷卻好了用語音提醒（目標、專注目標和對著我的）", "pvpCdVoice")
  check(-186, 20, "附近敵方陣營玩家警示（名字、人數）", "pvpNearby")
  check(-208, 40, "新出現的敵人唸「敵人」", "pvpNearbyVoice")
  check(-232, 20, "讀不到是什麼技能時，唸目標正在施放的法術（會比較吵）", "pvpSecretCast")
  check(-256, 20, "用語音（不勾只跳大字）", "pvpSpeak")
  p.voice = ns.UI.Text(p, "GameFontHighlightSmall", "", 430)
  p.voice:SetPoint("TOPLEFT", 0, -288)
  local nextVoice = ns.UI.Button(p, "換一個語音", 100, 22, function()
    local v = A.NextVoice()
    p.msg:SetText(v and ("改用：" .. v.name) or "遊戲裡沒有可以用的語音。")
    ns.UI.Refresh("pvpalert")
  end)
  nextVoice:SetPoint("TOPLEFT", 0, -306)
  local test = ns.UI.Button(p, "試聽", 70, 22, function()
    if not A.Say("變羊", true) then p.msg:SetText("唸不出來：這個遊戲版本沒有文字轉語音，或「用語音」沒勾。") end
  end)
  test:SetPoint("TOPLEFT", 106, -306)
  p.msg = ns.UI.Text(p, "GameFontHighlightSmall", "", 250)
  p.msg:SetPoint("TOPLEFT", 182, -310)
  local head = ns.UI.Text(p, "GameFontNormal", ns.GOLD .. "必殺名單|r")
  head:SetPoint("TOPLEFT", 0, -342)
  local how = ns.UI.Text(p, "GameFontDisableSmall",
    "在畫面右邊的「附近敵人」框按右鍵加入或移出；也可以在這裡打名字按「加入／移出」（打全名「主名 次名」，或只打主名都可以：只打主名的話，主名一樣的人都會響）。", 430)
  how:SetPoint("TOPLEFT", 0, -362)
  p.edit = ns.UI.Edit(p, 160, 22)
  p.edit:SetPoint("TOPLEFT", 4, -392)
  local add = ns.UI.Button(p, "加入／移出", 96, 22, function()
    local name = strtrim(p.edit:GetText() or "")
    if name ~= "" then A.ToggleKill(name) end
    p.edit:SetText("")
  end)
  add:SetPoint("LEFT", p.edit, "RIGHT", 8, 0)
  p.add = add
  p.kills = ns.UI.Text(p, "GameFontHighlightSmall", "", 430)
  p.kills:SetPoint("TOPLEFT", 0, -424)
end

local function refreshTab(p)
  for _, c in ipairs(p.checks) do c:Refresh() end
  local v = A.Voice()
  p.voice:SetText("語音：" .. (v and v.name or "|cffff8040遊戲裡沒有可以用的語音|r") ..
    (v and not (v.name:find("Chinese", 1, true) or v.name:find("Taiwan", 1, true) or v.name:find("Hanhan", 1, true)
      or v.name:find("中文", 1, true)) and "（看起來不是中文語音，中文可能唸不出來）" or ""))
  local names = {}
  for name in pairs(db.kill) do names[#names + 1] = name end
  table.sort(names)
  p.kills:SetText(#names == 0 and "還沒有人。" or (#names .. " 人：" .. table.concat(names, "、")))
end

ns.UI.AddTab("pvpalert", "PvP 警報", buildTab, refreshTab)
