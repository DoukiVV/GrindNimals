local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Players = game:GetService("Players")

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


-- FASE 3B:
-- Frank ya no clona/reemplaza directamente la mascota activa.
-- La creación del follower pertenece a PetSpawnService.
local PetSpawnService = require(
	ServerScriptService
		:WaitForChild("PetSystem")
		:WaitForChild("Services")
		:WaitForChild("PetSpawnService")
)

--==============================================================
-- PET UPGRADE SYSTEM - FRANK
-- Oveja base -> gris -> verde -> azul -> morado -> dorado
--==============================================================

local systemFolder = ReplicatedStorage:FindFirstChild("PetUpgradeSystem")
if not systemFolder then
	systemFolder = Instance.new("Folder")
	systemFolder.Name = "PetUpgradeSystem"
	systemFolder.Parent = ReplicatedStorage
end

local function remoteFunction(name)
	local r = systemFolder:FindFirstChild(name)
	if r and not r:IsA("RemoteFunction") then r:Destroy(); r = nil end
	if not r then
		r = Instance.new("RemoteFunction")
		r.Name = name
		r.Parent = systemFolder
	end
	return r
end

local function remoteEvent(name)
	local r = systemFolder:FindFirstChild(name)
	if r and not r:IsA("RemoteEvent") then r:Destroy(); r = nil end
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = systemFolder
	end
	return r
end

local GetUpgradeInfo = remoteFunction("GetUpgradeInfo")
local UpgradePet = remoteFunction("UpgradePet")
local OpenUpgradeUI = remoteEvent("OpenUpgradeUI")

local UPGRADE_ORDER = {
	Base = "Comun",
	Comun = "Poco comun",
	["Poco comun"] = "Raro",
	Raro = "Epico",
	Epico = "Legendario",
}

local DISPLAY = {
	Base = "Base",
	Comun = "Común",
	["Poco comun"] = "Poco común",
	Raro = "Raro",
	Epico = "Épico",
	Legendario = "Legendario",
}

local COLOR_NAME = {
	Base = "Sin pañuelo",
	Comun = "Gris",
	["Poco comun"] = "Verde",
	Raro = "Azul",
	Epico = "Morado",
	Legendario = "Dorado",
}

-- Nombres EXACTOS de tus carpetas según el Explorador que enseñaste.
local VARIANT_FOLDERS = {
	Comun = "Mascotas pañuelos grises",
	["Poco comun"] = "Mascotas pañuelos verdes",
	Raro = "Mascotas pañuelos azul",
	Epico = "Mascotas pañuelos morado",
	Legendario = "Mascotas pañuelos dorado",
}

