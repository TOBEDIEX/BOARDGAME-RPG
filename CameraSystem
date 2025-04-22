-- CameraSystem.lua
-- Simple camera system: locks on player and can switch to FreeCam
-- Modified to handle respawning gracefully

local CameraSystem = {}

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Local variables
local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local currentMode = "LockPlayer" -- LockPlayer or FreeCam
local connections = {}
local currentTurnPlayerId = nil
local freeCamPosition = Vector3.new(0, 0, 0)
local freeCamHeight = 40
local moveSpeed = 1 -- Adjust this to change base speed
local freeCamMoveSpeedMultiplier = 2.5 -- Slightly increased speed multiplier
local cameraOffset = Vector3.new(0, 8, 16)
local freeCamDirection = Vector3.new(0, -0.8, -1).Unit -- MOBA-style angled view from above
local cameraAngle = math.rad(45) -- 45 degree camera angle (MOBA-style)
local cameraDistance = 30 -- Distance of camera from target position
local isSystemActive = true -- Flag to track if the camera system is active

-- Debug function
local function debug(message)
	print("[CameraSystem] " .. message)
end

-- Forward declare initCameraSystem and cleanup
local initCameraSystem
local cleanup

-- Function to completely reset and reinitialize the camera system
local function resetCameraSystem()
	debug("Resetting camera system...")

	-- Clean up existing connections
	cleanup()

	-- Reset variables
	currentMode = "LockPlayer"
	freeCamPosition = Vector3.new(0, 0, 0)
	freeCamHeight = 40
	cameraDistance = 30
	isSystemActive = true

	-- Reactivate the system (make sure initCameraSystem is defined before calling)
	if initCameraSystem then
		initCameraSystem()
	else
		warn("[CameraSystem] initCameraSystem not yet defined during reset!")
	end


	debug("Camera system reset complete")
end

-- Find current turn player
local function findCurrentTurnPlayer()
	if not currentTurnPlayerId then return nil end
	local targetPlayer = Players:GetPlayerByUserId(currentTurnPlayerId)
	if not targetPlayer then return nil end
	local character = targetPlayer.Character
	if not character then return nil end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return nil end
	return {player = targetPlayer, character = character, rootPart = humanoidRootPart, position = humanoidRootPart.Position, lookVector = humanoidRootPart.CFrame.LookVector}
end

-- Find center of board
local function findBoardCenter()
	local tilesFolder = Workspace:FindFirstChild("BoardTiles")
	if not tilesFolder then return Vector3.new(0, 0, 0) end
	local totalPos = Vector3.new(0, 0, 0)
	local count = 0
	for _, tile in ipairs(tilesFolder:GetChildren()) do
		if tile:IsA("BasePart") then totalPos = totalPos + tile.Position; count = count + 1 end
	end
	-- *** FIXED: Changed return syntax ***
	if count > 0 then
		return totalPos / count
	else
		return Vector3.new(0, 0, 0)
	end
end

-- Update in lock player mode
local function updateLockPlayerCamera()
	if not isSystemActive then return end

	local playerInfo = findCurrentTurnPlayer()
	local targetCFrame
	if playerInfo then
		local targetPos = playerInfo.position
		local lookVector = playerInfo.lookVector
		local cameraPos = targetPos - (lookVector * cameraOffset.Z) + Vector3.new(0, cameraOffset.Y, 0)
		local lookAtPos = targetPos + Vector3.new(0, 2, 0)
		targetCFrame = CFrame.lookAt(cameraPos, lookAtPos)
	else
		local boardCenter = findBoardCenter()
		local cameraPos = boardCenter + Vector3.new(0, freeCamHeight, 20)
		targetCFrame = CFrame.lookAt(cameraPos, boardCenter)
	end
	local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(camera, tweenInfo, {CFrame = targetCFrame})
	tween:Play()
end

