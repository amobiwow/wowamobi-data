--[[ Denizens TW core ----------------------------------------------------

Taiwan fork of Denizens by Konig (MIT, see LICENSE). Query building, the send
queue, result capture, sorting and the deep scan. No UI in this file.

What this fork changes, and why (details next to each piece of code):
  * A level that is still capped is split by class, then by race, instead of
    being given up on. On launch day hundreds of players share each low level,
    and level-only splitting saw a third of them at best.
  * Class and race filters use the client's own localized names, so a zhTW
    client queries c-"戰士", not c-"Warrior" (which matches nobody there).
  * The hardware-event gate is actually detected (ADDON_ACTION_FORBIDDEN) and
    the scan falls back to click mode: real clicks in the world, a button or a
    key binding each send the next query. The original declared the flag but
    nothing ever set it.
  * The throttle backoff recovers after replies come back, and retries are
    counted per query - previously one bad patch slowed the rest of the session
    to 12 s per query, and the retry limit could never be reached.
  * Optional auto passes (/dz auto) that run only while the player is there.
    /dz auto 0 (or /dz 連續) is back to back: the next pass starts 10 s after one
    finishes, so the owner doesn't retype the command between rounds (owner
    2026-10-25). In click mode every query still waits for the player's own
    click, movement or ability; AFK and combat still pause it.

Everything here is built on what the client actually reported (see Probe.lua),
not on a Classic-era wiki page:

  * C_FriendList.SendWho / GetNumWhoResults / GetWhoInfo / SetWhoToUi exist
  * SortWho does NOT exist, so sorting is ours to do
  * GetWhoInfo returns: fullName, level, classStr, filename, raceStr,
    area, fullGuildName, gender.  The guild key is fullGuildName - NOT
    "guild", which is what the Classic docs would have had us write and
    which would have failed silently as an empty column.
--]]

local ADDON, ns = ...
local L = ns.L

DenizensTW = ns
-- Must match "## Interface:" in DenizensTW.toc. Kept here because
-- GetAddOnMetadata cannot read that field back out of the TOC.
ns.BUILT_FOR = 16001
ns.CAP = 50           -- the server's hard result cap; see DeepScan below
ns.MAX_LEVEL = 60
ns.results = {}       -- array of row tables
ns.resultIndex = {}   -- name -> true, so merging a batch is not a full rescan
ns.lastQuery = ""     -- the last query actually sent, from any source
ns.lastUserQuery = "" -- the last query the PLAYER asked for (never a sub-query)
ns.hardwareGated = false
ns.inHardware = false -- true only while running inside a click / key press
ns.stats = { sent = 0, replies = 0, timeouts = 0 }

-- Output discipline: Denizens prints ONE line at login and otherwise speaks
-- only when asked a question or when a scan ends. Everything else goes to a
-- ring buffer that /dz debug can dump.
local function say(msg)
    print("|cff66ccffDenizens TW|r " .. tostring(msg))
end
ns.say = say

ns.errors, ns.logLines = 0, {}

