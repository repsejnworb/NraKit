local _, ns = ...

-- Fill in mail subject: writes the subject of a mail you're sending from what's attached,
-- "Linen Cloth (40)", "Linen Cloth (40), Wool Cloth (20)", "25g" or "Linen Cloth (20) + 5g".
--
-- Blizzard's own version (SendMailFrame_Update) only names the first item and doesn't
-- always fire on Forever, so we redo it after every update, after any money box changes and
-- after Send Money / C.O.D. is switched. A subject is only replaced when it's empty or
-- still the one we (or Blizzard) wrote, so a subject you typed is never touched.

local module = {
	key = "mailSubject",
	section = "Utilities",
	name = "Fill in mail subject",
	description = "Writes the subject of a mail you're sending from what you attach: \"Linen Cloth (40)\", \"25g\" or \"Linen Cloth (20) + 5g\". A subject you typed yourself is left alone.",
	default = false,
}

local MAX_LETTERS = 64 -- the subject box's limit

local mailSubject = {}
ns.mailSubject = mailSubject

local lastSubject -- the subject we wrote last
local waitingForNames = false

-- 52010 copper -> "5g 20s 10c" (no colors or icons: it's plain mail text).
function mailSubject.MoneyText(copper)
	local gold = math.floor(copper / 10000)
	local silver = math.floor(copper / 100) % 100
	local parts = {}
	if gold > 0 then
		table.insert(parts, gold .. "g")
	end
	if silver > 0 then
		table.insert(parts, silver .. "s")
	end
	if copper % 100 > 0 then
		table.insert(parts, copper % 100 .. "c")
	end
	return table.concat(parts, " ")
end

-- items: { { name, count }, ... } in attachment order; money: copper; cod: true if the
-- money is a C.O.D. amount. Returns the subject, or "" for an empty mail.
function mailSubject.Subject(items, money, cod)
	local kinds, byName = {}, {}
	for _, item in ipairs(items) do
		local kind = byName[item.name]
		if not kind then
			kind = { name = item.name, count = 0 }
			byName[item.name] = kind
			table.insert(kinds, kind)
		end
		kind.count = kind.count + math.max(item.count or 1, 1)
	end
	local names = {}
	for index, kind in ipairs(kinds) do
		names[index] = kind.count > 1 and string.format("%s (%d)", kind.name, kind.count) or kind.name
	end

	local suffix = ""
	if money and money > 0 then
		if cod and #kinds > 0 then
			suffix = " (C.O.D. " .. mailSubject.MoneyText(money) .. ")"
		elseif not cod then
			suffix = #kinds > 0 and (" + " .. mailSubject.MoneyText(money)) or mailSubject.MoneyText(money)
		end
	end

	-- All the item names if they fit, else the first ones and "and N more".
	local subject = table.concat(names, ", ")
	if #subject + #suffix > MAX_LETTERS then
		for shown = #names - 1, 1, -1 do
			subject = table.concat(names, ", ", 1, shown) .. " and " .. (#names - shown) .. " more"
			if #subject + #suffix <= MAX_LETTERS or shown == 1 then
				break
			end
		end
	end
	return (subject .. suffix):sub(1, MAX_LETTERS)
end

-- The items attached to the mail being written, or nil if a name isn't loaded yet.
local function AttachedItems()
	local items = {}
	for index = 1, ATTACHMENTS_MAX_SEND or 12 do
		if HasSendMailItem(index) then
			local name, itemID, _, count = GetSendMailItem(index)
			name = name or (itemID and C_Item.GetItemNameByID(itemID))
			if not name then
				return nil
			end
			table.insert(items, { name = name, count = count })
		end
	end
	return items
end

function mailSubject.Update()
	if not ns:IsModuleEnabled(module.key) or not SendMailSubjectEditBox then
		return
	end
	local items = AttachedItems()
	if not items then
		waitingForNames = true -- GET_ITEM_INFO_RECEIVED tries again
		return
	end
	waitingForNames = false
	local money = SendMailMoney and MoneyInputFrame_GetCopper(SendMailMoney) or 0
	local cod = SendMailCODButton and SendMailCODButton:GetChecked() or false
	local subject = mailSubject.Subject(items, money, cod)

	local current = SendMailSubjectEditBox:GetText()
	local blizzards = SendMailFrame and SendMailFrame.previousItem
	if current ~= "" and current ~= lastSubject and current ~= blizzards then
		return -- typed by the player
	end
	lastSubject = subject
	if current ~= subject then
		SendMailSubjectEditBox:SetText(subject)
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function()
	if waitingForNames then
		mailSubject.Update()
	end
end)

function module:OnInitialize()
	if not SendMailFrame_Update or not SendMailSubjectEditBox then
		return
	end
	hooksecurefunc("SendMailFrame_Update", mailSubject.Update)
	-- The money boxes call the MoneyInputFrame_OnTextChanged (and SendMailFrame_CanSend) they
	-- saved when loading (XML function="..."), so hooking those globals never runs: watch
	-- the gold, silver and copper boxes themselves.
	for _, key in ipairs({ "gold", "silver", "copper" }) do
		local editBox = SendMailMoney and SendMailMoney[key]
		if editBox then
			editBox:HookScript("OnTextChanged", mailSubject.Update)
		end
	end
	hooksecurefunc("SendMailRadioButton_OnClick", mailSubject.Update)
	eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
end

function module:OnEnabledChanged()
	mailSubject.Update()
end

ns:RegisterModule(module)
