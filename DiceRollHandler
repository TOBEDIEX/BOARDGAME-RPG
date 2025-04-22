-- DiceRollHandler.lua
-- Manages dice roll interface and path selection
-- Version: 2.7.0 (Added Death & Respawn Handling)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris") -- Added Debris service

-- Get local player
local player = Players.LocalPlayer

-- Get UI elements
local PlayerGui = player:WaitForChild("PlayerGui")
local PopupUI = PlayerGui:WaitForChild("PopupUI")
local DiceRollUI = PopupUI:WaitForChild("DiceRollUI")

-- Validate UI exists
if not DiceRollUI then
	warn("DiceRollUI not found in PopupUI")
	return
end

-- Get UI components
local DiceWheel = DiceRollUI:FindFirstChild("DiceWheel")
local DiceResult = DiceWheel and DiceWheel:FindFirstChild("DiceResult")
local RollButton = DiceRollUI:FindFirstChild("RollButton")
local PathSelectionContainer = DiceRollUI:FindFirstChild("PathSelectionContainer")
local RemainingStepsText = PathSelectionContainer and PathSelectionContainer:FindFirstChild("RemainingStepsText")
local ForwardButton = PathSelectionContainer and PathSelectionContainer:FindFirstChild("ForwardButton")
local LeftButton = PathSelectionContainer and PathSelectionContainer:FindFirstChild("LeftButton")
local RightButton = PathSelectionContainer and PathSelectionContainer:FindFirstChild("RightButton")

-- Validate required components
if not DiceWheel or not DiceResult or not RollButton or not PathSelectionContainer
	or not RemainingStepsText or not ForwardButton or not LeftButton or not RightButton then
	warn("Some required UI elements for DiceRollUI are missing")
	return
end

-- Get remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local boardRemotes = remotes:WaitForChild("BoardRemotes")
local gameRemotes = remotes:WaitForChild("GameRemotes")
local uiRemotes = remotes:WaitForChild("UIRemotes")

-- Get remote events
local rollDiceEvent = boardRemotes:WaitForChild("RollDice")
local showPathSelectionEvent = boardRemotes:WaitForChild("ShowPathSelection")
local choosePathEvent = boardRemotes:WaitForChild("ChoosePath")
local updateTurnEvent = gameRemotes:WaitForChild("UpdateTurn")

-- Create Remote for DiceBonus
local inventoryRemotes = remotes:WaitForChild("InventoryRemotes", 5)
if not inventoryRemotes then
	inventoryRemotes = Instance.new("Folder")
	inventoryRemotes.Name = "InventoryRemotes"
	inventoryRemotes.Parent = remotes
end

local diceBonusEvent = inventoryRemotes:FindFirstChild("DiceBonus")
if not diceBonusEvent then
	diceBonusEvent = Instance.new("RemoteEvent")
	diceBonusEvent.Name = "DiceBonus"
	diceBonusEvent.Parent = inventoryRemotes
end

-- Ensure PlayerRespawned event exists
local playerRespawnedEvent = uiRemotes:FindFirstChild("PlayerRespawned")
if not playerRespawnedEvent then
	playerRespawnedEvent = Instance.new("RemoteEvent")
	playerRespawnedEvent.Name = "PlayerRespawned"
	playerRespawnedEvent.Parent = uiRemotes
end

-- Constants
local DICE_ANIMATION_DURATION = 2
local DICE_VALUES = {1, 2, 3, 4, 5, 6}
local DIRECTIONS = {
	FRONT = "FRONT",
	LEFT = "LEFT",
	RIGHT = "RIGHT"
}

-- Variables
local isRolling = false
local canRoll = false
local currentDiceResult = nil
local currentPathChoices = nil
local remainingSteps = 0
local activeDiceBonus = 0
local bonusDiceResults = {}
local isFixedMovement = false -- Flag for fixed movement crystals
local isPlayerDead = false -- NEW: Track player death state

