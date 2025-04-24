-- MovementController.lua
-- Client-side controller for movement abilities (Dash, Run)
-- Version: 2.0.5 (Robust cooldown handling, Fixed dash direction logic)

local MovementController = {}
MovementController.__index = MovementController

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ContextActionService = game:GetService("ContextActionService")

-- Constants
local DASH_KEY = Enum.KeyCode.Q
local SPECIAL_DASH_KEY = Enum.KeyCode.R
local RUN_KEY = Enum.KeyCode.W
local STOP_RUN_KEY = Enum.KeyCode.S

-- Attribute Names
local ATTR_CLASS = "Class" -- ชื่อ Attribute ที่ Client จะอ่านค่า Class

-- Dash Types (ควรตรงกับ Server)
local DASH_TYPE_DEFAULT = "Default"
local DASH_TYPE_SPECIAL = "Special"

-- Dash Effects (ควรตรงกับ Server)
local EFFECT_ROLL = "Roll"
local EFFECT_VANISH = "Vanish"

-- Dash Directions (ควรตรงกับ Server)
local DIR_FRONT = "Front"
local DIR_BACK = "Back"
local DIR_LEFT = "Left"
local DIR_RIGHT = "Right"

-- Running Constants
local DOUBLE_TAP_WINDOW = 0.28 -- เวลาที่ยอมรับการกด W ซ้ำ (วินาที)
local RUN_ANIM_ID = "rbxassetid://13836330574" -- ID Animation วิ่ง (ใส่ ID ของคุณ)
local RUN_ANIM_FADE_TIME = 0.15 -- เวลา Fade In/Out ของ Animation วิ่ง

-- VFX Constants
local ROLL_VFX_LIFETIME = 0.4 -- ระยะเวลาแสดงผล VFX ของ Roll
local VANISH_APPEAR_DELAY = 0.1 -- Delay ก่อนแสดงตัวตอน Vanish จบ

-- Variables
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")

-- State Variables
local regularDashCooldown = 0 -- Cooldown ของ Dash ปกติ (Initialize เป็น 0 เสมอ)
local specialDashCooldown = 0 -- Cooldown ของ Dash พิเศษ (Initialize เป็น 0 เสมอ)
local isDashing = false -- สถานะว่ากำลัง Dash อยู่หรือไม่
local isRunning = false -- สถานะว่ากำลังวิ่งอยู่หรือไม่ (สำหรับ Animation/Input)
local combatActive = false -- สถานะ Combat Mode
local playerClass = "Unknown" -- คลาสปัจจุบันของผู้เล่น (เริ่มต้นเป็น Unknown)
local classFetchConnection = nil -- Connection สำหรับรอ Event ClassAssigned

-- Animation Tracks
local dashAnimations = {} -- เก็บ Animation Tracks ของ Dash แต่ละทิศทาง
local runAnimationTrack = nil -- เก็บ Animation Track ของการวิ่ง

-- Double-tap detection variables
local lastWKeyPressTime = 0 -- เวลาที่กด W ครั้งล่าสุด (Initialize เป็น 0)
local wKeyPressCount = 0 -- จำนวนครั้งที่กด W ในช่วงเวลาสั้นๆ

-- Cooldown Update Connections (สำหรับ Heartbeat)
local regularCooldownConnection = nil
local specialCooldownConnection = nil

-- Remote Events (หาจาก ReplicatedStorage)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local combatRemotes = remotes:WaitForChild("CombatRemotes")
local dashRequest = combatRemotes:WaitForChild("DashRequest")
local specialDashRequest = combatRemotes:WaitForChild("SpecialDashRequest")
local dashEffect = combatRemotes:WaitForChild("DashEffect")
local dashCooldownEvent = combatRemotes:WaitForChild("DashCooldown")
local setCombatStateEvent = combatRemotes:WaitForChild("SetCombatState")
local runRequest = combatRemotes:WaitForChild("RunRequest")

-- Event สำหรับ Class Assignment (เพื่อให้ Client รู้ Class)
local uiRemotes = remotes:FindFirstChild("UIRemotes") or Instance.new("Folder", remotes)
uiRemotes.Name = "UIRemotes"
local classAssignedEvent = uiRemotes:FindFirstChild("ClassAssigned") or Instance.new("RemoteEvent", uiRemotes)
classAssignedEvent.Name = "ClassAssigned"

