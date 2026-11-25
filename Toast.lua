local _, ns = ...

-- Toasts: NraKit's messages in the middle of the screen, one look for every feature.
--
-- ns.toast.Show{
--   style = "big" | "small",  big: a heading, a large line with an icon and a detail line, with a
--                             pop (Farm goals' "Goal complete"); small: quieter and lower (a
--                             milestone, "3 quests to turn in here")
--   heading, text, detail,    the lines (each optional: without a heading the text is at the top,
--                             without text the list follows the heading)
--   textFont = font object,   for the text, e.g. "GameFontNormalHuge" (a zone's name)
--   lines = { "..." or { text, onClick, header, icon / atlas, iconColor }, ... },
--                             a list under it: one group, centred under the text, as wide as its
--                             longest line but no wider than the text above it (long lines wrap),
--                             the lines left-aligned in it. A header line (small capitals, an icon
--                             before it) starts a section; the lines under it line up with its
--                             title. A line with onClick opens what it's about (clicking elsewhere
--                             does the message's onClick). The message grows to fit.
--   icon = texture / atlas =, shown left of the text (optional)
--   headingColor = { r, g, b },
--   duration = seconds,       before it fades (default 6 big, 3 small); the mouse on it keeps it up
--   size = scale,             (default 1)
--   onClick = function,       makes it clickable (it closes when clicked); otherwise clicks go through
--   skipIfBusy = true,        drop it instead of waiting when the screen is full of toasts
--   key = "...",              one of its kind: while a toast with this key is up (or waiting),
--                             this one isn't shown; the one up stays a while longer instead
-- }
-- Toasts stack, up to MAX_SHOWN at once: the newest pops up at the top, always the same place,
-- and pushes the older ones down (they slide). More wait their turn (a big one first in line);
-- when one goes, the older ones below it slide up into the gap.

local UI = ns.UI
local toast = {}
ns.toast = toast

local FADE = 1
local HOVER_GRACE = 2 -- seconds a toast stays after the mouse leaves it
local LIST_MIN_WIDTH = 220 -- a list may be this wide even under a short title
local LIST_INSET = 20 -- where a section's title and its lines start, after the icon
local MAX_SHOWN = 3 -- at once; more wait their turn
local MAX_QUEUE = 5 -- waiting; more are dropped
local TOP = 260 -- the newest toast's top edge, above the middle of the screen
local GAP = 8
local SLIDE = 12 -- how quickly toasts slide down into a gap
local DEFAULTS = { big = { duration = 6 }, small = { duration = 3 } }

local free = { big = {}, small = {} } -- toast frames not in use
local shown = {} -- on screen, oldest first (the newest is at the top)
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
	frame:SetPoint("TOP", UIParent, "CENTER", 0, frame.y)
end

-- Where each toast belongs: the newest at the top, the older ones below it. A new one goes
-- straight to its place (and pops); the others slide there (OnUpdate).
local function Restack()
	local y = TOP
	for index = #shown, 1, -1 do
		local frame = shown[index]
		frame.targetY = y
		if not frame.y then
			frame.y = y
			Place(frame)
		end
		y = y - frame:GetHeight() - GAP
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
		line.icon = line:CreateTexture(nil, "ARTWORK")
		line.icon:SetSize(14, 14)
		line.icon:SetPoint("TOPLEFT", 0, 0)
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
	-- Headers: small capitals after their icon; the lines under them line up with the title.
	local width = 0
	for index, entry in ipairs(lines) do
		local line = LineButton(frame, index)
		entry = type(entry) == "table" and entry or { text = entry }
		local header = entry.header == true
		line.inset = LIST_INSET
		line.text:SetFontObject(header and "GameFontNormalSmall" or "GameFontHighlightSmall")
		line.text:ClearAllPoints()
		line.text:SetPoint("TOPLEFT", line.inset, header and -1 or 0)
		line.text:SetWidth(0)
		line.text:SetText(entry.text)
		if entry.atlas then
			line.icon:SetAtlas(entry.atlas)
			line.icon:SetTexCoord(0, 1, 0, 1)
		elseif entry.icon then
			line.icon:SetTexture(entry.icon)
			line.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
		line.icon:SetVertexColor(unpack(entry.iconColor or { 1, 1, 1 }))
		line.icon:SetShown(header and (entry.atlas or entry.icon) ~= nil)
		width = math.max(width, line.text:GetStringWidth() + line.inset)
	end
	-- No wider than the line above it: the group sits under the title, long lines wrap.
	local limit = math.max(above:GetStringWidth() + LIST_INSET, LIST_MIN_WIDTH)
	width = math.min(math.ceil(width) + 2, limit)
	local height, previous = 0, nil
	for index, entry in ipairs(lines) do
		local line = frame.lines[index]
		local header = type(entry) == "table" and entry.header == true
		line.text:SetWidth(width - line.inset)
		local lineHeight = math.max(line.text:GetStringHeight(), header and 14 or 0)
		line:SetSize(width, lineHeight)
		line:ClearAllPoints()
		local gap = header and index > 1 and 8 or 2 -- a little room above each section
		if previous then
			line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -gap)
		else
			line:SetPoint("TOP", above, "BOTTOM", 0, -8)
		end
		line.onClick = type(entry) == "table" and entry.onClick or nil
		line:EnableMouse(line.onClick ~= nil)
		line:Show()
		height = height + lineHeight + gap
		previous = line
	end
	return height + 10
