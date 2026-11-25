-- Toasts (Toast.lua): small ones wait their turn, big ones go in front, skipIfBusy drops.

return {
	run = function(t, ns, wow)
		local toast = ns.toast
		local function Shown(text)
			for _, frame in ipairs(wow.frames) do
				if frame.text == text and wow.visible(frame) then
					return true
				end
			end
			return false
		end
		local function Wait(seconds)
			for _ = 1, seconds * 10 do
				wow.advance(0.1)
			end
		end

		-- The toast frame showing this text.
		local function Toast(text)
			for _, frame in ipairs(wow.frames) do
				if frame.text == text and wow.visible(frame) then
					local holder = rawget(frame, "parent")
					return holder and rawget(holder, "parent")
				end
			end
		end

		t.test("up to three at once, the newest at the top pushing the others down; the fourth waits", function()
			toast.Show({ style = "small", text = "first", duration = 5 })
			local first = Toast("first")
			local top = rawget(first, "y")
			toast.Show({ style = "small", text = "second", duration = 1 })
			local second = Toast("second")
			t.equal(rawget(second, "y"), top, "the newest pops up at the top")
			t.ok(rawget(first, "targetY") < top, "the older one makes room below")
			wow.advance(1)
			t.equal(rawget(first, "y"), rawget(first, "targetY"), "sliding down to it")
			toast.Show({ style = "big", heading = "GOAL COMPLETE", text = "third", duration = 5 })
			toast.Show({ style = "small", text = "fourth", duration = 5 })
			local third = Toast("third")
			t.ok(Shown("first") and Shown("second") and Shown("third"), "three at once (big ones too)")
			t.ok(not Shown("fourth"), "the fourth waits")
			t.ok(rawget(third, "targetY") > rawget(second, "targetY") and rawget(second, "targetY") > rawget(first, "targetY"),
				"newest at the top, oldest lowest")
			local firstWas = rawget(first, "targetY")
			Wait(2.5)
			t.ok(not Shown("second") and Shown("fourth"), "the second went, the fourth came")
			t.equal(rawget(Toast("fourth"), "y"), top, "at the top")
			t.ok(rawget(first, "targetY") <= firstWas, "the oldest below the others")
			Wait(8)
			t.ok(not toast.IsShowing(), "then all gone")
		end)

		t.test("skipIfBusy drops it only when the screen is full; a big one is first in line", function()
			toast.Show({ style = "small", text = "one", duration = 1 })
			toast.Show({ style = "small", text = "milestone", skipIfBusy = true, duration = 1 })
			t.ok(Shown("milestone"), "room: shown")
			toast.Show({ style = "small", text = "two", duration = 1 })
			toast.Show({ style = "small", text = "dropped", skipIfBusy = true })
			toast.Show({ style = "small", text = "waiting", duration = 1 })
			toast.Show({ style = "big", heading = "GOAL COMPLETE", text = "big", duration = 1 })
			Wait(2.5)
			t.ok(Shown("big") and Shown("waiting"), "then the waiting ones, the big one first")
			t.ok(not Shown("dropped"), "the skipIfBusy one was dropped")
			Wait(3)
			t.noErrors()
		end)

		t.test("a toast with the same key as one already up isn't shown again; that one stays longer", function()
			toast.Show({ style = "small", text = "Stranglethorn", key = "arrival:Stranglethorn Vale", duration = 2 })
			Wait(1.5)
			toast.Show({ style = "small", text = "Stranglethorn again", key = "arrival:Stranglethorn Vale", duration = 2 })
			t.ok(not Shown("Stranglethorn again"), "not twice")
			Wait(1.5)
			t.ok(Shown("Stranglethorn"), "the first one stayed")
			toast.Show({ style = "small", text = "Wetlands", key = "arrival:Wetlands" })
			t.ok(Shown("Wetlands"), "another key shows")
			Wait(8)
		end)

		t.test("arriving in a zone: one message, each part a title with its things under it", function()
			local shown
			local show = toast.Show
			toast.Show = function(spec)
				shown = spec
			end
			local opened = {}
			ns.arrival.Add({ zone = "Ironforge", counts = { "7 TO-DOS" }, title = "TO-DO", icon = 1, order = 2,
				names = { "one", "two", "three", "four", "five", "six", "seven" }, onClick = function() table.insert(opened, "list") end })
			ns.arrival.Add({ zone = "Ironforge", counts = { "1 QUEST TO TURN IN" }, title = "QUESTS", atlas = "quest", order = 1,
				names = { "The Missing Diplomat" }, onClick = function() table.insert(opened, "quests") end })
			ns.arrival.Flush()
			toast.Show = show
			t.equal(shown.heading, "1 QUEST TO TURN IN  ·  7 TO-DOS", "the counts as its heading")
			t.equal(shown.text, "Ironforge", "the zone as its line, like other toasts")
			t.equal(shown.atlas, nil, "no icon on the zone line (the sections have them)")
			local texts = {}
			for _, line in ipairs(shown.lines) do
				table.insert(texts, (line.header and "# " or "") .. line.text)
			end
			local bullet = "|cff999999•|r  "
			local expected = { "# QUESTS", bullet .. "The Missing Diplomat", "# TO-DO", bullet .. "one", bullet .. "two",
				bullet .. "three", bullet .. "four", bullet .. "five", bullet .. "|cff999999and 2 more|r" }
			t.equal(table.concat(texts, " | "), table.concat(expected, " | "), "a section per part, quests first, at most five each")
			t.equal(shown.lines[1].atlas, "quest", "the section's icon")
			shown.lines[2].onClick()
			t.equal(table.concat(opened, ","), "quests", "a quest opens the quests")
			shown.lines[4].onClick()
			t.equal(table.concat(opened, ","), "quests,list", "a to-do the list")
			opened = {}
			shown.onClick()
			t.equal(table.concat(opened, ","), "quests,list", "the message itself both")
		end)
	end,
}
