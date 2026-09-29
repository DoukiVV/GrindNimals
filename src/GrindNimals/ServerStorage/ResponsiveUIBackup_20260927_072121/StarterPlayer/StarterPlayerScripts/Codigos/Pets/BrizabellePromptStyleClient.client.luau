local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local activeGuis = {}
local promptAnchors = {}
local promptAnchorConnections = {}
local promptAnchorStepNames = {}
local promptAnchorId = 0

local PROMPT_LABELS = {
	BrizabelleEggPrompt = { action = "Hablar", object = "Brizabelle" },

	-- Frank usa EXACTAMENTE el mismo diseño visual que Brizabelle.
	-- Solo cambia el texto y conserva su propio nombre de prompt para no abrir la tienda de huevos.
	PetUpgradePrompt = { action = "Hablar", object = "Frank" },

	-- Julian usa EXACTAMENTE el mismo diseño visual que Brizabelle.
	-- Solo cambia el texto y conserva su propio nombre de prompt.
	JulianSeedShopPrompt = { action = "Hablar", object = "Julian" },

	-- NPC DEL BANCO: cada uno muestra SU propio nombre.
	WilliamBankPrompt = {
		action = "Hablar",
		object = "William",
		keyCode = Enum.KeyCode.E,
		holdDuration = 0.55,
		minDistance = 14,
		studsOffset = Vector3.new(0, 3.35, 0),
	},

	DamianBankPrompt = {
		action = "Hablar",
		object = "Damian",
		keyCode = Enum.KeyCode.E,
		holdDuration = 0.55,
		minDistance = 12,
		studsOffset = Vector3.new(0, 3.35, 0),
	},

	WiwinBankPrompt = {
		action = "Hablar",
		object = "Wiwin",
		keyCode = Enum.KeyCode.E,
		holdDuration = 0.55,
		minDistance = 12,
		studsOffset = Vector3.new(0, 3.35, 0),
	},

	OliverBankPrompt = {
		action = "Hablar",
		object = "Oliver",
		keyCode = Enum.KeyCode.E,
		holdDuration = 0.55,
		minDistance = 12,
		studsOffset = Vector3.new(0, 3.35, 0),
	},

	OswaldBankPrompt = {
		action = "Hablar",
		object = "Oswald",
		keyCode = Enum.KeyCode.E,
		holdDuration = 0.55,
		minDistance = 12,
		studsOffset = Vector3.new(0, 3.35, 0),
	},

	-- Fuente de inicio diario: mismo diseño visual + ancla central.
	-- Mas distancia + pequeño hold para que no se pueda spamear con un toque.
	FuentePrompt = {
		action = "Ver inicio diario",
		object = "Fuente",
		keyCode = Enum.KeyCode.E,

		-- Mantener E evita spam accidental.
		holdDuration = 0.65,

		-- La distancia real la controla DailyLoginClient con FOUNTAIN_DISTANCE.
		-- Este valor es solo un minimo de seguridad.
		minDistance = 12,

		-- Tamaño SOLO del prompt de la fuente.
		guiSize = UDim2.fromOffset(230, 76),
		keySize = UDim2.fromOffset(50, 50),
		keyPosition = UDim2.fromOffset(7, 8),

		actionPosition = UDim2.fromOffset(68, 8),
		actionSize = UDim2.new(1, -76, 0, 29),

		objectPosition = UDim2.fromOffset(68, 39),
		objectSize = UDim2.new(1, -76, 0, 23),

		studsOffset = Vector3.new(0, 1.35, 0),
	},

	BrizabelleEggCleanPrompt = { action = "Limpiar", object = "Huevo" },
	BrizabelleEggBedPrompt = { action = "Dormir", object = "Mascota" },
	BrizabellePetMenuPrompt = { action = "", object = "", keyCode = Enum.KeyCode.R, icon = "rbxassetid://119382618384110", iconOnly = true, noAnimation = true, holdDuration = 0, followModel = true, studsOffset = Vector3.new(0, 2.45, 0) },
}

local function isStyledPrompt(prompt)
	return prompt and PROMPT_LABELS[prompt.Name] ~= nil
