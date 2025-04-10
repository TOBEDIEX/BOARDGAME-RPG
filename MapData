-- MapData.lua
-- ข้อมูลแผนที่กระดานเกม
-- วางที่: ServerStorage/GameData/MapData.lua

local MapData = {
	tiles = {
		[1] = {type = "start", position = Vector3.new(35.778, 0.6, -15.24)},
		[2] = {type = "normal", position = Vector3.new(35.778, 0.6, -7.24)},
		[3] = {type = "normal", position = Vector3.new(35.778, 0.6, 0.76)},
		[4] = {type = "normal", position = Vector3.new(35.778, 0.6, 8.76)},
		[5] = {type = "normal", position = Vector3.new(43.778, 0.6, 8.76)},
		[6] = {type = "normal", position = Vector3.new(51.778, 0.6, 8.76)},
		[7] = {type = "normal", position = Vector3.new(59.778, 0.6, 8.76)},
		[8] = {type = "normal", position = Vector3.new(67.778, 0.6, 8.76)},
		[9] = {type = "normal", position = Vector3.new(75.778, 0.6, 8.76)},
		[10] = {type = "shop", position = Vector3.new(75.778, 0.6, 16.76)},
		[11] = {type = "item", position = Vector3.new(75.778, 0.6, 32.76)},
		[12] = {type = "normal", position = Vector3.new(67.778, 0.6, 32.76)},
		[13] = {type = "money", position = Vector3.new(59.778, 0.6, 32.76)},
		[14] = {type = "battle", position = Vector3.new(51.778, 0.6, 32.76)},
		[15] = {type = "normal", position = Vector3.new(26.778, 0.6, 8.76)},
		[16] = {type = "normal", position = Vector3.new(18.778, 0.6, 8.76)},
		[17] = {type = "casino", position = Vector3.new(10.778, 0.6, 8.76)},
		[18] = {type = "normal", position = Vector3.new(2.778, 0.6, 8.76)},
		[19] = {type = "normal", position = Vector3.new(-5.222, 0.6, 8.76)},
		[20] = {type = "normal", position = Vector3.new(35.778, 0.6, 16.76)},
		[21] = {type = "normal", position = Vector3.new(35.778, 0.6, 24.76)},
		[22] = {type = "normal", position = Vector3.new(35.778, 0.6, 32.76)},
		[23] = {type = "normal", position = Vector3.new(43.778, 0.6, 32.76)},
	},

	connections = {
		-- เส้นทางหลัก (20 -> 1)
		[1] = {[2] = true},
		[2] = {[1] = true,[3] = true},
		[3] = {[4] = true,[2] = true},
		[4] = {[3] = true,[5] = true,[20] = true,[15] = true},
		[5] = {[6] = true,[4] = true},
		[6] = {[7] = true,[5] = true},
		[7] = {[6] = true,[8] = true},
		[8] = {[7] = true,[9] = true},
		[9] = {[10] = true,[8] = true},
		[10] = {[9] = true,[11] = true},
		[11] = {[10] = true,[12] = true},
		[12] = {[11] = true,[13] = true},
		[13] = {[14] = true,[12] = true},
		[14] = {[23] = true,[13] = true},
		[15] = {[16] = true,[4] = true},
		[16] = {[15] = true,[17] = true},
		[17] = {[18] = true,[16] = true},
		[18] = {[19] = true,[17] = true},
		[19] = {[18] = true},
		[23] = {[14] = true,[22] = true},
		[22] = {[23] = true,[21] = true},
		[21] = {[22] = true,[20] = true},
		[20] = {[21] = true,[4] = true},
	
		
	},

	specialAreas = {
		castle = {20},
		shops = {10},
		casinos = {17},
		banks = {12},
	},

	entitySpawnPoints = {
		monsters = {14},
		npcs = {10},
	},

	metadata = {
		name = "Main Board",
		description = "กระดานหลักสำหรับเกม Dokapon-style",
		version = "1.0",
		author = "MAP_CREATOR_NAME"
	}
}

return MapData
