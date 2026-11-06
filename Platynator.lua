-- The icon on nameplates drawn by Platynator.
--
-- Platynator moves Blizzard's UnitFrame off every plate and draws its own display frame there,
-- holding a list of widgets (the unit's name, a health bar, a level text, markers) laid out by the
-- player's chosen design. Nothing is announced to other addons, so the display is found among
-- the plate's children, and the icon sits beside its name text or its bar. The holder is a child
-- of the widget it sits beside, so it takes that widget's scale and shows and hides with it.
-- Only field names are read; Platynator's code is its author's.
local _, SF = ...
local Nameplates, Layout = SF.Nameplates, SF.Layout

local Platynator = { name = "platynator" }
SF.Platynator = Platynator

local Shown, Measure = Nameplates.Shown, Nameplates.Measure

-- What SpotFriends needs of the display's widgets: the name text, the health bar, the level
-- text. Looked up again once Platynator rebuilds the widgets (InitializeWidgets).
local widgetsOf = setmetatable({}, { __mode = "k" })   -- display -> { name, bar, level, list }

local function IsDisplay(child, unit)
	return type(child) == "table" and type(child.widgets) == "table" and child.InitializeWidgets ~= nil
		and child.unit == unit and Shown(child)
end

function Platynator.Find(plate, unit, again)
	if not plate.GetChildren then return nil end
	local ok, children = pcall(function() return { plate:GetChildren() } end)
	if ok then
		for _, child in ipairs(children) do
			if IsDisplay(child, unit) then return child end
		end
	end
	-- Platynator installs its display on the same event; it may simply not be there yet.
	if not again then return nil, "retry" end
	return nil
end

local function Widgets(display)
	local found = widgetsOf[display]
	if found and found.list == display.widgets then return found end
	found = { list = display.widgets }
	for _, w in ipairs(display.widgets) do
		local details = type(w) == "table" and w.details
		local kind = type(details) == "table" and details.kind
		if w.kind == "texts" and kind == "creatureName" and w.text then
			found.name = found.name or w
		elseif w.kind == "texts" and kind == "level" and w.text then
			found.level = found.level or w
		elseif w.kind == "bars" and kind == "health" then
			found.bar = found.bar or w
		end
	end
	widgetsOf[display] = found
	return found
end

local function Forget(display)
	widgetsOf[display] = nil
end

local function OnUnit(display, unit)
	Forget(display)
	Nameplates:OnFrameUnit(display, unit)
end

local function OnWidgets(display)
	Forget(display)
	Nameplates.Reposition(display)
end

local function OnLayout(display)
	Nameplates.Reposition(display)
end

-- The name widget shows only sometimes in a names-only design: the icon follows it (its holder
-- is the widget's child when it sits beside the name, but not when it sits by the bar).
local hookedWidgets = setmetatable({}, { __mode = "k" })

local function HookNameWidget(display)
	local found = Widgets(display)
	local w = found.name
	if not w or hookedWidgets[w] or not w.HookScript then return end
	hookedWidgets[w] = true
	local function Follow() Nameplates.MarkDirty(display) end
	w:HookScript("OnShow", Follow)
	w:HookScript("OnHide", Follow)
end

function Platynator.Hook(display)
	if display.SetUnit then hooksecurefunc(display, "SetUnit", OnUnit) end
	if display.InitializeWidgets then hooksecurefunc(display, "InitializeWidgets", OnWidgets) end
	if display.ApplyPixelPerfectSizing then hooksecurefunc(display, "ApplyPixelPerfectSizing", OnLayout) end
	if display.Install then hooksecurefunc(display, "Install", OnLayout) end
	HookNameWidget(display)
end

local function AnchorOf(w)
	local anchor = w.details and w.details.anchor
	if type(anchor) ~= "table" then return nil, 0, 0 end
	return anchor[1], tonumber(anchor[2]) or 0, tonumber(anchor[3]) or 0
end

local function TextShown(w)
	if not (w and Shown(w) and Shown(w.text)) then return false end
	local text = w.text.GetText and w.text:GetText()
	return text ~= nil and text ~= ""
end

function Platynator.Read(display, s)
	local found = Widgets(display)
	HookNameWidget(display)
	local name, bar, level = found.name, found.bar, found.level
	s.nameShown = TextShown(name)
	s.justify = name and name.text:GetJustifyH() or "CENTER"
	s.textWidth = name and Measure(name.text, "GetStringWidth") or nil
	s.barShown = bar ~= nil and Shown(bar)
	-- A name anchored neither above nor below the display's centre sits inside the bar.
	local point = name and AnchorOf(name)
	local inside = s.barShown and type(point) == "string" and not point:find("TOP") and not point:find("BOTTOM")
	s.style = inside and Layout.INSIDE_BAR or 2
	s.raidShown, s.classShown = false, false
	s.badge, s.badgeWidth, s.badgeJustify = nil, nil, nil
	if level and TextShown(level) and s.barShown then
		local levelPoint, x = AnchorOf(level)
		if (type(levelPoint) == "string" and levelPoint:find("RIGHT")) or x > 0 then
			s.badge = level.text
			s.badgeWidth = Measure(level.text, "GetStringWidth")
			s.badgeJustify = level.text:GetJustifyH()
		end
	end
	return s
end

local function WidgetFor(display, anchorTo)
	local found = Widgets(display)
	if anchorTo == "name" then return found.name end
	if anchorTo == "badge" then return found.level end
	return found.bar
end

function Platynator.Region(display, anchorTo)
	local w = WidgetFor(display, anchorTo)
	if not w then return display end
	if anchorTo == "name" or anchorTo == "badge" then return w.text end
	return w
end

function Platynator.Parent(display, anchorTo)
	return WidgetFor(display, anchorTo) or display
end

function Platynator.Describe(display, s)
	local found = Widgets(display)
	return string.format("widgets: name %s, bar %s, level %s", found.name and "yes" or "no",
		found.bar and "yes" or "no", found.level and "yes" or "no")
end

function Platynator.Dump(plate, display, Describe, names)
	names[display] = "Platynator display"
	local found = Widgets(display)
	names[found.name or false] = "name widget"
	names[found.bar or false] = "bar widget"
	names[found.level or false] = "level widget"
	Describe(display, "Platynator display")
	for i, w in ipairs(display.widgets) do
		local details = type(w) == "table" and w.details or {}
		local point, x, y = AnchorOf(w)
		Describe(w, string.format("widget %d %s/%s at %s(%s,%s)", i, tostring(w.kind), tostring(details.kind),
			tostring(point or "CENTER"), tostring(x), tostring(y)))
		if w.text then Describe(w.text, string.format("widget %d text", i)) end
	end
end

function Platynator:Setup()
	if self.ready then return end
	local addon = _G.Platynator
	if not (type(addon) == "table" and addon.API) then return end
	self.ready = true
	self.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("Platynator", "Version")) or "?"
	Nameplates:AddProvider(self)
	SF.platynator = true
end
