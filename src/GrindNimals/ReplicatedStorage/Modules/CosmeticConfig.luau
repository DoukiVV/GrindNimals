--!strict
--============================================================
-- ReplicatedStorage > Modules > CosmeticConfig (ModuleScript)
--============================================================
-- Tabla central de configuracion del sistema de cosmetica estilo Brookhaven.
-- Solo Ropa/Accesorios: no incluye escalas de cuerpo ni forma del personaje.
--
-- Para agregar items al catalogo rapido, agrega entradas dentro de "Items"
-- de la categoria correspondiente: { Id = 123456, Name = "Nombre visible" }.
--============================================================

export type CosmeticItem = {
	Id: number,
	Name: string,
}

export type CategoryId = "Hair" | "Hats" | "Face" | "Back" | "Shirts" | "Pants" | "Faces"

export type CategoryKind = "Accessory" | "Shirt" | "Pants" | "FaceDecal"

export type CategoryConfig = {
	Id: CategoryId,
	Title: string,
	Kind: CategoryKind,
	AccessoryTypeName: string?, -- Enum.AccessoryType name, solo si Kind == "Accessory"
	AllowMultiple: boolean,     -- true = se pueden llevar varios sin reemplazar el anterior
	ValidAssetTypeNames: { string }, -- nombres validos de Enum.AssetType para GetProductInfo
	Items: { CosmeticItem },
}

local Config = {}

-- Limites de seguridad para evitar spam / lag en el servidor.
Config.MaxAccessoriesPerCategory = 6
Config.MaxTotalAccessories = 24

-- Si true, el outfit se guarda en DataStore y se restaura al reconectar.
Config.SaveBetweenSessions = true
Config.DataStoreName = "CosmeticOutfitV1"

Config.Categories = {
	{
		Id = "Hair",
		Title = "Cabello",
		Kind = "Accessory",
		AccessoryTypeName = "Hair",
		AllowMultiple = false,
		ValidAssetTypeNames = { "HairAccessory" },
		Items = {},
	},
	{
		Id = "Hats",
		Title = "Sombreros",
		Kind = "Accessory",
		AccessoryTypeName = "Hat",
		AllowMultiple = true, -- Brookhaven permite apilar varios sombreros/gorras
		ValidAssetTypeNames = { "Hat" },
		Items = {},
	},
	{
		Id = "Face",
		Title = "Lentes / Rostro",
		Kind = "Accessory",
		AccessoryTypeName = "Face",
		AllowMultiple = true,
		ValidAssetTypeNames = { "FaceAccessory" },
		Items = {},
	},
	{
		Id = "Back",
		Title = "Espalda",
		Kind = "Accessory",
		AccessoryTypeName = "Back",
		AllowMultiple = true,
		ValidAssetTypeNames = { "BackAccessory" },
		Items = {},
	},
	{
		Id = "Shirts",
		Title = "Camisas",
		Kind = "Shirt",
		AllowMultiple = false, -- Roblox solo permite 1 camisa puesta a la vez
		ValidAssetTypeNames = { "Shirt" },
		Items = {},
	},
	{
		Id = "Pants",
		Title = "Pantalones",
		Kind = "Pants",
		AllowMultiple = false,
		ValidAssetTypeNames = { "Pants" },
		Items = {},
	},
	{
		Id = "Faces",
		Title = "Caras",
		Kind = "FaceDecal",
		AllowMultiple = false,
		ValidAssetTypeNames = { "Face" },
		Items = {},
	},
} :: { CategoryConfig }

Config.CategoryById = {} :: { [string]: CategoryConfig }
for _, category in ipairs(Config.Categories) do
	Config.CategoryById[category.Id] = category
end

return Config