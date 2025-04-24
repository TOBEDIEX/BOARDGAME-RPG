-- LoadingScreenHandler.lua
-- Manages game loading screen and player status display
-- Version: 4.1.0 (Improved Transition Logic)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Debug mode
local DEBUG_MODE = false

-- Debug helper function
local function debugLog(message)
	if DEBUG_MODE then
		print("[LoadingScreenHandler] " .. message)
	end
end

-- Get current player
local player = Players.LocalPlayer
if not player then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	player = Players.LocalPlayer
end

-- UI References
local PlayerGui, LoadingScreen, Background, LoadingBarFrame, LoadingBarFill
local LoadingText, PlayersReadyText

-- RemoteEvents References
local remotes = {}

-- Loading state
local loadingState = {
	assetsProgress = 0,
	playersReady = 0,
	totalPlayers = 0,
	minRequired = 2,
	maxPlayers = 4,
	isAssetsLoaded = false,
	allPlayersReady = false, -- Server determines actual readiness
	assetLoadedSent = false,
	serverSignaledTransition = false, -- Flag to track server signal
	loadingComplete = false -- Tracks if client-side loading finished
}

-- Track connections
local connections = {}

-- UI animation settings
local tweenInfo = {
	fast = TweenInfo.new(0.2, Enum.EasingStyle.Quad),
	normal = TweenInfo.new(0.5, Enum.EasingStyle.Quad),
	slow = TweenInfo.new(0.8, Enum.EasingStyle.Quad)
}

-- Update frequency control
local lastUpdateTime = 0
local updateThreshold = 0.05 -- 50ms

-- Forward declaration of functions
local sendReadySignal, transitionToClassSelection

-- Ensure all other UI screens are disabled during loading
local function disableOtherScreens()
	if not PlayerGui then return end

	-- Make sure ClassSelection and other screens are hidden during loading
	local screens = {"ClassSelection", "MainGameUI", "GameOverScreen"}

	for _, screenName in ipairs(screens) do
		local screen = PlayerGui:FindFirstChild(screenName)
		if screen and screen:IsA("ScreenGui") then
			screen.Enabled = false
			debugLog("Disabled screen: " .. screenName)
		end
	end
end

-- Clean up connections
local function cleanupConnections()
	for _, connection in ipairs(connections) do
		if typeof(connection) == "RBXScriptConnection" and connection.Connected then
			connection:Disconnect()
		end
	end
	connections = {}
	debugLog("Cleaned up all connections")
end

-- Helper to create tweens
local function createTween(object, properties, duration)
	local tweenInfo = TweenInfo.new(duration or 0.5, Enum.EasingStyle.Quad)
	return TweenService:Create(object, tweenInfo, properties)
end

-- Initialize UI with validation
local function initializeUI()
	debugLog("Initializing UI")

	-- Get PlayerGui with validation
	PlayerGui = player:WaitForChild("PlayerGui", 10)
	if not PlayerGui then
		warn("LoadingScreenHandler: PlayerGui not found")
		return false
	end

	-- Get LoadingScreen UI
	LoadingScreen = PlayerGui:WaitForChild("LoadingScreen", 5)
	if not LoadingScreen then
		warn("LoadingScreenHandler: LoadingScreen not found")
		return false
	end

	-- Get UI components
	Background = LoadingScreen:WaitForChild("Background", 3)
	if not Background then return false end

	LoadingBarFrame = Background:WaitForChild("LoadingBarFrame", 2)
	LoadingBarFill = LoadingBarFrame and LoadingBarFrame:WaitForChild("LoadingBarFill", 1)
	LoadingText = Background:WaitForChild("LoadingText", 2)
	PlayersReadyText = Background:WaitForChild("PlayersReadyText", 2)

	-- Verify all essential UI components
	if not LoadingBarFill or not LoadingText or not PlayersReadyText then
		warn("LoadingScreenHandler: Some UI components missing")
		return false
	end

	-- Set initial values
	LoadingBarFill.Size = UDim2.new(0, 0, 1, 0)
	LoadingText.Text = "Loading game... 0%"
	PlayersReadyText.Text = "Players ready: 0/0"
	PlayersReadyText.TextColor3 = Color3.fromRGB(255, 255, 0) -- Yellow initially

	-- *** CRITICAL: Ensure LoadingScreen is enabled and others are disabled ***
	LoadingScreen.Enabled = true
	disableOtherScreens()

	debugLog("UI initialized successfully")
	return true
