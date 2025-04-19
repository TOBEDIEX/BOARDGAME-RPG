-- InventoryUIHandler.lua (Updated for unpack Error & Programmatic Notification)
-- ตัวจัดการ UI ของระบบ Inventory (แบบกระชับพร้อมช่องอุปกรณ์)
-- Version: 1.3.6 (Fix unpack Error, Programmatic Notification)

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService") -- Needed for GUID

-- Get local player
local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- Constants
local ITEM_TYPES = { GENERAL = 1, EQUIPMENT = 2, SKILL = 3, SPECIAL = 4 }
local EQUIPMENT_SLOTS = { WEAPON = 1, HELMET = 2, ARMOR = 3, GLOVES = 4, BOOTS = 5, ACCESSORY = 6 }
local EQUIPMENT_SLOT_NAMES = { [1] = "WEAPON", [2] = "HELMET", [3] = "ARMOR", [4] = "GLOVES", [5] = "BOOTS", [6] = "ACCESSORY" }
local RARITY_COLORS = { [1] = Color3.fromRGB(150, 150, 150), [2] = Color3.fromRGB(100, 255, 100), [3] = Color3.fromRGB(100, 100, 255), [4] = Color3.fromRGB(200, 100, 255), [5] = Color3.fromRGB(255, 180, 60) }
local DEFAULT_TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local NOTIFICATION_DISPLAY_TIME = 3 -- เวลาที่ Notification แสดง (วินาที)
local NOTIFICATION_FADE_OUT_TIME = 0.5 -- เวลา fade out

-- Main UI Handler
local InventoryUIHandler = {}

-- UI Variables (Inventory Only)
local PopupUI = PlayerGui:WaitForChild("PopupUI")
local InventoryUI = PopupUI:WaitForChild("InventoryUI")
local itemsGrid = InventoryUI:FindFirstChild("ItemsGrid")
local categoryTabs = InventoryUI:FindFirstChild("CategoryTabs")
local itemDetails = InventoryUI:FindFirstChild("ItemDetails")
local actionButtons = InventoryUI:FindFirstChild("ActionButtons")
local closeButton = InventoryUI:FindFirstChild("CloseButton") or InventoryUI:FindFirstChild("Close")
local equipmentSlotsContainer = InventoryUI:FindFirstChild("EquipmentSlotsContainer")
local skillSlotsContainer = InventoryUI:FindFirstChild("SkillSlotsContainer")

-- Remote events/functions
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local inventoryRemotes = remotes:WaitForChild("InventoryRemotes", 10)
if not inventoryRemotes then	warn("InventoryRemotes not found after waiting!") end

-- Inventory data
local currentInventory = { items = {}, equippedItems = {}, maxSize = 50, selectedItem = nil, currentCategory = ITEM_TYPES.GENERAL, itemSlots = {} }
local isUsingItem = false

-- Helper functions
local function tween(object, properties, tweenInfo) local t = TweenService:Create(object, tweenInfo or DEFAULT_TWEEN_INFO, properties); t:Play(); return t end
local function playSound(soundName) local s = game:GetService("SoundService"):FindFirstChild(soundName); if s and s:IsA("Sound") then s:Play() end end

-- *** REVISED Notification Function (Creates UI Programmatically) ***
local activeNotificationFrames = {} -- Track active frames
local notificationOffsetY = 10 -- Initial Y offset from top
local notificationSpacing = 5 -- Spacing between notifications

local function createNotificationUI(message)
	-- Create Frame
	local notificationFrame = Instance.new("Frame")
	notificationFrame.Name = "NotificationFrame_" .. HttpService:GenerateGUID(false)
	notificationFrame.Size = UDim2.new(0, 250, 0, 50) -- Adjust size as needed
	notificationFrame.Position = UDim2.new(1, -15, 0, notificationOffsetY) -- Position top-right with offset
	notificationFrame.AnchorPoint = Vector2.new(1, 0) -- Anchor top-right
	notificationFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	notificationFrame.BackgroundTransparency = 0.2
	notificationFrame.BorderSizePixel = 0
	notificationFrame.Parent = PlayerGui -- Parent directly to PlayerGui

	-- Add Corner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = notificationFrame

	-- Add TextLabel
	local notificationLabel = Instance.new("TextLabel")
	notificationLabel.Name = "NotificationText"
	notificationLabel.Size = UDim2.new(1, -10, 1, -10) -- Padding
	notificationLabel.Position = UDim2.fromScale(0.5, 0.5)
	notificationLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	notificationLabel.BackgroundTransparency = 1
	notificationLabel.Font = Enum.Font.SourceSans -- Or your preferred font
	notificationLabel.Text = message or "Notification"
	notificationLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	notificationLabel.TextSize = 16 -- Adjust size
	notificationLabel.TextWrapped = true
	notificationLabel.TextXAlignment = Enum.TextXAlignment.Left
	notificationLabel.TextYAlignment = Enum.TextYAlignment.Center
	notificationLabel.Parent = notificationFrame

	-- Adjust offset for next notification
	notificationOffsetY = notificationOffsetY + notificationFrame.AbsoluteSize.Y + notificationSpacing

	return notificationFrame, notificationLabel