-- Create bonus dice function
local function createBonusDice(numBonusDice)
	-- Remove old dice first
	for _, dice in pairs(DiceWheel:GetChildren()) do
		if dice.Name:find("BonusDice") or dice.Name == "TotalResult" then
			dice:Destroy()
		end
	end

	bonusDiceResults = {}

	-- Position relative to main dice
	local mainDicePosition = DiceResult.Position
	local mainDiceAnchor = DiceResult.AnchorPoint
	local mainDiceSize = DiceResult.Size

	-- Spacing between dice
	local spacing = 1.5 -- Spacing as multiplier of dice width

	print("Creating " .. numBonusDice .. " bonus dice")

	-- If 1 bonus die, place to left of main die
	if numBonusDice == 1 then
		local bonusDice = DiceResult:Clone()
		bonusDice.Name = "BonusDice_1"
		bonusDice.Position = UDim2.new(mainDicePosition.X.Scale - spacing * mainDiceSize.X.Scale, 0, mainDicePosition.Y.Scale, 0)
		bonusDice.AnchorPoint = mainDiceAnchor
		bonusDice.TextColor3 = Color3.fromRGB(100, 255, 100) -- Light green
		bonusDice.Text = ""
		bonusDice.Parent = DiceWheel

		bonusDiceResults[1] = 0
	end

	-- If 2 bonus dice, place on left and right of main die
	if numBonusDice == 2 then
		-- Left die
		local leftDice = DiceResult:Clone()
		leftDice.Name = "BonusDice_L"
		leftDice.Position = UDim2.new(mainDicePosition.X.Scale - spacing * mainDiceSize.X.Scale, 0, mainDicePosition.Y.Scale, 0)
		leftDice.AnchorPoint = mainDiceAnchor
		leftDice.TextColor3 = Color3.fromRGB(100, 255, 100) -- Light green
		leftDice.Text = ""
		leftDice.Parent = DiceWheel

		-- Right die
		local rightDice = DiceResult:Clone()
		rightDice.Name = "BonusDice_R"
		rightDice.Position = UDim2.new(mainDicePosition.X.Scale + spacing * mainDiceSize.X.Scale, 0, mainDicePosition.Y.Scale, 0)
		rightDice.AnchorPoint = mainDiceAnchor
		rightDice.TextColor3 = Color3.fromRGB(100, 255, 100) -- Light green
		rightDice.Text = ""
		rightDice.Parent = DiceWheel

		bonusDiceResults[1] = 0
		bonusDiceResults[2] = 0
	end

	-- Support for more than 2 bonus dice if needed
	if numBonusDice > 2 then
		for i = 1, numBonusDice do
			local position
			if i % 2 == 1 then -- Odd dice go left
				local offset = math.ceil(i/2) * spacing
				position = UDim2.new(mainDicePosition.X.Scale - offset * mainDiceSize.X.Scale, 0, mainDicePosition.Y.Scale, 0)
			else -- Even dice go right
				local offset = (i/2) * spacing
				position = UDim2.new(mainDicePosition.X.Scale + offset * mainDiceSize.X.Scale, 0, mainDicePosition.Y.Scale, 0)
			end

			local bonusDice = DiceResult:Clone()
			bonusDice.Name = "BonusDice_" .. i
			bonusDice.Position = position
			bonusDice.AnchorPoint = mainDiceAnchor
			bonusDice.TextColor3 = Color3.fromRGB(100, 255, 100) -- Light green
			bonusDice.Text = ""
			bonusDice.Parent = DiceWheel

			bonusDiceResults[i] = 0
		end
	end

	return bonusDiceResults
end

