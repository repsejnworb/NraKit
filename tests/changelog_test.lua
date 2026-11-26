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
					t.ok(entry.title == nil or type(entry.title) == "string", "title is text in " .. release.version)
					t.ok(entry.tip == nil or type(entry.tip) == "string", "tip is text in " .. release.version)
					if entry.points then
						t.ok(#entry.points >= 1 and #entry.points <= 5, "1 to 5 points in " .. release.version)
						for _, point in ipairs(entry.points) do
							t.ok(type(point) == "string" and point ~= "", "a point is text in " .. release.version)
						end
					end
					if entry.module then
						t.ok(ns.modules[entry.module], "module exists: " .. entry.module)
					end
				end
			end
		end)

		-- Regression: a "→" showed as an empty box. The game font draws plain text, accented
		-- letters (Latin-1) and "•", little else: no arrows, curly quotes, em dashes or "…".
		t.test("entries only use characters the game font has", function()
			local function Check(text, where)
				local rest = text:gsub("[\32-\126]", ""):gsub("\194[\160-\191]", ""):gsub("\195[\128-\191]", "")
					:gsub("\226\128\162", "")
				t.ok(rest == "", "a character the game can't draw in " .. where .. ": " .. text)
			end
			for _, release in ipairs(ns.changelog) do
				for _, entry in ipairs(release.entries) do
					local where = release.version
					Check(entry[2], where)
					if entry.title then
						Check(entry.title, where)
					end
					if entry.tip then
						Check(entry.tip, where)
					end
					for _, point in ipairs(entry.points or {}) do
						Check(point, where)
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

		t.test("**words** stand out and /commands are gold", function()
			t.equal(whatsNew.Markup("Type **this** or /nra new (or /goal)."),
				"Type |cffffffffthis|r or |cffffd100/nra new|r (or |cffffd100/goal|r).", "marked up, /nra new as one")
			t.equal(whatsNew.Markup("its /nra command"), "its |cffffd100/nra|r command",
				"a word after /nra that isn't one of its commands stays out")
			-- Regression: colours don't nest, so gold commands inside a highlight broke it up.
			t.equal(whatsNew.Markup("**/remind, /todo** and /done."), "|cffffffff/remind, /todo|r and |cffffd100/done|r.",
				"commands inside a highlight stay bright")
			t.equal(whatsNew.Markup("and/or"), "and/or", "a slash inside a word is left alone")
		end)

		t.test("a feature with points is a title, summary, bullets and tip", function()
			ns:OpenWhatsNew()
			local function Visible(match)
				return wow.findAll(function(frame)
					return wow.visible(frame) and type(frame.text) == "string" and frame.text:find(match, 1, true)
				end)
			end
			t.ok(#Visible("•") >= 3, "bullets")
			t.ok(#Visible("Cooldown Manager fade") >= 1, "the feature's title")
			t.ok(#Visible("help-i") >= 1, "a tip, with its icon")
			t.ok(#Visible("|cffffffffwhich bars|r") >= 1, "highlighted words")
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

		-- Regression: a pooled switch kept the wide click area a feature card gave it, and it
		-- covered the Settings button next to it, so clicking Settings toggled the feature.
		t.test("a new feature's switch doesn't cover its Settings button", function()
			ns:OpenSettings("a") -- feature cards (every name with an "a"): switches widened over the names
			ns:OpenWhatsNew()
			for _ = 1, #ns.changelog do
				local closed = wow.findAll(function(frame)
					return wow.visible(frame) and rawget(frame, "version") and rawget(frame, "isOpen") == false
				end)[1]
				if not closed then
					break
				end
				closed.scripts.OnClick(closed)
			end
			local switches = wow.findAll(function(frame)
				return wow.visible(frame) and rawget(frame, "tooltipText") == "Turn this feature on or off."
			end)
			t.ok(#switches > 0, "feature switches shown")
			for _, switch in ipairs(switches) do
				local _, right = switch:GetHitRectInsets()
				-- 22 wide, Settings starts 62 to the right of the switch's left edge
				t.ok(22 - right < 62, "click area ends before Settings: " .. tostring(switch.settingKey) .. " reaches " .. (22 - right))
			end
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
