-- TurnIndicatorHandler.lua
-- จัดการ UI แสดงเทิร์นปัจจุบัน
-- Version: 1.1.0 (เพิ่มการแสดงสถานะคูลดาวน์การต่อสู้)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Debug mode
local DEBUG_MODE = false

-- Debug helper function
local function debugLog(message)
	if DEBUG_MODE then
		print("[TurnIndicatorHandler] " .. message)
	end
end

-- Get current player
local player = Players.LocalPlayer
if not player then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	player = Players.LocalPlayer
end

-- Get UI elements
local PlayerGui = player:WaitForChild("PlayerGui")
local MainGameUI = PlayerGui:WaitForChild("MainGameUI")
local CurrentTurnIndicator = MainGameUI:FindFirstChild("CurrentTurnIndicator")

-- ถ้าไม่พบ TurnIndicator ให้สร้างจากฟังก์ชันที่มีให้
if not CurrentTurnIndicator then
	debugLog("Turn Indicator not found, creating new one")

	-- Import TurnIndicator module
	local TurnIndicator = require(script.Parent.UI.TurnIndicator)
	CurrentTurnIndicator = TurnIndicator(MainGameUI)

	if not CurrentTurnIndicator then
		warn("Failed to create Turn Indicator UI")
		return
	end
end

-- Make sure we have key UI components
local TurnText = CurrentTurnIndicator:FindFirstChild("TurnText")
local PlayerClassLabel = CurrentTurnIndicator:FindFirstChild("PlayerClassLabel")
local PlayerLevelLabel = CurrentTurnIndicator:FindFirstChild("PlayerLevelLabel")
local TurnTimerFrame = CurrentTurnIndicator:FindFirstChild("TurnTimerFrame")
local TimerFill = TurnTimerFrame and TurnTimerFrame:FindFirstChild("TimerFill")
local TimerText = TurnTimerFrame and TurnTimerFrame:FindFirstChild("TimerText")

-- เพิ่ม UI แสดงสถานะคูลดาวน์การต่อสู้
local CombatCooldownLabel = nil
if not CurrentTurnIndicator:FindFirstChild("CombatCooldownLabel") then
	CombatCooldownLabel = Instance.new("TextLabel")
	CombatCooldownLabel.Name = "CombatCooldownLabel"
	CombatCooldownLabel.Size = UDim2.new(1, 0, 0, 20)
	CombatCooldownLabel.Position = UDim2.new(0, 0, 1, 3)
	CombatCooldownLabel.AnchorPoint = Vector2.new(0, 0)
	CombatCooldownLabel.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
	CombatCooldownLabel.BackgroundTransparency = 0.2
	CombatCooldownLabel.BorderSizePixel = 0
	CombatCooldownLabel.Font = Enum.Font.GothamSemibold
	CombatCooldownLabel.Text = "Combat Cooldown: 0"
	CombatCooldownLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	CombatCooldownLabel.TextSize = 14
	CombatCooldownLabel.Visible = false
	CombatCooldownLabel.Parent = CurrentTurnIndicator

	-- Add UICorner
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, 4)
	uiCorner.Parent = CombatCooldownLabel
else
	CombatCooldownLabel = CurrentTurnIndicator:FindFirstChild("CombatCooldownLabel")
end

-- Verify all required components are present
if not TurnText or not PlayerClassLabel or not PlayerLevelLabel or 
	not TurnTimerFrame or not TimerFill or not TimerText then
	warn("Turn Indicator is missing required components")
end

-- Get remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local gameRemotes = remotes:WaitForChild("GameRemotes")
local uiRemotes = remotes:WaitForChild("UIRemotes")
local combatRemotes = remotes:WaitForChild("CombatRemotes", 10) -- รอไม่เกิน 10 วินาที

-- Get required remotes
local updateTurnEvent = gameRemotes:WaitForChild("UpdateTurn")
local updateTurnTimerEvent = gameRemotes:FindFirstChild("UpdateTurnTimer")
local updateTurnDetailsEvent = uiRemotes:FindFirstChild("UpdateTurnDetails")
local combatCooldownEvent = gameRemotes:FindFirstChild("CombatCooldown") or 
	(combatRemotes and combatRemotes:FindFirstChild("CombatCooldown"))

-- Track timer tween
local currentTimerTween = nil
local isMyTurn = false
local currentCombatCooldown = 0 -- เพิ่มตัวแปรเก็บจำนวนเทิร์นคูลดาวน์ปัจจุบัน

