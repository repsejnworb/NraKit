local _, ns = ...

-- Toasts: NraKit's messages in the middle of the screen, one look for every feature.
--
-- ns.toast.Show{
--   style = "big" | "small",  big: a heading, a large line with an icon and a detail line, with a
--                             pop (Farm goals' "Goal complete"); small: quieter and lower (a
--                             milestone, "3 quests to turn in here")
--   heading, text, detail,    the lines (detail is optional; without text, the list follows the heading)
--   lines = { "..." or { text, onClick }, ... },
--                             a list under it, one per line: a block as wide as its longest line
--                             (long ones wrap), centred. A line with onClick opens what it's about
--                             (clicking elsewhere does the message's onClick). The message grows.
--   icon = texture / atlas =, shown left of the text (optional)
--   headingColor = { r, g, b },
--   duration = seconds,       before it fades (default 6 big, 3 small); the mouse on it keeps it up
--   size = scale,             (default 1)
--   onClick = function,       makes it clickable (it closes when clicked); otherwise clicks go through
--   skipIfBusy = true,        drop it instead of waiting when the screen is full of toasts
-- }
-- Toasts stack, up to MAX_SHOWN at once: each new one above the others, which stay put. More
-- wait their turn (a big one first in line); when one goes, those above it slide down.

local UI = ns.UI
local toast = {}
ns.toast = toast

local FADE = 1
local HOVER_GRACE = 2 -- seconds a toast stays after the mouse leaves it
local LIST_WIDTH = 420 -- the widest a list gets before its lines wrap
local MAX_SHOWN = 3 -- at once; more wait their turn
local MAX_QUEUE = 5 -- waiting; more are dropped
local BOTTOM = 168 -- the lowest toast's bottom edge, above the middle of the screen
local GAP = 8
local SLIDE = 12 -- how quickly toasts slide down into a gap
local DEFAULTS = { big = { duration = 6 }, small = { duration = 3 } }

local free = { big = {}, small = {} } -- toast frames not in use
local shown = {} -- on screen, oldest (lowest) first
local queue = {}
local ShowNext, ShowLines

-- Big: overshoots and settles; small: a gentle pop.
local function PopScale(style, age)
	if style == "small" then
		return age < 0.2 and (1.12 - 0.12 * age / 0.2) or 1
	end
	if age < 0.18 then
		return 1.35 - 0.4 * (age / 0.18)
	elseif age < 0.35 then
		return 0.95 + 0.05 * ((age - 0.18) / 0.17)
	end
	return 1
end

local function Place(frame)
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOM", UIParent, "CENTER", 0, frame.y)
end

-- Where each toast belongs: stacked upwards from the bottom, oldest lowest. A new one goes
-- straight to its place; the others slide (OnUpdate).
local function Restack()
	local y = BOTTOM
	for _, frame in ipairs(shown) do
		frame.targetY = y
		if not frame.y then
			frame.y = y
			Place(frame)
		end
		y = y + frame:GetHeight() + GAP
	end
end

local function OnUpdate(self, elapsed)
	if self.y and self.targetY and self.y ~= self.targetY then
		local step = (self.targetY - self.y) * math.min(1, (elapsed or 0) * SLIDE)
		self.y = math.abs(self.targetY - self.y) < 0.5 and self.targetY or self.y + step
		Place(self)
	end
	local now = GetTime()
	if self:IsMouseOver() and now - self.shownAt > 0.35 then
		self.holdUntil = math.max(self.holdUntil, now + HOVER_GRACE) -- the mouse on it keeps it up
	end
	self.inner:SetScale(PopScale(self.style, now - self.shownAt) * self.size)
	if now > self.holdUntil + FADE then
		self:Hide()
	elseif now > self.holdUntil then
		self:SetAlpha(1 - (now - self.holdUntil) / FADE)
	else
		self:SetAlpha(1)
	end
end

local function CreateToastFrame(style)
	local big = style == "big"
	local width, height = big and 640 or 520, big and 110 or 64
	-- The holder stays put; the inner frame is scaled around its centre for the pop.
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(width, height)
	frame.baseHeight = height -- placed in the stack by Restack
	frame:SetFrameStrata("HIGH")
	frame:Hide()
	frame.style = style
	local inner = CreateFrame("Frame", nil, frame)
	inner:SetSize(width, height)
	inner:SetPoint("CENTER")
	frame.inner = inner

	frame.heading = inner:CreateFontString(nil, "OVERLAY", big and "GameFontNormalLarge" or "GameFontNormalSmall")
	frame.text = inner:CreateFontString(nil, "OVERLAY", big and "GameFontNormalHuge" or "GameFontNormalLarge")
	frame.text:SetTextColor(1, 1, 1)
	frame.detail = inner:CreateFontString(nil, "OVERLAY", big and "GameFontHighlight" or "GameFontHighlightSmall")
	frame.detail:SetTextColor(unpack(UI.TEXT))
	frame.detail:SetWidth(width - 40)
	frame.detail:SetWordWrap(false)
	frame.lines = {} -- the list's lines (buttons, made as needed)
	frame.icon = inner:CreateTexture(nil, "ARTWORK")
	local iconSize = big and 44 or 20
	frame.icon:SetSize(iconSize, iconSize)
	frame.iconSize = iconSize

	frame.heading:SetPoint("TOP", 0, 0)
	frame:SetScript("OnUpdate", OnUpdate)
	frame:SetScript("OnMouseUp", function(self)
		local onClick = self.onClick
		self:Hide()
		if onClick then
			onClick()
		end
	end)
	frame:HookScript("OnHide", function(self)
		for index, each in ipairs(shown) do
			if each == self then
				table.remove(shown, index)
			end
		end
		self.y, self.targetY = nil, nil
		table.insert(free[self.style], self)
		Restack()
		ShowNext()
	end)
	return frame
end

local function LineButton(frame, index)
	local line = frame.lines[index]
	if not line then
		line = CreateFrame("Button", nil, frame.inner)
		line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		line.text:SetPoint("TOPLEFT")
		line.text:SetJustifyH("LEFT")
		line.text:SetWordWrap(true)
		line.highlight = line:CreateTexture(nil, "HIGHLIGHT")
		line.highlight:SetAllPoints()
		line.highlight:SetColorTexture(1, 1, 1, 0.08)
		line:SetScript("OnClick", function(self)
			local onClick = self.onClick
			frame:Hide()
			if onClick then
				onClick()
			end
		end)
		frame.lines[index] = line
	end
	return line
end

-- Lays out the list under `above`: a centred block as wide as its longest line. Returns its height.
function ShowLines(frame, lines, above)
	for _, line in ipairs(frame.lines) do
		line:Hide()
	end
	if #lines == 0 then
		return 0
	end
	local width = 0
	for index, entry in ipairs(lines) do
		local line = LineButton(frame, index)
		line.text:SetWidth(0)
		line.text:SetText(type(entry) == "table" and entry.text or entry)
		width = math.max(width, line.text:GetStringWidth())
	end
	width = math.min(math.ceil(width) + 2, LIST_WIDTH)
	local height, previous = 0, nil
	for index, entry in ipairs(lines) do
		local line = frame.lines[index]
		line.text:SetWidth(width)
		local lineHeight = line.text:GetStringHeight()
		line:SetSize(width, lineHeight)
		line:ClearAllPoints()
		if previous then
			line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -3)
		else
			line:SetPoint("TOP", above, "BOTTOM", 0, -8)
		end
		line.onClick = type(entry) == "table" and entry.onClick or nil
		line:EnableMouse(line.onClick ~= nil)
		line:Show()
		height = height + lineHeight + 3
		previous = line
	end
	return height + 10
