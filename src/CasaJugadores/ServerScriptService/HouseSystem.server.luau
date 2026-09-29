--!strict
-- ============================================================
-- HOUSE SYSTEM MULTIJUGADOR V4.7
-- Tipo: Script
-- Ubicación: CasaJugadores > ServerScriptService > HouseSystem
--
-- Corrige:
-- 1) Al regresar desde AdentroCasaJugadores, vuelve a cargar los
--    colores más recientes y no deja la casa con colores viejos.
-- 2) Libera inmediatamente una casa cuando el jugador cierra Roblox
--    o sale al lobby desde AdentroCasaJugadores.
-- 3) Pinta correctamente la pieza Puerta y su Union exterior.
-- ============================================================

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")

local HouseDataStore = DataStoreService:GetDataStore("HouseData_v1")
local SharedCustomizationStore =
	DataStoreService:GetDataStore("PlayerHouseCustomization_v3")

local HouseSessionMap =
	MemoryStoreService:GetHashMap("BlockFarmHouseSessions_v4")

local SESSION_TTL = 120
local SESSION_CHECK_INTERVAL = 20
local HOUSE_RELEASE_CHANNEL = "HouseExteriorRelease_v1"

local retainedInteriorUsers = {}

local function sessionKey(userId)
	return "user_" .. tostring(userId)
end

local function writeHouseSession(userId, payload)
	payload = type(payload) == "table" and payload or {}
	payload.UserId = userId
	payload.UpdatedAt = os.time()

	local ok, err = pcall(function()
		HouseSessionMap:SetAsync(
			sessionKey(userId),
			payload,
			SESSION_TTL
		)
	end)

	if not ok then
		warn("[HouseSystem] No se pudo escribir la sesión: "
			.. tostring(err))
	end

	return ok
end

local function readHouseSession(userId)
	local ok, result = pcall(function()
		return HouseSessionMap:GetAsync(sessionKey(userId))
	end)

	if not ok then
		warn("[HouseSystem] No se pudo leer la sesión de "
			.. tostring(userId))
		return nil
	end

	return type(result) == "table" and result or nil
end

local function removeHouseSession(userId)
	pcall(function()
		HouseSessionMap:RemoveAsync(sessionKey(userId))
	end)
end

local RemoteEvents =
	ReplicatedStorage:FindFirstChild("RemoteEvents")
	or Instance.new("Folder")

RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local function remote(name)
	local object = RemoteEvents:FindFirstChild(name)

	if not object then
		object = Instance.new("RemoteEvent")
		object.Name = name
		object.Parent = RemoteEvents
	end

	return object
end

local ApplyCustomization = remote("ApplyCustomization")
local RequestHouseData = remote("RequestHouseData")
local SendHouseData = remote("SendHouseData")

local CasaJugadorFolder = Workspace:WaitForChild("Casa Jugador")

local CASA_NAMES = {
	"Casa Jugador1",
	"Casa Jugador2",
	"Casa Jugador3",
	"Casa Jugador4",
	"Casa Jugador5",
	"Casa Jugador6",
	"Casa Jugador7",
	"Casa Jugador8",
}

local SURFACES = {
	Techo = {
		color = "TechoColor",
		material = "TechoMaterial",
		hints = {"techo", "roof", "tejado"},
	},
	Pared = {
		color = "ParedColor",
		material = "ParedMaterial",
		hints = {"pared", "paredes", "wall", "body"},
	},
	Piso = {
		color = "PisoColor",
		material = "PisoMaterial",
		hints = {"piso", "floor", "suelo", "escalon"},
	},
	Puerta = {
		color = "PuertaColor",
		material = "PuertaMaterial",
		hints = {"puerta", "door"},
	},
	Interior = {
		color = "InteriorColor",
		material = "InteriorMaterial",
		hints = {"interior", "adentro", "inside"},
	},
}

