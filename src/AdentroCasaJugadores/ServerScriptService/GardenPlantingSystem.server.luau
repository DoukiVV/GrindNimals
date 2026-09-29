local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")

local plantasFolder = ServerStorage:WaitForChild("Plantas")
local itemFolder = ServerStorage:WaitForChild("Item")
local semillasFolder = itemFolder:WaitForChild("Semillas")
local frutasFolder = itemFolder:WaitForChild("Frutas")
local gardensFolder = workspace:WaitForChild("Jardin")

--============================================================
-- XP POR ACCIONES DEL JUEGO
-- Busca el sistema central de nivel en el servidor.
-- Si AwardGameAction no existe todavía, usa AwardPlayerXP como respaldo.
--============================================================
local function awardGameActionXP(player, actionName, fallbackXP)
	if not player or player.Parent ~= Players then
		return
	end

	local actionEvent = ReplicatedStorage:FindFirstChild("AwardGameAction")
	if actionEvent and actionEvent:IsA("BindableEvent") then
		actionEvent:Fire(player, actionName)
		return
	end

	local xpEvent = ReplicatedStorage:FindFirstChild("AwardPlayerXP")
	if xpEvent and xpEvent:IsA("BindableEvent") then
		xpEvent:Fire(player, fallbackXP, actionName)
	end
end


--==============================================================
-- TIEMPOS DE CRECIMIENTO POR RAREZA
--==============================================================
local TIEMPOS_POR_RAREZA = {
	Comun = 20 * 60,                 -- 20 minutos
	Raro = 30 * 60,                  -- 30 minutos
	MuyRaro = 40 * 60,               -- 40 minutos
	Epico = 90 * 60,                 -- 1 hora 30 minutos
	Legendario = 3 * 60 * 60,        -- 3 horas
}

local RAREZA_POR_CULTIVO = {
	-- Legendarios
	SandiaNegra = "Legendario",
	["PiñaRosa"] = "Legendario",
	FresaRosa = "Legendario",
	FresaBlanca = "Legendario", -- compatibilidad con el nombre anterior
	MelonVerde = "Legendario",

	-- Epicos
	Sandia = "Epico",
	Melon = "Epico",
	Durian = "Epico",
	Cacao = "Epico",
	TrufaBlanca = "Epico",
	["Mangostán"] = "Epico",
	Coco = "Epico",
	Calabaza = "Epico",
	["Piña"] = "Epico",

	-- Muy raros
	Yuca = "MuyRaro",
	YucaMorada = "MuyRaro", -- compatibilidad con el nombre anterior
	TrufaNegra = "MuyRaro",
	Lichi = "MuyRaro",
	FrutaDragon = "MuyRaro",
	Carambola = "MuyRaro",
	Alcachofa = "MuyRaro",

	-- Raros
	Platano = "Raro",
	Fresa = "Raro",
	Mango = "Raro",
	Granada = "Raro",
	Higo = "Raro",
	Remolacha = "Raro",
	LechugaMorada = "Raro",
	ColMorada = "Raro",

	-- Comunes
	Zanahoria = "Comun",
	Papa = "Comun",
	Lechuga = "Comun",
	Col = "Comun",
	Cebolla = "Comun",
	Manzana = "Comun",
	Naranja = "Comun",
	Trigo = "Comun",
	Tomate = "Comun",
}

local function obtenerRarezaCultivo(nombreCultivo)
	return RAREZA_POR_CULTIVO[nombreCultivo] or "Comun"
end

local function obtenerTiempoTotalCultivo(nombreCultivo)
	local rareza = obtenerRarezaCultivo(nombreCultivo)
	return TIEMPOS_POR_RAREZA[rareza] or TIEMPOS_POR_RAREZA.Comun
end

local function formatearTiempo(segundos)
	segundos = math.max(0, math.ceil(segundos))
	local horas = math.floor(segundos / 3600)
	local minutos = math.floor((segundos % 3600) / 60)
	local segundosRestantes = segundos % 60

	if horas > 0 then
		return string.format("%dh %02dm %02ds", horas, minutos, segundosRestantes)
	elseif minutos > 0 then
		return string.format("%dm %02ds", minutos, segundosRestantes)
	else
		return tostring(segundosRestantes) .. "s"
	end
end
local cuadrosOcupados = {}
local originalSlotState = {}
local connectedPrompts = {}
local ultimoPlantado = {}
local gardenPreviewStore = DataStoreService:GetDataStore("PlayerGardenPreview_v4")
local saveGardenDebounce = {}
local GARDEN_PREVIEW_CHANNEL = "GardenPreviewUpdated_v1"

local cropsRoot = workspace:FindFirstChild("CultivosActivos") or Instance.new("Folder")
cropsRoot.Name = "CultivosActivos"
cropsRoot.Parent = workspace

