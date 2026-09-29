local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("BrizabelleEggSystem")
local CareEgg = remotes:WaitForChild("CareEgg")
local petViews = ReplicatedStorage:WaitForChild("MascotasView")
local PetConfigs = require(ReplicatedStorage:WaitForChild("PetConfigs"))

local EGG_NAME = "Huevo Mascota"
local FONT = Enum.Font.FredokaOne
local CORE_GUI_TYPES_TO_HIDE = {
	Enum.CoreGuiType.Chat,
	Enum.CoreGuiType.PlayerList,
	Enum.CoreGuiType.Health,
	Enum.CoreGuiType.EmotesMenu,
}
local busy = false
local open = false
local hiddenGuiStates = {}
local characterTransparency = {}
local coreHidden = false
local viewportModel = nil
local oldCameraState = nil
local cleaningActive = false
local cleaningProgress = 0
local mouseDown = false
local previousMouseIconEnabled = nil
local previousMouseIcon = nil
local hoverCursorActive = false
local previousPetMouseIconEnabled = nil
local cleaningCompleted = false
local dirtSpots = {}
local soapSpots = {}
local lastPetAt = 0
local careBillboard = nil
local pettingActive = false
local didPetWhileHeld = false
local lastHeartAt = 0
local celebrationTrack = nil
local careDepthOfField = nil
local previousDepthProps = nil
local nextPetPromptRefreshAt = 0
local petMenuPromptConnection = nil
local petMenuKeyWasDown = false

-- R directa: evita depender solamente del ProximityPrompt.
local lastDirectRPressAt = 0
local R_DEBOUNCE_SECONDS = 0.35

local playerControls = nil
local controlsDisabled = false
local closingView = false
local setCleaningMode
local callCare
local hudSuppressConnections = {}
local hiddenGuiFolder = Instance.new("Folder")
hiddenGuiFolder.Name = "EggCareHiddenGuis"
hiddenGuiFolder.Parent = script
local CELEBRATION_ANIMATION_ID = "rbxassetid://105255804146095"
local PET_CONFIG_ALIASES = {
	["Pajarillo"] = "Perico",
	["Pez dorado"] = "PezDorado",
	["HuevoBrizabelle"] = EGG_NAME,
}
local CLEAN_BUTTON_IMAGE = "rbxassetid://111735620931654"
local SLEEP_ALERT_IMAGE = "rbxassetid://78882623653528"
local BATH_ALERT_IMAGE = "rbxassetid://96875011257714"
local FOOD_ALERT_IMAGE = "rbxassetid://92988853754741"
local EAT_SOUND_ID = "rbxassetid://9118823108"
local SPONGE_CURSOR_IMAGE = "rbxassetid://80242377965093"
local PETTING_CURSOR_IMAGE = "rbxassetid://116593022929574"
local HEART_IMAGE = "rbxassetid://103081018586328"
local CLEAN_SPOT_COUNT = 7
local WASH_SECONDS = 7.0
local MAX_SOAP_SPOTS = 150
local CLICK_CURSOR_IMAGE = "rbxasset://textures/Cursors/KeyboardMouse/PointingHandCursor.png"
local PET_MENU_PROMPT_NAME = "BrizabellePetMenuPrompt"
local PET_MENU_PROMPT_KEY = Enum.KeyCode.R
local PET_MENU_ICON_IMAGE = "rbxassetid://119382618384110"
local EXIT_HOLD_ATTRIBUTE = "PetMenuExitHoldAlpha"
local EXIT_HOLD_SECONDS = 0.65

-- Cámara frontal del menú R.
-- Corre después del PetRenderer para usar la orientación ya actualizada.
local PET_CARE_CAMERA_STEP =
	"PetMenuFrontCamera_" .. tostring(player.UserId)

local PET_CARE_CAMERA_PRIORITY =
	Enum.RenderPriority.Last.Value + 100

-- Ajuste general del encuadre.
local PET_CARE_CAMERA_DISTANCE_MULTIPLIER = 3.35
local PET_CARE_CAMERA_HEIGHT_MULTIPLIER = 1.08
local PET_CARE_CAMERA_TARGET_HEIGHT_MULTIPLIER = 0.04

local gui = Instance.new("ScreenGui")
gui.Name = "EggCareViewGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
gui.Enabled = false
gui.Parent = playerGui

local menuScale = Instance.new("UIScale")
menuScale.Scale = 1
menuScale.Parent = gui

local shade = Instance.new("Frame")
shade.Name = "Shade"
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.fromRGB(20, 14, 10)
shade.BackgroundTransparency = 0.9
shade.BorderSizePixel = 0
shade.ZIndex = 1
shade.Parent = gui

local closeButton = Instance.new("TextLabel")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.fromScale(0.625, 0.315)
closeButton.Size = UDim2.fromOffset(132, 44)
closeButton.BackgroundTransparency = 1
closeButton.Text = ""
closeButton.ZIndex = 10
closeButton.Parent = gui

local closeButtonScale = Instance.new("UIScale")
closeButtonScale.Scale = 1
closeButtonScale.Parent = closeButton

local closeIcon = Instance.new("ImageLabel")
closeIcon.Name = "RIcon"
closeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
closeIcon.Position = UDim2.fromOffset(20, 22)
closeIcon.Size = UDim2.fromOffset(36, 36)
closeIcon.BackgroundTransparency = 1
closeIcon.Image = PET_MENU_ICON_IMAGE
closeIcon.ScaleType = Enum.ScaleType.Fit
closeIcon.ZIndex = closeButton.ZIndex + 1
closeIcon.Parent = closeButton

local closeLabel = Instance.new("TextLabel")
closeLabel.Name = "CloseLabel"
closeLabel.AnchorPoint = Vector2.new(0, 0.5)
closeLabel.Position = UDim2.fromOffset(42, 22)
closeLabel.Size = UDim2.fromOffset(86, 30)
closeLabel.BackgroundTransparency = 1
closeLabel.Font = FONT
closeLabel.Text = "Cerrar"
closeLabel.TextColor3 = Color3.fromRGB(255, 244, 226)
closeLabel.TextStrokeColor3 = Color3.fromRGB(64, 36, 13)
closeLabel.TextStrokeTransparency = 0
closeLabel.TextScaled = true
closeLabel.TextXAlignment = Enum.TextXAlignment.Left
closeLabel.TextYAlignment = Enum.TextYAlignment.Center
closeLabel.ZIndex = closeButton.ZIndex + 1
closeLabel.Parent = closeButton

local closeHoldBack = Instance.new("Frame")
closeHoldBack.Name = "HoldBack"
closeHoldBack.AnchorPoint = Vector2.new(0.5, 1)
closeHoldBack.Position = UDim2.fromScale(0.5, 1.05)
closeHoldBack.Size = UDim2.fromOffset(40, 5)
closeHoldBack.BackgroundColor3 = Color3.fromRGB(67, 46, 31)
closeHoldBack.BackgroundTransparency = 1
closeHoldBack.BorderSizePixel = 0
closeHoldBack.Visible = false
closeHoldBack.ZIndex = closeButton.ZIndex
closeHoldBack.Parent = closeButton
local closeHoldBackCorner = Instance.new("UICorner")
closeHoldBackCorner.CornerRadius = UDim.new(0, 5)
closeHoldBackCorner.Parent = closeHoldBack

local closeHoldFill = Instance.new("Frame")
closeHoldFill.Name = "Fill"
closeHoldFill.Size = UDim2.fromScale(0, 1)
closeHoldFill.BackgroundColor3 = Color3.fromRGB(255, 244, 204)
closeHoldFill.BackgroundTransparency = 1
closeHoldFill.BorderSizePixel = 0
closeHoldFill.Visible = false
closeHoldFill.ZIndex = closeHoldBack.ZIndex + 1
closeHoldFill.Parent = closeHoldBack
local closeHoldFillCorner = Instance.new("UICorner")
closeHoldFillCorner.CornerRadius = UDim.new(0, 5)
closeHoldFillCorner.Parent = closeHoldFill

local closeHoldStartedAt = nil
local closeHoldRequested = false

local viewport = Instance.new("ViewportFrame")
viewport.Name = "EggViewport"
viewport.AnchorPoint = Vector2.new(0.5, 0.5)
viewport.Position = UDim2.fromScale(0.5, 0.43)
viewport.Size = UDim2.fromOffset(320, 300)
viewport.BackgroundTransparency = 1
viewport.Ambient = Color3.fromRGB(255, 255, 255)
viewport.LightColor = Color3.fromRGB(255, 255, 255)
viewport.LightDirection = Vector3.new(-0.35, -1, -0.25)
viewport.ZIndex = 3
viewport.Parent = gui

local viewportCamera = Instance.new("Camera")
viewportCamera.Parent = viewport
viewport.CurrentCamera = viewportCamera

