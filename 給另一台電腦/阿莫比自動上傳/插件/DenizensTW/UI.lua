--[[ Denizens TW UI -------------------------------------------------------

Built from primitives on purpose. Forever removed WhoFrame, so there is no
Blizzard who-window to reskin, and rather than bet on which other UI templates
survived the port this file uses only CreateFrame, textures, fontstrings and a
slider. Nothing here can break because a template was renamed.

Fork changes: class and race pickers list the client's own localized names
(and Skyborne), the window does no work while it is hidden, a click-mode hint
appears while a scan waits for clicks, and the slash commands gained
scan / auto / status / mode, with wipe now asking for confirmation.
--]]

local ADDON, ns = ...
local L = ns.L

local ROW_H, VISIBLE = 18, 16
local COLUMNS = {
    { key = "name",  title = L["Name"],  width = 130 },
    { key = "level", title = L["Lvl"],   width = 34  },
    { key = "class", title = L["Class"], width = 74  },
    { key = "race",  title = L["Race"],  width = 74  },
    { key = "zone",  title = L["Zone"],  width = 120 },
    { key = "guild", title = L["Guild"], width = 130 },
}

local sortKey, sortDesc, offset = "level", false, 0
local view = {}
local uiDirty = false

local function classItems()
    local list = { "" }
    for _, n in ipairs((ns.ClassNames())) do list[#list + 1] = n end
    return list
end

local function raceItems()
    local list = { "" }
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    for _, n in ipairs((ns.RaceNames(faction))) do list[#list + 1] = n end
    return list
end

--==========================================================================
-- small widget helpers
--==========================================================================

local function panel(parent, r, g, b, a)
    local t = parent:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(parent)
    t:SetColorTexture(r, g, b, a)
    return t
end

local function label(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function editbox(parent, x, y, w)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetPoint("TOPLEFT", x, y)
    e:SetSize(w, 18)
    e:SetAutoFocus(false)
    e:SetFontObject("ChatFontNormal")
    e:SetTextInsets(4, 4, 0, 0)
    panel(e, 0, 0, 0, 0.5)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    return e
end

-- A self-contained dropdown whose items can be replaced after login, once the
-- client's localized class and race names and the player's faction are known.
local function dropdown(parent, x, y, w, items, onPick)
    local b = CreateFrame("Button", nil, parent)
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(w, 18)
    panel(b, 0, 0, 0, 0.5)
    b.text = b:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetText(L["Any"])
    b.value = ""

    local list = CreateFrame("Frame", nil, b)
    list:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
    panel(list, 0.05, 0.05, 0.05, 0.95)
    list:SetFrameStrata("DIALOG")
    list:Hide()
    local pool = {}

    function b.SetItems(_, newItems)
        for i, item in ipairs(newItems) do
            local row = pool[i]
            if not row then
                row = CreateFrame("Button", nil, list)
                row:SetPoint("TOPLEFT", 2, -(i - 1) * ROW_H - 2)
                row:SetSize(w - 4, ROW_H)
                row.fs = row:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
                row.fs:SetPoint("LEFT", 3, 0)
                -- Create the highlight ONCE, not on every mouse-over.
                local hl = row:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(row)
                hl:SetColorTexture(1, 1, 1, 0.15)
                row:SetScript("OnClick", function(self)
                    b.value = self.item
                    b.text:SetText(self.item == "" and L["Any"] or self.item)
                    list:Hide()
                    if onPick then onPick(self.item) end
                end)
                pool[i] = row
            end
            row.item = item
            row.fs:SetText(item == "" and L["Any"] or item)
            row:Show()
        end
        for i = #newItems + 1, #pool do pool[i]:Hide() end
        list:SetSize(w, #newItems * ROW_H + 4)
    end
    b:SetItems(items)

    b:SetScript("OnClick", function()
        if list:IsShown() then list:Hide() else list:Show() end
    end)
    return b
end

--==========================================================================
-- the window
--==========================================================================

local f = CreateFrame("Frame", "DenizensTWFrame", UIParent)
f:SetSize(600, 536)
f:SetPoint("CENTER")
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:SetFrameStrata("HIGH")
f:Hide()
panel(f, 0.06, 0.06, 0.07, 0.94)

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 12, -10)
title:SetText("Denizens TW")

local close = CreateFrame("Button", nil, f)
close:SetSize(20, 20)
close:SetPoint("TOPRIGHT", -8, -8)
local ct = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
ct:SetAllPoints()
ct:SetText("x")
close:SetScript("OnClick", function() f:Hide() end)

-- ---- query builder -------------------------------------------------------
label(f, L["Name"],  14, -40);  local eName  = editbox(f, 14, -54, 120)
label(f, L["Guild"], 142, -40); local eGuild = editbox(f, 142, -54, 130)
label(f, L["Zone"],  280, -40); local eZone  = editbox(f, 280, -54, 130)
label(f, L["Level"], 418, -40)
local eMin = editbox(f, 418, -54, 34)
local eMax = editbox(f, 458, -54, 34)
eMin:SetNumeric(true); eMax:SetNumeric(true)

label(f, L["Class"], 14, -80)
label(f, L["Race"],  142, -80)
local dClass, dRace

local eRaw   -- forward declaration; the builder writes into it

local function spec()
    return {
        name = eName:GetText(), guild = eGuild:GetText(), zone = eZone:GetText(),
        class = dClass and dClass.value or "", race = dRace and dRace.value or "",
        minLevel = tonumber(eMin:GetText()), maxLevel = tonumber(eMax:GetText()),
    }
end

local function refreshRaw()
    if eRaw then eRaw:SetText(ns.BuildQuery(spec())) end
end

dClass = dropdown(f, 14, -94, 120, classItems(), refreshRaw)
dRace  = dropdown(f, 142, -94, 130, raceItems(), refreshRaw)

for _, e in ipairs({ eName, eGuild, eZone, eMin, eMax }) do
    e:SetScript("OnTextChanged", refreshRaw)
end

label(f, L["Query sent"], 14, -120)
eRaw = editbox(f, 14, -134, 400)

local function doSearch()
    ns.UserSearch(eRaw:GetText())
end

-- Every button click is a hardware event, so it may carry a query even in
-- click mode.
local function button(parent, text, x, y, w, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(w, 20)
    panel(b, 0.18, 0.30, 0.42, 1)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetAllPoints()
    fs:SetText(text)
    b.label = fs          -- so callers can relabel without guessing at regions
    b:SetScript("OnClick", function() ns.WithHardware(onClick) end)
    return b
end

button(f, L["Search"], 420, -134, 74, doSearch)
button(f, L["Deep scan"], 500, -134, 84, function() ns.DeepScan(spec()) end)

-- ---- client-side filter --------------------------------------------------
label(f, L["Filter results"], 14, -160)
local eFilter = editbox(f, 96, -160, 200)
local status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
status:SetPoint("TOPLEFT", 310, -160)

-- ---- column headers ------------------------------------------------------
local headerY = -190
local x = 14
for _, col in ipairs(COLUMNS) do
    local b = CreateFrame("Button", nil, f)
    b:SetPoint("TOPLEFT", x, headerY)
    b:SetSize(col.width, ROW_H)
    panel(b, 0.14, 0.14, 0.16, 1)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", 3, 0)
    col.fs = fs
    b:SetScript("OnClick", function()
        if sortKey == col.key then sortDesc = not sortDesc
        else sortKey, sortDesc = col.key, false end
        offset = 0
        ns.OnResults()
    end)
    x = x + col.width
end

-- ---- rows ----------------------------------------------------------------
local rows = {}
for i = 1, VISIBLE do
    local r = CreateFrame("Button", nil, f)
    r:SetPoint("TOPLEFT", 14, headerY - i * ROW_H - 2)
    r:SetSize(562, ROW_H)
    r.cells = {}
    local cx = 0
    for ci, col in ipairs(COLUMNS) do
        local fs = r:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
        fs:SetPoint("LEFT", cx + 3, 0)
        fs:SetWidth(col.width - 6)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        r.cells[ci] = fs

        -- Invisible catcher per cell: FontStrings take no mouse input, so a
        -- truncated value has nothing to hover. Shows the full string only
        -- when it is genuinely cut off.
        local hit = CreateFrame("Frame", nil, r)
        hit:SetPoint("LEFT", cx, 0)
        hit:SetSize(col.width, ROW_H)
        hit:EnableMouse(true)
        if hit.SetPropagateMouseClicks then hit:SetPropagateMouseClicks(true) end
        if hit.SetPropagateMouseMotion then hit:SetPropagateMouseMotion(true) end
        hit:SetScript("OnEnter", function(self)
            local cell = r.cells[ci]
            if cell and cell:GetText() and ns.IsClipped(cell) then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                -- This client's signature is SetText(text [, color, alpha, wrap]).
                GameTooltip:SetText(cell:GetText())
                GameTooltip:Show()
            end
        end)
        hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if not hit.SetPropagateMouseClicks then
            hit:SetScript("OnMouseUp", function()
                if r.name then ChatFrame_OpenChat("/w " .. r.name .. " ") end
            end)
        end

        cx = cx + col.width
    end
    -- Clicking a row fills the chat box with a whisper; nothing is ever sent
    -- on the player's behalf.
    r:SetScript("OnClick", function()
        if r.name then ChatFrame_OpenChat("/w " .. r.name .. " ") end
    end)
    rows[i] = r
end

local slider = CreateFrame("Slider", nil, f)
slider:SetPoint("TOPRIGHT", -8, headerY - 2)
slider:SetSize(14, VISIBLE * ROW_H)
slider:SetOrientation("VERTICAL")
slider:SetMinMaxValues(0, 0)
slider:SetValueStep(1)
slider:SetObeyStepOnDrag(true)
panel(slider, 0, 0, 0, 0.4)
local thumb = slider:CreateTexture(nil, "ARTWORK")
thumb:SetColorTexture(0.45, 0.55, 0.65, 1)
thumb:SetSize(14, 28)
slider:SetThumbTexture(thumb)
slider:SetScript("OnValueChanged", function(_, v)
    offset = math.floor(v + 0.5)
    ns.Redraw()
end)

f:EnableMouseWheel(true)
f:SetScript("OnMouseWheel", function(_, delta)
    slider:SetValue(offset - delta)
end)

-- ---- census strip --------------------------------------------------------
-- "active" is the defensible figure, "known" is an upper bound that can only
-- grow because a deleted character is indistinguishable from an absent one.
local censusLine = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
censusLine:SetPoint("TOPLEFT", 338, -506)
censusLine:SetPoint("TOPRIGHT", -14, -506)
censusLine:SetJustifyH("LEFT")

local function printCensus()
    local stats = ns.Census.Stats()
    for _, line in ipairs(ns.Census.Summary(stats)) do ns.say(line) end
    local top = ns.Census.TopGuilds(8, stats)
    if #top > 0 then
        ns.say("  " .. L["top guilds:"])
        for _, g in ipairs(top) do
            ns.say(string.format("    %-28s %d", g.name, g.count))
        end
    end
end

button(f, L["Census report"], 14, -502, 100, printCensus)
button(f, L["Full census"], 120, -502, 100, function() ns.FullScan() end)

-- Only visible while a scan is running. In click mode it is also the "send
-- the next query" button, which a click is allowed to do.
local stepBtn = button(f, L["Cancel (%d)"], 226, -502, 104, function()
    if ns.hardwareGated and ns.QueueDepth() > 0 then
        ns.Step()
    else
        ns.CancelScan()
    end
end)
stepBtn:Hide()

local function refreshStep()
    local q = ns.QueueDepth()
    if q == 0 then stepBtn:Hide(); return end
    stepBtn:Show()
    stepBtn.label:SetText(string.format(
        ns.hardwareGated and L["Continue (%d)"] or L["Cancel (%d)"], q))
end

-- Stats walk the whole roster (up to 100,000 entries): never on every reply,
-- and never while the window is hidden.
local lastCensusRefresh = -1e9
local function refreshCensus(force)
    if not f:IsShown() then return end
    if not force and GetTime() - lastCensusRefresh < 5 then return end
    if not (ns.Census and ns.Census.Stats) then return end
    lastCensusRefresh = GetTime()
    local ok, s = pcall(ns.Census.Stats)
    if not ok or not s then return end
    censusLine:SetText(string.format(L["roster: |cff66ff66%d|r active (7d)   %d known ever   %d guilds"],
        s.active, s.known, s.guilds))
end

--==========================================================================
-- click-mode hint: says what to do while a scan waits for clicks
--==========================================================================

local hint = CreateFrame("Frame", "DenizensTWClickHint", UIParent)
hint:SetSize(560, 24)
hint:SetPoint("TOP", 0, -140)
hint:SetFrameStrata("HIGH")
hint:EnableMouse(false)      -- must never eat the very clicks it asks for
panel(hint, 0, 0, 0, 0.55)
hint.text = hint:CreateFontString(nil, "OVERLAY", "GameFontNormal")
hint.text:SetAllPoints()
hint:Hide()

local function refreshHint()
    local q = ns.QueueDepth()
    if ns.hardwareGated and q > 0 then
        hint.text:SetText(string.format(
            L["Click mode: %d queries left. Click the game world, move or use an ability to send the next one."], q))
        hint:Show()
    else
        hint:Hide()
    end
end

--==========================================================================
-- drawing
--==========================================================================

function ns.Redraw()
    for i = 1, VISIBLE do
        local row, data = rows[i], view[i + offset]
        if data then
            row.name = data.name
            local colour = RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.token]
            for ci, col in ipairs(COLUMNS) do
                local v = data[col.key]
                row.cells[ci]:SetText(v ~= "" and tostring(v) or "-")
                if col.key == "name" and colour then
                    row.cells[ci]:SetTextColor(colour.r, colour.g, colour.b)
                else
                    row.cells[ci]:SetTextColor(0.85, 0.85, 0.85)
                end
            end
            row:Show()
        else
            row.name = nil
            row:Hide()
        end
    end
end

-- Called by Core whenever the result set changes.
function ns.OnResults()
    pcall(refreshHint)
    if not f:IsShown() then
        uiDirty = true        -- catch up in OnShow; no sorting for nobody
        return
    end
    uiDirty = false
    view = ns.Filter(ns.results, eFilter:GetText())
    ns.Sort(view, sortKey, sortDesc)

    for _, col in ipairs(COLUMNS) do
        local arrow = ""
        if col.key == sortKey then arrow = sortDesc and "  v" or "  ^" end
        col.fs:SetText(col.title .. arrow)
    end

    local max = math.max(0, #view - VISIBLE)
    slider:SetMinMaxValues(0, max)
    if offset > max then offset = max end
    slider:SetValue(offset)

    local msg = string.format(L["%d shown"], #view)
    if #view ~= #ns.results then
        msg = msg .. string.format(L[" of %d"], #ns.results)
    end
    -- The honesty line. Exactly the cap means the server stopped counting.
    if #ns.results == ns.CAP then
        msg = msg .. "  |cffffd100" .. L["(capped - try Deep scan)"] .. "|r"
    end
    local q = ns.QueueDepth()
    if q > 0 then msg = msg .. "  |cff88ccff" .. string.format(L["[%d queued]"], q) .. "|r" end
    status:SetText(msg)

    -- Draw the rows FIRST. Everything below is cosmetic and may not stop the
    -- list rendering.
    ns.Redraw()

    local ok, err = pcall(refreshCensus)
    if not ok then ns.warn("census strip: " .. tostring(err)) end
    ok, err = pcall(refreshStep)
    if not ok then ns.warn("scan button: " .. tostring(err)) end
end

ns.OnScanDone = ns.OnResults
ns.OnModeChanged = function()
    pcall(refreshHint)
    pcall(refreshStep)
end

f:SetScript("OnShow", function()
    ns.OnResults()            -- catches up on anything that arrived while hidden
    pcall(refreshCensus, true)
end)

-- The queue changes between replies, and replies can be 12 seconds apart once
-- the throttle backs off. Poll the two integers that matter.
if C_Timer then
    C_Timer.NewTicker(0.5, function()
        pcall(refreshHint)
        if ns.InstallWhoMover then pcall(ns.InstallWhoMover) end
        if not f:IsShown() then return end
        pcall(refreshStep)
        local q = ns.QueueDepth()
        if q > 0 then
            status:SetText(string.format(L["%d shown"], #view) .. "  |cff88ccff"
                .. string.format(L["[%d queued]"], q) .. "|r")
        end
    end)
end
eFilter:SetScript("OnTextChanged", function() offset = 0; ns.OnResults() end)
eRaw:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    ns.WithHardware(doSearch)
end)

-- Once logged in, the localized names and the player's faction are known:
-- rebuild the pickers so they only offer what /who can actually match.
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function()
    pcall(function()
        dClass:SetItems(classItems())
        dRace:SetItems(raceItems())
    end)
end)

--==========================================================================
-- entry point
--==========================================================================

local isZh = (ns.locale == "zhTW" or ns.locale == "zhCN")
local HELP = isZh and {
    "|cffffd100/dz scan|r            完整普查 (所有在線玩家，自動突破 50 人上限)",
    "|cffffd100/dz auto 30|r         自動普查：每 30 分鐘一輪 (暫離或戰鬥中暫停)，/dz auto off 關閉",
    "|cffffd100/dz auto 0|r          連續普查：一輪做完 10 秒後自動下一輪 (也可以打 /dz 連續；點擊還是你自己按)",
    "|cffffd100/dz status|r          目前模式、進度、客戶端資訊",
    "|cffffd100/dz stop|r            中止掃描 (已掃到的會保留)",
    "|cffffd100/dz census|r          普查統計",
    "|cffffd100/dz|r                 打開視窗",
    "|cffffd100/dz <條件>|r          查詢，例如 /dz z-\"艾爾文森林\" 4-10",
    "|cffffd100/dz deep [條件]|r     依條件深度掃描",
    "|cffffd100/dz mode auto|r 或 |cffffd100/dz mode click|r   手動切換自動或點擊模式",
    "|cffffd100/dz wipe confirm|r    清空這個伺服器與陣營的資料",
    "|cffffd100/dz debug|r           查看最近的內部記錄",
    "|cffffd100/dz keys on|r 或 |cffffd100/dz keys off|r   點擊模式下，走路、跳、放技能要不要順便送出查詢 (預設開)",
    "|cffffd100/dz whopos|r 或 |cffffd100/dz whopos reset|r   「尋求組隊」視窗能不能拖、位置記住沒；加 reset 回到原位",
    "點擊模式下：點一下遊戲畫面、走路、跳或放技能，都會送出下一筆。也可以到「按鍵設定 > 插件」綁一個快捷鍵。",
} or {
    "|cffffd100/dz scan|r            full census of everyone online (gets past the 50 cap)",
    "|cffffd100/dz auto 30|r         a full pass every 30 min while you play (paused when AFK or in combat); /dz auto off",
    "|cffffd100/dz auto 0|r          back to back: the next pass starts 10 s after one finishes (your clicks still send each query)",
    "|cffffd100/dz status|r          mode, progress, client info",
    "|cffffd100/dz stop|r            stop a running scan (keeps what it found)",
    "|cffffd100/dz census|r          what the saved roster knows",
    "|cffffd100/dz|r                 open the window",
    "|cffffd100/dz <query>|r         search, e.g. /dz z-\"Elwynn Forest\" 4-10",
    "|cffffd100/dz deep [query]|r    deep scan a query",
    "|cffffd100/dz mode auto|r or |cffffd100/dz mode click|r   force automatic or click mode",
    "|cffffd100/dz wipe confirm|r    clear the saved roster for this realm and faction",
    "|cffffd100/dz debug|r           show the recent internal log",
    "|cffffd100/dz keys on|r or |cffffd100/dz keys off|r   in click mode, let moving, jumping and abilities send queries too (on by default)",
    "|cffffd100/dz whopos|r or |cffffd100/dz whopos reset|r   can the Find Group window be dragged, is its spot saved; reset puts it back",
    "In click mode every click in the game world, step, jump or ability sends the next query; you can also bind a key (Key Bindings > AddOns).",
}

local function printStatus()
    local mode = ns.hardwareGated and L["click"] or L["automatic"]
    ns.say(string.format(L["mode: %s   queue: %d   gap: %.1fs   sent this session: %d   no reply: %d"],
        mode, ns.QueueDepth(), ns.CurrentGap(), ns.stats.sent, ns.stats.timeouts))
    local off = ns.CarriersOff and ns.CarriersOff() or {}
    if #off > 0 then
        local names = { key = L["moving and abilities"], combat = L["combat"], click = L["clicks"] }
        local shown = {}
        for _, k in ipairs(off) do shown[#shown + 1] = names[k] or k end
        ns.say(string.format(L["turned off after the game refused them: %s"], table.concat(shown, "、")))
    end
    if (ns.stats.throttled or 0) > 0 or (ns.stats.foreign or 0) > 0 then
        ns.say(string.format(L["server said too fast: %d   replies that were not ours: %d"],
            ns.stats.throttled or 0, ns.stats.foreign or 0))
    end
    if ns.hardwareGated then
        local s0 = DenizensTWDB and DenizensTWDB.settings
        ns.say(string.format(L["Moving, jumping and abilities send queries in click mode: %s"],
            (s0 and s0.keys == false) and L["OFF"] or L["ON"]))
    end
    local sent, waiting, found = ns.ScanProgress()
    if sent then
        ns.say(string.format(L["scan in progress: %d sent, %d waiting, %d found so far"], sent, waiting, found))
    end
    local s = DenizensTWDB and DenizensTWDB.settings
    if s and s.auto then
        if ns.AutoContinuous() then
            ns.say(L["auto census: on (back to back)"])
        else
            ns.say(string.format(L["auto census: on (every %d min)"], s.autoMinutes or 30))
        end
        if ns.autoNextAt then
            ns.say(string.format(L["Next auto pass in %d min."],
                math.max(0, math.ceil((ns.autoNextAt - time()) / 60))))
        end
    else
        ns.say(L["auto census: off"])
    end
    local c = (DenizensTWDB and DenizensTWDB.client) or {}
    ns.say(string.format(L["client: %s %s (interface %s), locale %s"],
        tostring(c.version or "?"), tostring(c.build or "?"), tostring(c.interface or "?"),
        tostring(c.locale or ns.locale)))
    for _, line in ipairs(ns.Census.Summary()) do ns.say(line) end
end

local function handle(msg)
    msg = strtrim(msg or "")
    local lower = msg:lower()

    if lower == "scan" or lower == "full" then
        ns.FullScan()
        return
    end
    if lower == "deep" or lower:match("^deep%s") then
        -- An explicit argument wins: /dz deep z-"Elwynn Forest"
        local given = strtrim(msg:match("^%S+%s+(.*)$") or "")
        local q = given ~= "" and given or ns.CurrentQuery()
        ns.log(string.format('deep scan from: "%s"%s', q, q == "" and " (no filter)" or ""))
        ns.DeepScanQuery(q)
        return
    end
    if lower == "auto" or lower:match("^auto%s") then
        local arg = strtrim(lower:match("^auto%s+(.*)$") or "")
        if arg == "off" or arg == "stop" then
            ns.SetAuto(false)
        elseif arg == "0" or arg == "loop" or arg == "連續" then
            ns.SetAuto(true, 0)
        else
            ns.SetAuto(true, tonumber(arg))
        end
        return
    end
    if lower == "連續" or lower == "loop" then ns.SetAuto(true, 0) return end
    if lower == "status" then printStatus() return end
    if lower == "mode auto" or lower == "mode click" then
        ns.SetMode(lower == "mode click" and "click" or "auto")
        return
    end
    if lower == "debug" then ns.DumpLog(30) return end
    if lower == "debug on" or lower == "debug off" then
        ns.Census.Init()
        DenizensTWDB.settings.debug = (lower == "debug on")
        ns.say(string.format(L["live debug output %s"], DenizensTWDB.settings.debug and L["ON"] or L["OFF"]))
        return
    end
    if lower == "cancel" or lower == "stop" then
        if ns.CancelScan() == 0 then ns.say(L["No scan running."]) end
        return
    end
    if lower == "census" then printCensus() return end
    if lower == "wipe" then
        ns.say(L["This deletes every saved character for this realm and faction. Type |cffffd100/dz wipe confirm|r to do it."])
        return
    end
    if lower == "wipe confirm" then
        ns.Census.Wipe()
        ns.say(L["Census cleared for this realm and faction."])
        return
    end
    if lower == "takeover on" or lower == "takeover off" then
        local on = (lower == "takeover on")
        ns.Census.Init()          -- first run: the DB may not exist yet
        DenizensTWDB.settings.takeover = on
        ns.say(string.format(L["in-pane takeover %s - /reload to apply."], on and L["ENABLED"] or L["DISABLED"]))
        if not on then ns.say(L["the standalone window (/dz) touches none of Blizzard's frames."]) end
        return
    end
    if lower == "whopos" then
        local st = ns.WhoMoverState()
        if st.error then
            ns.say(string.format(L["Dragging the Find Group window failed to set up: %s - please send a screenshot."], st.error))
        elseif st.installed then
            ns.say(string.format(L["Find Group window: drag its title bar to move it (not in combat). Spot: %s."],
                st.spot and L["remembered"] or L["not moved yet"]))
        elseif not st.loaded then
            ns.say(L["The Find Group window has not loaded yet; it can be dragged as soon as it first appears."])
        else
            ns.say(L["In combat - the Find Group window can be dragged once combat ends."])
        end
        return
    end
    if lower == "whopos reset" then
        ns.Census.Init()
        ns.ResetWhoSpot()
        ns.say(L["The Find Group window goes back to its usual spot next time it opens."])
        return
    end
    if lower == "keys on" or lower == "keys off" then
        ns.Census.Init()          -- first run: the DB may not exist yet
        DenizensTWDB.settings.keys = (lower == "keys on")
        ns.say(string.format(L["Moving, jumping and abilities send queries in click mode: %s"],
            DenizensTWDB.settings.keys and L["ON"] or L["OFF"]))
        return
    end
    if lower == "help" then
        for _, line in ipairs(HELP) do ns.say(line) end
        return
    end
    if msg ~= "" then
        eRaw:SetText(msg)
        f:Show()
        doSearch()
    else
        if f:IsShown() then f:Hide() else f:Show(); refreshRaw() end
    end
end

SLASH_DENIZENSTW1 = "/dz"
SLASH_DENIZENSTW2 = "/dztw"
-- Typing a slash command is a hardware event, so the first query of a scan
-- goes out at once even in click mode.
SlashCmdList.DENIZENSTW = function(msg) ns.WithHardware(handle, msg) end
