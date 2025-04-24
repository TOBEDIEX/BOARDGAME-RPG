-- DashController.lua
-- Client-side controller for dash abilities in combat
-- Version: 1.2.3 (Replaced Roll trail with DashVFX effect)

local DashController = {}
DashController.__index = DashController

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris") -- Added Debris service

-- Constants
local DASH_KEY = Enum.KeyCode.Q
local SPECIAL_DASH_KEY = Enum.KeyCode.R  -- Key for Special Dash
local DEFAULT_WALKSPEED = 16
local THIEF_BOOST_ENDTIME_ATTR = "ThiefBoostEndTime"
local THIEF_BOOST_SPEED_ATTR = "ThiefBoostSpeed"
local ORIGINAL_SPEED_ATTR = "OriginalWalkSpeed"
local ROLL_VFX_LIFETIME = 0.5 -- Duration for the new Roll VFX

-- Variables
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")
local regularDashCooldown = 0
local specialDashCooldown = 0
local isDashing = false
local combatActive = false
local dashAnimations = {}
-- local activeTrails = {} -- No longer needed for Roll
local heartbeatConnection = nil
local playerClass = "Unknown"

-- Get remote events
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local combatRemotes = remotes:WaitForChild("CombatRemotes")
local dashRequest = combatRemotes:WaitForChild("DashRequest")
local specialDashRequest = combatRemotes:WaitForChild("SpecialDashRequest")
local dashEffect = combatRemotes:WaitForChild("DashEffect")
local dashCooldownEvent = combatRemotes:WaitForChild("DashCooldown")
local setCombatStateEvent = combatRemotes:WaitForChild("SetCombatState")

-- Initialize
function DashController:Initialize()
	self:UpdateCharacterReferences(character)
	self:PreloadDashAnimations()
	self:ConnectRemoteEvents()
	self:StartSpeedBoostManager()
	self:FetchPlayerClass()

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		self:HandleInput(input, gameProcessed)
	end)

	player.CharacterAdded:Connect(function(newCharacter)
		self:StopSpeedBoostManager()
		self:UpdateCharacterReferences(newCharacter)
		self:PreloadDashAnimations()
		-- self:CleanupAllTrails() -- No longer needed for Roll
		self:StartSpeedBoostManager()
		self:FetchPlayerClass()
		if humanoid and humanoid.Parent then humanoid.AutoRotate = true end
	end)

	player.CharacterRemoving:Connect(function()
		self:StopSpeedBoostManager()
		-- self:CleanupAllTrails() -- No longer needed for Roll
	end)

	print("[DashController] Initialized")
end

-- Fetch player's class
function DashController:FetchPlayerClass()
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
		print("[DashController] Player class set to:", playerClass)
	else
		task.wait(0.1)
		if humanoid and humanoid:GetAttribute("Class") then
			playerClass = humanoid:GetAttribute("Class")
			print("[DashController] Player class fetched from attribute:", playerClass)
		else
			local uiRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UIRemotes")
			local classAssigned = uiRemotes:FindFirstChild("ClassAssigned")
			if classAssigned then
				local conn
				conn = classAssigned.OnClientEvent:Connect(function(className, classInfo)
					playerClass = className
					print("[DashController] Player class updated via event:", playerClass)
					if conn then conn:Disconnect() end
				end)
			end
			print("[DashController] Unable to fetch player class immediately, waiting for event or attribute.")
		end
	end
end


-- Start Client-Side Speed Boost Manager
function DashController:StartSpeedBoostManager()
	if heartbeatConnection then return end
	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		if not humanoid or not humanoid.Parent or isDashing then return end
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
			end
		else
			local originalSpeed = humanoid:GetAttribute(ORIGINAL_SPEED_ATTR) or DEFAULT_WALKSPEED
			if math.abs(humanoid.WalkSpeed - originalSpeed) > 0.1 then humanoid.WalkSpeed = originalSpeed end
			if not humanoid.AutoRotate then humanoid.AutoRotate = true end
		end
	end)
end

-- Stop Client-Side Speed Boost Manager
function DashController:StopSpeedBoostManager()
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
function DashController:UpdateCharacterReferences(newCharacter)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid")
	animator = humanoid:WaitForChild("Animator")
	isDashing = false
	if humanoid and humanoid.Parent then humanoid.AutoRotate = true end
end

-- Preload dash animations
function DashController:PreloadDashAnimations()
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

