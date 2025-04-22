-- TurnService.server.lua
-- Service for managing turn system and player order
-- Version: 3.0.0 (Optimized)

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Load modules
local TurnSystem = require(ServerStorage.Modules.TurnSystem)

-- Create service object
local TurnService = {}

-- Get other services
local function getGameManager()
	local startTime = tick()
	while not _G.GameManager and tick() - startTime < 10 do
		wait(0.1)
	end
	return _G.GameManager
end

local function getPlayerManager()
	local gameManager = getGameManager()
	return gameManager and gameManager.playerManager
end

local function getBoardSystem()
	local gameManager = getGameManager()
	return gameManager and gameManager.boardSystem
end

-- Initialize service
function TurnService:Initialize()
	-- Create turn system
	local turnSystem = TurnSystem.new()

	-- Get Remote Events
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local gameRemotes = remotes:WaitForChild("GameRemotes")
	local uiRemotes = remotes:WaitForChild("UIRemotes")

	-- Setup remote events
	turnSystem:InitializeRemotes(gameRemotes)

	-- Get GameManager
	local gameManager = getGameManager()
	if not gameManager then
		spawn(function()
			wait(5)
			TurnService:Initialize()
		end)
		return nil
	end

	-- Setup GameManager
	gameManager.turnSystem = turnSystem

	-- Create necessary RemoteEvent
	if not uiRemotes:FindFirstChild("UpdateTurnDetails") then
		local updateTurnDetailsEvent = Instance.new("RemoteEvent")
		updateTurnDetailsEvent.Name = "UpdateTurnDetails"
		updateTurnDetailsEvent.Parent = uiRemotes
	end

	-- Setup event handlers

	-- When turn starts
	turnSystem.onTurnStart = function(playerID)
		-- Create UI data
		local player = Players:GetPlayerByUserId(playerID)
		if player then
			local playerManager = getPlayerManager()
			local playerData = playerManager and playerManager:GetPlayerData(player)

			-- Send additional data to all clients
			uiRemotes:WaitForChild("UpdateTurnDetails"):FireAllClients({
				playerId = playerID,
				playerName = player.Name,
				turnNumber = gameManager.gameState.currentTurn or 1,
				playerClass = playerData and playerData.class or "Unknown",
				playerLevel = playerData and playerData.stats and playerData.stats.level or 1
			})
		end
	end

	-- When turn ends
	turnSystem.onTurnEnd = function(playerID, reason)
		-- Update game state
		if gameManager.gameState.currentTurn then
			gameManager.gameState.currentTurn = gameManager.gameState.currentTurn + 1
		else
			gameManager.gameState.currentTurn = 1
		end
	end

	-- Connect to player leave event
	Players.PlayerRemoving:Connect(function(player)
		turnSystem:HandlePlayerLeaving(player.UserId)
	end)

	-- Connect to game start event
	gameRemotes:WaitForChild("StartGame").OnServerEvent:Connect(function()
		-- Create turn order from active players
		local playerManager = getPlayerManager()
		turnSystem:CreateTurnOrderFromActivePlayers(playerManager)

		-- Start turn system
		turnSystem:StartTurnSystem()

		-- Set initial turn number
		gameManager.gameState.currentTurn = 1
	end)

	-- Connect to game end event
	gameRemotes:WaitForChild("EndGame").OnServerEvent:Connect(function()
		-- Reset turn system
		turnSystem:Reset()
	end)

	-- Add to global state
	_G.TurnSystem = turnSystem

	return turnSystem
end

-- Initialize service
TurnService.system = TurnService:Initialize()

return TurnService
