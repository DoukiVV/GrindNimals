--============================================================
-- LEX - TIENDA SERVER V5.1 - HACHAS + VENTA DE MADERA + REGALO TUTORIAL
-- STACKS REALES MAXIMO x99
--
-- UBICACION:
-- ServerScriptService > LexAxeShopServer
--
-- FUNCIONAMIENTO:
-- - Cada compra permite elegir de x1 a x99.
-- - Puedes volver a comprar otras x99 las veces que quieras.
-- - Cada Tool fisico representa un stack maximo de x99.
-- - 203 hachas = 3 Tools: x99 + x99 + x5.
-- - NO crea 203 Tools individuales.
--
-- MIGRACION:
-- - Lee el viejo LexOwnedAxesV1.
-- - Si antes tenias una hacha comprada, migra a cantidad x1.
-- - Guarda las nuevas cantidades en LexAxeStacksV1.
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local ServerStorage = game:GetService("ServerStorage")

local OLD_DATASTORE_NAME = "LexOwnedAxesV1"
local STACK_DATASTORE_NAME = "LexAxeStacksV1"

local STACK_LIMIT = 99
local MAX_BUY_PER_PURCHASE = 99
local MAX_TOTAL_PER_AXE = 9999

local AXES = {
	Wood = {
		DisplayName = "Hacha de madera",
		TemplateName = "Hacha de Madera",
		Price = 100,
	},
	Copper = {
		DisplayName = "Hacha de cobre",
		TemplateName = "Hacha de Cobre",
		Price = 150,
	},
	Iron = {
		DisplayName = "Hacha de Hierro",
		TemplateName = "Hacha de Hierro",
		Price = 300,
	},
	Crystal = {
		DisplayName = "Hacha de cristal turbio",
		TemplateName = "Hacha de Cristal",
		Price = 150,
	},
	Quartz = {
		DisplayName = "Hacha de cuarzo",
		TemplateName = "Hacha de Cuarzo",
		Price = 200,
	},
	Hematite = {
		DisplayName = "Hacha de Hematita",
		TemplateName = "Hacha de Hematita",
		Price = 5000,
	},
	Obsidian = {
		DisplayName = "Hacha de obsidiana",
		TemplateName = "Hacha de Obsidiana",
		Price = 300,
	},
	Serpentine = {
		DisplayName = "Hacha de serpentina",
		TemplateName = "Hacha de Serpentina",
		Price = 150,
	},
}

local AXE_ORDER = {
	"Wood",
	"Copper",
	"Iron",
	"Crystal",
	"Quartz",
	"Hematite",
	"Obsidian",
	"Serpentine",
}


local WOODS = {
	MaderaRoble = {
		DisplayName =
			"Madera Roble",
		TemplateName =
			"MaderaRoble",
		Price = 5,
	},
	MaderaAbedul = {
		DisplayName =
			"Madera Abedul",
		TemplateName =
			"MaderaAbedul",
		Price = 15,
	},
	MaderaAbeto = {
		DisplayName =
			"Madera Abeto",
		TemplateName =
			"MaderaAbeto",
		Price = 30,
	},
}

local WOOD_ORDER = {
	"MaderaRoble",
	"MaderaAbedul",
	"MaderaAbeto",
}

local MAX_SELL_PER_TRANSACTION =
	99

local oldStore =
	DataStoreService:GetDataStore(
		OLD_DATASTORE_NAME
	)

local stackStore =
	DataStoreService:GetDataStore(
		STACK_DATASTORE_NAME
	)

local countCache = {}
local loadedPlayers = {}
local syncingPlayers = {}

--============================================================
-- NORMALIZAR NOMBRE
--============================================================

local function normalizeName(text)
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

local function clampAmount(value)
	return math.clamp(
		math.floor(
			tonumber(value) or 0
		),
		0,
		MAX_TOTAL_PER_AXE
	)
end

--============================================================
-- HACHAS
--============================================================

local axeFolder =
	ReplicatedStorage:WaitForChild(
		"Hachas"
	)

