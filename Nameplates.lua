-- The icon on players' nameplates.
--
-- Built for a crowded city: a non-player plate costs one UnitIsPlayer call; a stranger costs a
-- GUID lookup after its first sight; nothing runs per frame. The icon frame (a "holder") is a
-- child of the plate's frame, made the first time that frame shows an icon and reused for every
-- unit it shows afterwards. Positions follow the plate's own re-layouts through hooks, and an
-- anchor is only set again when the answer changes.
--
-- Which frame draws the plate is a "provider's" business: Blizzard's pooled UnitFrame (below), or
-- a nameplate addon's own frame (Platynator.lua). A provider finds the frame for a unit, hooks its
-- re-layouts, reads what it shows for Layout.Plan, and names the region and parent for an anchor.
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

local holders = setmetatable({}, { __mode = "k" })      -- plate frame -> holder
local hooked = setmetatable({}, { __mode = "k" })       -- plate frame -> true
local providerOf = setmetatable({}, { __mode = "k" })   -- plate frame -> provider
local players = {}                                      -- unit token -> plate frame, players on screen
local state, subject = {}, {}                           -- reused for every plate
local providers = {}                                    -- asked in order; the first frame found wins

Nameplates.players, Nameplates.holders, Nameplates.providers = players, holders, providers
Nameplates.errors = 0

local function Report(err)
	Nameplates.errors = Nameplates.errors + 1
	Nameplates.lastError = err
	if Nameplates.errors == 1 then
		SF.Print("a nameplate could not be updated (/spotfriends debug shows why): " .. tostring(err))
	end
end

--------------------------------------------------------------------------------
-- Reading a plate
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

Nameplates.Shown, Nameplates.Measure = Shown, Measure

--------------------------------------------------------------------------------
-- The Blizzard provider: the plate's pooled UnitFrame
--------------------------------------------------------------------------------

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

local function ReadBlizzard(uf, s)
	local name = uf.name
	local container = uf.HealthBarsContainer
	local bar = container and container.healthBar
	s.nameShown = Shown(name)
	s.justify = name and name:GetJustifyH() or "LEFT"
	local width = Measure(name, "GetStringWidth")
	local frameWidth = Measure(name, "GetWidth")
	if width and frameWidth and frameWidth > 0 and frameWidth < width then width = frameWidth end
	s.textWidth = width
	s.barShown = Shown(bar)
	s.style = uf.previewStyle or (NamePlateSetupOptions and NamePlateSetupOptions.unitNameAnchorStyle)
	s.raidShown = Shown(uf.RaidTargetFrame)
	s.classShown = Shown(uf.ClassificationFrame)
	s.badge, s.badgeWidth, s.badgeJustify = nil, nil, "CENTER"
	for _, badge in ipairs(Badges(uf)) do
		if Shown(badge) then
			-- A badge with no anchor is drawn nowhere; one not answering is taken as laid out.
			local points = Measure(badge, "GetNumPoints")
			if points == nil or points > 0 then
				s.badge, s.badgeWidth = badge, BadgeWidth(badge)
				break
			end
		end
	end
	return s
end

local Reposition

local Blizzard = {
	name = "blizzard",
	-- A UnitFrame another addon moved off its plate (Platynator parents it to a hidden frame)
	-- can show nothing.
	Find = function(plate, unit, again)
		local uf = plate.UnitFrame
		if not uf then return nil, "retry" end
		if uf.unit ~= unit and not again then return nil, "retry" end
		if uf.IsForbidden and uf:IsForbidden() then return nil end
		if uf.GetParent and uf:GetParent() ~= plate then return nil end
		return uf
	end,
	Hook = function(uf)
		if uf.UpdateAnchors then hooksecurefunc(uf, "UpdateAnchors", Reposition) end
	end,
	Read = ReadBlizzard,
	Region = function(uf, anchorTo, s)
		if anchorTo == "name" then return uf.name end
		if anchorTo == "badge" then return s.badge end
		if anchorTo == "raid" then return uf.RaidTargetFrame end
		if anchorTo == "class" then return uf.ClassificationFrame end
		return uf.HealthBarsContainer
	end,
	Parent = function(uf) return uf end,
	Describe = function(uf, s)
		return string.format("showOnly %s, simplified %s, badge %s", tostring(uf.showOnlyName),
			tostring(uf.isSimplified), s.badge and (s.badge == uf.LevelFrame and "LevelFrame" or "another frame") or "none")
	end,
}
Nameplates.Blizzard = Blizzard
providers[1] = Blizzard

--- Puts `provider` before Blizzard's: the frame it finds is the one that draws the plate.
function Nameplates:AddProvider(provider)
	for i, known in ipairs(providers) do
		if known == provider then return end
		if known == Blizzard then
			table.insert(providers, i, provider)
			return
		end
	end
	providers[#providers + 1] = provider
end

--------------------------------------------------------------------------------
-- Placing
--------------------------------------------------------------------------------

local function ProviderOf(frame)
	return providerOf[frame] or Blizzard
end

local function Adopt(holder, parent)
	if holder.parent == parent then return end
	holder.parent = parent
	holder:SetParent(parent)
	holder:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 10)
	-- A new parent may be scaled differently: the size is set again in that space.
	if holder.size then holder:SetSize(holder.size, holder.size) end
