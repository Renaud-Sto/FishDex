-- The fishing options (2026-11-05, to replace Better Fishing): game settings changed while
-- fishing and put back, auto loot, the double click's delay / mounted / recast, the
-- Options window.
local H = ...
local W = dofile("tests/fakewow.lua")

local function pure() return H.newNS("Locale", "Data", "Dex", "Shiny", "Lures", "Fishing").Fishing end

local function store(values)
    local cv = values
    return cv, function(k) return cv[k] end, function(k, v) cv[k] = v end
end

H.test("the options want names off and effects up, music and ambience off", function()
    local F = pure()
    H.eq(F.wanted({}), {})
    local w = F.wanted({ hideNames = true, loudSounds = true, loudVolume = 0.8 })
    H.eq(w.UnitNameNPC, "0")
    H.eq(w.nameplateShowFriendlyNPCs, "0")
    H.eq({ w.Sound_SFXVolume, w.Sound_MusicVolume, w.Sound_AmbienceVolume }, { "0.80", "0", "0" })
    H.eq(F.soundCVars(7).Sound_SFXVolume, "1.00")
    H.truthy(F.same("1", "1.000000"))
    H.falsy(F.same("1", "0.5"))
end)

H.test("a CVar is saved once, put back at the end, and the player's own change wins", function()
    local F = pure()
    local cv, get, set = store({ Sound_SFXVolume = "0.5", Sound_MusicVolume = "0.4", Sound_AmbienceVolume = "0.6" })
    local saved = {}
    F.apply(saved, F.wanted({ loudSounds = true, loudVolume = 1 }), get, set)
    H.eq(cv, { Sound_SFXVolume = "1.00", Sound_MusicVolume = "0", Sound_AmbienceVolume = "0" })
    -- a second apply (slider moved) keeps the first saved value
    F.apply(saved, F.wanted({ loudSounds = true, loudVolume = 0.6 }), get, set)
    H.eq(saved.Sound_SFXVolume, { was = "0.5", now = "0.60" })
    H.eq(cv.Sound_SFXVolume, "0.60")
    -- the player turns the music back on while fishing: kept at the end
    cv.Sound_MusicVolume = "0.9"
    F.restore(saved, get, set)
    H.eq(cv, { Sound_SFXVolume = "0.5", Sound_MusicVolume = "0.9", Sound_AmbienceVolume = "0.6" })
    H.eq(saved, {})
    -- a CVar this client lacks is never written
    F.apply(saved, F.wanted({ hideNames = true }), get, set)
    H.eq(cv.UnitNameNPC, nil)
    H.eq(saved, {})
end)

H.test("an option turned off while fishing puts its CVars back at once", function()
    local F = pure()
    local cv, get, set = store({ UnitNameNPC = "1", Sound_SFXVolume = "0.5", Sound_MusicVolume = "1",
        Sound_AmbienceVolume = "1" })
    local saved = {}
    F.apply(saved, F.wanted({ hideNames = true, loudSounds = true }), get, set)
    F.apply(saved, F.wanted({ hideNames = true }), get, set)
    H.eq({ cv.UnitNameNPC, cv.Sound_SFXVolume, cv.Sound_MusicVolume }, { "0", "0.5", "1" })
end)

H.test("a fishing spell is known by id, or by its name for a new rank", function()
    local Lures = H.newNS("Locale", "Data", "Dex", "Shiny", "Lures").Lures
    local names = { [7620] = "Fishing", [999999] = "Fishing", [133] = "Fireball" }
    local nameOf = function(id) return names[id] end
    H.truthy(Lures.isFishingSpell(7620, nameOf))
    H.truthy(Lures.isFishingSpell(999999, nameOf))
    H.falsy(Lures.isFishingSpell(133, nameOf))
    H.falsy(Lures.isFishingSpell(nil, nameOf))
    H.truthy(Lures.isFishingSpell(131476, function() return nil end))
end)

