-- AVATAR EDITOR CLIENT V20 - SOPORTA CHARACTER NUEVO AL CAMBIAR AVATAR
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AvatarEditorService = game:GetService("AvatarEditorService")

local Button = require(script.Button)
local Maid = require(ReplicatedStorage.Maid)
local TableUtil = require(ReplicatedStorage.TableUtil)
local Catalog = require(ReplicatedStorage.Catalog)
local ScreenSpace = require(ReplicatedStorage.ScreenSpace)
local PurchasePrompt = require(script.PurchasePrompt)
local NumberSlider = require(script.NumberSlider)

local CAMERA_BIND = "CameraBind"
local DEPTH = 7
local CAMERA_OFFSET = 0.75

local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)

local remoteEvent = ReplicatedStorage:WaitForChild("UpdateAvatar")

--============================================================
-- V11 - INICIO SEGURO
-- El LocalScript termina dentro de Players.<jugador>.PlayerScripts.
-- Obtenemos al Player desde el árbol y evitamos depender de LocalPlayer
-- durante el primer frame de carga.
--============================================================
local function resolvePlayer()
	local found = script:FindFirstAncestorOfClass("Player")
	while not found do
		task.wait()
		found = script:FindFirstAncestorOfClass("Player")
	end
	return found
end

local player = resolvePlayer()

--============================================================
-- V15 - CAMARA SIN INVISICAM + SIN GUARDIAS QUE ROMPAN ROPA 3D
--============================================================
-- V16: NO intentamos escribir DevCameraOcclusionMode desde LocalScript.
-- Studio no da permiso y solo generaba:
-- "Insufficent permissions to set DevCameraOcclusionMode".

-- El guard viejo fuerza LocalTransparencyModifier = 0 cada frame.
-- Eso puede pelear con el ocultado interno que usa layered clothing.
-- Lo desactivamos también en runtime por si todavía existe en PlayerScripts.
task.defer(function()
	for _, child in ipairs(player:WaitForChild("PlayerScripts"):GetChildren()) do
		if child:IsA("LocalScript") and child.Name == "AvatarTransparencyGuard" then
			pcall(function()
				child.Enabled = false
			end)
		end
	end
end)

-- Quitamos bindings viejos aunque hayan alcanzado a ejecutarse antes.
local function removeOldTransparencyBindings()
	pcall(function()
		RunService:UnbindFromRenderStep("AvatarTransparencyGuardPermanentV1")
	end)
	pcall(function()
		RunService:UnbindFromRenderStep("AvatarEditorTransparencyGuardV11")
	end)
end

for _, delayTime in ipairs({0, 0.15, 0.4, 1, 2, 4}) do
	task.delay(delayTime, removeOldTransparencyBindings)
end

local playerGui = player:WaitForChild("PlayerGui")
local avatarEditorGui = playerGui:WaitForChild("AvatarEditor")

local character = player.Character or player.CharacterAdded:Wait()
local rootPart = character.PrimaryPart or character:WaitForChild("HumanoidRootPart")
local humanoid = character:FindFirstChildWhichIsA("Humanoid") or character:WaitForChild("Humanoid")

local playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
local controlModule = playerModule:GetControls()
--local cameraModule = playerModule:GetCameras()

local function getCurrentCamera()
	local currentCamera = workspace.CurrentCamera
	while currentCamera == nil do
		workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
		currentCamera = workspace.CurrentCamera
	end
	return currentCamera
end

local camera = getCurrentCamera()

--============================================================
-- V6 - CORRECCION DE PERSONAJE TRANSPARENTE
-- Roblox puede dejar LocalTransparencyModifier aplicado cuando una
-- cámara personalizada se acerca al personaje. Nunca modificamos
-- Transparency real de las partes: solo limpiamos el efecto LOCAL.
--============================================================
local originalCameraType = camera.CameraType
local originalCameraSubject = camera.CameraSubject
local originalFieldOfView = camera.FieldOfView

local function clearCharacterLocalTransparency(_targetCharacter)
	-- V17 - NO TOCAR LocalTransparencyModifier.
	--
	-- Roblox usa LocalTransparencyModifier internamente para ocultar la
	-- geometria del cuerpo que queda debajo de la ropa 3D/layered clothing.
	-- Si lo forzamos a 0, el cuerpo base aparece atravesando la ropa como
	-- una silueta/fantasma despues de cambiar un articulo en el armario.
	--
	-- La camara del editor ya es Scriptable, asi que no necesitamos limpiar
	-- transparencia por frame. Esta funcion queda como no-op para no romper
	-- llamadas antiguas del resto del script.
end

--============================================================
-- V19 - LIMPIEZA SEGURA DE INVISICAM
--
-- V18 recorría TODO Workspace y podía cambiar LocalTransparencyModifier
-- de las mascotas. PetRenderer usa esa propiedad a propósito para ocultar
-- la mascota fuente y mostrar solamente su clon visual. Al ponerla a 0,
-- aparecía una segunda oveja/gato fantasma.
--
-- V19:
--   1) Solo recuerda partes ESTÁTICAS/ANCLADAS del mapa.
--   2) Excluye Characters, mascotas y cualquier Model con Humanoid.
--   3) Al cerrar solo restaura LAS MISMAS INSTANCIAS que existían al abrir.
--   4) Nunca toca objetos nuevos creados durante el editor.
--============================================================

local worldLtmBeforeEditor = {}

local function isDynamicCharacterOrPet(object)
	local model = object:FindFirstAncestorOfClass("Model")
	if not model then
		return false
	end

	-- Character real de cualquier jugador.
	if Players:GetPlayerFromCharacter(model) ~= nil then
		return true
	end

	-- Clon visual creado por PetRenderer.
	if model:GetAttribute("ClientPetVisual") == true then
		return true
	end

	-- Respaldo por nombre del clon visual.
	if string.find(model.Name, "_ClientVisual", 1, true) then
		return true
	end

	-- Mascotas fuente y otros rigs dinámicos.
	if model:FindFirstChildOfClass("Humanoid") ~= nil then
		return true
	end

	return false
end

local function isSafeStaticMapPart(object)
	return object:IsA("BasePart")
		and object.Anchored == true
		and not isDynamicCharacterOrPet(object)
end

local function rememberWorldTransparencyBeforeEditor()
	table.clear(worldLtmBeforeEditor)

	for _, object in ipairs(workspace:GetDescendants()) do
		if isSafeStaticMapPart(object) then
			-- Guardamos también los ceros. Así sabemos exactamente qué partes
			-- existían al abrir sin confundirlas con objetos creados después.
			worldLtmBeforeEditor[object] = object.LocalTransparencyModifier
		end
	end
end

local function restoreWorldTransparencyAfterEditor()
	local restored = 0

	-- MUY IMPORTANTE: iteramos el snapshot, NO todo Workspace.
	for object, expected in pairs(worldLtmBeforeEditor) do
		if object
			and object.Parent
			and isSafeStaticMapPart(object)
			and object.LocalTransparencyModifier ~= expected then

			object.LocalTransparencyModifier = expected
			restored += 1
		end
	end

	table.clear(worldLtmBeforeEditor)

	if restored > 0 then
	end
end

local function getLiveHumanoid()
	local liveCharacter = player.Character
	if not liveCharacter then
		return nil
	end
	return liveCharacter:FindFirstChildOfClass("Humanoid")
end

local function restoreGameplayCamera()
	camera = getCurrentCamera()

	local liveHumanoid = getLiveHumanoid()
	if liveHumanoid then
		humanoid = liveHumanoid
	end

	-- Primero dejamos la cámara exactamente donde estaba antes del editor.
	camera.CameraType = Enum.CameraType.Scriptable
	if originalCamCFrame then
		camera.CFrame = originalCamCFrame
	end
	camera.FieldOfView = originalFieldOfView or 70

	if humanoid and humanoid.Parent then
		camera.CameraSubject = humanoid
	elseif originalCameraSubject and originalCameraSubject.Parent then
		camera.CameraSubject = originalCameraSubject
	end

	-- Gameplay siempre vuelve a Custom. Nunca dejamos Scriptable guardado.
	camera.CameraType = Enum.CameraType.Custom

	-- Reafirmamos un frame después para ganar cualquier carrera con otros
	-- scripts de cámara, pero SIN forzar CFrame otra vez.
	task.defer(function()
		RunService.RenderStepped:Wait()

		if isOpen then
			return
		end
		if player:GetAttribute("PetCareMenuOpen") == true then
			return
		end

		local currentCamera = workspace.CurrentCamera
		local currentHumanoid = getLiveHumanoid()
		if currentCamera then
			if currentHumanoid then
				currentCamera.CameraSubject = currentHumanoid
			end
			if currentCamera.CameraType == Enum.CameraType.Scriptable then
				currentCamera.CameraType = Enum.CameraType.Custom
			end
		end
	end)
end

local function hideSpawnForceFieldVisual(targetCharacter)
	if not targetCharacter then
		return
	end

	for _, object in ipairs(targetCharacter:GetChildren()) do
		if object:IsA("ForceField") then
			pcall(function()
				object.Visible = false
			end)
		end
	end
end

local function forceTransparencyRecovery(targetCharacter)
	-- V15:
	-- Ya NO forzamos LocalTransparencyModifier = 0.
	-- La ropa 3D de Roblox necesita poder ocultar geometría interna del cuerpo.
	-- Forzarlo a 0 puede hacer visible el cuerpo por debajo de la ropa,
	-- que es exactamente el efecto de "silueta" que estamos viendo.
	hideSpawnForceFieldVisual(targetCharacter)
end

local avatarEditorFrame = avatarEditorGui.Main
local catalogFrame = avatarEditorFrame.Catalog
local viewerFrame = avatarEditorFrame.Viewer

local detailsOverlay = avatarEditorGui.DetailsOverlay
local toggleButton = avatarEditorGui.Toggle

local doneButton = viewerFrame.Done
local viewButton = viewerFrame.View

local headerFrame = catalogFrame.Header
local categoryTabsFrame = headerFrame.CategoryTabs
local subCategoryTabsFrame = headerFrame.SubCategoryTabs
local searchFrame = headerFrame.Search

local containerFrame = catalogFrame.Container
local scrollingFrame = containerFrame.ScrollingFrame
local scrollingFrameUIGridLayout = scrollingFrame.UIGridLayout

local scaleFrame = containerFrame.ScaleFrame
local scaleFrameUIGridLayout = scaleFrame.UIGridLayout

local searchTextBox = searchFrame.TextBox
local clearSearchButton = searchFrame.Clear

