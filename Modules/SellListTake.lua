local _, ns = ...

-- Sell List: taking items from your bank or mail into your bags, while you're at the bank or
-- the mailbox (the list reads them live then, SellList.lua). Click a bank or mail row to take
-- it; with more than one stack, a small panel by the row asks how many (Take All takes what
-- fits). Shift-click takes all that fits without asking.
--
--   Bank   the same as by hand: pick up from the bank slot, put it down in your bags
--          (C_Container.PickupContainerItem, SplitContainerItem for part of a stack). Nothing
--          protected: "using" the item (Blizzard's right-click) would be, for potions. Tidily:
--          one move at a time (a slot is locked until the server has it), the smallest bank
--          stack first, onto a partial stack of it in your bags if there is one, else into an
--          empty slot, so 2 + 2 + 3 potions become 5 + 2. A bag the game refuses (still on the
--          cursor) gets the item put back and isn't tried again.
--   Mail   TakeInboxItem, one attachment at a time (an attachment is a stack: it can't be
--          split), waiting for each to arrive; mail numbers shift as mails empty, so the
--          inbox is read again before each. C.O.D. mail is never listed (SellList.lua).
--
-- One thing at a time; progress and the result show in the list's footer (sell.TakeStatus).

local UI = ns.UI
local sell = ns.sellList

local MAIL_WAIT_SECONDS = 0.5 -- at least this between mail takes, and until the inbox updates
local BANK_STEP_SECONDS = 0.15 -- between bank moves (each also waits for its slots to unlock)

local job -- { item, where, want (items, or mail attachments), done, maxStack, refused = { [bag] = true } }
local status -- the footer's line about taking: "Taking 2 of 5...", "Took 3 stacks", ...

function sell.TakeStatus()
	return status
end

-- Forgets the last result ("Took 3 items from your bank."): it's about the moment it happened.
-- Not while a take is still going.
function sell.ClearTakeStatus()
	if not job and status then
		status = nil
		if sell.onTakeStatus then
			sell.onTakeStatus()
		end
	end
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
-- Forever has a keyring (bag -1, 32 slots): it takes keys only.
local KEYRING = Enum.BagIndex and Enum.BagIndex.Keyring or -1
local KEY_CLASS = Enum.ItemClass and Enum.ItemClass.Key or 13

-- /nra debug sell: what taking does (Debug.lua).
ns:RegisterDebug("sell", "Sell List: taking from the bank and mail (bags chosen, each move, the game's errors)")

local function Debug(text, ...)
	ns:Debug("sell", text, ...)
end

-- Whether a bag is a profession bag (herbs, enchanting...), as Blizzard's bags tell: its type
-- (GetContainerNumFreeSlots' bagFamily) can be 0 on some clients.
local function IsProfessionBag(bag)
	if bag == 0 or not (C_Container.ContainerIDToInventoryID and IsInventoryItemProfessionBag) then
		return false
	end
	local inventoryID = C_Container.ContainerIDToInventoryID(bag)
	return inventoryID ~= nil and IsInventoryItemProfessionBag("player", inventoryID) == true
end

-- The bags an item can go in, the way the game fills them: the keyring only for keys, the
-- reagent bag first for crafting reagents (each takes nothing else: "That item doesn't go in
-- that container"), then profession bags of its kind (herbs, ore...), then ordinary bags.
-- Also returns why, per bag (for /nra sell debug).
local function BagsFor(itemID)
	local family = C_Item.GetItemFamily and C_Item.GetItemFamily(itemID) or 0
	local isReagent = select(17, C_Item.GetItemInfo(itemID)) == true
	local isKey = select(6, C_Item.GetItemInfoInstant(itemID)) == KEY_CLASS
	local first, ordinary = {}, {}
	local why = {}
	for _, bag in ipairs(ns.inventory.BagsAt("bags")) do
		local _, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
		bagFamily = bagFamily or 0
		local profession = IsProfessionBag(bag)
		if bag == KEYRING then
			if isKey then
				table.insert(first, bag)
			end
			why[#why + 1] = string.format("%d:keyring%s", bag, isKey and "+" or "-")
		elseif bag == REAGENT_BAG then
			if isReagent then
				table.insert(first, bag)
			end
			why[#why + 1] = string.format("%d:reagent%s", bag, isReagent and "+" or "-")
		elseif bagFamily ~= 0 or profession then
			-- A profession bag takes only its kind: an item whose family matches it.
			local fits = bagFamily ~= 0 and bit.band(family or 0, bagFamily) ~= 0
			if fits then
				table.insert(first, bag)
			end
			why[#why + 1] = string.format("%d:profession(fam %s)%s", bag, tostring(bagFamily), fits and "+" or "-")
		else
			table.insert(ordinary, bag)
			why[#why + 1] = bag .. ":ordinary+"
		end
	end
	for _, bag in ipairs(ordinary) do
		table.insert(first, bag)
	end
	return first, string.format("item %s family %s reagent %s key %s; bags %s", tostring(itemID), tostring(family),
		tostring(isReagent), tostring(isKey), table.concat(why, " "))
end

-- A free bag slot that can hold the item, not one already used by this take; nil if your bags
-- are full (for it).
local function FreeBagSlot(itemID, skip, refused)
	for _, bag in ipairs(BagsFor(itemID)) do
		for slot = 1, refused and refused[bag] and 0 or C_Container.GetContainerNumSlots(bag) do
			if not C_Container.GetContainerItemID(bag, slot) and not (skip and skip[bag .. ":" .. slot]) then
				return bag, slot
			end
		end
	end
end
sell.BagsFor = BagsFor

-- How many of the item your bags can take: empty slots that can hold it, and what's left on
-- partial stacks of it.
function sell.RoomItems(item)
	local maxStack, room = MaxStack(item), 0
	for _, bag in ipairs(BagsFor(item.id)) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if not info then
				room = room + maxStack
			elseif info.itemID == item.id and maxStack > 1 then
				room = room + math.max(0, maxStack - (info.stackCount or 0))
			end
		end
	end
	return room
end

-- Room in your bags, in (full) stacks of the item.
function sell.Room(item)
	return math.floor(sell.RoomItems(item) / MaxStack(item))
end

-- A partial stack of the item in your bags to top up: bag, slot, how many more it takes.
-- `waiting` is true when there is one but it's locked (a move onto it is still going).
local function PartialStack(item, maxStack, refused)
	if maxStack <= 1 then
		return nil
	end
	local waiting = false
	for _, bag in ipairs(BagsFor(item.id)) do
		if not refused[bag] then
			for slot = 1, C_Container.GetContainerNumSlots(bag) do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if info and info.itemID == item.id and (info.stackCount or 0) < maxStack then
					if info.isLocked then
						waiting = true
					else
						return bag, slot, maxStack - info.stackCount
					end
				end
			end
		end
	end
	return nil, nil, nil, waiting
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

-- The bank: one move. Returns nothing while it's still going (or waiting for a lock).
local function BankStep()
	local remaining = job.want - job.done
	if remaining <= 0 then
		return Finish("Took " .. Plural(job.done, "item", "items") .. " from your bank.")
	end
	if GetCursorInfo() then
		return Finish("Stopped: you have something on your cursor.")
	end
	-- The smallest stack still in the bank (that empties bank slots); wait if they're locked.
	local source, locked = nil, false
	for _, place in ipairs(job.item.slots) do
		local info = C_Container.GetContainerItemInfo(place.bag, place.slot)
		if info and info.itemID == job.item.id and (info.stackCount or 0) > 0 then
			if info.isLocked then
				locked = true
			elseif not source or info.stackCount < source.count then
				source = { bag = place.bag, slot = place.slot, count = info.stackCount }
			end
		end
	end
	if not source then
		if locked then
			return
		end
		return Finish("Took " .. Plural(job.done, "item", "items") .. " from your bank.")
	end
	-- Onto a partial stack of it in your bags (wait if one is still locked from the last
	-- move), else into an empty slot.
	local bag, slot, room, waiting = PartialStack(job.item, job.maxStack, job.refused)
	if waiting then
		return
	end
	local into = "stack"
	if not bag then
		bag, slot = FreeBagSlot(job.item.id, nil, job.refused)
		room, into = job.maxStack, "empty"
	end
	if not bag then
		return Finish(string.format("Bags full: took %d of %d.", job.done, job.want))
	end
	local amount = math.min(remaining, source.count, room)
	Debug("%s %d from bank %d:%d (stack %d) onto bag %d:%d (%s, %s)",
		amount < source.count and "split" or "move", amount, source.bag, source.slot, source.count, bag, slot, into,
		tostring(C_Container.GetBagName and C_Container.GetBagName(bag)))
	if amount < source.count then
		C_Container.SplitContainerItem(source.bag, source.slot, amount)
	else
		C_Container.PickupContainerItem(source.bag, source.slot)
	end
	C_Container.PickupContainerItem(bag, slot)
	if GetCursorInfo() then
		-- Refused ("That item doesn't go in that container"): back it goes; not that bag again.
		Debug("refused by bag %d: putting it back, trying the next bag", bag)
		ClearCursor()
		job.refused[bag] = true
		return
	end
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
	Debug("mail %d attachment %d", next.mail, next.attachment)
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
	if not sell.IsPlaceOpen(job.where) then
		return Finish("Stopped: the " .. (job.where == "bank" and "bank" or "mailbox") .. " closed.")
	end
	if job.where == "bank" then
		if sinceStep >= BANK_STEP_SECONDS then
			sinceStep = 0
			BankStep()
		end
	elseif sinceStep >= MAIL_WAIT_SECONDS and not job.waiting then
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

-- While debugging: the game's red error messages, to see what it refused.
local errors = CreateFrame("Frame")
errors:RegisterEvent("UI_ERROR_MESSAGE")
errors:SetScript("OnEvent", function(_, _, _, message)
	Debug("game error: " .. tostring(message))
end)

-- Takes from where the item is: `stacks` stacks (nil: all of it), or with `items`, that many
-- items (the bank only: mail comes a whole attachment at a time).
function sell.Take(item, stacks, items)
	if job or not (item.where and sell.IsPlaceOpen(item.where)) or InCombatLockdown() then
		return false
	end
	local maxStack = MaxStack(item)
	local want
	if item.where == "bank" then
		want = math.min(items or (stacks or math.huge) * maxStack, item.count)
		if ns:IsDebugging("sell") then
			Debug(select(2, BagsFor(item.id)))
		end
	else
		want = math.min(stacks or math.huge, #item.attachments)
	end
	job = { item = item, where = item.where, want = want, done = 0, maxStack = maxStack, refused = {} }
	sinceStep = math.huge
	SetStatus(string.format("Taking 0 of %d...", want))
	runner:Show()
	return true
end

-- Takes all of it that fits in your bags (Shift-click, Take All).
function sell.TakeAllThatFits(item)
	if item.where == "bank" then
		return sell.Take(item, nil, math.min(item.count, sell.RoomItems(item)))
	end
	return sell.Take(item, math.min(sell.Room(item), sell.Stacks(item)))
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
	-- What fits: the bank in items (onto partial stacks too), mail in whole attachments.
	local short, fits, canTake
	if item.where == "bank" then
		short = prompt.fitsItems < item.count
		fits = prompt.unit == "items" and prompt.fitsItems or math.ceil(prompt.fitsItems / prompt.maxStack)
		canTake = items <= prompt.fitsItems
		prompt.roomText:SetText("Room in your bags: " .. (prompt.unit == "items" and Plural(prompt.roomItems, "item", "items")
			or Plural(math.floor(prompt.roomItems / prompt.maxStack), "stack", "stacks")))
	else
		short = prompt.room < prompt.total
		fits = math.min(prompt.room, prompt.total)
		canTake = stacks <= prompt.room
		prompt.roomText:SetText("Room in your bags: " .. Plural(prompt.room, "stack", "stacks"))
	end
	prompt.roomText:SetTextColor(unpack(short and UI.ACCENT or UI.TEXT_DIM))
	prompt.all.text:SetText(short and string.format("Take %d (All That Fit)", fits) or "Take All")
	prompt.all:SetWidth(prompt.all.text:GetStringWidth() + 20)
	prompt.all:SetEnabled(fits > 0)
	canTake = canTake and prompt.amount > 0
	prompt.take:SetEnabled(canTake)
	prompt.take:SetSelected(canTake) -- lit as the main button only while it can be clicked
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
	-- Above the list (HIGH), like the game's own pop-ups.
	prompt:SetFrameStrata("DIALOG")
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
	-- Take is the main button (lit), by Cancel; Take All is apart, far left, so it isn't
	-- clicked by mistake after choosing an amount.
	prompt.take = UI.CreateFlatButton(prompt, "Take", 24)
	prompt.take:SetWidth(64)
	prompt.take:SetPoint("RIGHT", prompt.cancel, "LEFT", -6, 0)
	prompt.take:SetSelected(true)
	prompt.take:SetScript("OnClick", TakeChosen)
	prompt.all = UI.CreateFlatButton(prompt, "Take All", 24)
	prompt.all:SetPoint("BOTTOMLEFT", 12, 12)
	prompt.all:SetScript("OnClick", function()
		sell.TakeAllThatFits(prompt.item)
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

-- Asks how much to take (by `row`): from the bank whenever there's more than one (even in one
-- stack: "take 4 of these 9"), from mail when there's more than one attachment (they can't be
-- split). A single one is taken at once; Shift-click takes all that fits without asking.
function sell.AskTake(item, row)
	local total = sell.Stacks(item)
	if (item.where == "bank" and item.count <= 1) or (item.where ~= "bank" and total <= 1) then
		sell.Take(item)
		return
	end
	if not prompt then
		CreatePrompt()
	end
	prompt.item, prompt.total, prompt.maxStack = item, total, MaxStack(item)
	prompt.room = sell.Room(item)
	prompt.roomItems = sell.RoomItems(item)
	prompt.fitsItems = math.min(item.count, prompt.roomItems)
	-- All in one stack: count in items. Several: in stacks.
	prompt.unit = (item.where == "bank" and total <= 1) and "items" or "stacks"
	prompt.title:SetText(item.name or ("Item " .. item.id))
	prompt.where:SetText(string.format("%d in %s", item.count, item.where == "mail" and "your mail" or "your bank"))
	-- As much as fits.
	if prompt.unit == "items" then
		SetAmount(prompt.fitsItems)
	elseif item.where == "bank" then
		-- All of it if it fits; else the whole stacks that fit.
		SetAmount(prompt.fitsItems >= item.count and total or math.max(1, math.floor(prompt.fitsItems / prompt.maxStack)))
	else
		SetAmount(math.min(prompt.room, total))
	end
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
