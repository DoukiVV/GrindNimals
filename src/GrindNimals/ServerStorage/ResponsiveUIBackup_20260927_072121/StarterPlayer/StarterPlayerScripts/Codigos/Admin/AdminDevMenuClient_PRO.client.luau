-- AdminDevMenuClient_PRO_V3_2_REMOTE_UNICO_FRUTA_X99.lua
-- Ubicacion:
-- StarterPlayer > StarterPlayerScripts > AdminDevMenuClient_PRO (LocalScript)
--
-- El menu inicia CERRADO.
-- Escribe /admin para abrirlo/cerrarlo.
-- Solo los UserId autorizados cargan el menu.
--
-- Incluye:
--  * Dolares
--  * Nivel
--  * Frutas/cultivos
--  * Obtener mascotas por tier
--  * Dar + equipar mascota
--  * Dar todos los tiers/panuelos
--  * Quitar mascota/tier
--  * Dar materiales para la siguiente mejora
--  * Animaciones de mascota
--  * Velocidad de animacion
--  * Vuelo
--  * Trade test

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextChatService = game:GetService("TextChatService")

local player = Players.LocalPlayer

--==============================================================
-- ADMINS AUTORIZADOS
--==============================================================

local ADMIN_USER_IDS = {
	[2763635937] = true,
	[1075477843] = true,
	[11621988902] = true,
	[2567510148] = true,
}

if ADMIN_USER_IDS[player.UserId] ~= true then
	return
end

--==============================================================
-- REFERENCIAS
--==============================================================

local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local PetConfigs = require(ReplicatedStorage:WaitForChild("PetConfigs"))
local EquipPet = ReplicatedStorage:WaitForChild("EquipPet")
local BackpackQuickSlotEvent = ReplicatedStorage:WaitForChild("BackpackQuickSlotEvent")

local AdminDevAction = ReplicatedStorage:WaitForChild("AdminDevAction", 20)
local AdminInventoryAction = ReplicatedStorage:WaitForChild("AdminInventoryActionV2", 20)
local AdminSetDollars = ReplicatedStorage:FindFirstChild("AdminSetDollars")
local AdminSetLevel = ReplicatedStorage:FindFirstChild("AdminSetLevel")
local AdminAddLevel = ReplicatedStorage:FindFirstChild("AdminAddLevel")

--==============================================================
-- MASCOTAS / TIERS
--==============================================================

local PETS = {
	"Oveja",
	"Huron",
	"Pez dorado",
	"Hamster",
	"Perico",
	"Tortuga",
	"Perro",
	"Gato",
	"Conejo",
}

local TIERS = {
	"Base",
	"Comun",
	"Poco comun",
	"Raro",
	"Epico",
	"Legendario",
}

local ANIMS = {
	"Walk",
	"Fly",
	"AFK",
	"AFK2",
	"Jump",
	"Eat",
	"Dig",
	"Celebrate",
}

--==============================================================
-- COLORES
--==============================================================

local C = {
	BG = Color3.fromRGB(15,18,23),
	PANEL = Color3.fromRGB(23,27,34),
	CARD = Color3.fromRGB(30,35,43),
	CARD2 = Color3.fromRGB(38,44,54),
	STROKE = Color3.fromRGB(66,77,92),
	BLUE = Color3.fromRGB(45,137,245),
	GREEN = Color3.fromRGB(55,171,91),
	RED = Color3.fromRGB(202,76,84),
	ORANGE = Color3.fromRGB(209,139,62),
	PURPLE = Color3.fromRGB(143,92,220),
	TEXT = Color3.fromRGB(245,248,255),
	SUB = Color3.fromRGB(165,177,193),
}

--==============================================================
-- UI HELPERS
--==============================================================

local function corner(object, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 7)
	c.Parent = object
	return c
end

local function stroke(object, color)
	local s = Instance.new("UIStroke")
	s.Color = color or C.STROKE
	s.Thickness = 1
	s.Transparency = 0.25
	s.Parent = object
	return s
end

local function pad(object, left, right, top, bottom)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, left or 0)
	p.PaddingRight = UDim.new(0, right or left or 0)
	p.PaddingTop = UDim.new(0, top or 0)
	p.PaddingBottom = UDim.new(0, bottom or top or 0)
	p.Parent = object
	return p
end

local function label(parent, text, height, bold)
	local object = Instance.new("TextLabel")
	object.BackgroundTransparency = 1
	object.Size = UDim2.new(1, 0, 0, height or 22)
	object.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	object.Text = text or ""
	object.TextColor3 = C.TEXT
	object.TextSize = bold and 14 or 13
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.Parent = parent
	return object
end

local function button(parent, text, color, height)
	local object = Instance.new("TextButton")
	object.AutoButtonColor = false
	object.BackgroundColor3 = color or C.CARD2
	object.BorderSizePixel = 0
	object.Size = UDim2.new(1, 0, 0, height or 34)
	object.Font = Enum.Font.GothamBold
	object.Text = text or "Boton"
	object.TextColor3 = C.TEXT
	object.TextSize = 13
	object.Parent = parent

	corner(object, 7)
	stroke(object)

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = object

	object.MouseEnter:Connect(function()
		if not object.Active then
			return
		end
		TweenService:Create(
			scale,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Scale = 1.02}
		):Play()
	end)

	object.MouseLeave:Connect(function()
		TweenService:Create(
			scale,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Scale = 1}
		):Play()
	end)

	object.MouseButton1Down:Connect(function()
		TweenService:Create(
			scale,
			TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Scale = 0.97}
		):Play()
	end)

	object.MouseButton1Up:Connect(function()
		TweenService:Create(
			scale,
			TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Scale = 1.02}
		):Play()
	end)

	return object
