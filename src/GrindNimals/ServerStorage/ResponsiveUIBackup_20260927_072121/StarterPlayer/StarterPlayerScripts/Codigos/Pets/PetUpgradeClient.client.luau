-- FRANK CLIENT V20 - tutorial de mejora + sistema normal
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local controls = nil
pcall(function()
	local playerScripts = player:WaitForChild("PlayerScripts")
	local playerModule = require(playerScripts:WaitForChild("PlayerModule"))
	controls = playerModule:GetControls()
end)

local movementLocked = false

local frankInputBlocked = false
local petMenuPromptStates = {}

local function sinkFrankInput()
	return Enum.ContextActionResult.Sink
end

local function setPetMenuPromptsEnabled(enabled)
	if enabled then
		for prompt, wasEnabled in pairs(petMenuPromptStates) do
			if prompt and prompt.Parent then
				prompt.Enabled = wasEnabled
			end
		end
		table.clear(petMenuPromptStates)
		return
	end

	table.clear(petMenuPromptStates)

	for _, instance in ipairs(workspace:GetDescendants()) do
		if instance:IsA("ProximityPrompt")
			and instance.Name == "BrizabellePetMenuPrompt" then

			petMenuPromptStates[instance] = instance.Enabled
			instance.Enabled = false
		end
	end
end

local function blockFrankInputs()
	if frankInputBlocked then
		return
	end

	frankInputBlocked = true

	-- Bloquea R para que no se pueda abrir el menú de mascota mientras Frank está abierto.
	ContextActionService:BindActionAtPriority(
		"Frank_Block_R",
		sinkFrankInput,
		false,
		10000,
		Enum.KeyCode.R
	)

	setPetMenuPromptsEnabled(false)
end

local function unblockFrankInputs()
	if not frankInputBlocked then
		return
	end

	frankInputBlocked = false
	ContextActionService:UnbindAction("Frank_Block_R")
	setPetMenuPromptsEnabled(true)
end

local savedMovement = {
	WalkSpeed = nil,
	JumpPower = nil,
	JumpHeight = nil,
	AutoRotate = nil,
}

local function lockMovement()
	if movementLocked then
		return
	end

	movementLocked = true

	if controls then
		pcall(function()
			controls:Disable()
		end)
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid then
		savedMovement.WalkSpeed = humanoid.WalkSpeed
		savedMovement.JumpPower = humanoid.JumpPower
		savedMovement.JumpHeight = humanoid.JumpHeight
		savedMovement.AutoRotate = humanoid.AutoRotate

		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
	end
end

local function unlockMovement()
	if not movementLocked then
		return
	end

	movementLocked = false

	if controls then
		pcall(function()
			controls:Enable()
		end)
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid then
		if savedMovement.WalkSpeed ~= nil then
			humanoid.WalkSpeed = savedMovement.WalkSpeed
		end
		if savedMovement.JumpPower ~= nil then
			humanoid.JumpPower = savedMovement.JumpPower
		end
		if savedMovement.JumpHeight ~= nil then
			humanoid.JumpHeight = savedMovement.JumpHeight
		end
		if savedMovement.AutoRotate ~= nil then
			humanoid.AutoRotate = savedMovement.AutoRotate
		end
	end

	savedMovement.WalkSpeed = nil
	savedMovement.JumpPower = nil
	savedMovement.JumpHeight = nil
	savedMovement.AutoRotate = nil
end

local system = ReplicatedStorage:WaitForChild("PetUpgradeSystem")
local GetUpgradeInfo = system:WaitForChild("GetUpgradeInfo")
local UpgradePet = system:WaitForChild("UpgradePet")
local OpenUpgradeUI = system:WaitForChild("OpenUpgradeUI")

--==============================================================
-- MODO DEMOSTRACION DEL TUTORIAL
-- Solo existe durante GO_FRANK / FRANK_EXAMPLE.
-- NO mejora ninguna mascota y NO consume materiales.
--==============================================================
local tutorialSystem = ReplicatedStorage:FindFirstChild("TutorialSystem")
	or ReplicatedStorage:WaitForChild("TutorialSystem", 10)
local tutorialRemotes = tutorialSystem and (tutorialSystem:FindFirstChild("Remotes")
	or tutorialSystem:WaitForChild("Remotes", 10))
local TutorialClientAction = tutorialRemotes and (tutorialRemotes:FindFirstChild("ClientAction")
	or tutorialRemotes:WaitForChild("ClientAction", 10))
local tutorialDemoActive = false
local tutorialDemoReported = false

local function isFrankTutorialDemoStep()
	if player:GetAttribute("TutorialCompleted") == true then
		return false
	end
	local step = tostring(player:GetAttribute("TutorialStep") or "")
	return step == "GO_FRANK" or step == "FRANK_EXAMPLE"
end

local function getTutorialDemoData()
	return {
		ok = true,
		tutorialDemo = true,
		maxLevel = false,
		petName = "Oveja",
		currentTier = "Base",
		currentDisplay = "Base",
		currentColor = "Sin pañuelo",
		nextTier = "Comun",
		nextDisplay = "Común",
		nextColor = "Gris",
		requirements = {
			{name = "Manzana", needed = 30, owned = 0, enough = false, demo = true},
			{name = "Naranja", needed = 30, owned = 0, enough = false, demo = true},
			{name = "Zanahoria", needed = 30, owned = 0, enough = false, demo = true},
		},
	}
end

local function reportFrankTutorialDone()
	if tutorialDemoReported then return end
	tutorialDemoReported = true
	if TutorialClientAction and TutorialClientAction:IsA("RemoteEvent") then
		TutorialClientAction:FireServer("ReportAction", {Name = "FRANK_DEMO_DONE"})
	else
		warn("[FrankTutorial] No encontre TutorialSystem.Remotes.ClientAction")
	end
end

local FONT = Enum.Font.FredokaOne

