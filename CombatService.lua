-- CombatService.server.lua
-- Manages the initiation and resolution of the pre-combat phase.
-- Location: ServerScriptService/Services/CombatService.server.lua
-- Version: 2.3.2 (Improved Turn Synchronization Logic)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Constants
local COMBAT_AREA_POSITION = Vector3.new(0, 100, 0) -- Define a specific Vector3 for the combat arena
local PRE_COMBAT_DURATION = 60 -- seconds for pre-combat phase
local COMBAT_COOLDOWN_TURNS = 2 -- turns of cooldown after combat
local RESPAWN_WAIT_TIMEOUT = 30 -- maximum seconds to wait for respawn before forcing combat end
local TURN_TIME_LIMIT = 60 -- Make sure this matches TurnSystem constant
local DEBUG_COMBAT = true

-- Modules and Services (Lazy Loaded)
local BoardSystem = nil
local TurnSystem = nil
local PlayerManager = nil
local DashSystem = nil

-- State
local activeCombatSession = nil -- { player1Id, player2Id, originalTileId, originalPos1, originalPos2, timerEndTime, currentTurnPlayerId, currentTurnNumber, playerStates={} }
local isCombatActive = false -- General flag (True when combat initiated until resolution starts)
local isResolvingCombat = false -- Specific flag to prevent re-entry into ResolvePreCombat
local pendingRespawnResolution = false -- Flag to track if we're waiting for respawn
local respawnWaitStartTime = 0 -- Time when respawn wait started
local forceRespawnCheckThread = nil -- Thread for respawn timeout
local forceRespawnCheckActive = false -- Flag to check if the thread is active
local waitingForDeadPlayerId = nil -- Store which player we're waiting for to respawn

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

local combatCooldownEvent = combatRemotes:FindFirstChild("CombatCooldown")
if not combatCooldownEvent then
	combatCooldownEvent = Instance.new("RemoteEvent")
	combatCooldownEvent.Name = "CombatCooldown"
	combatCooldownEvent.Parent = combatRemotes
end

-- New remotes for enhanced death handling
local combatPlayerStateEvent = combatRemotes:FindFirstChild("CombatPlayerState")
if not combatPlayerStateEvent then
	combatPlayerStateEvent = Instance.new("RemoteEvent")
	combatPlayerStateEvent.Name = "CombatPlayerState"
	combatPlayerStateEvent.Parent = combatRemotes
end

-- Game remotes needed for turn sync
local gameRemotes = remotes:WaitForChild("GameRemotes")
local updateTurnEvent = gameRemotes:WaitForChild("UpdateTurn")
local uiRemotes = remotes:WaitForChild("UIRemotes")
local updateTurnDetailsEvent = uiRemotes:FindFirstChild("UpdateTurnDetails")
local updateTurnTimerEvent = gameRemotes:FindFirstChild("UpdateTurnTimer") -- Added for sync

-- Helper Functions
local function log(message)
	if DEBUG_COMBAT then
		print("[CombatService] " .. message)
	end
end

local function getBoardSystem()
	if not BoardSystem then
		BoardSystem = _G.BoardSystem -- Assume BoardSystem is loaded into _G by BoardService
		if not BoardSystem then
			warn("[CombatService] BoardSystem not found in _G!")
		end
	end
	return BoardSystem
end

local function getTurnSystem()
	if not TurnSystem then
		local gameManager = _G.GameManager
		TurnSystem = gameManager and gameManager.turnSystem
		if not TurnSystem then
			warn("[CombatService] TurnSystem not found in GameManager!")
		end
	end
	return TurnSystem
end

local function getPlayerManager()
	if not PlayerManager then
		local gameManager = _G.GameManager
		PlayerManager = gameManager and gameManager.playerManager
		if not PlayerManager then
			warn("[CombatService] PlayerManager not found in GameManager!")
		end
	end
	return PlayerManager
end

local function getGameManager()
	return _G.GameManager
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

-- Function to cancel the respawn check thread
local function cancelRespawnCheck()
	if forceRespawnCheckThread then
		task.cancel(forceRespawnCheckThread) -- Use task.cancel for robustness
		forceRespawnCheckThread = nil
	end
	forceRespawnCheckActive = false
end

