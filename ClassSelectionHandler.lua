-- FixedClassSelectionHandler.lua
-- จัดการหน้าเลือกคลาสพื้นฐาน (Warrior, Thief, Mage)
-- Version: 7.1.1 (Fixed BackgroundTransparency error on ScreenGui)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- Debug mode
local DEBUG_MODE = false

-- Debug helper function
local function debugLog(message)
	if DEBUG_MODE then
		print("[ClassSelectionHandler] " .. message)
	end
end

-- โหลดข้อมูลคลาสจาก SharedModules
local ClassData = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("ClassData"))

-- Get current player
local player = Players.LocalPlayer
if not player then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	player = Players.LocalPlayer
end

-- UI references
local PlayerGui, ClassSelection, Background, TitleText, ClassesContainer
local ConfirmButton, TimerFrame, TimerText, PlayersSelectionStatus
local WarriorClass, MageClass, ThiefClass

-- คลาสพื้นฐานที่เลือกได้ (กำหนดแค่ 3 คลาสเริ่มต้น)
local STARTER_CLASSES = {
	"Warrior",
	"Thief",
	"Mage"
}

-- RemoteEvents references
local remotes = {}

-- Selection state
local selectionState = {
	selectedClass = nil,
	isConfirmed = false,
	playerSelections = {},
	playerFrames = {},
	timerValue = 60,
	isTimerActive = false,
	isInitialized = false, -- Track if initialize ran
	isActive = false -- Track if screen is currently active
}

-- Track connections
local connections = {}

-- Standard UI colors
local COLORS = {
	DEFAULT_FRAME = Color3.fromRGB(50, 50, 70),
	SELECTED_FRAME = Color3.fromRGB(60, 90, 140),
	HOVER_FRAME = Color3.fromRGB(60, 70, 100),
	DEFAULT_STROKE = Color3.fromRGB(100, 100, 150),
	SELECTED_STROKE = Color3.fromRGB(100, 200, 255),
	CONFIRM_ENABLED = Color3.fromRGB(40, 140, 60),
	CONFIRM_DISABLED = Color3.fromRGB(60, 60, 80),
	TIMER_NORMAL = Color3.fromRGB(255, 255, 255),
	TIMER_WARNING = Color3.fromRGB(255, 150, 50),
	TIMER_CRITICAL = Color3.fromRGB(255, 50, 50),
	WARRIOR_COLOR = Color3.fromRGB(200, 80, 80),
	MAGE_COLOR = Color3.fromRGB(70, 100, 200),
	THIEF_COLOR = Color3.fromRGB(80, 180, 80)
}

-- Helper function for tweening
local function createTween(object, properties, duration, style, direction)
	local tweenInfo = TweenInfo.new(
		duration or 0.3,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)
	local tween = TweenService:Create(object, tweenInfo, properties)
	return tween
end

-- Clean up connections specific to this handler
local function cleanupClassSelectionConnections()
	debugLog("Cleaning up ClassSelection connections")
	for _, connection in ipairs(connections) do
		if typeof(connection) == "RBXScriptConnection" and connection.Connected then
			connection:Disconnect()
		end
	end
	connections = {}
end

-- Fix timer frame positioning
local function fixTimerPosition()
	if not TimerFrame then return end
	debugLog("Fixing timer position")
	TimerFrame.Position = UDim2.new(0.9, 0, 0.05, 0)
	TimerFrame.Size = UDim2.new(0.15, 0, 0.06, 0)
	TimerFrame.AnchorPoint = Vector2.new(1, 0)
	TimerFrame.BackgroundTransparency = 0.2
	TimerFrame.ZIndex = 10
	if TimerText then TimerText.ZIndex = 11 end
	if not TimerFrame:FindFirstChild("UICorner") then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = TimerFrame
	end
	if not TimerFrame:FindFirstChild("UIStroke") then
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(200, 200, 255)
		stroke.Thickness = 2
		stroke.Parent = TimerFrame
	end
	debugLog("Timer position fixed")
end

