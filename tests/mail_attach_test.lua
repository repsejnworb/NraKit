-- Mail: Alt+click a bag item with Send Mail open to attach every stack of it.

local SILK, POUCH = 4306, 828
-- Bags: [bag][slot] = { itemID, count, isBound?, isLocked? }.
local bags = {
	[0] = { { SILK, 20 }, { POUCH, 1 }, { SILK, 20 }, { SILK, 5, true } },
	[1] = { { SILK, 7 }, { POUCH, 1 }, { SILK, 3, false, true } },
}
local attached, cursor = {}, nil
local mailOpen, altDown = true, true

SendMailFrame = { IsVisible = function()
	return mailOpen
end }
ATTACHMENTS_MAX_SEND = 12
HasSendMailItem = function(index)
	return attached[index] ~= nil
end
ClickSendMailItemButton = function(index)
	if cursor then
		attached[index] = cursor
		bags[cursor.bag][cursor.slot][4] = true -- locked while attached
		cursor = nil
	end
end
CursorHasItem = function()
	return cursor ~= nil
end
IsAltKeyDown = function()
	return altDown
end
C_Container.GetContainerNumSlots = function(bag)
	return bags[bag] and #bags[bag] or 0
end
C_Container.GetContainerItemInfo = function(bag, slot)
	local item = bags[bag] and bags[bag][slot]
	return item and { itemID = item[1], stackCount = item[2], isBound = item[3] == true, isLocked = item[4] == true }
end
C_Container.GetContainerItemID = function(bag, slot)
	local item = bags[bag] and bags[bag][slot]
	return item and item[1]
end
C_Container.PickupContainerItem = function(bag, slot)
	cursor = { bag = bag, slot = slot, itemID = bags[bag][slot][1] }
end

-- The open bags' item buttons (what ns:ForEachBagItemButton reads).
local buttons = {}
for bag = 0, 1 do
	for slot = 1, #bags[bag] do
		local button = CreateFrame("Button")
		rawset(button, "GetBagID", function()
			return bag
		end)
		rawset(button, "GetID", function()
			return slot
		end)
		buttons[bag .. ":" .. slot] = button
		table.insert(buttons, button)
	end
end
ContainerFrameCombinedBags = { IsShown = function()
	return true
end, Items = buttons }
ContainerFrameContainer = { ContainerFrames = {} }

return {
	enable = { "mail" },
	run = function(t, ns, wow)
		local function AltClick(bag, slot)
			local button = buttons[bag .. ":" .. slot]
			button.scripts.OnClick(button, "LeftButton")
		end
		local function Attached(itemID)
			local stacks = 0
			for _, item in pairs(attached) do
				if item.itemID == itemID then
					stacks = stacks + 1
				end
			end
			return stacks
		end

		C_Timer.After = function(_, fn) -- the bag buttons are hooked a frame after MAIL_SHOW
			fn()
		end
		wow.fire("MAIL_SHOW")

		t.test("Alt+click attaches every stack of the item, not soulbound or locked ones", function()
			AltClick(0, 1)
			t.equal(Attached(SILK), 3, "the three free stacks of silk")
			t.equal(Attached(POUCH), 0, "nothing else")
			t.equal(cursor, nil, "nothing left on the cursor")
		end)

		t.test("a full mail takes what fits and says so", function()
			for index = 4, 11 do
				attached[index] = { itemID = 1 }
			end
			AltClick(0, 2)
			t.equal(Attached(POUCH), 1, "one pouch in the last slot")
			local said = false
			for _, line in ipairs(wow.printed) do
				said = said or line:find("Attached 1 of 2 stacks", 1, true) ~= nil
			end
			t.ok(said, "says the mail is full")
		end)

		t.test("only with Alt, Send Mail open and the option on", function()
			attached = {}
			bags[0][1][4], bags[0][3][4], bags[1][1][4] = nil, nil, nil
			altDown = false
			AltClick(0, 1)
			t.equal(Attached(SILK), 0, "plain click")
			altDown, mailOpen = true, false
			AltClick(0, 1)
			t.equal(Attached(SILK), 0, "mail closed")
			mailOpen = true
			ns:SetSetting("mailAttachAll", false)
			AltClick(0, 1)
			t.equal(Attached(SILK), 0, "option off")
			ns:SetSetting("mailAttachAll", true)
			ns:SetSetting("mail", false)
			AltClick(0, 1)
			t.equal(Attached(SILK), 0, "Mail off")
			t.noErrors()
		end)
	end,
}
