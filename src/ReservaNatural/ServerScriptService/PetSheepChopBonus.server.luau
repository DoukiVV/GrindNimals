--============================================================
-- PET SHEEP CHOP BONUS V2.1
--
-- UBICACION:
-- ServerScriptService > PetSheepChopBonus
-- TIPO: ModuleScript
--
-- HABILIDAD ESPECIAL UNICA:
-- SOLO la Oveja aumenta la velocidad de tala y SOLAMENTE
-- mientras la Oveja real esta afuera.
--
-- MULTIPLICADORES:
-- Base / sin pañuelo  x1.00
-- Blanco/Gris         x1.50
-- Verde               x1.75
-- Azul                x2.00
-- Morado              x2.25
-- Dorado              x2.50
--
-- Cualquier otra mascota = x1.00
--============================================================

local Workspace = game:GetService("Workspace")

local PetSheepChopBonus = {}

local SHEEP_MULTIPLIER_BY_TIER = {
	Base = 1.00,
	Comun = 1.50,
	["Poco comun"] = 1.75,
	Raro = 2.00,
	Epico = 2.25,
	Legendario = 2.50,
}

local activePetByUserId = {}

local function normalize(value)
	local text = tostring(value or ""):lower()

	text = text
		:gsub("á", "a")
		:gsub("é", "e")
		:gsub("í", "i")
		:gsub("ó", "o")
		:gsub("ú", "u")
		:gsub("ü", "u")
		:gsub("ñ", "n")

	text = text:gsub("[%s_%-%./]+", "")

	return text
end

local function canonicalTier(value)
	local key = normalize(value)

	if key == "" or key == "base" then
		return "Base"
	elseif key == "comun"
		or key == "gris"
		or key == "blanco"
	then
		return "Comun"
	elseif key == "pococomun"
		or key == "verde"
	then
		return "Poco comun"
	elseif key == "raro"
		or key == "azul"
	then
		return "Raro"
	elseif key == "epico"
		or key == "morado"
	then
		return "Epico"
	elseif key == "legendario"
		or key == "dorado"
	then
		return "Legendario"
	end

	return "Base"
end

local function isSheepName(value)
	local key = normalize(value)

	return key == "oveja"
		or key == "ovejaderosario"
end

local function isRealActivePet(model)
	if not model or not model:IsA("Model") then
		return false
	end

	local owner = model:GetAttribute("Owner")
	local petType = model:GetAttribute("PetType")

	if typeof(owner) ~= "number" then
		return false
	end

	if typeof(petType) ~= "string" or petType == "" then
		return false
	end

	if model:GetAttribute("ClientPetVisual") == true then
		return false
	end

	if model:GetAttribute("Resting") == true then
		return false
	end

	return true
end

local function registerPet(model)
	if not isRealActivePet(model) then
		return
	end

	local owner = model:GetAttribute("Owner")
	activePetByUserId[owner] = model
end

local function unregisterPet(model)
	if not model or not model:IsA("Model") then
		return
	end

	local owner = model:GetAttribute("Owner")

	if typeof(owner) == "number"
		and activePetByUserId[owner] == model
	then
		activePetByUserId[owner] = nil
	end
end

for _, object in ipairs(Workspace:GetChildren()) do
	registerPet(object)
end

Workspace.ChildAdded:Connect(function(object)
	registerPet(object)
end)

Workspace.ChildRemoved:Connect(function(object)
	unregisterPet(object)
end)

local function getActivePet(player)
	if not player then
		return nil
	end

	local pet = activePetByUserId[player.UserId]

	if not pet
		or pet.Parent ~= Workspace
		or not isRealActivePet(pet)
	then
		activePetByUserId[player.UserId] = nil
		return nil
	end

	return pet
end

function PetSheepChopBonus.GetInfo(player)
	local pet = getActivePet(player)

	if not pet then
		return {
			active = false,
			isSheep = false,
			petName = "",
			tier = "Base",
			multiplier = 1.00,
		}
	end

	local petName = tostring(
		pet:GetAttribute("PetType")
			or pet.Name
	)

	local rawTier =
		pet:GetAttribute("UpgradeTier")
		or pet:GetAttribute("PetTier")
		or pet:GetAttribute("Tier")
		or pet:GetAttribute("Rarity")
		or pet:GetAttribute("Rareza")
		or "Base"

	local tier = canonicalTier(rawTier)
	local isSheep = isSheepName(petName)

	if not isSheep then
		return {
			active = true,
			isSheep = false,
			petName = petName,
			tier = tier,
			multiplier = 1.00,
		}
	end

	return {
		active = true,
		isSheep = true,
		petName = petName,
		tier = tier,
		multiplier =
			SHEEP_MULTIPLIER_BY_TIER[tier]
			or 1.00,
	}
end

function PetSheepChopBonus.GetMultiplier(player)
	return PetSheepChopBonus.GetInfo(player).multiplier
end

return PetSheepChopBonus
