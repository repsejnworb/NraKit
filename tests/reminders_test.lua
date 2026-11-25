-- Reminders: notes for your next login, after a time, in a zone, at a level or for another
-- character. Due ones show on a card you close yourself; the rest go to the tracker.

-- This module's timers run at once; other modules' don't run, as usual here.
C_Timer.After = function(_, callback)
	local source = debug.getinfo(callback, "S").source
	if source:find("Reminders", 1, true) or source:find("Toast", 1, true) then
		callback()
	end
end

local now = 1700000000
time = function()
	return now
end

return {
	enable = { "reminders" },
	db = { remindersData = { nextID = 1, characters = { ["Bob Stone"] = { seen = true, list = {} } } } },
	run = function(t, ns, wow)
		SOUNDKIT.ALARM_CLOCK_WARNING_3 = 12345
		local reminders = ns.reminders
		local function Login()
			wow.fire("PLAYER_ENTERING_WORLD", true, false)
		end
		local function Mine(text)
			for _, reminder in ipairs(reminders.List()) do
				if reminder.text == text then
					return reminder
				end
			end
		end
		local function Rows(parent)
			return wow.findAll(function(frame)
				return rawget(frame, "reminderID") and wow.visible(frame) and rawget(frame, "parent") == parent
			end)
		end
		-- Whether the card shows this text (a button, a label).
		local function Shown(text)
			for _, frame in ipairs(wow.frames) do
				local value = rawget(frame, "text")
				if type(value) == "table" then
					value = rawget(value, "text")
				end
				local inCard, parent = false, frame
				while parent do
					inCard = inCard or parent == NraKitRemindersCard
					parent = rawget(parent, "parent")
				end
				if value == text and inCard and wow.visible(frame) then
					return true
				end
			end
			return false
		end
		local function Remind(text)
			wow.printed = {}
			SlashCmdList.NRAKIT("remind " .. text)
			return wow.printed[1]
		end
		Login()

		t.test("the words after /nra remind: a trigger in front, else the next login", function()
			local spec = reminders.Parse("10 boar livers for Gubber")
			t.equal(spec.kind, "login", "a number without a unit is text")
			t.equal(spec.text, "10 boar livers for Gubber", "all of it")
			spec = reminders.Parse("in the morning check mail")
			t.equal(spec.kind, "login", "no colon, no zone")
			spec = reminders.Parse("30m check the AH")
			t.ok(spec.kind == "time" and spec.at == now + 1800 and spec.text == "check the AH", "30 minutes")
			t.equal(reminders.Parse("1h30m: x").at, now + 5400, "1h30m, with a colon")
			t.equal(reminders.Parse("2d x").at, now + 2 * 86400, "days")
			spec = reminders.Parse("in Stranglethorn Vale: buy |cffffffff|Hitem:4306::::::::|h[Silk Cloth]|h|r")
			t.ok(spec.kind == "zone" and spec.zone == "Stranglethorn Vale", "zone with spaces")
			t.ok(spec.text:find("|Hitem:4306", 1, true), "links kept")
			spec = reminders.Parse("at 40: train")
			t.ok(spec.kind == "level" and spec.level == 40 and spec.text == "train", "level")
			local _, problem = reminders.Parse("at 20: too late")
			t.ok(problem and problem:find("level 30 already", 1, true), "a level you have: " .. tostring(problem))
			_, problem = reminders.Parse("30m")
			t.ok(problem, "nothing to say")
		end)

		t.test("@character: a known one by first or full name, any spelling; others saved anyway", function()
			local spec = reminders.Parse("@bob: mail the bags")
			t.ok(spec.character == "Bob Stone" and spec.known and spec.kind == "login" and spec.text == "mail the bags", "first name")
			spec = reminders.Parse("@Bob-Stone at 40: buy the mount")
			t.ok(spec.character == "Bob Stone" and spec.kind == "level" and spec.level == 40 and spec.text == "buy the mount", "full name, with a trigger")
			spec = reminders.Parse("@Newbie: hi")
			t.ok(spec.character == "Newbie" and not spec.known, "unknown")
			t.ok(Remind("@newbie: hi"):find("Newbie", 1, true), "said who")
			t.ok(wow.printed[2]:find("haven't seen", 1, true), "and that it's not known yet")
			spec = reminders.Parse("@Nra: just me")
			t.equal(spec.character, nil, "yourself is a normal reminder")
		end)

		t.test("a login reminder: on the card at the next login, and the sound plays", function()
			t.ok(Remind("Go to Darkshore and hand in quests"):find("next login", 1, true), "confirmed")
			t.equal(Mine("Go to Darkshore and hand in quests").state, "waiting", "not this session")
			wow.played = {}
			Login()
			t.equal(Mine("Go to Darkshore and hand in quests").state, "due", "due")
			t.ok(NraKitRemindersCard:IsShown(), "card")
			t.equal(#Rows(NraKitRemindersCard), 1, "one row")
			t.equal(wow.played[1], 12345, "sound")
			t.ok(NraKitRemindersTracker:IsShown(), "the tracker stays up with the card")
			t.ok(Shown("Done") and Shown("Later"), "one reminder: Done and Later")
			t.ok(Shown("From last time"), "why it's there")
		end)

		t.test("closing it with one not ticked: the tracker keeps it, and the card shows it at the next login", function()
			wow.click("Later")
			t.ok(not NraKitRemindersCard:IsShown(), "closed")
			t.ok(NraKitRemindersTracker:IsShown(), "tracker")
			t.equal(#Rows(NraKitRemindersTracker), 1, "in the tracker")
			Login()
			t.ok(NraKitRemindersCard:IsShown(), "back at login")
		end)

		t.test("ticking it off: done, and the tracker goes", function()
			local row = Rows(NraKitRemindersCard)[1]
			row.check.scripts.OnClick(row.check)
			t.equal(Mine("Go to Darkshore and hand in quests").state, "done", "done")
			t.ok(wow.click("Close"), "the button says Close once all are done")
			t.ok(not NraKitRemindersTracker:IsShown(), "no tracker")
			Login()
			t.ok(not NraKitRemindersCard:IsShown(), "not at the next login")
		end)

		t.test("a timed reminder: due when the time comes, but not in combat", function()
			Remind("10m check the auction house")
			reminders.Check()
			t.equal(Mine("check the auction house").state, "waiting", "not yet")
			now = now + 600
			wow.data.inCombat = true
			reminders.Check()
			t.equal(Mine("check the auction house").state, "due", "due")
			t.ok(not NraKitRemindersCard:IsShown(), "no card in combat")
			wow.data.inCombat = false
			wow.fire("PLAYER_REGEN_ENABLED")
			t.ok(NraKitRemindersCard:IsShown(), "after combat")
			local row = Rows(NraKitRemindersCard)[1]
			row.check.scripts.OnClick(row.check)
			NraKitRemindersCard:Hide()
		end)

		t.test("one that came due while you were logged out says so", function()
			Remind("1h raid tonight")
			now = now + 7200
			Login()
			local reminder = Mine("raid tonight")
			t.ok(reminder.state == "due" and reminder.away, "away")
			t.ok(reminders.DueNote(reminder):find("while you were away", 1, true), "said")
			reminders.SetDone(reminder.id, true)
			NraKitRemindersCard:Hide()
		end)

		t.test("a zone reminder: when you're in it, straight away if you write it there", function()
			wow.data.zone = "Elwynn Forest"
			Remind("in darkshore: turtle quest")
			t.equal(Mine("turtle quest").state, "waiting", "not there")
			Remind("in Elwynn Forest: sell the junk")
			t.equal(Mine("sell the junk").state, "due", "you're there: due now")
			t.ok(NraKitRemindersCard:IsShown(), "card")
			wow.click("Done")
			wow.data.zone = "Darkshore"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			t.equal(Mine("turtle quest").state, "due", "entered Darkshore (any case)")
			wow.click("Done")
			GetSubZoneText = function()
				return ""
			end
			wow.data.zone = "The Barrens"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			Remind("in Ratchet: boat")
			t.equal(Mine("boat").state, "waiting", "not in Ratchet yet")
			GetSubZoneText = function()
				return "Ratchet"
			end
			wow.fire("ZONE_CHANGED")
			t.equal(Mine("boat").state, "due", "subzones count")
			wow.click("Done")
			GetSubZoneText = function()
				return ""
			end
			wow.data.zone = "Elwynn Forest"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			t.equal(#reminders.Due(), 0, "all done")
		end)

		t.test("the card: what popped it up on top, what's still open under it", function()
			Remind("old one")
			Login()
			wow.click("Later")
			Remind("in Stormwind: buy a mount")
			wow.data.zone = "Stormwind"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			t.ok(NraKitRemindersCard:IsShown(), "card")
			t.ok(Shown("You entered Stormwind") and Shown("buy a mount"), "the why and the reminder")
			t.ok(not Shown("old one"), "the old one isn't listed mid-session")
			t.ok(Shown("1 more still open (in your list on screen)"), "just counted")
			wow.click("Done")
			t.ok(not NraKitRemindersCard:IsShown() and Mine("buy a mount").state == "done", "Done ticks it and closes")
			t.equal(Mine("old one").state, "due", "the old one stays")

			Remind("new one")
			Login()
			t.ok(Shown("new one") and Shown("STILL OPEN") and Shown("old one"), "at login both, in two parts")
			t.ok(not Shown("Done"), "tick boxes, not Done, with more than one")
			for _, reminder in ipairs(reminders.Due()) do
				reminders.SetDone(reminder.id, true)
			end
			t.ok(wow.click("Close"), "all done")
			wow.data.zone = "Elwynn Forest"
			wow.fire("ZONE_CHANGED_NEW_AREA")
		end)

		t.test("a level reminder: when you reach it", function()
			Remind("at 31: train")
			wow.data.level = 31
			wow.fire("PLAYER_LEVEL_UP", 31)
			t.equal(Mine("train").state, "due", "due")
			reminders.SetDone(Mine("train").id, true)
			NraKitRemindersCard:Hide()
		end)

		t.test("right-click: remind me again later", function()
			Remind("feed the pet")
			Login()
			local row = Rows(NraKitRemindersCard)[1]
			reminders.Snooze(row.reminderID, 3600)
			local reminder = Mine("feed the pet")
			t.ok(reminder.state == "waiting" and reminder.kind == "time" and reminder.at == now + 3600, "in an hour")
			now = now + 3600
			reminders.Check()
			t.equal(reminder.state, "due", "back")
			reminders.SetDone(reminder.id, true)
			NraKitRemindersCard:Hide()
		end)

		t.test("without the tracker, closing just hides them until the next login", function()
			ns:SetSetting("remindersTracker", false)
			Remind("buy arrows")
			Login()
			wow.click("Later")
			t.ok(not NraKitRemindersTracker:IsShown(), "no tracker")
			Login()
			t.ok(NraKitRemindersCard:IsShown(), "back at login")
			reminders.SetDone(Mine("buy arrows").id, true)
			NraKitRemindersCard:Hide()
			ns:SetSetting("remindersTracker", true)
		end)

		t.test("the tracker folds, hides until the next login, and comes back with /nra remind show", function()
			local menu
			MenuUtil.CreateContextMenu = function(_, build)
				menu = wow.newMenu()
				build(nil, menu)
			end
			Remind("water the plants")
			Login()
			wow.click("Later")
			local tracker = NraKitRemindersTracker
			local header = rawget(tracker, "header")
			-- Dragged: held by its top-left corner, so folding keeps the header in place.
			local point
			rawset(tracker, "GetLeft", function()
				return 1200
			end)
			rawset(tracker, "GetTop", function()
				return 700
			end)
			rawset(tracker, "SetPoint", function(_, ...)
				point = { ... }
			end)
			tracker.scripts.OnDragStop(tracker)
			t.ok(point and point[1] == "TOPLEFT" and point[3] == "BOTTOMLEFT" and point[4] == 1200 and point[5] == 700,
				"pinned by its top-left")
			t.equal(NraKitDB.remindersTrackerPosition[1], "TOPLEFT", "saved that way")
			-- Growing up: held by its bottom-left, the header at the bottom.
			rawset(tracker, "GetBottom", function()
				return 300
			end)
			local headerPoints = {}
			rawset(header, "SetPoint", function(_, where)
				table.insert(headerPoints, where)
			end)
			ns:SetSetting("remindersListGrow", "up")
			t.ok(point[1] == "BOTTOMLEFT" and point[5] == 300, "pinned by its bottom-left")
			t.equal(headerPoints[1], "BOTTOMLEFT", "header at the bottom")
			ns:SetSetting("remindersListGrow", "down")
			t.equal(point[1], "TOPLEFT", "and back")
			-- A new size keeps the corner in the same place on screen: 1200, 700 at 200% is 600, 350
			-- in the list's own (doubled) units.
			ns:SetSetting("remindersListScale", 2)
			t.ok(point[4] == 600 and point[5] == 350, "same place at double size: " .. point[4] .. ", " .. point[5])
			ns:SetSetting("remindersListScale", 1)
			t.ok(point[4] == 1200 and point[5] == 700, "and back")
			header.scripts.OnClick(header, "LeftButton")
			t.ok(NraKitDB.remindersTrackerFolded and tracker:IsShown(), "folded, still there")
			t.equal(#Rows(tracker), 0, "just the header")
			header.scripts.OnClick(header, "LeftButton")
			t.equal(#Rows(tracker), 1, "unfolded")
			-- With the header hidden it shows just above the list; folding puts it inside: the
			-- list moves up by its height, so the header stays where it was (and back).
			ns:SetSetting("remindersListHideHeader", true)
			t.equal(point[5], 672, "header hidden: the items stay where they were (the list's top is the header's bottom)")
			header.scripts.OnClick(header, "LeftButton")
			t.equal(point[5], 700, "folded: the header in the same place")
			header.scripts.OnClick(header, "LeftButton")
			t.equal(point[5], 672, "unfolded again")
			ns:SetSetting("remindersListHideHeader", false)
			t.equal(point[5], 700, "header shown again: nothing moved")
			-- Right-click: the tab; shift-right-click: the settings; shift-click: hide until next login.
			header.scripts.OnClick(header, "RightButton")
			t.ok(NraKitRemindersFrame:IsShown(), "right-click: Reminders & To-do")
			NraKitRemindersFrame:Hide()
			IsShiftKeyDown = function()
				return true
			end
			header.scripts.OnClick(header, "RightButton")
			t.ok(NraKitOptionsFrame:IsShown(), "shift-right-click: settings")
			NraKitOptionsFrame:Hide()
			header.scripts.OnClick(header, "LeftButton")
			IsShiftKeyDown = function()
				return false
			end
			t.ok(not tracker:IsShown(), "shift-click: hidden")
			Remind("show")
			t.ok(tracker:IsShown() and not NraKitDB.remindersTrackerFolded, "back, unfolded")
			t.equal(Mine("show"), nil, "show isn't a reminder")
			local entries = wow.newMenu()
			ns:FillMenu(entries)
			t.ok(wow.menuEntry(entries.entries, "To-do list"), "in NraKit's menu")
			reminders.SetDone(Mine("water the plants").id, true)
			t.ok(not tracker:IsShown(), "gone when done")
			t.ok(Remind("show"):find("to-do list is empty", 1, true), "nothing to show")
			entries = wow.newMenu()
			ns:FillMenu(entries)
			t.ok(not wow.menuEntry(entries.entries, "To-do list"), "not in the menu then")
		end)

		t.test("/nra todo: straight on the list, no card, no sound", function()
			wow.played = {}
			SlashCmdList.NRAKIT("todo respec")
			local todo = Mine("respec")
			t.ok(todo and todo.quiet and todo.state == "due", "due now, a to-do")
			t.ok(not NraKitRemindersCard:IsShown(), "no card")
			t.equal(#wow.played, 0, "no sound")
			t.ok(NraKitRemindersTracker:IsShown() and #Rows(NraKitRemindersTracker) == 1, "on the list")
			t.equal(rawget(NraKitRemindersTracker.title, "text"), "|cffff9933Reminders|r & |cff66bfffTo-do|r (1)", "the list's name, in the two colours")
			NraKitRemindersFrame:Hide()
			SlashCmdList.NRAKIT("todo")
			t.ok(NraKitRemindersFrame:IsShown(), "/nra todo alone opens the tab, like /nra remind")
			NraKitRemindersFrame:Hide()
			NraKitRemindersTracker:Hide()
			SlashCmdList.NRAKIT("todo show")
			t.ok(NraKitRemindersTracker:IsShown(), "/nra todo show: the list on screen")
			SlashCmdList.NRAKIT("todo in Ironforge: buy reagents")
			wow.data.zone = "Ironforge"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			t.ok(Mine("buy reagents").state == "due" and not NraKitRemindersCard:IsShown(), "came due quietly")
			wow.data.zone = "Elwynn Forest"
			wow.fire("ZONE_CHANGED_NEW_AREA")
		end)

		t.test("the list in your order: arrows on the row, shift for the top, dragging", function()
			SlashCmdList.NRAKIT("todo third")
			local function Order()
				local texts = {}
				for _, reminder in ipairs(reminders.Due()) do
					table.insert(texts, reminder.text)
				end
				return table.concat(texts, ", ")
			end
			t.equal(Order(), "respec, buy reagents, third", "in the order they came")
			local function TrackerRow(text)
				for _, row in ipairs(Rows(NraKitRemindersTracker)) do
					if row.reminder.text == text then
						return row
					end
				end
			end
			local row = TrackerRow("third")
			row.up.scripts.OnClick(row.up)
			t.equal(Order(), "respec, third, buy reagents", "up one")
			IsShiftKeyDown = function()
				return true
			end
			row = TrackerRow("buy reagents")
			row.up.scripts.OnClick(row.up)
			IsShiftKeyDown = function()
				return false
			end
			t.equal(Order(), "buy reagents, respec, third", "shift: to the top")
			-- Drag "third" onto the top row's place.
			local dragging, target = TrackerRow("third"), TrackerRow("buy reagents")
			rawset(target, "IsMouseOver", function()
				return true
			end)
			dragging.scripts.OnDragStart(dragging)
			dragging.scripts.OnDragStop(dragging)
			rawset(target, "IsMouseOver", nil)
			t.equal(Order(), "third, buy reagents, respec", "dragged to the top")
			Login()
			t.equal(Order(), "third, buy reagents, respec", "kept")
			t.ok(not NraKitRemindersCard:IsShown(), "to-dos don't make a card at login")
		end)

		t.test("ticked in the list: stays a moment, fades, then goes", function()
			local tracker = NraKitRemindersTracker
			local row
			for _, each in ipairs(Rows(tracker)) do
				if each.reminder.text == "third" then
					row = each
				end
			end
			row.check.scripts.OnClick(row.check)
			t.equal(Mine("third").state, "done", "done")
			t.equal(#Rows(tracker), 3, "still there")
			wow.advance(2.5)
			tracker.scripts.OnUpdate(tracker)
			t.ok(row:GetAlpha() > 0.4 and row:GetAlpha() < 0.6, "fading")
			wow.advance(1)
			reminders.RefreshTracker()
			t.equal(#Rows(tracker), 2, "gone")
		end)

		t.test("the list: reminders and to-dos in their own parts, tagged with where; arrows stay in the part", function()
			wow.data.zone = "Ironforge"
			Remind("in Ironforge: see the banker")
			NraKitRemindersCard:Hide()
			local tracker = NraKitRemindersTracker
			local sections = rawget(tracker, "sections")
			t.ok(sections.loud:IsShown() and sections.quiet:IsShown(), "REMINDERS and TO DO")
			local row
			for _, each in ipairs(Rows(tracker)) do
				if each.reminder.text == "see the banker" then
					row = each
				end
			end
			local text = rawget(row.text, "text")
			t.ok(text:find("|cff4cd94cIronforge|r", 1, true), "tagged, green while you're there: " .. text)
			wow.data.zone = "Elwynn Forest"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			t.ok(rawget(row.text, "text"):find("|cffffd100Ironforge|r", 1, true), "gold elsewhere")
			row.scripts.OnEnter(row)
			t.ok(row.up:IsShown() and row.down:IsShown(), "both arrows")
			t.equal(row.up:GetAlpha(), 0.3, "it's alone in its part: up dimmed")
			t.equal(row.down:GetAlpha(), 0.3, "and down")
			reminders.SetDone(row.reminder.id, true)
		end)

		t.test("the list's settings: size, opacity, background, rows, tags, lock, hide in combat", function()
			SlashCmdList.NRAKIT("todo one")
			SlashCmdList.NRAKIT("todo two")
			SlashCmdList.NRAKIT("todo in Ironforge: three")
			wow.data.zone = "Ironforge"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			local tracker = NraKitRemindersTracker
			t.ok(ns:GetOption("remindersListBackgroundSplit") and ns:GetValue("remindersListItemsBackground") == 0,
				"by default: a header box, the items on their own")
			t.ok(rawget(tracker, "itemsBg"):GetAlpha() == 0 and rawget(tracker, "headerBg"):GetAlpha() == 1, "so it looks that way")
			ns:SetSetting("remindersListBackgroundSplit", false)
			ns:SetSetting("remindersListScale", 1.2)
			ns:SetSetting("remindersListAlpha", 0.6)
			ns:SetSetting("remindersListBackground", 0)
			t.equal(tracker:GetScale(), 1.2, "size")
			t.equal(tracker:GetAlpha(), 0.6, "opacity")
			t.ok(rawget(tracker, "headerBg"):GetAlpha() == 0 and rawget(tracker, "itemsBg"):GetAlpha() == 0, "no background")
			ns:SetSetting("remindersListBackgroundSplit", true)
			ns:SetSetting("remindersListHeaderBackground", 0.95)
			ns:SetSetting("remindersListItemsBackground", 0)
			t.ok(rawget(tracker, "headerBg"):GetAlpha() == 1 and rawget(tracker, "itemsBg"):GetAlpha() == 0, "header and items apart")
			t.equal(rawget(tracker, "itemsBorder"):GetAlpha(), 0, "no border around see-through items")
			-- Hovering brings see-through items up to the hover opacity (60% by default), quickly.
			local over = true
			rawset(tracker, "IsMouseOver", function()
				return over
			end)
			tracker.scripts.OnUpdate(tracker, 0.05)
			local partway = rawget(tracker, "itemsBg"):GetAlpha()
			t.ok(partway > 0 and partway < 0.6 / 0.95, "coming in")
			tracker.scripts.OnUpdate(tracker, 0.2)
			t.equal(rawget(tracker, "itemsBg"):GetAlpha(), 0.6 / 0.95, "items at the hover opacity")
			t.equal(rawget(tracker, "headerBg"):GetAlpha(), 1, "the header (more solid) as it was")
			over = false
			tracker.scripts.OnUpdate(tracker, 0.2)
			t.equal(rawget(tracker, "itemsBg"):GetAlpha(), 0, "see-through again")
			rawset(tracker, "IsMouseOver", nil)
			t.equal(rawget(tracker, "headerBorder"):GetAlpha(), 1, "the header keeps its border")
			-- Background opacity greys out in the NraKit window while they're set apart.
			ns:OpenSettings("Reminders & to-dos", "reminders")
			local function BackgroundSlider()
				for _, frame in ipairs(wow.frames) do
					local option = rawget(frame, "option")
					if type(option) == "table" and option.key == "remindersListBackground" and wow.visible(frame) then
						return frame
					end
				end
			end
			t.equal(BackgroundSlider().enabled, false, "Background opacity greyed out")
						ns:SetSetting("remindersListBackgroundSplit", false)
			t.equal(rawget(tracker, "headerBg"):GetAlpha(), 0, "together again: Background for both")
			ns:OpenSettings("Reminders & to-dos", "reminders")
			t.ok(BackgroundSlider().enabled ~= false, "and back")
			NraKitOptionsFrame:Hide()
			ns:SetSetting("remindersListRows", 2)
			t.equal(#Rows(tracker), 2, "two rows")
			t.equal(rawget(rawget(tracker, "more"), "text"), string.format("and %d more (/nra remind)", #reminders.Due() - 2), "the rest counted")
			ns:SetSetting("remindersListRows", 10)
			ns:SetSetting("remindersListTags", false)
			for _, row in ipairs(Rows(tracker)) do
				t.ok(not rawget(row.text, "text"):find("Ironforge", 1, true), "no tags")
			end
			ns:SetSetting("remindersListTags", true)
			ns:SetSetting("remindersListLock", true)
			local moved = false
			rawset(tracker, "StartMoving", function()
				moved = true
			end)
			tracker.scripts.OnDragStart(tracker)
			t.ok(not moved, "locked")
			ns:SetSetting("remindersListLock", false)
			t.ok(ns:GetOption("remindersListHideInCombat"), "hide in combat is on by default")
			wow.fire("PLAYER_REGEN_DISABLED")
			t.ok(tracker:IsShown(), "fading out")
			wow.advance(0.3)
			t.ok(not tracker:IsShown(), "hidden in combat")
			wow.fire("ZONE_CHANGED")
			t.ok(not tracker:IsShown(), "stays hidden while fighting")
			wow.fire("PLAYER_REGEN_ENABLED")
			t.ok(tracker:IsShown() and tracker:GetAlpha() == 0, "back after, fading in")
			wow.advance(0.3)
			t.equal(tracker:GetAlpha(), ns:GetValue("remindersListAlpha"), "faded in, to the overall opacity")
			ns:SetSetting("remindersListHideInCombat", false)
			-- Hiding the header: it shows while the mouse is over the list.
			ns:SetSetting("remindersListHideHeader", true)
			local header = rawget(tracker, "header")
			local over = false
			rawset(tracker, "IsMouseOver", function()
				return over
			end)
			tracker.scripts.OnUpdate(tracker)
			t.ok(not header:IsShown(), "header hidden")
			over = true
			tracker.scripts.OnUpdate(tracker)
			t.ok(header:IsShown(), "shown with the mouse on the list")
			over = false
			NraKitDB.remindersTrackerFolded = true
			reminders.RefreshTracker()
			tracker.scripts.OnUpdate(tracker)
			t.ok(header:IsShown(), "a folded list keeps its header")
			NraKitDB.remindersTrackerFolded = nil
			ns:SetSetting("remindersListHideHeader", false)
			rawset(tracker, "IsMouseOver", nil)
			t.ok(header:IsShown(), "header back")
			for _, setting in ipairs({ "remindersListScale", "remindersListAlpha" }) do
				ns:SetSetting(setting, 1)
			end
			ns:SetSetting("remindersListBackground", 0.95)
			for _, text in ipairs({ "one", "two", "three" }) do
				reminders.SetDone(Mine(text).id, true)
			end
			wow.data.zone = "Elwynn Forest"
			wow.fire("ZONE_CHANGED_NEW_AREA")
		end)

		t.test("zone to-dos: a countdown when you leave, then off the list; back (in place, with a message) when you return", function()
			local function Visible(text)
				for _, frame in ipairs(wow.frames) do
					local value = rawget(frame, "text")
					if type(value) == "table" then
						value = rawget(value, "text")
					end
					if value == text and wow.visible(frame) then
						return true
					end
				end
			end
			local tracker = NraKitRemindersTracker
			wow.data.zone = "Elwynn Forest"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			local show, shown = ns.toast.Show, nil
			ns.toast.Show = function(spec)
				shown = spec
			end
			SlashCmdList.NRAKIT("todo first")
			SlashCmdList.NRAKIT("todo in ironforge: pick up the mats")
			SlashCmdList.NRAKIT("todo last")
			wow.data.zone = "Ironforge"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			local todo = Mine("pick up the mats")
			t.equal(todo.state, "due", "there: on the list")
			t.ok(shown and shown.heading == "IRONFORGE" and shown.text == "|cff66bfff1 to-do|r" and shown.detail == "pick up the mats",
				"and a message for arriving")
			ns.toast.Show = show
			reminders.MoveTo(todo.id, 1)
			local function RowText()
				for _, row in ipairs(Rows(tracker)) do
					if row.reminder == todo then
						return rawget(row.text, "text")
					end
				end
			end
			wow.data.zone = "Dun Morogh"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			t.ok(RowText():find("|cffffd100Ironforge|r |cff99884410|r", 1, true), "counting down, the zone as the game writes it: " .. RowText())
			wow.advance(4)
			t.ok(RowText():find("|cff9988446|r", 1, true), "6 left: " .. RowText())
			wow.data.zone = "Ironforge"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			t.ok(todo.state == "due" and not RowText():find("|cff998844", 1, true), "back in time: stays, no count")
			wow.data.zone = "Dun Morogh"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			wow.advance(11)
			t.equal(todo.state, "waiting", "off the list")
			t.ok(rawget(tracker.title, "text"):find("elsewhere", 1, true), "the header says some are elsewhere: " .. rawget(tracker.title, "text"))
			wow.advance(2)
			reminders.RefreshTracker() -- (the timer for when it has faded)
			t.equal(RowText(), nil, "faded off")
			wow.data.zone = "Ironforge"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			t.equal(reminders.Due()[1], todo, "back, in its place at the top")
			-- Kept on the list (right-click).
			local menu
			MenuUtil.CreateContextMenu = function(_, build)
				menu = wow.newMenu()
				build(nil, menu)
			end
			reminders.OpenRowMenu(UIParent, todo)
			wow.menuEntry(menu.entries, "Keep it on the list outside Ironforge").onClick()
			wow.data.zone = "Dun Morogh"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			wow.advance(11)
			t.equal(todo.state, "due", "kept")
			for _, text in ipairs({ "first", "pick up the mats", "last" }) do
				reminders.SetDone(Mine(text).id, true)
			end
			wow.data.zone = "Elwynn Forest"
			wow.fire("ZONE_CHANGED_NEW_AREA")
		end)

		t.test("right-click turns a to-do into a reminder; the login card leaves to-dos out", function()
			local menu
			MenuUtil.CreateContextMenu = function(_, build)
				menu = wow.newMenu()
				build(nil, menu)
			end
			reminders.OpenRowMenu(UIParent, Mine("respec"))
			wow.menuEntry(menu.entries, "Make it a reminder").onClick()
			t.ok(not Mine("respec").quiet, "a reminder now")
			Login()
			t.ok(NraKitRemindersCard:IsShown() and Shown("respec") and not Shown("buy reagents"), "the card has the reminder, not the to-do")
			wow.click("Later")
			for _, reminder in ipairs(reminders.Due()) do
				reminders.SetDone(reminder.id, true)
			end
		end)

		t.test("the window: sections, writing one, editing, and ones for other characters", function()
			Remind("@Bob: mail the bags")
			Remind("2h stable the pet")
			ns:OpenReminders()
			t.ok(NraKitRemindersFrame:IsShown(), "open")
			local labels = {}
			for _, frame in ipairs(wow.frames) do
				local text = rawget(frame, "text")
				if type(text) == "string" and wow.visible(frame) then
					labels[text] = true
				end
			end
			t.ok(labels["For your other characters"] and labels["Waiting"] and labels["Done"], "sections")
			t.ok(labels["|cffff9933Reminders|r & |cff66bfffTo-do|r"], "the tab's name in the two colours")
			t.ok(labels["Bob Stone: next login"], "who and when")
			t.ok(labels["In 2 h (" .. date("%H:%M", now + 7200) .. ")"], "when a timed one comes")
			local row = wow.findAll(function(frame)
				return rawget(frame, "reminder") == Mine("stable the pet") and wow.visible(frame)
			end)[1]
			t.equal(rawget(row.kind, "text"), "Reminder", "what it is, under Waiting")
			row.scripts.OnClick(row, "LeftButton")
			local editBox
			for _, frame in ipairs(wow.frames) do
				if frame.kind == "EditBox" and wow.visible(frame) and rawget(frame, "parent") ~= NraKitRemindersFrame.body then
					editBox = frame
				end
			end
			wow.type(editBox, "stable the cat")
			editBox.scripts.OnEnterPressed(editBox)
			t.ok(Mine("stable the cat"), "edited")
			t.noErrors()
		end)

		t.test("the window: the Reminder / To-do switch, Show list and Settings", function()
			t.ok(NraKitRemindersFrame:IsShown(), "open")
			t.ok(wow.click("To-do"), "the switch")
			t.ok(NraKitDB.remindersAddQuiet, "remembered")
			local box
			for _, frame in ipairs(wow.frames) do
				if frame.kind == "EditBox" and rawget(frame, "parent") == NraKitRemindersFrame.body then
					box = frame
				end
			end
			wow.type(box, "polish the boots")
			box.scripts.OnEnterPressed(box)
			t.ok(Mine("polish the boots").quiet and Mine("polish the boots").state == "due", "a to-do, on the list")
			wow.click("Add")
			t.ok(wow.click("Add to-do"), "the form is for a to-do")
			local formSwitch = rawget(NraKitReminderForm, "kindChips")[1]
			formSwitch.scripts.OnClick(formSwitch)
			t.ok(wow.click("Add reminder"), "switched in the form")
			t.ok(NraKitDB.remindersAddQuiet, "the switch at the top stays")
			NraKitReminderForm:Hide()
			wow.click("Reminder")
			t.equal(NraKitDB.remindersAddQuiet, nil, "back to reminders")
			NraKitRemindersTracker:Hide()
			t.ok(wow.click("Show list"), "Show list")
			t.ok(NraKitRemindersTracker:IsShown(), "the list")
			t.ok(wow.click("Settings"), "Settings")
			t.ok(NraKitOptionsFrame:IsShown(), "the settings")
			NraKitOptionsFrame:Hide()
			ns:OpenReminders()
			reminders.SetDone(Mine("polish the boots").id, true)
		end)

		t.test("the ? button shows how to write them once there are some", function()
			local function HelpShown()
				for _, frame in ipairs(wow.frames) do
					local text = rawget(frame, "text")
					if type(text) == "string" and text:find("/nra remind 30m", 1, true) and wow.visible(frame) then
						return true
					end
				end
				return false
			end
			t.ok(not HelpShown(), "not while there are reminders")
			t.ok(wow.click("?"), "the button")
			t.ok(HelpShown(), "shown")
			NraKitRemindersFrame:Hide()
			ns:OpenReminders()
			t.ok(not HelpShown(), "closed again next time")
			NraKitRemindersFrame:Hide()
		end)

		t.test("Add with the box empty: a form to pick when, without the command words", function()
			C_Map.GetBestMapForUnit = function()
				return 10
			end
			C_Map.GetMapInfo = function(mapID)
				return ({ [10] = { parentMapID = 2 }, [2] = { parentMapID = 0 } })[mapID]
			end
			C_Map.GetMapChildrenInfo = function(mapID)
				return mapID == 2 and { { name = "Darkshore" }, { name = "Darnassus" }, { name = "Ashenvale" } } or {}
			end
			ns:OpenReminders()
			t.ok(wow.click("Add"), "Add")
			local form = NraKitReminderForm
			t.ok(form:IsShown(), "the form")
			local textBox = rawget(form, "textBox")

			t.ok(wow.click("< Back to the list") and not form:IsShown(), "back to the list without adding")
			wow.click("Add")
			textBox.scripts.OnEscapePressed(textBox)
			t.ok(not form:IsShown(), "Escape in the form cancels it too")
			wow.click("Add")
			t.ok(wow.click("Cancel") and not form:IsShown(), "and Cancel")
			wow.click("Add")
			t.ok(wow.click("Add reminder"), "submit empty")
			t.ok(form:IsShown() and rawget(rawget(form, "problem"), "text"):find("say", 1, true), "asks what it should say")

			wow.type(textBox, "sell the greens")
			wow.click("After a time")
			wow.click("1 hour")
			wow.click("Add reminder")
			t.ok(not form:IsShown(), "closed")
			local reminder = Mine("sell the greens")
			t.ok(reminder and reminder.kind == "time" and reminder.at == now + 3600, "in an hour")

			wow.click("Add")
			wow.type(textBox, "fish quest")
			wow.click("In a zone")
			local zoneBox = rawget(form, "zoneBox")
			wow.type(zoneBox, "dar")
			t.ok(wow.click("Ashenvale") == false and wow.click("Darnassus"), "matching zones to pick")
			wow.click("Add reminder")
			t.equal(Mine("fish quest").zone, "Darnassus", "picked zone")

			wow.click("Add")
			wow.type(textBox, "visit the trainer")
			wow.click("At a level")
			wow.type(rawget(form, "levelBox"), "20")
			wow.click("Add reminder")
			t.ok(rawget(rawget(form, "problem"), "text"):find("already", 1, true), "a level you have")
			wow.type(rawget(form, "levelBox"), "35")
			wow.click("Add reminder")
			t.equal(Mine("visit the trainer").level, 35, "level")

			wow.click("Add")
			wow.type(textBox, "mail the mats")
			wow.click("At a level")
			local menu
			MenuUtil.CreateContextMenu = function(_, build)
				menu = wow.newMenu()
				build(nil, menu)
			end
			local select = rawget(form, "characterSelect")
			select.scripts.OnClick(select)
			t.ok(wow.menuEntry(menu.entries, "Me (Nra)"), "you first")
			wow.menuEntry(menu.entries, "Bob Stone").onClick("Bob Stone")
			wow.type(rawget(form, "levelBox"), "20")
			wow.click("Add reminder")
			local theirs
			for _, each in ipairs(reminders.List("Bob Stone")) do
				if each.text == "mail the mats" then
					theirs = each
				end
			end
			t.ok(theirs and theirs.kind == "level" and theirs.level == 20 and theirs.from == "Nra", "for Bob, at 20 (his level isn't yours)")
			t.noErrors()
			NraKitRemindersFrame:Hide()
		end)

		t.test("logging in as the other character: theirs, from you", function()
			wow.data.units.player = { name = "Bob", surname = "Stone" }
			Login()
			local reminder = Mine("mail the bags")
			t.ok(reminder and reminder.state == "due" and reminder.from == "Nra", "due, from Nra")
			t.ok(reminders.DueNote(reminder):find("From Nra", 1, true), "says who from")
			wow.click("Later")
		end)

		t.test("a character that hadn't logged in yet gets theirs when they do", function()
			wow.data.units.player = { name = "Newbie", surname = "Smith" }
			Login()
			t.ok(Mine("hi") and Mine("hi").state == "due", "picked up by first name")
			t.equal(NraKitDB.remindersData.characters.Newbie, nil, "moved")
			t.ok(NraKitDB.remindersData.characters["Newbie Smith"].seen, "seen now")
			wow.data.units.player = nil
			t.noErrors()
		end)
	end,
}
