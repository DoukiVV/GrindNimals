-- PortalTextAnimationsClient V2.1 SUAVE
-- Ubicacion: StarterPlayer > StarterPlayerScripts
-- Tipo: LocalScript

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local SHOW_DISTANCE = 72
local HIDE_DISTANCE = 88

local FLOAT_HEIGHT = 0.10
local FLOAT_SPEED = 2.15
local PULSE_AMOUNT = 0.018
local PULSE_SPEED = 2.8
local ROTATION_AMOUNT = 0.45
local ROTATION_SPEED = 1.75

local tracked = {}
local rootPart

local function setupCharacter(character)
	rootPart = character:WaitForChild("HumanoidRootPart", 10)
end

if player.Character then
	task.spawn(setupCharacter, player.Character)
end
player.CharacterAdded:Connect(setupCharacter)

local function lower(v)
	return string.lower(tostring(v or ""))
end

local function isPortalGui(gui)
	if gui:GetAttribute("PortalAnimated") == true then
		return true
	end

	local current = gui
	for _ = 1, 8 do
		current = current.Parent
		if not current then break end

		local n = lower(current.Name)
		if string.find(n, "portal", 1, true) then
			return true
		end
		if string.sub(n, 1, 2) == "tp" then
			return true
		end
	end

	return false
end

local function findLabel(gui)
	for _, obj in ipairs(gui:GetDescendants()) do
		if obj:IsA("TextLabel") then
			return obj
		end
	end
end

local function worldPosition(gui)
	if gui.Adornee then
		if gui.Adornee:IsA("Attachment") then
			return gui.Adornee.WorldPosition
		elseif gui.Adornee:IsA("BasePart") then
			return gui.Adornee.Position
		end
	end

	local current = gui.Parent
	for _ = 1, 8 do
		if not current then break end

		if current:IsA("Attachment") then
			return current.WorldPosition
		elseif current:IsA("BasePart") then
			return current.Position
		elseif current:IsA("Model") then
			if current.PrimaryPart then
				return current.PrimaryPart.Position
			end
			local p = current:FindFirstChildWhichIsA("BasePart", true)
			if p then return p.Position end
		end

		current = current.Parent
	end
end

local function getScale(label)
	local s = label:FindFirstChild("PortalAnimatedScale")
	if not s then
		s = Instance.new("UIScale")
		s.Name = "PortalAnimatedScale"
		s.Parent = label
	end
	return s
end

local function cancelTweens(data)
	for _, tw in ipairs(data.tweens) do
		pcall(function() tw:Cancel() end)
	end
	table.clear(data.tweens)
end

local function tween(data, object, info, goal)
	local tw = TweenService:Create(object, info, goal)
	table.insert(data.tweens, tw)
	tw:Play()
	return tw
end

local function show(data)
	if data.visible then return end
	data.visible = true
	data.inIntro = true
	cancelTweens(data)

	data.gui.Enabled = true
	data.scale.Scale = 0.88
	data.label.TextTransparency = 1
	data.label.Rotation = 0
	data.gui.StudsOffsetWorldSpace = data.baseOffset + Vector3.new(0, -0.12, 0)

	if data.stroke then
		data.stroke.Transparency = 1
	end

	local pop = tween(
		data,
		data.scale,
		TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = 1.03}
	)

	tween(
		data,
		data.label,
		TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			TextTransparency = data.baseTextTransparency,
			Rotation = 0
		}
	)

	tween(
		data,
		data.gui,
		TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{StudsOffsetWorldSpace = data.baseOffset}
	)

	if data.stroke then
		tween(
			data,
			data.stroke,
			TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Transparency = data.baseStrokeTransparency}
		)
	end

	task.spawn(function()
		pop.Completed:Wait()
		if not data.visible or not data.gui.Parent then return end

		local settle = TweenService:Create(
			data.scale,
			TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{Scale = 1}
		)
		settle:Play()
		settle.Completed:Wait()

		if data.visible then
			data.inIntro = false
		end
	end)
end

local function hide(data)
	if not data.visible then return end

	data.visible = false
	data.inIntro = false
	cancelTweens(data)

	-- Salida suave:
	-- 1) se hace apenas mas pequeño
	-- 2) sube un poquito
	-- 3) texto y contorno desaparecen con fade
	local startOffset = data.gui.StudsOffsetWorldSpace

	local moveTween = tween(
		data,
		data.gui,
		TweenInfo.new(0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{
			StudsOffsetWorldSpace = data.baseOffset + Vector3.new(0, 0.18, 0)
		}
	)

	tween(
		data,
		data.scale,
		TweenInfo.new(0.30, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{Scale = 0.90}
	)

	tween(
		data,
		data.label,
		TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			TextTransparency = 1,
			Rotation = 0
		}
	)

	if data.stroke then
		tween(
			data,
			data.stroke,
			TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Transparency = 1}
		)
	end

	task.spawn(function()
		moveTween.Completed:Wait()

		if not data.visible and data.gui.Parent then
			data.gui.Enabled = false

			-- Dejar todo listo para la proxima entrada.
			data.gui.StudsOffsetWorldSpace = data.baseOffset
			data.scale.Scale = 1
			data.label.Rotation = 0
		end
	end)
end

local function track(gui)
	if tracked[gui] or not gui:IsA("BillboardGui") or not isPortalGui(gui) then
		return
	end

	local label = findLabel(gui)
	if not label then return end

	local scale = getScale(label)
	local stroke = label:FindFirstChildOfClass("UIStroke")

	-- IMPORTANTE: deja que ESTE script controle la desaparicion.
	-- Si MaxDistance es bajo, Roblox ocultaria el BillboardGui de golpe
	-- antes de que se alcance a ver la animacion de salida.
	gui.MaxDistance = 1000

	tracked[gui] = {
		gui = gui,
		label = label,
		scale = scale,
		stroke = stroke,
		baseOffset = gui.StudsOffsetWorldSpace,
		baseTextTransparency = label.TextTransparency,
		baseStrokeTransparency = stroke and stroke.Transparency or 0,
		phase = math.random() * math.pi * 2,
		visible = false,
		inIntro = false,
		tweens = {},
	}

	gui.Enabled = false
end

local count = 0
for _, obj in ipairs(Workspace:GetDescendants()) do
	if obj:IsA("BillboardGui") and isPortalGui(obj) then
		track(obj)
		count += 1
	end
end

Workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("BillboardGui") then
		task.defer(function()
			if obj.Parent then
				track(obj)
			end
		end)
	end
end)

RunService.RenderStepped:Connect(function()
	if not rootPart or not rootPart.Parent then
		return
	end

	local now = os.clock()

	for gui, data in pairs(tracked) do
		if not gui.Parent or not data.label.Parent then
			tracked[gui] = nil
			continue
		end

		local pos = worldPosition(gui)
		if not pos then
			continue
		end

		local distance = (rootPart.Position - pos).Magnitude

		if not data.visible and distance <= SHOW_DISTANCE then
			show(data)
		elseif data.visible and distance >= HIDE_DISTANCE then
			hide(data)
		end

		if data.visible and not data.inIntro then
			local t = now + data.phase

			data.gui.StudsOffsetWorldSpace =
				data.baseOffset + Vector3.new(
					0,
					math.sin(t * FLOAT_SPEED) * FLOAT_HEIGHT,
					0
				)

			data.scale.Scale =
				1 + math.sin(t * PULSE_SPEED) * PULSE_AMOUNT

			data.label.Rotation =
				math.sin(t * ROTATION_SPEED) * ROTATION_AMOUNT
		end
	end
end)
