local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local PetConfigs = require(ReplicatedStorage:WaitForChild("PetConfigs"))

local EGG_PRICE = 750
local EGG_NAME = "Huevo Mascota"
local DIRTY_EGG_TEMPLATE_NAME = "Huevo sucio"
local TRADE_UID_ATTR = "TradeUID"
local SLEEP_LOCK_ATTR = "BrizabellePetSleeping"
local SLEEP_RESTORE_PET_ATTR = "BrizabelleRestorePetAfterSleep"
local SLEEP_RESTORE_UNTIL_ATTR = "BrizabelleRestorePetUntil"
local WALK_AWARD_DISTANCE = 10
local DIRT_WALK_AWARDS = 12
local FOOD_WALK_AWARDS = 6
local ENERGY_LOSS_PER_WALK_AWARD = 8
local CLEAN_PROGRESS = 5
local WALK_PROGRESS = 1
local SLEEP_PROGRESS = 10
local FEED_PROGRESS = 5
local PET_PROGRESS = 5
local SLEEP_DURATION = 10
local PET_SLEEP_HOLD_TIMES = {
	["Oveja de rosario"] = 0.37,
	["Oveja"] = 0.37,
	["Huron"] = 0.4,
	["Hurón"] = 0.4,
	["Pez dorado"] = 1.3,
	["PezDorado"] = 1.3,
	["Hamster"] = 3.3,
	["Hámster"] = 3.3,
	["Perico"] = 36,
	["Tortuga"] = 1.1,
	["Perro"] = 1.1,
	["Gato"] = 0.63,
	["Conejo"] = 0.47,
}
local CLEAN_XP = 10
local SLEEP_XP = 20
local FEED_XP = 8
local INSTANT_HATCH_PRICE_ROBUX = 750

--============================================================
-- OSWALD - DEVELOPER PRODUCTS
-- IMPORTANTE: ProcessReceipt se mantiene CENTRALIZADO aqui.
--============================================================

local OSWALD_DOLLAR_PRODUCTS = {
	[3709750798] = 750,
	[3709750847] = 2500,
	[3709750869] = 7500,
	[3709750906] = 55000,
}

local DOLLAR_STORE_NAME = "PlayerDollarsV1"
local dollarStore = DataStoreService:GetDataStore(DOLLAR_STORE_NAME)
local PET_STORE_NAME = "PlayerPetsInventoryV1"
local petStore
local petStoreOk, petStoreErr = pcall(function()
	petStore = DataStoreService:GetDataStore(PET_STORE_NAME)
end)
if not petStoreOk then
	warn("DataStore de mascotas no disponible: " .. tostring(petStoreErr))
end
local pendingPetSaves = {}
local petValueConnections = {}
local walkRuntime = {}
local sleepingEggs = {}
local sleepingBedOccupant = nil
local tiredNoticeRuntime = {}

--============================================================
-- V STARTUP ALERT FIX
--
-- Al cambiar de Place se vuelven a cargar necesidades guardadas.
-- Eso NO significa que la mascota/huevo acaba de tener esa necesidad.
-- Evitamos volver a anunciar estados viejos al iniciar cada mundo.
--============================================================
local NEED_NOTICE_STARTUP_GRACE = 12
local needNoticeReadyAt = {}

local function canSendNeedNotice(player)
	if not player or player.Parent ~= Players then
		return false
	end

	local readyAt = needNoticeReadyAt[player]
	if readyAt and os.clock() < readyAt then
		return false
	end

	return true
end

local sleepingPetOffsets = {
	["Hamster"] = { height = 0.45, forward = -0.05, yaw = -90, roll = 0, sleepHoldTime = 0.43 },
	["Hámster"] = { height = 0.45, forward = -0.05, yaw = -90, roll = 0, sleepHoldTime = 0.43 },
	["Perro"] = { height = 0.78, forward = -0.05, yaw = -90, roll = 0, sleepHoldTime = 0.43 },
	["Gato"] = { height = 1.05, forward = -0.05, yaw = -90, roll = 0, sleepHoldTime = 0.43 },
	["Perico"] = { height = 0.55, forward = -0.05, yaw = -90, roll = 0 },
	["Pajarillo"] = { height = 0.55, forward = -0.05, yaw = -90, roll = 0 },
}

local rarityOrder = {
	{ rarity = "Comun", label = "Comun", chance = 35, pets = { "Perro", "Gato" } },
	{ rarity = "Poco comun", label = "Poco comun", chance = 25, pets = { "Conejo", "Perico" } },
	{ rarity = "Raro", label = "Raro", chance = 20, pets = { "Tortuga", "Hamster" } },
	{ rarity = "Epico", label = "Epico", chance = 15, pets = { "Huron", "Pez dorado" } },
	{ rarity = "Legendario", label = "Legendario", chance = 5, pets = { "Oveja de rosario" } },
}

local rarityColors = {
	["Comun"] = "Gris",
	["Poco comun"] = "Verde",
	["Raro"] = "Azul",
	["Epico"] = "Morado",
	["Legendario"] = "Dorado",
}

local aliases = {
	["Pajarillo"] = "Perico",
	["Pez dorado"] = "PezDorado",
	["Oveja de rosario"] = "Oveja",
}
local storedNameAliases = {
	["HuevoBrizabelle"] = EGG_NAME,
	["Pajarillo"] = "Perico",
	["PezDorado"] = "Pez dorado",
}

local function normalizeStoredPetName(petName)
	petName = tostring(petName or "")
	return storedNameAliases[petName] or petName
end

local function getPetSleepHoldTime(petName)
	petName = normalizeStoredPetName(petName)
	return PET_SLEEP_HOLD_TIMES[petName] or PET_SLEEP_HOLD_TIMES[aliases[petName]]
end

local folder = ReplicatedStorage:FindFirstChild("BrizabelleEggSystem") or Instance.new("Folder")
folder.Name = "BrizabelleEggSystem"
folder.Parent = ReplicatedStorage

local function remoteEvent(name)
	local remote = folder:FindFirstChild(name) or Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local function remoteFunction(name)
	local remote = folder:FindFirstChild(name) or Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local BuyEgg = remoteFunction("BuyEgg")
local HatchEgg = remoteFunction("HatchEgg")
local GetState = remoteFunction("GetState")
local CareEgg = remoteFunction("CareEgg")
local SelectPet = remoteEvent("SelectPet")
local RequestInstantHatch = remoteFunction("RequestInstantHatch")
local ConfirmInstantHatch = remoteFunction("ConfirmInstantHatch")
local EggNotify = remoteEvent("EggNotify")

local oswaldShopFolder =
	ReplicatedStorage:FindFirstChild("OswaldRobuxShopSystem")
	or Instance.new("Folder")

oswaldShopFolder.Name = "OswaldRobuxShopSystem"
oswaldShopFolder.Parent = ReplicatedStorage

local OswaldPurchaseResult =
	oswaldShopFolder:FindFirstChild("PurchaseResult")

if OswaldPurchaseResult
	and not OswaldPurchaseResult:IsA("RemoteEvent")
then
	OswaldPurchaseResult:Destroy()
	OswaldPurchaseResult = nil
end

if not OswaldPurchaseResult then
	OswaldPurchaseResult = Instance.new("RemoteEvent")
	OswaldPurchaseResult.Name = "PurchaseResult"
	OswaldPurchaseResult.Parent = oswaldShopFolder
end
local awardXPEvent = ReplicatedStorage:FindFirstChild("AwardPlayerXP")
if awardXPEvent and not awardXPEvent:IsA("BindableEvent") then
	awardXPEvent = nil
end

folder:SetAttribute("InstantHatchPriceRobux", INSTANT_HATCH_PRICE_ROBUX)
if typeof(folder:GetAttribute("InstantHatchProductId")) ~= "number" then
	folder:SetAttribute("InstantHatchProductId", 0)
end
local pendingInstantHatch = {}

local function cloneAlias(folderName, aliasName, sourceName)
	local petFolder = ReplicatedStorage:FindFirstChild(folderName)
	if not petFolder or petFolder:FindFirstChild(aliasName) then return end
	local sourceModel = petFolder:FindFirstChild(sourceName)
	if sourceModel then
		local clone = sourceModel:Clone()
		clone.Name = aliasName
		clone:SetAttribute("DisplayName", aliasName)
		clone.Parent = petFolder
	end