-- Create total result display above main dice
local function createTotalResult(total)
	-- Remove old total
	local oldTotal = DiceWheel:FindFirstChild("TotalResult")
	if oldTotal then
		oldTotal:Destroy()
	end

	-- Get main dice position
	local mainDicePosition = DiceResult.Position
	local mainDiceAnchorPoint = DiceResult.AnchorPoint
	local mainDiceSize = DiceResult.Size

	-- Create total frame
	local totalFrame = Instance.new("Frame")
	totalFrame.Name = "TotalResult"
	totalFrame.Size = UDim2.new(0, 120, 0, 40) -- Larger size
	-- Position above main dice, centered
	totalFrame.Position = UDim2.new(mainDicePosition.X.Scale, 0, mainDicePosition.Y.Scale - 0.35, 0)
	totalFrame.AnchorPoint = Vector2.new(0.5, 0.5) -- Center anchored
	totalFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
	totalFrame.BackgroundTransparency = 0.2
	totalFrame.ZIndex = 5
	totalFrame.Parent = DiceWheel

	-- Add rounded corners
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = totalFrame

	-- Add shadow
	local shadow = Instance.new("UIStroke")
	shadow.Color = Color3.fromRGB(0, 0, 0)
	shadow.Transparency = 0.5
	shadow.Thickness = 2
	shadow.Parent = totalFrame

	-- Add total text
	local totalText = Instance.new("TextLabel")
	totalText.Name = "TotalText"
	totalText.Size = UDim2.new(1, 0, 1, 0)
	totalText.Position = UDim2.new(0.5, 0, 0.5, 0)
	totalText.AnchorPoint = Vector2.new(0.5, 0.5)
	totalText.BackgroundTransparency = 1
	totalText.TextColor3 = Color3.fromRGB(255, 255, 0) -- Yellow
	totalText.Font = Enum.Font.GothamBold
	totalText.TextSize = 22
	totalText.Text = "Total: " .. total
	totalText.ZIndex = 6
	totalText.Parent = totalFrame

	-- Animation
	totalFrame.Size = UDim2.new(0, 0, 0, 40)
	totalText.TextTransparency = 1

	-- Expand frame animation
	local frameTween = TweenService:Create(
		totalFrame,
		TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Size = UDim2.new(0, 120, 0, 40)}
	)
	frameTween:Play()

	-- Reveal text animation
	frameTween.Completed:Connect(function()
		local textTween = TweenService:Create(
			totalText,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{TextTransparency = 0}
		)
		textTween:Play()
	end)

	return totalFrame
end

-- Create dice bonus notification in top right
local function createBonusNotification(bonusAmount)
	-- Remove any existing notification
	local oldNotification = PlayerGui:FindFirstChild("DiceBonusNotification")
	if oldNotification then
		oldNotification:Destroy()
	end

	-- Create new notification
	local notification = Instance.new("Frame")
	notification.Name = "DiceBonusNotification"
	notification.Size = UDim2.new(0, 160, 0, 40)
	notification.Position = UDim2.new(1, -170, 0, 10) -- Top right
	notification.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	notification.BackgroundTransparency = 0.2
	notification.BorderSizePixel = 0
	notification.Parent = PlayerGui

	-- Add rounded corners
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = notification

	-- Notification text
	local text = Instance.new("TextLabel")
	text.Name = "NotificationText"
	text.Size = UDim2.new(1, -10, 1, 0)
	text.Position = UDim2.new(0.5, 0, 0.5, 0)
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamSemibold
	text.TextSize = 14
	text.TextColor3 = Color3.fromRGB(120, 255, 120)
	text.Text = "Dice Bonus: +" .. bonusAmount
	text.Parent = notification

	-- Icon
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 24, 0, 24)
	icon.Position = UDim2.new(0, 8, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.BackgroundTransparency = 1
	icon.Image = "rbxassetid://7228017567" -- Dice image
	icon.ImageColor3 = Color3.fromRGB(120, 255, 120)
	icon.Parent = notification

	-- Adjust text position
	text.Position = UDim2.new(0.6, 0, 0.5, 0)

	-- Animation
	notification.Size = UDim2.new(0, 0, 0, 40)
	local sizeTween = TweenService:Create(
		notification,
		TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Size = UDim2.new(0, 160, 0, 40)}
	)
	sizeTween:Play()

	return notification
end

