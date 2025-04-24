-- MovementController.lua
-- Client-side controller for movement abilities including dash and running
-- Version: 1.0.1 (Fixed double-tap running and added running animation)

local MovementController = {}
MovementController.__index = MovementController

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Constants
local DASH_KEY = Enum.KeyCode.Q
local SPECIAL_DASH_KEY = Enum.KeyCode.R  -- Key for Special Dash
local DEFAULT_WALKSPEED = 16
local THIEF_BOOST_ENDTIME_ATTR = "ThiefBoostEndTime"
local THIEF_BOOST_SPEED_ATTR = "ThiefBoostSpeed"
local ORIGINAL_SPEED_ATTR = "OriginalWalkSpeed"
local ROLL_VFX_LIFETIME = 0.5 -- Duration for the new Roll VFX

-- Running Constants
local RUN_KEY = Enum.KeyCode.W
local DOUBLE_TAP_WINDOW = 0.3 -- Time window for double tap detection (seconds)
local RUN_ANIM_ID = "rbxassetid://13836330574" -- ใช้ ID อนิเมชั่นวิ่งของเกม Roblox (ใส่ ID ของคุณที่นี่)
local RUN_BOOST_ENDTIME_ATTR = "RunBoostEndTime" -- Attribute สำหรับเวลาสิ้นสุดการวิ่ง
local RUN_BOOST_SPEED_ATTR = "RunBoostSpeed" -- Attribute สำหรับความเร็วการวิ่ง

-- Variables
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")
local regularDashCooldown = 0
local specialDashCooldown = 0
local isDashing = false
local isRunning = false
local combatActive = false
local dashAnimations = {}
local runAnimation = nil
local heartbeatConnection = nil
local playerClass = "Unknown"

-- Double-tap detection variables
local lastWKeyPressTime = 0
local wKeyPressCount = 0

-- Get remote events
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local combatRemotes = remotes:WaitForChild("CombatRemotes")
local dashRequest = combatRemotes:WaitForChild("DashRequest")
local specialDashRequest = combatRemotes:WaitForChild("SpecialDashRequest")
local dashEffect = combatRemotes:WaitForChild("DashEffect")
local dashCooldownEvent = combatRemotes:WaitForChild("DashCooldown")
local setCombatStateEvent = combatRemotes:WaitForChild("SetCombatState")

-- Create Run RemoteEvents if they don't exist
local runRequest = combatRemotes:FindFirstChild("RunRequest")
if not runRequest then
	runRequest = Instance.new("RemoteEvent")
	runRequest.Name = "RunRequest"
	runRequest.Parent = combatRemotes
end

local runState = combatRemotes:FindFirstChild("RunState")
if not runState then
	runState = Instance.new("RemoteEvent")
	runState.Name = "RunState"
	runState.Parent = combatRemotes
end

-- Initialize
function MovementController:Initialize()
	self:UpdateCharacterReferences(character)
	self:PreloadDashAnimations()
	self:PreloadRunAnimation()
	self:ConnectRemoteEvents()
	self:StartSpeedBoostManager()
	self:FetchPlayerClass()

	-- Handle movement input
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		self:HandleInput(input, gameProcessed)
	end)

	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		self:HandleInputEnded(input, gameProcessed)
	end)

	player.CharacterAdded:Connect(function(newCharacter)
		self:StopSpeedBoostManager()
		self:UpdateCharacterReferences(newCharacter)
		self:PreloadDashAnimations()
		self:PreloadRunAnimation()
		self:StartSpeedBoostManager()
		self:FetchPlayerClass()
		if humanoid and humanoid.Parent then humanoid.AutoRotate = true end

		-- Reset running state when character respawns
		if isRunning then
			isRunning = false
			runRequest:FireServer(false)
		end
	end)

	player.CharacterRemoving:Connect(function()
		self:StopSpeedBoostManager()
		isRunning = false
	end)

	print("[MovementController] Initialized")
end