-- Preloaded VFX Assets (หาจาก ReplicatedStorage)
local vfxFolder = ReplicatedStorage:WaitForChild("VFX")
local dashVfxSource = vfxFolder and vfxFolder:FindFirstChild("DashVFX")
local soruVfxSource = vfxFolder and vfxFolder:FindFirstChild("soru")

-- Initialize the controller
function MovementController:Initialize()
	print("[MovementController] Initializing...")
	self:UpdateCharacterReferences(character) -- ตั้งค่า References เริ่มต้น
	self:PreloadAssets() -- โหลด Animation และตรวจสอบ VFX
	self:ConnectRemoteEvents() -- เชื่อมต่อ Remote Events
	self:ConnectInputHandlers() -- เชื่อมต่อ Input Events
	self:FetchPlayerClass() -- เริ่มกระบวนการรับค่า Class

	-- ตั้งค่าเริ่มต้นให้ตัวแปร State อย่างชัดเจน
	lastWKeyPressTime = 0
	wKeyPressCount = 0
	regularDashCooldown = 0
	specialDashCooldown = 0
	isDashing = false
	isRunning = false
	combatActive = false
	playerClass = "Unknown"

	-- Handle character respawn
	player.CharacterAdded:Connect(function(newCharacter)
		print("[MovementController] Character Added.")
		self:UpdateCharacterReferences(newCharacter)
		self:PreloadAssets() -- โหลดใหม่
		self:FetchPlayerClass() -- เริ่มรอ Class ใหม่

		-- Reset local states on respawn อย่างชัดเจน
		isDashing = false
		isRunning = false
		wKeyPressCount = 0
		lastWKeyPressTime = 0
		regularDashCooldown = 0
		specialDashCooldown = 0
		playerClass = "Unknown"
		-- Disconnect old cooldown timers if they exist from previous character
		if regularCooldownConnection then regularCooldownConnection:Disconnect(); regularCooldownConnection = nil end
		if specialCooldownConnection then specialCooldownConnection:Disconnect(); specialCooldownConnection = nil end
	end)

	-- Handle character removal (optional cleanup)
	player.CharacterRemoving:Connect(function(oldCharacter)
		print("[MovementController] Character Removing.")
		-- Stop animations
		if runAnimationTrack and runAnimationTrack.IsPlaying then runAnimationTrack:Stop(0) end
		-- Disconnect connections
		if regularCooldownConnection then regularCooldownConnection:Disconnect(); regularCooldownConnection = nil end
		if specialCooldownConnection then specialCooldownConnection:Disconnect(); specialCooldownConnection = nil end
		if classFetchConnection then classFetchConnection:Disconnect(); classFetchConnection = nil end
	end)

	print("[MovementController] Initialized.")
end

-- Update references to the current character and its components
function MovementController:UpdateCharacterReferences(newCharacter)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid")
	animator = humanoid:WaitForChild("Animator")
	-- Ensure AutoRotate is enabled by default
	if humanoid and humanoid.Parent then humanoid.AutoRotate = true end
	print("[MovementController] Updated character references.")
end

-- Preload animations and check for VFX existence
function MovementController:PreloadAssets()
	if not animator then print("[MovementController] PreloadAssets: Animator not found."); return end

	-- Preload Dash Animations
	for _, track in pairs(dashAnimations) do if track then track:Destroy() end end
	dashAnimations = {}
	local dashAnimIds = {
		[DIR_FRONT] = "rbxassetid://14103831900", [DIR_BACK] = "rbxassetid://14103833544",
		[DIR_LEFT] = "rbxassetid://14103834807", [DIR_RIGHT] = "rbxassetid://14103836416"
	}
	for direction, id in pairs(dashAnimIds) do
		-- ใช้ pcall เพื่อป้องกัน Error หาก Animation ID ไม่ถูกต้อง หรือโหลดไม่ได้
		local success, track = pcall(function()
			local anim = Instance.new("Animation"); anim.AnimationId = id
			local loadedTrack = animator:LoadAnimation(anim); anim:Destroy(); return loadedTrack
		end)
		if success and track then
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = false
			dashAnimations[direction] = track
		else
			warn("[MovementController] Failed to load dash animation:", id, "Error:", track)
		end
	end
	print("[MovementController] Dash animations preloaded.")

	-- Preload Running Animation
	if runAnimationTrack then runAnimationTrack:Destroy(); runAnimationTrack = nil end
	local success, track = pcall(function()
		local runAnim = Instance.new("Animation"); runAnim.AnimationId = RUN_ANIM_ID
		local loadedTrack = animator:LoadAnimation(runAnim); runAnim:Destroy(); return loadedTrack
	end)
	if success and track then
		runAnimationTrack = track
		runAnimationTrack.Priority = Enum.AnimationPriority.Movement -- หรือ Action ถ้าต้องการให้ทับท่าเดิน
		runAnimationTrack.Looped = true
		print("[MovementController] Running animation preloaded.")
	else
		warn("[MovementController] Failed to load running animation:", RUN_ANIM_ID, "Error:", track)
	end

	-- Check VFX existence (optional, good for debugging)
	if not dashVfxSource then warn("[MovementController] DashVFX folder not found in ReplicatedStorage/VFX") end
	if not soruVfxSource then warn("[MovementController] soru VFX folder not found in ReplicatedStorage/VFX") end
