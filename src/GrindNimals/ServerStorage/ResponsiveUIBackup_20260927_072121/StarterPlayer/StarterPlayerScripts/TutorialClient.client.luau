local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local system = ReplicatedStorage:WaitForChild("TutorialSystem")
local shared = require(system:WaitForChild("TutorialShared"))
local config = require(system:WaitForChild("TutorialConfig"))
local remotes = system:WaitForChild("Remotes")

local RequestState = remotes:WaitForChild("RequestState")
local ClientAction = remotes:WaitForChild("ClientAction")
local StateRemote = remotes:WaitForChild("State")
local CompletedRemote = remotes:WaitForChild("TutorialCompleted")

local FONT = Enum.Font.FredokaOne
local COLORS = config.COLORS

local currentStep
local totalSteps = 1
local stateSerial = 0
local cleanup = {}
local controls
local controlsLocked = false

local highlight
local arrowGui
local uiOverlay
local routeFolder
local routeArrows = {}

local pendingPayload
local lastRenderedSignature = nil
local loadingWatcherStarted = false

local FREE_EGG_NAME = "Huevo Mascota"
local freeEggBaseline = nil
local freeEggReportSent = false
local freeEggPurchaseBusy = false
local petMenuOpenReportSent = false

local function getOwnedEggCount()
	local inventory = player:FindFirstChild("TradePetsInventory")
	if not inventory then return 0 end

	local total = 0
	for _, item in ipairs(inventory:GetDescendants()) do
		if item:IsA("IntValue") or item:IsA("NumberValue") then
			local itemName = tostring(item:GetAttribute("ItemName") or item.Name)
			if itemName == FREE_EGG_NAME then
				total += math.max(0, tonumber(item.Value) or 0)
			end
		end
	end
	return total
end

local function equipTutorialEgg()
	player:SetAttribute("SelectedBackpackPet", FREE_EGG_NAME)
	local equipRemote = ReplicatedStorage:FindFirstChild("EquipPet")
	if equipRemote and equipRemote:IsA("RemoteEvent") then
		equipRemote:FireServer(FREE_EGG_NAME)
	end
end

local function closeBrizabelleShop()
	local shopGui = playerGui:FindFirstChild("BrizabelleEggGui")
	if shopGui and shopGui:IsA("ScreenGui") then
		shopGui.Enabled = false
	end
end

local function lockBrizabelleShopButtons(targetButton)
	local shopGui = playerGui:FindFirstChild("BrizabelleEggGui")
	if not shopGui then return function() end end

	local saved = {}
	for _, obj in ipairs(shopGui:GetDescendants()) do
		if obj:IsA("GuiButton") and obj ~= targetButton then
			local oldInteractable = nil
			pcall(function() oldInteractable = obj.Interactable end)
			saved[obj] = {
				Active = obj.Active,
				Selectable = obj.Selectable,
				AutoButtonColor = obj.AutoButtonColor,
				Interactable = oldInteractable,
			}

			obj.Active = false
			obj.Selectable = false
			obj.AutoButtonColor = false
			pcall(function() obj.Interactable = false end)
		end
	end

	-- El boton gratis SIEMPRE queda habilitado.
	if targetButton and targetButton:IsA("GuiButton") then
		targetButton.Active = true
		targetButton.Selectable = true
		pcall(function() targetButton.Interactable = true end)
	end

	return function()
		for obj, old in pairs(saved) do
			if obj and obj.Parent then
				obj.Active = old.Active
				obj.Selectable = old.Selectable
				obj.AutoButtonColor = old.AutoButtonColor
				if old.Interactable ~= nil then
					pcall(function() obj.Interactable = old.Interactable end)
				end
			end
		end
	end
end

local function reportFreeEggIfAcquired()
	if not currentStep or currentStep.Id ~= "BUY_FREE_EGG" then return false end
	if freeEggReportSent or freeEggBaseline == nil then return false end

	if getOwnedEggCount() > freeEggBaseline then
		freeEggReportSent = true
		equipTutorialEgg()
		closeBrizabelleShop()
		ClientAction:FireServer("ReportAction", {Name = "FREE_EGG_CLAIMED"})
		return true
	end
	return false
end

local function buyTutorialFreeEgg()
	if freeEggPurchaseBusy then return end
	if not currentStep or currentStep.Id ~= "BUY_FREE_EGG" then return end

	if reportFreeEggIfAcquired() then
		return
	end

	local eggSystem = ReplicatedStorage:FindFirstChild("BrizabelleEggSystem")
	local buyEgg = eggSystem and eggSystem:FindFirstChild("BuyEgg")
	if not buyEgg or not buyEgg:IsA("RemoteFunction") then
		warn("[TutorialV6.5] No encontre BrizabelleEggSystem.BuyEgg.")
		return
	end

	freeEggPurchaseBusy = true
	local ok, result = pcall(function()
		return buyEgg:InvokeServer()
	end)
	freeEggPurchaseBusy = false

	if not ok then
		warn("[TutorialV6.5] BuyEgg fallo:", result)
		return
	end

	if result and result.ok then
		equipTutorialEgg()
		closeBrizabelleShop()

		task.defer(function()
			for _ = 1, 20 do
				if reportFreeEggIfAcquired() then return end
				task.wait(0.05)
			end
			ClientAction:FireServer("ReportAction", {Name = "FREE_EGG_CLAIMED"})
		end)
	else
		warn("[TutorialV6.5] No se pudo obtener el huevo:", result and result.message or "sin respuesta")
	end
