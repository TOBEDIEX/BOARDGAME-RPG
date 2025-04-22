-- ClassData.lua
-- Class and stats data for the game (Updated version with DEF instead of MaxHP)
-- Location: ReplicatedStorage/SharedModules/ClassData.lua
-- Version: 2.0.0

local ClassData = {}

--[[
    Data Structure:
    - DisplayName: Name displayed in game
    - Description: Class description
    - IconAssetId: Asset ID for the class icon
    - BaseStats: Base stats for the class (at level 1)
      - DEF: Defense power (now used to calculate MaxHP: 1 DEF = 1 MaxHP)
      - MaxMP: Maximum magic points
      - ATK: Attack power
      - MAGIC: Magic power
    - Growth: Stat growth rates when leveling up (percentage)
    - NextClass: Next upgrade class
    - UpgradeCondition: Condition to upgrade class
]]

-- Game Classes
ClassData.Classes = {
	-- ===== Starter Classes =====
	Warrior = {
		DisplayName = "Warrior",
		Description = "Strong fighter with high HP and attack power. Excels at front-line combat.",
		IconAssetId = "rbxassetid://0", -- Replace with actual Asset ID
		BaseStats = {
			DEF = 125, -- Changed from MaxHP to DEF (value remains the same)
			MaxMP = 50,
			ATK = 95,
			MAGIC = 10
		},
		Growth = {
			DEF = 10, -- Changed from MaxHP to DEF (growth rate remains the same)
			MaxMP = 5,  -- 5% increase per level
			ATK = 8,    -- 8% increase per level
			MAGIC = 2   -- 2% increase per level
		},
		NextClass = "Knight",
		UpgradeCondition = { Type = "Level", Value = 10 }
	},

	Mage = {
		DisplayName = "Mage",
		Description = "Spell caster with high magic power and MP. Physically fragile but devastating spells.",
		IconAssetId = "rbxassetid://0", -- Replace with actual Asset ID
		BaseStats = {
			DEF = 85, -- Changed from MaxHP to DEF
			MaxMP = 120,
			ATK = 25,
			MAGIC = 95
		},
		Growth = {
			DEF = 5,   -- Changed from MaxHP to DEF
			MaxMP = 10,  -- 10% increase per level
			ATK = 3,     -- 3% increase per level
			MAGIC = 9    -- 9% increase per level
		},
		NextClass = "Wizard",
		UpgradeCondition = { Type = "Level", Value = 10 }
	},

	Thief = {
		DisplayName = "Thief",
		Description = "Agile rogue with balanced attack and magic. Higher chance to obtain treasures.",
		IconAssetId = "rbxassetid://0", -- Replace with actual Asset ID
		BaseStats = {
			DEF = 100, -- Changed from MaxHP to DEF
			MaxMP = 60,
			ATK = 75,
			MAGIC = 30
		},
		Growth = {
			DEF = 7,   -- Changed from MaxHP to DEF
			MaxMP = 6,   -- 6% increase per level
			ATK = 7,     -- 7% increase per level
			MAGIC = 4    -- 4% increase per level
		},
		NextClass = "Assassin",
		UpgradeCondition = { Type = "Level", Value = 10 }
	},

	-- ===== Warrior Upgrade Classes =====
	Knight = {
		DisplayName = "Knight",
		Description = "Honorable warrior with improved defense and team protection abilities.",
		IconAssetId = "rbxassetid://0", -- Replace with actual Asset ID
		BaseStats = {
			DEF = 180, -- Changed from MaxHP to DEF
			MaxMP = 65,
			ATK = 120,
			MAGIC = 15
		},
		Growth = {
			DEF = 12,  -- Changed from MaxHP to DEF
			MaxMP = 6,   -- 6% increase per level
			ATK = 9,     -- 9% increase per level
			MAGIC = 3    -- 3% increase per level
		},
		NextClass = "Paladin",
		UpgradeCondition = { Type = "Quest", Value = "ProveYourValor" }
	},

	Paladin = {
		DisplayName = "Paladin",
		Description = "Holy knight combining combat prowess with support magic and protection.",
		IconAssetId = "rbxassetid://0", -- Replace with actual Asset ID
		BaseStats = {
			DEF = 250, -- Changed from MaxHP to DEF
			MaxMP = 100,
			ATK = 150,
			MAGIC = 50
		},
		Growth = {
			DEF = 15,  -- Changed from MaxHP to DEF
			MaxMP = 8,   -- 8% increase per level
			ATK = 12,    -- 12% increase per level
			MAGIC = 5    -- 5% increase per level
		},
		NextClass = nil, -- Highest class in this path
		UpgradeCondition = nil
	},

	-- ===== Mage Upgrade Classes =====
	Wizard = {
		DisplayName = "Wizard",
		Description = "Elemental magic expert with higher destructive power and more complex spells.",
		IconAssetId = "rbxassetid://0", -- Replace with actual Asset ID
		BaseStats = {
			DEF = 110, -- Changed from MaxHP to DEF
			MaxMP = 180,
			ATK = 35,
			MAGIC = 130
		},
		Growth = {
			DEF = 6,   -- Changed from MaxHP to DEF
			MaxMP = 12,  -- 12% increase per level
			ATK = 4,     -- 4% increase per level
			MAGIC = 11   -- 11% increase per level
		},
		NextClass = "Archmage",
		UpgradeCondition = { Type = "Item", Value = "AncientGrimoire" }
	},

	Archmage = {
		DisplayName = "Archmage",
		Description = "Master of the highest magical arts, wielding immense power to reshape the battlefield.",
		IconAssetId = "rbxassetid://0", -- Replace with actual Asset ID
		BaseStats = {
			DEF = 140, -- Changed from MaxHP to DEF
			MaxMP = 250,
			ATK = 45,
			MAGIC = 180
		},
		Growth = {
			DEF = 7,   -- Changed from MaxHP to DEF
			MaxMP = 15,  -- 15% increase per level
			ATK = 5,     -- 5% increase per level
			MAGIC = 14   -- 14% increase per level
		},
		NextClass = nil, -- Highest class in this path
		UpgradeCondition = nil
	},

	-- ===== Thief Upgrade Classes =====
	Assassin = {
		DisplayName = "Assassin",
		Description = "Stealth expert focusing on critical strikes and shadow movement.",
		IconAssetId = "rbxassetid://0", -- Replace with actual Asset ID
		BaseStats = {
			DEF = 130, -- Changed from MaxHP to DEF
			MaxMP = 80,
			ATK = 110,
			MAGIC = 40
		},
		Growth = {
			DEF = 8,   -- Changed from MaxHP to DEF
			MaxMP = 7,   -- 7% increase per level
			ATK = 10,    -- 10% increase per level
			MAGIC = 5    -- 5% increase per level
		},
		NextClass = "ShadowMaster",
		UpgradeCondition = { Type = "Skill", Value = "MasterStealth" }
	},

	ShadowMaster = {
		DisplayName = "Shadow Master",
		Description = "Ultimate shadow manipulator using stealth and unpredictable attacks.",
		IconAssetId = "rbxassetid://0", -- Replace with actual Asset ID
		BaseStats = {
			DEF = 160, -- Changed from MaxHP to DEF
			MaxMP = 100,
			ATK = 140,
			MAGIC = 55
		},
		Growth = {
			DEF = 9,   -- Changed from MaxHP to DEF
			MaxMP = 8,   -- 8% increase per level
			ATK = 12,    -- 12% increase per level
			MAGIC = 6    -- 6% increase per level
		},
		NextClass = nil, -- Highest class in this path
		UpgradeCondition = nil
	}
}

