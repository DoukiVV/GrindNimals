--============================================================
-- DAILY LOGIN CLIENT V8 - AUTO SOLO SI PUEDE RECLAMAR + FUENTE
-- Ubicacion: StarterPlayer > StarterPlayerScripts > DailyLoginClient
-- Tipo: LocalScript
--
-- Este archivo mantiene tu interfaz V2 y agrega:
-- * Reabrir el menu al interactuar con la fuente.
-- * Compatible aunque PromptTriggered no envie Player en cliente.
-- * Al entrar: solo abre automaticamente si hay recompensa disponible.
-- * Si ya reclamo hoy: NO aparece automaticamente; se abre solo desde la fuente.
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local systemFolder = ReplicatedStorage:WaitForChild("DailyLoginSystem")
local GetDailyState = systemFolder:WaitForChild("GetDailyState")
local ClaimDailyReward = systemFolder:WaitForChild("ClaimDailyReward")
local petViews = ReplicatedStorage:WaitForChild("MascotasView")

local FONT = Enum.Font.FredokaOne

local DIAMOND_ICON = "rbxassetid://120590444497312"
local MONEY_ICON = "rbxassetid://117128537983961"
local DAILY_FOUNTAIN_PROMPT_NAME = "DailyLoginFountainPrompt"

--============================================================
-- AJUSTE RAPIDO DE LA FUENTE
--============================================================

-- Cambia SOLO este numero para decidir desde que tan lejos
-- aparece y se puede usar la interaccion.
-- 40 = medio, 60 = lejos, 80 = muy lejos.
local FOUNTAIN_DISTANCE = 40

-- Altura del prompt respecto al centro geometrico de la fuente.
-- Sube/baja este numero si quieres moverlo verticalmente.
local FOUNTAIN_PROMPT_HEIGHT = -8

local COLORS = {
	shade = Color3.fromRGB(0, 0, 0),
	panel = Color3.fromRGB(204, 144, 71),
	dark = Color3.fromRGB(82, 45, 24),
	cream = Color3.fromRGB(255, 232, 190),
	card = Color3.fromRGB(245, 216, 176),
	completed = Color3.fromRGB(170, 203, 134),
	today = Color3.fromRGB(255, 226, 145),
	green = Color3.fromRGB(85, 168, 77),
	red = Color3.fromRGB(186, 88, 82),
	gold = Color3.fromRGB(236, 180, 65),
	gray = Color3.fromRGB(145, 132, 116),
	white = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(55, 31, 18),
}

local function create(className, props, parent)
	local obj = Instance.new(className)
	for key, value in pairs(props or {}) do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

local function corner(obj, radius)
	create("UICorner", {
		CornerRadius = UDim.new(0, radius or 10),
	}, obj)
end

local function stroke(obj, thickness, color, transparency)
	return create("UIStroke", {
		Thickness = thickness or 2,
		Color = color or COLORS.dark,
		Transparency = transparency or 0,
	}, obj)
end

local function addButtonMotion(button)
	local scale = create("UIScale", {Scale = 1}, button)

	button.MouseEnter:Connect(function()
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
		TweenService:Create(scale, TweenInfo.new(0.07), {Scale = 0.95}):Play()
	end)

	button.MouseButton1Up:Connect(function()
		TweenService:Create(
			scale,
			TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Scale = 1.035}
		):Play()
	end)
end

local oldGui = playerGui:FindFirstChild("DailyLoginGui")
if oldGui then
	oldGui:Destroy()
end

local gui = create("ScreenGui", {
	Name = "DailyLoginGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 9000,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local shade = create("Frame", {
	Name = "Shade",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = COLORS.shade,
	BackgroundTransparency = 0.42,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 1,
}, gui)

local panel = create("Frame", {
	Name = "DailyPanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(1010, 500),
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
		math.min(viewport.X / 1160, viewport.Y / 650),
		0.52,
		1
	)
end

local function updateResponsiveScale()
	responsiveScale.Scale = getResponsiveScale()
end

updateResponsiveScale()

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale)
end

local title = create("TextLabel", {
	Position = UDim2.fromOffset(18, 16),
	Size = UDim2.new(1, -86, 0, 62),
	BackgroundColor3 = COLORS.cream,
	BorderSizePixel = 0,
	Text = "INICIO DIARIO DE SESION",
	Font = FONT,
	TextScaled = true,
	TextColor3 = COLORS.text,
	ZIndex = 11,
}, panel)

corner(title, 10)
stroke(title, 2)

