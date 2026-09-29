--============================================================
-- SISTEMA CENTRAL DE TALA V8.8 - VIDA AUTOMATICA + OVEJA + BRIDGE VENTA DE MADERA
--
-- TIPO:
-- Script
--
-- UBICACION:
-- ServerScriptService > TreeChopServer
--
-- OPTIMIZACION IMPORTANTE V6:
-- Cada arbol individual es el PADRE DIRECTO de "Tronco".
--
-- En tu estructura:
--
-- Workspace
-- └─ Arboles
--    └─ Arboles de roble          <-- grupo de muchos arboles
--       ├─ Roble                  <-- arbol individual
--       │  ├─ Tronco
--       │  │  ├─ Health
--       │  │  └─ ProximityPrompt
--       │  └─ BarraVida
--       ├─ Roble
--       ├─ Roble
--       └─ ...
--
-- ESTE SCRIPT NUNCA MUEVE EL GRUPO "Arboles de roble".
-- Solo oculta/restaura las piezas del arbol individual talado.
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local DataStoreService = game:GetService("DataStoreService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local TREES_ROOT = Workspace:WaitForChild("Arboles")

--============================================================
-- PUENTE TUTORIAL
--============================================================
local function fireTutorialAction(player, actionName, payload)
	if not player or player.Parent ~= Players then return false end
	local tutorialSystem = ReplicatedStorage:FindFirstChild("TutorialSystem")
	local tutorialRemotes = tutorialSystem and tutorialSystem:FindFirstChild("Remotes")
	local action = tutorialRemotes and tutorialRemotes:FindFirstChild("ActionCompleted")
	if action and action:IsA("BindableEvent") then
		action:Fire(player, actionName, payload or {})
		return true
	end
	return false
end

--============================================================
-- CONFIGURACION
--============================================================

local PROMPT_DISTANCE = 8
local MAX_CHOP_DISTANCE = 10

-- 1 minuto 30 segundos.
local TREE_RESPAWN_TIME = 90

local DEFAULT_DROP_AMOUNT = 4

-- Los troncos que aparecen al romperse el arbol son SOLO decoracion.
local DECOR_LOG_LIFETIME = 9
local MAX_DECOR_LOGS = 5
local MAX_STACK = 99

local WOOD_STORE_NAME = "TreeWoodInventoryV1"
local TREE_RESPAWN_STORE_NAME = "TreeRespawnStateV1"
local TREE_RESPAWN_STORE_KEY = "WorldState_v1"
local WOOD_AUTOSAVE_SECONDS = 60

local DROP_RANGE_BY_TREE = {
	Roble = { 4, 7 },
	Abedul = { 3, 4 },
	Abeto = { 2, 4 },
}


--============================================================
-- VIDA AUTOMATICA POR TIPO DE ARBOL V8.8
--
-- NO necesitas cambiar manualmente los NumberValue/IntValue Health.
-- Al iniciar el servidor, TreeChopServer detecta el tipo de árbol
-- y asigna automáticamente:
--
-- Roble   = 100 HP
-- Abedul  = 300 HP
-- Abeto   = 500 HP
--============================================================

local TREE_HEALTH_BY_TYPE = {
	Roble = 100,
	Abedul = 300,
	Abeto = 500,
}

-- Daño por SEGUNDO mientras se mantiene E.
local AXE_DAMAGE = {
	["hachademadera"] = 5,
	["hachadecobre"] = 10,
	["hachadehierro"] = 15,

	["hachadecristal"] = 5,
	["hachadecristalturbio"] = 5,

	["hachadecuarzo"] = 10,
	["hachadehematita"] = 1,
	["hachadeobsidiana"] = 15,
	["hachadeserpentina"] = 10,
}

local DROP_BY_TREE = {
	roble = "MaderaRoble",
	abedul = "MaderaAbedul",
	abeto = "MaderaAbeto",
}

--============================================================
-- ESTADO
--============================================================

local stateByTrunk = {}
local activeChops = {}


local woodStore =
	DataStoreService:GetDataStore(
		WOOD_STORE_NAME
	)


local treeRespawnStore =
	DataStoreService:GetDataStore(
		TREE_RESPAWN_STORE_NAME
	)

local persistedTreeRespawns = {}

local woodCounts = {}
local woodLoaded = {}


--============================================================
-- BRIDGE SERVER-ONLY PARA LA TIENDA DE LEX
--
-- LexAxeShopServer usa estas BindableFunctions para consultar
-- y vender madera SIN tocar directamente el DataStore.
-- Así el cache de TreeChop sigue siendo la única fuente real.
--============================================================

local oldWoodBridge =
	ServerStorage:FindFirstChild(
		"TreeWoodBridge"
	)

if oldWoodBridge then
	oldWoodBridge:Destroy()
end

local woodBridge =
	Instance.new(
		"Folder"
	)

woodBridge.Name =
	"TreeWoodBridge"

woodBridge.Parent =
	ServerStorage

local getWoodStateBridge =
	Instance.new(
		"BindableFunction"
	)

getWoodStateBridge.Name =
	"GetWoodState"

getWoodStateBridge.Parent =
	woodBridge

local sellWoodBridge =
	Instance.new(
		"BindableFunction"
	)

sellWoodBridge.Name =
	"SellWood"

sellWoodBridge.Parent =
	woodBridge

local woodSellLocks = {}

local treeChopSystem =
	ReplicatedStorage:FindFirstChild(
		"TreeChopSystem"
	)

if not treeChopSystem then
	treeChopSystem =
		Instance.new("Folder")

	treeChopSystem.Name =
		"TreeChopSystem"

	treeChopSystem.Parent =
		ReplicatedStorage
end

local setChopping =
	treeChopSystem:FindFirstChild(
		"SetChopping"
	)

if not setChopping then
	setChopping =
		Instance.new("RemoteEvent")

	setChopping.Name =
		"SetChopping"

	setChopping.Parent =
		treeChopSystem
end


local treeFelled =
	treeChopSystem:FindFirstChild(
		"TreeFelled"
	)

if not treeFelled then
	treeFelled =
		Instance.new(
			"RemoteEvent"
		)

	treeFelled.Name =
		"TreeFelled"

	treeFelled.Parent =
		treeChopSystem
end

--============================================================
-- NORMALIZAR TEXTO
--============================================================

local function normalize(text)
	text = tostring(text or "")

	local replacements = {
		["á"] = "a",
		["é"] = "e",
		["í"] = "i",
		["ó"] = "o",
		["ú"] = "u",

		["Á"] = "a",
		["É"] = "e",
		["Í"] = "i",
		["Ó"] = "o",
		["Ú"] = "u",

		["ñ"] = "n",
		["Ñ"] = "n",
	}

	for old, new in pairs(replacements) do
		text = text:gsub(old, new)
	end

	text = text:lower()
	text = text:gsub("%s+", "")
	text = text:gsub("[_%-%.,]", "")

	return text
end


--============================================================
-- HABILIDAD ESPECIAL UNICA DE LA OVEJA V8.7
--
-- SOLO funciona mientras la Oveja REAL esta afuera en Workspace.
--
-- Base / sin pañuelo = x1.00
-- Blanco / Gris       = x1.50
-- Verde               = x1.75
-- Azul                = x2.00
-- Morado              = x2.25
-- Dorado              = x2.50
--
-- Cualquier otra mascota = x1.00
--
-- OPTIMIZACION:
-- No buscamos mascotas por todo Workspace en cada Heartbeat.
-- Guardamos en cache la mascota activa de cada jugador.
--============================================================

local SHEEP_CHOP_MULTIPLIER_BY_TIER = {
	Base = 1.00,
	Comun = 1.50,
	["Poco comun"] = 1.75,
	Raro = 2.00,
	Epico = 2.25,
	Legendario = 2.50,
}

local activePetByUserId = {}

local function canonicalPetTier(value)
	local key =
		normalize(
			value
		)

	if
		key == ""
		or key == "base"
	then
		return "Base"
	elseif
		key == "comun"
		or key == "gris"
		or key == "blanco"
	then
		return "Comun"
	elseif
		key == "pococomun"
		or key == "verde"
	then
		return "Poco comun"
	elseif
		key == "raro"
		or key == "azul"
	then
		return "Raro"
	elseif
		key == "epico"
		or key == "morado"
	then
		return "Epico"
	elseif
		key == "legendario"
		or key == "dorado"
	then
		return "Legendario"
	end

	return "Base"
end

local function isSheepPetName(value)
	local key =
		normalize(
			value
		)

	return
		key == "oveja"
		or key == "ovejaderosario"
end

local function isRealActivePet(model)
	if
		not model
		or not model:IsA("Model")
	then
		return false
	end

	local owner =
		model:GetAttribute(
			"Owner"
		)

	local petType =
		model:GetAttribute(
			"PetType"
		)

	if typeof(owner) ~= "number" then
		return false
	end

	if
		typeof(petType) ~= "string"
		or petType == ""
	then
		return false
	end

	if
		model:GetAttribute(
			"ClientPetVisual"
		) == true
	then
		return false
	end

	-- Si por algun sistema la mascota esta descansando,
	-- no aplica la habilidad de tala.
	if
		model:GetAttribute(
			"Resting"
		) == true
	then
		return false
	end

	return true
end

local function registerActivePet(model)
	if not isRealActivePet(model) then
		return
	end

	local owner =
		model:GetAttribute(
			"Owner"
		)

	activePetByUserId[
	owner
	] =
		model
end

local function unregisterActivePet(model)
	if
		not model
		or not model:IsA("Model")
	then
		return
	end

	local owner =
		model:GetAttribute(
			"Owner"
		)

	if
		typeof(owner) == "number"
		and activePetByUserId[
		owner
		] == model
	then
		activePetByUserId[
		owner
		] =
			nil
	end
end

for _, object in ipairs(
	Workspace:GetChildren()
	) do
	registerActivePet(
		object
	)
end

Workspace.ChildAdded:Connect(
	function(object)
		-- PetServer normalmente pone Owner/PetType/UpgradeTier
		-- antes de parentear el Model a Workspace.
		task.defer(
			function()
				if object.Parent == Workspace then
					registerActivePet(
						object
					)
				end
			end
		)
	end
)

Workspace.ChildRemoved:Connect(
	function(object)
		unregisterActivePet(
			object
		)
	end
)

local function getActivePetForPlayer(
	player
)
	local pet =
		activePetByUserId[
	player.UserId
	]

	if
		pet
		and pet.Parent == Workspace
		and isRealActivePet(
			pet
		)
	then
		return pet
	end

	activePetByUserId[
	player.UserId
	] =
		nil

	-- Fallback: solo ocurre si el cache aun no habia visto la mascota.
	for _, object in ipairs(
		Workspace:GetChildren()
		) do
		if
			isRealActivePet(
				object
			)
				and object:GetAttribute(
					"Owner"
				) == player.UserId
		then
			activePetByUserId[
			player.UserId
			] =
				object

			return object
		end
	end

	return nil
end

local function getSheepChopMultiplier(
	player
)
	local pet =
		getActivePetForPlayer(
			player
		)

	if not pet then
		return 1.00
	end

	local petName =
		pet:GetAttribute(
			"PetType"
		)
		or pet.Name

	if not isSheepPetName(
		petName
		) then
		return 1.00
	end

	local rawTier =
		pet:GetAttribute(
			"UpgradeTier"
		)
		or pet:GetAttribute(
			"PetTier"
		)
		or pet:GetAttribute(
			"Tier"
		)
		or pet:GetAttribute(
			"Rarity"
		)
		or pet:GetAttribute(
			"Rareza"
		)
		or "Base"

	local tier =
		canonicalPetTier(
			rawTier
		)

	return
		SHEEP_CHOP_MULTIPLIER_BY_TIER[
	tier
	]
		or 1.00
end

--============================================================
-- RAIZ DEL ARBOL INDIVIDUAL
--============================================================

local function getTreeRoot(trunk)
	if not trunk then
		return nil
	end

	-- ESTE ES EL CAMBIO PRINCIPAL:
	-- NO buscamos el primer Model ancestro.
	-- El padre directo del Tronco ES el arbol individual.
	return trunk.Parent
end

--============================================================
-- TIPO DE ARBOL
--============================================================

local function getTreeType(treeRoot)
	if not treeRoot then
		return "Arbol"
	end

	local forced =
		treeRoot:GetAttribute("TreeType")

	if typeof(forced) == "string" and forced ~= "" then
		return forced
	end

	local current = treeRoot

	while current and current ~= Workspace do
		local name = normalize(current.Name)

		if name:find("roble", 1, true) then
			return "Roble"
		elseif name:find("abedul", 1, true) then
			return "Abedul"
		elseif name:find("abeto", 1, true) then
			return "Abeto"
		end

		current = current.Parent
	end

	return treeRoot.Name
end


--============================================================
-- ID PERSISTENTE DEL ARBOL
--============================================================

local function roundedCoord(value)
	local scaled =
		value * 10

	if scaled >= 0 then
		return math.floor(
			scaled + 0.5
		)
	end

	return math.ceil(
		scaled - 0.5
	)
end

local function getTreePersistentId(
	treeRoot,
	trunk
)
	local treeType =
		getTreeType(
			treeRoot
		)

	local position =
		trunk.Position

	return
		normalize(treeType)
		.. "_"
		.. tostring(
			roundedCoord(
				position.X
			)
		)
		.. "_"
		.. tostring(
			roundedCoord(
				position.Y
			)
		)
		.. "_"
		.. tostring(
			roundedCoord(
				position.Z
			)
		)
end

local function loadPersistentTreeRespawns()
	local success, raw =
		pcall(function()
			return treeRespawnStore:GetAsync(
				TREE_RESPAWN_STORE_KEY
			)
		end)

	if
		success
		and typeof(raw) == "table"
	then
		local now =
			os.time()

		for treeId, timestamp in pairs(
			raw
			) do
			local timeValue =
				tonumber(
					timestamp
				)

			if
				timeValue
				and timeValue > now
			then
				persistedTreeRespawns[
				tostring(treeId)
				] =
					timeValue
			end
		end
	elseif not success then
		warn(
			"[TreeChop] No se pudo cargar estado persistente de arboles:",
			raw
		)
	end
end

local function writeTreeRespawnState(
	treeId,
	respawnAt
)
	if
		not treeId
		or treeId == ""
	then
		return
	end

	if
		respawnAt
		and respawnAt > os.time()
	then
		persistedTreeRespawns[
		treeId
		] =
			respawnAt
	else
		persistedTreeRespawns[
		treeId
		] =
			nil
	end

	local success, err =
		pcall(function()
			treeRespawnStore:UpdateAsync(
				TREE_RESPAWN_STORE_KEY,
				function(old)
					old =
					typeof(old) == "table"
					and old
					or {}

					local now =
					os.time()

					for id, value in pairs(
						old
						) do
						local n =
						tonumber(
							value
						)

						if
							not n
							or n <= now
						then
							old[id] =
							nil
						end
					end

					if
						respawnAt
						and respawnAt > now
					then
						old[treeId] =
						respawnAt
					else
						old[treeId] =
						nil
					end

					return old
				end
			)
		end)

	if not success then
		warn(
			"[TreeChop] No se pudo guardar respawn de arbol:",
			treeId,
			err
		)
	end
end

--============================================================
-- DROP DEL ARBOL
--============================================================

local function getDropName(treeRoot)
	local forced =
		treeRoot:GetAttribute("DropName")

	if typeof(forced) == "string" and forced ~= "" then
		return forced
	end

	local current = treeRoot

	while current and current ~= Workspace do
		local name = normalize(current.Name)

		for word, dropName in pairs(DROP_BY_TREE) do
			if name:find(word, 1, true) then
				return dropName
			end
		end

		current = current.Parent
	end

	return nil
end

--============================================================
-- BUSCAR MADERA EN REPLICATEDSTORAGE
--============================================================

local function findWoodTemplate(name)
	if not name then
		return nil
	end

	local exact =
		ReplicatedStorage:FindFirstChild(name)

	if exact and exact:IsA("Tool") then
		return exact
	end

	local wanted = normalize(name)

	for _, child in ipairs(ReplicatedStorage:GetChildren()) do
		if
			child:IsA("Tool")
			and normalize(child.Name) == wanted
		then
			return child
		end
	end

	return nil
end

--============================================================
-- HACHA EQUIPADA
--============================================================

local function getEquippedAxe(player)
	local character = player.Character

	if not character then
		return nil, nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			local damage =
				AXE_DAMAGE[normalize(child.Name)]

			if damage then
				return child, damage
			end
		end
	end

	return nil, nil
end

--============================================================
-- DISTANCIA
--============================================================

local function playerNear(player, trunk)
	local character = player.Character

	if not character then
		return false
	end

	local root =
		character:FindFirstChild("HumanoidRootPart")

	if not root then
		return false
	end

	return
		(root.Position - trunk.Position).Magnitude
		<= MAX_CHOP_DISTANCE
end

--============================================================
-- GUARDAR PIEZAS DEL ARBOL INDIVIDUAL
--============================================================

local function collectTreeParts(treeRoot)
	local parts = {}

	-- El propio Roble puede ser MeshPart/BasePart.
	if treeRoot:IsA("BasePart") then
		table.insert(parts, treeRoot)
	end

	for _, object in ipairs(treeRoot:GetDescendants()) do
		if object:IsA("BasePart") then
			table.insert(parts, object)
		end
	end

	return parts
end

local function savePartStates(treeRoot)
	local saved = {}

	for _, part in ipairs(collectTreeParts(treeRoot)) do
		saved[part] = {
			Transparency = part.Transparency,
			CanCollide = part.CanCollide,
			CanTouch = part.CanTouch,
			CanQuery = part.CanQuery,
		}
	end

	return saved
end

local function hideIndividualTree(state)
	for part, values in pairs(state.savedParts) do
		if part and part.Parent then
			part.Transparency = 1
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
		end
	end

	if state.billboard and state.billboard.Parent then
		state.billboard.Enabled = false
	end
end

local function restoreIndividualTree(state)
	for part, values in pairs(state.savedParts) do
		if part and part.Parent then
			part.Transparency = values.Transparency
			part.CanCollide = values.CanCollide
			part.CanTouch = values.CanTouch
			part.CanQuery = values.CanQuery
		end
	end
end

--============================================================
-- MADERA / STACK / GUARDADO
--============================================================

local function canonicalWoodType(name)
	local normalized =
		normalize(name)

	if normalized == "maderaroble" then
		return "MaderaRoble"
	elseif normalized == "maderaabedul" then
		return "MaderaAbedul"
	elseif normalized == "maderaabeto" then
		return "MaderaAbeto"
	end

	return tostring(name or "")
end

local function prettyWoodName(templateName)
	local name = normalize(templateName)

	if name == "maderaroble" then
		return "Madera Roble"
	elseif name == "maderaabedul" then
		return "Madera Abedul"elseif name == "maderaabeto" then
		return "Madera Abeto"
	end

	return templateName
end

local function cleanWoodTool(tool)
	for _, object in ipairs(
		tool:GetDescendants()
		) do
		if
			object:IsA("Script")
			or object:IsA("LocalScript")
			or object:IsA("ProximityPrompt")
		then
			object:Destroy()
		end
	end
end

local function configureWood(
	tool,
	templateName,
	amount
)
	cleanWoodTool(tool)

	amount =
		math.clamp(
			math.floor(
				tonumber(amount)
				or 1
			),
			1,
			MAX_STACK
		)

	templateName =
		canonicalWoodType(
			templateName
		)

	local displayName =
		prettyWoodName(
			templateName
		)

	tool:SetAttribute(
		"EsMadera",
		true
	)

	tool:SetAttribute(
		"WoodType",
		templateName
	)

	tool:SetAttribute(
		"WoodStackQuantity",
		amount
	)

	tool:SetAttribute(
		"Cantidad",
		amount
	)

	tool:SetAttribute(
		"ItemType",
		"Material"
	)

	tool:SetAttribute(
		"ItemName",
		displayName
	)

	tool:SetAttribute(
		"BackpackDisplayName",
		displayName
	)

	tool.CanBeDropped =
		false

	-- La cantidad la muestra el BackpackScript.
	tool.Name =
		displayName
end

local function isWoodTool(tool)
	if
		not tool
		or not tool:IsA("Tool")
	then
		return false
	end

	if
		tool:GetAttribute(
			"EsMadera"
		) == true
	then
		return true
	end

	local name =
		normalize(
			tool:GetAttribute(
				"ItemName"
			)
			or tool.Name
		)

	return
		name:find(
			"maderaroble",
			1,
			true
		) == 1
		or name:find(
			"maderaabedul",
			1,
			true
		) == 1
		or name:find(
			"maderaabeto",
			1,
			true
		) == 1
end

local function getWoodTypeFromTool(tool)
	if not isWoodTool(tool) then
		return nil
	end

	local forced =
		tool:GetAttribute(
			"WoodType"
		)

	if
		typeof(forced) == "string"
		and forced ~= ""
	then
		return
			canonicalWoodType(
				forced
			)
	end

	local name =
		normalize(
			tool:GetAttribute(
				"ItemName"
			)
			or tool.Name
		)

	if
		name:find(
			"maderaroble",
			1,
			true
		) == 1
	then
		return "MaderaRoble"
	elseif
		name:find(
			"maderaabedul",
			1,
			true
		) == 1
	then
		return "MaderaAbedul"
	elseif
		name:find(
			"maderaabeto",
			1,
			true
		) == 1
	then
		return "MaderaAbeto"
	end

	return nil
end

local function defaultWoodCounts()
	return {
		MaderaRoble = 0,
		MaderaAbedul = 0,
		MaderaAbeto = 0,
	}
end

local function sanitizeWoodCounts(raw)
	local result =
		defaultWoodCounts()

	if typeof(raw) ~= "table" then
		return result
	end

	local source =
		typeof(raw.Counts) == "table"
		and raw.Counts
		or raw

	for woodType in pairs(result) do
		result[woodType] =
			math.max(
				0,
				math.floor(
					tonumber(
						source[woodType]
					)
					or 0
				)
			)
	end

	return result
end

local function clearPhysicalWoodType(
	player,
	woodType
)
	local containers = {
		player.Character,
		player:FindFirstChildOfClass(
			"Backpack"
		),
	}

	for _, container in ipairs(
		containers
		) do
		if container then
			for _, child in ipairs(
				container:GetChildren()
				) do
				if
					child:IsA("Tool")
					and getWoodTypeFromTool(
						child
					) == woodType
				then
					child:Destroy()
				end
			end
		end
	end
end

local function syncWoodType(
	player,
	woodType
)
	woodType =
		canonicalWoodType(
			woodType
		)

	local counts =
		woodCounts[player]

	if not counts then
		return
	end

	local backpack =
		player:FindFirstChildOfClass(
			"Backpack"
		)

	if not backpack then
		return
	end

	local template =
		findWoodTemplate(
			woodType
		)

	if
		not template
		or not template:IsA("Tool")
	then
		warn(
			"[TreeChop] Falta Tool de madera:",
			woodType
		)

		return
	end

	clearPhysicalWoodType(
		player,
		woodType
	)

	local remaining =
		math.max(
			0,
			math.floor(
				tonumber(
					counts[woodType]
				)
				or 0
			)
		)

	while remaining > 0 do
		local amount =
			math.min(
				MAX_STACK,
				remaining
			)

		local clone =
			template:Clone()

		configureWood(
			clone,
			woodType,
			amount
		)

		clone.Parent =
			backpack

		remaining -=
			amount
	end
end

local function syncAllWood(
	player
)
	if not woodLoaded[player] then
		return
	end

	for _, woodType in ipairs({
		"MaderaRoble",
		"MaderaAbedul",
		"MaderaAbeto",
		}) do
		syncWoodType(
			player,
			woodType
		)
	end
end

local function saveWoodInventory(
	player
)
	local counts =
		woodCounts[player]

	if not counts then
		return false
	end

	local payload = {
		Version = 1,
		UpdatedAt = os.time(),
		Counts = {
			MaderaRoble =
				math.max(
					0,
					math.floor(
						counts.MaderaRoble
						or 0
					)
				),
			MaderaAbedul =
				math.max(
					0,
					math.floor(
						counts.MaderaAbedul
						or 0
					)
				),
			MaderaAbeto =
				math.max(
					0,
					math.floor(
						counts.MaderaAbeto
						or 0
					)
				),
		},
	}

	local success, err =
		pcall(function()
			woodStore:SetAsync(
				"Player_"
				.. player.UserId,
				payload
			)
		end)

	if not success then
		warn(
			"[TreeChop] Error guardando madera:",
			player.Name,
			err
		)

		return false
	end

	return true
end

local function loadWoodInventory(
	player
)
	if woodLoaded[player] then
		return
	end

	local success, raw =
		pcall(function()
			return woodStore:GetAsync(
				"Player_"
				.. player.UserId
			)
		end)

	if not success then
		warn(
			"[TreeChop] Error cargando madera:",
			player.Name,
			raw
		)

		raw = nil
	end

	woodCounts[player] =
		sanitizeWoodCounts(
			raw
		)

	woodLoaded[player] =
		true

	player:WaitForChild(
		"Backpack"
	)

	syncAllWood(
		player
	)

	print(
		"[TreeChop] MADERA CARGADA |",
		player.Name,
		"| Roble:",
		woodCounts[player].MaderaRoble,
		"| Abedul:",
		woodCounts[player].MaderaAbedul,
		"| Abeto:",
		woodCounts[player].MaderaAbeto
	)
end

local function addWood(
	player,
	template,
	amount
)
	if not woodLoaded[player] then
		loadWoodInventory(
			player
		)
	end

	local templateName =
		canonicalWoodType(
			template.Name
		)

	local counts =
		woodCounts[player]
		or defaultWoodCounts()

	woodCounts[player] =
		counts

	counts[templateName] =
		math.max(
			0,
			math.floor(
				tonumber(
					counts[templateName]
				)
				or 0
			)
		)
		+ math.max(
			0,
			math.floor(
				tonumber(amount)
				or 0
			)
		)

	syncWoodType(
		player,
		templateName
	)

	return
		counts[templateName]
end

--============================================================
-- API SERVER-ONLY DE MADERA PARA LEX
--============================================================

local VALID_WOOD_TYPES = {
	MaderaRoble = true,
	MaderaAbedul = true,
	MaderaAbeto = true,
}

local function copyWoodCounts(
	player
)
	local counts =
		woodCounts[player]
		or defaultWoodCounts()

	return {
		MaderaRoble =
			math.max(
				0,
				math.floor(
					tonumber(
						counts.MaderaRoble
					)
					or 0
				)
			),
		MaderaAbedul =
			math.max(
				0,
				math.floor(
					tonumber(
						counts.MaderaAbedul
					)
					or 0
				)
			),
		MaderaAbeto =
			math.max(
				0,
				math.floor(
					tonumber(
						counts.MaderaAbeto
					)
					or 0
				)
			),
	}
end

getWoodStateBridge.OnInvoke =
	function(player)
		if
			not player
			or player.Parent
			~= Players
		then
			return {
				Success = false,
				Counts =
				defaultWoodCounts(),
			}
		end

		if not woodLoaded[player] then
			loadWoodInventory(
				player
			)
		end

		return {
			Success = true,
			Counts =
			copyWoodCounts(
				player
			),
		}
	end

sellWoodBridge.OnInvoke =
	function(
		player,
		woodType,
		requestedAmount
	)
	if
		not player
		or player.Parent
		~= Players
	then
		return {
			Success = false,
			Message =
				"Jugador no valido.",
		}
	end

	woodType =
		canonicalWoodType(
			woodType
		)

	if not VALID_WOOD_TYPES[
		woodType
		] then
		return {
			Success = false,
			Message =
				"Tipo de madera no valido.",
		}
	end

	local amount =
		math.floor(
			tonumber(
				requestedAmount
			)
			or 0
		)

	if
		amount < 1
		or amount > 99
	then
		return {
			Success = false,
			Message =
				"Solo puedes vender de x1 a x99 por vez.",
		}
	end

	if woodSellLocks[player] then
		return {
			Success = false,
			Message =
				"Espera un momento.",
		}
	end

	woodSellLocks[player] =
		true

	if not woodLoaded[player] then
		loadWoodInventory(
			player
		)
	end

	local counts =
		woodCounts[player]
		or defaultWoodCounts()

	woodCounts[player] =
		counts

	local current =
		math.max(
			0,
			math.floor(
				tonumber(
					counts[woodType]
				)
				or 0
			)
		)

	if current < amount then
		woodSellLocks[player] =
			nil

		return {
			Success = false,
			Message =
				"Solo tienes x"
				.. tostring(
					current
				)
				.. ".",
			Remaining =
				current,
			Counts =
				copyWoodCounts(
					player
				),
		}
	end

	counts[woodType] =
		current - amount

	syncWoodType(
		player,
		woodType
	)

	task.spawn(
		saveWoodInventory,
		player
	)

	local remaining =
		counts[woodType]

	woodSellLocks[player] =
		nil

	print(
		"[TreeChop] MADERA VENDIDA |",
		player.Name,
		"|",
		woodType,
		"| -"
			.. tostring(
				amount
			),
		"| quedan:",
		remaining
	)

	return {
		Success = true,
		SoldAmount =
			amount,
		Remaining =
			remaining,
		Counts =
			copyWoodCounts(
				player
			),
	}
end

local function watchCharacter(
	player,
	character
)
	character.ChildAdded:Connect(
		function(child)
			if not isWoodTool(child) then
				return
			end

			task.defer(function()
				if child.Parent ~= character then
					return
				end

				local backpack =
					player:FindFirstChildOfClass(
						"Backpack"
					)

				if backpack then
					child.Parent =
						backpack
				end
			end)
		end
	)
end

local function setupPlayer(
	player
)
	task.spawn(
		loadWoodInventory,
		player
	)

	if player.Character then
		watchCharacter(
			player,
			player.Character
		)
	end

	player.CharacterAdded:Connect(
		function(character)
			watchCharacter(
				player,
				character
			)

			task.delay(
				0.6,
				function()
					if player.Parent == Players then
						syncAllWood(
							player
						)
					end
				end
			)
		end
	)

	player.ChildAdded:Connect(
		function(child)
			if child:IsA("Backpack") then
				task.delay(
					0.25,
					function()
						if
							player.Parent
							== Players
						then
							syncAllWood(
								player
							)
						end
					end
				)
			end
		end
	)
end

for _, player in ipairs(
	Players:GetPlayers()
	) do
	setupPlayer(
		player
	)
end

Players.PlayerAdded:Connect(
	setupPlayer
)

task.spawn(function()
	while true do
		task.wait(
			WOOD_AUTOSAVE_SECONDS
		)

		for _, player in ipairs(
			Players:GetPlayers()
			) do
			if woodLoaded[player] then
				task.spawn(
					saveWoodInventory,
					player
				)
			end
		end
	end
end)

--============================================================
-- TRONCOS DECORATIVOS V8.2
--
-- - Marrones según el árbol.
-- - Caen desde arriba hasta la BASE del árbol.
-- - Se crean en servidor: todos los jugadores los ven.
-- - No se recogen; solo son decoración.
--============================================================

local LOG_BODY_COLOR = {
	Roble =
		Color3.fromRGB(
			119,
			76,
			43
		),
	Abedul =
		Color3.fromRGB(
			190,
			176,
			139
		),
	Abeto =
		Color3.fromRGB(
			90,
			63,
			39
		),
}

local LOG_END_COLOR = {
	Roble =
		Color3.fromRGB(
			197,
			148,
			88
		),
	Abedul =
		Color3.fromRGB(
			229,
			215,
			176
		),
	Abeto =
		Color3.fromRGB(
			157,
			116,
			72
		),
}

local function getDecorFolder()
	local folder =
		Workspace:FindFirstChild(
			"TreeDecorLogs"
		)

	if not folder then
		folder =
			Instance.new(
				"Folder"
			)

		folder.Name =
			"TreeDecorLogs"

		folder.Parent =
			Workspace
	end

	return folder
end

local function makeLogPart(
	name,
	size,
	color,
	parent
)
	local part =
		Instance.new(
			"Part"
		)

	part.Name =
		name

	part.Shape =
		Enum.PartType.Cylinder

	part.Size =
		size

	part.Material =
		Enum.Material.Wood

	part.Color =
		color

	part.Anchored =
		true

	part.CanCollide =
		false

	part.CanTouch =
		false

	part.CanQuery =
		false

	part.CastShadow =
		true

	part.Parent =
		parent

	return part
end

local function findDecorGroundY(
	worldX,
	worldZ,
	basePosition,
	radius
)-- basePosition viene calculado cerca de la base del tronco.
	-- Estimamos el piso y, si es posible, lo confirmamos con Raycast.
	local fallbackGroundY =
		basePosition.Y
	- 0.58

	local rayOrigin =
		Vector3.new(
			worldX,
			basePosition.Y + 7,
			worldZ
		)

	local rayDirection =
		Vector3.new(
			0,
			-16,
			0
		)

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	local excluded = {
		TREES_ROOT,
	}

	local decorFolder =
		Workspace:FindFirstChild(
			"TreeDecorLogs"
		)

	if decorFolder then
		table.insert(
			excluded,
			decorFolder
		)
	end

	params.FilterDescendantsInstances =
		excluded

	params.IgnoreWater =
		false

	local result =
		Workspace:Raycast(
			rayOrigin,
			rayDirection,
			params
		)

	local groundY =
		fallbackGroundY

	if result then
		local hitY =
			result.Position.Y

		-- Evita poner un tronquito encima de una valla/objeto alto.
		-- Solo aceptamos superficies razonablemente cercanas a la
		-- base real del árbol.
		if
			math.abs(
				hitY
				- fallbackGroundY
			)
				<= 1.25
		then
			groundY =
				hitY
		end
	end

	-- Centro del cilindro = piso + radio + margen pequeño.
	return
		groundY
		+ radius
		+ 0.08
end

local function createDecorLog(
	treeType,
	basePosition,
	index,
	total
)
	local model =
		Instance.new(
			"Model"
		)

	model.Name =
		"TroncoDecorativo_"
		.. tostring(
			treeType
		)

	local bodyColor =
		LOG_BODY_COLOR[
	treeType
	]
		or LOG_BODY_COLOR.Roble

	local endColor =
		LOG_END_COLOR[
	treeType
	]
		or LOG_END_COLOR.Roble

	local length =
		2.65
		+ math.random()
		* 0.55

	local radius =
		0.46
		+ math.random()
		* 0.08

	local body =
		makeLogPart(
			"Tronco",
			Vector3.new(
				length,
				radius * 2,
				radius * 2
			),
			bodyColor,
			model
		)

	local endA =
		makeLogPart(
			"CorteA",
			Vector3.new(
				0.09,
				radius * 1.92,
				radius * 1.92
			),
			endColor,
			model
		)

	local endB =
		makeLogPart(
			"CorteB",
			Vector3.new(
				0.09,
				radius * 1.92,
				radius * 1.92
			),
			endColor,
			model
		)

	model.PrimaryPart =
		body

	local relativeEndA =
		CFrame.new(
			length * 0.5 + 0.045,
			0,
			0
		)

	local relativeEndB =
		CFrame.new(
			-(length * 0.5 + 0.045),
			0,
			0
		)

	local angle =
		(
			(index - 1)
			/ math.max(
				total,
				1
			)
		)
		* math.pi
		* 2

	-- V8.5:
	-- Los ponemos alrededor del árbol en un círculo más amplio.
	-- Así no quedan atravesados unos con otros.
	local spread =
		2.25
		+ (
			(index % 2)
			* 0.28
		)

	local x =
		math.cos(
			angle
		)
		* spread

	local z =
		math.sin(
			angle
		)
		* spread

	-- Cada tronco queda tangente al círculo, con solo una pequeña
	-- variación para que no se vea demasiado perfecto.
	local yaw =
		angle
		+ (
			math.pi
			* 0.5
		)
		+ math.rad(
			math.random(
				-10,
				10
			)
		)

	local finalX =
		basePosition.X
		+ x

	local finalZ =
		basePosition.Z
		+ z

	local finalY =
		findDecorGroundY(
			finalX,
			finalZ,
			basePosition,
			radius
		)

	local finalPosition =
		Vector3.new(
			finalX,
			finalY,
			finalZ
		)

	-- Al terminar de caer quedan totalmente horizontales.
	local finalPivot =
		CFrame.new(
			finalPosition
		)
		* CFrame.Angles(
			0,
			yaw,
			0
		)

	local spawnPivot =
		CFrame.new(
			finalPosition
			+ Vector3.new(
				0,
				3.2
				+ index
				* 0.18,
				0
			)
		)
		* CFrame.Angles(
			math.rad(
				math.random(
					-18,
					18
				)
			),
			yaw
			+ math.rad(
				math.random(
					-12,
					12
				)
			),
			math.rad(
				math.random(
					-18,
					18
				)
			)
		)

	local function placeParts(
		pivot
	)
		body.CFrame =
			pivot

		endA.CFrame =
			pivot
			* relativeEndA

		endB.CFrame =
			pivot
			* relativeEndB
	end

	placeParts(
		spawnPivot
	)

	model.Parent =
		getDecorFolder()

	local cfValue =
		Instance.new(
			"CFrameValue"
		)

	cfValue.Value =
		spawnPivot

	local changedConnection =
		cfValue
		:GetPropertyChangedSignal(
			"Value"
		)
		:Connect(function()
			if model.Parent then
				placeParts(
					cfValue.Value
				)
			end
		end)

	local fallTween =
		TweenService:Create(
			cfValue,
			TweenInfo.new(
				0.58,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				Value =
				finalPivot,
			}
		)

	fallTween:Play()

	fallTween.Completed:Connect(
		function()
			changedConnection:Disconnect()
			cfValue:Destroy()
		end
	)

	task.delay(
		DECOR_LOG_LIFETIME
		- 1,
		function()
			if not model.Parent then
				return
			end

			for _, part in ipairs(
				model:GetChildren()
				) do
				if part:IsA(
					"BasePart"
					) then
					TweenService:Create(
						part,
						TweenInfo.new(
							0.85,
							Enum.EasingStyle.Quad,
							Enum.EasingDirection.In
						),
						{
							Transparency =
								1,
						}
					):Play()
				end
			end
		end
	)

	task.delay(
		DECOR_LOG_LIFETIME,
		function()
			if model.Parent then
				model:Destroy()
			end
		end
	)
end

local function getRandomDropAmount(
	treeType
)
	local range =
		DROP_RANGE_BY_TREE[
	treeType
	]

	if not range then
		return DEFAULT_DROP_AMOUNT
	end

	return math.random(
		range[1],
		range[2]
	)
end

--============================================================
-- TALADO COMPLETO
--============================================================

local function restoreTreeNow(
	state
)
	if
		not state
		or not state.treeRoot
		or not state.treeRoot.Parent
	then
		return
	end

	state.currentHealth =
		state.maxHealth

	state.health.Value =
		state.maxHealth

	state.treeRoot:SetAttribute(
		"CurrentTreeHealth",
		state.maxHealth
	)

	restoreIndividualTree(
		state
	)

	state.alive =
		true

	state.treeRoot:SetAttribute(
		"TreeAlive",
		true
	)

	state.prompt.Enabled =
		false

	if state.persistentId then
		writeTreeRespawnState(
			state.persistentId,
			nil
		)
	end
end

local function scheduleTreeRespawn(
	state,
	delaySeconds
)
	delaySeconds =
		math.max(
			0,
			tonumber(
				delaySeconds
			)
			or TREE_RESPAWN_TIME
		)

	task.delay(
		delaySeconds,
		function()
			restoreTreeNow(
				state
			)
		end
	)
end

local function killTree(
	state,
	rewardPlayer
)
	if not state.alive then
		return
	end

	state.alive =
		false

	state.currentHealth =
		0

	state.treeRoot:SetAttribute(
		"TreeAlive",
		false
	)

	state.treeRoot:SetAttribute(
		"CurrentTreeHealth",
		0
	)

	state.health.Value =
		0

	state.prompt.Enabled =
		false

	if
		state.billboard
		and state.billboard.Parent
	then
		state.billboard.Enabled =
			false
	end

	for player, activeState in pairs(
		activeChops
		) do
		if activeState == state then
			activeChops[player] =
				nil
		end
	end

	-- Ocultar este árbol para TODOS los jugadores.
	hideIndividualTree(
		state
	)

	-- Limpieza visual inmediata para TODOS los clientes.
	treeFelled:FireAllClients(
		state.treeRoot,
		state.trunk
	)

	print(
		"[TreeChop] ARBOL TALADO |",
		state.treeType,
		"| respawn: 90s | tronco:",
		state.persistentId
	)

	local rewardAmount =
		getRandomDropAmount(
			state.treeType
		)

	local template =
		findWoodTemplate(
			getDropName(
				state.treeRoot
			)
		)

	-- Dar la madera SOLO al jugador que terminó el árbol.
	if
		template
		and rewardPlayer
		and rewardPlayer.Parent
		== Players
	then
		local newTotal =
			addWood(
				rewardPlayer,
				template,
				rewardAmount
			)

		task.spawn(
			saveWoodInventory,
			rewardPlayer
		)

		print(
			"[TreeChop] MADERA AUTOMATICA |",
			rewardPlayer.Name,
			"|",
			template.Name,
			"| +"
				.. tostring(
					rewardAmount
				),
			"| total:",
			newTotal
		)
	elseif not template then
		warn(
			"[TreeChop] Falta plantilla de madera para:",
			state.treeType
		)
	end

	-- V8.9 / TUTORIAL V6.17:
	-- Primero se entrega la madera y DESPUÉS se completa el tutorial.
	-- Así el jugador recibe su recompensa del árbol antes de ver
	-- la alerta "TUTORIAL COMPLETADO".
	if rewardPlayer and rewardPlayer.Parent == Players then
		fireTutorialAction(rewardPlayer, "WOOD_CHOPPED", {
			TreeType = state.treeType,
			TreeId = state.persistentId,
			RewardAmount = rewardAmount,
			WoodName = template and template.Name or "",
		})
	end

	-- Tronquitos VISUALES para todos, haya o no plantilla.
	local decorCount =
		math.min(
			MAX_DECOR_LOGS,
			math.max(
				2,
				rewardAmount
			)
		)

	for index = 1, decorCount do
		createDecorLog(
			state.treeType,
			state.dropBasePosition,
			index,
			decorCount
		)
	end

	-- Persistir el tiempo restante:
	-- si sales/entras antes de 90 s, el árbol sigue talado.
	local respawnAt =
		os.time()
		+ TREE_RESPAWN_TIME

	if state.persistentId then
		writeTreeRespawnState(
			state.persistentId,
			respawnAt
		)
	end

	scheduleTreeRespawn(
		state,
		TREE_RESPAWN_TIME
	)
end

--============================================================
-- REGISTRAR TRONCO
--============================================================

local function registerTrunk(trunk)
	if stateByTrunk[trunk] then
		return
	end

	if
		not trunk:IsA("BasePart")
		or trunk.Name ~= "Tronco"
	then
		return
	end

	local health =
		trunk:FindFirstChild("Health")

	if
		not health
		or (
			not health:IsA("NumberValue")
				and not health:IsA("IntValue")
		)
	then
		return
	end

	local prompt =
		trunk:FindFirstChildWhichIsA(
			"ProximityPrompt"
		)

	if not prompt then
		return
	end

	local treeRoot =
		getTreeRoot(trunk)

	if not treeRoot then
		return
	end

	local treeType =
		getTreeType(treeRoot)

	-- V8.8:
	-- La vida ya no depende del valor que tenga puesto manualmente
	-- cada Health en Studio. Se fuerza automáticamente por tipo.
	local maxHealth =
		TREE_HEALTH_BY_TYPE[
	treeType
	]
		or math.max(
			1,
			tonumber(
				health.Value
			)
			or 1
		)

	-- Sincronizar el Value físico del Tronco al iniciar.
	-- Si el árbol estaba talado de forma persistente, más abajo
	-- se cambiará temporalmente a 0 hasta su respawn.
	health.Value =
		maxHealth

	local billboard = nil
	local barContainer =
		treeRoot:FindFirstChild(
			"BarraVida"
		)

	if barContainer then
		if barContainer:IsA(
			"BillboardGui"
			) then
			billboard =
				barContainer
		else
			billboard =
				barContainer:FindFirstChildWhichIsA(
					"BillboardGui",
					true
				)
		end
	end

	--========================================================
	-- OPTIMIZACION V6:
	-- Las 366+ barras NO se renderizan todo el tiempo.
	-- El cliente solo enciende la barra del arbol cercano.
	--========================================================

	if billboard then
		billboard.Enabled = false

		local white =
			billboard:FindFirstChild(
				"Blanco",
				true
			)

		if white and white:IsA("GuiObject") then
			treeRoot:SetAttribute(
				"TreeBarMaxXScale",
				white.Size.X.Scale
			)

			treeRoot:SetAttribute(
				"TreeBarMaxXOffset",
				white.Size.X.Offset
			)

			treeRoot:SetAttribute(
				"TreeBarMaxYScale",
				white.Size.Y.Scale
			)

			treeRoot:SetAttribute(
				"TreeBarMaxYOffset",
				white.Size.Y.Offset
			)
		end
	end

	local state = {
		treeRoot = treeRoot,
		trunk = trunk,
		health = health,
		prompt = prompt,
		treeType = treeType,
		persistentId =
			getTreePersistentId(
				treeRoot,
				trunk
			),

		maxHealth = maxHealth,
		currentHealth = maxHealth,

		alive = true,

		dropCFrame = trunk.CFrame,

		dropBasePosition =
			Vector3.new(
				trunk.Position.X,
				trunk.Position.Y
				- (
					trunk.Size.Y
					* 0.5
				)
				+ 0.58,
				trunk.Position.Z
			),

		respawnTime = TREE_RESPAWN_TIME,

		dropAmount =
			math.max(
				1,
				math.floor(
					tonumber(
						treeRoot:GetAttribute("DropAmount")
					)
					or DEFAULT_DROP_AMOUNT
				)
			),

		billboard = billboard,
		savedParts = savePartStates(treeRoot),
	}

	stateByTrunk[trunk] = state

	--========================================================
	-- ATRIBUTOS DEL ARBOL INDIVIDUAL
	--========================================================

	treeRoot:SetAttribute(
		"TreeType",
		treeType
	)

	treeRoot:SetAttribute(
		"TreeAlive",
		true
	)

	treeRoot:SetAttribute(
		"MaxTreeHealth",
		maxHealth
	)

	treeRoot:SetAttribute(
		"CurrentTreeHealth",
		maxHealth
	)


	treeRoot:SetAttribute(
		"RespawnTime",
		TREE_RESPAWN_TIME
	)

	--========================================================
	-- PROMPT
	--========================================================

	prompt.Name =
		"TreeChopPrompt"

	prompt.Style =
		Enum.ProximityPromptStyle.Custom

	prompt.ActionText =
		"Talar"

	prompt.ObjectText =
		"Árbol " .. treeType

	prompt.KeyboardKeyCode =
		Enum.KeyCode.E

	prompt.GamepadKeyCode =
		Enum.KeyCode.ButtonX

	prompt.HoldDuration = 999

	prompt.MaxActivationDistance =
		PROMPT_DISTANCE

	prompt.RequiresLineOfSight = false

	-- Evita que muchos arboles cercanos intenten mostrar
	-- varios prompts al mismo tiempo.
	prompt.Exclusivity =
		Enum.ProximityPromptExclusivity.OneGlobally

	prompt.Enabled = false

	-- Si este árbol fue cortado antes de reiniciar/reentrar
	-- y todavía no han pasado los 90 segundos, mantenerlo oculto.
	local persistedUntil =
		persistedTreeRespawns[
	state.persistentId
	]

	if
		persistedUntil
		and persistedUntil > os.time()
	then
		state.alive =
			false

		state.currentHealth =
			0

		state.health.Value =
			0

		state.treeRoot:SetAttribute(
			"TreeAlive",
			false
		)

		state.treeRoot:SetAttribute(
			"CurrentTreeHealth",
			0
		)

		hideIndividualTree(
			state
		)

		scheduleTreeRespawn(
			state,
			persistedUntil
			- os.time()
		)
	end

	-- V8 usa TreeChopSystem.SetChopping.
	-- El ProximityPrompt queda como referencia dentro del Tronco,
	-- pero está desactivado para evitar que Roblox oculte/muestre
	-- el botón según el ángulo de la cámara.

end

--============================================================
-- INTERACCION V8
--
-- El cliente manda Begin/End de E.
-- El servidor valida TODO: árbol, distancia y hacha.
--============================================================

setChopping.OnServerEvent:Connect(
	function(
		player,
		trunk,
		isHolding
	)
		if isHolding ~= true then
			activeChops[player] =
				nil

			return
		end

		if
			not trunk
			or not trunk:IsA(
				"BasePart"
			)
		then
			return
		end

		local state =
			stateByTrunk[
		trunk
		]

		if
			not state
			or not state.alive
			or not state.treeRoot.Parent
		then
			return
		end

		if not playerNear(
			player,
			trunk
			) then
			return
		end

		local axe, damage =
			getEquippedAxe(
				player
			)

		if
			not axe
			or not damage
		then
			return
		end

		activeChops[player] =
			state
	end
)

--============================================================-- ESCANEO
--============================================================

loadPersistentTreeRespawns()

for _, object in ipairs(TREES_ROOT:GetDescendants()) do
	if
		object:IsA("BasePart")
		and object.Name == "Tronco"
	then
		registerTrunk(object)
	end
end

TREES_ROOT.DescendantAdded:Connect(function(object)
	if
		object:IsA("BasePart")
		and object.Name == "Tronco"
	then
		task.delay(0.1, function()
			if object.Parent then
				registerTrunk(object)
			end
		end)

	elseif
		object:IsA("ProximityPrompt")
		or object.Name == "Health"
	then
		local trunk = object.Parent

		if
			trunk
			and trunk:IsA("BasePart")
			and trunk.Name == "Tronco"
		then
			task.delay(0.1, function()
				if trunk.Parent then
					registerTrunk(trunk)
				end
			end)
		end
	end
end)

--============================================================
-- DAÑO CENTRAL
--============================================================

RunService.Heartbeat:Connect(function(dt)
	for player, state in pairs(activeChops) do
		local valid =
			player.Parent ~= nil
			and state ~= nil
			and state.treeRoot.Parent ~= nil
			and state.alive

		local axe = nil
		local damage = nil

		if valid then
			axe, damage =
				getEquippedAxe(player)

			if not axe or not damage then
				valid = false
			end
		end

		if
			valid
			and not playerNear(
				player,
				state.trunk
			)
		then
			valid = false
		end

		if not valid then
			activeChops[player] = nil
		else
			--====================================================
			-- V8.7: HABILIDAD ESPECIAL DE LA OVEJA
			--
			-- Solo multiplica la tala si la Oveja real esta afuera.
			-- Cualquier otra mascota da x1.00.
			--====================================================

			local sheepMultiplier =
				getSheepChopMultiplier(
					player
				)

			state.currentHealth -=
				damage
				* sheepMultiplier
				* dt

			state.currentHealth =
				math.clamp(
					state.currentHealth,
					0,
					state.maxHealth
				)

			state.treeRoot:SetAttribute(
				"CurrentTreeHealth",
				state.currentHealth
			)

			if state.health:IsA("NumberValue") then
				state.health.Value =
					state.currentHealth
			else
				state.health.Value =
					math.ceil(
						state.currentHealth
					)
			end

			if state.currentHealth <= 0.001 then
				killTree(state, player)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	activeChops[player] = nil

	activePetByUserId[
	player.UserId
	] = nil

	if woodLoaded[player] then
		saveWoodInventory(
			player
		)
	end

	woodCounts[player] = nil
	woodLoaded[player] = nil
	woodSellLocks[player] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(
		Players:GetPlayers()
		) do
		if woodLoaded[player] then
			saveWoodInventory(
				player
			)
		end
	end
end)

do
	local totalTrees = 0
	local byType = {
		Roble = 0,
		Abeto = 0,
		Abedul = 0,
	}

	for _, state in pairs(stateByTrunk) do
		totalTrees += 1

		local treeType =
			state.treeRoot:GetAttribute("TreeType")

		if byType[treeType] ~= nil then
			byType[treeType] += 1
		end
	end

	print(
		"[TreeChop] CENTRAL V8.9 | tutorial termina despues de entregar madera | HP Roble 100 / Abedul 300 / Abeto 500 + Oveja + Lex | arboles: "
			.. totalTrees
			.. " | Roble: "
			.. byType.Roble
			.. " | Abeto: "
			.. byType.Abeto
			.. " | Abedul: "
			.. byType.Abedul
	)
end