-- Pure logic of the guild ranking (renaud, 2026-11-01): each account's score (everything
-- fished, shinies per grade), the one-line message that carries it, and the cache of the
-- scores heard from guild members. No game call here.
-- Trust: the roll is made by each client, so a score is only as honest as its sender; the
-- checks below only refuse what FishDex itself could never send.
local _, ns = ...

local Board = {}
ns.Board = Board

Board.PREFIX = "FishDex"   -- addon message prefix (16 bytes at most)
Board.VERSION = 1          -- wire format; a message of another version is ignored
Board.IDLE = 120           -- seconds without a fishing catch before the score is sent
Board.MAX = 9999999        -- largest count a message may carry
Board.COLUMNS = { "total", "rare", "epic", "legendary" }

-- An account id: 8 hex digits, drawn once and saved. It merges the alts of one account
-- (catches are per account) and tells two accounts with the same character name apart.
function Board.ensureId(db, random)
    local b = db.board
    if type(b.id) ~= "string" or not b.id:match("^%x%x%x%x%x%x%x%x$") then
        b.id = string.format("%08x", math.floor(random() * 4294967295))
    end
    return b.id
end

-- A shiny forced by /fishdex shinytest stays in the collection but never in the ranking.
function Board.noteForced(db, key)
    local forced = db.board.forced
    forced[key] = (tonumber(forced[key]) or 0) + 1
end

-- This account's score: { total, rare, epic, legendary, species }.
function Board.score(db)
    local s = { total = 0, species = 0, rare = 0, epic = 0, legendary = 0 }
    for _, c in pairs(db.catches) do
        s.total = s.total + c.count
        s.species = s.species + 1
    end
    for id, byGrade in pairs(db.shiny) do
        -- Shinies saved on an entry no longer eligible (quest items before 2026-11-01) stay
        -- in the save but leave the score.
        if not ns.Shiny.eligible(ns.Dex.entry(id)) then byGrade = {} end
        for key, c in pairs(byGrade) do
            if s[key] and type(c) == "table" and type(c.count) == "number" then s[key] = s[key] + c.count end
        end
    end
    for _, g in ipairs(ns.Shiny.GRADES) do
        s[g.key] = math.max(0, s[g.key] - (tonumber(db.board.forced[g.key]) or 0))
    end
    return s
end

Board.NAME_BYTES = 48

-- A character name fit for the wire and the table: no "^", "|" or control character,
-- spaces trimmed, at most NAME_BYTES bytes cut on a UTF-8 boundary; nil when empty.
-- Forever names are "First Last" (SO-6 notes), so a space is kept.
function Board.cleanName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("[%c%^|]", ""):gsub("^ +", ""):gsub(" +$", ""):gsub(" +", " ")
    if #name > Board.NAME_BYTES then
        name = name:sub(1, Board.NAME_BYTES)
        -- drop a cut multi-byte character: trailing continuation bytes and their lead byte
        name = name:gsub("[\192-\255][\128-\191]*$", "")
    end
    if name == "" then return nil end
    return name
end