end

-- Connect to RemoteEvents from the server
function MovementController:ConnectRemoteEvents()
	-- Handle Dash Effects/Completion signals from Server
	dashEffect.OnClientEvent:Connect(function(directionOrSignal, effectType, effectColor, animationId, playerSource, dashType, dashDuration)
		-- ตรวจสอบว่าเป็น Signal "Complete" หรือไม่
		if directionOrSignal == "Complete" then
			isDashing = false -- อัปเดตสถานะ Dash ของ Client
			if humanoid and humanoid.Parent then humanoid.AutoRotate = true end -- เปิด AutoRotate คืน
			print("[MovementController] Received Dash Complete signal.")
			return
		end

		-- ถ้าเป็น Effect สำหรับผู้เล่นอื่น (เช่น Vanish)
		if playerSource and playerSource ~= player then
			if effectType == EFFECT_VANISH then
				self:PlayOtherPlayerVanishEffect(playerSource, effectColor, dashDuration)
			end
			return -- ไม่ต้องทำอะไรต่อสำหรับ Local Player
		end

		-- ถ้าเป็น Effect สำหรับ Local Player
		if not character or not humanoid or not animator then return end

		-- หยุดวิ่ง (Animation) ทันทีเมื่อเริ่ม Dash (Client-side prediction)
		if isRunning then
			isRunning = false -- อัปเดตสถานะ Client
			self:UpdateRunningAnimation() -- หยุด Animation วิ่งทันที
		end

		isDashing = true -- ตั้งสถานะกำลัง Dash (Client-side)
		if humanoid and humanoid.Parent then humanoid.AutoRotate = false end -- ปิด AutoRotate ชั่วคราว

		-- เล่น Effect และ Animation (ถ้ามี)
		self:PlayLocalDashEffect(directionOrSignal, effectType, effectColor, animationId, dashDuration)
		print(string.format("[MovementController] Playing local dash effect: %s, Type: %s, Duration: %.2f", directionOrSignal, effectType, dashDuration))
	end)

	-- Handle Combat State changes
	setCombatStateEvent.OnClientEvent:Connect(function(isActive, duration)
		local stateChanged = (combatActive ~= isActive)
		combatActive = isActive
		print("[MovementController] Combat state changed to:", combatActive)

		if stateChanged and not isActive then
			-- Combat สิ้นสุด: หยุดวิ่ง (ถ้ากำลังวิ่งอยู่)
			if isRunning then
				self:RequestSetRunningState(false) -- ส่งคำขอหยุดวิ่งไป Server
			end
			if humanoid and humanoid.Parent then humanoid.AutoRotate = true end
		elseif isActive then
			if humanoid and humanoid.Parent then humanoid.AutoRotate = true end -- Ensure autorotate is on when combat starts
		end
	end)

	-- Handle Cooldown updates from Server
	dashCooldownEvent.OnClientEvent:Connect(function(cooldownTime, dashType)
		-- *** เพิ่มการตรวจสอบประเภทข้อมูลที่นี่ ***
		if type(cooldownTime) ~= "number" then
			warn("[MovementController] Received invalid cooldown time type:", type(cooldownTime), "for dash type:", dashType)
			cooldownTime = 0 -- ตั้งเป็น 0 ถ้าค่าไม่ถูกต้อง
		end

		if dashType == DASH_TYPE_DEFAULT then
			self:UpdateRegularCooldown(cooldownTime)
		elseif dashType == DASH_TYPE_SPECIAL then
			self:UpdateSpecialCooldown(cooldownTime)
		end
		print(string.format("[MovementController] Received cooldown update: Type: %s, Time: %.2f", dashType, cooldownTime))
	end)
