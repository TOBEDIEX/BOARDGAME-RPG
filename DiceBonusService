-- DiceBonusService.server.lua
-- บริการจัดการโบนัสลูกเต๋าฝั่งเซิร์ฟเวอร์
-- Version: 1.1.0 (ปรับปรุงการเชื่อมต่อกับระบบอื่น)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- ตั้งค่า Debug Mode
local DEBUG = true
local function log(msg) if DEBUG then print("[DiceBonusService] " .. msg) end end

-- สร้าง Remote Events
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local inventoryRemotes = remotes:FindFirstChild("InventoryRemotes")
if not inventoryRemotes then
	inventoryRemotes = Instance.new("Folder")
	inventoryRemotes.Name = "InventoryRemotes"
	inventoryRemotes.Parent = remotes
end

local diceBonusEvent = inventoryRemotes:FindFirstChild("DiceBonus")
if not diceBonusEvent then
	diceBonusEvent = Instance.new("RemoteEvent")
	diceBonusEvent.Name = "DiceBonus"
	diceBonusEvent.Parent = inventoryRemotes
end

-- เตรียมการเชื่อมต่อกับ BoardRemotes
local boardRemotes = remotes:WaitForChild("BoardRemotes")
local rollDiceEvent = boardRemotes:WaitForChild("RollDice")
local gameRemotes = remotes:WaitForChild("GameRemotes")
local updateTurnEvent = gameRemotes:WaitForChild("UpdateTurn")

-- เก็บข้อมูลโบนัสลูกเต๋าตามผู้เล่น
local playerDiceBonuses = {}

-- Main service
local DiceBonusService = {}

-- ฟังก์ชันคืนค่าโบนัสลูกเต๋าของผู้เล่น
function DiceBonusService.GetPlayerDiceBonus(player)
	if typeof(player) == "number" then
		-- กรณีส่ง UserId มาแทน Player
		return playerDiceBonuses[player] or 0
	else
		return playerDiceBonuses[player.UserId] or 0
	end
end

-- ฟังก์ชันตั้งค่าโบนัสลูกเต๋าของผู้เล่น
function DiceBonusService.SetPlayerDiceBonus(player, bonusAmount)
	local playerId = typeof(player) == "number" and player or player.UserId
	local playerObj = typeof(player) == "number" and Players:GetPlayerByUserId(player) or player

	if not playerObj then 
		log("ไม่พบผู้เล่น UserId: " .. playerId)
		return false 
	end

	playerDiceBonuses[playerId] = bonusAmount

	-- แจ้ง client เกี่ยวกับโบนัสลูกเต๋า
	diceBonusEvent:FireClient(playerObj, bonusAmount)

	-- ส่งข้อมูลให้ BoardService ด้วย (เพิ่มเติม)
	diceBonusEvent:FireServer(bonusAmount)

	log("ตั้งค่าโบนัสลูกเต๋าสำหรับ " .. playerObj.Name .. " เป็น +" .. bonusAmount)
	return true
end

-- ฟังก์ชันล้างโบนัสลูกเต๋าของผู้เล่น
function DiceBonusService.ClearPlayerDiceBonus(player)
	local playerId = typeof(player) == "number" and player or player.UserId
	local playerObj = typeof(player) == "number" and Players:GetPlayerByUserId(player) or player

	playerDiceBonuses[playerId] = nil

	-- แจ้ง client ว่าล้างโบนัสแล้ว (เพิ่มเติม)
	if playerObj then
		diceBonusEvent:FireClient(playerObj, 0)
	end

	log("ล้างโบนัสลูกเต๋าสำหรับผู้เล่น UserId: " .. playerId)
	return true
end

-- ฟังก์ชันเพิ่มโบนัสลูกเต๋าของผู้เล่น
function DiceBonusService.AddPlayerDiceBonus(player, bonusAmount)
	local playerId = typeof(player) == "number" and player or player.UserId
	local playerObj = typeof(player) == "number" and Players:GetPlayerByUserId(player) or player

	if not playerObj then 
		log("ไม่พบผู้เล่น UserId: " .. playerId)
		return false 
	end

	local currentBonus = playerDiceBonuses[playerId] or 0
	local newBonus = currentBonus + bonusAmount

	playerDiceBonuses[playerId] = newBonus

	-- แจ้ง client เกี่ยวกับโบนัสลูกเต๋า
	diceBonusEvent:FireClient(playerObj, newBonus)

	-- ส่งข้อมูลให้ BoardService ด้วย (เพิ่มเติม)
	diceBonusEvent:FireServer(newBonus)

	log("เพิ่มโบนัสลูกเต๋า +" .. bonusAmount .. " สำหรับ " .. playerObj.Name .. " (รวมเป็น +" .. newBonus .. ")")
	return true
end

