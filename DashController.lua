-- DashController.lua
-- Client-side controller for dash abilities in combat
-- Version: 1.2.0 (เพิ่ม Vanish สำหรับคลาส Thief ใช้ R)

local DashController = {}
DashController.__index = DashController

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Constants
local DASH_KEY = Enum.KeyCode.Q
local VANISH_KEY = Enum.KeyCode.R -- เพิ่มปุ่ม R สำหรับ Vanish
local TRAIL_LIFETIME = 0.45
local TRAIL_WIDTH_SCALE = 0.8
local DEFAULT_WALKSPEED = 16 -- ค่า WalkSpeed ปกติ
local THIEF_BOOST_ENDTIME_ATTR = "ThiefBoostEndTime" -- ชื่อ Attribute ตรงกับ Server
local THIEF_BOOST_SPEED_ATTR = "ThiefBoostSpeed" -- ชื่อ Attribute ตรงกับ Server
local ORIGINAL_SPEED_ATTR = "OriginalWalkSpeed" -- ชื่อ Attribute ตรงกับ Server

-- Variables
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")
local dashCooldown = 0
local vanishCooldown = 0 -- เพิ่ม cooldown สำหรับสกิล Vanish
local isDashing = false
local isVanishing = false -- เพิ่มตัวแปรสถานะ Vanish
local isAbilityLocked = false -- ล็อคการใช้ความสามารถระหว่างใช้อีกอันอยู่
local combatActive = false
local playerClass = "Unknown" -- เพิ่มตัวแปรเก็บคลาสของผู้เล่น
local isPlayerThief = false -- เพิ่มตัวแปรเช็คว่าเป็น Thief หรือไม่
local dashAnimations = {}
local activeTrails = {}
local heartbeatConnection = nil -- Connection สำหรับจัดการ Speed Boost
local classCheckEnabled = true -- ตัวแปรควบคุมการตรวจสอบคลาส

-- Get remote events
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local combatRemotes = remotes:WaitForChild("CombatRemotes")
local dashRequest = combatRemotes:WaitForChild("DashRequest")
local dashEffect = combatRemotes:WaitForChild("DashEffect")
local dashCooldownEvent = combatRemotes:WaitForChild("DashCooldown")
local setCombatStateEvent = combatRemotes:WaitForChild("SetCombatState")

-- เพิ่ม Remote Events สำหรับ Vanish
local vanishRequest = combatRemotes:WaitForChild("VanishRequest")
local vanishCooldownEvent = combatRemotes:WaitForChild("VanishCooldown")

