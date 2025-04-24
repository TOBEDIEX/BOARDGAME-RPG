-- MovementSystem.lua
-- Module for managing movement abilities including dash, running, and AutoRun (Server-Side)
-- Version: 2.1.0 (Added AutoRun support, Vanish while running fix)

local MovementSystem = {}
MovementSystem.__index = MovementSystem

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local Debris = game:GetService("Debris")

-- Constants
local DASH_COLLISION_GROUP = "DashingPlayers"
local DEFAULT_COLLISION_GROUP = "Default"
local DEFAULT_WALKSPEED = 16

-- Attribute Names
local ATTR_CLASS = "Class"
local ATTR_THIEF_BOOST_ENDTIME = "ThiefBoostEndTime"
local ATTR_THIEF_BOOST_SPEED = "ThiefBoostSpeed"
local ATTR_ORIGINAL_SPEED = "OriginalWalkSpeed"

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

-- Class Settings (Existing)
local CLASS_DASH_SETTINGS = { Warrior = {[DASH_TYPE_DEFAULT] = {Distance=12, Duration=0.3, Cooldown=2.0, Effect=EFFECT_ROLL, EffectColor=Color3.fromRGB(255,130,0), AnimationRequired=true, SpeedBoost=0, SpeedBoostDuration=0}}, Mage = {[DASH_TYPE_DEFAULT] = {Distance=15, Duration=0.3, Cooldown=3.5, Effect=EFFECT_ROLL, EffectColor=Color3.fromRGB(70,130,255), AnimationRequired=true, SpeedBoost=0, SpeedBoostDuration=0}}, Thief = {[DASH_TYPE_DEFAULT] = {Distance=15, Duration=0.3, Cooldown=2.0, Effect=EFFECT_ROLL, EffectColor=Color3.fromRGB(110,255,110), AnimationRequired=true, SpeedBoost=0, SpeedBoostDuration=0}, [DASH_TYPE_SPECIAL] = {Distance=18, Duration=0.25, Cooldown=5.0, Effect=EFFECT_VANISH, EffectColor=Color3.fromRGB(110,255,110), AnimationRequired=false, SpeedBoost=34, SpeedBoostDuration=1.25}}}
local CLASS_RUN_SETTINGS = { Warrior = {SpeedMultiplier=1.7}, Mage = {SpeedMultiplier=1.5}, Thief = {SpeedMultiplier=1.8} }
local DEFAULT_DASH_SETTINGS = {Distance=14, Duration=0.35, Cooldown=2.5, Effect=EFFECT_ROLL, EffectColor=Color3.fromRGB(200,200,200), AnimationRequired=true, SpeedBoost=0, SpeedBoostDuration=0}
local DEFAULT_RUN_SETTINGS = {SpeedMultiplier=1.6}

-- Animation IDs (Existing)
local DASH_ANIMATIONS = {[DIR_FRONT]="rbxassetid://14103831900", [DIR_BACK]="rbxassetid://14103833544", [DIR_LEFT]="rbxassetid://14103834807", [DIR_RIGHT]="rbxassetid://14103836416"}

-- Constructor (Modified)
function MovementSystem.new(combatService)
	local self = setmetatable({}, MovementSystem)
	self.combatService = combatService
	self.activeDashes = {}
	self.playerCooldowns = {}
	self.playerRunning = {} -- Tracks if player is *currently* running (affected by S key)
	self.playerAutoRunEnabled = {} -- ** เพิ่ม: เก็บสถานะ AutoRun ของแต่ละ Player **

	self:SetupCollisionGroup()
	self:SetupRemoteEvents() -- Includes AutoRun events now
	self:StartBoostCleanupLoop()
	return self
end

-- Setup Collision Group (Existing)
function MovementSystem:SetupCollisionGroup()
	local success, exists = pcall(function() return PhysicsService:GetCollisionGroupId(DASH_COLLISION_GROUP) end)
	if not success or not exists then pcall(function() PhysicsService:CreateCollisionGroup(DASH_COLLISION_GROUP); PhysicsService:CollisionGroupSetCollidable(DASH_COLLISION_GROUP, DASH_COLLISION_GROUP, false); PhysicsService:CollisionGroupSetCollidable(DASH_COLLISION_GROUP, DEFAULT_COLLISION_GROUP, true); print("[MovementSystem] Collision group", DASH_COLLISION_GROUP, "created.") end) end