--============================================================
-- AVATAR EDITOR V4 - PESTAÑAS SOLO TEXTO + ITEMS CREMA
-- Mantiene la lógica original del catálogo y UpdateAvatar.
--============================================================
local THEME = {
	Brown = Color3.fromRGB(204, 144, 71),
	BrownDark = Color3.fromRGB(111, 75, 48),
	BrownDeep = Color3.fromRGB(61, 50, 43),
	Card = Color3.fromRGB(255, 239, 207),
	Cream = Color3.fromRGB(255, 236, 199),
	CreamLight = Color3.fromRGB(255, 246, 225),
	ItemCard = Color3.fromRGB(255, 239, 207),
	ItemCardHover = Color3.fromRGB(255, 246, 225),
	Gold = Color3.fromRGB(238, 179, 91),
	Green = Color3.fromRGB(91, 178, 96),
	Red = Color3.fromRGB(184, 73, 66),
	White = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(224, 210, 190),

	-- V9: buscador claro, texto negro.
	SearchBackground = Color3.fromRGB(255, 244, 215),
	SearchText = Color3.fromRGB(28, 22, 18),
	SearchPlaceholder = Color3.fromRGB(92, 70, 50),

	-- V10: acabado cartoon igual a las tiendas del juego.
	TabNormal = Color3.fromRGB(255, 236, 199),
	TabHover = Color3.fromRGB(255, 246, 225),
	TabSelectedMain = Color3.fromRGB(78, 171, 87),
	TabSelectedSub = Color3.fromRGB(238, 179, 91),
	Outline = Color3.fromRGB(92, 57, 35),
	Shadow = Color3.fromRGB(77, 48, 31),
}

-- Los Name NO se cambian porque la lógica del catálogo depende de ellos.
-- Solo se cambia el texto que ve el jugador.
local SPANISH = {
	Accessories = "Accesorios",
	Clothing = "Ropa",
	Clothes = "Ropa",
	Body = "Cuerpo",
	Appearance = "Apariencia",
	Animations = "Animaciones",
	Wearing = "Equipado",
	Avatars = "Avatares",
	Hair = "Cabello",
	Hat = "Sombreros",
	Hats = "Sombreros",
	Faces = "Rostros",
	FaceAccessory = "Cara",
	NeckAccessory = "Cuello",
	Neck = "Cuello",
	ShoulderAccessory = "Hombros",
	Shoulder = "Hombros",
	FrontAccessory = "Frente",
	Front = "Frente",
	BackAccessory = "Espalda",
	Back = "Espalda",
	WaistAccessory = "Cintura",
	Waist = "Cintura",
	TShirt = "Camisetas",
	Shirt = "Camisas",
	Pants = "Pantalones",
	TShirtAccessory = "Camisetas 3D",
	ShirtAccessory = "Camisas 3D",
	PantsAccessory = "Pantalones 3D",
	JacketAccessory = "Chaquetas",
	SweaterAccessory = "Suéteres",
	ShortsAccessory = "Shorts",
	DressSkirtAccessory = "Vestidos",
	LeftShoeAccessory = "Zapato izq.",
	RightShoeAccessory = "Zapato der.",
	EyebrowAccessory = "Cejas",
	EyelashAccessory = "Pestañas",
	Mood = "Expresiones",
	Face = "Rostros",
	Head = "Cabezas",
	Torso = "Torso",
	LeftArm = "Brazo izq.",
	RightArm = "Brazo der.",
	LeftLeg = "Pierna izq.",
	RightLeg = "Pierna der.",
	SkinTone = "Piel",
	Scale = "Cuerpo",
	Climb = "Escalar",
	Fall = "Caída",
	Idle = "Reposo",
	Jump = "Salto",
	Run = "Correr",
	Swim = "Nadar",
	Walk = "Caminar",
	Done = "LISTO",
	View = "VER",
}

local TEXT_TRANSLATIONS = {
	["Search"] = "Buscar",
	["Accessories"] = "Accesorios",
	["Accessory"] = "Accesorios",
	["Clothing"] = "Ropa",
	["Clothes"] = "Ropa",
	["Body"] = "Cuerpo",
	["Appearance"] = "Apariencia",
	["Animations"] = "Animaciones",
	["Animation"] = "Animaciones",
	["Wearing"] = "Equipado",
	["Avatars"] = "Avatares",
	["Hair"] = "Cabello",
	["Hats"] = "Sombreros",
	["Faces"] = "Rostros",
	["Neck"] = "Cuello",
	["Shoulder"] = "Hombros",
	["Front"] = "Frente",
	["Back"] = "Espalda",
	["Waist"] = "Cintura",
	["Hat"] = "Sombreros",
	["Face Accessory"] = "Accesorio de cara",
	["Neck Accessory"] = "Accesorio de cuello",
	["Shoulder Accessory"] = "Accesorio de hombro",
	["Front Accessory"] = "Accesorio frontal",
	["Back Accessory"] = "Accesorio de espalda",
	["Waist Accessory"] = "Accesorio de cintura",
	["TShirt"] = "Camisetas",
	["Shirt"] = "Camisa",
	["Pants"] = "Pantalones",
	["TShirtAccessory"] = "Camisetas 3D",
	["ShirtAccessory"] = "Camisas 3D",
	["PantsAccessory"] = "Pantalones 3D",
	["JacketAccessory"] = "Chaquetas",
	["SweaterAccessory"] = "Suéteres",
	["ShortsAccessory"] = "Shorts",
	["DressSkirtAccessory"] = "Vestidos",
	["LeftShoeAccessory"] = "Zapato izq.",
	["RightShoeAccessory"] = "Zapato der.",
	["EyebrowAccessory"] = "Cejas",
	["EyelashAccessory"] = "Pestañas",
	["Mood"] = "Expresiones",
	["Face"] = "Rostro",
	["Head"] = "Cabeza",
	["Skin Tone"] = "Tono de piel",
	["SkinTone"] = "Tono de piel",
	["Scale"] = "Cuerpo",
	["Height"] = "Altura",
	["Width"] = "Ancho",
	["Proportion"] = "Proporción",
	["Body Type"] = "Tipo de cuerpo",
	["BodyType"] = "Tipo de cuerpo",
	["Climb"] = "Escalar",
	["Fall"] = "Caída",
	["Idle"] = "Reposo",
	["Jump"] = "Saltar",
	["Run"] = "Correr",
	["Swim"] = "Nadar",
	["Walk"] = "Caminar",
	["Done"] = "LISTO",
	["View"] = "VER",
	["Buy"] = "COMPRAR",
	["Purchase"] = "COMPRAR",
	["Cancel"] = "CANCELAR",
	["Close"] = "CERRAR",
	["Details"] = "DETALLES",
	["Wear"] = "PONER",
	["Remove"] = "QUITAR",
}

local function translateTextTree(root)
	for _, obj in ipairs(root:GetDescendants()) do
		if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
			local translated = TEXT_TRANSLATIONS[obj.Text]
			if translated then
				obj.Text = translated
			end
			if obj:IsA("TextBox") then
				local translatedPlaceholder = TEXT_TRANSLATIONS[obj.PlaceholderText]
				if translatedPlaceholder then
					obj.PlaceholderText = translatedPlaceholder
				end
			end
		end
	end
end


local function ensureCorner(gui, radius)
	if not gui or not gui:IsA("GuiObject") then
		return
	end
	local corner = gui:FindFirstChild("AvatarThemeCorner") or gui:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		corner.Name = "AvatarThemeCorner"
		corner.Parent = gui
	end
	corner.CornerRadius = UDim.new(0, radius or 8)
end

local function ensureStroke(gui, color, thickness, transparency, name)
	if not gui or not gui:IsA("GuiObject") then
		return nil
	end
	name = name or "AvatarThemeStroke"
	local stroke = gui:FindFirstChild(name)
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Name = name
		stroke.Parent = gui
	end
	stroke.Color = color or THEME.Cream
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0
	return stroke
end

local function removeOldThemeStroke(gui)
	if not gui then
		return
	end
	local old = gui:FindFirstChild("AvatarThemeStroke")
	if old then
		old:Destroy()
	end
end

local function removeDecorativeBorders(gui)
	if not gui then
		return
	end
	for _, descendant in ipairs(gui:GetDescendants()) do
		local n = string.lower(descendant.Name)
		if descendant:IsA("UIStroke") and descendant.Name ~= "CatalogCardStroke" then
			descendant.Enabled = false
		elseif (descendant:IsA("ImageLabel") or descendant:IsA("ImageButton")) and descendant.Name ~= "Icon" then
			if string.find(n, "border") or string.find(n, "corner") or string.find(n, "outline") or string.find(n, "frame") then
				descendant.Visible = false
			end
		end
	end
end

local function styleTextObject(gui)
	if gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox") then
		gui.Font = Enum.Font.FredokaOne
		gui.TextColor3 = THEME.White
		if gui:IsA("TextBox") then
			gui.PlaceholderColor3 = THEME.Muted
		end
	end
end

local function setSpanishLabel(button)
	if not button or not button:IsA("GuiButton") then
		return
	end
	local text = SPANISH[button.Name]
	if not text then
		return
	end

	if button:IsA("TextButton") then
		button.Text = text
		button.Font = Enum.Font.FredokaOne
		button.TextColor3 = THEME.White
		button.TextSize = 13
		return
	end

	local label = button:FindFirstChild("EtiquetaEspanol")
	if not label then
		label = Instance.new("TextLabel")
		label.Name = "EtiquetaEspanol"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Position = UDim2.fromScale(0, 0)
		label.ZIndex = button.ZIndex + 5
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = THEME.White
		label.TextStrokeTransparency = 0.75
		label.TextScaled = true
		label.Parent = button
		local limit = Instance.new("UITextSizeConstraint")
		limit.MinTextSize = 10
		limit.MaxTextSize = 14
		limit.Parent = label
	end
	label.Text = text
end

-- Animación EXACTA del botón que mandaste: cambia Size, no mete borde ni fondo.
local function addToggleButtonAnimation(button)
	if not button or not button:IsA("GuiButton") then
		return
	end
	if button:GetAttribute("AvatarToggleSizeAnimation") then
		return
	end
	button:SetAttribute("AvatarToggleSizeAnimation", true)
	button.AutoButtonColor = false

	-- El botón de vestirse queda solo con su imagen.
	button.BorderSizePixel = 0
	button.BackgroundTransparency = 1
	removeOldThemeStroke(button)
	for _, child in ipairs(button:GetChildren()) do
		if child:IsA("UIStroke") then
			child.Enabled = false
		end
	end

	local normalSize = button.Size
	local hoverSize = normalSize + UDim2.new(0, 6, 0, 6)
	local clickSize = normalSize - UDim2.new(0, 4, 0, 4)

	local hoverTween = TweenService:Create(
		button,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Size = hoverSize}
	)
	local normalTween = TweenService:Create(
		button,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Size = normalSize}
	)
	local clickTween = TweenService:Create(
		button,
		TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Size = clickSize}
	)

	button.MouseEnter:Connect(function()
		hoverTween:Play()
	end)
	button.MouseLeave:Connect(function()
		normalTween:Play()
	end)
	button.MouseButton1Down:Connect(function()
		clickTween:Play()
	end)
	button.MouseButton1Up:Connect(function()
		hoverTween:Play()
	end)
end