end

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function addStroke(parent, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = parent
	return stroke
end

local function getAdornee(prompt)
	local parent = prompt.Parent
	if parent and parent:IsA("BasePart") then return parent end
	if parent and parent:IsA("Attachment") and parent.Parent and parent.Parent:IsA("BasePart") then
		return parent.Parent
	end
	return nil
end

local function cleanupPromptAnchor(prompt)
	local stepName = promptAnchorStepNames[prompt]
	if stepName then
		RunService:UnbindFromRenderStep(stepName)
		promptAnchorStepNames[prompt] = nil
	end
	local connection = promptAnchorConnections[prompt]
	if connection then
		connection:Disconnect()
		promptAnchorConnections[prompt] = nil
	end
	local anchor = promptAnchors[prompt]
	if anchor then
		anchor:Destroy()
		promptAnchors[prompt] = nil
	end
end

local function getPromptModel(prompt, fallbackPart)
	local model = fallbackPart and fallbackPart:FindFirstAncestorOfClass("Model")
	if model and model.Parent then return model end
	return fallbackPart
end

local function getPromptTopPosition(target)
	if not target then return nil end
	if target:IsA("Model") then
		local cf, size = target:GetBoundingBox()
		return cf.Position + Vector3.new(0, size.Y * 0.5 + 0.45, 0)
	elseif target:IsA("BasePart") then
		return target.Position + Vector3.new(0, target.Size.Y * 0.5 + 0.45, 0)
	end
	return nil
end

local function createFollowAnchor(prompt, adornee)
	cleanupPromptAnchor(prompt)
	local target = getPromptModel(prompt, adornee)
	local position = getPromptTopPosition(target)
	if not position then return adornee end
	local anchor = Instance.new("Part")
	anchor.Name = "BrizabellePetPromptAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace
	promptAnchors[prompt] = anchor
	promptAnchorId += 1
	local stepName = "BrizabellePetPromptFollow_" .. tostring(promptAnchorId)
	promptAnchorStepNames[prompt] = stepName
	RunService:BindToRenderStep(stepName, Enum.RenderPriority.Last.Value, function()
		if not prompt.Parent or not anchor.Parent then
			cleanupPromptAnchor(prompt)
			return
		end
		local nextTarget = getPromptModel(prompt, adornee)
		local nextPosition = getPromptTopPosition(nextTarget)
		if nextPosition then
			anchor.CFrame = CFrame.new(nextPosition)
		end
	end)
	return anchor
end

local function applyPromptProps(prompt)
	local labels = PROMPT_LABELS[prompt.Name]
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.KeyboardKeyCode = labels.keyCode or Enum.KeyCode.E
	prompt.GamepadKeyCode = labels.gamepadKeyCode or Enum.KeyCode.ButtonX
	prompt.HoldDuration = labels.holdDuration or math.max(prompt.HoldDuration, 0.45)
	prompt.MaxActivationDistance = math.max(
		prompt.MaxActivationDistance,
		labels.minDistance or 12
	)
	prompt.RequiresLineOfSight = false
	prompt.ActionText = labels.action
	prompt.ObjectText = labels.object
end

local function setLabelText(gui, prompt)
	local labels = PROMPT_LABELS[prompt.Name]
	local action = gui and gui:FindFirstChild("ActionText", true)
	local object = gui and gui:FindFirstChild("ObjectText", true)
	if action and action:IsA("TextLabel") then action.Text = labels.action end
	if object and object:IsA("TextLabel") then object.Text = labels.object end
end

local function createPromptGui(prompt)
	if activeGuis[prompt] then activeGuis[prompt]:Destroy() end
	local adornee = getAdornee(prompt)
	if not adornee then return end
	applyPromptProps(prompt)

	local labels = PROMPT_LABELS[prompt.Name]
	local guiAdornee = labels.followModel and createFollowAnchor(prompt, adornee) or adornee
	local gui = Instance.new("BillboardGui")
	gui.Name = "BrizabelleStyledPromptGui"
	gui.Adornee = guiAdornee
	gui.AlwaysOnTop = true
	gui.Size = labels.guiSize or (labels.iconOnly and UDim2.fromOffset(58, 58) or UDim2.fromOffset(165, 54))
	gui.StudsOffsetWorldSpace = labels.followModel and Vector3.zero or (labels.studsOffset or Vector3.new(0, 3.35, 0))
	gui.Parent = playerGui

	local scale = Instance.new("UIScale")
	scale.Scale = labels.noAnimation and 1 or 0.82
	scale.Parent = gui

	local frame = Instance.new("Frame")
	frame.Name = "PromptFrame"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local key = Instance.new("Frame")
	key.Name = "KeyBubble"
	key.Position = labels.keyPosition or (labels.iconOnly and UDim2.fromScale(0, 0) or UDim2.fromOffset(5, 3))
	key.Size = labels.keySize or (labels.iconOnly and UDim2.fromScale(1, 1) or UDim2.fromOffset(37, 37))
	key.BackgroundColor3 = Color3.fromRGB(215, 187, 158)
	key.BackgroundTransparency = labels.iconOnly and 1 or 0
	key.BorderSizePixel = 0
	key.Parent = frame
	if not labels.iconOnly then
		addCorner(key, 52)
		local keyStroke = addStroke(key, Color3.fromRGB(8, 10, 10), 4)
		keyStroke.Name = "KeyStroke"
	end

	local keyScale = Instance.new("UIScale")
	keyScale.Scale = 1
	keyScale.Parent = key

	local keyFill = Instance.new("Frame")
	keyFill.Name = "KeyFill"
	keyFill.AnchorPoint = Vector2.new(0.5, 0.5)
	keyFill.Position = UDim2.fromScale(0.5, 0.5)
	keyFill.Size = UDim2.fromScale(1, 1)
	keyFill.BackgroundColor3 = Color3.fromRGB(126, 126, 126)
	keyFill.BackgroundTransparency = labels.iconOnly and 1 or 0
	keyFill.BorderSizePixel = 0
	keyFill.Visible = not labels.iconOnly
	keyFill.Parent = key
	if not labels.iconOnly then addCorner(keyFill, 52) end

	local keyFillScale = Instance.new("UIScale")
	keyFillScale.Scale = 0
	keyFillScale.Parent = keyFill

	if labels.icon then
		local keyIcon = Instance.new("ImageLabel")
		keyIcon.Name = "KeyIcon"
		keyIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		keyIcon.Position = UDim2.fromScale(0.5, 0.5)
		keyIcon.Size = labels.iconOnly and UDim2.fromScale(1, 1) or UDim2.fromScale(0.82, 0.82)
		keyIcon.BackgroundTransparency = 1
		keyIcon.Image = labels.icon
		keyIcon.ScaleType = Enum.ScaleType.Fit
		keyIcon.Parent = key
	else
		local keyText = Instance.new("TextLabel")
		keyText.Size = UDim2.fromScale(1, 1)
		keyText.BackgroundTransparency = 1
		keyText.Font = Enum.Font.FredokaOne
		keyText.Text = (labels.keyCode and labels.keyCode.Name) or "E"
		keyText.TextColor3 = Color3.fromRGB(0, 5, 6)
		keyText.TextScaled = true
		keyText.Parent = key
	end

	local action = Instance.new("TextLabel")
	action.Name = "ActionText"
	action.Position = labels.actionPosition or UDim2.fromOffset(46, 4)
	action.Size = labels.actionSize or UDim2.new(1, -54, 0, 21)
	action.BackgroundTransparency = 1
	action.Font = Enum.Font.FredokaOne
	action.Text = PROMPT_LABELS[prompt.Name].action
	action.TextColor3 = Color3.fromRGB(255, 244, 226)
	action.TextTransparency = 1
	action.TextScaled = true
	action.TextXAlignment = Enum.TextXAlignment.Left
	action.Visible = not labels.iconOnly
	action.Parent = frame

	local object = Instance.new("TextLabel")
	object.Name = "ObjectText"
	object.Position = labels.objectPosition or UDim2.fromOffset(46, 25)
	object.Size = labels.objectSize or UDim2.new(1, -54, 0, 17)
	object.BackgroundTransparency = 1
	object.Font = Enum.Font.FredokaOne
	object.Text = PROMPT_LABELS[prompt.Name].object
	object.TextColor3 = Color3.fromRGB(223, 187, 150)
	object.TextTransparency = 1
	object.TextScaled = true
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.Visible = not labels.iconOnly
	object.Parent = frame

	activeGuis[prompt] = gui
	if not labels.noAnimation then
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		local finalActionPosition = labels.actionPosition or UDim2.fromOffset(52, 4)
		local finalObjectPosition = labels.objectPosition or UDim2.fromOffset(52, 25)
		TweenService:Create(action, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextTransparency = 0, Position = finalActionPosition }):Play()
		TweenService:Create(object, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextTransparency = 0, Position = finalObjectPosition }):Play()
		TweenService:Create(keyScale, TweenInfo.new(0.64, Enum.EasingStyle.Back, Enum.EasingDirection.InOut, -1, true), { Scale = 1.1 }):Play()
		TweenService:Create(key, TweenInfo.new(0.84, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 4 }):Play()
		setLabelText(gui, prompt)
	end
