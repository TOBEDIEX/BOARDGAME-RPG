-- MovementSystem.lua
-- Module for managing movement abilities including dash and running (Server-Side)
-- Version: 2.0.0 (Server-Authoritative Speed Control, Optimized)

local MovementSystem = {}
MovementSystem.__index = MovementSystem

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local Debris = game:GetService("Debris") -- เพิ่ม Debris Service

-- Constants
local DASH_COLLISION_GROUP = "DashingPlayers"
local DEFAULT_COLLISION_GROUP = "Default"
local DEFAULT_WALKSPEED = 16

-- Attribute Names (ใช้ Constants เพื่อลดการพิมพ์ผิด)
local ATTR_CLASS = "Class"
local ATTR_THIEF_BOOST_ENDTIME = "ThiefBoostEndTime"
local ATTR_THIEF_BOOST_SPEED = "ThiefBoostSpeed"
local ATTR_ORIGINAL_SPEED = "OriginalWalkSpeed" -- เก็บ Speed ก่อน Boost/Dash

-- Running Constants
-- Speed Multipliers ถูกย้ายไป CLASS_RUN_SETTINGS

-- Dash Types (ใช้ Constants)
local DASH_TYPE_DEFAULT = "Default"
local DASH_TYPE_SPECIAL = "Special"

-- Dash Effects (ใช้ Constants)
local EFFECT_ROLL = "Roll"
local EFFECT_VANISH = "Vanish"

-- Dash Directions (ใช้ Constants)
local DIR_FRONT = "Front"
local DIR_BACK = "Back"
local DIR_LEFT = "Left"
local DIR_RIGHT = "Right"

-- Class Settings (ใช้ Constants ที่ประกาศไว้)
local CLASS_DASH_SETTINGS = {
	Warrior = {
		[DASH_TYPE_DEFAULT] = { Distance = 12, Duration = 0.3, Cooldown = 2.0, Effect = EFFECT_ROLL, EffectColor = Color3.fromRGB(255, 130, 0), AnimationRequired = true, SpeedBoost = 0, SpeedBoostDuration = 0 }
	},
	Mage = {
		[DASH_TYPE_DEFAULT] = { Distance = 15, Duration = 0.3, Cooldown = 3.5, Effect = EFFECT_ROLL, EffectColor = Color3.fromRGB(70, 130, 255), AnimationRequired = true, SpeedBoost = 0, SpeedBoostDuration = 0 }
	},
	Thief = {
		[DASH_TYPE_DEFAULT] = { Distance = 15, Duration = 0.3, Cooldown = 2.0, Effect = EFFECT_ROLL, EffectColor = Color3.fromRGB(110, 255, 110), AnimationRequired = true, SpeedBoost = 0, SpeedBoostDuration = 0 },
		[DASH_TYPE_SPECIAL] = { Distance = 18, Duration = 0.25, Cooldown = 5.0, Effect = EFFECT_VANISH, EffectColor = Color3.fromRGB(110, 255, 110), AnimationRequired = false, SpeedBoost = 34, SpeedBoostDuration = 1.25 } -- Vanish effect will use SpeedBoostDuration
	}
}

-- Class Running Settings (ใช้ Constants)
local CLASS_RUN_SETTINGS = {
	Warrior = { SpeedMultiplier = 1.7 }, -- ปรับค่าตามต้องการ
	Mage = { SpeedMultiplier = 1.5 },    -- ปรับค่าตามต้องการ
	Thief = { SpeedMultiplier = 1.8 }     -- ปรับค่าตามต้องการ
}

local DEFAULT_DASH_SETTINGS = { Distance = 14, Duration = 0.35, Cooldown = 2.5, Effect = EFFECT_ROLL, EffectColor = Color3.fromRGB(200, 200, 200), AnimationRequired = true, SpeedBoost = 0, SpeedBoostDuration = 0 }
local DEFAULT_RUN_SETTINGS = { SpeedMultiplier = 1.6 } -- ค่า Default หากไม่พบคลาส

-- Animation IDs (ใช้ Constants)
local DASH_ANIMATIONS = {
	[DIR_FRONT] = "rbxassetid://14103831900",
	[DIR_BACK] = "rbxassetid://14103833544",
	[DIR_LEFT] = "rbxassetid://14103834807",
	[DIR_RIGHT] = "rbxassetid://14103836416"
}

