--============================================================
-- OSWALD ROBUX SHOP CLIENT
-- Ubicacion: StarterPlayer > StarterPlayerScripts > OswaldRobuxShopClient
-- Tipo: LocalScript
--
-- Productos:
-- 750$    = 150 Robux
-- 2,500$  = 500 Robux
-- 7,500$  = 1,500 Robux
-- 55,000$ = 5,000 Robux
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local folder = ReplicatedStorage:WaitForChild("OswaldRobuxShopSystem")
local GetProducts = folder:WaitForChild("GetProducts")
local PurchaseResult = folder:WaitForChild("PurchaseResult")

local FONT = Enum.Font.FredokaOne
local MONEY_ICON = "rbxassetid://117128537983961"

local COLORS = {
	shade = Color3.fromRGB(0, 0, 0),
	panel = Color3.fromRGB(204, 144, 71),
	dark = Color3.fromRGB(91, 55, 32),
	brown = Color3.fromRGB(128, 82, 49),
	cream = Color3.fromRGB(255, 232, 190),
	cream2 = Color3.fromRGB(244, 216, 178),
	green = Color3.fromRGB(78, 164, 73),
	blue = Color3.fromRGB(65, 143, 222),
	red = Color3.fromRGB(188, 83, 78),
	gray = Color3.fromRGB(148, 134, 116),
	white = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(55, 31, 18),
	muted = Color3.fromRGB(110, 77, 53),
}

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
		Color = color or COLORS.dark,
		Transparency = transparency or 0,
	}, object)
end

local function addMotion(button)
	local scale = create("UIScale", {Scale = 1}, button)

	button.MouseEnter:Connect(function()
		if button.Active then
			TweenService:Create(
				scale,
				TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Scale = 1.035}
			):Play()
		end
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), {Scale = 1}):Play()
	end)

	button.MouseButton1Down:Connect(function()
		if button.Active then
			TweenService:Create(scale, TweenInfo.new(0.07), {Scale = 0.95}):Play()
		end
	end)

	button.MouseButton1Up:Connect(function()
		if button.Active then
			TweenService:Create(
				scale,
				TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{Scale = 1.035}
			):Play()
		end
	end)
end

local function formatNumber(number)
	number = math.max(0, math.floor(tonumber(number) or 0))
	local text = tostring(number)

	while true do
		local nextText, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		text = nextText
		if count == 0 then
			break
		end
	end

	return text
end

local products = {}

local okProducts, resultProducts = pcall(function()
	return GetProducts:InvokeServer()
end)

if okProducts and typeof(resultProducts) == "table" then
	products = resultProducts
else
	products = {
		{productId = 3709750798, dollars = 750, robux = 150},
		{productId = 3709750847, dollars = 2500, robux = 500},
		{productId = 3709750869, dollars = 7500, robux = 1500},
		{productId = 3709750906, dollars = 55000, robux = 5000},
	}
end

local old = playerGui:FindFirstChild("OswaldRobuxShopGui")
if old then
	old:Destroy()
end

local gui = create("ScreenGui", {
	Name = "OswaldRobuxShopGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 9150,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local shade = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = COLORS.shade,
	BackgroundTransparency = 0.48,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 1,
}, gui)

local panel = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(720, 500),
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 10,
}, gui)

corner(panel, 18)
stroke(panel, 4)

local responsiveScale = create("UIScale", {
	Scale = 1,
}, panel)

local function getScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)

	return math.clamp(
		math.min(viewport.X / 900, viewport.Y / 650),
		0.58,
		1
	)
end

