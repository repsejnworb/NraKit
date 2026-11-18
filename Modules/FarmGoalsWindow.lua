local _, ns = ...

-- Goals window (/nra goal): active goals, a form for new goals and the history of
-- finished ones. Same look as the other NraKit windows (UI.lua).
--
-- New goal form: pick a type (Item, Level, XP, Gold). An item can be dropped on the
-- slot, shift-clicked while the name box has focus, or typed. Item and gold goals can
-- start from what you already have: tick bags, bank, mail and other characters (the
-- last two need Inventory Tracker's data) and the starting count updates live.
-- "Recount" reuses the same section to change an existing goal's starting count.

local UI = ns.UI
local WIDTH, HEIGHT = 720, 500
local SIDEBAR_WIDTH = 170
local PAD = UI.PAD

local frame, scroll, form
local navButtons = {}
local page = "active" -- "active", "new", "history" or "recount"
local recountID
local pool = UI.CreatePool()
local cards = {} -- goal id -> card widgets on the active page
local cardSignature

local GOAL_TYPES = {
	{ key = "item", label = "Item" },
	{ key = "level", label = "Level" },
	{ key = "xp", label = "XP" },
	{ key = "gold", label = "Gold" },
}

local function G()
	return ns.goals
end

------------------------------------------------------------------------------
-- Active goals
------------------------------------------------------------------------------

local Render

local function CardButton(card, label, onClick)
	local button = pool:Acquire("cardButton", function()
		local b = UI.CreateFlatButton(scroll.content, "", 20)
		b:SetFrameLevel(scroll.content:GetFrameLevel() + 2)
		return b
	end)
	button.text:SetText(label)
	button:SetWidth(button.text:GetStringWidth() + 20)
	button:SetScript("OnClick", onClick)
	return button
end

local function UpdateCard(card, goal)
	local name, icon = G().Describe(goal)
	local fraction, value = G().GetProgress(goal)
	card.icon:SetTexture(icon)
	card.icon:SetDesaturated(goal.paused and true or false)
	card.name:SetText(name)
	card.value:SetText(value)
	card.info:SetText(G().DescribeRate(goal))
	card.track:SetValue(math.min(math.max(fraction, 0), 1))
	if goal.completed then
		card.track:SetStatusBarColor(0.3, 0.85, 0.3)
		card.name:SetTextColor(0.3, 0.85, 0.3)
	elseif goal.paused then
		card.track:SetStatusBarColor(0.5, 0.5, 0.5)
		card.name:SetTextColor(unpack(UI.GREY))
	else
		card.track:SetStatusBarColor(unpack(UI.ACCENT))
		card.name:SetTextColor(unpack(UI.GOLD))
	end
end

local function AcquireCard()
	return pool:Acquire("card", function()
		local card = CreateFrame("Frame", nil, scroll.content)
		card:SetHeight(76)
		card.bg = card:CreateTexture(nil, "BACKGROUND")
		card.bg:SetAllPoints()
		card.bg:SetColorTexture(unpack(UI.PANEL))
		card.icon = card:CreateTexture(nil, "ARTWORK")
		card.icon:SetSize(36, 36)
		card.icon:SetPoint("TOPLEFT", 10, -10)
		card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		card.value = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		card.value:SetPoint("TOPRIGHT", -12, -12)
		card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -2)
		card.name:SetPoint("RIGHT", card.value, "LEFT", -8, 0)
		card.name:SetJustifyH("LEFT")
		card.name:SetWordWrap(false)
		card.track = CreateFrame("StatusBar", nil, card)
		card.track:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
		card.track:SetMinMaxValues(0, 1)
		card.track:SetHeight(5)
		card.track:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -22)
		card.track:SetPoint("RIGHT", -12, 0)
		card.track.bg = card.track:CreateTexture(nil, "BACKGROUND")
		card.track.bg:SetAllPoints()
		card.track.bg:SetColorTexture(1, 1, 1, 0.12)
		card.info = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		card.info:SetPoint("BOTTOMLEFT", 56, 12)
		card.info:SetJustifyH("LEFT")
		return card
	end)
end

