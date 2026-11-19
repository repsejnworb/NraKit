-- Player notes: names, labels, the chat command, tooltip, right-click menu, warnings,
-- the window, and Unit Scanner alerts for Hostile players.

return {
	enable = { "playerNotes" },
	run = function(t, ns, wow)
		local notes = ns.playerNotes
		local players = function()
			return NraKitDB.playerNotesData.players
		end
		local function Slash(text)
			SlashCmdList.NRAKIT(text)
		end
		local function Printed(text)
			for _, line in ipairs(wow.printed) do
				if line:find(text, 1, true) then
					return true
				end
			end
			return false
		end
		wow.data.units.player = { name = "Nra", surname = "Brown" }

		t.test("names: realm-style and spacing match the same player", function()
			t.equal(notes.Display(" bob   stone "), "bob stone", "spacing")
			t.equal(notes.Key("Bob-Stone"), "bob stone", "dash")
			notes.AddNote("Bob Stone", "stole my node")
			t.ok(notes.Find("bob-stone"), "found by dash name")
			t.equal(players()["bob stone"].label, "neutral", "a note alone gets the neutral label")
		end)

		t.test("labels by what you'd type", function()
			t.equal(notes.LabelByWord("kos").id, "kos", "initials")
			t.equal(notes.LabelByWord("KillOnSight").id, "kos", "name without spaces")
			t.equal(notes.LabelByWord("avoid").id, "avoid", "one word")
			t.ok(notes.LabelByWord("stole") == nil, "not a label")
		end)

		t.test("/nra note <First Last> <label> <note>", function()
			Slash("note Ann Lee kos ganked me at the flight master")
			local record = players()["ann lee"]
			t.ok(record, "saved")
			t.equal(record.name, "Ann Lee", "name")
			t.equal(record.label, "kos", "label")
			local note = record.notes[1]
			t.equal(note.text, "ganked me at the flight master", "note")
			t.equal(note.zone, "Elwynn Forest", "zone")
			t.equal(note.by, "Nra Brown", "your character")
		end)

		t.test("/nra note <first name> <label> picks a noted player", function()
			Slash("note bob avoid")
			t.equal(players()["bob stone"].label, "avoid", "Bob Stone relabelled")
			t.ok(players()["bob"] == nil, "no new player called Bob")
		end)

		t.test("/nra note <label> <note> uses your target", function()
			wow.data.units.target = { name = "Cid", surname = "Vale", guid = "Player-1-0001", class = "Rogue" }
			Slash("note good healed me through the whole dungeon")
			local record = players()["cid vale"]
			t.ok(record, "target saved")
			t.equal(record.label, "good", "label")
			t.equal(record.guid, "Player-1-0001", "GUID kept")
			t.equal(record.class, "ROGUE", "class kept")
			wow.data.units.target = nil
		end)

		t.test("with a player targeted, plain text is a note for them", function()
			wow.data.units.target = { name = "Hal", surname = "Pike", guid = "Player-1-0009" }
			Slash("note testing")
			t.ok(players()["testing"] == nil, "no player called testing")
			local record = players()["hal pike"]
			t.ok(record and record.notes[1].text == "testing", "note on the target")
			Slash("note Hal Pike avoid camped the mailbox")
			t.equal(record.label, "avoid", "naming your target works too")
			t.equal(record.notes[2].text, "camped the mailbox", "and its note")
			Slash("note Ann Lee was here again")
			t.equal(players()["ann lee"].notes[2].text, "was here again", "a noted player named in full wins over the target")
			wow.data.units.target = nil
		end)

		t.test("without a target, a lone word or label asks who it's for", function()
			wow.printed = {}
			Slash("note testing")
			t.ok(players()["testing"] == nil, "nobody added")
			t.ok(wow.printed[#wow.printed]:find("Who is that for", 1, true), "explains")
			Slash("note kos stole my node")
			t.ok(players()["kos stole"] == nil, "a label first doesn't become a name")
			Slash("note Bob Smith was rude")
			t.ok(players()["bob smith"], "a new Bob, not Bob Stone")
			t.equal(#players()["bob stone"].notes, 1, "Bob Stone untouched")
		end)

		t.test("!remove takes your target out of your notes, !undo brings them back", function()
			wow.data.units.target = { name = "Hal", surname = "Pike", guid = "Player-1-0009" }
			Slash("note remove")
			t.equal(players()["hal pike"].notes[3].text, "remove", "plain words are still a note")
			wow.printed = {}
			Slash("note !remove")
			t.ok(players()["hal pike"] == nil, "removed")
			t.ok(wow.printed[1]:find("3 notes", 1, true) and wow.printed[1]:find("!undo", 1, true), "says how to undo")
			Slash("note !undo")
			t.equal(#players()["hal pike"].notes, 3, "back with its notes")
			Slash("note !rm Hal Pike")
			t.ok(players()["hal pike"] == nil, "removed by name")
			Slash("note fresh start")
			Slash("note !undo")
			t.equal(#players()["hal pike"].notes, 4, "undo after re-adding merges the notes")
			t.equal(players()["hal pike"].notes[4].text, "fresh start", "newest last")
			wow.printed = {}
			Slash("note !undo")
			t.ok(wow.printed[1]:find("Nothing to undo", 1, true), "only once")
			Slash("note !bogus")
			t.ok(wow.printed[2]:find("Unknown", 1, true), "unknown command")
			t.ok(players()["bogus"] == nil, "never a player or a note")
			wow.data.units.target = nil
		end)

		t.test("a renamed player is still found by GUID", function()
			wow.data.units.target = { name = "Cid", surname = "Newname", guid = "Player-1-0001" }
			local record = notes.FindUnit("target")
			t.ok(record and record.name == "Cid Vale", "found by GUID")
			notes.Ensure("Cid Newname", { guid = "Player-1-0001" })
			t.ok(players()["cid newname"] and not players()["cid vale"], "moved to the new name")
			wow.data.units.target = nil
		end)

		t.test("tooltip shows the label and the latest note", function()
			wow.data.units.mouseover = { name = "Ann", surname = "Lee" }
			local lines = wow.unitTooltip("mouseover")
			t.ok(lines[1] and lines[1]:find("Kill on sight", 1, true), "label line")
			t.ok(lines[2] and lines[2]:find("was here again", 1, true), "latest note line")
			NraKitDB.playerNotesTooltip = false
			t.equal(#wow.unitTooltip("mouseover"), 0, "option off")
			NraKitDB.playerNotesTooltip = true
			wow.data.units.mouseover = { name = "Stranger", surname = "Danger" }
			t.equal(#wow.unitTooltip("mouseover"), 0, "nothing for players without notes")
		end)

		t.test("right-click menu on a player: note and label", function()
			wow.data.units.target = { name = "Dee", surname = "Rook", guid = "Player-1-0002" }
			local entries = wow.openMenu("MENU_UNIT_PLAYER", { unit = "target" })
			t.ok(wow.menuEntry(entries, "Add player note..."), "add note entry")
			local labelMenu = wow.menuEntry(entries, "Player label")
			t.ok(labelMenu, "label submenu")
			local avoid = wow.menuEntry(labelMenu.entries, "Avoid")
			t.ok(not avoid.isSelected(), "nothing selected yet")
			avoid.onClick()
			t.equal(players()["dee rook"].label, "avoid", "label set from the menu")
			t.ok(avoid.isSelected(), "now selected")
			entries = wow.openMenu("MENU_UNIT_PLAYER", { unit = "target" })
			t.ok(wow.menuEntry(entries, "Player note..."), "existing player: Player note...")
		end)

		t.test("no menu entries for yourself or NPCs", function()
			t.equal(#wow.openMenu("MENU_UNIT_SELF", { unit = "player" }), 0, "self menu not hooked")
			t.equal(#wow.openMenu("MENU_UNIT_PLAYER", { unit = "player" }), 0, "yourself")
			wow.data.units.target = { name = "Hogger", isPlayer = false }
			t.equal(#wow.openMenu("MENU_UNIT_TARGET", { unit = "target" }), 0, "an NPC")
			wow.data.units.target = nil
		end)

		t.test("chat name menu opens the window; the first note saves the player", function()
			local entries = wow.openMenu("MENU_UNIT_FRIEND", { name = "Eli", surname = "Moss" })
			wow.menuEntry(entries, "Add player note...").onClick()
			t.ok(NraKitPlayerNotesFrame:IsShown(), "window open")
			t.ok(players()["eli moss"] == nil, "not saved just by opening")
			local box
			for _, frame in ipairs(wow.findAll(function(frame)
				return frame.template == "InputBoxTemplate" and frame.scripts.OnEnterPressed
					and not frame.scripts.OnEditFocusLost and wow.visible(frame)
			end)) do
				box = frame
			end
			wow.type(box, "sold me a fake map")
			box.scripts.OnEnterPressed(box)
			t.ok(players()["eli moss"], "saved")
			t.equal(players()["eli moss"].notes[1].text, "sold me a fake map", "note")
			t.equal(box:GetText(), "", "box cleared")
		end)

		t.test("Avoid and Kill on sight warn when they join your group, once", function()
			wow.printed, wow.raidNotices = {}, {}
			wow.data.units.party1 = { name = "Ann", surname = "Lee" } -- Kill on sight
			wow.data.units.party2 = { name = "Cid", surname = "Newname" } -- Good
			wow.data.party = { "party1", "party2" }
			wow.fire("GROUP_ROSTER_UPDATE")
			t.ok(Printed("Ann Lee"), "warned about Ann")
			t.ok(not Printed("Cid"), "not about a Good player")
			t.equal(#wow.raidNotices, 1, "on screen")
			wow.printed = {}
			wow.fire("GROUP_ROSTER_UPDATE")
			t.ok(not Printed("Ann Lee"), "not again while they stay")
			wow.data.party = {}
			wow.fire("GROUP_ROSTER_UPDATE")
		end)

		t.test("whispers warn (realm-style sender names too), with a cooldown", function()
			wow.printed = {}
			wow.fire("CHAT_MSG_WHISPER", "hey", "Bob-Stone")
			t.ok(Printed("Bob Stone") and Printed("whispered you"), "warned")
			wow.printed = {}
			wow.fire("CHAT_MSG_WHISPER", "hey again", "Bob-Stone")
			t.ok(not Printed("Bob Stone"), "cooldown")
			NraKitDB.playerNotesWarnWhisper = false
			wow.fire("CHAT_MSG_WHISPER", "hi", "Ann Lee")
			t.ok(not Printed("Ann Lee"), "option off")
			NraKitDB.playerNotesWarnWhisper = true
		end)

		t.test("labels: add, rename, retone, delete moves players", function()
			local label = notes.AddLabel("Ninja", "caution")
			notes.SetLabel("Fay Dorn", label.id)
			notes.RenameLabel(label.id, "Loot ninja")
			t.equal(notes.LabelByWord("lootninja").id, label.id, "renamed")
			notes.SetLabelTone(label.id, "hostile")
			notes.DeleteLabel(label.id)
			t.equal(players()["fay dorn"].label, "kos", "moved to the first Hostile label")
			for _, other in ipairs(notes.SortedLabels()) do
				if other.id ~= "neutral" then
					notes.DeleteLabel(other.id)
				end
			end
			t.ok(not notes.CanDeleteLabel("neutral"), "the last label stays")
			t.equal(players()["fay dorn"].label, "neutral", "everyone ends on the last label")
		end)

		t.test("+ Add player: needs a surname, then opens the new player", function()
			NraKitPlayerNotesFrame:Show()
			t.ok(wow.click("+  Add player"), "add page")
			local box
			for _, frame in ipairs(wow.findAll(function(frame)
				return frame.template == "InputBoxTemplate" and frame.scripts.OnTextChanged and wow.visible(frame)
			end)) do
				box = frame
			end
			wow.type(box, "gus")
			t.equal(wow.click("Add"), false, "one word can't be added")
			box.scripts.OnEnterPressed(box)
			t.ok(NraKitDB.playerNotesData.players["gus"] == nil, "Enter doesn't add it either")
			wow.type(box, "gus  hale")
			t.ok(wow.click("Add"), "two words can")
			local record = players()["gus hale"]
			t.ok(record, "saved")
			t.equal(record.name, "Gus Hale", "capitalised")
			t.equal(record.label, "neutral", "default label")
		end)

		t.test("the labels page adds a label", function()
			NraKitPlayerNotesFrame:Show()
			t.ok(wow.click("Labels"), "labels page")
			local before = #notes.GetLabels()
			t.ok(wow.click("+ New label"), "new label button")
			t.equal(#notes.GetLabels(), before + 1, "label added")
		end)

		t.test("chat command lists players and has help", function()
			wow.printed = {}
			Slash("note list")
			t.ok(Printed("Ann Lee"), "listed")
			wow.printed = {}
			Slash("note help")
			t.ok(Printed("/nra note"), "help printed")
		end)
	end,
}