-- Una unidad de cada material.
-- Puedes cambiar las cantidades aquí cuando quieras.
local RECIPES = {
	["Oveja"] = {
		Base = {
			{display="Manzana", aliases={"Manzana"}, amount=30},
			{display="Naranja", aliases={"Naranja"}, amount=30},
			{display="Zanahoria", aliases={"Zanahoria"}, amount=30},
		},
		Comun = {
			{display="Plátano", aliases={"Platano","Plátano"}, amount=25},
			{display="Mango", aliases={"Mango"}, amount=25},
		},
		["Poco comun"] = {
			{display="Fruta del dragón", aliases={"FrutaDragon","Fruta del dragon","Fruta del dragón"}, amount=20},
			{display="Trufa negra", aliases={"TrufaNegra","Trufa negra"}, amount=20},
		},
		Raro = {
			{display="Sandía", aliases={"Sandia","Sandía"}, amount=15},
			{display="Piña", aliases={"Piña","Pina"}, amount=15},
		},
		Epico = {
			{display="Melón verde", aliases={"MelonVerde","Melon verde","Melón verde"}, amount=10},
			{display="Piña rosa", aliases={"PiñaRosa","PinaRosa","Piña rosa"}, amount=10},
		},
	},

	["Huron"] = {
		Base = {
			{display="Lechuga", aliases={"Lechuga"}, amount=30},
			{display="Trigo", aliases={"Trigo"}, amount=30},
			{display="Cebolla", aliases={"Cebolla"}, amount=30},
		},
		Comun = {
			{display="Remolacha", aliases={"Remolacha"}, amount=25},
			{display="Lechuga morada", aliases={"LechugaMorada","Lechuga morada"}, amount=25},
		},
		["Poco comun"] = {
			{display="Yuca", aliases={"Yuca"}, amount=20},
			{display="Alcachofa", aliases={"Alcachofa"}, amount=20},
		},
		Raro = {
			{display="Coco", aliases={"Coco"}, amount=15},
			{display="Cacao", aliases={"Cacao"}, amount=15},
		},
		Epico = {
			{display="Sandía negra", aliases={"SandiaNegra","Sandia negra","Sandía negra"}, amount=10},
			{display="Fresa blanca", aliases={"FresaBlanca","Fresa blanca"}, amount=10},
		},
	},

	["Pez dorado"] = {
		Base = {
			{display="Lechuga", aliases={"Lechuga"}, amount=60},
			{display="Col", aliases={"Col"}, amount=30},
		},
		Comun = {
			{display="Lechuga morada", aliases={"LechugaMorada","Lechuga morada"}, amount=25},
			{display="Col morada", aliases={"ColMorada","Col morada"}, amount=25},
		},
		["Poco comun"] = {
			{display="Carambola", aliases={"Carambola"}, amount=20},
			{display="Alcachofa", aliases={"Alcachofa"}, amount=20},
		},
		Raro = {
			{display="Calabaza", aliases={"Calabaza"}, amount=15},
			{display="Melón", aliases={"Melon","Melón"}, amount=15},
		},
		Epico = {
			{display="Sandía negra", aliases={"SandiaNegra","Sandia negra","Sandía negra"}, amount=10},
			{display="Melón verde", aliases={"MelonVerde","Melon verde","Melón verde"}, amount=10},
		},
	},

	["Hamster"] = {
		Base = {
			{display="Lechuga", aliases={"Lechuga"}, amount=30},
			{display="Manzana", aliases={"Manzana"}, amount=30},
			{display="Col", aliases={"Col"}, amount=30},
		},
		Comun = {
			{display="Lechuga morada", aliases={"LechugaMorada","Lechuga morada"}, amount=25},
			{display="Higo", aliases={"Higo"}, amount=25},
		},
		["Poco comun"] = {
			{display="Trufa negra", aliases={"TrufaNegra","Trufa negra"}, amount=20},
			{display="Alcachofa", aliases={"Alcachofa"}, amount=20},
		},
		Raro = {
			{display="Rambután", aliases={"Rambutan","Rambután"}, amount=15},
			{display="Piña", aliases={"Piña","Pina"}, amount=15},
		},
		Epico = {
			{display="Sandía negra", aliases={"SandiaNegra","Sandia negra","Sandía negra"}, amount=10},
			{display="Piña rosa", aliases={"PiñaRosa","PinaRosa","Piña rosa"}, amount=10},
		},
	},

	["Perico"] = {
		Base = {
			{display="Manzana", aliases={"Manzana"}, amount=30},
			{display="Naranja", aliases={"Naranja"}, amount=30},
			{display="Cebolla", aliases={"Cebolla"}, amount=30},
		},
		Comun = {
			{display="Granada", aliases={"Granada"}, amount=25},
			{display="Fresa", aliases={"Fresa"}, amount=25},
		},
		["Poco comun"] = {
			{display="Lichi", aliases={"Lichi"}, amount=20},
			{display="Fruta del dragón", aliases={"FrutaDragon","Fruta del dragon","Fruta del dragón"}, amount=20},
		},
		Raro = {
			{display="Sandía", aliases={"Sandia","Sandía"}, amount=15},
			{display="Melón", aliases={"Melon","Melón"}, amount=15},
		},
		Epico = {
			{display="Sandía negra", aliases={"SandiaNegra","Sandia negra","Sandía negra"}, amount=10},
			{display="Melón verde", aliases={"MelonVerde","Melon verde","Melón verde"}, amount=10},
		},
	},

	["Tortuga"] = {
		Base = {
			{display="Manzana", aliases={"Manzana"}, amount=30},
			{display="Naranja", aliases={"Naranja"}, amount=30},
			{display="Lechuga", aliases={"Lechuga"}, amount=30},
		},
		Comun = {
			{display="Mango", aliases={"Mango"}, amount=25},
			{display="Plátano", aliases={"Platano","Plátano"}, amount=25},
		},
		["Poco comun"] = {
			{display="Carambola", aliases={"Carambola"}, amount=20},
			{display="Fruta del dragón", aliases={"FrutaDragon","Fruta del dragon","Fruta del dragón"}, amount=20},
		},
		Raro = {
			{display="Sandía", aliases={"Sandia","Sandía"}, amount=15},
			{display="Piña", aliases={"Piña","Pina"}, amount=15},
		},
		Epico = {
			{display="Fresa blanca", aliases={"FresaBlanca","Fresa blanca"}, amount=10},
			{display="Melón verde", aliases={"MelonVerde","Melon verde","Melón verde"}, amount=10},
		},
	},

	["Perro"] = {
		Base = {
			{display="Zanahoria", aliases={"Zanahoria"}, amount=30},
			{display="Papa", aliases={"Papa"}, amount=30},
			{display="Trigo", aliases={"Trigo"}, amount=30},
		},
		Comun = {
			{display="Remolacha", aliases={"Remolacha"}, amount=25},
			{display="Lechuga morada", aliases={"LechugaMorada","Lechuga morada"}, amount=25},
		},
		["Poco comun"] = {
			{display="Yuca", aliases={"Yuca"}, amount=20},
			{display="Trufa negra", aliases={"TrufaNegra","Trufa negra"}, amount=20},
		},
		Raro = {
			{display="Durián", aliases={"Durian","Durián"}, amount=15},
			{display="Trufa blanca", aliases={"TrufaBlanca","Trufa blanca"}, amount=15},
		},
		Epico = {
			{display="Sandía negra", aliases={"SandiaNegra","Sandia negra","Sandía negra"}, amount=10},
			{display="Piña rosa", aliases={"PiñaRosa","PinaRosa","Piña rosa"}, amount=10},
		},
	},

	["Gato"] = {
		Base = {
			{display="Papa", aliases={"Papa"}, amount=30},
			{display="Naranja", aliases={"Naranja"}, amount=30},
			{display="Trigo", aliases={"Trigo"}, amount=30},
		},
		Comun = {
			{display="Higo", aliases={"Higo"}, amount=25},
			{display="Col morada", aliases={"ColMorada","Col morada"}, amount=25},
		},
		["Poco comun"] = {
			{display="Alcachofa", aliases={"Alcachofa"}, amount=20},
			{display="Carambola", aliases={"Carambola"}, amount=20},
		},
		Raro = {
			{display="Calabaza", aliases={"Calabaza"}, amount=15},
			{display="Durián", aliases={"Durian","Durián"}, amount=15},
		},
		Epico = {
			{display="Fresa blanca", aliases={"FresaBlanca","Fresa blanca"}, amount=10},
			{display="Sandía verde", aliases={"SandiaVerde","Sandia verde","Sandía verde"}, amount=10},
		},
	},

	["Conejo"] = {
		Base = {
			{display="Cebolla", aliases={"Cebolla"}, amount=30},
			{display="Col", aliases={"Col"}, amount=30},
			{display="Lechuga", aliases={"Lechuga"}, amount=30},
		},
		Comun = {
			{display="Lechuga morada", aliases={"LechugaMorada","Lechuga morada"}, amount=25},
			{display="Col morada", aliases={"ColMorada","Col morada"}, amount=25},
		},
		["Poco comun"] = {
			{display="Fruta del dragón", aliases={"FrutaDragon","Fruta del dragon","Fruta del dragón"}, amount=20},
			{display="Lichi", aliases={"Lichi"}, amount=20},
		},
		Raro = {
			{display="Trufa blanca", aliases={"TrufaBlanca","Trufa blanca"}, amount=15},
			{display="Rambután", aliases={"Rambutan","Rambután"}, amount=15},
		},
		Epico = {
			{display="Fresa blanca", aliases={"FresaBlanca","Fresa blanca"}, amount=10},
			{display="Melón verde", aliases={"MelonVerde","Melon verde","Melón verde"}, amount=10},
		},
	},
}