local dialogueGui
local gui

local COLORS = {
	panel = Color3.fromRGB(180, 126, 76),
	panelDark = Color3.fromRGB(150, 101, 62),
	dark = Color3.fromRGB(75, 45, 28),
	cream = Color3.fromRGB(255, 232, 190),
	cream2 = Color3.fromRGB(243, 210, 168),
	green = Color3.fromRGB(77, 165, 79),
	greenDark = Color3.fromRGB(60, 135, 63),
	disabled = Color3.fromRGB(108, 93, 74),
	white = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(43, 25, 15),
	red = Color3.fromRGB(195, 62, 53),
}

local TIER_COLORS = {
	Base = Color3.fromRGB(95, 75, 65),
	Comun = Color3.fromRGB(135, 135, 135),
	["Poco comun"] = Color3.fromRGB(73, 181, 82),
	Raro = Color3.fromRGB(65, 135, 225),
	Epico = Color3.fromRGB(157, 79, 206),
	Legendario = Color3.fromRGB(220, 171, 46),
}

local function corner(obj, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = obj
	return c
end

local function stroke(obj, thickness, color)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 2
	s.Color = color or COLORS.dark
	s.Parent = obj
	return s
end

--==============================================================
-- OCULTAR HUD COMPLETO
--==============================================================
-- Esta versión no depende de que el HUD sea un ScreenGui directo.
-- Oculta:
--   1) ScreenGui/BillboardGui/SurfaceGui dentro de PlayerGui.
--   2) GuiObjects que estén metidos dentro de Folders.
--   3) CoreGui de Roblox mientras hablas con Frank.
-- Y mantiene visibles únicamente las interfaces de Frank.

local hudLockActive = false
local savedEnabledStates = {}
local savedVisibleStates = {}
local coreGuiStates = {}
local hudLockConnection = nil
local hudDescendantConnection = nil

local CORE_GUI_TYPES = {
	Enum.CoreGuiType.Backpack,
	Enum.CoreGuiType.Chat,
	Enum.CoreGuiType.Health,
	Enum.CoreGuiType.PlayerList,
	Enum.CoreGuiType.EmotesMenu,
}

local function isFrankGuiObject(instance)
	if dialogueGui and (instance == dialogueGui or instance:IsDescendantOf(dialogueGui)) then
		return true
	end
	if gui and (instance == gui or instance:IsDescendantOf(gui)) then
		return true
	end
	return false
end

local function saveAndHideInstance(instance)
	if not instance or isFrankGuiObject(instance) then
		return
	end

	if instance:IsA("LayerCollector") then
		if savedEnabledStates[instance] == nil then
			savedEnabledStates[instance] = instance.Enabled
		end
		if instance.Enabled then
			instance.Enabled = false
		end
	elseif instance:IsA("GuiObject") then
		if savedVisibleStates[instance] == nil then
			savedVisibleStates[instance] = instance.Visible
		end
		if instance.Visible then
			instance.Visible = false
		end
	end
end

local function forceHudHidden()
	if not hudLockActive then
		return
	end

	-- Recorremos TODOS los descendientes por si tu HUD está dentro
	-- de Folders u otros contenedores.
	for _, instance in ipairs(playerGui:GetDescendants()) do
		saveAndHideInstance(instance)
	end

	for _, child in ipairs(playerGui:GetChildren()) do
		saveAndHideInstance(child)
	end

	-- Ocultar CoreGui de Roblox.
	for _, coreType in ipairs(CORE_GUI_TYPES) do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(coreType, false)
		end)
	end
end

local function hideGameHud()
	if hudLockActive then
		forceHudHidden()
		return
	end

	hudLockActive = true
	table.clear(savedEnabledStates)
	table.clear(savedVisibleStates)
	table.clear(coreGuiStates)

	-- Guardar estado de CoreGui antes de esconderlo.
	for _, coreType in ipairs(CORE_GUI_TYPES) do
		local ok, enabled = pcall(function()
			return StarterGui:GetCoreGuiEnabled(coreType)
		end)
		if ok then
			coreGuiStates[coreType] = enabled
		end
	end

	forceHudHidden()

	-- Si algún script crea o vuelve a mostrar HUD mientras Frank está abierto,
	-- lo escondemos de nuevo inmediatamente.
	hudDescendantConnection = playerGui.DescendantAdded:Connect(function(instance)
		if not hudLockActive then
			return
		end
		task.defer(function()
			if instance.Parent then
				saveAndHideInstance(instance)
			end
		end)
	end)

	hudLockConnection = RunService.RenderStepped:Connect(function()
		forceHudHidden()
	end)
end

local function restoreGameHud()
	hudLockActive = false

	if hudLockConnection then
		hudLockConnection:Disconnect()
		hudLockConnection = nil
	end

	if hudDescendantConnection then
		hudDescendantConnection:Disconnect()
		hudDescendantConnection = nil
	end

	for instance, wasEnabled in pairs(savedEnabledStates) do
		if instance and instance.Parent then
			pcall(function()
				instance.Enabled = wasEnabled
			end)
		end
	end

	for instance, wasVisible in pairs(savedVisibleStates) do
		if instance and instance.Parent then
			pcall(function()
				instance.Visible = wasVisible
			end)
		end
	end

	for coreType, wasEnabled in pairs(coreGuiStates) do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(coreType, wasEnabled)
		end)
	end

	table.clear(savedEnabledStates)
	table.clear(savedVisibleStates)
	table.clear(coreGuiStates)
end

--==============================================================
-- DIÁLOGO
--==============================================================

dialogueGui = Instance.new("ScreenGui")
dialogueGui.Name = "FrankDialogueGui"
dialogueGui.ResetOnSpawn = false
dialogueGui.IgnoreGuiInset = true
dialogueGui.DisplayOrder = 500
dialogueGui.Enabled = false
dialogueGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
dialogueGui.Parent = playerGui