end

local function input(parent, placeholder, text)
	local object = Instance.new("TextBox")
	object.ClearTextOnFocus = false
	object.BackgroundColor3 = C.CARD2
	object.BorderSizePixel = 0
	object.Size = UDim2.new(1, 0, 0, 34)
	object.Font = Enum.Font.Gotham
	object.PlaceholderText = placeholder or ""
	object.PlaceholderColor3 = C.SUB
	object.Text = text or ""
	object.TextColor3 = C.TEXT
	object.TextSize = 13
	object.Parent = parent

	corner(object, 7)
	stroke(object)

	return object
end

local function section(parent, titleText)
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = C.CARD
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, 10)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Parent = parent

	corner(frame, 9)
	stroke(frame)
	pad(frame, 12, 12, 10, 12)

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	label(frame, titleText, 20, true)

	return frame
end

local function digits(box)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local value = tostring(box.Text):gsub("[^%d]", "")
		if box.Text ~= value then
			box.Text = value
		end
	end)
end

--==============================================================
-- REMOTES
--==============================================================

local function invoke(remote, ...)
	if not remote or not remote:IsA("RemoteFunction") then
		return false, "Remote no disponible."
	end

	local args = table.pack(...)

	local ok, a, b, c = pcall(function()
		return remote:InvokeServer(
			table.unpack(args, 1, args.n)
		)
	end)

	if not ok then
		return false, "Error al invocar Remote."
	end

	return a, b, c
end

local function callDev(action, data)
	if not AdminDevAction or not AdminDevAction:IsA("RemoteFunction") then
		return false, "AdminDevAction no existe."
	end

	local ok, success, message = pcall(function()
		return AdminDevAction:InvokeServer(
			action,
			data or {}
		)
	end)

	if not ok then
		return false, "Error al usar AdminDevAction."
	end

	return success, message
end

--==============================================================
-- SINCRONIZAR MASCOTA CON SLOT RAPIDO 2
--==============================================================

local function syncPetToQuickSlot2(petName, tier)
	petName = tostring(petName or player:GetAttribute("SelectedBackpackPet") or "")
	tier = tostring(tier or player:GetAttribute("SelectedBackpackPetTier") or "Base")

	if petName == "" then
		return
	end

	BackpackQuickSlotEvent:Fire(2, {
		kind = "Pet",
		name = petName,
		tier = tier,
	})

	for _, delayTime in ipairs({0.05, 0.15, 0.35}) do
		task.delay(delayTime, function()
			if BackpackQuickSlotEvent.Parent then
				BackpackQuickSlotEvent:Fire(2, {
					kind = "Pet",
					name = petName,
					tier = tier,
				})
			end
		end)
	end
end

--==============================================================
-- GUI PRINCIPAL
--==============================================================

local oldGui = playerGui:FindFirstChild("AdminDevMenu")
if oldGui then
	oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "AdminDevMenu"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(900, 610)
panel.BackgroundColor3 = C.BG
panel.BorderSizePixel = 0
panel.Parent = gui

corner(panel, 12)
stroke(panel, C.BLUE)

local top = Instance.new("Frame")
top.Name = "Top"
top.Size = UDim2.new(1, 0, 0, 52)
top.BackgroundColor3 = C.PANEL
top.BorderSizePixel = 0
top.Parent = panel
corner(top, 12)

local title = label(top, "ADMIN DEV TOOLS", 52, true)
title.Position = UDim2.fromOffset(16, 0)
title.Size = UDim2.new(1, -120, 1, 0)
title.TextSize = 18

local close = button(top, "X", C.CARD2, 30)
close.AnchorPoint = Vector2.new(1, 0.5)
close.Position = UDim2.new(1, -12, 0.5, 0)
close.Size = UDim2.fromOffset(32, 30)

local side = Instance.new("Frame")
side.Name = "Side"
side.Position = UDim2.fromOffset(0, 52)
side.Size = UDim2.new(0, 165, 1, -52)
side.BackgroundColor3 = C.PANEL
side.BorderSizePixel = 0
side.Parent = panel

pad(side, 10, 10, 12, 12)

local sideLayout = Instance.new("UIListLayout")
sideLayout.Padding = UDim.new(0, 7)
sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
sideLayout.Parent = side

local content = Instance.new("Frame")
content.Name = "Content"
content.Position = UDim2.fromOffset(165, 52)
content.Size = UDim2.new(1, -165, 1, -52)
content.BackgroundTransparency = 1
content.ClipsDescendants = true
content.Parent = panel

local pages = {}
local tabs = {}

local pageNames = {
	"Jugador",
	"Inventario",
	"Mascota",
	"Movimiento",
	"Pruebas",
}

