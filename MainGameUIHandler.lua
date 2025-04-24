-- MainGameUIHandler.lua
-- Handles main game UI updates, status bars, turn indicators, notifications, settings button, AutoRun toggle, and settings close button.
-- Version: 6.1.6 (Added SettingUI Close Button functionality)

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
local SettingUI = PopupUI:FindFirstChild("SettingsUIWorkspace") -- Assuming SettingUI is now in PopupUI
local NotificationSystem = PopupUI:WaitForChild("NotificationSystem", 10)
local NotificationTemplate = nil
local myStatusBar = nil -- Reference to the local player's status bar UI
local InventoryButton = MainGameUI:FindFirstChild("InventoryButton")
local QuestButton = MainGameUI:FindFirstChild("QuestButton")
local SettingButton = MainGameUI:FindFirstChild("SettingButton")
local CurrentTurnIndicator = MainGameUI:FindFirstChild("CurrentTurnIndicator")

-- Setting UI Elements
local SettingsUIWorkspace = SettingUI
local SettingsTitle = SettingsUIWorkspace and SettingsUIWorkspace:FindFirstChild("Title") -- ** เพิ่ม: อ้างอิง Title **
local SettingsCloseButton = SettingsTitle and SettingsTitle:FindFirstChild("CloseButton") -- ** เพิ่ม: อ้างอิง CloseButton ใน Title **
local EnableAutoRunToggle = SettingsUIWorkspace and SettingsUIWorkspace:FindFirstChild("EnableAutoRunToggle")
local AutoRunButton = EnableAutoRunToggle and EnableAutoRunToggle:FindFirstChild("Button")
local AutoRunLabel = EnableAutoRunToggle and EnableAutoRunToggle:FindFirstChild("Label")


-- Turn Indicator Components (Existing)
local TurnText = nil
local PlayerClassLabel = nil
local PlayerLevelLabel = nil
local TurnTimerFrame = nil
local TimerFill = nil
local TimerText = nil
local CombatTimerText = nil

if CurrentTurnIndicator then
	TurnText = CurrentTurnIndicator:FindFirstChild("TurnText")
	PlayerClassLabel = CurrentTurnIndicator:FindFirstChild("PlayerClassLabel")
	PlayerLevelLabel = CurrentTurnIndicator:FindFirstChild("PlayerLevelLabel")
	TurnTimerFrame = CurrentTurnIndicator:FindFirstChild("TurnTimerFrame")
	if TurnTimerFrame then
		TimerFill = TurnTimerFrame:FindFirstChild("TimerFill")
		TimerText = TurnTimerFrame:FindFirstChild("TimerText")
	end
	CombatTimerText = CurrentTurnIndicator:FindFirstChild("CombatTimerText")
	if not CombatTimerText and TurnText then
		CombatTimerText = TurnText:Clone()
		CombatTimerText.Name = "CombatTimerText"
		CombatTimerText.Text = "PRE-COMBAT: 120s"
		CombatTimerText.Visible = false
		CombatTimerText.Size = UDim2.new(1, 0, 0.5, 0)
		CombatTimerText.Position = UDim2.new(0.5, 0, 0.5, 0)
		CombatTimerText.AnchorPoint = Vector2.new(0.5, 0.5)
		CombatTimerText.Parent = CurrentTurnIndicator
	elseif CombatTimerText then
		CombatTimerText.Visible = false
	end
else
	warn("[MainGameUIHandler] CurrentTurnIndicator UI not found!")
end

-- Initialize Notification System (Existing)
if NotificationSystem then
	NotificationSystem.Visible = true
	NotificationTemplate = NotificationSystem:WaitForChild("Notification", 5)
	if NotificationTemplate then
		NotificationTemplate.Visible = false
	else
		warn("[Notification ERROR] Notification template not found in NotificationSystem!")
	end
else
	warn("[Notification ERROR] NotificationSystem not found in PopupUI!")
end

