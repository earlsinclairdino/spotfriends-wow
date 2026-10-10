local Expect = dofile(ADDON_DIR .. "tests/expect.lua")
local Layout = Expect.Load("Layout.lua")
local Equal = Expect.Equal

local GAP = Layout.GAP

local function State(fields)
	local s = { nameShown = true, justify = "LEFT", textWidth = 100, barShown = true, style = 2,
		raidShown = false, classShown = false, badge = nil, badgeWidth = nil }
	for k, v in pairs(fields or {}) do s[k] = v end
	return s
end

local function Check(label, state, position, ox, oy, anchorTo, point, relative, x, y)
	local a, p, r, px, py = Layout.Plan(state, position, ox, oy)
	Equal(a, anchorTo, label .. ": anchor")
	if anchorTo == nil then return end
	Equal(p, point, label .. ": point")
	Equal(r, relative, label .. ": relative point")
	Equal(px, x, label .. ": x")
	Equal(py, y, label .. ": y")
end

-- Left: before the name.
Check("left, name above the bar", State(), "left", 0, 0, "name", "RIGHT", "LEFT", -GAP, 0)
Check("left, offsets", State(), "left", 5, -3, "name", "RIGHT", "LEFT", -GAP + 5, -3)
Check("left, name inside the bar", State({ style = 1 }), "left", 0, 0, "name", "RIGHT", "LEFT", -GAP, 0)
Check("left, centred name", State({ style = 3, justify = "CENTER", textWidth = 80 }), "left", 0, 0,
	"name", "RIGHT", "CENTER", -(40 + GAP), 0)
Check("left, right-justified name", State({ justify = "RIGHT", textWidth = 60 }), "left", 0, 0,
	"name", "RIGHT", "RIGHT", -(60 + GAP), 0)
Check("left, names only", State({ barShown = false, justify = "CENTER", textWidth = 90 }), "left", 0, 0,
	"name", "RIGHT", "CENTER", -(45 + GAP), 0)
Check("left, centred, width unknown", State({ justify = "CENTER", textWidth = false }), "left", 0, 0,
	"name", "RIGHT", "LEFT", -GAP, 0)
Check("left, simplified (name hidden)", State({ nameShown = false }), "left", 0, 0, "bar", "RIGHT", "LEFT", -GAP, 0)
Check("left, nothing shown", State({ nameShown = false, barShown = false }), "left", 0, 0, nil)
Check("left, raid marker, name inside the bar", State({ style = 1, raidShown = true }), "left", 0, 0,
	"raid", "RIGHT", "LEFT", -GAP, 0)
Check("left, classification and raid marker", State({ style = 1, raidShown = true, classShown = true }), "left", 0, 0,
	"class", "RIGHT", "LEFT", -GAP, 0)
Check("left, raid marker, name above the bar", State({ style = 2, raidShown = true }), "left", 0, 0,
	"name", "RIGHT", "LEFT", -GAP, 0)
Check("left, raid marker, name hidden", State({ nameShown = false, raidShown = true }), "left", 0, 0,
	"raid", "RIGHT", "LEFT", -GAP, 0)
Check("left, raid marker, names only", State({ barShown = false, raidShown = true, justify = "CENTER", textWidth = 50 }), "left", 0, 0,
	"name", "RIGHT", "CENTER", -(25 + GAP), 0)

-- Right: after the plate.
Check("right, bar", State(), "right", 0, 0, "bar", "LEFT", "RIGHT", GAP, 0)
Check("right, offsets", State(), "right", -4, 6, "bar", "LEFT", "RIGHT", GAP - 4, 6)
local BADGE = {}
Check("right, level badge", State({ badge = BADGE, badgeWidth = 28 }), "right", 0, 0,
	"badge", "LEFT", "CENTER", 14 + GAP, 0)
Check("right, level badge, offsets", State({ badge = BADGE, badgeWidth = 28 }), "right", 3, -1,
	"badge", "LEFT", "CENTER", 14 + GAP + 3, -1)
Check("right, level badge of unknown width", State({ badge = BADGE, badgeWidth = false }), "right", 0, 0,
	"badge", "LEFT", "RIGHT", GAP, 0)
Check("right, no badge", State({ badge = false }), "right", 0, 0,
	"bar", "LEFT", "RIGHT", GAP, 0)
Check("right, simplified", State({ nameShown = false }), "right", 0, 0, "bar", "LEFT", "RIGHT", GAP, 0)
Check("right, names only, centred", State({ barShown = false, justify = "CENTER", textWidth = 90 }), "right", 0, 0,
	"name", "LEFT", "CENTER", 45 + GAP, 0)
Check("right, names only, left-justified", State({ barShown = false, justify = "LEFT", textWidth = 90 }), "right", 0, 0,
	"name", "LEFT", "LEFT", 90 + GAP, 0)
Check("right, names only, right-justified", State({ barShown = false, justify = "RIGHT", textWidth = 90 }), "right", 0, 0,
	"name", "LEFT", "RIGHT", GAP, 0)
Check("right, names only, width unknown", State({ barShown = false, justify = "CENTER", textWidth = false }), "right", 0, 0,
	"name", "LEFT", "RIGHT", GAP, 0)
Check("right, nothing shown", State({ nameShown = false, barShown = false }), "right", 0, 0, nil)

Expect.Done("layout")
