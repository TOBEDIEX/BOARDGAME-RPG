-- InventoryService.server.lua
-- Server-side inventory management service
-- Location: ServerScriptService/Services/InventoryService.server.lua
-- Version: 1.0.9 (Heal player only on first equip of an item instance)

-- Services
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

-- Debug mode for detailed logging
local DEBUG_MODE = true

-- Helper function for logging
local function debugLog(message)
	if DEBUG_MODE then
		print("[InventoryService] " .. message)
	end
end

-- Load dependencies
local Modules = ServerStorage:WaitForChild("Modules")
local InventorySystem = require(Modules:WaitForChild("InventorySystem"))

-- Try to load ItemData module
local ItemData = nil
local SharedModules = ReplicatedStorage:WaitForChild("SharedModules")
local success, result = pcall(function()
	return require(SharedModules:WaitForChild("ItemData"))
end)

if success then
	ItemData = result
	debugLog("Successfully loaded ItemData module")
else
	warn("[InventoryService] Failed to load ItemData module: " .. tostring(result))
	ItemData = {
		ITEM_TYPES = InventorySystem.GetItemTypes(), EQUIPMENT_SLOTS = InventorySystem.GetEquipmentSlots(),
		Items = {}, Equipment = {},
		GetItemById = function(itemId) return ItemData.Items[itemId] or ItemData.Equipment[itemId] end,
		UseHandlers = {}
	}
end

-- Initialize remote events/functions
local function initializeRemotes()
	debugLog("Initializing remote events/functions...")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local inventoryRemotes = remotes:FindFirstChild("InventoryRemotes")
	if not inventoryRemotes then inventoryRemotes = Instance.new("Folder"); inventoryRemotes.Name = "InventoryRemotes"; inventoryRemotes.Parent = remotes end
	local useItemRemote = inventoryRemotes:FindFirstChild("UseItem")
	if useItemRemote and not useItemRemote:IsA("RemoteFunction") then warn("[InventoryService] Existing 'UseItem' is not a RemoteFunction. Replacing."); useItemRemote:Destroy(); useItemRemote = nil end
	if not useItemRemote then useItemRemote = Instance.new("RemoteFunction"); useItemRemote.Name = "UseItem"; useItemRemote.Parent = inventoryRemotes; debugLog("Created RemoteFunction: UseItem") end
	local remoteEvents = { "UpdateInventory", "AddItem", "RemoveItem", "EquipItem", "UnequipItem", "SortInventory", "InspectItem", "EquipmentSlotClicked", "EquipmentChanged", "DiceBonus" }
	for _, eventName in ipairs(remoteEvents) do if not inventoryRemotes:FindFirstChild(eventName) then local event = Instance.new("RemoteEvent"); event.Name = eventName; event.Parent = inventoryRemotes; debugLog("Created RemoteEvent: " .. eventName) end end
	return inventoryRemotes
end

-- Player inventory cache
local playerInventories = {}

-- Track item/bonus uses per turn
local playerDiceBonusUses = {}
local playerItemUsedThisTurn = {}

-- Get GameManager reference
local function getGameManager()
	local startTime = tick(); local attempts = 0; local maxAttempts = 20
	while not _G.GameManager and attempts < maxAttempts do wait(0.5); attempts = attempts + 1 end
	if not _G.GameManager then warn("[InventoryService] Failed to get GameManager after " .. maxAttempts .. " attempts.") end
	return _G.GameManager
end

-- Main service table
local InventoryService = {}

-- Initialize Player Inventory
function InventoryService.InitializePlayer(player)
	if playerInventories[player.UserId] then return playerInventories[player.UserId] end
	local inventory = InventorySystem.new()
	InventoryService.GiveStartingItems(player, inventory)
	playerInventories[player.UserId] = inventory
	InventoryService.SendInventoryToClient(player)
	return inventory
end

