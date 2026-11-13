local _, ns = ...

-- /leave with no argument leaves your group (party, raid or instance group), and
-- /leavegroup does the same. Blizzard's /leave leaves a chat channel ("/leave 2")
-- and does nothing without an argument, so that case is free. We post-hook
-- Blizzard's handler instead of replacing it, so nothing of theirs is tainted.
-- C_PartyInfo.LeaveParty isn't protected; Blizzard's Leave Group menu entry uses it too.

local module = {
	key = "leaveGroup",
	section = "Group",
	name = "/leave leaves your group",
	description = "Type /leave (with nothing after it) or /leavegroup to leave your party, raid or instance group. /leave <channel> still leaves a chat channel.",
	default = false,
}

local function LeaveGroup()
	if not ns:IsModuleEnabled(module.key) then
		return
	end
	local instance = LE_PARTY_CATEGORY_INSTANCE
	if instance and IsInGroup(instance) then
		C_PartyInfo.LeaveParty(instance)
	elseif IsInGroup() then
		C_PartyInfo.LeaveParty()
	else
		ns:Print("You're not in a group.")
	end
end

function module:OnInitialize()
	if SlashCmdList.LEAVE then
		hooksecurefunc(SlashCmdList, "LEAVE", function(msg)
			if strtrim(msg or "") == "" then
				LeaveGroup()
			end
		end)
	end

	SLASH_NRAKIT_LEAVEGROUP1 = "/leavegroup"
	SlashCmdList.NRAKIT_LEAVEGROUP = function()
		if ns:IsModuleEnabled(module.key) then
			LeaveGroup()
		else
			ns:Print("/leavegroup is part of \"" .. module.name .. "\", which is turned off. Turn it on in /nra.")
		end
	end
end

ns:RegisterModule(module)
