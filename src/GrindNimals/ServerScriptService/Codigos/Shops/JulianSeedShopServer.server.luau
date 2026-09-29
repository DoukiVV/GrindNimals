--============================================================
-- JULIAN - TIENDA DE SEMILLAS V4.2 - VENDER TODO LO QUE TIENES
-- Colocar en:
-- ServerScriptService > JulianSeedShopServer
--
-- Hace:
-- - Oculta el nombre flotante de Julian.
-- - Crea el ProximityPrompt "Hablar" con E como Brizabelle.
-- - Valida compras EN EL SERVIDOR.
-- - Cobra Dolares.
-- - Suma semillas al inventario optimizado por cantidades.
-- - Usa exactamente los cultivos compatibles con tu sistema de plantado.
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local MAX_BUY_AMOUNT = 99
local MAX_SELL_AMOUNT = 1000000
local MAX_SHOP_DISTANCE = 18

-- Precio que JULIAN paga al jugador por cada semilla.
local SELL_PRICE_BY_RARITY = {
	Comun = 2,
	Raro = 5,
	["Muy Raro"] = 10,
	Epico = 15,
	Legendario = 35,
}


--============================================================
-- RAREZAS COMPLETAS DE TODAS LAS SEMILLAS
--============================================================

local SEED_RARITY_BY_CROP = {
	-- LEGENDARIO
	SandiaNegra = "Legendario",
	MelonVerde = "Legendario",
	PinaRosa = "Legendario",
	FresaRosa = "Legendario",

	-- EPICO
	Sandia = "Epico",
	Melon = "Epico",
	Durian = "Epico",
	Cacao = "Epico",
	TrufaBlanca = "Epico",
	Mangostan = "Epico",
	Coco = "Epico",
	Calabaza = "Epico",
	Pina = "Epico",

	-- MUY RARO
	Yuca = "Muy Raro",
	TrufaNegra = "Muy Raro",
	Lichi = "Muy Raro",
	FrutaDragon = "Muy Raro",
	Carambola = "Muy Raro",
	Alcachofa = "Muy Raro",

	-- RARO
	Platano = "Raro",
	Fresa = "Raro",
	Mango = "Raro",
	Granada = "Raro",
	Higo = "Raro",
	Remolacha = "Raro",
	LechugaMorada = "Raro",
	ColMorada = "Raro",

	-- COMUN
	Zanahoria = "Comun",
	Papa = "Comun",
	Lechuga = "Comun",
	Col = "Comun",
	Cebolla = "Comun",
	Manzana = "Comun",
	Naranja = "Comun",
	Trigo = "Comun",
}

local RARITY_ORDER = {
	Comun = 1,
	Raro = 2,
	["Muy Raro"] = 3,
	Epico = 4,
	Legendario = 5,
}

--============================================================
-- CATALOGO
--============================================================

local CATALOG = {
	{crop="Platano",        display="Plátano",                    rarity="Raro",     price=10},
	{crop="Fresa",          display="Fresa",                      rarity="Raro",     price=10},
	{crop="Mango",          display="Mango",                      rarity="Raro",     price=10},

	{crop="Zanahoria",      display="Zanahoria",                  rarity="Comun",    price=4},
	{crop="Papa",           display="Papa",                       rarity="Comun",    price=4},
	{crop="Lechuga",        display="Lechuga",                    rarity="Comun",    price=4},
	{crop="Col",            display="Col",                        rarity="Comun",    price=4},
	{crop="Cebolla",        display="Cebolla",                    rarity="Comun",    price=4},
	{crop="Manzana",        display="Manzana",                    rarity="Comun",    price=4},
	{crop="Naranja",        display="Naranja",                    rarity="Comun",    price=4},
	{crop="Trigo",          display="Trigo",                      rarity="Comun",    price=4},

	{crop="Yuca",           display="Yuca",                       rarity="Muy Raro", price=30},
	{crop="TrufaNegra",     display="Trufa negra",                rarity="Muy Raro", price=30},
	{crop="Lichi",          display="Lichi",                      rarity="Muy Raro", price=30},

	{crop="Granada",        display="Granada",                    rarity="Raro",     price=10},
	{crop="Higo",           display="Higo",                       rarity="Raro",     price=10},
	{crop="Remolacha",      display="Remolacha",                  rarity="Raro",     price=10},

	{crop="FrutaDragon",    display="Fruta del dragón",           rarity="Muy Raro", price=30},
	{crop="Carambola",      display="Carambola / Fruta estrella", rarity="Muy Raro", price=30},
	{crop="Alcachofa",      display="Alcachofa",                  rarity="Muy Raro", price=30},

	{crop="LechugaMorada",  display="Lechuga morada",             rarity="Raro",     price=10},
	{crop="ColMorada",      display="Col morada",                 rarity="Raro",     price=10},
}

local CATALOG_BY_CROP = {}
for _, entry in ipairs(CATALOG) do
	CATALOG_BY_CROP[entry.crop] = entry