-- Function to sync turn data with all clients (Simplified - Called ONCE at end of ResolvePreCombat)
local function syncTurnToAllClients(turnSystem, syncDelay)
	if not turnSystem then log("Cannot sync turns - TurnSystem missing"); return end

	-- Allow a short delay for system stabilization if requested
	if syncDelay and syncDelay > 0 then
		task.wait(syncDelay)
	end

	-- Get the current player's turn AFTER all resolution logic
	local currentPlayerTurnId = turnSystem:GetCurrentPlayerTurn()
	if not currentPlayerTurnId then
		log("Cannot sync turns - no current player turn after resolution")
		-- Maybe force next turn if stuck? Or just log.
		return
	end

	-- Get GameManager for turn number AFTER resolution
	local gameManager = getGameManager()
	if not gameManager or not gameManager.gameState then
		log("Cannot sync turns - GameManager or gameState missing")
		return
	end
	local currentTurnNumber = gameManager.gameState.currentTurn or 1 -- Use the final restored turn number

	log("FINAL SYNC: Syncing turn state to ALL clients: Player=" .. tostring(currentPlayerTurnId) .. ", Turn=" .. tostring(currentTurnNumber))

	-- 1. Send basic turn update
	if updateTurnEvent then
		updateTurnEvent:FireAllClients(currentPlayerTurnId)
		log("  > Sent UpdateTurn event")
	end

	-- 2. Send detailed turn info if possible
	local currentPlayer = Players:GetPlayerByUserId(currentPlayerTurnId)
	local playerManager = getPlayerManager()
	if currentPlayer and playerManager and updateTurnDetailsEvent then
		local playerData = playerManager:GetPlayerData(currentPlayer)
		if playerData then
			local turnDetails = {
				playerId = currentPlayerTurnId,
				playerName = currentPlayer.Name,
				turnNumber = currentTurnNumber,
				playerClass = playerData.class or "Unknown",
				playerLevel = playerData.stats and playerData.stats.level or 1
			}
			updateTurnDetailsEvent:FireAllClients(turnDetails)
			log("  > Sent UpdateTurnDetails event")
		else log("  > Could not get PlayerData for details sync.") end
	else log("  > Cannot send details: Player/Manager/Event missing.") end

	-- 3. Send turn timer to all clients
	if updateTurnTimerEvent then
		local timeRemaining = turnSystem:GetTurnTimeRemaining() or TURN_TIME_LIMIT -- Get actual remaining time
		updateTurnTimerEvent:FireAllClients(timeRemaining)
		log("  > Sent UpdateTurnTimer event: " .. timeRemaining .. "s")
	else log("  > Cannot send timer: Event missing.") end
end

-- Main Service Table
local CombatService = {}

