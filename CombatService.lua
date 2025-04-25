-- CombatService.server.lua
-- Manages the initiation, resolution, and death detection during combat.
-- Location: ServerScriptService/Services/CombatService.server.lua
-- Version: 1.5.3 (Added TurnSystem.OnPlayerDeath call)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

-- Constants
local COMBAT_AREA_POSITION = Vector3.new(0, 100, 0)
local PRE_COMBAT_DURATION = 60 -- Can be adjusted if needed
local COMBAT_COOLDOWN_TURNS = 2
local RESPAWN_VISUAL_DELAY = 2 -- วินาทีที่รอหลัง Teleport ก่อนจบ Combat
local DEBUG_COMBAT = true

-- Modules and Services (Lazy Loaded)
local BoardSystem = nil
local TurnSystem = nil
local CheckpointSystem = nil
local CameraSystem = nil
local DiceRollHandler = nil
local DashSystem = nil

-- State
local activeCombatSession = nil -- { player1Id, player2Id, originalTileId, originalPos1, originalPos2, timerEndTime, currentTurnPlayerId, timerThread, diedConnections = {conn1, conn2} }
local isCombatActive = false

-- Remotes (Same as before)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local combatRemotes = remotes:FindFirstChild("CombatRemotes")
if not combatRemotes then
	combatRemotes = Instance.new("Folder")
	combatRemotes.Name = "CombatRemotes"
	combatRemotes.Parent = remotes
end
local setCombatStateEvent = combatRemotes:FindFirstChild("SetCombatState") or Instance.new("RemoteEvent", combatRemotes)
setCombatStateEvent.Name = "SetCombatState"
local setSystemEnabledEvent = combatRemotes:FindFirstChild("SetSystemEnabled") or Instance.new("RemoteEvent", combatRemotes)
setSystemEnabledEvent.Name = "SetSystemEnabled"
local combatCooldownEvent = combatRemotes:FindFirstChild("CombatCooldown") or Instance.new("RemoteEvent", combatRemotes)
combatCooldownEvent.Name = "CombatCooldown"


-- Helper Functions (Same as before)
local function log(message)
	if DEBUG_COMBAT then
		print("[CombatService] " .. message)
	end
end

local function getBoardSystem()
	if not BoardSystem then BoardSystem = _G.BoardSystem end
	if not BoardSystem then warn("[CombatService] BoardSystem not found!") end
	return BoardSystem
end

local function getTurnSystem()
	if not TurnSystem then TurnSystem = _G.GameManager and _G.GameManager.turnSystem end
	if not TurnSystem then warn("[CombatService] TurnSystem not found!") end
	return TurnSystem
end

local function getCheckpointSystem()
	if not CheckpointSystem then CheckpointSystem = _G.GameManager and _G.GameManager.checkpointSystem or _G.CheckpointSystem end
	if not CheckpointSystem then warn("[CombatService] CheckpointSystem not found!") end
	return CheckpointSystem
end

-- *** UPDATED teleportPlayer function ***
local function teleportPlayer(player, position)
	if not player or not player:IsA("Player") then -- Ensure 'player' is a Player object
		warn("[CombatService] Invalid player object passed to teleportPlayer.")
		return
	end
	if not position or typeof(position) ~= "Vector3" then
		warn("[CombatService] Invalid position passed to teleportPlayer for player " .. player.Name)
		return
	end

	local character = player.Character
	local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")

	if humanoidRootPart then
		log("Teleporting " .. player.Name .. " to " .. tostring(position))
		-- Call RequestStreamAroundAsync on the PLAYER object
		local success, err = pcall(player.RequestStreamAroundAsync, player, position)
		if not success then
			warn("[CombatService] RequestStreamAroundAsync failed for player " .. player.Name .. ": " .. tostring(err))
		end
		task.wait(0.1) -- Short delay for streaming request
		humanoidRootPart.CFrame = CFrame.new(position + Vector3.new(0, 3, 0)) -- Offset to avoid ground clipping
	else
		warn("[CombatService] HumanoidRootPart not found for " .. player.Name .. " during teleport.")
	end
end

-- *** NEW HELPER: Disconnect Died Listeners ***
local function disconnectDiedListeners(session)
	if session and session.diedConnections then
		log("Disconnecting Humanoid.Died listeners.")
		for _, conn in ipairs(session.diedConnections) do
			if conn and conn.Connected then
				conn:Disconnect()
			end
		end
		session.diedConnections = nil -- Clear the connections
	end
end

-- Main Service Table
local CombatService = {}

