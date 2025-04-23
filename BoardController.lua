local BoardController = {}
BoardController.__index = BoardController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer

-- PlayerModule references for character control
local playerModule = nil
local playerControls = nil

local DIRECTIONS = { FRONT = "FRONT", LEFT = "LEFT", RIGHT = "RIGHT" }
local STEP_TIMEOUT = 5.0
local DELAY_BETWEEN_STEPS = 0.1
local MOVEMENT_COMPLETE_DELAY = 0.5

local DiceRollUI, PathSelectionContainer, RemainingStepsText
local ForwardButton, LeftButton, RightButton
local CurrentTileText
local isInCombatState = false

function BoardController.new()
	local self = setmetatable({}, BoardController)

	self.tilePositions = {}
	self.remotes = self:GetRemoteEvents()
	self.uiConnections = {}
	self.activeMovementCoroutines = {}
	self.pendingMovementConfirmations = {}

	-- Initialize PlayerModule reference
	self:InitializePlayerModule()

	self:InitializeUIReferences()
	self:ConnectEvents()
	self:UpdateCurrentTileUI(nil)

	-- Lock player controls by default when board game starts
	self:LockPlayerControls()

	return self
end

function BoardController:InitializePlayerModule()
	-- Get PlayerModule and Controls from player's PlayerScripts
	if player and player:FindFirstChild("PlayerScripts") then
		local playerScripts = player.PlayerScripts

		-- Try to get the PlayerModule
		local success, result = pcall(function()
			playerModule = require(playerScripts:WaitForChild("PlayerModule"))
			return playerModule:GetControls()
		end)

		if success and result then
			playerControls = result
			print("[BoardController] Successfully initialized PlayerModule controls")
		else
			warn("[BoardController] Failed to initialize PlayerModule controls: ", result)
		end
	else
		warn("[BoardController] PlayerScripts not found, cannot initialize PlayerModule")
	end
end

function BoardController:LockPlayerControls()
	if playerControls then
		print("[BoardController] Locking player controls for board game mode")
		playerControls:Disable()
		-- Additional specific locks if needed
		-- playerControls:SetMovementEnabled(false)
		-- playerControls:SetCameraEnabled(false)
	else
		warn("[BoardController] Cannot lock controls - PlayerControls not initialized")
	end
end

function BoardController:UnlockPlayerControls()
	if playerControls then
		print("[BoardController] Unlocking player controls")
		playerControls:Enable()
		-- Additional specific unlocks if needed
		-- playerControls:SetMovementEnabled(true)
		-- playerControls:SetCameraEnabled(true)
	else
		warn("[BoardController] Cannot unlock controls - PlayerControls not initialized")
	end
end

function BoardController:InitializeUIReferences()
	local PlayerGui = player:WaitForChild("PlayerGui")
	if not PlayerGui then return end

	local PopupUI = PlayerGui:WaitForChild("PopupUI")
	if not PopupUI then return end

	DiceRollUI = PopupUI:WaitForChild("DiceRollUI")

	if not DiceRollUI then
		warn("[BoardController] DiceRollUI not found!")
		return
	end

	PathSelectionContainer = DiceRollUI:FindFirstChild("PathSelectionContainer")
	if not PathSelectionContainer then
		warn("[BoardController] PathSelectionContainer not found!")
	else
		RemainingStepsText = PathSelectionContainer:FindFirstChild("RemainingStepsText")
		ForwardButton = PathSelectionContainer:FindFirstChild("ForwardButton")
		LeftButton = PathSelectionContainer:FindFirstChild("LeftButton")
		RightButton = PathSelectionContainer:FindFirstChild("RightButton")
	end

	local MainGameUI = PlayerGui:FindFirstChild("MainGameUI")
	if MainGameUI then
		CurrentTileText = MainGameUI:FindFirstChild("CurrentTileText")
	else
		warn("[BoardController] MainGameUI not found!")
	end
end

