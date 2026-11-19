-- Changelog tooling for releases (run from the repo root, with luajit or lua):
--   lua tools/changelog.lua count                    entries in the Unreleased block
--   lua tools/changelog.lua released [file]          entries in released versions (of file, e.g.
--                                                    the last release's copy, to catch additions)
--   lua tools/changelog.lua release <version> <date> turn the Unreleased block into that version
--   lua tools/changelog.lua markdown <version>       release notes for a version (or Unreleased),
--                                                    written to CHANGELOG.md by `just release`

local FILE = "Changelog.lua"

local function Load(file)
	local ns = {}
	assert(loadfile(file or FILE))("NraKit", ns)
	return ns.changelog
end

local function Find(changelog, version)
	for _, release in ipairs(changelog) do
		if release.version == version then
			return release
		end
	end
end

local command = arg[1]

if command == "count" then
	local release = Find(Load(), "Unreleased")
	print(release and #release.entries or 0)

elseif command == "released" then
	local total = 0
	for _, release in ipairs(Load(arg[2])) do
		if release.version ~= "Unreleased" then
			total = total + #release.entries
		end
	end
	print(total)

elseif command == "release" then
	local version, date = assert(arg[2], "version?"), assert(arg[3], "date?")
	local release = Find(Load(), "Unreleased")
	if not release or #release.entries == 0 then
		io.stderr:write("Changelog.lua has nothing under Unreleased.\n")
		os.exit(1)
	end
	local handle = assert(io.open(FILE))
	local text = handle:read("*a")
	handle:close()
	local replaced, count = text:gsub('{ version = "Unreleased", entries = {',
		string.format('{ version = "%s", date = "%s", entries = {', version, date), 1)
	assert(count == 1, "Unreleased block not found in " .. FILE)
	handle = assert(io.open(FILE, "w"))
	handle:write(replaced)
	handle:close()

elseif command == "markdown" then
	local version = assert(arg[2], "version?")
	local release = Find(Load(), version)
	if not release then
		io.stderr:write("No " .. version .. " in Changelog.lua.\n")
		os.exit(1)
	end
	print("# NraKit " .. version)
	for _, kind in ipairs({ { "new", "New" }, { "improved", "Improved" }, { "fixed", "Fixed" } }) do
		local lines = {}
		for _, entry in ipairs(release.entries) do
			if entry[1] == kind[1] then
				table.insert(lines, "- " .. entry[2])
			end
		end
		if #lines > 0 then
			print("")
			print("### " .. kind[2])
			print(table.concat(lines, "\n"))
		end
	end
	print("")
	print("Type /nra new in game to see what's new in every version.")

else
	io.stderr:write("usage: lua tools/changelog.lua count | released [file] | release <version> <date> | markdown <version>\n")
	os.exit(2)
end