-- Update free cam
local function updateFreeCam(deltaTime)
	if not isSystemActive then return end

	-- Get mouse input for camera rotation
	local mouseMovement = UserInputService:GetMouseDelta()

	-- Set rotation speed
	local rotationSpeed = 0.005

	-- Rotate camera based on mouse movement (if right mouse button is pressed)
	if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
		-- Only rotate around Y axis (left-right) to maintain MOBA-style tilted view
		local rotationY = -mouseMovement.X * rotationSpeed

		-- Create rotation CFrame
		local rotationCF = CFrame.Angles(0, rotationY, 0)

		-- Main direction vector in XZ plane
		local horizontalDir = Vector3.new(freeCamDirection.X, 0, freeCamDirection.Z).Unit

		-- Rotate only the horizontal component
		local newHorizontalDir = (rotationCF * horizontalDir)

		-- Reconstruct the direction maintaining the tilt angle
		freeCamDirection = Vector3.new(newHorizontalDir.X, -math.sin(cameraAngle), newHorizontalDir.Z).Unit
	end

	-- Initialize movement input vector
	local moveInput = Vector3.new(0, 0, 0)

	-- Get WASD input
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		moveInput = moveInput + Vector3.new(0, 0, -1) -- Forward
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		moveInput = moveInput + Vector3.new(0, 0, 1) -- Backward
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		moveInput = moveInput + Vector3.new(-1, 0, 0) -- Left
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		moveInput = moveInput + Vector3.new(1, 0, 0) -- Right
	end

	-- Adjust height with Q/E (to change viewing area)
	local heightChange = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.Q) then
		heightChange = -1 -- Down
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.E) then
		heightChange = 1 -- Up
	end

	-- Adjust zoom with Z/X (to change camera distance)
	local zoomChange = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.Z) then
		zoomChange = -1 -- Zoom in
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.X) then
		zoomChange = 1 -- Zoom out
	end

	-- Calculate movement, height and zoom speeds
	local currentMoveSpeed = moveSpeed * freeCamMoveSpeedMultiplier * deltaTime * 60
	local currentHeightSpeed = moveSpeed * freeCamMoveSpeedMultiplier * deltaTime * 60
	local currentZoomSpeed = moveSpeed * freeCamMoveSpeedMultiplier * deltaTime * 60 * 2

	-- Update height and zoom
	freeCamHeight = math.clamp(freeCamHeight + heightChange * currentHeightSpeed, 10, 150)
	cameraDistance = math.clamp(cameraDistance + zoomChange * currentZoomSpeed, 10, 100)

	-- Calculate movement direction
	if moveInput.Magnitude > 0.01 then
		-- Create CFrame from current camera direction (XZ plane only)
		local horizontalDir = Vector3.new(freeCamDirection.X, 0, freeCamDirection.Z).Unit
		local cameraCFrame = CFrame.lookAt(Vector3.new(0, 0, 0), horizontalDir)

		-- Transform input vector to world space
		local moveDirection = cameraCFrame:VectorToWorldSpace(moveInput)

		-- Restrict movement to XZ plane
		moveDirection = Vector3.new(moveDirection.X, 0, moveDirection.Z)

		-- Normalize direction for consistent speed
		if moveDirection.Magnitude > 0.01 then
			moveDirection = moveDirection.Unit

			-- Update camera position
			freeCamPosition = freeCamPosition + moveDirection * currentMoveSpeed
		end
	end

	-- Calculate target position (where the camera is looking at)
	local targetPosition = Vector3.new(freeCamPosition.X, 0, freeCamPosition.Z)

	-- Calculate horizontal direction vector (XZ plane)
	local horizontalDirection = Vector3.new(freeCamDirection.X, 0, freeCamDirection.Z).Unit

	-- Calculate camera position using distance and tilt angle
	local offsetX = -horizontalDirection.X * cameraDistance * math.cos(cameraAngle)
	local offsetY = cameraDistance * math.sin(cameraAngle)
	local offsetZ = -horizontalDirection.Z * cameraDistance * math.cos(cameraAngle)

	local finalCameraOffset = Vector3.new(offsetX, offsetY, offsetZ) -- Renamed variable to avoid conflict
	local cameraPosition = targetPosition + finalCameraOffset

	-- Update camera
	camera.CFrame = CFrame.lookAt(cameraPosition, targetPosition)
end

-- Toggle camera mode
local function toggleCameraMode()
	if not isSystemActive then return end

	if currentMode == "LockPlayer" then
		currentMode = "FreeCam"
		local playerInfo = findCurrentTurnPlayer()
		if playerInfo then
			freeCamPosition = Vector3.new(playerInfo.position.X, 0, playerInfo.position.Z)
			freeCamHeight = 30 -- Good starting height for MOBA view

			-- Get initial camera direction from player's look direction
			local horizontalDir = Vector3.new(playerInfo.lookVector.X, 0, playerInfo.lookVector.Z).Unit
			freeCamDirection = Vector3.new(horizontalDir.X, -math.sin(cameraAngle), horizontalDir.Z).Unit
		else
			freeCamPosition = findBoardCenter()
			freeCamHeight = 40
			-- Initial MOBA-style direction, angled from above
			freeCamDirection = Vector3.new(0, -math.sin(cameraAngle), -math.cos(cameraAngle)).Unit
		end

		-- Set camera distance and height to reasonable values
		cameraDistance = 30 -- Starting distance
		freeCamHeight = math.clamp(freeCamHeight, 10, 150)

		camera.CameraType = Enum.CameraType.Scriptable
		camera.CameraSubject = nil
	else
		currentMode = "LockPlayer"
		camera.CameraType = Enum.CameraType.Scriptable
		updateLockPlayerCamera()
	end
end