-- Initialize
function DashController:Initialize()
	self:UpdateCharacterReferences(character)
	self:PreloadDashAnimations()
	self:ConnectRemoteEvents()
	self:StartSpeedBoostManager() -- เริ่มตัวจัดการ Speed Boost ฝั่ง Client

	-- ดึงข้อมูลคลาสของผู้เล่น
	local initialClassCheck = self:GetPlayerClass()
	if not initialClassCheck then
		print("[DashController] Initial class check failed, will retry...")
	end

	-- เพิ่มการตรวจสอบคลาสอย่างต่อเนื่อง
	-- ตรวจสอบทุก 2 วินาทีจนกว่าจะได้ค่าคลาสที่ถูกต้อง หรือครบ 15 ครั้ง (30 วินาที)
	local classCheckCount = 0
	local maxChecks = 15

	task.spawn(function()
		while classCheckCount < maxChecks and classCheckEnabled do
			classCheckCount = classCheckCount + 1
			task.wait(2) -- รอ 2 วินาที

			if not classCheckEnabled then break end

			local success = self:CheckPlayerClassRealtime()
			if success and isPlayerThief then
				print("[DashController] Found player is Thief after " .. classCheckCount .. " attempts")
				break -- หยุดถ้าได้ค่าคลาสเป็น Thief แล้ว
			elseif success and playerClass ~= "Unknown" then
				print("[DashController] Found player class: " .. playerClass)
				if classCheckCount >= 5 then -- ตรวจสอบครบ 5 ครั้งแล้ว ก็ลดความถี่ลง
					task.wait(3) -- เพิ่มการรอเป็น 5 วินาที
				end
			end
		end

		-- หลังจากตรวจสอบเสร็จแล้ว ให้เช็คอีกครั้งเพื่อความแน่ใจ
		if not isPlayerThief and playerClass ~= "Thief" then
			print("[DashController] Final class check: Player is not confirmed as Thief, continuing checks on input")
		else
			print("[DashController] Final class check: Player is confirmed as Thief")
			-- ไม่ต้องปิดการตรวจสอบคลาส เผื่อผู้เล่นเปลี่ยนคลาสในภายหลัง
		end
	end)

	-- จัดการการกดปุ่ม
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		self:HandleInput(input, gameProcessed)
	end)

	player.CharacterAdded:Connect(function(newCharacter)
		self:StopSpeedBoostManager() -- หยุดของเก่าก่อน
		self:UpdateCharacterReferences(newCharacter)
		self:PreloadDashAnimations()
		self:CleanupAllTrails()
		self:StartSpeedBoostManager() -- เริ่มใหม่สำหรับตัวละครใหม่
		self:GetPlayerClass() -- อัปเดตคลาสเมื่อตัวละครเปลี่ยน

		-- รีเซ็ตสถานะการใช้ความสามารถ
		isDashing = false
		isVanishing = false
		isAbilityLocked = false
	end)

	player.CharacterRemoving:Connect(function()
		self:StopSpeedBoostManager() -- หยุดเมื่อตัวละครถูกลบ
		self:CleanupAllTrails()

		-- รีเซ็ตสถานะการใช้ความสามารถ
		isDashing = false
		isVanishing = false
		isAbilityLocked = false
	end)

	print("[DashController] Initialized")
end

-- ดึงข้อมูลคลาสของผู้เล่น
function DashController:GetPlayerClass()
	-- ไม่ตั้งค่า playerClass = "Unknown" เพื่อไม่ให้เปลี่ยนค่าเดิม

	-- ฟังก์ชันสำหรับตรวจสอบคลาส
	local function tryGetClass()
		local gameManager = _G.GameManager
		if gameManager then
			if gameManager.classSystem then
				local c = gameManager.classSystem:GetPlayerClass(player)
				if c then 
					playerClass = c
					isPlayerThief = (c == "Thief")
					print("[DashController] Player class identified: " .. playerClass .. ", isThief: " .. tostring(isPlayerThief))
					return true
				end
			end

			if gameManager.playerManager then
				local d = gameManager.playerManager:GetPlayerData(player)
				if d and d.class then
					playerClass = d.class
					isPlayerThief = (d.class == "Thief")
					print("[DashController] Player class identified: " .. playerClass .. ", isThief: " .. tostring(isPlayerThief))
					return true
				end
			end
		end
		return false
	end

	-- พยายามดึงข้อมูลทันที
	if tryGetClass() then
		return true
	end

	return false
end

-- เพิ่มฟังก์ชันตรวจสอบคลาสแบบเรียลไทม์
function DashController:CheckPlayerClassRealtime()
	-- ถ้าปิดการตรวจสอบคลาส ให้ข้ามไป
	if not classCheckEnabled then return false end

	-- ฟังก์ชันสำหรับตรวจสอบคลาสแบบเรียลไทม์
	local gameManager = _G.GameManager
	if gameManager then
		if gameManager.classSystem then
			local c = gameManager.classSystem:GetPlayerClass(player)
			if c then 
				if playerClass ~= c then
					playerClass = c
					isPlayerThief = (c == "Thief")
					print("[DashController] Updated player class: " .. playerClass .. ", isThief: " .. tostring(isPlayerThief))
				end
				return true
			end
		end

		if gameManager.playerManager then
			local d = gameManager.playerManager:GetPlayerData(player)
			if d and d.class then
				if playerClass ~= d.class then
					playerClass = d.class
					isPlayerThief = (d.class == "Thief")
					print("[DashController] Updated player class: " .. playerClass .. ", isThief: " .. tostring(isPlayerThief))
				end
				return true
			end
		end
	end

	print("[DashController] Could not identify player class")
	return false