-- Interface methods for PlayerManager to notify about death/respawn
function CombatService:NotifyPlayerDeath(playerId)
	-- <<< FIX: Add check for nil playerId >>>
	if playerId == nil then
		warn("[CombatService] NotifyPlayerDeath called with nil playerId! Aborting.")
		return
	end

	-- Check if combat is actually active before proceeding
	if not isCombatActive or not activeCombatSession then
		log("NotifyPlayerDeath: Called for player " .. tostring(playerId) .. " but no active combat session.")
		return -- Not in combat, nothing to notify
	end

	log("Received death notification for player " .. tostring(playerId))

	-- Check if this player is part of the active combat
	if playerId ~= activeCombatSession.player1Id and playerId ~= activeCombatSession.player2Id then
		log("Player " .. tostring(playerId) .. " is not part of the active combat session (" .. tostring(activeCombatSession.player1Id) .. ", " .. tostring(activeCombatSession.player2Id) .. "). Ignoring.")
		return
	end

	-- Ensure playerStates exists
	if not activeCombatSession.playerStates then
		activeCombatSession.playerStates = {}
	end
	if not activeCombatSession.playerStates[playerId] then
		activeCombatSession.playerStates[playerId] = {} -- Initialize if missing
	end

	-- Update player state in combat session only if not already marked dead
	if not activeCombatSession.playerStates[playerId] or activeCombatSession.playerStates[playerId].isAlive ~= false then
		activeCombatSession.playerStates[playerId].isAlive = false
		activeCombatSession.playerStates[playerId].deathTime = tick()
		activeCombatSession.playerStates[playerId].hasRespawned = false
	else
		log("Player " .. tostring(playerId) .. " already marked as dead. Ignoring duplicate notification.")
		return -- Avoid processing death twice
	end

	-- Get the players (check if they are still in game)
	local player1 = Players:GetPlayerByUserId(activeCombatSession.player1Id)
	local player2 = Players:GetPlayerByUserId(activeCombatSession.player2Id)

	-- Determine who died and who's still alive
	local deadPlayerId = playerId -- Confirmed not nil
	local deadPlayer = (deadPlayerId == activeCombatSession.player1Id) and player1 or player2

	-- <<< FIX: Ensure player IDs in session are valid before calculating alivePlayerId >>>
	if activeCombatSession.player1Id == nil or activeCombatSession.player2Id == nil then
		warn("[CombatService] Active combat session has nil player IDs! Session: ", activeCombatSession)
		-- Attempt to resolve based on the dead player ID, assuming the other must be the alive one
		local otherPlayerId = nil
		if player1 and player1.UserId ~= deadPlayerId then otherPlayerId = player1.UserId end
		if player2 and player2.UserId ~= deadPlayerId then otherPlayerId = player2.UserId end

		if otherPlayerId then
			log("Attempting recovery: Assuming other player ID is " .. tostring(otherPlayerId))
			self:ResolvePreCombat("session_error_recovery")
		else
			log("Cannot recover session with nil IDs. Forcing resolution.")
			self:ResolvePreCombat("session_error")
		end
		return
	end

	local alivePlayerId = (deadPlayerId == activeCombatSession.player1Id)
		and activeCombatSession.player2Id
		or activeCombatSession.player1Id

	local alivePlayer = (alivePlayerId == activeCombatSession.player1Id) and player1 or player2

	-- Check if the other player is also dead (check the actual state)
	local otherPlayerState = activeCombatSession.playerStates[alivePlayerId]
	local isOtherPlayerAlive = not (otherPlayerState and otherPlayerState.isAlive == false) -- Check explicitly for false

	-- <<< FIX: Use tostring() for IDs in log to prevent potential errors if they aren't strings/numbers >>>
	log("Player " .. tostring(deadPlayerId) .. " died. Other player " .. tostring(alivePlayerId) .. " alive status: " .. tostring(isOtherPlayerAlive))

	-- Notify clients about this player's death
	if combatPlayerStateEvent and deadPlayer then
		log("Notifying all clients about player " .. tostring(deadPlayerId) .. " death")
		combatPlayerStateEvent:FireAllClients(deadPlayerId, "died")
	end

	-- Immediately transition dead player to board game state
	if deadPlayer then
		log("Transitioning dead player " .. deadPlayer.Name .. " (" .. tostring(deadPlayerId) .. ") to board game state")

		-- Mark that this player is handled (prevents duplicate actions in ResolvePreCombat)
		activeCombatSession.playerStates[deadPlayerId].isHandled = true

		-- Set system states for the dead player
		setSystemEnabledEvent:FireClient(deadPlayer, "CameraSystem", true)
		setSystemEnabledEvent:FireClient(deadPlayer, "DiceRollHandler", true)
		setSystemEnabledEvent:FireClient(deadPlayer, "PlayerControls", false)
		setCombatStateEvent:FireClient(deadPlayer, false, 0) -- End combat state for dead player
	else
		log("Dead player object not found for ID: " .. tostring(deadPlayerId) .. ". Cannot transition state.")
	end

	-- If both players are dead, resolve combat immediately
	if not isOtherPlayerAlive then
		log("Both players (" .. tostring(deadPlayerId) .. " and " .. tostring(alivePlayerId) .. ") are dead. Resolving combat immediately.")
		-- Ensure the other player is also marked as handled if they exist
		if alivePlayer and activeCombatSession.playerStates[alivePlayerId] then
			activeCombatSession.playerStates[alivePlayerId].isHandled = true
		end
		self:ResolvePreCombat("both_dead")
		return
	end

	-- If only one player remains alive, we need to wait for the dead player to respawn
	if isOtherPlayerAlive then
		log("One player (" .. tostring(alivePlayerId) .. ") remains alive. Waiting for dead player " .. tostring(deadPlayerId) .. " to respawn.")
		pendingRespawnResolution = true
		respawnWaitStartTime = tick()
		waitingForDeadPlayerId = deadPlayerId -- Store who we're waiting for

		-- Cancel existing timeout thread if any
		cancelRespawnCheck()

		-- Create a timer to check for timeout
		forceRespawnCheckActive = true
		forceRespawnCheckThread = task.spawn(function()
			local startTime = tick()
			log("Respawn check thread started for player " .. tostring(waitingForDeadPlayerId))
			-- Check pendingRespawnResolution first to exit quickly if resolved
			while pendingRespawnResolution and forceRespawnCheckActive and waitingForDeadPlayerId == deadPlayerId do
				if tick() - startTime > RESPAWN_WAIT_TIMEOUT then
					log("Respawn wait timed out after " .. RESPAWN_WAIT_TIMEOUT .. " seconds for player " .. tostring(deadPlayerId) .. ". Forcing combat resolution.")
					-- Ensure flags are set BEFORE calling ResolvePreCombat
					pendingRespawnResolution = false
					waitingForDeadPlayerId = nil
					forceRespawnCheckActive = false
					CombatService:ResolvePreCombat("timeout") -- Call directly on the service table
					break -- Exit loop
				end
				task.wait(1)
			end
			log("Respawn check thread finished for player " .. tostring(deadPlayerId))
		end)

		-- Notify the alive player that we're waiting for respawn
		if alivePlayer and combatPlayerStateEvent then
			log("Notifying alive player " .. alivePlayer.Name .. " (" .. tostring(alivePlayerId) .. ") to wait for respawn of " .. tostring(deadPlayerId))
			combatPlayerStateEvent:FireClient(alivePlayer, "waiting_for_respawn", deadPlayerId)
		end
	end
end