-- CheckCombatCooldown (Same as before)
function CombatService:CheckCombatCooldown(playerID)
	local turnSystem = getTurnSystem()
	return turnSystem and turnSystem:HasCombatCooldown(playerID) or false
end

-- Initiate the pre-combat sequence (No significant changes needed here for this request)
function CombatService:InitiatePreCombat(player1, player2, tileId)
	if isCombatActive then
		log("Cannot initiate combat, another session is already active.")
		return false
	end

	-- Cooldown check (Same as before)
	if self:CheckCombatCooldown(player1.UserId) or self:CheckCombatCooldown(player2.UserId) then
		log("Cannot initiate combat, a player is on cooldown.")
		return false
	end

	log("Initiating Pre-Combat between " .. player1.Name .. " and " .. player2.Name .. " on tile " .. tileId)
	isCombatActive = true

	local boardSystem = getBoardSystem()
	local turnSystem = getTurnSystem()
	if not boardSystem or not turnSystem then
		warn("[CombatService] Cannot initiate combat: Missing required systems.")
		isCombatActive = false
		return false
	end

	local char1 = player1.Character
	local hum1 = char1 and char1:FindFirstChildOfClass("Humanoid")
	local char2 = player2.Character
	local hum2 = char2 and char2:FindFirstChildOfClass("Humanoid")

	if not hum1 or not hum2 then
		warn("[CombatService] Cannot initiate combat: Humanoid not found.")
		isCombatActive = false
		return false
	end

	local originalPos1 = char1:FindFirstChild("HumanoidRootPart") and char1.HumanoidRootPart.Position
	local originalPos2 = char2:FindFirstChild("HumanoidRootPart") and char2.HumanoidRootPart.Position
	if not originalPos1 or not originalPos2 then
		warn("[CombatService] Cannot get original positions.")
		isCombatActive = false
		return false
	end

	local currentTurnPlayerId = turnSystem:GetCurrentPlayerTurn()

	activeCombatSession = {
		player1Id = player1.UserId,
		player2Id = player2.UserId,
		originalTileId = tileId,
		originalPos1 = originalPos1,
		originalPos2 = originalPos2,
		timerEndTime = tick() + PRE_COMBAT_DURATION,
		currentTurnPlayerId = currentTurnPlayerId,
		timerThread = nil,
		diedConnections = {}
	}

	log("Pausing Turn System, setting up client states, warping players...")
	turnSystem:PauseTurns()
	setSystemEnabledEvent:FireClient(player1, "CameraSystem", false); setSystemEnabledEvent:FireClient(player1, "DiceRollHandler", false); setSystemEnabledEvent:FireClient(player1, "PlayerControls", true)
	setSystemEnabledEvent:FireClient(player2, "CameraSystem", false); setSystemEnabledEvent:FireClient(player2, "DiceRollHandler", false); setSystemEnabledEvent:FireClient(player2, "PlayerControls", true)
	teleportPlayer(player1, COMBAT_AREA_POSITION + Vector3.new(-10, 0, 0))
	teleportPlayer(player2, COMBAT_AREA_POSITION + Vector3.new(10, 0, 0))

	log("Starting combat timer on clients...")
	setCombatStateEvent:FireClient(player1, true, PRE_COMBAT_DURATION)
	setCombatStateEvent:FireClient(player2, true, PRE_COMBAT_DURATION)
	for _, p in pairs(Players:GetPlayers()) do
		if p.UserId ~= player1.UserId and p.UserId ~= player2.UserId then
			setCombatStateEvent:FireClient(p, true, 0)
		end
	end

	log("Connecting Humanoid.Died listeners.")
	local diedConnection1 = hum1.Died:Connect(function()
		log("Humanoid.Died fired for player 1: " .. player1.Name)
		if isCombatActive and activeCombatSession and activeCombatSession.player1Id == player1.UserId and activeCombatSession.player2Id == player2.UserId then
			log("Death occurred during active combat. Player 2 ("..player2.Name..") wins.")
			self:HandlePlayerDeathInCombat(player1, player2)
		else
			log("Death occurred but not during this active combat session or session mismatch.")
		end
	end)
	table.insert(activeCombatSession.diedConnections, diedConnection1)

	local diedConnection2 = hum2.Died:Connect(function()
		log("Humanoid.Died fired for player 2: " .. player2.Name)
		if isCombatActive and activeCombatSession and activeCombatSession.player1Id == player1.UserId and activeCombatSession.player2Id == player2.UserId then
			log("Death occurred during active combat. Player 1 ("..player1.Name..") wins.")
			self:HandlePlayerDeathInCombat(player2, player1)
		else
			log("Death occurred but not during this active combat session or session mismatch.")
		end
	end)
	table.insert(activeCombatSession.diedConnections, diedConnection2)

	log("Starting server-side timeout timer...")
	activeCombatSession.timerThread = task.delay(PRE_COMBAT_DURATION, function()
		if isCombatActive and activeCombatSession and
			activeCombatSession.player1Id == player1.UserId and
			activeCombatSession.player2Id == player2.UserId then
			log("Combat timer finished (Timeout). Resolving session.")
			CombatService:ResolvePreCombat()
		else
			log("Combat timer finished, but session already ended/changed.")
		end
	end)

	log("Combat initiated. Monitoring Humanoid.Died and timer.")
	return true
