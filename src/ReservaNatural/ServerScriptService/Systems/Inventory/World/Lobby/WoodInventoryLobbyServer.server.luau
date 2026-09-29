-- WoodInventoryLobbyServer V3 - BOOTSTRAP
-- Ubicacion: ServerScriptService > WoodInventoryLobbyServer
-- Tipo: Script
-- SOLO LOBBY

local ServerScriptService = game:GetService("ServerScriptService")

local service = require(
	ServerScriptService
		:WaitForChild("Systems")
		:WaitForChild("Inventory")
		:WaitForChild("World")
		:WaitForChild("Lobby")
		:WaitForChild("WoodInventoryLobbyService")
)

service.Start()