local buttonHolder = Instance.new("Frame")
buttonHolder.Name = "Buttons"
buttonHolder.AnchorPoint = Vector2.new(0.5, 0.5)
buttonHolder.Position = UDim2.fromScale(0.5, 0.84)
buttonHolder.Size = UDim2.fromOffset(520, 190)
buttonHolder.BackgroundTransparency = 1
buttonHolder.ZIndex = 8
buttonHolder.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 14)
layout.Parent = buttonHolder

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function addStroke(parent, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = parent
	return stroke
end

local function makeButton(name, text, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(220, 56)
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = text
	button.Font = FONT
	button.TextScaled = true
	button.TextColor3 = Color3.fromRGB(255, 248, 224)
	button.TextStrokeColor3 = Color3.fromRGB(75, 43, 18)
	button.TextStrokeTransparency = 0.2
	button.ZIndex = 9
	button.Parent = buttonHolder
	addCorner(button, 9)
	addStroke(button, Color3.fromRGB(77, 45, 22), 3)
	local scale = Instance.new("UIScale")
	scale.Name = "ButtonScale"
	scale.Parent = button
	if text ~= "" then
		button.MouseEnter:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.05 }):Play()
		end)
		button.MouseLeave:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
		button.MouseButton1Down:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 0.94 }):Play()
		end)
		button.MouseButton1Up:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.03 }):Play()
		end)
	end
	return button
end

local cleanButton = makeButton("CleanEgg", "", Color3.fromRGB(72, 166, 95))
cleanButton.Size = UDim2.fromOffset(230, 196)
cleanButton.Position = UDim2.fromOffset(0, 32)
cleanButton.BackgroundTransparency = 1
cleanButton.Text = ""
local cleanButtonOutline = Instance.new("ImageLabel")
cleanButtonOutline.Name = "Outline"
cleanButtonOutline.AnchorPoint = Vector2.new(0.5, 0.5)
cleanButtonOutline.Position = UDim2.fromScale(0.5, 0.5)
cleanButtonOutline.Size = UDim2.fromOffset(232, 232)
cleanButtonOutline.BackgroundTransparency = 1
cleanButtonOutline.Image = CLEAN_BUTTON_IMAGE
cleanButtonOutline.ImageColor3 = Color3.fromRGB(76, 42, 20)
cleanButtonOutline.ImageTransparency = 0.05
cleanButtonOutline.ScaleType = Enum.ScaleType.Fit
cleanButtonOutline.ZIndex = cleanButton.ZIndex
cleanButtonOutline.Parent = cleanButton
local cleanButtonIcon = Instance.new("ImageLabel")
cleanButtonIcon.Name = "Icon"
cleanButtonIcon.AnchorPoint = Vector2.new(0.5, 0.5)
cleanButtonIcon.Position = UDim2.fromScale(0.5, 0.5)
cleanButtonIcon.Size = UDim2.fromOffset(208, 208)
cleanButtonIcon.BackgroundTransparency = 1
cleanButtonIcon.Image = CLEAN_BUTTON_IMAGE
cleanButtonIcon.ScaleType = Enum.ScaleType.Fit
cleanButtonIcon.ZIndex = cleanButton.ZIndex + 1
cleanButtonIcon.Parent = cleanButton
cleanButton.TextXAlignment = Enum.TextXAlignment.Center
cleanButton.Text = ""
local petButton = makeButton("PetEgg", "Acariciar huevo", Color3.fromRGB(217, 156, 72))
petButton.Visible = false

local alertHolder = Instance.new("Frame")
alertHolder.Name = "NeedAlerts"
alertHolder.AnchorPoint = Vector2.new(0.5, 0.5)
alertHolder.Position = UDim2.fromScale(0.5, 0.28)
alertHolder.Size = UDim2.fromOffset(520, 150)
alertHolder.BackgroundTransparency = 1
alertHolder.ZIndex = 9
alertHolder.Parent = gui

local alertLayout = Instance.new("UIListLayout")
alertLayout.FillDirection = Enum.FillDirection.Horizontal
alertLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
alertLayout.VerticalAlignment = Enum.VerticalAlignment.Center
alertLayout.Padding = UDim.new(0, 42)
alertLayout.Parent = alertHolder

local function makeAlertButton(name, image)
	local button = Instance.new("ImageLabel")
	button.Name = name
	button.Size = UDim2.fromOffset(128, 128)
	button.BackgroundTransparency = 1
	button.Image = image
	button.ScaleType = Enum.ScaleType.Fit
	button.ZIndex = alertHolder.ZIndex + 1
	button.Parent = alertHolder
	local outline = Instance.new("ImageLabel")
	outline.Name = "Outline"
	outline.AnchorPoint = Vector2.new(0.5, 0.5)
	outline.Position = UDim2.fromScale(0.5, 0.5)
	outline.Size = UDim2.fromOffset(138, 138)
	outline.BackgroundTransparency = 1
	outline.Image = image
	outline.ImageColor3 = Color3.fromRGB(76, 42, 20)
	outline.ImageTransparency = 0.08
	outline.ScaleType = Enum.ScaleType.Fit
	outline.ZIndex = button.ZIndex
	outline.Parent = button
	button.ZIndex = outline.ZIndex + 1
	return button
end

local sleepAlertButton = makeAlertButton("SleepAlert", SLEEP_ALERT_IMAGE)
local bathAlertButton = makeAlertButton("BathAlert", BATH_ALERT_IMAGE)
local foodAlertButton = makeAlertButton("FoodAlert", FOOD_ALERT_IMAGE)
alertHolder.Visible = false

local alertAnimationIndex = 0
local function animateAlertIcon(icon)
	local scale = icon:FindFirstChild("AlertScale") or Instance.new("UIScale")
	scale.Name = "AlertScale"
	scale.Scale = 1
	scale.Parent = icon
	alertAnimationIndex += 1
	local delayTime = alertAnimationIndex * 0.09
	task.spawn(function()
		task.wait(delayTime)
		while icon.Parent do
			if icon.Visible and alertHolder.Visible then
				TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.12 }):Play()
				task.wait(0.22)
				TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
			task.wait(1.2)
		end
	end)
end
animateAlertIcon(sleepAlertButton)
animateAlertIcon(bathAlertButton)
animateAlertIcon(foodAlertButton)

local cleanProgressBack = Instance.new("Frame")
cleanProgressBack.Name = "CleanProgress"
cleanProgressBack.AnchorPoint = Vector2.new(0.5, 0.5)
cleanProgressBack.Position = UDim2.fromScale(0.5, 0.765)
cleanProgressBack.Size = UDim2.fromOffset(280, 22)
cleanProgressBack.BackgroundColor3 = Color3.fromRGB(64, 43, 28)
cleanProgressBack.BorderSizePixel = 0
cleanProgressBack.Visible = false
cleanProgressBack.ZIndex = 7
cleanProgressBack.Parent = gui
addCorner(cleanProgressBack, 9)
addStroke(cleanProgressBack, Color3.fromRGB(255, 248, 224), 2)

local cleanProgressFill = Instance.new("Frame")
cleanProgressFill.Name = "Fill"
cleanProgressFill.Size = UDim2.fromScale(0, 1)
cleanProgressFill.BackgroundColor3 = Color3.fromRGB(94, 213, 128)
cleanProgressFill.BorderSizePixel = 0
cleanProgressFill.ZIndex = 8
cleanProgressFill.Parent = cleanProgressBack
addCorner(cleanProgressFill, 9)

local dirtLayer = Instance.new("Frame")
dirtLayer.Name = "DirtLayer"
dirtLayer.Size = UDim2.fromScale(1, 1)
dirtLayer.BackgroundTransparency = 1
dirtLayer.Visible = false
dirtLayer.ZIndex = 12
dirtLayer.Parent = gui

local soapLayer = Instance.new("Frame")
soapLayer.Name = "SoapLayer"
soapLayer.Size = UDim2.fromScale(1, 1)
soapLayer.BackgroundTransparency = 1
soapLayer.Visible = false
soapLayer.ZIndex = 14
soapLayer.Parent = gui

local spongeCursor = Instance.new("ImageLabel")
spongeCursor.Name = "SpongeCursor"
spongeCursor.AnchorPoint = Vector2.new(0.18, 0.18)
spongeCursor.Size = UDim2.fromOffset(54, 54)
spongeCursor.BackgroundTransparency = 1
spongeCursor.Image = SPONGE_CURSOR_IMAGE
spongeCursor.ScaleType = Enum.ScaleType.Fit
spongeCursor.Visible = false
spongeCursor.ZIndex = 30
spongeCursor.Parent = gui

local hoverGui = Instance.new("ScreenGui")
hoverGui.Name = "EggCareClickCursorGui"
hoverGui.ResetOnSpawn = false
hoverGui.IgnoreGuiInset = true
hoverGui.DisplayOrder = 100001
hoverGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
hoverGui.Enabled = true
hoverGui.Parent = playerGui

local clickHandCursor = Instance.new("ImageLabel")
clickHandCursor.Name = "ClickHandCursor"
clickHandCursor.AnchorPoint = Vector2.new(0.18, 0.08)
clickHandCursor.Size = UDim2.fromOffset(46, 46)
clickHandCursor.BackgroundTransparency = 1
clickHandCursor.Image = CLICK_CURSOR_IMAGE
clickHandCursor.ScaleType = Enum.ScaleType.Fit
clickHandCursor.Visible = false
clickHandCursor.ZIndex = 100
clickHandCursor.Parent = hoverGui

