-- BoardSystem.lua
-- Core module for board system and character movement
-- Version: 3.3.0 (Removed onTileEffect trigger during movement)

local BoardSystem = {}
BoardSystem.__index = BoardSystem

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Load related modules
local DirectionalPathfinder = require(script.Parent:WaitForChild("DirectionalPathfinder"))

-- Constants for board directions
local DIRECTIONS = DirectionalPathfinder.DIRECTIONS

-- DEBUG MODE
local DEBUG_MOVEMENT = true

function BoardSystem.new()
	local self = setmetatable({}, BoardSystem)

	self.tiles = {}
	self.connections = {}
	self.playerPositions = {}
	self.playerLastTile = {}
	self.playerRemainingSteps = {}
	self.playerMovementState = {}
	self.playerAutoPath = {}
	self.tilePositions = {}
	self.entitySpawnPoints = {}
	self.onPlayerMoved = nil
	self.onPlayerPathComplete = nil
	-- REMOVED: self.onTileEffect = nil -- ลบ callback นี้ออก

	return self
end

function BoardSystem:LoadMap(mapData)
	if not mapData or type(mapData) ~= "table" then return false end

	-- Reset data
	self.tiles = {}
	self.connections = {}
	self.tilePositions = {}

	-- Load tile data
	for id, tile in pairs(mapData.tiles or {}) do
		self.tiles[id] = {
			id = id,
			type = tile.type or "normal",
			properties = tile.properties or {},
			position = tile.position
		}

		if tile.position then
			self.tilePositions[id] = tile.position
		end
	end

	-- Load connections
	self.connections = mapData.connections or {}

	-- Load spawn points
	self.entitySpawnPoints = mapData.entitySpawnPoints or {}

	return true
end

function BoardSystem:CountTiles()
	local count = 0
	for _ in pairs(self.tiles) do
		count = count + 1
	end
	return count
end

function BoardSystem:SetPlayerPosition(playerId, tileId, lastTileId)
	if not playerId or not tileId then return false end

	-- Store previous position
	self.playerLastTile[playerId] = lastTileId or self.playerPositions[playerId]

	-- Set new position
	self.playerPositions[playerId] = tileId

	-- Call callback if set
	if self.onPlayerMoved then
		self.onPlayerMoved(playerId, self.playerLastTile[playerId], tileId)
	end

	return true
end

function BoardSystem:GetPlayerTile(playerId)
	return self.playerPositions[playerId]
end

function BoardSystem:GetTilePosition(tileId)
	return self.tilePositions[tileId]
end

function BoardSystem:GetTileInfo(tileId)
	return self.tiles[tileId]
end

function BoardSystem:GetTilesByType(tileType)
	local result = {}
	for id, tile in pairs(self.tiles) do
		if tile.type == tileType then
			table.insert(result, id)
		end
	end
	return result
end

function BoardSystem:GetAvailableDirections(tileId, prevTileId)
	return DirectionalPathfinder.getPathOptions(
		prevTileId, tileId, self.connections, self.tilePositions)
end

function BoardSystem:GetNextTileFromDirection(tileId, direction, prevTileId)
	local availableDirections = self:GetAvailableDirections(tileId, prevTileId)
	for _, dirInfo in ipairs(availableDirections) do
		if dirInfo.direction == direction then
			return dirInfo.tileId
		end
	end
	return nil
end

function BoardSystem:GetPlayersOnTile(tileId)
	local players = {}
	for playerId, playerTileId in pairs(self.playerPositions) do
		if playerTileId == tileId then
			table.insert(players, playerId)
		end
	end
	return players
end