create("UITextSizeConstraint", {
	MinTextSize = 24,
	MaxTextSize = 42,
}, title)

local closeButton = create("TextButton", {
	Name = "Close",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -18, 0, 22),
	Size = UDim2.fromOffset(48, 48),
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

local subtitle = create("TextLabel", {
	Position = UDim2.fromOffset(25, 86),
	Size = UDim2.new(1, -50, 0, 32),
	BackgroundTransparency = 1,
	Text = "Vuelve cada dia para reclamar tu siguiente recompensa.",
	Font = FONT,
	TextSize = 19,
	TextColor3 = COLORS.text,
	ZIndex = 11,
}, panel)

local rewardsHolder = create("Frame", {
	Position = UDim2.fromOffset(24, 126),
	Size = UDim2.new(1, -48, 0, 238),
	BackgroundColor3 = Color3.fromRGB(121, 79, 48),
	BackgroundTransparency = 0.06,
	BorderSizePixel = 0,
	ZIndex = 11,
}, panel)

corner(rewardsHolder, 12)
stroke(rewardsHolder, 3)

create("UIGridLayout", {
	CellSize = UDim2.fromOffset(124, 202),
	CellPadding = UDim2.fromOffset(10, 0),
	FillDirectionMaxCells = 7,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, rewardsHolder)

local FALLBACK_AMOUNTS = {
	[1] = "5",
	[2] = "50",
	[3] = "100",
	[4] = "150",
	[5] = "200",
	[6] = "5",
	[7] = "",
}

local function rewardIconForDay(day)
	if day == 1 or day == 6 then
		return DIAMOND_ICON
	elseif day >= 2 and day <= 5 then
		return MONEY_ICON
	end
	return ""
end

local function findEggSourceModel()
	local template =
		petViews:FindFirstChild("Huevo Mascota")
		or petViews:FindFirstChild("HuevoBrizabelle")

	if not template then
		return nil
	end

	if template:IsA("Model") then
		return template
	end

	local sourceViewport =
		template:IsA("ViewportFrame")
		and template
		or template:FindFirstChildWhichIsA("ViewportFrame", true)

	if sourceViewport then
		local model = sourceViewport:FindFirstChildWhichIsA("Model", true)
		if model then
			return model
		end
	end

	return template:FindFirstChildWhichIsA("Model", true)
end

local function putEggModel(viewport)
	local source = findEggSourceModel()

	if not source then
		warn("[DailyLoginClient] No se encontro Huevo Mascota en MascotasView.")
		return
	end

	local world = Instance.new("WorldModel")
	world.Name = "EggWorld"
	world.Parent = viewport

	local model = source:Clone()
	model.Name = "HuevoMascotaPreview"

	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("BasePart") then
			object.Anchored = true
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = false
			object.CastShadow = false
		elseif object:IsA("Script") or object:IsA("LocalScript") then
			object:Destroy()
		end
	end

	model.Parent = world

	local camera = Instance.new("Camera")
	camera.Name = "EggCamera"
	camera.FieldOfView = 32
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local cf, size = model:GetBoundingBox()
	local center = cf.Position
	local maxSize = math.max(size.X, size.Y, size.Z, 0.1)

	camera.CFrame = CFrame.new(
		center + Vector3.new(0, maxSize * 0.05, maxSize * 2.1),
		center
	)
end

local rewardCards = {}

for day = 1, 7 do
	local card = create("Frame", {
		Name = "Day" .. tostring(day),
		BackgroundColor3 = COLORS.card,
		BorderSizePixel = 0,
		LayoutOrder = day,
		ZIndex = 12,
	}, rewardsHolder)

	corner(card, 10)
	local cardStroke = stroke(card, 2, COLORS.dark)

	create("TextLabel", {
		Position = UDim2.fromOffset(6, 9),
		Size = UDim2.new(1, -12, 0, 29),
		BackgroundTransparency = 1,
		Text = "DIA " .. tostring(day),
		Font = FONT,
		TextSize = 18,
		TextColor3 = COLORS.text,
		ZIndex = 14,
	}, card)

	local visualHolder = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 43),
		Size = UDim2.new(1, -12, 0, 98),
		BackgroundTransparency = 1,
		ZIndex = 13,
	}, card)

	local amountLabel = nil
	local eggViewport = nil

	if day == 7 then
		eggViewport = create("ViewportFrame", {
			Name = "EggViewport",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(92, 92),
			BackgroundTransparency = 1,
			Ambient = Color3.fromRGB(255, 255, 255),
			LightColor = Color3.fromRGB(255, 255, 255),
			LightDirection = Vector3.new(-1, -1, -1),
			ZIndex = 14,
		}, visualHolder)

		putEggModel(eggViewport)
	else
		create("ImageLabel", {
			Name = "RewardIcon",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.fromOffset(64, 64),
			BackgroundTransparency = 1,
			Image = rewardIconForDay(day),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 14,
		}, visualHolder)

		amountLabel = create("TextLabel", {
			Name = "Amount",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.new(1, -8, 0, 28),
			BackgroundTransparency = 1,
			Text = FALLBACK_AMOUNTS[day],
			Font = FONT,
			TextSize = 20,
			TextColor3 = COLORS.text,
			ZIndex = 15,
		}, visualHolder)
	end

	local stateLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -9),
		Size = UDim2.new(1, -10, 0, 29),
		BackgroundTransparency = 1,
		Text = "",
		Font = FONT,
		TextSize = 13,
		TextColor3 = COLORS.dark,
		TextWrapped = true,
		ZIndex = 16,
	}, card)

	rewardCards[day] = {
		card = card,
		stroke = cardStroke,
		amountLabel = amountLabel,
		eggViewport = eggViewport,
		stateLabel = stateLabel,
	}
