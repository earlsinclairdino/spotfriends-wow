-- The icons a player can put on a friend's nameplate. Pure Lua: the tests load it with dofile.
local Icons = {}

local FOLDER = "Interface\\AddOns\\SpotFriends\\Textures\\"

-- Keys are what the settings save: never rename one. The order is the picker's.
Icons.List = {
	{ key = "gold-star", label = "Gold Star", file = "gold-star.png" },
	{ key = "silver-blue-star", label = "Silver-Blue Star", file = "silver-blue-star.png" },
	{ key = "sapphire-crystal-star", label = "Sapphire Crystal Star", file = "sapphire-crystal-star.png" },
	{ key = "mint-outline-star", label = "Mint Outline Star", file = "mint-outline-star.png" },
	{ key = "gold-medallion-star", label = "Gold Medallion Star", file = "gold-medallion-star.png" },
	{ key = "shield-star", label = "Shield Star", file = "shield-star.png" },
	{ key = "winged-star", label = "Winged Star", file = "winged-star.png" },
	{ key = "violet-starburst", label = "Violet Starburst", file = "violet-starburst.png" },
	{ key = "ruby-hex-star", label = "Ruby Hex Star", file = "ruby-hex-star.png" },
	{ key = "double-gold-stars", label = "Double Gold Stars", file = "double-gold-stars.png" },
	{ key = "teal-circle", label = "Teal Circle Friends", file = "teal-circle.png" },
	{ key = "cyan-outline-circle", label = "Cyan Outline Friends", file = "cyan-outline-circle.png" },
	{ key = "navy-square", label = "Navy Square Friends", file = "navy-square.png" },
	{ key = "gold-medallion", label = "Gold Medallion Friends", file = "gold-medallion.png" },
	{ key = "emerald-circle", label = "Emerald Circle Friends", file = "emerald-circle.png" },
	{ key = "cyan-shield", label = "Cyan Shield Friends", file = "cyan-shield.png" },
	{ key = "violet-crystal", label = "Violet Circle Friends", file = "violet-crystal.png" },
	{ key = "blue-gold-split", label = "Blue & Gold Friends", file = "blue-gold-split.png" },
	{ key = "linked-rings", label = "Linked Rings", file = "linked-rings.png" },
	{ key = "black-gold-minimal", label = "Black & Gold Friends", file = "black-gold-minimal.png" },
	{ key = "silver-crescent", label = "Silver Crescent", file = "silver-crescent.png" },
	{ key = "sapphire-crescent", label = "Sapphire Crescent", file = "sapphire-crescent.png" },
	{ key = "ruby-heart", label = "Ruby Heart", file = "ruby-heart.png" },
	{ key = "red-heart", label = "Red Heart", file = "red-heart.png" },
	{ key = "blue-spot", label = "Blue Spot", file = "blue-spot.png" },
	{ key = "gold-spot", label = "Gold Spot", file = "gold-spot.png" },
}

Icons.NONE = "none"
Icons.DEFAULT = "default"

-- Keys renamed since a release: settings saved with the old key are mapped on load.
Icons.RENAMED = { ["blue-orb"] = "blue-spot", ["gold-coin"] = "gold-spot" }

function Icons.Current(key)
	return Icons.RENAMED[key] or key
end

local byKey, paths = {}, {}
for _, icon in ipairs(Icons.List) do
	byKey[icon.key] = icon
	paths[icon.key] = FOLDER .. icon.file
end

function Icons.Get(key)
	return key and byKey[key] or nil
end

--- The texture path, or nil for "none", "default" and a key no longer shipped.
function Icons.Path(key)
	return key and paths[key] or nil
end

Icons.FRIEND_DEFAULT = "gold-spot"
Icons.GROUP_DEFAULT = "blue-spot"

function Icons.Default()
	return Icons.FRIEND_DEFAULT
end

function Icons.Label(key)
	if key == Icons.NONE then return "None" end
	if key == nil or key == Icons.DEFAULT then return "Default" end
	local icon = byKey[key]
	return icon and icon.label or key
end

local _, NS = ...
if type(NS) == "table" then NS.Icons = Icons end
return Icons