end

-- Start Client-Side Speed Boost Manager (เหมือนเดิม)
function DashController:StartSpeedBoostManager()
	if heartbeatConnection then return end -- ป้องกันการเริ่มซ้ำ

	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		if not humanoid or not humanoid.Parent or isDashing then
			-- ถ้าไม่มี Humanoid หรือกำลัง Dash อยู่ ไม่ต้องจัดการ Speed
			return
		end

		local boostEndTime = humanoid:GetAttribute(THIEF_BOOST_ENDTIME_ATTR)

		if boostEndTime and typeof(boostEndTime) == "number" then
			if tick() < boostEndTime then
				-- ยังอยู่ในช่วง Boost
				local boostedSpeed = humanoid:GetAttribute(THIEF_BOOST_SPEED_ATTR)
				if boostedSpeed and typeof(boostedSpeed) == "number" then
					-- ตั้งค่า Speed Boost ถ้ายังไม่เท่า
					if math.abs(humanoid.WalkSpeed - boostedSpeed) > 0.1 then
						humanoid.WalkSpeed = boostedSpeed
					end
				end
			else
				-- หมดเวลา Boost หรือเวลาไม่ถูกต้อง
				local originalSpeed = humanoid:GetAttribute(ORIGINAL_SPEED_ATTR) or DEFAULT_WALKSPEED
				-- คืนค่า Speed ถ้ายังไม่เท่าค่าเดิม
				if math.abs(humanoid.WalkSpeed - originalSpeed) > 0.1 then
					humanoid.WalkSpeed = originalSpeed
				end
				-- Server ควรจะลบ Attribute เอง แต่ Client หยุดใช้ค่า Boost
			end
		else
			-- ไม่มี Attribute Boost หรือหมดเวลาแล้ว
			local originalSpeed = humanoid:GetAttribute(ORIGINAL_SPEED_ATTR) or DEFAULT_WALKSPEED
			-- ตรวจสอบว่า Speed ปัจจุบันไม่ใช่ค่า Default หรือค่าที่เก็บไว้
			if math.abs(humanoid.WalkSpeed - originalSpeed) > 0.1 then
				-- คืนค่า Speed เป็นค่า Default หรือค่าที่เก็บไว้ (ถ้ามี)
				humanoid.WalkSpeed = originalSpeed
			end
		end
	end)
end

-- Stop Client-Side Speed Boost Manager (เหมือนเดิม)
function DashController:StopSpeedBoostManager()
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
		-- ลองคืนค่า Speed เป็น Default เมื่อหยุด Manager
		if humanoid and humanoid.Parent then
			humanoid.WalkSpeed = DEFAULT_WALKSPEED
		end
	end
end

-- UpdateCharacterReferences (เหมือนเดิม)
function DashController:UpdateCharacterReferences(newCharacter)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid")
	animator = humanoid:WaitForChild("Animator")
	isDashing = false
end

-- PreloadDashAnimations (เพิ่ม Debug)
function DashController:PreloadDashAnimations()
	if not animator then print("[DashController] No animator found, cannot load animations"); return end

	-- ล้างอนิเมชั่นเก่าก่อน
	for _, anim in pairs(dashAnimations) do 
		if anim then anim:Destroy() end 
	end
	dashAnimations = {}

	-- อนิเมชั่นสำหรับแต่ละทิศทาง
	local ids = {
		Front = "rbxassetid://14103831900",
		Back = "rbxassetid://14103833544",
		Left = "rbxassetid://14103834807",
		Right = "rbxassetid://14103836416"
	}

	-- โหลดอนิเมชั่นแต่ละตัว
	for direction, id in pairs(ids) do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local track = animator:LoadAnimation(animation)
		if track then
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = false
			dashAnimations[direction] = track
		else
			print("[DashController] Failed to load animation for direction:", direction)
		end
		animation:Destroy()
	end

	print("[DashController] Animations loaded successfully")
end

