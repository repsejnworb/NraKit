-- Copy Wowhead link: the box with the link shows on top of NraKit's windows.

local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

return {
	enable = { "wishlist" },
	run = function(t, ns, wow)
		-- Regression: the box was in the same layer as the NraKit window, so opening it from the
		-- Wishlist or Item lookup put it behind the window.
		t.test("the link box is above NraKit's windows", function()
			ns:OpenWishlist(true)
			local window = NraKitWishlistFrame
			ns.wowheadLink.Show("item", 7718)
			local box
			for _, frame in ipairs(wow.frames) do
				if rawget(frame, "url") then
					box = frame
				end
			end
			t.ok(box and box.shown, "shown")
			t.ok(STRATA[box:GetFrameStrata()] > STRATA[window:GetFrameStrata()],
				box:GetFrameStrata() .. " over " .. window:GetFrameStrata())
			t.noErrors()
		end)
	end,
}
