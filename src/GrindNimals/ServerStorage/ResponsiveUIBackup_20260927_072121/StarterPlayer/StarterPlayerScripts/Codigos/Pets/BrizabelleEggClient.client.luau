local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("BrizabelleEggSystem")
local BuyEgg = remotes:WaitForChild("BuyEgg")
local HatchEgg = remotes:WaitForChild("HatchEgg")
local GetState = remotes:WaitForChild("GetState")
local CareEgg = remotes:WaitForChild("CareEgg")
local RequestInstantHatch = remotes:WaitForChild("RequestInstantHatch")
local ConfirmInstantHatch = remotes:WaitForChild("ConfirmInstantHatch")
local EggNotify = remotes:WaitForChild("EggNotify")
local equipPetEvent = ReplicatedStorage:WaitForChild("EquipPet")
local petViews = ReplicatedStorage:WaitForChild("MascotasView")

local EGG_NAME = "Huevo Mascota"
local EGG_DISPLAY = "Huevo mascota"
local FONT = Enum.Font.FredokaOne
local COLORS = {
	panel = Color3.fromRGB(180, 126, 76),
	dark = Color3.fromRGB(75, 45, 28),
	cream = Color3.fromRGB(255, 232, 190),
	button = Color3.fromRGB(77, 165, 79),
	buttonDark = Color3.fromRGB(108, 93, 74),
	white = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(43, 25, 15),
}
local RARITY_TEXT_COLORS = {
	["Comun"] = Color3.fromRGB(185, 185, 185),
	["Poco comun"] = Color3.fromRGB(91, 213, 88),
	["Raro"] = Color3.fromRGB(82, 160, 255),
	["Epico"] = Color3.fromRGB(179, 92, 255),
	["Legendario"] = Color3.fromRGB(255, 203, 65),
}

local function create(className, props, parent)
	local obj = Instance.new(className)
	for key, value in pairs(props or {}) do obj[key] = value end
	obj.Parent = parent
	return obj
end

local function corner(obj, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = obj
end

local function stroke(obj, thickness, color)
	local s = Instance.new("UIStroke")
	s.Color = color or COLORS.dark
	s.Thickness = thickness or 2
	s.Parent = obj
	return s
end

local gui = create("ScreenGui", {
	Name = "BrizabelleEggGui",
	ResetOnSpawn = false,
	Enabled = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 85,
}, playerGui)

local panel = create("Frame", {
	Name = "ShopPanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(600, 285),
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	ZIndex = 20,
}, gui)
corner(panel, 10)
stroke(panel, 3)

local title = create("TextLabel", {
	BackgroundColor3 = COLORS.cream,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(16, 14),
	Size = UDim2.new(1, -70, 0, 48),
	Text = "Tienda de huevos",
	Font = FONT,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(0, 0, 0),
	ZIndex = 21,
}, panel)
corner(title, 6)

local close = create("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -18, 0, 18),
	Size = UDim2.fromOffset(38, 38),
	BackgroundTransparency = 1,
	Text = "X",
	Font = FONT,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(0, 0, 0),
	ZIndex = 22,
}, panel)

local oddsHolder = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(24, 78),
	Size = UDim2.fromOffset(350, 154),
	ZIndex = 21,
}, panel)
local oddsLayout = Instance.new("UIListLayout")
oddsLayout.SortOrder = Enum.SortOrder.LayoutOrder
oddsLayout.Padding = UDim.new(0, 4)
oddsLayout.Parent = oddsHolder

local oddsLines = {
	{ rarity = "Comun", text = "Comun: Perro, Gato: 35%" },
	{ rarity = "Poco comun", text = "Poco comun: Conejo, Perico: 25%" },
	{ rarity = "Raro", text = "Raro: Tortuga, Hamster: 20%" },
	{ rarity = "Epico", text = "Epico: Huron, Pez dorado: 15%" },
	{ rarity = "Legendario", text = "Legendario: Oveja de rosario: 5%" },
}
local rarityEffects = {}
for index, line in ipairs(oddsLines) do
	local rarityLabel = create("TextLabel", {
		Name = line.rarity,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 25),
		Text = line.text,
		Font = FONT,
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = RARITY_TEXT_COLORS[line.rarity] or COLORS.white,
		TextStrokeColor3 = Color3.fromRGB(72, 43, 24),
		TextStrokeTransparency = 0.08,
		LayoutOrder = index,
		ZIndex = 22,
	}, oddsHolder)
	local rarityStroke = Instance.new("UIStroke")
	rarityStroke.Color = Color3.fromRGB(72, 43, 24)
	rarityStroke.Thickness = 1.8
	rarityStroke.Transparency = 0.05
	rarityStroke.Parent = rarityLabel
	local rarityGradient = Instance.new("UIGradient")
	rarityGradient.Rotation = 0
	rarityGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLORS.white),
		ColorSequenceKeypoint.new(0.48, RARITY_TEXT_COLORS[line.rarity] or COLORS.white),
		ColorSequenceKeypoint.new(1, COLORS.white),
	})
	rarityGradient.Parent = rarityLabel
	table.insert(rarityEffects, { gradient = rarityGradient, stroke = rarityStroke, index = index })