end

--============================================================
-- REMOTES
--
-- Se crean PRIMERO para que el cliente nunca se quede esperando
-- aunque Julian haya sido renombrado o esté dentro de otra carpeta/modelo.
--============================================================

local remotes = ReplicatedStorage:FindFirstChild("JulianSeedShop")
if remotes and not remotes:IsA("Folder") then
	remotes:Destroy()
	remotes = nil
end

if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "JulianSeedShop"
	remotes.Parent = ReplicatedStorage
end

local function ensureRemoteEvent(name)
	local obj = remotes:FindFirstChild(name)

	if obj and not obj:IsA("RemoteEvent") then
		obj:Destroy()
		obj = nil
	end

	if not obj then
		obj = Instance.new("RemoteEvent")
		obj.Name = name
		obj.Parent = remotes
	end

	return obj
end

local function ensureRemoteFunction(name)
	local obj = remotes:FindFirstChild(name)

	if obj and not obj:IsA("RemoteFunction") then
		obj:Destroy()
		obj = nil
	end

	if not obj then
		obj = Instance.new("RemoteFunction")
		obj.Name = name
		obj.Parent = remotes
	end

	return obj
end

local OpenShop = ensureRemoteEvent("OpenShop")
local GetCatalog = ensureRemoteFunction("GetCatalog")
local BuySeed = ensureRemoteFunction("BuySeed")
local SellSeed = ensureRemoteFunction("SellSeed")

--============================================================
-- CARPETAS
--============================================================

local itemFolder = ServerStorage:WaitForChild("Item")
local semillasFolder = itemFolder:WaitForChild("Semillas")

local interiores = Workspace:WaitForChild("Interiores")
local tienda = interiores:WaitForChild("Tienda Cultivos")

--============================================================
-- BUSCAR A JULIAN DE FORMA ROBUSTA
--
-- Tu error era:
--   WaitForChild("Julian")
--
-- El NPC que tiene JulianSeedShopPrompt no está siendo encontrado
-- como hijo directo con ese nombre durante la ejecución.
--
-- Ahora buscamos:
-- 1) un Model llamado Julian;
-- 2) el Model que contiene JulianSeedShopPrompt;
-- 3) un Model con Humanoid cuyo DisplayName sea Julian.
--============================================================

local function findJulianModel()
	local direct = tienda:FindFirstChild("Julian")
	if direct and direct:IsA("Model") then
		return direct
	end

	for _, obj in ipairs(tienda:GetDescendants()) do
		if obj:IsA("Model") and string.lower(obj.Name) == "julian" then
			return obj
		end
	end

	for _, obj in ipairs(tienda:GetDescendants()) do
		if obj:IsA("ProximityPrompt")
			and (obj.Name == "JulianSeedShopPrompt" or obj.Name == "BrizabelleEggPrompt")
		then
			local model = obj:FindFirstAncestorOfClass("Model")
			if model then
				return model
			end
		end
	end

	for _, obj in ipairs(tienda:GetDescendants()) do
		if obj:IsA("Humanoid") then
			local displayName = tostring(obj.DisplayName or "")
			if string.lower(displayName) == "julian" then
				local model = obj:FindFirstAncestorOfClass("Model")
				if model then
					return model
				end
			end
		end
	end

	return nil
end

local julian = findJulianModel()

if not julian then
	error(
		"[JulianSeedShop] No pude encontrar el NPC. "
			.. "Pon JulianSeedShopPrompt dentro del HumanoidRootPart del NPC "
			.. "que está en Workspace > Interiores > Tienda Cultivos."
	)
end

--============================================================
-- NOMBRES / NORMALIZACION
-- Compatible con tu GardenPlanting.
--============================================================

local function trim(value)
	return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function normalize(value)
	local text = trim(value):lower()
	text = text:gsub("á","a"):gsub("é","e"):gsub("í","i"):gsub("ó","o"):gsub("ú","u"):gsub("ü","u"):gsub("ñ","n")
	text = text:gsub("[%s_%-]+", "")
	return text
end

