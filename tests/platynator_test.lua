-- Nameplates.lua and Platynator.lua against stand-ins for Platynator's plates: a display frame
-- among the plate's children with a list of widgets, Blizzard's UnitFrame moved off the plate.
local Expect = dofile(ADDON_DIR .. "tests/expect.lua")
local Equal, True = Expect.Equal, Expect.True

local calls = { CreateFrame = 0, SetParent = 0 }

local function Region(fields)
	local r = { shown = true, width = 100, frameWidth = 200, justify = "CENTER", level = 500, scripts = {} }
	for k, v in pairs(fields or {}) do r[k] = v end
	function r:IsShown() return self.shown end
	function r:Show()
		self.shown = true
		for _, fn in ipairs(self.scripts.OnShow or {}) do fn(self) end
	end
	function r:Hide()
		self.shown = false
		for _, fn in ipairs(self.scripts.OnHide or {}) do fn(self) end
	end
	function r:HookScript(name, fn)
		self.scripts[name] = self.scripts[name] or {}
		table.insert(self.scripts[name], fn)
	end
	function r:GetStringWidth() return self.width end
	function r:GetWidth() return self.frameWidth end
	function r:GetJustifyH() return self.justify end
	function r:GetText() return self.textValue or "Fizzle Sprockettorque" end
	function r:GetFrameLevel() return self.level end
	function r:GetParent() return self.parent end
	function r:GetChildren() return unpack(self.children or {}) end
	function r:GetNumPoints() return 1 end
	for _, method in ipairs({ "GetLeft", "GetRight", "GetTop", "GetBottom", "GetCenter", "GetRect" }) do
		r[method] = function() error("Action[FrameMeasurement] failed because[Can't measure restricted regions]") end
	end
	return r
end

local function NewFrame(_, _, parent)
	calls.CreateFrame = calls.CreateFrame + 1
	local f = Region({ shown = true, parent = parent })
	function f:SetFrameLevel(level) self.level = level end
	function f:SetParent(parent)
		calls.SetParent = calls.SetParent + 1
		self.parent = parent
	end
	function f:SetSize(w) self.size = w end
	function f:ClearAllPoints() self.anchor = nil end
	function f:SetPoint(...) self.anchor = { ... } end
	function f:CreateTexture()
		local t = {}
		function t:SetAllPoints() end
		function t:SetTexture(path) self.path = path end
		return t
	end
	return f
end

-- Platynator's widgets: a 1x1 holder with the FontString at `text`, or a bar frame.
local function TextWidget(kind, anchor, align, fields)
	local w = Region({ kind = "texts", details = { kind = kind, anchor = anchor, align = align } })
	w.text = Region(fields or {})
	w.text.justify = align or "CENTER"
	return w
end

local function BarWidget()
	local w = Region({ kind = "bars", details = { kind = "health", anchor = {} } })
	w.statusBar = Region()
	return w
end

local function Display(unit, widgets)
	local d = Region({ widgets = widgets, unit = unit, installs = 0 })
	function d:InitializeWidgets() end
	function d:SetUnit(u) self.unit = u end
	function d:Install() self.installs = self.installs + 1 end
	function d:ApplyPixelPerfectSizing() end
	return d
end

local hiddenFrame = Region({ shown = false })
local units, plates = {}, {}

local function Plate(unit, fields, display)
	units[unit] = fields
	local plate = Region()
	local uf = Region({ unit = unit, parent = hiddenFrame })   -- moved off the plate by Platynator
	uf.name = Region()
	plate.UnitFrame = uf
	local click = Region({ visual = Region() })
	plate.children = { click, uf.WidgetContainer or Region(), display }
	plates[unit] = plate
	return plate
end

