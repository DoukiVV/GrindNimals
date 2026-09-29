--============================================================
-- SHARED PLAYER PROGRESS SERVER V3
--
-- TIPO:
-- Script
--
-- PONER EN:
-- 1) CasaJugadores
-- 2) AdentroCasaJugadores
--
-- NO ponerlo en Lobby si ahi ya tienes:
-- - GranjaMoneyServer
-- - GranjaLevelServer
-- - DailyLoginServer / sistema de diamantes
--
-- DATASTORES COMPARTIDOS:
-- Dolares   -> PlayerDollarsV1
-- Nivel/XP  -> PlayerLevelV2
-- Diamantes -> PlayerDiamondsV1
--
-- V2:
-- 1) Ya NO muestra "Subiste de nivel" al entrar/cargar datos.
-- 2) Crea AwardPlayerXP para que otros sistemas den XP.
-- 3) Crea AwardGameAction para dar XP por acciones del juego.
-- 4) Solo muestra la alerta cuando realmente ganas suficiente XP.
-- 5) Mantiene el mismo nivel/XP/dinero/diamantes entre mundos.
--============================================================

local Players =
	game:GetService("Players")

local DataStoreService =
	game:GetService("DataStoreService")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

------------------------------------------------------------
-- DATASTORES
------------------------------------------------------------

local DOLLAR_STORE =
	DataStoreService:GetDataStore(
		"PlayerDollarsV1"
	)

local LEVEL_STORE =
	DataStoreService:GetDataStore(
		"PlayerLevelV2"
	)

local LEGACY_LEVEL_STORE =
	DataStoreService:GetDataStore(
		"PlayerLevelV1"
	)

local DIAMOND_STORE =
	DataStoreService:GetDataStore(
		"PlayerDiamondsV1"
	)

------------------------------------------------------------
-- LIMITES
------------------------------------------------------------

local MAX_DOLLARS = 999999999999999
local MAX_LEVEL = 999999
local MAX_DIAMONDS = 999999999

local SAVE_DELAY = 2
local AUTOSAVE_SECONDS = 90

------------------------------------------------------------
-- EVENTOS
------------------------------------------------------------

local LEVEL_NOTICE_NAME =
	"AdminLevelUpNotice"

local XP_EVENT_NAME =
	"AwardPlayerXP"

local ACTION_EVENT_NAME =
	"AwardGameAction"

local function ensureRemoteEvent(name)
	local object =
		ReplicatedStorage:FindFirstChild(name)

	if object
		and not object:IsA("RemoteEvent")
	then
		object:Destroy()
		object = nil
	end

	if not object then
		object = Instance.new("RemoteEvent")
		object.Name = name
		object.Parent = ReplicatedStorage
	end

	return object
end

local function ensureBindableEvent(name)
	local object =
		ReplicatedStorage:FindFirstChild(name)

	if object
		and not object:IsA("BindableEvent")
	then
		object:Destroy()
		object = nil
	end

	if not object then
		object = Instance.new("BindableEvent")
		object.Name = name
		object.Parent = ReplicatedStorage
	end

	return object
end

local levelNotice =
	ensureRemoteEvent(
		LEVEL_NOTICE_NAME
	)

local awardXPEvent =
	ensureBindableEvent(
		XP_EVENT_NAME
	)

local awardGameAction =
	ensureBindableEvent(
		ACTION_EVENT_NAME
	)

------------------------------------------------------------
-- XP POR ACCIONES DEL JUEGO
--
-- Estas cantidades son faciles de modificar.
--
-- Para usarlo desde OTRO SCRIPT DEL SERVIDOR:
--
-- local AwardGameAction =
--     game.ReplicatedStorage:WaitForChild("AwardGameAction")
--
-- AwardGameAction:Fire(player, "PlantCrop")
------------------------------------------------------------

local ACTION_XP = {
	-- Granja / jardin
	PlantCrop = 4,
	HarvestCrop = 8,
	HarvestTreeFruit = 10,
	BuyGardenPlot = 20,

	-- Bosque
	ChopTree = 15,

	-- Mascotas
	HatchEgg = 25,
	PetUpgrade = 40,

	-- Trade
	CompleteTrade = 15,

	-- Casa
	BuyFurniture = 3,
}

-- Evita XP infinito por spam accidental.
local ACTION_COOLDOWN = {
	PlantCrop = 0.75,
	HarvestCrop = 0.40,
	HarvestTreeFruit = 0.40,
	BuyGardenPlot = 3,
	ChopTree = 1.5,
	HatchEgg = 2,
	PetUpgrade = 2,
	CompleteTrade = 300, -- 5 min, evita farmear trades vacíos/repetidos
	BuyFurniture = 0.75,
}

