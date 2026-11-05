-- Template from the wow-addon-dev skill (adapted from CraftProfitProbe, MIT): a THROWAWAY
-- addon that asks the real client questions before the addon code depends on the answer.
-- Never shipped, excluded from luacheck (probe/**). Rename MyAddon / FISHDEXPROBE / /map.
-- * Every line it prints, the chat lines of the addon under test and every Lua error are
--   mirrored into the FishDexProbeLog saved variable. /reload (or logout) writes it to
--   WTF/Account/<ACCOUNT>/SavedVariables/MyAddonProbe.lua, which Claude can read itself.
-- * Every call goes through try(): a missing API prints MISSING, an error prints ERR, a
--   secret value prints <SECRET>; the probe itself never raises.
-- * It hooks DEFAULT_CHAT_FRAME:AddMessage and the error handler: acceptable in a probe,
--   never in a shipped addon (references/taint-and-restrictions.md).
local VERSION = "0.1.0"
local TAG = "|cff66ccff[PROBE " .. VERSION .. "]|r "
local WATCHED = "FishDex" -- chat lines containing this are mirrored into the log

local function isSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, res = pcall(issecretvalue, v)
    return ok and res == true
end

local function show(v)
    if v == nil then return "nil" end
    if isSecret(v) then return "<SECRET>" end
    return tostring(v)
end

-- Persistent log, repeated lines folded as "(xN)", capped at MAX_LOG lines.
local MAX_LOG = 3000
local lastText, lastRepeat, lastStamp
local function logLine(text)
    if type(FishDexProbeLog) ~= "table" then FishDexProbeLog = {} end
    local log = FishDexProbeLog
    if text == lastText then
        lastRepeat = lastRepeat + 1
        log[#log] = lastStamp .. " " .. text .. " (x" .. lastRepeat .. ")"
        return
    end
    lastText, lastRepeat, lastStamp = text, 1, date("%H:%M:%S")
    log[#log + 1] = lastStamp .. " " .. text
    if #log > MAX_LOG then table.remove(log, 1) end
end

local function plain(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function out(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = show((select(i, ...))) end
    DEFAULT_CHAT_FRAME:AddMessage(TAG .. table.concat(parts, " "))
end

hooksecurefunc(DEFAULT_CHAT_FRAME, "AddMessage", function(_, text)
    if type(text) ~= "string" or isSecret(text) then return end
    if text:find(WATCHED, 1, true) or text:find("[PROBE", 1, true) then logLine(plain(text)) end
end)

local previousHandler = geterrorhandler()
seterrorhandler(function(err)
    logLine("LUA ERROR: " .. show(err))
    return previousHandler(err)
end)

-- Calls fn without ever raising; returns a printable summary of every value returned.
-- Careful: a returned table prints as its address; read table fields with a direct pcall.
local function pack(...) return { n = select("#", ...), ... } end

local function try(fn, ...)
    if type(fn) ~= "function" then return "MISSING" end
    local r = pack(pcall(fn, ...)) -- one call only: the probed API may have side effects
    if not r[1] then return "ERR: " .. tostring(r[2]) end
    local parts = {}
    for i = 2, r.n do parts[#parts + 1] = show(r[i]) end
    return #parts == 0 and "(no return)" or table.concat(parts, ",")
end

-- "C_Item.GetItemInfo" -> the value at that path, or nil.
local function resolve(path)
    local v = _G
    for key in path:gmatch("[^%.]+") do
        if type(v) ~= "table" then return nil end
        v = v[key]
    end
    return v
end

local cmds = {}

-- /fdp api <path> [path...]: the type of each global (does this API exist on this build?).
cmds.api = function(arg)
    for path in arg:gmatch("%S+") do out(path, "->", type(resolve(path))) end
end

-- /fdp client: which client and build this is.
cmds.client = function()
    out("GetBuildInfo:", try(GetBuildInfo))
    out("WOW_PROJECT_ID:", show(WOW_PROJECT_ID), "WOW_PROJECT_CAMELOT:", show(WOW_PROJECT_CAMELOT))
    out("GetLocale:", try(GetLocale))
end

-- /fdp atlas <name> [name...]: does the atlas exist, and its size (an unknown atlas draws
-- nothing; a missing file path draws a green square).
cmds.atlas = function(arg)
    for name in arg:gmatch("%S+") do
        local ok, info = pcall(C_Texture.GetAtlasInfo, name)
        if ok and type(info) == "table" then
            out("atlas", name, show(info.width) .. "x" .. show(info.height), "file", show(info.file))
        else
            out("atlas", name, "MISSING")
        end
    end
end

-- /fdp file <path>: does the client serve this file to addons (a file id) or not (nil).
cmds.file = function(arg)
    out("file", arg, try(GetFileIDFromPath, arg))
end

-- /fdp template <FrameType> <Template>: create it the way the addon will (nil parent, then
-- SetParent). pcall says only that CreateFrame returned: an OnLoad error goes to the error
-- handler instead, so read the LUA ERROR lines of the log too.
cmds.template = function(arg)
    local kind, template = arg:match("^(%S+)%s+(%S+)$")
    if not kind then out("usage: /fdp template Button UIPanelButtonTemplate") return end
    local ok, f = pcall(CreateFrame, kind, nil, nil, template)
    out("template", template, "as", kind, ok and "created" or ("FAILS: " .. tostring(f)))
    if ok and f then f:SetParent(UIParent) f:Hide() end
end

-- Event watcher: names in EVENTS are logged with their first argument (log only, the chat
-- stays readable). An event the client does not know is noted once.
local EVENTS = { "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }
local watching = false
local frame = CreateFrame("Frame")
for _, e in ipairs(EVENTS) do
    if not pcall(frame.RegisterEvent, frame, e) then logLine("event rejected by client: " .. e) end
end
frame:SetScript("OnEvent", function(_, event, a1, a2)
    if watching or event:find("^ADDON_ACTION") then
        logLine(string.format("EVENT %.3f %s %s %s", GetTime(), event, show(a1), show(a2)))
    end
end)

-- /fdp watch on|off: trace mode, every watched event stamped with GetTime().
cmds.watch = function(arg)
    watching = arg == "on"
    logLine("WATCH " .. (watching and "ON" or "OFF") .. string.format(" at %.3f", GetTime()))
    out("watch:", watching and "on (log only; /reload writes it)" or "off")
end


-- Fishing loot: every loot window is logged automatically (no command needed), with the
-- fishing flag, the zone and each slot's item id, name, quality, class and subclass.
local function zoneLine()
    local mapID = try(C_Map and C_Map.GetBestMapForUnit, "player")
    return "zone=" .. try(GetZoneText) .. " sub=" .. try(GetSubZoneText)
        .. " real=" .. try(GetRealZoneText) .. " mapID=" .. mapID
end

local function itemLine(link)
    if type(link) ~= "string" then return "link=nil" end
    local id = tonumber(link:match("item:(%d+)"))
    local name, _, quality, _, _, itype, isub, _, _, _, _, classID, subclassID =
        (C_Item and C_Item.GetItemInfo or GetItemInfo)(link)
    return string.format("id=%s name=%s q=%s type=%s/%s class=%s/%s", show(id), show(name),
        show(quality), show(itype), show(isub), show(classID), show(subclassID))
end

local lootFrame = CreateFrame("Frame")
for _, e in ipairs({ "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED", "CHAT_MSG_LOOT",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
    if not pcall(lootFrame.RegisterEvent, lootFrame, e) then logLine("event rejected by client: " .. e) end
end
lootFrame:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "LOOT_OPENED" or event == "LOOT_READY" then
        logLine(string.format("%s %.3f autoloot=%s IsFishingLoot=%s n=%s %s", event, GetTime(),
            show(a1), try(IsFishingLoot), try(GetNumLootItems), zoneLine()))
        if event == "LOOT_OPENED" then
            local n = GetNumLootItems and GetNumLootItems() or 0
            for i = 1, n do
                local okL, link = pcall(GetLootSlotLink, i)
                local okT, stype = pcall(GetLootSlotType, i)
                logLine("  slot " .. i .. " type=" .. show(okT and stype) .. " " .. itemLine(okL and link or nil))
            end
        end
    elseif event == "CHAT_MSG_LOOT" then
        if type(a1) == "string" and not isSecret(a1) then
            logLine("CHAT_MSG_LOOT " .. plain(a1) .. " " .. itemLine(a1:match("|H(item:[^|]+)|h")))
        else
            logLine("CHAT_MSG_LOOT " .. show(a1))
        end
    elseif event:find("CHANNEL") then
        if a1 == "player" then
            logLine(string.format("%s %.3f spellID=%s", event, GetTime(), show(a3)))
        end
    else
        logLine(string.format("%s %.3f", event, GetTime()))
    end
end)

-- /fdp item <id> [id...]: name, icon, class of an item id (checks a fish table entry).
cmds.item = function(arg)
    for id in arg:gmatch("%d+") do
        out("item", id, itemLine("item:" .. id), "icon", try(C_Item and C_Item.GetItemIconByID, tonumber(id)))
    end
end

-- /fdp area <id...>: localized zone name from a Wowhead/AreaTable zone id.
cmds.area = function(arg)
    for id in arg:gmatch("%d+") do
        out("area", id, try(C_Map and C_Map.GetAreaInfo, tonumber(id)))
    end
end

-- /fdp spell <id...>: localized spell (recipe) name, and whether the player knows it.
cmds.spell = function(arg)
    for id in arg:gmatch("%d+") do
        local n = tonumber(id)
        out("spell", id, try(C_Spell and C_Spell.GetSpellName, n), "known", try(IsPlayerSpell, n),
            "IsSpellKnown", try(IsSpellKnown, n))
    end
end

-- Sound audition: /fdp sounds [word] lists the SOUNDKIT keys that sound like a reward
-- (or contain `word`); /fdp sound plays the next one, /fdp sound <n> plays number n.
local soundList, soundIndex = {}, 0
local SOUND_WORDS = { "TOAST", "FANFARE", "ACHIEVEMENT", "REWARD", "LOOT", "LEVEL", "COMPLETE",
    "CHEER", "LEGENDARY", "EPIC", "TREASURE", "UNLOCK", "COLLECTION", "SPARKLE", "CHIME" }
cmds.sounds = function(arg)
    soundList, soundIndex = {}, 0
    if type(SOUNDKIT) ~= "table" then out("SOUNDKIT missing") return end
    local words = arg ~= "" and { arg:upper() } or SOUND_WORDS
    for key, id in pairs(SOUNDKIT) do
        if type(key) == "string" and type(id) == "number" then
            for _, w in ipairs(words) do
                if key:find(w, 1, true) then soundList[#soundList + 1] = key break end
            end
        end
    end
    table.sort(soundList)
    for i, key in ipairs(soundList) do logLine(string.format("sound %d %s %d", i, key, SOUNDKIT[key])) end
    out(#soundList, "sounds found. /fdp sound to hear the next one, /fdp sound <n> for number n")
end
cmds.sound = function(arg)
    if #soundList == 0 then cmds.sounds("") end
    local n = tonumber(arg) or (soundIndex % #soundList) + 1
    local key = soundList[n]
    if not key then out("no sound", n) return end
    soundIndex = n
    PlaySound(SOUNDKIT[key], "Master")
    out(string.format("[%d/%d] %s", n, #soundList, key))
end

-- /fdp all: every question at once (zones, recipes, items, APIs).
cmds.all = function()
    cmds.client("")
    cmds.api("IsFishingLoot C_Map.GetAreaInfo C_Spell.GetSpellName IsPlayerSpell C_TradeSkillUI.GetAllRecipeIDs"
        .. " C_TradeSkillUI.GetRecipeInfo Item.CreateFromItemID C_Item.GetItemInfo C_Item.GetItemIconByID"
        .. " RaidNotice_AddMessage RaidWarningFrame C_AlertFrames TopBannerManager_Show PlaySound")
    cmds.area("12 33 1377 618 1637")
    cmds.spell("7751 18245 25704 7836 20916")
    cmds.item("6291 13888 21071 6359 21113 6356 6309 7973 6717")
    cmds.atlas("collections-background-tile Garr_FollowerToast-Rare UI-Achievement-Alert-Background"
        .. " ui-journeys-tooltip-icon-unlocked loottoast-bg-questrewardupgrade")
    out("SOUNDKIT", show(SOUNDKIT and SOUNDKIT.UI_FISHING_CATCH), show(SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST),
        show(SOUNDKIT and SOUNDKIT.ACHIEVEMENT_MENU_OPEN), show(SOUNDKIT and SOUNDKIT.UI_70_ARTIFACT_FORGE_TRAIT_GOLDTRAIT))
end

-- /fdp dex: checks FishDex's whole static table against this client (2026-11-05, Forever
-- launch). Items load asynchronously, so each answer is logged when it arrives; a missing
-- id is logged as MISSING. Ids copied from FishDex/Data.lua, Lures.lua and Sounds.lua.
local DEX_ITEMS = "6291 6303 6289 6317 6361 21071 6308 6522 6358 21153 6359 8365 6362 4603 13754"
    .. " 13758 13759 13756 13755 13760 13889 13893 13888 13757 13422 13890 6299 6717 1467 19975"
    .. " 16970 6292 6294 6295 6309 6310 6311 6363 6364 13901 13902 13903 13904 13905 13885 13886"
    .. " 13882 13883 13884 13887 13876 13907 13908 6356 6351 6352 6353 6354 6355 6357 6307 13874"
    .. " 13875 13918 20708 21113 21150 7973 8366 13881 13891 20709 21114 21151 3820 7070 7079 6297"
    .. " 6304 6529 6530 6811 6532 7307 6533 34861 46006 62673 68049 6256 6365 6366 12225 19970"
local DEX_ZONES = "1 8 10 11 12 14 15 16 17 28 33 36 38 40 41 44 45 47 85 130 139 141 148 215 267"
    .. " 331 357 361 400 405 406 440 490 493 618 1377 1497 1519 1637 1638 1657"
local DEX_SPELLS = "7751 7752 7753 7754 7755 7827 7828 7836 7837 8238 8240 17551 18238 18239 18240"
    .. " 18241 18242 18243 18244 18245 18246 18247 20916 25704 25954 131474 131476 18248 7732 7731 7620"

local function itemAnswer(id)
    local exists = try(C_Item and C_Item.DoesItemExistByID, id)
    if exists ~= "true" then logLine("dex item " .. id .. " MISSING (" .. exists .. ")") return end
    if type(Item) ~= "table" or type(Item.CreateFromItemID) ~= "function" then
        logLine("dex item " .. id .. " " .. itemLine("item:" .. id)) return
    end
    local ok, item = pcall(Item.CreateFromItemID, Item, id)
    if not ok or type(item) ~= "table" then logLine("dex item " .. id .. " ERR " .. show(item)) return end
    item:ContinueOnItemLoad(function() logLine("dex item " .. id .. " " .. itemLine("item:" .. id)) end)
end

cmds.dex = function()
    local n = 0
    for id in DEX_ITEMS:gmatch("%d+") do n = n + 1 itemAnswer(tonumber(id)) end
    for id in DEX_ZONES:gmatch("%d+") do logLine("dex area " .. id .. " " .. try(C_Map and C_Map.GetAreaInfo, tonumber(id))) end
    for id in DEX_SPELLS:gmatch("%d+") do
        local s = tonumber(id)
        logLine("dex spell " .. id .. " " .. try(C_Spell and C_Spell.GetSpellName, s)
            .. " known=" .. try(IsPlayerSpell, s))
    end
    out(n, "items asked; wait 5 s then /reload, the answers are in the log")
end

-- /fdp sndcheck: plays the 4 default sound files of Sounds.lua, 3 s apart, between two
-- controls (file id 1 = surely missing, SOUNDKIT.READY_CHECK = surely present), and logs
-- what PlaySoundFile returns and whether C_Sound.IsPlaying still sees it 0.3 s later. If
-- the missing control looks like the present one, this check proves nothing.
local SND = { { "control-missing", 1 }, { "new", 1067169 }, { "rare", 569143 },
    { "epic", 1489461 }, { "legendary", 775180 }, { "control-soundkit", "READY_CHECK" } }
cmds.sndcheck = function()
    for i, s in ipairs(SND) do
        C_Timer.After((i - 1) * 3, function()
            local ok, willPlay, handle
            if type(s[2]) == "number" then
                ok, willPlay, handle = pcall(PlaySoundFile, s[2], "Master")
            else
                ok, willPlay, handle = pcall(PlaySound, SOUNDKIT and SOUNDKIT[s[2]], "Master")
            end
            out("snd", s[1], show(s[2]), "ok", show(ok), "willPlay", show(willPlay), "handle", show(handle))
            C_Timer.After(0.3, function()
                logLine("snd " .. s[1] .. " playing@0.3s=" .. try(C_Sound and C_Sound.IsPlaying, handle))
            end)
        end)
    end
end

-- /fdp cvars: the game settings FishDex's fishing options change, as this client has them
-- (nil: the client lacks it, FishDex then leaves it alone).
cmds.cvars = function()
    local get = C_CVar and C_CVar.GetCVar or GetCVar
    for _, name in ipairs({ "UnitNameNPC", "UnitNameFriendlySpecialNPCName", "UnitNameInteractiveNPC",
        "UnitNameNonCombatCreatureName", "UnitNameHostleNPC", "nameplateShowFriendlyNPCs", "Sound_SFXVolume",
        "Sound_MusicVolume", "Sound_AmbienceVolume", "autoLootDefault" }) do
        out("cvar", name, try(get, name))
    end
end

SLASH_FISHDEXPROBE1 = "/fdp"
SlashCmdList.FISHDEXPROBE = function(msg)
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
    if cmd == "log" then
        out("logged lines:", FishDexProbeLog and #FishDexProbeLog or 0, "- /reload writes them to disk")
    elseif cmd == "clear" then
        FishDexProbeLog = {}
        out("log cleared")
    elseif cmds[cmd] then
        out("== " .. cmd .. " " .. arg)
        cmds[cmd](arg)
    else
        out("commands: client | api <path...> | atlas <name...> | file <path>"
            .. " | template <Type> <Template> | item <id...> | area <id...> | spell <id...> | all | dex | sndcheck | cvars | sounds [word] | sound [n] | watch on|off | log | clear")
    end
end
out("loaded. /fdp for commands. Lua errors on screen: /console scriptErrors 1")