local DEFAULT_DATA = {
	TechoColor = {R = 0.2, G = 0.2, B = 0.2},
	TechoMaterial = Enum.Material.SmoothPlastic.Value,

	ParedColor = {R = 0.7, G = 0.5, B = 0.3},
	ParedMaterial = Enum.Material.SmoothPlastic.Value,

	PisoColor = {R = 0.55, G = 0.42, B = 0.28},
	PisoMaterial = Enum.Material.Wood.Value,

	PuertaColor = {R = 0.36, G = 0.2, B = 0.11},
	PuertaMaterial = Enum.Material.Wood.Value,

	InteriorColor = {R = 0.78, G = 0.7, B = 0.58},
	InteriorMaterial = Enum.Material.SmoothPlastic.Value,

	Furniture = {},
}

local MATERIAL_ALIASES = {
	Concreto = Enum.Material.Concrete,
	Ladrillo = Enum.Material.Brick,
	Madera = Enum.Material.Wood,
	Piedra = Enum.Material.Cobblestone,
	Liso = Enum.Material.SmoothPlastic,
	Metal = Enum.Material.Metal,
	Marmol = Enum.Material.Marble,
	Tejas = Enum.Material.Slate,
}

local playerHouseMap = {}
local availableHouses = {}
local loadedData = {}
local pendingSaves = {}
local requestedReturnHouse = {}
local pendingReturnSpawn = {}

local function cloneTable(value)
	if type(value) ~= "table" then
		return value
	end

	local result = {}

	for key, child in pairs(value) do
		result[key] = cloneTable(child)
	end

	return result
end

local function normalizeColor(color, fallback)
	if type(color) ~= "table" then
		return cloneTable(fallback)
	end

	return {
		R = math.clamp(tonumber(color.R) or fallback.R, 0, 1),
		G = math.clamp(tonumber(color.G) or fallback.G, 0, 1),
		B = math.clamp(tonumber(color.B) or fallback.B, 0, 1),
	}
end

local function normalizeMaterial(value, fallback)
	local numeric = tonumber(value) or fallback

	return Enum.Material:FromValue(numeric)
		and numeric
		or fallback
end

local function normalizeData(data)
	data = type(data) == "table" and data or {}

	local normalized = cloneTable(DEFAULT_DATA)

	for _, config in pairs(SURFACES) do
		normalized[config.color] = normalizeColor(
			data[config.color],
			DEFAULT_DATA[config.color]
		)

		normalized[config.material] = normalizeMaterial(
			data[config.material],
			DEFAULT_DATA[config.material]
		)
	end

	normalized.Furniture =
		type(data.Furniture) == "table"
		and data.Furniture
		or {}

	return normalized
end

local function materialValueFromStored(value, fallback)
	if type(value) == "number" then
		return normalizeMaterial(value, fallback)
	end

	if type(value) == "string" then
		local material =
			MATERIAL_ALIASES[value]
			or Enum.Material[value]

		if material then
			return material.Value
		end
	end

	return fallback
end

local function mergeSharedSurfaceData(baseData, sharedData)
	if type(sharedData) ~= "table"
		or type(sharedData.Surface) ~= "table"
	then
		return baseData
	end

	for surface, config in pairs(SURFACES) do
		local entry = sharedData.Surface[surface]

		if type(entry) == "table" then
			if type(entry.Color) == "table" then
				baseData[config.color] = normalizeColor(
					entry.Color,
					baseData[config.color]
				)
			end

			baseData[config.material] = materialValueFromStored(
				entry.Material,
				baseData[config.material]
			)
		end
	end

	if type(sharedData.Furniture) == "table" then
		baseData.Furniture = sharedData.Furniture
	end

	return baseData
end

local function storeHouseDefaults(casaModel)
	for _, part in ipairs(casaModel:GetDescendants()) do
		if part:IsA("BasePart")
			and part:GetAttribute("HouseDefaultColor") == nil
		then
			part:SetAttribute(
				"HouseDefaultColor",
				part.Color
			)

			part:SetAttribute(
				"HouseDefaultMaterial",
				part.Material.Name
			)
		end
	end
