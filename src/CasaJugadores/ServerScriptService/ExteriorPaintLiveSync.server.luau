-- ============================================================
-- EXTERIOR DOOR PAINT SYNC V5
-- Tipo: Script
-- Ubicación: CasaJugadores > ServerScriptService > ExteriorPaintLiveSync
--
-- Corrige la pintura de la puerta frontal visible en CasaJugadores.
-- Funciona tanto cuando:
-- 1) El jugador pinta desde el botón de CasaJugadores.
-- 2) El jugador pinta desde AdentroCasaJugadores.
-- 3) La casa se vuelve a asignar/cargar desde DataStore.
--
-- Pinta únicamente la hoja de la puerta:
-- Door > Puerta > Doorframe > Puerta y su Union.
-- No pinta marcos, bisagras, MuroNegro ni piezas auxiliares.
-- ============================================================

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MessagingService = game:GetService("MessagingService")
local DataStoreService = game:GetService("DataStoreService")

local CasaJugadorFolder = Workspace:WaitForChild("Casa Jugador")
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local ApplyCustomization = RemoteEvents:WaitForChild("ApplyCustomization")

local HouseDataStore = DataStoreService:GetDataStore("HouseData_v1")
local SharedCustomizationStore =
	DataStoreService:GetDataStore("PlayerHouseCustomization_v3")

local HOUSE_PAINT_CHANNEL = "HousePaintUpdated_v4"

local MATERIALS_BY_LABEL = {
	Concreto = Enum.Material.Concrete,
	Ladrillo = Enum.Material.Brick,
	Madera = Enum.Material.Wood,
	Piedra = Enum.Material.Slate,
	Liso = Enum.Material.SmoothPlastic,
	Metal = Enum.Material.Metal,
	Marmol = Enum.Material.Marble,
	Tejas = Enum.Material.RoofShingles,
}

local function colorFromTable(value)
	if type(value) ~= "table" then
		return nil
	end

	local r = tonumber(value.R)
	local g = tonumber(value.G)
	local b = tonumber(value.B)

	if not r or not g or not b then
		return nil
	end

	return Color3.new(
		math.clamp(r, 0, 1),
		math.clamp(g, 0, 1),
		math.clamp(b, 0, 1)
	)
end

local function materialFromValue(value)
	local numeric = tonumber(value)
	if not numeric then
		return nil
	end

	return Enum.Material:FromValue(numeric)
end

local function materialFromStoredValue(value)
	if type(value) == "string" then
		return MATERIALS_BY_LABEL[value] or Enum.Material[value]
	end

	return materialFromValue(value)
end

local function hasAncestorNamed(instance, targetName, stopAt)
	local current = instance.Parent

	while current and current ~= stopAt do
		if current.Name == targetName then
			return true
		end
		current = current.Parent
	end

	return false
end

local function isExteriorDoorLeafPart(part, house)
	if not part:IsA("BasePart") then
		return false
	end

	if part.Name == "MuroNegro" then
		return false
	end

	-- Solo revisar la puerta frontal exterior de CasaJugadores.
	if not hasAncestorNamed(part, "Door", house) then
		return false
	end

	-- Union visible dentro de:
	-- Door > Puerta > Doorframe > Puerta > Union
	if part.Name == "Union"
		and hasAncestorNamed(part, "Doorframe", house)
		and hasAncestorNamed(part, "Puerta", house)
	then
		return true
	end

	-- Algunas casas muestran también un BasePart llamado "Puerta".
	if part.Name == "Puerta"
		and hasAncestorNamed(part, "Doorframe", house)
	then
		return true
	end

	return false
end

local function ownerUserIdOfHouse(house)
	local ownerValue = house:FindFirstChild("OwnerUserId")

	if ownerValue and ownerValue:IsA("ValueBase") then
		local value = tonumber(ownerValue.Value)
		if value and value > 0 then
			return value
		end
	end

	local presenceOwner =
		tonumber(house:GetAttribute("PresenceOwnerUserId"))

	if presenceOwner and presenceOwner > 0 then
		return presenceOwner
	end

	return nil
end

local function findHouseByOwnerUserId(userId)
	for _, house in ipairs(CasaJugadorFolder:GetChildren()) do
		if house:IsA("Model")
			and ownerUserIdOfHouse(house) == userId
		then
			return house
		end
	end

	return nil
end

