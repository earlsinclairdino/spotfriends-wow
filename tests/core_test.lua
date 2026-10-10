local Expect = dofile(ADDON_DIR .. "tests/expect.lua")
local Equal = Expect.Equal

local SF = { Icons = Expect.Load("Icons.lua"), Resolver = Expect.Load("Resolver.lua") }
assert(loadfile(ADDON_DIR .. "Core.lua"))("SpotFriends", SF)
Equal(_G.SpotFriends, SF, "the addon table is global")

-- Fill adds what is missing, nested too, and keeps what is there.
local target = { size = 30, friends = { bnet = { ["A#1"] = "blue-orb" } } }
SF.Fill(target, SF.Defaults())
Equal(target.size, 30, "a saved value is kept")
Equal(target.position, "left", "a missing value is added")
Equal(target.friends.bnet["A#1"], "blue-orb", "a nested saved value is kept")
Equal(type(target.friends.ingame), "table", "a missing nested table is added")
Equal(type(target.characters), "table", "characters added")

-- Sanitise brings odd values back inside what the page offers.
local odd = SF.Fill({ defaultIcon = "retired-icon", position = "middle", size = 500, offsetX = -99, offsetY = "x" }, SF.Defaults())
SF.Sanitise(odd)
Equal(odd.defaultIcon, SF.Icons.Default(), "an icon no longer shipped falls back")
Equal(odd.position, "left", "an unknown position falls back")
Equal(odd.size, SF.SIZE_MAX, "size clamped")
Equal(odd.offsetX, -SF.OFFSET_LIMIT, "offset clamped")
Equal(odd.offsetY, 0, "a non-number offset reset")
local none = SF.Sanitise(SF.Fill({ defaultIcon = "none" }, SF.Defaults()))
Equal(none.defaultIcon, "none", "no default icon is a valid choice")

-- InitDB on a first run, then on a saved file.
SpotFriendsDB = nil
SF.InitDB()
Equal(SpotFriendsDB.enabled, true, "first run: defaults")
SpotFriendsDB = { enabled = false, characters = { ["meril jita"] = "red-heart" } }
SF.InitDB()
Equal(SpotFriendsDB.enabled, false, "a saved switch kept")
Equal(SpotFriendsDB.characters["meril jita"], "red-heart", "a saved override kept")
Equal(SF.DB(), SpotFriendsDB, "DB is the saved table")

-- Reset keeps the same table (the page holds no stale reference) and drops the answers.
local generation = SF.Resolver.generation
local db = SF.DB()
SF.ResetSettings()
Equal(SF.DB(), db, "the same table")
Equal(db.enabled, true, "back to the default")
Equal(next(db.characters), nil, "overrides gone")
Equal(SF.Resolver.generation, generation + 1, "cached answers dropped")

-- Events the client does not know are kept, the rest registered.
local registered = {}
local frame = { RegisterEvent = function(_, event)
	if event == "NOT_ON_THIS_CLIENT" then error("unknown event") end
	registered[#registered + 1] = event
end }
SF.RegisterEvents(frame, { "PLAYER_LOGIN", "NOT_ON_THIS_CLIENT", "CVAR_UPDATE" })
Equal(#registered, 2, "two registered")
Equal(SF.missingEvents[1], "NOT_ON_THIS_CLIENT", "the refusal kept")

-- The 0.2 defaults.
local fresh = SF.Defaults()
Equal(fresh.size, 14, "size 14")
Equal(fresh.defaultIcon, "gold-spot", "Gold Spot")
Equal(fresh.group.enabled, true, "group marking on")
Equal(fresh.group.icon, "blue-spot", "Blue Spot for the group")
Equal(fresh.minimap.hide, false, "the minimap button shown")
Equal(fresh.minimap.minimapPos, 175, "away from Spoken's button")

-- A 0.2 file: the button moves off Spoken's angle; one the player dragged stays.
SpotFriendsDB = { version = 2, size = 20, minimap = { minimapPos = 204 } }
SF.InitDB()
Equal(SpotFriendsDB.minimap.minimapPos, 175, "moved off Spoken's button")
Equal(SpotFriendsDB.size, 20, "a 0.2 file's size is the player's own")
SpotFriendsDB = { version = 2, minimap = { minimapPos = 90 } }
SF.InitDB()
Equal(SpotFriendsDB.minimap.minimapPos, 90, "a dragged button stays")
SpotFriendsDB.minimap.minimapPos = 204
SF.InitDB()
Equal(SpotFriendsDB.minimap.minimapPos, 204, "dragged to 204 after the move, it stays")

-- A 0.1 file: its untouched defaults move to the new ones, its own choices stay.
SpotFriendsDB = { enabled = true, defaultIcon = "gold-star", size = 20, position = "right",
	friends = { bnet = { ["A#1"] = "blue-orb" }, ingame = { Bob = "gold-coin" } },
	characters = { ["meril jita"] = "blue-orb", ["oryn"] = "none" } }
SF.InitDB()
Equal(SpotFriendsDB.size, 14, "old default size migrated")
Equal(SpotFriendsDB.defaultIcon, "gold-spot", "old default icon migrated")
Equal(SpotFriendsDB.position, "right", "a choice kept")
Equal(SpotFriendsDB.friends.bnet["A#1"], "blue-spot", "a renamed icon on a friend")
Equal(SpotFriendsDB.friends.ingame.Bob, "gold-spot", "a renamed icon on a character friend")
Equal(SpotFriendsDB.characters["meril jita"], "blue-spot", "a renamed icon on a character")
Equal(SpotFriendsDB.characters.oryn, "none", "none kept")
Equal(SpotFriendsDB.group.enabled, true, "group marking added")
Equal(SpotFriendsDB.version, SF.SETTINGS_VERSION, "now at the current version")
SpotFriendsDB = { size = 22, defaultIcon = "winged-star" }
SF.InitDB()
Equal(SpotFriendsDB.size, 22, "a chosen size is not migrated")
Equal(SpotFriendsDB.defaultIcon, "winged-star", "a chosen icon is not migrated")
SpotFriendsDB.size = 20
SF.InitDB()
Equal(SpotFriendsDB.size, 20, "a 0.2 file keeps 20 when chosen")
SpotFriendsDB.group.icon = "retired"
SF.InitDB()
Equal(SpotFriendsDB.group.icon, "blue-spot", "an unknown group icon falls back")

-- Reset keeps the minimap button where it was dragged, shown again.
SpotFriendsDB.minimap.minimapPos, SpotFriendsDB.minimap.hide = 77, true
local minimap = SpotFriendsDB.minimap
SF.ResetSettings()
Equal(SpotFriendsDB.minimap, minimap, "the same minimap table")
Equal(minimap.minimapPos, 77, "its place kept")
Equal(minimap.hide, false, "shown again")

-- Characters, one at a time and all at once.
SF.SetCharacter("meril jita", "red-heart")
SF.SetCharacter("oryn", "default")
Equal(SpotFriendsDB.characters["meril jita"], "red-heart", "set")
SF.SetCharacter("oryn", nil)
Equal(SpotFriendsDB.characters.oryn, nil, "removed")
SF.ClearCharacters()
Equal(next(SpotFriendsDB.characters), nil, "cleared")

Expect.Done("core")