end

local function showNotification(message, displayDuration)
	displayDuration = displayDuration or NOTIFICATION_DISPLAY_TIME

	local notificationFrame, notificationLabel = createNotificationUI(message)
	if not notificationFrame then return end -- Failed to create UI

	local frameId = notificationFrame.Name -- Use unique name as ID

	-- Store reference
	activeNotificationFrames[frameId] = notificationFrame

	-- Coroutine to fade out and destroy
	task.spawn(function()
		task.wait(displayDuration)
		-- Check if frame still exists and wasn't removed prematurely
		if activeNotificationFrames[frameId] then
			local fadeInfo = TweenInfo.new(NOTIFICATION_FADE_OUT_TIME, Enum.EasingStyle.Linear)
			local fadeTween = tween(notificationFrame, { BackgroundTransparency = 1 }, fadeInfo)
			tween(notificationLabel, { TextTransparency = 1 }, fadeInfo) -- Fade text too

			fadeTween.Completed:Connect(function()
				if activeNotificationFrames[frameId] then
					activeNotificationFrames[frameId]:Destroy()
					activeNotificationFrames[frameId] = nil

					-- Reset offset if this was the last notification (or implement repositioning)
					local hasActive = false
					for _ in pairs(activeNotificationFrames) do
						hasActive = true
						break
					end
					if not hasActive then
						notificationOffsetY = 10 -- Reset Y offset
					end
					-- Note: This simple reset might cause overlap if middle notifications disappear.
					-- A more complex system would reposition remaining notifications.
				end
			end)
		end
	end)
end


-- Clear items grid (เหมือนเดิม)
local function clearItemGrid() for _, slot in pairs(currentInventory.itemSlots) do if slot.instance then slot.instance:Destroy() end end; currentInventory.itemSlots = {} end

-- Update action buttons (เหมือนเดิม)
local function updateActionButtons(item) if not actionButtons then return end; local useBtn = actionButtons:FindFirstChild("UseButton") or actionButtons:FindFirstChild("Use"); local equipBtn = actionButtons:FindFirstChild("EquipButton") or actionButtons:FindFirstChild("Equip"); local discardBtn = actionButtons:FindFirstChild("DiscardButton") or actionButtons:FindFirstChild("Discard"); if useBtn then useBtn.Visible = false end; if equipBtn then equipBtn.Visible = false end; if discardBtn then discardBtn.Visible = true end; if not item then return end; if item.usable and useBtn then useBtn.Visible = true end; if item.type == ITEM_TYPES.EQUIPMENT and equipBtn then equipBtn.Visible = true; local txt = equipBtn:FindFirstChild("EquipText"); if txt then txt.Text = item.equipped and "Unequip" or "Equip" end end end

-- Update item details (เหมือนเดิม)
local function updateItemDetails(item) if not itemDetails then return end; if not item then itemDetails.Visible = false; if actionButtons then actionButtons.Visible = false end; return end; itemDetails.Visible = true; if actionButtons then actionButtons.Visible = true end; local nameLbl = itemDetails:FindFirstChild("SelectedItemName"); if nameLbl then nameLbl.Text = item.name or "Unknown"; nameLbl.TextColor3 = RARITY_COLORS[item.rarity or 1] or Color3.new(1,1,1) end; local descLbl = itemDetails:FindFirstChild("ItemDescription"); if descLbl then descLbl.Text = item.description or "" end; local statsFX = itemDetails:FindFirstChild("StatEffects"); if statsFX then for _, c in pairs(statsFX:GetChildren()) do if c:IsA("TextLabel") and c.Name ~= "StatEffect" then c:Destroy() end end; local tmpl = statsFX:FindFirstChild("StatEffect"); if tmpl then tmpl.Visible = false; if item.stats then for stat, val in pairs(item.stats) do if val ~= 0 then local lbl = tmpl:Clone(); lbl.Name = "Stat_"..stat; lbl.Visible = true; lbl.Text = stat:upper()..": "..(val>0 and "+" or "")..tostring(val); lbl.TextColor3 = val>0 and Color3.fromRGB(100,255,100) or Color3.fromRGB(255,100,100); lbl.Parent = statsFX end end end end end; updateActionButtons(item) end

