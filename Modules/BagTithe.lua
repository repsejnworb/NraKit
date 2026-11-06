local _, ns = ...

-- Bag Tithe: a button next to the bag sort button that highlights the bag slots
-- worth the least when sold (vendor price x stack size), so you know what to sell
-- or destroy when your bags are full.
--
-- Purely an overlay: we add non-interactive textures/text on top of Blizzard's
-- item buttons and never change how they behave, so clicking, dragging, using
-- and equipping work as normal. Works with separate and combined bags, because
-- Blizzard moves the same sort button between them and we follow it.

local module = {
	key = "bagTithe",
	section = "Bags",
	name = "Bag Tithe",
	description = "Adds a button next to the bag sort button that highlights your least valuable bag slots (vendor price times stack size), so you know what to sell or destroy when your bags are full. Alt+click an item while it's active to leave it out of the ranking.",
	default = false,
	options = {
		{
			key = "bagTitheCount",
			header = "General",
			type = "number",
			name = "Slots to highlight",
			description = "How many of the least valuable slots to highlight.",
			default = 5, min = 1, max = 20, step = 1,
		},
		{
			key = "bagTitheShowRank",
			name = "Show rank number",
			description = "Show a number on each highlighted slot: 1 is the least valuable.",
			default = true,
		},
		{
			key = "bagTitheRankSize",
			parent = "bagTitheShowRank",
			type = "number",
			name = "Rank number size",
			description = "Font size of the rank number.",
			default = 18, min = 10, max = 28, step = 1,
		},
		{
			-- Key kept from when this was the only tint option, so existing settings carry over.
			key = "bagTitheShowTint",
			name = "Tint icon border",
			description = "Color the border of each highlighted slot from red (least valuable) to yellow.",
			default = true,
		},
		{
			key = "bagTitheTintIcon",
			name = "Tint whole icon",
			description = "Wash the whole icon of each highlighted slot in its red-to-yellow color. Can be combined with the border tint.",
			default = true,
		},
		{
			key = "bagTitheTintOpacity",
			parent = "bagTitheTintIcon",
			type = "number",
			name = "Icon tint opacity",
			description = "How strongly the whole-icon tint covers the icon.",
			default = 35, min = 5, max = 90, step = 5, format = "%d%%",
		},
		{
			key = "bagTitheShowValue",
			name = "Show sell value",
			description = "Show what the whole slot sells for (vendor price times stack size).",
			default = true,
		},
		{
			key = "bagTitheAltClick",
			header = "Ignore list",
			name = "Alt+click to ignore items",
			description = "While Bag Tithe is active, Alt+left-click an item to leave it out of the ranking, or to put it back. Ignored items are remembered on all your characters.",
			default = true,
		},
	},
}

local IGNORE_KEY = "bagTitheIgnore"
local SEARCH_BOX_SHRINK = 32
local DIM_ALPHA = 0.7
local BUTTON_ICON = "Interface\\Icons\\INV_Misc_Coin_01"
-- The sort button is 28x26 with its broom drawn at roughly 20px inside a frame.
local BUTTON_WIDTH, BUTTON_HEIGHT = 28, 26
local BUTTON_ICON_SIZE = 20
local IGNORED_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
-- Rank numbers use the standard game font with a thick outline so they stay
-- readable on top of any item icon.
local RANK_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local active = false
local refreshQueued = false
local tithe = {} -- shared with the ignore list page
ns.BagTithe = tithe

-- item button -> our overlay frame
local overlays = {}
local hookedButtons = {}
local hookedFrames = {}
local titheButton

---------------------------------------------------------------------------
-- Ignore list (account-wide, keyed by item ID)
---------------------------------------------------------------------------

function tithe:GetIgnoreList()
	NraKitDB[IGNORE_KEY] = NraKitDB[IGNORE_KEY] or {}
	return NraKitDB[IGNORE_KEY]
end

function tithe:IsIgnored(itemID)
	return itemID and self:GetIgnoreList()[itemID] == true
end

function tithe:SetIgnored(itemID, ignored)
	if itemID then
		self:GetIgnoreList()[itemID] = ignored and true or nil
		self:Changed()
	end
end