-- ConnectRemoteEvents (เพิ่ม Vanish Events)
function DashController:ConnectRemoteEvents()
	dashEffect.OnClientEvent:Connect(function(direction, effectType, effectColor, animationId, playerSource)
		if not character or not humanoid or not animator then return end

		if direction == "Complete" then 
			isDashing = false
			isVanishing = false
			isAbilityLocked = false -- ปลดล็อคการใช้ความสามารถเมื่อสิ้นสุด
			self:CleanupAllTrails()
			return
		end

		if playerSource and playerSource ~= player then 
			if effectType == "Vanish" then 
				self:PlayOtherPlayerVanishEffect(playerSource, direction, effectColor)
			end
			return
		end

		-- ตั้งค่าตัวแปรสถานะตามประเภทเอฟเฟค
		if effectType == "Vanish" then
			isVanishing = true
		else
			isDashing = true
		end

		self:PlayDashEffect(direction, effectType, effectColor, animationId)
	end)

	dashCooldownEvent.OnClientEvent:Connect(function(cooldownTime) self:UpdateCooldown(cooldownTime) end)
	vanishCooldownEvent.OnClientEvent:Connect(function(cooldownTime) self:UpdateVanishCooldown(cooldownTime) end)
	setCombatStateEvent.OnClientEvent:Connect(function(isActive, duration) 
		combatActive = isActive
		if not isActive then 
			self:UpdateCooldown(0)
			self:UpdateVanishCooldown(0)
			isDashing = false
			isVanishing = false
			isAbilityLocked = false -- ปลดล็อคการใช้ความสามารถเมื่อสิ้นสุดการต่อสู้
		end 
	end)
end

-- HandleInput (ป้องกันการกด Q+R พร้อมกัน และเพิ่ม Debug)
function DashController:HandleInput(input, gameProcessed)
	if gameProcessed or not combatActive then return end

	-- ป้องกันการใช้ความสามารถซ้อนกัน
	if isDashing or isVanishing or isAbilityLocked then
		return
	end

	if input.KeyCode == DASH_KEY then
		self:TryDash()
	elseif input.KeyCode == VANISH_KEY then
		-- ตรวจสอบคลาสแบบเรียลไทม์ทุกครั้งที่กด R
		if not isPlayerThief then
			-- พยายามตรวจสอบคลาสอีกครั้ง
			self:CheckPlayerClassRealtime()

			if playerClass == "Thief" or isPlayerThief then
				print("[DashController] Vanish activated - Class check successful")
				self:TryVanish()
			else
				print("[DashController] Vanish failed - Player class: " .. playerClass .. ", isThief: " .. tostring(isPlayerThief))

				-- ตรวจสอบค่าเสริม (สำหรับ Debug)
				local gameManager = _G.GameManager
				if gameManager then
					if gameManager.classSystem then
						local c = gameManager.classSystem:GetPlayerClass(player)
						print("[DashController] Direct class check: " .. tostring(c))
					end

					if gameManager.playerManager then
						local d = gameManager.playerManager:GetPlayerData(player)
						if d then 
							print("[DashController] Player data class: " .. tostring(d.class))
						else
							print("[DashController] No player data found")
						end
					end
				else
					print("[DashController] No GameManager found")
				end

				-- ทดลองเปิดใช้ความสามารถโดยไม่สนใจการตรวจสอบคลาส (Debug)
				print("[DashController] Forcing Vanish ability test...")
				self:TryVanish()
			end
		else
			self:TryVanish()
		end
	end

	-- ปุ่มลับสำหรับ Debug - เปิดใช้งานความสามารถ Vanish
	if input.KeyCode == Enum.KeyCode.F1 then
		print("[DashController] Debug mode - Overriding class to Thief")
		playerClass = "Thief"
		isPlayerThief = true
	end
end

