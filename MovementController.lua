-- MovementController.lua
-- Client-side controller for movement abilities (Dash, Run, AutoRun)
-- Version: 2.1.1 (Fixed run sticking when releasing keys with AutoRun enabled)

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
local RUN_KEY = Enum.KeyCode.W -- Still used for direction and initiating run if AutoRun is off
local STOP_RUN_KEY = Enum.KeyCode.S -- Key to stop running (even with AutoRun)

-- Attribute Names
local ATTR_CLASS = "Class"

-- Dash Types
local DASH_TYPE_DEFAULT = "Default"
local DASH_TYPE_SPECIAL = "Special"

-- Dash Effects
local EFFECT_ROLL = "Roll"
local EFFECT_VANISH = "Vanish"

-- Dash Directions
local DIR_FRONT = "Front"
local DIR_BACK = "Back"
local DIR_LEFT = "Left"
local DIR_RIGHT = "Right"

-- Running Constants
local DOUBLE_TAP_WINDOW = 0.28
local RUN_ANIM_ID = "rbxassetid://13836330574"
local RUN_ANIM_FADE_TIME = 0.15

-- VFX Constants
local ROLL_VFX_LIFETIME = 0.4
local VANISH_APPEAR_DELAY = 0.1

-- Variables
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")

-- State Variables
local regularDashCooldown = 0
local specialDashCooldown = 0
local isDashing = false
local isRunning = false -- Client-side running state (for animation/input logic)
local combatActive = false
local playerClass = "Unknown"
local classFetchConnection = nil
local isAutoRunEnabled = false -- Client-side AutoRun state

-- Animation Tracks
local dashAnimations = {}
local runAnimationTrack = nil

-- Double-tap detection variables
local lastWKeyPressTime = 0
local wKeyPressCount = 0

-- Cooldown Update Connections
local regularCooldownConnection = nil
local specialCooldownConnection = nil

-- Remote Events
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local combatRemotes = remotes:WaitForChild("CombatRemotes")
local uiRemotes = remotes:WaitForChild("UIRemotes") -- Get UIRemotes

local dashRequest = combatRemotes:WaitForChild("DashRequest")
local specialDashRequest = combatRemotes:WaitForChild("SpecialDashRequest")
local dashEffect = combatRemotes:WaitForChild("DashEffect")
local dashCooldownEvent = combatRemotes:WaitForChild("DashCooldown")
local setCombatStateEvent = combatRemotes:WaitForChild("SetCombatState")
local runRequest = combatRemotes:WaitForChild("RunRequest")
local autoRunStateChangedEvent = uiRemotes:WaitForChild("AutoRunStateChanged")

-- Event for Class Assignment (Existing)
local classAssignedEvent = uiRemotes:FindFirstChild("ClassAssigned") or Instance.new("RemoteEvent", uiRemotes)
classAssignedEvent.Name = "ClassAssigned"

-- Preloaded VFX Assets (Existing)
local vfxFolder = ReplicatedStorage:WaitForChild("VFX")
local dashVfxSource = vfxFolder and vfxFolder:FindFirstChild("DashVFX")
local soruVfxSource = vfxFolder and vfxFolder:FindFirstChild("soru")

-- Initialize the controller
function MovementController:Initialize()
	print("[MovementController] Initializing (v2.1.1)...")
	self:UpdateCharacterReferences(character)
	self:PreloadAssets()
	self:ConnectRemoteEvents()
	self:ConnectInputHandlers()
	self:FetchPlayerClass()

	-- Initial states
	lastWKeyPressTime = 0; wKeyPressCount = 0; regularDashCooldown = 0; specialDashCooldown = 0
	isDashing = false; isRunning = false; combatActive = false; playerClass = "Unknown"; isAutoRunEnabled = false

	player.CharacterAdded:Connect(function(newCharacter)
		print("[MovementController] Character Added.")
		self:UpdateCharacterReferences(newCharacter)
		self:PreloadAssets()
		self:FetchPlayerClass()
		-- Reset states
		isDashing = false; isRunning = false; wKeyPressCount = 0; lastWKeyPressTime = 0
		regularDashCooldown = 0; specialDashCooldown = 0; playerClass = "Unknown"; isAutoRunEnabled = false
		if regularCooldownConnection then regularCooldownConnection:Disconnect(); regularCooldownConnection = nil end
		if specialCooldownConnection then specialCooldownConnection:Disconnect(); specialCooldownConnection = nil end
	end)

	player.CharacterRemoving:Connect(function(oldCharacter)
		print("[MovementController] Character Removing.")
		if runAnimationTrack and runAnimationTrack.IsPlaying then runAnimationTrack:Stop(0) end
		if regularCooldownConnection then regularCooldownConnection:Disconnect(); regularCooldownConnection = nil end
		if specialCooldownConnection then specialCooldownConnection:Disconnect(); specialCooldownConnection = nil end
		if classFetchConnection then classFetchConnection:Disconnect(); classFetchConnection = nil end
	end)

	print("[MovementController] Initialized.")