local dialogueShade = Instance.new("Frame")
dialogueShade.Size = UDim2.fromScale(1, 1)
dialogueShade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
dialogueShade.BackgroundTransparency = 0.48
dialogueShade.BorderSizePixel = 0
dialogueShade.ZIndex = 1
dialogueShade.Parent = dialogueGui

local dialogueBox = Instance.new("Frame")
dialogueBox.Name = "DialogueBox"
dialogueBox.AnchorPoint = Vector2.new(0.5, 1)
dialogueBox.Position = UDim2.new(0.5, 0, 1, -34)
dialogueBox.Size = UDim2.fromOffset(620, 104)
dialogueBox.BackgroundColor3 = COLORS.panel
dialogueBox.BorderSizePixel = 0
dialogueBox.ZIndex = 2
dialogueBox.Parent = dialogueShade
corner(dialogueBox, 14)
stroke(dialogueBox, 3, COLORS.dark)

local dialogueScale = Instance.new("UIScale")
dialogueScale.Name = "DialogueScale"
dialogueScale.Parent = dialogueBox

local speaker = Instance.new("TextLabel")
speaker.BackgroundTransparency = 1
speaker.Position = UDim2.fromOffset(18, 12)
speaker.Size = UDim2.new(1, -36, 0, 27)
speaker.Font = FONT
speaker.Text = "FRANK"
speaker.TextSize = 24
speaker.TextColor3 = COLORS.cream
speaker.TextStrokeColor3 = COLORS.dark
speaker.TextStrokeTransparency = 0.2
speaker.TextXAlignment = Enum.TextXAlignment.Left
speaker.ZIndex = 3
speaker.Parent = dialogueBox

local dialogueText = Instance.new("TextLabel")
dialogueText.BackgroundTransparency = 1
dialogueText.Position = UDim2.fromOffset(18, 40)
dialogueText.Size = UDim2.new(1, -54, 0, 52)
dialogueText.Font = FONT
dialogueText.Text = ""
dialogueText.TextSize = 22
dialogueText.TextWrapped = true
dialogueText.TextColor3 = COLORS.white
dialogueText.TextStrokeColor3 = COLORS.dark
dialogueText.TextStrokeTransparency = 0.28
dialogueText.TextXAlignment = Enum.TextXAlignment.Left
dialogueText.TextYAlignment = Enum.TextYAlignment.Top
dialogueText.ZIndex = 3
dialogueText.Parent = dialogueBox

-- Flecha para indicar que puedes hacer clic en cualquier parte del diálogo.
local dialogueArrow = Instance.new("TextLabel")
dialogueArrow.Name = "ContinueArrow"
dialogueArrow.AnchorPoint = Vector2.new(1, 1)
dialogueArrow.Position = UDim2.new(1, -14, 1, -8)
dialogueArrow.Size = UDim2.fromOffset(34, 26)
dialogueArrow.BackgroundTransparency = 1
dialogueArrow.Text = "▼"
dialogueArrow.Font = FONT
dialogueArrow.TextSize = 20
dialogueArrow.TextColor3 = COLORS.cream
dialogueArrow.TextStrokeColor3 = COLORS.dark
dialogueArrow.TextStrokeTransparency = 0.2
dialogueArrow.ZIndex = 3
dialogueArrow.Parent = dialogueBox

local arrowTween = TweenService:Create(
	dialogueArrow,
	TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{Position = UDim2.new(1, -14, 1, -4)}
)
arrowTween:Play()

local dialogueClick = Instance.new("TextButton")
dialogueClick.Name = "DialogueClickArea"
dialogueClick.Size = UDim2.fromScale(1, 1)
dialogueClick.BackgroundTransparency = 1
dialogueClick.Text = ""
dialogueClick.AutoButtonColor = false
dialogueClick.ZIndex = 4
dialogueClick.Parent = dialogueBox

local dialogueData = nil

local function makeDialogueText(data)
	if not data then
		return "Hmm... no pude revisar a tu mascota."
	end

	if not data.ok then
		if data.petName then
			return "Veo que tienes un " .. tostring(data.petName) .. ", pero ahora mismo no puedo revisar su mejora."
		end
		return "No veo ninguna mascota afuera. Saca una mascota y vuelve conmigo."
	end

	if data.maxLevel then
		return "Veo que tienes un " .. tostring(data.petName) .. " " ..
			string.lower(tostring(data.currentDisplay or "")) ..
			". Ya alcanzó el nivel máximo."
	end

	return "Veo que tienes un " .. tostring(data.petName) .. " " ..
		string.lower(tostring(data.currentDisplay or "base")) ..
		". Puedo mejorarlo a " .. tostring(data.nextDisplay or "la siguiente rareza") .. "."
end

local function showFrankDialogue(data)
	dialogueData = data
	dialogueText.Text = makeDialogueText(data)

	dialogueGui.Enabled = true
	dialogueScale.Scale = 0.88
	dialogueBox.Position = UDim2.new(0.5, 0, 1, 15)

	TweenService:Create(
		dialogueScale,
		TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Scale = 1}
	):Play()

	TweenService:Create(
		dialogueBox,
		TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Position = UDim2.new(0.5, 0, 1, -34)}
	):Play()
end

--==============================================================
-- INTERFAZ DE MEJORA - MINIMALISTA Y SIN ENCIMARSE
--==============================================================

gui = Instance.new("ScreenGui")
gui.Name = "PetUpgradeGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 500
gui.Enabled = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local shade = Instance.new("Frame")
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
shade.BackgroundTransparency = 0.42
shade.BorderSizePixel = 0
shade.Parent = gui

local main = Instance.new("Frame")
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Position = UDim2.fromScale(0.5, 0.5)
main.Size = UDim2.fromOffset(700, 430)
main.BackgroundColor3 = COLORS.panel
main.BorderSizePixel = 0
main.Parent = shade
corner(main, 14)
stroke(main, 4, COLORS.dark)