end

--- Puts `holder` where Layout says, touching its anchor only when the answer changed.
--- Shared with the settings page's preview, which passes a stand-in for the UnitFrame.
function Nameplates.Place(frame, holder, db)
	local provider = ProviderOf(frame)
	local anchorTo, point, relative, x, y = Layout.Plan(provider.Read(frame, state), db.position, db.offsetX, db.offsetY)
	if not anchorTo then
		holder.anchorTo = nil
		holder:Hide()
		return
	end
	local parent = provider.Parent(frame, anchorTo, state)
	if parent and parent ~= holder.parent then
		Adopt(holder, parent)
		holder.anchorTo = nil
	end
	if anchorTo ~= holder.anchorTo or point ~= holder.point or relative ~= holder.relative
		or x ~= holder.x or y ~= holder.y then
		holder:ClearAllPoints()
		holder:SetPoint(point, provider.Region(frame, anchorTo, state), relative, x, y)
		holder.anchorTo, holder.point, holder.relative, holder.x, holder.y = anchorTo, point, relative, x, y
	end
	holder:Show()
end

Reposition = function(frame)
	local holder = holders[frame]
	if holder and holder.active then
		local ok, err = pcall(Nameplates.Place, frame, holder, SF.DB())
		if not ok then Report(err) end
	end
end
Nameplates.Reposition = Reposition

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

local function NewHolder(frame)
	local holder = CreateFrame("Frame", nil, frame)
	holder.parent = frame
	holder:SetFrameLevel(frame:GetFrameLevel() + 10)
	local icon = holder:CreateTexture(nil, "OVERLAY", nil, 7)
	icon:SetAllPoints()
	holder.icon = icon
	holder:Hide()
	holders[frame] = holder
	return holder
end

local function Update(unit)
	local frame = players[unit]
	if not frame then return end
	local db = SF.DB()
	local key
	if db.enabled then
		if SF.testMode then
			key = Icons.Path(db.defaultIcon) and db.defaultIcon or Icons.Default()
		else
			key = Lookup(unit, db)
		end
	end
	local holder = holders[frame]
	if not key then
		if holder and holder.active then
			holder.active = false
			holder:Hide()
		end
		return
	end
	holder = holder or NewHolder(frame)
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
	Nameplates.Place(frame, holder, db)
end

local function SafeUpdate(unit)
	local ok, err = pcall(Update, unit)
	if not ok then Report(err) end
end
Nameplates.SafeUpdate = SafeUpdate

--------------------------------------------------------------------------------
-- Plates coming and going
--------------------------------------------------------------------------------

-- Blizzard's driver (and a nameplate addon) set the plate up on the same event; should this
-- addon hear it first, the plate is looked at again on the next frame.
local pending, pendingQueued = {}, false

local function FindFrame(plate, unit, again)
	local wantRetry = false
	for _, provider in ipairs(providers) do
		local frame, status = provider.Find(plate, unit, again)
		if frame then return frame, provider end
		if status == "retry" then wantRetry = true end
	end
	return nil, nil, wantRetry
end

local function Added(unit, again)
	local plate = GetNamePlateForUnit and GetNamePlateForUnit(unit)
	if not plate then return false end
	if not Known(UnitIsPlayer(unit)) or Known(UnitIsUnit(unit, "player")) then return true end
	local frame, provider, wantRetry = FindFrame(plate, unit, again)
	if not frame then return not (wantRetry and not again) end
	providerOf[frame] = provider
	if not hooked[frame] then
		hooked[frame] = true
		provider.Hook(frame)
	end
	players[unit] = frame
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
	local frame = players[unit]
	if not frame then return end
	players[unit] = nil
	local holder = holders[frame]
	if holder and holder.active then
		holder.active = false
		holder:Hide()
	end
end

--- A provider's frame shows another unit now, or none: the icon follows on the next frame.
function Nameplates:OnFrameUnit(frame, unit)
	for token, known in pairs(players) do
		if known == frame and token ~= unit then self:OnRemoved(token) end
	end
	if unit and not players[unit] then
		pending[unit] = true
		if not pendingQueued then
			pendingQueued = true
			C_Timer.After(0, RunPending)
		end
	end
end

function Nameplates:OnNameChanged(unit)
	if not players[unit] then return end
	Resolver.Forget(UnitGUID(unit))
	SafeUpdate(unit)
end

-- A simplified plate shows its name only while targeted: the old and the new target move, after
-- the plate has been redrawn this frame.
local dirty, dirtyQueued, lastTarget = {}, false, nil

local function RunDirty()
	dirtyQueued = false
	for frame in pairs(dirty) do
		dirty[frame] = nil
		Reposition(frame)
	end
end

local function MarkDirty(frame)
	if not frame or not holders[frame] then return end
	dirty[frame] = true
	if not dirtyQueued then
		dirtyQueued = true
		C_Timer.After(0, RunDirty)
	end