-- ฟังก์ชันแก้ไขสำหรับรองรับจำนวนก้าวที่มากขึ้น
function BoardSystem:GenerateAutoPath(playerId, startTileId, prevTileId, stepsRemaining)
	if DEBUG_MOVEMENT then
		print("[BoardSystem] GenerateAutoPath: Player " .. playerId ..
			" from tile " .. startTileId .. " with " .. stepsRemaining .. " steps remaining")
	end

	local currentTileId = startTileId
	local currentPrevTileId = prevTileId
	local path = {currentTileId}
	local remainingSteps = stepsRemaining

	-- บันทึกทางเดินที่เคยผ่านมาแล้วเพื่อป้องกันการวนซ้ำ
	local visitedTiles = {[currentTileId] = true}
	local maxIteration = 100 -- ป้องกันการลูปไม่สิ้นสุด
	local iteration = 0

	-- รองรับก้าวไม่จำกัด ไม่ว่าจะกี่ก้าวก็ตาม
	while remainingSteps > 0 and iteration < maxIteration do
		iteration = iteration + 1

		-- Get available directions
		local availableDirections = self:GetAvailableDirections(currentTileId, currentPrevTileId)

		if DEBUG_MOVEMENT and #availableDirections == 0 then
			print("[BoardSystem] -> Dead end at tile " .. currentTileId)
		end

		-- Stop if dead end
		if #availableDirections == 0 then break end

		-- กรองทางเลือกที่ไม่ใช่ก้าวถอยหลัง (ย้อนกลับไปทางเดิม)
		local validDirections = {}
		for _, dirInfo in ipairs(availableDirections) do
			-- ตรวจสอบว่าไม่ใช่การย้อนกลับและไม่เคยผ่านช่องนี้มาแล้ว
			if dirInfo.tileId ~= currentPrevTileId and not visitedTiles[dirInfo.tileId] then
				table.insert(validDirections, dirInfo)
			end
		end

		-- Auto-move only when there's only one valid way forward
		if #validDirections == 1 then
			local nextTileId = validDirections[1].tileId

			-- บันทึกช่องที่เดินผ่าน
			visitedTiles[nextTileId] = true

			-- เดินไปยังช่องถัดไป
			table.insert(path, nextTileId)
			currentPrevTileId = currentTileId
			currentTileId = nextTileId
			remainingSteps = remainingSteps - 1

			if DEBUG_MOVEMENT then
				print("[BoardSystem] -> Auto-move to tile " .. nextTileId ..
					", remaining steps: " .. remainingSteps)
			end
		else
			-- Multiple directions or dead end, player must choose
			if DEBUG_MOVEMENT then
				print("[BoardSystem] -> Found fork with " .. #validDirections .. " options at tile " .. currentTileId)
			end
			break
		end
	end

	if iteration >= maxIteration then
		print("[BoardSystem] WARNING: Max iteration reached for player " .. playerId ..
			". Possible infinite loop detected.")
	end

	-- ตรวจสอบว่าใช้ก้าวหมดหรือไม่
	local autoComplete = (remainingSteps == 0)

	if DEBUG_MOVEMENT then
		print("[BoardSystem] Path generation complete: " .. #path ..
			" steps, auto-complete: " .. tostring(autoComplete) ..
			", remaining steps: " .. remainingSteps)
	end

	-- ข้อมูลทางเดินที่จะส่งกลับ
	local pathInfo = {
		path = path,
		autoComplete = autoComplete,
		endTileId = path[#path],
		stepsRemaining = remainingSteps,
		endPrevTileId = path[#path-1] or currentPrevTileId
	}

	-- คำนวณทิศทางที่เลือกได้ ถ้ายังมีก้าวเหลือและไม่ใช่ตัน
	if remainingSteps > 0 then
		pathInfo.availableDirections = self:GetAvailableDirections(path[#path], path[#path-1] or currentPrevTileId)

		-- กรองทิศทางที่อาจจะวนกลับไปทางเดิม
		local filteredDirections = {}
		for _, dirInfo in ipairs(pathInfo.availableDirections) do
			if not visitedTiles[dirInfo.tileId] or #pathInfo.availableDirections <= 1 then
				table.insert(filteredDirections, dirInfo)
			end
		end

		-- ถ้าทุกทางเคยเดินผ่านหมดแล้ว ให้ใช้ทุกทาง
		if #filteredDirections > 0 then
			pathInfo.availableDirections = filteredDirections
		end
	else
		pathInfo.availableDirections = {}
	end

	return pathInfo
end

function BoardSystem:ProcessPlayerMove(playerId, diceResult)
	local currentTileId = self.playerPositions[playerId]
	local prevTileId = self.playerLastTile[playerId]

	if not currentTileId then return false end

	-- แสดงผลลัพธ์ลูกเต๋า
	if DEBUG_MOVEMENT then
		print("[BoardSystem] Player ID " .. playerId .. " rolled: " .. diceResult ..
			" from tile " .. currentTileId)
	end

	-- Store remaining steps
	self.playerRemainingSteps = self.playerRemainingSteps or {}
	self.playerRemainingSteps[playerId] = diceResult

	-- Generate auto path
	local pathInfo = self:GenerateAutoPath(playerId, currentTileId, prevTileId, diceResult)

	-- Store path for reference
	self.playerAutoPath[playerId] = pathInfo.path

	-- Set movement state and handle path
	if pathInfo.autoComplete then
		-- Auto-complete path
		self.playerMovementState[playerId] = "auto_complete"

		-- Move player to final tile
		if #pathInfo.path > 1 then
			self:SetPlayerPosition(playerId, pathInfo.endTileId, pathInfo.endPrevTileId)
		end

		-- Reset remaining steps
		self.playerRemainingSteps[playerId] = 0

		-- REMOVED: Trigger tile effect (จะถูกย้ายไปทำหลัง MovementVisualizationComplete)
		-- if self.onTileEffect then
		--	 self.onTileEffect(playerId, pathInfo.endTileId, self.tiles[pathInfo.endTileId])
		-- end

		-- Call path complete callback
		if self.onPlayerPathComplete then
			self.onPlayerPathComplete(playerId, pathInfo.endTileId)
		end

		return {
			autoPath = pathInfo.path,
			endTileId = pathInfo.endTileId,
			stepsRemaining = 0,
			availableDirections = {},
			requiresChoice = false,
			autoComplete = true
		}
	else
		-- Path to fork then requires choice
		self.playerMovementState[playerId] = "need_choice"

		-- Move player to last auto-path tile
		if #pathInfo.path > 1 then
			self:SetPlayerPosition(playerId, pathInfo.endTileId, pathInfo.endPrevTileId)
		end

		-- Update remaining steps
		self.playerRemainingSteps[playerId] = pathInfo.stepsRemaining

		-- แสดงจำนวนก้าวที่เหลือในทางเลือกแต่ละทาง
		if DEBUG_MOVEMENT then
			print("[BoardSystem] Player ID " .. playerId .. " needs to choose direction")
			print("[BoardSystem] Available directions: " .. #pathInfo.availableDirections)
			for i, dirInfo in ipairs(pathInfo.availableDirections) do
				print("  " .. i .. ". Direction: " .. dirInfo.direction ..
					", Tile: " .. dirInfo.tileId)
			end
			print("[BoardSystem] Steps remaining: " .. pathInfo.stepsRemaining)
		end

		-- เพิ่มข้อมูลจำนวนก้าวที่เหลือในแต่ละทางเลือก
		for i, dirInfo in ipairs(pathInfo.availableDirections) do
			dirInfo.stepsRemaining = pathInfo.stepsRemaining
		end

		-- REMOVED: Trigger tile effect (จะถูกย้ายไปทำหลัง MovementVisualizationComplete)
		-- if self.onTileEffect then
		--	 self.onTileEffect(playerId, pathInfo.endTileId, self.tiles[pathInfo.endTileId])
		-- end

		return {
			autoPath = pathInfo.path,
			endTileId = pathInfo.endTileId,
			stepsRemaining = pathInfo.stepsRemaining,
			availableDirections = pathInfo.availableDirections,
			requiresChoice = true,
			autoComplete = false
		}
	end
end

function BoardSystem:ProcessDirectionChoice(playerId, direction)
	local currentTileId = self.playerPositions[playerId]
	local prevTileId = self.playerLastTile[playerId]
	local stepsRemaining = self.playerRemainingSteps[playerId] or 0

	if DEBUG_MOVEMENT then
		print("[BoardSystem] ProcessDirectionChoice: Player " .. playerId ..
			" chose " .. direction .. ", from tile " .. currentTileId ..
			", with " .. stepsRemaining .. " steps remaining")
	end

	if stepsRemaining <= 0 then
		print("[BoardSystem] ERROR: No steps remaining but ProcessDirectionChoice was called")
		return false
	end

	-- Get next tile based on direction
	local nextTileId = self:GetNextTileFromDirection(currentTileId, direction, prevTileId)
	if not nextTileId then
		print("[BoardSystem] ERROR: No next tile found for direction " .. direction)
		return false
	end

	-- Move one step in chosen direction
	self:SetPlayerPosition(playerId, nextTileId, currentTileId)

	-- Reduce remaining steps
	stepsRemaining = stepsRemaining - 1
	self.playerRemainingSteps[playerId] = stepsRemaining

	if DEBUG_MOVEMENT then
		print("[BoardSystem] -> Moved to tile " .. nextTileId ..
			", remaining steps: " .. stepsRemaining)
	end

	-- Continue movement if steps remain
	if stepsRemaining > 0 then
		-- Generate new auto path from chosen tile
		local pathInfo = self:GenerateAutoPath(playerId, nextTileId, currentTileId, stepsRemaining)

		-- Update auto path
		self.playerAutoPath[playerId] = pathInfo.path

		if pathInfo.autoComplete then
			-- Auto-complete remaining path
			self.playerMovementState[playerId] = "auto_complete"

			-- Move player to final tile
			if #pathInfo.path > 1 then
				self:SetPlayerPosition(playerId, pathInfo.endTileId, pathInfo.endPrevTileId)
			end

			-- Reset remaining steps
			self.playerRemainingSteps[playerId] = 0

			-- REMOVED: Trigger tile effect
			-- if self.onTileEffect then
			--	 self.onTileEffect(playerId, pathInfo.endTileId, self.tiles[pathInfo.endTileId])
			-- end

			-- Call path complete callback
			if self.onPlayerPathComplete then
				self.onPlayerPathComplete(playerId, pathInfo.endTileId)
			end

			return {
				autoPath = pathInfo.path,
				endTileId = pathInfo.endTileId,
				stepsRemaining = 0,
				availableDirections = {},
				requiresChoice = false,
				autoComplete = true,
				moveComplete = true
			}
		else
			-- Path to next fork, requires another choice
			self.playerMovementState[playerId] = "need_choice"

			-- Move player to last auto-path tile
			if #pathInfo.path > 1 then
				self:SetPlayerPosition(playerId, pathInfo.endTileId, pathInfo.endPrevTileId)
			end

			-- Update remaining steps
			self.playerRemainingSteps[playerId] = pathInfo.stepsRemaining

			-- เพิ่มข้อมูลจำนวนก้าวที่เหลือในแต่ละทางเลือก
			for i, dirInfo in ipairs(pathInfo.availableDirections) do
				dirInfo.stepsRemaining = pathInfo.stepsRemaining
			end

			-- REMOVED: Trigger tile effect
			-- if self.onTileEffect then
			--	 self.onTileEffect(playerId, pathInfo.endTileId, self.tiles[pathInfo.endTileId])
			-- end

			return {
				autoPath = pathInfo.path,
				endTileId = pathInfo.endTileId,
				stepsRemaining = pathInfo.stepsRemaining,
				availableDirections = pathInfo.availableDirections,
				requiresChoice = true,
				autoComplete = false,
				moveComplete = false
			}
		end
	else
		-- Movement complete (used all steps)
		self.playerRemainingSteps[playerId] = 0
		self.playerMovementState[playerId] = "waiting"

		-- REMOVED: Trigger tile effect
		-- if self.onTileEffect then
		--	 self.onTileEffect(playerId, nextTileId, self.tiles[nextTileId])
		-- end

		-- Call path complete callback
		if self.onPlayerPathComplete then
			self.onPlayerPathComplete(playerId, nextTileId)
		end

		if DEBUG_MOVEMENT then
			print("[BoardSystem] Movement complete, all steps used")
		end

		return {
			autoPath = {currentTileId, nextTileId},
			endTileId = nextTileId,
			stepsRemaining = 0,
			availableDirections = {},
			requiresChoice = false,
			autoComplete = true,
			moveComplete = true
		}
	end
end

-- REMOVED: onTileEffect parameter
function BoardSystem:SetupCallbacks(onPlayerMoved, onPlayerPathComplete)
	self.onPlayerMoved = onPlayerMoved
	self.onPlayerPathComplete = onPlayerPathComplete
	-- REMOVED: self.onTileEffect = onTileEffect
end

return BoardSystem