------------------------------------------------------------
-- RUNTIME
------------------------------------------------------------

local runtime = {}
local actionRuntime = {}

------------------------------------------------------------
-- LEADERSTATS
------------------------------------------------------------

local function getLeaderstats(player)
	local folder =
		player:FindFirstChild(
			"leaderstats"
		)

	if folder
		and not folder:IsA("Folder")
	then
		folder:Destroy()
		folder = nil
	end

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
	end

	return folder
end

local function numericValue(
	parent,
	name,
	defaultValue
)
	local value =
		parent:FindFirstChild(name)

	if value
		and not (
			value:IsA("IntValue")
				or value:IsA("NumberValue")
		)
	then
		value:Destroy()
		value = nil
	end

	if not value then
		value = Instance.new("IntValue")
		value.Name = name
		value.Value = defaultValue
		value.Parent = parent
	end

	return value
end

------------------------------------------------------------
-- XP NECESARIA
------------------------------------------------------------

local function xpNeeded(level)
	level =
		math.clamp(
			math.floor(
				tonumber(level) or 1
			),
			1,
			MAX_LEVEL
		)

	return
		100
		+ (level - 1) * 50
end

------------------------------------------------------------
-- DATASTORE
------------------------------------------------------------

local function readStore(store, key)
	local ok, result =
		pcall(function()
			return store:GetAsync(key)
		end)

	return ok, result
end

local function loadLevel(userId)
	local key =
		tostring(userId)

	local ok, saved =
		readStore(
			LEVEL_STORE,
			key
		)

	if ok then
		if type(saved) == "table" then
			return
				math.clamp(
					math.floor(
						tonumber(saved.level)
						or 1
					),
					1,
					MAX_LEVEL
				),
				math.max(
					0,
					math.floor(
						tonumber(saved.xp)
						or 0
					)
				)

		elseif typeof(saved) == "number" then
			return
				math.clamp(
					math.floor(saved),
					1,
					MAX_LEVEL
				),
				0
		end
	end

	local legacyOk,
		legacy =
		readStore(
			LEGACY_LEVEL_STORE,
			key
		)

	if legacyOk
		and typeof(legacy)
		== "number"
	then
		return
			math.clamp(
				math.floor(legacy),
				1,
				MAX_LEVEL
			),
			0
	end

	return 1, 0
end

------------------------------------------------------------
-- ATRIBUTOS
------------------------------------------------------------

local function updateLevelAttributes(
	player,
	levelValue,
	xpValue
)
	player:SetAttribute(
		"PlayerLevel",
		levelValue.Value
	)

	player:SetAttribute(
		"PlayerXP",
		xpValue.Value
	)

	player:SetAttribute(
		"PlayerXPNeeded",
		xpNeeded(
			levelValue.Value
		)
	)
end

------------------------------------------------------------
-- GUARDADO DIFERIDO
------------------------------------------------------------

local savePlayer

local function markDirty(player)
	local state =
		runtime[player]

	if not state
		or not state.loaded
	then
		return
	end

	state.dirty = true
	state.saveToken += 1

	local token =
		state.saveToken

	task.delay(
		SAVE_DELAY,
		function()
			local current =
				runtime[player]

			if not current
				or not current.loaded
				or current.saveToken ~= token
				or player.Parent ~= Players
			then
				return
			end

			current._requestSave = true
		end
	)
end

------------------------------------------------------------
-- SUBIR XP
------------------------------------------------------------

local function awardXP(
	player,
	amount,
	reason
)
	local state =
		runtime[player]

	if not state
		or not state.loaded
		or not state.values
	then
		return false
	end

	amount =
		math.floor(
			tonumber(amount) or 0
		)

	if amount <= 0 then
		return false
	end

	local levelValue =
		state.values.level

	local xpValue =
		state.values.xp

	local oldLevel =
		levelValue.Value

	xpValue.Value += amount

	while levelValue.Value < MAX_LEVEL do
		local needed =
			xpNeeded(
				levelValue.Value
			)

		if xpValue.Value < needed then
			break
		end

		xpValue.Value -= needed
		levelValue.Value += 1
	end

	updateLevelAttributes(
		player,
		levelValue,
		xpValue
	)

	markDirty(player)

	-- CRITICO:
	-- La alerta SOLO se dispara aqui, despues de ganar XP.
	-- Cargar el nivel guardado al entrar NO llama este bloque.
	if levelValue.Value > oldLevel then
		levelNotice:FireClient(
			player,
			levelValue.Value
		)
	end

	if reason then
		player:SetAttribute(
			"LastXPReason",
			tostring(reason)
		)
	end

	return true
