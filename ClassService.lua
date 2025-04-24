-- ClassService.server.lua
-- Handles class selection and management on the server side
-- Location: ServerScriptService/Services/ClassService.server.lua
-- Version: 1.1.0 (Removed readiness checks and UI triggers, relies on GameManager)

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

-- Get GameManager from global (Keep this helper function)
local function getGameManager()
	local startTime = tick()
	local attempts = 0
	local maxAttempts = 20
	while not _G.GameManager and attempts < maxAttempts do
		task.wait(0.5) -- Use task.wait
		attempts = attempts + 1
	end
	if not _G.GameManager then
		warn("[ClassService] Failed to get GameManager after " .. maxAttempts .. " attempts.")
	else
		-- debugLog("GameManager found successfully.") -- Reduce log spam
	end
	return _G.GameManager
end

-- REMOVED: playerReadyStatus tracking (Handled by GameManager)
-- local playerReadyStatus = {}

-- Initialize player selection tracking (Keep this for actual class choices)
local playerSelections = {}
-- REMOVED: classSelectionFinished flag (GameManager controls game state)
-- local classSelectionFinished = false

-- Initialize remote events (Keep this function)
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
	local playerSelectedClassEvent = ensureRemoteEvent(uiRemotes, "PlayerSelectedClass") -- Client fires this when selecting
	local updateClassSelectionEvent = ensureRemoteEvent(uiRemotes, "UpdateClassSelection") -- Server fires this to update UI
	local showMainGameUIEvent = ensureRemoteEvent(uiRemotes, "ShowMainGameUI") -- Fired by GameManager
	local levelUpEvent = ensureRemoteEvent(uiRemotes, "LevelUp")
	local classLevelUpEvent = ensureRemoteEvent(uiRemotes, "ClassLevelUp")
	local updatePlayerStatsEvent = ensureRemoteEvent(uiRemotes, "UpdatePlayerStats")
	local showClassSelectionEvent = ensureRemoteEvent(uiRemotes, "ShowClassSelection") -- Fired by GameManager
	local classUpgradeAvailableEvent = ensureRemoteEvent(uiRemotes, "ClassUpgradeAvailable")
	local updateExperienceEvent = ensureRemoteEvent(uiRemotes, "UpdateExperience")

	-- Game Remotes (Ensure StartGame and AddExpDebug exist)
	local startGameEvent = ensureRemoteEvent(gameRemotes, "StartGame") -- Fired by GameManager
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

-- REMOVED: finishClassSelection function
-- This entire logic block is now handled within GameManager's state transitions
-- (specifically StartClassSelectionTimeout and StartGame)
--[[
local function finishClassSelection(remotes)
	-- ... (code removed) ...
end
--]]

-- REMOVED: areAllPlayersReady function (Handled by GameManager)
--[[
local function areAllPlayersReady()
	-- ... (code removed) ...
end
--]]

-- REMOVED: monitorPlayerReadyState function (Handled by GameManager)
--[[
local function monitorPlayerReadyState(gameManager, remotes)
	-- ... (code removed) ...
end
--]]