local function normalize(s)
	s = tostring(s or ""):lower()
	s = s:gsub("á","a"):gsub("é","e"):gsub("í","i"):gsub("ó","o"):gsub("ú","u"):gsub("ñ","n")
	s = s:gsub("[%s_%-]+","")
	return s
end

local function isSheepName(name)
	local n = normalize(name)
	return n == "oveja" or n == "ovejaderosario" or n:find("oveja", 1, true) ~= nil
end

local function canonicalPetName(name)
	local n = normalize(name)
	local map = {
		oveja = "Oveja",
		ovejaderosario = "Oveja",
		huron = "Huron",
		pezdorado = "Pez dorado",
		hamster = "Hamster",
		perico = "Perico",
		tortuga = "Tortuga",
		perro = "Perro",
		gato = "Gato",
		conejo = "Conejo",
	}
	if map[n] then return map[n] end
	for alias, canonical in pairs(map) do
		if n:find(alias, 1, true) then
			return canonical
		end
	end
	return tostring(name or "")
end

local function getActivePet(player)
	for _, object in ipairs(Workspace:GetDescendants()) do
		if object:IsA("Model")
			and object:GetAttribute("Owner") == player.UserId
			and object:GetAttribute("PetType") ~= nil then

			local petType = tostring(object:GetAttribute("PetType") or "")
			if petType ~= "" and petType ~= "Huevo Mascota" then
				return object
			end
		end
	end
	return nil
