-- NraKit button: a movable icon with a badge for what's waiting, click actions you pick and
-- NraKit's menu on right-click.

C_Timer.After = function(_, callback)
	if debug.getinfo(callback, "S").source:find("Reminders", 1, true) then
		callback()
	end
end

return {
	enable = { "nraButton", "reminders", "wishlist" },
	run = function(t, ns, wow)
		local menu
		MenuUtil.CreateContextMenu = function(_, build)
			menu = wow.newMenu()
			build(nil, menu)
		end
		local button = NraKitButton
		local badge = rawget(button, "badge")
		local function Click(mouseButton)
			button.scripts.OnClick(button, mouseButton or "LeftButton")
		end

		t.test("on screen, no badge while nothing is waiting", function()
			t.ok(button:IsShown(), "shown")
			t.ok(not badge:IsShown(), "no badge")
		end)

		t.test("a due reminder: counted on the badge; a click shows it", function()
			ns.reminders.Add({ text = "feed the pet" })
			wow.fire("PLAYER_ENTERING_WORLD", true, false)
			t.ok(badge:IsShown(), "badge")
			t.equal(rawget(badge.text, "text"), 1, "count")
			wow.click("Later")
			t.ok(NraKitRemindersTracker:IsShown(), "tracker")
			NraKitDB.remindersTrackerFolded = true
			Click()
			t.ok(not NraKitDB.remindersTrackerFolded, "the click unfolds the list")
			ns.reminders.SetDone(ns.reminders.Due()[1].id, true)
			t.ok(not badge:IsShown(), "gone when done")
		end)

		t.test("to-dos don't count on the badge (a to-do list is rarely empty)", function()
			SlashCmdList.NRAKIT("todo respec")
			t.ok(#ns.reminders.Due() == 1 and not badge:IsShown(), "no badge for a to-do")
			ns.reminders.SetDone(ns.reminders.Due()[1].id, true)
		end)

		t.test("nothing waiting: a click opens the NraKit window", function()
			Click()
			t.ok(NraKitOptionsFrame:IsShown(), "NraKit window")
			NraKitOptionsFrame:Hide()
		end)

		t.test("shift-click and click do what you pick", function()
			ns:SetSetting("nraButtonShiftClick", "wishlist")
			wow.data.shift = true
			IsShiftKeyDown = function()
				return true
			end
			Click()
			t.ok(NraKitWishlistFrame:IsShown(), "wishlist")
			NraKitWishlistFrame:Hide()
			IsShiftKeyDown = function()
				return false
			end
			ns:SetSetting("nraButtonLeftClick", "menu")
			menu = nil
			Click()
			t.ok(menu and wow.menuEntry(menu.entries, "Wishlist"), "the menu")
			ns:SetSetting("nraButtonLeftClick", "waiting")
		end)

		t.test("right-click: NraKit's menu, with locking", function()
			Click("RightButton")
			t.ok(wow.menuEntry(menu.entries, "Reminders") and wow.menuEntry(menu.entries, "Settings"), "windows and settings")
			wow.menuEntry(menu.entries, "Lock the button").onClick()
			t.ok(ns:GetOption("nraButtonLock"), "locked")
			local moved = false
			rawset(button, "StartMoving", function()
				moved = true
			end)
			button.scripts.OnDragStart(button)
			t.ok(not moved, "doesn't move while locked")
			ns:SetSetting("nraButtonLock", false)
			button.scripts.OnDragStart(button)
			t.ok(moved, "moves")
		end)

		t.test("what's new counts only if you want it to", function()
			NraKitDB.changelogSeen = #ns.whatsNew.Entries() - 2
			ns:BadgeChanged()
			t.ok(not badge:IsShown(), "off by default")
			ns:SetSetting("nraButtonBadgeWhatsNew", true)
			t.equal(rawget(badge.text, "text"), 2, "two changes")
			ns:SetSetting("nraButtonBadge", false)
			t.ok(not badge:IsShown(), "no badge at all")
			ns:SetSetting("nraButtonBadge", true)
			ns.whatsNew.MarkSeen()
			t.ok(not badge:IsShown(), "seen")
		end)

		t.test("the click choices are dropdowns in the NraKit window", function()
			ns:OpenSettings("NraKit button", "nraButton")
			local found
			for _, frame in ipairs(wow.frames) do
				local option = rawget(frame, "option")
				if type(option) == "table" and option.key == "nraButtonShiftClick" and wow.visible(frame) then
					found = frame
				end
			end
			t.ok(found, "dropdown")
			found.scripts.OnClick(found)
			wow.menuEntry(menu.entries, "Farm goals window").onClick("goals")
			t.equal(ns:GetValue("nraButtonShiftClick"), "goals", "picked")
			t.equal(rawget(found.text, "text"), "Farm goals window", "shows it")
			NraKitOptionsFrame:Hide()
		end)

		t.test("a new size keeps the button's centre where it is", function()
			local point
			rawset(button, "GetCenter", function()
				return 500, 400
			end)
			rawset(button, "SetPoint", function(_, ...)
				point = { ... }
			end)
			button.scripts.OnDragStop(button)
			t.ok(point[1] == "CENTER" and point[4] == 500 and point[5] == 400, "dragged: its centre")
			ns:SetSetting("nraButtonScale", 2)
			t.ok(point[4] == 250 and point[5] == 200, "the same centre on screen at double size")
			ns:SetSetting("nraButtonScale", 1)
			t.ok(point[4] == 500 and point[5] == 400, "and back")
		end)

		t.test("hide in combat; off hides it", function()
			ns:SetSetting("nraButtonHideInCombat", true)
			wow.fire("PLAYER_REGEN_DISABLED")
			t.ok(not button:IsShown(), "hidden in combat")
			wow.fire("PLAYER_REGEN_ENABLED")
			t.ok(button:IsShown(), "back")
			ns:SetSetting("nraButton", false)
			t.ok(not button:IsShown(), "off")
			t.noErrors()
		end)
	end,
}
