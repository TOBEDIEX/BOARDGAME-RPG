-- MainGameUIHandler.lua
-- Handles main game UI updates, status bars, turn indicators, and notifications.
-- Version: 6.1.3 (Fix MainGameUI not enabling after closing popup during combat)

--[ Services ]--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

--[ Local Player Setup ]--
local player = Players.LocalPlayer
if not player then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	player = Players.LocalPlayer
end

--[ UI Elements ]--
local PlayerGui = player:WaitForChild("PlayerGui")
local MainGameUI = PlayerGui:WaitForChild("MainGameUI")
local StatusBarContainer = MainGameUI:WaitForChild("StatusBarContainer")
local PopupUI = PlayerGui:WaitForChild("PopupUI")
local InventoryUI = PopupUI:FindFirstChild("InventoryUI")
local QuestUI = PopupUI:FindFirstChild("QuestUI")
local NotificationSystem = PopupUI:WaitForChild("NotificationSystem", 10)
local NotificationTemplate = nil
local myStatusBar = nil -- Reference to the local player's status bar UI
local InventoryButton = MainGameUI:FindFirstChild("InventoryButton")
local QuestButton = MainGameUI:FindFirstChild("QuestButton")
local CurrentTurnIndicator = MainGameUI:FindFirstChild("CurrentTurnIndicator")

-- Turn Indicator Components
local TurnText = nil
local PlayerClassLabel = nil
local PlayerLevelLabel = nil
local TurnTimerFrame = nil
local TimerFill = nil
local TimerText = nil
local CombatTimerText = nil -- Text label specifically for combat countdown

if CurrentTurnIndicator then
	TurnText = CurrentTurnIndicator:FindFirstChild("TurnText")
	PlayerClassLabel = CurrentTurnIndicator:FindFirstChild("PlayerClassLabel")
	PlayerLevelLabel = CurrentTurnIndicator:FindFirstChild("PlayerLevelLabel")
	TurnTimerFrame = CurrentTurnIndicator:FindFirstChild("TurnTimerFrame")
	if TurnTimerFrame then
		TimerFill = TurnTimerFrame:FindFirstChild("TimerFill")
		TimerText = TurnTimerFrame:FindFirstChild("TimerText")
	end
	-- Try to find or create the Combat Timer Text
	CombatTimerText = CurrentTurnIndicator:FindFirstChild("CombatTimerText")
	if not CombatTimerText and TurnText then -- Create if missing, clone from TurnText for style
		CombatTimerText = TurnText:Clone()
		CombatTimerText.Name = "CombatTimerText"
		CombatTimerText.Text = "PRE-COMBAT: 120s"
		CombatTimerText.Visible = false -- Start hidden
		CombatTimerText.Size = UDim2.new(1, 0, 0.5, 0) -- Adjust size/position as needed
		CombatTimerText.Position = UDim2.new(0.5, 0, 0.5, 0) -- Center it
		CombatTimerText.AnchorPoint = Vector2.new(0.5, 0.5)
		CombatTimerText.Parent = CurrentTurnIndicator
	elseif CombatTimerText then
		CombatTimerText.Visible = false -- Ensure it's hidden initially
	end

else
	warn("[MainGameUIHandler] CurrentTurnIndicator UI not found!")
end


-- Initialize Notification System
if NotificationSystem then
	NotificationSystem.Visible = true
	NotificationTemplate = NotificationSystem:WaitForChild("Notification", 5)
	if NotificationTemplate then
		NotificationTemplate.Visible = false -- Keep template hidden
	else
		warn("[Notification ERROR] Notification template not found in NotificationSystem!")
	end
else
	warn("[Notification ERROR] NotificationSystem not found in PopupUI!")
end

