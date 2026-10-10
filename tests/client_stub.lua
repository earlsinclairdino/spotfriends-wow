-- A permissive stand-in for the client: widgets that remember points, text, scripts and shown
-- state, answer any other method with a no-op, and the handful of APIs SpotFriends calls.
-- Enough to load the whole addon in TOC order and drive its page, commands and nameplates.
local Stub = { widgets = {}, timers = {}, chat = {}, cvars = {}, combat = false }

local function Visible(w)
	while w do
		if not w.shown then return false end
		w = w.parent
	end
	return true
end

local function Widget(kind, name, parent)
	local w = { kind = kind, name = name, parent = parent, shown = true, points = {}, scripts = {},
		hooks = {}, text = "", width = 0, height = 0, level = 1, enabled = true }
	function w:SetPoint(...) self.points[#self.points + 1] = { ... } end
	function w:ClearAllPoints() self.points = {} end
	function w:SetAllPoints() self.points = { { "ALL" } } end
	function w:SetSize(width, height) self.width, self.height = width, height end
	function w:SetWidth(width) self.width = width end
	function w:SetHeight(height) self.height = height end
	function w:GetWidth() return self.width end
	function w:GetHeight() return self.height end
	-- Every position is refused, as the client does for a nameplate's regions: placement must
	-- never need one (the settings page's preview goes through the same code).
	for _, method in ipairs({ "GetLeft", "GetRight", "GetTop", "GetBottom", "GetCenter", "GetRect" }) do
		w[method] = function() error("Frame:GetRight(): Action[FrameMeasurement] failed because[Can't measure restricted regions]") end
	end
	function w:GetNumPoints() return #self.points end
	function w:Show()
		local was = self.shown
		self.shown = true
		if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
	end
	function w:Hide()
		local was = self.shown
		self.shown = false
		if was and self.scripts.OnHide then self.scripts.OnHide(self) end
	end
	function w:SetShown(on) if on then self:Show() else self:Hide() end end
	function w:IsShown() return self.shown end
	function w:IsVisible() return Visible(self) end
	function w:SetScript(script, fn) self.scripts[script] = fn end
	function w:GetScript(script) return self.scripts[script] end
	function w:HookScript(script, fn)
		self.hooks[script] = self.hooks[script] or {}
		table.insert(self.hooks[script], fn)
	end
	function w:SetText(text) self.text = text or "" end
	function w:GetText() return self.text end
	function w:GetStringWidth() return #tostring(self.text) * 6 end
	function w:SetJustifyH(j) self.justify = j end
	function w:GetJustifyH() return self.justify or "LEFT" end
	function w:SetChecked(on) self.checked = on and true or false end
	function w:GetChecked() return self.checked end
	function w:SetTexture(path) self.texture = path end
	function w:SetValue(value)
		self.value = value
		if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
	end
	function w:GetValue() return self.value end
	function w:SetEnabled(on) self.enabled = on and true or false end
	function w:GetParent() return self.parent end
	function w:GetFrameLevel() return self.level end
	function w:SetFrameLevel(level) self.level = level end
	function w:IsForbidden() return false end
	function w:RegisterEvent(event)
		self.events = self.events or {}
		self.events[event] = true
	end
	function w:UnregisterEvent(event) if self.events then self.events[event] = nil end end
	function w:CreateFontString() return Widget("FontString", nil, self) end
	function w:CreateTexture() return Widget("Texture", nil, self) end
	function w:Click(mouse)
		if not self.enabled then return end
		if self.kind == "CheckButton" then self.checked = not self.checked end
		if self.scripts.OnClick then self.scripts.OnClick(self, mouse or "LeftButton") end
		for _, h in ipairs(self.hooks.OnClick or {}) do h(self, mouse or "LeftButton") end
	end
	setmetatable(w, { __index = function(_, k)
		if type(k) == "string" and k:match("^[A-Z]") then return function() end end
	end })
	table.insert(Stub.widgets, w)
	return w
end
Stub.Widget = Widget

function CreateFrame(kind, name, parent)
	local w = Widget(kind, name, parent)
	if name then _G[name] = w end
	return w
end

UIParent = Widget("Frame", "UIParent")
GameTooltip = Widget("GameTooltip", "GameTooltip")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) table.insert(Stub.chat, message) end }
UIErrorsFrame = { AddMessage = function(_, message) table.insert(Stub.chat, "error frame: " .. message) end }
SlashCmdList = {}
UISpecialFrames = {}
BackdropTemplateMixin = {}
GameFontNormal = {}
ERR_NOT_IN_COMBAT = "You can't do that while in combat"
UNKNOWNOBJECT = "Unknown"
WOW_PROJECT_ID = 1
NamePlateSetupOptions = { unitNameAnchorStyle = 2 }