-- Initialize UI references (Does NOT enable the screen)
local function initializeUI()
	debugLog("Initializing UI References")

	PlayerGui = player:WaitForChild("PlayerGui", 10)
	if not PlayerGui then warn("ClassSelectionHandler: PlayerGui not found"); return false end

	ClassSelection = PlayerGui:WaitForChild("ClassSelection", 5)
	if not ClassSelection then warn("ClassSelectionHandler: ClassSelection not found"); return false end

	-- *** CRITICAL: Ensure it starts disabled ***
	ClassSelection.Enabled = false
	-- ClassSelection.BackgroundTransparency = 1 -- <<< REMOVED THIS LINE - Cannot set transparency on ScreenGui itself

	Background = ClassSelection:WaitForChild("Background", 3)
	if not Background then return false end
	Background.BackgroundTransparency = 1 -- Ensure background Frame starts transparent

	TitleText = Background:WaitForChild("TitleText", 2)
	ClassesContainer = Background:WaitForChild("ClassesContainer", 2)
	ConfirmButton = Background:WaitForChild("ConfirmButton", 2)
	TimerFrame = Background:WaitForChild("TimerFrame", 2)
	if TimerFrame then TimerText = TimerFrame:WaitForChild("TimerText", 1) end
	PlayersSelectionStatus = Background:WaitForChild("PlayersSelectionStatus", 2)

	if not TitleText or not ClassesContainer or not ConfirmButton then
		warn("ClassSelectionHandler: Essential UI components missing")
		return false
	end

	WarriorClass = ClassesContainer:FindFirstChild("WarriorClass")
	MageClass = ClassesContainer:FindFirstChild("MageClass")
	ThiefClass = ClassesContainer:FindFirstChild("ThiefClass")

	if not WarriorClass or not MageClass or not ThiefClass then
		warn("ClassSelectionHandler: Class frames missing")
		return false
	end

	-- Set initial timer text if available
	if TimerText then
		TimerText.Text = "Time: " .. selectionState.timerValue
	end

	debugLog("UI references initialized successfully (Screen remains disabled)")
	return true
end

-- Connect to RemoteEvents
local function connectRemoteEvents()
	debugLog("Connecting to remote events")
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then return false end
	local uiRemotes = remotesFolder:WaitForChild("UIRemotes", 5)
	if not uiRemotes then return false end

	remotes.playerSelectedClass = uiRemotes:WaitForChild("PlayerSelectedClass", 3)
	remotes.updateClassSelection = uiRemotes:WaitForChild("UpdateClassSelection", 3)
	remotes.updateClassSelectionTimer = uiRemotes:WaitForChild("UpdateClassSelectionTimer", 3)
	remotes.notifyRandomClass = uiRemotes:WaitForChild("NotifyRandomClass", 3)
	remotes.showMainGameUI = uiRemotes:WaitForChild("ShowMainGameUI", 3)
	remotes.showClassSelection = uiRemotes:WaitForChild("ShowClassSelection", 3) -- Listen for activation signal

	for name, remote in pairs(remotes) do
		if not remote then warn("ClassSelectionHandler: Remote event missing - " .. name); return false end
	end
	debugLog("Remote events connected successfully")
	return true
end