for _, name in ipairs(pageNames) do
	local tab = button(side, name, C.CARD, 38)
	tab.TextXAlignment = Enum.TextXAlignment.Left
	pad(tab, 12, 4, 0, 0)

	tabs[name] = tab

	local page = Instance.new("ScrollingFrame")
	page.Name = name .. "Page"
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 6
	page.ScrollBarImageColor3 = C.BLUE
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.CanvasSize = UDim2.new()
	page.Visible = false
	page.Parent = content

	pad(page, 16, 16, 16, 42)

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 12)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = page

	pages[name] = page
end

local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0, 1)
status.Position = UDim2.new(0, 177, 1, -10)
status.Size = UDim2.new(1, -191, 0, 24)
status.BackgroundColor3 = C.CARD
status.BorderSizePixel = 0
status.Font = Enum.Font.Gotham
status.Text = "Listo"
status.TextColor3 = C.SUB
status.TextSize = 12
status.TextXAlignment = Enum.TextXAlignment.Left
status.ZIndex = 20
status.Parent = panel

pad(status, 9, 9, 0, 0)
corner(status, 6)

local function setStatus(text, color)
	status.Text = tostring(text or "")
	status.TextColor3 = color or C.SUB
end

local function setTab(name)
	for tabName, page in pairs(pages) do
		page.Visible = tabName == name
	end

	for tabName, tab in pairs(tabs) do
		tab.BackgroundColor3 =
			tabName == name and C.BLUE or C.CARD

		tab.TextColor3 =
			tabName == name and C.TEXT or C.SUB
	end
end

for name, tab in pairs(tabs) do
	tab.Activated:Connect(function()
		setTab(name)
	end)
end

--==============================================================
-- PAGINA: JUGADOR
--==============================================================

do
	local page = pages.Jugador

	local dollars = section(page, "Dolares")

	local dollarsBox = input(
		dollars,
		"Cantidad",
		""
	)
	digits(dollarsBox)

	local setDollars = button(
		dollars,
		"Poner dolares",
		C.BLUE,
		36
	)

	setDollars.Activated:Connect(function()
		local amount = tonumber(dollarsBox.Text)

		if not amount then
			setStatus(
				"Cantidad invalida",
				C.RED
			)
			return
		end

		local ok, message, value =
			invoke(
				AdminSetDollars,
				amount
			)

		if ok then
			setStatus(
				"Dolares: "
					.. tostring(value)
					.. "$",
				C.GREEN
			)
		else
			setStatus(
				message or "Error",
				C.RED
			)
		end
	end)

	local levelSection = section(
		page,
		"Nivel"
	)

	local levelBox = input(
		levelSection,
		"Nivel / cantidad",
		""
	)
	digits(levelBox)

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 34)
	row.Parent = levelSection

	local addLevel = button(
		row,
		"Subir",
		C.GREEN,
		34
	)
	addLevel.Size =
		UDim2.new(0.48, 0, 1, 0)

	local setLevel = button(
		row,
		"Poner",
		C.BLUE,
		34
	)

	setLevel.AnchorPoint =
		Vector2.new(1, 0)

	setLevel.Position =
		UDim2.new(1, 0, 0, 0)

	setLevel.Size =
		UDim2.new(0.48, 0, 1, 0)

	local function levelAction(remote)
		local amount =
			tonumber(levelBox.Text)

		if not amount then
			setStatus(
				"Nivel invalido",
				C.RED
			)
			return
		end

		local ok, message, value =
			invoke(
				remote,
				amount
			)

		if ok then
			setStatus(
				"Nivel: "
					.. tostring(value),
				C.GREEN
			)
		else
			setStatus(
				message or "Error",
				C.RED
			)
		end
	end

	addLevel.Activated:Connect(function()
		levelAction(AdminAddLevel)
	end)

	setLevel.Activated:Connect(function()
		levelAction(AdminSetLevel)
	end)
end

--==============================================================
-- PAGINA: INVENTARIO
-- V3: SEMILLAS Y FRUTAS TOTALMENTE SEPARADAS
--
-- Ya NO escribes nombres ni cantidades.
-- 1) Eliges cantidad con un botón.
-- 2) Presionas directamente la semilla o fruta.
--
-- IMPORTANTE:
-- - Semillas -> ServerStorage > Item > Semillas
-- - Frutas   -> ServerStorage > Item > Frutas
-- El servidor valida la carpeta exacta, así nunca confunde una fruta
-- con una semilla aunque tengan nombres parecidos.
--==============================================================

