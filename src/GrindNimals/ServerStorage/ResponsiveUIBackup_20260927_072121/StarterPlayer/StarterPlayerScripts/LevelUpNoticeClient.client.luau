--============================================================
-- LEVEL UP NOTICE CLIENT V2
--
-- TIPO:
-- LocalScript
--
-- PONER EN:
-- StarterPlayer > StarterPlayerScripts
--
-- V2:
-- YA NO observa leaderstats.Nivel directamente.
-- Solo muestra la animacion cuando el servidor confirma
-- que el jugador SUBIO DE NIVEL GANANDO XP.
--
-- Esto elimina la falsa alerta al entrar a AdentroCasaJugadores.
--============================================================

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local TweenService =
	game:GetService("TweenService")

local player =
	Players.LocalPlayer

local playerGui =
	player:WaitForChild("PlayerGui")

------------------------------------------------------------
-- GUI
------------------------------------------------------------

local gui =
	playerGui:FindFirstChild(
		"AdminLevelNoticeGui"
	)

if not gui then
	gui = Instance.new("ScreenGui")
	gui.Name = "AdminLevelNoticeGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	gui.Parent = playerGui
else
	gui.DisplayOrder = 1000
end

local holder =
	gui:FindFirstChild(
		"PersistentLevelNotice"
	)

if not holder then
	holder = Instance.new("Frame")
	holder.Name = "PersistentLevelNotice"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.38)
	holder.Size = UDim2.fromOffset(560, 128)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Name = "NoticeScale"
	scale.Scale = 0.4
	scale.Parent = holder

	local glow = Instance.new("TextLabel")
	glow.Name = "Glow"
	glow.BackgroundTransparency = 1
	glow.Size = UDim2.fromScale(1, 1)
	glow.Font = Enum.Font.FredokaOne
	glow.TextColor3 = Color3.fromRGB(255, 197, 73)
	glow.TextTransparency = 1
	glow.TextStrokeTransparency = 1
	glow.TextScaled = true
	glow.Parent = holder

	local shadow = Instance.new("TextLabel")
	shadow.Name = "Shadow"
	shadow.BackgroundTransparency = 1
	shadow.Position = UDim2.fromOffset(4, 5)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Font = Enum.Font.FredokaOne
	shadow.TextColor3 = Color3.fromRGB(54, 29, 8)
	shadow.TextStrokeColor3 = Color3.fromRGB(54, 29, 8)
	shadow.TextStrokeTransparency = 1
	shadow.TextTransparency = 1
	shadow.TextScaled = true
	shadow.Parent = holder

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextColor3 = Color3.fromRGB(255, 248, 205)
	text.TextStrokeColor3 = Color3.fromRGB(78, 42, 10)
	text.TextTransparency = 1
	text.TextStrokeTransparency = 1
	text.TextScaled = true
	text.Parent = holder
end

local scale =
	holder:WaitForChild(
		"NoticeScale"
	)

local glow =
	holder:WaitForChild("Glow")

local shadow =
	holder:WaitForChild("Shadow")

local text =
	holder:WaitForChild("Text")

local activeTweens = {}
local lastLevel = nil
local lastShownAt = 0

------------------------------------------------------------
-- ANIMACION
------------------------------------------------------------

local function stopTweens()
	for _, tween in ipairs(
		activeTweens
		) do
		tween:Cancel()
	end

	table.clear(activeTweens)
end

local function playTween(
	instance,
	tweenInfo,
	goal
)
	local tween =
		TweenService:Create(
			instance,
			tweenInfo,
			goal
		)

	table.insert(
		activeTweens,
		tween
	)

	tween:Play()

	return tween
end

local function showNotice(level)
	level =
		math.floor(
			tonumber(level)
			or 0
		)

	if level <= 0 then
		return
	end

	-- Seguridad extra durante carga.
	if player:GetAttribute("SuppressLevelUpNotice") == true or player:GetAttribute("TutorialLocked") == true then
		return
	end

	local now =
		os.clock()

	if lastLevel == level
		and now - lastShownAt < 0.8
	then
		return
	end

	lastLevel = level
	lastShownAt = now

	stopTweens()

	local message =
		"Subiste a nivel "
		.. tostring(level)

	text.Text = message
	glow.Text = message
	shadow.Text = message

	text.TextTransparency = 0
	text.TextStrokeTransparency = 0
	shadow.TextTransparency = 0.08
	shadow.TextStrokeTransparency = 0
	glow.TextTransparency = 0.35

	holder.Visible = true
	holder.Position = UDim2.fromScale(0.5, 0.45)
	holder.Rotation = -12
	scale.Scale = 0.18

	playTween(
		scale,
		TweenInfo.new(
			0.46,
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out
		),
		{
			Scale = 1.18,
		}
	)

	playTween(
		holder,
		TweenInfo.new(
			0.46,
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out
		),
		{
			Rotation = 1,
			Position =
				UDim2.fromScale(
					0.5,
					0.4
				),
		}
	)

	task.delay(
		0.42,
		function()
			if not holder.Visible then
				return
			end

			playTween(
				scale,
				TweenInfo.new(
					0.18,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				),
				{
					Scale = 0.94,
				}
			)

			task.wait(0.18)

			if holder.Visible then
				playTween(
					scale,
					TweenInfo.new(
						0.2,
						Enum.EasingStyle.Back,
						Enum.EasingDirection.Out
					),
					{
						Scale = 1,
					}
				)
			end
		end
	)

	task.delay(
		4,
		function()
			if not holder.Visible
				or lastLevel ~= level
			then
				return
			end

			playTween(
				holder,
				TweenInfo.new(
					0.45,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				),
				{
					Position =
						UDim2.fromScale(
							0.5,
							0.28
						),
					Rotation = 5,
				}
			)

			playTween(
				scale,
				TweenInfo.new(
					0.45,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				),
				{
					Scale = 0.78,
				}
			)

			playTween(
				text,
				TweenInfo.new(
					0.45,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				),
				{
					TextTransparency = 1,
					TextStrokeTransparency = 1,
				}
			)

			playTween(
				shadow,
				TweenInfo.new(
					0.45,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				),
				{
					TextTransparency = 1,
					TextStrokeTransparency = 1,
				}
			)

			playTween(
				glow,
				TweenInfo.new(
					0.45,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				),
				{
					TextTransparency = 1,
				}
			)

			task.wait(0.48)

			if lastLevel == level then
				holder.Visible = false
			end
		end
	)
end

------------------------------------------------------------
-- SOLO ESCUCHA EL EVENTO DEL SERVIDOR
--
-- IMPORTANTE:
-- Se elimino por completo el listener:
-- leaderstats.Nivel.Changed
--
-- Ese era el que confundia:
-- Nivel temporal 1 -> Nivel guardado 5
-- con una subida real.
------------------------------------------------------------

local remote =
	ReplicatedStorage:WaitForChild(
		"AdminLevelUpNotice",
		20
	)

if remote
	and remote:IsA("RemoteEvent")
then
	remote.OnClientEvent:Connect(
		showNotice
	)
else
	warn(
		"[LevelNotice] No encontre AdminLevelUpNotice."
	)
end
