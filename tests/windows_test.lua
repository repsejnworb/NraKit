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

		t.test("tabs only for features that are on", function()
			ns:OpenSettings()
			t.ok(NraKitOptionsFrame:IsShown(), "settings open")
			t.ok(wow.findAll(function(frame)
				return wow.visible(frame) and rawget(frame, "tabKey") == "inventory"
			end)[1], "Inventory tab")
			t.ok(wow.findAll(function(frame)
				return wow.visible(frame) and rawget(frame, "tabKey") == "notes"
			end)[1], "Notes tab")
			t.ok(not wow.findAll(function(frame)
				return wow.visible(frame) and rawget(frame, "tabKey") == "goals"
			end)[1], "no Goals tab while Farm goals is off")
		end)

		t.test("a tab replaces the open window", function()
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
			t.equal(Labels(lastMenu.entries), "Inventory, Player notes, What's new, Settings", "menu")
			wow.menuEntry(lastMenu.entries, "Player notes").onClick()
			t.ok(NraKitPlayerNotesFrame:IsShown() and not NraKitOptionsFrame:IsShown(), "notes from the menu")
			NraKit_OnCompartmentEnter("NraKit", UIParent)
		end)

		t.test("turning a feature on adds its tab and menu entry", function()
			ns:SetSetting("farmGoals", true)
			NraKit_OnCompartmentClick("NraKit", "RightButton")
			t.equal(Labels(lastMenu.entries), "Inventory, Farm goals, Player notes, What's new, Settings", "menu")
			wow.menuEntry(lastMenu.entries, "Farm goals").onClick()
			t.ok(NraKitGoalsFrame:IsShown() and not NraKitPlayerNotesFrame:IsShown(), "goals window")
			t.ok(wow.findAll(function(frame)
				return wow.visible(frame) and rawget(frame, "tabKey") == "goals"
			end)[1], "Goals tab")
		end)
	end,
}