local function findAxeTemplate(templateName)
	local exact =
		axeFolder:FindFirstChild(
			templateName
		)

	if exact then
		return exact
	end

	local wanted =
		normalizeName(
			templateName
		)

	for _, object in ipairs(
		axeFolder:GetChildren()
		) do
		if
			normalizeName(object.Name)
			== wanted
		then
			return object
		end
	end

	return nil
end

local function getAxeIdForTool(tool)
	if
		not tool
		or not tool:IsA("Tool")
	then
		return nil
	end

	local attr =
		tool:GetAttribute(
			"AxeId"
		)

	if
		typeof(attr) == "string"
		and AXES[attr]
	then
		return attr
	end

	local normalized =
		normalizeName(tool.Name)

	for axeId, data in pairs(AXES) do
		local template =
			findAxeTemplate(
				data.TemplateName
			)

		local templateName =
			template
			and template.Name
			or data.TemplateName

		if
			normalizeName(templateName)
			== normalized
		then
			return axeId
		end
	end

	return nil
end

local function getStackAmount(tool)
	local amount =
		tonumber(
			tool:GetAttribute(
				"AxeStackQuantity"
			)
		)
		or tonumber(
			tool:GetAttribute(
				"Cantidad"
			)
		)
		or 1

	return math.clamp(
		math.floor(amount),
		1,
		STACK_LIMIT
	)
end

local function applyAxeAttributes(
	tool,
	axeId,
	amount
)
	local data =
		AXES[axeId]

	if not data then
		return
	end

	amount =
		math.clamp(
			math.floor(
				tonumber(amount) or 1
			),
			1,
			STACK_LIMIT
		)

	tool:SetAttribute(
		"LexAxeManaged",
		true
	)

	tool:SetAttribute(
		"IsAxe",
		true
	)

	tool:SetAttribute(
		"AxeId",
		axeId
	)

	tool:SetAttribute(
		"AxeStackQuantity",
		amount
	)

	tool:SetAttribute(
		"Cantidad",
		amount
	)

	tool:SetAttribute(
		"ItemType",
		"Tool"
	)

	tool:SetAttribute(
		"ItemName",
		data.DisplayName
	)

	tool:SetAttribute(
		"BackpackDisplayName",
		data.DisplayName
	)
end

--============================================================
-- LEX
--============================================================

local lex =
	workspace:FindFirstChild(
		"Lex",
		true
	)

if
	not lex
	or not lex:IsA("Model")
then
	error(
		"[LexAxeShop] No encontre el Model Lex."
	)
end

local humanoid =
	lex:FindFirstChildOfClass(
		"Humanoid"
	)

if humanoid then
	humanoid.DisplayDistanceType =
		Enum.HumanoidDisplayDistanceType.None

	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
end

local promptPart =
	lex:FindFirstChild(
		"HumanoidRootPart"
	)
	or lex:FindFirstChild(
		"UpperTorso"
	)
	or lex:FindFirstChild(
		"Torso"
	)
	or lex:FindFirstChild(
		"Head"
	)
	or lex:FindFirstChildWhichIsA(
		"BasePart"
	)

if not promptPart then
	error(
		"[LexAxeShop] Lex no tiene BasePart para el prompt."
	)
end

for _, object in ipairs(
	lex:GetDescendants()
	) do
	if object:IsA("ProximityPrompt") then
		object:Destroy()
	end
end

local prompt =
	Instance.new(
		"ProximityPrompt"
	)

prompt.Name =
	"LexAxeShopPrompt"

prompt.ActionText =
	"Hablar"

prompt.ObjectText =
	"Lex"

prompt.KeyboardKeyCode =
	Enum.KeyCode.E

prompt.GamepadKeyCode =
	Enum.KeyCode.ButtonX

prompt.HoldDuration =
	0.45

prompt.MaxActivationDistance =
	12

prompt.RequiresLineOfSight =
	false

prompt.Style =
	Enum.ProximityPromptStyle.Custom

prompt.Parent =
	promptPart

--============================================================
-- REMOTES
--============================================================

local oldSystem =
	ReplicatedStorage:FindFirstChild(
		"LexAxeShopSystem"
	)

if oldSystem then
	oldSystem:Destroy()
