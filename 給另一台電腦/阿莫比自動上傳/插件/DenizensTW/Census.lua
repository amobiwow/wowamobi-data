--[[ Denizens TW census ---------------------------------------------------

Persistent population data. Every /who reply - ours, a deep scan's, or one you
typed yourself - is folded into a saved roster, so the picture accumulates
across sessions instead of dying with the window.

On what this can and cannot know
--------------------------------
A /who census is a record of who was SEEN, never of who EXISTS. Three honest
limits, stated here so the UI can stop short of claiming more:

  * Offline players are invisible. A census is a sample of the online
    population at the moments you happened to scan.
  * Deletes, renames and transfers are unobservable. A character that is gone
    looks exactly like a character that has not logged in. This is why the
    headline number is "seen in the last N days" and the all-time total is
    reported separately rather than as "the population".
  * The server caps each reply at 50, so any single query is a ceiling, not a
    count. Deep scan exists to work around that; see Core.lua.

So: treat "active" as the real figure, "known" as an upper bound that only
ever grows, and never present either as a server population.

Fork changes: the roster keeps the locale-free class file (token) and gender,
the cap is 100,000 characters (was 25,000) with an O(1) running count and
pruning in batches instead of a full sort on every reply, each scan records
how long it took and how much it found, and a version bump migrates the saved
data instead of wiping it.
--]]

local ADDON, ns = ...
local L = ns.L

local DB_VERSION = 2
local DEFAULT_MAX_PLAYERS = 100000   -- prune beyond this, oldest sighting first
local PRUNE_TO = 0.95                -- ...down to 95%, so pruning is rare
local MAX_SCANS = 500
local ACTIVE_WINDOW = 7 * 24 * 3600

ns.Census = {}
local Census = ns.Census

local function realmKey()
    -- Forever is realmless, but GetRealmName still returns something stable,
    -- and keying by it means an Era install and a Forever install cannot
    -- pollute each other's roster.
    local realm = (GetRealmName and GetRealmName()) or "Unknown"
    local faction = (UnitFactionGroup and UnitFactionGroup("player")) or "Neutral"
    return realm .. " - " .. faction
end
Census.RealmKey = realmKey

local function defaultSettings()
    return {
        takeover = false,       -- the fork's default: never touch Blizzard's pane
        autoRecord = true,
        auto = false,
        autoMinutes = 30,
        maxPlayers = DEFAULT_MAX_PLAYERS,
    }
end

local function newRealm()
    return { players = {}, scans = {}, count = 0, races = {}, classes = {} }
end

function Census.Init()
    if type(DenizensTWDB) ~= "table" then
        DenizensTWDB = { version = DB_VERSION, realms = {} }
    end
    local db = DenizensTWDB
    -- Never wipe on a version change: migrate what is there.
    if db.version ~= DB_VERSION then db.version = DB_VERSION end
    db.addon = ADDON
    db.realms = db.realms or {}
    db.client = db.client or {}
    db.settings = db.settings or {}
    for k, v in pairs(defaultSettings()) do
        if db.settings[k] == nil then db.settings[k] = v end
    end

    -- At ADDON_LOADED the player's faction may not be known yet. Do not create
    -- a stray "Realm - Neutral" roster; PLAYER_LOGIN runs this again.
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if faction ~= "Alliance" and faction ~= "Horde" then
        Census.db = nil
        return nil
    end
    local key = realmKey()
    local r = db.realms[key] or newRealm()
    db.realms[key] = r
    r.players = r.players or {}
    r.scans = r.scans or {}
    r.races = r.races or {}
    r.classes = r.classes or {}
    if type(r.count) ~= "number" then
        local n = 0
        for _ in pairs(r.players) do n = n + 1 end
        r.count = n
    end
    Census.db = r
    return r
end

-- Before login (faction unknown) this hands back a throwaway roster, so a
-- caller can never index nil; nothing real is recorded before login anyway.
local function db()
    return Census.db or Census.Init() or newRealm()
end

--==========================================================================
-- recording
--==========================================================================