-- Give Starting Items based on class
function InventoryService.GiveStartingItems(player, inventory)
	local gameManager = getGameManager()
	local playerData = gameManager and gameManager.playerManager and gameManager.playerManager:GetPlayerData(player)
	local playerClass = playerData and playerData.class or "Unknown"
	debugLog("Giving starting items to " .. player.Name .. " (Class: " .. playerClass .. ")")
	if ItemData and ItemData.Items then
		if ItemData.Items.health_potion_small then inventory:AddItem(ItemData.Items.health_potion_small, 3); debugLog("Added 3x Small Health Potions") end
		if ItemData.Items.mana_potion_small then inventory:AddItem(ItemData.Items.mana_potion_small, 3); debugLog("Added 3x Small Mana Potions") end
		if ItemData.Items.dice_bonus_1 then inventory:AddItem(ItemData.Items.dice_bonus_1, 2); debugLog("Added 2x Lucky Dice +1") end
	end
	if ItemData and ItemData.Equipment then
		if playerClass == "Warrior" and ItemData.Equipment.bronze_sword then inventory:AddItem(ItemData.Equipment.bronze_sword); debugLog("Added Bronze Sword")
		elseif playerClass == "Mage" and ItemData.Equipment.apprentice_staff then inventory:AddItem(ItemData.Equipment.apprentice_staff); debugLog("Added Apprentice Staff")
		elseif playerClass == "Thief" and ItemData.Equipment.bronze_dagger then inventory:AddItem(ItemData.Equipment.bronze_dagger); debugLog("Added Bronze Dagger") end
		if ItemData.Equipment.leather_armor then inventory:AddItem(ItemData.Equipment.leather_armor); debugLog("Added Leather Armor") end
	end
	return true
end

-- Get Player Inventory (ensures initialization)
function InventoryService.GetPlayerInventory(player)
	if not playerInventories[player.UserId] then return InventoryService.InitializePlayer(player) end
	return playerInventories[player.UserId]
end

-- Send full inventory data to the client
function InventoryService.SendInventoryToClient(player)
	local inventory = InventoryService.GetPlayerInventory(player)
	if not inventory then return false end
	local clientData = { items = inventory:GetAllItems(), equippedItems = inventory:GetEquippedItems(), maxSize = inventory.maxSize }
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local inventoryRemotes = remotes:WaitForChild("InventoryRemotes")
	local updateEvent = inventoryRemotes:WaitForChild("UpdateInventory")
	updateEvent:FireClient(player, clientData)
	return true
end

-- Add an item to a player's inventory
function InventoryService.AddItemToPlayer(player, itemId, quantity)
	local inventory = InventoryService.GetPlayerInventory(player)
	if not inventory then return false, "Failed to get player inventory" end
	if not ItemData then warn("[InventoryService] ItemData module not loaded!"); return false, "Item data not available" end
	local itemData = ItemData.GetItemById(itemId)
	if not itemData then return false, "Item not found" end
	local success, message = inventory:AddItem(itemData, quantity)
	if success then InventoryService.SendInventoryToClient(player); debugLog("Added item " .. itemId .. " x" .. tostring(quantity) .. " to player " .. player.Name) end
	return success, message
end

-- Remove an item from a player's inventory using its unique inventory ID
function InventoryService.RemoveItemFromPlayer(player, inventoryId, quantity)
	local inventory = InventoryService.GetPlayerInventory(player)
	if not inventory then return false, "Failed to get player inventory" end
	local item = inventory:FindItemByInventoryId(inventoryId)
	local itemName = item and item.name or "Unknown Item"
	local success, message = inventory:RemoveItem(inventoryId, quantity)
	if success then InventoryService.SendInventoryToClient(player); debugLog("Removed item " .. itemName .. " from player " .. player.Name) end
	return success, message
end

-- Update player stats based on currently equipped items
function InventoryService.UpdatePlayerStats(player, equipmentStats)
	local gameManager = getGameManager()
	if not gameManager or not gameManager.playerManager then return false, "Player manager not available" end
	local playerData = gameManager.playerManager:GetPlayerData(player)
	if not playerData or not playerData.stats then return false, "Player data not found" end
	local baseStats = playerData.baseStats
	if not baseStats then debugLog("Creating new baseStats from current stats for " .. player.Name); baseStats = table.clone(playerData.stats); baseStats.defense = 0; playerData.baseStats = baseStats end
	local newStats = {}
	for stat, baseValue in pairs(baseStats) do newStats[stat] = baseValue + (equipmentStats[stat] or 0) end
	newStats.hp = math.min(playerData.stats.hp, newStats.maxHp)
	newStats.mp = math.min(playerData.stats.mp, newStats.maxMp)
	for stat, value in pairs(newStats) do playerData.stats[stat] = value end
	gameManager.playerManager:SyncPlayerStats(player)
	debugLog("Updated stats with equipment bonuses for " .. player.Name)
	return true