end

-- Update references (Existing)
function MovementController:UpdateCharacterReferences(newCharacter) character = newCharacter; humanoid = newCharacter:WaitForChild("Humanoid"); animator = humanoid:WaitForChild("Animator"); if humanoid and humanoid.Parent then humanoid.AutoRotate = true end; print("[MovementController] Updated character references.") end

-- Preload assets (Existing)
function MovementController:PreloadAssets() if not animator then print("[MovementController] PreloadAssets: Animator not found."); return end; for _, track in pairs(dashAnimations) do if track then track:Destroy() end end; dashAnimations = {}; local dashAnimIds = {[DIR_FRONT] = "rbxassetid://14103831900", [DIR_BACK] = "rbxassetid://14103833544", [DIR_LEFT] = "rbxassetid://14103834807", [DIR_RIGHT] = "rbxassetid://14103836416"}; for direction, id in pairs(dashAnimIds) do local success, track = pcall(function() local anim = Instance.new("Animation"); anim.AnimationId = id; local loadedTrack = animator:LoadAnimation(anim); anim:Destroy(); return loadedTrack end); if success and track then track.Priority = Enum.AnimationPriority.Action; track.Looped = false; dashAnimations[direction] = track else warn("[MovementController] Failed to load dash animation:", id, "Error:", track) end end; print("[MovementController] Dash animations preloaded."); if runAnimationTrack then runAnimationTrack:Destroy(); runAnimationTrack = nil end; local success, track = pcall(function() local runAnim = Instance.new("Animation"); runAnim.AnimationId = RUN_ANIM_ID; local loadedTrack = animator:LoadAnimation(runAnim); runAnim:Destroy(); return loadedTrack end); if success and track then runAnimationTrack = track; runAnimationTrack.Priority = Enum.AnimationPriority.Movement; runAnimationTrack.Looped = true; print("[MovementController] Running animation preloaded.") else warn("[MovementController] Failed to load running animation:", RUN_ANIM_ID, "Error:", track) end; if not dashVfxSource then warn("[MovementController] DashVFX folder not found in ReplicatedStorage/VFX") end; if not soruVfxSource then warn("[MovementController] soru VFX folder not found in ReplicatedStorage/VFX") end end

