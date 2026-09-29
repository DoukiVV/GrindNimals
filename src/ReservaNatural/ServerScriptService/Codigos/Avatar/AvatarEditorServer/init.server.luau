--============================================================
-- AVATAR EDITOR SERVER V14.3 STABLE - COSMETICOS CON REBUILD LIMPIO DEBOUNCED
-- Catalogo actual + ropa 3D + bundles por UserOutfit + guardado + SPAWN SIN PARPADEO.
--
-- REEMPLAZA el servidor viejo que escucha ReplicatedStorage.UpdateAvatar.
--
-- La diferencia importante con el servidor antiguo:
-- NO reemplaza Torso/Head/brazos manualmente con ReplaceBodyPartR15.
-- Construye un HumanoidDescription completo y usa
-- Humanoid:ApplyDescriptionResetAsync(), evitando romper Neck/attachments.
--
-- Mantiene el DataStore AvatarEditorAppearanceV1 para NO perder
-- la apariencia que ya hubieras guardado con la V5.
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local AssetService = game:GetService("AssetService")
local DataStoreService = game:GetService("DataStoreService")

--============================================================
-- V10 - SPAWN CORRECTO DESDE EL PRIMER FRAME
--
-- Antes Roblox creaba primero el avatar normal y, ~2 segundos después,
-- este script ejecutaba ApplyDescriptionResetAsync con la apariencia
-- guardada. Ese segundo montaje era el "parpadeo" que se veía al entrar.
--
-- Ahora desactivamos el autospawn y creamos al jugador DIRECTAMENTE
-- con su HumanoidDescription final.
--============================================================
Players.CharacterAutoLoads = false

-- V12: UpdateAvatar se garantiza desde el servidor.
-- Si el RemoteEvent no existe, el cliente se queda detenido en WaitForChild()
-- y el botón Vestirse nunca llega a conectarse.
local remoteEvent = ReplicatedStorage:FindFirstChild("UpdateAvatar")

if remoteEvent and not remoteEvent:IsA("RemoteEvent") then
	warn("[AvatarEditorV14.3] UpdateAvatar existía pero NO era RemoteEvent. Se reemplazará.")
	remoteEvent:Destroy()
	remoteEvent = nil
end

if not remoteEvent then
	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = "UpdateAvatar"
	remoteEvent.Parent = ReplicatedStorage
end

local STORE_NAME = "AvatarEditorAppearanceV1"
local appearanceStore = DataStoreService:GetDataStore(STORE_NAME)

local MAX_RIGID_ACCESSORIES = 10
local MIN_ACTION_INTERVAL = 0.08

local playerStates = {}
local applying = {}
local saveInProgress = {}
local lastActionAt = {}
local respawnScheduled = {}

-- V14.3: agrupa cambios rápidos de cosméticos para no recrear el Character
-- varias veces si el jugador toca varios artículos seguidos.
local cosmeticRefreshSerial = {}
local COSMETIC_REFRESH_DELAY = 0.20

local avatarTypeById = {}
local avatarTypeIdByName = {}

for _, enumItem in ipairs(Enum.AvatarAssetType:GetEnumItems()) do
	avatarTypeById[enumItem.Value] = enumItem
	avatarTypeIdByName[enumItem.Name] = enumItem.Value
end

--============================================================
-- TIPOS ADMITIDOS
-- Incluye ropa clasica + ropa 3D/layered + partes del cuerpo actuales.
--============================================================
local ALLOWED_ASSET_TYPES = {
	[2] = true,  -- TShirt
	[8] = true,  -- Hat
	[11] = true, -- Shirt
	[12] = true, -- Pants
	[17] = true, -- Head
	[18] = true, -- Face
	[27] = true, -- Torso
	[28] = true, -- RightArm
	[29] = true, -- LeftArm
	[30] = true, -- LeftLeg
	[31] = true, -- RightLeg

	[41] = true, -- HairAccessory
	[42] = true, -- FaceAccessory
	[43] = true, -- NeckAccessory
	[44] = true, -- ShoulderAccessory
	[45] = true, -- FrontAccessory
	[46] = true, -- BackAccessory
	[47] = true, -- WaistAccessory

	[48] = true, -- ClimbAnimation
	[50] = true, -- FallAnimation
	[51] = true, -- IdleAnimation
	[52] = true, -- JumpAnimation
	[53] = true, -- RunAnimation
	[54] = true, -- SwimAnimation
	[55] = true, -- WalkAnimation

	[64] = true, -- TShirtAccessory
	[65] = true, -- ShirtAccessory
	[66] = true, -- PantsAccessory
	[67] = true, -- JacketAccessory
	[68] = true, -- SweaterAccessory
	[69] = true, -- ShortsAccessory
	[70] = true, -- LeftShoeAccessory
	[71] = true, -- RightShoeAccessory
	[72] = true, -- DressSkirtAccessory
	[76] = true, -- EyebrowAccessory
	[77] = true, -- EyelashAccessory
	[78] = true, -- MoodAnimation
	[79] = true, -- DynamicHead
}

local bannedAssets = {
	-- [123456789] = true,
}

local RIGID_PROPERTY_BY_TYPE = {
	[8] = "HatAccessory",
	[41] = "HairAccessory",
	[42] = "FaceAccessory",
	[43] = "NeckAccessory",
	[44] = "ShouldersAccessory",
	[45] = "FrontAccessory",
	[46] = "BackAccessory",
	[47] = "WaistAccessory",
}

local LAYERED_ACCESSORY_TYPE_BY_ASSET = {
	[64] = Enum.AccessoryType.TShirt,
	[65] = Enum.AccessoryType.Shirt,
	[66] = Enum.AccessoryType.Pants,
	[67] = Enum.AccessoryType.Jacket,
	[68] = Enum.AccessoryType.Sweater,
	[69] = Enum.AccessoryType.Shorts,
	[70] = Enum.AccessoryType.LeftShoe,
	[71] = Enum.AccessoryType.RightShoe,
	[72] = Enum.AccessoryType.DressSkirt,
	[76] = Enum.AccessoryType.Eyebrow,
	[77] = Enum.AccessoryType.Eyelash,
}