end

-- Set up remote events (Modified)
function MovementSystem:SetupRemoteEvents()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local combatRemotes = remotes:FindFirstChild("CombatRemotes") or Instance.new("Folder", remotes); combatRemotes.Name = "CombatRemotes"
	local uiRemotes = remotes:FindFirstChild("UIRemotes") or Instance.new("Folder", remotes); uiRemotes.Name = "UIRemotes" -- Ensure UIRemotes exists

	-- Dash Events (Existing)
	self.dashRequest = combatRemotes:FindFirstChild("DashRequest") or Instance.new("RemoteEvent", combatRemotes); self.dashRequest.Name = "DashRequest"
	self.specialDashRequest = combatRemotes:FindFirstChild("SpecialDashRequest") or Instance.new("RemoteEvent", combatRemotes); self.specialDashRequest.Name = "SpecialDashRequest"
	self.dashEffect = combatRemotes:FindFirstChild("DashEffect") or Instance.new("RemoteEvent", combatRemotes); self.dashEffect.Name = "DashEffect"
	self.dashCooldown = combatRemotes:FindFirstChild("DashCooldown") or Instance.new("RemoteEvent", combatRemotes); self.dashCooldown.Name = "DashCooldown"

	-- Running Events (Existing)
	self.runRequest = combatRemotes:FindFirstChild("RunRequest") or Instance.new("RemoteEvent", combatRemotes); self.runRequest.Name = "RunRequest"
	self.runState = combatRemotes:FindFirstChild("RunState") or Instance.new("RemoteEvent", combatRemotes); self.runState.Name = "RunState"

	-- ** เพิ่ม: AutoRun Remote Events **
	self.setAutoRunStateEvent = uiRemotes:FindFirstChild("SetAutoRunState") or Instance.new("RemoteEvent", uiRemotes)
	self.setAutoRunStateEvent.Name = "SetAutoRunState"
	self.autoRunStateChangedEvent = uiRemotes:FindFirstChild("AutoRunStateChanged") or Instance.new("RemoteEvent", uiRemotes)
	self.autoRunStateChangedEvent.Name = "AutoRunStateChanged"

	-- Connect Handlers (Modified)
	self.dashRequest.OnServerEvent:Connect(function(player, direction) self:ProcessDashRequest(player, direction, DASH_TYPE_DEFAULT) end)
	self.specialDashRequest.OnServerEvent:Connect(function(player, direction) self:ProcessDashRequest(player, direction, DASH_TYPE_SPECIAL) end)
	self.runRequest.OnServerEvent:Connect(function(player, isRunning) self:SetPlayerRunningState(player, isRunning) end)
	self.setAutoRunStateEvent.OnServerEvent:Connect(function(player, isEnabled) self:SetPlayerAutoRunState(player, isEnabled) end) -- ** เพิ่ม: Handler สำหรับ AutoRun **
end