-- Animación ligera para botones dentro del menú. Usa UIScale para no romper layouts.
local function addMenuButtonAnimation(button)
	if not button or not button:IsA("GuiButton") then
		return
	end
	if button:GetAttribute("AvatarMenuAnimation") then
		return
	end
	button:SetAttribute("AvatarMenuAnimation", true)
	button.AutoButtonColor = false

	local scale = button:FindFirstChild("AvatarMenuScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "AvatarMenuScale"
		scale.Scale = 1
		scale.Parent = button
	end

	local hovered = false
	local tween
	local function go(value, duration)
		if tween then tween:Cancel() end
		tween = TweenService:Create(scale, TweenInfo.new(duration or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = value})
		tween:Play()
	end
	button.MouseEnter:Connect(function()
		hovered = true
		go(1.025)
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		go(1)
	end)
	button.MouseButton1Down:Connect(function()
		go(0.965, 0.07)
	end)
	button.MouseButton1Up:Connect(function()
		go(hovered and 1.025 or 1, 0.09)
	end)
end


--============================================================
-- PESTAÑAS SOLO TEXTO
-- Quita por completo las imágenes/bordes viejos de los botones originales.
-- El Name del botón NO cambia, por lo que la lógica sigue funcionando.
--============================================================
local function getTabText(button)
	return SPANISH[button.Name] or button.Name
end

local function getOrCreateTabLabel(button)
	local label = button:FindFirstChild("TextoPestana")
	if not label then
		label = Instance.new("TextLabel")
		label.Name = "TextoPestana"
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.new(1, -6, 1, -2)
		label.BorderSizePixel = 0
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = THEME.White
		label.TextStrokeTransparency = 1
		label.TextScaled = true
		label.TextWrapped = false
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.ZIndex = button.ZIndex + 20
		label.Parent = button

		local constraint = Instance.new("UITextSizeConstraint")
		constraint.Name = "LimiteTexto"
		constraint.MinTextSize = 10
		constraint.MaxTextSize = 16
		constraint.Parent = label
	end
	label.Text = getTabText(button)
	return label
end

local function eraseOldTabVisuals(button)
	button.BorderSizePixel = 0
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false

	if button:IsA("ImageButton") then
		button.ImageTransparency = 1
	elseif button:IsA("TextButton") then
		button.TextTransparency = 1
		button.TextStrokeTransparency = 1
	end

	local tabLabel = button:FindFirstChild("TextoPestana")
	for _, child in ipairs(button:GetDescendants()) do
		if child.Name ~= "TextoPestana" and child.Parent ~= tabLabel then
			if child:IsA("UIStroke") then
				child.Enabled = false
			elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
				child.BackgroundTransparency = 1
				child.ImageTransparency = 1
			elseif child:IsA("Frame") then
				child.BackgroundTransparency = 1
			elseif child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
				child.BackgroundTransparency = 1
				child.TextTransparency = 1
				child.TextStrokeTransparency = 1
			end
		end
	end
end

local function styleTabButton(button, selected)
	if not button or not button:IsA("GuiButton") then
		return
	end

	-- Conservamos Name para la lógica, pero reemplazamos por completo el look viejo.
	eraseOldTabVisuals(button)
	button.BackgroundTransparency = 0
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.ClipsDescendants = false
	ensureCorner(button, 9)

	local isMainTab = button.Parent == categoryTabsFrame
	local label = getOrCreateTabLabel(button)
	label.TextTransparency = 0
	label.TextStrokeTransparency = 1
	label.TextScaled = false
	label.TextWrapped = true
	label.TextTruncate = Enum.TextTruncate.None
	label.TextSize = isMainTab and 16 or 14
	label.Size = UDim2.new(1, -14, 1, -8)

	local limit = label:FindFirstChild("LimiteTexto")
	if limit then
		limit.MinTextSize = isMainTab and 13 or 12
		limit.MaxTextSize = isMainTab and 17 or 15
	end

	button:SetAttribute("AvatarTabSelected", selected == true)
	if selected then
		button.BackgroundColor3 = isMainTab and THEME.TabSelectedMain or THEME.TabSelectedSub
		label.TextColor3 = THEME.White
	else
		button.BackgroundColor3 = THEME.TabNormal
		label.TextColor3 = THEME.BrownDeep
	end

	local stroke = ensureStroke(button, THEME.Outline, selected and 2.4 or 2.0, 0, "TabStroke")
	if stroke then
		stroke.Enabled = true
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end

	-- Sin sombras que sobresalgan: el estilo cartoon lo da el borde café grueso.
	local oldShadow = button:FindFirstChild("CartoonShadow")
	if oldShadow then
		oldShadow:Destroy()
	end

	-- El texto siempre por encima.
	label.ZIndex = button.ZIndex + 5

	-- No crecemos al hacer hover: crecer era una de las causas de amontonamiento.
	-- Solo hacemos un pequeño "press" hacia adentro al hacer click.
	if not button:GetAttribute("CartoonTabAnimV10") then
		button:SetAttribute("CartoonTabAnimV10", true)
		local scale = button:FindFirstChild("CartoonPressScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Name = "CartoonPressScale"
			scale.Scale = 1
			scale.Parent = button
		end

		button.MouseEnter:Connect(function()
			if button.BackgroundColor3 == THEME.TabNormal then
				TweenService:Create(
					button,
					TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{BackgroundColor3 = THEME.TabHover}
				):Play()
			end
		end)

		button.MouseLeave:Connect(function()
			local isSelectedNow = button:GetAttribute("AvatarTabSelected") == true

			TweenService:Create(
				button,
				TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{BackgroundColor3 =
					isSelectedNow
					and ((button.Parent == categoryTabsFrame) and THEME.TabSelectedMain or THEME.TabSelectedSub)
					or THEME.TabNormal}
			):Play()
		end)

		button.MouseButton1Down:Connect(function()
			TweenService:Create(
				scale,
				TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Scale = 0.965}
			):Play()
		end)

		button.MouseButton1Up:Connect(function()
			TweenService:Create(
				scale,
				TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{Scale = 1}
			):Play()
		end)
	end

	local oldScale = button:FindFirstChild("AvatarMenuScale")
	if oldScale then
		oldScale.Scale = 1
	end
end


local function styleStandardButton(button, backgroundColor)
	if not button or not button:IsA("GuiButton") then
		return
	end
	button.BackgroundColor3 = backgroundColor or THEME.BrownDark
	button.BackgroundTransparency = 0
	button.BorderSizePixel = 0
	removeDecorativeBorders(button)
	ensureCorner(button, 7)
	ensureStroke(button, THEME.Cream, 1, 0.38)
	styleTextObject(button)
	setSpanishLabel(button)
	addMenuButtonAnimation(button)
end

local function getOrCreateItemNameLabel(guiButton)
	local label = guiButton:FindFirstChild("NombreArticulo")
	if not label then
		label = Instance.new("TextLabel")
		label.Name = "NombreArticulo"
		label.AnchorPoint = Vector2.new(0, 1)
		label.Position = UDim2.new(0, 7, 1, -5)
		label.Size = UDim2.new(1, -14, 0, 24)
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = THEME.BrownDeep
		label.TextSize = 12
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.ZIndex = guiButton.ZIndex + 6
		label.Parent = guiButton
		ensureCorner(label, 6)
	end
	return label
end

local function styleCatalogItem(guiButton, displayName)
	if not guiButton or not guiButton:IsA("GuiButton") then
		return
	end

	-- Tarjeta crema/blanca como las interfaces de las tiendas del juego.
	guiButton.BackgroundColor3 = THEME.ItemCard
	guiButton.BackgroundTransparency = 0
	guiButton.BorderSizePixel = 0
	if guiButton:IsA("ImageButton") then
		-- El template viejo usa una imagen como marco. La ocultamos.
		guiButton.ImageTransparency = 1
	end
	guiButton.ClipsDescendants = true
	removeDecorativeBorders(guiButton)
	ensureCorner(guiButton, 9)
	ensureStroke(guiButton, THEME.BrownDark, 1.4, 0.28, "CatalogCardStroke")
	addMenuButtonAnimation(guiButton)

	local icon = guiButton:FindFirstChild("Icon", true)

	-- Limpia fondos negros/grises y adornos de esquina del template viejo.
	for _, descendant in ipairs(guiButton:GetDescendants()) do
		local n = string.lower(descendant.Name)
		local isDetails = descendant:IsA("GuiButton") and (string.find(n, "detail") or string.find(n, "more"))

		if descendant:IsA("Frame") then
			descendant.BackgroundTransparency = 1
			descendant.BorderSizePixel = 0
		elseif descendant:IsA("TextLabel") and descendant.Name ~= "NombreArticulo" then
			-- Oculta textos viejos del template para que no se encimen.
			descendant.BackgroundTransparency = 1
			descendant.TextTransparency = 1
		elseif (descendant:IsA("ImageLabel") or descendant:IsA("ImageButton")) and descendant ~= icon and not isDetails then
			-- Quita marcos/esquinas/selecciones viejas.
			descendant.BackgroundTransparency = 1
			descendant.ImageTransparency = 1
		elseif descendant:IsA("UIStroke") and descendant.Name ~= "CatalogCardStroke" then
			descendant.Enabled = false
		end
	end

	if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
		icon.Visible = true
		icon.BackgroundTransparency = 1
		icon.ImageTransparency = 0
		icon.ScaleType = Enum.ScaleType.Fit
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 7)
		icon.Size = UDim2.new(1, -18, 1, -38)
		icon.ZIndex = guiButton.ZIndex + 3
	end

	local label = getOrCreateItemNameLabel(guiButton)
	label.BackgroundTransparency = 1
	label.TextColor3 = THEME.BrownDeep
	label.Text = tostring(displayName or guiButton.Name or "Artículo")
	label.ZIndex = guiButton.ZIndex + 8

	-- Botón de detalles: conserva la lógica, pero sin cuadro oscuro.
	for _, descendant in ipairs(guiButton:GetDescendants()) do
		if descendant:IsA("GuiButton") and descendant ~= guiButton then
			local n = string.lower(descendant.Name)
			if string.find(n, "detail") or string.find(n, "more") then
				descendant.BackgroundTransparency = 1
				descendant.BorderSizePixel = 0
				if descendant:IsA("ImageButton") then
					descendant.ImageColor3 = THEME.BrownDeep
				end
			end
		end
	end
end

local function setCardSelectedStyle(buttonClass, selected)
	if not buttonClass or not buttonClass.guiButton then
		return
	end
	removeDecorativeBorders(buttonClass.guiButton)
	local stroke = buttonClass.guiButton:FindFirstChild("CatalogCardStroke")
	if stroke and stroke:IsA("UIStroke") then
		if selected then
			stroke.Color = THEME.Green
			stroke.Thickness = 2.5
			stroke.Transparency = 0
		else
			stroke.Color = THEME.BrownDark
			stroke.Thickness = 1.4
			stroke.Transparency = 0.28
		end
	end
end

local function updateCatalogGrid()
	local width = scrollingFrame.AbsoluteSize.X
	if width <= 0 then
		return
	end
	local columns
	if width >= 980 then
		columns = 5
	elseif width >= 760 then
		columns = 4
	elseif width >= 520 then
		columns = 3
	else
		columns = 2
	end
	local gap = 10
	local cellWidth = math.floor((width - gap * (columns - 1) - 6) / columns)
	local cellHeight = math.clamp(math.floor(cellWidth * 0.88), 132, 190)
	scrollingFrameUIGridLayout.CellPadding = UDim2.fromOffset(gap, gap)
	scrollingFrameUIGridLayout.CellSize = UDim2.fromOffset(cellWidth, cellHeight)
end


