-- DashController.lua
-- Client-side controller for dash abilities in combat
-- Version: 1.1.4 (แก้ไข WidthScale, จัดการ Attribute Speed Boost)

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
local isDashing = false
local combatActive = false
local dashAnimations = {}
local activeTrails = {}
local heartbeatConnection = nil -- Connection สำหรับจัดการ Speed Boost

-- Get remote events
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local combatRemotes = remotes:WaitForChild("CombatRemotes")
local dashRequest = combatRemotes:WaitForChild("DashRequest")
local dashEffect = combatRemotes:WaitForChild("DashEffect")
local dashCooldownEvent = combatRemotes:WaitForChild("DashCooldown")
local setCombatStateEvent = combatRemotes:WaitForChild("SetCombatState")

-- Initialize
function DashController:Initialize()
	self:UpdateCharacterReferences(character)
	self:PreloadDashAnimations()
	self:ConnectRemoteEvents()
	self:StartSpeedBoostManager() -- เริ่มตัวจัดการ Speed Boost ฝั่ง Client

	UserInputService.InputBegan:Connect(function(input, gameProcessed) self:HandleInput(input, gameProcessed) end)
	player.CharacterAdded:Connect(function(newCharacter)
		self:StopSpeedBoostManager() -- หยุดของเก่าก่อน
		self:UpdateCharacterReferences(newCharacter)
		self:PreloadDashAnimations()
		self:CleanupAllTrails()
		self:StartSpeedBoostManager() -- เริ่มใหม่สำหรับตัวละครใหม่
	end)
	player.CharacterRemoving:Connect(function()
		self:StopSpeedBoostManager() -- หยุดเมื่อตัวละครถูกลบ
		self:CleanupAllTrails()
	end)
	print("[DashController] Initialized")
end

-- Start Client-Side Speed Boost Manager
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
						-- print("[DashController-Boost] Set speed to boosted:", boostedSpeed) -- Debug
					end
				end
			else
				-- หมดเวลา Boost หรือเวลาไม่ถูกต้อง
				local originalSpeed = humanoid:GetAttribute(ORIGINAL_SPEED_ATTR) or DEFAULT_WALKSPEED
				-- คืนค่า Speed ถ้ายังไม่เท่าค่าเดิม
				if math.abs(humanoid.WalkSpeed - originalSpeed) > 0.1 then
					humanoid.WalkSpeed = originalSpeed
					-- print("[DashController-Boost] Reset speed to original:", originalSpeed) -- Debug
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
				-- print("[DashController-Boost] Reset speed to default/original:", originalSpeed) -- Debug
			end
		end
	end)
	-- print("[DashController] Speed Boost Manager Started.") -- Debug
end

-- Stop Client-Side Speed Boost Manager
function DashController:StopSpeedBoostManager()
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
		-- print("[DashController] Speed Boost Manager Stopped.") -- Debug
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

-- PreloadDashAnimations (เหมือนเดิม)
function DashController:PreloadDashAnimations()
	if not animator then return end; for _,t in pairs(dashAnimations) do if t then t:Destroy() end end; dashAnimations={}
	local ids={Front="rbxassetid://14103831900",Back="rbxassetid://14103833544",Left="rbxassetid://14103834807",Right="rbxassetid://14103836416"}
	for d,id in pairs(ids) do local a=Instance.new("Animation");a.AnimationId=id;local t=animator:LoadAnimation(a);if t then t.Priority=Enum.AnimationPriority.Action;t.Looped=false;dashAnimations[d]=t end;a:Destroy() end
end

-- ConnectRemoteEvents (เหมือนเดิม)
function DashController:ConnectRemoteEvents()
	dashEffect.OnClientEvent:Connect(function(direction, effectType, effectColor, animationId, playerSource)
		if not character or not humanoid or not animator then return end
		if direction == "Complete" then isDashing = false; self:CleanupAllTrails(); return end
		if playerSource and playerSource ~= player then if effectType == "Vanish" then self:PlayOtherPlayerVanishEffect(playerSource, direction, effectColor) end; return end
		isDashing = true
		self:PlayDashEffect(direction, effectType, effectColor, animationId)
	end)
	dashCooldownEvent.OnClientEvent:Connect(function(cooldownTime) self:UpdateCooldown(cooldownTime) end)
	setCombatStateEvent.OnClientEvent:Connect(function(isActive, duration) combatActive = isActive; if not isActive then self:UpdateCooldown(0) end end)
