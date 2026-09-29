-- FruitInventorySaveServer V4.4 - BOOTSTRAP
-- Ubicacion: ServerScriptService > FruitInventorySaveServer
-- Tipo: Script

local ServerScriptService = game:GetService("ServerScriptService")

local service = require(
	ServerScriptService
		:WaitForChild("Systems")
		:WaitForChild("Inventory")
		:WaitForChild("Services")
		:WaitForChild("FruitInventoryService")
)

service.Start()