function CombatService:NotifyPlayerRespawn(playerId)
	-- Add check for nil playerId
	if playerId == nil then
		warn("[CombatService] NotifyPlayerRespawn called with nil playerId! Aborting.")
		return
	end

	-- Check if we are actually waiting for a respawn
	if not pendingRespawnResolution then
		log("NotifyPlayerRespawn: Received respawn for " .. tostring(playerId) .. ", but not currently waiting for any respawn.")
		return
	end

	-- Check if this is the player we are waiting for
	if waitingForDeadPlayerId ~= playerId then
		log("NotifyPlayerRespawn: Received respawn for " .. tostring(playerId) .. ", but waiting for " .. tostring(waitingForDeadPlayerId) .. ". Ignoring.")
		return
	end

	-- Check if the session still exists (it should if pendingRespawnResolution is true)
	if not activeCombatSession then
		log("NotifyPlayerRespawn: No active combat session when respawn occurred for " .. tostring(playerId) .. ". Clearing pending state.")
		pendingRespawnResolution = false -- Clear waiting state as combat ended somehow
		waitingForDeadPlayerId = nil
		cancelRespawnCheck()
		return
	end

	log("Received expected respawn notification for player " .. tostring(playerId))

	-- Check if this player is part of the active combat (redundant but safe)
	if playerId ~= activeCombatSession.player1Id and playerId ~= activeCombatSession.player2Id then
		log("Player " .. tostring(playerId) .. " respawned but is no longer part of the active combat. Strange state, resolving.")
		pendingRespawnResolution = false
		waitingForDeadPlayerId = nil
		cancelRespawnCheck()
		self:ResolvePreCombat("respawned_player_not_in_session")
		return
	end

	-- Update player state in combat session
	if not activeCombatSession.playerStates then activeCombatSession.playerStates = {} end
	if not activeCombatSession.playerStates[playerId] then activeCombatSession.playerStates[playerId] = {} end

	activeCombatSession.playerStates[playerId].isAlive = true
	activeCombatSession.playerStates[playerId].hasRespawned = true
	activeCombatSession.playerStates[playerId].respawnTime = tick()

	log("Player " .. tostring(playerId) .. " has respawned. Resolving combat.")

	-- Clear the waiting state FIRST
	pendingRespawnResolution = false
	waitingForDeadPlayerId = nil

	-- Cancel the respawn check timer
	cancelRespawnCheck()

	-- Resolve the combat after a short delay using task.spawn for safety
	task.spawn(function()
		task.wait(0.5) -- Short delay to ensure client state updates
		-- Check if combat is still marked active by the session before resolving
		if activeCombatSession and activeCombatSession.player1Id == playerId or activeCombatSession.player2Id == playerId then
			self:ResolvePreCombat("after_respawn")
		else
			log("ResolvePreCombat after respawn skipped: Session changed or ended before delay completed.")
		end
	end)
end

-- Check combat cooldown for a player
function CombatService:CheckCombatCooldown(playerID)
	local turnSystem = getTurnSystem()
	if not turnSystem then
		warn("[CombatService] Cannot check combat cooldown: TurnSystem not found.")
		return false -- Default to no cooldown if system unavailable
	end

	return turnSystem:HasCombatCooldown(playerID)
end