-- Connect remote events
function DashController:ConnectRemoteEvents()
	dashEffect.OnClientEvent:Connect(function(direction, effectType, effectColor, animationId, playerSource, dashType, dashDuration)
		if not character or not humanoid or not animator then return end

		if direction == "Complete" then
			isDashing = false
			-- self:CleanupAllTrails() -- No longer needed for Roll
			if humanoid and humanoid.Parent then humanoid.AutoRotate = true end
			return
		end

		if playerSource and playerSource ~= player then
			if effectType == "Vanish" then
				self:PlayOtherPlayerVanishEffect(playerSource, direction, effectColor, dashDuration)
			end
			return
		end

		isDashing = true
		self:PlayDashEffect(direction, effectType, effectColor, animationId, dashDuration)
	end)

	setCombatStateEvent.OnClientEvent:Connect(function(isActive, duration)
		combatActive = isActive
		if not isActive then
			self:UpdateRegularCooldown(0); self:UpdateSpecialCooldown(0)
			if humanoid and humanoid.Parent then humanoid.AutoRotate = true end
			print("[DashController] Combat ended, ensuring AutoRotate is enabled.")
		else
			print("[DashController] Combat started.")
			if humanoid and humanoid.Parent then humanoid.AutoRotate = true end
		end
	end)
end

-- Handle input
function DashController:HandleInput(input, gameProcessed)
	if gameProcessed or not combatActive or isDashing then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	if input.KeyCode == DASH_KEY then
		if playerClass == "Thief" and specialDashCooldown > 0 then return end
		self:TryRegularDash()
	elseif input.KeyCode == SPECIAL_DASH_KEY and playerClass == "Thief" then
		if regularDashCooldown > 0 then return end
		self:TrySpecialDash()
	end
end

-- Try regular dash / special dash logic (unchanged)
function DashController:TryRegularDash()
	if isDashing or regularDashCooldown > 0 then return end
	if not character or not humanoid or not humanoid.RootPart then return end
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Dead then return end
	local dir = self:GetDashDirection()
	dashRequest:FireServer(dir)
end

function DashController:TrySpecialDash()
	if isDashing or specialDashCooldown > 0 then return end
	if playerClass ~= "Thief" then return end
	if not character or not humanoid or not humanoid.RootPart then return end
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Dead then return end
	local dir = self:GetDashDirection()
	specialDashRequest:FireServer(dir)
end

function DashController:GetDashDirection()
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

-- Cooldown update logic (unchanged)
function DashController:UpdateRegularCooldown(newCooldown)
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

function DashController:UpdateSpecialCooldown(newCooldown)
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
function DashController:PlayDashEffect(direction, effectType, effectColor, animationId, dashDuration)
	if animationId and effectType ~= "Vanish" then
		local t = dashAnimations[direction]
		if t then t:Stop(0); t:Play(0.1) else warn("Anim not found:", direction) end
	end

	-- *** MODIFICATION START: Handle Roll effect ***
	if effectType == "Roll" then
		self:PlayNewRollEffect(effectColor) -- Call the new function
		-- *** MODIFICATION END ***
	elseif effectType == "Vanish" then
		self:PlayVanishEffect(effectColor, dashDuration)
	end
end

-- *** NEW FUNCTION: PlayNewRollEffect ***
function DashController:PlayNewRollEffect(effectColor)
	if not character or not humanoid then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Find the VFX folder and the specific DashVFX assets
	local vfxFolder = ReplicatedStorage:FindFirstChild("VFX")
	local dashVfxSource = vfxFolder and vfxFolder:FindFirstChild("DashVFX")
	if not dashVfxSource then
		warn("[DashController] Could not find VFX/DashVFX in ReplicatedStorage")
		return
	end

	local line1Source = dashVfxSource:FindFirstChild("Line1")
	local line2Source = dashVfxSource:FindFirstChild("Line2")

	if not line1Source or not line2Source then
		warn("[DashController] Could not find Line1 or Line2 inside DashVFX")
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

	print("[DashController] Played new Roll VFX") -- Debug
end

-- Play vanish effect (Uses dashDuration passed from server)
function DashController:PlayVanishEffect(effectColor, dashDuration)
	if not character or not humanoid then return end
	local effectTime = (typeof(dashDuration) == "number" and dashDuration > 0) and dashDuration or 0.25
	print("[DashController] Playing Vanish effect for duration:", effectTime)

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
function DashController:PlayOtherPlayerVanishEffect(playerSource, direction, effectColor, dashDuration)
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

