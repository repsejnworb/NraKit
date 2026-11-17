local _, ns = ...

-- Known Recipes: marks recipes (and anything else the game calls "Already known",
-- like mounts or pets) at vendors and in your bags, so you don't have to mouse over
-- each one. Optionally also marks recipes you can learn now (green +) or once your
-- skill is high enough (yellow +).
--
-- Everything is read from the item's tooltip data, the same lines the tooltip shows:
--   known        a line equal to ITEM_SPELL_KNOWN ("Already known")
--   later        a red "Requires <profession> (<rank>)" line for a profession you have
--   learnable    a recipe with no red skill requirement
-- A red requirement for a profession you don't have means it isn't for you: no mark.
-- Only the first skill line counts; recipe tooltips can include the crafted item's own.

local module = {
	key = "knownRecipes",
	section = "Recipes",
	name = "Known recipes",
	description = "Marks recipes you already know with a green check at vendors and in your bags, so you don't have to mouse over each one. Also works for anything else the game calls \"Already known\".",
	default = false,
	options = {
		{
			key = "knownRecipesLearnable",
			header = "What to mark",
			name = "Recipes you can learn",
			description = "Mark recipes for your professions that you don't know yet: a green + if you can learn them now, a yellow + if your skill isn't high enough yet.",
			default = true,
		},
		{
			key = "knownRecipesMerchant",
			header = "Where to show",
			name = "Vendors",
			description = "Mark items in vendor windows.",
			default = true,
		},
		{
			key = "knownRecipesDesaturate",
			parent = "knownRecipesMerchant",
			name = "Grey out known items",
			description = "Also show the icon of known items in grey at vendors, so they're easy to skip.",
			default = true,
		},
		{
			key = "knownRecipesBags",
			name = "Bags",
			description = "Mark items in your bags.",
			default = true,
		},
		{
			key = "knownRecipesTithe",
			name = "Known recipes are junk in Bag Tithe",
			description = "Bag Tithe ranks recipes you already know as your least valuable items, whatever they sell for.",
			default = false,
		},
	},
}

local KNOWN = "known"
local LEARNABLE = "learnable"
local LATER = "later"

local CHECK_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local MARK_SIZE = 16
local PLUS_COLORS = {
	[LEARNABLE] = { 0.2, 1, 0.2 },
	[LATER] = { 1, 0.85, 0.1 },
}

local SKILL_PATTERN

local function IsRed(color)
	return color and color.r and color.r > 0.9 and color.g < 0.3 and color.b < 0.3
end

-- Names of the professions (and secondary skills) this character has.
local function GetProfessionNames()
	local names = {}
	if GetProfessions then
		for _, index in pairs({ GetProfessions() }) do
			local name = GetProfessionInfo(index)
			if name then
				names[name] = true
			end
		end
	end
	return names
end

---------------------------------------------------------------------------
-- Item state
---------------------------------------------------------------------------