end

local status = create("TextLabel", {
	Position = UDim2.fromOffset(26, 378),
	Size = UDim2.new(1, -52, 0, 35),
	BackgroundTransparency = 1,
	Text = "",
	Font = FONT,
	TextSize = 19,
	TextColor3 = COLORS.text,
	TextWrapped = true,
	ZIndex = 11,
}, panel)

local claimButton = create("TextButton", {
	Name = "ClaimButton",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -25),
	Size = UDim2.fromOffset(390, 58),
	BackgroundColor3 = COLORS.green,
	BorderSizePixel = 0,
	Text = "RECLAMAR",
	Font = FONT,
	TextScaled = true,
	TextColor3 = COLORS.white,
	AutoButtonColor = false,
	ZIndex = 12,
}, panel)

corner(claimButton, 12)
stroke(claimButton, 3)
addButtonMotion(claimButton)

create("UITextSizeConstraint", {
	MinTextSize = 20,
	MaxTextSize = 34,
}, claimButton)

local latestState = nil
local claiming = false
local serverOffset = 0

-- Anti-spam para la fuente.
local FOUNTAIN_OPEN_COOLDOWN = 1.75
local lastFountainOpenAt = -math.huge

local function syncedNow()
	return os.time() + serverOffset
end

local function formatRemaining(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = seconds % 60
	return string.format("%02dh %02dm %02ds", hours, minutes, secs)
end

local fetchState

local function updateTimerText()
	if not latestState then
		return
	end

	if latestState.canClaim then
		status.Text = "Tu recompensa esta lista."
		return
	end

	local nextClaimAt = tonumber(latestState.nextClaimAt) or syncedNow()
	local remaining = nextClaimAt - syncedNow()

	if remaining <= 0 then
		task.spawn(function()
			if fetchState then
				fetchState()
			end
		end)
		return
	end

	status.Text = "Siguiente recompensa en " .. formatRemaining(remaining)
end

local function renderState(state)
	if not state then
		return
	end

	latestState = state

	if typeof(state.serverNow) == "number" then
		serverOffset = state.serverNow - os.time()
	end

	local currentDay = math.clamp(
		math.floor(tonumber(state.currentDay) or 1),
		1,
		7
	)

	local lastCompletedDay = math.clamp(
		math.floor(tonumber(state.lastCompletedDay) or 0),
		0,
		7
	)

	for day = 1, 7 do
		local info = rewardCards[day]

		info.card.BackgroundColor3 = COLORS.card
		info.stroke.Color = COLORS.dark
		info.stroke.Thickness = 2
		info.stateLabel.Text = ""

		if state.streakReset then
			if day == 1 then
				info.card.BackgroundColor3 = COLORS.today
				info.stroke.Color = COLORS.gold
				info.stroke.Thickness = 5
				info.stateLabel.Text = "HOY"
			end
		elseif state.canClaim then
			if day < currentDay then
				info.card.BackgroundColor3 = COLORS.completed
				info.stateLabel.Text = "COMPLETADO"
			elseif day == currentDay then
				info.card.BackgroundColor3 = COLORS.today
				info.stroke.Color = COLORS.gold
				info.stroke.Thickness = 5
				info.stateLabel.Text = "HOY"
			end
		else
			if day <= lastCompletedDay then
				info.card.BackgroundColor3 = COLORS.completed
				info.stateLabel.Text = "COMPLETADO"
			end
		end

		local reward = state.rewards and state.rewards[day]
		if info.amountLabel and reward then
			info.amountLabel.Text = tostring(reward.amount or "")
		end
	end

	if state.canClaim then
		claimButton.Active = true
		claimButton.BackgroundColor3 = COLORS.green
		claimButton.Text = "RECLAMAR DIA " .. tostring(currentDay)
	else
		claimButton.Active = false
		claimButton.BackgroundColor3 = COLORS.gray
		claimButton.Text = "RECLAMADO"
	end

	updateTimerText()
end

fetchState = function()
	status.Text = "Cargando..."

	local ok, state = pcall(function()
		return GetDailyState:InvokeServer()
	end)

	if ok and typeof(state) == "table" then
		renderState(state)
		return true
	end

	status.Text = "No se pudo cargar el inicio diario."
	return false
end

local opening = false

local function openDaily()
	if opening then
		return
	end

	opening = true
	fetchState()

	shade.Visible = true
	panel.Visible = true

	local target = getResponsiveScale()
	responsiveScale.Scale = target * 0.82
	panel.Position = UDim2.fromScale(0.5, 0.515)

	TweenService:Create(
		responsiveScale,
		TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Scale = target}
	):Play()

	TweenService:Create(
		panel,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Position = UDim2.fromScale(0.5, 0.5)}
	):Play()

	task.delay(0.25, function()
		opening = false
	end)