-- Select item (เหมือนเดิม)
local function selectItem(item) for _, slot in pairs(currentInventory.itemSlots) do if slot.instance then tween(slot.instance, {BackgroundColor3 = Color3.fromRGB(50,50,50)}) end end; currentInventory.selectedItem = item; local slotData = currentInventory.itemSlots[item.inventoryId]; if slotData and slotData.instance then tween(slotData.instance, {BackgroundColor3 = Color3.fromRGB(80,120,200)}) end; updateItemDetails(item); local inspectRemote = inventoryRemotes and inventoryRemotes:FindFirstChild("InspectItem"); if inspectRemote then inspectRemote:FireServer(item.inventoryId) end end

-- Create item slot (เหมือนเดิม)
local function createItemSlot(item) if not itemsGrid then return nil end; local tmpl = itemsGrid:FindFirstChild("InventoryItem"); if not tmpl then return nil end; local slot = tmpl:Clone(); slot.Name = "Item_"..item.inventoryId; slot.Visible = true; local icon = slot:FindFirstChild("ItemIcon"); if icon then if item.iconId and item.iconId ~= "" then icon.Image = item.iconId else local defIcons={[1]="rbxassetid://6442564832",[2]="rbxassetid://6442577397",[3]="rbxassetid://6442584030",[4]="rbxassetid://6442590793"}; icon.Image = defIcons[item.type] or defIcons[1] end; local stroke = slot:FindFirstChild("UIStroke"); if stroke then stroke.Color = RARITY_COLORS[item.rarity or 1] or Color3.fromRGB(150,150,150) end; local eqInd = icon:FindFirstChild("EquippedIndicator"); if item.equipped then if not eqInd then eqInd=Instance.new("ImageLabel");eqInd.Name="EquippedIndicator";eqInd.Size=UDim2.new(1,0,1,0);eqInd.BackgroundTransparency=1;eqInd.Image="rbxassetid://6442622551";eqInd.ZIndex=icon.ZIndex+1;eqInd.Parent=icon end; eqInd.Visible=true else if eqInd then eqInd.Visible=false end end end; local nameLbl = slot:FindFirstChild("ItemName"); if nameLbl then nameLbl.Text = item.name or "?" end; local countLbl = slot:FindFirstChild("ItemCount"); if countLbl then countLbl.Visible = (item.quantity and item.quantity > 1); if countLbl.Visible then countLbl.Text = tostring(item.quantity) end end; slot.InputBegan:Connect(function(inp) if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then selectItem(item); tween(slot, {BackgroundColor3 = Color3.fromRGB(80,120,200)}); playSound("ItemSelect") end end); slot.InputEnded:Connect(function(inp) if (inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch) and currentInventory.selectedItem ~= item then tween(slot, {BackgroundColor3 = Color3.fromRGB(50,50,50)}) end end); currentInventory.itemSlots[item.inventoryId] = {instance=slot, item=item}; slot.Parent = itemsGrid; return slot end

-- Filter items by category (เหมือนเดิม)
local function filterItemsByCategory(category) currentInventory.currentCategory = category; if not categoryTabs then return end; for _, slot in pairs(currentInventory.itemSlots) do if slot.instance then slot.instance.Visible = (slot.item.type == category or category == 0) end end; for _, tab in pairs(categoryTabs:GetChildren()) do if tab:IsA("TextButton") or tab:IsA("Frame") then local typeAttr = tab:GetAttribute("ItemType"); local sel = (typeAttr == category); local btn = tab; if tab:IsA("Frame") then btn=tab:FindFirstChildOfClass("TextButton") or tab end; tween(btn, {BackgroundColor3 = sel and Color3.fromRGB(80,120,200) or Color3.fromRGB(50,50,70)}); local strk=btn:FindFirstChild("UIStroke"); if strk then strk.Color = sel and Color3.fromRGB(100,150,255) or Color3.fromRGB(80,80,120) end end end; if equipmentSlotsContainer then equipmentSlotsContainer.Visible=(category==ITEM_TYPES.EQUIPMENT) end; if skillSlotsContainer then skillSlotsContainer.Visible=(category==ITEM_TYPES.SKILL) end end