-- ฟังก์ชันปรับปรุงการแสดงข้อมูลเทิร์น
local function updateTurnDisplay(turnData)
	if not CurrentTurnIndicator then return end

	debugLog("Updating turn display: " .. tostring(turnData.playerName))

	-- ตรวจสอบว่าเป็นเทิร์นของเราหรือไม่
	local currentPlayerId = turnData.playerId
	isMyTurn = (currentPlayerId == player.UserId)

	-- อัปเดตข้อความ
	if TurnText then
		TurnText.Text = turnData.playerName .. "'s Turn" .. 
			(turnData.turnNumber and " (Turn " .. turnData.turnNumber .. ")" or "")
	end

	-- อัปเดตข้อมูลคลาสและเลเวล
	if PlayerClassLabel then
		PlayerClassLabel.Text = "Class: " .. (turnData.playerClass or "Unknown")
	end

	if PlayerLevelLabel then
		PlayerLevelLabel.Text = "Lv." .. (turnData.playerLevel or "1")
	end

	-- ปรับสีและเอฟเฟคตามเทิร์น
	local backgroundColor, strokeColor, textColor

	if isMyTurn then
		-- ถ้าเป็นเทิร์นของเรา
		backgroundColor = Color3.fromRGB(50, 100, 180)
		strokeColor = Color3.fromRGB(100, 200, 255)
		textColor = Color3.fromRGB(255, 255, 255)

		-- แอนิเมชันเมื่อเริ่มเทิร์น
		local originalScale = CurrentTurnIndicator.Size
		local originalPosition = CurrentTurnIndicator.Position

		TweenService:Create(
			CurrentTurnIndicator,
			TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{
				Size = UDim2.new(originalScale.X.Scale * 1.1, 0, originalScale.Y.Scale * 1.1, 0),
				BackgroundColor3 = Color3.fromRGB(60, 120, 200)
			}
		):Play()

		wait(0.5)

		TweenService:Create(
			CurrentTurnIndicator,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Size = originalScale,
				BackgroundColor3 = backgroundColor
			}
		):Play()
	else
		-- ถ้าเป็นเทิร์นของคนอื่น
		backgroundColor = Color3.fromRGB(50, 80, 120)
		strokeColor = Color3.fromRGB(100, 150, 200)
		textColor = Color3.fromRGB(220, 220, 255)
	end

	-- อัปเดตสี
	CurrentTurnIndicator.BackgroundColor3 = backgroundColor

	-- อัปเดต UIStroke ถ้ามี
	local stroke = CurrentTurnIndicator:FindFirstChild("UIStroke")
	if stroke then
		stroke.Color = strokeColor
	end

	-- อัปเดตสีข้อความ
	if TurnText then
		TurnText.TextColor3 = textColor
	end

	-- รีเซ็ตไทเมอร์
	if TimerFill and TimerText then
		-- ยกเลิก tween ที่ทำงานอยู่
		if currentTimerTween then
			currentTimerTween:Cancel()
			currentTimerTween = nil
		end

		-- รีเซ็ตค่าไทเมอร์
		TimerFill.Size = UDim2.new(1, 0, 1, 0)
		TimerFill.BackgroundColor3 = Color3.fromRGB(50, 200, 50) -- เขียว
		TimerText.Text = "120s"
	end
end

-- ฟังก์ชันอัปเดตเวลา
local function updateTimer(timeRemaining)
	if not TurnTimerFrame or not TimerFill or not TimerText then return end

	-- ถ้าไม่ได้อยู่ในเกม (TurnIndicator ถูกซ่อน) ให้ข้าม
	if not CurrentTurnIndicator.Visible then return end

	debugLog("Updating timer: " .. timeRemaining .. "s")

	-- อัปเดตข้อความเวลา
	TimerText.Text = tostring(timeRemaining) .. "s"

	-- คำนวณอัตราส่วนที่เหลือ (สมมติเวลาเต็มคือ 120 วินาที)
	local maxTime = 120 -- เวลาสูงสุดที่คาดว่าจะตั้งไว้
	local fillRatio = timeRemaining / maxTime

	-- ยกเลิก tween ที่ทำงานอยู่
	if currentTimerTween then
		currentTimerTween:Cancel()
		currentTimerTween = nil
	end

	-- อนิเมชันลดขนาดแถบเวลา
	currentTimerTween = TweenService:Create(
		TimerFill,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Size = UDim2.new(fillRatio, 0, 1, 0)}
	)
	currentTimerTween:Play()

	-- เปลี่ยนสีตามเวลาที่เหลือ
	if timeRemaining <= 10 then
		TimerFill.BackgroundColor3 = Color3.fromRGB(255, 50, 50) -- แดง
	elseif timeRemaining <= 30 then
		TimerFill.BackgroundColor3 = Color3.fromRGB(255, 150, 50) -- ส้ม
	else
		TimerFill.BackgroundColor3 = Color3.fromRGB(50, 200, 50) -- เขียว
	end
end

