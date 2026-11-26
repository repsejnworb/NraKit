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

local module = {
	key = "warrior",
	section = "Classes",
	name = "Warrior",
	description = "Small things for warriors: a mark on your rage bar where the rage you keep on changing stance ends.",
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
	},
}

local PASSIVE_SPELL = 1310185 -- Tactical Mastery: keep 10
local PASSIVE_RAGE = 10
local TALENT_SPELL = 12295 -- Improved Tactical Mastery: 5 more per rank
local TALENT_RAGE_PER_RANK = 5
local SLIDE_SECONDS = 0.4
local FADE_SECONDS = 0.4
local ARROW_SIZE = 10
local ARROW_OFFSET_Y = -9.5

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

	-- A small metal arrow inside the bar, at its top, pointing down at the mark. The arrow is
	-- drawn in the upper part of its picture, hence the offset (measured in game).
	overlay.arrow = overlay:CreateTexture(nil, "OVERLAY")
	overlay.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	overlay.arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
	overlay.arrow:SetPoint("CENTER", fill, "TOPRIGHT", 0, ARROW_OFFSET_Y)

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

local function Update()
	if not ns:IsModuleEnabled(module.key) or not ns:GetOption("warriorTacticalMastery") then
		retained = 0
	else
		retained = mark.Retained()
	end
	if EnsureOverlay() and (WantMark() or overlay:IsShown()) then
		overlay:Show()
	end
end
mark.Update = Update

-- Where the mark is drawn now (in rage), and how visible (for tests).
function mark.Shown()
	return shownRage, overlay and overlay:IsShown() and overlay:GetAlpha() or 0
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
end

function module:OnOptionChanged()
	Update()
end

ns:RegisterModule(module)
