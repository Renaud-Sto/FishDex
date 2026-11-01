-- Fishing comfort: the lure button and the double click to fish.
local H = ...
local W = dofile("tests/fakewow.lua")

local function pure()
    return H.newNS("Locale", "Data", "Dex", "Shiny", "Lures").Lures
end

H.test("lures in the bags, best first; the chosen one is offered while the bags hold it", function()
    local Lures = pure()
    local bags = { [6529] = 3, [6533] = 1, [6530] = 0 }
    local list = Lures.inBags(function(id) return bags[id] end)
    H.eq(#list, 2)
    H.eq(list[1].id, 6533)
    H.eq(Lures.pick(list, 6529).id, 6529)
    H.eq(Lures.pick(list, 6530).id, 6533) -- none left: the best one
    H.eq(Lures.pick({}, 6529), nil)
    H.eq(Lures.ordered(list, 6529)[1].id, 6529)
end)

H.test("pole, spell, time left and double click", function()
    local Lures = pure()
    H.truthy(Lures.isPole(2, 20))
    H.falsy(Lures.isPole(2, 7))
    H.eq(Lures.fishingSpell(function(id) return id == 7620 end), 7620)
    H.eq(Lures.fishingSpell(function(id) return id == 131474 end), 131474)
    H.eq(Lures.fishingSpell(function() return false end), nil)
    H.eq(Lures.timeLeft(600000), "10:00")
    H.eq(Lures.timeLeft(42500), "42 s")
    H.eq(Lures.timeLeft(0), nil)
    H.truthy(Lures.isDouble(10, "RightButton", 10.3, "RightButton"))
    H.falsy(Lures.isDouble(10, "RightButton", 10.6, "RightButton"))
    H.falsy(Lures.isDouble(10, "LeftButton", 10.1, "RightButton"))
    H.falsy(Lures.isDouble(nil, nil, 10, "RightButton"))
end)

local function boot()
    local T = W.boot(H, { locale = "frFR" })
    local env = T.env
    T.pole, T.bags, T.combat, T.bindings = 6256, { [6529] = 2, [6532] = 1 }, false, {}
    env.GetInventoryItemID = function(_, slot) return slot == 16 and T.pole or nil end
    env.C_Item.GetItemInfoInstant = function(id)
        if id == 6256 then return id, "Weapon", "Fishing Poles", "INVTYPE_2HWEAPON", 1, 2, 20 end
        return id, "Weapon", "Swords", "INVTYPE_WEAPON", 1, 2, 7
    end
    env.C_Item.GetItemCount = function(id) return T.bags[id] or 0 end
    env.C_Item.GetItemIconByID = function(id) return id end
    env.InCombatLockdown = function() return T.combat end
    env.IsPlayerSpell = function(id) return id == 7620 end
    env.IsMounted = function() return false end
    env.SetOverrideBindingClick = function(_, _, key, name) T.bindings[#T.bindings + 1] = { key, name } end
    T.fire("ADDON_LOADED", H.ADDON)
    T.fire("PLAYER_LOGIN")
    return T
end

H.test("the lure button shows with a pole, offers the best lure, and a choice from the list", function()
    local T = boot()
    local b = T.env.FishDexLureButton
    H.truthy(b and b:IsShown())
    H.eq(rawget(b, "lureID"), 6532)
    -- the hover list holds the other lure; clicking it makes it the offered one
    local choice
    for _, fr in ipairs(T.frames) do if rawget(fr, "lureID") == 6529 and fr ~= b then choice = fr end end
    H.truthy(choice)
    rawget(choice, "scripts").OnClick(choice)
    H.eq(rawget(b, "lureID"), 6529)
    H.eq(T.env.FishDexDB.settings.lure.id, 6529)
    -- no pole: hidden; in combat the change waits for the end of combat
    T.combat = true
    T.pole = 1234
    T.fire("PLAYER_EQUIPMENT_CHANGED")
    H.truthy(b:IsShown())
    T.combat = false
    T.fire("PLAYER_REGEN_ENABLED")
    H.falsy(b:IsShown())
end)

H.test("a double right click on the world binds the right button to the fishing cast, once", function()
    local T = boot()
    local DC = T.ns.DoubleCast
    DC.onWorldDown("RightButton")
    H.eq(#T.bindings, 0)
    T.clock = T.clock + 0.2
    DC.onWorldDown("RightButton")
    H.eq(T.bindings, { { "BUTTON2", "FishDexCastButton" } })
    -- a left double click does nothing in the right-click mode; "off" stops everything
    DC.onWorldDown("LeftButton")
    DC.onWorldDown("LeftButton")
    H.eq(#T.bindings, 1)
    T.env.SlashCmdList.FISHDEX("clic") -- right -> left
    T.env.SlashCmdList.FISHDEX("clic") -- left -> off
    H.eq(T.env.FishDexDB.settings.doubleCast, "off")
    DC.onWorldDown("RightButton")
    DC.onWorldDown("RightButton")
    H.eq(#T.bindings, 1)
end)

H.test("test mode: without a pole, /fishdex testcanne shows the button until turned off", function()
    local T = boot()
    T.pole = nil
    T.fire("PLAYER_EQUIPMENT_CHANGED")
    local b = T.env.FishDexLureButton
    H.falsy(b and b:IsShown())
    T.env.SlashCmdList.FISHDEX("testcanne")
    b = T.env.FishDexLureButton
    H.truthy(b and b:IsShown())
    T.env.SlashCmdList.FISHDEX("testcanne")
    H.falsy(b:IsShown())
end)
