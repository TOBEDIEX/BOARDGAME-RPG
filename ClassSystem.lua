-- ClassSystem.lua
-- Module for managing player classes and stats
-- Location: ServerStorage/Modules/ClassSystem.lua
-- Version: 1.0.3 (Added SetAttribute for 'Class' on Humanoid)

local ClassSystem = {}
ClassSystem.__index = ClassSystem

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Load ClassData module
local SharedModules = ReplicatedStorage:WaitForChild("SharedModules")
local ClassData = require(SharedModules:WaitForChild("ClassData"))

-- Constants
local EXP_TO_LEVEL_DIVIDER = 100
local CLASS_EXP_DIVIDER = 150
local MAX_PLAYER_LEVEL = 99
local ATTR_CLASS = "Class" -- ชื่อ Attribute ที่จะใช้ (ควรตรงกับ Client)

-- Constructor
function ClassSystem.new()
	local self = setmetatable({}, ClassSystem)

	self.playerClasses = {}
	self.playerLevels = {}
	self.playerClassLevels = {}
	self.playerExp = {}
	self.playerClassExp = {}

	self.onClassAssigned = nil
	self.onLevelUp = nil
	self.onClassLevelUp = nil

	return self
end

-- Get all starter classes
function ClassSystem:GetStarterClasses()
	return ClassData:GetStarterClasses()
end

-- Get all classes (including upgrades)
function ClassSystem:GetAllClasses()
	return ClassData:GetAllClasses()
end

-- Get class info
function ClassSystem:GetClassInfo(className)
	return ClassData:GetClassInfo(className)
end