end

local function restoreHouseDefaults(casaModel)
	for _, part in ipairs(casaModel:GetDescendants()) do
		if part:IsA("BasePart") then
			local color =
				part:GetAttribute("HouseDefaultColor")

			local materialName =
				part:GetAttribute("HouseDefaultMaterial")

			if typeof(color) == "Color3" then
				part.Color = color
			end

			if type(materialName) == "string" then
				local material = Enum.Material[materialName]

				if material then
					part.Material = material
				end
			end
		end
	end
end

local function houseIsOccupied(casaModel)
	local ownerUserId =
		casaModel:FindFirstChild("OwnerUserId")

	if ownerUserId
		and ownerUserId:IsA("ValueBase")
		and tonumber(ownerUserId.Value)
		and tonumber(ownerUserId.Value) > 0
	then
		return true
	end

	return casaModel:GetAttribute("PresenceOwnerOnline") == true
end

local function takeAvailableHouse()
	table.sort(availableHouses, function(a, b)
		return (table.find(CASA_NAMES, a) or 999)
			< (table.find(CASA_NAMES, b) or 999)
	end)

	for index, casaName in ipairs(availableHouses) do
		local casaModel =
			CasaJugadorFolder:FindFirstChild(casaName)

		if casaModel and not houseIsOccupied(casaModel) then
			table.remove(availableHouses, index)
			return casaName, casaModel
		end
	end

	return nil, nil
end

for _, name in ipairs(CASA_NAMES) do
	local casa = CasaJugadorFolder:FindFirstChild(name)

	if casa then
		storeHouseDefaults(casa)
		table.insert(availableHouses, name)
	else
		warn("[HouseSystem] No se encontró la casa: " .. name)
	end
end

local function sortAvailableHouses()
	table.sort(availableHouses, function(a, b)
		return (table.find(CASA_NAMES, a) or 999)
			< (table.find(CASA_NAMES, b) or 999)
	end)
end

local function loadPlayerData(userId)
	if loadedData[userId] then
		return cloneTable(loadedData[userId])
	end

	local success, data = pcall(function()
		return HouseDataStore:GetAsync(
			"Player_" .. tostring(userId)
		)
	end)

	if not success then
		warn("[HouseSystem] No se pudieron cargar datos de casa para "
			.. tostring(userId))
	end

	loadedData[userId] =
		normalizeData(success and data or nil)

	return cloneTable(loadedData[userId])
end

-- Fuerza una lectura nueva al regresar desde el interior.
-- PlayerHouseCustomization_v3 se mezcla encima de HouseData_v1 porque
-- es donde HousePaintServer guarda primero los cambios interiores.
local function loadPlayerDataFresh(userId)
	local legacyOk, legacyData = pcall(function()
		return HouseDataStore:GetAsync(
			"Player_" .. tostring(userId)
		)
	end)

	local sharedOk, sharedData = pcall(function()
		return SharedCustomizationStore:GetAsync(
			"user_" .. tostring(userId)
		)
	end)

	local data = normalizeData(
		legacyOk and legacyData
			or loadedData[userId]
			or nil
	)

	if sharedOk then
		data = mergeSharedSurfaceData(data, sharedData)
	end

	loadedData[userId] = normalizeData(data)

	return cloneTable(loadedData[userId]),
		legacyOk or sharedOk
end

local function materialNameFromValue(value)
	local material = Enum.Material:FromValue(value)

	return material
		and material.Name
		or Enum.Material.SmoothPlastic.Name
end