end

-- Handle Player Death During Combat (No changes needed here)
function CombatService:HandlePlayerDeathInCombat(deadPlayer, remainingPlayer)
	log("--- HandlePlayerDeathInCombat START ---")
	if not isCombatActive or not activeCombatSession then
		log("HandlePlayerDeathInCombat called but no active combat session.")
		log("--- HandlePlayerDeathInCombat END (No Session) ---")
		return
	end

	if not deadPlayer or not remainingPlayer or
		not ((activeCombatSession.player1Id == deadPlayer.UserId and activeCombatSession.player2Id == remainingPlayer.UserId) or
			(activeCombatSession.player2Id == deadPlayer.UserId and activeCombatSession.player1Id == remainingPlayer.UserId)) then
		log("HandlePlayerDeathInCombat called with incorrect players for the current session. Aborting.")
		log("--- HandlePlayerDeathInCombat END (Player Mismatch) ---")
		return
	end

	log("Player " .. deadPlayer.Name .. " confirmed dead. Winner: " .. remainingPlayer.Name)
	disconnectDiedListeners(activeCombatSession)
	log("Calling EndCombatWithWinner...")
	self:EndCombatWithWinner(remainingPlayer, deadPlayer)
	log("--- HandlePlayerDeathInCombat END ---")
end

