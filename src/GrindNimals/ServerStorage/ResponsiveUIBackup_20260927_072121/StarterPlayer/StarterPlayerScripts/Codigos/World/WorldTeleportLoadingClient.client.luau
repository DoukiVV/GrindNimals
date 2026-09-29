--============================================================
-- WORLD TELEPORT LOADING CLIENT - V8 STYLE
--
-- UBICACION:
-- StarterPlayer > StarterPlayerScripts > WorldTeleportLoadingClient
-- Tipo: LocalScript
--
-- MISMO ESTILO de GameStartLoadingClient:
-- - Fondo cafe con degradado
-- - Logo grande
-- - FredokaOne
-- - Barra de progreso
-- - Bloquea movimiento mientras viaja
--
-- IMPORTANTE:
-- Este loading NO fuerza 5 segundos.
-- Dura solamente lo que tarde el TeleportService.
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("WorldTeleportEvent")

--============================================================
-- CONFIG - MISMA PALETA DE TU PANTALLA V8
--============================================================

local LOGO_IMAGE = "rbxassetid://77375619575374"

local BG_TOP = Color3.fromRGB(149, 110, 71)
local BG_MIDDLE = Color3.fromRGB(129, 93, 58)
local BG_BOTTOM = Color3.fromRGB(110, 77, 46)

local ACCENT = Color3.fromRGB(204, 144, 71)
local ACCENT_LIGHT = Color3.fromRGB(231, 179, 109)
local ACCENT_DARK = Color3.fromRGB(140, 84, 35)

local TEXT_COLOR = Color3.fromRGB(255, 248, 236)
local TEXT_STROKE = Color3.fromRGB(92, 53, 27)
local TRACK = Color3.fromRGB(89, 56, 30)
local TRACK_STROKE = Color3.fromRGB(120, 78, 45)

--============================================================
-- ESTADO
--============================================================

local loading = false
local destinationText = "MUNDO"
local loadingStartedAt = 0
local dotToken = 0

local controls = nil
local controlsLocked = false
local movementConnection = nil

--============================================================
-- CONTROLES
--============================================================

local function getControls()
	if controls then
		return controls
	end

	local playerScripts = player:FindFirstChild("PlayerScripts")
		or player:WaitForChild("PlayerScripts", 10)

	if not playerScripts then
		return nil
	end

	local playerModule = playerScripts:FindFirstChild("PlayerModule")
		or playerScripts:WaitForChild("PlayerModule", 10)

	if not playerModule then
		return nil
	end

	local ok, module = pcall(require, playerModule)
	if ok and module and module.GetControls then
		controls = module:GetControls()
	end

	return controls
end

local function stopCharacterMotion()
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")

	if humanoid then
		humanoid:Move(Vector3.zero, false)
	end

	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

local function lockControls()
	if controlsLocked then
		return
	end

	controlsLocked = true

	task.spawn(function()
		local currentControls = getControls()
		if currentControls and controlsLocked then
			pcall(function()
				currentControls:Disable()
			end)
		end
	end)

	stopCharacterMotion()

	if movementConnection then
		movementConnection:Disconnect()
	end

	movementConnection = RunService.RenderStepped:Connect(function()
		if controlsLocked then
			stopCharacterMotion()
		end
	end)
end

local function unlockControls()
	controlsLocked = false

	if movementConnection then
		movementConnection:Disconnect()
		movementConnection = nil
	end

	local currentControls = controls or getControls()
	if currentControls then
		pcall(function()
			currentControls:Enable()
		end)
	end
end

player.CharacterAdded:Connect(function()
	if controlsLocked then
		task.defer(stopCharacterMotion)
	end
end)

--============================================================
-- LIMPIAR GUI ANTERIOR
--============================================================

local oldGui = playerGui:FindFirstChild("WorldTeleportLoadingGui")
if oldGui then
	oldGui:Destroy()
end

--============================================================
-- GUI
--============================================================

local gui = Instance.new("ScreenGui")
gui.Name = "WorldTeleportLoadingGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 1000001
gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
gui.Parent = playerGui

local group = Instance.new("CanvasGroup")
group.Name = "LoadingGroup"
group.Size = UDim2.fromScale(1, 1)
group.BackgroundColor3 = BG_MIDDLE
group.BackgroundTransparency = 0
group.BorderSizePixel = 0
group.GroupTransparency = 0
group.Parent = gui

