-- GameManager.lua
-- Main module that controls all game logic
-- Version: 3.1.0 (Added Checkpoint System)

local GameManager = {}
GameManager.__index = GameManager

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

-- Constants
local MIN_PLAYERS = 2
local MAX_PLAYERS = 4
local CLASS_SELECTION_TIME = 60

function GameManager.new()
	local self = setmetatable({}, GameManager)

	-- Game state
	self.gameState = {
		isLoading = true,
		isClassSelection = false,
		isGameStarted = false,
		isGameEnded = false,
		currentTurn = 0,
		gameTime = 0,
		selectionTimeLeft = CLASS_SELECTION_TIME
	}

	-- System references
	self.playerManager = nil
	self.classSystem = nil
	self.boardSystem = nil
	self.turnSystem = nil
	self.checkpointSystem = nil

	-- Player tracking
	self.playersReady = {}
	self.playersSelectedClass = {}

	-- Timers
	self.timers = {
		playerCheck = nil,
		classSelection = nil,
		playerCheckTimestamp = 0,
		classSelectionTimestamp = 0
	}

	-- Get remote events
	self.remotes = self:GetRemoteEvents()

	return self
end

function GameManager:GetRemoteEvents()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local gameRemotes = remotes:WaitForChild("GameRemotes")
	local uiRemotes = remotes:WaitForChild("UIRemotes")
	local boardRemotes = remotes:WaitForChild("BoardRemotes")

	-- Check required events
	local function ensureEvent(parent, name)
		local event = parent:FindFirstChild(name)
		if not event then
			warn("Creating missing RemoteEvent:", name, "in", parent.Name)
			event = Instance.new("RemoteEvent", parent)
			event.Name = name
		end
		return event
	end

	return {
		game = {
			startGame = ensureEvent(gameRemotes, "StartGame"),
			endGame = ensureEvent(gameRemotes, "EndGame"),
			updateTurn = ensureEvent(gameRemotes, "UpdateTurn"),
			gameStats = ensureEvent(gameRemotes, "GameStats")
		},
		ui = {
			updateLoading = ensureEvent(uiRemotes, "UpdateLoading"),
			updatePlayersReady = ensureEvent(uiRemotes, "UpdatePlayersReady"),
			showClassSelection = ensureEvent(uiRemotes, "ShowClassSelection"),
			updateClassSelection = ensureEvent(uiRemotes, "UpdateClassSelection"),
			updateClassSelectionTimer = ensureEvent(uiRemotes, "UpdateClassSelectionTimer"),
			notifyRandomClass = ensureEvent(uiRemotes, "NotifyRandomClass"),
			showMainGameUI = ensureEvent(uiRemotes, "ShowMainGameUI")
		},
		board = {
			startPlayerMovementPath = ensureEvent(boardRemotes, "StartPlayerMovementPath"),
			updatePlayerPosition = ensureEvent(boardRemotes, "UpdatePlayerPosition")
		}
	}
end