end

local function closeDaily()
	panel.Visible = false
	shade.Visible = false
end

closeButton.Activated:Connect(closeDaily)

claimButton.Activated:Connect(function()
	if claiming or not latestState or not latestState.canClaim then
		return
	end

	claiming = true
	claimButton.Text = "RECLAMANDO..."

	local ok, result = pcall(function()
		return ClaimDailyReward:InvokeServer()
	end)

	claiming = false

	if ok and typeof(result) == "table" then
		if result.state then
			renderState(result.state)
		end

		if result.message and result.message ~= "" then
			status.Text = tostring(result.message)
			task.delay(2.2, updateTimerText)
		end
	else
		status.Text = "No se pudo reclamar. Intenta otra vez."
	end
end)

--============================================================
-- FUENTE: PROMPT CREADO/CONFIGURADO EN EL CLIENTE
--
-- Tu Explorer muestra:
-- Workspace > Lobby > Decoracion > Fuente > Hitbox Fuente > Part
--
-- El servidor no esta encontrando esa ruta en tu partida, pero el
-- cliente si tiene la fuente visible. Como este prompt SOLO abre UI,
-- es correcto configurarlo localmente. La recompensa sigue validada
-- completamente por DailyLoginServer.
--============================================================

local connectedFountainPrompt = nil
local fountainPromptConnection = nil

local function normalizeName(value)
	local s = tostring(value or ""):lower()
	s = s:gsub("á", "a"):gsub("é", "e"):gsub("í", "i")
	s = s:gsub("ó", "o"):gsub("ú", "u"):gsub("ñ", "n")
	s = s:gsub("[%s_%-]+", "")
	return s
end

local function findDirectFountain()
	local lobby = workspace:FindFirstChild("Lobby")
	if lobby then
		local decoracion = lobby:FindFirstChild("Decoracion")
		if decoracion then
			local fuente = decoracion:FindFirstChild("Fuente")
			if fuente then
				return fuente
			end
		end
	end

	return nil
end

local function findFountainAnywhere()
	local direct = findDirectFountain()
	if direct then
		return direct
	end

	-- Fallback robusto por si Roblox tarda en replicar o cambia
	-- levemente el nombre/ruta.
	for _, object in ipairs(workspace:GetDescendants()) do
		if normalizeName(object.Name) == "fuente" then
			local parent = object.Parent
			local grandparent = parent and parent.Parent

			if parent
				and normalizeName(parent.Name) == "decoracion"
				and grandparent
				and normalizeName(grandparent.Name) == "lobby"
			then
				return object
			end
		end
	end

	return nil
end

local function findHitboxContainer(fuente)
	if not fuente then
		return nil
	end

	for _, child in ipairs(fuente:GetChildren()) do
		if normalizeName(child.Name) == "hitboxfuente" then
			return child
		end
	end

	for _, object in ipairs(fuente:GetDescendants()) do
		if normalizeName(object.Name) == "hitboxfuente" then
			return object
		end
	end

	return nil
