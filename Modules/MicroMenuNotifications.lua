local _, ns = ...

-- Micro menu notifications: quiets the blue notification dot on micro menu buttons.
-- The dot is the button's NotificationOverlay frame.
--
-- Shop: Blizzard shows the dot for "new products". We only set the overlay's alpha,
-- so we never fight Blizzard's logic and putting it back is just alpha 1.
--
-- Legacy (Forever only): Blizzard shows the dot while any Legacy challenge is
-- unviewed (LegacyMicroButtonMixin:UpdateNotificationIcon). We show it only while the
-- Legacy Tree has unspent points instead. Every path Blizzard takes ends in
-- SetHasNotification, so we post-hook that and set the overlay to our answer. The
-- points are the tree's trait currency, read the same way Blizzard_LegacySystem's
-- RefreshCachedCurrencyInfo does (that addon is load-on-demand, so we don't use it).

local module = {
	key = "microMenuNotifications",
	section = "Interface",
	name = "Hide Micro Menu Notifications",
	description = "Hides the blue notification dot on micro menu buttons that keep showing it.",
	default = false,
	options = {
		{
			key = "microMenuHideShop",
			name = "Shop",
			description = "Hide the Shop button's \"new products\" dot.",
			default = true,
		},
		{
			key = "microMenuLegacyPoints",
			name = "Legacy: only for unspent points",
			description = "The Legacy button's dot shows only while you have Legacy Tree points to spend, instead of for every new challenge.",
			default = true,
		},
	},
}

-- LegacyTreeData[1].treeID; all Legacy trees share one point pool.
local LEGACY_TREE_ID = 1187

local function SetShopHidden(hidden)
	local overlay = StoreMicroButton and StoreMicroButton.NotificationOverlay
	if overlay then
		overlay:SetAlpha(hidden and 0 or 1)
	end
end

local function HasUnspentLegacyPoints()
	local treeID = LegacyTreeData and LegacyTreeData[1] and LegacyTreeData[1].treeID or LEGACY_TREE_ID
	local configID = C_Traits.GetConfigIDByTreeID(treeID)
	if not configID then
		return false
	end
	-- Points placed in the tree but not applied yet still count as unspent.
	local excludeStagedChanges = true
	local currencies = C_Traits.GetTreeCurrencyInfo(configID, treeID, excludeStagedChanges)
	local info = currencies and currencies[1]
	return info ~= nil and (info.quantity or 0) > 0
end

local function IsLegacyActive()
	return LegacyMicroButton ~= nil and ns:IsModuleEnabled(module.key) and ns:GetOption("microMenuLegacyPoints")
end

local function ApplyLegacy()
	if not IsLegacyActive() then
		return
	end
	local unlocked = not LegacyMicroButton.IsLegacySystemUnlocked or LegacyMicroButton:IsLegacySystemUnlocked()
	LegacyMicroButton.NotificationOverlay:SetShown(unlocked and HasUnspentLegacyPoints())
end

local function Update()
	SetShopHidden(ns:IsModuleEnabled(module.key) and ns:GetOption("microMenuHideShop"))
	if not LegacyMicroButton then
		return
	end
	if IsLegacyActive() then
		ApplyLegacy()
	elseif LegacyMicroButton.UpdateNotificationIcon then
		-- Back to Blizzard's own rule.
		LegacyMicroButton:UpdateNotificationIcon()
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", ApplyLegacy)

local LEGACY_EVENTS = {
	"PLAYER_ENTERING_WORLD", "TRAIT_TREE_CURRENCY_INFO_UPDATED", "TRAIT_CONFIG_UPDATED",
	"MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "ACHIEVEMENT_EARNED",
}

function module:OnInitialize()
	if LegacyMicroButton and LegacyMicroButton.SetHasNotification then
		hooksecurefunc(LegacyMicroButton, "SetHasNotification", ApplyLegacy)
		for _, event in ipairs(LEGACY_EVENTS) do
			if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(event) then
				eventFrame:RegisterEvent(event)
			end
		end
	end
	Update()
end

function module:OnEnabledChanged()
	Update()
end

function module:OnOptionChanged()
	Update()
end

ns:RegisterModule(module)
