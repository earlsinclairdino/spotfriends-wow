local _, SF = ...

local function Yes(value) return value and "yes" or "no" end

local function Debug()
	local Print = SF.Print
	local version, build, _, interface = GetBuildInfo()
	Print(string.format("SpotFriends %s on %s (%s), interface %s", tostring(SF.VERSION), tostring(version),
		tostring(build), tostring(interface)))
	Print(string.format("API: C_NamePlate %s, C_FriendList %s, C_BattleNet %s, BNGetNumFriends %s, issecretvalue %s, Settings %s, CompactUnitFrame_UpdateName %s",
		Yes(C_NamePlate and C_NamePlate.GetNamePlateForUnit), Yes(C_FriendList and C_FriendList.GetFriendInfoByIndex),
		Yes(C_BattleNet and C_BattleNet.GetFriendAccountInfo), Yes(BNGetNumFriends), Yes(issecretvalue),
		Yes(Settings and Settings.RegisterCanvasLayoutCategory), Yes(CompactUnitFrame_UpdateName)))
	if #SF.missingEvents > 0 then
		Print("events this client refused: " .. table.concat(SF.missingEvents, ", "))
	end
	local cvars = SF.cvars or SF.FindCVars()
	Print(string.format("CVars: friendly plates %s = %s, names only %s = %s, simplified = %s, distance %s = %s, name style %s",
		tostring(cvars.friendly), tostring(SF.GetCVar(cvars.friendly)), tostring(cvars.namesOnly),
		tostring(SF.GetCVar(cvars.namesOnly)), tostring(SF.GetCVar("nameplateSimplifiedTypes")),
		tostring(cvars.distance), tostring(SF.GetCVar(cvars.distance)),
		tostring(NamePlateSetupOptions and NamePlateSetupOptions.unitNameAnchorStyle)))
	local first, second = UnitName("player")
	Print(string.format("you: %s / %s + %s, guid %s, realm %s / %s", tostring(GetUnitName and GetUnitName("player", true)),
		tostring(first), tostring(second), tostring(UnitGUID("player")), tostring(GetRealmName and GetRealmName()),
		tostring(GetNormalizedRealmName and GetNormalizedRealmName())))

	local Friends = SF.Friends
	local bnet, bnetOnline, ingame, ingameOnline = Friends:Counts()
	Print(string.format("friends: Battle.net %d (%d online), characters %d (%d online)", bnet, bnetOnline, ingame, ingameOnline))
	local shown = 0
	for _, record in ipairs(Friends.snapshot.bnet) do
		for _, c in ipairs(record.characters) do
			if shown < 5 then
				shown = shown + 1
				Print(string.format("  bnet %s: %s, realm %s%s, guid %s, client %s, online %s", record.id, tostring(c.name),
					tostring(c.realm), c.elsewhere and " (another realm: GUID or name-realm only)" or "", tostring(c.guid),
					tostring(c.client), Yes(c.online)))
			end
		end
	end
	for i, record in ipairs(Friends.snapshot.ingame) do
		if i > 5 then break end
		Print(string.format("  character %s: guid %s, online %s", record.name, tostring(record.guid), Yes(record.online)))
	end

	local db = SF.DB()
	local group = Friends.group or {}
	Print(string.format("group: marking %s, icon %s, %d members", db.group.enabled and "on" or "off",
		tostring(db.group.icon), #group))
	for i, member in ipairs(group) do
		if i > 5 then break end
		Print(string.format("  member %s, guid %s", tostring(member.name), tostring(member.guid)))
	end
	Print(string.format("right-click menu: %s; minimap button: %s", #SF.UnitMenu.hooked > 0
		and table.concat(SF.UnitMenu.hooked, ", ") or "not available on this client",
		SF.MinimapButton.object and (SF.MinimapButton:IsShown() and "shown" or "hidden") or "no libraries"))

	local holders, active = SF.Nameplates:HolderCount()
	Print(string.format("plates: %d icon frames (%d showing), %d answers cached (generation %d), %d errors%s",
		holders, active, SF.Resolver.CacheSize(), SF.Resolver.generation, SF.Nameplates.errors,
		SF.Nameplates.lastError and (": " .. tostring(SF.Nameplates.lastError)) or ""))
	local count = 0
	for unit in pairs(SF.Nameplates.players) do
		count = count + 1
		if count <= 15 then Print("  " .. SF.Nameplates:Describe(unit)) end
	end
	if count == 0 then Print("  no player nameplate on screen") end
	if count > 15 then Print(string.format("  ... and %d more", count - 15)) end
end

local function Command(message)
	local command = (message or ""):match("^%s*(%S*)"):lower()
	if command == "" or command == "options" or command == "settings" then
		if not (SF.Options and SF.Options:Open()) then
			SF.Print("the settings page is not available on this client.")
		end
	elseif command == "debug" then
		Debug()
	elseif command == "plate" then
		local ok, lines = pcall(SF.Nameplates.Dump, SF.Nameplates)
		if not ok then lines = { "could not read the nameplate: " .. tostring(lines) } end
		for _, line in ipairs(lines) do SF.Print(line) end
	elseif command == "test" then
		SF.testMode = not SF.testMode or nil
		SF.Print(SF.testMode and "test: the default icon on every player's nameplate." or "test off.")
		SF.Changed()
	elseif command == "reset" then
		SF.ResetSettings()
		SF.Print("settings back to their defaults.")
	else
		SF.Print("/spotfriends opens the settings; /spotfriends test shows the icon on every player; /spotfriends debug prints what the addon sees; /spotfriends plate lists the parts of your target's nameplate; /spotfriends reset restores the defaults.")
	end
end

_G.SLASH_SPOTFRIENDS1 = "/spotfriends"
_G.SLASH_SPOTFRIENDS2 = "/sf"
SlashCmdList["SPOTFRIENDS"] = Command

-- The AddOn Compartment button (## AddonCompartmentFunc).
function _G.SpotFriends_OpenSettings()
	if SF.Options then SF.Options:Open() end
end