-- Update inventory display (เหมือนเดิม)
local function updateInventoryDisplay() clearItemGrid(); local sorted={}; for _, item in pairs(currentInventory.items) do table.insert(sorted, item) end; table.sort(sorted, function(a,b) if (a.rarity or 1)==(b.rarity or 1) then return (a.name or "")<(b.name or "") end; return (a.rarity or 1)>(b.rarity or 1) end); for _, item in ipairs(sorted) do local slot=createItemSlot(item); if slot then slot.Visible=(item.type==currentInventory.currentCategory or currentInventory.currentCategory==0) end end; local countTxt=InventoryUI:FindFirstChild("ItemCountText"); if countTxt then countTxt.Text="Items: "..#sorted.."/"..currentInventory.maxSize end end

-- Update equipment slots UI (เหมือนเดิม)
local function updateEquipmentSlotsUI() if not equipmentSlotsContainer then return end; if not currentInventory.equippedItems then return end; for slotType, item in pairs(currentInventory.equippedItems) do local slotName=EQUIPMENT_SLOT_NAMES[slotType]; if not slotName then continue end; local slotFrame=equipmentSlotsContainer:FindFirstChild("Slot_"..slotName); if not slotFrame then continue end; local nameLbl=slotFrame:FindFirstChild("ItemNameLabel"); local iconFrame=slotFrame:FindFirstChild("IconFrame"); local iconImg=iconFrame and iconFrame:FindFirstChild("IconImage"); local stroke=slotFrame:FindFirstChild("SlotStroke"); if nameLbl then nameLbl.Text=item.name or "?"; nameLbl.TextColor3=RARITY_COLORS[item.rarity or 1] or Color3.new(1,1,1) end; if iconImg then if item.iconId and item.iconId~="" then iconImg.Image=item.iconId; iconImg.ImageColor3=Color3.new(1,1,1) else iconImg.Image="" end end; if stroke then stroke.Color=RARITY_COLORS[item.rarity or 1] or Color3.fromRGB(180,150,100) end end; for _, slotName in ipairs({"WEAPON","HELMET","ARMOR","GLOVES","BOOTS","ACCESSORY"}) do local slotType=nil; for typeNum, name in pairs(EQUIPMENT_SLOT_NAMES) do if name==slotName then slotType=typeNum; break end end; if not slotType then continue end; if not currentInventory.equippedItems[slotType] then local slotFrame=equipmentSlotsContainer:FindFirstChild("Slot_"..slotName); if not slotFrame then continue end; local nameLbl=slotFrame:FindFirstChild("ItemNameLabel"); local iconFrame=slotFrame:FindFirstChild("IconFrame"); local iconImg=iconFrame and iconFrame:FindFirstChild("IconImage"); local stroke=slotFrame:FindFirstChild("SlotStroke"); if nameLbl then nameLbl.Text="None"; nameLbl.TextColor3=Color3.fromRGB(200,200,200) end; if stroke then stroke.Color=Color3.fromRGB(180,150,100) end; if iconImg then local defIcons={WEAPON="rbxassetid://6442677274",HELMET="rbxassetid://6442677747",ARMOR="rbxassetid://6442678135",GLOVES="rbxassetid://6442678539",BOOTS="rbxassetid://6442678968",ACCESSORY="rbxassetid://6442679364"}; iconImg.Image=defIcons[slotName] or ""; iconImg.ImageColor3=Color3.fromRGB(210,210,210) end end end end

