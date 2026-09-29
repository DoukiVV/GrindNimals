--============================================================
-- WILLIAM BANK CLIENT V2
-- Ubicacion: StarterPlayer > StarterPlayerScripts > WilliamBankClient
-- Tipo: LocalScript
--
-- CAMBIO CORRECTO:
--      1 Diamante = 100 Dolares
--      5 Diamantes = 500 Dolares
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local folder = ReplicatedStorage:WaitForChild("WilliamBankSystem")
local GetBankState = folder:WaitForChild("GetBankState")
local ExchangeDiamondsForDollars = folder:WaitForChild("ExchangeDiamondsForDollars")

local FONT = Enum.Font.FredokaOne

local MONEY_ICON = "rbxassetid://117128537983961"
local DIAMOND_ICON = "rbxassetid://120590444497312"

local OPEN_COOLDOWN = 1.25
local MAX_INPUT_DIAMONDS = 10000

local COLORS = {
	shade = Color3.fromRGB(0, 0, 0),

	panel = Color3.fromRGB(204, 144, 71),
	panelDark = Color3.fromRGB(91, 55, 32),
	brown = Color3.fromRGB(128, 82, 49),
	cream = Color3.fromRGB(255, 232, 190),
	cream2 = Color3.fromRGB(244, 216, 178),

	green = Color3.fromRGB(78, 164, 73),
	red = Color3.fromRGB(188, 83, 78),
	gray = Color3.fromRGB(148, 134, 116),
	blue = Color3.fromRGB(84, 170, 235),

	white = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(55, 31, 18),
	muted = Color3.fromRGB(110, 77, 53),
}

--============================================================
-- HELPERS
--============================================================

local function create(className, props, parent)
	local object = Instance.new(className)

	for key, value in pairs(props or {}) do
		object[key] = value
	end

	object.Parent = parent
	return object
end

local function corner(object, radius)
	create("UICorner", {
		CornerRadius = UDim.new(0, radius or 10),
	}, object)
end

local function stroke(object, thickness, color, transparency)
	return create("UIStroke", {
		Thickness = thickness or 2,
		Color = color or COLORS.panelDark,
		Transparency = transparency or 0,
	}, object)
end

local function addButtonMotion(button)
	local scale = create("UIScale", {Scale = 1}, button)

	button.MouseEnter:Connect(function()
		if not button.Active then return end

		TweenService:Create(
			scale,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Scale = 1.035}
		):Play()
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), {Scale = 1}):Play()
	end)

	button.MouseButton1Down:Connect(function()
		if not button.Active then return end
		TweenService:Create(scale, TweenInfo.new(0.07), {Scale = 0.95}):Play()
	end)

	button.MouseButton1Up:Connect(function()
		if not button.Active then return end

		TweenService:Create(
			scale,
			TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Scale = 1.035}
		):Play()
	end)
end

local function formatNumber(number)
	number = math.max(0, math.floor(tonumber(number) or 0))
	local text = tostring(number)

	while true do
		local replaced, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		text = replaced
		if count == 0 then break end
	end

	return text
end

--============================================================
-- GUI
--============================================================

local old = playerGui:FindFirstChild("WilliamBankGui")
if old then old:Destroy() end

local gui = create("ScreenGui", {
	Name = "WilliamBankGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 9100,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local shade = create("Frame", {
	Name = "Shade",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = COLORS.shade,
	BackgroundTransparency = 0.48,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 1,
}, gui)

local panel = create("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(700, 400),
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 10,
}, gui)

corner(panel, 18)
stroke(panel, 4)

local responsiveScale = create("UIScale", {
	Name = "ResponsiveScale",
	Scale = 1,
}, panel)

local function getResponsiveScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)

	return math.clamp(
		math.min(viewport.X / 860, viewport.Y / 620),
		0.58,
		1
	)
end

--============================================================
-- HEADER
--============================================================