--[ Constants ]-- (Existing)
local CLASS_COLORS = { Warrior = Color3.fromRGB(220, 60, 60), Knight = Color3.fromRGB(180, 60, 60), Paladin = Color3.fromRGB(220, 100, 100), Mage = Color3.fromRGB(70, 100, 200), Wizard = Color3.fromRGB(50, 80, 180), Archmage = Color3.fromRGB(90, 120, 220), Thief = Color3.fromRGB(80, 180, 80), Assassin = Color3.fromRGB(60, 160, 60), Shadow = Color3.fromRGB(100, 200, 100), Default = Color3.fromRGB(150, 150, 150) }
local GOLD_COLOR = Color3.fromRGB(212, 175, 55)
local COMBAT_NOTIFICATION_ICON = "rbxassetid://5107144714"
local TOGGLE_ON_COLOR = Color3.fromRGB(70, 180, 70)
local TOGGLE_OFF_COLOR = Color3.fromRGB(180, 70, 70)

--[ State Variables ]-- (Existing)
local statusExpanded = true
local turnTimerActive = false
local turnTimerConnection = nil
local turnDetailsData = nil
local isMyTurn = false
local lastNotifiedTurnNumber = -1
local playerClassInfo = { class = nil, level = 1, classLevel = 1, exp = 0, classExp = 0, nextLevelExp = 100, nextClassLevelExp = 150 }
local currentPlayerStats = { hp = 100, maxHp = 100, mp = 50, maxMp = 50, attack = 10, defense = 10, magic = 10, magicDefense = 10, agility = 10, money = 100 }
local isCombatStateActive = false
local combatTimerEndTime = 0
local combatTimerConnection = nil
local isUIInteractionDisabled = false
local isAutoRunEnabled = false

--[ Remote Events ]-- (Existing)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local uiRemotes = remotes:WaitForChild("UIRemotes")
local gameRemotes = remotes:WaitForChild("GameRemotes")
local combatRemotes = remotes:WaitForChild("CombatRemotes")
local updatePlayerStatsEvent = uiRemotes:WaitForChild("UpdatePlayerStats")
local statChangedEvent = uiRemotes:FindFirstChild("StatChanged")
local updateExpEvent = uiRemotes:WaitForChild("UpdateExperience")
local levelUpEvent = uiRemotes:WaitForChild("LevelUp")
local classLevelUpEvent = uiRemotes:WaitForChild("ClassLevelUp")
local updateTurnEvent = gameRemotes:WaitForChild("UpdateTurn")
local updateTurnDetailsEvent = uiRemotes:FindFirstChild("UpdateTurnDetails")
local updateTurnTimerEvent = gameRemotes:WaitForChild("UpdateTurnTimer")
local endGameEvent = gameRemotes:WaitForChild("EndGame")
local setCombatStateEvent = combatRemotes:WaitForChild("SetCombatState")
local setAutoRunStateEvent = uiRemotes:FindFirstChild("SetAutoRunState") or Instance.new("RemoteEvent", uiRemotes); setAutoRunStateEvent.Name = "SetAutoRunState"
local autoRunStateChangedEvent = uiRemotes:FindFirstChild("AutoRunStateChanged") or Instance.new("RemoteEvent", uiRemotes); autoRunStateChangedEvent.Name = "AutoRunStateChanged"

-- Forward declare functions (Existing)
local updateMyStatusBar; local updateTurnIndicator; local updateTurnTimer; local setupPlayerStatusBar; local createNotification; local showLevelUpNotification; local showClassLevelUpNotification; local setupButtonHandlers; local handleCombatStateChange; local updateCombatTimer; local updateAutoRunToggleVisuals

--[ Helper Functions ]-- (Existing)
local function createTween(object, properties, duration, style, direction) local tweenInfo = TweenInfo.new(duration or 0.3, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out); return TweenService:Create(object, tweenInfo, properties) end
createNotification = function(text, iconId, duration) if not NotificationSystem or not NotificationTemplate then return nil end; local success, notificationClone = pcall(function() local clone = NotificationTemplate:Clone(); clone.Name = "ActiveNotification"; clone.Visible = true; clone.BackgroundTransparency = 1; clone.LayoutOrder = tick(); local textLabel = clone:FindFirstChild("NotificationText"); local iconImage = clone:FindFirstChild("NotificationIcon"); if textLabel and textLabel:IsA("TextLabel") then textLabel.Text = text end; if iconImage and iconImage:IsA("ImageLabel") then if iconId and string.find(iconId, "rbxassetid") then iconImage.Image = iconId; iconImage.Visible = true else iconImage.Visible = false end end; clone.Parent = NotificationSystem; local targetTransparency = 0.2; local fadeInTween = createTween(clone, {BackgroundTransparency = targetTransparency}, 0.4); fadeInTween:Play(); task.delay(duration or 3, function() if clone and clone.Parent then local fadeOutTween = createTween(clone, {BackgroundTransparency = 1}, 0.4); fadeOutTween:Play(); fadeOutTween.Completed:Connect(function() if clone and clone.Parent then clone:Destroy() end end) end end); return clone end); if not success then warn("[Notification ERROR] Failed to create notification:", notificationClone); return nil end; return notificationClone end