-- Apply hover effects to UI elements
local function applyUIEffects()
	debugLog("Applying UI effects")
	for _, classFrame in pairs({WarriorClass, MageClass, ThiefClass}) do
		if not classFrame then continue end
		classFrame.BackgroundTransparency = 0.1
		if not classFrame:FindFirstChild("UIStroke") then Instance.new("UIStroke", classFrame).Color = COLORS.DEFAULT_STROKE; Instance.new("UIStroke", classFrame).Thickness = 2 end
		if not classFrame:FindFirstChild("UICorner") then Instance.new("UICorner", classFrame).CornerRadius = UDim.new(0, 8) end
		if not classFrame:GetAttribute("EffectsApplied") then
			local enter = classFrame.MouseEnter:Connect(function() if not selectionState.selectedClass or classFrame.Name:sub(1, -6) ~= selectionState.selectedClass then createTween(classFrame, {BackgroundColor3 = COLORS.HOVER_FRAME}, 0.2):Play() end end)
			local leave = classFrame.MouseLeave:Connect(function() if not selectionState.selectedClass or classFrame.Name:sub(1, -6) ~= selectionState.selectedClass then createTween(classFrame, {BackgroundColor3 = COLORS.DEFAULT_FRAME}, 0.2):Play() end end)
			table.insert(connections, enter); table.insert(connections, leave)
			classFrame:SetAttribute("EffectsApplied", true)
		end
	end
	if ConfirmButton and not ConfirmButton:GetAttribute("EffectsApplied") then
		if not ConfirmButton:FindFirstChild("UIStroke") then Instance.new("UIStroke", ConfirmButton).Color = COLORS.DEFAULT_STROKE; Instance.new("UIStroke", ConfirmButton).Thickness = 2 end
		if not ConfirmButton:FindFirstChild("UICorner") then Instance.new("UICorner", ConfirmButton).CornerRadius = UDim.new(0, 8) end
		local enter = ConfirmButton.MouseEnter:Connect(function() if selectionState.selectedClass and not selectionState.isConfirmed then createTween(ConfirmButton, {Size = UDim2.new(ConfirmButton.Size.X.Scale * 1.05, 0, ConfirmButton.Size.Y.Scale * 1.05, 0)}, 0.2):Play() end end)
		local leave = ConfirmButton.MouseLeave:Connect(function() if selectionState.selectedClass and not selectionState.isConfirmed then createTween(ConfirmButton, {Size = UDim2.new(ConfirmButton.Size.X.Scale / 1.05, 0, ConfirmButton.Size.Y.Scale / 1.05, 0)}, 0.2):Play() end end)
		table.insert(connections, enter); table.insert(connections, leave)
		ConfirmButton:SetAttribute("EffectsApplied", true)
	end
	debugLog("UI effects applied")
end

-- Update class display
local function updateClassVisuals()
	if not selectionState.isActive then return end -- Only update if active
	for _, classFrame in pairs({WarriorClass, MageClass, ThiefClass}) do
		if classFrame then
			createTween(classFrame, {BackgroundColor3 = COLORS.DEFAULT_FRAME, BackgroundTransparency = 0.1}):Play()
			local stroke = classFrame:FindFirstChild("UIStroke"); if stroke then stroke.Color = COLORS.DEFAULT_STROKE; stroke.Thickness = 2 end
		end
	end
	if selectionState.selectedClass then
		local selectedFrame = (selectionState.selectedClass == "Warrior" and WarriorClass) or (selectionState.selectedClass == "Mage" and MageClass) or (selectionState.selectedClass == "Thief" and ThiefClass)
		if selectedFrame then
			createTween(selectedFrame, {BackgroundColor3 = COLORS.SELECTED_FRAME, BackgroundTransparency = 0}):Play()
			local stroke = selectedFrame:FindFirstChild("UIStroke"); if stroke then stroke.Color = COLORS.SELECTED_STROKE; stroke.Thickness = 3 end
		end
	end
	if ConfirmButton then
		local confirmText = ConfirmButton:FindFirstChild("ConfirmText")
		local stroke = ConfirmButton:FindFirstChild("UIStroke")
		if selectionState.selectedClass and not selectionState.isConfirmed then
			ConfirmButton.BackgroundColor3 = COLORS.CONFIRM_ENABLED; ConfirmButton.Active = true; ConfirmButton.AutoButtonColor = true
			if stroke then stroke.Color = Color3.fromRGB(100, 255, 100); stroke.Thickness = 2 end
			if confirmText then confirmText.TextColor3 = Color3.fromRGB(255, 255, 255); confirmText.Text = "CONFIRM" end
		else
			ConfirmButton.BackgroundColor3 = COLORS.CONFIRM_DISABLED; ConfirmButton.Active = false; ConfirmButton.AutoButtonColor = false
			if stroke then stroke.Color = Color3.fromRGB(150, 150, 150); stroke.Thickness = 1 end
			if confirmText then confirmText.TextColor3 = Color3.fromRGB(200, 200, 200); confirmText.Text = selectionState.isConfirmed and "Waiting..." or "CONFIRM" end
		end
	end