-- Process dash request (Modified for Vanish while running)
function MovementSystem:ProcessDashRequest(player, direction, dashType)
	local playerId = player.UserId
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not humanoid or humanoid:GetState() == Enum.HumanoidStateType.Dead then return false end
	if not self.combatService or not self.combatService:IsCombatActive() then return false end
	if self.activeDashes[playerId] then return false end

	local playerClass = self:GetPlayerClass(player)
	if dashType == DASH_TYPE_SPECIAL and playerClass ~= "Thief" then print("[MovementSystem] Player", player.Name, "is not Thief, cannot use Special Dash."); return false end

	if not self.playerCooldowns[playerId] then self.playerCooldowns[playerId] = { [DASH_TYPE_DEFAULT] = 0, [DASH_TYPE_SPECIAL] = 0 } end
	local currentTime = time(); local cooldownData = self.playerCooldowns[playerId]; local dashSettings = self:GetDashSettings(playerClass, dashType)

	if cooldownData[dashType] and cooldownData[dashType] > currentTime then local remainingCooldown = cooldownData[dashType] - currentTime; self.dashCooldown:FireClient(player, remainingCooldown, dashType); print("[MovementSystem] Player", player.Name, dashType, "Dash on cooldown. Remaining:", remainingCooldown); return false end
	if playerClass == "Thief" then local otherDashType = (dashType == DASH_TYPE_DEFAULT) and DASH_TYPE_SPECIAL or DASH_TYPE_DEFAULT; if cooldownData[otherDashType] and cooldownData[otherDashType] > currentTime then local remainingOtherCooldown = cooldownData[otherDashType] - currentTime; self.dashCooldown:FireClient(player, remainingOtherCooldown, dashType); print("[MovementSystem] Player", player.Name, "Thief's other dash ("..otherDashType..") on cooldown. Remaining:", remainingOtherCooldown); return false end end

	-- ** เพิ่ม: ถ้าเป็น Vanish และกำลังวิ่งอยู่ ให้หยุดวิ่งก่อน **
	local wasRunningBeforeVanish = false
	if dashType == DASH_TYPE_SPECIAL and self.playerRunning[playerId] then
		print("[MovementSystem] Stopping run before Vanish for player", player.Name)
		self:SetPlayerRunningState(player, false) -- หยุดวิ่ง (Server-side)
		wasRunningBeforeVanish = true -- ทำเครื่องหมายว่าหยุดวิ่งเพื่อ Vanish
		task.wait(0.05) -- รอให้การหยุดวิ่งเสร็จสิ้น
		-- ตรวจสอบอีกครั้งว่าหยุดวิ่งสำเร็จ
		if self.playerRunning[playerId] then
			print("[MovementSystem] Failed to stop run before Vanish, aborting dash.")
			return false -- ถ้ายังวิ่งอยู่ แสดงว่ามีปัญหา ยกเลิก Dash
		end
	end

	local success = self:PerformDash(player, direction, dashSettings, dashType, wasRunningBeforeVanish) -- ส่งสถานะ wasRunningBeforeVanish
	if success then
		self.playerCooldowns[playerId][dashType] = currentTime + dashSettings.Cooldown
		self.dashCooldown:FireClient(player, dashSettings.Cooldown, dashType)
		print("[MovementSystem] Player", player.Name, "performed", dashType, "Dash. Cooldown:", dashSettings.Cooldown)
	elseif wasRunningBeforeVanish then
		-- ถ้า Dash ไม่สำเร็จ แต่เราหยุดวิ่งไปแล้ว และ AutoRun เปิดอยู่ ให้กลับไปวิ่ง
		if self.playerAutoRunEnabled[playerId] then
			print("[MovementSystem] Vanish failed after stopping run, resuming AutoRun.")
			task.wait(0.05)
			self:SetPlayerRunningState(player, true)
		end
	end
	return success
end

-- Get dash settings (Existing)
function MovementSystem:GetDashSettings(playerClass, dashType) if CLASS_DASH_SETTINGS[playerClass] then if dashType == DASH_TYPE_SPECIAL and CLASS_DASH_SETTINGS[playerClass][DASH_TYPE_SPECIAL] then return CLASS_DASH_SETTINGS[playerClass][DASH_TYPE_SPECIAL] elseif CLASS_DASH_SETTINGS[playerClass][DASH_TYPE_DEFAULT] then return CLASS_DASH_SETTINGS[playerClass][DASH_TYPE_DEFAULT] end end; return DEFAULT_DASH_SETTINGS end