function GameManager:Initialize()
	-- Check PlayerManager and ClassSystem
	if not self.playerManager or not self.classSystem then
		warn("PlayerManager and ClassSystem must be set before initializing GameManager")
		return
	end

	-- Initialize checkpoint system
	local Modules = ServerStorage:WaitForChild("Modules")
	local success, CheckpointSystem = pcall(function()
		return require(Modules:WaitForChild("CheckpointSystem"))
	end)

	if success and CheckpointSystem then
		self.checkpointSystem = CheckpointSystem.new()
		_G.CheckpointSystem = self.checkpointSystem
		print("[GameManager] CheckpointSystem initialized")
	else
		warn("[GameManager] Failed to load CheckpointSystem module")
	end

	-- Connect player events
	Players.PlayerAdded:Connect(function(player)
		self:OnPlayerAdded(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:OnPlayerRemoving(player)
	end)

	-- Initialize existing players
	for _, player in pairs(Players:GetPlayers()) do
		self:OnPlayerAdded(player)
	end

	-- Start player check
	self:StartPlayerCheck()
end

function GameManager:StartPlayerCheck()
	-- Clear existing timer
	if self.timers.playerCheck then
		self.timers.playerCheck:Disconnect()
		self.timers.playerCheck = nil
	end

	-- Start timestamp tracking
	self.timers.playerCheckTimestamp = tick()

	-- Check player count every second
	self.timers.playerCheck = RunService.Heartbeat:Connect(function()
		-- Calculate elapsed time
		local currentTime = tick()
		local elapsedTime = currentTime - self.timers.playerCheckTimestamp
		if elapsedTime < 1 then return end

		-- Update timestamp
		self.timers.playerCheckTimestamp = currentTime

		-- Skip if game ended
		if self.gameState.isGameEnded then return end

		local playerCount = self.playerManager:GetPlayerCount()
		local readyCount = self:CountReadyPlayers()

		-- Update ready players UI
		self.remotes.ui.updatePlayersReady:FireAllClients(readyCount, playerCount)

		-- Check game start conditions
		if not self.gameState.isGameStarted then
			if playerCount >= MIN_PLAYERS then
				if self.gameState.isLoading then
					if self:AreAllPlayersReady() and playerCount > 0 then
						self:FinishLoading()
					end
				end
			end
		else
			-- Check remaining players
			if playerCount < MIN_PLAYERS then
				self:EndGame("Not enough players to continue (minimum " .. MIN_PLAYERS .. " required)")
			end
		end
	end)
end

function GameManager:CountReadyPlayers()
	local readyCount = 0
	for _, isReady in pairs(self.playersReady) do
		if isReady then readyCount = readyCount + 1 end
	end
	return readyCount
end

function GameManager:AreAllPlayersReady()
	local playerCount = self.playerManager:GetPlayerCount()
	if playerCount == 0 then return false end
	for _, player in pairs(Players:GetPlayers()) do
		if not self.playersReady[player.UserId] then
			return false
		end
	end
	return true
end


function GameManager:HaveAllPlayersSelectedClass()
	for _, player in pairs(Players:GetPlayers()) do
		if not self.playersSelectedClass[player.UserId] then
			return false
		end
	end
	return true
end

function GameManager:OnPlayerAdded(player)
	-- Register player
	self.playerManager:RegisterPlayer(player)

	-- Set ready status
	self.playersReady[player.UserId] = false

	-- Show loading screen
	self.remotes.ui.updateLoading:FireClient(player, 0)

	-- Update player counts
	local playerCount = self.playerManager:GetPlayerCount()
	local readyCount = self:CountReadyPlayers()
	self.remotes.ui.updatePlayersReady:FireAllClients(readyCount, playerCount)
end

function GameManager:OnPlayerReady(player)
	-- Set player as ready
	self.playersReady[player.UserId] = true

	-- Count ready players
	local readyCount = self:CountReadyPlayers()
	local playerCount = self.playerManager:GetPlayerCount()

	-- Update loading UI
	local progress = 0
	if playerCount > 0 then
		progress = readyCount / playerCount
	end
	self.remotes.ui.updateLoading:FireAllClients(progress)
	self.remotes.ui.updatePlayersReady:FireAllClients(readyCount, playerCount)

	-- Check for transition
	if self:AreAllPlayersReady() and playerCount >= MIN_PLAYERS and self.gameState.isLoading then
		self:FinishLoading()
	end
end

function GameManager:FinishLoading()
	-- Change from loading to class selection
	self.gameState.isLoading = false
	self.gameState.isClassSelection = true

	-- Show class selection UI
	self.remotes.ui.showClassSelection:FireAllClients()

	-- Start class selection timeout
	self:StartClassSelectionTimeout()
end

function GameManager:StartClassSelectionTimeout()
	-- Reset timer
	self.gameState.selectionTimeLeft = CLASS_SELECTION_TIME

	-- Clear existing timer
	if self.timers.classSelection then
		self.timers.classSelection:Disconnect()
		self.timers.classSelection = nil
	end

	-- Start timestamp tracking
	self.timers.classSelectionTimestamp = tick()

	-- Send initial timer to clients
	self.remotes.ui.updateClassSelectionTimer:FireAllClients(self.gameState.selectionTimeLeft)

	-- Start timer
	self.timers.classSelection = RunService.Heartbeat:Connect(function()
		-- Calculate elapsed time
		local currentTime = tick()
		local elapsedTime = currentTime - self.timers.classSelectionTimestamp
		if elapsedTime < 1 then return end

		-- Update timestamp
		self.timers.classSelectionTimestamp = currentTime

		-- Skip if not in class selection or game ended
		if not self.gameState.isClassSelection or self.gameState.isGameEnded then
			if self.timers.classSelection then
				self.timers.classSelection:Disconnect()
				self.timers.classSelection = nil
			end
			return
		end

		-- Decrease timer
		self.gameState.selectionTimeLeft = self.gameState.selectionTimeLeft - 1
		local timeLeft = self.gameState.selectionTimeLeft
		if timeLeft < 0 then timeLeft = 0 end

		-- Update timer for all clients
		self.remotes.ui.updateClassSelectionTimer:FireAllClients(timeLeft)

		-- Check if all players selected
		if self:HaveAllPlayersSelectedClass() then
			if self.timers.classSelection then
				self.timers.classSelection:Disconnect()
				self.timers.classSelection = nil
			end
			task.wait(1.5)
			if not self.gameState.isGameStarted then
				self:StartGame()
			end
			return
		end

		-- Time's up
		if timeLeft <= 0 then
			if self.timers.classSelection then
				self.timers.classSelection:Disconnect()
				self.timers.classSelection = nil
			end

			-- Randomly assign class to remaining players
			for _, player in pairs(Players:GetPlayers()) do
				if not self.playersSelectedClass[player.UserId] then
					local randomClass = self.classSystem:GetRandomClass()
					self:OnPlayerSelectedClass(player, randomClass)
					self.remotes.ui.notifyRandomClass:FireClient(player, randomClass)
				end
			end

			task.wait(3)
			if not self.gameState.isGameStarted then
				self:StartGame()
			end
		end
	end)
end

function GameManager:OnPlayerSelectedClass(player, selectedClass)
	-- Store class selection
	self.playersSelectedClass[player.UserId] = selectedClass

	-- Assign class
	self.classSystem:AssignClassToPlayer(player, selectedClass)

	-- Update UI
	self.remotes.ui.updateClassSelection:FireAllClients(player.UserId, selectedClass)

	-- Check if all selected and still in class selection phase
	if self.gameState.isClassSelection and self:HaveAllPlayersSelectedClass() then
		if self.timers.classSelection then
			self.timers.classSelection:Disconnect()
			self.timers.classSelection = nil
		end

		task.wait(2)
		if not self.gameState.isGameStarted then
			self:StartGame()
		end
	end
end

function GameManager:StartGame()
	-- Prevent duplicate game start
	if self.gameState.isGameStarted then
		print("Game already started, skipping StartGame call.")
		return
	end

	local playerCount = self.playerManager:GetPlayerCount()

	-- Check player count
	if playerCount < MIN_PLAYERS then
		warn("Cannot start game, not enough players:", playerCount, "Minimum:", MIN_PLAYERS)
		return
	end

	print("Starting game...")
	-- Update game state
	self.gameState.isClassSelection = false
	self.gameState.isGameStarted = true
	self.gameState.isLoading = false -- Ensure loading is false

	-- Show main game UI
	self.remotes.ui.showMainGameUI:FireAllClients()
	self.remotes.game.startGame:FireAllClients()

	-- Initialize player positions and visuals
	self:InitializePlayerPositions()

	-- Start turn system
	if self.turnSystem then
		self.turnSystem:CreateTurnOrderFromActivePlayers(self.playerManager)
		self.turnSystem:StartTurnSystem()
		self.gameState.currentTurn = 1
		print("Turn system started. Current turn:", self.gameState.currentTurn)
	else
		warn("TurnSystem not available!")
	end

	-- Start game timer
	self:StartGameTimer()
	print("Game started successfully.")
end

function GameManager:InitializePlayerPositions()
	if not self.boardSystem then
		warn("BoardSystem not found in InitializePlayerPositions")
		return false
	end

	print("Initializing player positions...")
	local startTileId = 1 -- Start tile is 1

	-- Get tile position
	local tilePosition = nil
	local tilesFolder = Workspace:FindFirstChild("BoardTiles")
	if tilesFolder then
		local tilePart = tilesFolder:FindFirstChild("Tile" .. startTileId) or tilesFolder:FindFirstChild(tostring(startTileId))
		if tilePart and tilePart:IsA("BasePart") then
			tilePosition = tilePart.Position
			print("Found start tile position:", tilePosition)
		else
			warn("Could not find tile part for tile ID:", startTileId)
		end
	else
		warn("BoardTiles folder not found in workspace!")
	end

	-- If position not found, use default from MapData
	if not tilePosition then
		-- Try to get from MapData
		local MapData = require(game:GetService("ServerStorage").GameData.MapData)
		if MapData and MapData.tiles and MapData.tiles[startTileId] and MapData.tiles[startTileId].position then
			tilePosition = MapData.tiles[startTileId].position
			print("Using MapData position for tile ID:", startTileId, tilePosition)
		else
			-- Use hardcoded position if no data found
			tilePosition = Vector3.new(35.778, 0.6, -15.24) -- Default position from MapData
			print("Using hardcoded position for tile ID:", startTileId, tilePosition)
		end
	end

	for _, player in pairs(Players:GetPlayers()) do
		local playerId = player.UserId

		-- 1. Set logical position in BoardSystem
		self.boardSystem:SetPlayerPosition(playerId, startTileId, nil)
		print("Set logical position for player", playerId, "to tile", startTileId)

		-- 2. Warp character to start position directly
		local character = player.Character
		if character then
			local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
			if humanoidRootPart and tilePosition then
				-- Teleport character directly to start position
				humanoidRootPart.CFrame = CFrame.new(tilePosition + Vector3.new(0, 3, 0))
				print("Directly teleported player", playerId, "to start position")
			else
				warn("Could not teleport player", playerId, "- missing HumanoidRootPart or tile position")
			end
		else
			warn("Player character not found for player:", playerId)
			-- Wait for character to spawn (if not spawned)
			player.CharacterAdded:Connect(function(newCharacter)
				local humanoidRootPart = newCharacter:WaitForChild("HumanoidRootPart", 5)
				if humanoidRootPart and tilePosition then
					humanoidRootPart.CFrame = CFrame.new(tilePosition + Vector3.new(0, 3, 0))
					print("Teleported newly spawned character for player", playerId, "to start position")
				end
			end)
		end

		-- 3. Send Event so Client knows where player is (UI updates)
		local initialMovementData = {
			path = {startTileId},
			directions = nil,
			requiresConfirmation = false
		}

		-- Send event to everyone to update UI
		self.remotes.board.updatePlayerPosition:FireAllClients(playerId, startTileId)
		print("Fired UpdatePlayerPosition for player", playerId)

		-- Send event to specific player to update UI
		self.remotes.board.startPlayerMovementPath:FireClient(player, playerId, initialMovementData)
		print("Fired StartPlayerMovementPath for player", playerId)
	end

	print("Player positions initialized.")
	return true
end

function GameManager:StartGameTimer()
	local lastUpdateTime = tick()

	-- Use task.spawn to avoid blocking main thread
	task.spawn(function()
		while self.gameState.isGameStarted and not self.gameState.isGameEnded do
			local currentTime = tick()
			local elapsed = currentTime - lastUpdateTime

			if elapsed >= 1 then
				lastUpdateTime = currentTime
				self.gameState.gameTime = self.gameState.gameTime + 1
				-- print("Game Time:", self.gameState.gameTime) -- Optional: Print game time
			end

			task.wait(0.2)
		end
		print("Game timer stopped.")
	end)
end

function GameManager:CheckWinCondition()
	-- Check player count
	local activePlayers = self.playerManager:GetPlayerCount()
	if activePlayers <= 1 and self.gameState.isGameStarted then
		-- Find last player
		local lastPlayer = nil
		for _, player in pairs(Players:GetPlayers()) do
			lastPlayer = player
			break
		end

		if lastPlayer then
			self:EndGame(lastPlayer.Name .. " wins! (Last player remaining)")
			return true
		else -- Case when no players remain
			self:EndGame("Game ended. No players remaining.")
			return true
		end
	end

	-- Check turn count
	if self.gameState.currentTurn >= 30 and self.gameState.isGameStarted then
		local richestPlayer = nil
		local highestMoney = -1 -- Start at -1 so first player with money > -1 can be winner

		for _, player in pairs(Players:GetPlayers()) do
			local playerData = self.playerManager:GetPlayerData(player)
			if playerData and playerData.stats and playerData.stats.money > highestMoney then
				richestPlayer = player
				highestMoney = playerData.stats.money
			end
		end

		if richestPlayer then
			self:EndGame(richestPlayer.Name .. " wins with " .. highestMoney .. " coins! (Turn limit reached)")
			return true
		else -- Case when no one has money
			self:EndGame("Game ended. Turn limit reached, but no winner found based on money.")
			return true
		end
	end

	return false
end

function GameManager:OnPlayerRemoving(player)
	local playerId = player.UserId
	print("Player removing:", player.Name, "(ID:", playerId, ")")

	-- Remove player data
	self.playerManager:UnregisterPlayer(player)
	self.playersReady[playerId] = nil
	self.playersSelectedClass[playerId] = nil

	-- If game started, let TurnSystem handle player leave
	if self.gameState.isGameStarted and self.turnSystem then
		self.turnSystem:HandlePlayerLeave(playerId)
	end

	-- Update player count UI
	local playerCount = self.playerManager:GetPlayerCount()
	local readyCount = self:CountReadyPlayers()
	self.remotes.ui.updatePlayersReady:FireAllClients(readyCount, playerCount)

	-- Check end game conditions only if the game has started
	if self.gameState.isGameStarted then
		-- Check if enough players remain immediately after removal
		if playerCount < MIN_PLAYERS then
			self:EndGame("Not enough players remaining (only " .. playerCount .. " left)")
		else
			-- Check win condition (e.g., if the leaving player was the only opponent)
			self:CheckWinCondition()
		end
	end
end


function GameManager:EndGame(reason)
	-- Prevent duplicate game end
	if self.gameState.isGameEnded then
		print("Game already ended, skipping EndGame call. Reason:", reason)
		return
	end

	print("Ending game. Reason:", reason)
	-- Update game state
	self.gameState.isGameEnded = true
	self.gameState.isGameStarted = false
	self.gameState.isClassSelection = false
	self.gameState.isLoading = false

	-- Cancel timers
	if self.timers.playerCheck then
		self.timers.playerCheck:Disconnect()
		self.timers.playerCheck = nil
		print("Player check timer stopped.")
	end

	if self.timers.classSelection then
		self.timers.classSelection:Disconnect()
		self.timers.classSelection = nil
		print("Class selection timer stopped.")
	end

	-- Reset turn system
	if self.turnSystem then
		self.turnSystem:Reset()
		print("Turn system reset.")
	end

	-- Notify all clients
	self.remotes.game.endGame:FireAllClients(reason)
	print("EndGame event fired to clients.")

	-- Show stats after a short delay
	task.delay(2, function()
		self:ShowGameStats(reason)
	end)
end

function GameManager:ShowGameStats(reason)
	print("Showing game stats...")
	-- Create stats data
	local gameStats = {
		reason = reason,
		totalTurns = self.gameState.currentTurn,
		gameDuration = self.gameState.gameTime,
		playerStats = {}
	}

	-- Collect player stats from PlayerManager (safer)
	local allPlayerData = self.playerManager:GetAllPlayerData()
	for playerId, playerData in pairs(allPlayerData) do
		local player = Players:GetPlayerByUserId(playerId)
		if player then -- Check if player is still in game
			table.insert(gameStats.playerStats, {
				playerName = player.Name,
				playerId = playerId,
				level = playerData.stats and playerData.stats.level or 1,
				money = playerData.stats and playerData.stats.money or 0,
				class = playerData.class or "Unknown"
			})
		else
			-- Optionally add data for players who left
			-- table.insert(gameStats.playerStats, { playerName = "Player Left ("..playerId..")", ... })
		end
	end

	-- Sort by money
	table.sort(gameStats.playerStats, function(a, b)
		return (a.money or 0) > (b.money or 0)
	end)

	-- Send stats
	self.remotes.game.gameStats:FireAllClients(gameStats)
	print("GameStats event fired to clients.")
end


function GameManager:ResetGame()
	print("Resetting game...")
	-- Reset game state
	self.gameState = {
		isLoading = true,
		isClassSelection = false,
		isGameStarted = false,
		isGameEnded = false,
		currentTurn = 0,
		gameTime = 0,
		selectionTimeLeft = CLASS_SELECTION_TIME
	}

	-- Clear data
	self.playersReady = {}
	self.playersSelectedClass = {}

	-- Cancel timers if they are still running
	if self.timers.playerCheck then
		self.timers.playerCheck:Disconnect()
		self.timers.playerCheck = nil
	end
	if self.timers.classSelection then
		self.timers.classSelection:Disconnect()
		self.timers.classSelection = nil
	end

	-- Reset systems that need resetting
	if self.turnSystem then self.turnSystem:Reset() end
	if self.boardSystem then
		-- May need to clear playerPositions in boardSystem
		-- self.boardSystem:ClearAllPlayerPositions() -- Assuming this function exists
	end

	-- Reset checkpoint system if it exists
	if self.checkpointSystem then
		self.checkpointSystem:ResetAllCheckpoints()
		print("Checkpoint system reset.")
	end

	-- Reset players currently in the server
	for _, player in pairs(Players:GetPlayers()) do
		-- Re-register player (might not be necessary if PlayerManager doesn't delete data on Reset)
		-- self.playerManager:RegisterPlayer(player)
		self.playersReady[player.UserId] = false
		-- Send loading screen again
		self.remotes.ui.updateLoading:FireClient(player, 0)
		-- May need to kick players or send to Lobby UI instead
	end

	-- Restart the initial player check loop
	self:StartPlayerCheck()
	print("Game reset complete. Waiting for players...")
end


return GameManager
