-- slaynr
maestro.command("slaynr", {"player:target", "number:rounds(optional)", "string:reason(optional)", "boolean:shouldRemove(optional)"}, function(caller, targets, rounds, reason, shouldRemove)
	if #targets == 0 then return true, "Query matched no players." end
	if #targets > 1 then return true, "Query matched more than one player." end

	rounds = rounds or 1
	rounds = tonumber(rounds)
	if not rounds then return true, "Invalid number of rounds specified." end

	reason = reason or ""

	shouldRemove = shouldRemove or false

	local target = targets[1]
	local old_slays = tonumber(target:GetPData("slaynr_slays", 0))
	local new_slays = math.max(old_slays + (shouldRemove and -rounds or rounds), 0)

	if new_slays == 0 then
		target:RemovePData("slaynr_slays")
		target:RemovePData("slaynr_lastreason")
	else
		target:SetPData("slaynr_slays", new_slays)
		target:SetPData("slaynr_lastreason", reason)
	end

	return false, (shouldRemove and "removed" or "added") .. " %2 rounds of slaying " .. (shouldRemove and "from" or "to") .. " %1" .. (reason and (" (\"%3\")") or "") .. "; New total: " .. new_slays
end, [[Slays a player for a number of rounds.]])

hook.Add("PlayerSpawn", "ttt_maestro_commands_slaynr_inform" , function(ply)
	local slays_left = tonumber(ply:GetPData("slaynr_slays", 0))
	local reason = ply:GetPData("slaynr_lastreason", false)

	if ply:Alive() and slays_left > 0 and SERVER then
		local msg = {color_white, "You will be slain this round"}
		if slays_left > 1 then
			msg[#msg + 1] = " and "
			msg[#msg + 1] = maestro.blue
			msg[#msg + 1] = slays_left - 1
			msg[#msg + 1] = color_white
			msg[#msg + 1] = " round(s) after the current round"
		end
		if reason then
			msg[#msg + 1] = " (\""
			msg[#msg + 1] = maestro.blue
			msg[#msg + 1] = reason
			msg[#msg + 1] = color_white
			msg[#msg + 1] = "\")"
		end
		maestro.chat(ply, unpack(msg))
	end
end)

hook.Add("TTTBeginRound", "ttt_maestro_commands_slaynr", function()
	local slain_players = {}

	for _, ply in pairs(player.GetAll()) do
		local slays_left = tonumber(ply:GetPData("slaynr_slays", 0))
		if slays_left == 0 then continue end

		if (not ply:Alive()) or ply:IsSpec() then continue end

		ply:StripWeapons()

		-- todo: test if all these timers are still necessary
		timer.Create("slaycheck" .. ply:SteamID(), 0.1, 0, function() -- workaround for issue with tommys damage log
			ply:Kill()

			GAMEMODE:PlayerSilentDeath(ply)

			local corpse = ply.server_ragdoll or ply:GetRagdollEntity()
			if IsValid(corpse) then
				ply:SetNWBool("body_found", true)
				SendFullStateUpdate()

				if string.find(corpse:GetModel(), "zm_", 6, true) or corpse.player_ragdoll then
					corpse:Remove()
				end
			end

			ply:SetTeam(TEAM_SPEC)
			if ply:IsSpec() then
				timer.Destroy("slaycheck" .. ply:SteamID())
				return
			end
		end)

		timer.Simple(0.5, function() -- have to wait for gamemode before doing this
			if ply:GetRole() == ROLE_TRAITOR then
				SendConfirmedTraitors(GetInnocentFilter(false)) -- Update innocent's list of traitors.
				SCORE:HandleBodyFound(ply, ply)
			end
		end)

		slays_left = slays_left - 1
		if slays_left == 0 then
			ply:RemovePData("slaynr_slays")
			ply:RemovePData("slaynr_lastreason")
		else
			ply:SetPData("slaynr_slays", slays_left)
		end

		slain_players[#slain_players + 1] = ply
	end

	-- i know this is dumb
	local slain_players_n = {}
	for k, v in pairs(slain_players) do
		local l = #slain_players_n
		slain_players_n[l + 1] = v
		if k == #slain_players then continue end
		slain_players_n[l + 2] = color_white
		slain_players_n[l + 3] = ", "
	end
	if #slain_players > 0 then slain_players_n[#slain_players_n - 1] = (#slain_players > 2 and ", and " or " and ") end
	slain_players_n[#slain_players_n + 1] = (#slain_players == 1 and " was" or " were") .. " slain."

	if SERVER then maestro.chat(nil, unpack(slain_players_n)) end
end)

hook.Add("PlayerDisconnected", "ttt_maestro_commands_slaynr_disconnected" , function(ply)
	local slays_left = tonumber(ply:GetPData("slaynr_slays", 0))

	if slays_left > 0 and SERVER then
		maestro.chat(nil, maestro.blue, ply:GetName(), color_white, " (", maestro.blue, ply:SteamID(), color_white, ") left the server with ", maestro.blue, slays_left, color_white, " slays remaining.")
	end
end)
-- end slaynr

-- changerole
local str_to_role
hook.Add("PostGamemodeLoaded", "ttt_maestro_commands_changerole_strtorole", function()
	str_to_role = {
		i = ROLE_INNOCENT,
		t = ROLE_TRAITOR,
		d = ROLE_DETECTIVE,
		innocent = ROLE_INNOCENT,
		traitor = ROLE_TRAITOR,
		detective = ROLE_DETECTIVE,
		unmark = false,
	}
end)

local ttt_credits_starting = GetConVar("ttt_credits_starting")

maestro.command("changerole", {"player:target", "string:role"}, function(caller, targets, rolestr)
	if #targets == 0 then return true, "Query matched no players." end

	local role = str_to_role[rolestr]
	if not role then return true, "Invalid role specified (use 'traitor', 'innocent', or 'detective')" end
	if GetRoundState() ~= ROUND_ACTIVE then return true, "The round isn't active!" end

	for _, target in pairs(targets) do
		if not target:Alive() then continue end -- should we tell the caller when we skip someone?
		if target:GetRole() == role then continue end

		target:ResetEquipment()

		-- Strip their loadout weapons
		for _, wep in pairs(target:GetWeapons()) do
			if wep.InLoadoutFor and wep.InLoadoutFor[target:GetClass()] then
				target:StripWeapon(wep)
			end
		end

		target:SetRole(role)
		target:SetCredits(ttt_credits_starting:GetInt())
		SendFullStateUpdate()

		for _, wep in pairs(weapons.GetList()) do
			if wep.InLoadoutFor and wep.InLoadoutFor[r] and not target:HasWeapon(wep) then
				target:Give(wep)
			end
		end
		local items = EquipmentItems[r]
		if items then
			for _, item in pairs(items) do
				if item.loadout and item.id then
					target:GiveEquipmentItem(item.id)
				end
			end
		end

		if SERVER then maestro.chat(target, caller, color_white, " has set your role to ", maestro.blue, target:GetRoleString()) end
	end

	return false, "set the role of %1 to %2"
end, [[Sets a player's role.]])

local rolenr = {}
maestro.command("changerolenr", {"player:target", "string:role"}, function(caller, targets, rolestr)
	if #targets == 0 then return true, "Query matched no players." end

	local role = str_to_role[rolestr]
	if role == nil then return true, "Invalid role specified (use 'traitor', 'innocent', 'detective', or 'unmark')" end

	for _, target in pairs(targets) do
		rolenr[target] = role
	end

	return false, "marked %1 to be %2 next round"
end, [[Sets a player's role next round.]])

hook.Add("TTTBeginRound", "ttt_maestro_commands_changerolenr", function()
	for ply, role in pairs(rolenr) do
		if not (role and IsValid(ply)) then return end
		ply:SetRole(role)
		if role == ROLE_TRAITOR or role == ROLE_DETECTIVE then
			ply:SetCredits(ttt_credits_starting:GetInt())
		end
		if SERVER then maestro.chat(ply, color_white, "You have been made ", maestro.blue, ply:GetRoleString(), color_white, " by an admin this round.") end
	end
	rolenr = {}
end)
-- end changerole

-- respawn & respawntp
local function respawn(ply)
	local corpse = ply.server_ragdoll or ply:GetRagdollEntity()
	if IsValid(corpse) then
		CORPSE.SetFound(corpse, false)
		ply:SetNWBool("body_found", false)
		corpse:Remove()
		SendFullStateUpdate()
	end

	ply:SpawnForRound(true)
	ply:SetCredits((ply:GetRole() == ROLE_INNOCENT) and 0 or ttt_credits_starting:GetInt())

	if SERVER then maestro.chat(ply, "You have been respawned.") end
end

maestro.command("respawn", {"player:target"}, function(caller, targets)
	if #targets == 0 then return true, "Query matched no players." end

	if GetRoundState() == ROUND_WAIT then return true, "Waiting for players!" end

	for _, target in pairs(targets) do
		if target:Alive() then continue end -- should we tell the caller when we skip someone?

		if not target:IsSpec() then
			respawn(target)
		else
			target:ConCommand("ttt_spectator_mode 0")

			-- wait for the spectator exiting to finish
			timer.Simple(0.1, function()
				respawn(target)
			end)
		end
	end

	return false, "respawned %1"
end, [[Respawns a player.]])

local function respawntp(caller, target)
	local tr = {
		start = caller:GetPos() + Vector(0, 0, 32), -- Move them up a bit so they can travel across the ground
		endpos = caller:GetPos() + caller:EyeAngles():Forward() * 16384,
		filter = {target, caller},
	}
	tr = util.TraceLine(tr)

	local pos = tr.HitPos

	local corpse = target.server_ragdoll or target:GetRagdollEntity()
	if IsValid(corpse) then
		CORPSE.SetFound(corpse, false)
		target:SetNWBool("body_found", false)
		corpse:Remove()
		SendFullStateUpdate()
	end

	target:SpawnForRound(true)
	target:SetCredits((target:GetRole() == ROLE_INNOCENT) and 0 or ttt_credits_starting:GetInt())

	target:SetPos(pos)

	if SERVER then maestro.chat(target, "You have been respawned.") end
end

maestro.command("respawntp", {"player:target"}, function(caller, targets)
	if #targets == 0 then return true, "Query matched no players." end
	if not IsValid(caller) then return true, "The server console cannot respawntp as it is not in the world. Use respawn." end

	if GetRoundState() == ROUND_WAIT then return true, "Waiting for players!" end

	for _, target in pairs(targets) do
		if target:Alive() then continue end -- should we tell the caller when we skip someone?

		if not target:IsSpec() then
			respawntp(caller, target)
		else
			target:ConCommand("ttt_spectator_mode 0")

			-- wait for the spectator exiting to finish
			timer.Simple(0.1, function()
				respawntp(caller, target)
			end)
		end
	end

	return false, "respawned and teleported %1"
end, [[Respawns and teleports a player.]])
-- end respawn & respawntp

-- karma
maestro.command("karma", {"player:target", "number:amount"}, function(caller, targets, amount)
	if #targets == 0 then return true, "Query matched no players." end

	for _, target in pairs(targets) do
		target:SetBaseKarma(amount)
		target:SetLiveKarma(amount)
	end

	return false, "set the karma of %1 to %2"
end, [[Sets the karma of a player.]])
-- end karma

-- fspec
maestro.command("fspec", {"player:target", "boolean:shouldUnspec(optional)"}, function(caller, targets, shouldUnspec)
	if #targets == 0 then return true, "Query matched no players." end

	shouldUnspec = shouldUnspec or false

	for _, target in pairs(targets) do
		if not shouldUnspec then
			target:Kill()
			target:SetForceSpec(true)
			target:SetTeam(TEAM_SPEC)
			target:ConCommand("ttt_spectator_mode 1")
			target:ConCommand("ttt_cl_idlepopup")
		else
			target:ConCommand("ttt_spectator_mode 0")
		end
	end

	return false, "forced %1 " .. (shouldUnspec and "out of spectate mode" or "to spectate")
end, [[Forces a player to spectate mode.]])
-- end fspec

-- identify
maestro.command("identify", {"player:target", "boolean:shouldUnidentify(optional)"}, function(caller, targets, shouldUnidentify)
	if #targets == 0 then return true, "Query matched no players." end

	shouldUnidentify = shouldUnidentify or false

	for _, target in pairs(targets) do
		local corpse = target.server_ragdoll or target:GetRagdollEntity()
		if not corpse then continue end -- should we tell the caller when we skip someone?

		if not shouldUnidentify then
			CORPSE.SetFound(corpse, true)
			target:SetNWBool("body_found", true)

			if target:GetRole() == ROLE_TRAITOR then
				-- update innocent's list of traitors
				SendConfirmedTraitors(GetInnocentFilter(false))
				SCORE:HandleBodyFound(caller, target)
			end
		else
			CORPSE.SetFound(corpse, false)
			target:SetNWBool("body_found", false)
			SendFullStateUpdate()
		end
	end

	return false, not shouldUnidentify and "forced the body of %1 to be identified" or nil
end, [[Identifies a player's body.]])
-- end identify

-- roundrestart
maestro.command("roundrestart", {}, function(caller)
	concommand.GetTable()["ttt_roundrestart"]() -- why isn't there a global function? the world may never know.

	return false, "restarted the round"
end, [[Restarts the round.]])
-- end roundrestart