function Census.Prune()
    local r = db()
    local max = tonumber(DenizensTWDB and DenizensTWDB.settings and DenizensTWDB.settings.maxPlayers)
                or DEFAULT_MAX_PLAYERS
    if r.count <= max then return 0 end

    local list = {}
    for name, p in pairs(r.players) do list[#list + 1] = { name = name, last = p.last or 0 } end
    table.sort(list, function(a, b) return a.last < b.last end)
    local target = math.floor(max * PRUNE_TO)
    local drop = #list - target
    for i = 1, drop do r.players[list[i].name] = nil end
    r.count = #list - drop
    ns.log(string.format("pruned %d oldest sightings (cap %d)", drop, max))
    return drop
end

-- Fold a batch of sightings in. Returns how many were new, which is the only
-- number that tells you whether a scan is still discovering anything.
function Census.Record(rows)
    if not DenizensTWDB or not (DenizensTWDB.settings and DenizensTWDB.settings.autoRecord) then
        return 0, 0
    end
    local r = db()
    local store, now, new, updated = r.players, time(), 0, 0
    for _, row in ipairs(rows) do
        local p = store[row.name]
        if not p then
            new = new + 1
            p = { first = now, seen = 0 }
            store[row.name] = p
        else
            updated = updated + 1
        end
        p.lvl   = row.level
        p.class = row.class
        if row.token and row.token ~= "" then p.token = row.token end
        p.race  = row.race
        p.sex   = row.sex
        p.guild = row.guild
        p.area  = row.zone          -- subzone, not the parent zone
        p.last  = now
        p.seen  = (p.seen or 0) + 1
        if row.race and row.race ~= "" then r.races[row.race] = true end
        if row.class and row.class ~= "" then r.classes[row.class] = row.token or true end
    end
    r.count = r.count + new
    if new > 0 then Census.Prune() end
    return new, updated
end

-- Class or race names this realm and faction has actually returned, in the
-- client's own language. Core uses them so a split never misses a value.
function Census.Observed(kind)
    local out = {}
    local set = db()[kind]
    if type(set) == "table" then
        for name in pairs(set) do out[#out + 1] = name end
        table.sort(out)
    end
    return out
end

function Census.NoteScan(record)
    local scans = db().scans
    scans[#scans + 1] = record
    while #scans > MAX_SCANS do table.remove(scans, 1) end
end

function Census.LastScan()
    local scans = db().scans
    for i = #scans, 1, -1 do
        if not scans[i].cancelled then return scans[i] end
    end
    return nil
end

--==========================================================================
-- reporting
--==========================================================================

function Census.Stats()
    local store, now = db().players, time()
    local s = {
        known = 0, active = 0, guilds = 0, guilded = 0,
        maxLevel = 0, byBracket = {}, byClass = {},
    }
    local guildSet = {}
    for _, p in pairs(store) do
        s.known = s.known + 1
        if p.last and (now - p.last) <= ACTIVE_WINDOW then s.active = s.active + 1 end
        local lvl = p.lvl or 0
        if lvl > s.maxLevel then s.maxLevel = lvl end
        local bracket = math.floor(lvl / 10) * 10
        s.byBracket[bracket] = (s.byBracket[bracket] or 0) + 1
        if p.class and p.class ~= "" then
            s.byClass[p.class] = (s.byClass[p.class] or 0) + 1
        end
        if p.guild and p.guild ~= "" then
            s.guilded = s.guilded + 1
            if not guildSet[p.guild] then
                guildSet[p.guild] = 0
                s.guilds = s.guilds + 1
            end
            guildSet[p.guild] = guildSet[p.guild] + 1
        end
    end
    s.guildSet = guildSet
    return s
end

function Census.TopGuilds(limit, stats)
    local s = stats or Census.Stats()
    local list = {}
    for name, count in pairs(s.guildSet) do
        list[#list + 1] = { name = name, count = count }
    end
    table.sort(list, function(a, b)
        if a.count == b.count then return a.name < b.name end
        return a.count > b.count
    end)
    while #list > (limit or 10) do table.remove(list) end
    return list
end

function Census.Summary(stats)
    local s = stats or Census.Stats()
    local out = {
        string.format("|cffffd100%s|r", realmKey()),
        "  " .. string.format(L["active (seen in 7 days): |cff66ff66%d|r"], s.active),
        "  " .. string.format(L["known ever (upper bound, includes deleted): %d"], s.known),
        "  " .. string.format(L["guilds seen: %d   in a guild: %d%%"], s.guilds,
            s.known > 0 and math.floor(s.guilded / s.known * 100) or 0),
        "  " .. string.format(L["highest level seen: %d"], s.maxLevel),
    }
    local brackets = {}
    for b in pairs(s.byBracket) do brackets[#brackets + 1] = b end
    table.sort(brackets)
    local parts = {}
    for _, b in ipairs(brackets) do
        parts[#parts + 1] = string.format("%d-%d:%d", b == 0 and 1 or b,
            b + 9, s.byBracket[b])
    end
    if #parts > 0 then out[#out + 1] = "  " .. L["levels"] .. "  " .. table.concat(parts, "  ") end

    local last = Census.LastScan()
    if last and last.at then
        out[#out + 1] = "  " .. string.format(L["last scan: %s ago, %d found, %d new, %d queries"],
            ns.FormatDuration(time() - last.at), last.found or 0, last.new or 0, last.sent or 0)
    end
    return out
end

function Census.Wipe()
    local key = realmKey()
    DenizensTWDB.realms[key] = newRealm()
    Census.db = DenizensTWDB.realms[key]
end

--==========================================================================
-- wiring
--==========================================================================

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= ADDON then return end
    Census.Init()
end)