end

local system =
	Instance.new("Folder")

system.Name =
	"LexAxeShopSystem"

system.Parent =
	ReplicatedStorage

local openShop =
	Instance.new("RemoteEvent")

openShop.Name =
	"OpenShop"

openShop.Parent =
	system

local getShopState =
	Instance.new("RemoteFunction")

getShopState.Name =
	"GetShopState"

getShopState.Parent =
	system

local buyAxe =
	Instance.new("RemoteFunction")

buyAxe.Name =
	"BuyAxe"

buyAxe.Parent =
	system


local sellWood =
	Instance.new(
		"RemoteFunction"
	)

sellWood.Name =
	"SellWood"

sellWood.Parent =
	system

--============================================================
-- DINERO
--============================================================

local MONEY_NAMES = {
	"Dolares",
	"Dólares",
	"Dollars",
	"Cash",
	"Money",
	"Dinero",
	"Monedas",
}

local function findMoneyValue(player)
	local containers = {
		player:FindFirstChild(
			"leaderstats"
		),
		player:FindFirstChild(
			"Stats"
		),
		player:FindFirstChild(
			"Data"
		),
		player,
	}

	for _, container in ipairs(
		containers
		) do
		if container then
			for _, name in ipairs(
				MONEY_NAMES
				) do
				local value =
					container:FindFirstChild(
						name
					)

				if
					value
					and (
						value:IsA(
							"IntValue"
						)
							or value:IsA(
								"NumberValue"
							)
					)
				then
					return value
				end
			end
		end
	end

	return nil
end

--============================================================
-- GUARDADO
--============================================================

local function sanitizeCounts(raw)
	local source =
		typeof(raw) == "table"
		and (
			typeof(raw.Counts)
			== "table"
			and raw.Counts
			or raw
		)
		or {}

	local result = {}

	for axeId in pairs(AXES) do
		local value =
			source[axeId]

		if value == true then
			result[axeId] = 1
		else
			local amount =
				clampAmount(value)

			if amount > 0 then
				result[axeId] =
					amount
			end
		end
	end

	return result
end

local function saveCounts(player)
	local counts =
		countCache[player]

	if not counts then
		return false
	end

	local payload = {
		Version = 1,
		Counts = {},
		UpdatedAt = os.time(),
	}

	for axeId in pairs(AXES) do
		local amount =
			clampAmount(
				counts[axeId]
			)

		if amount > 0 then
			payload.Counts[axeId] =
				amount
		end
	end

	local success, err =
		pcall(function()
			stackStore:SetAsync(
				"Player_"
				.. player.UserId,
				payload
			)
		end)

	if not success then
		warn(
			"[LexAxeShop] Error guardando stacks:",
			player.Name,
			err
		)

		return false
	end

	return true
end

local function loadCounts(player)
	if loadedPlayers[player] then
		return
	end

	local key =
		"Player_"
		.. player.UserId

	local successNew, rawNew =
		pcall(function()
			return
			stackStore:GetAsync(
				key
			)
		end)

	local counts = {}
	local migrated = false

	if
		successNew
		and typeof(rawNew) == "table"
	then
		counts =
			sanitizeCounts(
				rawNew
			)
	elseif not successNew then
		warn(
			"[LexAxeShop] Error cargando stacks:",
			player.Name,
			rawNew
		)
	end

	-- Si V4 aún no tiene datos, migrar V3 booleano -> x1.
	if
		next(counts) == nil
	then
		local successOld, rawOld =
			pcall(function()
				return
				oldStore:GetAsync(
					key
				)
			end)

		if
			successOld
			and typeof(rawOld)
			== "table"
		then
			for axeId, value in pairs(
				rawOld
				) do
				if
					AXES[axeId]
					and value == true
				then
					counts[axeId] =
						1

					migrated =
						true
				end
			end
		elseif not successOld then
			warn(
				"[LexAxeShop] Error leyendo V3 para migrar:",
				player.Name,
				rawOld
			)
		end
	end

	countCache[player] =
		counts

	loadedPlayers[player] =
		true

	if migrated then
		task.spawn(
			saveCounts,
			player
		)
	end