end

local viewport = create("ViewportFrame", {
	BackgroundColor3 = Color3.fromRGB(135, 91, 55),
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(405, 78),
	Size = UDim2.fromOffset(158, 142),
	Ambient = Color3.fromRGB(255, 255, 255),
	LightColor = Color3.fromRGB(255, 255, 255),
	ZIndex = 21,
}, panel)
corner(viewport, 8)
stroke(viewport, 2)
local viewportCamera = Instance.new("Camera")
viewportCamera.Parent = viewport
viewport.CurrentCamera = viewportCamera
local viewportModel = nil

local buyButton = create("TextButton", {
	Name = "BuyHoldButton",
	Position = UDim2.fromOffset(24, 238),
	Size = UDim2.fromOffset(250, 42),
	BackgroundColor3 = COLORS.button,
	BorderSizePixel = 0,
	Text = "",
	AutoButtonColor = false,
	ZIndex = 21,
}, panel)
corner(buyButton, 8)
stroke(buyButton, 2)
local buyFill = create("Frame", {
	Name = "HoldFill",
	BackgroundColor3 = Color3.fromRGB(93, 205, 96),
	BorderSizePixel = 0,
	Size = UDim2.fromScale(0, 1),
	ZIndex = 22,
}, buyButton)
corner(buyFill, 8)
local buyLabel = create("TextLabel", {
	Name = "Label",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	Text = "750$",
	Font = FONT,
	TextScaled = true,
	TextColor3 = COLORS.white,
	TextStrokeTransparency = 0.35,
	ZIndex = 23,
}, buyButton)

local hatchButton = create("TextButton", {
	Name = "OpenHatchButton",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -24, 0, 238),
	Size = UDim2.fromOffset(250, 42),
	BackgroundColor3 = COLORS.buttonDark,
	BorderSizePixel = 0,
	Text = "Abrir huevo",
	Font = FONT,
	TextScaled = true,
	TextColor3 = COLORS.white,
	AutoButtonColor = false,
	ZIndex = 21,
}, panel)
corner(hatchButton, 8)
stroke(hatchButton, 2)