-- Setup equipment slot events (เหมือนเดิม)
local function setupEquipmentSlotEvents() if not equipmentSlotsContainer then return end; for slotTypeNum, slotName in pairs(EQUIPMENT_SLOT_NAMES) do local slotFrame=equipmentSlotsContainer:FindFirstChild("Slot_"..slotName); if not slotFrame then warn("[InvUI] Missing slot frame:", "Slot_"..slotName); continue end; if slotFrame:GetAttribute("Connected") then continue end; slotFrame.InputBegan:Connect(function(inp) if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then local eqItem=nil; if currentInventory.equippedItems and currentInventory.equippedItems[slotTypeNum] then eqItem=currentInventory.equippedItems[slotTypeNum] end; if eqItem then local itemInGrid=currentInventory.itemSlots[eqItem.inventoryId]; if itemInGrid then selectItem(itemInGrid.item) else currentInventory.selectedItem=eqItem; updateItemDetails(eqItem) end; tween(slotFrame,{BackgroundColor3=Color3.fromRGB(80,120,200)}); playSound("ItemSelect") else currentInventory.selectedItem=nil; updateItemDetails(nil); playSound("Cancel") end end end); slotFrame.InputEnded:Connect(function(inp) if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then tween(slotFrame,{BackgroundColor3=Color3.fromRGB(50,40,25)}) end end); slotFrame.BackgroundColor3=Color3.fromRGB(60,45,30); slotFrame:SetAttribute("Connected",true) end end

-- Handle inventory updates from server (เหมือนเดิม)
local function handleInventoryUpdate(clientData) print("[InvUI DEBUG] Received UpdateInventory"); print("  > Equipped:", clientData.equippedItems); currentInventory.items = clientData.items or {}; currentInventory.equippedItems = clientData.equippedItems or {}; currentInventory.maxSize = clientData.maxSize or 50; updateInventoryDisplay(); updateEquipmentSlotsUI(); if currentInventory.selectedItem then local exists=false; for _,item in pairs(currentInventory.items) do if item.inventoryId==currentInventory.selectedItem.inventoryId then exists=true; currentInventory.selectedItem=item; break end end; if exists then updateItemDetails(currentInventory.selectedItem); local slotData=currentInventory.itemSlots[currentInventory.selectedItem.inventoryId]; if slotData and slotData.instance then tween(slotData.instance,{BackgroundColor3=Color3.fromRGB(80,120,200)}) end else currentInventory.selectedItem=nil; updateItemDetails(nil) end end end

-- Initialize category tabs (เหมือนเดิม)
local function initCategoryTabs() if not categoryTabs then return end; local cfgs={{Name="SPECIAL",Type=4},{Name="GENERAL",Type=1},{Name="SKILL",Type=3},{Name="EQUIPMENT",Type=2}}; for i,cfg in ipairs(cfgs) do local tab=nil; for _,c in pairs(categoryTabs:GetChildren()) do if c:IsA("TextButton") or c:IsA("Frame") then local lbl=c:FindFirstChildOfClass("TextLabel"); if (lbl and lbl.Text==cfg.Name) or (c.Name==cfg.Name) or (c:IsA("TextButton") and c.Text==cfg.Name) then tab=c; break end end end; if tab then tab:SetAttribute("ItemType",cfg.Type); local clk=tab; if tab:IsA("Frame") then clk=tab:FindFirstChildOfClass("TextButton") or tab end; if not clk:GetAttribute("Connected") then clk.MouseButton1Click:Connect(function() filterItemsByCategory(cfg.Type); playSound("TabClick") end); clk:SetAttribute("Connected",true) end else warn("[InvUI] No tab for:",cfg.Name) end end; filterItemsByCategory(ITEM_TYPES.GENERAL) end