local function boot(cvars)
    local T = W.boot(H, { locale = "frFR" })
    local env = T.env
    T.cv, T.looted, T.combat, T.bindings = cvars or {}, {}, false, {}
    T.mounted, T.channel = false, nil
    T.loot = { "item:6291", "item:6303" }
    env.GetCVar = function(k) return T.cv[k] end
    env.SetCVar = function(k, v) T.cv[k] = v end
    env.InCombatLockdown = function() return T.combat end
    env.IsFishingLoot = function() return true end
    env.GetNumLootItems = function() return #T.loot end
    env.GetLootSlotLink = function(i) return T.loot[i] end
    env.LootSlot = function(i) T.looted[#T.looted + 1] = i end
    env.C_Spell = { GetSpellName = function(id) return id == 7620 and "Pêche" or nil end }
    env.GetInventoryItemID = function(_, slot) return slot == 16 and 6256 or nil end
    env.C_Item.GetItemInfoInstant = function(id) return id, "Weapon", "Fishing Poles", "INVTYPE_2HWEAPON", 1, 2, 20 end
    env.C_Item.GetItemCount = function() return 0 end
    env.IsPlayerSpell = function(id) return id == 7620 end
    env.IsMounted = function() return T.mounted end
    env.UnitChannelInfo = function() if T.channel then return "Pêche", "", 1, 0, 0, false, false, T.channel end end
    env.SetOverrideBindingClick = function(_, _, key, name) T.bindings[#T.bindings + 1] = { key, name } end
    T.fire("ADDON_LOADED", H.ADDON)
    T.fire("PLAYER_LOGIN")
    return T
end

local CV = { UnitNameNPC = "1", UnitNameFriendlySpecialNPCName = "1", UnitNameInteractiveNPC = "1",
    UnitNameNonCombatCreatureName = "1", nameplateShowFriendlyNPCs = "1" }
local function copy(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end

H.test("names are hidden from the cast to 20 s after the last catch, even through a long cast", function()
    local T = boot(copy(CV))
    T.env.FishDexDB.settings.hideNames = true
    T.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
    H.eq(T.cv.UnitNameNPC, "0")
    H.eq(T.cv.nameplateShowFriendlyNPCs, "0")
    T.tick(25) -- the bobber is still out
    H.eq(T.cv.UnitNameNPC, "0")
    T.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid", 7620)
    T.tick(15)
    H.eq(T.cv.UnitNameNPC, "0")
    T.tick(10)
    H.eq(T.cv, CV)
    H.eq(T.env.FishDexDB.fishing.saved, {})
end)

H.test("a crash leaves the saved values: the next login puts them back; logout does too", function()
    local T = boot(copy(CV))
    T.env.FishDexDB.settings.hideNames = true
    T.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
    H.eq(T.cv.UnitNameNPC, "0")
    T.fire("PLAYER_LOGOUT")
    H.eq(T.cv, CV)
    -- a crash: the client kept the changed values, the saved data kept the old ones
    local saved = { saved = { UnitNameNPC = { was = "1", now = "0" } } }
    local T2 = W.boot(H, { locale = "frFR" })
    T2.env.FishDexDB = { fishing = saved }
    local cv = { UnitNameNPC = "0" }
    T2.env.GetCVar = function(k) return cv[k] end
    T2.env.SetCVar = function(k, v) cv[k] = v end
    T2.fire("ADDON_LOADED", H.ADDON)
    T2.fire("PLAYER_LOGIN")
    H.eq(cv.UnitNameNPC, "1")
end)

H.test("a CVar change asked in combat waits for its end", function()
    local T = boot(copy(CV))
    T.env.FishDexDB.settings.hideNames = true
    T.combat = true
    T.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
    H.eq(T.cv.UnitNameNPC, "1")
    T.combat = false
    T.fire("PLAYER_REGEN_ENABLED")
    H.eq(T.cv.UnitNameNPC, "0")
end)

H.test("auto loot takes a fished window once, after FishDex read it, unless the game loots", function()
    local T = boot()
    local db = T.env.FishDexDB
    T.fire("LOOT_READY", false)
    H.eq(T.looted, {}) -- option off
    T.fire("LOOT_CLOSED")
    db.settings.autoLoot = true
    T.fire("LOOT_READY", false)
    T.fire("LOOT_OPENED", false)
    H.eq(T.looted, { 2, 1 })
    H.eq(db.catches[6291].count, 2) -- read before being taken
    T.fire("LOOT_CLOSED")
    T.fire("LOOT_READY", true) -- the game's own auto loot
    H.eq(T.looted, { 2, 1 })
    -- mob loot is never taken
    T.fire("LOOT_CLOSED")
    T.env.IsFishingLoot = function() return false end
    T.fire("LOOT_READY", false)
    H.eq(T.looted, { 2, 1 })
end)

H.test("the double click follows its delay, the mounted and the recast options", function()
    local T = boot()
    local DC, s = T.ns.DoubleCast, T.env.FishDexDB.settings
    local function double(gap)
        DC.onWorldDown("RightButton")
        T.clock = T.clock + gap
        DC.onWorldDown("RightButton")
        T.clock = T.clock + 5
    end
    s.castDelay = 0.25
    double(0.3)
    H.eq(#T.bindings, 0)
    double(0.2)
    H.eq(#T.bindings, 1)
    T.mounted = true
    double(0.1)
    H.eq(#T.bindings, 1)
    s.castMounted = true
    double(0.1)
    H.eq(#T.bindings, 2)
    T.mounted = false
    T.channel = 7620 -- the bobber is out
    double(0.1)
    H.eq(#T.bindings, 2)
    s.recast = true
    double(0.1)
    H.eq(#T.bindings, 3)
end)

local function find(T, test)
    for _, fr in ipairs(T.frames) do if test(fr) then return fr end end
end

local function click(box, on)
    box:SetChecked(on)
    rawget(box, "scripts").OnClick(box)
end

H.test("the Options window's boxes save every option, the double click keeps its button", function()
    local T = boot(copy(CV))
    local s = T.env.FishDexDB.settings
    T.ns.Options.toggle()
    H.truthy(T.env.FishDexOptionsWindow:IsShown())
    local function box(key) return find(T, function(fr) return fr.kind == "CheckButton" and rawget(fr, "key") == key end) end
    for _, key in ipairs({ "sound", "announce", "share", "lureButton", "autoLoot", "hideNames", "loudSounds",
        "doubleCast", "castMounted", "recast" }) do
        H.truthy(box(key))
    end
    H.truthy(box("doubleCast"):GetChecked())
    click(box("autoLoot"), true)
    H.eq(s.autoLoot, true)
    click(box("sound"), false)
    H.eq(s.sound, false)
    -- the button choice survives turning the double click off and on
    local swap = find(T, function(fr) return fr.text == T.ns.L.CAST_RightButton end)
    rawget(swap, "scripts").OnClick(swap)
    H.eq({ s.castButton, s.doubleCast }, { "LeftButton", "LeftButton" })
    click(box("doubleCast"), false)
    H.eq(s.doubleCast, "off")
    H.falsy(box("recast"):IsEnabled())
    click(box("doubleCast"), true)
    H.eq(s.doubleCast, "LeftButton")
    -- hide names turned on while fishing changes the game at once
    T.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
    click(box("hideNames"), true)
    H.eq(T.cv.UnitNameNPC, "0")
    click(box("hideNames"), false)
    H.eq(T.cv.UnitNameNPC, "1")
end)