-- Initiate the pre-combat sequence
function CombatService:InitiatePreCombat(player1, player2, tileId)
	if not player1 or not player2 then
		warn("[CombatService] InitiatePreCombat called with nil player object(s).")
		return false
	end

	-- Use IsCombatActive() which includes pendingRespawn check
	if self:IsCombatActive() then
		log("Cannot initiate combat, another session is already active or resolving.")
		return false
	end

	-- Check combat cooldown for both players
	local turnSystem = getTurnSystem() -- Get turn system once
	if turnSystem then
		if self:CheckCombatCooldown(player1.UserId) then
			local cooldownTurns = turnSystem:GetCombatCooldown(player1.UserId)
			log("Cannot initiate combat, player " .. player1.Name .. " is on combat cooldown (" .. tostring(cooldownTurns) .. " turns).")
			if combatCooldownEvent then
				combatCooldownEvent:FireClient(player1, cooldownTurns, true) -- Notify self
				if player2 then combatCooldownEvent:FireClient(player2, cooldownTurns, false, player1.Name) end -- Notify opponent
			end
			return false
		end

		if self:CheckCombatCooldown(player2.UserId) then
			local cooldownTurns = turnSystem:GetCombatCooldown(player2.UserId)
			log("Cannot initiate combat, player " .. player2.Name .. " is on combat cooldown (" .. tostring(cooldownTurns) .. " turns).")
			if combatCooldownEvent then
				combatCooldownEvent:FireClient(player2, cooldownTurns, true) -- Notify self
				if player1 then combatCooldownEvent:FireClient(player1, cooldownTurns, false, player2.Name) end -- Notify opponent
			end
			return false
		end
	else
		warn("[CombatService] TurnSystem not found during cooldown check. Proceeding without check.")
	end

	log("Initiating Pre-Combat between " .. player1.Name .. " (" .. tostring(player1.UserId) .. ") and " .. player2.Name .. " (" .. tostring(player2.UserId) .. ") on tile " .. tostring(tileId))
	isCombatActive = true -- Set flag early

	local boardSystem = getBoardSystem()
	local playerManager = getPlayerManager() -- TurnSystem already fetched

	if not boardSystem or not turnSystem or not playerManager then
		warn("[CombatService] Cannot initiate combat: Missing required systems (Board, Turn, or PlayerManager).")
		isCombatActive = false -- Reset flag
		return false
	end

	-- Store original positions BEFORE teleporting (ensure characters exist)
	local originalPos1 = player1.Character and player1.Character:FindFirstChild("HumanoidRootPart") and player1.Character.HumanoidRootPart.Position
	local originalPos2 = player2.Character and player2.Character:FindFirstChild("HumanoidRootPart") and player2.Character.HumanoidRootPart.Position

	if not originalPos1 or not originalPos2 then
		warn("[CombatService] Cannot get original positions for players (Character or HumanoidRootPart missing?). Aborting combat initiation.")
		isCombatActive = false
		-- Maybe notify players?
		return false
	end

	-- Get alive status for both players using PlayerManager
	local player1Data = playerManager:GetPlayerData(player1)
	local player2Data = playerManager:GetPlayerData(player2)

	-- Check isAlive status from PlayerManager data
	local player1Alive = player1Data and player1Data.isAlive
	local player2Alive = player2Data and player2Data.isAlive

	if not player1Alive or not player2Alive then
		warn("[CombatService] Cannot initiate combat: PlayerManager reports one or both players are dead. P1: " .. tostring(player1Alive) .. ", P2: " .. tostring(player2Alive))
		isCombatActive = false
		-- Optionally notify players why combat didn't start
		return false
	end

	-- Get current turn information
	local currentTurnPlayerId = turnSystem:GetCurrentPlayerTurn()
	log("Current turn player before combat: " .. tostring(currentTurnPlayerId))

	-- Get current turn number from GameManager
	local gameManager = getGameManager()
	local currentTurnNumber = 1
	if gameManager and gameManager.gameState then
		currentTurnNumber = gameManager.gameState.currentTurn or 1
	end
	log("Current turn number before combat: " .. tostring(currentTurnNumber))

	-- Store session data
	activeCombatSession = {
		player1Id = player1.UserId,
		player2Id = player2.UserId,
		originalTileId = tileId,
		originalPos1 = originalPos1,
		originalPos2 = originalPos2,
		timerEndTime = tick() + PRE_COMBAT_DURATION,
		currentTurnPlayerId = currentTurnPlayerId, -- Store who's turn it WAS
		currentTurnNumber = currentTurnNumber, -- Store the turn number
		playerStates = {
			[player1.UserId] = { isAlive = true, isHandled = false }, -- Initialize isHandled
			[player2.UserId] = { isAlive = true, isHandled = false }  -- Initialize isHandled
		}
	}

	-- Reset respawn resolution tracking
	pendingRespawnResolution = false
	waitingForDeadPlayerId = nil
	isResolvingCombat = false -- Ensure resolving flag is false

	-- Cancel any existing respawn check (shouldn't be one, but safe)
	cancelRespawnCheck()

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
	-- Define specific spawn points within the area
	local spawnOffset1 = Vector3.new(-10, 0, 0) -- Example offset for player 1
	local spawnOffset2 = Vector3.new(10, 0, 0)  -- Example offset for player 2
	teleportPlayer(player1, COMBAT_AREA_POSITION + spawnOffset1)
	teleportPlayer(player2, COMBAT_AREA_POSITION + spawnOffset2)

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
		-- Check if the session associated with THIS timer is still the active one
		-- AND we are not waiting for respawn AND not already resolving
		if activeCombatSession and activeCombatSession.player1Id == player1.UserId and
			activeCombatSession.player2Id == player2.UserId and
			isCombatActive and not pendingRespawnResolution and not isResolvingCombat then
			log("Pre-combat timer finished naturally. Resolving session.")
			self:ResolvePreCombat("timer_ended")
		elseif pendingRespawnResolution then
			log("Pre-combat timer finished, but waiting for respawn. Resolution deferred.")
		elseif isResolvingCombat then
			log("Pre-combat timer finished, but resolution already in progress.")
		else
			log("Pre-combat timer finished, but the active session changed or ended before timer completion. No resolution needed from timer.")
		end
	end)

	return true
end

