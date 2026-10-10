-- The whole addon loaded in TOC order against the client stub: start-up, the settings page as a
-- player would use it, the slash commands, and a friend's nameplate.
local Expect = dofile(ADDON_DIR .. "tests/expect.lua")
local Stub = dofile(ADDON_DIR .. "tests/client_stub.lua")
local Equal, True = Expect.Equal, Expect.True

Stub.friends.bnet = {
	{ battleTag = "Meri#1111", accountName = "Meri Real",
		gameAccountInfo = { characterName = "Meril Jita", realmName = "Elsewhere", realmDisplayName = "ClassicBetaPvE2", playerGuid = "Player-1-MER",
			clientProgram = "WoW", isOnline = true } },
	{ battleTag = "Gone#2222", accountName = "Gone Away", gameAccountInfo = nil },
	{ battleTag = "Retail#3333", accountName = "On Retail",
		gameAccountInfo = { characterName = "Meril", realmName = "Argent Dawn", playerGuid = "Player-9-RET",
			clientProgram = "WoW", isOnline = true } },
}
Stub.friends.ingame = {
	{ name = "Tamsin Vale", guid = "Player-1-TAM", connected = true },
}

local SF = Stub.LoadAddon(ADDON_DIR)
Stub.Fire("ADDON_LOADED", "SpotFriends")
Stub.Fire("PLAYER_ENTERING_WORLD")
Stub.RunTimers()

