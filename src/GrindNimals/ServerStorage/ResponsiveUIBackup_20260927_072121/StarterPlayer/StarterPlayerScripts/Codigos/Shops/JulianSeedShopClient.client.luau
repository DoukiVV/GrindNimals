--============================================================
-- JULIAN - INTERFAZ V4.6 - FILTROS COMPRA + REFRESH VENTA
-- Colocar en:
-- StarterPlayer > StarterPlayerScripts > JulianSeedShopClient
--
-- La interfaz se crea sola.
-- No necesitas crear ScreenGui, Frames ni botones manualmente.
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("JulianSeedShop")
local OpenShop = remotes:WaitForChild("OpenShop")
local GetCatalog = remotes:WaitForChild("GetCatalog")
local BuySeed = remotes:WaitForChild("BuySeed")
local SellSeed = remotes:WaitForChild("SellSeed")

local FONT = Enum.Font.FredokaOne

--============================================================
-- FONDOS DE SEMILLAS
--
-- IDs que me diste:
-- Cultivos: 92350017860944
-- Arboles:  106574900935819
--
-- IMPORTANTE:
-- El fondo SIEMPRE se muestra por debajo del icono real del Tool.
--============================================================

local CULTIVO_BACKGROUND = "rbxassetid://92350017860944"
local TREE_BACKGROUND = "rbxassetid://106574900935819"

-- Clasificacion EXACTA que me diste.
local CROP_BACKGROUND_KIND = {
	-- CULTIVOS
	LechugaMorada = "Cultivo",
	TrufaNegra = "Cultivo",
	TrufaBlanca = "Cultivo",
	Calabaza = "Cultivo",
	Cebolla = "Cultivo",
	Col = "Cultivo",
	ColMorada = "Cultivo",
	MelonVerde = "Cultivo",
	["Piña"] = "Cultivo",
	Pina = "Cultivo",
	Remolacha = "Cultivo",
	Tomate = "Cultivo",
	Trigo = "Cultivo",

	-- ARBOLES
	Cacao = "Arbol",
	Carambola = "Arbol",
	Coco = "Arbol",
	Durian = "Arbol",
	FrutaDragon = "Arbol",
	Granada = "Arbol",
	Lichi = "Arbol",
	Mango = "Arbol",
	Mangostan = "Arbol",
	Manzana = "Arbol",
	Naranja = "Arbol",
	Platano = "Arbol",
}

-- Estas semillas de la tienda no venian clasificadas en tu mensaje.
-- Por ahora usan fondo de CULTIVO para que nunca queden sin fondo.
local TEMP_CULTIVO_FALLBACK = {
	Fresa = true,
	Zanahoria = true,
	Papa = true,
	Lechuga = true,
	Yuca = true,
	Higo = true,
	Alcachofa = true,
}

local function backgroundForCrop(crop)
	local kind = CROP_BACKGROUND_KIND[crop]

	if kind == "Arbol" then
		return TREE_BACKGROUND
	end

	if kind == "Cultivo" then
		return CULTIVO_BACKGROUND
	end

	if TEMP_CULTIVO_FALLBACK[crop] then
		return CULTIVO_BACKGROUND
	end

	-- Cualquier semilla nueva queda visible mientras la clasificas.
	return CULTIVO_BACKGROUND
end

local COLORS = {
	panel = Color3.fromRGB(180, 126, 76),
	panel2 = Color3.fromRGB(156, 108, 70),
	dark = Color3.fromRGB(75, 45, 28),
	dark2 = Color3.fromRGB(48, 29, 19),
	cream = Color3.fromRGB(255, 232, 190),
	cream2 = Color3.fromRGB(239, 211, 165),
	white = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(52, 31, 19),
	green = Color3.fromRGB(73, 166, 79),
	greenHover = Color3.fromRGB(88, 188, 94),
	red = Color3.fromRGB(185, 76, 69),
	common = Color3.fromRGB(184, 184, 184),
	rare = Color3.fromRGB(78, 157, 255),
	veryRare = Color3.fromRGB(178, 91, 235),
	epic = Color3.fromRGB(145, 73, 200),
	legendary = Color3.fromRGB(214, 165, 48),
	selected = Color3.fromRGB(255, 210, 100),
}

local function rarityColor(rarity)
	if rarity == "Comun" then
		return COLORS.common
	elseif rarity == "Raro" then
		return COLORS.rare
	elseif rarity == "Muy Raro" then
		return COLORS.veryRare
	elseif rarity == "Epico" then
		return COLORS.epic
	elseif rarity == "Legendario" then
		return COLORS.legendary
	end

	return Color3.fromRGB(115, 101, 89)
end

local function create(className, props, parent)
	local obj = Instance.new(className)
	for key, value in pairs(props or {}) do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

local function corner(obj, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = obj
	return c
end

local function stroke(obj, thickness, color, transparency)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 2
	s.Color = color or COLORS.dark
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = obj
	return s
end

local function constraint(label, minSize, maxSize)
	local c = Instance.new("UITextSizeConstraint")
	c.MinTextSize = minSize or 8
	c.MaxTextSize = maxSize or 24
	c.Parent = label
	return c
end

local function scaleFor(button)
	local scale = button:FindFirstChild("MotionScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "MotionScale"
		scale.Parent = button
	end
	return scale
end

local function animateButton(button)
	if not button:IsA("GuiButton") then
		return
	end

	local s = scaleFor(button)

	button.MouseEnter:Connect(function()
		TweenService:Create(
			s,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Scale = 1.035}
		):Play()
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(
			s,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Scale = 1}
		):Play()
	end)

	button.MouseButton1Down:Connect(function()
		TweenService:Create(
			s,
			TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Scale = 0.95}
		):Play()
	end)

	button.MouseButton1Up:Connect(function()
		TweenService:Create(
			s,
			TweenInfo.new(0.17, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Scale = 1.03}
		):Play()
	end)
