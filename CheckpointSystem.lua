-- CheckpointSystem.lua
-- Module for managing player checkpoints and respawn points
-- Version: 1.0.0

local CheckpointSystem = {}
CheckpointSystem.__index = CheckpointSystem

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Constants
local DEFAULT_SPAWN_TILE_ID = 1
local DEBUG = true

function CheckpointSystem.new()
	local self = setmetatable({}, CheckpointSystem)

	-- Store player checkpoint data
	-- Format: {userId = {tileId = checkpointTileId, position = Vector3}}
	self.playerCheckpoints = {}

	-- Initialize remote events
	self:InitializeRemotes()

	return self
end

function CheckpointSystem:InitializeRemotes()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	-- Create CheckpointRemotes folder if it doesn't exist
	local checkpointRemotes = remotes:FindFirstChild("CheckpointRemotes")
	if not checkpointRemotes then
		checkpointRemotes = Instance.new("Folder")
		checkpointRemotes.Name = "CheckpointRemotes"
		checkpointRemotes.Parent = remotes
	end

	-- Set Checkpoint remote event
	self.setCheckpointRemote = checkpointRemotes:FindFirstChild("SetCheckpoint")
	if not self.setCheckpointRemote then
		self.setCheckpointRemote = Instance.new("RemoteEvent")
		self.setCheckpointRemote.Name = "SetCheckpoint"
		self.setCheckpointRemote.Parent = checkpointRemotes
	end

	-- Show Checkpoint Dialog remote event
	self.showCheckpointDialogRemote = checkpointRemotes:FindFirstChild("ShowCheckpointDialog")
	if not self.showCheckpointDialogRemote then
		self.showCheckpointDialogRemote = Instance.new("RemoteEvent")
		self.showCheckpointDialogRemote.Name = "ShowCheckpointDialog"
		self.showCheckpointDialogRemote.Parent = checkpointRemotes
	end

	-- Connect client response
	self.setCheckpointRemote.OnServerEvent:Connect(function(player, tileId, confirmed)
		self:HandleCheckpointResponse(player, tileId, confirmed)
	end)

	if DEBUG then
		print("[CheckpointSystem] Remote events initialized")
	end
end

-- Check if a tile is a checkpoint tile
function CheckpointSystem:IsCheckpointTile(tileId, tileType)
	-- Castle tiles are checkpoints
	if tileType == "castle" then
		return true
	end

	-- Get MapData to check tile types
	local success, mapData = pcall(function()
		return require(game:GetService("ServerStorage").GameData.MapData)
	end)

	if success and mapData and mapData.specialAreas and mapData.specialAreas.castle then
		for _, castleTileId in ipairs(mapData.specialAreas.castle) do
			if tileId == castleTileId then
				return true
			end
		end
	end

	return false
end

-- Handle player landing on a potential checkpoint tile
function CheckpointSystem:OnPlayerLandedOnTile(player, tileId, tileType)
	if self:IsCheckpointTile(tileId, tileType) then
		if DEBUG then
			print("[CheckpointSystem] Player " .. player.Name .. " landed on checkpoint tile " .. tileId)
		end

		-- Get tile position
		local tilePosition = nil
		local boardSystem = _G.BoardSystem
		if boardSystem and boardSystem.GetTilePosition then
			tilePosition = boardSystem:GetTilePosition(tileId)
		end

		-- Show dialog to player
		self.showCheckpointDialogRemote:FireClient(player, tileId, tilePosition)
	end
end

-- Handle player response to checkpoint dialog
function CheckpointSystem:HandleCheckpointResponse(player, tileId, confirmed)
	local userId = player.UserId

	if confirmed then
		if DEBUG then
			print("[CheckpointSystem] Player " .. player.Name .. " set checkpoint at tile " .. tileId)
		end

		-- Get tile position
		local tilePosition = nil
		local boardSystem = _G.BoardSystem
		if boardSystem and boardSystem.GetTilePosition then
			tilePosition = boardSystem:GetTilePosition(tileId)
		end

		-- Set checkpoint
		self.playerCheckpoints[userId] = {
			tileId = tileId,
			position = tilePosition
		}
	else
		if DEBUG then
			print("[CheckpointSystem] Player " .. player.Name .. " declined checkpoint at tile " .. tileId)
		end
	end
end

-- Get player respawn tile ID
function CheckpointSystem:GetPlayerRespawnTileId(player)
	local userId = player.UserId
	local checkpoint = self.playerCheckpoints[userId]

	if checkpoint then
		return checkpoint.tileId
	else
		return DEFAULT_SPAWN_TILE_ID
	end
end

-- Get player respawn position
function CheckpointSystem:GetPlayerRespawnPosition(player)
	local userId = player.UserId
	local checkpoint = self.playerCheckpoints[userId]

	if checkpoint and checkpoint.position then
		return checkpoint.position
	else
		-- Get default spawn position from board tile 1
		local boardSystem = _G.BoardSystem
		if boardSystem and boardSystem.GetTilePosition then
			return boardSystem:GetTilePosition(DEFAULT_SPAWN_TILE_ID)
		else
			-- Fallback to hardcoded position if needed
			return Vector3.new(35.778, 0.6, -15.24) -- Default position from MapData
		end
	end
end

-- Reset player checkpoint
function CheckpointSystem:ResetPlayerCheckpoint(player)
	local userId = player.UserId
	self.playerCheckpoints[userId] = nil
end

-- Reset all player checkpoints
function CheckpointSystem:ResetAllCheckpoints()
	self.playerCheckpoints = {}
end

return CheckpointSystem
