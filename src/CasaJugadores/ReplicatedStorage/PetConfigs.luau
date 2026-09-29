--============================================================
-- PetConfigs COMPATIBILITY WRAPPER
-- Tipo: ModuleScript
-- Ubicacion:
-- ReplicatedStorage > PetConfigs
--
-- ESTE ARCHIVO CONSERVA LA RUTA ANTIGUA:
-- require(ReplicatedStorage:WaitForChild("PetConfigs"))
--
-- Asi NO tienes que modificar PetRenderer, PetMenuHotkeyClient,
-- BrizabelleEggServer ni otros scripts todavia.
--============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return require(
	ReplicatedStorage
		:WaitForChild("GameShared")
		:WaitForChild("Pets")
		:WaitForChild("PetConfigs")
)