-- End Combat with a Winner (Added TurnSystem:OnPlayerDeath call)
function CombatService:EndCombatWithWinner(winner, loser)
	log("--- EndCombatWithWinner START --- Winner: " .. winner.Name .. ", Loser: " .. loser.Name)
	local wasCombatActive = isCombatActive
	local currentSession = activeCombatSession

	if not wasCombatActive or not currentSession then
		log("EndCombatWithWinner called but combat was not active or session was already cleared. Aborting.")
		disconnectDiedListeners(currentSession)
		return false
	end

	if currentSession.timerThread then
		log("Cancelling combat timeout timer.")
		task.cancel(currentSession.timerThread)
	end

	disconnectDiedListeners(currentSession)

	local boardSystem = getBoardSystem()
	local turnSystem = getTurnSystem() -- Get TurnSystem instance
	local checkpointSystem = getCheckpointSystem()

	if not boardSystem or not turnSystem or not checkpointSystem then -- Check turnSystem
		warn("[CombatService] Cannot end combat: Missing required systems (Board, Turn, or Checkpoint).")
		setCombatStateEvent:FireAllClients(false, 0)
		activeCombatSession = nil
		isCombatActive = false
		return false
	end

	-- Extract data before clearing
	local originalTileId = currentSession.originalTileId
	local winnerOriginalPos = (winner.UserId == currentSession.player1Id) and currentSession.originalPos1 or currentSession.originalPos2
	local currentTurnPlayerId = currentSession.currentTurnPlayerId -- Whose turn it was when combat started

	log("Clearing active combat session data early.")
	activeCombatSession = nil
	isCombatActive = false -- Set inactive now

	-- 2. Set Combat Cooldowns
	log("Setting combat cooldowns.")
	turnSystem:SetCombatCooldown(winner.UserId, COMBAT_COOLDOWN_TURNS)
	turnSystem:SetCombatCooldown(loser.UserId, COMBAT_COOLDOWN_TURNS)

	-- *** NEW: Inform TurnSystem about the death ***
	log("Informing TurnSystem that player " .. loser.UserId .. " died.")
	local success, err = pcall(turnSystem.OnPlayerDeath, turnSystem, loser.UserId)
	if not success then
		warn("[CombatService] Error calling TurnSystem:OnPlayerDeath for loser " .. loser.UserId .. ": " .. tostring(err))
	end
	-- *** END NEW ***

	-- 3. Handle Loser Respawn
	log("Processing loser (" .. loser.Name .. ") respawn.")
	local respawnTileId = checkpointSystem:GetPlayerRespawnTileId(loser)
	local respawnPosition = checkpointSystem:GetPlayerRespawnPosition(loser)
	if not respawnPosition then
		warn("[CombatService] Could not get respawn position for loser " .. loser.Name .. ". Using fallback.")
		respawnPosition = Vector3.new(35.778, 0.6, -15.24)
	end
	log("Loser " .. loser.Name .. " respawning at Tile " .. respawnTileId .. " Pos: " .. tostring(respawnPosition))
	teleportPlayer(loser, respawnPosition)
	boardSystem:SetPlayerPosition(loser.UserId, respawnTileId) -- Update board position AFTER teleport

	-- 4. Handle Winner Return
	log("Returning winner (" .. winner.Name .. ") to original combat tile " .. originalTileId)
	if winnerOriginalPos then
		teleportPlayer(winner, winnerOriginalPos)
		boardSystem:SetPlayerPosition(winner.UserId, originalTileId) -- Update board position AFTER teleport
	else
		warn("[CombatService] Could not get original position for winner " .. winner.Name .. ".")
		local tilePos = boardSystem:GetTilePosition(originalTileId)
		if tilePos then teleportPlayer(winner, tilePos) end
		boardSystem:SetPlayerPosition(winner.UserId, originalTileId)
	end

	-- Wait for visuals (Respawn Delay)
	log("Waiting " .. RESPAWN_VISUAL_DELAY .. " seconds for respawn/teleport visual...")
	task.wait(RESPAWN_VISUAL_DELAY)

	-- 5. Resume Turn System & End Originating Turn
	log("Resuming Turn System.")
	turnSystem:ResumeTurns() -- Resume first
	task.wait(0.1) -- Short delay after resuming

	-- Now, end the turn that was active when combat *started*
	local playerWhoseTurnItWas = Players:GetPlayerByUserId(currentTurnPlayerId)
	if playerWhoseTurnItWas then
		log("Attempting to end turn for player " .. playerWhoseTurnItWas.Name .. " (ID: " .. currentTurnPlayerId .. ") which was active when combat started.")
		-- Check if the turn system *thinks* it's still this player's turn (it might not be if ResumeTurns changed it)
		if turnSystem:GetCurrentPlayerTurn() == currentTurnPlayerId then
			turnSystem:EndPlayerTurn(currentTurnPlayerId, "combat_win_resolved")
		else
			log("Turn changed after resuming or wasn't " .. currentTurnPlayerId .. " anymore. Current turn is: " .. tostring(turnSystem:GetCurrentPlayerTurn()) .. ". Skipping EndPlayerTurn for originating player.")
			-- If the turn somehow already advanced, we might need to force the next turn calculation again? Or just let it be.
			-- For now, just log it. If problems persist, we might need to call NextTurn explicitly here if the current turn isn't the originating one.
		end
	else
		warn("[CombatService] Player " .. currentTurnPlayerId .. " (whose turn it was) not found after combat. Cannot end their turn.")
		-- Maybe call NextTurn if the current turn is nil?
		if turnSystem:GetCurrentPlayerTurn() == nil then
			log("Current turn is nil after resume, attempting to advance.")
			turnSystem:NextTurn()
		end
	end

	-- 6. Re-enable Client Systems & Lock Controls
	log("Re-enabling standard client systems and locking controls.")
	setSystemEnabledEvent:FireClient(winner, "CameraSystem", true); setSystemEnabledEvent:FireClient(winner, "DiceRollHandler", true); setSystemEnabledEvent:FireClient(winner, "PlayerControls", false)
	if combatCooldownEvent then combatCooldownEvent:FireClient(winner, COMBAT_COOLDOWN_TURNS) end
	setSystemEnabledEvent:FireClient(loser, "CameraSystem", true); setSystemEnabledEvent:FireClient(loser, "DiceRollHandler", true); setSystemEnabledEvent:FireClient(loser, "PlayerControls", false)
	if combatCooldownEvent then combatCooldownEvent:FireClient(loser, COMBAT_COOLDOWN_TURNS) end

	-- 7. End Combat State on Clients
	log("Ending combat state on all clients.")
	setCombatStateEvent:FireAllClients(false, 0) -- Signal combat end

	log("--- EndCombatWithWinner END --- Combat resolution complete.")
	return true
end