-- Fetch player's class
function MovementController:FetchPlayerClass()
	local success, result = pcall(function()
		local classRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GameRemotes"):FindFirstChild("GetPlayerClass")
		if classRemote and classRemote:IsA("RemoteFunction") then
			return classRemote:InvokeServer()
		end
		local playerData = ReplicatedStorage:FindFirstChild("PlayerData")
		if playerData and playerData:FindFirstChild(player.Name) then
			return playerData[player.Name]:GetAttribute("Class")
		end
		return nil
	end)

	if success and result then
		playerClass = result
		print("[MovementController] Player class set to:", playerClass)
	else
		task.wait(0.1)
		if humanoid and humanoid:GetAttribute("Class") then
			playerClass = humanoid:GetAttribute("Class")
			print("[MovementController] Player class fetched from attribute:", playerClass)
		else
			local uiRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UIRemotes")
			local classAssigned = uiRemotes:FindFirstChild("ClassAssigned")
			if classAssigned then
				local conn
				conn = classAssigned.OnClientEvent:Connect(function(className, classInfo)
					playerClass = className
					print("[MovementController] Player class updated via event:", playerClass)
					if conn then conn:Disconnect() end
				end)
			end
			print("[MovementController] Unable to fetch player class immediately, waiting for event or attribute.")
		end
	end
end

-- Start Client-Side Speed Boost Manager
function MovementController:StartSpeedBoostManager()
	if heartbeatConnection then return end
	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		if not humanoid or not humanoid.Parent or isDashing then return end

		-- จัดการ Thief Special Boost
		local boostEndTime = humanoid:GetAttribute(THIEF_BOOST_ENDTIME_ATTR)
		if boostEndTime and typeof(boostEndTime) == "number" then
			if tick() < boostEndTime then
				local boostedSpeed = humanoid:GetAttribute(THIEF_BOOST_SPEED_ATTR)
				if boostedSpeed and typeof(boostedSpeed) == "number" then
					if math.abs(humanoid.WalkSpeed - boostedSpeed) > 0.1 then humanoid.WalkSpeed = boostedSpeed end
				end
			else
				local originalSpeed = humanoid:GetAttribute(ORIGINAL_SPEED_ATTR) or DEFAULT_WALKSPEED
				if math.abs(humanoid.WalkSpeed - originalSpeed) > 0.1 then humanoid.WalkSpeed = originalSpeed end
				if not humanoid.AutoRotate then humanoid.AutoRotate = true end

				-- ล้างแอตทริบิวต์
				humanoid:SetAttribute(THIEF_BOOST_ENDTIME_ATTR, nil)
				humanoid:SetAttribute(THIEF_BOOST_SPEED_ATTR, nil)
				humanoid:SetAttribute(ORIGINAL_SPEED_ATTR, nil)
			end

			-- จัดการ Running Boost
		else
			local runEndTime = humanoid:GetAttribute(RUN_BOOST_ENDTIME_ATTR)
			if runEndTime and typeof(runEndTime) == "number" then
				if tick() < runEndTime then
					local runSpeed = humanoid:GetAttribute(RUN_BOOST_SPEED_ATTR)
					if runSpeed and typeof(runSpeed) == "number" then
						-- ตรวจสอบว่าความเร็วถูกต้องหรือไม่
						if math.abs(humanoid.WalkSpeed - runSpeed) > 0.1 then 
							humanoid.WalkSpeed = runSpeed
							print("[MovementController] Maintaining run speed: " .. runSpeed)
						end
					end
				else
					-- หมดเวลาวิ่ง (ไม่น่าเกิดขึ้น เพราะการวิ่งควรหยุดจากฟังก์ชันอื่น)
					humanoid.WalkSpeed = DEFAULT_WALKSPEED
					humanoid:SetAttribute(RUN_BOOST_ENDTIME_ATTR, nil)
					humanoid:SetAttribute(RUN_BOOST_SPEED_ATTR, nil)
					humanoid:SetAttribute(ORIGINAL_SPEED_ATTR, nil)

					-- หากยังมีการวิ่งอยู่ ให้หยุดวิ่ง
					if isRunning then
						isRunning = false
						runRequest:FireServer(false)
						if runAnimation then
							runAnimation:Stop()
						end
					end
					print("[MovementController] Run timeout - resetting speed")
				end
			end 
		end
	end)
end

-- Stop Client-Side Speed Boost Manager
function MovementController:StopSpeedBoostManager()
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
		if humanoid and humanoid.Parent then
			humanoid.WalkSpeed = humanoid:GetAttribute(ORIGINAL_SPEED_ATTR) or DEFAULT_WALKSPEED
			humanoid.AutoRotate = true
		end
	end
end

-- Update character references
function MovementController:UpdateCharacterReferences(newCharacter)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid")
	animator = humanoid:WaitForChild("Animator")
	isDashing = false
	if humanoid and humanoid.Parent then humanoid.AutoRotate = true end