end

--============================================================
-- GUI
--============================================================

local old = playerGui:FindFirstChild("JulianSeedShopGui")
if old then
	old:Destroy()
end

local gui = create("ScreenGui", {
	Name = "JulianSeedShopGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	Enabled = false,
	DisplayOrder = 90,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local dim = create("Frame", {
	Name = "Dim",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(25, 17, 12),
	BackgroundTransparency = 0.42,
	BorderSizePixel = 0,
	ZIndex = 1,
}, gui)

local panel = create("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(840, 525),
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	ZIndex = 10,
}, gui)
corner(panel, 14)
stroke(panel, 4, COLORS.dark)

local panelScale = create("UIScale", {
	Name = "ResponsiveScale",
	Scale = 1,
}, panel)

local function updateResponsiveScale()
	local camera = Workspace.CurrentCamera
	local viewport =
		camera
		and camera.ViewportSize
		or Vector2.new(
			1280,
			720
		)

	-- V4.5:
	-- Queremos que Julian ocupe aprox. 90% del ancho/alto disponible.
	-- Así en PC las letras dejan de verse pequeñas y en pantallas
	-- menores sigue entrando completa.
	local scaleByWidth =
		(viewport.X * 0.90)
		/ 840

	local scaleByHeight =
		(viewport.Y * 0.90)
		/ 525

	panelScale.Scale =
		math.clamp(
			math.min(
				scaleByWidth,
				scaleByHeight
			),
			0.76,
			1.20
		)
end

updateResponsiveScale()

if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale)
end

--============================================================
-- CABECERA
--============================================================

local header = create("Frame", {
	Name = "Header",
	Position = UDim2.fromOffset(16, 14),
	Size = UDim2.new(1, -32, 0, 66),
	BackgroundColor3 = COLORS.cream,
	BorderSizePixel = 0,
	ZIndex = 11,
}, panel)
corner(header, 10)
stroke(header, 2, COLORS.dark)

local title = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(18, 4),
	Size = UDim2.new(1, -250, 0, 34),
	Text = "TIENDA DE JULIAN",
	Font = FONT,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = COLORS.text,
	ZIndex = 12,
}, header)
constraint(title, 21, 33)

local subtitle = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(20, 37),
	Size = UDim2.new(1, -260, 0, 22),
	Text = "Julian • Compra o vende tus semillas",
	Font = FONT,
	TextSize = 17,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(115, 76, 49),
	ZIndex = 12,
}, header)

local moneyLabel = create("TextLabel", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -62, 0.5, 0),
	Size = UDim2.fromOffset(170, 40),
	BackgroundColor3 = COLORS.dark,
	BorderSizePixel = 0,
	Text = "0$",
	Font = FONT,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 239, 156),
	ZIndex = 13,
}, header)
corner(moneyLabel, 9)
stroke(moneyLabel, 2, COLORS.dark2)
constraint(moneyLabel, 14, 23)

local closeButton = create("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(38, 38),
	BackgroundColor3 = COLORS.red,
	BorderSizePixel = 0,
	Text = "X",
	Font = FONT,
	TextSize = 20,
	TextColor3 = COLORS.white,
	AutoButtonColor = false,
	ZIndex = 14,
}, header)
corner(closeButton, 9)
stroke(closeButton, 2, COLORS.dark)
animateButton(closeButton)

--============================================================
-- IZQUIERDA: CATALOGO
--============================================================

local catalogPanel = create("Frame", {
	Name = "CatalogPanel",
	Position = UDim2.fromOffset(16, 92),
	Size = UDim2.fromOffset(565, 417),
	BackgroundColor3 = COLORS.panel2,
	BorderSizePixel = 0,
	ZIndex = 11,
}, panel)
corner(catalogPanel, 11)
stroke(catalogPanel, 2, COLORS.dark)

local modeTabs = create("Frame", {
	Name = "ModeTabs",
	Position = UDim2.fromOffset(10, 8),
	Size = UDim2.new(1, -20, 0, 34),
	BackgroundTransparency = 1,
	ZIndex = 12,
}, catalogPanel)

local buyModeButton = create("TextButton", {
	Name = "BuyMode",
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.new(0.5, -4, 1, 0),
	BackgroundColor3 = COLORS.green,
	BorderSizePixel = 0,
	Text = "COMPRAR SEMILLAS",
	Font = FONT,
	TextSize = 16,
	TextColor3 = COLORS.white,
	AutoButtonColor = false,
	ZIndex = 13,
}, modeTabs)
corner(buyModeButton, 8)
stroke(buyModeButton, 2, COLORS.dark)
animateButton(buyModeButton)

local sellModeButton = create("TextButton", {
	Name = "SellMode",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 0),
	Size = UDim2.new(0.5, -4, 1, 0),
	BackgroundColor3 = COLORS.dark,
	BorderSizePixel = 0,
	Text = "VENDER SEMILLAS",
	Font = FONT,
	TextSize = 16,
	TextColor3 = COLORS.white,
	AutoButtonColor = false,
	ZIndex = 13,
}, modeTabs)
corner(sellModeButton, 8)
stroke(sellModeButton, 2, COLORS.dark)
animateButton(sellModeButton)

local filters = create("Frame", {
	Name = "Filters",
	Position = UDim2.fromOffset(10, 47),
	Size = UDim2.new(1, -20, 0, 34),
	BackgroundTransparency = 1,
	ZIndex = 12,
}, catalogPanel)