-- itemID -> state (false when there's nothing to mark)
local cache = {}
local professions

local function ReadState(itemID, data)
	local isRecipe = select(6, C_Item.GetItemInfoInstant(itemID)) == Enum.ItemClass.Recipe
	local skillName, skillRed
	for _, line in ipairs(data.lines or {}) do
		local text = line.leftText
		if text == ITEM_SPELL_KNOWN then
			return KNOWN
		end
		if isRecipe and not skillName and SKILL_PATTERN and text then
			skillName = text:match(SKILL_PATTERN)
			skillRed = skillName and IsRed(line.leftColor)
		end
	end
	if not isRecipe then
		return false
	end
	if not skillName then
		-- No profession requirement (e.g. class books): learnable unless something is red.
		for _, line in ipairs(data.lines or {}) do
			if IsRed(line.leftColor) then
				return false
			end
		end
		return LEARNABLE
	end
	if not skillRed then
		return LEARNABLE
	end
	professions = professions or GetProfessionNames()
	return professions[skillName] and LATER or false
end

-- getData() returns the item's tooltip data; it's only called on a cache miss.
local function GetState(itemID, getData)
	if not itemID then
		return false
	end
	if cache[itemID] ~= nil then
		return cache[itemID]
	end
	if not C_Item.IsItemDataCachedByID(itemID) then
		-- GET_ITEM_INFO_RECEIVED refreshes once it's loaded.
		C_Item.RequestLoadItemDataByID(itemID)
		return false
	end
	local data = getData()
	if not data then
		return false
	end
	local state = ReadState(itemID, data)
	cache[itemID] = state
	return state
end

local function IsShown(state)
	if state == KNOWN then
		return true
	end
	return (state == LEARNABLE or state == LATER) and ns:GetOption("knownRecipesLearnable")
end

---------------------------------------------------------------------------
-- Marks
---------------------------------------------------------------------------

local marks = {}

local function GetMark(button, anchor)
	local mark = marks[button]
	if not mark then
		-- Own frame above the button's children; never takes the mouse.
		mark = CreateFrame("Frame", nil, button)
		mark:SetAllPoints(anchor)
		mark:SetFrameLevel(button:GetFrameLevel() + 6)
		mark.check = mark:CreateTexture(nil, "OVERLAY")
		mark.check:SetTexture(CHECK_TEXTURE)
		mark.check:SetSize(MARK_SIZE, MARK_SIZE)
		mark.check:SetPoint("TOPRIGHT", -1, -1)
		mark.plus = mark:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
		mark.plus:SetText("+")
		mark.plus:SetPoint("TOPRIGHT", -3, -1)
		marks[button] = mark
	end
	return mark
end

local function SetMark(button, state, anchor)
	if not IsShown(state) then
		if marks[button] then
			marks[button]:Hide()
		end
		return
	end
	local mark = GetMark(button, anchor or button)
	mark.check:SetShown(state == KNOWN)
	mark.plus:SetShown(state ~= KNOWN)
	if state ~= KNOWN then
		mark.plus:SetTextColor(unpack(PLUS_COLORS[state]))
	end
	mark:Show()
end

local function HideAllMarks()
	for _, mark in pairs(marks) do
		mark:Hide()
	end
end

---------------------------------------------------------------------------
-- Vendors
---------------------------------------------------------------------------

-- Merchant buttons we greyed out, so we only undo our own desaturation.
local desaturated = {}

local function SetDesaturated(itemButton, on)
	local icon = itemButton.icon or itemButton.Icon
	if not icon then
		return
	end
	if on then
		icon:SetDesaturated(true)
		desaturated[itemButton] = true
	elseif desaturated[itemButton] then
		icon:SetDesaturated(false)
		desaturated[itemButton] = nil
	end
end

local function UpdateMerchant()
	if not MerchantFrame or not MerchantFrame:IsShown() then
		return
	end
	local enabled = ns:IsModuleEnabled(module.key) and ns:GetOption("knownRecipesMerchant")
	local onItemsTab = MerchantFrame.selectedTab == 1
	local numItems = GetMerchantNumItems()
	for i = 1, MERCHANT_ITEMS_PER_PAGE do
		local itemButton = _G["MerchantItem" .. i .. "ItemButton"]
		if itemButton then
			local index = (MerchantFrame.page - 1) * MERCHANT_ITEMS_PER_PAGE + i
			local state = false
			if enabled and onItemsTab and index <= numItems and itemButton:IsShown() then
				state = GetState(GetMerchantItemID(index), function()
					return C_TooltipInfo.GetMerchantItem(index)
				end)
			end
			SetMark(itemButton, state, itemButton.icon or itemButton.Icon)
			SetDesaturated(itemButton, state == KNOWN and ns:GetOption("knownRecipesDesaturate"))
		end
	end
end

---------------------------------------------------------------------------
-- Bags
---------------------------------------------------------------------------

local function UpdateBags()
	local enabled = ns:IsModuleEnabled(module.key) and ns:GetOption("knownRecipesBags")
	ns:ForEachBagItemButton(function(itemButton)
		local state = false
		if enabled then
			local bag, slot = itemButton:GetBagID(), itemButton:GetID()
			state = GetState(C_Container.GetContainerItemID(bag, slot), function()
				return C_TooltipInfo.GetBagItem(bag, slot)
			end)
		end
		SetMark(itemButton, state, itemButton.icon or itemButton.Icon)
	end)
end

---------------------------------------------------------------------------
-- Bag Tithe
---------------------------------------------------------------------------

-- Asked by Bag Tithe: is the item in this slot a known recipe it should rank as junk?
function ns:KnownRecipeIsJunk(bag, slot, itemID)
	if not ns:IsModuleEnabled(module.key) or not ns:GetOption("knownRecipesTithe") then
		return false
	end
	if select(6, C_Item.GetItemInfoInstant(itemID)) ~= Enum.ItemClass.Recipe then
		return false
	end
	return GetState(itemID, function()
		return C_TooltipInfo.GetBagItem(bag, slot)
	end) == KNOWN
end

local function RefreshBagTithe()
	local bagTithe = ns.modules.bagTithe
	if bagTithe and bagTithe.QueueRefresh then
		bagTithe:QueueRefresh()
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

local refreshQueued = false
local function Refresh()
	refreshQueued = false
	UpdateBags()
	UpdateMerchant()
end

local function QueueRefresh()
	if not refreshQueued then
		refreshQueued = true
		C_Timer.After(0, Refresh)
	end
end

local function InvalidateAndRefresh()
	wipe(cache)
	professions = nil
	QueueRefresh()
	RefreshBagTithe()
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event)
	if event == "BAG_UPDATE_DELAYED" or event == "GET_ITEM_INFO_RECEIVED" then
		QueueRefresh()
	else
		-- Learned something, or a skill went up: known / learnable can change.
		InvalidateAndRefresh()
	end
