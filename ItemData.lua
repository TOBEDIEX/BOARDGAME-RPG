-- ItemData.lua
-- Complete item data for the game (Updated version)
-- Version: 2.1.0 - Added Crystal Movement Items

-- Constants
local ITEM_TYPES = {
	GENERAL = 1,    -- General items
	EQUIPMENT = 2,  -- Weapons and armor
	SKILL = 3,      -- Skill books
	SPECIAL = 4     -- Special/quest items
}

local EQUIPMENT_SLOTS = {
	WEAPON = 1,
	HELMET = 2,
	ARMOR = 3,
	GLOVES = 4,
	BOOTS = 5,
	ACCESSORY = 6
}

local ItemData = {}

-- Function for using items (will be defined by InventoryService)
ItemData.UseHandlers = ItemData.UseHandlers or {}

-- Add Defense Boost items
ItemData.Items = {
	-- Test item
	test_item = {
		id = "test_item",
		name = "Test Item",
		description = "This is a test item for inventory system.",
		type = ITEM_TYPES.GENERAL,
		rarity = 1,
		stackable = true,
		maxStack = 99,
		sellPrice = 10,
		buyPrice = 20,
		usable = true,
		consumable = true,
		iconId = "rbxassetid://6675226918",
		stats = {
			hp = 50
		}
	},

	-- Dice bonus +1
	dice_bonus_1 = {
		id = "dice_bonus_1",
		name = "BonusDice +1",
		description = "Add your dice 1",
		type = ITEM_TYPES.GENERAL,
		rarity = 2,
		stackable = true,
		maxStack = 5,
		sellPrice = 100,
		buyPrice = 300,
		usable = true,
		consumable = true,
		iconId = "rbxassetid://122493284803076", -- Dice image
		stats = {
			diceRollBonus = 1
		}
	},

	-- Dice bonus +2
	dice_bonus_2 = {
		id = "dice_bonus_2",
		name = "BonusDice +2",
		description = "Add your Dice 2",
		type = ITEM_TYPES.GENERAL,
		rarity = 3,
		stackable = true,
		maxStack = 3,
		sellPrice = 250,
		buyPrice = 600,
		usable = true,
		consumable = true,
		iconId = "rbxassetid://106756897158809", -- Dice image
		stats = {
			diceRollBonus = 2
		}
	},

	-- Health potion
	health_potion = {
		id = "health_potion",
		name = "Health Potion",
		description = "Restores 50 HP",
		type = ITEM_TYPES.GENERAL,
		rarity = 1,
		stackable = true,
		maxStack = 10,
		sellPrice = 50,
		buyPrice = 150,
		usable = true,
		consumable = true,
		iconId = "rbxassetid://7060145106", -- Potion image
		stats = {
			hp = 50
		}
	},

	-- Mana potion
	mana_potion = {
		id = "mana_potion",
		name = "Mana Potion",
		description = "Restores 30 MP",
		type = ITEM_TYPES.GENERAL,
		rarity = 1,
		stackable = true,
		maxStack = 10,
		sellPrice = 60,
		buyPrice = 180,
		usable = true,
		consumable = true,
		iconId = "rbxassetid://7060145299", -- Potion image
		stats = {
			mp = 30
		}
	},

	-- Defense scroll
	defense_scroll = {
		id = "defense_scroll",
		name = "Defense Scroll",
		description = "Permanently increases DEF by +3",
		type = ITEM_TYPES.GENERAL,
		rarity = 2,
		stackable = true,
		maxStack = 5,
		sellPrice = 200,
		buyPrice = 500,
		usable = true,
		consumable = true,
		iconId = "rbxassetid://7060146509", -- Scroll image
		stats = {
			defensePermanent = 3
		}
	},

	-- Attack scroll
	attack_scroll = {
		id = "attack_scroll",
		name = "Attack Scroll",
		description = "Permanently increases ATK by +3",
		type = ITEM_TYPES.GENERAL,
		rarity = 2,
		stackable = true,
		maxStack = 5,
		sellPrice = 200,
		buyPrice = 500,
		usable = true,
		consumable = true,
		iconId = "rbxassetid://7060146202", -- Scroll image
		stats = {
			attackPermanent = 3
		}
	},

	-- Magic scroll
	magic_scroll = {
		id = "magic_scroll",
		name = "Magic Scroll",
		description = "Permanently increases MAGIC by +3",
		type = ITEM_TYPES.GENERAL,
		rarity = 2,
		stackable = true,
		maxStack = 5,
		sellPrice = 200,
		buyPrice = 500,
		usable = true,
		consumable = true,
		iconId = "rbxassetid://7060146799", -- Scroll image
		stats = {
			magicPermanent = 3
		}
	},
	
	-- NEW: Crystal that allows moving exactly 1 space
	crystal_1 = {
		id = "crystal_1",
		name = "Movement Crystal (1)",
		description = "Allows you to move exactly 1 space instead of rolling the dice.",
		type = ITEM_TYPES.GENERAL,
		rarity = 1,
		stackable = true,
		maxStack = 5,
		sellPrice = 100,
		buyPrice = 250,
		usable = true,
		consumable = true,
		iconId = "rbxassetid://7060876128", -- Replace with appropriate crystal icon
		stats = {
			fixedMovement = 1
		}
	},

	-- NEW: Crystal that allows moving exactly 2 spaces
	crystal_2 = {
		id = "crystal_2",
		name = "Movement Crystal (2)",
		description = "Allows you to move exactly 2 spaces instead of rolling the dice.",
		type = ITEM_TYPES.GENERAL,
		rarity = 2,
		stackable = true,
		maxStack = 5,
		sellPrice = 150,
		buyPrice = 350,
		usable = true,
		consumable = true,
		iconId = "rbxassetid://7060876235", -- Replace with appropriate crystal icon
		stats = {
			fixedMovement = 2
		}
	},

	-- NEW: Crystal that allows moving exactly 3 spaces
	crystal_3 = {
		id = "crystal_3",
		name = "Movement Crystal (3)",
		description = "Allows you to move exactly 3 spaces instead of rolling the dice.",
		type = ITEM_TYPES.GENERAL,
		rarity = 2,
		stackable = true,
		maxStack = 5,
		sellPrice = 200,
		buyPrice = 450,
		usable = true,
		consumable = true,
		iconId = "rbxassetid://7060876342", -- Replace with appropriate crystal icon
		stats = {
			fixedMovement = 3
		}
	},

	-- NEW: Crystal that allows moving exactly 4 spaces
	crystal_4 = {
		id = "crystal_4",
		name = "Movement Crystal (4)",
		description = "Allows you to move exactly 4 spaces instead of rolling the dice.",
		type = ITEM_TYPES.GENERAL,
		rarity = 3,
		stackable = true,
		maxStack = 5,
		sellPrice = 250,
		buyPrice = 550,
		usable = true,
		consumable = true,
		iconId = "rbxassetid://7060876458", -- Replace with appropriate crystal icon
		stats = {
			fixedMovement = 4
		}
	},

	-- NEW: Crystal that allows moving exactly 5 spaces
	crystal_5 = {
		id = "crystal_5",
		name = "Movement Crystal (5)",
		description = "Allows you to move exactly 5 spaces instead of rolling the dice.",
		type = ITEM_TYPES.GENERAL,
		rarity = 3,
		stackable = true,
		maxStack = 5,
		sellPrice = 300,
		buyPrice = 650,
		usable = true,
		consumable = true,
		iconId = "rbxassetid://7060876575", -- Replace with appropriate crystal icon
		stats = {
			fixedMovement = 5
		}
	},

	-- NEW: Crystal that allows moving exactly 6 spaces
	crystal_6 = {
		id = "crystal_6",
		name = "Movement Crystal (6)",
		description = "Allows you to move exactly 6 spaces instead of rolling the dice.",
		type = ITEM_TYPES.GENERAL,
		rarity = 4,
		stackable = true,
		maxStack = 5,
		sellPrice = 350,
		buyPrice = 750,
		usable = true,
		consumable = true,
		iconId = "rbxassetid://7060876684", -- Replace with appropriate crystal icon
		stats = {
			fixedMovement = 6
		}
	},
}