local function applyDoorPaint(house, color, material, source)
	if not house or not color or not material then
		return 0
	end

	local changed = 0

	for _, object in ipairs(house:GetDescendants()) do
		if object:IsA("BasePart")
			and isExteriorDoorLeafPart(object, house)
		then
			if object:IsA("UnionOperation") then
				object.UsePartColor = true
			end

			object.Color = color
			object.Material = material
			changed += 1
		end
	end

	if changed > 0 then
		print(string.format(
			"[ExteriorDoorPaint] %s pintó %d pieza(s) de puerta en %s",
			tostring(source or "Actualización"),
			changed,
			house.Name
			))
	else
		warn(string.format(
			"[ExteriorDoorPaint] No encontré la hoja de la puerta en %s. "
				.. "Revisa la ruta Door > Puerta > Doorframe > Puerta > Union.",
			house.Name
			))
	end

	return changed
end

local function applyDoorFromExteriorData(player, data)
	if type(data) ~= "table" then
		return
	end

	local color = colorFromTable(data.PuertaColor)
	local material = materialFromValue(data.PuertaMaterial)

	if not color or not material then
		return
	end

	local house = findHouseByOwnerUserId(player.UserId)
	if not house then
		warn("[ExteriorDoorPaint] No encontré la casa exterior de "
			.. player.Name)
		return
	end

	applyDoorPaint(house, color, material, "CasaJugadores")
end

-- El botón exterior usa RemoteEvents.ApplyCustomization.
ApplyCustomization.OnServerEvent:Connect(function(player, data)
	applyDoorFromExteriorData(player, data)
end)

local function applyInteriorMessage(data)
	if type(data) ~= "table"
		or tostring(data.Surface or "") ~= "Puerta"
	then
		return
	end

	local userId = tonumber(data.UserId)
	local color = colorFromTable(data.Color)
	local material =
		MATERIALS_BY_LABEL[tostring(data.Material or "")]

	if not userId or not color or not material then
		return
	end

	local house = findHouseByOwnerUserId(userId)
	if not house then
		-- El jugador puede estar entrando y la casa todavía no tiene OwnerUserId.
		task.delay(1, function()
			local delayedHouse = findHouseByOwnerUserId(userId)
			if delayedHouse then
				applyDoorPaint(
					delayedHouse,
					color,
					material,
					"AdentroCasaJugadores"
				)
			end
		end)
		return
	end

	applyDoorPaint(
		house,
		color,
		material,
		"AdentroCasaJugadores"
	)
end

-- Los cambios hechos en AdentroCasaJugadores llegan por MessagingService.
local subscribed, subscribeError = pcall(function()
	MessagingService:SubscribeAsync(
		HOUSE_PAINT_CHANNEL,
		function(message)
			applyInteriorMessage(message.Data)
		end
	)
end)

if not subscribed then
	warn("[ExteriorDoorPaint] No se pudo escuchar "
		.. HOUSE_PAINT_CHANNEL .. ": " .. tostring(subscribeError))
end

local function readStoredDoor(userId)
	local legacyOk, legacyData = pcall(function()
		return HouseDataStore:GetAsync("Player_" .. tostring(userId))
	end)

	if legacyOk and type(legacyData) == "table" then
		local color = colorFromTable(legacyData.PuertaColor)
		local material =
			materialFromStoredValue(legacyData.PuertaMaterial)

		if color and material then
			return color, material
		end
	end

	local sharedOk, sharedData = pcall(function()
		return SharedCustomizationStore:GetAsync(
			"user_" .. tostring(userId)
		)
	end)

	if sharedOk
		and type(sharedData) == "table"
		and type(sharedData.Surface) == "table"
		and type(sharedData.Surface.Puerta) == "table"
	then
		local entry = sharedData.Surface.Puerta
		local color = colorFromTable(entry.Color)
		local material = materialFromStoredValue(entry.Material)

		if color and material then
			return color, material
		end
	end

	return nil, nil
end

local function restorePlayerDoor(player)
	local started = os.clock()
	local house = findHouseByOwnerUserId(player.UserId)

	while player.Parent
		and not house
		and os.clock() - started < 20
	do
		task.wait(0.25)
		house = findHouseByOwnerUserId(player.UserId)
	end

	if not house then
		return
	end

	local color, material = readStoredDoor(player.UserId)
	if color and material then
		applyDoorPaint(house, color, material, "Datos guardados")
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(restorePlayerDoor, player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(restorePlayerDoor, player)
end

print("[ExteriorDoorPaint] V5 listo: botón exterior + sincronización interior.")