end
Nameplates.MarkDirty = MarkDirty

function Nameplates:OnTargetChanged()
	MarkDirty(lastTarget)
	lastTarget = nil
	for unit, frame in pairs(players) do
		if Known(UnitIsUnit(unit, "target")) then
			lastTarget = frame
			break
		end
	end
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

--------------------------------------------------------------------------------
-- For the debug commands
--------------------------------------------------------------------------------

local function Show(v)
	if v ~= nil and issecretvalue and issecretvalue(v) then return "<secret>" end
	return tostring(v)
end

local function Describe(unit)
	local plate = GetNamePlateForUnit and GetNamePlateForUnit(unit)
	local frame = players[unit]
	local first, second = UnitName(unit)
	local whole = GetUnitName and GetUnitName(unit, true) or nil
	local line = string.format("%s: %s / %s + %s, guid %s, player %s", unit,
		Show(whole), Show(first), Show(second), Show(UnitGUID(unit)), Show(UnitIsPlayer(unit)))
	if not frame then
		local uf = plate and plate.UnitFrame
		if not uf then return line .. ", no unit frame" end
		if uf.IsForbidden and uf:IsForbidden() then return line .. ", forbidden" end
		return line .. ", not tracked"
	end
	local provider = ProviderOf(frame)
	local s = provider.Read(frame, state)
	line = line .. string.format(", %s plate: name %s %s w=%s, bar %s, style %s, %s", provider.name,
		Show(s.nameShown), Show(s.justify), s.textWidth and string.format("%.0f", s.textWidth) or "?",
		Show(s.barShown), Show(s.style), provider.Describe and provider.Describe(frame, s) or "")
	subject.guid = Known(UnitGUID(unit))
	subject.whole, subject.first, subject.second = whole, first, second
	local key, source, record = Resolver.Resolve(SF.DB(), SF.Friends.index, subject)
	line = line .. string.format(", icon %s from %s%s", Show(key), Show(source),
		record and (" (" .. tostring(record.id) .. ")") or "")
	local holder = holders[frame]
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
	local unit = plate and "target"
	if not plate then
		for token in pairs(players) do
			unit, plate = token, GetNamePlateForUnit(token)
			break
		end
	end
	if not plate then return { "no player nameplate: target a player or stand near one" } end
	local uf = plate.UnitFrame
	local names = {}
	if uf then
		for key, value in pairs(uf) do
			if type(value) == "table" and type(key) == "string" then names[value] = key end
		end
		local container = uf.HealthBarsContainer
		if container then
			names[container.healthBar or false] = "HealthBarsContainer.healthBar"
			if container.healthBar then names[container.healthBar.bgTexture or false] = "healthBar.bgTexture" end
		end
		names[uf] = "UnitFrame"
	end
	names[plate] = "NamePlate"
	for _, holder in pairs(holders) do names[holder] = "SpotFriends icon" end
	local whole = Known(GetUnitName and GetUnitName(unit, true))
	local lines = { string.format("the nameplate of %s (%s): its parts, as size and anchors", tostring(whole or "?"), unit) }
	local function Describe(region, label)
		local kind = region.GetObjectType and region:GetObjectType() or "?"
		local parts = { string.format("%s %s %s", label, kind, Shown(region) and "shown" or "hidden") }
		local w, h = Measure(region, "GetWidth"), Measure(region, "GetHeight")
		parts[#parts + 1] = string.format("%sx%s", w and string.format("%.0f", w) or "?", h and string.format("%.0f", h) or "?")
		local scale = Measure(region, "GetScale")
		if scale and scale ~= 1 then parts[#parts + 1] = string.format("scale %.2f", scale) end
		local text = region.GetText and Known(region:GetText())
		if type(text) == "string" and text ~= "" then parts[#parts + 1] = string.format("%q", text) end
		local count = Measure(region, "GetNumPoints") or 0
		for i = 1, count do
			local ok, point, relativeTo, relativePoint, x, y = pcall(region.GetPoint, region, i)
			if ok then
				parts[#parts + 1] = string.format("%s>%s.%s(%s,%s)", tostring(point),
					relativeTo and (names[relativeTo] or "?") or "nil",
					tostring(relativePoint), tostring(Number(x) or "?"), tostring(Number(y) or "?"))
			end
		end
		lines[#lines + 1] = table.concat(parts, " ")
	end
	local function Each(prefix, ...)
		for i = 1, select("#", ...) do
			local region = select(i, ...)
			Describe(region, prefix .. (names[region] or ("#" .. i)))
		end
	end
	local frame = players[unit]
	local provider = frame and providerOf[frame]
	if provider and provider.Dump then
		provider.Dump(plate, frame, Describe, names)
	elseif uf then
		Each("", uf:GetChildren())
		Each("region ", uf:GetRegions())
		if type(uf.LevelFrame) == "table" then
			Each("LevelFrame/", uf.LevelFrame:GetRegions())
			Each("LevelFrame/", uf.LevelFrame:GetChildren())
		end
	else
		lines[#lines + 1] = "the plate has no UnitFrame and no tracked frame"
	end
	return lines
end