end

-- Connect to RemoteEvents
local function connectRemoteEvents()
	debugLog("Connecting to remote events")

	-- Get RemoteEvents folders
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then return false end

	local uiRemotes = remotesFolder:WaitForChild("UIRemotes", 5)
	local gameRemotes = remotesFolder:WaitForChild("GameRemotes", 5)
	if not uiRemotes or not gameRemotes then return false end

	-- Reference RemoteEvents
	remotes.updateLoading = uiRemotes:WaitForChild("UpdateLoading", 3) -- Server might send progress updates
	remotes.updatePlayersReady = uiRemotes:WaitForChild("UpdatePlayersReady", 3)
	remotes.showClassSelection = uiRemotes:WaitForChild("ShowClassSelection", 3) -- *** Signal to transition ***
	remotes.assetsLoaded = gameRemotes:WaitForChild("AssetsLoaded", 3) -- Client sends this when done

	-- Validate connections
	if not remotes.updateLoading or not remotes.updatePlayersReady or
		not remotes.showClassSelection or not remotes.assetsLoaded then
		warn("LoadingScreenHandler: Some RemoteEvents missing")
		return false
	end

	debugLog("Remote events connected successfully")
	return true
end

-- Update loading progress with debounce
local function updateLoadingProgress(progress)
	-- Control update frequency
	local currentTime = tick()
	if currentTime - lastUpdateTime < updateThreshold then return end
	lastUpdateTime = currentTime

	-- Clamp progress between 0 and 1
	progress = math.clamp(progress, 0, 1)
	loadingState.assetsProgress = progress

	debugLog("Updating loading progress: " .. math.floor(progress * 100) .. "%")

	-- Update LoadingBar with tween
	if LoadingBarFill then
		createTween(LoadingBarFill, {Size = UDim2.new(progress, 0, 1, 0)}, 0.2):Play()
	end

	-- Update text
	if LoadingText then
		LoadingText.Text = "Loading game... " .. math.floor(progress * 100) .. "%"
	end

	-- Check if loading complete
	if progress >= 1 and not loadingState.loadingComplete then
		loadingState.isAssetsLoaded = true
		loadingState.loadingComplete = true -- Mark client-side loading as done
		if LoadingText then
			LoadingText.Text = "Loading complete! Waiting for server..."
			LoadingText.TextColor3 = Color3.fromRGB(150, 255, 150) -- Light green
		end
		debugLog("Client-side asset loading finished.")
		sendReadySignal() -- Send signal now that client is done
	end
end

-- Update player ready status (from server)
local function updatePlayersReadyStatus(playersReady, totalPlayers)
	-- Validate received values
	if type(playersReady) ~= "number" or type(totalPlayers) ~= "number" then return end

	-- Skip updates if no changes
	if loadingState.playersReady == playersReady and loadingState.totalPlayers == totalPlayers then
		return
	end

	debugLog("Updating players ready (from server): " .. playersReady .. "/" .. totalPlayers)

	-- Record new state
	loadingState.playersReady = playersReady
	loadingState.totalPlayers = totalPlayers

	-- Update text
	if PlayersReadyText then
		PlayersReadyText.Text = "Players ready: " .. playersReady .. "/" .. totalPlayers
	end

	-- Update text color based on server status (more reliable)
	if PlayersReadyText then
		if playersReady >= totalPlayers and totalPlayers >= loadingState.minRequired then
			PlayersReadyText.TextColor3 = Color3.fromRGB(0, 255, 0) -- Green
		elseif totalPlayers < loadingState.minRequired then
			PlayersReadyText.TextColor3 = Color3.fromRGB(255, 0, 0) -- Red
		else
			PlayersReadyText.TextColor3 = Color3.fromRGB(255, 255, 0) -- Yellow
		end
	end

	-- Note: No transition logic here. Transition is handled by ShowClassSelection event.
end