-- Connect to RemoteEvents (Existing)
function MovementController:ConnectRemoteEvents()
	dashEffect.OnClientEvent:Connect(function(directionOrSignal, effectType, effectColor, animationId, playerSource, dashType, dashDuration) if directionOrSignal == "Complete" then isDashing = false; if humanoid and humanoid.Parent then humanoid.AutoRotate = true end; print("[MovementController] Received Dash Complete signal."); if isAutoRunEnabled and combatActive and self:CanDashOrRun() then task.wait(0.05); if not isDashing and not isRunning then print("[MovementController] AutoRun enabled, requesting run resume after dash complete."); self:RequestSetRunningState(true) end end; return end; if playerSource and playerSource ~= player then if effectType == EFFECT_VANISH then self:PlayOtherPlayerVanishEffect(playerSource, effectColor, dashDuration) end; return end; if not character or not humanoid or not animator then return end; if isRunning then isRunning = false; self:UpdateRunningAnimation() end; isDashing = true; if humanoid and humanoid.Parent then humanoid.AutoRotate = false end; self:PlayLocalDashEffect(directionOrSignal, effectType, effectColor, animationId, dashDuration); print(string.format("[MovementController] Playing local dash effect: %s, Type: %s, Duration: %.2f", directionOrSignal, effectType, dashDuration)) end)
	setCombatStateEvent.OnClientEvent:Connect(function(isActive, duration) local stateChanged = (combatActive ~= isActive); combatActive = isActive; print("[MovementController] Combat state changed to:", combatActive); if stateChanged and not isActive then if isRunning then self:RequestSetRunningState(false) end end; if humanoid and humanoid.Parent then humanoid.AutoRotate = true end; if stateChanged and isActive and isAutoRunEnabled and not isRunning and not isDashing and self:CanDashOrRun() then print("[MovementController] Combat started with AutoRun enabled, requesting run start."); self:RequestSetRunningState(true) end end)
	dashCooldownEvent.OnClientEvent:Connect(function(cooldownTime, dashType) if type(cooldownTime) ~= "number" then warn("[MovementController] Received invalid cooldown time type:", type(cooldownTime), "for dash type:", dashType); cooldownTime = 0 end; if dashType == DASH_TYPE_DEFAULT then self:UpdateRegularCooldown(cooldownTime) elseif dashType == DASH_TYPE_SPECIAL then self:UpdateSpecialCooldown(cooldownTime) end; print(string.format("[MovementController] Received cooldown update: Type: %s, Time: %.2f", dashType, cooldownTime)) end)
	autoRunStateChangedEvent.OnClientEvent:Connect(function(newState) if isAutoRunEnabled ~= newState then isAutoRunEnabled = newState; print("[MovementController] AutoRun state updated from server:", isAutoRunEnabled); if not isAutoRunEnabled and isRunning then self:RequestSetRunningState(false) elseif isAutoRunEnabled and combatActive and not isRunning and not isDashing and self:CanDashOrRun() then print("[MovementController] AutoRun enabled via server, requesting run start."); self:RequestSetRunningState(true) end end end)
end

-- Connect input handlers (Modified)
function MovementController:ConnectInputHandlers()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		local keyCode = input.KeyCode

		-- Dash Input (Q / R) (Existing)
		if combatActive and not isDashing then
			if keyCode == DASH_KEY then if playerClass == "Thief" and specialDashCooldown > 0 then print("[MovementController] Cannot use Default Dash, Special Dash is on cooldown."); return end; self:TryRegularDash()
			elseif keyCode == SPECIAL_DASH_KEY and playerClass == "Thief" then if regularDashCooldown > 0 then print("[MovementController] Cannot use Special Dash, Default Dash is on cooldown."); return end; if isRunning then print("[MovementController] Requesting stop run before Vanish."); self:RequestSetRunningState(false); task.wait(0.05); if isRunning or isDashing then print("[MovementController] Failed to stop run before Vanish or already dashing."); return end end; self:TrySpecialDash() end
		end

		-- Running Input (W / S) (Existing)
		if keyCode == RUN_KEY then if not combatActive or isDashing then return end; if isAutoRunEnabled then if not isRunning then print("[MovementController] W pressed with AutoRun enabled, requesting run start."); self:RequestSetRunningState(true) end else local currentTime = time(); if type(lastWKeyPressTime) == "number" and currentTime - lastWKeyPressTime < DOUBLE_TAP_WINDOW then wKeyPressCount = wKeyPressCount + 1; if wKeyPressCount >= 2 and not isRunning then print("[MovementController] Double-tap W detected - Requesting run start."); self:RequestSetRunningState(true); wKeyPressCount = 0 end else wKeyPressCount = 1 end; lastWKeyPressTime = currentTime end
		elseif keyCode == STOP_RUN_KEY and isRunning then print("[MovementController] S pressed - Requesting run stop."); self:RequestSetRunningState(false) end
	end)

	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if gameProcessed or not isRunning then return end -- Only act if currently running
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

		-- ** แก้ไข: ตรวจสอบเฉพาะปุ่มเคลื่อนที่หลัก W, A, D (S จะหยุดใน InputBegan) **
		local keyW = UserInputService:IsKeyDown(Enum.KeyCode.W)
		local keyA = UserInputService:IsKeyDown(Enum.KeyCode.A)
		-- local keyS = UserInputService:IsKeyDown(Enum.KeyCode.S) -- ไม่ต้องเช็ค S ที่นี่
		local keyD = UserInputService:IsKeyDown(Enum.KeyCode.D)

		-- ** แก้ไข: ส่งคำขอหยุดวิ่ง *เสมอ* เมื่อปล่อยปุ่ม W, A, หรือ D ทั้งหมด (ถ้ากำลังวิ่งอยู่) **
		if not keyW and not keyA and not keyD then
			print("[MovementController] All movement keys (W/A/D) released - Requesting run stop.")
			self:RequestSetRunningState(false) -- ส่งคำขอหยุดเสมอ
		end
		-- Server จะจัดการเองว่าจะให้วิ่งต่อหรือไม่ถ้า AutoRun เปิดอยู่
	end)
	print("[MovementController] Input handlers connected.")