--[ Core UI Update Functions ]-- (Existing - No changes needed)
setupPlayerStatusBar = function() if not myStatusBar then myStatusBar = StatusBarContainer:FindFirstChild("MyPlayerStatusBar"); if not myStatusBar then warn("MyPlayerStatusBar not found in StatusBarContainer!") end end; return myStatusBar end
updateMyStatusBar = function(stats) if not myStatusBar then setupPlayerStatusBar(); if not myStatusBar then return end end; for key, value in pairs(stats) do if currentPlayerStats[key] ~= nil then currentPlayerStats[key] = value end end; if stats.level then playerClassInfo.level = stats.level end; if stats.class then playerClassInfo.class = stats.class end; if stats.exp then playerClassInfo.exp = stats.exp end; if stats.nextLevelExp then playerClassInfo.nextLevelExp = stats.nextLevelExp end; if myStatusBar:FindFirstChild("PlayerName") then myStatusBar.PlayerName.Text = player.Name end; if stats.level and myStatusBar:FindFirstChild("PlayerLevel") then (myStatusBar.PlayerLevel:FindFirstChild("LevelLabel") or myStatusBar.PlayerLevel).Text = "Lv." .. stats.level end; if stats.class and myStatusBar:FindFirstChild("PlayerClass") then myStatusBar.PlayerClass.Text = "Class: " .. stats.class end; if stats.hp and stats.maxHp and myStatusBar:FindFirstChild("HPBar") and myStatusBar.HPBar:FindFirstChild("HPFill") then local fill = myStatusBar.HPBar.HPFill; local textLabel = myStatusBar.HPBar:FindFirstChild("HPText"); local ratio = math.clamp(stats.hp / stats.maxHp, 0, 1); createTween(fill, {Size = UDim2.new(ratio, 0, 1, 0)}, 0.3, Enum.EasingStyle.Elastic):Play(); if textLabel then textLabel.Text = math.floor(stats.hp) .. "/" .. math.floor(stats.maxHp) end end; if stats.mp and stats.maxMp and myStatusBar:FindFirstChild("MPBar") and myStatusBar.MPBar:FindFirstChild("MPFill") then local fill = myStatusBar.MPBar.MPFill; local textLabel = myStatusBar.MPBar:FindFirstChild("MPText"); local ratio = math.clamp(stats.mp / stats.maxMp, 0, 1); createTween(fill, {Size = UDim2.new(ratio, 0, 1, 0)}, 0.3, Enum.EasingStyle.Elastic):Play(); if textLabel then textLabel.Text = math.floor(stats.mp) .. "/" .. math.floor(stats.maxMp) end end; if stats.money and myStatusBar:FindFirstChild("MoneyContainer") and myStatusBar.MoneyContainer:FindFirstChild("MoneyAmount") then local moneyLabel = myStatusBar.MoneyContainer.MoneyAmount; local currentMoney = tonumber(moneyLabel.Text) or 0; local newMoney = stats.money; if newMoney ~= currentMoney then local diff = newMoney - currentMoney; local direction = diff > 0 and 1 or -1; end; moneyLabel.Text = tostring(newMoney) end; local statList = {"defense", "attack", "mp", "magic"}; for _, statName in ipairs(statList) do local valueLabel = myStatusBar:FindFirstChild(string.upper(statName) .. "Value"); if stats[statName] and valueLabel then valueLabel.Text = tostring(stats[statName]) end end; if stats.defense and myStatusBar:FindFirstChild("DEFValue") then myStatusBar.DEFValue.Text = tostring(stats.defense) end; if stats.attack and myStatusBar:FindFirstChild("ATKValue") then myStatusBar.ATKValue.Text = tostring(stats.attack) end; if stats.mp and myStatusBar:FindFirstChild("MPValue") then myStatusBar.MPValue.Text = tostring(stats.mp) end; if stats.magic and myStatusBar:FindFirstChild("MAGValue") then myStatusBar.MAGValue.Text = tostring(stats.magic) end; local expBar = myStatusBar:FindFirstChild("ExpBar"); if expBar and expBar:FindFirstChild("ExpFill") then expBar.Visible = true; local expFill = expBar.ExpFill; local expText = expBar:FindFirstChild("ExpText"); local currentExp = stats.exp or playerClassInfo.exp or 0; local neededExp = stats.nextLevelExp or playerClassInfo.nextLevelExp or 100; if neededExp <= 0 then neededExp = 100 end; local ratio = math.clamp(currentExp / neededExp, 0, 1); createTween(expFill, {Size = UDim2.new(ratio, 0, 1, 0)}, 0.5):Play(); if expText then expText.Text = "EXP: " .. math.floor(currentExp) .. "/" .. math.floor(neededExp) end end end
updateTurnIndicator = function(turnDetails) if not turnDetails or turnDetails.playerId == nil then return end; if not CurrentTurnIndicator then return end; if isCombatStateActive then return end; local currentPlayerName = turnDetails.playerName or "Unknown"; local turnNumber = turnDetails.turnNumber or 1; local playerClass = turnDetails.playerClass or "Unknown"; local playerLevel = turnDetails.playerLevel or 1; local currentPlayerId = turnDetails.playerId; if TurnText then TurnText.Visible = true; TurnText.Text = currentPlayerName .. "'s Turn (Turn " .. turnNumber .. ")" end; if PlayerClassLabel then PlayerClassLabel.Visible = true; PlayerClassLabel.Text = "Class: " .. playerClass end; if PlayerLevelLabel then PlayerLevelLabel.Visible = true; PlayerLevelLabel.Text = "Lv." .. playerLevel end; if CombatTimerText then CombatTimerText.Visible = false end; if TurnTimerFrame then if turnTimerConnection then turnTimerConnection:Disconnect(); turnTimerConnection = nil end; TurnTimerFrame.Visible = true end; isMyTurn = (currentPlayerId == player.UserId); if isMyTurn then if myStatusBar then end; if turnNumber > lastNotifiedTurnNumber then lastNotifiedTurnNumber = turnNumber end; else end; turnDetailsData = turnDetails end
updateTurnTimer = function(timeRemaining) if not CurrentTurnIndicator or isCombatStateActive then return end; if not TurnTimerFrame then return end; if not TimerFill or not TimerText then return end; if type(timeRemaining) == "string" and timeRemaining == "Paused" then TimerText.Text = "Paused"; return elseif type(timeRemaining) ~= "number" then return end; TimerText.Text = tostring(timeRemaining) .. "s"; local maxTime = 60; local ratio = math.clamp(timeRemaining / maxTime, 0, 1); createTween(TimerFill, {Size = UDim2.new(ratio, 0, 1, 0)}, 0.3):Play(); if timeRemaining <= 15 then TimerFill.BackgroundColor3 = Color3.fromRGB(255, 50, 50) elseif timeRemaining <= 30 then TimerFill.BackgroundColor3 = Color3.fromRGB(255, 150, 50) else TimerFill.BackgroundColor3 = Color3.fromRGB(50, 200, 50) end end
updateCombatTimer = function() if not isCombatStateActive or not CombatTimerText then if combatTimerConnection then combatTimerConnection:Disconnect(); combatTimerConnection = nil end; return end; local timeRemaining = math.max(0, math.floor(combatTimerEndTime - tick())); CombatTimerText.Text = "COMBAT STARTING: " .. timeRemaining .. "s"; if timeRemaining <= 10 then CombatTimerText.TextColor3 = Color3.fromRGB(255, 80, 80) else CombatTimerText.TextColor3 = Color3.fromRGB(255, 255, 100) end; if timeRemaining <= 0 then if combatTimerConnection then combatTimerConnection:Disconnect(); combatTimerConnection = nil end end end
updateAutoRunToggleVisuals = function() if AutoRunButton and AutoRunLabel then if isAutoRunEnabled then AutoRunButton.BackgroundColor3 = TOGGLE_ON_COLOR; AutoRunLabel.Text = "AutoRun: ON"; AutoRunLabel.TextColor3 = TOGGLE_ON_COLOR else AutoRunButton.BackgroundColor3 = TOGGLE_OFF_COLOR; AutoRunLabel.Text = "AutoRun: OFF"; AutoRunLabel.TextColor3 = TOGGLE_OFF_COLOR end else warn("[MainGameUIHandler] AutoRun Toggle Button or Label not found in SettingUI!") end end