end

-- Equip an item for a player
-- *** MODIFIED HEAL LOGIC TO CHECK FLAG ***
function InventoryService.EquipItemForPlayer(player, inventoryId)
	local inventory = InventoryService.GetPlayerInventory(player)
	if not inventory then return false, "Failed to get player inventory" end

	-- Find the item *before* equipping to check its state
	local item = inventory:FindItemByInventoryId(inventoryId)
	if not item then return false, "Item not found" end

	-- Check if the item had been equipped before (using our custom flag)
	local itemHadBeenEquipped = item._hasBeenEquipped == true -- Check if flag is explicitly true

	-- Check if the item is actually equippable
	if not item.equippable and item.type ~= InventorySystem.GetItemTypes().EQUIPMENT then
		return false, "Item cannot be equipped"
	end

	-- Check class restriction
	if item.classRestriction then
		local gameManager = getGameManager()
		local playerClass = gameManager and gameManager.classSystem and gameManager.classSystem:GetPlayerClass(player)
		if not playerClass or playerClass ~= item.classRestriction then
			return false, "This item is restricted to " .. item.classRestriction .. " class"
		end
	end

	-- Attempt to equip the item using InventorySystem
	local success, message = inventory:EquipItem(inventoryId)

	if success then
		debugLog(player.Name .. " equipped " .. item.name)

		-- Recalculate stats with the newly equipped item
		local equipmentStats = inventory:CalculateEquipmentStats()
		InventoryService.UpdatePlayerStats(player, equipmentStats) -- Updates stats & syncs

		-- *** MODIFIED HEAL LOGIC: Check _hasBeenEquipped flag ***
		if not itemHadBeenEquipped then -- Heal only if it wasn't equipped before
			local gameManager = getGameManager()
			if gameManager and gameManager.playerManager then
				local playerData = gameManager.playerManager:GetPlayerData(player)
				if playerData and playerData.stats then
					if playerData.stats.hp < playerData.stats.maxHp then
						print(string.format("[InventoryService] Healing %s to full HP (%d) after equipping %s for the first time.", player.Name, playerData.stats.maxHp, item.name))
						gameManager.playerManager:UpdatePlayerHP(player, playerData.stats.maxHp)
					else
						print(string.format("[InventoryService] Player %s already at full HP after first equip of %s.", player.Name, item.name))
					end
					-- Set the flag *after* attempting the heal for the first time
					-- IMPORTANT: This assumes 'item' variable still references the correct item table in the inventory
					item._hasBeenEquipped = true
					print(string.format("[InventoryService] Marked item %s (InvID: %s) as equipped for the first time.", item.name, inventoryId))
				else
					warn("[InventoryService] Could not get playerData or stats to heal player after first equip.")
				end
			else
				warn("[InventoryService] PlayerManager not found, cannot heal player after first equip.")
			end
		else
			-- Item had been equipped before, skip heal
			print(string.format("[InventoryService] Skipping heal for %s. Item %s (InvID: %s) has been equipped before.", player.Name, item.name, inventoryId))
		end
		-- *** END OF MODIFIED HEAL LOGIC ***

		-- Update the client's inventory UI
		InventoryService.SendInventoryToClient(player)

		-- Notify the client specifically about the equipment change
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local inventoryRemotes = remotes:WaitForChild("InventoryRemotes")
		local equipmentChangedEvent = inventoryRemotes:WaitForChild("EquipmentChanged")
		equipmentChangedEvent:FireClient(player, item.subType, item)

	end
	return success, message
end