--============================================================
-- V9 - HEADER RESPONSIVE REALMENTE SEPARADO
-- Posiciona cada pestaña manualmente. Esto evita que UIGridLayout/UIs
-- viejos del template muevan botones y los monten sobre el buscador.
--============================================================
local function destroyAllLayouts(holder)
	if not holder then
		return
	end
	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("UIGridLayout")
			or child:IsA("UIListLayout")
			or child:IsA("UITableLayout")
			or child:IsA("UIPageLayout") then
			child:Destroy()
		end
	end
end

local function visibleGuiButtons(holder)
	local result = {}
	if not holder then
		return result
	end

	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("GuiButton") and child.Visible then
			table.insert(result, child)
		end
	end

	table.sort(result, function(a, b)
		if a.LayoutOrder == b.LayoutOrder then
			return a.Name < b.Name
		end
		return a.LayoutOrder < b.LayoutOrder
	end)

	return result
end

local function getTabLayoutSettings(width, isMain)
	local camera = workspace.CurrentCamera
	if camera and camera.ViewportSize.Y < 600 then
		return math.max(3, math.floor(width / 90)), 36, 4
	end
	-- V10: botones grandes y legibles, especialmente en celular.
	if isMain then
		if width < 430 then
			return 2, 46, 9
		elseif width < 560 then
			return 3, 44, 9
		elseif width < 840 then
			return 4, 43, 9
		else
			return 5, 42, 10
		end
	else
		if width < 430 then
			return 2, 44, 9
		elseif width < 560 then
			return 3, 42, 9
		elseif width < 840 then
			return 4, 40, 9
		else
			return 5, 39, 10
		end
	end
end

local function layoutTabHolder(holder, width, isMain)
	if not holder then
		return 0
	end

	destroyAllLayouts(holder)

	local buttons = visibleGuiButtons(holder)
	local count = #buttons
	if count == 0 then
		holder.Size = UDim2.new(1, 0, 0, 0)
		return 0
	end

	local columns, cellHeight, gap = getTabLayoutSettings(width, isMain)
	columns = math.max(1, math.min(columns, count))

	local rows = math.ceil(count / columns)
	local cellWidth = math.floor((width - gap * (columns - 1)) / columns)

	for index, button in ipairs(buttons) do
		local zero = index - 1
		local column = zero % columns
		local row = math.floor(zero / columns)

		button.AnchorPoint = Vector2.new(0, 0)
		button.Position = UDim2.fromOffset(
			column * (cellWidth + gap),
			row * (cellHeight + gap)
		)
		button.Size = UDim2.fromOffset(cellWidth, cellHeight)
		button.ClipsDescendants = false
		button.Visible = true

		-- Solo recolocamos. No cambiamos el estado visual seleccionado aquí.
		local scale = button:FindFirstChild("AvatarMenuScale")
		if scale then
			scale.Scale = 1
		end
	end

	local totalHeight = rows * cellHeight + math.max(0, rows - 1) * gap
	holder.Size = UDim2.new(1, 0, 0, totalHeight)
	return totalHeight
end

local function getVisibleSubFrame()
	for _, frame in ipairs(subCategoryTabsFrame:GetChildren()) do
		if frame:IsA("GuiObject") and frame.Visible then
			return frame
		end
	end
	return nil
end

local function refreshHeaderLayout()
	local absoluteWidth = catalogFrame.AbsoluteSize.X
	if absoluteWidth <= 0 then
		return
	end

	local side = absoluteWidth < 520 and 12 or 14
	local sectionGap = absoluteWidth < 520 and 12 or 13
	local width = math.max(1, math.floor(absoluteWidth - side * 2))
	local y = 12

	destroyAllLayouts(categoryTabsFrame)
	destroyAllLayouts(subCategoryTabsFrame)

	categoryTabsFrame.AnchorPoint = Vector2.new(0, 0)
	categoryTabsFrame.Position = UDim2.fromOffset(side, y)
	categoryTabsFrame.Size = UDim2.new(1, -side * 2, 0, 0)
	categoryTabsFrame.ClipsDescendants = false
	categoryTabsFrame.BackgroundTransparency = 1

	local mainHeight = layoutTabHolder(categoryTabsFrame, width, true)
	y += mainHeight + sectionGap

	local visibleSub = getVisibleSubFrame()
	local subHeight = 0

	subCategoryTabsFrame.AnchorPoint = Vector2.new(0, 0)
	subCategoryTabsFrame.Position = UDim2.fromOffset(side, y)
	subCategoryTabsFrame.Size = UDim2.new(1, -side * 2, 0, 0)
	subCategoryTabsFrame.ClipsDescendants = false
	subCategoryTabsFrame.BackgroundTransparency = 1

	for _, frame in ipairs(subCategoryTabsFrame:GetChildren()) do
		if frame:IsA("GuiObject") then
			destroyAllLayouts(frame)
			frame.AnchorPoint = Vector2.new(0, 0)
			frame.Position = UDim2.fromOffset(0, 0)
			frame.Size = UDim2.new(1, 0, 0, 0)
			frame.BackgroundTransparency = 1
			frame.ClipsDescendants = false

			if frame == visibleSub then
				subHeight = layoutTabHolder(frame, width, false)
				frame.Size = UDim2.new(1, 0, 0, subHeight)
			end
		end
	end

	subCategoryTabsFrame.Size = UDim2.new(1, -side * 2, 0, subHeight)

	if subHeight > 0 then
		y += subHeight + sectionGap
	end

	-- El buscador ocupa su propia fila completa. Nunca comparte espacio con pestañas.
	local searchHeight = absoluteWidth < 520 and 46 or 44
	searchFrame.AnchorPoint = Vector2.new(0, 0)
	searchFrame.Position = UDim2.fromOffset(side, y)
	searchFrame.Size = UDim2.new(1, -side * 2, 0, searchHeight)
	y += searchHeight + 12

	headerFrame.AnchorPoint = Vector2.new(0, 0)
	headerFrame.Position = UDim2.fromOffset(0, 0)
	headerFrame.Size = UDim2.new(1, 0, 0, y)
	headerFrame.ClipsDescendants = false

	containerFrame.AnchorPoint = Vector2.new(0, 0)
	containerFrame.Position = UDim2.fromOffset(0, y)
	containerFrame.Size = UDim2.new(1, 0, 1, -y)

	updateCatalogGrid()
end


local function styleTheme()
	-- El editor siempre queda encima del HUD del juego.
	avatarEditorGui.DisplayOrder = 500
	avatarEditorGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	avatarEditorFrame.BackgroundTransparency = 1
	avatarEditorFrame.BorderSizePixel = 0
	catalogFrame.BackgroundColor3 = THEME.Brown
	catalogFrame.BorderSizePixel = 0
	viewerFrame.BackgroundTransparency = 1
	viewerFrame.BorderSizePixel = 0
	ensureCorner(catalogFrame, 12)
	ensureStroke(catalogFrame, THEME.Cream, 1.5, 0.15)

	headerFrame.BackgroundColor3 = THEME.BrownDark
	headerFrame.BorderSizePixel = 0
	containerFrame.BackgroundColor3 = THEME.Brown
	containerFrame.BorderSizePixel = 0
	ensureCorner(headerFrame, 10)
	ensureCorner(containerFrame, 10)

	-- V10: barra de búsqueda cartoon, clara, alineada y sin rectángulos salidos.
	searchFrame.BackgroundColor3 = THEME.SearchBackground
	searchFrame.BackgroundTransparency = 0
	searchFrame.BorderSizePixel = 0
	searchFrame.ClipsDescendants = false
	if searchFrame:IsA("ImageLabel") or searchFrame:IsA("ImageButton") then
		searchFrame.ImageTransparency = 1
	end
	ensureCorner(searchFrame, 10)
	local searchStroke = ensureStroke(searchFrame, THEME.Outline, 2.2, 0, "SearchCartoonStroke")
	if searchStroke then
		searchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end

	for _, child in ipairs(searchFrame:GetChildren()) do
		if child ~= searchTextBox and child ~= clearSearchButton then
			if child:IsA("ImageLabel") or child:IsA("ImageButton") then
				child.Visible = false
			elseif child:IsA("Frame") and child.Name ~= "SearchShadow" then
				child.Visible = false
			end
		end
	end

	local oldSearchShadow = searchFrame:FindFirstChild("SearchShadow")
	if oldSearchShadow then
		oldSearchShadow:Destroy()
	end

	searchTextBox.AnchorPoint = Vector2.new(0, 0.5)
	searchTextBox.Position = UDim2.new(0, 14, 0.5, 0)
	searchTextBox.Size = UDim2.new(1, -62, 1, -10)
	searchTextBox.BackgroundTransparency = 1
	searchTextBox.BorderSizePixel = 0
	searchTextBox.TextColor3 = THEME.SearchText
	searchTextBox.PlaceholderColor3 = THEME.SearchPlaceholder
	searchTextBox.Font = Enum.Font.FredokaOne
	searchTextBox.TextSize = 17
	searchTextBox.TextXAlignment = Enum.TextXAlignment.Left
	searchTextBox.PlaceholderText = "Buscar ropa, cabello, accesorios..."
	searchTextBox.ClearTextOnFocus = false
	searchTextBox.ZIndex = searchFrame.ZIndex + 3
	if string.lower(searchTextBox.Text) == "search" then
		searchTextBox.Text = ""
	end

	clearSearchButton.AnchorPoint = Vector2.new(0.5, 0.5)
	clearSearchButton.Position = UDim2.new(1, -21, 0.5, 0)
	clearSearchButton.Size = UDim2.fromOffset(28, 28)
	clearSearchButton.ZIndex = searchFrame.ZIndex + 4

	styleStandardButton(clearSearchButton, THEME.Red)
	local clearStroke = ensureStroke(clearSearchButton, THEME.Outline, 2, 0, "ClearCartoonStroke")
	if clearStroke then
		clearStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end

	scrollingFrame.BackgroundColor3 = THEME.Brown
	scrollingFrame.BorderSizePixel = 0
	scrollingFrame.ScrollBarImageColor3 = THEME.CreamLight
	scrollingFrame.ScrollBarThickness = 6
	scaleFrame.BackgroundColor3 = THEME.Brown
	scaleFrame.BorderSizePixel = 0

	for _, child in ipairs(categoryTabsFrame:GetChildren()) do
		if child:IsA("GuiButton") then
			styleTabButton(child, false)
		end
	end
	for _, holder in ipairs(subCategoryTabsFrame:GetChildren()) do
		if holder:IsA("GuiObject") then
			holder.BackgroundTransparency = 1
			for _, child in ipairs(holder:GetChildren()) do
				if child:IsA("GuiButton") then
					styleTabButton(child, false)
				end
			end
		end
	end

	-- V5: se cierra guardando con el mismo botón exterior de Vestirse.
	-- Ya no mostramos VER ni LISTO.
	doneButton.Visible = false
	doneButton.Active = false
	viewButton.Visible = false
	viewButton.Active = false

	-- MUY IMPORTANTE: el botón exterior conserva su imagen original.
	-- Sin borde, sin fondo; solo la animación que pidió el usuario.
	addToggleButtonAnimation(toggleButton)

	for _, descendant in ipairs(detailsOverlay:GetDescendants()) do
		styleTextObject(descendant)
		if descendant:IsA("TextButton") then
			styleStandardButton(descendant, descendant.BackgroundColor3)
		elseif descendant:IsA("Frame") and descendant.BackgroundTransparency < 1 then
			descendant.BorderSizePixel = 0
			ensureCorner(descendant, 8)
		end
	end

	translateTextTree(avatarEditorGui)
	refreshHeaderLayout()
	updateCatalogGrid()
