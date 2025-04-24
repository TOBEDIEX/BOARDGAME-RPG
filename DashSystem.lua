-- DashSystem.lua
-- Module for managing dash abilities in combat
-- Version: 1.2.3 (Vanish effect duration now uses SpeedBoostDuration for Thief)

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
local THIEF_BOOST_ENDTIME_ATTR = "ThiefBoostEndTime" -- Attribute name
local THIEF_BOOST_SPEED_ATTR = "ThiefBoostSpeed" -- Stores boosted speed
local ORIGINAL_SPEED_ATTR = "OriginalWalkSpeed" -- Stores original speed

-- Class Settings
local CLASS_DASH_SETTINGS = {
	Warrior = {
		Default = { Distance = 12, Duration = 0.3, Cooldown = 2.0, Effect = "Roll", EffectColor = Color3.fromRGB(255, 130, 0), AnimationRequired = true, SpeedBoost = 0, SpeedBoostDuration = 0 }
	},
	Mage = {
		Default = { Distance = 15, Duration = 0.3, Cooldown = 3.5, Effect = "Roll", EffectColor = Color3.fromRGB(70, 130, 255), AnimationRequired = true, SpeedBoost = 0, SpeedBoostDuration = 0 }
	},
	Thief = {
		Default = { Distance = 15, Duration = 0.3, Cooldown = 2.0, Effect = "Roll", EffectColor = Color3.fromRGB(110, 255, 110), AnimationRequired = true, SpeedBoost = 0, SpeedBoostDuration = 0 },
		Special = { Distance = 18, Duration = 0.25, Cooldown = 5.0, Effect = "Vanish", EffectColor = Color3.fromRGB(110, 255, 110), AnimationRequired = false, SpeedBoost = 34, SpeedBoostDuration = 1.25 } -- Vanish effect will use SpeedBoostDuration
	}
}

local DEFAULT_DASH_SETTINGS = { Distance = 14, Duration = 0.35, Cooldown = 2.5, Effect = "Roll", EffectColor = Color3.fromRGB(200, 200, 200), AnimationRequired = true, SpeedBoost = 0, SpeedBoostDuration = 0 }
local DASH_ANIMATIONS = { Front = "rbxassetid://14103831900", Back = "rbxassetid://14103833544", Left = "rbxassetid://14103834807", Right = "rbxassetid://14103836416" }

-- Constructor
function DashSystem.new(combatService)
	local self = setmetatable({}, DashSystem)
	self.combatService = combatService
	self.activeDashes = {}
	self.playerCooldowns = {} -- Structure: {userId = {Default = time, Special = time}}
	self:SetupCollisionGroup()
	self:SetupRemoteEvents()
	return self
end

-- Setup Collision Group
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

-- Set up remote events
function DashSystem:SetupRemoteEvents()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local combatRemotes = remotes:FindFirstChild("CombatRemotes") or Instance.new("Folder", remotes)
	combatRemotes.Name = "CombatRemotes"

	self.dashRequest = combatRemotes:FindFirstChild("DashRequest") or Instance.new("RemoteEvent", combatRemotes)
	self.dashRequest.Name = "DashRequest"
	self.specialDashRequest = combatRemotes:FindFirstChild("SpecialDashRequest") or Instance.new("RemoteEvent", combatRemotes)
	self.specialDashRequest.Name = "SpecialDashRequest"
	self.dashEffect = combatRemotes:FindFirstChild("DashEffect") or Instance.new("RemoteEvent", combatRemotes)
	self.dashEffect.Name = "DashEffect"
	self.dashCooldown = combatRemotes:FindFirstChild("DashCooldown") or Instance.new("RemoteEvent", combatRemotes)
	self.dashCooldown.Name = "DashCooldown"

	self.dashRequest.OnServerEvent:Connect(function(player, direction)
		self:ProcessDashRequest(player, direction, "Default")
	end)
	self.specialDashRequest.OnServerEvent:Connect(function(player, direction)
		self:ProcessDashRequest(player, direction, "Special")
	end)
