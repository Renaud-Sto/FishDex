-- On-screen announce of a first catch: the game's raid warning area (centre of the screen,
-- like a boss emote), a chat line, and a sound when the option is on.
local _, ns = ...

local Announce = {}
ns.Announce = Announce

local L = ns.L


function Announce.itemText(itemID)
    local name = ns.Main.itemName(itemID) or L.UNKNOWN_NAME
    local icon = ns.Main.itemIcon(itemID)
    if icon then return "|T" .. tostring(icon) .. ":20:20|t " .. name end
    return name
end

-- Centre of the screen (raid warning area), else the error line; chat always.
local function show(text, color)
    if ns.Main.db.settings.announce then
        local shown = false
        if type(RaidNotice_AddMessage) == "function" and type(RaidWarningFrame) == "table" then
            shown = pcall(RaidNotice_AddMessage, RaidWarningFrame, text, color)
        end
        if not shown and type(UIErrorsFrame) == "table" then
            pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, text, color.r, color.g, color.b)
        end
    end
    ns.Main.say(text)
end

function Announce.newCatch(itemID)
    local color = type(ChatTypeInfo) == "table" and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.82, b = 0 }
    show(string.format(L.NEW_CATCH, Announce.itemText(itemID)), color)
    if ns.Main.db.settings.sound then ns.Sounds.playFor("new") end
end

-- A shiny catch, in its grade's colour; "a first!" when this item reaches this grade
-- for the first time. Each grade has its own sound (Sounds.lua, chosen by the player).
function Announce.shiny(itemID, key, first)
    local g = ns.Shiny.grade(key)
    local rgb = g and g.color or { 1, 1, 1 }
    local text = string.format(L.SHINY_CATCH, L["GRADE_" .. key] or key, Announce.itemText(itemID))
    if first then text = text .. " " .. L.SHINY_FIRST end
    show(text, { r = rgb[1], g = rgb[2], b = rgb[3] })
    if ns.Main.db.settings.sound then ns.Sounds.playFor(key) end
end
