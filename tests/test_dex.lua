-- Pure dex logic: saved data, catches, categories, recipe state.
local H = ...

local function load()
    local ns = H.newNS("Locale", "Data", "Dex", "Shiny")
    return ns, ns.Dex.repair({})
end

H.test("a first catch is new, the next ones only count", function()
    local ns, db = load()
    H.truthy(ns.Dex.record(db, 6291, 100, "Elwynn"))
    H.falsy(ns.Dex.record(db, 6291, 200, "Westfall"))
    H.eq(db.catches[6291], { count = 2, first = 100, zone = "Elwynn" })
end)

H.test("an item missing from the data is still recorded, in the discoveries tab", function()
    local ns, db = load()
    H.eq(#ns.Dex.categories(db), 6)
    H.truthy(ns.Dex.record(db, 999999, 1, nil))
    local cats = ns.Dex.categories(db)
    H.eq(cats[#cats], "found")
    H.eq(ns.Dex.list(db, "found")[1].id, 999999)
    local caught, total = ns.Dex.progress(db)
    H.eq({ caught, total }, { 0, #ns.Data.ENTRIES })
end)

H.test("progress counts per category", function()
    local ns, db = load()
    ns.Dex.record(db, 6291, 1)
    ns.Dex.record(db, 6356, 1)
    local c, t = ns.Dex.progress(db, "fish")
    H.eq(c, 1)
    H.eq(t, #ns.Dex.list(db, "fish"))
    H.eq(({ ns.Dex.progress(db) })[1], 2)
end)

H.test("saved data is repaired in place and bad catch records are dropped", function()
    local ns = H.newNS("Locale", "Data", "Dex", "Shiny")
    local saved = { catches = { [6291] = { count = "x" }, bad = 3 }, settings = { sound = "yes" } }
    local db = ns.Dex.repair(saved)
    H.truthy(db == saved)
    H.eq(saved.catches, { [6291] = { count = 1 } })
    H.eq(saved.settings, { sound = true, announce = true, share = true, locale = "", sounds = {},
        minimap = { hide = false, angle = 200 }, lureButton = true, lure = { id = 0 }, doubleCast = "RightButton" })
end)

H.test("recipe state: unscanned until a profession window was read, then known or unknown", function()
    local ns, db = load()
    H.eq(ns.Dex.recipeState(db, "Me-R", 7751, nil), "unscanned")
    H.eq(ns.Dex.recipeState(db, "Me-R", 7751, true), "known")
    ns.Dex.storeScan(db, "Me-R", { 7751, 12345 })
    H.eq(ns.Dex.recipeState(db, "Me-R", 7751, false), "known")
    H.eq(ns.Dex.recipeState(db, "Me-R", 7752, false), "unknown")
    H.falsy(db.known["Me-R"][12345])
end)

H.test("every entry has a known category, zones from the zone table and recipes from the recipe table", function()
    local ns = H.newNS("Locale", "Data", "Dex", "Shiny")
    local cats, ids = {}, {}
    for _, c in ipairs(ns.Data.CATEGORIES) do cats[c] = true end
    for _, e in ipairs(ns.Data.ENTRIES) do
        H.truthy(cats[e.cat])
        if ids[e.id] then error("duplicate id " .. e.id) end
        ids[e.id] = true
        for _, z in ipairs(e.zones) do if not ns.Data.ZONES[z] then error("zone " .. z) end end
        for _, r in ipairs(e.recipes) do if not ns.Data.RECIPES[r] then error("recipe " .. r) end end
        if e.cat ~= "item" and e.cat ~= "wreck" and #e.zones == 0 then error("no zone for " .. e.id) end
    end
end)

H.test("both locales have the same keys, and one per category", function()
    local ns = H.newNS("Locale", "Data")
    local en, fr = ns.LOCALES.enUS, ns.LOCALES.frFR
    for k in pairs(en) do if fr[k] == nil then error("frFR misses " .. k) end end
    for k in pairs(fr) do if en[k] == nil then error("enUS misses " .. k) end end
    for _, c in ipairs(ns.Data.CATEGORIES) do H.truthy(en["CAT_" .. c]) end
    H.truthy(en.CAT_found)
end)
