-- The settings page (Options > AddOns > SpotFriends): the default icon and where icons sit, a
-- preview drawn like a nameplate, a shortcut to the game's own friendly-nameplate settings, an
-- icon per friend, and an icon per character name.
local _, SF = ...
local Icons, Resolver = SF.Icons, SF.Resolver

local Options = {}
SF.Options = Options

local LEFT = 16
local LABEL_WIDTH = 170
local ROW_HEIGHT = 30
local LIST_ROW = 28
local LIST_WIDTH = 560
local NAME_COLOR = { 0.25, 0.78, 0.92 }

local panel, content, scroll
local controls = {}        -- every control with a Refresh, re-read on show and after changes
local refreshing = false

--------------------------------------------------------------------------------
-- Small builders
--------------------------------------------------------------------------------

local function Tooltip(frame, title, body)
	if not title then return end
	frame:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(type(title) == "function" and title() or title, 1, 1, 1)
		local text = type(body) == "function" and body() or body
		if text then GameTooltip:AddLine(text, nil, nil, nil, true) end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Text(parent, font, text, width)
	local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
	fs:SetJustifyH("LEFT")
	if width then
		fs:SetWidth(width)
		if fs.SetWordWrap then fs:SetWordWrap(true) end
	end
	fs:SetText(text or "")
	return fs
end

local function Section(parent, title, y)
	local label = Text(parent, "GameFontNormalLarge", title)
	label:SetPoint("TOPLEFT", LEFT, y)
	local rule = parent:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(1, 0.82, 0, 0.25)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
	rule:SetWidth(LIST_WIDTH)
	return y - 34
end