local function writePlayerData(userId, data)
	local success, err = pcall(function()
		HouseDataStore:SetAsync(
			"Player_" .. tostring(userId),
			data
		)
	end)

	if not success then
		warn("[HouseSystem] Error guardando casa Player_"
			.. tostring(userId) .. ": " .. tostring(err))
	end

	pcall(function()
		SharedCustomizationStore:UpdateAsync(
			"user_" .. tostring(userId),
			function(current)
				current =
					type(current) == "table"
					and current
					or {}

				current.Surface =
					type(current.Surface) == "table"
					and current.Surface
					or {}

				for surface, config in pairs(SURFACES) do
					current.Surface[surface] = {
						Color = data[config.color],
						Material = materialNameFromValue(
							data[config.material]
						),
					}
				end

				current.Furniture = data.Furniture
				current.UpdatedAt = os.time()

				return current
			end
		)
	end)
end

local function queueSave(player, data, immediate)
	local userId = player.UserId

	loadedData[userId] = normalizeData(data)
	pendingSaves[userId] = loadedData[userId]

	if immediate then
		local toSave = pendingSaves[userId]
		pendingSaves[userId] = nil
		writePlayerData(userId, toSave)
		return
	end

	task.delay(8, function()
		if pendingSaves[userId] ~= loadedData[userId] then
			return
		end

		local toSave = pendingSaves[userId]
		pendingSaves[userId] = nil

		if toSave then
			writePlayerData(userId, toSave)
		end
	end)
end

local function applySurface(part, colorData, materialValue)
	if part:IsA("UnionOperation") then
		part.UsePartColor = true
	end

	part.Color = Color3.new(
		colorData.R,
		colorData.G,
		colorData.B
	)

	local material =
		Enum.Material:FromValue(materialValue)

	if material then
		part.Material = material
	end
end

local function hasHint(text, hints)
	for _, hint in ipairs(hints) do
		if text:find(hint, 1, true) then
			return true
		end
	end

	return false
end

local function getPaintSurface(part)
	if not part:IsA("BasePart")
		or part.Name == "MuroNegro"
	then
		return nil
	end

	local doorModel = part:FindFirstAncestor("Door")

	if doorModel then
		local exteriorFolder =
			doorModel:FindFirstChild("Puerta")

		local doorframe =
			exteriorFolder
			and exteriorFolder:FindFirstChild("Doorframe")

		local movingDoor =
			doorframe
			and doorframe:FindFirstChild("Puerta")

		local allowedUnion =
			movingDoor
			and movingDoor:FindFirstChild("Union")

		if part == movingDoor
			or part == allowedUnion
		then
			return "Puerta"
		end

		return nil
	end

	local parentName =
		part.Parent
		and part.Parent.Name:lower()
		or ""

	local text =
		part.Name:lower()
		.. " "
		.. parentName

	if hasHint(text, SURFACES.Techo.hints) then
		return "Techo"
	elseif hasHint(text, SURFACES.Interior.hints) then
		return "Interior"
	elseif hasHint(text, SURFACES.Piso.hints) then
		return "Piso"
	elseif hasHint(text, SURFACES.Pared.hints) then
		return "Pared"
	end

	return nil
end

local function applyHouseCustomization(casaModel, data)
	data = normalizeData(data)

	for _, part in ipairs(casaModel:GetDescendants()) do
		if part:IsA("BasePart") then
			local surface = getPaintSurface(part)

			if surface == "Techo" then
				applySurface(
					part,
					data.TechoColor,
					data.TechoMaterial
				)
			elseif surface == "Puerta" then
				applySurface(
					part,
					data.PuertaColor,
					data.PuertaMaterial
				)
			elseif surface == "Interior" then
				applySurface(
					part,
					data.InteriorColor,
					data.InteriorMaterial
				)
			elseif surface == "Piso" then
				applySurface(
					part,
					data.PisoColor,
					data.PisoMaterial
				)
			elseif surface == "Pared" then
				applySurface(
					part,
					data.ParedColor,
					data.ParedMaterial
				)
			end
		end
	end
end

local function getPlayerHouseModel(player)
	local casaName = playerHouseMap[player.UserId]

	return casaName
		and CasaJugadorFolder:FindFirstChild(casaName)
		or nil
end

