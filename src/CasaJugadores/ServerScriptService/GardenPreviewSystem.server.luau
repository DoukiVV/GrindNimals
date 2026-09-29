-- GardenPreviewSystem V11 - CasaJugadores | usa Preview/Normales + Preview/Ampliado
-- Refleja en el exterior:
-- 1) parcelas desbloqueadas/compradas en AdentroCasaJugadores
-- 2) cultivos plantados, exactamente en el mismo SlotIndex
-- 3) timers de crecimiento
--
-- Usa los mismos DataStores del interior.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local ServerStorage = game:GetService("ServerStorage")

local CasaJugadorFolder = Workspace:WaitForChild("Casa Jugador")
-- El GardenPlanting actual de AdentroCasaJugadores guarda en V4.
local GardenPreviewStore =
	DataStoreService:GetDataStore("PlayerGardenPreview_v4")

-- Respaldo para datos viejos que todavía estén en V1.
local GardenPreviewLegacyStore =
	DataStoreService:GetDataStore("PlayerGardenPreview_v1")

-- Misma compra de parcelas que GardenPlotPurchaseSystem.
local GardenPlotStore =
	DataStoreService:GetDataStore("PlayerGardenPlots_v1")

local PlantasFolder = ServerStorage:WaitForChild("Plantas")
local PREVIEW_NAME = "GardenCropPreview"
local LEGACY_PREVIEW_NAME = "GardenPreview"
local GARDEN_PREVIEW_CHANNEL = "GardenPreviewUpdated_v1"
local livePreviewDataByUserId = {}

local C = {
	cream = Color3.fromRGB(255, 238, 205),
	signBg = Color3.fromRGB(59, 39, 25),
	leaf = Color3.fromRGB(41, 139, 65),
	leaf2 = Color3.fromRGB(92, 186, 92),
	stem = Color3.fromRGB(62, 130, 52),
	trunk = Color3.fromRGB(98, 61, 35),
}

local cropColors = {
	Tomate = Color3.fromRGB(225, 48, 42), Fresa = Color3.fromRGB(216, 44, 85), FresaBlanca = Color3.fromRGB(246, 238, 218),
	Zanahoria = Color3.fromRGB(239, 131, 35), Papa = Color3.fromRGB(182, 138, 75), Remolacha = Color3.fromRGB(136, 35, 74),
	Trigo = Color3.fromRGB(228, 190, 75), Lechuga = Color3.fromRGB(95, 189, 80), LechugaMorada = Color3.fromRGB(134, 77, 154),
	Calabaza = Color3.fromRGB(229, 132, 38), Sandia = Color3.fromRGB(48, 151, 74), SandiaNegra = Color3.fromRGB(25, 73, 48),
	Cebolla = Color3.fromRGB(222, 207, 180), Col = Color3.fromRGB(93, 169, 90), ColMorada = Color3.fromRGB(119, 66, 145),
	Mango = Color3.fromRGB(239, 162, 45), Manzana = Color3.fromRGB(218, 50, 47), Naranja = Color3.fromRGB(234, 136, 40),
	Coco = Color3.fromRGB(126, 80, 46), Cacao = Color3.fromRGB(92, 49, 28), Granada = Color3.fromRGB(188, 39, 58),
}