-- Resolve the pre-combat sequence and return players (Simplified Turn Logic)
function CombatService:ResolvePreCombat(reason)
	reason = reason or "unknown" -- Provide a default reason

	-- Prevent re-entry if already resolving
	if isResolvingCombat then
		log("ResolvePreCombat called while already resolving. Ignoring. Reason: " .. reason)
		return false
	end

	-- Check if there's an active session to resolve
	if not activeCombatSession then
		log("ResolvePreCombat called but no active combat session. Reason: " .. reason .. ". Ignoring.")
		isCombatActive = false -- Ensure flags are reset
		pendingRespawnResolution = false
		waitingForDeadPlayerId = nil
		cancelRespawnCheck()
		return false
	end

	-- Mark as resolving immediately
	isResolvingCombat = true
	isCombatActive = false -- Mark main combat as inactive now resolution starts

	-- Store session data locally before clearing global reference
	local session = activeCombatSession
	activeCombatSession = nil -- Clear global session reference now

	local player1Id = session.player1Id
	local player2Id = session.player2Id
	local originalPos1 = session.originalPos1
	local originalPos2 = session.originalPos2
	local currentTurnPlayerId = session.currentTurnPlayerId -- The player whose turn it WAS
	local currentTurnNumber = session.currentTurnNumber -- The turn number it WAS
	local playerStates = session.playerStates or {} -- Use the stored states

	log("Resolving Pre-Combat session. Reason: " .. reason .. ". Players: " .. tostring(player1Id) .. ", " .. tostring(player2Id))

	-- Clear other flags
	pendingRespawnResolution = false
	waitingForDeadPlayerId = nil
	cancelRespawnCheck() -- Stop any respawn timer

	-- Get player objects (they might have left)
	local player1 = Players:GetPlayerByUserId(player1Id)
	local player2 = Players:GetPlayerByUserId(player2Id)

	-- Set combat cooldown for both players involved in the session
	local turnSystem = getTurnSystem()
	if turnSystem then
		local player1Handled = playerStates[player1Id] and playerStates[player1Id].isHandled
		if player1 and not player1Handled then
			turnSystem:SetCombatCooldown(player1Id, COMBAT_COOLDOWN_TURNS)
			log("Set combat cooldown for player " .. player1.Name .. " (" .. tostring(player1Id) .. ") for " .. COMBAT_COOLDOWN_TURNS .. " turns.")
			if combatCooldownEvent then combatCooldownEvent:FireClient(player1, COMBAT_COOLDOWN_TURNS) end
		elseif not player1 then log("Player " .. tostring(player1Id) .. " left, cannot set cooldown.")
		elseif player1Handled then log("Player " .. player1.Name .. " was already handled, skipping cooldown set here.") end

		local player2Handled = playerStates[player2Id] and playerStates[player2Id].isHandled
		if player2 and not player2Handled then
			turnSystem:SetCombatCooldown(player2Id, COMBAT_COOLDOWN_TURNS)
			log("Set combat cooldown for player " .. player2.Name .. " (" .. tostring(player2Id) .. ") for " .. COMBAT_COOLDOWN_TURNS .. " turns.")
			if combatCooldownEvent then combatCooldownEvent:FireClient(player2, COMBAT_COOLDOWN_TURNS) end
		elseif not player2 then log("Player " .. tostring(player2Id) .. " left, cannot set cooldown.")
		elseif player2Handled then log("Player " .. player2.Name .. " was already handled, skipping cooldown set here.") end
	else warn("[CombatService] TurnSystem not available during ResolvePreCombat. Cannot set cooldowns.") end

	-- Determine final alive states based on the session data
	local player1Alive = playerStates[player1Id] and playerStates[player1Id].isAlive
	local player2Alive = playerStates[player2Id] and playerStates[player2Id].isAlive
	local player1Handled = playerStates[player1Id] and playerStates[player1Id].isHandled
	local player2Handled = playerStates[player2Id] and playerStates[player2Id].isHandled

	log("Final states for resolution: P1("..tostring(player1Id)..") Alive=" .. tostring(player1Alive) .. ", Handled=" .. tostring(player1Handled) ..
		"; P2("..tostring(player2Id)..") Alive=" .. tostring(player2Alive) .. ", Handled=" .. tostring(player2Handled))

	-- Teleport players back IF they are alive AND haven't been handled
	if player1 and player1Alive and not player1Handled then log("Warping player " .. player1.Name .. " back."); teleportPlayer(player1, originalPos1)
	elseif player1 and not player1Handled then log("Player " .. player1.Name .. " is dead or handled, not teleporting.")
	elseif not player1 then log("Player " .. tostring(player1Id) .. " not found, cannot teleport.") end

	if player2 and player2Alive and not player2Handled then log("Warping player " .. player2.Name .. " back."); teleportPlayer(player2, originalPos2)
	elseif player2 and not player2Handled then log("Player " .. player2.Name .. " is dead or handled, not teleporting.")
	elseif not player2 then log("Player " .. tostring(player2Id) .. " not found, cannot teleport.") end

	-- Re-enable client systems for players who are alive and weren't handled
	if player1 and not player1Handled then
		log("Re-enabling systems for player " .. player1.Name)
		setSystemEnabledEvent:FireClient(player1, "CameraSystem", true)
		setSystemEnabledEvent:FireClient(player1, "DiceRollHandler", true)
		setSystemEnabledEvent:FireClient(player1, "PlayerControls", false)
	end
	if player2 and not player2Handled then
		log("Re-enabling systems for player " .. player2.Name)
		setSystemEnabledEvent:FireClient(player2, "CameraSystem", true)
		setSystemEnabledEvent:FireClient(player2, "DiceRollHandler", true)
		setSystemEnabledEvent:FireClient(player2, "PlayerControls", false)
	end

	-- End combat state visual on ALL clients immediately
	log("Ending combat state visual on all clients.")
	setCombatStateEvent:FireAllClients(false, 0) -- Signal combat end to everyone

	-- Restore Turn System State
	if turnSystem then
		log("Restoring Turn System state.")

		-- Restore the turn number FIRST
		local gameManager = getGameManager()
		if gameManager and gameManager.gameState then
			if gameManager.gameState.currentTurn ~= currentTurnNumber then
				log("Restoring turn number to pre-combat value: " .. tostring(currentTurnNumber))
				gameManager.gameState.currentTurn = currentTurnNumber
			else
				log("Turn number ("..tostring(gameManager.gameState.currentTurn)..") already matches pre-combat value.")
			end
		else warn("[CombatService] GameManager or gameState not found, cannot restore turn number.") end

		-- Resume turns (unpause)
		turnSystem:ResumeTurns()
		log("Turn system resumed.")

		-- Wait briefly for resume to process internal state
		task.wait(0.2)

		-- Determine the correct turn state AFTER resuming
		local playerManager = getPlayerManager()
		local originalTurnPlayer = Players:GetPlayerByUserId(currentTurnPlayerId)
		local originalTurnPlayerData = originalTurnPlayer and playerManager and playerManager:GetPlayerData(originalTurnPlayer)
		-- Check the LATEST alive status from PlayerManager AFTER respawn might have happened
		local originalTurnPlayerIsAliveAndInGame = originalTurnPlayerData and originalTurnPlayerData.isAlive

		log("Original turn player ("..tostring(currentTurnPlayerId)..") info: Exists=" .. tostring(originalTurnPlayer ~= nil) .. ", IsAliveAccordingToPlayerManager=" .. tostring(originalTurnPlayerIsAliveAndInGame))

		local currentTurnInSystem = turnSystem:GetCurrentPlayerTurn()
		log("Turn system reports current player after resume: " .. tostring(currentTurnInSystem))

		if originalTurnPlayerIsAliveAndInGame then
			-- If the original player is alive, their turn should continue or be restored.
			if currentTurnInSystem ~= currentTurnPlayerId then
				log("Turn system did not resume on the correct player. Forcing turn back to " .. tostring(currentTurnPlayerId))
				-- Force the turn back to the original player
				local forceSuccess = false
				if turnSystem.ForceSetCurrentTurn then
					forceSuccess = turnSystem:ForceSetCurrentTurn(currentTurnPlayerId)
					if forceSuccess then log("Used ForceSetCurrentTurn.") end
				elseif turnSystem.SetCurrentPlayer then -- Fallback
					forceSuccess = turnSystem:SetCurrentPlayer(currentTurnPlayerId)
					if forceSuccess then log("Used SetCurrentPlayer.") end
				end
				if not forceSuccess then log("No method found or failed to force turn reset. State might be inconsistent.") end
				-- Wait briefly after forcing
				task.wait(0.1)
			else
				log("Turn correctly resumed/stayed on original player " .. tostring(currentTurnPlayerId))
			end
			-- The turn is now (or should be) the original player's.
		else
			-- If the original player is dead or left, their turn needs to formally end now.
			log("Original turn player " .. tostring(currentTurnPlayerId) .. " is dead or left. Ending their turn formally.")
			-- Check if the turn system is still stuck on the dead/left player.
			-- It might have already advanced if HandlePlayerLeaving was called.
			if currentTurnInSystem == currentTurnPlayerId then
				-- Turn system is still stuck on the dead/left player, end it.
				-- Use task.spawn for safety as EndPlayerTurn might yield or call callbacks
				task.spawn(turnSystem.EndPlayerTurn, turnSystem, currentTurnPlayerId, "player_dead_after_combat")
				-- Wait for EndPlayerTurn to potentially trigger NextTurn and state changes
				task.wait(0.3) -- Increased wait slightly
			else
				-- Turn system already advanced past dead/left player.
				log("Turn system already advanced. Current: " .. tostring(currentTurnInSystem))
			end
			-- The turn should now be the next valid player's.
		end

		-- Perform ONE final sync after all state adjustments
		log("Performing final turn sync.")
		syncTurnToAllClients(turnSystem, 0.2) -- Use a small delay

	else
		warn("[CombatService] TurnSystem not available during final stage of ResolvePreCombat. Cannot restore turn state.")
	end

	-- Mark resolution as complete
	isResolvingCombat = false
	log("Combat resolution complete for reason: " .. reason)
	return true
