-- ItemTileHandler.server.lua
-- ตัวจัดการเหตุการณ์ช่อง Item ฝั่งเซิร์ฟเวอร์
-- Version: 1.1.0 - แก้ไขเพื่อรองรับการยืนยันไอเทมจากผู้เล่น

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- ตั้งค่า Debug Mode
local DEBUG = true
local function log(msg) if DEBUG then print("[ItemTileServer] " .. msg) end end

-- สร้าง Remote Events
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local eventTileRemotes = remotes:FindFirstChild("EventTileRemotes") or Instance.new("Folder")
eventTileRemotes.Name = "EventTileRemotes"
eventTileRemotes.Parent = remotes

local itemEventRemote = eventTileRemotes:FindFirstChild("ItemEvent") or Instance.new("RemoteEvent")
itemEventRemote.Name = "ItemEvent"
itemEventRemote.Parent = eventTileRemotes

-- โหลด ItemData module
local ItemData = nil
local success, result = pcall(function()
	return require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("ItemData"))
end)

if success then
	ItemData = result
	log("โหลด ItemData module สำเร็จ")
else
	warn("[ItemTileServer] ไม่สามารถโหลด ItemData module: " .. tostring(result))
	-- สร้าง ItemData จำลอง
	ItemData = {
		Items = {
			health_potion = {
				id = "health_potion",
				name = "Health Potion",
				description = "ฟื้นพลังชีวิต 50 หน่วย",
				type = 1,
				rarity = 1,
				iconId = "rbxassetid://7060145106"
			}
		},
		GetRandomItemFromPool = function()
			return {
				id = "health_potion",
				name = "Health Potion",
				description = "ฟื้นพลังชีวิต 50 หน่วย",
				type = 1,
				rarity = 1,
				iconId = "rbxassetid://7060145106"
			}
		end,
		GetItemById = function(id)
			return {
				id = id,
				name = "Unknown Item",
				description = "Item data not available.",
				type = 1,
				rarity = 1,
				iconId = ""
			}
		end
	}
end

-- หา InventoryService
local function getInventoryService()
	-- ลองหาจากหลายวิธี
	if _G.GameManager and _G.GameManager.inventoryService then 
		return _G.GameManager.inventoryService 
	end

	-- ถ้าไม่พบ สร้าง stub
	log("ไม่พบ InventoryService สร้าง stub")
	return {
		AddItemToPlayer = function(player, itemId, quantity)
			log("⚠️ [STUB] AddItemToPlayer สำหรับ " .. player.Name .. " - ไอเทม: " .. itemId .. " x" .. tostring(quantity))
			return true, "Item added (stub)"
		end
	}
end

-- เก็บข้อมูลไอเทมที่รอการยืนยันจากผู้เล่น
local pendingItems = {}

-- สร้างคีย์สำหรับเก็บข้อมูลไอเทมรอคอย
local function createPendingKey(player, itemId)
	return player.UserId .. "_" .. itemId .. "_" .. os.time()
end

-- รับฟังเหตุการณ์จาก client
itemEventRemote.OnServerEvent:Connect(function(player, command, data)
	log("ได้รับคำสั่ง: " .. tostring(command) .. " จาก " .. player.Name)

	if command == "giveRandomItem" then
		-- สุ่มไอเทม
		local randomItem = ItemData.GetRandomItemFromPool()
		if not randomItem then
			warn("[ItemTileServer] ไม่สามารถสุ่มไอเทมได้ สำหรับผู้เล่น " .. player.Name)
			return
		end

		log("สุ่มได้ไอเทม: " .. randomItem.name .. " (ID: " .. randomItem.id .. ")")

		-- สร้างคีย์สำหรับไอเทมรอคอย
		local pendingKey = createPendingKey(player, randomItem.id)

		-- เก็บข้อมูลไอเทมรอการยืนยัน
		pendingItems[pendingKey] = {
			player = player,
			item = randomItem,
			timestamp = os.time()
		}

		-- ส่งข้อมูลไอเทมไปให้ client แสดง UI ยืนยัน
		-- เพิ่ม pendingKey เพื่อใช้อ้างอิงตอนยืนยัน
		itemEventRemote:FireClient(player, "confirmItem", {
			item = randomItem,
			pendingKey = pendingKey
		})

		log("ส่งคำขอยืนยันไอเทม " .. randomItem.name .. " ไปยัง " .. player.Name)

		-- ตั้งเวลาลบข้อมูลรอคอยหลังจาก 5 นาที ถ้าไม่มีการตอบกลับ
		task.delay(300, function()
			if pendingItems[pendingKey] then
				pendingItems[pendingKey] = nil
				log("ลบข้อมูลไอเทมรอคอยที่หมดเวลาสำหรับ " .. player.Name)
			end
		end)
	elseif command == "keepItem" and data and data.pendingKey then
		-- ผู้เล่นตกลงรับไอเทม
		local pendingData = pendingItems[data.pendingKey]

		if not pendingData then
			log("ไม่พบข้อมูลไอเทมรอคอยสำหรับคีย์: " .. data.pendingKey)
			return
		end

		-- ตรวจสอบว่าเป็นผู้เล่นคนเดียวกัน
		if pendingData.player ~= player then
			log("ผู้เล่นไม่ตรงกัน สำหรับคีย์: " .. data.pendingKey)
			return
		end

		local randomItem = pendingData.item

		-- เพิ่มไอเทมให้ผู้เล่น
		local inventoryService = getInventoryService()
		local success, message = inventoryService.AddItemToPlayer(player, randomItem.id, 1)

		-- แจ้งกลับไปยัง client
		if success then
			log("เพิ่ม " .. randomItem.name .. " ให้กับ " .. player.Name .. " สำเร็จ")
			itemEventRemote:FireClient(player, "itemAdded", randomItem)
		else
			warn("[ItemTileServer] ไม่สามารถเพิ่มไอเทมให้ผู้เล่น: " .. (message or "ไม่ทราบสาเหตุ"))
			itemEventRemote:FireClient(player, "itemError", {
				item = randomItem,
				message = message or "ไม่สามารถเพิ่มไอเทมได้"
			})
		end

		-- ลบข้อมูลรอคอย
		pendingItems[data.pendingKey] = nil
	elseif command == "discardItem" and data and data.pendingKey then
		-- ผู้เล่นปฏิเสธไอเทม
		local pendingData = pendingItems[data.pendingKey]

		if pendingData then
			log("ผู้เล่น " .. player.Name .. " ปฏิเสธไอเทม " .. pendingData.item.name)

			-- แจ้ง client ว่าได้ยกเลิกไอเทมแล้ว
			itemEventRemote:FireClient(player, "itemDiscarded", pendingData.item)

			-- ลบข้อมูลรอคอย
			pendingItems[data.pendingKey] = nil
		else
			log("ไม่พบข้อมูลไอเทมรอคอยสำหรับคีย์: " .. data.pendingKey)
		end
	end
end)

