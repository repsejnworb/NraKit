-- Campfire Timer: the campfire rest (once per time you sit down), and the sleeping bag
-- (Resting) waits for 3 stacks of Well-Rested.

local WELCOMING_CAMPFIRE, CAMP_BENEFITS = 1229739, 1229741
local SLEEPING_BAG, WELL_RESTED = 1331671, 429959

return {
	enable = { "campfireTimer" },
	run = function(t, ns, wow)
		local auras = {}
		C_UnitAuras.GetPlayerAuraBySpellID = function(spellID)
			return auras[spellID]
		end
		local function Set(spellID, aura)
			auras[spellID] = aura
			wow.fire("UNIT_AURA", "player")
		end
		local function Stacks(n)
			Set(WELL_RESTED, n > 0 and { applications = n, duration = 7200, expirationTime = 9999 } or nil)
		end
		local IN_BAG = { duration = 0, expirationTime = 0 }
		-- The bar's title and time text, or nil while it's hidden.
		local function Bar()
			wow.advance(0) -- the text updates every frame
			for _, frame in ipairs(wow.frames) do
				local title, time = rawget(frame, "title"), rawget(frame, "time")
				if title and time and rawget(frame, "track") and wow.visible(frame) then
					return rawget(title, "text"), rawget(time, "text")
				end
			end
		end
		local function Time()
			return select(2, Bar())
		end

		-- A round at the fire: the rest buff for 60 seconds, then Camp Benefits (as the game does it).
		local function SitDown()
			Set(WELCOMING_CAMPFIRE, { duration = 60, expirationTime = GetTime() + 60, icon = 1 })
		end
		local function FinishRound()
			wow.advance(60)
			auras[CAMP_BENEFITS] = { duration = 7200, expirationTime = GetTime() + 7200 }
			Set(WELCOMING_CAMPFIRE, nil)
		end

		-- Regression: with Camp Benefits from an earlier rest, getting up early said "Camp Benefits ready".
		-- Regression: the time was written (a new string) every frame.
		t.test("the time text is written only when the second changes", function()
			SitDown()
			Bar()
			local timeText
			for _, frame in ipairs(wow.frames) do
				if rawget(frame, "time") and rawget(frame, "track") then
					timeText = rawget(frame, "time")
				end
			end
			local writes = 0
			local setText = timeText.SetText
			rawset(timeText, "SetText", function(self, ...)
				writes = writes + 1
				return setText(self, ...)
			end)
			for _ = 1, 5 do
				wow.advance(0.1)
			end
			t.ok(writes <= 1, "at most once in half a second: " .. writes)
			wow.advance(1)
			t.ok(writes >= 1, "a new second, written")
			rawset(timeText, "SetText", nil)
			Set(WELCOMING_CAMPFIRE, nil) -- up early
			wow.advance(10)
		end)

		t.test("getting up early hides the bar, even with Camp Benefits from before", function()
			auras[CAMP_BENEFITS] = { duration = 7200, expirationTime = GetTime() + 3600 }
			SitDown()
			t.equal(Bar(), "Welcoming Campfire", "the bar shows")
			wow.advance(3)
			local played = #wow.played
			Set(WELCOMING_CAMPFIRE, nil)
			t.equal(Bar(), nil, "hidden, not done")
			t.equal(#wow.played, played, "no sound")
		end)

		t.test("staying seated after the rest doesn't show the bar every round", function()
			wow.advance(20)
			SitDown()
			local played = #wow.played
			FinishRound()
			t.equal(Bar(), "Camp Benefits ready", "done")
			t.ok(#wow.played > played, "with the sound")
			wow.advance(5)
			SitDown() -- the next round, still seated
			wow.advance(5)
			t.equal(Bar(), nil, "no bar for the next round")
			FinishRound()
			wow.advance(5)
			SitDown()
			t.equal(Bar(), nil, "nor the one after")
		end)

		t.test("sitting down again shows the bar again", function()
			wow.advance(10)
			Set(WELCOMING_CAMPFIRE, nil) -- got up during a round
			wow.advance(1)
			SitDown()
			t.equal(Bar(), "Welcoming Campfire", "after getting up during a round")
			FinishRound()
			wow.advance(15) -- got up between rounds
			SitDown()
			t.equal(Bar(), "Welcoming Campfire", "after getting up between rounds")
			Set(WELCOMING_CAMPFIRE, nil)
			auras[CAMP_BENEFITS] = nil
			wow.advance(10)
		end)

		t.test("in a sleeping bag the bar counts Well-Rested stacks, then says it's done", function()
			Set(SLEEPING_BAG, IN_BAG)
			t.equal(Bar(), "Well-Rested", "the bar shows")
			t.equal(Time(), "0/3", "no stacks yet, no time known")
			wow.advance(60)
			Stacks(1)
			t.equal(Time(), "1/3  2:00", "learned a stack takes a minute: two to go")
			wow.advance(30)
			t.equal(Time(), "1/3  1:30", "counts down")
			wow.advance(30)
			Stacks(2)
			local played = #wow.played
			wow.advance(60)
			Stacks(3)
			t.equal(Bar(), "Fully Well-Rested", "done")
			t.ok(#wow.played > played, "with the sound")
			t.equal(NraKitDB.campfireTimerData.wellRestedInterval, 60, "the interval is saved")
		end)

		t.test("getting out early hides the bar; already full shows done without a sound", function()
			Set(SLEEPING_BAG, nil)
			Stacks(0)
			wow.advance(10)
			t.equal(Bar(), nil, "the done message has faded")
			Set(SLEEPING_BAG, IN_BAG)
			t.equal(Time(), "0/3  3:00", "uses the learned interval right away")
			Set(SLEEPING_BAG, nil)
			t.equal(Bar(), nil, "hidden when you get out")
			Stacks(3)
			local played = #wow.played
			Set(SLEEPING_BAG, IN_BAG)
			t.equal(Bar(), "Fully Well-Rested", "says you're full")
			t.equal(#wow.played, played, "no sound")
		end)

		t.test("the sleeping bag can be turned off", function()
			Set(SLEEPING_BAG, nil)
			Stacks(1)
			wow.advance(10)
			ns:SetSetting("campfireTimerSleepingBag", false)
			Set(SLEEPING_BAG, IN_BAG)
			t.equal(Bar(), nil, "no bar")
			t.noErrors()
		end)
	end,
}