--[ Constants ]--
local CLASS_COLORS = {
	Warrior = Color3.fromRGB(220, 60, 60), Knight = Color3.fromRGB(180, 60, 60), Paladin = Color3.fromRGB(220, 100, 100),
	Mage = Color3.fromRGB(70, 100, 200), Wizard = Color3.fromRGB(50, 80, 180), Archmage = Color3.fromRGB(90, 120, 220),
	Thief = Color3.fromRGB(80, 180, 80), Assassin = Color3.fromRGB(60, 160, 60), Shadow = Color3.fromRGB(100, 200, 100),
	Default = Color3.fromRGB(150, 150, 150)
}
local GOLD_COLOR = Color3.fromRGB(212, 175, 55) -- Used for UI accents
local COMBAT_NOTIFICATION_ICON = "rbxassetid://5107144714" -- Warning/Stop Icon ID (Example)

--[ State Variables ]--
local statusExpanded = true -- Tracks if the player status bar is expanded
local turnTimerActive = false
local turnTimerConnection = nil
local turnDetailsData = nil
local isMyTurn = false
local lastNotifiedTurnNumber = -1
local playerClassInfo = { class = nil, level = 1, classLevel = 1, exp = 0, classExp = 0, nextLevelExp = 100, nextClassLevelExp = 150 }
local currentPlayerStats = { hp = 100, maxHp = 100, mp = 50, maxMp = 50, attack = 10, defense = 10, magic = 10, magicDefense = 10, agility = 10, money = 100 }
local isCombatStateActive = false -- Track combat state
local combatTimerEndTime = 0 -- Store end time for combat timer
local combatTimerConnection = nil -- Connection for combat timer loop
local isUIInteractionDisabled = false -- Flag used for logic checks (primarily for *opening* popups or specific actions)

--[ Remote Events ]--
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local uiRemotes = remotes:WaitForChild("UIRemotes")
local gameRemotes = remotes:WaitForChild("GameRemotes")
local combatRemotes = remotes:WaitForChild("CombatRemotes") -- Added CombatRemotes

-- UI Updates
local updatePlayerStatsEvent = uiRemotes:WaitForChild("UpdatePlayerStats")
local statChangedEvent = uiRemotes:FindFirstChild("StatChanged")
local updateExpEvent = uiRemotes:WaitForChild("UpdateExperience")
local levelUpEvent = uiRemotes:WaitForChild("LevelUp")
local classLevelUpEvent = uiRemotes:WaitForChild("ClassLevelUp")
-- Turn Management
local updateTurnEvent = gameRemotes:WaitForChild("UpdateTurn")
local updateTurnDetailsEvent = uiRemotes:FindFirstChild("UpdateTurnDetails")
local updateTurnTimerEvent = gameRemotes:WaitForChild("UpdateTurnTimer")
-- Game State
local endGameEvent = gameRemotes:WaitForChild("EndGame")
-- Combat State
local setCombatStateEvent = combatRemotes:WaitForChild("SetCombatState") -- Added SetCombatState

-- Forward declare functions that might be called before full definition (optional but good practice)
local updateMyStatusBar
local updateTurnIndicator
local updateTurnTimer
local setupPlayerStatusBar
local createNotification
local showLevelUpNotification
local showClassLevelUpNotification
local setupButtonHandlers
local handleCombatStateChange -- NEW
local updateCombatTimer -- NEW

--[ Helper Functions ]--

