-- Fill in mail subject: the subject text, and when it may replace what's in the box.

return {
	enable = { "mailSubject" },
	run = function(t, ns, wow)
		local mailSubject = ns.mailSubject
		local function Items(...)
			local list = {}
			for index = 1, select("#", ...), 2 do
				table.insert(list, { name = select(index, ...), count = select(index + 1, ...) })
			end
			return list
		end

		t.test("money text", function()
			t.equal(mailSubject.MoneyText(250000), "25g", "gold")
			t.equal(mailSubject.MoneyText(52010), "5g 20s 10c", "gold, silver, copper")
			t.equal(mailSubject.MoneyText(305), "3s 5c", "no gold")
		end)

		t.test("subjects", function()
			t.equal(mailSubject.Subject({}, 0, false), "", "empty mail")
			t.equal(mailSubject.Subject(Items("Linen Cloth", 1), 0, false), "Linen Cloth", "one item")
			t.equal(mailSubject.Subject(Items("Linen Cloth", 20, "Linen Cloth", 20), 0, false), "Linen Cloth (40)", "stacks add up")
			t.equal(mailSubject.Subject(Items("Linen Cloth", 20, "Wool Cloth", 5), 0, false), "Linen Cloth (20), Wool Cloth (5)", "two kinds")
			t.equal(mailSubject.Subject({}, 250000, false), "25g", "gold only")
			t.equal(mailSubject.Subject(Items("Linen Cloth", 20), 50000, false), "Linen Cloth (20) + 5g", "items and gold")
			t.equal(mailSubject.Subject(Items("Linen Cloth", 20), 50000, true), "Linen Cloth (20) (C.O.D. 5g)", "C.O.D.")
			t.equal(mailSubject.Subject({}, 50000, true), "", "C.O.D. without items says nothing")
		end)

		t.test("too many kinds: the first ones and how many more", function()
			local subject = mailSubject.Subject(Items("Heavy Mageweave Bandage", 20, "Runecloth Bandage", 20,
				"Mageweave Bandage", 20, "Silk Bandage", 20), 0, false)
			t.ok(#subject <= 64, "fits: " .. subject)
			t.ok(subject:find(" more$"), "says more: " .. subject)
			t.ok(subject:find("^Heavy Mageweave Bandage %(20%)"), "starts with the first item: " .. subject)
		end)

		-- A stand-in send-mail frame.
		local attached, money, cod = {}, 0, false
		SendMailSubjectEditBox = CreateFrame("EditBox")
		SendMailMoney = CreateFrame("Frame")
		SendMailCODButton = { GetChecked = function()
			return cod
		end }
		SendMailFrame = {}
		ATTACHMENTS_MAX_SEND = 12
		HasSendMailItem = function(index)
			return attached[index] ~= nil
		end
		GetSendMailItem = function(index)
			local item = attached[index]
			return item.name, item.id, 0, item.count
		end
		MoneyInputFrame_GetCopper = function()
			return money
		end
		local box = SendMailSubjectEditBox

		t.test("fills an empty subject and follows the attachments", function()
			attached = { { name = "Linen Cloth", id = 2589, count = 20 } }
			mailSubject.Update()
			t.equal(box:GetText(), "Linen Cloth (20)", "item")
			attached[2] = { name = "Linen Cloth", id = 2589, count = 20 }
			money = 50000
			mailSubject.Update()
			t.equal(box:GetText(), "Linen Cloth (40) + 5g", "more items and gold")
			attached, money = {}, 0
			mailSubject.Update()
			t.equal(box:GetText(), "", "cleared again")
		end)

		t.test("replaces Blizzard's own subject", function()
			box:SetText("Linen Cloth")
			SendMailFrame.previousItem = "Linen Cloth"
			attached = { { name = "Linen Cloth", id = 2589, count = 1 }, { name = "Wool Cloth", id = 2592, count = 1 } }
			mailSubject.Update()
			t.equal(box:GetText(), "Linen Cloth, Wool Cloth", "replaced")
		end)

		t.test("never touches a subject you typed", function()
			box:SetText("Mats for the shoulders")
			money = 10000
			mailSubject.Update()
			t.equal(box:GetText(), "Mats for the shoulders", "kept")
			attached, money = {}, 0
			mailSubject.Update()
			t.equal(box:GetText(), "Mats for the shoulders", "kept after removing everything")
		end)

		t.test("waits for an item name that isn't loaded yet", function()
			box:SetText("")
			attached = { { id = 4338, count = 10 } }
			mailSubject.Update()
			t.equal(box:GetText(), "", "nothing yet")
			wow.data.items[4338] = { name = "Mageweave Cloth", bags = 0, bank = 0 }
			wow.fire("GET_ITEM_INFO_RECEIVED", 4338, true)
			t.equal(box:GetText(), "Mageweave Cloth (10)", "filled once loaded")
		end)

		t.test("does nothing while the feature is off", function()
			ns:SetSetting("mailSubject", false)
			box:SetText("")
			attached = { { name = "Linen Cloth", id = 2589, count = 1 } }
			mailSubject.Update()
			t.equal(box:GetText(), "", "untouched")
			t.noErrors()
		end)
	end,
}