function tithe:ClearIgnoreList()
	wipe(self:GetIgnoreList())
	self:Changed()
end

-- Callbacks for the ignore list page.
tithe.listeners = {}
function tithe:Changed()
	for _, listener in ipairs(self.listeners) do
		listener()
	end
	module:QueueRefresh()
end

---------------------------------------------------------------------------
-- Ranking
---------------------------------------------------------------------------

-- Inline coin icons, using the same atlases as Blizzard's money frames.
local COIN_ICON_SIZE = 11
local GOLD_ICON = CreateAtlasMarkup("coin-gold", COIN_ICON_SIZE, COIN_ICON_SIZE, 1, 0)
local SILVER_ICON = CreateAtlasMarkup("coin-silver", COIN_ICON_SIZE, COIN_ICON_SIZE, 1, 0)
local COPPER_ICON = CreateAtlasMarkup("coin-copper", COIN_ICON_SIZE, COIN_ICON_SIZE, 1, 0)

-- Compact value in the largest coin, e.g. 85[c], 4.2[s], 12[g], to fit on an item icon.
local function FormatValue(copper)
	local function compact(amount, icon)
		if amount >= 10 then
			return string.format("%d%s", amount, icon)
		end
		return (string.format("%.1f", amount):gsub("%.0$", "")) .. icon
	end
	if copper >= 10000 then
		return compact(copper / 10000, GOLD_ICON)
	elseif copper >= 100 then
		return compact(copper / 100, SILVER_ICON)
	end
	return string.format("%d%s", copper, COPPER_ICON)
end

local function SlotKey(bag, slot)
	return bag * 1000 + slot
end

