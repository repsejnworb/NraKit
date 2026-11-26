local _, ns = ...

-- Sell List: taking items from your bank or mail into your bags, while you're at the bank or
-- the mailbox (the list reads them live then, SellList.lua). Click a bank or mail row to take
-- it; with more than one stack, a small panel by the row asks how many (Take All takes what
-- fits). Shift-click takes all that fits without asking.
--
--   Bank   the same as by hand: pick up from the bank slot, put it in a free bag slot that can
--          hold it (C_Container.PickupContainerItem, SplitContainerItem for part of a stack).
--          Nothing protected: "using" the item (Blizzard's right-click) would be, for potions.
--   Mail   TakeInboxItem, one attachment at a time (an attachment is a stack: it can't be
--          split), waiting for each to arrive; mail numbers shift as mails empty, so the
--          inbox is read again before each. C.O.D. mail is never listed (SellList.lua).
--
-- One thing at a time; progress and the result show in the list's footer (sell.TakeStatus).

local UI = ns.UI
local sell = ns.sellList

local STEP_SECONDS = 0.2 -- between bank moves
local MAIL_WAIT_SECONDS = 0.5 -- at least this between mail takes, and until the inbox updates

local job -- { item, where, want (items or attachments), done, maxStack, targets = { "bag:slot" = true } }
local status -- the footer's line about taking: "Taking 2 of 5...", "Took 3 stacks", ...

function sell.TakeStatus()
	return status
end

local function SetStatus(text)
	status = text
	if sell.onTakeStatus then
		sell.onTakeStatus()
	end
end

local function MaxStack(item)
	local stack = select(8, C_Item.GetItemInfo(item.link or item.id))
	return math.max(stack or 1, 1)
end

-- A free bag slot that can hold the item (profession bags only take their kind), not one
-- already used by this job; nil if your bags are full.
local function FreeBagSlot(itemID, skip)
	local family = C_Item.GetItemFamily and C_Item.GetItemFamily(itemID) or 0
	for _, bag in ipairs(ns.inventory.BagsAt("bags")) do
		local _, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
		if (bagFamily or 0) == 0 or bit.band(family or 0, bagFamily) ~= 0 then
			for slot = 1, C_Container.GetContainerNumSlots(bag) do
				if not C_Container.GetContainerItemID(bag, slot) and not (skip and skip[bag .. ":" .. slot]) then
					return bag, slot
				end
			end
		end
	end
end

-- How many free bag slots can hold the item: room, in stacks.
function sell.Room(item)
	local skip, room = {}, 0
	while true do
		local bag, slot = FreeBagSlot(item.id, skip)
		if not bag then
			return room
		end
		skip[bag .. ":" .. slot] = true
		room = room + 1
	end
end

-- How many stacks the item is where it is: bank stacks of its full size, or mail attachments.
function sell.Stacks(item)
	if item.where == "mail" then
		return #(item.attachments or {})
	end
	return math.ceil(item.count / MaxStack(item))
end

---------------------------------------------------------------------------
-- Doing it
---------------------------------------------------------------------------

local runner = CreateFrame("Frame")
runner:Hide()

local function Finish(text)
	job = nil
	runner:Hide()
	SetStatus(text)
end

local function Plural(count, one, many)
	return count .. " " .. (count == 1 and one or many)
end

-- The bank: moves the next part (a whole slot, or a split) into a free bag slot.
local function BankStep()
	local remaining = job.want - job.done
	if remaining <= 0 then
		return Finish("Took " .. Plural(job.done, "item", "items") .. " from your bank.")
	end
	if GetCursorInfo() then
		return Finish("Stopped: you have something on your cursor.")
	end
	-- The source: a slot that still holds the item (it may have moved meanwhile).
	local source
	for _, place in ipairs(job.item.slots) do
		local info = C_Container.GetContainerItemInfo(place.bag, place.slot)
		if info and info.itemID == job.item.id and not info.isLocked and (info.stackCount or 0) > 0 then
			source = { bag = place.bag, slot = place.slot, count = info.stackCount }
			break
		end
	end
	if not source then
		return Finish("Took " .. Plural(job.done, "item", "items") .. " from your bank.")
	end
	local bag, slot = FreeBagSlot(job.item.id, job.targets)
	if not bag then
		return Finish(string.format("Bags full: took %d of %d.", job.done, job.want))
	end
	local amount = math.min(remaining, source.count, job.maxStack)
	if amount < source.count then
		C_Container.SplitContainerItem(source.bag, source.slot, amount)
	else
		C_Container.PickupContainerItem(source.bag, source.slot)
	end
	C_Container.PickupContainerItem(bag, slot)
	job.targets[bag .. ":" .. slot] = true
	job.done = job.done + amount
	SetStatus(string.format("Taking %d of %d...", job.done, job.want))
end

-- The mail: takes the next attachment of the item, then waits for it to arrive.
local function MailStep()
	if job.done >= job.want then
		return Finish("Took " .. Plural(job.done, "stack", "stacks") .. " from your mail.")
	end
	local next
	for _, item in ipairs(sell.LiveMailItems()) do
		if item.id == job.item.id and (not job.item.link or item.link == job.item.link or not item.link) then
			next = item.attachments[1]
			break
		end
	end
	if not next then
		return Finish("Took " .. Plural(job.done, "stack", "stacks") .. " from your mail.")
	end
	if not FreeBagSlot(job.item.id) then
		return Finish(string.format("Bags full: took %d of %d stacks.", job.done, job.want))
	end
	TakeInboxItem(next.mail, next.attachment)
	job.done = job.done + 1
	job.waiting = true
	SetStatus(string.format("Taking %d of %d...", job.done, job.want))
end

local sinceStep = 0
runner:SetScript("OnUpdate", function(_, elapsed)
	sinceStep = sinceStep + elapsed
	if not job then
		runner:Hide()
		return
	end
	if job.where == "bank" then
		if not sell.IsPlaceOpen("bank") then
			return Finish("Stopped: the bank closed.")
		end
		if sinceStep >= STEP_SECONDS then
			sinceStep = 0
			BankStep()
		end
	else
		if not sell.IsPlaceOpen("mail") then
			return Finish("Stopped: the mailbox closed.")
		end
		if sinceStep >= MAIL_WAIT_SECONDS and not job.waiting then
			sinceStep = 0
			MailStep()
		end
	end
end)
runner:SetScript("OnEvent", function()
	-- The mail taken has arrived (the inbox changed): on to the next, after the wait.
	if job then
		job.waiting = false
	end
end)
runner:RegisterEvent("MAIL_INBOX_UPDATE")
runner:RegisterEvent("BAG_UPDATE_DELAYED")

-- Takes `stacks` stacks of the item (nil: all of it) from where it is, as much as fits.
function sell.Take(item, stacks)
	if job or not (item.where and sell.IsPlaceOpen(item.where)) or InCombatLockdown() then
		return false
	end
	local maxStack = MaxStack(item)
	local want
	if item.where == "mail" then
		want = math.min(stacks or math.huge, #item.attachments)
	else
		want = math.min((stacks or math.huge) * maxStack, item.count)
	end
	job = { item = item, where = item.where, want = want, done = 0, maxStack = maxStack, targets = {} }
	sinceStep = math.huge
	SetStatus(string.format("Taking 0 of %d...", want))
	runner:Show()
	return true
end

function sell.IsTaking()
	return job ~= nil
end

---------------------------------------------------------------------------
-- How many? A small panel by the row
---------------------------------------------------------------------------

local prompt

local function UpdatePrompt()
	local item, stacks, total = prompt.item, prompt.stacks, prompt.total
	prompt.amount:SetText(tostring(stacks))
	local items
	if item.where == "mail" then
		items = 0
		for index = 1, stacks do
			items = items + item.attachments[index].count
		end
	else
		items = math.min(stacks * MaxStack(item), item.count)
	end
	prompt.items:SetText(string.format("%s  (%d %s)", stacks == 1 and "stack" or "stacks", items, items == 1 and "item" or "items"))
	local fits = math.min(prompt.room, total)
	prompt.roomText:SetText(string.format("Room in your bags: %s", Plural(prompt.room, "stack", "stacks")))
	prompt.roomText:SetTextColor(unpack(prompt.room < total and UI.ACCENT or UI.TEXT_DIM))
	prompt.all.text:SetText(fits < total and string.format("Take %d (All That Fit)", fits) or "Take All")
	prompt.all:SetWidth(prompt.all.text:GetStringWidth() + 20)
	prompt.all:SetEnabled(fits > 0)
	prompt.take:SetEnabled(stacks > 0 and stacks <= fits)
end

local function SetStacks(stacks)
	prompt.stacks = math.max(1, math.min(stacks, prompt.total))
	UpdatePrompt()
end

local function CreatePrompt()
	prompt = CreateFrame("Frame", "NraKitSellTakePrompt", UIParent)
	prompt:SetSize(300, 118)
	-- Above the list (both would be DIALOG, and the list comes to the front when clicked).
	prompt:SetFrameStrata("FULLSCREEN_DIALOG")
	prompt:SetToplevel(true)
	prompt:EnableMouse(true)
	prompt:EnableKeyboard(true)
	local bg = prompt:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(UI.BG))
	UI.AddBorder(prompt)

	prompt.title = prompt:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	prompt.title:SetPoint("TOPLEFT", 12, -10)
	prompt.title:SetPoint("RIGHT", -12, 0)
	prompt.title:SetJustifyH("LEFT")
	prompt.title:SetWordWrap(false)

	local label = prompt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("TOPLEFT", 12, -36)
	label:SetText("Take")
	prompt.minus = UI.CreateFlatButton(prompt, "-", 20)
	prompt.minus:SetWidth(20)
	prompt.minus:SetPoint("LEFT", label, "RIGHT", 8, 0)
	prompt.minus:SetScript("OnClick", function()
		SetStacks(prompt.stacks - 1)
	end)
	prompt.amount = prompt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	prompt.amount:SetPoint("LEFT", prompt.minus, "RIGHT", 6, 0)
	prompt.amount:SetWidth(24)
	prompt.plus = UI.CreateFlatButton(prompt, "+", 20)
	prompt.plus:SetWidth(20)
	prompt.plus:SetPoint("LEFT", prompt.amount, "RIGHT", 6, 0)
	prompt.plus:SetScript("OnClick", function()
		SetStacks(prompt.stacks + 1)
	end)
	prompt.items = prompt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	prompt.items:SetPoint("LEFT", prompt.plus, "RIGHT", 8, 0)

	prompt.roomText = prompt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	prompt.roomText:SetPoint("TOPLEFT", 12, -62)

	prompt.cancel = UI.CreateFlatButton(prompt, "Cancel", 22)
	prompt.cancel:SetPoint("BOTTOMRIGHT", -10, 10)
	prompt.cancel:SetScript("OnClick", function()
		prompt:Hide()
	end)
	prompt.take = UI.CreateFlatButton(prompt, "Take", 22)
	prompt.take:SetPoint("RIGHT", prompt.cancel, "LEFT", -6, 0)
	prompt.take:SetScript("OnClick", function()
		sell.Take(prompt.item, prompt.stacks)
		prompt:Hide()
	end)
	prompt.all = UI.CreateFlatButton(prompt, "Take All", 22)
	prompt.all:SetPoint("RIGHT", prompt.take, "LEFT", -6, 0)
	prompt.all:SetScript("OnClick", function()
		sell.Take(prompt.item, math.min(prompt.room, prompt.total))
		prompt:Hide()
	end)

	-- Enter takes, Escape cancels; other keys go on to the game.
	prompt:SetScript("OnKeyDown", function(self, key)
		if key == "ENTER" then
			self:SetPropagateKeyboardInput(false)
			if prompt.take:IsEnabled() then
				prompt.take:Click()
			end
		elseif key == "ESCAPE" then
			self:SetPropagateKeyboardInput(false)
			self:Hide()
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)
end

-- Asks how many stacks to take (by `row`); with one stack there's nothing to ask.
function sell.AskTake(item, row)
	local total = sell.Stacks(item)
	if total <= 1 then
		sell.Take(item)
		return
	end
	if not prompt then
		CreatePrompt()
	end
	prompt.item, prompt.total = item, total
	prompt.room = sell.Room(item)
	local where = item.where == "mail" and "your mail" or "your bank"
	prompt.title:SetText(string.format("%s  |cff999999%d in %s|r", item.name or ("Item " .. item.id), item.count, where))
	SetStacks(math.min(prompt.room, total)) -- as much as fits
	prompt:ClearAllPoints()
	prompt:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", 0, -2)
	prompt:Show()
	prompt:Raise()
end

function sell.HidePrompt()
	if prompt then
		prompt:Hide()
	end
end

-- (For tests.)
function sell.Prompt()
	return prompt
end
