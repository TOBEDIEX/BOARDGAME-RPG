-- ClassService.server.lua
-- Handles class selection and management on the server side
-- Location: ServerScriptService/Services/ClassService.server.lua
-- Version: 1.0.2 (Added Debug Level Up Listener)

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Debug mode for detailed logging
local DEBUG_MODE = true -- เปิด Debug ไว้ก่อนเพื่อให้เห็น Log การทำงาน

-- Helper function for logging
local function debugLog(message)
	if DEBUG_MODE then
		print("[ClassService] " .. message)
	end
end

-- Load modules
local Modules = ServerStorage:WaitForChild("Modules")
local ClassSystem = require(Modules:WaitForChild("ClassSystem"))
local SharedModules = ReplicatedStorage:WaitForChild("SharedModules")
local ClassData = require(SharedModules:WaitForChild("ClassData"))

-- Get GameManager from global
local function getGameManager()
	local startTime = tick()
	local attempts = 0
	local maxAttempts = 20
	while not _G.GameManager and attempts < maxAttempts do
		wait(0.5)
		attempts = attempts + 1
	end
	if not _G.GameManager then
		warn("[ClassService] Failed to get GameManager after " .. maxAttempts .. " attempts.")
	else
		debugLog("GameManager found successfully.")
	end
	return _G.GameManager
end

-- Initialize player selection tracking
local playerSelections = {}
local playerReadyStatus = {}
local classSelectionFinished = false -- Flag to prevent multiple finishes

-- Initialize remote events
local function initializeRemoteEvents()
	debugLog("Initializing remote events...")

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local uiRemotes = remotes:WaitForChild("UIRemotes")
	local gameRemotes = remotes:WaitForChild("GameRemotes") -- Get GameRemotes folder

	-- Create required remotes if they don't exist
	local function ensureRemoteEvent(parent, name)
		local event = parent:FindFirstChild(name)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = parent
			debugLog("Created RemoteEvent: " .. name)
		end
		return event
	end

	-- UI Remotes
	local classAssignedEvent = ensureRemoteEvent(uiRemotes, "ClassAssigned")
	local playerSelectedClassEvent = ensureRemoteEvent(uiRemotes, "PlayerSelectedClass")
	local updateClassSelectionEvent = ensureRemoteEvent(uiRemotes, "UpdateClassSelection")
	local showMainGameUIEvent = ensureRemoteEvent(uiRemotes, "ShowMainGameUI")
	local levelUpEvent = ensureRemoteEvent(uiRemotes, "LevelUp")
	local classLevelUpEvent = ensureRemoteEvent(uiRemotes, "ClassLevelUp")
	local updatePlayerStatsEvent = ensureRemoteEvent(uiRemotes, "UpdatePlayerStats")
	local showClassSelectionEvent = ensureRemoteEvent(uiRemotes, "ShowClassSelection")
	local classUpgradeAvailableEvent = ensureRemoteEvent(uiRemotes, "ClassUpgradeAvailable")
	local updateExperienceEvent = ensureRemoteEvent(uiRemotes, "UpdateExperience")

	-- Game Remotes (Ensure StartGame and AddExpDebug exist)
	local startGameEvent = ensureRemoteEvent(gameRemotes, "StartGame")
	local addExpDebugEvent = ensureRemoteEvent(gameRemotes, "AddExpDebug") -- Ensure debug event exists


	debugLog("All remote events initialized.")

	return {
		classAssigned = classAssignedEvent,
		playerSelectedClass = playerSelectedClassEvent,
		updateClassSelection = updateClassSelectionEvent,
		showMainGameUI = showMainGameUIEvent,
		levelUp = levelUpEvent,
		classLevelUp = classLevelUpEvent,
		updatePlayerStats = updatePlayerStatsEvent,
		showClassSelection = showClassSelectionEvent,
		classUpgradeAvailable = classUpgradeAvailableEvent,
		updateExperience = updateExperienceEvent,
		startGame = startGameEvent,
		addExpDebug = addExpDebugEvent -- Include debug event
	}
end

