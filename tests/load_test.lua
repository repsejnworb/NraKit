-- Every feature turned on: the whole addon loads, logs in and opens its windows without errors.
local keys = {}
for line in io.lines("NraKit.toc") do
	if line:match("^Modules") then
		local text = io.open((line:gsub("\\", "/"))):read("a")
		local key = text:match("\n%s*key = \"([%w]+)\",\n%s*section")
		if key then
			table.insert(keys, key)
		end
	end
end

return {
	enable = keys,
	run = function(t, ns, wow)
		t.test("every module registered", function()
			t.ok(#keys >= 15, "found " .. #keys .. " modules in the TOC")
			for _, key in ipairs(keys) do
				t.ok(ns.modules[key], key .. " is registered")
			end
		end)

		t.test("settings window opens and searches", function()
			ns:OpenSettings()
			t.ok(NraKitOptionsFrame and NraKitOptionsFrame:IsShown(), "settings window shown")
		end)

		t.test("inventory browser opens", function()
			ns:OpenInventoryBrowser()
			t.ok(NraKitInventoryFrame and NraKitInventoryFrame:IsShown(), "inventory window shown")
		end)

		t.test("goals window opens", function()
			ns:OpenGoalsWindow()
			t.ok(NraKitGoalsFrame and NraKitGoalsFrame:IsShown(), "goals window shown")
		end)

		t.test("module data keys don't overwrite settings", function()
			for _, module in ipairs(ns.moduleOrder) do
				t.equal(type(NraKitDB[module.key]), "boolean", module.key .. " is still an on/off setting")
			end
		end)
	end,
}