-- ฟังก์ชันทดสอบ
local function testGiveRandomItem(player)
	-- ถ้าไม่ระบุผู้เล่น ใช้ผู้เล่นแรกในเซิร์ฟเวอร์
	if not player then
		local players = Players:GetPlayers()
		if #players == 0 then 
			warn("[ItemTileServer] ไม่มีผู้เล่นในเกม")
			return false 
		end
		player = players[1]
	end

	log("ทดสอบสุ่มไอเทมให้ " .. player.Name)

	-- สุ่มไอเทม
	local randomItem = ItemData.GetRandomItemFromPool()
	if not randomItem then
		warn("[ItemTileServer] ไม่สามารถสุ่มไอเทมได้")
		return false
	end

	log("สุ่มได้ไอเทม: " .. randomItem.name .. " (ID: " .. randomItem.id .. ")")

	-- สร้างคีย์สำหรับไอเทมรอคอย
	local pendingKey = createPendingKey(player, randomItem.id)

	-- เก็บข้อมูลไอเทมรอการยืนยัน
	pendingItems[pendingKey] = {
		player = player,
		item = randomItem,
		timestamp = os.time()
	}

	-- ส่งข้อมูลไอเทมไปให้ client แสดง UI ยืนยัน
	itemEventRemote:FireClient(player, "confirmItem", {
		item = randomItem,
		pendingKey = pendingKey
	})

	log("ส่งคำขอยืนยันไอเทม " .. randomItem.name .. " ไปยัง " .. player.Name)
	return true
end

-- เพิ่มฟังก์ชันทดสอบใน global
_G.TestGiveRandomItem = testGiveRandomItem

-- เพิ่มฟังก์ชันทดสอบเพิ่มไอเทมโดยตรง (ไม่ต้องยืนยัน)
local function testAddItemDirectly(player, itemId)
	-- ถ้าไม่ระบุผู้เล่น ใช้ผู้เล่นแรกในเซิร์ฟเวอร์
	if not player then
		local players = Players:GetPlayers()
		if #players == 0 then 
			warn("[ItemTileServer] ไม่มีผู้เล่นในเกม")
			return false 
		end
		player = players[1]
	end

	-- ถ้าไม่ระบุไอเทม สุ่มไอเทม
	if not itemId then
		local randomItem = ItemData.GetRandomItemFromPool()
		if not randomItem then
			warn("[ItemTileServer] ไม่สามารถสุ่มไอเทมได้")
			return false
		end
		itemId = randomItem.id
	end

	log("ทดสอบเพิ่มไอเทม " .. itemId .. " ให้กับ " .. player.Name .. " โดยตรง")

	-- เพิ่มไอเทมให้ผู้เล่นโดยตรง
	local inventoryService = getInventoryService()
	local success, message = inventoryService.AddItemToPlayer(player, itemId, 1)

	if success then
		log("เพิ่ม " .. itemId .. " ให้กับ " .. player.Name .. " สำเร็จ")
		-- ดึงข้อมูลไอเทม
		local itemData = ItemData.GetItemById(itemId)
		if itemData then
			itemEventRemote:FireClient(player, "itemAdded", itemData)
		end
	else
		warn("[ItemTileServer] ไม่สามารถเพิ่มไอเทมให้ผู้เล่น: " .. (message or "ไม่ทราบสาเหตุ"))
	end

	return success
end

-- เพิ่มฟังก์ชันทดสอบใน global
_G.TestAddItemDirectly = testAddItemDirectly

log("ระบบช่อง Item ฝั่งเซิร์ฟเวอร์เริ่มต้นแล้ว - พิมพ์ _G.TestGiveRandomItem() ในแถบคำสั่งเพื่อทดสอบ")