local pettingCursor = Instance.new("ImageLabel")
pettingCursor.Name = "PettingCursor"
pettingCursor.AnchorPoint = Vector2.new(0.22, 0.12)
pettingCursor.Size = UDim2.fromOffset(58, 58)
pettingCursor.BackgroundTransparency = 1
pettingCursor.Image = PETTING_CURSOR_IMAGE
pettingCursor.ScaleType = Enum.ScaleType.Fit
pettingCursor.Visible = false
pettingCursor.ZIndex = 31
pettingCursor.Parent = gui

local message = Instance.new("TextLabel")
message.Name = "Message"
message.AnchorPoint = Vector2.new(0.5, 0.5)
message.Position = UDim2.fromScale(0.5, 0.12)
message.Size = UDim2.fromOffset(560, 48)
message.BackgroundTransparency = 1
message.Text = ""
message.Font = FONT
message.TextScaled = true
message.TextColor3 = Color3.fromRGB(255, 248, 222)
message.TextStrokeColor3 = Color3.fromRGB(77, 43, 14)
message.TextStrokeTransparency = 0
message.Visible = false
message.ZIndex = 11
message.Parent = gui

local viewScale = Instance.new("UIScale")
viewScale.Name = "ViewScale"
viewScale.Scale = 1
viewScale.Parent = viewport

local function showMessage(text)
	message.Text = tostring(text or "")
	message.Visible = true
	message.TextTransparency = 0
	message.TextStrokeTransparency = 0
	message.Position = UDim2.fromScale(0.5, 0.12)
	TweenService:Create(message, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.10) }):Play()
	task.delay(1.6, function()
		if message.Text == text then
			TweenService:Create(message, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.wait(0.28)
			if message.Text == text then message.Visible = false end
		end
	end)
end

local function playEatingSound()
	local sound = Instance.new("Sound")
	sound.Name = "PetEatingSound"
	sound.SoundId = EAT_SOUND_ID
	sound.Volume = 0.7
	sound.PlaybackSpeed = 1 + (math.random(-6, 6) * 0.01)
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		if sound.Parent then sound:Destroy() end
	end)
	task.delay(3, function()
		if sound.Parent then sound:Destroy() end
	end)
end

local function getSelectedPetName()
	local selected = tostring(player:GetAttribute("SelectedBackpackPet") or "")
	if selected ~= "" then
		return selected
	end
	return EGG_NAME
end

local function isOwnedEggModel(object)
	if not object:IsA("Model") or object:GetAttribute("Owner") ~= player.UserId then
		return false
	end
	local petType = tostring(object:GetAttribute("PetType") or "")
	if petType == "" then
		return false
	end
	return petType == getSelectedPetName()
end

local function getOwnedEggModels()
	local models = {}
	for _, object in ipairs(workspace:GetChildren()) do
		if isOwnedEggModel(object) then
			if object:GetAttribute("ClientPetVisual") == true or object.Name:find("_ClientVisual", 1, true) then
				table.insert(models, 1, object)
			else
				table.insert(models, object)
			end
		end
	end
	return models
end

local function findOwnedEggModel()
	return getOwnedEggModels()[1]
end

local closeView
local openView

local function getPetPromptRoot(model)
	if not model then return nil end
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if root and root:IsA("BasePart") then return root end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function ensurePetMenuPrompt()
	local model = findOwnedEggModel()
	local root = getPetPromptRoot(model)
	if not root then return nil end
	for _, object in ipairs(workspace:GetDescendants()) do
		if object:IsA("ProximityPrompt") and object.Name == PET_MENU_PROMPT_NAME and object.Parent ~= root then
			object:Destroy()
		end
	end
	local prompt = root:FindFirstChild(PET_MENU_PROMPT_NAME) or Instance.new("ProximityPrompt")
	prompt.Name = PET_MENU_PROMPT_NAME
	prompt.ActionText = ""
	prompt.ObjectText = ""
	prompt.KeyboardKeyCode = PET_MENU_PROMPT_KEY
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Enabled = not open
	prompt.Parent = root
	if not petMenuPromptConnection or petMenuPromptConnection.Connected == false then
		petMenuPromptConnection = prompt.Triggered:Connect(function()
			if open then
				closeView()
			else
				openView()
			end
		end)
	end
	return prompt
end

local function canUsePetMenuPrompt()
	return findOwnedEggModel() ~= nil
end

local function getOwnedPetValue(petName)
	petName = tostring(petName or "")
	for _, folderName in ipairs({ "TradePetsInventory", "Pets", "Mascotas" }) do
		local petsFolder = player:FindFirstChild(folderName)
		if petsFolder then
			local direct = petsFolder:FindFirstChild(petName)
			if direct then return direct end
			for _, value in ipairs(petsFolder:GetChildren()) do
				if tostring(value:GetAttribute("ItemName") or value.Name) == petName then
					return value
				end
			end
		end
	end
	return nil
end

local function getOwnedEggValue()
	return getOwnedPetValue(EGG_NAME)
end

local function getSelectedPetValue()
	return getOwnedPetValue(getSelectedPetName()) or getOwnedEggValue()
end

local function isOwnedEggDirty()
	local eggValue = getOwnedEggValue()
	if eggValue and eggValue:GetAttribute("Dirty") == true then
		return true
	end
	local eggModel = findOwnedEggModel()
	return eggModel and (eggModel:GetAttribute("EggWantedDirty") == true or eggModel:GetAttribute("EggActualDirty") == true) or false
end

local function isSelectedPetTired()
	local petValue = getSelectedPetValue()
	return petValue and (petValue:GetAttribute("Tired") == true or petValue:GetAttribute("Resting") == true) or false
end

local function isSelectedPetHungry()
	local petValue = getSelectedPetValue()
	return petValue and petValue:GetAttribute("Hungry") == true or false
end

local function setAlertButtonVisible(button, visible)
	button.Visible = visible
	button.Size = visible and UDim2.fromOffset(128, 128) or UDim2.fromOffset(0, 128)
end

local function updateNeedAlerts()
	if not open or cleaningActive then
		alertHolder.Visible = false
		return
	end
	local selectedName = getSelectedPetName()
	local isEggMenu = selectedName == EGG_NAME
	local needsBath = isEggMenu and isOwnedEggDirty()
	local needsSleep = isSelectedPetTired()
	local needsFood = isSelectedPetHungry()
	setAlertButtonVisible(bathAlertButton, needsBath)
	setAlertButtonVisible(sleepAlertButton, needsSleep)
	setAlertButtonVisible(foodAlertButton, needsFood)
	alertHolder.Visible = needsBath or needsSleep or needsFood
end

local function updateCleanButtonVisibility()
	cleanButton.Visible = not cleaningCompleted and (cleaningActive or isOwnedEggDirty())
end

local function markEggCleanLocally()
	local eggValue = getOwnedEggValue()
	if eggValue then
		eggValue:SetAttribute("Dirty", false)
	end
	for _, eggModel in ipairs(getOwnedEggModels()) do
		eggModel:SetAttribute("EggWantedDirty", false)
		eggModel:SetAttribute("EggActualDirty", false)
	end
end

local function isInsideOwnedEgg(instance)
	if not instance then return false end
	for _, egg in ipairs(getOwnedEggModels()) do
		if instance:IsDescendantOf(egg) then
			return true
		end
	end
	return false
end

local function getEggScreenBounds()
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	for _, egg in ipairs(getOwnedEggModels()) do
		local cf, size = egg:GetBoundingBox()
		local half = size * 0.5
		local minX, minY = math.huge, math.huge
		local maxX, maxY = -math.huge, -math.huge
		local visiblePoints = 0
		for _, x in ipairs({ -half.X, half.X }) do
			for _, y in ipairs({ -half.Y, half.Y }) do
				for _, z in ipairs({ -half.Z, half.Z }) do
					local point, visible = camera:WorldToViewportPoint((cf * CFrame.new(x, y, z)).Position)
					if visible then
						visiblePoints += 1
						minX = math.min(minX, point.X)
						maxX = math.max(maxX, point.X)
						minY = math.min(minY, point.Y)
						maxY = math.max(maxY, point.Y)
					end
				end
			end
		end
		if visiblePoints > 0 then
			local padding = 10
			local centerScreen = Vector2.new((minX + maxX) * 0.5, (minY + maxY) * 0.5)
			local radiusX = math.max((maxX - minX) * 0.5 + padding, 18)
			local radiusY = math.max((maxY - minY) * 0.5 + padding, 18)
			return centerScreen, math.max(radiusX, radiusY), size, radiusX, radiusY, minY, maxY
		end
	end
	return nil
end

local function updateNeedAlertPosition()
	local centerScreen, _, _, _, _, minY = getEggScreenBounds()
	if not centerScreen or not minY then return end
	alertHolder.Position = UDim2.fromOffset(centerScreen.X, math.max(76, minY - 68))
end