-- Creates a simple tween.
local function createTween(object, properties, duration, style, direction)
	local tweenInfo = TweenInfo.new(duration or 0.3, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	return TweenService:Create(object, tweenInfo, properties)
end

-- Creates and displays a notification using the existing UI template.
createNotification = function(text, iconId, duration)
	if not NotificationSystem or not NotificationTemplate then return nil end

	local success, notificationClone = pcall(function()
		local clone = NotificationTemplate:Clone()
		clone.Name = "ActiveNotification"
		clone.Visible = true
		clone.BackgroundTransparency = 1 -- Start transparent
		clone.LayoutOrder = tick() -- Ensure newest is positioned correctly by layout

		local textLabel = clone:FindFirstChild("NotificationText")
		local iconImage = clone:FindFirstChild("NotificationIcon")

		if textLabel and textLabel:IsA("TextLabel") then textLabel.Text = text end

		if iconImage and iconImage:IsA("ImageLabel") then
			if iconId and string.find(iconId, "rbxassetid") then
				iconImage.Image = iconId
				iconImage.Visible = true
			else
				iconImage.Visible = false -- Hide if no valid iconId
			end
		end

		clone.Parent = NotificationSystem -- Parent to the container with UIListLayout

		-- Fade In
		local targetTransparency = 0.2 -- Target visible transparency
		local fadeInTween = createTween(clone, {BackgroundTransparency = targetTransparency}, 0.4)
		fadeInTween:Play()

		-- Schedule Fade Out and Destroy
		task.delay(duration or 3, function()
			if clone and clone.Parent then
				local fadeOutTween = createTween(clone, {BackgroundTransparency = 1}, 0.4)
				fadeOutTween:Play()
				fadeOutTween.Completed:Connect(function()
					if clone and clone.Parent then clone:Destroy() end
				end)
			end
		end)
		return clone
	end)

	if not success then
		warn("[Notification ERROR] Failed to create notification:", notificationClone) -- Keep error warning
		return nil
	end
	return notificationClone
end

--[ Core UI Update Functions ]--

-- Finds the local player's status bar UI element.
setupPlayerStatusBar = function()
	if not myStatusBar then -- Only find it once
		myStatusBar = StatusBarContainer:FindFirstChild("MyPlayerStatusBar")
		if not myStatusBar then
			warn("MyPlayerStatusBar not found in StatusBarContainer!") -- Keep essential warning
		end
	end
	return myStatusBar
end

-- Updates the local player's status bar with new stats.
updateMyStatusBar = function(stats)
	if not myStatusBar then setupPlayerStatusBar(); if not myStatusBar then return end end -- Ensure status bar exists

	-- Update internal state
	for key, value in pairs(stats) do
		if currentPlayerStats[key] ~= nil then currentPlayerStats[key] = value end
	end
	if stats.level then playerClassInfo.level = stats.level end
	if stats.class then playerClassInfo.class = stats.class end
	if stats.exp then playerClassInfo.exp = stats.exp end
	if stats.nextLevelExp then playerClassInfo.nextLevelExp = stats.nextLevelExp end

	-- Update UI elements
	if myStatusBar:FindFirstChild("PlayerName") then myStatusBar.PlayerName.Text = player.Name end
	if stats.level and myStatusBar:FindFirstChild("PlayerLevel") then (myStatusBar.PlayerLevel:FindFirstChild("LevelLabel") or myStatusBar.PlayerLevel).Text = "Lv." .. stats.level end
	if stats.class and myStatusBar:FindFirstChild("PlayerClass") then myStatusBar.PlayerClass.Text = "Class: " .. stats.class; --[[ Update Bar Colors based on class ]] end

	-- Update HP Bar
	if stats.hp and stats.maxHp and myStatusBar:FindFirstChild("HPBar") and myStatusBar.HPBar:FindFirstChild("HPFill") then
		local fill = myStatusBar.HPBar.HPFill
		local textLabel = myStatusBar.HPBar:FindFirstChild("HPText")
		local ratio = math.clamp(stats.hp / stats.maxHp, 0, 1)
		createTween(fill, {Size = UDim2.new(ratio, 0, 1, 0)}, 0.3, Enum.EasingStyle.Elastic):Play()
		if textLabel then textLabel.Text = math.floor(stats.hp) .. "/" .. math.floor(stats.maxHp) end
		--[[ Update HP Bar Color based on class or ratio ]]
	end

	-- Update MP Bar
	if stats.mp and stats.maxMp and myStatusBar:FindFirstChild("MPBar") and myStatusBar.MPBar:FindFirstChild("MPFill") then
		local fill = myStatusBar.MPBar.MPFill
		local textLabel = myStatusBar.MPBar:FindFirstChild("MPText")
		local ratio = math.clamp(stats.mp / stats.maxMp, 0, 1)
		createTween(fill, {Size = UDim2.new(ratio, 0, 1, 0)}, 0.3, Enum.EasingStyle.Elastic):Play()
		if textLabel then textLabel.Text = math.floor(stats.mp) .. "/" .. math.floor(stats.maxMp) end
		--[[ Update MP Bar Color based on class ]]
	end

	-- Update Money Display & Notification
	if stats.money and myStatusBar:FindFirstChild("MoneyContainer") and myStatusBar.MoneyContainer:FindFirstChild("MoneyAmount") then
		local moneyLabel = myStatusBar.MoneyContainer.MoneyAmount
		local currentMoney = tonumber(moneyLabel.Text) or 0
		local newMoney = stats.money
		if newMoney ~= currentMoney then
			local diff = newMoney - currentMoney
			local direction = diff > 0 and 1 or -1
			--[[ Money change text animation ]]
			-- createNotification((direction > 0 and "+" or "") .. diff .. " coins", direction > 0 and "rbxassetid://GAIN_ID" or "rbxassetid://LOSS_ID", 2) -- Replace with actual IDs
		end
		moneyLabel.Text = tostring(newMoney)
	end

	-- Update Stat Texts (ATK, DEF, MAG, MP Value)
	local statList = {"defense", "attack", "mp", "magic"}
	for _, statName in ipairs(statList) do
		local valueLabel = myStatusBar:FindFirstChild(string.upper(statName) .. "Value")
		if stats[statName] and valueLabel then
			valueLabel.Text = tostring(stats[statName])
		end
	end
	-- Specific stat updates if names differ (e.g., DEFValue)
	if stats.defense and myStatusBar:FindFirstChild("DEFValue") then myStatusBar.DEFValue.Text = tostring(stats.defense) end
	if stats.attack and myStatusBar:FindFirstChild("ATKValue") then myStatusBar.ATKValue.Text = tostring(stats.attack) end
	if stats.mp and myStatusBar:FindFirstChild("MPValue") then myStatusBar.MPValue.Text = tostring(stats.mp) end
	if stats.magic and myStatusBar:FindFirstChild("MAGValue") then myStatusBar.MAGValue.Text = tostring(stats.magic) end

	-- Update EXP Bar - Fixed to properly handle all EXP updates
	local expBar = myStatusBar:FindFirstChild("ExpBar")
	if expBar and expBar:FindFirstChild("ExpFill") then
		-- Make sure ExpBar is visible
		expBar.Visible = true

		local expFill = expBar.ExpFill
		local expText = expBar:FindFirstChild("ExpText")

		-- Use either passed exp or stored exp values
		local currentExp = stats.exp or playerClassInfo.exp or 0
		local neededExp = stats.nextLevelExp or playerClassInfo.nextLevelExp or 100

		-- Make sure we don't divide by zero
		if neededExp <= 0 then neededExp = 100 end

		-- Calculate ratio and clamp it between 0 and 1
		local ratio = math.clamp(currentExp / neededExp, 0, 1)

		-- Update the fill
		createTween(expFill, {Size = UDim2.new(ratio, 0, 1, 0)}, 0.5):Play()

		-- Update the text if it exists
		if expText then
			expText.Text = "EXP: " .. math.floor(currentExp) .. "/" .. math.floor(neededExp)
		end
	else
		--warn("[UI DEBUG] ExpBar or ExpFill not found in status bar")
	end
end

-- Updates the turn indicator UI based on received turn details.
updateTurnIndicator = function(turnDetails)
	if not turnDetails or turnDetails.playerId == nil then return end -- Ensure valid data
	if not CurrentTurnIndicator then return end
	if isCombatStateActive then return end -- Don't update if combat is active

	local currentPlayerName = turnDetails.playerName or "Unknown"
	local turnNumber = turnDetails.turnNumber or 1
	local playerClass = turnDetails.playerClass or "Unknown"
	local playerLevel = turnDetails.playerLevel or 1
	local currentPlayerId = turnDetails.playerId

	-- Update Text Labels (only if not in combat)
	if TurnText then TurnText.Visible = true; TurnText.Text = currentPlayerName .. "'s Turn (Turn " .. turnNumber .. ")" end
	if PlayerClassLabel then PlayerClassLabel.Visible = true; PlayerClassLabel.Text = "Class: " .. playerClass end
	if PlayerLevelLabel then PlayerLevelLabel.Visible = true; PlayerLevelLabel.Text = "Lv." .. playerLevel end
	if CombatTimerText then CombatTimerText.Visible = false end -- Hide combat timer text

	-- Handle Timer Frame Visibility
	if TurnTimerFrame then
		if turnTimerConnection then turnTimerConnection:Disconnect(); turnTimerConnection = nil end
		TurnTimerFrame.Visible = true -- Assuming timer starts with turn
	end

	-- Check if it's the local player's turn
	isMyTurn = (currentPlayerId == player.UserId)

	if isMyTurn then
		-- Highlight Player's UI (e.g., status bar border)
		if myStatusBar then
			--[[ Add highlight effect, e.g., tweening UIStroke Color/Thickness ]]
		end

		-- Notify Player (only once per turn number)
		if turnNumber > lastNotifiedTurnNumber then
			-- createNotification("It's your turn!", "rbxassetid://YOUR_TURN_ICON_ID", 2) -- Replace with actual ID
			lastNotifiedTurnNumber = turnNumber
		end

		-- Animate Turn Indicator (Optional visual cue)
		--[[ Add tweening for size/color change ]]
	else
		-- Reset Turn Indicator style if needed
		-- CurrentTurnIndicator.BackgroundColor3 = Color3.fromRGB(80, 80, 100) -- Example reset
	end

	turnDetailsData = turnDetails -- Store latest details
end

-- Updates the turn timer UI.
updateTurnTimer = function(timeRemaining)
	if not CurrentTurnIndicator or isCombatStateActive then return end -- Don't update if combat active
	if not TurnTimerFrame then return end
	if not TimerFill or not TimerText then return end

	-- Handle "Paused" state from TurnSystem
	if type(timeRemaining) == "string" and timeRemaining == "Paused" then
		TimerText.Text = "Paused"
		-- Optionally change fill color or appearance for paused state
		-- TimerFill.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
		return -- Stop further processing for paused state
	elseif type(timeRemaining) ~= "number" then
		return -- Ignore invalid time values
	end

	TimerText.Text = tostring(timeRemaining) .. "s"
	local maxTime = 60 -- Assuming max turn time from TurnSystem constant
	local ratio = math.clamp(timeRemaining / maxTime, 0, 1)
	createTween(TimerFill, {Size = UDim2.new(ratio, 0, 1, 0)}, 0.3):Play()

	-- Change timer color based on time left
	if timeRemaining <= 15 then TimerFill.BackgroundColor3 = Color3.fromRGB(255, 50, 50) -- Use INACTIVITY_WARNING_TIME
	elseif timeRemaining <= 30 then TimerFill.BackgroundColor3 = Color3.fromRGB(255, 150, 50)
	else TimerFill.BackgroundColor3 = Color3.fromRGB(50, 200, 50) end
end

-- NEW: Updates the combat timer UI.
updateCombatTimer = function()
	if not isCombatStateActive or not CombatTimerText then
		if combatTimerConnection then combatTimerConnection:Disconnect(); combatTimerConnection = nil end
		return
	end

	local timeRemaining = math.max(0, math.floor(combatTimerEndTime - tick()))
	CombatTimerText.Text = "COMBAT STARTING: " .. timeRemaining .. "s"

	-- Optionally add visual cues like color change when time is low
	if timeRemaining <= 10 then
		CombatTimerText.TextColor3 = Color3.fromRGB(255, 80, 80)
	else
		CombatTimerText.TextColor3 = Color3.fromRGB(255, 255, 100) -- Yellowish for combat
	end

	if timeRemaining <= 0 then
		if combatTimerConnection then combatTimerConnection:Disconnect(); combatTimerConnection = nil end
		-- Server will handle the actual end state via SetCombatState(false)
	end
end

--[ Button Setup Functions ]--

-- Sets up common button handlers for Inventory, Quest, Close buttons, etc.
setupButtonHandlers = function()
	-- Helper to connect main action buttons (Inventory, Quest)
	local function setupActionButton(button, uiElement, otherUIElement)
		if button and not button:GetAttribute("Connected") then
			button.MouseButton1Click:Connect(function()
				-- Check if UI interaction is disabled (Combat Active)
				if isUIInteractionDisabled then
					print("[UI DEBUG] UI interaction disabled (Combat Active). Button:", button.Name)
					-- Show notification instead of doing nothing
					createNotification("อยู่ในช่วง Combat ไม่สามารถกดได้", COMBAT_NOTIFICATION_ICON, 2)
					return -- Prevent opening the UI
				end

				-- Original logic to open UI
				if uiElement then
					local shouldBeVisible = not uiElement.Visible
					uiElement.Visible = shouldBeVisible
					MainGameUI.Enabled = not shouldBeVisible -- Hide main game UI when popup is open

					-- Close other popup if opening this one
					if shouldBeVisible and otherUIElement then
						otherUIElement.Visible = false
					end
					-- Update button colors after state change
					if InventoryButton then InventoryButton.BackgroundColor3 = InventoryUI and InventoryUI.Visible and Color3.fromRGB(80,120,80) or Color3.fromRGB(50,50,50) end
					if QuestButton then QuestButton.BackgroundColor3 = QuestUI and QuestUI.Visible and Color3.fromRGB(80,120,80) or Color3.fromRGB(50,50,50) end
				end
			end)
			button:SetAttribute("Connected", true)
		end
	end

	-- Helper to connect close buttons within popups
	local function setupCloseButton(closeButton, uiElement, associatedButton)
		if uiElement and closeButton and not closeButton:GetAttribute("Connected") then
			closeButton.MouseButton1Click:Connect(function()
				uiElement.Visible = false
				--[[ *** MODIFIED LOGIC START *** ]]
				-- Re-enable MainGameUI IF no other popups are currently visible.
				-- The combat state (isUIInteractionDisabled) should NOT prevent this.
				if (not InventoryUI or not InventoryUI.Visible) and (not QuestUI or not QuestUI.Visible) then
					MainGameUI.Enabled = true -- Re-enable the main UI regardless of combat state
				end
				--[[ *** MODIFIED LOGIC END *** ]]

				-- Reset associated button color
				if associatedButton then associatedButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50) end
			end)
			closeButton:SetAttribute("Connected", true)
		end
	end

	-- Connect Inventory and Quest buttons
	setupActionButton(InventoryButton, InventoryUI, QuestUI)
	setupActionButton(QuestButton, QuestUI, InventoryUI)

	-- Connect Close buttons (assuming they exist within the respective UI frames)
	setupCloseButton(InventoryUI and InventoryUI:FindFirstChild("CloseButton"), InventoryUI, InventoryButton)
	setupCloseButton(QuestUI and QuestUI:FindFirstChild("CloseButton"), QuestUI, QuestButton)

	-- Connect Status Bar Collapse/Expand button
	local arrowButtonFrame = StatusBarContainer:FindFirstChild("ArrowButton")
	if arrowButtonFrame then
		local arrowButton = arrowButtonFrame:FindFirstChild("Button")
		if arrowButton and not arrowButton:GetAttribute("Connected") then
			arrowButton.MouseButton1Click:Connect(function()
				-- Allow status bar interaction even during combat
				local playerStatusBar = StatusBarContainer:FindFirstChild("MyPlayerStatusBar")
				if not playerStatusBar then return end
				statusExpanded = not statusExpanded
				local arrowIcon = arrowButtonFrame:FindFirstChild("ArrowIcon") -- Assuming icon is sibling of button

				if statusExpanded then
					playerStatusBar.Visible = true
					createTween(playerStatusBar, {Size = UDim2.new(1, 0, 1.4, 0)}, 0.4, Enum.EasingStyle.Back):Play()
					if arrowIcon then arrowIcon.Text = "<" end -- Or adjust rotation/image
				else
					createTween(playerStatusBar, {Size = UDim2.new(1, 0, 0, 0)}, 0.3):Play()
					task.delay(0.2, function() if not statusExpanded then playerStatusBar.Visible = false end end) -- Hide after tween if still collapsed
					if arrowIcon then arrowIcon.Text = ">" end -- Or adjust rotation/image
				end
			end)
			arrowButton:SetAttribute("Connected", true)
		end
	end