end

local function lower(text)
	return string.lower(tostring(text or ""))
end

local function create(className, props, parent)
	local obj = Instance.new(className)
	for key, value in pairs(props or {}) do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

local function corner(obj, radius)
	return create("UICorner", {CornerRadius = UDim.new(0, radius or 10)}, obj)
end

local function stroke(obj, thickness, color)
	return create("UIStroke", {
		Thickness = thickness or 2,
		Color = color or COLORS.Dark,
	}, obj)
end

local function addCleanup(item)
	table.insert(cleanup, item)
	return item
end

local function destroy(obj)
	if obj then
		pcall(function() obj:Destroy() end)
	end
end

local function clearRouteOnly()
	for i = #routeArrows, 1, -1 do
		local arrow = routeArrows[i]
		if arrow and arrow.Model then
			destroy(arrow.Model)
		end
		routeArrows[i] = nil
	end
	destroy(routeFolder)
	routeFolder = nil
end

local function clearCleanup()
	stateSerial += 1

	for _, item in ipairs(cleanup) do
		pcall(function()
			if typeof(item) == "RBXScriptConnection" then
				item:Disconnect()
			elseif typeof(item) == "Instance" then
				item:Destroy()
			elseif typeof(item) == "function" then
				item()
			end
		end)
	end
	cleanup = {}

	destroy(highlight)
	destroy(arrowGui)
	destroy(uiOverlay)
	clearRouteOnly()

	highlight = nil
	arrowGui = nil
	uiOverlay = nil
end

--============================================================
-- UI PRINCIPAL - V5.5 OBJETIVO LIMPIO
-- Solo muestra una frase corta en pantalla.
--============================================================

local gui = playerGui:FindFirstChild("GrindNimalsTutorialGui")
if not gui then
	gui = create("ScreenGui", {
		Name = "GrindNimalsTutorialGui",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 1000000,
		ZIndexBehavior = Enum.ZIndexBehavior.Global,
	}, playerGui)
end
gui:ClearAllChildren()

-- Este Frame existe solo para posicionar/escalar el texto.
-- NO tiene fondo, barra, descripcion ni contador de pasos.
local panel = create("Frame", {
	Name = "ObjectiveHolder",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.085),
	Size = UDim2.fromOffset(760, 76),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 50,
}, gui)

local panelScale = create("UIScale", {Scale = 1}, panel)

local title = create("TextLabel", {
	Name = "ObjectiveText",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = FONT,
	Text = "",
	TextScaled = true,
	TextWrapped = true,
	TextColor3 = COLORS.Cream,
	TextStrokeColor3 = COLORS.Dark,
	TextStrokeTransparency = 0,
	ZIndex = 51,
}, panel)

local titleConstraint = create("UITextSizeConstraint", {
	MinTextSize = 24,
	MaxTextSize = 42,
}, title)

-- Boton pequeno, solo se usa en pasos INFO como Frank/Tutorial completado.
local button = create("TextButton", {
	Name = "ContinueButton",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 1, 6),
	Size = UDim2.fromOffset(180, 40),
	BackgroundColor3 = COLORS.Green,
	BorderSizePixel = 0,
	Font = FONT,
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
	TextStrokeColor3 = COLORS.Dark,
	TextStrokeTransparency = 0.15,
	AutoButtonColor = false,
	Visible = false,
	ZIndex = 52,
}, panel)
corner(button, 10)
stroke(button, 2)

local helpButton = create("TextButton", {
	Name = "HelpButton",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -18, 0, 88),
	Size = UDim2.fromOffset(50, 50),
	BackgroundColor3 = COLORS.Cream,
	BorderSizePixel = 0,
	Font = FONT,
	Text = "?",
	TextScaled = true,
	TextColor3 = COLORS.Text,
	Visible = false,
	ZIndex = 40,
}, gui)
corner(helpButton, 25)
stroke(helpButton, 3)

local baseScale = 1
local function responsive()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	baseScale = math.clamp(math.min(viewport.X / 1000, viewport.Y / 650), 0.62, 1)
	panelScale.Scale = baseScale
end
responsive()

local cameraConnection
local function hookCamera()
	if cameraConnection then cameraConnection:Disconnect() end
	local camera = workspace.CurrentCamera
	if camera then
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(responsive)
	end
end
hookCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	responsive()
	hookCamera()
end)

local function getControls()
	if controls then return controls end
	local playerScripts = player:FindFirstChild("PlayerScripts") or player:WaitForChild("PlayerScripts", 8)
	local playerModule = playerScripts and (playerScripts:FindFirstChild("PlayerModule") or playerScripts:WaitForChild("PlayerModule", 8))
	if playerModule then
		local ok, module = pcall(require, playerModule)
		if ok and module and module.GetControls then
			controls = module:GetControls()
		end
	end
	return controls