end


-- Function to check if combat is currently active OR resolving
function CombatService:IsCombatActive()
	-- Return true if combat was initiated and hasn't finished resolving OR if waiting for respawn
	return isCombatActive or isResolvingCombat or pendingRespawnResolution
end

-- Function to get the active combat session details (read-only)
function CombatService:GetActiveCombatSession()
	-- Return session only if combat is truly active (not just resolving/pending)
	if isCombatActive and activeCombatSession then
		return activeCombatSession -- Return a reference (be careful not to modify externally)
	end
	return nil
end


-- Initialize dash system for combat
function CombatService:InitializeDashSystem()
	if DashSystem then return DashSystem end -- Already initialized

	local dashSystemModule = nil
	local moduleName = "DashSystem" -- Or "MovementSystem" if that's the final name

	-- Function to attempt loading the module
	local function tryLoadModule(location, name)
		local success, result = pcall(function()
			return require(location:WaitForChild(name, 5)) -- Add timeout
		end)
		if success then
			log("Successfully loaded " .. name .. " module from " .. location:GetFullName())
			return result
		else
			-- Don't warn if just not found, only on error
			-- warn("[CombatService] Failed to load " .. name .. " module from " .. location:GetFullName() .. ": " .. tostring(result))
			return nil
		end
	end

	-- Try loading from ServerStorage/Modules first
	local ssModules = ServerStorage:FindFirstChild("Modules")
	if ssModules then dashSystemModule = tryLoadModule(ssModules, moduleName) end

	-- Fallback: Try loading from script's parent (if it exists there)
	if not dashSystemModule then
		log("DashSystem not found in ServerStorage/Modules, trying script.Parent")
		dashSystemModule = tryLoadModule(script.Parent, moduleName)
	end

	-- If still not found, create a placeholder (last resort)
	if not dashSystemModule then
		warn("[CombatService] DashSystem module not found in expected locations. Creating placeholder.")
		local newModule = Instance.new("ModuleScript")
		newModule.Name = moduleName

		local placeholder = [[
			print("[DashSystem] WARNING: This is a placeholder module. Functionality will be missing.")
			local DashSystem = {}
			DashSystem.__index = DashSystem
			function DashSystem.new(combatService)
				local self = setmetatable({}, DashSystem)
				self.combatService = combatService
				print("[DashSystem Placeholder] Initialized.")
				return self
			end
			function DashSystem:Register() print("[DashSystem Placeholder] Register called.") end
			-- Add placeholder methods for any functions CombatService might call
			function DashSystem:EnableDash(player) print("[DashSystem Placeholder] EnableDash called for " .. (player and player.Name or "nil")) end
			function DashSystem:DisableDash(player) print("[DashSystem Placeholder] DisableDash called for " .. (player and player.Name or "nil")) end
			return DashSystem
		]]
		newModule.Source = placeholder
		newModule.Parent = script.Parent -- Place it next to CombatService

		-- Try loading the newly created placeholder
		dashSystemModule = tryLoadModule(script.Parent, moduleName)
	end

	-- If module loaded (either real or placeholder), create instance
	if dashSystemModule and dashSystemModule.new then
		DashSystem = dashSystemModule.new(self) -- Pass CombatService instance
		log("DashSystem instance created.")

		-- Register it with GameManager if available
		if DashSystem.Register then
			DashSystem:Register()
			log("DashSystem registration attempted.")
		else
			warn("[CombatService] DashSystem module does not have a Register function.")
		end
	else
		warn("[CombatService] Failed to load or create DashSystem module. Dash functionality unavailable.")
		DashSystem = nil -- Ensure it's nil if failed
	end

	return DashSystem