-- Create fixed movement notification
local function createFixedMovementNotification(moveAmount)
	-- Remove any existing notification
	local oldNotification = PlayerGui:FindFirstChild("FixedMovementNotification")
	if oldNotification then
		oldNotification:Destroy()
	end

	-- Create new notification
	local notification = Instance.new("Frame")
	notification.Name = "FixedMovementNotification"
	notification.Size = UDim2.new(0, 190, 0, 40)
	notification.Position = UDim2.new(1, -200, 0, 60) -- Below the dice bonus notification
	notification.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	notification.BackgroundTransparency = 0.2
	notification.BorderSizePixel = 0
	notification.Parent = PlayerGui

	-- Add rounded corners
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = notification

	-- Notification text
	local text = Instance.new("TextLabel")
	text.Name = "NotificationText"
	text.Size = UDim2.new(1, -10, 1, 0)
	text.Position = UDim2.new(0.5, 0, 0.5, 0)
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamSemibold
	text.TextSize = 14
	text.TextColor3 = Color3.fromRGB(180, 180, 255) -- Light purple for crystal
	text.Text = "Moving exactly " .. moveAmount .. " space" .. (moveAmount > 1 and "s" or "")
	text.Parent = notification

	-- Icon
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 24, 0, 24)
	icon.Position = UDim2.new(0, 8, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.BackgroundTransparency = 1
	icon.Image = "rbxassetid://7060876128" -- Crystal image (replace with actual ID)
	icon.ImageColor3 = Color3.fromRGB(180, 180, 255)
	icon.Parent = notification

	-- Adjust text position
	text.Position = UDim2.new(0.6, 0, 0.5, 0)

	-- Animation
	notification.Size = UDim2.new(0, 0, 0, 40)
	local sizeTween = TweenService:Create(
		notification,
		TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Size = UDim2.new(0, 190, 0, 40)}
	)
	sizeTween:Play()

	return notification
end

-- Create notification for when player is dead
local function createDeathNotification()
	-- Remove any existing notification
	local oldNotification = PlayerGui:FindFirstChild("DeathNotification")
	if oldNotification then
		oldNotification:Destroy()
	end

	-- Create new notification
	local notification = Instance.new("Frame")
	notification.Name = "DeathNotification"
	notification.Size = UDim2.new(0, 240, 0, 50)
	notification.Position = UDim2.new(0.5, 0, 0.3, 0) -- Center top
	notification.AnchorPoint = Vector2.new(0.5, 0.5)
	notification.BackgroundColor3 = Color3.fromRGB(200, 30, 30) -- Red for death
	notification.BackgroundTransparency = 0.2
	notification.BorderSizePixel = 0
	notification.ZIndex = 10
	notification.Parent = PlayerGui

	-- Add rounded corners
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = notification

	-- Notification text
	local text = Instance.new("TextLabel")
	text.Name = "NotificationText"
	text.Size = UDim2.new(1, -10, 1, 0)
	text.Position = UDim2.new(0.5, 0, 0.5, 0)
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextSize = 18
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.Text = "You are dead! Respawning soon..."
	text.ZIndex = 11
	text.Parent = notification

	-- Animation
	notification.Size = UDim2.new(0, 0, 0, 50)
	local sizeTween = TweenService:Create(
		notification,
		TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Size = UDim2.new(0, 240, 0, 50)}
	)
	sizeTween:Play()

	-- Add pulsing effect to make it stand out
	task.spawn(function()
		while notification and notification.Parent do
			local pulseTween = TweenService:Create(
				notification,
				TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{BackgroundTransparency = 0.5}
			)
			pulseTween:Play()
			task.wait(1) -- Use task.wait instead of wait

			if not notification or not notification.Parent then break end

			local reverseTween = TweenService:Create(
				notification,
				TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{BackgroundTransparency = 0.2}
			)
			reverseTween:Play()
			task.wait(1) -- Use task.wait instead of wait
		end
	end)

	return notification
end

