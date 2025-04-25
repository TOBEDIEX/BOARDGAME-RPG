-- TurnSystem.lua
-- Module for managing turn system and player order
-- Version: 3.3.1 (Added Shuffle Debug Logs)

local TurnSystem = {}
TurnSystem.__index = TurnSystem

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService") -- Added for Heartbeat
local Task = task -- Using task library

-- Constants
local TURN_TIME_LIMIT = 60
local INACTIVITY_WARNING_TIME = 15
local MOVEMENT_SAFETY_DELAY = 0.8
local COMBAT_COOLDOWN_TURNS = 2 -- จำนวนเทิร์นที่ติดคูลดาวน์หลังการต่อสู้

-- Constructor (เหมือนเดิม)
function TurnSystem.new()
	local self = setmetatable({}, TurnSystem)
	self.turnOrder = {}
	self.currentTurnIndex = 0
	self.currentPlayerTurn = nil
	self.isTurnActive = false
	self.turnTimer = nil
	self.turnTimeRemaining = 0
	self.turnStates = {}
	self.skipTurnPlayers = {}
	self.pendingEndTurn = {}
	self.deadPlayers = {}
	self.isPaused = false
	self.pausedTurnState = nil
	self.combatCooldowns = {}
	self.onTurnStart = nil
	self.onTurnEnd = nil
	self.onTurnTimerUpdate = nil
	self.remotes = nil
	return self
end

-- InitializeRemotes (เหมือนเดิม)
function TurnSystem:InitializeRemotes(gameRemotes)
	if not gameRemotes then
		local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
		gameRemotes = remotesFolder:WaitForChild("GameRemotes")
	end
	local function ensureRemoteEvent(parent, name)
		local event = parent:FindFirstChild(name)
		if not event then
			event = Instance.new("RemoteEvent", parent)
			event.Name = name
			print("[TurnSystem] Created RemoteEvent:", name)
		end
		return event
	end
	self.remotes = {
		updateTurn = ensureRemoteEvent(gameRemotes, "UpdateTurn"),
		updateTurnTimer = ensureRemoteEvent(gameRemotes, "UpdateTurnTimer"),
		turnAction = ensureRemoteEvent(gameRemotes, "TurnAction"),
		turnState = ensureRemoteEvent(gameRemotes, "TurnState"),
		combatCooldown = ensureRemoteEvent(gameRemotes, "CombatCooldown")
	}
	if self.remotes.turnAction then
		if self._turnActionConnection then self._turnActionConnection:Disconnect() end
		self._turnActionConnection = self.remotes.turnAction.OnServerEvent:Connect(function(player, actionType, actionData)
			self:HandleTurnAction(player, actionType, actionData)
		end)
	end
	return self.remotes
end

-- SetTurnOrder (เหมือนเดิม)
function TurnSystem:SetTurnOrder(players)
	if type(players) ~= "table" then return false end
	self.turnOrder = players
	self.currentTurnIndex = 0
	self.currentPlayerTurn = nil
	self.isTurnActive = false
	-- Debug log showing the final order being set
	print("[TurnSystem] SetTurnOrder FINAL (UserIds):", table.concat(self.turnOrder, ", "))
	return true
end