local CULTIVOS_SALEN_SUELO = {
	Cebolla = true,
	Col = true,
	ColMorada = true,
	Lechuga = true,
	LechugaMorada = true,
	Papa = true,
	Remolacha = true,
	Trigo = true,
	TrufaBlanca = true,
	TrufaNegra = true,
	YucaMorada = true,
	Yuca = true,
	Zanahoria = true,
}

local CULTIVOS_NORMALES = {
	Alcachofa = true,
	Calabaza = true,
	Cebolla = true,
	Col = true,
	ColMorada = true,
	Fresa = true,
	FresaBlanca = true,
	FresaRosa = true,
	Lechuga = true,
	LechugaMorada = true,
	Melon = true,
	MelonVerde = true,
	Papa = true,
	["Piña"] = true,
	["PiñaRosa"] = true,
	Remolacha = true,
	Sandia = true,
	SandiaNegra = true,
	Tomate = true,
	Trigo = true,
	TrufaBlanca = true,
	TrufaNegra = true,
	YucaMorada = true,
	Yuca = true,
	Zanahoria = true,
}

local CULTIVOS_ARBOLES = {
	Cacao = true,
	Carambola = true,
	Coco = true,
	Durian = true,
	FrutaDragon = true,
	Granada = true,
	Higo = true,
	Lichi = true,
	Mango = true,
	["Mangostán"] = true,
	Manzana = true,
	Naranja = true,
	Platano = true,
}

local ETAPAS_POR_CULTIVO = { Tomate = 4 }

local function trim(value)
	return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function normalizarNombre(value)
	local text = trim(value):gsub("%s+", "")
	text = text:gsub("á", "a"):gsub("é", "e"):gsub("í", "i"):gsub("ó", "o"):gsub("ú", "u"):gsub("ñ", "n")
	text = text:gsub("Á", "A"):gsub("É", "E"):gsub("Í", "I"):gsub("Ó", "O"):gsub("Ú", "U"):gsub("Ñ", "N")
	return text:lower()
end

local CULTIVOS_CANONICOS = {}
for nombre in pairs(CULTIVOS_NORMALES) do CULTIVOS_CANONICOS[normalizarNombre(nombre)] = nombre end
for nombre in pairs(CULTIVOS_ARBOLES) do CULTIVOS_CANONICOS[normalizarNombre(nombre)] = nombre end
CULTIVOS_CANONICOS[normalizarNombre("TrufaNegraYBlanca")] = "TrufaNegra"
CULTIVOS_CANONICOS[normalizarNombre("FrutadelDragon")] = "FrutaDragon"
CULTIVOS_CANONICOS[normalizarNombre("FrutaDelDragon")] = "FrutaDragon"
CULTIVOS_CANONICOS[normalizarNombre("Platanero")] = "Platano"
CULTIVOS_CANONICOS[normalizarNombre("Mangostan")] = "Mangostán"
CULTIVOS_CANONICOS[normalizarNombre("Pina")] = "Piña"

local function tipoCultivo(nombreCultivo)
	if CULTIVOS_ARBOLES[nombreCultivo] then return "Arbol" end
	if CULTIVOS_NORMALES[nombreCultivo] then return "Cultivo" end
	return nil
end

local function getGardenNumber(instance)
	local current = instance
	for _ = 1, 12 do
		if not current then break end
		local number = current.Name:match("^Jardin%s*(%d+)$")
		if number then return tonumber(number) end
		current = current.Parent
	end
	return nil
end
local crearEtapa
local configurarRecoleccion
local obtenerNumeroEtapas
local iniciarCrecimiento

local function cropPreviewRecord(slotIndex, cropName, cropType, plantedAt)
	plantedAt = tonumber(plantedAt) or os.time()
	local totalGrowSeconds = obtenerTiempoTotalCultivo(cropName)
	return {
		SlotIndex = slotIndex,
		Crop = cropName,
		Type = cropType or tipoCultivo(cropName) or "Cultivo",
		PlantedAt = plantedAt,
		ReadyAt = plantedAt + totalGrowSeconds,
		TotalGrowSeconds = totalGrowSeconds,
	}
end

local function obtenerEtapaPorTiempo(nombreCultivo, plantedAt)
	local etapas = obtenerNumeroEtapas(nombreCultivo)
	local tiempoTotal = obtenerTiempoTotalCultivo(nombreCultivo)
	local transcurrido = math.max(0, os.time() - (tonumber(plantedAt) or os.time()))

	if transcurrido >= tiempoTotal then
		return etapas, true
	end

	local progreso = math.clamp(transcurrido / tiempoTotal, 0, 0.999999)
	local etapa = math.floor(progreso * (etapas - 1)) + 1
	etapa = math.clamp(etapa, 1, etapas - 1)
	return etapa, false
end