do
	local page = pages.Inventario
	local selectedAmount = 30
	local amountButtons = {}

	--==========================================================
	-- CANTIDAD
	--==========================================================
	local amountSection =
		section(
			page,
			"Cantidad a entregar"
		)

	local amountRow = Instance.new("Frame")
	amountRow.BackgroundTransparency = 1
	amountRow.Size = UDim2.new(1, 0, 0, 34)
	amountRow.Parent = amountSection

	local amounts = {1, 10, 30, 99}

	local function refreshAmountButtons()
		for amount, amountButton in pairs(amountButtons) do
			amountButton.BackgroundColor3 =
				amount == selectedAmount
				and C.BLUE
				or C.CARD2
		end
	end

	for index, amount in ipairs(amounts) do
		-- V3.1: captura independiente por boton.
		-- Evita cualquier problema de closure con el valor del for.
		local chosenAmount = amount

		local amountButton =
			button(
				amountRow,
				"x" .. tostring(chosenAmount),
				C.CARD2,
				34
			)

		amountButton.Size =
			UDim2.new(
				0.235,
				0,
				1,
				0
			)

		amountButton.Position =
			UDim2.new(
				(index - 1) * 0.255,
				0,
				0,
				0
			)

		amountButtons[chosenAmount] = amountButton

		amountButton.Activated:Connect(function()
			selectedAmount = chosenAmount
			refreshAmountButtons()

			setStatus(
				"Cantidad seleccionada: x"
					.. tostring(selectedAmount),
				C.BLUE
			)
		end)
	end

	refreshAmountButtons()

	--==========================================================
	-- CATALOGO DESDE EL SERVIDOR
	--==========================================================
	local catalogOk, catalogMessage, catalog =
		invoke(
			AdminInventoryAction,
			"GetCatalogs"
		)

	if not catalogOk
		or typeof(catalog) ~= "table"
	then
		setStatus(
			catalogMessage
				or "No se pudo cargar semillas/frutas.",
			C.RED
		)

		catalog = {
			seeds = {},
			fruits = {},
		}
	end

	--==========================================================
	-- CREA BOTONES EN 2 COLUMNAS
	--==========================================================
	local function addCatalogButtons(
		parentSection,
		entries,
		actionName,
		itemKind,
		buttonColor
	)
		if #entries == 0 then
			local empty =
				label(
					parentSection,
					"No hay "
					.. itemKind:lower()
					.. " en ServerStorage.",
					24,
					false
				)

			empty.TextColor3 = C.SUB
			return
		end

		local index = 1

		while index <= #entries do
			local row = Instance.new("Frame")
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, 0, 0, 34)
			row.Parent = parentSection

			for column = 1, 2 do
				local entry = entries[index]

				if not entry then
					break
				end

				local itemButton =
					button(
						row,
						tostring(entry.display),
						buttonColor,
						34
					)

				itemButton.TextSize = 11
				itemButton.TextWrapped = true

				itemButton.Size =
					UDim2.new(
						0.485,
						0,
						1,
						0
					)

				if column == 2 then
					itemButton.AnchorPoint =
						Vector2.new(1, 0)

					itemButton.Position =
						UDim2.new(1, 0, 0, 0)
				end

				local capturedEntry = entry

				itemButton.Activated:Connect(function()
					local ok, message, data =
						invoke(
							AdminInventoryAction,
							actionName,
							{
								name =
								capturedEntry.key,
								amount =
								selectedAmount,
							}
						)

					if ok then
						setStatus(
							"+"
								.. tostring(
									(data and data.amount)
									or selectedAmount
								)
								.. " "
								.. itemKind
								.. ": "
								.. tostring(
									(data and data.display)
									or capturedEntry.display
								),
							C.GREEN
						)
					else
						setStatus(
							message or "Error",
							C.RED
						)
					end
				end)

				index += 1
			end
		end
	end

	--==========================================================
	-- SEMILLAS
	--==========================================================
	local seedSection =
		section(
			page,
			"SEMILLAS - solo da semillas"
		)

	local seedHint =
		label(
			seedSection,
			"Presiona una semilla para recibirla.",
			20,
			false
		)

	seedHint.TextColor3 = C.SUB

	addCatalogButtons(
		seedSection,
		catalog.seeds or {},
		"GiveSeed",
		"Semilla",
		C.GREEN
	)

	--==========================================================
	-- FRUTAS
	--==========================================================
	local fruitSection =
		section(
			page,
			"FRUTAS - solo da frutas"
		)

	local fruitHint =
		label(
			fruitSection,
			"Presiona una fruta para recibirla.",
			20,
			false
		)

	fruitHint.TextColor3 = C.SUB

	addCatalogButtons(
		fruitSection,
		catalog.fruits or {},
		"GiveFruit",
		"Fruta",
		C.ORANGE
	)
end

--==============================================================
-- PAGINA: MASCOTA
--==============================================================

local animButtons = {}
local speedButtons = {}
local petLabel = nil

local function petType()
	for _, object in ipairs(
		workspace:GetChildren()
		) do
		if object:IsA("Model")
			and object:GetAttribute("Owner")
			== player.UserId
			and object:GetAttribute(
				"ClientPetVisual"
			) ~= true
		then
			local petName =
				object:GetAttribute(
					"PetType"
				)

			if typeof(petName)
				== "string"
			then
				return petName
			end
		end
	end

	return nil
end

local function refreshPet()
	if not petLabel then
		return
	end

	local currentPet = petType()

	local config =
		currentPet
		and PetConfigs[currentPet]

	local active =
		player:GetAttribute(
			"AdminPetAnimationOverride"
		)

	local animationSpeed =
		player:GetAttribute(
			"AdminPetAnimationSpeed"
		)

	if typeof(animationSpeed)
		~= "number"
	then
		animationSpeed = 1
	end

	petLabel.Text =
		currentPet
		and (
			"Mascota: "
			.. currentPet
		)
		or "Mascota: ninguna"

	for animationName, animButton
		in pairs(animButtons)
	do
		local available =
			config
			and typeof(
				config[animationName]
			) == "string"

		animButton.Active =
			available == true

		animButton.TextTransparency =
			available and 0 or 0.55

		animButton.BackgroundColor3 =
			(active == animationName and C.BLUE)
			or (
				available
				and C.CARD2
				or C.CARD
			)
	end

	for multiplier, speedButton
		in pairs(speedButtons)
	do
		speedButton.BackgroundColor3 =
			math.abs(
				animationSpeed
				- multiplier
			) < 0.01
			and C.BLUE
			or C.CARD2
	end
