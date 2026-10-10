-- Where the icon goes on a nameplate. Pure Lua: given what the plate shows, it answers an anchor
-- and offsets, and the tests check every case without a client.
--
-- Two alignments, as in the mockups: "left" puts the icon just before the name; "right" puts it
-- after the plate (the health bar, or the level badge beside it), or after the name when the
-- plate shows the name alone.
local Layout = {}

Layout.GAP = 2
Layout.INSIDE_BAR = 1   -- NamePlateConstants.NAME_ANCHOR_STYLES.InsideHealthBar

-- state = {
--   nameShown, justify ("LEFT" | "CENTER" | "RIGHT"), textWidth (number or nil when unknown),
--   barShown, style (the name anchor style), raidShown, classShown,
--   badge (the level badge at the bar's right end, shown and laid out, or nil),
--   badgeWidth (its widest shown part, nil when unknown),
-- }
--- Returns anchorTo ("name" | "bar" | "badge" | "raid" | "class"), point, relativePoint, x, y,
--- or nothing when the plate shows nothing the icon could sit beside.
function Layout.Plan(state, position, offsetX, offsetY)
	local gap = Layout.GAP
	local ox, oy = offsetX or 0, offsetY or 0
	local width = state.textWidth
	if position == "right" then
		if state.barShown then
			-- The badge sits at the bar's right end (beside it on Forever, inside its border in
			-- the classic style): after it is after the plate. Its art can be wider than its
			-- frame, so the icon starts half its widest part from its centre.
			if state.badge then
				if state.badgeWidth then
					return "badge", "LEFT", "CENTER", state.badgeWidth / 2 + gap + ox, oy
				end
				return "badge", "LEFT", "RIGHT", gap + ox, oy
			end
			return "bar", "LEFT", "RIGHT", gap + ox, oy
		end
		if not state.nameShown then return end
		local justify = state.justify
		if not width or justify == "RIGHT" then
			return "name", "LEFT", "RIGHT", gap + ox, oy
		elseif justify == "CENTER" then
			return "name", "LEFT", "CENTER", width / 2 + gap + ox, oy
		end
		return "name", "LEFT", "LEFT", width + gap + ox, oy
	end

	-- Inside the bar the name starts at the bar's left edge, where the raid marker and the
	-- classification badge sit too: the icon goes before those instead of under them.
	local besideMarkers = state.barShown and (state.raidShown or state.classShown)
		and (not state.nameShown or state.style == Layout.INSIDE_BAR)
	if state.nameShown and not besideMarkers then
		local justify = state.justify
		if justify == "CENTER" and width then
			return "name", "RIGHT", "CENTER", -(width / 2 + gap) + ox, oy
		elseif justify == "RIGHT" and width then
			return "name", "RIGHT", "RIGHT", -(width + gap) + ox, oy
		end
		return "name", "RIGHT", "LEFT", -gap + ox, oy
	end
	if not state.barShown then return end
	if state.classShown then
		return "class", "RIGHT", "LEFT", -gap + ox, oy
	elseif state.raidShown then
		return "raid", "RIGHT", "LEFT", -gap + ox, oy
	end
	return "bar", "RIGHT", "LEFT", -gap + ox, oy
end

local _, NS = ...
if type(NS) == "table" then NS.Layout = Layout end
return Layout