-- ฟังก์ชันทดสอบตั้งค่าโบนัสลูกเต๋า
function DiceBonusService.TestSetBonus(player, bonusAmount)
	-- ถ้าไม่ระบุผู้เล่น ใช้ผู้เล่นแรกในเซิร์ฟเวอร์
	if not player then
		local players = Players:GetPlayers()
		if #players == 0 then 
			warn("[DiceBonusService] ไม่มีผู้เล่นในเกม")
			return false 
		end
		player = players[1]
	end

	-- ถ้าไม่ระบุจำนวนโบนัส ใช้ค่าเริ่มต้น 1
	bonusAmount = bonusAmount or 1

	log("ทดสอบตั้งค่าโบนัสลูกเต๋า +" .. bonusAmount .. " สำหรับ " .. player.Name)

	-- ตั้งค่าโบนัส
	return DiceBonusService.SetPlayerDiceBonus(player, bonusAmount)
end

-- ฟังก์ชันใหม่: ส่งค่าโบนัสลูกเต๋าให้ทุกระบบ
function DiceBonusService.BroadcastDiceBonus(player, bonusAmount)
	local playerId = typeof(player) == "number" and player or player.UserId
	local playerObj = typeof(player) == "number" and Players:GetPlayerByUserId(player) or player

	if not playerObj then return false end

	-- บันทึกค่าในระบบนี้
	playerDiceBonuses[playerId] = bonusAmount

	-- ส่งให้ Client
	diceBonusEvent:FireClient(playerObj, bonusAmount)

	-- ส่งให้ระบบอื่นๆ
	diceBonusEvent:FireServer(bonusAmount)

	-- ส่งให้ GameManager (ถ้ามี)
	if _G.GameManager and _G.GameManager.boardService then
		if _G.GameManager.boardService.SetDiceBonus then
			_G.GameManager.boardService.SetDiceBonus(playerId, bonusAmount)
		end
	end

	log("Broadcast dice bonus +" .. bonusAmount .. " for player " .. playerObj.Name)
	return true
end

-- ====== รายการเชื่อมต่อกับระบบอื่นๆ ======

-- ตรวจสอบเมื่อผู้เล่นทอยลูกเต๋า
rollDiceEvent.OnServerEvent:Connect(function(player, diceResult)
	-- ตรวจสอบว่ามีโบนัสอยู่หรือไม่ (ควรถูกคำนวณจาก client แล้ว)
	if playerDiceBonuses[player.UserId] then
		-- แสดงข้อมูลการใช้โบนัส
		log("ผู้เล่น " .. player.Name .. " ได้ใช้โบนัสลูกเต๋า +" .. playerDiceBonuses[player.UserId] .. 
			" และทอยได้ " .. diceResult)

		-- หลังจากทอยลูกเต๋าแล้ว ล้างโบนัสทิ้ง
		playerDiceBonuses[player.UserId] = nil

		-- แจ้ง client ว่าล้างโบนัสแล้ว
		diceBonusEvent:FireClient(player, 0)
	end
end)

-- ตรวจสอบเมื่อเปลี่ยนเทิร์น (ล้างโบนัสเมื่อจบเทิร์น)
updateTurnEvent.OnServerEvent:Connect(function(_, currentPlayerId)
	-- ตรวจสอบว่ามีโบนัสค้างอยู่จากเทิร์นก่อนหน้า
	for playerId, bonus in pairs(playerDiceBonuses) do
		if playerId ~= currentPlayerId then
			-- แจ้ง client ว่าล้างโบนัสแล้ว
			local player = Players:GetPlayerByUserId(playerId)
			if player then
				diceBonusEvent:FireClient(player, 0)
			end

			-- ล้างโบนัสของผู้เล่นที่ไม่ใช่ผู้เล่นปัจจุบัน
			playerDiceBonuses[playerId] = nil
			log("ล้างโบนัสลูกเต๋าสำหรับผู้เล่น UserId: " .. playerId .. " เนื่องจากหมดเทิร์น")
		end
	end
end)

-- ตรวจสอบเมื่อผู้เล่นออก
Players.PlayerRemoving:Connect(function(player)
	playerDiceBonuses[player.UserId] = nil
	log("ล้างโบนัสลูกเต๋าสำหรับ " .. player.Name .. " เนื่องจากออกจากเกม")
end)

-- เพิ่มฟังก์ชันเพื่อรับข้อมูลโบนัสจากระบบอื่นๆ
diceBonusEvent.OnServerEvent:Connect(function(player, bonusAmount)
	if player and typeof(bonusAmount) == "number" then
		playerDiceBonuses[player.UserId] = bonusAmount
		log("Received bonus data from external system: " .. bonusAmount .. " for player " .. player.Name)
	end
end)

-- เพิ่มฟังก์ชันทดสอบใน global
_G.TestSetDiceBonus = DiceBonusService.TestSetBonus

-- เพิ่มตัวจัดการใน GameManager
if _G.GameManager then
	_G.GameManager.diceBonusService = DiceBonusService
	log("ลงทะเบียน DiceBonusService กับ GameManager เรียบร้อย")
end

-- เพิ่มเข้า _G เพื่อให้สคริปต์อื่นเข้าถึงได้
_G.DiceBonusService = DiceBonusService

log("ระบบโบนัสลูกเต๋าฝั่งเซิร์ฟเวอร์เริ่มต้นแล้ว - พิมพ์ _G.TestSetDiceBonus() ในแถบคำสั่งเพื่อทดสอบ")

return DiceBonusService