C_NamePlate = { GetNamePlateForUnit = function(unit) return plates[unit] end, GetNamePlates = function() return {} end }
UnitIsPlayer = function(unit) return units[unit] and units[unit].player end
UnitIsUnit = function(a, b) return a == b end
UnitGUID = function(unit) return units[unit] and units[unit].guid end
UnitName = function(unit) local u = units[unit]; return u and u.first, u and u.second end
GetUnitName = function(unit) local u = units[unit]; return u and (u.first .. " " .. u.second) end
CreateFrame = NewFrame
local hooks = {}
hooksecurefunc = function(target, name, fn)
	local original = target[name]
	target[name] = function(...)
		local a = original(...)
		fn(...)
		return a
	end
	hooks[#hooks + 1] = name
end
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers()
	local due = timers
	timers = {}
	for _, fn in ipairs(due) do fn() end
end
UNKNOWNOBJECT = "Unknown"
Platynator = { API = {} }
C_AddOns = { GetAddOnMetadata = function() return "541" end }

local SF = {
	Icons = Expect.Load("Icons.lua"), Resolver = Expect.Load("Resolver.lua"), Layout = Expect.Load("Layout.lua"),
	Print = function() end,
}
local db = { enabled = true, defaultIcon = "gold-spot", position = "left", size = 14, offsetX = 0, offsetY = 0,
	friends = { bnet = {}, ingame = {} }, characters = {}, group = { enabled = false } }
SF.DB = function() return db end
SF.Friends = { index = SF.Resolver.BuildIndex({ bnet = {
	{ kind = "bnet", id = "Fiz#1", characters = { { name = "Fizzle Sprockettorque", guid = "Player-1-FIZ" } } },
	{ kind = "bnet", id = "Bob#2", characters = { { name = "Bob Nimblegear", guid = "Player-1-BOB" } } },
}, ingame = {} }) }
assert(loadfile(ADDON_DIR .. "Nameplates.lua"))("SpotFriends", SF)
assert(loadfile(ADDON_DIR .. "Platynator.lua"))("SpotFriends", SF)
local Nameplates = SF.Nameplates
Nameplates.started = true
SF.Platynator:Setup()
True(SF.platynator, "Platynator recognised")
Equal(Nameplates.providers[1], SF.Platynator, "asked before Blizzard's frames")
local GAP = SF.Layout.GAP

-- A names-only design: the centred name alone.
local name = TextWidget("creatureName", { "BOTTOM", 0, 0 }, "CENTER", { width = 90 })
local display = Display("nameplate1", { name })
Plate("nameplate1", { player = true, guid = "Player-1-FIZ", first = "Fizzle", second = "Sprockettorque" }, display)
Nameplates:OnAdded("nameplate1")
local holder = Nameplates.holders[display]
True(holder ~= nil and holder:IsShown(), "the icon is on Platynator's display")
Equal(holder.parent, name, "a child of the name widget, taking its scale")
Equal(holder.anchor[2], name.text, "anchored to the name text")
Equal(holder.anchor[3], "CENTER", "from the centred text")
Equal(holder.anchor[4], -(45 + GAP), "before its left edge")
Equal(Nameplates.holders[plates.nameplate1.UnitFrame], nil, "nothing under Blizzard's moved frame")
db.position = "right"
Nameplates:RefreshAll()
Equal(holder.anchor[1], "LEFT", "right: after the text")
Equal(holder.anchor[4], 45 + GAP, "past its right edge")
True(hooks[1] ~= nil, "the display is hooked")

-- The names-only design shows the name only sometimes: the icon follows the widget.
name:Hide()
RunTimers()
True(not holder:IsShown(), "no name, no bar: hidden")
name:Show()
RunTimers()
True(holder:IsShown(), "shown with the name")

-- A design with a bar and the name above it, then a level text at the bar's right end.
local name2 = TextWidget("creatureName", { "BOTTOM", 0, 8 }, "CENTER", { width = 120 })
local bar = BarWidget()
local display2 = Display("nameplate2", { bar, name2 })
Plate("nameplate2", { player = true, guid = "Player-1-BOB", first = "Bob", second = "Nimblegear" }, display2)
Nameplates:OnAdded("nameplate2")
local holder2 = Nameplates.holders[display2]
Equal(holder2.parent, bar, "right with a bar: a child of the bar widget")
Equal(holder2.anchor[2], bar, "after the bar")
Equal(holder2.anchor[3], "RIGHT", "its right edge")
db.position = "left"
Nameplates:RefreshAll()
Equal(holder2.parent, name2, "left: back under the name widget")
Equal(holder2.anchor[4], -(60 + GAP), "before the name")
db.position = "right"
local level = TextWidget("level", { "RIGHT", 86, 0 }, "RIGHT", { width = 14, textValue = "15" })
display2.widgets = { bar, name2, level }
display2:InitializeWidgets()
Equal(holder2.anchor[2], level.text, "after the level text at the bar's right end")
Equal(holder2.anchor[3], "RIGHT", "from its right edge, as it is right-justified")
Equal(holder2.anchor[4], GAP, "just past it")
Equal(holder2.parent, level, "a child of the level widget")
level.details.anchor = { "LEFT", -40, 0 }
display2:InitializeWidgets()
Equal(holder2.anchor[2], bar, "a level text on the left is no badge")

-- A design with the name inside the bar: left goes before the text.
local name3 = TextWidget("creatureName", { "LEFT", -59, 0 }, "LEFT", { width = 70 })
local display3 = Display("nameplate3", { BarWidget(), name3 })
Plate("nameplate3", { player = true, guid = "Player-1-FIZ", first = "Fizzle", second = "Sprockettorque" }, display3)
db.position = "left"
Nameplates:OnAdded("nameplate3")
local holder3 = Nameplates.holders[display3]
Equal(holder3.anchor[2], name3.text, "name inside the bar: before the text")
Equal(holder3.anchor[3], "LEFT", "its left edge")

-- A simplified design, no name: beside the bar.
local bar4 = BarWidget()
local display4 = Display("nameplate4", { bar4 })
Plate("nameplate4", { player = true, guid = "Player-1-BOB", first = "Bob", second = "Nimblegear" }, display4)
Nameplates:OnAdded("nameplate4")
local holder4 = Nameplates.holders[display4]
Equal(holder4.anchor[2], bar4, "no name: by the bar")
Equal(holder4.anchor[1], "RIGHT", "before it on the left")

-- The display is not there yet when the plate is announced: found on the retry.
local name5 = TextWidget("creatureName", { "BOTTOM", 0, 0 }, "CENTER")
local display5 = Display("nameplate5", { name5 })
local plate5 = Plate("nameplate5", { player = true, guid = "Player-1-FIZ", first = "Fizzle", second = "Sprockettorque" }, display5)
plate5.children = { plate5.UnitFrame }
Nameplates:OnAdded("nameplate5")
Equal(Nameplates.holders[display5], nil, "not found at once")
plate5.children = { plate5.UnitFrame, display5 }
RunTimers()
True(Nameplates.holders[display5] ~= nil and Nameplates.holders[display5]:IsShown(), "found on the retry")

-- The display changes unit (Platynator pools them), then shows none.
display5:SetUnit("nameplate6")
units.nameplate6 = { player = true, guid = "Player-9-STR", first = "Stranger", second = "Danger" }
plates.nameplate6 = plate5
display5.unit = "nameplate6"
RunTimers()
True(not Nameplates.holders[display5]:IsShown(), "a stranger on the same display: hidden")
Equal(Nameplates.players.nameplate5, nil, "the old unit forgotten")
display5:SetUnit(nil)
RunTimers()
True(not Nameplates.holders[display5]:IsShown(), "no unit: hidden")

-- A plate Platynator skipped keeps Blizzard's frame on the plate: the Blizzard provider.
local plate7 = Region()
local uf7 = Region({ unit = "nameplate7", parent = plate7 })
uf7.name = Region({ justify = "LEFT", width = 80 })
uf7.HealthBarsContainer = Region()
uf7.HealthBarsContainer.healthBar = Region()
plate7.UnitFrame = uf7
plate7.children = { uf7 }
plates.nameplate7 = plate7
units.nameplate7 = { player = true, guid = "Player-1-FIZ", first = "Fizzle", second = "Sprockettorque" }
Nameplates:OnAdded("nameplate7")
RunTimers()
local holder7 = Nameplates.holders[uf7]
True(holder7 ~= nil and holder7:IsShown(), "Blizzard's frame when Platynator left the plate alone")
Equal(holder7.anchor[2], uf7.name, "before the name")

-- NPCs and strangers cost nothing.
local before = calls.CreateFrame
Plate("nameplate8", { player = false, guid = "Creature-1", first = "Boar" }, Display("nameplate8", {}))
Nameplates:OnAdded("nameplate8")
Equal(calls.CreateFrame, before, "an NPC makes no frame")

Equal(Nameplates.errors, 0, "no errors")
True(Nameplates:Describe("nameplate1"):find("platynator plate", 1, true) ~= nil, "debug names the provider")
Expect.Done("platynator")