end

local fountainPromptAnchor = nil

local function getBoundsCenter(container)
	if not container then
		return nil
	end

	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	local found = false

	for _, object in ipairs(container:GetDescendants()) do
		if object:IsA("BasePart") then
			found = true

			-- Calcula las 8 esquinas para que funcione incluso si las Parts
			-- estan rotadas.
			local half = object.Size * 0.5
			local corners = {
				Vector3.new(-half.X, -half.Y, -half.Z),
				Vector3.new(-half.X, -half.Y,  half.Z),
				Vector3.new(-half.X,  half.Y, -half.Z),
				Vector3.new(-half.X,  half.Y,  half.Z),
				Vector3.new( half.X, -half.Y, -half.Z),
				Vector3.new( half.X, -half.Y,  half.Z),
				Vector3.new( half.X,  half.Y, -half.Z),
				Vector3.new( half.X,  half.Y,  half.Z),
			}

			for _, localCorner in ipairs(corners) do
				local p = object.CFrame:PointToWorldSpace(localCorner)

				minV = Vector3.new(
					math.min(minV.X, p.X),
					math.min(minV.Y, p.Y),
					math.min(minV.Z, p.Z)
				)

				maxV = Vector3.new(
					math.max(maxV.X, p.X),
					math.max(maxV.Y, p.Y),
					math.max(maxV.Z, p.Z)
				)
			end
		end
	end

	if not found then
		return nil
	end

	return (minV + maxV) * 0.5
end

local function getFountainCenter(fuente)
	-- Prioridad: Hitbox Fuente, porque representa mejor el area completa.
	local hitbox = findHitboxContainer(fuente)
	local center = getBoundsCenter(hitbox)

	if not center then
		center = getBoundsCenter(fuente)
	end

	return center
end

local function getOrCreateFountainAnchor(fuente)
	local center = getFountainCenter(fuente)

	if not center then
		return nil
	end

	if not fountainPromptAnchor or not fountainPromptAnchor.Parent then
		fountainPromptAnchor = Instance.new("Part")
		fountainPromptAnchor.Name = "DailyLoginPromptAnchor"
		fountainPromptAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
		fountainPromptAnchor.Anchored = true
		fountainPromptAnchor.CanCollide = false
		fountainPromptAnchor.CanTouch = false
		fountainPromptAnchor.CanQuery = false
		fountainPromptAnchor.Transparency = 1
		fountainPromptAnchor.CastShadow = false
		fountainPromptAnchor.Parent = workspace
	end

	fountainPromptAnchor.CFrame = CFrame.new(
		center + Vector3.new(0, FOUNTAIN_PROMPT_HEIGHT, 0)
	)

	return fountainPromptAnchor
end

local function findExistingFountainPrompt(fuente)
	if not fuente then
		return nil
	end

	-- En tu captura ya existe uno llamado "FuentePrompt".
	for _, object in ipairs(fuente:GetDescendants()) do
		if object:IsA("ProximityPrompt") then
			local n = normalizeName(object.Name)
			if n == "fuenteprompt"
				or n == "dailyloginfountainprompt"
			then
				return object
			end
		end
	end

	-- Si ya lo movimos al ancla central, tambien lo reutilizamos.
	if fountainPromptAnchor and fountainPromptAnchor.Parent then
		local centeredPrompt = fountainPromptAnchor:FindFirstChild("FuentePrompt")
		if centeredPrompt and centeredPrompt:IsA("ProximityPrompt") then
			return centeredPrompt
		end
	end

	return nil
end

local function findPromptPart(fuente)
	local hitbox = findHitboxContainer(fuente)

	if hitbox then
		if hitbox:IsA("BasePart") then
			return hitbox
		end

		local part = hitbox:FindFirstChildWhichIsA("BasePart", true)
		if part then
			return part
		end
	end

	return fuente and fuente:FindFirstChildWhichIsA("BasePart", true) or nil
end

local function configureFountainPrompt(prompt)
	if not prompt then
		return
	end

	prompt.Name = "FuentePrompt"
	prompt.ActionText = "Ver inicio diario"
	prompt.ObjectText = "Fuente"
	prompt.Enabled = true
	prompt.HoldDuration = 0.65
	prompt.MaxActivationDistance = FOUNTAIN_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.ClickablePrompt = true
	prompt.Style = Enum.ProximityPromptStyle.Custom
