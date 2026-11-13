local _, ns = ...

-- Shows a large reminder in the middle of the screen while you have unspent talent
-- points. Hidden while dead and (optionally) in combat. Based on EnhanceQoL's
-- "Unspent talent points" reminder.

local module = {
	key = "unspentTalents",
	section = "Reminders",
	name = "Unspent talent points",
	description = "Show a reminder in the middle of the screen while you have talent points to spend.",
	default = false,
	options = {
		{
			key = "unspentTalentsHideInCombat",
			header = "General",
			name = "Hide in combat",
			description = "Don't show the reminder while you're in combat.",
			default = true,
		},
		{
			key = "unspentTalentsShowCount",
			name = "Show number of points",
			description = "Add how many points are unspent, e.g. \"Unspent talent points (2)\".",
			default = true,
		},
		{
			key = "unspentTalentsFontSize",
			header = "Appearance",
			type = "number",
			name = "Text size",
			description = "Font size of the reminder.",
			default = 24, min = 12, max = 48, step = 1,
		},
		{
			key = "unspentTalentsOffsetY",
			type = "number",
			name = "Height on screen",
			description = "How far above (or below, if negative) the middle of the screen the reminder is shown.",
			default = 220, min = -400, max = 400, step = 10,
		},
	},
}

local TEXT = "Unspent talent points"
local COLOR = { 1, 0.75, 0.2 }

local frame, text

local function EnsureFrame()
	if frame then
		return
	end
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(600, 60)
	frame:SetFrameStrata("HIGH")
	frame:EnableMouse(false)
	text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	text:SetAllPoints()
	text:SetTextColor(unpack(COLOR))
	frame:Hide()
end

local function ApplyStyle()
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, ns:GetValue("unspentTalentsOffsetY") or 220)
	local font, _, flags = GameFontNormalLarge:GetFont()
	text:SetFont(font, ns:GetValue("unspentTalentsFontSize") or 24, flags)
end

-- Returns the number of unspent class + spec points (0 if none).
local function GetUnspentPoints()
	if not (C_ClassTalents and C_ClassTalents.HasUnspentTalentPoints) then
		return 0
	end
	local hasPoints, classPoints, specPoints = C_ClassTalents.HasUnspentTalentPoints()
	if not hasPoints then
		return 0
	end
	return math.max((classPoints or 0) + (specPoints or 0), 1)
end

local function Refresh()
	if not ns:IsModuleEnabled(module.key) then
		if frame then
			frame:Hide()
		end
		return
	end
	EnsureFrame()
	ApplyStyle()

	local points = 0
	local hidden = UnitIsDeadOrGhost("player")
		or (ns:GetOption("unspentTalentsHideInCombat") and InCombatLockdown())
	if not hidden then
		points = GetUnspentPoints()
	end
	if points > 0 then
		if ns:GetOption("unspentTalentsShowCount") then
			text:SetText(string.format("%s (%d)", TEXT, points))
		else
			text:SetText(TEXT)
		end
		frame:Show()
	else
		frame:Hide()
	end
end

local refreshQueued = false
local function QueueRefresh()
	if not refreshQueued then
		refreshQueued = true
		C_Timer.After(0, function()
			refreshQueued = false
			Refresh()
		end)
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", QueueRefresh)

local EVENTS = {
	"PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
}

function module:OnInitialize()
	self:OnEnabledChanged(ns:IsModuleEnabled(self.key))
end

function module:OnEnabledChanged(enabled)
	for _, event in ipairs(EVENTS) do
		if enabled then
			-- Not every event exists on every client; skip the ones that don't.
			pcall(eventFrame.RegisterEvent, eventFrame, event)
		else
			eventFrame:UnregisterEvent(event)
		end
	end
	QueueRefresh()
end

function module:OnOptionChanged()
	QueueRefresh()
end

ns:RegisterModule(module)