local function RenderActive(content, width)
	local goals = G().GetData().goals
	local y = -PAD
	wipe(cards)
	local ids = {}
	for _, goal in ipairs(goals) do
		local card = AcquireCard()
		card:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
		card:SetWidth(width)
		UpdateCard(card, goal)
		cards[goal.id] = card
		table.insert(ids, goal.id .. (goal.completed and "c" or ""))

		-- Buttons, right to left.
		local anchor
		local function Add(label, onClick)
			local button = CardButton(card, label, onClick)
			if anchor then
				button:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
			else
				button:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 8)
			end
			anchor = button
		end
		local id = goal.id
		if goal.completed then
			Add("Clear", function()
				G().RemoveGoal(id)
			end)
		else
			Add("Remove", function()
				G().RemoveGoal(id)
			end)
			Add("Reset", function()
				goal.gained, goal.active, goal.milestone = 0, 0, 0
				if goal.type == "level" then
					goal.startLevel = UnitLevel("player") + UnitXP("player") / math.max(UnitXPMax("player"), 1)
				end
				G().Update()
			end)
			if goal.type == "item" or goal.type == "gold" then
				Add("Recount", function()
					ns:OpenGoalsWindow("recount", id)
				end)
			end
			Add(goal.paused and "Resume" or "Pause", function()
				goal.paused = not goal.paused or nil
				G().Update()
				Render()
			end)
		end
		y = y - 76 - 8
	end
	cardSignature = table.concat(ids, ",")

	if #goals == 0 then
		local empty = pool:Acquire("text", function()
			return content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
		end)
		empty:SetText("No goals yet. Pick \"New goal\" on the left, or type /nra goal 4000 and shift-click an item.")
		empty:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 2, y - 4)
		y = y - 30
	end
	return -y + PAD
end

------------------------------------------------------------------------------
-- History
------------------------------------------------------------------------------

local function RenderHistory(content, width)
	local history = G().GetData().history
	local y = -PAD
	for index, entry in ipairs(history) do
		local row = pool:Acquire("historyRow", function()
			local r = CreateFrame("Frame", nil, content)
			r:SetHeight(32)
			r.bg = r:CreateTexture(nil, "BACKGROUND")
			r.bg:SetAllPoints()
			r.icon = r:CreateTexture(nil, "ARTWORK")
			r.icon:SetSize(22, 22)
			r.icon:SetPoint("LEFT", 8, 0)
			r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
			r.when = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			r.when:SetPoint("RIGHT", -10, 0)
			return r
		end)
		row:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
		row:SetWidth(width)
		row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
		local _, icon = G().Describe(entry)
		row.icon:SetTexture(icon)
		local name = entry.name
		if entry.type == "item" then
			name = G().FormatNumber(entry.target) .. " " .. name
		end
		row.name:SetText(name)
		row.when:SetText(string.format("took %s  ·  %s", G().FormatDuration(entry.active or 0),
			date("%Y-%m-%d", entry.completed)))
		y = y - 32
	end
	if #history == 0 then
		local empty = pool:Acquire("text", function()
			return content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
		end)
		empty:SetText("Finished goals show up here once you clear them from the tracker.")
		empty:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 2, y - 4)
		y = y - 30
	else
		local clear = pool:Acquire("clearHistory", function()
			local b = UI.CreateFlatButton(content, "Clear history", 22)
			b:SetScript("OnClick", function()
				wipe(G().GetData().history)
				Render()
			end)
			return b
		end)
		clear:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y - 10)
		y = y - 40
	end
	return -y + PAD
end

------------------------------------------------------------------------------
-- New goal / recount form
------------------------------------------------------------------------------

local formType = "item"
local formItemID

local function MakeLabel(parent, text, font)
	local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	label:SetText(text)
	label:SetJustifyH("LEFT")
	return label
end

local function MakeEditBox(parent, width, numeric)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width, 22)
	box:SetAutoFocus(false)
	box:SetNumeric(numeric and true or false)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	return box
end

local function MakeHeading(parent, text)
	local heading = MakeLabel(parent, text:upper(), "GameFontNormalSmall")
	heading:SetTextColor(unpack(UI.ACCENT))
	return heading
end

-- Current form values: target amount and starting count.
local function ReadForm()
	local amount = tonumber(form.amount:GetText())
	local holdings = form.holdings
	local start = 0
	if holdings and (formType == "item" or formType == "gold") then
		for _, seed in ipairs(form.seeds) do
			if seed:IsShown() and seed:GetChecked() and seed:IsEnabled() then
				start = start + (seed.count or 0)
			end
		end
	end
	return amount, start
end

