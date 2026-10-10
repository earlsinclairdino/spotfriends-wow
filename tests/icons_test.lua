local Expect = dofile(ADDON_DIR .. "tests/expect.lua")
local Icons = Expect.Load("Icons.lua")
local Equal = Expect.Equal

Equal(#Icons.List, 26, "26 icons")
local keys, files = {}, {}
for i, icon in ipairs(Icons.List) do
	Expect.True(type(icon.key) == "string" and icon.key ~= "", "icon " .. i .. " has a key")
	Expect.True(type(icon.label) == "string" and icon.label ~= "", icon.key .. " has a label")
	Equal(keys[icon.key], nil, icon.key .. " is unique")
	Equal(files[icon.file], nil, icon.file .. " is unique")
	Expect.True(icon.key ~= Icons.NONE and icon.key ~= Icons.DEFAULT, icon.key .. " is not a reserved word")
	keys[icon.key], files[icon.file] = true, true
	local handle = io.open(ADDON_DIR .. "Textures/" .. icon.file, "rb")
	Expect.True(handle ~= nil, icon.file .. " exists")
	if handle then
		Equal(handle:read(4), "\137PNG", icon.file .. " is a PNG")
		handle:close()
	end
	Equal(Icons.Path(icon.key), "Interface\\AddOns\\SpotFriends\\Textures\\" .. icon.file, icon.key .. " path")
end

Expect.True(Icons.Get(Icons.Default()) ~= nil, "the default icon exists")
Equal(Icons.Path(Icons.NONE), nil, "none has no texture")
Equal(Icons.Path(Icons.DEFAULT), nil, "default has no texture of its own")
Equal(Icons.Path("retired-icon"), nil, "an unknown key has no texture")
Equal(Icons.Path(nil), nil, "nil has no texture")
Equal(Icons.Label(Icons.NONE), "None", "none's label")
Equal(Icons.Label(nil), "Default", "nil reads as default")
Equal(Icons.Label("gold-star"), "Gold Star", "a label")

-- Two icons renamed in 0.2; their old keys still resolve.
Equal(Icons.Label("blue-spot"), "Blue Spot", "Blue Spot")
Equal(Icons.Label("gold-spot"), "Gold Spot", "Gold Spot")
Equal(Icons.Get("blue-orb"), nil, "the old key is gone")
Equal(Icons.Current("blue-orb"), "blue-spot", "blue-orb maps to blue-spot")
Equal(Icons.Current("gold-coin"), "gold-spot", "gold-coin maps to gold-spot")
Equal(Icons.Current("ruby-heart"), "ruby-heart", "other keys unchanged")
Equal(Icons.Default(), "gold-spot", "friends get Gold Spot by default")
Equal(Icons.GROUP_DEFAULT, "blue-spot", "the group gets Blue Spot by default")

Expect.Done("icons")
