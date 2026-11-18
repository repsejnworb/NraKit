-- Runs one test file against NraKit in the stand-in client (tests/wow.lua).
--   lua tests/run.lua tests/farm_goals_test.lua
-- A test file returns { enable = { module keys }, run = function(t, ns, wow) ... end }.
-- The addon is loaded file by file in NraKit.toc order, then ADDON_LOADED and
-- PLAYER_LOGIN are fired, like logging in. Exits non-zero if anything failed.

local testFile = assert(arg[1], "usage: lua tests/run.lua tests/<name>_test.lua")
local out = print -- wow.install() replaces print to capture the addon's chat lines
local wow = dofile("tests/wow.lua")
wow.install()

local spec = dofile(testFile)
NraKitDB = {}
for _, key in ipairs(spec.enable or {}) do
	NraKitDB[key] = true
end

-- Load the addon like the client does.
local ns = {}
for line in io.lines("NraKit.toc") do
	line = line:gsub("\r", "")
	if line ~= "" and not line:match("^#") then
		local path = line:gsub("\\", "/")
		local chunk = assert(loadfile(path))
		chunk("NraKit", ns)
	end
end
wow.fire("ADDON_LOADED", "NraKit")
wow.fire("PLAYER_LOGIN")

local passed, failed = 0, 0
local current

local function Fail(message)
	error({ testFailure = message }, 2)
end

local t = {}

function t.ok(value, message)
	if not value then
		Fail(message or "expected a true value")
	end
end

function t.equal(actual, expected, message)
	if actual ~= expected then
		Fail(string.format("%s: expected %s, got %s", message or "values differ", tostring(expected), tostring(actual)))
	end
end

-- Fails if the addon reported errors (module start-up uses geterrorhandler) since the last check.
function t.noErrors(message)
	if #wow.errors > 0 then
		local errors = table.concat(wow.errors, "\n    ")
		wow.errors = {}
		Fail((message or "addon errors") .. ":\n    " .. errors)
	end
end

function t.test(name, fn)
	current = name
	local ok, err = xpcall(fn, function(e)
		if type(e) == "table" and e.testFailure then
			return e.testFailure
		end
		return debug.traceback(tostring(e), 2)
	end)
	if ok and #wow.errors > 0 then
		ok, err = false, "addon errors:\n    " .. table.concat(wow.errors, "\n    ")
		wow.errors = {}
	end
	if ok then
		passed = passed + 1
		out("  ok    " .. name)
	else
		failed = failed + 1
		out("  FAIL  " .. name .. "\n        " .. tostring(err):gsub("\n", "\n        "))
	end
end

out(testFile)
t.test("addon loads and starts without errors", function()
	t.noErrors("start-up errors")
end)
spec.run(t, ns, wow)
out(string.format("  %d passed, %d failed", passed, failed))
os.exit(failed == 0)