local cropAliases = {
	-- LEGENDARIO
	[normalize("SandiaNegra")] = "SandiaNegra",
	[normalize("Sandía Negra")] = "SandiaNegra",
	[normalize("Sandia Negra")] = "SandiaNegra",

	[normalize("MelonVerde")] = "MelonVerde",
	[normalize("Melón verde")] = "MelonVerde",
	[normalize("Melon verde")] = "MelonVerde",

	[normalize("PinaRosa")] = "PinaRosa",
	[normalize("Piña rosa")] = "PinaRosa",
	[normalize("Pina rosa")] = "PinaRosa",

	[normalize("FresaRosa")] = "FresaRosa",
	[normalize("Fresa rosa")] = "FresaRosa",

	-- EPICO
	[normalize("Sandia")] = "Sandia",
	[normalize("Sandía")] = "Sandia",

	[normalize("Melon")] = "Melon",
	[normalize("Melón")] = "Melon",

	[normalize("Durian")] = "Durian",

	[normalize("Cacao")] = "Cacao",

	[normalize("TrufaBlanca")] = "TrufaBlanca",
	[normalize("Trufa blanca")] = "TrufaBlanca",

	[normalize("Mangostan")] = "Mangostan",
	[normalize("Mangostán")] = "Mangostan",

	[normalize("Coco")] = "Coco",

	[normalize("Calabaza")] = "Calabaza",

	[normalize("Pina")] = "Pina",
	[normalize("Piña")] = "Pina",

	-- MUY RARO
	[normalize("Yuca")] = "Yuca",

	[normalize("TrufaNegra")] = "TrufaNegra",
	[normalize("Trufa negra")] = "TrufaNegra",
	[normalize("TrufaNegraYBlanca")] = "TrufaNegra",

	[normalize("Lichi")] = "Lichi",

	[normalize("FrutaDragon")] = "FrutaDragon",
	[normalize("Fruta del Dragon")] = "FrutaDragon",
	[normalize("Fruta del dragón")] = "FrutaDragon",

	[normalize("Carambola")] = "Carambola",
	[normalize("Fruta estrella")] = "Carambola",
	[normalize("Carambola / Fruta estrella")] = "Carambola",

	[normalize("Alcachofa")] = "Alcachofa",

	-- RARO
	[normalize("Platano")] = "Platano",
	[normalize("Plátano")] = "Platano",
	[normalize("Platanero")] = "Platano",

	[normalize("Fresa")] = "Fresa",
	[normalize("Mango")] = "Mango",
	[normalize("Granada")] = "Granada",
	[normalize("Higo")] = "Higo",
	[normalize("Remolacha")] = "Remolacha",

	[normalize("LechugaMorada")] = "LechugaMorada",
	[normalize("Lechuga morada")] = "LechugaMorada",

	[normalize("ColMorada")] = "ColMorada",
	[normalize("Col morada")] = "ColMorada",

	-- COMUN
	[normalize("Zanahoria")] = "Zanahoria",
	[normalize("Papa")] = "Papa",
	[normalize("Lechuga")] = "Lechuga",
	[normalize("Col")] = "Col",
	[normalize("Cebolla")] = "Cebolla",
	[normalize("Manzana")] = "Manzana",
	[normalize("Naranja")] = "Naranja",
	[normalize("Trigo")] = "Trigo",
}

