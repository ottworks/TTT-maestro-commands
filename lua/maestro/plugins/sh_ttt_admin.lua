if GAMEMODE_NAME ~= "terrortown" then return end -- todo: test

-- slaynr
maestro.command("slaynr", {"player:target", "number:rounds(optional)", "string:reason(optional)", "boolean:shouldRemove(optional)"}, function(caller, targets, rounds, reason, shouldRemove)
	if #targets == 0 then return true, "Query matched no players." end

	rounds = rounds or 1
	if not tonumber(rounds) then return true, "Invalid number of rounds specified." end

	reason = reason or ""

	shouldRemove = shouldRemove or false

	for _, target in pairs(targets) do
		local old_slays = tonumber(target:GetPData("slaynr_slays", 0))
		local new_slays = math.max(old_slays + (shouldRemove and -rounds or rounds), 0)

		if new_slays == 0 then
			target:RemovePData("slaynr_slays")
			target:RemovePData("slaynr_lastreason")
		else
			target:SetPData("slaynr_slays", new_slays)
			target:SetPData("slaynr_lastreason", reason)
		end
	end

	return true, (shouldRemove and "removed" or "added") .. " %1 rounds of slaying " .. (shouldRemove and "from" or "to") .. " %1" .. (reason and (" for " .. reason) or "")
end, [[Slays a player for a number of rounds.]])

hook.Add("PlayerSpawn", "ttt_maestro_commands_slaynr_inform" , function(ply)
	local slays_left = tonumber(ply:GetPData("slaynr_slays", 0))
	local reason = ply:GetPData("slaynr_lastreason", false)

	if ply:Alive() and slays_left > 0 then
		local msg = "You will be slain this round" .. (slays_left > 1 and (" and " .. (slays_left - 1) " round(s) after the current round") or "") .. (reason and ("for \"" .. reason .. "\".") or ".")

		maestro.chat(ply, msg)
	end
end)

