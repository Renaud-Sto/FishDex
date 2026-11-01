-- Entry point: saved data, game names (localized by the client, English fallback from the
-- data), recipe scan from the profession window, slash command and compartment.
-- Silent at login: chat only answers a player's action or a new catch.
local ADDON, ns = ...

local Main = {}
ns.Main = Main

local L, Data, Dex = ns.L, ns.Data, ns.Dex

function Main.say(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff" .. L.TITLE .. "|r " .. tostring(text))
end

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    if type(issecretvalue) == "function" and (issecretvalue(a) or issecretvalue(b)) then return nil end
    return a, b
end

function Main.itemName(itemID)
    local name = safe(C_Item and C_Item.GetItemInfo, itemID)
    if type(name) == "string" and name ~= "" then return name end
    safe(C_Item and C_Item.RequestLoadItemDataByID, itemID)
    local e = Dex.entry(itemID)
    return e and e.name or nil
end

function Main.itemIcon(itemID)
    local icon = safe(C_Item and C_Item.GetItemIconByID, itemID)
    if icon then return icon end
    return nil
end

function Main.zoneName(areaID)
    local name = safe(C_Map and C_Map.GetAreaInfo, areaID)
    if type(name) == "string" and name ~= "" then return name end
    return Data.ZONES[areaID] or ("#" .. tostring(areaID))
end

function Main.recipeName(spellID)
    local name = safe(C_Spell and C_Spell.GetSpellName, spellID)
    if type(name) == "string" and name ~= "" then return name end
    local r = Data.RECIPES[spellID]
    return r and r[3] or ("#" .. tostring(spellID))
end

function Main.charKey()
    local name = safe(UnitName, "player") or "?"
    local realm = safe(GetRealmName) or "?"
    return tostring(name) .. "-" .. tostring(realm)
end

function Main.recipeState(spellID)
    return Dex.recipeState(Main.db, Main.charKey(), spellID, safe(IsPlayerSpell, spellID))
end

-- Profession window open: note which of the dex recipes this character has learned.
-- Recipes of another profession answer nil and are left as they were.
function Main.scanRecipes()
    local ui = C_TradeSkillUI
    if type(ui) ~= "table" or type(ui.GetRecipeInfo) ~= "function" then return end
    if safe(ui.IsDataSourceChanging) == true then return end
    local learned, seen = {}, false
    for spellID in pairs(Data.RECIPES) do
        local info = safe(ui.GetRecipeInfo, spellID)
        if type(info) == "table" then
            seen = true
            if info.learned == true then learned[#learned + 1] = spellID end
        end
    end
    if seen then
        Dex.storeScan(Main.db, Main.charKey(), learned)
        Main.refresh()
    end
end

function Main.refresh()
    if ns.Window and ns.Window.refresh then ns.Window.refresh() end
end

function Main.init()
    if type(FishDexDB) ~= "table" then FishDexDB = {} end
    Main.db = Dex.repair(FishDexDB)
    ns.Board.ensureId(Main.db, math.random)
    if Main.db.settings.locale ~= "" then ns.setLocale(Main.db.settings.locale) end
    Main.ready = true
    ns.MinimapButton.apply()
end

function Main.toggleSetting(key, onText, offText)
    local s = Main.db.settings
    s[key] = not s[key]
    Main.say(s[key] and onText or offText)
    Main.refresh()
end

function Main.onEvent(event, arg1, ...)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then Main.init() end
        return
    end
    if not Main.ready then return end
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if arg1 == ADDON then Main.say(event .. ": " .. tostring((...))) end
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE"
        or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
        Main.scanRecipes()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if ns.Window then ns.Window.refreshSoon() end
    elseif event == "CHAT_MSG_ADDON" or event == "PLAYER_LOGIN" then
        ns.Comm.onEvent(event, arg1, ...)
    else
        ns.Detect.onEvent(event, arg1, ...)
    end
end

local function slash(msg)
    if not Main.ready then return end
    local cmd = ((msg or ""):match("^(%S*)") or ""):lower()
    if cmd == "" then
        ns.Window.toggle()
    elseif cmd == "son" or cmd == "sound" then
        Main.toggleSetting("sound", L.SOUND_ON, L.SOUND_OFF)
    elseif cmd == "annonce" or cmd == "announce" then
        Main.toggleSetting("announce", L.ANNOUNCE_ON, L.ANNOUNCE_OFF)
    elseif cmd == "appat" or cmd == "lure" then
        Main.say(ns.LureButton.toggle() and L.LURE_ON or L.LURE_OFF)
        Main.refresh()
    elseif cmd == "clic" or cmd == "click" then
        Main.say(L["DOUBLE_" .. ns.DoubleCast.cycle()])
        Main.refresh()
    elseif cmd == "minimap" then
        local m = Main.db.settings.minimap
        m.hide = not m.hide
        ns.MinimapButton.apply()
        Main.say(m.hide and L.MINIMAP_OFF or L.MINIMAP_ON)
    elseif cmd == "fr" or cmd == "en" or cmd == "auto" then
        -- Addon texts only: item, zone and recipe names stay in the client's language.
        local locale = cmd == "fr" and "frFR" or cmd == "en" and "enUS" or ""
        Main.db.settings.locale = locale
        ns.setLocale(locale ~= "" and locale or GetLocale())
        Main.say(L.LANGUAGE_SET)
        Main.refresh()
    elseif cmd == "shinytest" then
        -- Not in the help: forces the next eligible catch to a grade, to see the announce.
        local key = ((msg or ""):match("^%S+%s+(%S+)") or "rare"):lower()
        if not ns.Shiny.grade(key) then key = "rare" end
        ns.Detect.forceNext = key
        Main.say(string.format(L.SHINY_TEST, L["GRADE_" .. key]))
    else
        Main.say(L.HELP)
    end
end

-- TOC AddonCompartmentFunc: the client calls it with (addonName, mouseButton).
function FishDex_OnCompartmentClick()
    if Main.ready then ns.Window.toggle() end
end

SLASH_FISHDEX1 = "/fishdex"
SLASH_FISHDEX2 = "/peche"
SlashCmdList.FISHDEX = slash

local frame = CreateFrame("Frame")
local events = { "ADDON_LOADED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "TRADE_SKILL_SHOW",
    "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "GET_ITEM_INFO_RECEIVED" }
for _, e in ipairs(ns.Detect.EVENTS) do events[#events + 1] = e end
for _, e in ipairs(ns.Comm.EVENTS) do events[#events + 1] = e end
for _, event in ipairs(events) do
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, ...) Main.onEvent(event, ...) end)