local title = create("TextLabel", {
	Position = UDim2.fromOffset(18, 16),
	Size = UDim2.new(1, -82, 0, 62),
	BackgroundColor3 = COLORS.cream,
	BorderSizePixel = 0,
	Text = "EMPLEADO WILLIAM",
	Font = FONT,
	TextScaled = true,
	TextColor3 = COLORS.text,
	ZIndex = 11,
}, panel)

corner(title, 10)
stroke(title, 2)

create("UITextSizeConstraint", {
	MinTextSize = 24,
	MaxTextSize = 38,
}, title)

local closeButton = create("TextButton", {
	Name = "Close",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -18, 0, 22),
	Size = UDim2.fromOffset(46, 46),
	BackgroundColor3 = COLORS.red,
	BorderSizePixel = 0,
	Text = "X",
	Font = FONT,
	TextScaled = true,
	TextColor3 = COLORS.white,
	AutoButtonColor = false,
	ZIndex = 12,
}, panel)

corner(closeButton, 10)
stroke(closeButton, 2)
addButtonMotion(closeButton)

create("TextLabel", {
	Position = UDim2.fromOffset(24, 84),
	Size = UDim2.new(1, -48, 0, 30),
	BackgroundTransparency = 1,
	Text = "Cambia tus diamantes por dolares",
	Font = FONT,
	TextSize = 20,
	TextColor3 = COLORS.text,
	ZIndex = 11,
}, panel)

--============================================================
-- CONVERSION DINAMICA
-- La cantidad puede ser grande sin encimarse con los iconos.
--============================================================

local rateCard = create("Frame", {
	Position = UDim2.fromOffset(24, 128),
	Size = UDim2.new(1, -48, 0, 86),
	BackgroundColor3 = COLORS.brown,
	BorderSizePixel = 0,
	ZIndex = 11,
}, panel)

corner(rateCard, 12)
stroke(rateCard, 3)

-- Lado izquierdo: Diamantes
local diamondSide = create("Frame", {
	Position = UDim2.new(0, 10, 0, 8),
	Size = UDim2.new(0.43, -10, 1, -16),
	BackgroundTransparency = 1,
	ZIndex = 12,
}, rateCard)

local diamondIcon = create("ImageLabel", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 8, 0.5, 0),
	Size = UDim2.fromOffset(50, 50),
	BackgroundTransparency = 1,
	Image = DIAMOND_ICON,
	ScaleType = Enum.ScaleType.Fit,
	ZIndex = 13,
}, diamondSide)

local rateDiamondText = create("TextLabel", {
	Position = UDim2.fromOffset(66, 0),
	Size = UDim2.new(1, -72, 1, 0),
	BackgroundTransparency = 1,
	Text = "1",
	Font = FONT,
	TextScaled = true,
	TextColor3 = COLORS.white,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center,
	ZIndex = 13,
}, diamondSide)

create("UITextSizeConstraint", {
	MinTextSize = 16,
	MaxTextSize = 34,
}, rateDiamondText)

-- Signo =
create("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(54, 54),
	BackgroundTransparency = 1,
	Text = "=",
	Font = FONT,
	TextSize = 34,
	TextColor3 = COLORS.white,
	ZIndex = 13,
}, rateCard)

-- Lado derecho: Dolares
local moneySide = create("Frame", {
	Position = UDim2.new(0.57, 0, 0, 8),
	Size = UDim2.new(0.43, -10, 1, -16),
	BackgroundTransparency = 1,
	ZIndex = 12,
}, rateCard)

local moneyIcon = create("ImageLabel", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 0, 0.5, 0),
	Size = UDim2.fromOffset(50, 50),
	BackgroundTransparency = 1,
	Image = MONEY_ICON,
	ScaleType = Enum.ScaleType.Fit,
	ZIndex = 13,
}, moneySide)