local function setOwnerTags(casaModel, player)
	local ownerName =
		casaModel:FindFirstChild("OwnerName")
		or Instance.new("StringValue")

	ownerName.Name = "OwnerName"
	ownerName.Value = player.DisplayName
	ownerName.Parent = casaModel

	local ownerUsername =
		casaModel:FindFirstChild("OwnerUsername")
		or Instance.new("StringValue")

	ownerUsername.Name = "OwnerUsername"
	ownerUsername.Value = player.Name
	ownerUsername.Parent = casaModel

	local ownerUserId =
		casaModel:FindFirstChild("OwnerUserId")
		or Instance.new("IntValue")

	ownerUserId.Name = "OwnerUserId"
	ownerUserId.Value = player.UserId
	ownerUserId.Parent = casaModel
end

local function clearOwnerTags(casaModel)
	for _, tagName in ipairs({
		"OwnerName",
		"OwnerUsername",
		"OwnerUserId",
		}) do
		local tag = casaModel:FindFirstChild(tagName)

		if tag then
			tag:Destroy()
		end
	end
end

local function findPresenceHouseForPlayer(player)
	for _, casaName in ipairs(CASA_NAMES) do
		local casaModel =
			CasaJugadorFolder:FindFirstChild(casaName)

		if casaModel
			and tonumber(
				casaModel:GetAttribute("PresenceOwnerUserId")
			) == player.UserId
		then
			return casaName, casaModel
		end
	end

	return nil, nil
end

local function removeAvailableHouse(casaName)
	local index = table.find(availableHouses, casaName)

	if index then
		table.remove(availableHouses, index)
	end
end

local function claimRequestedReturnHouse(player, requestedName)
	if type(requestedName) ~= "string"
		or requestedName == ""
	then
		return nil
	end

	local house =
		CasaJugadorFolder:FindFirstChild(requestedName)

	if not house then
		return nil
	end

	local owner = house:FindFirstChild("OwnerUserId")
	local ownerId = owner and tonumber(owner.Value) or nil

	local presenceId = tonumber(
		house:GetAttribute("PresenceOwnerUserId")
	)

	if (ownerId and ownerId ~= player.UserId)
		or (presenceId and presenceId ~= player.UserId)
	then
		return nil
	end

	local wasReservedInThisServer =
		playerHouseMap[player.UserId] == requestedName
		or ownerId == player.UserId
		or presenceId == player.UserId

	removeAvailableHouse(requestedName)
	playerHouseMap[player.UserId] = requestedName
	retainedInteriorUsers[player.UserId] = nil

	-- Borra el caché viejo antes de leer los colores cambiados dentro.
	loadedData[player.UserId] = nil

	local data, freshRead =
		loadPlayerDataFresh(player.UserId)

	-- Si la casa ya permanecía visible en este mismo servidor,
	-- no la regresamos primero a blanco/default. Se conserva el aspecto
	-- actual y se reaplican los datos nuevos en cuanto estén disponibles.
	if not wasReservedInThisServer then
		restoreHouseDefaults(house)

		if freshRead then
			applyHouseCustomization(house, data)
		end
	end

	setOwnerTags(house, player)

	house:SetAttribute(
		"PresenceOwnerUserId",
		player.UserId
	)
	house:SetAttribute("PresenceOwnerOnline", true)
	house:SetAttribute("PresenceUpdatedAt", os.time())

	-- Segundo refresco para cubrir la pequeña carrera entre el guardado
	-- del interior y el regreso al exterior.
	task.delay(0.8, function()
		if not player.Parent then
			return
		end

		if playerHouseMap[player.UserId] ~= requestedName then
			return
		end

		local latestData, latestRead =
			loadPlayerDataFresh(player.UserId)

		if latestRead and house.Parent then
			applyHouseCustomization(house, latestData)

			SendHouseData:FireClient(
				player,
				latestData,
				requestedName
			)
		end
	end)

	writeHouseSession(player.UserId, {
		ExteriorHouseName = requestedName,
		ExteriorHouseNumber =
			tonumber(requestedName:match("(%d+)$")),
		ExteriorPlaceId = game.PlaceId,
		ExteriorJobId = game.JobId,
		State = "Exterior",
	})

	SendHouseData:FireClient(
		player,
		data,
		requestedName
	)

	print("[HouseSystem] " .. player.Name
		.. " recuperó " .. requestedName
		.. " con pintura actualizada.")

	return requestedName
