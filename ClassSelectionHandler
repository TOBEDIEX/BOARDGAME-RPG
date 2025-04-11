-- FixedClassSelectionHandler.lua
-- จัดการหน้าเลือกคลาสพื้นฐาน (Warrior, Thief, Mage)
-- Version: 7.0.0 (Fully Fixed with Correct Lua Syntax)

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
	isTimerActive = false
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

	-- สีสถานะสำหรับแต่ละคลาส
	WARRIOR_COLOR = Color3.fromRGB(200, 80, 80),   -- สีแดง
	MAGE_COLOR = Color3.fromRGB(70, 100, 200),     -- สีน้ำเงิน
	THIEF_COLOR = Color3.fromRGB(80, 180, 80)      -- สีเขียว
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

-- Clean up connections
local function cleanupConnections()
	for _, connection in ipairs(connections) do
		if typeof(connection) == "RBXScriptConnection" and connection.Connected then
			connection:Disconnect()
		end
	end
	connections = {}
	debugLog("Cleaned up all connections")
end

-- Fix timer frame positioning
local function fixTimerPosition()
	if not TimerFrame then return end

	debugLog("Fixing timer position")

	-- Ensure timer doesn't overlap with other UI elements
	TimerFrame.Position = UDim2.new(0.9, 0, 0.05, 0)
	TimerFrame.Size = UDim2.new(0.15, 0, 0.06, 0)
	TimerFrame.AnchorPoint = Vector2.new(1, 0)

	-- Make timer more visible
	TimerFrame.BackgroundTransparency = 0.2
	TimerFrame.ZIndex = 10

	if TimerText then
		TimerText.ZIndex = 11
	end

	-- Add UICorner if not present
	if not TimerFrame:FindFirstChild("UICorner") then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = TimerFrame
	end

	-- Add UIStroke for better visibility
	if not TimerFrame:FindFirstChild("UIStroke") then
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(200, 200, 255)
		stroke.Thickness = 2
		stroke.Parent = TimerFrame
	end

	debugLog("Timer position fixed")
end

-- Initialize UI references
local function initializeUI()
	debugLog("Initializing UI")

	-- Get PlayerGui and ClassSelection
	PlayerGui = player:WaitForChild("PlayerGui", 10)
	if not PlayerGui then 
		warn("ClassSelectionHandler: PlayerGui not found")
		return false 
	end

	ClassSelection = PlayerGui:WaitForChild("ClassSelection", 5)
	if not ClassSelection then 
		warn("ClassSelectionHandler: ClassSelection not found")
		return false 
	end

	-- Check if ClassSelection is already enabled
	if not ClassSelection.Enabled then
		ClassSelection.Enabled = false
		debugLog("ClassSelection disabled initially to prevent UI flash")
	end

	-- Get main UI components
	Background = ClassSelection:WaitForChild("Background", 3)
	if not Background then return false end

	TitleText = Background:WaitForChild("TitleText", 2)
	ClassesContainer = Background:WaitForChild("ClassesContainer", 2)
	ConfirmButton = Background:WaitForChild("ConfirmButton", 2)
	TimerFrame = Background:WaitForChild("TimerFrame", 2)

	if TimerFrame then 
		TimerText = TimerFrame:WaitForChild("TimerText", 1)

		-- Fix timer position
		fixTimerPosition()
	end

	PlayersSelectionStatus = Background:WaitForChild("PlayersSelectionStatus", 2)

	-- Validate required components
	if not TitleText or not ClassesContainer or not ConfirmButton then
		warn("ClassSelectionHandler: Essential UI components missing")
		return false
	end

	-- Get class frames
	WarriorClass = ClassesContainer:FindFirstChild("WarriorClass")
	MageClass = ClassesContainer:FindFirstChild("MageClass")
	ThiefClass = ClassesContainer:FindFirstChild("ThiefClass")

	if not WarriorClass or not MageClass or not ThiefClass then
		warn("ClassSelectionHandler: Class frames missing")
		return false
	end

	-- Set initial UI state
	if TimerText then
		TimerText.Text = "Time: " .. selectionState.timerValue
	end

	debugLog("UI initialized successfully")
	return true