local rateMoneyText = create("TextLabel", {
	Position = UDim2.fromOffset(58, 0),
	Size = UDim2.new(1, -62, 1, 0),
	BackgroundTransparency = 1,
	Text = "100$",
	Font = FONT,
	TextScaled = true,
	TextColor3 = COLORS.white,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center,
	ZIndex = 13,
}, moneySide)

create("UITextSizeConstraint", {
	MinTextSize = 14,
	MaxTextSize = 34,
}, rateMoneyText)

--============================================================
-- CANTIDAD DE DIAMANTES
--============================================================

local quantityHolder = create("Frame", {
	Position = UDim2.fromOffset(24, 228),
	Size = UDim2.new(1, -48, 0, 72),
	BackgroundColor3 = COLORS.cream2,
	BorderSizePixel = 0,
	ZIndex = 11,
}, panel)

corner(quantityHolder, 12)
stroke(quantityHolder, 2)

create("TextLabel", {
	Position = UDim2.fromOffset(14, 6),
	Size = UDim2.new(1, -28, 0, 22),
	BackgroundTransparency = 1,
	Text = "DIAMANTES QUE QUIERES CAMBIAR",
	Font = FONT,
	TextSize = 16,
	TextColor3 = COLORS.muted,
	ZIndex = 12,
}, quantityHolder)

local minusButton = create("TextButton", {
	Position = UDim2.fromOffset(14, 32),
	Size = UDim2.fromOffset(52, 32),
	BackgroundColor3 = COLORS.brown,
	BorderSizePixel = 0,
	Text = "-",
	Font = FONT,
	TextSize = 26,
	TextColor3 = COLORS.white,
	AutoButtonColor = false,
	ZIndex = 12,
}, quantityHolder)

corner(minusButton, 8)
stroke(minusButton, 2)
addButtonMotion(minusButton)

local quantityBox = create("TextBox", {
	Position = UDim2.fromOffset(74, 32),
	Size = UDim2.fromOffset(112, 32),
	BackgroundColor3 = COLORS.white,
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	Text = "1",
	PlaceholderText = "1",
	Font = FONT,
	TextSize = 20,
	TextColor3 = COLORS.text,
	PlaceholderColor3 = COLORS.gray,
	ZIndex = 12,
}, quantityHolder)

corner(quantityBox, 8)
stroke(quantityBox, 2)

local plusButton = create("TextButton", {
	Position = UDim2.fromOffset(194, 32),
	Size = UDim2.fromOffset(52, 32),
	BackgroundColor3 = COLORS.brown,
	BorderSizePixel = 0,
	Text = "+",
	Font = FONT,
	TextSize = 24,
	TextColor3 = COLORS.white,
	AutoButtonColor = false,
	ZIndex = 12,
}, quantityHolder)

corner(plusButton, 8)
stroke(plusButton, 2)
addButtonMotion(plusButton)

local presets = {
	{text = "x1", amount = 1},
	{text = "x5", amount = 5},
	{text = "x10", amount = 10},
}

local presetX = 262

for index, preset in ipairs(presets) do
	local button = create("TextButton", {
		Position = UDim2.fromOffset(presetX + (index - 1) * 68, 32),
		Size = UDim2.fromOffset(60, 32),
		BackgroundColor3 = COLORS.brown,
		BorderSizePixel = 0,
		Text = preset.text,
		Font = FONT,
		TextSize = 16,
		TextColor3 = COLORS.white,
		AutoButtonColor = false,
		ZIndex = 12,
	}, quantityHolder)

	corner(button, 8)
	stroke(button, 2)
	addButtonMotion(button)

	button:SetAttribute("PresetAmount", preset.amount)
end

local maxButton = create("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 32),
	Size = UDim2.fromOffset(76, 32),
	BackgroundColor3 = COLORS.blue,
	BorderSizePixel = 0,
	Text = "MAX",
	Font = FONT,
	TextSize = 16,
	TextColor3 = COLORS.white,
	AutoButtonColor = false,
	ZIndex = 12,
}, quantityHolder)