end

do
	local page = pages.Mascota

	--==========================================================
	-- OBTENER MASCOTAS
	--==========================================================

	local petIndex = 1
	local tierIndex = 1

	local function selectedPet()
		return PETS[petIndex]
	end

	local function selectedTier()
		return TIERS[tierIndex]
	end

	local obtain =
		section(
			page,
			"Obtener mascotas"
		)

	-- Selector mascota
	local petRow = Instance.new("Frame")
	petRow.BackgroundTransparency = 1
	petRow.Size = UDim2.new(1, 0, 0, 36)
	petRow.Parent = obtain

	local petPrev =
		button(
			petRow,
			"<",
			C.CARD2,
			36
		)
	petPrev.Size =
		UDim2.fromOffset(42, 36)

	local petSelected =
		label(
			petRow,
			"",
			36,
			true
		)

	petSelected.Position =
		UDim2.fromOffset(50, 0)

	petSelected.Size =
		UDim2.new(1, -100, 0, 36)

	petSelected.TextXAlignment =
		Enum.TextXAlignment.Center

	local petNext =
		button(
			petRow,
			">",
			C.CARD2,
			36
		)

	petNext.AnchorPoint =
		Vector2.new(1, 0)

	petNext.Position =
		UDim2.new(1, 0, 0, 0)

	petNext.Size =
		UDim2.fromOffset(42, 36)

	-- Selector tier
	local tierRow = Instance.new("Frame")
	tierRow.BackgroundTransparency = 1
	tierRow.Size = UDim2.new(1, 0, 0, 36)
	tierRow.Parent = obtain

	local tierPrev =
		button(
			tierRow,
			"<",
			C.CARD2,
			36
		)

	tierPrev.Size =
		UDim2.fromOffset(42, 36)

	local tierSelected =
		label(
			tierRow,
			"",
			36,
			true
		)

	tierSelected.Position =
		UDim2.fromOffset(50, 0)

	tierSelected.Size =
		UDim2.new(1, -100, 0, 36)

	tierSelected.TextXAlignment =
		Enum.TextXAlignment.Center

	local tierNext =
		button(
			tierRow,
			">",
			C.CARD2,
			36
		)

	tierNext.AnchorPoint =
		Vector2.new(1, 0)

	tierNext.Position =
		UDim2.new(1, 0, 0, 0)

	tierNext.Size =
		UDim2.fromOffset(42, 36)

	local function refreshSelectors()
		petSelected.Text =
			"Mascota: "
			.. selectedPet()

		tierSelected.Text =
			"Tier: "
			.. selectedTier()
	end

	petPrev.Activated:Connect(function()
		petIndex = petIndex - 1

		if petIndex < 1 then
			petIndex = #PETS
		end

		refreshSelectors()
	end)

	petNext.Activated:Connect(function()
		petIndex = petIndex + 1

		if petIndex > #PETS then
			petIndex = 1
		end

		refreshSelectors()
	end)

	tierPrev.Activated:Connect(function()
		tierIndex = tierIndex - 1

		if tierIndex < 1 then
			tierIndex = #TIERS
		end

		refreshSelectors()
	end)

	tierNext.Activated:Connect(function()
		tierIndex = tierIndex + 1

		if tierIndex > #TIERS then
			tierIndex = 1
		end

		refreshSelectors()
	end)

	-- Botones de mascotas

	local give =
		button(
			obtain,
			"Dar mascota / tier",
			C.GREEN,
			36
		)

	local giveEquip =
		button(
			obtain,
			"Dar + equipar ahora",
			C.BLUE,
			36
		)

	local giveAll =
		button(
			obtain,
			"Dar todos los panuelos",
			C.PURPLE,
			36
		)

	local remove =
		button(
			obtain,
			"Quitar 1 de este tier",
			C.RED,
			34
		)

	local kit =
		button(
			obtain,
			"Dar materiales para SIGUIENTE mejora",
			C.ORANGE,
			36
		)

	give.Activated:Connect(function()
		local ok, message =
			callDev(
				"GivePet",
				{
					petName = selectedPet(),
					tier = selectedTier(),
					amount = 1,
				}
			)

		setStatus(
			message or "Mascota agregada",
			ok and C.GREEN or C.RED
		)
	end)

	giveEquip.Activated:Connect(function()
		local petName =
			selectedPet()

		local tier =
			selectedTier()

		local ok, message =
			callDev(
				"GivePet",
				{
					petName = petName,
					tier = tier,
					amount = 1,
				}
			)

		if not ok then
			setStatus(
				message
					or "No se pudo dar la mascota",
				C.RED
			)
			return
		end

		local selectedOk,
		selectedMessage =
			callDev(
				"SelectPet",
				{
					petName = petName,
					tier = tier,
				}
			)

		if not selectedOk then
			setStatus(
				selectedMessage
					or "No se pudo seleccionar",
				C.RED
			)
			return
		end

		player:SetAttribute(
			"SelectedBackpackPet",
			petName
		)

		player:SetAttribute(
			"SelectedBackpackPetTier",
			tier
		)

		EquipPet:FireServer(
			petName,
			tier
		)

		syncPetToQuickSlot2(
			petName,
			tier
		)

		setStatus(
			"Equipada: "
				.. petName
				.. " ["
				.. tier
				.. "]",
			C.GREEN
		)
	end)

	giveAll.Activated:Connect(function()
		local ok, message =
			callDev(
				"GiveAllTiers",
				{
					petName =
					selectedPet(),
				}
			)

		setStatus(
			message
				or "Todos los tiers agregados",
			ok and C.GREEN or C.RED
		)
	end)

	remove.Activated:Connect(function()
		local ok, message =
			callDev(
				"RemovePet",
				{
					petName =
					selectedPet(),

					tier =
					selectedTier(),

					amount = 1,
				}
			)

		setStatus(
			message
				or "Mascota eliminada",
			ok and C.GREEN or C.RED
		)
	end)

	kit.Activated:Connect(function()
		local ok, message =
			callDev(
				"GiveUpgradeKit",
				{
					petName =
					selectedPet(),

					tier =
					selectedTier(),
				}
			)

		setStatus(
			message
				or "Materiales entregados",
			ok and C.GREEN or C.RED
		)
	end)

	refreshSelectors()

	--==========================================================
	-- MASCOTA ACTUAL / ANIMACIONES
	--==========================================================

	local current =
		section(
			page,
			"Mascota actual"
		)

	petLabel =
		label(
			current,
			"Mascota: ninguna",
			22,
			false
		)

	petLabel.TextColor3 = C.SUB

	local normal =
		button(
			current,
			"Modo normal",
			C.BLUE,
			34
		)

	normal.Activated:Connect(function()
		player:SetAttribute(
			"AdminPetAnimationOverride",
			""
		)

		refreshPet()
	end)

	local animations =
		section(
			page,
			"Animaciones"
		)

	for _, animationName
		in ipairs(ANIMS)
	do
		local animButton =
			button(
				animations,
				animationName,
				C.CARD2,
				30
			)

		animButtons[animationName] =
			animButton

		animButton.Activated:Connect(
			function()
				local currentPet =
					petType()

				local config =
					currentPet
					and PetConfigs[currentPet]

				if config
					and typeof(
						config[
						animationName
						]
					) == "string"
				then
					local currentOverride =
						player:GetAttribute(
							"AdminPetAnimationOverride"
						)

					player:SetAttribute(
						"AdminPetAnimationOverride",
						currentOverride
							== animationName
							and ""
							or animationName
					)

					refreshPet()
				end
			end
		)
	end

	local speedSection =
		section(
			page,
			"Velocidad animacion"
		)

	for _, multiplier in ipairs({
		0,
		0.5,
		1,
		1.5,
		2,
		}) do
		local speedButton =
			button(
				speedSection,
				tostring(multiplier)
				.. "x",
				C.CARD2,
				30
			)

		speedButtons[multiplier] =
			speedButton

		speedButton.Activated:Connect(
			function()
				player:SetAttribute(
					"AdminPetAnimationSpeed",
					multiplier
				)

				refreshPet()
			end
		)
	end

	local actions =
		section(
			page,
			"Acciones"
		)

	local respawn =
		button(
			actions,
			"Respawn mascota",
			C.CARD2,
			34
		)

	local removeOutside =
		button(
			actions,
			"Quitar mascota de afuera",
			C.RED,
			34
		)

	respawn.Activated:Connect(function()
		local currentPet =
			petType()
			or player:GetAttribute(
				"SelectedBackpackPet"
			)

		if typeof(currentPet)
			== "string"
			and currentPet ~= ""
		then
			local currentTier =
				player:GetAttribute(
					"SelectedBackpackPetTier"
				) or "Base"

			EquipPet:FireServer(
				currentPet,
				currentTier
			)

			syncPetToQuickSlot2(
				currentPet,
				currentTier
			)

			setStatus(
				"Mascota respawneada",
				C.GREEN
			)
		else
			setStatus(
				"No hay mascota seleccionada",
				C.RED
			)
		end
	end)

	removeOutside.Activated:Connect(
		function()
			EquipPet:FireServer("")

			setStatus(
				"Mascota retirada",
				C.ORANGE
			)
		end
	)
