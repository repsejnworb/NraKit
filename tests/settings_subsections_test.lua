-- Subsections in the NraKit window: a module with `subsection` (Warrior, in Classes) gets
-- its own entry under its section in the sidebar, showing just its features, options open.

return {
	run = function(t, ns, wow)
		local function Shown(text)
			return #wow.findAll(function(frame)
				return frame.text == text and wow.visible(frame)
			end) > 0
		end

		t.test("Classes lists Warrior as a subsection", function()
			local classes
			for _, section in ipairs(ns:GetSections()) do
				if section.name == "Classes" then
					classes = section
				end
			end
			t.ok(classes, "a Classes section")
			t.equal(classes.subsections[1].name, "Warrior", "with Warrior in it")
			t.equal(classes.subsections[1].modules[1].key, "warrior", "the Warrior module")
		end)

		t.test("clicking Warrior shows just Warrior, its options open", function()
			ns:OpenSettings()
			t.ok(wow.click("Warrior"), "a Warrior entry in the sidebar")
			t.ok(Shown("Classes  >  Warrior"), "headed Classes > Warrior")
			t.ok(Shown("Tactical Mastery mark"), "its options are open")
			t.ok(not Shown("Class-Colored Health Bars"), "nothing from other sections")
		end)

		t.test("clicking the section shows the whole section again", function()
			t.ok(wow.click("Classes"), "the Classes entry")
			t.ok(Shown("Classes"), "headed Classes")
			t.ok(not Shown("Tactical Mastery mark"), "options folded as usual")
			t.noErrors()
		end)
	end,
}