-- Constructor
function MovementSystem.new(combatService)
	local self = setmetatable({}, MovementSystem)
	self.combatService = combatService
	self.activeDashes = {} -- Structure: {userId = dashData}
	self.playerCooldowns = {} -- Structure: {userId = {Default = endTime, Special = endTime}}
	self.playerRunning = {} -- Structure: {userId = isRunning}

	self:SetupCollisionGroup()
	self:SetupRemoteEvents()
	self:StartBoostCleanupLoop() -- เริ่ม Loop ตรวจสอบ Boost ที่หมดอายุ
	return self
end

-- Setup Collision Group
function MovementSystem:SetupCollisionGroup()
	-- สร้าง Collision Group ถ้ายังไม่มี (ใช้ pcall เพื่อป้องกัน error หากสร้างไว้แล้ว)
	local success, exists = pcall(function() return PhysicsService:GetCollisionGroupId(DASH_COLLISION_GROUP) end)
	if not success or not exists then
		pcall(function()
			PhysicsService:CreateCollisionGroup(DASH_COLLISION_GROUP)
			PhysicsService:CollisionGroupSetCollidable(DASH_COLLISION_GROUP, DASH_COLLISION_GROUP, false) -- Dashing players don't collide with each other
			PhysicsService:CollisionGroupSetCollidable(DASH_COLLISION_GROUP, DEFAULT_COLLISION_GROUP, true) -- Dashing players collide with default objects
			print("[MovementSystem] Collision group", DASH_COLLISION_GROUP, "created.")
		end)
	end
end

-- Set up remote events
function MovementSystem:SetupRemoteEvents()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local combatRemotes = remotes:FindFirstChild("CombatRemotes") or Instance.new("Folder", remotes)
	combatRemotes.Name = "CombatRemotes"

	-- Dash Events
	self.dashRequest = combatRemotes:FindFirstChild("DashRequest") or Instance.new("RemoteEvent", combatRemotes)
	self.dashRequest.Name = "DashRequest"
	self.specialDashRequest = combatRemotes:FindFirstChild("SpecialDashRequest") or Instance.new("RemoteEvent", combatRemotes)
	self.specialDashRequest.Name = "SpecialDashRequest"
	self.dashEffect = combatRemotes:FindFirstChild("DashEffect") or Instance.new("RemoteEvent", combatRemotes) -- ส่ง Effect ไป Client
	self.dashEffect.Name = "DashEffect"
	self.dashCooldown = combatRemotes:FindFirstChild("DashCooldown") or Instance.new("RemoteEvent", combatRemotes) -- ส่ง Cooldown ไป Client
	self.dashCooldown.Name = "DashCooldown"

	-- Running Events
	self.runRequest = combatRemotes:FindFirstChild("RunRequest") or Instance.new("RemoteEvent", combatRemotes) -- รับคำขอวิ่ง/หยุดวิ่งจาก Client
	self.runRequest.Name = "RunRequest"
	self.runState = combatRemotes:FindFirstChild("RunState") or Instance.new("RemoteEvent", combatRemotes) -- ส่งสถานะการวิ่ง (จริง/เท็จ) ไปยัง Client อื่นๆ (ถ้าต้องการ)
	self.runState.Name = "RunState"

	-- ลบ setSpeedEvent ออก เพราะ Server จะควบคุม Speed โดยตรง
	local oldSetSpeed = combatRemotes:FindFirstChild("SetSpeed")
	if oldSetSpeed then oldSetSpeed:Destroy() end

	-- Connect Handlers
	self.dashRequest.OnServerEvent:Connect(function(player, direction)
		-- ใช้ Constants แทน String โดยตรง
		self:ProcessDashRequest(player, direction, DASH_TYPE_DEFAULT)
	end)
	self.specialDashRequest.OnServerEvent:Connect(function(player, direction)
		-- ใช้ Constants แทน String โดยตรง
		self:ProcessDashRequest(player, direction, DASH_TYPE_SPECIAL)
	end)
	self.runRequest.OnServerEvent:Connect(function(player, isRunning)
		self:SetPlayerRunningState(player, isRunning)
	end)
end

