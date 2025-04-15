-- ItemTileHandler.client.lua
-- ตัวจัดการเหตุการณ์ช่อง Item ฝั่งไคลเอนต์
-- Version: 1.1.0 - แก้ไขการทำงานของ Discard Button

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Constants
local ITEM_COLOR = Color3.fromRGB(100, 255, 100)
local NOTIFY_DURATION = 3
local CARD_ANIMATION_DURATION = 1.5

-- Get local player
local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- State
local state = {
	isProcessingItemCard = false,
	pendingItemCardQueue = {},
	pendingKey = nil -- เพิ่มตัวแปรเก็บคีย์สำหรับอ้างอิงไอเทมที่กำลังรอการยืนยัน
}

-- Remote events
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local eventTileRemotes = remotes:FindFirstChild("EventTileRemotes")
if not eventTileRemotes then
	eventTileRemotes = Instance.new("Folder")
	eventTileRemotes.Name = "EventTileRemotes"
	eventTileRemotes.Parent = remotes
end

local itemEventRemote = eventTileRemotes:FindFirstChild("ItemEvent")
if not itemEventRemote then
	itemEventRemote = Instance.new("RemoteEvent")
	itemEventRemote.Name = "ItemEvent"
	itemEventRemote.Parent = eventTileRemotes
end

-- Helper functions
local function tweenUI(obj, duration, properties, style, direction, onComplete)
	style = style or Enum.EasingStyle.Quad
	direction = direction or Enum.EasingDirection.Out

	local tween = TweenService:Create(
		obj, 
		TweenInfo.new(duration, style, direction), 
		properties
	)

	if onComplete then tween.Completed:Connect(onComplete) end
	tween:Play()
	return tween
end

local function playSound(parent, soundId, volume)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.5
	sound.Parent = parent
	sound:Play()

	-- ลบเสียงหลังจากเล่นเสร็จ
	sound.Ended:Connect(function()
		sound:Destroy()
	end)

	return sound
end