end

--============================================================
-- V7 - PESTAÑAS NUEVAS
-- Agrega "Avatares" y ropa 3D sin que tengas que crear botones a mano.
-- Clona botones existentes para conservar el mismo layout/funcionamiento.
--============================================================
local function firstGuiButton(parent)
	if not parent then
		return nil
	end
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("GuiButton") then
			return child
		end
	end
	return nil
end

local function cloneTabButton(parent, template, internalName, order)
	if not parent or not template or parent:FindFirstChild(internalName) then
		return parent and parent:FindFirstChild(internalName) or nil
	end
	local clone = template:Clone()
	clone.Name = internalName
	clone.LayoutOrder = order or 100
	clone.Visible = true
	clone.Parent = parent
	return clone
end

local function ensureModernTabs()
	-- Apartado principal AVATARES
	if not categoryTabsFrame:FindFirstChild("Avatars") then
		local template = firstGuiButton(categoryTabsFrame)
		if template then
			cloneTabButton(categoryTabsFrame, template, "Avatars", 90)
		end
	end

	-- Apartados de ropa 3D dentro de Ropa/Clothes/Clothing.
	local clothingFrame =
		subCategoryTabsFrame:FindFirstChild("Clothes")
		or subCategoryTabsFrame:FindFirstChild("Clothing")

	if clothingFrame then
		local template = firstGuiButton(clothingFrame)
		if template then
			local modern = {
				{"TShirt", 55},
				{"TShirtAccessory", 60},
				{"ShirtAccessory", 61},
				{"PantsAccessory", 62},
				{"JacketAccessory", 63},
				{"SweaterAccessory", 64},
				{"ShortsAccessory", 65},
				{"DressSkirtAccessory", 66},
				{"LeftShoeAccessory", 67},
				{"RightShoeAccessory", 68},
			}
			for _, info in ipairs(modern) do
				cloneTabButton(clothingFrame, template, info[1], info[2])
			end
		end
	end

	-- Cejas y pestañas modernas dentro de Accesorios.
	local accessoriesFrame = subCategoryTabsFrame:FindFirstChild("Accessories")
	if accessoriesFrame then
		local template = firstGuiButton(accessoriesFrame)
		if template then
			cloneTabButton(accessoriesFrame, template, "EyebrowAccessory", 90)
			cloneTabButton(accessoriesFrame, template, "EyelashAccessory", 91)
		end
	end

	-- Expresiones/Mood dentro de Animaciones.
	local animationsFrame = subCategoryTabsFrame:FindFirstChild("Animations")
	if animationsFrame then
		local template = firstGuiButton(animationsFrame)
		if template then
			cloneTabButton(animationsFrame, template, "Mood", 90)
		end
	end
end

ensureModernTabs()

styleTheme()

local purchasePrompt = PurchasePrompt.new(detailsOverlay)

local activeButtons = Maid.new()
local activeConnections = Maid.new()
local activeCategoryButtons = {}
local activeSubCategoryButtons = {}

local numberValue = Instance.new("NumberValue")
numberValue.Value = CAMERA_OFFSET

local categoryButtons = TableUtil.Filter(categoryTabsFrame:GetChildren(), function(item)
	return item:IsA("GuiButton")
end)
local subCategoryFrames = TableUtil.Filter(subCategoryTabsFrame:GetChildren(), function(item)
	return item:IsA("GuiObject")
end)

local catalogFrameOpenTween = TweenService:Create(catalogFrame, tweenInfo, {Position = UDim2.new(0, 0, 0, 0)})
local catalogFrameCloseTween = TweenService:Create(catalogFrame, tweenInfo, {Position = UDim2.new(-0.6, 0, 0, 0)})
local viewerFrameOpenTween = TweenService:Create(viewerFrame, tweenInfo, {Position = UDim2.new(1, 0, 0, 0)})
local viewerFrameCloseTween = TweenService:Create(viewerFrame, tweenInfo, {Position = UDim2.new(1.4, 0, 0, 0)})
local viewFramePartialOpenTween = TweenService:Create(viewerFrame, tweenInfo, {Position = UDim2.new(1.4, -36, 0, 0)})
local fullViewCloseTween = TweenService:Create(numberValue, tweenInfo, {Value = CAMERA_OFFSET})
local fullViewOpenTween = TweenService:Create(numberValue, tweenInfo, {Value = 0.5})

local currentCategory = "Accessories"
local currentSubCategory = "Hair"

local isOpen = false
local fullView = false

--============================================================
-- V15 - SIN GUARDIA PERMANENTE DE LocalTransparencyModifier
--
-- No hacemos barridos por frame. Roblox queda libre de ocultar la geometría
-- corporal que debe quedar debajo de layered clothing.
--============================================================
local function attachTransparencyWatcher(_targetCharacter)
	-- Intencionalmente vacío.
end

-- see link for what the dictionary looks like: https://developer.roblox.com/en-us/api-reference/function/Players/GetCharacterAppearanceInfoAsync
local wearingAssets

-- Estado del catálogo en vivo.
local liveCatalogMode = false
local liveCatalogRequest = nil
local liveSearchSerial = 0
local liveSearchHandler = nil

-- V10: protección contra spam/HTTP 429.
local suppressSearchSignal = false
local searchDebounceToken = 0
local lastCatalogRequestAt = 0
local catalogRequestBusy = false
local catalogCooldownUntil = 0
local CATALOG_MIN_REQUEST_GAP = 0.85
local CATALOG_429_RETRIES = 3
local SEARCH_DEBOUNCE = 0.80

-- Cache por categoría + búsqueda. Al volver a una pestaña no vuelve a pedir lo mismo.
local liveCatalogCache = {}
local currentLiveCacheKey = nil
local currentLiveCache = nil

-- Muchas páginas, pero cargadas poco a poco para no congelar celular.
local liveCatalogPages = nil
local liveCatalogSeen = {}
local liveCatalogCount = 0
local liveCatalogLoading = false
local LIVE_PAGE_SIZE = 30
local LIVE_INITIAL_PAGES = 1       -- 30 objetos de entrada; el resto llega al bajar
local LIVE_MAX_ITEMS = 300         -- hasta 300 por apartado/búsqueda
local LIVE_PREFETCH_DISTANCE = 420

local originalCamCFrame = camera.CFrame

local function characterAdded(newCharacter)
	character = newCharacter or player.Character
	if not character then
		return
	end

	rootPart = character.PrimaryPart or character:WaitForChild("HumanoidRootPart")
	humanoid = character:FindFirstChildWhichIsA("Humanoid") or character:WaitForChild("Humanoid")
	camera = getCurrentCamera()

	-- V20:
	-- V14 del servidor crea un Character COMPLETAMENTE NUEVO al cambiar
	-- bundles/cuerpo. Si Vestirse sigue abierto, mantenemos el editor dueño
	-- de la cámara y de los controles mientras CharacterAdded actualiza refs.
	if isOpen then
		player:SetAttribute("AvatarEditorOpen", true)
		controlModule:Disable()
		avatarEditorFrame.Visible = true
		camera.CameraSubject = humanoid
		camera.CameraType = Enum.CameraType.Scriptable
	else
		originalCamCFrame = camera.CFrame
	end

	-- No tocar LocalTransparencyModifier del cuerpo.
	forceTransparencyRecovery(character)
end

local function hideAllSubCategoryFrames()
	for i, frame in ipairs(subCategoryFrames) do
		frame.Visible = false
	end
end

local function setSelectedCategory(guiButton)
	for button, class in next, activeCategoryButtons do
		class:SetSelected(false)
		styleTabButton(button, false)
	end
	if activeCategoryButtons[guiButton] then
		activeCategoryButtons[guiButton]:SetSelected(true)
		styleTabButton(guiButton, true)
	end
end

local function setSelectedSubCategory(guiButton)
	for button, class in next, activeSubCategoryButtons do
		class:SetSelected(false)
		styleTabButton(button, false)
	end
	if activeSubCategoryButtons[guiButton] then
		activeSubCategoryButtons[guiButton]:SetSelected(true)
		styleTabButton(guiButton, true)
	end
end

local function updateScrollingFrameCanvasSize()
	scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, scrollingFrameUIGridLayout.AbsoluteContentSize.Y)
end

local function updateScaleFrameCanvasSize()
	scaleFrame.CanvasSize = UDim2.new(0, 0, 0, scaleFrameUIGridLayout.AbsoluteContentSize.Y)
end

local function setSearchTextSilently(value)
	suppressSearchSignal = true
	searchTextBox.Text = tostring(value or "")
	suppressSearchSignal = false
end

local function clearSearch()
	setSearchTextSilently("")
end

local function resetScrollingFrame(keepSearchText)
	activeButtons:DoCleaning()
	local oldStatus = scrollingFrame:FindFirstChild("CatalogStatusMessage")
	if oldStatus then
		oldStatus:Destroy()
	end
	if not keepSearchText then
		clearSearch()
	end
	scrollingFrame.CanvasPosition = Vector2.new(0, 0)
end

-- https://github.com/forrestthewoods/lib_fts/blob/master/code/fts_fuzzy_match.js
function stringMatch(pattern, str)
	local patternIndex = 1
	local patternLength = #pattern
	local strIndex = 1
	local strLength = #str

	while patternIndex <= patternLength and strIndex <= strLength do
		local patternChar = pattern:sub(patternIndex, patternIndex):lower()
		local strChar = str:sub(strIndex, strIndex):lower()

		if patternChar == strChar then
			patternIndex = patternIndex + 1
		end

		strIndex = strIndex + 1
	end

	return patternLength > 0 and strLength > 0 and (patternIndex - 1) == patternLength
end

-- should probably search after a delay
local function search()
	if suppressSearchSignal then
		return
	end

	local text = searchTextBox.Text

	-- En catálogo en vivo esperamos a que el jugador termine de escribir.
	-- Esto elimina las peticiones por cada tecla y reduce muchísimo los 429.
	if liveCatalogMode and liveSearchHandler then
		searchDebounceToken += 1
		local token = searchDebounceToken
		task.delay(SEARCH_DEBOUNCE, function()
			if token ~= searchDebounceToken then
				return
			end
			liveSearchHandler(text)
		end)
		return
	end

	-- Fallback local: filtra sin consultar internet.
	for _, button in next, activeButtons._tasks do
		if text == "" then
			button.guiButton.Visible = true
		else
			local match = stringMatch(text, button.guiButton.Name)
			button.guiButton.Visible = match
		end
	end
	scrollingFrame.CanvasPosition = Vector2.new(0, 0)
	updateScrollingFrameCanvasSize()
end


local function isWearing(id)
	for i, asset in ipairs(wearingAssets.assets) do
		if asset.id == id then
			return true
		end
	end
	return false
end

-- probably not a good idea but whatever
local function updateSelected()
	for _, button in next, activeButtons._tasks do
		local selected = isWearing(button.AssetId)
		button:SetSelected(selected)
		setCardSelectedStyle(button, selected)
	end
end

