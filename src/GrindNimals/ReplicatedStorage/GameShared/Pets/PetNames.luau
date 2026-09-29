--============================================================
-- PetNames V2
-- Tipo: ModuleScript
-- Ubicacion:
-- ReplicatedStorage > GameShared > Pets > PetNames
--
-- Centraliza TODOS los alias de nombres.
-- Reemplaza el PetNames de la Fase 1 por este.
--============================================================

local PetNames = {}

PetNames.EGG_NAME = "Huevo Mascota"

-- Nombre canonico usado por inventario/UI.
PetNames.CanonicalAliases = {
	["Pajarillo"] = "Perico",
	["PezDorado"] = "Pez dorado",
	["Oveja de rosario"] = "Oveja",
	["HuevoBrizabelle"] = "Huevo Mascota",
}

-- Nombre del modelo/configuracion base.
PetNames.ModelAliases = {
	["Pajarillo"] = "Perico",
	["Pez dorado"] = "PezDorado",
	["Oveja de rosario"] = "Oveja",
	["Huevo Mascota"] = "HuevoBrizabelle",
}

function PetNames.Normalize(value)
	local text = tostring(value or ""):lower()
	text = text:gsub("á", "a")
	text = text:gsub("é", "e")
	text = text:gsub("í", "i")
	text = text:gsub("ó", "o")
	text = text:gsub("ú", "u")
	text = text:gsub("ñ", "n")
	text = text:gsub("[%s_%-]+", "")
	return text
end

function PetNames.Canonical(name)
	name = tostring(name or "")
	return PetNames.CanonicalAliases[name] or name
end

-- Compatibilidad con el nombre usado en la Fase 1.
function PetNames.ToStoredName(name)
	return PetNames.Canonical(name)
end

function PetNames.ToModelName(name)
	name = tostring(name or "")
	return PetNames.ModelAliases[name] or PetNames.ModelAliases[PetNames.Canonical(name)] or PetNames.Canonical(name)
end

function PetNames.IsSheepName(value)
	return PetNames.Normalize(value):find("oveja", 1, true) ~= nil
end

function PetNames.NamesMatch(a, b)
	return PetNames.Normalize(a) == PetNames.Normalize(b)
		or (PetNames.IsSheepName(a) and PetNames.IsSheepName(b))
end

return PetNames