end

--[ Notification Functions ]--

-- Shows a level up notification.
showLevelUpNotification = function(newLevel, statIncreases)
	local statText = "LEVEL UP! Reached level " .. newLevel .. "!\n"
	for stat, increase in pairs(statIncreases) do
		local statName = stat:gsub("Max", "") -- e.g., MaxHP -> HP
		if increase > 0 then
			statText = statText .. statName .. " +" .. increase .. " "
		end
	end
	-- createNotification(statText, "rbxassetid://YOUR_LEVELUP_ICON_ID", 5) -- Replace with actual ID
end

-- Shows a class level up notification.
showClassLevelUpNotification = function(newClassLevel, statIncreases, nextClass)
	local message = "CLASS LEVEL UP! " .. (playerClassInfo.class or "Class") .. " reached level " .. newClassLevel .. "!"
	if nextClass then
		message = message .. "\nUpgrade to " .. nextClass .. " is now available!"
	end
	-- createNotification(message, "rbxassetid://YOUR_CLASS_UP_ICON_ID", 5) -- Replace with actual ID
end

--[ Combat State Handling ]--

-- NEW: Handles changes in combat state
handleCombatStateChange = function(isActive, duration)
	print("[UI DEBUG] Received SetCombatState:", isActive, duration)
	isCombatStateActive = isActive
	isUIInteractionDisabled = isActive -- Link UI interaction state (used for *opening* popups) to combat state

	-- REMOVED: Direct enabling/disabling of MainGameUI or Buttons based on combat state.
	-- Interaction logic is now handled within individual button clicks (setupActionButton)
	-- and the close button logic (setupCloseButton) ensures MainGameUI is re-enabled correctly.

	if not CurrentTurnIndicator then return end

	if isActive then
		-- Enter Combat State
		if TurnText then TurnText.Visible = false end
		if PlayerClassLabel then PlayerClassLabel.Visible = false end
		if PlayerLevelLabel then PlayerLevelLabel.Visible = false end
		if TurnTimerFrame then TurnTimerFrame.Visible = false end -- Hide normal turn timer
		if CombatTimerText then CombatTimerText.Visible = true end

		combatTimerEndTime = tick() + duration

		-- Start the combat timer update loop if duration > 0
		if duration > 0 then
			if combatTimerConnection then combatTimerConnection:Disconnect() end -- Stop previous if any
			combatTimerConnection = RunService.Heartbeat:Connect(updateCombatTimer)
			updateCombatTimer() -- Initial update
		else
			-- If duration is 0, just show "COMBAT ACTIVE" or similar
			if CombatTimerText then CombatTimerText.Text = "COMBAT ACTIVE" end
		end

	else
		-- Exit Combat State
		isCombatStateActive = false
		isUIInteractionDisabled = false -- Allow opening popups again
		if combatTimerConnection then combatTimerConnection:Disconnect(); combatTimerConnection = nil end

		if CombatTimerText then CombatTimerText.Visible = false end
		-- Restore normal turn indicator elements (visibility will be handled by updateTurnIndicator)
		if TurnText then TurnText.Visible = true end
		if PlayerClassLabel then PlayerClassLabel.Visible = true end
		if PlayerLevelLabel then PlayerLevelLabel.Visible = true end
		if TurnTimerFrame then TurnTimerFrame.Visible = true end -- Show normal timer frame again

		-- Refresh the turn indicator with the last known details
		if turnDetailsData then
			updateTurnIndicator(turnDetailsData)
		end
		-- Refresh the normal turn timer if it was active
		if turnTimerActive and updateTurnTimerEvent then
			print("[UI DEBUG] Combat ended, normal turn timer needs refresh (requesting might be needed).")
		end
	end
