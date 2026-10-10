-- Which icon, if any, a player in the world gets. Pure Lua (no frames, no client calls) so the
-- tests run it in plain Lua 5.1.
--
-- Priority: a character override, then the friend-list entry's own icon, then the default.
-- "none" at any level means no icon. Hundreds of nameplates come and go every few seconds in a
-- city, so answers are cached by GUID and names are normalised once per distinct spelling.
local Resolver = {}

local NONE, DEFAULT = "none", "default"

-- The Midnight engine hands addons some unit facts as secret values: they cannot be compared,
-- cut or used as a table key, so a secret counts as no value at all.
local isSecret = issecretvalue or function() return false end

function Resolver.SetSecretTest(fn)
	isSecret = fn or issecretvalue or function() return false end
end

function Resolver.Known(value)
	if value == nil or isSecret(value) then return nil end
	return value
end

local function Clear(t)
	for k in pairs(t) do t[k] = nil end
end

--------------------------------------------------------------------------------
-- Names
--------------------------------------------------------------------------------

-- string.lower only knows ASCII; this lowers the Latin-1 capitals (UTF-8 C3 80..9E, except the
-- multiplication sign) so "Éowyn" typed in the settings meets "éowyn" as the client spells it.
local function LowerLatin(c)
	local b = c:byte()
	if b == 0x97 then return "\195" .. c end
	return "\195" .. string.char(b + 32)
end

local normalised, normalisedCount = {}, 0
local NORMALISED_MAX = 5000
Resolver.normaliseMisses = 0

--- "Xanduin Laszwyn", " xanduin  laszwyn ", "Xanduin-Laszwyn" -> "xanduin laszwyn". A Retail
--- "Name-Realm" becomes "name realm", which is how the unit's (name, realm) pair is joined too.
function Resolver.NormalizeName(raw)
	if type(raw) ~= "string" or isSecret(raw) then return nil end
	local hit = normalised[raw]
	if hit ~= nil then return hit or nil end
	Resolver.normaliseMisses = Resolver.normaliseMisses + 1
	local s = raw:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	s = s:gsub("[\"']", ""):gsub("%-", " "):gsub("%s+", " ")
	s = s:match("^%s*(.-)%s*$"):lower():gsub("\195([\128-\158])", LowerLatin)
	if normalisedCount >= NORMALISED_MAX then
		Clear(normalised)
		normalisedCount = 0
	end
	normalised[raw] = s ~= "" and s or false
	normalisedCount = normalisedCount + 1
	return s ~= "" and s or nil
end

--------------------------------------------------------------------------------
-- The friend index
--------------------------------------------------------------------------------

-- A friend record: { kind = "bnet" | "ingame", id = battleTag | friend-list name, ... }.
-- The same character can be both an in-game friend and a Battle.net friend's character: the
-- second record to claim a GUID or a name becomes the first one's `twin`, and an icon chosen on
-- either applies.
local function Claim(map, key, record)
	local held = map[key]
	if held == nil then
		map[key] = record
	elseif held ~= record and held.twin == nil then
		held.twin = record
	end
end

-- `elsewhere`: the character is on another realm (a Battle.net friend playing Retail, say). Its
-- bare name would match a stranger here who shares it, so only its GUID and name-realm count.
local function AddCharacter(index, record, name, realm, guid, elsewhere)
	guid = Resolver.Known(guid)
	if type(guid) == "string" and guid ~= "" then
		Claim(index.byGuid, guid, record)
	end
	local key = Resolver.NormalizeName(name)
	if not key then return end
	if not elsewhere then Claim(index.byName, key, record) end
	realm = Resolver.Known(realm)
	if type(realm) == "string" and realm ~= "" and not key:find(" ", 1, true) then
		local withRealm = Resolver.NormalizeName(name .. "-" .. realm)
		if withRealm then Claim(index.byName, withRealm, record) end
	end
end

--- friends = { bnet = { { id, characters = { { name, realm, guid, elsewhere } } } }, ingame = { { id, name, guid } } }.
--- Reuses `index` (cleared) when given, so a rebuild allocates no new lookup tables.
function Resolver.BuildIndex(friends, index)
	index = index or { byGuid = {}, byName = {} }
	Clear(index.byGuid)
	Clear(index.byName)
	for _, record in ipairs(friends and friends.ingame or {}) do
		record.twin = nil
		AddCharacter(index, record, record.name, nil, record.guid)
	end
	for _, record in ipairs(friends and friends.bnet or {}) do
		record.twin = nil
		for _, character in ipairs(record.characters or {}) do
			AddCharacter(index, record, character.name, character.realm, character.guid, character.elsewhere)
		end
	end
	return index