function GetRealmName() return "ClassicBetaPvE2" end
function GetNormalizedRealmName() return "ClassicBetaPvE2" end
function GetBuildInfo() return "1.60.1", "70205", "Oct 2026", 16001 end
function InCombatLockdown() return Stub.combat end
C_AddOns = { GetAddOnMetadata = function() return "0.1.0" end }

C_Timer = { After = function(_, fn) table.insert(Stub.timers, fn) end }
function Stub.RunTimers()
	for _ = 1, 10 do
		local due = Stub.timers
		if #due == 0 then return end
		Stub.timers = {}
		for _, fn in ipairs(due) do fn() end
	end
end

local known = { nameplateShowFriendlyPlayers = "0", nameplateShowOnlyNameForFriendlyPlayerUnits = "0",
	nameplateSimplifiedTypes = "0", nameplateMaxDistance = "41" }
for k, v in pairs(known) do Stub.cvars[k] = v end
C_CVar = {
	GetCVarDefault = function(name) return known[name] end,
	GetCVar = function(name) return Stub.cvars[name] end,
	GetCVarBool = function(name) return Stub.cvars[name] == "1" end,
	SetCVar = function(name, value)
		if Stub.combat then error("blocked in combat") end
		Stub.cvars[name] = tostring(value)
	end,
}

Settings = {
	RegisterCanvasLayoutCategory = function(panel, name)
		return { panel = panel, name = name, GetID = function() return name end }
	end,
	RegisterAddOnCategory = function(category) Stub.category = category end,
	OpenToCategory = function(id) Stub.opened = id; return true end,
}

function hooksecurefunc(target, name, fn)
	if type(target) == "string" then
		target, name, fn = _G, target, name
	end
	local original = target[name]
	target[name] = function(...)
		local a, b, c, d = original(...)
		fn(...)
		return a, b, c, d
	end
end

-- Units, friends and the group.
Stub.units = {}
Stub.group = {}      -- unit tokens in the party, without the player
Stub.raid = false
function UnitExists(unit) return unit == "player" or Stub.units[unit] ~= nil end
function GetNumGroupMembers() return #Stub.group > 0 and #Stub.group + 1 or 0 end
function IsInRaid() return Stub.raid end

-- Confirmation dialogs accept at once.
StaticPopupDialogs = {}
YES, NO = "Yes", "No"
function StaticPopup_Show(which)
	Stub.popups = (Stub.popups or 0) + 1
	local dialog = StaticPopupDialogs[which]
	if dialog and dialog.OnAccept then dialog.OnAccept() end
end

-- The 11.0 menu system: a description records what is added to it.
Stub.menus = {}
MenuResponse = { Close = 1 }
local function Description(text, kind, a, b)
	local d = { text = text, kind = kind, children = {}, initializers = {} }
	if kind == "radio" then d.isSelected, d.setSelected = a, b else d.callback = a end
	local function Add(childKind)
		return function(self, label, x, y)
			local child = Description(label, childKind, x, y)
			table.insert(self.children, child)
			return child
		end
	end
	d.CreateButton, d.CreateRadio, d.CreateCheckbox = Add("button"), Add("radio"), Add("checkbox")
	d.CreateTitle = Add("title")
	function d:CreateDivider() table.insert(self.children, { kind = "divider" }) end
	function d:AddInitializer(fn) table.insert(self.initializers, fn) end
	return d
end
Menu = { ModifyMenu = function(tag, fn) Stub.menus[tag] = fn; return {} end }
--- Opens the menu `tag` on contextData and returns its root description.
function Stub.Menu(tag, contextData)
	local root = Description("root", "root")
	Stub.menus[tag](nil, root, contextData)
	return root
end
function Stub.MenuEntry(root, text)
	for _, child in ipairs(root.children) do
		if child.text and child.text:find(text, 1, true) then return child end
	end
end

