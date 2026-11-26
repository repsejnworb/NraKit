-- What Farm Goals are worth: item goals priced at the auction house (Auctionator, as the Sell
-- List reads it), gold per hour, "worth ~85g" when done; and the Sell List keeping a goal's
-- items apart until the goal is done.

local MITHRIL = 3858
local MITHRIL_LINK = "|cffffffff|Hitem:3858::::::::30:::::|h[Mithril Ore]|h|r"

Enum.BagIndex = { Backpack = 0 }
-- 30 Mithril Ore in your bags.
C_Container.GetContainerNumSlots = function(bag)
	return bag == 0 and 1 or 0
end
C_Container.GetContainerItemInfo = function(bag, slot)
	if bag == 0 and slot == 1 then
		return { itemID = MITHRIL, stackCount = 30, hyperlink = "item:3858", iconFileID = 1, quality = 1 }
	end
end
C_Item.GetItemInfo = function(item)
	if tostring(item):find("3858", 1, true) then
		return "Mithril Ore", "item:3858", 1, 1, 1, "", "", 20, "", 1, 500, 0, 0, 0
	end
end
-- Auctionator: 2g 13s each, seen a day ago.
Auctionator = { API = { v1 = {
	GetAuctionPriceByItemID = function(_, id)
		return id == MITHRIL and 21300 or nil
	end,
	GetAuctionPriceByItemLink = function(_, link)
		return tostring(link):find("3858", 1, true) and 21300 or nil
	end,
	GetAuctionAgeByItemID = function()
		return 1
	end,
	GetAuctionAgeByItemLink = function()
		return 1
	end,
} } }

return {
	enable = { "farmGoals", "sellList" },
	run = function(t, ns, wow)
		local goal = ns.goals.AddGoal({ type = "item", itemID = MITHRIL, target = 40 })

		t.test("an item goal shows gold per hour", function()
			goal.gained, goal.active = 32, 6400 -- 18 an hour
			local rate = ns.goals.DescribeRate(goal)
			t.ok(rate:find("18/h", 1, true), "items per hour: " .. rate)
			t.ok(rate:find("~38g/h", 1, true), "and gold per hour (18 x 2g 13s): " .. rate)
		end)

		t.test("its items are kept apart on the Sell List while you're farming them", function()
			local groups = ns.sellList.Collect()
			t.equal(#groups.goals, 1, "in For Your Farm Goals")
			t.equal(#groups.ah, 0, "not To Sell")
		end)

		t.test("done: the message says what it's worth, and the items can be sold", function()
			local shown
			local show = ns.toast.Show
			ns.toast.Show = function(message)
				shown = message
			end
			wow.fire("CHAT_MSG_LOOT", "You receive loot: " .. MITHRIL_LINK .. "x8.")
			ns.toast.Show = show
			t.ok(goal.completed, "done")
			t.ok(shown and shown.detail:find("worth ~85g", 1, true), "worth ~85g (40 x 2g 13s): " .. tostring(shown and shown.detail))
			local groups = ns.sellList.Collect()
			t.equal(#groups.goals, 0, "no longer apart")
			t.equal(#groups.ah, 1, "To Sell: Auction House")
		end)

		t.test("with the option off, no worth is shown", function()
			local running = ns.goals.AddGoal({ type = "item", itemID = MITHRIL, target = 100 })
			running.gained, running.active = 10, 3600
			t.ok(ns.goals.DescribeRate(running):find("g/h", 1, true), "on: gold per hour")
			ns:SetSetting("farmGoalsValue", false)
			t.ok(not ns.goals.DescribeRate(running):find("g/h", 1, true), "off: none")
			ns:SetSetting("farmGoalsValue", true)
			t.noErrors()
		end)
	end,
}