end

-- Connect keyboard/mouse input handlers
function MovementController:ConnectInputHandlers()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end -- ไม่ต้องทำอะไรถ้า Input ถูก xử lý โดย UI หรือระบบอื่นแล้ว
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

		local keyCode = input.KeyCode

		-- Dash Input (Q / R) - ต้องอยู่ใน Combat Mode และไม่ได้กำลัง Dash
		if combatActive and not isDashing then
			if keyCode == DASH_KEY then
				-- Check for Thief's special cooldown conflict
				-- ใช้ค่าที่เก็บไว้ในตัวแปรโดยตรง ไม่ต้องอ่านซ้ำ
				if playerClass == "Thief" and specialDashCooldown > 0 then
					print("[MovementController] Cannot use Default Dash, Special Dash is on cooldown.")
					return
				end
				-- ถ้ากำลังวิ่งอยู่ ให้ส่งคำขอหยุดวิ่ง *ก่อน* ส่งคำขอ Dash
				if isRunning then
					self:RequestSetRunningState(false)
					task.wait(0.05) -- รอเล็กน้อยให้ Server ประมวลผลการหยุดวิ่ง
				end
				self:TryRegularDash()

			elseif keyCode == SPECIAL_DASH_KEY and playerClass == "Thief" then
				-- Check for default cooldown conflict
				-- ใช้ค่าที่เก็บไว้ในตัวแปรโดยตรง
				if regularDashCooldown > 0 then
					print("[MovementController] Cannot use Special Dash, Default Dash is on cooldown.")
					return
				end
				-- ห้ามใช้ Special Dash ขณะวิ่ง
				if isRunning then
					print("[MovementController] Cannot use Special Dash while running.")
					return
				end
				self:TrySpecialDash()
			end
		end

		-- Running Input (Double-Tap W) - ต้องอยู่ใน Combat Mode และไม่ได้กำลัง Dash
		if keyCode == RUN_KEY then
			if not combatActive then return end -- ต้องอยู่ใน Combat
			if isDashing then return end -- ห้ามวิ่งขณะ Dash

			local currentTime = time() -- ใช้ time()
			-- Check type of lastWKeyPressTime before comparing
			if type(lastWKeyPressTime) == "number" and currentTime - lastWKeyPressTime < DOUBLE_TAP_WINDOW then
				wKeyPressCount = wKeyPressCount + 1
				if wKeyPressCount >= 2 and not isRunning then
					-- Double-tap detected! Request to start running.
					print("[MovementController] Double-tap W detected - Requesting run start.")
					self:RequestSetRunningState(true)
					wKeyPressCount = 0 -- Reset counter after successful double tap
				end
			else
				-- First tap or tap outside window
				wKeyPressCount = 1
			end
			lastWKeyPressTime = currentTime -- Update time after processing
		end

		-- Stop Running Input (S) - ถ้ากำลังวิ่งอยู่
		if keyCode == STOP_RUN_KEY and isRunning then
			print("[MovementController] S pressed - Requesting run stop.")
			self:RequestSetRunningState(false)
		end
	end)

	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if not isRunning then return end -- ทำงานเฉพาะตอนกำลังวิ่งอยู่
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

		-- หยุดวิ่งเมื่อปล่อยปุ่มเคลื่อนที่ *ทั้งหมด*
		local keyW = UserInputService:IsKeyDown(Enum.KeyCode.W)
		local keyA = UserInputService:IsKeyDown(Enum.KeyCode.A)
		local keyS = UserInputService:IsKeyDown(Enum.KeyCode.S)
		local keyD = UserInputService:IsKeyDown(Enum.KeyCode.D)

		if not keyW and not keyA and not keyS and not keyD then
			print("[MovementController] All movement keys released - Requesting run stop.")
			self:RequestSetRunningState(false)
		end
	end)
	print("[MovementController] Input handlers connected.")
end

