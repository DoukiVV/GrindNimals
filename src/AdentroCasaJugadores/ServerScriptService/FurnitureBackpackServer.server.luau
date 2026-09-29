--============================================================
-- FURNITURE BACKPACK SERVER V2
--
-- UBICACION:
-- AdentroCasaJugadores > ServerScriptService > FurnitureBackpackServer
-- Tipo: Script
--
-- DATASTORE:
-- FurnitureBackpack_v1   (MISMO DE ANTES)
--
-- FUNCIONES:
-- - comprar un mueble y guardarlo sin colocarlo
-- - consultar inventario
-- - sincronizar UI
-- - bridge servidor-servidor para HouseInteriorServer:
--      Add
--      Remove
--      GetAmount
--
-- NO crea RemoteEvents falsos dentro de HouseCustomizationRemotes.
-- HouseInteriorServer V6.7 crea y controla:
-- StorePlacedFurniture
-- PlaceInventoryFurniture
--============================================================

local Players =
	game:GetService("Players")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local ServerStorage =
	game:GetService("ServerStorage")

local DataStoreService =
	game:GetService("DataStoreService")

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


local FurnitureCatalog =
	require(
		ReplicatedStorage:WaitForChild(
			"FurnitureCatalog"
		)
	)

local store =
	DataStoreService:GetDataStore(
		"FurnitureBackpack_v1"
	)

--============================================================
-- REMOTES DE LA MOCHILA
--============================================================

local remotes =
	ReplicatedStorage:FindFirstChild(
		"FurnitureBackpackRemotes"
	)

if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "FurnitureBackpackRemotes"
	remotes.Parent = ReplicatedStorage
end

local function ensureRemote(
	className,
	name
)
	local object =
		remotes:FindFirstChild(name)

	if object
		and object.ClassName ~= className then

		object:Destroy()
		object = nil
	end

	if not object then
		object = Instance.new(className)
		object.Name = name
		object.Parent = remotes
	end

	return object
end

local requestStore =
	ensureRemote(
		"RemoteFunction",
		"RequestStoreFurniture"
	)

local inventoryUpdated =
	ensureRemote(
		"RemoteEvent",
		"FurnitureInventoryUpdated"
	)

local getInventory =
	ensureRemote(
		"RemoteFunction",
		"GetFurnitureInventory"
	)

--============================================================
-- BRIDGE SERVIDOR -> SERVIDOR
--============================================================

local bridge =
	ServerStorage:FindFirstChild(
		"FurnitureBackpackBridge"
	)

if bridge
	and not bridge:IsA("BindableFunction") then

	bridge:Destroy()
	bridge = nil
end

if not bridge then
	bridge = Instance.new("BindableFunction")
	bridge.Name = "FurnitureBackpackBridge"
	bridge.Parent = ServerStorage
end

--============================================================
-- ESTADO
--============================================================

local inventories = {}
local busy = {}
local loaded = {}

local function copyInventory(source)
	local result = {}

	for name, amount in pairs(
		source or {}
		) do
		result[name] =
			math.max(
				0,
				math.floor(
					tonumber(amount) or 0
				)
			)
	end

	return result
end

local function cleanInventory(raw)
	local result = {}

	if typeof(raw) ~= "table" then
		return result
	end

	for furnitureName, amount in pairs(raw) do
		if FurnitureCatalog[furnitureName]
			and typeof(amount) == "number" then

			local cleanAmount =
				math.max(
					0,
					math.floor(amount)
				)

			if cleanAmount > 0 then
				result[furnitureName] =
					cleanAmount
			end
		end
	end

	return result
end

local function fireInventory(player)
	if player
		and player.Parent == Players then

		inventoryUpdated:FireClient(
			player,
			cleanInventory(
				inventories[player]
			)
		)
	end
end

local function loadPlayer(player)
	if loaded[player] then
		return true
	end

	local saved = nil

	local success, err =
		pcall(function()
			saved =
			store:GetAsync(
				"user_"
				.. player.UserId
			)
		end)

	if not success then
		warn(
			"[FurnitureBackpack] Error cargando "
				.. player.Name
				.. ": "
				.. tostring(err)
		)

		inventories[player] =
			inventories[player]
			or {}

		return false
	end

	inventories[player] =
		cleanInventory(saved)

	loaded[player] = true
	fireInventory(player)

	return true
end

local function ensureLoaded(player)
	if loaded[player] then
		return true
	end

	return loadPlayer(player)
end

local function saveSnapshot(
	player,
	snapshot
)
	local success, err =
		pcall(function()
			store:UpdateAsync(
				"user_"
				.. player.UserId,
				function()
					return cleanInventory(
						snapshot
					)
				end
			)
		end)

	if not success then
		warn(
			"[FurnitureBackpack] Error guardando "
				.. player.Name
				.. ": "
				.. tostring(err)
		)
	end

	return success
end

local function savePlayer(player)
	if not loaded[player] then
		return true
	end

	return saveSnapshot(
		player,
		inventories[player]
			or {}
	)
end

local function findMoneyValue(player)
	local possibleContainers = {
		player:FindFirstChild("leaderstats"),
		player:FindFirstChild("Stats"),
		player:FindFirstChild("Data"),
		player,
	}

	local possibleNames = {
		"Dolares",
		"Dólares",
		"Dinero",
		"Money",
		"Cash",
		"Dollars",
		"Monedas",
	}

	for _, container in ipairs(
		possibleContainers
		) do
		if container then
			for _, valueName in ipairs(
				possibleNames
				) do
				local value =
					container:FindFirstChild(
						valueName
					)

				if value
					and (
						value:IsA("IntValue")
							or value:IsA("NumberValue")
					) then

					return value
				end
			end
		end
	end

	return nil