local title = create("TextLabel", {
	Position = UDim2.fromOffset(18, 16),
	Size = UDim2.new(1, -82, 0, 62),
	BackgroundColor3 = COLORS.cream,
	BorderSizePixel = 0,
	Text = "EMPLEADO OSWALD",
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

local close = create("TextButton", {
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

corner(close, 10)
stroke(close, 2)
addMotion(close)

create("TextLabel", {
	Position = UDim2.fromOffset(24, 86),
	Size = UDim2.new(1, -48, 0, 30),
	BackgroundTransparency = 1,
	Text = "Compra dolares con Robux",
	Font = FONT,
	TextSize = 20,
	TextColor3 = COLORS.text,
	ZIndex = 11,
}, panel)

local holder = create("Frame", {
	Position = UDim2.fromOffset(24, 128),
	Size = UDim2.new(1, -48, 0, 290),
	BackgroundColor3 = COLORS.brown,
	BorderSizePixel = 0,
	ZIndex = 11,
}, panel)

corner(holder, 12)
stroke(holder, 3)

create("UIPadding", {
	PaddingTop = UDim.new(0, 12),
	PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
}, holder)

create("UIGridLayout", {
	CellSize = UDim2.fromOffset(315, 125),
	CellPadding = UDim2.fromOffset(12, 12),
	FillDirectionMaxCells = 2,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, holder)

local cards = {}

for index, info in ipairs(products) do
	local card = create("Frame", {
		BackgroundColor3 = COLORS.cream2,
		BorderSizePixel = 0,
		LayoutOrder = index,
		ZIndex = 12,
	}, holder)

	corner(card, 11)
	stroke(card, 2)

	create("ImageLabel", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.39, 0),
		Size = UDim2.fromOffset(62, 62),
		BackgroundTransparency = 1,
		Image = MONEY_ICON,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 13,
	}, card)

	create("TextLabel", {
		Position = UDim2.fromOffset(86, 12),
		Size = UDim2.new(1, -100, 0, 48),
		BackgroundTransparency = 1,
		Text = formatNumber(info.dollars) .. "$",
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = FONT,
		TextSize = 28,
		TextColor3 = COLORS.text,
		ZIndex = 13,
	}, card)

	local buy = create("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -24, 0, 42),
		BackgroundColor3 = COLORS.green,
		BorderSizePixel = 0,
		Text = formatNumber(info.robux) .. " ROBUX",
		Font = FONT,
		TextSize = 19,
		TextColor3 = COLORS.white,
		AutoButtonColor = false,
		ZIndex = 13,
	}, card)

	corner(buy, 9)
	stroke(buy, 2)
	addMotion(buy)

	buy:SetAttribute("ProductId", info.productId)
	buy:SetAttribute("Dollars", info.dollars)
	table.insert(cards, buy)
end

local status = create("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -14),
	Size = UDim2.new(1, -48, 0, 42),
	BackgroundTransparency = 1,
	Text = "",
	Font = FONT,
	TextSize = 16,
	TextColor3 = COLORS.text,
	TextWrapped = true,
	ZIndex = 12,
}, panel)

local purchasing = false
local currentProductId = nil
local lastOpenAt = -math.huge

local function setButtonsEnabled(enabled)
	for _, button in ipairs(cards) do
		button.Active = enabled
		button.BackgroundColor3 = enabled and COLORS.green or COLORS.gray
	end
end

local function openShop()
	if panel.Visible then
		return
	end

	local now = os.clock()
	if now - lastOpenAt < 1 then
		return
	end

	lastOpenAt = now
	status.Text = ""
	shade.Visible = true
	panel.Visible = true

	local target = getScale()
	responsiveScale.Scale = target * 0.82
	panel.Position = UDim2.fromScale(0.5, 0.515)

	TweenService:Create(
		responsiveScale,
		TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Scale = target}
	):Play()

	TweenService:Create(
		panel,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Position = UDim2.fromScale(0.5, 0.5)}
	):Play()
end

local function closeShop()
	if purchasing then
		return
	end

	panel.Visible = false
	shade.Visible = false
	status.Text = ""
end

close.Activated:Connect(closeShop)

for _, button in ipairs(cards) do
	button.Activated:Connect(function()
		if purchasing then
			return
		end

		local productId = tonumber(button:GetAttribute("ProductId"))
		local dollars = tonumber(button:GetAttribute("Dollars")) or 0

		if not productId or productId <= 0 then
			status.Text = "Producto invalido."
			return
		end

		purchasing = true
		currentProductId = productId
		setButtonsEnabled(false)
		status.Text =
			"Compra "
			.. formatNumber(dollars)
			.. "$ con Robux..."

		MarketplaceService:PromptProductPurchase(
			player,
			productId
		)
	end)
end

MarketplaceService.PromptProductPurchaseFinished:Connect(
	function(userId, productId, wasPurchased)
		if userId ~= player.UserId then
			return
		end

		if currentProductId ~= productId then
			return
		end

		if not wasPurchased then
			purchasing = false
			currentProductId = nil
			setButtonsEnabled(true)
			status.Text = "Compra cancelada."
		else
			-- No damos el dinero aqui.
			-- Esperamos ProcessReceipt del servidor.
			status.Text = "Procesando compra..."
		end
	end
)

PurchaseResult.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then
		return
	end

	purchasing = false
	currentProductId = nil
	setButtonsEnabled(true)

	if data.ok then
		status.Text =
			"Compra completada: +"
			.. formatNumber(data.dollars)
			.. "$"
	else
		status.Text = tostring(data.message or "No se pudo completar la compra.")
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, promptPlayer)
	if prompt.Name ~= "OswaldBankPrompt" then
		return
	end

	if promptPlayer ~= nil and promptPlayer ~= player then
		return
	end

	openShop()
end)