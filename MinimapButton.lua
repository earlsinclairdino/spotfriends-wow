-- The minimap button: left-click opens the settings, middle-click turns the icons on or off.
-- Built on LibDataBroker and LibDBIcon (Libs/, loaded by embeds.xml), which keep its angle in
-- SpotFriendsDB.minimap and let it be dragged around the minimap.
local _, SF = ...
local Icons = SF.Icons

local MinimapButton = {}
SF.MinimapButton = MinimapButton

local NAME = "SpotFriends"
local HINT = "|cff66bbff%s|r %s"

local function Libraries()
	if not LibStub then return nil end
	return LibStub("LibDataBroker-1.1", true), LibStub("LibDBIcon-1.0", true)
end

local tooltipShown

local function FillTooltip(tooltip)
	local db = SF.DB()
	tooltip:SetText("SpotFriends")
	if db.enabled then
		tooltip:AddLine("Icons on", 1, 0.82, 0)
	else
		tooltip:AddLine("Icons off", 0.6, 0.6, 0.6)
	end
	local _, bnetOnline, _, ingameOnline = SF.Friends:Counts()
	local group = #(SF.Friends.group or {})
	local status = string.format("%d friends online", bnetOnline + ingameOnline)
	if group > 0 then status = status .. string.format(", %d in your group", group) end
	tooltip:AddLine(status, 0.8, 0.8, 0.8)
	tooltip:AddLine(" ")
	tooltip:AddLine(string.format(HINT, "Left-click", "open settings"), 0.7, 0.7, 0.7)
	tooltip:AddLine(string.format(HINT, "Middle-click", "turn the icons on or off"), 0.7, 0.7, 0.7)
end

function MinimapButton:Toggle()
	local db = SF.DB()
	db.enabled = not db.enabled
	SF.Print(db.enabled and "icons on." or "icons off.")
	SF.Changed()
	-- The tooltip under the cursor says on or off: redraw it.
	if tooltipShown and tooltipShown:IsShown() then
		tooltipShown:ClearLines()
		FillTooltip(tooltipShown)
		tooltipShown:Show()
	end
end

-- LibDBIcon puts every icon in a 17-pixel box at (7, -6), which sits 1.5 pixels left of the
-- ring's hole: unseen on a square icon, plain on a round one. The hole is the button's
-- background disc, 20 pixels at (7, -5); the icon is centred on it. The lib builds a hidden
-- button only when first shown, so this runs after each Refresh too.
local function Centre(icon)
	local button = icon.GetMinimapButton and icon:GetMinimapButton(NAME)
	local texture = button and button.icon
	if not texture or button.spotFriendsCentred then return end
	button.spotFriendsCentred = true
	texture:ClearAllPoints()
	texture:SetSize(18, 18)
	texture:SetPoint("CENTER", button, "TOPLEFT", 17, -15)
end

function MinimapButton:Setup()
	if self.object then return end
	local broker, icon = Libraries()
	if not (broker and icon) then return end
	self.object = broker:NewDataObject(NAME, {
		type = "launcher",
		text = NAME,
		icon = Icons.Path(Icons.FRIEND_DEFAULT),
		OnClick = function(_, mouseButton)
			if mouseButton == "MiddleButton" then
				MinimapButton:Toggle()
			else
				SF.Options:Open()
			end
		end,
		OnTooltipShow = function(tooltip)
			tooltipShown = tooltip
			FillTooltip(tooltip)
		end,
	})
	icon:Register(NAME, self.object, SF.DB().minimap)
	Centre(icon)
end

--- Shows or hides the button as SpotFriendsDB.minimap.hide says.
function MinimapButton:Refresh()
	local _, icon = Libraries()
	if not (icon and self.object) then return end
	icon:Refresh(NAME, SF.DB().minimap)
	Centre(icon)
end

function MinimapButton:SetShown(shown)
	SF.DB().minimap.hide = not shown
	self:Refresh()
end

function MinimapButton:IsShown()
	return not SF.DB().minimap.hide
end