end

local function Display(spec)
	local style = spec.style == "big" and "big" or "small"
	local frame = table.remove(free[style]) or CreateToastFrame(style)
	frame.heading:SetText(spec.heading or "")
	frame.heading:SetTextColor(unpack(spec.headingColor or UI.ACCENT))
	frame.text:SetText(spec.text or "")
	frame.detail:SetText(spec.detail or "")
	frame.detail:SetShown(spec.detail ~= nil)

	-- Icon left of the text, both centred together.
	local hasIcon = spec.icon ~= nil or spec.atlas ~= nil
	if spec.atlas then
		frame.icon:SetAtlas(spec.atlas)
		frame.icon:SetTexCoord(0, 1, 0, 1)
	elseif spec.icon then
		frame.icon:SetTexture(spec.icon)
		frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	frame.icon:SetShown(hasIcon)
	local shift = hasIcon and (frame.iconSize + 8) / 2 or 0
	frame.text:ClearAllPoints()
	frame.text:SetPoint("TOP", frame.heading, "BOTTOM", shift, style == "big" and -8 or -4)
	frame.icon:ClearAllPoints()
	frame.icon:SetPoint("RIGHT", frame.text, "LEFT", -8, 0)
	frame.detail:ClearAllPoints()
	frame.detail:SetPoint("TOP", frame.text, "BOTTOM", -shift, style == "big" and -8 or -4)

	-- The list, under the detail, the text or (with neither) the heading.
	local hasText = spec.text ~= nil and spec.text ~= ""
	frame.text:SetShown(hasText)
	frame.icon:SetShown(hasIcon and hasText)
	local above = spec.detail and frame.detail or hasText and frame.text or frame.heading
	local height = (hasText and frame.baseHeight or 24) + ShowLines(frame, spec.lines or {}, above)
	frame:SetHeight(height)
	frame.inner:SetHeight(height)

	frame.onClick = spec.onClick
	frame:EnableMouse(spec.onClick ~= nil)
	frame.size = spec.size or 1
	frame.shownAt = GetTime()
	frame.holdUntil = frame.shownAt + (spec.duration or DEFAULTS[style].duration)
	frame:SetAlpha(1)
	table.insert(shown, frame)
	Restack()
	frame:Show()