end

--- members = { { name, guid } } for the party or raid, without the player. Reuses `index`.
function Resolver.BuildGroupIndex(members, index)
	index = index or { byGuid = {}, byName = {} }
	Clear(index.byGuid)
	Clear(index.byName)
	for _, member in ipairs(members or {}) do
		local guid = Resolver.Known(member.guid)
		if type(guid) == "string" and guid ~= "" then index.byGuid[guid] = member end
		local key = Resolver.NormalizeName(member.name)
		if key then index.byName[key] = member end
	end
	return index
end

--------------------------------------------------------------------------------
-- Resolving
--------------------------------------------------------------------------------

local function FriendChoice(db, record)
	local list = db.friends and db.friends[record.kind]
	return list and list[record.id] or nil
end

local function Final(db, choice)
	if choice == nil or choice == DEFAULT then choice = db.defaultIcon end
	if choice == nil or choice == NONE then return nil end
	return choice
end

-- Three spellings of a unit's name: the whole one the client shows ("First Last" on Forever,
-- "Name-Realm" for a Retail visitor), first and second joined (UnitName answers a Forever
-- surname the way Retail answers a realm), and the first alone, for an entry that has no more.
local candidates = {}

local function Candidates(subject)
	local first, second = Resolver.Known(subject.first), Resolver.Known(subject.second)
	candidates[1] = Resolver.NormalizeName(Resolver.Known(subject.whole))
	candidates[2] = (type(first) == "string" and type(second) == "string" and second ~= "")
		and Resolver.NormalizeName(first .. " " .. second) or nil
	candidates[3] = Resolver.NormalizeName(first)
	return candidates
end

local function InGroup(group, guid, names)
	if type(guid) == "string" and group.byGuid[guid] then return group.byGuid[guid] end
	for i = 1, 3 do
		local name = names[i]
		if name and group.byName[name] then return group.byName[name] end
	end
end

local function GroupAnswer(db, index, guid, names)
	local group = db.group
	if not (group and group.enabled and index and index.group) then return nil end
	local member = InGroup(index.group, guid, names)
	if not member then return nil end
	local choice = group.icon
	if choice == nil or choice == NONE then return nil, "group", member end
	return choice, "group", member
end

--- subject = { guid, whole, first, second } as the client reports them (secrets allowed).
--- Returns the icon key or nil, then where the answer came from ("character", "bnet",
--- "ingame", "group") and the friend record or group member, for the debug command.
--- Priority: a character by name, then a friend (even one set to none), then the group.
function Resolver.Resolve(db, index, subject)
	local names = Candidates(subject)
	local characters = db.characters
	if characters then
		for i = 1, 3 do
			local name = names[i]
			local choice = name and characters[name]
			if choice then return Final(db, choice), "character" end
		end
	end
	if not index then return nil end
	local guid = Resolver.Known(subject.guid)
	local record = type(guid) == "string" and index.byGuid[guid] or nil
	if not record then
		for i = 1, 3 do
			local name = names[i]
			record = name and index.byName[name]
			if record then break end
		end
	end
	if not record then return GroupAnswer(db, index, guid, names) end
	local choice = FriendChoice(db, record)
	if choice == nil and record.twin then choice = FriendChoice(db, record.twin) end
	return Final(db, choice), record.kind, record
end

--------------------------------------------------------------------------------
-- The answer cache
--------------------------------------------------------------------------------

-- GUID -> icon key, or false for "no icon". Most plates in a city are strangers, so a stranger
-- costs one lookup after its first sight. Emptied on any change that could alter an answer.
local cache, cacheCount = {}, 0
local CACHE_MAX = 5000
Resolver.generation = 0

function Resolver.Invalidate()
	Clear(cache)
	cacheCount = 0
	Resolver.generation = Resolver.generation + 1
end

function Resolver.Forget(guid)
	guid = Resolver.Known(guid)
	if guid and cache[guid] ~= nil then
		cache[guid] = nil
		cacheCount = cacheCount - 1
	end
end

--- The cached answer for `guid`: a key, false (no icon), or nil when not cached.
function Resolver.Cached(guid)
	return cache[guid]
end

function Resolver.Remember(guid, key)
	if cacheCount >= CACHE_MAX then
		Clear(cache)
		cacheCount = 0
	end
	if cache[guid] == nil then cacheCount = cacheCount + 1 end
	cache[guid] = key or false
end

function Resolver.CacheSize()
	return cacheCount
end

local _, NS = ...
if type(NS) == "table" then NS.Resolver = Resolver end
return Resolver