end

local function normalizeTier(tier)
	tier = tostring(tier or "Base")
	if tier == "" then tier = "Base" end
	return tier
end

local function petNamesMatch(a, b)
	return normalize(a) == normalize(b) or (isSheepName(a) and isSheepName(b))
end

local function findPetValue(player, petName, requestedTier)
	local container = player:FindFirstChild("TradePetsInventory")
	if not container then return nil end
	local wantedTier = requestedTier ~= nil and normalizeTier(requestedTier) or nil

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("IntValue") or child:IsA("NumberValue") then
			local storedName = tostring(child:GetAttribute("ItemName") or child.Name)
			local storedTier = normalizeTier(child:GetAttribute("UpgradeTier"))
			if petNamesMatch(storedName, petName) and (wantedTier == nil or storedTier == wantedTier) then
				return child
			end
		end
	end
	return nil
end

local function getTier(player, pet)
	local petName = tostring(pet:GetAttribute("PetType") or pet.Name)
	local tier = pet:GetAttribute("UpgradeTier")

	if type(tier) ~= "string" or tier == "" then
		local selectedName = tostring(player:GetAttribute("SelectedBackpackPet") or "")
		local selectedTier = player:GetAttribute("SelectedBackpackPetTier")
		if selectedName ~= "" and petNamesMatch(selectedName, petName) and type(selectedTier) == "string" and selectedTier ~= "" then
			tier = selectedTier
		end
	end

	if type(tier) ~= "string" or tier == "" then
		tier = "Base"
	end
	tier = normalizeTier(tier)

	local value = findPetValue(player, petName, tier)
	if not value then
		-- Compatibilidad con datos viejos mientras termina la migración.
		value = findPetValue(player, petName)
		if value then
			tier = normalizeTier(value:GetAttribute("UpgradeTier"))
		end
	end

	pet:SetAttribute("UpgradeTier", tier)
	player:SetAttribute("SelectedBackpackPet", canonicalPetName(petName))
	player:SetAttribute("SelectedBackpackPetTier", tier)
	return tier, value
end