-- Show dice roll UI
local function showDiceRollUI()
	-- Don't show if player is dead
	if isPlayerDead then
		createDeathNotification()
		return
	end -- *** FIXED: Changed } to end ***

	DiceRollUI.Visible = true
	RollButton.Visible = true
	PathSelectionContainer.Visible = false

	-- Reset UI state
	DiceResult.Text = ""
	RemainingStepsText.Text = "Steps: 0"
	ForwardButton.Visible = false
	LeftButton.Visible = false
	RightButton.Visible = false

	isRolling = false
	currentDiceResult = nil
	currentPathChoices = nil
	remainingSteps = 0
	isFixedMovement = false -- Reset fixed movement flag

	-- Show bonus notification if active
	if activeDiceBonus > 0 then
		createBonusNotification(activeDiceBonus)
		createBonusDice(activeDiceBonus)
	else
		-- Remove any bonus dice
		for _, dice in pairs(DiceWheel:GetChildren()) do
			if dice.Name:find("BonusDice") or dice.Name == "TotalResult" then
				dice:Destroy()
			end
		end
	end
end

-- Hide dice roll UI
local function hideDiceRollUI()
	DiceRollUI.Visible = false
	isRolling = false
	canRoll = false
	isFixedMovement = false -- Reset fixed movement flag
end -- *** FIXED: Changed } to end ***