end

-- Preload dash animations
function MovementController:PreloadDashAnimations()
	if not animator then return end
	for _, t in pairs(dashAnimations) do if t then t:Destroy() end end
	dashAnimations = {}
	local ids = {
		Front = "rbxassetid://14103831900", Back = "rbxassetid://14103833544",
		Left = "rbxassetid://14103834807", Right = "rbxassetid://14103836416"
	}
	for d, id in pairs(ids) do
		local a = Instance.new("Animation"); a.AnimationId = id
		local t = animator:LoadAnimation(a)
		if t then t.Priority = Enum.AnimationPriority.Action; t.Looped = false; dashAnimations[d] = t end
		a:Destroy()
	end
end

-- Preload running animation
function MovementController:PreloadRunAnimation()
	if not animator then return end

	-- Clear existing animation if any
	if runAnimation then 
		runAnimation:Stop()
		runAnimation:Destroy() 
		runAnimation = nil
	end

	-- Create and load running animation
	local anim = Instance.new("Animation")
	anim.AnimationId = RUN_ANIM_ID
	runAnimation = animator:LoadAnimation(anim)

	if runAnimation then
		runAnimation.Priority = Enum.AnimationPriority.Movement
		runAnimation.Looped = true
		print("[MovementController] Running animation loaded")
	else
		warn("[MovementController] Failed to load running animation")
	end

	anim:Destroy()
end

-- Connect remote events
function MovementController:ConnectRemoteEvents()
	dashEffect.OnClientEvent:Connect(function(direction, effectType, effectColor, animationId, playerSource, dashType, dashDuration)
		if not character or not humanoid or not animator then return end

		if direction == "Complete" then
			isDashing = false
			if humanoid and humanoid.Parent then humanoid.AutoRotate = true end

			-- ล้างค่าความเร็วและแอตทริบิวต์ออกทั้งหมด
			humanoid.WalkSpeed = DEFAULT_WALKSPEED
			humanoid:SetAttribute(ORIGINAL_SPEED_ATTR, nil)

			-- รีเซ็ตสถานะการวิ่งให้เป็น false เสมอหลัง dash
			if isRunning then
				print("[MovementController] Resetting running state after dash")
				isRunning = false
				runRequest:FireServer(false)
				if runAnimation then
					runAnimation:Stop()
				end
			end

			return
		end

		if playerSource and playerSource ~= player then
			if effectType == "Vanish" then
				self:PlayOtherPlayerVanishEffect(playerSource, direction, effectColor, dashDuration)
			end
			return
		end

		-- ถ้ากำลังวิ่งอยู่ให้หยุดวิ่งก่อนเริ่ม dash
		if isRunning then
			isRunning = false
			runRequest:FireServer(false)
			if runAnimation then
				runAnimation:Stop()
			end
		end

		isDashing = true
		self:PlayDashEffect(direction, effectType, effectColor, animationId, dashDuration)
	end)

	setCombatStateEvent.OnClientEvent:Connect(function(isActive, duration)
		combatActive = isActive
		print("[MovementController] Combat state changed to:", combatActive)

		if not isActive then
			self:UpdateRegularCooldown(0)
			self:UpdateSpecialCooldown(0)
			if humanoid and humanoid.Parent then humanoid.AutoRotate = true end
			print("[MovementController] Combat ended, ensuring AutoRotate is enabled.")

			-- หยุดวิ่งเมื่อโหมดต่อสู้สิ้นสุด
			if isRunning then
				self:SetRunningState(false)
			end
		else
			print("[MovementController] Combat started.")
			if humanoid and humanoid.Parent then humanoid.AutoRotate = true end
		end
	end)

	-- Handle run state updates from server
	runState.OnClientEvent:Connect(function(playerId, runningState)
		if playerId == player.UserId then
			local wasRunning = isRunning
			isRunning = runningState

			print("[MovementController] Received running state from server:", isRunning)

			-- Only update effects if state actually changed
			if wasRunning ~= isRunning then
				self:UpdateRunningEffects()
			end
		end
	end)

	-- Set up cooldown events
	dashCooldownEvent.OnClientEvent:Connect(function(cooldownTime, dashType)
		if dashType == "Default" then 
			self:UpdateRegularCooldown(cooldownTime)
		elseif dashType == "Special" then 
			self:UpdateSpecialCooldown(cooldownTime)
		end
	end)

	-- ตั้งค่า RemoteEvent สำหรับรับค่าความเร็วโดยตรงจาก Server
	local setSpeedEvent = combatRemotes:FindFirstChild("SetSpeed")
	if not setSpeedEvent then
		setSpeedEvent = Instance.new("RemoteEvent")
		setSpeedEvent.Name = "SetSpeed"
		setSpeedEvent.Parent = combatRemotes
	end

	-- รับค่าความเร็วจาก server
	setSpeedEvent.OnClientEvent:Connect(function(speed)
		if humanoid and humanoid.Parent then
			print("[MovementController] Setting speed from server:", speed)
			humanoid.WalkSpeed = speed
		end
	end)
