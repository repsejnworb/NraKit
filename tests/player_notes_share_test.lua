-- Player notes in chat (PlayerNotesShare.lua): linking a note, the link others see, asking
-- for the note, the pieces it's sent in, and adding it from the review window.

return {
	enable = { "playerNotes" },
	run = function(t, ns, wow)
		local notes, share = ns.playerNotes, ns.playerNotesShare
		local sent, timers = {}, {}
		local sendResult -- what the next SendAddonMessage returns
		C_ChatInfo.SendAddonMessage = function(prefix, message, channel, target)
			table.insert(sent, { prefix = prefix, message = message, channel = channel, target = target })
			local result = sendResult
			sendResult = nil
			return result or 0
		end
		C_Timer.After = function(_, callback)
			table.insert(timers, callback)
		end
		local function RunTimers()
			while #timers > 0 do
				local pending = timers
				timers = {}
				for _, callback in ipairs(pending) do
					callback()
				end
			end
		end
		local function Message(text, sender)
			wow.fire("CHAT_MSG_ADDON", "NraKitNote", text, "WHISPER", sender)
		end
		local function Printed(text)
			for _, line in ipairs(wow.printed) do
				if line:find(text, 1, true) then
					return true
				end
			end
			return false
		end
		local function Sent(kind)
			local list = {}
			for _, message in ipairs(sent) do
				if message.message:sub(1, #kind + 1) == kind .. "\t" then
					table.insert(list, message)
				end
			end
			return list
		end
		local function ReviewShown()
			return NraKitNoteShareFrame ~= nil and NraKitNoteShareFrame:IsShown()
		end
		wow.data.units.player = { name = "Nra", surname = "Brown" }

		local SPECIAL = "tab\there, a new\nline, a || pipe, a \\ backslash and Æsir åäö"
		notes.SetLabel("Theron Nightbloom", "avoid")
		notes.AddNote("Theron Nightbloom", "Ninjad a crate back in Westfall.")
		notes.AddNote("Theron Nightbloom", SPECIAL)
		for index = 1, 3 do
			notes.AddNote("Theron Nightbloom", index .. ": " .. string.rep("long story about him ", 12))
		end
		notes.GetData().players["theron nightbloom"].notes[1].by = "Banker Nra"
		notes.AddNote("Zed Quill", "never linked")

		t.test("shift-click a player in your notes links them in chat", function()
			ns:OpenPlayerNotes()
			local button = wow.findAll(function(frame)
				return wow.visible(frame) and rawget(frame, "key") == "theron nightbloom"
			end)[1]
			IsModifiedClick = function(kind)
				return kind == "CHATLINK"
			end
			button.scripts.OnClick(button)
			IsModifiedClick = function()
				return false
			end
			t.equal(wow.chatBox, "[NraKit note: Theron Nightbloom]", "in the chat box")
			NraKitPlayerNotesFrame:Hide()
		end)

		t.test("the text in chat becomes a link to whoever sent it", function()
			local line = wow.chat("CHAT_MSG_SAY", "watch out: [NraKit note: Theron Nightbloom]", "Angry Nra")
			t.ok(line:find("|Haddon:nrakit:note:Angry Nra:Theron Nightbloom|h[NraKit note: Theron Nightbloom]|h", 1, true), line)
			t.ok(line:find("^watch out: "), "the rest of the line stays")
			line = wow.chat("CHAT_MSG_WHISPER_INFORM", "[NraKit note: Theron Nightbloom]", "Bob Stone")
			t.ok(line:find("note:Nra Brown:", 1, true), "a whisper you send links to you, not the receiver")
			ns:SetSetting("playerNotesShareLinks", false)
			t.equal(wow.chat("CHAT_MSG_SAY", "[NraKit note: X Y]", "Angry Nra"), "[NraKit note: X Y]", "plain with the option off")
			ns:SetSetting("playerNotesShareLinks", true)
		end)

		t.test("a note you didn't link isn't sent", function()
			sent = {}
			Message("REQ\t7\tZed Quill", "Ann Lee")
			Message("REQ\t8\tNobody Here", "Ann Lee")
			RunTimers()
			t.equal(#Sent("DENY"), 2, "denied")
			t.equal(sent[1].message, "DENY\t7", "with the request's id")
			t.equal(sent[1].target, "Ann Lee", "whispered back")
			t.equal(#Sent("PART"), 0, "nothing of the note")
		end)

		local pieces
		t.test("a linked note is sent in numbered pieces", function()
			sent = {}
			Message("REQ\t1\tTheron Nightbloom", "Bob Stone")
			RunTimers()
			pieces = Sent("PART")
			t.ok(#pieces > 1, "more than one piece: " .. #pieces)
			for index, piece in ipairs(pieces) do
				t.ok(#piece.message <= 255, "fits in an addon message")
				t.ok(piece.message:find("^PART\t1\t" .. index .. "\t" .. #pieces .. "\t"), "numbered")
				t.equal(piece.target, "Bob Stone", "to whoever asked")
			end
		end)

		t.test("a throttled piece is sent again", function()
			sent = {}
			sendResult = 3
			Message("REQ\t2\tTheron Nightbloom", "Bob Stone")
			RunTimers()
			t.equal(#Sent("PART"), #pieces + 1, "the throttled one twice")
			t.equal(Sent("PART")[1].message, Sent("PART")[2].message, "the same piece again")
		end)

		t.test("clicking a link asks for the note; pieces out of order still open it", function()
			notes.DeletePlayer("theron nightbloom")
			sent = {}
			wow.clickLink("addon:nrakit:note:Angry Nra:Theron Nightbloom")
			local request = Sent("REQ")[1]
			t.ok(request, "asked")
			t.equal(request.target, "Angry Nra", "the one who linked it")
			local id = request.message:match("^REQ\t(%d+)\tTheron Nightbloom$")
			t.ok(id, "for that player: " .. request.message:gsub("\t", "<TAB>"))
			Message("PART\t999\t1\t1\tjunk", "Angry Nra") -- not our request
			for index = #pieces, 1, -1 do
				t.ok(not ReviewShown(), "waits for every piece")
				Message(pieces[index].message:gsub("^PART\t1\t", "PART\t" .. id .. "\t"), "Angry Nra")
			end
			t.ok(ReviewShown(), "review window")
			t.ok(wow.click("Add 5 notes"), "Add, with the count")
			t.ok(not ReviewShown(), "closes")
			local record = notes.Find("Theron Nightbloom")
			t.equal(record.label, "avoid", "their label, for someone new")
			t.equal(#record.notes, 5, "every note")
			t.equal(record.notes[1].by, "Banker Nra", "keeps who wrote it")
			t.equal(record.notes[1].sharedBy, "Angry Nra", "and who shared it")
			t.equal(record.notes[2].text, SPECIAL, "tabs, new lines, pipes and letters come through")
		end)

		t.test("adding again skips notes you have; your label stays unless you pick theirs", function()
			notes.SetLabel("Theron Nightbloom", "neutral")
			local shared = { name = "Theron Nightbloom", label = "Kill on sight", tone = "hostile", total = 2, from = "Ann Lee",
				notes = { notes.Find("Theron Nightbloom").notes[1], { time = 5, text = "new one", by = "Ann Lee" } } }
			share.ShowReview(shared)
			t.ok(wow.click("Add 1 note"), "only the new one counts")
			local record = notes.Find("Theron Nightbloom")
			t.equal(#record.notes, 6, "one added")
			t.equal(record.label, "neutral", "kept your label")
			share.ShowReview(shared)
			t.equal(select(2, wow.click("Add")), "disabled", "nothing new to add")
			for _, frame in ipairs(wow.frames) do
				local text = rawget(frame, "text")
				if frame.scripts.OnClick and wow.visible(frame) and type(text) == "table" and (rawget(text, "text") or ""):find("^Use ") then
					frame.scripts.OnClick(frame)
				end
			end
			t.ok(wow.click("Add"), "the label is a change")
			t.equal(notes.Find("Theron Nightbloom").label, "kos", "their label, matched by name")
		end)

		t.test("no answer, offline, or not linked: it says so", function()
			wow.printed = {}
			wow.clickLink("addon:nrakit:note:Angry Nra:Theron Nightbloom")
			wow.advance(10)
			RunTimers()
			t.ok(Printed("No answer from Angry Nra"), "no answer")
			sendResult = 12
			wow.clickLink("addon:nrakit:note:Gone Guy:Theron Nightbloom")
			t.ok(Printed("Gone Guy is offline"), "offline")
			sent = {}
			wow.clickLink("addon:nrakit:note:Ann Lee:Theron Nightbloom")
			Message("DENY\t" .. Sent("REQ")[1].message:match("^REQ\t(%d+)"), "Ann Lee")
			t.ok(Printed("Ann Lee hasn't linked a note on Theron Nightbloom"), "denied")
		end)

		t.test("your own link opens your notes", function()
			sent = {}
			wow.clickLink("addon:nrakit:note:Nra Brown:Theron Nightbloom")
			t.equal(#sent, 0, "nothing sent")
			t.ok(NraKitPlayerNotesFrame:IsShown(), "your notes")
			t.noErrors()
		end)
	end,
}
