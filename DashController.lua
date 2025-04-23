-- DashController.lua
-- Client-side controller for dash abilities in combat
-- Version: 1.0.0

local DashController = {}
DashController.__index = DashController

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Constants
local DASH_KEY = Enum.KeyCode.Q  -- กำหนดปุ่มสำหรับการ Dash

-- Variables
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local dashCooldown = 0
local isDashing = false
local combatActive = false
local dashAnimations = {}

-- Get remote events
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local combatRemotes = remotes:WaitForChild("CombatRemotes")
local dashRequest = combatRemotes:WaitForChild("DashRequest")
local dashEffect = combatRemotes:WaitForChild("DashEffect")
local dashCooldownEvent = combatRemotes:WaitForChild("DashCooldown")
local setCombatStateEvent = combatRemotes:WaitForChild("SetCombatState")

-- ฟังก์ชันสำหรับเริ่มต้นระบบ
function DashController:Initialize()
	-- Prepare dash animations
	self:PreloadDashAnimations()

	-- Listen for input events
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		self:HandleInput(input, gameProcessed)
	end)

	-- Listen for remote events
	self:ConnectRemoteEvents()

	-- Listen for character changes
	player.CharacterAdded:Connect(function(newCharacter)
		character = newCharacter
		humanoid = character:WaitForChild("Humanoid")
		self:PreloadDashAnimations()
	end)


	print("[DashController] Initialized")
end

-- สร้างและโหลด Animation objects ล่วงหน้า
function DashController:PreloadDashAnimations()
	local animator = humanoid:FindFirstChild("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	-- Clear existing animations
	dashAnimations = {}

	-- Dash animations
	local animationIds = {
		Front = "rbxassetid://14103831900",
		Back = "rbxassetid://14103833544",
		Left = "rbxassetid://14103834807",
		Right = "rbxassetid://14103836416"
	}

	-- Create animation objects
	for direction, id in pairs(animationIds) do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		dashAnimations[direction] = animator:LoadAnimation(animation)

		-- Configure animation
		dashAnimations[direction].Priority = Enum.AnimationPriority.Action
		dashAnimations[direction].Looped = false
	end
end

-- การเชื่อมต่อกับ Remote Events
function DashController:ConnectRemoteEvents()
	-- Listen for dash effect event
	dashEffect.OnClientEvent:Connect(function(direction, effectType, effectColor, animationId, playerSource)
		if direction == "Complete" then
			-- Dash completed
			isDashing = false
			return
		end

		-- If we're receiving another player's Thief vanish effect
		if playerSource and playerSource ~= player then
			self:PlayOtherPlayerVanishEffect(playerSource, direction, effectColor)
			return
		end

		-- Play dash animation and effect for our own character
		self:PlayDashEffect(direction, effectType, effectColor)
	end)

	-- Listen for dash cooldown updates
	dashCooldownEvent.OnClientEvent:Connect(function(cooldownTime)
		self:UpdateCooldown(cooldownTime)
	end)

	-- Listen for combat state changes
	setCombatStateEvent.OnClientEvent:Connect(function(isActive, duration)
		combatActive = isActive

		if not isActive then
			-- Clear dash cooldown when combat ends
			self:UpdateCooldown(0)
		end
	end)
end

-- การจัดการกับ Input
function DashController:HandleInput(input, gameProcessed)
	-- Ignore if game has already processed this input
	if gameProcessed then return end

	-- Dash on Q key press
	if input.KeyCode == DASH_KEY then
		self:TryDash()
	end
end

-- พยายามใช้ Dash - ไม่มีการแสดง UI
function DashController:TryDash()
	-- Check if we're allowed to dash
	if not combatActive then
		-- ถ้าไม่ได้อยู่ในโหมด Combat (ไม่มีการแสดงข้อความ)
		return
	end

	if isDashing then
		-- ถ้ากำลัง Dash อยู่แล้ว
		return
	end

	if dashCooldown > 0 then
		-- ถ้าอยู่ในช่วงคูลดาวน์ (ไม่มีการแสดงข้อความ)
		return
	end

	-- Check if character exists and is on ground
	if not character or not humanoid then
		return
	end

	-- Anti-exploit: Check if player is jumping or in air
	if humanoid:GetState() == Enum.HumanoidStateType.Jumping or 
		humanoid:GetState() == Enum.HumanoidStateType.Freefall then
		-- ถ้าอยู่ในอากาศ จะไม่สามารถใช้ Dash ได้ (ไม่มีการแสดงข้อความ)
		return
	end

	-- Determine dash direction based on movement keys being pressed
	local direction = self:GetDashDirection()

	-- Send dash request to server
	dashRequest:FireServer(direction)

	-- Set local state
	isDashing = true
end

-- ฟังก์ชันแสดงข้อความลอยเหนือตัวละคร (ถูกปิดใช้งาน - ไม่แสดงข้อความใดๆ)
function DashController:ShowFloatingText(text)
	-- ฟังก์ชันนี้ถูกปิดใช้งานตามคำขอ - ไม่แสดงข้อความใดๆ เหนือหัวตัวละคร
	return
end

-- หาทิศทางการ Dash จากการกดปุ่มเคลื่อนที่
function DashController:GetDashDirection()
	local movementKeys = {
		[Enum.KeyCode.W] = "Front",
		[Enum.KeyCode.S] = "Back",
		[Enum.KeyCode.A] = "Left",
		[Enum.KeyCode.D] = "Right"
	}

	for key, direction in pairs(movementKeys) do
		if UserInputService:IsKeyDown(key) then
			return direction
		end
	end

	-- Default to forward if no keys pressed
	return "Front"
end

-- อัพเดตสถานะคูลดาวน์ (ไม่มีการแสดง UI ตามคำขอ)
function DashController:UpdateCooldown(newCooldown)
	dashCooldown = newCooldown

	if dashCooldown <= 0 then
		-- Reset cooldown
		dashCooldown = 0
		return
	end

	-- Start cooldown timer (ไม่มีการแสดง UI แต่ยังคงนับเวลาคูลดาวน์)
	local startTime = tick()
	local connection

	connection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local remaining = dashCooldown - elapsed

		if remaining <= 0 then
			-- Cooldown complete
			dashCooldown = 0
			if connection then connection:Disconnect() end
			return
		end
	end)