end


--[ Remote Event Connections ]--

updatePlayerStatsEvent.OnClientEvent:Connect(function(playerId, stats)
	if playerId == player.UserId then
		updateMyStatusBar(stats)
	end
end)

if statChangedEvent then
	statChangedEvent.OnClientEvent:Connect(function(changedStats)
		local statsToUpdate = {}
		for stat, values in pairs(changedStats) do
			statsToUpdate[stat] = values.newValue
			currentPlayerStats[stat] = values.newValue
		end
		if statsToUpdate.hp and not statsToUpdate.maxHp then statsToUpdate.maxHp = currentPlayerStats.maxHp end
		if statsToUpdate.mp and not statsToUpdate.maxMp then statsToUpdate.maxMp = currentPlayerStats.maxMp end
		updateMyStatusBar(statsToUpdate)
	end)
end

updateTurnEvent.OnClientEvent:Connect(function(currentPlayerId)
	local details = {
		playerId = currentPlayerId,
		playerName = "Unknown",
		turnNumber = (turnDetailsData and turnDetailsData.turnNumber or 0) + 1,
		playerClass = "Unknown",
		playerLevel = 1
	}
	local foundPlayer = Players:GetPlayerByUserId(currentPlayerId)
	if foundPlayer then details.playerName = foundPlayer.Name end
	updateTurnIndicator(details)
end)