local hatchMenu = create("Frame", {
	Name = "HatchPanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(520, 330),
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 40,
}, gui)
corner(hatchMenu, 10)
stroke(hatchMenu, 3)
local hatchTitle = create("TextLabel", {
	BackgroundColor3 = COLORS.cream,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(14, 14),
	Size = UDim2.new(1, -64, 0, 46),
	Text = "Abrir huevo",
	Font = FONT,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(0, 0, 0),
	ZIndex = 41,
}, hatchMenu)
corner(hatchTitle, 6)
local hatchClose = create("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 18),
	Size = UDim2.fromOffset(34, 34),
	BackgroundTransparency = 1,
	Text = "X",
	Font = FONT,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(0, 0, 0),
	ZIndex = 42,
}, hatchMenu)
local eggList = create("ScrollingFrame", {
	Name = "EggList",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(18, 74),
	Size = UDim2.new(1, -36, 0, 210),
	CanvasSize = UDim2.fromOffset(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
	ZIndex = 41,
}, hatchMenu)
local eggGrid = Instance.new("UIGridLayout")
eggGrid.CellSize = UDim2.fromOffset(150, 204)
eggGrid.CellPadding = UDim2.fromOffset(6, 8)
eggGrid.SortOrder = Enum.SortOrder.LayoutOrder
eggGrid.FillDirectionMaxCells = 3
eggGrid.Parent = eggList
local robuxButton = create("TextButton", {
	Name = "RobuxOpenButton",
	Position = UDim2.fromOffset(42, 276),
	Size = UDim2.new(1, -84, 0, 40),
	BackgroundColor3 = COLORS.button,
	BorderSizePixel = 0,
	Text = "",
	Font = FONT,
	TextScaled = true,
	TextColor3 = COLORS.white,
	AutoButtonColor = false,
	ZIndex = 41,
}, hatchMenu)
corner(robuxButton, 8)
stroke(robuxButton, 2)
robuxButton.Visible = false
robuxButton.Active = false

local toastGui = create("ScreenGui", {
	Name = "BrizabelleEggToastGui",
	ResetOnSpawn = false,
	DisplayOrder = 120,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)
local toast = create("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.12),
	Size = UDim2.fromOffset(540, 64),
	BackgroundColor3 = Color3.fromRGB(255, 220, 116),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Text = "",
	Font = FONT,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(72, 43, 15),
	TextStrokeTransparency = 1,
	Visible = false,
	ZIndex = 100,
}, toastGui)
corner(toast, 10)
stroke(toast, 3, Color3.fromRGB(130, 73, 31))
local toastScale = Instance.new("UIScale")
toastScale.Parent = toast

local latestState = nil -- TUTORIAL_LATEST_STATE_DECLARED_BEFORE_HELPER

local function tutorialFreeEggActive()
	local step = tostring(player:GetAttribute("TutorialStep") or "")
	return player:GetAttribute("TutorialLocked") == true
		and player:GetAttribute("FreeStarterEggClaimed") ~= true
		and (step == "BUY_FREE_EGG")
end

local function setTutorialAwareBuyLabel(state)
	-- TUTORIAL_FREE_EGG_LABEL: solo cambia UI; BuyEgg valida gratis en servidor.
	if tutorialFreeEggActive() then
		buyLabel.Text = "OBTENER GRATIS"
	else
		buyLabel.Text = tostring(tonumber(state and state.price) or 750) .. "$"
	end
end

player:GetAttributeChangedSignal("TutorialStep"):Connect(function()
	setTutorialAwareBuyLabel(latestState)
end)
player:GetAttributeChangedSignal("FreeStarterEggClaimed"):Connect(function()
	setTutorialAwareBuyLabel(latestState)
end)

local latestState = nil
local busy = false
local studioInstantConfirmToken = 0
local confirmStudioInstantHatch
local selectedEggId = nil
local selectedEggStroke = nil
local menuAnimating = false
local eggEquipRequested = false
local lastMenuOpenAt = 0

local panelScale = Instance.new("UIScale")
panelScale.Name = "PanelScale"
panelScale.Scale = 1
panelScale.Parent = panel

local hatchScale = Instance.new("UIScale")
hatchScale.Name = "HatchScale"
hatchScale.Scale = 1
hatchScale.Parent = hatchMenu

local buttonBaseColors = {}
local buttonScales = {}

local function addButtonMotion(button, hoverColor, pressColor)
	if not button or not button:IsA("GuiButton") then return end
	buttonBaseColors[button] = button.BackgroundColor3
	local scale = button:FindFirstChild("MotionScale") or Instance.new("UIScale")
	scale.Name = "MotionScale"
	scale.Scale = 1
	scale.Parent = button
	buttonScales[button] = scale

	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.045 }):Play()
		TweenService:Create(button, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = hoverColor or button.BackgroundColor3 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		TweenService:Create(button, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = buttonBaseColors[button] or button.BackgroundColor3 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 0.965 }):Play()
		TweenService:Create(button, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = pressColor or button.BackgroundColor3 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.035 }):Play()
	end)
end

local function playPanelIn(targetPanel, targetScale)
	targetPanel.Visible = true
	targetScale.Scale = 0.72
	targetPanel.Position = UDim2.fromScale(0.5, 0.515)
	TweenService:Create(targetScale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(targetPanel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.5) }):Play()
end

addButtonMotion(buyButton, Color3.fromRGB(91, 190, 91), Color3.fromRGB(64, 138, 66))
addButtonMotion(hatchButton, Color3.fromRGB(130, 113, 91), Color3.fromRGB(86, 74, 59))
addButtonMotion(robuxButton, Color3.fromRGB(91, 190, 91), Color3.fromRGB(64, 138, 66))

