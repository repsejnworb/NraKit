local _, ns = ...

-- Sell List: taking items from your bank or mail into your bags, while you're at the bank or
-- the mailbox (the list reads them live then, SellList.lua). Click a bank or mail row to take
-- it; with more than one stack, a small panel by the row asks how many (Take All takes what
-- fits). Shift-click takes all that fits without asking.
--
--   Bank   the same as by hand: pick up from the bank slot, put it in a free bag slot that can
--          hold it (C_Container.PickupContainerItem, SplitContainerItem for part of a stack).
--          Nothing protected: "using" the item (Blizzard's right-click) would be, for potions.
--          All of it right in your click: done later (from a timer) the game picks the item up
--          but quietly won't put it down (seen in game). Whole stacks first, then one split.
--   Mail   TakeInboxItem, one attachment at a time (an attachment is a stack: it can't be
--          split), waiting for each to arrive; mail numbers shift as mails empty, so the
--          inbox is read again before each. C.O.D. mail is never listed (SellList.lua).
--
-- One thing at a time; progress and the result show in the list's footer (sell.TakeStatus).

local UI = ns.UI
local sell = ns.sellList

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

local REAGENT_BAG = Enum.BagIndex and Enum.BagIndex.ReagentBag or 5

-- The bags an item can go in, the way the game fills them: the reagent bag first for crafting
-- reagents (it takes nothing else: "The item doesn't go into that container"), then profession
-- bags of its kind (herbs, ore...), then ordinary bags.
local function BagsFor(itemID)
	local family = C_Item.GetItemFamily and C_Item.GetItemFamily(itemID) or 0
	local isReagent = select(17, C_Item.GetItemInfo(itemID)) == true
	local first, ordinary = {}, {}
	for _, bag in ipairs(ns.inventory.BagsAt("bags")) do
		local _, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
		bagFamily = bagFamily or 0
		if bag == REAGENT_BAG then
			if isReagent then
				table.insert(first, bag)
			end
		elseif bagFamily ~= 0 then
			if bit.band(family or 0, bagFamily) ~= 0 then
				table.insert(first, bag)
			end
		else
			table.insert(ordinary, bag)
		end
	end
	for _, bag in ipairs(ordinary) do
		table.insert(first, bag)
	end
	return first
end

-- A free bag slot that can hold the item, not one already used by this take; nil if your bags
-- are full (for it).
local function FreeBagSlot(itemID, skip)
	for _, bag in ipairs(BagsFor(itemID)) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			if not C_Container.GetContainerItemID(bag, slot) and not (skip and skip[bag .. ":" .. slot]) then
				return bag, slot
			end
		end
	end
end
sell.BagsFor = BagsFor

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

-- The bank: moves `want` items into free bag slots, now (in your click): whole stacks into
-- free slots, then the rest split off one stack. Returns the line to show.
local function TakeFromBank(item, want)
	if GetCursorInfo() then
		return "Stopped: you have something on your cursor."
	end
	local maxStack, done, targets = MaxStack(item), 0, {}
	local split = false
	for _, place in ipairs(item.slots) do
		local remaining = want - done
		if remaining <= 0 then
			break
		end
		local info = C_Container.GetContainerItemInfo(place.bag, place.slot)
		if info and info.itemID == item.id and not info.isLocked and (info.stackCount or 0) > 0 then
			local amount = math.min(remaining, info.stackCount, maxStack)
			-- Part of a stack: only once (the stack is locked until the server has split it).
			if amount < info.stackCount and split then
				break
			end
			local bag, slot = FreeBagSlot(item.id, targets)
			if not bag then
				return string.format("Bags full: took %d of %d.", done, want)
			end
			if amount < info.stackCount then
				C_Container.SplitContainerItem(place.bag, place.slot, amount)
				split = true
			else
				C_Container.PickupContainerItem(place.bag, place.slot)
			end
			C_Container.PickupContainerItem(bag, slot)
			targets[bag .. ":" .. slot] = true
			done = done + amount
		end
	end
	return "Took " .. Plural(done, "item", "items") .. " from your bank."
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
	if not sell.IsPlaceOpen("mail") then
		return Finish("Stopped: the mailbox closed.")
	end
	if sinceStep >= MAIL_WAIT_SECONDS and not job.waiting then
		sinceStep = 0
		MailStep()
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

-- Takes from where the item is, as much as fits: `stacks` stacks (nil: all of it), or with
-- `items`, that many items (the bank only: mail comes a whole attachment at a time).
-- Call it from a click: the bank's moves happen right then.
function sell.Take(item, stacks, items)
	if job or not (item.where and sell.IsPlaceOpen(item.where)) or InCombatLockdown() then
		return false
	end
	local maxStack = MaxStack(item)
	if item.where == "bank" then
		local want = items or (stacks or math.huge) * maxStack
		SetStatus(TakeFromBank(item, math.min(want, item.count)))
		return true
	end
	local want = math.min(stacks or math.huge, #item.attachments)
	job = { item = item, where = item.where, want = want, done = 0, maxStack = maxStack }
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

-- The panel stands out from the list: darker, an orange line on top, a shadow around it.
local PROMPT_BG = { 0.04, 0.04, 0.05, 0.98 }
local PROMPT_WIDTH, PROMPT_HEIGHT = 390, 150

local prompt

-- How much the panel's amount is in stacks, and in items (bank stacks are full ones; mail's are
-- attachments).
local function Amounts()
	local item, amount = prompt.item, prompt.amount
	if prompt.unit == "items" then
		return math.ceil(amount / prompt.maxStack), amount
	end
	if item.where == "mail" then
		local items = 0
		for index = 1, amount do
			items = items + item.attachments[index].count
		end
		return amount, items
	end
	return amount, math.min(amount * prompt.maxStack, item.count)
end

local function UpdatePrompt()
	local item = prompt.item
	local stacks, items = Amounts()
	prompt.amountText:SetText(tostring(prompt.amount))
	-- [ Items ][ Stacks ]: the one in use lit, the other plain. Mail can't be split: stacks only.
	prompt.itemsButton:SetSelected(prompt.unit == "items")
	prompt.stacksButton:SetSelected(prompt.unit == "stacks")
	local canSplit = item.where == "bank"
	prompt.itemsButton:SetEnabled(canSplit)
	if not canSplit then
		prompt.itemsButton.text:SetTextColor(unpack(UI.TEXT_DIM))
	end
	if prompt.unit == "items" then
		prompt.detail:SetText(string.format("(%s)", Plural(stacks, "stack", "stacks")))
	else
		prompt.detail:SetText(string.format("(%s)", Plural(items, "item", "items")))
	end
	local fits = math.min(prompt.room, prompt.total)
	prompt.roomText:SetText("Room in your bags: " .. Plural(prompt.room, "stack", "stacks"))
	prompt.roomText:SetTextColor(unpack(prompt.room < prompt.total and UI.ACCENT or UI.TEXT_DIM))
	prompt.all.text:SetText(fits < prompt.total and string.format("Take %d (All That Fit)", fits) or "Take All")
	prompt.all:SetWidth(prompt.all.text:GetStringWidth() + 20)
	prompt.all:SetEnabled(fits > 0)
	prompt.take:SetEnabled(prompt.amount > 0 and stacks <= prompt.room)
end

-- The amount, kept between 1 and the most there is (in the unit shown).
local function SetAmount(amount)
	local most = prompt.unit == "items" and prompt.item.count or prompt.total
	prompt.amount = math.max(1, math.min(amount, most))
	UpdatePrompt()
end

-- Counts in "items" or "stacks", keeping about the same amount.
local function SetUnit(unit)
	if unit == prompt.unit then
		return
	end
	local stacks, items = Amounts()
	prompt.unit = unit
	SetAmount(unit == "items" and items or stacks)
end

local function TakeChosen()
	if prompt.unit == "items" then
		sell.Take(prompt.item, nil, prompt.amount)
	else
		sell.Take(prompt.item, prompt.amount)
	end
	prompt:Hide()
end

local function CreatePrompt()
	prompt = CreateFrame("Frame", "NraKitSellTakePrompt", UIParent)
	prompt:SetSize(PROMPT_WIDTH, PROMPT_HEIGHT)
	-- Above the list (both would be DIALOG, and the list comes to the front when clicked).
	prompt:SetFrameStrata("FULLSCREEN_DIALOG")
	prompt:SetToplevel(true)
	prompt:EnableMouse(true)
	prompt:EnableKeyboard(true)
	local shadow = prompt:CreateTexture(nil, "BACKGROUND", nil, -1)
	shadow:SetPoint("TOPLEFT", -6, 6)
	shadow:SetPoint("BOTTOMRIGHT", 6, -6)
	shadow:SetColorTexture(0, 0, 0, 0.55)
	local bg = prompt:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(PROMPT_BG))
	UI.AddBorder(prompt)
	local accent = prompt:CreateTexture(nil, "ARTWORK")
	accent:SetPoint("TOPLEFT")
	accent:SetPoint("TOPRIGHT")
	accent:SetHeight(2)
	accent:SetColorTexture(unpack(UI.ACCENT))

	prompt.title = prompt:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	prompt.title:SetPoint("TOPLEFT", 14, -14)
	prompt.title:SetPoint("RIGHT", -14, 0)
	prompt.title:SetJustifyH("LEFT")
	prompt.title:SetWordWrap(false)
	prompt.where = prompt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	prompt.where:SetPoint("TOPLEFT", prompt.title, "BOTTOMLEFT", 0, -3)
	prompt.where:SetTextColor(unpack(UI.TEXT_DIM))

	local label = prompt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("TOPLEFT", 14, -58)
	label:SetText("Take")
	prompt.minus = UI.CreateFlatButton(prompt, "-", 22)
	prompt.minus:SetWidth(22)
	prompt.minus:SetPoint("LEFT", label, "RIGHT", 10, 0)
	prompt.minus:SetScript("OnClick", function()
		SetAmount(prompt.amount - (IsShiftKeyDown() and 10 or 1))
	end)
	prompt.amountText = prompt:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	prompt.amountText:SetPoint("LEFT", prompt.minus, "RIGHT", 4, 0)
	prompt.amountText:SetWidth(36)
	prompt.plus = UI.CreateFlatButton(prompt, "+", 22)
	prompt.plus:SetWidth(22)
	prompt.plus:SetPoint("LEFT", prompt.amountText, "RIGHT", 4, 0)
	prompt.plus:SetScript("OnClick", function()
		SetAmount(prompt.amount + (IsShiftKeyDown() and 10 or 1))
	end)
	-- [ Items ][ Stacks ] side by side: which one the amount counts in, both always in view.
	prompt.itemsButton = UI.CreateFlatButton(prompt, "Items", 22)
	prompt.itemsButton:SetWidth(54)
	prompt.itemsButton:SetPoint("LEFT", prompt.plus, "RIGHT", 10, 0)
	prompt.itemsButton:SetMotionScriptsWhileDisabled(true)
	prompt.itemsButton:SetScript("OnClick", function()
		SetUnit("items")
	end)
	prompt.itemsButton:SetScript("OnEnter", function(self)
		if self:IsEnabled() then
			UI.ShowTooltip(self, "Count in items", "Take an exact number of items (part of a stack is split off).")
		else
			UI.ShowTooltip(self, "Count in items", "Mail comes a whole stack at a time: it can't be split.")
		end
	end)
	prompt.itemsButton:SetScript("OnLeave", GameTooltip_Hide)
	prompt.stacksButton = UI.CreateFlatButton(prompt, "Stacks", 22)
	prompt.stacksButton:SetWidth(58)
	prompt.stacksButton:SetPoint("LEFT", prompt.itemsButton, "RIGHT", 1, 0)
	prompt.stacksButton:SetScript("OnClick", function()
		SetUnit("stacks")
	end)
	prompt.stacksButton:SetScript("OnEnter", function(self)
		UI.ShowTooltip(self, "Count in stacks", "Take whole stacks.")
	end)
	prompt.stacksButton:SetScript("OnLeave", GameTooltip_Hide)
	prompt.detail = prompt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	prompt.detail:SetPoint("LEFT", prompt.stacksButton, "RIGHT", 8, 0)
	prompt.detail:SetTextColor(unpack(UI.TEXT_DIM))

	prompt.roomText = prompt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	prompt.roomText:SetPoint("TOPLEFT", 14, -86)

	prompt.cancel = UI.CreateFlatButton(prompt, "Cancel", 24)
	prompt.cancel:SetPoint("BOTTOMRIGHT", -12, 12)
	prompt.cancel:SetScript("OnClick", function()
		prompt:Hide()
	end)
	prompt.take = UI.CreateFlatButton(prompt, "Take", 24)
	prompt.take:SetPoint("RIGHT", prompt.cancel, "LEFT", -6, 0)
	prompt.take:SetScript("OnClick", TakeChosen)
	prompt.all = UI.CreateFlatButton(prompt, "Take All", 24)
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
				TakeChosen()
			end
		elseif key == "ESCAPE" then
			self:SetPropagateKeyboardInput(false)
			self:Hide()
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)
end

-- Asks how much to take (by `row`); with one stack there's nothing to ask.
function sell.AskTake(item, row)
	local total = sell.Stacks(item)
	if total <= 1 then
		sell.Take(item)
		return
	end
	if not prompt then
		CreatePrompt()
	end
	prompt.item, prompt.total, prompt.maxStack = item, total, MaxStack(item)
	prompt.room = sell.Room(item)
	prompt.unit = "stacks"
	prompt.title:SetText(item.name or ("Item " .. item.id))
	prompt.where:SetText(string.format("%d in %s", item.count, item.where == "mail" and "your mail" or "your bank"))
	SetAmount(math.min(prompt.room, total)) -- as much as fits
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
