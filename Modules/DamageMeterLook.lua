local _, ns = ...

-- Damage Meter Look: a clean, flat look for the game's own damage meter, like NraKit's
-- windows and the Goal Tracker. The header becomes a thin dark strip with a small gold title
-- and small grey buttons (optionally only while the mouse is over the meter); the bars get
-- a flat fill in a toned-down class colour and outlined text.
--
-- Size, style, icons and class colours stay in Edit Mode; this only changes the look on top.
--
-- The meter shows secret values in combat, which Blizzard's code can only handle while it
-- runs untainted. So this never calls the meter's Lua methods or writes its fields: it only
-- post-hooks (hooksecurefunc) and makes widget calls on Blizzard's regions (SetTexture,
-- SetFont, SetAlpha, SetPoint...). The header's clicks always land on Blizzard's own buttons;
-- we hide their art and draw a small glyph on them. Undoing it needs a reload (Blizzard puts
-- its look back only when it builds the meter).

local module = {
	key = "damageMeterLook",
	section = "Interface",
	name = "Damage Meter Look",
	description = "A clean, flat look for the game's damage meter: a thin header with small buttons, flat bars and outlined text. Size, style and colours stay in Edit Mode.",
	default = false,
	options = {
		{
			key = "damageMeterLookHover",
			name = "Header buttons only on hover",
			description = "Show the meter's header buttons (session, settings, minimize) only while the mouse is over the meter.",
			default = true,
		},
	},
}

local FLAT = "Interface\\Buttons\\WHITE8X8"
local HEADER_HEIGHT = 22
local BUTTON_SIZE = 16
local FILL_ALPHA = 0.55 -- the class colour, toned down over the dark background
local GLYPH_COLOR = { 0.7, 0.7, 0.7 }
local DIM_COLOR = { 0.6, 0.6, 0.6 }
local RELOAD_DIALOG = "NRAKIT_DAMAGE_METER_RELOAD"

local applied = false -- skinned this session (only a reload undoes it)
local skinned = setmetatable({}, { __mode = "k" }) -- bar rows we've skinned and hooked
local windows = {} -- session window -> our state: { glyphs, line, arrow }

------------------------------------------------------------------------------
-- Bars
------------------------------------------------------------------------------

local function SkinText(text)
	text:SetFontObject("GameFontHighlightSmall") -- Blizzard's text size setting still scales it
	local file, size = text:GetFont()
	if file then
		text:SetFont(file, size, "OUTLINE")
	end
	text:SetShadowOffset(1, -1)
	text:SetShadowColor(0, 0, 0, 0.6)
end

local function SkinRow(row)
	local bar = row.StatusBar
	if not bar then
		return
	end
	local fill = bar:GetStatusBarTexture()
	if fill then
		fill:SetTexture(FLAT) -- Blizzard colours it with SetVertexColor, which a new file keeps
		fill:SetAlpha(FILL_ALPHA)
	end
	if bar.Background then
		bar.Background:SetColorTexture(1, 1, 1, 0.04)
	end
	if bar.BackgroundEdge then
		bar.BackgroundEdge:Hide()
	end
	if bar.Name then
		SkinText(bar.Name)
	end
	if bar.Value then
		SkinText(bar.Value)
		bar.Value:SetTextColor(0.85, 0.85, 0.85)
	end
	if not skinned[row] then
		skinned[row] = true
		-- Blizzard puts its look back whenever the style changes.
		if type(row.UpdateStyle) == "function" then
			hooksecurefunc(row, "UpdateStyle", SkinRow)
		end
	end
end

-- Blizzard re-initialises every visible row on each meter update: only new rows need us.
local function SkinNewRow(row)
	if not skinned[row] then
		SkinRow(row)
	end
end

------------------------------------------------------------------------------
-- Header
------------------------------------------------------------------------------

-- Hides a frame's own textures (Blizzard's art), except the one we keep.
local function HideArt(frame, keep)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:GetObjectType() == "Texture" and region ~= keep then
			region:SetAlpha(0)
		end
	end
	if frame.GetNormalTexture then
		for _, art in ipairs({ frame:GetNormalTexture(), frame:GetPushedTexture(), frame:GetHighlightTexture() }) do
			art:SetAlpha(0)
		end
	end
end

-- Our look on one of Blizzard's header buttons: its art hidden, a small grey glyph (text or
-- an icon) and a faint highlight. The click stays Blizzard's.
local function Glyph(state, button, text, icon)
	local glyph = state.glyphs[button]
	if not glyph then
		glyph = {}
		state.glyphs[button] = glyph
		if icon then
			glyph.icon = button:CreateTexture(nil, "OVERLAY")
			glyph.icon:SetTexture(icon)
			glyph.icon:SetSize(11, 11)
			glyph.icon:SetPoint("CENTER")
			glyph.icon:SetDesaturated(true)
			glyph.icon:SetVertexColor(unpack(GLYPH_COLOR))
		else
			glyph.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			glyph.text:SetPoint("CENTER", 0, 1)
			glyph.text:SetTextColor(unpack(GLYPH_COLOR))
		end
		local highlight = button:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.08)
		glyph.highlight = highlight
	end
	if glyph.text then
		glyph.text:SetText(text)
	end
	HideArt(button, glyph.icon)
	glyph.highlight:SetAlpha(1)
	button:SetScale(1)
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	return glyph
end

