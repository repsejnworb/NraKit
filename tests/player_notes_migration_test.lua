-- Player notes from before tags: each player's label (from an editable list) becomes one
-- of the four fixed labels, and a label of your own becomes a tag too.

return {
	enable = { "playerNotes" },
	db = {
		playerNotesData = {
			labels = {
				{ id = "kos", name = "Kill on sight", tone = "hostile" },
				{ id = "avoid", name = "Gankers", tone = "caution" }, -- a built-in one, renamed
				{ id = "neutral", name = "Neutral", tone = "neutral" },
				{ id = "good", name = "Good", tone = "friendly" },
				{ id = "friend", name = "Friend", tone = "friendly", color = { 0.35, 0.7, 1 } },
				{ id = "custom1", name = "Good tank", tone = "friendly" },
			},
			nextLabel = 2,
			players = {
				["ann lee"] = { name = "Ann Lee", label = "kos", notes = { { text = "ganked me", time = 1 } }, created = 1, updated = 1 },
				["bob stone"] = { name = "Bob Stone", label = "avoid", notes = {}, created = 1, updated = 1 },
				["cid vale"] = { name = "Cid Vale", label = "good", notes = {}, created = 1, updated = 1 },
				["dee rook"] = { name = "Dee Rook", label = "friend", notes = {}, created = 1, updated = 1 },
				["eli moss"] = { name = "Eli Moss", label = "custom1", notes = {}, created = 1, updated = 1 },
				["fay dorn"] = { name = "Fay Dorn", label = "gone", notes = {}, created = 1, updated = 1 },
			},
		},
	},
	run = function(t, ns)
		local notes = ns.playerNotes

		t.test("labels become the four fixed ones, and your own become tags", function()
			local players = notes.GetData().players
			local function Check(key, tone, tags, what)
				local record = players[key]
				t.equal(record.tone, tone, what .. ": label")
				t.equal(table.concat(record.tags, ","), tags, what .. ": tags")
				t.ok(record.label == nil, what .. ": old label gone")
			end
			Check("ann lee", "hostile", "", "Kill on sight")
			Check("bob stone", "caution", "Gankers", "a renamed built-in label")
			Check("cid vale", "friendly", "", "Good")
			Check("dee rook", "friendly", "", "Friend")
			Check("eli moss", "friendly", "Good tank", "your own label")
			Check("fay dorn", "neutral", "", "a label that no longer exists")
			t.equal(players["ann lee"].notes[1].text, "ganked me", "notes kept")
			t.ok(notes.GetData().labels == nil and notes.GetData().nextLabel == nil, "the label list is gone")
			local tags = {}
			for _, tag in ipairs(notes.AllTags()) do
				table.insert(tags, tag.name)
			end
			t.equal(table.concat(tags, ","), "Gankers,Good tank", "the tag list")
			t.noErrors()
		end)
	end,
}