local function setViewportModel(targetViewport, modelName)
	for _, child in ipairs(targetViewport:GetChildren()) do
		if child:IsA("Model") or child:IsA("Camera") then child:Destroy() end
	end
	local template = petViews:FindFirstChild(modelName or EGG_NAME)
	if not template then return end
	local sourceViewport = template:FindFirstChildWhichIsA("ViewportFrame")
	local sourceModel = sourceViewport and sourceViewport:FindFirstChildWhichIsA("Model") or nil
	local model = (sourceModel and sourceModel:Clone()) or template:Clone()
	model.Parent = targetViewport
	local camera = Instance.new("Camera")
	camera.Parent = targetViewport
	targetViewport.CurrentCamera = camera
	local cf, size = model:GetBoundingBox()
	local maxSize = math.max(size.X, size.Y, size.Z, 1)
	local center = cf.Position
	camera.CFrame = CFrame.new(center + Vector3.new(maxSize * 1.45, maxSize * 0.75, maxSize * 2.05), center)
	camera.FieldOfView = 32
	return model
end

viewportModel = setViewportModel(viewport, EGG_NAME)

RunService.RenderStepped:Connect(function(dt)
	if viewportModel and viewportModel.Parent and gui.Enabled and panel.Visible then
		viewportModel:PivotTo(viewportModel:GetPivot() * CFrame.Angles(0, dt * 1.4, 0))
	end
	if gui.Enabled then
		local t = os.clock()
		for _, effect in ipairs(rarityEffects) do
			effect.gradient.Offset = Vector2.new(math.sin(t * 1.2 + effect.index) * 0.18, 0)
			effect.stroke.Transparency = 0.05
		end
	end
end)

local toastTweens = {}
local toastToken = 0
local function showToast(text)
	toastToken += 1
	local myToken = toastToken
	for _, tween in ipairs(toastTweens) do tween:Cancel() end
	table.clear(toastTweens)

	toast.Text = tostring(text or "")
	toast.Visible = true
	toast.AnchorPoint = Vector2.new(0.5, 0.5)
	toast.Position = UDim2.fromScale(0.5, 0.42)
	toast.Size = UDim2.fromOffset(560, 86)
	toast.BackgroundTransparency = 1
	toast.TextColor3 = Color3.fromRGB(255, 248, 205)
	toast.TextStrokeColor3 = Color3.fromRGB(78, 42, 10)
	toast.TextStrokeTransparency = 0
	toast.TextTransparency = 0
	toast.Font = FONT
	toast.TextScaled = true
	toast.ZIndex = 260
	toast.Rotation = -10

	local scale = toast:FindFirstChild("AnimatedNoticeScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "AnimatedNoticeScale"
		scale.Parent = toast
	end
	scale.Scale = 0.18

	local function play(instance, info, goal)
		local tween = TweenService:Create(instance, info, goal)
		table.insert(toastTweens, tween)
		tween:Play()
		return tween
	end

	play(scale, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.05 })
	play(toast, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0, Position = UDim2.fromScale(0.5, 0.36) })
	task.delay(0.42, function()
		if myToken ~= toastToken or not toast.Visible then return end
		play(scale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 0.96 })
		task.wait(0.16)
		if myToken == toastToken and toast.Visible then
			play(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		end
	end)
	task.delay(2.6, function()
		if myToken ~= toastToken or not toast.Visible then return end
		play(toast, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(0.5, 0.28), Rotation = 5, TextTransparency = 1, TextStrokeTransparency = 1 })
		play(scale, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.76 })
		task.wait(0.38)
		if myToken == toastToken then toast.Visible = false end
	end)
end
-- Forward declaration:
-- selectEggOnServer usa updateVisual antes de que su implementación
-- aparezca más abajo en el archivo.
local updateVisual

