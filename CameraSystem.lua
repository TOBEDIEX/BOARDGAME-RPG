-- CameraSystem.lua
-- Camera system: LockPlayer (Uses Roblox Default Controls focused on turn player),
-- FreeCam (Roblox Studio Style), V Toggle.
-- Version: 1.7.0 (Implemented Studio-like FreeCam)

local CameraSystem = {}

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService") -- Kept for potential future use
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Local variables
local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local currentMode = "LockPlayer" -- "LockPlayer" or "FreeCam"
local connections = {}
local currentTurnPlayerId = nil
local isSystemActive = true -- Flag to track if the camera system is active
local isResetting = false -- Flag to prevent race conditions during reset
local renderSteppedConnection = nil -- Explicitly store RenderStepped connection

-- Camera Control Variables (FreeCam Only)
local freeCamMoveSpeed = 50 -- Base speed, adjustable with mouse wheel
local shiftMultiplier = 3 -- Speed multiplier when holding Shift
local rotationSpeed = 0.003 -- Sensitivity for mouse rotation
local minMoveSpeed = 5
local maxMoveSpeed = 500

-- Debug function
local function debug(message, ...)
	print(string.format("[CameraSystem] " .. message, ...))
end

-- Forward declare initCameraSystem and cleanup
local initCameraSystem
local cleanup
local startRenderStepped -- Declare startRenderStepped

-- Function to set the camera focus (Used ONLY for LockPlayer mode)
local function setLockPlayerFocus(playerId)
	if currentMode ~= "LockPlayer" or not isSystemActive then return end

	local targetPlayer = playerId and Players:GetPlayerByUserId(playerId)
	local targetCharacter = targetPlayer and targetPlayer.Character
	local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")

	-- Ensure CameraType is Custom for LockPlayer mode
	if camera.CameraType ~= Enum.CameraType.Custom then
		camera.CameraType = Enum.CameraType.Custom
		debug("Set CameraType to Custom for LockPlayer mode.")
	end

	if targetHumanoid and targetHumanoid.Health > 0 then
		if camera.CameraSubject ~= targetHumanoid then
			camera.CameraSubject = targetHumanoid
			debug("LockPlayer: Camera subject set to Humanoid of player ID: %s", tostring(playerId))
		end
	else
		if camera.CameraSubject ~= nil then
			camera.CameraSubject = nil
			debug("LockPlayer: Target player/humanoid not valid for ID: %s. Camera subject cleared.", tostring(playerId))
		end
	end
end

-- Handle Mouse Input for Rotation (FreeCam Only)
local function handleMouseRotationInput(deltaTime)
	if currentMode ~= "FreeCam" then return end

	if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
		local mouseDelta = UserInputService:GetMouseDelta()
		-- Apply rotation directly to the camera's CFrame
		local currentCFrame = camera.CFrame
		local rotationX = CFrame.Angles(0, -mouseDelta.X * rotationSpeed, 0)
		local rotationY = CFrame.Angles(-mouseDelta.Y * rotationSpeed, 0, 0)
		-- Apply Y rotation first (around world up), then X rotation (relative to new camera orientation)
		camera.CFrame = currentCFrame * rotationX * rotationY
	end
end

-- Update free cam (Studio Style)
local function updateFreeCam(deltaTime)
	if currentMode ~= "FreeCam" then return end

	-- Calculate current speed based on Shift key
	local currentSpeed = freeCamMoveSpeed
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
		currentSpeed = currentSpeed * shiftMultiplier
	end
	local moveAmount = currentSpeed * deltaTime

	-- Handle WASDQE Movement Input relative to camera CFrame
	local moveVector = Vector3.new(0,0,0)
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVector = moveVector + Vector3.new(0, 0, -moveAmount) end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVector = moveVector + Vector3.new(0, 0, moveAmount) end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVector = moveVector + Vector3.new(-moveAmount, 0, 0) end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVector = moveVector + Vector3.new(moveAmount, 0, 0) end
	if UserInputService:IsKeyDown(Enum.KeyCode.E) then moveVector = moveVector + Vector3.new(0, moveAmount, 0) end -- World Up
	if UserInputService:IsKeyDown(Enum.KeyCode.Q) then moveVector = moveVector + Vector3.new(0, -moveAmount, 0) end -- World Down

	-- Apply movement relative to camera orientation for WASD, world for QE
	local currentCFrame = camera.CFrame
	local horizontalMove = Vector3.new(moveVector.X, 0, moveVector.Z)
	local verticalMove = Vector3.new(0, moveVector.Y, 0)

	local newPosition = currentCFrame.Position + currentCFrame:VectorToWorldSpace(horizontalMove) + verticalMove

	-- Update camera CFrame directly
	camera.CFrame = CFrame.new(newPosition) * (currentCFrame - currentCFrame.Position)