-- Unequip an item from a specific slot for a player
function InventoryService.UnequipItemForPlayer(player, slotType)
	local inventory = InventoryService.GetPlayerInventory(player)
	if not inventory then return false, "Failed to get player inventory" end
	local currentItem = inventory:GetEquippedItemInSlot(slotType)
	if not currentItem then return false, "No item equipped in this slot" end
	local success, message = inventory:UnequipItem(slotType)
	if success then
		debugLog(player.Name .. " unequipped " .. currentItem.name)
		local equipmentStats = inventory:CalculateEquipmentStats()
		InventoryService.UpdatePlayerStats(player, equipmentStats)
		InventoryService.SendInventoryToClient(player)
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local inventoryRemotes = remotes:WaitForChild("InventoryRemotes")
		local equipmentChangedEvent = inventoryRemotes:WaitForChild("EquipmentChanged")
		equipmentChangedEvent:FireClient(player, slotType, nil)
		-- No heal logic on unequip
	end
	return success, message
end

-- Use an item for a player (Invoked by client via RemoteFunction)
function InventoryService.UseItemForPlayer(player, inventoryId)
	local inventory = InventoryService.GetPlayerInventory(player)
	if not inventory then return false, "Failed to get player inventory" end
	local item = inventory:FindItemByInventoryId(inventoryId)
	if not item then return false, "Item not found" end
	local itemName = item.name or "Unknown Item"; local itemId = item.id
	if not item.usable then debugLog(itemName .. " cannot be used (not usable)."); return false, "Item cannot be used" end

	local gameManager = getGameManager()
	local turnSystem = gameManager and gameManager.turnSystem
	if not turnSystem then warn("[InventoryService] Turn system not available for usage checks.")
	else
		local itemUsedFlag = playerItemUsedThisTurn[player.UserId]
		debugLog(string.format("Checking item use limit for %s attempting to use '%s'. Flag value: %s", player.Name, itemName, tostring(itemUsedFlag)))
		if itemUsedFlag then debugLog(player.Name .. " tried item " .. itemName .. " but already used item this turn. Blocking use."); return false, "You can only use one item per turn"
		else debugLog("Item use limit check passed for " .. player.Name) end

		if turnSystem:GetCurrentPlayerTurn() ~= player.UserId then debugLog(player.Name .. " tried item " .. itemName .. " outside turn."); return false, "You can only use this item during your turn" end

		local isDiceBonus = item.stats and item.stats.diceBonus and item.stats.diceBonus > 0
		if isDiceBonus then if playerDiceBonusUses[player.UserId] then debugLog(player.Name .. " already used dice bonus this turn."); return false, "You already used a dice bonus item this turn" end end
	end

	local useFunction
	if ItemData and ItemData.UseHandlers and ItemData.UseHandlers[item.id] then useFunction = ItemData.UseHandlers[item.id]; debugLog("Using custom UseHandler for item: " .. item.id)
	else
		useFunction = function(playerArg, itemDataArg)
			debugLog("Using default use function for item: " .. itemDataArg.id); local gm = getGameManager(); local changed = false; local appliedBonus = 0
			if itemDataArg.stats and gm and gm.playerManager then
				local pData = gm.playerManager:GetPlayerData(playerArg); if pData and pData.stats then
					for statName, statValue in pairs(itemDataArg.stats) do
						if statName == "diceBonus" then if gm.diceBonusService then gm.diceBonusService.SetPlayerDiceBonus(playerArg, statValue); appliedBonus = statValue; changed = true else warn("[InventoryService] DiceBonusService not found!") end
						elseif pData.stats[statName] ~= nil then
							if statName == "hp" then local current = pData.stats.hp; local maxV = pData.stats.maxHp; local newV = math.min(current + statValue, maxV); if newV ~= current then gm.playerManager:UpdatePlayerHP(playerArg, newV); changed = true end
							elseif statName == "mp" then local current = pData.stats.mp; local maxV = pData.stats.maxMp; local newV = math.min(current + statValue, maxV); if newV ~= current then gm.playerManager:UpdatePlayerMP(playerArg, newV); changed = true end
							else debugLog("Ignoring direct stat change for '" .. statName .. "' in default item use.") end
						end
					end
					if appliedBonus > 0 then playerDiceBonusUses[playerArg.UserId] = { itemId = itemDataArg.id, bonusAmount = appliedBonus, timestamp = os.time() }; debugLog(playerArg.Name .. " used dice bonus +" .. appliedBonus) end
					if changed and appliedBonus == 0 then debugLog("Stats changed for " .. playerArg.Name) end
				else warn("[InventoryService] Could not get PlayerData/Stats for " .. playerArg.Name) end
			elseif itemDataArg.type == InventorySystem.GetItemTypes().SKILL then
				local skillId = itemDataArg.skillId; if skillId and gm and gm.skillSystem then debugLog("Attempting to learn skill: " .. tostring(skillId)); local successLearn, learnMsg = gm.skillSystem:LearnSkill(playerArg, skillId); if successLearn then return true, learnMsg or "Learned skill: " .. (itemDataArg.skillName or "?") else return false, learnMsg or "Could not learn skill" end
				else warn("[InventoryService] SkillSystem/skillId missing for: " .. itemDataArg.id); return false, "Cannot learn skill" end
			end
			return true, "Used " .. itemDataArg.name
		end
	end

	local successCall, messageOrError = pcall(useFunction, player, item)
	if not successCall then warn("Error executing use function for item " .. itemName .. ": " .. tostring(messageOrError)); return false, "Error using item" end
	if type(messageOrError) == "boolean" and not messageOrError then local _, failMessage = messageOrError; return false, failMessage or "Could not use item" end

	playerItemUsedThisTurn[player.UserId] = true
	debugLog(player.Name .. " marked as having used an item this turn.")

	debugLog("Checking if item '" .. itemName .. "' is consumable. Value: " .. tostring(item.consumable))
	if item.consumable then
		debugLog("Item " .. itemName .. " is consumable, removing 1.")
		local removeSuccess, removeMessage = InventoryService.RemoveItemFromPlayer(player, inventoryId, 1)
		if not removeSuccess then warn("[InventoryService] Failed to remove consumable item " .. itemName .. " after use:", removeMessage) end
	end

	local useMessage = type(messageOrError) == "string" and messageOrError or "Item used successfully"
	debugLog(player.Name .. " successfully used " .. itemName .. ". Message: " .. tostring(useMessage))
	return true, useMessage