corner(maxButton, 8)
stroke(maxButton, 2)
addButtonMotion(maxButton)

--============================================================
-- BOTON DE CAMBIO
--============================================================

local exchangeButton = create("TextButton", {
	Name = "Exchange",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 316),
	Size = UDim2.fromOffset(470, 54),
	BackgroundColor3 = COLORS.green,
	BorderSizePixel = 0,
	Text = "CAMBIAR 1 DIAMANTE POR 100$",
	Font = FONT,
	TextScaled = true,
	TextColor3 = COLORS.white,
	AutoButtonColor = false,
	ZIndex = 12,
}, panel)

corner(exchangeButton, 12)
stroke(exchangeButton, 3)
addButtonMotion(exchangeButton)

create("UITextSizeConstraint", {
	MinTextSize = 15,
	MaxTextSize = 24,
}, exchangeButton)

local status = create("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.new(1, -48, 0, 22),
	BackgroundTransparency = 1,
	Text = "",
	Font = FONT,
	TextSize = 14,
	TextColor3 = COLORS.text,
	TextWrapped = true,
	ZIndex = 12,
}, panel)

--============================================================
-- LOGICA
--============================================================

local state = {
	dollars = 0,
	diamonds = 0,
	dollarsPerDiamond = 100,
	maxExchangeable = 0,
}

local busy = false
local lastOpenedAt = -math.huge

local function getQuantity()
	local number = tonumber(quantityBox.Text)
	if not number then return 1 end

	return math.clamp(
		math.floor(number),
		1,
		MAX_INPUT_DIAMONDS
	)
end

local function setQuantity(value)
	value = math.clamp(
		math.floor(tonumber(value) or 1),
		1,
		MAX_INPUT_DIAMONDS
	)

	quantityBox.Text = tostring(value)
end

local function render()
	local quantity = getQuantity()
	local rate = math.max(1, math.floor(tonumber(state.dollarsPerDiamond) or 100))
	local received = quantity * rate

	-- La tarjeta central muestra EN VIVO lo que entregas y recibes.
	rateDiamondText.Text = formatNumber(quantity)
	rateMoneyText.Text = formatNumber(received) .. "$"

	if busy then
		exchangeButton.Active = false
		exchangeButton.BackgroundColor3 = COLORS.gray
		exchangeButton.Text = "PROCESANDO..."
		return
	end

	if state.diamonds < quantity then
		exchangeButton.Active = false
		exchangeButton.BackgroundColor3 = COLORS.gray
		exchangeButton.Text = "NO TIENES SUFICIENTES DIAMANTES"
	else
		exchangeButton.Active = true
		exchangeButton.BackgroundColor3 = COLORS.green
		exchangeButton.Text =
			"CAMBIAR "
			.. formatNumber(quantity)
			.. (quantity == 1 and " DIAMANTE POR " or " DIAMANTES POR ")
			.. formatNumber(received)
			.. "$"
	end
end

local function applyState(newState)
	if typeof(newState) ~= "table" then return end

	state.dollars = math.max(0, math.floor(tonumber(newState.dollars) or 0))
	state.diamonds = math.max(0, math.floor(tonumber(newState.diamonds) or 0))
	state.dollarsPerDiamond = math.max(1, math.floor(tonumber(newState.dollarsPerDiamond) or 100))
	state.maxExchangeable = math.max(0, math.floor(tonumber(newState.maxExchangeable) or state.diamonds))

	render()
end

local function fetchState()
	status.Text = "Cargando tus monedas..."

	local ok, result = pcall(function()
		return GetBankState:InvokeServer()
	end)

	if ok and typeof(result) == "table" then
		applyState(result)
		status.Text = ""
		return true
	end

	status.Text = "No se pudieron cargar tus monedas."
	return false
end