-- ** เพิ่ม: Set player AutoRun state **
function MovementSystem:SetPlayerAutoRunState(player, isEnabled)
	local playerId = player.UserId
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not humanoid or humanoid:GetState() == Enum.HumanoidStateType.Dead then return end

	-- อัปเดตสถานะ Server-side
	self.playerAutoRunEnabled[playerId] = isEnabled
	print(string.format("[MovementSystem] Player %s AutoRun state set to: %s", player.Name, tostring(isEnabled)))

	-- ส่งสถานะกลับไปให้ Client (เพื่ออัปเดต UI Toggle)
	self.autoRunStateChangedEvent:FireClient(player, isEnabled)

	-- จัดการการเริ่ม/หยุดวิ่งตามสถานะ AutoRun ใหม่
	if isEnabled then
		-- ถ้าเปิด AutoRun และอยู่ใน Combat แต่ยังไม่ได้วิ่ง/Dash ให้เริ่มวิ่ง
		if self.combatService and self.combatService:IsCombatActive() and not self.playerRunning[playerId] and not self.activeDashes[playerId] then
			print("[MovementSystem] AutoRun enabled, starting run.")
			self:SetPlayerRunningState(player, true)
		end
	else
		-- ถ้าปิด AutoRun และกำลังวิ่งอยู่ ให้หยุดวิ่ง
		if self.playerRunning[playerId] then
			print("[MovementSystem] AutoRun disabled, stopping run.")
			self:SetPlayerRunningState(player, false)
		end
	end
end

-- Set player running state (Modified for AutoRun)
function MovementSystem:SetPlayerRunningState(player, isRunning)
	local playerId = player.UserId
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not humanoid or humanoid:GetState() == Enum.HumanoidStateType.Dead then return end
	if self.activeDashes[playerId] then return end -- ห้ามเปลี่ยนสถานะวิ่งขณะ Dash

	-- ตรวจสอบ Combat Mode
	local isInCombat = self.combatService and self.combatService:IsCombatActive()
	if not isInCombat then
		if isRunning then isRunning = false end -- ห้ามเริ่มวิ่งนอก Combat
		if self.playerRunning[playerId] then isRunning = false end -- หยุดวิ่งถ้านอก Combat
	end

	-- ถ้าสถานะไม่เปลี่ยนแปลง ก็ไม่ต้องทำอะไร
	if self.playerRunning[playerId] == isRunning then return end

	-- ** เพิ่ม: ตรวจสอบ AutoRun เมื่อพยายาม *หยุด* วิ่ง **
	if not isRunning and self.playerAutoRunEnabled[playerId] then
		-- ถ้า AutoRun เปิดอยู่ การกด S หรือปล่อยปุ่ม (ที่ Client ส่งมา) จะหยุดวิ่งชั่วคราว
		-- แต่ Server จะยังคงถือว่า AutoRun เปิดอยู่ Client จะเริ่มวิ่งใหม่เมื่อกด W
		print(string.format("[MovementSystem] Player %s stopped running temporarily (AutoRun is ON).", player.Name))
		-- แค่ปรับ Speed กลับ แต่ไม่เปลี่ยน self.playerRunning
		local originalSpeed = humanoid:GetAttribute(ATTR_ORIGINAL_SPEED) or DEFAULT_WALKSPEED
		humanoid.WalkSpeed = originalSpeed
		humanoid:SetAttribute(ATTR_ORIGINAL_SPEED, nil)
		self.playerRunning[playerId] = false -- ** แก้ไข: ต้องตั้งเป็น false เพื่อให้ Client เริ่มใหม่ได้ **
		-- ไม่ต้องทำอะไรเพิ่ม Server จะรอ Client ส่ง Request มาใหม่ถ้ากด W
		return -- ออกจากฟังก์ชัน ไม่ต้องทำ Logic ด้านล่าง
	end

	-- อัปเดตสถานะการวิ่งบน Server
	self.playerRunning[playerId] = isRunning

	self:ClearThiefBoost(humanoid)

	if isRunning then
		local playerClass = self:GetPlayerClass(player)
		local runSettings = CLASS_RUN_SETTINGS[playerClass] or DEFAULT_RUN_SETTINGS
		local runSpeed = DEFAULT_WALKSPEED * runSettings.SpeedMultiplier
		if not humanoid:GetAttribute(ATTR_ORIGINAL_SPEED) then humanoid:SetAttribute(ATTR_ORIGINAL_SPEED, humanoid.WalkSpeed) end
		humanoid.WalkSpeed = runSpeed
		print(string.format("[MovementSystem] Player %s started running. Class: %s, Speed: %.2f", player.Name, playerClass, runSpeed))
	else
		-- หยุดวิ่ง (กรณี AutoRun ปิด หรือ ออกจาก Combat)
		local originalSpeed = humanoid:GetAttribute(ATTR_ORIGINAL_SPEED) or DEFAULT_WALKSPEED
		humanoid.WalkSpeed = originalSpeed
		humanoid:SetAttribute(ATTR_ORIGINAL_SPEED, nil)
		print(string.format("[MovementSystem] Player %s stopped running. Reset speed to: %.2f", player.Name, originalSpeed))
	end

	-- แจ้ง Client อื่นๆ (ถ้าจำเป็น)
	-- self.runState:FireAllClients(playerId, isRunning)
