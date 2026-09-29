--============================================================
-- ANIMACION SUAVE DE TELETRANSPORTE
--
-- COLOCAR EN:
-- StarterPlayer > StarterPlayerScripts > VegetableShopTeleportClient
--
-- Crea automáticamente:
-- - Fade oscuro
-- - Blur
-- - Pequeño zoom de cámara
-- - Texto de entrada/salida
--
-- No necesitas crear ninguna interfaz manualmente.
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remote =
	ReplicatedStorage:WaitForChild(
		"VegetableShopTeleportFX"
	)

--============================================================
-- CONFIGURACION VISUAL
--============================================================

local FADE_OUT_TIME = 0.28
local FADE_IN_TIME = 0.42

local MAX_BLUR = 18
local FOV_ZOOM = 5

-- La pantalla no se vuelve negro absoluto inmediatamente.
-- Esto hace que la entrada sea más suave.
local OVERLAY_DARKNESS = 0

--============================================================
-- GUI
--============================================================

local oldGui =
	playerGui:FindFirstChild(
		"VegetableShopTeleportGui"
	)

if oldGui then
	oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "VegetableShopTeleportGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 10000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.Position = UDim2.fromScale(0, 0)
overlay.BorderSizePixel = 0
overlay.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
overlay.BackgroundTransparency = 1
overlay.Visible = false
overlay.ZIndex = 1
overlay.Parent = gui

-- Segunda capa para que el centro se sienta menos brusco.
local centerGlow = Instance.new("Frame")
centerGlow.Name = "CenterGlow"
centerGlow.AnchorPoint = Vector2.new(0.5, 0.5)
centerGlow.Position = UDim2.fromScale(0.5, 0.5)
centerGlow.Size = UDim2.fromScale(1.15, 1.15)
centerGlow.BorderSizePixel = 0
centerGlow.BackgroundColor3 = Color3.fromRGB(35, 43, 52)
centerGlow.BackgroundTransparency = 1
centerGlow.ZIndex = 2
centerGlow.Parent = overlay

local gradient = Instance.new("UIGradient")
gradient.Rotation = 90
gradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.15),
	NumberSequenceKeypoint.new(0.5, 0.7),
	NumberSequenceKeypoint.new(1, 0.15),
})
gradient.Parent = centerGlow

local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0.5, 0.5)
status.Position = UDim2.fromScale(0.5, 0.56)
status.Size = UDim2.fromScale(0.92, 0.14)
status.BackgroundTransparency = 1
status.Text = ""
status.Font = Enum.Font.FredokaOne
status.TextColor3 = Color3.fromRGB(245, 245, 245)
status.TextStrokeColor3 = Color3.fromRGB(25, 25, 25)
status.TextStrokeTransparency = 0.55
status.TextTransparency = 1
status.TextScaled = true
status.ZIndex = 3
status.Parent = overlay

local textConstraint = Instance.new("UITextSizeConstraint")
textConstraint.MinTextSize = 28
textConstraint.MaxTextSize = 52
textConstraint.Parent = status

local statusScale = Instance.new("UIScale")
statusScale.Scale = 0.96
statusScale.Parent = status

--============================================================
-- BLUR LOCAL
--============================================================

local oldBlur =
	Lighting:FindFirstChild(
		"VegetableShopTeleportBlur"
	)

if oldBlur then
	oldBlur:Destroy()
end

local blur = Instance.new("BlurEffect")
blur.Name = "VegetableShopTeleportBlur"
blur.Size = 0
blur.Enabled = false
blur.Parent = Lighting

--============================================================
-- TWEENS
--============================================================

local activeTweens = {}
local animationToken = 0
local savedFov = nil

local function cancelTweens()
	for _, tween in ipairs(activeTweens) do
		pcall(function()
			tween:Cancel()
		end)
	end

	table.clear(activeTweens)
end

local function playTween(instance, info, goals)
	local tween =
		TweenService:Create(
			instance,
			info,
			goals
		)

	table.insert(activeTweens, tween)
	tween:Play()

	return tween
end