end

local function setMovementLocked(locked)
	controlsLocked = locked
	local c = getControls()
	if c then
		pcall(function()
			if locked then c:Disable() else c:Enable() end
		end)
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and locked then root.AssemblyLinearVelocity = Vector3.zero end
end

player.CharacterAdded:Connect(function()
	if controlsLocked then
		task.wait(0.25)
		setMovementLocked(true)
	end
end)

local function setPanelPosition(step)
	-- Objetivo normal arriba al centro. Solo el final puede ir al centro.
	if step.PanelPosition == "Center" then
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Position = UDim2.fromScale(0.5, 0.48)
	else
		panel.AnchorPoint = Vector2.new(0.5, 0)
		panel.Position = UDim2.fromScale(0.5, 0.085)
	end
end

local function animatePanelIn()
	panel.Visible = true
	panelScale.Scale = baseScale * 0.82
	title.TextTransparency = 1
	title.TextStrokeTransparency = 1
	TweenService:Create(panelScale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = baseScale}):Play()
	TweenService:Create(title, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
		TextStrokeTransparency = 0,
	}):Play()
end

local function playCheck()
	local check = create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(150, 120),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = "OK!",
		TextScaled = true,
		TextColor3 = COLORS.Green,
		TextStrokeColor3 = COLORS.Dark,
		TextStrokeTransparency = 0.15,
		ZIndex = 100,
	}, gui)
	local sc = create("UIScale", {Scale = 0.4}, check)
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
	TweenService:Create(check, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
	task.delay(0.6, function() destroy(check) end)
end

--============================================================
-- DETECTOR DE PANTALLAS DE CARGA / TP - V5.4
--
-- IMPORTANTE:
-- Ya NO escaneamos textos como "CARGANDO" por todo PlayerGui.
-- Eso podia detectar Labels hijos aunque su Frame padre estuviera oculto
-- y dejaba TODO el tutorial invisible para siempre.
--
-- Tus dos sistemas reales son:
--   GameStartLoadingGui      -> se DESTRUYE al terminar la carga.
--   WorldTeleportLoadingGui  -> existe siempre, pero Enabled=false al acabar.
--============================================================

local function isBlockingLoadingVisible()
	local startGui = playerGui:FindFirstChild("GameStartLoadingGui")
	if startGui and startGui:IsA("ScreenGui") and startGui.Enabled then
		return true
	end

	local teleportGui = playerGui:FindFirstChild("WorldTeleportLoadingGui")
	if teleportGui and teleportGui:IsA("ScreenGui") and teleportGui.Enabled then
		return true
	end

	return false
end

local function hideTutorialWhileLoading()
	clearCleanup()
	panel.Visible = false
	helpButton.Visible = false
end

--============================================================
-- MARCADOR NORMAL SOBRE NPC / OBJETIVO - V5.6
--
-- Se elimino por completo el indicador lateral/off-screen que mostraba
-- "BRIZABELLE 89m". Solo queda el marcador normal sobre el NPC.
--============================================================

local function buildLocator(target, step, serial)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local origin = root and root.Position or nil
	local adornee = shared.GetAdornee(target, origin)
	if not adornee then return false end

	if step.Highlight then
		highlight = create("Highlight", {
			Name = "TutorialHighlight",
			Adornee = target:IsA("Folder") and adornee or target,
			FillColor = COLORS.Gold,
			FillTransparency = 0.82,
			OutlineColor = COLORS.Gold,
			OutlineTransparency = 0.05,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		}, workspace.CurrentCamera or workspace)

		local pulse = TweenService:Create(
			highlight,
			TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{FillTransparency = 0.64}
		)
		pulse:Play()
		addCleanup(function() pulse:Cancel() end)
	end

	arrowGui = create("BillboardGui", {
		Name = "TutorialObjectiveArrow",
		Adornee = adornee,
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(210, 125),
		StudsOffset = Vector3.new(0, 5.5, 0),
		MaxDistance = 1000,
	}, gui)

	create("TextLabel", {
		Size = UDim2.fromScale(1, 0.58),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = "▼",
		TextScaled = true,
		TextColor3 = COLORS.Gold,
		TextStrokeColor3 = COLORS.Dark,
		TextStrokeTransparency = 0,
		ZIndex = 4,
	}, arrowGui)

	local objectiveLabel = step.Target and step.Target.Label or step.Title or "OBJETIVO"
	create("TextLabel", {
		Position = UDim2.fromScale(0, 0.52),
		Size = UDim2.fromScale(1, 0.34),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = objectiveLabel,
		TextScaled = true,
		TextColor3 = COLORS.Cream,
		TextStrokeColor3 = COLORS.Dark,
		TextStrokeTransparency = 0,
		ZIndex = 4,
	}, arrowGui)

	local bounce = TweenService:Create(
		arrowGui,
		TweenInfo.new(0.70, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{StudsOffset = Vector3.new(0, 6.45, 0)}
	)
	bounce:Play()
	addCleanup(function() bounce:Cancel() end)

	-- Solo ocultamos el marcador normal mientras realmente hay una pantalla
	-- de carga. NO creamos ningun indicador lateral.
	addCleanup(RunService.RenderStepped:Connect(function()
		if serial ~= stateSerial or not target.Parent then return end
		if arrowGui then
			arrowGui.Enabled = not isBlockingLoadingVisible()
		end
	end))

	return true
end

--============================================================
-- CAMINO GUIA V5.9 - FLECHAS 3D DIRECTAS, SIN BEAM NI PATHFINDING
--
-- Esta version evita los dos problemas anteriores:
--   * Beam: se veia como una aguja/linea a cierta distancia.
--   * Pathfinding: podia trabarse al caminar o despues de un teleport.
--
-- Ahora son chevrons 3D reales, locales, que se colocan directamente
-- entre la posicion ACTUAL del jugador y el objetivo en cada frame.
--============================================================

local function getCharacterRoot()
	local character = player.Character
	if not character then return nil end
	return character:FindFirstChild("HumanoidRootPart")
end

local function ensureRouteFolder()
	if routeFolder and routeFolder.Parent then return routeFolder end
	routeFolder = create("Folder", {Name = "TutorialRouteArrows"}, workspace)
	return routeFolder
end

local function makeArrowPiece(parent, name, size)
	return create("Part", {
		Name = name,
		Size = size,
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = (config.ROUTE and config.ROUTE.Color) or Color3.fromRGB(249, 241, 0),
		Transparency = 0.03,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	}, parent)
end

local function createRouteArrow(index)
	local model = create("Model", {Name = string.format("TutorialChevron_%02d", index)}, ensureRouteFolder())
	local left = makeArrowPiece(model, "Left", Vector3.new(0.48, 0.12, 2.15))
	local right = makeArrowPiece(model, "Right", Vector3.new(0.48, 0.12, 2.15))
	local glow = create("PointLight", {
		Name = "Glow",
		Brightness = 0.18,
		Range = 3.5,
		Shadows = false,
		Color = (config.ROUTE and config.ROUTE.Color) or Color3.fromRGB(249, 241, 0),
	}, left)

	local arrow = {Model = model, Left = left, Right = right, Glow = glow}
	routeArrows[index] = arrow
	return arrow
end

local function getRouteArrow(index)
	return routeArrows[index] or createRouteArrow(index)
end

local function setArrowVisible(arrow, visible)
	if not arrow then return end
	local transparency = visible and 0.03 or 1
	arrow.Left.Transparency = transparency
	arrow.Right.Transparency = transparency
	arrow.Glow.Enabled = visible
end

local function hideUnusedArrows(fromIndex)
	for i = fromIndex, #routeArrows do
		setArrowVisible(routeArrows[i], false)
	end
end

local function groundAt(position)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {ensureRouteFolder()}
	if player.Character then
		table.insert(ignore, player.Character)
	end
	params.FilterDescendantsInstances = ignore

	local result = workspace:Raycast(
		position + Vector3.new(0, 14, 0),
		Vector3.new(0, -34, 0),
		params
	)
	if result then
		return result.Position
	end
	return Vector3.new(position.X, position.Y - 2.8, position.Z)
end

local function positionChevron(arrow, worldPos, flatDirection, groundOffset)
	-- CFrame.lookAt apunta el -Z hacia el objetivo.
	local base = CFrame.lookAt(
		worldPos + Vector3.new(0, groundOffset, 0),
		worldPos + Vector3.new(0, groundOffset, 0) + flatDirection,
		Vector3.yAxis
	)

	-- Forma de chevron ^ apuntando hacia el -Z local.
	arrow.Left.CFrame = base
		* CFrame.new(-0.48, 0, 0.28)
		* CFrame.Angles(0, math.rad(-43), 0)
	arrow.Right.CFrame = base
		* CFrame.new(0.48, 0, 0.28)
		* CFrame.Angles(0, math.rad(43), 0)

	setArrowVisible(arrow, true)
end

local function startSmoothRoute(target, step, serial)
	clearRouteOnly()
	ensureRouteFolder()

	local phase = 0
	local lastRootPosition = nil
	local groundCache = {}
	local groundTimer = 0

	addCleanup(RunService.RenderStepped:Connect(function(dt)
		if serial ~= stateSerial or currentStep ~= step or not target.Parent then return end

		if isBlockingLoadingVisible() then
			hideUnusedArrows(1)
			groundCache = {}
			lastRootPosition = nil
			return
		end

		local root = getCharacterRoot()
		if not root then
			hideUnusedArrows(1)
			return
		end

		local targetPos = shared.GetWorldPosition(target, root.Position)
		if not targetPos then
			hideUnusedArrows(1)
			return
		end

		local routeCfg = config.ROUTE or {}
		local flatDelta = Vector3.new(
			targetPos.X - root.Position.X,
			0,
			targetPos.Z - root.Position.Z
		)
		local distance = flatDelta.Magnitude
		local hideDistance = routeCfg.HideDistance or 18

		-- Cerca de Brizabelle/Frank/Lex: desaparece TODA la ruta.
		if distance <= hideDistance or distance < 0.1 then
			hideUnusedArrows(1)
			return
		end

		local direction = flatDelta.Unit
		local spacing = routeCfg.Spacing or 5.2
		local startOffset = routeCfg.StartOffset or 4.5
		local stopBeforeTarget = routeCfg.StopBeforeTarget or 10
		local maxArrows = routeCfg.MaxArrows or 18
		local flowSpeed = routeCfg.FlowSpeed or 3.0
		local groundOffset = routeCfg.GroundOffset or 0.18

		-- Si hubo TP/salto grande, limpiamos alturas viejas al instante.
		if lastRootPosition and (root.Position - lastRootPosition).Magnitude >= (routeCfg.TeleportJumpDistance or 18) then
			groundCache = {}
			phase = 0
		end
		lastRootPosition = root.Position

		phase = (phase + dt * flowSpeed) % spacing
		groundTimer += dt
		local refreshGround = groundTimer >= (routeCfg.GroundRefreshSeconds or 0.08)
		if refreshGround then groundTimer = 0 end

		local usableDistance = math.max(0, distance - stopBeforeTarget)
		local count = 0

		for i = 1, maxArrows do
			local d = startOffset + phase + (i - 1) * spacing
			if d >= usableDistance then break end

			local rawPos = root.Position + direction * d
			local groundPos = groundCache[i]
			if refreshGround or not groundPos then
				groundPos = groundAt(rawPos)
				groundCache[i] = groundPos
			else
				-- Mantiene X/Z pegados al jugador entre raycasts para que el
				-- seguimiento se vea suave; conserva solo la altura cacheada.
				groundPos = Vector3.new(rawPos.X, groundPos.Y, rawPos.Z)
				groundCache[i] = groundPos
			end

			count += 1
			positionChevron(getRouteArrow(count), groundPos, direction, groundOffset)
		end

		hideUnusedArrows(count + 1)
	end))
end

local function startTargetTracking(step, serial)
	local alive = true
	addCleanup(function() alive = false end)

	task.spawn(function()
		local target
		local locatorBuilt = false
		local routeStarted = false
		local announcedTarget = false
		local announcedMissing = false

		while alive and serial == stateSerial and currentStep == step do
			if not target or not target.Parent then
				target = shared.FindTarget(step, player)
				locatorBuilt = false
				routeStarted = false
				clearRouteOnly()
				if not target and not announcedMissing then
					announcedMissing = true
					warn("[TutorialGuide] Buscando objetivo para " .. tostring(step.Id) .. "...")
				end
			end

			if target then
				if not announcedTarget then
					announcedTarget = true
					print("[TutorialGuide] Objetivo encontrado:", target:GetFullName())
				end
				if not locatorBuilt then
					locatorBuilt = buildLocator(target, step, serial)
				end
				if step.Route and not routeStarted and (config.ROUTE == nil or config.ROUTE.Enabled ~= false) then
					routeStarted = true
					startSmoothRoute(target, step, serial)
				end
			end

			task.wait(target and 0.20 or 0.12)
		end
	end)
end

--============================================================
-- ENFOQUE DE BOTONES DEL TUTORIAL
--============================================================

local function getGuiDescriptor(step)
	if step.GuiTarget and config.GuiTargets[step.GuiTarget] then
		return config.GuiTargets[step.GuiTarget]
	end
	if step.UiTarget then return step.UiTarget end
	return nil
end

local function makeUiFocus(step, serial)
	local descriptor = getGuiDescriptor(step)
	if not descriptor then return end

	-- V6.1: resalta el objetivo. En Brizabelle, solo OBTENER GRATIS queda interactivo.
	local focusedObject = nil
	local focusStroke = nil
	local focusArrow = nil
	local strokeTween = nil
	local arrowTween = nil
	local activatedConnection = nil
	local restoreOtherButtons = nil

	local function clearFocusVisual()
		if activatedConnection then activatedConnection:Disconnect(); activatedConnection = nil end
		if restoreOtherButtons then restoreOtherButtons(); restoreOtherButtons = nil end
		if strokeTween then strokeTween:Cancel(); strokeTween = nil end
		if arrowTween then arrowTween:Cancel(); arrowTween = nil end
		destroy(focusArrow)
		destroy(focusStroke)
		focusArrow = nil
		focusStroke = nil
		focusedObject = nil
	end

	addCleanup(clearFocusVisual)

	local function focus(obj)
		if focusedObject == obj and focusStroke and focusStroke.Parent then return end
		clearFocusVisual()
		focusedObject = obj

		if step.Id == "BUY_FREE_EGG" and obj.Name == "BuyHoldButton" then
			restoreOtherButtons = lockBrizabelleShopButtons(obj)
		end

		focusStroke = create("UIStroke", {
			Name = "TutorialFocusStroke",
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = COLORS.Gold,
			Thickness = 5,
			Transparency = 0,
			LineJoinMode = Enum.LineJoinMode.Round,
		}, obj)

		focusArrow = create("TextLabel", {
			Name = "TutorialFocusArrow",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0, -7),
			Size = UDim2.fromOffset(56, 44),
			BackgroundTransparency = 1,
			Font = FONT,
			Text = "▼",
			TextScaled = true,
			TextColor3 = COLORS.Gold,
			TextStrokeColor3 = COLORS.Dark,
			TextStrokeTransparency = 0,
			Active = false,
			Selectable = false,
			ZIndex = math.max(100, obj.ZIndex + 20),
		}, obj)

		strokeTween = TweenService:Create(
			focusStroke,
			TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{Transparency = 0.55}
		)
		strokeTween:Play()

		arrowTween = TweenService:Create(
			focusArrow,
			TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{Position = UDim2.new(0.5, 0, 0, -15)}
		)
		arrowTween:Play()

		if obj:IsA("GuiButton") then
			activatedConnection = obj.Activated:Connect(function()
				if serial ~= stateSerial or currentStep ~= step then return end
				if step.Id == "BUY_FREE_EGG" and obj.Name == "BuyHoldButton" then
					task.spawn(buyTutorialFreeEgg)
				else
					ClientAction:FireServer("UiTargetActivated", {Target = obj.Name})
				end
			end)
		end
	end

	addCleanup(RunService.Heartbeat:Connect(function()
		if serial ~= stateSerial or currentStep ~= step then return end
		local obj = shared.FindGuiObject(player, descriptor)
		if not obj or not obj:IsA("GuiObject") or not obj.Visible or isBlockingLoadingVisible() then
			if focusArrow then focusArrow.Visible = false end
			if focusStroke then focusStroke.Enabled = false end
			return
		end

		focus(obj)
		if focusArrow then focusArrow.Visible = true end
		if focusStroke then focusStroke.Enabled = true end
	end))
end

--============================================================
-- AYUDA
--============================================================

local function showHelp()
	local existing = gui:FindFirstChild("HelpPanel")
	if existing then
		existing:Destroy()
		return
	end

	local hp = create("Frame", {
		Name = "HelpPanel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -80, 0, 88),
		Size = UDim2.fromOffset(430, 500),
		BackgroundColor3 = COLORS.Panel,
		BorderSizePixel = 0,
		ZIndex = 90,
	}, gui)
	corner(hp, 14)
	stroke(hp, 4)

	local heading = create("TextLabel", {
		Position = UDim2.fromOffset(14, 12),
		Size = UDim2.new(1, -28, 0, 42),
		BackgroundColor3 = COLORS.Cream,
		BorderSizePixel = 0,
		Font = FONT,
		Text = "Guia de GrindNimals",
		TextScaled = true,
		TextColor3 = COLORS.Text,
		ZIndex = 91,
	}, hp)
	corner(heading, 8)

	local close = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 62),
		Size = UDim2.fromOffset(40, 34),
		BackgroundColor3 = COLORS.Red,
		BorderSizePixel = 0,
		Font = FONT,
		Text = "X",
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 92,
	}, hp)
	corner(close, 8)

	local list = create("ScrollingFrame", {
		Position = UDim2.fromOffset(14, 104),
		Size = UDim2.new(1, -28, 1, -118),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 91,
	}, hp)
	create("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, list)

	for _, section in ipairs(config.HelpSections or {}) do
		local card = create("TextLabel", {
			Size = UDim2.new(1, -8, 0, 78),
			BackgroundColor3 = COLORS.Card,
			BorderSizePixel = 0,
			Font = FONT,
			Text = section.Title .. "\n" .. section.Body,
			TextWrapped = true,
			TextSize = 18,
			TextColor3 = COLORS.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = 92,
		}, list)
		corner(card, 8)
		stroke(card, 2)
	end

	close.MouseButton1Click:Connect(function() hp:Destroy() end)
end

local function showPetMenuInfoModal()
	local overlay = create("Frame", {
		Name = "PetMenuTutorialModal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.28,
		BorderSizePixel = 0,
		ZIndex = 300,
	}, gui)
	addCleanup(overlay)

	local card = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.54),
		Size = UDim2.fromOffset(760, 452),
		BackgroundColor3 = COLORS.Panel,
		BorderSizePixel = 0,
		ZIndex = 301,
	}, overlay)
	corner(card, 18)
	stroke(card, 3)

	local head = create("TextLabel", {
		Position = UDim2.fromOffset(18, 16),
		Size = UDim2.new(1, -36, 0, 52),
		BackgroundColor3 = COLORS.Cream,
		BorderSizePixel = 0,
		Font = FONT,
		Text = "MENU DEL HUEVO MASCOTA",
		TextSize = 28,
		TextColor3 = COLORS.Text,
		ZIndex = 302,
	}, card)
	corner(head, 10)
	stroke(head, 2)

	local intro = create("TextLabel", {
		Position = UDim2.fromOffset(24, 78),
		Size = UDim2.new(1, -48, 0, 52),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = "Presiona R para abrir el menu de tu mascota. Desde ahi veras sus necesidades y podras usar sus cuidados.",
		TextWrapped = true,
		TextSize = 21,
		TextColor3 = COLORS.Cream,
		TextStrokeColor3 = COLORS.Dark,
		TextStrokeTransparency = 0.15,
		ZIndex = 302,
	}, card)

	local row = create("Frame", {
		Position = UDim2.fromOffset(24, 132),
		Size = UDim2.new(1, -48, 0, 208),
		BackgroundTransparency = 1,
		ZIndex = 302,
	}, card)
	local rowLayout = create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)

	local function addInfoCard(titleText, bodyText)
		local infoCard = create("Frame", {
			Size = UDim2.fromOffset(224, 202),
			BackgroundColor3 = COLORS.Card,
			BorderSizePixel = 0,
			ZIndex = 302,
		}, row)
		corner(infoCard, 12)
		stroke(infoCard, 2)

		local cardTitle = create("TextLabel", {
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.new(1, -20, 0, 34),
			BackgroundColor3 = COLORS.Cream,
			BorderSizePixel = 0,
			Font = FONT,
			Text = titleText,
			TextSize = 21,
			TextColor3 = COLORS.Text,
			ZIndex = 303,
		}, infoCard)
		corner(cardTitle, 8)
		stroke(cardTitle, 1.5)

		create("TextLabel", {
			Position = UDim2.fromOffset(12, 54),
			Size = UDim2.new(1, -24, 1, -66),
			BackgroundTransparency = 1,
			Font = FONT,
			Text = bodyText,
			TextWrapped = true,
			TextSize = 18,
			TextColor3 = COLORS.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 303,
		}, infoCard)
	end

	addInfoCard("DORMIR", "Si tu huevo tiene sueno, llevalo a su cama en Casa Jugadores. Acercate a la cama y usa el boton para que descanse.")
	addInfoCard("LIMPIARSE", "Al caminar con tu huevo este se ensucia. Usa la esponja y manten presionado hasta llenar la barra de limpieza.")
	addInfoCard("ACARICIAR", "Para acariciar a tu huevo, manten presionado el cuidado hasta completar el progreso. Esto tambien cuenta como atencion para tu mascota.")

	local footer = create("TextLabel", {
		Position = UDim2.fromOffset(24, 352),
		Size = UDim2.new(1, -48, 0, 42),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = "Ahora usa el menu real de tu huevo mascota y completa el cuidado para continuar.",
		TextWrapped = true,
		TextSize = 18,
		TextColor3 = COLORS.Cream,
		TextStrokeColor3 = COLORS.Dark,
		TextStrokeTransparency = 0.15,
		ZIndex = 302,
	}, card)

	local okButton = create("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(230, 46),
		BackgroundColor3 = COLORS.Green,
		BorderSizePixel = 0,
		Font = FONT,
		Text = "ENTENDIDO",
		TextSize = 22,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeColor3 = COLORS.Dark,
		TextStrokeTransparency = 0.15,
		AutoButtonColor = false,
		ZIndex = 302,
	}, card)
	corner(okButton, 10)
	stroke(okButton, 2)

	setMovementLocked(true)
	okButton.MouseButton1Click:Connect(function()
		if overlay and overlay.Parent then
			overlay:Destroy()
		end
		setMovementLocked(currentStep and currentStep.LockMovement == true)
	end)
