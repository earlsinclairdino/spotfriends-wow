local Expect = dofile(ADDON_DIR .. "tests/expect.lua")
local Resolver = Expect.Load("Resolver.lua")
local Equal = Expect.Equal

-- Names
Equal(Resolver.NormalizeName("Xanduin Laszwyn"), "xanduin laszwyn", "two-part name")
Equal(Resolver.NormalizeName("  Xanduin   Laszwyn "), "xanduin laszwyn", "spaces trimmed and collapsed")
Equal(Resolver.NormalizeName("Xanduin-Laszwyn"), "xanduin laszwyn", "a dash reads as a space")
Equal(Resolver.NormalizeName("Bob-Argent Dawn"), "bob argent dawn", "Retail name-realm")
Equal(Resolver.NormalizeName('"Meril Jita"'), "meril jita", "quotes dropped")
Equal(Resolver.NormalizeName("\195\137owyn"), "\195\169owyn", "Latin-1 capital lowered")
Equal(Resolver.NormalizeName("|cff00ff00Meril|r"), "meril", "colour codes dropped")
Equal(Resolver.NormalizeName("   "), nil, "blank")
Equal(Resolver.NormalizeName(nil), nil, "nil")
Equal(Resolver.NormalizeName(42), nil, "not a string")

-- The same spelling is normalised once.
local misses = Resolver.normaliseMisses
Resolver.NormalizeName("Cache Check")
Resolver.NormalizeName("Cache Check")
Resolver.NormalizeName("Cache Check")
Equal(Resolver.normaliseMisses - misses, 1, "a repeated spelling is a cache hit")

-- The friend lists, as Friends.lua builds them.
local friends = {
	bnet = {
		{ kind = "bnet", id = "Meri#1111", characters = { { name = "Meril Jita", realm = "Forever", guid = "Player-1-AAA" } } },
		{ kind = "bnet", id = "Xan#2222", characters = { { name = "Xanduin Laszwyn", guid = "Player-1-XAN" } } },
		{ kind = "bnet", id = "Off#3333", characters = {} },
		{ kind = "bnet", id = "Retail#4444", characters = { { name = "Bob", realm = "Argent Dawn" } } },
	},
	ingame = {
		{ kind = "ingame", id = "Tamsin Vale", name = "Tamsin Vale", guid = "Player-1-TAM" },
		{ kind = "ingame", id = "Oryn", name = "Oryn" },
		-- Also Xanduin's character: a twin of the Battle.net entry.
		{ kind = "ingame", id = "Xanduin Laszwyn", name = "Xanduin Laszwyn", guid = "Player-1-XAN" },
	},
}
local index = Resolver.BuildIndex(friends)

local function Db()
	return { defaultIcon = "gold-star", friends = { bnet = {}, ingame = {} }, characters = {} }
end

local function Unit(guid, whole, first, second)
	return { guid = guid, whole = whole, first = first, second = second }
end

local db = Db()
local key, source

-- By GUID, whatever the name says.
key, source = Resolver.Resolve(db, index, Unit("Player-1-AAA", "Somebody Else", "Somebody", "Else"))
Equal(key, "gold-star", "a friend by GUID gets the default")
Equal(source, "bnet", "found on Battle.net")

-- By name when the GUID is unknown, in each spelling the client may use.
Equal(Resolver.Resolve(db, index, Unit(nil, "Tamsin Vale", "Tamsin", "Vale")), "gold-star", "whole name")
Equal(Resolver.Resolve(db, index, Unit(nil, nil, "Tamsin", "Vale")), "gold-star", "first and surname joined")
Equal(Resolver.Resolve(db, index, Unit(nil, nil, "Oryn", "Brightwater")), "gold-star", "a first-name-only friend entry")
Equal(Resolver.Resolve(db, index, Unit(nil, "Bob-Argent Dawn", "Bob", "Argent Dawn")), "gold-star", "Retail name-realm")
Equal(Resolver.Resolve(db, index, Unit("Player-9-NOPE", "Stranger Danger", "Stranger", "Danger")), nil, "a stranger")
Equal(Resolver.Resolve(db, index, Unit(nil, nil, nil, nil)), nil, "nothing known")