--[ Button Setup Functions ]-- (Modified)

setupButtonHandlers = function()
	-- Helper to connect main action buttons (Inventory, Quest, Setting) (Existing)
	local function setupActionButton(button, uiElement, otherUIElements)
		if button and not button:GetAttribute("Connected") then
			button.MouseButton1Click:Connect(function()
				if isUIInteractionDisabled then print("[UI DEBUG] UI interaction disabled (Combat Active). Button:", button.Name); createNotification("อยู่ในช่วง Combat ไม่สามารถกดได้", COMBAT_NOTIFICATION_ICON, 2); return end
				if uiElement then
					local shouldBeVisible = not uiElement.Visible; uiElement.Visible = shouldBeVisible; MainGameUI.Enabled = not shouldBeVisible
					if shouldBeVisible and otherUIElements then for _, otherUI in ipairs(otherUIElements) do if otherUI then otherUI.Visible = false end end end
					if InventoryButton then InventoryButton.BackgroundColor3 = InventoryUI and InventoryUI.Visible and TOGGLE_ON_COLOR or Color3.fromRGB(50,50,50) end
					if QuestButton then QuestButton.BackgroundColor3 = QuestUI and QuestUI.Visible and TOGGLE_ON_COLOR or Color3.fromRGB(50,50,50) end
					if SettingButton then SettingButton.BackgroundColor3 = SettingUI and SettingUI.Visible and TOGGLE_ON_COLOR or Color3.fromRGB(50,50,50) end
					if button == SettingButton and shouldBeVisible then updateAutoRunToggleVisuals() end
				elseif button == SettingButton then print("[MainGameUIHandler] SettingButton clicked! (SettingUI not found)"); createNotification("Setting UI is not implemented yet.", nil, 2) end
			end)
			button:SetAttribute("Connected", true)
		end
	end

	-- Helper to connect close buttons within popups (Existing)
	local function setupCloseButton(closeButton, uiElement, associatedButton)
		if uiElement and closeButton and not closeButton:GetAttribute("Connected") then
			closeButton.MouseButton1Click:Connect(function()
				uiElement.Visible = false
				if (not InventoryUI or not InventoryUI.Visible) and (not QuestUI or not QuestUI.Visible) and (not SettingUI or not SettingUI.Visible) then MainGameUI.Enabled = true end
				if associatedButton then associatedButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50) end
			end)
			closeButton:SetAttribute("Connected", true)
		end
	end

	-- Connect Inventory, Quest, and Setting buttons (Existing)
	setupActionButton(InventoryButton, InventoryUI, {QuestUI, SettingUI})
	setupActionButton(QuestButton, QuestUI, {InventoryUI, SettingUI})
	setupActionButton(SettingButton, SettingUI, {InventoryUI, QuestUI})

	-- Connect Close buttons (Modified)
	setupCloseButton(InventoryUI and InventoryUI:FindFirstChild("CloseButton"), InventoryUI, InventoryButton)
	setupCloseButton(QuestUI and QuestUI:FindFirstChild("CloseButton"), QuestUI, QuestButton)
	-- ** แก้ไข: ใช้ตัวแปร SettingsCloseButton ที่ประกาศไว้ด้านบน **
	setupCloseButton(SettingsCloseButton, SettingUI, SettingButton) -- ใช้ SettingsCloseButton ที่หาจาก Title

	-- Connect AutoRun Toggle Button (Existing)
	if AutoRunButton and not AutoRunButton:GetAttribute("Connected") then
		AutoRunButton.MouseButton1Click:Connect(function() isAutoRunEnabled = not isAutoRunEnabled; updateAutoRunToggleVisuals(); setAutoRunStateEvent:FireServer(isAutoRunEnabled); print("[MainGameUIHandler] AutoRun Toggled:", isAutoRunEnabled) end)
		AutoRunButton:SetAttribute("Connected", true)
	end

	-- Connect Status Bar Collapse/Expand button (Existing)
	local arrowButtonFrame = StatusBarContainer:FindFirstChild("ArrowButton"); if arrowButtonFrame then local arrowButton = arrowButtonFrame:FindFirstChild("Button"); if arrowButton and not arrowButton:GetAttribute("Connected") then arrowButton.MouseButton1Click:Connect(function() local playerStatusBar = StatusBarContainer:FindFirstChild("MyPlayerStatusBar"); if not playerStatusBar then return end; statusExpanded = not statusExpanded; local arrowIcon = arrowButtonFrame:FindFirstChild("ArrowIcon"); if statusExpanded then playerStatusBar.Visible = true; createTween(playerStatusBar, {Size = UDim2.new(1, 0, 1.4, 0)}, 0.4, Enum.EasingStyle.Back):Play(); if arrowIcon then arrowIcon.Text = "<" end else createTween(playerStatusBar, {Size = UDim2.new(1, 0, 0, 0)}, 0.3):Play(); task.delay(0.2, function() if not statusExpanded then playerStatusBar.Visible = false end end); if arrowIcon then arrowIcon.Text = ">" end end end); arrowButton:SetAttribute("Connected", true) end end