local mainScale = Instance.new("UIScale")
mainScale.Name = "ResponsiveScale"
mainScale.Parent = main

local inner = Instance.new("Frame")
inner.Position = UDim2.fromOffset(12, 12)
inner.Size = UDim2.new(1, -24, 1, -24)
inner.BackgroundColor3 = COLORS.panel
inner.BorderSizePixel = 0
inner.Parent = main
corner(inner, 10)

-- Header
local topBar = Instance.new("Frame")
topBar.Position = UDim2.fromOffset(8, 8)
topBar.Size = UDim2.new(1, -16, 0, 54)
topBar.BackgroundColor3 = COLORS.cream
topBar.BorderSizePixel = 0
topBar.Parent = inner
corner(topBar, 7)
stroke(topBar, 1.5, COLORS.dark)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(14, 4)
title.Size = UDim2.new(1, -62, 1, -8)
title.Font = FONT
title.Text = "MEJORAR MASCOTA"
title.TextSize = 27
title.TextColor3 = COLORS.text
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = topBar

local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0.5)
close.Position = UDim2.new(1, -10, 0.5, 0)
close.Size = UDim2.fromOffset(36, 36)
close.BackgroundTransparency = 1
close.Text = "X"
close.Font = FONT
close.TextSize = 23
close.TextColor3 = COLORS.text
close.Parent = topBar

local petTitle = Instance.new("TextLabel")
petTitle.BackgroundTransparency = 1
petTitle.Position = UDim2.fromOffset(16, 70)
petTitle.Size = UDim2.new(1, -32, 0, 30)
petTitle.Font = FONT
petTitle.TextSize = 22
petTitle.TextColor3 = COLORS.text
petTitle.Parent = inner

-- Receta
local recipeStrip = Instance.new("Frame")
recipeStrip.Position = UDim2.fromOffset(16, 108)
recipeStrip.Size = UDim2.new(1, -32, 0, 210)
recipeStrip.BackgroundColor3 = COLORS.panelDark
recipeStrip.BorderSizePixel = 0
recipeStrip.Parent = inner
corner(recipeStrip, 9)

local recipeInner = Instance.new("Frame")
recipeInner.Position = UDim2.fromOffset(8, 8)
recipeInner.Size = UDim2.new(1, -16, 1, -16)
recipeInner.BackgroundColor3 = COLORS.cream2
recipeInner.BorderSizePixel = 0
recipeInner.Parent = recipeStrip
corner(recipeInner, 7)

local currentCard = Instance.new("Frame")
currentCard.Position = UDim2.fromOffset(8, 8)
currentCard.Size = UDim2.fromOffset(150, 178)
currentCard.BackgroundColor3 = COLORS.cream
currentCard.BorderSizePixel = 0
currentCard.Parent = recipeInner
corner(currentCard, 7)
stroke(currentCard, 1.3, COLORS.panelDark)

local currentText = Instance.new("TextLabel")
currentText.BackgroundTransparency = 1
currentText.Position = UDim2.fromOffset(6, 6)
currentText.Size = UDim2.new(1, -12, 1, -12)
currentText.Font = FONT
currentText.TextWrapped = true
currentText.TextSize = 17
currentText.TextColor3 = COLORS.text
currentText.Parent = currentCard
currentText.Visible = false

local ingredientHolder = Instance.new("Frame")
ingredientHolder.BackgroundTransparency = 1
ingredientHolder.Position = UDim2.fromOffset(165, 8)
ingredientHolder.Size = UDim2.new(1, -340, 0, 178)
ingredientHolder.Parent = recipeInner

local ingredientLayout = Instance.new("UIListLayout")
ingredientLayout.FillDirection = Enum.FillDirection.Horizontal
ingredientLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
ingredientLayout.VerticalAlignment = Enum.VerticalAlignment.Center
ingredientLayout.Padding = UDim.new(0, 6)
ingredientLayout.Parent = ingredientHolder

local equals = Instance.new("TextLabel")
equals.BackgroundTransparency = 1
equals.AnchorPoint = Vector2.new(0.5, 0.5)
equals.Position = UDim2.new(1, -168, 0.5, 0)
equals.Size = UDim2.fromOffset(28, 42)
equals.Font = FONT
equals.Text = "="
equals.TextSize = 28
equals.TextColor3 = COLORS.dark
equals.Parent = recipeInner

local nextCard = Instance.new("Frame")
nextCard.AnchorPoint = Vector2.new(1, 0)
nextCard.Position = UDim2.new(1, -7, 0, 8)
nextCard.Size = UDim2.fromOffset(150, 178)
nextCard.BackgroundColor3 = COLORS.cream
nextCard.BorderSizePixel = 0
nextCard.Parent = recipeInner
corner(nextCard, 7)
stroke(nextCard, 1.3, COLORS.panelDark)

local nextText = Instance.new("TextLabel")
nextText.BackgroundTransparency = 1
nextText.Position = UDim2.fromOffset(6, 6)
nextText.Size = UDim2.new(1, -12, 1, -12)
nextText.Font = FONT
nextText.TextWrapped = true
nextText.TextSize = 16
nextText.Parent = nextCard
nextText.Visible = false

-- Estado / materiales
local materialsTitle = Instance.new("TextLabel")
materialsTitle.BackgroundTransparency = 1
materialsTitle.Position = UDim2.fromOffset(18, 252)
materialsTitle.Size = UDim2.new(1, -36, 0, 24)
materialsTitle.Font = FONT
materialsTitle.Text = ""
materialsTitle.TextSize = 17
materialsTitle.TextColor3 = COLORS.text
materialsTitle.TextXAlignment = Enum.TextXAlignment.Left
materialsTitle.Parent = inner
materialsTitle.Visible = false

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Position = UDim2.fromOffset(18, 280)
status.Size = UDim2.new(1, -36, 0, 38)
status.Font = FONT
status.TextWrapped = true
status.TextSize = 14
status.TextColor3 = COLORS.text
status.TextXAlignment = Enum.TextXAlignment.Center
status.Parent = inner
status.Visible = false