-- Create notification
local function createNotification(message, duration, color)
	duration = duration or NOTIFY_DURATION
	color = color or ITEM_COLOR

	local notification = Instance.new("Frame")
	notification.Name = "ItemNotification"
	notification.Size = UDim2.new(0, 280, 0, 60)
	notification.Position = UDim2.new(0.5, 0, -0.2, 0)
	notification.AnchorPoint = Vector2.new(0.5, 0)
	notification.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	notification.BackgroundTransparency = 0.2
	notification.BorderSizePixel = 0

	-- Add UI Elements
	local corner = Instance.new("UICorner", notification)
	corner.CornerRadius = UDim.new(0, 8)

	local icon = Instance.new("ImageLabel", notification)
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 32, 0, 32)
	icon.Position = UDim2.new(0, 14, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.BackgroundTransparency = 1
	icon.Image = "rbxassetid://6675226918" -- Item icon

	local textLabel = Instance.new("TextLabel", notification)
	textLabel.Name = "Message"
	textLabel.Size = UDim2.new(1, -60, 1, 0)
	textLabel.Position = UDim2.new(0, 56, 0, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = message
	textLabel.Font = Enum.Font.GothamSemibold
	textLabel.TextSize = 16
	textLabel.TextColor3 = color
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextWrapped = true

	notification.Parent = PlayerGui

	-- Show and hide notification
	tweenUI(notification, 0.5, {Position = UDim2.new(0.5, 0, 0.05, 0)}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	task.delay(duration, function()
		tweenUI(notification, 0.5, {Position = UDim2.new(0.5, 0, -0.2, 0)}, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 
		function() 
			notification:Destroy() 
		end)
	end)

	return notification
end

-- Find ItemCardGui
local function findItemCardUI()
	-- Look directly in PlayerGui
	local itemCardUI = PlayerGui:FindFirstChild("ItemCardGui")
	if itemCardUI then return itemCardUI end

	-- Look in all ScreenGuis
	for _, gui in pairs(PlayerGui:GetChildren()) do
		if gui:IsA("ScreenGui") then
			itemCardUI = gui:FindFirstChild("ItemCardGui")
			if itemCardUI then return itemCardUI end

			-- Look deeper
			for _, child in pairs(gui:GetChildren()) do
				if child.Name == "ItemCardGui" then
					return child
				end
			end
		end
	end

	print("[ItemTileHandler] ItemCardGui ไม่พบใน PlayerGui")
	return nil
end

-- Play card reveal animation
local function playCardRevealAnimation(frame, onComplete)
	if not frame then 
		if onComplete then onComplete() end
		return 
	end

	-- Store original values
	local originalRotation = frame.Rotation or 0
	local originalSize = frame.Size
	local originalPosition = frame.Position
	local originalTransparency = frame.BackgroundTransparency or 0

	-- Create card back
	local cardBack = Instance.new("Frame")
	cardBack.Name = "CardBack"
	cardBack.Size = originalSize
	cardBack.Position = originalPosition
	cardBack.AnchorPoint = frame.AnchorPoint
	cardBack.BackgroundColor3 = Color3.fromRGB(30, 120, 30)
	cardBack.ZIndex = frame.ZIndex + 1
	cardBack.Parent = frame.Parent

	-- Add design elements
	local pattern = Instance.new("ImageLabel")
	pattern.Name = "CardPattern"
	pattern.Size = UDim2.fromScale(0.8, 0.8)
	pattern.Position = UDim2.fromScale(0.5, 0.5)
	pattern.AnchorPoint = Vector2.new(0.5, 0.5)
	pattern.BackgroundTransparency = 1
	pattern.Image = "rbxassetid://6127039592"
	pattern.ImageColor3 = Color3.fromRGB(220, 255, 220)
	pattern.ImageTransparency = 0.7
	pattern.ZIndex = cardBack.ZIndex + 1
	pattern.Parent = cardBack

	local border = Instance.new("UIStroke")
	border.Color = Color3.fromRGB(100, 255, 100)
	border.Thickness = 3
	border.Parent = cardBack

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = cardBack

	-- Hide main frame
	frame.Visible = false

	-- Set starting position
	cardBack.Rotation = 180
	cardBack.Size = UDim2.new(
		originalSize.X.Scale, originalSize.X.Offset * 0.8,
		originalSize.Y.Scale, originalSize.Y.Offset * 0.8
	)

	-- Play card flip sound
	playSound(cardBack, "rbxassetid://6732897163", 0.5)

	-- Card shuffle animation
	local numShuffle = 5
	local shuffleDelay = 0.1

	for i = 1, numShuffle do
		task.delay(i * shuffleDelay, function()
			local offsetX = math.random(-10, 10)
			local offsetY = math.random(-10, 10)

			tweenUI(cardBack, shuffleDelay, {
				Position = UDim2.new(
					originalPosition.X.Scale, originalPosition.X.Offset + offsetX,
					originalPosition.Y.Scale, originalPosition.Y.Offset + offsetY
				),
				Rotation = originalRotation + math.random(-15, 15)
			})
		end)
	end

	-- Flip card after shuffle
	task.delay(numShuffle * shuffleDelay + 0.2, function()
		-- Return to original position
		tweenUI(cardBack, 0.3, {
			Position = originalPosition,
			Rotation = 0
		}, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function()
			-- Play card flip sound
			playSound(cardBack, "rbxassetid://5852130173", 0.7)

			-- Card disappear animation
			tweenUI(cardBack, 0.4, {
				Size = UDim2.new(
					originalSize.X.Scale, originalSize.X.Offset * 0.1,
					originalSize.Y.Scale, originalSize.Y.Offset
				),
				Rotation = 90
			}, Enum.EasingStyle.Back, Enum.EasingDirection.In, function()
				-- Remove card back
				cardBack:Destroy()

				-- Show front card
				frame.Visible = true
				frame.Rotation = 90
				frame.Size = UDim2.new(
					originalSize.X.Scale, originalSize.X.Offset * 0.1,
					originalSize.Y.Scale, originalSize.Y.Offset
				)

				-- Front card reveal animation
				tweenUI(frame, 0.4, {
					Rotation = 0,
					Size = originalSize,
					BackgroundTransparency = originalTransparency
				}, Enum.EasingStyle.Back, Enum.EasingDirection.Out, function()
					-- Play sparkle sound
					playSound(frame, "rbxassetid://5852296378", 0.5)

					-- Create sparkle effects
					for i = 1, 8 do
						task.delay(i * 0.05, function()
							local sparkle = Instance.new("Frame")
							sparkle.Name = "Sparkle" .. i
							sparkle.Size = UDim2.fromOffset(5, 5)
							sparkle.Position = UDim2.fromScale(math.random(), math.random())
							sparkle.AnchorPoint = Vector2.new(0.5, 0.5)
							sparkle.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
							sparkle.BackgroundTransparency = 0
							sparkle.ZIndex = frame.ZIndex + 5

							local corner = Instance.new("UICorner")
							corner.CornerRadius = UDim.new(1, 0)
							corner.Parent = sparkle

							sparkle.Parent = frame

							tweenUI(sparkle, 0.5, {
								Size = UDim2.fromOffset(20, 20),
								Position = UDim2.fromScale(0.5, 0.5),
								BackgroundTransparency = 1
							}, nil, nil, function()
								sparkle:Destroy()
								if i == 8 and onComplete then onComplete() end
							end)
						end)
					end
				end)
			end)
		end)
	end)
end

-- ค้นหาองค์ประกอบใน UI
local function findUIElement(parent, names)
	for _, name in ipairs(names) do
		local element = parent:FindFirstChild(name)
		if element then return element end
	end

	for _, child in pairs(parent:GetChildren()) do
		if table.find(names, child.Name) then
			return child
		end
	end

	return nil
end

-- แสดงไอเทมการ์ด
local function showItemCardAnimation(itemData, pendingKey)
	-- ตรวจสอบสถานะการทำงาน
	if state.isProcessingItemCard then
		-- หากกำลังแสดงการ์ดอยู่ ให้จัดคิวรอ
		table.insert(state.pendingItemCardQueue, {itemData = itemData, pendingKey = pendingKey})
		return
	end

	state.isProcessingItemCard = true
	state.pendingKey = pendingKey -- เก็บคีย์อ้างอิงไอเทมปัจจุบัน

	-- ค้นหา UI
	local itemCardUI = findItemCardUI()
	if not itemCardUI then
		createNotification("คุณได้รับไอเทม " .. itemData.name .. " แต่ไม่พบ UI แสดงการ์ด", NOTIFY_DURATION, ITEM_COLOR)

		-- แจ้งเซิร์ฟเวอร์ว่ายอมรับไอเทมโดยอัตโนมัติ
		if pendingKey then
			itemEventRemote:FireServer("keepItem", {pendingKey = pendingKey})
		end

		-- เคลียร์สถานะ
		state.isProcessingItemCard = false
		state.pendingKey = nil

		-- ตรวจสอบการ์ดในคิว
		if #state.pendingItemCardQueue > 0 then
			local nextCard = table.remove(state.pendingItemCardQueue, 1)
			task.delay(0.5, function()
				showItemCardAnimation(nextCard.itemData, nextCard.pendingKey)
			end)
		end

		return
	end

	-- ทำให้ UI มองเห็นได้
	itemCardUI.Enabled = true

	-- ค้นหา MainFrame
	local mainFrame
	if itemCardUI:IsA("Frame") then
		mainFrame = itemCardUI
	else
		mainFrame = itemCardUI:FindFirstChild("MainFrame")
		if not mainFrame then
			-- ค้นหาเชิงลึก
			for _, child in pairs(itemCardUI:GetDescendants()) do
				if child:IsA("Frame") and (child.Name == "MainFrame" or child.Name == "Backdrop" or child.Name:find("Main")) then
					for _, subChild in pairs(child:GetChildren()) do
						if subChild:IsA("Frame") and (subChild.Name == "OuterCardFrame" or subChild.Name == "InnerCardFrame" or subChild.Name:find("Card")) then
							mainFrame = child
							break
						end
					end
					if mainFrame then break end
				end
			end
		end
	end

	if not mainFrame then
		createNotification("คุณได้รับไอเทม " .. itemData.name .. " แต่ไม่พบ MainFrame ใน UI", NOTIFY_DURATION, ITEM_COLOR)

		-- แจ้งเซิร์ฟเวอร์ว่ายอมรับไอเทมโดยอัตโนมัติ
		if pendingKey then
			itemEventRemote:FireServer("keepItem", {pendingKey = pendingKey})
		end

		-- เคลียร์สถานะ
		state.isProcessingItemCard = false
		state.pendingKey = nil

		-- ตรวจสอบการ์ดในคิว
		if #state.pendingItemCardQueue > 0 then
			local nextCard = table.remove(state.pendingItemCardQueue, 1)
			task.delay(0.5, function()
				showItemCardAnimation(nextCard.itemData, nextCard.pendingKey)
			end)
		end

		return
	end

	mainFrame.Visible = true

	-- ตั้งค่าข้อมูลไอเทมใน UI
	-- หาส่วนต่างๆของ UI
	local outerCardFrame = findUIElement(mainFrame, {"OuterCardFrame", "CardFrame"})
	local activeFrame = outerCardFrame or mainFrame

	local innerCardFrame = findUIElement(activeFrame, {"InnerCardFrame", "Card"})
	if innerCardFrame then activeFrame = innerCardFrame end

	-- กำหนดชื่อไอเทม
	local headerFrame = findUIElement(activeFrame, {"HeaderFrame", "Header", "TitleFrame"})
	if headerFrame then
		local titleText = findUIElement(headerFrame, {"TitleText", "Title"})
		if titleText then
			titleText.Text = itemData.name
		end
	end

	-- กำหนดไอคอน
	local iconFrameOuter = findUIElement(activeFrame, {"IconFrameOuter", "IconFrame", "ItemIcon"})
	if iconFrameOuter then
		local iconFrame = findUIElement(iconFrameOuter, {"IconFrame", "Icon"})
		if iconFrame then
			local itemIcon = findUIElement(iconFrame, {"ItemIcon", "Icon", "Image"})
			if itemIcon then
				itemIcon.Image = itemData.iconId or ""
			end
		end
	end

	-- กำหนดความหายาก
	local rarityFrame = findUIElement(activeFrame, {"RarityFrame", "Rarity"})
	if rarityFrame then
		local rarityText = findUIElement(rarityFrame, {"RarityText", "Text"})
		if rarityText then
			local rarityNames = {"Common", "Uncommon", "Rare", "Epic", "Legendary"}
			rarityText.Text = rarityNames[itemData.rarity or 1] or "Common"
		end
	end

	-- กำหนดคำอธิบาย
	local descriptionFrame = findUIElement(activeFrame, {"DescriptionFrame", "Description"})
	if descriptionFrame then
		local descScroll = findUIElement(descriptionFrame, {"DescriptionScroll", "Scroll"})
		local descTarget = descScroll or descriptionFrame

		local descText = findUIElement(descTarget, {"DescriptionText", "Text"})
		if descText then
			descText.Text = itemData.description or "No description available."
		end
	end

	-- เล่นอนิเมชันเปิดการ์ด
	playCardRevealAnimation(mainFrame, function()
		-- เล่นเสียงเอฟเฟกต์
		playSound(mainFrame, "rbxassetid://6895079853", 0.5)

		-- หลังจากอนิเมชันเสร็จสิ้น ให้ตั้งเวลารีเซ็ตสถานะ
		task.delay(CARD_ANIMATION_DURATION, function()
			state.isProcessingItemCard = false

			-- ตรวจสอบการ์ดในคิว
			if #state.pendingItemCardQueue > 0 then
				local nextCard = table.remove(state.pendingItemCardQueue, 1)
				task.delay(0.5, function()
					showItemCardAnimation(nextCard.itemData, nextCard.pendingKey)
				end)
			end
		end)
	end)

	-- ตั้งค่าปุ่ม
	local keepButton = findUIElement(activeFrame, {"KeepButton", "Keep", "AcceptButton", "Accept"})
	if keepButton then
		-- เชื่อมต่อกับปุ่มโดยไม่ต้องตรวจสอบการเชื่อมต่อเดิม
		-- เนื่องจากปุ่มถูกสร้างใหม่ทุกครั้งที่เปิดการ์ด จึงไม่จำเป็นต้องล้างการเชื่อมต่อเดิม
		keepButton.MouseButton1Click:Connect(function()
			-- ส่งคำสั่งยืนยันไอเทมไปยังเซิร์ฟเวอร์
			if state.pendingKey then
				itemEventRemote:FireServer("keepItem", {pendingKey = state.pendingKey})
				createNotification("คุณได้รับ " .. itemData.name, NOTIFY_DURATION, ITEM_COLOR)
			end

			itemCardUI.Enabled = false
			mainFrame.Visible = false

			-- เคลียร์สถานะ
			state.pendingKey = nil

			-- ตรวจสอบการ์ดในคิว
			if #state.pendingItemCardQueue > 0 then
				local nextCard = table.remove(state.pendingItemCardQueue, 1)
				task.delay(0.5, function()
					showItemCardAnimation(nextCard.itemData, nextCard.pendingKey)
				end)
			end
		end)
	end

	local discardButton = findUIElement(activeFrame, {"DiscardButton", "Discard", "CancelButton", "Cancel"})
	if discardButton then
		-- เชื่อมต่อกับปุ่มโดยไม่ต้องตรวจสอบการเชื่อมต่อเดิม
		-- เนื่องจากปุ่มถูกสร้างใหม่ทุกครั้งที่เปิดการ์ด จึงไม่จำเป็นต้องล้างการเชื่อมต่อเดิม
		discardButton.MouseButton1Click:Connect(function()
			-- ส่งคำสั่งปฏิเสธไอเทมไปยังเซิร์ฟเวอร์
			if state.pendingKey then
				itemEventRemote:FireServer("discardItem", {pendingKey = state.pendingKey})
				createNotification("คุณทิ้ง " .. itemData.name, NOTIFY_DURATION, Color3.fromRGB(255, 100, 100))
			end

			itemCardUI.Enabled = false
			mainFrame.Visible = false

			-- เคลียร์สถานะ
			state.pendingKey = nil

			-- ตรวจสอบการ์ดในคิว
			if #state.pendingItemCardQueue > 0 then
				local nextCard = table.remove(state.pendingItemCardQueue, 1)
				task.delay(0.5, function()
					showItemCardAnimation(nextCard.itemData, nextCard.pendingKey)
				end)
			end
		end)
	end
end

-- รับฟังเหตุการณ์จากเซิร์ฟเวอร์
itemEventRemote.OnClientEvent:Connect(function(command, data)
	if command == "confirmItem" and data and data.item then
		-- แสดง UI ยืนยันการรับไอเทม
		createNotification("คุณพบไอเทม " .. data.item.name .. "! กดยืนยันเพื่อเก็บ", NOTIFY_DURATION, ITEM_COLOR)
		showItemCardAnimation(data.item, data.pendingKey)
	elseif command == "itemAdded" then
		-- ไอเทมถูกเพิ่มเข้าคลังแล้ว (ไม่ต้องทำอะไรเพิ่ม เพราะแสดงข้อความไปแล้วตอนกด Keep)
	elseif command == "itemDiscarded" then
		-- ไอเทมถูกทิ้งแล้ว (ไม่ต้องทำอะไรเพิ่ม เพราะแสดงข้อความไปแล้วตอนกด Discard)
	elseif command == "itemError" and data then
		-- แสดงข้อความผิดพลาด
		createNotification("เกิดข้อผิดพลาด: " .. (data.message or "ไม่สามารถเพิ่มไอเทมได้"), NOTIFY_DURATION, Color3.fromRGB(255, 80, 80))
	end
end)

-- ฟังก์ชันสำหรับเรียกใช้เมื่อตกช่อง Item
local function handleItemTile()
	-- ฟังก์ชันนี้จะถูกเรียกจาก EventTileHandler แล้ว
	-- ไม่จำเป็นต้องแสดงการแจ้งเตือนหรือขอไอเทมทันที เพราะจะถูกจัดการโดย EventTileHandler
	-- เราใช้ฟังก์ชันว่างเพื่อความเข้ากันได้กับโค้ดเดิม
end

-- เปิดฟังก์ชันให้ EventTileHandler เรียกใช้
_G.HandleItemTile = handleItemTile

print("[ItemTileHandler] ระบบไอเทมไคลเอนต์พร้อมใช้งาน")