-- Returns slot key -> { rank, value }, and whether some prices are still loading.
local function RankSlots()
	local candidates = {}
	local pending = false
	for bag = Enum.BagIndex.Backpack, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and not info.hasNoValue and not tithe:IsIgnored(info.itemID) then
				local sellPrice = select(11, C_Item.GetItemInfo(info.hyperlink or info.itemID))
				if sellPrice == nil then
					pending = true
					C_Item.RequestLoadItemDataByID(info.itemID)
				elseif sellPrice > 0 then
					table.insert(candidates, {
						key = SlotKey(bag, slot),
						value = sellPrice * math.max(info.stackCount or 1, 1),
					})
				end
			end
		end
	end
	table.sort(candidates, function(a, b)
		if a.value ~= b.value then
			return a.value < b.value
		end
		return a.key < b.key
	end)

	local ranked = {}
	local count = math.min(ns:GetValue("bagTitheCount") or 5, #candidates)
	for rank = 1, count do
		ranked[candidates[rank].key] = { rank = rank, value = candidates[rank].value, total = count }
	end
	return ranked, pending
end

---------------------------------------------------------------------------
-- Overlays
---------------------------------------------------------------------------

local function OnItemButtonClick(itemButton, mouseButton)
	if not active or mouseButton ~= "LeftButton" or not IsAltKeyDown()
		or not ns:GetOption("bagTitheAltClick") then
		return
	end
	-- Alt+left-click has no default action on bag items, so this doesn't clash.
	local itemID = C_Container.GetContainerItemID(itemButton:GetBagID(), itemButton:GetID())
	if itemID then
		tithe:SetIgnored(itemID, not tithe:IsIgnored(itemID))
	end
end

local function GetOverlay(itemButton)
	local overlay = overlays[itemButton]
	if overlay then
		return overlay
	end
	overlay = CreateFrame("Frame", nil, itemButton)
	overlay:SetAllPoints(itemButton)
	overlay:SetFrameLevel(itemButton:GetFrameLevel() + 5)

	overlay.dim = overlay:CreateTexture(nil, "OVERLAY", nil, 1)
	overlay.dim:SetAllPoints()
	overlay.dim:SetColorTexture(0, 0, 0, DIM_ALPHA)

	overlay.wash = overlay:CreateTexture(nil, "OVERLAY", nil, 1)
	overlay.wash:SetAllPoints()
	overlay.wash:SetColorTexture(1, 1, 1)

	overlay.border = overlay:CreateTexture(nil, "OVERLAY", nil, 2)
	overlay.border:SetTexture("Interface\\Common\\WhiteIconFrame")
	overlay.border:SetAllPoints()

	overlay.ignored = overlay:CreateTexture(nil, "OVERLAY", nil, 3)
	overlay.ignored:SetTexture(IGNORED_ICON)
	overlay.ignored:SetSize(14, 14)
	overlay.ignored:SetPoint("TOPRIGHT", -1, -1)

	overlay.rank = overlay:CreateFontString(nil, "OVERLAY")
	overlay.rank:SetFont(RANK_FONT, 18, "THICKOUTLINE")
	overlay.rank:SetShadowColor(0, 0, 0, 1)
	overlay.rank:SetShadowOffset(1, -1)
	overlay.rank:SetPoint("BOTTOMLEFT", 1, 1)

	overlay.value = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	overlay.value:SetPoint("TOP", 0, -2)
	overlay.value:SetTextColor(1, 1, 1)

	overlays[itemButton] = overlay

	if not hookedButtons[itemButton] then
		hookedButtons[itemButton] = true
		itemButton:HookScript("OnClick", OnItemButtonClick)
	end
	return overlay
end

-- Red for rank 1, shading to yellow for the last highlighted rank.
local function RankColor(rank, total)
	local t = total > 1 and (rank - 1) / (total - 1) or 0
	return 1, t, 0
end

local function ApplyOverlay(itemButton, ranked)
	local bag, slot = itemButton:GetBagID(), itemButton:GetID()
	if not bag or not slot then
		return
	end
	local overlay = GetOverlay(itemButton)
	local entry = ranked[SlotKey(bag, slot)]

	overlay.ignored:SetShown(tithe:IsIgnored(C_Container.GetContainerItemID(bag, slot)))
	if not entry then
		overlay.dim:Show()
		overlay.border:Hide()
		overlay.wash:Hide()
		overlay.rank:Hide()
		overlay.value:Hide()
	else
		local r, g, b = RankColor(entry.rank, entry.total)
		overlay.dim:Hide()
		overlay.border:SetVertexColor(r, g, b)
		overlay.border:SetShown(ns:GetOption("bagTitheShowTint"))
		overlay.wash:SetVertexColor(r, g, b, (ns:GetValue("bagTitheTintOpacity") or 35) / 100)
		overlay.wash:SetShown(ns:GetOption("bagTitheTintIcon"))
		overlay.rank:SetFont(RANK_FONT, ns:GetValue("bagTitheRankSize") or 18, "THICKOUTLINE")
		overlay.rank:SetText(entry.rank)
		overlay.rank:SetTextColor(1, 1, 1) -- constant color reads fastest; the border carries the tint
		overlay.rank:SetShown(ns:GetOption("bagTitheShowRank"))
		overlay.value:SetText(FormatValue(entry.value))
		overlay.value:SetShown(ns:GetOption("bagTitheShowValue"))
	end
	overlay:Show()
end

local function HideAllOverlays()
	for _, overlay in pairs(overlays) do
		overlay:Hide()
	end
end

local function Refresh()
	refreshQueued = false
	if not active or not ns:IsModuleEnabled(module.key) then
		HideAllOverlays()
		return
	end
	local ranked, pending = RankSlots()
	if pending then
		-- Rank only once every price is known, so nothing is highlighted wrongly.
		HideAllOverlays()
		return
	end
	HideAllOverlays()
	for _, frame in ContainerFrameUtil_EnumerateContainerFrames() do
		if frame:IsShown() then
			for _, itemButton in frame:EnumerateValidItems() do
				ApplyOverlay(itemButton, ranked)
			end
		end
	end
end

function module:QueueRefresh()
	if not refreshQueued then
		refreshQueued = true
		C_Timer.After(0, Refresh)
	end
end

---------------------------------------------------------------------------
-- Button next to the sort button
---------------------------------------------------------------------------

local function SetActive(value)
	active = value
	if titheButton then
		titheButton.activeGlow:SetShown(active)
	end
	module:QueueRefresh()
end

local function CreateTitheButton()
	-- Parented to the sort button, so it shows and moves with it in both bag modes.
	-- Same footprint as the sort button, with the icon inset to the size of its broom.
	local button = CreateFrame("Button", nil, BagItemAutoSortButton)
	button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
	button:SetPoint("RIGHT", BagItemAutoSortButton, "LEFT", -2, 0)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(BUTTON_ICON)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetSize(BUTTON_ICON_SIZE, BUTTON_ICON_SIZE)
	icon:SetPoint("CENTER")
	button.icon = icon

	-- Nudge the icon on press, like Blizzard's buttons.
	button:SetScript("OnMouseDown", function()
		icon:SetPoint("CENTER", 1, -1)
	end)
	button:SetScript("OnMouseUp", function()
		icon:SetPoint("CENTER")
	end)

	-- Same highlight as the sort button.
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	highlight:SetBlendMode("ADD")
	highlight:SetSize(BUTTON_ICON_SIZE + 4, BUTTON_ICON_SIZE + 4)
	highlight:SetPoint("CENTER")

	button.activeGlow = button:CreateTexture(nil, "OVERLAY")
	button.activeGlow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	button.activeGlow:SetBlendMode("ADD")
	button.activeGlow:SetSize(BUTTON_ICON_SIZE + 4, BUTTON_ICON_SIZE + 4)
	button.activeGlow:SetPoint("CENTER")
	button.activeGlow:Hide()

	button:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		SetActive(not active)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, "Bag Tithe")
		GameTooltip_AddNormalLine(GameTooltip, string.format(
			"Highlight your %d least valuable bag slots.", ns:GetValue("bagTitheCount") or 5))
		if ns:GetOption("bagTitheAltClick") then
			GameTooltip_AddInstructionLine(GameTooltip, "Alt+click an item to ignore it.")
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	-- Closing the bags turns Tithe off again.
	button:SetScript("OnHide", function()
		if active then
			SetActive(false)
		end
	end)
	return button
