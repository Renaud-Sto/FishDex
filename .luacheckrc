-- Template from the wow-addon-dev skill (adapted from CraftProfit, MIT). Zero warnings is
-- the rule: every WoW global the addon reads is declared below, so a typo in a global
-- (or a global that does not exist) is caught offline. 
max_line_length = false
exclude_files = { "probe/**" }

-- The addon runs in WoW's sandbox: no io, package/require, dofile/loadfile, and os is
-- limited to time/date/clock.
stds.wowlua = {
    read_globals = {
        "assert", "collectgarbage", "error", "getmetatable", "ipairs", "next", "pairs", "pcall",
        "print", "rawequal", "rawget", "rawset", "select", "setmetatable", "tonumber", "tostring",
        "type", "unpack", "xpcall", "date",
        -- Explicit field lists: a bare library name would allow any field and hide typos
        -- such as math.flor or table.unpack (nil calls in WoW's Lua 5.1).
        math = { fields = {
            "abs", "acos", "asin", "atan", "atan2", "ceil", "cos", "cosh", "deg", "exp", "floor",
            "fmod", "frexp", "huge", "ldexp", "log", "log10", "max", "min", "modf", "pi", "pow",
            "rad", "random", "randomseed", "sin", "sinh", "sqrt", "tan", "tanh",
        } },
        string = { fields = {
            "byte", "char", "find", "format", "gmatch", "gsub", "len", "lower", "match", "rep",
            "reverse", "sub", "upper",
        } },
        table = { fields = { "concat", "insert", "maxn", "remove", "sort", "getn", "foreach", "foreachi" } },
        os = { fields = { "time", "date", "clock" } },
    },
}

-- Tests run on LuaJIT and use io, os, loadfile, dofile and setfenv.
std = "lua51"
files["FishDex"] = { std = "wowlua" }

-- Globals the addon itself writes.
globals = {
    "FishDexDB",
    "SLASH_FISHDEX1",
    "SLASH_FISHDEX2",
    "FishDex_OnCompartmentClick",
}

-- WoW API the addon reads: add each one when the code starts using it.
read_globals = {
    "CreateFrame", "GetLocale", "GetTime", "time", "issecretvalue", "C_Timer", "C_Item",
    "C_Map", "C_Spell", "C_TradeSkillUI", "UIParent", "DEFAULT_CHAT_FRAME", "UISpecialFrames",
    "GameTooltip", "PlaySound", "SOUNDKIT", "NORMAL_FONT_COLOR", "HIGHLIGHT_FONT_COLOR",
    "DISABLED_FONT_COLOR", "GetFileIDFromPath", "IsFishingLoot", "GetNumLootItems", "GetLootSlotLink",
    "GetRealZoneText", "GetZoneText", "UnitName", "GetRealmName", "IsPlayerSpell", "PlaySoundFile", "LibStub",
    "RaidNotice_AddMessage", "RaidWarningFrame", "ChatTypeInfo", "UIErrorsFrame",
    "ButtonFrameTemplate_HideAttic", "ButtonFrameTemplate_HidePortrait",
    "ButtonFrameTemplate_HideButtonBar", "SOUNDKIT",
    -- SlashCmdList is read-only as a whole; the addon may assign only its own handler.
    SlashCmdList = { other_fields = true, fields = { FISHDEX = { read_only = false } } },
}