-- *** initActionButtons (แก้ไข unpack Error) ***
local function initActionButtons()
	if not actionButtons or not inventoryRemotes then warn("ActionButtons or InventoryRemotes not found, cannot initialize."); return end
	local useButton = actionButtons:FindFirstChild("UseButton") or actionButtons:FindFirstChild("Use"); local useRemoteFunc = inventoryRemotes:FindFirstChild("UseItem")
	if useButton and useRemoteFunc and useRemoteFunc:IsA("RemoteFunction") and not useButton:GetAttribute("Connected") then
		useButton.MouseButton1Click:Connect(function()
			if isUsingItem then return end; if currentInventory.selectedItem then isUsingItem = true; local selectedItemId = currentInventory.selectedItem.inventoryId; print("[InvUI] Invoking UseItem for:", selectedItemId)
				local success, result = pcall(function() return useRemoteFunc:InvokeServer(selectedItemId) end)
				task.delay(0.3, function() isUsingItem = false end)

				if success then
					local serverSuccess, serverMessage
					-- *** FIXED UNPACK ERROR HERE ***
					-- Check if result is actually a table before unpacking
					if type(result) == "table" then
						serverSuccess, serverMessage = table.unpack(result)
					else
						-- If pcall succeeded but result isn't a table, assume server logic failed internally
						serverSuccess = false
						serverMessage = "Invalid response from server." -- Or use 'result' if it might be an error string
						warn("[InvUI] InvokeServer pcall succeeded but result was not a table:", result)
					end
					-- Ensure serverSuccess is boolean, default to false
					if type(serverSuccess) ~= "boolean" then serverSuccess = false end

					print("[InvUI] UseItem Invoke Result - Success:", serverSuccess, "Message:", serverMessage)
					if not serverSuccess then showNotification(serverMessage or "Cannot use this item now.", 4); playSound("Cancel")
					else playSound("ItemUse") end
				else -- pcall failed
					warn("[InvUI] Error invoking UseItem:", result); showNotification("Error communicating with server.", 3); playSound("Cancel"); isUsingItem = false
				end
			else isUsingItem = false end
		end); useButton:SetAttribute("Connected", true)
	elseif not useRemoteFunc or not useRemoteFunc:IsA("RemoteFunction") then warn("[InvUI] UseItem RemoteFunction not found or is wrong type!"); if useButton then useButton.Visible = false end end

	-- Equip button (เหมือนเดิม)
	local equipButton = actionButtons:FindFirstChild("EquipButton") or actionButtons:FindFirstChild("Equip"); local equipRemote = inventoryRemotes:FindFirstChild("EquipItem"); local unequipRemote = inventoryRemotes:FindFirstChild("UnequipItem")
	if equipButton and equipRemote and unequipRemote and not equipButton:GetAttribute("Connected") then equipButton.MouseButton1Click:Connect(function() if not currentInventory.selectedItem then return end; local item=currentInventory.selectedItem; if item.equipped then print("[InvUI] Firing UnequipItem"); unequipRemote:FireServer(item.subType); playSound("ItemUnequip") else print("[InvUI] Firing EquipItem"); equipRemote:FireServer(item.inventoryId); playSound("ItemEquip") end end); equipButton:SetAttribute("Connected", true) end

	-- Discard button (เหมือนเดิม - ลบทั้ง Stack)
	local discardButton = actionButtons:FindFirstChild("DiscardButton") or actionButtons:FindFirstChild("Discard"); local removeRemote = inventoryRemotes:FindFirstChild("RemoveItem")
	if discardButton and removeRemote and not discardButton:GetAttribute("Connected") then
		discardButton.MouseButton1Click:Connect(function() if not currentInventory.selectedItem then return end; local itemToDiscard = currentInventory.selectedItem; local conf = InventoryUI:FindFirstChild("ConfirmDiscard"); if conf then conf.Visible = true; local ok = conf:FindFirstChild("ConfirmButton"); local cancel = conf:FindFirstChild("CancelButton"); if ok and not ok:GetAttribute("Connected") then ok.MouseButton1Click:Connect(function() if itemToDiscard then print("[InvUI] Firing RemoveItem for stack:", itemToDiscard.inventoryId, "Qty:", itemToDiscard.quantity or 1); removeRemote:FireServer(itemToDiscard.inventoryId, itemToDiscard.quantity or 1) end; conf.Visible = false; playSound("ItemDiscard"); currentInventory.selectedItem = nil; updateItemDetails(nil) end); ok:SetAttribute("Connected", true) end; if cancel and not cancel:GetAttribute("Connected") then cancel.MouseButton1Click:Connect(function() conf.Visible = false; playSound("Cancel") end); cancel:SetAttribute("Connected", true) end else print("[InvUI] Firing RemoveItem (no confirm) for stack:", itemToDiscard.inventoryId, "Qty:", itemToDiscard.quantity or 1); removeRemote:FireServer(itemToDiscard.inventoryId, itemToDiscard.quantity or 1); playSound("ItemDiscard"); currentInventory.selectedItem = nil; updateItemDetails(nil) end end)
		discardButton:SetAttribute("Connected", true)
	end
end


-- Initialize close button (เหมือนเดิม)
local function initCloseButton() if not closeButton then return end; if not closeButton:GetAttribute("Connected") then closeButton.MouseButton1Click:Connect(function() InventoryUI.Visible = false; playSound("Close") end); closeButton:SetAttribute("Connected", true) end end

