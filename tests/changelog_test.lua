-- What's new: the changelog data, what counts as new to you, the chat line after an
-- update, and the page in the NraKit window.

return {
	run = function(t, ns, wow)
		local whatsNew = ns.whatsNew
		local total = #whatsNew.Entries()
		local function Printed(text)
			for _, line in ipairs(wow.printed) do
				if line:find(text, 1, true) then
					return true
				end
			end
			return false
		end

		t.test("every entry is well formed", function()
			local kinds = { new = true, improved = true, fixed = true }
			for index, release in ipairs(ns.changelog) do
				if release.version == "Unreleased" then
					t.equal(index, 1, "Unreleased is the top block")
				else
					t.ok(release.version:match("^%d+%.%d+%.%d+"), "version number: " .. release.version)
					t.ok(release.date and release.date:match("^%d%d%d%d%-%d%d%-%d%d$"), "date for " .. release.version)
				end
				for _, entry in ipairs(release.entries) do
					t.ok(kinds[entry[1]], "kind in " .. release.version .. ": " .. tostring(entry[1]))
					t.ok(type(entry[2]) == "string" and entry[2] ~= "", "text in " .. release.version)
					if entry.module then
						t.ok(ns.modules[entry.module], "module exists: " .. entry.module)
					end
				end
			end
		end)

		t.test("every feature is announced as new somewhere", function()
			local announced = {}
			for _, entry in ipairs(whatsNew.Entries()) do
				if entry.kind == "new" and entry.module then
					announced[entry.module] = true
				end
			end
			for _, module in ipairs(ns.moduleOrder) do
				t.ok(announced[module.key], module.key .. " needs a \"new\" entry with module = \"" .. module.key .. "\" in Changelog.lua")
			end
		end)

		t.test("a fresh install has seen everything and says nothing", function()
			t.equal(NraKitDB.changelogSeen, total, "seen")
			t.equal(whatsNew.UnseenCount(), 0, "nothing new")
			wow.printed = {}
			whatsNew.Announce()
			t.equal(#wow.printed, 0, "no chat line")
		end)

		t.test("after an update: one chat line with what's new", function()
			NraKitDB.changelogSeen = total - 2
			NraKitDB.changelogAnnounced = total - 2
			wow.printed = {}
			whatsNew.Announce()
			t.equal(#wow.printed, 1, "one line")
			t.ok(Printed("has been updated") and Printed("/nra new"), "says how to see it")
			wow.printed = {}
			whatsNew.Announce()
			t.equal(#wow.printed, 0, "only once per update")
			t.equal(whatsNew.UnseenCount(), 2, "still unseen until the page is opened")
		end)

		t.test("the chat line can be turned off", function()
			NraKitDB.changelogAnnounced = 0
			NraKitDB.whatsNewChat = false
			wow.printed = {}
			whatsNew.Announce()
			t.equal(#wow.printed, 0, "no chat line")
			NraKitDB.whatsNewChat = nil
		end)

		t.test("/nra new opens the page and marks it all seen", function()
			SlashCmdList.NRAKIT("new")
			t.ok(NraKitOptionsFrame:IsShown(), "window open")
			t.equal(whatsNew.UnseenCount(), 0, "seen")
			local badges = wow.findAll(function(frame)
				return frame.shown and rawget(frame, "text") == "NEW TO YOU"
			end)
			t.ok(#badges >= 1, "the new version stays marked while the window is open")
		end)

		t.test("a new feature can be turned on from the page", function()
			-- Open every version, so a feature switch shows whatever the newest ones hold.
			for _ = 1, #ns.changelog do
				local closed = wow.findAll(function(frame)
					return wow.visible(frame) and rawget(frame, "version") and rawget(frame, "isOpen") == false
				end)[1]
				if not closed then
					break
				end
				closed.scripts.OnClick(closed)
			end
			local check = wow.findAll(function(frame)
				local key = rawget(frame, "settingKey")
				return wow.visible(frame) and key and ns.modules[key] and not NraKitDB[key]
			end)[1]
			t.ok(check, "switch shown")
			local key = check.settingKey -- the page redraws (and reuses the switch) after the click
			check:SetChecked(true)
			check.scripts.OnClick(check)
			t.equal(NraKitDB[key], true, "turned on")
			t.ok(wow.click("Settings"), "settings link")
			t.noErrors()
		end)

		t.test("the page's chat switch is saved", function()
			ns:OpenWhatsNew()
			local check
			for _, frame in ipairs(wow.findAll(function(frame)
				return wow.visible(frame) and rawget(frame, "settingKey") == "whatsNewChat"
			end)) do
				check = frame
			end
			check:SetChecked(false)
			check.scripts.OnClick(check)
			t.equal(NraKitDB.whatsNewChat, false, "off")
			t.ok(not whatsNew.ChatEnabled(), "no chat line")
		end)
	end,
}