-- rbxthumb://type=Asset&id=00000000&w=420&h=420 -- use 150x150 for less memory
local function makeButton(v)
	local button; button = Button.new({
		Name = v.Name,
		Icon = "rbxthumb://type=Asset&id=" .. v.Id .. "&w=150&h=150",
		AssetId = v.Id,
		ActivatedCallback = function(inputObject)
			remoteEvent:FireServer("wear", v.Id)
		end,
		DetailsCallback = function(inputObject)
			purchasePrompt:Prompt(v.Id)
		end,
	})
	local selected = isWearing(v.Id)
	button:SetSelected(selected)
	button:Parent(scrollingFrame)
	styleCatalogItem(button.guiButton, v.Name)
	setCardSelectedStyle(button, selected)
	return button
end


--============================================================
-- CATÁLOGO ROBLOX EN VIVO
-- Usa AvatarEditorService:SearchCatalogAsync(), por lo que los objetos
-- no quedan congelados en el ModuleScript Catalog.
--============================================================
local LIVE_ASSET_TYPES = {
	Hair = {Enum.AvatarAssetType.HairAccessory},
	Hat = {Enum.AvatarAssetType.Hat},
	Hats = {Enum.AvatarAssetType.Hat},
	Faces = {Enum.AvatarAssetType.FaceAccessory},
	FaceAccessory = {Enum.AvatarAssetType.FaceAccessory},
	Neck = {Enum.AvatarAssetType.NeckAccessory},
	NeckAccessory = {Enum.AvatarAssetType.NeckAccessory},
	Shoulder = {Enum.AvatarAssetType.ShoulderAccessory},
	ShoulderAccessory = {Enum.AvatarAssetType.ShoulderAccessory},
	Front = {Enum.AvatarAssetType.FrontAccessory},
	FrontAccessory = {Enum.AvatarAssetType.FrontAccessory},
	Back = {Enum.AvatarAssetType.BackAccessory},
	BackAccessory = {Enum.AvatarAssetType.BackAccessory},
	Waist = {Enum.AvatarAssetType.WaistAccessory},
	WaistAccessory = {Enum.AvatarAssetType.WaistAccessory},

	TShirt = {Enum.AvatarAssetType.TShirt},
	Shirt = {Enum.AvatarAssetType.Shirt},
	Pants = {Enum.AvatarAssetType.Pants},
	TShirtAccessory = {Enum.AvatarAssetType.TShirtAccessory},
	ShirtAccessory = {Enum.AvatarAssetType.ShirtAccessory},
	PantsAccessory = {Enum.AvatarAssetType.PantsAccessory},
	JacketAccessory = {Enum.AvatarAssetType.JacketAccessory},
	SweaterAccessory = {Enum.AvatarAssetType.SweaterAccessory},
	ShortsAccessory = {Enum.AvatarAssetType.ShortsAccessory},
	DressSkirtAccessory = {Enum.AvatarAssetType.DressSkirtAccessory},
	LeftShoeAccessory = {Enum.AvatarAssetType.LeftShoeAccessory},
	RightShoeAccessory = {Enum.AvatarAssetType.RightShoeAccessory},
	EyebrowAccessory = {Enum.AvatarAssetType.EyebrowAccessory},
	EyelashAccessory = {Enum.AvatarAssetType.EyelashAccessory},

	Head = {Enum.AvatarAssetType.Head, Enum.AvatarAssetType.DynamicHead},
	Torso = {Enum.AvatarAssetType.Torso},
	LeftArm = {Enum.AvatarAssetType.LeftArm},
	RightArm = {Enum.AvatarAssetType.RightArm},
	LeftLeg = {Enum.AvatarAssetType.LeftLeg},
	RightLeg = {Enum.AvatarAssetType.RightLeg},

	Climb = {Enum.AvatarAssetType.ClimbAnimation},
	Fall = {Enum.AvatarAssetType.FallAnimation},
	Idle = {Enum.AvatarAssetType.IdleAnimation},
	Jump = {Enum.AvatarAssetType.JumpAnimation},
	Run = {Enum.AvatarAssetType.RunAnimation},
	Swim = {Enum.AvatarAssetType.SwimAnimation},
	Walk = {Enum.AvatarAssetType.WalkAnimation},
	Mood = {Enum.AvatarAssetType.MoodAnimation},
}

-- V9: Torso/brazos/piernas normalmente forman parte de bundles de cuerpo.
-- Buscar solo AssetType.Torso con IncludeOffSale=false puede devolver 0.
-- Para estas pestañas buscamos bundles BodyParts y extraemos únicamente
-- la pieza correspondiente del bundle.
local BODY_PART_BUNDLE_TARGET = {
	Torso = "Torso",
	LeftArm = "LeftArm",
	RightArm = "RightArm",
	LeftLeg = "LeftLeg",
	RightLeg = "RightLeg",
}

local function getBundledBodyPart(bundleItem, targetAssetType)
	if type(bundleItem) ~= "table" or type(bundleItem.BundledItems) ~= "table" then
		return nil
	end

	for _, bundled in ipairs(bundleItem.BundledItems) do
		local bundledType = tostring(bundled.AssetType or "")
		if bundledType == targetAssetType then
			local id = tonumber(bundled.Id)
			if id then
				return {
					Id = id,
					Name = tostring(bundleItem.Name or "Cuerpo") .. " - " .. (SPANISH[targetAssetType] or targetAssetType),
					ItemType = "Asset",
					AssetType = targetAssetType,
				}
			end
		end
	end

	return nil
end


local function enumListKey(list)
	if not list then
		return "-"
	end
	local parts = {}
	for _, value in ipairs(list) do
		table.insert(parts, tostring(value))
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

local function makeLiveCacheKey(request, keyword)
	local pieces = {
		"a=" .. enumListKey(request.assetTypes),
		"b=" .. enumListKey(request.bundleTypes),
		"body=" .. tostring(request.extractBodyPart or ""),
		"filter=" .. tostring(request.filterAssetType or ""),
		"off=" .. tostring(request.includeOffSale == true),
		"sort=" .. tostring(request.sortType or Enum.CatalogSortType.Relevance),
		"q=" .. string.lower(tostring(keyword or "")),
	}
	return table.concat(pieces, "|")
end

local function copyDictionary(source)
	local result = {}
	for k, v in pairs(source or {}) do
		result[k] = v
	end
	return result
end

local function itemMatchesRequestedAssetType(item, requestedType)
	if not requestedType or requestedType == "" then
		return true
	end

	local assetType = tostring(item.AssetType or "")
	if assetType == requestedType or string.find(assetType, requestedType, 1, true) then
		return true
	end

	local mapped = LIVE_ASSET_TYPES[requestedType]
	local enumItem = mapped and mapped[1]
	if enumItem and tonumber(item.AssetType) == enumItem.Value then
		return true
	end

	return false
end

local function normalizeLiveItem(rawItem, request)
	if not rawItem then
		return nil
	end

	local item = rawItem
	if request and request.extractBodyPart then
		item = getBundledBodyPart(rawItem, request.extractBodyPart)
	end
	if not item then
		return nil
	end

	if request and request.filterAssetType and not itemMatchesRequestedAssetType(item, request.filterAssetType) then
		return nil
	end

	return item
end

local function waitForCatalogRequestSlot(serial)
	while catalogRequestBusy do
		if serial ~= liveSearchSerial then
			return false
		end
		task.wait(0.05)
	end

	local now = os.clock()
	local waitFor = math.max(
		0,
		CATALOG_MIN_REQUEST_GAP - (now - lastCatalogRequestAt),
		catalogCooldownUntil - now
	)
	if waitFor > 0 then
		task.wait(waitFor)
	end

	if serial ~= liveSearchSerial then
		return false
	end
	return true
end

local function is429Error(err)
	return string.find(string.lower(tostring(err)), "429", 1, true) ~= nil
		or string.find(string.lower(tostring(err)), "too many requests", 1, true) ~= nil
end

local function searchCatalogWithBackoff(params, serial)
	for attempt = 1, CATALOG_429_RETRIES do
		if not waitForCatalogRequestSlot(serial) then
			return false, "cancelled"
		end

		catalogRequestBusy = true
		lastCatalogRequestAt = os.clock()
		local ok, result = pcall(function()
			return AvatarEditorService:SearchCatalogAsync(params)
		end)
		catalogRequestBusy = false

		if serial ~= liveSearchSerial then
			return false, "cancelled"
		end

		if ok then
			return true, result
		end

		if not is429Error(result) then
			return false, result
		end

		local delayTime = 1.25 * (2 ^ (attempt - 1))
		catalogCooldownUntil = math.max(catalogCooldownUntil, os.clock() + delayTime)
		warn(string.format(
			"[AvatarEditor] Roblox limitó temporalmente el catálogo (429). Reintento %d/%d en %.2fs.",
			attempt,
			CATALOG_429_RETRIES,
			delayTime
			))
		task.wait(delayTime)
	end

	return false, "HTTP 429 (Too Many Requests)"
end

local function advanceCatalogPageWithBackoff(pages, serial)
	for attempt = 1, 3 do
		if not waitForCatalogRequestSlot(serial) then
			return false, "cancelled"
		end

		catalogRequestBusy = true
		lastCatalogRequestAt = os.clock()
		local ok, err = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		catalogRequestBusy = false

		if serial ~= liveSearchSerial then
			return false, "cancelled"
		end

		if ok then
			return true
		end

		if not is429Error(err) then
			return false, err
		end

		local delayTime = 1.25 * (2 ^ (attempt - 1))
		catalogCooldownUntil = math.max(catalogCooldownUntil, os.clock() + delayTime)
		task.wait(delayTime)
	end

	return false, "HTTP 429 (Too Many Requests)"
end

local function showCatalogMessage(message)
	resetScrollingFrame(true)

	local card = Instance.new("TextLabel")
	card.Name = "CatalogStatusMessage"
	card.BackgroundColor3 = THEME.CreamLight
	card.BackgroundTransparency = 0
	card.BorderSizePixel = 0
	card.TextColor3 = THEME.BrownDeep
	card.Font = Enum.Font.FredokaOne
	card.TextSize = 17
	card.TextWrapped = true
	card.Text = tostring(message)
	card.Size = UDim2.new(1, -24, 0, 78)
	card.ZIndex = scrollingFrame.ZIndex + 5
	card.Parent = scrollingFrame
	ensureCorner(card, 10)
	ensureStroke(card, THEME.Outline, 2, 0, "StatusStroke")
end