end

local function mutateAndSave(
	player,
	mutator
)
	if busy[player] then
		return false,
			"Espera un momento."
	end

	if not ensureLoaded(player) then
		return false,
			"No se pudo cargar tu mochila de muebles."
	end

	busy[player] = true

	local previous =
		copyInventory(
			inventories[player]
		)

	local working =
		copyInventory(previous)

	local okMutate,
		success,
		message,
		value =
		pcall(
			mutator,
			working
		)

	if not okMutate then
		busy[player] = nil

		warn(
			"[FurnitureBackpack] Mutación falló: "
				.. tostring(success)
		)

		return false,
			"No se pudo actualizar la mochila."
	end

	if success ~= true then
		busy[player] = nil
		return false,
			message
	end

	if not saveSnapshot(
		player,
		working
		) then
		busy[player] = nil
		return false,
			"No se pudo guardar el inventario."
	end

	inventories[player] =
		cleanInventory(
			working
		)

	fireInventory(player)

	busy[player] = nil

	return true,
		message,
		value
end

--============================================================
-- BRIDGE
--============================================================

bridge.OnInvoke =
	function(
		action,
		player,
		furnitureName,
		amount
	)
	if not player
		or not player:IsA("Player")
		or player.Parent ~= Players then

		return false,
			"Jugador inválido."
	end

	action =
		tostring(action or "")

	furnitureName =
		tostring(
			furnitureName or ""
		)

	amount =
		math.max(
			1,
			math.floor(
				tonumber(amount) or 1
			)
		)

	if action == "GetAmount" then
		if not ensureLoaded(player) then
			return false, 0
		end

		return true,
			math.max(
				0,
				math.floor(
					tonumber(
						(inventories[player] or {})[
						furnitureName
						]
					) or 0
				)
			)
	end

	if not FurnitureCatalog[
		furnitureName
		] then
		return false,
			"Ese mueble no existe en FurnitureCatalog."
	end

	if action == "Add" then
		return mutateAndSave(
			player,
			function(inventory)
				inventory[furnitureName] =
					(inventory[furnitureName] or 0)
					+ amount

				return true,
				"Guardado.",
				inventory[furnitureName]
			end
		)
	end

	if action == "Remove" then
		return mutateAndSave(
			player,
			function(inventory)
				local current =
					math.max(
						0,
						math.floor(
							tonumber(
								inventory[
								furnitureName
								]
							) or 0
						)
					)

				if current < amount then
					return false,
					"No tienes suficientes unidades."
				end

				local left =
					current - amount

				if left > 0 then
					inventory[
					furnitureName
					] = left
				else
					inventory[
					furnitureName
					] = nil
				end

				return true,
				"Usado.",
				left
			end
		)
	end

	return false,
		"Acción de bridge desconocida."
end

--============================================================
-- COMPRA DIRECTA A BACKPACK
--============================================================

requestStore.OnServerInvoke =
	function(
		player,
		furnitureName
	)
	if typeof(furnitureName)
		~= "string" then

		return false,
			"Mueble inválido."
	end

	local price =
		FurnitureCatalog[
	furnitureName
	]

	if not price then
		return false,
			"Este mueble no existe en el catálogo."
	end

	if busy[player] then
		return false,
			"Espera un momento."
	end

	local moneyValue =
		findMoneyValue(player)

	if not moneyValue then
		return false,
			"No se encontró la moneda del jugador."
	end

	if moneyValue.Value < price then
		return false,
			"No tienes suficiente dinero."
	end

	local oldMoney =
		moneyValue.Value

	moneyValue.Value =
		oldMoney - price

	local success,
		message =
		mutateAndSave(
			player,
			function(inventory)
				inventory[furnitureName] =
				(inventory[furnitureName] or 0)
				+ 1

				return true,
				"Guardaste "
				.. furnitureName
				.. " en la mochila."
			end
		)

	if not success then
		moneyValue.Value =
			oldMoney

		return false,
			message
			or "No se pudo guardar la compra. Tu dinero fue devuelto."
	end

	-- Compra real completada: da XP una sola vez.
	awardGameActionXP(player, "BuyFurniture", 3)

	return true,
		message,
		cleanInventory(
			inventories[player]
		)
end

getInventory.OnServerInvoke =
	function(player)
		ensureLoaded(player)

		return cleanInventory(
			inventories[player]
		)
	end

--============================================================
-- JUGADORES
--============================================================

Players.PlayerAdded:Connect(
	function(player)
		task.spawn(
			loadPlayer,
			player
		)
	end
)

for _, player in ipairs(
	Players:GetPlayers()
	) do
	task.spawn(
		loadPlayer,
		player
	)
end

Players.PlayerRemoving:Connect(
	function(player)
		savePlayer(player)

		inventories[player] = nil
		busy[player] = nil
		loaded[player] = nil
	end
)

game:BindToClose(function()
	local pending = 0

	for _, player in ipairs(
		Players:GetPlayers()
		) do
		pending += 1

		task.spawn(function()
			savePlayer(player)
			pending -= 1
		end)
	end

	local started =
		os.clock()

	while pending > 0
		and os.clock() - started < 6 do

		task.wait(0.05)
	end
end)

print(
	"[FurnitureBackpack] V2 activo | "
		.. "DataStore + bridge de casa."
)