local function snapshotGarden(player, gardenNumber)
	local crops = {}
	local seenSlots = {}

	for cuadro, datos in pairs(cuadrosOcupados) do
		if datos and datos.owner == player and datos.gardenNumber == gardenNumber then
			local slotIndex = tonumber(cuadro:GetAttribute("GardenSlotIndex")) or 0
			seenSlots[slotIndex] = true
			table.insert(crops, cropPreviewRecord(
				slotIndex,
				datos.nombreCultivo,
				cuadro:GetAttribute("GardenSlotType") or tipoCultivo(datos.nombreCultivo) or "Cultivo",
				datos.plantedAt
				))
		end
	end

	local garden = gardensFolder:FindFirstChild("Jardin " .. tostring(gardenNumber)) or gardensFolder:FindFirstChild("Jardin" .. tostring(gardenNumber))
	if garden then
		for _, slot in ipairs(garden:GetDescendants()) do
			if slot:IsA("BasePart") and slot.Name == "SlotPlantar" and slot:GetAttribute("GardenOccupied") then
				local ownerUserId = tonumber(slot:GetAttribute("GardenOwnerUserId"))
				local cropName = slot:GetAttribute("GardenCropName")
				local slotIndex = tonumber(slot:GetAttribute("GardenSlotIndex")) or 0
				if ownerUserId == player.UserId and type(cropName) == "string" and cropName ~= "" and not seenSlots[slotIndex] then
					seenSlots[slotIndex] = true
					table.insert(crops, cropPreviewRecord(
						slotIndex,
						cropName,
						slot:GetAttribute("GardenSlotType") or tipoCultivo(cropName) or "Cultivo",
						slot:GetAttribute("GardenPlantedAt")
						))
				end
			end
		end
	end

	table.sort(crops, function(a, b) return (a.SlotIndex or 0) < (b.SlotIndex or 0) end)
	return {
		GardenNumber = gardenNumber,
		UpdatedAt = os.time(),
		Crops = crops,
	}
end

local function publishGardenPreviewUpdate(player, data)
	if not player or type(data) ~= "table" then return end
	task.spawn(function()
		local okPublish, publishErr = pcall(function()
			MessagingService:PublishAsync(GARDEN_PREVIEW_CHANNEL, {
				UserId = player.UserId,
				GardenNumber = data.GardenNumber,
				UpdatedAt = data.UpdatedAt,
				Crops = data.Crops,
			})
		end)
		if not okPublish then
			warn("[GardenPlanting] No se pudo avisar preview en tiempo real: " .. tostring(publishErr))
		end
	end)
end

local function saveGardenPreviewNow(player, gardenNumber, waitForSave)
	gardenNumber = tonumber(gardenNumber)

	if not player or not gardenNumber then
		return false
	end

	local data = snapshotGarden(player, gardenNumber)
	publishGardenPreviewUpdate(player, data)

	local function writeData()
		local okSave, err = pcall(function()
			gardenPreviewStore:SetAsync(
				"Player_" .. tostring(player.UserId),
				data
			)

			gardenPreviewStore:SetAsync(
				"user_" .. tostring(player.UserId),
				data
			)
		end)

		if okSave then
			print(string.format(
				"[GardenPlanting] Jardin guardado para %s: cultivos=%d",
				player.Name,
				type(data.Crops) == "table" and #data.Crops or 0
				))
		else
			warn(
				"[GardenPlanting] No se pudo guardar jardin: "
					.. tostring(err)
			)
		end

		return okSave
	end

	if waitForSave == true then
		return writeData()
	end

	task.spawn(writeData)
	return true
end

local function saveGardenPreview(player, gardenNumber)
	if not player or not gardenNumber then return end
	local token = tostring(player.UserId) .. ":" .. tostring(gardenNumber)
	if saveGardenDebounce[token] then return end
	saveGardenDebounce[token] = true
	task.delay(0.2, function()
		saveGardenDebounce[token] = nil
		saveGardenPreviewNow(player, gardenNumber)
	end)
end
local function getSlotByIndex(gardenNumber, slotIndex)
	for cuadro in pairs(originalSlotState) do
		if getGardenNumber(cuadro) == gardenNumber and cuadro:GetAttribute("GardenSlotIndex") == slotIndex then
			return cuadro
		end
	end
	return nil
end

local function findPlayerForGarden(gardenNumber)
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("HouseNumber") == gardenNumber then
			return player
		end
	end
	return nil
end

