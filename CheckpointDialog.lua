-- CheckpointDialog.client.lua
-- Client-side handler for checkpoint dialog
-- Version: 1.0.1 (Fixed notification UI)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local PopupUI = PlayerGui:WaitForChild("PopupUI")

-- Get remote events
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local checkpointRemotes = remotes:WaitForChild("CheckpointRemotes", 10)
if not checkpointRemotes then
	-- Create the folder if it's not found after timeout
	checkpointRemotes = Instance.new("Folder")
	checkpointRemotes.Name = "CheckpointRemotes"
	checkpointRemotes.Parent = remotes

	-- Create required events
	local setCheckpoint = Instance.new("RemoteEvent")
	setCheckpoint.Name = "SetCheckpoint"
	setCheckpoint.Parent = checkpointRemotes

	local showDialog = Instance.new("RemoteEvent")
	showDialog.Name = "ShowCheckpointDialog"
	showDialog.Parent = checkpointRemotes
end

local setCheckpointRemote = checkpointRemotes:WaitForChild("SetCheckpoint")
local showCheckpointDialogRemote = checkpointRemotes:WaitForChild("ShowCheckpointDialog")

-- Create checkpoint dialog UI if it doesn't exist
local function createCheckpointDialogUI()
	local existingDialog = PopupUI:FindFirstChild("CheckpointDialog")
	if existingDialog then
		return existingDialog
	end

	local dialog = Instance.new("Frame")
	dialog.Name = "CheckpointDialog"
	dialog.Size = UDim2.new(0, 400, 0, 200)
	dialog.Position = UDim2.new(0.5, -200, 0.5, -100)
	dialog.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	dialog.BorderSizePixel = 0
	dialog.Visible = false
	dialog.Parent = PopupUI
	dialog.ZIndex = 10

	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, 10)
	uiCorner.Parent = dialog

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, 0, 0, 40)
	titleLabel.Position = UDim2.new(0, 0, 0, 10)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Checkpoint"
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 24
	titleLabel.ZIndex = 11
	titleLabel.Parent = dialog

	local messageLabel = Instance.new("TextLabel")
	messageLabel.Name = "MessageLabel"
	messageLabel.Size = UDim2.new(1, -40, 0, 60)
	messageLabel.Position = UDim2.new(0, 20, 0, 50)
	messageLabel.BackgroundTransparency = 1
	messageLabel.Text = "Do you want to set this location as your checkpoint? When you die, you'll respawn at this point instead of the starting point."
	messageLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	messageLabel.Font = Enum.Font.Gotham
	messageLabel.TextSize = 16
	messageLabel.TextWrapped = true
	messageLabel.ZIndex = 11
	messageLabel.Parent = dialog

	local yesButton = Instance.new("TextButton")
	yesButton.Name = "YesButton"
	yesButton.Size = UDim2.new(0, 150, 0, 50)
	yesButton.Position = UDim2.new(0.25, -75, 1, -70)
	yesButton.BackgroundColor3 = Color3.fromRGB(45, 150, 45)
	yesButton.Text = "YES"
	yesButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	yesButton.Font = Enum.Font.GothamBold
	yesButton.TextSize = 20
	yesButton.ZIndex = 11
	yesButton.Parent = dialog

	local yesCorner = Instance.new("UICorner")
	yesCorner.CornerRadius = UDim.new(0, 6)
	yesCorner.Parent = yesButton

	local noButton = Instance.new("TextButton")
	noButton.Name = "NoButton"
	noButton.Size = UDim2.new(0, 150, 0, 50)
	noButton.Position = UDim2.new(0.75, -75, 1, -70)
	noButton.BackgroundColor3 = Color3.fromRGB(150, 45, 45)
	noButton.Text = "NO"
	noButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	noButton.Font = Enum.Font.GothamBold
	noButton.TextSize = 20
	noButton.ZIndex = 11
	noButton.Parent = dialog

	local noCorner = Instance.new("UICorner")
	noCorner.CornerRadius = UDim.new(0, 6)
	noCorner.Parent = noButton

	-- Add a semi-transparent background overlay
	local overlay = PopupUI:FindFirstChild("DialogOverlay")
	if not overlay then
		overlay = Instance.new("Frame")
		overlay.Name = "DialogOverlay"
		overlay.Size = UDim2.new(1, 0, 1, 0)
		overlay.Position = UDim2.new(0, 0, 0, 0)
		overlay.BackgroundColor3 = Color3.new(0, 0, 0)
		overlay.BackgroundTransparency = 0.5
		overlay.Visible = false
		overlay.ZIndex = 9
		overlay.Parent = PopupUI
	end

	return dialog, overlay
