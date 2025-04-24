-- GameManager.lua
-- Main module that controls all game logic
-- Version: 3.2.3 (Fixed race condition in StartGame transition)

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
local LOADING_TIMEOUT = 120 -- เวลาสูงสุดที่รอในหน้า Loading (วินาที) ก่อนเตะออก

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
	self.playersReady = {} -- Tracks players who have finished loading assets (client-side)
	self.playersSelectedClass = {}
	self.playerJoinTimes = {} -- Tracks when each player joined (for timeout)

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

	-- เพิ่ม Event สำหรับ Client แจ้งว่าโหลด Asset เสร็จ
	local function ensureServerEvent(parent, name)
		local event = parent:FindFirstChild(name)
		if not event then
			warn("Creating missing RemoteScript:", name, "in", parent.Name)
			event = Instance.new("RemoteEvent", parent) -- ใช้ RemoteEvent เหมือนเดิม แต่ Server จะ Listen
			event.Name = name
		end
		return event
	end

	return {
		game = {
			startGame = ensureEvent(gameRemotes, "StartGame"),
			endGame = ensureEvent(gameRemotes, "EndGame"),
			updateTurn = ensureEvent(gameRemotes, "UpdateTurn"),
			gameStats = ensureEvent(gameRemotes, "GameStats"),
			assetsLoaded = ensureServerEvent(gameRemotes, "AssetsLoaded") -- Client fires this
		},
		ui = {
			updateLoading = ensureEvent(uiRemotes, "UpdateLoading"), -- Server sends progress (optional)
			updatePlayersReady = ensureEvent(uiRemotes, "UpdatePlayersReady"), -- Server sends ready count
			showClassSelection = ensureEvent(uiRemotes, "ShowClassSelection"), -- Server signals transition
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

	-- Connect AssetsLoaded event from clients
	if self.remotes.game.assetsLoaded then
		self.remotes.game.assetsLoaded.OnServerEvent:Connect(function(player)
			self:OnPlayerReady(player) -- Call OnPlayerReady when client signals assets loaded
		end)
		print("[GameManager] Connected to AssetsLoaded event from clients.")
	else
		warn("[GameManager] AssetsLoaded remote event not found!")
	end

	-- Initialize existing players
	for _, player in pairs(Players:GetPlayers()) do
		self:OnPlayerAdded(player)
	end

	-- Start player check loop
	self:StartPlayerCheck()
end

function GameManager:StartPlayerCheck()
	-- Clear existing timer
	if self.timers.playerCheck then
		if self.timers.playerCheck.Connected then
			self.timers.playerCheck:Disconnect()
		end
		self.timers.playerCheck = nil
	end

	-- Start timestamp tracking for the loop itself
	self.timers.playerCheckTimestamp = tick()
	print("[GameManager] Player check timer starting/restarting...")

	-- Check player count and status every second
	self.timers.playerCheck = RunService.Heartbeat:Connect(function()
		-- Calculate elapsed time for loop frequency control
		local currentTime = tick()
		local elapsedTime = currentTime - self.timers.playerCheckTimestamp
		if elapsedTime < 1 then return end -- Run check approx every 1 second

		-- Update timestamp
		self.timers.playerCheckTimestamp = currentTime

		-- Skip if game ended
		if self.gameState.isGameEnded then
			if self.timers.playerCheck then
				if self.timers.playerCheck.Connected then self.timers.playerCheck:Disconnect() end
				self.timers.playerCheck = nil
				print("[GameManager] Player check timer stopped (game ended).")
			end
			return
		end

		local playerCount = self.playerManager:GetPlayerCount()
		local readyCount = self:CountReadyPlayers()

		-- Update ready players UI for all clients
		self.remotes.ui.updatePlayersReady:FireAllClients(readyCount, playerCount)

		-- Check Loading Timeout for players still loading
		if self.gameState.isLoading then
			for _, player in pairs(Players:GetPlayers()) do
				local userId = player.UserId
				-- Check if player is still considered loading by the server and has a join time
				if self.playersReady and not self.playersReady[userId] and self.playerJoinTimes and self.playerJoinTimes[userId] then
					local timeSpentLoading = currentTime - self.playerJoinTimes[userId]
					if timeSpentLoading > LOADING_TIMEOUT then
						print("[GameManager] Kicking player", player.Name, "due to loading timeout:", timeSpentLoading, "seconds")
						player:Kick("You were disconnected for taking too long to load.")
						-- OnPlayerRemoving will handle cleanup
					end
				end
			end
		end

		-- Check game start conditions ONLY if we are currently in the loading phase
		if self.gameState.isLoading then
			-- Condition 1: Do we have enough players?
			if playerCount >= MIN_PLAYERS then
				-- Condition 2: Are ALL connected players ready (finished loading assets)?
				if self:AreAllPlayersReady() then
					print("[GameManager] Minimum players reached and all players ready. Finishing loading.")
					self:FinishLoading() -- Attempt to finish loading
					-- FinishLoading now has its own check and will stop the timer if successful
				else
					-- Enough players, but waiting for some to load
					-- print("[GameManager] Waiting for players to finish loading assets (" .. readyCount .. "/" .. playerCount .. ")")
				end
			else
				-- Not enough players yet, stay in loading state
				-- print("[GameManager] Waiting for more players (" .. playerCount .. "/" .. MIN_PLAYERS .. ")")
				-- Keep isLoading = true (already true)
			end
			-- Check conditions if the game has already started (e.g., player drops below min)
		elseif self.gameState.isGameStarted then
			-- Check if player count drops below minimum during the game
			if playerCount < MIN_PLAYERS then
				print("[GameManager] Player count dropped below minimum during game. Ending game.")
				self:EndGame("Not enough players to continue (minimum " .. MIN_PLAYERS .. " required)")
			end
		end
	end)
end

-- Counts players marked as ready by the server (meaning they fired AssetsLoaded)
function GameManager:CountReadyPlayers()
	local readyCount = 0
	if not self.playersReady then return 0 end -- Handle nil table case

	for userId, isReady in pairs(self.playersReady) do
		-- Ensure the player still exists before counting them as ready
		if isReady and Players:GetPlayerByUserId(userId) then
			readyCount = readyCount + 1
		elseif not Players:GetPlayerByUserId(userId) then
			-- Clean up ready status if player left but wasn't cleared somehow
			self.playersReady[userId] = nil
		end
	end
	return readyCount
end

-- Checks if ALL currently connected players are marked as ready by the server
function GameManager:AreAllPlayersReady()
	local playerCount = self.playerManager:GetPlayerCount()
	if playerCount == 0 then return false end -- Cannot be ready if no players

	local readyCount = self:CountReadyPlayers()
	-- Check if the number of ready players equals the total number of players
	return readyCount == playerCount and playerCount > 0 -- Ensure readyCount matches and is not zero
end

function GameManager:OnPlayerAdded(player)
	local userId = player.UserId
	print("[GameManager] Player added:", player.Name, "(ID:", userId, ")")

	-- Register player in PlayerManager
	self.playerManager:RegisterPlayer(player)

	-- Ensure tracking tables exist
	if not self.playersReady then self.playersReady = {} end
	if not self.playerJoinTimes then self.playerJoinTimes = {} end

	-- Set initial ready status to false (waiting for client AssetsLoaded signal)
	self.playersReady[userId] = false
	-- Record join time for timeout check
	self.playerJoinTimes[userId] = tick()

	-- Show loading screen (client handles progress bar)
	-- Server just tells the client to show the loading screen initially
	self.remotes.ui.updateLoading:FireClient(player, 0) -- Sending 0 might not be necessary if client handles progress

	-- Update player counts immediately for everyone
	local playerCount = self.playerManager:GetPlayerCount()
	local readyCount = self:CountReadyPlayers()
	self.remotes.ui.updatePlayersReady:FireAllClients(readyCount, playerCount)

	-- Restart player check if it wasn't running (e.g., server just started, or after game end)
	if not self.timers.playerCheck or not self.timers.playerCheck.Connected then
		print("[GameManager] Restarting player check timer on player join.")
		self:StartPlayerCheck()
	end
end

-- Called when a client fires the AssetsLoaded remote event
function GameManager:OnPlayerReady(player)
	if not player or not player:IsA("Player") then return end -- Basic validation
	local userId = player.UserId

	-- Only proceed if the player wasn't already marked as ready
	if self.playersReady and not self.playersReady[userId] then -- Check if table exists
		print("[GameManager] Player reported ready (AssetsLoaded):", player.Name)
		-- Mark player as ready on the server
		self.playersReady[userId] = true
		-- Optional: Stop tracking join time for timeout once ready
		-- if self.playerJoinTimes then self.playerJoinTimes[userId] = nil end

		-- Update player counts for UI
		local readyCount = self:CountReadyPlayers()
		local playerCount = self.playerManager:GetPlayerCount()
		self.remotes.ui.updatePlayersReady:FireAllClients(readyCount, playerCount)

		-- Check if conditions are met to finish loading
		-- This check is now primarily handled within the StartPlayerCheck loop
		-- but we can do an immediate check here too for responsiveness
		if self.gameState.isLoading and playerCount >= MIN_PLAYERS and self:AreAllPlayersReady() then
			print("[GameManager] Last player became ready. Attempting to FinishLoading (from OnPlayerReady).")
			self:FinishLoading() -- Attempt to finish loading
		end
	elseif self.playersReady and self.playersReady[userId] then
		-- print("[GameManager] Player", player.Name, "reported ready again, ignored.") -- Reduce log spam
	else
		warn("[GameManager] OnPlayerReady called but self.playersReady is nil or player not found?")
	end
end

function GameManager:FinishLoading()
	-- *** ADDED REINFORCED CHECK ***
	local playerCount = self.playerManager:GetPlayerCount()
	if playerCount < MIN_PLAYERS then
		warn("[GameManager] FinishLoading called with insufficient players (" .. playerCount .. "/" .. MIN_PLAYERS .. "). Aborting transition.")
		-- Ensure we stay in loading state
		self.gameState.isLoading = true
		self.gameState.isClassSelection = false
		-- Do NOT fire ShowClassSelection or stop the player check timer
		return -- Stop execution of this function
	end
	-- *** END ADDED CHECK ***

	-- Prevent running multiple times if already not loading
	if not self.gameState.isLoading then
		-- print("[GameManager] FinishLoading called but game is not in loading state. Skipping.") -- Reduce log spam
		return
	end

	print("[GameManager] Finishing loading phase, transitioning to Class Selection.")
	-- Change game state *AFTER* checks pass
	self.gameState.isLoading = false
	self.gameState.isClassSelection = true

	-- Stop the player check timer now that loading is officially finished
	if self.timers.playerCheck then
		if self.timers.playerCheck.Connected then self.timers.playerCheck:Disconnect() end
		self.timers.playerCheck = nil
		print("[GameManager] Player check timer stopped (loading finished successfully).")
	end

	-- Signal clients to show class selection UI
	-- Clients (LoadingScreenHandler) should listen for this and handle the transition
	self.remotes.ui.showClassSelection:FireAllClients()
	print("[GameManager] Fired ShowClassSelection to all clients.")

	-- Start class selection timeout timer
	self:StartClassSelectionTimeout()
end


function GameManager:StartClassSelectionTimeout()
	-- Reset timer value
	self.gameState.selectionTimeLeft = CLASS_SELECTION_TIME

	-- Clear existing timer if any
	if self.timers.classSelection then
		if self.timers.classSelection.Connected then self.timers.classSelection:Disconnect() end
		self.timers.classSelection = nil
	end

	-- Start timestamp tracking for the timer loop
	self.timers.classSelectionTimestamp = tick()
	print("[GameManager] Class selection timer starting (".. CLASS_SELECTION_TIME .." seconds)...")

	-- Send initial timer value to clients
	self.remotes.ui.updateClassSelectionTimer:FireAllClients(self.gameState.selectionTimeLeft)

	-- Start timer loop
	self.timers.classSelection = RunService.Heartbeat:Connect(function()
		-- Calculate elapsed time for loop frequency control
		local currentTime = tick()
		local elapsedTime = currentTime - self.timers.classSelectionTimestamp
		if elapsedTime < 1 then return end -- Run check approx every 1 second

		-- Update timestamp
		self.timers.classSelectionTimestamp = currentTime

		-- Skip if not in class selection phase or game ended
		if not self.gameState.isClassSelection or self.gameState.isGameEnded then
			if self.timers.classSelection then
				if self.timers.classSelection.Connected then self.timers.classSelection:Disconnect() end
				self.timers.classSelection = nil
				print("[GameManager] Class selection timer stopped (state changed or game ended).")
			end
			return
		end

		-- Decrease timer
		self.gameState.selectionTimeLeft = self.gameState.selectionTimeLeft - 1
		local timeLeft = math.max(0, self.gameState.selectionTimeLeft) -- Ensure timer doesn't go below 0

		-- Update timer UI for all clients
		self.remotes.ui.updateClassSelectionTimer:FireAllClients(timeLeft)

		-- *** IMPROVED CHECK FOR ALL SELECTED ***
		local allSelected = true
		local currentPlayers = Players:GetPlayers() -- Get current list of players
		local currentPlayersCount = #currentPlayers

		if currentPlayersCount < MIN_PLAYERS then -- Add check for minimum players here too
			allSelected = false -- Cannot start if players dropped below minimum during selection
			-- print("[GameManager] Class selection check: Player count dropped below minimum.")
		elseif not self.playersSelectedClass then
			allSelected = false -- Selection table doesn't exist
			warn("[GameManager] Class selection check: playersSelectedClass table is nil.")
		else
			for _, p in ipairs(currentPlayers) do
				-- Check if the player exists in the selection table AND has a non-nil value
				if not self.playersSelectedClass[p.UserId] then
					allSelected = false
					-- print("[GameManager] Waiting for player", p.Name, "to select.") -- Reduce spam
					break -- Optimization: No need to check further
				end
			end
		end
		-- *** END IMPROVED CHECK ***

		-- If all players selected OR time runs out, proceed to start game
		if allSelected or timeLeft <= 0 then
			-- Stop this timer FIRST to prevent race conditions
			if self.timers.classSelection then
				if self.timers.classSelection.Connected then self.timers.classSelection:Disconnect() end
				self.timers.classSelection = nil
				print("[GameManager] Class selection timer stopped (condition met: allSelected="..tostring(allSelected)..", timeLeft="..timeLeft..").")
			end

			-- Ensure we are still in the class selection phase before proceeding
			if not self.gameState.isClassSelection then
				warn("[GameManager] Condition met to end class selection, but game state is no longer isClassSelection. Aborting StartGame sequence.")
				return
			end

			-- *** CHANGE STATE IMMEDIATELY ***
			print("[GameManager] Setting gameState.isClassSelection = false")
			self.gameState.isClassSelection = false -- Change state *before* random assignment/wait

			-- If time ran out, assign random classes to those who didn't choose
			if timeLeft <= 0 and not allSelected then
				print("[GameManager] Class selection time up. Assigning random classes.")
				for _, p in ipairs(currentPlayers) do
					if not self.playersSelectedClass or not self.playersSelectedClass[p.UserId] then
						if self.classSystem then
							local randomClass = self.classSystem:GetRandomClass()
							if randomClass then
								self:OnPlayerSelectedClass(p, randomClass) -- Call this to handle assignment and UI update
								self.remotes.ui.notifyRandomClass:FireClient(p, randomClass)
								print("[GameManager] Assigned random class", randomClass, "to", p.Name)
							else
								warn("[GameManager] Failed to get random class for", p.Name)
							end
						else
							warn("[GameManager] Cannot assign random class to", p.Name, "- ClassSystem not found.")
						end
					end
				end
				-- Wait a bit for players to see the random assignment notification
				task.wait(3)
			else
				-- All players selected before time ran out, or time ran out after random assignment
				print("[GameManager] All players selected class or time ran out after random assignment.")
				task.wait(1.5) -- Short delay before starting
			end

			-- Start the game if it hasn't started yet
			-- Use task.spawn for safety, but the state check inside is less critical now
			task.spawn(function()
				-- Check if game hasn't started and we are NOT in class selection anymore
				if not self.gameState.isClassSelection and not self.gameState.isGameStarted then
					print("[GameManager] Proceeding to StartGame (from Class Selection end).")
					self:StartGame() -- StartGame also checks player count again
				else
					warn("[GameManager] Aborted StartGame call from Class Selection end: State changed (isClassSelection="..tostring(self.gameState.isClassSelection)..", isGameStarted="..tostring(self.gameState.isGameStarted)..")")
				end
			end)

			return -- Exit the timer loop since condition was met
		end
	end)
end

function GameManager:OnPlayerSelectedClass(player, selectedClass)
	if not player or not selectedClass then return end
	local userId = player.UserId

	-- Ensure the table exists
	if not self.playersSelectedClass then self.playersSelectedClass = {} end

	-- Only record if in the correct phase and not already selected
	-- Allow re-selection logic if needed, but for now, prevent it if already selected.
	if self.gameState.isClassSelection and not self.playersSelectedClass[userId] then
		print("[GameManager] Player", player.Name, "selected class:", selectedClass)
		-- Store class selection
		self.playersSelectedClass[userId] = selectedClass

		-- Assign class using ClassSystem (check if it exists)
		if self.classSystem then
			self.classSystem:AssignClassToPlayer(player, selectedClass)
		else
			warn("[GameManager] Cannot assign class to", player.Name, "- ClassSystem not found.")
		end

		-- Update UI for all clients to show who selected what
		self.remotes.ui.updateClassSelection:FireAllClients(userId, selectedClass)

		-- Note: The check to start the game early if all players select
		-- is now handled inside the StartClassSelectionTimeout loop.
	elseif not self.gameState.isClassSelection then
		warn("[GameManager] Player", player.Name, "tried to select class ("..tostring(selectedClass)..") but state is not ClassSelection.")
	elseif self.playersSelectedClass[userId] then
		warn("[GameManager] Player", player.Name, "tried to select class ("..tostring(selectedClass)..") but already selected:", self.playersSelectedClass[userId])
	end
end

function GameManager:StartGame()
	-- Prevent duplicate game start
	if self.gameState.isGameStarted then
		-- print("[GameManager] Game already started, skipping StartGame call.") -- Reduce spam
		return
	end
	-- *** REMOVED REDUNDANT CHECK: The state should be correct now ***
	-- Ensure class selection is finished before starting
	-- if self.gameState.isClassSelection then
	--     warn("[GameManager] StartGame called while still in class selection. Aborting.")
	--     return
	-- end

	local currentPlayers = Players:GetPlayers()
	local playerCount = #currentPlayers -- Use live player count

	-- *** CRITICAL CHECK: Ensure enough players right before starting ***
	if playerCount < MIN_PLAYERS then
		warn("[GameManager] Cannot start game, not enough players:", playerCount, "Minimum:", MIN_PLAYERS)
		-- Don't just warn, prevent the game from starting incorrectly.
		-- Reset back to loading state? Or just end? Let's try resetting.
		print("[GameManager] Not enough players to start. Resetting game.")
		self:ResetGame() -- Go back to loading phase
		return
	end

	-- Ensure all players actually have a class assigned
	local allAssigned = true
	if not self.classSystem then
		warn("[GameManager] CRITICAL: ClassSystem not found! Cannot verify or assign classes.")
		allAssigned = false
	else
		for _, p in ipairs(currentPlayers) do
			if not self.classSystem:GetPlayerClass(p) then
				warn("[GameManager] Player", p.Name, "does not have a class assigned before StartGame! Assigning random fallback.")
				local randomClass = self.classSystem:GetRandomClass()
				if randomClass then
					-- Use OnPlayerSelectedClass to ensure data consistency and UI updates
					-- Need to temporarily allow selection even if isClassSelection is false for this fallback
					local originalState = self.gameState.isClassSelection
					self.gameState.isClassSelection = true -- Temporarily allow
					self:OnPlayerSelectedClass(p, randomClass)
					self.gameState.isClassSelection = originalState -- Restore state

					-- Verify again after assignment attempt
					if not self.classSystem:GetPlayerClass(p) then
						allAssigned = false
						warn("[GameManager] CRITICAL: Failed to assign fallback class to", p.Name)
						break
					end
				else
					allAssigned = false
					warn("[GameManager] CRITICAL: Failed to get random class for fallback assignment to", p.Name)
					break
				end
			end
		end
	end

	if not allAssigned then
		warn("[GameManager] Cannot start game, failed to ensure all players have classes.")
		self:ResetGame() -- Reset if class assignment failed
		return
	end


	print("[GameManager] Starting game...")
	-- Update game state
	self.gameState.isClassSelection = false -- Ensure this is false
	self.gameState.isGameStarted = true
	self.gameState.isLoading = false -- Ensure loading is false

	-- Signal clients to show main game UI and hide others
	self.remotes.ui.showMainGameUI:FireAllClients()
	self.remotes.game.startGame:FireAllClients() -- General game start signal
	print("[GameManager] Fired ShowMainGameUI and StartGame events.")

	-- Initialize player positions and visuals on the board
	local success = self:InitializePlayerPositions()
	if not success then
		warn("[GameManager] Failed to initialize player positions! Game might not function correctly.")
		-- Consider ending the game if positions fail critically
		print("[GameManager] Critical error initializing positions. Ending game.")
		self:EndGame("Failed to initialize board.")
		return
	end

	-- Start turn system
	if self.turnSystem then
		print("[GameManager] Initializing Turn System...")
		self.turnSystem:CreateTurnOrderFromActivePlayers(self.playerManager)
		self.turnSystem:StartTurnSystem()
		self.gameState.currentTurn = 1 -- Initialize turn counter
		print("[GameManager] Turn system started. Current turn:", self.gameState.currentTurn)
	else
		warn("[GameManager] TurnSystem not available! Game logic will be incomplete.")
	end

	-- Start game timer
	self:StartGameTimer()
	print("[GameManager] Game started successfully.")
end

--[[ ... ส่วนที่เหลือของ GameManager.lua (InitializePlayerPositions, StartGameTimer, CheckWinCondition, OnPlayerRemoving, EndGame, ShowGameStats, ResetGame) เหมือนเดิม ... ]]
function GameManager:InitializePlayerPositions()
	if not self.boardSystem then
		warn("[GameManager] BoardSystem not found in InitializePlayerPositions")
		return false
	end

	print("[GameManager] Initializing player positions...")
	local startTileId = 1 -- Assuming start tile ID is 1

	-- Get the physical position of the start tile
	local tilePosition = self.boardSystem:GetTilePosition(startTileId) -- Use BoardSystem method if available

	if not tilePosition then
		warn("[GameManager] Could not get start tile position from BoardSystem. Trying fallback methods...")
		-- Fallback 1: Look in Workspace
		local tilesFolder = Workspace:FindFirstChild("BoardTiles")
		if tilesFolder then
			local tilePart = tilesFolder:FindFirstChild("Tile" .. startTileId) or tilesFolder:FindFirstChild(tostring(startTileId))
			if tilePart and tilePart:IsA("BasePart") then
				tilePosition = tilePart.Position
				print("[GameManager] Found start tile position via Workspace:", tilePosition)
			end
		end

		-- Fallback 2: Look in MapData module
		if not tilePosition then
			local MapData = ServerStorage:FindFirstChild("GameData") and ServerStorage.GameData:FindFirstChild("MapData")
			if MapData then
				local success, mapDataModule = pcall(require, MapData)
				if success and mapDataModule and mapDataModule.tiles and mapDataModule.tiles[startTileId] and mapDataModule.tiles[startTileId].position then
					tilePosition = mapDataModule.tiles[startTileId].position
					print("[GameManager] Using MapData position for tile ID:", startTileId, tilePosition)
				end
			end
		end

		-- Fallback 3: Hardcoded position (last resort)
		if not tilePosition then
			tilePosition = Vector3.new(35.778, 0.6, -15.24) -- Default position from original code
			warn("[GameManager] Using hardcoded position for start tile:", startTileId, tilePosition)
		end
	end

	if not tilePosition then
		warn("[GameManager] CRITICAL: Failed to determine start tile position. Cannot initialize player positions.")
		return false -- Cannot proceed without a start position
	end

	-- Position each player
	for _, player in pairs(Players:GetPlayers()) do
		local playerId = player.UserId

		-- 1. Set logical position in BoardSystem
		self.boardSystem:SetPlayerPosition(playerId, startTileId, nil) -- Set logical position first
		print("[GameManager] Set logical position for player", playerId, "to tile", startTileId)

		-- 2. Teleport character model to the physical start position
		local character = player.Character or player.CharacterAdded:Wait() -- Get character, wait if needed
		if character then
			local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
			-- Wait for root part briefly if not immediately available
			if not humanoidRootPart then humanoidRootPart = character:WaitForChild("HumanoidRootPart", 2) end

			if humanoidRootPart then
				-- Teleport slightly above the tile position
				humanoidRootPart.CFrame = CFrame.new(tilePosition + Vector3.new(0, 3, 0))
				print("[GameManager] Teleported player", playerId, "to start position:", tilePosition)
			else
				warn("[GameManager] Could not teleport player", playerId, "- HumanoidRootPart not found after wait.")
			end
		else
			warn("[GameManager] Player character not found for player:", playerId, "even after waiting.")
		end

		-- 3. Notify clients about the initial position for UI updates
		-- Send to everyone to update leaderboards, etc.
		self.remotes.board.updatePlayerPosition:FireAllClients(playerId, startTileId)
		-- Send specifically to the player for their own UI/camera focus if needed
		-- This initial path might not be necessary if UpdatePlayerPosition handles the UI
		-- local initialMovementData = { path = {startTileId}, directions = nil, requiresConfirmation = false }
		-- self.remotes.board.startPlayerMovementPath:FireClient(player, playerId, initialMovementData)
		print("[GameManager] Fired UpdatePlayerPosition for player", playerId, "at tile", startTileId)
	end

	print("[GameManager] Player positions initialized.")
	return true
end

function GameManager:StartGameTimer()
	if not self.gameState.isGameStarted then return end -- Only run if game is started

	local lastUpdateTime = tick()
	print("[GameManager] Starting game timer.")

	-- Use task.spawn for non-blocking timer loop
	task.spawn(function()
		while self.gameState.isGameStarted and not self.gameState.isGameEnded do
			local currentTime = tick()
			local elapsed = currentTime - lastUpdateTime

			-- Update game time every second
			if elapsed >= 1 then
				lastUpdateTime = currentTime
				self.gameState.gameTime = self.gameState.gameTime + 1
				-- print("Game Time:", self.gameState.gameTime) -- Optional: Log game time
			end

			task.wait(0.1) -- Check frequently but not excessively
		end
		print("[GameManager] Game timer stopped. Final game time:", self.gameState.gameTime)
	end)
end

function GameManager:CheckWinCondition()
	-- Only check if the game is actually running
	if not self.gameState.isGameStarted or self.gameState.isGameEnded then
		return false
	end

	-- Check 1: Last player standing
	local activePlayers = self.playerManager and self.playerManager:GetActivePlayers() -- Use PlayerManager method if available
	if not activePlayers then -- Fallback if method doesn't exist
		activePlayers = Players:GetPlayers()
	end
	local activePlayerCount = #activePlayers

	if activePlayerCount < MIN_PLAYERS then -- Check if count is less than minimum needed to play
		local winner = nil
		if activePlayerCount == 1 then
			winner = activePlayers[1]
			print("[GameManager] Win Condition: Last player standing -", winner.Name)
			self:EndGame(winner.Name .. " wins! (Last player remaining)")
			return true
		elseif activePlayerCount == 0 then
			print("[GameManager] Win Condition: No players remaining.")
			self:EndGame("Game ended. No players remaining.")
			return true
		else
			-- This case should ideally not be reached if MIN_PLAYERS is 2,
			-- but included for robustness if MIN_PLAYERS could be > 2
			print("[GameManager] Player count ("..activePlayerCount..") dropped below minimum ("..MIN_PLAYERS.."). Ending game.")
			self:EndGame("Game ended. Not enough players.")
			return true
		end
	end

	-- Check 2: Turn limit reached
	local MAX_TURNS = 30 -- Define max turns
	if self.gameState.currentTurn >= MAX_TURNS then
		print("[GameManager] Win Condition: Turn limit reached (Turn", self.gameState.currentTurn, ")")
		local richestPlayer = nil
		local highestMoney = -math.huge -- Start with negative infinity to correctly compare

		for _, player in ipairs(activePlayers) do
			-- Get money safely from PlayerManager
			local playerData = self.playerManager and self.playerManager:GetPlayerData(player)
			local playerMoney = playerData and playerData.stats and playerData.stats.money or 0

			if playerMoney > highestMoney then
				richestPlayer = player
				highestMoney = playerMoney
			end
		end

		if richestPlayer then
			print("[GameManager] Richest player:", richestPlayer.Name, "with", highestMoney)
			self:EndGame(richestPlayer.Name .. " wins with " .. highestMoney .. " coins! (Turn limit reached)")
			return true
		else -- Case when no one has positive money or all tied at 0
			print("[GameManager] Turn limit reached, but no clear winner based on money.")
			self:EndGame("Game ended. Turn limit reached, draw or no winner.")
			return true
		end
	end

	-- Add other win conditions here (e.g., reaching a specific goal)

	return false -- No win condition met yet
end

function GameManager:OnPlayerRemoving(player)
	local userId = player.UserId
	print("[GameManager] Player removing:", player.Name, "(ID:", userId, ")")

	-- Clean up player data
	if self.playerManager then self.playerManager:UnregisterPlayer(player) end
	if self.playersReady then self.playersReady[userId] = nil end
	if self.playersSelectedClass then self.playersSelectedClass[userId] = nil end
	if self.playerJoinTimes then self.playerJoinTimes[userId] = nil end -- Remove join time tracking

	-- If game started, notify TurnSystem and check win conditions
	if self.gameState.isGameStarted and not self.gameState.isGameEnded then
		print("[GameManager] Handling player leave during active game.")
		if self.turnSystem then
			self.turnSystem:HandlePlayerLeave(playerId)
		end
		-- Check win condition immediately after handling leave
		-- Use task.wait to allow PlayerRemoving events to fully process before checking
		task.wait()
		self:CheckWinCondition() -- This now handles the "less than MIN_PLAYERS" case too
	end

	-- Update player count UI for remaining players
	local playerCount = self.playerManager and self.playerManager:GetPlayerCount() or #Players:GetPlayers()
	local readyCount = self:CountReadyPlayers()
	self.remotes.ui.updatePlayersReady:FireAllClients(readyCount, playerCount)

	-- If player leaves during loading or class selection, re-evaluate conditions
	if self.gameState.isLoading then
		task.wait() -- Allow player list to update
		local currentCount = self.playerManager and self.playerManager:GetPlayerCount() or #Players:GetPlayers()
		-- Check if conditions are NOW met after player left
		if currentCount >= MIN_PLAYERS and self:AreAllPlayersReady() then
			print("[GameManager] Conditions met to finish loading after player left.")
			self:FinishLoading()
		end
	elseif self.gameState.isClassSelection then
		task.wait() -- Allow player list to update
		local currentPlayers = Players:GetPlayers()
		local currentCount = #currentPlayers
		local allSelected = true
		if currentCount == 0 then allSelected = false end
		if self.playersSelectedClass then
			for _, p in ipairs(currentPlayers) do
				if not self.playersSelectedClass[p.UserId] then
					allSelected = false
					break
				end
			end
		else
			allSelected = false -- Table doesn't exist
		end


		if allSelected and currentCount > 0 then -- Make sure someone is left
			print("[GameManager] All remaining players have selected class after player left. Proceeding to start.")
			if self.timers.classSelection then if self.timers.classSelection.Connected then self.timers.classSelection:Disconnect() end; self.timers.classSelection = nil end
			task.delay(1.5, function() -- Use task.delay for safety
				-- *** FIX: Check if state is STILL isClassSelection before starting ***
				if self.gameState.isClassSelection and not self.gameState.isGameStarted then
					-- Need to set isClassSelection to false *before* starting
					print("[GameManager] Setting isClassSelection=false before starting game (player left case)")
					self.gameState.isClassSelection = false
					self:StartGame()
				end
			end)
		end
	end
end


function GameManager:EndGame(reason)
	-- Prevent duplicate game end calls
	if self.gameState.isGameEnded then
		-- print("[GameManager] Game already ended, skipping EndGame call. Reason:", reason) -- Reduce spam
		return
	end

	print("[GameManager] Ending game. Reason:", reason)
	-- Update game state FIRST
	self.gameState.isGameEnded = true
	self.gameState.isGameStarted = false
	self.gameState.isClassSelection = false
	self.gameState.isLoading = false

	-- Cancel all active timers cleanly
	if self.timers.playerCheck then
		if self.timers.playerCheck.Connected then self.timers.playerCheck:Disconnect() end
		self.timers.playerCheck = nil
		print("[GameManager] Player check timer stopped.")
	end
	if self.timers.classSelection then
		if self.timers.classSelection.Connected then self.timers.classSelection:Disconnect() end
		self.timers.classSelection = nil
		print("[GameManager] Class selection timer stopped.")
	end
	-- Stop game timer loop (it checks isGameStarted/isGameEnded itself)

	-- Reset turn system if it exists
	if self.turnSystem then
		self.turnSystem:Reset()
		print("[GameManager] Turn system reset.")
	end

	-- Notify all clients that the game has ended
	self.remotes.game.endGame:FireAllClients(reason)
	print("[GameManager] EndGame event fired to clients.")

	-- Show game stats after a short delay to allow UI transitions
	task.delay(3, function()
		-- Ensure game hasn't been reset in the meantime
		if self.gameState.isGameEnded then
			self:ShowGameStats(reason)
		end
	end)

	-- Consider initiating a game reset after stats are shown
	task.delay(15, function() -- Wait 15 seconds after ending
		if self.gameState.isGameEnded then -- Check if still in ended state
			print("[GameManager] Initiating automatic game reset.")
			self:ResetGame()
		end
	end)
end

function GameManager:ShowGameStats(reason)
	-- Check if game ended state is still true before showing stats
	if not self.gameState.isGameEnded then
		print("[GameManager] ShowGameStats called but game is not ended. Skipping.")
		return
	end
	print("[GameManager] Preparing and showing game stats...")

	-- Create stats data structure
	local gameStats = {
		reason = reason or "Game Over",
		totalTurns = self.gameState.currentTurn,
		gameDuration = self.gameState.gameTime,
		playerStats = {}
	}

	-- Collect stats for players who were present at the end
	-- Use PlayerManager data as the source of truth
	local finalPlayerData = self.playerManager and self.playerManager:GetAllPlayerData() -- Get data for all registered players
	if not finalPlayerData then
		warn("[GameManager] PlayerManager or GetAllPlayerData not available for stats.")
		finalPlayerData = {} -- Use empty table as fallback
	end

	for playerId, playerData in pairs(finalPlayerData) do
		local player = Players:GetPlayerByUserId(playerId)
		-- Include stats even if player left just before EndGame was called? Or only current players?
		-- Let's include all players managed by PlayerManager at the point EndGame was called.
		if player or playerData then -- Include if player exists or data exists
			local playerName = player and player.Name or (playerData and playerData.Name) or ("Player " .. playerId) -- Handle players who left
			table.insert(gameStats.playerStats, {
				playerName = playerName,
				playerId = playerId,
				level = playerData and playerData.stats and playerData.stats.level or 1,
				money = playerData and playerData.stats and playerData.stats.money or 0,
				class = playerData and playerData.class or "N/A" -- Use N/A if class wasn't assigned
			})
		end
	end

	-- Sort players by final money (descending)
	table.sort(gameStats.playerStats, function(a, b)
		return (a.money or 0) > (b.money or 0)
	end)

	-- Send stats to all clients
	self.remotes.game.gameStats:FireAllClients(gameStats)
	print("[GameManager] GameStats event fired to clients.")
end


function GameManager:ResetGame()
	print("[GameManager] Resetting game state for a new round...")

	-- Disconnect player signals to avoid interference during reset
	-- (Consider wrapping Add/Removing connections in functions to easily disconnect/reconnect)

	-- Reset game state flags
	self.gameState = {
		isLoading = true, -- Start in loading state
		isClassSelection = false,
		isGameStarted = false,
		isGameEnded = false, -- Crucial to reset this
		currentTurn = 0,
		gameTime = 0,
		selectionTimeLeft = CLASS_SELECTION_TIME
	}

	-- Clear player tracking data
	self.playersReady = {}
	self.playersSelectedClass = {}
	self.playerJoinTimes = {} -- Clear join times

	-- Cancel any lingering timers
	if self.timers.playerCheck then if self.timers.playerCheck.Connected then self.timers.playerCheck:Disconnect() end; self.timers.playerCheck = nil end
	if self.timers.classSelection then if self.timers.classSelection.Connected then self.timers.classSelection:Disconnect() end; self.timers.classSelection = nil end
	print("[GameManager] Timers cancelled.")

	-- Reset game systems
	if self.turnSystem then self.turnSystem:Reset(); print("[GameManager] TurnSystem reset.") end
	if self.boardSystem and self.boardSystem.ClearAllPlayerPositions then -- Check if function exists
		pcall(function() self.boardSystem:ClearAllPlayerPositions() end) -- Safely call
		print("[GameManager] BoardSystem player positions cleared.")
	end
	if self.checkpointSystem and self.checkpointSystem.ResetAllCheckpoints then
		pcall(function() self.checkpointSystem:ResetAllCheckpoints() end)
		print("[GameManager] Checkpoint system reset.")
	end
	if self.playerManager and self.playerManager.ResetAllPlayerData then
		-- Decide whether to clear all player data in PlayerManager or just reset states
		pcall(function() self.playerManager:ResetAllPlayerData() end) -- If function exists
		print("[GameManager] PlayerManager state reset.")
	end

	-- Handle players currently in the server
	for _, player in pairs(Players:GetPlayers()) do
		print("[GameManager] Resetting state for player:", player.Name)
		-- Mark as not ready for the new round
		if self.playersReady then self.playersReady[player.UserId] = false end
		-- Record a new join time for the reset phase
		if self.playerJoinTimes then self.playerJoinTimes[player.UserId] = tick() end
		-- Send loading screen signal again to reset client UI
		self.remotes.ui.updateLoading:FireClient(player, 0) -- Tell client to show loading
		-- Ensure other UIs are hidden (client should handle this on receiving updateLoading/showClassSelection etc.)
	end

	-- Update UI immediately after reset
	local playerCount = self.playerManager and self.playerManager:GetPlayerCount() or #Players:GetPlayers()
	local readyCount = self:CountReadyPlayers()
	self.remotes.ui.updatePlayersReady:FireAllClients(readyCount, playerCount)

	-- Restart the initial player check loop for the new round
	print("[GameManager] Restarting player check loop for new game.")
	self:StartPlayerCheck() -- This should now handle the waiting logic correctly
	print("[GameManager] Game reset complete. Waiting for players...")
end


return GameManager