end

helpButton.MouseButton1Click:Connect(showHelp)

button.MouseButton1Click:Connect(function()
	if currentStep and currentStep.CompleteTutorial then
		ClientAction:FireServer("FinalButton")
	else
		ClientAction:FireServer("Continue")
	end
end)

CompletedRemote.OnClientEvent:Connect(function()
	playCheck()
	helpButton.Visible = true
	panel.Visible = false
	setMovementLocked(false)
	clearCleanup()
end)

--============================================================
-- ESTADO
--============================================================

local function buildSignature(data, step)
	if not data or not step then
		return tostring(data and data.Completed)
	end
	return table.concat({
		tostring(data.Step or ""),
		tostring(data.Completed),
		tostring(step.Id or ""),
		tostring(step.Index or 0),
	}, "|")
end

local function renderState(data, step, count, fullConfig)
	clearCleanup()

	config = fullConfig or config
	COLORS = config.COLORS
	currentStep = step
	totalSteps = count or 1
	local serial = stateSerial

	if not data or data.Completed then
		helpButton.Visible = true
		panel.Visible = false
		setMovementLocked(false)
		lastRenderedSignature = buildSignature(data, step)
		return
	end

	if not step then
		panel.Visible = false
		lastRenderedSignature = buildSignature(data, step)
		return
	end

	helpButton.Visible = false
	title.Text = step.ObjectiveText or step.Title or step.Id

	button.Text = step.ButtonText or "ENTENDIDO"
	local manual = step.Type == "INFO" or step.OptionalAction == true
	button.Visible = manual

	setPanelPosition(step)
	animatePanelIn()
	setMovementLocked(step.LockMovement == true)


	if step.Id == "BUY_FREE_EGG" then
		freeEggReportSent = false
		freeEggPurchaseBusy = false
		local inventory = player:FindFirstChild("TradePetsInventory")
		if not inventory then inventory = player:WaitForChild("TradePetsInventory", 3) end
		freeEggBaseline = getOwnedEggCount()

		task.spawn(function()
			while serial == stateSerial and currentStep == step do
				if reportFreeEggIfAcquired() then return end
				task.wait(0.12)
			end
		end)
	else
		freeEggBaseline = nil
		freeEggReportSent = false
		freeEggPurchaseBusy = false
	end

	-- V6.5: respaldo directo del tutorial. Si el menu REAL de mascota
	-- ya se abrio con R, avanzamos aunque el LocalScript de cuidados
	-- tarde un frame en reportarlo.
	if step.Id == "PET_MENU_R" then
		petMenuOpenReportSent = false
		task.spawn(function()
			while serial == stateSerial and currentStep == step do
				local careGui = playerGui:FindFirstChild("EggCareViewGui")
				local realMenuOpen = player:GetAttribute("PetCareMenuOpen") == true
					or (careGui and careGui:IsA("ScreenGui") and careGui.Enabled)
				if realMenuOpen and not petMenuOpenReportSent then
					petMenuOpenReportSent = true
					ClientAction:FireServer("ReportAction", {Name = "PET_MENU_OPENED"})
					print("[TutorialV6.5] Menu real detectado -> PET_MENU_OPENED")
					return
				end
				task.wait(0.05)
			end
		end)
	else
		petMenuOpenReportSent = false
	end

	if step.Arrow or step.Highlight or step.Route or step.Target or step.DynamicTarget then
		startTargetTracking(step, serial)
	end

	if step.GuiTarget or step.UiTarget or step.Type == "OPEN_UI" or step.Type == "CLICK_UI" then
		makeUiFocus(step, serial)
	end

	-- PET_MENU_NEEDS se explica exclusivamente desde TutorialPetMenuBridgeClient.
	-- No crear otro modal aqui para evitar que aparezca dos veces.

	lastRenderedSignature = buildSignature(data, step)