end

-- Select class function
local function selectClass(className)
	if not selectionState.isActive or selectionState.isConfirmed then return end -- Only select if active and not confirmed
	local isValid = table.find(STARTER_CLASSES, className)
	if not isValid then warn("Invalid class selected: " .. className); return end
	debugLog("Selecting class: " .. className)
	selectionState.selectedClass = className
	updateClassVisuals()
	local selectedFrame = (className == "Warrior" and WarriorClass) or (className == "Mage" and MageClass) or (className == "Thief" and ThiefClass)
	if selectedFrame then
		local tween = createTween(selectedFrame, {Size = UDim2.new(selectedFrame.Size.X.Scale * 1.05, 0, selectedFrame.Size.Y.Scale * 1.05, 0)}, 0.4, Enum.EasingStyle.Bounce)
		tween:Play()
		tween.Completed:Wait() -- Wait for bounce out
		-- Only tween back if this is still the selected class
		if selectionState.selectedClass == className then
			createTween(selectedFrame, {Size = UDim2.new(selectedFrame.Size.X.Scale / 1.05, 0, selectedFrame.Size.Y.Scale / 1.05, 0)}, 0.2):Play()
		end
	end
end

-- Update timer display
local function updateTimer(timeLeft)
	if not selectionState.isActive then return end -- Only update if active
	selectionState.timerValue = timeLeft
	if TimerText then
		TimerText.Text = "Time: " .. timeLeft
		local color = COLORS.TIMER_NORMAL
		if timeLeft <= 5 then color = COLORS.TIMER_CRITICAL
		elseif timeLeft <= 10 then color = COLORS.TIMER_WARNING end
		TimerText.TextColor3 = color
		if timeLeft <= 5 then -- Flash effect
			local flashTween = createTween(TimerFrame, {BackgroundColor3 = Color3.fromRGB(200, 50, 50)}, 0.3)
			flashTween.Completed:Connect(function() createTween(TimerFrame, {BackgroundColor3 = Color3.fromRGB(50, 50, 70)}, 0.3):Play() end)
			flashTween:Play()
		end
	end
end

-- Update player selection status
local function updatePlayerSelectionStatus(userId, className)
	if not selectionState.isActive then return end -- Only update if active
	selectionState.playerSelections[userId] = className
	if not PlayersSelectionStatus then return end

	-- Find player name
	local playerObj = Players:GetPlayerByUserId(userId)
	local playerName = playerObj and playerObj.Name or "Player"

	-- Find or create player status frame
	local statusFrame = selectionState.playerFrames[userId]
	if not statusFrame then
		local template = PlayersSelectionStatus:FindFirstChild("PlayerStatus")
		if template then
			statusFrame = template:Clone()
			statusFrame.Visible = true
			statusFrame.Name = "PlayerStatus_" .. userId
			statusFrame.Text = playerName .. ": Selecting..." -- Initial text
			statusFrame.LayoutOrder = #Players:GetPlayers() -- Simple layout order
			statusFrame.Parent = PlayersSelectionStatus
			selectionState.playerFrames[userId] = statusFrame
		else
			warn("PlayerStatus template not found in PlayersSelectionStatus")
			return -- Cannot proceed without template
		end
	end

	-- Update display
	if statusFrame and className then
		statusFrame.Text = playerName .. ": " .. className
		local color = (className == "Warrior" and COLORS.WARRIOR_COLOR) or (className == "Mage" and COLORS.MAGE_COLOR) or (className == "Thief" and COLORS.THIEF_COLOR) or Color3.fromRGB(100, 255, 100)
		statusFrame.TextColor3 = color
		local tween = createTween(statusFrame, {TextSize = statusFrame.TextSize + 2}, 0.3)
		tween:Play()
		tween.Completed:Connect(function() createTween(statusFrame, {TextSize = statusFrame.TextSize - 2}, 0.3):Play() end)
	elseif statusFrame then -- Player hasn't selected yet
		statusFrame.Text = playerName .. ": Selecting..."
		statusFrame.TextColor3 = Color3.fromRGB(200, 200, 200) -- Default greyish color
	end

	-- Update title count (optional)
	-- local selectedCount = 0
	-- for _, selection in pairs(selectionState.playerSelections) do if selection then selectedCount = selectedCount + 1 end end
	-- if TitleText then TitleText.Text = "Choose Your Class (" .. selectedCount .. "/" .. #Players:GetPlayers() .. ")" end