-- Process dash request from client
function MovementSystem:ProcessDashRequest(player, direction, dashType)
	local playerId = player.UserId
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	-- Basic checks
	if not humanoid or humanoid:GetState() == Enum.HumanoidStateType.Dead then return false end
	if not self.combatService or not self.combatService:IsCombatActive() then return false end -- ต้องอยู่ใน Combat Mode
	if self.activeDashes[playerId] then return false end -- กำลัง Dash อยู่แล้ว

	-- Check class for special dash
	local playerClass = self:GetPlayerClass(player)
	if dashType == DASH_TYPE_SPECIAL and playerClass ~= "Thief" then
		print("[MovementSystem] Player", player.Name, "is not Thief, cannot use Special Dash.")
		return false
	end

	-- Initialize cooldowns if not present
	if not self.playerCooldowns[playerId] then
		self.playerCooldowns[playerId] = { [DASH_TYPE_DEFAULT] = 0, [DASH_TYPE_SPECIAL] = 0 }
	end

	local currentTime = time() -- ใช้ time() แทน tick()
	local cooldownData = self.playerCooldowns[playerId]
	local dashSettings = self:GetDashSettings(playerClass, dashType)

	-- Check cooldown for the requested dash type
	if cooldownData[dashType] and cooldownData[dashType] > currentTime then
		local remainingCooldown = cooldownData[dashType] - currentTime
		self.dashCooldown:FireClient(player, remainingCooldown, dashType) -- แจ้ง Client เรื่อง Cooldown ที่เหลือ
		print("[MovementSystem] Player", player.Name, dashType, "Dash on cooldown. Remaining:", remainingCooldown)
		return false
	end

	-- Check cooldown for the *other* dash type (Thief can't use default while special is on CD, and vice-versa)
	if playerClass == "Thief" then
		local otherDashType = (dashType == DASH_TYPE_DEFAULT) and DASH_TYPE_SPECIAL or DASH_TYPE_DEFAULT
		if cooldownData[otherDashType] and cooldownData[otherDashType] > currentTime then
			local remainingOtherCooldown = cooldownData[otherDashType] - currentTime
			self.dashCooldown:FireClient(player, remainingOtherCooldown, dashType) -- แจ้ง Client ว่า Dash อื่นติด Cooldown
			print("[MovementSystem] Player", player.Name, "Thief's other dash ("..otherDashType..") on cooldown. Remaining:", remainingOtherCooldown)
			return false
		end
	end

	-- Attempt to perform the dash
	local success = self:PerformDash(player, direction, dashSettings, dashType)
	if success then
		-- Set cooldown
		self.playerCooldowns[playerId][dashType] = currentTime + dashSettings.Cooldown
		self.dashCooldown:FireClient(player, dashSettings.Cooldown, dashType) -- แจ้ง Client เรื่อง Cooldown ใหม่
		print("[MovementSystem] Player", player.Name, "performed", dashType, "Dash. Cooldown:", dashSettings.Cooldown)
	end
	return success
end

-- Get dash settings based on class and type
function MovementSystem:GetDashSettings(playerClass, dashType)
	if CLASS_DASH_SETTINGS[playerClass] then
		if dashType == DASH_TYPE_SPECIAL and CLASS_DASH_SETTINGS[playerClass][DASH_TYPE_SPECIAL] then
			return CLASS_DASH_SETTINGS[playerClass][DASH_TYPE_SPECIAL]
		elseif CLASS_DASH_SETTINGS[playerClass][DASH_TYPE_DEFAULT] then
			return CLASS_DASH_SETTINGS[playerClass][DASH_TYPE_DEFAULT]
		end
	end
	-- Fallback to default settings if class or specific type not found
	return DEFAULT_DASH_SETTINGS
end


-- Set player running state (SERVER-AUTHORITATIVE)
function MovementSystem:SetPlayerRunningState(player, isRunning)
	local playerId = player.UserId
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	-- Basic checks
	if not humanoid or humanoid:GetState() == Enum.HumanoidStateType.Dead then return end
	if self.activeDashes[playerId] then return end -- ห้ามวิ่งขณะ Dash
	if not self.combatService or not self.combatService:IsCombatActive() then
		-- ถ้าไม่ได้อยู่ใน Combat Mode และพยายามจะวิ่ง ให้หยุดวิ่งเสมอ
		if isRunning then isRunning = false end
		-- ถ้าไม่ได้อยู่ใน Combat Mode และกำลังวิ่งอยู่ (เช่น Combat เพิ่งจบ) ให้หยุดวิ่ง
		if self.playerRunning[playerId] then isRunning = false end
	end

	-- ถ้าสถานะไม่เปลี่ยนแปลง ก็ไม่ต้องทำอะไร
	if self.playerRunning[playerId] == isRunning then return end

	-- อัปเดตสถานะการวิ่งบน Server
	self.playerRunning[playerId] = isRunning

	-- ล้าง Boost ของ Thief ถ้ามี ก่อนเปลี่ยน Speed
	self:ClearThiefBoost(humanoid)

	-- คำนวณและตั้งค่า WalkSpeed โดยตรงบน Server
	if isRunning then
		local playerClass = self:GetPlayerClass(player)
		local runSettings = CLASS_RUN_SETTINGS[playerClass] or DEFAULT_RUN_SETTINGS
		local runSpeed = DEFAULT_WALKSPEED * runSettings.SpeedMultiplier

		-- เก็บ Speed เดิมไว้ก่อนวิ่ง (ถ้ายังไม่มี)
		if not humanoid:GetAttribute(ATTR_ORIGINAL_SPEED) then
			humanoid:SetAttribute(ATTR_ORIGINAL_SPEED, humanoid.WalkSpeed)
		end
		humanoid.WalkSpeed = runSpeed
		print(string.format("[MovementSystem] Player %s started running. Class: %s, Speed: %.2f", player.Name, playerClass, runSpeed))
	else
		-- หยุดวิ่ง: คืนค่า Speed เป็นค่าเดิมก่อนวิ่ง หรือค่า Default
		local originalSpeed = humanoid:GetAttribute(ATTR_ORIGINAL_SPEED) or DEFAULT_WALKSPEED
		humanoid.WalkSpeed = originalSpeed
		humanoid:SetAttribute(ATTR_ORIGINAL_SPEED, nil) -- ล้าง Attribute Speed เดิมออก
		print(string.format("[MovementSystem] Player %s stopped running. Reset speed to: %.2f", player.Name, originalSpeed))
	end

	-- แจ้ง Client อื่นๆ (ถ้าจำเป็น) ว่าสถานะการวิ่งเปลี่ยนไป
	-- self.runState:FireAllClients(playerId, isRunning) -- อาจจะไม่จำเป็นถ้า Client จัดการ Animation เองได้
end

-- Get player's class (Simplified - assumes GameManager sets attribute or similar reliable method)
function MovementSystem:GetPlayerClass(player)
	-- พยายามอ่านจาก Attribute บน Humanoid ก่อน (ควรเป็นวิธีหลัก)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local classAttr = humanoid:GetAttribute(ATTR_CLASS)
		if classAttr and typeof(classAttr) == "string" then
			return classAttr
		end
	end

	-- Fallback: ลองใช้ GameManager (ถ้ามี)
	local gameManager = _G.GameManager
	if gameManager then
		if gameManager.classSystem and gameManager.classSystem.GetPlayerClass then
			local classFromSystem = gameManager.classSystem:GetPlayerClass(player)
			if classFromSystem then return classFromSystem end
		end
		if gameManager.playerManager and gameManager.playerManager.GetPlayerData then
			local playerData = gameManager.playerManager:GetPlayerData(player)
			if playerData and playerData.class then return playerData.class end
		end
	end

	-- ถ้ายังไม่ได้ ให้ค่า Default ไปก่อน
	warn("[MovementSystem] Could not determine class for player:", player.Name, "- Using 'Unknown'")
	return "Unknown"
end

-- Perform the actual dash movement and effects
function MovementSystem:PerformDash(player, directionString, dashSettings, dashType)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")

	-- Double-check conditions
	if not humanoid or not hrp or humanoid:GetState() == Enum.HumanoidStateType.Dead then return false end
	if self.activeDashes[player.UserId] then return false end -- Already dashing check again
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then return false end -- Cannot dash mid-air

	local playerId = player.UserId

	-- หยุดวิ่งก่อน Dash (ถ้ากำลังวิ่งอยู่)
	local wasRunning = self.playerRunning[playerId]
	if wasRunning then
		self:SetPlayerRunningState(player, false) -- Server หยุดการวิ่งและปรับ Speed
	end

	-- เก็บข้อมูล Dash
	local dashData = {
		player = player,
		settings = dashSettings,
		startTime = time(), -- ใช้ time()
		completed = false,
		originalCollisionGroups = {}, -- เปลี่ยนชื่อให้ชัดเจนขึ้น
		originalWalkSpeed = humanoid.WalkSpeed, -- เก็บ Speed ปัจจุบันก่อน Dash
		directionString = directionString,
		dashType = dashType,
		wasRunning = wasRunning -- เก็บสถานะการวิ่งก่อน Dash
	}
	self.activeDashes[playerId] = dashData

	-- เปลี่ยน Collision Group
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			dashData.originalCollisionGroups[part] = part.CollisionGroup -- เก็บ Group เดิม
			local success, err = pcall(function() part.CollisionGroup = DASH_COLLISION_GROUP end)
			if not success then warn("[MovementSystem] Failed to set collision group for", part:GetFullName(), ":", err) end
		end
	end

	-- โหลด Animation ID (ถ้าต้องการ)
	local animationId = dashSettings.AnimationRequired and DASH_ANIMATIONS[directionString] or nil

	-- คำนวณระยะเวลา Effect (สำหรับ Vanish จะนานกว่า)
	local effectDuration = dashSettings.Duration -- Default duration
	if dashSettings.Effect == EFFECT_VANISH and dashSettings.SpeedBoostDuration and dashSettings.SpeedBoostDuration > 0 then
		effectDuration = dashSettings.SpeedBoostDuration -- Vanish effect lasts for boost duration
	end

	-- ส่ง Event ให้ Client แสดงผล Effect (VFX, Animation)
	-- ส่ง duration ที่คำนวณแล้วไปด้วย
	self.dashEffect:FireClient(player, directionString, dashSettings.Effect, dashSettings.EffectColor, animationId, nil, dashType, effectDuration)

	-- ถ้าเป็น Vanish ส่ง Event ให้ Client อื่นๆ ด้วย (เพื่อให้เห็นตัวละครหายไป)
	if dashSettings.Effect == EFFECT_VANISH then
		for _, otherPlayer in pairs(Players:GetPlayers()) do
			if otherPlayer ~= player then
				-- ส่ง Player Source ไปด้วย เพื่อให้ Client อื่นรู้ว่าใครหายไป
				self.dashEffect:FireClient(otherPlayer, directionString, dashSettings.Effect, dashSettings.EffectColor, nil, player, dashType, effectDuration)
			end
		end
	end

	-- ใช้ LinearVelocity สำหรับการเคลื่อนที่
	self:ApplyDashVelocity(dashData)

	-- ตั้งเวลา Cleanup Dash (ใช้ task.delay)
	task.delay(dashSettings.Duration, function()
		-- ตรวจสอบว่า dashData ยังเป็นอันปัจจุบันหรือไม่ (ป้องกันกรณีผู้เล่นตายหรือออกจากเกมระหว่าง Dash)
		if self.activeDashes[playerId] == dashData then
			self:CleanupDash(playerId)
		end
	end)

	return true
end

-- Apply physics-based dash movement
function MovementSystem:ApplyDashVelocity(dashData)
	local player = dashData.player
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not hrp or not humanoid then
		self:CleanupDash(player.UserId) -- Cleanup if character parts are missing
		return
	end

	-- สร้าง Attachment ถ้ายังไม่มี
	local attachment = hrp:FindFirstChild("DashAttachment")
	if not attachment then
		attachment = Instance.new("Attachment", hrp)
		attachment.Name = "DashAttachment"
	end

	-- ลบ LinearVelocity เก่า (ถ้ามี)
	local oldVelocity = hrp:FindFirstChild("DashLinearVelocity")
	if oldVelocity then oldVelocity:Destroy() end

	-- คำนวณทิศทาง
	local moveDirectionVector = self:GetDirectionVector(dashData.directionString, character)

	-- สร้าง LinearVelocity ใหม่
	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "DashLinearVelocity"
	linearVelocity.Attachment0 = attachment
	linearVelocity.MaxForce = 100000 -- เพิ่มค่า MaxForce เพื่อให้แน่ใจว่าเอาชนะแรงเสียดทานได้
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	linearVelocity.LineDirection = moveDirectionVector
	linearVelocity.LineVelocity = dashData.settings.Distance / dashData.settings.Duration -- ความเร็ว = ระยะทาง / เวลา
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World -- เคลื่อนที่เทียบกับ World
	linearVelocity.Parent = hrp
	dashData.linearVelocity = linearVelocity -- เก็บ reference ไว้

	-- ปิดการควบคุมบางอย่างของ Humanoid ชั่วคราว
	humanoid.AutoRotate = false
	-- humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false) -- อาจจะไม่จำเป็น ถ้า LinearVelocity แรงพอ

	-- เพิ่มแรงต้านอากาศเล็กน้อยเพื่อให้หยุดนิ่งขึ้น (Optional)
	-- local bodyForce = Instance.new("BodyForce")
	-- bodyForce.Force = Vector3.new(0, humanoid:GetMass() * workspace.Gravity * 0.1, 0) -- แรงต้านแนวตั้งเล็กน้อย
	-- bodyForce.Parent = hrp
	-- Debris:AddItem(bodyForce, dashData.settings.Duration) -- ให้แรงนี้อยู่แค่ช่วง Dash