end

--==============================================================
-- PAGINA: MOVIMIENTO / VUELO
--==============================================================

local flying = false
local speed = 65

local humanoid = nil
local root = nil
local attachment = nil
local velocity = nil
local orientation = nil
local flightConnection = nil

local move = {
	F = false,
	B = false,
	L = false,
	R = false,
	U = false,
	D = false,
}

local flyButton = nil
local speedText = nil

local function stopFly()
	if not flying then
		return
	end

	flying = false

	if flightConnection then
		flightConnection:Disconnect()
		flightConnection = nil
	end

	if velocity then
		velocity:Destroy()
		velocity = nil
	end

	if orientation then
		orientation:Destroy()
		orientation = nil
	end

	if attachment then
		attachment:Destroy()
		attachment = nil
	end

	if humanoid then
		humanoid.AutoRotate = true
		humanoid.PlatformStand = false

		pcall(function()
			humanoid:ChangeState(
				Enum.HumanoidStateType.Running
			)
		end)
	end

	if flyButton then
		flyButton.Text =
			"Activar vuelo"

		flyButton.BackgroundColor3 =
			C.BLUE
	end
end

local function moveVector()
	camera = workspace.CurrentCamera

	if not camera then
		return Vector3.zero
	end

	local vector = Vector3.zero

	local look =
		camera.CFrame.LookVector

	local right =
		camera.CFrame.RightVector

	if move.F then
		vector = vector + look
	end

	if move.B then
		vector = vector - look
	end

	if move.R then
		vector = vector + right
	end

	if move.L then
		vector = vector - right
	end

	if move.U then
		vector =
			vector + Vector3.yAxis
	end

	if move.D then
		vector =
			vector - Vector3.yAxis
	end

	if vector.Magnitude > 0 then
		return vector.Unit
	end

	return Vector3.zero