end

-- HandleInput (เหมือนเดิม)
function DashController:HandleInput(input, gameProcessed) if gameProcessed or not combatActive or isDashing or dashCooldown > 0 then return end; if input.KeyCode == DASH_KEY then self:TryDash() end end

-- TryDash (เหมือนเดิม)
function DashController:TryDash() if isDashing then return end; if not character or not humanoid or not humanoid.RootPart then return end; if humanoid:GetState()==Enum.HumanoidStateType.Jumping or humanoid:GetState()==Enum.HumanoidStateType.Freefall or humanoid:GetState()==Enum.HumanoidStateType.Dead then return end; local dir=self:GetDashDirection(); dashRequest:FireServer(dir) end

-- GetDashDirection (เหมือนเดิม)
function DashController:GetDashDirection() if UserInputService:IsKeyDown(Enum.KeyCode.S) then return "Back" elseif UserInputService:IsKeyDown(Enum.KeyCode.A) then return "Left" elseif UserInputService:IsKeyDown(Enum.KeyCode.D) then return "Right" elseif UserInputService:IsKeyDown(Enum.KeyCode.W) then return "Front" else return "Front" end end

-- UpdateCooldown (เหมือนเดิม)
function DashController:UpdateCooldown(newCooldown) dashCooldown=newCooldown;if dashCooldown<=0 then dashCooldown=0;return end;local st=tick();local c;c=RunService.Heartbeat:Connect(function() if not c then return end;local el=tick()-st;local rem=newCooldown-el;if rem<=0 then dashCooldown=0;c:Disconnect();c=nil else dashCooldown=rem end end) end

-- PlayDashEffect (เหมือนเดิม)
function DashController:PlayDashEffect(direction, effectType, effectColor, animationId) if animationId and effectType ~= "Vanish" then local t=dashAnimations[direction];if t then t:Stop(0);t:Play(0.1) else warn("Anim not found:",direction) end end; if effectType=="Roll" then self:PlayRollEffect(effectColor) elseif effectType=="Vanish" then self:PlayVanishEffect(effectColor) end; self:CreateLimbTrailEffect(effectColor) end

-- PlayRollEffect (เหมือนเดิม)
function DashController:PlayRollEffect(effectColor) if not character or not character.PrimaryPart then return end;local h=character.PrimaryPart;local a=Instance.new("Attachment",h);local p=Instance.new("ParticleEmitter",a);p.Texture="rbxassetid://2581889193";p.Color=ColorSequence.new(effectColor,Color3.fromRGB(255,255,255));p.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,1.5),NumberSequenceKeypoint.new(1,0.1)});p.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.4),NumberSequenceKeypoint.new(0.7,0.8),NumberSequenceKeypoint.new(1,1)});p.Lifetime=NumberRange.new(0.4,0.6);p.Rate=50;p.Rotation=NumberRange.new(-180,180);p.RotSpeed=NumberRange.new(-90,90);p.SpreadAngle=Vector2.new(45,45);p.Speed=NumberRange.new(4,7);p.Acceleration=Vector3.new(0,-2,0);game.Debris:AddItem(a,1.5) end