end

-- Make room for our button by narrowing the search box.
local function OnSetSearchBoxPoint(_, searchBox)
	if ns:IsModuleEnabled(module.key) then
		searchBox:SetWidth(searchBox:GetWidth() - SEARCH_BOX_SHRINK)
	end
end

local function HookContainerFrame(frame)
	if not frame or hookedFrames[frame] then
		return
	end
	hookedFrames[frame] = true
	if frame.SetSearchBoxPoint then
		hooksecurefunc(frame, "SetSearchBoxPoint", OnSetSearchBoxPoint)
	end
	if frame.UpdateItems then
		hooksecurefunc(frame, "UpdateItems", function()
			if active then
				module:QueueRefresh()
			end
		end)
	end
end

local function UpdateSearchBoxLayout()
	local anchorBag = BagItemSearchBox and BagItemSearchBox.anchorBag
	if anchorBag and anchorBag.UpdateSearchBox then
		anchorBag:UpdateSearchBox()
	end
end

---------------------------------------------------------------------------
-- Module lifecycle
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event)
	if active then
		module:QueueRefresh()
	end
end)

function module:OnInitialize()
	titheButton = CreateTitheButton()
	HookContainerFrame(ContainerFrameCombinedBags)
	for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
		HookContainerFrame(frame)
	end
	self:OnEnabledChanged(ns:IsModuleEnabled(self.key))
end

function module:OnEnabledChanged(enabled)
	if enabled then
		eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
		eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	else
		eventFrame:UnregisterAllEvents()
		SetActive(false)
	end
	if titheButton then
		titheButton:SetShown(enabled)
	end
	UpdateSearchBoxLayout()
end

function module:OnOptionChanged()
	self:QueueRefresh()
end

function module:OnSettingsRegistered(rootCategory, _, sublayout)
	local page = tithe:CreateIgnoreListPage()
	local pageCategory = Settings.RegisterCanvasLayoutSubcategory(rootCategory, page, "Bag Tithe ignore list")
	if sublayout then
		sublayout:AddInitializer(CreateSettingsButtonInitializer("Ignored items", "Edit ignore list", function()
			Settings.OpenToCategory(pageCategory:GetID())
		end, "Show and edit the items Bag Tithe leaves out of the ranking.", true))
	end
end

ns:RegisterModule(module)