end

-- Toggle camera mode
local function toggleCameraMode()
	if not isSystemActive then return end

	if currentMode == "LockPlayer" then
		-- Switching TO FreeCam
		currentMode = "FreeCam"
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CameraSubject = nil
		debug("Switched to FreeCam mode (Studio Style).")
		-- No specific initialization needed, RenderStepped will handle movement/rotation from current pos

	else -- Switching TO LockPlayer
		currentMode = "LockPlayer"
		debug("Switched to LockPlayer mode.")
		setLockPlayerFocus(currentTurnPlayerId) -- Sets Type to Custom and sets Subject
	end
end

-- Function to completely reset and reinitialize the camera system
local function resetCameraSystem()
	if isResetting then return end
	isResetting = true
	debug("Resetting camera system...")
	cleanup()

	-- Reset variables
	currentMode = "LockPlayer" -- Default to LockPlayer
	freeCamMoveSpeed = 50 -- Reset speed
	currentTurnPlayerId = nil
	isSystemActive = true

	if initCameraSystem then
		task.defer(initCameraSystem)
	else
		warn("[CameraSystem] initCameraSystem not yet defined during reset!")
	end

	debug("Camera system reset complete")
	task.wait(0.1)
	isResetting = false
end

-- Connect to turn system (Only sets Subject in LockPlayer mode)
local function connectToTurnSystem()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	if not remotes then return end
	local gameRemotes = remotes:FindFirstChild("GameRemotes")
	if not gameRemotes then return end
	local updateTurnEvent = gameRemotes:FindFirstChild("UpdateTurn")
	if not updateTurnEvent then return end

	if connections.turnUpdate then connections.turnUpdate:Disconnect(); connections.turnUpdate = nil end

	connections.turnUpdate = updateTurnEvent.OnClientEvent:Connect(function(playerId)
		debug("UpdateTurn event received for player ID: %s", tostring(playerId))
		currentTurnPlayerId = playerId
		if currentMode == "LockPlayer" and isSystemActive then
			setLockPlayerFocus(currentTurnPlayerId)
		end
	end)
	debug("Connected to UpdateTurn event.")
end

-- Connect to player respawn system
local function connectToRespawnSystem()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	if not remotes then return end
	local uiRemotes = remotes:FindFirstChild("UIRemotes")
	if not uiRemotes then return end

	local playerRespawnedEvent = uiRemotes:FindFirstChild("PlayerRespawned")
	if not playerRespawnedEvent then
		warn("[CameraSystem] PlayerRespawned event not found under UIRemotes!")
		return
	end

	if connections.playerRespawn then connections.playerRespawn:Disconnect(); connections.playerRespawn = nil end

	connections.playerRespawn = playerRespawnedEvent.OnClientEvent:Connect(function(respawnData)
		debug("Received player respawn notification for UserID: %s", tostring(respawnData and respawnData.playerUserId))
		if respawnData and respawnData.playerUserId == player.UserId then
			task.defer(function()
				debug("Local player respawned. Resetting camera system.")
				resetCameraSystem() -- Full reset to ensure correct state and focus
			end)
		end
	end)
	debug("Connected to player respawn system")
end