end

-- Process dash request
function DashSystem:ProcessDashRequest(player, direction, dashType)
	local playerId = player.UserId

	if not self.combatService or not self.combatService:IsCombatActive() then return false end

	local playerClass = self:GetPlayerClass(player)
	if dashType == "Special" and playerClass ~= "Thief" then return false end

	if not self.playerCooldowns[playerId] then
		self.playerCooldowns[playerId] = { Default = 0, Special = 0 }
	end

	local currentTime = tick()
	local cooldownData = self.playerCooldowns[playerId]

	if cooldownData[dashType] and cooldownData[dashType] > currentTime then
		local remainingCooldown = cooldownData[dashType] - currentTime
		self.dashCooldown:FireClient(player, remainingCooldown, dashType)
		return false
	end

	local otherDashType = (dashType == "Default") and "Special" or "Default"
	if playerClass == "Thief" and cooldownData[otherDashType] and cooldownData[otherDashType] > currentTime then
		local remainingOtherCooldown = cooldownData[otherDashType] - currentTime
		self.dashCooldown:FireClient(player, remainingOtherCooldown, dashType)
		return false
	end

	if self.activeDashes[playerId] then return false end

	local dashSettings
	if playerClass == "Thief" and dashType == "Special" then
		dashSettings = CLASS_DASH_SETTINGS.Thief.Special
	elseif CLASS_DASH_SETTINGS[playerClass] and CLASS_DASH_SETTINGS[playerClass].Default then
		dashSettings = CLASS_DASH_SETTINGS[playerClass].Default
	else
		dashSettings = DEFAULT_DASH_SETTINGS
	end

	local success = self:PerformDash(player, direction, dashSettings, dashType)
	if success then
		self.playerCooldowns[playerId][dashType] = currentTime + dashSettings.Cooldown
		self.dashCooldown:FireClient(player, dashSettings.Cooldown, dashType)
	end
	return success
end

-- Get player's class
function DashSystem:GetPlayerClass(player)
	local gameManager = _G.GameManager
	if gameManager then
		if gameManager.classSystem and gameManager.classSystem.GetPlayerClass then
			local c = gameManager.classSystem:GetPlayerClass(player)
			if c then return c end
		end
		if gameManager.playerManager and gameManager.playerManager.GetPlayerData then
			local d = gameManager.playerManager:GetPlayerData(player)
			if d and d.class then return d.class end
		end
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum:GetAttribute("Class") then
		return hum:GetAttribute("Class")
	end
	return "Unknown"
end


-- Perform dash
function DashSystem:PerformDash(player, direction, dashSettings, dashType)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not hrp or humanoid:GetState() == Enum.HumanoidStateType.Dead then return false end
	if self.activeDashes[player.UserId] then return false end
	if humanoid:GetState() == Enum.HumanoidStateType.Jumping or humanoid:GetState() == Enum.HumanoidStateType.Freefall then return false end

	local dashData = {
		player = player,
		settings = dashSettings,
		startTime = tick(),
		completed = false,
		originalCollisionGroup = {},
		directionString = direction,
		dashType = dashType
	}
	self.activeDashes[player.UserId] = dashData

	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			dashData.originalCollisionGroup[part] = part.CollisionGroup
			pcall(function() part.CollisionGroup = DASH_COLLISION_GROUP end)
		end
	end

	local animationId = dashSettings.AnimationRequired and self:DetermineAnimationId(direction) or nil

	-- *** MODIFICATION START: Determine effect duration based on effect type ***
	local effectDuration
	if dashSettings.Effect == "Vanish" and dashSettings.SpeedBoostDuration and dashSettings.SpeedBoostDuration > 0 then
		-- For Vanish (Thief Special), use SpeedBoostDuration for the visual effect duration
		effectDuration = dashSettings.SpeedBoostDuration
		print("[DashSystem] Using SpeedBoostDuration for Vanish effect:", effectDuration) -- Debug
	else
		-- For other effects (like Roll), use the movement duration
		effectDuration = dashSettings.Duration
	end
	-- *** MODIFICATION END ***

	-- Fire effect to the dashing player
	self.dashEffect:FireClient(player, direction, dashData.settings.Effect, dashData.settings.EffectColor, animationId, nil, dashType, effectDuration)

	-- Fire Vanish effect to other players (using the same determined duration)
	if dashData.settings.Effect == "Vanish" then
		for _, otherPlayer in pairs(Players:GetPlayers()) do
			if otherPlayer ~= player then
				self.dashEffect:FireClient(otherPlayer, direction, dashData.settings.Effect, dashData.settings.EffectColor, nil, player, dashType, effectDuration)
			end
		end
	end

	-- Apply the dash movement (uses dashSettings.Duration for movement time)
	self:ApplyDashVelocity(dashData)
	return true