local backgroundGradient = Instance.new("UIGradient")
backgroundGradient.Rotation = 90
backgroundGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, BG_TOP),
	ColorSequenceKeypoint.new(0.52, BG_MIDDLE),
	ColorSequenceKeypoint.new(1.00, BG_BOTTOM),
})
backgroundGradient.Parent = group

local content = Instance.new("Frame")
content.Name = "Content"
content.AnchorPoint = Vector2.new(0.5, 0.5)
content.Position = UDim2.fromScale(0.5, 0.52)
content.Size = UDim2.fromOffset(1040, 620)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ZIndex = 5
content.Parent = group

local contentScale = Instance.new("UIScale")
contentScale.Name = "ResponsiveScale"
contentScale.Scale = 1
contentScale.Parent = content

local finishScale = Instance.new("UIScale")
finishScale.Name = "FinishScale"
finishScale.Scale = 1
finishScale.Parent = content

local function updateResponsiveScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	contentScale.Scale = math.clamp(
		math.min(viewport.X / 1280, viewport.Y / 720),
		0.54,
		1.10
	)
end

local cameraConnection = nil

local function bindCameraViewport()
	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end

	local camera = workspace.CurrentCamera
	if camera then
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale)
	end

	updateResponsiveScale()
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCameraViewport)
bindCameraViewport()

--============================================================
-- LOGO
--============================================================

local logo = Instance.new("ImageLabel")
logo.Name = "GameLogo"
logo.AnchorPoint = Vector2.new(0.5, 0)
logo.Position = UDim2.new(0.5, 0, 0, 8)
logo.Size = UDim2.fromOffset(860, 390)
logo.BackgroundTransparency = 1
logo.BorderSizePixel = 0
logo.Image = LOGO_IMAGE
logo.ScaleType = Enum.ScaleType.Fit
logo.ZIndex = 8
logo.Parent = content

local logoScale = Instance.new("UIScale")
logoScale.Name = "LogoScale"
logoScale.Scale = 1
logoScale.Parent = logo

-- Precalienta el logo antes de que el jugador toque un portal.
task.spawn(function()
	pcall(function()
		ContentProvider:PreloadAsync({logo})
	end)
end)

--============================================================
-- TEXTO
--============================================================

local title = Instance.new("TextLabel")
title.Name = "LoadingTitle"
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0, 362)
title.Size = UDim2.fromOffset(840, 70)
title.BackgroundTransparency = 1
title.BorderSizePixel = 0
title.Font = Enum.Font.FredokaOne
title.Text = "VIAJANDO..."
title.TextColor3 = TEXT_COLOR
title.TextScaled = true
title.TextStrokeColor3 = TEXT_STROKE
title.TextStrokeTransparency = 0.08
title.ZIndex = 8
title.Parent = content

local titleConstraint = Instance.new("UITextSizeConstraint")
titleConstraint.MinTextSize = 26
titleConstraint.MaxTextSize = 52
titleConstraint.Parent = title

--============================================================
-- BARRA
--============================================================

local barHolder = Instance.new("Frame")
barHolder.Name = "BarHolder"
barHolder.AnchorPoint = Vector2.new(0.5, 0)
barHolder.Position = UDim2.new(0.5, 0, 0, 458)
barHolder.Size = UDim2.fromOffset(660, 44)
barHolder.BackgroundTransparency = 1
barHolder.BorderSizePixel = 0
barHolder.ZIndex = 8
barHolder.Parent = content

local barBack = Instance.new("Frame")
barBack.Name = "ProgressBack"
barBack.AnchorPoint = Vector2.new(0.5, 0)
barBack.Position = UDim2.new(0.5, 0, 0, 0)
barBack.Size = UDim2.fromOffset(640, 24)
barBack.BackgroundColor3 = TRACK
barBack.BackgroundTransparency = 0.02
barBack.BorderSizePixel = 0
barBack.ClipsDescendants = true
barBack.ZIndex = 9
barBack.Parent = barHolder

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 12)
barCorner.Parent = barBack

local barStroke = Instance.new("UIStroke")
barStroke.Color = TRACK_STROKE
barStroke.Thickness = 2
barStroke.Transparency = 0.05
barStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
barStroke.Parent = barBack

local fill = Instance.new("Frame")
fill.Name = "ProgressFill"
fill.Size = UDim2.fromScale(0.03, 1)
fill.BackgroundColor3 = ACCENT
fill.BorderSizePixel = 0
fill.ZIndex = 10
fill.Parent = barBack

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 12)
fillCorner.Parent = fill

