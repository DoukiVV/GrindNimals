-- SeedInventorySaveServer V10 - BOOTSTRAP
-- Ubicacion: ServerScriptService > SeedInventorySaveServer
-- Tipo: Script

local ServerScriptService = game:GetService("ServerScriptService")

local service = require(
	ServerScriptService
		:WaitForChild("Systems")
		:WaitForChild("Inventory")
		:WaitForChild("Services")
		:WaitForChild("SeedInventoryService")
)

service.Start()