end

local function assignHouse(player)
	local requestedName =
		requestedReturnHouse[player.UserId]

	if requestedName then
		local claimed =
			claimRequestedReturnHouse(
				player,
				requestedName
			)

		requestedReturnHouse[player.UserId] = nil

		if claimed then
			return claimed
		end
	end

	local existingName =
		playerHouseMap[player.UserId]

	if existingName then
		local existingHouse =
			CasaJugadorFolder:FindFirstChild(existingName)

		if existingHouse then
			local data = loadPlayerData(player.UserId)

			setOwnerTags(existingHouse, player)
			applyHouseCustomization(existingHouse, data)

			existingHouse:SetAttribute(
				"PresenceOwnerUserId",
				player.UserId
			)
			existingHouse:SetAttribute(
				"PresenceOwnerOnline",
				true
			)
			existingHouse:SetAttribute(
				"PresenceUpdatedAt",
				os.time()
			)

			SendHouseData:FireClient(
				player,
				data,
				existingName
			)

			return existingName
		end

		playerHouseMap[player.UserId] = nil
	end

	local presenceHouseName, presenceHouse =
		findPresenceHouseForPlayer(player)

	if presenceHouse then
		removeAvailableHouse(presenceHouseName)
		playerHouseMap[player.UserId] =
			presenceHouseName

		loadedData[player.UserId] = nil

		local data =
			loadPlayerDataFresh(player.UserId)

		applyHouseCustomization(presenceHouse, data)
		setOwnerTags(presenceHouse, player)

		presenceHouse:SetAttribute(
			"PresenceOwnerOnline",
			true
		)

		print("[HouseSystem] "
			.. player.Name
			.. " regresó a "
			.. presenceHouseName)

		SendHouseData:FireClient(
			player,
			data,
			presenceHouseName
		)

		return presenceHouseName
	end

	if #availableHouses == 0 then
		warn("[HouseSystem] No hay casas disponibles para "
			.. player.Name)

		SendHouseData:FireClient(
			player,
			loadPlayerData(player.UserId),
			""
		)

		return nil
	end

	local casaName, casaModel = takeAvailableHouse()

	if not casaModel then
		warn("[HouseSystem] No hay casas libres para "
			.. player.Name)

		SendHouseData:FireClient(
			player,
			loadPlayerData(player.UserId),
			""
		)

		return nil
	end

	playerHouseMap[player.UserId] = casaName

	local data = loadPlayerData(player.UserId)

	restoreHouseDefaults(casaModel)
	applyHouseCustomization(casaModel, data)
	setOwnerTags(casaModel, player)

	casaModel:SetAttribute(
		"PresenceOwnerUserId",
		player.UserId
	)
	casaModel:SetAttribute("PresenceOwnerOnline", true)
	casaModel:SetAttribute("PresenceUpdatedAt", os.time())

	writeHouseSession(player.UserId, {
		ExteriorHouseName = casaName,
		ExteriorHouseNumber =
			tonumber(casaName:match("(%d+)$")),
		ExteriorPlaceId = game.PlaceId,
		ExteriorJobId = game.JobId,
		State = "Exterior",
	})

	print("[HouseSystem] "
		.. player.Name
		.. " asignado a "
		.. casaName)

	SendHouseData:FireClient(
		player,
		data,
		casaName
	)

	return casaName
end

