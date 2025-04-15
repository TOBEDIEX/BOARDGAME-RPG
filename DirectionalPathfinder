-- DirectionalPathfinder.lua (แก้ไขปัญหาการคำนวณทิศทางที่ไปผิดช่อง)
-- ระบบคำนวณทิศทางสัมพัทธ์สำหรับกระดานเกม
-- วางที่: ServerStorage/Modules/DirectionalPathfinder.lua

local DirectionalPathfinder = {}

-- ค่าคงที่สำหรับทิศทาง
DirectionalPathfinder.DIRECTIONS = {
	FRONT = "FRONT",
	LEFT = "LEFT",
	RIGHT = "RIGHT"
}

-- Debug flag - เปิดไว้เพื่อช่วยในการแก้ไขปัญหา
local DEBUG_MODE = true

-- Debug logging function
local function debugLog(message)
	if DEBUG_MODE then
		print("[DirectionalPathfinder] " .. tostring(message))
	end
end

-- ฟังก์ชันตรวจสอบว่าช่องมีการเชื่อมต่อกันโดยตรงหรือไม่
function DirectionalPathfinder.areTilesConnected(connections, fromTileId, toTileId)
	if not connections or not connections[fromTileId] then
		return false
	end

	return connections[fromTileId][toTileId] == true
end

