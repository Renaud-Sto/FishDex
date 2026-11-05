-- Pure logic of the fishing options (renaud, 2026-11-05, to replace Better Fishing): which
-- game settings (CVars) change while fishing, and how they are saved and put back. The
-- game calls come in as arguments: get(name) -> string or nil, set(name, value).
local _, ns = ...

local Fishing = {}
ns.Fishing = Fishing

-- A fishing session ends this many seconds after the last cast or catch.
Fishing.IDLE = 20

-- Friendly NPC names and nameplates off; hostile ones are left as the player set them.
Fishing.NAME_CVARS = {
    UnitNameNPC = "0",
    UnitNameFriendlySpecialNPCName = "0",
    UnitNameInteractiveNPC = "0",
    UnitNameNonCombatCreatureName = "0",
    nameplateShowFriendlyNPCs = "0",
}

-- Louder splash: effects at `volume` (0..1), music and ambience off.
function Fishing.soundCVars(volume)
    if type(volume) ~= "number" then volume = 1 end
    volume = math.max(0, math.min(1, volume))
    return {
        Sound_SFXVolume = string.format("%.2f", volume),
        Sound_MusicVolume = "0",
        Sound_AmbienceVolume = "0",
    }
end

-- Every CVar the options want while fishing: name -> value.
function Fishing.wanted(settings)
    local out = {}
    if settings.hideNames then
        for k, v in pairs(Fishing.NAME_CVARS) do out[k] = v end
    end
    if settings.loudSounds then
        for k, v in pairs(Fishing.soundCVars(settings.loudVolume)) do out[k] = v end
    end
    return out
end

-- "1" and "1.000000" are the same value for the game.
function Fishing.same(a, b)
    if a == b then return true end
    local x, y = tonumber(a), tonumber(b)
    return x ~= nil and y ~= nil and math.abs(x - y) < 0.001
end

-- Puts one CVar back, unless the player changed it meanwhile (their choice wins).
local function restoreOne(saved, name, get, set)
    local s = saved[name]
    saved[name] = nil
    if type(s) ~= "table" then return end
    if Fishing.same(get(name), s.now) then set(name, s.was) end
end

-- Moves the game to `wanted`: each CVar is saved once (saved[name] = { was, now }) before
-- its first change, a CVar no longer wanted goes back. A CVar this client lacks (get
-- answers nil) is left alone.
function Fishing.apply(saved, wanted, get, set)
    for name in pairs(saved) do
        if wanted[name] == nil then restoreOne(saved, name, get, set) end
    end
    for name, value in pairs(wanted) do
        local s = saved[name]
        if s then
            if not Fishing.same(s.now, value) then
                s.now = value
                set(name, value)
            end
        else
            local current = get(name)
            if current ~= nil then
                saved[name] = { was = current, now = value }
                set(name, value)
            end
        end
    end
end

-- Puts every saved CVar back (end of the session, logout, or a login after a crash).
function Fishing.restore(saved, get, set)
    local names = {}
    for name in pairs(saved) do names[#names + 1] = name end
    for _, name in ipairs(names) do restoreOne(saved, name, get, set) end
end

-- Still fishing: a cast or catch less than IDLE seconds ago.
function Fishing.active(last, now)
    return type(last) == "number" and now - last <= Fishing.IDLE
end
