-- BoardService.server.lua
-- Server-side service for board system management
-- Version: 3.8.0 (Added Combat Initiation Trigger)

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Load required modules
local Modules = ServerStorage:WaitForChild("Modules")
local BoardSystem = require(Modules:WaitForChild("BoardSystem"))
local MapData = require(ServerStorage.GameData.MapData)
-- Combat Service (will be loaded/referenced later)
local CombatService = nil

-- Enable debug mode
local DEBUG_MOVEMENT = true
local TRUST_CLIENT_DICE = true -- Trust dice roll values from client

-- Create required RemoteEvents
local function ensureRemoteEvents()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local boardRemotes = remotes:WaitForChild("BoardRemotes")

	local requiredEvents = {
		"RollDice",
		"PlayerArrivedAtTile",
		"ChoosePath",
		"TileTriggerEvent",
		"ActivityComplete",
		"StartPlayerMovementPath",
		"MovementVisualizationComplete",
		"UpdatePlayerPosition" -- Added for respawn/teleport updates
	}

	for _, eventName in ipairs(requiredEvents) do
		if not boardRemotes:FindFirstChild(eventName) then
			Instance.new("RemoteEvent", boardRemotes).Name = eventName
		end
	end

	-- Create ShowPathSelection for backwards compatibility
	if not boardRemotes:FindFirstChild("ShowPathSelection") then
		Instance.new("RemoteEvent", boardRemotes).Name = "ShowPathSelection"
	end

	return remotes
end

-- Constants
local DIRECTIONS = { FRONT = "FRONT", LEFT = "LEFT", RIGHT = "RIGHT" }

-- Get GameManager from global variable
local function getGameManager()
	local startTime = tick()
	while not _G.GameManager and tick() - startTime < 10 do
		task.wait(0.1)
	end
	return _G.GameManager
end

-- Get DiceBonusService
local function getDiceBonusService()
	if _G.DiceBonusService then
		return _G.DiceBonusService
	end

	local gameManager = getGameManager()
	if gameManager and gameManager.diceBonusService then
		return gameManager.diceBonusService
	end

	return nil
end

-- Get CombatService (Lazy Load)
local function getCombatService()
	if not CombatService then
		local gameManager = getGameManager()
		CombatService = gameManager and gameManager.combatService
		if not CombatService then
			warn("[BoardService] CombatService not found in GameManager!")
		end
	end
	return CombatService
end


-- Store movement completion state
local pendingMovementCompletions = {}

-- Storage for player dice bonuses (redundant for error prevention)
local playerDiceBonus = {}