end

-- Get direction vector based on string and character orientation
function MovementSystem:GetDirectionVector(directionString, character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return Vector3.zAxis end -- Default forward

	local lookVector = hrp.CFrame.LookVector
	local rightVector = hrp.CFrame.RightVector

	if directionString == DIR_BACK then return -lookVector.Unit
	elseif directionString == DIR_LEFT then return -rightVector.Unit
	elseif directionString == DIR_RIGHT then return rightVector.Unit
	else return lookVector.Unit end -- Default to Front
end

-- Clean up resources and states after dash completion or interruption
function MovementSystem:CleanupDash(userId)
	local dashData = self.activeDashes[userId]
	if not dashData or dashData.completed then
		self.activeDashes[userId] = nil -- Ensure it's cleared if called multiple times
		return
	end

	dashData.completed = true -- Mark as completed to prevent double cleanup
	local player = dashData.player
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	-- Remove LinearVelocity
	if dashData.linearVelocity and dashData.linearVelocity.Parent then
		dashData.linearVelocity:Destroy()
	end

	-- Restore Collision Groups
	if character and dashData.originalCollisionGroups then
		for part, groupName in pairs(dashData.originalCollisionGroups) do
			if part and part.Parent then
				-- ใช้ pcall ป้องกัน Error หาก Part ถูกลบไปแล้ว
				pcall(function() part.CollisionGroup = groupName or DEFAULT_COLLISION_GROUP end)
			end
		end
	end

	-- Restore Humanoid state
	if humanoid and humanoid.Parent then
		humanoid.AutoRotate = true
		-- humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)

		-- Handle Thief Speed Boost (Server-Side)
		if dashData.dashType == DASH_TYPE_SPECIAL and dashData.settings.Effect == EFFECT_VANISH and dashData.settings.SpeedBoost > 0 and dashData.settings.SpeedBoostDuration > 0 then
			local boostedSpeed = dashData.settings.SpeedBoost
			local boostEndTime = time() + dashData.settings.SpeedBoostDuration

			-- เก็บ Speed ปัจจุบัน (ซึ่งควรจะเป็นค่า Default หรือค่าก่อน Dash)
			humanoid:SetAttribute(ATTR_ORIGINAL_SPEED, humanoid.WalkSpeed)
			humanoid:SetAttribute(ATTR_THIEF_BOOST_SPEED, boostedSpeed)
			humanoid:SetAttribute(ATTR_THIEF_BOOST_ENDTIME, boostEndTime)
			humanoid.WalkSpeed = boostedSpeed -- ตั้งค่า Speed Boost ทันที
			print(string.format("[MovementSystem] Player %s (Thief) started Speed Boost. Speed: %.2f, Duration: %.2fs", player.Name, boostedSpeed, dashData.settings.SpeedBoostDuration))

			-- ไม่ต้องใช้ task.delay ที่นี่แล้ว เพราะมี BoostCleanupLoop จัดการ
		else
			-- ไม่ใช่ Thief Boost หรือไม่มี Boost: คืนค่า Speed เป็นค่าก่อน Dash
			humanoid.WalkSpeed = dashData.originalWalkSpeed
			print(string.format("[MovementSystem] Player %s finished Dash. Reset speed to: %.2f", player.Name, dashData.originalWalkSpeed))

			-- ถ้าก่อน Dash กำลังวิ่งอยู่ ให้กลับไปวิ่งต่อ (Server จะปรับ Speed ให้เอง)
			if dashData.wasRunning then
				task.wait(0.05) -- รอเล็กน้อยเพื่อให้แน่ใจว่า Dash Cleanup เสร็จสมบูรณ์
				-- ตรวจสอบอีกครั้งว่ายังอยู่ใน Combat Mode หรือไม่
				if self.combatService and self.combatService:IsCombatActive() and not self.activeDashes[userId] then
					print(string.format("[MovementSystem] Player %s was running before dash, resuming run.", player.Name))
					self:SetPlayerRunningState(player, true)
				end
			end
		end
	end

	-- แจ้ง Client ว่า Dash เสร็จสมบูรณ์ (สำหรับ Client-side cleanup ถ้ามี)
	if player then
		self.dashEffect:FireClient(player, "Complete", nil, nil, nil, nil, dashData.dashType, 0)
	end

	-- เคลียร์ข้อมูล Dash ปัจจุบัน
	self.activeDashes[userId] = nil