local filterLayout = create("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 5),
	VerticalAlignment = Enum.VerticalAlignment.Center,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, filters)

local filterButtons = {}
local filterDefinitions = {
	{"Todas", "Todas", 68},
	{"Común", "Comun", 75},
	{"Raro", "Raro", 65},
	{"Muy raro", "Muy Raro", 88},
	{"Épico", "Epico", 70},
	{"Legendario", "Legendario", 105},
}

for index, data in ipairs(filterDefinitions) do
	local button = create("TextButton", {
		Name = "Filter_" .. data[2],
		Size = UDim2.fromOffset(data[3], 31),
		BackgroundColor3 = COLORS.cream2,
		BorderSizePixel = 0,
		Text = data[1],
		Font = FONT,
		TextSize = 14,
		TextColor3 = COLORS.text,
		AutoButtonColor = false,
		LayoutOrder = index,
		ZIndex = 13,
	}, filters)
	corner(button, 8)
	stroke(button, 2, COLORS.dark)
	animateButton(button)
	filterButtons[data[2]] = button
end

local seedList = create("ScrollingFrame", {
	Name = "SeedList",
	Position = UDim2.fromOffset(10, 88),
	Size = UDim2.new(1, -20, 1, -98),
	BackgroundColor3 = Color3.fromRGB(113, 76, 50),
	BackgroundTransparency = 0.10,
	BorderSizePixel = 0,
	ScrollBarThickness = 7,
	ScrollBarImageColor3 = COLORS.cream,
	CanvasSize = UDim2.fromOffset(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 12,
}, catalogPanel)
corner(seedList, 9)
stroke(seedList, 2, COLORS.dark)

create("UIPadding", {
	PaddingTop = UDim.new(0, 9),
	PaddingBottom = UDim.new(0, 9),
	PaddingLeft = UDim.new(0, 9),
	PaddingRight = UDim.new(0, 9),
}, seedList)

local grid = create("UIGridLayout", {
	CellSize = UDim2.fromOffset(170, 142),
	CellPadding = UDim2.fromOffset(7, 8),
	FillDirectionMaxCells = 3,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, seedList)

--============================================================
-- DERECHA: DETALLE
--============================================================

local detail = create("Frame", {
	Name = "Detail",
	Position = UDim2.fromOffset(593, 92),
	Size = UDim2.new(1, -609, 0, 417),
	BackgroundColor3 = COLORS.cream,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 11,
}, panel)
corner(detail, 11)
stroke(detail, 3, COLORS.dark)

local detailTitle = create("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(10, 12),
	Size = UDim2.new(1, -20, 0, 48),
	Text = "Selecciona\nuna semilla",
	Font = FONT,
	TextScaled = true,
	TextWrapped = true,
	TextColor3 = COLORS.text,
	ZIndex = 12,
}, detail)
constraint(detailTitle, 16, 27)

local detailIconHolder = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 70),
	Size = UDim2.fromOffset(145, 126),
	BackgroundColor3 = Color3.fromRGB(215, 181, 133),
	BorderSizePixel = 0,
	ZIndex = 12,
}, detail)
corner(detailIconHolder, 10)
stroke(detailIconHolder, 2, COLORS.dark)

local detailBackground = create("ImageLabel", {
	Name = "SeedBackground",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Image = CULTIVO_BACKGROUND,
	ScaleType = Enum.ScaleType.Crop,
	ZIndex = 13,
}, detailIconHolder)
corner(detailBackground, 9)

local detailIcon = create("ImageLabel", {
	Name = "SeedIcon",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.72, 0.72),
	BackgroundTransparency = 1,
	Image = "",
	ScaleType = Enum.ScaleType.Fit,
	ZIndex = 14,
}, detailIconHolder)

local rarityLabel = create("TextLabel", {
	Position = UDim2.fromOffset(12, 207),
	Size = UDim2.new(1, -24, 0, 29),
	BackgroundColor3 = COLORS.common,
	BorderSizePixel = 0,
	Text = "—",
	Font = FONT,
	TextSize = 18,
	TextColor3 = COLORS.white,
	TextStrokeTransparency = 0.45,
	ZIndex = 12,
}, detail)
corner(rarityLabel, 7)
stroke(rarityLabel, 2, COLORS.dark)

local unitPriceLabel = create("TextLabel", {
	Position = UDim2.fromOffset(12, 244),
	Size = UDim2.new(1, -24, 0, 27),
	BackgroundTransparency = 1,
	Text = "Precio: —",
	Font = FONT,
	TextSize = 19,
	TextColor3 = COLORS.text,
	ZIndex = 12,
}, detail)

local quantityLabel = create("TextLabel", {
	Position = UDim2.fromOffset(12, 276),
	Size = UDim2.new(1, -82, 0, 20),
	BackgroundTransparency = 1,
	Text = "Cantidad",
	Font = FONT,
	TextSize = 16,
	TextColor3 = Color3.fromRGB(109, 73, 47),
	ZIndex = 12,
}, detail)

local maxSellButton = create("TextButton", {
	Name = "MaxSellButton",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 272),
	Size = UDim2.fromOffset(58, 25),
	BackgroundColor3 = COLORS.panel2,
	BorderSizePixel = 0,
	Text = "MAX",
	Font = FONT,
	TextSize = 14,
	TextColor3 = COLORS.white,
	AutoButtonColor = false,
	Visible = false,
	ZIndex = 13,
}, detail)
corner(maxSellButton, 7)
stroke(maxSellButton, 2, COLORS.dark)
animateButton(maxSellButton)