local tutorialInfo = Instance.new("TextLabel")
tutorialInfo.Name = "FrankTutorialExplanation"
tutorialInfo.Position = UDim2.fromOffset(18, 326)
tutorialInfo.Size = UDim2.new(1, -36, 0, 156)
tutorialInfo.BackgroundColor3 = COLORS.cream
tutorialInfo.BorderSizePixel = 0
tutorialInfo.Font = Enum.Font.Gotham
tutorialInfo.TextWrapped = true
tutorialInfo.TextSize = 20
tutorialInfo.TextColor3 = COLORS.text
tutorialInfo.Text = ""
tutorialInfo.TextXAlignment = Enum.TextXAlignment.Left
tutorialInfo.TextYAlignment = Enum.TextYAlignment.Top
tutorialInfo.Visible = false
tutorialInfo.Parent = inner
corner(tutorialInfo, 8)
stroke(tutorialInfo, 1.5, COLORS.dark)

local craft = Instance.new("TextButton")
craft.AnchorPoint = Vector2.new(0.5, 1)
craft.Position = UDim2.new(0.5, 0, 1, -16)
craft.Size = UDim2.fromOffset(260, 48)
craft.BackgroundColor3 = COLORS.green
craft.BorderSizePixel = 0
craft.Text = "MEJORAR"
craft.TextColor3 = COLORS.white
craft.Font = FONT
craft.TextSize = 22
craft.AutoButtonColor = false
craft.Parent = inner
corner(craft, 9)
stroke(craft, 1.8, COLORS.dark)

local function updateResponsiveScale()
	local camera = workspace.CurrentCamera
	if not camera then return end

	local viewport = camera.ViewportSize
	local scaleX = viewport.X / 780
	local scaleY = viewport.Y / 520
	mainScale.Scale = math.clamp(math.min(scaleX, scaleY), 0.78, 1.08)
end

updateResponsiveScale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale)
end


--==============================================================
-- PREVIEWS 3D DE MASCOTAS
--==============================================================

local VARIANT_FOLDERS = {
	Comun = "Mascotas pañuelos grises",
	["Poco comun"] = "Mascotas pañuelos verdes",
	Raro = "Mascotas pañuelos azul",
	Epico = "Mascotas pañuelos morado",
	Legendario = "Mascotas pañuelos dorado",
}

local currentViewport = Instance.new("ViewportFrame")
currentViewport.Name = "CurrentPetPreview"
currentViewport.Position = UDim2.fromOffset(6, 6)
currentViewport.Size = UDim2.new(1, -12, 1, -30)
currentViewport.BackgroundTransparency = 1
currentViewport.Ambient = Color3.fromRGB(255,255,255)
currentViewport.LightColor = Color3.fromRGB(255,255,255)
currentViewport.LightDirection = Vector3.new(-1,-1,-1)
currentViewport.Parent = currentCard

local currentTierLabel = Instance.new("TextLabel")
currentTierLabel.AnchorPoint = Vector2.new(0.5,1)
currentTierLabel.Position = UDim2.new(0.5,0,1,-3)
currentTierLabel.Size = UDim2.new(1,-10,0,30)
currentTierLabel.BackgroundTransparency = 1
currentTierLabel.Font = FONT
currentTierLabel.TextSize = 19
currentTierLabel.TextColor3 = COLORS.text
currentTierLabel.TextStrokeColor3 = COLORS.cream
currentTierLabel.TextStrokeTransparency = 0.2
currentTierLabel.Parent = currentCard

local nextViewport = Instance.new("ViewportFrame")
nextViewport.Name = "NextPetPreview"
nextViewport.Position = UDim2.fromOffset(6, 6)
nextViewport.Size = UDim2.new(1, -12, 1, -30)
nextViewport.BackgroundTransparency = 1
nextViewport.Ambient = Color3.fromRGB(255,255,255)
nextViewport.LightColor = Color3.fromRGB(255,255,255)
nextViewport.LightDirection = Vector3.new(-1,-1,-1)
nextViewport.Parent = nextCard

local nextTierLabel = Instance.new("TextLabel")
nextTierLabel.AnchorPoint = Vector2.new(0.5,1)
nextTierLabel.Position = UDim2.new(0.5,0,1,-3)
nextTierLabel.Size = UDim2.new(1,-10,0,30)
nextTierLabel.BackgroundTransparency = 1
nextTierLabel.Font = FONT
nextTierLabel.TextSize = 19
nextTierLabel.TextColor3 = COLORS.text
nextTierLabel.TextStrokeColor3 = COLORS.cream
nextTierLabel.TextStrokeTransparency = 0.2
nextTierLabel.Parent = nextCard

local function normalizeName(value)
	return tostring(value or ""):lower():gsub("[%s_%-]+","")
end

local function findBaseViewModel(petName)
	local views = ReplicatedStorage:FindFirstChild("MascotasView")
	if not views then
		return nil
	end

	local exact = views:FindFirstChild(petName)
	if exact and exact:IsA("Model") then
		return exact
	end

	for _, obj in ipairs(views:GetChildren()) do
		if obj:IsA("Model") then
			local n = normalizeName(obj.Name)
			local p = normalizeName(petName)

			if n == p or n:find(p, 1, true) or p:find(n, 1, true) then
				return obj
			end
		end
	end

	return nil
end

