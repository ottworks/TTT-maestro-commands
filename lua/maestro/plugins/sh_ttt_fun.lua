if GAMEMODE_NAME ~= "terrortown" then return end -- todo: test

-- credits
maestro.command("credits", {"player:target", "number:credits"}, function(caller, targets, credits)
	if #targets == 0 then return true, "Query matched no players." end

	credits = tonumber(credits)
	if not credits then return true, "Invalid number of credits specified." end

	for k, v in pairs(targets) do
		v:AddCredits(credits)
	end

	return true, "gave %2 credits to %1"
end, [[Gives a player an amount of credits.]])
-- end credits