-- ฟังก์ชันหลักสำหรับคำนวณทิศทางสัมพัทธ์ (แก้ไขแล้ว)
-- previousTileId: ช่องที่เดินมา
-- currentTileId: ช่องปัจจุบัน
-- nextTileOptions: ชุดตัวเลือกช่องถัดไป (array ของ tileId)
-- tilePositions: ตำแหน่งของช่องทั้งหมด (hash table: tileId -> Vector3)
-- connections: ข้อมูลการเชื่อมต่อระหว่างช่อง (เพิ่มพารามิเตอร์นี้)
function DirectionalPathfinder.calculateRelativeDirections(previousTileId, currentTileId, nextTileOptions, tilePositions, connections)
	-- ตรวจสอบความถูกต้องของข้อมูลนำเข้า
	if not currentTileId or not tilePositions[currentTileId] then
		return {}
	end

	if not nextTileOptions or #nextTileOptions == 0 then
		return {}
	end


	-- ตรวจสอบการเชื่อมต่อของช่องที่เป็นไปได้
	-- *** ส่วนนี้เป็นการแก้ไขที่สำคัญ: กรองช่องที่ไม่ได้เชื่อมต่อโดยตรงออก ***
	local validNextTiles = {}
	for _, tileId in ipairs(nextTileOptions) do
		if DirectionalPathfinder.areTilesConnected(connections, currentTileId, tileId) then
			table.insert(validNextTiles, tileId)
		else
		end
	end

	-- ถ้าไม่มีช่องที่เชื่อมต่อโดยตรง ให้แจ้งเตือนและส่งค่าว่างกลับไป
	if #validNextTiles == 0 then
		return {}
	end

	-- กรณีพิเศษ 1: ไม่มีช่องก่อนหน้าหรือมีทางเลือกเพียงช่องเดียว
	if not previousTileId then

		-- มีทางเลือกเดียว ให้เป็น FRONT
		if #validNextTiles == 1 then
			local result = {}
			result[validNextTiles[1]] = DirectionalPathfinder.DIRECTIONS.FRONT
			return result
		end

		-- หลายทางเลือก ให้กำหนดเป็น หน้า, ซ้าย, ขวา ตามลำดับ
		local directionMap = {}
		local directions = {
			DirectionalPathfinder.DIRECTIONS.FRONT,
			DirectionalPathfinder.DIRECTIONS.LEFT,
			DirectionalPathfinder.DIRECTIONS.RIGHT
		}

		for i = 1, math.min(#validNextTiles, #directions) do
			directionMap[validNextTiles[i]] = directions[i]
		end

		return directionMap
	end

	-- กรณีพิเศษ 2: มีทางเลือกเดียว แต่มีช่องก่อนหน้า
	if #validNextTiles == 1 then

		-- ถ้าทางเลือกเดียวคือช่องก่อนหน้า (ทางตัน)
		if validNextTiles[1] == previousTileId then
			local result = {}
			result[previousTileId] = DirectionalPathfinder.DIRECTIONS.FRONT
			return result
		end

		-- ทางเลือกเดียวที่ไม่ใช่ช่องก่อนหน้า เป็นทิศทางไปข้างหน้า
		local result = {}
		result[validNextTiles[1]] = DirectionalPathfinder.DIRECTIONS.FRONT
		return result
	end

	-- กรณีปกติ: มีหลายทางเลือกและมีช่องก่อนหน้า
	-- 1. คำนวณเวกเตอร์ทิศทาง (ทิศทางการเดินปัจจุบัน)
	local previousPosition = tilePositions[previousTileId]
	local currentPosition = tilePositions[currentTileId]

	if not previousPosition then
		previousPosition = Vector3.new(currentPosition.X, currentPosition.Y, currentPosition.Z - 10)  -- สมมติทิศทางจากด้านล่างขึ้นบน
	end

	-- คำนวณเวกเตอร์ทิศทางการเดิน (เวกเตอร์จากช่องก่อนหน้าไปช่องปัจจุบัน)
	local forwardVector = (currentPosition - previousPosition)

	-- ป้องกันเวกเตอร์เป็นศูนย์
	if forwardVector.Magnitude < 0.001 then
		forwardVector = Vector3.new(0, 0, 1)  -- ค่าเริ่มต้น Z+
	else
		forwardVector = forwardVector.Unit
	end

	-- 2. คำนวณเวกเตอร์ "ขวา" ด้วย cross product กับเวกเตอร์ "ขึ้น"
	local upVector = Vector3.new(0, 1, 0)
	local rightVector = forwardVector:Cross(upVector)

	-- ป้องกันเวกเตอร์เป็นศูนย์
	if rightVector.Magnitude < 0.001 then
		rightVector = Vector3.new(1, 0, 0)  -- ค่าเริ่มต้น X+
	else
		rightVector = rightVector.Unit
	end

	-- 3. คำนวณเวกเตอร์ "ซ้าย"
	local leftVector = -rightVector

	-- 4. สร้าง hash map ของทิศทางสำหรับแต่ละช่องถัดไป
	local directionsMap = {}
	local highestDotValues = {
		[DirectionalPathfinder.DIRECTIONS.FRONT] = -1,
		[DirectionalPathfinder.DIRECTIONS.LEFT] = -1,
		[DirectionalPathfinder.DIRECTIONS.RIGHT] = -1
	}  -- เก็บค่า dot product สูงสุดสำหรับแต่ละทิศทาง

	-- ลูปผ่านช่องที่เชื่อมต่อกับช่องปัจจุบัน
	for _, nextTileId in ipairs(validNextTiles) do
		-- ข้ามช่องก่อนหน้า (ใช้ในการกำหนดทิศทาง แต่ไม่ใช่เป็นตัวเลือกในการเดิน)
		if nextTileId == previousTileId then
			continue
		end

		local nextPosition = tilePositions[nextTileId]
		if not nextPosition then
			continue
		end

		-- คำนวณเวกเตอร์ทิศทางไปยังช่องถัดไป
		local nextVector = (nextPosition - currentPosition)

		-- ป้องกันเวกเตอร์เป็นศูนย์
		if nextVector.Magnitude < 0.001 then
			continue
		else
			nextVector = nextVector.Unit
		end

		-- คำนวณ dot product เพื่อหาความเหมือนระหว่างเวกเตอร์
		local forwardDot = forwardVector:Dot(nextVector)
		local rightDot = rightVector:Dot(nextVector)
		local leftDot = leftVector:Dot(nextVector)


		-- ปรับค่า dot product เพื่อลดความกำกวม
		-- เพิ่มน้ำหนักให้ทิศทางไปข้างหน้าเล็กน้อย
		forwardDot = forwardDot * 1.2 -- เพิ่มค่าจาก 1.1 เป็น 1.2

		-- เลือกทิศทางที่มีค่า dot มากที่สุด (มุมน้อยที่สุด)
		local maxDot = math.max(forwardDot, rightDot, leftDot)
		local direction

		if maxDot == forwardDot then
			direction = DirectionalPathfinder.DIRECTIONS.FRONT
			if forwardDot > highestDotValues[direction] then
				highestDotValues[direction] = forwardDot
				-- อัปเดตทิศทาง FRONT สำหรับช่องที่มีค่า dot สูงที่สุด
				-- กำหนดช่องนี้เป็น FRONT แทนช่องก่อนหน้า (ถ้ามี)
				for tileId, dir in pairs(directionsMap) do
					if dir == DirectionalPathfinder.DIRECTIONS.FRONT then
						directionsMap[tileId] = nil -- ลบการกำหนดทิศทาง FRONT เดิม
					end
				end
				directionsMap[nextTileId] = direction
			end
		elseif maxDot == rightDot then
			direction = DirectionalPathfinder.DIRECTIONS.RIGHT
			if rightDot > highestDotValues[direction] then
				highestDotValues[direction] = rightDot
				-- อัปเดตทิศทาง RIGHT สำหรับช่องที่มีค่า dot สูงที่สุด
				for tileId, dir in pairs(directionsMap) do
					if dir == DirectionalPathfinder.DIRECTIONS.RIGHT then
						directionsMap[tileId] = nil -- ลบการกำหนดทิศทาง RIGHT เดิม
					end
				end
				directionsMap[nextTileId] = direction
			end
		elseif maxDot == leftDot then
			direction = DirectionalPathfinder.DIRECTIONS.LEFT
			if leftDot > highestDotValues[direction] then
				highestDotValues[direction] = leftDot
				-- อัปเดตทิศทาง LEFT สำหรับช่องที่มีค่า dot สูงที่สุด
				for tileId, dir in pairs(directionsMap) do
					if dir == DirectionalPathfinder.DIRECTIONS.LEFT then
						directionsMap[tileId] = nil -- ลบการกำหนดทิศทาง LEFT เดิม
					end
				end
				directionsMap[nextTileId] = direction
			end
		end

		-- ถ้ายังไม่ได้กำหนดทิศทาง ให้กำหนดทิศทางเริ่มต้น
		if not directionsMap[nextTileId] then
			directionsMap[nextTileId] = direction
		end

	end

	-- ตรวจสอบความขัดแย้งหลังจากกำหนดทิศทางที่ดีที่สุด
	local directionCount = {}
	for _, direction in pairs(directionsMap) do
		directionCount[direction] = (directionCount[direction] or 0) + 1
	end

	-- แสดงผลลัพธ์สุดท้าย
	for tileId, direction in pairs(directionsMap) do
	end

	-- พิมพ์คำเตือนสำหรับทิศทางที่ขาดหายไป
	local hasDirection = {
		[DirectionalPathfinder.DIRECTIONS.FRONT] = false,
		[DirectionalPathfinder.DIRECTIONS.LEFT] = false,
		[DirectionalPathfinder.DIRECTIONS.RIGHT] = false
	}
	for _, direction in pairs(directionsMap) do
		hasDirection[direction] = true
	end

	for direction, exists in pairs(hasDirection) do
		if not exists then
		end
	end

	return directionsMap
end

-- ฟังก์ชันแปลงทิศทางให้อยู่ในรูปแบบที่ใช้ในเกม (แก้ไขแล้ว)
function DirectionalPathfinder.getPathOptions(previousTileId, currentTileId, connections, tilePositions)
	-- หาช่องที่เชื่อมกับช่องปัจจุบัน
	local nextTileOptions = {}

	if not connections[currentTileId] then
		return {}
	end

	for tileId, _ in pairs(connections[currentTileId]) do
		table.insert(nextTileOptions, tileId)
	end

	-- ตรวจสอบว่ามีช่องเชื่อมต่อหรือไม่
	if #nextTileOptions == 0 then
		return {}
	end

	-- ระบุช่องที่เชื่อมต่อโดยตรง
	for i, tileId in ipairs(nextTileOptions) do
	end

	-- คำนวณทิศทางสัมพัทธ์ (ส่ง connections เพิ่มเติม)
	local directionsMap = DirectionalPathfinder.calculateRelativeDirections(
		previousTileId, currentTileId, nextTileOptions, tilePositions, connections)

	-- แปลงเป็นรูปแบบ options ที่ใช้ในเกม
	local pathOptions = {}

	for tileId, direction in pairs(directionsMap) do
		table.insert(pathOptions, {
			direction = direction,
			tileId = tileId
		})
	end

	-- เรียงลำดับตามทิศทาง (FRONT, LEFT, RIGHT)
	local directionOrder = {
		[DirectionalPathfinder.DIRECTIONS.FRONT] = 1,
		[DirectionalPathfinder.DIRECTIONS.LEFT] = 2,
		[DirectionalPathfinder.DIRECTIONS.RIGHT] = 3
	}

	table.sort(pathOptions, function(a, b)
		return directionOrder[a.direction] < directionOrder[b.direction]
	end)

	-- แสดงผลลัพธ์สุดท้ายของทางเลือก
	for i, option in ipairs(pathOptions) do
	end

	return pathOptions
end

-- ฟังก์ชันสำหรับทดสอบการคำนวณทิศทาง
function DirectionalPathfinder.testDirections(tilePositions, connections)

	-- ทดสอบกรณีปัญหา: เดินจากช่อง 3 ไป 11 โดยผิดพลาด
	local testCases = {
		{prev = 2, current = 3, expected = {[5] = "LEFT", [8] = "RIGHT", [4] = "FRONT"}},
		{prev = 2, current = 3, next_tiles = {5, 8, 4, 11}, expected = {[5] = "LEFT", [8] = "RIGHT", [4] = "FRONT"}},
		{prev = 9, current = 10, expected = {[11] = "FRONT", [9] = "RIGHT"}},
		{prev = 11, current = 10, expected = {[9] = "FRONT", [11] = "RIGHT"}},
		{prev = 14, current = 15, expected = {[16] = "FRONT", [14] = "RIGHT"}},
		{prev = 16, current = 17, expected = {[4] = "FRONT", [16] = "RIGHT"}},
	}

	for i, test in ipairs(testCases) do

		-- หาช่องที่เชื่อมกับช่องปัจจุบัน
		local nextTileOptions = {}
		if test.next_tiles then
			nextTileOptions = test.next_tiles
		else
			for tileId, _ in pairs(connections[test.current] or {}) do
				table.insert(nextTileOptions, tileId)
			end
		end


		-- คำนวณทิศทาง
		local directions = DirectionalPathfinder.calculateRelativeDirections(
			test.prev, test.current, nextTileOptions, tilePositions, connections)

		-- แสดงผลลัพธ์
		local results = {}
		for tileId, direction in pairs(directions) do
			table.insert(results, "[" .. tileId .. "]" .. direction)
		end


		-- ตรวจสอบกับค่าที่คาดหวัง
		local allCorrect = true
		for tileId, expectedDir in pairs(test.expected) do
			if directions[tileId] ~= expectedDir then
				allCorrect = false
			end
		end

		if allCorrect then
			print("  ✓ ผลลัพธ์ถูกต้อง")
		else
			print("  ✗ การทดสอบล้มเหลว")
		end
	end

	print("\n=== ทดสอบเสร็จสิ้น ===")
end

-- ตั้งค่าเริ่มต้นสำหรับทดสอบเมื่อโมดูลถูกโหลด
function DirectionalPathfinder.runAutoDiagnostics(connections, tilePositions)
	if DEBUG_MODE and connections and tilePositions then
		print("\n[DirectionalPathfinder] เริ่มการวิเคราะห์อัตโนมัติ")

		-- ตรวจสอบการเชื่อมต่อที่มีปัญหา
		if connections[3] then
			print("ตรวจสอบการเชื่อมต่อของช่อง 3:")
			for tileId, connected in pairs(connections[3]) do
				print("- เชื่อมต่อกับช่อง " .. tileId .. ": " .. tostring(connected))
			end

			if connections[3][11] then
				print("❌ พบปัญหา: ช่อง 3 มีการเชื่อมต่อโดยตรงกับช่อง 11 ซึ่งไม่ควรเป็นเช่นนั้น")
			else
				print("✓ ถูกต้อง: ช่อง 3 ไม่ได้เชื่อมต่อโดยตรงกับช่อง 11")
			end
		end

		-- ทดสอบการคำนวณทิศทางสำหรับช่อง 3
		if tilePositions[3] and tilePositions[2] then
			local nextTileOptions = {}
			if connections[3] then
				for tileId, _ in pairs(connections[3]) do
					table.insert(nextTileOptions, tileId)
				end
			end


			local directions = DirectionalPathfinder.calculateRelativeDirections(
				2, 3, nextTileOptions, tilePositions, connections)

			print("- ผลลัพธ์ทิศทาง:")
			for tileId, direction in pairs(directions) do
			end
		end

		print("\n[DirectionalPathfinder] เสร็จสิ้นการวิเคราะห์อัตโนมัติ")
	end
end

return DirectionalPathfinder