local minus = create("TextButton", {
	Position = UDim2.fromOffset(21, 302),
	Size = UDim2.fromOffset(44, 36),
	BackgroundColor3 = COLORS.panel2,
	BorderSizePixel = 0,
	Text = "−",
	Font = FONT,
	TextSize = 22,
	TextColor3 = COLORS.white,
	AutoButtonColor = false,
	ZIndex = 13,
}, detail)
corner(minus, 8)
stroke(minus, 2, COLORS.dark)
animateButton(minus)

local amountLabel = create("TextBox", {
	Name = "AmountBox",
	Position = UDim2.fromOffset(73, 302),
	Size = UDim2.new(1, -146, 0, 36),
	BackgroundColor3 = Color3.fromRGB(255, 245, 220),
	BorderSizePixel = 0,
	Text = "1",
	PlaceholderText = "1",
	ClearTextOnFocus = false,
	MultiLine = false,
	TextEditable = true,
	Font = FONT,
	TextSize = 20,
	TextColor3 = COLORS.text,
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 13,
}, detail)
corner(amountLabel, 8)
stroke(amountLabel, 2, COLORS.dark)

local plus = create("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -21, 0, 302),
	Size = UDim2.fromOffset(44, 36),
	BackgroundColor3 = COLORS.panel2,
	BorderSizePixel = 0,
	Text = "+",
	Font = FONT,
	TextSize = 22,
	TextColor3 = COLORS.white,
	AutoButtonColor = false,
	ZIndex = 13,
}, detail)
corner(plus, 8)
stroke(plus, 2, COLORS.dark)
animateButton(plus)

local totalLabel = create("TextLabel", {
	Position = UDim2.fromOffset(12, 343),
	Size = UDim2.new(1, -24, 0, 24),
	BackgroundTransparency = 1,
	Text = "Total: —",
	Font = FONT,
	TextSize = 19,
	TextColor3 = COLORS.text,
	ZIndex = 12,
}, detail)

local buyButton = create("TextButton", {
	Position = UDim2.fromOffset(12, 370),
	Size = UDim2.new(1, -24, 0, 38),
	BackgroundColor3 = COLORS.green,
	BorderSizePixel = 0,
	Text = "COMPRAR",
	Font = FONT,
	TextSize = 20,
	TextColor3 = COLORS.white,
	AutoButtonColor = false,
	ZIndex = 13,
}, detail)
corner(buyButton, 9)
stroke(buyButton, 2, COLORS.dark)
animateButton(buyButton)

--============================================================
-- TOAST
--============================================================

local toast = create("TextLabel", {
	Name = "PurchaseMessage",
	AnchorPoint = Vector2.new(0.5, 1),

	-- Abajo de la pantalla.
	Position = UDim2.new(0.5, 0, 0.94, 0),

	-- Más espacio para textos largos.
	Size = UDim2.new(0.72, 0, 0, 58),

	-- SIN fondo: solo se verá el texto.
	BackgroundTransparency = 1,
	BorderSizePixel = 0,

	Text = "",
	Font = FONT,
	TextSize = 25,
	TextScaled = false,
	TextWrapped = true,
	TextColor3 = Color3.fromRGB(246, 255, 235),

	-- Contorno para que se lea bien sobre cualquier fondo.
	TextStrokeColor3 = Color3.fromRGB(43, 62, 32),
	TextStrokeTransparency = 0.12,

	Visible = false,
	ZIndex = 100,
}, gui)

local toastSize = Instance.new("UITextSizeConstraint")
toastSize.MinTextSize = 20
toastSize.MaxTextSize = 30
toastSize.Parent = toast

local toastScale = Instance.new("UIScale")
toastScale.Name = "ToastScale"
toastScale.Scale = 1
toastScale.Parent = toast

local toastToken = 0

local function showToast(text, good)
	toastToken += 1
	local token = toastToken

	toast.Text = tostring(text or "")

	-- Compra correcta: texto claro/verde suave.
	-- Error: rojo suave.
	if good then
		toast.TextColor3 = Color3.fromRGB(225, 255, 190)
		toast.TextStrokeColor3 = Color3.fromRGB(47, 78, 34)
	else
		toast.TextColor3 = Color3.fromRGB(255, 210, 195)
		toast.TextStrokeColor3 = Color3.fromRGB(88, 34, 25)
	end

	toast.TextTransparency = 1
	toast.TextStrokeTransparency = 1
	toast.Visible = true

	-- Empieza un poco más abajo y sube suavemente.
	toast.Position = UDim2.new(0.5, 0, 0.955, 0)
	toastScale.Scale = 0.90

	TweenService:Create(
		toast,
		TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			TextTransparency = 0,
			TextStrokeTransparency = 0.12,
			Position = UDim2.new(0.5, 0, 0.93, 0),
		}
	):Play()

	TweenService:Create(
		toastScale,
		TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Scale = 1}
	):Play()

	task.delay(2.25, function()
		if token ~= toastToken then
			return
		end

		local tween = TweenService:Create(
			toast,
			TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{
				TextTransparency = 1,
				TextStrokeTransparency = 1,
				Position = UDim2.new(0.5, 0, 0.90, 0),
			}
		)

		TweenService:Create(
			toastScale,
			TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{Scale = 0.96}
		):Play()

		tween:Play()
		tween.Completed:Wait()

		if token == toastToken then
			toast.Visible = false
		end
	end)
end

--============================================================
-- LOGICA UI
--============================================================

local buyCatalog = {}
local sellCatalog = {}
local shopMode = "Buy"

local selected = nil
local quantity = 1
local currentFilter = "Todas"
local selectedCard = nil
local buying = false

