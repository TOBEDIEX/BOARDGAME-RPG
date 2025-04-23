-- TurnSystem.lua
-- Module for managing turn system and player order
-- Version: 3.2.0 (Added Pause/Resume and Combat Handling)

local TurnSystem = {}
TurnSystem.__index = TurnSystem

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService") -- Added for Heartbeat

-- Constants
local TURN_TIME_LIMIT = 60
local INACTIVITY_WARNING_TIME = 15
local MOVEMENT_SAFETY_DELAY = 0.8

-- Constructor
function TurnSystem.new()
	local self = setmetatable({}, TurnSystem)

	self.turnOrder = {} -- Should store UserIds (numbers)
	self.currentTurnIndex = 0
	self.currentPlayerTurn = nil -- Stores the UserId of the current player
	self.isTurnActive = false
	self.turnTimer = nil
	self.turnTimeRemaining = 0
	self.turnStates = {} -- Stores additional state per player if needed
	self.skipTurnPlayers = {} -- Stores UserId -> turns to skip
	self.pendingEndTurn = {} -- Stores UserId -> {reason, timestamp}
	self.deadPlayers = {} -- Stores UserId -> dead state (true/false)
	self.isPaused = false -- NEW: Flag to pause turn progression
	self.pausedTurnState = nil -- NEW: Store state if paused mid-turn {playerId, timeRemaining}

	-- Callbacks (can be set by other systems like GameManager)
	self.onTurnStart = nil
	self.onTurnEnd = nil
	self.onTurnTimerUpdate = nil

	self.remotes = nil -- Will be initialized later

	return self
end

-- Initialize RemoteEvents used by the system
function TurnSystem:InitializeRemotes(gameRemotes)
	if not gameRemotes then
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		gameRemotes = remotes:WaitForChild("GameRemotes")
	end

	-- Ensure required remotes exist or create them
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
		turnState = ensureRemoteEvent(gameRemotes, "TurnState")
	}

	-- Connect server event for turn actions from clients
	if self.remotes.turnAction then
		-- Disconnect previous connection if any to prevent duplicates
		if self._turnActionConnection then self._turnActionConnection:Disconnect() end
		self._turnActionConnection = self.remotes.turnAction.OnServerEvent:Connect(function(player, actionType, actionData)
			self:HandleTurnAction(player, actionType, actionData)
		end)
	end

	return self.remotes
end

-- Set the order of players for turns (expects a table of UserIds)
function TurnSystem:SetTurnOrder(players)
	if type(players) ~= "table" then return false end
	self.turnOrder = players
	self.currentTurnIndex = 0
	self.currentPlayerTurn = nil
	self.isTurnActive = false
	print("[TurnSystem] Set Turn Order:", self.turnOrder) -- Debug
	return true
end

-- Create turn order from currently active players, optionally using PlayerManager for sorting
function TurnSystem:CreateTurnOrderFromActivePlayers(playerManager)
	local playerOrder = {} -- This will store UserIds

	if playerManager then
		local sortedPlayersData = playerManager:GetPlayersSortedByJoinTime()
		print("[TurnSystem DEBUG] CreateTurnOrder: Got sortedPlayersData:", sortedPlayersData) -- DEBUG
		if type(sortedPlayersData) ~= "table" then
			warn("[TurnSystem] CreateTurnOrder: GetPlayersSortedByJoinTime did not return a table!")
			return false
		end
		for i, pData in ipairs(sortedPlayersData) do
			print(string.format("[TurnSystem DEBUG] CreateTurnOrder: Processing index %d, type: %s", i, type(pData))) -- DEBUG
			-- Validate the player data structure before accessing properties
			if type(pData) == "table" and pData.player and typeof(pData.player) == "Instance" and pData.player:IsA("Player") then
				if pData.player.Parent == Players then
					print("  > Adding UserId:", pData.player.UserId) -- DEBUG
					table.insert(playerOrder, pData.player.UserId)
				else
					warn("[TurnSystem] CreateTurnOrder: Player", pData.player.Name, "is no longer in Players service.")
				end
			else
				-- Detailed warning for invalid data structure
				warn("[TurnSystem] CreateTurnOrder: Found invalid or unexpected data structure at index", i)
				if type(pData) == "table" then
					warn("  > pData Table Content:", pData)
					if pData.player then
						warn("  > pData.player Type:", typeof(pData.player))
						if typeof(pData.player) == "Instance" then warn("  > pData.player ClassName:", pData.player.ClassName) end
					else
						warn("  > pData.player is nil or missing.")
					end
				elseif typeof(pData) == "Instance" and pData:IsA("Player") then
					warn("  > CRITICAL: Found a direct Player Instance instead of PlayerData table! Player:", pData.Name, "UserId:", pData.UserId)
				else
					warn("  > Unexpected data type:", type(pData))
				end
			end
		end
	else
		-- Fallback if PlayerManager is not provided
		warn("[TurnSystem] CreateTurnOrder: PlayerManager not provided, using Players:GetPlayers() fallback.")
		for _, player in pairs(Players:GetPlayers()) do
			if player and typeof(player) == "Instance" and player:IsA("Player") then
				table.insert(playerOrder, player.UserId)
			end
		end
	end

	-- Shuffle the order if more than one player
	if #playerOrder > 1 then
		self:ShuffleTurnOrder(playerOrder)
	end

	print("[TurnSystem] Created Final Turn Order (UserIds):", playerOrder) -- Debug
	return self:SetTurnOrder(playerOrder)
