-- Inventory Tracker and names: characters are "Firstname Surname", two of yours can share a
-- first name, and data saved by older versions under the first name alone moves over.

-- You're "Nra Kit". hooksecurefunc really hooks here (for SendMail).
local unitName = UnitName
UnitName = function(unit)
	if unit == "player" then
		return "Nra", "Kit"
	end
	return unitName(unit)
end
hooksecurefunc = function(name, hook)
	local original = _G[name]
	if original then
		_G[name] = function(...)
			original(...)
			hook(...)
		end
	end
end
local attached = {}
function SendMail() end
GetSendMailItem = function(index)
	local item = attached[index]
	if item then
		return "", item.id, 0, item.count
	end
end

local LINEN = 2589

return {
	enable = { "inventoryTracker", "farmGoals" },
	db = {
		-- Saved by an older version: by first name only.
		inventory = { Realm = {
			Nra = { class = "WARRIOR", bank = { [LINEN] = 5 } },
			Bob = { class = "MAGE", bags = { [LINEN] = 3 } },
		} },
		farmGoalsData = { ["Nra-Realm"] = { goals = {}, history = { { type = "level", target = 10 } } } },
	},
	run = function(t, ns, wow)
		local characters = NraKitDB.inventory.Realm

		local function TooltipLines(itemID)
			local lines = {}
			rawset(GameTooltip, "AddLine", function() end)
			rawset(GameTooltip, "AddDoubleLine", function(_, left, right)
				table.insert(lines, left .. ": " .. right)
			end)
			for _, call in ipairs(wow.tooltipCalls) do
				if call.type == Enum.TooltipDataType.Item then
					call.callback(GameTooltip, { id = itemID })
				end
			end
			return table.concat(lines, " | ")
		end

		local function Mail(recipient, count)
			attached = { { id = LINEN, count = count } }
			SendMail(recipient, "", "")
			wow.fire("MAIL_SEND_SUCCESS")
			attached = {}
		end

		t.test("your saved inventory and goals move to your full name", function()
			t.ok(characters["Nra Kit"], "inventory under Nra Kit")
			t.equal(characters.Nra, nil, "not under Nra any more")
			t.equal(characters["Nra Kit"].bank[LINEN], 5, "bank kept")
			t.equal(ns.inventory.GetPlayer(), "Nra Kit", "you")
			t.ok(NraKitDB.farmGoalsData["Nra Kit-Realm"], "goals moved")
			t.equal(NraKitDB.farmGoalsData["Nra-Realm"], nil, "old goals key gone")
			t.equal(#ns.goals.GetData().history, 1, "history kept")
		end)

		t.test("characters sharing a first name are kept apart in the tooltip", function()
			characters["Nra Smith"] = { class = "MAGE", bags = { [LINEN] = 7 } }
			local text = TooltipLines(LINEN)
			t.ok(text:find("Nra Kit: 5", 1, true), "you: " .. text)
			t.ok(text:find("Nra Smith: 7", 1, true), "the other Nra: " .. text)
			t.ok(text:find("Total: 15", 1, true), "total: " .. text)
		end)

		t.test("Holders lists everyone with the item, you too (for the Shopping list's have)", function()
			ns:SetSetting("inventoryTrackerCurrent", false)
			local holders = ns.inventory.Holders(LINEN)
			t.equal(holders[1].label, "Nra Kit", "you first, even with yourself off in tooltips")
			t.equal(holders[1].total, 5, "your count")
			t.equal(#holders, 3, "and the others")
			ns:SetSetting("inventoryTrackerCurrent", true)
		end)

		t.test("mail to your characters by full name", function()
			Mail("nra smith", 2)
			t.equal(characters["Nra Smith"].mail[LINEN], 2, "lowercase full name")
			Mail("Nra-Smith", 1)
			t.equal(characters["Nra Smith"].mail[LINEN], 3, "dash between the names")
			Mail("Nra", 4)
			t.equal(characters["Nra Kit"].mail, nil, "a first name two characters share matches neither")
			t.equal(characters["Nra Smith"].mail[LINEN], 3, "nor the other")
		end)

		t.test("mail finds a character still saved under its first name", function()
			Mail("Bob Stone", 6)
			t.equal(characters.Bob.mail[LINEN], 6, "old entry Bob")
		end)

		t.test("hovering your gold in the bags lists every character's gold", function()
			characters.Bob.money = 123456
			wow.data.money = 5000
			local lines, shown = {}, false
			rawset(GameTooltip, "AddDoubleLine", function(_, left, right)
				table.insert(lines, left .. ": " .. right)
			end)
			rawset(GameTooltip, "Show", function()
				shown = true
			end)
			GetMoneyString = false -- (the game's formatting with coin icons; here the plain one)
			local gold = ContainerFrame1MoneyFrame.GoldButton
			gold.scripts.OnEnter(gold)
			t.ok(shown, "a tooltip")
			t.equal(lines[1], ns:PlayerName() .. ": 0g 50s 0c", "you first, with what you have now")
			t.equal(lines[2], "Bob: 12g 34s 56c", "then the others")
			t.equal(lines[#lines], "Total: 12g 84s 56c", "and the total")
			-- The combined bags too; and the option turns it off.
			lines, shown = {}, false
			ns:SetSetting("inventoryTrackerMoney", false)
			local combined = ContainerFrameCombinedBags.MoneyFrame.CopperButton
			combined.scripts.OnEnter(combined)
			t.ok(not shown, "off: nothing")
			ns:SetSetting("inventoryTrackerMoney", true)
			combined.scripts.OnEnter(combined)
			t.ok(shown, "on the combined bags' gold too")
			rawset(GameTooltip, "AddDoubleLine", nil)
			rawset(GameTooltip, "Show", nil)
		end)

		t.test("forget takes the full name", function()
			SlashCmdList.NRAKIT("inv forget nra smith")
			t.equal(characters["Nra Smith"], nil, "forgotten")
			t.ok(characters["Nra Kit"], "you're still there")
			t.noErrors()
		end)
	end,
}