end

local function startFly()
	if flying then
		return
	end

	local character =
		player.Character
		or player.CharacterAdded:Wait()

	humanoid =
		character:WaitForChild(
			"Humanoid"
		)

	root =
		character:WaitForChild(
			"HumanoidRootPart"
		)

	camera = workspace.CurrentCamera

	flying = true

	humanoid.AutoRotate = false
	humanoid.PlatformStand = true

	pcall(function()
		humanoid:ChangeState(
			Enum.HumanoidStateType.Physics
		)
	end)

	attachment =
		Instance.new("Attachment")

	attachment.Name =
		"AdminFlightAttachment"

	attachment.Parent = root

	velocity =
		Instance.new("LinearVelocity")

	velocity.Name =
		"AdminFlightVelocity"

	velocity.Attachment0 =
		attachment

	velocity.MaxForce =
		math.huge

	velocity.RelativeTo =
		Enum.ActuatorRelativeTo.World

	velocity.VectorVelocity =
		Vector3.zero

	velocity.Parent = root

	orientation =
		Instance.new(
			"AlignOrientation"
		)

	orientation.Name =
		"AdminFlightOrientation"

	orientation.Attachment0 =
		attachment

	orientation.MaxTorque =
		math.huge

	orientation.Responsiveness =
		18

	orientation.Mode =
		Enum.OrientationAlignmentMode.OneAttachment

	orientation.Parent = root

	flightConnection =
		RunService.RenderStepped:Connect(
			function()
				if not root
					or not root.Parent
				then
					stopFly()
					return
				end

				camera =
				workspace.CurrentCamera

				if not camera then
					return
				end

				velocity.VectorVelocity =
				moveVector()
				* speed

				local look =
				camera.CFrame.LookVector

				if look.Magnitude > 0 then
					orientation.CFrame =
					CFrame.lookAt(
						root.Position,
						root.Position
						+ look
					)
				end
			end
		)

	if flyButton then
		flyButton.Text =
			"Desactivar vuelo"

		flyButton.BackgroundColor3 =
			C.RED
	end
end

do
	local page =
		pages.Movimiento

	local flySection =
		section(
			page,
			"Vuelo"
		)

	flyButton =
		button(
			flySection,
			"Activar vuelo",
			C.BLUE,
			38
		)

	flyButton.Activated:Connect(
		function()
			if flying then
				stopFly()
			else
				startFly()
			end
		end
	)

	speedText =
		label(
			flySection,
			"Velocidad: 65",
			20,
			false
		)

	speedText.TextColor3 = C.SUB

	local minus =
		button(
			flySection,
			"-10",
			C.CARD2,
			32
		)

	local plus =
		button(
			flySection,
			"+10",
			C.CARD2,
			32
		)

	minus.Activated:Connect(function()
		speed =
			math.clamp(
				speed - 10,
				25,
				150
			)

		speedText.Text =
			"Velocidad: "
			.. tostring(speed)
	end)

	plus.Activated:Connect(function()
		speed =
			math.clamp(
				speed + 10,
				25,
				150
			)

		speedText.Text =
			"Velocidad: "
			.. tostring(speed)
	end)

	local hint =
		label(
			flySection,
			"WASD mover | Espacio subir | Ctrl/Q bajar | F vuelo",
			20,
			false
		)

	hint.TextColor3 = C.SUB
end

--==============================================================
-- PAGINA: PRUEBAS
--==============================================================

do
	local page = pages.Pruebas

	local tradeSection =
		section(
			page,
			"Trade"
		)

	local tradeButton =
		button(
			tradeSection,
			"Anadir jugador de prueba",
			C.ORANGE,
			36
		)

	local function syncTrade()
		local enabled =
			player:GetAttribute(
				"TradeTestPlayerEnabled"
			) == true

		tradeButton.Text =
			enabled
			and "Quitar jugador de prueba"
			or "Anadir jugador de prueba"

		tradeButton.BackgroundColor3 =
			enabled
			and C.GREEN
			or C.ORANGE
	end

	tradeButton.Activated:Connect(
		function()
			player:SetAttribute(
				"TradeTestPlayerEnabled",
				player:GetAttribute(
					"TradeTestPlayerEnabled"
				) ~= true
			)

			syncTrade()
		end
	)

	syncTrade()

	local debugSection =
		section(
			page,
			"Debug mascota"
		)

	local resetAnimation =
		button(
			debugSection,
			"Reset animacion",
			C.CARD2,
			34
		)

	resetAnimation.Activated:Connect(
		function()
			player:SetAttribute(
				"AdminPetAnimationOverride",
				""
			)

			player:SetAttribute(
				"AdminPetAnimationSpeed",
				1
			)

			refreshPet()

			setStatus(
				"Animacion restaurada",
				C.GREEN
			)
		end
	)

	local reequip =
		button(
			debugSection,
			"Reequipar seleccionada",
			C.CARD2,
			34
		)

	reequip.Activated:Connect(function()
		local petName =
			player:GetAttribute(
				"SelectedBackpackPet"
			)

		local tier =
			player:GetAttribute(
				"SelectedBackpackPetTier"
			)

		if typeof(petName)
			== "string"
			and petName ~= ""
		then
			EquipPet:FireServer(
				petName,
				tier
			)

			syncPetToQuickSlot2(
				petName,
				tier
			)

			setStatus(
				"Mascota reequipada",
				C.GREEN
			)
		else
			setStatus(
				"No hay mascota seleccionada",
				C.RED
			)
		end
	end)