-- A friend's own icon beats the default; "none" hides; "default" follows it.
db.friends.bnet["Meri#1111"] = "ruby-heart"
Equal(Resolver.Resolve(db, index, Unit("Player-1-AAA")), "ruby-heart", "the friend's own icon")
db.friends.bnet["Meri#1111"] = "none"
Equal(Resolver.Resolve(db, index, Unit("Player-1-AAA")), nil, "none on the friend")
db.friends.bnet["Meri#1111"] = "default"
Equal(Resolver.Resolve(db, index, Unit("Player-1-AAA")), "gold-star", "default on the friend")
db.defaultIcon = "none"
Equal(Resolver.Resolve(db, index, Unit("Player-1-AAA")), nil, "no default icon")
db.defaultIcon = "gold-star"

-- A character override beats the friend list, and applies to strangers too.
db.friends.bnet["Meri#1111"] = "ruby-heart"
db.characters["meril jita"] = "winged-star"
key, source = Resolver.Resolve(db, index, Unit("Player-1-AAA", "Meril Jita", "Meril", "Jita"))
Equal(key, "winged-star", "the character override wins")
Equal(source, "character", "from the character list")
db.characters["meril jita"] = "none"
Equal(Resolver.Resolve(db, index, Unit("Player-1-AAA", "Meril Jita", "Meril", "Jita")), nil, "none on the character beats the friend icon")
db.characters["stranger danger"] = "default"
Equal(Resolver.Resolve(db, index, Unit(nil, nil, "Stranger", "Danger")), "gold-star", "a stranger marked with the default")
db.characters["oryn"] = "blue-orb"
Equal(Resolver.Resolve(db, index, Unit(nil, "Oryn Brightwater", "Oryn", "Brightwater")), "blue-orb", "a first-name override")

-- The same character as an in-game friend and a Battle.net friend: either icon applies.
db = Db()
db.friends.ingame["Xanduin Laszwyn"] = "cyan-shield"
Equal(Resolver.Resolve(db, index, Unit("Player-1-XAN")), "cyan-shield", "the twin's icon applies")
db.friends.bnet["Xan#2222"] = "shield-star"
Equal(Resolver.Resolve(db, index, Unit("Player-1-XAN")), "cyan-shield", "the first claim's icon first")

-- Secrets are never compared or used as keys.
Resolver.SetSecretTest(function(v) return v == "SECRET" end)
db = Db()
Equal(Resolver.Resolve(db, index, Unit("SECRET", "SECRET", "SECRET", "SECRET")), nil, "all secret")
Equal(Resolver.Resolve(db, index, Unit("SECRET", "Tamsin Vale", "SECRET", nil)), "gold-star", "a secret GUID, a known name")
Equal(Resolver.Known("SECRET"), nil, "Known drops a secret")
Resolver.SetSecretTest(nil)

-- A Battle.net friend on another realm (playing Retail, say): its bare name would match a
-- stranger here, so only its GUID and its name-realm count.
local away = Resolver.BuildIndex({ ingame = {}, bnet = {
	{ kind = "bnet", id = "Away#5555", characters = { { name = "Bob", realm = "Argent Dawn", guid = "Player-9-BOB", elsewhere = true } } },
} })
Equal(Resolver.Resolve(Db(), away, Unit(nil, "Bob Smith", "Bob", "Smith")), nil, "a stranger sharing the bare name")
Equal(Resolver.Resolve(Db(), away, Unit(nil, "Bob", "Bob", nil)), nil, "even the exact bare name")
Equal(Resolver.Resolve(Db(), away, Unit("Player-9-BOB")), "gold-star", "the friend by GUID")
Equal(Resolver.Resolve(Db(), away, Unit(nil, "Bob-Argent Dawn", "Bob", "Argent Dawn")), "gold-star", "the friend by name-realm")

-- Rebuilding reuses the index tables.
local byGuid = index.byGuid
local again = Resolver.BuildIndex({ bnet = {}, ingame = { { kind = "ingame", id = "Solo", name = "Solo" } } }, index)
Equal(again, index, "the same index table")
Equal(again.byGuid, byGuid, "the same GUID table")
Equal(again.byGuid["Player-1-AAA"], nil, "old entries gone")
Equal(Resolver.Resolve(Db(), again, Unit(nil, "Solo")), "gold-star", "new entries in")

