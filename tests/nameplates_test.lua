-- Nameplates.lua against stand-ins for the client's frames and unit functions. Checks what a
-- crowded city needs: NPCs and strangers create nothing, a friend's icon is set once, and an
-- anchor is not set again while the plate looks the same.
local Expect = dofile(ADDON_DIR .. "tests/expect.lua")
local Equal = Expect.Equal

local calls = { SetPoint = 0, SetTexture = 0, CreateFrame = 0, UnitName = 0, hooks = 0 }

local function Region(fields)
	local r = { shown = true, width = 100, frameWidth = 200, justify = "LEFT", right = 300 }
	for k, v in pairs(fields or {}) do r[k] = v end
	function r:IsShown() return self.shown end
	function r:Show() self.shown = true end
	function r:Hide() self.shown = false end
	function r:GetStringWidth() return self.width end
	function r:GetWidth() return self.frameWidth end
	function r:GetJustifyH() return self.justify end
	-- The client refuses an addon any nameplate position.
	for _, method in ipairs({ "GetLeft", "GetRight", "GetTop", "GetBottom", "GetCenter", "GetRect" }) do
		r[method] = function() error("Frame:GetRight(): Action[FrameMeasurement] failed because[Can't measure restricted regions]") end
	end
	function r:GetNumPoints() return self.points or (self.anchors and #self.anchors) or 1 end
	function r:GetPoint(i) return unpack(self.anchors and self.anchors[i] or {}) end
	function r:GetRegions() return unpack(self.regions or {}) end
	function r:GetChildren() return unpack(self.children or {}) end
	function r:GetFrameLevel() return 5 end
	return r
end

local function NewFrame()
	calls.CreateFrame = calls.CreateFrame + 1
	local f = Region({ shown = true })
	function f:SetFrameLevel() end
	function f:SetSize(w) self.size = w end
	function f:ClearAllPoints() self.anchor = nil end
	function f:SetPoint(...)
		calls.SetPoint = calls.SetPoint + 1
		self.anchor = { ... }
	end
	function f:CreateTexture()
		local t = {}
		function t:SetAllPoints() end
		function t:SetTexture(path)
			calls.SetTexture = calls.SetTexture + 1
			self.path = path
		end
		return t
	end
	return f
end

local function UnitFrame(unit)
	local uf = Region()
	uf.unit = unit
	uf.name = Region()
	uf.HealthBarsContainer = Region({ right = 300 })
	uf.HealthBarsContainer.healthBar = Region()
	-- Mainline's 15-pixel level frame with art wider than itself, as Forever draws its badge.
	uf.LevelFrame = Region({ shown = false, frameWidth = 15, regions = { Region({ frameWidth = 28 }) } })
	-- Another frame hanging off the bar's right side, in case the badge is not LevelFrame.
	uf.OtherBadge = Region({ shown = false, frameWidth = 20,
		anchors = { { "LEFT", uf.HealthBarsContainer, "RIGHT", 4, 0 } } })
	-- And one inside the bar, which is not a badge.
	uf.Inside = Region({ shown = true, anchors = { { "RIGHT", uf.HealthBarsContainer, "RIGHT", -4, 0 } } })
	uf.children = { uf.HealthBarsContainer, uf.LevelFrame, uf.OtherBadge, uf.Inside }
	uf.RaidTargetFrame = Region({ shown = false })
	uf.ClassificationFrame = Region({ shown = false })
	function uf:IsForbidden() return false end
	function uf:UpdateAnchors() end
	return uf
end

-- The world: three plates, an NPC, a stranger and a friend.
local units = {
	nameplate1 = { player = false, guid = "Creature-0-1", first = "Boar" },
	nameplate2 = { player = true, guid = "Player-1-STR", first = "Stranger", second = "Danger" },
	nameplate3 = { player = true, guid = "Player-1-XAN", first = "Xanduin", second = "Laszwyn" },
}
local plates = {}
for unit in pairs(units) do plates[unit] = { UnitFrame = UnitFrame(unit) } end

C_NamePlate = { GetNamePlateForUnit = function(unit) return plates[unit] end, GetNamePlates = function() return {} end }
UnitIsPlayer = function(unit) return units[unit] and units[unit].player end
UnitIsUnit = function() return false end
UnitGUID = function(unit) return units[unit] and units[unit].guid end
UnitName = function(unit)
	calls.UnitName = calls.UnitName + 1
	local u = units[unit]
	return u and u.first, u and u.second
end
GetUnitName = function(unit)
	local u = units[unit]
	return u and (u.second and (u.first .. " " .. u.second) or u.first)
end
CreateFrame = function() return NewFrame() end
hooksecurefunc = function() calls.hooks = calls.hooks + 1 end
C_Timer = { After = function(_, fn) fn() end }
UNKNOWNOBJECT = "Unknown"

local SF = {
	Icons = Expect.Load("Icons.lua"), Resolver = Expect.Load("Resolver.lua"), Layout = Expect.Load("Layout.lua"),
	Print = function() end,
}
local db = { enabled = true, defaultIcon = "gold-star", position = "left", size = 20, offsetX = 0, offsetY = 0,
	friends = { bnet = {}, ingame = {} }, characters = {} }
SF.DB = function() return db end
SF.Friends = { index = SF.Resolver.BuildIndex({ bnet = {
	{ kind = "bnet", id = "Xan#1", characters = { { name = "Xanduin Laszwyn", guid = "Player-1-XAN" } } },
}, ingame = {} }) }
assert(loadfile(ADDON_DIR .. "Nameplates.lua"))("SpotFriends", SF)
local Nameplates = SF.Nameplates
Nameplates.started = true

-- An NPC: nothing made, nothing hooked, its name never read.
Nameplates:OnAdded("nameplate1")
Equal(calls.CreateFrame, 0, "an NPC makes no frame")
Equal(calls.hooks, 0, "an NPC's frame is not hooked")
Equal(calls.UnitName, 0, "an NPC's name is not read")

-- A stranger: resolved once, then from the cache; no frame.
Nameplates:OnAdded("nameplate2")
Equal(calls.CreateFrame, 0, "a stranger makes no frame")
Equal(calls.UnitName, 1, "a stranger's name read once")
Nameplates:OnRemoved("nameplate2")
Nameplates:OnAdded("nameplate2")
Equal(calls.UnitName, 1, "the second sight comes from the cache")

-- A friend: one frame, one texture, one anchor.
Nameplates:OnAdded("nameplate3")
local uf = plates.nameplate3.UnitFrame
local holder = Nameplates.holders[uf]
Expect.True(holder ~= nil, "a friend gets an icon frame")
Equal(calls.CreateFrame, 1, "one frame made")
Equal(calls.SetTexture, 1, "its texture set once")
Equal(calls.SetPoint, 1, "anchored once")
Equal(holder.anchor[2], uf.name, "anchored to the name")
Equal(holder.anchor[3], "LEFT", "before the name")
Equal(holder.size, 20, "the chosen size")
Expect.True(holder:IsShown(), "shown")

-- Blizzard re-laying the plate out the same way: nothing touched.
Nameplates:RefreshAll()
Nameplates:RefreshAll()
Equal(calls.SetPoint, 1, "the same layout sets no anchor")
Equal(calls.SetTexture, 1, "the same icon sets no texture")

-- The plate switches to names only: the anchor moves once.
uf.HealthBarsContainer.healthBar.shown = false
uf.name.justify = "CENTER"
uf.name.width = 80
Nameplates:RefreshAll()
Equal(calls.SetPoint, 2, "a new layout anchors again")
Equal(holder.anchor[3], "CENTER", "against the centred name")
Equal(holder.anchor[4], -(40 + SF.Layout.GAP), "at the text's left edge")

-- Right of the plate: after the level badge when it is shown and laid out, else after the bar.
uf.HealthBarsContainer.healthBar.shown = true
db.position = "right"
Nameplates:RefreshAll()
Equal(holder.anchor[2], uf.HealthBarsContainer, "right, no badge: after the bar")
uf.LevelFrame.shown = true
Nameplates:RefreshAll()
Equal(holder.anchor[2], uf.LevelFrame, "right: after the level badge")
Equal(holder.anchor[3], "CENTER", "from the badge's centre")
Equal(holder.anchor[4], 14 + SF.Layout.GAP, "past its widest part, not its narrower frame")
uf.LevelFrame.points = 0
Nameplates:RefreshAll()
Equal(holder.anchor[2], uf.HealthBarsContainer, "a badge with no anchor: after the bar")
uf.LevelFrame.shown, uf.LevelFrame.points = false, nil
uf.OtherBadge.shown = true
Nameplates:RefreshAll()
Equal(holder.anchor[2], uf.OtherBadge, "a badge on another frame, found by its anchor")
Equal(holder.anchor[4], 10 + SF.Layout.GAP, "past it")
uf.OtherBadge.shown = false
db.position = "left"
uf.HealthBarsContainer.healthBar.shown = false
Nameplates:RefreshAll()

-- The plate leaves, another unit takes the pooled frame and the friend comes back: the frame
-- is reused.
Nameplates:OnRemoved("nameplate3")
Expect.True(not holder:IsShown(), "hidden when the plate leaves")
Nameplates:OnAdded("nameplate3")
Equal(calls.CreateFrame, 1, "the frame reused")
Expect.True(holder:IsShown(), "shown again")

-- Turned off: hidden, nothing made.
db.enabled = false
Nameplates:RefreshAll()
Expect.True(not holder:IsShown(), "hidden when turned off")
db.enabled = true

-- The friend gets another icon: the texture changes once.
db.friends.bnet["Xan#1"] = "ruby-heart"
SF.Resolver.Invalidate()
Nameplates:RefreshAll()
Equal(calls.SetTexture, 2, "the new icon set")
Expect.True(holder.icon.path:find("ruby%-heart") ~= nil, "the ruby heart")

-- "None" on the friend: hidden.
db.friends.bnet["Xan#1"] = "none"
SF.Resolver.Invalidate()
Nameplates:RefreshAll()
Expect.True(not holder:IsShown(), "none hides the icon")

-- Test mode: every player, strangers too, gets the default icon.
SF.testMode = true
Nameplates:OnAdded("nameplate2")
Expect.True(Nameplates.holders[plates.nameplate2.UnitFrame] ~= nil, "test mode marks a stranger")
SF.testMode = nil

-- A name still loading is not remembered.
units.nameplate2.first = "Unknown"
SF.Resolver.Invalidate()
Nameplates:OnAdded("nameplate2")
Equal(SF.Resolver.Cached("Player-1-STR"), nil, "an unloaded name is not cached")

Equal(Nameplates.errors, 0, "no errors")
Expect.Done("nameplates")
