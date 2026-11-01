-- The guild ranking: score, wire format, cache, and the guild channel traffic.
local H = ...
local W = dofile("tests/fakewow.lua")

local function pure()
    local ns = H.newNS("Locale", "Data", "Dex", "Shiny", "Board")
    return ns, ns.Dex.repair({})
end

H.test("the score counts every fished catch and the shinies per grade, minus the forced ones", function()
    local ns, db = pure()
    ns.Dex.record(db, 6291, 1, "z")
    ns.Dex.record(db, 6291, 2, "z")
    ns.Dex.record(db, 6356, 3, "z")
    ns.Shiny.record(db, 6291, "rare", 1)
    ns.Shiny.record(db, 6291, "legendary", 1)
    ns.Shiny.record(db, 6291, "legendary", 2)
    ns.Board.noteForced(db, "legendary")
    ns.Shiny.record(db, 6717, "epic", 1) -- a quest item, saved before quest items left the roll
    H.eq(ns.Board.score(db), { total = 3, species = 2, rare = 1, epic = 0, legendary = 1 })
end)

H.test("a score survives the wire; anything FishDex would not send is refused", function()
    local ns = pure()
    local s = { total = 120, rare = 3, epic = 1, legendary = 0, species = 14 }
    local text = ns.Board.encode("S", "0a1b2c3d", s)
    H.truthy(#text < 60)
    H.eq({ ns.Board.decode(text) }, { "S", "0a1b2c3d", s })   -- no name: the sender's is used
    local named = ns.Board.encode("S", "0a1b2c3d", s, "Sto Prime")
    H.eq({ ns.Board.decode(named) }, { "S", "0a1b2c3d", s, "Sto Prime" })
    H.eq({ ns.Board.decode(named .. "^extra") }, { "S", "0a1b2c3d", s, "Sto Prime" }) -- later fields ignored
    H.eq(ns.Board.cleanName("  Sto^|  Prime	 "), "Sto Prime")
    H.eq(#ns.Board.cleanName(string.rep("é", 40)), 46) -- cut on a character boundary
    H.eq(ns.Board.decode("S^2^0a1b2c3d^1^0^0^0^1"), nil)      -- another version
    H.eq(ns.Board.decode("X^1^0a1b2c3d^1^0^0^0^1"), nil)      -- unknown kind
    H.eq(ns.Board.decode("S^1^nothex!!^1^0^0^0^1"), nil)      -- bad id
    H.eq(ns.Board.decode("S^1^0a1b2c3d^1^1^1^0^1"), nil)      -- more shinies than catches
    H.eq(ns.Board.decode("S^1^0a1b2c3d^-4^0^0^0^1"), nil)     -- negative
    H.eq(ns.Board.decode("S^1^0a1b2c3d^99999999^0^0^0^1"), nil) -- above MAX
    H.eq(ns.Board.decode("S^1^0a1b2c3d^5^0^0"), nil)          -- fields missing
end)

H.test("the account id is drawn once and kept", function()
    local ns, db = pure()
    local id = ns.Board.ensureId(db, function() return 0.5 end)
    H.truthy(id:match("^%x%x%x%x%x%x%x%x$"))
    H.eq(ns.Board.ensureId(db, function() return 0.1 end), id)
end)

H.test("rows: this account live, the others from the cache of this guild, sorted by the column", function()
    local ns, db = pure()
    ns.Board.store(db, "G-R", "00000001", "Ana", { total = 50, rare = 0, epic = 2, legendary = 0, species = 9 }, 10)
    ns.Board.store(db, "G-R", "00000002", "Bob", { total = 80, rare = 1, epic = 0, legendary = 0, species = 9 }, 11)
    ns.Board.store(db, "Other-R", "00000003", "Cy", { total = 999, rare = 9, epic = 9, legendary = 9, species = 9 }, 12)
    -- an older line of this very account (another character) is replaced by the live score
    ns.Board.store(db, "G-R", "aaaaaaaa", "Alt", { total = 1, rare = 0, epic = 0, legendary = 0, species = 1 }, 13)
    local me = { id = "aaaaaaaa", name = "Me", score = { total = 60, rare = 0, epic = 0, legendary = 1, species = 3 } }
    local names = {}
    for _, r in ipairs(ns.Board.rows(db, "G-R", me)) do names[#names + 1] = r.name end
    H.eq(names, { "Bob", "Me", "Ana" })
    names = {}
    for _, r in ipairs(ns.Board.rows(db, "G-R", me, "epic")) do names[#names + 1] = r.name end
    H.eq(names, { "Ana", "Bob", "Me" })
end)

-- The whole addon in the fake client, in a guild, with the addon channel recorded.
local function boot()
    local T = W.boot(H, { locale = "frFR" })
    local env = T.env
    T.sent, T.loot = {}, {}
    env.Enum.SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8 }
    T.result = 0
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        IsAddonMessagePrefixRegistered = function() return true end,
        InChatMessagingLockdown = function() return false end,
        SendAddonMessage = function(prefix, text, channel)
            T.sent[#T.sent + 1] = { prefix, text, channel }
            return T.result
        end,
    }
    env.IsInGuild = function() return true end
    env.GetGuildInfo = function() return "La Guilde" end
    env.GetRealmName = function() return "Royaume" end
    env.UnitName = function() return "Moi" end
    env.Ambiguate = function(name) return (name:gsub("%-Royaume$", "")) end
    env.IsFishingLoot = function() return true end
    env.GetNumLootItems = function() return #T.loot end
    env.GetLootSlotLink = function(i) return "|Hitem:" .. T.loot[i] .. "::|h[x]|h" end
    T.fire("ADDON_LOADED", H.ADDON)
    T.ns.Detect.roll = function() return 0.99 end
    return T
end

local function fish(T, id)
    T.loot = { id }
    T.fire("LOOT_OPENED")
    T.fire("LOOT_CLOSED")
end

H.test("login sends one hello on the guild channel; fishing sends the score only after 2 idle minutes", function()
    local T = boot()
    T.fire("PLAYER_LOGIN")
    T.run()
    H.eq(#T.sent, 1)
    H.eq(T.sent[1][1], "FishDex")
    H.eq(T.sent[1][3], "GUILD")
    H.truthy(T.sent[1][2]:match("^H%^1%^%x+%^0%^0%^0%^0%^0%^Moi$"))
    T.clock = T.clock + 60
    fish(T, 6291)
    fish(T, 6291)
    H.eq(#T.sent, 1) -- nothing while fishing
    T.clock = T.clock + 121
    T.run()
    H.eq(#T.sent, 2)
    H.truthy(T.sent[2][2]:match("^S%^1%^%x+%^2%^0%^0%^0%^1%^Moi$"))
    -- the same score is not sent twice
    T.ns.Comm.onCatch()
    T.clock = T.clock + 121
    T.run()
    H.eq(#T.sent, 2)
end)

H.test("a member's score is saved for the guild and shown in the Guild tab; a hello gets one answer", function()
    local T = boot()
    T.fire("CHAT_MSG_ADDON", "FishDex", "H^1^0000beef^40^2^1^0^7", "GUILD", "Pêcheuse-Royaume")
    T.fire("CHAT_MSG_ADDON", "FishDex", "H^1^0000cafe^10^0^0^0^2", "GUILD", "Autre-Royaume")
    local saved = T.env.FishDexDB.board.guilds["La Guilde-Royaume"]
    H.eq(saved["0000beef"].name, "Pêcheuse")
    H.eq(saved["0000beef"].total, 40)
    T.clock = T.clock + 60
    T.run()
    H.eq(#T.sent, 1) -- two hellos, one answer
    H.truthy(T.sent[1][2]:match("^S%^"))
    T.env.SlashCmdList.FISHDEX("")
    local tab
    for _, fr in ipairs(T.frames) do if rawget(fr, "tab") == "board" then tab = fr end end
    H.truthy(tab)
    rawget(tab, "scripts").OnClick(tab)
    local win = T.env.FishDexWindow
    H.truthy(rawget(rawget(win, "ranking"), "right").text:find("3 pêcheurs", 1, true))
    H.falsy(rawget(rawget(win, "list"), "frame").shown)
end)

H.test("ignored: other prefixes, other channels, this account's own echo, a bad line, sharing off", function()
    local T = boot()
    local db = T.env.FishDexDB
    T.fire("CHAT_MSG_ADDON", "SO-6", "S^1^0000beef^40^2^1^0^7", "GUILD", "A-Royaume")
    T.fire("CHAT_MSG_ADDON", "FishDex", "S^1^0000beef^40^2^1^0^7", "WHISPER", "A-Royaume")
    T.fire("CHAT_MSG_ADDON", "FishDex", "S^1^" .. db.board.id .. "^40^2^1^0^7", "GUILD", "Moi-Royaume")
    T.fire("CHAT_MSG_ADDON", "FishDex", "S^1^0000beef^4^2^1^9^7", "GUILD", "A-Royaume")
    H.eq(db.board.guilds, {})
    db.settings.share = false
    T.fire("PLAYER_LOGIN")
    T.run()
    H.eq(#T.sent, 0)
end)

H.test("a throttled message waits and leaves later; two messages are 30 s apart at least", function()
    local T = boot()
    -- The fake ignores delays: run the timers one at a time, moving the clock by hand.
    local function step() table.remove(T.timers, 1)() end
    T.result = 3
    T.ns.Comm.queue("S", true)
    step()
    H.eq(#T.sent, 1)
    H.eq(#T.timers, 1) -- the retry
    T.result = 0
    step() -- too early: waits for the gap
    H.eq(#T.sent, 1)
    T.clock = T.clock + 31
    step()
    H.eq(#T.sent, 2)
    H.eq(#T.timers, 0)
    T.ns.Comm.queue("S", true)
    step()
    H.eq(#T.sent, 2)
    T.clock = T.clock + 31
    step()
    H.eq(#T.sent, 3)
end)

H.test("a forced shinytest shiny does not count in the ranking", function()
    local T = boot()
    T.env.SlashCmdList.FISHDEX("shinytest legendary")
    fish(T, 6291)
    local db = T.env.FishDexDB
    H.eq(T.ns.Shiny.best(db, 6291), "legendary")
    H.eq(T.ns.Board.score(db).legendary, 0)
end)

H.test("without a guild the Guild tab still shows this account's own line", function()
    local T = boot()
    T.env.IsInGuild = function() return false end
    T.env.SlashCmdList.FISHDEX("")
    local tab
    for _, fr in ipairs(T.frames) do if rawget(fr, "tab") == "board" then tab = fr end end
    rawget(tab, "scripts").OnClick(tab)
    local win = T.env.FishDexWindow
    H.truthy(rawget(rawget(win, "ranking"), "right").text:find("1 pêcheurs", 1, true))
    local rows = T.ns.Board.rows(T.env.FishDexDB, nil, T.ns.Comm.me())
    H.eq(#rows, 1)
    H.truthy(rows[1].me)
end)

H.test("the minimap button opens the window and can be hidden", function()
    local W2 = dofile("tests/fakewow.lua")
    local T = W2.boot(H, { locale = "frFR" })
    T.env.Minimap = W2.frame("Frame", "Minimap")
    T.fire("ADDON_LOADED", H.ADDON)
    local b = T.env.FishDexMinimapButton
    H.truthy(b)
    rawget(b, "scripts").OnClick(b, "LeftButton")
    H.truthy(T.env.FishDexWindow:IsShown())
    T.env.SlashCmdList.FISHDEX("minimap")
    H.falsy(b:IsShown())
    H.eq(T.env.FishDexDB.settings.minimap.hide, true)
end)

H.test("Forever names: First Last from UnitName's surname, sent in the message and shown", function()
    local T = boot()
    T.env.UnitName = function() return "Sto", "Prime" end
    H.eq(T.ns.Comm.playerName(), "Sto Prime")
    T.env.GetUnitName = function() return "Sto Prime-Royaume" end
    H.eq(T.ns.Comm.playerName(), "Sto Prime")
    T.env.GetUnitName, T.env.UnitName = nil, function() return "Moi", "Royaume" end
    H.eq(T.ns.Comm.playerName(), "Moi") -- elsewhere the second return is the realm
    T.fire("CHAT_MSG_ADDON", "FishDex", "S^1^0000beef^40^2^1^0^7^Kanye Est", "GUILD", "Kanye-Royaume")
    H.eq(T.env.FishDexDB.board.guilds["La Guilde-Royaume"]["0000beef"].name, "Kanye Est")
end)

H.test("one line per account; its characters are kept for the tooltip, most recent first", function()
    local ns, db = pure()
    local s = { total = 5, rare = 0, epic = 0, legendary = 0, species = 2 }
    ns.Board.store(db, "G-R", "0000beef", "Sto Prime", s, 10)
    ns.Board.store(db, "G-R", "0000beef", "Sto Reroll", s, 20)
    ns.Board.noteChar(db, "Moi Un", 1)
    ns.Board.noteChar(db, "Moi Deux", 2)
    local me = { id = "aaaaaaaa", name = "Moi Deux", score = s }
    local rows = ns.Board.rows(db, "G-R", me)
    H.eq(#rows, 2)
    for _, r in ipairs(rows) do
        if r.me then H.eq(r.alts, { "Moi Deux", "Moi Un" }) else H.eq(r.alts, { "Sto Reroll", "Sto Prime" }) end
        if not r.me then H.eq(r.name, "Sto Reroll") end
    end
end)