local function currentCatalog()
	if shopMode == "Sell" then
		return sellCatalog
	end

	return buyCatalog
end

local function iconFor(entry)
	if
		typeof(entry.icon) == "string"
		and entry.icon ~= ""
	then
		return entry.icon
	end

	return ""
end

local function backgroundFor(entry)
	return
		backgroundForCrop(
			entry.crop
		)
end

local function formatRarity(rarity)
	if rarity == "Comun" then
		return "COMÚN"
	elseif rarity == "Raro" then
		return "RARO"
	elseif rarity == "Muy Raro" then
		return "MUY RARO"
	elseif rarity == "Epico" then
		return "ÉPICO"
	elseif rarity == "Legendario" then
		return "LEGENDARIO"
	end

	return "SIN RAREZA"
end

local function refreshModeVisuals()
	local buyingMode =
		shopMode == "Buy"

	buyModeButton.BackgroundColor3 =
		buyingMode
		and COLORS.green
		or COLORS.dark

	sellModeButton.BackgroundColor3 =
		not buyingMode
		and COLORS.green
		or COLORS.dark

	-- En COMPRAR solo existen:
	-- Todas, Comun, Raro y Muy Raro.
	-- Epico/Legendario siguen disponibles SOLO al vender.
	if filterButtons.Epico then
		filterButtons.Epico.Visible =
			not buyingMode
	end

	if filterButtons.Legendario then
		filterButtons.Legendario.Visible =
			not buyingMode
	end

	if
		buyingMode
		and (
			currentFilter == "Epico"
				or currentFilter == "Legendario"
		)
	then
		currentFilter =
			"Todas"
	end

	if buyingMode then
		subtitle.Text =
			"Julian • Compra semillas"
	else
		subtitle.Text =
			"Julian • Vende las semillas de tu mochila"
	end
end

local function refreshFilterVisuals()
	for filter, button in pairs(
		filterButtons
		) do
		if filter == currentFilter then
			button.BackgroundColor3 =
				COLORS.selected
		else
			button.BackgroundColor3 =
				COLORS.cream2
		end
	end
end

local function refreshDetail()
	local selling =
		shopMode == "Sell"

	if not selected then
		detail.Visible =
			false

		maxSellButton.Visible =
			false

		return
	end

	detail.Visible =
		true

	maxSellButton.Visible =
		selling

	if
		selling
		and selected.ownedCount
	then
		quantity =
			math.clamp(
				quantity,
				1,
				math.max(
					1,
					math.floor(
						tonumber(
							selected.ownedCount
						)
						or 1
					)
				)
			)
	else
		quantity =
			math.clamp(
				quantity,
				1,
				99
			)
	end

	detailTitle.Text =
		selected.display

	detailBackground.Image =
		backgroundFor(
			selected
		)

	detailIcon.Image =
		iconFor(
			selected
		)

	rarityLabel.Text =
		formatRarity(
			selected.rarity
		)

	rarityLabel.BackgroundColor3 =
		rarityColor(
			selected.rarity
		)

	local unitPrice =
		tonumber(
			selected.price
		)
		or 0

	if selling then
		unitPriceLabel.Text =
			"Venta: "
			.. tostring(
				unitPrice
			)
			.. "$ por unidad"

		quantityLabel.Text =
			"Tienes x"
			.. tostring(
				math.max(
					0,
					math.floor(
						tonumber(
							selected.ownedCount
						)
						or 0
					)
				)
			)

		totalLabel.Text =
			"Recibes: "
			.. tostring(
				unitPrice
				* quantity
			)
			.. "$"
	else
		unitPriceLabel.Text =
			tostring(
				unitPrice
			)
			.. "$ por unidad"

		quantityLabel.Text =
			"Cantidad"

		totalLabel.Text =
			"Total: "
			.. tostring(
				unitPrice
				* quantity
			)
			.. "$"
	end

	amountLabel.Text =
		tostring(
			quantity
		)

	if selected.available == false then
		buyButton.Text =
			selling
			and "SIN RAREZA"
			or "NO DISPONIBLE"

		buyButton.BackgroundColor3 =
			Color3.fromRGB(
				120,
				105,
				91
			)

		buyButton.Active =
			false
	elseif selling then
		local owned =
			math.max(
				0,
				math.floor(
					tonumber(
						selected.ownedCount
					)
					or 0
				)
			)

		local canSell =
			owned >= quantity
			and unitPrice > 0

		buyButton.Text =
			"VENDER x"
			.. tostring(
				quantity
			)

		buyButton.BackgroundColor3 =
			canSell
			and COLORS.green
			or Color3.fromRGB(
				120,
				105,
				91
			)

		buyButton.Active =
			canSell
	else
		buyButton.Text =
			"COMPRAR x"
			.. tostring(
				quantity
			)

		buyButton.BackgroundColor3 =
			COLORS.green

		buyButton.Active =
			true
	end
end

local function clearCards()
	for _, child in ipairs(
		seedList:GetChildren()
		) do
		if child:IsA(
			"GuiButton"
			) then
			child:Destroy()
		end
	end

	selectedCard =
		nil
end

local function selectEntry(
	entry,
	card
)
	selected =
		entry

	quantity =
		1

	if
		selectedCard
		and selectedCard.Parent
	then
		local oldStroke =
			selectedCard:FindFirstChild(
				"SelectedStroke"
			)

		if oldStroke then
			oldStroke:Destroy()
		end
	end

	selectedCard =
		card

	local selectionStroke =
		Instance.new(
			"UIStroke"
		)

	selectionStroke.Name =
		"SelectedStroke"

	selectionStroke.Color =
		COLORS.selected

	selectionStroke.Thickness =
		4

	selectionStroke.ApplyStrokeMode =
		Enum.ApplyStrokeMode.Border

	selectionStroke.Parent =
		card

	refreshDetail()