end

-- Connect to RemoteEvents
local function connectRemoteEvents()
	debugLog("Connecting to remote events")

	-- Get Remotes folders
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then return false end

	local uiRemotes = remotesFolder:WaitForChild("UIRemotes", 5)

	-- Get RemoteEvents
	remotes.playerSelectedClass = uiRemotes:WaitForChild("PlayerSelectedClass", 3)
	remotes.updateClassSelection = uiRemotes:WaitForChild("UpdateClassSelection", 3)
	remotes.updateClassSelectionTimer = uiRemotes:WaitForChild("UpdateClassSelectionTimer", 3)
	remotes.notifyRandomClass = uiRemotes:WaitForChild("NotifyRandomClass", 3)
	remotes.showMainGameUI = uiRemotes:WaitForChild("ShowMainGameUI", 3)

	-- Validate all remotes
	for name, remote in pairs(remotes) do
		if not remote then 
			warn("ClassSelectionHandler: Remote event missing - " .. name)
			return false 
		end
	end

	debugLog("Remote events connected successfully")
	return true
end

-- Apply hover effects to UI elements
local function applyUIEffects()
	debugLog("Applying UI effects")

	-- Add hover effects to class frames
	for _, classFrame in pairs({WarriorClass, MageClass, ThiefClass}) do
		if not classFrame then continue end

		classFrame.BackgroundTransparency = 0.1

		-- Add UIStroke if missing
		if not classFrame:FindFirstChild("UIStroke") then
			local stroke = Instance.new("UIStroke")
			stroke.Color = COLORS.DEFAULT_STROKE
			stroke.Thickness = 2
			stroke.Parent = classFrame
		end

		-- Add UICorner if missing
		if not classFrame:FindFirstChild("UICorner") then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 8)
			corner.Parent = classFrame
		end

		-- Add hover effects if not already connected
		if not classFrame:GetAttribute("EffectsApplied") then
			local mouseEnter = classFrame.MouseEnter:Connect(function()
				if not selectionState.selectedClass or 
					classFrame.Name:sub(1, -6) ~= selectionState.selectedClass then
					createTween(classFrame, {BackgroundColor3 = COLORS.HOVER_FRAME}, 0.2):Play()
				end
			end)

			local mouseLeave = classFrame.MouseLeave:Connect(function()
				if not selectionState.selectedClass or 
					classFrame.Name:sub(1, -6) ~= selectionState.selectedClass then
					createTween(classFrame, {BackgroundColor3 = COLORS.DEFAULT_FRAME}, 0.2):Play()
				end
			end)

			table.insert(connections, mouseEnter)
			table.insert(connections, mouseLeave)

			classFrame:SetAttribute("EffectsApplied", true)
		end
	end

	-- Add confirm button effects
	if ConfirmButton and not ConfirmButton:GetAttribute("EffectsApplied") then
		-- Add UIStroke if missing
		if not ConfirmButton:FindFirstChild("UIStroke") then
			local stroke = Instance.new("UIStroke")
			stroke.Color = COLORS.DEFAULT_STROKE
			stroke.Thickness = 2
			stroke.Parent = ConfirmButton
		end

		-- Add UICorner if missing
		if not ConfirmButton:FindFirstChild("UICorner") then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 8)
			corner.Parent = ConfirmButton
		end

		-- Add hover effects
		local mouseEnter = ConfirmButton.MouseEnter:Connect(function()
			if selectionState.selectedClass and not selectionState.isConfirmed then
				createTween(
					ConfirmButton, 
					{Size = UDim2.new(ConfirmButton.Size.X.Scale * 1.05, 0, ConfirmButton.Size.Y.Scale * 1.05, 0)},
					0.2
				):Play()
			end
		end)

		local mouseLeave = ConfirmButton.MouseLeave:Connect(function()
			if selectionState.selectedClass and not selectionState.isConfirmed then
				createTween(
					ConfirmButton, 
					{Size = UDim2.new(ConfirmButton.Size.X.Scale / 1.05, 0, ConfirmButton.Size.Y.Scale / 1.05, 0)},
					0.2
				):Play()
			end
		end)

		table.insert(connections, mouseEnter)
		table.insert(connections, mouseLeave)

		ConfirmButton:SetAttribute("EffectsApplied", true)
	end

	debugLog("UI effects applied")