end

-- Get player's class (Existing)
function MovementSystem:GetPlayerClass(player) local character = player.Character; local humanoid = character and character:FindFirstChildOfClass("Humanoid"); if humanoid then local classAttr = humanoid:GetAttribute(ATTR_CLASS); if classAttr and typeof(classAttr) == "string" then return classAttr end end; local gameManager = _G.GameManager; if gameManager then if gameManager.classSystem and gameManager.classSystem.GetPlayerClass then local classFromSystem = gameManager.classSystem:GetPlayerClass(player); if classFromSystem then return classFromSystem end end; if gameManager.playerManager and gameManager.playerManager.GetPlayerData then local playerData = gameManager.playerManager:GetPlayerData(player); if playerData and playerData.class then return playerData.class end end end; warn("[MovementSystem] Could not determine class for player:", player.Name, "- Using 'Unknown'"); return "Unknown" end

-- Perform the actual dash (Modified)
function MovementSystem:PerformDash(player, directionString, dashSettings, dashType, wasRunningBeforeVanish) -- เพิ่ม wasRunningBeforeVanish
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not hrp or humanoid:GetState() == Enum.HumanoidStateType.Dead then return false end
	if self.activeDashes[player.UserId] then return false end
	local state = humanoid:GetState(); if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then return false end

	local playerId = player.UserId

	-- หยุดวิ่งก่อน Dash (ถ้ายังวิ่งอยู่ และไม่ใช่กรณี Vanish ที่หยุดไปแล้ว)
	local wasRunning = self.playerRunning[playerId] or wasRunningBeforeVanish -- ใช้สถานะก่อน Vanish ด้วย
	if self.playerRunning[playerId] and not wasRunningBeforeVanish then
		self:SetPlayerRunningState(player, false)
	end

	local dashData = { player = player, settings = dashSettings, startTime = time(), completed = false, originalCollisionGroups = {}, originalWalkSpeed = humanoid.WalkSpeed, directionString = directionString, dashType = dashType, wasRunning = wasRunning } -- เก็บ wasRunning ที่ถูกต้อง
	self.activeDashes[playerId] = dashData

	for _, part in ipairs(character:GetDescendants()) do if part:IsA("BasePart") then dashData.originalCollisionGroups[part] = part.CollisionGroup; local success, err = pcall(function() part.CollisionGroup = DASH_COLLISION_GROUP end); if not success then warn("[MovementSystem] Failed to set collision group for", part:GetFullName(), ":", err) end end end

	local animationId = dashSettings.AnimationRequired and DASH_ANIMATIONS[directionString] or nil
	local effectDuration = dashSettings.Duration; if dashSettings.Effect == EFFECT_VANISH and dashSettings.SpeedBoostDuration and dashSettings.SpeedBoostDuration > 0 then effectDuration = dashSettings.SpeedBoostDuration end

	self.dashEffect:FireClient(player, directionString, dashSettings.Effect, dashSettings.EffectColor, animationId, nil, dashType, effectDuration)
	if dashSettings.Effect == EFFECT_VANISH then for _, otherPlayer in pairs(Players:GetPlayers()) do if otherPlayer ~= player then self.dashEffect:FireClient(otherPlayer, directionString, dashSettings.Effect, dashSettings.EffectColor, nil, player, dashType, effectDuration) end end end

	self:ApplyDashVelocity(dashData)

	task.delay(dashSettings.Duration, function()
		if self.activeDashes[playerId] == dashData then self:CleanupDash(playerId) end
	end)

	return true
end