-- Handle player selection event from client
local function handlePlayerSelection(player, className, remotes)
	if not player or not className then
		debugLog("Invalid player selection parameters")
		return
	end

	local gameManager = getGameManager()
	if not gameManager then
		warn("[ClassService] GameManager not found when handling player selection for " .. player.Name)
		return
	end

	-- Check if the game is actually in the class selection phase via GameManager state
	if not gameManager.gameState or not gameManager.gameState.isClassSelection then
		warn("[ClassService] Ignoring class selection from " .. player.Name .. ", game not in class selection phase.")
		return
	end

	local classInfo = ClassData:GetClassInfo(className)
	if not classInfo then
		debugLog("Invalid class selected by " .. player.Name .. ": " .. tostring(className))
		-- Optional: Notify client of invalid selection?
		return
	end

	-- Store selection locally in ClassService if needed for other logic,
	-- but GameManager is the primary handler now.
	-- playerSelections[player.UserId] = className
	-- debugLog(player.Name .. " selected class: " .. className .. " (local ClassService tracking)")

	-- *** CRITICAL CHANGE: Delegate the handling to GameManager ***
	if gameManager.OnPlayerSelectedClass then
		debugLog("Forwarding player selection ("..className..") for " .. player.Name .. " to GameManager.")
		gameManager:OnPlayerSelectedClass(player, className)
	else
		warn("[ClassService] gameManager:OnPlayerSelectedClass function not found!")
	end

	-- REMOVED: Logic to check if all selected and call finishClassSelection
	-- GameManager's StartClassSelectionTimeout loop handles this now.
	--[[
	local allSelected = true
	-- ... (check logic removed) ...
	if allSelected then
		debugLog("All currently connected players have selected classes.")
		finishClassSelection(remotes)
	end
	--]]
end


