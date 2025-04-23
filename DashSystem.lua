-- DashSystem.lua
-- Module for managing dash abilities in combat
-- เพิ่มระบบ Dash/Dodge สำหรับ Combat Mode
-- Version: 1.0.0

local DashSystem = {}
DashSystem.__index = DashSystem

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Constants for Different Classes
local CLASS_DASH_SETTINGS = {
	Warrior = {
		Distance = 12,          -- ระยะการ Dash (หน่วยเป็น studs)
		Duration = 0.35,        -- ระยะเวลาการ Dash (วินาที)
		Cooldown = 2.0,         -- เวลาคูลดาวน์ (วินาที)
		Effect = "Roll",        -- รูปแบบการ Dash (กลิ้ง)
		EffectColor = Color3.fromRGB(255, 130, 0)  -- สีส้มเข้ม
	},
	Mage = {
		Distance = 15,          -- ระยะการ Dash ไกลกว่า Warrior
		Duration = 0.4,         -- ระยะเวลาการ Dash นานกว่า
		Cooldown = 3.5,         -- คูลดาวน์นานกว่า
		Effect = "Roll",        -- รูปแบบการ Dash (กลิ้ง)
		EffectColor = Color3.fromRGB(70, 130, 255)  -- สีฟ้า
	},
	Thief = {
		Distance = 25,          -- ระยะการ Dash ไกลที่สุด
		Duration = 1.25,        -- ระยะเวลาการ Dash นานที่สุด
		Cooldown = 3,         -- คูลดาวน์ปานกลาง
		Effect = "Vanish",      -- รูปแบบการ Dash (หายตัว)
		EffectColor = Color3.fromRGB(110, 255, 110) -- สีเขียว
	}
}

-- Default dash settings ถ้าไม่พบคลาสที่ตรงกัน
local DEFAULT_DASH_SETTINGS = {
	Distance = 14,
	Duration = 0.4,
	Cooldown = 2.5,
	Effect = "Roll",
	EffectColor = Color3.fromRGB(200, 200, 200)
}

-- Set up Animation IDs
local DASH_ANIMATIONS = {
	Front = "rbxassetid://14103831900",  -- Animation ID สำหรับ Dash ไปด้านหน้า
	Back = "rbxassetid://14103833544",   -- Animation ID สำหรับ Dash ถอยหลัง
	Left = "rbxassetid://14103834807",   -- Animation ID สำหรับ Dash ไปทางซ้าย
	Right = "rbxassetid://14103836416"   -- Animation ID สำหรับ Dash ไปทางขวา
}

-- Constructor
function DashSystem.new(combatService)
	local self = setmetatable({}, DashSystem)

	-- Reference to other systems
	self.combatService = combatService

	-- Active dash data
	self.activeDashes = {}      -- ข้อมูลของการ Dash ที่กำลังทำงานอยู่
	self.playerCooldowns = {}   -- เก็บข้อมูลคูลดาวน์ของแต่ละผู้เล่น
	self.dashAnimations = {}    -- เก็บ Animation objects

	-- Remote Events
	self:SetupRemoteEvents()

	return self
end

-- Set up remote events for dash system
function DashSystem:SetupRemoteEvents()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local combatRemotes = remotes:FindFirstChild("CombatRemotes")

	if not combatRemotes then
		combatRemotes = Instance.new("Folder")
		combatRemotes.Name = "CombatRemotes"
		combatRemotes.Parent = remotes
		print("[DashSystem] Created CombatRemotes folder")
	end

	-- Create dash remote events if they don't exist
	self.dashRequest = combatRemotes:FindFirstChild("DashRequest")
	if not self.dashRequest then
		self.dashRequest = Instance.new("RemoteEvent")
		self.dashRequest.Name = "DashRequest"
		self.dashRequest.Parent = combatRemotes
		print("[DashSystem] Created DashRequest RemoteEvent")
	end

	self.dashEffect = combatRemotes:FindFirstChild("DashEffect")
	if not self.dashEffect then
		self.dashEffect = Instance.new("RemoteEvent")
		self.dashEffect.Name = "DashEffect"
		self.dashEffect.Parent = combatRemotes
		print("[DashSystem] Created DashEffect RemoteEvent")
	end

	self.dashCooldown = combatRemotes:FindFirstChild("DashCooldown")
	if not self.dashCooldown then
		self.dashCooldown = Instance.new("RemoteEvent")
		self.dashCooldown.Name = "DashCooldown"
		self.dashCooldown.Parent = combatRemotes
		print("[DashSystem] Created DashCooldown RemoteEvent")
	end

	-- Connect server-side event handler
	self.dashRequest.OnServerEvent:Connect(function(player, direction)
		self:ProcessDashRequest(player, direction)
	end)