local function SkinHeader(window, state)
	local header = window.Header
	header:SetColorTexture(0.04, 0.04, 0.06, 0.85)
	header:SetHeight(HEADER_HEIGHT) -- the bars are anchored under it, so they move up with it
	if not state.line then
		state.line = window:CreateTexture(nil, "ARTWORK")
		state.line:SetColorTexture(1, 1, 1, 0.1)
		state.line:SetHeight(1)
		state.line:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT")
		state.line:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT")
	end

	-- Right side, all the same size on the strip's middle: minimize, settings, session.
	local minimize, settings, session = window.MinimizeButton, window.SettingsDropdown, window.SessionDropdown
	local right = header
	local function PlaceRight(frame, gap)
		frame:ClearAllPoints()
		frame:SetPoint("RIGHT", right, right == header and "RIGHT" or "LEFT", -gap, 0)
		right = frame
	end
	if minimize then
		Glyph(state, minimize, "-")
		PlaceRight(minimize, 3)
	end
	if settings then
		Glyph(state, settings, nil, "Interface\\Buttons\\UI-OptionsButton")
		PlaceRight(settings, 2)
	end
	if session then
		HideArt(session)
		session:SetScale(1)
		session:SetHeight(BUTTON_SIZE)
		PlaceRight(session, 4)
		if session.SessionName then
			session.SessionName:SetFontObject("GameFontHighlightSmall")
			session.SessionName:SetTextColor(unpack(DIM_COLOR))
		end
	end

	-- Left side: the type as a gold title, then the combat timer. The whole title is the type
	-- button (Blizzard's is only its arrow), with a small arrow after it on hover. The title has
	-- a fixed place; the timer comes and goes after it (and after the arrow's place, which is
	-- always kept), so nothing moves.
	local timer = window.SessionTimer
	local typeButton = window.DamageMeterTypeDropdown
	if typeButton then
		HideArt(typeButton)
		typeButton:SetScale(1)
		typeButton:ClearAllPoints()
		typeButton:SetPoint("LEFT", header, "LEFT", 4, 0)
		typeButton:SetPoint("RIGHT", right, right == header and "RIGHT" or "LEFT", -6, 0)
		typeButton:SetHeight(BUTTON_SIZE)
		local title = typeButton.TypeName
		if title then
			title:SetFontObject("GameFontNormalSmall")
			title:SetTextColor(1, 0.82, 0)
			title:ClearAllPoints()
			title:SetPoint("LEFT", typeButton, "LEFT", 2, 0)
		end
		if not state.arrow then
			state.arrow = typeButton:CreateTexture(nil, "OVERLAY")
			state.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
			state.arrow:SetSize(10, 10)
			state.arrow:SetVertexColor(unpack(GLYPH_COLOR))
			state.arrow:SetPoint("LEFT", title or typeButton, title and "RIGHT" or "LEFT", 3, -2)
			local highlight = typeButton:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetAllPoints()
			highlight:SetColorTexture(1, 1, 1, 0.05)
		end
	end
	if timer then
		timer:SetFontObject("GameFontHighlightSmall")
		timer:SetTextColor(unpack(DIM_COLOR))
		timer:ClearAllPoints()
		if state.arrow then
			timer:SetPoint("LEFT", state.arrow, "RIGHT", 4, 2)
		else
			timer:SetPoint("LEFT", header, "LEFT", 6, 0)
		end
	end
end

-- What fades in on hover: the buttons, the session name and the title's arrow. The title stays.
-- Checked against their actual alpha every time, not a remembered state: something can show
-- them again after we hid them (it did, right after loading).
local function UpdateHover(window, state)
	local shown = not ns:GetOption("damageMeterLookHover") or window:IsMouseOver()
		or (EditModeManagerFrame and EditModeManagerFrame:IsShown())
	local alpha = shown and 1 or 0
	for _, control in pairs({ window.SessionDropdown, window.SettingsDropdown, window.MinimizeButton, state.arrow }) do
		if math.abs(control:GetAlpha() - alpha) > 0.01 then
			control:SetAlpha(alpha)
		end
	end
	-- Minimized or not.
	local glyph = window.MinimizeButton and state.glyphs[window.MinimizeButton]
	local container = window.MinimizeContainer
	if glyph and container then
		glyph.text:SetText(container:IsShown() and "-" or "+")
	end
end

------------------------------------------------------------------------------
-- Windows
------------------------------------------------------------------------------

local function SkinWindow(window)
	local state = windows[window]
	if not state then
		state = { glyphs = {} }
		windows[window] = state
		local container = window.MinimizeContainer
		-- A hairline border of our own. It belongs to the part that hides when minimized, so
		-- only the header strip is left then.
		local border = CreateFrame("Frame", nil, container or window)
		border:SetAllPoints(window)
		local edges = {}
		for i = 1, 4 do
			edges[i] = border:CreateTexture(nil, "OVERLAY")
			edges[i]:SetColorTexture(1, 1, 1, 0.1)
		end
		edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
		edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
		edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
		edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
		-- Hover: our own frame looks every frame (Blizzard does the same for its resize handle).
		local poller = CreateFrame("Frame", nil, window)
		poller:SetScript("OnUpdate", function()
			UpdateHover(window, state)
		end)
		-- New rows, and rows reused for other people.
		hooksecurefunc(window, "InitEntry", function(_, row)
			SkinNewRow(row)
		end)
		hooksecurefunc(window, "SetupEntry", function(_, row)
			SkinNewRow(row)
		end)
		if container and container.Background then
			container.Background:SetColorTexture(0.04, 0.04, 0.06, 1) -- Blizzard's transparency setting still applies
		end
		if container and container.LocalPlayerEntry then
			SkinRow(container.LocalPlayerEntry)
		end
		local scrollBox = container and container.ScrollBox
		if scrollBox and type(scrollBox.ForEachFrame) == "function" then
			scrollBox:ForEachFrame(SkinRow)
		end
	end
	SkinHeader(window, state)
	UpdateHover(window, state)
end

-- The meter's windows: DamageMeterSessionWindow1, 2, ... (more can be opened later).
local function SkinWindows()
	for i = 1, 10 do
		local window = _G["DamageMeterSessionWindow" .. i]
		if type(window) == "table" and window.Header and type(window.InitEntry) == "function" then
			SkinWindow(window)
		end
	end
end

local function Apply()
	if applied or type(DamageMeter) ~= "table" then
		return
	end
	applied = true
	SkinWindows()
	if type(DamageMeter.SetupSessionWindow) == "function" then
		hooksecurefunc(DamageMeter, "SetupSessionWindow", SkinWindows)
	end
end

-- Turning it off: Blizzard's look comes back with a reload.
local function AskReload()
	if type(StaticPopupDialogs) ~= "table" then
		return
	end
	StaticPopupDialogs[RELOAD_DIALOG] = StaticPopupDialogs[RELOAD_DIALOG] or {
		text = "NraKit: reload the interface to get the damage meter's own look back?",
		button1 = "Reload",
		button2 = "Later",
		OnAccept = function()
			ReloadUI()
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}
	StaticPopup_Show(RELOAD_DIALOG)
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, _, addon)
	if addon == "Blizzard_DamageMeter" and ns:IsModuleEnabled(module.key) then
		Apply()
	end