end

-- Update class display
local function updateClassVisuals()
	-- Reset all class frames
	for _, classFrame in pairs({WarriorClass, MageClass, ThiefClass}) do
		if classFrame then
			createTween(classFrame, {
				BackgroundColor3 = COLORS.DEFAULT_FRAME,
				BackgroundTransparency = 0.1
			}):Play()

			local stroke = classFrame:FindFirstChild("UIStroke")
			if stroke then
				stroke.Color = COLORS.DEFAULT_STROKE
				stroke.Thickness = 2
			end
		end
	end

	-- Highlight selected class
	if selectionState.selectedClass then
		local selectedFrame
		if selectionState.selectedClass == "Warrior" then selectedFrame = WarriorClass
		elseif selectionState.selectedClass == "Mage" then selectedFrame = MageClass
		elseif selectionState.selectedClass == "Thief" then selectedFrame = ThiefClass
		end

		if selectedFrame then
			createTween(selectedFrame, {
				BackgroundColor3 = COLORS.SELECTED_FRAME,
				BackgroundTransparency = 0
			}):Play()

			local stroke = selectedFrame:FindFirstChild("UIStroke")
			if stroke then
				stroke.Color = COLORS.SELECTED_STROKE
				stroke.Thickness = 3
			end
		end
	end

	-- Update confirm button state
	if ConfirmButton then
		if selectionState.selectedClass and not selectionState.isConfirmed then
			-- Active state
			ConfirmButton.BackgroundColor3 = COLORS.CONFIRM_ENABLED
			ConfirmButton.Active = true
			ConfirmButton.AutoButtonColor = true

			local stroke = ConfirmButton:FindFirstChild("UIStroke")
			if stroke then
				stroke.Color = Color3.fromRGB(100, 255, 100)
				stroke.Thickness = 2
			end

			local confirmText = ConfirmButton:FindFirstChild("ConfirmText")
			if confirmText then
				confirmText.TextColor3 = Color3.fromRGB(255, 255, 255)
				confirmText.Text = "CONFIRM"
			end
		else
			-- Inactive state
			ConfirmButton.BackgroundColor3 = COLORS.CONFIRM_DISABLED

			if selectionState.isConfirmed then
				ConfirmButton.Active = false
				ConfirmButton.AutoButtonColor = false

				local confirmText = ConfirmButton:FindFirstChild("ConfirmText")
				if confirmText then
					confirmText.Text = "Waiting for others..."
					confirmText.TextColor3 = Color3.fromRGB(200, 200, 200)
				end
			else
				ConfirmButton.Active = false

				local stroke = ConfirmButton:FindFirstChild("UIStroke")
				if stroke then
					stroke.Color = Color3.fromRGB(150, 150, 150)
					stroke.Thickness = 1
				end

				local confirmText = ConfirmButton:FindFirstChild("ConfirmText")
				if confirmText then
					confirmText.TextColor3 = Color3.fromRGB(200, 200, 200)
					confirmText.Text = "CONFIRM"
				end
			end
		end
	end
end