end

awardXPEvent.Event:Connect(
	function(player, amount, reason)
		awardXP(
			player,
			amount,
			reason or "Sistema"
		)
	end
)

------------------------------------------------------------
-- XP POR ACCION
------------------------------------------------------------

local function awardAction(
	player,
	actionName,
	multiplier
)
	if not player
		or player.Parent ~= Players
	then
		return
	end

	actionName =
		tostring(
			actionName or ""
		)

	local baseXP =
		ACTION_XP[actionName]

	if not baseXP then
		warn(
			"[SharedProgress] Accion XP desconocida: "
				.. actionName
		)
		return
	end

	local playerActions =
		actionRuntime[player]

	if not playerActions then
		playerActions = {}
		actionRuntime[player] = playerActions
	end

	local now =
		os.clock()

	local nextAllowed =
		playerActions[actionName]
		or 0

	if now < nextAllowed then
		return
	end

	playerActions[actionName] =
		now
		+ (
			ACTION_COOLDOWN[actionName]
			or 0
		)

	multiplier =
		math.clamp(
			math.floor(
				tonumber(multiplier)
				or 1
			),
			1,
			10
		)

	awardXP(
		player,
		baseXP * multiplier,
		actionName
	)
end

awardGameAction.Event:Connect(
	awardAction
)

------------------------------------------------------------
-- CARGAR JUGADOR
------------------------------------------------------------

local function loadPlayer(player)
	if runtime[player] then
		return
	end

	local state = {
		loaded = false,
		saveToken = 0,
		dirty = false,
		connections = {},
	}

	runtime[player] = state

	-- Mientras cargamos:
	-- cualquier cliente puede saber que NO debe anunciar niveles.
	player:SetAttribute(
		"SharedProgressLoaded",
		false
	)

	player:SetAttribute(
		"SuppressLevelUpNotice",
		true
	)

	local leaderstats =
		getLeaderstats(player)

	local dollars =
		numericValue(
			leaderstats,
			"Dolares",
			0
		)

	local level =
		numericValue(
			leaderstats,
			"Nivel",
			1
		)

	local xp =
		numericValue(
			leaderstats,
			"XP",
			0
		)

	local diamonds =
		numericValue(
			leaderstats,
			"Diamantes",
			0
		)

	local userKey =
		tostring(
			player.UserId
		)

	--------------------------------------------------------
	-- DOLARES
	--------------------------------------------------------

	local okMoney,
		savedMoney =
		readStore(
			DOLLAR_STORE,
			userKey
		)

	if okMoney
		and typeof(savedMoney)
		== "number"
	then
		dollars.Value =
			math.clamp(
				math.floor(savedMoney),
				0,
				MAX_DOLLARS
			)

	elseif not okMoney then
		warn(
			"[SharedProgress] No se pudieron cargar dolares de "
				.. player.Name
		)
	end

	--------------------------------------------------------
	-- NIVEL / XP
	--------------------------------------------------------

	local loadedLevel,
		loadedXP =
		loadLevel(
			player.UserId
		)

	-- Esto NO dispara una alerta de nivel.
	level.Value = loadedLevel
	xp.Value = loadedXP

	--------------------------------------------------------
	-- DIAMANTES
	--------------------------------------------------------

	local okDiamonds,
		savedDiamonds =
		readStore(
			DIAMOND_STORE,
			userKey
		)

	if okDiamonds
		and typeof(savedDiamonds)
		== "number"
	then
		diamonds.Value =
			math.clamp(
				math.floor(savedDiamonds),
				0,
				MAX_DIAMONDS
			)

	elseif not okDiamonds then
		warn(
			"[SharedProgress] No se pudieron cargar diamantes de "
				.. player.Name
		)
	end

	state.values = {
		dollars = dollars,
		level = level,
		xp = xp,
		diamonds = diamonds,
	}

	updateLevelAttributes(
		player,
		level,
		xp
	)

	--------------------------------------------------------
	-- CONEXIONES
	--------------------------------------------------------

	table.insert(
		state.connections,
		dollars.Changed:Connect(
			function()
				markDirty(player)
			end
		)
	)

	table.insert(
		state.connections,
		diamonds.Changed:Connect(
			function()
				markDirty(player)
			end
		)
	)

	table.insert(
		state.connections,
		level.Changed:Connect(
			function()
				updateLevelAttributes(
					player,
					level,
					xp
				)

				markDirty(player)
			end
		)
	)

	table.insert(
		state.connections,
		xp.Changed:Connect(
			function()
				updateLevelAttributes(
					player,
					level,
					xp
				)

				markDirty(player)
			end
		)
	)

	state.loaded = true

	player:SetAttribute(
		"SharedProgressLoaded",
		true
	)

	-- Se quita en el siguiente ciclo para que todos los clientes
	-- ya hayan tomado como base el nivel cargado.
	task.defer(function()
		if player.Parent == Players then
			player:SetAttribute(
				"SuppressLevelUpNotice",
				false
			)
		end
	end)

	print(
		"[SharedProgress] "
			.. player.Name
			.. " cargado | Nivel "
			.. tostring(level.Value)
			.. " | XP "
			.. tostring(xp.Value)
			.. "/"
			.. tostring(
				xpNeeded(level.Value)
			)
	)