end

for aliasName, sourceName in pairs(aliases) do
	cloneAlias("Mascotas", aliasName, sourceName)
	cloneAlias("MascotasView", aliasName, sourceName)
end

local petConfigs = ReplicatedStorage:FindFirstChild("PetConfigs")
if petConfigs and petConfigs:IsA("ModuleScript") then
	-- Las mascotas con alias comparten modelo; si el script de configuracion ya fue actualizado, esto no hace nada.
end

local function ensureUid(instance)
	local uid = instance:GetAttribute(TRADE_UID_ATTR)
	if typeof(uid) ~= "string" or uid == "" then
		uid = HttpService:GenerateGUID(false)
		instance:SetAttribute(TRADE_UID_ATTR, uid)
	end
	return uid
end

local function getMoneyValue(player)
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
	for _, container in ipairs(possibleContainers) do
		if container then
			for _, valueName in ipairs(possibleNames) do
				local value = container:FindFirstChild(valueName)
				if value and (value:IsA("IntValue") or value:IsA("NumberValue")) then
					return value
				end
			end
		end
	end
	return nil
end

local function awardPlayerXP(player, amount)
	local event = awardXPEvent or ReplicatedStorage:FindFirstChild("AwardPlayerXP")
	if event and event:IsA("BindableEvent") then
		awardXPEvent = event
		event:Fire(player, amount)
	end
end

local function getPetContainer(player)
	local container = player:FindFirstChild("TradePetsInventory")
	if not container then
		container = Instance.new("Folder")
		container.Name = "TradePetsInventory"
		container.Parent = player
	end
	return container
end

local function getItemValue(player, itemName)
	local container = getPetContainer(player)
	for _, child in ipairs(container:GetChildren()) do
		local name = normalizeStoredPetName(child:GetAttribute("ItemName") or child.Name)
		if name == normalizeStoredPetName(itemName) and (child:IsA("IntValue") or child:IsA("NumberValue")) then
			return child
		end
	end
	return nil
end

local function canStoreAttribute(value)
	local valueType = typeof(value)
	return valueType == "string" or valueType == "number" or valueType == "boolean"
end

local function serializePetInventory(player)
	local container = getPetContainer(player)
	local items = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("IntValue") or child:IsA("NumberValue") then
			local amount = math.max(0, math.floor(tonumber(child.Value) or 0))
			if amount > 0 then
				local attrs = {}
				for key, attrValue in pairs(child:GetAttributes()) do
					if canStoreAttribute(attrValue) then
						attrs[key] = attrValue
					end
				end
				local itemName = normalizeStoredPetName(attrs.ItemName or child:GetAttribute("ItemName") or child.Name)
				attrs.ItemName = itemName
				table.insert(items, {
					name = child.Name,
					itemName = itemName,
					amount = amount,
					attributes = attrs,
				})
			end
		end
	end
	return {
		version = 1,
		items = items,
		selectedPet = player:GetAttribute("SelectedBackpackPet"),
		eggProgress = player:GetAttribute("BrizabelleEggProgress"),
	}
end

local function savePetInventoryNow(player)
	if not player then return end
	if not petStore then return end
	local data = serializePetInventory(player)
	local ok, err = pcall(function()
		petStore:SetAsync(tostring(player.UserId), data)
	end)
	if not ok then
		warn("No se pudo guardar mascotas de " .. player.Name .. ": " .. tostring(err))
	end
end

local function queuePetSave(player)
	if not player or not player.Parent then return end
	if pendingPetSaves[player] then return end
	pendingPetSaves[player] = true
	task.delay(8, function()
		pendingPetSaves[player] = nil
		if player.Parent then
			savePetInventoryNow(player)
		end
	end)
end

local ensureCareDefaults

local function trackPetValue(player, value)
	if not value or petValueConnections[value] then return end
	petValueConnections[value] = {
		value.Changed:Connect(function()
			queuePetSave(player)
		end),
		value.AttributeChanged:Connect(function()
			queuePetSave(player)
		end),
		value.Destroying:Connect(function()
			local connections = petValueConnections[value]
			petValueConnections[value] = nil
			if connections then
				for _, connection in ipairs(connections) do
					connection:Disconnect()
				end
			end
			queuePetSave(player)
		end),
	}
end

local function clearPetContainer(player)
	local container = getPetContainer(player)
	for _, child in ipairs(container:GetChildren()) do
		child:Destroy()
	end
end

local function loadPetInventory(player)
	if not petStore then return end
	local ok, data = pcall(function()
		return petStore:GetAsync(tostring(player.UserId))
	end)
	if not ok then
		warn("No se pudo cargar mascotas de " .. player.Name .. ": " .. tostring(data))
		return
	end
	if typeof(data) ~= "table" or typeof(data.items) ~= "table" then
		return
	end
	clearPetContainer(player)
	local container = getPetContainer(player)
	for _, item in ipairs(data.items) do
		if typeof(item) == "table" then
			local amount = math.max(0, math.floor(tonumber(item.amount) or 0))
			local itemName = normalizeStoredPetName(item.itemName or item.name or "")
			if amount > 0 and itemName ~= "" then
				local value = Instance.new("IntValue")
				value.Name = itemName
				value.Value = amount
				value:SetAttribute("ItemName", itemName)
				if typeof(item.attributes) == "table" then
					for key, attrValue in pairs(item.attributes) do
						if canStoreAttribute(attrValue) then
							value:SetAttribute(key, attrValue)
						end
					end
				end
				ensureCareDefaults(value, itemName == EGG_NAME)
				if itemName == EGG_NAME then
					value:SetAttribute("Resting", false)
				end
				ensureUid(value)
				value.Parent = container
				trackPetValue(player, value)
			end
		end
	end
	if typeof(data.selectedPet) == "string" and data.selectedPet ~= "" then
		player:SetAttribute("SelectedBackpackPet", normalizeStoredPetName(data.selectedPet))
	end
	if typeof(data.eggProgress) == "number" then
		player:SetAttribute("BrizabelleEggProgress", math.clamp(data.eggProgress, 0, 100))
	end
end


local function countItem(player, itemName)
	local value = getItemValue(player, itemName)
	return value and math.max(0, math.floor(value.Value)) or 0
end

local function getFoodToolsFolder()
	local itemFolder = ServerStorage:FindFirstChild("Item")
	return itemFolder and itemFolder:FindFirstChild("Frutas") or nil
end

local function isFoodTool(tool)
	if not tool or not tool:IsA("Tool") then return false end
	local foodFolder = getFoodToolsFolder()
	if not foodFolder then return false end
	local foodName = tostring(tool:GetAttribute("ItemName") or tool.Name):gsub("^%s+", ""):gsub("%s+$", "")
	for _, foodTool in ipairs(foodFolder:GetChildren()) do
		if foodTool:IsA("Tool") then
			local storedName = tostring(foodTool:GetAttribute("ItemName") or foodTool.Name):gsub("^%s+", ""):gsub("%s+$", "")
			if foodName == storedName then
				return true
			end
		end
	end
	return false
end

local function getEquippedFoodTool(player)
	local character = player.Character
	if not character then return nil end
	for _, child in ipairs(character:GetChildren()) do
		if isFoodTool(child) then
			return child
		end
	end
	return nil
end

local function addPetAmount(player, petName, amount, attrs)
	local container = getPetContainer(player)
	local value = getItemValue(player, petName)
	if not value then
		value = Instance.new("IntValue")
		value.Name = petName
		value.Value = 0
		value:SetAttribute("ItemName", petName)
		ensureUid(value)
		value.Parent = container
		trackPetValue(player, value)
	end
	value.Value += amount
	for key, attrValue in pairs(attrs or {}) do
		value:SetAttribute(key, attrValue)
	end
	queuePetSave(player)
	return value
end

local function removePetAmount(player, petName, amount)
	local value = getItemValue(player, petName)
	if value and value.Value >= amount then
		value.Value -= amount
		if value.Value <= 0 then value:Destroy() end
		queuePetSave(player)
		return true
	end
	return false