-- Select class function
local function selectClass(className)
	-- Don't allow selection after confirmation
	if selectionState.isConfirmed then 
		debugLog("Class selection rejected - already confirmed")
		return 
	end

	-- Validate class name (เฉพาะ 3 คลาสพื้นฐานเท่านั้น)
	local isValid = false
	for _, validClass in ipairs(STARTER_CLASSES) do
		if className == validClass then
			isValid = true
			break
		end
	end

	if not isValid then 
		warn("Invalid class selected: " .. className)
		return 
	end

	debugLog("Selecting class: " .. className)

	-- Set selected class
	selectionState.selectedClass = className

	-- Update display
	updateClassVisuals()

	-- Show selection effect
	local selectedFrame
	if className == "Warrior" then selectedFrame = WarriorClass
	elseif className == "Mage" then selectedFrame = MageClass
	elseif className == "Thief" then selectedFrame = ThiefClass
	end

	if selectedFrame then
		-- Pulse animation
		createTween(
			selectedFrame,
			{Size = UDim2.new(selectedFrame.Size.X.Scale * 1.05, 0, selectedFrame.Size.Y.Scale * 1.05, 0)},
			0.4,
			Enum.EasingStyle.Bounce
		):Play()

		wait(0.4)

		if selectionState.selectedClass == className then
			createTween(
				selectedFrame,
				{Size = UDim2.new(selectedFrame.Size.X.Scale / 1.05, 0, selectedFrame.Size.Y.Scale / 1.05, 0)}
			):Play()
		end
	end
end

-- Update timer display
local function updateTimer(timeLeft)
	-- Update timer value
	selectionState.timerValue = timeLeft

	-- Update display
	if TimerText then
		TimerText.Text = "Time: " .. timeLeft

		-- Change color based on time
		if timeLeft <= 5 then
			TimerText.TextColor3 = COLORS.TIMER_CRITICAL

			-- Flash effect
			local flashTween = createTween(
				TimerFrame,
				{BackgroundColor3 = Color3.fromRGB(200, 50, 50)},
				0.3
			)
			flashTween.Completed:Connect(function()
				createTween(
					TimerFrame,
					{BackgroundColor3 = Color3.fromRGB(50, 50, 70)},
					0.3
				):Play()
			end)
			flashTween:Play()

		elseif timeLeft <= 10 then
			TimerText.TextColor3 = COLORS.TIMER_WARNING
		else
			TimerText.TextColor3 = COLORS.TIMER_NORMAL
		end
	end
end

-- Update player selection status
local function updatePlayerSelectionStatus(userId, className)
	-- Store player selection
	selectionState.playerSelections[userId] = className

	-- ถ้าไม่มี PlayersSelectionStatus ให้ข้ามการอัปเดต
	if not PlayersSelectionStatus then return end

	-- Find or create player status frame
	if not selectionState.playerFrames[userId] then
		-- Look for template
		local template = PlayersSelectionStatus:FindFirstChild("PlayerStatus")

		if template then
			-- Create new status display
			local newStatus = template:Clone()
			newStatus.Visible = true
			newStatus.Name = "PlayerStatus_" .. userId

			-- Find player name
			local playerName = "Player"
			for _, p in pairs(Players:GetPlayers()) do
				if p.UserId == userId then
					playerName = p.Name
					break
				end
			end

			-- Set initial text
			newStatus.Text = playerName .. ": Selecting..."

			-- Set position
			local playerCount = 0
			for _ in pairs(selectionState.playerFrames) do
				playerCount = playerCount + 1
			end
			newStatus.LayoutOrder = playerCount + 1

			-- Store reference
			selectionState.playerFrames[userId] = newStatus
			newStatus.Parent = PlayersSelectionStatus
		end
	end

	-- Update display
	local statusFrame = selectionState.playerFrames[userId]
	if statusFrame and className then
		-- Find player name
		local playerName = "Player"
		for _, p in pairs(Players:GetPlayers()) do
			if p.UserId == userId then
				playerName = p.Name
				break
			end
		end

		-- Update text and color
		statusFrame.Text = playerName .. ": " .. className

		-- กำหนดสีตามคลาส
		if className == "Warrior" then
			statusFrame.TextColor3 = COLORS.WARRIOR_COLOR
		elseif className == "Mage" then
			statusFrame.TextColor3 = COLORS.MAGE_COLOR
		elseif className == "Thief" then
			statusFrame.TextColor3 = COLORS.THIEF_COLOR
		else
			statusFrame.TextColor3 = Color3.fromRGB(100, 255, 100)
		end

		-- Pulse animation
		createTween(statusFrame, {TextSize = statusFrame.TextSize + 2}, 0.3):Play()
		wait(0.3)
		createTween(statusFrame, {TextSize = statusFrame.TextSize - 2}, 0.3):Play()
	end

	-- Update count
	local selectedCount = 0
	local totalPlayers = #Players:GetPlayers()

	for _, selection in pairs(selectionState.playerSelections) do
		if selection then selectedCount = selectedCount + 1 end
	end

	-- Update title
	if TitleText then
		TitleText.Text = "Choose Your Class" 
		-- ไม่แสดงจำนวนผู้เล่น เพราะอาจจะมีปัญหาอื่นๆ
	end
