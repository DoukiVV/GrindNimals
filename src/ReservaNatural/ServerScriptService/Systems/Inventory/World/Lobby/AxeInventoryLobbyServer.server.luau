-- AxeInventoryLobbyServer V2 - BOOTSTRAP
-- Ubicacion: ServerScriptService > AxeInventoryLobbyServer
-- Tipo: Script
-- SOLO LOBBY

local ServerScriptService = game:GetService("ServerScriptService")

local service = require(
	ServerScriptService
		:WaitForChild("Systems")
		:WaitForChild("Inventory")
		:WaitForChild("World")
		:WaitForChild("Lobby")
		:WaitForChild("AxeInventoryLobbyService")
)

service.Start()