end

local function Display(spec)
	local style = spec.style == "big" and "big" or "small"
	local frame = table.remove(free[style]) or CreateToastFrame(style)
	frame.heading:SetText(spec.heading or "")
	frame.heading:SetTextColor(unpack(spec.headingColor or UI.ACCENT))
	frame.text:SetFontObject(spec.textFont or (style == "big" and "GameFontNormalHuge" or "GameFontNormalLarge"))
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
	if spec.heading then
		frame.text:SetPoint("TOP", frame.heading, "BOTTOM", shift, style == "big" and -8 or -4)
	else
		frame.text:SetPoint("TOP", frame.inner, "TOP", shift, 0) -- the text is the headline
	end
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

	frame.key = spec.key
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
	if spec.key then
		for _, frame in ipairs(shown) do
			if frame.key == spec.key then
				-- Already up: it stays as if it had just come.
				frame.holdUntil = math.max(frame.holdUntil, GetTime() + (spec.duration or DEFAULTS[frame.style].duration))
				return
			end
		end
		for _, waiting in ipairs(queue) do
			if waiting.key == spec.key then
				return
			end
		end
	end
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
-- ns.arrival.Add{ zone = "Ironforge", title = "|cff..QUESTS (2)|r", icon = file / atlas = name,
--   iconColor = { r, g, b }?, names = { ... }, onClick = function,
--   order = number (lower first; quests 1, reminders and to-dos 2) }
-- Shown as the zone's name (large), then the sections as one group centred under it: each its
-- title in small capitals after its icon, and its names under the title, one per line.
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
	local zones, seen, lines, clicks = {}, {}, {}, {}
	for _, part in ipairs(parts) do
		if part.zone and not seen[part.zone] then
			seen[part.zone] = true
			table.insert(zones, part.zone)
		end
		table.insert(lines, { text = part.title, header = true, icon = part.icon, atlas = part.atlas, iconColor = part.iconColor,
			onClick = part.onClick })
		local names = part.names or {}
		for index, name in ipairs(names) do
			if index > MAX_ARRIVAL_NAMES then
				table.insert(lines, { text = string.format("|cff999999and %d more|r", #names - MAX_ARRIVAL_NAMES), onClick = part.onClick })
				break
			end
			table.insert(lines, { text = name, onClick = part.onClick })
		end
		table.insert(clicks, part.onClick)
	end
	toast.Show({
		style = "small",
		key = "arrival:" .. table.concat(zones, ","), -- zoning in and out doesn't show it again
		text = table.concat(zones, " · "), -- the headline
		textFont = "GameFontNormalHuge",
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