local function occupyLoadedSlot(cuadro, player, crop)
	if not cuadro or not player or cuadrosOcupados[cuadro] then return end

	local cropName = tostring(crop.Crop or "")
	local plantaFolder = plantasFolder:FindFirstChild(cropName)
	if not plantaFolder then
		warn("[GardenPlanting] No existe Plantas/" .. cropName)
		return
	end

	local plantedAt = tonumber(crop.PlantedAt) or os.time()
	cuadrosOcupados[cuadro] = {
		nombreCultivo = cropName,
		plantaFolder = plantaFolder,
		planta = nil,
		gardenNumber = player:GetAttribute("HouseNumber"),
		owner = player,
		plantedAt = plantedAt,
		etapaActual = nil,
		growthRunning = false,
	}

	cuadro:SetAttribute("GardenOccupied", true)
	cuadro:SetAttribute("GardenCropName", cropName)
	cuadro:SetAttribute("GardenOwnerUserId", player.UserId)
	cuadro:SetAttribute("GardenPlantedAt", plantedAt)

	local prompt = cuadro:FindFirstChild("GardenPlantPrompt") or cuadro:FindFirstChild("ProximityPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt:SetAttribute("GardenOccupied", true)
		prompt.Enabled = false
	end

	cuadro.Transparency = 1
	cuadro.CanCollide = false
	cuadro.CanQuery = true

	local etapaActual, listo = obtenerEtapaPorTiempo(cropName, plantedAt)
	crearEtapa(cuadro, plantaFolder, etapaActual)

	if listo then
		configurarRecoleccion(cuadro, player)
	else
		task.spawn(function()
			iniciarCrecimiento(cuadro, player)
		end)
	end
end

local function loadGardenForPlayer(player)
	local gardenNumber =
		tonumber(player:GetAttribute("HouseNumber"))

	if not gardenNumber then
		return
	end

	local data = nil

	local okPrimary, primaryData = pcall(function()
		return gardenPreviewStore:GetAsync(
			"Player_" .. tostring(player.UserId)
		)
	end)

	if okPrimary and type(primaryData) == "table" then
		data = primaryData
	end

	-- Compatibilidad con la segunda clave utilizada por el sistema.
	if type(data) ~= "table"
		or type(data.Crops) ~= "table"
	then
		local okFallback, fallbackData = pcall(function()
			return gardenPreviewStore:GetAsync(
				"user_" .. tostring(player.UserId)
			)
		end)

		if okFallback and type(fallbackData) == "table" then
			data = fallbackData
		end
	end

	if type(data) ~= "table"
		or type(data.Crops) ~= "table"
	then
		print(
			"[GardenPlanting] Sin cultivos guardados para "
				.. player.Name
		)
		return
	end

	-- No comparar data.GardenNumber con gardenNumber.
	-- Casa1-Casa8 son slots temporales; el progreso pertenece al UserId.
	local loadedCount = 0

	for _, crop in ipairs(data.Crops) do
		local slotIndex =
			tonumber(crop.SlotIndex) or 0

		local slot =
			getSlotByIndex(gardenNumber, slotIndex)

		if slot then
			occupyLoadedSlot(slot, player, crop)
			loadedCount += 1
		else
			warn(string.format(
				"[GardenPlanting] No se encontro el slot %d en Jardin%d",
				slotIndex,
				gardenNumber
				))
		end
	end

	print(string.format(
		"[GardenPlanting] Jardin cargado para %s en Jardin%d: cultivos=%d",
		player.Name,
		gardenNumber,
		loadedCount
		))
end

local function playerOwnsGarden(player, gardenNumber)
	return typeof(gardenNumber) == "number" and player:GetAttribute("HouseNumber") == gardenNumber
end

obtenerNumeroEtapas = function(nombreCultivo)
	if CULTIVOS_SALEN_SUELO[nombreCultivo] then return 3 end
	return ETAPAS_POR_CULTIVO[nombreCultivo] or 3
end

local function obtenerSemilla(jugador)
	local containers = {jugador.Character, jugador:FindFirstChildOfClass("Backpack")}
	for _, container in ipairs(containers) do
		if container then
			local tools = {}
			for _, obj in ipairs(container:GetChildren()) do
				if obj:IsA("Tool") then table.insert(tools, obj) end
			end
			table.sort(tools, function(a, b) return trim(a.Name):lower() < trim(b.Name):lower() end)
			for _, obj in ipairs(tools) do
				local name = trim(obj.Name)
				local itemType = trim(obj:GetAttribute("ItemType") or obj:GetAttribute("Tipo")):lower()
				if itemType == "cultivo" or itemType == "crop" or name:match("^Semilla") or name:match("^Brote") or name:match("^Esporas") then
					return obj
				end
			end
		end
	end
	return nil
end

local function obtenerNombreCultivo(nombreTool)
	nombreTool = trim(nombreTool)
	local limpio = nombreTool
	for _, prefijo in ipairs({"SemilllaDe", "SemillaDe", "Semilla", "Brote", "Esporas"}) do
		if limpio:sub(1, #prefijo) == prefijo then
			limpio = limpio:sub(#prefijo + 1)
			break
		end
	end
	local directo = CULTIVOS_CANONICOS[normalizarNombre(limpio)]
	if directo then return directo end
	local toolKey = normalizarNombre(nombreTool)
	for clave, nombreCanonico in pairs(CULTIVOS_CANONICOS) do
		if toolKey:find(clave, 1, true) then return nombreCanonico end
	end
	return limpio
end

local function buscarItemPorCultivo(folder, nombreCultivo)
	local exacto = folder:FindFirstChild(nombreCultivo) or folder:FindFirstChild(nombreCultivo .. " ")
	if exacto then return exacto end
	for _, item in ipairs(folder:GetChildren()) do
		if obtenerNombreCultivo(item.Name) == nombreCultivo then
			return item
		end
	end
	return nil
end

local function configurarModelo(instancia)
	if instancia:IsA("BasePart") then
		instancia.Anchored = true
		instancia.CanCollide = false
		instancia.CanTouch = false
		instancia.CanQuery = false
	elseif instancia:IsA("Model") then
		for _, obj in ipairs(instancia:GetDescendants()) do
			if obj:IsA("BasePart") then
				obj.Anchored = true
				obj.CanCollide = false
				obj.CanTouch = false
				obj.CanQuery = false
			end
		end
		if not instancia.PrimaryPart then
			local base = instancia:FindFirstChildWhichIsA("BasePart", true)
			if base then instancia.PrimaryPart = base end
		end
	end
end

local function posicionar(instancia, posicion)
	if instancia:IsA("BasePart") then
		instancia.CFrame = CFrame.new(posicion)
	elseif instancia:IsA("Model") and instancia.PrimaryPart then
		instancia:PivotTo(CFrame.new(posicion))
	end
end

local function getGardenCropFolder(gardenNumber)
	local folder = cropsRoot:FindFirstChild("Jardin" .. tostring(gardenNumber))
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Jardin" .. tostring(gardenNumber)
		folder.Parent = cropsRoot
	end
	return folder
end

local function destruirPlanta(cuadro)
	local datos = cuadrosOcupados[cuadro]
	if datos and datos.planta then
		datos.planta:Destroy()
		datos.planta = nil
	end
end

local function crearBillboard(cuadro)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Temporizador"
	gui.Size = UDim2.new(0, 120, 0, 50)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	-- El temporizador solo se muestra cuando el jugador esta cerca.
	-- Asi no se ve desde la otra punta de la casa o desde fuera.
	gui.MaxDistance = 50
	gui.Parent = cuadro
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.FredokaOne
	label.Parent = gui
	return gui, label
end

local function actualizarTemporizador(label, segundos)
	for i = segundos, 1, -1 do
		if not label or not label.Parent then return end
		label.Text = i .. "s"
		task.wait(1)
	end
end

crearEtapa = function(cuadro, plantaFolder, etapa)
	local plantilla
	if CULTIVOS_SALEN_SUELO[plantaFolder.Name] then
		plantilla = plantaFolder:FindFirstChild(plantaFolder.Name .. "Cultivo")
	else
		plantilla = plantaFolder:FindFirstChild("Etapa" .. etapa)
	end
	if not plantilla then
		warn("[GardenPlanting] No existe modelo en Plantas/" .. plantaFolder.Name)
		return nil
	end
	destruirPlanta(cuadro)
	local clon = plantilla:Clone()
	configurarModelo(clon)
	local datos = cuadrosOcupados[cuadro]
	clon.Parent = getGardenCropFolder(datos.gardenNumber)

	local alturaModelo = 0
	if clon:IsA("Model") then
		local _, size = clon:GetBoundingBox()
		alturaModelo = size.Y
	elseif clon:IsA("BasePart") then
		alturaModelo = clon.Size.Y
	end

	local posicionFinal = Vector3.new(cuadro.Position.X, cuadro.Position.Y + (alturaModelo / 2) - 0.1, cuadro.Position.Z)
	if CULTIVOS_SALEN_SUELO[plantaFolder.Name] then
		local porcentajeVisible = {[1] = 0.15, [2] = 0.50, [3] = 1.00}
		local visible = porcentajeVisible[etapa] or 1
		local profundidad = alturaModelo * (1 - visible)
		local nuevaY = posicionFinal.Y - profundidad
		if plantaFolder.Name == "Remolacha" and etapa == 3 then nuevaY -= alturaModelo * 0.23 end
		posicionar(clon, Vector3.new(posicionFinal.X, nuevaY, posicionFinal.Z))
	else
		posicionar(clon, posicionFinal)
	end
	datos.planta = clon
	datos.etapaActual = etapa
	return clon
end

local function darItems(jugador, nombreCultivo)
	local backpack = jugador:FindFirstChildOfClass("Backpack")
	if not backpack then return end
	local fruta = buscarItemPorCultivo(frutasFolder, nombreCultivo)
	if fruta then
		for _ = 1, math.random(4, 12) do fruta:Clone().Parent = backpack end
	end
	if math.random(1, 2) == 1 then
		local semilla = buscarItemPorCultivo(semillasFolder, nombreCultivo)
		if semilla then
			for _ = 1, math.random(2, 6) do semilla:Clone().Parent = backpack end
		end
	end
end

local function restoreSlot(cuadro)
	local state = originalSlotState[cuadro]
	if not state then return end
	cuadro.Transparency = state.Transparency
	cuadro.Reflectance = state.Reflectance
	cuadro.CanCollide = state.CanCollide
	cuadro.CanQuery = state.CanQuery
end

configurarRecoleccion = function(cuadro, jugadorDueno)
	local datos = cuadrosOcupados[cuadro]
	if not datos then return end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RecolectarPrompt"
	prompt.ActionText = "Recoger"
	prompt.ObjectText = datos.nombreCultivo
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
	prompt.HoldDuration = 0.7
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 14
	prompt:SetAttribute("GardenOwnerUserId", jugadorDueno.UserId)
	prompt:SetAttribute("LocalPlantName", datos.nombreCultivo)
	prompt.Parent = cuadro
	prompt.Triggered:Connect(function(jugador)
		if jugador ~= jugadorDueno then return end
		prompt:Destroy()
		destruirPlanta(cuadro)
		darItems(jugador, datos.nombreCultivo)

		if tipoCultivo(datos.nombreCultivo) == "Arbol" then
			awardGameActionXP(jugador, "HarvestTreeFruit", 10)
		else
			awardGameActionXP(jugador, "HarvestCrop", 8)
		end

		cuadrosOcupados[cuadro] = nil
		saveGardenPreviewNow(jugador, datos.gardenNumber)
		cuadro:SetAttribute("GardenOccupied", false)
		cuadro:SetAttribute("GardenCropName", nil)
		cuadro:SetAttribute("GardenOwnerUserId", nil)
		cuadro:SetAttribute("GardenPlantedAt", nil)
		local plantarPrompt = cuadro:FindFirstChild("GardenPlantPrompt") or cuadro:FindFirstChild("ProximityPrompt")
		if plantarPrompt and plantarPrompt:IsA("ProximityPrompt") then
			plantarPrompt:SetAttribute("GardenOccupied", false)
			plantarPrompt.Enabled = cuadro:GetAttribute("GardenPlotUnlocked") ~= false
		end
		restoreSlot(cuadro)
	end)
end

iniciarCrecimiento = function(cuadro, jugador)
	local datos = cuadrosOcupados[cuadro]
	if not datos then return end
	if datos.growthRunning then return end

	datos.growthRunning = true
	local nombreCultivo = datos.nombreCultivo
	local etapas = obtenerNumeroEtapas(nombreCultivo)
	local tiempoTotal = obtenerTiempoTotalCultivo(nombreCultivo)

	local viejo = cuadro:FindFirstChild("Temporizador")
	if viejo then viejo:Destroy() end

	local gui, label = crearBillboard(cuadro)

	while cuadrosOcupados[cuadro] == datos do
		local transcurrido = math.max(0, os.time() - datos.plantedAt)
		local restante = tiempoTotal - transcurrido

		if restante <= 0 then
			break
		end

		local progreso = math.clamp(transcurrido / tiempoTotal, 0, 0.999999)
		local etapaActual = math.floor(progreso * (etapas - 1)) + 1
		etapaActual = math.clamp(etapaActual, 1, etapas - 1)

		if datos.etapaActual ~= etapaActual then
			crearEtapa(cuadro, datos.plantaFolder, etapaActual)
		end

		if label and label.Parent then
			label.Text = formatearTiempo(restante)
		end

		task.wait(1)
	end

	if cuadrosOcupados[cuadro] ~= datos then
		if gui and gui.Parent then gui:Destroy() end
		return
	end

	crearEtapa(cuadro, datos.plantaFolder, etapas)
	if gui and gui.Parent then gui:Destroy() end
	datos.growthRunning = false
	configurarRecoleccion(cuadro, jugador)
	saveGardenPreview(jugador, datos.gardenNumber)
end

local function plantar(cuadro, jugador, esZonaArboles, gardenNumber)
	if cuadrosOcupados[cuadro] then return end
	if cuadro:GetAttribute("GardenPlotUnlocked") == false then return end
	if not playerOwnsGarden(jugador, gardenNumber) then return end
	local root = jugador.Character and jugador.Character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - cuadro.Position).Magnitude > 16 then return end
	local semilla = obtenerSemilla(jugador)
	if not semilla then return end
	local nombreCultivo = obtenerNombreCultivo(semilla.Name)
	local tipo = tipoCultivo(nombreCultivo)
	local tipoZona = esZonaArboles and "Arbol" or "Cultivo"
	if tipo ~= tipoZona then return end
	local plantaFolder = plantasFolder:FindFirstChild(nombreCultivo)
	if not plantaFolder then
		warn("[GardenPlanting] No existe Plantas/" .. nombreCultivo)
		return
	end
	local ahora = os.clock()
	if ahora - (ultimoPlantado[jugador] or 0) < 0.8 then return end
	ultimoPlantado[jugador] = ahora
	if cuadrosOcupados[cuadro] then return end
	cuadrosOcupados[cuadro] = {
		nombreCultivo = nombreCultivo,
		plantaFolder = plantaFolder,
		planta = nil,
		gardenNumber = gardenNumber,
		owner = jugador,
		plantedAt = os.time(),
		etapaActual = nil,
		growthRunning = false,
	}
	cuadro:SetAttribute("GardenOccupied", true)
	cuadro:SetAttribute("GardenCropName", nombreCultivo)
	cuadro:SetAttribute("GardenOwnerUserId", jugador.UserId)
	cuadro:SetAttribute("GardenPlantedAt", cuadrosOcupados[cuadro].plantedAt)
	semilla:Destroy()
	local prompt = cuadro:FindFirstChild("GardenPlantPrompt") or cuadro:FindFirstChild("ProximityPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt:SetAttribute("GardenOccupied", true)
		prompt.Enabled = false
	end
	cuadro.Transparency = 1
	cuadro.CanCollide = false
	cuadro.CanQuery = true
	if not crearEtapa(cuadro, plantaFolder, 1) then
		cuadrosOcupados[cuadro] = nil
		cuadro:SetAttribute("GardenOccupied", false)
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt:SetAttribute("GardenOccupied", false)
			prompt.Enabled = true
		end
		restoreSlot(cuadro)
		return
	end
	awardGameActionXP(jugador, "PlantCrop", 4)

	saveGardenPreviewNow(jugador, gardenNumber)
	task.spawn(function() iniciarCrecimiento(cuadro, jugador) end)
end

local function conectarSlot(objeto, esZonaArboles, gardenNumber)
	local cuadro = objeto:IsA("BasePart") and objeto or objeto:FindFirstChildWhichIsA("BasePart", true)
	if not cuadro then return end
	if connectedPrompts[cuadro] then return end
	connectedPrompts[cuadro] = true
	originalSlotState[cuadro] = originalSlotState[cuadro] or {
		Transparency = cuadro.Transparency,
		Reflectance = cuadro.Reflectance,
		CanCollide = cuadro.CanCollide,
		CanQuery = cuadro.CanQuery,
	}
	local prompt = cuadro:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = cuadro
	end
	local slotType = esZonaArboles and "Arbol" or "Cultivo"
	cuadro:SetAttribute("GardenSlotType", slotType)
	cuadro:SetAttribute("GardenOccupied", cuadrosOcupados[cuadro] ~= nil)
	prompt.Name = "GardenPlantPrompt"
	prompt.ActionText = "Plantar"
	prompt.ObjectText = slotType
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
	prompt.HoldDuration = 0.45
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt:SetAttribute("GardenSlotType", slotType)
	prompt:SetAttribute("GardenOccupied", cuadrosOcupados[cuadro] ~= nil)
	prompt.Enabled = cuadro:GetAttribute("GardenPlotUnlocked") ~= false
	prompt.Triggered:Connect(function(jugador)
		plantar(cuadro, jugador, esZonaArboles, gardenNumber)
	end)
end

local function getSortedSlots(zone)
	local slots = {}
	if not zone then return slots end
	for _, child in ipairs(zone:GetChildren()) do
		if child.Name == "SlotPlantar" then
			local slot = child:IsA("BasePart") and child or child:FindFirstChildWhichIsA("BasePart", true)
			if slot then table.insert(slots, {container = child, part = slot}) end
		end
	end
	table.sort(slots, function(a, b)
		local aLocal = zone.CFrame:PointToObjectSpace(a.part.Position)
		local bLocal = zone.CFrame:PointToObjectSpace(b.part.Position)
		local dz = math.abs(aLocal.Z - bLocal.Z)
		if dz > 0.15 then return aLocal.Z < bLocal.Z end
		return aLocal.X < bLocal.X
	end)
	return slots
end

local EXPANSION_SLOT_CONFIG = {
	ZonaDePlantado = {IsTrees = false, Rows = 6, Columns = 6, GenerateSlots = false},
	ZonaDePlantadoArboles = {IsTrees = true, Rows = 3, Columns = 4, GenerateSlots = false},
	TerrenoCultivos = {IsTrees = false, Rows = 6, Columns = 6, GenerateSlots = true},
	TerrenoArboles = {IsTrees = true, Rows = 3, Columns = 4, GenerateSlots = true},
}

local ZONE_CONNECT_ORDER = {"ZonaDePlantado", "ZonaDePlantadoArboles", "TerrenoCultivos", "TerrenoArboles"}

local function ensureGeneratedSlots(zone, config)
	if not config.GenerateSlots then return end
	for _, child in ipairs(zone:GetChildren()) do
		if child.Name == "SlotPlantar" then return end
	end

	local rows = config.Rows
	local columns = config.Columns
	local marginX = math.min(4, zone.Size.X * 0.18)
	local marginZ = math.min(4, zone.Size.Z * 0.18)
	local usableX = math.max(2, zone.Size.X - marginX * 2)
	local usableZ = math.max(2, zone.Size.Z - marginZ * 2)
	local topY = zone.Size.Y / 2 + 0.12

	for row = 1, rows do
		for column = 1, columns do
			local alphaX = columns == 1 and 0.5 or (column - 1) / (columns - 1)
			local alphaZ = rows == 1 and 0.5 or (row - 1) / (rows - 1)
			local localX = -usableX / 2 + usableX * alphaX
			local localZ = -usableZ / 2 + usableZ * alphaZ

			local slot = Instance.new("Part")
			slot.Name = "SlotPlantar"
			slot.Anchored = true
			slot.CanCollide = false
			slot.CanQuery = true
			slot.CanTouch = false
			slot.Transparency = 1
			slot.Size = Vector3.new(2, 0.25, 2)
			slot.CFrame = zone.CFrame * CFrame.new(localX, topY, localZ)
			slot:SetAttribute("GeneratedExpansionSlot", true)
			slot:SetAttribute("GardenPlotUnlocked", false)
			slot.Parent = zone
		end
	end
end

local function conectarJardin(jardin)
	local gardenNumber = getGardenNumber(jardin)
	local slotIndex = 0
	if not gardenNumber then return 0 end
	local count = 0
	for _, zoneName in ipairs(ZONE_CONNECT_ORDER) do
		local zone = jardin:FindFirstChild(zoneName, true)
		local config = EXPANSION_SLOT_CONFIG[zoneName]
		if zone and zone:IsA("BasePart") and config then
			ensureGeneratedSlots(zone, config)
			for _, slotInfo in ipairs(getSortedSlots(zone)) do
				slotIndex += 1
				local cuadro = slotInfo.part
				cuadro:SetAttribute("GardenSlotIndex", slotIndex)
				conectarSlot(slotInfo.container, config.IsTrees, gardenNumber)
				count += 1
			end
		end
	end
	return count
end

local total = 0
for _, jardin in ipairs(gardensFolder:GetChildren()) do
	total += conectarJardin(jardin)
end
print("[GardenPlanting] Slots conectados en jardines reales: " .. tostring(total))

gardensFolder.ChildAdded:Connect(function(jardin)
	task.wait(0.2)
	local added = conectarJardin(jardin)
	if added > 0 then print("[GardenPlanting] Slots conectados en " .. jardin.Name .. ": " .. tostring(added)) end
	local gardenNumber = getGardenNumber(jardin)
	local player = gardenNumber and findPlayerForGarden(gardenNumber)
	if player then task.defer(loadGardenForPlayer, player) end
end)

Players.PlayerRemoving:Connect(function(player)
	local gardenNumber =
		tonumber(player:GetAttribute("HouseNumber"))

	-- Se espera a que DataStore termine antes de borrar los cultivos
	-- del jardín temporal.
	if gardenNumber then
		saveGardenPreviewNow(
			player,
			gardenNumber,
			true
		)
	end

	ultimoPlantado[player] = nil

	for cuadro, datos in pairs(cuadrosOcupados) do
		if datos.owner == player then
			destruirPlanta(cuadro)
			cuadrosOcupados[cuadro] = nil

			cuadro:SetAttribute(
				"GardenOccupied",
				false
			)
			cuadro:SetAttribute(
				"GardenCropName",
				nil
			)
			cuadro:SetAttribute(
				"GardenOwnerUserId",
				nil
			)
			cuadro:SetAttribute(
				"GardenPlantedAt",
				nil
			)

			local prompt =
				cuadro:FindFirstChild(
					"GardenPlantPrompt"
				)
				or cuadro:FindFirstChild(
					"ProximityPrompt"
				)

			if prompt
				and prompt:IsA("ProximityPrompt")
			then
				prompt:SetAttribute(
					"GardenOccupied",
					false
				)
				prompt.Enabled = true
			end

			restoreSlot(cuadro)
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	local loaded = false
	local function tryLoad()
		if loaded then return end
		if not player:GetAttribute("HouseNumber") then return end
		loaded = true
		task.wait(1)
		loadGardenForPlayer(player)
	end
	player:GetAttributeChangedSignal("HouseNumber"):Connect(tryLoad)
	task.defer(tryLoad)
	task.delay(3, tryLoad)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.defer(function()
		task.wait(1)
		loadGardenForPlayer(player)
	end)
end

game:BindToClose(function()
	local pending = 0

	for _, player in ipairs(Players:GetPlayers()) do
		local gardenNumber =
			tonumber(
				player:GetAttribute("HouseNumber")
			)

		if gardenNumber then
			pending += 1

			task.spawn(function()
				saveGardenPreviewNow(
					player,
					gardenNumber,
					true
				)

				pending -= 1
			end)
		end
	end

	local started = os.clock()

	while pending > 0
		and os.clock() - started < 8
	do
		task.wait(0.05)
	end
end)

task.spawn(function()
	while task.wait(20) do
		for _, player in ipairs(Players:GetPlayers()) do
			local gardenNumber =
				tonumber(
					player:GetAttribute("HouseNumber")
				)

			if gardenNumber then
				saveGardenPreviewNow(
					player,
					gardenNumber,
					false
				)
			end
		end
	end
end)