hook.Add("TTTBeginRound", "ttt_maestro_commands_slaynr", function()
	local slain_players = {}

	for k, v in pairs(player.GetAll()) do
		local slays_left = tonumber(target:GetPData("slaynr_slays", 0))
		if slays_left == 0 then return end

		if (not v:Alive()) or v:IsSpec() then return end

		v:StripWeapons()

		-- todo: test if all these timers are still necessary
		timer.Create("slaycheck" .. v:SteamID(), 0.1, 0, function() -- workaround for issue with tommys damage log
			v:Kill()

			GAMEMODE:PlayerSilentDeath(v)

			local corpse = v.server_ragdoll or v:GetRagdollEntity()
			if IsValid(corpse) then
				v:SetNWBool("body_found", true)
				SendFullStateUpdate()

				if string.find(corpse:GetModel(), "zm_", 6, true) or corpse.player_ragdoll then
					corpse:Remove()
				end
			end

			v:SetTeam(TEAM_SPEC)
			if v:IsSpec() then
				timer.Destroy("slaycheck" .. v:SteamID())
				return
			end
		end)

		timer.Simple(0.5, function() -- have to wait for gamemode before doing this
			if v:GetRole() == ROLE_TRAITOR then
				SendConfirmedTraitors(GetInnocentFilter(false)) -- Update innocent's list of traitors.
				SCORE:HandleBodyFound(v, v)
			end
		end)

		slays_left = slays_left - 1
		if slays_left == 0 then
			v:RemovePData("slaynr_slays")
			v:RemovePData("slaynr_lastreason")
		else
			v:SetPData("slaynr_slays", slays_left)
		end

		slain_players[#slain_players + 1] = v
	end

	maestro.chat(nil, table.concat(slain_players, ", ") .. (#slain_players == 1 and "was" or "were") .. " slain.")
end)

hook.Add("PlayerDisconnected", "ttt_maestro_commands_slaynr_disconnected" , function(ply)
	local slays_left = tonumber(ply:GetPData("slaynr_slays", 0))

	if slays_left > 0 then
		maestro.chat(nil, ply:GetName() .. "(" .. ply:SteamID() .. ") left the server with " .. slays_left .. " slays remaining.")
	end
end)
-- end slaynr

-- changerole
local str_to_role = {
	innocent = ROLE_INNOCENT,
	i = ROLE_INNOCENT,
	traitor = ROLE_TRAITOR,
	t = ROLE_TRAITOR,
	detective = ROLE_DETECTIVE,
	d = ROLE_DETECTIVE,
	unmark = false,
}

local ttt_credits_starting = GetConVar("ttt_credits_starting")

maestro.command("changerole", {"player:target", "string:role"}, function(caller, targets, rolestr)
	if #targets == 0 then return true, "Query matched no players." end

	role = str_to_role[rolestr]
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

		local r = target:GetRole()
		local weps = GetLoadoutWeapons(r)
		if weps then
			for _, cls in pairs(weps) do
				if not ply:HasWeapon(cls) then
					target:Give(cls)
				end
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

		maestro.chat(target, caller:Nick() .. " has set your role to " .. target:GetRoleString())
	end

	-- Notify admins
	local admins = {}
	for k, v in pairs(player.GetAll()) do if v:IsAdmin() then admins[#admins + 1] = v end end
	local targetsstr = ""
	for k, v in pairs(targets) do targetsstr = targetsstr .. v:GetName() .. ", " end
	targetsstr = string.sub(targetsstr, 1, -3)
	maestro.chat(admins, caller:GetName() .. " set the role of " .. targetsstr .. " to " .. rolestr .. ".")

	return true
end, [[Sets a player's role.]])

local rolenr = {}
maestro.command("changerolenr", {"player:target", "string:role"}, function(caller, targets, rolestr)
	if #targets == 0 then return true, "Query matched no players." end

	role = str_to_role[rolestr]
	if role == nil then return true, "Invalid role specified (use 'traitor', 'innocent', 'detective', or 'unmark')" end

	for _, target in pairs(targets) do
		rolenr[target] = role
	end

	-- Notify admins
	local admins = {}
	for k, v in pairs(player.GetAll()) do if v:IsAdmin() then admins[#admins + 1] = v end end
	local targetsstr = ""
	for k, v in pairs(targets) do targetsstr = targetsstr .. v:GetName() .. ", " end
	targetsstr = string.sub(targetsstr, 1, -3)
	maestro.chat(admins, caller:GetName() .. " marked " .. targetsstr .. " to be " .. rolestr .. " next round.")

	return true -- no message as we want this hidden to non-admins
end, [[Sets a player's role next round.]])

hook.Add("TTTBeginRound", "ttt_maestro_commands_changerolenr", function()
	for ply, role in pairs(rolenr) do
		if not (role and IsValid(ply)) then return end
		ply:SetRole(role)
		if role == ROLE_TRAITOR or role == ROLE_DETECTIVE then
			ply:SetCredits(ttt_credits_starting:GetInt())
		end
		maestro.chat(ply, "You have been made "..ply:GetRoleString().." by an admin this round.")
	end
	rolenr = {}
end)
-- end changerole

-- respawn & respawntp
local function respawn(ply)
	local corpse = ply.server_ragdoll or ply:GetRagdollEntity()
	if IsValid(corpse) then corpse_remove(corpse) end

	ply:SpawnForRound(true)
	ply:SetCredits((v:GetRole() == ROLE_INNOCENT) and 0 or ttt_credits_starting:GetInt())

	maestro.chat(ply, "You have been respawned.")
end

maestro.command("respawn", {"player:target"}, function(caller, targets)
	if #targets == 0 then return true, "Query matched no players." end

	if GetRoundState() ~= ROUND_WAIT then return true, "Waiting for players!" end

	for _, target in pairs(targets) do
		if target:Alive() then continue end -- should we tell the caller when we skip someone?

		if not ply:IsSpec() then
			respawn(target)
		else
			target:ConCommand("ttt_spectator_mode 0")

			-- wait for the spectator exiting to finish
			timer.Simple(0.1, function()
				respawn(target)
			end)
		end
	end

	return true, "respawned %1"
end, [[Respawns a player.]])

local function respawntp(caller, target)
	local tr = {
		start = caller:GetPos() + Vector(0, 0, 32), -- Move them up a bit so they can travel across the ground
		endpos = caller:GetPos() + caller:EyeAngles():Forward() * 16384,
		filter = {target, caller},
	}
	tr = util.TraceEntity(tr, target)

	local pos = tr.HitPos

	local corpse = target.server_ragdoll or target:GetRagdollEntity()
	if IsValid(corpse) then corpse_remove(corpse) end

	target:SpawnForRound(true)
	ply:SetCredits((v:GetRole() == ROLE_INNOCENT) and 0 or ttt_credits_starting:GetInt())

	target:SetPos(pos)

	maestro.chat(target, "You have been respawned.")
end

maestro.command("respawntp", {"player:target"}, function(caller, targets)
	if #targets == 0 then return true, "Query matched no players." end
	if not IsValid(caller) then return true, "The server console cannot respawntp as it is not in the world. Use respawn." end

	if GetRoundState() ~= ROUND_WAIT then return true, "Waiting for players!" end

	for _, target in pairs(targets) do
		if target:Alive() then continue end -- should we tell the caller when we skip someone?

		if not ply:IsSpec() then
			respawntp(target)
		else
			target:ConCommand("ttt_spectator_mode 0")

			-- wait for the spectator exiting to finish
			timer.Simple(0.1, function()
				respawntp(target)
			end)
		end
	end

	return true, "respawned and teleported %1"
end, [[Respawns and teleports a player.]])
-- end respawn & respawntp

-- karma
maestro.command("karma", {"player:target", "number:amount"}, function(caller, targets, amount)
	if #targets == 0 then return true, "Query matched no players." end

	for _, target in pairs(targets) do
		target:SetBaseKarma(amount)
		target:SetLiveKarma(amount)
	end

	return true, "set the karma of %1 to %2"
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

	return true, "forced %1 " .. (shouldUnspec and "out of spectate mode" or "to spectate")
end, [[Forces a player to spectator.]])
-- end fspec

-- identify
maestro.command("identify", {"player:target", "boolean:shouldUnidentify(optional)"}, function(caller, targets, shouldUnidentify)
	if #targets == 0 then return true, "Query matched no players." end

	shouldUnidentify = shouldUnidentify or false

	for _, target in pairs(targets) do
		local corpse = ply.server_ragdoll or ply:GetRagdollEntity()
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

	if not shouldUnidentify then
		return true, "forced the body of %1 to be identified"
	else
		return true
	end
end, [[Identifies a player's body.]])
-- end identify

-- roundrestart
local roundrestart = concommand.GetTable()["ttt_roundrestart"] -- why isn't there a global function? the world may never know.
maestro.command("roundrestart", {}, function(caller)
	roundrestart()

	return true, "restarted the round"
end, [[Restarts the round.]])
-- end roundrestart
