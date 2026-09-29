--============================================================
-- GRINDNIMALS - TUTORIAL PET MENU BRIDGE V3
-- UBICACION:
-- StarterPlayer > StarterPlayerScripts > TutorialPetMenuBridgeClient
-- TIPO: LocalScript
--
-- IMPORTANTE:
-- Este script esta separado de PetMenuHotkeyClient para NO provocar
-- "Out of local registers" en ese script grande.
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local tutorialSystem = ReplicatedStorage:WaitForChild("TutorialSystem")
local remotes = tutorialSystem:WaitForChild("Remotes")
local ClientAction = remotes:WaitForChild("ClientAction")

local FONT = Enum.Font.FredokaOne

local panel = nil
local understoodButton = nil
local explanationDismissed = false
local explanationShownThisStep = false
local menuOpenReported = false
local careReported = false
local pressStartedAt = nil
local pressStartedNearEgg = false
local ignoreCareUntil = 0

local function reportAction(name)
	ClientAction:FireServer("ReportAction", {Name = name})
	print("[TutorialPetMenuBridge] ReportAction:", name)
end

local function isMenuOpen()
	if player:GetAttribute("PetCareMenuOpen") == true then
		return true
	end
	local gui = playerGui:FindFirstChild("EggCareViewGui")
	return gui and gui:IsA("ScreenGui") and gui.Enabled == true
end

local function destroyPanel()
	if panel then
		panel:Destroy()
		panel = nil
	end
	understoodButton = nil
end

local function dismissExplanation()
	if not panel then return end
	explanationDismissed = true
	ignoreCareUntil = os.clock() + 0.15
	destroyPanel()
	print("[TutorialPetMenuBridge] Explicacion cerrada. El menu real sigue abierto: acaricia ahora a tu huevo.")
end

local function pointInside(guiObject, point)
	if not guiObject or not guiObject.Parent then return false end
	local p = guiObject.AbsolutePosition
	local s = guiObject.AbsoluteSize
	return point.X >= p.X and point.X <= p.X + s.X
		and point.Y >= p.Y and point.Y <= p.Y + s.Y
end

local function addCorner(obj, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = obj
end

local function addStroke(obj, thickness, color)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color
	s.Parent = obj
end

local function makeText(parent, text, position, size, textSize, align)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = FONT
	label.Text = text
	label.TextWrapped = true
	label.TextSize = textSize
	label.TextColor3 = Color3.fromRGB(55, 31, 18)
	label.TextXAlignment = align or Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.ZIndex = 903
	label.Parent = parent
	return label
end

local function showExplanation()
	if panel or explanationDismissed or explanationShownThisStep then return end
	if tostring(player:GetAttribute("TutorialStep") or "") ~= "PET_MENU_NEEDS" then return end
	if not isMenuOpen() then return end

	local eggGui = playerGui:FindFirstChild("EggCareViewGui")
	if not eggGui or not eggGui:IsA("ScreenGui") then
		warn("[TutorialPetMenuBridge] No encontre EggCareViewGui")
		return
	end

	local shade = Instance.new("Frame")
	shade.Name = "TutorialEggExplanation"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.fromRGB(20, 14, 10)
	shade.BackgroundTransparency = 0.28
	shade.BorderSizePixel = 0
	shade.Active = true
	shade.ZIndex = 900
	shade.Parent = eggGui
	panel = shade
	explanationShownThisStep = true

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.53)
	card.Size = UDim2.fromOffset(720, 430)
	card.BackgroundColor3 = Color3.fromRGB(204, 144, 71)
	card.BorderSizePixel = 0
	card.Active = true
	card.ZIndex = 901
	card.Parent = shade
	addCorner(card, 18)
	addStroke(card, 4, Color3.fromRGB(82, 45, 24))

	local header = Instance.new("TextLabel")
	header.Position = UDim2.fromOffset(18, 16)
	header.Size = UDim2.new(1, -36, 0, 54)
	header.BackgroundColor3 = Color3.fromRGB(255, 232, 190)
	header.BorderSizePixel = 0
	header.Font = FONT
	header.Text = "NECESIDADES DE TU HUEVO MASCOTA"
	header.TextSize = 27
	header.TextColor3 = Color3.fromRGB(55, 31, 18)
	header.ZIndex = 902
	header.Parent = card
	addCorner(header, 10)
	addStroke(header, 2, Color3.fromRGB(82, 45, 24))

	makeText(
		card,
		"Tu huevo necesita dormir, limpiarse y recibir carino. Pulsa ENTENDIDO y, sin salir de este menu, acaricia ahora a tu huevo.",
		UDim2.fromOffset(28, 82),
		UDim2.new(1, -56, 0, 58),
		20,
		Enum.TextXAlignment.Left
	)

	local function infoCard(x, titleText, bodyText)
		local f = Instance.new("Frame")
		f.Position = UDim2.fromOffset(x, 150)
		f.Size = UDim2.fromOffset(210, 178)
		f.BackgroundColor3 = Color3.fromRGB(245, 216, 176)
		f.BorderSizePixel = 0
		f.ZIndex = 902
		f.Parent = card
		addCorner(f, 12)
		addStroke(f, 2, Color3.fromRGB(82, 45, 24))

		local h = Instance.new("TextLabel")
		h.Position = UDim2.fromOffset(10, 10)
		h.Size = UDim2.new(1, -20, 0, 34)
		h.BackgroundColor3 = Color3.fromRGB(255, 232, 190)
		h.BorderSizePixel = 0
		h.Font = FONT
		h.Text = titleText
		h.TextSize = 21
		h.TextColor3 = Color3.fromRGB(55, 31, 18)
		h.ZIndex = 903
		h.Parent = f
		addCorner(h, 8)

		local b = makeText(
			f,
			bodyText,
			UDim2.fromOffset(12, 52),
			UDim2.new(1, -24, 1, -64),
			17,
			Enum.TextXAlignment.Left
		)
		b.TextYAlignment = Enum.TextYAlignment.Top
	end

	infoCard(24, "DORMIR", "Cuando tenga sueno, podras hacerlo descansar en su cama.")
	infoCard(255, "LIMPIARSE", "Al caminar se ensuciara. Usa la esponja y manten presionado hasta completar la limpieza.")
	infoCard(486, "ACARICIAR", "Pulsa ENTENDIDO y manten presionado sobre el huevo. Hazlo ahora para continuar el tutorial.")

	local understood = Instance.new("TextButton")
	understood.AnchorPoint = Vector2.new(0.5, 1)
	understood.Position = UDim2.new(0.5, 0, 1, -18)
	understood.Size = UDim2.fromOffset(230, 48)
	understood.BackgroundColor3 = Color3.fromRGB(85, 168, 77)
	understood.BorderSizePixel = 0
	understood.Font = FONT
	understood.Text = "ENTENDIDO"
	understood.TextSize = 22
	understood.TextColor3 = Color3.new(1, 1, 1)
	understood.TextStrokeColor3 = Color3.fromRGB(82, 45, 24)
	understood.TextStrokeTransparency = 0.15
	understood.AutoButtonColor = true
	understood.Active = true
	understood.Selectable = true
	understood.Modal = true
	understood.ZIndex = 1000
	understood.Parent = card
	addCorner(understood, 10)
	addStroke(understood, 2, Color3.fromRGB(82, 45, 24))
	understoodButton = understood

	understood.Activated:Connect(dismissExplanation)
	understood.MouseButton1Click:Connect(dismissExplanation)

	print("[TutorialPetMenuBridge] Panel de explicacion mostrado.")