local function itemName(instance)
	return tostring(instance:GetAttribute("ItemName") or instance.Name)
end

local function matchesAliases(name, aliases)
	local a = normalize(name)
	for _, alias in ipairs(aliases) do
		if a == normalize(alias) then return true end
	end
	return false
end

local function getFruitFolder()
	local itemFolder = ServerStorage:FindFirstChild("Item")
	if not itemFolder then return nil end
	return itemFolder:FindFirstChild("Frutas")
end

local function getToolImage(tool)
	if not tool then return "" end
	if tool:IsA("Tool") and type(tool.TextureId) == "string" and tool.TextureId ~= "" then
		return tool.TextureId
	end
	for _, attrName in ipairs({"Image", "Icon", "ImageId", "TextureId"}) do
		local value = tool:GetAttribute(attrName)
		if type(value) == "string" and value ~= "" then
			return value
		end
	end
	local handle = tool:FindFirstChild("Handle")
	if handle then
		for _, obj in ipairs(handle:GetDescendants()) do
			if obj:IsA("Decal") or obj:IsA("Texture") then
				if obj.Texture and obj.Texture ~= "" then
					return obj.Texture
				end
			end
		end
	end
	return ""
end

local function findFruitTemplate(ingredient)
	local fruitFolder = getFruitFolder()
	if not fruitFolder then return nil end
	for _, child in ipairs(fruitFolder:GetChildren()) do
		if matchesAliases(child.Name, ingredient.aliases) then
			return child
		end
	end
	return nil
end

local function getIngredientImage(ingredient)
	return getToolImage(findFruitTemplate(ingredient))
end

local function getPlayerFoodTools(player)
	local list = {}
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character

	for _, container in ipairs({backpack, character}) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") then
					table.insert(list, child)
				end
			end
		end
	end
	return list
end

local function countIngredient(player, ingredient)
	local count = 0
	for _, tool in ipairs(getPlayerFoodTools(player)) do
		if matchesAliases(itemName(tool), ingredient.aliases) then
			count += 1
		end
	end
	return count
end

local function copyStackAttributes(source, target, nextTier)
	if not source or not target then return end
	for key, value in pairs(source:GetAttributes()) do
		if key ~= "TradeUID" and key ~= "UpgradeTier" and key ~= "ItemName" then
			pcall(function()
				target:SetAttribute(key, value)
			end)
		end
	end
	target:SetAttribute("ItemName", canonicalPetName(source:GetAttribute("ItemName") or source.Name))
	target:SetAttribute("UpgradeTier", normalizeTier(nextTier))
end

local function addTierAmount(player, petName, tier, amount, copyFrom)
	local container = player:FindFirstChild("TradePetsInventory")
	if not container then return nil end
	petName = canonicalPetName(petName)
	tier = normalizeTier(tier)
	local value = findPetValue(player, petName, tier)
	if not value then
		value = Instance.new("IntValue")
		value.Name = petName .. "__" .. tier:gsub("%s+", "_")
		value.Value = 0
		value:SetAttribute("ItemName", petName)
		value:SetAttribute("UpgradeTier", tier)
		value.Parent = container
		if copyFrom then
			copyStackAttributes(copyFrom, value, tier)
		end
	end
	value.Value += amount
	return value
end

local function removeTierAmount(player, petName, tier, amount)
	local value = findPetValue(player, petName, tier)
	if not value or value.Value < amount then
		return false
	end
	value.Value -= amount
	if value.Value <= 0 then
		value:Destroy()
	end
	return true
end