end

-- Confirm selection function
local function confirmSelection()
	if not selectionState.isActive or not selectionState.selectedClass or selectionState.isConfirmed then return end
	debugLog("Confirming selection: " .. selectionState.selectedClass)
	selectionState.isConfirmed = true

	-- Disable class selection buttons visually and functionally
	for _, classFrame in pairs({WarriorClass, MageClass, ThiefClass}) do
		if classFrame then classFrame.Active = false; classFrame.Selectable = false end -- Make sure they aren't clickable
	end

	-- Update confirm button state
	updateClassVisuals() -- This will handle the button text and appearance

	-- Send to server
	if remotes.playerSelectedClass then remotes.playerSelectedClass:FireServer(selectionState.selectedClass) end

	-- Update own selection status immediately
	updatePlayerSelectionStatus(player.UserId, selectionState.selectedClass)

	-- Confirmation animation
	if ConfirmButton then
		local originalColor = ConfirmButton.BackgroundColor3
		local flashTween = createTween(ConfirmButton, {BackgroundColor3 = Color3.fromRGB(100, 255, 100)}, 0.3)
		flashTween:Play()
		flashTween.Completed:Connect(function() createTween(ConfirmButton, {BackgroundColor3 = originalColor}, 0.3):Play() end)
	end
end

-- Handle random class assignment
local function handleRandomClassAssignment(className)
	if not selectionState.isActive or selectionState.isConfirmed then return end -- Don't assign if not active or already confirmed
	local isValid = table.find(STARTER_CLASSES, className)
	if not isValid then warn("Invalid random class assigned: " .. className); return end
	debugLog("Handling random class assignment: " .. className)

	-- Select the class (this updates visuals)
	selectClass(className)

	-- Show notification
	local notification = Background:FindFirstChild("RandomClassNotification")
	if not notification then -- Create if doesn't exist
		notification = Instance.new("Frame", Background)
		notification.Name = "RandomClassNotification"
		notification.Size = UDim2.new(0.6, 0, 0.15, 0)
		notification.BackgroundColor3 = Color3.fromRGB(200, 80, 80)
		notification.BackgroundTransparency = 0.2
		notification.BorderSizePixel = 0
		notification.ZIndex = 10
		Instance.new("UICorner", notification).CornerRadius = UDim.new(0, 8)
		Instance.new("UIStroke", notification).Color = Color3.fromRGB(255, 150, 150); Instance.new("UIStroke", notification).Thickness = 3
		local textLabel = Instance.new("TextLabel", notification)
		textLabel.Size = UDim2.new(1, 0, 1, 0); textLabel.BackgroundTransparency = 1
		textLabel.TextColor3 = Color3.fromRGB(255, 255, 255); textLabel.TextSize = 20
		textLabel.Font = Enum.Font.GothamBold; textLabel.TextWrapped = true; textLabel.ZIndex = 11
	end

	local notificationText = notification:FindFirstChildOfClass("TextLabel")
	if notificationText then notificationText.Text = "Time's up! System randomly selected " .. className .. " for you" end

	notification.Position = UDim2.new(0.2, 0, -0.2, 0) -- Start off-screen
	notification.Visible = true
	notification.BackgroundTransparency = 0.2 -- Make visible again
	createTween(notification, {Position = UDim2.new(0.2, 0, 0.1, 0)}, 0.5):Play()

	-- Automatically confirm this selection after a short delay
	task.delay(0.5, function()
		if not selectionState.isConfirmed then -- Only confirm if not already done
			confirmSelection()
		end
	end)

	-- Hide notification after a while
	task.delay(3.5, function()
		if notification and notification.Parent then
			createTween(notification, {Position = UDim2.new(0.2, 0, -0.2, 0), BackgroundTransparency = 1}, 0.5):Play()
			task.wait(0.5)
			notification.Visible = false
		end
	end)