local function isPointInsideGui(guiObject, screenPosition)
	if not guiObject or not guiObject.Parent then return false end
	local position = guiObject.AbsolutePosition
	local size = guiObject.AbsoluteSize
	return screenPosition.X >= position.X and screenPosition.X <= position.X + size.X and screenPosition.Y >= position.Y and screenPosition.Y <= position.Y + size.Y
end

local function isMouseOverCleanButton()
	return open and cleanButton.Visible and isPointInsideGui(cleanButton, UserInputService:GetMouseLocation())
end

local function isClickNearOwnedEgg(screenPosition)
	local centerScreen, _, _, radiusX, radiusY = getEggScreenBounds()
	if not centerScreen then return false end
	local dx = (screenPosition.X - centerScreen.X) / radiusX
	local dy = (screenPosition.Y - centerScreen.Y) / radiusY
	return (dx * dx + dy * dy) <= 1
end

local function getPointedOwnedEgg(screenPosition)
	if not isClickNearOwnedEgg(screenPosition) then
		return nil
	end
	return findOwnedEggModel()
end

local function isHoveringOwnedEgg(screenPosition)
	return getPointedOwnedEgg(screenPosition) ~= nil
end

local function setClickableCursor(active)
	if cleaningActive or open then active = false end
	local mousePosition = UserInputService:GetMouseLocation()
	clickHandCursor.Position = UDim2.fromOffset(mousePosition.X, mousePosition.Y)
	clickHandCursor.Visible = active
	if active == hoverCursorActive then return end
	hoverCursorActive = active
	if active then
		if previousMouseIcon == nil then
			previousMouseIcon = mouse.Icon
		end
		pcall(function()
			mouse.Icon = CLICK_CURSOR_IMAGE
		end)
	else
		if previousMouseIcon ~= nil then
			pcall(function()
				mouse.Icon = previousMouseIcon
			end)
			previousMouseIcon = nil
		else
			pcall(function()
				mouse.Icon = ""
			end)
		end
	end
end

local function setPettingCursor(active)
	if cleaningActive or not open then active = false end
	local mousePosition = UserInputService:GetMouseLocation()
	pettingCursor.Position = UDim2.fromOffset(mousePosition.X, mousePosition.Y)
	pettingCursor.Visible = active
	if active then
		if previousPetMouseIconEnabled == nil then
			previousPetMouseIconEnabled = UserInputService.MouseIconEnabled
		end
		UserInputService.MouseIconEnabled = false
	else
		if previousPetMouseIconEnabled ~= nil then
			UserInputService.MouseIconEnabled = previousPetMouseIconEnabled
			previousPetMouseIconEnabled = nil
		end
		if open and not cleaningActive then
			UserInputService.MouseIconEnabled = true
		end
	end
end

local function clearSoapSpots()
	for _, spot in ipairs(soapSpots) do
		local frame = typeof(spot) == "table" and spot.frame or spot
		if frame and frame.Parent then
			frame:Destroy()
		end
	end
	table.clear(soapSpots)
	soapLayer.Visible = false
end

local function clearDirtSpots()
	for _, spot in ipairs(dirtSpots) do
		if spot.button then
			spot.button:Destroy()
		end
	end
	table.clear(dirtSpots)
	dirtLayer.Visible = false
end

local fillEggWithSoap
local fadeSoapAfterClean

local function finishCleaningIfReady()
	if cleaningProgress >= 1 and cleaningActive then
		cleaningCompleted = true
		fillEggWithSoap(true)
		setCleaningMode(false)
		task.defer(function()
			if open then
				callCare("Clean")
			end
		end)
	end
end

local function setCleanProgress(value)
	cleaningProgress = math.clamp(value, 0, 1)
	cleanProgressFill.Size = UDim2.fromScale(cleaningProgress, 1)
	finishCleaningIfReady()
end

local function updateCleanProgress()
	setCleanProgress(cleaningProgress)
end

local function updateDirtSpotPositions()
	local centerScreen, radius = getEggScreenBounds()
	if not centerScreen then return end
	for _, spot in ipairs(dirtSpots) do
		local button = spot.button
		if button and button.Parent then
			local x = centerScreen.X + spot.offset.X * radius
			local y = centerScreen.Y + spot.offset.Y * radius * 0.82
			button.Position = UDim2.fromOffset(x, y)
		end
	end
end

local function spawnSoapBubble(screenPosition, forcedOffset, big)
	soapLayer.Visible = true
	local centerScreen, radius = getEggScreenBounds()
	local jitter = Vector2.new(math.random(-12, 12), math.random(-10, 10))
	local offset = forcedOffset
	if not offset and centerScreen and radius then
		offset = Vector2.new((screenPosition.X - centerScreen.X + jitter.X) / radius, (screenPosition.Y - centerScreen.Y + jitter.Y) / (radius * 0.82))
	end
	if offset and centerScreen and radius then
		screenPosition = Vector2.new(centerScreen.X + offset.X * radius, centerScreen.Y + offset.Y * radius * 0.82)
	end
	local foam = Instance.new("Frame")
	foam.Name = big and "SoapBlanket" or "SoapFoam"
	foam.AnchorPoint = Vector2.new(0.5, 0.5)
	foam.Position = UDim2.fromOffset(screenPosition.X + jitter.X, screenPosition.Y + jitter.Y)
	local width = big and math.random(68, 98) or math.random(42, 66)
	local height = big and math.random(52, 80) or math.random(32, 52)
	foam.Size = UDim2.fromOffset(width, height)
	foam.BackgroundColor3 = Color3.fromRGB(238, 252, 255)
	foam.BackgroundTransparency = big and 0.01 or 0.09
	foam.BorderSizePixel = 0
	foam.Rotation = math.random(-22, 22)
	foam.ZIndex = big and 17 or 15
	foam.Parent = soapLayer
	addCorner(foam, 40)
	local stroke = addStroke(foam, Color3.fromRGB(176, 229, 255), big and 2 or 1.5)
	stroke.Transparency = big and 0.22 or 0.32
	local shine = Instance.new("Frame")
	shine.Name = "BubbleShine"
	shine.AnchorPoint = Vector2.new(0.5, 0.5)
	shine.Position = UDim2.fromScale(0.34, 0.32)
	shine.Size = UDim2.fromScale(0.34, 0.22)
	shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	shine.BackgroundTransparency = 0.35
	shine.BorderSizePixel = 0
	shine.ZIndex = foam.ZIndex + 1
	shine.Parent = foam
	addCorner(shine, 24)
	table.insert(soapSpots, { frame = foam, offset = offset })
	TweenService:Create(foam, TweenInfo.new(big and 0.1 or 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = foam.Size + UDim2.fromOffset(big and 18 or 8, big and 14 or 6),
		BackgroundTransparency = big and 0 or 0.06,
	}):Play()
	if #soapSpots > MAX_SOAP_SPOTS then
		local old = table.remove(soapSpots, 1)
		local oldFrame = old and old.frame or old
		if oldFrame and oldFrame.Parent then oldFrame:Destroy() end
	end
end

fadeSoapAfterClean = function()
	soapLayer.Visible = true
	for _, spot in ipairs(soapSpots) do
		local frame = typeof(spot) == "table" and spot.frame or spot
		if frame and frame.Parent then
			TweenService:Create(frame, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = 1,
				Size = frame.Size + UDim2.fromOffset(18, 14),
			}):Play()
			local stroke = frame:FindFirstChildOfClass("UIStroke")
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
			end
			local shine = frame:FindFirstChild("BubbleShine")
			if shine then
				TweenService:Create(shine, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
			end
		end
	end
	task.delay(0.42, function()
		clearSoapSpots()
		cleaningCompleted = false
		updateCleanButtonVisibility()
	end)
end

fillEggWithSoap = function(finalCover)
	local centerScreen, radius = getEggScreenBounds()
	if not centerScreen or not radius then return end
	soapLayer.Visible = true
	local rows = finalCover and {
		{ y = -0.66, count = 4, width = 0.42 },
		{ y = -0.48, count = 6, width = 0.62 },
		{ y = -0.28, count = 7, width = 0.78 },
		{ y = -0.08, count = 8, width = 0.9 },
		{ y = 0.12, count = 8, width = 0.9 },
		{ y = 0.32, count = 7, width = 0.78 },
		{ y = 0.5, count = 6, width = 0.62 },
		{ y = 0.66, count = 4, width = 0.42 },
	} or {
		{ y = -0.46, count = 4, width = 0.55 },
		{ y = -0.16, count = 5, width = 0.72 },
		{ y = 0.14, count = 5, width = 0.72 },
		{ y = 0.44, count = 4, width = 0.55 },
	}
	for _, row in ipairs(rows) do
		for index = 1, row.count do
			local x = row.count == 1 and 0 or ((index - 1) / (row.count - 1) - 0.5) * row.width * 2
			local offset = Vector2.new(x + math.random(-6, 6) / 100, row.y + math.random(-5, 5) / 100)
			if offset.X * offset.X + (offset.Y / 0.82) * (offset.Y / 0.82) <= 0.95 then
				spawnSoapBubble(centerScreen, offset, finalCover)
			end
		end
	end
end

local function updateSoapSpotPositions()
	local centerScreen, radius = getEggScreenBounds()
	if not centerScreen or not radius then return end
	for _, spot in ipairs(soapSpots) do
		local frame = spot.frame
		if frame and frame.Parent and spot.offset then
			frame.Position = UDim2.fromOffset(centerScreen.X + spot.offset.X * radius, centerScreen.Y + spot.offset.Y * radius * 0.82)
		end
	end
end

local function updateSpongeCursor()
	if not cleaningActive then return end
	local mousePosition = UserInputService:GetMouseLocation()
	spongeCursor.Position = UDim2.fromOffset(mousePosition.X, mousePosition.Y)
end

local function cleanDirtSpot(data, screenPosition)
	if not data or data.cleaned then return false end
	local spot = data.button
	if not spot or not spot.Parent then return false end
	data.cleaned = true
	data.scrub = 1
	spot.Active = false
	spawnSoapBubble(screenPosition or UserInputService:GetMouseLocation())
	showCareBillboard("✦")
	TweenService:Create(spot, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = UDim2.fromOffset(4, 4),
		BackgroundTransparency = 1,
		Rotation = spot.Rotation + 25,
	}):Play()
	local stroke = spot:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
	end
	task.delay(0.2, function()
		if spot then spot:Destroy() end
		updateCleanProgress()
	end)
	return true