end

-- Handle input
function MovementController:HandleInput(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	-- Debug: print current combat state when W is pressed
	if input.KeyCode == RUN_KEY then
		print("[MovementController] W pressed. Combat active:", combatActive, "isDashing:", isDashing, "isRunning:", isRunning)
	end

	-- Dash controls (only in combat)
	if combatActive and not isDashing then
		if input.KeyCode == DASH_KEY then
			if playerClass == "Thief" and specialDashCooldown > 0 then return end
			if isRunning then
				-- ถ้ากำลังวิ่งอยู่ให้หยุดวิ่งก่อนใช้ dash
				self:SetRunningState(false)
				task.wait(0.05) -- รอเล็กน้อยเพื่อให้การหยุดวิ่งทำงานเสร็จก่อน
			end
			self:TryRegularDash()
		elseif input.KeyCode == SPECIAL_DASH_KEY and playerClass == "Thief" then
			if regularDashCooldown > 0 then return end
			-- ถ้ากำลังวิ่งอยู่ จะไม่สามารถใช้สกิลพิเศษได้
			if isRunning then
				print("[MovementController] Can't use special dash while running")
				return
			end
			self:TrySpecialDash()
		end
	end

	-- Running control (double-tap W) - ทำงานเฉพาะในโหมดต่อสู้เท่านั้น
	if input.KeyCode == RUN_KEY then
		-- ตรวจสอบว่าอยู่ในโหมดต่อสู้หรือไม่
		if not combatActive then
			print("[MovementController] Can't run - Not in combat mode")
			return
		end

		-- ตรวจสอบว่าไม่ได้กำลัง dash
		if isDashing then 
			print("[MovementController] Can't run while dashing")
			return
		end

		local currentTime = tick()

		-- Check if this is a double-tap
		if currentTime - lastWKeyPressTime < DOUBLE_TAP_WINDOW then
			wKeyPressCount = wKeyPressCount + 1

			-- Double-tap detected
			if wKeyPressCount >= 2 and not isRunning then
				print("[MovementController] Double-tap W detected - Activating running")
				self:SetRunningState(true)
				wKeyPressCount = 0
			end
		else
			-- First tap within window
			wKeyPressCount = 1
		end

		lastWKeyPressTime = currentTime
	end

	-- Stop running if S is pressed
	if input.KeyCode == Enum.KeyCode.S and isRunning then
		print("[MovementController] S pressed while running - Stopping run")
		self:SetRunningState(false)
	end
end

-- Handle input ended
function MovementController:HandleInputEnded(input, gameProcessed)
	-- Reset running when movement keys are released
	if isRunning and input.UserInputType == Enum.UserInputType.Keyboard then
		-- หยุดวิ่งเมื่อปล่อยปุ่มเคลื่อนที่ใดๆ (W, A, S, D)
		if input.KeyCode == RUN_KEY or 
			input.KeyCode == Enum.KeyCode.A or 
			input.KeyCode == Enum.KeyCode.S or 
			input.KeyCode == Enum.KeyCode.D then

			-- ตรวจสอบว่ายังมีการกดปุ่มเคลื่อนที่อื่นอยู่หรือไม่
			local anyMovementKeyPressed = UserInputService:IsKeyDown(Enum.KeyCode.A) or 
				UserInputService:IsKeyDown(Enum.KeyCode.S) or 
				UserInputService:IsKeyDown(Enum.KeyCode.D) or
				UserInputService:IsKeyDown(Enum.KeyCode.W)

			if not anyMovementKeyPressed then
				print("[MovementController] Released movement key - Stopping run")
				self:SetRunningState(false)
			end
		end
	end
end

-- Set running state
function MovementController:SetRunningState(state)
	print("[MovementController] Trying to set running state to:", state, "Current state:", isRunning)

	if isRunning == state then return end

	-- Handle visuals client-side first for responsive feedback
	local wasRunning = isRunning
	isRunning = state

	-- Update local effects immediately
	self:UpdateRunningEffects()

	-- Notify server about running state change
	print("[MovementController] Sending running state to server:", isRunning)
	runRequest:FireServer(isRunning)

	-- Server will eventually confirm with runState event
end

-- Clean up after dash
function MovementController:CleanupAfterDash()
	-- เวลา dash เสร็จแล้วให้ยกเลิกค่า ORIGINAL_SPEED_ATTR เพื่อให้สามารถกำหนดค่าใหม่ได้เมื่อเริ่มวิ่ง
	if humanoid then
		-- ลบแอตทริบิวต์ความเร็วต้นฉบับ (ถ้ามี) เพื่อเริ่มต้นใหม่
		if humanoid:GetAttribute(ORIGINAL_SPEED_ATTR) then
			humanoid:SetAttribute(ORIGINAL_SPEED_ATTR, nil)
		end
	end
end

-- Update running visual effects (with animation)
function MovementController:UpdateRunningEffects()
	if isRunning then
		print("[MovementController] Running started - Playing animation")

		-- กำหนดความเร็วการวิ่งตามคลาส (คล้ายกับฝั่ง server)
		local runSpeedMultiplier = 1.0
		if playerClass == "Thief" then
			runSpeedMultiplier = 1.8
		elseif playerClass == "Warrior" then
			runSpeedMultiplier = 1.7
		elseif playerClass == "Mage" then
			runSpeedMultiplier = 1.5
		end

		-- คำนวณความเร็ววิ่ง
		local runSpeed = DEFAULT_WALKSPEED * runSpeedMultiplier
		local runEndTime = tick() + 3600 -- 1 ชั่วโมง (ตั้งค่านานๆ เพื่อให้ SpeedBoostManager ทำงานตลอด)

		-- ตั้งค่า Attributes สำหรับการวิ่ง (คล้ายกับ Vanish)
		humanoid:SetAttribute(ORIGINAL_SPEED_ATTR, DEFAULT_WALKSPEED)
		humanoid:SetAttribute(RUN_BOOST_SPEED_ATTR, runSpeed)
		humanoid:SetAttribute(RUN_BOOST_ENDTIME_ATTR, runEndTime)

		-- ตั้งค่าความเร็วโดยตรง
		humanoid.WalkSpeed = runSpeed
		print("[MovementController] Set run speed to: " .. runSpeed)

		-- Play running animation
		if runAnimation then
			runAnimation:Play()
			runAnimation:AdjustSpeed(1.0)  -- ปรับความเร็วอนิเมชั่นให้เหมาะสม
		end
	else
		print("[MovementController] Running stopped - Stopping animation")

		-- คืนค่าความเร็วเป็นค่าเริ่มต้น
		humanoid.WalkSpeed = DEFAULT_WALKSPEED

		-- ล้างแอตทริบิวต์
		humanoid:SetAttribute(RUN_BOOST_ENDTIME_ATTR, nil)
		humanoid:SetAttribute(RUN_BOOST_SPEED_ATTR, nil)
		humanoid:SetAttribute(ORIGINAL_SPEED_ATTR, nil)

		-- Stop running animation
		if runAnimation then
			runAnimation:Stop()
		end
	end
end

-- Try regular dash / special dash logic
function MovementController:TryRegularDash()
	if isDashing or regularDashCooldown > 0 then return end
	if not character or not humanoid or not humanoid.RootPart then return end
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Dead then return end
	local dir = self:GetDashDirection()
	dashRequest:FireServer(dir)
end

function MovementController:TrySpecialDash()
	if isDashing or specialDashCooldown > 0 then return end
	if playerClass ~= "Thief" then return end
	if not character or not humanoid or not humanoid.RootPart then return end
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Dead then return end
	local dir = self:GetDashDirection()
	specialDashRequest:FireServer(dir)
end

function MovementController:GetDashDirection()
	if not character or not character:FindFirstChild("HumanoidRootPart") then return "Front" end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	local cameraLook = camera.CFrame.LookVector
	local characterLook = hrp.CFrame.LookVector
	local dotProduct = cameraLook:Dot(characterLook)
	local isCharacterFacingAway = (dotProduct < -0.1)
	local keyW = UserInputService:IsKeyDown(Enum.KeyCode.W); local keyS = UserInputService:IsKeyDown(Enum.KeyCode.S)
	local keyA = UserInputService:IsKeyDown(Enum.KeyCode.A); local keyD = UserInputService:IsKeyDown(Enum.KeyCode.D)
	if isCharacterFacingAway then
		if keyS then return "Front" elseif keyW then return "Back"
		elseif keyA then return "Right" elseif keyD then return "Left"
		else return "Front" end
	else
		if keyS then return "Back" elseif keyA then return "Left"
		elseif keyD then return "Right" elseif keyW then return "Front"
		else return "Front" end
	end
end

-- Cooldown update logic
function MovementController:UpdateRegularCooldown(newCooldown)
	regularDashCooldown = newCooldown
	if regularDashCooldown <= 0 then regularDashCooldown = 0; return end
	local startTime = tick(); local connection
	connection = RunService.Heartbeat:Connect(function()
		if not connection then return end
		local elapsed = tick() - startTime; local remaining = newCooldown - elapsed
		if remaining <= 0 then regularDashCooldown = 0; if connection then connection:Disconnect(); connection = nil end
		else regularDashCooldown = remaining end
	end)
end

function MovementController:UpdateSpecialCooldown(newCooldown)
	specialDashCooldown = newCooldown
	if specialDashCooldown <= 0 then specialDashCooldown = 0; return end
	local startTime = tick(); local connection
	connection = RunService.Heartbeat:Connect(function()
		if not connection then return end
		local elapsed = tick() - startTime; local remaining = newCooldown - elapsed
		if remaining <= 0 then specialDashCooldown = 0; if connection then connection:Disconnect(); connection = nil end
		else specialDashCooldown = remaining end
	end)
end

-- Play dash effect
function MovementController:PlayDashEffect(direction, effectType, effectColor, animationId, dashDuration)
	if animationId and effectType ~= "Vanish" then
		local t = dashAnimations[direction]
		if t then t:Stop(0); t:Play(0.1) else warn("Anim not found:", direction) end
	end

	if effectType == "Roll" then
		self:PlayNewRollEffect(effectColor)
	elseif effectType == "Vanish" then
		self:PlayVanishEffect(effectColor, dashDuration)
	end
end

-- PlayNewRollEffect
function MovementController:PlayNewRollEffect(effectColor)
	if not character or not humanoid then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Find the VFX folder and the specific DashVFX assets
	local vfxFolder = ReplicatedStorage:FindFirstChild("VFX")
	local dashVfxSource = vfxFolder and vfxFolder:FindFirstChild("DashVFX")
	if not dashVfxSource then
		warn("[MovementController] Could not find VFX/DashVFX in ReplicatedStorage")
		return
	end

	local line1Source = dashVfxSource:FindFirstChild("Line1")
	local line2Source = dashVfxSource:FindFirstChild("Line2")

	if not line1Source or not line2Source then
		warn("[MovementController] Could not find Line1 or Line2 inside DashVFX")
		return
	end

	-- Clone, parent, and schedule cleanup for Line1
	local line1Clone = line1Source:Clone()
	line1Clone.Parent = hrp
	-- Optional: Apply color if the effect supports it (e.g., ParticleEmitter)
	for _, descendant in ipairs(line1Clone:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Color = ColorSequence.new(effectColor)
			descendant:Emit(descendant.Rate * ROLL_VFX_LIFETIME) -- Emit particles for the duration
		end
	end
	Debris:AddItem(line1Clone, ROLL_VFX_LIFETIME) -- Remove after specified lifetime

	-- Clone, parent, and schedule cleanup for Line2
	local line2Clone = line2Source:Clone()
	line2Clone.Parent = hrp
	-- Optional: Apply color
	for _, descendant in ipairs(line2Clone:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Color = ColorSequence.new(effectColor)
			descendant:Emit(descendant.Rate * ROLL_VFX_LIFETIME)
		end
	end
	Debris:AddItem(line2Clone, ROLL_VFX_LIFETIME)

	print("[MovementController] Played new Roll VFX") -- Debug
end

-- Play vanish effect (Uses dashDuration passed from server)
function MovementController:PlayVanishEffect(effectColor, dashDuration)
	if not character or not humanoid then return end
	local effectTime = (typeof(dashDuration) == "number" and dashDuration > 0) and dashDuration or 0.25
	print("[MovementController] Playing Vanish effect for duration:", effectTime)

	local originalTransparency = {}
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") or part:IsA("Decal") then
			originalTransparency[part] = part.LocalTransparencyModifier
			TweenService:Create(part, TweenInfo.new(0.1), {LocalTransparencyModifier = 1}):Play()
		end
	end

	local vfx = ReplicatedStorage:FindFirstChild("VFX")
	local soru = vfx and vfx:FindFirstChild("soru")
	local hrp = character:FindFirstChild("HumanoidRootPart")

	if soru and hrp then
		local ring = soru:FindFirstChild("Ring"); local soru1 = soru:FindFirstChild("Soru1"); local soru2 = soru:FindFirstChild("Soru2")
		if ring then local c = ring.SoruRing:Clone(); c.Parent = hrp; for _, p in ipairs(c:GetDescendants()) do if p:IsA("ParticleEmitter") then p.Color = ColorSequence.new(effectColor) end end; Debris:AddItem(c, 1.5) end
		if soru1 then local c = soru1:Clone(); c.Parent = hrp; Debris:AddItem(c, 1.5) end
		task.delay(effectTime, function()
			if not character or not character.Parent then return end
			for part, originalTransp in pairs(originalTransparency) do if part and part.Parent then TweenService:Create(part, TweenInfo.new(0.15), {LocalTransparencyModifier = originalTransp}):Play() end end
			if soru2 and hrp and hrp.Parent then local c = soru2:Clone(); c.Parent = hrp; Debris:AddItem(c, 1.5) end
		end)
	else
		warn("VFX/soru not found.")
		task.delay(effectTime, function()
			if not character or not character.Parent then return end
			for part, originalTransp in pairs(originalTransparency) do if part and part.Parent then TweenService:Create(part, TweenInfo.new(0.15), {LocalTransparencyModifier = originalTransp}):Play() end end
		end)
	end
end

-- Play other player vanish effect (Uses dashDuration passed from server)
function MovementController:PlayOtherPlayerVanishEffect(playerSource, direction, effectColor, dashDuration)
	local otherCharacter = playerSource.Character; if not otherCharacter then return end
	local hrp = otherCharacter:FindFirstChild("HumanoidRootPart"); if not hrp then return end
	local effectTime = (typeof(dashDuration) == "number" and dashDuration > 0) and dashDuration or 0.25

	local originalTransparency = {}
	for _, part in pairs(otherCharacter:GetDescendants()) do
		if part:IsA("BasePart") or part:IsA("Decal") then
			originalTransparency[part] = part.LocalTransparencyModifier
			TweenService:Create(part, TweenInfo.new(0.1), {LocalTransparencyModifier = 1}):Play()
		end
	end

	local vfx = ReplicatedStorage:FindFirstChild("VFX"); local soru = vfx and vfx:FindFirstChild("soru")
	if soru then
		local ring = soru:FindFirstChild("Ring"); local soru1 = soru:FindFirstChild("Soru1"); local soru2 = soru:FindFirstChild("Soru2")
		if ring then local c = ring:Clone(); c.Parent = hrp; for _, p in ipairs(c:GetDescendants()) do if p:IsA("ParticleEmitter") then p.Color = ColorSequence.new(effectColor) end end; Debris:AddItem(c, 1.5) end
		if soru1 then local c = soru1:Clone(); c.Parent = hrp; Debris:AddItem(c, 1.5) end
		task.delay(effectTime, function()
			if not otherCharacter or not otherCharacter.Parent then return end
			for part, originalTransp in pairs(originalTransparency) do if part and part.Parent then TweenService:Create(part, TweenInfo.new(0.15), {LocalTransparencyModifier = originalTransp}):Play() end end
			if soru2 and hrp and hrp.Parent then local c = soru2:Clone(); c.Parent = hrp; Debris:AddItem(c, 1.5) end
		end)
	else
		task.delay(effectTime, function()
			if not otherCharacter or not otherCharacter.Parent then return end
			for part, originalTransp in pairs(originalTransparency) do if part and part.Parent then TweenService:Create(part, TweenInfo.new(0.15), {LocalTransparencyModifier = originalTransp}):Play() end end
		end)
	end
end

-- Initialize
local controller = MovementController
MovementController:Initialize()

return MovementController