-- Connect to turn system
local function connectToTurnSystem()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	if not remotes then return end
	local gameRemotes = remotes:FindFirstChild("GameRemotes")
	if not gameRemotes then return end
	local updateTurnEvent = gameRemotes:FindFirstChild("UpdateTurn")
	if not updateTurnEvent then return end
	connections.turnUpdate = updateTurnEvent.OnClientEvent:Connect(function(playerId)
		currentTurnPlayerId = playerId
		if currentMode == "LockPlayer" then
			updateLockPlayerCamera()
		end
	end)
end -- *** FIXED: Changed } to end ***

-- Connect to player respawn system
local function connectToRespawnSystem()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	if not remotes then return end
	local uiRemotes = remotes:FindFirstChild("UIRemotes")
	if not uiRemotes then return end

	-- Wait for the PlayerRespawned remote event
	local playerRespawnedEvent = uiRemotes:FindFirstChild("PlayerRespawned")
	if not playerRespawnedEvent then
		playerRespawnedEvent = Instance.new("RemoteEvent")
		playerRespawnedEvent.Name = "PlayerRespawned"
		playerRespawnedEvent.Parent = uiRemotes
		debug("Created PlayerRespawned remote event")
		-- *** FIXED: Removed stray } ***
	end

	-- Connect to the respawn event
	connections.playerRespawn = playerRespawnedEvent.OnClientEvent:Connect(function(respawnData)
		debug("Received player respawn notification")

		-- Reset camera system on respawn
		task.defer(function()
			resetCameraSystem()

			-- Focus camera on respawn position if available
			if respawnData and respawnData.respawnTileId then
				-- Find the tile in workspace
				local tilesFolder = Workspace:FindFirstChild("BoardTiles")
				if tilesFolder then
					local tile = tilesFolder:FindFirstChild("Tile" .. respawnData.respawnTileId) or
						tilesFolder:FindFirstChild(tostring(respawnData.respawnTileId))

					if tile then
						-- Switch to lock player mode and focus camera
						currentMode = "LockPlayer"
						updateLockPlayerCamera()
						debug("Camera focused on respawn tile: " .. respawnData.respawnTileId)
					end -- *** FIXED: Removed stray } ***
				end -- *** FIXED: Removed stray } ***
			end
		end) -- Close task.defer function
	end) -- Close OnClientEvent connection

	debug("Connected to player respawn system")
end -- *** FIXED: Changed } to end ***

-- Clean up connections
cleanup = function() -- Assign to the forward-declared variable
	for name, connection in pairs(connections) do
		if connection then connection:Disconnect(); connections[name] = nil end
	end
	debug("All camera connections cleaned up")
end -- *** FIXED: Changed } to end ***

-- Initialize camera system
initCameraSystem = function() -- Assign to the forward-declared variable
	debug("Checking for character...")
	if not player.Character then
		debug("Character not found, waiting...")
		player.CharacterAdded:Wait()
		debug("Character added.")
	end
	debug("Waiting for HumanoidRootPart...")
	player.Character:WaitForChild("HumanoidRootPart")
	debug("HumanoidRootPart found.")


	debug("Initializing camera system")
	isSystemActive = true

	-- Connect to the turn system
	connectToTurnSystem()

	-- Connect to the respawn system
	connectToRespawnSystem()

	-- Set camera to scriptable mode
	camera.CameraType = Enum.CameraType.Scriptable

	-- Connect input for camera toggle
	connections.inputBegan = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.V then toggleCameraMode() end
	end)

	-- Connect render stepped for camera updates
	connections.renderStepped = RunService.RenderStepped:Connect(function(deltaTime)
		if not camera or not camera.Parent then
			debug("Camera not found or destroyed, stopping RenderStepped.")
			if connections.renderStepped then connections.renderStepped:Disconnect(); connections.renderStepped = nil end
			return
		end

		if not isSystemActive then return end -- 

		if currentMode == "LockPlayer" then
			updateLockPlayerCamera()
		elseif currentMode == "FreeCam" then
			updateFreeCam(deltaTime)
		end
	end)

	-- Safety cleanup on character removal or script destruction
	connections.characterRemoving = player.CharacterRemoving:Connect(function() -- Store connection
		debug("Character removing - preparing for potential reset")
	end) -- *** FIXED: Removed stray } ***

	connections.scriptDestroying = script.Destroying:Connect(cleanup) -- Store connection

	debug("Camera system initialized")
end

-- Function to pause/disable camera system (used when player dies)
function CameraSystem.Disable()
	debug("Disabling camera system")
	isSystemActive = false
end 

-- Function to resume/enable camera system (used when player respawns)
function CameraSystem.Enable()
	debug("Enabling camera system")
	if not isSystemActive then
		isSystemActive = true
		-- Re-initialize or reset to ensure everything is set up correctly
		resetCameraSystem() -- Use reset to handle re-connections and state
	else
		debug("Camera system already enabled.")
	end
end -- *** FIXED: Changed } to end ***

-- Start
initCameraSystem()

return CameraSystem