end

local function renderCatalog()
	clearCards()

	local catalog =
		currentCatalog()

	local selling =
		shopMode == "Sell"

	for _, entry in ipairs(
		catalog
		) do
		if
			currentFilter == "Todas"
			or entry.rarity
			== currentFilter
		then
			local card =
				create(
					"ImageButton",
					{
						Name =
						(
							selling
							and "SellSeed_"
							or "Seed_"
						)
						.. tostring(
							entry.sellKey
							or entry.crop
						),
						BackgroundColor3 =
						COLORS.cream,
						BorderSizePixel =
						0,
						Image =
						"",
						AutoButtonColor =
						false,
						LayoutOrder =
						entry.order
						or 0,
						ZIndex =
						13,
					},
					seedList
				)

			corner(
				card,
				9
			)

			stroke(
				card,
				2,
				COLORS.dark
			)

			animateButton(
				card
			)

			local iconBack =
				create(
					"Frame",
					{
						Position =
						UDim2.fromOffset(
							8,
							8
						),
						Size =
						UDim2.new(
							1,
							-16,
							0,
							78
						),
						BackgroundColor3 =
						Color3.fromRGB(
							214,
							178,
							128
						),
						BorderSizePixel =
						0,
						ClipsDescendants =
						true,
						ZIndex =
						14,
					},
					card
				)

			corner(
				iconBack,
				7
			)

			create(
				"ImageLabel",
				{
					Name =
						"SeedBackground",
					Size =
						UDim2.fromScale(
							1,
							1
						),
					BackgroundTransparency =
						1,
					Image =
						backgroundFor(
							entry
						),
					ScaleType =
						Enum.ScaleType.Crop,
					ImageTransparency =
						entry.available == false
						and 0.38
						or 0,
					ZIndex =
						15,
				},
				iconBack
			)

			create(
				"ImageLabel",
				{
					Name =
						"SeedIcon",
					AnchorPoint =
						Vector2.new(
							0.5,
							0.5
						),
					Position =
						UDim2.fromScale(
							0.5,
							0.5
						),
					Size =
						UDim2.fromScale(
							0.70,
							0.70
						),
					BackgroundTransparency =
						1,
					Image =
						iconFor(
							entry
						),
					ScaleType =
						Enum.ScaleType.Fit,
					ImageTransparency =
						entry.available == false
						and 0.55
						or 0,
					ZIndex =
						16,
				},
				iconBack
			)

			if selling then
				local ownedPill =
					create(
						"TextLabel",
						{
							AnchorPoint =
							Vector2.new(
								1,
								0
							),
							Position =
							UDim2.new(
								1,
								-4,
								0,
								4
							),
							Size =
							UDim2.fromOffset(
								48,
								21
							),
							BackgroundColor3 =
							COLORS.dark,
							BorderSizePixel =
							0,
							Text =
							"x"
							.. tostring(
								entry.ownedCount
								or 0
							),
							Font =
							FONT,
							TextSize =
							13,
							TextColor3 =
							COLORS.white,
							ZIndex =
							18,
						},
						iconBack
					)

				corner(
					ownedPill,
					6
				)
			end

			local nameLabel =
				create(
					"TextLabel",
					{
						Position =
						UDim2.fromOffset(
							7,
							89
						),
						Size =
						UDim2.new(
							1,
							-14,
							0,
							25
						),
						BackgroundTransparency =
						1,
						Text =
						entry.display,
						Font =
						FONT,
						TextScaled =
						true,
						TextWrapped =
						true,
						TextColor3 =
						COLORS.text,
						ZIndex =
						15,
					},
					card
				)

			constraint(
				nameLabel,
				11,
				17
			)

			local rarityPill =
				create(
					"TextLabel",
					{
						Position =
						UDim2.fromOffset(
							7,
							116
						),
						Size =
						UDim2.new(
							0.58,
							-8,
							0,
							20
						),
						BackgroundColor3 =
						rarityColor(
							entry.rarity
						),
						BorderSizePixel =
						0,
						Text =
						formatRarity(
							entry.rarity
						),
						Font =
						FONT,
						TextSize =
						11,
						TextColor3 =
						COLORS.white,
						TextStrokeTransparency =
						0.55,
						ZIndex =
						15,
					},
					card
				)

			corner(
				rarityPill,
				6
			)

			local pricePill =
				create(
					"TextLabel",
					{
						AnchorPoint =
						Vector2.new(
							1,
							0
						),
						Position =
						UDim2.new(
							1,
							-7,
							0,
							116
						),
						Size =
						UDim2.new(
							0.42,
							-2,
							0,
							20
						),
						BackgroundColor3 =
						COLORS.green,
						BorderSizePixel =
						0,
						Text =
						tostring(
							entry.price
							or 0
						)
						.. "$",
						Font =
						FONT,
						TextSize =
						13,
						TextColor3 =
						COLORS.white,
						ZIndex =
						15,
					},
					card
				)

			corner(
				pricePill,
				6
			)

			if entry.available == false then
				local missing =
					create(
						"TextLabel",
						{
							AnchorPoint =
							Vector2.new(
								0.5,
								0.5
							),
							Position =
							UDim2.fromScale(
								0.5,
								0.34
							),
							Size =
							UDim2.new(
								1,
								-12,
								0,
								25
							),
							BackgroundColor3 =
							COLORS.red,
							BackgroundTransparency =
							0.08,
							BorderSizePixel =
							0,
							Text =
							selling
							and "SIN RAREZA"
							or "FALTA TOOL",
							Font =
							FONT,
							TextSize =
							12,
							TextColor3 =
							COLORS.white,
							ZIndex =
							18,
						},
						card
					)

				corner(
					missing,
					6
				)
			end

			card.Activated:Connect(
				function()
					selectEntry(
						entry,
						card
					)
				end
			)
		end
	end