end

local function handleMenuOpened()
	if not isMenuOpen() then return end
	local step = tostring(player:GetAttribute("TutorialStep") or "")

	if step == "PET_MENU_R" and not menuOpenReported then
		menuOpenReported = true
		reportAction("PET_MENU_OPENED")
		task.delay(0.1, showExplanation)
	elseif step == "PET_MENU_NEEDS" then
		showExplanation()
	end
end

player:GetAttributeChangedSignal("PetCareMenuOpen"):Connect(function()
	if isMenuOpen() then
		handleMenuOpened()
	else
		destroyPanel()
	end
end)

player:GetAttributeChangedSignal("TutorialStep"):Connect(function()
	local step = tostring(player:GetAttribute("TutorialStep") or "")
	if step == "PET_MENU_R" then
		menuOpenReported = false
		careReported = false
		explanationDismissed = false
		explanationShownThisStep = false
	elseif step == "PET_MENU_NEEDS" then
		careReported = false
		explanationDismissed = false
		task.delay(0.08, showExplanation)
	else
		destroyPanel()
	end
end)

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "EggCareViewGui" then
		task.delay(0.1, handleMenuOpened)
	end
end)

-- Respaldo para detectar un acariciado real por mantener presionado
-- cerca del centro, donde se muestra el huevo en el menu de cuidados.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if not explanationDismissed or careReported then return end
	if tostring(player:GetAttribute("TutorialStep") or "") ~= "PET_MENU_NEEDS" then return end
	if not isMenuOpen() or os.clock() < ignoreCareUntil then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local position = input.Position
	local center = Vector2.new(viewport.X * 0.5, viewport.Y * 0.52)
	local radius = math.min(viewport.X, viewport.Y) * 0.32
	pressStartedNearEgg = (Vector2.new(position.X, position.Y) - center).Magnitude <= radius
	pressStartedAt = pressStartedNearEgg and os.clock() or nil
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	-- Respaldo fuerte para ENTENDIDO: si el menu real consume Activated,
	-- comprobamos manualmente si el click/tap termino dentro del boton.
	if panel and understoodButton and understoodButton.Parent then
		local pos = input.Position
		if pointInside(understoodButton, Vector2.new(pos.X, pos.Y)) then
			dismissExplanation()
			return
		end
	end

	if not pressStartedAt then return end
	local held = os.clock() - pressStartedAt
	pressStartedAt = nil

	if careReported or not pressStartedNearEgg then return end
	if held < 0.45 then return end
	if tostring(player:GetAttribute("TutorialStep") or "") ~= "PET_MENU_NEEDS" then return end
	if not isMenuOpen() then return end

	careReported = true
	reportAction("PET_CARE_USED")
end)

task.delay(1, handleMenuOpened)
print("[TutorialPetMenuBridge] V3 ACTIVO | panel unico + acariciar en el mismo menu + salto al bosque")