-- Get random starter class
function ClassSystem:GetRandomClass()
	local starterClasses = self:GetStarterClasses()
	if #starterClasses == 0 then return nil end
	return starterClasses[math.random(1, #starterClasses)]
end

-- Calculate stats for a player based on class and level
function ClassSystem:CalculatePlayerStats(userId, className, level)
	className = className or self.playerClasses[userId]
	level = level or self.playerLevels[userId] or 1

	if not className then
		warn("[ClassSystem] CalculatePlayerStats: No class found for UserId", userId, "- returning default stats.")
		return ClassData.DefaultStats
	end

	local calculatedStats = ClassData:CalculateStatsAtLevel(className, level)
	if not calculatedStats then
		warn(string.format("[ClassSystem] CalculatePlayerStats: ClassData:CalculateStatsAtLevel returned nil for %s at level %d. Returning defaults.", className, level))
		return ClassData.DefaultStats
	end
	return calculatedStats
end

-- Assign class to player
function ClassSystem:AssignClassToPlayer(player, className)
	local userId = typeof(player) == "Instance" and player:IsA("Player") and player.UserId or player
	if not userId then warn("[ClassSystem] AssignClassToPlayer: Invalid player argument."); return false end

	local classInfo = ClassData:GetClassInfo(className)
	if not classInfo then
		warn("[ClassSystem] AssignClassToPlayer: Class not found in ClassData: " .. tostring(className))
		return false
	end

	-- 1. Store class internally
	self.playerClasses[userId] = className
	print("[ClassSystem] Assigning class " .. className .. " to player " .. (typeof(player) == "Instance" and player.Name or tostring(userId)))

	-- 2. Initialize level and experience
	self.playerLevels[userId] = 1
	self.playerClassLevels[userId] = 1
	self.playerExp[userId] = 0
	self.playerClassExp[userId] = 0

	-- 3. Get Player Instance (needed for Humanoid and Events)
	local playerInstance = Players:GetPlayerByUserId(userId)

	-- *** NEW: Set 'Class' Attribute on Humanoid ***
	if playerInstance and playerInstance.Character then
		local character = playerInstance.Character
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:SetAttribute(ATTR_CLASS, className)
			print("[ClassSystem] Set attribute '"..ATTR_CLASS.."' to '"..className.."' on Humanoid for player " .. playerInstance.Name)
		else
			warn("[ClassSystem] AssignClassToPlayer: Humanoid not found for player " .. playerInstance.Name .. " when trying to set attribute.")
			-- Consider waiting for humanoid if needed, or handle cases where character loads later
			-- playerInstance.CharacterAdded:Connect(function(char)
			--    local hum = char:WaitForChild("Humanoid")
			--    hum:SetAttribute(ATTR_CLASS, className)
			--    print("[ClassSystem] Set attribute on newly added character's Humanoid.")
			-- end)
		end
	elseif playerInstance then
		warn("[ClassSystem] AssignClassToPlayer: Character not found for player " .. playerInstance.Name .. " when trying to set attribute.")
		-- Handle character not loaded yet if necessary
	end
	-- *** END NEW CODE ***

	-- 4. Update player stats via GameManager (if available)
	local playerManager = _G.GameManager and _G.GameManager.playerManager
	if playerManager then
		if playerManager:GetPlayerData(playerInstance or userId) then -- Pass instance if available
			self:UpdatePlayerStatsFromClass(playerInstance or userId, playerManager)
		else
			warn("[ClassSystem] AssignClassToPlayer: Player data not found in PlayerManager for", (playerInstance and playerInstance.Name or userId), "- stats not updated immediately.")
		end
	else
		warn("[ClassSystem] AssignClassToPlayer: PlayerManager not found in _G.GameManager.")
	end

	-- 5. Send RemoteEvent to client
	if playerInstance then
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local uiRemotes = remotes:WaitForChild("UIRemotes")
		local classAssignedEvent = uiRemotes:FindFirstChild("ClassAssigned")

		if classAssignedEvent then
			-- Fire event *after* setting attribute and updating stats
			classAssignedEvent:FireClient(playerInstance, className, classInfo)
		else
			warn("[ClassSystem] AssignClassToPlayer: ClassAssigned RemoteEvent not found.")
		end
	end

	-- 6. Call callback if assigned
	if self.onClassAssigned then
		pcall(self.onClassAssigned, playerInstance or player, className, classInfo)
	end

	return true
end


-- Update player stats based on class (called by AssignClassToPlayer and potentially LevelUp)
function ClassSystem:UpdatePlayerStatsFromClass(player, playerManager)
	local userId = typeof(player) == "Instance" and player:IsA("Player") and player.UserId or player
	if not userId then warn("[ClassSystem] UpdatePlayerStatsFromClass: Invalid player argument."); return false end

	local className = self.playerClasses[userId]
	local level = self.playerLevels[userId] or 1

	if not className then
		warn("[ClassSystem] UpdatePlayerStatsFromClass: No class assigned to player: " .. tostring(userId))
		return false
	end

	local baseStats = self:CalculatePlayerStats(userId, className, level)
	if not baseStats then
		warn("[ClassSystem] UpdatePlayerStatsFromClass: Failed to calculate base stats for player: " .. tostring(userId))
		return false
	end

	local playerInstance = Players:GetPlayerByUserId(userId) -- Get instance for name
	local playerName = playerInstance and playerInstance.Name or tostring(userId)

	local playerData = playerManager:GetPlayerData(player) -- Use the original argument (instance or ID)
	if not playerData then
		warn("[ClassSystem] UpdatePlayerStatsFromClass: No player data found in PlayerManager for: " .. playerName)
		return false
	end

	print("[ClassSystem] Updating BASE stats for " .. playerName .. " (" .. className .. " Level " .. level .. "): ", baseStats)

	local currentMoney = playerData.stats and playerData.stats.money or 100 -- Default money if stats exist but money doesn't
	local currentExp = self.playerExp[userId] or 0
	local currentNextLevelExp = self:GetExpForNextLevel(level)

	-- Ensure stats table exists
	if not playerData.stats then playerData.stats = {} end
	if not playerData.baseStats then playerData.baseStats = {} end

	local hpPercent = 1; if playerData.stats.maxHp and playerData.stats.maxHp > 0 then hpPercent = (playerData.stats.hp or playerData.stats.maxHp) / playerData.stats.maxHp end
	local mpPercent = 1; if playerData.stats.maxMp and playerData.stats.maxMp > 0 then mpPercent = (playerData.stats.mp or playerData.stats.maxMp) / playerData.stats.maxMp end

	playerData.baseStats = {
		maxHp = baseStats.MaxHP or 100,
		maxMp = baseStats.MaxMP or 50,
		attack = baseStats.ATK or 10,
		defense = baseStats.DEF or 0,
		magic = baseStats.MAGIC or 10,
		level = level,
		money = currentMoney
	}

	playerData.stats.level = level
	playerData.class = className
	playerData.stats.money = currentMoney
	playerData.stats.exp = currentExp
	playerData.stats.nextLevelExp = currentNextLevelExp

	print("[ClassSystem] Updated playerData.stats with EXP values:", playerData.stats.exp, "/", playerData.stats.nextLevelExp)

	print("[ClassSystem] Base stats updated. Triggering ApplyEquipmentStatsToPlayer in PlayerManager.")
	playerManager:ApplyEquipmentStatsToPlayer(player) -- Pass original argument

	-- Restore HP/MP based on percentage AFTER equipment applied
	local finalPlayerData = playerManager:GetPlayerData(player)
	if finalPlayerData and finalPlayerData.stats then
		local finalMaxHp = finalPlayerData.stats.maxHp or 100
		local finalMaxMp = finalPlayerData.stats.maxMp or 50
		local newHp = math.max(1, math.floor(finalMaxHp * hpPercent)) -- Ensure at least 1 HP
		local newMp = math.floor(finalMaxMp * mpPercent)

		-- Use PlayerManager functions to update HP/MP to trigger UI updates etc.
		playerManager:UpdatePlayerHP(player, newHp)
		playerManager:UpdatePlayerMP(player, newMp)
		print(string.format("[ClassSystem] Restored HP/MP for %s: HP=%d/%d (%.2f%%), MP=%d/%d (%.2f%%)",
			playerName, newHp, finalMaxHp, hpPercent*100, newMp, finalMaxMp, mpPercent*100))
	end

	print("[ClassSystem] UpdatePlayerStatsFromClass finished for " .. playerName)
	return true
end


-- Calculate level based on total EXP
function ClassSystem:CalculateLevelFromExp(exp)
	if exp < 0 then exp = 0 end
	local level = 1
	while true do
		if level >= MAX_PLAYER_LEVEL then return MAX_PLAYER_LEVEL end
		local expNeededForNext = self:GetExpForNextLevel(level)
		if exp < expNeededForNext then return level end
		level = level + 1
		if level > MAX_PLAYER_LEVEL + 5 then warn("[ClassSystem] CalculateLevelFromExp potentially looping, breaking at level", level); return MAX_PLAYER_LEVEL end
	end
end

-- Check for level up
function ClassSystem:CheckLevelUp(userId)
	local currentExp = self.playerExp[userId]
	if currentExp == nil then return false end

	local oldLevel = self.playerLevels[userId] or 1
	local newLevel = self:CalculateLevelFromExp(currentExp)

	if newLevel > oldLevel then
		print(string.format("[ClassSystem] Player %d Leveled Up! %d -> %d (Exp: %d)", userId, oldLevel, newLevel, currentExp))
		local levelDiff = newLevel - oldLevel
		self.playerLevels[userId] = newLevel

		local className = self.playerClasses[userId]
		local oldBaseStats = self:CalculatePlayerStats(userId, className, oldLevel)
		local newBaseStats = self:CalculatePlayerStats(userId, className, newLevel)

		local statIncreases = {}
		if oldBaseStats and newBaseStats then
			for stat, newValue in pairs(newBaseStats) do
				statIncreases[stat] = newValue - (oldBaseStats[stat] or 0)
			end
			print("[ClassSystem] Stat Increases:", statIncreases)
		else
			warn("[ClassSystem] CheckLevelUp: Failed to calculate old or new base stats for stat increase calculation.")
		end

		local player = Players:GetPlayerByUserId(userId)
		if player then
			self:ApplyStatIncreases(player, statIncreases)

			local remotes = ReplicatedStorage:WaitForChild("Remotes")
			local uiRemotes = remotes:WaitForChild("UIRemotes")
			local levelUpEvent = uiRemotes:FindFirstChild("LevelUp")
			if levelUpEvent then
				levelUpEvent:FireClient(player, newLevel, statIncreases)
			else
				warn("[ClassSystem] CheckLevelUp: LevelUp RemoteEvent not found.")
			end

			local updateExpEvent = uiRemotes:FindFirstChild("UpdateExperience")
			if updateExpEvent then
				local nextLevelExp = self:GetExpForNextLevel(newLevel)
				print("[ClassSystem] After LevelUp: Sending updated EXP data:", currentExp, "/", nextLevelExp)
				updateExpEvent:FireClient(player, {
					exp = currentExp,
					nextLevelExp = nextLevelExp,
					level = newLevel,
					classExp = self.playerClassExp[userId] or 0,
					nextClassLevelExp = self:GetClassExpForNextLevel(self.playerClassLevels[userId] or 1),
					classLevel = self.playerClassLevels[userId] or 1
				})
			end

			if self.onLevelUp then
				pcall(self.onLevelUp, player, newLevel, oldLevel, statIncreases)
			end
		end
		return true
	end
	return false
end


-- Apply stat increases to player's current stats in PlayerManager
function ClassSystem:ApplyStatIncreases(player, statIncreases)
	local playerManager = _G.GameManager and _G.GameManager.playerManager
	if not playerManager then warn("[ClassSystem] ApplyStatIncreases: PlayerManager not found."); return end

	local playerData = playerManager:GetPlayerData(player)
	if not playerData or not playerData.stats then warn("[ClassSystem] ApplyStatIncreases: PlayerData or stats not found for", player.Name); return end

	print("[ClassSystem] Applying Stat Increases for", player.Name, ":", statIncreases)

	local currentMoney = playerData.stats.money or 100

	local statMapping = { MaxHP = "maxHp", MaxMP = "maxMp", ATK = "attack", DEF = "defense", MAGIC = "magic" }
	local maxHpIncreased = false
	local maxMpIncreased = false

	-- Ensure baseStats exists
	if not playerData.baseStats then playerData.baseStats = {} end

	for classDataStat, increase in pairs(statIncreases) do
		if increase ~= 0 then
			local pmStatName = statMapping[classDataStat]
			if pmStatName then
				-- Update base stat, initialize if nil
				playerData.baseStats[pmStatName] = (playerData.baseStats[pmStatName] or 0) + increase
				print(string.format("  > Updated baseStat %s by %d to %d", pmStatName, increase, playerData.baseStats[pmStatName]))

				if pmStatName == "maxHp" then maxHpIncreased = true end
				if pmStatName == "maxMp" then maxMpIncreased = true end
			end
		end
	end

	print("[ClassSystem] ApplyStatIncreases: Re-applying equipment stats after base stat update.")
	playerData.baseStats.money = currentMoney -- Restore money in baseStats before re-applying
	playerManager:ApplyEquipmentStatsToPlayer(player)

	local finalPlayerData = playerManager:GetPlayerData(player)
	if finalPlayerData and finalPlayerData.stats then
		finalPlayerData.stats.money = currentMoney -- Ensure money is correct in final stats

		if maxHpIncreased then
			print("[ClassSystem] ApplyStatIncreases: Healing HP to full after level up.")
			playerManager:UpdatePlayerHP(player, finalPlayerData.stats.maxHp)
		end
		if maxMpIncreased then
			print("[ClassSystem] ApplyStatIncreases: Restoring MP to full after level up.")
			playerManager:UpdatePlayerMP(player, finalPlayerData.stats.maxMp)
		end
	end
end


-- Get player's class
function ClassSystem:GetPlayerClass(player)
	local userId = typeof(player) == "Instance" and player:IsA("Player") and player.UserId or player
	return self.playerClasses[userId]
end

-- Get player's level
function ClassSystem:GetPlayerLevel(player)
	local userId = typeof(player) == "Instance" and player:IsA("Player") and player.UserId or player
	return self.playerLevels[userId] or 1
end

-- Get player's class level
function ClassSystem:GetPlayerClassLevel(player)
	local userId = typeof(player) == "Instance" and player:IsA("Player") and player.UserId or player
	return self.playerClassLevels[userId] or 1
end

-- Get TOTAL exp required to reach the start of a given level
function ClassSystem:GetExpForLevel(level)
	if level <= 1 then return 0 end
	return (level * level) * EXP_TO_LEVEL_DIVIDER
end

-- Get TOTAL exp required to reach the NEXT level (level + 1)
function ClassSystem:GetExpForNextLevel(currentLevel)
	local nextLevel = currentLevel + 1
	return self:GetExpForLevel(nextLevel)
end


-- Get class exp required for next level
function ClassSystem:GetClassExpForNextLevel(classLevel)
	local nextClassLevel = classLevel + 1
	return (nextClassLevel * nextClassLevel) * CLASS_EXP_DIVIDER
end

-- Add experience to player
function ClassSystem:AddExperience(player, amount)
	local userId = typeof(player) == "Instance" and player:IsA("Player") and player.UserId or player
	if not userId then warn("[ClassSystem] AddExperience: Invalid player argument."); return false end

	if self.playerExp[userId] == nil then
		warn("[ClassSystem] AddExperience: No EXP data found for UserId", userId, "- cannot add EXP.")
		return false
	end
	if amount <= 0 then return false end

	local oldExp = self.playerExp[userId]
	self.playerExp[userId] = self.playerExp[userId] + amount
	local classExpToAdd = math.floor(amount * 0.7)
	self.playerClassExp[userId] = (self.playerClassExp[userId] or 0) + classExpToAdd

	print(string.format("[ClassSystem] Added %d EXP to player %d. Total EXP: %d -> %d. Added %d Class EXP.", amount, userId, oldExp, self.playerExp[userId], classExpToAdd))

	local playerInstance = Players:GetPlayerByUserId(userId)
	if playerInstance then
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local uiRemotes = remotes:WaitForChild("UIRemotes")
		local updateExpEvent = uiRemotes:FindFirstChild("UpdateExperience")
		if updateExpEvent then
			local currentLevel = self.playerLevels[userId] or 1
			local currentClassLevel = self.playerClassLevels[userId] or 1
			print("[ClassSystem] Before LevelCheck: Sending EXP update", self.playerExp[userId], "/", self:GetExpForNextLevel(currentLevel))
			updateExpEvent:FireClient(playerInstance, {
				exp = self.playerExp[userId],
				nextLevelExp = self:GetExpForNextLevel(currentLevel),
				level = currentLevel,
				classExp = self.playerClassExp[userId],
				nextClassLevelExp = self:GetClassExpForNextLevel(currentClassLevel),
				classLevel = currentClassLevel
			})
		else
			warn("[ClassSystem] AddExperience: UpdateExperience RemoteEvent not found.")
		end
	end

	local leveledUp = self:CheckLevelUp(userId)
	local classLeveledUp = self:CheckClassLevelUp(userId)

	return leveledUp or classLeveledUp
end


-- Check for class level up and possible class upgrade
function ClassSystem:CheckClassLevelUp(userId)
	if self.playerClassExp[userId] == nil then return false end

	local oldClassLevel = self.playerClassLevels[userId] or 1
	local newClassLevel = 1
	while true do
		local expForNextClassLevel = self:GetClassExpForNextLevel(newClassLevel)
		if self.playerClassExp[userId] < expForNextClassLevel then
			break
		end
		newClassLevel = newClassLevel + 1
	end

	if newClassLevel > oldClassLevel then
		print(string.format("[ClassSystem] Player %d Class Leveled Up! %d -> %d (Class Exp: %d)", userId, oldClassLevel, newClassLevel, self.playerClassExp[userId]))
		local levelDiff = newClassLevel - oldClassLevel
		self.playerClassLevels[userId] = newClassLevel

		local className = self.playerClasses[userId]
		local classInfo = ClassData:GetClassInfo(className)
		local statIncreases = {} -- Define class level up stat bonuses here if any

		local nextClass = classInfo and classInfo.NextClass
		local upgradeCondition = classInfo and classInfo.UpgradeCondition
		local canUpgradeClass = false
		if upgradeCondition and nextClass then
			if upgradeCondition.Type == "Level" and newClassLevel >= upgradeCondition.Value then
				canUpgradeClass = true
				print("[ClassSystem] Player", userId, "can now upgrade class to", nextClass)
			end
		end

		local player = Players:GetPlayerByUserId(userId)
		if player then
			if next(statIncreases) ~= nil then
				self:ApplyStatIncreases(player, statIncreases)
			end

			local remotes = ReplicatedStorage:WaitForChild("Remotes")
			local uiRemotes = remotes:WaitForChild("UIRemotes")
			local classLevelUpEvent = uiRemotes:FindFirstChild("ClassLevelUp")
			if classLevelUpEvent then
				classLevelUpEvent:FireClient(player, newClassLevel, statIncreases, canUpgradeClass and nextClass or nil)
			else
				warn("[ClassSystem] CheckClassLevelUp: ClassLevelUp RemoteEvent not found.")
			end

			if canUpgradeClass and nextClass then
				local classUpgradeEvent = uiRemotes:FindFirstChild("ClassUpgradeAvailable")
				if classUpgradeEvent then
					local nextClassInfo = ClassData:GetClassInfo(nextClass)
					classUpgradeEvent:FireClient(player, nextClass, nextClassInfo)
				else
					warn("[ClassSystem] CheckClassLevelUp: ClassUpgradeAvailable RemoteEvent not found.")
				end
			end

			if self.onClassLevelUp then
				pcall(self.onClassLevelUp, player, newClassLevel, oldClassLevel, statIncreases, canUpgradeClass and nextClass or nil)
			end
		end
		return true
	end
	return false
end


-- Upgrade player to next class
function ClassSystem:UpgradePlayerClass(player)
	local userId = typeof(player) == "Instance" and player:IsA("Player") and player.UserId or player
	if not userId then warn("[ClassSystem] UpgradePlayerClass: Invalid player argument."); return false, "Invalid player" end

	local currentClass = self.playerClasses[userId]
	if not currentClass then return false, "No class assigned to player" end

	local classInfo = ClassData:GetClassInfo(currentClass)
	if not classInfo or not classInfo.NextClass then return false, "No upgrade available for this class" end

	local nextClass = classInfo.NextClass
	local upgradeCondition = classInfo.UpgradeCondition

	if upgradeCondition then
		if upgradeCondition.Type == "Level" then
			local classLevel = self.playerClassLevels[userId] or 1
			if classLevel < upgradeCondition.Value then
				return false, "Class level " .. upgradeCondition.Value .. " required for upgrade"
			end
			-- Add other condition checks here (Quest, Item, Skill)
			-- elseif upgradeCondition.Type == "Quest" then ...
		end
	end

	print(string.format("[ClassSystem] Upgrading player %d from %s to %s", userId, currentClass, nextClass))
	-- AssignClassToPlayer returns true/false for success/failure
	local success = self:AssignClassToPlayer(player, nextClass)
	if success then
		return true, "Successfully upgraded to " .. nextClass
	else
		return false, "Failed to assign the upgraded class"
	end
end


-- Reset all player class data (for game restart)
function ClassSystem:ResetAllPlayerClasses()
	print("[ClassSystem] Resetting all player class data.")
	self.playerClasses = {}
	self.playerLevels = {}
	self.playerClassLevels = {}
	self.playerExp = {}
	self.playerClassExp = {}
	-- Reset attributes on existing players' humanoids? Maybe not necessary if characters reset too.
end

return ClassSystem