end

-- Loop to check for expired Thief boosts
function MovementSystem:StartBoostCleanupLoop()
	task.spawn(function()
		while task.wait(0.5) do -- ตรวจสอบทุกๆ ครึ่งวินาที
			local currentTime = time()
			for userId, _ in pairs(self.playerCooldowns) do -- วนลูปผู้เล่นที่มีข้อมูลอยู่
				local player = Players:GetPlayerByUserId(userId)
				if player and player.Character then
					local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Parent then
						local boostEndTime = humanoid:GetAttribute(ATTR_THIEF_BOOST_ENDTIME)
						if boostEndTime and typeof(boostEndTime) == "number" and currentTime >= boostEndTime then
							-- Boost หมดเวลา
							local originalSpeed = humanoid:GetAttribute(ATTR_ORIGINAL_SPEED) or DEFAULT_WALKSPEED
							-- ตรวจสอบว่าไม่ได้กำลัง Dash หรือ วิ่ง อยู่ ก่อนคืนค่า Speed
							if not self.activeDashes[userId] and not self.playerRunning[userId] then
								humanoid.WalkSpeed = originalSpeed
								print(string.format("[MovementSystem] Player %s Thief Boost expired. Reset speed to: %.2f", player.Name, originalSpeed))
							elseif self.playerRunning[userId] then
								-- ถ้ากำลังวิ่งอยู่ ให้ปล่อยให้ SetPlayerRunningState จัดการ Speed
								print(string.format("[MovementSystem] Player %s Thief Boost expired while running. Speed will be handled by running state.", player.Name))
							end
							-- ล้าง Attributes ของ Boost
							humanoid:SetAttribute(ATTR_THIEF_BOOST_ENDTIME, nil)
							humanoid:SetAttribute(ATTR_THIEF_BOOST_SPEED, nil)
							humanoid:SetAttribute(ATTR_ORIGINAL_SPEED, nil) -- ล้าง Speed เดิมด้วย
						end
					end
				end
			end
		end
	end)