end

-- Get direction vector
function DashSystem:GetDirectionVector(directionString, character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return Vector3.zAxis end
	local lookVector = hrp.CFrame.LookVector
	local rightVector = hrp.CFrame.RightVector
	if directionString == "Back" then return -lookVector.Unit
	elseif directionString == "Left" then return -rightVector.Unit
	elseif directionString == "Right" then return rightVector.Unit
	else return lookVector.Unit end
end

-- Determine animation ID
function DashSystem:DetermineAnimationId(direction)
	return DASH_ANIMATIONS[direction] or DASH_ANIMATIONS.Front
end

-- Apply dash velocity
function DashSystem:ApplyDashVelocity(dashData)
	local player = dashData.player
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not hrp or not humanoid then
		self:CleanupDash(player.UserId)
		return
	end

	local attachment = hrp:FindFirstChild("DashAttachment") or Instance.new("Attachment", hrp)
	attachment.Name = "DashAttachment"

	local oldVelocity = hrp:FindFirstChild("DashLinearVelocity")
	if oldVelocity then oldVelocity:Destroy() end

	local moveDirectionVector = self:GetDirectionVector(dashData.directionString, character)
	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "DashLinearVelocity"
	linearVelocity.Attachment0 = attachment
	linearVelocity.MaxForce = 80000
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	linearVelocity.LineDirection = moveDirectionVector
	-- Movement velocity is still based on movement Duration
	linearVelocity.LineVelocity = dashData.settings.Distance / dashData.settings.Duration
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.Parent = hrp
	dashData.linearVelocity = linearVelocity

	humanoid.AutoRotate = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)

	-- Delay cleanup based on movement Duration
	task.delay(dashData.settings.Duration, function()
		if self.activeDashes[player.UserId] == dashData then
			self:CleanupDash(player.UserId)
		end
	end)
end

