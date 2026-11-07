-- The fishing key (2026-11-07, after SKTools' Easy Fishing): one key casts, reels the bobber
-- in through the Interact Key once it is in reach, and takes the loot.
local H = ...
local W = dofile("tests/fakewow.lua")

local BOBBER = "GameObject-0-1-0-1-35591-0000ABCD"

H.test("the bobber is known by its GUID, and a secret GUID never counts", function()
    local K = H.newNS("Locale", "Data", "Dex", "Shiny", "Lures", "Fishing", "FishKey").FishKey
    H.truthy(K.isBobber(BOBBER))
    H.falsy(K.isBobber(BOBBER, true))
    H.falsy(K.isBobber("GameObject-0-1-0-1-1617-0000ABCD"))
    H.falsy(K.isBobber("Creature-0-1-0-1-35591-0000ABCD"))
    H.falsy(K.isBobber(nil))
end)

H.test("a press loots, then reels, then casts; nothing without a key or a pole", function()
    local K = H.newNS("Locale", "Data", "Dex", "Shiny", "Lures", "Fishing", "FishKey").FishKey
    local s = { bound = true, pole = true }
    H.eq(K.want(s), "cast")
    s.channeling = true
    H.eq(K.want(s), nil) -- out of reach: never a second cast, the key says so
    s.inReach = true
    H.eq(K.want(s), "reel")
    s.lootOpen = true
    H.eq(K.want(s), "loot")
    H.eq(K.want({ bound = false, pole = true }), nil)
    H.eq(K.want({ bound = true, pole = false }), nil)
    H.eq(K.castMacro("Pêche"), "/cast [nocombat,nomounted] Pêche")
    H.eq(K.castMacro(nil), nil)
end)

H.test("the key only adds the soft-target CVars when it is in use", function()
    local F = H.newNS("Locale", "Data", "Dex", "Shiny", "Lures", "Fishing", "FishKey").Fishing
    H.eq(F.wanted({}), {})
    H.eq(F.wanted({}, true), { SoftTargetInteract = "3", SoftTargetInteractRange = "30",
        SoftTargetInteractArc = "2", SoftTargetIconGameObject = "1", SoftTargetIconInteract = "1" })
end)

local function boot(keys)
    local T = W.boot(H, { locale = "frFR" })
    local env = T.env
    T.cv = { SoftTargetInteract = "1", SoftTargetInteractRange = "15", SoftTargetInteractArc = "0" }
    T.combat, T.over, T.looted, T.pole = false, {}, {}, true
    T.soft = nil
    env.GetCVar = function(k) return T.cv[k] end
    env.SetCVar = function(k, v) T.cv[k] = v end
    env.InCombatLockdown = function() return T.combat end
    env.IsFishingLoot = function() return true end
    env.GetNumLootItems = function() return 2 end
    env.GetLootSlotLink = function(i) return ({ "item:6291", "item:6303" })[i] end
    env.LootSlot = function(i) T.looted[#T.looted + 1] = i end
    env.C_Spell = { GetSpellName = function(id) return id == 7620 and "Pêche" or nil end }
    env.GetInventoryItemID = function(_, slot) return T.pole and slot == 16 and 6256 or nil end
    env.C_Item.GetItemInfoInstant = function(id) return id, "Weapon", "Fishing Poles", "INVTYPE_2HWEAPON", 1, 2, 20 end
    env.C_Item.GetItemCount = function() return 0 end
    env.IsPlayerSpell = function(id) return id == 7620 end
    env.UnitChannelInfo = function() end
    env.UnitGUID = function(unit) return unit == "softinteract" and T.soft or nil end
    env.GetBindingKey = function(action) if action == "FISHDEX_FISHKEY" then return unpack(keys or {}) end end
    env.ClearOverrideBindings = function() T.over = {} end
    env.SetOverrideBinding = function(_, _, key, action) T.over[key] = action end
    env.SetOverrideBindingClick = function(_, _, key, name) T.over[key] = "CLICK " .. name end
    T.fire("ADDON_LOADED", H.ADDON)
    T.fire("PLAYER_LOGIN")
    T.fire("PLAYER_ENTERING_WORLD")
    return T
end

H.test("the bound key casts, reels the bobber in once in reach, then loots", function()
    local T = boot({ "F" })
    local cast = T.env.FishDexKeyCastButton
    H.eq(T.over, { F = "CLICK FishDexKeyCastButton" })
    H.eq(T.ns.FishKeyButton.state(), "cast")
    -- the press starts the session: the Interact Key reaches the bobber before it lands
    rawget(cast, "scripts").PreClick(cast)
    H.eq(T.cv, { SoftTargetInteract = "3", SoftTargetInteractRange = "30", SoftTargetInteractArc = "2" })
    T.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
    H.eq(T.ns.FishKeyButton.state(), nil) -- out of reach: the key's own binding says so
    H.eq(T.over, {})
    T.fire("PLAYER_SOFT_INTERACT_CHANGED", nil, BOBBER)
    H.eq(T.over, { F = "INTERACTTARGET" })
    T.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid", 7620)
    T.fire("LOOT_OPENED", false)
    H.eq(T.over, { F = "CLICK FishDexKeyLootButton" })
    local loot = T.env.FishDexKeyLootButton
    rawget(loot, "scripts").OnClick(loot)
    H.eq(T.looted, { 2, 1 })
    T.fire("LOOT_CLOSED")
    H.eq(T.over, { F = "CLICK FishDexKeyCastButton" })
    -- the session ends 10 s after the last catch: the player's CVars come back
    T.tick(15)
    H.eq(T.cv, { SoftTargetInteract = "1", SoftTargetInteractRange = "15", SoftTargetInteractArc = "0" })
end)

H.test("no key bound or no pole: no override and no CVar change; combat waits", function()
    local T = boot({})
    T.env.FishDexDB.settings.doubleCast = "off"
    T.env.FishDexDB.settings.doubleReel = false
    H.eq(T.over, {})
    T.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
    H.eq(T.cv.SoftTargetInteract, "1")
    T.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid", 7620)
    local T2 = boot({ "F" })
    T2.pole = false
    T2.fire("PLAYER_EQUIPMENT_CHANGED", 16)
    H.eq(T2.over, {})
    T2.pole = true
    T2.combat = true
    T2.fire("PLAYER_EQUIPMENT_CHANGED", 16)
    H.eq(T2.over, {})
    T2.combat = false
    T2.fire("PLAYER_REGEN_ENABLED")
    H.eq(T2.over, { F = "CLICK FishDexKeyCastButton" })
    -- a secret soft target never turns the key into the Interact Key
    T2.env.issecretvalue = function(v) return v == BOBBER end
    T2.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
    T2.fire("PLAYER_SOFT_INTERACT_CHANGED", nil, BOBBER)
    H.falsy(T2.over.F == "INTERACTTARGET")
end)

H.test("a key is pressed with its modifiers; a lone modifier waits", function()
    local K = H.newNS("Locale", "Data", "Dex", "Shiny", "Lures", "Fishing", "FishKey").FishKey
    H.eq(K.chord("F"), "F")
    H.eq(K.chord("F", { alt = true, shift = true }), "ALT-SHIFT-F")
    H.eq(K.chord("LSHIFT", { shift = true }), nil)
end)

H.test("the Options window's button binds the fishing key, Escape cancels, right click clears", function()
    local T = boot({})
    local binds, saved = {}, 0
    T.env.GetBindingKey = function(action)
        local out = {}
        for k, a in pairs(binds) do if a == action then out[#out + 1] = k end end
        table.sort(out)
        return unpack(out)
    end
    T.env.GetBindingAction = function(k) return binds[k] or "" end
    T.env.SetBinding = function(k, a) binds[k] = a end
    T.env.SaveBindings = function() saved = saved + 1 end
    binds.F = "TOGGLEAUTORUN"
    T.ns.Options.toggle()
    local b = T.env.FishDexOptionsWindow.fishKeyButton
    H.eq(b:GetText(), T.ns.L.OPT_FISHKEY_NONE)
    rawget(b, "scripts").OnClick(b, "LeftButton")
    H.eq(b:GetText(), T.ns.L.OPT_FISHKEY_PRESS)
    rawget(b, "scripts").OnKeyDown(b, "ESCAPE")
    H.eq(binds, { F = "TOGGLEAUTORUN" })
    -- no key handler outside a capture: Escape and movement reach the game
    H.eq(rawget(b, "scripts").OnKeyDown, nil)
    rawget(b, "scripts").OnClick(b, "LeftButton")
    rawget(b, "scripts").OnKeyDown(b, "LSHIFT") -- waits for the key
    rawget(b, "scripts").OnKeyDown(b, "F")
    H.eq(binds, { F = "FISHDEX_FISHKEY" })
    H.eq(saved, 1)
    -- the player is told what the key did before (its label in game; the fake env's _G is
    -- plain Lua's, so the action name here)
    H.truthy(T.chat[#T.chat]:find("TOGGLEAUTORUN", 1, true) or T.chat[#T.chat]:find("Course auto", 1, true))
    T.fire("UPDATE_BINDINGS")
    H.eq(T.over, { F = "CLICK FishDexKeyCastButton" })
    -- a new key moves it
    rawget(b, "scripts").OnClick(b, "LeftButton")
    rawget(b, "scripts").OnKeyDown(b, "G")
    H.eq(binds, { G = "FISHDEX_FISHKEY" })
    rawget(b, "scripts").OnClick(b, "RightButton")
    H.eq(binds, {})
    -- in combat nothing is written
    T.combat = true
    rawget(b, "scripts").OnClick(b, "LeftButton")
    rawget(b, "scripts").OnKeyDown(b, "F")
    H.eq(binds, {})
end)

H.test("the Interact Key fishes too, and keeps its own job while an NPC is its target", function()
    local T = boot({})
    local binds = { X = "INTERACTTARGET" }
    T.env.GetBindingKey = function(action)
        for k, a in pairs(binds) do if a == action then return k end end
    end
    T.fire("UPDATE_BINDINGS")
    H.eq(T.over, { X = "CLICK FishDexKeyCastButton" })
    -- an NPC in front: X talks to it
    T.fire("PLAYER_SOFT_INTERACT_CHANGED", nil, "Creature-0-1-0-1-3333-0000ABCD")
    H.eq(T.over, {})
    T.fire("PLAYER_SOFT_INTERACT_CHANGED", "Creature-0-1-0-1-3333-0000ABCD", nil)
    H.eq(T.over, { X = "CLICK FishDexKeyCastButton" })
    -- fishing: the bobber in reach makes X the Interact Key again (the game's own action)
    T.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
    T.fire("PLAYER_SOFT_INTERACT_CHANGED", nil, BOBBER)
    H.eq(T.over, { X = "INTERACTTARGET" })
    T.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid", 7620)
    T.fire("PLAYER_SOFT_INTERACT_CHANGED", BOBBER, nil)
    -- the option off: X is left alone
    T.env.FishDexDB.settings.useInteractKey = false
    T.fire("UPDATE_BINDINGS")
    H.eq(T.over, {})
    -- the fishing key's own key never gives way to an NPC
    binds.F = "FISHDEX_FISHKEY"
    T.env.GetBindingKey = function(action)
        local out = {}
        for k, a in pairs(binds) do if a == action then out[#out + 1] = k end end
        return unpack(out)
    end
    T.env.FishDexDB.settings.useInteractKey = true
    T.fire("PLAYER_SOFT_INTERACT_CHANGED", nil, "Creature-0-1-0-1-3333-0000ABCD")
    H.eq(T.over, { F = "CLICK FishDexKeyCastButton" })
end)

H.test("the double click reels the bobber in once it is in reach, after the first release", function()
    local T = boot({})
    local held = true
    T.env.IsMouseButtonDown = function() return held end
    T.env.UnitChannelInfo = function() if T.channeling then return "Pêche", "", 1, 0, 0, false, false, 7620 end end
    -- the double click alone turns the soft-target CVars on while fishing
    T.channeling = true
    T.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
    H.eq(T.cv.SoftTargetInteract, "3")
    T.fire("PLAYER_SOFT_INTERACT_CHANGED", nil, BOBBER)
    T.ns.DoubleCast.onWorldDown("RightButton")
    T.tick(0.02)
    H.eq(T.over, {}) -- still held: the camera's turn keeps its binding
    held = false
    T.tick(0.02)
    H.eq(T.over, { BUTTON2 = "INTERACTTARGET" })
    T.run() -- the window ends
    H.eq(T.over, {})
    -- released too late: nothing
    held = true
    T.ns.DoubleCast.onWorldDown("RightButton")
    T.tick(1)
    held = false
    T.tick(0.02)
    H.eq(T.over, {})
    -- out of reach: the double click does nothing while the bobber is out
    T.fire("PLAYER_SOFT_INTERACT_CHANGED", BOBBER, nil)
    T.ns.DoubleCast.onWorldDown("RightButton")
    T.clock = T.clock + 0.1
    T.ns.DoubleCast.onWorldDown("RightButton")
    T.tick(0.02)
    H.eq(T.over, {})
end)

H.test("cast and reel in are two options; left and right click never become fishing keys", function()
    local T = boot({})
    local s = T.env.FishDexDB.settings
    local held = false
    T.env.IsMouseButtonDown = function() return held end
    T.env.UnitChannelInfo = function() if T.channeling then return "Pêche", "", 1, 0, 0, false, false, 7620 end end
    -- reel in off: a click while the bobber is in reach binds nothing
    s.doubleReel = false
    T.channeling = true
    T.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
    T.fire("PLAYER_SOFT_INTERACT_CHANGED", nil, BOBBER)
    T.ns.DoubleCast.onWorldDown("RightButton")
    T.tick(0.02)
    H.eq(T.over, {})
    -- reel in on, cast off: the double click still reels in
    s.doubleReel, s.doubleCast = true, "off"
    T.ns.DoubleCast.onWorldDown("RightButton")
    T.tick(0.02)
    H.eq(T.over, { BUTTON2 = "INTERACTTARGET" })
    -- that moment's BUTTON2 -> Interact Key is never read back as an Interact Key to fish with
    local binds = { X = "INTERACTTARGET", BUTTON2 = "INTERACTTARGET" }
    T.env.GetBindingKey = function(action)
        local out = {}
        for k, a in pairs(binds) do if a == action then out[#out + 1] = k end end
        table.sort(out)
        return unpack(out)
    end
    T.run()
    T.channeling = false
    T.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid", 7620)
    T.fire("PLAYER_SOFT_INTERACT_CHANGED", BOBBER, nil)
    T.fire("UPDATE_BINDINGS")
    H.eq(T.over, { X = "CLICK FishDexKeyCastButton" })
    -- cast off: no double click cast
    T.ns.DoubleCast.onWorldDown("RightButton")
    T.clock = T.clock + 0.1
    T.ns.DoubleCast.onWorldDown("RightButton")
    H.eq(T.over, { X = "CLICK FishDexKeyCastButton" })
end)