-- Reset player selections (Called by GameManager if needed)
local function resetPlayerSelections()
	playerSelections = {}
	-- REMOVED: classSelectionFinished = false
	debugLog("ClassService: Player selections table reset.")
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
		-- Avoid creating a dummy GameManager here, let it fail if necessary
		return nil
	end

	-- Create ClassSystem if needed and assign to GameManager
	-- This assumes ClassSystem is primarily managed/used via GameManager
	if not gameManager.classSystem then
		debugLog("Creating new ClassSystem and assigning to gameManager.classSystem")
		gameManager.classSystem = ClassSystem.new()
		-- Ensure ClassSystem has necessary references if it needs them independently
		-- gameManager.classSystem:Initialize() -- If an init method exists
	elseif not gameManager.classSystem.new then
		warn("[ClassService] gameManager.classSystem exists but seems invalid (missing .new). Recreating.")
		gameManager.classSystem = ClassSystem.new()
	else
		debugLog("ClassSystem already exists in GameManager.")
	end

	-- Set up class assignment handler (This seems like internal ClassSystem logic)
	-- Let's connect these callbacks directly to the instance in GameManager
	if gameManager.classSystem then
		local function handleClassAssignment(player, className, classData)
			-- This might be redundant if PlayerManager/GameManager handles stats/UI updates
			debugLog("ClassSystem assigned " .. className .. " to " .. player.Name .. ". Firing ClassAssigned event.")
			remotes.classAssigned:FireClient(player, className, classData)
		end

		gameManager.classSystem.onClassAssigned = handleClassAssignment
		gameManager.classSystem.onLevelUp = function(player, newLevel, oldLevel, statIncreases)
			debugLog(player.Name .. " Leveled Up: " .. oldLevel .. " -> " .. newLevel)
			remotes.levelUp:FireClient(player, newLevel, statIncreases)
			-- Also update general stats UI
			remotes.updatePlayerStats:FireClient(player, gameManager.playerManager:GetPlayerData(player).stats)
			remotes.updateExperience:FireClient(player, gameManager.classSystem:GetPlayerExperience(player), gameManager.classSystem:GetExpForNextLevel(newLevel))
		end
		gameManager.classSystem.onClassLevelUp = function(player, newClassLevel, oldClassLevel, statIncreases, nextClass)
			debugLog(player.Name .. " Class Leveled Up: " .. oldClassLevel .. " -> " .. newClassLevel)
			remotes.classLevelUp:FireClient(player, newClassLevel, statIncreases, nextClass)
			-- Also update general stats UI
			remotes.updatePlayerStats:FireClient(player, gameManager.playerManager:GetPlayerData(player).stats)
		end
		gameManager.classSystem.onExperienceChanged = function(player, currentExp, requiredExp)
			remotes.updateExperience:FireClient(player, currentExp, requiredExp)
		end
		gameManager.classSystem.onUpgradeAvailable = function(player, available)
			remotes.classUpgradeAvailable:FireClient(player, available)
		end
		debugLog("Connected ClassSystem callbacks (onLevelUp, etc.)")
	else
		warn("[ClassService] ClassSystem not available in GameManager to connect internal callbacks.")
	end

	-- Connect to player selected class event from client
	remotes.playerSelectedClass.OnServerEvent:Connect(function(player, className)
		handlePlayerSelection(player, className, remotes)
	end)
	debugLog("Connected PlayerSelectedClass listener.")

	-- REMOVED: Call to monitorPlayerReadyState
	-- monitorPlayerReadyState(gameManager, remotes)

	-- Add public methods/functions to GameManager for other services to use
	-- Make sure these functions exist/are needed in GameManager context
	gameManager.resetPlayerSelections = resetPlayerSelections -- Keep if GameManager needs to clear ClassService's local table
	-- REMOVED: gameManager.triggerClassSelectionUI assignment

	-- Function to add experience to a player (Delegate to ClassSystem via GameManager)
	gameManager.addExperienceToPlayer = function(player, amount)
		if gameManager.classSystem then
			return gameManager.classSystem:AddExperience(player, amount)
		end
		warn("[ClassService Proxy] addExperienceToPlayer: ClassSystem not available in GameManager.")
		return false
	end

	-- Function to upgrade a player's class (Delegate to ClassSystem via GameManager)
	gameManager.upgradePlayerClass = function(player)
		if gameManager.classSystem then
			return gameManager.classSystem:UpgradePlayerClass(player)
		end
		warn("[ClassService Proxy] upgradePlayerClass: ClassSystem not available in GameManager.")
		return false, "ClassSystem not available"
	end

	-- Get GameRemotes reference (ensure it's done after initializeRemoteEvents)
	local gameRemotesFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GameRemotes")

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
			local currentExp = classSystem:GetPlayerExperience(player) -- Use specific getter

			-- Check if data retrieval was successful
			if not currentLevel or currentExp == nil then -- Check for nil specifically for EXP
				warn(string.format("[ClassService] Could not get current level or EXP for %s (Lvl: %s, Exp: %s).",
					player.Name, tostring(currentLevel), tostring(currentExp)))
				return
			end

			-- คำนวณ EXP ที่ต้องการสำหรับเลเวลถัดไป
			local expForNextLevel = classSystem:GetExpForNextLevel(currentLevel)

			-- Handle case where expForNextLevel might be nil or 0 (max level?)
			if not expForNextLevel or expForNextLevel <= 0 then
				debugLog(string.format("%s is already at max level or EXP requirement is invalid (Lvl %d). Cannot add EXP via debug.", player.Name, currentLevel))
				return
			end

			-- คำนวณ EXP ที่ต้องเพิ่มเพื่อให้ถึงเลเวลถัดไปพอดี + 1
			local expToAdd = (expForNextLevel - currentExp) + 1
			-- ป้องกันกรณีที่ค่าติดลบ (ถ้าเกิดข้อผิดพลาด) หรือเป็น 0
			expToAdd = math.max(1, expToAdd)

			debugLog(string.format("Received AddLevelDebug from %s (Lvl %d, Exp %d). Needs %d for Lvl %d. Adding %d EXP.",
				player.Name, currentLevel, currentExp, expForNextLevel, currentLevel + 1, expToAdd))

			-- เรียกใช้ฟังก์ชันเพิ่ม EXP via GameManager proxy
			if currentManager.addExperienceToPlayer then
				local success = currentManager.addExperienceToPlayer(player, expToAdd)
				if success then
					debugLog(string.format("Added %d EXP to %s successfully (Should reach Lvl %d).", expToAdd, player.Name, currentLevel + 1))
				else
					warn(string.format("Failed to add EXP to %s.", player.Name))
				end
			else
				warn("[ClassService] addExperienceToPlayer function not found in GameManager when handling AddExpDebug.")
			end
		end)
		debugLog("Connected AddLevelDebug listener.")
	else
		warn("[ClassService] AddExpDebug RemoteEvent not found in GameRemotes.")
	end

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

