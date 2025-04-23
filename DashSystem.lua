-- DashSystem.lua
-- Module for managing dash abilities in combat
-- Version: 1.1.5 (ใช้ Attribute จัดการ Thief Speed Boost)

local DashSystem = {}
DashSystem.__index = DashSystem

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")

-- Constants
local DASH_COLLISION_GROUP = "DashingPlayers"
local DEFAULT_COLLISION_GROUP = "Default"
local DEFAULT_WALKSPEED = 16
local THIEF_BOOST_ENDTIME_ATTR = "ThiefBoostEndTime" -- ชื่อ Attribute
local THIEF_BOOST_SPEED_ATTR = "ThiefBoostSpeed" -- เก็บค่า Speed ที่ Boost แล้ว
local ORIGINAL_SPEED_ATTR = "OriginalWalkSpeed" -- เก็บค่า Speed เดิม

-- Class Settings (เหมือนเดิม)
local CLASS_DASH_SETTINGS = {
	Warrior = { Distance = 12, Duration = 0.3, Cooldown = 2.0, Effect = "Roll", EffectColor = Color3.fromRGB(255, 130, 0), AnimationRequired = true, SpeedBoost = 0, SpeedBoostDuration = 0 },
	Mage = { Distance = 15, Duration = 0.35, Cooldown = 3.5, Effect = "Roll", EffectColor = Color3.fromRGB(70, 130, 255), AnimationRequired = true, SpeedBoost = 0, SpeedBoostDuration = 0 },
	Thief = { Distance = 18, Duration = 0.25, Cooldown = 3.0, Effect = "Vanish", EffectColor = Color3.fromRGB(110, 255, 110), AnimationRequired = false, SpeedBoost = 24, SpeedBoostDuration = 1.5 }
}
local DEFAULT_DASH_SETTINGS = { Distance = 14, Duration = 0.35, Cooldown = 2.5, Effect = "Roll", EffectColor = Color3.fromRGB(200, 200, 200), AnimationRequired = true, SpeedBoost = 0, SpeedBoostDuration = 0 }
local DASH_ANIMATIONS = { Front = "rbxassetid://14103831900", Back = "rbxassetid://14103833544", Left = "rbxassetid://14103834807", Right = "rbxassetid://14103836416" }

-- Constructor
function DashSystem.new(combatService)
	local self = setmetatable({}, DashSystem)
	self.combatService = combatService
	self.activeDashes = {}
	self.playerCooldowns = {}
	-- ไม่ต้องใช้ originalSpeeds และ activeBoosts แล้ว
	self:SetupCollisionGroup()
	self:SetupRemoteEvents()
	-- ไม่ต้อง StartBoostManager แล้ว
	return self
end

-- ตั้งค่า Collision Group (เหมือนเดิม)
function DashSystem:SetupCollisionGroup()
	local success, result = pcall(function() return PhysicsService:GetCollisionGroupId(DASH_COLLISION_GROUP) end)
	if not success or not result then
		pcall(function()
			PhysicsService:CreateCollisionGroup(DASH_COLLISION_GROUP)
			PhysicsService:CollisionGroupSetCollidable(DASH_COLLISION_GROUP, DASH_COLLISION_GROUP, false)
			PhysicsService:CollisionGroupSetCollidable(DASH_COLLISION_GROUP, DEFAULT_COLLISION_GROUP, true)
		end)
	end
end

-- Set up remote events (เหมือนเดิม)
function DashSystem:SetupRemoteEvents()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local combatRemotes = remotes:FindFirstChild("CombatRemotes") or Instance.new("Folder", remotes); combatRemotes.Name = "CombatRemotes"
	self.dashRequest = combatRemotes:FindFirstChild("DashRequest") or Instance.new("RemoteEvent", combatRemotes); self.dashRequest.Name = "DashRequest"
	self.dashEffect = combatRemotes:FindFirstChild("DashEffect") or Instance.new("RemoteEvent", combatRemotes); self.dashEffect.Name = "DashEffect"
	self.dashCooldown = combatRemotes:FindFirstChild("DashCooldown") or Instance.new("RemoteEvent", combatRemotes); self.dashCooldown.Name = "DashCooldown"
	self.dashRequest.OnServerEvent:Connect(function(player, direction) self:ProcessDashRequest(player, direction) end)
end

-- Process dash request (เหมือนเดิม)
function DashSystem:ProcessDashRequest(player, direction)
	local playerId = player.UserId
	if not self.combatService or not self.combatService:IsCombatActive() then return false end
	if self.playerCooldowns[playerId] and self.playerCooldowns[playerId] > tick() then
		self.dashCooldown:FireClient(player, self.playerCooldowns[playerId] - tick()); return false
	end
	if self.activeDashes[playerId] then return false end
	local playerClass = self:GetPlayerClass(player)
	local dashSettings = self:GetDashSettingsForClass(playerClass)
	local success = self:PerformDash(player, direction, dashSettings)
	if success then
		self.playerCooldowns[playerId] = tick() + dashSettings.Cooldown
		self.dashCooldown:FireClient(player, dashSettings.Cooldown)
	end
	return success