end

-- Transition to main game
local function transitionToMainGame()
	debugLog("Transitioning to main game")
	selectionState.isActive = false -- Mark as inactive

	-- Fade out effect
	local fadeOutTween = createTween(Background, {BackgroundTransparency = 1}, 0.5)
	for _, element in pairs(Background:GetDescendants()) do
		if element:IsA("GuiObject") then createTween(element, {BackgroundTransparency = 1}, 0.5):Play() end
		if element:IsA("TextLabel") or element:IsA("TextButton") then createTween(element, {TextTransparency = 1}, 0.5):Play() end
	end
	fadeOutTween:Play()

	fadeOutTween.Completed:Connect(function()
		ClassSelection.Enabled = false -- Disable after fade
		debugLog("ClassSelection disabled.")
		local MainGameUI = PlayerGui:FindFirstChild("MainGameUI")
		if MainGameUI then
			MainGameUI.Enabled = true
			debugLog("Main game UI shown")
			-- Potentially call an init function on MainGameUI handler here
		else
			warn("MainGameUI not found")
		end
		cleanupClassSelectionConnections() -- Clean up connections for this screen
	end)
end

-- Setup button connections (Called when screen becomes active)
local function setupButtonConnections()
	if not selectionState.isActive then return end -- Only connect if active
	cleanupClassSelectionConnections() -- Clear previous connections first
	debugLog("Setting up button connections")

	local function connectClassButton(classButton, className)
		if not classButton then return end
		if classButton:GetAttribute("Connected") then return end -- Avoid double connection
		local connection = classButton.MouseButton1Click:Connect(function() selectClass(className) end)
		table.insert(connections, connection)
		classButton:SetAttribute("Connected", true)
	end
	connectClassButton(WarriorClass, "Warrior")
	connectClassButton(MageClass, "Mage")
	connectClassButton(ThiefClass, "Thief")

	if ConfirmButton and not ConfirmButton:GetAttribute("Connected") then
		local connection = ConfirmButton.MouseButton1Click:Connect(confirmSelection)
		table.insert(connections, connection)
		ConfirmButton:SetAttribute("Connected", true)
	end

	local connection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end -- Ignore if chat or other UI handled it
		if input.KeyCode == Enum.KeyCode.Return and selectionState.isActive and selectionState.selectedClass and not selectionState.isConfirmed then
			confirmSelection()
		end
	end)
	table.insert(connections, connection)
	debugLog("Button connections set up")
end