local function findVariantModel(tier, petName)
	local folderName = VARIANT_FOLDERS[tier]
	if not folderName then return nil end

	local animals = workspace:FindFirstChild("Animales pañuelos")
	local folder = animals and animals:FindFirstChild(folderName)

	if not folder then
		folder = workspace:FindFirstChild(folderName, true)
	end

	if not folder then
		return nil
	end

	local exact = folder:FindFirstChild(petName)
	if exact and exact:IsA("Model") then
		return exact
	end

	local p = normalizeName(petName)

	for _, obj in ipairs(folder:GetChildren()) do
		if obj:IsA("Model") then
			local n = normalizeName(obj.Name)
			if n == p or n:find(p, 1, true) or p:find(n, 1, true) then
				return obj
			end
		end
	end

	for _, obj in ipairs(folder:GetDescendants()) do
		if obj:IsA("Model") then
			local n = normalizeName(obj.Name)
			if n == p or n:find(p, 1, true) or p:find(n, 1, true) then
				return obj
			end
		end
	end

	return nil
end


local function normalizedObjectName(obj)
	return tostring(obj and obj.Name or ""):lower()
end

local function isScarfObject(obj)
	local n = normalizedObjectName(obj)
	return n:find("pañuelo", 1, true)
		or n:find("panuelo", 1, true)
		or n:find("scarf", 1, true)
		or n:find("bandana", 1, true)
end

local function findMatchingBodyAttachment(model, attachmentName, accessory)
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("Attachment")
			and obj.Name == attachmentName
			and not obj:IsDescendantOf(accessory) then
			return obj
		end
	end
	return nil
end

local function fixAccessoryPlacement(model)
	for _, accessory in ipairs(model:GetDescendants()) do
		if accessory:IsA("Accessory") then
			local handle = accessory:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				local accessoryAttachment = handle:FindFirstChildWhichIsA("Attachment")

				if accessoryAttachment then
					local bodyAttachment = findMatchingBodyAttachment(
						model,
						accessoryAttachment.Name,
						accessory
					)

					if bodyAttachment then
						handle.CFrame =
							bodyAttachment.WorldCFrame
							* accessoryAttachment.CFrame:Inverse()
					end
				end
			end
		end
	end
end

local function getBodyPartsExcludingScarf(model)
	local parts = {}

	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BasePart") and not isScarfObject(obj) then
			local ancestorScarf = false
			local p = obj.Parent
			while p and p ~= model do
				if isScarfObject(p) then
					ancestorScarf = true
					break
				end
				p = p.Parent
			end

			if not ancestorScarf then
				table.insert(parts, obj)
			end
		end
	end

	return parts
end

local function getPartsBoundingBox(parts)
	if #parts == 0 then
		return nil, nil
	end

	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)

	for _, part in ipairs(parts) do
		local cf = part.CFrame
		local s = part.Size * 0.5

		for _, x in ipairs({-1, 1}) do
			for _, y in ipairs({-1, 1}) do
				for _, z in ipairs({-1, 1}) do
					local p = cf:PointToWorldSpace(Vector3.new(s.X*x, s.Y*y, s.Z*z))
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
	end

	return (minV + maxV) * 0.5, (maxV - minV)
end

local function collectScarfRoots(model)
	local roots = {}

	for _, obj in ipairs(model:GetChildren()) do
		if isScarfObject(obj) then
			table.insert(roots, obj)
		end
	end

	if #roots == 0 then
		for _, obj in ipairs(model:GetDescendants()) do
			if isScarfObject(obj) then
				local parent = obj.Parent
				if parent == model or not isScarfObject(parent) then
					table.insert(roots, obj)
				end
			end
		end
	end

	return roots
end

local function getPivotAndSize(obj)
	if obj:IsA("Model") then
		return obj:GetPivot(), select(2, obj:GetBoundingBox())
	elseif obj:IsA("BasePart") then
		return obj.CFrame, obj.Size
	elseif obj:IsA("Accessory") then
		local handle = obj:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			return handle.CFrame, handle.Size
		end
	end
	return nil, nil
end

local function pivotObject(obj, cf)
	if obj:IsA("Model") then
		obj:PivotTo(cf)
	elseif obj:IsA("BasePart") then
		obj.CFrame = cf
	elseif obj:IsA("Accessory") then
		local handle = obj:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			handle.CFrame = cf
		end
	end
end

local function fixLooseScarfPlacement(model)
	local scarfRoots = collectScarfRoots(model)
	if #scarfRoots == 0 then
		return
	end

	local bodyParts = getBodyPartsExcludingScarf(model)
	local bodyCenter, bodySize = getPartsBoundingBox(bodyParts)
	if not bodyCenter or not bodySize then
		return
	end

	-- Punto aproximado del cuello:
	-- arriba del centro del cuerpo y ligeramente al frente.
	local neckPos = bodyCenter + Vector3.new(
		0,
		bodySize.Y * 0.23,
		-bodySize.Z * 0.24
	)

	for _, scarf in ipairs(scarfRoots) do
		local scarfCf, scarfSize = getPivotAndSize(scarf)
		if scarfCf and scarfSize then
			local delta = neckPos - scarfCf.Position
			local tooFar = delta.Magnitude > math.max(bodySize.X, bodySize.Y, bodySize.Z) * 0.35

			if tooFar then
				-- Mantiene la orientación original del pañuelo,
				-- solamente lo mueve al cuello.
				local rotationOnly = scarfCf - scarfCf.Position
				local target = CFrame.new(neckPos) * rotationOnly
				pivotObject(scarf, target)
			end
		end
	end
end

local function cleanCloneForViewport(model)
	local clone = model:Clone()

	-- Primero accesorios con Attachments normales.
	fixAccessoryPlacement(clone)

	-- Después corrige pañuelos guardados como piezas/modelos sueltos.
	fixLooseScarfPlacement(clone)

	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()

		elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			d:Destroy()

		elseif d:IsA("BasePart") then
			-- PREVIEW SOLAMENTE:
			-- anclar todas las piezas mantiene exactamente la posición
			-- con la que fueron guardadas en el modelo de pañuelo.
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true

		elseif d:IsA("ParticleEmitter")
			or d:IsA("Trail")
			or d:IsA("Beam") then
			d.Enabled = false
		end
	end

	local root = clone:FindFirstChild("HumanoidRootPart")
		or clone.PrimaryPart
		or clone:FindFirstChildWhichIsA("BasePart", true)

	if root then
		clone.PrimaryPart = root
	end

	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = false
		humanoid.PlatformStand = true
		pcall(function()
			humanoid.EvaluateStateMachine = false
		end)
	end

	return clone