end

-- Function to clear Thief boost attributes immediately (e.g., when starting to run)
function MovementSystem:ClearThiefBoost(humanoid)
	if humanoid and humanoid.Parent then
		if humanoid:GetAttribute(ATTR_THIEF_BOOST_ENDTIME) then
			humanoid:SetAttribute(ATTR_THIEF_BOOST_ENDTIME, nil)
			humanoid:SetAttribute(ATTR_THIEF_BOOST_SPEED, nil)
			-- ไม่ต้องคืนค่า Speed ที่นี่ เพราะฟังก์ชันที่เรียก ClearThiefBoost จะตั้งค่า Speed ใหม่เอง
			print("[MovementSystem] Cleared active Thief Boost attributes.")
		end
		-- ไม่ควรล้าง ATTR_ORIGINAL_SPEED ที่นี่ เพราะอาจจะยังต้องใช้
	end
end


-- Clear cooldown for a player
function MovementSystem:ClearCooldown(player, dashType)
	local playerId = typeof(player) == "Instance" and player.UserId or player
	if not playerId then return end

	if not self.playerCooldowns[playerId] then return end -- ไม่มีข้อมูล Cooldown

	local playerInstance = typeof(player) == "Instance" and player or Players:GetPlayerByUserId(playerId)

	if dashType and (dashType == DASH_TYPE_DEFAULT or dashType == DASH_TYPE_SPECIAL) then
		if self.playerCooldowns[playerId][dashType] then
			self.playerCooldowns[playerId][dashType] = 0
			if playerInstance then self.dashCooldown:FireClient(playerInstance, 0, dashType) end
			print("[MovementSystem] Cleared", dashType, "cooldown for player", playerId)
		end
	else -- Clear all cooldowns if type is nil or invalid
		self.playerCooldowns[playerId] = { [DASH_TYPE_DEFAULT] = 0, [DASH_TYPE_SPECIAL] = 0 }
		if playerInstance then
			self.dashCooldown:FireClient(playerInstance, 0, DASH_TYPE_DEFAULT)
			self.dashCooldown:FireClient(playerInstance, 0, DASH_TYPE_SPECIAL)
		end
		print("[MovementSystem] Cleared all dash cooldowns for player", playerId)
	end