function BoardController:GetRemoteEvents()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local boardRemotes = remotes:WaitForChild("BoardRemotes")
	local combatRemotes = remotes:WaitForChild("CombatRemotes", 10) -- Wait for combat remotes with timeout

	local movementVisComplete = boardRemotes:FindFirstChild("MovementVisualizationComplete")
	if not movementVisComplete then
		movementVisComplete = Instance.new("RemoteEvent", boardRemotes)
		movementVisComplete.Name = "MovementVisualizationComplete"
		warn("[BoardController] Created missing RemoteEvent: MovementVisualizationComplete")
	end

	local eventTable = {
		playerArrivedAtTile = boardRemotes:WaitForChild("PlayerArrivedAtTile"),
		choosePath = boardRemotes:WaitForChild("ChoosePath"),
		startPlayerMovementPath = boardRemotes:WaitForChild("StartPlayerMovementPath"),
		tileTriggerEvent = boardRemotes:WaitForChild("TileTriggerEvent"),
		activityComplete = boardRemotes:WaitForChild("ActivityComplete"),
		movementVisualizationComplete = movementVisComplete
	}

	-- Add combat remotes if they exist
	if combatRemotes then
		eventTable.setCombatState = combatRemotes:FindFirstChild("SetCombatState")
		eventTable.setSystemEnabled = combatRemotes:FindFirstChild("SetSystemEnabled")
	end

	return eventTable
end

function BoardController:ConnectEvents()
	self.remotes.startPlayerMovementPath.OnClientEvent:Connect(function(playerId, movementData)
		if type(movementData) ~= "table" then
			warn("[BoardController] Received non-table movement data for playerId:", playerId)
			return
		end
		if type(movementData.path) ~= "table" or #movementData.path == 0 then
			warn("[BoardController] Received invalid or empty path data for playerId:", playerId)
			return
		end
		if movementData.directions and type(movementData.directions) ~= "table" then
			warn("[BoardController] Received non-table directions data for playerId:", playerId, ". Setting to nil.")
			movementData.directions = nil
		end
		if movementData.requiresConfirmation ~= nil and type(movementData.requiresConfirmation) ~= "boolean" then
			warn("[BoardController] Received non-boolean requiresConfirmation data for playerId:", playerId, ". Setting to false.")
			movementData.requiresConfirmation = false
		end

		self:StartMoveAlongPath(playerId, movementData.path, movementData.directions, movementData.requiresConfirmation)
	end)

	self.remotes.tileTriggerEvent.OnClientEvent:Connect(function(playerId, tileId, tileType)
		self:ShowTileEffect(playerId, tileId, tileType)
	end)

	-- Connect to combat state changes if the remote exists
	if self.remotes.setCombatState then
		self.remotes.setCombatState.OnClientEvent:Connect(function(isActive, duration)
			isInCombatState = isActive

			if isActive then
				print("[BoardController] Combat state activated - Unlocking player controls")
				self:UnlockPlayerControls()
			else
				print("[BoardController] Combat state deactivated - Locking player controls")
				self:LockPlayerControls()
			end
		end)
	end

	-- Connect to system enabled changes if the remote exists
	if self.remotes.setSystemEnabled then
		self.remotes.setSystemEnabled.OnClientEvent:Connect(function(systemName, isEnabled)
			-- If this is for another system, we'll just handle it here for simplicity
			if systemName == "PlayerControls" then
				if isEnabled then
					self:UnlockPlayerControls()
				else
					self:LockPlayerControls()
				end
			end
		end)
	end
end