local function UpdateForm()
	local recounting = page == "recount"
	local goal = recounting and G().FindGoal(recountID)
	if recounting and not goal then
		page = "active"
		Render()
		return
	end
	local goalType = recounting and goal.type or formType
	formType = goalType
	local itemID = recounting and goal.itemID or formItemID

	for _, chip in ipairs(form.typeChips) do
		chip:SetSelected(chip.key == goalType)
		chip:SetShown(not recounting)
	end
	form.title:SetText(recounting and ("Recount: " .. (G().Describe(goal))) or "New goal")

	-- Item picker
	local isItem = goalType == "item"
	form.slot:SetShown(isItem and not recounting)
	form.itemName:SetShown(isItem and not recounting)
	form.itemHint:SetShown(isItem and not recounting)
	if isItem then
		local name = itemID and C_Item.GetItemNameByID(itemID)
		local icon = itemID and select(5, C_Item.GetItemInfoInstant(itemID))
		form.slot.icon:SetTexture(icon or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
		form.itemLabel:SetText(name or (itemID and ("item " .. itemID)) or "No item picked")
	end
	form.itemLabel:SetShown(isItem and not recounting)

	-- Amount
	local amountLabels = { item = "How many to have", level = "Target level", xp = "XP to gain", gold = "Gold to have" }
	form.amountLabel:SetText(amountLabels[goalType])
	form.amountLabel:SetShown(not recounting)
	form.amount:SetShown(not recounting)

	-- Starting count
	local seeding = goalType == "item" or goalType == "gold"
	form.seedHeading:SetShown(seeding)
	local holdings = seeding and (goalType == "gold" or itemID) and G().GetHoldings(goalType == "item" and itemID or nil)
	form.holdings = holdings
	local isGold = goalType == "gold"
	local format = isGold and G().FormatGold or G().FormatNumber
	local seedInfo = {
		{ label = isGold and "This character" or "Bags", count = holdings and holdings.bags, show = true },
		{ label = "Bank", count = holdings and holdings.bank, show = not isGold },
		{ label = "Mail", count = holdings and holdings.mail, show = not isGold, needsTracker = true },
		{ label = "Other characters", count = holdings and holdings.othersTotal, show = true, needsTracker = true },
	}
	for index, seed in ipairs(form.seeds) do
		local info = seedInfo[index]
		local visible = seeding and info.show
		seed:SetShown(visible)
		seed.count = info.count or 0
		local available = holdings ~= nil and (not info.needsTracker or holdings.trackerOn)
		seed:SetEnabled(available)
		seed.Text:SetText(info.label)
		seed.Text:SetTextColor(unpack(available and UI.TEXT or UI.TEXT_DIM))
		seed.countText:SetText(available and format(seed.count) or "")
	end
	-- Who the other characters are
	local others = {}
	for _, other in ipairs(holdings and holdings.others or {}) do
		local r, g, b = ns.inventory.ClassColor(other.class)
		table.insert(others, string.format("|cff%02x%02x%02x%s|r %s", r * 255, g * 255, b * 255, other.name, format(other.count)))
		if #others == 4 then
			break
		end
	end
	form.othersText:SetShown(seeding)
	if holdings and not holdings.trackerOn then
		form.othersText:SetText("Turn on Inventory Tracker to include mail and other characters.")
	else
		form.othersText:SetText(table.concat(others, "  ·  "))
	end

	local amount, start = ReadForm()
	if recounting then
		amount = goal.target
	end
	if seeding then
		local target = amount and (isGold and amount * 10000 or amount)
		form.startText:SetText(string.format("Starting count  |cffffffff%s|r%s", format(start),
			target and ("   →   " .. format(start) .. " / " .. format(target)) or ""))
	end
	form.startText:SetShown(seeding)

	-- Create / update button
	local valid
	if recounting then
		valid = true
		form.create:SetText("Update starting count")
	else
		valid = amount and amount > 0 and (not isItem or itemID ~= nil)
		if goalType == "level" then
			valid = amount and amount > UnitLevel("player")
		end
		form.create:SetText("Create goal")
	end
	form.create:SetEnabled(valid and true or false)
end

local function SetItem(itemID)
	formItemID = itemID
	if form.itemName:HasFocus() then
		form.itemName:ClearFocus()
	end
	form.itemName:SetText("")
	UpdateForm()
end

local function SubmitForm()
	local amount, start = ReadForm()
	if page == "recount" then
		local goal = G().FindGoal(recountID)
		if goal then
			goal.start = start
			G().Update()
		end
		page = "active"
		Render()
		return
	end
	local goal = { type = formType }
	if formType == "item" then
		goal.itemID, goal.target, goal.start = formItemID, amount, start
	elseif formType == "gold" then
		goal.target, goal.start = amount * 10000, start
	else
		goal.target = amount
	end
	G().AddGoal(goal)
	form.amount:SetText("")
	formItemID = nil
	page = "active"
	Render()
end

local function CreateForm(body)
	form = CreateFrame("Frame", nil, body)
	form:SetPoint("TOPLEFT", PAD, -PAD)
	form:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	form:Hide()

	form.title = MakeLabel(form, "New goal", "GameFontNormalLarge")
	form.title:SetPoint("TOPLEFT", 2, 0)
	form.title:SetTextColor(1, 1, 1)

	form.typeChips = {}
	local anchor
	for _, info in ipairs(GOAL_TYPES) do
		local chip = UI.CreateFlatButton(form, info.label, 24)
		chip:SetWidth(math.max(chip:GetWidth(), 64))
		chip.key = info.key
		chip:SetScript("OnClick", function(self)
			formType = self.key
			form.amount:SetText(self.key == "level" and tostring(UnitLevel("player") + 1) or "")
			UpdateForm()
		end)
		if anchor then
			chip:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
		else
			chip:SetPoint("TOPLEFT", 0, -32)
		end
		anchor = chip
		table.insert(form.typeChips, chip)
	end

	-- Item slot: drop an item on it (or click while holding one).
	local slot = CreateFrame("Button", nil, form)
	slot:SetSize(40, 40)
	slot:SetPoint("TOPLEFT", 0, -72)
	slot.icon = slot:CreateTexture(nil, "ARTWORK")
	slot.icon:SetAllPoints()
	UI.AddBorder(slot)
	local function TakeCursorItem()
		local kind, itemID = GetCursorInfo()
		if kind == "item" and itemID then
			ClearCursor()
			SetItem(itemID)
		end
	end
	slot:SetScript("OnReceiveDrag", TakeCursorItem)
	slot:SetScript("OnClick", TakeCursorItem)
	slot:SetScript("OnEnter", function(self)
		if formItemID then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetItemByID(formItemID)
			GameTooltip:Show()
		end
	end)
	slot:SetScript("OnLeave", GameTooltip_Hide)
	form.slot = slot

	form.itemLabel = MakeLabel(form, "", "GameFontNormal")
	form.itemLabel:SetPoint("TOPLEFT", slot, "TOPRIGHT", 10, -2)
	form.itemName = MakeEditBox(form, 220)
	form.itemName:SetPoint("BOTTOMLEFT", slot, "BOTTOMRIGHT", 16, 0)
	form.itemName:SetScript("OnEnterPressed", function(self)
		local text = strtrim(self:GetText())
		local itemID = tonumber(text:match("item:(%d+)")) or tonumber(text) or (text ~= "" and C_Item.GetItemInfoInstant(text))
		if itemID then
			SetItem(itemID)
		else
			self:ClearFocus()
			ns:Print("Unknown item \"" .. text .. "\". Try dropping it on the slot or shift-clicking it.")
		end
	end)
	form.itemHint = MakeLabel(form, "Drop an item on the slot, or type a name and press Enter. Shift-click an item while the box has focus.", "GameFontDisableSmall")
	form.itemHint:SetPoint("TOPLEFT", slot, "BOTTOMLEFT", 0, -6)
	form.itemHint:SetPoint("RIGHT", form, "RIGHT")

	form.amountLabel = MakeLabel(form, "")
	form.amountLabel:SetPoint("TOPLEFT", 2, -150)
	form.amount = MakeEditBox(form, 110, true)
	form.amount:SetPoint("LEFT", form.amountLabel, "LEFT", 160, 0)
	form.amount:SetScript("OnTextChanged", UpdateForm)
	form.amount:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if form.create:IsEnabled() then
			SubmitForm()
		end
	end)

	-- Starting count
	form.seedHeading = MakeHeading(form, "Start from what I have")
	form.seedHeading:SetPoint("TOPLEFT", 2, -186)
	form.seeds = {}
	for index = 1, 4 do
		local seed = CreateFrame("CheckButton", nil, form, "UICheckButtonTemplate")
		seed:SetSize(22, 22)
		seed:SetPoint("TOPLEFT", 0, -202 - (index - 1) * 24)
		seed.Text:SetFontObject("GameFontHighlight")
		seed:SetHitRectInsets(0, -150, 0, 0)
		seed:SetScript("OnClick", UpdateForm)
		seed.countText = form:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		seed.countText:SetPoint("LEFT", seed, "LEFT", 200, 1)
		seed.countText:SetWidth(90)
		seed.countText:SetJustifyH("RIGHT")
		seed:HookScript("OnShow", function(self)
			self.countText:Show()
		end)
		seed:HookScript("OnHide", function(self)
			self.countText:Hide()
		end)
		table.insert(form.seeds, seed)
	end
	form.othersText = MakeLabel(form, "", "GameFontDisableSmall")
	form.othersText:SetPoint("TOPLEFT", 26, -300)
	form.othersText:SetPoint("RIGHT", form, "RIGHT")
	form.startText = MakeLabel(form, "", "GameFontNormal")
	form.startText:SetPoint("TOPLEFT", 2, -324)

	form.create = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
	form.create:SetSize(190, 26)
	form.create:SetPoint("BOTTOMLEFT", 0, 0)
	form.create:SetScript("OnClick", SubmitForm)

	-- Shift-clicking an item while the name box has focus picks it.
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		hooksecurefunc(ChatFrameUtil, "InsertLink", function(link)
			if form:IsVisible() and form.itemName:HasFocus() and type(link) == "string" then
				local itemID = tonumber(link:match("item:(%d+)"))
				if itemID then
					SetItem(itemID)
				end
			end
		end)
	end