-- TryDash (เพิ่ม Debug ทิศทาง)
function DashController:TryDash()
	if isDashing or isVanishing or isAbilityLocked then return end
	if dashCooldown > 0 then return end
	if not character or not humanoid or not humanoid.RootPart then return end
	if humanoid:GetState() == Enum.HumanoidStateType.Jumping or humanoid:GetState() == Enum.HumanoidStateType.Freefall or humanoid:GetState() == Enum.HumanoidStateType.Dead then return end

	-- ล็อคการใช้ความสามารถ
	isAbilityLocked = true

	local dir = self:GetDashDirection()

	-- Debug ทิศทาง
	local dashVector = self:CalculateDashVector(dir)
	print("[DashController] Dash - Direction: " .. dir .. ", Vector: (" .. 
		string.format("%.2f, %.2f, %.2f", dashVector.X, dashVector.Y, dashVector.Z) .. ")")

	dashRequest:FireServer(dir)

	-- ถ้าไม่ได้รับการตอบกลับจาก Server ภายใน 0.5 วินาที ให้ปลดล็อคการใช้ความสามารถ
	task.delay(0.5, function()
		if isAbilityLocked and not isDashing then
			isAbilityLocked = false
		end
	end)
end

-- TryVanish (เพิ่มการป้องกันใช้ความสามารถซ้อน)
function DashController:TryVanish()
	if isDashing or isVanishing or isAbilityLocked then return end
	if vanishCooldown > 0 then return end
	if not character or not humanoid or not humanoid.RootPart then return end
	if humanoid:GetState() == Enum.HumanoidStateType.Jumping or humanoid:GetState() == Enum.HumanoidStateType.Freefall or humanoid:GetState() == Enum.HumanoidStateType.Dead then return end

	-- ล็อคการใช้ความสามารถ
	isAbilityLocked = true

	local dir = self:GetDashDirection()
	vanishRequest:FireServer(dir)

	-- ถ้าไม่ได้รับการตอบกลับจาก Server ภายใน 0.5 วินาที ให้ปลดล็อคการใช้ความสามารถ
	task.delay(0.5, function()
		if isAbilityLocked and not isVanishing then
			isAbilityLocked = false
		end
	end)
end

-- GetDashDirection (แก้ไขให้ใช้ทิศทางการหันหน้าของตัวละครเป็นหลัก)
function DashController:GetDashDirection()
	-- ตรวจสอบปุ่มที่กดอยู่
	local moveForward = UserInputService:IsKeyDown(Enum.KeyCode.W)
	local moveBackward = UserInputService:IsKeyDown(Enum.KeyCode.S)
	local moveLeft = UserInputService:IsKeyDown(Enum.KeyCode.A)
	local moveRight = UserInputService:IsKeyDown(Enum.KeyCode.D)

	-- กรณีไม่กดปุ่มใดๆ
	if not (moveForward or moveBackward or moveLeft or moveRight) then
		return "Front" -- ถ้าไม่กดปุ่มใด ให้ใช้ทิศทางที่ตัวละครกำลังหันหน้าไป
	end

	-- ตรวจสอบทิศทางที่ละเอียดขึ้น
	if moveForward and moveLeft then
		return "FrontLeft"
	elseif moveForward and moveRight then
		return "FrontRight"
	elseif moveBackward and moveLeft then
		return "BackLeft"
	elseif moveBackward and moveRight then
		return "BackRight"
	elseif moveForward then
		return "Front"
	elseif moveBackward then
		return "Back"
	elseif moveLeft then
		return "Left"
	elseif moveRight then
		return "Right"
	end

	return "Front" -- ค่าเริ่มต้น
end

-- คำนวณเวกเตอร์ทิศทางสำหรับการ Dash (Client-side calculation helper)
function DashController:CalculateDashVector(directionString)
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return Vector3.new(0, 0, 1) -- ค่าเริ่มต้นหากไม่มี HRP
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	local lookVector = hrp.CFrame.LookVector
	local rightVector = hrp.CFrame.RightVector

	-- แก้ไขการคำนวณทิศทางให้สัมพันธ์กับการหันหน้าของตัวละคร
	-- ทิศทางจะอ้างอิงตามตัวละคร ไม่ใช่ตามหน้าจอ
	if directionString == "Front" then
		return lookVector.Unit
	elseif directionString == "Back" then
		return -lookVector.Unit
	elseif directionString == "Left" then
		return -rightVector.Unit
	elseif directionString == "Right" then
		return rightVector.Unit
	elseif directionString == "FrontLeft" then
		return (lookVector - rightVector).Unit
	elseif directionString == "FrontRight" then
		return (lookVector + rightVector).Unit
	elseif directionString == "BackLeft" then
		return (-lookVector - rightVector).Unit
	elseif directionString == "BackRight" then
		return (-lookVector + rightVector).Unit
	end

	return lookVector.Unit -- ค่าเริ่มต้น
