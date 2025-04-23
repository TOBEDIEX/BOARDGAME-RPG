-- DiceRollHandler.lua
-- Manages dice roll interface and path selection
-- Version: 2.8.1 (Fixed UI Re-enabling after Combat)

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
local combatRemotes = remotes:WaitForChild("CombatRemotes") -- Added CombatRemotes

-- Get remote events
local rollDiceEvent = boardRemotes:WaitForChild("RollDice")
local showPathSelectionEvent = boardRemotes:WaitForChild("ShowPathSelection")
local choosePathEvent = boardRemotes:WaitForChild("ChoosePath")
local updateTurnEvent = gameRemotes:WaitForChild("UpdateTurn")
local setSystemEnabledEvent = combatRemotes:WaitForChild("SetSystemEnabled") -- Added SetSystemEnabled

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
local canRoll = false -- Tracks if the player *can* roll (is their turn, not dead, not disabled)
local isMyTurn = false -- NEW: Track if it's currently the local player's turn
local currentDiceResult = nil
local currentPathChoices = nil
local remainingSteps = 0
local activeDiceBonus = 0
local bonusDiceResults = {}
local isFixedMovement = false -- Flag for fixed movement crystals
local isPlayerDead = false -- Track player death state
local isSystemDisabled = false -- Flag to disable system during combat

-- Create bonus dice function (No changes needed)
local function createBonusDice(numBonusDice)
	-- ... (โค้ดเดิม)
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

	--print("Creating " .. numBonusDice .. " bonus dice")

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

-- Create total result display above main dice (No changes needed)
local function createTotalResult(total)
	-- ... (โค้ดเดิม)
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

-- Create dice bonus notification in top right (No changes needed)
local function createBonusNotification(bonusAmount)
	-- ... (โค้ดเดิม)
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

-- Create fixed movement notification (No changes needed)
local function createFixedMovementNotification(moveAmount)
	-- ... (โค้ดเดิม)
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

-- Create notification for when player is dead (No changes needed)
local function createDeathNotification()
	-- ... (โค้ดเดิม)
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
	-- Don't show if player is dead or system is disabled
	if isPlayerDead then
		createDeathNotification()
		return
	end
	if isSystemDisabled then -- Check if disabled by combat
		print("[DiceRollHandler] System is disabled, cannot show UI.")
		hideDiceRollUI() -- Ensure it's hidden if disabled
		return
	end

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
	-- Don't reset canRoll here, let updateTurnEvent handle it
	isFixedMovement = false -- Reset fixed movement flag
end

-- Animate dice roll (No changes needed)
local function animateDiceRoll(finalResult, skipAnimation)
	-- ... (โค้ดเดิม)
	-- Don't roll if player is dead or system disabled
	if isPlayerDead then createDeathNotification(); return end
	if isSystemDisabled then print("[DiceRollHandler] System disabled, cannot roll dice."); return end

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
		rollDiceEvent:FireServer(finalResult, true) -- Send isFixed=true for server logic

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
	--print("=== DICE ROLL RESULT ===")
	--print("Main dice: " .. mainDiceResult)
	--print("Bonus dice: " .. table.concat(allDiceResults.bonus, ", "))
	--print("Total result: " .. totalResult)
	--print("======================")

	task.wait(0.3) -- Use task.wait

	-- Send result to server (isFixed is false for normal rolls)
	rollDiceEvent:FireServer(totalResult, false)

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

-- Show path choices (No changes needed)
local function showPathChoices(choices)
	-- ... (โค้ดเดิม)
	-- Don't show if player is dead or system disabled
	if isPlayerDead then createDeathNotification(); return end
	if isSystemDisabled then print("[DiceRollHandler] System disabled, cannot show path choices."); return end

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

-- Choose path direction (No changes needed)
local function choosePath(direction)
	-- ... (โค้ดเดิม)
	-- Don't process if player is dead or system disabled
	if isPlayerDead then createDeathNotification(); return end
	if isSystemDisabled then print("[DiceRollHandler] System disabled, cannot choose path."); return end

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

-- Function to handle player death (No changes needed)
local function onPlayerDeath()
	-- ... (โค้ดเดิม)
	print("[DiceRollHandler] Player has died")
	isPlayerDead = true

	-- Hide all dice UI elements
	hideDiceRollUI()

	-- Show death notification
	createDeathNotification()
end

-- Function to handle player respawn (No changes needed)
local function onPlayerRespawn(respawnData)
	-- ... (โค้ดเดิม)
	print("[DiceRollHandler] Player has respawned")
	isPlayerDead = false
	isSystemDisabled = false -- Re-enable system on respawn

	-- Remove death notification
	local deathNotification = PlayerGui:FindFirstChild("DeathNotification")
	if deathNotification then
		deathNotification:Destroy()
	end

	-- Reset UI state
	isRolling = false
	canRoll = false
	currentDiceResult = nil
	currentPathChoices = nil
	remainingSteps = 0
	isFixedMovement = false
	activeDiceBonus = 0

	print("[DiceRollHandler] Dice system reset after respawn")
end

-- Button event handlers (No changes needed)
RollButton.Activated:Connect(function()
	-- ... (โค้ดเดิม)
	if isPlayerDead then createDeathNotification(); return end
	if isSystemDisabled then print("[DiceRollHandler] Cannot roll, system disabled."); return end

	if not isRolling and canRoll then
		local diceResult = math.random(1, 6)
		animateDiceRoll(diceResult)
	end
end)