-- Default stats fallback for error handling
ClassData.DefaultStats = {
	DEF = 100, -- Changed from MaxHP to DEF
	MaxMP = 50,
	ATK = 10,
	MAGIC = 10
}

---------------------------
-- Helper Functions
---------------------------

-- Get class information
function ClassData:GetClassInfo(className)
	if not className or className == "" then
		warn("[ClassData] Warning: Attempted to get info for nil or empty className")
		return nil
	end

	local classInfo = self.Classes[className]
	if not classInfo then
		warn("[ClassData] Warning: Class not found: " .. tostring(className))
	end

	return classInfo
end

-- Get base stats for a class at level 1
function ClassData:GetBaseStats(className)
	local info = self:GetClassInfo(className)
	if not info or not info.BaseStats then
		warn("[ClassData] No BaseStats found for class: " .. tostring(className))
		return self.DefaultStats
	end
	return info.BaseStats
end

-- Calculate stats for a class at a specific level
function ClassData:CalculateStatsAtLevel(className, level)
	level = level or 1
	if level < 1 then level = 1 end

	local info = self:GetClassInfo(className)
	if not info then return self.DefaultStats end

	local baseStats = info.BaseStats
	local growth = info.Growth

	if not baseStats or not growth then
		return self.DefaultStats
	end

	local stats = {}
	for stat, baseValue in pairs(baseStats) do
		local growthRate = growth[stat] or 0
		stats[stat] = math.floor(baseValue * (1 + (growthRate/100) * (level-1)))
	end

	-- Calculate MaxHP based on DEF (1 DEF = 1 MaxHP)
	stats.MaxHP = stats.DEF

	return stats
end

-- Get next class in upgrade path
function ClassData:GetNextClass(className)
	local info = self:GetClassInfo(className)
	return info and info.NextClass
end

-- Get upgrade condition for a class
function ClassData:GetUpgradeCondition(className)
	local info = self:GetClassInfo(className)
	return info and info.UpgradeCondition
end

-- Get all starter classes
function ClassData:GetStarterClasses()
	return {"Warrior", "Thief", "Mage"}
end

-- Check if a class is a starter class
function ClassData:IsStarterClass(className)
	local starterClasses = self:GetStarterClasses()
	for _, class in ipairs(starterClasses) do
		if class == className then
			return true
		end
	end
	return false
end

-- Get all available classes
function ClassData:GetAllClasses()
	local classes = {}
	for className, _ in pairs(self.Classes) do
		table.insert(classes, className)
	end
	return classes
end

return ClassData