local function buildRequirementState(player, petName, tier)
	local petRecipes = RECIPES[canonicalPetName(petName)] or {}
	local recipe = petRecipes[tier] or {}
	local result = {}
	local all = true

	if tier ~= "Base" then
		local baseValue = findPetValue(player, petName, "Base")
		local baseOwned = baseValue and math.max(0, math.floor(tonumber(baseValue.Value) or 0)) or 0
		table.insert(result, {
			kind = "Pet",
			name = canonicalPetName(petName) .. " sin pañuelo",
			petName = canonicalPetName(petName),
			tier = "Base",
			owned = baseOwned,
			needed = 1,
			enough = baseOwned >= 1,
		})
		if baseOwned < 1 then all = false end
	end

	for _, ingredient in ipairs(recipe) do
		local owned = countIngredient(player, ingredient)
		local need = ingredient.amount or 1
		table.insert(result, {
			kind = "Fruit",
			name = ingredient.display,
			owned = owned,
			needed = need,
			enough = owned >= need,
			image = getIngredientImage(ingredient),
		})
		if owned < need then all = false end
	end

	return result, all
end

local function consumeIngredients(player, petName, tier)
	local petRecipes = RECIPES[canonicalPetName(petName)] or {}
	local recipe = petRecipes[tier] or {}
	local tools = getPlayerFoodTools(player)

	if tier ~= "Base" then
		local baseValue = findPetValue(player, petName, "Base")
		if not baseValue or baseValue.Value < 1 then
			return false, "Necesitas otro " .. canonicalPetName(petName) .. " sin pañuelo."
		end
	end

	for _, ingredient in ipairs(recipe) do
		if countIngredient(player, ingredient) < (ingredient.amount or 1) then
			return false, "Te faltan materiales."
		end
	end

	for _, ingredient in ipairs(recipe) do
		local remaining = ingredient.amount or 1
		for _, tool in ipairs(tools) do
			if remaining <= 0 then break end
			if tool.Parent and matchesAliases(itemName(tool), ingredient.aliases) then
				tool:Destroy()
				remaining -= 1
			end
		end
	end

	if tier ~= "Base" then
		if not removeTierAmount(player, petName, "Base", 1) then
			return false, "No se pudo consumir la mascota base adicional."
		end
	end

	return true
end

--==============================================================
-- MODELOS
-- La búsqueda y creación de la mascota activa ahora pertenece
-- exclusivamente a PetSpawnService.
--==============================================================

local function targetModelExists(petName, tier)
	return PetSpawnService.FindPetTemplate(
		canonicalPetName(petName),
		tier
	) ~= nil
end

local function getUpgradeData(player)
	local pet = getActivePet(player)
	if not pet then
		return {ok = false, message = "Saca una mascota primero."}
	end

	local petName = tostring(pet:GetAttribute("PetType") or pet.Name)

	local tier = getTier(player, pet)
	local nextTier = UPGRADE_ORDER[tier]

	local petRecipes = RECIPES[canonicalPetName(petName)]
	if not petRecipes or (nextTier and not petRecipes[tier]) then
		return {
			ok = false,
			petName = petName,
			message = "Frank todavía no tiene una receta configurada para esta mascota.",
		}
	end

	if not nextTier then
		return {
			ok = true,
			maxLevel = true,
			petName = petName,
			currentTier = tier,
			currentDisplay = DISPLAY[tier],
			currentColor = COLOR_NAME[tier],
			requirements = {},
			message = "Tu Oveja ya es Legendaria.",
		}
	end

	local requirements, canCraft = buildRequirementState(player, petName, tier)

	return {
		ok = true,
		maxLevel = false,
		petName = petName,
		currentTier = tier,
		currentDisplay = DISPLAY[tier],
		currentColor = COLOR_NAME[tier],
		nextTier = nextTier,
		nextDisplay = DISPLAY[nextTier],
		nextColor = COLOR_NAME[nextTier],
		requirements = requirements,
		canCraft = canCraft,
	}
end

GetUpgradeInfo.OnServerInvoke = function(player)
	return getUpgradeData(player)
end