-- Fetch player's class - Try attribute first, then wait for event
function MovementController:FetchPlayerClass()
	-- Disconnect previous listener if exists
	if classFetchConnection then
		classFetchConnection:Disconnect()
		classFetchConnection = nil
	end

	-- Try reading attribute immediately
	if humanoid and humanoid.Parent then
		local classAttr = humanoid:GetAttribute(ATTR_CLASS)
		if classAttr and typeof(classAttr) == "string" and classAttr ~= "" and classAttr ~= "Unknown" then
			playerClass = classAttr
			print("[MovementController] Player class fetched immediately from attribute:", playerClass)
			return -- Found it, no need to wait for event
		end
	end

	-- If attribute not found or invalid, wait for the ClassAssigned event
	playerClass = "Unknown" -- Set to unknown while waiting
	print("[MovementController] Class attribute not found or invalid. Waiting for ClassAssigned event...")

	-- Check if the event object is valid before connecting
	if classAssignedEvent and classAssignedEvent:IsA("RemoteEvent") then
		classFetchConnection = classAssignedEvent.OnClientEvent:Connect(function(assignedClassName)
			if assignedClassName and typeof(assignedClassName) == "string" and assignedClassName ~= "" then
				playerClass = assignedClassName
				print("[MovementController] Player class received via ClassAssigned event:", playerClass)
				-- Optional: Disconnect after receiving the class if it's only assigned once
				-- if classFetchConnection then classFetchConnection:Disconnect(); classFetchConnection = nil end
			else
				warn("[MovementController] Received invalid class name from ClassAssigned event:", assignedClassName)
			end
		end)
	else
		warn("[MovementController] ClassAssigned RemoteEvent object is not valid or not found.")
	end
end


-- Request server to change running state
function MovementController:RequestSetRunningState(state)
	-- ป้องกันการส่ง Request ซ้ำๆ ถ้าสถานะเหมือนเดิม (ยกเว้นกรณีต้องการ Force Stop)
	if isRunning == state and state == true then return end

	print("[MovementController] Requesting server to set running state:", state)
	runRequest:FireServer(state)

	-- Client-side prediction for smoother visuals
	if isRunning ~= state then
		isRunning = state
		self:UpdateRunningAnimation() -- อัปเดต Animation ทันที
	end
end

-- Update running animation based on the 'isRunning' state
function MovementController:UpdateRunningAnimation()
	if not runAnimationTrack then
		-- warn("[MovementController] Cannot update running animation: Track not loaded.")
		return
	end

	if isRunning then
		if not runAnimationTrack.IsPlaying then
			runAnimationTrack:Play(RUN_ANIM_FADE_TIME) -- Fade in
			runAnimationTrack:AdjustSpeed(1.0) -- ตั้งค่า Speed Animation (ปรับตามต้องการ)
			-- print("[MovementController] Playing running animation.")
		end
	else
		if runAnimationTrack.IsPlaying then
			runAnimationTrack:Stop(RUN_ANIM_FADE_TIME) -- Fade out
			-- print("[MovementController] Stopping running animation.")
		end
	end
end

-- Try to initiate a regular dash
function MovementController:TryRegularDash()
	-- Check type of regularCooldown before comparing
	-- ใช้ค่าที่เก็บไว้ในตัวแปร local โดยตรง
	if isDashing or (type(regularDashCooldown) == "number" and regularDashCooldown > 0) then
		-- print("[MovementController] Cannot regular dash: Dashing or on cooldown. Cooldown:", regularDashCooldown)
		return
	end
	if not self:CanDashOrRun() then return end

	local direction = self:GetDashDirection() -- เรียกใช้ฟังก์ชันที่แก้ไขแล้ว
	print("[MovementController] Requesting Regular Dash. Direction:", direction)
	dashRequest:FireServer(direction)
end

-- Try to initiate a special dash (Thief)
function MovementController:TrySpecialDash()
	-- Check type of specialCooldown before comparing
	-- ใช้ค่าที่เก็บไว้ในตัวแปร local โดยตรง
	if isDashing or (type(specialDashCooldown) == "number" and specialDashCooldown > 0) then
		-- print("[MovementController] Cannot special dash: Dashing or on cooldown. Cooldown:", specialDashCooldown)
		return
	end
	-- ตรวจสอบ Class อีกครั้งก่อนส่ง Request
	if playerClass ~= "Thief" then
		print("[MovementController] Cannot special dash: Player class is not Thief ("..playerClass..")")
		return
	end
	if not self:CanDashOrRun() then return end

	local direction = self:GetDashDirection() -- เรียกใช้ฟังก์ชันที่แก้ไขแล้ว
	print("[MovementController] Requesting Special Dash. Direction:", direction)
	specialDashRequest:FireServer(direction)