-- Equipment with DEF support
ItemData.Equipment = {
	-- Test equipment
	test_equipment = {
		id = "test_equipment",
		name = "Test Equipment",
		description = "This is a test equipment for inventory system.",
		type = ITEM_TYPES.EQUIPMENT,
		subType = EQUIPMENT_SLOTS.WEAPON,
		rarity = 2,
		stackable = false,
		maxStack = 1,
		sellPrice = 100,
		buyPrice = 300,
		usable = false,
		iconId = "rbxassetid://6675226140",
		stats = {
			attack = 10,
			defense = 5
		}
	},

	-- Warrior starting weapon
	bronze_sword = {
		id = "bronze_sword",
		name = "Bronze Sword",
		description = "Basic weapon for warriors",
		type = ITEM_TYPES.EQUIPMENT,
		subType = EQUIPMENT_SLOTS.WEAPON,
		rarity = 1,
		stackable = false,
		maxStack = 1,
		sellPrice = 50,
		buyPrice = 150,
		usable = false,
		iconId = "rbxassetid://6675226240",
		classRestriction = "Warrior",
		stats = {
			attack = 15,
			defense = 3 -- Added DEF which also increases MaxHP
		}
	},

	-- Mage starting weapon
	apprentice_staff = {
		id = "apprentice_staff",
		name = "Apprentice Staff",
		description = "Staff for beginner magic users",
		type = ITEM_TYPES.EQUIPMENT,
		subType = EQUIPMENT_SLOTS.WEAPON,
		rarity = 1,
		stackable = false,
		maxStack = 1,
		sellPrice = 50,
		buyPrice = 150,
		usable = false,
		iconId = "rbxassetid://6675226399",
		classRestriction = "Mage",
		stats = {
			attack = 5,
			magic = 15,
			defense = 2 -- Added DEF which also increases MaxHP
		}
	},

	-- Thief starting weapon
	bronze_dagger = {
		id = "bronze_dagger",
		name = "Bronze Dagger",
		description = "Light dagger for quick attacks but low damage",
		type = ITEM_TYPES.EQUIPMENT,
		subType = EQUIPMENT_SLOTS.WEAPON,
		rarity = 1,
		stackable = false,
		maxStack = 1,
		sellPrice = 50,
		buyPrice = 150,
		usable = false,
		iconId = "rbxassetid://6675226485",
		classRestriction = "Thief",
		stats = {
			attack = 10,
			magic = 5,
			defense = 1 -- Added DEF which also increases MaxHP
		}
	},

	-- Starting armor
	leather_armor = {
		id = "leather_armor",
		name = "Leather Armor",
		description = "Light leather armor providing minimal protection",
		type = ITEM_TYPES.EQUIPMENT,
		subType = EQUIPMENT_SLOTS.ARMOR,
		rarity = 1,
		stackable = false,
		maxStack = 1,
		sellPrice = 40,
		buyPrice = 120,
		usable = false,
		iconId = "rbxassetid://6675226750",
		stats = {
			maxHp = 10 
		}
	},

	-- Starting helmet
	leather_helmet = {
		id = "leather_helmet",
		name = "Leather Helmet",
		description = "Light leather helmet providing minimal head protection",
		type = ITEM_TYPES.EQUIPMENT,
		subType = EQUIPMENT_SLOTS.HELMET,
		rarity = 1,
		stackable = false,
		maxStack = 1,
		sellPrice = 30,
		buyPrice = 90,
		usable = false,
		iconId = "rbxassetid://6675226899",
		stats = {
			defense = 5 -- Added DEF which also increases MaxHP
		}
	},

	-- Starting boots
	leather_boots = {
		id = "leather_boots",
		name = "Leather Boots",
		description = "Light leather boots increasing mobility",
		type = ITEM_TYPES.EQUIPMENT,
		subType = EQUIPMENT_SLOTS.BOOTS,
		rarity = 1,
		stackable = false,
		maxStack = 1,
		sellPrice = 25,
		buyPrice = 75,
		usable = false,
		iconId = "rbxassetid://6675226910",
		stats = {
			defense = 3 -- Added DEF which also increases MaxHP
		}
	}
}