end

-- Confirm selection function
local function confirmSelection()
	-- Check if class is selected and not already confirmed
	if not selectionState.selectedClass or selectionState.isConfirmed then 
		debugLog("Cannot confirm selection: " .. 
			(not selectionState.selectedClass and "no class selected" or "already confirmed"))
		return 
	end

	debugLog("Confirming selection: " .. selectionState.selectedClass)

	-- Set confirmed state
	selectionState.isConfirmed = true

	-- Disable class selection
	for _, classFrame in pairs({WarriorClass, MageClass, ThiefClass}) do
		if classFrame then classFrame.Active = false end
	end

	-- Update button
	if ConfirmButton then
		ConfirmButton.Active = false
		ConfirmButton.AutoButtonColor = false

		createTween(ConfirmButton, {
			BackgroundColor3 = Color3.fromRGB(30, 100, 30),
			BackgroundTransparency = 0.3
		}):Play()

		local confirmText = ConfirmButton:FindFirstChild("ConfirmText")
		if confirmText then
			confirmText.Text = "Waiting for others..."
		end
	end

	-- Send to server
	if remotes.playerSelectedClass then
		remotes.playerSelectedClass:FireServer(selectionState.selectedClass)
	end

	-- Update own selection status
	updatePlayerSelectionStatus(player.UserId, selectionState.selectedClass)

	-- แอนิเมชันการยืนยัน - แฟลชที่ปุ่ม Confirm 
	if ConfirmButton then
		local originalColor = ConfirmButton.BackgroundColor3
		local originalTransparency = ConfirmButton.BackgroundTransparency

		createTween(ConfirmButton, {
			BackgroundColor3 = Color3.fromRGB(100, 255, 100),
			BackgroundTransparency = 0
		}, 0.3):Play()

		wait(0.3)

		createTween(ConfirmButton, {
			BackgroundColor3 = originalColor,
			BackgroundTransparency = originalTransparency
		}, 0.3):Play()
	end
end

