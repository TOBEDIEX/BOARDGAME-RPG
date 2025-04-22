-- ClassSystem.lua
-- Module for managing player classes and stats
-- Location: ServerStorage/Modules/ClassSystem.lua
-- Version: 1.0.2 (Fixed Money Preservation and Improved EXP Updates)

local ClassSystem = {}
ClassSystem.__index = ClassSystem

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Load ClassData module
local SharedModules = ReplicatedStorage:WaitForChild("SharedModules")
local ClassData = require(SharedModules:WaitForChild("ClassData"))

-- Constants
local EXP_TO_LEVEL_DIVIDER = 100  -- For calculating level from exp
local CLASS_EXP_DIVIDER = 150     -- For calculating class level from exp
local MAX_PLAYER_LEVEL = 99 -- กำหนดเลเวลสูงสุด

-- Constructor
function ClassSystem.new()
	local self = setmetatable({}, ClassSystem)

	-- Player data storage
	self.playerClasses = {}       -- Player classes
	self.playerLevels = {}        -- Player levels
	self.playerClassLevels = {}   -- Player class levels
	self.playerExp = {}           -- Player experience
	self.playerClassExp = {}      -- Player class experience

	-- Event callbacks
	self.onClassAssigned = nil    -- Called when class assigned
	self.onLevelUp = nil          -- Called when player levels up
	self.onClassLevelUp = nil     -- Called when class levels up

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
	if #starterClasses == 0 then return nil end -- Handle empty case
	return starterClasses[math.random(1, #starterClasses)]
end

-- Calculate stats for a player based on class and level
function ClassSystem:CalculatePlayerStats(userId, className, level)
	className = className or self.playerClasses[userId]
	level = level or self.playerLevels[userId] or 1

	if not className then
		warn("[ClassSystem] CalculatePlayerStats: No class found for UserId", userId, "- returning default stats.")
		return ClassData.DefaultStats -- Return default stats if no class
	end

	-- Delegate calculation to ClassData module
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

	self.playerClasses[userId] = className
	print("[ClassSystem] Assigning class " .. className .. " to player " .. (typeof(player) == "Instance" and player.Name or tostring(userId)))

	-- Initialize level and experience
	self.playerLevels[userId] = 1
	self.playerClassLevels[userId] = 1
	self.playerExp[userId] = 0
	self.playerClassExp[userId] = 0

	-- Update player stats via GameManager (if available)
	local playerManager = _G.GameManager and _G.GameManager.playerManager
	if playerManager then
		-- Ensure player data exists in PlayerManager before updating stats
		if playerManager:GetPlayerData(player) then
			self:UpdatePlayerStatsFromClass(player, playerManager)
		else
			warn("[ClassSystem] AssignClassToPlayer: Player data not found in PlayerManager for", player.Name, "- stats not updated immediately.")
			-- PlayerManager should handle initializing stats when player is registered
		end
	else
		warn("[ClassSystem] AssignClassToPlayer: PlayerManager not found in _G.GameManager.")
	end

	-- Send RemoteEvent to client
	local playerInstance = Players:GetPlayerByUserId(userId)
	if playerInstance then
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local uiRemotes = remotes:WaitForChild("UIRemotes")
		local classAssignedEvent = uiRemotes:FindFirstChild("ClassAssigned") -- Use FindFirstChild for safety

		if classAssignedEvent then
			classAssignedEvent:FireClient(playerInstance, className, classInfo)
		else
			warn("[ClassSystem] AssignClassToPlayer: ClassAssigned RemoteEvent not found.")
		end
	end

	-- Call callback if assigned
	if self.onClassAssigned then
		-- Ensure we pass the player instance if possible
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

	-- Calculate BASE stats based on class and level (without equipment)
	local baseStats = self:CalculatePlayerStats(userId, className, level)
	if not baseStats then
		warn("[ClassSystem] UpdatePlayerStatsFromClass: Failed to calculate base stats for player: " .. tostring(userId))
		return false
	end

	local playerData = playerManager:GetPlayerData(player)
	if not playerData then
		warn("[ClassSystem] UpdatePlayerStatsFromClass: No player data found in PlayerManager for: " .. tostring(userId))
		return false
	end

	print("[ClassSystem] Updating BASE stats for " .. className .. " (Level " .. level .. "): ", baseStats)

	-- Store current money and EXP values before updating stats
	local currentMoney = playerData.stats.money or 100
	local currentExp = self.playerExp[userId] or 0
	local currentNextLevelExp = self:GetExpForNextLevel(level)

	print("[ClassSystem] Saved current money value before update:", currentMoney)
	print("[ClassSystem] Current EXP values:", currentExp, "/", currentNextLevelExp)

	-- Store current HP/MP percentage before changing max values
	local hpPercent = 1; if playerData.stats and playerData.stats.maxHp and playerData.stats.maxHp > 0 then hpPercent = playerData.stats.hp / playerData.stats.maxHp end
	local mpPercent = 1; if playerData.stats and playerData.stats.maxMp and playerData.stats.maxMp > 0 then mpPercent = playerData.stats.mp / playerData.stats.maxMp end

	-- Update baseStats table in PlayerData
	playerData.baseStats = {
		maxHp = baseStats.MaxHP or 100,
		maxMp = baseStats.MaxMP or 50,
		attack = baseStats.ATK or 10,
		defense = baseStats.DEF or 0,
		magic = baseStats.MAGIC or 10,
		level = level, -- Keep level in base stats for reference
		money = currentMoney -- Preserve money value in base stats
	}

	-- Update main stats level and class
	playerData.stats.level = level
	playerData.class = className
	playerData.stats.money = currentMoney -- Preserve money in main stats too

	-- Update EXP related values in player stats (เพิ่มข้อมูล EXP เข้าไปใน playerData.stats)
	playerData.stats.exp = currentExp
	playerData.stats.nextLevelExp = currentNextLevelExp

	print("[ClassSystem] Updated playerData.stats with EXP values:", playerData.stats.exp, "/", playerData.stats.nextLevelExp)

	-- Let PlayerManager handle applying equipment and syncing
	print("[ClassSystem] Base stats updated. Triggering ApplyEquipmentStatsToPlayer in PlayerManager.")
	playerManager:ApplyEquipmentStatsToPlayer(player) -- This will recalculate final stats and sync

	print("[ClassSystem] UpdatePlayerStatsFromClass finished for " .. className)
	return true
end

-- Calculate level based on total EXP
function ClassSystem:CalculateLevelFromExp(exp)
	if exp < 0 then exp = 0 end -- Ensure non-negative EXP
	local level = 1
	while true do
		-- Check if current level exceeds max level (if defined)
		if level >= MAX_PLAYER_LEVEL then
			return MAX_PLAYER_LEVEL
		end

		local expNeededForNext = self:GetExpForNextLevel(level) -- Exp needed to reach level+1
		if exp < expNeededForNext then
			-- Haven't reached the threshold for the next level yet
			return level
		end
		-- If EXP meets or exceeds threshold, increment level and check next threshold
		level = level + 1
		-- Safety break in case of infinite loop
		if level > MAX_PLAYER_LEVEL + 5 then
			warn("[ClassSystem] CalculateLevelFromExp potentially looping, breaking at level", level)
			return MAX_PLAYER_LEVEL
		end
	end
end

-- Check for level up
function ClassSystem:CheckLevelUp(userId)
	local currentExp = self.playerExp[userId]
	if currentExp == nil then return false end -- No EXP data

	local oldLevel = self.playerLevels[userId] or 1
	-- Calculate level based on current total EXP
	local newLevel = self:CalculateLevelFromExp(currentExp)

	if newLevel > oldLevel then
		print(string.format("[ClassSystem] Player %d Leveled Up! %d -> %d (Exp: %d)", userId, oldLevel, newLevel, currentExp))
		local levelDiff = newLevel - oldLevel
		self.playerLevels[userId] = newLevel -- Update stored level

		-- Calculate new base stats based on the new level
		local className = self.playerClasses[userId]
		-- Calculate stats for old and new level to find the difference
		local oldBaseStats = self:CalculatePlayerStats(userId, className, oldLevel)
		local newBaseStats = self:CalculatePlayerStats(userId, className, newLevel)

		-- Calculate stat increases (difference between new base and old base)
		local statIncreases = {}
		if oldBaseStats and newBaseStats then
			for stat, newValue in pairs(newBaseStats) do
				-- Compare with old value, default to 0 if stat didn't exist before
				statIncreases[stat] = newValue - (oldBaseStats[stat] or 0)
			end
			print("[ClassSystem] Stat Increases:", statIncreases)
		else
			warn("[ClassSystem] CheckLevelUp: Failed to calculate old or new base stats for stat increase calculation.")
		end

		-- Notify client and update stats
		local player = Players:GetPlayerByUserId(userId)
		if player then
			-- Apply the calculated stat increases via PlayerManager
			-- This function should add the increases to the *current* stats in PlayerManager
			self:ApplyStatIncreases(player, statIncreases)

			-- Send level up notification to client *after* stats are applied
			local remotes = ReplicatedStorage:WaitForChild("Remotes")
			local uiRemotes = remotes:WaitForChild("UIRemotes")
			local levelUpEvent = uiRemotes:FindFirstChild("LevelUp")
			if levelUpEvent then
				levelUpEvent:FireClient(player, newLevel, statIncreases) -- Send level and increases
			else
				warn("[ClassSystem] CheckLevelUp: LevelUp RemoteEvent not found.")
			end

			-- ส่งอัพเดต EXP หลังจาก Level Up ด้วย
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

			-- Call level up callback if set
			if self.onLevelUp then
				pcall(self.onLevelUp, player, newLevel, oldLevel, statIncreases)
			end
		end

		return true -- Leveled up
	end

	return false -- Did not level up
end

-- Apply stat increases to player's current stats in PlayerManager
function ClassSystem:ApplyStatIncreases(player, statIncreases)
	local playerManager = _G.GameManager and _G.GameManager.playerManager
	if not playerManager then warn("[ClassSystem] ApplyStatIncreases: PlayerManager not found."); return end

	local playerData = playerManager:GetPlayerData(player)
	if not playerData or not playerData.stats then warn("[ClassSystem] ApplyStatIncreases: PlayerData or stats not found for", player.Name); return end

	print("[ClassSystem] Applying Stat Increases for", player.Name, ":", statIncreases)

	-- Store current money before updates
	local currentMoney = playerData.stats.money or 100
	print("[ClassSystem] Saved money before applying stat increases:", currentMoney)

	-- Map ClassData stat names (used in calculation) to PlayerManager stat names
	local statMapping = {
		MaxHP = "maxHp", MaxMP = "maxMp",
		ATK = "attack", DEF = "defense", MAGIC = "magic"
	}

	local statsToUpdate = {}
	local maxHpIncreased = false
	local maxMpIncreased = false

	-- Update each stat in playerData.stats and playerData.baseStats
	for classDataStat, increase in pairs(statIncreases) do
		if increase ~= 0 then -- Only apply if there's an actual increase
			local pmStatName = statMapping[classDataStat]
			if pmStatName then
				-- Update base stat first
				if playerData.baseStats[pmStatName] ~= nil then
					playerData.baseStats[pmStatName] = playerData.baseStats[pmStatName] + increase
					print(string.format("  > Updated baseStat %s by %d to %d", pmStatName, increase, playerData.baseStats[pmStatName]))
				else
					warn(string.format("[ClassSystem] ApplyStatIncreases: BaseStat '%s' not found for %s", pmStatName, player.Name))
				end

				-- Track if MaxHP/MP increased to potentially heal fully
				if pmStatName == "maxHp" then maxHpIncreased = true end
				if pmStatName == "maxMp" then maxMpIncreased = true end
			end
		end
	end

	-- Re-apply equipment stats which will use the updated baseStats
	print("[ClassSystem] ApplyStatIncreases: Re-applying equipment stats after base stat update.")

	-- Restore money in baseStats before re-applying equipment
	playerData.baseStats.money = currentMoney

	playerManager:ApplyEquipmentStatsToPlayer(player) -- This recalculates final stats and syncs

	-- Heal to full HP/MP after level up (using final stats after equipment)
	local finalPlayerData = playerManager:GetPlayerData(player) -- Get updated data again
	if finalPlayerData and finalPlayerData.stats then
		-- Fix money one last time if needed
		finalPlayerData.stats.money = currentMoney

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
	if level <= 1 then return 0 end -- Level 1 requires 0 total EXP
	return (level * level) * EXP_TO_LEVEL_DIVIDER
end

-- Get TOTAL exp required to reach the NEXT level (level + 1)
function ClassSystem:GetExpForNextLevel(currentLevel)
	local nextLevel = currentLevel + 1
	return self:GetExpForLevel(nextLevel)
end


-- Get class exp required for next level
function ClassSystem:GetClassExpForNextLevel(classLevel)
	-- Assuming similar quadratic scaling for class levels
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
	if amount <= 0 then return false end -- Don't add zero or negative EXP

	-- Add experience
	local oldExp = self.playerExp[userId]
	self.playerExp[userId] = self.playerExp[userId] + amount
	-- Also add class experience (e.g., 70% of player exp)
	local classExpToAdd = math.floor(amount * 0.7)
	self.playerClassExp[userId] = (self.playerClassExp[userId] or 0) + classExpToAdd

	print(string.format("[ClassSystem] Added %d EXP to player %d. Total EXP: %d -> %d. Added %d Class EXP.", amount, userId, oldExp, self.playerExp[userId], classExpToAdd))

	-- Send updated exp to client BEFORE checking level up
	local playerInstance = Players:GetPlayerByUserId(userId)
	if playerInstance then
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local uiRemotes = remotes:WaitForChild("UIRemotes")
		local updateExpEvent = uiRemotes:FindFirstChild("UpdateExperience")
		if updateExpEvent then
			-- Get current levels
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

		-- Check for level up(s) AFTER sending initial EXP update
local leveledUp = self:CheckLevelUp(userId)
local classLeveledUp = self:CheckClassLevelUp(userId) -- Check class level up too

return leveledUp or classLeveledUp -- Return true if either player or class leveled up
end

-- Check for class level up and possible class upgrade
function ClassSystem:CheckClassLevelUp(userId)
	if self.playerClassExp[userId] == nil then return false end

	local oldClassLevel = self.playerClassLevels[userId] or 1
	-- Calculate class level using iterative method
	local newClassLevel = 1
	while true do
		local expForNextClassLevel = self:GetClassExpForNextLevel(newClassLevel)
		if self.playerClassExp[userId] < expForNextClassLevel then
			break -- Current class level is newClassLevel
		end
		newClassLevel = newClassLevel + 1
		end

		if newClassLevel > oldClassLevel then
	print(string.format("[ClassSystem] Player %d Class Leveled Up! %d -> %d (Class Exp: %d)", userId, oldClassLevel, newClassLevel, self.playerClassExp[userId]))
	local levelDiff = newClassLevel - oldClassLevel
	self.playerClassLevels[userId] = newClassLevel

	-- Get current class and info
	local className = self.playerClasses[userId]
	local classInfo = ClassData:GetClassInfo(className)

	-- Calculate stat increases from class level up (e.g., smaller bonus than player level up)
	local statIncreases = {} -- Define how class levels grant stats, maybe fixed bonuses?
	-- Example: Small fixed bonus per class level
	-- statIncreases = { MaxHP = 5 * levelDiff, ATK = 1 * levelDiff } -- Define actual bonuses

	-- Check for class upgrade availability
	local nextClass = classInfo and classInfo.NextClass
	local upgradeCondition = classInfo and classInfo.UpgradeCondition
	local canUpgradeClass = false
	if upgradeCondition and nextClass then
		if upgradeCondition.Type == "Level" and newClassLevel >= upgradeCondition.Value then
			canUpgradeClass = true
			print("[ClassSystem] Player", userId, "can now upgrade class to", nextClass)
		end
		-- Add other condition checks (Quest, Item, Skill) if needed
	end

	-- Notify client and update stats
	local player = Players:GetPlayerByUserId(userId)
	if player then
		-- Apply stat increases (if any defined)
		if next(statIncreases) ~= nil then -- Check if table is not empty
			self:ApplyStatIncreases(player, statIncreases)
		end

		-- Send class level up notification
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local uiRemotes = remotes:WaitForChild("UIRemotes")
		local classLevelUpEvent = uiRemotes:FindFirstChild("ClassLevelUp")
		if classLevelUpEvent then
			classLevelUpEvent:FireClient(
				player, newClassLevel, statIncreases,
				canUpgradeClass and nextClass or nil -- Send next class name if upgradeable
			)
		else
			warn("[ClassSystem] CheckClassLevelUp: ClassLevelUp RemoteEvent not found.")
		end

		-- Notify if class upgrade available
		if canUpgradeClass and nextClass then
			local classUpgradeEvent = uiRemotes:FindFirstChild("ClassUpgradeAvailable")
			if classUpgradeEvent then
				local nextClassInfo = ClassData:GetClassInfo(nextClass)
				classUpgradeEvent:FireClient(player, nextClass, nextClassInfo)
			else
				warn("[ClassSystem] CheckClassLevelUp: ClassUpgradeAvailable RemoteEvent not found.")
			end
		end

		-- Call class level up callback if set
		if self.onClassLevelUp then
			pcall(self.onClassLevelUp, player, newClassLevel, oldClassLevel, statIncreases, canUpgradeClass and nextClass or nil)
		end
	end
	return true -- Class leveled up
end
return false -- Did not class level up
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

	-- Check upgrade condition
	if upgradeCondition then
		if upgradeCondition.Type == "Level" then
			local classLevel = self.playerClassLevels[userId] or 1
			if classLevel < upgradeCondition.Value then
				return false, "Class level " .. upgradeCondition.Value .. " required for upgrade"
				end
				end
				end

				-- Perform the upgrade by assigning the new class
print(string.format("[ClassSystem] Upgrading player %d from %s to %s", userId, currentClass, nextClass))
return self:AssignClassToPlayer(player, nextClass) -- AssignClass handles stat updates etc.
end

-- Reset all player class data (for game restart)
function ClassSystem:ResetAllPlayerClasses()
	print("[ClassSystem] Resetting all player class data.")
	self.playerClasses = {}
	self.playerLevels = {}
	self.playerClassLevels = {}
	self.playerExp = {}
	self.playerClassExp = {}
end

return ClassSystem