-- Apply dash velocity (Existing)
function MovementSystem:ApplyDashVelocity(dashData) local player = dashData.player; local character = player.Character; local hrp = character and character:FindFirstChild("HumanoidRootPart"); local humanoid = character and character:FindFirstChildOfClass("Humanoid"); if not hrp or not humanoid then self:CleanupDash(player.UserId); return end; local attachment = hrp:FindFirstChild("DashAttachment"); if not attachment then attachment = Instance.new("Attachment", hrp); attachment.Name = "DashAttachment" end; local oldVelocity = hrp:FindFirstChild("DashLinearVelocity"); if oldVelocity then oldVelocity:Destroy() end; local moveDirectionVector = self:GetDirectionVector(dashData.directionString, character); local linearVelocity = Instance.new("LinearVelocity"); linearVelocity.Name = "DashLinearVelocity"; linearVelocity.Attachment0 = attachment; linearVelocity.MaxForce = 100000; linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Line; linearVelocity.LineDirection = moveDirectionVector; linearVelocity.LineVelocity = dashData.settings.Distance / dashData.settings.Duration; linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World; linearVelocity.Parent = hrp; dashData.linearVelocity = linearVelocity; humanoid.AutoRotate = false; end
-- Get direction vector (Existing)
function MovementSystem:GetDirectionVector(directionString, character) local hrp = character:FindFirstChild("HumanoidRootPart"); if not hrp then return Vector3.zAxis end; local lookVector = hrp.CFrame.LookVector; local rightVector = hrp.CFrame.RightVector; if directionString == DIR_BACK then return -lookVector.Unit elseif directionString == DIR_LEFT then return -rightVector.Unit elseif directionString == DIR_RIGHT then return rightVector.Unit else return lookVector.Unit end end

-- Clean up after dash (Modified for AutoRun resume)
function MovementSystem:CleanupDash(userId)
	local dashData = self.activeDashes[userId]
	if not dashData or dashData.completed then self.activeDashes[userId] = nil; return end

	dashData.completed = true
	local player = dashData.player
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if dashData.linearVelocity and dashData.linearVelocity.Parent then dashData.linearVelocity:Destroy() end
	if character and dashData.originalCollisionGroups then for part, groupName in pairs(dashData.originalCollisionGroups) do if part and part.Parent then pcall(function() part.CollisionGroup = groupName or DEFAULT_COLLISION_GROUP end) end end end

	if humanoid and humanoid.Parent then
		humanoid.AutoRotate = true

		if dashData.dashType == DASH_TYPE_SPECIAL and dashData.settings.Effect == EFFECT_VANISH and dashData.settings.SpeedBoost > 0 and dashData.settings.SpeedBoostDuration > 0 then
			local boostedSpeed = dashData.settings.SpeedBoost; local boostEndTime = time() + dashData.settings.SpeedBoostDuration
			humanoid:SetAttribute(ATTR_ORIGINAL_SPEED, humanoid.WalkSpeed); humanoid:SetAttribute(ATTR_THIEF_BOOST_SPEED, boostedSpeed); humanoid:SetAttribute(ATTR_THIEF_BOOST_ENDTIME, boostEndTime)
			humanoid.WalkSpeed = boostedSpeed
			print(string.format("[MovementSystem] Player %s (Thief) started Speed Boost. Speed: %.2f, Duration: %.2fs", player.Name, boostedSpeed, dashData.settings.SpeedBoostDuration))
			-- BoostCleanupLoop จะจัดการการคืนค่า Speed และการกลับไปวิ่ง (ถ้า AutoRun เปิด)
		else
			-- Dash ปกติ หรือ Vanish ที่ไม่มี Boost
			humanoid.WalkSpeed = dashData.originalWalkSpeed
			print(string.format("[MovementSystem] Player %s finished Dash. Reset speed to: %.2f", player.Name, dashData.originalWalkSpeed))

			-- ** เพิ่ม: ตรวจสอบ AutoRun เพื่อกลับไปวิ่งต่อ **
			if self.playerAutoRunEnabled[userId] and dashData.wasRunning then
				task.wait(0.05) -- รอเล็กน้อย
				if self.combatService and self.combatService:IsCombatActive() and not self.activeDashes[userId] and not self.playerRunning[userId] then
					print(string.format("[MovementSystem] Player %s has AutoRun enabled, resuming run after dash.", player.Name))
					self:SetPlayerRunningState(player, true)
				end
				-- ถ้า AutoRun ปิด แต่ก่อนหน้าวิ่งอยู่ (Double-Tap) ให้กลับไปวิ่งตามปกติ
			elseif not self.playerAutoRunEnabled[userId] and dashData.wasRunning then
				task.wait(0.05)
				if self.combatService and self.combatService:IsCombatActive() and not self.activeDashes[userId] and not self.playerRunning[userId] then
					print(string.format("[MovementSystem] Player %s was running before dash (AutoRun OFF), resuming run.", player.Name))
					self:SetPlayerRunningState(player, true)
				end
			end
		end
	end

	if player then self.dashEffect:FireClient(player, "Complete", nil, nil, nil, nil, dashData.dashType, 0) end
	self.activeDashes[userId] = nil