-- Send ready signal to Server
sendReadySignal = function()
	if not remotes.assetsLoaded then return false end

	-- Only send if assets are loaded and haven't sent before
	if loadingState.isAssetsLoaded and not loadingState.assetLoadedSent then
		debugLog("Sending assets loaded signal to server")
		remotes.assetsLoaded:FireServer()
		loadingState.assetLoadedSent = true -- Mark as sent
		return true
	end

	return false
end

-- Transition to class selection (Called ONLY by ShowClassSelection event)
transitionToClassSelection = function()
	-- Prevent multiple transitions
	if loadingState.serverSignaledTransition then
		debugLog("Transition already in progress or completed.")
		return
	end
	loadingState.serverSignaledTransition = true -- Set flag immediately

	debugLog("Received ShowClassSelection signal. Transitioning...")

	-- Fade out LoadingScreen
	local fadeOutTween = createTween(Background, {BackgroundTransparency = 1}, 0.5)
	fadeOutTween:Play()

	fadeOutTween.Completed:Connect(function()
		-- Disable LoadingScreen *after* fade
		LoadingScreen.Enabled = false
		debugLog("LoadingScreen disabled.")

		-- Look for class selection screen
		local ClassSelection = PlayerGui:FindFirstChild("ClassSelection") -- Use FindFirstChild, it might be disabled
		if ClassSelection then
			debugLog("Found ClassSelection screen. Enabling...")
			-- Set properties before enabling to avoid flashing
			local classBackground = ClassSelection:FindFirstChild("Background")
			if classBackground then
				classBackground.BackgroundTransparency = 1 -- Start transparent
			end

			-- Enable class selection with fade in
			ClassSelection.Enabled = true -- *** Enable it NOW ***

			if classBackground then
				createTween(classBackground, {BackgroundTransparency = 0}, 0.5):Play()
			end

			debugLog("Class selection screen shown and faded in.")
		else
			warn("LoadingScreenHandler: Class selection screen not found during transition")
		end

		-- Clean up loading connections
		cleanupConnections()
	end)
end

-- Load assets with progress display
local function preloadAssets()
	-- Start loading
	updateLoadingProgress(0)
	debugLog("Starting asset preloading")

	-- Group assets by type
	local assetsToLoad = {} -- Simpler list

	-- Find main UIs to preload
	local uiToPreload = {
		PlayerGui:FindFirstChild("ClassSelection"),
		PlayerGui:FindFirstChild("MainGameUI"),
		PlayerGui:FindFirstChild("PopupUI"),
		PlayerGui:FindFirstChild("GameOverScreen")
	}

	-- Collect assets
	for _, ui in ipairs(uiToPreload) do
		if ui then
			for _, descendant in ipairs(ui:GetDescendants()) do
				-- Preload common asset types
				if descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") or
					descendant:IsA("Sound") or descendant:IsA("MeshPart") or
					descendant:IsA("SpecialMesh") or descendant:IsA("Decal") or
					descendant:IsA("Texture") or descendant:IsA("Script") or
					descendant:IsA("LocalScript") or descendant:IsA("ModuleScript") then
					table.insert(assetsToLoad, descendant)
				end
			end
		end
	end

	-- Add other critical assets if needed (e.g., from ReplicatedStorage)

	local totalAssets = #assetsToLoad
	debugLog("Found " .. totalAssets .. " assets to preload")

	-- If no assets to load
	if totalAssets == 0 then
		debugLog("No assets found to preload.")
		updateLoadingProgress(1) -- Mark as complete
		return
	end

	-- Use ContentProvider:PreloadAsync with progress tracking
	local loadedAssets = 0
	local preloadConnection = nil

	-- Use a coroutine for preloading
	coroutine.wrap(function()
		local success, err = pcall(function()
			ContentProvider:PreloadAsync(assetsToLoad, function(assetId, status)
				if status == Enum.AssetFetchStatus.Success or status == Enum.AssetFetchStatus.Failure then
					loadedAssets = loadedAssets + 1
					local progress = loadedAssets / totalAssets
					-- Update progress on the main thread using spawn or bindable event if needed
					task.spawn(updateLoadingProgress, progress)
				end
			end)
		end)

		if not success then
			warn("Asset preloading failed:", err)
			-- Still mark as loaded to proceed, but log the error
			task.spawn(updateLoadingProgress, 1)
		else
			debugLog("Asset preloading complete (via PreloadAsync callback).")
			-- Ensure 100% is shown if callback didn't quite reach it
			if loadingState.assetsProgress < 1 then
				task.spawn(updateLoadingProgress, 1)
			end
		end
	end)()

	-- Fallback timer in case PreloadAsync hangs or doesn't report fully
	local startTime = tick()
	local maxTime = 15 -- Max time before forcing completion
	preloadConnection = RunService.Heartbeat:Connect(function()
		if loadingState.loadingComplete then
			preloadConnection:Disconnect()
			preloadConnection = nil
			return
		end

		local elapsed = tick() - startTime
		if elapsed > maxTime then
			warn("Preloading timed out after " .. maxTime .. "s. Forcing completion.")
			preloadConnection:Disconnect()
			preloadConnection = nil
			updateLoadingProgress(1) -- Force complete
		end
	end)
	table.insert(connections, preloadConnection)
