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

-- "S" (a score) or "H" (a score from someone who just logged in, who asks for others').
-- "kind^version^id^total^rare^epic^legendary^species": under 60 bytes, never cut.
function Board.encode(kind, id, s)
    return table.concat({ kind, Board.VERSION, id, s.total, s.rare, s.epic, s.legendary, s.species }, "^")
end

local function count(text)
    if type(text) ~= "string" or not text:match("^%d+$") then return nil end
    local n = tonumber(text)
    if n > Board.MAX then return nil end
    return n
end

-- kind, id, score; nil for anything FishDex would not have sent. Fields after the known
-- ones are ignored, so a later version can add some at the end.
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
    return f[1], f[3], s
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

-- Saves a score heard from `name` (as the game named the sender).
function Board.store(db, guild, id, name, s, now)
    local g = guildTable(db, guild)
    g[id] = { name = name, total = s.total, rare = s.rare, epic = s.epic, legendary = s.legendary,
        species = s.species, t = now }
end

-- Ranking rows, best first by `sortKey` (a column; ties: total, then name). `me` =
-- { id, name, score } adds this account live, whatever the cache says about it.
function Board.rows(db, guild, me, sortKey)
    local key = sortKey or "total"
    local out = {}
    for id, e in pairs(guild and db.board.guilds[guild] or {}) do
        if type(e) == "table" and (not me or id ~= me.id) and type(e[key]) == "number" then
            out[#out + 1] = { id = id, name = tostring(e.name), total = e.total, rare = e.rare, epic = e.epic,
                legendary = e.legendary, t = e.t }
        end
    end
    if me then
        local s = me.score
        out[#out + 1] = { id = me.id, name = me.name, total = s.total, rare = s.rare, epic = s.epic,
            legendary = s.legendary, me = true }
    end
    table.sort(out, function(a, b)
        if a[key] ~= b[key] then return a[key] > b[key] end
        if a.total ~= b.total then return a.total > b.total end
        return a.name < b.name
    end)
    return out
end
