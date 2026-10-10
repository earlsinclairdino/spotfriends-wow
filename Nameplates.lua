-- The icon on players' nameplates.
--
-- Built for a crowded city: a non-player plate costs one UnitIsPlayer call; a stranger costs a
-- GUID lookup after its first sight; nothing runs per frame. The icon frame (a "holder") is a
-- child of the plate's pooled UnitFrame, made the first time that UnitFrame shows an icon and
-- reused for every unit it shows afterwards. Positions follow Blizzard's own re-layouts through
-- hooks, and an anchor is only set again when the answer changes.
local _, SF = ...
local Resolver, Layout, Icons = SF.Resolver, SF.Layout, SF.Icons

local Nameplates = {}
SF.Nameplates = Nameplates

local Known = Resolver.Known
local GetNamePlateForUnit = C_NamePlate and C_NamePlate.GetNamePlateForUnit
local GetNamePlates = C_NamePlate and C_NamePlate.GetNamePlates
local UnitIsPlayer, UnitIsUnit, UnitGUID, UnitName = UnitIsPlayer, UnitIsUnit, UnitGUID, UnitName
local GetUnitName = GetUnitName
local pcall, pairs = pcall, pairs

local holders = setmetatable({}, { __mode = "k" })   -- UnitFrame -> holder
local hooked = setmetatable({}, { __mode = "k" })    -- UnitFrame -> true
local players = {}                                   -- unit token -> UnitFrame, players on screen
local state, subject = {}, {}                        -- reused for every plate

Nameplates.players, Nameplates.holders = players, holders
Nameplates.errors = 0

local function Report(err)
	Nameplates.errors = Nameplates.errors + 1
	Nameplates.lastError = err
	if Nameplates.errors == 1 then
		SF.Print("a nameplate could not be updated (/spotfriends debug shows why): " .. tostring(err))
	end
end

--------------------------------------------------------------------------------
-- Placing
--------------------------------------------------------------------------------

local function Number(value)
	value = Known(value)
	return type(value) == "number" and value or nil
end

local function Shown(region)
	return type(region) == "table" and region:IsShown() and true or false
end

-- Midnight refuses to tell an addon where a nameplate is on screen: GetLeft, GetRight, GetCenter
-- and the like raise "Can't measure restricted regions" on its regions. So placement never asks
-- for a position, only for what is shown, the name's width and whether a region is laid out,
-- each through a pcall in case the client restricts those too.
local function Measure(region, method)
	if type(region) ~= "table" or not region[method] then return nil end
	local ok, value = pcall(region[method], region)
	if not ok then return nil end
	return Number(value)
end

-- The level badge at the bar's right end. Its frame can be narrower than its art (Forever's
-- "13" badge drew past the frame's right edge, and an icon after that edge sat on the badge), so
-- the icon is placed from the badge's centre by its widest shown part. Mainline lays out
-- LevelFrame; should Forever draw the badge on another frame, it is the shown child hanging off
-- the bar's right side. Found once per pooled UnitFrame, as anchors, never positions.
local badges = setmetatable({}, { __mode = "k" })   -- UnitFrame -> { candidate regions }

local function HangsRightOfBar(region, container)
	local ok, count = pcall(region.GetNumPoints, region)
	if not ok or type(count) ~= "number" then return false end
	local bar = container.healthBar
	for i = 1, count do
		local got, point, relativeTo, relativePoint = pcall(region.GetPoint, region, i)
		if got and type(point) == "string" and type(relativePoint) == "string"
			and (relativeTo == container or relativeTo == bar or (bar and relativeTo == bar.bgTexture))
			and relativePoint:find("RIGHT") and not point:find("RIGHT") then
			return true
		end
	end
	return false
end