end

-- Fetch player's class (Existing)
function MovementController:FetchPlayerClass() if classFetchConnection then classFetchConnection:Disconnect(); classFetchConnection = nil end; if humanoid and humanoid.Parent then local classAttr = humanoid:GetAttribute(ATTR_CLASS); if classAttr and typeof(classAttr) == "string" and classAttr ~= "" and classAttr ~= "Unknown" then playerClass = classAttr; print("[MovementController] Player class fetched immediately from attribute:", playerClass); return end end; playerClass = "Unknown"; print("[MovementController] Class attribute not found or invalid. Waiting for ClassAssigned event..."); if classAssignedEvent and classAssignedEvent:IsA("RemoteEvent") then classFetchConnection = classAssignedEvent.OnClientEvent:Connect(function(assignedClassName) if assignedClassName and typeof(assignedClassName) == "string" and assignedClassName ~= "" then playerClass = assignedClassName; print("[MovementController] Player class received via ClassAssigned event:", playerClass) else warn("[MovementController] Received invalid class name from ClassAssigned event:", assignedClassName) end end) else warn("[MovementController] ClassAssigned RemoteEvent object is not valid or not found.") end end

-- Request server to change running state (Existing)
function MovementController:RequestSetRunningState(state) if isRunning == state and state == true then return end; print("[MovementController] Requesting server to set running state:", state); runRequest:FireServer(state); if isRunning ~= state then isRunning = state; self:UpdateRunningAnimation() end end

-- Update running animation (Existing)
function MovementController:UpdateRunningAnimation() if not runAnimationTrack then return end; if isRunning then if not runAnimationTrack.IsPlaying then runAnimationTrack:Play(RUN_ANIM_FADE_TIME); runAnimationTrack:AdjustSpeed(1.0) end else if runAnimationTrack.IsPlaying then runAnimationTrack:Stop(RUN_ANIM_FADE_TIME) end end end

-- Try to initiate a regular dash (Existing)
function MovementController:TryRegularDash() if isDashing or (type(regularDashCooldown) == "number" and regularDashCooldown > 0) then return end; if not self:CanDashOrRun() then return end; local direction = self:GetDashDirection(); print("[MovementController] Requesting Regular Dash. Direction:", direction); dashRequest:FireServer(direction) end

-- Try to initiate a special dash (Thief) (Existing)
function MovementController:TrySpecialDash() if isDashing or (type(specialDashCooldown) == "number" and specialDashCooldown > 0) then return end; if playerClass ~= "Thief" then print("[MovementController] Cannot special dash: Player class is not Thief ("..playerClass..")"); return end; if not self:CanDashOrRun() then return end; local direction = self:GetDashDirection(); print("[MovementController] Requesting Special Dash. Direction:", direction); specialDashRequest:FireServer(direction) end

-- Check if player can dash or run (Existing)
function MovementController:CanDashOrRun() if not character or not humanoid or not humanoid.RootPart then return false end; local state = humanoid:GetState(); if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Dead or state == Enum.HumanoidStateType.FallingDown or state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.Seated then return false end; return true end