local function freeExteriorHouse(userId, reason)
	local casaName = playerHouseMap[userId]

	if not casaName then
		return
	end

	local casaModel =
		CasaJugadorFolder:FindFirstChild(casaName)

	playerHouseMap[userId] = nil
	loadedData[userId] = nil
	pendingSaves[userId] = nil
	retainedInteriorUsers[userId] = nil
	requestedReturnHouse[userId] = nil
	pendingReturnSpawn[userId] = nil

	if casaModel then
		clearOwnerTags(casaModel)
		restoreHouseDefaults(casaModel)

		casaModel:SetAttribute(
			"PresenceOwnerUserId",
			nil
		)
		casaModel:SetAttribute(
			"PresenceOwnerOnline",
			false
		)
		casaModel:SetAttribute(
			"PresenceUpdatedAt",
			os.time()
		)
	end

	if not table.find(availableHouses, casaName) then
		table.insert(availableHouses, casaName)
		sortAvailableHouses()
	end

	print("[HouseSystem] "
		.. casaName
		.. " liberada: "
		.. tostring(reason))
end

local function releaseHouse(player)
	local userId = player.UserId
	local casaName = playerHouseMap[userId]

	if not casaName then
		return
	end

	if pendingSaves[userId] then
		writePlayerData(
			userId,
			pendingSaves[userId]
		)
		pendingSaves[userId] = nil
	end

	-- Al entrar al Place interior se conserva la casa exterior.
	if player:GetAttribute("TravelingToInterior") == true then
		retainedInteriorUsers[userId] = true

		local casaModel =
			CasaJugadorFolder:FindFirstChild(casaName)

		if casaModel then
			casaModel:SetAttribute(
				"PresenceOwnerUserId",
				userId
			)
			casaModel:SetAttribute(
				"PresenceOwnerOnline",
				true
			)
			casaModel:SetAttribute(
				"PresenceUpdatedAt",
				os.time()
			)
		end

		print("[HouseSystem] "
			.. player.Name
			.. " entró al interior; "
			.. casaName
			.. " continúa ocupada.")

		return
	end

	removeHouseSession(userId)
	freeExteriorHouse(
		userId,
		"salió de CasaJugadores"
	)
end

-- Aviso inmediato enviado por InteriorSlotCoordinator cuando el jugador
-- cierra Roblox o sale al lobby desde AdentroCasaJugadores.
local subscribed, subscribeError = pcall(function()
	MessagingService:SubscribeAsync(
		HOUSE_RELEASE_CHANNEL,
		function(message)
			local data = message.Data

			if type(data) ~= "table"
				or data.Action ~= "ReleaseExterior"
			then
				return
			end

			local userId = tonumber(data.UserId)
			local exteriorJobId =
				tostring(data.ExteriorJobId or "")

			if not userId
				or exteriorJobId ~= game.JobId
			then
				return
			end

			local expectedHouse =
				tostring(data.ExteriorHouseName or "")

			local currentHouse =
				playerHouseMap[userId]

			if currentHouse
				and expectedHouse ~= ""
				and currentHouse ~= expectedHouse
			then
				return
			end

			removeHouseSession(userId)

			freeExteriorHouse(
				userId,
				data.Reason
					or "salió del interior"
			)
		end
	)
end)

if not subscribed then
	warn("[HouseSystem] No se pudo escuchar "
		.. HOUSE_RELEASE_CHANNEL
		.. ": "
		.. tostring(subscribeError))
end

ApplyCustomization.OnServerEvent:Connect(
	function(player, customData)
		local casaModel = getPlayerHouseModel(player)

		if not casaModel then
			assignHouse(player)
			casaModel = getPlayerHouseModel(player)
		end

		if not casaModel then
			return
		end

		local data = normalizeData(customData)

		applyHouseCustomization(casaModel, data)
		queueSave(player, data, false)

		SendHouseData:FireClient(
			player,
			data,
			playerHouseMap[player.UserId] or ""
		)

		print("[HouseSystem] Personalización actualizada para "
			.. player.Name)
	end
)

