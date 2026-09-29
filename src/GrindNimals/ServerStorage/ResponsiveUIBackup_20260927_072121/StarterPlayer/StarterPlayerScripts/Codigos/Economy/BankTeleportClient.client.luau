--============================================================
-- BANCO - ANIMACION DE TELETRANSPORTE
--
-- COLOCAR EN:
-- StarterPlayer > StarterPlayerScripts > BankTeleportClient
--
-- Se crea sola:
-- - pantalla oscura
-- - blur
-- - zoom leve
-- - texto FredokaOne
--
-- No necesitas crear GUI manualmente.
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
		"BankTeleportFX"
	)

--============================================================
-- CONFIG
--============================================================

local FADE_OUT_TIME = 0.28
local FADE_IN_TIME = 0.42

local MAX_BLUR = 18
local FOV_ZOOM = 5

--============================================================
-- GUI
--============================================================

local oldGui =
	playerGui:FindFirstChild(
		"BankTeleportGui"
	)

if oldGui then
	oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "BankTeleportGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 50000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.fromRGB(5, 6, 8)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.Visible = false
overlay.ZIndex = 1
overlay.Parent = gui

local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0.5, 0.5)
status.Position = UDim2.fromScale(0.5, 0.55)
status.Size = UDim2.fromScale(0.90, 0.14)
status.BackgroundTransparency = 1
status.Text = ""
status.Font = Enum.Font.FredokaOne
status.TextColor3 = Color3.fromRGB(255, 255, 255)
status.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
status.TextStrokeTransparency = 0.18
status.TextTransparency = 1
status.TextScaled = true
status.ZIndex = 2
status.Parent = overlay

local constraint = Instance.new("UITextSizeConstraint")
constraint.MinTextSize = 28
constraint.MaxTextSize = 52
constraint.Parent = status

local statusScale = Instance.new("UIScale")
statusScale.Scale = 0.94
statusScale.Parent = status

--============================================================
-- BLUR
--============================================================

local oldBlur =
	Lighting:FindFirstChild(
		"BankTeleportBlur"
	)

if oldBlur then
	oldBlur:Destroy()
end

local blur = Instance.new("BlurEffect")
blur.Name = "BankTeleportBlur"
blur.Size = 0
blur.Enabled = false
blur.Parent = Lighting

--============================================================
-- ANIMACION
--============================================================

local tweens = {}
local token = 0
local savedFov = nil

local function cancelTweens()
	for _, tween in ipairs(tweens) do
		pcall(function()
			tween:Cancel()
		end)
	end

	table.clear(tweens)
end

local function playTween(object, info, goal)
	local tween =
		TweenService:Create(
			object,
			info,
			goal
		)

	table.insert(tweens, tween)

	tween:Play()

	return tween
end

local function fadeOut(message)
	token += 1
	cancelTweens()

	local thisToken = token

	local camera =
		Workspace.CurrentCamera

	overlay.Visible = true
	overlay.BackgroundTransparency = 1

	status.Text =
		tostring(message or "")

	status.TextTransparency = 1
	status.TextStrokeTransparency = 1
	statusScale.Scale = 0.92

	blur.Enabled = true
	blur.Size = 0

	if camera then
		savedFov =
			camera.FieldOfView
	end

	playTween(
		overlay,
		TweenInfo.new(
			FADE_OUT_TIME,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut
		),
		{
			BackgroundTransparency = 0
		}
	)

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

	task.delay(0.04, function()
		if thisToken ~= token then
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
				TextTransparency = 0,
				TextStrokeTransparency = 0.18,
			}
		)

		playTween(
			statusScale,
			TweenInfo.new(
				0.24,
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out
			),
			{
				Scale = 1
			}
		)
	end)
end

local function fadeIn()
	token += 1
	cancelTweens()

	local thisToken = token

	local camera =
		Workspace.CurrentCamera

	playTween(
		status,
		TweenInfo.new(
			0.14,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		),
		{
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	)

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
		playTween(
			camera,
			TweenInfo.new(
				FADE_IN_TIME,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut
			),
			{
				FieldOfView =
					savedFov
					or camera.FieldOfView
			}
		)
	end

	task.delay(
		FADE_IN_TIME + 0.04,
		function()
			if thisToken ~= token then
				return
			end

			overlay.Visible = false
			blur.Enabled = false
			blur.Size = 0
		end
	)
end

remote.OnClientEvent:Connect(
	function(action, message)
		if action == "Out" then
			fadeOut(message)

		elseif action == "In" then
			fadeIn()
		end
	end
)

player.CharacterAdded:Connect(function()
	token += 1
	cancelTweens()

	overlay.Visible = false
	overlay.BackgroundTransparency = 1

	status.TextTransparency = 1

	blur.Size = 0
	blur.Enabled = false

	local camera =
		Workspace.CurrentCamera

	if camera and savedFov then
		camera.FieldOfView = savedFov
	end
end)