end

--============================================================
-- STACKS FISICOS
--============================================================

local function clearStarterGearAxes(
	player,
	axeId
)
	local starterGear =
		player:FindFirstChild(
			"StarterGear"
		)

	if not starterGear then
		return
	end

	for _, child in ipairs(
		starterGear:GetChildren()
		) do
		if
			child:IsA("Tool")
			and getAxeIdForTool(child)
			== axeId
		then
			child:Destroy()
		end
	end
end

local function collectPlayerAxeTools(
	player,
	axeId
)
	local tools = {}

	local character =
		player.Character

	local backpack =
		player:FindFirstChildOfClass(
			"Backpack"
		)

	local function add(container)
		if not container then
			return
		end

		for _, child in ipairs(
			container:GetChildren()
			) do
			if
				child:IsA("Tool")
				and getAxeIdForTool(
					child
				) == axeId
			then
				table.insert(
					tools,
					child
				)
			end
		end
	end

	-- Character primero para conservar el stack que está en la mano.
	add(character)
	add(backpack)

	return tools
end

local function syncAxeStacks(
	player,
	axeId
)
	local data =
		AXES[axeId]

	if not data then
		return false
	end

	local backpack =
		player:FindFirstChildOfClass(
			"Backpack"
		)

	if not backpack then
		return false
	end

	local template =
		findAxeTemplate(
			data.TemplateName
		)

	if
		not template
		or not template:IsA("Tool")
	then
		warn(
			"[LexAxeShop] No encontre Tool:",
			data.TemplateName
		)

		return false
	end

	local counts =
		countCache[player]
		or {}

	local target =
		clampAmount(
			counts[axeId]
		)

	local existing =
		collectPlayerAxeTools(
			player,
			axeId
		)

	local needed =
		target > 0
		and math.ceil(
			target / STACK_LIMIT
		)
		or 0

	for index = 1, needed do
		local amount =
			math.min(
				STACK_LIMIT,
				target
				- (
					(index - 1)
					* STACK_LIMIT
				)
			)

		local tool =
			existing[index]

		if
			not tool
			or not tool.Parent
		then
			tool =
				template:Clone()

			tool.Parent =
				backpack
		end

		applyAxeAttributes(
			tool,
			axeId,
			amount
		)
	end

	for index = needed + 1, #existing do
		local tool =
			existing[index]

		if tool and tool.Parent then
			tool:Destroy()
		end
	end

	clearStarterGearAxes(
		player,
		axeId
	)

	return true
end

local function syncAllAxeStacks(player)
	if syncingPlayers[player] then
		return
	end

	if not loadedPlayers[player] then
		return
	end

	local backpack =
		player:FindFirstChildOfClass(
			"Backpack"
		)

	if not backpack then
		return
	end

	syncingPlayers[player] =
		true

	for _, axeId in ipairs(
		AXE_ORDER
		) do
		syncAxeStacks(
			player,
			axeId
		)
	end

	syncingPlayers[player] =
		nil
end

--============================================================
-- BRIDGE DE MADERA
--============================================================

local function getWoodBridgeFunction(
	functionName
)
	local bridge =
		ServerStorage:FindFirstChild(
			"TreeWoodBridge"
		)

	if not bridge then
		bridge =
			ServerStorage:WaitForChild(
				"TreeWoodBridge",
				5
			)
	end

	if not bridge then
		return nil
	end

	local fn =
		bridge:FindFirstChild(
			functionName
		)

	if
		fn
		and fn:IsA(
			"BindableFunction"
		)
	then
		return fn
	end

	return nil
end

local function getWoodCounts(
	player
)
	local fn =
		getWoodBridgeFunction(
			"GetWoodState"
		)

	if not fn then
		return {
			MaderaRoble = 0,
			MaderaAbedul = 0,
			MaderaAbeto = 0,
		}
	end

	local ok, result =
		pcall(function()
			return fn:Invoke(
				player
			)
		end)

	if
		not ok
		or typeof(result)
		~= "table"
		or typeof(result.Counts)
		~= "table"
	then
		return {
			MaderaRoble = 0,
			MaderaAbedul = 0,
			MaderaAbeto = 0,
		}
	end

	return result.Counts