local function addLiveButton(item)
	local id = tonumber(item.Id)
	if not id then
		return
	end

	local name = tostring(item.Name or ("Artículo " .. id))
	local itemType = tostring(item.ItemType or "Asset")
	local isBundle = itemType == "Bundle" or item.BundleType ~= nil

	local icon
	if isBundle then
		icon = "rbxthumb://type=BundleThumbnail&id=" .. id .. "&w=420&h=420"
	else
		icon = "rbxthumb://type=Asset&id=" .. id .. "&w=420&h=420"
	end

	local button = Button.new({
		Name = name,
		Icon = icon,
		AssetId = id,
		ActivatedCallback = function()
			if isBundle then
				remoteEvent:FireServer("wearBundle", id)
			else
				remoteEvent:FireServer("wear", id)
			end
		end,
		DetailsCallback = function()
			-- El PurchasePrompt viejo trabaja con assets, no con bundles.
			if not isBundle then
				purchasePrompt:Prompt(id)
			end
		end,
	})

	local selected = (not isBundle) and isWearing(id) or false
	button:SetSelected(selected)
	button:Parent(scrollingFrame)
	styleCatalogItem(button.guiButton, name)
	setCardSelectedStyle(button, selected)

	local key = "live_" .. tostring(id) .. "_" .. tostring(#activeButtons._tasks + 1)
	activeButtons[key] = button
end

local function appendLiveCurrentPage(pages, serial)
	if not pages or serial ~= liveSearchSerial then
		return 0
	end

	local added = 0
	for _, rawItem in ipairs(pages:GetCurrentPage()) do
		if serial ~= liveSearchSerial or liveCatalogCount >= LIVE_MAX_ITEMS then
			break
		end

		local item = normalizeLiveItem(rawItem, liveCatalogRequest)
		if item then
			local id = tonumber(item.Id)
			local itemType = tostring(item.ItemType or "Asset")
			local key = itemType .. ":" .. tostring(id or item.Name)
			if not liveCatalogSeen[key] then
				liveCatalogSeen[key] = true
				addLiveButton(item)
				liveCatalogCount += 1
				added += 1

				if currentLiveCache then
					currentLiveCache.seen[key] = true
					table.insert(currentLiveCache.items, item)
					currentLiveCache.pages = pages
				end
			end
		end
	end

	updateScrollingFrameCanvasSize()
	return added
end


local function advanceAndAppendLivePage(serial)
	if liveCatalogLoading or not liveCatalogPages then
		return false
	end
	if serial ~= liveSearchSerial or liveCatalogCount >= LIVE_MAX_ITEMS then
		return false
	end
	if liveCatalogPages.IsFinished then
		return false
	end

	liveCatalogLoading = true
	local ok, err = advanceCatalogPageWithBackoff(liveCatalogPages, serial)
	liveCatalogLoading = false

	if not ok then
		if err ~= "cancelled" then
			warn("[AvatarEditor V10] No se pudo cargar la siguiente página:", err)
		end
		return false
	end
	if serial ~= liveSearchSerial then
		return false
	end

	if currentLiveCache then
		currentLiveCache.pages = liveCatalogPages
	end
	appendLiveCurrentPage(liveCatalogPages, serial)
	return true
end


local function loadMoreLiveCatalog()
	if not liveCatalogMode or not liveCatalogPages or liveCatalogLoading then
		return
	end
	if liveCatalogCount >= LIVE_MAX_ITEMS or liveCatalogPages.IsFinished then
		return
	end

	local serial = liveSearchSerial
	task.spawn(function()
		advanceAndAppendLivePage(serial)
	end)
end

local function runLiveCatalogSearch(request, keyword)
	if not request then
		return false
	end

	liveCatalogMode = true
	liveCatalogRequest = request
	liveSearchSerial += 1
	local mySerial = liveSearchSerial
	local normalizedKeyword = tostring(keyword or "")
	local cacheKey = makeLiveCacheKey(request, normalizedKeyword)

	currentLiveCacheKey = cacheKey

	-- Si ya visitamos esta categoría/búsqueda, la mostramos sin otra petición HTTP.
	local cached = liveCatalogCache[cacheKey]
	if cached and cached.items and #cached.items > 0 then
		resetScrollingFrame(true)
		liveCatalogPages = cached.pages
		liveCatalogSeen = copyDictionary(cached.seen)
		liveCatalogCount = #cached.items
		liveCatalogLoading = false
		currentLiveCache = cached

		for _, item in ipairs(cached.items) do
			addLiveButton(item)
		end

		updateScrollingFrameCanvasSize()
		return true
	end

	-- Bloquea el paginado anterior mientras llega la nueva categoría.
	liveCatalogPages = nil
	liveCatalogLoading = true
	currentLiveCache = nil

	local params = CatalogSearchParams.new()
	params.SortType = request.sortType or Enum.CatalogSortType.Relevance
	params.IncludeOffSale = request.includeOffSale == true
	params.Limit = LIVE_PAGE_SIZE
	params.SearchKeyword = normalizedKeyword

	if request.assetTypes then
		params.AssetTypes = request.assetTypes
	end
	if request.bundleTypes then
		params.BundleTypes = request.bundleTypes
	end

	local ok, pagesOrError = searchCatalogWithBackoff(params, mySerial)
	liveCatalogLoading = false

	if mySerial ~= liveSearchSerial then
		return false
	end

	if not ok then
		if pagesOrError ~= "cancelled" then
			warn("[AvatarEditor] SearchCatalogAsync falló:", pagesOrError)
		end
		return false
	end

	-- Solo limpiamos la lista DESPUÉS de recibir una respuesta válida.
	resetScrollingFrame(true)
	liveCatalogPages = pagesOrError
	liveCatalogSeen = {}
	liveCatalogCount = 0
	liveCatalogLoading = false

	local cache = {
		items = {},
		seen = {},
		pages = liveCatalogPages,
		createdAt = os.clock(),
	}
	liveCatalogCache[cacheKey] = cache
	currentLiveCache = cache

	appendLiveCurrentPage(liveCatalogPages, mySerial)

	-- Para filtros como zapatos, una página puede traer más del otro lado.
	-- Avanzamos hasta 3 páginas como máximo solo si todavía no hay suficientes.
	local desiredInitial = request.filterAssetType and 12 or 1
	local extraPages = 0
	while liveCatalogCount < desiredInitial
		and not liveCatalogPages.IsFinished
		and liveCatalogCount < LIVE_MAX_ITEMS
		and extraPages < 2 do

		extraPages += 1
		if not advanceAndAppendLivePage(mySerial) then
			break
		end
	end

	updateScrollingFrameCanvasSize()
	return true
end


liveSearchHandler = function(keyword)
	if not liveCatalogRequest then
		return
	end
	runLiveCatalogSearch(liveCatalogRequest, keyword)
end

local function loadAvatarBundles()
	currentSubCategory = nil
	searchFrame.Visible = true
	scrollingFrame.Visible = true
	scaleFrame.Visible = false
	liveCatalogMode = true

	local request = {
		bundleTypes = {
			Enum.BundleType.BodyParts,
			Enum.BundleType.DynamicHeadAvatar,
		},
		sortType = Enum.CatalogSortType.Relevance,
		includeOffSale = true,
	}
	runLiveCatalogSearch(request, searchTextBox.Text)
end

-- definetly not a good idea loading thousands of items at once; use infinite scrolling methods if possible
local function loadAccessories(category)
	currentSubCategory = category

	-- V10: partes del cuerpo salen desde bundles reales.
	local bodyPartTarget = BODY_PART_BUNDLE_TARGET[category]
	if bodyPartTarget then
		searchFrame.Visible = true
		scrollingFrame.Visible = true
		scaleFrame.Visible = false

		local success = runLiveCatalogSearch({
			bundleTypes = {Enum.BundleType.BodyParts},
			extractBodyPart = bodyPartTarget,
			includeOffSale = true,
			sortType = Enum.CatalogSortType.Relevance,
		}, searchTextBox.Text)

		if success then
			return
		end
	end

	local liveTypes = LIVE_ASSET_TYPES[category]
	if liveTypes then
		searchFrame.Visible = true
		scrollingFrame.Visible = true
		scaleFrame.Visible = false

		local request = {
			assetTypes = liveTypes,
			includeOffSale = false,
			sortType = Enum.CatalogSortType.Relevance,
		}

		-- Los zapatos son assets separados izquierda/derecha.
		-- Buscar ambos tipos juntos da muchos más resultados; luego filtramos el lado correcto.
		if category == "LeftShoeAccessory" or category == "RightShoeAccessory" then
			request.assetTypes = {
				Enum.AvatarAssetType.LeftShoeAccessory,
				Enum.AvatarAssetType.RightShoeAccessory,
			}
			request.filterAssetType = category
			request.includeOffSale = true
			request.sortType = Enum.CatalogSortType.Relevance
		end

		-- Animaciones antiguas/off-sale siguen siendo válidas para avatar y amplían el catálogo.
		if category == "Climb"
			or category == "Fall"
			or category == "Idle"
			or category == "Jump"
			or category == "Run"
			or category == "Swim"
			or category == "Walk"
			or category == "Mood" then

			request.includeOffSale = true
			request.sortType = Enum.CatalogSortType.Relevance
		end

		-- Cabezas también tienen contenido que no siempre está a la venta.
		if category == "Head" then
			request.includeOffSale = true
		end

		local success = runLiveCatalogSearch(request, searchTextBox.Text)
		if success then
			if liveCatalogCount == 0 then
				showCatalogMessage("No encontré artículos en esta categoría. Prueba otra búsqueda.")
			end
			return
		end
	end

	-- Fallback al Catalog antiguo si Marketplace falla.
	liveCatalogMode = false
	liveCatalogRequest = nil
	resetScrollingFrame(true)

	local categoryTable = Catalog[currentCategory]
	local list = categoryTable and categoryTable[category]
	if list and #list > 0 then
		for i, v in ipairs(list) do
			if v ~= nil then
				local button = makeButton(v)
				activeButtons[i] = button
			end
		end
		updateScrollingFrameCanvasSize()
		return
	end

	showCatalogMessage("Roblox está limitando temporalmente el catálogo. Espera unos segundos y vuelve a tocar esta categoría.")
end


local function loadWearing()
	currentSubCategory = nil
	liveCatalogMode = false
	liveCatalogRequest = nil
	resetScrollingFrame()
	scrollingFrame.Visible = true
	for i, asset in ipairs(wearingAssets.assets) do
		local v = {Id = asset.id, Name = asset.name}
		local button = makeButton(v)
		activeButtons[i] = button
	end
	updateScrollingFrameCanvasSize()
end

local function loadSkinTones()
	liveCatalogMode = false
	liveCatalogRequest = nil
	local list = Catalog.Appearance.SkinTone
	if list then
		for name, color in next, list do
			local button; button = Button.new({
				Name = name,
				Icon = "rbxasset://textures/whiteCircle.png",
				ActivatedCallback = function(inputObject)
					remoteEvent:FireServer("skintone", name)
				end,
			})
			button.guiButton.Icon.ImageColor3 = color
			button:Parent(scrollingFrame)
			styleCatalogItem(button.guiButton, "Tono de piel")
			activeButtons[name] = button
		end
		updateScrollingFrameCanvasSize()
	end
end

local function loadScales()
	-- uhh? i forgot what I wanted to do here.
end

local function getCameraOffsetCFrame()
	local ViewSizeX = ScreenSpace.ViewSizeX()
	local ViewSizeY = ScreenSpace.ViewSizeY()
	local offset = ScreenSpace.ScreenToWorld(numberValue.Value * ViewSizeX, ViewSizeY/2, -DEPTH)
	local cameraCFrame = rootPart.CFrame * offset
	local lookCFrame = rootPart.CFrame * Vector3.new(offset.X, offset.Y, DEPTH)
	return CFrame.new(cameraCFrame, lookCFrame)
end

local function updateCamera(delta)
	camera.CFrame = getCameraOffsetCFrame()
	-- V17: NO tocar LocalTransparencyModifier.
	-- Roblox lo necesita para ocultar el cuerpo debajo de ropa 3D.
end

-- Evita que slots, dinero, diamantes, mascota, botones, etc. se monten encima del editor.
local hiddenScreenGuis = {}
local function hideGameHud()
	table.clear(hiddenScreenGuis)
	for _, gui in ipairs(playerGui:GetChildren()) do
		if gui:IsA("ScreenGui") and gui ~= avatarEditorGui then
			hiddenScreenGuis[gui] = gui.Enabled
			if gui.Enabled then
				gui.Enabled = false
			end
		end
	end
end

local function restoreGameHud()
	for gui, wasEnabled in pairs(hiddenScreenGuis) do
		if gui and gui.Parent then
			gui.Enabled = wasEnabled
		end
	end
	table.clear(hiddenScreenGuis)
end

local function openSequence()
	-- Nunca permitimos dos sistemas de cámara al mismo tiempo.
	if player:GetAttribute("PetCareMenuOpen") == true then
		warn("[AvatarEditor] Apertura bloqueada: menú de mascota está abierto.")
		return
	end

	-- Refrescamos la referencia por si Roblox reemplazó CurrentCamera.
	camera = getCurrentCamera()

	-- Snapshot seguro SOLO de partes estáticas del mapa.
	rememberWorldTransparencyBeforeEditor()

	player:SetAttribute("AvatarEditorOpen", true)
	hideGameHud()
	controlModule:Disable()
	avatarEditorFrame.Visible = true
	catalogFrameOpenTween:Play()
	viewerFrameOpenTween:Play()

	-- Guardamos TODO el estado normal de la cámara antes del editor.
	originalCamCFrame = camera.CFrame
	originalCameraType = camera.CameraType
	originalCameraSubject = camera.CameraSubject
	originalFieldOfView = camera.FieldOfView

	-- Scriptable evita que el CameraModule pelee con el tween del armario.
	camera.CameraType = Enum.CameraType.Scriptable
	-- V17: no forzamos LocalTransparencyModifier al abrir.

	local cameraCFrame = getCameraOffsetCFrame()
	local cameraTween = TweenService:Create(camera, tweenInfo, {CFrame = cameraCFrame})
	activeConnections[CAMERA_BIND] = cameraTween.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed and isOpen then
			RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, updateCamera)
		end
	end)
	cameraTween:Play()
	isOpen = true
