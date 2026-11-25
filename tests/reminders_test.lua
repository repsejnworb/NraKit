-- Reminders: notes for your next login, after a time, in a zone, at a level or for another
-- character. Due ones show on a card you close yourself; the rest go to the tracker.

-- This module's timers run at once; other modules' don't run, as usual here.
C_Timer.After = function(_, callback)
	if debug.getinfo(callback, "S").source:find("Reminders", 1, true) then
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
		SOUNDKIT.UI_BNET_TOAST = 12345
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
			t.ok(not (NraKitRemindersTracker and NraKitRemindersTracker:IsShown()), "no tracker while the card is up")
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
			wow.click("Close")
		end)

		t.test("one that came due while you were logged out says so", function()
			Remind("1h raid tonight")
			now = now + 7200
			Login()
			local reminder = Mine("raid tonight")
			t.ok(reminder.state == "due" and reminder.away, "away")
			t.ok(reminders.DueNote(reminder):find("while you were away", 1, true), "said")
			reminders.SetDone(reminder.id, true)
			wow.click("Close")
		end)

		t.test("a zone reminder: when you enter it, not where you are when you write it", function()
			wow.data.zone = "Elwynn Forest"
			Remind("in darkshore: turtle quest")
			Remind("in Elwynn Forest: sell the junk")
			t.ok(wow.printed[1]:find("You're there now", 1, true), "said it waits")
			wow.fire("ZONE_CHANGED_NEW_AREA")
			t.equal(Mine("sell the junk").state, "waiting", "not where you are")
			wow.data.zone = "Darkshore"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			t.equal(Mine("turtle quest").state, "due", "entered Darkshore (any case)")
			t.equal(Mine("sell the junk").state, "waiting", "left Elwynn")
			wow.data.zone = "Elwynn Forest"
			wow.fire("ZONE_CHANGED_NEW_AREA")
			t.equal(Mine("sell the junk").state, "due", "back in Elwynn")
			t.equal(#Rows(NraKitRemindersCard), 2, "both on the card")
			GetSubZoneText = function()
				return "Ratchet"
			end
			Remind("in Ratchet: boat")
			wow.data.zone = "The Barrens"
			GetSubZoneText = function()
				return ""
			end
			wow.fire("ZONE_CHANGED")
			GetSubZoneText = function()
				return "Ratchet"
			end
			wow.fire("ZONE_CHANGED")
			t.equal(Mine("boat").state, "due", "subzones count")
			for _, reminder in ipairs(reminders.Due()) do
				reminders.SetDone(reminder.id, true)
			end
			wow.click("Close")
		end)

		t.test("a level reminder: when you reach it", function()
			Remind("at 31: train")
			wow.data.level = 31
			wow.fire("PLAYER_LEVEL_UP", 31)
			t.equal(Mine("train").state, "due", "due")
			reminders.SetDone(Mine("train").id, true)
			wow.click("Close")
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
			wow.click("Close")
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
			wow.click("Close")
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
			header.scripts.OnClick(header, "LeftButton")
			t.ok(NraKitDB.remindersTrackerFolded and tracker:IsShown(), "folded, still there")
			t.equal(#Rows(tracker), 0, "just the header")
			header.scripts.OnClick(header, "LeftButton")
			t.equal(#Rows(tracker), 1, "unfolded")
			header.scripts.OnClick(header, "RightButton")
			wow.menuEntry(menu.entries, "Fold").onClick()
			header.scripts.OnClick(header, "RightButton")
			wow.menuEntry(menu.entries, "Hide until next login").onClick()
			t.ok(not tracker:IsShown(), "hidden")
			Remind("show")
			t.ok(tracker:IsShown() and not NraKitDB.remindersTrackerFolded, "back, unfolded")
			t.equal(Mine("show"), nil, "show isn't a reminder")
			local entries = wow.newMenu()
			ns:FillMenu(entries)
			t.ok(wow.menuEntry(entries.entries, "Show due reminders"), "in NraKit's menu")
			reminders.SetDone(Mine("water the plants").id, true)
			t.ok(not tracker:IsShown(), "gone when done")
			t.ok(Remind("show"):find("No reminders are due", 1, true), "nothing to show")
			entries = wow.newMenu()
			ns:FillMenu(entries)
			t.ok(not wow.menuEntry(entries.entries, "Show due reminders"), "not in the menu then")
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
			t.ok(labels["Bob Stone: next login"], "who and when")
			t.ok(labels["In 2 h (" .. date("%H:%M", now + 7200) .. ")"], "when a timed one comes")
			local row = wow.findAll(function(frame)
				return rawget(frame, "reminder") == Mine("stable the pet") and wow.visible(frame)
			end)[1]
			row.scripts.OnClick(row, "LeftButton")
			local editBox
			for _, frame in ipairs(wow.frames) do
				if frame.kind == "EditBox" and frame.shown and rawget(frame, "parent") ~= NraKitRemindersFrame.body then
					editBox = frame
				end
			end
			wow.type(editBox, "stable the cat")
			editBox.scripts.OnEnterPressed(editBox)
			t.ok(Mine("stable the cat"), "edited")
			t.noErrors()
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