end

--==============================================================
-- INPUT DEL VUELO
--==============================================================

local keyMap = {
	[Enum.KeyCode.W] = "F",
	[Enum.KeyCode.S] = "B",
	[Enum.KeyCode.A] = "L",
	[Enum.KeyCode.D] = "R",
	[Enum.KeyCode.Space] = "U",
	[Enum.KeyCode.LeftControl] = "D",
	[Enum.KeyCode.Q] = "D",
}

--==============================================================
-- ABRIR / CERRAR CON /admin
--==============================================================

local visible = false
panel.Visible = false

local function show(value)
	visible = value == true
	panel.Visible = visible

	if not visible and flying then
		stopFly()
	end
end

close.Activated:Connect(function()
	show(false)
end)

local oldCommand =
	TextChatService:FindFirstChild(
		"AdminMenuCommand_Local"
	)

if oldCommand then
	oldCommand:Destroy()
end

local adminCommand =
	Instance.new("TextChatCommand")

adminCommand.Name =
	"AdminMenuCommand_Local"

adminCommand.PrimaryAlias =
	"/admin"

adminCommand.Parent =
	TextChatService

adminCommand.Triggered:Connect(function()
	show(not visible)
end)

--==============================================================
-- TECLAS
--==============================================================

UserInputService.InputBegan:Connect(
	function(inputObject, gameProcessed)
		if inputObject.UserInputType
			~= Enum.UserInputType.Keyboard
		then
			return
		end

		local direction =
			keyMap[inputObject.KeyCode]

		if direction then
			move[direction] = true
		end

		if not gameProcessed
			and inputObject.KeyCode
			== Enum.KeyCode.F
			and visible
		then
			if flying then
				stopFly()
			else
				startFly()
			end
		end
	end
)

UserInputService.InputEnded:Connect(
	function(inputObject)
		if inputObject.UserInputType
			~= Enum.UserInputType.Keyboard
		then
			return
		end

		local direction =
			keyMap[inputObject.KeyCode]

		if direction then
			move[direction] = false
		end
	end
)

--==============================================================
-- ARRASTRAR MENU
--==============================================================

local dragging = false
local dragStart = nil
local startPosition = nil

top.Active = true

top.InputBegan:Connect(function(inputObject)
	if inputObject.UserInputType
		== Enum.UserInputType.MouseButton1
	then
		dragging = true
		dragStart = inputObject.Position
		startPosition = panel.Position
	end
end)

top.InputEnded:Connect(function(inputObject)
	if inputObject.UserInputType
		== Enum.UserInputType.MouseButton1
	then
		dragging = false
	end
end)

UserInputService.InputChanged:Connect(
	function(inputObject)
		if dragging
			and inputObject.UserInputType
			== Enum.UserInputType.MouseMovement
		then
			local delta =
				inputObject.Position
			- dragStart

			panel.Position =
				UDim2.new(
					startPosition.X.Scale,
					startPosition.X.Offset
					+ delta.X,
					startPosition.Y.Scale,
					startPosition.Y.Offset
					+ delta.Y
				)
		end
	end
)

--==============================================================
-- ACTUALIZACION
--==============================================================

player.CharacterAdded:Connect(function()
	stopFly()
end)

player:SetAttribute(
	"AdminPetAnimationOverride",
	""
)

player:SetAttribute(
	"AdminPetAnimationSpeed",
	1
)

player:GetAttributeChangedSignal(
	"AdminPetAnimationOverride"
):Connect(refreshPet)

player:GetAttributeChangedSignal(
	"AdminPetAnimationSpeed"
):Connect(refreshPet)

player:GetAttributeChangedSignal(
	"SelectedBackpackPet"
):Connect(function()
	syncPetToQuickSlot2()
end)

player:GetAttributeChangedSignal(
	"SelectedBackpackPetTier"
):Connect(function()
	syncPetToQuickSlot2()
end)

task.spawn(function()
	task.wait(1)

	local selectedPet =
		player:GetAttribute(
			"SelectedBackpackPet"
		)

	if typeof(selectedPet) == "string"
		and selectedPet ~= ""
	then
		syncPetToQuickSlot2(
			selectedPet,
			player:GetAttribute(
				"SelectedBackpackPetTier"
			) or "Base"
		)
	end
end)

task.spawn(function()
	while gui.Parent do
		refreshPet()
		task.wait(0.35)
	end
end)

setTab("Jugador")
refreshPet()

setStatus(
	"Escribe /admin para abrir o cerrar",
	C.GREEN
)