end

local function closeSequence()
	-- Guardado explícito al volver a presionar Vestirse.
	remoteEvent:FireServer("save")

	-- Deja de controlar la cámara INMEDIATAMENTE.
	RunService:UnbindFromRenderStep(CAMERA_BIND)

	catalogFrameCloseTween:Play()
	viewerFrameCloseTween:Play()
	avatarEditorFrame.Visible = false

	-- Mientras aún tenemos control Scriptable, restauramos únicamente
	-- las partes estáticas que Invisicam pudo dejar transparentes.
	camera = getCurrentCamera()
	camera.CameraType = Enum.CameraType.Scriptable
	restoreWorldTransparencyAfterEditor()

	-- No hacemos tween de regreso: ese tween era otra fuente de cámara trabada.
	-- Volvemos de una vez al CFrame anterior y entregamos control a CameraModule.
	isOpen = false
	restoreGameplayCamera()

	controlModule:Enable()
	restoreGameHud()

	player:SetAttribute("AvatarEditorOpen", false)

	numberValue.Value = CAMERA_OFFSET
	fullView = false
end

local function toggle()
	if not isOpen and player:GetAttribute("PetCareMenuOpen") == true then
		warn("[AvatarEditor] No puede abrirse mientras el menú de mascota está activo.")
		return
	end

	local sound = toggleButton:FindFirstChild("Open")
	if sound and sound:IsA("Sound") then
		sound:Play()
	end

	if isOpen then
		closeSequence()
	else
		openSequence()
	end
end

local function toggleView()
	if fullView then
		catalogFrameOpenTween:Play()
		viewerFrameOpenTween:Play()
		fullViewCloseTween:Play()
	else
		catalogFrameCloseTween:Play()
		viewFramePartialOpenTween:Play()
		fullViewOpenTween:Play()
	end
	fullView = not fullView
end

local function onClientEvent(characterAppearanceInfo)
	wearingAssets = characterAppearanceInfo
	updateSelected()

	if character and character.Parent then
		forceTransparencyRecovery(character)
	end
end

for i, button in ipairs(categoryButtons) do
	local function activated(inputObject)
		local subCategoryTabFrame = subCategoryTabsFrame:FindFirstChild(button.Name)
		if subCategoryTabFrame then
			hideAllSubCategoryFrames()
			currentCategory = button.Name
			setSelectedCategory(button)
			subCategoryTabFrame.Visible = true
			task.defer(refreshHeaderLayout)
		elseif button.Name == "Avatars" then
			hideAllSubCategoryFrames()
			currentCategory = button.Name
			setSelectedCategory(button)
			setSelectedSubCategory(nil)
			resetScrollingFrame()
			loadAvatarBundles()
			task.defer(refreshHeaderLayout)
		elseif button.Name == "Wearing" then
			hideAllSubCategoryFrames()
			currentCategory = button.Name
			setSelectedCategory(button)
			loadWearing()
			setSelectedSubCategory(nil)
			scaleFrame.Visible = false
			task.defer(refreshHeaderLayout)
		end
	end
	local categoryButton = Button.new({
		guiButton = button,
		ActivatedCallback = activated,
	})
	categoryButton:SetSelected(button.Name == currentCategory)
	activeCategoryButtons[button] = categoryButton
	styleTabButton(button, button.Name == currentCategory)
end

for i, frame in ipairs(subCategoryFrames) do
	local subCategoryButtons = TableUtil.Filter(frame:GetChildren(), function(item)
		return item:IsA("GuiButton")
	end)
	for ii, button in ipairs(subCategoryButtons) do
		local function activated(inputObject)
			-- V10: limpiamos el texto SIN disparar otra búsqueda HTTP.
			clearSearch()
			setSelectedSubCategory(button)
			if button.Name == "SkinTone" then
				resetScrollingFrame(true)
				loadSkinTones()
				scrollingFrame.Visible = true
				scaleFrame.Visible = false
				searchFrame.Visible = true
			elseif button.Name == "Scale" then
				resetScrollingFrame(true)
				loadScales()
				scrollingFrame.Visible = false
				scaleFrame.Visible = true
				searchFrame.Visible = false
			else
				loadAccessories(button.Name)
				scrollingFrame.Visible = true
				scaleFrame.Visible = false
				searchFrame.Visible = true
			end
			task.defer(refreshHeaderLayout)
		end
		local subCategoryButton = Button.new({
			guiButton = button,
			ActivatedCallback = activated,
		})
		subCategoryButton:SetSelected(button.Name == currentSubCategory)
		activeSubCategoryButtons[button] = subCategoryButton
		styleTabButton(button, button.Name == currentSubCategory)
	end
end

-- hopefully this won't use all the bandwith, limit how often it fires the server if possible
local heightSliderFrame = NumberSlider.new(function(newValue, oldValue)
	remoteEvent:FireServer("scale", "BodyHeightScale", newValue)
end, scaleFrame.Height, 90, 105, true)

local widthSliderFrame = NumberSlider.new(function(newValue, oldValue)
	remoteEvent:FireServer("scale", "BodyWidthScale", newValue)
end, scaleFrame.Width, 70, 100, true)

local headSliderFrame = NumberSlider.new(function(newValue, oldValue)
	remoteEvent:FireServer("scale", "HeadScale", newValue)
end, scaleFrame.Head, 95, 100, true)

local proportionSliderFrame = NumberSlider.new(function(newValue, oldValue)
	remoteEvent:FireServer("scale", "BodyProportionScale", newValue)
end, scaleFrame.Proportion, 0, 100, true)

local bodySliderFrame = NumberSlider.new(function(newValue, oldValue)
	remoteEvent:FireServer("scale", "BodyTypeScale", newValue)
end, scaleFrame.BodyType, 0, 100, true)

avatarEditorFrame.Visible = false
catalogFrameCloseTween:Play()
viewerFrameCloseTween:Play()

do
	for attempt = 1, 3 do
		local success, result = pcall(function()
			return game:GetService("Players"):GetCharacterAppearanceInfoAsync(player.UserId)
		end)
		if success and result then
			wearingAssets = result
			break
		end
		warn("[AvatarEditor] No se pudo cargar la apariencia. Intento " .. attempt .. "/3")
		task.wait(0.5)
	end
end

if not wearingAssets then
	wearingAssets = {
		assets = {},
		scales = {height = 1, width = 1, head = 1, proportion = 0, bodyType = 0},
	}
end
wearingAssets.assets = wearingAssets.assets or {}
wearingAssets.scales = wearingAssets.scales or {height = 1, width = 1, head = 1, proportion = 0, bodyType = 0}

loadAccessories(currentSubCategory)
updateScaleFrameCanvasSize()

heightSliderFrame:Set((wearingAssets.scales.height or 1) * 100)
widthSliderFrame:Set((wearingAssets.scales.width or 1) * 100)
headSliderFrame:Set((wearingAssets.scales.head or 1) * 100)
proportionSliderFrame:Set((wearingAssets.scales.proportion or 0) * 100)
bodySliderFrame:Set((wearingAssets.scales.bodyType or 0) * 100)

forceTransparencyRecovery(character)

clearSearchButton.Activated:Connect(function()
	local hadText = searchTextBox.Text ~= ""
	clearSearch()
	if hadText and liveCatalogMode and liveSearchHandler then
		liveSearchHandler("")
	else
		search()
	end
end)
searchTextBox:GetPropertyChangedSignal("Text"):Connect(search)
player.CharacterAdded:Connect(characterAdded)
toggleButton.Activated:Connect(toggle)
remoteEvent.OnClientEvent:Connect(onClientEvent)
remoteEvent:FireServer("requestState")
scaleFrameUIGridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateScaleFrameCanvasSize)
scrollingFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	updateCatalogGrid()
	task.defer(refreshHeaderLayout)
end)
scrollingFrameUIGridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateScrollingFrameCanvasSize)
scrollingFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
	if not liveCatalogMode or not liveCatalogPages or liveCatalogLoading then
		return
	end
	local bottom = scrollingFrame.CanvasPosition.Y + scrollingFrame.AbsoluteWindowSize.Y
	local contentHeight = scrollingFrameUIGridLayout.AbsoluteContentSize.Y
	if bottom >= contentHeight - LIVE_PREFETCH_DISTANCE then
		loadMoreLiveCatalog()
	end
end)
catalogFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	task.defer(refreshHeaderLayout)
end)

task.defer(function()
	refreshHeaderLayout()
	updateCatalogGrid()
end)

catalogFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	task.defer(refreshHeaderLayout)
end)

headerFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	task.defer(function()
		updateCatalogGrid()
	end)
end)

-- V16: si por cualquier ruta externa se abre PetCareMenu mientras el
-- armario está activo, cerramos el armario primero y dejamos una sola cámara.
player:GetAttributeChangedSignal("PetCareMenuOpen"):Connect(function()
	if isOpen and player:GetAttribute("PetCareMenuOpen") == true then
		warn("[AvatarEditor] PetCareMenu intentó abrirse; cerrando armario para evitar choque de cámara/LTM.")
		closeSequence()
	end
end)
