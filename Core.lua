local ADDON_NAME, SF = ...
_G.SpotFriends = SF

SF.ADDON_NAME = ADDON_NAME
SF.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version"))
	or (GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version")) or "?"

local Icons, Resolver = SF.Icons, SF.Resolver

SF.SIZE_MIN, SF.SIZE_MAX = 8, 48
SF.OFFSET_LIMIT = 30

SF.MINIMAP_ANGLE = 175

-- Bumped when saved settings need a one-time change on load (see Migrate).
SF.SETTINGS_VERSION = 3

function SF.Defaults()
	return {
		version = SF.SETTINGS_VERSION,
		enabled = true,
		defaultIcon = Icons.Default(),
		position = "left",
		size = 14,
		offsetX = 0,
		offsetY = 0,
		-- [battleTag] / [friend-list name] -> icon key; "none" hides; absent follows the default.
		friends = { bnet = {}, ingame = {} },
		-- [normalised character name] -> icon key, "default" or "none"; beats the friend list.
		characters = {},
		-- Party and raid members who are not friends.
		group = { enabled = true, icon = Icons.GROUP_DEFAULT },
		-- LibDBIcon's own table: the button's angle and whether it is hidden. 175 degrees is the
		-- minimap's left side, clear of Spoken's button (204) and of LibDBIcon's default (225).
		minimap = { minimapPos = SF.MINIMAP_ANGLE, hide = false },
	}
end

function SF.Fill(target, defaults)
	for key, value in pairs(defaults) do
		if target[key] == nil then
			target[key] = value
		elseif type(value) == "table" and type(target[key]) == "table" then
			SF.Fill(target[key], value)
		end
	end
	return target
end

local function Clamp(value, low, high, fallback)
	if type(value) ~= "number" then return fallback end
	if value < low then return low end
	if value > high then return high end
	return value
end

--- Untouched defaults from an older file become the new ones; a player's own choices stay.
function SF.Migrate(db)
	local version = db.version or 1
	if version < 2 then
		if db.size == 20 then db.size = 14 end
		if db.defaultIcon == "gold-star" then db.defaultIcon = Icons.FRIEND_DEFAULT end
	end
	-- 0.2 placed the button at Spoken's angle, on top of Spoken's button.
	if version < 3 and type(db.minimap) == "table" and db.minimap.minimapPos == 204 then
		db.minimap.minimapPos = SF.MINIMAP_ANGLE
	end
	db.version = SF.SETTINGS_VERSION
	return db
end

local function CurrentKeys(list)
	if type(list) ~= "table" then return end
	for key, value in pairs(list) do list[key] = Icons.Current(value) end
end

local function ValidIcon(key, fallback)
	if key == Icons.NONE or Icons.Get(key) then return key end
	return fallback
end

--- Settings saved by an older or hand-edited file are brought back inside what the page offers.
function SF.Sanitise(db)
	local defaults = SF.Defaults()
	db.defaultIcon = ValidIcon(Icons.Current(db.defaultIcon), defaults.defaultIcon)
	db.group.icon = ValidIcon(Icons.Current(db.group.icon), defaults.group.icon)
	db.group.enabled = db.group.enabled and true or false
	CurrentKeys(db.friends.bnet)
	CurrentKeys(db.friends.ingame)
	CurrentKeys(db.characters)
	if db.position ~= "left" and db.position ~= "right" then db.position = defaults.position end
	db.size = Clamp(db.size, SF.SIZE_MIN, SF.SIZE_MAX, defaults.size)
	db.offsetX = Clamp(db.offsetX, -SF.OFFSET_LIMIT, SF.OFFSET_LIMIT, 0)
	db.offsetY = Clamp(db.offsetY, -SF.OFFSET_LIMIT, SF.OFFSET_LIMIT, 0)
	return db
end

local fallback = SF.Defaults()

function SF.InitDB()
	local saved = type(SpotFriendsDB) == "table" and SpotFriendsDB or nil
	if saved then SF.Migrate(saved) end
	SpotFriendsDB = SF.Sanitise(SF.Fill(saved or {}, SF.Defaults()))
end

--- The settings, readable before ADDON_LOADED too (as the defaults).
function SF.DB()
	return SpotFriendsDB or fallback
end

--- Everything back to the defaults, but the minimap button stays where it was dragged (and
--- LibDBIcon keeps the same table).
function SF.ResetSettings()
	local db = SF.DB()
	local minimap = db.minimap
	for key in pairs(db) do db[key] = nil end
	SF.Fill(db, SF.Defaults())
	if type(minimap) == "table" then
		minimap.hide = false
		db.minimap = minimap
	end
	if SF.MinimapButton then SF.MinimapButton:Refresh() end
	SF.Changed()
end

--- An icon for a character by name (normalised), "default", "none", or nil to forget it.
function SF.SetCharacter(key, choice)
	if not key then return end
	SF.DB().characters[key] = choice
	SF.Changed()
end

function SF.ClearCharacters()
	local characters = SF.DB().characters
	for key in pairs(characters) do characters[key] = nil end
	SF.Changed()
end

--- Anything that may change which plate gets which icon: drop the cached answers and redo the
--- plates on screen (once, on the next frame, however many changes come in between).
function SF.Changed()
	Resolver.Invalidate()
	if SF.Nameplates then SF.Nameplates:RefreshSoon() end
	if SF.Options then SF.Options:RefreshSoon() end
end

--- Only the size or the offsets changed: answers stay, positions are redone.
function SF.Moved()
	if SF.Nameplates then SF.Nameplates:RefreshSoon() end
end

function SF.Print(message)
	DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7SpotFriends|r: " .. tostring(message))
end

-- Registering an event the client does not define throws on Forever and would abort the file;
-- each is registered alone and a refusal is kept for /spotfriends debug.
SF.missingEvents = {}

function SF.RegisterEvents(frame, events)
	for _, event in ipairs(events) do
		if not pcall(frame.RegisterEvent, frame, event) then
			table.insert(SF.missingEvents, event)
		end
	end
end

--------------------------------------------------------------------------------
-- The game's own nameplate settings, offered on the page as a shortcut
--------------------------------------------------------------------------------

local function CVarExists(name)
	if C_CVar and C_CVar.GetCVarDefault then return C_CVar.GetCVarDefault(name) ~= nil end
	return GetCVar and GetCVar(name) ~= nil
end

local function FirstCVar(...)
	for i = 1, select("#", ...) do
		local name = select(i, ...)
		if CVarExists(name) then return name end
	end
end

-- Resolved at Start: the names changed with Midnight's nameplates, and Forever runs that engine.
function SF.FindCVars()
	SF.cvars = {
		friendly = FirstCVar("nameplateShowFriendlyPlayers", "nameplateShowFriends"),
		namesOnly = FirstCVar("nameplateShowOnlyNameForFriendlyPlayerUnits", "nameplateShowOnlyNames"),
		distance = FirstCVar("nameplateMaxDistance"),
	}
	return SF.cvars
end

function SF.GetCVar(name)
	if not name then return nil end
	if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
	return GetCVar(name)
end

local queuedCVars = {}

--- The client refuses CVar writes from an addon in combat: a write made then waits for the end
--- of combat.
function SF.SetCVar(name, value)
	if not name then return false end
	value = tostring(value)
	if InCombatLockdown and InCombatLockdown() then
		queuedCVars[name] = value
		SF.Print("the game's setting changes when this combat ends.")
		return false
	end
	local set = (C_CVar and C_CVar.SetCVar) or SetCVar
	return pcall(set, name, value) and true or false
end

function SF.ApplyQueuedCVars()
	for name, value in pairs(queuedCVars) do
		queuedCVars[name] = nil
		SF.SetCVar(name, value)
	end
end