-- Setup remote event connections (Called when screen becomes active)
local function setupRemoteConnections()
	if not selectionState.isActive then return end -- Only connect if active
	debugLog("Setting up remote connections")

	-- Note: These connections are added to the 'connections' table managed by cleanupClassSelectionConnections

	if remotes.updateClassSelection then
		local conn = remotes.updateClassSelection.OnClientEvent:Connect(updatePlayerSelectionStatus)
		table.insert(connections, conn)
	end
	if remotes.updateClassSelectionTimer then
		local conn = remotes.updateClassSelectionTimer.OnClientEvent:Connect(updateTimer)
		table.insert(connections, conn)
	end
	if remotes.notifyRandomClass then
		local conn = remotes.notifyRandomClass.OnClientEvent:Connect(handleRandomClassAssignment)
		table.insert(connections, conn)
	end
	if remotes.showMainGameUI then
		local conn = remotes.showMainGameUI.OnClientEvent:Connect(transitionToMainGame)
		table.insert(connections, conn)
	end

	-- Player Added/Removing listeners for updating the status list
	local function updatePlayerList()
		if not selectionState.isActive or not PlayersSelectionStatus then return end
		debugLog("Updating player list display")
		-- Clear existing frames first
		for userId, frame in pairs(selectionState.playerFrames) do
			if not Players:GetPlayerByUserId(userId) then
				frame:Destroy()
				selectionState.playerFrames[userId] = nil
				selectionState.playerSelections[userId] = nil -- Clear data too
			end
		end
		-- Add/update frames for current players
		for _, p in ipairs(Players:GetPlayers()) do
			updatePlayerSelectionStatus(p.UserId, selectionState.playerSelections[p.UserId])
		end
	end

	local connAdded = Players.PlayerAdded:Connect(function() task.wait(0.1); updatePlayerList() end)
	local connRemoving = Players.PlayerRemoving:Connect(function() task.wait(0.1); updatePlayerList() end)
	table.insert(connections, connAdded)
	table.insert(connections, connRemoving)

	debugLog("Remote connections set up")
end

-- *** Function to activate the Class Selection screen ***
local function activateClassSelection()
	if selectionState.isActive then return end -- Already active
	debugLog("Activating Class Selection screen...")
	selectionState.isActive = true

	-- Reset state for activation
	selectionState.selectedClass = nil
	selectionState.isConfirmed = false
	-- Don't reset playerSelections immediately, wait for server updates

	-- Ensure UI is ready
	if not selectionState.isInitialized then
		warn("Attempted to activate ClassSelection before initialization!")
		if not initializeUI() then return end -- Try initializing now
		selectionState.isInitialized = true
	end

	-- Enable the screen and fade in
	ClassSelection.Enabled = true
	createTween(Background, {BackgroundTransparency = 0}, 0.5):Play() -- Fade in background Frame

	-- Apply effects, fix positions, connect buttons/remotes
	fixTimerPosition()
	applyUIEffects()
	setupButtonConnections()
	setupRemoteConnections()

	-- Update visuals and player list
	updateClassVisuals()
	-- Update player list based on current players
	for _, p in ipairs(Players:GetPlayers()) do
		updatePlayerSelectionStatus(p.UserId, selectionState.playerSelections[p.UserId]) -- Use existing data if available
	end

	debugLog("Class Selection Activated.")
end


-- Initialization function (Runs once when script starts)
local function initialize()
	if selectionState.isInitialized then return end
	debugLog("Initializing ClassSelectionHandler Script")

	-- Initialize UI references (keeps screen disabled)
	if not initializeUI() then
		warn("ClassSelectionHandler: Failed to initialize UI")
		return
	end

	-- Connect to RemoteEvents (including the activation signal)
	if not connectRemoteEvents() then
		warn("ClassSelectionHandler: Failed to connect remote events")
		return
	end

	-- *** CRITICAL: Listen for the activation signal from LoadingScreenHandler/Server ***
	if remotes.showClassSelection then
		local activationConnection = remotes.showClassSelection.OnClientEvent:Connect(activateClassSelection)
		-- This connection should persist even if others are cleaned up
	else
		warn("ClassSelectionHandler: Could not connect to ShowClassSelection event for activation!")
	end

	selectionState.isInitialized = true
	debugLog("ClassSelectionHandler Script Initialized. Waiting for activation signal.")
end

-- Setup cleanup when player leaves
Players.PlayerRemoving:Connect(function(plr)
	if plr == player then
		cleanupClassSelectionConnections()
		selectionState.isActive = false -- Mark inactive on leave
	end
end)

-- Enable debug mode function
local function enableDebugMode(enable)
	DEBUG_MODE = enable
	debugLog("Debug mode " .. (enable and "enabled" or "disabled"))
	return DEBUG_MODE
end

-- Start the initialization process
initialize()

-- Export public functions
local ClassSelectionHandler = {
	EnableDebug = enableDebugMode
}

return ClassSelectionHandler