end

-- Get player's class (เหมือนเดิม)
function DashSystem:GetPlayerClass(player)
	local gameManager = _G.GameManager
	if gameManager and gameManager.classSystem then local c=gameManager.classSystem:GetPlayerClass(player); if c then return c end end
	if gameManager and gameManager.playerManager then local d=gameManager.playerManager:GetPlayerData(player); if d and d.class then return d.class end end
	return "Unknown"
end

-- Get dash settings (เหมือนเดิม)
function DashSystem:GetDashSettingsForClass(className) return CLASS_DASH_SETTINGS[className] or DEFAULT_DASH_SETTINGS end

-- Perform dash (ปรับปรุง: ไม่เก็บ original speed ที่นี่)
function DashSystem:PerformDash(player, direction, dashSettings)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp or humanoid:GetState() == Enum.HumanoidStateType.Dead then return false end
	if self.activeDashes[player.UserId] then return false end
	if humanoid:GetState() == Enum.HumanoidStateType.Jumping or humanoid:GetState() == Enum.HumanoidStateType.Freefall then return false end

	local dashData = { player = player, settings = dashSettings, startTime = tick(), completed = false, originalCollisionGroup = {}, directionString = direction }
	self.activeDashes[player.UserId] = dashData
	-- ไม่ต้องเก็บ originalSpeeds ที่นี่แล้ว

	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then dashData.originalCollisionGroup[part] = part.CollisionGroup; part.CollisionGroup = DASH_COLLISION_GROUP end
	end

	local animationId = dashSettings.AnimationRequired and self:DetermineAnimationId(direction) or nil
	self.dashEffect:FireClient(player, direction, dashData.settings.Effect, dashData.settings.EffectColor, animationId)

	if dashData.settings.Effect == "Vanish" then
		for _, otherPlayer in pairs(Players:GetPlayers()) do
			if otherPlayer ~= player then self.dashEffect:FireClient(otherPlayer, direction, dashData.settings.Effect, dashData.settings.EffectColor, nil, player) end
		end
	end

	self:ApplyDashVelocity(dashData)
	return true
end

-- Get direction vector (เหมือนเดิม)
function DashSystem:GetDirectionVector(directionString, character)
	local hrp = character:FindFirstChild("HumanoidRootPart"); if not hrp then return Vector3.zAxis end
	local lookVector = hrp.CFrame.LookVector; local rightVector = hrp.CFrame.RightVector
	if directionString == "Back" then return -lookVector.Unit
	elseif directionString == "Left" then return -rightVector.Unit
	elseif directionString == "Right" then return rightVector.Unit
	else return lookVector.Unit end
end

-- Determine animation ID (เหมือนเดิม)
function DashSystem:DetermineAnimationId(direction) return DASH_ANIMATIONS[direction] or DASH_ANIMATIONS.Front end

-- Apply dash velocity (เหมือนเดิม)
function DashSystem:ApplyDashVelocity(dashData)
	local player = dashData.player; local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then self:CleanupDash(player.UserId); return end
	local attachment = hrp:FindFirstChild("DashAttachment") or Instance.new("Attachment", hrp); attachment.Name = "DashAttachment"
	local oldVelocity = hrp:FindFirstChild("DashLinearVelocity"); if oldVelocity then oldVelocity:Destroy() end
	local moveDirectionVector = self:GetDirectionVector(dashData.directionString, character)
	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "DashLinearVelocity"; linearVelocity.Attachment0 = attachment; linearVelocity.MaxForce = 60000
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Line; linearVelocity.LineDirection = moveDirectionVector
	linearVelocity.LineVelocity = dashData.settings.Distance / dashData.settings.Duration; linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.Parent = hrp; dashData.linearVelocity = linearVelocity
	humanoid.AutoRotate = false; humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
	if dashData.settings.Effect == "Vanish" then
		dashData.originalTransparency = {}
		for _, part in pairs(character:GetDescendants()) do if part:IsA("BasePart") or part:IsA("Decal") then dashData.originalTransparency[part] = part.Transparency; part.Transparency = 1 end end
	end
	task.delay(dashData.settings.Duration, function() if self.activeDashes[player.UserId] == dashData then self:CleanupDash(player.UserId) end end)
end