-- Create UI Elements for cooldown indicators (unchanged)
function DashController:CreateCooldownUI()
	local regularCooldownLabel, specialCooldownLabel; local regularFrame, specialFrame
	local function createOrUpdateCooldownDisplay(dashType, cooldownTime)
		local gui = player:FindFirstChild("PlayerGui"); if not gui then return end
		local screenGui = gui:FindFirstChild("DashCooldownGui")
		if not screenGui then screenGui = Instance.new("ScreenGui"); screenGui.Name = "DashCooldownGui"; screenGui.ResetOnSpawn = false; screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; screenGui.Parent = gui end
		if dashType == "Default" then
			if not regularFrame or not regularFrame.Parent then
				regularFrame = Instance.new("Frame"); regularFrame.Name = "RegularDashFrame"; regularFrame.Size = UDim2.new(0, 50, 0, 50); regularFrame.Position = UDim2.new(0.02, 0, 0.75, 0); regularFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40); regularFrame.BackgroundTransparency = 0.3; regularFrame.BorderSizePixel = 0; regularFrame.Parent = screenGui
				local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = regularFrame; local k = Instance.new("TextLabel"); k.Name = "KeyLabel"; k.Size = UDim2.new(1, 0, 0.5, 0); k.Position = UDim2.new(0, 0, 0, 0); k.BackgroundTransparency = 1; k.Text = "Q"; k.TextColor3 = Color3.fromRGB(255, 255, 255); k.TextSize = 18; k.Font = Enum.Font.GothamBold; k.Parent = regularFrame
				regularCooldownLabel = Instance.new("TextLabel"); regularCooldownLabel.Name = "CooldownLabel"; regularCooldownLabel.Size = UDim2.new(1, 0, 0.5, 0); regularCooldownLabel.Position = UDim2.new(0, 0, 0.5, 0); regularCooldownLabel.BackgroundTransparency = 1; regularCooldownLabel.Text = ""; regularCooldownLabel.TextColor3 = Color3.fromRGB(255, 80, 80); regularCooldownLabel.TextSize = 14; regularCooldownLabel.Font = Enum.Font.Gotham; regularCooldownLabel.Parent = regularFrame
			end
			regularFrame.Visible = true; regularCooldownLabel.Text = string.format("%.1fs", cooldownTime); regularCooldownLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		elseif dashType == "Special" then
			if not specialFrame or not specialFrame.Parent then
				specialFrame = Instance.new("Frame"); specialFrame.Name = "SpecialDashFrame"; specialFrame.Size = UDim2.new(0, 50, 0, 50); specialFrame.Position = UDim2.new(0.02, 0, 0.85, 0); specialFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40); specialFrame.BackgroundTransparency = 0.3; specialFrame.BorderSizePixel = 0; specialFrame.Parent = screenGui
				local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = specialFrame; local k = Instance.new("TextLabel"); k.Name = "KeyLabel"; k.Size = UDim2.new(1, 0, 0.5, 0); k.Position = UDim2.new(0, 0, 0, 0); k.BackgroundTransparency = 1; k.Text = "R"; k.TextColor3 = Color3.fromRGB(255, 255, 255); k.TextSize = 18; k.Font = Enum.Font.GothamBold; k.Parent = specialFrame
				specialCooldownLabel = Instance.new("TextLabel"); specialCooldownLabel.Name = "CooldownLabel"; specialCooldownLabel.Size = UDim2.new(1, 0, 0.5, 0); specialCooldownLabel.Position = UDim2.new(0, 0, 0.5, 0); specialCooldownLabel.BackgroundTransparency = 1; specialCooldownLabel.Text = ""; specialCooldownLabel.TextColor3 = Color3.fromRGB(255, 80, 80); specialCooldownLabel.TextSize = 14; specialCooldownLabel.Font = Enum.Font.Gotham; specialCooldownLabel.Parent = specialFrame
			end
			specialFrame.Visible = true; specialCooldownLabel.Text = string.format("%.1fs", cooldownTime); specialCooldownLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		end
	end
	dashCooldownEvent.OnClientEvent:Connect(function(cooldownTime, dashType)
		if dashType == "Default" then self:UpdateRegularCooldown(cooldownTime); if cooldownTime > 0 then createOrUpdateCooldownDisplay("Default", cooldownTime) elseif regularFrame then regularFrame.Visible = false end
		elseif dashType == "Special" then self:UpdateSpecialCooldown(cooldownTime); if cooldownTime > 0 then createOrUpdateCooldownDisplay("Special", cooldownTime) elseif specialFrame then specialFrame.Visible = false end end
	end)
	RunService.RenderStepped:Connect(function()
		if regularCooldownLabel and regularFrame and regularFrame.Visible then if regularDashCooldown > 0 then regularCooldownLabel.Text = string.format("%.1fs", regularDashCooldown) else regularFrame.Visible = false end end
		if playerClass == "Thief" then if specialCooldownLabel and specialFrame and specialFrame.Visible then if specialDashCooldown > 0 then specialCooldownLabel.Text = string.format("%.1fs", specialDashCooldown) else specialFrame.Visible = false end elseif specialFrame and specialFrame.Parent then specialFrame.Visible = false end
		elseif specialFrame and specialFrame.Parent then specialFrame.Visible = false end
	end)
end

-- Initialize
local controller = {}
DashController:Initialize()
DashController:CreateCooldownUI()

return DashController