end

-- Add a function that TurnSystem can call to force sync turns (if needed externally)
function CombatService:SyncTurns()
	local turnSystem = getTurnSystem()
	if turnSystem then
		log("External call to SyncTurns received.")
		syncTurnToAllClients(turnSystem, 0)
		return true
	else
		warn("[CombatService] SyncTurns called but TurnSystem is not available.")
		return false
	end
end

-- Register with GameManager if available
local function registerWithGameManager()
	local retries = 5
	local waitTime = 2
	for i = 1, retries do
		local gameManager = _G.GameManager
		if gameManager then
			if not gameManager.combatService then
				gameManager.combatService = CombatService
				log("CombatService registered with GameManager.")
				-- Initialize DashSystem ONLY after successful registration
				CombatService:InitializeDashSystem()
				return -- Success
			else
				log("CombatService already registered with GameManager.")
				-- Check if DashSystem needs init (e.g., if script reloaded)
				if not DashSystem then
					CombatService:InitializeDashSystem()
				end
				return -- Already registered
			end
		else
			log("GameManager not found. Retrying registration in " .. waitTime .. "s... (" .. i .. "/" .. retries .. ")")
			task.wait(waitTime)
		end
	end
	warn("[CombatService] GameManager not found after " .. retries .. " retries. Service might not be accessible globally.")
end

-- Initial registration attempt
registerWithGameManager()

log("Enhanced CombatService Initialized (v2.3.2).")
return CombatService