if updateTurnDetailsEvent then
	updateTurnDetailsEvent.OnClientEvent:Connect(updateTurnIndicator)
end

if updateTurnTimerEvent then
	updateTurnTimerEvent.OnClientEvent:Connect(updateTurnTimer)
end

if updateExpEvent then
	updateExpEvent.OnClientEvent:Connect(function(expData)
		if expData.exp ~= nil then playerClassInfo.exp = expData.exp end
		if expData.nextLevelExp ~= nil then playerClassInfo.nextLevelExp = expData.nextLevelExp end
		if expData.classExp ~= nil then playerClassInfo.classExp = expData.classExp end
		if expData.nextClassLevelExp ~= nil then playerClassInfo.nextClassLevelExp = expData.nextClassLevelExp end
		if expData.level ~= nil then playerClassInfo.level = expData.level end
		updateMyStatusBar({
			exp = playerClassInfo.exp,
			nextLevelExp = playerClassInfo.nextLevelExp,
			level = playerClassInfo.level
		})
	end)
end

levelUpEvent.OnClientEvent:Connect(function(newLevel, statIncreases)
	playerClassInfo.level = newLevel
	updateMyStatusBar({
		level = newLevel,
		exp = playerClassInfo.exp,
		nextLevelExp = playerClassInfo.nextLevelExp
	})
	showLevelUpNotification(newLevel, statIncreases)
end)