-- Initialize inventory UI
local function init()
	-- Initial UI setup (เหมือนเดิม)
	if InventoryUI then InventoryUI.Visible=false; if itemDetails then itemDetails.Visible=false end; if actionButtons then actionButtons.Visible=false end; local conf=InventoryUI:FindFirstChild("ConfirmDiscard"); if conf then conf.Visible=false end; if itemsGrid then local tmpl=itemsGrid:FindFirstChild("InventoryItem"); if tmpl then tmpl.Visible=false end end; if equipmentSlotsContainer then equipmentSlotsContainer.Visible=false end; if skillSlotsContainer then skillSlotsContainer.Visible=false end end

	-- Create sounds (เหมือนเดิม)
	local sounds={{Name="ItemSelect",Id="rbxassetid://184241792",Volume=0.5},{Name="ItemUse",Id="rbxassetid://184241792",Volume=0.6},{Name="ItemEquip",Id="rbxassetid://184241792",Volume=0.6},{Name="ItemUnequip",Id="rbxassetid://184241792",Volume=0.6},{Name="ItemDiscard",Id="rbxassetid://184241792",Volume=0.5},{Name="TabClick",Id="rbxassetid://184241792",Volume=0.4},{Name="Close",Id="rbxassetid://184241792",Volume=0.5},{Name="Cancel",Id="rbxassetid://184241792",Volume=0.5}}; for _,si in ipairs(sounds) do local ss=game:GetService("SoundService"); if not ss:FindFirstChild(si.Name) then local s=Instance.new("Sound");s.Name=si.Name;s.SoundId=si.Id;s.Volume=si.Volume;s.Parent=ss end end

	-- Initialize UI components
	initCategoryTabs()
	initActionButtons() -- This now sets up the InvokeServer call
	initCloseButton()
	setupEquipmentSlotEvents()

	-- Connect to remote events (UpdateInventory, InspectItem, EquipmentChanged)
	if inventoryRemotes then
		local updateEvent = inventoryRemotes:FindFirstChild("UpdateInventory")
		if updateEvent and updateEvent:IsA("RemoteEvent") then updateEvent.OnClientEvent:Connect(handleInventoryUpdate); print("[InvUI] Connected UpdateInventory") else warn("[InvUI] UpdateInventory not found or not RemoteEvent!") end
		local inspectEvent = inventoryRemotes:FindFirstChild("InspectItem")
		if inspectEvent and inspectEvent:IsA("RemoteEvent") then inspectEvent.OnClientEvent:Connect(function(itemData) if currentInventory.selectedItem and currentInventory.selectedItem.inventoryId==itemData.inventoryId then for k,v in pairs(itemData) do currentInventory.selectedItem[k]=v end; updateItemDetails(currentInventory.selectedItem) end end); print("[InvUI] Connected InspectItem") else warn("[InvUI] InspectItem not found or not RemoteEvent!") end
		local equipChangedEvent = inventoryRemotes:FindFirstChild("EquipmentChanged")
		if equipChangedEvent and equipChangedEvent:IsA("RemoteEvent") then equipChangedEvent.OnClientEvent:Connect(function(slotType,itemData) print("[InvUI DEBUG] EquipChanged:",slotType,itemData and itemData.name); if itemData then currentInventory.equippedItems[slotType]=itemData else if currentInventory.equippedItems[slotType] then currentInventory.equippedItems[slotType]=nil end end; updateEquipmentSlotsUI(); local invId=itemData and itemData.inventoryId; if not invId then local oldItem=nil; for _,item in pairs(currentInventory.items) do if item.subType==slotType and item.equipped==false then oldItem=item; break end end; if oldItem then invId=oldItem.inventoryId end end; if invId then local slotData=currentInventory.itemSlots[invId]; if slotData and slotData.instance then local ind=slotData.instance:FindFirstChild("EquippedIndicator"); if ind then ind.Visible=(itemData~=nil) end end end end); print("[InvUI] Connected EquipmentChanged") else warn("[InvUI] EquipmentChanged not found or not RemoteEvent!") end
	else warn("[InvUI] InventoryRemotes folder not found! UI will not function correctly.") end
end -- End of init function

-- Initialize on script load
init()
print("[InventoryUIHandler] Initialized.")

return InventoryUIHandler