-- Clean up after dash (ปรับปรุง: ตั้ง Attribute สำหรับ Thief Boost)
function DashSystem:CleanupDash(userId)
	local dashData = self.activeDashes[userId]
	if not dashData or dashData.completed then
		if self.activeDashes[userId] then self.activeDashes[userId] = nil end
		return
	end
	dashData.completed = true
	local player = dashData.player
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if dashData.linearVelocity and dashData.linearVelocity.Parent then dashData.linearVelocity:Destroy() end

	if character and dashData.originalCollisionGroup then
		for part, groupName in pairs(dashData.originalCollisionGroup) do if part and part.Parent then part.CollisionGroup = groupName or DEFAULT_COLLISION_GROUP end end
	end

	if humanoid and humanoid.Parent then
		humanoid.AutoRotate = true
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)

		-- ไม่ต้องคืนค่า WalkSpeed ที่นี่แล้ว Client จะจัดการเอง

		if dashData.settings.Effect == "Vanish" and dashData.originalTransparency then
			for part, origTransparency in pairs(dashData.originalTransparency) do if part and part.Parent then part.Transparency = origTransparency end end
		end

		-- Apply Thief Speed Boost (Set Attributes)
		if dashData.settings.SpeedBoost > 0 and dashData.settings.SpeedBoostDuration > 0 then
			local originalSpeed = humanoid.WalkSpeed -- อ่านค่าปัจจุบันก่อน Boost
			local boostedSpeed = originalSpeed + dashData.settings.SpeedBoost
			local boostEndTime = tick() + dashData.settings.SpeedBoostDuration

			humanoid:SetAttribute(ORIGINAL_SPEED_ATTR, originalSpeed)
			humanoid:SetAttribute(THIEF_BOOST_SPEED_ATTR, boostedSpeed)
			humanoid:SetAttribute(THIEF_BOOST_ENDTIME_ATTR, boostEndTime)
			-- print(string.format("[DashSystem] Player %d: Set boost attributes. EndTime: %.2f", userId, boostEndTime)) -- Debug

			-- Schedule attribute removal
			task.delay(dashData.settings.SpeedBoostDuration + 0.1, function() -- เพิ่ม buffer เล็กน้อย
				-- ตรวจสอบว่า Attribute ยังอยู่ และเวลาตรงกันหรือไม่ (เผื่อมีการ Dash ซ้อน)
				local currentEndTime = humanoid:GetAttribute(THIEF_BOOST_ENDTIME_ATTR)
				if currentEndTime and math.abs(currentEndTime - boostEndTime) < 0.1 then
					humanoid:SetAttribute(THIEF_BOOST_ENDTIME_ATTR, nil)
					humanoid:SetAttribute(THIEF_BOOST_SPEED_ATTR, nil)
					humanoid:SetAttribute(ORIGINAL_SPEED_ATTR, nil)
					-- print(string.format("[DashSystem] Player %d: Removed boost attributes.", userId)) -- Debug
				end
			end)
		end
	end

	if player then self.dashEffect:FireClient(player, "Complete") end
	self.activeDashes[userId] = nil
	-- print(string.format("[DashSystem] Player %d: Dash state cleared.", userId)) -- Debug
end

-- Clear cooldown (เหมือนเดิม)
function DashSystem:ClearCooldown(player)
	local playerId = typeof(player) == "Instance" and player.UserId or player; if not playerId then return end
	self.playerCooldowns[playerId] = nil
	local playerInstance = typeof(player) == "Instance" and player or Players:GetPlayerByUserId(playerId)
	if playerInstance then self.dashCooldown:FireClient(playerInstance, 0) end
end

-- Initialize player (ล้าง Attribute ที่อาจค้าง)
function DashSystem:InitializePlayer(player)
	local userId = player.UserId
	if self.activeDashes[userId] then self:CleanupDash(userId) end
	-- Clear attributes on initialize
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:SetAttribute(THIEF_BOOST_ENDTIME_ATTR, nil)
		humanoid:SetAttribute(THIEF_BOOST_SPEED_ATTR, nil)
		humanoid:SetAttribute(ORIGINAL_SPEED_ATTR, nil)
	end
	self.playerCooldowns[userId] = nil
	self.activeDashes[userId] = nil
end

-- Register system (ล้าง Attribute ตอนออก)
function DashSystem:Register()
	local gameManager = _G.GameManager
	if gameManager then gameManager.dashSystem = self; print("[DashSystem] Registered with GameManager") else warn("[DashSystem] GameManager not found") end
	Players.PlayerAdded:Connect(function(player) self:InitializePlayer(player) end)
	for _, player in pairs(Players:GetPlayers()) do task.spawn(self.InitializePlayer, self, player) end
	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		-- Clear attributes on removing
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:SetAttribute(THIEF_BOOST_ENDTIME_ATTR, nil)
			humanoid:SetAttribute(THIEF_BOOST_SPEED_ATTR, nil)
			humanoid:SetAttribute(ORIGINAL_SPEED_ATTR, nil)
		end
		self.playerCooldowns[userId] = nil
		self.activeDashes[userId] = nil
	end)
	print("[DashSystem] Registration complete")
end

-- ไม่ต้องมี Shutdown แล้ว
-- function DashSystem:Shutdown() end

return DashSystem
