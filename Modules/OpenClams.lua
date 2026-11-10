local _, ns = ...

-- Open Clams: a button in the bag's money row (bottom left) that opens the next clam (or any
-- other "Right Click to Open" item) in your bags, one per click. It shows the next
-- item's icon and how many are left. Also bindable to a key.
--
-- Using items is protected, so this is a SecureActionButton that "uses" an item by
-- ID; each click or key press opens one. Its attributes, position and visibility can
-- only change out of combat, so in combat it keeps what it had and catches up after.
-- Using by item ID (not bag slot) means a stale button can only ever open that same
-- kind of container, never use or equip whatever moved into the slot.

local module = {
	key = "openClams",
	section = "Bags",
	name = "Open Clams",
	description = "Adds a button at the bottom left of your bags, next to your money, that opens the next clam or other openable container in your bags, one per click. You can also bind it to a key under Keybindings > AddOns > NraKit.",
	default = false,
	options = {
		{
			key = "openClamsHideEmpty",
			header = "General",
			name = "Hide button when there's nothing to open",
			description = "Only show the button while you have something to open. When off, it stays visible and greyed out.",
			default = true,
		},
		{
			key = "openClamsGlow",
			name = "Highlight openable items",
			description = "Draw a green border around items in your bags that can be opened.",
			default = true,
		},
	},
}

local BUTTON_NAME = "NraKitOpenClamsButton"
local BINDING = "CLICK " .. BUTTON_NAME .. ":LeftButton"
BINDING_HEADER_NRAKIT = "NraKit"
_G["BINDING_NAME_" .. BINDING] = "Open next clam or container"

local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_Shell_03"
-- Fits the money row, which is only about 16px tall.
local BUTTON_SIZE = 18
local BUTTON_ICON_SIZE = 16
local LOCKED_TEXT = LOCKED or "Locked"

local openButton
local nextItem -- { itemID, link, icon } of the item the next click opens
local totalCount = 0
local pendingSecureUpdate = false
local refreshQueued = false
local glows = {}
local hookedFrames = {}

---------------------------------------------------------------------------
-- Finding openable items
---------------------------------------------------------------------------

-- Lockboxes are openable too, but only once picked.
local function IsLocked(bag, slot)
	local data = C_TooltipInfo.GetBagItem(bag, slot)
	for _, line in ipairs(data and data.lines or {}) do
		if line.leftText == LOCKED_TEXT then
			return true
		end
	end
	return false
end

local function IsOpenable(info, bag, slot)
	return info and info.hasLoot and not info.isLocked and not IsLocked(bag, slot)
end

-- Returns the first openable item and the total count, and a set of openable slots.
local function Scan()
	local first, count, slots = nil, 0, {}
	for bag = Enum.BagIndex.Backpack, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if IsOpenable(info, bag, slot) then
				first = first or { itemID = info.itemID, link = info.hyperlink, icon = info.iconFileID }
				count = count + math.max(info.stackCount or 1, 1)
				slots[bag * 1000 + slot] = true
			end
		end
	end
	return first, count, slots
end

---------------------------------------------------------------------------
-- Bag highlights
---------------------------------------------------------------------------

local function GetGlow(itemButton)
	local glow = glows[itemButton]
	if not glow then
		glow = CreateFrame("Frame", nil, itemButton)
		glow:SetAllPoints(itemButton)
		glow:SetFrameLevel(itemButton:GetFrameLevel() + 4)
		local border = glow:CreateTexture(nil, "OVERLAY")
		border:SetTexture("Interface\\Common\\WhiteIconFrame")
		border:SetVertexColor(0.2, 1, 0.3)
		border:SetAllPoints()
		glows[itemButton] = glow
	end
	return glow
end

local function UpdateGlows(slots)
	for _, glow in pairs(glows) do
		glow:Hide()
	end
	if not ns:IsModuleEnabled(module.key) or not ns:GetOption("openClamsGlow") then
		return
	end
	for _, frame in ContainerFrameUtil_EnumerateContainerFrames() do
		if frame:IsShown() then
			for _, itemButton in frame:EnumerateValidItems() do
				local bag, slot = itemButton:GetBagID(), itemButton:GetID()
				if bag and slot and slots[bag * 1000 + slot] then
					GetGlow(itemButton):Show()
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- The button
---------------------------------------------------------------------------

local function UpdateLook()
	openButton.icon:SetTexture(nextItem and nextItem.icon or DEFAULT_ICON)
	openButton.icon:SetDesaturated(not nextItem)
	openButton.count:SetText(totalCount > 0 and totalCount or "")
end

-- The bag that holds the sort button (backpack or combined bags) has the money row we sit in.
local function GetMoneyFrame()
	local bag = BagItemSearchBox and BagItemSearchBox.anchorBag
	return bag and bag:IsVisible() and bag.MoneyFrame
end