end

local function refreshShopDataFromServer()
	local ok, data =
		pcall(function()
			return GetCatalog:InvokeServer()
		end)

	if
		not ok
		or typeof(data) ~= "table"
	then
		return false
	end

	buyCatalog =
		typeof(data.items) == "table"
		and data.items
		or buyCatalog

	sellCatalog =
		typeof(data.sellItems) == "table"
		and data.sellItems
		or {}

	if data.money ~= nil then
		moneyLabel.Text =
			tostring(
				math.floor(
					tonumber(
						data.money
					)
					or 0
				)
			)
			.. "$"
	end

	return true
end

local function switchShopMode(
	newMode
)
	if
		newMode ~= "Buy"
		and newMode ~= "Sell"
	then
		return
	end

	-- MUY IMPORTANTE:
	-- al pasar a VENDER volvemos a consultar el servidor.
	-- Así aparece inmediatamente cualquier semilla que acabas de comprar.
	if newMode == "Sell" then
		refreshShopDataFromServer()
	end

	shopMode =
		newMode

	selected =
		nil

	selectedCard =
		nil

	quantity =
		1

	currentFilter =
		"Todas"

	refreshModeVisuals()
	refreshFilterVisuals()
	refreshDetail()
	renderCatalog()
end

buyModeButton.Activated:Connect(
	function()
		switchShopMode(
			"Buy"
		)
	end
)

sellModeButton.Activated:Connect(
	function()
		switchShopMode(
			"Sell"
		)
	end
)

for filter, button in pairs(
	filterButtons
	) do
	button.Activated:Connect(
		function()
			currentFilter =
				filter

			selected =
				nil

			quantity =
				1

			refreshFilterVisuals()
			refreshDetail()
			renderCatalog()
		end
	)
end

--============================================================
-- CANTIDAD ESCRIBIBLE CON TECLADO V4.3
--
-- FIX:
-- V4.2 llamaba refreshDetail() en CADA cambio de Text.
-- refreshDetail() volvía a escribir amountLabel.Text y podía
-- interrumpir la edición/foco del TextBox.
--
-- Ahora:
-- - mientras escribes, NO reconstruimos el TextBox
-- - solo limpiamos caracteres no numéricos
-- - actualizamos cantidad/total/botón sin tocar el foco
-- - Comprar: máximo x99
-- - Vender: máximo = TODO lo que tengas de esa semilla
--============================================================

local amountTextBusy = false

local function getMaxQuantityForSelection()
	local maxAmount = 99

	if
		shopMode == "Sell"
		and selected
	then
		local owned =
			math.max(
				0,
				math.floor(
					tonumber(
						selected.ownedCount
					)
					or 0
				)
			)

		if owned > 0 then
			maxAmount =
				owned
		else
			maxAmount =
				1
		end
	end

	return
		math.max(
			1,
			maxAmount
		)
end

local function updateTypedQuantityVisuals()
	if not selected then
		return
	end

	local selling =
		shopMode == "Sell"

	local unitPrice =
		tonumber(
			selected.price
		)
		or 0

	if selling then
		totalLabel.Text =
			"Recibes: "
			.. tostring(
				unitPrice
				* quantity
			)
			.. "$"

		local owned =
			math.max(
				0,
				math.floor(
					tonumber(
						selected.ownedCount
					)
					or 0
				)
			)

		local canSell =
			selected.available ~= false
			and owned >= quantity
			and unitPrice > 0

		buyButton.Text =
			"VENDER x"
			.. tostring(
				quantity
			)

		buyButton.BackgroundColor3 =
			canSell
			and COLORS.green
			or Color3.fromRGB(
				120,
				105,
				91
			)

		buyButton.Active =
			canSell
	else
		totalLabel.Text =
			"Total: "
			.. tostring(
				unitPrice
				* quantity
			)
			.. "$"

		buyButton.Text =
			"COMPRAR x"
			.. tostring(
				quantity
			)

		buyButton.Active =
			selected.available ~= false

		buyButton.BackgroundColor3 =
			buyButton.Active
			and COLORS.green
			or Color3.fromRGB(
				120,
				105,
				91
			)
	end
end

local function readTypedQuantity(
	finalize
)
	if amountTextBusy then
		return
	end

	local raw =
		tostring(
			amountLabel.Text
			or ""
		)

	-- Quitar letras/símbolos, sin perder el foco.
	local digits =
		raw:gsub(
			"%D",
			""
		)

	if digits ~= raw then
		amountTextBusy =
			true

		amountLabel.Text =
			digits

		amountTextBusy =
			false
	end

	-- Mientras escribe se permite vacío.
	if digits == "" then
		if finalize then
			quantity = 1

			amountTextBusy =
				true

			amountLabel.Text =
				"1"

			amountTextBusy =
				false

			updateTypedQuantityVisuals()
		end

		return
	end

	local value =
		math.floor(
			tonumber(
				digits
			)
			or 1
		)

	local maxAmount =
		getMaxQuantityForSelection()

	value =
		math.clamp(
			value,
			1,
			maxAmount
		)

	quantity =
		value

	-- Si escribió 999, visualmente convertirlo a 99.
	if
		tostring(value)
		~= digits
	then
		amountTextBusy =
			true

		amountLabel.Text =
			tostring(
				value
			)

		amountTextBusy =
			false
	end

	updateTypedQuantityVisuals()