-- Handle random class assignment
local function handleRandomClassAssignment(className)
	-- Select the random class (ตรวจสอบว่าเป็นคลาสพื้นฐานหรือไม่)
	local isValid = false
	for _, validClass in ipairs(STARTER_CLASSES) do
		if className == validClass then
			isValid = true
			break
		end
	end

	if not isValid then 
		warn("Invalid random class assigned: " .. className)
		return 
	end

	debugLog("Handling random class assignment: " .. className)

	-- เลือกคลาส
	selectClass(className)

	-- แสดงการแจ้งเตือน
	local notification

	-- หาตัวที่มีอยู่แล้วใน UI
	for _, child in pairs(Background:GetChildren()) do
		if child:IsA("Frame") and child.Name:find("Notification") then
			notification = child:Clone()
			notification.Visible = true
			notification.Name = "RandomClassNotification"
			notification.Parent = Background
			break
		end
	end

	-- ถ้าไม่มี ให้สร้างใหม่
	if not notification then
		notification = Instance.new("Frame")
		notification.Name = "RandomClassNotification"
		notification.Size = UDim2.new(0.6, 0, 0.15, 0)
		notification.Position = UDim2.new(0.2, 0, -0.2, 0)
		notification.BackgroundColor3 = Color3.fromRGB(200, 80, 80)
		notification.BackgroundTransparency = 0.2
		notification.BorderSizePixel = 0
		notification.ZIndex = 10

		-- Add design elements
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = notification

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 150, 150)
		stroke.Thickness = 3
		stroke.Parent = notification

		-- Add text
		local notificationText = Instance.new("TextLabel")
		notificationText.Size = UDim2.new(1, 0, 1, 0)
		notificationText.BackgroundTransparency = 1
		notificationText.Text = "Time's up! System randomly selected " .. className .. " for you"
		notificationText.TextColor3 = Color3.fromRGB(255, 255, 255)
		notificationText.TextSize = 20
		notificationText.Font = Enum.Font.GothamBold
		notificationText.TextWrapped = true
		notificationText.ZIndex = 11
		notificationText.Parent = notification

		notification.Parent = Background
	else
		-- อัปเดตข้อความ
		local notificationText = notification:FindFirstChildOfClass("TextLabel")
		if notificationText then
			notificationText.Text = "Time's up! System randomly selected " .. className .. " for you"
		end
	end

	-- แสดงการแจ้งเตือน
	notification.Position = UDim2.new(0.2, 0, -0.2, 0)
	notification.Visible = true
	createTween(notification, {Position = UDim2.new(0.2, 0, 0.1, 0)}, 0.5):Play()

	-- Confirm selection
	wait(0.8)
	confirmSelection()

	-- ซ่อนการแจ้งเตือน
	wait(3)
	createTween(notification, {
		Position = UDim2.new(0.2, 0, -0.2, 0),
		BackgroundTransparency = 1
	}, 0.5):Play()

	wait(0.5)
	notification.Visible = false
end

-- Transition to main game
local function transitionToMainGame()
	debugLog("Transitioning to main game")

	-- Fade out effect
	local fadeOutTween = createTween(Background, {BackgroundTransparency = 1}, 0.5)

	-- Fade out all elements
	for _, element in pairs(Background:GetDescendants()) do
		if element:IsA("Frame") or element:IsA("ImageLabel") or element:IsA("ImageButton") then
			createTween(element, {BackgroundTransparency = 1}, 0.5):Play()
		elseif element:IsA("TextLabel") or element:IsA("TextButton") then
			createTween(element, {
				BackgroundTransparency = 1,
				TextTransparency = 1
			}, 0.5):Play()
		end
	end

	-- Play fade out
	fadeOutTween:Play()

	-- Handle transition
	fadeOutTween.Completed:Connect(function()
		-- Disable class selection
		ClassSelection.Enabled = false

		-- Find and show main game UI
		local MainGameUI = PlayerGui:WaitForChild("MainGameUI", 5)
		if MainGameUI then
			MainGameUI.Enabled = true
			debugLog("Main game UI shown")
		else
			warn("MainGameUI not found")
		end

		-- Clean up
		cleanupConnections()
	end)
end

-- Setup button connections
local function setupButtonConnections()
	-- Clear previous connections
	cleanupConnections()
	debugLog("Setting up button connections")

	-- Connect class buttons
	local function connectClassButton(classButton, className)
		if not classButton then return end

		-- Check if already connected
		if classButton:GetAttribute("Connected") then return end

		local connection = classButton.MouseButton1Click:Connect(function()
			selectClass(className)
		end)

		table.insert(connections, connection)
		classButton:SetAttribute("Connected", true)
	end

	connectClassButton(WarriorClass, "Warrior")
	connectClassButton(MageClass, "Mage")
	connectClassButton(ThiefClass, "Thief")

	-- Connect confirm button
	if ConfirmButton and not ConfirmButton:GetAttribute("Connected") then
		local connection = ConfirmButton.MouseButton1Click:Connect(function()
			confirmSelection()
		end)

		table.insert(connections, connection)
		ConfirmButton:SetAttribute("Connected", true)
	end

	-- Connect Enter key for confirmation
	local connection = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Return and 
			selectionState.selectedClass and not selectionState.isConfirmed then
			confirmSelection()
		end
	end)

	table.insert(connections, connection)
	debugLog("Button connections set up")
end

