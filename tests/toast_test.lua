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

		t.test("a small toast waits for the one in front of it", function()
			toast.Show({ style = "small", heading = "A", text = "first", duration = 1 })
			toast.Show({ style = "small", heading = "B", text = "second", duration = 1 })
			t.ok(Shown("first"), "the first")
			t.ok(not Shown("second"), "the second waits")
			Wait(2.5)
			t.ok(Shown("second"), "then the second")
			Wait(2.5)
			t.ok(not toast.IsShowing("small"), "then gone")
		end)

		t.test("a big toast goes in front; skipIfBusy drops instead of waiting", function()
			toast.Show({ style = "small", text = "small one", duration = 5 })
			toast.Show({ style = "small", text = "waiting", duration = 1 })
			toast.Show({ style = "big", heading = "GOAL COMPLETE", text = "big one", duration = 1 })
			t.ok(Shown("big one"), "big shown")
			t.ok(not toast.IsShowing("small"), "the small one made way")
			t.ok(not Shown("waiting"), "and the waiting one doesn't jump over the big one")
			toast.Show({ style = "small", text = "milestone", skipIfBusy = true })
			Wait(2.5)
			t.ok(Shown("waiting"), "after the big one: the one that waited")
			Wait(2.5)
			t.ok(not Shown("milestone"), "the skipIfBusy one was dropped")
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
