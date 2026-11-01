-- Game adapter of the guild ranking: sends this account's score on the guild addon channel
-- and saves the scores of the members who have FishDex. Kept nearly silent on purpose: the
-- server throttles addon messages per player, every addon together (SO-6 measured on
-- Forever that two messages in a row get refused), so FishDex sends one line of under 60
-- bytes at login, one when the player has stopped fishing for Board.IDLE seconds, and one
-- to answer a member who just logged in; never two within Comm.GAP seconds.
local _, ns = ...

local Comm = {}
ns.Comm = Comm

local Board = ns.Board

Comm.LOGIN_DELAY = 15   -- the guild channel is not always joined at PLAYER_LOGIN
Comm.GAP = 30           -- seconds between two messages of this player
Comm.RETRY = 5          -- after a throttle refusal, or while the guild name is not known yet
Comm.LOCKDOWN_RETRY = 30
Comm.GUILD_TRIES = 12   -- guild name still unknown after this many tries: give up until the next event
Comm.REPLY_MIN, Comm.REPLY_SPREAD = 2, 8 -- answers to a newcomer spread over 2 to 10 s

local pending, force = nil, false -- what waits to leave: "H" or "S"; force = even if unchanged
local armed = false               -- a send timer is running
local lastSentAt, lastScore = nil, nil
local lastCatch = nil
local guildTries = 0
local replying = false            -- an answer to a newcomer is waiting for its delay

local function clean(...)
    if type(issecretvalue) == "function" then
        for i = 1, select("#", ...) do
            if issecretvalue((select(i, ...))) then return false end
        end
    end
    return true
end

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if not ok or not clean(a) then return nil end
    return a
end

local function code(name)
    local e = Enum and Enum.SendAddonMessageResult
    return e and e[name]
end

local function chat() return type(C_ChatInfo) == "table" and C_ChatInfo or {} end

-- "Guild-Realm", or nil outside a guild or while the game does not know the name yet.
function Comm.guildKey()
    if safe(IsInGuild) ~= true then return nil end
    local name = safe(GetGuildInfo, "player")
    if type(name) ~= "string" or name == "" then return nil end
    return name .. "-" .. tostring(safe(GetRealmName) or "?")
end

-- The player's name as Forever writes it, "First Last": GetUnitName first (under pcall),
-- else UnitName's two returns, the second being the surname on Forever and the realm
-- elsewhere (SO-6 notes, Noyau.lua). The realm suffix is dropped.
function Comm.playerName()
    local realm = tostring(safe(GetRealmName) or "")
    local full = safe(GetUnitName, "player", true)
    if type(full) == "string" and full:find(" ", 1, true) then
        return Board.cleanName((full:gsub("%-" .. realm:gsub("%p", "%%%0") .. "$", "")))
    end
    local ok, first, second = pcall(UnitName, "player")
    if not ok or not clean(first, second) or type(first) ~= "string" then return nil end
    if type(second) == "string" and second ~= "" and second ~= realm and not first:find("[ %-]") then
        first = first .. " " .. second
    end
    return Board.cleanName(first)
end

-- This account as the ranking shows it: one line, named after the character played now.
function Comm.me()
    local db = ns.Main.db
    return { id = db.board.id, name = Comm.playerName() or "?", score = Board.score(db) }
end

local attempt

local function schedule(delay)
    if armed then return end
    armed = true
    C_Timer.After(delay, attempt)
end

attempt = function()
    armed = false
    if not pending then return end
    local db = ns.Main.db
    if not db.settings.share or safe(IsInGuild) ~= true then
        pending = nil
        return
    end
    if not Comm.guildKey() then
        guildTries = guildTries + 1
        if guildTries <= Comm.GUILD_TRIES then schedule(Comm.RETRY) else pending = nil end
        return
    end
    guildTries = 0
    if safe(chat().InChatMessagingLockdown) == true then
        schedule(Comm.LOCKDOWN_RETRY)
        return
    end
    local now = GetTime()
    if lastSentAt and now - lastSentAt < Comm.GAP then
        schedule(Comm.GAP - (now - lastSentAt))
        return
    end
    local text = Board.encode(pending, db.board.id, Board.score(db), Comm.playerName())
    local score = text:sub(2)
    if not force and pending == "S" and score == lastScore then
        pending = nil
        return
    end
    local send = chat().SendAddonMessage
    if type(send) ~= "function" then
        pending = nil
        return
    end
    local ok, res = pcall(send, Board.PREFIX, text, "GUILD")
    lastSentAt = now
    if ok and (res == code("AddonMessageThrottle") or res == code("ChannelThrottle")) then
        schedule(Comm.RETRY)
        return
    end
    if ok and res == code("AddOnMessageLockdown") then
        schedule(Comm.LOCKDOWN_RETRY)
        return
    end
    -- A client that answers nothing did not refuse.
    if ok and (res == nil or res == true or res == 0 or res == code("Success")) then lastScore = score end
    pending, force = nil, false
end

-- Asks for one message; a waiting "H" stays an "H" (it also asks the others to answer).
function Comm.queue(kind, forced)
    if pending ~= "H" then pending = kind end
    force = force or forced == true
    schedule(0)
end

-- A fishing catch was read: the score leaves once the player has stopped for Board.IDLE.
local function idleCheck()
    if lastCatch and GetTime() - lastCatch >= Board.IDLE - 1 then
        lastCatch = nil
        Comm.queue("S")
    end
end

function Comm.onCatch()
    lastCatch = GetTime()
    C_Timer.After(Board.IDLE, idleCheck)
end

function Comm.receive(prefix, text, channel, sender)
    if not clean(prefix, text, channel, sender) then return end
    if prefix ~= Board.PREFIX or channel ~= "GUILD" or type(sender) ~= "string" then return end
    local kind, id, score, named = Board.decode(text)
    if not kind then return end
    local db = ns.Main.db
    if id == db.board.id then return end -- this account (another of its characters, or the echo)
    local guild = Comm.guildKey()
    if not guild then return end
    local name = named or (type(Ambiguate) == "function" and safe(Ambiguate, sender, "none")) or sender
    Board.store(db, guild, id, name, score, time())
    ns.Main.refresh()
    if kind == "H" and db.settings.share and not replying and pending ~= "H" and not (pending and force) then
        -- One answer covers every newcomer heard before it leaves.
        replying = true
        C_Timer.After(Comm.REPLY_MIN + math.random() * Comm.REPLY_SPREAD, function()
            replying = false
            Comm.queue("S", true)
        end)
    end
end

function Comm.onEvent(event, ...)
    if event == "CHAT_MSG_ADDON" then
        Comm.receive(...)
    elseif event == "PLAYER_LOGIN" then
        if safe(chat().IsAddonMessagePrefixRegistered, Board.PREFIX) ~= true then
            safe(chat().RegisterAddonMessagePrefix, Board.PREFIX)
        end
        C_Timer.After(Comm.LOGIN_DELAY, function() Comm.queue("H") end)
    end
end

Comm.EVENTS = { "CHAT_MSG_ADDON", "PLAYER_LOGIN" }

safe(chat().RegisterAddonMessagePrefix, Board.PREFIX)