local function getCamera()
	return Workspace.CurrentCamera
end

--============================================================
-- FADE OUT
--============================================================

local function fadeOut(message)
	animationToken += 1

	cancelTweens()

	local token = animationToken
	local camera = getCamera()

	overlay.Visible = true
	overlay.BackgroundTransparency = 1

	centerGlow.BackgroundTransparency = 1

	status.Text = tostring(message or "")
	status.TextTransparency = 1
	statusScale.Scale = 0.94

	blur.Enabled = true
	blur.Size = 0

	if camera then
		savedFov = camera.FieldOfView
	else
		savedFov = nil
	end

	-- Fondo oscuro.
	playTween(
		overlay,
		TweenInfo.new(
			FADE_OUT_TIME,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut
		),
		{
			BackgroundTransparency = OVERLAY_DARKNESS
		}
	)

	-- Glow suave.
	playTween(
		centerGlow,
		TweenInfo.new(
			FADE_OUT_TIME * 0.85,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		),
		{
			BackgroundTransparency = 0.72
		}
	)

	-- Blur progresivo.
	playTween(
		blur,
		TweenInfo.new(
			FADE_OUT_TIME,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut
		),
		{
			Size = MAX_BLUR
		}
	)

	-- Zoom muy ligero.
	if camera then
		playTween(
			camera,
			TweenInfo.new(
				FADE_OUT_TIME,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut
			),
			{
				FieldOfView =
					math.max(
						40,
						camera.FieldOfView - FOV_ZOOM
					)
			}
		)
	end

	-- Texto.
	task.delay(0.05, function()
		if token ~= animationToken then
			return
		end

		playTween(
			status,
			TweenInfo.new(
				0.18,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				TextTransparency = 0
			}
		)

		playTween(
			statusScale,
			TweenInfo.new(
				0.22,
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out
			),
			{
				Scale = 1
			}
		)
	end)
end

--============================================================
-- FADE IN
--============================================================

local function fadeIn()
	animationToken += 1

	cancelTweens()

	local token = animationToken
	local camera = getCamera()

	-- Texto desaparece primero.
	playTween(
		status,
		TweenInfo.new(
			0.14,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		),
		{
			TextTransparency = 1
		}
	)

	playTween(
		statusScale,
		TweenInfo.new(
			0.18,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		),
		{
			Scale = 1.03
		}
	)

	-- Abrir nuevamente la imagen.
	playTween(
		overlay,
		TweenInfo.new(
			FADE_IN_TIME,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut
		),
		{
			BackgroundTransparency = 1
		}
	)

	playTween(
		centerGlow,
		TweenInfo.new(
			FADE_IN_TIME * 0.75,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		),
		{
			BackgroundTransparency = 1
		}
	)

	playTween(
		blur,
		TweenInfo.new(
			FADE_IN_TIME,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut
		),
		{
			Size = 0
		}
	)

	if camera then
		local targetFov =
			savedFov
			or camera.FieldOfView

		playTween(
			camera,
			TweenInfo.new(
				FADE_IN_TIME,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut
			),
			{
				FieldOfView = targetFov
			}
		)
	end

	task.delay(
		FADE_IN_TIME + 0.05,

		function()
			if token ~= animationToken then
				return
			end

			overlay.Visible = false
			blur.Size = 0
			blur.Enabled = false
		end
	)
end

--============================================================
-- REMOTE
--============================================================

remote.OnClientEvent:Connect(
	function(action, message)

		if action == "Out" then
			fadeOut(message)

		elseif action == "In" then
			fadeIn()
		end

	end
)

--============================================================
-- LIMPIEZA SI EL PERSONAJE REAPARECE
--============================================================

player.CharacterAdded:Connect(function()
	animationToken += 1
	cancelTweens()

	overlay.Visible = false
	overlay.BackgroundTransparency = 1

	status.TextTransparency = 1

	blur.Size = 0
	blur.Enabled = false

	local camera = getCamera()

	if camera and savedFov then
		camera.FieldOfView = savedFov
	end
end)