-- Finish class selection and transition to game
local function finishClassSelection(remotes)
	if classSelectionFinished then
		debugLog("finishClassSelection called again, ignoring.")
		return -- Prevent running multiple times
	end
	classSelectionFinished = true -- Set flag
	debugLog("Finishing class selection...")

	local gameManager = getGameManager()
	if not gameManager then
		warn("[ClassService] GameManager not found, cannot finish class selection")
		classSelectionFinished = false -- Reset flag if failed
		return
	end

	-- Step 1: Assign classes to all players first
	for userId, className in pairs(playerSelections) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			local classInfo = ClassData:GetClassInfo(className)
			debugLog("Assigning class " .. className .. " to player " .. player.Name)

			if gameManager.classSystem then
				gameManager.classSystem:AssignClassToPlayer(player, className)
			else
				warn("[ClassService] ClassSystem not found during finishClassSelection for " .. player.Name)
			end

			if gameManager.playerManager then
				gameManager.playerManager:SetPlayerClass(player, className)
			else
				warn("[ClassService] PlayerManager not found during finishClassSelection for " .. player.Name)
			end
		else
			warn("[ClassService] Player not found for UserId " .. userId .. " during finishClassSelection.")
		end
	end

	-- Step 2: Wait a moment
	debugLog("Waiting briefly after class assignment...")
	task.wait(1) -- Use task.wait instead of wait()

	-- Step 3: Update UI and Humanoid health
	debugLog("Syncing final stats and Humanoid health for all players...")
	for _, player in pairs(Players:GetPlayers()) do
		if playerSelections[player.UserId] then
			local playerData = gameManager.playerManager and gameManager.playerManager:GetPlayerData(player)
			if playerData and playerData.stats then
				-- PlayerManager's SyncPlayerStats should handle Humanoid updates now
				gameManager.playerManager:SyncPlayerStats(player)

				debugLog(string.format("Final Sync: Synced stats/humanoid for %s: HP=%d/%d, Class=%s",
					player.Name, playerData.stats.hp, playerData.stats.maxHp, playerData.class))
			else
				warn("[ClassService] Final Sync: Failed to get playerData for " .. player.Name)
			end
		end
	end

	-- Show main game UI
	debugLog("Transitioning to main game UI...")
	remotes.showMainGameUI:FireAllClients()
	debugLog("All players transitioned to main game UI")

	-- Start game via GameManager or directly trigger TurnSystem start
	if gameManager.StartGame then
		debugLog("Calling gameManager:StartGame()...")
		gameManager:StartGame()
	elseif gameManager.turnSystem then
		debugLog("Starting turn system directly...")
		if gameManager.playerManager then
			local success = gameManager.turnSystem:CreateTurnOrderFromActivePlayers(gameManager.playerManager)
			if success then
				gameManager.turnSystem:StartTurnSystem()
			else
				warn("[ClassService] Failed to create turn order.")
			end
		else
			warn("[ClassService] Cannot start TurnSystem directly, PlayerManager not found.")
		end
	else
		warn("[ClassService] Cannot start game, TurnSystem not found.")
	end
end