local function openBank()
	if panel.Visible then return end

	local now = os.clock()

	if now - lastOpenedAt < OPEN_COOLDOWN then
		return
	end

	lastOpenedAt = now
	setQuantity(1)
	fetchState()

	shade.Visible = true
	panel.Visible = true

	local targetScale = getResponsiveScale()
	responsiveScale.Scale = targetScale * 0.82
	panel.Position = UDim2.fromScale(0.5, 0.515)

	TweenService:Create(
		responsiveScale,
		TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Scale = targetScale}
	):Play()

	TweenService:Create(
		panel,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Position = UDim2.fromScale(0.5, 0.5)}
	):Play()
end

local function closeBank()
	if busy then return end

	panel.Visible = false
	shade.Visible = false
	status.Text = ""
end

closeButton.Activated:Connect(closeBank)

quantityBox:GetPropertyChangedSignal("Text"):Connect(function()
	local cleaned = tostring(quantityBox.Text):gsub("[^%d]", "")

	if quantityBox.Text ~= cleaned then
		quantityBox.Text = cleaned
		return
	end

	if cleaned ~= "" then
		render()
	end
end)

quantityBox.FocusLost:Connect(function()
	setQuantity(getQuantity())
	render()
end)

minusButton.Activated:Connect(function()
	setQuantity(getQuantity() - 1)
	render()
end)

plusButton.Activated:Connect(function()
	setQuantity(getQuantity() + 1)
	render()
end)

for _, child in ipairs(quantityHolder:GetChildren()) do
	if child:IsA("TextButton") then
		local amount = child:GetAttribute("PresetAmount")

		if typeof(amount) == "number" then
			child.Activated:Connect(function()
				setQuantity(amount)
				render()
			end)
		end
	end
end

maxButton.Activated:Connect(function()
	if state.maxExchangeable <= 0 then
		setQuantity(1)
	else
		setQuantity(math.min(state.maxExchangeable, MAX_INPUT_DIAMONDS))
	end

	render()
end)

exchangeButton.Activated:Connect(function()
	if busy or not exchangeButton.Active then
		return
	end

	local quantity = getQuantity()

	if state.diamonds < quantity then
		status.Text = "No tienes suficientes Diamantes."
		render()
		return
	end

	busy = true
	status.Text = "William esta haciendo el cambio..."
	render()

	local ok, result = pcall(function()
		return ExchangeDiamondsForDollars:InvokeServer(quantity)
	end)

	busy = false

	if ok and typeof(result) == "table" then
		if result.state then
			applyState(result.state)
		end

		status.Text = tostring(result.message or "")

		if result.ok then
			local scale = exchangeButton:FindFirstChildOfClass("UIScale")

			if scale then
				scale.Scale = 0.92

				TweenService:Create(
					scale,
					TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{Scale = 1}
				):Play()
			end
		end
	else
		status.Text = "No se pudo completar el cambio."
	end

	render()
end)

--============================================================
-- PROMPT
--============================================================

local function configureWilliamPrompt(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return
	end

	prompt.ActionText = "Hablar"
	prompt.ObjectText = "William"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = math.max(prompt.HoldDuration, 0.55)
	prompt.MaxActivationDistance = math.max(prompt.MaxActivationDistance, 14)
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true
end

ProximityPromptService.PromptShown:Connect(function(prompt)
	if prompt.Name == "WilliamBankPrompt" then
		configureWilliamPrompt(prompt)
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, promptPlayer)
	if not prompt or prompt.Name ~= "WilliamBankPrompt" then
		return
	end

	if promptPlayer ~= nil and promptPlayer ~= player then
		return
	end

	openBank()
end)

task.spawn(function()
	for _ = 1, 60 do
		for _, object in ipairs(workspace:GetDescendants()) do
			if object:IsA("ProximityPrompt")
				and object.Name == "WilliamBankPrompt"
			then
				configureWilliamPrompt(object)
				return
			end
		end

		task.wait(0.5)
	end

	warn("[WilliamBankClient] No encontre WilliamBankPrompt.")
end)