end

local function cleanDirtAt(screenPosition, dt)
	if not isClickNearOwnedEgg(screenPosition) then return false end
	spawnSoapBubble(screenPosition)
	if math.random() < 0.55 then
		local centerScreen, radius = getEggScreenBounds()
		if centerScreen and radius then
			local offset = Vector2.new((screenPosition.X - centerScreen.X) / radius + math.random(-9, 9) / 100, (screenPosition.Y - centerScreen.Y) / (radius * 0.82) + math.random(-9, 9) / 100)
			spawnSoapBubble(screenPosition, offset, false)
		end
	end
	if cleaningProgress > 0.34 and #soapSpots < 82 then
		fillEggWithSoap(false)
	end
	if dt and dt > 0 then
		setCleanProgress(cleaningProgress + dt / WASH_SECONDS)
	else
		setCleanProgress(cleaningProgress + 0.035)
	end
	return true
end

local function makeDirtSpot(index, offset, size)
	local spot = Instance.new("ImageButton")
	spot.Name = "DirtSpot" .. index
	spot.AnchorPoint = Vector2.new(0.5, 0.5)
	spot.Size = UDim2.fromOffset(size, math.floor(size * 0.72))
	spot.BackgroundColor3 = Color3.fromRGB(91, 58, 30)
	spot.BackgroundTransparency = 0.08
	spot.BorderSizePixel = 0
	spot.AutoButtonColor = false
	spot.Image = ""
	spot.Rotation = math.random(-18, 18)
	spot.ZIndex = 13
	spot.Parent = dirtLayer
	addCorner(spot, size)
	local stroke = addStroke(spot, Color3.fromRGB(56, 36, 19), 2)
	stroke.Transparency = 0.25
	local shine = Instance.new("Frame")
	shine.Name = "SoftPatch"
	shine.AnchorPoint = Vector2.new(0.5, 0.5)
	shine.Position = UDim2.fromScale(0.35, 0.35)
	shine.Size = UDim2.fromScale(0.46, 0.35)
	shine.BackgroundColor3 = Color3.fromRGB(122, 82, 43)
	shine.BackgroundTransparency = 0.28
	shine.BorderSizePixel = 0
	shine.ZIndex = spot.ZIndex + 1
	shine.Parent = spot
	addCorner(shine, size)
	local data = { button = spot, offset = offset, cleaned = false, scrub = 0 }
	table.insert(dirtSpots, data)
	spot.Activated:Connect(function()
		if not cleaningActive or busy then return end
		cleanDirtSpot(data, UserInputService:GetMouseLocation())
	end)
end

local function createDirtSpots()
	clearDirtSpots()
	dirtLayer.Visible = false
	updateCleanProgress()
end

local function clearViewport()
	for _, child in ipairs(viewport:GetChildren()) do
		if child:IsA("Model") then child:Destroy() end
	end
	viewportModel = nil
end

local function getEggAdornee(egg)
	if not egg then return nil end
	if egg.PrimaryPart then return egg.PrimaryPart end
	return egg:FindFirstChildWhichIsA("BasePart", true)
end

local function removeCareBillboard()
	if careBillboard then
		careBillboard:Destroy()
		careBillboard = nil
	end
end

local function spawnFloatingHeart()
	local camera = workspace.CurrentCamera
	local egg = findOwnedEggModel()
	if not camera or not egg then return end
	local cf, size = egg:GetBoundingBox()
	local top = cf.Position + Vector3.new(0, math.max(size.Y * 0.58, 1.2), 0)
	local screenPoint, visible = camera:WorldToViewportPoint(top)
	if not visible then return end
	local heart = Instance.new("ImageLabel")
	heart.Name = "PetHeart"
	heart.AnchorPoint = Vector2.new(0.5, 0.5)
	heart.Position = UDim2.fromOffset(screenPoint.X + math.random(-45, 45), screenPoint.Y + math.random(-18, 18))
	heart.Size = UDim2.fromOffset(44, 44)
	heart.BackgroundTransparency = 1
	heart.Image = HEART_IMAGE
	heart.ImageTransparency = 0
	heart.ScaleType = Enum.ScaleType.Fit
	heart.Rotation = math.random(-15, 15)
	heart.ZIndex = 12
	heart.Parent = gui
	TweenService:Create(heart, TweenInfo.new(0.72, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = heart.Position - UDim2.fromOffset(math.random(-20, 20), 74),
		ImageTransparency = 1,
		Rotation = heart.Rotation + math.random(-18, 18),
	}):Play()
	task.delay(0.9, function()
		if heart then heart:Destroy() end
	end)
end

local function getCareAnimationId(model, animationName)
	local petType = model and tostring(model:GetAttribute("PetType") or "") or ""
	local configName = PET_CONFIG_ALIASES[petType] or petType
	local config = PetConfigs[configName]
	local animationId = config and config[animationName]
	if type(animationId) == "string" and animationId ~= "" then
		return animationId
	end
	if animationName == "Celebrate" then
		return CELEBRATION_ANIMATION_ID
	end
	return nil
end

-- Token para que varias caricias seguidas no apaguen antes
-- la celebración más reciente.
local careCelebrateToken = 0

local function playCareAnimation(animationName, stopAfterSeconds, withHearts)
	local egg = findOwnedEggModel()
	if not egg then return end

	-- IMPORTANTE:
	-- PetRenderer_StableSideFollower es quien controla el modelo visible.
	-- Para Celebrate NO cargamos otro AnimationTrack aquí.
	-- Le pedimos al renderer que reproduzca SU pista Celebrate.
	if animationName == "Celebrate" then
		careCelebrateToken += 1
		local token = careCelebrateToken

		local previousOverride = player:GetAttribute("AdminPetAnimationOverride")
		local previousSpeed = player:GetAttribute("AdminPetAnimationSpeed")

		player:SetAttribute("AdminPetAnimationOverride", "Celebrate")
		player:SetAttribute("AdminPetAnimationSpeed", 1)

		if withHearts then
			for index = 1, 4 do
				task.delay((index - 1) * 0.08, function()
					if token == careCelebrateToken then
						spawnFloatingHeart()
					end
				end)
			end
		end

		-- Damos tiempo suficiente para que la animación se vea claramente.
		task.delay(stopAfterSeconds or 2.0, function()
			if token ~= careCelebrateToken then
				return
			end

			if player:GetAttribute("AdminPetAnimationOverride") == "Celebrate" then
				if typeof(previousOverride) == "string" and previousOverride ~= "Celebrate" then
					player:SetAttribute("AdminPetAnimationOverride", previousOverride)
				else
					player:SetAttribute("AdminPetAnimationOverride", "")
				end

				if typeof(previousSpeed) == "number" then
					player:SetAttribute("AdminPetAnimationSpeed", previousSpeed)
				else
					player:SetAttribute("AdminPetAnimationSpeed", 1)
				end
			end
		end)

		return
	end

	-- Las demás animaciones de cuidado conservan el sistema anterior.
	local careAnimationId = getCareAnimationId(egg, animationName)
	if not careAnimationId then return end

	local humanoid = egg:FindFirstChildWhichIsA("Humanoid", true)
	local controller = egg:FindFirstChildWhichIsA("AnimationController", true)

	if not humanoid and not controller then
		controller = Instance.new("AnimationController")
		controller.Name = "CareAnimationController"
		controller.Parent = egg
	end

	local animatorParent = humanoid or controller
	local animator = animatorParent and animatorParent:FindFirstChildWhichIsA("Animator")

	if animatorParent and not animator then
		animator = Instance.new("Animator")
		animator.Parent = animatorParent
	end

	if animator then
		pcall(function()
			if celebrationTrack then
				celebrationTrack:Stop(0.05)
				celebrationTrack = nil
			end

			local animation = Instance.new("Animation")
			animation.AnimationId = careAnimationId

			local track = animator:LoadAnimation(animation)
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = false
			track:Play(0.06, 1, 1)

			celebrationTrack = track

			task.delay(stopAfterSeconds or 1.05, function()
				if track then
					pcall(function()
						track:Stop(0.1)
					end)
				end
				if celebrationTrack == track then
					celebrationTrack = nil
				end
				animation:Destroy()
			end)
		end)
	end

	if withHearts then
		for index = 1, 3 do
			task.delay((index - 1) * 0.07, spawnFloatingHeart)
		end
	end