end

-- Show checkpoint dialog
local function showCheckpointDialog(tileId, tilePosition)
	local dialog, overlay = createCheckpointDialogUI()

	-- Reset previous connections
	local yesButton = dialog:FindFirstChild("YesButton")
	local noButton = dialog:FindFirstChild("NoButton")

	local function closeDialog()
		dialog.Visible = false
		if overlay then overlay.Visible = false end
	end

	-- Set up new button connections
	yesButton.MouseButton1Click:Connect(function()
		closeDialog()
		setCheckpointRemote:FireServer(tileId, true)

		-- Show notification
		local notif = Instance.new("TextLabel")
		notif.Size = UDim2.new(0, 300, 0, 50)
		notif.Position = UDim2.new(0.5, -150, 0.8, 0)
		notif.AnchorPoint = Vector2.new(0, 0)
		notif.BackgroundColor3 = Color3.fromRGB(45, 150, 45)
		notif.TextColor3 = Color3.fromRGB(255, 255, 255)
		notif.Text = "✓ Checkpoint set successfully!"
		notif.Font = Enum.Font.GothamBold
		notif.TextSize = 16
		notif.BackgroundTransparency = 0.2
		notif.ZIndex = 100

		local notifCorner = Instance.new("UICorner")
		notifCorner.CornerRadius = UDim.new(0, 8)
		notifCorner.Parent = notif

		-- Find a suitable parent for the notification
		local targetParent = nil

		-- Option 1: Use PopupUI if it exists
		if PopupUI then
			targetParent = PopupUI
		else
			-- Option 2: Find an existing ScreenGui
			for _, child in pairs(PlayerGui:GetChildren()) do
				if child:IsA("ScreenGui") then
					targetParent = child
					break
				end
			end

			-- Option 3: Create a new ScreenGui if none found
			if not targetParent then
				targetParent = Instance.new("ScreenGui")
				targetParent.Name = "NotificationGui" 
				targetParent.ResetOnSpawn = false
				targetParent.Parent = PlayerGui
			end
		end

		-- Set the parent of the notification
		notif.Parent = targetParent

		-- Remove after 3 seconds
		game:GetService("Debris"):AddItem(notif, 3)
	end)

	noButton.MouseButton1Click:Connect(function()
		closeDialog()
		setCheckpointRemote:FireServer(tileId, false)
	end)

	-- Show dialog with animation
	if overlay then overlay.Visible = true end
	dialog.Visible = true
	dialog.Position = UDim2.new(0.5, -200, 0.6, -100)
	dialog.BackgroundTransparency = 1

	for _, child in pairs(dialog:GetChildren()) do
		if child:IsA("GuiObject") and (child:IsA("TextLabel") or child:IsA("TextButton")) then
			child.BackgroundTransparency = 1
			child.TextTransparency = 1
		end
	end

	-- Create and play tween
	local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(dialog, tweenInfo, {
		Position = UDim2.new(0.5, -200, 0.5, -100),
		BackgroundTransparency = 0
	})
	tween:Play()

	for _, child in pairs(dialog:GetChildren()) do
		if child:IsA("GuiObject") and (child:IsA("TextLabel") or child:IsA("TextButton")) then
			local childTween = TweenService:Create(child, tweenInfo, {
				BackgroundTransparency = child.BackgroundTransparency == 1 and 1 or 0,
				TextTransparency = 0
			})
			childTween:Play()
		end
	end
end

-- Connect remote event
showCheckpointDialogRemote.OnClientEvent:Connect(function(tileId, tilePosition)
	showCheckpointDialog(tileId, tilePosition)
end)

print("[CheckpointDialog] Client-side handler initialized")