-- *** แก้ไข: CreateTurnOrderFromActivePlayers (เพิ่ม Log) ***
function TurnSystem:CreateTurnOrderFromActivePlayers(playerManager)
	local playerOrder = {} -- This will store UserIds

	local sourceDescription = "" -- Describe where the player list came from

	if playerManager and playerManager.GetPlayersSortedByJoinTime then
		sourceDescription = "PlayerManager:GetPlayersSortedByJoinTime"
		local sortedPlayersData = playerManager:GetPlayersSortedByJoinTime()
		print("[TurnSystem DEBUG] CreateTurnOrder: Got data from", sourceDescription)

		if type(sortedPlayersData) ~= "table" then
			warn("[TurnSystem] CreateTurnOrder: GetPlayersSortedByJoinTime did not return a table! Falling back.")
			sourceDescription = "Players:GetPlayers (Fallback 1)"
			for _, player in ipairs(Players:GetPlayers()) do
				if player and player:IsA("Player") then table.insert(playerOrder, player.UserId) end
			end
		else
			for i, pData in ipairs(sortedPlayersData) do
				if type(pData) == "table" and pData.player and typeof(pData.player) == "Instance" and pData.player:IsA("Player") then
					if pData.player.Parent == Players then
						table.insert(playerOrder, pData.player.UserId)
					else
						warn("[TurnSystem] CreateTurnOrder: Player", pData.player.Name, "is no longer in Players service (skipped).")
					end
				else
					warn("[TurnSystem] CreateTurnOrder: Found invalid data structure at index", i, "from PlayerManager.")
				end
			end
		end
	else
		sourceDescription = "Players:GetPlayers (Fallback 2)"
		warn("[TurnSystem] CreateTurnOrder: PlayerManager or GetPlayersSortedByJoinTime not available. Using", sourceDescription)
		for _, player in ipairs(Players:GetPlayers()) do
			if player and player:IsA("Player") then table.insert(playerOrder, player.UserId) end
		end
	end

	-- *** เพิ่ม Log ก่อน Shuffle ***
	print(string.format("[TurnSystem DEBUG] Order BEFORE Shuffle (Source: %s): %s", sourceDescription, table.concat(playerOrder, ", ")))

	-- Shuffle the order if more than one player
	if #playerOrder > 1 then
		self:ShuffleTurnOrder(playerOrder)
		-- *** เพิ่ม Log หลัง Shuffle ***
		print("[TurnSystem DEBUG] Order AFTER Shuffle:", table.concat(playerOrder, ", "))
	else
		print("[TurnSystem DEBUG] Only one player or zero players, no shuffle needed.")
	end

	-- Set the potentially shuffled order
	return self:SetTurnOrder(playerOrder)
end
-- *** สิ้นสุดการแก้ไข ***

-- ShuffleTurnOrder (เหมือนเดิม)
function TurnSystem:ShuffleTurnOrder(order)
	local playerCount = #order
	for i = playerCount, 2, -1 do
		local j = math.random(i)
		order[i], order[j] = order[j], order[i]
	end
	-- Removed debug log from here as it's now logged after the call
	return order
end

-- StartTurnSystem (เหมือนเดิม)
function TurnSystem:StartTurnSystem()
	if #self.turnOrder == 0 then
		warn("[TurnSystem] Cannot start turn system, turn order is empty.")
		return false
	end
	print("[TurnSystem] Starting Turn System...")
	self.currentTurnIndex = 0
	self.isPaused = false
	self:NextTurn()
	return true
end