local function clearEggCards()
	for _, child in ipairs(eggList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	-- NO borrar selectedEggId aquí.
	-- Se conserva entre refresh para que cada tarjeta represente
	-- siempre el mismo huevo individual.
	selectedEggStroke = nil
end

local function selectEggOnServer(eggId, silent)
	eggId = tostring(eggId or "")

	if eggId == "" then
		return false
	end

	local ok, result = pcall(function()
		return CareEgg:InvokeServer(
			"SelectEgg",
			eggId
		)
	end)

	if ok and result then
		if result.state then
			updateVisual(result.state)
		end

		if not result.ok and not silent then
			showToast(
				result.message
					or "No se pudo seleccionar el huevo"
			)
		end

		return result.ok == true
	end

	if not silent then
		showToast("No se pudo seleccionar el huevo")
	end

	return false
end

local function openSelectedEgg()
	if busy then return end
	busy = true
	local ok, result = pcall(function()
		return HatchEgg:InvokeServer(selectedEggId)
	end)
	busy = false
	if not ok or not result then
		showToast("No se pudo abrir el huevo")
		return
	end
	if not result.ok then
		showToast(result.message or "No se pudo abrir")
		return
	end
	gui.Enabled = false
	panel.Visible = false
	hatchMenu.Visible = false
end

local function scheduleStudioInstantConfirm()
	if not RunService:IsStudio() then return end
	studioInstantConfirmToken += 1
	local token = studioInstantConfirmToken
	task.delay(4.0, function()
		if token ~= studioInstantConfirmToken then return end
		confirmStudioInstantHatch()
	end)
	task.delay(7.0, function()
		if token ~= studioInstantConfirmToken then return end
		confirmStudioInstantHatch()
	end)
end

local function promptSelectedEggRobux()
	if busy then return end
	if not selectedEggId then
		showToast("Selecciona un huevo")
		return
	end
	busy = true
	local ok, result = pcall(function() return RequestInstantHatch:InvokeServer(selectedEggId) end)
	busy = false
	if not ok or not result then
		showToast("No se pudo iniciar la compra")
		return
	end
	if not result.ok then
		showToast(result.message or "No se pudo abrir")
		return
	end
	panel.Visible = false
	hatchMenu.Visible = true
	MarketplaceService:PromptProductPurchase(player, result.productId)
	scheduleStudioInstantConfirm()
end

local function makeEggCard(egg, order)
	local card = create("TextButton", {
		Name = "EggCard" .. tostring(order),
		BackgroundColor3 = Color3.fromRGB(151, 98, 60),
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = order,
		ZIndex = 42,
	}, eggList)
	corner(card, 8)
	local cardStroke = stroke(card, 2, COLORS.dark)
	local eggViewport = create("ViewportFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -32, 0, 78),
		Ambient = Color3.fromRGB(255, 255, 255),
		LightColor = Color3.fromRGB(255, 255, 255),
		ZIndex = 43,
	}, card)
	setViewportModel(eggViewport, EGG_NAME)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 86),
		Size = UDim2.new(1, -16, 0, 24),
		Text = EGG_DISPLAY,
		Font = FONT,
		TextScaled = true,
		TextColor3 = COLORS.white,
		TextStrokeTransparency = 0.35,
		ZIndex = 43,
	}, card)
	local openButton = create("TextButton", {
		Name = "OpenEggButton",
		BackgroundColor3 = COLORS.button,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 111),
		Size = UDim2.new(1, -16, 0, 25),
		Text = "Abrir huevo",
		Font = FONT,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 245, 210),
		TextStrokeTransparency = 0.3,
		AutoButtonColor = false,
		ZIndex = 46,
	}, card)
	corner(openButton, 6)
	stroke(openButton, 1.5, COLORS.dark)
	addButtonMotion(openButton, Color3.fromRGB(91, 190, 91), Color3.fromRGB(64, 138, 66))
	openButton.Activated:Connect(function()
		if busy then
			return
		end

		selectedEggId =
			tostring(
				egg.id
				or order
			)

		if selectedEggStroke then
			selectedEggStroke.Color =
				COLORS.dark
		end

		selectedEggStroke = cardStroke
		cardStroke.Color =
			Color3.fromRGB(
				255,
				220,
				96
			)

		-- Seleccionar este huevo también en servidor.
		selectEggOnServer(
			selectedEggId,
			true
		)

		if tonumber(egg.progress)
			and tonumber(egg.progress) >= 100 then

			openSelectedEgg()
		else
			promptSelectedEggRobux()
		end
	end)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 135),
		Size = UDim2.new(1, -16, 0, 24),
		Text = "750 Robux",
		Font = FONT,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(145, 255, 130),
		TextStrokeTransparency = 0.3,
		ZIndex = 43,
	}, card)
	local progress = math.clamp(tonumber(egg.progress) or 0, 0, 100)
	local bar = create("Frame", {
		Position = UDim2.fromOffset(12, 166),
		Size = UDim2.new(1, -24, 0, 18),
		BackgroundColor3 = Color3.fromRGB(65, 45, 34),
		BorderSizePixel = 0,
		ZIndex = 43,
	}, card)
	corner(bar, 8)
	local fill = create("Frame", {
		Size = UDim2.fromScale(progress / 100, 1),
		BackgroundColor3 = Color3.fromRGB(255, 205, 76),
		BorderSizePixel = 0,
		ZIndex = 44,
	}, bar)
	corner(fill, 8)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = tostring(progress) .. "%",
		Font = FONT,
		TextScaled = true,
		TextColor3 = COLORS.white,
		TextStrokeTransparency = 0.35,
		ZIndex = 45,
	}, bar)
	card.Activated:Connect(function()
		selectedEggId =
			tostring(
				egg.id
				or order
			)

		if selectedEggStroke then
			selectedEggStroke.Color =
				COLORS.dark
		end

		selectedEggStroke = cardStroke
		cardStroke.Color =
			Color3.fromRGB(
				255,
				220,
				96
			)

		selectEggOnServer(
			selectedEggId,
			true
		)
	end)

	if tostring(egg.id or order)
		== tostring(selectedEggId or "") then

		selectedEggStroke = cardStroke
		cardStroke.Color =
			Color3.fromRGB(
				255,
				220,
				96
			)
	end