end

--============================================================
-- PUENTE TUTORIAL - PRIMERA HACHA GRATIS
--============================================================

local tutorialAxeBusy = {}

local function getTutorialActionCompleted()
	local tutorialSystem = ReplicatedStorage:FindFirstChild("TutorialSystem")
	local tutorialRemotes = tutorialSystem and tutorialSystem:FindFirstChild("Remotes")
	local action = tutorialRemotes and tutorialRemotes:FindFirstChild("ActionCompleted")
	if action and action:IsA("BindableEvent") then
		return action
	end
	return nil
end

local function fireTutorialAction(player, actionName, payload)
	local action = getTutorialActionCompleted()
	if action then
		action:Fire(player, actionName, payload or {})
		return true
	end
	return false
end

local function isTutorialFreeAxeEligible(player)
	if not player or player.Parent ~= Players then
		return false
	end

	-- Si el tutorial ya registro el regalo, Lex vuelve a funcionar normal.
	if player:GetAttribute("FreeStarterAxeClaimed") == true then
		return false
	end

	local tutorialStep =
		tostring(
			player:GetAttribute("TutorialStep")
			or ""
		)

	-- RESERVE_TALK_LEX es el paso actual del tutorial V6.15+.
	-- Los otros dos se conservan por compatibilidad con progreso viejo.
	return
		tutorialStep == "RESERVE_TALK_LEX"
		or tutorialStep == "LEX_FREE_AXE"
		or tutorialStep == "RESERVE_ENTER_SHOP"
end

local function grantTutorialWoodAxe(player)
	if not isTutorialFreeAxeEligible(player) then
		return false
	end

	if tutorialAxeBusy[player] then
		return true
	end

	tutorialAxeBusy[player] = true

	loadCounts(player)

	local counts =
		countCache[player]
		or {}

	local current =
		clampAmount(
			counts.Wood
		)

	-- Primer regalo del tutorial:
	-- si ya existe una Hacha de Madera por datos de pruebas anteriores,
	-- NO duplicamos el Tool, pero sí dejamos que el tutorial continúe.
	if current <= 0 then
		counts.Wood = 1
		countCache[player] = counts

		local synced =
			syncAxeStacks(
				player,
				"Wood"
			)

		if not synced then
			counts.Wood = 0
			tutorialAxeBusy[player] = nil

			warn(
				"[LexAxeShop/Tutorial] No pude entregar Hacha de Madera a",
				player.Name
			)

			return false
		end

		task.spawn(
			saveCounts,
			player
		)

		print(
			"[LexAxeShop/Tutorial] REGALO DE BIENVENIDA: Hacha de Madera GRATIS ->",
			player.Name
		)
	else
		print(
			"[LexAxeShop/Tutorial] Ya tenia Hacha de Madera; no se duplica:",
			player.Name
		)
	end

	-- Dejamos que la tienda alcance a abrirse y que TutorialServer
	-- procese el Prompt de Lex. Luego confirmamos el regalo.
	task.delay(
		0.35,
		function()
			if player.Parent == Players then
				fireTutorialAction(
					player,
					"FREE_AXE_CLAIMED",
					{
						AxeId = "Wood",
						Free = true,
						Source = "LexFirstShopOpen",
					}
				)
			end

			tutorialAxeBusy[player] = nil
		end
	)

	return true
end

Players.PlayerRemoving:Connect(function(player)
	tutorialAxeBusy[player] = nil
end)

--============================================================
-- TIENDA
--============================================================

prompt.Triggered:Connect(
	function(player)
		loadCounts(player)

		-- V6.16:
		-- La PRIMERA vez que el tutorial abre la tienda de Lex:
		-- 1) se entrega Hacha de Madera gratis;
		-- 2) la tienda SI se abre;
		-- 3) el tutorial avanza después de confirmar el regalo.
		--
		-- En visitas posteriores Lex funciona como tienda normal.
		grantTutorialWoodAxe(player)

		openShop:FireClient(
			player
		)
	end
)