end

local function setViewportModel(viewport, sourceModel)
	viewport:ClearAllChildren()

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport

	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	if not sourceModel then
		return false
	end

	local clone = cleanCloneForViewport(sourceModel)
	clone.Parent = worldModel

	local boxCf, boxSize = clone:GetBoundingBox()

	if boxSize.Magnitude <= 0 then
		return false
	end

	-- Mover todo el modelo como un bloque.
	-- Esto conserva exactamente el pañuelo y todos los accesorios.
	local offset = CFrame.new(-boxCf.Position)
	clone:PivotTo(offset * clone:GetPivot())

	local _, centeredSize = clone:GetBoundingBox()

	local halfHeight = centeredSize.Y * 0.5
	local halfWidth = math.max(centeredSize.X, centeredSize.Z) * 0.5

	local fov = math.rad(camera.FieldOfView)
	local verticalDistance = halfHeight / math.tan(fov * 0.5)
	local horizontalDistance = halfWidth / math.tan(fov * 0.5)

	local distance = math.max(verticalDistance, horizontalDistance) * 1.18
	distance = math.max(distance, 2.5)

	local focus = Vector3.new(0, centeredSize.Y * 0.02, 0)

	-- Vista 3/4 uniforme.
	camera.CFrame = CFrame.lookAt(
		Vector3.new(distance * 0.55, centeredSize.Y * 0.16, distance),
		focus
	)

	return true
end

local function refreshPetPreviews(data)
	if not data or not data.ok then
		currentViewport:ClearAllChildren()
		nextViewport:ClearAllChildren()
		currentTierLabel.Text = "?"
		nextTierLabel.Text = "?"
		return
	end

	local petName = tostring(data.petName or "Mascota")
	local activeModel = findBaseViewModel(petName)

	setViewportModel(currentViewport, activeModel)
	currentTierLabel.Text = tostring(data.currentDisplay or "Base")

	if data.maxLevel then
		nextViewport:ClearAllChildren()
		nextTierLabel.Text = "MÁXIMO"
	else
		local nextModel = findVariantModel(data.nextTier, petName)
		if data.tutorialDemo then
			nextModel = nextModel or activeModel
		else
			nextModel = nextModel or activeModel
		end
		setViewportModel(nextViewport, nextModel)
		nextTierLabel.Text = tostring(data.nextDisplay or "")
	end
end

local function clearIngredients()
	for _, child in ipairs(ingredientHolder:GetChildren()) do
		if child ~= ingredientLayout then
			child:Destroy()
		end
	end
end

local function ingredientCard(req)
	local card = Instance.new("Frame")
	card.Size = UDim2.fromOffset(86, 134)
	card.BackgroundColor3 = COLORS.cream
	card.BorderSizePixel = 0
	card.Parent = ingredientHolder
	corner(card, 6)
	stroke(card, 1.2, COLORS.panelDark)

	local icon = Instance.new("ImageLabel")
	icon.Name = "FruitIcon"
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromOffset(10, 8)
	icon.Size = UDim2.new(1, -18, 0, 58)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = tostring(req.image or "")
	icon.Visible = icon.Image ~= ""
	icon.Parent = card

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(4, icon.Visible and 60 or 20)
	name.Size = UDim2.new(1, -8, 0, icon.Visible and 26 or 48)
	name.Font = FONT
	name.Text = tostring(req.name or "?")
	name.TextWrapped = true
	name.TextSize = 12
	name.TextColor3 = COLORS.text
	name.Parent = card

	local amount = Instance.new("TextLabel")
	amount.BackgroundTransparency = 1
	amount.AnchorPoint = Vector2.new(0.5, 1)
	amount.Position = UDim2.new(0.5, 0, 1, -7)
	amount.Size = UDim2.new(1, -6, 0, 20)
	amount.Font = FONT
	if req.demo then
		amount.Text = "NECESITAS " .. tostring(req.needed or 0)
		amount.TextColor3 = COLORS.text
	else
		amount.Text = tostring(req.owned or 0) .. " / " .. tostring(req.needed or 0)
		amount.TextColor3 = req.enough and COLORS.greenDark or COLORS.red
	end
	amount.TextSize = 12
	amount.Parent = card
end

