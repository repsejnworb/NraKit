-- Player notes: names, labels, tags, the chat command, tooltip, right-click menu, warnings,
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
			t.equal(players()["bob stone"].tone, "neutral", "a note alone makes them Neutral")
		end)

		t.test("labels by what you'd type", function()
			t.equal(notes.ToneByWord("kos").key, "hostile", "initials")
			t.equal(notes.ToneByWord("KillOnSight").key, "hostile", "name without spaces")
			t.equal(notes.ToneByWord("avoid").key, "caution", "one word")
			t.equal(notes.ToneByWord("liked").key, "friendly", "liked")
			t.equal(notes.ToneByWord("good").key, "friendly", "good (and friend) still mean Liked")
			t.equal(notes.GetTone("friendly").name, "Liked", "named Liked")
			t.ok(notes.ToneByWord("stole") == nil, "not a label")
		end)

		t.test("/nra note <First Last> <label> <note>", function()
			Slash("note Ann Lee kos ganked me at the flight master")
			local record = players()["ann lee"]
			t.ok(record, "saved")
			t.equal(record.name, "Ann Lee", "name")
			t.equal(record.tone, "hostile", "label")
			local note = record.notes[1]
			t.equal(note.text, "ganked me at the flight master", "note")
			t.equal(note.zone, "Elwynn Forest", "zone")
			t.equal(note.by, "Nra Brown", "your character")
		end)

		t.test("/nra note <first name> <label> picks a noted player", function()
			Slash("note bob avoid")
			t.equal(players()["bob stone"].tone, "caution", "Bob Stone relabelled")
			t.ok(players()["bob"] == nil, "no new player called Bob")
		end)

		t.test("/nra note <label> <note> uses your target", function()
			wow.data.units.target = { name = "Cid", surname = "Vale", guid = "Player-1-0001", class = "Rogue" }
			Slash("note good healed me through the whole dungeon")
			local record = players()["cid vale"]
			t.ok(record, "target saved")
			t.equal(record.tone, "friendly", "label")
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
			t.equal(record.tone, "caution", "naming your target works too")
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
			t.ok(not lines[1]:find("#", 1, true), "no tags, no tag text")
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
			local noteMenu = wow.menuEntry(entries, "Player note")
			t.ok(noteMenu, "Player note submenu")
			t.ok(wow.menuEntry(noteMenu.entries, "Add a note..."), "add note entry")
			t.ok(wow.menuEntry(noteMenu.entries, "Kill on sight"), "Kill on sight in it")
			local avoid = wow.menuEntry(noteMenu.entries, "Avoid")
			t.ok(not avoid.isSelected(), "nothing selected yet")
			avoid.onClick()
			t.equal(players()["dee rook"].tone, "caution", "label set from the menu")
			t.ok(avoid.isSelected(), "now selected")
			entries = wow.openMenu("MENU_UNIT_PLAYER", { unit = "target" })
			t.ok(wow.menuEntry(wow.menuEntry(entries, "Player note").entries, "Open notes..."), "existing player: Open notes...")
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
			wow.menuEntry(wow.menuEntry(entries, "Player note").entries, "Add a note...").onClick()
			t.ok(NraKitPlayerNotesFrame:IsShown(), "window open")
			t.ok(players()["eli moss"] == nil, "not saved just by opening")
			t.ok(#wow.findAll(function(frame)
				return wow.visible(frame) and rawget(frame, "label") == "No tags"
			end) == 1, "No tags shows before there are any tags")
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
			wow.data.units.party2 = { name = "Cid", surname = "Newname" } -- Friend
			wow.data.party = { "party1", "party2" }
			wow.fire("GROUP_ROSTER_UPDATE")
			t.ok(Printed("Ann Lee"), "warned about Ann")
			t.ok(not Printed("Cid"), "not about a Friend")
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

		t.test("tags: added from chat, one spelling, renamed (merging) and deleted", function()
			Slash("note Fay Dorn avoid #ninjalooter #Tank took the boe")
			local record = players()["fay dorn"]
			t.equal(record.tone, "caution", "label")
			t.equal(table.concat(record.tags, ","), "ninjalooter,Tank", "tags, sorted")
			t.equal(record.notes[1].text, "took the boe", "note after the tags")
			Slash("note fay #Ninja_Looter")
			notes.AddTag("Gil Rowe", "#NinjaLooter")
			t.equal(players()["gil rowe"].tags[1], "ninjalooter", "a tag keeps the spelling it has")
			notes.AddTag("Gil Rowe", "  #tank,  healer ")
			t.equal(players()["gil rowe"].tags[2], "tank healer", "no #, commas or extra spaces")
			local names = {}
			for _, tag in ipairs(notes.AllTags()) do
				table.insert(names, tag.name .. "=" .. tag.count)
			end
			t.equal(table.concat(names, " "), "Ninja_Looter=1 ninjalooter=2 Tank=1 tank healer=1", "every tag with its count")
			notes.RenameTag("Ninja_Looter", "NINJALOOTER")
			t.equal(table.concat(record.tags, ","), "ninjalooter,Tank", "renaming into another tag merges them")
			notes.RenameTag("ninjalooter", "Ninja looter")
			t.equal(players()["gil rowe"].tags[1], "Ninja looter", "renamed on everyone")
			notes.DeleteTag("tank healer")
			t.equal(#players()["gil rowe"].tags, 1, "deleted")
			notes.RemoveTag("fay dorn", "tank")
			t.equal(table.concat(record.tags, ","), "Ninja looter", "removed from one player")
		end)

		t.test("the list has a section per tag, closed with a click", function()
			NraKitPlayerNotesFrame:Show()
			local function Listed(name)
				return #wow.findAll(function(frame)
					return wow.visible(frame) and rawget(frame, "key") and rawget(frame.text, "text") == name
				end)
			end
			t.ok(wow.click("#Ninja looter"), "a section for the tag")
			t.equal(Listed("Fay Dorn"), 0, "closed")
			t.equal(NraKitDB.playerNotesData.collapsed["ninja looter"], true, "remembered")
			t.ok(wow.click("#Ninja looter"), "and opened again")
			t.equal(Listed("Gil Rowe"), 1, "its players")
			t.equal(Listed("Ann Lee"), 1, "untagged players in No tags")
			notes.AddTag("Ann Lee", "Tank")
			t.equal(Listed("Ann Lee"), 1, "a tagged player leaves No tags")
			notes.AddTag("Ann Lee", "Ninja looter")
			t.equal(Listed("Ann Lee"), 2, "and shows under each of their tags")
			t.ok(wow.click("Fold all"), "fold all")
			t.equal(Listed("Ann Lee"), 0, "everything folded")
			t.ok(wow.click("Unfold all"), "and unfold all")
			t.equal(Listed("Ann Lee"), 2, "open again")
			IsShiftKeyDown = function()
				return true
			end
			wow.click("#Tank")
			IsShiftKeyDown = function()
				return false
			end
			t.equal(Listed("Ann Lee"), 1, "shift-click: only that section open")
			t.equal(Listed("Gil Rowe"), 0, "the others folded")
			wow.click("Unfold all")
		end)

		t.test("a player's page: + Tag picks your tags or makes a new one; a click removes one", function()
			local menu
			MenuUtil.CreateContextMenu = function(owner, generator)
				menu = wow.newMenu()
				generator(owner, menu)
			end
			ns:OpenPlayerNotes("Bob Stone")
			t.ok(wow.click("+ Tag"), "+ Tag")
			local entry = wow.menuEntry(menu.entries, "#Ninja looter")
			t.ok(entry and entry.kind == "checkbox", "your tags to tick")
			t.ok(not entry.isSelected(), "not ticked yet")
			entry.onClick()
			t.ok(notes.HasTag(players()["bob stone"], "Ninja looter"), "added")
			t.ok(entry.isSelected(), "ticked")
			entry.onClick()
			t.ok(not notes.HasTag(players()["bob stone"], "Ninja looter"), "unticking removes it")
			entry.onClick()
			wow.menuEntry(menu.entries, "New tag...").onClick()
			local box = NraKitPlayerNotesFrame and wow.findAll(function(frame)
				return wow.visible(frame) and frame.template == "InputBoxTemplate" and frame.scripts.OnEditFocusLost
					and frame:GetParent() ~= nil and not rawget(frame, "tag")
			end)[1]
			t.ok(box, "a box for the new tag")
			t.ok(not wow.click("+ Tag"), "in place of + Tag")
			wow.type(box, "#Pvp hero")
			box.scripts.OnEnterPressed(box)
			t.ok(notes.HasTag(players()["bob stone"], "Pvp hero"), "made and added")
			t.ok(wow.click("+ Tag"), "+ Tag is back")
			t.ok(wow.click("#Ninja looter  |cff808080x|r"), "the tag chip")
			t.ok(not notes.HasTag(players()["bob stone"], "Ninja looter"), "removed")
			t.ok(wow.click("Kill on sight") or wow.click(notes.ToneText(notes.GetTone("hostile"))), "label chip")
			t.equal(players()["bob stone"].tone, "hostile", "label set")
			notes.SetTone("Bob Stone", "caution")
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
			t.equal(record.tone, "neutral", "default label")
		end)

		t.test("the tags page adds and renames tags", function()
			NraKitPlayerNotesFrame:Show()
			t.ok(wow.click("Tags"), "tags page")
			local newBox = wow.findAll(function(frame)
				return wow.visible(frame) and frame.template == "InputBoxTemplate" and not rawget(frame, "tag")
					and frame.scripts.OnEnterPressed and not frame.scripts.OnEditFocusLost
			end)[1]
			wow.type(newBox, "Healers")
			t.ok(wow.click("+ New tag"), "+ New tag")
			local healers
			for _, tag in ipairs(notes.AllTags()) do
				if tag.name == "Healers" then
					healers = tag
				end
			end
			t.ok(healers and healers.count == 0, "a tag nobody has yet")
			t.ok(#wow.findAll(function(frame)
				return wow.visible(frame) and rawget(frame, "label") == "#Healers"
			end) == 0, "no empty section in the list")
			local box = wow.findAll(function(frame)
				return wow.visible(frame) and rawget(frame, "tag") == "Tank" and frame.template == "InputBoxTemplate"
			end)[1]
			t.ok(box, "a row per tag")
			wow.type(box, "Good tank")
			box.scripts.OnEnterPressed(box)
			t.ok(notes.HasTag(players()["ann lee"], "Good tank"), "renamed")
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