local function makePart(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function makeCylinder(parent, name, size, cf, color, material)
	local p = makePart(parent, name, size, cf, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function cropColor(name)
	return cropColors[name] or Color3.fromRGB(235, 189, 72)
end
local function hidePreviewBaseParts(instance)
	for _, obj in ipairs(instance:GetDescendants()) do
		if obj:IsA("SelectionBox") or obj:IsA("BoxHandleAdornment") then
			obj:Destroy()
		elseif obj:IsA("BasePart") then
			local name = obj.Name:lower()
			local size = obj.Size
			local looksLikeFlatGreenBase = size.Y <= math.max(0.08, math.min(size.X, size.Z) * 0.18)
				and size.X >= 0.65 and size.Z >= 0.65
				and obj.Color.G > obj.Color.R * 1.2 and obj.Color.G > obj.Color.B * 1.2
			local namedAsBase = name:find("cuadro", 1, true) or name:find("slot", 1, true) or name:find("base", 1, true) or name:find("suelo", 1, true) or name:find("terrain", 1, true) or name:find("plantado", 1, true)
			if namedAsBase or looksLikeFlatGreenBase then
				obj.Transparency = 1
				obj.CanCollide = false
				obj.CanTouch = false
				obj.CanQuery = false
			end
		end
	end
end

local function configurePreviewModel(instance)
	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanTouch = false
		instance.CanQuery = false
	elseif instance:IsA("Model") then
		for _, obj in ipairs(instance:GetDescendants()) do
			if obj:IsA("BasePart") then
				obj.Anchored = true
				obj.CanCollide = false
				obj.CanTouch = false
				obj.CanQuery = false
			end
		end
		if not instance.PrimaryPart then
			local base = instance:FindFirstChildWhichIsA("BasePart", true)
			if base then instance.PrimaryPart = base end
		end
	end
end

local function findCropTemplate(cropName, cropType)
	local folder = PlantasFolder:FindFirstChild(cropName) or PlantasFolder:FindFirstChild(cropName .. " ")
	if not folder then return nil end
	if cropType == "Arbol" then
		for _, name in ipairs({"Etapa3", "Etapa2", "Etapa1"}) do
			local direct = folder:FindFirstChild(name)
			if direct then return direct end
			local deep = folder:FindFirstChild(name, true)
			if deep then return deep end
		end
		local model = folder:FindFirstChildWhichIsA("Model", true)
		if model then return model end
		return folder:FindFirstChildWhichIsA("BasePart", true)
	end
	return folder:FindFirstChild(cropName .. "Cultivo")
		or folder:FindFirstChild(cropName .. " Cultivo")
		or folder:FindFirstChildWhichIsA("Model", true)
		or folder:FindFirstChildWhichIsA("MeshPart", true)
		or folder:FindFirstChildWhichIsA("BasePart", true)
end
local function fitCloneToSlot(clone, slot, cropType)
	configurePreviewModel(clone)
	local slotTop = slot.CFrame * CFrame.new(0, slot.Size.Y * 0.5 + 0.04, 0)
	local targetHeight = cropType == "Arbol" and math.clamp(slot.Size.Z * 2.15, 3.0, 5.25) or math.clamp(slot.Size.Z * 0.82, 1.0, 1.85)
	local maxFootprint = cropType == "Arbol" and math.min(slot.Size.X, slot.Size.Z) * 2.05 or math.min(slot.Size.X, slot.Size.Z) * 1.18
	local currentHeight = 1
	local currentFootprint = 1
	if clone:IsA("Model") then
		local _, size = clone:GetBoundingBox()
		currentHeight = math.max(size.Y, 0.1)
		currentFootprint = math.max(size.X, size.Z, 0.1)
	else
		currentHeight = math.max(clone.Size.Y, 0.1)
		currentFootprint = math.max(clone.Size.X, clone.Size.Z, 0.1)
	end
	local scale = math.min(targetHeight / currentHeight, maxFootprint / currentFootprint)
	if clone:IsA("Model") then
		pcall(function() clone:ScaleTo(scale) end)
		local _, size = clone:GetBoundingBox()
		clone:PivotTo(slotTop * CFrame.new(0, size.Y * 0.5, 0))
	else
		clone.Size = clone.Size * scale
		clone.CFrame = slotTop * CFrame.new(0, clone.Size.Y * 0.5, 0)
	end
	hidePreviewBaseParts(clone)
end

local function cloneRealCrop(parent, slot, cropName, cropType)
	local template = findCropTemplate(cropName, cropType)
	if not template then
		warn("[GardenPreview] No encontre modelo real para " .. tostring(cropName) .. "; usando preview simple.")
		return nil
	end
	local clone = template:Clone()
	clone.Name = "PreviewReal_" .. tostring(cropName)
	clone.Parent = parent
	fitCloneToSlot(clone, slot, cropType)
	return clone
end

local function loadPreviewData(userId)
	if not userId or userId <= 0 then
		return nil
	end

	local liveData =
		livePreviewDataByUserId[userId]

	if type(liveData) == "table" then
		return liveData
	end

	local stores = {
		GardenPreviewStore,
		GardenPreviewLegacyStore,
	}

	for _, store in ipairs(stores) do
		for _, prefix in ipairs({
			"Player_",
			"user_",
			}) do
			local ok, data =
				pcall(function()
					return store:GetAsync(
						prefix
						.. tostring(userId)
					)
				end)

			if ok
				and type(data) == "table" then

				return data
			end
		end
	end

	return nil
end

local function getCartelFace(cartel)
	local biggest
	for _, inst in ipairs(cartel:GetDescendants()) do
		if inst:IsA("BasePart") and (not biggest or inst.Size.X * inst.Size.Y > biggest.Size.X * biggest.Size.Y) then
			biggest = inst
		end
	end
	return biggest
end

local function chooseCartelFace(face, house)
	local casa = house:FindFirstChild("Casa")
	if not casa then return Enum.NormalId.Back end
	local toOutside = (face.Position - casa:GetPivot().Position).Unit
	local normals = {
		{Enum.NormalId.Front, Vector3.new(0, 0, -1)},
		{Enum.NormalId.Back, Vector3.new(0, 0, 1)},
		{Enum.NormalId.Right, Vector3.new(1, 0, 0)},
		{Enum.NormalId.Left, Vector3.new(-1, 0, 0)},
	}
	local bestFace = Enum.NormalId.Back
	local bestDot = -math.huge
	for _, info in ipairs(normals) do
		local worldNormal = face.CFrame:VectorToWorldSpace(info[2])
		local dot = worldNormal:Dot(toOutside)
		if dot > bestDot then
			bestDot = dot
			bestFace = info[1]
		end
	end
	return bestFace
end

local function setCartelName(house)
	local cartel = house:FindFirstChild("Cartel")
	if not cartel then return end
	local face = getCartelFace(cartel)
	if not face then return end
	local owner = house:FindFirstChild("OwnerName")
	local ownerUser = house:FindFirstChild("OwnerUsername")
	local ownerId = house:FindFirstChild("OwnerUserId")
	local displayName = owner and owner.Value or ""
	local username = ownerUser and ownerUser.Value or displayName
	local userId = ownerId and tonumber(ownerId.Value) or nil
	local existing = face:FindFirstChild("OwnerNameSurface")
	if existing
		and existing:GetAttribute("OwnerUserId") == userId
		and existing:GetAttribute("DisplayName") == displayName
		and existing:GetAttribute("Username") == username then
		return
	end
	if existing then existing:Destroy() end
	if displayName == "" then return end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "OwnerNameSurface"
	gui:SetAttribute("OwnerUserId", userId)
	gui:SetAttribute("DisplayName", displayName)
	gui:SetAttribute("Username", username)
	gui.Face = chooseCartelFace(face, house)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 58
	gui.LightInfluence = 0
	gui.Parent = face

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(212, 177, 147)
	bg.BackgroundTransparency = 0
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local avatar = Instance.new("ImageLabel")
	avatar.Name = "OwnerAvatar"
	avatar.Size = UDim2.fromScale(0.30, 0.78)
	avatar.Position = UDim2.fromScale(0.045, 0.11)
	avatar.BackgroundTransparency = 1
	avatar.ScaleType = Enum.ScaleType.Crop
	avatar.Parent = bg

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = avatar

	if userId then
		task.spawn(function()
			local okThumb, thumb = pcall(function()
				return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
			end)
			if okThumb and avatar.Parent then avatar.Image = thumb end
		end)
	end

	local function makeOutlinedLabel(name, text, size, position, strokeOffset)
		local holder = Instance.new("Frame")
		holder.Name = name .. "Holder"
		holder.Size = size
		holder.Position = position
		holder.BackgroundTransparency = 1
		holder.Parent = bg

		local offsets = {
			Vector2.new(-strokeOffset, 0), Vector2.new(strokeOffset, 0),
			Vector2.new(0, -strokeOffset), Vector2.new(0, strokeOffset),
			Vector2.new(-strokeOffset, -strokeOffset), Vector2.new(strokeOffset, -strokeOffset),
			Vector2.new(-strokeOffset, strokeOffset), Vector2.new(strokeOffset, strokeOffset),
		}
		for _, offset in ipairs(offsets) do
			local shadow = Instance.new("TextLabel")
			shadow.Name = name .. "Outline"
			shadow.Size = UDim2.fromScale(1, 1)
			shadow.Position = UDim2.fromOffset(offset.X, offset.Y)
			shadow.BackgroundTransparency = 1
			shadow.Font = Enum.Font.FredokaOne
			shadow.Text = text
			shadow.TextColor3 = Color3.fromRGB(0, 0, 0)
			shadow.TextStrokeTransparency = 1
			shadow.TextXAlignment = Enum.TextXAlignment.Left
			shadow.TextScaled = true
			shadow.TextWrapped = true
			shadow.ZIndex = 1
			shadow.Parent = holder
		end

		local label = Instance.new("TextLabel")
		label.Name = name
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.Text = text
		label.TextColor3 = Color3.fromRGB(245, 245, 250)
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.TextStrokeTransparency = 0.05
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextScaled = true
		label.TextWrapped = true
		label.ZIndex = 2
		label.Parent = holder
		return label
	end

	makeOutlinedLabel("OwnerDisplayName", displayName, UDim2.fromScale(0.59, 0.42), UDim2.fromScale(0.39, 0.18), 2)
	makeOutlinedLabel("OwnerUsernameText", "@" .. username, UDim2.fromScale(0.59, 0.28), UDim2.fromScale(0.39, 0.58), 1)
end

local function clearOldGeneratedPreview(house)
	local patio = house:FindFirstChild("Patio")
	local oldPatioPreview = patio and patio:FindFirstChild(LEGACY_PREVIEW_NAME)
	if oldPatioPreview then oldPatioPreview:Destroy() end
	local jardin = house:FindFirstChild("Jardin")
	local oldGardenPreview = jardin and jardin:FindFirstChild(PREVIEW_NAME)
	if oldGardenPreview then oldGardenPreview:Destroy() end
end

local function hidePreviewPlantingSlots(jardin)
	if not jardin then
		return
	end

	-- V3:
	-- Busca los SlotPlantar en TODO el Jardin.
	-- Las expansiones TerrenoCultivos/TerrenoArboles pueden estar
	-- fuera de la carpeta "Zonas de cultivo".
	for _, obj in ipairs(
		jardin:GetDescendants()
		) do
		if obj:IsA("BasePart")
			and obj.Name == "SlotPlantar" then

			obj.Transparency = 1
			obj.CanCollide = false
			obj.CanTouch = false
			obj.CanQuery = false

			local prompt =
				obj:FindFirstChildOfClass(
					"ProximityPrompt"
				)

			if prompt then
				prompt.Enabled = false
			end

		elseif obj:IsA("Decal")
			or obj:IsA("Texture") then

			local parent = obj.Parent

			if parent
				and parent:IsA("BasePart")
				and parent.Name == "SlotPlantar" then

				obj.Transparency = 1
			end
		end
	end
end

local function getSlots(zone)
	local slots = {}

	if not zone then
		return slots
	end

	for _, child in ipairs(
		zone:GetChildren()
		) do
		if child.Name == "SlotPlantar" then
			local slot =
				child:IsA("BasePart")
				and child
				or child:FindFirstChildWhichIsA(
					"BasePart",
					true
				)

			if slot then
				table.insert(
					slots,
					slot
				)
			end
		end
	end

	table.sort(
		slots,
		function(a, b)
			local aLocal =
				zone.CFrame:PointToObjectSpace(
					a.Position
				)

			local bLocal =
				zone.CFrame:PointToObjectSpace(
					b.Position
				)

			local dz =
				math.abs(
					aLocal.Z
					- bLocal.Z
				)

			if dz > 0.15 then
				return aLocal.Z
					< bLocal.Z
			end

			return aLocal.X
				< bLocal.X
		end
	)

	return slots
end

--============================================================
-- ZONAS DE AMPLIACION REALES DE CASA JUGADORES
--
-- Estructura confirmada:
-- Casa JugadorN
-- > Jardin
--   > Zona de venta de terreno
--     > Part
--     > Part
--   > Zonas de cultivo
--     > ZonaDePlantado
--     > ZonaDePlantadoArboles
--
-- Los dos "Part" son las ampliaciones exteriores.
-- Como ambos se llaman igual, los identificamos comparando su tamaño
-- con las parcelas base:
--   parcela grande -> cultivos
--   parcela pequeña -> arboles
-- y usamos el mejor emparejamiento por dimensiones.
--============================================================

--============================================================
-- ESTRUCTURA VISUAL V11
--
-- Jardin
-- > Preview
--   > Ampliado
--     > ZonaDePlantado
--     > ZonaDePlantadoArboles
--   > Normales
--     > ZonaDePlantado
--     > ZonaDePlantadoArboles
--
-- "Ampliado" ya es el mismo diseño que "Normales", solamente
-- transparente. Por eso NO clonamos ni generamos otro diseño.
--============================================================

local authoredTransparency = setmetatable(
	{},
	{ __mode = "k" }
)

local function rememberAuthoredTransparency(root)
	if not root then
		return
	end

	if root:IsA("BasePart")
		or root:IsA("Decal")
		or root:IsA("Texture") then

		if authoredTransparency[root] == nil then
			authoredTransparency[root] =
				root.Transparency
		end
	end

	for _, object in ipairs(
		root:GetDescendants()
		) do
		if object:IsA("BasePart")
			or object:IsA("Decal")
			or object:IsA("Texture") then

			if authoredTransparency[object] == nil then
				authoredTransparency[object] =
					object.Transparency
			end
		end
	end
end

local function relativePath(
	root,
	object
)
	local names = {}
	local current = object

	while current
		and current ~= root do

		table.insert(
			names,
			1,
			current.Name
		)

		current = current.Parent
	end

	return names
end

local function findByRelativePath(
	root,
	path
)
	local current = root

	for _, name in ipairs(path) do
		current =
			current
			and current:FindFirstChild(
				name
			)

		if not current then
			return nil
		end
	end

	return current
end

local function isInsidePlantingSlot(
	object,
	root
)
	local current = object

	while current
		and current ~= root do

		if current.Name == "SlotPlantar" then
			return true
		end

		current = current.Parent
	end

	return false
end

local function setExpandedVisualState(
	expandedZone,
	normalZone,
	unlocked
)
	if not expandedZone then
		return
	end

	rememberAuthoredTransparency(
		expandedZone
	)

	-- La pieza principal.
	if expandedZone:IsA("BasePart") then
		if unlocked
			and normalZone
			and normalZone:IsA("BasePart") then

			expandedZone.Transparency =
				normalZone.Transparency
		else
			expandedZone.Transparency =
				authoredTransparency[
			expandedZone
			] or expandedZone.Transparency
		end
	end

	for _, object in ipairs(
		expandedZone:GetDescendants()
		) do
		if object:IsA("BasePart")
			or object:IsA("Decal")
			or object:IsA("Texture") then

			-- Los SlotPlantar siempre deben seguir invisibles.
			if isInsidePlantingSlot(
				object,
				expandedZone
				) then

				if object:IsA("BasePart")
					or object:IsA("Decal")
					or object:IsA("Texture") then

					object.Transparency = 1
				end

				continue
			end

			if unlocked
				and normalZone then

				local matching =
					findByRelativePath(
						normalZone,
						relativePath(
							expandedZone,
							object
						)
					)

				if matching
					and (
						matching:IsA("BasePart")
							or matching:IsA("Decal")
							or matching:IsA("Texture")
					) then

					object.Transparency =
						matching.Transparency
				elseif object:IsA("BasePart") then
					-- Respaldo: hacer visible solo lo que no era
					-- completamente invisible de fábrica.
					local original =
						authoredTransparency[
					object
					]

					if original
						and original < 1 then

						object.Transparency = 0
					end
				end
			else
				local original =
					authoredTransparency[
				object
				]

				if original ~= nil then
					object.Transparency =
						original
				end
			end
		end
	end
end

local function getPreviewFolders(jardin)
	local preview =
		jardin:FindFirstChild(
			"Preview"
		)

	if not preview then
		return nil, nil, nil
	end

	local normales =
		preview:FindFirstChild(
			"Normales"
		)

	local ampliado =
		preview:FindFirstChild(
			"Ampliado"
		)

	return preview,
		normales,
		ampliado
end

local function findGardenZone(
	jardin,
	zoneName
)
	if not jardin then
		return nil
	end

	local _,
		normales,
		ampliado =
		getPreviewFolders(
			jardin
		)

	if not normales
		or not ampliado then

		return nil
	end

	if zoneName == "ZonaDePlantado" then
		return normales:FindFirstChild(
			"ZonaDePlantado"
		)
	end

	if zoneName == "ZonaDePlantadoArboles" then
		return normales:FindFirstChild(
			"ZonaDePlantadoArboles"
		)
	end

	if zoneName == "TerrenoCultivos" then
		return ampliado:FindFirstChild(
			"ZonaDePlantado"
		)
	end

	if zoneName == "TerrenoArboles" then
		return ampliado:FindFirstChild(
			"ZonaDePlantadoArboles"
		)
	end

	return nil
end

local ZONE_CONFIG = {
	ZonaDePlantado = {
		IsTrees = false,
		GenerateSlots = false,
	},

	ZonaDePlantadoArboles = {
		IsTrees = true,
		GenerateSlots = false,
	},

	TerrenoCultivos = {
		IsTrees = false,
		GenerateSlots = true,
		Rows = 6,
		Columns = 6,
	},

	TerrenoArboles = {
		IsTrees = true,
		GenerateSlots = true,
		Rows = 3,
		Columns = 4,
	},
}

-- IMPORTANTE:
-- Debe ser EL MISMO orden que usa GardenPlantingSystem del interior.
local ZONE_ORDER = {
	"ZonaDePlantado",
	"ZonaDePlantadoArboles",
	"TerrenoCultivos",
	"TerrenoArboles",
}

--============================================================
-- RANGOS REALES DEL GardenPlantingSystem
--
-- El interior conecta 96 slots por jardin:
-- 36 cultivos base
-- 12 arboles base
-- 36 cultivos expansion
-- 12 arboles expansion
--
-- Por eso los indices guardados quedan:
-- 1-36   ZonaDePlantado
-- 37-48  ZonaDePlantadoArboles
-- 49-84  TerrenoCultivos
-- 85-96  TerrenoArboles
--
-- Esto evita que CasaJugadores dependa de cuántos SlotPlantar
-- físicos tenga cada zona exterior.
--============================================================

local ZONE_SLOT_RANGES = {
	ZonaDePlantado = {
		Start = 1,
		Count = 36,
	},

	ZonaDePlantadoArboles = {
		Start = 37,
		Count = 12,
	},

	TerrenoCultivos = {
		Start = 49,
		Count = 36,
	},

	TerrenoArboles = {
		Start = 85,
		Count = 12,
	},
}

local PLOT_RULES = {
	ZonaDePlantado = {
		Id = "BaseCultivos",
		DefaultUnlocked = true,
	},

	ZonaDePlantadoArboles = {
		Id = "BaseArboles",
		DefaultUnlocked = true,
	},

	TerrenoCultivos = {
		Id = "CultivosNivel3",
		DefaultUnlocked = false,
	},

	TerrenoArboles = {
		Id = "ArbolesNivel5",
		DefaultUnlocked = false,
	},
}

local function ensureExpansionSlots(
	zone,
	config
)
	if not zone
		or not zone:IsA("BasePart")
		or not config
		or not config.GenerateSlots then

		return
	end

	local expected =
		(config.Rows or 0)
		* (config.Columns or 0)

	local existing = {}

	for _, child in ipairs(
		zone:GetChildren()
		) do
		if child.Name == "SlotPlantar"
			and child:IsA("BasePart") then

			table.insert(
				existing,
				child
			)
		end
	end

	if #existing == expected
		and expected > 0 then

		return
	end

	-- Si son slots generados por una preview anterior e incompleta,
	-- se regeneran para conservar exactamente el mismo mapa del interior.
	local hasManualSlot = false

	for _, slot in ipairs(existing) do
		if slot:GetAttribute(
			"GeneratedPreviewSlot"
			) == true then

			slot:Destroy()
		else
			hasManualSlot = true
		end
	end

	-- Si el mapa ya trae slots manuales, se respetan.
	if hasManualSlot then
		return
	end

	local rows = config.Rows
	local columns = config.Columns

	local marginX =
		math.min(
			4,
			zone.Size.X * 0.18
		)

	local marginZ =
		math.min(
			4,
			zone.Size.Z * 0.18
		)

	local usableX =
		math.max(
			2,
			zone.Size.X
			- marginX * 2
		)

	local usableZ =
		math.max(
			2,
			zone.Size.Z
			- marginZ * 2
		)

	local topY =
		zone.Size.Y / 2
		+ 0.12

	for row = 1, rows do
		for column = 1, columns do
			local alphaX =
				columns == 1
				and 0.5
				or (column - 1)
				/ (columns - 1)

			local alphaZ =
				rows == 1
				and 0.5
				or (row - 1)
				/ (rows - 1)

			local localX =
				-usableX / 2
				+ usableX * alphaX

			local localZ =
				-usableZ / 2
				+ usableZ * alphaZ

			local slot =
				Instance.new("Part")

			slot.Name = "SlotPlantar"

			slot.Size =
				Vector3.new(
					2,
					0.25,
					2
				)

			slot.CFrame =
				zone.CFrame
				* CFrame.new(
					localX,
					topY,
					localZ
				)

			slot.Anchored = true
			slot.Transparency = 1
			slot.CanCollide = false
			slot.CanTouch = false
			slot.CanQuery = false

			slot:SetAttribute(
				"GeneratedPreviewSlot",
				true
			)

			slot.Parent = zone
		end
	end
end

local function loadOwnedPlots(userId)
	local owned = {
		BaseCultivos = true,
		BaseArboles = true,
	}

	if not userId
		or userId <= 0 then

		return owned
	end

	local ok, data =
		pcall(function()
			return GardenPlotStore:GetAsync(
				"Plots_"
				.. tostring(userId)
			)
		end)

	if ok
		and type(data) == "table"
		and type(data.Owned)
		== "table" then

		for plotId, value in pairs(
			data.Owned
			) do
			if value == true then
				owned[tostring(plotId)] =
					true
			end
		end
	end

	return owned
end

--============================================================
-- VISUAL DE AMPLIACION V11
--============================================================

local function applyUnlockedPlotVisuals(
	house,
	ownerUserId
)
	local jardin =
		house:FindFirstChild("Jardin")

	if not jardin then
		return
	end

	local preview,
		normales,
		ampliado =
		getPreviewFolders(
			jardin
		)

	if not preview
		or not normales
		or not ampliado then

		warn(
			"[GardenPreview] "
				.. house.Name
				.. " necesita Jardin > Preview > Normales/Ampliado."
		)

		return
	end

	local owned =
		loadOwnedPlots(
			ownerUserId
		)

	-- Parcelas normales: siempre visibles tal como las diseñaste.
	local normalCultivos =
		normales:FindFirstChild(
			"ZonaDePlantado"
		)

	local normalArboles =
		normales:FindFirstChild(
			"ZonaDePlantadoArboles"
		)

	if normalCultivos
		and normalCultivos:IsA("BasePart") then

		normalCultivos:SetAttribute(
			"GardenPlotUnlocked",
			true
		)
	end

	if normalArboles
		and normalArboles:IsA("BasePart") then

		normalArboles:SetAttribute(
			"GardenPlotUnlocked",
			true
		)
	end

	-- Parcelas ampliadas: ya existen físicamente.
	local expandedCultivos =
		ampliado:FindFirstChild(
			"ZonaDePlantado"
		)

	local expandedArboles =
		ampliado:FindFirstChild(
			"ZonaDePlantadoArboles"
		)

	local cropsUnlocked =
		owned.CultivosNivel3 == true

	local treesUnlocked =
		owned.ArbolesNivel5 == true

	if expandedCultivos then
		expandedCultivos:SetAttribute(
			"GardenPlotUnlocked",
			cropsUnlocked
		)

		expandedCultivos:SetAttribute(
			"PreviewPurchased",
			cropsUnlocked
		)

		setExpandedVisualState(
			expandedCultivos,
			normalCultivos,
			cropsUnlocked
		)
	end

	if expandedArboles then
		expandedArboles:SetAttribute(
			"GardenPlotUnlocked",
			treesUnlocked
		)

		expandedArboles:SetAttribute(
			"PreviewPurchased",
			treesUnlocked
		)

		setExpandedVisualState(
			expandedArboles,
			normalArboles,
			treesUnlocked
		)
	end
end

local function getGardenSlotMap(house)
	local jardin =
		house:FindFirstChild("Jardin")

	if not jardin then
		return nil, {}
	end

	local preview,
		normales,
		ampliado =
		getPreviewFolders(
			jardin
		)

	if not preview
		or not normales
		or not ampliado then

		warn(
			"[GardenPreview] Falta estructura Preview en "
				.. house.Name
		)

		return jardin, {}
	end

	local slotMap = {}

	for _, zoneName in ipairs(
		ZONE_ORDER
		) do
		local zone =
			findGardenZone(
				jardin,
				zoneName
			)

		local config =
			ZONE_CONFIG[zoneName]

		local range =
			ZONE_SLOT_RANGES[zoneName]

		if zone
			and config
			and range then

			ensureExpansionSlots(
				zone,
				config
			)

			local zoneSlots =
				getSlots(zone)

			-- Si una zona de expansion todavía no tiene todos los
			-- slots generados, forzamos una segunda comprobación.
			if config.GenerateSlots
				and #zoneSlots < range.Count then

				ensureExpansionSlots(
					zone,
					config
				)

				zoneSlots =
					getSlots(zone)
			end

			for localIndex, slot in ipairs(
				zoneSlots
				) do
				if localIndex > range.Count then
					break
				end

				local globalIndex =
					range.Start
					+ localIndex
				- 1

				slot:SetAttribute(
					"GardenSlotIndex",
					globalIndex
				)

				slot:SetAttribute(
					"PreviewZoneName",
					zoneName
				)

				slot:SetAttribute(
					"PreviewZoneSlotIndex",
					localIndex
				)

				slotMap[globalIndex] = {
					Slot = slot,
					ZoneName = zoneName,
					ZoneIndex = localIndex,
					Type =
						config.IsTrees
						and "Arbol"
						or "Cultivo",
				}
			end
		end
	end

	return jardin, slotMap
end

local function formatSeconds(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local minutes = math.floor(seconds / 60)
	local rest = seconds % 60
	if minutes > 0 then
		return string.format("%d:%02d", minutes, rest)
	end
	return tostring(rest)
end

local function addTimerBillboard(parent, slot, crop, ownerUserId)
	local readyAt = tonumber(crop.ReadyAt)

	-- Si el cultivo ya termino, no se crea ningun Label ni Billboard.
	if not readyAt or readyAt <= os.time() then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "PreviewTimer"
	gui.Adornee = slot
	gui.Size = UDim2.new(0, 46, 0, 16)
	gui.StudsOffset = Vector3.new(0, 1.35, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 55
	gui.Enabled = false
	gui:SetAttribute("OwnerUserId", ownerUserId)
	gui:SetAttribute("ReadyAt", readyAt)
	gui.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "TimerLabel"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(255, 245, 215)
	label.TextStrokeTransparency = 0.72
	label.TextScaled = true
	label.Parent = gui

	task.spawn(function()
		while gui.Parent do
			local remaining = readyAt - os.time()

			if remaining <= 0 then
				-- Destruirlo evita que el LocalScript vuelva a habilitar un Label terminado.
				gui:Destroy()
				return
			end

			label.Text = formatSeconds(remaining)
			task.wait(1)
		end
	end)
end

local function makeCropPreview(parent, slot, cropName)
	if cloneRealCrop(parent, slot, cropName, "Cultivo") then return end
	local base = slot.CFrame * CFrame.new(0, slot.Size.Y * 0.5 + 0.08, 0)
	local height = math.clamp(slot.Size.Z * 0.38, 0.65, 1.05)
	makeCylinder(parent, "PreviewStem", Vector3.new(0.12, height, 0.12), base * CFrame.new(0, height * 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), C.stem, Enum.Material.Grass)
	makePart(parent, "PreviewLeaf", Vector3.new(slot.Size.X * 0.38, 0.12, slot.Size.Z * 0.16), base * CFrame.new(-slot.Size.X * 0.08, height * 0.58, 0) * CFrame.Angles(0, math.rad(18), math.rad(16)), C.leaf, Enum.Material.Grass)
	makePart(parent, "PreviewLeaf", Vector3.new(slot.Size.X * 0.38, 0.12, slot.Size.Z * 0.16), base * CFrame.new(slot.Size.X * 0.08, height * 0.75, 0) * CFrame.Angles(0, math.rad(-18), math.rad(-16)), C.leaf2, Enum.Material.Grass)
	makePart(parent, "PreviewCrop", Vector3.new(0.28, 0.24, 0.28), base * CFrame.new(0, height + 0.13, 0), cropColor(cropName), Enum.Material.SmoothPlastic)
end

local function makeTreePreview(parent, slot, cropName)
	if cloneRealCrop(parent, slot, cropName, "Arbol") then return end
	local base = slot.CFrame * CFrame.new(0, slot.Size.Y * 0.5 + 0.08, 0)
	local height = math.clamp(slot.Size.Z * 0.55, 0.9, 1.45)
	makeCylinder(parent, "PreviewTreeTrunk", Vector3.new(0.20, height, 0.20), base * CFrame.new(0, height * 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), C.trunk, Enum.Material.Wood)
	makePart(parent, "PreviewTreeTop", Vector3.new(slot.Size.X * 0.72, height * 0.7, slot.Size.Z * 0.55), base * CFrame.new(0, height + 0.32, 0), C.leaf, Enum.Material.Grass)
	makePart(parent, "PreviewFruit", Vector3.new(0.24, 0.24, 0.24), base * CFrame.new(slot.Size.X * 0.15, height + 0.45, -slot.Size.Z * 0.12), cropColor(cropName), Enum.Material.SmoothPlastic)
end
local function buildCropPreview(house)
	clearOldGeneratedPreview(house)
	setCartelName(house)

	local ownerIdValue =
		house:FindFirstChild(
			"OwnerUserId"
		)

	local ownerUserId =
		ownerIdValue
		and tonumber(
			ownerIdValue.Value
		)
		or tonumber(
			house:GetAttribute(
				"OwnerUserId"
			)
		)

	local jardin, slotMap =
		getGardenSlotMap(house)

	if not jardin then
		return
	end

	-- Reflejar las parcelas compradas en AdentroCasaJugadores.
	applyUnlockedPlotVisuals(
		house,
		ownerUserId
	)

	hidePreviewPlantingSlots(
		jardin
	)

	local data =
		ownerUserId
		and loadPreviewData(
			ownerUserId
		)
		or nil

	local crops =
		type(data) == "table"
		and type(data.Crops)
		== "table"
		and data.Crops
		or {}

	local preview =
		Instance.new("Model")

	preview.Name =
		PREVIEW_NAME

	preview:SetAttribute(
		"CropCount",
		#crops
	)

	preview:SetAttribute(
		"OwnerUserId",
		ownerUserId
	)

	local _,
		normalFolder,
		expandedFolder =
		getPreviewFolders(
			jardin
		)

	local expansionCultivos =
		expandedFolder
		and expandedFolder:FindFirstChild(
			"ZonaDePlantado"
		)

	local expansionArboles =
		expandedFolder
		and expandedFolder:FindFirstChild(
			"ZonaDePlantadoArboles"
		)

	if expansionCultivos then
		preview:SetAttribute(
			"ExpansionCultivosPath",
			expansionCultivos:GetFullName()
		)
	end

	if expansionArboles then
		preview:SetAttribute(
			"ExpansionArbolesPath",
			expansionArboles:GetFullName()
		)
	end

	preview.Parent =
		jardin

	local mappedCropCount = 0
	local maxSavedSlotIndex = 0

	for _, crop in ipairs(crops) do
		local cropType =
			tostring(
				crop.Type
				or "Cultivo"
			)

		local cropName =
			tostring(
				crop.Crop
				or "Cultivo"
			)

		local slotIndex =
			tonumber(
				crop.SlotIndex
			)

		if slotIndex then
			maxSavedSlotIndex =
				math.max(
					maxSavedSlotIndex,
					slotIndex
				)
		end

		local slotInfo =
			slotIndex
			and slotMap[slotIndex]
			or nil

		if slotInfo
			and slotInfo.Slot then

			mappedCropCount += 1

			local slot =
				slotInfo.Slot

			-- El SlotIndex manda.
			-- Así lo plantado en TerrenoCultivos/TerrenoArboles
			-- aparece en la parcela de expansión correcta.
			if cropType == "Arbol" then
				makeTreePreview(
					preview,
					slot,
					cropName
				)
			else
				makeCropPreview(
					preview,
					slot,
					cropName
				)
			end

			addTimerBillboard(
				preview,
				slot,
				crop,
				ownerUserId
			)
		else
			local expectedZone = "desconocida"

			if slotIndex then
				if slotIndex >= 1
					and slotIndex <= 36 then

					expectedZone = "ZonaDePlantado"

				elseif slotIndex <= 48 then
					expectedZone = "ZonaDePlantadoArboles"

				elseif slotIndex <= 84 then
					expectedZone = "TerrenoCultivos"

				elseif slotIndex <= 96 then
					expectedZone = "TerrenoArboles"
				end
			end

			warn(
				"[GardenPreview] No existe SlotIndex "
					.. tostring(slotIndex)
					.. " en "
					.. house.Name
					.. " | zona esperada: "
					.. expectedZone
					.. " | Jardin: "
					.. tostring(
						jardin:GetFullName()
					)
			)
		end
	end

	preview:SetAttribute(
		"MappedCropCount",
		mappedCropCount
	)

	preview:SetAttribute(
		"SavedMaxSlotIndex",
		maxSavedSlotIndex
	)

	preview:SetAttribute(
		"PreviewSlotCount",
		(function()
			local count = 0
			for _ in pairs(slotMap) do
				count += 1
			end
			return count
		end)()
	)
end

local function houseOwnerUserId(house)
	local ownerId = house:FindFirstChild("OwnerUserId")
	if ownerId and ownerId:IsA("ValueBase") then return tonumber(ownerId.Value) end
	return tonumber(house:GetAttribute("OwnerUserId"))
end

local function rebuildPreviewForUser(userId)
	userId = tonumber(userId)
	if not userId then return end
	for i = 1, 8 do
		local house = CasaJugadorFolder:FindFirstChild("Casa Jugador" .. i)
		if house and houseOwnerUserId(house) == userId then
			buildCropPreview(house)
		end
	end
end

local function connectHouse(house)
	if not house:IsA("Model") then return end
	buildCropPreview(house)
	house.ChildAdded:Connect(function(child)
		if child.Name == "OwnerUserId" or child.Name == "OwnerName" then
			task.delay(0.25, function() if house.Parent then buildCropPreview(house) end end)
		end
	end)
	for _, tagName in ipairs({"OwnerUserId", "OwnerName"}) do
		local tag = house:FindFirstChild(tagName)
		if tag and tag:IsA("ValueBase") then
			tag:GetPropertyChangedSignal("Value"):Connect(function()
				task.delay(0.25, function() if house.Parent then buildCropPreview(house) end end)
			end)
		end
	end
end

for i = 1, 8 do
	local house = CasaJugadorFolder:FindFirstChild("Casa Jugador" .. i)
	if house then connectHouse(house) end
end

CasaJugadorFolder.ChildAdded:Connect(function(child)
	if child.Name:match("^Casa Jugador%d+$") then
		task.wait(0.5)
		connectHouse(child)
	end
end)

task.spawn(function()
	local okSubscribe, subscribeErr = pcall(function()
		MessagingService:SubscribeAsync(GARDEN_PREVIEW_CHANNEL, function(message)
			local data = message.Data
			if type(data) == "table" then
				local userId = tonumber(data.UserId)
				if userId and type(data.Crops) == "table" then
					livePreviewDataByUserId[userId] = {
						GardenNumber =
							data.GardenNumber,

						UpdatedAt =
							data.UpdatedAt
							or os.time(),

						Crops =
							data.Crops,
					}
				end
				task.defer(rebuildPreviewForUser, data.UserId)
			end
		end)
	end)
	if not okSubscribe then
		warn("[GardenPreview] No se pudo escuchar actualizaciones en tiempo real: " .. tostring(subscribeErr))
	end
end)

while task.wait(30) do
	for i = 1, 8 do
		local house = CasaJugadorFolder:FindFirstChild("Casa Jugador" .. i)
		if house then buildCropPreview(house) end
	end
end
print("[GardenPreview] V11 ACTIVO | usa Preview/Normales + Preview/Ampliado preparados en Studio.")