-- Resolve the pre-combat sequence (Timeout Scenario - No changes needed here)
function CombatService:ResolvePreCombat()
	log("--- ResolvePreCombat START (Timeout Scenario) ---")
	local wasCombatActive = isCombatActive
	local currentSession = activeCombatSession

	if not wasCombatActive or not currentSession then
		log("ResolvePreCombat called but combat not active or session already cleared. Aborting.")
		return false
	end

	if not currentSession.timerThread then
		log("ResolvePreCombat called, but timer thread is nil (likely resolved by death). Aborting.")
		disconnectDiedListeners(currentSession)
		activeCombatSession = nil
		isCombatActive = false
		return false
	end

	log("Resolving Pre-Combat session due to TIMEOUT.")
	disconnectDiedListeners(currentSession)

	local player1Id = currentSession.player1Id
	local player2Id = currentSession.player2Id
	local originalPos1 = currentSession.originalPos1
	local originalPos2 = currentSession.originalPos2
	local currentTurnPlayerId = currentSession.currentTurnPlayerId
	local originalTileId = currentSession.originalTileId

	log("Clearing active combat session data (Timeout).")
	activeCombatSession = nil
	isCombatActive = false

	local player1 = Players:GetPlayerByUserId(player1Id)
	local player2 = Players:GetPlayerByUserId(player2Id)
	local turnSystem = getTurnSystem()
	local boardSystem = getBoardSystem()

	if turnSystem then
		if player1 then turnSystem:SetCombatCooldown(player1.UserId, COMBAT_COOLDOWN_TURNS) end
		if player2 then turnSystem:SetCombatCooldown(player2.UserId, COMBAT_COOLDOWN_TURNS) end
	end

	log("Warping players back to original positions (Timeout).")
	if player1 then
		teleportPlayer(player1, originalPos1)
		if boardSystem then boardSystem:SetPlayerPosition(player1.UserId, originalTileId) end
	end
	if player2 then
		teleportPlayer(player2, originalPos2)
		if boardSystem then boardSystem:SetPlayerPosition(player2.UserId, originalTileId) end
	end

	if turnSystem then
		log("Resuming Turn System (Timeout).")
		turnSystem:ResumeTurns()
		task.wait(0.5)
		local currentPlayerTurn = turnSystem:GetCurrentPlayerTurn()
		if currentPlayerTurn and currentPlayerTurn == currentTurnPlayerId then
			log("Ending originating turn (Timeout)...")
			turnSystem:EndPlayerTurn(currentPlayerTurn, "combat_timeout")
		else
			log("Turn already changed (Timeout), skipping EndPlayerTurn.")
		end
	end

	log("Re-enabling client systems (Timeout).")
	if player1 then
		setSystemEnabledEvent:FireClient(player1, "CameraSystem", true); setSystemEnabledEvent:FireClient(player1, "DiceRollHandler", true); setSystemEnabledEvent:FireClient(player1, "PlayerControls", false)
		if combatCooldownEvent then combatCooldownEvent:FireClient(player1, COMBAT_COOLDOWN_TURNS) end
	end
	if player2 then
		setSystemEnabledEvent:FireClient(player2, "CameraSystem", true); setSystemEnabledEvent:FireClient(player2, "DiceRollHandler", true); setSystemEnabledEvent:FireClient(player2, "PlayerControls", false)
		if combatCooldownEvent then combatCooldownEvent:FireClient(player2, COMBAT_COOLDOWN_TURNS) end
	end

	log("Ending combat state on clients (Timeout).")
	setCombatStateEvent:FireAllClients(false, 0)

	log("--- ResolvePreCombat END (Timeout Scenario) ---")
	return true
end

-- IsCombatActive (Same as before)
function CombatService:IsCombatActive()
	return isCombatActive
end

-- InitializeDashSystem (Same as before)
function CombatService:InitializeDashSystem()
	if DashSystem then return DashSystem end
	local success, dashSystemModule = pcall(require, ServerStorage.Modules.MovementSystem)
	if success and dashSystemModule then
		DashSystem = dashSystemModule.new(self)
		DashSystem:Register()
		log("DashSystem initialized and registered")
		return DashSystem
	else
		warn("[CombatService] Failed to load MovementSystem (DashSystem): ", dashSystemModule)
		return nil
	end
end

-- Register with GameManager (Same as before)
local function registerWithGameManager()
	local gameManager = _G.GameManager or (task.wait(2) and _G.GameManager)
	if gameManager then
		gameManager.combatService = CombatService
		log("CombatService registered with GameManager.")
		CombatService:InitializeDashSystem()
		CheckpointSystem = gameManager.checkpointSystem
		if CheckpointSystem then log("Found CheckpointSystem via GameManager.") end
	else
		warn("[CombatService] GameManager not found.")
	end
	if not CheckpointSystem then CheckpointSystem = _G.CheckpointSystem end
	if not CheckpointSystem then warn("[CombatService] CheckpointSystem could not be found!") end
end

registerWithGameManager()

log("CombatService Initialized.")
return CombatService
