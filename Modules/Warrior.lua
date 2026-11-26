local _, ns = ...

-- Warrior: QoL for warriors (the Classes section has one module per class).
--
-- Tactical Mastery mark: the rage bar in the Personal Resource Display gets a small arrow
-- where the rage you keep when changing stance ends.
--
-- On Forever, the Tactical Mastery passive (1310185, "You retain up to 10 Rage when you
-- change Stances") keeps 10, and the Improved Tactical Mastery talent (12295, "an
-- additional 15") adds 5 per rank (Wowhead: 5/10/15). The rank is read from the active
-- talent loadout, so learning the passive, respeccing or switching loadouts moves the arrow.
--
-- The mark is NraKit's own bar over the rage bar; the rage bar itself is never changed.
--
-- Proc alerts: the game shows no proc glow on Forever for Overpower, Revenge, Victory Rush
-- and Execute, so they're registered with NraKit's shared proc alerts (ProcAlerts.lua).

local module = {
	key = "warrior",
	section = "Classes",
	subsection = "Warrior",
	name = "Warrior",
	description = "Small things for warriors: a mark on your rage bar where the rage you keep on changing stance ends, and a glow when Overpower, Revenge, Victory Rush or Execute can be used.",
	default = false,
	options = {
		{
			key = "warriorTacticalMastery",
			name = "Tactical Mastery mark",
			description = "The rage bar of the Personal Resource Display shows a small arrow at how much rage you keep when you change stance (Tactical Mastery, plus Improved Tactical Mastery's ranks). It follows what you've learned and your talents by itself.",
			default = true,
		},
		{
			key = "warriorTacticalMasteryShade",
			parent = "warriorTacticalMastery",
			name = "Shade the rage you keep",
			description = "Also lightly shade the bar up to the mark, not just the arrow.",
			default = false,
		},
		{
			key = "warriorTacticalMasteryPosition",
			parent = "warriorTacticalMastery",
			type = "choice",
			name = "Arrow",
			description = "Where the arrow sits: inside the bar at its top (pointing down), at its bottom (pointing up), or both.",
			default = "top",
			choices = {
				{ "top", "Top" },
				{ "bottom", "Bottom" },
				{ "both", "Top and bottom" },
			},
		},
		{
			key = "warriorTacticalMasterySize",
			parent = "warriorTacticalMastery",
			type = "number",
			name = "Arrow size",
			description = "How big the arrow is.",
			default = 1,
			min = 0.5,
			max = 2,
			step = 0.1,
			format = function(value)
				return math.floor(value * 100 + 0.5) .. "%"
			end,
		},
		{
			key = "warriorProcs",
			header = "Proc Alerts",
			name = "Glow when a proc can be used",
			description = "Your action button glows (like the game's own proc glow) while Overpower, Revenge, Victory Rush or Execute can be used, which the game doesn't show for them. Bright: press it now. Dim: it's up, but you're short of rage or it's on cooldown.",
			default = true,
		},
		{
			key = "warriorProcOverpower",
			parent = "warriorProcs",
			name = "Overpower",
			description = "After your target dodges (Battle Stance).",
			default = true,
		},
		{
			key = "warriorProcRevenge",
			parent = "warriorProcs",
			name = "Revenge",
			description = "After you block, dodge or parry (Defensive Stance).",
			default = true,
		},
		{
			key = "warriorProcVictoryRush",
			parent = "warriorProcs",
			name = "Victory Rush",
			description = "After you kill an enemy that gives experience or honor.",
			default = true,
		},
		{
			key = "warriorProcExecute",
			parent = "warriorProcs",
			name = "Execute",
			description = "While your target is low enough on health to Execute.",
			default = true,
		},
		{
			key = "warriorProcCountdown",
			parent = "warriorProcs",
			name = "Time left",
			description = "A thin gold bar along the bottom of the button drains as the proc runs out, turning orange (and the glow pulsing) at the end; long ones (Victory Rush) also count down the seconds. Victory Rush's time comes from its buff; Overpower's and Revenge's NraKit learns the first time one runs out unused, so their bar shows from then on.",
			default = true,
		},
		{
			key = "warriorProcIcon",
			parent = "warriorProcs",
			name = "Icon by the rage bar",
			description = "Also show the proc's icon next to the Personal Resource Display's rage bar, for when you don't watch your action bars.",
			default = false,
		},
		{
			key = "warriorProcSound",
			parent = "warriorProcs",
			name = "Sound",
			description = "Play a sound when a proc can be used.",
			default = false,
		},
		{
			key = "warriorProcSoundChoice",
			parent = "warriorProcSound",
			type = "sound",
			name = "Sound",
			description = "Which sound to play when a proc can be used.",
			default = "kit:MAP_PING",
		},
	},
}

local PASSIVE_SPELL = 1310185 -- Tactical Mastery: keep 10
local PASSIVE_RAGE = 10
local TALENT_SPELL = 12295 -- Improved Tactical Mastery: 5 more per rank
local TALENT_RAGE_PER_RANK = 5
local SLIDE_SECONDS = 0.4
local FADE_SECONDS = 0.4
local ARROW_SIZE = 10
-- The arrow is drawn in the upper part of its picture: measured from screenshots, at 100%
-- this offset puts its top on the first row inside the bar's border. It scales with the
-- arrow, and the bottom arrow (the picture flipped) mirrors it.
local ARROW_OFFSET_Y = -4

local mark = {}
ns.tacticalMastery = mark

-- The talent's rank in the active loadout (0 if not taken).
function mark.TalentRank()
	if type(C_ClassTalents) ~= "table" or type(C_Traits) ~= "table" then
		return 0
	end
	local configID = C_ClassTalents.GetActiveConfigID()
	local config = configID and C_Traits.GetConfigInfo(configID)
	for _, treeID in ipairs(config and config.treeIDs or {}) do
		for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
			local node = C_Traits.GetNodeInfo(configID, nodeID)
			for _, entryID in ipairs(node and node.entryIDs or {}) do
				local entry = C_Traits.GetEntryInfo(configID, entryID)
				local definition = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
				if definition and definition.spellID == TALENT_SPELL then
					return node.activeRank or node.currentRank or 0
				end
			end
		end
	end
	return 0
end

-- The rage kept when changing stance.
function mark.Retained()
	if not IsPlayerSpell(PASSIVE_SPELL) then
		return 0
	end
	return PASSIVE_RAGE + TALENT_RAGE_PER_RANK * mark.TalentRank()
end

local overlay -- on the rage bar: its fill is the shade, with the arrow
local retained = 0
local shownRage -- where the arrow is drawn now, in rage (slides to the target)

local function PowerBar()
	local frame = PersonalResourceDisplayFrame
	return type(frame) == "table" and frame.PowerBar or nil
end

local function IsWarriorRage()
	local _, class = UnitClass("player")
	return class == "WARRIOR" and UnitPowerType("player") == Enum.PowerType.Rage
end

local function WantMark()
	return retained > 0 and PowerBar() ~= nil and IsWarriorRage()
end

-- Max rage is a secret value, so Lua can't work out where on the bar the mark goes. A bar
-- can take secrets though: the mark is NraKit's own bar over the rage bar, 0 to max rage,
-- filled to the rage kept, and the arrow sits at the end of its fill.
local function Draw(rage)
	overlay:SetMinMaxValues(0, UnitPowerMax("player", Enum.PowerType.Rage))
	overlay:SetValue(rage)
	overlay:SetStatusBarColor(1, 1, 1, ns:GetOption("warriorTacticalMasteryShade") and 0.12 or 0)
end

-- The arrows' place and size, from the options.
local function PlaceArrows()
	local scale = ns:GetValue("warriorTacticalMasterySize") or 1
	local size, offset = ARROW_SIZE * scale, ARROW_OFFSET_Y * scale
	local position = ns:GetValue("warriorTacticalMasteryPosition") or "top"
	overlay.top:SetSize(size, size)
	overlay.top:ClearAllPoints()
	overlay.top:SetPoint("CENTER", overlay.fill, "TOPRIGHT", 0, offset)
	overlay.top:SetShown(position ~= "bottom")
	overlay.bottom:SetSize(size, size)
	overlay.bottom:ClearAllPoints()
	overlay.bottom:SetPoint("CENTER", overlay.fill, "BOTTOMRIGHT", 0, -offset)
	overlay.bottom:SetShown(position ~= "top")
end

local function EnsureOverlay()
	local bar = PowerBar()
	if overlay or not bar then
		return overlay
	end
	overlay = CreateFrame("StatusBar", nil, bar)
	overlay:SetAllPoints(bar)
	overlay:SetFrameLevel(bar:GetFrameLevel() + 5)
	overlay:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	overlay:SetAlpha(0)
	overlay:Hide()
	local fill = overlay:GetStatusBarTexture()

	-- Small metal arrows inside the bar pointing at the mark: down from the top, up from the bottom.
	overlay.top = overlay:CreateTexture(nil, "OVERLAY")
	overlay.top:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	overlay.bottom = overlay:CreateTexture(nil, "OVERLAY")
	overlay.bottom:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	overlay.bottom:SetTexCoord(0, 1, 1, 0)
	overlay.fill = fill

	-- Slides when the amount changes, fades in and out when the mark comes and goes.
	overlay:SetScript("OnUpdate", function(self, elapsed)
		local alpha = self:GetAlpha()
		if WantMark() then
			if not shownRage then
				shownRage = retained
			end
			local step = math.max(math.abs(retained - shownRage), 1) * elapsed / SLIDE_SECONDS
			if math.abs(retained - shownRage) <= step then
				shownRage = retained
			else
				shownRage = shownRage + (retained > shownRage and step or -step)
			end
			Draw(shownRage)
			self:SetAlpha(math.min(1, alpha + elapsed / FADE_SECONDS))
		else
			alpha = math.max(0, alpha - elapsed / FADE_SECONDS)
			self:SetAlpha(alpha)
			if alpha == 0 then
				shownRage = nil
				self:Hide()
			end
		end
	end)
	return overlay
end

---------------------------------------------------------------------------
-- Proc alerts
---------------------------------------------------------------------------

ns.procAlerts.Register({
	key = "warrior",
	IsEnabled = function()
		return ns:IsModuleEnabled(module.key) and ns:GetOption("warriorProcs") and select(2, UnitClass("player")) == "WARRIOR"
	end,
	spells = {
		{ name = "Overpower", option = "warriorProcOverpower" },
		{ name = "Revenge", option = "warriorProcRevenge" },
		{ name = "Victory Rush", option = "warriorProcVictoryRush", aura = "Victorious" }, -- buff 402975, 20 sec
		{ name = "Execute", option = "warriorProcExecute", timed = false },
	},
	options = {
		countdown = "warriorProcCountdown",
		icon = "warriorProcIcon",
		sound = "warriorProcSound",
		soundChoice = "warriorProcSoundChoice",
	},
})

---------------------------------------------------------------------------
-- Tactical Mastery mark
---------------------------------------------------------------------------

local function Update()
	if not ns:IsModuleEnabled(module.key) or not ns:GetOption("warriorTacticalMastery") then
		retained = 0
	else
		retained = mark.Retained()
	end
	if EnsureOverlay() then
		PlaceArrows()
		if WantMark() or overlay:IsShown() then
			overlay:Show()
		end
	end
end
mark.Update = Update

-- Where the mark is drawn now (in rage), and how visible (for tests).
function mark.Shown()
	return shownRage, overlay and overlay:IsShown() and overlay:GetAlpha() or 0
end

-- The arrows (for tests).
function mark.Arrows()
	return overlay and overlay.top, overlay and overlay.bottom
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, addonName)
	if event == "ADDON_LOADED" and addonName ~= "Blizzard_PersonalResourceDisplay" then
		return
	end
	Update()
end)

local EVENTS = {
	"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "TRAIT_CONFIG_UPDATED",
	"ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "UPDATE_SHAPESHIFT_FORM",
}

function module:OnInitialize()
	self:OnEnabledChanged(ns:IsModuleEnabled(self.key))
end

function module:OnEnabledChanged(enabled)
	for _, event in ipairs(EVENTS) do
		if enabled then
			eventFrame:RegisterEvent(event)
		else
			eventFrame:UnregisterEvent(event)
		end
	end
	if enabled then
		eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
		eventFrame:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
	else
		eventFrame:UnregisterEvent("UNIT_MAXPOWER")
		eventFrame:UnregisterEvent("UNIT_DISPLAYPOWER")
	end
	Update()
	ns.procAlerts.Refresh()
end

function module:OnOptionChanged()
	Update()
	ns.procAlerts.Refresh()
end

ns:RegisterModule(module)