end)

---------------------------------------------------------------------------
-- /nra dps: show or hide the meter, whether or not the look is on. It flips the game's own
-- setting (the damageMeterEnabled CVar, Options > Gameplay); the meter follows it by itself,
-- so its frames are never touched.
---------------------------------------------------------------------------

local ENABLED_CVAR = "damageMeterEnabled"

-- Why the meter may still not show once it's on: its Edit Mode visibility. NraKit leaves that
-- alone (changing it would taint the meter or your Edit Mode layout); set to Always, it's
-- /nra dps alone that decides.
local ALWAYS_HINT = " Set its visibility to Always in Edit Mode, and /nra dps alone decides."

local function VisibilityNote()
	local visibility = DamageMeter and DamageMeter.visibility
	local values = Enum.DamageMeterVisibility
	if not visibility or not values then
		return ""
	elseif visibility == values.InCombat then
		return " It shows in combat only." .. ALWAYS_HINT
	elseif visibility == values.InGroup then
		return " It shows in a group only." .. ALWAYS_HINT
	elseif visibility == values.Hidden then
		return " Edit Mode has it hidden, though." .. ALWAYS_HINT
	end
	return ""
end

local function OnDpsCommand(rest)
	if type(C_DamageMeter) == "table" and C_DamageMeter.IsDamageMeterAvailable and not C_DamageMeter.IsDamageMeterAvailable() then
		ns:Print("The damage meter isn't available here.")
		return
	end
	rest = rest:lower()
	local on
	if rest == "show" or rest == "on" then
		on = true
	elseif rest == "hide" or rest == "off" then
		on = false
	elseif rest == "" then
		on = not C_CVar.GetCVarBool(ENABLED_CVAR)
	else
		ns:PrintCommandHelp("dps")
		return
	end
	C_CVar.SetCVar(ENABLED_CVAR, on and "1" or "0")
	ns:Print(on and ("Damage meter shown." .. VisibilityNote()) or "Damage meter hidden (/nra dps shows it again).")
end

function module:OnInitialize()
	ns:RegisterSlashCommand("dps", OnDpsCommand, {
		summary = "Show or hide the game's damage meter",
		usage = {
			"/nra dps - show or hide it",
			"/nra dps show, /nra dps hide - one or the other",
		},
	})
	eventFrame:RegisterEvent("ADDON_LOADED") -- in case the meter loads after us
	if ns:IsModuleEnabled(module.key) then
		Apply()
	end
end

function module:OnEnabledChanged(enabled)
	if enabled then
		Apply()
	elseif applied then
		AskReload()
	end
end

function module:OnOptionChanged()
	for window, state in pairs(windows) do
		UpdateHover(window, state)
	end
end

ns:RegisterModule(module)