classLevelUpEvent.OnClientEvent:Connect(function(newClassLevel, statIncreases, nextClass)
	playerClassInfo.classLevel = newClassLevel
	showClassLevelUpNotification(newClassLevel, statIncreases, nextClass)
end)

endGameEvent.OnClientEvent:Connect(function(reason)
	local gameOverScreen = PlayerGui:FindFirstChild("GameOverScreen")
	if gameOverScreen then
		gameOverScreen.Enabled = true
		MainGameUI.Enabled = false
		if PopupUI then PopupUI.Enabled = false end
		local background = gameOverScreen:FindFirstChild("Background")
		local announcement = background and background:FindFirstChild("WinnerAnnouncement")
		if announcement then announcement.Text = reason end
	end
end)

if setCombatStateEvent then
	setCombatStateEvent.OnClientEvent:Connect(handleCombatStateChange)
	print("[MainGameUIHandler] Connected to SetCombatState event.")
else
	warn("[MainGameUIHandler] SetCombatState RemoteEvent not found in CombatRemotes!")
end

--[ Initialization ]--

MainGameUI.Enabled = false -- Start disabled, enabled by game state manager
if PopupUI then
	PopupUI.Enabled = true
	if InventoryUI then InventoryUI.Visible = false end
	if QuestUI then QuestUI.Visible = false end
end

setupPlayerStatusBar()
setupButtonHandlers()

MainGameUI:GetPropertyChangedSignal("Enabled"):Connect(function()
	if MainGameUI.Enabled then
		setupPlayerStatusBar()
		if myStatusBar then
			updateMyStatusBar(currentPlayerStats)
		end
	end
end)

print("[MainGameUIHandler] Initialized (v6.1.3) - Fixed close button logic during combat.")