end

local function playCelebrationAnimation()
	playCareAnimation("Celebrate", 3.2, true)
end

local function playEatAnimation()
	playCareAnimation("Eat", 1.05, false)
end

local function spawnCleanStars()
	local centerScreen, radius = getEggScreenBounds()
	if not centerScreen then return end
	for index = 1, 14 do
		task.delay((index - 1) * 0.035, function()
			local star = Instance.new("TextLabel")
			star.Name = "CleanStar"
			star.AnchorPoint = Vector2.new(0.5, 0.5)
			local angle = (index / 14) * math.pi * 2
			local startRadius = radius * (0.36 + math.random() * 0.34)
			local start = centerScreen + Vector2.new(math.cos(angle) * startRadius, math.sin(angle) * startRadius * 0.75)
			star.Position = UDim2.fromOffset(start.X, start.Y)
			star.Size = UDim2.fromOffset(42, 42)
			star.BackgroundTransparency = 1
			star.Font = FONT
			star.Text = "✦"
			star.TextScaled = true
			star.TextColor3 = Color3.fromRGB(255, 245, 156)
			star.TextStrokeColor3 = Color3.fromRGB(91, 50, 16)
			star.TextStrokeTransparency = 0
			star.Rotation = math.random(-24, 24)
			star.ZIndex = 28
			star.Parent = gui
			local drift = Vector2.new(math.cos(angle) * 52, math.sin(angle) * 38 - 48)
			TweenService:Create(star, TweenInfo.new(0.72, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(start.X + drift.X, start.Y + drift.Y),
				TextTransparency = 1,
				TextStrokeTransparency = 1,
				Rotation = star.Rotation + math.random(35, 85),
				Size = UDim2.fromOffset(18, 18),
			}):Play()
			task.delay(0.82, function()
				if star then star:Destroy() end
			end)
		end)
	end
end

local function showCareBillboard(text)
	if text == "♡" then
		spawnFloatingHeart()
		return
	end
	local egg = findOwnedEggModel()
	local adornee = getEggAdornee(egg)
	if not adornee then return end
	if not careBillboard or not careBillboard.Parent then
		careBillboard = Instance.new("BillboardGui")
		careBillboard.Name = "EggCareMouseFx"
		careBillboard.AlwaysOnTop = true
		careBillboard.Size = UDim2.fromOffset(130, 80)
		careBillboard.StudsOffsetWorldSpace = Vector3.new(0, 2.9, 0)
		careBillboard.Parent = gui
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = FONT
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 248, 224)
		label.TextStrokeColor3 = Color3.fromRGB(91, 47, 19)
		label.TextStrokeTransparency = 0
		label.Parent = careBillboard
	end
	careBillboard.Adornee = adornee
	local label = careBillboard:FindFirstChild("Label")
	if label then
		label.Text = text
		label.TextTransparency = 0
		label.TextStrokeTransparency = 0
		label.Position = UDim2.fromScale(0, 0)
		TweenService:Create(label, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0, -0.12) }):Play()
		task.delay(0.45, function()
			if label and label.Parent and label.Text == text then
				TweenService:Create(label, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1, Position = UDim2.fromScale(0, -0.3) }):Play()
			end
		end)
	end
end

local lastCareCameraPet = nil

local function getPetFrontDirection(model)
	if not model then
		return Vector3.new(0, 0, 1)
	end

	local root =
		getPetPromptRoot(model)

	if root then
		-- FIX V2:
		-- La prueba con la oveja confirmó que -LookVector mostraba
		-- la espalda. El frente visual real coincide con +LookVector.
		local front =
			root.CFrame.LookVector

		front =
			Vector3.new(
				front.X,
				0,
				front.Z
			)

		if front.Magnitude > 0.001 then
			return front.Unit
		end
	end

	local cf =
		model:GetBoundingBox()

	local fallback =
		cf.LookVector

	fallback =
		Vector3.new(
			fallback.X,
			0,
			fallback.Z
		)

	if fallback.Magnitude > 0.001 then
		return fallback.Unit
	end

	return Vector3.new(0, 0, 1)
end

local function applyCareCamera(instant)
	local camera =
		workspace.CurrentCamera

	local pet =
		findOwnedEggModel()

	if
		not camera
		or not pet
	then
		return
	end

	local cf, size =
		pet:GetBoundingBox()

	local center =
		cf.Position

	local maxSize =
		math.max(
			size.X,
			size.Y,
			size.Z,
			1
		)

	local front =
		getPetFrontDirection(
			pet
		)

	local cameraPos =
		center
		+ front
		* (
			maxSize
			* PET_CARE_CAMERA_DISTANCE_MULTIPLIER
		)
		+ Vector3.new(
			0,
			maxSize
			* PET_CARE_CAMERA_HEIGHT_MULTIPLIER,
			0
		)

	local target =
		center
		+ Vector3.new(
			0,
			maxSize
			* PET_CARE_CAMERA_TARGET_HEIGHT_MULTIPLIER,
			0
		)

	local goal =
		CFrame.lookAt(
			cameraPos,
			target,
			Vector3.yAxis
		)

	camera.CameraType =
		Enum.CameraType.Scriptable

	camera.FieldOfView =
		35

	-- Sin Lerp:
	-- evita que por algunos frames se vea costado/espalda.
	camera.CFrame =
		goal

	if lastCareCameraPet ~= pet then
		lastCareCameraPet =
			pet

		print(
			"[PetMenuHotkey] CAMARA FRONTAL |",
			tostring(
				pet:GetAttribute("PetType")
					or pet.Name
			),
			"| root:",
			getPetPromptRoot(pet)
				and getPetPromptRoot(pet):GetFullName()
				or "sin root"
		)
	end
end

local function stopCareCameraFollow()
	RunService:UnbindFromRenderStep(
		PET_CARE_CAMERA_STEP
	)
end

local function startCareCameraFollow()
	stopCareCameraFollow()

	RunService:BindToRenderStep(
		PET_CARE_CAMERA_STEP,
		PET_CARE_CAMERA_PRIORITY,
		function()
			if
				open
				and gui.Enabled
			then
				applyCareCamera(
					false
				)
			end
		end
	)
end

local function restoreCamera()
	local camera = workspace.CurrentCamera
	if not camera then return end
	if oldCameraState then
		camera.CameraType = oldCameraState.cameraType
		camera.CameraSubject = oldCameraState.subject
		camera.FieldOfView = oldCameraState.fov
		camera.CFrame = oldCameraState.cframe
	else
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		camera.CameraType = Enum.CameraType.Custom
		if humanoid then
			camera.CameraSubject = humanoid
		end
		camera.FieldOfView = 70
	end
	if camera.CameraType == Enum.CameraType.Scriptable then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		camera.CameraType = Enum.CameraType.Custom
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
	oldCameraState = nil
end

setCleaningMode = function(active)
	if active and not isOwnedEggDirty() then
		clearSoapSpots()
		return
	end
	cleaningActive = active
	cleanProgressBack.Visible = active
	updateNeedAlerts()
	updateCleanButtonVisibility()
	cleanButton.Text = ""
	if active then
		cleaningCompleted = false
		cleaningProgress = 0
		cleanProgressFill.Size = UDim2.fromScale(0, 1)
		if previousMouseIconEnabled == nil then
			previousMouseIconEnabled = UserInputService.MouseIconEnabled
		end
		setClickableCursor(false)
		setPettingCursor(false)
		UserInputService.MouseIconEnabled = false
		cleanButton.Visible = true
		soapLayer.Visible = true
		spongeCursor.Visible = true
		updateSpongeCursor()
		createDirtSpots()
	else
		if previousMouseIconEnabled ~= nil then
			UserInputService.MouseIconEnabled = previousMouseIconEnabled
			previousMouseIconEnabled = nil
		end
		spongeCursor.Visible = false
		clearDirtSpots()
		if not cleaningCompleted then
			clearSoapSpots()
		end
		updateCleanButtonVisibility()
	end
end

local function disconnectHudSuppression()
	for _, connection in ipairs(hudSuppressConnections) do
		connection:Disconnect()
	end
	table.clear(hudSuppressConnections)
end

local function getPlayerControls()
	if playerControls then
		return playerControls
	end
	local playerScripts = player:FindFirstChild("PlayerScripts")
	local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if not playerModule then
		return nil
	end
	local ok, module = pcall(require, playerModule)
	if ok and module and module.GetControls then
		local controlsOk, controls = pcall(function()
			return module:GetControls()
		end)
		if controlsOk then
			playerControls = controls
		end
	end
	return playerControls
end

