-- Game adapter: tells a fished loot window from any other and hands its items to the dex.
-- Only a loot window opened by fishing counts (renaud's rule: an item bought at the auction
-- house or looted from a mob never fills the dex). Every game call is guarded.
local _, ns = ...

local Detect = {}
ns.Detect = Detect

-- Fishing ranks (Classic ids). A loot window that opens right after the player's own
-- fishing channel ends is fishing loot even if IsFishingLoot is missing on this client.
local FISHING_SPELLS = { [7620] = true, [7731] = true, [7732] = true, [18248] = true }
local CHANNEL_GRACE = 3 -- seconds between the end of the channel and the loot window

Detect.lastFishingStop = nil
local handled = false -- one loot window is read once (LOOT_READY then LOOT_OPENED)

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if not ok then return nil end
    if type(issecretvalue) == "function" and issecretvalue(a) then return nil end
    return a
end

function Detect.isFishingLoot(now)
    if safe(IsFishingLoot) == true then return true end
    local stop = Detect.lastFishingStop
    return stop ~= nil and now - stop <= CHANNEL_GRACE
end

-- Item ids of the open loot window (money and currency slots skipped).
function Detect.lootItemIDs()
    local ids = {}
    local n = safe(GetNumLootItems) or 0
    if type(n) ~= "number" then return ids end
    for slot = 1, n do
        local link = safe(GetLootSlotLink, slot)
        local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
        if id then ids[#ids + 1] = id end
    end
    return ids
end

function Detect.zoneName()
    local z = safe(GetRealZoneText) or safe(GetZoneText)
    if type(z) == "string" and z ~= "" then return z end
    return nil
end

-- Reads the loot window when it is fishing loot; returns the item ids caught for the first time.
function Detect.onLoot(db, now, clock)
    if handled then return {} end
    if not Detect.isFishingLoot(clock) then return {} end
    handled = true
    local fresh = {}
    local zone = Detect.zoneName()
    for _, id in ipairs(Detect.lootItemIDs()) do
        if ns.Dex.record(db, id, now, zone) then fresh[#fresh + 1] = id end
    end
    return fresh
end

function Detect.onEvent(event, a1, _, a3)
    local db = ns.Main and ns.Main.db
    if not db then return end
    if event == "LOOT_READY" or event == "LOOT_OPENED" then
        local fresh = Detect.onLoot(db, time(), GetTime())
        for _, id in ipairs(fresh) do ns.Announce.newCatch(id) end
        if #fresh > 0 or handled then ns.Main.refresh() end
    elseif event == "LOOT_CLOSED" then
        handled = false
        Detect.lastFishingStop = nil
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if a1 == "player" and FISHING_SPELLS[a3] then Detect.lastFishingStop = GetTime() end
    end
end

Detect.EVENTS = { "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED", "UNIT_SPELLCAST_CHANNEL_STOP" }
