local ADDON_NAME, SF = ...
local Nameplates, Friends = SF.Nameplates, SF.Friends

local frame = CreateFrame("Frame")
local started = false

local function Start()
	if started then return end
	started = true
	SF.FindCVars()
	Friends:Rebuild()
	Friends:RebuildGroup()
	Nameplates:Start()
	SF.Options:Setup()
	SF.UnitMenu:Setup()
	SF.MinimapButton:Setup()
	Friends:Request()
end

local handlers = {
	ADDON_LOADED = function(name)
		if name == ADDON_NAME then
			SF.InitDB()
			frame:UnregisterEvent("ADDON_LOADED")
		end
	end,
	-- The Settings API and the friend lists are all there by the first one.
	PLAYER_ENTERING_WORLD = function()
		if not started then
			Start()
		else
			Nameplates:Rescan()
			Friends:RebuildSoon()
			Friends:RebuildGroupSoon()
		end
	end,
	NAME_PLATE_UNIT_ADDED = function(unit) Nameplates:OnAdded(unit) end,
	NAME_PLATE_UNIT_REMOVED = function(unit) Nameplates:OnRemoved(unit) end,
	UNIT_NAME_UPDATE = function(unit) Nameplates:OnNameChanged(unit) end,
	PLAYER_TARGET_CHANGED = function() Nameplates:OnTargetChanged() end,
	CVAR_UPDATE = function(name)
		Nameplates:OnCVar(name)
		SF.Options:RefreshSoon()
	end,
	PLAYER_REGEN_ENABLED = function() SF.ApplyQueuedCVars() end,
	GROUP_ROSTER_UPDATE = function() Friends:RebuildGroupSoon() end,
}

local function FriendsChanged() Friends:RebuildSoon() end
for _, event in ipairs(Friends.EVENTS) do handlers[event] = FriendsChanged end

frame:SetScript("OnEvent", function(_, event, ...)
	local handler = handlers[event]
	if handler and (started or event == "ADDON_LOADED" or event == "PLAYER_ENTERING_WORLD") then
		handler(...)
	end
end)

local events = {}
for event in pairs(handlers) do events[#events + 1] = event end
table.sort(events)
SF.RegisterEvents(frame, events)