UpgradePet.OnServerInvoke = function(player)
	local pet = getActivePet(player)
	if not pet then
		return {ok = false, message = "No tienes una mascota afuera."}
	end

	local petName = tostring(pet:GetAttribute("PetType") or pet.Name)
	local tier, petValue = getTier(player, pet)
	local nextTier = UPGRADE_ORDER[tier]

	local petRecipes = RECIPES[canonicalPetName(petName)]
	if not petRecipes or (nextTier and not petRecipes[tier]) then
		return {
			ok = false,
			message = "Frank todavía no tiene una receta configurada para esta mascota.",
		}
	end
	if not nextTier then
		return {ok = false, message = "Tu Oveja ya es Legendaria."}
	end

	local requirements, canCraft = buildRequirementState(player, petName, tier)
	if not canCraft then
		return {
			ok = false,
			message = "Te faltan materiales para esta mejora.",
			requirements = requirements,
		}
	end

	-- Primero comprobar que existe el modelo destino ANTES de consumir.
	if not targetModelExists(petName, nextTier) then
		return {
			ok = false,
			message = "Falta el modelo de " .. petName .. " en la carpeta: " .. tostring(VARIANT_FOLDERS[nextTier]),
		}
	end

	local consumed, consumeError = consumeIngredients(player, petName, tier)
	if not consumed then
		return {ok = false, message = consumeError or "No se pudieron consumir los materiales."}
	end

	-- Transformar SOLO una unidad del tier actual al siguiente tier.
	-- Ejemplo: Perro Base x2 + Perro Gris x1 -> al mejorar el gris:
	-- consume 1 Base y convierte 1 Gris en 1 Verde.
	local currentStack = findPetValue(player, petName, tier)
	if not currentStack or currentStack.Value < 1 then
		return {ok = false, message = "No se encontró la mascota del tier actual en tu inventario."}
	end

	local sourceStack = currentStack
	currentStack.Value -= 1
	if currentStack.Value <= 0 then
		currentStack.Parent = nil
	end

	local upgradedStack = addTierAmount(player, petName, nextTier, 1, sourceStack)
	if not upgradedStack then
		-- rollback mínimo si no se pudo crear el nuevo stack
		if sourceStack.Parent == nil then sourceStack.Parent = player:FindFirstChild("TradePetsInventory") end
		sourceStack.Value += 1
		return {ok = false, message = "No se pudo crear el stack de la mascota mejorada."}
	end

	if sourceStack.Parent == nil then
		sourceStack:Destroy()
	end

	player:SetAttribute("SelectedBackpackPet", canonicalPetName(petName))
	player:SetAttribute("SelectedBackpackPetTier", nextTier)

	local newPet = PetSpawnService.SpawnPet(
		player,
		canonicalPetName(petName),
		nextTier
	)

	if not newPet then
		return {
			ok = false,
			message = "La mejora se guardó, pero no se pudo reconstruir la mascota activa."
		}
	end

	awardGameActionXP(player, "PetUpgrade", 40)

	return {
		ok = true,
		message = "¡Frank mejoró tu " .. petName .. " a " .. DISPLAY[nextTier] .. " (" .. COLOR_NAME[nextTier] .. ")!",
		newTier = nextTier,
		state = getUpgradeData(player),
	}
end

local function configureFrankPrompt(prompt)
	prompt.Name = "PetUpgradePrompt"
	prompt.ActionText = "Hablar"
	prompt.ObjectText = "Frank"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
	prompt.HoldDuration = 0.45
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Enabled = true
end

local function connectFrank()
	local granja = Workspace:WaitForChild("Granja")
	local frank = granja:WaitForChild("Frank")
	local root = frank:WaitForChild("HumanoidRootPart")

	-- Quita el nombre "Frank" que Roblox muestra encima de la cabeza.
	local humanoid = frank:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.NameDisplayDistance = 0
		humanoid.HealthDisplayDistance = 0
	end

	local prompt = root:FindFirstChild("PetUpgradePrompt")

	if not prompt then
		local old = root:FindFirstChild("BrizabelleEggPrompt")
		if old and old:IsA("ProximityPrompt") then
			prompt = old
		else
			prompt = Instance.new("ProximityPrompt")
			prompt.Parent = root
		end
	end

	configureFrankPrompt(prompt)

	prompt.Triggered:Connect(function(player)
		OpenUpgradeUI:FireClient(player)
	end)
end

connectFrank()