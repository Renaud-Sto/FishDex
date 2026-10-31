-- Sound choice: the pure helpers, then the sound window in the fake game.
local H = ...
local W = dofile("tests/fakewow.lua")

local KIT = { UI_EPICLOOT_TOAST = 1, UI_LEGENDARY_LOOT_TOAST = 2, READY_CHECK = 3,
    UI_GARRISON_TOAST_MISSION_COMPLETE = 4, MAP_PING = 5, LEVELUPSOUND = 6, BAD = "x" }

H.test("an empty search lists reward-like sounds, a word lists every key containing it", function()
    local ns = H.newNS("Locale", "Data", "Dex", "Shiny", "Sounds")
    H.eq(ns.Sounds.filter(KIT, ""), { "LEVELUPSOUND", "UI_EPICLOOT_TOAST",
        "UI_GARRISON_TOAST_MISSION_COMPLETE", "UI_LEGENDARY_LOOT_TOAST" })
    H.eq(ns.Sounds.filter(KIT, " ping "), { "MAP_PING" })
    H.eq(ns.Sounds.filter(KIT, "bad"), {})
    H.eq(ns.Sounds.filter(nil, ""), {})
end)

H.test("the chosen sound wins when the client has it, else the first default it has", function()
    local ns = H.newNS("Locale", "Data", "Dex", "Shiny", "Sounds")
    local db = ns.Dex.repair({})
    H.eq(ns.Sounds.keyFor(db, "rare", KIT), "READY_CHECK")
    db.settings.sounds.rare = "MAP_PING"
    H.eq(ns.Sounds.keyFor(db, "rare", KIT), "MAP_PING")
    db.settings.sounds.rare = "GONE_FROM_THIS_CLIENT"
    H.eq(ns.Sounds.keyFor(db, "rare", KIT), "READY_CHECK")
    H.eq(ns.Sounds.keyFor(db, "legendary", {}), nil)
    H.eq(ns.Sounds.label("UI_LEGENDARY_LOOT_TOAST"), "Legendary loot toast")
end)

local function boot()
    local T = W.boot(H, { locale = "frFR" })
    T.sounds = {}
    T.env.SOUNDKIT = KIT
    T.env.PlaySound = function(id) T.sounds[#T.sounds + 1] = id end
    T.fire("ADDON_LOADED", H.ADDON)
    return T
end

local function find(T, test)
    for _, fr in ipairs(T.frames) do if test(fr) then return fr end end
end

H.test("the sound window plays a clicked sound and keeps it for the chosen announce", function()
    local T = boot()
    T.env.SlashCmdList.FISHDEX("")
    local open = find(T, function(fr) return fr.text == T.ns.L.SOUNDS_BUTTON end)
    H.truthy(open)
    rawget(open, "scripts").OnClick(open)
    local win = T.env.FishDexSoundsWindow
    H.truthy(win and win:IsShown())
    -- Choose the legendary announce, click the first listed sound, use it.
    local legendary = find(T, function(fr) return rawget(fr, "target") == "legendary" end)
    rawget(legendary, "scripts").OnClick(legendary)
    local row = find(T, function(fr) return rawget(fr, "key") == "LEVELUPSOUND" end)
    rawget(row, "scripts").OnClick(row)
    H.eq(T.sounds, { 6 })
    local use = find(T, function(fr) return fr.text == T.ns.L.SOUND_USE end)
    rawget(use, "scripts").OnClick(use)
    H.eq(T.env.FishDexDB.settings.sounds, { legendary = "LEVELUPSOUND" })
    -- A legendary catch now plays it.
    T.ns.Announce.shiny(6291, "legendary", true)
    H.eq(T.sounds, { 6, 6 })
end)