end

------------------------------------------------------------
-- GUARDAR
------------------------------------------------------------

savePlayer = function(player)
	local state =
		runtime[player]

	if not state
		or not state.loaded
		or not state.values
	then
		return false
	end

	local values =
		state.values

	local key =
		tostring(
			player.UserId
		)

	local money =
		math.clamp(
			math.floor(
				tonumber(
					values.dollars.Value
				) or 0
			),
			0,
			MAX_DOLLARS
		)

	local level =
		math.clamp(
			math.floor(
				tonumber(
					values.level.Value
				) or 1
			),
			1,
			MAX_LEVEL
		)

	local xp =
		math.max(
			0,
			math.floor(
				tonumber(
					values.xp.Value
				) or 0
			)
		)

	local diamonds =
		math.clamp(
			math.floor(
				tonumber(
					values.diamonds.Value
				) or 0
			),
			0,
			MAX_DIAMONDS
		)

	local okMoney =
		pcall(function()
			DOLLAR_STORE:SetAsync(
				key,
				money
			)
		end)

	local okLevel =
		pcall(function()
			LEVEL_STORE:SetAsync(
				key,
				{
					level = level,
					xp = xp,
				}
			)
		end)

	local okDiamonds =
		pcall(function()
			DIAMOND_STORE:SetAsync(
				key,
				diamonds
			)
		end)

	if okMoney
		and okLevel
		and okDiamonds
	then
		state.dirty = false
		state._requestSave = nil
		return true
	end

	warn(
		"[SharedProgress] No se pudo guardar todo el progreso de "
			.. player.Name
	)

	return false
end

------------------------------------------------------------
-- PLAYER ADDED
------------------------------------------------------------

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

------------------------------------------------------------
-- PLAYER REMOVING
------------------------------------------------------------

Players.PlayerRemoving:Connect(
	function(player)
		savePlayer(player)

		local state =
			runtime[player]

		if state then
			for _, connection in ipairs(
				state.connections
					or {}
				) do
				connection:Disconnect()
			end
		end

		actionRuntime[player] = nil
		runtime[player] = nil
	end
)

------------------------------------------------------------
-- SAVE DIFERIDO
------------------------------------------------------------

task.spawn(function()
	while true do
		task.wait(0.5)

		for player, state in pairs(
			runtime
			) do
			if player.Parent == Players
				and state.loaded
				and state._requestSave
			then
				savePlayer(player)
			end
		end
	end
end)

------------------------------------------------------------
-- AUTOSAVE
------------------------------------------------------------

task.spawn(function()
	while true do
		task.wait(
			AUTOSAVE_SECONDS
		)

		for player, state in pairs(
			runtime
			) do
			if player.Parent == Players
				and state.loaded
				and state.dirty
			then
				savePlayer(player)
			end
		end
	end
end)

------------------------------------------------------------
-- CERRAR SERVIDOR
------------------------------------------------------------

game:BindToClose(function()
	local pending = 0

	for player, state in pairs(
		runtime
		) do
		if state.loaded then
			pending += 1

			task.spawn(function()
				savePlayer(player)
				pending -= 1
			end)
		end
	end

	local started =
		os.clock()

	while pending > 0
		and os.clock() - started < 8
	do
		task.wait(0.05)
	end
end)

print(
	"[SharedProgress] V3 ACTIVO | carga sin falsa alerta + XP por acciones."
)
