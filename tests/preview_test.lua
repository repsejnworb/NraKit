-- /nra preview: every preview shows without errors, with its feature on or off.

return {
	run = function(t, ns, wow)
		local NAMES = { "campfire", "goal", "goals", "milestone", "scan", "talents", "turnin", "warning" }
		local function Printed(text)
			for _, line in ipairs(wow.printed) do
				if line:find(text, 1, true) then
					return true
				end
			end
		end
		local function Shown(text)
			for _, frame in ipairs(wow.frames) do
				if frame.text == text and wow.visible(frame) then
					return true
				end
			end
		end

		t.test("/nra preview lists them", function()
			SlashCmdList.NRAKIT("preview")
			for _, name in ipairs(NAMES) do
				t.ok(Printed(name), "listed: " .. name)
			end
		end)

		t.test("each one runs (features off)", function()
			for _, name in ipairs(NAMES) do
				SlashCmdList.NRAKIT("preview " .. name)
				wow.advance(10)
			end
			t.noErrors()
		end)

		t.test("goal shows the Goal complete toast; /nra test works too", function()
			wow.advance(10)
			SlashCmdList.NRAKIT("test goal")
			t.ok(Shown("GOAL COMPLETE"), "toast")
		end)

		t.test("an unknown name says so", function()
			SlashCmdList.NRAKIT("preview nope")
			t.ok(Printed("No preview called \"nope\""), "says so")
		end)
	end,
}