-- LibStub with the two minimap libraries, recording what the addon asks of them.
Stub.broker, Stub.dbicon = { objects = {} }, { registered = {}, refreshed = 0 }
function Stub.broker:NewDataObject(name, object) self.objects[name] = object; return object end
function Stub.dbicon:Register(name, object, db) self.registered[name] = { object = object, db = db } end
function Stub.dbicon:Refresh(name, db)
	self.refreshed = self.refreshed + 1
	self.registered[name].db = db
	self.registered[name].shown = not db.hide
end
function Stub.dbicon:GetMinimapButton(name)
	local entry = self.registered[name]
	if not entry then return nil end
	entry.button = entry.button or Widget("Button", "LibDBIcon10_" .. name)
	entry.button.icon = entry.button.icon or Widget("Texture", nil, entry.button)
	return entry.button
end
local libraries = { ["LibDataBroker-1.1"] = Stub.broker, ["LibDBIcon-1.0"] = Stub.dbicon }
LibStub = setmetatable({}, { __call = function(_, name) return libraries[name] end })
function UnitIsPlayer(unit) return Stub.units[unit] and Stub.units[unit].player or false end
function UnitIsUnit(a, b) return a == b end
function UnitGUID(unit) return Stub.units[unit] and Stub.units[unit].guid end
function UnitName(unit)
	if unit == "player" then return "Me", "Myself" end
	local u = Stub.units[unit]
	return u and u.first, u and u.second
end
function GetUnitName(unit)
	if unit == "player" then return "Me Myself" end
	local u = Stub.units[unit]
	return u and (u.second and (u.first .. " " .. u.second) or u.first)
end

Stub.plates = {}
C_NamePlate = {
	GetNamePlateForUnit = function(unit) return Stub.plates[unit] end,
	GetNamePlates = function()
		local list = {}
		for _, plate in pairs(Stub.plates) do list[#list + 1] = plate end
		return list
	end,
}

function Stub.AddPlate(unit, fields)
	Stub.units[unit] = fields
	local uf = Widget("Frame", nil, nil)
	uf.unit = unit
	uf.name = Widget("FontString", nil, uf)
	uf.name.text = fields.second and (fields.first .. " " .. fields.second) or fields.first
	uf.HealthBarsContainer = Widget("Frame", nil, uf)
	uf.HealthBarsContainer.healthBar = Widget("StatusBar", nil, uf.HealthBarsContainer)
	uf.LevelFrame = Widget("Frame", nil, uf)
	uf.RaidTargetFrame = Widget("Frame", nil, uf)
	uf.RaidTargetFrame.shown = false
	uf.ClassificationFrame = Widget("Frame", nil, uf)
	uf.ClassificationFrame.shown = false
	function uf:UpdateAnchors() end
	local plate = { UnitFrame = uf, namePlateUnitToken = unit }
	Stub.plates[unit] = plate
	return uf
end

Stub.friends = { ingame = {}, bnet = {} }
C_FriendList = {
	GetNumFriends = function() return #Stub.friends.ingame end,
	GetFriendInfoByIndex = function(i) return Stub.friends.ingame[i] end,
	ShowFriends = function() Stub.askedFriends = true end,
}
function BNGetNumFriends() return #Stub.friends.bnet end
C_BattleNet = {
	GetFriendAccountInfo = function(i) return Stub.friends.bnet[i] end,
	GetFriendNumGameAccounts = function(i)
		local a = Stub.friends.bnet[i]
		return a and a.gameAccountInfo and 1 or 0
	end,
	GetFriendGameAccountInfo = function(i) return Stub.friends.bnet[i].gameAccountInfo end,
}

function Stub.Fire(event, ...)
	for _, w in ipairs(Stub.widgets) do
		if w.events and w.events[event] and w.scripts.OnEvent then w.scripts.OnEvent(w, event, ...) end
	end
end

--- Loads every file the TOC lists, as the client would.
function Stub.LoadAddon(dir)
	local SF = {}
	for line in io.lines(dir .. "SpotFriends.toc") do
		line = line:gsub("\r", "")
		if line:match("%.lua$") then
			assert(loadfile(dir .. line))("SpotFriends", SF)
		end
	end
	return SF
end

function Stub.Find(predicate)
	for _, w in ipairs(Stub.widgets) do
		if predicate(w) then return w end
	end
end

function Stub.FindText(text)
	return Stub.Find(function(w)
		return w.kind == "FontString" and type(w.text) == "string" and w.text:find(text, 1, true) ~= nil and Visible(w)
	end)
end

return Stub
