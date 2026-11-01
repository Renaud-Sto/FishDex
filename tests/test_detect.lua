-- Detection in the fake game: only fishing loot fills the dex, first catches are announced.
local H = ...
local W = dofile("tests/fakewow.lua")

local function boot(opts)
    opts = opts or {}
    local T = W.boot(H, { locale = "frFR" })
    local env = T.env
    T.loot, T.fishing, T.notices, T.sounds = {}, false, {}, {}
    env.IsFishingLoot = function() return T.fishing end
    env.GetNumLootItems = function() return #T.loot end
    env.GetLootSlotLink = function(i) local id = T.loot[i] return id and ("|Hitem:" .. id .. "::|h[x]|h") end
    env.GetRealZoneText = function() return "Forêt d'Elwynn" end
    env.RaidWarningFrame = {}
    env.RaidNotice_AddMessage = function(_, text) T.notices[#T.notices + 1] = text end
    env.SOUNDKIT = { UI_EPICLOOT_TOAST = 31578 }
    env.PlaySound = function(id) T.sounds[#T.sounds + 1] = id end
    if opts.noFishingAPI then env.IsFishingLoot = nil end
    T.fire("ADDON_LOADED", H.ADDON)
    return T
end

H.test("a fished item is recorded once per loot window and announced with a sound", function()
    local T = boot()
    T.fishing, T.loot = true, { 6291 }
    T.fire("LOOT_READY", true)
    T.fire("LOOT_OPENED", true)
    T.fire("LOOT_CLOSED")
    local c = T.env.FishDexDB.catches[6291]
    H.eq(c.count, 1)
    H.eq(c.zone, "Forêt d'Elwynn")
    H.eq(#T.notices, 1)
    H.truthy(T.notices[1]:find("Nouvelle prise", 1, true))
    H.eq(T.sounds, { 31578 })
end)

H.test("a second catch of the same fish counts but is not announced again", function()
    local T = boot()
    T.fishing, T.loot = true, { 6291 }
    T.fire("LOOT_OPENED") T.fire("LOOT_CLOSED")
    T.fire("LOOT_OPENED") T.fire("LOOT_CLOSED")
    H.eq(T.env.FishDexDB.catches[6291].count, 2)
    H.eq(#T.notices, 1)
end)

H.test("loot that is not fishing loot never fills the dex", function()
    local T = boot()
    T.fishing, T.loot = false, { 6291 }
    T.fire("LOOT_OPENED") T.fire("LOOT_CLOSED")
    H.eq(T.env.FishDexDB.catches, {})
    H.eq(#T.notices, 0)
end)

H.test("without IsFishingLoot, loot right after the player's fishing channel counts", function()
    local T = boot({ noFishingAPI = true })
    T.loot = { 6303 }
    T.fire("LOOT_OPENED") T.fire("LOOT_CLOSED")
    H.eq(T.env.FishDexDB.catches, {})
    T.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast", 7620)
    T.fire("LOOT_OPENED") T.fire("LOOT_CLOSED")
    H.eq(T.env.FishDexDB.catches[6303].count, 1)
    T.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast", 7620)
    T.clock = T.clock + 10
    T.fire("LOOT_OPENED")
    H.eq(T.env.FishDexDB.catches[6303].count, 1)
end)

H.test("sound and announce follow their options", function()
    local T = boot()
    T.env.SlashCmdList.FISHDEX("son")
    T.env.SlashCmdList.FISHDEX("annonce")
    H.falsy(T.env.FishDexDB.settings.sound)
    H.falsy(T.env.FishDexDB.settings.announce)
    T.fishing, T.loot = true, { 6291 }
    T.fire("LOOT_OPENED")
    H.eq(#T.notices, 0)
    H.eq(#T.sounds, 0)
    H.truthy(T.env.FishDexDB.catches[6291])
end)

H.test("nothing is printed at login; the window opens and shows a slot per entry", function()
    local T = boot()
    H.eq(#T.chat, 0)
    T.env.SlashCmdList.FISHDEX("")
    local win = T.env.FishDexWindow
    H.truthy(win and win:IsShown())
    local shown = 0
    for _, fr in ipairs(T.frames) do
        if fr.kind == "Button" and rawget(fr, "parent") == rawget(win, "grid") and fr.shown then shown = shown + 1 end
    end
    H.eq(shown, math.min(14, #T.ns.Dex.list(T.env.FishDexDB, "fish"))) -- one page
    H.truthy(rawget(win, "pageText").text:find("Page 1/", 1, true))
    T.env.SlashCmdList.FISHDEX("")
    H.falsy(win:IsShown())
end)

H.test("/fishdex fr switches the addon texts on an English client and is kept for the next session", function()
    local T = boot()
    T.env.GetLocale = function() return "enUS" end
    T.env.SlashCmdList.FISHDEX("en")
    H.eq(T.ns.L.CAT_wreck, "Wrecks")
    T.env.SlashCmdList.FISHDEX("fr")
    H.eq(T.ns.L.CAT_wreck, "Épaves")
    H.eq(T.env.FishDexDB.settings.locale, "frFR")
    T.env.SlashCmdList.FISHDEX("auto")
    H.eq(T.ns.L.CAT_wreck, "Wrecks")
    H.eq(T.env.FishDexDB.settings.locale, "")
end)
