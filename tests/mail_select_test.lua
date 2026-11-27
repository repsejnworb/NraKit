-- Mail: Open selected mail. Ticks stay on the mails you ticked, even among identical ones (a
-- batch your alt sent itself), as mails are emptied away; Shift-click ticks a range.

-- The inbox: { subject, items }; a mail with nothing left vanishes. Five identical mails, then two others.
local inbox
local function FreshInbox()
	inbox = {}
	for i = 1, 5 do
		inbox[i] = { subject = "Thorium Bar", items = 1, id = i }
	end
	table.insert(inbox, { subject = "Linen Cloth", items = 1, id = 6 })
	table.insert(inbox, { subject = "Wool Cloth", items = 1, id = 7 })
end
FreshInbox()

GetInboxNumItems = function()
	return #inbox
end
GetInboxHeaderInfo = function(index)
	local mail = inbox[index]
	return nil, nil, "Bank Alt", mail.subject, 0, 0, 29.5, mail.items, false, false, false, true, false
end
TakeInboxItem = function(index)
	inbox[index].items = inbox[index].items - 1
	if inbox[index].items == 0 then
		table.remove(inbox, index)
	end
end

-- Hooks really hook here.
hooksecurefunc = function(target, name, fn)
	if type(target) == "table" then
		local original = target[name]
		rawset(target, name, function(...)
			original(...)
			fn(...)
		end)
	else
		local original = _G[target]
		_G[target] = function(...)
			original(...)
			name(...)
		end
	end
end

-- Blizzard's Open All button and the inbox's rows (all 7 on one page).
OpenAllMail = CreateFrame("Button")
rawset(OpenAllMail, "ShouldSkipCurrentMail", function()
	return false
end)
local opening = false -- the button is disabled while it opens
rawset(OpenAllMail, "StopOpening", function()
	opening = false
end)
rawset(OpenAllMail, "IsEnabled", function()
	return not opening
end)
INBOXITEMS_TO_DISPLAY = 7
OPEN_ALL_MAIL_BUTTON = "Open All"
for i = 1, 7 do
	CreateFrame("Frame", "MailItem" .. i)
	rawset(CreateFrame("Button", "MailItem" .. i .. "Button"), "index", i)
end
local shift = false
IsShiftKeyDown = function()
	return shift
end

return {
	enable = { "mail" },
	run = function(t, ns, wow)
		local checkboxes = {}
		for _, frame in ipairs(wow.frames) do
			local row = rawget(frame, "row")
			if row then
				checkboxes[row] = frame
			end
		end
		local function Click(row, withShift)
			shift = withShift == true
			checkboxes[row]:GetScript("OnClick")(checkboxes[row])
			shift = false
		end
		-- Which mails (by id) Open All would open now.
		local function Opened()
			local list = {}
			for index, mail in ipairs(inbox) do
				OpenAllMail.mailIndex = index
				if not OpenAllMail:ShouldSkipCurrentMail() then
					table.insert(list, mail.id)
				end
			end
			return table.concat(list, ",")
		end
		-- Open All on the selection, like Blizzard's: take from a mail until it's gone, start over.
		local function OpenAll()
			opening = true
			local index = 1
			while inbox[index] do
				OpenAllMail.mailIndex = index
				if OpenAllMail:ShouldSkipCurrentMail() then
					index = index + 1
				else
					TakeInboxItem(index)
				end
			end
			OpenAllMail:StopOpening()
		end

		t.test("ticking one of identical mails ticks just that one", function()
			t.ok(checkboxes[2] ~= nil, "a checkbox per row")
			Click(2)
			t.equal(Opened(), "2", "only the second Thorium Bar")
			t.equal(OpenAllMail:GetText(), "Open Selected (1)", "the button says one")
		end)

		t.test("Shift-click ticks every mail in between", function()
			Click(5, true)
			t.equal(Opened(), "2,3,4,5", "from the one clicked before to this one")
			Click(3, true)
			t.equal(Opened(), "2", "Shift-click on a ticked one unticks the range")
		end)

		t.test("Open All opens just the ticked ones, though the others look the same", function()
			Click(4)
			Click(6)
			t.equal(Opened(), "2,4,6", "ticked")
			OpenAll()
			local left = {}
			for _, mail in ipairs(inbox) do
				table.insert(left, mail.id)
			end
			t.equal(table.concat(left, ","), "1,3,5,7", "the unticked ones are still there")
			t.equal(OpenAllMail:GetText(), OPEN_ALL_MAIL_BUTTON, "nothing selected any more")
		end)

		t.test("ticks stay on their mails when one above is taken by hand", function()
			FreshInbox()
			Click(4)
			TakeInboxItem(1)
			t.equal(Opened(), "4", "still the fourth mail, now third in the inbox")
		end)

		t.test("with the option off, Open All doesn't read the inbox for it", function()
			ns:SetSetting("openSelectedMail", false)
			local reads = 0
			local header = GetInboxHeaderInfo
			GetInboxHeaderInfo = function(...)
				reads = reads + 1
				return header(...)
			end
			TakeInboxItem(1)
			Opened()
			t.equal(reads, 0, "nothing read")
			GetInboxHeaderInfo = header
			ns:SetSetting("openSelectedMail", true)
		end)
	end,
}