-- Connect to system enable/disable event
local function connectToSystemEnableEvent()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local combatRemotes = remotes:FindFirstChild("CombatRemotes")
	if not combatRemotes then warn("[CameraSystem] CombatRemotes folder not found!"); return end

	local setSystemEnabledEvent = combatRemotes:FindFirstChild("SetSystemEnabled")
	if not setSystemEnabledEvent then warn("[CameraSystem] SetSystemEnabled event not found!"); return end

	if connections.systemEnable then connections.systemEnable:Disconnect(); connections.systemEnable = nil end

	connections.systemEnable = setSystemEnabledEvent.OnClientEvent:Connect(function(systemName, enabled)
		if systemName == "CameraSystem" then
			debug("Received SetSystemEnabled for CameraSystem: %s", tostring(enabled))
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
cleanup = function()
	debug("Cleaning up camera connections...")
	for name, connection in pairs(connections) do
		if connection then
			debug("  Disconnecting: %s", name)
			connection:Disconnect()
			connections[name] = nil
		end
	end
	if renderSteppedConnection then
		debug("  Disconnecting: renderStepped")
		renderSteppedConnection:Disconnect()
		renderSteppedConnection = nil
	end
	debug("All camera connections cleaned up")
end

-- Start the RenderStepped loop (Only needed for FreeCam updates)
startRenderStepped = function()
	if renderSteppedConnection then return end

	debug("Starting RenderStepped loop (for FreeCam).")
	renderSteppedConnection = RunService.RenderStepped:Connect(function(deltaTime)
		if not camera or not camera.Parent then debug("Camera not found, stopping."); cleanup(); return end
		if not isSystemActive then return end

		-- Only run updates if in FreeCam mode
		if currentMode == "FreeCam" then
			-- Handle Mouse Rotation Input
			handleMouseRotationInput(deltaTime)
			-- Update FreeCam position/CFrame
			updateFreeCam(deltaTime)
		end
	end)
end

-- Initialize camera system
initCameraSystem = function()
	debug("Initializing camera system...")
	cleanup()

	local char = player.Character or player.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if not hrp then warn("[CameraSystem] HRP not found."); return end
	debug("Character and HRP ready.")

	isSystemActive = true
	-- Initial setup depends on the Enable function

	connectToTurnSystem()
	connectToRespawnSystem()
	connectToSystemEnableEvent()

	-- Connect input for camera toggle (V key)
	connections.inputBegan = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not isSystemActive or gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.V then toggleCameraMode() end
	end)
	debug("Connected InputBegan for V toggle.")

	-- Connect InputChanged for Mouse Wheel Zoom (Adjusts FreeCam Speed)
	connections.inputChanged = UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if not isSystemActive or gameProcessed or currentMode ~= "FreeCam" then return end -- Check mode

		if input.UserInputType == Enum.UserInputType.MouseWheel then
			local scrollDelta = input.Position.Z -- Z component contains the scroll delta
			if scrollDelta ~= 0 then
				-- Adjust move speed, make it exponential for better feel
				local changeFactor = 1.2
				if scrollDelta > 0 then
					freeCamMoveSpeed = math.min(freeCamMoveSpeed * changeFactor, maxMoveSpeed)
				else
					freeCamMoveSpeed = math.max(freeCamMoveSpeed / changeFactor, minMoveSpeed)
				end
				debug("FreeCam Speed set to: %.2f", freeCamMoveSpeed)
			end
		end
	end)
	debug("Connected InputChanged for Mouse Wheel (FreeCam speed).")

	startRenderStepped() -- Start the loop (it will only do work in FreeCam)

	connections.characterRemoving = player.CharacterRemoving:Connect(cleanup)
	debug("Connected CharacterRemoving.")
	if script then connections.scriptDestroying = script.Destroying:Connect(cleanup); debug("Connected Script Destroying.") end

	-- Explicitly enable the system to set initial state
	CameraSystem.Enable()

	debug("Camera system initialization complete.")
end

-- Function to disable camera system
function CameraSystem.Disable()
	if not isSystemActive then return end
	debug("Disabling custom camera system (Reverting to Default)")
	isSystemActive = false

	-- Revert to default camera controls
	camera.CameraType = Enum.CameraType.Custom
	local localHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	camera.CameraSubject = localHumanoid
	debug("Camera reverted to Custom type, subject set to local Humanoid (or nil).")
end

-- Function to enable camera system
function CameraSystem.Enable()
	-- Allow re-enabling to reset state if needed
	debug("Enabling custom camera system")
	isSystemActive = true

	-- Set initial state based on the current mode
	if currentMode == "LockPlayer" then
		debug("Setting initial mode to LockPlayer.")
		setLockPlayerFocus(currentTurnPlayerId) -- Sets Type to Custom and sets Subject
	elseif currentMode == "FreeCam" then
		debug("Setting initial mode to FreeCam.")
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CameraSubject = nil
		-- No need to force update, RenderStepped will handle it
	end

	-- Ensure RenderStepped is running
	if not renderSteppedConnection or not renderSteppedConnection.Connected then
		startRenderStepped()
	end

	debug("Custom camera system re-enabled.")
end

-- Start initialization safely
task.spawn(initCameraSystem)

return CameraSystem
