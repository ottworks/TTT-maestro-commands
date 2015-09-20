if GAMEMODE_NAME ~= "terrortown" then return end -- todo: test

-- voteslaynr
maestro.command("voteslaynr", {"player:target", "string:reason(optional)"}, function(caller, targets, reason)
	if #targets < 1 then
		return true, "Query matched no players."
	elseif #targets > 1 then
		return true, "Query matched multiple players."
	end

	local target = targets[1]
	local title = "\"Slay " .. target:GetName() .. " next round?" .. (reason and (" (" .. reason .. ")\"") or "\"")

	maestro.vote(title, {"Yes, slay this player.", "No, do not slay this player."}, function(option, voted, total)
		if option then
			maestro.chat(nil, color_white, "Option \"", option, "\" has won. (", voted, "/", total, ")")
			if option == "Yes, slay this player." then
				maestro.chat(nil, color_white, "Player ", target, " will be slain.")

				local current_slays = target:GetPData("slaynr_slays", 0)
				target:SetPData("slaynr_slays", current_slays + 1)
				target:SetPData("slaynr_lastreason", reason)
			else
				maestro.chat(nil, color_white, "No action will be taken.")
			end
		else
			maestro.chat(nil, color_white, "No options have won.")
		end
	end)

	return false, "started a vote to slay %1 next round" .. (reason and " (\"%2\")" or "")
end, [[Starts a vote to slay a player next round.]])
-- end voteslaynr

-- votefspec
maestro.command("votefspec", {"player:target", "string:reason(optional)"}, function(caller, targets, reason)
	if #targets < 1 then
		return true, "Query matched no players."
	elseif #targets > 1 then
		return true, "Query matched multiple players."
	end

	local target = targets[1]
	local title = "\"Force " .. target:GetName() .. " to spectate?" .. (reason and (" (" .. reason .. ")\"") or "\"")

	maestro.vote(title, {"Yes, force this player to spectate.", "No, do not force this player to spectate."}, function(option, voted, total)
		if option then
			maestro.chat(nil, color_white, "Option \"", option, "\" has won. (", voted, "/", total, ")")
			if option == "Yes, force this player to spectate." then
				maestro.chat(nil, color_white, "Player ", target, " will be forced to spectate.")

				target:ConCommand("ttt_spectator_mode 1")
				target:ConCommand("ttt_cl_idlepopup")
			else
				maestro.chat(nil, color_white, "No action will be taken.")
			end
		else
			maestro.chat(nil, color_white, "No options have won.")
		end
	end)

	return false, "started a vote to force %1 to spectate mode" .. (reason and " (\"%2\")" or "")
end, [[Starts a vote to force a player to spectate.]])
-- end votefspec