local function disablePlayerControls()
	if controlsDisabled then return end
	local controls = getPlayerControls()
	if controls and controls.Disable then
		pcall(function()
			controls:Disable()
		end)
		controlsDisabled = true
	end
end

local function enablePlayerControls()
	if not controlsDisabled then return end
	local controls = getPlayerControls()
	if controls and controls.Enable then
		pcall(function()
			controls:Enable()
		end)
	end
	controlsDisabled = false
end

local function watchScreenGui(screenGui)
	if not screenGui:IsA("ScreenGui") or screenGui == gui then return end
	table.insert(hudSuppressConnections, screenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if open and screenGui ~= hoverGui and screenGui.Enabled then
			if hiddenGuiStates[screenGui] == nil then
				hiddenGuiStates[screenGui] = {
					Parent = screenGui.Parent,
					Enabled = screenGui.Enabled,
				}
			end
			screenGui.Enabled = false
			screenGui.Parent = hiddenGuiFolder
		end
	end))
end

local function suppressHudNow()
	if not open or closingView then return end
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") and child ~= gui and child ~= hoverGui then
			if hiddenGuiStates[child] == nil then
				hiddenGuiStates[child] = {
					Parent = child.Parent,
					Enabled = child.Enabled,
				}
			end
			child.Enabled = false
			child.Parent = hiddenGuiFolder
		end
	end
	pcall(function()
		for _, coreGuiType in ipairs(CORE_GUI_TYPES_TO_HIDE) do
			StarterGui:SetCoreGuiEnabled(coreGuiType, false)
		end
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		StarterGui:SetCore("TopbarEnabled", false)
		StarterGui:SetCore("ResetButtonCallback", false)
		coreHidden = true
	end)
end

local function updateBackgroundFocus(instant)
	local camera = workspace.CurrentCamera
	local egg = findOwnedEggModel()
	if not camera or not egg or not careDepthOfField then return end
	local cf = egg:GetBoundingBox()
	local distance = (camera.CFrame.Position - cf.Position).Magnitude
	careDepthOfField.Enabled = true
	careDepthOfField.FocusDistance = distance
	careDepthOfField.InFocusRadius = math.max(5, egg:GetExtentsSize().Magnitude * 1.1)
	careDepthOfField.NearIntensity = 0
	local targetFar = 0.92
	if instant then
		careDepthOfField.FarIntensity = targetFar
	else
		careDepthOfField.FarIntensity = careDepthOfField.FarIntensity + (targetFar - careDepthOfField.FarIntensity) * 0.18
	end
end

local function applyBackgroundBlur()
	careDepthOfField = Lighting:FindFirstChild("EggCareBackgroundFocus")
	if careDepthOfField and not careDepthOfField:IsA("DepthOfFieldEffect") then
		careDepthOfField = nil
	end
	if not careDepthOfField then
		careDepthOfField = Instance.new("DepthOfFieldEffect")
		careDepthOfField.Name = "EggCareBackgroundFocus"
		careDepthOfField.Enabled = true
		careDepthOfField.FarIntensity = 0
		careDepthOfField.NearIntensity = 0
		careDepthOfField.InFocusRadius = 5
		careDepthOfField.Parent = Lighting
		previousDepthProps = nil
	else
		previousDepthProps = {
			Enabled = careDepthOfField.Enabled,
			FarIntensity = careDepthOfField.FarIntensity,
			NearIntensity = careDepthOfField.NearIntensity,
			FocusDistance = careDepthOfField.FocusDistance,
			InFocusRadius = careDepthOfField.InFocusRadius,
		}
	end
	updateBackgroundFocus(true)
end

local function removeBackgroundBlur()
	if not careDepthOfField then return end
	local effect = careDepthOfField
	if previousDepthProps then
		effect.Enabled = previousDepthProps.Enabled
		effect.FarIntensity = previousDepthProps.FarIntensity
		effect.NearIntensity = previousDepthProps.NearIntensity
		effect.FocusDistance = previousDepthProps.FocusDistance
		effect.InFocusRadius = previousDepthProps.InFocusRadius
	else
		TweenService:Create(effect, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { FarIntensity = 0, NearIntensity = 0 }):Play()
		task.delay(0.22, function()
			if effect and effect.Parent then
				effect:Destroy()
			end
		end)
	end
	careDepthOfField = nil
	previousDepthProps = nil
end

local function hideHudAndCharacter()
	disablePlayerControls()
	disconnectHudSuppression()
	table.clear(hiddenGuiStates)
	table.clear(characterTransparency)

	for _, child in ipairs(playerGui:GetChildren()) do
		watchScreenGui(child)
	end

	table.insert(hudSuppressConnections, playerGui.ChildAdded:Connect(function(child)
		watchScreenGui(child)
		task.defer(suppressHudNow)
		task.delay(0.05, suppressHudNow)
	end))

	suppressHudNow()
	applyBackgroundBlur()

	local character = player.Character
	if character then
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("BasePart") then
				-- Guardamos el valor original una sola vez.
				if characterTransparency[descendant] == nil then
					characterTransparency[descendant] = descendant.LocalTransparencyModifier
				end
				descendant.LocalTransparencyModifier = 1
			end
		end

		-- IMPORTANTE:
		-- Si ApplyDescription/AvatarEditor agrega piezas mientras el menú R está abierto,
		-- también las registramos para que al cerrar NO se queden en LTM = 1.
		table.insert(hudSuppressConnections, character.DescendantAdded:Connect(function(descendant)
			if open and descendant:IsA("BasePart") then
				task.defer(function()
					if open and descendant.Parent then
						if characterTransparency[descendant] == nil then
							characterTransparency[descendant] = descendant.LocalTransparencyModifier
						end
						descendant.LocalTransparencyModifier = 1
					end
				end)
			end
		end))
	end
end

local function clearCareVisuals()
	alertHolder.Visible = false
	cleanProgressBack.Visible = false
	dirtLayer.Visible = false
	soapLayer.Visible = false
	spongeCursor.Visible = false
	clickHandCursor.Visible = false
	pettingCursor.Visible = false
	message.Visible = false
	viewport.Visible = false
	for _, child in ipairs(gui:GetChildren()) do
		if child.Name == "CleanStar" or child.Name == "PetHeart" then
			child:Destroy()
		end
	end
end

local function restoreHudAndCharacter()
	disconnectHudSuppression()

	for screenGui, state in pairs(hiddenGuiStates) do
		if screenGui then
			screenGui.Parent = state.Parent or playerGui
			screenGui.Enabled = state.Enabled
		end
	end
	table.clear(hiddenGuiStates)

	for _, screenGui in ipairs(hiddenGuiFolder:GetChildren()) do
		if screenGui:IsA("ScreenGui") then
			screenGui.Parent = playerGui
			screenGui.Enabled = true
		end
	end

	-- Restauración inmediata de todas las piezas que ocultó ESTE menú.
	for instance, value in pairs(characterTransparency) do
		if instance and instance.Parent then
			instance.LocalTransparencyModifier = value
		end
	end
	table.clear(characterTransparency)

	-- V6:
	-- NO forzamos LocalTransparencyModifier = 0 después de cerrar.
	-- Roblox usa LTM internamente para ocultar geometría del cuerpo que debe
	-- quedar debajo de ropa 3D/layered clothing. Forzar 0 en todas las partes
	-- hacía reaparecer el cuerpo/accesorios como "siluetas" o fantasmas.
	--
	-- Ya restauramos arriba exactamente el valor que tenía cada parte antes de
	-- abrir el menú, así que CameraModule y layered clothing quedan libres de
	-- recalcular su estado normal sin que este script los vuelva a pisar.

	removeBackgroundBlur()
	enablePlayerControls()

	if coreHidden then
		pcall(function()
			for _, coreGuiType in ipairs(CORE_GUI_TYPES_TO_HIDE) do
				StarterGui:SetCoreGuiEnabled(coreGuiType, true)
			end
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
			StarterGui:SetCore("TopbarEnabled", true)
			StarterGui:SetCore("ResetButtonCallback", true)
		end)
		coreHidden = false
	end
end

closeView = function()
	if not open and not gui.Enabled then return end
	closingView = true
	menuScale.Scale = 1
	TweenService:Create(shade, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(closeButtonScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.9 }):Play()
	open = false
	player:SetAttribute("PetCareMenuOpen", false)
	mouseDown = false
	pettingActive = false
	didPetWhileHeld = false
	if celebrationTrack then
		celebrationTrack:Stop(0.05)
		celebrationTrack = nil
	end
	setCleaningMode(false)
	clearCareVisuals()
	setClickableCursor(false)
	setPettingCursor(false)
	UserInputService.MouseIconEnabled = true
	if not cleaningCompleted then
		clearSoapSpots()
	end
	removeCareBillboard()
	stopCareCameraFollow()
	restoreCamera()
	restoreHudAndCharacter()
	clearViewport()
	menuScale.Scale = 1
	shade.BackgroundTransparency = 0.9
	closeButtonScale.Scale = 1
	closeIcon.Rotation = 0
	closeHoldFill.Size = UDim2.fromScale(0, 1)
	player:SetAttribute(EXIT_HOLD_ATTRIBUTE, 0)
	gui.Enabled = false
	task.defer(function()
		if not open then
			clearCareVisuals()
			restoreCamera()
			restoreHudAndCharacter()
		end
	end)
	task.delay(0.15, function()
		if not open then
			clearCareVisuals()
			restoreCamera()
			restoreHudAndCharacter()
		end
	end)
	ensurePetMenuPrompt()
	closingView = false