end)

local EVENTS = {
	"BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_TAB",
	"SKILL_LINES_CHANGED", "NEW_MOUNT_ADDED", "NEW_PET_ADDED", "NEW_TOY_ADDED",
}

local function IsEventValid(event)
	return not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event)
end

function module:OnInitialize()
	if ITEM_MIN_SKILL then
		-- "Requires %s (%d)" -> a pattern capturing the profession name in any locale.
		local escaped = ITEM_MIN_SKILL:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
		SKILL_PATTERN = "^" .. escaped:gsub("%%s", "(.+)"):gsub("%%d", "%%d+") .. "$"
	end

	for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
		if frame.UpdateItems then
			hooksecurefunc(frame, "UpdateItems", QueueRefresh)
		end
	end
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags.UpdateItems then
		hooksecurefunc(ContainerFrameCombinedBags, "UpdateItems", QueueRefresh)
	end
	-- Runs after Blizzard sets each button's icon and tint, so our grey stays on top.
	hooksecurefunc("MerchantFrame_UpdateMerchantInfo", UpdateMerchant)
	hooksecurefunc("MerchantFrame_UpdateBuybackInfo", UpdateMerchant)

	self:OnEnabledChanged(ns:IsModuleEnabled(self.key))
end

function module:OnEnabledChanged(enabled)
	for _, event in ipairs(EVENTS) do
		if IsEventValid(event) then
			if enabled then
				eventFrame:RegisterEvent(event)
			else
				eventFrame:UnregisterEvent(event)
			end
		end
	end
	if enabled then
		InvalidateAndRefresh()
	else
		HideAllMarks()
		UpdateMerchant()
		RefreshBagTithe()
	end
end

function module:OnOptionChanged(key)
	if key == "knownRecipesTithe" then
		RefreshBagTithe()
	end
	QueueRefresh()
end

ns:RegisterModule(module)