-- StartPlayerTurn (เหมือนเดิม - โค้ดยาว ไม่ต้องใส่ซ้ำ)
function TurnSystem:StartPlayerTurn(playerID, attemptCount)
	attemptCount = attemptCount or 0
	-- print(string.format("[TurnSystem DEBUG] StartPlayerTurn called for ID: %s (Attempt: %d)", tostring(playerID), attemptCount)) -- DEBUG

	if self.isPaused then
		-- print("[TurnSystem DEBUG] Turn system is paused. Aborting StartPlayerTurn.")
		return false
	end

	if attemptCount > (#self.turnOrder * 2) + 1 then
		warn("[TurnSystem] ERROR: Exceeded max attempts ("..attemptCount..") to find next valid player. Stopping turns.")
		self:Reset()
		return false
	end

	if not playerID or type(playerID) ~= "number" then
		warn("[TurnSystem] StartPlayerTurn called with invalid playerID type:", type(playerID), ". Value:", tostring(playerID), ". Moving to next.")
		return self:NextTurn(attemptCount + 1)
	end

	local player = Players:GetPlayerByUserId(playerID)

	if not player then
		warn("[TurnSystem] Player with ID " .. tostring(playerID) .. " not found (left?). Removing from turn order.")
		local foundAndRemoved = false
		for i = #self.turnOrder, 1, -1 do
			if self.turnOrder[i] == playerID then
				table.remove(self.turnOrder, i)
				foundAndRemoved = true
				-- print("[TurnSystem] Removed ID", playerID, "from turn order. New order:", self.turnOrder) -- Debug
				break
			end
		end
		if foundAndRemoved then
			self.currentTurnIndex = math.max(0, self.currentTurnIndex - 1)
		end
		if #self.turnOrder == 0 then
			warn("[TurnSystem] No players left after removal. Stopping turns.")
			self:Reset()
			return false
		end
		return self:NextTurn(attemptCount + 1)
	end

	if self.deadPlayers[playerID] then
		print("[TurnSystem] Player", player.Name, "is dead. Skipping turn.")
		return self:NextTurn(attemptCount + 1)
	end

	if self.skipTurnPlayers[playerID] then
		print("[TurnSystem] Player", player.Name, "is skipping turn.")
		local turnsToSkip = self.skipTurnPlayers[playerID] - 1
		if turnsToSkip <= 0 then
			self.skipTurnPlayers[playerID] = nil
			print("  > Finished skipping.")
		else
			self.skipTurnPlayers[playerID] = turnsToSkip
			print("  >", turnsToSkip, "more turns to skip.")
		end
		return self:NextTurn(attemptCount + 1)
	end

	local gameManager = _G.GameManager
	if gameManager then
		if gameManager.inventoryService and gameManager.inventoryService.ResetTurnFlagsForPlayer then
			local resetSuccess, resetMsg = pcall(gameManager.inventoryService.ResetTurnFlagsForPlayer, gameManager.inventoryService, playerID)
			if not resetSuccess then
				warn("[TurnSystem] Error calling InventoryService.ResetTurnFlagsForPlayer for ID", playerID, ":", resetMsg)
				-- else print("[TurnSystem DEBUG] Successfully called InventoryService.ResetTurnFlagsForPlayer for ID", playerID)
			end
		end
	end

	self:DecrementCombatCooldown(playerID)

	print("[TurnSystem] Starting turn for Player:", player.Name, "(ID:", playerID, ")")
	self.currentPlayerTurn = playerID
	self.isTurnActive = true
	self.turnTimeRemaining = TURN_TIME_LIMIT
	self.pendingEndTurn[playerID] = nil

	if self.remotes and self.remotes.updateTurn then
		self.remotes.updateTurn:FireAllClients(playerID)
	else warn("[TurnSystem] Remotes not initialized for UpdateTurn.") end

	if self.remotes and self.remotes.turnState then
		local cooldownTurns = self:GetCombatCooldown(playerID)
		self.remotes.turnState:FireClient(player, {
			timeLimit = TURN_TIME_LIMIT, isYourTurn = true, combatCooldown = cooldownTurns
		})
		if cooldownTurns > 0 then
			if self.remotes.combatCooldown then
				self.remotes.combatCooldown:FireClient(player, cooldownTurns)
			else warn("[TurnSystem] CombatCooldown remote missing.") end
		end
	else warn("[TurnSystem] Remotes not initialized for TurnState.") end

	self:StartTurnTimer()

	if self.onTurnStart then
		local success, err = pcall(self.onTurnStart, playerID)
		if not success then warn("[TurnSystem] Error in onTurnStart callback:", err) end
	end

	return true
end

-- StartTurnTimer (เหมือนเดิม)
function TurnSystem:StartTurnTimer()
	if self.turnTimer then self.turnTimer:Disconnect(); self.turnTimer = nil end
	local turnStartTime = os.clock()
	local lastSecondFired = -1
	self.turnTimer = RunService.Heartbeat:Connect(function(deltaTime)
		if not self.isTurnActive or self.isPaused then
			if self.turnTimer then
				self.turnTimer:Disconnect(); self.turnTimer = nil
				if self.isPaused then
					-- print("[TurnSystem DEBUG] Turn timer paused.")
					self.pausedTurnState = { playerId = self.currentPlayerTurn, timeRemaining = self.turnTimeRemaining }
				end
			end
			return
		end
		local elapsedTime = os.clock() - turnStartTime
		self.turnTimeRemaining = math.max(0, TURN_TIME_LIMIT - elapsedTime)
		local currentSecondDisplay = math.floor(self.turnTimeRemaining)
		if currentSecondDisplay ~= lastSecondFired then
			lastSecondFired = currentSecondDisplay
			if self.remotes and self.remotes.updateTurnTimer then self.remotes.updateTurnTimer:FireAllClients(currentSecondDisplay) end
			if self.onTurnTimerUpdate then pcall(self.onTurnTimerUpdate, currentSecondDisplay) end
			if currentSecondDisplay == INACTIVITY_WARNING_TIME then
				local player = Players:GetPlayerByUserId(self.currentPlayerTurn)
				if player and self.remotes and self.remotes.turnState then self.remotes.turnState:FireClient(player, { warning = "Turn time is running out!", timeLeft = currentSecondDisplay }) end
			end
		end
		if self.turnTimeRemaining <= 0 then
			print("[TurnSystem] Turn timer ended for player:", self.currentPlayerTurn)
			if self.isTurnActive then self:EndPlayerTurn(self.currentPlayerTurn, "timeout") end
		end
	end)
end

-- EndPlayerTurn (เหมือนเดิม - โค้ดยาว ไม่ต้องใส่ซ้ำ)
function TurnSystem:EndPlayerTurn(playerID, reason)
	reason = reason or "normal"
	-- print(string.format("[TurnSystem DEBUG] EndPlayerTurn called for ID: %s, Reason: %s", tostring(playerID), reason)) -- DEBUG

	if not self.isTurnActive or playerID ~= self.currentPlayerTurn then
		warn(string.format( "[TurnSystem] Attempted to end turn for wrong player or inactive turn. Current: %s, Requested: %s, Active: %s. Ignoring request.", tostring(self.currentPlayerTurn), tostring(playerID), tostring(self.isTurnActive) ))
		if not self.isTurnActive and self.pendingEndTurn[playerID] and reason ~= "timeout" then
			-- print("[TurnSystem DEBUG] Clearing pending end turn for player", playerID, "due to inactive turn state.")
			self.pendingEndTurn[playerID] = nil
		end
		return false
	end

	if self.pendingEndTurn[playerID] and reason ~= "timeout" then
		-- print("[TurnSystem DEBUG] EndPlayerTurn ignored, already pending for:", playerID) -- DEBUG
		return false
	end

	if reason == "timeout" and self.pendingEndTurn[playerID] then
		-- print("[TurnSystem DEBUG] Timeout occurred during pending end turn. Cancelling pending movement end.") -- DEBUG
		self.pendingEndTurn[playerID] = nil
	elseif (reason == "move_complete" or reason == "move_timeout") and not self.pendingEndTurn[playerID] then
		-- print("[TurnSystem DEBUG] Pending end turn requested for movement reason:", reason) -- DEBUG
		self.pendingEndTurn[playerID] = { reason = reason, timestamp = os.clock() }
		Task.delay(MOVEMENT_SAFETY_DELAY, function()
			if self.currentPlayerTurn == playerID and self.isTurnActive and self.pendingEndTurn[playerID] then
				local endingReason = self.pendingEndTurn[playerID].reason
				self.pendingEndTurn[playerID] = nil
				-- print("[TurnSystem DEBUG] Executing delayed end turn after MOVEMENT_SAFETY_DELAY. Reason:", endingReason) -- DEBUG
				self:ExecuteEndTurn(playerID, endingReason)
			else
				-- if self.pendingEndTurn[playerID] then print("[TurnSystem DEBUG] Delayed end turn cancelled (Turn changed or became inactive). Current:", self.currentPlayerTurn, "Active:", self.isTurnActive) -- DEBUG; self.pendingEndTurn[playerID] = nil
				-- else print("[TurnSystem DEBUG] Delayed end turn cancelled (Pending state was already cleared, likely by timeout).") -- DEBUG
				-- end
			end
		end)
		return true
	end

	-- print("[TurnSystem DEBUG] Executing end turn immediately. Reason:", reason) -- DEBUG
	self.pendingEndTurn[playerID] = nil
	return self:ExecuteEndTurn(playerID, reason)
end

-- ExecuteEndTurn (เหมือนเดิม)
function TurnSystem:ExecuteEndTurn(playerID, reason)
	if playerID ~= self.currentPlayerTurn or not self.isTurnActive then
		warn(string.format( "[TurnSystem ExecuteEndTurn] Invalid state detected! Current: %s, Requested: %s, Active: %s. Aborting.", tostring(self.currentPlayerTurn), tostring(playerID), tostring(self.isTurnActive) ))
		return false
	end
	print("[TurnSystem] Executing End Turn for Player ID:", playerID, "Reason:", reason)
	local endingPlayerID = self.currentPlayerTurn
	if self.turnTimer then self.turnTimer:Disconnect(); self.turnTimer = nil; -- print("  > Turn timer stopped.")
	end
	self.isTurnActive = false
	self.currentPlayerTurn = nil
	self.pendingEndTurn[endingPlayerID] = nil
	if self.onTurnEnd then
		local success, err = pcall(self.onTurnEnd, endingPlayerID, reason)
		if not success then warn("[TurnSystem] Error in onTurnEnd callback:", err) end
	end
	local player = Players:GetPlayerByUserId(endingPlayerID)
	if player and self.remotes and self.remotes.turnState then self.remotes.turnState:FireClient(player, { isYourTurn = false, turnEnded = true, reason = reason }); -- print("  > Notified ending player:", endingPlayerID)
	end
	Task.wait(0.2)
	print("[TurnSystem] Moving to next turn...")
	if not self.isPaused then self:NextTurn()
	else print("[TurnSystem] System is paused, not moving to next turn after end.") end
	return true
end

-- NextTurn (เหมือนเดิม)
function TurnSystem:NextTurn(attemptCount)
	if self.isPaused then print("[TurnSystem DEBUG] Turn system is paused. Cannot move to next turn."); return false end
	if #self.turnOrder == 0 then warn("[TurnSystem] No players left in turn order. Stopping turns."); self:Reset(); return false end
	self.currentTurnIndex = self.currentTurnIndex + 1
	if self.currentTurnIndex > #self.turnOrder then self.currentTurnIndex = 1 end
	local nextPlayerID = self.turnOrder[self.currentTurnIndex]
	print(string.format("[TurnSystem] NextTurn: Attempting turn for index %d / %d. PlayerID: %s", self.currentTurnIndex, #self.turnOrder, tostring(nextPlayerID)))
	Task.spawn(self.StartPlayerTurn, self, nextPlayerID, attemptCount)
	return true
end

-- SetPlayerSkipTurns (เหมือนเดิม)
function TurnSystem:SetPlayerSkipTurns(playerID, turns)
	if not playerID or type(playerID) ~= "number" then return false end
	if turns and type(turns) == "number" and turns > 0 then
		self.skipTurnPlayers[playerID] = turns; print("[TurnSystem] Player", playerID, "will skip", turns, "turns.")
	else
		if self.skipTurnPlayers[playerID] then print("[TurnSystem] Cleared skip turns for player", playerID) end
		self.skipTurnPlayers[playerID] = nil
	end
	return true
end

-- GetCurrentPlayerTurn (เหมือนเดิม)
function TurnSystem:GetCurrentPlayerTurn() return self.currentPlayerTurn end

-- IsPlayerTurn (เหมือนเดิม)
function TurnSystem:IsPlayerTurn(playerID)
	if not self.isTurnActive or self.isPaused then return false end
	if playerID ~= self.currentPlayerTurn then return false end
	if self.deadPlayers[playerID] then return false end
	return true
end

-- HandleTurnAction (เหมือนเดิม)
function TurnSystem:HandleTurnAction(player, actionType, actionData)
	local playerID = player.UserId
	if self.isPaused then warn("[TurnSystem] Received action", actionType, "from player", player.Name, "but the turn system is paused."); return false end
	if not self:IsPlayerTurn(playerID) then warn("[TurnSystem] Received action", actionType, "from player", player.Name, "but it's not their turn."); return false end
	print("[TurnSystem] Handling action:", actionType, "from player:", player.Name)
	if actionType == "endTurn" then return self:EndPlayerTurn(playerID, "player_choice")
	elseif actionType == "rollDice" then print("  > Action 'rollDice' acknowledged."); return true
	elseif actionType == "useItem" then print("  > Action 'useItem' acknowledged."); return true
	elseif actionType == "moveComplete" then print("  > Action 'moveComplete' received."); return self:EndPlayerTurn(playerID, "move_complete")
	end
	warn("[TurnSystem] Unhandled action type:", actionType)
	return false
end

-- HandlePlayerLeaving (เหมือนเดิม)
function TurnSystem:HandlePlayerLeaving(playerID)
	if not playerID or type(playerID) ~= "number" then return false end
	print("[TurnSystem] Handling player leaving:", playerID)
	local wasCurrentTurn = (playerID == self.currentPlayerTurn)
	local turnIndexBeforeRemoval = self.currentTurnIndex
	local removed = false
	for i = #self.turnOrder, 1, -1 do
		if self.turnOrder[i] == playerID then
			table.remove(self.turnOrder, i); removed = true
			print("  > Removed from turn order. New order:", table.concat(self.turnOrder, ", "))
			if i <= turnIndexBeforeRemoval then self.currentTurnIndex = math.max(0, turnIndexBeforeRemoval - 1); -- print("  > Adjusted currentTurnIndex to:", self.currentTurnIndex)
			end
			break
		end
	end
	if not removed then print("  > Player", playerID, "not found in current turn order.") end
	self.skipTurnPlayers[playerID] = nil; self.turnStates[playerID] = nil; self.pendingEndTurn[playerID] = nil
	self.deadPlayers[playerID] = nil; self.combatCooldowns[playerID] = nil
	print("  > Cleared state for player", playerID)
	if wasCurrentTurn and self.isTurnActive then
		print("  > Leaving player was current turn. Ending their turn and moving next.")
		if self.turnTimer then self.turnTimer:Disconnect(); self.turnTimer = nil end
		self.isTurnActive = false; self.currentPlayerTurn = nil
		if not self.isPaused and #self.turnOrder > 0 then self:NextTurn()
		elseif self.isPaused then print("  > Turn system is paused, not moving to next turn.")
		elseif #self.turnOrder == 0 then print("  > No players left after removal. Resetting."); self:Reset() end
	elseif #self.turnOrder > 0 and self.currentTurnIndex >= #self.turnOrder then
		self.currentTurnIndex = 0; print("  > Adjusted currentTurnIndex to 0 due to removal making it out of bounds.")
	elseif #self.turnOrder == 0 then print("  > Last player left or turn order empty. Resetting turn system."); self:Reset() end
	return true
end

-- OnPlayerDeath (เหมือนเดิม)
function TurnSystem:OnPlayerDeath(playerID)
	if not playerID or type(playerID) ~= "number" then return false end
	print("[TurnSystem] Player", playerID, "has died.")
	self.deadPlayers[playerID] = true
	if self.currentPlayerTurn == playerID and self.isTurnActive then
		print("[TurnSystem] Ending turn of dead player", playerID)
		self:ExecuteEndTurn(playerID, "player_death")
		return true
	end
	print("[TurnSystem] Marked player", playerID, "as dead.")
	return true
end

-- OnPlayerRespawn (เหมือนเดิม)
function TurnSystem:OnPlayerRespawn(playerID)
	if not playerID or type(playerID) ~= "number" then return false end
	print("[TurnSystem] Player", playerID, "has respawned.")
	if not self.deadPlayers[playerID] then print(" > Player", playerID, "was not marked as dead.") end
	self.deadPlayers[playerID] = nil
	local isInTurnOrder = false; for _, id in ipairs(self.turnOrder) do if id == playerID then isInTurnOrder = true; break end end
	if not isInTurnOrder then table.insert(self.turnOrder, playerID); print("[TurnSystem] Added respawned player", playerID, "back to turn order.") end
	self.skipTurnPlayers[playerID] = 1; print("[TurnSystem] Player", playerID, "will skip next turn after respawn.")
	return true
end

-- Reset (เหมือนเดิม)
function TurnSystem:Reset()
	print("[TurnSystem] Resetting Turn System...")
	if self.turnTimer then self.turnTimer:Disconnect(); self.turnTimer = nil end
	self.turnOrder = {}; self.currentTurnIndex = 0; self.currentPlayerTurn = nil; self.isTurnActive = false
	self.turnTimeRemaining = 0; self.turnStates = {}; self.skipTurnPlayers = {}; self.pendingEndTurn = {}
	self.deadPlayers = {}; self.isPaused = false; self.pausedTurnState = nil; self.combatCooldowns = {}
	print("[TurnSystem] Reset complete.")
	return true
end

-- PauseTurns (เหมือนเดิม)
function TurnSystem:PauseTurns()
	if self.isPaused then print("[TurnSystem] Already paused."); return end
	print("[TurnSystem] Pausing turns.")
	self.isPaused = true
	if self.isTurnActive and self.turnTimer then
		self.turnTimer:Disconnect(); self.turnTimer = nil
		self.pausedTurnState = { playerId = self.currentPlayerTurn, timeRemaining = self.turnTimeRemaining }
		print(string.format("  > Stored paused turn state for player %d with %.2f s remaining.", self.pausedTurnState.playerId, self.pausedTurnState.timeRemaining))
		if self.remotes and self.remotes.updateTurnTimer then self.remotes.updateTurnTimer:FireAllClients("Paused") end
	elseif self.isTurnActive then warn("[TurnSystem] Pausing active turn, but timer was not running."); self.pausedTurnState = { playerId = self.currentPlayerTurn, timeRemaining = self.turnTimeRemaining } end
end

-- ResumeTurns (เหมือนเดิม)
function TurnSystem:ResumeTurns()
	if not self.isPaused then print("[TurnSystem] Not paused."); return end
	print("[TurnSystem] Resuming turns.")
	self.isPaused = false; local pausedState = self.pausedTurnState; self.pausedTurnState = nil
	if pausedState and pausedState.playerId then
		local player = Players:GetPlayerByUserId(pausedState.playerId)
		if player and not self.deadPlayers[pausedState.playerId] then
			print(string.format("  > Resuming turn for player %d with %.2f s remaining.", pausedState.playerId, pausedState.timeRemaining))
			self.currentPlayerTurn = pausedState.playerId; self.isTurnActive = true; self.turnTimeRemaining = pausedState.timeRemaining
			local foundIndex = table.find(self.turnOrder, pausedState.playerId)
			if foundIndex then self.currentTurnIndex = foundIndex
			else warn("[TurnSystem] Resuming player", pausedState.playerId, "not found in turn order anymore! Moving next."); self:NextTurn(); return end
			self:StartTurnTimer()
			if self.remotes and self.remotes.updateTurn then self.remotes.updateTurn:FireAllClients(pausedState.playerId) end
			if self.remotes and self.remotes.updateTurnTimer then self.remotes.updateTurnTimer:FireAllClients(math.floor(pausedState.timeRemaining)) end
		else
			if not player then warn("  > Paused player", pausedState.playerId, "is no longer in the game. Moving to next turn.")
			else warn("  > Paused player", pausedState.playerId, "is dead. Moving to next turn.") end
			self:NextTurn()
		end
	else print("  > No valid paused turn state found or turn wasn't active. Moving to next turn."); self:NextTurn() end
end

-- Combat Cooldown Functions (เหมือนเดิม)
function TurnSystem:SetCombatCooldown(playerID, turns)
	if not playerID or type(playerID) ~= "number" then return false end
	turns = tonumber(turns)
	if turns and turns > 0 then
		self.combatCooldowns[playerID] = turns; print("[TurnSystem] Player", playerID, "has", turns, "turns of combat cooldown.")
		local player = Players:GetPlayerByUserId(playerID)
		if player and self.remotes and self.remotes.combatCooldown then self.remotes.combatCooldown:FireClient(player, turns) end
	else
		if self.combatCooldowns[playerID] then
			print("[TurnSystem] Cleared combat cooldown for player", playerID); self.combatCooldowns[playerID] = nil
			local player = Players:GetPlayerByUserId(playerID)
			if player and self.remotes and self.remotes.combatCooldown then self.remotes.combatCooldown:FireClient(player, 0) end
		end
	end
	return true
end
function TurnSystem:DecrementCombatCooldown(playerID)
	if not playerID or not self.combatCooldowns[playerID] then return false end
	local remainingCooldown = self.combatCooldowns[playerID] - 1
	if remainingCooldown <= 0 then
		self.combatCooldowns[playerID] = nil; print("[TurnSystem] Combat cooldown ended for player", playerID)
		local player = Players:GetPlayerByUserId(playerID)
		if player and self.remotes and self.remotes.combatCooldown then self.remotes.combatCooldown:FireClient(player, 0) end
	else
		self.combatCooldowns[playerID] = remainingCooldown; print("[TurnSystem] Combat cooldown for player", playerID, "reduced to", remainingCooldown, "turns")
		local player = Players:GetPlayerByUserId(playerID)
		if player and self.remotes and self.remotes.combatCooldown then self.remotes.combatCooldown:FireClient(player, remainingCooldown) end
	end
	return true
end
function TurnSystem:GetCombatCooldown(playerID) if not playerID then return 0 end; return self.combatCooldowns[playerID] or 0 end
function TurnSystem:HasCombatCooldown(playerID) return self:GetCombatCooldown(playerID) > 0 end

return TurnSystem