end

local function renderEggCards(state)
	local preferredEggId =
		tostring(
			state
			and state.selectedEggId
			or selectedEggId
			or ""
		)

	clearEggCards()

	local eggs =
		state
		and state.eggs
		or {}

	if #eggs == 0 then
		selectedEggId = nil

		create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(450, 80),
			Text = "No tienes huevos",
			Font = FONT,
			TextScaled = true,
			TextColor3 = COLORS.white,
			TextStrokeTransparency = 0.35,
			ZIndex = 42,
		}, eggList)

		return
	end

	local preferredExists = false

	for _, egg in ipairs(eggs) do
		if tostring(egg.id or "")
			== preferredEggId then

			preferredExists = true
			break
		end
	end

	if preferredExists then
		selectedEggId = preferredEggId
	else
		selectedEggId =
			tostring(
				eggs[1].id
				or "1"
			)
	end

	for index, egg in ipairs(eggs) do
		makeEggCard(
			egg,
			index
		)
	end
end

local function getPetInventoryValue(petName)
	local inventory = player:FindFirstChild("TradePetsInventory")
	if not inventory then return nil end
	for _, child in ipairs(inventory:GetChildren()) do
		if (child:IsA("IntValue") or child:IsA("NumberValue")) and (child.Name == petName or child:GetAttribute("ItemName") == petName) then
			return child
		end
	end
	return nil
end

local function isSleepingNow()
	return workspace:FindFirstChild("BrizabelleSleepingEgg_" .. player.UserId) ~= nil
		or workspace:FindFirstChild("BrizabelleSleepingPet_" .. player.UserId) ~= nil
end

local function selectedNeedsSleep()
	if isSleepingNow() then
		return false
	end
	local selectedPet = tostring(player:GetAttribute("SelectedBackpackPet") or "")
	if selectedPet == "" or selectedPet == EGG_NAME or selectedPet == "HuevoBrizabelle" then
		return latestState and latestState.tired == true and latestState.resting ~= true
	end
	local value = getPetInventoryValue(selectedPet)
	return value and value:GetAttribute("Tired") == true and value:GetAttribute("Resting") ~= true
end

local function updateBedPromptVisibility()
	local enabled = selectedNeedsSleep() == true
	for _, object in ipairs(workspace:GetDescendants()) do
		if object:IsA("ProximityPrompt") and object.Name == "BrizabelleEggBedPrompt" then
			object.Enabled = enabled
		end
	end
end

updateVisual = function(state)
	latestState = state
	updateBedPromptVisibility()
	if not state then return end
	setTutorialAwareBuyLabel(state)
	local eggCount = tonumber(state.eggCount) or 0
	local selectedPet = tostring(player:GetAttribute("SelectedBackpackPet") or "")
	local restorePet = tostring(player:GetAttribute("BrizabelleRestorePetAfterSleep") or "")
	local shouldKeepPet = restorePet ~= "" and getPetInventoryValue(restorePet) ~= nil
		or (selectedPet ~= "" and selectedPet ~= EGG_NAME and selectedPet ~= "HuevoBrizabelle" and getPetInventoryValue(selectedPet) ~= nil)
	if eggCount > 0 and not eggEquipRequested and not shouldKeepPet then
		eggEquipRequested = true
		player:SetAttribute("SelectedBackpackPet", EGG_NAME)
		equipPetEvent:FireServer(EGG_NAME)
	elseif eggCount <= 0 or shouldKeepPet then
		eggEquipRequested = false
	end
	hatchButton.BackgroundColor3 = eggCount > 0 and COLORS.button or COLORS.buttonDark
	if hatchMenu.Visible then renderEggCards(state) end