end

-- UpdateCooldown (เหมือนเดิม)
function DashController:UpdateCooldown(newCooldown)
	dashCooldown = newCooldown
	if dashCooldown <= 0 then 
		dashCooldown = 0
		return 
	end

	local startTime = tick()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not connection then return end
		local elapsed = tick() - startTime
		local remaining = newCooldown - elapsed
		if remaining <= 0 then
			dashCooldown = 0
			connection:Disconnect()
			connection = nil
		else
			dashCooldown = remaining
		end
	end)
end

-- เพิ่มฟังก์ชัน UpdateVanishCooldown
function DashController:UpdateVanishCooldown(newCooldown)
	vanishCooldown = newCooldown
	if vanishCooldown <= 0 then 
		vanishCooldown = 0
		return 
	end

	local startTime = tick()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not connection then return end
		local elapsed = tick() - startTime
		local remaining = newCooldown - elapsed
		if remaining <= 0 then
			vanishCooldown = 0
			connection:Disconnect()
			connection = nil
		else
			vanishCooldown = remaining
		end
	end)
end

-- PlayDashEffect (แก้ไขให้ไม่สร้าง Trail เมื่อใช้ Vanish)
function DashController:PlayDashEffect(direction, effectType, effectColor, animationId)
	-- เล่น Animation ถ้ามี และไม่ใช่ Vanish
	if animationId and effectType ~= "Vanish" then
		local anim = dashAnimations[direction]
		if anim then
			anim:Stop(0)
			anim:Play(0.1)
		else
			warn("Anim not found:", direction)
		end
	end

	-- แสดงเอฟเฟคตามประเภท
	if effectType == "Roll" then
		self:PlayRollEffect(effectColor)
		-- สร้าง Trail เฉพาะเมื่อเป็นการ Roll
		self:CreateLimbTrailEffect(effectColor)
	elseif effectType == "Vanish" then
		self:PlayVanishEffect(effectColor)
		-- ไม่สร้าง Trail เมื่อเป็น Vanish
	end
end

-- PlayRollEffect (เหมือนเดิม)
function DashController:PlayRollEffect(effectColor)
	if not character or not character.PrimaryPart then return end
	local h = character.PrimaryPart
	local a = Instance.new("Attachment", h)
	local p = Instance.new("ParticleEmitter", a)
	p.Texture = "rbxassetid://2581889193"
	p.Color = ColorSequence.new(effectColor, Color3.fromRGB(255, 255, 255))
	p.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 0.1)})
	p.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(0.7, 0.8), NumberSequenceKeypoint.new(1, 1)})
	p.Lifetime = NumberRange.new(0.4, 0.6)
	p.Rate = 50
	p.Rotation = NumberRange.new(-180, 180)
	p.RotSpeed = NumberRange.new(-90, 90)
	p.SpreadAngle = Vector2.new(45, 45)
	p.Speed = NumberRange.new(4, 7)
	p.Acceleration = Vector3.new(0, -2, 0)
	game.Debris:AddItem(a, 1.5)
end