-- Check if all players are loaded (ready for class selection)
local function areAllPlayersReady()
	local allPlayers = Players:GetPlayers()
	if #allPlayers == 0 then return false end -- Need at least one player

	local readyCount = 0
	for _, player in ipairs(allPlayers) do
		if playerReadyStatus[player.UserId] == true then
			readyCount = readyCount + 1
		end
	end
	debugLog(string.format("areAllPlayersReady Check: %d / %d players ready.", readyCount, #allPlayers))
	return readyCount == #allPlayers
end

-- Monitor player ready state from GameManager
local function monitorPlayerReadyState(gameManager, remotes)
	if not gameManager then return end
	debugLog("Starting player ready state monitoring...")

	local gameRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GameRemotes")
	local assetsLoadedEvent = gameRemotes:WaitForChild("AssetsLoaded")

	assetsLoadedEvent.OnServerEvent:Connect(function(player)
		if not playerReadyStatus[player.UserId] then
			playerReadyStatus[player.UserId] = true
			debugLog("Player assets loaded: " .. player.Name)

			if areAllPlayersReady() then
				debugLog("All players assets loaded. Triggering class selection UI.")
				remotes.showClassSelection:FireAllClients()
			end
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		playerReadyStatus[player.UserId] = false
		debugLog("Player joined: " .. player.Name .. " (Marked as not ready)")
	end)

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		playerReadyStatus[userId] = nil
		local wasSelected = playerSelections[userId]
		playerSelections[userId] = nil
		debugLog("Player left: " .. player.Name .. (wasSelected and " (Had selected class: "..wasSelected..")" or " (Had not selected class)"))

		if not classSelectionFinished then
			local allRemainingSelected = true
			local currentPlayers = Players:GetPlayers()
			if #currentPlayers > 0 then
				for _, plr in pairs(currentPlayers) do
					if not playerSelections[plr.UserId] then
						allRemainingSelected = false
						break
					end
				end
			else
				allRemainingSelected = false
			end

			if allRemainingSelected then
				debugLog("Player left, but all remaining players have now selected. Finishing selection.")
				finishClassSelection(remotes)
			else
				remotes.updateClassSelection:FireAllClients(userId, nil)
			end
		end
	end)

	for _, player in pairs(Players:GetPlayers()) do
		if playerReadyStatus[player.UserId] == nil then
			playerReadyStatus[player.UserId] = false
		end
	end

	debugLog("Player ready state monitoring initialized.")
end


-- Handle player selection
local function handlePlayerSelection(player, className, remotes)
	if not player or not className then
		debugLog("Invalid player selection parameters")
		return
	end

	if classSelectionFinished then
		debugLog("Ignoring class selection from " .. player.Name .. ", selection already finished.")
		return
	end

	local classInfo = ClassData:GetClassInfo(className)
	if not classInfo then
		debugLog("Invalid class selected by " .. player.Name .. ": " .. tostring(className))
		return
	end

	playerSelections[player.UserId] = className
	debugLog(player.Name .. " selected class: " .. className)

	remotes.updateClassSelection:FireAllClients(player.UserId, className)

	local allSelected = true
	local currentPlayers = Players:GetPlayers()
	if #currentPlayers == 0 then
		allSelected = false
	end

	for _, plr in pairs(currentPlayers) do
		if not playerSelections[plr.UserId] then
			allSelected = false
			debugLog("Waiting for player " .. plr.Name .. " to select.")
			break
		end
	end

	if allSelected then
		debugLog("All currently connected players have selected classes.")
		finishClassSelection(remotes)
	end
end


-- Reset player selections (e.g., for a new round)
local function resetPlayerSelections()
	playerSelections = {}
	classSelectionFinished = false -- Reset finished flag
	debugLog("Player selections reset. Ready for new selection.")
end

-- Initialize service
local function initializeClassService()
	debugLog("Initializing ClassService...")

	-- Initialize remote events first
	local remotes = initializeRemoteEvents()
	debugLog("Remote events initialized")

	-- Wait for GameManager
	local gameManager = getGameManager()
	if not gameManager then
		warn("[ClassService] FATAL: GameManager not found after wait. Service cannot fully initialize.")
		gameManager = {}
		_G.GameManager = gameManager
	end

	-- Create ClassSystem if needed and assign to GameManager
	if not gameManager.classSystem then
		debugLog("Creating new ClassSystem and assigning to gameManager.classSystem")
		gameManager.classSystem = ClassSystem.new()
	end

	-- Set up class assignment handler
	local function handleClassAssignment(player, className, classData)
		debugLog("Handling class assignment notification for " .. player.Name .. ": " .. className)
		remotes.classAssigned:FireClient(player, className, classData)
	end

	-- Connect to player selected class event from client
	remotes.playerSelectedClass.OnServerEvent:Connect(function(player, className)
		handlePlayerSelection(player, className, remotes)
	end)

	-- Connect internal event handlers within ClassSystem
	if gameManager.classSystem then
		gameManager.classSystem.onClassAssigned = handleClassAssignment
		gameManager.classSystem.onLevelUp = function(player, newLevel, oldLevel, statIncreases)
			debugLog(player.Name .. " Leveled Up: " .. oldLevel .. " -> " .. newLevel)
			remotes.levelUp:FireClient(player, newLevel, statIncreases)
		end
		gameManager.classSystem.onClassLevelUp = function(player, newClassLevel, oldClassLevel, statIncreases, nextClass)
			debugLog(player.Name .. " Class Leveled Up: " .. oldClassLevel .. " -> " .. newClassLevel)
			remotes.classLevelUp:FireClient(player, newClassLevel, statIncreases, nextClass)
		end
	else
		warn("[ClassService] ClassSystem not available to connect internal callbacks.")
	end

	-- Set up player ready monitoring
	monitorPlayerReadyState(gameManager, remotes)

	-- Add public methods/functions to GameManager for other services to use
	gameManager.resetPlayerSelections = resetPlayerSelections
	gameManager.triggerClassSelectionUI = function()
		resetPlayerSelections()
		if areAllPlayersReady() then
			debugLog("Triggering class selection UI for all players.")
			remotes.showClassSelection:FireAllClients()
		else
			debugLog("Cannot trigger class selection UI, not all players are ready.")
			-- remotes.showClassSelection:FireAllClients() -- Option to force show
		end
	end

	-- Function to add experience to a player
	gameManager.addExperienceToPlayer = function(player, amount)
		if gameManager.classSystem then
			return gameManager.classSystem:AddExperience(player, amount)
		end
		warn("[ClassService] addExperienceToPlayer: ClassSystem not available.")
		return false
	end

	-- Function to upgrade a player's class
	gameManager.upgradePlayerClass = function(player)
		if gameManager.classSystem then
			return gameManager.classSystem:UpgradePlayerClass(player)
		end
		warn("[ClassService] upgradePlayerClass: ClassSystem not available.")
		return false, "ClassSystem not available"
	end

	-- Get GameRemotes reference (ensure it's done after initializeRemoteEvents)
	local gameRemotesFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GameRemotes")

	-- >> เพิ่มโค้ดส่วนนี้เข้าไป <<
	-- Listener for Debug Add EXP/Level RemoteEvent
	local addExpDebugEvent = gameRemotesFolder:WaitForChild("AddExpDebug") -- Use reference from above
	if addExpDebugEvent then
		addExpDebugEvent.OnServerEvent:Connect(function(player)
			-- ตรวจสอบว่ามี GameManager และ ClassSystem หรือไม่
			local currentManager = getGameManager() -- เรียกใช้ฟังก์ชันเพื่อเอา GameManager ล่าสุด
			if not currentManager or not currentManager.classSystem then
				warn("[ClassService] GameManager or ClassSystem not found when handling AddExpDebug.")
				return -- ออกจากการทำงานถ้าไม่มีระบบที่ต้องการ
			end

			local classSystem = currentManager.classSystem
			local userId = player.UserId

			-- ดึงข้อมูลเลเวลและ EXP ปัจจุบัน
			local currentLevel = classSystem:GetPlayerLevel(player)
			-- Assuming playerExp is accessible like this, adjust if needed based on ClassSystem structure
			local currentExp = classSystem.playerExp and classSystem.playerExp[userId]

			-- Check if data retrieval was successful
			if not currentLevel or currentExp == nil then -- Check for nil specifically for EXP
				warn(string.format("[ClassService] Could not get current level or EXP for %s (Lvl: %s, Exp: %s).",
					player.Name, tostring(currentLevel), tostring(currentExp)))
				return
			end

			-- คำนวณ EXP ที่ต้องการสำหรับเลเวลถัดไป
			local expForNextLevel = classSystem:GetExpForNextLevel(currentLevel)

			-- คำนวณ EXP ที่ต้องเพิ่มเพื่อให้ถึงเลเวลถัดไปพอดี + 1
			local expToAdd = (expForNextLevel - currentExp) + 1
			-- ป้องกันกรณีที่ค่าติดลบ (ถ้าเกิดข้อผิดพลาด) หรือเป็น 0
			expToAdd = math.max(1, expToAdd)

			debugLog(string.format("Received AddLevelDebug from %s (Lvl %d, Exp %d). Needs %d for Lvl %d. Adding %d EXP.",
				player.Name, currentLevel, currentExp, expForNextLevel, currentLevel + 1, expToAdd))

			-- เรียกใช้ฟังก์ชันเพิ่ม EXP
			if currentManager.addExperienceToPlayer then
				local success = currentManager.addExperienceToPlayer(player, expToAdd)
				if success then
					debugLog(string.format("Added %d EXP to %s successfully (Should reach Lvl %d).", expToAdd, player.Name, currentLevel + 1))
				else
					warn(string.format("Failed to add EXP to %s.", player.Name))
				end
			else
				warn("[ClassService] addExperienceToPlayer function not found when handling AddExpDebug.")
			end
		end)
		debugLog("Connected AddLevelDebug listener.") -- อาจจะเปลี่ยนชื่อ Log เป็น AddLevelDebug
	else
		warn("[ClassService] AddExpDebug RemoteEvent not found in GameRemotes.")
	end
	-- >> สิ้นสุดโค้ดส่วนที่เพิ่ม <<

	debugLog("ClassService initialization complete")
	return gameManager -- Return the potentially modified gameManager
end

-- Enable debug logging
local function setDebugMode(enabled)
	DEBUG_MODE = enabled
	debugLog("Debug mode " .. (enabled and "enabled" or "disabled"))
end

-- Initialize with debug mode setting
setDebugMode(true) -- Set to true for verbose logging during testing

-- Start the service
local gameManagerInstance = initializeClassService()

-- Return the service itself or the modified gameManager?
-- Returning gameManager seems appropriate as this service modifies it.
return gameManagerInstance
