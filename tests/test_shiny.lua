-- Shiny catches: the roll, the saved records, and the announce in the fake game.
local H = ...
local W = dofile("tests/fakewow.lua")

local function pure()
    local ns = H.newNS("Locale", "Data", "Dex", "Shiny")
    return ns, ns.Dex.repair({})
end

H.test("a roll maps to the best grade first, then a normal catch", function()
    local ns = pure()
    local S = ns.Shiny
    local l, r, s = S.GRADES[1].chance, S.GRADES[2].chance, S.GRADES[3].chance
    H.eq(S.fromRoll(0), "legendary")
    H.eq(S.fromRoll(l - 1e-9), "legendary")
    H.eq(S.fromRoll(l), "rare")
    H.eq(S.fromRoll(l + r - 1e-9), "rare")
    H.eq(S.fromRoll(l + r), "shiny")
    H.eq(S.fromRoll(l + r + s), nil)
    H.eq(S.fromRoll(0.999), nil)
end)

H.test("only fish and rare fish can be shiny", function()
    local ns = pure()
    H.truthy(ns.Shiny.eligible(ns.Dex.entry(6291)))
    H.truthy(ns.Shiny.eligible(ns.Dex.entry(6717)))
    H.falsy(ns.Shiny.eligible(ns.Dex.entry(6356)))
    H.falsy(ns.Shiny.eligible(nil))
end)

H.test("shiny records count per grade and the best grade wins", function()
    local ns, db = pure()
    H.truthy(ns.Shiny.record(db, 6291, "shiny", 10))
    H.falsy(ns.Shiny.record(db, 6291, "shiny", 20))
    H.eq(ns.Shiny.best(db, 6291), "shiny")
    H.truthy(ns.Shiny.record(db, 6291, "legendary", 30))
    H.eq(ns.Shiny.best(db, 6291), "legendary")
    H.eq(db.shiny[6291].shiny, { count = 2, first = 10 })
    local list, done = ns.Shiny.list(db)
    H.eq(done, 1)
    H.eq(#list, #ns.Dex.list(db, "fish") + #ns.Dex.list(db, "rare"))
    H.eq({ ns.Dex.progress(db, "shiny") }, { 1, #list })
end)

local function boot(roll)
    local T = W.boot(H, { locale = "frFR" })
    local env = T.env
    T.loot, T.notices, T.sounds = {}, {}, {}
    env.IsFishingLoot = function() return true end
    env.GetNumLootItems = function() return #T.loot end
    env.GetLootSlotLink = function(i) return "|Hitem:" .. T.loot[i] .. "::|h[x]|h" end
    env.RaidWarningFrame = {}
    env.RaidNotice_AddMessage = function(_, text, color) T.notices[#T.notices + 1] = { text, color } end
    env.SOUNDKIT = { UI_EPICLOOT_TOAST = 1, UI_LEGENDARY_LOOT_TOAST = 2 }
    env.PlaySound = function(id) T.sounds[#T.sounds + 1] = id end
    T.fire("ADDON_LOADED", H.ADDON)
    T.ns.Detect.roll = function() return roll end
    return T
end

local function fish(T, id)
    T.loot = { id }
    T.fire("LOOT_OPENED")
    T.fire("LOOT_CLOSED")
end

H.test("a shiny catch is saved and announced in its grade colour instead of the normal announce", function()
    local T = boot(0) -- 0 is always legendary
    fish(T, 6291)
    H.eq(T.env.FishDexDB.shiny[6291].legendary.count, 1)
    H.eq(T.env.FishDexDB.catches[6291].count, 1)
    H.eq(#T.notices, 1)
    H.truthy(T.notices[1][1]:find("Shiny légendaire", 1, true))
    H.truthy(T.notices[1][1]:find("une première", 1, true))
    H.eq(T.notices[1][2].g, 0.5)
    H.eq(T.sounds, { 2 })
    fish(T, 6291)
    H.falsy(T.notices[2][1]:find("une première", 1, true))
end)

H.test("a normal roll leaves shinies alone; chests never roll", function()
    local T = boot(0.99)
    fish(T, 6291)
    H.eq(T.env.FishDexDB.shiny, {})
    T.ns.Detect.roll = function() return 0 end
    fish(T, 6356)
    H.eq(T.env.FishDexDB.shiny, {})
end)

H.test("/fishdex shinytest forces the next eligible catch only", function()
    local T = boot(0.99)
    T.env.SlashCmdList.FISHDEX("shinytest rare")
    fish(T, 6356) -- a chest: not eligible, the forced grade waits
    fish(T, 6291)
    H.eq(T.ns.Shiny.best(T.env.FishDexDB, 6291), "rare")
    fish(T, 6303)
    H.eq(T.ns.Shiny.best(T.env.FishDexDB, 6303), nil)
end)

H.test("the shiny tab opens and shows one slot per eligible entry", function()
    local T = boot(0)
    fish(T, 6291)
    T.env.SlashCmdList.FISHDEX("")
    local win = T.env.FishDexWindow
    local shinyTab
    for _, fr in ipairs(T.frames) do if rawget(fr, "cat") == "shiny" then shinyTab = fr end end
    H.truthy(shinyTab)
    rawget(shinyTab, "scripts").OnClick(shinyTab)
    local shown = 0
    for _, fr in ipairs(T.frames) do
        if fr.kind == "Button" and rawget(fr, "parent") == rawget(win, "grid") and fr.shown then shown = shown + 1 end
    end
    H.eq(shown, #T.ns.Shiny.list(T.env.FishDexDB))
end)