end

-- Al hacer clic, seleccionar el número actual para poder
-- escribir "25" directamente sin tener que borrar el "1".
amountLabel.Focused:Connect(function()
	task.defer(function()
		if not amountLabel:IsFocused() then
			return
		end

		local length =
			#tostring(
				amountLabel.Text
				or ""
			)

		amountLabel.CursorPosition =
			length + 1

		amountLabel.SelectionStart =
			1
	end)
end)

-- Mientras escribe: NO llamar refreshDetail().
amountLabel:GetPropertyChangedSignal(
	"Text"
):Connect(function()
	if amountTextBusy then
		return
	end

	readTypedQuantity(
		false
	)
end)

-- Enter o clic fuera confirma el valor final.
amountLabel.FocusLost:Connect(function()
	readTypedQuantity(
		true
	)
end)

minus.Activated:Connect(function()
	if not selected then
		return
	end

	quantity =
		math.max(
			1,
			quantity - 1
		)

	refreshDetail()
end)

plus.Activated:Connect(function()
	if not selected then
		return
	end

	quantity =
		math.min(
			getMaxQuantityForSelection(),
			quantity + 1
		)

	refreshDetail()
end)

maxSellButton.Activated:Connect(function()
	if
		not selected
		or shopMode ~= "Sell"
	then
		return
	end

	quantity =
		getMaxQuantityForSelection()

	amountTextBusy =
		true

	amountLabel.Text =
		tostring(
			quantity
		)

	amountTextBusy =
		false

	updateTypedQuantityVisuals()
end)

buyButton.Activated:Connect(function()
	readTypedQuantity(
		true
	)

	if
		buying
		or not selected
		or not buyButton.Active
	then
		return
	end

	local selling =
		shopMode == "Sell"

	if selected.available == false then
		showToast(
			selling
				and "Esta semilla no tiene rareza configurada."
				or "Falta el Tool de esta semilla en ServerStorage > Item > Semillas.",
			false
		)

		return
	end

	buying =
		true

	buyButton.Text =
		selling
		and "VENDIENDO..."
		or "COMPRANDO..."

	task.spawn(function()
		local ok, result =
			pcall(function()
				if selling then
					return SellSeed:InvokeServer(
						selected.sellKey,
						quantity
					)
				end

				return BuySeed:InvokeServer(
					selected.crop,
					quantity
				)
			end)

		buying =
			false

		if
			ok
			and typeof(result)
			== "table"
		then
			if result.money ~= nil then
				moneyLabel.Text =
					tostring(
						result.money
					)
					.. "$"
			end

			if
				not selling
				and result.ok == true
			then
				-- Actualizar inventario de venta después de comprar.
				refreshShopDataFromServer()
			end

			if
				selling
				and result.ok == true
			then
				selected.ownedCount =
					math.max(
						0,
						math.floor(
							tonumber(
								result.ownedCount
							)
							or 0
						)
					)

				if
					selected.ownedCount
					<= 0
				then
					for index = #sellCatalog, 1, -1 do
						if
							sellCatalog[index].sellKey
							== selected.sellKey
						then
							table.remove(
								sellCatalog,
								index
							)

							break
						end
					end

					selected =
						nil

					selectedCard =
						nil

					quantity =
						1
				else
					quantity =
						math.min(
							quantity,
							selected.ownedCount
						)
				end

				renderCatalog()
			end

			showToast(
				result.message
					or (
						result.ok
						and (
							selling
							and "Venta realizada."
							or "Compra realizada."
						)
						or (
							selling
							and "No se pudo vender."
							or "No se pudo comprar."
						)
					),
				result.ok == true
			)
		else
			showToast(
				"No se pudo conectar con la tienda.",
				false
			)
		end

		refreshDetail()
	end)
end)

--============================================================
-- ABRIR / CERRAR
--============================================================

local function closeShop()
	if not gui.Enabled then
		return
	end

	local tween = TweenService:Create(
		panelScale,
		TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{Scale = math.max(0.01, panelScale.Scale * 0.94)}
	)
	tween:Play()

	local fade = TweenService:Create(
		dim,
		TweenInfo.new(0.14),
		{BackgroundTransparency = 1}
	)
	fade:Play()

	tween.Completed:Wait()
	gui.Enabled = false
	updateResponsiveScale()
end

local function openShop()
	local ok, data = pcall(function()
		return GetCatalog:InvokeServer()
	end)

	if not ok or typeof(data) ~= "table" then
		showToast("No se pudo cargar la tienda de Julian.", false)
		return
	end

	buyCatalog =
		typeof(data.items) == "table"
		and data.items
		or {}

	sellCatalog =
		typeof(data.sellItems) == "table"
		and data.sellItems
		or {}

	moneyLabel.Text =
		tostring(
			math.floor(
				tonumber(
					data.money
				)
				or 0
			)
		)
		.. "$"

	shopMode = "Buy"
	selected = nil
	selectedCard = nil
	quantity = 1
	currentFilter = "Todas"

	refreshModeVisuals()
	refreshFilterVisuals()
	refreshDetail()
	renderCatalog()

	gui.Enabled = true
	dim.BackgroundTransparency = 1

	updateResponsiveScale()
	local targetScale = panelScale.Scale
	panelScale.Scale = targetScale * 0.86

	TweenService:Create(
		dim,
		TweenInfo.new(0.18),
		{BackgroundTransparency = 0.42}
	):Play()

	TweenService:Create(
		panelScale,
		TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Scale = targetScale}
	):Play()
end

closeButton.Activated:Connect(closeShop)

OpenShop.OnClientEvent:Connect(openShop)