end

local function applyState(data, step, count, fullConfig)
	pendingPayload = table.pack(data, step, count, fullConfig)

	if isBlockingLoadingVisible() then
		hideTutorialWhileLoading()
		return
	end

	local signature = buildSignature(data, step)
	if signature == lastRenderedSignature and panel.Visible then
		return
	end

	renderState(data, step, count, fullConfig)
end

StateRemote.OnClientEvent:Connect(applyState)
print("[TutorialV6.8] Cliente activo. Esperando estado del servidor...")

local function requestFreshState()
	local ok, data, step, count, fullConfig = pcall(function()
		return RequestState:InvokeServer()
	end)
	if ok and data and step then
		pendingPayload = table.pack(data, step, count, fullConfig)
		renderState(data, step, count, fullConfig)
		print("[TutorialV6.8] Estado mostrado:", tostring(data.Step))
		return true
	end
	return false
end

local function startLoadingWatcher()
	if loadingWatcherStarted then return end
	loadingWatcherStarted = true
	task.spawn(function()
		local wasBlocking = isBlockingLoadingVisible()
		if wasBlocking then
			hideTutorialWhileLoading()
			print("[TutorialV6.8] Esperando a que termine la pantalla de carga...")
		end

		while true do
			local blocking = isBlockingLoadingVisible()
			if blocking and not wasBlocking then
				hideTutorialWhileLoading()
			elseif (not blocking) and wasBlocking then
				task.wait(0.15)
				-- Pedimos el estado REAL otra vez. No reutilizamos un estado viejo.
				if not requestFreshState() and pendingPayload then
					renderState(table.unpack(pendingPayload, 1, pendingPayload.n))
				end
			end
			wasBlocking = blocking
			task.wait(0.12)
		end
	end)
end
startLoadingWatcher()

-- Respaldo: si el servidor cambia los atributos del jugador pero por alguna
-- carrera el Remote de estado no llega al cliente, pedimos el estado de nuevo.
local function scheduleStateRefresh()
	task.defer(function()
		if not isBlockingLoadingVisible() then
			requestFreshState()
		end
	end)
end

player:GetAttributeChangedSignal("TutorialStep"):Connect(scheduleStateRefresh)
player:GetAttributeChangedSignal("TutorialCompleted"):Connect(scheduleStateRefresh)

-- Reintenta la peticion inicial. Esto corrige el caso donde el servidor
-- todavia estaba cargando el DataStore cuando entro el LocalScript.
task.spawn(function()
	for attempt = 1, 25 do
		local ok, data, step, count, fullConfig = pcall(function()
			return RequestState:InvokeServer()
		end)
		if ok and data and step then
			applyState(data, step, count, fullConfig)
			return
		end
		task.wait(0.35)
	end
	warn("[TutorialV6.5] No se pudo obtener el estado inicial del tutorial.")
end)