--============================================================
-- V8 - PUFFINESS CORRECTO PARA ROPA 3D
--
-- V7 forzaba Puffiness = 0 en TODA la ropa 3D. Eso hace que prendas
-- layered queden pegadas al cuerpo y, al caminar/idle, el cuerpo interno
-- puede atravesar la prenda y verse como una "silueta" gris/transparente.
--
-- Usamos valores moderados por tipo para dejar separación real del cuerpo.
--============================================================
local LAYERED_PUFFINESS_BY_ASSET = {
	[64] = 0.25, -- TShirt
	[65] = 0.38, -- Shirt
	[66] = 0.40, -- Pants
	[67] = 0.65, -- Jacket
	[68] = 0.55, -- Sweater
	[69] = 0.38, -- Shorts
	[70] = 0.28, -- LeftShoe
	[71] = 0.28, -- RightShoe
	[72] = 0.55, -- DressSkirt
	[76] = 0.05, -- Eyebrow
	[77] = 0.05, -- Eyelash
}

-- Los tipos con el mismo SLOT se sustituyen entre si.
-- Ejemplo: Head clasica y DynamicHead comparten "Head".
local SLOT_BY_ASSET_TYPE = {
	[2] = "GraphicTShirt",
	[11] = "Shirt",
	[12] = "Pants",
	[17] = "Head",
	[79] = "Head",
	[18] = "Face",
	[27] = "Torso",
	[28] = "RightArm",
	[29] = "LeftArm",
	[30] = "LeftLeg",
	[31] = "RightLeg",

	-- V11: los accesorios rigidos tambien son SLOT UNICO.
	-- Antes se acumulaban: al poner otro avatar/sombrero/cabello,
	-- Roblox conservaba lo anterior y parecia una segunda silueta.
	[8] = "Rigid_Hat",
	[41] = "Rigid_Hair",
	[42] = "Rigid_Face",
	[43] = "Rigid_Neck",
	[44] = "Rigid_Shoulders",
	[45] = "Rigid_Front",
	[46] = "Rigid_Back",
	[47] = "Rigid_Waist",

	[48] = "ClimbAnimation",
	[50] = "FallAnimation",
	[51] = "IdleAnimation",
	[52] = "JumpAnimation",
	[53] = "RunAnimation",
	[54] = "SwimAnimation",
	[55] = "WalkAnimation",
	[78] = "MoodAnimation",

	[64] = "Layered_TShirt",
	[65] = "Layered_Shirt",
	[66] = "Layered_Pants",
	[67] = "Layered_Jacket",
	[68] = "Layered_Sweater",
	[69] = "Layered_Shorts",
	[70] = "Layered_LeftShoe",
	[71] = "Layered_RightShoe",
	[72] = "Layered_DressSkirt",
	[76] = "Layered_Eyebrow",
	[77] = "Layered_Eyelash",
}

-- V11: al elegir un AVATAR/BUNDLE reemplazamos TODO el aspecto visual
-- anterior, pero conservamos las animaciones elegidas por el jugador.
local ANIMATION_ASSET_TYPES = {
	[48] = true,
	[50] = true,
	[51] = true,
	[52] = true,
	[53] = true,
	[54] = true,
	[55] = true,
	[78] = true,
}

local SCALE_KEYS = {
	"bodyType",
	"depth",
	"head",
	"height",
	"proportion",
	"width",
}

local BODY_COLOR_KEYS = {
	"headColorId",
	"leftArmColorId",
	"leftLegColorId",
	"rightArmColorId",
	"rightLegColorId",
	"torsoColorId",
}

--============================================================
-- UTILIDADES DE ESTADO
--============================================================
local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[deepCopy(k)] = deepCopy(v)
	end
	return copy
end

local function normalizeState(state)
	state = type(state) == "table" and state or {}
	state.assets = type(state.assets) == "table" and state.assets or {}
	state.scales = type(state.scales) == "table" and state.scales or {}
	state.bodyColors = type(state.bodyColors) == "table" and state.bodyColors or {}

	state.scales.bodyType = tonumber(state.scales.bodyType) or 0
	state.scales.depth = tonumber(state.scales.depth) or 1
	state.scales.head = tonumber(state.scales.head) or 1
	state.scales.height = tonumber(state.scales.height) or 1
	state.scales.proportion = tonumber(state.scales.proportion) or 0
	state.scales.width = tonumber(state.scales.width) or 1

	return state
end

local function mergeSavedAppearance(baseInfo, saved)
	baseInfo = normalizeState(baseInfo)
	if type(saved) ~= "table" then
		return baseInfo
	end

	if type(saved.assets) == "table" then
		baseInfo.assets = deepCopy(saved.assets)
	end

	if type(saved.scales) == "table" then
		for _, key in ipairs(SCALE_KEYS) do
			local value = tonumber(saved.scales[key])
			if value ~= nil then
				baseInfo.scales[key] = value
			end
		end
	end

	if type(saved.bodyColors) == "table" then
		for _, key in ipairs(BODY_COLOR_KEYS) do
			local value = tonumber(saved.bodyColors[key])
			if value ~= nil then
				baseInfo.bodyColors[key] = value
			end
		end
	end

	return normalizeState(baseInfo)
end

local function copyStateForSave(state)
	state = normalizeState(state)
	local data = {
		version = 2,
		assets = {},
		scales = {},
		bodyColors = {},
	}

	for _, asset in ipairs(state.assets) do
		if type(asset) == "table" and tonumber(asset.id) then
			local assetType = type(asset.assetType) == "table" and asset.assetType or {}
			table.insert(data.assets, {
				id = tonumber(asset.id),
				name = tostring(asset.name or ""),
				assetType = {
					id = tonumber(assetType.id) or 0,
					name = tostring(assetType.name or ""),
				},
			})
		end
	end

	for _, key in ipairs(SCALE_KEYS) do
		data.scales[key] = tonumber(state.scales[key])
	end

	for _, key in ipairs(BODY_COLOR_KEYS) do
		local value = tonumber(state.bodyColors[key])
		if value then
			data.bodyColors[key] = value
		end
	end

	return data
end

