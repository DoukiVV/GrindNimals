--============================================================
-- GAME START LOADING CLIENT - UNIVERSAL V8
--
-- UBICACION:
-- ReplicatedFirst > GameStartLoadingClient
-- Tipo: LocalScript
--
-- CAMBIOS:
-- - Quitado el fondo raro detras del logo.
-- - Fondo general mas oscuro y limpio.
-- - Logo mucho mas grande.
-- - Barra de progreso visible.
-- - Duracion minima 5 segundos.
-- - Salida final mucho mas rapida para que no se quede estorbando.
--============================================================

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local playerGui = player:WaitForChild("PlayerGui")

--============================================================
-- CONFIG
--============================================================

local LOGO_IMAGE = "rbxassetid://77375619575374"

-- Fondo mas oscuro y limpio, sin manchas raras.
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

local MIN_VISIBLE_TIME = 5.0
local SERVER_LOADING_GRACE = 0.65
local MAX_WAIT_TIME = 45

local startedAt = os.clock()
local closing = false

--============================================================
-- BLOQUEAR MOVIMIENTO
--============================================================

local controls = nil
local controlsLocked = true
local renderConnection = nil

local function getControls()
	if controls then return controls end

	local playerScripts = player:FindFirstChild("PlayerScripts") or player:WaitForChild("PlayerScripts", 10)
	if not playerScripts then return nil end

	local playerModule = playerScripts:FindFirstChild("PlayerModule") or playerScripts:WaitForChild("PlayerModule", 10)
	if not playerModule then return nil end

	local ok, module = pcall(require, playerModule)
	if ok and module and module.GetControls then
		controls = module:GetControls()
	end
	return controls
end

local function stopCharacterMotion()
	local character = player.Character
	if not character then return end

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

local function disableControls()
	controlsLocked = true
	task.spawn(function()
		local c = getControls()
		if c and controlsLocked then
			pcall(function() c:Disable() end)
		end
	end)
	stopCharacterMotion()
end

local function enableControls()
	controlsLocked = false
	local c = controls or getControls()
	if c then
		pcall(function() c:Enable() end)
	end
end

disableControls()

player.CharacterAdded:Connect(function()
	if controlsLocked then
		task.wait(0.05)
		disableControls()
	end
end)

renderConnection = RunService.RenderStepped:Connect(function()
	if controlsLocked then
		stopCharacterMotion()
	end
end)

--============================================================
-- LIMPIAR GUI ANTERIOR
--============================================================

local oldGui = playerGui:FindFirstChild("GameStartLoadingGui")
if oldGui then
	oldGui:Destroy()
end

--============================================================
-- GUI
--============================================================

local gui = Instance.new("ScreenGui")
gui.Name = "GameStartLoadingGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000000
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
	contentScale.Scale = math.clamp(math.min((viewport.X - 24) / 1040, (viewport.Y - 24) / 620), 0.1, 1.10)
end

updateResponsiveScale()

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

task.spawn(function()
	while gui.Parent and not closing do
		local up = TweenService:Create(logoScale, TweenInfo.new(1.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Scale = 1.02})
		up:Play()
		up.Completed:Wait()
		if not gui.Parent or closing then break end
		local down = TweenService:Create(logoScale, TweenInfo.new(1.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Scale = 1})
		down:Play()
		down.Completed:Wait()
	end
end)

--============================================================
-- TEXTO
--============================================================

local title = Instance.new("TextLabel")
title.Name = "LoadingTitle"
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0, 362)
title.Size = UDim2.fromOffset(760, 70)
title.BackgroundTransparency = 1
title.BorderSizePixel = 0
title.Font = Enum.Font.FredokaOne
title.Text = "CARGANDO LOBBY..."
title.TextColor3 = TEXT_COLOR
title.TextScaled = true
title.TextStrokeColor3 = TEXT_STROKE
title.TextStrokeTransparency = 0.08
title.ZIndex = 8
title.Parent = content

local titleConstraint = Instance.new("UITextSizeConstraint")
titleConstraint.MinTextSize = 28
titleConstraint.MaxTextSize = 52
titleConstraint.Parent = title

