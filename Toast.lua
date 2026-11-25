local _, ns = ...

-- Toasts: NraKit's messages in the middle of the screen, one look for every feature.
--
-- ns.toast.Show{
--   style = "big" | "small",  big: a heading, a large line with an icon and a detail line, with a
--                             pop (Farm goals' "Goal complete"); small: quieter and lower (a
--                             milestone, "3 quests to turn in here")
--   heading, text, detail,    the lines (detail is optional)
--   icon = texture / atlas =, shown left of the text (optional)
--   headingColor = { r, g, b },
--   duration = seconds,       before it fades (default 6 big, 3 small); the mouse on it keeps it up
--   size = scale,             (default 1)
--   onClick = function,       makes it clickable (it closes when clicked); otherwise clicks go through
--   skipIfBusy = true,        drop it instead of waiting while another toast is up
-- }
-- A big toast replaces whatever is showing; a small one waits for the toast in front of it
-- (a few at most), so nothing is talked over.

local UI = ns.UI
local toast = {}
ns.toast = toast

local FADE = 1
local MAX_QUEUE = 3
local DEFAULTS = { big = { duration = 6, y = 260 }, small = { duration = 3, y = 200 } }

local frames = {}
local queue = {}
local ShowNext

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

local function OnUpdate(self)
	local now = GetTime()
	if self:IsMouseOver() and now - self.shownAt > 0.35 then
		self.holdUntil = math.max(self.holdUntil, now + 1) -- the mouse on it keeps it up
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
	frame:SetPoint("CENTER", 0, DEFAULTS[style].y)
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
	frame:HookScript("OnHide", function()
		ShowNext()
	end)
	frames[style] = frame
	return frame
end

local function Display(spec)
	local style = spec.style == "big" and "big" or "small"
	local frame = frames[style] or CreateToastFrame(style)
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

	frame.onClick = spec.onClick
	frame:EnableMouse(spec.onClick ~= nil)
	frame.size = spec.size or 1
	frame.shownAt = GetTime()
	frame.holdUntil = frame.shownAt + (spec.duration or DEFAULTS[style].duration)
	frame:SetAlpha(1)
	frame:Show()
end

local function Busy()
	return (frames.big and frames.big:IsShown()) or (frames.small and frames.small:IsShown())
end

function ShowNext()
	if not Busy() and #queue > 0 then
		Display(table.remove(queue, 1))
	end
end

function toast.Show(spec)
	if spec.style == "big" then
		Display(spec) -- first, so a waiting small toast doesn't take the small one's place
		if frames.small and frames.small:IsShown() then
			frames.small:Hide() -- a big one goes in front; the small one doesn't come back
		end
		return
	end
	if not Busy() then
		Display(spec)
	elseif not spec.skipIfBusy and #queue < MAX_QUEUE then
		table.insert(queue, spec)
	end
end

-- Whether a toast is showing now (tests, and features that want to know).
function toast.IsShowing(style)
	return frames[style] ~= nil and frames[style]:IsShown()
end

------------------------------------------------------------------------------
-- Arrival: one small message when you enter a zone, with what features have for you there
-- (quests to turn in, to-dos). Features add their part as they notice; parts within a moment
-- of each other share one message. Dropped in combat (stale by the end of the fight).
--
-- ns.arrival.Add{ zone = "Ironforge", text = "2 to-dos", names = { ... }, onClick = function?,
--   atlas = icon?, order = number (lower first; quests 1, to-dos 2) }
------------------------------------------------------------------------------

local arrival = {}
ns.arrival = arrival
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
	local zones, seen, texts, names, onClick, atlas = {}, {}, {}, {}, nil, nil
	for _, part in ipairs(parts) do
		if part.zone and not seen[part.zone] then
			seen[part.zone] = true
			table.insert(zones, part.zone)
		end
		table.insert(texts, part.text)
		for _, name in ipairs(part.names or {}) do
			table.insert(names, name)
		end
		onClick = onClick or part.onClick
		atlas = atlas or part.atlas
	end
	toast.Show({
		style = "small",
		heading = table.concat(zones, " · "):upper(),
		text = table.concat(texts, "  ·  "),
		atlas = atlas,
		detail = #names > 0 and table.concat(names, ", ") or nil,
		duration = 6,
		onClick = onClick,
	})
end

function arrival.Add(part)
	table.insert(pending, part)
	if #pending == 1 then
		C_Timer.After(0.3, arrival.Flush)
	end
end