end


-- Reset usage flags for a player (Called by TurnSystem at turn start)
function InventoryService.ResetTurnFlagsForPlayer(player)
	if not player then return false end
	local playerId = typeof(player) == "number" and player or player.UserId
	debugLog(string.format("Attempting ResetTurnFlagsForPlayer for PlayerID: %s (Type: %s)", tostring(playerId), type(playerId)))
	local diceReset = false
	if playerDiceBonusUses[playerId] then debugLog(string.format("  > Found dice bonus flag for %s. Resetting.", tostring(playerId))); playerDiceBonusUses[playerId] = nil; diceReset = true end
	local itemReset = false
	local currentItemFlagValue = playerItemUsedThisTurn[playerId]
	debugLog(string.format("  > Checking item usage flag for %s. Current value: %s", tostring(playerId), tostring(currentItemFlagValue)))
	if currentItemFlagValue then debugLog(string.format("  > Resetting item usage flag for %s.", tostring(playerId))); playerItemUsedThisTurn[playerId] = nil; itemReset = true; debugLog(string.format("  > Item usage flag for %s should now be nil. Verification: %s", tostring(playerId), tostring(playerItemUsedThisTurn[playerId])))
	else debugLog(string.format("  > No item usage flag found to reset for %s.", tostring(playerId))) end
	if diceReset or itemReset then debugLog("Reset turn flags completed for player: " .. tostring(playerId) .. " (Dice: " .. tostring(diceReset) .. ", Item: " .. tostring(itemReset) .. ")"); return true
	else debugLog("No flags needed resetting for player: " .. tostring(playerId)); return false end
end


-- Handle clicking on an equipment slot in the UI (called via RemoteEvent)
function InventoryService.HandleEquipmentSlotClick(player, slotType)
	local inventory = InventoryService.GetPlayerInventory(player)
	if not inventory then return false, "Failed to get player inventory" end
	if inventory:HasEquippedItemInSlot(slotType) then return InventoryService.UnequipItemForPlayer(player, slotType)
	else local remotes = ReplicatedStorage:WaitForChild("Remotes"); local inventoryRemotes = remotes:WaitForChild("InventoryRemotes"); local equipmentSlotClickedEvent = inventoryRemotes:WaitForChild("EquipmentSlotClicked"); equipmentSlotClickedEvent:FireClient(player, slotType); return true, "Opening equipment selection for slot " .. slotType end