end

-- เล่นเอฟเฟคต์การ Dash
function DashController:PlayDashEffect(direction, effectType, effectColor)
	-- Set dashing flag
	isDashing = true

	-- Play animation if available
	local animation = dashAnimations[direction]
	if animation then
		animation:Play()
	end

	-- Create visual effects based on effect type
	if effectType == "Roll" then
		self:PlayRollEffect(effectColor)
	elseif effectType == "Vanish" then
		self:PlayVanishEffect(effectColor)
	end
end

-- เอฟเฟคการ Roll
function DashController:PlayRollEffect(effectColor)
	-- Create trail effect
	self:CreateTrailEffect(effectColor)

	-- Create particle effect
	local attachment = Instance.new("Attachment")
	attachment.Parent = character.HumanoidRootPart

	local particleEmitter = Instance.new("ParticleEmitter")
	particleEmitter.Texture = "rbxassetid://2581889193" -- Smoke texture
	particleEmitter.Color = ColorSequence.new(effectColor)
	particleEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.2)
	})
	particleEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1)
	})
	particleEmitter.Lifetime = NumberRange.new(0.5, 0.8)
	particleEmitter.Rate = 40
	particleEmitter.SpreadAngle = Vector2.new(35, 35)
	particleEmitter.Speed = NumberRange.new(3, 5)
	particleEmitter.Parent = attachment

	-- Remove after dash
	game.Debris:AddItem(attachment, 1)
end

-- เอฟเฟคการ Vanish (หายตัว) สำหรับ Thief โดยใช้เอฟเฟค Ring จาก VFX/soru
function DashController:PlayVanishEffect(effectColor)
	-- Make parts semi-transparent locally
	local originalTransparency = {}
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") or part:IsA("Decal") then
			originalTransparency[part] = part.LocalTransparencyModifier
			part.LocalTransparencyModifier = 0.9 -- เพิ่มความโปร่งใสให้มากขึ้น (0.9 แทน 0.8)
		end
	end

	-- ใช้เอฟเฟค Ring จาก VFX/soru
	local VFX = ReplicatedStorage:FindFirstChild("VFX")
	local soruFolder = VFX and VFX:FindFirstChild("soru")
	local ringEffect = soruFolder and soruFolder:FindFirstChild("Ring")

	if ringEffect then
		-- Clone and play Ring effect
		local ringClone = ringEffect:Clone()
		ringClone.Parent = character.HumanoidRootPart

		-- Set effect color if needed
		local ringParts = ringClone:GetDescendants()
		for _, part in ipairs(ringParts) do
			if part:IsA("ParticleEmitter") then
				-- อาจจะปรับสีตาม effectColor ถ้าต้องการ
				part:Emit(part:GetAttribute("EmitCount") or 30)
			end
		end

		-- Clean up after effect duration
		game.Debris:AddItem(ringClone, 1) -- เพิ่มระยะเวลาเอฟเฟคให้นานขึ้น

		-- เล่นเอฟเฟค Soru1 ตอนเริ่มต้น
		local soru1 = soruFolder and soruFolder:FindFirstChild("Soru1")
		if soru1 then
			local soru1Clone = soru1:Clone()
			soru1Clone.Parent = character.HumanoidRootPart
			game.Debris:AddItem(soru1Clone, 1) -- เพิ่มระยะเวลาเอฟเฟคให้นานขึ้น
		end

		-- เล่นเอฟเฟค Soru2 ตอนปลาย - เพิ่มดีเลย์ให้นานขึ้น
		delay(0.9, function() -- เพิ่มดีเลย์จาก 0.45 เป็น 0.9 วินาที
			local soru2 = soruFolder and soruFolder:FindFirstChild("Soru2")
			if soru2 then
				local soru2Clone = soru2:Clone()
				soru2Clone.Parent = character.HumanoidRootPart
				game.Debris:AddItem(soru2Clone, 1) -- เพิ่มระยะเวลาเอฟเฟคให้นานขึ้น
			end
		end)
	else
	end

	-- Restore transparency after dash - เพิ่มระยะเวลาการหายตัวให้นานขึ้น
	delay(1.0, function() -- เพิ่มระยะเวลาจาก 0.5 เป็น 1.0 วินาที
		for part, origTransparency in pairs(originalTransparency) do
			if part:IsA("BasePart") or part:IsA("Decal") then
				part.LocalTransparencyModifier = origTransparency
			end
		end
	end)
