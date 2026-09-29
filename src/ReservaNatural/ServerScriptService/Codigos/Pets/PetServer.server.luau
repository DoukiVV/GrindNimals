--============================================================
-- PetServer V2 ORGANIZADO
-- Tipo: Script
-- Ubicacion:
-- ServerScriptService > PetServer
--
-- REEMPLAZA el PetServer anterior.
--
-- Ahora PetServer es solo el punto de arranque.
-- Toda la logica vive en:
-- ServerScriptService > PetSystem > Services > PetSpawnService
--============================================================

local ServerScriptService =
	game:GetService("ServerScriptService")

local PetSpawnService =
	require(
		ServerScriptService
		:WaitForChild("PetSystem")
		:WaitForChild("Services")
		:WaitForChild("PetSpawnService")
	)

PetSpawnService.Start()