task.spawn(function()
	local dotCount = 1
	while gui.Parent and not closing do
		title.Text = "CARGANDO LOBBY" .. string.rep(".", dotCount)
		dotCount += 1
		if dotCount > 3 then dotCount = 1 end
		task.wait(0.38)
	end
end)

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
-- PROGRESO
--============================================================

local visualProgress = 0.03
local targetProgress = 0.03
local gameLoaded = game:IsLoaded()
local clientReadyAt = nil

if not gameLoaded then
	task.spawn(function()
		game.Loaded:Wait()
		gameLoaded = true
		clientReadyAt = os.clock()
	end)
else
	clientReadyAt = os.clock()
end

local function characterIsReady()
	local character = player.Character
	if not character then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	return humanoid ~= nil and root ~= nil
end

local function serverStillLoading()
	if player:GetAttribute("GameStartLoading") == true then
		return true
	end
	local worldReady = player:GetAttribute("WorldReady")
	if worldReady == false then
		return true
	end
	return false
end

local function minTimeProgress()
	local elapsed = os.clock() - startedAt
	local alpha = math.clamp(elapsed / MIN_VISIBLE_TIME, 0, 1)
	return 0.03 + (0.92 - 0.03) * alpha
end

local function computeTargetProgress()
	local timeBased = minTimeProgress()
	if not gameLoaded then
		return math.min(timeBased, 0.62)
	end
	if not characterIsReady() then
		return math.min(math.max(timeBased, 0.68), 0.78)
	end
	if serverStillLoading() then
		return math.min(math.max(timeBased, 0.82), 0.92)
	end
	return timeBased
end

local progressConnection = RunService.RenderStepped:Connect(function(dt)
	if closing then return end
	targetProgress = computeTargetProgress()
	visualProgress += (targetProgress - visualProgress) * math.clamp(dt * 5.2, 0, 1)
	fill.Size = UDim2.fromScale(math.clamp(visualProgress, 0.03, 0.92), 1)
end)

--============================================================
-- TERMINAR
--============================================================

local function finishLoading()
	if closing then return end
	closing = true

	local elapsed = os.clock() - startedAt
	if elapsed < MIN_VISIBLE_TIME then
		task.wait(MIN_VISIBLE_TIME - elapsed)
	end

	local completeTween = TweenService:Create(fill, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.fromScale(1, 1)})
	completeTween:Play()
	completeTween.Completed:Wait()

	title.Text = "¡LISTO!"

	local pop1 = TweenService:Create(logoScale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1.06})
	local pop2 = TweenService:Create(finishScale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1.02})
	pop1:Play(); pop2:Play()
	pop2.Completed:Wait()

	local fade = TweenService:Create(group, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {GroupTransparency = 1})
	local exitScale = TweenService:Create(finishScale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0.96})
	local strokeFade = TweenService:Create(barStroke, TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 1})
	fade:Play(); exitScale:Play(); strokeFade:Play()
	fade.Completed:Wait()

	if progressConnection then progressConnection:Disconnect() progressConnection = nil end
	if renderConnection then renderConnection:Disconnect() renderConnection = nil end
	if cameraConnection then cameraConnection:Disconnect() cameraConnection = nil end
	if gui.Parent then gui:Destroy() end
	enableControls()
end

--============================================================
-- ESPERAR LISTO
--============================================================

task.spawn(function()
	while gui.Parent and not gameLoaded do
		if os.clock() - startedAt >= MAX_WAIT_TIME then
			finishLoading()
			return
		end
		task.wait(0.05)
	end

	if clientReadyAt then
		local graceLeft = SERVER_LOADING_GRACE - (os.clock() - clientReadyAt)
		if graceLeft > 0 then
			task.wait(graceLeft)
		end
	else
		task.wait(SERVER_LOADING_GRACE)
	end

	while gui.Parent do
		local elapsed = os.clock() - startedAt
		local ready = gameLoaded and characterIsReady() and not serverStillLoading()
		if ready and elapsed >= MIN_VISIBLE_TIME then
			finishLoading()
			return
		end
		if elapsed >= MAX_WAIT_TIME then
			warn("[GameStartLoading] Tiempo maximo alcanzado; cerrando pantalla.")
			finishLoading()
			return
		end
		task.wait(0.08)
	end
end)