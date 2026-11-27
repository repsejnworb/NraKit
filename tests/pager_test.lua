-- UI.CreatePager: a long list a page at a time, and back where you were when you come back to
-- the same list (only the place is kept, not the list).

return {
	enable = {},
	run = function(t, ns, wow)
		local UI = ns.UI
		local clicked = 0
		local pager = UI.CreatePager(UIParent, 10, function()
			clicked = clicked + 1
		end)
		-- A scroll area (the pager only reads and sets how far down it is).
		local scroll = { at = 0 }
		function scroll:SetScroll(value)
			self.at = value
		end
		function scroll:GetVerticalScroll()
			return self.at
		end
		local function List(count)
			local list = {}
			for i = 1, count do
				list[i] = i
			end
			return list
		end

		t.test("a page of the list, clamped to the last", function()
			pager:Open("things")
			local rows = pager:Slice(List(35), "all")
			t.equal(#rows, 10, "ten")
			t.equal(rows[1], 1, "from the first")
			pager.page = 9
			rows = pager:Slice(List(35), "all")
			t.equal(pager.page, 4, "only 4 pages")
			t.equal(#rows, 5, "the last 5")
			t.equal(pager:First(), 31, "from 31")
			t.equal(pager:Update(35, scroll), 4, "4 pages")
			t.ok(pager.frame:IsShown(), "the buttons")
			t.equal(pager:Update(8, scroll), 1, "one page")
			t.ok(not pager.frame:IsShown(), "no buttons")
		end)

		t.test("a page button pages and calls back", function()
			pager:Slice(List(35), "all")
			pager:Update(35, scroll)
			pager.prev:GetScript("OnClick")(pager.prev)
			t.equal(pager.page, 3, "back one")
			t.equal(clicked, 1, "called back")
		end)

		t.test("back to the same list: the same page and scroll; another list: page 1", function()
			pager.page = 2
			pager:Slice(List(35), "all")
			scroll:SetScroll(120)
			pager:Leave(scroll)
			pager:Open("other")
			pager:Slice(List(50), "other list")
			t.equal(pager.page, 1, "another list opens on page 1")
			pager:Open("things")
			t.equal(#pager:Slice({}, "all"), 0, "still loading: nothing yet")
			pager:Slice(List(35), "all")
			t.equal(pager.page, 2, "back on page 2")
			pager:Update(35, scroll)
			t.equal(scroll:GetVerticalScroll(), 120, "scrolled as you left it")
			pager:Open("things")
			pager:Slice(List(35), "a new search")
			t.equal(pager.page, 1, "the same name, but a different list: page 1")
		end)

		t.test("Reset: page 1, at the top", function()
			pager.page = 3
			pager:Reset()
			pager:Slice(List(35), "all")
			pager:Update(35, scroll)
			t.equal(pager.page, 1, "page 1")
			t.equal(scroll:GetVerticalScroll(), 0, "at the top")
		end)
	end,
}
