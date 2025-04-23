-- CombatService.server.lua
-- Manages the initiation and resolution of the pre-combat phase.
-- Location: ServerScriptService/Services/CombatService.server.lua
-- Version: 1.1.0 (Added PlayerControls toggling during combat)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

-- Constants
local COMBAT_AREA_POSITION = Vector3.new(0, 100, 0) -- Define a specific Vector3 for the combat arena
local PRE_COMBAT_DURATION = 120 -- 2 minutes in seconds
local DEBUG_COMBAT = true

-- Modules and Services (Lazy Loaded)
local BoardSystem = nil
local TurnSystem = nil
local CameraSystem = nil -- Client-side, controlled via remotes
local DiceRollHandler = nil -- Client-side, controlled via remotes

-- State
local activeCombatSession = nil -- { player1Id, player2Id, originalTileId, originalPos1, originalPos2, timerEndTime }
local isCombatActive = false -- General flag

-- Remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local combatRemotes = remotes:FindFirstChild("CombatRemotes")
if not combatRemotes then
	combatRemotes = Instance.new("Folder")
	combatRemotes.Name = "CombatRemotes"
	combatRemotes.Parent = remotes
end

local setCombatStateEvent = combatRemotes:FindFirstChild("SetCombatState")
if not setCombatStateEvent then
	setCombatStateEvent = Instance.new("RemoteEvent")
	setCombatStateEvent.Name = "SetCombatState"
	setCombatStateEvent.Parent = combatRemotes
end

local setSystemEnabledEvent = combatRemotes:FindFirstChild("SetSystemEnabled")
if not setSystemEnabledEvent then
	setSystemEnabledEvent = Instance.new("RemoteEvent")
	setSystemEnabledEvent.Name = "SetSystemEnabled"
	setSystemEnabledEvent.Parent = combatRemotes
end


-- Helper Functions
local function log(message)
	if DEBUG_COMBAT then
		print("[CombatService] " .. message)
	end
end

local function getBoardSystem()
	if not BoardSystem then
		BoardSystem = _G.BoardSystem -- Assume BoardSystem is loaded into _G by BoardService
		if not BoardSystem then warn("[CombatService] BoardSystem not found in _G!") end
	end
	return BoardSystem
end

local function getTurnSystem()
	if not TurnSystem then
		local gameManager = _G.GameManager
		TurnSystem = gameManager and gameManager.turnSystem
		if not TurnSystem then warn("[CombatService] TurnSystem not found in GameManager!") end
	end
	return TurnSystem
end

local function teleportPlayer(player, position)
	if not player or not position then return end
	local character = player.Character
	if not character then return end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart then
		log("Teleporting " .. player.Name .. " to " .. tostring(position))
		humanoidRootPart.CFrame = CFrame.new(position + Vector3.new(0, 3, 0)) -- Add offset to avoid ground clipping
	else
		warn("[CombatService] HumanoidRootPart not found for " .. player.Name)
	end
end

-- Main Service Table
local CombatService = {}

