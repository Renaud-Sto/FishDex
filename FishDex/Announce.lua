-- On-screen announce of a first catch: the game's raid warning area (centre of the screen,
-- like a boss emote), a chat line, and a sound when the option is on.
local _, ns = ...

local Announce = {}
ns.Announce = Announce

local L = ns.L

-- First SOUNDKIT entry this client has wins.
local SOUNDS = { "UI_EPICLOOT_TOAST", "UI_IG_STORE_PURCHASE_DELIVERED_TOAST_01", "RAID_WARNING" }

function Announce.itemText(itemID)
    local name = ns.Main.itemName(itemID) or L.UNKNOWN_NAME
    local icon = ns.Main.itemIcon(itemID)
    if icon then return "|T" .. tostring(icon) .. ":20:20|t " .. name end
    return name
end

function Announce.sound()
    if type(PlaySound) ~= "function" or type(SOUNDKIT) ~= "table" then return end
    for _, key in ipairs(SOUNDS) do
        local id = SOUNDKIT[key]
        if type(id) == "number" then
            pcall(PlaySound, id, "Master")
            return
        end
    end
end

function Announce.newCatch(itemID)
    local settings = ns.Main.db.settings
    local text = string.format(L.NEW_CATCH, Announce.itemText(itemID))
    if settings.announce then
        local shown = false
        if type(RaidNotice_AddMessage) == "function" and type(RaidWarningFrame) == "table" then
            local color = type(ChatTypeInfo) == "table" and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.82, b = 0 }
            shown = pcall(RaidNotice_AddMessage, RaidWarningFrame, text, color)
        end
        if not shown and type(UIErrorsFrame) == "table" then
            pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, text, 1, 0.82, 0)
        end
    end
    ns.Main.say(text)
    if settings.sound then Announce.sound() end
end