end

-- Process dash request from client
function DashSystem:ProcessDashRequest(player, direction)
	local playerId = player.UserId

	-- 1. Check if player is in combat mode
	if not self.combatService or not self.combatService:IsCombatActive() then
		print("[DashSystem] Dash request rejected - Player not in combat: " .. player.Name)
		return false
	end

	-- 2. Check if player is on cooldown
	if self.playerCooldowns[playerId] then
		local remainingCooldown = self.playerCooldowns[playerId] - tick()
		if remainingCooldown > 0 then
			print("[DashSystem] Dash on cooldown for " .. player.Name .. " - " .. string.format("%.1f", remainingCooldown) .. "s remaining")
			-- Notify client of remaining cooldown (optional)
			self.dashCooldown:FireClient(player, remainingCooldown)
			return false
		end
	end

	-- 3. Get player class and dash settings
	local playerClass = self:GetPlayerClass(player)
	local dashSettings = self:GetDashSettingsForClass(playerClass)

	-- 4. Perform dash
	local success = self:PerformDash(player, direction, dashSettings)

	-- 5. Set cooldown if successful
	if success then
		self.playerCooldowns[playerId] = tick() + dashSettings.Cooldown
		-- Notify client of cooldown
		self.dashCooldown:FireClient(player, dashSettings.Cooldown)
	end

	return success
end

-- Get player's class
function DashSystem:GetPlayerClass(player)
	-- Try to get from GameManager
	local gameManager = _G.GameManager
	if gameManager and gameManager.classSystem then
		local playerClass = gameManager.classSystem:GetPlayerClass(player)
		if playerClass then
			return playerClass
		end
	end

	-- Alternative: Try to get from PlayerManager
	if gameManager and gameManager.playerManager then
		local playerData = gameManager.playerManager:GetPlayerData(player)
		if playerData and playerData.class then
			return playerData.class
		end
	end

	print("[DashSystem] Warning: Could not determine class for player " .. player.Name)
	return "Unknown"
end

-- Get dash settings for a specific class
function DashSystem:GetDashSettingsForClass(className)
	local settings = CLASS_DASH_SETTINGS[className]
	if not settings then
		print("[DashSystem] Warning: No dash settings for class " .. className .. ". Using defaults.")
		return DEFAULT_DASH_SETTINGS
	end
	return settings
end

