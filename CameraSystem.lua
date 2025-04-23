-- CameraSystem.lua
-- Simple camera system: locks on player and can switch to FreeCam
-- Version: 1.2.2 (Revert to Default Roblox Camera during Combat)

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
local isResetting = false -- Flag to prevent race conditions during reset
local renderSteppedConnection = nil -- Explicitly store RenderStepped connection

-- Define Combat Area Position (Same as CombatService) - Still useful for potential future logic
local COMBAT_AREA_POSITION = Vector3.new(0, 100, 0)

-- Debug function
local function debug(message)
	print("[CameraSystem] " .. message)
end

-- Forward declare initCameraSystem and cleanup
local initCameraSystem
local cleanup
local startRenderStepped -- Declare startRenderStepped

-- Function to completely reset and reinitialize the camera system
local function resetCameraSystem()
	if isResetting then return end -- Prevent recursive resets
	isResetting = true
	debug("Resetting camera system...")

	-- Clean up existing connections
	cleanup()

	-- Reset variables
	currentMode = "LockPlayer"
	freeCamPosition = Vector3.new(0, 0, 0)
	freeCamHeight = 40
	cameraDistance = 30
	isSystemActive = true -- Ensure it's active after reset

	-- Reactivate the system (make sure initCameraSystem is defined before calling)
	if initCameraSystem then
		-- Use task.defer to avoid potential issues with immediate re-initialization
		task.defer(initCameraSystem)
	else
		warn("[CameraSystem] initCameraSystem not yet defined during reset!")
	end

	debug("Camera system reset complete")
	-- Reset the flag after a short delay to allow init to start
	task.wait(0.1)
	isResetting = false
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
	if count > 0 then
		return totalPos / count
	else
		return Vector3.new(0, 0, 0)
	end
end

-- Update in lock player mode
local function updateLockPlayerCamera()
	-- Removed the isSystemActive check here, RenderStepped handles it
	if currentMode ~= "LockPlayer" then return end

	local playerInfo = findCurrentTurnPlayer()
	local targetCFrame
	if playerInfo then
		local targetPos = playerInfo.position
		local lookVector = playerInfo.lookVector
		-- Ensure lookVector is not zero
		if lookVector.Magnitude < 0.1 then lookVector = Vector3.new(0, 0, -1) end

		local cameraPos = targetPos - (lookVector.Unit * cameraOffset.Z) + Vector3.new(0, cameraOffset.Y, 0)
		local lookAtPos = targetPos + Vector3.new(0, 2, 0)
		targetCFrame = CFrame.lookAt(cameraPos, lookAtPos)
	else
		-- Fallback if player not found (e.g., between turns)
		local boardCenter = findBoardCenter()
		local cameraPos = boardCenter + Vector3.new(0, freeCamHeight, 20)
		targetCFrame = CFrame.lookAt(cameraPos, boardCenter)
	end

	-- Only tween if the target CFrame is significantly different
	if targetCFrame and (camera.CFrame.Position - targetCFrame.Position).Magnitude > 0.1 then
		local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		-- Check if camera is still valid before tweening
		if camera and camera.Parent then
			local tween = TweenService:Create(camera, tweenInfo, {CFrame = targetCFrame})
			tween:Play()
		end
	elseif targetCFrame and camera and camera.Parent then
		-- If very close, just set it directly to avoid jitter
		camera.CFrame = targetCFrame
	end
end


-- Update free cam
local function updateFreeCam(deltaTime)
	-- Removed the isSystemActive check here, RenderStepped handles it
	if currentMode ~= "FreeCam" then return end

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

			-- Update camera position based on freeCamPosition (which is the center point)
			freeCamPosition = freeCamPosition + moveDirection * currentMoveSpeed
		end
	end

	-- Calculate target position (where the camera is looking at - the center point)
	local targetPosition = Vector3.new(freeCamPosition.X, 0, freeCamPosition.Z)

	-- Calculate horizontal direction vector (XZ plane)
	local horizontalDirection = Vector3.new(freeCamDirection.X, 0, freeCamDirection.Z).Unit

	-- Calculate camera position using distance and tilt angle relative to targetPosition
	local offsetX = -horizontalDirection.X * cameraDistance * math.cos(cameraAngle)
	local offsetY = cameraDistance * math.sin(cameraAngle) -- Height based on distance and angle
	local offsetZ = -horizontalDirection.Z * cameraDistance * math.cos(cameraAngle)

	local finalCameraOffset = Vector3.new(offsetX, offsetY, offsetZ)
	-- Use freeCamHeight for the Y component of the camera's position directly
	local cameraPosition = targetPosition + Vector3.new(finalCameraOffset.X, freeCamHeight, finalCameraOffset.Z)

	-- Update camera lookAt
	local lookAtTarget = targetPosition -- Look at the ground position (center point)

	-- Check if camera is valid before setting CFrame
	if camera and camera.Parent then
		camera.CFrame = CFrame.lookAt(cameraPosition, lookAtTarget)
	end