-- Setup remote event connections
local function setupRemoteConnections()
	debugLog("Setting up remote connections")

	-- Update class selection status
	if remotes.updateClassSelection then
		local connection = remotes.updateClassSelection.OnClientEvent:Connect(function(userId, className)
			updatePlayerSelectionStatus(userId, className)
		end)

		table.insert(connections, connection)
	end

	-- Update timer
	if remotes.updateClassSelectionTimer then
		local connection = remotes.updateClassSelectionTimer.OnClientEvent:Connect(function(timeLeft)
			updateTimer(timeLeft)
		end)

		table.insert(connections, connection)
	end

	-- Handle random class assignment
	if remotes.notifyRandomClass then
		local connection = remotes.notifyRandomClass.OnClientEvent:Connect(function(className)
			handleRandomClassAssignment(className)
		end)

		table.insert(connections, connection)
	end

	-- Transition to main game
	if remotes.showMainGameUI then
		local connection = remotes.showMainGameUI.OnClientEvent:Connect(function()
			transitionToMainGame()
		end)

		table.insert(connections, connection)
	end

	-- Player count tracking
	local connection = Players.PlayerAdded:Connect(function()
		wait()

		-- Update player count
		local selectedCount = 0
		for _, selection in pairs(selectionState.playerSelections) do
			if selection then selectedCount = selectedCount + 1 end
		end
	end)

	table.insert(connections, connection)

	connection = Players.PlayerRemoving:Connect(function(plr)
		wait()

		-- Remove data for player
		if selectionState.playerSelections[plr.UserId] then
			selectionState.playerSelections[plr.UserId] = nil
		end

		if selectionState.playerFrames[plr.UserId] then
			selectionState.playerFrames[plr.UserId]:Destroy()
			selectionState.playerFrames[plr.UserId] = nil
		end
	end)

	table.insert(connections, connection)
	debugLog("Remote connections set up")
end

-- Fix initial UI glitches 
local function fixUIGlitches()
	debugLog("Fixing UI glitches")

	-- Check for PlayerGui and ClassSelection
	if not PlayerGui or not ClassSelection then return end

	-- Ensure ClassSelection is enabled but transparent while initializing
	ClassSelection.Enabled = true

	-- Make background transparent initially
	if Background then
		Background.BackgroundTransparency = 1
	end

	-- Fade in the UI smoothly
	RunService.RenderStepped:Wait()

	if Background then
		createTween(Background, {BackgroundTransparency = 0}, 0.5):Play()
	end

	-- Call fixTimerPosition again after a slight delay
	spawn(function()
		wait(0.5)
		if TimerFrame then
			fixTimerPosition()
		end
	end)

	debugLog("UI glitches fixed")
end

-- Initialization function
local function initialize()
	debugLog("Initializing ClassSelectionHandler")

	-- Setup UI
	if not initializeUI() then
		warn("ClassSelectionHandler: Failed to initialize UI")
		return
	end

	-- Connect to RemoteEvents
	if not connectRemoteEvents() then
		warn("ClassSelectionHandler: Failed to connect remote events")
		return
	end

	-- Fix UI glitches
	fixUIGlitches()

	-- Apply UI effects
	applyUIEffects()

	-- Setup button connections
	setupButtonConnections()

	-- Setup remote connections
	setupRemoteConnections()

	-- Update initial display
	updateClassVisuals()

	-- Show current player status
	updatePlayerSelectionStatus(player.UserId)

	debugLog("ClassSelectionHandler initialization complete")
end

-- Setup cleanup when player leaves
Players.PlayerRemoving:Connect(function(plr)
	if plr == player then
		cleanupConnections()
	end
end)

-- Enable debug mode function
local function enableDebugMode(enable)
	DEBUG_MODE = enable
	debugLog("Debug mode " .. (enable and "enabled" or "disabled"))
	return DEBUG_MODE
end

-- Start system
initialize()

-- Export public functions
local ClassSelectionHandler = {
	EnableDebug = enableDebugMode,
	ForceUIFix = function()
		fixUIGlitches()
		fixTimerPosition()
	end
}

return ClassSelectionHandler