getShopState.OnServerInvoke =
	function(player)
		loadCounts(player)

		local money =
		findMoneyValue(
			player
		)

		local items = {}
		local counts =
		countCache[player]
		or {}

		local woodItems = {}
		local woodCounts =
		getWoodCounts(
			player
		)

		for order, axeId in ipairs(
			AXE_ORDER
			) do
			local data =
			AXES[axeId]

			local template =
			findAxeTemplate(
				data.TemplateName
			)

			local ownedCount =
			clampAmount(
				counts[axeId]
			)

			table.insert(
				items,
				{
					Id = axeId,
					Order = order,
					DisplayName =
					data.DisplayName,
					TemplateName =
					template
					and template.Name
					or data.TemplateName,
					Price =
					data.Price,
					Owned =
					ownedCount > 0,
					OwnedCount =
					ownedCount,
					Available =
					template ~= nil
					and template:IsA(
						"Tool"
					),
					MaxBuy =
					MAX_BUY_PER_PURCHASE,
					StackLimit =
					STACK_LIMIT,
				}
			)
		end

		for order, woodId in ipairs(
			WOOD_ORDER
			) do
			local data =
			WOODS[woodId]

			local ownedCount =
			math.max(
				0,
				math.floor(
					tonumber(
						woodCounts[
						woodId
						]
					)
					or 0
				)
			)

			table.insert(
				woodItems,
				{
					Id =
					woodId,
					Order =
					order,
					DisplayName =
					data.DisplayName,
					TemplateName =
					data.TemplateName,
					Price =
					data.Price,
					OwnedCount =
					ownedCount,
					Available =
					true,
					MaxSell =
					MAX_SELL_PER_TRANSACTION,
				}
			)
		end

		return {
			Dollars =
			money
			and money.Value
			or 0,
			Items =
			items,
			WoodItems =
			woodItems,
			MaxBuy =
			MAX_BUY_PER_PURCHASE,
			StackLimit =
			STACK_LIMIT,
			MaxSell =
			MAX_SELL_PER_TRANSACTION,
		}
	end

buyAxe.OnServerInvoke =
	function(
		player,
		axeId,
		requestedAmount
	)
	local data =
		type(axeId) == "string"
		and AXES[axeId]
		or nil

	if not data then
		return {
			Success = false,
			Message =
				"Hacha no valida.",
		}
	end

	loadCounts(player)

	local amount =
		math.floor(
			tonumber(
				requestedAmount
			)
			or 1
		)

	if
		amount < 1
		or amount
		> MAX_BUY_PER_PURCHASE
	then
		return {
			Success = false,
			Message =
				"Puedes comprar de x1 a x99 por vez.",
		}
	end

	local template =
		findAxeTemplate(
			data.TemplateName
		)

	if
		not template
		or not template:IsA("Tool")
	then
		return {
			Success = false,
			Message =
				"No encontre el Tool de esta hacha.",
		}
	end

	local counts =
		countCache[player]

	local current =
		clampAmount(
			counts[axeId]
		)

	if
		current + amount
		> MAX_TOTAL_PER_AXE
	then
		return {
			Success = false,
			Message =
				"Maximo "
				.. tostring(
					MAX_TOTAL_PER_AXE
				)
				.. " de esta hacha.",
			OwnedCount =
				current,
		}
	end

	local money =
		findMoneyValue(
			player
		)

	if not money then
		return {
			Success = false,
			Message =
				"No pude encontrar tus dolares.",
		}
	end

	local totalPrice =
		data.Price
		* amount

	if
		money.Value
		< totalPrice
	then
		return {
			Success = false,
			Message =
				"Te faltan $"
				.. tostring(
					totalPrice
					- money.Value
				)
				.. ".",
			Dollars =
				money.Value,
			OwnedCount =
				current,
		}
	end

	money.Value -=
		totalPrice

	counts[axeId] =
		current
		+ amount

	local syncOk =
		syncAxeStacks(
			player,
			axeId
		)

	if not syncOk then
		money.Value +=
			totalPrice

		counts[axeId] =
			current

		syncAxeStacks(
			player,
			axeId
		)

		return {
			Success = false,
			Message =
				"No se pudo entregar el stack de hachas.",
			Dollars =
				money.Value,
			OwnedCount =
				current,
		}
	end

	task.spawn(
		saveCounts,
		player
	)

	local newCount =
		counts[axeId]

	return {
		Success = true,
		Message =
			"Compraste x"
			.. tostring(amount)
			.. " "
			.. data.DisplayName
			.. "!",
		Dollars =
			money.Value,
		OwnedCount =
			newCount,
		BoughtAmount =
			amount,
		TotalPrice =
			totalPrice,
		StackLimit =
			STACK_LIMIT,
	}