end

-- สร้างเอฟเฟคเส้นสาย (Trail) ตามตัวละคร
function DashController:CreateTrailEffect(effectColor)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso then return end

	-- Create attachments for trail
	local attachment1 = Instance.new("Attachment")
	attachment1.Position = Vector3.new(0, 0.25, 0.5)
	attachment1.Parent = torso

	local attachment2 = Instance.new("Attachment")
	attachment2.Position = Vector3.new(0, 0.25, -0.5)
	attachment2.Parent = torso

	-- Create trail
	local trail = Instance.new("Trail")
	trail.Attachment0 = attachment1
	trail.Attachment1 = attachment2
	trail.Color = ColorSequence.new(effectColor)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1)
	})
	trail.Lifetime = 0.4
	trail.FaceCamera = true
	trail.Parent = torso

	-- Clean up after dash
	game.Debris:AddItem(attachment1, 1)
	game.Debris:AddItem(attachment2, 1)
	game.Debris:AddItem(trail, 1)
end

-- แสดงเอฟเฟคการหายตัวของผู้เล่นอื่น (สำหรับ Thief) โดยใช้เอฟเฟค VFX/soru
function DashController:PlayOtherPlayerVanishEffect(playerSource, direction, effectColor)
	local otherCharacter = playerSource.Character
	if not otherCharacter then return end

	local hrp = otherCharacter:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Make character appear transparent
	for _, part in pairs(otherCharacter:GetDescendants()) do
		if part:IsA("BasePart") or part:IsA("Decal") then
			part.LocalTransparencyModifier = 0.9 -- เพิ่มความโปร่งใสให้มากขึ้น (0.9 แทน 0.8)
		end
	end

	-- ใช้เอฟเฟค Ring และ Soru1 จาก VFX/soru
	local VFX = ReplicatedStorage:FindFirstChild("VFX")
	local soruFolder = VFX and VFX:FindFirstChild("soru")

	-- เล่นเอฟเฟค Ring
	if soruFolder and soruFolder:FindFirstChild("Ring") then
		local ringClone = soruFolder.Ring:Clone()
		ringClone.Parent = hrp
		game.Debris:AddItem(ringClone, 1) 

		-- เล่นเอฟเฟค Soru1 ตอนเริ่มต้น
		if soruFolder:FindFirstChild("Soru1") then
			local soru1Clone = soruFolder.Soru1:Clone() 
			soru1Clone.Parent = hrp
			game.Debris:AddItem(soru1Clone, 1) 
		end
	else
	end

	-- Restore normal appearance and play reappear effect after dash
	delay(1.0, function() -- เพิ่มระยะเวลาการหายตัวจาก 0.5 เป็น 1.0 วินาที
		for _, part in pairs(otherCharacter:GetDescendants()) do
			if part:IsA("BasePart") or part:IsA("Decal") then
				part.LocalTransparencyModifier = 0
			end
		end

		-- เล่นเอฟเฟค Soru2 ตอนปลาย
		if soruFolder and soruFolder:FindFirstChild("Soru2") then
			local soru2Clone = soruFolder.Soru2:Clone()
			soru2Clone.Parent = hrp
			game.Debris:AddItem(soru2Clone, 1)
		else
		end
	end)
end

-- เริ่มต้นระบบ
DashController:Initialize()

return DashController