-- Main service initialization function
local function initializeBoardService()
	local remotes = ensureRemoteEvents()
	local boardSystem = BoardSystem.new()

	-- Load Map
	if not MapData then
		boardSystem:LoadMap({tiles={[1]={type="start", position=Vector3.new(0,0,0)}}, connections={}})
	else
		boardSystem:LoadMap(MapData)
	end

	local gameManager = getGameManager()
	if not gameManager then
		warn("[BoardService] GameManager not found during initialization!")
		return nil -- Cannot proceed without GameManager
	end
	gameManager.boardSystem = boardSystem -- Assign boardSystem to GameManager

	-- Set up callbacks
	boardSystem:SetupCallbacks(
		-- onPlayerMoved
		function(playerId, fromTileId, toTileId)
			if DEBUG_MOVEMENT then
				print("[BoardService] Player " .. playerId .. " moved from tile " ..
					(fromTileId or "nil") .. " to tile " .. toTileId)
			end
			-- Fire event to update position on all clients
			local boardRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BoardRemotes")
			boardRemotes:WaitForChild("UpdatePlayerPosition"):FireAllClients(playerId, toTileId)
		end,

		-- onPlayerPathComplete
		function(playerId, finalTileId)
			local boardRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BoardRemotes")
			boardRemotes:WaitForChild("PlayerArrivedAtTile"):FireAllClients(playerId, finalTileId)

			if DEBUG_MOVEMENT then
				print("[BoardService] Player " .. playerId .. " completed path calculation at tile " .. finalTileId)
			end

			local player = Players:GetPlayerByUserId(playerId)
			if player then
				pendingMovementCompletions[playerId] = {
					finalTileId = finalTileId,
					timestamp = os.time(),
					confirmed = false
				}

				task.spawn(function()
					task.wait(30) -- Timeout 30 seconds
					if pendingMovementCompletions[playerId] and not pendingMovementCompletions[playerId].confirmed then
						pendingMovementCompletions[playerId].confirmed = true -- Consider confirmed on timeout

						if DEBUG_MOVEMENT then
							print("[BoardService] Movement confirmation timed out for player " .. playerId)
						end

						-- Trigger Tile Effect on timeout
						local tileInfo = boardSystem:GetTileInfo(finalTileId)
						if tileInfo then
							local boardRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BoardRemotes")
							boardRemotes:WaitForChild("TileTriggerEvent"):FireAllClients(playerId, finalTileId, tileInfo.type)
							if DEBUG_MOVEMENT then
								print("[BoardService] Tile effect triggered (timeout) for player " .. playerId ..
									" at tile " .. finalTileId .. " (type: " .. tileInfo.type .. ")")
							end
						end

						-- Check for combat initiation on timeout as well
						local playersOnTile = boardSystem:GetPlayersOnTile(finalTileId)
						if #playersOnTile >= 2 then
							local combatService = getCombatService()
							if combatService and not combatService:IsCombatActive() then
								local player1 = Players:GetPlayerByUserId(playersOnTile[1])
								local player2 = Players:GetPlayerByUserId(playersOnTile[2])
								if player1 and player2 then
									print("[BoardService] Initiating combat due to timeout on shared tile " .. finalTileId)
									combatService:InitiatePreCombat(player1, player2, finalTileId)
								end
							end
						end

						-- End turn if still same player and not in combat
						local combatService = getCombatService()
						if gameManager.turnSystem and playerId == gameManager.turnSystem:GetCurrentPlayerTurn() and (not combatService or not combatService:IsCombatActive()) then
							gameManager.turnSystem:EndPlayerTurn(playerId, "move_timeout")
						end
						-- Clear pending data
						pendingMovementCompletions[playerId] = nil
					end
				end)
			else
				-- If player not found (left game), end turn immediately if they were the current player
				if gameManager.turnSystem and gameManager.turnSystem:GetCurrentPlayerTurn() == playerId then
					task.wait(0.5) -- Short delay
					gameManager.turnSystem:EndPlayerTurn(playerId, "player_left")
				end
			end
		end
	)

	-- Function to record dice bonuses (Same as before)
	local inventoryRemotes = remotes:WaitForChild("InventoryRemotes")
	if inventoryRemotes:FindFirstChild("DiceBonus") then
		inventoryRemotes.DiceBonus.OnServerEvent:Connect(function(player, bonusAmount)
			if player then
				playerDiceBonus[player.UserId] = bonusAmount
				-- print("[BoardService] Saved dice bonus " .. bonusAmount .. " for player " .. player.Name)
			end
		end)
	end

	-- Set up bidirectional RollDice remote event (Same as before, with combat check)
	local boardRemotes = remotes:WaitForChild("BoardRemotes")
	local rollDiceRemote = boardRemotes:WaitForChild("RollDice")

	rollDiceRemote.OnServerEvent:Connect(function(player, diceResult, isFixedMovement)
		local playerId = player.UserId

		-- Check if combat is active first
		local combatService = getCombatService()
		if combatService and combatService:IsCombatActive() then
			if DEBUG_MOVEMENT then print("[BoardService] Rejected dice roll from player " .. playerId .. " - Combat Active") end
			return
		end

		-- Check turn and other conditions (Same as before)
		if not gameManager or not gameManager.turnSystem then return end
		if gameManager.turnSystem:GetCurrentPlayerTurn() ~= playerId then
			if DEBUG_MOVEMENT then print("[BoardService] Rejected dice roll from player " .. playerId .. " - not their turn") end
			return
		end

		local isFixed = isFixedMovement == true
		local finalDiceResult = diceResult

		if isFixed then
			print("[BoardService] Player " .. player.Name .. " is using a Crystal for fixed movement: " .. finalDiceResult)
		else
			local diceBonusService = getDiceBonusService()
			local diceBonus = playerDiceBonus[playerId] or 0
			if diceBonus == 0 and diceBonusService then
				diceBonus = diceBonusService.GetPlayerDiceBonus(playerId) or 0
				if diceBonus > 0 then playerDiceBonus[playerId] = diceBonus end
			end
			print("[BoardService] Player " .. player.Name .. " rolled " .. finalDiceResult .. " (Bonus dice: " .. diceBonus .. ")")
			-- Validation (Same as before)
			if not TRUST_CLIENT_DICE then
				local minPossibleResult = 1 + diceBonus
				local maxPossibleResult = 6 + (diceBonus * 6)
				if finalDiceResult < minPossibleResult or finalDiceResult > maxPossibleResult then
					warn("[BoardService] Invalid dice result from player " .. player.Name .. ": " .. finalDiceResult)
					local baseDiceRoll = math.random(1, 6)
					finalDiceResult = baseDiceRoll
					for i = 1, diceBonus do finalDiceResult = finalDiceResult + math.random(1, 6) end
					print("[BoardService] Using server-generated dice result instead: " .. finalDiceResult)
				end
			else
				if finalDiceResult < 1 then finalDiceResult = 1 end
				if finalDiceResult > 100 then finalDiceResult = 12 end
			end
		end

		-- Process movement (Same as before)
		local moveInfo = boardSystem:ProcessPlayerMove(playerId, finalDiceResult)
		if moveInfo and moveInfo.autoPath and #moveInfo.autoPath > 0 then
			local movementData = {
				path = moveInfo.autoPath,
				directions = moveInfo.requiresChoice and moveInfo.availableDirections or nil,
				requiresConfirmation = true
			}
			if DEBUG_MOVEMENT then print("[BoardService] Sending movement path to player " .. playerId .. " (Length: " .. #moveInfo.autoPath .. ")") end
			boardRemotes.StartPlayerMovementPath:FireClient(player, playerId, movementData)
		else
			if gameManager.turnSystem:GetCurrentPlayerTurn() == playerId then
				if DEBUG_MOVEMENT then print("[BoardService] No movement for player " .. playerId .. ", ending turn") end
				gameManager.turnSystem:EndPlayerTurn(playerId, "no_move")
			end
		end

		-- Reset and clear dice bonus (Same as before)
		playerDiceBonus[playerId] = nil
		if not isFixed and diceBonus > 0 then
			local diceBonusService = getDiceBonusService()
			if diceBonusService then diceBonusService.ClearPlayerDiceBonus(playerId) end
			if gameManager.inventoryService and gameManager.inventoryService.ResetDiceBonusUse then
				gameManager.inventoryService.ResetDiceBonusUse(playerId)
			end
		end
	end)

	-- Server can now send to client for crystal fixed movement (Same as before)
	_G.SendFixedMovement = function(player, fixedValue)
		if player and fixedValue and typeof(fixedValue) == "number" then
			rollDiceRemote:FireClient(player, fixedValue, true)
			return true
		end
		return false
	end

	-- Handle path selection (Same as before, with combat check)
	boardRemotes.ChoosePath.OnServerEvent:Connect(function(player, direction)
		local playerId = player.UserId

		-- Check combat active
		local combatService = getCombatService()
		if combatService and combatService:IsCombatActive() then
			if DEBUG_MOVEMENT then print("[BoardService] Rejected path choice from player " .. playerId .. " - Combat Active") end
			return
		end

		-- Check turn (Same as before)
		if not gameManager or not gameManager.turnSystem then return end
		if gameManager.turnSystem:GetCurrentPlayerTurn() ~= playerId then
			if DEBUG_MOVEMENT then print("[BoardService] Rejected path choice from player " .. playerId .. " - not their turn") end
			return
		end

		if DEBUG_MOVEMENT then print("[BoardService] Player " .. playerId .. " chose direction: " .. direction) end

		-- Process direction choice (Same as before)
		local moveResult = boardSystem:ProcessDirectionChoice(playerId, direction)
		if moveResult and moveResult.autoPath and #moveResult.autoPath > 0 then
			local movementData = {
				path = moveResult.autoPath,
				directions = moveResult.requiresChoice and moveResult.availableDirections or nil,
				requiresConfirmation = true
			}
			if DEBUG_MOVEMENT then print("[BoardService] Sending movement path after direction choice (Length: " .. #moveResult.autoPath .. ")") end
			boardRemotes.StartPlayerMovementPath:FireClient(player, playerId, movementData)
		else
			if gameManager.turnSystem:GetCurrentPlayerTurn() == playerId then
				if DEBUG_MOVEMENT then print("[BoardService] Invalid direction choice from player " .. playerId .. ", ending turn") end
				gameManager.turnSystem:EndPlayerTurn(playerId, "invalid_choice")
			end
		end
	end)

	-- Handle movement completion confirmation from client (Includes Combat Initiation)
	boardRemotes.MovementVisualizationComplete.OnServerEvent:Connect(function(player, finalTileId)
		local playerId = player.UserId

		-- Check pending confirmation (Same as before)
		if not pendingMovementCompletions[playerId] then
			if DEBUG_MOVEMENT then print("[BoardService] Received movement completion from player " .. playerId .. " but no pending confirmation found.") end
			return
		end

		-- Check player validity (Same as before)
		local currentPlayer = Players:GetPlayerByUserId(playerId)
		if not currentPlayer or not boardSystem.playerPositions[playerId] then
			if DEBUG_MOVEMENT then print("[BoardService] Player " .. playerId .. " left or data cleaned up, skipping movement completion.") end
			pendingMovementCompletions[playerId] = nil
			return
		end

		if DEBUG_MOVEMENT then print("[BoardService] Player " .. playerId .. " confirmed movement visualization complete at tile " .. finalTileId) end

		-- Set confirmed (Same as before)
		pendingMovementCompletions[playerId].confirmed = true

		-- Check if combat is active (Safety check)
		local combatService = getCombatService()
		if combatService and combatService:IsCombatActive() then
			if DEBUG_MOVEMENT then print("[BoardService] Combat is active, skipping tile effects and turn end logic.") end
			pendingMovementCompletions[playerId] = nil
			return
		end

		-- *** COMBAT INITIATION CHECK ***
		local playersOnTile = boardSystem:GetPlayersOnTile(finalTileId)
		if #playersOnTile >= 2 then
			if combatService and not combatService:IsCombatActive() then
				local player1 = Players:GetPlayerByUserId(playersOnTile[1])
				local player2 = Players:GetPlayerByUserId(playersOnTile[2])
				-- Ensure the current player is one of the players involved
				if player1 and player2 and (player1.UserId == playerId or player2.UserId == playerId) then
					print("[BoardService] Initiating combat on shared tile " .. finalTileId)
					local combatInitiated = combatService:InitiatePreCombat(player1, player2, finalTileId)
					if combatInitiated then
						pendingMovementCompletions[playerId] = nil -- Clear pending state as combat handles flow
						return -- Stop further processing
					else
						print("[BoardService] Combat initiation failed.")
					end
				end
			else
				-- print("[BoardService] CombatService not available or combat already active. Skipping initiation.")
			end
		end
		-- *** END COMBAT INITIATION CHECK ***

		-- Trigger Tile Effect (Only if not in combat)
		local tileInfo = boardSystem:GetTileInfo(finalTileId)
		if tileInfo then
			local tileType = tileInfo.type
			boardRemotes:WaitForChild("TileTriggerEvent"):FireAllClients(playerId, finalTileId, tileType)
			-- Checkpoint System Integration (Same as before)
			local checkpointSystem = gameManager and gameManager.checkpointSystem or _G.CheckpointSystem
			if checkpointSystem and checkpointSystem.OnPlayerLandedOnTile then
				checkpointSystem:OnPlayerLandedOnTile(player, finalTileId, tileType)
			end
			if DEBUG_MOVEMENT then print("[BoardService] Tile effect triggered for player " .. playerId .. " at tile " .. finalTileId .. " (type: " .. tileType .. ")") end
		end

		-- End turn logic (Only if not in combat)
		if gameManager.turnSystem then
			local currentTurnPlayerId = gameManager.turnSystem:GetCurrentPlayerTurn()
			if playerId == currentTurnPlayerId then
				local currentMovementState = boardSystem.playerMovementState[playerId]
				local currentRemainingSteps = boardSystem.playerRemainingSteps[playerId]

				if currentMovementState == nil or currentRemainingSteps == nil then
					if DEBUG_MOVEMENT then print("[BoardService] Warning: Player state or remaining steps is nil for player " .. playerId) end
				else
					local hasChoices = currentMovementState == "need_choice"
					if DEBUG_MOVEMENT then
						print("[BoardService] Player " .. playerId .. " movement state: " .. currentMovementState)
						print("  Has more choices: " .. tostring(hasChoices))
						print("  Steps remaining: " .. currentRemainingSteps)
					end
					if not hasChoices then
						task.wait(0.5) -- Wait for animations
						if gameManager.turnSystem:GetCurrentPlayerTurn() == playerId then -- Re-check turn
							if DEBUG_MOVEMENT then print("[BoardService] Ending turn for player " .. playerId .. " after complete movement.") end
							gameManager.turnSystem:EndPlayerTurn(playerId, "move_complete")
						else
							if DEBUG_MOVEMENT then print("[BoardService] Turn changed before ending for player " .. playerId) end
						end
					end
				end
			else
				if DEBUG_MOVEMENT then print("[BoardService] Movement complete for player " .. playerId .. ", but it's not their turn anymore.") end
			end
		else
			warn("[BoardService] TurnSystem not available when trying to end turn.")
		end

		-- Clear pending confirmation (Important: Do this last)
		pendingMovementCompletions[playerId] = nil
	end)

	return boardSystem
end

-- Initialize service
local boardSystemInstance = initializeBoardService()
if boardSystemInstance then
	_G.BoardSystem = boardSystemInstance -- Store instance in Global if successful
	print("[BoardService] Initialized successfully.")
else
	warn("[BoardService] Initialization failed.")
end

return boardSystemInstance