end

-- Initialize player state when they join or respawn
function MovementSystem:InitializePlayer(player)
	local userId = player.UserId
	print("[MovementSystem] Initializing player:", player.Name)

	-- Cleanup any lingering dash state
	if self.activeDashes[userId] then
		print("[MovementSystem] Cleaning up lingering dash for player:", player.Name)
		self:CleanupDash(userId)
	end

	-- Reset states
	self.playerCooldowns[userId] = { [DASH_TYPE_DEFAULT] = 0, [DASH_TYPE_SPECIAL] = 0 }
	self.activeDashes[userId] = nil
	self.playerRunning[userId] = false

	-- Wait for character and humanoid, then reset attributes and speed
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")

	-- ใช้ task.spawn เพื่อไม่ให้ block ถ้าต้องรอ Humanoid นาน
	task.spawn(function()
		if not humanoid.Parent then humanoid.AncestryChanged:Wait() end -- รอให้ Humanoid อยู่ใน hierarchy

		-- ตรวจสอบอีกครั้งว่าผู้เล่นยังอยู่
		if not Players:GetPlayerByUserId(userId) then return end

		-- Reset Attributes and Speed
		humanoid:SetAttribute(ATTR_THIEF_BOOST_ENDTIME, nil)
		humanoid:SetAttribute(ATTR_THIEF_BOOST_SPEED, nil)
		humanoid:SetAttribute(ATTR_ORIGINAL_SPEED, nil)
		humanoid.WalkSpeed = DEFAULT_WALKSPEED
		humanoid.AutoRotate = true -- Ensure autorotate is on
		print("[MovementSystem] Reset attributes and speed for player:", player.Name)
	end)