end

-- Set up remote event/function connections
local function setupRemotes()
	debugLog("Setting up remotes...")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local inventoryRemotes = initializeRemotes()
	local useItemFunc = inventoryRemotes:WaitForChild("UseItem")
	useItemFunc.OnServerInvoke = InventoryService.UseItemForPlayer
	local addItemEvent = inventoryRemotes:WaitForChild("AddItem")
	addItemEvent.OnServerEvent:Connect(function(p, id, q) InventoryService.AddItemToPlayer(p, id, q) end)
	local removeItemEvent = inventoryRemotes:WaitForChild("RemoveItem")
	removeItemEvent.OnServerEvent:Connect(function(p, invId, q) InventoryService.RemoveItemFromPlayer(p, invId, q) end)
	local equipItemEvent = inventoryRemotes:WaitForChild("EquipItem")
	equipItemEvent.OnServerEvent:Connect(function(p, invId) InventoryService.EquipItemForPlayer(p, invId) end)
	local unequipItemEvent = inventoryRemotes:WaitForChild("UnequipItem")
	unequipItemEvent.OnServerEvent:Connect(function(p, slot) InventoryService.UnequipItemForPlayer(p, slot) end)
	local slotClickEvent = inventoryRemotes:WaitForChild("EquipmentSlotClicked")
	slotClickEvent.OnServerEvent:Connect(function(p, slot) InventoryService.HandleEquipmentSlotClick(p, slot) end)
	local inspectItemEvent = inventoryRemotes:WaitForChild("InspectItem")
	inspectItemEvent.OnServerEvent:Connect(function(p, invId) local inv = InventoryService.GetPlayerInventory(p); if inv then local item = inv:FindItemByInventoryId(invId); if item then inspectItemEvent:FireClient(p, item) end end end)
	debugLog("Remotes set up successfully")
end

-- Set up player join/leave events for inventory management
local function setupPlayerAndTurnEvents()
	debugLog("Setting up player events...")
	Players.PlayerAdded:Connect(function(player) InventoryService.InitializePlayer(player) end)
	Players.PlayerRemoving:Connect(function(player) local userId = player.UserId; playerInventories[userId] = nil; playerDiceBonusUses[userId] = nil; playerItemUsedThisTurn[userId] = nil; debugLog("Cleared inventory and usage cache for leaving player: " .. userId) end)
	for _, player in pairs(Players:GetPlayers()) do task.spawn(InventoryService.InitializePlayer, player) end
	debugLog("Player events set up successfully")
end

-- Initialize the service
local function init()
	debugLog("Initializing InventoryService...")
	local gameManager = getGameManager()
	if gameManager then gameManager.inventoryService = InventoryService; debugLog("InventoryService registered with GameManager") end
	setupRemotes()
	setupPlayerAndTurnEvents()
	_G.TestDiceBonus = function(player, bonusAmount) if not player then local players = Players:GetPlayers(); if #players == 0 then warn("[InvSvc] No players"); return false end; player = players[1] end; bonusAmount = bonusAmount or 1; local gm = getGameManager(); local ts = gm and gm.turnSystem; if ts and ts:GetCurrentPlayerTurn() ~= player.UserId then warn("[InvSvc] Not " .. player.Name .. "'s turn"); return false end; if gm and gm.diceBonusService then gm.diceBonusService.SetPlayerDiceBonus(player, bonusAmount); playerDiceBonusUses[player.UserId] = { itemId = "test_dice_bonus", bonusAmount = bonusAmount, timestamp = os.time() }; debugLog("Test dice bonus +" .. bonusAmount .. " set for " .. player.Name); return true else warn("[InvSvc] DiceBonusService not found"); return false end end
	debugLog("InventoryService initialized successfully")
end

-- Enable/disable debug mode
function InventoryService.SetDebugMode(enabled)
	DEBUG_MODE = enabled
	debugLog("Debug mode " .. (enabled and "enabled" or "disabled"))
end
InventoryService.SetDebugMode(true) -- Enable debug by default for testing

-- Start initialization
init()

return InventoryService