local function Checkbox(parent, label, tooltip, get, set, x, y)
	local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	box:SetSize(26, 26)
	box:SetPoint("TOPLEFT", x or LEFT, y)
	local text = Text(box, "GameFontHighlight", label)
	text:SetPoint("LEFT", box, "RIGHT", 4, 1)
	box.label = text
	box:SetScript("OnClick", function(self)
		if refreshing then return end
		set(self:GetChecked() and true or false)
		Options:Refresh()
	end)
	box.Refresh = function() box:SetChecked(get() and true or false) end
	Tooltip(box, label, tooltip)
	controls[#controls + 1] = box
	return box
end

local function Slider(parent, label, minValue, maxValue, step, get, set, y, tooltip)
	local caption = Text(parent, "GameFontHighlight", label)
	caption:SetPoint("TOPLEFT", LEFT + 4, y - 6)
	local function Take(value)
		value = math.floor(value / step + 0.5) * step
		if not refreshing and value ~= get() then set(value) end
	end
	local holder
	local ok, made = pcall(CreateFrame, "Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
	if ok and made and made.Init and MinimalSliderWithSteppersMixin and made.RegisterCallback then
		holder = made
		holder:SetWidth(260)
		local formatters = {}
		local labels = MinimalSliderWithSteppersMixin.Label
		if labels then formatters[labels.Right] = function(value) return tostring(math.floor(value + 0.5)) end end
		holder:Init(get(), minValue, maxValue, math.floor((maxValue - minValue) / step + 0.5), formatters)
		holder:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged,
			function(_, value) Take(value) end, holder)
		holder.Refresh = function() holder:SetValue(get()) end
	else
		holder = CreateFrame("Frame", nil, parent)
		holder:SetSize(260, 20)
		local slider = CreateFrame("Slider", nil, holder, WOW_PROJECT_ID == nil and "OptionsSliderTemplate" or "UISliderTemplate")
		slider:SetHeight(16)
		slider:SetWidth(210)
		slider:SetOrientation("HORIZONTAL")
		slider:SetPoint("LEFT", holder, "LEFT", 0, 0)
		slider:SetMinMaxValues(minValue, maxValue)
		slider:SetValueStep(step)
		if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
		local value = Text(holder, "GameFontHighlight", "")
		value:SetPoint("LEFT", slider, "RIGHT", 10, 0)
		slider:SetScript("OnValueChanged", function(_, current)
			value:SetText(tostring(math.floor(current + 0.5)))
			Take(current)
		end)
		holder.Refresh = function()
			slider:SetValue(get())
			value:SetText(tostring(get()))
		end
		Tooltip(slider, label, tooltip)
	end
	holder:SetPoint("TOPLEFT", LEFT + LABEL_WIDTH, y - 2)
	Tooltip(holder, label, tooltip)
	holder.caption = caption
	controls[#controls + 1] = holder
	return holder
end

-- One confirmation dialog for the page's destructive buttons.
local function Confirm(question, accept)
	if not (StaticPopupDialogs and StaticPopup_Show) then
		accept()
		return
	end
	StaticPopupDialogs.SPOTFRIENDS_CONFIRM = {
		text = question, button1 = YES or "Yes", button2 = NO or "No",
		OnAccept = function() accept() end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopup_Show("SPOTFRIENDS_CONFIRM")
end

local function Button(parent, label, width, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(label)
	button:SetScript("OnClick", onClick)
	return button
end

--- A square button showing an icon key: a key's texture, "Default" as the default icon dimmed,
--- "None" as the word.
local function IconButton(parent, size)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(size, size)
	local back = button:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.45)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	button.icon = icon
	local none = Text(button, "GameFontDisableSmall", "None")
	none:SetPoint("CENTER")
	button.none = none
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	function button:SetKey(key)
		self.key = key
		if key == Icons.NONE then
			icon:SetTexture(nil)
			none:Show()
			return
		end
		none:Hide()
		local path = Icons.Path(key)
		local dimmed = path == nil
		path = path or Icons.Path(SF.DB().defaultIcon)
		icon:SetTexture(path)
		icon:SetAlpha(dimmed and 0.45 or 1)
		if not path then none:Show() end
	end
	return button
end

--------------------------------------------------------------------------------
-- The icon picker
--------------------------------------------------------------------------------

local Picker = {}
Options.Picker = Picker
local PICK_SIZE, PICK_GAP, PICK_COLUMNS = 36, 4, 7

local function BuildPicker()
	local frame = CreateFrame("Frame", "SpotFriendsIconPicker", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	if frame.SetBackdrop then
		frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14,
			insets = { left = 4, right = 4, top = 4, bottom = 4 } })
	end
	local title = Text(frame, "GameFontNormal", "")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetPoint("RIGHT", -30, 0)
	frame.title = title
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 0, 0)
	frame.tiles = {}
	local keys = {}
	for _, icon in ipairs(Icons.List) do keys[#keys + 1] = icon.key end
	keys[#keys + 1] = Icons.DEFAULT
	keys[#keys + 1] = Icons.NONE
	for i, key in ipairs(keys) do
		local tile = IconButton(frame, PICK_SIZE)
		local column, row = (i - 1) % PICK_COLUMNS, math.floor((i - 1) / PICK_COLUMNS)
		tile:SetPoint("TOPLEFT", 10 + column * (PICK_SIZE + PICK_GAP), -30 - row * (PICK_SIZE + PICK_GAP))
		tile.choice = key
		local selected = tile:CreateTexture(nil, "OVERLAY")
		selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
		selected:SetBlendMode("ADD")
		selected:SetAllPoints()
		tile.selected = selected
		if key == Icons.DEFAULT then
			local word = Text(tile, "GameFontHighlightSmall", "Default")
			word:SetPoint("BOTTOM", 0, 2)
		end
		tile:SetScript("OnClick", function(self)
			local onPick = Picker.onPick
			frame:Hide()
			if onPick then onPick(self.choice) end
		end)
		Tooltip(tile, function() return Icons.Label(tile.choice) end, function()
			if tile.choice == Icons.DEFAULT then return Picker.defaultTip end
			if tile.choice == Icons.NONE then return "No icon." end
		end)
		frame.tiles[#frame.tiles + 1] = tile
	end
	local rows = math.ceil(#keys / PICK_COLUMNS)
	frame:SetSize(20 + PICK_COLUMNS * (PICK_SIZE + PICK_GAP) - PICK_GAP, 40 + rows * (PICK_SIZE + PICK_GAP))
	frame:Hide()
	frame:SetScript("OnHide", function() Picker.onPick = nil end)
	if UISpecialFrames then table.insert(UISpecialFrames, "SpotFriendsIconPicker") end
	return frame
end

--- Opens the grid beside `anchor`. allowDefault offers "Default" (the default icon, or for a
--- friend, following it); onPick(key) receives the chosen key.
function Picker:Open(anchor, title, current, allowDefault, onPick)
	self.frame = self.frame or BuildPicker()
	local frame = self.frame
	frame.title:SetText(title)
	self.onPick = onPick
	self.defaultTip = allowDefault == "friend" and "Follows the default icon." or "The default icon."
	for _, tile in ipairs(frame.tiles) do
		tile:SetKey(tile.choice)
		local offered = tile.choice ~= Icons.DEFAULT or allowDefault
		tile:SetEnabled(offered and true or false)
		tile:SetAlpha(offered and 1 or 0.25)
		local isCurrent = tile.choice == (current or Icons.DEFAULT)
		tile.selected:SetShown(isCurrent)
	end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
	frame:Show()
	frame:Raise()
end

function Picker:Hide()
	if self.frame then self.frame:Hide() end
end

--------------------------------------------------------------------------------
-- The preview
--------------------------------------------------------------------------------

-- The same placement code as the real plates, on a stand-in drawn like one.
local PREVIEW_STYLES = {
	{ label = "Name above the bar", style = 2 },
	{ label = "Name inside the bar", style = 1 },
	{ label = "Name centred (Classic)", style = 3 },
	{ label = "Names only", style = 2, namesOnly = true },
	{ label = "Simplified", style = 2, simplified = true },
}

local preview

local function LayoutPreview()
	local p = preview
	local look = PREVIEW_STYLES[p.index]
	local uf, name, container, bar, level = p.uf, p.uf.name, p.container, p.bar, p.level
	uf.previewStyle = look.style
	container:SetHeight(look.simplified and 5 or (look.style == 1 and 18 or 11))
	bar:SetShown(not look.namesOnly)
	level:SetShown(not look.namesOnly)
	name:SetShown(not look.simplified)
	name:ClearAllPoints()
	if look.namesOnly then
		name:SetJustifyH("CENTER")
		name:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 4, 2)
		name:SetPoint("BOTTOMRIGHT", container, "TOPRIGHT", -4, 2)
	elseif look.style == 1 then
		name:SetJustifyH("LEFT")
		name:SetPoint("LEFT", container, "LEFT", 4, 0)
		name:SetPoint("RIGHT", container, "RIGHT", -4, 0)
	elseif look.style == 3 then
		name:SetJustifyH("CENTER")
		name:SetPoint("BOTTOM", container, "TOP", 0, 2)
	else
		name:SetJustifyH("LEFT")
		name:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 4, 2)
		name:SetPoint("BOTTOMRIGHT", container, "TOPRIGHT", -4, 2)
	end
	p.cycle:SetText(look.label)
end

local function UpdatePreview()
	if not preview then return end
	LayoutPreview()
	local db = SF.DB()
	local holder = preview.holder
	local key = db.defaultIcon
	local path = Icons.Path(key)
	if not db.enabled or not path then
		holder:Hide()
		return
	end
	holder.icon:SetTexture(path)
	holder:SetSize(db.size, db.size)
	SF.Nameplates.Place(preview.uf, holder, db)
end

local function BuildPreview(parent, y)
	local box = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	box:SetSize(320, 92)
	box:SetPoint("TOPLEFT", LEFT + 4, y)
	if box.SetBackdrop then
		box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		box:SetBackdropColor(0.09, 0.12, 0.08, 0.95)
		box:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
	end
	local uf = CreateFrame("Frame", nil, box)
	uf:SetAllPoints()
	local container = CreateFrame("Frame", nil, uf)
	container:SetSize(170, 11)
	container:SetPoint("CENTER", uf, "CENTER", -12, -12)
	local back = container:CreateTexture(nil, "BACKGROUND")
	back:SetPoint("TOPLEFT", -2, 2)
	back:SetPoint("BOTTOMRIGHT", 2, -2)
	back:SetColorTexture(0, 0, 0, 0.85)
	local bar = CreateFrame("StatusBar", nil, container)
	bar:SetAllPoints()
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetStatusBarColor(0.12, 0.55, 0.75)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	container.healthBar = bar
	local level = CreateFrame("Frame", nil, uf)
	level:SetSize(24, 15)
	level:SetPoint("LEFT", container, "RIGHT", 5, 0)
	local levelBack = level:CreateTexture(nil, "BACKGROUND")
	levelBack:SetAllPoints()
	levelBack:SetColorTexture(0, 0, 0, 0.85)
	local levelText = Text(level, "GameFontNormalSmall", "2")
	levelText:SetPoint("CENTER")
	local name = uf:CreateFontString(nil, "OVERLAY")
	name:SetFontObject(_G.SystemFont_NamePlate or GameFontNormal)
	name:SetText("Fizzle Sprockettorque")
	name:SetTextColor(NAME_COLOR[1], NAME_COLOR[2], NAME_COLOR[3])
	if name.SetWordWrap then name:SetWordWrap(false) end
	uf.name, uf.HealthBarsContainer, uf.LevelFrame = name, container, level
	local holder = CreateFrame("Frame", nil, uf)
	holder:SetFrameLevel(uf:GetFrameLevel() + 10)
	holder.icon = holder:CreateTexture(nil, "OVERLAY")
	holder.icon:SetAllPoints()

	local cycle = Button(parent, "", 190, function()
		preview.index = preview.index % #PREVIEW_STYLES + 1
		UpdatePreview()
	end)
	cycle:SetPoint("TOPLEFT", box, "TOPRIGHT", 12, -4)
	Tooltip(cycle, "Preview", "Shows the icon on each way the game can draw a friendly nameplate. The game's own nameplate settings decide which one you see in the world.")
	local hint = Text(parent, "GameFontDisableSmall", "Click to see the other nameplate looks.", 190)
	hint:SetPoint("TOPLEFT", cycle, "BOTTOMLEFT", 2, -6)

	local index = 1
	local cvars = SF.cvars or {}
	local style = NamePlateSetupOptions and NamePlateSetupOptions.unitNameAnchorStyle
	if cvars.namesOnly and SF.GetCVar(cvars.namesOnly) == "1" then
		index = 4
	elseif style == 1 then
		index = 2
	elseif style == 3 then
		index = 3
	end
	preview = { uf = uf, container = container, bar = bar, level = level, holder = holder, cycle = cycle, index = index }
	controls[#controls + 1] = { Refresh = UpdatePreview }
	return y - 104
end

--------------------------------------------------------------------------------
-- Lists: friends and characters
--------------------------------------------------------------------------------

local function TitleCase(s)
	return (s:gsub("(%S)(%S*)", function(first, rest) return first:upper() .. rest end))
end

local function ByOnlineThenId(a, b)
	if a.online ~= b.online then return a.online end
	return tostring(a.id):lower() < tostring(b.id):lower()
end

local friendsBlock, charactersBlock

local function FriendRow(block, i)
	local row = CreateFrame("Frame", nil, block)
	row:SetSize(LIST_WIDTH, LIST_ROW)
	local button = IconButton(row, 24)
	button:SetPoint("LEFT", 4, 0)
	local name = Text(row, "GameFontHighlight", "")
	name:SetPoint("LEFT", button, "RIGHT", 10, 0)
	name:SetWidth(230)
	if name.SetWordWrap then name:SetWordWrap(false) end
	local detail = Text(row, "GameFontDisableSmall", "")
	detail:SetPoint("LEFT", name, "RIGHT", 8, 0)
	detail:SetWidth(170)
	if detail.SetWordWrap then detail:SetWordWrap(false) end
	local choice = Text(row, "GameFontNormalSmall", "")
	choice:SetPoint("LEFT", detail, "RIGHT", 8, 0)
	choice:SetWidth(120)
	row.button, row.name, row.detail, row.choice = button, name, detail, choice
	local stripe = row:CreateTexture(nil, "BACKGROUND")
	stripe:SetAllPoints()
	stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
	block.rows[i] = row
	return row
end

local function SetFriendIcon(record, key)
	local list = SF.DB().friends[record.kind]
	if key == Icons.DEFAULT then key = nil end
	list[record.id] = key
	SF.Changed()
end

local function FillFriendRow(row, record)
	local db = SF.DB()
	local key = db.friends[record.kind][record.id]
	row.button:SetKey(key or Icons.DEFAULT)
	if record.kind == "bnet" then
		local tag = record.id:match("^([^#]+)") or record.id
		row.name:SetText(record.display ~= record.id and (record.display .. "  |cff888888" .. tag .. "|r") or tag)
	else
		row.name:SetText(record.display)
	end
	local detail
	if not record.online then
		detail = "offline"
	elseif record.kind == "bnet" then
		detail = record.character and ("playing " .. record.character) or "online"
	else
		detail = "online"
	end
	row.detail:SetText(detail)
	row.choice:SetText(key and Icons.Label(key) or ("Default (" .. Icons.Label(db.defaultIcon) .. ")"))
	row.button:SetScript("OnClick", function(self, mouse)
		if mouse == "RightButton" then
			SetFriendIcon(record, nil)
			return
		end
		Picker:Open(self, "Icon for " .. tostring(record.kind == "bnet" and (record.id:match("^([^#]+)") or record.id) or record.id),
			key or Icons.DEFAULT, "friend", function(choice) SetFriendIcon(record, choice) end)
	end)
	row:Show()
end

local function RefreshFriends()
	local block = friendsBlock
	local snapshot = SF.Friends.snapshot
	local bnet, ingame = {}, {}
	for _, r in ipairs(snapshot.bnet) do bnet[#bnet + 1] = r end
	for _, r in ipairs(snapshot.ingame) do ingame[#ingame + 1] = r end
	table.sort(bnet, ByOnlineThenId)
	table.sort(ingame, ByOnlineThenId)
	local y, i = -2, 0
	local function Heading(label, count)
		local heading = block.headings[label]
		heading:ClearAllPoints()
		heading:SetPoint("TOPLEFT", 4, y)
		heading:SetText(string.format("%s (%d)", label, count))
		y = y - 20
	end
	local function Rows(list)
		for _, record in ipairs(list) do
			i = i + 1
			local row = block.rows[i] or FriendRow(block, i)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, y)
			FillFriendRow(row, record)
			y = y - LIST_ROW
		end
		y = y - 8
	end
	Heading("Battle.net friends", #bnet)
	Rows(bnet)
	Heading("Character friends", #ingame)
	Rows(ingame)
	for j = i + 1, #block.rows do block.rows[j]:Hide() end
	block:SetHeight(-y + 4)
end

local SetCharacterIcon = function(key, choice) SF.SetCharacter(key, choice) end

local function CharacterRow(block, i)
	local row = CreateFrame("Frame", nil, block)
	row:SetSize(LIST_WIDTH, LIST_ROW)
	local button = IconButton(row, 24)
	button:SetPoint("LEFT", 4, 0)
	local name = Text(row, "GameFontHighlight", "")
	name:SetPoint("LEFT", button, "RIGHT", 10, 0)
	name:SetWidth(230)
	local choice = Text(row, "GameFontNormalSmall", "")
	choice:SetPoint("LEFT", name, "RIGHT", 8, 0)
	choice:SetWidth(170)
	local remove = Button(row, "Remove", 80, nil)
	remove:SetPoint("LEFT", choice, "RIGHT", 8, 0)
	row.button, row.name, row.choice, row.remove = button, name, choice, remove
	block.rows[i] = row
	return row
end

local function RefreshCharacters()
	local block = charactersBlock
	local db = SF.DB()
	local keys = {}
	for key in pairs(db.characters) do keys[#keys + 1] = key end
	table.sort(keys)
	local y = -38
	for i, key in ipairs(keys) do
		local row = block.rows[i] or CharacterRow(block, i)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, y)
		local choice = db.characters[key]
		row.button:SetKey(choice)
		row.name:SetText(TitleCase(key))
		row.choice:SetText(choice == Icons.DEFAULT and ("Default (" .. Icons.Label(db.defaultIcon) .. ")") or Icons.Label(choice))
		row.button:SetScript("OnClick", function(self)
			Picker:Open(self, "Icon for " .. TitleCase(key), choice, "character",
				function(picked) SetCharacterIcon(key, picked) end)
		end)
		row.remove:SetScript("OnClick", function() SetCharacterIcon(key, nil) end)
		row:Show()
		y = y - LIST_ROW
	end
	for j = #keys + 1, #block.rows do block.rows[j]:Hide() end
	block.empty:SetShown(#keys == 0)
	block.clear:SetEnabled(#keys > 0)
	if #keys == 0 then y = y - 20 end
	block:SetHeight(-y + 8)
end

local function BuildCharacters(parent)
	local block = CreateFrame("Frame", nil, parent)
	block:SetSize(LIST_WIDTH, 80)
	block.rows = {}
	local box = CreateFrame("EditBox", nil, block, "InputBoxTemplate")
	box:SetSize(220, 20)
	box:SetPoint("TOPLEFT", 10, -6)
	box:SetAutoFocus(false)
	if box.SetMaxLetters then box:SetMaxLetters(60) end
	local function Add()
		local key = Resolver.NormalizeName(box:GetText())
		if not key then return end
		box:SetText("")
		box:ClearFocus()
		local db = SF.DB()
		if db.characters[key] == nil then SetCharacterIcon(key, Icons.DEFAULT) end
		Picker:Open(block.add, "Icon for " .. TitleCase(key), db.characters[key], "character",
			function(picked) SetCharacterIcon(key, picked) end)
	end
	box:SetScript("OnEnterPressed", Add)
	box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
	Tooltip(box, "Character name", "The character's whole name as the game shows it, such as \"Fizzle Sprockettorque\". A first name alone matches every character with that first name.")
	local add = Button(block, "Add", 80, Add)
	add:SetPoint("LEFT", box, "RIGHT", 10, 0)
	block.add = add
	local clear = Button(block, "Clear list", 100, function()
		Confirm("Remove every character from SpotFriends' list?", SF.ClearCharacters)
	end)
	clear:SetPoint("LEFT", add, "RIGHT", 10, 0)
	Tooltip(clear, "Clear list", "Removes every character below. Friends keep their own icons.")
	block.clear = clear
	local empty = Text(block, "GameFontDisable", "No character has an icon of its own.")
	empty:SetPoint("TOPLEFT", 10, -40)
	block.empty = empty
	return block
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

local function Build()
	panel = CreateFrame("Frame")
	panel.name = "SpotFriends"
	scroll = CreateFrame("ScrollFrame", "SpotFriendsOptionsScroll", panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -6)
	scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(LIST_WIDTH + 40, 1200)
	scroll:SetScrollChild(content)
	scroll:HookScript("OnSizeChanged", function(self, width) content:SetWidth(math.max(width or 0, LIST_WIDTH + 40)) end)

	local y = -8
	local title = Text(content, "GameFontNormalHuge", "SpotFriends")
	title:SetPoint("TOPLEFT", LEFT, y)
	local version = Text(content, "GameFontDisableSmall", "v" .. tostring(SF.VERSION))
	version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 2)
	y = y - 30
	local intro = Text(content, "GameFontHighlightSmall",
		"An icon next to your friends' nameplates, so you spot them in a crowd. Battle.net friends and character friends get the default icon unless you choose another below; a character name of your own choice beats both, and people in your group who are not friends get the group icon.",
		LIST_WIDTH)
	intro:SetPoint("TOPLEFT", LEFT, y)
	y = y - 42

	local db = SF.DB
	local defaults = Button(content, "Defaults", 100, function()
		Confirm("Put every SpotFriends setting back to its default? Your friends' icons and the characters list are cleared too.", function()
			SF.ResetSettings()
			Options:Refresh()
		end)
	end)
	defaults:SetPoint("TOPRIGHT", content, "TOPLEFT", LEFT + LIST_WIDTH, y + 2)
	Tooltip(defaults, "Defaults", "Every setting back to its default: the icons, their place and size, each friend's icon and the characters list. The minimap button stays where you put it.")
	y = Section(content, "Icon", y)
	Checkbox(content, "Show icons on friends' nameplates", "Also with a middle-click on the minimap button.",
		function() return db().enabled end, function(on) db().enabled = on; SF.Changed() end, LEFT, y)
	Checkbox(content, "Test: show it on every player", "Puts the default icon on every player's nameplate until you turn it off or reload, to try the placement without a friend nearby.",
		function() return SF.testMode end, function(on) SF.testMode = on or nil; SF.Changed() end, LEFT + 290, y)
	y = y - ROW_HEIGHT
	Checkbox(content, "Show the minimap button", "Left-click it for these settings, middle-click it to turn the icons on or off. Drag it around the minimap.",
		function() return SF.MinimapButton:IsShown() end, function(on) SF.MinimapButton:SetShown(on) end, LEFT, y)
	y = y - ROW_HEIGHT

	local defaultLabel = Text(content, "GameFontHighlight", "Default icon")
	defaultLabel:SetPoint("TOPLEFT", LEFT + 4, y - 9)
	local defaultButton = IconButton(content, 32)
	defaultButton:SetPoint("TOPLEFT", LEFT + LABEL_WIDTH, y)
	local defaultName = Text(content, "GameFontNormal", "")
	defaultName:SetPoint("LEFT", defaultButton, "RIGHT", 10, 0)
	defaultButton:SetScript("OnClick", function(self)
		Picker:Open(self, "Default icon", db().defaultIcon, false, function(choice)
			db().defaultIcon = choice
			SF.Changed()
		end)
	end)
	Tooltip(defaultButton, "Default icon", "What every friend gets unless you choose another icon for them below. None shows icons only for the friends and characters you gave one.")
	controls[#controls + 1] = { Refresh = function()
		defaultButton:SetKey(db().defaultIcon)
		defaultName:SetText(Icons.Label(db().defaultIcon))
	end }
	y = y - 42

	local positionLabel = Text(content, "GameFontHighlight", "Position")
	positionLabel:SetPoint("TOPLEFT", LEFT + 4, y - 6)
	Checkbox(content, "Left, before the name", "The icon sits just before the friend's name.",
		function() return db().position == "left" end, function() db().position = "left"; SF.Moved() end,
		LEFT + LABEL_WIDTH - 4, y)
	Checkbox(content, "Right, after the nameplate", "The icon sits after the health bar and level badge, or after the name when the nameplate shows the name alone.",
		function() return db().position == "right" end, function() db().position = "right"; SF.Moved() end,
		LEFT + LABEL_WIDTH + 190, y)
	y = y - ROW_HEIGHT

	Slider(content, "Size", SF.SIZE_MIN, SF.SIZE_MAX, 1, function() return db().size end,
		function(v) db().size = v; SF.Moved() end, y, "The icon's size on a nameplate of the game's medium size; it grows and shrinks with the nameplates.")
	y = y - ROW_HEIGHT
	Slider(content, "Horizontal offset", -SF.OFFSET_LIMIT, SF.OFFSET_LIMIT, 1, function() return db().offsetX end,
		function(v) db().offsetX = v; SF.Moved() end, y, "Moves the icon right (positive) or left (negative).")
	y = y - ROW_HEIGHT
	Slider(content, "Vertical offset", -SF.OFFSET_LIMIT, SF.OFFSET_LIMIT, 1, function() return db().offsetY end,
		function(v) db().offsetY = v; SF.Moved() end, y, "Moves the icon up (positive) or down (negative).")
	y = y - ROW_HEIGHT - 6

	y = BuildPreview(content, y)

	y = Section(content, "Group", y - 6)
	Checkbox(content, "Mark people in my group", "Party and raid members who are not your friends get the group icon. A friend keeps their own icon, and a character from the list below keeps theirs.",
		function() return db().group.enabled end, function(on) db().group.enabled = on; SF.Changed() end, LEFT, y)
	y = y - ROW_HEIGHT
	local groupLabel = Text(content, "GameFontHighlight", "Group icon")
	groupLabel:SetPoint("TOPLEFT", LEFT + 4, y - 9)
	local groupButton = IconButton(content, 32)
	groupButton:SetPoint("TOPLEFT", LEFT + LABEL_WIDTH, y)
	local groupName = Text(content, "GameFontNormal", "")
	groupName:SetPoint("LEFT", groupButton, "RIGHT", 10, 0)
	groupButton:SetScript("OnClick", function(self)
		Picker:Open(self, "Group icon", db().group.icon, false, function(choice)
			db().group.icon = choice
			SF.Changed()
		end)
	end)
	Tooltip(groupButton, "Group icon", "What party and raid members who are not friends get.")
	controls[#controls + 1] = { Refresh = function()
		groupButton:SetKey(db().group.icon)
		groupName:SetText(Icons.Label(db().group.icon))
		groupButton:SetAlpha(db().group.enabled and 1 or 0.4)
	end }
	y = y - 42

	local cvars = SF.cvars or SF.FindCVars()
	y = Section(content, "The game's nameplates", y - 6)
	local note = Text(content, "GameFontHighlightSmall",
		"The icon needs a nameplate. Beyond nameplate range, or with friendly nameplates off, the game draws the name itself and no addon can put anything beside it. These are the game's own settings (Options > Nameplates), here as a shortcut.",
		LIST_WIDTH)
	note:SetPoint("TOPLEFT", LEFT, y)
	y = y - 46
	if cvars.friendly then
		Checkbox(content, "Show friendly players' nameplates", "The game's setting: friendly players get a nameplate, and with it the icon.",
			function() return SF.GetCVar(cvars.friendly) == "1" end,
			function(on) SF.SetCVar(cvars.friendly, on and 1 or 0) end, LEFT, y)
		y = y - ROW_HEIGHT
	end
	if cvars.namesOnly then
		Checkbox(content, "Names only for friendly players", "The game's setting: a friendly player's nameplate shows the name without a health bar, the closest look to the name the game draws far away.",
			function() return SF.GetCVar(cvars.namesOnly) == "1" end,
			function(on) SF.SetCVar(cvars.namesOnly, on and 1 or 0) end, LEFT + 24, y)
		y = y - ROW_HEIGHT
	end
	if cvars.distance then
		Slider(content, "Nameplate distance", 10, 60, 1,
			function() return math.floor((tonumber(SF.GetCVar(cvars.distance)) or 40) + 0.5) end,
			function(v) SF.SetCVar(cvars.distance, v) end, y,
			"The game's setting: how far away nameplates show, in yards. The game may cap it lower than this slider.")
		y = y - ROW_HEIGHT
	end

	y = Section(content, "Friends", y - 6)
	local friendsNote = Text(content, "GameFontHighlightSmall",
		"Click an icon to choose another; right-click it to go back to the default.", LIST_WIDTH)
	friendsNote:SetPoint("TOPLEFT", LEFT, y)
	y = y - 20
	friendsBlock = CreateFrame("Frame", nil, content)
	friendsBlock:SetSize(LIST_WIDTH, 40)
	friendsBlock:SetPoint("TOPLEFT", LEFT, y)
	friendsBlock.rows = {}
	friendsBlock.headings = {}
	for _, label in ipairs({ "Battle.net friends", "Character friends" }) do
		friendsBlock.headings[label] = Text(friendsBlock, "GameFontNormal", label)
	end
	controls[#controls + 1] = { Refresh = RefreshFriends }

	local charactersTitle = CreateFrame("Frame", nil, content)
	charactersTitle:SetSize(LIST_WIDTH, 60)
	charactersTitle:SetPoint("TOPLEFT", friendsBlock, "BOTTOMLEFT", -LEFT, -10)
	Section(charactersTitle, "Characters", 0)
	local charactersNote = Text(charactersTitle, "GameFontHighlightSmall",
		"An icon for a character by name, friend or not. It beats the friend list's icon; None hides the icon for that character.",
		LIST_WIDTH)
	charactersNote:SetPoint("TOPLEFT", LEFT, -34)
	charactersBlock = BuildCharacters(content)
	charactersBlock:SetPoint("TOPLEFT", charactersTitle, "BOTTOMLEFT", LEFT, -4)
	controls[#controls + 1] = { Refresh = RefreshCharacters }

	panel.staticHeight = -y
	panel:SetScript("OnShow", function()
		SF.Friends:Request()
		Options:Refresh()
	end)
	panel:SetScript("OnHide", function() Picker:Hide() end)
end

function Options:Refresh()
	if not panel or not panel:IsVisible() then return end
	refreshing = true
	for _, control in ipairs(controls) do
		local ok, err = pcall(control.Refresh)
		if not ok then SF.Print("settings page: " .. tostring(err)) end
	end
	refreshing = false
	content:SetHeight(panel.staticHeight + friendsBlock:GetHeight() + 80 + charactersBlock:GetHeight() + 30)
end

local refreshQueued = false
local function RunRefresh()
	refreshQueued = false
	Options:Refresh()
end

function Options:RefreshSoon()
	if refreshQueued or not panel or not panel:IsVisible() then return end
	refreshQueued = true
	C_Timer.After(0, RunRefresh)
end

function Options:Setup()
	if panel then return end
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		SF.Print("this client has no settings page for addons; use /spotfriends.")
		return
	end
	Build()
	self.category = Settings.RegisterCanvasLayoutCategory(panel, "SpotFriends")
	Settings.RegisterAddOnCategory(self.category)
end

function Options:Open()
	local category = self.category
	if not (category and Settings and Settings.OpenToCategory) then return false end
	-- The client will not open it for an addon in combat; a click that does nothing reads as
	-- a broken button.
	if InCombatLockdown and InCombatLockdown() then
		if UIErrorsFrame and ERR_NOT_IN_COMBAT then UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1) end
		return true
	end
	local id = category.GetID and category:GetID() or nil
	if id and pcall(Settings.OpenToCategory, id) then return true end
	return pcall(Settings.OpenToCategory, category) and true or false
end