local function Badges(uf)
	local list = badges[uf]
	if list then return list end
	list = {}
	if type(uf.LevelFrame) == "table" then list[1] = uf.LevelFrame end
	local container = uf.HealthBarsContainer
	if type(container) == "table" and uf.GetChildren then
		local ok, children = pcall(function() return { uf:GetChildren() } end)
		for _, child in ipairs(ok and children or {}) do
			if child ~= uf.LevelFrame and child ~= container and child ~= holders[uf]
				and HangsRightOfBar(child, container) then
				list[#list + 1] = child
			end
		end
	end
	badges[uf] = list
	return list
end

local function Widest(width, ...)
	for i = 1, select("#", ...) do
		local region = select(i, ...)
		if Shown(region) then
			local w = Measure(region, "GetWidth")
			if w and w > width then width = w end
		end
	end
	return width
end

local function BadgeWidth(badge)
	local width = Measure(badge, "GetWidth") or 0
	if badge.GetRegions then width = Widest(width, badge:GetRegions()) end
	if badge.GetChildren then width = Widest(width, badge:GetChildren()) end
	return width > 0 and width or nil
end

local function ReadState(uf)
	local name = uf.name
	local container = uf.HealthBarsContainer
	local bar = container and container.healthBar
	state.nameShown = Shown(name)
	state.justify = name and name:GetJustifyH() or "LEFT"
	local width = Measure(name, "GetStringWidth")
	local frameWidth = Measure(name, "GetWidth")
	if width and frameWidth and frameWidth > 0 and frameWidth < width then width = frameWidth end
	state.textWidth = width
	state.barShown = Shown(bar)
	state.style = uf.previewStyle or (NamePlateSetupOptions and NamePlateSetupOptions.unitNameAnchorStyle)
	state.raidShown = Shown(uf.RaidTargetFrame)
	state.classShown = Shown(uf.ClassificationFrame)
	state.badge, state.badgeWidth = nil, nil
	for _, badge in ipairs(Badges(uf)) do
		if Shown(badge) then
			-- A badge with no anchor is drawn nowhere; one not answering is taken as laid out.
			local points = Measure(badge, "GetNumPoints")
			if points == nil or points > 0 then
				state.badge, state.badgeWidth = badge, BadgeWidth(badge)
				break
			end
		end
	end
	return state
end

local function Region(uf, anchorTo)
	if anchorTo == "name" then return uf.name end
	if anchorTo == "badge" then return state.badge end
	if anchorTo == "raid" then return uf.RaidTargetFrame end
	if anchorTo == "class" then return uf.ClassificationFrame end
	return uf.HealthBarsContainer
end

--- Puts `holder` where Layout says, touching its anchor only when the answer changed.
--- Shared with the settings page's preview, which passes a stand-in for the UnitFrame.
function Nameplates.Place(uf, holder, db)
	local anchorTo, point, relative, x, y = Layout.Plan(ReadState(uf), db.position, db.offsetX, db.offsetY)
	if not anchorTo then
		holder.anchorTo = nil
		holder:Hide()
		return
	end
	if anchorTo ~= holder.anchorTo or point ~= holder.point or relative ~= holder.relative
		or x ~= holder.x or y ~= holder.y then
		holder:ClearAllPoints()
		holder:SetPoint(point, Region(uf, anchorTo), relative, x, y)
		holder.anchorTo, holder.point, holder.relative, holder.x, holder.y = anchorTo, point, relative, x, y
	end
	holder:Show()
end

local function Reposition(uf)
	local holder = holders[uf]
	if holder and holder.active then
		local ok, err = pcall(Nameplates.Place, uf, holder, SF.DB())
		if not ok then Report(err) end
	end
end

--------------------------------------------------------------------------------
-- Which icon
--------------------------------------------------------------------------------

local function Lookup(unit, db)
	local guid = Known(UnitGUID(unit))
	if guid then
		local cached = Resolver.Cached(guid)
		if cached ~= nil then return cached or nil end
	end
	subject.guid = guid
	subject.whole = GetUnitName and GetUnitName(unit, true) or nil
	subject.first, subject.second = UnitName(unit)
	local key = Resolver.Resolve(db, SF.Friends.index, subject)
	-- A name the client has not loaded yet reads "Unknown": remembering that answer would miss
	-- a friend until the next change. UNIT_NAME_UPDATE brings the real one.
	local first = Known(subject.first)
	if guid and first and first ~= UNKNOWNOBJECT then Resolver.Remember(guid, key) end
	return key
end

local function NewHolder(uf)
	local holder = CreateFrame("Frame", nil, uf)
	holder:SetFrameLevel(uf:GetFrameLevel() + 10)
	local icon = holder:CreateTexture(nil, "OVERLAY")
	icon:SetAllPoints()
	holder.icon = icon
	holder:Hide()
	holders[uf] = holder
	return holder
end

local function Update(unit)
	local uf = players[unit]
	if not uf then return end
	local db = SF.DB()
	local key
	if db.enabled then
		if SF.testMode then
			key = Icons.Path(db.defaultIcon) and db.defaultIcon or Icons.Default()
		else
			key = Lookup(unit, db)
		end
	end
	local holder = holders[uf]
	if not key then
		if holder and holder.active then
			holder.active = false
			holder:Hide()
		end
		return
	end
	holder = holder or NewHolder(uf)
	if holder.key ~= key then
		holder.key = key
		holder.icon:SetTexture(Icons.Path(key) or Icons.Path(Icons.Default()))
	end
	if holder.size ~= db.size then
		holder.size = db.size
		holder:SetSize(db.size, db.size)
	end
	holder.unit = unit
	holder.active = true
	Nameplates.Place(uf, holder, db)
end

local function SafeUpdate(unit)
	local ok, err = pcall(Update, unit)
	if not ok then Report(err) end
end

--------------------------------------------------------------------------------
-- Plates coming and going
--------------------------------------------------------------------------------

local OnAnchors = function(uf) Reposition(uf) end

-- Blizzard's driver acquires the UnitFrame on the same event; should this addon hear it first,
-- the plate is looked at again on the next frame.
local pending, pendingQueued = {}, false

local function Added(unit, again)
	local plate = GetNamePlateForUnit and GetNamePlateForUnit(unit)
	local uf = plate and plate.UnitFrame
	if not uf then return false end
	if uf.unit ~= unit and not again then return false end
	if uf.IsForbidden and uf:IsForbidden() then return true end
	if not Known(UnitIsPlayer(unit)) or Known(UnitIsUnit(unit, "player")) then return true end
	if not hooked[uf] and uf.UpdateAnchors then
		hooked[uf] = true
		hooksecurefunc(uf, "UpdateAnchors", OnAnchors)
	end
	players[unit] = uf
	SafeUpdate(unit)
	return true
end

local function RunPending()
	pendingQueued = false
	for unit in pairs(pending) do
		pending[unit] = nil
		local ok, err = pcall(Added, unit, true)
		if not ok then Report(err) end
	end
end

function Nameplates:OnAdded(unit)
	local ok, done = pcall(Added, unit)
	if not ok then
		Report(done)
	elseif not done then
		pending[unit] = true
		if not pendingQueued then
			pendingQueued = true
			C_Timer.After(0, RunPending)
		end
	end
end

function Nameplates:OnRemoved(unit)
	pending[unit] = nil
	local uf = players[unit]
	if not uf then return end
	players[unit] = nil
	local holder = holders[uf]
	if holder and holder.active then
		holder.active = false
		holder:Hide()
	end
end

function Nameplates:OnNameChanged(unit)
	if not players[unit] then return end
	Resolver.Forget(UnitGUID(unit))
	SafeUpdate(unit)
end

-- A simplified plate shows its name only while targeted: the old and the new target move, after
-- Blizzard has redrawn them this frame.
local dirty, dirtyQueued, lastTarget = {}, false, nil

local function RunDirty()
	dirtyQueued = false
	for uf in pairs(dirty) do
		dirty[uf] = nil
		Reposition(uf)
	end
end

local function MarkDirty(uf)
	if not uf or not holders[uf] then return end
	dirty[uf] = true
	if not dirtyQueued then
		dirtyQueued = true
		C_Timer.After(0, RunDirty)
	end
end

function Nameplates:OnTargetChanged()
	MarkDirty(lastTarget)
	local plate = GetNamePlateForUnit and GetNamePlateForUnit("target")
	lastTarget = plate and plate.UnitFrame or nil
	MarkDirty(lastTarget)
end

--------------------------------------------------------------------------------
-- Everything again
--------------------------------------------------------------------------------

function Nameplates:RefreshAll()
	for unit in pairs(players) do SafeUpdate(unit) end
end

local refreshQueued = false
local function RunRefresh()
	refreshQueued = false
	Nameplates:RefreshAll()
end

function Nameplates:RefreshSoon()
	if refreshQueued or not self.started then return end
	refreshQueued = true
	C_Timer.After(0, RunRefresh)
end

--- Picks up the plates already on screen (after a /reload, or a loading screen).
function Nameplates:Rescan()
	for unit in pairs(players) do self:OnRemoved(unit) end
	if not GetNamePlates then return end
	local ok, plates = pcall(GetNamePlates)
	if not ok or type(plates) ~= "table" then return end
	for _, plate in ipairs(plates) do
		local uf = plate.UnitFrame
		local unit = plate.namePlateUnitToken or (plate.GetUnit and plate:GetUnit()) or (uf and uf.unit)
		if unit then self:OnAdded(unit) end
	end
end

Nameplates.CVARS = {
	nameplateShowOnlyNameForFriendlyPlayerUnits = true,
	nameplateSimplifiedTypes = true,
	nameplateShowFriendlyPlayers = true,
	nameplateShowFriends = true,
	nameplateShowOnlyNames = true,
	nameplateStyle = true,
	nameplateSize = true,
}

function Nameplates:OnCVar(name)
	if self.CVARS[name] then self:RefreshSoon() end
end

function Nameplates:Start()
	if self.started then return end
	self.started = true
	if CompactUnitFrame_UpdateName then
		hooksecurefunc("CompactUnitFrame_UpdateName", Reposition)
	end
	self:Rescan()
end

function Nameplates:HolderCount()
	local count, active = 0, 0
	for _, holder in pairs(holders) do
		count = count + 1
		if holder.active then active = active + 1 end
	end
	return count, active
end

local function Show(v)
	if v ~= nil and issecretvalue and issecretvalue(v) then return "<secret>" end
	return tostring(v)
end

local function Describe(unit)
	local plate = GetNamePlateForUnit and GetNamePlateForUnit(unit)
	local uf = players[unit] or (plate and plate.UnitFrame)
	local first, second = UnitName(unit)
	local whole = GetUnitName and GetUnitName(unit, true) or nil
	local line = string.format("%s: %s / %s + %s, guid %s, player %s", unit,
		Show(whole), Show(first), Show(second), Show(UnitGUID(unit)), Show(UnitIsPlayer(unit)))
	if not uf then return line .. ", no unit frame" end
	if uf.IsForbidden and uf:IsForbidden() then return line .. ", forbidden" end
	local s = ReadState(uf)
	line = line .. string.format(", showOnly %s, simplified %s, name %s %s w=%s, bar %s, badge %s, style %s",
		Show(uf.showOnlyName), Show(uf.isSimplified), Show(s.nameShown), Show(s.justify),
		s.textWidth and string.format("%.0f", s.textWidth) or "?", Show(s.barShown),
		s.badge and ((s.badge == uf.LevelFrame and "LevelFrame" or "another frame")
			.. (s.badgeWidth and string.format(" w=%.0f", s.badgeWidth) or "")) or "none", Show(s.style))
	subject.guid = Known(UnitGUID(unit))
	subject.whole, subject.first, subject.second = whole, first, second
	local key, source, record = Resolver.Resolve(SF.DB(), SF.Friends.index, subject)
	line = line .. string.format(", icon %s from %s%s", Show(key), Show(source),
		record and (" (" .. tostring(record.id) .. ")") or "")
	local holder = holders[uf]
	if holder then
		line = line .. string.format(", holder %s at %s %s %s", holder:IsShown() and "shown" or "hidden",
			tostring(holder.anchorTo), tostring(holder.relative), holder.x and string.format("%.1f", holder.x) or "")
	end
	return line
end

--- What the debug command prints for one plate.
function Nameplates:Describe(unit)
	local ok, line = pcall(Describe, unit)
	if ok then return line end
	return tostring(unit) .. ": could not be described: " .. tostring(line)
end

--- The parts of one player's nameplate, as anchors and sizes (positions are refused): for
--- finding which frame draws something when the placement guesses wrong. The target's plate,
--- else the first player plate on screen.
function Nameplates:Dump()
	local plate = GetNamePlateForUnit and GetNamePlateForUnit("target")
	local uf, unit = plate and plate.UnitFrame, "target"
	if not uf then
		for token, candidate in pairs(players) do uf, unit = candidate, token; break end
	end
	if not uf then return { "no player nameplate: target a player or stand near one" } end
	local names = {}
	for key, value in pairs(uf) do
		if type(value) == "table" and type(key) == "string" then names[value] = key end
	end
	local container = uf.HealthBarsContainer
	if container then
		names[container.healthBar or false] = "HealthBarsContainer.healthBar"
		if container.healthBar then names[container.healthBar.bgTexture or false] = "healthBar.bgTexture" end
	end
	if holders[uf] then names[holders[uf]] = "SpotFriends icon" end
	local whole = Known(GetUnitName and GetUnitName(unit, true))
	local lines = { string.format("the nameplate of %s (%s): its parts, as size and anchors", tostring(whole or "?"), unit) }
	local function Describe(region, label)
		local kind = region.GetObjectType and region:GetObjectType() or "?"
		local parts = { string.format("%s %s %s", label, kind, Shown(region) and "shown" or "hidden") }
		local w, h = Measure(region, "GetWidth"), Measure(region, "GetHeight")
		parts[#parts + 1] = string.format("%sx%s", w and string.format("%.0f", w) or "?", h and string.format("%.0f", h) or "?")
		local text = region.GetText and Known(region:GetText())
		if type(text) == "string" and text ~= "" then parts[#parts + 1] = string.format("%q", text) end
		local count = Measure(region, "GetNumPoints") or 0
		for i = 1, count do
			local ok, point, relativeTo, relativePoint, x, y = pcall(region.GetPoint, region, i)
			if ok then
				parts[#parts + 1] = string.format("%s>%s.%s(%s,%s)", tostring(point),
					relativeTo and (names[relativeTo] or (relativeTo == uf and "UnitFrame") or "?") or "nil",
					tostring(relativePoint), tostring(Number(x) or "?"), tostring(Number(y) or "?"))
			end
		end
		lines[#lines + 1] = table.concat(parts, " ")
	end
	local function Each(owner, prefix, ...)
		for i = 1, select("#", ...) do
			local region = select(i, ...)
			Describe(region, prefix .. (names[region] or ("#" .. i)))
		end
	end
	Each(uf, "", uf:GetChildren())
	Each(uf, "region ", uf:GetRegions())
	if type(uf.LevelFrame) == "table" then
		Each(uf.LevelFrame, "LevelFrame/", uf.LevelFrame:GetRegions())
		Each(uf.LevelFrame, "LevelFrame/", uf.LevelFrame:GetChildren())
	end
	return lines
end
