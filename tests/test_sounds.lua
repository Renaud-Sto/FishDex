-- Sound choice: the pure helpers, then the sound window in the fake game.
local H = ...
local W = dofile("tests/fakewow.lua")

local KIT = { UI_EPICLOOT_TOAST = 1, UI_LEGENDARY_LOOT_TOAST = 2, READY_CHECK = 3,
    UI_GARRISON_TOAST_MISSION_COMPLETE = 4, MAP_PING = 5, LEVELUPSOUND = 6, BAD = "x" }

local function load()
    return H.newNS("Locale", "Data", "Dex", "Shiny", "SoundList", "Sounds")
end

H.test("all sounds: every SOUNDKIT key, or those containing the searched word", function()
    local ns = load()
    H.eq(#ns.Sounds.filter(KIT, ""), 6)
    H.eq(ns.Sounds.filter(KIT, " ping "), { "MAP_PING" })
    H.eq(ns.Sounds.filter(KIT, "bad"), {})
    H.eq(ns.Sounds.filter(nil, ""), {})
end)

H.test("the chosen sound wins when the client has it, else the first default it has", function()
    local ns = load()
    local db = ns.Dex.repair({})
    H.eq(ns.Sounds.keyFor(db, "rare", KIT), "file:569143")
    db.settings.sounds.rare = "MAP_PING"
    H.eq(ns.Sounds.keyFor(db, "rare", KIT), "MAP_PING")
    db.settings.sounds.rare = "GONE_FROM_THIS_CLIENT"
    H.eq(ns.Sounds.keyFor(db, "rare", KIT), "file:569143")
    H.eq(ns.Sounds.label("UI_LEGENDARY_LOOT_TOAST"), "Legendary loot toast")
end)

H.test("the selection lists named game sound files and a chosen file plays with PlaySoundFile", function()
    local ns = load()
    local all = ns.Sounds.selection("")
    H.eq(#all, #ns.SoundList)
    H.eq(all[1], "file:" .. ns.SoundList[1][1])
    ns.setLocale("frFR")
    H.eq(ns.Sounds.label("file:566564"), "Cloche : Cloche (Alliance)")
    H.eq(ns.Sounds.selection("cloche")[1], "file:566564")
    ns.setLocale("enUS")
    H.eq(ns.Sounds.label("file:566564"), "Bell: Bell toll (Alliance)")
    local db = ns.Dex.repair({})
    db.settings.sounds.epic = "file:566564"
    H.eq(ns.Sounds.keyFor(db, "epic", KIT), "file:566564")
    db.settings.sounds.epic = "file:1" -- not in the selection: back to the default
    H.eq(ns.Sounds.keyFor(db, "epic", KIT), "file:1489461")
end)

H.test("a sound this client cannot play falls through to the next default", function()
    local T = W.boot(H, { locale = "frFR" })
    T.fire("ADDON_LOADED", H.ADDON)
    local played = {}
    T.env.SOUNDKIT = KIT
    -- Files from 700000 up are missing: PlaySoundFile answers false for them.
    T.env.PlaySoundFile = function(id) played[#played + 1] = id return id < 700000 end
    T.env.PlaySound = function(id) played[#played + 1] = "kit" .. id return true end
    H.eq(T.ns.Sounds.playFor("epic"), "file:569143")
    H.eq(played, { 1489461, 569143 })
    T.env.FishDexDB.settings.sounds.legendary = "file:1514318" -- recent too
    played = {}
    H.eq(T.ns.Sounds.playFor("legendary"), "file:567408")
    H.eq(played, { 1514318, 775180, 567408 })
end)

H.test("sounds shared by other addons (LibSharedMedia) are listed, played from their path, never required", function()
    local ns = load()
    H.eq(ns.Sounds.shared(""), {}) -- no LibStub in plain Lua: nothing, no error
    local played = {}
    local media = { ["DBM: Air Horn"] = "Interface/AddOns/DBM-Core/sounds/AirHorn.ogg", None = "" }
    local lib = {
        List = function() return { "None", "DBM: Air Horn" } end,
        Fetch = function(_, _, name) return media[name] end,
    }
    _G.LibStub = function(name) if name == "LibSharedMedia-3.0" then return lib end end
    _G.PlaySoundFile = function(path) played[#played + 1] = path return true end
    local ok, err = pcall(function()
        H.eq(ns.Sounds.shared(""), { "lsm:DBM: Air Horn" })
        H.eq(ns.Sounds.shared("horn"), { "lsm:DBM: Air Horn" })
        H.eq(ns.Sounds.label("lsm:DBM: Air Horn"), "DBM: Air Horn")
        H.truthy(ns.Sounds.play("lsm:DBM: Air Horn"))
        H.eq(played, { media["DBM: Air Horn"] })
        H.falsy(ns.Sounds.play("lsm:Gone")) -- addon removed: not valid, the default takes over
    end)
    _G.LibStub, _G.PlaySoundFile = nil, nil
    if not ok then error(err, 0) end
end)

local function boot()
    local T = W.boot(H, { locale = "frFR" })
    T.sounds = {}
    T.env.SOUNDKIT = KIT
    T.env.PlaySound = function(id) T.sounds[#T.sounds + 1] = id return true end
    T.env.PlaySoundFile = function(id) T.sounds[#T.sounds + 1] = "file" .. id end
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
    -- Choose the legendary announce, switch to all sounds, click one, use it.
    local legendary = find(T, function(fr) return rawget(fr, "target") == "legendary" end)
    rawget(legendary, "scripts").OnClick(legendary)
    local first = find(T, function(fr) return rawget(fr, "key") == "file:" .. T.ns.SoundList[1][1] end)
    H.truthy(first) -- the selection is shown first
    local all = find(T, function(fr) return rawget(fr, "mode") == "all" end)
    rawget(all, "scripts").OnClick(all)
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