ForwardButton.Activated:Connect(function()
	-- ... (โค้ดเดิม)
	if not isPlayerDead and not isSystemDisabled then
		choosePath(DIRECTIONS.FRONT)
	elseif isPlayerDead then
		createDeathNotification()
	else
		print("[DiceRollHandler] Cannot choose path, system disabled.")
	end
end)

LeftButton.Activated:Connect(function()
	-- ... (โค้ดเดิม)
	if not isPlayerDead and not isSystemDisabled then
		choosePath(DIRECTIONS.LEFT)
	elseif isPlayerDead then
		createDeathNotification()
	else
		print("[DiceRollHandler] Cannot choose path, system disabled.")
	end
end)

RightButton.Activated:Connect(function()
	-- ... (โค้ดเดิม)
	if not isPlayerDead and not isSystemDisabled then
		choosePath(DIRECTIONS.RIGHT)
	elseif isPlayerDead then
		createDeathNotification()
	else
		print("[DiceRollHandler] Cannot choose path, system disabled.")
	end
end)

-- Remote event handlers
showPathSelectionEvent.OnClientEvent:Connect(showPathChoices)

updateTurnEvent.OnClientEvent:Connect(function(currentPlayerId)
	isMyTurn = (currentPlayerId == player.UserId) -- Update isMyTurn state

	if isMyTurn and not isPlayerDead and not isSystemDisabled then -- Check disabled flag
		showDiceRollUI()
		canRoll = true
	else
		hideDiceRollUI()
		canRoll = false
	end
end)

-- Receive dice bonus (No changes needed)
diceBonusEvent.OnClientEvent:Connect(function(bonusAmount)
	-- ... (โค้ดเดิม)
	activeDiceBonus = bonusAmount
	--print("[DiceRollHandler] Received dice bonus: +" .. bonusAmount)

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

-- Handle fixed movement from crystal items (No changes needed)
rollDiceEvent.OnClientEvent:Connect(function(fixedValue, isFixed)
	-- ... (โค้ดเดิม)
	if isFixed then
		print("[DiceRollHandler] Received fixed movement: " .. fixedValue)
		isFixedMovement = true

		-- If it's our turn and we're allowed to roll (and not dead/disabled)
		if canRoll and not isPlayerDead and not isSystemDisabled then
			-- Use the fixed value (skip animation for crystals)
			animateDiceRoll(fixedValue, true)
		end
	end
	-- Normal dice rolls are handled by the button click
end)

-- Connect to the player respawn event (No changes needed)
playerRespawnedEvent.OnClientEvent:Connect(onPlayerRespawn)

-- Connect to the system enable/disable event
if setSystemEnabledEvent then
	setSystemEnabledEvent.OnClientEvent:Connect(function(systemName, enabled)
		if systemName == "DiceRollHandler" then
			print("[DiceRollHandler] Received SetSystemEnabled:", enabled)
			isSystemDisabled = not enabled -- Set the disabled flag

			if isSystemDisabled then
				hideDiceRollUI() -- Immediately hide UI if disabled
				canRoll = false -- Prevent rolling
			else
				-- *** NEW: Re-enable UI immediately if conditions met ***
				if isMyTurn and not isPlayerDead then
					print("[DiceRollHandler] System re-enabled, showing UI because it's my turn.")
					showDiceRollUI()
					canRoll = true
				else
					print("[DiceRollHandler] System re-enabled, but not showing UI (not my turn or dead).")
					canRoll = false -- Ensure canRoll is false if not showing UI
				end
			end
		end
	end)
	print("[DiceRollHandler] Connected to SetSystemEnabled event.")
else
	warn("[DiceRollHandler] SetSystemEnabled RemoteEvent not found in CombatRemotes!")
end


-- Listen for character death (No changes needed)
player.CharacterAdded:Connect(function(character)
	-- ... (โค้ดเดิม)
	local humanoid = character:WaitForChild("Humanoid")

	-- Connect to the Humanoid.Died event
	humanoid.Died:Connect(function()
		onPlayerDeath()
	end)
end)

-- Check if character already exists and connect (No changes needed)
if player.Character then
	-- ... (โค้ดเดิม)
	local humanoid = player.Character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			onPlayerDeath()
		end)
	end
end

-- Initial setup
DiceRollUI.Visible = false

-- Export the module for other scripts to use (No changes needed)
local DiceRollHandler = {}
-- ... (โค้ดเดิม)
DiceRollHandler.ShowUI = showDiceRollUI
DiceRollHandler.HideUI = hideDiceRollUI
DiceRollHandler.SetDeathState = function(isDead)
	isPlayerDead = isDead
	if isDead then
		hideDiceRollUI()
		createDeathNotification()
	end
end
-- Expose enable/disable for external control if needed (e.g., from CombatController)
DiceRollHandler.SetEnabled = function(enabled)
	print("[DiceRollHandler] SetEnabled called:", enabled)
	isSystemDisabled = not enabled
	if isSystemDisabled then
		hideDiceRollUI()
		canRoll = false
	else
		-- Re-check conditions when manually enabled
		if isMyTurn and not isPlayerDead then
			showDiceRollUI()
			canRoll = true
		else
			canRoll = false
		end
	end
end


-- Make accessible from other scripts
_G.DiceRollHandler = DiceRollHandler

return DiceRollHandler