end

local function finishHold(prompt, instant)
	local labels = PROMPT_LABELS[prompt.Name]
	if labels and labels.noAnimation then return end
	local gui = activeGuis[prompt]
	local key = gui and gui:FindFirstChild("KeyBubble", true)
	local info = instant and TweenInfo.new(0) or TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if key then
		local normalKeySize = labels.keySize or UDim2.fromOffset(37, 37)
		local normalKeyPosition = labels.keyPosition or UDim2.fromOffset(5, 3)
		TweenService:Create(key, info, {
			BackgroundColor3 = Color3.fromRGB(215, 187, 158),
			Rotation = 0,
			Size = normalKeySize,
			Position = normalKeyPosition,
		}):Play()
		local stroke = key:FindFirstChild("KeyStroke")
		if stroke and stroke:IsA("UIStroke") then
			TweenService:Create(stroke, info, { Color = Color3.fromRGB(8, 10, 10), Thickness = 4 }):Play()
		end
		local keyText = key:FindFirstChildWhichIsA("TextLabel")
		if keyText then TweenService:Create(keyText, info, { TextColor3 = Color3.fromRGB(0, 5, 6) }):Play() end
		local keyFill = key:FindFirstChild("KeyFill", true)
		local keyFillScale = keyFill and keyFill:FindFirstChildOfClass("UIScale")
		if keyFillScale then TweenService:Create(keyFillScale, info, { Scale = 0 }):Play() end
	end