end

--============================================================
-- VENDER MADERA
--============================================================

sellWood.OnServerInvoke =
	function(
		player,
		woodId,
		requestedAmount
	)
	local data =
		type(woodId)
		== "string"
		and WOODS[woodId]
		or nil

	if not data then
		return {
			Success = false,
			Message =
				"Madera no valida.",
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
		or amount
		> MAX_SELL_PER_TRANSACTION
	then
		return {
			Success = false,
			Message =
				"Puedes vender de x1 a x99 por vez.",
		}
	end

	local money =
		findMoneyValue(
			player
		)

	if not money then
		return {
			Success = false,
			Message =
				"No pude encontrar tus dolares.",
		}
	end

	local bridge =
		getWoodBridgeFunction(
			"SellWood"
		)

	if not bridge then
		return {
			Success = false,
			Message =
				"El inventario de madera no esta disponible.",
		}
	end

	local ok, woodResult =
		pcall(function()
			return bridge:Invoke(
				player,
				woodId,
				amount
			)
		end)

	if
		not ok
		or typeof(woodResult)
		~= "table"
	then
		return {
			Success = false,
			Message =
				"No se pudo vender la madera.",
		}
	end

	if
		woodResult.Success
		~= true
	then
		return {
			Success = false,
			Message =
				woodResult.Message
				or "No tienes suficiente madera.",
			Dollars =
				money.Value,
			RemainingCount =
				tonumber(
					woodResult.Remaining
				)
				or 0,
		}
	end

	local totalPrice =
		data.Price
		* amount

	money.Value +=
		totalPrice

	return {
		Success = true,
		Message =
			"Vendiste x"
			.. tostring(
				amount
			)
			.. " "
			.. data.DisplayName
			.. " por "
			.. tostring(
				totalPrice
			)
			.. "$.",
		Dollars =
			money.Value,
		RemainingCount =
			tonumber(
				woodResult.Remaining
			)
			or 0,
		SoldAmount =
			amount,
		TotalPrice =
			totalPrice,
	}
end

--============================================================
-- JUGADORES
--============================================================

local function scheduleSync(
	player,
	delayTime
)
	task.delay(
		delayTime or 0.35,
		function()
			if
				player.Parent
				== Players
			then
				syncAllAxeStacks(
					player
				)
			end
		end
	)
end

local function playerAdded(player)
	task.spawn(function()
		loadCounts(player)

		player:WaitForChild(
			"Backpack"
		)

		scheduleSync(
			player,
			0.45
		)
	end)

	player.CharacterAdded:Connect(
		function()
			scheduleSync(
				player,
				0.60
			)
		end
	)

	player.ChildAdded:Connect(
		function(child)
			if child:IsA("Backpack") then
				scheduleSync(
					player,
					0.25
				)
			end
		end
	)
end

for _, player in ipairs(
	Players:GetPlayers()
	) do
	playerAdded(player)
end

Players.PlayerAdded:Connect(
	playerAdded
)

Players.PlayerRemoving:Connect(
	function(player)
		if loadedPlayers[player] then
			saveCounts(player)
		end

		countCache[player] = nil
		loadedPlayers[player] = nil
		syncingPlayers[player] = nil
	end
)

game:BindToClose(function()
	for _, player in ipairs(
		Players:GetPlayers()
		) do
		if loadedPlayers[player] then
			saveCounts(player)
		end
	end
end)

print(
	"[LexAxeShop] V5 activo | compra hachas + venta madera | Roble $5 | Abedul $15 | Abeto $30."
)