end


-- Toggle camera mode
local function toggleCameraMode()
	if not isSystemActive then return end -- Check if system is active

	if currentMode == "LockPlayer" then
		currentMode = "FreeCam"
		local playerInfo = findCurrentTurnPlayer()
		if playerInfo then
			freeCamPosition = Vector3.new(playerInfo.position.X, 0, playerInfo.position.Z)
			freeCamHeight = 30 -- Good starting height for MOBA view

			-- Get initial camera direction from player's look direction
			local horizontalDir = Vector3.new(playerInfo.lookVector.X, 0, playerInfo.lookVector.Z).Unit
			if horizontalDir.Magnitude < 0.1 then horizontalDir = Vector3.new(0,0,-1) end -- Default if zero
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
		debug("Switched to FreeCam mode.")
	else
		currentMode = "LockPlayer"
		camera.CameraType = Enum.CameraType.Scriptable
		updateLockPlayerCamera() -- Update immediately to lock onto player
		debug("Switched to LockPlayer mode.")
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

	-- Disconnect previous connection if exists
	if connections.turnUpdate then connections.turnUpdate:Disconnect(); connections.turnUpdate = nil end

	connections.turnUpdate = updateTurnEvent.OnClientEvent:Connect(function(playerId)
		currentTurnPlayerId = playerId
		-- RenderStepped will handle the update if active and in LockPlayer mode
	end)
	debug("Connected to UpdateTurn event.")
end

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
	end

	-- Disconnect previous connection if exists
	if connections.playerRespawn then connections.playerRespawn:Disconnect(); connections.playerRespawn = nil end

	-- Connect to the respawn event
	connections.playerRespawn = playerRespawnedEvent.OnClientEvent:Connect(function(respawnData)
		debug("Received player respawn notification")

		-- Reset camera system on respawn
		task.defer(function()
			resetCameraSystem() -- This now includes setting isSystemActive = true

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
					end
				end
			end
		end) -- Close task.defer function
	end) -- Close OnClientEvent connection

	debug("Connected to player respawn system")
end

-- NEW: Connect to system enable/disable event
local function connectToSystemEnableEvent()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local combatRemotes = remotes:FindFirstChild("CombatRemotes")
	if not combatRemotes then warn("[CameraSystem] CombatRemotes folder not found!"); return end

	local setSystemEnabledEvent = combatRemotes:FindFirstChild("SetSystemEnabled")
	if not setSystemEnabledEvent then warn("[CameraSystem] SetSystemEnabled event not found!"); return end

	-- Disconnect previous connection if exists
	if connections.systemEnable then connections.systemEnable:Disconnect(); connections.systemEnable = nil end

	connections.systemEnable = setSystemEnabledEvent.OnClientEvent:Connect(function(systemName, enabled)
		if systemName == "CameraSystem" then
			debug("Received SetSystemEnabled for CameraSystem:", enabled)
			if enabled then
				CameraSystem.Enable()
			else
				CameraSystem.Disable()
			end
		end
	end)
	debug("Connected to SetSystemEnabled event for CameraSystem")
end


-- Clean up connections
cleanup = function() -- Assign to the forward-declared variable
	debug("Cleaning up camera connections...")
	for name, connection in pairs(connections) do
		if connection then
			debug("  Disconnecting:", name)
			connection:Disconnect()
			connections[name] = nil
		end
	end
	-- Also stop the render stepped loop if it's running
	if renderSteppedConnection then
		debug("  Disconnecting: renderStepped")
		renderSteppedConnection:Disconnect()
		renderSteppedConnection = nil
	end
	debug("All camera connections cleaned up")
