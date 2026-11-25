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

		t.test("up to three at once, each new one above the others; the fourth waits", function()
			toast.Show({ style = "small", text = "first", duration = 1 })
			toast.Show({ style = "small", text = "second", duration = 5 })
			toast.Show({ style = "big", heading = "GOAL COMPLETE", text = "third", duration = 5 })
			toast.Show({ style = "small", text = "fourth", duration = 5 })
			t.ok(Shown("first") and Shown("second") and Shown("third"), "three at once (big ones too)")
			t.ok(not Shown("fourth"), "the fourth waits")
			local first, second, third = Toast("first"), Toast("second"), Toast("third")
			t.ok(rawget(first, "y") < rawget(second, "y") and rawget(second, "y") < rawget(third, "y"), "newest on top")
			local secondWas = rawget(second, "y")
			Wait(2.5)
			t.ok(not Shown("first") and Shown("fourth"), "the first went, the fourth came")
			t.ok(rawget(Toast("fourth"), "targetY") > rawget(third, "targetY"), "on top")
			t.ok(rawget(second, "y") < secondWas, "the ones above the gap slid down")
			t.equal(rawget(second, "y"), 168, "into the first one's place, at the bottom")
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

		t.test("arriving in a zone: one message, each part a title with its things under it", function()
			local shown
			local show = toast.Show
			toast.Show = function(spec)
				shown = spec
			end
			ns.arrival.Add({ zone = "Ironforge", title = "To do", color = { 0.4, 0.75, 1 }, order = 2,
				names = { "one", "two", "three", "four", "five", "six", "seven" } })
			ns.arrival.Add({ zone = "Ironforge", title = "Quests to turn in", order = 1, names = { "The Missing Diplomat" } })
			ns.arrival.Flush()
			toast.Show = show
			t.equal(shown.heading, "IRONFORGE", "the zone, once")
			t.equal(shown.text, nil, "no summary line")
			local expected = { "|cffffd100Quests to turn in|r", "•  The Missing Diplomat", "|cff66bfffTo do|r",
				"•  one", "•  two", "•  three", "•  four", "•  five", "|cff999999•  and 2 more|r" }
			t.equal(table.concat(shown.lines, " | "), table.concat(expected, " | "), "quests first, then to-dos, at most five each")
		end)
	end,
}