-- PlayVanishEffect (แก้ไขให้ไม่ส่งผลกับ UI)
function DashController:PlayVanishEffect(effectColor)
	if not character or not humanoid then return end
	local origTransparency = {}

	-- สร้าง ScreenGui ป้องกัน UI เดิมไม่ให้ได้รับผลกระทบ
	local protectUI = Instance.new("ScreenGui")
	protectUI.Name = "VanishProtectionGui"
	protectUI.IgnoreGuiInset = true
	protectUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	protectUI.ResetOnSpawn = false
	protectUI.Parent = player:FindFirstChildOfClass("PlayerGui")

	-- เก็บค่าความโปร่งใสเฉพาะของตัวละคร ไม่รวม UI
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") or part:IsA("Decal") then
			origTransparency[part] = part.LocalTransparencyModifier
			TweenService:Create(part, TweenInfo.new(0.15), {LocalTransparencyModifier = 0.95}):Play()
		end
	end

	local vfx = ReplicatedStorage:FindFirstChild("VFX")
	local soru = vfx and vfx:FindFirstChild("soru")
	local hrp = character:FindFirstChild("HumanoidRootPart")

	if soru and hrp then
		local ring = soru:FindFirstChild("Ring")
		local soru1 = soru:FindFirstChild("Soru1")
		local soru2 = soru:FindFirstChild("Soru2")

		if ring then
			local ringClone = ring:Clone()
			ringClone.Parent = hrp
			for _, part in ipairs(ringClone:GetDescendants()) do
				if part:IsA("ParticleEmitter") then
					part.Color = ColorSequence.new(effectColor)
				end
			end
			game.Debris:AddItem(ringClone, 1.5)
		end

		if soru1 then
			local soruClone = soru1:Clone()
			soruClone.Parent = hrp
			game.Debris:AddItem(soruClone, 1.5)
		end

		local vanishDuration = 1.2
		task.delay(vanishDuration, function()
			if not character or not character.Parent then
				protectUI:Destroy()
				return
			end

			for part, originalTrans in pairs(origTransparency) do
				if part and part.Parent then
					TweenService:Create(part, TweenInfo.new(0.2), {LocalTransparencyModifier = originalTrans}):Play()
				end
			end

			if soru2 and hrp and hrp.Parent then
				local soru2Clone = soru2:Clone()
				soru2Clone.Parent = hrp
				game.Debris:AddItem(soru2Clone, 1.5)
			end

			-- ลบ protection GUI หลังจาก Vanish เสร็จสิ้น
			task.delay(0.3, function()
				protectUI:Destroy()
			end)
		end)
	else
		warn("VFX/soru not found.")
		local vanishDuration = 1.2
		task.delay(vanishDuration, function()
			if not character or not character.Parent then
				protectUI:Destroy()
				return
			end

			for part, originalTrans in pairs(origTransparency) do
				if part and part.Parent then
					TweenService:Create(part, TweenInfo.new(0.2), {LocalTransparencyModifier = originalTrans}):Play()
				end
			end

			-- ลบ protection GUI หลังจาก Vanish เสร็จสิ้น
			task.delay(0.3, function()
				protectUI:Destroy()
			end)
		end)
	end
end

-- สร้างเอฟเฟค Trail ที่แขนและขา (เหมือนเดิม)
function DashController:CreateLimbTrailEffect(effectColor)
	if not character then return end
	self:CleanupAllTrails()
	local limbNames = {"Left Arm", "Right Arm", "Left Leg", "Right Leg"} -- R6 Names
	local attachments = {}
	for _, name in ipairs(limbNames) do
		local limb = character:FindFirstChild(name)
		if limb and limb:IsA("BasePart") then
			local att0 = Instance.new("Attachment", limb); att0.Name = name:gsub(" ","").."_TrailAtt0"; att0.Position = Vector3.new(0, limb.Size.Y/2 - 0.1, 0)
			local att1 = Instance.new("Attachment", limb); att1.Name = name:gsub(" ","").."_TrailAtt1"; att1.Position = Vector3.new(0, -limb.Size.Y/2 + 0.1, 0)
			table.insert(attachments, att0); table.insert(attachments, att1)
			local trail = Instance.new("Trail", limb); trail.Name = name:gsub(" ","").."_Trail"
			trail.Attachment0 = att0; trail.Attachment1 = att1
			trail.Color = ColorSequence.new(effectColor)
			trail.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0.3),NumberSequenceKeypoint.new(0.6,0.7),NumberSequenceKeypoint.new(1,1)})
			trail.Lifetime = TRAIL_LIFETIME
			trail.WidthScale = NumberSequence.new(TRAIL_WIDTH_SCALE)
			trail.FaceCamera = true; trail.Enabled = true
			table.insert(activeTrails, trail)
		end
	end
	task.delay(TRAIL_LIFETIME + 0.2, function() for _, att in ipairs(attachments) do if att and att.Parent then att:Destroy() end end end)