end


-- Check if the player is in a state where they can dash or run
function MovementController:CanDashOrRun()
	if not character or not humanoid or not humanoid.RootPart then return false end
	local state = humanoid:GetState()
	-- ไม่สามารถ Dash/Run ได้ในสถานะเหล่านี้
	if state == Enum.HumanoidStateType.Jumping or
		state == Enum.HumanoidStateType.Freefall or
		state == Enum.HumanoidStateType.Dead or
		state == Enum.HumanoidStateType.FallingDown or
		state == Enum.HumanoidStateType.Ragdoll or
		state == Enum.HumanoidStateType.Seated then
		-- print("[MovementController] Cannot dash/run in current state:", state)
		return false
	end
	return true
end

-- *** Simplified Dash Direction Logic ***
-- Determine the intended dash direction based *only* on WASD input relative to the character.
function MovementController:GetDashDirection()
	local keyW = UserInputService:IsKeyDown(Enum.KeyCode.W)
	local keyS = UserInputService:IsKeyDown(Enum.KeyCode.S)
	local keyA = UserInputService:IsKeyDown(Enum.KeyCode.A)
	local keyD = UserInputService:IsKeyDown(Enum.KeyCode.D)

	-- Prioritize Forward/Backward movement keys
	if keyW then
		return DIR_FRONT -- กด W -> Dash หน้า
	elseif keyS then
		return DIR_BACK -- กด S -> Dash หลัง
		-- If no Forward/Backward keys, check Left/Right
	elseif keyA then
		return DIR_LEFT -- กด A -> Dash ซ้าย
	elseif keyD then
		return DIR_RIGHT -- กด D -> Dash ขวา
		-- If no movement keys are pressed, default to Forward
	else
		return DIR_FRONT
	end
end


-- Update cooldown timer using RunService.Heartbeat (Helper function)
local function StartCooldownTimer(duration, callback)
	-- ถ้า duration เป็น 0 หรือน้อยกว่า ไม่ต้องสร้าง connection
	if duration <= 0 then
		callback(0)
		return nil -- No connection needed
	end

	local startTime = time() -- ใช้ time() เพื่อความแม่นยำ
	local connection = nil -- ประกาศ connection ไว้ข้างนอก

	connection = RunService.Heartbeat:Connect(function(dt)
		local elapsed = time() - startTime
		local remaining = duration - elapsed
		if remaining <= 0 then
			callback(0) -- ตั้งค่าเป็น 0 เมื่อหมดเวลา
			if connection then
				connection:Disconnect() -- Disconnect ตัวเอง
				connection = nil -- Clear reference
			end
		else
			callback(remaining) -- อัปเดตค่าที่เหลือ
		end
	end)
	callback(duration) -- อัปเดตค่าเริ่มต้นทันที
	return connection -- คืนค่า connection เพื่อให้ยกเลิกได้
end

-- *** NEW: Robust Cooldown Update Logic ***
-- Update Regular Dash Cooldown
function MovementController:UpdateRegularCooldown(newCooldown)
	-- Disconnect previous timer if exists
	if regularCooldownConnection then
		regularCooldownConnection:Disconnect()
		regularCooldownConnection = nil
	end

	-- Ensure newCooldown is a valid number, default to 0 if not
	if type(newCooldown) ~= "number" or newCooldown <= 0 then
		regularDashCooldown = 0 -- Set to 0 immediately
		-- Update UI to show 0 cooldown (if applicable)
		-- print("[MovementController] Regular Cooldown set to 0")
	else
		-- Start new timer only if cooldown > 0
		regularDashCooldown = newCooldown -- Set initial value for immediate check
		regularCooldownConnection = StartCooldownTimer(newCooldown, function(remaining)
			regularDashCooldown = remaining -- Update the variable as timer runs
			-- Update UI here if needed
		end)
		-- print("[MovementController] Regular Cooldown started:", newCooldown)
	end
end

-- Update Special Dash Cooldown
function MovementController:UpdateSpecialCooldown(newCooldown)
	-- Disconnect previous timer if exists
	if specialCooldownConnection then
		specialCooldownConnection:Disconnect()
		specialCooldownConnection = nil
	end

	-- Ensure newCooldown is a valid number, default to 0 if not
	if type(newCooldown) ~= "number" or newCooldown <= 0 then
		specialDashCooldown = 0 -- Set to 0 immediately
		-- Update UI to show 0 cooldown (if applicable)
		-- print("[MovementController] Special Cooldown set to 0")
	else
		-- Start new timer only if cooldown > 0
		specialDashCooldown = newCooldown -- Set initial value
		specialCooldownConnection = StartCooldownTimer(newCooldown, function(remaining)
			specialDashCooldown = remaining -- Update the variable
			-- Update UI here if needed
		end)
		-- print("[MovementController] Special Cooldown started:", newCooldown)
	end