-- Item pool for Item Tiles
ItemData.ItemTilePool = {
	-- Sorted by drop frequency (approximate percentages)
	{id = "health_potion", weight = 35},  -- 35%
	{id = "mana_potion", weight = 25},    -- 25%  
	{id = "dice_bonus_1", weight = 15},   -- 15%
	{id = "crystal_1", weight = 8},       -- 8% (NEW)
	{id = "crystal_2", weight = 6},       -- 6% (NEW)
	{id = "crystal_3", weight = 4},       -- 4% (NEW)
	{id = "defense_scroll", weight = 3},  -- 3%
	{id = "attack_scroll", weight = 2},   -- 2%
	{id = "crystal_4", weight = 1},       -- 1% (NEW)
	{id = "crystal_5", weight = 0.5},     -- 0.5% (NEW)
	{id = "magic_scroll", weight = 0.3},  -- 0.3%
	{id = "dice_bonus_2", weight = 0.1},  -- 0.1%
	{id = "crystal_6", weight = 0.1}      -- 0.1% (NEW)
}

-- Find item by ID
function ItemData.GetItemById(itemId)
	-- Check general items
	if ItemData.Items[itemId] then
		return ItemData.Items[itemId]
	end

	-- Check equipment
	if ItemData.Equipment[itemId] then
		return ItemData.Equipment[itemId]
	end

	return nil
