-- The player's friends, from the in-game list and Battle.net, in the plain tables Resolver
-- indexes. Friend events come in bursts (a login fires several BN_FRIEND_INFO_CHANGED), so a
-- rebuild waits for the burst to settle and runs once.
local _, SF = ...
local Resolver = SF.Resolver

local Friends = { snapshot = { bnet = {}, ingame = {} }, index = nil, group = {} }
SF.Friends = Friends

local REBUILD_DELAY = 1

local C_FriendList, C_BattleNet = C_FriendList, C_BattleNet
local Known = Resolver.Known

local function Text(value)
	value = Known(value)
	if type(value) == "string" and value ~= "" then return value end
	return nil
end

local function ReadInGame(list)
	local count = C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends() or 0
	local get = C_FriendList and C_FriendList.GetFriendInfoByIndex
	if not get then return end
	for i = 1, Known(count) or 0 do
		local info = get(i)
		local name = info and Text(info.name)
		if name then
			list[#list + 1] = {
				kind = "ingame", id = name, name = name, display = name,
				guid = Text(info.guid), online = info.connected and true or false,
				className = Text(info.className), level = Known(info.level),
			}
		end
	end
end

-- This client's realm, as Battle.net may spell it, normalised; filled at each rebuild.
local myRealms = {}

--- True only when the realm is known and is not this one, in either of the spellings
--- Battle.net gives (its name and its display name).
local function OnAnotherRealm(realm, displayRealm)
	if next(myRealms) == nil then return false end
	local key = Resolver.NormalizeName(realm)
	if not key or myRealms[key] then return false end
	local display = Resolver.NormalizeName(displayRealm)
	return not (display and myRealms[display])
end

local function AddGameAccount(record, game)
	if not game then return end
	local name = Text(game.characterName)
	if not name then return end
	local realm = Text(game.realmName)
	local characters = record.characters
	characters[#characters + 1] = {
		name = name, realm = realm, guid = Text(game.playerGuid),
		client = Text(game.clientProgram), online = game.isOnline and true or false,
		elsewhere = OnAnotherRealm(realm, Text(game.realmDisplayName)),
	}
	if record.online and not record.character then record.character = name end
end

local function ReadBattleNet(list)
	local count = BNGetNumFriends and BNGetNumFriends() or 0
	local getAccount = C_BattleNet and C_BattleNet.GetFriendAccountInfo
	if not getAccount then return end
	local numGames = C_BattleNet.GetFriendNumGameAccounts
	local getGame = C_BattleNet.GetFriendGameAccountInfo
	for i = 1, Known(count) or 0 do
		local account = getAccount(i)
		local tag = account and Text(account.battleTag)
		if tag then
			local game = account.gameAccountInfo
			local record = {
				kind = "bnet", id = tag,
				-- accountName is a protected string: a FontString shows it, Lua cannot read it.
				display = Known(account.accountName) or tag,
				online = game and game.isOnline and true or false,
				characters = {},
			}
			local games = numGames and Known(numGames(i)) or 0
			if games > 0 and getGame then
				for j = 1, games do AddGameAccount(record, getGame(i, j)) end
			else
				AddGameAccount(record, game)
			end
			list[#list + 1] = record
		end
	end
end

function Friends:Rebuild()
	for k in pairs(myRealms) do myRealms[k] = nil end
	local name = Resolver.NormalizeName(Text(GetRealmName and GetRealmName()))
	local normalised = Resolver.NormalizeName(Text(GetNormalizedRealmName and GetNormalizedRealmName()))
	if name then myRealms[name] = true end
	if normalised then myRealms[normalised] = true end
	local snapshot = { bnet = {}, ingame = {} }
	pcall(ReadInGame, snapshot.ingame)
	pcall(ReadBattleNet, snapshot.bnet)
	self.snapshot = snapshot
	self.index = Resolver.BuildIndex(snapshot, self.index)
	SF.Changed()
end

local queued = false
local function RunQueued()
	queued = false
	Friends:Rebuild()
end

function Friends:RebuildSoon()
	if queued then return end
	queued = true
	C_Timer.After(REBUILD_DELAY, RunQueued)
end

--- Asks the server for a fresh in-game list; FRIENDLIST_UPDATE answers.
function Friends:Request()
	if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
end

function Friends:Counts()
	local s, online = self.snapshot, 0
	for _, r in ipairs(s.bnet) do if r.online then online = online + 1 end end
	local ingameOnline = 0
	for _, r in ipairs(s.ingame) do if r.online then ingameOnline = ingameOnline + 1 end end
	return #s.bnet, online, #s.ingame, ingameOnline
end

--------------------------------------------------------------------------------
-- The party or raid
--------------------------------------------------------------------------------

local function MemberName(unit)
	local whole = Text(GetUnitName and GetUnitName(unit, true))
	if whole then return whole end
	local first, second = UnitName(unit)
	first, second = Text(first), Text(second)
	if first and second then return first .. " " .. second end
	return first
end

local function ReadGroup(list)
	local count = Known(GetNumGroupMembers and GetNumGroupMembers()) or 0
	if count == 0 then return end
	local raid = IsInRaid and Known(IsInRaid())
	local prefix, last = raid and "raid" or "party", raid and count or count - 1
	for i = 1, last do
		local unit = prefix .. i
		if Known(UnitExists(unit)) and not Known(UnitIsUnit(unit, "player")) then
			local name = MemberName(unit)
			local guid = Text(UnitGUID(unit))
			if name or guid then list[#list + 1] = { kind = "group", id = guid or name, name = name, guid = guid } end
		end
	end
end

function Friends:RebuildGroup()
	local group = {}
	pcall(ReadGroup, group)
	self.group = group
	self.index = self.index or Resolver.BuildIndex({ bnet = {}, ingame = {} })
	self.index.group = Resolver.BuildGroupIndex(group, self.index.group)
	SF.Changed()
end

-- A join fires GROUP_ROSTER_UPDATE several times, and again for every role or subgroup change.
local GROUP_DELAY = 0.5
local groupQueued = false
local function RunGroup()
	groupQueued = false
	Friends:RebuildGroup()
end

function Friends:RebuildGroupSoon()
	if groupQueued then return end
	groupQueued = true
	C_Timer.After(GROUP_DELAY, RunGroup)
end

Friends.EVENTS = {
	"FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_LIST_SIZE_CHANGED",
	"BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_CONNECTED", "BN_DISCONNECTED",
}