end

openView = function()
	-- V5: el AvatarEditor también controla cámara/visibilidad.
	-- Nunca permitimos ambos menús abiertos a la vez.
	if player:GetAttribute("AvatarEditorOpen") == true then
		warn("[PetMenuHotkey] Apertura bloqueada: AvatarEditor está abierto.")
		return
	end

	if open or busy or not findOwnedEggModel() then return end
	ensurePetMenuPrompt()
	local camera = workspace.CurrentCamera
	if camera then
		oldCameraState = {
			cameraType = camera.CameraType,
			subject = camera.CameraSubject,
			cframe = camera.CFrame,
			fov = camera.FieldOfView,
		}
	end
	open = true
	player:SetAttribute("PetCareMenuOpen", true)
	closingView = false
	ensurePetMenuPrompt()
	disablePlayerControls()
	hideHudAndCharacter()
	task.delay(0.05, suppressHudNow)
	task.delay(0.2, suppressHudNow)
	task.delay(0.6, suppressHudNow)
	clearViewport()
	viewport.Visible = false
	menuScale.Scale = 1
	shade.BackgroundTransparency = 1
	closeButtonScale.Scale = 0.88
	closeIcon.Rotation = 0
	closeHoldFill.Size = UDim2.fromScale(0, 1)
	player:SetAttribute(EXIT_HOLD_ATTRIBUTE, 0)
	gui.Enabled = true
	TweenService:Create(shade, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.9 }):Play()
	TweenService:Create(closeButtonScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	message.Visible = false
	setCleaningMode(false)
	updateNeedAlerts()
	updateCleanButtonVisibility()
	applyCareCamera(true)
	startCareCameraFollow()
end

local function togglePetMenuFromPrompt()
	if UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end

	if player:GetAttribute("AvatarEditorOpen") == true then
		return Enum.ContextActionResult.Sink
	end

	if open then
		closeView()
		return Enum.ContextActionResult.Sink
	end
	if canUsePetMenuPrompt() then
		openView()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end



ContextActionService:BindActionAtPriority("PetMenuDeviceAction",function(_,s) if s~=Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end return togglePetMenuFromPrompt() end,true,5500,PET_MENU_PROMPT_KEY,Enum.KeyCode.ButtonY)
pcall(function() ContextActionService:SetTitle("PetMenuDeviceAction","Mascota") ContextActionService:SetPosition("PetMenuDeviceAction",UDim2.new(1,-86,1,-332)) end)

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name ~= PET_MENU_PROMPT_NAME then return end
	togglePetMenuFromPrompt()
end)

player:GetAttributeChangedSignal("PetMenuToggleRequest"):Connect(function()
	if open then
		closeView()
	elseif canUsePetMenuPrompt() then
		openView()
	end
end)

callCare = function(action)
	if busy then return nil end
	busy = true
	local ok, result = pcall(function()
		return CareEgg:InvokeServer(action)
	end)
	busy = false
	if ok and result then
		if action == "Clean" then
			if result.ok then
				markEggCleanLocally()
				fillEggWithSoap(true)
				spawnCleanStars()
				fadeSoapAfterClean()
				task.delay(0.55, function()
					clearSoapSpots()
					cleaningCompleted = false
					updateCleanButtonVisibility()
				end)
			else
				clearSoapSpots()
				cleaningCompleted = false
				updateCleanButtonVisibility()
			end
		elseif (action == "Feed" or action == "Eat") and result.ok then
			playEatingSound()
			playEatAnimation()
			showCareBillboard("+Food")
			showMessage(result.message or "Comio")
			updateNeedAlerts()
		elseif action == "Pet" and result.ok then
			showCareBillboard("♡")
			playCelebrationAnimation()
		end
	end
	return ok and result or nil
end

local function pulseCleanButton(strength)
	local scale = cleanButton:FindFirstChild("ButtonScale")
	if not scale then return end
	TweenService:Create(scale, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = strength or 0.9 }):Play()
	task.delay(0.08, function()
		if scale.Parent then
			TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end)
end

cleanButton.Activated:Connect(function()
	if not open then return end
	pulseCleanButton(cleaningActive and 0.88 or 0.92)
	if cleaningActive then
		setCleaningMode(false)
	else
		setCleaningMode(true)
	end
end)

petButton.Activated:Connect(function()
	showCareBillboard("♡")
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	-- =========================================================
	-- TECLA R: abrir/cerrar menú de mascota directamente
	-- Se procesa antes de gameProcessed para que otros sistemas
	-- de interfaz no se "coman" la R.
	-- =========================================================
	if input.UserInputType == Enum.UserInputType.Keyboard
		and input.KeyCode == PET_MENU_PROMPT_KEY
	then
		-- No abrir mientras el jugador está escribiendo.
		if UserInputService:GetFocusedTextBox() then
			return
		end

		-- V5: R no puede abrir cuidados mientras el armario controla la cámara.
		if player:GetAttribute("AvatarEditorOpen") == true then
			return
		end

		-- Evita dobles activaciones R + ProximityPrompt.
		if os.clock() - lastDirectRPressAt < R_DEBOUNCE_SECONDS then
			return
		end
		lastDirectRPressAt = os.clock()

		if open then
			closeView()
			return
		end

		if canUsePetMenuPrompt() then
			openView()
			return
		end
	end

	if open and cleaningActive and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
		if isMouseOverCleanButton() then
			mouseDown = false
			return
		end
		mouseDown = true
		cleanDirtAt(UserInputService:GetMouseLocation(), 0.08)
		return
	end
	local isPointerInput = input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	if not open and isPointerInput and isClickNearOwnedEgg(input.Position) then
		callCare("Feed")
		return
	end
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Escape and open then
		closeView()
		return
	end
	if not isPointerInput then return end
	if open then
		mouseDown = true
		if cleaningActive then
			if not isMouseOverCleanButton() then
				cleanDirtAt(UserInputService:GetMouseLocation(), 0.08)
			end
		elseif isClickNearOwnedEgg(input.Position) then
			pettingActive = true
			didPetWhileHeld = true
			lastHeartAt = 0
			spawnFloatingHeart()
		end
		return
	end
	-- La R directa se procesa arriba; el ProximityPrompt queda como respaldo.
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		mouseDown = false
		if pettingActive then
			pettingActive = false
			if didPetWhileHeld then
				didPetWhileHeld = false
				callCare("Pet")
			end
		end
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local mousePosition = UserInputService:GetMouseLocation()
	if not open or not gui.Enabled then
		if os.clock() >= nextPetPromptRefreshAt then
			nextPetPromptRefreshAt = os.clock() + 0.45
			ensurePetMenuPrompt()
		end
		setClickableCursor(isHoveringOwnedEgg(mousePosition))
		return
	end
	setClickableCursor(false)
	updateBackgroundFocus(false)
	updateNeedAlerts()
	updateNeedAlertPosition()
	suppressHudNow()
	task.defer(suppressHudNow)
	local nearEgg = isClickNearOwnedEgg(mousePosition)
	setPettingCursor(not cleaningActive and nearEgg)
	if cleaningActive then
		local overCleanButton = isMouseOverCleanButton()
		if overCleanButton then
			spongeCursor.Visible = false
			UserInputService.MouseIconEnabled = true
		else
			spongeCursor.Visible = true
			UserInputService.MouseIconEnabled = false
			updateSpongeCursor()
		end
		updateDirtSpotPositions()
		updateSoapSpotPositions()
		if mouseDown and nearEgg then
			local mousePosition = UserInputService:GetMouseLocation()
			spawnSoapBubble(mousePosition)
			cleanDirtAt(mousePosition, dt)
		end
	elseif pettingActive and mouseDown and nearEgg then
		if os.clock() - lastHeartAt > 0.18 then
			lastHeartAt = os.clock()
			spawnFloatingHeart()
		end
	end
end)

player.CharacterAdded:Connect(function()
	if open then closeView() end
end)

script.Destroying:Connect(function()
	pcall(function()
		RunService:UnbindFromRenderStep(
			PET_CARE_CAMERA_STEP
		)
	end)
end)

-- V5: respaldo de seguridad. Si el armario se abre por otra ruta
-- mientras cuidados está abierto, cerramos cuidados inmediatamente.
player:GetAttributeChangedSignal("AvatarEditorOpen"):Connect(function()
	if open and player:GetAttribute("AvatarEditorOpen") == true then
		warn("[PetMenuHotkey] AvatarEditor abrió; cerrando cuidados para evitar choque de cámara/LTM.")
		closeView()
	end
end)

print(
	"[PetMenuHotkey] V6 SIN FORZAR LTM | compatible con AvatarEditor + ropa 3D."
)