end

local function getEggValue(player)
	return getItemValue(player, EGG_NAME)
end

ensureCareDefaults = function(value, isEgg)
	if not value then return end
	if typeof(value:GetAttribute("Progress")) ~= "number" then
		value:SetAttribute("Progress", 0)
	end
	if typeof(value:GetAttribute("Energy")) ~= "number" then
		value:SetAttribute("Energy", 100)
	end
	if typeof(value:GetAttribute("Tired")) ~= "boolean" then
		value:SetAttribute("Tired", false)
	end
	if typeof(value:GetAttribute("Resting")) ~= "boolean" then
		value:SetAttribute("Resting", false)
	end
	if not isEgg and typeof(value:GetAttribute("Hungry")) ~= "boolean" then
		value:SetAttribute("Hungry", false)
	end
end

local function getProgress(player)
	local egg = getEggValue(player)
	if not egg then return 0 end
	return math.clamp(tonumber(egg:GetAttribute("Progress")) or 0, 0, 100)
end

local function setProgress(player, progress)
	local egg = getEggValue(player)
	if not egg then return 0 end
	progress = math.clamp(math.floor((tonumber(progress) or 0) + 0.5), 0, 100)
	egg:SetAttribute("Progress", progress)
	player:SetAttribute("BrizabelleEggProgress", progress)
	EggNotify:FireClient(player, "Progress", getState(player))
	return progress
end

local function getPetProgress(petValue)
	if not petValue then return 0 end
	return math.clamp(tonumber(petValue:GetAttribute("Progress")) or 0, 0, 100)
end

local function addSelectedPetProgress(player, petValue, amount, reason)
	if not petValue then return getState(player) end
	local before = getPetProgress(petValue)
	local after = math.clamp(math.floor(before + amount + 0.5), 0, 100)
	petValue:SetAttribute("Progress", after)
	queuePetSave(player)
	if after > before then
		EggNotify:FireClient(player, "PetCare", { reason = reason, progress = after, petName = petValue:GetAttribute("ItemName") or petValue.Name, state = getState(player) })
	end
	return getState(player)
end

local function eggNeedsCare(egg)
	if not egg then return false end
	return egg:GetAttribute("Dirty") == true or egg:GetAttribute("Tired") == true or egg:GetAttribute("Resting") == true
end

function addProgress(player, amount, reason, ignoreNeeds)
	local egg = getEggValue(player)
	if not egg then return getState(player) end
	if not ignoreNeeds and eggNeedsCare(egg) then
		return getState(player)
	end
	local before = getProgress(player)
	local after = setProgress(player, before + amount)
	if after >= 100 and before < 100 then
		EggNotify:FireClient(player, "Ready", getState(player))
	elseif after > before then
		EggNotify:FireClient(player, "Care", { reason = reason, progress = after, state = getState(player) })
	end
	return getState(player)
end

function getState(player)
	local money = getMoneyValue(player)
	local egg = getEggValue(player)
	local progress = getProgress(player)
	local eggCount = countItem(player, EGG_NAME)
	local eggs = {}
	for index = 1, eggCount do
		table.insert(eggs, {
			id = tostring(index),
			name = EGG_NAME,
			displayName = "Huevo mascota",
			progress = progress,
			dirty = egg and egg:GetAttribute("Dirty") == true or false,
			tired = egg and egg:GetAttribute("Tired") == true or false,
			energy = egg and math.clamp(tonumber(egg:GetAttribute("Energy")) or 100, 0, 100) or 100,
			resting = egg and egg:GetAttribute("Resting") == true or false,
		})
	end
	return {
		price = EGG_PRICE,
		money = money and money.Value or 0,
		eggName = EGG_NAME,
		eggDisplayName = "Huevo mascota",
		eggCount = eggCount,
		eggs = eggs,
		progress = progress,
		dirty = egg and egg:GetAttribute("Dirty") == true or false,
		tired = egg and egg:GetAttribute("Tired") == true or false,
		energy = egg and math.clamp(tonumber(egg:GetAttribute("Energy")) or 100, 0, 100) or 100,
		resting = egg and egg:GetAttribute("Resting") == true or false,
		needsCare = egg and eggNeedsCare(egg) or false,
		ready = eggCount > 0 and progress >= 100,
		pool = rarityOrder,
	}
end