function ns.log(msg)
    local line = date("%H:%M:%S") .. "  " .. tostring(msg)
    ns.logLines[#ns.logLines + 1] = line
    while #ns.logLines > 300 do table.remove(ns.logLines, 1) end
    if DenizensTWDB and DenizensTWDB.settings and DenizensTWDB.settings.debug then
        say(msg)
    end
end

-- Something went wrong. Counted so the login line can mention it once.
function ns.warn(msg)
    ns.errors = ns.errors + 1
    ns.log("|cffff5555" .. tostring(msg) .. "|r")
end

function ns.FormatDuration(secs)
    secs = math.max(0, math.floor(tonumber(secs) or 0))
    return string.format(L["%dm %02ds"], math.floor(secs / 60), secs % 60)
end

--==========================================================================
-- Query building
--==========================================================================

-- The /who filter tokens. A value containing a space must be quoted, and an
-- unquoted multi-word zone is the single most common reason a query silently
-- returns everybody instead of the zone asked for.
local TOKEN = { name = "n", guild = "g", zone = "z", race = "r", class = "c" }

local function token(prefix, value)
    value = value and strtrim(value) or ""
    if value == "" then return nil end
    return string.format('%s-"%s"', prefix, value)
end
ns.Token = token

-- spec = { name, guild, zone, race, class, minLevel, maxLevel }
function ns.BuildQuery(spec)
    local parts = {}
    for field, prefix in pairs(TOKEN) do
        local t = token(prefix, spec[field])
        if t then parts[#parts + 1] = t end
    end
    table.sort(parts)   -- stable output, so the raw box does not jitter

    local lo, hi = tonumber(spec.minLevel), tonumber(spec.maxLevel)
    if lo and hi then
        if lo > hi then lo, hi = hi, lo end
        parts[#parts + 1] = (lo == hi) and tostring(lo)
                                       or string.format("%d-%d", lo, hi)
    elseif lo then
        parts[#parts + 1] = tostring(lo)
    elseif hi then
        parts[#parts + 1] = tostring(hi)
    end

    return table.concat(parts, " ")
end

-- Split a raw /who query into tokens, keeping quoted values intact, so that
-- z-"Stormwind City" survives as one token instead of becoming two.
local function tokenize(q)
    local out, i, n = {}, 1, #(q or "")
    while i <= n do
        local c = q:sub(i, i)
        if c:match("%s") then
            i = i + 1
        else
            local start, inQuote = i, false
            while i <= n do
                local ch = q:sub(i, i)
                if ch == '"' then inQuote = not inQuote
                elseif ch:match("%s") and not inQuote then break end
                i = i + 1
            end
            out[#out + 1] = q:sub(start, i - 1)
        end
    end
    return out
end

local function isLevelToken(t)
    return t:match("^%d+$") ~= nil or t:match("^%d+%-%d+$") ~= nil
end

-- Strip the level filter out of a raw query and report what it was, so a deep
-- scan can re-impose its own ranges over whatever the player actually typed.
function ns.SplitQuery(raw)
    local base, lo, hi = {}, nil, nil
    for _, t in ipairs(tokenize(raw)) do
        if isLevelToken(t) then
            local a, b = t:match("^(%d+)%-(%d+)$")
            if a then lo, hi = tonumber(a), tonumber(b)
            else lo = tonumber(t); hi = lo end
        else
            base[#base + 1] = t
        end
    end
    return table.concat(base, " "), lo, hi
end

-- Does the query already filter on this token (c- or r-)? Then a deep scan
-- must not add a second one of its own.
local function hasFilter(base, prefix)
    for _, t in ipairs(tokenize(base)) do
        if t:sub(1, 2):lower() == prefix .. "-" then return true end
    end
    return false
end

--==========================================================================
-- The send queue
--==========================================================================
-- /who is server-throttled. Firing them back to back gets the extras silently
-- dropped, which looks exactly like "the addon is broken" - so every query
-- goes through one queue with a gap, and a query whose reply never arrives is
-- retried with a longer gap rather than abandoned.

local BASE_GAP, MAX_GAP, REPLY_TIMEOUT, MAX_RETRIES = 2.5, 12, 5, 3
local queue, inFlight, sentAt, gap = {}, nil, -1e9, BASE_GAP
-- The pace the server has shown it needs. Every "too fast" pushes it up to
-- just past the interval that was refused; every answer lets it ease off a
-- little, so it settles near the server's real limit and wasted clicks stay
-- rare. lastOkSend is when the last answered query went out.
local floorGap, lastOkSend = 0, nil

-- What carried the query now being sent: "click" (the 3D world), "key"
-- (moving, jumping, abilities), "combat" (either, in combat); nil for a typed
-- command, a button of ours or our key binding. If the game refuses a send that
-- rode on a real input, that kind of input is paused for a while (it may only
-- be the situation, e.g. swimming); refused five times in one session, it is
-- off until the next login.
local currentSource, sendingNow = nil, false
local carrierOff, carrierRefusals = {}, {}
local CARRIER_PAUSE, CARRIER_GIVE_UP = 90, 5

-- A gate that refuses silently (no ADDON_ACTION_FORBIDDEN) would otherwise
-- look like endless throttling: every timer-sent query times out and is given
-- up one by one. If timer-sent queries have NEVER been answered this session
-- and several in a row time out, treat it as a gate, not a throttle.
-- Six in a row means the gap has already grown to its 12 s ceiling; a real
-- throttle stricter than that would make automatic sending hopeless anyway.
local SILENT_GATE_AFTER = 6
local timerReplies, timerTimeoutsInRow = 0, 0

-- Bumped by CancelScan. Every deep-scan callback captures the generation it
-- was created under and returns early if it no longer matches, so a cancelled
-- scan cannot resurrect itself through a reply that was already in the air.
local generation = 0
local ignoreNextReply = false

local driver = CreateFrame("Frame")

local function inCombat()
    return InCombatLockdown and InCombatLockdown() and true or false
end

local function isAFK()
    return UnitIsAFK and UnitIsAFK("player") and true or false
end

local function pump()
    if inFlight or #queue == 0 then return end
    if ns.conflict then return end
    -- In click mode only a real click may send. A timer trying anyway would
    -- just provoke the same refusal (and Blizzard's popup) again.
    if ns.hardwareGated and not ns.inHardware then return end
    if GetTime() - sentAt < math.max(gap, floorGap) then return end
    -- Auto passes only run while the player is actually there.
    local nextItem = queue[1]
    if nextItem.state and nextItem.state.auto and isAFK() then return end

    inFlight = table.remove(queue, 1)
    inFlight.hw = ns.inHardware
    inFlight.sentAt = GetTime()
    inFlight.source = currentSource
    sentAt = GetTime()
    if C_FriendList.SetWhoToUi then C_FriendList.SetWhoToUi(true) end
    ns.lastQuery = inFlight.query
    ns.stats.sent = ns.stats.sent + 1
    if inFlight.state then inFlight.state.sent = inFlight.state.sent + 1 end
    sendingNow = true
    local ok, err = pcall(C_FriendList.SendWho, inFlight.query)
    sendingNow = false
    if not ok then
        ns.warn("SendWho error: " .. tostring(err))
        local text = tostring(err):lower()
        if text:find("protected", 1, true) or text:find("hardware", 1, true) then
            ns.MarkGated("error")
        end
    end
end

-- The client refused SendWho outside a hardware event. Switch to click mode
-- for good (remembered per client build), and put the refused query back.
function ns.MarkGated(source)
    if not ns.hardwareGated then
        ns.hardwareGated = true
        if DenizensTWDB and DenizensTWDB.client then
            DenizensTWDB.client.gatedBuild = DenizensTWDB.client.build or true
        end
        ns.log("hardware gate detected (" .. tostring(source) .. ")")
        say(L["This client only sends /who on a real click or key press. Switched to click mode: click in the game world, move, jump or use an ability (or press your Denizens TW key binding) - each one sends the next query. If Blizzard showed an \"AddOn blocked\" box, choose Ignore."])
        if ns.OnModeChanged then ns.OnModeChanged() end
    end
    -- The refused query never left the client: requeue it, uncounted.
    if inFlight then
        local item = inFlight
        inFlight = nil
        ns.stats.sent = math.max(0, ns.stats.sent - 1)
        if item.state then item.state.sent = math.max(0, item.state.sent - 1) end
        table.insert(queue, 1, item)
    end
    -- Timeouts so far were refusals, not a throttle: start the count afresh,
    -- and from now on a click is the pacing, so the backed-off gap goes too.
    for _, item in ipairs(queue) do item.retries = 0 end
    gap = BASE_GAP
    sentAt = -1e9   -- the next click may send at once
end

-- A send that rode on a real click or key was refused anyway. Put it back
-- uncounted and pause that kind of input; the player is told only if it
-- keeps happening and the input is switched off for the session.
local CARRIER_MSG = {
    key = "Moving and abilities cannot carry a /who on this client (the game refused it), so only clicks in the game world send queries now.",
    combat = "This client refuses /who during combat, so queries wait until combat is over.",
    click = "Even a click in the game world could not send this /who. Please type /dz debug and send a screenshot.",
}

local function refusedCarrier(source, why)
    local item = inFlight
    inFlight = nil
    ns.stats.sent = math.max(0, ns.stats.sent - 1)
    if item.state then item.state.sent = math.max(0, item.state.sent - 1) end
    table.insert(queue, 1, item)
    sentAt = -1e9                       -- the next input that does work may send at once
    ns.log("refused on " .. tostring(source) .. " (" .. tostring(why) .. ")")
    if not source then return end
    carrierRefusals[source] = (carrierRefusals[source] or 0) + 1
    if carrierRefusals[source] >= CARRIER_GIVE_UP then
        if carrierOff[source] ~= math.huge and CARRIER_MSG[source] then
            say("|cffffd100" .. L[CARRIER_MSG[source]] .. "|r")
        end
        carrierOff[source] = math.huge
    else
        carrierOff[source] = GetTime() + CARRIER_PAUSE
    end
end

local function carrierPaused(kind)
    local untilT = carrierOff[kind]
    return untilT ~= nil and GetTime() < untilT
end

function ns.CarriersOff()
    local out = {}
    for k in pairs(carrierOff) do
        if carrierPaused(k) then out[#out + 1] = k end
    end
    table.sort(out)
    return out
end

function ns.SetMode(mode)
    if mode == "click" then
        ns.hardwareGated = true
        say(L["Mode set to click - every query waits for a click or key press."])
    else
        ns.hardwareGated = false
        if DenizensTWDB and DenizensTWDB.client then DenizensTWDB.client.gatedBuild = nil end
        say(L["Mode set to automatic - the next query tells whether this client allows it."])
    end
    if ns.OnModeChanged then ns.OnModeChanged() end
end

driver:SetScript("OnUpdate", function()
    if inFlight and GetTime() - sentAt > REPLY_TIMEOUT then
        -- No WHO_LIST_UPDATE came back. Assume throttled: widen the gap and
        -- put the query back at the front rather than losing the sub-query and
        -- silently returning an incomplete census.
        local item = inFlight
        inFlight = nil
        item.retries = (item.retries or 0) + 1
        ns.stats.timeouts = ns.stats.timeouts + 1
        if item.state then item.state.timeouts = item.state.timeouts + 1 end
        sentAt = GetTime()
        -- Until a timer-sent query has been answered at least once, a timeout
        -- may mean a silent gate rather than a throttle. Giving up then would
        -- throw away a whole branch of the scan, so keep it until we know.
        local undecided = not item.hw and not ns.hardwareGated and timerReplies == 0
        -- A click-sent query costs the player a click per try, and a busy
        -- server is the usual reason it went unanswered: give it more tries.
        local limit = item.hw and 8 or MAX_RETRIES
        if item.retries <= limit or undecided then
            gap = math.min(gap * 1.6, MAX_GAP)
            table.insert(queue, 1, item)
        else
            ns.warn("gave up on " .. item.query .. " (no reply)")
            if item.onDone then item.onDone({}, true) end
        end
        if not item.hw and not ns.hardwareGated then
            timerTimeoutsInRow = timerTimeoutsInRow + 1
            if timerReplies == 0 and timerTimeoutsInRow >= SILENT_GATE_AFTER then
                ns.MarkGated("no reply to any timed query")
            end
        end
    end
    pump()
end)

-- Call this ONLY from something that is itself a hardware event: a button's
-- OnClick, a key binding, a click on the 3D world, a typed slash command.
function ns.Step()
    local was = ns.inHardware
    ns.inHardware = true
    local ok, err = pcall(pump)
    ns.inHardware = was
    if not ok then ns.warn("step: " .. tostring(err)) end
end
ns.Pump = ns.Step   -- the name UI code used before

-- Run fn as part of the current hardware event (see ns.Step).
function ns.WithHardware(fn, ...)
    local was = ns.inHardware
    ns.inHardware = true
    local ok, err = pcall(fn, ...)
    ns.inHardware = was
    if not ok then
        ns.warn(tostring(err))
        say("|cffff5555" .. tostring(err) .. "|r")
    end
end

-- Stop everything: drop the queue, abandon the query already sent, and
-- invalidate any callback still holding a reference to the old scan.
function ns.CancelScan()
    local n = #queue + (inFlight and 1 or 0)
    local state = ns.scanState
    if n == 0 and not state then return 0 end
    generation = generation + 1
    wipe(queue)
    if inFlight then
        -- Its reply may still arrive. Discard that one rather than letting it
        -- be mistaken for a /who the player typed.
        ignoreNextReply = true
        inFlight = nil
    end
    sentAt = GetTime()
    if state and not state.done then
        state.cancelled = true
        if ns.FinishScan then ns.FinishScan(state, true) end
    end
    say(string.format(L["Scan cancelled - %d queries dropped, %d players kept."], n, #ns.results))
    if ns.OnResults then ns.OnResults() end
    return math.max(n, 1)
end

function ns.Send(query, onDone, state, expect)
    if ns.conflict then
        say(L["The original Denizens is also enabled. Two addons sending /who at once throttle each other, so Denizens TW will not scan. Untick one of them in the AddOns list at character select."])
        return false
    end
    queue[#queue + 1] = { query = query, onDone = onDone, state = state, expect = expect }
    pump()
    return true
end

-- A search the player asked for (not a deep-scan sub-query).
function ns.UserSearch(q)
    q = strtrim(q or "")
    ns.lastUserQuery = q
    return ns.Send(q, function(batch) ns.Absorb(batch, false) end)
end

function ns.QueueDepth() return #queue + (inFlight and 1 or 0) end
function ns.CurrentGap() return math.max(gap, floorGap) end

--==========================================================================
-- Result capture
--==========================================================================

-- Localized class name -> locale-free class file, learned from every reply.
local classFileOf = {}

local function harvest()
    local out, n = {}, C_FriendList.GetNumWhoResults()
    for i = 1, n or 0 do
        local info = C_FriendList.GetWhoInfo(i)
        if info and info.fullName and info.fullName ~= "" then
            out[#out + 1] = {
                name   = info.fullName,
                level  = info.level or 0,
                class  = info.classStr or "",
                token  = info.filename or "",      -- locale-free class file
                race   = info.raceStr or "",
                zone   = info.area or "",
                guild  = info.fullGuildName or "",
                sex    = info.gender,
            }
            local row = out[#out]
            if row.class ~= "" and row.token ~= "" then classFileOf[row.class] = row.token end
        end
    end
    return out
end

-- Two names describe the same thing when one contains the other: the server
-- matches filters loosely, so r-"天裔精靈" brings back "高天盟天裔精靈".
local function sameName(a, b)
    return a:find(b, 1, true) ~= nil or b:find(a, 1, true) ~= nil
end

-- Could this batch be the answer to the query we are waiting for? Every row
-- must sit inside the query's level range and, when the query named them, its
-- class and race. A late reply to an earlier query, a /who from Blizzard's own
-- window or one the player typed usually fails this at once (the Forever beta
-- showed its window sending z-"zone" level-3..level+3 by itself). Blank fields
-- prove nothing either way.
local function answers(batch, expect)
    if not expect then return true end
    local wantFile = expect.class and classFileOf[expect.class]
    for _, row in ipairs(batch) do
        local lvl = tonumber(row.level) or 0
        if lvl > 0 and (lvl < expect.lo or lvl > expect.hi) then return false end
        if expect.class then
            if wantFile and row.token ~= "" then
                if row.token ~= wantFile then return false end
            elseif row.class ~= "" and not sameName(row.class, expect.class) then
                return false
            end
        end
        if expect.race and row.race ~= "" and not sameName(row.race, expect.race) then return false end
    end
    return true
end

-- The server's "you must wait before using /who again". The query in flight
-- was refused and its answer is never coming. The Forever beta says either
-- 你必須稍等一下，才能再次使用「/誰」。 or 你必須等待2秒，才能再次使用「/誰」。
-- Returns the seconds it named (0 when it named none), or nil.
local function whoThrottle(msg)
    if type(msg) ~= "string" then return nil end
    local zh = msg:find("/誰", 1, true) and (msg:find("稍等", 1, true) or msg:find("等待", 1, true))
    local low = msg:lower()
    local en = low:find("/who", 1, true) and low:find("wait", 1, true)
    if not (zh or en) then return nil end
    return tonumber(msg:match("(%d+)")) or 0
end

-- Forever's own who window is LFGWhoListFrame, under LFGParentFrame (the
-- Group Finder), and it opens on every /who reply. Hiding it from here never
-- worked in game (Blizzard shows it after our handler has run), and calling
-- Hide() on the Group Finder from addon code risks tainting its queue
-- buttons, so its visibility is no longer touched. Instead the player can drag
-- it out of the way by its title bar, out of combat; only its position
-- changes. The spot is saved and put back whenever Blizzard re-anchors it.
local whoMover

local function whoSpot()
    local s = DenizensTWDB and DenizensTWDB.settings
    return s and s.whoPos
end

local function placeWho()
    local frame, p = _G.LFGParentFrame, whoSpot()
    if not (frame and p) or inCombat() then return end
    frame:ClearAllPoints()
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local moverError

local function installWhoMover(frame)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    local grip = CreateFrame("Frame", nil, frame)
    grip:SetPoint("TOPLEFT", frame, "TOPLEFT", 70, 0)     -- clear of the eye icon
    grip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -40, 0)  -- and of the close button
    grip:SetHeight(32)
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function()
        if not inCombat() then frame:StartMoving() end
    end)
    grip:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, relPoint, x, y = frame:GetPoint(1)
        if type(point) == "string" and DenizensTWDB and DenizensTWDB.settings then
            DenizensTWDB.settings.whoPos = { point, relPoint or point, x or 0, y or 0 }
        end
    end)
    -- Blizzard re-anchors the window when it opens and when other panels open
    -- or close: put it back right after, never in combat.
    frame:HookScript("OnShow", function()
        if C_Timer and C_Timer.After then C_Timer.After(0, placeWho) else placeWho() end
    end)
    if hooksecurefunc and type(UpdateUIPanelPositions) == "function" then
        hooksecurefunc("UpdateUIPanelPositions", function()
            if frame:IsShown() then placeWho() end
        end)
    end
    whoMover = grip
    placeWho()
    if not whoSpot() then
        say(L["Tip: drag the Find Group window by its title bar to move it out of the way (not in combat). Its spot is remembered; /dz whopos reset puts it back."])
    end
end

-- Called on every /who reply and twice a second by the UI ticker, so the
-- handle is there as soon as Blizzard first loads the window. A failure is
-- recorded once (shown by /dz whopos) instead of breaking the reply handler.
function ns.InstallWhoMover()
    if whoMover or moverError or inCombat() then return end
    local frame = _G.LFGParentFrame          -- loaded on demand by Blizzard
    if not (frame and frame.SetMovable) then return end
    local ok, err = pcall(installWhoMover, frame)
    if not ok then
        moverError = tostring(err)
        ns.warn("who window mover: " .. moverError)
    end
end

function ns.WhoMoverState()
    return {
        installed = whoMover ~= nil, error = moverError,
        loaded = _G.LFGParentFrame ~= nil, spot = whoSpot() ~= nil,
    }
end

function ns.ResetWhoSpot()
    if DenizensTWDB and DenizensTWDB.settings then DenizensTWDB.settings.whoPos = nil end
end

driver:RegisterEvent("WHO_LIST_UPDATE")
driver:RegisterEvent("CHAT_MSG_SYSTEM")
driver:RegisterEvent("ADDON_ACTION_FORBIDDEN")
driver:RegisterEvent("ADDON_ACTION_BLOCKED")
-- UI_ERROR_MESSAGE is deliberately NOT used to detect refusals: it carries
-- every red error the game raises and cannot be tied to /who. The honest
-- signals are the timeout path and ADDON_ACTION_FORBIDDEN / _BLOCKED naming
-- this addon. Some builds also name the function ("C_FriendList.SendWho()");
-- the Forever beta (1.60.1.70450) sent ADDON_ACTION_BLOCKED - the "Interface
-- action failed because of an AddOn" line - without a usable name, so a
-- refusal that lands while a timer-sent /who is leaving counts as well.

driver:SetScript("OnEvent", function(_, event, a, b)
    if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        if a == ADDON then
            ns.log(string.format("%s: %s (sending %s, source %s)", event, tostring(b),
                tostring(sendingNow), tostring(inFlight and inFlight.source)))
            local named = tostring(b or ""):find("SendWho", 1, true)
            local hwSend = inFlight and inFlight.hw and (sendingNow or GetTime() - (inFlight.sentAt or 0) < 0.5)
            local justSent = inFlight and not inFlight.hw and GetTime() - sentAt < 1
            if hwSend then
                refusedCarrier(inFlight.source, event)
            elseif named or justSent then
                ns.MarkGated(event)
            end
        end
        return
    end

    if event == "CHAT_MSG_SYSTEM" then
        -- Refused for going too fast: put the query back at once instead of
        -- waiting out the timeout, slow down a step, and do not count it as a
        -- try towards giving up - nothing was wrong with the query.
        local wait = inFlight and whoThrottle(a)
        if wait then
            local item = inFlight
            inFlight = nil
            ns.stats.throttled = (ns.stats.throttled or 0) + 1
            ns.stats.sent = math.max(0, ns.stats.sent - 1)
            if item.state then item.state.sent = math.max(0, item.state.sent - 1) end
            table.insert(queue, 1, item)
            if wait > 0 then
                gap = math.min(math.max(gap, wait + 0.3), MAX_GAP)   -- what it asked for now
            end
            if item.sentAt and lastOkSend then
                local refused = item.sentAt - lastOkSend
                floorGap = math.min(MAX_GAP, math.max(floorGap, refused + math.max(wait, 0.5) + 0.2))
            elseif wait == 0 then
                gap = math.min(gap * 1.6, MAX_GAP)
            end
            sentAt = GetTime()
        end
        return
    end

    if ignoreNextReply then
        ignoreNextReply = false   -- late reply from a cancelled scan
        return
    end
    -- Blizzard loads its who window on demand: look for it on replies.
    if not whoMover then
        ns.InstallWhoMover()
        if not whoMover and C_Timer and C_Timer.After then C_Timer.After(0, ns.InstallWhoMover) end
    end
    local batch = harvest()
    ns.stats.replies = ns.stats.replies + 1

    -- Not the answer to the query in flight: keep the sightings (they are
    -- real players online right now), but let it decide nothing, and keep
    -- waiting for the real answer.
    if inFlight and not answers(batch, inFlight.expect) then
        ns.stats.foreign = (ns.stats.foreign or 0) + 1
        ns.Absorb(batch, true)
        return
    end

    if not inFlight then
        -- Either a /who the player typed, or the late second reply to a query
        -- we already retried. A late reply must not wipe a scan in progress.
        local late = (GetTime() - sentAt) < 15
        ns.Absorb(batch, late)
        return
    end

    local item = inFlight
    inFlight, sentAt = nil, GetTime()
    if not item.hw then
        timerReplies = timerReplies + 1
        timerTimeoutsInRow = 0
    end
    -- Replies are flowing again: let the gap drift back down to normal.
    gap = math.max(BASE_GAP, gap * 0.9)
    floorGap = floorGap * 0.98
    lastOkSend = item.sentAt
    if item.onDone then item.onDone(batch) else ns.Absorb(batch, false) end
    pump()
end)

-- Merge a batch into the visible set, de-duplicating by name. Deep scan relies
-- on this: overlapping splits WILL return the same player twice. Returns how
-- many characters the census had never seen before.
function ns.Absorb(batch, keepExisting)
    if not keepExisting then
        wipe(ns.results)
        wipe(ns.resultIndex)
    end
    local index = ns.resultIndex
    for _, row in ipairs(batch) do
        if not index[row.name] then
            index[row.name] = true
            ns.results[#ns.results + 1] = row
        end
    end
    -- Every sighting feeds the persistent roster, including replies to a /who
    -- the player typed - the census should also grow from ordinary use.
    local new = 0
    if ns.Census and ns.Census.Record then new = ns.Census.Record(batch) or 0 end
    if ns.OnResults then ns.OnResults() end
    return new
end

--==========================================================================
-- Partition axes for a level that is still capped
--==========================================================================
-- Level comes first because it partitions the population cleanly. Once a
-- single level is still capped, class is the next clean partition (every
-- character has exactly one class), then race. Both must use the client's
-- own localized names: the server matches the filter against the same
-- strings GetWhoInfo returns.

local CLASSIC_CLASS_FILES = {
    WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true,
    SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true,
}
local FALLBACK_CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest",
                           "Shaman", "Mage", "Warlock", "Druid" }
local FACTION_RACE_IDS = { Alliance = { 1, 3, 4, 7 }, Horde = { 2, 5, 6, 8 } }
local FALLBACK_RACES = {
    Alliance = { "Human", "Dwarf", "Night Elf", "Gnome", "Skyborne" },
    Horde    = { "Orc", "Undead", "Tauren", "Troll", "Skyborne" },
}

local function addUnique(list, seen, name)
    name = name and strtrim(tostring(name)) or ""
    if name ~= "" and not seen[name] then
        seen[name] = true
        list[#list + 1] = name
    end
end

local function addObserved(list, seen, kind)
    -- Only once the roster is live (after login); never create it from here.
    if ns.Census and ns.Census.db and ns.Census.Observed then
        for _, n in ipairs(ns.Census.Observed(kind)) do addUnique(list, seen, n) end
    end
end

function ns.ClassNames()
    local list, seen = {}, {}
    if GetClassInfo then
        for id = 1, 13 do
            local ok, name, file = pcall(GetClassInfo, id)
            if ok and name and (file == nil or CLASSIC_CLASS_FILES[file]) then
                addUnique(list, seen, name)
            end
        end
    end
    if #list == 0 then
        for _, n in ipairs(FALLBACK_CLASSES) do addUnique(list, seen, n) end
    end
    addObserved(list, seen, "classes")
    return list, seen
end

-- Skyborne is new in Forever and its race ID is not known in advance, so look
-- for it by its (locale-free) client file name once per session.
local skyborneCache
local function skyborneNames()
    if skyborneCache then return skyborneCache end
    skyborneCache = {}
    if C_CreatureInfo and C_CreatureInfo.GetRaceInfo then
        for id = 1, 150 do
            local ok, info = pcall(C_CreatureInfo.GetRaceInfo, id)
            if ok and type(info) == "table" and info.raceName then
                local file = tostring(info.clientFileString or ""):lower()
                if file:find("sky", 1, true) then
                    skyborneCache[#skyborneCache + 1] = info.raceName
                end
            end
        end
    end
    return skyborneCache
end

function ns.RaceNames(faction)
    faction = faction or (UnitFactionGroup and UnitFactionGroup("player"))
    local list, seen = {}, {}
    if C_CreatureInfo and C_CreatureInfo.GetRaceInfo then
        local function addIds(ids)
            for _, id in ipairs(ids) do
                local ok, info = pcall(C_CreatureInfo.GetRaceInfo, id)
                if ok and type(info) == "table" then addUnique(list, seen, info.raceName) end
            end
        end
        if FACTION_RACE_IDS[faction] then
            addIds(FACTION_RACE_IDS[faction])
        else
            addIds(FACTION_RACE_IDS.Alliance)
            addIds(FACTION_RACE_IDS.Horde)
        end
        for _, n in ipairs(skyborneNames()) do addUnique(list, seen, n) end
    end
    if #list == 0 then
        local fallback = FALLBACK_RACES[faction]
        if fallback then
            for _, n in ipairs(fallback) do addUnique(list, seen, n) end
        else
            for _, n in ipairs(FALLBACK_RACES.Alliance) do addUnique(list, seen, n) end
            for _, n in ipairs(FALLBACK_RACES.Horde) do addUnique(list, seen, n) end
        end
    end
    addObserved(list, seen, "races")
    return list, seen
end

--==========================================================================
-- Deep scan - defeating the 50-result cap
--==========================================================================
-- A query that returns EXACTLY the cap is almost certainly truncated: the
-- server stopped counting, so you are looking at an arbitrary 50 of an
-- unknown number. "50 People Found" is not a population, it is a ceiling.
--
-- So: when a query comes back at the cap, split it and ask again for each
-- part - level range in halves first, then (for a single level) by class,
-- then by race. Merge as replies arrive. A capped sample becomes a census.

-- A node of the scan tree: a level range plus at most one value per axis.
local function subQuery(base, node)
    local parts = {}
    if base ~= "" then parts[#parts + 1] = base end
    if node.class then parts[#parts + 1] = token("c", node.class) end
    if node.race then parts[#parts + 1] = token("r", node.race) end
    if node.zone then parts[#parts + 1] = token("z", node.zone) end
    parts[#parts + 1] = (node.lo == node.hi) and tostring(node.lo)
                        or string.format("%d-%d", node.lo, node.hi)
    return table.concat(parts, " ")
end

-- A capped reply is also a free sample: any class or race it shows that the
-- lists do not have yet joins them, so a partition cannot silently miss it.
local function learn(list, seen, batch, field)
    for _, row in ipairs(batch) do addUnique(list, seen, row[field]) end
end

local function distinct(batch, field)
    local list, seen = {}, {}
    learn(list, seen, batch, field)
    return list
end

local function describeLeaf(leaf)
    local s = "Lv" .. leaf.lo
    if leaf.class then s = s .. " " .. leaf.class end
    if leaf.race then s = s .. " " .. leaf.race end
    if leaf.zone then s = s .. " @" .. leaf.zone end
    return s
end

-- Which axis to split a capped single level on next, in order.
--   class / race are clean partitions (every character has exactly one).
--   zone is a best-effort last resort: the zones seen in the capped reply.
-- Class first while levels are crowded (launch day: hundreds per level, and
-- 9 class buckets each stay under 50); race first once levels are thin
-- (a mature realm: 60-110 per level, where 5 race buckets already suffice).
local function nextAxis(state, node)
    local first = state.preferRace and "race" or "class"
    local second = (first == "race") and "class" or "race"
    for _, axis in ipairs({ first, second, "zone" }) do
        if node[axis] == nil and state.split[axis] then return axis end
    end
    return nil
end

-- After a single level has been fully split once, its true size is known.
-- Thin levels switch the scan to race-first, crowded ones back to class-first.
local function noteLevelSize(state, group)
    if group.capped then
        state.preferRace = false
        return
    end
    local sizes = state.levelSizes
    sizes[#sizes + 1] = group.total
    if #sizes > 3 then table.remove(sizes, 1) end
    local biggest = 0
    for _, n in ipairs(sizes) do if n > biggest then biggest = n end end
    -- Under ~140, even the biggest race (about a third of a faction) fits in 50.
    state.preferRace = biggest < 140
end

function ns.FinishScan(state, cancelled)
    if state.done then return end
    state.done = true
    if ns.scanState == state then ns.scanState = nil end

    local now = time()
    local capped = {}
    for i, leaf in ipairs(state.capped) do
        if i > 12 then capped[#capped + 1] = "..." break end
        capped[#capped + 1] = describeLeaf(leaf)
    end
    local record = {
        started = state.started, at = now, secs = now - state.started,
        query = state.base, levels = state.lo .. "-" .. state.hi,
        found = #ns.results, new = state.new,
        sent = state.sent, replies = state.replies, timeouts = state.timeouts,
        failed = state.failed, capped = #state.capped,
        cappedList = table.concat(capped, ", "),
        mode = ns.hardwareGated and "click" or "auto",
        kind = state.kind, locale = ns.locale,
        cancelled = cancelled and true or nil,
    }
    if ns.Census and ns.Census.NoteScan then ns.Census.NoteScan(record) end

    if not cancelled then
        say(string.format(L["Census complete: %d found (%d new), %d queries, %s."],
            #ns.results, state.new, state.sent, ns.FormatDuration(record.secs)))
        if #state.capped > 0 then
            say("|cffffd100" .. string.format(
                L["Still capped after every split: %s - more players exist there than one query can show."],
                record.cappedList) .. "|r")
        end
        if state.failed > 0 then
            say(string.format(L["%d queries got no reply and were given up."], state.failed))
        end
    end
    if ns.OnScanDone then ns.OnScanDone() end
    if not cancelled and ns.ScheduleAuto then ns.ScheduleAuto() end
end

local scan
scan = function(state, node, depth)
    local query = subQuery(state.base, node)
    local gen = generation
    state.pending = state.pending + 1
    local expect = { lo = node.lo, hi = node.hi, class = node.class, race = node.race }
    ns.Send(query, function(batch, failed)
        if gen ~= generation then return end   -- this scan was cancelled
        state.pending = state.pending - 1
        state.replies = state.replies + 1
        if failed then state.failed = state.failed + 1 end
        state.new = state.new + (ns.Absorb(batch, true) or 0)
        local capped = #batch >= ns.CAP

        -- Children of a level's first split report back, so the level's real
        -- size is known once they are all in.
        local group = node.group
        if group then
            group.left = group.left - 1
            group.total = group.total + #batch
            if capped then group.capped = true end
            if group.left == 0 then noteLevelSize(state, group) end
        end

        if capped then
            if node.lo < node.hi and depth < 12 then
                local mid = math.floor((node.lo + node.hi) / 2)
                scan(state, { lo = node.lo, hi = mid, class = node.class, race = node.race, zone = node.zone }, depth + 1)
                scan(state, { lo = mid + 1, hi = node.hi, class = node.class, race = node.race, zone = node.zone }, depth + 1)
            else
                local axis = nextAxis(state, node)
                local values
                if axis == "class" then
                    learn(state.classes, state.classSeen, batch, "class")
                    values = state.classes
                elseif axis == "race" then
                    learn(state.races, state.raceSeen, batch, "race")
                    values = state.races
                elseif axis == "zone" then
                    values = distinct(batch, "zone")
                end
                if values and #values > 0 then
                    local first = (node.class == nil and node.race == nil and node.zone == nil)
                    local g = first and { left = #values, total = 0, capped = false } or nil
                    for _, v in ipairs(values) do
                        local child = { lo = node.lo, hi = node.hi, class = node.class,
                                        race = node.race, zone = node.zone, group = g }
                        child[axis] = v
                        scan(state, child, depth + 1)
                    end
                else
                    -- Nothing left to split on. Say so rather than imply completeness.
                    state.capped[#state.capped + 1] = node
                end
            end
        end

        if state.pending == 0 then ns.FinishScan(state) end
    end, state, expect)
end

-- Deep scan any raw query. Whatever level filter it carries becomes the outer
-- bound; with no query at all this is a census of everyone online.
function ns.DeepScanQuery(raw, opts)
    opts = opts or {}
    if ns.conflict then
        say(L["The original Denizens is also enabled. Two addons sending /who at once throttle each other, so Denizens TW will not scan. Untick one of them in the AddOns list at character select."])
        return false
    end
    if ns.scanState and not ns.scanState.done then
        say(string.format(L["A scan is already running (%d queued). /dz stop cancels it."], ns.QueueDepth()))
        return false
    end
    local base, lo, hi = ns.SplitQuery(raw or "")
    lo = lo or 1
    hi = hi or ns.MAX_LEVEL
    if lo > hi then lo, hi = hi, lo end
    wipe(ns.results)
    wipe(ns.resultIndex)

    local classes, classSeen = ns.ClassNames()
    local races, raceSeen = ns.RaceNames()
    local state = {
        base = base, lo = lo, hi = hi, pending = 0, capped = {},
        started = time(), sent = 0, replies = 0, timeouts = 0, failed = 0, new = 0,
        kind = opts.kind or "deep", auto = opts.auto,
        split = { class = not hasFilter(base, "c"), race = not hasFilter(base, "r"),
                  zone = not hasFilter(base, "z") },
        classes = classes, classSeen = classSeen, races = races, raceSeen = raceSeen,
        preferRace = false, levelSizes = {},
    }
    ns.scanState = state
    ns.log(string.format('deep scan %d-%d over "%s"', lo, hi, base ~= "" and base or "everyone"))
    if not opts.quiet then
        say(string.format(L["Census scan started (levels %d-%d%s)."], lo, hi,
            base ~= "" and string.format(L[", filter: %s"], base) or ""))
    end
    scan(state, { lo = lo, hi = hi }, 0)
    return true
end

function ns.DeepScan(spec)
    return ns.DeepScanQuery(ns.BuildQuery(spec))
end

-- The census pass: everyone online, every level.
function ns.FullScan(opts)
    return ns.DeepScanQuery("", opts)
end

function ns.ScanProgress()
    local s = ns.scanState
    if not s or s.done then return nil end
    return s.sent, ns.QueueDepth(), #ns.results
end

-- Whatever query the player last asked for. Never a deep-scan sub-query:
-- reusing one of those (c-"Hunter" 37) would silently narrow the next scan.
function ns.CurrentQuery()
    local box = _G.WhoFrameEditBox
    local typed = box and box.GetText and strtrim(box:GetText() or "") or ""
    if typed ~= "" then return typed end
    return ns.lastUserQuery or ""
end

--==========================================================================
-- Sorting and filtering (client-side: SortWho does not exist here)
--==========================================================================

local COMPARE = {
    name  = function(a, b) return a.name  < b.name  end,
    level = function(a, b) return a.level < b.level end,
    class = function(a, b) return a.class < b.class end,
    race  = function(a, b) return a.race  < b.race  end,
    zone  = function(a, b) return a.zone  < b.zone  end,
    guild = function(a, b) return a.guild < b.guild end,
}

function ns.Sort(rows, key, descending)
    local cmp = COMPARE[key] or COMPARE.name
    table.sort(rows, function(a, b)
        if a[key] == b[key] then return a.name < b.name end  -- stable tiebreak
        if descending then return cmp(b, a) end
        return cmp(a, b)
    end)
end

-- Is this text actually cut off? Only then is a tooltip worth showing.
function ns.IsClipped(fs)
    if fs.IsTruncated then
        local ok, truncated = pcall(fs.IsTruncated, fs)
        if ok then return truncated end
    end
    return fs:GetStringWidth() > fs:GetWidth() + 0.5
end

-- Instant, costs no server query: narrows what is already on screen.
function ns.Filter(rows, text)
    text = strtrim(text or ""):lower()
    if text == "" then return rows end
    local out = {}
    for _, r in ipairs(rows) do
        local hay = (r.name .. " " .. r.class .. " " .. r.race .. " "
                     .. r.zone .. " " .. r.guild):lower()
        if hay:find(text, 1, true) then out[#out + 1] = r end
    end
    return out
end

--==========================================================================
-- Auto passes: a full census every N minutes, only while the player is here
--==========================================================================

local autoToken = 0
local CONTINUOUS_GAP = 10     -- seconds between back-to-back passes (/dz auto 0)

-- autoMinutes 0 = back to back
local function autoWait(s)
    local m = tonumber(s.autoMinutes) or 30
    return m <= 0 and CONTINUOUS_GAP or m * 60
end
ns.AutoContinuous = function()
    local s = DenizensTWDB and DenizensTWDB.settings
    return s and s.auto and (tonumber(s.autoMinutes) or 30) <= 0 or false
end

function ns.ScheduleAuto(delay)
    local s = DenizensTWDB and DenizensTWDB.settings
    if not (s and s.auto) or not C_Timer then return end
    autoToken = autoToken + 1
    local mine = autoToken
    local wait = delay or autoWait(s)
    ns.autoNextAt = time() + wait
    C_Timer.After(wait, function()
        if mine == autoToken and ns.TryAuto then ns.TryAuto() end
    end)
end

function ns.TryAuto()
    local s = DenizensTWDB and DenizensTWDB.settings
    if not (s and s.auto) then return end
    -- In click mode the pass is only queued: the player's clicks, movement and
    -- abilities carry it, so nothing goes out while nobody is playing.
    if isAFK() then ns.ScheduleAuto(120) return end
    if inCombat() then ns.ScheduleAuto(60) return end
    if ns.scanState and not ns.scanState.done then ns.ScheduleAuto(60) return end
    if not ns.FullScan({ auto = true, kind = "auto", quiet = true }) then ns.ScheduleAuto(300) end
end

function ns.SetAuto(on, minutes)
    if not (ns.Census and ns.Census.Init) then return end
    ns.Census.Init()
    local s = DenizensTWDB.settings
    s.auto = on and true or false
    if minutes then s.autoMinutes = minutes <= 0 and 0 or math.max(10, math.floor(minutes)) end
    autoToken = autoToken + 1     -- cancel any pending timer
    ns.autoNextAt = nil
    if not s.auto then say(L["Auto census OFF."]) return end
    if (tonumber(s.autoMinutes) or 30) <= 0 then
        say(ns.hardwareGated and L["Continuous census ON: the next pass starts 10 s after one finishes. In click mode each query still goes out with your own clicks, movement and abilities. Paused when AFK or in combat; /dz auto off stops it."]
            or L["Continuous census ON: the next pass starts 10 s after one finishes, while you are playing (paused when AFK or in combat). /dz auto off stops it."])
    elseif ns.hardwareGated then
        say(string.format(L["Auto census ON: a pass every %d minutes while you are playing. In click mode its queries go out with your clicks, movement and abilities."],
            s.autoMinutes or 30))
    else
        say(string.format(L["Auto census ON: a full pass every %d minutes while you are playing (paused when AFK or in combat)."],
            s.autoMinutes or 30))
    end
    if not (ns.scanState and not ns.scanState.done) then
        ns.FullScan({ auto = true, kind = "auto" })
    end
end

--==========================================================================
-- Click mode plumbing
--==========================================================================

-- A click on the 3D world is a hardware event: let it carry the next query.
-- The player's click still does whatever it was going to do; this only rides
-- along. In combat a reply would pop Blizzard's who window open over the
-- fight, so combat clicks and keys carry a query only while that window is
-- already open - a reply then just refreshes it where it is.
local function whoWindowOpen()
    local f = _G.LFGParentFrame
    return f ~= nil and f:IsShown() and true or false
end

local function rideAlong(kind)
    if not (ns.hardwareGated and #queue > 0 and not inFlight) then return end
    local combat = inCombat()
    if combat and not whoWindowOpen() then return end
    local source = combat and "combat" or kind
    if carrierPaused(source) or (combat and carrierPaused(kind)) then return end
    currentSource = source
    ns.Step()
    currentSource = nil
end
if WorldFrame and WorldFrame.HookScript then
    WorldFrame:HookScript("OnMouseDown", function() rideAlong("click") end)
end

-- So does a key the player presses while playing: moving, jumping, using an
-- ability. These functions are protected, so the game only ever runs them for
-- a real key press or click. hooksecurefunc runs our part after Blizzard's, so
-- the key still does exactly what it did: nothing is intercepted, and the
-- protected call itself is untouched. One press sends at most one query, the
-- same as one click. /dz keys off turns this off.
local KEY_HOOKS = { "MoveForwardStart", "MoveBackwardStart", "StrafeLeftStart", "StrafeRightStart",
                    "TurnLeftStart", "TurnRightStart", "JumpOrAscendStart", "ToggleAutoRun", "UseAction" }
local function keysCarry()
    local s = DenizensTWDB and DenizensTWDB.settings
    return not (s and s.keys == false)
end
if hooksecurefunc then
    for _, name in ipairs(KEY_HOOKS) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, function() if keysCarry() then rideAlong("key") end end)
        end
    end
end

-- Key binding target (Bindings.xml).
function DenizensTW_Step()
    if ns.hardwareGated then ns.Step() end
end

--==========================================================================
-- Login: remember the client, catch the original addon, say one line
--==========================================================================

local startup = CreateFrame("Frame")
startup:RegisterEvent("PLAYER_LOGIN")
startup:SetScript("OnEvent", function()
    if ns.Census and ns.Census.Init then ns.Census.Init() end
    ns.InstallWhoMover()

    -- GetBuildInfo returns MORE than four values on this client; name them.
    local version, build, _, toc = GetBuildInfo()
    local client = DenizensTWDB and DenizensTWDB.client
    if client then
        client.locale = ns.locale
        client.version, client.build, client.interface = version, build, tonumber(toc)
        -- Click mode was needed on this exact build before: start in it, so
        -- Blizzard's "AddOn blocked" box does not come back every session.
        if client.gatedBuild and client.gatedBuild == build then
            ns.hardwareGated = true
        end
    end

    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if isLoaded and isLoaded("Denizens") then ns.conflict = true end

    local function report()
        local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
        local addonVersion = (meta and meta(ADDON, "Version")) or "?"
        if client then client.addonVersion = addonVersion end
        local built, clientToc = ns.BUILT_FOR, tonumber(toc) or 0

        local notes = {}
        if ns.errors > 0 then
            notes[#notes + 1] = "|cffff5555" .. string.format(L["%d problem(s) - /dz debug"], ns.errors) .. "|r"
        end
        if built > 0 and clientToc > 0 and built ~= clientToc then
            notes[#notes + 1] = "|cffffd100" .. string.format(L["out of date - built for %d, client is %d"], built, clientToc) .. "|r"
        end
        if ns.hardwareGated then
            notes[#notes + 1] = L["click mode (this client needs a click for every /who)"]
        end

        if #notes == 0 then
            say(string.format(L["v%s loaded. |cffffd100/dz scan|r starts a census, |cffffd100/dz help|r lists commands."], addonVersion))
        else
            say(string.format(L["v%s loaded - %s"], addonVersion, table.concat(notes, "; ")))
        end
        if ns.conflict then
            say("|cffff5555" .. L["The original Denizens is also enabled. Two addons sending /who at once throttle each other, so Denizens TW will not scan. Untick one of them in the AddOns list at character select."] .. "|r")
        end
    end
    if C_Timer and C_Timer.After then C_Timer.After(4, report) else report() end

    if DenizensTWDB and DenizensTWDB.settings and DenizensTWDB.settings.auto then
        ns.ScheduleAuto(90)
    end
end)

-- Dump the ring buffer. This is where all the running commentary went.
function ns.DumpLog(n)
    local lines = ns.logLines
    if #lines == 0 then say("log is empty.") return end
    say(string.format("last %d of %d log lines:", math.min(n or 25, #lines), #lines))
    for i = math.max(1, #lines - (n or 25) + 1), #lines do
        print("  " .. lines[i])
    end
end