end


-- Play local player's dash effects (Animation + VFX)
function MovementController:PlayLocalDashEffect(direction, effectType, effectColor, animationId, dashDuration)
	-- Play Animation (if applicable and not Vanish)
	if animationId and effectType ~= EFFECT_VANISH then
		local animTrack = dashAnimations[direction]
		if animTrack then
			-- Optional: Stop previous animation instance if overlapping?
			-- animTrack:Stop(0)
			animTrack:Play(0.1) -- Play with a short fade-in
			-- Optional: Adjust speed based on dash duration?
			-- animTrack:AdjustSpeed(animTrack.Length / dashDuration)
		else
			warn("[MovementController] Dash animation track not found for direction:", direction)
		end
	end

	-- Play VFX based on type
	if effectType == EFFECT_ROLL then
		self:PlayRollVFX(effectColor)
	elseif effectType == EFFECT_VANISH then
		self:PlayVanishVFX(effectColor, dashDuration) -- Pass duration for vanish timing
	end
end

-- Play Roll VFX
function MovementController:PlayRollVFX(effectColor)
	if not character or not humanoid or not dashVfxSource then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local line1Source = dashVfxSource:FindFirstChild("Line1")
	local line2Source = dashVfxSource:FindFirstChild("Line2")

	-- Function to clone, setup, and add VFX to Debris
	local function setupVfx(source, lifetime)
		if not source then return end
		local clone = source:Clone()
		clone.Parent = hrp
		for _, descendant in ipairs(clone:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
				-- Check if Color property exists before setting
				local success, _ = pcall(function() descendant.Color = ColorSequence.new(effectColor) end)
				-- Enable the effect
				descendant.Enabled = true
			end
		end
		Debris:AddItem(clone, lifetime)
	end

	-- Setup Line1 and Line2
	if line1Source then setupVfx(line1Source, ROLL_VFX_LIFETIME)
	else warn("[MovementController] Roll VFX 'Line1' not found.") end

	if line2Source then setupVfx(line2Source, ROLL_VFX_LIFETIME * 1.2) -- ให้เส้นที่สองอยู่นานกว่าเล็กน้อย
	else warn("[MovementController] Roll VFX 'Line2' not found.") end
end

-- Play Vanish VFX (Local Player)
function MovementController:PlayVanishVFX(effectColor, vanishDuration)
	if not character or not humanoid or not soruVfxSource then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local effectTime = (typeof(vanishDuration) == "number" and vanishDuration > 0) and vanishDuration or 0.25 -- Use duration from server
	local fadeOutTime = 0.1
	local fadeInTime = 0.15

	-- 1. Fade Out Character Parts
	local originalTransparency = {}
	for _, descendant in pairs(character:GetDescendants()) do
		-- Handle BaseParts and Decals
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			-- Store original modifier, default to 0 if nil
			originalTransparency[descendant] = descendant.LocalTransparencyModifier or 0
			-- Tween to fully transparent
			TweenService:Create(descendant, TweenInfo.new(fadeOutTime), {LocalTransparencyModifier = 1}):Play()
			-- Handle Accessories
		elseif descendant:IsA("Accessory") then
			local handle = descendant:FindFirstChild("Handle")
			if handle then
				originalTransparency[handle] = handle.LocalTransparencyModifier or 0
				TweenService:Create(handle, TweenInfo.new(fadeOutTime), {LocalTransparencyModifier = 1}):Play()
			end
		end
	end

	-- 2. Play Initial Vanish Effects (Ring, Soru1)
	local ringSource = soruVfxSource:FindFirstChild("Ring")
	local soru1Source = soruVfxSource:FindFirstChild("Soru1")
	local soru2Source = soruVfxSource:FindFirstChild("Soru2") -- Reappear effect

	-- Function to clone, setup, and add VFX to Debris
	local function setupVfx(source, lifetime)
		if not source then return end
		local clone = source:Clone()
		clone.Parent = hrp
		for _, p in ipairs(clone:GetDescendants()) do
			if p:IsA("ParticleEmitter") then
				local success, _ = pcall(function() p.Color = ColorSequence.new(effectColor) end)
				p.Enabled = true
			end
		end
		Debris:AddItem(clone, lifetime)
	end

	if ringSource then setupVfx(ringSource, 1.5) -- Let ring effect linger
	else warn("[MovementController] Vanish VFX 'Ring' not found.") end

	if soru1Source then setupVfx(soru1Source, 1.5)
	else warn("[MovementController] Vanish VFX 'Soru1' not found.") end

	-- 3. Schedule Reappear Effects and Fade In
	task.delay(effectTime - VANISH_APPEAR_DELAY, function()
		-- Check if character still exists before reappearing
		if not character or not character.Parent or not humanoid or not humanoid.Parent then return end

		-- Play Reappear Effect (Soru2)
		if soru2Source and hrp and hrp.Parent then setupVfx(soru2Source, 1.5)
		else warn("[MovementController] Vanish VFX 'Soru2' not found.") end

		-- Fade In Character Parts
		for part, originalTransp in pairs(originalTransparency) do
			-- Check if part still exists and is part of the character
			if part and part.Parent and part:IsDescendantOf(character) then
				TweenService:Create(part, TweenInfo.new(fadeInTime), {LocalTransparencyModifier = originalTransp}):Play()
			end
		end
	end)
end

-- Play Vanish VFX for Other Players
function MovementController:PlayOtherPlayerVanishEffect(otherPlayer, effectColor, vanishDuration)
	local otherCharacter = otherPlayer.Character
	if not otherCharacter or not otherCharacter.Parent then return end
	local hrp = otherCharacter:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp.Parent then return end
	if not soruVfxSource then return end -- Ensure VFX exists

	local effectTime = (typeof(vanishDuration) == "number" and vanishDuration > 0) and vanishDuration or 0.25
	local fadeOutTime = 0.1
	local fadeInTime = 0.15

	-- Fade Out, Play Effects, Schedule Fade In (Similar to local player, but on otherCharacter)
	local originalTransparency = {}
	for _, descendant in pairs(otherCharacter:GetDescendants()) do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			originalTransparency[descendant] = descendant.LocalTransparencyModifier or 0
			TweenService:Create(descendant, TweenInfo.new(fadeOutTime), {LocalTransparencyModifier = 1}):Play()
		elseif descendant:IsA("Accessory") then
			local handle = descendant:FindFirstChild("Handle")
			if handle then
				originalTransparency[handle] = handle.LocalTransparencyModifier or 0
				TweenService:Create(handle, TweenInfo.new(fadeOutTime), {LocalTransparencyModifier = 1}):Play()
			end
		end
	end

	local ringSource = soruVfxSource:FindFirstChild("Ring")
	local soru1Source = soruVfxSource:FindFirstChild("Soru1")
	local soru2Source = soruVfxSource:FindFirstChild("Soru2")

	-- Function to clone, setup, and add VFX to Debris for other player
	local function setupOtherVfx(source, lifetime)
		if not source then return end
		local clone = source:Clone()
		clone.Parent = hrp -- Parent to other player's HRP
		for _, p in ipairs(clone:GetDescendants()) do
			if p:IsA("ParticleEmitter") then
				local success, _ = pcall(function() p.Color = ColorSequence.new(effectColor) end)
				p.Enabled = true
			end
		end
		Debris:AddItem(clone, lifetime)
	end

	if ringSource then setupOtherVfx(ringSource, 1.5) end
	if soru1Source then setupOtherVfx(soru1Source, 1.5) end

	task.delay(effectTime - VANISH_APPEAR_DELAY, function()
		-- Check if other character still exists
		if not otherCharacter or not otherCharacter.Parent then return end

		-- Play reappear effect
		if soru2Source and hrp and hrp.Parent then setupOtherVfx(soru2Source, 1.5) end

		-- Fade In other character parts
		for part, originalTransp in pairs(originalTransparency) do
			if part and part.Parent and part:IsDescendantOf(otherCharacter) then
				TweenService:Create(part, TweenInfo.new(fadeInTime), {LocalTransparencyModifier = originalTransp}):Play()
			end
		end
	end)
end


-- Start the controller
local controller = setmetatable({}, MovementController)
controller:Initialize()

return controller -- Return the initialized controller object (optional)