-- "S" (a score) or "H" (a score from someone who just logged in, who asks for others').
-- "kind^version^id^total^rare^epic^legendary^species^name": under 110 bytes, never cut.
-- The name travels in the message because Forever's sender names ("First Last") are not
-- measured yet: what the sender calls itself is shown, the channel's sender is a fallback.
function Board.encode(kind, id, s, name)
    return table.concat({ kind, Board.VERSION, id, s.total, s.rare, s.epic, s.legendary, s.species,
        Board.cleanName(name) or "" }, "^")
end

local function count(text)
    if type(text) ~= "string" or not text:match("^%d+$") then return nil end
    local n = tonumber(text)
    if n > Board.MAX then return nil end
    return n
end

-- kind, id, score, name (nil when absent); nil for anything FishDex would not have sent.
-- Fields after the known ones are ignored, so a later version can add some at the end.
function Board.decode(text)
    if type(text) ~= "string" or #text > 255 then return nil end
    local f = {}
    for part in (text .. "^"):gmatch("([^%^]*)%^") do f[#f + 1] = part end
    if f[1] ~= "S" and f[1] ~= "H" then return nil end
    if f[2] ~= tostring(Board.VERSION) then return nil end
    if type(f[3]) ~= "string" or not f[3]:match("^%x%x%x%x%x%x%x%x$") then return nil end
    local s = { total = count(f[4]), rare = count(f[5]), epic = count(f[6]), legendary = count(f[7]),
        species = count(f[8]) }
    for _, v in ipairs({ "total", "rare", "epic", "legendary", "species" }) do
        if not s[v] then return nil end
    end
    if s.rare + s.epic + s.legendary > s.total or s.species > s.total then return nil end
    return f[1], f[3], s, Board.cleanName(f[9])
end

-- Scores are kept per guild ("Guild-Realm"): a member who changes guild starts afresh.
local function guildTable(db, guild)
    local g = db.board.guilds[guild]
    if type(g) ~= "table" then
        g = {}
        db.board.guilds[guild] = g
    end
    return g
end

Board.ALTS_MAX = 20

-- Adds `name` to a set of character names (name = last time seen), keeping the
-- ALTS_MAX most recent.
local function addAlt(set, name, now)
    if type(name) ~= "string" then return end
    set[name] = now
    local n, oldest, oldestT = 0, nil, nil
    for k, t in pairs(set) do
        n = n + 1
        if not oldestT or t < oldestT then oldest, oldestT = k, t end
    end
    if n > Board.ALTS_MAX then set[oldest] = nil end
end

-- The characters of this account that played with FishDex (renaud, 2026-11-01: one line
-- per account, its characters in the line's tooltip).
function Board.noteChar(db, name, now)
    addAlt(db.board.chars, Board.cleanName(name), now)
end

-- Saves a score heard from `name`; the characters already heard on that account stay.
function Board.store(db, guild, id, name, s, now)
    local g = guildTable(db, guild)
    local alts = type(g[id]) == "table" and type(g[id].alts) == "table" and g[id].alts or {}
    addAlt(alts, name, now)
    g[id] = { name = name, total = s.total, rare = s.rare, epic = s.epic, legendary = s.legendary,
        species = s.species, t = now, alts = alts }
end

-- Names of a set, most recently seen first.
function Board.altList(set)
    local out = {}
    for k, t in pairs(type(set) == "table" and set or {}) do
        if type(k) == "string" and type(t) == "number" then out[#out + 1] = k end
    end
    table.sort(out, function(a, b)
        if set[a] ~= set[b] then return set[a] > set[b] end
        return a < b
    end)
    return out
end

-- Ranking rows, best first by `sortKey` (a column; ties: total, then name). `me` =
-- { id, name, score } adds this account live, whatever the cache says about it.
function Board.rows(db, guild, me, sortKey)
    local key = sortKey or "total"
    local out = {}
    for id, e in pairs(guild and db.board.guilds[guild] or {}) do
        if type(e) == "table" and (not me or id ~= me.id) and type(e[key]) == "number" then
            out[#out + 1] = { id = id, name = tostring(e.name), total = e.total, rare = e.rare, epic = e.epic,
                legendary = e.legendary, t = e.t, alts = Board.altList(e.alts) }
        end
    end
    if me then
        local s = me.score
        out[#out + 1] = { id = me.id, name = me.name, total = s.total, rare = s.rare, epic = s.epic,
            legendary = s.legendary, me = true, alts = Board.altList(db.board.chars) }
    end
    table.sort(out, function(a, b)
        if a[key] ~= b[key] then return a[key] > b[key] end
        if a.total ~= b.total then return a.total > b.total end
        return a.name < b.name
    end)
    return out
end