Equal(SpotFriendsDB.enabled, true, "defaults saved")
True(Stub.category ~= nil, "the settings page is registered")
Equal(Stub.category.name, "SpotFriends", "under its name")
Equal(SF.cvars.friendly, "nameplateShowFriendlyPlayers", "Midnight's friendly nameplate CVar found")
Equal(SF.cvars.namesOnly, "nameplateShowOnlyNameForFriendlyPlayerUnits", "the names-only CVar found")
Equal(#SF.Friends.snapshot.bnet, 3, "Battle.net friends read")
Equal(SF.Friends.snapshot.bnet[1].characters[1].elsewhere, false, "a friend on this realm, by its display name")
Equal(SF.Friends.snapshot.bnet[3].characters[1].elsewhere, true, "a friend playing on another realm")
Equal(#SF.Friends.snapshot.ingame, 1, "character friends read")

-- A friend's nameplate appears.
local uf = Stub.AddPlate("nameplate1", { player = true, guid = "Player-1-MER", first = "Meril", second = "Jita" })
Stub.AddPlate("nameplate2", { player = false, guid = "Creature-1", first = "Boar" })
-- A stranger here named like the friend who plays on another realm.
local namesake = Stub.AddPlate("nameplate3", { player = true, guid = "Player-1-NSK", first = "Meril", second = "Other" })
Stub.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
Stub.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
Stub.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
Equal(SF.Nameplates.holders[namesake], nil, "a namesake of a friend on another realm gets no icon")
local holder = SF.Nameplates.holders[uf]
True(holder ~= nil and holder:IsShown(), "the friend's nameplate shows the icon")
True(holder.icon.texture:find("gold%-spot") ~= nil, "the default icon, Gold Spot")
Equal(holder.point, "RIGHT", "left of the name")

-- The page opens.
local panel = Stub.category.panel
panel.shown = false
panel:Show()
Stub.RunTimers()
True(Stub.askedFriends, "opening the page asks for a fresh friend list")
True(Stub.FindText("Meri Real") ~= nil, "a Battle.net friend listed")
True(Stub.FindText("playing Meril Jita") ~= nil, "with the character played")
True(Stub.FindText("Tamsin Vale") ~= nil, "a character friend listed")
True(Stub.FindText("Battle.net friends (3)") ~= nil, "the Battle.net heading counts them")

local Picker = SF.Options.Picker
local function Pick(key)
	for _, tile in ipairs(Picker.frame.tiles) do
		if tile.choice == key then tile:Click(); return end
	end
	error("no tile " .. key)
end

-- The default icon.
local defaultButton = Stub.Find(function(w) return w.kind == "Button" and w.width == 32 and w.SetKey and w.key ~= nil end)
defaultButton:Click()
Equal(Picker.frame.title.text, "Default icon", "the picker opens for the default icon")
Pick("ruby-heart")
Stub.RunTimers()
Equal(SpotFriendsDB.defaultIcon, "ruby-heart", "the default icon chosen")
True(holder.icon.texture:find("ruby%-heart") ~= nil, "the nameplate follows")
True(Stub.FindText("Ruby Heart") ~= nil, "the page shows its name")

-- A friend's own icon, then back to the default with a right-click.
local row = Stub.FindText("Meri Real").parent
row.button:Click("LeftButton")
Pick("blue-spot")
Stub.RunTimers()
Equal(SpotFriendsDB.friends.bnet["Meri#1111"], "blue-spot", "the friend's icon saved")
True(holder.icon.texture:find("blue%-spot") ~= nil, "the nameplate shows it")
row = Stub.FindText("Meri Real").parent
row.button:Click("RightButton")
Stub.RunTimers()
Equal(SpotFriendsDB.friends.bnet["Meri#1111"], nil, "right-click goes back to the default")

-- A character override, typed in.
local box = Stub.Find(function(w) return w.kind == "EditBox" end)
box:SetText("  meril-jita ")
box.scripts.OnEnterPressed(box)
Equal(SpotFriendsDB.characters["meril jita"], "default", "added, following the default")
Pick("none")
Stub.RunTimers()
Equal(SpotFriendsDB.characters["meril jita"], "none", "none chosen")
True(not holder:IsShown(), "the override hides the friend's icon")
True(Stub.FindText("Meril Jita") ~= nil, "listed by name")
local remove = Stub.Find(function(w) return w.kind == "Button" and w.text == "Remove" and w:IsVisible() end)
remove:Click()
Stub.RunTimers()
Equal(SpotFriendsDB.characters["meril jita"], nil, "removed")
True(holder:IsShown(), "the icon is back")

-- Position, size.
local right = Stub.FindText("Right, after the nameplate").parent
right:Click()
Stub.RunTimers()
Equal(SpotFriendsDB.position, "right", "right chosen")
Equal(holder.anchorTo, "bar", "after the plate")
local sizeHolder = Stub.Find(function(w) return w.caption and w.caption.text == "Size" end)
local slider = Stub.Find(function(w) return w.kind == "Slider" and w.parent == sizeHolder end)
slider:SetValue(31)
Stub.RunTimers()
Equal(SpotFriendsDB.size, 31, "size saved")
Equal(holder.width, 31, "the nameplate's icon resized")

-- The preview goes through every look without an error.
local cycle = Stub.Find(function(w) return w.kind == "Button" and w.text == "Name above the bar" end)
for _ = 1, 5 do cycle:Click() end
Equal(cycle.text, "Name above the bar", "back to the first look")

-- The game's own settings: written out of combat, queued in combat.
local friendly = Stub.FindText("Show friendly players' nameplates").parent
friendly:Click()
Equal(Stub.cvars.nameplateShowFriendlyPlayers, "1", "friendly nameplates on")
Stub.combat = true
local namesOnly = Stub.FindText("Names only for friendly players").parent
namesOnly:Click()
Equal(Stub.cvars.nameplateShowOnlyNameForFriendlyPlayerUnits, "0", "not written in combat")
Stub.combat = false
Stub.Fire("PLAYER_REGEN_ENABLED")
Equal(Stub.cvars.nameplateShowOnlyNameForFriendlyPlayerUnits, "1", "written when combat ends")

-- Slash commands.
SlashCmdList.SPOTFRIENDS("")
Equal(Stub.opened, "SpotFriends", "/spotfriends opens the page")
SlashCmdList.SPOTFRIENDS("debug")
True(#Stub.chat > 5, "debug prints")
SlashCmdList.SPOTFRIENDS("test")
Stub.RunTimers()
local boar = SF.Nameplates.holders[Stub.plates.nameplate2.UnitFrame]
Equal(boar, nil, "test mode still leaves NPCs alone")
SlashCmdList.SPOTFRIENDS("test")
SlashCmdList.SPOTFRIENDS("reset")
Stub.RunTimers()
Equal(SpotFriendsDB.position, "left", "reset")
SlashCmdList.SPOTFRIENDS("nonsense")
_G.SpotFriends_OpenSettings()

-- The group: a party member who is not a friend gets the group icon.
local grim = Stub.AddPlate("nameplate4", { player = true, guid = "Player-1-GRM", first = "Grim", second = "Stoneback" })
Stub.units.party1 = Stub.units.nameplate4
Stub.units.party2 = Stub.units.nameplate1
Stub.group = { "party1", "party2" }
Stub.Fire("GROUP_ROSTER_UPDATE")
Stub.RunTimers()
Stub.Fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
local grimHolder = SF.Nameplates.holders[grim]
True(grimHolder ~= nil and grimHolder:IsShown(), "a group member is marked")
True(grimHolder.icon.texture:find("blue%-spot") ~= nil, "with Blue Spot")
True(holder.icon.texture:find("gold%-spot") ~= nil, "a friend in the group keeps the friend icon")
local groupBox = Stub.FindText("Mark people in my group").parent
groupBox:Click()
Stub.RunTimers()
Equal(SpotFriendsDB.group.enabled, false, "group marking off")
True(not grimHolder:IsShown(), "the member's icon goes")
groupBox:Click()
Stub.RunTimers()
True(grimHolder:IsShown(), "and comes back")
for _, w in ipairs(Stub.widgets) do
	if w.kind == "Button" and w.width == 32 and w.SetKey then
		w:Click()
		if Picker.frame.title.text == "Group icon" then break end
	end
end
Equal(Picker.frame.title.text, "Group icon", "the picker opens for the group icon")
Pick("ruby-heart")
Stub.RunTimers()
Equal(SpotFriendsDB.group.icon, "ruby-heart", "group icon chosen")
True(grimHolder.icon.texture:find("ruby%-heart") ~= nil, "the member follows")

-- The right-click menu on a player.
Equal(#SF.UnitMenu.hooked, 7, "every unit menu hooked")
local root = Stub.Menu("MENU_UNIT_TARGET", { unit = "nameplate4" })
local add = Stub.MenuEntry(root, "Add to SpotFriends")
True(add ~= nil, "Add to SpotFriends offered")
Equal(add.callback(), MenuResponse.Close, "it closes the menu")
Stub.RunTimers()
Equal(SpotFriendsDB.characters["grim stoneback"], "default", "added with the default icon")
True(grimHolder.icon.texture:find("gold%-spot") ~= nil, "the character override beats the group icon")
root = Stub.Menu("MENU_UNIT_TARGET", { unit = "nameplate4" })
True(Stub.MenuEntry(root, "Remove from SpotFriends") ~= nil, "Remove offered once listed")
local iconsMenu = Stub.MenuEntry(root, "SpotFriends Icon")
Equal(#iconsMenu.children, 28, "default, 26 icons and none")
local fakeButton = { AttachTexture = function() return Stub.Widget("Texture") end, fontString = Stub.Widget("FontString") }
fakeButton.fontString.GetUnboundedStringWidth = function() return 70 end
for _, entry in ipairs(iconsMenu.children) do
	for _, init in ipairs(entry.initializers) do
		local width, height = init(fakeButton)
		Equal(width, 130, entry.text .. ": the row is sized for its icon")
		Equal(height, 20, entry.text .. ": row height")
	end
end
local heart = Stub.MenuEntry(iconsMenu, "Red Heart")
True(not heart.isSelected(), "not chosen yet")
heart.setSelected()
Stub.RunTimers()
Equal(SpotFriendsDB.characters["grim stoneback"], "red-heart", "icon chosen from the menu")
True(heart.isSelected(), "shown as chosen")
True(grimHolder.icon.texture:find("red%-heart") ~= nil, "the nameplate follows")
True(Stub.FindText("Grim Stoneback") ~= nil, "the page lists the character")
Stub.MenuEntry(Stub.Menu("MENU_UNIT_TARGET", { unit = "nameplate4" }), "Remove from SpotFriends").callback()
Equal(SpotFriendsDB.characters["grim stoneback"], nil, "removed from the menu")
Stub.MenuEntry(Stub.Menu("MENU_UNIT_PLAYER", { name = "Tamsin", server = "Vale" }), "Add to SpotFriends").callback()
Equal(SpotFriendsDB.characters["tamsin vale"], "default", "added by the menu's name fields")
Equal(#Stub.Menu("MENU_UNIT_PLAYER", { unit = "player" }).children, 0, "nothing on your own menu")
Equal(#Stub.Menu("MENU_UNIT_TARGET", { unit = "nameplate2" }).children, 0, "nothing on an NPC")

-- Clear list and Defaults, each behind a confirmation.
SF.SetCharacter("someone else", "blue-spot")
Stub.RunTimers()
local popups = Stub.popups or 0
Stub.Find(function(w) return w.kind == "Button" and w.text == "Clear list" end):Click()
Stub.RunTimers()
Equal(Stub.popups, popups + 1, "Clear list asks first")
Equal(next(SpotFriendsDB.characters), nil, "the list is empty")
SpotFriendsDB.size = 30
SpotFriendsDB.minimap.minimapPos = 99
Stub.Find(function(w) return w.kind == "Button" and w.text == "Defaults" end):Click()
Stub.RunTimers()
Equal(SpotFriendsDB.size, 14, "Defaults restores the size")
Equal(SpotFriendsDB.group.icon, "blue-spot", "and the group icon")
Equal(SpotFriendsDB.minimap.minimapPos, 99, "the minimap button stays where it was")

-- The minimap button.
local registered = Stub.dbicon.registered.SpotFriends
True(registered ~= nil, "registered with LibDBIcon")
Equal(registered.db, SpotFriendsDB.minimap, "with the saved table")
local launcher = registered.object
True(launcher.icon:find("gold%-spot") ~= nil, "its icon is Gold Spot")
local centred = Stub.dbicon:GetMinimapButton("SpotFriends").icon
Equal(centred.width, 18, "the icon sized for the ring's hole")
Equal(centred.points[1][1], "CENTER", "centred")
Equal(centred.points[1][4], 17, "on the hole's centre, x")
Equal(centred.points[1][5], -15, "on the hole's centre, y")
launcher.OnClick(nil, "MiddleButton")
Stub.RunTimers()
Equal(SpotFriendsDB.enabled, false, "middle-click turns the icons off")
True(not grimHolder:IsShown(), "the icons go")
local tip = { lines = {} }
function tip:SetText(text) self.lines = { text } end
function tip:AddLine(text) table.insert(self.lines, text) end
function tip:ClearLines() self.lines = {} end
function tip:IsShown() return true end
function tip:Show() end
launcher.OnTooltipShow(tip)
local tipText = table.concat(tip.lines, "\n")
True(tipText:find("Icons off", 1, true) ~= nil, "the tooltip says off")
True(tipText:find("Left-click", 1, true) ~= nil and tipText:find("Middle-click", 1, true) ~= nil, "and the clicks")
True(tipText:find("in your group", 1, true) ~= nil, "and the group")
launcher.OnClick(nil, "MiddleButton")
Stub.RunTimers()
Equal(SpotFriendsDB.enabled, true, "middle-click turns them on")
True(table.concat(tip.lines, "\n"):find("Icons on", 1, true) ~= nil, "the open tooltip is redrawn")
Stub.opened = nil
launcher.OnClick(nil, "LeftButton")
Equal(Stub.opened, "SpotFriends", "left-click opens the settings")
local minimapBox = Stub.FindText("Show the minimap button").parent
minimapBox:Click()
Equal(SpotFriendsDB.minimap.hide, true, "the button hidden")
Equal(registered.shown, false, "LibDBIcon told")
minimapBox:Click()
Equal(registered.shown, true, "shown again")

-- /sf plate and /sf debug with the new parts.
local before = #Stub.chat
SlashCmdList.SPOTFRIENDS("plate")
True(#Stub.chat > before, "plate prints")
for i = before + 1, #Stub.chat do True(not Stub.chat[i]:find("could not read", 1, true), "plate: " .. Stub.chat[i]) end
before = #Stub.chat
SlashCmdList.SPOTFRIENDS("debug")
local printed = table.concat(Stub.chat, "\n", before + 1)
True(printed:find("group: marking on", 1, true) ~= nil, "debug shows the group")
True(printed:find("MENU_UNIT_TARGET", 1, true) ~= nil, "debug shows the menus")
True(printed:find("minimap button: shown", 1, true) ~= nil, "debug shows the minimap button")

-- The plate leaves.
Stub.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
True(not holder:IsShown(), "hidden when the plate leaves")

-- Nothing went wrong along the way.
for _, line in ipairs(Stub.chat) do
	True(not line:find("settings page:", 1, true), "no settings page error: " .. line)
	True(not line:find("could not be updated", 1, true), "no nameplate error: " .. line)
end
Equal(SF.Nameplates.errors, 0, "no nameplate errors")
Equal(#SF.missingEvents, 0, "every event registered")

Expect.Done("addon")