end

local function beginHold(prompt)
	local labels = PROMPT_LABELS[prompt.Name]
	if labels and labels.noAnimation then return end
	local gui = activeGuis[prompt]
	local key = gui and gui:FindFirstChild("KeyBubble", true)
	if key then
		local keyFill = key:FindFirstChild("KeyFill", true)
		local keyFillScale = keyFill and keyFill:FindFirstChildOfClass("UIScale")
		if keyFillScale then
			keyFillScale.Scale = 0
			TweenService:Create(keyFillScale, TweenInfo.new(math.max(prompt.HoldDuration, 0.05), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		local keyText = key:FindFirstChildWhichIsA("TextLabel")
		if keyText then TweenService:Create(keyText, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = Color3.fromRGB(245, 245, 245) }):Play() end
	end
end

ProximityPromptService.PromptShown:Connect(function(prompt)
	if not isStyledPrompt(prompt) then return end
	createPromptGui(prompt)
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	if not isStyledPrompt(prompt) then return end
	finishHold(prompt, true)
	local gui = activeGuis[prompt]
	if gui then
		gui:Destroy()
		activeGuis[prompt] = nil
	end
	cleanupPromptAnchor(prompt)
end)

ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, triggeringPlayer)
	if not isStyledPrompt(prompt) then return end
	if triggeringPlayer and triggeringPlayer ~= player then return end
	beginHold(prompt)
end)

ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt, triggeringPlayer)
	if not isStyledPrompt(prompt) then return end
	if triggeringPlayer and triggeringPlayer ~= player then return end
	finishHold(prompt, false)
end)

workspace.DescendantAdded:Connect(function(instance)
	if instance:IsA("ProximityPrompt") and isStyledPrompt(instance) then
		task.defer(function()
			if instance.Parent then applyPromptProps(instance) end
		end)
	end
end)

for _, instance in ipairs(workspace:GetDescendants()) do
	if instance:IsA("ProximityPrompt") and isStyledPrompt(instance) then
		applyPromptProps(instance)
	end
end