end

--[ Notification Functions ]-- (Existing - No changes)
showLevelUpNotification = function(newLevel, statIncreases) local statText = "LEVEL UP! Reached level " .. newLevel .. "!\n"; for stat, increase in pairs(statIncreases) do local statName = stat:gsub("Max", ""); if increase > 0 then statText = statText .. statName .. " +" .. increase .. " " end end; end
showClassLevelUpNotification = function(newClassLevel, statIncreases, nextClass) local message = "CLASS LEVEL UP! " .. (playerClassInfo.class or "Class") .. " reached level " .. newClassLevel .. "!"; if nextClass then message = message .. "\nUpgrade to " .. nextClass .. " is now available!" end; end

--[ Combat State Handling ]-- (Existing - No changes)
handleCombatStateChange = function(isActive, duration) print("[UI DEBUG] Received SetCombatState:", isActive, duration); isCombatStateActive = isActive; isUIInteractionDisabled = isActive; if not CurrentTurnIndicator then return end; if isActive then if TurnText then TurnText.Visible = false end; if PlayerClassLabel then PlayerClassLabel.Visible = false end; if PlayerLevelLabel then PlayerLevelLabel.Visible = false end; if TurnTimerFrame then TurnTimerFrame.Visible = false end; if CombatTimerText then CombatTimerText.Visible = true end; combatTimerEndTime = tick() + duration; if duration > 0 then if combatTimerConnection then combatTimerConnection:Disconnect() end; combatTimerConnection = RunService.Heartbeat:Connect(updateCombatTimer); updateCombatTimer() else if CombatTimerText then CombatTimerText.Text = "COMBAT ACTIVE" end end else isCombatStateActive = false; isUIInteractionDisabled = false; if combatTimerConnection then combatTimerConnection:Disconnect(); combatTimerConnection = nil end; if CombatTimerText then CombatTimerText.Visible = false end; if TurnText then TurnText.Visible = true end; if PlayerClassLabel then PlayerClassLabel.Visible = true end; if PlayerLevelLabel then PlayerLevelLabel.Visible = true end; if TurnTimerFrame then TurnTimerFrame.Visible = true end; if turnDetailsData then updateTurnIndicator(turnDetailsData) end; if turnTimerActive and updateTurnTimerEvent then print("[UI DEBUG] Combat ended, normal turn timer needs refresh (requesting might be needed).") end end end