local fillGradient = Instance.new("UIGradient")
fillGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, ACCENT_DARK),
	ColorSequenceKeypoint.new(0.45, ACCENT),
	ColorSequenceKeypoint.new(1.00, ACCENT_LIGHT),
})
fillGradient.Parent = fill

local shine = Instance.new("Frame")
shine.Name = "Shine"
shine.Position = UDim2.fromScale(0, 0.08)
shine.Size = UDim2.fromScale(1, 0.28)
shine.BackgroundColor3 = Color3.fromRGB(255, 234, 192)
shine.BackgroundTransparency = 0.52
shine.BorderSizePixel = 0
shine.ZIndex = 11
shine.Parent = fill

local shineCorner = Instance.new("UICorner")
shineCorner.CornerRadius = UDim.new(0, 12)
shineCorner.Parent = shine

--============================================================
-- ANIMACIONES
--============================================================

task.spawn(function()
	while gui.Parent do
		if loading then
			local up = TweenService:Create(
				logoScale,
				TweenInfo.new(1.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{Scale = 1.02}
			)
			up:Play()
			up.Completed:Wait()

			if loading then
				local down = TweenService:Create(
					logoScale,
					TweenInfo.new(1.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{Scale = 1}
				)
				down:Play()
				down.Completed:Wait()
			end
		else
			logoScale.Scale = 1
			task.wait(0.1)
		end
	end
end)

local progressConnection = RunService.RenderStepped:Connect(function(dt)
	if not loading then
		return
	end

	local elapsed = os.clock() - loadingStartedAt

	-- Sube rapido al inicio y se queda en 92% esperando a Roblox.
	local target = 0.92 - (0.89 * math.exp(-elapsed * 3.25))
	target = math.clamp(target, 0.03, 0.92)

	local current = fill.Size.X.Scale
	local nextValue = current + (target - current) * math.clamp(dt * 7.5, 0, 1)

	fill.Size = UDim2.fromScale(nextValue, 1)
end)

local function startDots()
	dotToken += 1
	local myToken = dotToken

	task.spawn(function()
		local dots = 1

		while loading and myToken == dotToken do
			title.Text = "VIAJANDO A " .. destinationText .. string.rep(".", dots)

			dots += 1
			if dots > 3 then
				dots = 1
			end

			task.wait(0.34)
		end
	end)
end

--============================================================
-- MOSTRAR / OCULTAR
--============================================================

local function cleanDestinationName(value)
	local text = tostring(value or "MUNDO")
	text = text:gsub("^%s+", ""):gsub("%s+$", "")

	if text == "" then
		text = "MUNDO"
	end

	return string.upper(text)
end

local function showLoading(destinationName)
	destinationText = cleanDestinationName(destinationName)
	loading = true
	loadingStartedAt = os.clock()

	gui.Enabled = true
	group.GroupTransparency = 0
	finishScale.Scale = 1
	logoScale.Scale = 1
	fill.Size = UDim2.fromScale(0.03, 1)

	title.TextColor3 = TEXT_COLOR
	title.TextStrokeColor3 = TEXT_STROKE

	lockControls()
	startDots()

	-- Hace que esta misma interfaz sea la que Roblox mantenga
	-- durante la transición entre Places.
	pcall(function()
		TeleportService:SetTeleportGui(gui)
	end)
end

local function hideLoading(message)
	if not loading then
		return
	end

	loading = false
	dotToken += 1

	title.Text = tostring(message or "NO SE PUDO VIAJAR. INTENTA OTRA VEZ.")
	fill.Size = UDim2.fromScale(0.03, 1)

	task.spawn(function()
		task.wait(0.85)

		if loading then
			return
		end

		local fade = TweenService:Create(
			group,
			TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{GroupTransparency = 1}
		)

		local shrink = TweenService:Create(
			finishScale,
			TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{Scale = 0.97}
		)

		fade:Play()
		shrink:Play()
		fade.Completed:Wait()

		if loading then
			return
		end

		gui.Enabled = false
		group.GroupTransparency = 0
		finishScale.Scale = 1
		unlockControls()
	end)
end

--============================================================
-- REMOTE
--============================================================

remote.OnClientEvent:Connect(function(action, message)
	if action == "Show" then
		showLoading(message)
	elseif action == "Hide" then
		hideLoading(message)
	end
end)