end

------------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------------

local function UpdateNav()
	local data = G().GetData()
	for _, button in ipairs(navButtons) do
		button:SetSelected(button.page == page or (button.page == "new" and page == "recount"))
		if button.page == "active" then
			button.count:SetText(#data.goals)
		elseif button.page == "history" then
			button.count:SetText(#data.history)
		end
	end
end

function Render()
	if not (frame and frame:IsShown()) then
		return
	end
	UpdateNav()
	pool:ReleaseAll()
	local showForm = page == "new" or page == "recount"
	form:SetShown(showForm)
	scroll:SetShown(not showForm)
	if showForm then
		UpdateForm()
		return
	end
	local content = scroll.content
	local width = content:GetWidth() - 2 * PAD
	local height = page == "history" and RenderHistory(content, width) or RenderActive(content, width)
	content:SetHeight(height)
	scroll:SetScroll(scroll:GetVerticalScroll())
end

-- Goals change every second while running: update the cards in place unless the
-- list itself changed.
local function OnGoalsChanged()
	if not (frame and frame:IsShown()) then
		return
	end
	if page ~= "active" then
		if page == "history" then
			UpdateNav()
		end
		return
	end
	local ids = {}
	for _, goal in ipairs(G().GetData().goals) do
		table.insert(ids, goal.id .. (goal.completed and "c" or ""))
	end
	if table.concat(ids, ",") ~= cardSignature then
		Render()
		return
	end
	for _, goal in ipairs(G().GetData().goals) do
		if cards[goal.id] then
			UpdateCard(cards[goal.id], goal)
		end
	end
	UpdateNav()
end

local function CreateGoalsWindow()
	frame = UI.CreateWindow("NraKitGoalsFrame", "Goals", WIDTH, HEIGHT, SIDEBAR_WIDTH)

	local anchor
	for _, info in ipairs({ { "active", "Active goals" }, { "new", "New goal" }, { "history", "History" } }) do
		local button = UI.CreateNavButton(frame.sidebar, SIDEBAR_WIDTH - 2 * PAD, 26, info[2])
		button.page = info[1]
		button:SetScript("OnClick", function(self)
			page = self.page
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			scroll:SetScroll(0)
			Render()
		end)
		if anchor then
			button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
		else
			button:SetPoint("TOPLEFT", PAD, -PAD)
		end
		anchor = button
		table.insert(navButtons, button)
	end

	scroll = UI.CreateScrollArea(frame.body)
	scroll:SetPoint("TOPLEFT")
	scroll:SetPoint("BOTTOMRIGHT", -13, 0)
	scroll.content:SetWidth(WIDTH - SIDEBAR_WIDTH - 15)

	CreateForm(frame.body)

	frame:SetScript("OnShow", Render)
	frame:RegisterEvent("BAG_UPDATE_DELAYED")
	frame:SetScript("OnEvent", function()
		if form:IsVisible() then
			UpdateForm()
		end
	end)
	ns.goals.onChanged = OnGoalsChanged
end

-- /nra goal, the tracker's "+" and "Recount". With a page, always shows it.
function ns:OpenGoalsWindow(toPage, goalID)
	if not ns:IsModuleEnabled("farmGoals") then
		ns:Print("Turn on Farm goals first (/nra).")
		return
	end
	if not frame then
		CreateGoalsWindow()
	end
	if not toPage and frame:IsShown() then
		frame:Hide()
		return
	end
	if toPage then
		page = toPage
		recountID = goalID
	end
	if page == "new" and formType == "level" and form.amount:GetText() == "" then
		form.amount:SetText(tostring(UnitLevel("player") + 1))
	end
	frame:Show()
	Render()
end