end

-- Boost Cleanup Loop (Modified for AutoRun resume)
function MovementSystem:StartBoostCleanupLoop()
	task.spawn(function()
		while task.wait(0.5) do
			local currentTime = time()
			for userId, _ in pairs(self.playerCooldowns) do
				local player = Players:GetPlayerByUserId(userId)
				if player and player.Character then
					local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Parent then
						local boostEndTime = humanoid:GetAttribute(ATTR_THIEF_BOOST_ENDTIME)
						if boostEndTime and typeof(boostEndTime) == "number" and currentTime >= boostEndTime then
							local originalSpeed = humanoid:GetAttribute(ATTR_ORIGINAL_SPEED) or DEFAULT_WALKSPEED
							local shouldResumeRun = false -- Flag to check if we need to resume running

							-- ตรวจสอบว่าไม่ได้กำลัง Dash อยู่
							if not self.activeDashes[userId] then
								-- ** เพิ่ม: ตรวจสอบ AutoRun **
								if self.playerAutoRunEnabled[userId] then
									-- ถ้า AutoRun เปิดอยู่ ให้เตรียมกลับไปวิ่ง
									shouldResumeRun = true
									print(string.format("[MovementSystem] Player %s Thief Boost expired with AutoRun ON.", player.Name))
									-- ไม่ต้องตั้ง Speed ที่นี่ SetPlayerRunningState จะจัดการเอง
								elseif self.playerRunning[userId] then
									-- ถ้า AutoRun ปิด แต่กำลังวิ่งอยู่ (อาจเกิดจาก Bug?) ให้หยุดวิ่ง
									print(string.format("[MovementSystem] Player %s Thief Boost expired while running (AutoRun OFF). Stopping run.", player.Name))
									self:SetPlayerRunningState(player, false) -- หยุดวิ่งและคืน Speed
								else
									-- ถ้า AutoRun ปิด และไม่ได้วิ่งอยู่ ให้คืน Speed ปกติ
									humanoid.WalkSpeed = originalSpeed
									print(string.format("[MovementSystem] Player %s Thief Boost expired. Reset speed to: %.2f", player.Name, originalSpeed))
								end
							end

							-- ล้าง Attributes ของ Boost
							humanoid:SetAttribute(ATTR_THIEF_BOOST_ENDTIME, nil)
							humanoid:SetAttribute(ATTR_THIEF_BOOST_SPEED, nil)
							humanoid:SetAttribute(ATTR_ORIGINAL_SPEED, nil)

							-- กลับไปวิ่งถ้า AutoRun เปิดอยู่ และไม่ได้ Dash
							if shouldResumeRun and not self.activeDashes[userId] then
								task.wait(0.05) -- รอเล็กน้อย
								if self.combatService and self.combatService:IsCombatActive() and not self.playerRunning[userId] then
									print("[MovementSystem] Resuming AutoRun after Thief Boost expired.")
									self:SetPlayerRunningState(player, true)
								end
							end
						end
					end
				end
			end
		end
	end)
end

