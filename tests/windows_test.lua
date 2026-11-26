-- NraKit's windows as tabs of one app, and the addon button's menu.

return {
	enable = { "inventoryTracker", "playerNotes" },
	run = function(t, ns, wow)
		local lastMenu
		MenuUtil.CreateContextMenu = function(_, generator)
			lastMenu = wow.newMenu()
			generator(nil, lastMenu)
		end
		local function Labels(entries)
			local labels = {}
			for _, entry in ipairs(entries) do
				if entry.kind == "button" then
					table.insert(labels, entry.text)
				end
			end
			return table.concat(labels, ", ")
		end

		local function Tab(key)
			return wow.findAll(function(frame)
				return wow.visible(frame) and rawget(frame, "tabKey") == key and frame.scripts.OnClick ~= nil
			end)[1]
		end

		t.test("every tab is there, also for features that are off", function()
			ns:OpenSettings()
			t.ok(NraKitOptionsFrame:IsShown(), "settings open")
			t.ok(Tab("inventory"), "Inventory tab")
			t.ok(Tab("notes"), "Notes tab")
			t.ok(Tab("goals"), "Goals tab while Farm Goals is off")
			t.ok(Tab("items"), "Lookup tab while Lookup is off")
		end)

		t.test("a tab whose feature is off says what it does and turns it on", function()
			t.ok(wow.click("Goals"), "Goals tab")
			t.ok(NraKitFeatureOffFrame:IsShown(), "the feature-is-off page")
			t.ok(not NraKitOptionsFrame:IsShown(), "in place of settings")
			t.ok(wow.findAll(function(frame)
				return wow.visible(frame) and frame.text == ns.modules.farmGoals.description
			end)[1], "its description")
			t.ok(wow.click("Lookup"), "another off tab")
			t.ok(NraKitFeatureOffFrame:IsShown(), "still the page")
			t.ok(wow.click("Turn on Lookup"), "turn-on button")
			t.equal(NraKitDB.itemLookup, true, "turned on")
			t.ok(NraKitItemLookupFrame:IsShown(), "its window opens")
			t.ok(not NraKitFeatureOffFrame:IsShown(), "in place of the page")
			ns:SetSetting("itemLookup", false)
			t.ok(NraKitFeatureOffFrame:IsShown(), "turned off again: back to the page")
			NraKitFeatureOffFrame:Hide()
		end)

		t.test("a tab replaces the open window", function()
			ns:OpenSettings()
			t.ok(wow.click("Notes"), "Notes tab")
			t.ok(NraKitPlayerNotesFrame:IsShown(), "notes open")
			t.ok(not NraKitOptionsFrame:IsShown(), "settings closed")
			t.ok(wow.click("Inventory"), "Inventory tab")
			t.ok(NraKitInventoryFrame:IsShown(), "inventory open")
			t.ok(not NraKitPlayerNotesFrame:IsShown(), "notes closed")
			t.ok(wow.click("Settings"), "Settings tab")
			t.ok(NraKitOptionsFrame:IsShown() and not NraKitInventoryFrame:IsShown(), "back to settings")
		end)

		t.test("opening a window by its command also closes the others", function()
			SlashCmdList.NRAKIT("note")
			t.ok(NraKitPlayerNotesFrame:IsShown() and not NraKitOptionsFrame:IsShown(), "one window")
			NraKitPlayerNotesFrame:Hide()
		end)

		t.test("dragging one moves them all", function()
			NraKitOptionsFrame:Show()
			NraKitOptionsFrame.titleBar.scripts.OnDragStop()
			t.ok(NraKitDB.windowPosition, "position saved")
			NraKitOptionsFrame:Hide()
		end)

		t.test("addon button: left-click settings, right-click a menu of windows", function()
			NraKit_OnCompartmentClick("NraKit", "LeftButton")
			t.ok(NraKitOptionsFrame:IsShown(), "settings")
			NraKit_OnCompartmentClick("NraKit", "RightButton")
			t.equal(Labels(lastMenu.entries), "Inventory, Player Notes, What's New, Settings", "menu")
			wow.menuEntry(lastMenu.entries, "Player Notes").onClick()
			t.ok(NraKitPlayerNotesFrame:IsShown() and not NraKitOptionsFrame:IsShown(), "notes from the menu")
			NraKit_OnCompartmentEnter("NraKit", UIParent)
		end)

		t.test("turning a feature on adds its menu entry", function()
			ns:SetSetting("farmGoals", true)
			NraKit_OnCompartmentClick("NraKit", "RightButton")
			t.equal(Labels(lastMenu.entries), "Inventory, Farm Goals, Player Notes, What's New, Settings", "menu")
			wow.menuEntry(lastMenu.entries, "Farm Goals").onClick()
			t.ok(NraKitGoalsFrame:IsShown() and not NraKitPlayerNotesFrame:IsShown(), "goals window")
			t.ok(Tab("goals"), "Goals tab")
			t.noErrors()
		end)
	end,
}