-- Animate dice roll
local function animateDiceRoll(finalResult, skipAnimation)
	-- Don't roll if player is dead
	if isPlayerDead then
		createDeathNotification()
		return
	end -- *** FIXED: Changed } to end ***

	if isRolling then return end

	isRolling = true
	RollButton.Visible = false

	-- For fixed movement (crystal items), we might want to skip the animation
	if skipAnimation then
		-- Update result without animation
		DiceResult.Text = tostring(finalResult)

		-- Skip animation and use the fixed result
		isRolling = false
		currentDiceResult = finalResult
		remainingSteps = finalResult

		-- Show fixed movement notification instead of total
		createFixedMovementNotification(finalResult)

		-- Fire the dice roll event to server
		rollDiceEvent:FireServer(finalResult)

		-- Flag that we're using fixed movement
		isFixedMovement = true

		return finalResult
	end

	-- Create bonus dice for standard rolls
	if activeDiceBonus > 0 then
		createBonusDice(activeDiceBonus)
	end

	-- Animation sequence
	local startTime = tick()
	local endTime = startTime + DICE_ANIMATION_DURATION
	local frameRate = 0.1
	local lastUpdate = 0

	-- Animation loop
	while tick() < endTime do
		local currentTime = tick()
		if currentTime - lastUpdate >= frameRate then
			lastUpdate = currentTime

			-- Random value for main dice
			local randomValue = DICE_VALUES[math.random(1, #DICE_VALUES)]
			DiceResult.Text = tostring(randomValue)

			-- Random values for bonus dice
			if activeDiceBonus == 1 then
				local bonusDice = DiceWheel:FindFirstChild("BonusDice_1")
				if bonusDice then
					local bonusValue = DICE_VALUES[math.random(1, #DICE_VALUES)]
					bonusDice.Text = tostring(bonusValue)
				end
			elseif activeDiceBonus == 2 then
				local leftDice = DiceWheel:FindFirstChild("BonusDice_L")
				local rightDice = DiceWheel:FindFirstChild("BonusDice_R")

				if leftDice then
					leftDice.Text = tostring(DICE_VALUES[math.random(1, #DICE_VALUES)])
				end

				if rightDice then
					rightDice.Text = tostring(DICE_VALUES[math.random(1, #DICE_VALUES)])
				end
			else
				-- For more than 2 bonus dice
				for i = 1, activeDiceBonus do
					local bonusDice = DiceWheel:FindFirstChild("BonusDice_" .. i)
					if bonusDice then
						bonusDice.Text = tostring(DICE_VALUES[math.random(1, #DICE_VALUES)])
					end
				end
			end

			-- Slow down animation near end
			local timeLeft = endTime - currentTime
			if timeLeft < 1 then
				frameRate = 0.2
			end

			task.wait(frameRate) -- Use task.wait
		end
		task.wait() -- Yield to prevent freezing
	end

	-- Get real dice results
	local mainDiceResult = finalResult
	local totalResult = mainDiceResult

	-- Record all dice results
	local allDiceResults = {
		main = mainDiceResult,
		bonus = {}
	}

	-- Generate results for bonus dice
	if activeDiceBonus == 1 then
		local bonusDice = DiceWheel:FindFirstChild("BonusDice_1")
		if bonusDice then
			local bonusValue = math.random(1, 6)
			table.insert(allDiceResults.bonus, bonusValue)
			bonusDice.Text = tostring(bonusValue)
			totalResult = totalResult + bonusValue
		end
	elseif activeDiceBonus == 2 then
		local leftDice = DiceWheel:FindFirstChild("BonusDice_L")
		local rightDice = DiceWheel:FindFirstChild("BonusDice_R")

		if leftDice then
			local leftValue = math.random(1, 6)
			table.insert(allDiceResults.bonus, leftValue)
			leftDice.Text = tostring(leftValue)
			totalResult = totalResult + leftValue
		end

		if rightDice then
			local rightValue = math.random(1, 6)
			table.insert(allDiceResults.bonus, rightValue)
			rightDice.Text = tostring(rightValue)
			totalResult = totalResult + rightValue
		end
	else
		-- For more than 2 bonus dice
		for i = 1, activeDiceBonus do
			local bonusDice = DiceWheel:FindFirstChild("BonusDice_" .. i)
			if bonusDice then
				local bonusValue = math.random(1, 6)
				table.insert(allDiceResults.bonus, bonusValue)
				bonusDice.Text = tostring(bonusValue)
				totalResult = totalResult + bonusValue
			end
		end
	end

	-- Display original result
	DiceResult.Text = tostring(mainDiceResult)

	-- Show total above
	if activeDiceBonus > 0 then
		createTotalResult(totalResult)
	end

	-- Bounce animation for main dice
	local resultTween = TweenService:Create(
		DiceResult,
		TweenInfo.new(0.5, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
		{TextSize = 60}
	)
	resultTween:Play()

	-- Bounce animation for bonus dice
	if activeDiceBonus == 1 then
		local bonusDice = DiceWheel:FindFirstChild("BonusDice_1")
		if bonusDice then
			local bonusTween = TweenService:Create(
				bonusDice,
				TweenInfo.new(0.5, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
				{TextSize = 48}
			)
			bonusTween:Play()
		end
	elseif activeDiceBonus == 2 then
		local leftDice = DiceWheel:FindFirstChild("BonusDice_L")
		local rightDice = DiceWheel:FindFirstChild("BonusDice_R")

		if leftDice then
			local leftTween = TweenService:Create(
				leftDice,
				TweenInfo.new(0.5, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
				{TextSize = 48}
			)
			leftTween:Play()
		end

		if rightDice then
			local rightTween = TweenService:Create(
				rightDice,
				TweenInfo.new(0.5, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
				{TextSize = 48}
			)
			rightTween:Play()
		end
	else
		-- For more than 2 bonus dice
		for i = 1, activeDiceBonus do
			local bonusDice = DiceWheel:FindFirstChild("BonusDice_" .. i)
			if bonusDice then
				local bonusTween = TweenService:Create(
					bonusDice,
					TweenInfo.new(0.5, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
					{TextSize = 48}
				)
				bonusTween:Play()
			end
		end
	end

	task.wait(0.5) -- Use task.wait

	-- Return to normal size
	local resetTween = TweenService:Create(
		DiceResult,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{TextSize = 36}
	)
	resetTween:Play()

	-- Return bonus dice to normal size
	if activeDiceBonus == 1 then
		local bonusDice = DiceWheel:FindFirstChild("BonusDice_1")
		if bonusDice then
			local resetBonusTween = TweenService:Create(
				bonusDice,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{TextSize = 32}
			)
			resetBonusTween:Play()
		end
	elseif activeDiceBonus == 2 then
		local leftDice = DiceWheel:FindFirstChild("BonusDice_L")
		local rightDice = DiceWheel:FindFirstChild("BonusDice_R")

		if leftDice then
			local resetLeftTween = TweenService:Create(
				leftDice,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{TextSize = 32}
			)
			resetLeftTween:Play()
		end

		if rightDice then
			local resetRightTween = TweenService:Create(
				rightDice,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{TextSize = 32}
			)
			resetRightTween:Play()
		end
	else
		-- For more than 2 bonus dice
		for i = 1, activeDiceBonus do
			local bonusDice = DiceWheel:FindFirstChild("BonusDice_" .. i)
			if bonusDice then
				local resetBonusTween = TweenService:Create(
					bonusDice,
					TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{TextSize = 32}
				)
				resetBonusTween:Play()
			end
		end
	end

	isRolling = false
	currentDiceResult = totalResult  -- Store total of all dice
	remainingSteps = totalResult     -- Use total for movement steps

	-- Debug output
	print("=== DICE ROLL RESULT ===")
	print("Main dice: " .. mainDiceResult)
	print("Bonus dice: " .. table.concat(allDiceResults.bonus, ", "))
	print("Total result: " .. totalResult)
	print("======================")

	task.wait(0.3) -- Use task.wait

	-- Send result to server
	rollDiceEvent:FireServer(totalResult)

	-- Reset bonus after use
	activeDiceBonus = 0

	-- Remove bonus notification
	local notification = PlayerGui:FindFirstChild("DiceBonusNotification")
	if notification then
		local hideTween = TweenService:Create(
			notification,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{Size = UDim2.new(0, 0, 0, 40)}
		)
		hideTween:Play()
		hideTween.Completed:Connect(function()
			notification:Destroy()
		end)
	end

	return totalResult
end

-- Show path choices
local function showPathChoices(choices)
	-- Don't show if player is dead
	if isPlayerDead then
		createDeathNotification()
		return
	end -- *** FIXED: Changed } to end ***

	PathSelectionContainer.Visible = true
	RemainingStepsText.Text = "Steps: " .. remainingSteps
	task.wait(0.5) -- Small delay for UI updates

	-- Reset buttons
	ForwardButton.Visible = false
	LeftButton.Visible = false
	RightButton.Visible = false

	-- Show available direction buttons
	for _, choice in ipairs(choices) do
		if choice.direction == DIRECTIONS.FRONT then
			ForwardButton.Visible = true
		elseif choice.direction == DIRECTIONS.LEFT then
			LeftButton.Visible = true
		elseif choice.direction == DIRECTIONS.RIGHT then
			RightButton.Visible = true
		end
	end

	currentPathChoices = choices
end

-- Choose path direction
local function choosePath(direction)
	-- Don't process if player is dead
	if isPlayerDead then
		createDeathNotification()
		return
	end -- *** FIXED: Changed } to end ***

	if not currentPathChoices then return end

	-- Hide buttons during movement
	ForwardButton.Visible = false
	LeftButton.Visible = false
	RightButton.Visible = false

	-- Send choice to server
	choosePathEvent:FireServer(direction)

	-- Update remaining steps
	remainingSteps = remainingSteps - 1
	RemainingStepsText.Text = "Steps: " .. remainingSteps

	if remainingSteps <= 0 then
		PathSelectionContainer.Visible = false
	end
end

-- Function to handle player death
local function onPlayerDeath()
	print("[DiceRollHandler] Player has died")
	isPlayerDead = true

	-- Hide all dice UI elements
	hideDiceRollUI()

	-- Show death notification
	createDeathNotification()
end -- *** FIXED: Changed } to end ***

-- Function to handle player respawn
local function onPlayerRespawn(respawnData)
	print("[DiceRollHandler] Player has respawned")
	isPlayerDead = false

	-- Remove death notification
	local deathNotification = PlayerGui:FindFirstChild("DeathNotification")
	if deathNotification then
		deathNotification:Destroy()
	end -- *** FIXED: Changed } to end ***

	-- Reset UI state
	isRolling = false
	canRoll = false
	currentDiceResult = nil
	currentPathChoices = nil
	remainingSteps = 0
	isFixedMovement = false
	activeDiceBonus = 0

	print("[DiceRollHandler] Dice system reset after respawn")
end -- *** FIXED: Changed } to end ***

-- Button event handlers
RollButton.Activated:Connect(function()
	if isPlayerDead then
		createDeathNotification()
		return
	end -- *** FIXED: Changed } to end ***

	if not isRolling and canRoll then
		local diceResult = math.random(1, 6)
		animateDiceRoll(diceResult)
	end
end)

ForwardButton.Activated:Connect(function()
	if not isPlayerDead then
		choosePath(DIRECTIONS.FRONT)
	else -- *** FIXED: Changed { to else ***
		createDeathNotification()
	end -- *** FIXED: Changed } to end ***
end)

LeftButton.Activated:Connect(function()
	if not isPlayerDead then
		choosePath(DIRECTIONS.LEFT)
	else -- *** FIXED: Changed { to else ***
		createDeathNotification()
	end -- *** FIXED: Changed } to end ***
end)

RightButton.Activated:Connect(function()
	if not isPlayerDead then
		choosePath(DIRECTIONS.RIGHT)
	else -- *** FIXED: Changed { to else ***
		createDeathNotification()
	end -- *** FIXED: Changed } to end ***
end)

-- Remote event handlers
showPathSelectionEvent.OnClientEvent:Connect(showPathChoices)

updateTurnEvent.OnClientEvent:Connect(function(currentPlayerId)
	local isMyTurn = currentPlayerId == player.UserId

	if isMyTurn and not isPlayerDead then
		showDiceRollUI()
		canRoll = true
	else
		hideDiceRollUI()
		canRoll = false
	end -- *** FIXED: Changed } to end ***
end)

-- Receive dice bonus
diceBonusEvent.OnClientEvent:Connect(function(bonusAmount)
	activeDiceBonus = bonusAmount
	print("[DiceRollHandler] Received dice bonus: +" .. bonusAmount)

	-- Play notification sound
	local notificationSound = Instance.new("Sound")
	notificationSound.SoundId = "rbxassetid://6026984224"  -- Notification sound
	notificationSound.Volume = 0.5
	notificationSound.Parent = DiceRollUI
	notificationSound:Play()
	Debris:AddItem(notificationSound, 2) -- Use Debris service

	-- Create notification in top right
	createBonusNotification(bonusAmount)

	-- Update UI if DiceRollUI is visible
	if DiceRollUI.Visible then
		showDiceRollUI()
	end
end)

-- Handle fixed movement from crystal items
rollDiceEvent.OnClientEvent:Connect(function(fixedValue, isFixed)
	if isFixed then
		print("[DiceRollHandler] Received fixed movement: " .. fixedValue)
		isFixedMovement = true

		-- If it's our turn and we're allowed to roll
		if canRoll and not isPlayerDead then
			-- Use the fixed value (skip animation for crystals)
			animateDiceRoll(fixedValue, true)
		end -- *** FIXED: Changed } to end ***
	end -- *** FIXED: Changed } to end ***
	-- Normal dice rolls are handled by the button click
end)

-- Connect to the player respawn event
playerRespawnedEvent.OnClientEvent:Connect(onPlayerRespawn)

-- Listen for character death
player.CharacterAdded:Connect(function(character)
	local humanoid = character:WaitForChild("Humanoid")

	-- Connect to the Humanoid.Died event
	humanoid.Died:Connect(function()
		onPlayerDeath()
	end)
end)

-- Check if character already exists and connect
if player.Character then
	local humanoid = player.Character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			onPlayerDeath()
		end)
	end -- *** FIXED: Changed } to end ***
end -- *** FIXED: Changed } to end ***

-- Initial setup
DiceRollUI.Visible = false

-- Export the module for other scripts to use
local DiceRollHandler = {}
DiceRollHandler.ShowUI = showDiceRollUI
DiceRollHandler.HideUI = hideDiceRollUI
DiceRollHandler.SetDeathState = function(isDead)
	isPlayerDead = isDead
	if isDead then
		hideDiceRollUI()
		createDeathNotification()
	end -- *** FIXED: Changed } to end ***
end

-- Make accessible from other scripts
_G.DiceRollHandler = DiceRollHandler

return DiceRollHandler