-- Get dash direction (Existing)
function MovementController:GetDashDirection() local keyW = UserInputService:IsKeyDown(Enum.KeyCode.W); local keyS = UserInputService:IsKeyDown(Enum.KeyCode.S); local keyA = UserInputService:IsKeyDown(Enum.KeyCode.A); local keyD = UserInputService:IsKeyDown(Enum.KeyCode.D); if keyW then return DIR_FRONT elseif keyS then return DIR_BACK elseif keyA then return DIR_LEFT elseif keyD then return DIR_RIGHT else return DIR_FRONT end end

-- Cooldown Timer Helper (Existing)
local function StartCooldownTimer(duration, callback) if duration <= 0 then callback(0); return nil end; local startTime = time(); local connection = nil; connection = RunService.Heartbeat:Connect(function(dt) local elapsed = time() - startTime; local remaining = duration - elapsed; if remaining <= 0 then callback(0); if connection then connection:Disconnect(); connection = nil end else callback(remaining) end end); callback(duration); return connection end

-- Update Cooldowns (Existing)
function MovementController:UpdateRegularCooldown(newCooldown) if regularCooldownConnection then regularCooldownConnection:Disconnect(); regularCooldownConnection = nil end; if type(newCooldown) ~= "number" or newCooldown <= 0 then regularDashCooldown = 0 else regularDashCooldown = newCooldown; regularCooldownConnection = StartCooldownTimer(newCooldown, function(remaining) regularDashCooldown = remaining end) end end
function MovementController:UpdateSpecialCooldown(newCooldown) if specialCooldownConnection then specialCooldownConnection:Disconnect(); specialCooldownConnection = nil end; if type(newCooldown) ~= "number" or newCooldown <= 0 then specialDashCooldown = 0 else specialDashCooldown = newCooldown; specialCooldownConnection = StartCooldownTimer(newCooldown, function(remaining) specialDashCooldown = remaining end) end end