end

local function refresh()
	local ok, state = pcall(function() return GetState:InvokeServer() end)
	if ok then updateVisual(state) else updateBedPromptVisibility() end
end

local function showShop()
	panel.Visible = true
	hatchMenu.Visible = false
	refresh()
end

local function showHatchMenu()
	refresh()
	local eggCount = latestState and tonumber(latestState.eggCount) or 0
	if eggCount <= 0 then
		showToast("No tienes huevos para abrir")
		return
	end
	panel.Visible = false
	playPanelIn(hatchMenu, hatchScale)
	renderEggCards(latestState)
end
local function openMenu()
	if menuAnimating or gui.Enabled or os.clock() - lastMenuOpenAt < 0.45 then
		return
	end
	menuAnimating = true
	lastMenuOpenAt = os.clock()
	gui.Enabled = true
	showShop()
	playPanelIn(panel, panelScale)
	task.delay(0.35, function()
		menuAnimating = false
	end)
end
close.Activated:Connect(function()
	gui.Enabled = false
	hatchMenu.Visible = false
	panel.Visible = true
end)

hatchClose.Activated:Connect(showShop)

local HOLD_SECONDS = 1.1
local holdingBuy = false
local holdStartedAt = 0
local holdCompleted = false

local function setHoldProgress(alpha)
	buyFill.Size = UDim2.fromScale(math.clamp(alpha or 0, 0, 1), 1)
end

local function flashInsufficient()
	buyButton.BackgroundColor3 = Color3.fromRGB(215, 67, 67)
	buyFill.BackgroundColor3 = Color3.fromRGB(235, 82, 82)
	buyLabel.Text = "Dinero insuficiente"
	task.delay(1.25, function()
		buyButton.BackgroundColor3 = COLORS.button
		buyFill.BackgroundColor3 = Color3.fromRGB(93, 205, 96)
		if latestState then
			setTutorialAwareBuyLabel(latestState)
		else
			setTutorialAwareBuyLabel(latestState)
		end
	end)
end

local function performBuy()
	if busy then return end
	busy = true
	local ok, result = pcall(function() return BuyEgg:InvokeServer() end)
	if ok and result then
		updateVisual(result.state)
		if result.ok then
			player:SetAttribute("SelectedBackpackPet", EGG_NAME)
			equipPetEvent:FireServer(EGG_NAME)
			gui.Enabled = false
			panel.Visible = false
			hatchMenu.Visible = false
		else
			if tostring(result.message or ""):lower():find("insuficiente") then flashInsufficient() else showToast(result.message or "No se pudo comprar.") end
		end
	else
		showToast("No se pudo comprar el huevo.")
	end
	busy = false
end

buyButton.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
	if busy then return end
	holdingBuy = true
	holdCompleted = false
	holdStartedAt = os.clock()
	buyLabel.Text = "Mantener"
	buyButton.BackgroundColor3 = COLORS.button
	buyFill.BackgroundColor3 = Color3.fromRGB(93, 205, 96)
	setHoldProgress(0)
end)

buyButton.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
	holdingBuy = false
	if not holdCompleted then
		TweenService:Create(buyFill, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(0, 1) }):Play()
		setTutorialAwareBuyLabel(latestState)
	end
end)

RunService.RenderStepped:Connect(function()
	if not holdingBuy or holdCompleted then return end
	local alpha = (os.clock() - holdStartedAt) / HOLD_SECONDS
	setHoldProgress(alpha)
	if alpha >= 1 then
		holdCompleted = true
		holdingBuy = false
		performBuy()
		task.delay(0.2, function() setHoldProgress(0) end)
	end
end)

hatchButton.Activated:Connect(showHatchMenu)