local function choosePet()
	local roll = math.random(1, 100)
	local total = 0
	local selected = rarityOrder[#rarityOrder]
	for _, entry in ipairs(rarityOrder) do
		total += entry.chance
		if roll <= total then
			selected = entry
			break
		end
	end
	local petName = selected.pets[math.random(1, #selected.pets)]
	return petName, selected.rarity, roll
end

local function grantHatchedPet(player, source)
	if not removePetAmount(player, EGG_NAME, 1) then
		return nil, "No se pudo usar el huevo."
	end
	local petName, rarity, roll = choosePet()
	addPetAmount(player, petName, 1, {
		Rarity = rarity,
		RarityColor = rarityColors[rarity] or "Gris",
		GrowthStage = "Bebe",
		Progress = 0,
		Energy = 100,
		Tired = false,
		Resting = false,
		Hungry = false,
		GachaSource = source or "Huevo Brizabelle",
		Roll = roll,
	})
	player:SetAttribute("SelectedBackpackPet", petName)
	player:SetAttribute("BrizabelleEggProgress", 0)
	local result = { petName = petName, rarity = rarity, rarityColor = rarityColors[rarity] or "Gris" }
	EggNotify:FireClient(player, "Hatched", result)
	return result
end

local function findOwnedPetModel(player, petName)
	petName = normalizeStoredPetName(petName)
	for _, object in ipairs(Workspace:GetChildren()) do
		if object:IsA("Model") and object:GetAttribute("Owner") == player.UserId then
			local modelPetType = normalizeStoredPetName(object:GetAttribute("PetType"))
			if petName == "" or modelPetType == petName then
				return object
			end
		end
	end
	return nil
end

local function findOwnedEggModel(player)
	return findOwnedPetModel(player, EGG_NAME)
end

local function getActiveOwnedPetName(player)
	local selectedPetName = normalizeStoredPetName(player:GetAttribute("SelectedBackpackPet") or "")
	if selectedPetName ~= "" and selectedPetName ~= EGG_NAME and getItemValue(player, selectedPetName) then
		return selectedPetName
	end
	for _, object in ipairs(Workspace:GetChildren()) do
		if object:IsA("Model") and object:GetAttribute("Owner") == player.UserId then
			local modelPetType = normalizeStoredPetName(object:GetAttribute("PetType"))
			if modelPetType ~= "" and modelPetType ~= EGG_NAME and getItemValue(player, modelPetType) then
				return modelPetType
			end
		end
	end
	return ""
end

local function removeOwnedPetModels(player, petName)
	petName = petName and normalizeStoredPetName(petName) or ""
	for _, object in ipairs(Workspace:GetChildren()) do
		if object:IsA("Model") and object:GetAttribute("Owner") == player.UserId and object:GetAttribute("PetType") ~= nil then
			local modelPetType = normalizeStoredPetName(object:GetAttribute("PetType"))
			if petName == "" or modelPetType == petName then
				object:Destroy()
			end
		end
	end
end

local function removeOwnedEggModels(player)
	removeOwnedPetModels(player, EGG_NAME)
end

local function getDirtyEggVisualPart()
	local template = Workspace:FindFirstChild(DIRTY_EGG_TEMPLATE_NAME)
	if not template or not template:IsA("Model") then return nil end
	return template:FindFirstChild("Huevo Sucio", true) or template:FindFirstChildWhichIsA("BasePart", true)
end

local function getCleanEggVisualPart()
	local petsFolder = ReplicatedStorage:FindFirstChild("Mascotas")
	local template = petsFolder and petsFolder:FindFirstChild(EGG_NAME)
	return template and template:FindFirstChild("Torso", true) or nil
end

local function replaceEggTorso(model, visualPart)
	local oldTorso = model:FindFirstChild("Torso", true)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not visualPart or not oldTorso or not oldTorso:IsA("BasePart") or not root then return false end
	local newTorso = visualPart:Clone()
	newTorso.Name = "Torso"
	newTorso.CFrame = oldTorso.CFrame
	newTorso.Anchored = oldTorso.Anchored
	newTorso.CanCollide = oldTorso.CanCollide
	newTorso.CanTouch = oldTorso.CanTouch
	newTorso.CanQuery = oldTorso.CanQuery
	newTorso.Massless = oldTorso.Massless
	newTorso.CastShadow = oldTorso.CastShadow
	newTorso.Parent = oldTorso.Parent
	for _, joint in ipairs(root:GetChildren()) do
		if joint:IsA("Motor6D") and joint.Part1 == oldTorso then
			joint.Part1 = newTorso
		end
	end
	oldTorso:Destroy()
	return true
end

local function applyEggAppearance(model, useDirtyEgg)
	local visualPart = useDirtyEgg and getDirtyEggVisualPart() or getCleanEggVisualPart()
	if replaceEggTorso(model, visualPart) then
		model:SetAttribute("DirtyEggVisual", useDirtyEgg == true)
		model:SetAttribute("EggAppearanceVersion", (tonumber(model:GetAttribute("EggAppearanceVersion")) or 0) + 1)
	end
end

local function applyDirtyEggAppearance(model)
	applyEggAppearance(model, true)
end

local function spawnOwnedPetModel(player, petName, smoothTransition)
	petName = normalizeStoredPetName(petName)
	if player:GetAttribute(SLEEP_LOCK_ATTR) == true and petName == EGG_NAME then
		return nil
	end
	local previousModel = smoothTransition and findOwnedPetModel(player, petName) or nil
	local eggValue = petName == EGG_NAME and getEggValue(player) or nil
	local useDirtyEgg = eggValue and eggValue:GetAttribute("Dirty") == true
	if previousModel and petName == EGG_NAME then
		applyEggAppearance(previousModel, useDirtyEgg)
		return previousModel
	end
	if not smoothTransition then
		removeOwnedPetModels(player, petName)
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local petsFolder = ReplicatedStorage:FindFirstChild("Mascotas")
	local source = petsFolder and petsFolder:FindFirstChild(petName)
	if not source and aliases[petName] and petsFolder then
		source = petsFolder:FindFirstChild(aliases[petName])
	end
	if not root or not source then return nil end
	local model = source:Clone()
	if useDirtyEgg then
		applyDirtyEggAppearance(model)
	end
	local modelRoot = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not modelRoot then
		model:Destroy()
		return nil
	end
	model.PrimaryPart = modelRoot
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = part == modelRoot
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
			part.CastShadow = false
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		pcall(function()
			humanoid.EvaluateStateMachine = false
		end)
		humanoid.PlatformStand = true
		humanoid.AutoRotate = false
	end
	model.Name = petName
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("PetType", petName)
	model:SetAttribute("IsMoving", false)
	model:SetAttribute("PetRenderSource", true)
	model.Parent = Workspace
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	local spawnCFrame = (previousModel and previousModel.Parent and previousModel:GetPivot()) or (root.CFrame * CFrame.new(0, 0, 4))
	model:PivotTo(spawnCFrame)
	if smoothTransition then
		local originalTransparency = {}
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				originalTransparency[part] = part.Transparency
				part.Transparency = 1
			end
		end
		for part, transparency in pairs(originalTransparency) do
			if part and part.Parent then
				TweenService:Create(part, TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = transparency }):Play()
			end
		end
		if previousModel and previousModel.Parent then
			for _, part in ipairs(previousModel:GetDescendants()) do
				if part:IsA("BasePart") then
					TweenService:Create(part, TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
				end
			end
			task.delay(0.42, function()
				if previousModel and previousModel.Parent then previousModel:Destroy() end
			end)
		end
	end
	return model
end

local function spawnOwnedEggModel(player, smoothTransition)
	return spawnOwnedPetModel(player, EGG_NAME, smoothTransition)
end

local function configurePrompt(prompt, actionText, objectText)
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
	prompt.HoldDuration = 0.45
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
end

local function findPetBed()
	local bedNames = {
		"Cama para mascotas",
		"Cama para mascotas ",
		"Cama para mascota",
		"Cama para mascota ",
	}
	for _, bedName in ipairs(bedNames) do
		local directBed = Workspace:FindFirstChild(bedName)
		if directBed and directBed:IsA("BasePart") then
			return directBed
		end
	end
	local eggBedModel = Workspace:FindFirstChild("huevo y cama ") or Workspace:FindFirstChild("huevo y cama")
	for _, container in ipairs({ eggBedModel, Workspace:FindFirstChild("Prueba") }) do
		if container then
			for _, bedName in ipairs(bedNames) do
				local bed = container:FindFirstChild(bedName, true)
				if bed and bed:IsA("BasePart") then
					return bed
				end
			end
		end
	end
	return nil
end

local function removeOldBedPrompt(targetBed)
	for _, object in ipairs(Workspace:GetDescendants()) do
		if object:IsA("ProximityPrompt") and object.Name == "BrizabelleEggBedPrompt" and object.Parent ~= targetBed then
			object:Destroy()
		end
	end
end

local function ensureWorldPrompts()
	local brizRoot = Workspace:FindFirstChild("Granja")
		and Workspace.Granja:FindFirstChild("Brizabelle")
		and Workspace.Granja.Brizabelle:FindFirstChild("Brizabelle")
		and Workspace.Granja.Brizabelle.Brizabelle:FindFirstChild("HumanoidRootPart")
	if brizRoot then
		local prompt = brizRoot:FindFirstChild("BrizabelleEggPrompt") or Instance.new("ProximityPrompt")
		prompt.Name = "BrizabelleEggPrompt"
		configurePrompt(prompt, "Hablar", "Brizabelle")
		prompt.Parent = brizRoot
	end
	local bed = findPetBed()
	if bed and bed:IsA("BasePart") then
		removeOldBedPrompt(bed)
		local prompt = bed:FindFirstChild("BrizabelleEggBedPrompt") or Instance.new("ProximityPrompt")
		prompt.Name = "BrizabelleEggBedPrompt"
		configurePrompt(prompt, "Dormir", "Mascota")
		prompt.Parent = bed
	end
end

local function updateEggPrompt(player)
	local egg = getEggValue(player)
	if not egg then return end

	-- Si ya venía cansado desde otro mundo, NO repetimos la alerta.
	-- La alerta "Tired" se envía únicamente cuando Energy cruza a 0
	-- durante juego real.
	if egg:GetAttribute("Tired") == true then
		return getState(player)
	end

	local model = findOwnedEggModel(player)
	if not model then return end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") and descendant.Name == "BrizabelleEggCleanPrompt" then
			descendant:Destroy()
		end
	end
end

local function updateNeedPrompts(player)
	updateEggPrompt(player)
end

local function markDirtyIfNeeded(player, egg)
	if egg:GetAttribute("Dirty") == true then return end
	local walksSinceClean = math.max(0, math.floor(tonumber(egg:GetAttribute("WalkAwardsSinceClean")) or 0))
	if walksSinceClean >= DIRT_WALK_AWARDS then
		egg:SetAttribute("Dirty", true)
		spawnOwnedEggModel(player, true)

		if canSendNeedNotice(player) then
			EggNotify:FireClient(
				player,
				"Dirty",
				getState(player)
			)
		end
	end
end

local function drainEnergyForWalk(player, egg, chunks)
	local energy = math.clamp(tonumber(egg:GetAttribute("Energy")) or 100, 0, 100)
	energy = math.max(0, energy - ENERGY_LOSS_PER_WALK_AWARD * chunks)
	egg:SetAttribute("Energy", energy)
	if energy <= 0 and egg:GetAttribute("Tired") ~= true then
		egg:SetAttribute("Tired", true)

		if canSendNeedNotice(player) then
			EggNotify:FireClient(
				player,
				"Tired",
				getState(player)
			)
		end
	end
end

local function markHungryForWalk(player, careValue, chunks, petName)
	if not careValue or chunks <= 0 then return end
	local foodWalks = math.max(0, math.floor(tonumber(careValue:GetAttribute("FoodCareWalks")) or 0)) + chunks
	careValue:SetAttribute("FoodCareWalks", foodWalks)
	if foodWalks >= FOOD_WALK_AWARDS and careValue:GetAttribute("Hungry") ~= true then
		careValue:SetAttribute("Hungry", true)

		if canSendNeedNotice(player) then
			EggNotify:FireClient(
				player,
				"Hungry",
				{
					petName = petName,
					state = getState(player),
				}
			)
		end
	end
end

local function updateDirtyState(player)
	local egg = getEggValue(player)
	if not egg or getProgress(player) >= 100 then return end
	if not findOwnedEggModel(player) then
		walkRuntime[player] = nil
		return
	end
	markDirtyIfNeeded(player, egg)
	updateNeedPrompts(player)
end

local function awardSelectedPetWalkCare(player, petName)
	local petValue = getItemValue(player, petName)
	if not petValue or petValue:GetAttribute("Resting") == true then return getState(player) end
	ensureCareDefaults(petValue, false)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return getState(player) end
	local current = root.Position
	local runtime = walkRuntime[player]
	if not runtime or runtime.petName ~= petName then
		walkRuntime[player] = { petName = petName, lastPosition = current, distance = 0 }
		return getState(player)
	end
	local moved = Vector3.new(current.X - runtime.lastPosition.X, 0, current.Z - runtime.lastPosition.Z).Magnitude
	runtime.lastPosition = current
	if moved < 0.15 then return getState(player) end
	runtime.distance = math.max(0, runtime.distance or 0) + math.clamp(moved, 0, 14)
	local chunks = math.floor(runtime.distance / WALK_AWARD_DISTANCE)
	if chunks > 0 then
		runtime.distance -= chunks * WALK_AWARD_DISTANCE
		local energy = math.clamp(tonumber(petValue:GetAttribute("Energy")) or 100, 0, 100)
		energy = math.max(0, energy - ENERGY_LOSS_PER_WALK_AWARD * chunks)
		petValue:SetAttribute("Energy", energy)
		if energy <= 0 and petValue:GetAttribute("Tired") ~= true then
			petValue:SetAttribute("Tired", true)

			if canSendNeedNotice(player) then
				EggNotify:FireClient(
					player,
					"Tired",
					{
						petName = petName,
						state = getState(player),
					}
				)
			end
		end
		markHungryForWalk(player, petValue, chunks, petName)
	end
	return getState(player)
end

local function awardWalkProgress(player)
	local selectedPetName = getActiveOwnedPetName(player)
	if selectedPetName ~= "" then
		return awardSelectedPetWalkCare(player, selectedPetName)
	end
	local egg = getEggValue(player)
	if not egg or getProgress(player) >= 100 then return getState(player) end
	local model = findOwnedEggModel(player)
	if not model then
		walkRuntime[player] = nil
		return getState(player)
	end
	local character = player.Characterlocal character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return getState(player) end
	local current = root.Position
	local runtime = walkRuntime[player]
	if not runtime then
		walkRuntime[player] = { lastPosition = current, distance = 0 }
		return getState(player)
	end
	local moved = Vector3.new(current.X - runtime.lastPosition.X, 0, current.Z - runtime.lastPosition.Z).Magnitude
	runtime.lastPosition = current
	if moved < 0.15 then return getState(player) end
	runtime.distance = math.max(0, runtime.distance or 0) + math.clamp(moved, 0, 14)
	local chunks = math.floor(runtime.distance / WALK_AWARD_DISTANCE)
	if chunks > 0 then
		runtime.distance -= chunks * WALK_AWARD_DISTANCE
		local state = addProgress(player, chunks * WALK_PROGRESS, "pasear")
		if getProgress(player) < 100 then
			drainEnergyForWalk(player, egg, chunks)
			local walkAwards = math.max(0, math.floor(tonumber(egg:GetAttribute("WalkAwardsSinceClean")) or 0)) + chunks
			egg:SetAttribute("WalkAwardsSinceClean", walkAwards)
			markDirtyIfNeeded(player, egg)
			markHungryForWalk(player, egg, chunks, EGG_NAME)
		end
		return state
	end
	return getState(player)
end

local function addSleepingZzz(clone, adornee)
	if not adornee then return end
	local zzz = Instance.new("BillboardGui")
	zzz.Name = "SleepingZzz"
	zzz.Adornee = adornee
	zzz.AlwaysOnTop = true
	zzz.Size = UDim2.fromOffset(190, 135)
	zzz.StudsOffsetWorldSpace = Vector3.new(0, 3.15, 0)
	zzz.Parent = clone

	local letters = {}
	local specs = {
		{ text = "Z", x = 0.22, delay = 0.00, size = 38, sway = 0.050 },
		{ text = "z", x = 0.47, delay = 0.28, size = 31, sway = 0.042 },
		{ text = "z", x = 0.68, delay = 0.56, size = 24, sway = 0.034 },
	}
	for index, spec in ipairs(specs) do
		local label = Instance.new("TextLabel")
		label.Name = "SleepLetter" .. index
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(spec.x, 0.76)
		label.Size = UDim2.fromOffset(spec.size + 18, spec.size + 18)
		label.Font = Enum.Font.FredokaOne
		label.Text = spec.text
		label.TextSize = spec.size
		label.TextColor3 = Color3.fromRGB(235, 245, 255)
		label.TextStrokeColor3 = Color3.fromRGB(38, 48, 88)
		label.TextStrokeTransparency = 0
		label.TextTransparency = 1
		label.Rotation = -8 + index * 7
		label.Parent = zzz
		table.insert(letters, { label = label, spec = spec })
	end

	task.spawn(function()
		local cycle = 2.35
		while clone.Parent and zzz.Parent do
			local now = os.clock()
			for _, item in ipairs(letters) do
				local label = item.label
				local spec = item.spec
				local alpha = ((now + spec.delay) % cycle) / cycle
				local eased = alpha * alpha * (3 - 2 * alpha)
				local fadeIn = math.clamp(alpha / 0.24, 0, 1)
				local fadeOut = 1 - math.clamp((alpha - 0.66) / 0.34, 0, 1)
				local visible = math.clamp(fadeIn * fadeOut, 0, 1)
				local sway = math.sin((alpha * math.pi * 2) + spec.delay * 2.4) * (spec.sway or 0.04)
				local floatY = 0.84 - eased * 0.62
				label.Position = UDim2.fromScale(spec.x + sway, floatY)
				label.TextTransparency = 1 - visible
				label.TextStrokeTransparency = 1 - visible * 0.9
				label.TextSize = spec.size + math.floor(math.sin(math.clamp(alpha / 0.66, 0, 1) * math.pi) * 4)
				label.Rotation = -8 + math.sin(alpha * math.pi * 2 + spec.delay) * 7
			end
			task.wait(0.025)
		end
	end)
end

local function playSleepAnimation(clone, petName, sleepSettings)
	local config = PetConfigs[petName] or (aliases[petName] and PetConfigs[aliases[petName]])
	local sleepAnimation = config and config.Sleep
	if type(sleepAnimation) ~= "string" or sleepAnimation == "" then return end
	local animatorParent = clone:FindFirstChildOfClass("Humanoid") or clone:FindFirstChildOfClass("AnimationController")
	if not animatorParent then
		animatorParent = Instance.new("AnimationController")
		animatorParent.Name = "SleepAnimationController"
		animatorParent.Parent = clone
	end
	local animator = animatorParent:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = animatorParent
	end
	local animation = Instance.new("Animation")
	animation.Name = "Sleep"
	animation.AnimationId = sleepAnimation
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and track then
		track.Looped = false
		track.Priority = Enum.AnimationPriority.Action
		track:Play(0.12, 1, 1)
		task.spawn(function()
			local startedAt = os.clock()
			while clone.Parent and track.Length <= 0 and os.clock() - startedAt < 2 do
				task.wait(0.05)
			end
			local holdTime = tonumber(sleepSettings and sleepSettings.sleepHoldTime)
			local holdFraction = math.clamp(tonumber(sleepSettings and sleepSettings.sleepHoldFraction) or 0.43, 0.1, 0.98)
			local holdPosition = holdTime or (track.Length > 0 and math.max(track.Length * holdFraction, 0.05) or 0.43)
			if track.Length > 0 then
				holdPosition = math.clamp(holdPosition, 0.05, math.max(track.Length - 0.03, 0.05))
			end
			task.wait(holdPosition)
			if clone.Parent then
				if not track.IsPlaying then
					track:Play(0, 1, 0)
				end
				track.TimePosition = holdPosition
				track:AdjustSpeed(0)
			end
		end)
	else
		warn("No se pudo cargar animacion Sleep para " .. tostring(petName))
	end
end

local function showBedPet(player, petName, isEgg)
	petName = normalizeStoredPetName(petName)
	local bed = findPetBed()
	local petsFolder = ReplicatedStorage:FindFirstChild("Mascotas")
	local source = petsFolder and petsFolder:FindFirstChild(petName)
	if not source and aliases[petName] and petsFolder then
		source = petsFolder:FindFirstChild(aliases[petName])
	end
	if not bed or not bed:IsA("BasePart") or not source then return nil end
	local cloneName = (isEgg and "BrizabelleSleepingEgg_" or "BrizabelleSleepingPet_") .. player.UserId
	local old = Workspace:FindFirstChild(cloneName)
	if old then old:Destroy() end
	local clone = source:Clone()
	if isEgg then
		local eggValue = getEggValue(player)
		if eggValue and eggValue:GetAttribute("Dirty") == true then
			applyDirtyEggAppearance(clone)
		end
	end
	clone.Name = cloneName
	clone:SetAttribute("Owner", nil)
	clone:SetAttribute("PetType", nil)
	clone:SetAttribute("PetRenderSource", nil)
	clone:SetAttribute("SleepingOwner", player.UserId)
	clone:SetAttribute("SleepingEgg", isEgg == true)
	clone:SetAttribute("SleepingPet", isEgg ~= true)
	clone:SetAttribute("SleepingPetType", petName)
	clone.Parent = Workspace
	local adornee = clone.PrimaryPart or clone:FindFirstChild("HumanoidRootPart") or clone:FindFirstChildWhichIsA("BasePart", true)
	if adornee and adornee:IsA("BasePart") then
		clone.PrimaryPart = adornee
	end
	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = part == adornee
			part.CanCollide = false
			part.CanTouch = false
			part.Massless = true
		end
	end
	local petOffset = (not isEgg) and sleepingPetOffsets[petName] or nil
	local sleepSettings = petOffset
	local petSleepHoldTime = (not isEgg) and getPetSleepHoldTime(petName) or nil
	if petSleepHoldTime then
		sleepSettings = sleepSettings and table.clone(sleepSettings) or {}
		sleepSettings.sleepHoldTime = petSleepHoldTime
	end
	local heightOffset = petOffset and petOffset.height or (isEgg and (tonumber(bed:GetAttribute("SleepingEggHeight")) or 1.85) or (tonumber(bed:GetAttribute("SleepingPetHeight")) or 0.55))
	local forwardOffset = petOffset and petOffset.forward or (isEgg and (tonumber(bed:GetAttribute("SleepingEggForwardOffset")) or -0.05) or (tonumber(bed:GetAttribute("SleepingPetForwardOffset")) or -0.05))
	local pitchDegrees = petOffset and petOffset.pitch or (isEgg and (tonumber(bed:GetAttribute("SleepingEggPitchDegrees")) or 0) or (tonumber(bed:GetAttribute("SleepingPetPitchDegrees")) or 0))
	local yawDegrees = petOffset and petOffset.yaw or (isEgg and (tonumber(bed:GetAttribute("SleepingEggYawDegrees")) or 0) or (tonumber(bed:GetAttribute("SleepingPetYawDegrees")) or -90))
	local rollDegrees = petOffset and petOffset.roll or (isEgg and (tonumber(bed:GetAttribute("SleepingEggRollDegrees")) or -13) or (tonumber(bed:GetAttribute("SleepingPetRollDegrees")) or 0))
	local sleepPosition = (bed.CFrame * CFrame.new(0, bed.Size.Y * 0.5 + heightOffset, forwardOffset)).Position
	local logoDirection = -bed.CFrame.LookVector
	local lookTarget = sleepPosition + Vector3.new(logoDirection.X, 0, logoDirection.Z)
	local cf = CFrame.lookAt(sleepPosition, lookTarget) * CFrame.Angles(math.rad(pitchDegrees), math.rad(yawDegrees), math.rad(rollDegrees))
	clone:PivotTo(cf)
	local animationOk, animationErr = pcall(function()
		playSleepAnimation(clone, petName, sleepSettings)
	end)
	if not animationOk then
		warn("No se pudo reproducir Sleep para " .. tostring(petName) .. ": " .. tostring(animationErr))
	end
	addSleepingZzz(clone, adornee)
	return clone
end

local function showBedEgg(player)
	return showBedPet(player, EGG_NAME, true)
end

BuyEgg.OnServerInvoke = function(player)
	local money = getMoneyValue(player)
	if not money then
		return { ok = false, message = "No se encontro tu dinero.", state = getState(player) }
	end
	if money.Value < EGG_PRICE then
		return { ok = false, message = "Dinero insuficiente", state = getState(player) }
	end
	money.Value -= EGG_PRICE
	local now = os.time()
	addPetAmount(player, EGG_NAME, 1, {
		Stage = "Huevo",
		GrowthStage = "Huevo",
		Progress = 0,
		Dirty = false,
		Tired = false,
		Energy = 100,
		WalkAwardsSinceClean = 0,
		PurchasedAt = now,
		LastWalkAwardAt = now,
	})
	player:SetAttribute("SelectedBackpackPet", EGG_NAME)
	player:SetAttribute("BrizabelleEggProgress", 0)
	EggNotify:FireClient(player, "Purchased", getState(player))
	return { ok = true, message = "Adquiriste un huevo mascota", state = getState(player) }
end

CareEgg.OnServerInvoke = function(player, action)
	action = tostring(action or "")
	local egg = getEggValue(player)
	if action == "Clean" then
		if not egg then
			return { ok = false, message = "No tienes un huevo.", state = getState(player) }
		end
		if egg:GetAttribute("Dirty") ~= true then
			return { ok = false, message = "El huevo ya esta limpio.", state = getState(player) }
		end
		egg:SetAttribute("Dirty", false)
		egg:SetAttribute("WalkAwardsSinceClean", 0)
		walkRuntime[player] = nil
		spawnOwnedEggModel(player, true)
		local state = addProgress(player, CLEAN_PROGRESS, "limpiar", true)
		awardPlayerXP(player, CLEAN_XP)
		updateEggPrompt(player)
		return { ok = true, message = "Limpiaste el huevo. +5% +10 XP", state = state }
	elseif action == "Walk" then
		return { ok = true, message = "Paseando.", state = awardWalkProgress(player) }
	elseif action == "Pet" then
		local selectedPetName = getActiveOwnedPetName(player)
		local selectedPetValue = selectedPetName ~= "" and getItemValue(player, selectedPetName) or nil
		if selectedPetValue then
			local state = addSelectedPetProgress(player, selectedPetValue, PET_PROGRESS, "acariciar")
			return { ok = true, message = "Acariciaste a " .. selectedPetName .. ". +" .. PET_PROGRESS .. "%", state = state }
		end
		return { ok = true, message = "Acariciaste tu huevo", state = getState(player) }
	elseif action == "Feed" or action == "Eat" then
		local foodTool = getEquippedFoodTool(player)
		if not foodTool then
			return { ok = false, message = "Saca una fruta o vegetal para comer.", state = getState(player) }
		end
		local foodName = tostring(foodTool:GetAttribute("ItemName") or foodTool.Name):gsub("^%s+", ""):gsub("%s+$", "")
		local selectedPetName = getActiveOwnedPetName(player)
		local selectedPetValue = selectedPetName ~= "" and getItemValue(player, selectedPetName) or nil
		if not selectedPetValue and not egg then
			return { ok = false, message = "Equipa tu huevo o mascota para comer.", state = getState(player) }
		end
		if selectedPetValue and selectedPetValue:GetAttribute("Hungry") ~= true then
			return { ok = false, message = selectedPetName .. " no tiene hambre.", state = getState(player) }
		end
		if egg and not selectedPetValue and egg:GetAttribute("Hungry") ~= true then
			return { ok = false, message = "Tu huevo no tiene hambre.", state = getState(player) }
		end
		foodTool:Destroy()
		if selectedPetValue then
			selectedPetValue:SetAttribute("Hungry", false)
			selectedPetValue:SetAttribute("FoodCareWalks", 0)
			selectedPetValue:SetAttribute("LastFedAt", os.time())
			local state = addSelectedPetProgress(player, selectedPetValue, FEED_PROGRESS, "comer")
			awardPlayerXP(player, FEED_XP)
			queuePetSave(player)
			EggNotify:FireClient(player, "Fed", { petName = selectedPetName, state = state })
			return { ok = true, message = selectedPetName .. " comio " .. foodName .. ". +" .. FEED_PROGRESS .. "% +" .. FEED_XP .. " XP", state = state }
		end
		egg:SetAttribute("Hungry", false)
		egg:SetAttribute("FoodCareWalks", 0)
		egg:SetAttribute("LastFedAt", os.time())
		local state = addProgress(player, FEED_PROGRESS, "comer", true)
		awardPlayerXP(player, FEED_XP)
		queuePetSave(player)
		EggNotify:FireClient(player, "Fed", { message = "Tu huevo comio " .. foodName, state = state })
		return { ok = true, message = "Tu huevo comio " .. foodName .. ". +" .. FEED_PROGRESS .. "% +" .. FEED_XP .. " XP", state = state }
	elseif action == "Sleep" then
		local selectedPetName = getActiveOwnedPetName(player)
		local selectedPetValue = selectedPetName ~= "" and getItemValue(player, selectedPetName) or nil
		local sleepingClone = sleepingEggs[player]
		local workspaceEggClone = Workspace:FindFirstChild("BrizabelleSleepingEgg_" .. player.UserId)
		local workspacePetClone = Workspace:FindFirstChild("BrizabelleSleepingPet_" .. player.UserId)

		if sleepingBedOccupant and sleepingBedOccupant ~= player.UserId then
			return { ok = false, message = "La cama ya esta ocupada.", state = getState(player) }
		end

		if selectedPetValue then
			if selectedPetValue:GetAttribute("Resting") == true and not sleepingClone and not workspacePetClone then
				selectedPetValue:SetAttribute("Resting", false)
			end
			if selectedPetValue:GetAttribute("Resting") == true or sleepingClone or workspacePetClone then
				return { ok = false, message = "Tu mascota ya esta descansando.", state = getState(player) }
			end
			if selectedPetValue:GetAttribute("Tired") ~= true then
				return { ok = false, message = "Tu mascota no necesita dormir.", state = getState(player) }
			end
			selectedPetValue:SetAttribute("Resting", true)
			player:SetAttribute(SLEEP_LOCK_ATTR, true)
			player:SetAttribute(SLEEP_RESTORE_PET_ATTR, selectedPetName)
			player:SetAttribute(SLEEP_RESTORE_UNTIL_ATTR, os.clock() + SLEEP_DURATION + 6)
			player:SetAttribute("SelectedBackpackPet", selectedPetName)
			walkRuntime[player] = nil
			removeOwnedPetModels(player, selectedPetName)
			removeOwnedEggModels(player)
			local petSleepingClone = showBedPet(player, selectedPetName, false)
			if not petSleepingClone then
				selectedPetValue:SetAttribute("Resting", false)
				player:SetAttribute(SLEEP_LOCK_ATTR, false)
				spawnOwnedPetModel(player, selectedPetName)
				return { ok = false, message = "No se pudo poner la mascota en la cama.", state = getState(player) }
			end
			sleepingEggs[player] = petSleepingClone
			sleepingBedOccupant = player.UserId
			EggNotify:FireClient(player, "SleepStarted", { state = getState(player) })
			task.spawn(function()
				local stopAt = os.clock() + SLEEP_DURATION
				while player.Parent and petSleepingClone.Parent and os.clock() < stopAt do
					removeOwnedEggModels(player)
					task.wait(0.25)
				end
			end)
			task.delay(SLEEP_DURATION, function()
				if petSleepingClone and petSleepingClone.Parent then petSleepingClone:Destroy() end
				sleepingEggs[player] = nil
				if sleepingBedOccupant == player.UserId then sleepingBedOccupant = nil end
				if not player.Parent then return end
				local currentPet = getItemValue(player, selectedPetName)
				if not currentPet then
					player:SetAttribute(SLEEP_LOCK_ATTR, false)
					return
				end
				currentPet:SetAttribute("Tired", false)
				currentPet:SetAttribute("Resting", false)
				currentPet:SetAttribute("Energy", 100)
				tiredNoticeRuntime[player] = nil
				local state = addSelectedPetProgress(player, currentPet, SLEEP_PROGRESS, "dormir")
				removeOwnedEggModels(player)
				player:SetAttribute(SLEEP_RESTORE_PET_ATTR, selectedPetName)
				player:SetAttribute(SLEEP_RESTORE_UNTIL_ATTR, os.clock() + 6)
				player:SetAttribute("SelectedBackpackPet", selectedPetName)
				player:SetAttribute(SLEEP_LOCK_ATTR, false)
				spawnOwnedPetModel(player, selectedPetName)
				queuePetSave(player)
				EggNotify:FireClient(player, "Rested", { petName = selectedPetName, state = state })
			end)
			return { ok = true, message = "Tu mascota debe descansar en la cama.", state = getState(player) }
		end

		if not egg then
			return { ok = false, message = "Equipa un huevo o mascota cansada.", state = getState(player) }
		end
		if egg:GetAttribute("Resting") == true and not sleepingClone and not workspaceEggClone then
			egg:SetAttribute("Resting", false)
		end
		if egg:GetAttribute("Resting") == true or sleepingClone or workspaceEggClone then
			return { ok = false, message = "Tu huevo ya esta descansando.", state = getState(player) }
		end
		if egg:GetAttribute("Tired") ~= true then
			return { ok = false, message = "Tu huevo no necesita dormir.", state = getState(player) }
		end
		egg:SetAttribute("Resting", true)
		walkRuntime[player] = nil
		removeOwnedEggModels(player)
		local eggSleepingClone = showBedEgg(player)
		sleepingEggs[player] = eggSleepingClone or true
		sleepingBedOccupant = player.UserId
		EggNotify:FireClient(player, "SleepStarted", getState(player))
		task.delay(SLEEP_DURATION, function()
			if eggSleepingClone and eggSleepingClone.Parent then eggSleepingClone:Destroy() end
			sleepingEggs[player] = nil
			if sleepingBedOccupant == player.UserId then sleepingBedOccupant = nil end
			if not player.Parent then return end
			local currentEgg = getEggValue(player)
			if not currentEgg then return end
			currentEgg:SetAttribute("Tired", false)
			currentEgg:SetAttribute("Resting", false)
			tiredNoticeRuntime[player] = nil
			currentEgg:SetAttribute("Energy", 100)
			local state = addProgress(player, SLEEP_PROGRESS, "descansar", true)
			awardPlayerXP(player, SLEEP_XP)
			spawnOwnedEggModel(player)
			EggNotify:FireClient(player, "Rested", { state = state })
		end)
		return { ok = true, message = "Tu huevo debe descansar en la cama.", state = getState(player) }
	end
	return { ok = false, message = "Accion desconocida.", state = getState(player) }
end

HatchEgg.OnServerInvoke = function(player)
	local state = getState(player)
	if state.eggCount <= 0 then
		return { ok = false, message = "No tienes un huevo para abrir.", state = state }
	end
	if not state.ready then
		return { ok = false, message = "Tu huevo necesita llegar al 100%.", state = state }
	end
	local result, err = grantHatchedPet(player, "Huevo Brizabelle")
	if not result then
		return { ok = false, message = err or "No se pudo abrir el huevo.", state = getState(player) }
	end
	return { ok = true, message = "Tu huevo abrio: " .. result.petName .. " (" .. result.rarity .. ").", result = result, state = getState(player) }
end

RequestInstantHatch.OnServerInvoke = function(player)
	local state = getState(player)
	if state.eggCount <= 0 then
		return { ok = false, message = "No tienes huevos para abrir.", state = state }
	end
	local productId = tonumber(folder:GetAttribute("InstantHatchProductId")) or 0
	if productId <= 0 then
		return { ok = false, message = "Producto Robux pendiente de configurar.", state = state }
	end
	pendingInstantHatch[player.UserId] = true
	return { ok = true, productId = productId, priceRobux = INSTANT_HATCH_PRICE_ROBUX, state = state }
end

ConfirmInstantHatch.OnServerInvoke = function(player)
	if not pendingInstantHatch[player.UserId] then
		return { ok = false, message = "No hay compra instantanea pendiente.", state = getState(player) }
	end
	if countItem(player, EGG_NAME) <= 0 then
		pendingInstantHatch[player.UserId] = nil
		return { ok = false, message = "No tienes huevos para abrir.", state = getState(player) }
	end
	pendingInstantHatch[player.UserId] = nil
	local result, err = grantHatchedPet(player, "Apertura instantanea Studio")
	if not result then
		return { ok = false, message = err or "No se pudo abrir el huevo.", state = getState(player) }
	end
	return { ok = true, result = result, state = getState(player) }
end

local function grantOswaldRobuxDollars(player, amount)
	local money = getMoneyValue(player)

	if not money then
		return false, "No se encontro tu valor de Dolares."
	end

	amount = math.max(0, math.floor(tonumber(amount) or 0))

	if amount <= 0 then
		return false, "Cantidad de compra invalida."
	end

	money.Value += amount

	-- Guardado inmediato adicional porque esta recompensa fue pagada
	-- con Robux. GranjaMoneyServer tambien seguira guardando normalmente.
	local saveOk, saveErr = pcall(function()
		dollarStore:SetAsync(
			tostring(player.UserId),
			math.max(0, math.floor(tonumber(money.Value) or 0))
		)
	end)

	if not saveOk then
		warn(
			"[OswaldRobuxShop] Se dio el dinero, pero fallo el guardado inmediato: "
				.. tostring(saveErr)
		)
	end

	OswaldPurchaseResult:FireClient(player, {
		ok = true,
		dollars = amount,
		totalDollars = money.Value,
	})

	return true
end

MarketplaceService.ProcessReceipt = function(receiptInfo)
	--========================================================
	-- 1) PRODUCTOS DE OSWALD
	--========================================================

	local oswaldDollars =
		OSWALD_DOLLAR_PRODUCTS[receiptInfo.ProductId]

	if oswaldDollars then
		local player =
			Players:GetPlayerByUserId(receiptInfo.PlayerId)

		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local granted, err =
			grantOswaldRobuxDollars(
				player,
				oswaldDollars
			)

		if not granted then
			OswaldPurchaseResult:FireClient(player, {
				ok = false,
				message = err or "No se pudo entregar la compra.",
			})

			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		print(
			"[OswaldRobuxShop] Compra concedida | "
				.. player.Name
				.. " | +"
				.. tostring(oswaldDollars)
				.. "$ | ProductId "
				.. tostring(receiptInfo.ProductId)
		)

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	--========================================================
	-- 2) APERTURA INSTANTANEA DE BRIZABELLE
	--========================================================

	local productId =
		tonumber(
			folder:GetAttribute("InstantHatchProductId")
		) or 0

	if productId <= 0
		or receiptInfo.ProductId ~= productId
	then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local player =
		Players:GetPlayerByUserId(receiptInfo.PlayerId)

	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if countItem(player, EGG_NAME) <= 0 then
		pendingInstantHatch[player.UserId] = nil
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	pendingInstantHatch[player.UserId] = nil

	grantHatchedPet(
		player,
		"Apertura instantanea Robux"
	)

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

GetState.OnServerInvoke = function(player)
	awardWalkProgress(player)
	return getState(player)
end

SelectPet.OnServerEvent:Connect(function(player, petName)
	petName = normalizeStoredPetName(petName)
	if petName == "" then return end
	local restorePet = normalizeStoredPetName(player:GetAttribute(SLEEP_RESTORE_PET_ATTR) or "")
	local restoreUntil = tonumber(player:GetAttribute(SLEEP_RESTORE_UNTIL_ATTR)) or 0
	if player:GetAttribute(SLEEP_LOCK_ATTR) == true or Workspace:FindFirstChild("BrizabelleSleepingEgg_" .. player.UserId) or Workspace:FindFirstChild("BrizabelleSleepingPet_" .. player.UserId) then
		return
	end
	if petName == EGG_NAME and restorePet ~= "" and os.clock() < restoreUntil and getItemValue(player, restorePet) then
		player:SetAttribute("SelectedBackpackPet", restorePet)
		queuePetSave(player)
		return
	end
	if petName == EGG_NAME then
		if getEggValue(player) then
			player:SetAttribute("SelectedBackpackPet", EGG_NAME)
			walkRuntime[player] = nil
			queuePetSave(player)
		end
		return
	end
	local petValue = getItemValue(player, petName)
	if not petValue then return end
	ensureCareDefaults(petValue, false)
	player:SetAttribute("SelectedBackpackPet", petName)
	walkRuntime[player] = nil
	queuePetSave(player)
end)

Players.PlayerAdded:Connect(function(player)
	loadPetInventory(player)
	player:GetAttributeChangedSignal("SelectedBackpackPet"):Connect(function()
		queuePetSave(player)
	end)
	player:GetAttributeChangedSignal("BrizabelleEggProgress"):Connect(function()
		queuePetSave(player)
	end)
	local container = getPetContainer(player)
	container.ChildAdded:Connect(function(child)
		if child:IsA("IntValue") or child:IsA("NumberValue") then
			trackPetValue(player, child)
			queuePetSave(player)
		end
	end)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("IntValue") or child:IsA("NumberValue") then
			ensureCareDefaults(child, normalizeStoredPetName(child:GetAttribute("ItemName") or child.Name) == EGG_NAME)
			trackPetValue(player, child)
		end
	end
	local egg = getEggValue(player)
	if egg then
		egg:SetAttribute("Resting", false)
		player:SetAttribute("BrizabelleEggProgress", getProgress(player))
	end

	-- Desde este punto los datos ya están cargados.
	-- Durante 12 s cualquier necesidad heredada del Place anterior
	-- se aplica al estado, pero NO vuelve a lanzar su alerta.
	needNoticeReadyAt[player] =
		os.clock()
		+ NEED_NOTICE_STARTUP_GRACE
end)

task.spawn(function()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			awardWalkProgress(player)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	pendingPetSaves[player] = nil
	walkRuntime[player] = nil
	tiredNoticeRuntime[player] = nil
	needNoticeReadyAt[player] = nil
	local sleepingClone = sleepingEggs[player]
	if typeof(sleepingClone) == "Instance" and sleepingClone.Parent then sleepingClone:Destroy() end
	local sleepingEggClone = Workspace:FindFirstChild("BrizabelleSleepingEgg_" .. player.UserId)
	if sleepingEggClone then sleepingEggClone:Destroy() end
	local sleepingPetClone = Workspace:FindFirstChild("BrizabelleSleepingPet_" .. player.UserId)
	if sleepingPetClone then sleepingPetClone:Destroy() end
	if sleepingBedOccupant == player.UserId then sleepingBedOccupant = nil end
	sleepingEggs[player] = nil
	savePetInventoryNow(player)
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		savePetInventoryNow(player)
	end
end)

ensureWorldPrompts()

task.spawn(function()
	while true do
		task.wait(5)
		ensureWorldPrompts()
		for _, player in ipairs(Players:GetPlayers()) do
			awardWalkProgress(player)
			updateDirtyState(player)
		end
	end
end)

warn("[PetNeeds] STARTUP ALERT FIX activo | no repite necesidades viejas al cambiar de mundo.")
