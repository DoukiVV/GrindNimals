--[[
    TradeServer_V6_4_STACKS_X99.lua
    Ubicacion: ServerScriptService > TradeServer
    Tipo: Script

    Sistema de intercambio SERVER-AUTHORITATIVE.

    Seguridad:
    - El cliente nunca entrega/quita objetos por su cuenta.
    - Toda oferta se valida contra el inventario REAL del servidor.
    - UID para herramientas y stacks de mascotas.
    - Semillas SeedSaveV9, frutas, madera/troncos y herramientas.
    - Las mascotas se muestran por tier en el cliente usando modelos 3D.
    - Cada cambio invalida las dos confirmaciones.
    - Bloqueo de 3 s despues de cada cambio.
    - Cuando ambos aceptan hay un segundo conteo final de seguridad de 3 s.
    - Durante ese conteo la oferta queda congelada.
    - Revalidacion + escrow + rollback antes del commit.
    - Anti-spam de solicitudes y acciones.

    Remotes creados automaticamente en ReplicatedStorage > TradeSystem:
    RequestTrade, RespondTrade, TradeAction, TradeUpdate, TradeNotify,
    SetTradeEnabled, PlayerListUpdate, GetInventorySnapshot, GetTradePlayers
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

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


--============================================================
-- CONFIG
--============================================================

local MAX_SLOTS = 9
local MAX_STACK_OFFER = 9999
local MAX_PET_OFFER = 99
local INVENTORY_STACK_LIMIT = 99

local CHANGE_LOCK_SECONDS = 3
local FINAL_SECURITY_SECONDS = 3
local REQUEST_TIMEOUT = 10
local REQUEST_COOLDOWN = 2
local PAIR_REQUEST_COOLDOWN = 20
local ACTION_COOLDOWN = 0.07

local TRADE_UID_ATTR = "TradeUID"
local TRADE_ENABLED_ATTR = "TradeEnabled"

local function serverNow()
	return workspace:GetServerTimeNow()
end

--============================================================
-- REMOTES
--============================================================

local tradeFolder = ReplicatedStorage:FindFirstChild("TradeSystem")
if tradeFolder and not tradeFolder:IsA("Folder") then
	tradeFolder:Destroy()
	tradeFolder = nil
end

if not tradeFolder then
	tradeFolder = Instance.new("Folder")
	tradeFolder.Name = "TradeSystem"
	tradeFolder.Parent = ReplicatedStorage
end

local function ensureRemoteEvent(name)
	local remote = tradeFolder:FindFirstChild(name)
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = tradeFolder
	end
	return remote
end

local function ensureRemoteFunction(name)
	local remote = tradeFolder:FindFirstChild(name)
	if remote and not remote:IsA("RemoteFunction") then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = tradeFolder
	end
	return remote
end

local RequestTrade = ensureRemoteEvent("RequestTrade")
local RespondTrade = ensureRemoteEvent("RespondTrade")
local TradeAction = ensureRemoteEvent("TradeAction")
local TradeUpdate = ensureRemoteEvent("TradeUpdate")
local TradeNotify = ensureRemoteEvent("TradeNotify")
local SetTradeEnabled = ensureRemoteEvent("SetTradeEnabled")
local PlayerListUpdate = ensureRemoteEvent("PlayerListUpdate")
local GetInventorySnapshot = ensureRemoteFunction("GetInventorySnapshot")
local GetTradePlayers = ensureRemoteFunction("GetTradePlayers")

--============================================================
-- ESTADO
--============================================================

local sessionsByUserId = {}
local pendingBySenderId = {}
local pendingByTargetId = {}
local lastRequestAt = {}
local lastActionAt = {}
local pairCooldownUntil = {}

--============================================================
-- HELPERS GENERALES
--============================================================

local function trim(value)
	return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function normalize(value)
	local text = trim(value):lower()
	text = text:gsub("á", "a")
	text = text:gsub("é", "e")
	text = text:gsub("í", "i")
	text = text:gsub("ó", "o")
	text = text:gsub("ú", "u")
	text = text:gsub("ü", "u")
	text = text:gsub("ñ", "n")
	text = text:gsub("[%s_%-]+", "")
	return text
end

local function notify(player, kind, data)
	if player and player.Parent == Players then
		TradeNotify:FireClient(player, kind, data or {})
	end
end

local function firePlayerListUpdate()
	PlayerListUpdate:FireAllClients()
end


local function compactOfferSlots(offer)
	if typeof(offer) ~= "table" then
		return offer
	end

	local compacted = {}
	local writeIndex = 1

	for readIndex = 1, MAX_SLOTS do
		local item = offer[readIndex]
		if item then
			compacted[writeIndex] = item
			writeIndex += 1
		end
	end

	for i = writeIndex, MAX_SLOTS do
		compacted[i] = false
	end

	for i = 1, MAX_SLOTS do
		offer[i] = compacted[i]
	end

	return offer
end

local function rateLimit(bucket, key, cooldown)
	local now = serverNow()
	local previous = bucket[key] or 0
	if now - previous < cooldown then
		return false, math.max(0, cooldown - (now - previous))
	end
	bucket[key] = now
	return true, 0
end

local function ensureUid(instance)
	local uid = instance:GetAttribute(TRADE_UID_ATTR)
	if typeof(uid) ~= "string" or uid == "" then
		uid = HttpService:GenerateGUID(false)
		instance:SetAttribute(TRADE_UID_ATTR, uid)
	end
	return uid
end

local function pairKey(a, b)
	a = math.floor(tonumber(a) or 0)
	b = math.floor(tonumber(b) or 0)
	if a > b then
		a, b = b, a
	end
	return tostring(a) .. ":" .. tostring(b)
end

local function isTradeLockedInstance(instance)
	if not instance then
		return true
	end
	if instance:GetAttribute("TradeLocked") == true then
		return true
	end
	if instance:GetAttribute("Untradeable") == true then
		return true
	end
	if instance:GetAttribute("CanTrade") == false then
		return true
	end
	return false
end

local function getTradeContainers(player)
	local result = {}
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		table.insert(result, backpack)
	end
	if player.Character then
		table.insert(result, player.Character)
	end
	return result
end

local function findToolByUid(player, uid)
	if typeof(uid) ~= "string" or uid == "" then
		return nil
	end
	for _, container in ipairs(getTradeContainers(player)) do
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute(TRADE_UID_ATTR) == uid then
				return child
			end
		end
	end
	return nil
end

--============================================================
-- HERRAMIENTAS APILADAS (HACHAS x99)
--============================================================

local function isAxeStackTool(tool)
	return tool
		and tool:IsA("Tool")
		and (
			tool:GetAttribute("IsAxe") == true
			or tool:GetAttribute("AxeStackQuantity") ~= nil
		)
end

local function getAxeStackAmount(tool)
	if not isAxeStackTool(tool) then
		return 1
	end

	return math.clamp(
		math.floor(
			tonumber(tool:GetAttribute("AxeStackQuantity"))
				or tonumber(tool:GetAttribute("Cantidad"))
				or 1
		),
		1,
		INVENTORY_STACK_LIMIT
	)
end

local function setAxeStackAmount(tool, amount)
	if not tool or not tool:IsA("Tool") then
		return
	end

	amount = math.clamp(
		math.floor(tonumber(amount) or 1),
		1,
		INVENTORY_STACK_LIMIT
	)

	tool:SetAttribute("AxeStackQuantity", amount)
	tool:SetAttribute("Cantidad", amount)
end

local function getTradeToolStackAmount(tool)
	if isAxeStackTool(tool) then
		return getAxeStackAmount(tool)
	end
	return 1
end

local function setTradeToolStackAmount(tool, amount)
	if isAxeStackTool(tool) then
		setAxeStackAmount(tool, amount)
	end
end


local function getImageFromInstance(instance)
	if not instance then
		return ""
	end
	if instance:IsA("Tool") then
		return instance.TextureId or ""
	end
	for _, attr in ipairs({"Icon", "Image", "ImageId", "TextureId"}) do
		local value = instance:GetAttribute(attr)
		if typeof(value) == "string" and value ~= "" then
			return value
		end
	end
	for _, childName in ipairs({"Icon", "Image"}) do
		local child = instance:FindFirstChild(childName)
		if child and child:IsA("StringValue") and child.Value ~= "" then
			return child.Value
		end
	end
	return ""
end

--============================================================
-- SEMILLAS / STACKS V9
--============================================================

local itemFolder = ServerStorage:FindFirstChild("Item")
local seedFolder = itemFolder and itemFolder:FindFirstChild("Semillas")
local seedTemplateByKey = {}
local seedAliasToKey = {}

local function seedDisplayName(tool)
	local display = tool and tool:GetAttribute("BackpackDisplayName")
	if typeof(display) == "string" and trim(display) ~= "" then
		return trim(display)
	end
	local itemName = tool and tool:GetAttribute("ItemName")
	if typeof(itemName) == "string" and trim(itemName) ~= "" then
		return trim(itemName)
	end
	return tool and tool.Name or "Semilla"
end

local function canonicalSeedKeyFromTemplate(tool)
	local crop = tool:GetAttribute("SeedCropName")
	if typeof(crop) == "string" and trim(crop) ~= "" then
		return trim(crop)
	end
	local itemName = tool:GetAttribute("ItemName")
	if typeof(itemName) == "string" and trim(itemName) ~= "" then
		return trim(itemName)
	end
	return tool.Name
end

local function rebuildSeedIndex()
	table.clear(seedTemplateByKey)
	table.clear(seedAliasToKey)
	if not seedFolder then
		return
	end

	for _, tool in ipairs(seedFolder:GetDescendants()) do
		if tool:IsA("Tool") then
			local key = canonicalSeedKeyFromTemplate(tool)
			seedTemplateByKey[key] = seedTemplateByKey[key] or tool

			local aliases = {
				key,
				tool.Name,
				tool:GetAttribute("ItemName"),
				tool:GetAttribute("SeedCropName"),
				tool:GetAttribute("BackpackDisplayName"),
			}
			for _, alias in ipairs(aliases) do
				if typeof(alias) == "string" and trim(alias) ~= "" then
					seedAliasToKey[normalize(alias)] = key
					local stripped = normalize(alias)
					if stripped:sub(1, 9) == "semillade" then
						seedAliasToKey[stripped:sub(10)] = key
					elseif stripped:sub(1, 7) == "semilla" then
						seedAliasToKey[stripped:sub(8)] = key
					end
				end
			end
		end
	end
end

rebuildSeedIndex()
if seedFolder then
	seedFolder.DescendantAdded:Connect(function()
		task.defer(rebuildSeedIndex)
	end)
	seedFolder.DescendantRemoving:Connect(function()
		task.defer(rebuildSeedIndex)
	end)
end

local function seedKeyFromValue(value)
	if typeof(value) ~= "string" or trim(value) == "" then
		return nil
	end
	local n = normalize(value)
	local direct = seedAliasToKey[n]
	if direct then
		return direct
	end
	if n:sub(1, 9) == "semillade" then
		return seedAliasToKey[n:sub(10)]
	elseif n:sub(1, 7) == "semilla" then
		return seedAliasToKey[n:sub(8)]
	end
	return nil
end

local function seedKeyFromTool(tool)
	if not tool or not tool:IsA("Tool") then
		return nil
	end

	for _, value in ipairs({
		tool:GetAttribute("SeedCropName"),
		tool:GetAttribute("ItemName"),
		tool:GetAttribute("BackpackDisplayName"),
		tool.Name,
		}) do
		local key = seedKeyFromValue(value)
		if key then
			return key
		end
	end

	if tool:GetAttribute("IsSeed") == true then
		local crop = tool:GetAttribute("SeedCropName")
		if typeof(crop) == "string" and trim(crop) ~= "" then
			return trim(crop)
		end
	end

	return nil
end

local function getSeedStackAmount(tool)
	return math.clamp(
		math.floor(
			tonumber(tool:GetAttribute("SeedStackQuantity"))
				or tonumber(tool:GetAttribute("Cantidad"))
				or 1
		),
		1,
		99
	)
end

local function setSeedStackAmount(tool, amount)
	amount = math.clamp(math.floor(tonumber(amount) or 1), 1, 99)
	tool:SetAttribute("SeedStackQuantity", amount)
	tool:SetAttribute("Cantidad", amount)
end

local function findSeedTools(player, key)
	local result = {}
	for _, container in ipairs(getTradeContainers(player)) do
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and seedKeyFromTool(child) == key then
				table.insert(result, child)
			end
		end
	end
	return result
end

local function countSeed(player, key)
	local total = 0
	for _, tool in ipairs(findSeedTools(player, key)) do
		total += getSeedStackAmount(tool)
	end
	return total
end


--============================================================
-- FRUTAS
--============================================================

local fruitFolder = itemFolder and itemFolder:FindFirstChild("Frutas")
local fruitTemplateByKey = {}
local fruitAliasToKey = {}

local function canonicalFruitKeyFromTemplate(tool)
	local itemName = tool:GetAttribute("ItemName")
	if typeof(itemName) == "string" and trim(itemName) ~= "" then
		return trim(itemName)
	end
	return trim(tool.Name)
end

local function rebuildFruitIndex()
	table.clear(fruitTemplateByKey)
	table.clear(fruitAliasToKey)

	if not fruitFolder then
		return
	end

	for _, tool in ipairs(fruitFolder:GetDescendants()) do
		if tool:IsA("Tool") then
			local key = canonicalFruitKeyFromTemplate(tool)
			fruitTemplateByKey[key] = fruitTemplateByKey[key] or tool

			for _, alias in ipairs({
				key,
				tool.Name,
				tool:GetAttribute("ItemName"),
				tool:GetAttribute("BackpackDisplayName"),
				}) do
				if typeof(alias) == "string" and trim(alias) ~= "" then
					fruitAliasToKey[normalize(alias)] = key
				end
			end
		end
	end
end

rebuildFruitIndex()

if fruitFolder then
	fruitFolder.DescendantAdded:Connect(function()
		task.defer(rebuildFruitIndex)
	end)

	fruitFolder.DescendantRemoving:Connect(function()
		task.defer(rebuildFruitIndex)
	end)
end

local function fruitKeyFromValue(value)
	if typeof(value) ~= "string" or trim(value) == "" then
		return nil
	end
	return fruitAliasToKey[normalize(value)]
end

local function fruitKeyFromTool(tool)
	if not tool or not tool:IsA("Tool") then
		return nil
	end

	if tool:GetAttribute("IsFruit") == true then
		local direct =
			fruitKeyFromValue(tool:GetAttribute("ItemName"))
			or fruitKeyFromValue(tool.Name)

		if direct then
			return direct
		end
	end

	for _, value in ipairs({
		tool:GetAttribute("ItemName"),
		tool:GetAttribute("BackpackDisplayName"),
		tool.Name,
		}) do
		local key = fruitKeyFromValue(value)
		if key then
			return key
		end
	end

	return nil
end

local function findFruitTools(player, key)
	local result = {}

	for _, container in ipairs(getTradeContainers(player)) do
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool")
				and fruitKeyFromTool(child) == key
				and not isTradeLockedInstance(child)
			then
				table.insert(result, child)
			end
		end
	end

	return result
end

local function getFruitStackAmount(tool)
	if not tool or not tool:IsA("Tool") then
		return 0
	end

	return math.clamp(
		math.floor(
			tonumber(tool:GetAttribute("FruitStackQuantity"))
				or tonumber(tool:GetAttribute("Cantidad"))
				or 1
		),
		1,
		INVENTORY_STACK_LIMIT
	)
end

local function setFruitStackAmount(tool, amount)
	if not tool or not tool:IsA("Tool") then
		return
	end

	amount = math.clamp(
		math.floor(tonumber(amount) or 1),
		1,
		INVENTORY_STACK_LIMIT
	)

	tool:SetAttribute("FruitStackQuantity", amount)
	tool:SetAttribute("Cantidad", amount)
end

local function countFruit(player, key)
	local total = 0
	for _, tool in ipairs(findFruitTools(player, key)) do
		total += getFruitStackAmount(tool)
	end
	return total
end

local function fruitDisplayName(template, key)
	if template then
		local pretty =
			template:GetAttribute("BackpackDisplayName")
			or template:GetAttribute("ItemName")

		if typeof(pretty) == "string" and trim(pretty) ~= "" then
			return trim(pretty)
		end
	end

	return tostring(key or "Fruta")
end

--============================================================
-- MADERA / TRONCOS
--
-- TreeChopServer V8.9 expone:
-- ServerStorage > TreeWoodBridge > GetWoodState / TransferWood
--
-- La madera NO se mueve manipulando Tools directamente porque
-- TreeChop mantiene un cache autoritativo propio.
--============================================================

local WOOD_TYPES = {
	MaderaRoble = "Madera Roble",
	MaderaAbedul = "Madera Abedul",
	MaderaAbeto = "Madera Abeto",
}

local function woodTypeFromTool(tool)
	if not tool or not tool:IsA("Tool") then
		return nil
	end

	local forced = tool:GetAttribute("WoodType")
	if typeof(forced) == "string" and WOOD_TYPES[forced] then
		return forced
	end

	if tool:GetAttribute("EsMadera") == true then
		local n = normalize(tool:GetAttribute("ItemName") or tool.Name)
		if n == "maderaroble" then
			return "MaderaRoble"
		elseif n == "maderaabedul" then
			return "MaderaAbedul"
		elseif n == "maderaabeto" then
			return "MaderaAbeto"
		end
	end

	local n = normalize(tool:GetAttribute("ItemName") or tool.Name)
	if n == "maderaroble" then
		return "MaderaRoble"
	elseif n == "maderaabedul" then
		return "MaderaAbedul"
	elseif n == "maderaabeto" then
		return "MaderaAbeto"
	end

	return nil
end

local function getWoodBridge()
	local folder = ServerStorage:FindFirstChild("TreeWoodBridge")
	if not folder or not folder:IsA("Folder") then
		return nil
	end

	local getState = folder:FindFirstChild("GetWoodState")
	local transfer = folder:FindFirstChild("TransferWood")

	if not getState or not getState:IsA("BindableFunction") then
		return nil
	end

	return folder, getState, transfer
end

local function getWoodCounts(player)
	local _, getState = getWoodBridge()

	if not getState then
		return {
			MaderaRoble = 0,
			MaderaAbedul = 0,
			MaderaAbeto = 0,
		}
	end

	local ok, result = pcall(function()
		return getState:Invoke(player)
	end)

	if not ok or typeof(result) ~= "table" or result.Success ~= true then
		return {
			MaderaRoble = 0,
			MaderaAbedul = 0,
			MaderaAbeto = 0,
		}
	end

	local counts = typeof(result.Counts) == "table" and result.Counts or {}

	return {
		MaderaRoble = math.max(0, math.floor(tonumber(counts.MaderaRoble) or 0)),
		MaderaAbedul = math.max(0, math.floor(tonumber(counts.MaderaAbedul) or 0)),
		MaderaAbeto = math.max(0, math.floor(tonumber(counts.MaderaAbeto) or 0)),
	}
end

local function transferWood(sender, receiver, woodType, amount)
	local _, _, transfer = getWoodBridge()

	if not transfer or not transfer:IsA("BindableFunction") then
		return false, "TreeChopServer V8.9 es necesario para tradear madera."
	end

	local ok, result = pcall(function()
		return transfer:Invoke(sender, receiver, woodType, amount)
	end)

	if not ok then
		return false, tostring(result)
	end

	if typeof(result) ~= "table" or result.Success ~= true then
		return false,
			typeof(result) == "table"
			and tostring(result.Message or "No se pudo transferir la madera.")
			or "No se pudo transferir la madera."
	end

	return true
end

local function getWoodIcon(woodType)
	local wanted = normalize(WOOD_TYPES[woodType] or woodType)

	for _, object in ipairs(ReplicatedStorage:GetChildren()) do
		if object:IsA("Tool")
			and normalize(object:GetAttribute("ItemName") or object.Name) == wanted
		then
			return object.TextureId or ""
		end
	end

	return ""
end

--============================================================
-- MASCOTAS / STACK POR PAÑUELO
--============================================================

local TIER_ORDER = {
	Base = 1,
	Comun = 2,
	["Poco comun"] = 3,
	Raro = 4,
	Epico = 5,
	Legendario = 6,
}

local function normalizeTier(value)
	local n = normalize(value)
	if n == "comun" then return "Comun" end
	if n == "pococomun" then return "Poco comun" end
	if n == "raro" then return "Raro" end
	if n == "epico" then return "Epico" end
	if n == "legendario" then return "Legendario" end
	return "Base"
end


-- Mascotas reales que existen en el sistema del juego.
local VALID_TRADE_PETS = {
	perro = true,
	gato = true,
	conejo = true,
	perico = true,
	pajarillo = true,
	tortuga = true,
	hamster = true,
	huron = true,
	pezdorado = true,
	oveja = true,
	ovejaderosario = true,
	huevomascota = true,
	huevobrizabelle = true,
}

local VALID_PET_TIERS = {
	Base = true,
	Comun = true,
	["Poco comun"] = true,
	Raro = true,
	Epico = true,
	Legendario = true,
}

local function isKnownTradePet(petName, tier)
	return VALID_TRADE_PETS[normalize(petName)] == true
		and VALID_PET_TIERS[normalizeTier(tier)] == true
end

local function getPetContainer(player, createIfMissing)
	local folder = player:FindFirstChild("TradePetsInventory")
	if folder and folder:IsA("Folder") then
		return folder
	end
	if createIfMissing then
		folder = Instance.new("Folder")
		folder.Name = "TradePetsInventory"
		folder.Parent = player
		return folder
	end
	return nil
end

local function getPetName(value)
	local itemName = value:GetAttribute("ItemName")
	if typeof(itemName) == "string" and trim(itemName) ~= "" then
		return trim(itemName)
	end
	return trim(value.Name)
end

local function getPetTier(value)
	return normalizeTier(value:GetAttribute("UpgradeTier") or "Base")
end

local function getPetRecords(player)
	local records = {}
	local folder = getPetContainer(player, false)
	if not folder then
		return records
	end

	for _, value in ipairs(folder:GetChildren()) do
		if (value:IsA("IntValue") or value:IsA("NumberValue")) and value.Value > 0 then
			local petName = getPetName(value)
			local tier = getPetTier(value)

			if isKnownTradePet(petName, tier) then
				local uid = ensureUid(value)
				records[uid] = {
					uid = uid,
					name = petName,
					tier = tier,
					count = math.max(0, math.floor(value.Value)),
					instance = value,
				}
			else
				warn(
					"[TradeServer] Valor de mascota ignorado por nombre/tier invalido:",
					value:GetFullName(),
					"| ItemName:",
					tostring(petName),
					"| Tier:",
					tostring(tier)
				)
			end
		end
	end

	return records
end

local function samePetStack(value, petName, tier)
	return (value:IsA("IntValue") or value:IsA("NumberValue"))
		and getPetName(value) == petName
		and getPetTier(value) == tier
end

local function activePetUsesStack(player, petName, tier)
	local selectedName = trim(player:GetAttribute("SelectedBackpackPet") or "")
	local selectedTier = normalizeTier(player:GetAttribute("SelectedBackpackPetTier") or "Base")
	if selectedName == petName and selectedTier == tier then
		return true
	end

	for _, object in ipairs(workspace:GetChildren()) do
		if object:IsA("Model")
			and object:GetAttribute("Owner") == player.UserId
			and trim(object:GetAttribute("PetType") or object.Name) == petName
			and normalizeTier(object:GetAttribute("UpgradeTier") or "Base") == tier
		then
			return true
		end
	end

	return false
end

local function copySafeAttributes(instance)
	local result = {}
	for key, value in pairs(instance:GetAttributes()) do
		if key ~= TRADE_UID_ATTR and key ~= "ItemName" and key ~= "UpgradeTier" then
			local t = typeof(value)
			if t == "string" or t == "number" or t == "boolean" then
				result[key] = value
			end
		end
	end
	result.Resting = false
	return result
end

local function petStackName(petName, tier)
	return petName .. "_" .. tostring(tier):gsub("%s+", "_")
end

local function getPetBaseIcon(petName)
	local views = ReplicatedStorage:FindFirstChild("MascotasView")
		or ReplicatedStorage:FindFirstChild("Mascotas")
	if not views then
		return ""
	end

	local direct = views:FindFirstChild(petName)
	if direct then
		return getImageFromInstance(direct)
	end

	for _, object in ipairs(views:GetDescendants()) do
		if object:IsA("Model") and normalize(object.Name) == normalize(petName) then
			return getImageFromInstance(object)
		end
	end

	return ""
end

--============================================================
-- SNAPSHOT DE INVENTARIO
--============================================================

local function prettyPetName(name)
	local n = normalize(name)

	if n == "pezdorado" then
		return "Pez dorado"
	elseif n == "ovejaderosario" or n == "oveja" then
		return "Oveja de rosario"
	elseif n == "huron" then
		return "Hurón"
	elseif n == "platano" then
		return "Plátano"
	end

	return tostring(name or "Mascota")
end

local function buildInventorySnapshot(player)
	local tools = {}
	local seedsByKey = {}
	local fruitsByKey = {}

	for _, container in ipairs(getTradeContainers(player)) do
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and not isTradeLockedInstance(child) then
				local seedKey = seedKeyFromTool(child)
				local fruitKey = fruitKeyFromTool(child)
				local woodType = woodTypeFromTool(child)

				if seedKey then
					local group = seedsByKey[seedKey]

					if not group then
						group = {
							kind = "Seed",
							key = seedKey,
							name = seedDisplayName(child),
							count = 0,
							icon = child.TextureId or "",
						}
						seedsByKey[seedKey] = group
					end

					group.count += getSeedStackAmount(child)

					if group.icon == "" and child.TextureId ~= "" then
						group.icon = child.TextureId
					end

				elseif fruitKey then
					local group = fruitsByKey[fruitKey]

					if not group then
						group = {
							kind = "Fruit",
							key = fruitKey,
							name = fruitDisplayName(child, fruitKey),
							count = 0,
							icon = child.TextureId or "",
						}
						fruitsByKey[fruitKey] = group
					end

					-- FruitInventorySaveServer V4 usa stacks reales x99.
					group.count += getFruitStackAmount(child)

					if group.icon == "" and child.TextureId ~= "" then
						group.icon = child.TextureId
					end

				elseif not woodType then
					local stackable = isAxeStackTool(child)
					local amount = stackable and getAxeStackAmount(child) or 1

					table.insert(tools, {
						kind = "Tool",
						name = trim(
							child:GetAttribute("BackpackDisplayName")
								or child:GetAttribute("ItemName")
								or child.Name
						),
						realName = child.Name,
						uid = ensureUid(child),
						count = amount,
						stackable = stackable,
						icon = child.TextureId or "",
					})
				end
			end
		end
	end

	-- Madera autoritativa de TreeChop.
	local woodCounts = getWoodCounts(player)

	for woodType, displayName in pairs(WOOD_TYPES) do
		local count = math.max(0, math.floor(tonumber(woodCounts[woodType]) or 0))

		if count > 0 then
			table.insert(tools, {
				kind = "Wood",
				key = woodType,
				name = displayName,
				count = count,
				icon = getWoodIcon(woodType),
			})
		end
	end

	local crops = {}

	for _, item in pairs(seedsByKey) do
		table.insert(crops, item)
	end

	for _, item in pairs(fruitsByKey) do
		table.insert(crops, item)
	end

	local pets = {}

	for _, record in pairs(getPetRecords(player)) do
		if not isTradeLockedInstance(record.instance) then
			table.insert(pets, {
				kind = "Pet",
				name = prettyPetName(record.name),
				realPetName = record.name,
				tier = record.tier,
				uid = record.uid,
				count = record.count,
				icon = getPetBaseIcon(record.name),
			})
		end
	end

	table.sort(tools, function(a, b)
		if a.name == b.name then
			return tostring(a.uid or a.key or "") < tostring(b.uid or b.key or "")
		end
		return tostring(a.name):lower() < tostring(b.name):lower()
	end)

	table.sort(crops, function(a, b)
		if a.kind ~= b.kind then
			return a.kind < b.kind
		end
		return tostring(a.name):lower() < tostring(b.name):lower()
	end)

	table.sort(pets, function(a, b)
		if a.name ~= b.name then
			return tostring(a.name):lower() < tostring(b.name):lower()
		end

		local ao = TIER_ORDER[a.tier] or 99
		local bo = TIER_ORDER[b.tier] or 99

		if ao ~= bo then
			return ao < bo
		end

		return tostring(a.uid) < tostring(b.uid)
	end)

	return {
		tools = tools,
		seeds = crops, -- La pestaña "Cultivos" contiene SEMILLAS + FRUTAS.
		pets = pets,
		serverTime = serverNow(),
	}
end

--============================================================
-- OFERTAS: SANITIZAR Y VALIDAR
--============================================================

local function sanitizeStackId(value)
	if typeof(value) ~= "string" then
		return nil
	end
	value = value:sub(1, 160)
	if value == "" then
		return nil
	end
	return value
end

local function sanitizeItem(raw)
	if typeof(raw) ~= "table" then
		return nil
	end

	local kind = raw.kind
	local stackId = sanitizeStackId(raw.stackId)

	if kind == "Tool" then
		local uid = raw.uid
		if typeof(uid) ~= "string" or uid == "" then
			return nil
		end

		return {
			kind = "Tool",
			uid = uid,
			count = math.clamp(
				math.floor(tonumber(raw.count) or 1),
				1,
				INVENTORY_STACK_LIMIT
			),
			stackId = stackId,
		}
	end

	if kind == "Seed" then
		local key = seedKeyFromValue(raw.key or raw.name)
		if not key then
			return nil
		end

		return {
			kind = "Seed",
			key = key,
			count = math.clamp(
				math.floor(tonumber(raw.count) or 1),
				1,
				MAX_STACK_OFFER
			),
			stackId = stackId,
		}
	end

	if kind == "Fruit" then
		local key = fruitKeyFromValue(raw.key or raw.name)
		if not key then
			return nil
		end

		return {
			kind = "Fruit",
			key = key,
			count = math.clamp(
				math.floor(tonumber(raw.count) or 1),
				1,
				MAX_STACK_OFFER
			),
			stackId = stackId,
		}
	end

	if kind == "Wood" then
		local key = tostring(raw.key or "")
		if not WOOD_TYPES[key] then
			return nil
		end

		return {
			kind = "Wood",
			key = key,
			count = math.clamp(
				math.floor(tonumber(raw.count) or 1),
				1,
				MAX_STACK_OFFER
			),
			stackId = stackId,
		}
	end

	if kind == "Pet" then
		local uid = raw.uid
		if typeof(uid) ~= "string" or uid == "" then
			return nil
		end

		return {
			kind = "Pet",
			uid = uid,
			count = math.clamp(
				math.floor(tonumber(raw.count) or 1),
				1,
				MAX_PET_OFFER
			),
			stackId = stackId,
		}
	end

	return nil
end

local function emptySlots()
	local slots = table.create(MAX_SLOTS)
	for i = 1, MAX_SLOTS do
		slots[i] = false
	end
	return slots
end

local function offerHasAnything(slots)
	for i = 1, MAX_SLOTS do
		if slots[i] then
			return true
		end
	end
	return false
end

local function validateOffer(player, slots)
	local usedToolUids = {}
	local seedTotals = {}
	local fruitTotals = {}
	local woodTotals = {}
	local petTotals = {}
	local petRecords = getPetRecords(player)

	for slot = 1, MAX_SLOTS do
		local item = slots[slot]

		if item then
			if item.kind == "Tool" then
				if usedToolUids[item.uid] then
					return false, "La misma herramienta esta repetida."
				end

				local tool = findToolByUid(player, item.uid)

				if not tool
					or seedKeyFromTool(tool)
					or fruitKeyFromTool(tool)
					or woodTypeFromTool(tool)
					or isTradeLockedInstance(tool)
				then
					return false, "Una herramienta de tu oferta ya no esta disponible."
				end

				local availableAmount = getTradeToolStackAmount(tool)
				if item.count > availableAmount then
					return false, "No tienes suficientes unidades de esa herramienta."
				end

				if not isAxeStackTool(tool) and item.count ~= 1 then
					return false, "Esa herramienta no se puede apilar."
				end

				usedToolUids[item.uid] = true

			elseif item.kind == "Seed" then
				if not seedTemplateByKey[item.key]
					and not seedAliasToKey[normalize(item.key)]
				then
					return false, "Una semilla de tu oferta ya no es valida."
				end

				seedTotals[item.key] =
					(seedTotals[item.key] or 0)
					+ item.count

			elseif item.kind == "Fruit" then
				if not fruitTemplateByKey[item.key]
					and not fruitAliasToKey[normalize(item.key)]
				then
					return false, "Una fruta de tu oferta ya no es valida."
				end

				fruitTotals[item.key] =
					(fruitTotals[item.key] or 0)
					+ item.count

			elseif item.kind == "Wood" then
				if not WOOD_TYPES[item.key] then
					return false, "Una madera de tu oferta ya no es valida."
				end

				woodTotals[item.key] =
					(woodTotals[item.key] or 0)
					+ item.count

			elseif item.kind == "Pet" then
				local record = petRecords[item.uid]

				if not record or isTradeLockedInstance(record.instance) then
					return false, "Una mascota de tu oferta ya no esta disponible."
				end

				petTotals[item.uid] =
					(petTotals[item.uid] or 0)
					+ item.count

				if petTotals[item.uid] > record.count then
					return false, "No tienes suficientes " .. prettyPetName(record.name) .. "."
				end
			else
				return false, "Tipo de objeto invalido."
			end
		end
	end

	for key, amount in pairs(seedTotals) do
		if countSeed(player, key) < amount then
			return false, "Ya no tienes suficientes semillas para esa oferta."
		end
	end

	for key, amount in pairs(fruitTotals) do
		if countFruit(player, key) < amount then
			return false, "Ya no tienes suficientes frutas para esa oferta."
		end
	end

	local woodCounts = getWoodCounts(player)

	for woodType, amount in pairs(woodTotals) do
		if (woodCounts[woodType] or 0) < amount then
			return false, "Ya no tienes suficiente " .. (WOOD_TYPES[woodType] or "madera") .. "."
		end
	end

	for uid, amount in pairs(petTotals) do
		local record = petRecords[uid]

		if record
			and amount >= record.count
			and activePetUsesStack(player, record.name, record.tier)
		then
			return false,
				"Guarda o cambia tu mascota activa antes de tradear la ultima "
				.. prettyPetName(record.name)
				.. "."
		end

		if record
			and record.instance:GetAttribute("Resting") == true
			and amount >= record.count
		then
			return false,
				"Esa mascota esta descansando. Quitala de la cama antes de tradearla."
		end
	end

	return true
end

local function decorateOfferItem(player, item)
	if not item then
		return false
	end

	if item.kind == "Tool" then
		local tool = findToolByUid(player, item.uid)

		if not tool then
			return {
				kind = "Tool",
				name = "Objeto",
				uid = item.uid,
				count = item.count or 1,
				stackable = false,
				stackId = item.stackId,
				icon = "",
			}
		end

		return {
			kind = "Tool",
			name = trim(
				tool:GetAttribute("BackpackDisplayName")
					or tool:GetAttribute("ItemName")
					or tool.Name
			),
			uid = item.uid,
			count = item.count or 1,
			stackable = isAxeStackTool(tool),
			stackId = item.stackId,
			icon = tool.TextureId or "",
		}
	end

	if item.kind == "Seed" then
		local template = seedTemplateByKey[item.key]

		return {
			kind = "Seed",
			key = item.key,
			name = template and seedDisplayName(template) or tostring(item.key),
			count = item.count,
			stackId = item.stackId,
			icon = template and (template.TextureId or "") or "",
		}
	end

	if item.kind == "Fruit" then
		local template = fruitTemplateByKey[item.key]

		return {
			kind = "Fruit",
			key = item.key,
			name = fruitDisplayName(template, item.key),
			count = item.count,
			stackId = item.stackId,
			icon = template and (template.TextureId or "") or "",
		}
	end

	if item.kind == "Wood" then
		return {
			kind = "Wood",
			key = item.key,
			name = WOOD_TYPES[item.key] or "Madera",
			count = item.count,
			stackId = item.stackId,
			icon = getWoodIcon(item.key),
		}
	end

	if item.kind == "Pet" then
		local record = getPetRecords(player)[item.uid]

		return {
			kind = "Pet",
			uid = item.uid,
			name = record and prettyPetName(record.name) or "Mascota",
			realPetName = record and record.name or "Mascota",
			tier = record and record.tier or "Base",
			count = item.count,
			stackId = item.stackId,
			icon = record and getPetBaseIcon(record.name) or "",
		}
	end

	return false
end

--============================================================
-- SESION
--============================================================

local function getSession(player)
	return sessionsByUserId[player.UserId]
end

local function publicSession(session)
	local offers = {}

	for _, userId in ipairs(session.userIds) do
		local key = tostring(userId)
		local player = Players:GetPlayerByUserId(userId)
		offers[key] = table.create(MAX_SLOTS)

		for i = 1, MAX_SLOTS do
			local raw = session.offers[key][i]
			offers[key][i] = player and decorateOfferItem(player, raw) or false
		end
	end

	return {
		sessionId = session.id,
		serverTime = serverNow(),
		players = session.players,
		offers = offers,
		confirmed = session.confirmed,
		revision = session.revision,
		lockUntil = session.lockUntil,
		finalizing = session.finalizing == true,
		finalizeAt = session.finalizeAt or 0,
	}
end

local function sendUpdate(session)
	if not session or session.closed then
		return
	end
	local payload = publicSession(session)
	for _, userId in ipairs(session.userIds) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			TradeUpdate:FireClient(player, payload)
		end
	end
end

local function clearSessionMappings(session)
	for _, userId in ipairs(session.userIds) do
		if sessionsByUserId[userId] == session then
			sessionsByUserId[userId] = nil
		end
		local player = Players:GetPlayerByUserId(userId)
		if player then
			player:SetAttribute("TradeCommitLock", false)
		end
	end
end

local function closeSession(session, reason)
	if not session or session.closed then
		return
	end

	session.closed = true
	session.finalizing = false
	session.finalizeToken = (session.finalizeToken or 0) + 1
	clearSessionMappings(session)

	for _, userId in ipairs(session.userIds) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			notify(player, "TradeClosed", {
				reason = reason or "Intercambio cancelado.",
			})
		end
	end

	firePlayerListUpdate()
end

local function finishSessionSuccess(session)
	if not session or session.closed then
		return
	end

	session.closed = true
	session.finalizing = false
	session.finalizeToken = (session.finalizeToken or 0) + 1
	clearSessionMappings(session)

	for _, userId in ipairs(session.userIds) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			player:SetAttribute(
				"TradeInventoryRevision",
				(tonumber(player:GetAttribute("TradeInventoryRevision")) or 0) + 1
			)
			awardGameActionXP(player, "CompleteTrade", 15)

			notify(player, "TradeSuccess", {
				message = "Intercambio completado correctamente.",
			})
		end
	end

	firePlayerListUpdate()
end

local function resetConfirmationsAfterChange(session)
	session.revision += 1
	session.finalizing = false
	session.finalizeAt = 0
	session.finalizeToken = (session.finalizeToken or 0) + 1

	local unlockAt = serverNow() + CHANGE_LOCK_SECONDS
	for _, userId in ipairs(session.userIds) do
		local key = tostring(userId)
		session.confirmed[key] = false
		session.confirmedRevision[key] = -1
		session.lockUntil[key] = unlockAt
	end
end

--============================================================
-- ESCROW / TRANSACCION ATOMICA
--============================================================

local function makeEscrow(sessionId)
	local root = ServerStorage:FindFirstChild("TradeEscrow")

	if not root then
		root = Instance.new("Folder")
		root.Name = "TradeEscrow"
		root.Parent = ServerStorage
	end

	local old = root:FindFirstChild(sessionId)

	if old then
		old:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = sessionId
	folder.Parent = root

	return folder
end

local function rollbackStage(stage)
	if not stage then
		return
	end

	for i = #stage.entries, 1, -1 do
		local entry = stage.entries[i]

		if entry.type == "MovedTool"
			or entry.type == "MovedSeed"
			or entry.type == "MovedFruit"
		then
			if entry.instance and entry.instance.Parent then
				entry.instance.Parent = entry.originalParent
			end

		elseif entry.type == "PartialToolStack" then
			if entry.source and entry.source.Parent then
				setTradeToolStackAmount(entry.source, entry.originalAmount)
			end

			if entry.clone and entry.clone.Parent then
				entry.clone:Destroy()
			end

		elseif entry.type == "PartialSeed" then
			if entry.source and entry.source.Parent then
				setSeedStackAmount(entry.source, entry.originalAmount)
			end

			if entry.clone and entry.clone.Parent then
				entry.clone:Destroy()
			end

		elseif entry.type == "PartialFruit" then
			if entry.source and entry.source.Parent then
				setFruitStackAmount(entry.source, entry.originalAmount)
			end

			if entry.clone and entry.clone.Parent then
				entry.clone:Destroy()
			end

		elseif entry.type == "PetStack" then
			if entry.instance and entry.instance.Parent then
				entry.instance.Value = entry.originalValue
			end
		end
	end
end

local function stageOffer(player, slots, escrowFolder)
	local stage = {
		player = player,
		entries = {},
		wood = {},
	}

	local reservedTools = {}
	local petTotals = {}

	-- Herramientas unicas + recopilar mascotas/madera.
	for i = 1, MAX_SLOTS do
		local item = slots[i]

		if item and item.kind == "Tool" then
			local tool = findToolByUid(player, item.uid)

			if not tool
				or reservedTools[tool]
				or seedKeyFromTool(tool)
				or fruitKeyFromTool(tool)
				or woodTypeFromTool(tool)
				or isTradeLockedInstance(tool)
			then
				rollbackStage(stage)
				return nil, "Una herramienta cambio antes de completar el intercambio."
			end

			local availableAmount = getTradeToolStackAmount(tool)
			local takeAmount = math.max(1, math.floor(tonumber(item.count) or 1))

			if takeAmount > availableAmount
				or (not isAxeStackTool(tool) and takeAmount ~= 1)
			then
				rollbackStage(stage)
				return nil, "La cantidad de esa herramienta cambio antes de completar el intercambio."
			end

			reservedTools[tool] = true

			if isAxeStackTool(tool) and takeAmount < availableAmount then
				local oldAmount = availableAmount
				setTradeToolStackAmount(tool, oldAmount - takeAmount)

				local clone = tool:Clone()
				clone:SetAttribute(TRADE_UID_ATTR, HttpService:GenerateGUID(false))
				setTradeToolStackAmount(clone, takeAmount)
				clone.Parent = escrowFolder

				table.insert(stage.entries, {
					type = "PartialToolStack",
					source = tool,
					originalAmount = oldAmount,
					clone = clone,
				})
			else
				table.insert(stage.entries, {
					type = "MovedTool",
					instance = tool,
					originalParent = tool.Parent,
				})

				tool.Parent = escrowFolder
			end

		elseif item and item.kind == "Pet" then
			petTotals[item.uid] =
				(petTotals[item.uid] or 0)
				+ item.count

		elseif item and item.kind == "Wood" then
			stage.wood[item.key] =
				(stage.wood[item.key] or 0)
				+ item.count
		end
	end

	-- Semillas apiladas.
	local seedTotals = {}

	for i = 1, MAX_SLOTS do
		local item = slots[i]

		if item and item.kind == "Seed" then
			seedTotals[item.key] =
				(seedTotals[item.key] or 0)
				+ item.count
		end
	end

	for key, amountNeeded in pairs(seedTotals) do
		local remaining = amountNeeded
		local candidates = findSeedTools(player, key)

		table.sort(candidates, function(a, b)
			return getSeedStackAmount(a) < getSeedStackAmount(b)
		end)

		for _, tool in ipairs(candidates) do
			if remaining <= 0 then
				break
			end

			if not reservedTools[tool] and not isTradeLockedInstance(tool) then
				reservedTools[tool] = true

				local stackAmount = getSeedStackAmount(tool)

				if remaining >= stackAmount then
					table.insert(stage.entries, {
						type = "MovedSeed",
						instance = tool,
						originalParent = tool.Parent,
					})

					tool.Parent = escrowFolder
					remaining -= stackAmount
				else
					local takeAmount = remaining
					local oldAmount = stackAmount

					setSeedStackAmount(tool, oldAmount - takeAmount)

					local clone = tool:Clone()
					clone:SetAttribute(TRADE_UID_ATTR, HttpService:GenerateGUID(false))
					setSeedStackAmount(clone, takeAmount)
					clone.Parent = escrowFolder

					table.insert(stage.entries, {
						type = "PartialSeed",
						source = tool,
						originalAmount = oldAmount,
						clone = clone,
					})

					remaining = 0
				end
			end
		end

		if remaining > 0 then
			rollbackStage(stage)
			return nil, "Tus semillas cambiaron antes de completar el intercambio."
		end
	end

	-- Frutas V4: stacks físicos reales x99.
	local fruitTotals = {}

	for i = 1, MAX_SLOTS do
		local item = slots[i]

		if item and item.kind == "Fruit" then
			fruitTotals[item.key] =
				(fruitTotals[item.key] or 0)
				+ item.count
		end
	end

	for key, amountNeeded in pairs(fruitTotals) do
		local remaining = amountNeeded
		local candidates = findFruitTools(player, key)

		table.sort(candidates, function(a, b)
			return getFruitStackAmount(a) < getFruitStackAmount(b)
		end)

		for _, tool in ipairs(candidates) do
			if remaining <= 0 then
				break
			end

			if not reservedTools[tool] and not isTradeLockedInstance(tool) then
				reservedTools[tool] = true
				local stackAmount = getFruitStackAmount(tool)

				if remaining >= stackAmount then
					table.insert(stage.entries, {
						type = "MovedFruit",
						instance = tool,
						originalParent = tool.Parent,
					})

					tool.Parent = escrowFolder
					remaining -= stackAmount
				else
					local takeAmount = remaining
					local oldAmount = stackAmount

					setFruitStackAmount(tool, oldAmount - takeAmount)

					local clone = tool:Clone()
					clone:SetAttribute(TRADE_UID_ATTR, HttpService:GenerateGUID(false))
					setFruitStackAmount(clone, takeAmount)
					clone.Parent = escrowFolder

					table.insert(stage.entries, {
						type = "PartialFruit",
						source = tool,
						originalAmount = oldAmount,
						clone = clone,
					})

					remaining = 0
				end
			end
		end

		if remaining > 0 then
			rollbackStage(stage)
			return nil, "Tus frutas cambiaron antes de completar el intercambio."
		end
	end

	-- Mascotas.
	local petRecords = getPetRecords(player)

	for uid, amount in pairs(petTotals) do
		local record = petRecords[uid]

		if not record
			or record.count < amount
			or isTradeLockedInstance(record.instance)
		then
			rollbackStage(stage)
			return nil, "Una mascota cambio antes de completar el intercambio."
		end

		if amount >= record.count
			and activePetUsesStack(player, record.name, record.tier)
		then
			rollbackStage(stage)
			return nil, "Guarda o cambia tu mascota activa antes de tradearla."
		end

		local originalValue = record.instance.Value
		local attrs = copySafeAttributes(record.instance)

		record.instance.Value = originalValue - amount

		table.insert(stage.entries, {
			type = "PetStack",
			instance = record.instance,
			originalValue = originalValue,
			name = record.name,
			tier = record.tier,
			amount = amount,
			attributes = attrs,
		})
	end

	-- Revalidar madera justo al terminar el stage.
	local woodCounts = getWoodCounts(player)

	for woodType, amount in pairs(stage.wood) do
		if (woodCounts[woodType] or 0) < amount then
			rollbackStage(stage)
			return nil, "Tu madera cambio antes de completar el intercambio."
		end
	end

	return stage
end

local function addPetToTarget(target, petName, tier, amount, attributes)
	local folder = getPetContainer(target, true)

	for _, value in ipairs(folder:GetChildren()) do
		if samePetStack(value, petName, tier) then
			local oldValue = value.Value
			value.Value += amount

			return {
				type = "RestorePetNumber",
				instance = value,
				oldValue = oldValue,
			}
		end
	end

	local value = Instance.new("IntValue")
	value.Name = petStackName(petName, tier)
	value.Value = amount
	value:SetAttribute("ItemName", petName)
	value:SetAttribute("UpgradeTier", tier)
	value:SetAttribute(TRADE_UID_ATTR, HttpService:GenerateGUID(false))

	for key, attrValue in pairs(attributes or {}) do
		if key ~= TRADE_UID_ATTR
			and key ~= "ItemName"
			and key ~= "UpgradeTier"
		then
			pcall(function()
				value:SetAttribute(key, attrValue)
			end)
		end
	end

	value:SetAttribute("Resting", false)
	value.Parent = folder

	return {
		type = "DestroyCreatedPet",
		instance = value,
	}
end

local function rollbackCommit(receipt)
	if not receipt then
		return
	end

	for i = #receipt.undo, 1, -1 do
		local action = receipt.undo[i]

		if action.type == "MoveBackToEscrow" then
			if action.instance and action.instance.Parent then
				action.instance.Parent = action.escrow
			end

		elseif action.type == "RestorePetNumber" then
			if action.instance and action.instance.Parent then
				action.instance.Value = action.oldValue
			end

		elseif action.type == "DestroyCreatedPet" then
			if action.instance and action.instance.Parent then
				action.instance:Destroy()
			end

		elseif action.type == "ReverseWoodTransfer" then
			-- Rollback server-only del cache de madera.
			transferWood(
				action.from,
				action.to,
				action.woodType,
				action.amount
			)
		end
	end
end

local function commitStage(stage, target, escrowFolder)
	local receipt = {
		undo = {},
	}

	local backpack =
		target:FindFirstChildOfClass("Backpack")
		or target:WaitForChild("Backpack", 3)

	if not backpack then
		return nil, "El inventario del receptor no esta disponible."
	end

	for _, entry in ipairs(stage.entries) do
		if entry.type == "MovedTool"
			or entry.type == "MovedSeed"
			or entry.type == "MovedFruit"
		then
			if not entry.instance or not entry.instance.Parent then
				rollbackCommit(receipt)
				return nil, "Un objeto desaparecio durante la transferencia."
			end

			entry.instance.Parent = backpack

			table.insert(receipt.undo, {
				type = "MoveBackToEscrow",
				instance = entry.instance,
				escrow = escrowFolder,
			})

		elseif entry.type == "PartialToolStack"
			or entry.type == "PartialSeed"
			or entry.type == "PartialFruit"
		then
			if not entry.clone or not entry.clone.Parent then
				rollbackCommit(receipt)
				return nil, "Un stack parcial desaparecio durante la transferencia."
			end

			entry.clone.Parent = backpack

			table.insert(receipt.undo, {
				type = "MoveBackToEscrow",
				instance = entry.clone,
				escrow = escrowFolder,
			})

		elseif entry.type == "PetStack" then
			local undo = addPetToTarget(
				target,
				entry.name,
				entry.tier,
				entry.amount,
				entry.attributes
			)

			table.insert(receipt.undo, undo)
		end
	end

	-- La madera se transfiere usando el cache real de TreeChopServer.
	for woodType, amount in pairs(stage.wood or {}) do
		local ok, err = transferWood(
			stage.player,
			target,
			woodType,
			amount
		)

		if not ok then
			rollbackCommit(receipt)
			return nil, err or "No se pudo transferir la madera."
		end

		table.insert(receipt.undo, {
			type = "ReverseWoodTransfer",
			from = target,
			to = stage.player,
			woodType = woodType,
			amount = amount,
		})
	end

	return receipt
end

local function finalizeStage(stage)
	for _, entry in ipairs(stage.entries) do
		if entry.type == "PetStack" then
			local value = entry.instance

			if value and value.Parent and value.Value <= 0 then
				value:Destroy()
			end
		end
	end
end

local function forceSeedSave(player)
	local force = game:GetService("ServerScriptService"):FindFirstChild("ForceSeedInventorySave")

	if not force then
		return
	end

	task.spawn(function()
		if force:IsA("BindableFunction") then
			pcall(function()
				force:Invoke(player)
			end)
		elseif force:IsA("BindableEvent") then
			pcall(function()
				force:Fire(player)
			end)
		end
	end)
end

local function forceFruitSave(player)
	local force = game:GetService("ServerScriptService"):FindFirstChild("ForceFruitInventorySave")

	if not force then
		return
	end

	task.spawn(function()
		if force:IsA("BindableFunction") then
			pcall(function()
				force:Invoke(player)
			end)
		elseif force:IsA("BindableEvent") then
			pcall(function()
				force:Fire(player)
			end)
		end
	end)
end

local function completeTransaction(session)
	if session.closed or not session.finalizing then
		return
	end

	local aId, bId = session.userIds[1], session.userIds[2]
	local a = Players:GetPlayerByUserId(aId)
	local b = Players:GetPlayerByUserId(bId)

	if not a or not b then
		closeSession(session, "Un jugador salio del servidor.")
		return
	end

	local aKey, bKey = tostring(aId), tostring(bId)

	if not session.confirmed[aKey] or not session.confirmed[bKey] then
		return
	end

	if session.confirmedRevision[aKey] ~= session.revision
		or session.confirmedRevision[bKey] ~= session.revision
	then
		return
	end

	if serverNow() + 0.02 < (session.finalizeAt or 0) then
		return
	end

	if not offerHasAnything(session.offers[aKey]) and not offerHasAnything(session.offers[bKey]) then
		session.finalizing = false
		session.confirmed[aKey] = false
		session.confirmed[bKey] = false
		notify(a, "TradeError", {message = "El intercambio esta vacio."})
		notify(b, "TradeError", {message = "El intercambio esta vacio."})
		sendUpdate(session)
		return
	end

	-- Revalidacion FINAL, justo antes de reservar objetos.
	local okA, errA = validateOffer(a, session.offers[aKey])
	local okB, errB = validateOffer(b, session.offers[bKey])
	if not okA or not okB then
		session.finalizing = false
		session.confirmed[aKey] = false
		session.confirmed[bKey] = false
		notify(a, "TradeError", {message = errA or errB or "La oferta cambio."})
		notify(b, "TradeError", {message = errA or errB or "La oferta cambio."})
		sendUpdate(session)
		return
	end

	a:SetAttribute("TradeCommitLock", true)
	b:SetAttribute("TradeCommitLock", true)

	local escrow = makeEscrow(session.id)

	local stageA, stageErrA = stageOffer(a, session.offers[aKey], escrow)
	if not stageA then
		a:SetAttribute("TradeCommitLock", false)
		b:SetAttribute("TradeCommitLock", false)
		escrow:Destroy()
		notify(a, "TradeError", {message = stageErrA or "No se pudo reservar tu oferta."})
		notify(b, "TradeError", {message = "La oferta del otro jugador cambio."})
		closeSession(session, "Intercambio cancelado por cambio de inventario.")
		return
	end

	local stageB, stageErrB = stageOffer(b, session.offers[bKey], escrow)
	if not stageB then
		rollbackStage(stageA)
		a:SetAttribute("TradeCommitLock", false)
		b:SetAttribute("TradeCommitLock", false)
		escrow:Destroy()
		notify(a, "TradeError", {message = "La oferta del otro jugador cambio."})
		notify(b, "TradeError", {message = stageErrB or "No se pudo reservar tu oferta."})
		closeSession(session, "Intercambio cancelado por cambio de inventario.")
		return
	end

	local receiptA, commitErrA = commitStage(stageA, b, escrow)
	if not receiptA then
		rollbackStage(stageB)
		rollbackStage(stageA)
		a:SetAttribute("TradeCommitLock", false)
		b:SetAttribute("TradeCommitLock", false)
		escrow:Destroy()
		notify(a, "TradeError", {message = commitErrA or "No se pudo transferir la oferta."})
		notify(b, "TradeError", {message = commitErrA or "No se pudo transferir la oferta."})
		closeSession(session, "Intercambio cancelado por error de transferencia.")
		return
	end

	local receiptB, commitErrB = commitStage(stageB, a, escrow)
	if not receiptB then
		rollbackCommit(receiptA)
		rollbackStage(stageB)
		rollbackStage(stageA)
		a:SetAttribute("TradeCommitLock", false)
		b:SetAttribute("TradeCommitLock", false)
		escrow:Destroy()
		notify(a, "TradeError", {message = commitErrB or "No se pudo transferir la oferta."})
		notify(b, "TradeError", {message = commitErrB or "No se pudo transferir la oferta."})
		closeSession(session, "Intercambio cancelado por error de transferencia.")
		return
	end

	finalizeStage(stageA)
	finalizeStage(stageB)

	a:SetAttribute("TradeCommitLock", false)
	b:SetAttribute("TradeCommitLock", false)

	if escrow.Parent then
		escrow:Destroy()
	end

	forceSeedSave(a)
	forceSeedSave(b)
	forceFruitSave(a)
	forceFruitSave(b)

	finishSessionSuccess(session)
end

local function beginFinalSecurity(session)
	if session.closed or session.finalizing then
		return
	end

	local aKey = tostring(session.userIds[1])
	local bKey = tostring(session.userIds[2])

	if not session.confirmed[aKey] or not session.confirmed[bKey] then
		return
	end

	if session.confirmedRevision[aKey] ~= session.revision
		or session.confirmedRevision[bKey] ~= session.revision
	then
		return
	end

	session.finalizing = true
	session.finalizeAt = serverNow() + FINAL_SECURITY_SECONDS
	session.finalizeToken = (session.finalizeToken or 0) + 1
	local token = session.finalizeToken

	sendUpdate(session)

	task.delay(FINAL_SECURITY_SECONDS + 0.05, function()
		if session.closed
			or not session.finalizing
			or session.finalizeToken ~= token
		then
			return
		end
		completeTransaction(session)
	end)
end

local function startSession(a, b)
	local session = {
		id = HttpService:GenerateGUID(false),
		userIds = {a.UserId, b.UserId},
		players = {
			[tostring(a.UserId)] = {
				userId = a.UserId,
				name = a.Name,
				displayName = a.DisplayName,
			},
			[tostring(b.UserId)] = {
				userId = b.UserId,
				name = b.Name,
				displayName = b.DisplayName,
			},
		},
		offers = {
			[tostring(a.UserId)] = emptySlots(),
			[tostring(b.UserId)] = emptySlots(),
		},
		confirmed = {
			[tostring(a.UserId)] = false,
			[tostring(b.UserId)] = false,
		},
		confirmedRevision = {
			[tostring(a.UserId)] = -1,
			[tostring(b.UserId)] = -1,
		},
		lockUntil = {
			[tostring(a.UserId)] = serverNow(),
			[tostring(b.UserId)] = serverNow(),
		},
		revision = 0,
		finalizing = false,
		finalizeAt = 0,
		finalizeToken = 0,
		closed = false,
	}

	sessionsByUserId[a.UserId] = session
	sessionsByUserId[b.UserId] = session

	notify(a, "TradeStarted", {sessionId = session.id})
	notify(b, "TradeStarted", {sessionId = session.id})
	sendUpdate(session)
	firePlayerListUpdate()
end

--============================================================
-- SOLICITUDES / ANTI-SPAM
--============================================================

local function clearPendingRequest(request)
	if not request then
		return
	end
	if request.sender and pendingBySenderId[request.sender.UserId] == request then
		pendingBySenderId[request.sender.UserId] = nil
	end
	if request.target and pendingByTargetId[request.target.UserId] == request then
		pendingByTargetId[request.target.UserId] = nil
	end
	firePlayerListUpdate()
end

local function cancelPendingForPlayer(player, reasonForOther)
	local sent = pendingBySenderId[player.UserId]
	if sent then
		clearPendingRequest(sent)
		if sent.target and sent.target.Parent == Players then
			notify(sent.target, "RequestExpired", {requestId = sent.id})
			if reasonForOther then
				notify(sent.target, "TradeError", {message = reasonForOther})
			end
		end
	end

	local received = pendingByTargetId[player.UserId]
	if received then
		clearPendingRequest(received)
		if received.sender and received.sender.Parent == Players then
			notify(received.sender, "RequestExpired", {requestId = received.id})
			if reasonForOther then
				notify(received.sender, "TradeError", {message = reasonForOther})
			end
		end
	end
end

RequestTrade.OnServerEvent:Connect(function(sender, targetUserId)
	local allowed, remaining = rateLimit(lastRequestAt, sender.UserId, REQUEST_COOLDOWN)
	if not allowed then
		notify(sender, "TradeError", {
			message = string.format("Espera %.1fs antes de enviar otra solicitud.", remaining),
		})
		return
	end

	if typeof(targetUserId) ~= "number" then
		return
	end

	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == sender then
		return
	end

	if sender:GetAttribute(TRADE_ENABLED_ATTR) == nil then
		sender:SetAttribute(TRADE_ENABLED_ATTR, true)
	end

	if target:GetAttribute(TRADE_ENABLED_ATTR) ~= true then
		notify(sender, "TradeError", {message = "Ese jugador desactivo las solicitudes de intercambio."})
		return
	end

	if sessionsByUserId[sender.UserId] or sessionsByUserId[target.UserId] then
		notify(sender, "TradeError", {message = "Uno de los jugadores ya esta intercambiando."})
		return
	end

	if pendingBySenderId[sender.UserId] or pendingByTargetId[sender.UserId] then
		notify(sender, "TradeError", {message = "Ya tienes una solicitud pendiente."})
		return
	end

	if pendingBySenderId[target.UserId] or pendingByTargetId[target.UserId] then
		notify(sender, "TradeError", {message = "Ese jugador ya tiene una solicitud pendiente."})
		return
	end

	local pKey = pairKey(sender.UserId, target.UserId)
	local cooldown = math.max(0, (pairCooldownUntil[pKey] or 0) - serverNow())
	if cooldown > 0 then
		notify(sender, "TradeError", {
			message = "Espera " .. tostring(math.ceil(cooldown)) .. "s antes de volver a solicitar a ese jugador.",
		})
		return
	end

	pairCooldownUntil[pKey] = serverNow() + PAIR_REQUEST_COOLDOWN

	local request = {
		id = HttpService:GenerateGUID(false),
		sender = sender,
		target = target,
		createdAt = serverNow(),
	}

	pendingBySenderId[sender.UserId] = request
	pendingByTargetId[target.UserId] = request

	notify(sender, "RequestSent", {
		requestId = request.id,
		targetName = target.DisplayName,
		cooldown = PAIR_REQUEST_COOLDOWN,
	})

	notify(target, "TradeRequest", {
		requestId = request.id,
		fromUserId = sender.UserId,
		fromName = sender.DisplayName,
		fromUsername = sender.Name,
		expiresAt = request.createdAt + REQUEST_TIMEOUT,
		duration = REQUEST_TIMEOUT,
	})

	firePlayerListUpdate()

	task.delay(REQUEST_TIMEOUT, function()
		if pendingBySenderId[sender.UserId] ~= request then
			return
		end
		clearPendingRequest(request)
		if sender.Parent == Players then
			notify(sender, "RequestRejected", {
				targetName = target.DisplayName,
				automatic = true,
			})
		end

		if target.Parent == Players then
			notify(target, "RequestExpired", {
				requestId = request.id,
				automatic = true,
			})
		end
	end)
end)

RespondTrade.OnServerEvent:Connect(function(target, accepted, senderUserId, requestId)
	if typeof(accepted) ~= "boolean"
		or typeof(senderUserId) ~= "number"
		or typeof(requestId) ~= "string"
	then
		return
	end

	local request = pendingByTargetId[target.UserId]
	if not request
		or request.id ~= requestId
		or request.sender.UserId ~= senderUserId
		or request.target ~= target
	then
		return
	end

	clearPendingRequest(request)

	local sender = request.sender
	if not sender or sender.Parent ~= Players then
		return
	end

	if not accepted then
		notify(sender, "RequestRejected", {
			targetName = target.DisplayName,
		})
		firePlayerListUpdate()
		return
	end

	if target:GetAttribute(TRADE_ENABLED_ATTR) ~= true then
		notify(sender, "TradeError", {message = "El jugador dejo de aceptar solicitudes."})
		return
	end

	if sessionsByUserId[sender.UserId] or sessionsByUserId[target.UserId] then
		notify(sender, "TradeError", {message = "El intercambio ya no esta disponible."})
		notify(target, "TradeError", {message = "El intercambio ya no esta disponible."})
		return
	end

	startSession(sender, target)
end)

--============================================================
-- ACCIONES DEL TRADE
--============================================================

TradeAction.OnServerEvent:Connect(function(player, action, data)
	if typeof(action) ~= "string" then
		return
	end

	local session = getSession(player)
	if not session or session.closed then
		return
	end

	data = typeof(data) == "table" and data or {}
	if data.sessionId ~= session.id then
		return
	end

	-- Cancelar siempre se permite, incluso durante el conteo final.
	if action == "Cancel" then
		closeSession(session, player.DisplayName .. " cancelo el intercambio.")
		return
	end

	local allowed = rateLimit(lastActionAt, player.UserId, ACTION_COOLDOWN)
	if not allowed then
		return
	end

	if session.finalizing then
		notify(player, "TradeError", {message = "La oferta esta bloqueada durante la verificacion final."})
		return
	end

	local key = tostring(player.UserId)

	if action == "SetSlot" then
		local slot = math.floor(tonumber(data.slot) or 0)
		if slot < 1 or slot > MAX_SLOTS then
			return
		end

		local item = sanitizeItem(data.item)
		if not item then
			notify(player, "TradeError", {message = "Objeto invalido."})
			return
		end

		local previous = session.offers[key][slot]
		session.offers[key][slot] = item

		local ok, err = validateOffer(player, session.offers[key])
		if not ok then
			session.offers[key][slot] = previous
			notify(player, "TradeError", {message = err or "Oferta invalida."})
		else
			resetConfirmationsAfterChange(session)
		end

		sendUpdate(session)
		return
	end

	if action == "ClearSlot" then
		local slot = math.floor(tonumber(data.slot) or 0)
		if slot < 1 or slot > MAX_SLOTS then
			return
		end

		if session.offers[key][slot] then
			session.offers[key][slot] = false
			compactOfferSlots(session.offers[key])
			resetConfirmationsAfterChange(session)
			sendUpdate(session)
		end
		return
	end

	if action == "Confirm" then
		if serverNow() < (session.lockUntil[key] or 0) then
			notify(player, "TradeError", {message = "Espera 3 segundos despues del ultimo cambio."})
			return
		end

		local ok, err = validateOffer(player, session.offers[key])
		if not ok then
			session.confirmed[key] = false
			session.confirmedRevision[key] = -1
			notify(player, "TradeError", {message = err or "Tu oferta ya no es valida."})
			sendUpdate(session)
			return
		end

		session.confirmed[key] = true
		session.confirmedRevision[key] = session.revision
		sendUpdate(session)

		local aKey = tostring(session.userIds[1])
		local bKey = tostring(session.userIds[2])
		if session.confirmed[aKey] and session.confirmed[bKey] then
			beginFinalSecurity(session)
		end
		return
	end
end)

--============================================================
-- AJUSTE DE SOLICITUDES + LISTA
--============================================================

SetTradeEnabled.OnServerEvent:Connect(function(player, enabled)
	if typeof(enabled) ~= "boolean" then
		return
	end

	player:SetAttribute(TRADE_ENABLED_ATTR, enabled)

	if not enabled then
		cancelPendingForPlayer(
			player,
			player.DisplayName .. " desactivo las solicitudes de intercambio."
		)
	end

	firePlayerListUpdate()
end)

GetTradePlayers.OnServerInvoke = function(player)
	local result = {}

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player
			and other:GetAttribute(TRADE_ENABLED_ATTR) == true
			and not sessionsByUserId[other.UserId]
			and not pendingBySenderId[other.UserId]
			and not pendingByTargetId[other.UserId]
		then
			local cooldown = math.max(
				0,
				(pairCooldownUntil[pairKey(player.UserId, other.UserId)] or 0) - serverNow()
			)

			table.insert(result, {
				userId = other.UserId,
				name = other.Name,
				displayName = other.DisplayName,
				cooldownRemaining = cooldown,
			})
		end
	end

	table.sort(result, function(a, b)
		return tostring(a.displayName):lower() < tostring(b.displayName):lower()
	end)

	return {
		enabled = player:GetAttribute(TRADE_ENABLED_ATTR) == true,
		players = result,
		serverTime = serverNow(),
	}
end

GetInventorySnapshot.OnServerInvoke = function(player)
	local session = getSession(player)
	if not session or session.closed then
		return {tools = {}, seeds = {}, pets = {}, serverTime = serverNow()}
	end
	return buildInventorySnapshot(player)
end

--============================================================
-- PLAYERS / LIMPIEZA
--============================================================

local function setupPlayer(player)
	if player:GetAttribute(TRADE_ENABLED_ATTR) == nil then
		player:SetAttribute(TRADE_ENABLED_ATTR, true)
	end
end

Players.PlayerAdded:Connect(function(player)
	setupPlayer(player)
	firePlayerListUpdate()
end)

for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	cancelPendingForPlayer(player, player.DisplayName .. " salio del servidor.")

	local session = sessionsByUserId[player.UserId]
	if session then
		closeSession(session, player.DisplayName .. " salio del servidor.")
	end

	lastRequestAt[player.UserId] = nil
	lastActionAt[player.UserId] = nil

	task.defer(firePlayerListUpdate)
end)