-- PlayVanishEffect (เหมือนเดิม)
function DashController:PlayVanishEffect(effectColor) if not character or not humanoid then return end;local o={};for _,p in pairs(character:GetDescendants()) do if p:IsA("BasePart")or p:IsA("Decal") then o[p]=p.LocalTransparencyModifier;TweenService:Create(p,TweenInfo.new(0.15),{LocalTransparencyModifier=0.95}):Play() end end;local v=ReplicatedStorage:FindFirstChild("VFX");local s=v and v:FindFirstChild("soru");local h=character:FindFirstChild("HumanoidRootPart");if s and h then local r=s:FindFirstChild("Ring");local s1=s:FindFirstChild("Soru1");local s2=s:FindFirstChild("Soru2");if r then local rc=r:Clone();rc.Parent=h;for _,p in ipairs(rc:GetDescendants()) do if p:IsA("ParticleEmitter")then p.Color=ColorSequence.new(effectColor) end end;game.Debris:AddItem(rc,1.5) end;if s1 then local sc=s1:Clone();sc.Parent=h;game.Debris:AddItem(sc,1.5) end;local vd=1.2;task.delay(vd,function() if not character or not character.Parent then return end;for p,ot in pairs(o) do if p and p.Parent then TweenService:Create(p,TweenInfo.new(0.2),{LocalTransparencyModifier=ot}):Play() end end;if s2 and h and h.Parent then local sc2=s2:Clone();sc2.Parent=h;game.Debris:AddItem(sc2,1.5) end end) else warn("VFX/soru not found.");local vd=1.2;task.delay(vd,function() if not character or not character.Parent then return end;for p,ot in pairs(o) do if p and p.Parent then TweenService:Create(p,TweenInfo.new(0.2),{LocalTransparencyModifier=ot}):Play() end end end) end end

-- สร้างเอฟเฟค Trail ที่แขนและขา (แก้ไข WidthScale และ R6)
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
			trail.WidthScale = NumberSequence.new(TRAIL_WIDTH_SCALE) -- แก้ไข: ใช้ NumberSequence.new()
			trail.FaceCamera = true; trail.Enabled = true
			table.insert(activeTrails, trail)
		end
	end
	task.delay(TRAIL_LIFETIME + 0.2, function() for _, att in ipairs(attachments) do if att and att.Parent then att:Destroy() end end end)
end

-- CleanupAllTrails (เหมือนเดิม)
function DashController:CleanupAllTrails() for i=#activeTrails,1,-1 do local t=activeTrails[i];if t and t.Parent then if t.Attachment0 then t.Attachment0:Destroy() end;if t.Attachment1 then t.Attachment1:Destroy() end;t:Destroy() end;table.remove(activeTrails,i) end end

-- PlayOtherPlayerVanishEffect (เหมือนเดิม)
function DashController:PlayOtherPlayerVanishEffect(playerSource, direction, effectColor) local oc=playerSource.Character;if not oc then return end;local h=oc:FindFirstChild("HumanoidRootPart");if not h then return end;local o={};for _,p in pairs(oc:GetDescendants()) do if p:IsA("BasePart")or p:IsA("Decal") then o[p]=p.LocalTransparencyModifier;TweenService:Create(p,TweenInfo.new(0.15),{LocalTransparencyModifier=0.95}):Play() end end;local v=ReplicatedStorage:FindFirstChild("VFX");local s=v and v:FindFirstChild("soru");if s then local r=s:FindFirstChild("Ring");local s1=s:FindFirstChild("Soru1");local s2=s:FindFirstChild("Soru2");if r then local rc=r:Clone();rc.Parent=h;for _,p in ipairs(rc:GetDescendants()) do if p:IsA("ParticleEmitter")then p.Color=ColorSequence.new(effectColor) end end;game.Debris:AddItem(rc,1.5) end;if s1 then local sc=s1:Clone();sc.Parent=h;game.Debris:AddItem(sc,1.5) end;local vd=1.2;task.delay(vd,function() if not oc or not oc.Parent then return end;for p,op in pairs(o) do if p and p.Parent then TweenService:Create(p,TweenInfo.new(0.2),{LocalTransparencyModifier=op}):Play() end end;if s2 and h and h.Parent then local sc2=s2:Clone();sc2.Parent=h;game.Debris:AddItem(sc2,1.5) end end) else local vd=1.2;task.delay(vd,function() if not oc or not oc.Parent then return end;for p,op in pairs(o) do if p and p.Parent then TweenService:Create(p,TweenInfo.new(0.2),{LocalTransparencyModifier=op}):Play() end end end) end end

-- Initialize
DashController:Initialize()

return DashController