end

-- CleanupAllTrails (เหมือนเดิม)
function DashController:CleanupAllTrails()
	for i = #activeTrails, 1, -1 do
		local trail = activeTrails[i]
		if trail and trail.Parent then
			if trail.Attachment0 then trail.Attachment0:Destroy() end
			if trail.Attachment1 then trail.Attachment1:Destroy() end
			trail:Destroy()
		end
		table.remove(activeTrails, i)
	end
end

-- PlayOtherPlayerVanishEffect (แก้ไขให้ไม่ส่งผลกับ UI)
function DashController:PlayOtherPlayerVanishEffect(playerSource, direction, effectColor)
	local otherCharacter = playerSource.Character
	if not otherCharacter then return end

	local hrp = otherCharacter:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- สร้าง ScreenGui ป้องกัน UI เดิมไม่ให้ได้รับผลกระทบ
	local protectUI = Instance.new("ScreenGui")
	protectUI.Name = "VanishProtectionGui_Other"
	protectUI.IgnoreGuiInset = true
	protectUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	protectUI.ResetOnSpawn = false
	protectUI.Parent = player:FindFirstChildOfClass("PlayerGui")

	local origTransparency = {}
	for _, part in pairs(otherCharacter:GetDescendants()) do
		if part:IsA("BasePart") or part:IsA("Decal") then
			origTransparency[part] = part.LocalTransparencyModifier
			TweenService:Create(part, TweenInfo.new(0.15), {LocalTransparencyModifier = 0.95}):Play()
		end
	end

	local vfx = ReplicatedStorage:FindFirstChild("VFX")
	local soru = vfx and vfx:FindFirstChild("soru")

	if soru then
		local ring = soru:FindFirstChild("Ring")
		local soru1 = soru:FindFirstChild("Soru1")
		local soru2 = soru:FindFirstChild("Soru2")

		if ring then
			local ringClone = ring:Clone()
			ringClone.Parent = hrp
			for _, part in ipairs(ringClone:GetDescendants()) do
				if part:IsA("ParticleEmitter") then
					part.Color = ColorSequence.new(effectColor)
				end
			end
			game.Debris:AddItem(ringClone, 1.5)
		end

		if soru1 then
			local soruClone = soru1:Clone()
			soruClone.Parent = hrp
			game.Debris:AddItem(soruClone, 1.5)
		end

		local vanishDuration = 1.2
		task.delay(vanishDuration, function()
			if not otherCharacter or not otherCharacter.Parent then
				protectUI:Destroy()
				return
			end

			for part, originalPercentage in pairs(origTransparency) do
				if part and part.Parent then
					TweenService:Create(part, TweenInfo.new(0.2), {LocalTransparencyModifier = originalPercentage}):Play()
				end
			end

			if soru2 and hrp and hrp.Parent then
				local soru2Clone = soru2:Clone()
				soru2Clone.Parent = hrp
				game.Debris:AddItem(soru2Clone, 1.5)
			end

			-- ลบ protection GUI หลังจาก Vanish เสร็จสิ้น
			task.delay(0.3, function()
				protectUI:Destroy()
			end)
		end)
	else
		local vanishDuration = 1.2
		task.delay(vanishDuration, function()
			if not otherCharacter or not otherCharacter.Parent then
				protectUI:Destroy()
				return
			end

			for part, originalPercentage in pairs(origTransparency) do
				if part and part.Parent then
					TweenService:Create(part, TweenInfo.new(0.2), {LocalTransparencyModifier = originalPercentage}):Play()
				end
			end

			-- ลบ protection GUI หลังจาก Vanish เสร็จสิ้น
			task.delay(0.3, function()
				protectUI:Destroy()
			end)
		end)
	end
end

-- Initialize
DashController:Initialize()

return DashController