end

-- Shuffle the turn order array using Fisher-Yates algorithm
function TurnSystem:ShuffleTurnOrder(order)
	local playerCount = #order
	for i = playerCount, 2, -1 do
		local j = math.random(i)
		order[i], order[j] = order[j], order[i]
	end
	return order
end

-- Start the turn system (begins the first turn)
function TurnSystem:StartTurnSystem()
	if #self.turnOrder == 0 then
		warn("[TurnSystem] Cannot start turn system, turn order is empty.")
		return false
	end
	print("[TurnSystem] Starting Turn System...") -- Debug
	self.currentTurnIndex = 0 -- Reset index before starting
	self.isPaused = false -- Ensure not paused on start
	self:NextTurn() -- Start the first turn
	return true
end

-- Start a specific player's turn
function TurnSystem:StartPlayerTurn(playerID, attemptCount)
	attemptCount = attemptCount or 0
	print(string.format("[TurnSystem DEBUG] StartPlayerTurn called for ID: %s (Attempt: %d)", tostring(playerID), attemptCount)) -- DEBUG

	-- Check if paused
	if self.isPaused then
		print("[TurnSystem DEBUG] Turn system is paused. Aborting StartPlayerTurn.")
		-- Store the intended player if needed, but don't start the turn
		-- self.pausedTurnState = { playerId = playerID, timeRemaining = TURN_TIME_LIMIT }
		return false
	end

	-- Safety break to prevent infinite loops if no valid player can be found
	if attemptCount > (#self.turnOrder * 2) + 1 then
		warn("[TurnSystem] ERROR: Exceeded max attempts ("..attemptCount..") to find next valid player. Stopping turns.")
		self:Reset()
		return false
	end

	-- Validate Player ID type
	if not playerID or type(playerID) ~= "number" then
		warn("[TurnSystem] StartPlayerTurn called with invalid playerID type:", type(playerID), ". Value:", tostring(playerID), ". Moving to next.")
		return self:NextTurn(attemptCount + 1)
	end

	-- Find the player instance
	local player = Players:GetPlayerByUserId(playerID)

	-- Handle case where player left the game
	if not player then
		warn("[TurnSystem] Player with ID " .. tostring(playerID) .. " not found (left?). Removing from turn order.")
		local foundAndRemoved = false
		for i = #self.turnOrder, 1, -1 do
			if self.turnOrder[i] == playerID then
				table.remove(self.turnOrder, i)
				foundAndRemoved = true
				print("[TurnSystem] Removed ID", playerID, "from turn order. New order:", self.turnOrder) -- Debug
				break
			end
		end
		-- Adjust index if removal affected current position
		if foundAndRemoved then
			self.currentTurnIndex = math.max(0, self.currentTurnIndex - 1) -- Decrement index carefully
		end
		return self:NextTurn(attemptCount + 1) -- Try the next player
	end

	-- Check if the player is dead
	if self.deadPlayers[playerID] then
		print("[TurnSystem] Player", player.Name, "is dead. Skipping turn.")
		return self:NextTurn(attemptCount + 1) -- Skip dead players
	end

	-- Check if the player needs to skip this turn
	if self.skipTurnPlayers[playerID] then
		print("[TurnSystem] Player", player.Name, "is skipping turn.") -- Debug Print
		local turnsToSkip = self.skipTurnPlayers[playerID] - 1
		if turnsToSkip <= 0 then
			self.skipTurnPlayers[playerID] = nil -- Remove skip entry
			print("  > Finished skipping.") -- Debug
		else
			self.skipTurnPlayers[playerID] = turnsToSkip -- Decrement turns to skip
			print("  >", turnsToSkip, "more turns to skip.") -- Debug
		end
		return self:NextTurn(attemptCount + 1) -- Move to the next player
	end

	-- Reset relevant flags in other services via GameManager
	local gameManager = _G.GameManager -- Get GameManager reference
	if gameManager then
		-- Reset Inventory Service flags (like item usage)
		if gameManager.inventoryService and gameManager.inventoryService.ResetTurnFlagsForPlayer then
			local resetSuccess, resetMsg = pcall(gameManager.inventoryService.ResetTurnFlagsForPlayer, playerID)
			if not resetSuccess then
				warn("[TurnSystem] Error calling InventoryService.ResetTurnFlagsForPlayer for ID", playerID, ":", resetMsg)
			else
				print("[TurnSystem DEBUG] Successfully called InventoryService.ResetTurnFlagsForPlayer for ID", playerID)
			end
		else
			warn("[TurnSystem] InventoryService or ResetTurnFlagsForPlayer function not found in GameManager.")
		end
		-- Add calls to reset flags in other services here if needed
	else
		warn("[TurnSystem] GameManager not found, cannot reset turn flags in other services.")
	end

	-- Start the actual turn
	print("[TurnSystem] Starting turn for Player:", player.Name, "(ID:", playerID, ")") -- Debug Print
	self.currentPlayerTurn = playerID
	self.isTurnActive = true
	self.turnTimeRemaining = TURN_TIME_LIMIT
	self.pendingEndTurn[playerID] = nil -- Clear any pending end turn state

	-- Notify all clients about the new turn
	if self.remotes and self.remotes.updateTurn then
		self.remotes.updateTurn:FireAllClients(playerID)
	else
		warn("[TurnSystem] Remotes not initialized for UpdateTurn.")
	end

	-- Send specific state info to the current player
	if self.remotes and self.remotes.turnState then
		self.remotes.turnState:FireClient(player, { timeLimit = TURN_TIME_LIMIT, isYourTurn = true })
	else
		warn("[TurnSystem] Remotes not initialized for TurnState.")
	end

	-- Start the turn timer
	self:StartTurnTimer()

	-- Call the external onTurnStart callback if it's set
	if self.onTurnStart then
		local success, err = pcall(self.onTurnStart, playerID)
		if not success then
			warn("[TurnSystem] Error in onTurnStart callback:", err)
		end
	end

	return true -- Turn started successfully
end

-- Start the countdown timer for the current turn
function TurnSystem:StartTurnTimer()
	-- Stop any existing timer
	if self.turnTimer then
		self.turnTimer:Disconnect()
		self.turnTimer = nil
	end

	local startTime = os.time()
	local lastSecond = -1 -- Track the last second updated to avoid excessive remote calls

	-- Use Heartbeat for smooth timer updates
	self.turnTimer = RunService.Heartbeat:Connect(function()
		-- Stop the timer if the turn is no longer active OR if the system is paused
		if not self.isTurnActive or self.isPaused then
			if self.turnTimer then
				self.turnTimer:Disconnect()
				self.turnTimer = nil
				if self.isPaused then
					print("[TurnSystem DEBUG] Turn timer paused.")
					-- Store remaining time if paused mid-turn
					self.pausedTurnState = { playerId = self.currentPlayerTurn, timeRemaining = self.turnTimeRemaining }
				end
			end
			return
		end

		local elapsedTime = os.time() - startTime
		local currentSecond = math.floor(elapsedTime)
		self.turnTimeRemaining = math.max(0, TURN_TIME_LIMIT - elapsedTime)

		-- Update timer display only once per second
		if currentSecond ~= lastSecond then
			lastSecond = currentSecond
			local displayTime = math.max(0, TURN_TIME_LIMIT - currentSecond)

			-- Update all clients with the remaining time
			if self.remotes and self.remotes.updateTurnTimer then
				self.remotes.updateTurnTimer:FireAllClients(displayTime)
			end

			-- Call the timer update callback if set
			if self.onTurnTimerUpdate then
				pcall(self.onTurnTimerUpdate, displayTime) -- Use pcall for safety
			end

			-- Send a warning to the current player when time is low
			if displayTime == INACTIVITY_WARNING_TIME then
				local player = Players:GetPlayerByUserId(self.currentPlayerTurn)
				if player and self.remotes and self.remotes.turnState then
					self.remotes.turnState:FireClient(player, { warning = "Turn time is running out!", timeLeft = displayTime })
				end
			end
		end

		-- End the turn automatically if time runs out
		if self.turnTimeRemaining <= 0 then
			print("[TurnSystem] Turn timer ended for player:", self.currentPlayerTurn) -- Debug
			-- Ensure EndPlayerTurn is called only once for timeout
			if self.isTurnActive then -- Double check turn is still active before ending
				self:EndPlayerTurn(self.currentPlayerTurn, "timeout")
			end
		end
	end)
end

-- End the current player's turn
function TurnSystem:EndPlayerTurn(playerID, reason)
	reason = reason or "normal"
	print(string.format("[TurnSystem DEBUG] EndPlayerTurn called for ID: %s, Reason: %s", tostring(playerID), reason)) -- DEBUG

	-- Check if the turn is actually active AND if the playerID matches the current turn
	-- This prevents errors if EndPlayerTurn is called multiple times during turn transition
	if not self.isTurnActive or playerID ~= self.currentPlayerTurn then
		-- Provide more context in the warning
		warn(string.format(
			"[TurnSystem] Attempted to end turn for wrong player or inactive turn. Current: %s, Requested: %s, Active: %s",
			tostring(self.currentPlayerTurn),
			tostring(playerID),
			tostring(self.isTurnActive)
			))
		-- If the turn is inactive but a pending end exists (not from timeout), clear it to prevent issues.
		if not self.isTurnActive and self.pendingEndTurn[playerID] and reason ~= "timeout" then
			print("[TurnSystem DEBUG] Clearing pending end turn for player", playerID, "due to inactive turn state.")
			self.pendingEndTurn[playerID] = nil
		end
		return false -- Stop execution if the state is invalid
	end

	-- Check for pending end turn to avoid multiple calls, unless it's a timeout
	if self.pendingEndTurn[playerID] and reason ~= "timeout" then
		print("[TurnSystem DEBUG] EndPlayerTurn ignored, already pending for:", playerID) -- DEBUG
		return false
	end

	-- If a timeout happens while a move-related end is pending, cancel the pending one and proceed with timeout
	if reason == "timeout" and self.pendingEndTurn[playerID] then
		print("[TurnSystem DEBUG] Timeout occurred during pending end turn. Cancelling pending.") -- DEBUG
		self.pendingEndTurn[playerID] = nil -- Clear pending state
		-- Fall through to ExecuteEndTurn immediately for timeout reason
		-- Handle delayed end turn for movement completion
	elseif (reason == "move_complete" or reason == "move_timeout") and not self.pendingEndTurn[playerID] then
		print("[TurnSystem DEBUG] Pending end turn for movement reason:", reason) -- DEBUG
		-- Track the pending end request
		self.pendingEndTurn[playerID] = {
			reason = reason,
			timestamp = os.time()
		}

		-- Delay the actual turn end to allow animations/movement to finish
		task.delay(MOVEMENT_SAFETY_DELAY, function()
			-- Verify it's still the current player's turn and the end is still pending
			-- Use playerID here for comparison as self.currentPlayerTurn might become nil if timeout happened
			if self.currentPlayerTurn == playerID and self.pendingEndTurn[playerID] then
				local endingReason = self.pendingEndTurn[playerID].reason
				self.pendingEndTurn[playerID] = nil -- Clear pending state before execution
				print("[TurnSystem DEBUG] Executing delayed end turn after MOVEMENT_SAFETY_DELAY. Reason:", endingReason) -- DEBUG
				self:ExecuteEndTurn(playerID, endingReason) -- Execute the actual turn end
			else
				-- If turn changed or pending state was cleared (e.g., by timeout)
				print("[TurnSystem DEBUG] Delayed end turn cancelled (Turn changed or pending state cleared).") -- DEBUG
			end
		end)

		return true -- Indicate that the end turn process has started (pending)
	end

	-- For non-movement reasons or timeout (when not pending), end turn immediately
	print("[TurnSystem DEBUG] Executing end turn immediately. Reason:", reason) -- DEBUG
	return self:ExecuteEndTurn(playerID, reason)
end


-- Internal function to perform the actual turn end logic
function TurnSystem:ExecuteEndTurn(playerID, reason)
	-- Final check to ensure state is valid before proceeding
	if playerID ~= self.currentPlayerTurn or not self.isTurnActive then
		-- This check might be redundant due to the refined check in EndPlayerTurn, but keep for safety
		print("[TurnSystem DEBUG] ExecuteEndTurn: Invalid state. Current:", self.currentPlayerTurn, "Requested:", playerID, "Active:", self.isTurnActive) -- DEBUG
		return false
	end

	print("[TurnSystem] Executing End Turn for Player ID:", playerID, "Reason:", reason) -- Debug
	local endingPlayerID = self.currentPlayerTurn

	-- Stop the timer and mark turn as inactive
	self.isTurnActive = false
	self.currentPlayerTurn = nil -- Set current player to nil *before* calling NextTurn
	if self.turnTimer then
		self.turnTimer:Disconnect()
		self.turnTimer = nil
		print("  > Turn timer stopped.") -- Debug
	end

	-- Call the external onTurnEnd callback if set
	if self.onTurnEnd then
		local success, err = pcall(self.onTurnEnd, endingPlayerID, reason)
		if not success then
			warn("[TurnSystem] Error in onTurnEnd callback:", err)
		end
	end

	-- Notify the player whose turn just ended
	local player = Players:GetPlayerByUserId(endingPlayerID)
	if player and self.remotes and self.remotes.turnState then
		self.remotes.turnState:FireClient(player, { isYourTurn = false, turnEnded = true, reason = reason })
		print("  > Notified ending player:", endingPlayerID) -- Debug
	end

	-- Short delay before starting the next turn (optional, can help with flow)
	task.wait(0.2)

	print("[TurnSystem] Moving to next turn...") -- Debug
	self:NextTurn() -- Proceed to the next player's turn
	return true
end

-- Move to the next player in the turn order
function TurnSystem:NextTurn(attemptCount)
	-- Check if paused
	if self.isPaused then
		print("[TurnSystem DEBUG] Turn system is paused. Cannot move to next turn.")
		return false
	end

	-- Check if there are any players left
	if #self.turnOrder == 0 then
		warn("[TurnSystem] No players left in turn order. Stopping turns.")
		self:Reset()
		return false
	end

	-- Calculate the index of the next player, wrapping around if necessary
	if self.currentTurnIndex <= 0 or self.currentTurnIndex >= #self.turnOrder then
		self.currentTurnIndex = 1 -- Start from the beginning
	else
		self.currentTurnIndex = self.currentTurnIndex + 1 -- Move to the next index
	end

	local nextPlayerID = self.turnOrder[self.currentTurnIndex]
	print(string.format("[TurnSystem] NextTurn: Attempting turn for index %d / %d. PlayerID: %s", self.currentTurnIndex, #self.turnOrder, tostring(nextPlayerID))) -- Debug Print

	-- Use task.spawn to avoid potential yielding issues if StartPlayerTurn takes time
	task.spawn(self.StartPlayerTurn, self, nextPlayerID, attemptCount)
	return true
end

-- Set a player to skip a specified number of turns
function TurnSystem:SetPlayerSkipTurns(playerID, turns)
	if not playerID then return false end
	if turns and turns > 0 then
		self.skipTurnPlayers[playerID] = turns
		print("[TurnSystem] Player", playerID, "will skip", turns, "turns.") -- Debug
	else
		-- If turns is 0 or nil, clear the skip status
		self.skipTurnPlayers[playerID] = nil
		print("[TurnSystem] Cleared skip turns for player", playerID) -- Debug
	end
	return true
end

-- Get the UserId of the player whose turn it currently is
function TurnSystem:GetCurrentPlayerTurn()
	return self.currentPlayerTurn
end

-- Check if it is currently the specified player's turn
function TurnSystem:IsPlayerTurn(playerID)
	-- First check if the player is in the dead state
	if self.deadPlayers[playerID] then
		return false
	end

	-- Check if it's the player's active turn and system is not paused
	return playerID == self.currentPlayerTurn and self.isTurnActive and not self.isPaused
end

-- Handle actions received from the client during their turn
function TurnSystem:HandleTurnAction(player, actionType, actionData)
	local playerID = player.UserId

	-- Check if paused
	if self.isPaused then
		warn("[TurnSystem] Received action", actionType, "from player", player.Name, "but the turn system is paused.")
		return false
	end

	-- Verify it's the correct player's turn
	if not self:IsPlayerTurn(playerID) then
		warn("[TurnSystem] Received action", actionType, "from player", player.Name, "but it's not their turn.")
		return false
	end

	print("[TurnSystem] Handling action:", actionType, "from player:", player.Name) -- Debug

	-- Handle specific actions
	if actionType == "endTurn" then
		-- Player chooses to end their turn manually
		return self:EndPlayerTurn(playerID, "player_choice")
	elseif actionType == "rollDice" then
		-- Acknowledge action, but actual logic might be in another system (e.g., BoardService)
		print("  > Action 'rollDice' acknowledged (handled by another system).") -- Debug
		return true
	elseif actionType == "useItem" then
		-- Acknowledge action, logic handled by InventoryService via its own remote
		print("  > Action 'useItem' acknowledged (handled by another system).") -- Debug
		return true
		-- Add other potential turn actions here
	end

	-- Warn if the action type is not recognized
	warn("[TurnSystem] Unhandled action type:", actionType)
	return false
end

-- Handle a player leaving the game
function TurnSystem:HandlePlayerLeaving(playerID)
	print("[TurnSystem] Handling player leaving:", playerID) -- Debug
	local wasCurrentTurn = (playerID == self.currentPlayerTurn)
	local turnIndexBeforeRemoval = self.currentTurnIndex
	local removed = false

	-- Remove the player from the turn order array
	for i = #self.turnOrder, 1, -1 do
		if self.turnOrder[i] == playerID then
			table.remove(self.turnOrder, i)
			removed = true
			print("  > Removed from turn order. New order:", self.turnOrder) -- Debug
			-- Adjust the current index if the removal shifted positions before it
			if i <= turnIndexBeforeRemoval then
				self.currentTurnIndex = math.max(0, turnIndexBeforeRemoval - 1)
				print("  > Adjusted currentTurnIndex to:", self.currentTurnIndex) -- Debug
			end
			break
		end
	end

	-- Clear any related state for the leaving player
	self.skipTurnPlayers[playerID] = nil
	self.turnStates[playerID] = nil
	self.pendingEndTurn[playerID] = nil
	self.deadPlayers[playerID] = nil

	-- If the leaving player was the one whose turn it was
	if wasCurrentTurn then
		print("  > Leaving player was current turn. Ending their turn and moving next.") -- Debug
		-- Stop the timer immediately
		if self.turnTimer then self.turnTimer:Disconnect(); self.turnTimer = nil end
		self.isTurnActive = false
		self.currentPlayerTurn = nil
		-- Move to the next player only if not paused
		if not self.isPaused then
			self:NextTurn()
		else
			print("  > Turn system is paused, not moving to next turn.")
		end
		-- Adjust index if the removal made the current index out of bounds
	elseif #self.turnOrder > 0 and self.currentTurnIndex >= #self.turnOrder then
		self.currentTurnIndex = 0 -- Wrap around or reset (resetting to 0 to prepare for NextTurn increment)
		print("  > Adjusted currentTurnIndex due to removal making it out of bounds.") -- Debug
		-- If no players are left, reset the system
	elseif #self.turnOrder == 0 then
		print("  > Last player left. Resetting turn system.") -- Debug
		self:Reset()
	end
	return true
end

-- NEW: Handle player death
function TurnSystem:OnPlayerDeath(playerID)
	print("[TurnSystem] Player", playerID, "has died. Adjusting turn system...")

	-- Mark the player as dead
	self.deadPlayers[playerID] = true

	-- If it's currently the dead player's turn, end it immediately
	if self.currentPlayerTurn == playerID and self.isTurnActive then
		print("[TurnSystem] Ending turn of dead player", playerID)
		self:EndPlayerTurn(playerID, "player_death")
		return true
	end

	-- Player was not the current turn, so just mark them dead
	print("[TurnSystem] Marked player", playerID, "as dead. They will be skipped in turn rotation.")
	return true
end

-- NEW: Handle player respawn
function TurnSystem:OnPlayerRespawn(playerID)
	print("[TurnSystem] Player", playerID, "has respawned. Adjusting turn system...")

	-- Remove dead state
	self.deadPlayers[playerID] = nil

	-- Check if player exists in turn order
	local isInTurnOrder = false
	for _, id in ipairs(self.turnOrder) do
		if id == playerID then
			isInTurnOrder = true
			break
		end
	end

	-- If player was removed from turn order, add them back
	if not isInTurnOrder then
		table.insert(self.turnOrder, playerID)
		print("[TurnSystem] Added respawned player", playerID, "back to turn order.")
	end

	-- Set player to skip one turn after respawn
	self.skipTurnPlayers[playerID] = 1
	print("[TurnSystem] Player", playerID, "will skip next turn after respawn.")

	return true
end

-- Reset the turn system to its initial state
function TurnSystem:Reset()
	print("[TurnSystem] Resetting Turn System...") -- Debug
	-- Stop the timer if running
	if self.turnTimer then
		self.turnTimer:Disconnect()
		self.turnTimer = nil
	end
	-- Clear all state variables
	self.turnOrder = {}
	self.currentTurnIndex = 0
	self.currentPlayerTurn = nil
	self.isTurnActive = false
	self.turnTimeRemaining = 0
	self.turnStates = {}
	self.skipTurnPlayers = {}
	self.pendingEndTurn = {}
	self.deadPlayers = {}
	self.isPaused = false -- Reset pause state
	self.pausedTurnState = nil
	print("[TurnSystem] Reset complete.") -- Debug
	return true
end

-- NEW: Pause the turn system
function TurnSystem:PauseTurns()
	if self.isPaused then
		print("[TurnSystem] Already paused.")
		return
	end
	print("[TurnSystem] Pausing turns.")
	self.isPaused = true
	-- If a turn is active, stop its timer and store state
	if self.isTurnActive and self.turnTimer then
		self.turnTimer:Disconnect() -- Disconnect stops the Heartbeat connection
		self.turnTimer = nil
		self.pausedTurnState = { playerId = self.currentPlayerTurn, timeRemaining = self.turnTimeRemaining }
		print("  > Stored paused turn state for player", self.pausedTurnState.playerId, "with", self.pausedTurnState.timeRemaining, "s remaining.")
		-- Optionally notify clients that the turn is paused
		if self.remotes and self.remotes.updateTurnTimer then
			self.remotes.updateTurnTimer:FireAllClients("Paused") -- Send a specific state
		end
	end
end

-- NEW: Resume the turn system
function TurnSystem:ResumeTurns()
	if not self.isPaused then
		print("[TurnSystem] Not paused.")
		return
	end
	print("[TurnSystem] Resuming turns.")
	self.isPaused = false
	local pausedState = self.pausedTurnState
	self.pausedTurnState = nil -- Clear paused state

	-- If a turn was active when paused, resume it
	if pausedState and pausedState.playerId then
		local player = Players:GetPlayerByUserId(pausedState.playerId)
		-- Check if the player is still valid and not dead
		if player and not self.deadPlayers[pausedState.playerId] then
			print("  > Resuming turn for player", pausedState.playerId, "with", pausedState.timeRemaining, "s remaining.")
			self.currentPlayerTurn = pausedState.playerId
			self.isTurnActive = true
			self.turnTimeRemaining = pausedState.timeRemaining
			-- Find the correct index for the resumed player
			for i, id in ipairs(self.turnOrder) do
				if id == pausedState.playerId then
					self.currentTurnIndex = i
					break
				end
			end
			self:StartTurnTimer() -- Restart the timer
			-- Notify clients
			if self.remotes and self.remotes.updateTurn then
				self.remotes.updateTurn:FireAllClients(pausedState.playerId)
			end
			if self.remotes and self.remotes.updateTurnTimer then
				self.remotes.updateTurnTimer:FireAllClients(math.floor(pausedState.timeRemaining))
			end
		else
			print("  > Paused player", pausedState.playerId, "is no longer valid or is dead. Moving to next turn.")
			self:NextTurn() -- Move to the next player if the paused one is invalid
		end
	else
		-- If no turn was active, just start the next turn
		print("  > No paused turn state found. Moving to next turn.")
		self:NextTurn()
	end
end


return TurnSystem