end

function ShowNext()
	while #shown < MAX_SHOWN and #queue > 0 do
		Display(table.remove(queue, 1))
	end
end

function toast.Show(spec)
	if #shown < MAX_SHOWN then
		Display(spec)
	elseif not spec.skipIfBusy and #queue < MAX_QUEUE then
		-- A big one (a goal done) is first in line.
		table.insert(queue, spec.style == "big" and 1 or #queue + 1, spec)
	end
end

-- Whether a toast (of this style, or any) is showing now (tests, and features that want to know).
function toast.IsShowing(style)
	for _, frame in ipairs(shown) do
		if not style or frame.style == style then
			return true
		end
	end
	return false
end

------------------------------------------------------------------------------
-- Arrival: one small message when you enter a zone, with what features have for you there
-- (quests to turn in, to-dos). Features add their part as they notice; parts within a moment
-- of each other share one message. Dropped in combat (stale by the end of the fight).
--
-- ns.arrival.Add{ zone = "Ironforge", one = "to-do", many = "to-dos", color = { r, g, b },
--   names = { ... }, onClick = function, order = number (lower first; quests 1, to-dos 2) }
-- Shown like other toasts: the counts as its heading ("1 QUEST TO TURN IN · 2 TO-DOS", each in
-- its colour), the zone as its line (with an icon), and the names under it, one per line,
-- with a bullet in their part's colour.
------------------------------------------------------------------------------

local arrival = {}
ns.arrival = arrival
local MAX_ARRIVAL_NAMES = 5 -- per part; the rest are counted
local pending = {}

function arrival.Flush()
	local parts = pending
	pending = {}
	if #parts == 0 or InCombatLockdown() then
		return
	end
	table.sort(parts, function(a, b)
		return (a.order or 9) < (b.order or 9)
	end)
	local zones, seen, counts, lines, clicks = {}, {}, {}, {}, {}
	local hasQuests = false
	for _, part in ipairs(parts) do
		if part.zone and not seen[part.zone] then
			seen[part.zone] = true
			table.insert(zones, part.zone)
		end
		local color = part.color or UI.GOLD
		local hex = string.format("|cff%02x%02x%02x", color[1] * 255, color[2] * 255, color[3] * 255)
		local names = part.names or {}
		-- "1 QUEST TO TURN IN" in its colour, for the heading.
		table.insert(counts, hex .. (#names .. " " .. (#names == 1 and part.one or part.many)):upper() .. "|r")
		for index, name in ipairs(names) do
			if index > MAX_ARRIVAL_NAMES then
				table.insert(lines, { text = string.format("%s•|r  |cff999999and %d more|r", hex, #names - MAX_ARRIVAL_NAMES), onClick = part.onClick })
				break
			end
			table.insert(lines, { text = hex .. "•|r  " .. name, onClick = part.onClick })
		end
		table.insert(clicks, part.onClick)
		hasQuests = hasQuests or part.order == 1
	end
	toast.Show({
		style = "small",
		heading = table.concat(counts, "  ·  "),
		text = table.concat(zones, " · "),
		atlas = hasQuests and "UI-QuestIcon-TurnIn-Normal" or nil,
		icon = not hasQuests and "Interface\\Icons\\INV_Misc_Note_01" or nil,
		lines = lines,
		duration = 6 + math.min(4, #lines * 0.5), -- a longer list stays a little longer
		-- Clicking the message opens all of it (a line opens just what it's about).
		onClick = function()
			for _, onClick in ipairs(clicks) do
				onClick()
			end
		end,
	})
end

function arrival.Add(part)
	table.insert(pending, part)
	if #pending == 1 then
		C_Timer.After(0.3, arrival.Flush)
	end
end