end


-- Setup event connections
local function setupEventConnections()
	-- Clear previous connections
	cleanupConnections()
	debugLog("Setting up event connections")

	-- Connect to RemoteEvents
	-- Note: UpdateLoading might not be needed if progress is client-driven
	-- if remotes.updateLoading then
	-- 	local connection = remotes.updateLoading.OnClientEvent:Connect(updateLoadingProgress)
	-- 	table.insert(connections, connection)
	-- end

	if remotes.updatePlayersReady then
		local connection = remotes.updatePlayersReady.OnClientEvent:Connect(updatePlayersReadyStatus)
		table.insert(connections, connection)
	end

	-- *** CRITICAL: Listen for the server signal to transition ***
	if remotes.showClassSelection then
		local connection = remotes.showClassSelection.OnClientEvent:Connect(transitionToClassSelection)
		table.insert(connections, connection)
		debugLog("Connected to ShowClassSelection event.")
	end

	-- Track player count changes locally (for UI text updates)
	local function updateLocalPlayerCount()
		local currentPlayers = #Players:GetPlayers()
		-- Only update totalPlayers if it differs, let server control ready count
		if loadingState.totalPlayers ~= currentPlayers then
			updatePlayersReadyStatus(loadingState.playersReady, currentPlayers)
		end
	end

	local connection = Players.PlayerAdded:Connect(updateLocalPlayerCount)
	table.insert(connections, connection)

	connection = Players.PlayerRemoving:Connect(function()
		task.wait() -- Wait a frame for player list to update
		updateLocalPlayerCount()
	end)
	table.insert(connections, connection)

	-- F9 key to accelerate loading (for testing)
	connection = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.F9 and not loadingState.loadingComplete then
			debugLog("F9 pressed - fast-forwarding loading")
			updateLoadingProgress(1) -- Force client loading complete
		end
	end)
	table.insert(connections, connection)

	debugLog("Event connections setup complete")
end

-- Main initialization
local function initialize()
	debugLog("Initializing LoadingScreenHandler")

	-- Setup UI (Ensures LoadingScreen is enabled, others disabled)
	if not initializeUI() then
		warn("LoadingScreenHandler: Unable to initialize UI")
		return
	end

	-- Connect to RemoteEvents
	if not connectRemoteEvents() then
		warn("LoadingScreenHandler: Unable to connect to RemoteEvents")
		return
	end

	-- Setup event connections (Crucially connects ShowClassSelection)
	setupEventConnections()

	-- Start loading assets (Will call updateLoadingProgress and sendReadySignal when done)
	preloadAssets()

	-- No automatic transition logic here anymore. Waiting for server signal.

	debugLog("LoadingScreenHandler initialization complete. Waiting for assets and server signal.")
end

-- Cleanup on player leave
Players.PlayerRemoving:Connect(function(plr)
	if plr == player then
		cleanupConnections()
	end
end)

-- Enable debug mode
local function enableDebugMode(enable)
	DEBUG_MODE = enable
	debugLog("Debug mode " .. (enable and "enabled" or "disabled"))
	return DEBUG_MODE
end

-- Start system
initialize()

-- Export public functions
local LoadingScreenHandler = {
	EnableDebug = enableDebugMode,
	-- ForceTransition removed, should be server-driven
}

return LoadingScreenHandler