-- Perform dash for player
function DashSystem:PerformDash(player, direction, dashSettings)
	local character = player.Character
	if not character then
		print("[DashSystem] No character found for " .. player.Name)
		return false
	end

	local humanoid = character:FindFirstChild("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp then
		print("[DashSystem] Humanoid or HumanoidRootPart not found for " .. player.Name)
		return false
	end

	-- Check if player is already dashing
	if self.activeDashes[player.UserId] then
		print("[DashSystem] Player " .. player.Name .. " is already dashing")
		return false
	end

	-- Check if player is jumping (anti-exploit)
	if humanoid.FloorMaterial == Enum.Material.Air or humanoid:GetState() == Enum.HumanoidStateType.Jumping then
		print("[DashSystem] Dash rejected - Player " .. player.Name .. " is in air")
		return false
	end

	-- Normalize direction
	local dirVector = self:GetDirectionVector(direction, character)

	-- Set up dash data
	local dashData = {
		player = player,
		startPosition = hrp.Position,
		direction = dirVector,
		settings = dashSettings,
		startTime = tick(),
		completed = false
	}

	-- Store in active dashes
	self.activeDashes[player.UserId] = dashData

	-- Determine animation based on direction
	local animationId = self:DetermineAnimationId(direction)

	-- Play animation on the client
	self.dashEffect:FireClient(player, direction, dashData.settings.Effect, dashData.settings.EffectColor, animationId)

	-- For thief's vanish effect, notify others as well
	if dashData.settings.Effect == "Vanish" then
		for _, otherPlayer in pairs(Players:GetPlayers()) do
			if otherPlayer ~= player then
				self.dashEffect:FireClient(otherPlayer, direction, dashData.settings.Effect, dashData.settings.EffectColor, animationId, player)
			end
		end
	end

	-- If server-sided dash movement is needed:
	self:ApplyDashImpulse(dashData)

	return true
end

-- Get direction vector based on input direction and character orientation
function DashSystem:GetDirectionVector(direction, character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return Vector3.new(0, 0, 1) end

	local lookVector = hrp.CFrame.LookVector
	local rightVector = hrp.CFrame.RightVector

	if direction == "Front" then
		return lookVector.Unit
	elseif direction == "Back" then
		return -lookVector.Unit
	elseif direction == "Left" then
		return -rightVector.Unit
	elseif direction == "Right" then
		return rightVector.Unit
	end

	-- Default to forward
	return lookVector.Unit
end

-- Determine animation ID based on dash direction
function DashSystem:DetermineAnimationId(direction)
	return DASH_ANIMATIONS[direction] or DASH_ANIMATIONS.Front
end

-- Apply dash impulse/force to character
function DashSystem:ApplyDashImpulse(dashData)
	local player = dashData.player
	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChild("Humanoid")
	if not hrp or not humanoid then return end

	-- Disable normal controls during dash
	humanoid.WalkSpeed = 0

	-- Start a physics-based dash using BodyVelocity
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(50000, 0, 50000)  -- Strong force on X and Z, none on Y
	bodyVelocity.P = 1250  -- Higher P value makes it more responsive
	bodyVelocity.Velocity = dashData.direction * dashData.settings.Distance * (1 / dashData.settings.Duration)
	bodyVelocity.Parent = hrp

	-- Store for cleanup
	dashData.bodyVelocity = bodyVelocity

	-- Clean up after dash duration
	local endTime = dashData.startTime + dashData.settings.Duration

	task.delay(dashData.settings.Duration, function()
		self:CleanupDash(player.UserId)
	end)

	-- Special handling for Thief's vanish effect
	if dashData.settings.Effect == "Vanish" then
		-- Make character transparent during dash for Thief
		for _, part in pairs(character:GetDescendants()) do
			if part:IsA("BasePart") or part:IsA("Decal") then
				dashData.originalTransparency = dashData.originalTransparency or {}
				dashData.originalTransparency[part] = part.Transparency
				part.Transparency = 1
			end
		end
	end
end

-- Clean up after dash is completed
function DashSystem:CleanupDash(userId)
	local dashData = self.activeDashes[userId]
	if not dashData then return end

	local player = dashData.player
	local character = player and player.Character

	if character then
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid then
			-- Restore normal controls
			humanoid.WalkSpeed = 16
		end

		-- Clean up body velocity
		if dashData.bodyVelocity and dashData.bodyVelocity.Parent then
			dashData.bodyVelocity:Destroy()
		end

		-- For Thief: restore transparency
		if dashData.settings.Effect == "Vanish" and dashData.originalTransparency then
			for part, origTransparency in pairs(dashData.originalTransparency) do
				if part:IsA("BasePart") or part:IsA("Decal") then
					part.Transparency = origTransparency
				end
			end
		end
	end

	-- Notify client that dash is complete
	if player then
		self.dashEffect:FireClient(player, "Complete")
	end

	-- Remove from active dashes
	self.activeDashes[userId] = nil
end

-- Clear dash cooldown for player (useful when testing)
function DashSystem:ClearCooldown(player)
	local playerId = typeof(player) == "Instance" and player:IsA("Player") and player.UserId or player
	if not playerId then return end

	self.playerCooldowns[playerId] = nil
	print("[DashSystem] Cleared dash cooldown for player " .. tostring(playerId))

	-- Notify client
	local playerInstance = typeof(player) == "Instance" and player or Players:GetPlayerByUserId(playerId)
	if playerInstance then
		self.dashCooldown:FireClient(playerInstance, 0)
	end
end

-- Initialize for a new player (pre-load animations)
function DashSystem:InitializePlayer(player)
	-- Nothing needed for server-side initialization currently
	print("[DashSystem] Initialized dash system for player " .. player.Name)
end

-- Register this system with CombatService and GameManager
function DashSystem:Register()
	local gameManager = _G.GameManager
	if gameManager then
		gameManager.dashSystem = self
		print("[DashSystem] Registered dash system with GameManager")
	else
		warn("[DashSystem] GameManager not found, dash system not registered globally")
	end

	-- Connect to PlayerAdded event
	Players.PlayerAdded:Connect(function(player)
		self:InitializePlayer(player)
	end)

	-- Initialize existing players
	for _, player in pairs(Players:GetPlayers()) do
		self:InitializePlayer(player)
	end

	print("[DashSystem] Dash system registration complete")
end

return DashSystem