--[ Remote Event Connections ]-- (Existing - No changes)
updatePlayerStatsEvent.OnClientEvent:Connect(function(playerId, stats) if playerId == player.UserId then updateMyStatusBar(stats) end end)
if statChangedEvent then statChangedEvent.OnClientEvent:Connect(function(changedStats) local statsToUpdate = {}; for stat, values in pairs(changedStats) do statsToUpdate[stat] = values.newValue; currentPlayerStats[stat] = values.newValue end; if statsToUpdate.hp and not statsToUpdate.maxHp then statsToUpdate.maxHp = currentPlayerStats.maxHp end; if statsToUpdate.mp and not statsToUpdate.maxMp then statsToUpdate.maxMp = currentPlayerStats.maxMp end; updateMyStatusBar(statsToUpdate) end) end
updateTurnEvent.OnClientEvent:Connect(function(currentPlayerId) local details = {playerId = currentPlayerId, playerName = "Unknown", turnNumber = (turnDetailsData and turnDetailsData.turnNumber or 0) + 1, playerClass = "Unknown", playerLevel = 1}; local foundPlayer = Players:GetPlayerByUserId(currentPlayerId); if foundPlayer then details.playerName = foundPlayer.Name end; updateTurnIndicator(details) end)
if updateTurnDetailsEvent then updateTurnDetailsEvent.OnClientEvent:Connect(updateTurnIndicator) end
if updateTurnTimerEvent then updateTurnTimerEvent.OnClientEvent:Connect(updateTurnTimer) end
if updateExpEvent then updateExpEvent.OnClientEvent:Connect(function(expData) if expData.exp ~= nil then playerClassInfo.exp = expData.exp end; if expData.nextLevelExp ~= nil then playerClassInfo.nextLevelExp = expData.nextLevelExp end; if expData.classExp ~= nil then playerClassInfo.classExp = expData.classExp end; if expData.nextClassLevelExp ~= nil then playerClassInfo.nextClassLevelExp = expData.nextClassLevelExp end; if expData.level ~= nil then playerClassInfo.level = expData.level end; updateMyStatusBar({exp = playerClassInfo.exp, nextLevelExp = playerClassInfo.nextLevelExp, level = playerClassInfo.level}) end) end
levelUpEvent.OnClientEvent:Connect(function(newLevel, statIncreases) playerClassInfo.level = newLevel; updateMyStatusBar({level = newLevel, exp = playerClassInfo.exp, nextLevelExp = playerClassInfo.nextLevelExp}); showLevelUpNotification(newLevel, statIncreases) end)
classLevelUpEvent.OnClientEvent:Connect(function(newClassLevel, statIncreases, nextClass) playerClassInfo.classLevel = newClassLevel; showClassLevelUpNotification(newClassLevel, statIncreases, nextClass) end)
endGameEvent.OnClientEvent:Connect(function(reason) local gameOverScreen = PlayerGui:FindFirstChild("GameOverScreen"); if gameOverScreen then gameOverScreen.Enabled = true; MainGameUI.Enabled = false; if PopupUI then PopupUI.Enabled = false end; local background = gameOverScreen:FindFirstChild("Background"); local announcement = background and background:FindFirstChild("WinnerAnnouncement"); if announcement then announcement.Text = reason end end end)
if setCombatStateEvent then setCombatStateEvent.OnClientEvent:Connect(handleCombatStateChange); print("[MainGameUIHandler] Connected to SetCombatState event.") else warn("[MainGameUIHandler] SetCombatState RemoteEvent not found in CombatRemotes!") end
autoRunStateChangedEvent.OnClientEvent:Connect(function(newState) if isAutoRunEnabled ~= newState then isAutoRunEnabled = newState; print("[MainGameUIHandler] AutoRun state updated from server:", isAutoRunEnabled); if SettingUI and SettingUI.Visible then updateAutoRunToggleVisuals() end end end)

--[ Initialization ]-- (Existing)
MainGameUI.Enabled = false; if PopupUI then PopupUI.Enabled = true; if InventoryUI then InventoryUI.Visible = false end; if QuestUI then QuestUI.Visible = false end; if SettingUI then SettingUI.Visible = false end end
setupPlayerStatusBar(); setupButtonHandlers(); updateAutoRunToggleVisuals()
MainGameUI:GetPropertyChangedSignal("Enabled"):Connect(function() if MainGameUI.Enabled then setupPlayerStatusBar(); if myStatusBar then updateMyStatusBar(currentPlayerStats) end end end)

print("[MainGameUIHandler] Initialized (v6.1.6) - Added SettingUI Close Button.")