end

-- Cleanup player state when they leave
function MovementSystem:CleanupPlayer(player)
	local userId = player.UserId
	print("[MovementSystem] Cleaning up player:", player.Name)

	-- Clear states
	self.playerCooldowns[userId] = nil
	self.activeDashes[userId] = nil
	self.playerRunning[userId] = nil

	-- ไม่จำเป็นต้อง reset attribute หรือ speed เพราะตัวละครจะถูกลบไปแล้ว
end

-- Register system with GameManager and connect player events
function MovementSystem:Register()
	local gameManager = _G.GameManager
	if gameManager then
		gameManager.movementSystem = self
		print("[MovementSystem] Registered with GameManager")
	else
		warn("[MovementSystem] GameManager not found, MovementSystem may not be accessible globally.")
	end

	-- Handle existing players
	for _, player in pairs(Players:GetPlayers()) do
		task.spawn(self.InitializePlayer, self, player)
	end

	-- Connect events for players joining/leaving/respawning
	Players.PlayerAdded:Connect(function(player)
		self:InitializePlayer(player)
		player.CharacterAdded:Connect(function(character)
			-- Re-initialize some states on respawn, especially speed and attributes
			task.wait(0.1) -- ให้เวลาตัวละครโหลดเล็กน้อย
			self:InitializePlayer(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:CleanupPlayer(player)
	end)

	print("[MovementSystem] System Ready.")
end

return MovementSystem