local function refresh()
	local ok, data

	if tutorialDemoActive or isFrankTutorialDemoStep() then
		tutorialDemoActive = true
		ok = true
		data = getTutorialDemoData()
	else
		ok, data = pcall(function()
			return GetUpgradeInfo:InvokeServer()
		end)
	end

	clearIngredients()

	if not ok or not data then
		petTitle.Text = "ERROR"
		refreshPetPreviews(nil)
		currentText.Text = "?"
		nextText.Text = "?"
		status.Text = "No se pudo obtener la información."
		craft.Visible = false
		return
	end

	if not data.ok then
		main.Size = UDim2.fromOffset(700, 430)
		title.Text = "MEJORAR MASCOTA"
		close.Visible = true
		tutorialInfo.Visible = false
		petTitle.Text = data.petName and string.upper(data.petName) or "SIN MASCOTA"
		refreshPetPreviews(data)
		currentText.Text = "?"
		nextText.Text = "?"
		status.Text = data.message or "Saca una mascota."
		status.Visible = true
		craft.Visible = false
		return
	end

	if data.tutorialDemo then
		main.Size = UDim2.fromOffset(700, 612)
		title.Text = "EJEMPLO DE MEJORA"
		close.Visible = false
		status.Visible = false
		tutorialInfo.Visible = true
		tutorialInfo.Text = "1) IZQUIERDA: tu mascota actual.\n2) CENTRO: los materiales que pide Frank.\n3) DERECHA: la siguiente rareza de tu mascota.\n\nMejorar aumenta sus habilidades.\nEste ejemplo NO gasta nada. Despues deberas sacar una mascota real y reunir sus materiales."
	else
		main.Size = UDim2.fromOffset(700, 430)
		title.Text = "MEJORAR MASCOTA"
		close.Visible = true
		status.Visible = false
		tutorialInfo.Visible = false
	end

	petTitle.Text = data.tutorialDemo and "EJEMPLO: OVEJA" or string.upper(data.petName or "MASCOTA")
	refreshPetPreviews(data)

	currentText.Text = (data.currentDisplay or "") .. "\n" .. (data.currentColor or "")
	currentText.TextColor3 = TIER_COLORS[data.currentTier] or COLORS.text

	if data.maxLevel then
		nextText.Text = "MÁXIMO"
		nextText.TextColor3 = TIER_COLORS.Legendario
		status.Text = data.message or "Esta mascota ya alcanzó el nivel máximo."
		craft.Visible = false
		return
	end

	nextText.Text = (data.nextDisplay or "") .. "\n" .. (data.nextColor or "")
	nextText.TextColor3 = TIER_COLORS[data.nextTier] or COLORS.text

	for _, req in ipairs(data.requirements or {}) do
		ingredientCard(req)
	end

	if data.tutorialDemo then
		craft.Text = "ENTENDIDO"
		craft.BackgroundColor3 = COLORS.green
		craft.Active = true
		pcall(function() craft.Interactable = true end)
		craft.Visible = true
		return
	end

	if data.canCraft then
		status.Text = ""
		craft.Text = "MEJORAR"
		craft.BackgroundColor3 = COLORS.green
		craft.Active = true
		pcall(function() craft.Interactable = true end)
	else
		status.Text = ""
		craft.Text = "FALTAN MATERIALES"
		craft.BackgroundColor3 = COLORS.disabled
		craft.Active = false
		pcall(function() craft.Interactable = false end)
	end

	craft.Visible = true
end

local function openCrafting()
	dialogueGui.Enabled = false
	gui.Enabled = true
	updateResponsiveScale()

	mainScale.Scale = math.max(mainScale.Scale * 0.92, 0.68)
	TweenService:Create(
		mainScale,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Scale = math.clamp(math.min(
			(workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.X or 690) / 690,
			(workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y or 470) / 470
			), 0.72, 1)}
	):Play()

	refresh()
	forceHudHidden()
end

local function closeAll()
	gui.Enabled = false
	dialogueGui.Enabled = false
	dialogueData = nil
	tutorialDemoActive = false
	main.Size = UDim2.fromOffset(700, 430)
	title.Text = "MEJORAR MASCOTA"
	close.Visible = true
	tutorialInfo.Visible = false
	restoreGameHud()
	unlockMovement()
	unblockFrankInputs()
end

local function beginFrankConversation()
	hideGameHud()
	lockMovement()
	blockFrankInputs()

	-- Durante el paso de Frank NO pedimos una mascota real.
	-- Abrimos directamente la interfaz de mejora con datos de ejemplo.
	if isFrankTutorialDemoStep() then
		tutorialDemoActive = true
		tutorialDemoReported = false
		dialogueData = nil
		dialogueGui.Enabled = false
		openCrafting()
		forceHudHidden()
		return
	end

	tutorialDemoActive = false
	local ok, data = pcall(function()
		return GetUpgradeInfo:InvokeServer()
	end)

	if not ok then
		data = {
			ok = false,
			message = "No se pudo leer tu mascota.",
		}
	end

	showFrankDialogue(data)
	forceHudHidden()
end

dialogueClick.MouseButton1Click:Connect(function()
	if dialogueData and dialogueData.ok then
		openCrafting()
	else
		closeAll()
	end
end)

close.MouseButton1Click:Connect(function()
	if tutorialDemoActive then return end
	closeAll()
end)
OpenUpgradeUI.OnClientEvent:Connect(beginFrankConversation)


ContextActionService:BindActionAtPriority("PetUpgradeCloseDeviceAction", function(_, inputState)
	if inputState ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
	if gui.Enabled or dialogueGui.Enabled then
		closeAll()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, true, 5500, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
pcall(function()
	ContextActionService:SetTitle("PetUpgradeCloseDeviceAction", "Cerrar")
	ContextActionService:SetPosition("PetUpgradeCloseDeviceAction", UDim2.new(1, -86, 1, -412))
end)


UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	if (gui.Enabled or dialogueGui.Enabled) and input.KeyCode == Enum.KeyCode.Escape then
		if tutorialDemoActive then return end
		closeAll()
	end
end)

craft.MouseButton1Click:Connect(function()
	if not craft.Active then return end

	if tutorialDemoActive then
		craft.Active = false
		pcall(function() craft.Interactable = false end)
		craft.Text = "LISTO"
		reportFrankTutorialDone()
		task.wait(0.18)
		closeAll()
		return
	end

	craft.Active = false
	craft.Text = "MEJORANDO..."

	local ok, result = pcall(function()
		return UpgradePet:InvokeServer()
	end)

	if ok and result then
		status.Text = result.message or "Listo."
	else
		status.Text = "Ocurrió un error al mejorar."
	end

	task.wait(0.65)
	refresh()
	forceHudHidden()
end)

player.CharacterAdded:Connect(function()
	if hudLockActive or movementLocked then
		task.wait(0.2)

		if hudLockActive then
			forceHudHidden()
		end

		if movementLocked then
			-- Reaplica bloqueo al nuevo Humanoid.
			movementLocked = false
			lockMovement()
		end
	end
end)