RequestHouseData.OnServerEvent:Connect(
	function(player)
		if not playerHouseMap[player.UserId] then
			assignHouse(player)
			return
		end

		SendHouseData:FireClient(
			player,
			loadPlayerData(player.UserId),
			playerHouseMap[player.UserId] or ""
		)
	end
)

local function readReturnData(player)
	local joinData = player:GetJoinData()

	local data =
		type(joinData) == "table"
		and joinData.TeleportData
		or nil

	if type(data) ~= "table"
		or data.Route ~= "InteriorToExterior"
	then
		return nil
	end

	if tonumber(data.OwnerUserId) ~= player.UserId then
		return nil
	end

	return data
end

local function moveToReturnSpawn(player, casaName)
	local house =
		CasaJugadorFolder:FindFirstChild(casaName)

	local returnSpawn =
		house
		and house:FindFirstChild("Door")
		and house.Door:FindFirstChild("ReturnSpawn")

	if not returnSpawn
		or not returnSpawn:IsA("BasePart")
	then
		warn("[HouseSystem] Falta "
			.. casaName
			.. " > Door > ReturnSpawn")
		return
	end

	local character =
		player.Character
		or player.CharacterAdded:Wait()

	task.wait(0.8)

	for _ = 1, 5 do
		if not character.Parent then
			return
		end

		character:PivotTo(
			returnSpawn.CFrame
				* CFrame.new(0, 3, 0)
		)

		task.wait(0.3)
	end
end

local function setupPlayer(player)
	local returnData = readReturnData(player)

	if returnData then
		local expectedName =
			tostring(
				returnData.ExteriorHouseName
				or ""
			)

		if expectedName ~= "" then
			requestedReturnHouse[player.UserId] =
				expectedName

			pendingReturnSpawn[player.UserId] = true

			-- Impide reutilizar los colores guardados en caché
			-- antes de entrar al interior.
			loadedData[player.UserId] = nil
		end
	end

	local casaName = assignHouse(player)

	if not casaName then
		return
	end

	writeHouseSession(player.UserId, {
		ExteriorHouseName = casaName,
		ExteriorHouseNumber =
			tonumber(casaName:match("(%d+)$")),
		ExteriorPlaceId = game.PlaceId,
		ExteriorJobId = game.JobId,
		State = "Exterior",
	})

	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		assignHouse(player)

		if pendingReturnSpawn[player.UserId] then
			pendingReturnSpawn[player.UserId] = nil

			task.spawn(
				moveToReturnSpawn,
				player,
				playerHouseMap[player.UserId]
			)
		end
	end)

	if returnData then
		task.spawn(function()
			local character =
				player.Character
				or player.CharacterAdded:Wait()

			if character
				and pendingReturnSpawn[player.UserId]
			then
				pendingReturnSpawn[player.UserId] = nil
				moveToReturnSpawn(
					player,
					casaName
				)
			end
		end)
	end
end

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(releaseHouse)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end

-- Respaldo: si MessagingService falla, la casa se libera cuando
-- desaparezca la sesión del interior.
task.spawn(function()
	while task.wait(SESSION_CHECK_INTERVAL) do
		for userId in pairs(retainedInteriorUsers) do
			local session = readHouseSession(userId)
			local casaName = playerHouseMap[userId]

			local valid =
				session
				and casaName
				and tostring(
					session.ExteriorJobId or ""
				) == game.JobId
				and tostring(
					session.ExteriorHouseName or ""
				) == casaName
				and (
					session.State == "TravelingInterior"
					or session.State == "Interior"
					or session.State == "ReturningExterior"
				)

			if not valid then
				freeExteriorHouse(
					userId,
					"sesión interior terminada"
				)
			end
		end
	end
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		if pendingSaves[player.UserId] then
			writePlayerData(
				player.UserId,
				pendingSaves[player.UserId]
			)
		end
	end
end)

print("[HouseSystem] V4.7 iniciado. Casas disponibles: "
	.. #availableHouses
	.. " / "
	.. #CASA_NAMES)