local function saveAppearance(player, reason)
	if not player then
		return false
	end

	local state = playerStates[player]
	if not state or saveInProgress[player] then
		return false
	end

	saveInProgress[player] = true
	local data = copyStateForSave(state)
	local key = "u_" .. player.UserId
	local success = false
	local lastError

	for attempt = 1, 3 do
		local ok, err = pcall(function()
			appearanceStore:SetAsync(key, data)
		end)
		if ok then
			success = true
			break
		end
		lastError = err
		task.wait(0.35 * attempt)
	end

	saveInProgress[player] = nil

	if success then
	else
		warn(string.format(
			"[AvatarEditorV14.3] ERROR GUARDANDO | %s | %s",
			player.Name,
			tostring(lastError)
			))
	end

	return success
end

local function loadSavedAppearance(player)
	local saved
	local ok, err = pcall(function()
		saved = appearanceStore:GetAsync("u_" .. player.UserId)
	end)
	if not ok then
		warn("[AvatarEditorV14.3] Error cargando " .. player.Name .. ": " .. tostring(err))
		return nil
	end
	return saved
end

local function fireState(player)
	local state = playerStates[player]
	if state then
		remoteEvent:FireClient(player, deepCopy(state))
	end
end

--============================================================
-- CONSTRUCCION SEGURA DEL HumanoidDescription
--============================================================
local function colorFromBrickColorNumber(number, fallback)
	number = tonumber(number)
	if not number then
		return fallback
	end

	local ok, brickColor = pcall(function()
		return BrickColor.new(number)
	end)
	if ok and brickColor then
		return brickColor.Color
	end
	return fallback
end

