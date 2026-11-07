-- Pure logic of the fishing key (renaud, 2026-11-07, the way SKTools' Easy Fishing does it):
-- one key the player binds in the game's Key Bindings (Bindings.xml, FishDex section) casts
-- Fishing, then reels the bobber in once it is in the game's Interact Key reach, then takes
-- the loot. Nothing tells an addon that a fish bit: every press is the player's own, and the
-- key only changes what that press does (UI/FishKeyButton.lua sets the override bindings).
local _, ns = ...

local FishKey = {}
ns.FishKey = FishKey

-- The bobber: GameObject entry 35591, summoned by every Fishing rank (SKTools, measured on
-- Forever by its author). Its GUID is "GameObject-0-server-instance-zone-35591-spawn".
FishKey.BOBBER_ID = 35591

-- While a session runs with the key bound: the Interact Key works from the keyboard
-- (Enum.SoftTargetEnableFlags.Any), reaches 30 yd (Forever's bobber lands 10-20 yd out)
-- and anywhere in front. Put back at the session's end like the other fishing CVars.
FishKey.CVARS = {
    SoftTargetInteract = "3",
    SoftTargetInteractRange = "30",
    SoftTargetInteractArc = "2",
    -- the hand icon over the bobber: the player sees when a press reels it in
    SoftTargetIconGameObject = "1",
    SoftTargetIconInteract = "1",
}

-- Whether a soft-interact GUID is the bobber. A secret GUID (`secret` true) cannot be read:
-- it never counts, and no string operation touches it.
function FishKey.isBobber(guid, secret)
    if secret or type(guid) ~= "string" then return false end
    local id = guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    return tonumber(id) == FishKey.BOBBER_ID
end

-- What a press does, first match wins: "loot" (a fished loot window is open), "reel" (the
-- bobber is out and in reach), "cast", or nil (the key falls back to its own binding, which
-- only says why). `s` holds: bound, pole, lootOpen, channeling, inReach. Never a second
-- cast while the bobber is out: it would lose the fish (renaud, 2026-11-07).
function FishKey.want(s)
    if not s.bound or not s.pole then return nil end
    if s.lootOpen then return "loot" end
    if s.channeling and s.inReach then return "reel" end
    if s.channeling then return nil end
    return "cast"
end

-- The cast macro: never in combat or mounted (a cast would dismount the player).
function FishKey.castMacro(name)
    if type(name) ~= "string" or name == "" then return nil end
    return "/cast [nocombat,nomounted] " .. name
end

-- Keys that never make a fishing key on their own (a modifier is held with another key).
FishKey.MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true, UNKNOWN = true }
-- Mouse buttons that can be the key; left and right stay the mouse's.
FishKey.MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

-- The binding string of a key pressed with modifiers ("ALT-CTRL-SHIFT-F"), nil for a lone
-- modifier. `mods` holds alt, ctrl, shift.
function FishKey.chord(key, mods)
    if type(key) ~= "string" or key == "" or FishKey.MODIFIERS[key] then return nil end
    mods = mods or {}
    local parts = {}
    if mods.alt then parts[#parts + 1] = "ALT" end
    if mods.ctrl then parts[#parts + 1] = "CTRL" end
    if mods.shift then parts[#parts + 1] = "SHIFT" end
    parts[#parts + 1] = key
    return table.concat(parts, "-")
end