end

local function connectFountainPrompt(prompt)
	if not prompt then
		return false
	end

	if connectedFountainPrompt == prompt
		and fountainPromptConnection
	then
		configureFountainPrompt(prompt)
		return true
	end

	if fountainPromptConnection then
		fountainPromptConnection:Disconnect()
		fountainPromptConnection = nil
	end

	connectedFountainPrompt = prompt
	configureFountainPrompt(prompt)

	fountainPromptConnection = prompt.Triggered:Connect(function(triggeringPlayer)
		if triggeringPlayer ~= nil
			and triggeringPlayer ~= player
		then
			return
		end

		local now = os.clock()

		-- Si la interfaz ya esta abierta, E no vuelve a ejecutarla.
		if panel.Visible then
			return
		end

		-- Cooldown adicional por seguridad.
		if now - lastFountainOpenAt < FOUNTAIN_OPEN_COOLDOWN then
			return
		end

		lastFountainOpenAt = now

		-- Bloquea temporalmente el prompt despues de usarlo.
		prompt.Enabled = false
		openDaily()

		task.delay(FOUNTAIN_OPEN_COOLDOWN, function()
			if prompt and prompt.Parent then
				prompt.Enabled = true
			end
		end)
	end)
	return true
end

local function setupFountainPrompt()
	local fuente = findFountainAnywhere()
	if not fuente then
		return false
	end

	local prompt = findExistingFountainPrompt(fuente)
	local centerAnchor = getOrCreateFountainAnchor(fuente)

	if not centerAnchor then
		warn("[DailyLoginFuente] No pude calcular el centro de la fuente.")
		return false
	end

	if not prompt then
		-- Tambien revisa si ya fue movido al ancla central.
		prompt = centerAnchor:FindFirstChild("FuentePrompt")
	end

	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "FuentePrompt"
	end

	-- MUY IMPORTANTE:
	-- El ProximityPrompt vive en el centro geometrico de la fuente.
	-- La distancia ya no se mide desde una Part aleatoria del Hitbox.
	prompt.Parent = centerAnchor

	configureFountainPrompt(prompt)
	prompt.MaxActivationDistance = FOUNTAIN_DISTANCE

	return connectFountainPrompt(prompt)
end

-- Busca la fuente hasta que termine de aparecer en el cliente.
task.spawn(function()
	for attempt = 1, 120 do
		if setupFountainPrompt() then
			return
		end

		if attempt == 1 or attempt % 10 == 0 then
		end

		task.wait(0.5)
	end

	warn("[DailyLoginFuente] No pude encontrar la fuente en el cliente despues de 60 segundos.")
end)

-- Si el mapa/Hitbox se reconstruye, vuelve a enlazarlo.
workspace.DescendantAdded:Connect(function(object)
	local n = normalizeName(object.Name)

	if n == "fuente"
		or n == "hitboxfuente"
		or n == "fuenteprompt"
	then
		task.delay(0.25, setupFountainPrompt)
	end
end)

task.spawn(function()
	while gui.Parent do
		task.wait(1)

		if panel.Visible and latestState then
			updateTimerText()

			if not latestState.canClaim then
				local remaining =
					(tonumber(latestState.nextClaimAt) or 0)
				- syncedNow()

				if remaining <= 0 then
					fetchState()
				end
			end
		end
	end
end)

local function waitForLoadingToFinish()
	local startedAt = os.clock()

	while os.clock() - startedAt < 100 do
		local loadingGui = playerGui:FindFirstChild("GameStartLoadingGui")
		local loadingAttribute = player:GetAttribute("GameStartLoading")

		if not loadingGui and loadingAttribute ~= true then
			break
		end

		task.wait(0.1)
	end

	task.wait(0.3)
end

task.spawn(function()
	waitForLoadingToFinish()

	-- Al entrar al juego, solo abre automaticamente si existe
	-- una recompensa disponible para reclamar.
	--
	-- Si el jugador ya reclamo su recompensa de hoy,
	-- NO se abre automaticamente. Aun puede abrirla
	-- manualmente desde la fuente.
	local ok, state = pcall(function()
		return GetDailyState:InvokeServer()
	end)

	if ok and typeof(state) == "table" then
		renderState(state)

		if state.canClaim == true then
			openDaily()
		else
			closeDaily()
		end
	else
		closeDaily()
		warn("[DailyLoginClient] No se pudo comprobar el estado inicial del login diario.")
	end
end)