end

-- Start the RenderStepped loop
startRenderStepped = function()
	if renderSteppedConnection then return end -- Don't start if already running

	debug("Starting RenderStepped loop.")
	renderSteppedConnection = RunService.RenderStepped:Connect(function(deltaTime)
		-- Basic safety check
		if not camera or not camera.Parent then
			debug("Camera not found or destroyed, stopping RenderStepped.")
			cleanup() -- Clean up all connections if camera is gone
			return
		end

		-- Skip updates if disabled
		if not isSystemActive then return end

		-- Update based on mode
		if currentMode == "LockPlayer" then
			updateLockPlayerCamera()
		elseif currentMode == "FreeCam" then
			updateFreeCam(deltaTime)
		end
	end)
end

-- Initialize camera system
initCameraSystem = function() -- Assign to the forward-declared variable
	debug("Initializing camera system...")

	-- Ensure cleanup runs first if re-initializing
	cleanup()

	-- Wait for character and essential parts
	local char = player.Character or player.CharacterAdded:Wait()
	char:WaitForChild("HumanoidRootPart", 10)
	debug("Character and HumanoidRootPart ready.")

	isSystemActive = true -- Ensure active on init

	-- Connect events
	connectToTurnSystem()
	connectToRespawnSystem()
	connectToSystemEnableEvent()

	-- Set camera to scriptable mode
	camera.CameraType = Enum.CameraType.Scriptable

	-- Connect input for camera toggle
	connections.inputBegan = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not isSystemActive then return end -- Ignore input if disabled
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.V then toggleCameraMode() end
	end)
	debug("Connected InputBegan.")

	-- Start the RenderStepped loop
	startRenderStepped()

	-- Safety cleanup on character removal or script destruction
	connections.characterRemoving = player.CharacterRemoving:Connect(function(character)
		debug("Character removing - cleaning up connections.")
		cleanup() -- Clean up when character is removed
	end)
	debug("Connected CharacterRemoving.")

	-- This connection might be redundant if cleanup handles script destruction, but keep for safety
	if script then
		connections.scriptDestroying = script.Destroying:Connect(cleanup)
		debug("Connected Script Destroying.")
	end

	debug("Camera system initialization complete.")
end

-- Function to pause/disable camera system (used when player dies or combat starts)
function CameraSystem.Disable()
	if not isSystemActive then return end -- Prevent multiple calls
	debug("Disabling camera system (Reverting to Default Roblox Camera)")
	isSystemActive = false

	-- Stop the RenderStepped loop explicitly
	if renderSteppedConnection then
		renderSteppedConnection:Disconnect()
		renderSteppedConnection = nil
		debug("RenderStepped loop stopped.")
	end

	-- Revert to default camera controls
	camera.CameraType = Enum.CameraType.Custom -- Let Roblox default scripts take over
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid -- Set subject for default scripts
		debug("Camera reverted to Custom type, subject set to Humanoid.")
	else
		camera.CameraSubject = nil -- Clear subject if humanoid not found
		debug("Camera reverted to Custom type, Humanoid not found, subject cleared.")
	end
end

-- Function to resume/enable camera system (used when player respawns or combat ends)
function CameraSystem.Enable()
	if isSystemActive then return end -- Prevent multiple calls
	debug("Enabling custom camera system")
	isSystemActive = true

	-- Take back control from default scripts
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil -- Clear subject from default camera
	debug("Camera set to Scriptable type, subject cleared.")

	-- Restart the RenderStepped loop
	startRenderStepped()

	-- Force an update based on the current mode immediately
	if currentMode == "LockPlayer" then
		debug("Forcing immediate update for LockPlayer mode.")
		updateLockPlayerCamera()
	elseif currentMode == "FreeCam" then
		debug("FreeCam mode active, RenderStepped will handle update.")
		-- Optional: Immediately update FreeCam position if needed, though RenderStepped should handle it
		-- updateFreeCam(0) -- Pass 0 delta time for an immediate position update
	end
	debug("Custom camera system re-enabled.")
end

-- Start initialization safely
task.spawn(initCameraSystem)

return CameraSystem