local function cropFromToolName(name)
	local key = normalize(name)

	local prefixes = {
		"semillade",
		"semillla de",
		"semillla",
		"semilla",
		"brote",
		"esporas",
	}

	for _, prefixRaw in ipairs(prefixes) do
		local prefix = normalize(prefixRaw)
		if key:sub(1, #prefix) == prefix then
			key = key:sub(#prefix + 1)
			break
		end
	end

	if cropAliases[key] then
		return cropAliases[key]
	end

	-- Fallback: permite nombres como "SemillaDeFrutaDragonTool".
	for aliasKey, canonical in pairs(cropAliases) do
		if key:find(aliasKey, 1, true) then
			return canonical
		end
	end

	return nil
end

local function findSeedTemplate(crop)
	-- Primero intenta coincidencia directa.
	local direct = semillasFolder:FindFirstChild(crop)
	if direct and direct:IsA("Tool") then
		return direct
	end

	for _, item in ipairs(semillasFolder:GetChildren()) do
		if item:IsA("Tool") then
			local byName = cropFromToolName(item.Name)
			local byItemName = cropFromToolName(item:GetAttribute("ItemName"))
			local byCropAttr = item:GetAttribute("SeedCropName")

			if byName == crop
				or byItemName == crop
				or byCropAttr == crop
			then
				return item
			end
		end
	end

	return nil
end


--============================================================
-- SEMILLAS / RAREZA / STACKS
--============================================================

local function canonicalRarity(value)
	local key = normalize(value)

	if key == "comun"
		or key == "common"
	then
		return "Comun"
	elseif key == "raro"
		or key == "rare"
	then
		return "Raro"
	elseif key == "muyraro"
		or key == "veryrare"
	then
		return "Muy Raro"
	elseif key == "epico"
		or key == "epic"
	then
		return "Epico"
	elseif key == "legendario"
		or key == "legendary"
	then
		return "Legendario"
	end

	return nil
end

local function getSeedStackAmount(tool)
	if not tool or not tool:IsA("Tool") then
		return 0
	end

	local amount =
		tonumber(
			tool:GetAttribute(
				"SeedStackQuantity"
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
		99
	)
end

local function isSeedTool(tool)
	if not tool or not tool:IsA("Tool") then
		return false
	end

	if tool:GetAttribute("IsSeed") == true then
		return true
	end

	if tool:GetAttribute("SeedStackQuantity") ~= nil then
		return true
	end

	if tool:GetAttribute("SeedCropName") ~= nil then
		return true
	end

	local itemType =
		normalize(
			tool:GetAttribute(
				"ItemType"
			)
		)

	if itemType == "cultivo"
		or itemType == "crop"
		or itemType == "seed"
	then
		return true
	end

	return
		cropFromToolName(
			tool:GetAttribute(
				"ItemName"
			)
			or tool.Name
		)
		~= nil
end

local function getSeedCrop(tool)
	if not isSeedTool(tool) then
		return nil
	end

	local attr =
		tool:GetAttribute(
			"SeedCropName"
		)

	if typeof(attr) == "string"
		and trim(attr) ~= ""
	then
		return trim(attr)
	end

	local byItem =
		cropFromToolName(
			tool:GetAttribute(
				"ItemName"
			)
		)

	if byItem then
		return byItem
	end

	local byName =
		cropFromToolName(
			tool.Name
		)

	if byName then
		return byName
	end

	-- Fallback para semillas nuevas que no estén en cropAliases.
	-- El ToolName sigue siendo un ID estable para poder venderlas.
	local fallback =
		trim(
			tool.Name
		)

	if fallback ~= "" then
		return fallback
	end

	return nil
end

local function getSeedTemplateForTool(tool)
	if not tool or not tool:IsA("Tool") then
		return nil
	end

	local exact =
		semillasFolder:FindFirstChild(
			tool.Name
		)

	if exact and exact:IsA("Tool") then
		return exact
	end

	local crop =
		getSeedCrop(
			tool
		)

	if crop then
		return
			findSeedTemplate(
				crop
			)
	end

	return nil
end

local function rarityFromSeedIdentity(
	crop,
	tool
)
	if
		typeof(crop) == "string"
		and SEED_RARITY_BY_CROP[
		crop
		]
	then
		return
			SEED_RARITY_BY_CROP[
		crop
		]
	end

	local candidates = {}

	if tool then
		table.insert(
			candidates,
			tool.Name
		)

		table.insert(
			candidates,
			tool:GetAttribute(
				"ItemName"
			)
		)

		table.insert(
			candidates,
			tool:GetAttribute(
				"BackpackDisplayName"
			)
		)

		table.insert(
			candidates,
			tool:GetAttribute(
				"SeedCropName"
			)
		)
	end

	if crop then
		table.insert(
			candidates,
			crop
		)
	end

	for _, candidate in ipairs(
		candidates
		) do
		if
			typeof(candidate) == "string"
			and trim(candidate) ~= ""
		then
			local canonical =
				cropFromToolName(
					candidate
				)

			if
				canonical
				and SEED_RARITY_BY_CROP[
				canonical
				]
			then
				return
					SEED_RARITY_BY_CROP[
				canonical
				]
			end

			local normalized =
				normalize(
					candidate
				)

			normalized =
				normalized:gsub(
					"^semillade",
					""
				)

			normalized =
				normalized:gsub(
					"^semilla",
					""
				)

			for cropName, rarity in pairs(
				SEED_RARITY_BY_CROP
				) do
				if
					normalize(
						cropName
					)
						== normalized
				then
					return rarity
				end
			end
		end
	end

	return nil
end

local function getSeedRarity(tool)
	if not tool then
		return nil
	end

	for _, attrName in ipairs({
		"SeedRarity",
		"Rarity",
		"Rareza",
		}) do
		local rarity =
			canonicalRarity(
				tool:GetAttribute(
					attrName
				)
			)

		if rarity then
			return rarity
		end
	end

	local template =
		getSeedTemplateForTool(
			tool
		)

	if template then
		for _, attrName in ipairs({
			"SeedRarity",
			"Rarity",
			"Rareza",
			}) do
			local rarity =
				canonicalRarity(
					template:GetAttribute(
						attrName
					)
				)

			if rarity then
				return rarity
			end
		end
	end

	local crop =
		getSeedCrop(
			tool
		)

	-- Fuente principal para vender: tabla completa del juego.
	local explicitRarity =
		rarityFromSeedIdentity(
			crop,
			tool
		)

	if explicitRarity then
		return explicitRarity
	end

	-- Compatibilidad con el catálogo de compra de Julian.
	local catalogEntry =
		crop
		and CATALOG_BY_CROP[
	crop
	]

	if catalogEntry then
		return
			canonicalRarity(
				catalogEntry.rarity
			)
	end

	return nil
end

local function seedDisplayName(tool)
	if not tool then
		return "Semilla"
	end

	local display =
		tool:GetAttribute(
			"BackpackDisplayName"
		)

	if typeof(display) == "string"
		and trim(display) ~= ""
	then
		display =
			trim(display)
	else
		display =
			trim(
				tool:GetAttribute(
					"ItemName"
				)
				or tool.Name
			)
	end

	-- En la tienda se ve más limpio sin repetir "Semilla".
	display =
		display:gsub(
			"^[Ss]emilla%s+[Dd]e%s+",
			""
		)

	display =
		display:gsub(
			"^[Ss]emilla%s+",
			""
		)

	if display == "" then
		display = tool.Name
	end

	return display
end

local function getSeedSellKey(tool)
	if not tool then
		return nil
	end

	-- Tool.Name es estable entre todos los stacks de la misma semilla
	-- en SeedSaveV9.
	return trim(tool.Name)
end

local function collectSeedTools(player)
	local result = {}

	local function scan(container)
		if not container then
			return
		end

		for _, child in ipairs(
			container:GetChildren()
			) do
			if
				child:IsA("Tool")
				and isSeedTool(
					child
				)
			then
				table.insert(
					result,
					child
				)
			end
		end
	end

	scan(
		player:FindFirstChildOfClass(
			"Backpack"
		)
	)

	scan(
		player.Character
	)

	return result
end

local function buildSellInventory(player)
	local groups = {}

	for _, tool in ipairs(
		collectSeedTools(
			player
		)
		) do
		local sellKey =
			getSeedSellKey(
				tool
			)

		if sellKey then
			local group =
				groups[sellKey]

			if not group then
				local rarity =
					getSeedRarity(
						tool
					)

				local crop =
					getSeedCrop(
						tool
					)

				local icon =
					tool.TextureId
					or ""

				if icon == "" then
					local template =
						getSeedTemplateForTool(
							tool
						)

					if template then
						icon =
							template.TextureId
							or ""
					end
				end

				group = {
					sellKey =
						sellKey,
					crop =
						crop
						or sellKey,
					display =
						seedDisplayName(
							tool
						),
					rarity =
						rarity
						or "Desconocida",
					price =
						rarity
						and SELL_PRICE_BY_RARITY[
					rarity
					]
						or 0,
					icon =
						icon,
					toolName =
						tool.Name,
					ownedCount =
						0,
					available =
						rarity ~= nil
						and SELL_PRICE_BY_RARITY[
					rarity
					] ~= nil,
				}

				groups[sellKey] =
					group
			end

			group.ownedCount +=
				getSeedStackAmount(
					tool
				)
		end
	end

	local result = {}

	for _, group in pairs(
		groups
		) do
		if group.ownedCount > 0 then
			table.insert(
				result,
				group
			)
		end
	end

	table.sort(
		result,
		function(a, b)
			local ar =
				RARITY_ORDER[
			a.rarity
			]
				or 999

			local br =
				RARITY_ORDER[
			b.rarity
			]
				or 999

			if ar ~= br then
				return ar < br
			end

			return
				tostring(
					a.display
				):lower()
				<
				tostring(
					b.display
				):lower()
		end
	)

	for index, entry in ipairs(
		result
		) do
		entry.order =
			index
	end

	return result
end

local function applySeedStackAmount(
	tool,
	amount
)
	amount =
		math.clamp(
			math.floor(
				tonumber(amount)
				or 1
			),
			1,
			99
		)

	tool:SetAttribute(
		"SeedStackQuantity",
		amount
	)

	tool:SetAttribute(
		"Cantidad",
		amount
	)
end

local function getForceSeedSave()
	local forceSave =
		ServerScriptService:FindFirstChild(
			"ForceSeedInventorySave"
		)

	if
		forceSave
		and forceSave:IsA(
			"BindableFunction"
		)
	then
		return forceSave
	end

	return nil
end

local function forceSaveSeeds(player)
	local forceSave =
		getForceSeedSave()

	if not forceSave then
		return
			false,
			"No existe ForceSeedInventorySave."
	end

	local invokeOk, resultOk, resultMessage =
		pcall(function()
			return forceSave:Invoke(
				player
			)
		end)

	if not invokeOk then
		return
			false,
			tostring(resultOk)
	end

	return
		resultOk == true,
		tostring(
			resultMessage
			or ""
		)
end

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

local function getMoneyValue(player)
	local containers = {
		player:FindFirstChild("leaderstats"),
		player:FindFirstChild("Stats"),
		player:FindFirstChild("Data"),
		player,
	}

	for _, container in ipairs(containers) do
		if container then
			for _, name in ipairs(MONEY_NAMES) do
				local value = container:FindFirstChild(name)
				if value and (value:IsA("IntValue") or value:IsA("NumberValue")) then
					return value
				end
			end
		end
	end

	return nil
end

--============================================================
-- JULIAN
--============================================================

local humanoid = julian:FindFirstChildOfClass("Humanoid")
	or julian:FindFirstChildWhichIsA("Humanoid", true)

local function hideJulianOverheadName()
	if not humanoid then
		warn("[JulianSeedShop] Julian no tiene Humanoid; no puedo ocultar el nombre Roblox.")
		return
	end

	-- Quita COMPLETAMENTE el nombre/vida que Roblox muestra sobre la cabeza.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0

	-- Refuerzo: si otro script intenta cambiarlo, lo volvemos a ocultar.
	pcall(function()
		humanoid.DisplayName = " "
	end)
end

hideJulianOverheadName()

if humanoid then
	humanoid:GetPropertyChangedSignal("DisplayDistanceType"):Connect(function()
		if humanoid.DisplayDistanceType ~= Enum.HumanoidDisplayDistanceType.None then
			task.defer(hideJulianOverheadName)
		end
	end)

	humanoid:GetPropertyChangedSignal("NameDisplayDistance"):Connect(function()
		if humanoid.NameDisplayDistance ~= 0 then
			task.defer(hideJulianOverheadName)
		end
	end)

	humanoid:GetPropertyChangedSignal("HealthDisplayDistance"):Connect(function()
		if humanoid.HealthDisplayDistance ~= 0 then
			task.defer(hideJulianOverheadName)
		end
	end)
end

-- Si el NPC trae un BillboardGui viejo específicamente para su nombre,
-- lo quitamos. NO tocamos ProximityPrompts.
local head = julian:FindFirstChild("Head", true)
if head then
	for _, child in ipairs(head:GetChildren()) do
		if child:IsA("BillboardGui") then
			local lowerName = string.lower(child.Name)
			if lowerName:find("name", 1, true)
				or lowerName:find("nombre", 1, true)
				or lowerName == "nametag"
			then
				child:Destroy()
			end
		end
	end
end

local julianRoot = julian:FindFirstChild("HumanoidRootPart")
	or julian:FindFirstChild("HumanoidRootPart", true)
	or julian.PrimaryPart
	or julian:FindFirstChildWhichIsA("BasePart", true)

if not julianRoot then
	error("[JulianSeedShop] Julian necesita HumanoidRootPart o una BasePart.")
end

--============================================================
-- PROMPT DE JULIAN
--
-- Si ya copiaste el BrizabelleEggPrompt dentro de Julian,
-- REUTILIZAMOS ESE MISMO ProximityPrompt para conservar
-- exactamente el mismo diseño/configuracion.
--
-- IMPORTANTE:
-- Lo renombramos a JulianSeedShopPrompt para que el
-- BrizabelleEggClient NO lo confunda con Brizabelle.
--============================================================

local prompt = julianRoot:FindFirstChild("JulianSeedShopPrompt")

if prompt and not prompt:IsA("ProximityPrompt") then
	prompt:Destroy()
	prompt = nil
end

-- Si ya pusiste una copia del prompt de Brizabelle en Julian,
-- la usamos en vez de crear otra.
if not prompt then
	local copiedBrizabellePrompt = julianRoot:FindFirstChild("BrizabelleEggPrompt")

	if copiedBrizabellePrompt and copiedBrizabellePrompt:IsA("ProximityPrompt") then
		prompt = copiedBrizabellePrompt
	else
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = julianRoot
	end
end

-- MISMA configuracion de Brizabelle.
prompt.Name = "JulianSeedShopPrompt"
prompt.ActionText = "Hablar"
prompt.ObjectText = "Julian"
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
prompt.Style = Enum.ProximityPromptStyle.Custom
prompt.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
prompt.HoldDuration = 0.45
prompt.MaxActivationDistance = 12
prompt.RequiresLineOfSight = false
prompt.Enabled = true
prompt.Parent = julianRoot

prompt.Triggered:Connect(function(player)
	OpenShop:FireClient(player)
end)

--============================================================
-- SEGURIDAD
--============================================================

local function playerNearJulian(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	return (root.Position - julianRoot.Position).Magnitude <= MAX_SHOP_DISTANCE
end

--============================================================
-- CATALOGO PARA EL CLIENTE
--============================================================

GetCatalog.OnServerInvoke = function(player)
	local money =
		getMoneyValue(
			player
		)

	local result = {}

	for index, entry in ipairs(
		CATALOG
		) do
		local template =
			findSeedTemplate(
				entry.crop
			)

		local icon = ""

		if template then
			icon =
				template.TextureId
				or ""
		end

		table.insert(
			result,
			{
				order =
					index,
				crop =
					entry.crop,
				display =
					entry.display,
				rarity =
					entry.rarity,
				price =
					entry.price,
				icon =
					icon,
				toolName =
					template
					and template.Name
					or "",
				available =
					template ~= nil,
			}
		)
	end

	local sellItems = {}

	if
		player:GetAttribute(
			"SeedInventoryLoaded"
		) == true
	then
		sellItems =
			buildSellInventory(
				player
			)
	end

	return {
		items =
			result,
		sellItems =
			sellItems,
		money =
			money
			and math.floor(
				money.Value
			)
			or 0,
		sellPrices =
			SELL_PRICE_BY_RARITY,
	}
end

--============================================================
-- COMPRAR
--============================================================

local busy = {}

BuySeed.OnServerInvoke = function(
	player,
	requestedCrop,
	requestedAmount
)
	if busy[player] then
		return {
			ok = false,
			message = "Espera un momento.",
		}
	end

	if not playerNearJulian(
		player
		) then
		return {
			ok = false,
			message = "Acércate a Julian para comprar.",
		}
	end

	if
		player:GetAttribute(
			"SeedInventoryLoaded"
		) ~= true
	then
		return {
			ok = false,
			message = "Tu inventario de semillas todavía está cargando.",
		}
	end

	local crop =
		tostring(
			requestedCrop
			or ""
		)

	local entry =
		CATALOG_BY_CROP[
	crop
	]

	if not entry then
		return {
			ok = false,
			message = "Esa semilla no está a la venta.",
		}
	end

	local amount =
		math.clamp(
			math.floor(
				tonumber(
					requestedAmount
				)
				or 0
			),
			1,
			MAX_BUY_AMOUNT
		)

	local template =
		findSeedTemplate(
			crop
		)

	if not template then
		return {
			ok = false,
			message =
				"Falta la semilla de "
				.. entry.display
				.. " en ServerStorage > Item > Semillas.",
		}
	end

	local backpack =
		player:FindFirstChildOfClass(
			"Backpack"
		)

	if not backpack then
		return {
			ok = false,
			message = "No se encontró tu mochila.",
		}
	end

	local money =
		getMoneyValue(
			player
		)

	if not money then
		return {
			ok = false,
			message = "No se encontró tu dinero.",
		}
	end

	local total =
		entry.price
		* amount

	if money.Value < total then
		return {
			ok = false,
			message = "No tienes suficientes dólares.",
			money =
				math.floor(
					money.Value
				),
		}
	end

	busy[player] =
		true

	-- V9: un solo Tool puede representar hasta x99.
	local clone =
		template:Clone()

	local itemName =
		clone:GetAttribute(
			"ItemName"
		)

	if typeof(itemName) ~= "string"
		or itemName == ""
	then
		itemName =
			template.Name
	end

	clone:SetAttribute(
		"ItemName",
		itemName
	)

	clone:SetAttribute(
		"ItemType",
		"Cultivo"
	)

	clone:SetAttribute(
		"IsSeed",
		true
	)

	clone:SetAttribute(
		"SeedCropName",
		crop
	)

	clone:SetAttribute(
		"SeedRarity",
		entry.rarity
	)

	clone:SetAttribute(
		"BackpackDisplayName",
		"Semilla "
			.. entry.display
	)

	applySeedStackAmount(
		clone,
		amount
	)

	money.Value -=
		total

	clone.Parent =
		backpack

	local saved, saveMessage =
		forceSaveSeeds(
			player
		)

	if not saved then
		if clone.Parent then
			clone:Destroy()
		end

		money.Value +=
			total

		busy[player] =
			nil

		warn(
			"[JulianSeedShop] Compra revertida porque no se pudo guardar: "
				.. tostring(
					saveMessage
				)
		)

		return {
			ok = false,
			message = "No se pudo guardar la compra. Tu dinero fue devuelto.",
			money =
				math.floor(
					money.Value
				),
		}
	end

	busy[player] =
		nil

	return {
		ok = true,
		message =
			"Compraste x"
			.. tostring(
				amount
			)
			.. " "
			.. entry.display
			.. ".",
		money =
			math.floor(
				money.Value
			),
		crop =
			crop,
		amount =
			amount,
		total =
			total,
		toolName =
			template.Name,
	}
end

--============================================================
-- VENDER SEMILLAS
--============================================================

SellSeed.OnServerInvoke = function(
	player,
	requestedSellKey,
	requestedAmount
)
	if busy[player] then
		return {
			ok = false,
			message = "Espera un momento.",
		}
	end

	if not playerNearJulian(
		player
		) then
		return {
			ok = false,
			message = "Acércate a Julian para vender.",
		}
	end

	if
		player:GetAttribute(
			"SeedInventoryLoaded"
		) ~= true
	then
		return {
			ok = false,
			message = "Tu inventario de semillas todavía está cargando.",
		}
	end

	local sellKey =
		trim(
			requestedSellKey
			or ""
		)

	if sellKey == "" then
		return {
			ok = false,
			message = "Semilla no válida.",
		}
	end

	local requested =
		math.floor(
			tonumber(
				requestedAmount
			)
			or 0
		)

	if
		requested < 1
		or requested
		> MAX_SELL_AMOUNT
	then
		return {
			ok = false,
			message = "Cantidad de venta no válida.",
		}
	end

	local matchingTools = {}
	local available = 0
	local firstTool = nil

	for _, tool in ipairs(
		collectSeedTools(
			player
		)
		) do
		if
			getSeedSellKey(
				tool
			) == sellKey
		then
			firstTool =
				firstTool
				or tool

			local stackAmount =
				getSeedStackAmount(
					tool
				)

			available +=
				stackAmount

			table.insert(
				matchingTools,
				{
					tool =
						tool,
					amount =
						stackAmount,
				}
			)
		end
	end

	if
		not firstTool
		or available <= 0
	then
		return {
			ok = false,
			message = "Ya no tienes esa semilla.",
			ownedCount = 0,
		}
	end

	if available < requested then
		return {
			ok = false,
			message =
				"Solo tienes x"
				.. tostring(
					available
				)
				.. ".",
			ownedCount =
				available,
		}
	end

	local saleDisplayName =
		seedDisplayName(
			firstTool
		)

	local rarity =
		getSeedRarity(
			firstTool
		)

	local unitPrice =
		rarity
		and SELL_PRICE_BY_RARITY[
	rarity
	]
		or nil

	if not unitPrice then
		return {
			ok = false,
			message =
				"Esta semilla no tiene una rareza válida configurada.",
			ownedCount =
				available,
		}
	end

	local money =
		getMoneyValue(
			player
		)

	if not money then
		return {
			ok = false,
			message = "No se encontró tu dinero.",
			ownedCount =
				available,
		}
	end

	busy[player] =
		true

	-- Quitamos primero las semillas del inventario físico.
	-- Los stacks completos se mueven temporalmente fuera del jugador;
	-- así SeedSaveV9 no los cuenta durante ForceSave.
	local transactionFolder =
		Instance.new(
			"Folder"
		)

	transactionFolder.Name =
		"_JulianSeedSale_"
		.. tostring(
			player.UserId
		)

	transactionFolder.Parent =
		ServerStorage

	local changes = {}
	local remaining =
		requested

	-- Consumir stacks pequeños primero.
	table.sort(
		matchingTools,
		function(a, b)
			return
				a.amount
				< b.amount
		end
	)

	for _, info in ipairs(
		matchingTools
		) do
		if remaining <= 0 then
			break
		end

		local tool =
			info.tool

		if
			tool
			and tool.Parent
		then
			local originalParent =
				tool.Parent

			local oldAmount =
				info.amount

			if remaining >= oldAmount then
				table.insert(
					changes,
					{
						tool =
							tool,
						parent =
							originalParent,
						amount =
							oldAmount,
						moved =
							true,
					}
				)

				remaining -=
					oldAmount

				tool.Parent =
					transactionFolder
			else
				table.insert(
					changes,
					{
						tool =
							tool,
						parent =
							originalParent,
						amount =
							oldAmount,
						moved =
							false,
					}
				)

				applySeedStackAmount(
					tool,
					oldAmount
					- remaining
				)

				remaining =
					0
			end
		end
	end

	if remaining > 0 then
		-- Algo cambió durante la transacción: revertir.
		for _, change in ipairs(
			changes
			) do
			local tool =
				change.tool

			if tool then
				applySeedStackAmount(
					tool,
					change.amount
				)

				if change.moved then
					local target =
						change.parent

					if
						not target
						or not target.Parent
					then
						target =
							player:FindFirstChildOfClass(
								"Backpack"
							)
					end

					if target then
						tool.Parent =
							target
					end
				end
			end
		end

		transactionFolder:Destroy()
		busy[player] =
			nil

		return {
			ok = false,
			message = "Tu inventario cambió. Intenta vender otra vez.",
			ownedCount =
				available,
		}
	end

	local saved, saveMessage =
		forceSaveSeeds(
			player
		)

	if not saved then
		-- Restaurar exactamente los stacks anteriores.
		for _, change in ipairs(
			changes
			) do
			local tool =
				change.tool

			if tool then
				applySeedStackAmount(
					tool,
					change.amount
				)

				if change.moved then
					local target =
						change.parent

					if
						not target
						or not target.Parent
					then
						target =
							player:FindFirstChildOfClass(
								"Backpack"
							)
					end

					if target then
						tool.Parent =
							target
					end
				end
			end
		end

		transactionFolder:Destroy()

		busy[player] =
			nil

		warn(
			"[JulianSeedShop] Venta revertida porque no se pudo guardar: "
				.. tostring(
					saveMessage
				)
		)

		return {
			ok = false,
			message = "No se pudo guardar la venta. Tus semillas fueron restauradas.",
			money =
				math.floor(
					money.Value
				),
			ownedCount =
				available,
		}
	end

	-- El guardado de semillas ya confirmó la venta.
	-- IMPORTANTE:
	-- SeedSaveV9 revisa ChildRemoved con un pequeño delay.
	-- Dejamos los Tools vendidos temporalmente en ServerStorage
	-- para que V9 vea que fueron MOVIDOS y no los interprete
	-- como una semilla consumida.
	task.delay(
		0.25,
		function()
			if transactionFolder.Parent then
				transactionFolder:Destroy()
			end
		end
	)

	local total =
		unitPrice
		* requested

	money.Value +=
		total

	busy[player] =
		nil

	local remainingOwned =
		available
	- requested

	return {
		ok = true,
		message =
			"Vendiste x"
			.. tostring(
				requested
			)
			.. " "
			.. saleDisplayName
			.. " por "
			.. tostring(
				total
			)
			.. "$.",
		money =
			math.floor(
				money.Value
			),
		sellKey =
			sellKey,
		amount =
			requested,
		unitPrice =
			unitPrice,
		total =
			total,
		ownedCount =
			remainingOwned,
		rarity =
			rarity,
	}
end

Players.PlayerRemoving:Connect(function(player)
	busy[player] = nil
end)