-- The answer cache.
Resolver.Invalidate()
local generation = Resolver.generation
Equal(Resolver.Cached("Player-1-AAA"), nil, "empty after Invalidate")
Resolver.Remember("Player-1-AAA", "gold-star")
Resolver.Remember("Player-2-BBB", nil)
Equal(Resolver.Cached("Player-1-AAA"), "gold-star", "a remembered key")
Equal(Resolver.Cached("Player-2-BBB"), false, "a remembered stranger")
Equal(Resolver.CacheSize(), 2, "two answers")
Resolver.Forget("Player-1-AAA")
Equal(Resolver.Cached("Player-1-AAA"), nil, "forgotten")
Equal(Resolver.CacheSize(), 1, "one answer")
Resolver.Invalidate()
Equal(Resolver.generation, generation + 1, "the generation moves on")
Equal(Resolver.CacheSize(), 0, "empty again")

-- A city's worth of plates: mostly strangers, a few friends, every name seen many times. Only
-- the first sight of each GUID resolves; the rest are cache hits.
index = Resolver.BuildIndex(friends, index)
db = Db()
local resolves, hits = 0, 0
local start = os.clock()
for i = 1, 50000 do
	local n = i % 400
	local guid = n < 5 and ({ "Player-1-AAA", "Player-1-XAN", "Player-1-TAM", "Player-1-AAA", "Player-1-XAN" })[n + 1]
		or ("Player-1-" .. n)
	local cached = Resolver.Cached(guid)
	if cached == nil then
		resolves = resolves + 1
		cached = Resolver.Resolve(db, index, Unit(guid, "Someone " .. n, "Someone", tostring(n))) or false
		Resolver.Remember(guid, cached)
	else
		hits = hits + 1
	end
end
Equal(resolves, 398, "each distinct GUID resolved once")
Equal(hits, 50000 - 398, "everything else from the cache")
Equal(Resolver.Cached("Player-1-XAN"), "gold-star", "a friend cached with its icon")
Equal(Resolver.Cached("Player-1-77"), false, "a stranger cached as no icon")
print(string.format("50000 plate lookups in %.1f ms", (os.clock() - start) * 1000))

-- The group: members who are not friends get the group icon; friends and characters win.
do
	local list = { bnet = {}, ingame = { { kind = "ingame", id = "Tamsin Vale", name = "Tamsin Vale", guid = "Player-1-TAM" } } }
	local idx = Resolver.BuildIndex(list)
	idx.group = Resolver.BuildGroupIndex({
		{ name = "Grim Stoneback", guid = "Player-1-GRM" },
		{ name = "Tamsin Vale", guid = "Player-1-TAM" },
		{ name = "Nob Guid" },
	})
	local gdb = Db()
	gdb.group = { enabled = true, icon = "blue-spot" }
	local k, src = Resolver.Resolve(gdb, idx, Unit("Player-1-GRM", "Grim Stoneback", "Grim", "Stoneback"))
	Equal(k, "blue-spot", "a group member gets the group icon")
	Equal(src, "group", "from the group")
	Equal(Resolver.Resolve(gdb, idx, Unit(nil, nil, "Nob", "Guid")), "blue-spot", "a member by name")
	Equal(Resolver.Resolve(gdb, idx, Unit("Player-1-TAM")), "gold-star", "a friend in the group keeps the friend icon")
	gdb.friends.ingame["Tamsin Vale"] = "none"
	Equal(Resolver.Resolve(gdb, idx, Unit("Player-1-TAM")), nil, "a friend set to none stays hidden in the group")
	gdb.characters["grim stoneback"] = "red-heart"
	Equal(Resolver.Resolve(gdb, idx, Unit("Player-1-GRM", "Grim Stoneback")), "red-heart", "a character beats the group")
	gdb.characters["grim stoneback"] = nil
	gdb.group.icon = "none"
	Equal(Resolver.Resolve(gdb, idx, Unit("Player-1-GRM")), nil, "group icon none")
	gdb.group.icon, gdb.group.enabled = "blue-spot", false
	Equal(Resolver.Resolve(gdb, idx, Unit("Player-1-GRM")), nil, "group marking off")
	gdb.group.enabled = true
	Equal(Resolver.Resolve(gdb, idx, Unit("Player-1-ZZZ", "Grim Other", "Grim", "Other")), nil, "a namesake outside the group")
	-- Rebuilding the friend index keeps the group, and the group index is reused.
	local groupTable = idx.group
	Resolver.BuildIndex(list, idx)
	Equal(idx.group, groupTable, "the friend rebuild keeps the group")
	Equal(Resolver.BuildGroupIndex({}, idx.group), groupTable, "the same group table")
	Equal(Resolver.Resolve(gdb, idx, Unit("Player-1-GRM")), nil, "an emptied group")
end

Expect.Done("resolver")