function BoardController:StartMoveAlongPath(playerId, path, availableDirections, requiresConfirmation)
	if self.activeMovementCoroutines[playerId] then
		task.spawn(coroutine.close, self.activeMovementCoroutines[playerId])
		self.activeMovementCoroutines[playerId] = nil
		print("[BoardController] Closed existing movement coroutine for playerId:", playerId)
	end

	if requiresConfirmation then
		self.pendingMovementConfirmations[playerId] = { path = path, finalTileId = path[#path] }
	else
		self.pendingMovementConfirmations[playerId] = nil
	end

	local co = coroutine.create(function()
		self:MovePlayerAlongPath(playerId, path, availableDirections, requiresConfirmation)
	end)
	self.activeMovementCoroutines[playerId] = co
	local success, err = coroutine.resume(co)

	if not success then
		warn("[BoardController] Coroutine resume failed immediately for playerId:", playerId, "Error:", err)
		if self.activeMovementCoroutines[playerId] == co then
			self.activeMovementCoroutines[playerId] = nil
		end
		self:UpdateCurrentTileUI(path[#path])

		if requiresConfirmation and playerId == player.UserId then
			self:ConfirmMovementCompletion(playerId, path[#path])
		end
	end
end

function BoardController:MovePlayerAlongPath(playerId, path, availableDirections, requiresConfirmation)
	local currentCoroutine = coroutine.running()
	local movementSuccess = true
	local lastReachedTileIndex = 1

	local function cleanup(reason)
		warn("[BoardController] Cleaning up movement for playerId:", playerId, "Reason:", reason)
		if self.activeMovementCoroutines[playerId] == currentCoroutine then
			self.activeMovementCoroutines[playerId] = nil
		end
		local finalTileId = path[lastReachedTileIndex]
		if finalTileId then self:UpdateCurrentTileUI(finalTileId) end

		if requiresConfirmation and playerId == player.UserId then
			self:ConfirmMovementCompletion(playerId, finalTileId)
		end
	end

	local targetPlayer = Players:GetPlayerByUserId(playerId)
	if not targetPlayer then return cleanup("Player not found") end

	local character = targetPlayer.Character or targetPlayer.CharacterAdded:Wait(5)
	if not character then return cleanup("Character not found") end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then return cleanup("Humanoid or RootPart not found") end

	if self.activeMovementCoroutines[playerId] ~= currentCoroutine then return cleanup("Coroutine replaced before start") end

	if rootPart.Anchored then rootPart.Anchored = false end
	humanoid.WalkSpeed = 16

	for i = 2, #path do
		if self.activeMovementCoroutines[playerId] ~= currentCoroutine or coroutine.status(currentCoroutine) == "dead" then
			movementSuccess = false
			cleanup("Coroutine interrupted during path traversal")
			return
		end

		local nextTileId = path[i]
		local targetPosition = self:GetTilePosition(nextTileId)

		if targetPosition then
			humanoid:MoveTo(targetPosition)
			local success, result = pcall(function() return humanoid.MoveToFinished:Wait(STEP_TIMEOUT) end)

			if not success then
				warn("[BoardController] MoveToFinished Wait errored for playerId:", playerId, "Step:", i, "Tile:", nextTileId, "Error:", result)
				rootPart.CFrame = CFrame.new(targetPosition + Vector3.new(0, 3, 0))
				movementSuccess = false
				lastReachedTileIndex = i
				cleanup("MoveToFinished errored, teleported")
				return
			elseif not result then
				warn("[BoardController] MoveTo timed out for playerId:", playerId, "Step:", i, "Tile:", nextTileId, ". Teleporting.")
				rootPart.CFrame = CFrame.new(targetPosition + Vector3.new(0, 3, 0))
				lastReachedTileIndex = i
			else
				lastReachedTileIndex = i
			end

			task.wait(DELAY_BETWEEN_STEPS)
		else
			warn("[BoardController] Target position not found for Tile ID:", nextTileId, "at step:", i, "for playerId:", playerId)
			movementSuccess = false
			cleanup("Target tile position not found")
			return
		end
	end

	local finalTileId = path[lastReachedTileIndex]

	if self.activeMovementCoroutines[playerId] ~= currentCoroutine then
		return cleanup("Coroutine replaced after path traversal")
	end

	if movementSuccess then
		task.wait(MOVEMENT_COMPLETE_DELAY)

		if self.activeMovementCoroutines[playerId] ~= currentCoroutine then
			return cleanup("Coroutine replaced during final delay")
		end

		if playerId == player.UserId then
			if availableDirections and #availableDirections > 0 then
				self:UpdateCurrentTileUI(finalTileId)
				self:ShowPathSelectionUI(availableDirections)
			else
				self.activeMovementCoroutines[playerId] = nil
				self:UpdateCurrentTileUI(finalTileId)
				if requiresConfirmation then
					self:ConfirmMovementCompletion(playerId, finalTileId)
				end
			end
		else
			self.activeMovementCoroutines[playerId] = nil
		end
	else
		warn("[BoardController] Movement finished with failure status for playerId:", playerId, "Last reached Tile:", finalTileId)
	end

	if playerId == player.UserId and not self.activeMovementCoroutines[playerId] then
		if finalTileId then self:UpdateCurrentTileUI(finalTileId) end
	end
end


function BoardController:ConfirmMovementCompletion(playerId, finalTileId)
	if playerId ~= player.UserId then return end

	local pendingData = self.pendingMovementConfirmations[playerId]
	if not pendingData then
		print("[BoardController] No pending confirmation data found for playerId:", playerId)
		if finalTileId then self:UpdateCurrentTileUI(finalTileId) end
		return
	end

	if pendingData.finalTileId ~= finalTileId then
		warn("[BoardController] Mismatched finalTileId for confirmation. Expected:", pendingData.finalTileId, "Got:", finalTileId, ". Sending confirmation for the *received* tile ID.")
	end

	print("[BoardController] Sending MovementVisualizationComplete for playerId:", playerId, "Tile:", finalTileId)
	self.pendingMovementConfirmations[playerId] = nil
	self.remotes.movementVisualizationComplete:FireServer(finalTileId)
	self:UpdateCurrentTileUI(finalTileId)
end

function BoardController:UpdateCurrentTileUI(tileId)
	if not CurrentTileText then
		return
	end

	if tileId then
		CurrentTileText.Text = "Tile: " .. tostring(tileId)
		CurrentTileText.Visible = true
	else
		CurrentTileText.Text = "Tile: -"
		CurrentTileText.Visible = false
	end
end

function BoardController:ShowPathSelectionUI(availableDirections)
	if not PathSelectionContainer or not RemainingStepsText or not ForwardButton or not LeftButton or not RightButton then
		warn("[BoardController] Cannot show Path Selection UI - Critical elements missing.")
		if self.activeMovementCoroutines[player.UserId] then
			task.spawn(coroutine.close, self.activeMovementCoroutines[player.UserId])
			self.activeMovementCoroutines[player.UserId] = nil
		end
		return
	end

	for _, connection in pairs(self.uiConnections) do
		if connection.Connected then connection:Disconnect() end
	end
	self.uiConnections = {}

	PathSelectionContainer.Visible = true
	ForwardButton.Visible = false
	LeftButton.Visible = false
	RightButton.Visible = false

	local steps = "N/A"
	if availableDirections[1] and availableDirections[1].stepsRemaining then
		steps = tostring(availableDirections[1].stepsRemaining)
	end
	RemainingStepsText.Text = "Steps: " .. steps

	local buttonVisibleCount = 0
	for _, dirInfo in ipairs(availableDirections) do
		local button = nil
		local directionEnum = nil

		if dirInfo.direction == DIRECTIONS.FRONT then
			button, directionEnum = ForwardButton, DIRECTIONS.FRONT
		elseif dirInfo.direction == DIRECTIONS.LEFT then
			button, directionEnum = LeftButton, DIRECTIONS.LEFT
		elseif dirInfo.direction == DIRECTIONS.RIGHT then
			button, directionEnum = RightButton, DIRECTIONS.RIGHT
		else
			warn("[BoardController] Unknown direction received in availableDirections:", dirInfo.direction)
		end

		if button and directionEnum then
			button.Visible = true
			buttonVisibleCount = buttonVisibleCount + 1
			local connection = button.Activated:Connect(function()
				if PathSelectionContainer.Visible then
					self:ChooseDirection(directionEnum)
				else
					warn("[BoardController] PathSelectionContainer was hidden when button activated. Ignoring.")
				end
			end)
			table.insert(self.uiConnections, connection)
		end
	end

	if buttonVisibleCount == 0 then
		warn("[BoardController] No valid direction buttons to show in Path Selection UI. Hiding UI.")
		PathSelectionContainer.Visible = false
		if self.activeMovementCoroutines[player.UserId] then
			task.spawn(coroutine.close, self.activeMovementCoroutines[player.UserId])
			self.activeMovementCoroutines[player.UserId] = nil
		end
		local pendingConfirmation = self.pendingMovementConfirmations[player.UserId]
		if pendingConfirmation then
			self:ConfirmMovementCompletion(player.UserId, pendingConfirmation.finalTileId)
		end
	end
end

function BoardController:ChooseDirection(direction)
	if not PathSelectionContainer or not PathSelectionContainer.Visible then
		warn("[BoardController] ChooseDirection called while PathSelectionContainer is hidden or missing.")
		return
	end

	print("[BoardController] Player chose direction:", direction)
	PathSelectionContainer.Visible = false

	for _, connection in pairs(self.uiConnections) do
		if connection.Connected then connection:Disconnect() end
	end
	self.uiConnections = {}

	if self.activeMovementCoroutines[player.UserId] then
		self.activeMovementCoroutines[player.UserId] = nil
	end

	local pendingConfirmation = self.pendingMovementConfirmations[player.UserId]
	if pendingConfirmation then
		self:ConfirmMovementCompletion(player.UserId, pendingConfirmation.finalTileId)
	end

	self.remotes.choosePath:FireServer(direction)
end

function BoardController:GetTilePosition(tileId)
	if self.tilePositions[tileId] then
		return self.tilePositions[tileId]
	end

	local tilesFolder = Workspace:FindFirstChild("BoardTiles")
	if not tilesFolder then warn("[BoardController] BoardTiles folder not found!") return nil end

	local tileName1 = "Tile" .. tostring(tileId)
	local tileName2 = tostring(tileId)
	local tilePart = tilesFolder:FindFirstChild(tileName1) or tilesFolder:FindFirstChild(tileName2)

	if not tilePart or not tilePart:IsA("BasePart") then
		return nil
	end

	self.tilePositions[tileId] = tilePart.Position
	return tilePart.Position
end

function BoardController:ShowTileEffect(playerId, tileId, tileType)
	local tilePosition = self:GetTilePosition(tileId)
	if not tilePosition then return end

	local lowerTileType = string.lower(tostring(tileType or "unknown"))
	local color = Color3.fromRGB(200, 200, 200)

	if lowerTileType == "shop" then color = Color3.fromRGB(255, 215, 0)
	elseif lowerTileType == "battle" then color = Color3.fromRGB(255, 0, 0)
	elseif lowerTileType == "item" then color = Color3.fromRGB(0, 255, 0)
	elseif lowerTileType == "money" then color = Color3.fromRGB(255, 255, 0)
	elseif lowerTileType == "casino" then color = Color3.fromRGB(255, 0, 255)
	elseif lowerTileType == "bank" then color = Color3.fromRGB(0, 0, 255)
	elseif lowerTileType == "castle" then color = Color3.fromRGB(128, 0, 128)
	end

	self:CreateParticleEffect(tilePosition, color, tileType and string.upper(tostring(tileType)) or "UNKNOWN")
	self:PlayTileSound(lowerTileType, playerId, tileId)
end

function BoardController:CreateParticleEffect(position, color, effectType)
	local effectContainer = Instance.new("Model", Workspace.CurrentCamera)
	effectContainer.Name = "TileEffect_" .. effectType .. "_" .. math.random(1000)
	Debris:AddItem(effectContainer, 2.0)

	local effectPart = Instance.new("Part")
	effectPart.Anchored = true
	effectPart.CanCollide = false
	effectPart.Transparency = 1
	effectPart.Size = Vector3.new(5, 0.2, 5)
	effectPart.Position = position + Vector3.new(0, 0.1, 0)
	effectPart.Color = color
	effectPart.Material = Enum.Material.Neon
	effectPart.Shape = Enum.PartType.Cylinder
	effectPart.Orientation = Vector3.new(0, 0, 90)
	effectPart.Parent = effectContainer

	local emitter = Instance.new("ParticleEmitter", effectPart)
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 0.8),
		NumberSequenceKeypoint.new(1, 0.1)
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.7, 0.8),
		NumberSequenceKeypoint.new(1, 1)
	})
	emitter.Lifetime = NumberRange.new(0.8, 1.5)
	emitter.Rate = 40
	emitter.Speed = NumberRange.new(3, 6)
	emitter.SpreadAngle = Vector2.new(360, 360)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Enabled = true

	local tweenInfo = TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(effectPart, tweenInfo, {
		Orientation = effectPart.Orientation + Vector3.new(0, 180, 0),
		Transparency = 1,
		Size = effectPart.Size * 0.1
	})
	tween:Play()

	task.delay(1.3, function()
		if emitter and emitter.Parent then
			emitter.Enabled = false
		end
	end)
end

function BoardController:PlayTileSound(tileType, playerId, tileId)
	local soundId = "rbxassetid://4067980844"
	if tileType == "shop" then soundId = "rbxassetid://132089340"
	elseif tileType == "battle" then soundId = "rbxassetid://122224253"
	elseif tileType == "item" then soundId = "rbxassetid://184661655"
	end

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 0.6

	local soundParent = nil
	local targetPlayerInstance = Players:GetPlayerByUserId(playerId)
	if targetPlayerInstance then
		local character = targetPlayerInstance.Character
		soundParent = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	end

	if not soundParent then
		local tilePos = self:GetTilePosition(tileId)
		if tilePos then
			local soundPart = Instance.new("Part", Workspace.CurrentCamera)
			soundPart.Anchored = true
			soundPart.CanCollide = false
			soundPart.Transparency = 1
			soundPart.Position = tilePos
			soundPart.Size = Vector3.one
			soundPart.Name = "TempSoundPart_" .. tileId
			sound.Parent = soundPart
			local soundDuration = (sound.TimeLength > 0 and sound.TimeLength) or 2
			Debris:AddItem(soundPart, soundDuration + 0.5)
		else
			warn("[BoardController] Cannot find position to play sound for tile:", tileId)
			sound:Destroy()
			return
		end
	else
		sound.Parent = soundParent
		local soundDuration = (sound.TimeLength > 0 and sound.TimeLength) or 2
		Debris:AddItem(sound, soundDuration + 0.5)
	end

	sound:Play()
end


local instance = BoardController.new()
return instance
