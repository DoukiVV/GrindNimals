--============================================================
-- SHARED INVENTORY WORLD CHECK V1
-- Ubicacion: ServerScriptService > SharedInventoryWorldCheck
-- Tipo: Script
--
-- Copia ESTE MISMO script a Lobby, CasaJugadores, Bosque, etc.
-- Todos deben imprimir el MISMO GameId.
-- PlaceId debe ser diferente en cada mundo.
--============================================================

local ServerStorage = game:GetService("ServerStorage")

local item = ServerStorage:FindFirstChild("Item")
local seeds = item and item:FindFirstChild("Semillas")
local fruits = item and item:FindFirstChild("Frutas")

local function countTools(folder)
	if not folder then
		return 0
	end

	local count = 0

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Tool") then
			count += 1
		end
	end

	return count
end