-- Initiate the pre-combat sequence
function CombatService:InitiatePreCombat(player1, player2, tileId)
	if isCombatActive then
		log("Cannot initiate combat, another session is already active.")
		return false
	end

	log("Initiating Pre-Combat between " .. player1.Name .. " and " .. player2.Name .. " on tile " .. tileId)
	isCombatActive = true

	local boardSystem = getBoardSystem()
	local turnSystem = getTurnSystem()

	if not boardSystem or not turnSystem then
		warn("[CombatService] Cannot initiate combat: Missing required systems (BoardSystem or TurnSystem).")
		isCombatActive = false
		return false
	end

	-- Store original positions BEFORE teleporting
	local originalPos1 = player1.Character and player1.Character:FindFirstChild("HumanoidRootPart") and player1.Character.HumanoidRootPart.Position
	local originalPos2 = player2.Character and player2.Character:FindFirstChild("HumanoidRootPart") and player2.Character.HumanoidRootPart.Position

	if not originalPos1 or not originalPos2 then
		warn("[CombatService] Cannot get original positions for players. Aborting combat initiation.")
		isCombatActive = false
		return false
	end

	-- Store session data
	activeCombatSession = {
		player1Id = player1.UserId,
		player2Id = player2.UserId,
		originalTileId = tileId,
		originalPos1 = originalPos1,
		originalPos2 = originalPos2,
		timerEndTime = tick() + PRE_COMBAT_DURATION
	}

	-- 1. Pause Turn System
	log("Pausing Turn System.")
	turnSystem:PauseTurns()

	-- 2. Disable Client Systems (Camera, DiceRoll UI)
	log("Disabling client systems for players.")
	setSystemEnabledEvent:FireClient(player1, "CameraSystem", false)
	setSystemEnabledEvent:FireClient(player1, "DiceRollHandler", false)
	setSystemEnabledEvent:FireClient(player2, "CameraSystem", false)
	setSystemEnabledEvent:FireClient(player2, "DiceRollHandler", false)
	
	-- 3. Enable Player Controls for combat
	log("Enabling PlayerControls for combat participants.")
	setSystemEnabledEvent:FireClient(player1, "PlayerControls", true)
	setSystemEnabledEvent:FireClient(player2, "PlayerControls", true)

	-- 4. Warp Players to Combat Area
	log("Warping players to combat area: " .. tostring(COMBAT_AREA_POSITION))
	teleportPlayer(player1, COMBAT_AREA_POSITION + Vector3.new(-1214.4, 45.032, -233.3)) -- Offset players slightly
	teleportPlayer(player2, COMBAT_AREA_POSITION + Vector3.new(-1473.9, 45.032, -233.3))

	-- 5. Start Combat Timer on Clients
	log("Starting combat timer (" .. PRE_COMBAT_DURATION .. "s) on clients.")
	setCombatStateEvent:FireClient(player1, true, PRE_COMBAT_DURATION)
	setCombatStateEvent:FireClient(player2, true, PRE_COMBAT_DURATION)
	-- Optionally notify other players that combat started (without timer)
	for _, p in pairs(Players:GetPlayers()) do
		if p.UserId ~= player1.UserId and p.UserId ~= player2.UserId then
			setCombatStateEvent:FireClient(p, true, 0) -- Indicate combat active, no timer
		end
	end

	-- 6. Start Server-Side Timer for Resolution
	task.delay(PRE_COMBAT_DURATION, function()
		-- Check if the same combat session is still active
		if isCombatActive and activeCombatSession and
			activeCombatSession.player1Id == player1.UserId and
			activeCombatSession.player2Id == player2.UserId then
			log("Pre-combat timer finished. Resolving session.")
			CombatService:ResolvePreCombat()
		else
			log("Pre-combat timer finished, but the active session changed or ended. No resolution needed.")
		end
	end)

	return true
end

-- Resolve the pre-combat sequence and return players
function CombatService:ResolvePreCombat()
	if not isCombatActive or not activeCombatSession then
		log("ResolvePreCombat called but no active combat session.")
		return false
	end

	log("Resolving Pre-Combat session.")

	local player1 = Players:GetPlayerByUserId(activeCombatSession.player1Id)
	local player2 = Players:GetPlayerByUserId(activeCombatSession.player2Id)
	local originalTileId = activeCombatSession.originalTileId
	local originalPos1 = activeCombatSession.originalPos1
	local originalPos2 = activeCombatSession.originalPos2

	-- 1. Warp Players Back
	log("Warping players back to original positions.")
	if player1 then teleportPlayer(player1, originalPos1) end
	if player2 then teleportPlayer(player2, originalPos2) end

	-- 2. Resume Turn System
	local turnSystem = getTurnSystem()
	if turnSystem then
		log("Resuming Turn System.")
		turnSystem:ResumeTurns()
	end

	-- 3. Re-enable Client Systems
	log("Re-enabling client systems.")
	if player1 then
		setSystemEnabledEvent:FireClient(player1, "CameraSystem", true)
		setSystemEnabledEvent:FireClient(player1, "DiceRollHandler", true)
		-- Disable Player Controls (lock movement) when returning to the board game
		setSystemEnabledEvent:FireClient(player1, "PlayerControls", false)
	end
	if player2 then
		setSystemEnabledEvent:FireClient(player2, "CameraSystem", true)
		setSystemEnabledEvent:FireClient(player2, "DiceRollHandler", true)
		-- Disable Player Controls (lock movement) when returning to the board game
		setSystemEnabledEvent:FireClient(player2, "PlayerControls", false)
	end

	-- 4. End Combat State on Clients
	log("Ending combat state on clients.")
	setCombatStateEvent:FireAllClients(false, 0) -- Signal combat end to everyone

	-- 5. Clear Session Data
	log("Clearing active combat session.")
	activeCombatSession = nil
	isCombatActive = false

	-- Optional: If the turn was paused mid-turn, decide how to proceed.
	-- For now, resuming will likely just start the next turn or continue the timer.

	return true
end

-- Function to check if combat is currently active
function CombatService:IsCombatActive()
	return isCombatActive
end

-- Register with GameManager if available
local function registerWithGameManager()
	local gameManager = _G.GameManager
	if gameManager then
		gameManager.combatService = CombatService
		log("CombatService registered with GameManager.")
	else
		-- Retry after a delay if GameManager isn't ready yet
		task.wait(2)
		gameManager = _G.GameManager
		if gameManager then
			gameManager.combatService = CombatService
			log("CombatService registered with GameManager (after delay).")
		else
			warn("[CombatService] GameManager not found after delay. Service might not be accessible.")
		end
	end
end

registerWithGameManager()

log("CombatService Initialized.")
return CombatService