-- เพิ่มฟังก์ชันใหม่: อัปเดตการแสดงสถานะคูลดาวน์การต่อสู้
local function updateCombatCooldown(cooldownTurns, failedCombatReason)
	if not CombatCooldownLabel then return end

	currentCombatCooldown = cooldownTurns or 0

	if currentCombatCooldown <= 0 then
		-- ซ่อนป้ายถ้าไม่มีคูลดาวน์
		CombatCooldownLabel.Visible = false
		debugLog("Hiding combat cooldown label")
		return
	end

	-- แสดงสถานะคูลดาวน์
	CombatCooldownLabel.Visible = true

	if failedCombatReason then
		-- กรณีแสดงเมื่อไม่สามารถเข้าต่อสู้ได้
		if failedCombatReason == true then
			-- คูลดาวน์ของตัวเอง
			CombatCooldownLabel.Text = "Combat Cooldown: " .. cooldownTurns .. " turns"
			CombatCooldownLabel.BackgroundColor3 = Color3.fromRGB(255, 50, 50) -- สีแดง
		else
			-- คูลดาวน์ของคู่ต่อสู้
			CombatCooldownLabel.Text = "Opponent has combat cooldown: " .. cooldownTurns .. " turns"
			CombatCooldownLabel.BackgroundColor3 = Color3.fromRGB(150, 50, 150) -- สีม่วง
		end

		-- แสดง 3 วินาทีแล้วซ่อน
		task.delay(3, function()
			if not CombatCooldownLabel then return end
			CombatCooldownLabel.Visible = false
		end)
	else
		-- กรณีแสดงสถานะคูลดาวน์ปกติ
		CombatCooldownLabel.Text = "Combat Cooldown: " .. cooldownTurns .. " turns"
		CombatCooldownLabel.BackgroundColor3 = Color3.fromRGB(255, 50, 50) -- สีแดง

		-- แอนิเมชันเมื่อได้รับคูลดาวน์ใหม่ (ถ้าเพิ่งเริ่มติดคูลดาวน์)
		if cooldownTurns == 2 then -- สมมติว่าค่าเริ่มต้นคือ 2 เทิร์น
			local originalTransparency = CombatCooldownLabel.BackgroundTransparency

			TweenService:Create(
				CombatCooldownLabel,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{BackgroundTransparency = 0}
			):Play()

			wait(0.3)

			TweenService:Create(
				CombatCooldownLabel,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{BackgroundTransparency = originalTransparency}
			):Play()
		end
	end

	debugLog("Updated combat cooldown: " .. cooldownTurns .. " turns")
end

-- เชื่อมต่อกับ Remote Events
if updateTurnEvent then
	updateTurnEvent.OnClientEvent:Connect(function(currentPlayerId)
		-- สร้างข้อมูลเบื้องต้นถ้ายังไม่ได้รับ UpdateTurnDetails
		local turnData = {
			playerId = currentPlayerId,
			playerName = "Unknown",
			turnNumber = 1,
			playerClass = "Unknown",
			playerLevel = 1
		}

		-- หาชื่อผู้เล่น
		for _, plr in pairs(Players:GetPlayers()) do
			if plr.UserId == currentPlayerId then
				turnData.playerName = plr.Name
				break
			end
		end

		-- อัปเดตการแสดงผล
		updateTurnDisplay(turnData)
	end)
end

if updateTurnDetailsEvent then
	updateTurnDetailsEvent.OnClientEvent:Connect(function(turnDetails)
		-- อัปเดตการแสดงผลด้วยข้อมูลละเอียด
		updateTurnDisplay(turnDetails)
	end)
end

if updateTurnTimerEvent then
	updateTurnTimerEvent.OnClientEvent:Connect(function(timeRemaining)
		-- อัปเดตเวลา
		updateTimer(timeRemaining)
	end)
end

-- เชื่อมต่อกับ Remote Event คูลดาวน์การต่อสู้
if combatCooldownEvent then
	combatCooldownEvent.OnClientEvent:Connect(function(cooldownTurns, failedCombatReason)
		-- อัปเดตการแสดงสถานะคูลดาวน์
		updateCombatCooldown(cooldownTurns, failedCombatReason)
	end)
end

-- แสดง/ซ่อน Turn Indicator
local function setIndicatorVisible(visible)
	if not CurrentTurnIndicator then return end

	CurrentTurnIndicator.Visible = visible

	if visible then
		-- เอฟเฟคเมื่อแสดง
		CurrentTurnIndicator.BackgroundTransparency = 1

		TweenService:Create(
			CurrentTurnIndicator,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{BackgroundTransparency = 0.2}
		):Play()
	end
end

-- เริ่มต้นสถานะ
setIndicatorVisible(false)

-- เชื่อมต่อกับการแสดง MainGameUI
MainGameUI:GetPropertyChangedSignal("Enabled"):Connect(function()
	if MainGameUI.Enabled then
		-- เมื่อ MainGameUI ถูกเปิดใช้งาน
		setIndicatorVisible(true)
	else
		-- เมื่อ MainGameUI ถูกปิด
		setIndicatorVisible(false)
	end
end)

-- ฟังก์ชันสำหรับเรียกใช้จากภายนอก
local TurnIndicatorHandler = {
	Show = function() setIndicatorVisible(true) end,
	Hide = function() setIndicatorVisible(false) end,
	UpdateDisplay = updateTurnDisplay,
	UpdateTimer = updateTimer,
	UpdateCombatCooldown = updateCombatCooldown, -- เพิ่มฟังก์ชันใหม่
	IsMyTurn = function() return isMyTurn end,
	GetCombatCooldown = function() return currentCombatCooldown end, -- เพิ่มฟังก์ชันใหม่
	EnableDebug = function(enable) 
		DEBUG_MODE = enable
		debugLog("Debug mode " .. (enable and "enabled" or "disabled"))
	end
}

return TurnIndicatorHandler
