-- SpotFriends' entries in the game's right-click menu on a player (portraits, party and raid
-- frames): add or remove the character, and choose its icon from a list drawn like the game's
-- Target Marker Icon one. Uses the menu system the game has had since 11.0 (Menu.ModifyMenu),
-- which Forever's Mainline interface has; a client without it gets no entry and keeps the
-- settings page's Characters list.
local _, SF = ...
local Icons, Resolver = SF.Icons, SF.Resolver

local UnitMenu = { hooked = {} }
SF.UnitMenu = UnitMenu

local TAGS = { "MENU_UNIT_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS", "MENU_UNIT_PARTY",
	"MENU_UNIT_RAID_PLAYER", "MENU_UNIT_RAID", "MENU_UNIT_ENEMY_PLAYER" }

local Known = Resolver.Known
local ICON_SIZE = 16

local function Text(value)
	value = Known(value)
	if type(value) == "string" and value ~= "" then return value end
	return nil
end

--- The character's whole name as the client shows it, from the menu's unit or its name fields.
local function CharacterName(contextData)
	local unit = contextData and contextData.unit
	if unit and Known(UnitExists(unit)) then
		if not Known(UnitIsPlayer(unit)) or Known(UnitIsUnit(unit, "player")) then return nil end
		local whole = Text(GetUnitName and GetUnitName(unit, true))
		if whole then return whole end
		local first, second = UnitName(unit)
		first, second = Text(first), Text(second)
		if first and second then return first .. " " .. second end
		return first
	end
	local name = contextData and Text(contextData.name)
	if not name then return nil end
	local server = Text(contextData.server)
	return server and (name .. "-" .. server) or name
end

local function Close()
	return MenuResponse and MenuResponse.Close or nil
end

-- The icon at the right of its row, as the game's Target Marker entries draw theirs.
local function WithIcon(description, path)
	if not (path and description.AddInitializer) then return end
	description:AddInitializer(function(button)
		if not button.AttachTexture then return end
		local texture = button:AttachTexture()
		texture:SetPoint("RIGHT")
		texture:SetSize(ICON_SIZE, ICON_SIZE)
		texture:SetTexture(path)
		local label = button.fontString
		if label then
			label:SetPoint("RIGHT", texture, "LEFT")
			local width = label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or 100
			return width + 60, 20
		end
	end)
end

local function IconChoice(parent, key, choice, label, path)
	local function IsSelected()
		return (SF.DB().characters[key] or false) == choice
	end
	local function Choose()
		SF.SetCharacter(key, choice)
		return Close()
	end
	-- Without the compositor (an older menu), the icon goes in the label instead.
	if path and not parent.AddInitializer then label = "|T" .. path .. ":" .. ICON_SIZE .. "|t " .. label end
	local description = parent:CreateRadio(label, IsSelected, Choose)
	WithIcon(description, path)
	return description
end

local function Modify(_, root, contextData)
	local display = CharacterName(contextData)
	local key = display and Resolver.NormalizeName(display)
	if not key then return end
	local listed = SF.DB().characters[key] ~= nil
	root:CreateDivider()
	if root.CreateTitle then root:CreateTitle("SpotFriends") end
	if listed then
		root:CreateButton("Remove from SpotFriends", function()
			SF.SetCharacter(key, nil)
			return Close()
		end)
	else
		root:CreateButton("Add to SpotFriends", function()
			SF.SetCharacter(key, Icons.DEFAULT)
			SF.Print(display .. " added, with the default icon.")
			return Close()
		end)
	end
	local icons = root:CreateButton("SpotFriends Icon")
	IconChoice(icons, key, Icons.DEFAULT, "Default (" .. Icons.Label(SF.DB().defaultIcon) .. ")",
		Icons.Path(SF.DB().defaultIcon))
	for _, icon in ipairs(Icons.List) do
		IconChoice(icons, key, icon.key, icon.label, Icons.Path(icon.key))
	end
	IconChoice(icons, key, Icons.NONE, "None")
end

local reported = false

function UnitMenu:Setup()
	if self.ready or not (Menu and Menu.ModifyMenu) then return end
	self.ready = true
	for _, tag in ipairs(TAGS) do
		if pcall(Menu.ModifyMenu, tag, function(...)
			local ok, err = pcall(Modify, ...)
			if not ok and not reported then
				reported = true
				SF.Print("the right-click menu entry failed: " .. tostring(err))
			end
		end) then
			table.insert(self.hooked, tag)
		end
	end
end