-- Play Local Dash Effect (Existing)
function MovementController:PlayLocalDashEffect(direction, effectType, effectColor, animationId, dashDuration) if animationId and effectType ~= EFFECT_VANISH then local animTrack = dashAnimations[direction]; if animTrack then animTrack:Play(0.1) else warn("[MovementController] Dash animation track not found for direction:", direction) end end; if effectType == EFFECT_ROLL then self:PlayRollVFX(effectColor) elseif effectType == EFFECT_VANISH then self:PlayVanishVFX(effectColor, dashDuration) end end
-- Play Roll VFX (Existing)
function MovementController:PlayRollVFX(effectColor) if not character or not humanoid or not dashVfxSource then return end; local hrp = character:FindFirstChild("HumanoidRootPart"); if not hrp then return end; local line1Source = dashVfxSource:FindFirstChild("Line1"); local line2Source = dashVfxSource:FindFirstChild("Line2"); local function setupVfx(source, lifetime) if not source then return end; local clone = source:Clone(); clone.Parent = hrp; for _, descendant in ipairs(clone:GetDescendants()) do if descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then local success, _ = pcall(function() descendant.Color = ColorSequence.new(effectColor) end); descendant.Enabled = true end end; Debris:AddItem(clone, lifetime) end; if line1Source then setupVfx(line1Source, ROLL_VFX_LIFETIME) else warn("[MovementController] Roll VFX 'Line1' not found.") end; if line2Source then setupVfx(line2Source, ROLL_VFX_LIFETIME * 1.2) else warn("[MovementController] Roll VFX 'Line2' not found.") end end
-- Play Vanish VFX (Local) (Existing)
function MovementController:PlayVanishVFX(effectColor, vanishDuration) if not character or not humanoid or not soruVfxSource then return end; local hrp = character:FindFirstChild("HumanoidRootPart"); if not hrp then return end; local effectTime = (typeof(vanishDuration) == "number" and vanishDuration > 0) and vanishDuration or 0.25; local fadeOutTime = 0.1; local fadeInTime = 0.15; local originalTransparency = {}; for _, descendant in pairs(character:GetDescendants()) do if descendant:IsA("BasePart") or descendant:IsA("Decal") then originalTransparency[descendant] = descendant.LocalTransparencyModifier or 0; TweenService:Create(descendant, TweenInfo.new(fadeOutTime), {LocalTransparencyModifier = 1}):Play() elseif descendant:IsA("Accessory") then local handle = descendant:FindFirstChild("Handle"); if handle then originalTransparency[handle] = handle.LocalTransparencyModifier or 0; TweenService:Create(handle, TweenInfo.new(fadeOutTime), {LocalTransparencyModifier = 1}):Play() end end end; local ringSource = soruVfxSource:FindFirstChild("Ring"); local soru1Source = soruVfxSource:FindFirstChild("Soru1"); local soru2Source = soruVfxSource:FindFirstChild("Soru2"); local function setupVfx(source, lifetime) if not source then return end; local clone = source:Clone(); clone.Parent = hrp; for _, p in ipairs(clone:GetDescendants()) do if p:IsA("ParticleEmitter") then local success, _ = pcall(function() p.Color = ColorSequence.new(effectColor) end); p.Enabled = true end end; Debris:AddItem(clone, lifetime) end; if ringSource then setupVfx(ringSource, 1.5) else warn("[MovementController] Vanish VFX 'Ring' not found.") end; if soru1Source then setupVfx(soru1Source, 1.5) else warn("[MovementController] Vanish VFX 'Soru1' not found.") end; task.delay(effectTime - VANISH_APPEAR_DELAY, function() if not character or not character.Parent or not humanoid or not humanoid.Parent then return end; if soru2Source and hrp and hrp.Parent then setupVfx(soru2Source, 1.5) else warn("[MovementController] Vanish VFX 'Soru2' not found.") end; for part, originalTransp in pairs(originalTransparency) do if part and part.Parent and part:IsDescendantOf(character) then TweenService:Create(part, TweenInfo.new(fadeInTime), {LocalTransparencyModifier = originalTransp}):Play() end end end) end
-- Play Vanish VFX (Other) (Existing)
function MovementController:PlayOtherPlayerVanishEffect(otherPlayer, effectColor, vanishDuration) local otherCharacter = otherPlayer.Character; if not otherCharacter or not otherCharacter.Parent then return end; local hrp = otherCharacter:FindFirstChild("HumanoidRootPart"); if not hrp or not hrp.Parent then return end; if not soruVfxSource then return end; local effectTime = (typeof(vanishDuration) == "number" and vanishDuration > 0) and vanishDuration or 0.25; local fadeOutTime = 0.1; local fadeInTime = 0.15; local originalTransparency = {}; for _, descendant in pairs(otherCharacter:GetDescendants()) do if descendant:IsA("BasePart") or descendant:IsA("Decal") then originalTransparency[descendant] = descendant.LocalTransparencyModifier or 0; TweenService:Create(descendant, TweenInfo.new(fadeOutTime), {LocalTransparencyModifier = 1}):Play() elseif descendant:IsA("Accessory") then local handle = descendant:FindFirstChild("Handle"); if handle then originalTransparency[handle] = handle.LocalTransparencyModifier or 0; TweenService:Create(handle, TweenInfo.new(fadeOutTime), {LocalTransparencyModifier = 1}):Play() end end end; local ringSource = soruVfxSource:FindFirstChild("Ring"); local soru1Source = soruVfxSource:FindFirstChild("Soru1"); local soru2Source = soruVfxSource:FindFirstChild("Soru2"); local function setupOtherVfx(source, lifetime) if not source then return end; local clone = source:Clone(); clone.Parent = hrp; for _, p in ipairs(clone:GetDescendants()) do if p:IsA("ParticleEmitter") then local success, _ = pcall(function() p.Color = ColorSequence.new(effectColor) end); p.Enabled = true end end; Debris:AddItem(clone, lifetime) end; if ringSource then setupOtherVfx(ringSource, 1.5) end; if soru1Source then setupOtherVfx(soru1Source, 1.5) end; task.delay(effectTime - VANISH_APPEAR_DELAY, function() if not otherCharacter or not otherCharacter.Parent then return end; if soru2Source and hrp and hrp.Parent then setupOtherVfx(soru2Source, 1.5) end; for part, originalTransp in pairs(originalTransparency) do if part and part.Parent and part:IsDescendantOf(otherCharacter) then TweenService:Create(part, TweenInfo.new(fadeInTime), {LocalTransparencyModifier = originalTransp}):Play() end end end) end

-- Start the controller
local controller = setmetatable({}, MovementController)
controller:Initialize()

return controller