local function makeCsv(list)
	local result = {}
	for _, id in ipairs(list) do
		result[#result + 1] = tostring(id)
	end
	return table.concat(result, ",")
end

local function puffinessForAccessoryType(accessoryType)
	if accessoryType == Enum.AccessoryType.TShirt then
		return 0.35
	elseif accessoryType == Enum.AccessoryType.Shirt then
		return 0.55
	elseif accessoryType == Enum.AccessoryType.Pants then
		return 0.55
	elseif accessoryType == Enum.AccessoryType.Jacket then
		return 0.85
	elseif accessoryType == Enum.AccessoryType.Sweater then
		return 0.75
	elseif accessoryType == Enum.AccessoryType.Shorts then
		return 0.5
	elseif accessoryType == Enum.AccessoryType.DressSkirt then
		return 0.8
	elseif accessoryType == Enum.AccessoryType.LeftShoe or accessoryType == Enum.AccessoryType.RightShoe then
		return 0.3
	elseif accessoryType == Enum.AccessoryType.Eyebrow or accessoryType == Enum.AccessoryType.Eyelash then
		return 0.05
	end
	return nil
end

local function fixLiveWrapLayers(character)
	if not character or not character.Parent then
		return
	end

	for _, accessory in ipairs(character:GetChildren()) do
		if accessory:IsA('Accessory') then
			local puffiness = puffinessForAccessoryType(accessory.AccessoryType)
			if puffiness ~= nil then
				for _, desc in ipairs(accessory:GetDescendants()) do
					if desc:IsA('WrapLayer') then
						pcall(function()
							desc.Puffiness = puffiness
						end)
					end
				end
			end
		end
	end
end

local function buildDescription(state)
	state = normalizeState(state)

	local description = Instance.new("HumanoidDescription")

	description.BodyTypeScale = math.clamp(state.scales.bodyType, 0, 1)
	description.DepthScale = math.clamp(state.scales.depth, 0.5, 1.5)
	description.HeadScale = math.clamp(state.scales.head, 0.5, 1.5)
	description.HeightScale = math.clamp(state.scales.height, 0.5, 1.5)
	description.ProportionScale = math.clamp(state.scales.proportion, 0, 1)
	description.WidthScale = math.clamp(state.scales.width, 0.5, 1.5)

	description.HeadColor = colorFromBrickColorNumber(
		state.bodyColors.headColorId,
		Color3.fromRGB(163, 162, 165)
	)
	description.LeftArmColor = colorFromBrickColorNumber(
		state.bodyColors.leftArmColorId,
		description.HeadColor
	)
	description.LeftLegColor = colorFromBrickColorNumber(
		state.bodyColors.leftLegColorId,
		description.HeadColor
	)
	description.RightArmColor = colorFromBrickColorNumber(
		state.bodyColors.rightArmColorId,
		description.HeadColor
	)
	description.RightLegColor = colorFromBrickColorNumber(
		state.bodyColors.rightLegColorId,
		description.HeadColor
	)
	description.TorsoColor = colorFromBrickColorNumber(
		state.bodyColors.torsoColorId,
		description.HeadColor
	)

	local rigidLists = {
		HatAccessory = {},
		HairAccessory = {},
		FaceAccessory = {},
		NeckAccessory = {},
		ShouldersAccessory = {},
		FrontAccessory = {},
		BackAccessory = {},
		WaistAccessory = {},
	}

	local layered = {}
	local layeredOrder = 0

	for _, asset in ipairs(state.assets) do
		local id = tonumber(asset.id)
		local assetType = type(asset.assetType) == "table" and asset.assetType or {}
		local typeId = tonumber(assetType.id)

		if id and typeId and ALLOWED_ASSET_TYPES[typeId] then
			local rigidProperty = RIGID_PROPERTY_BY_TYPE[typeId]
			if rigidProperty then
				rigidLists[rigidProperty][#rigidLists[rigidProperty] + 1] = id
			elseif LAYERED_ACCESSORY_TYPE_BY_ASSET[typeId] then
				layeredOrder += 1
				layered[#layered + 1] = {
					AssetId = id,
					AccessoryType = LAYERED_ACCESSORY_TYPE_BY_ASSET[typeId],
					IsLayered = true,
					Order = layeredOrder,
					Puffiness = LAYERED_PUFFINESS_BY_ASSET[typeId] or 0.45,
				}
			elseif typeId == 2 then
				description.GraphicTShirt = id
			elseif typeId == 11 then
				description.Shirt = id
			elseif typeId == 12 then
				description.Pants = id
			elseif typeId == 17 or typeId == 79 then
				description.Head = id
			elseif typeId == 18 then
				description.Face = id
			elseif typeId == 27 then
				description.Torso = id
			elseif typeId == 28 then
				description.RightArm = id
			elseif typeId == 29 then
				description.LeftArm = id
			elseif typeId == 30 then
				description.LeftLeg = id
			elseif typeId == 31 then
				description.RightLeg = id
			elseif typeId == 48 then
				description.ClimbAnimation = id
			elseif typeId == 50 then
				description.FallAnimation = id
			elseif typeId == 51 then
				description.IdleAnimation = id
			elseif typeId == 52 then
				description.JumpAnimation = id
			elseif typeId == 53 then
				description.RunAnimation = id
			elseif typeId == 54 then
				description.SwimAnimation = id
			elseif typeId == 55 then
				description.WalkAnimation = id
			elseif typeId == 78 then
				description.MoodAnimation = id
			end
		end
	end

	description.HatAccessory = makeCsv(rigidLists.HatAccessory)
	description.HairAccessory = makeCsv(rigidLists.HairAccessory)
	description.FaceAccessory = makeCsv(rigidLists.FaceAccessory)
	description.NeckAccessory = makeCsv(rigidLists.NeckAccessory)
	description.ShouldersAccessory = makeCsv(rigidLists.ShouldersAccessory)
	description.FrontAccessory = makeCsv(rigidLists.FrontAccessory)
	description.BackAccessory = makeCsv(rigidLists.BackAccessory)
	description.WaistAccessory = makeCsv(rigidLists.WaistAccessory)

	local ok, err = pcall(function()
		description:SetAccessories(layered, false)
	end)
	if not ok then
		warn("[AvatarEditorV14.3] No se pudieron preparar accesorios 3D:", err)
	end

	return description
end

--============================================================
-- APLICACION ANTI-MUERTE
--============================================================
local function safeApplyState(player, state)
	if applying[player] then
		return false, "busy"
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false, "no_character"
	end

	applying[player] = true

	local oldDescription
	pcall(function()
		oldDescription = humanoid:GetAppliedDescription()
	end)

	local oldPivot = character:GetPivot()
	local oldHealth = humanoid.Health
	local oldMaxHealth = humanoid.MaxHealth
	local oldRequiresNeck = humanoid.RequiresNeck
	local oldAutoRotate = humanoid.AutoRotate

	-- Esta es la proteccion clave: mientras Roblox reconstruye UpperTorso/Head,
	-- no permitimos que la ausencia momentanea del Neck mate al Humanoid.
	humanoid.RequiresNeck = false

	local description = buildDescription(state)
	local success, err = pcall(function()
		humanoid:ApplyDescriptionResetAsync(description)
	end)

	if not success and oldDescription then
		pcall(function()
			humanoid:ApplyDescriptionResetAsync(oldDescription)
		end)
	end

	if character.Parent then
		pcall(function()
			character:PivotTo(oldPivot)
		end)
	end

	if humanoid.Parent then
		humanoid.RequiresNeck = oldRequiresNeck
		humanoid.AutoRotate = oldAutoRotate
		humanoid.MaxHealth = oldMaxHealth
		if oldHealth > 0 and humanoid.Health > 0 then
			humanoid.Health = math.min(oldHealth, humanoid.MaxHealth)
		end
	end

	description:Destroy()
	if oldDescription then
		oldDescription:Destroy()
	end

	applying[player] = nil

	if not success then
		warn("[AvatarEditorV14.3] ApplyDescription fallo para " .. player.Name .. ": " .. tostring(err))
		return false, tostring(err)
	end

	-- V9: después de ApplyDescriptionResetAsync Roblox ya creó los accessories reales.
	-- Ajustamos otra vez sus WrapLayers para evitar que el cuerpo se meta en la ropa 3D
	-- durante animaciones normales fuera del editor.
	for _, delayTime in ipairs({0, 0.15, 0.4, 1}) do
		task.delay(delayTime, function()
			if character and character.Parent then
				fixLiveWrapLayers(character)
			end
		end)
	end

	return true
end

--============================================================
-- V14 - RECONSTRUCCION LIMPIA DEL CHARACTER
--
-- ApplyDescriptionResetAsync modifica el mismo Character. Con cambios grandes
-- de cuerpo/bundle Roblox puede dejar durante la sesión piezas visuales viejas
-- o accesorios deformados. Al volver a entrar desaparecen porque el Character
-- nace desde cero.
--
-- V14 hace lo mismo SIN sacar al jugador del lugar:
-- crea un Character NUEVO con la HumanoidDescription final, lo coloca en el
-- mismo CFrame y destruye cualquier residuo perteneciente al Character viejo.
--============================================================

local function rebuildCharacterClean(player, description, reason)
	if applying[player] then
		return false, "busy"
	end

	local oldCharacter = player.Character
	if not oldCharacter or oldCharacter.Parent == nil then
		return false, "no_character"
	end

	local oldPivot = oldCharacter:GetPivot()
	local oldHumanoid = oldCharacter:FindFirstChildOfClass("Humanoid")
	local oldHealth = oldHumanoid and oldHumanoid.Health or nil
	local oldMaxHealth = oldHumanoid and oldHumanoid.MaxHealth or nil

	-- Snapshot de objetos del Character viejo. Solo se usan para limpiar
	-- residuos si Roblox llegara a reparentarlos fuera del modelo antiguo.
	local oldObjects = {}
	for _, object in ipairs(oldCharacter:GetDescendants()) do
		if object:IsA("BasePart")
			or object:IsA("Accessory")
			or object:IsA("Shirt")
			or object:IsA("Pants")
			or object:IsA("ShirtGraphic")
			or object:IsA("BodyColors") then
			table.insert(oldObjects, object)
		end
	end

	applying[player] = true
	player:SetAttribute("AvatarAppearanceReady", false)

	local success, err = pcall(function()
		player:LoadCharacterWithHumanoidDescriptionAsync(description)
	end)

	if not success then
		applying[player] = nil
		player:SetAttribute("AvatarAppearanceReady", true)
		return false, tostring(err)
	end

	local newCharacter = player.Character
	if not newCharacter or newCharacter == oldCharacter then
		applying[player] = nil
		player:SetAttribute("AvatarAppearanceReady", true)
		return false, "character_not_replaced"
	end

	local newRoot = newCharacter:WaitForChild("HumanoidRootPart", 10)
	local newHumanoid = newCharacter:FindFirstChildOfClass("Humanoid")
		or newCharacter:WaitForChild("Humanoid", 10)

	if newRoot and newCharacter.Parent then
		pcall(function()
			newCharacter:PivotTo(oldPivot)
		end)
	end

	if newHumanoid then
		if oldMaxHealth and oldMaxHealth > 0 then
			newHumanoid.MaxHealth = oldMaxHealth
		end
		if oldHealth and oldHealth > 0 then
			newHumanoid.Health = math.min(oldHealth, newHumanoid.MaxHealth)
		end
	end

	-- Si Roblox no destruyó el modelo anterior por alguna razón, lo hacemos.
	if oldCharacter
		and oldCharacter ~= newCharacter
		and oldCharacter.Parent then
		pcall(function()
			oldCharacter:Destroy()
		end)
	end

	-- Limpieza secundaria: cualquier pieza que pertenecía al Character viejo
	-- y haya quedado reparentada fuera del Character nuevo se elimina.
	task.delay(0.15, function()
		for _, object in ipairs(oldObjects) do
			if object
				and object.Parent
				and (not newCharacter or not object:IsDescendantOf(newCharacter)) then
				pcall(function()
					object:Destroy()
				end)
			end
		end
	end)

	applying[player] = nil
	return true
end

--============================================================
-- V14.3 - REBUILD LIMPIO PARA COSMETICOS
--
-- La evidencia del diagnóstico muestra que el Character real tiene
-- Transparency=0 y LTM=0, pero el render puede conservar una malla vieja
-- después de ApplyDescriptionResetAsync sobre el MISMO Character.
--
-- Para ropa/cabello/accesorios NO usamos ese método.
-- Esperamos 0.20 s para agrupar clics rápidos y reconstruimos una sola vez
-- con el mismo camino limpio que ya funciona al cambiar Avatar/Bundle.
--============================================================
local function scheduleCleanCosmeticRefresh(player, reason)
	local serial = (cosmeticRefreshSerial[player] or 0) + 1
	cosmeticRefreshSerial[player] = serial

	task.delay(COSMETIC_REFRESH_DELAY, function()
		if player.Parent ~= Players then
			return
		end

		if cosmeticRefreshSerial[player] ~= serial then
			return
		end

		-- Si justo se está aplicando un bundle/cuerpo, esperamos un poco.
		local deadline = os.clock() + 2.5
		while applying[player] and os.clock() < deadline do
			if cosmeticRefreshSerial[player] ~= serial then
				return
			end
			task.wait(0.03)
		end

		if cosmeticRefreshSerial[player] ~= serial then
			return
		end

		if applying[player] then
			warn("[AvatarEditorV14.3] Refresh cosmético cancelado por busy | " .. player.Name)
			return
		end

		local state = playerStates[player]
		if not state then
			return
		end

		local description = buildDescription(state)
		local ok, err = rebuildCharacterClean(
			player,
			description,
			"cosmeticos: " .. tostring(reason or "cambio")
		)
		description:Destroy()

		if not ok then
			warn(
				"[AvatarEditorV14.3] No pude reconstruir cosméticos | "
					.. player.Name
					.. " | "
					.. tostring(err)
			)
			return
		end

		fireState(player)
	end)
end

local function cancelPendingCosmeticRefresh(player)
	cosmeticRefreshSerial[player] = (cosmeticRefreshSerial[player] or 0) + 1
end

--============================================================
-- MANEJO DE ASSETS
--============================================================
local function assetTypeSlot(typeId)
	return SLOT_BY_ASSET_TYPE[tonumber(typeId)]
end

local function findAssetIndexById(state, id)
	for index, asset in ipairs(state.assets) do
		if tonumber(asset.id) == id then
			return index
		end
	end
	return nil
end

local function removeSameSlot(state, typeId)
	local targetSlot = assetTypeSlot(typeId)
	if not targetSlot then
		return
	end

	for i = #state.assets, 1, -1 do
		local asset = state.assets[i]
		local existingTypeId =
			type(asset.assetType) == "table"
			and tonumber(asset.assetType.id)
			or nil

		if existingTypeId and assetTypeSlot(existingTypeId) == targetSlot then
			table.remove(state.assets, i)
		end
	end
end

local function countRigidAccessories(state)
	local count = 0
	for _, asset in ipairs(state.assets) do
		local typeId =
			type(asset.assetType) == "table"
			and tonumber(asset.assetType.id)
			or nil
		if typeId and RIGID_PROPERTY_BY_TYPE[typeId] then
			count += 1
		end
	end
	return count
end

local function makeAssetEntry(id, name, typeId)
	local enumItem = avatarTypeById[typeId]
	return {
		id = id,
		name = tostring(name or ("Artículo " .. id)),
		assetType = {
			id = typeId,
			name = enumItem and enumItem.Name or tostring(typeId),
		},
	}
end

local function toggleAsset(player, id)
	id = tonumber(id)
	if not id or id <= 0 or bannedAssets[id] then
		return
	end

	local state = playerStates[player]
	if not state then
		return
	end

	local productInfo
	local ok, err = pcall(function()
		productInfo = MarketplaceService:GetProductInfoAsync(id, Enum.InfoType.Asset)
	end)
	if not ok or not productInfo then
		warn("[AvatarEditorV14.3] No pude leer asset " .. tostring(id) .. ": " .. tostring(err))
		return
	end

	local typeId = tonumber(productInfo.AssetTypeId)
	if not typeId or not ALLOWED_ASSET_TYPES[typeId] then
		warn("[AvatarEditorV14.3] Asset no admitido:", id, productInfo.AssetTypeId)
		return
	end

	local exactIndex = findAssetIndexById(state, id)
	local before = deepCopy(state)

	if exactIndex then
		-- Pulsar otra vez el mismo articulo lo quita.
		table.remove(state.assets, exactIndex)
	else
		-- V11: SIEMPRE quitamos el articulo anterior del mismo slot.
		-- Esto aplica tambien a Hat/Hair/FaceAccessory/etc.
		-- Resultado: nunca queda el accesorio viejo pegado al nuevo.
		removeSameSlot(state, typeId)

		if RIGID_PROPERTY_BY_TYPE[typeId] and countRigidAccessories(state) >= MAX_RIGID_ACCESSORIES then
			warn("[AvatarEditorV14.3] Limite de accesorios rigidos alcanzado para " .. player.Name)
			playerStates[player] = before
			return
		end

		table.insert(
			state.assets,
			makeAssetEntry(id, productInfo.Name, typeId)
		)
	end

	local BODY_GEOMETRY_TYPES = {
		[17] = true, -- Head
		[27] = true, -- Torso
		[28] = true, -- RightArm
		[29] = true, -- LeftArm
		[30] = true, -- LeftLeg
		[31] = true, -- RightLeg
		[79] = true, -- DynamicHead
	}

	if BODY_GEOMETRY_TYPES[typeId] then
		-- El V14 original ya hacía esto bien y no dejaba silueta.
		cancelPendingCosmeticRefresh(player)

		local description = buildDescription(state)
		local applied, applyErr = rebuildCharacterClean(
			player,
			description,
			"body asset " .. tostring(id)
		)
		description:Destroy()

		if not applied then
			playerStates[player] = before
			fireState(player)
			warn(
				"[AvatarEditorV14.3] No pude aplicar body asset "
					.. tostring(id)
					.. ": "
					.. tostring(applyErr)
			)
			return
		end

		fireState(player)
	else
		-- V14.3:
		-- NO usamos safeApplyState/ApplyDescriptionResetAsync en el Character vivo.
		-- Actualizamos el estado de la UI y hacemos UN rebuild limpio tras 0.20 s.
		fireState(player)
		scheduleCleanCosmeticRefresh(
			player,
			"asset=" .. tostring(id) .. " type=" .. tostring(typeId)
		)
	end
end

--============================================================
-- V13 - BUNDLES REALES POR USEROUTFIT
--
-- Los bundles de cuerpo de Roblox traen un item Type="UserOutfit".
-- Ese outfit contiene la descripción COMPLETA del cuerpo: partes,
-- escalas, proporciones y colores. V12 ignoraba UserOutfit y solo
-- copiaba algunos Asset del bundle, por eso al pasar de un cuerpo
-- grande a uno pequeño podían quedar proporciones/partes del anterior.
--============================================================

local BUNDLE_DESCRIPTION_PROPERTY_BY_TYPE = {
	[2] = "GraphicTShirt",
	[11] = "Shirt",
	[12] = "Pants",
	[17] = "Head",
	[79] = "Head",
	[18] = "Face",
	[27] = "Torso",
	[28] = "RightArm",
	[29] = "LeftArm",
	[30] = "LeftLeg",
	[31] = "RightLeg",
	[48] = "ClimbAnimation",
	[50] = "FallAnimation",
	[51] = "IdleAnimation",
	[52] = "JumpAnimation",
	[53] = "RunAnimation",
	[54] = "SwimAnimation",
	[55] = "WalkAnimation",
	[78] = "MoodAnimation",
}

local function findBundleOutfitId(details)
	for _, item in ipairs(details.Items or {}) do
		if tostring(item.Type) == "UserOutfit" then
			local id = tonumber(item.Id)
			if id and id > 0 then
				return id
			end
		end
	end
	return nil
end

local function colorToBrickNumber(color)
	local ok, brick = pcall(function()
		return BrickColor.new(color)
	end)
	if ok and brick then
		return brick.Number
	end
	return 194
end

local function resolveBundleItemTypeId(item)
	local byName = avatarTypeIdByName[tostring(item.AssetType or "")]
	if byName then
		return byName
	end

	local id = tonumber(item.Id)
	if not id then
		return nil
	end

	local info
	local ok = pcall(function()
		info = MarketplaceService:GetProductInfoAsync(id, Enum.InfoType.Asset)
	end)
	if ok and info then
		return tonumber(info.AssetTypeId)
	end

	return nil
end

local function copyDescriptionVisualStateIntoState(state, description, details)
	-- Conservamos únicamente animaciones elegidas aparte.
	local preservedAnimations = {}
	for _, asset in ipairs(state.assets or {}) do
		local typeId =
			type(asset.assetType) == "table"
			and tonumber(asset.assetType.id)
			or nil

		if typeId and ANIMATION_ASSET_TYPES[typeId] then
			table.insert(preservedAnimations, deepCopy(asset))
		end
	end

	state.assets = preservedAnimations

	-- El outfit oficial decide la forma real del cuerpo.
	state.scales.bodyType = description.BodyTypeScale
	state.scales.depth = description.DepthScale
	state.scales.head = description.HeadScale
	state.scales.height = description.HeightScale
	state.scales.proportion = description.ProportionScale
	state.scales.width = description.WidthScale

	state.bodyColors.headColorId = colorToBrickNumber(description.HeadColor)
	state.bodyColors.leftArmColorId = colorToBrickNumber(description.LeftArmColor)
	state.bodyColors.leftLegColorId = colorToBrickNumber(description.LeftLegColor)
	state.bodyColors.rightArmColorId = colorToBrickNumber(description.RightArmColor)
	state.bodyColors.rightLegColorId = colorToBrickNumber(description.RightLegColor)
	state.bodyColors.torsoColorId = colorToBrickNumber(description.TorsoColor)

	-- Guardamos todos los assets reales que Roblox reporta dentro del bundle.
	for _, item in ipairs(details.Items or {}) do
		if tostring(item.Type) == "Asset" then
			local id = tonumber(item.Id)
			local typeId = resolveBundleItemTypeId(item)

			if id and typeId and ALLOWED_ASSET_TYPES[typeId] then
				removeSameSlot(state, typeId)
				table.insert(state.assets, makeAssetEntry(id, item.Name, typeId))
			end
		end
	end

	-- Refuerzo: si el outfit trae propiedades visuales que no aparecieron
	-- bien tipadas en Items, las agregamos directamente desde HumanoidDescription.
	for typeId, propertyName in pairs(BUNDLE_DESCRIPTION_PROPERTY_BY_TYPE) do
		local value = tonumber(description[propertyName])
		if value and value > 0 and ALLOWED_ASSET_TYPES[typeId] then
			local alreadyThere = findAssetIndexById(state, value)
			if not alreadyThere then
				removeSameSlot(state, typeId)
				table.insert(
					state.assets,
					makeAssetEntry(value, "Bundle " .. propertyName, typeId)
				)
			end
		end
	end

	return normalizeState(state)
end

local function safeApplyExactDescription(player, description)
	if applying[player] then
		return false, "busy"
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false, "no_character"
	end

	applying[player] = true

	local oldDescription
	pcall(function()
		oldDescription = humanoid:GetAppliedDescription()
	end)

	local oldPivot = character:GetPivot()
	local oldHealth = humanoid.Health
	local oldMaxHealth = humanoid.MaxHealth
	local oldRequiresNeck = humanoid.RequiresNeck
	local oldAutoRotate = humanoid.AutoRotate

	humanoid.RequiresNeck = false

	local success, err = pcall(function()
		-- CLAVE V13:
		-- aplicamos directamente el HumanoidDescription oficial del UserOutfit.
		-- No reconstruimos el cuerpo a medias con assets sueltos.
		humanoid:ApplyDescriptionResetAsync(description)
	end)

	if not success and oldDescription then
		pcall(function()
			humanoid:ApplyDescriptionResetAsync(oldDescription)
		end)
	end

	if character.Parent then
		pcall(function()
			character:PivotTo(oldPivot)
		end)
	end

	if humanoid.Parent then
		humanoid.RequiresNeck = oldRequiresNeck
		humanoid.AutoRotate = oldAutoRotate
		humanoid.MaxHealth = oldMaxHealth
		if oldHealth > 0 and humanoid.Health > 0 then
			humanoid.Health = math.min(oldHealth, humanoid.MaxHealth)
		end
	end

	if oldDescription then
		oldDescription:Destroy()
	end

	applying[player] = nil

	if not success then
		return false, tostring(err)
	end

	for _, delayTime in ipairs({0, 0.15, 0.4, 1}) do
		task.delay(delayTime, function()
			if character and character.Parent and player.Character == character then
				fixLiveWrapLayers(character)
			end
		end)
	end

	return true
end

--============================================================
-- BUNDLES / AVATARES
--============================================================
local function applyBundle(player, bundleId)
	bundleId = tonumber(bundleId)
	if not bundleId or bundleId <= 0 then
		return
	end

	local state = playerStates[player]
	if not state then
		return
	end

	-- Un bundle ya hace su propio rebuild completo.
	cancelPendingCosmeticRefresh(player)

	local details
	local ok, err = pcall(function()
		details = AssetService:GetBundleDetailsAsync(bundleId)
	end)

	if not ok or type(details) ~= "table" then
		warn("[AvatarEditorV14.3] No pude leer bundle " .. tostring(bundleId) .. ": " .. tostring(err))
		return
	end

	local before = deepCopy(state)
	local outfitId = findBundleOutfitId(details)

	--========================================================
	-- V13 - RUTA PRINCIPAL: USEROUTFIT OFICIAL DEL BUNDLE
	--========================================================
	if outfitId then
		local outfitDescription
		local outfitOk, outfitErr = pcall(function()
			outfitDescription = Players:GetHumanoidDescriptionFromOutfitIdAsync(outfitId)
		end)

		if outfitOk and outfitDescription then
			local nextState = deepCopy(before)
			copyDescriptionVisualStateIntoState(nextState, outfitDescription, details)
			playerStates[player] = nextState

			local applied, applyErr = rebuildCharacterClean(
				player,
				outfitDescription,
				"bundle " .. tostring(bundleId) .. " / outfit " .. tostring(outfitId)
			)
			outfitDescription:Destroy()

			if not applied then
				playerStates[player] = before
				fireState(player)
				warn(
					"[AvatarEditorV14.3] Falló aplicar UserOutfit "
						.. tostring(outfitId)
						.. " del bundle "
						.. tostring(bundleId)
						.. ": "
						.. tostring(applyErr)
				)
				return
			end
			fireState(player)
			return
		else
			warn(
				"[AvatarEditorV14.3] No pude cargar UserOutfit "
					.. tostring(outfitId)
					.. ": "
					.. tostring(outfitErr)
			)
		end
	end

	--========================================================
	-- FALLBACK: bundles antiguos que no traen UserOutfit
	--========================================================
	local preservedAnimations = {}
	for _, asset in ipairs(state.assets) do
		local typeId =
			type(asset.assetType) == "table"
			and tonumber(asset.assetType.id)
			or nil

		if typeId and ANIMATION_ASSET_TYPES[typeId] then
			table.insert(preservedAnimations, deepCopy(asset))
		end
	end

	state.assets = preservedAnimations
	local added = 0

	for _, item in ipairs(details.Items or {}) do
		if tostring(item.Type) == "Asset" then
			local id = tonumber(item.Id)
			local typeId = resolveBundleItemTypeId(item)

			if id and typeId and ALLOWED_ASSET_TYPES[typeId] then
				removeSameSlot(state, typeId)

				if not RIGID_PROPERTY_BY_TYPE[typeId]
					or countRigidAccessories(state) < MAX_RIGID_ACCESSORIES then

					table.insert(state.assets, makeAssetEntry(id, item.Name, typeId))
					added += 1
				end
			end
		end
	end

	if added == 0 then
		playerStates[player] = before
		warn("[AvatarEditorV14.3] Bundle sin partes compatibles:", bundleId)
		fireState(player)
		return
	end

	local fallbackDescription = buildDescription(state)
	local applied, applyErr = rebuildCharacterClean(
		player,
		fallbackDescription,
		"bundle fallback " .. tostring(bundleId)
	)
	fallbackDescription:Destroy()

	if not applied then
		playerStates[player] = before
		fireState(player)
		warn(
			"[AvatarEditorV14.3] No se pudo aplicar fallback del bundle "
				.. tostring(bundleId)
				.. ": "
				.. tostring(applyErr)
		)
		return
	end
	fireState(player)
end

--============================================================
-- TONO DE PIEL Y ESCALAS
--============================================================
local function setSkinTone(player, colorName)
	if type(colorName) ~= "string" then
		return
	end

	local state = playerStates[player]
	if not state then
		return
	end

	local ok, brickColor = pcall(function()
		return BrickColor.new(colorName)
	end)
	if not ok or not brickColor then
		return
	end

	local before = deepCopy(state)

	state.bodyColors.headColorId = brickColor.Number
	state.bodyColors.leftArmColorId = brickColor.Number
	state.bodyColors.leftLegColorId = brickColor.Number
	state.bodyColors.rightArmColorId = brickColor.Number
	state.bodyColors.rightLegColorId = brickColor.Number
	state.bodyColors.torsoColorId = brickColor.Number

	if not safeApplyState(player, state) then
		playerStates[player] = before
	else
		fireState(player)
	end
end

local SCALE_NAME_TO_KEY = {
	BodyHeightScale = "height",
	BodyWidthScale = "width",
	HeadScale = "head",
	BodyProportionScale = "proportion",
	BodyTypeScale = "bodyType",
	BodyDepthScale = "depth",
}

local function setScale(player, scaleName, value)
	local key = SCALE_NAME_TO_KEY[scaleName]
	value = tonumber(value)
	if not key or not value then
		return
	end

	local state = playerStates[player]
	if not state then
		return
	end

	local minValue, maxValue = 0, 100
	if scaleName == "BodyHeightScale" then
		minValue, maxValue = 90, 105
	elseif scaleName == "BodyWidthScale" then
		minValue, maxValue = 70, 100
	elseif scaleName == "HeadScale" then
		minValue, maxValue = 95, 100
	end

	value = math.clamp(value, minValue, maxValue)

	local before = deepCopy(state)
	state.scales[key] = value / 100

	if not safeApplyState(player, state) then
		playerStates[player] = before
	else
		fireState(player)
	end
end

--============================================================
-- REMOTE
--============================================================
local function allowAction(player)
	local now = os.clock()
	local previous = lastActionAt[player] or 0
	if now - previous < MIN_ACTION_INTERVAL then
		return false
	end
	lastActionAt[player] = now
	return true
end

local function onServerEvent(player, action, ...)
	if action == "requestState" then
		fireState(player)
		return
	elseif action == "save" then
		task.spawn(saveAppearance, player, "cerrar armario")
		return
	end

	if not allowAction(player) then
		return
	end

	if action == "wear" then
		toggleAsset(player, ...)
	elseif action == "wearBundle" then
		applyBundle(player, ...)
	elseif action == "skintone" then
		setSkinTone(player, ...)
	elseif action == "scale" then
		setScale(player, ...)
	end
end

--============================================================
-- PLAYER LOAD / RESPAWN V10
--============================================================
local function getBaseAppearance(player)
	local info

	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return Players:GetCharacterAppearanceInfoAsync(player.UserId)
		end)

		if ok and result then
			info = result
			break
		end

		task.wait(0.4 * attempt)
	end

	return normalizeState(info)
end

local function scheduleRespawn(player)
	if respawnScheduled[player] then
		return
	end

	respawnScheduled[player] = true

	task.delay(Players.RespawnTime, function()
		respawnScheduled[player] = nil

		if player.Parent ~= Players then
			return
		end

		local state = playerStates[player]
		if not state then
			return
		end

		player:SetAttribute("AvatarAppearanceReady", false)

		local description = buildDescription(state)

		local ok, err = pcall(function()
			player:LoadCharacterWithHumanoidDescriptionAsync(description)
		end)

		description:Destroy()

		if not ok then
			warn(
				"[AvatarEditorV14.3] No se pudo reaparecer a "
					.. player.Name
					.. ": "
					.. tostring(err)
			)

			-- Fallback: por lo menos intenta crear el Character normal.
			pcall(function()
				player:LoadCharacterAsync()
			end)
		end
	end)
end

local function prepareSpawnedCharacter(player, character)
	if not character or player.Character ~= character then
		return
	end

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or player.Character ~= character then
		return
	end

	-- El Character ya nació con la apariencia final.
	-- Solo hacemos el post-fix de ropa 3D; NO volvemos a aplicar
	-- HumanoidDescription aquí, porque eso provocaría otro parpadeo.
	for _, delayTime in ipairs({0, 0.15, 0.4, 1}) do
		task.delay(delayTime, function()
			if character.Parent and player.Character == character then
				fixLiveWrapLayers(character)
			end
		end)
	end

	player:SetAttribute("AvatarAppearanceReady", true)
	fireState(player)

	humanoid.Died:Connect(function()
		if player.Character == character then
			player:SetAttribute("AvatarAppearanceReady", false)
			scheduleRespawn(player)
		end
	end)
end

local function spawnPlayerWithSavedAppearance(player)
	local state = playerStates[player]
	if not state or player.Parent ~= Players then
		return
	end

	player:SetAttribute("AvatarAppearanceReady", false)

	local description = buildDescription(state)

	local ok, err = pcall(function()
		player:LoadCharacterWithHumanoidDescriptionAsync(description)
	end)

	description:Destroy()

	if not ok then
		warn(
			"[AvatarEditorV14.3] LoadCharacterWithHumanoidDescriptionAsync falló para "
				.. player.Name
				.. ": "
				.. tostring(err)
		)

		-- Fallback seguro.
		local fallbackOk = pcall(function()
			player:LoadCharacterAsync()
		end)

		if not fallbackOk then
			player:SetAttribute("AvatarAppearanceReady", true)
		end
	end
end

local function playerAdded(player)
	player:SetAttribute("AvatarAppearanceReady", false)

	-- Primero cargamos TODO el estado del avatar.
	-- Mientras esto ocurre no existe un Character incompleto que luego
	-- tenga que ser reconstruido delante del jugador.
	local baseInfo = getBaseAppearance(player)
	local saved = loadSavedAppearance(player)
	local state = mergeSavedAppearance(baseInfo, saved)

	playerStates[player] = state

	player.CharacterAdded:Connect(function(character)
		task.defer(function()
			prepareSpawnedCharacter(player, character)
		end)
	end)

	-- En condiciones normales CharacterAutoLoads=false significa que
	-- todavía no existe Character. Si Studio ya había creado uno por una
	-- recarga de scripts, lo reemplazamos por uno con la apariencia final.
	if player.Parent == Players then
		spawnPlayerWithSavedAppearance(player)
	end
end

local function playerRemoving(player)
	saveAppearance(player, "salir del juego")
	playerStates[player] = nil
	applying[player] = nil
	saveInProgress[player] = nil
	lastActionAt[player] = nil
	respawnScheduled[player] = nil
	cosmeticRefreshSerial[player] = nil
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(playerAdded, player)
end

Players.PlayerAdded:Connect(playerAdded)
Players.PlayerRemoving:Connect(playerRemoving)
remoteEvent.OnServerEvent:Connect(onServerEvent)

game:BindToClose(function()
	local pending = 0
	for _, player in ipairs(Players:GetPlayers()) do
		pending += 1
		task.spawn(function()
			saveAppearance(player, "cierre del servidor")
			pending -= 1
		end)
	end

	local start = os.clock()
	while pending > 0 and os.clock() - start < 8 do
		task.wait(0.05)
	end
end)