-- Clear Thief Boost (Existing)
function MovementSystem:ClearThiefBoost(humanoid) if humanoid and humanoid.Parent then if humanoid:GetAttribute(ATTR_THIEF_BOOST_ENDTIME) then humanoid:SetAttribute(ATTR_THIEF_BOOST_ENDTIME, nil); humanoid:SetAttribute(ATTR_THIEF_BOOST_SPEED, nil); print("[MovementSystem] Cleared active Thief Boost attributes.") end end end
-- Clear Cooldown (Existing)
function MovementSystem:ClearCooldown(player, dashType) local playerId = typeof(player) == "Instance" and player.UserId or player; if not playerId then return end; if not self.playerCooldowns[playerId] then return end; local playerInstance = typeof(player) == "Instance" and player or Players:GetPlayerByUserId(playerId); if dashType and (dashType == DASH_TYPE_DEFAULT or dashType == DASH_TYPE_SPECIAL) then if self.playerCooldowns[playerId][dashType] then self.playerCooldowns[playerId][dashType] = 0; if playerInstance then self.dashCooldown:FireClient(playerInstance, 0, dashType) end; print("[MovementSystem] Cleared", dashType, "cooldown for player", playerId) end else self.playerCooldowns[playerId] = { [DASH_TYPE_DEFAULT] = 0, [DASH_TYPE_SPECIAL] = 0 }; if playerInstance then self.dashCooldown:FireClient(playerInstance, 0, DASH_TYPE_DEFAULT); self.dashCooldown:FireClient(playerInstance, 0, DASH_TYPE_SPECIAL) end; print("[MovementSystem] Cleared all dash cooldowns for player", playerId) end end

-- Initialize player (Modified)
function MovementSystem:InitializePlayer(player)
	local userId = player.UserId
	print("[MovementSystem] Initializing player:", player.Name)
	if self.activeDashes[userId] then print("[MovementSystem] Cleaning up lingering dash for player:", player.Name); self:CleanupDash(userId) end
	self.playerCooldowns[userId] = { [DASH_TYPE_DEFAULT] = 0, [DASH_TYPE_SPECIAL] = 0 }
	self.activeDashes[userId] = nil
	self.playerRunning[userId] = false
	self.playerAutoRunEnabled[userId] = false -- ** เพิ่ม: ตั้งค่า AutoRun เริ่มต้นเป็น false **

	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")
	task.spawn(function()
		if not humanoid.Parent then humanoid.AncestryChanged:Wait() end
		if not Players:GetPlayerByUserId(userId) then return end
		humanoid:SetAttribute(ATTR_THIEF_BOOST_ENDTIME, nil); humanoid:SetAttribute(ATTR_THIEF_BOOST_SPEED, nil); humanoid:SetAttribute(ATTR_ORIGINAL_SPEED, nil)
		humanoid.WalkSpeed = DEFAULT_WALKSPEED; humanoid.AutoRotate = true
		print("[MovementSystem] Reset attributes and speed for player:", player.Name)
		-- ** เพิ่ม: ส่งสถานะ AutoRun เริ่มต้นให้ Client **
		self.autoRunStateChangedEvent:FireClient(player, self.playerAutoRunEnabled[userId])
	end)
end

-- Cleanup player (Modified)
function MovementSystem:CleanupPlayer(player)
	local userId = player.UserId
	print("[MovementSystem] Cleaning up player:", player.Name)
	self.playerCooldowns[userId] = nil
	self.activeDashes[userId] = nil
	self.playerRunning[userId] = nil
	self.playerAutoRunEnabled[userId] = nil -- ** เพิ่ม: ล้างสถานะ AutoRun **
end

-- Register system (Existing)
function MovementSystem:Register()
	local gameManager = _G.GameManager; if gameManager then gameManager.movementSystem = self; print("[MovementSystem] Registered with GameManager") else warn("[MovementSystem] GameManager not found, MovementSystem may not be accessible globally.") end
	for _, player in pairs(Players:GetPlayers()) do task.spawn(self.InitializePlayer, self, player) end
	Players.PlayerAdded:Connect(function(player) self:InitializePlayer(player); player.CharacterAdded:Connect(function(character) task.wait(0.1); self:InitializePlayer(player) end) end)
	Players.PlayerRemoving:Connect(function(player) self:CleanupPlayer(player) end)
	print("[MovementSystem] System Ready (v2.1.0 - AutoRun Added).")
end

return MovementSystem