-- Clean up after dash
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

	if dashData.linearVelocity and dashData.linearVelocity.Parent then
		dashData.linearVelocity:Destroy()
	end

	if character and dashData.originalCollisionGroup then
		for part, groupName in pairs(dashData.originalCollisionGroup) do
			if part and part.Parent then
				pcall(function() part.CollisionGroup = groupName or DEFAULT_COLLISION_GROUP end)
			end
		end
	end

	if humanoid and humanoid.Parent then
		humanoid.AutoRotate = true
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)

		-- Apply Speed Boost via Attributes
		-- Speed boost logic remains the same, timed by SpeedBoostDuration
		if dashData.settings.SpeedBoost > 0 and dashData.settings.SpeedBoostDuration > 0 then
			local originalSpeed = humanoid:GetAttribute(ORIGINAL_SPEED_ATTR) or humanoid.WalkSpeed
			local boostedSpeed = dashData.settings.SpeedBoost
			local boostEndTime = tick() + dashData.settings.SpeedBoostDuration

			humanoid:SetAttribute(ORIGINAL_SPEED_ATTR, originalSpeed)
			humanoid:SetAttribute(THIEF_BOOST_SPEED_ATTR, boostedSpeed)
			humanoid:SetAttribute(THIEF_BOOST_ENDTIME_ATTR, boostEndTime)
			humanoid.WalkSpeed = boostedSpeed

			task.delay(dashData.settings.SpeedBoostDuration + 0.1, function()
				local currentChar = player and player.Character
				local currentHum = currentChar and currentChar:FindFirstChildOfClass("Humanoid")
				if currentHum and currentHum.Parent then
					local currentEndTime = currentHum:GetAttribute(THIEF_BOOST_ENDTIME_ATTR)
					if currentEndTime and math.abs(currentEndTime - boostEndTime) < 0.1 then
						local originalSpeedToRestore = currentHum:GetAttribute(ORIGINAL_SPEED_ATTR) or DEFAULT_WALKSPEED
						currentHum.WalkSpeed = originalSpeedToRestore
						currentHum:SetAttribute(THIEF_BOOST_ENDTIME_ATTR, nil)
						currentHum:SetAttribute(THIEF_BOOST_SPEED_ATTR, nil)
						currentHum:SetAttribute(ORIGINAL_SPEED_ATTR, nil)
					end
				end
			end)
		else
			local originalSpeedToRestore = humanoid:GetAttribute(ORIGINAL_SPEED_ATTR) or DEFAULT_WALKSPEED
			if math.abs(humanoid.WalkSpeed - originalSpeedToRestore) > 0.1 then
				humanoid.WalkSpeed = originalSpeedToRestore
			end
		end
	end

	if player then
		-- Send "Complete" signal (duration doesn't matter here)
		self.dashEffect:FireClient(player, "Complete", nil, nil, nil, nil, dashData.dashType, 0)
	end

	self.activeDashes[userId] = nil
end


-- Clear cooldown
function DashSystem:ClearCooldown(player, dashType)
	local playerId = typeof(player) == "Instance" and player.UserId or player
	if not playerId then return end

	if not self.playerCooldowns[playerId] then
		self.playerCooldowns[playerId] = {Default = 0, Special = 0}
	end

	local playerInstance = typeof(player) == "Instance" and player or Players:GetPlayerByUserId(playerId)

	if dashType then
		if self.playerCooldowns[playerId][dashType] then
			self.playerCooldowns[playerId][dashType] = 0
			if playerInstance then self.dashCooldown:FireClient(playerInstance, 0, dashType) end
		end
	else
		self.playerCooldowns[playerId] = {Default = 0, Special = 0}
		if playerInstance then
			self.dashCooldown:FireClient(playerInstance, 0, "Default")
			self.dashCooldown:FireClient(playerInstance, 0, "Special")
		end
	end
end


-- Initialize player
function DashSystem:InitializePlayer(player)
	local userId = player.UserId
	if self.activeDashes[userId] then
		self:CleanupDash(userId)
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:SetAttribute(THIEF_BOOST_ENDTIME_ATTR, nil)
		humanoid:SetAttribute(THIEF_BOOST_SPEED_ATTR, nil)
		humanoid:SetAttribute(ORIGINAL_SPEED_ATTR, nil)
		humanoid.WalkSpeed = DEFAULT_WALKSPEED
	end
	self.playerCooldowns[userId] = {Default = 0, Special = 0}
	self.activeDashes[userId] = nil
end

-- Register system
function DashSystem:Register()
	local gameManager = _G.GameManager
	if gameManager then
		gameManager.dashSystem = self
		print("[DashSystem] Registered with GameManager")
	else
		warn("[DashSystem] GameManager not found")
	end

	Players.PlayerAdded:Connect(function(player)
		self:InitializePlayer(player)
	end)
	for _, player in pairs(Players:GetPlayers()) do
		task.spawn(self.InitializePlayer, self, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
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

return DashSystem
