local _, ns = ...

-- Alt+click to attach all: with Send Mail open, Alt+left-click an item in your bags to attach
-- every stack of it you carry (4 Small Red Pouches, 5 stacks of Silk Cloth...), as far as the
-- mail's attachment slots go. Soulbound and locked stacks are left out.
--
-- Each stack is picked up and dropped on a free attachment slot (PickupContainerItem,
-- ClickSendMailItemButton), as mail addons do; neither is protected. Alt+left-click has no
-- default action on bag items. The bag buttons are hooked (HookScript) when the mailbox
-- opens, bags are opened and bags change, since they're made when bags are first opened.


local feature = { key = "mailAttachAll" } -- an option of the Mail feature (Mail.lua)

local attach = {}
ns.mailAttachAll = attach

local hooked = {}

-- Whether an Alt+click on a bag item now attaches all of it (Bag Tithe then leaves it alone).
function attach.IsActive()
	return ns.mail.IsOn(feature.key) and SendMailFrame ~= nil and SendMailFrame:IsVisible()
end

-- The bag slots holding this item that can be mailed: { { bag, slot }, ... }.
local function Stacks(itemID)
	local stacks = {}
	for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID == itemID and not info.isLocked and not info.isBound then
				table.insert(stacks, { bag, slot })
			end
		end
	end
	return stacks
end

-- Attaches every stack of the item; returns how many were attached and how many there were.
function attach.AttachAll(itemID)
	local free = {}
	for index = 1, ATTACHMENTS_MAX_SEND or 12 do
		if not HasSendMailItem(index) then
			table.insert(free, index)
		end
	end
	local stacks = Stacks(itemID)
	local attached = 0
	for index, stack in ipairs(stacks) do
		local attachment = free[index]
		if not attachment then
			break
		end
		C_Container.PickupContainerItem(stack[1], stack[2])
		ClickSendMailItemButton(attachment)
		attached = attached + 1
	end
	if attached < #stacks then
		ns:Print(string.format("Attached %d of %d stacks: the mail is full.", attached, #stacks))
	end
	return attached, #stacks
end

local function OnItemClick(itemButton, mouseButton)
	if mouseButton ~= "LeftButton" or not IsAltKeyDown() or not attach.IsActive() or CursorHasItem() then
		return
	end
	local itemID = C_Container.GetContainerItemID(itemButton:GetBagID(), itemButton:GetID())
	if itemID then
		attach.AttachAll(itemID)
	end
end

local function HookButtons()
	ns:ForEachBagItemButton(function(itemButton)
		if not hooked[itemButton] then
			hooked[itemButton] = true
			itemButton:HookScript("OnClick", OnItemClick)
		end
	end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function()
	-- MAIL_SHOW opens your bags right after; BAG_UPDATE_DELAYED covers bags opened later.
	C_Timer.After(0, HookButtons)
end)

function feature.OnEnabledChanged(enabled)
	if enabled then
		eventFrame:RegisterEvent("MAIL_SHOW")
		eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
	else
		eventFrame:UnregisterAllEvents()
	end
end

function feature.OnInitialize()
	for _, name in ipairs({ "OpenAllBags", "ToggleAllBags", "ToggleBackpack", "ToggleBag", "OpenBag" }) do
		if _G[name] then
			hooksecurefunc(name, function()
				if attach.IsActive() then
					C_Timer.After(0, HookButtons)
				end
			end)
		end
	end
	feature.OnEnabledChanged(ns.mail.IsOn(feature.key))
end

ns.mail.Register(feature)