-- The secure button is never parented or anchored to Blizzard's bag frames: a protected
-- frame inside them makes them protected too, which can stop Blizzard from closing the
-- bags. It lives on UIParent and is moved over the left of the money row (where there's
-- free space; the money is drawn on the right) by absolute position. Out of combat only;
-- in combat we can only fade it out when the bags close, and fix it up afterwards.
local lastLeft, lastBottom
local function PlaceButton()
	local moneyFrame = GetMoneyFrame()
	local wanted = ns:IsModuleEnabled(module.key) and moneyFrame
		and (nextItem ~= nil or not ns:GetOption("openClamsHideEmpty"))
	if InCombatLockdown() then
		pendingSecureUpdate = true
		openButton:SetAlpha(wanted and 1 or 0)
		return
	end
	local left, bottom = moneyFrame and moneyFrame:GetLeft(), moneyFrame and moneyFrame:GetBottom()
	if not wanted or not left then
		lastLeft, lastBottom = nil, nil
		openButton:Hide()
		return
	end
	lastLeft, lastBottom = left, bottom

	local moneyScale = moneyFrame:GetEffectiveScale()
	openButton:SetScale(moneyScale / UIParent:GetEffectiveScale())
	local toButton = moneyScale / openButton:GetEffectiveScale()
	openButton:ClearAllPoints()
	openButton:SetPoint("LEFT", UIParent, "BOTTOMLEFT",
		left * toButton, (bottom + moneyFrame:GetHeight() / 2) * toButton)
	openButton:SetFrameStrata(moneyFrame:GetFrameStrata())
	openButton:SetFrameLevel(moneyFrame:GetFrameLevel() + 5)
	openButton:SetAlpha(1)
	openButton:Show()
end

-- Follows the bags: an ordinary (not protected) frame on the sort button, so it's shown
-- exactly while the bag with the sort button is, and notices when that bag moves.
local function CreateWatcher()
	local watcher = CreateFrame("Frame", nil, BagItemAutoSortButton)
	watcher:SetScript("OnShow", PlaceButton)
	watcher:SetScript("OnHide", PlaceButton)
	watcher:SetScript("OnUpdate", function()
		if InCombatLockdown() then
			return
		end
		local moneyFrame = GetMoneyFrame()
		local left, bottom = moneyFrame and moneyFrame:GetLeft(), moneyFrame and moneyFrame:GetBottom()
		if left ~= lastLeft or bottom ~= lastBottom then
			PlaceButton()
		end
	end)
end

-- Attributes, position and visibility: protected, so out of combat only.
local function UpdateSecure()
	if InCombatLockdown() then
		pendingSecureUpdate = true
		return
	end
	pendingSecureUpdate = false

	local enabled = ns:IsModuleEnabled(module.key)
	if enabled and nextItem then
		openButton:SetAttribute("type", "item")
		openButton:SetAttribute("item", "item:" .. nextItem.itemID)
	else
		openButton:SetAttribute("type", nil)
		openButton:SetAttribute("item", nil)
	end

	PlaceButton()
end

local function Refresh()
	refreshQueued = false
	local slots
	if ns:IsModuleEnabled(module.key) then
		nextItem, totalCount, slots = Scan()
	else
		nextItem, totalCount, slots = nil, 0, {}
	end
	UpdateLook()
	UpdateSecure()
	UpdateGlows(slots)
	if openButton:IsMouseOver() and GameTooltip:GetOwner() == openButton then
		openButton:GetScript("OnEnter")(openButton)
	end
end

function module:QueueRefresh()
	if not refreshQueued then
		refreshQueued = true
		C_Timer.After(0, Refresh)
	end
end

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, "Open Clams")
	if nextItem then
		GameTooltip_AddNormalLine(GameTooltip, "Click to open: " .. (nextItem.link or ""))
		GameTooltip_AddNormalLine(GameTooltip, string.format("%d left to open.", totalCount))
	else
		GameTooltip_AddDisabledLine(GameTooltip, "Nothing to open.")
	end
	if InCombatLockdown() then
		GameTooltip_AddErrorLine(GameTooltip, "Moves on to the next item after combat.")
	end
	local key = GetBindingKey(BINDING)
	if key then
		GameTooltip_AddInstructionLine(GameTooltip, "Keybind: " .. GetBindingText(key))
	else
		GameTooltip_AddInstructionLine(GameTooltip, "Bind a key under Keybindings > AddOns > NraKit.")
	end
	GameTooltip:Show()
end

local function CreateOpenButton()
	-- See PlaceButton for why this is on UIParent. The keybind clicks it even while hidden.
	local button = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	-- Mouse clicks act on release; key presses follow the "cast on key down" setting.
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:Hide()

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetSize(BUTTON_ICON_SIZE, BUTTON_ICON_SIZE)
	icon:SetPoint("CENTER")
	button.icon = icon

	button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	button.count:SetPoint("LEFT", button, "RIGHT", 2, 0)

	-- Nudge the icon on press, like Blizzard's buttons.
	button:SetScript("OnMouseDown", function()
		icon:SetPoint("CENTER", 1, -1)
	end)
	button:SetScript("OnMouseUp", function()
		icon:SetPoint("CENTER")
	end)

	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	highlight:SetBlendMode("ADD")
	highlight:SetSize(BUTTON_ICON_SIZE + 4, BUTTON_ICON_SIZE + 4)
	highlight:SetPoint("CENTER")

	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

local function HookContainerFrame(frame)
	if not frame or hookedFrames[frame] then
		return
	end
	hookedFrames[frame] = true
	if frame.UpdateItems then
		hooksecurefunc(frame, "UpdateItems", function()
			module:QueueRefresh()
		end)
	end
end

---------------------------------------------------------------------------
-- Module lifecycle
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		if pendingSecureUpdate then
			module:QueueRefresh()
		end
	else
		module:QueueRefresh()
	end
end)

function module:OnInitialize()
	openButton = CreateOpenButton()
	HookContainerFrame(ContainerFrameCombinedBags)
	for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
		HookContainerFrame(frame)
	end
	CreateWatcher()
	self:OnEnabledChanged(ns:IsModuleEnabled(self.key))
end

function module:OnEnabledChanged(enabled)
	if enabled then
		eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
		eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	else
		eventFrame:UnregisterAllEvents()
		-- Still catch up after combat if we were turned off during it.
		eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	end
	if openButton then
		Refresh()
	end
end

function module:OnOptionChanged()
	self:QueueRefresh()
end

ns:RegisterModule(module)
