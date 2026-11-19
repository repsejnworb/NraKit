local _, ns = ...

-- /nra preview <name> (also /nra test): shows a feature's on-screen message or bar with made-up
-- content, to see how it looks (and where) without waiting for it to happen. Plain
-- /nra preview lists them. Features add theirs with ns:RegisterPreview; previews work
-- whether the feature is on or off, and change nothing.

local previews, order = {}, {}

-- name: one word for the command; description: what it shows; show: function() shows it.
function ns:RegisterPreview(name, description, show)
	name = name:lower()
	if not previews[name] then
		table.insert(order, name)
		table.sort(order)
	end
	previews[name] = { name = name, description = description, show = show }
end

local function List()
	ns:Print("Previews (/nra preview <name>):")
	for _, name in ipairs(order) do
		print(string.format("  |cffffd100%s|r  %s", name, previews[name].description))
	end
end

local function OnSlashCommand(input)
	local name = (input or ""):match("^(%S*)"):lower()
	if name == "" then
		List()
		return
	end
	local preview = previews[name]
	if not preview then
		ns:Print(string.format("No preview called \"%s\".", name))
		List()
		return
	end
	preview.show()
end

local help = {
	summary = "Preview on-screen messages and bars (goal complete, quest reminders, alerts...)",
	usage = {
		"/nra preview - list what can be previewed (also /nra test)",
		"/nra preview <name> - show it with made-up content, e.g. /nra preview goal",
	},
}
ns:RegisterSlashCommand("preview", OnSlashCommand, help)
ns:RegisterSlashCommand("test", OnSlashCommand, help)

-- Made-up content for previews.
ns.previewSample = {
	itemID = 4306, -- Silk Cloth
	itemName = "Silk Cloth",
	itemIcon = 132905,
}