end

-- Additional functions that may be needed
function ItemData.GetItemsByType(itemType)
	local result = {}

	-- Check general items
	for id, item in pairs(ItemData.Items) do
		if item.type == itemType then
			table.insert(result, item)
		end
	end

	-- Check equipment
	for id, item in pairs(ItemData.Equipment) do
		if item.type == itemType then
			table.insert(result, item)
		end
	end

	return result
end

-- Get a random item from the ItemTilePool
function ItemData.GetRandomItemFromPool()
	local totalWeight = 0
	for _, itemInfo in ipairs(ItemData.ItemTilePool) do
		totalWeight = totalWeight + itemInfo.weight
	end

	local randomValue = math.random(1, totalWeight * 100) / 100 -- Support for decimal weights
	local currentWeight = 0

	for _, itemInfo in ipairs(ItemData.ItemTilePool) do
		currentWeight = currentWeight + itemInfo.weight
		if randomValue <= currentWeight then
			return ItemData.GetItemById(itemInfo.id)
		end
	end

	-- Fallback (shouldn't happen)
	return ItemData.GetItemById("health_potion")
end

-- Export constants
ItemData.ITEM_TYPES = ITEM_TYPES
ItemData.EQUIPMENT_SLOTS = EQUIPMENT_SLOTS

-- ====== ITEM USE HANDLERS ======

-- Lucky Dice +1
ItemData.UseHandlers.dice_bonus_1 = function(player, itemData)
	-- Check if it's the player's turn
	local turnSystem = _G.GameManager and _G.GameManager.turnSystem
	if not turnSystem then
		return false, "Turn system not available"
	end

	if turnSystem:GetCurrentPlayerTurn() ~= player.UserId then
		return false, "You can only use this item during your turn"
	end

	-- Notify the client about the dice bonus
	local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
	local inventoryRemotes = remotes:WaitForChild("InventoryRemotes")
	local diceBonusEvent = inventoryRemotes:FindFirstChild("DiceBonus")

	if not diceBonusEvent then
		diceBonusEvent = Instance.new("RemoteEvent")
		diceBonusEvent.Name = "DiceBonus"
		diceBonusEvent.Parent = inventoryRemotes
	end

	-- Send bonus to client
	diceBonusEvent:FireClient(player, 1)

	-- Show notification message
	local message = "🎲 Added +1 dice bonus for your next roll!"

	-- Play sound effect
	pcall(function()
		local soundService = game:GetService("SoundService")
		local sound = soundService:FindFirstChild("ItemUse") or Instance.new("Sound", soundService)
		sound.Name = "ItemUse"
		sound.SoundId = "rbxassetid://6895079853"
		sound.Volume = 0.7
		sound:Play()
	end)

	return true, message
end

-- Magical Dice +2
ItemData.UseHandlers.dice_bonus_2 = function(player, itemData)
	-- Check if it's the player's turn
	local turnSystem = _G.GameManager and _G.GameManager.turnSystem
	if not turnSystem then
		return false, "Turn system not available"
	end

	if turnSystem:GetCurrentPlayerTurn() ~= player.UserId then
		return false, "You can only use this item during your turn"
	end

	-- Notify the client about the dice bonus
	local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
	local inventoryRemotes = remotes:WaitForChild("InventoryRemotes")
	local diceBonusEvent = inventoryRemotes:FindFirstChild("DiceBonus")

	if not diceBonusEvent then
		diceBonusEvent = Instance.new("RemoteEvent")
		diceBonusEvent.Name = "DiceBonus"
		diceBonusEvent.Parent = inventoryRemotes
	end

	-- Send bonus to client
	diceBonusEvent:FireClient(player, 2)

	-- Show notification message
	local message = "🎲✨ Added +2 dice bonus for your next roll!"

	-- Play sound effect (special sound for +2)
	pcall(function()
		local soundService = game:GetService("SoundService")
		local sound = soundService:FindFirstChild("MagicItemUse") or Instance.new("Sound", soundService)
		sound.Name = "MagicItemUse"
		sound.SoundId = "rbxassetid://6026984224"
		sound.Volume = 0.7
		sound:Play()
	end)

	return true, message
end

-- Defense Scroll (permanent DEF boost)
ItemData.UseHandlers.defense_scroll = function(player, itemData)
	-- Check if ClassSystem is available
	local gameManager = _G.GameManager
	local playerManager = gameManager and gameManager.playerManager

	if not playerManager then
		return false, "System not ready"
	end

	-- Get player data
	local playerData = playerManager:GetPlayerData(player)
	if not playerData then
		return false, "Player data not found"
	end

	-- Add permanent Defense boost
	local defBonus = itemData.stats.defensePermanent or 3

	-- Update defense in player data
	playerData.stats.defense = playerData.stats.defense + defBonus
	playerData.stats.maxHp = playerData.stats.defense  -- MaxHP = Defense

	-- Update baseStats too
	if playerData.baseStats then
		playerData.baseStats.defense = playerData.baseStats.defense + defBonus
		playerData.baseStats.maxHp = playerData.baseStats.defense
	end

	-- Increase current HP by the same amount
	playerData.stats.hp = playerData.stats.hp + defBonus

	-- Update Humanoid if available
	if player.Character and player.Character:FindFirstChild("Humanoid") then
		local humanoid = player.Character:FindFirstChild("Humanoid")
		humanoid.MaxHealth = playerData.stats.maxHp
		humanoid.Health = humanoid.Health + defBonus
	end

	-- Sync player stats to client
	playerManager:SyncPlayerStats(player)

	-- Show notification message
	local message = "🛡️ Permanently increased Defense (DEF) by +" .. defBonus .. " (Max HP increased too)"

	-- Play stat boost sound
	pcall(function()
		local soundService = game:GetService("SoundService")
		local sound = soundService:FindFirstChild("StatUpSound") or Instance.new("Sound", soundService)
		sound.Name = "StatUpSound"
		sound.SoundId = "rbxassetid://9114835652"
		sound.Volume = 0.8
		sound:Play()
	end)

	return true, message
end

-- Attack Scroll (permanent ATK boost)
ItemData.UseHandlers.attack_scroll = function(player, itemData)
	-- Check if ClassSystem is available
	local gameManager = _G.GameManager
	local playerManager = gameManager and gameManager.playerManager

	if not playerManager then
		return false, "System not ready"
	end

	-- Get player data
	local playerData = playerManager:GetPlayerData(player)
	if not playerData then
		return false, "Player data not found"
	end

	-- Add permanent Attack boost
	local atkBonus = itemData.stats.attackPermanent or 3

	-- Update attack in player data
	playerData.stats.attack = playerData.stats.attack + atkBonus

	-- Update baseStats too
	if playerData.baseStats then
		playerData.baseStats.attack = playerData.baseStats.attack + atkBonus
	end

	-- Sync player stats to client
	playerManager:SyncPlayerStats(player)

	-- Show notification message
	local message = "⚔️ Permanently increased Attack (ATK) by +" .. atkBonus

	-- Play stat boost sound
	pcall(function()
		local soundService = game:GetService("SoundService")
		local sound = soundService:FindFirstChild("StatUpSound") or Instance.new("Sound", soundService)
		sound.Name = "StatUpSound"
		sound.SoundId = "rbxassetid://9114835652"
		sound.Volume = 0.8
		sound:Play()
	end)

	return true, message
end

-- Magic Scroll (permanent MAGIC boost)
ItemData.UseHandlers.magic_scroll = function(player, itemData)
	-- Check if ClassSystem is available
	local gameManager = _G.GameManager
	local playerManager = gameManager and gameManager.playerManager

	if not playerManager then
		return false, "System not ready"
	end

	-- Get player data
	local playerData = playerManager:GetPlayerData(player)
	if not playerData then
		return false, "Player data not found"
	end

	-- Add permanent Magic boost
	local magicBonus = itemData.stats.magicPermanent or 3

	-- Update magic in player data
	playerData.stats.magic = playerData.stats.magic + magicBonus

	-- Update baseStats too
	if playerData.baseStats then
		playerData.baseStats.magic = playerData.baseStats.magic + magicBonus
	end

	-- Sync player stats to client
	playerManager:SyncPlayerStats(player)

	-- Show notification message
	local message = "✨ Permanently increased Magic (MAGIC) by +" .. magicBonus

	-- Play stat boost sound
	pcall(function()
		local soundService = game:GetService("SoundService")
		local sound = soundService:FindFirstChild("StatUpSound") or Instance.new("Sound", soundService)
		sound.Name = "StatUpSound"
		sound.SoundId = "rbxassetid://9114835652"
		sound.Volume = 0.8
		sound:Play()
	end)

	return true, message
end

-- NEW: Common function for all movement crystals
local function handleCrystalUse(player, itemData)
    -- Check if it's the player's turn
    local gameManager = _G.GameManager
    local turnSystem = gameManager and gameManager.turnSystem
    
    if not turnSystem then
        return false, "Turn system not available"
    end
    
    if turnSystem:GetCurrentPlayerTurn() ~= player.UserId then
        return false, "You can only use this item during your turn"
    end
    
    -- Get the fixed movement value from the item's stats
    local fixedMovement = itemData.stats and itemData.stats.fixedMovement
    if not fixedMovement or fixedMovement < 1 or fixedMovement > 6 then
        return false, "Invalid movement value in crystal"
    end
    
    -- Get the necessary remotes
    local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
    local boardRemotes = remotes:WaitForChild("BoardRemotes")
    local rollDiceRemote = boardRemotes:WaitForChild("RollDice")
    
    -- Trigger movement with the fixed value directly
    -- This reuses the existing dice roll event but with our fixed value
    rollDiceRemote:FireClient(player, fixedMovement, true) -- true indicates this is a fixed movement (will skip animation)
    
    -- Play sound effect for crystal use
    pcall(function()
        local soundService = game:GetService("SoundService")
        local sound = soundService:FindFirstChild("CrystalUse") or Instance.new("Sound", soundService)
        sound.Name = "CrystalUse"
        sound.SoundId = "rbxassetid://6026984224" -- Crystal sound
        sound.Volume = 0.7
        sound:Play()
    end)
    
    -- Format message for UI
    local message = string.format("✨ Using Crystal to move exactly %d space%s!", 
                                fixedMovement, 
                                fixedMovement > 1 and "s" or "")
    
    return true, message
end

-- NEW: Specific handlers for each crystal
ItemData.UseHandlers.crystal_1 = function(player, itemData)
    return handleCrystalUse(player, itemData)
end

ItemData.UseHandlers.crystal_2 = function(player, itemData)
    return handleCrystalUse(player, itemData)
end

ItemData.UseHandlers.crystal_3 = function(player, itemData)
    return handleCrystalUse(player, itemData)
end

ItemData.UseHandlers.crystal_4 = function(player, itemData)
    return handleCrystalUse(player, itemData)
end

ItemData.UseHandlers.crystal_5 = function(player, itemData)
    return handleCrystalUse(player, itemData)
end

ItemData.UseHandlers.crystal_6 = function(player, itemData)
    return handleCrystalUse(player, itemData)
end

return ItemData