robuxButton.Activated:Connect(function()
	if busy then return end
	if not selectedEggId then
		showToast("Selecciona un huevo")
		return
	end
	busy = true
	local ok, result = pcall(function() return RequestInstantHatch:InvokeServer(selectedEggId) end)
	busy = false
	if not ok or not result then
		showToast("No se pudo iniciar la compra")
		return
	end
	if not result.ok then
		showToast(result.message or "No se pudo abrir")
		return
	end
	panel.Visible = false
	hatchMenu.Visible = true
	MarketplaceService:PromptProductPurchase(player, result.productId)
	scheduleStudioInstantConfirm()
end)

local function callCare(action)
	local ok, result = pcall(function() return CareEgg:InvokeServer(action) end)
	if ok and result then
		updateVisual(result.state)
		if not result.ok and result.message and action ~= "Walk" then
			showToast(result.message)
		elseif result.ok and result.message and action ~= "Walk" and action ~= "Sleep" and action ~= "Clean" then
			showToast(result.message)
		end
	end
end

EggNotify.OnClientEvent:Connect(function(kind, data)
	if kind == "Purchased" then
		player:SetAttribute("SelectedBackpackPet", EGG_NAME)
		equipPetEvent:FireServer(EGG_NAME)
		if typeof(data) == "table" then updateVisual(data) end
	elseif kind == "Dirty" then
		if typeof(data) == "table" then updateVisual(data) end
	elseif kind == "Tired" then
		if typeof(data) == "table" then updateVisual(data.state or data) end
	elseif kind == "Hungry" then
		if typeof(data) == "table" then updateVisual(data.state or data) end
	elseif kind == "SleepStarted" then
		if typeof(data) == "table" then updateVisual(data.state or data) end
	elseif kind == "Rested" then
		if typeof(data) == "table" and data.state then updateVisual(data.state) end
	elseif kind == "Ready" then
		if typeof(data) == "table" then updateVisual(data) end
	elseif kind == "Hatched" and typeof(data) == "table" then
		gui.Enabled = false
		hatchMenu.Visible = false
		panel.Visible = false
		if data.petName then
			player:SetAttribute("SelectedBackpackPet", data.petName)
			equipPetEvent:FireServer(data.petName)
		end
		refresh()
	elseif kind == "Care" and typeof(data) == "table" then
		if data.state then updateVisual(data.state) end
	elseif typeof(data) == "table" then
		updateVisual(data)
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer ~= player then return end
	if prompt.Name == "BrizabelleEggPrompt" then
		openMenu()
	elseif prompt.Name == "BrizabelleEggCleanPrompt" then
		callCare("Clean")
	elseif prompt.Name == "BrizabelleEggBedPrompt" then
		updateBedPromptVisibility()
		if selectedNeedsSleep() then
			callCare("Sleep")
		end
	end
end)

task.spawn(function()
	task.wait(1)
	refresh()
	while true do
		task.wait(1)
		callCare("Walk")
		updateBedPromptVisibility()
		if gui.Enabled then refresh() end
	end
end)

task.spawn(function()
	while true do
		task.wait(0.2)
		updateBedPromptVisibility()
	end
end)

player:GetAttributeChangedSignal("SelectedBackpackPet"):Connect(updateBedPromptVisibility)
workspace.ChildAdded:Connect(function(object)
	if object.Name == "BrizabelleSleepingEgg_" .. player.UserId or object.Name == "BrizabelleSleepingPet_" .. player.UserId then
		updateBedPromptVisibility()
	end
end)
workspace.ChildRemoved:Connect(function(object)
	if object.Name == "BrizabelleSleepingEgg_" .. player.UserId or object.Name == "BrizabelleSleepingPet_" .. player.UserId then
		updateBedPromptVisibility()
	end
end)

confirmStudioInstantHatch = function()
	local ok, result = pcall(function()
		return ConfirmInstantHatch:InvokeServer()
	end)
	if ok and result and result.ok then
		gui.Enabled = false
		hatchMenu.Visible = false
		panel.Visible = false
		return true
	end
	if ok and result and result.message and not tostring(result.message):lower():find("pendiente", 1, true) then
		showToast(result.message)
	end
	return false
end

MarketplaceService.PromptProductPurchaseFinished:Connect(function(finishedPlayer, productId, wasPurchased)
	if finishedPlayer ~= player then return end
	if wasPurchased then
		studioInstantConfirmToken += 1
		if not confirmStudioInstantHatch() then
			gui.Enabled = false
			hatchMenu.Visible = false
			panel.Visible = false
		end
	else
		studioInstantConfirmToken += 1
		panel.Visible = false
		hatchMenu.Visible = true
	end
end)