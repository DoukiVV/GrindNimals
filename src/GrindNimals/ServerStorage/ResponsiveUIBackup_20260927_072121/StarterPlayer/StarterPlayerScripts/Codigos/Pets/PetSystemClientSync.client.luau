--============================================================
-- PetSystemClientSync V2 ORGANIZADO
-- Tipo: LocalScript
-- Ubicacion:
-- StarterPlayer > StarterPlayerScripts > PetSystemClientSync
--
-- REEMPLAZA el PetSystemClientSync anterior de ~733 lineas.
--
-- Ahora este archivo SOLO inicia controllers.
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local playerScripts = player:WaitForChild("PlayerScripts")

--============================================================
-- SINGLETON
--============================================================

local markerName = "PetSystemClientSyncSingleton"
local oldMarker = playerGui:FindFirstChild(markerName)

if oldMarker then
	warn("[PetSystemClientSync] Ya existe una instancia activa. Esta copia no iniciara.")
	return
end

local marker = Instance.new("Folder")
marker.Name = markerName
marker.Parent = playerGui

--============================================================
-- DESACTIVAR RENDERER VIEJO DEL SLOT 2
--============================================================

local function disableOldSelectionRenderer(instance)
	if instance == script or not instance:IsA("LocalScript") then
		return
	end

	local lowerName = instance.Name:lower()

	if lowerName == "petselectionsyncclient" then
		instance.Disabled = true
	end
end

for _, instance in ipairs(playerScripts:GetDescendants()) do
	disableOldSelectionRenderer(instance)
end

playerScripts.DescendantAdded:Connect(function(instance)
	task.defer(function()
		if instance.Parent then
			disableOldSelectionRenderer(instance)
		end
	end)
end)

--============================================================
-- CONTROLLERS
--============================================================

local clientFolder = ReplicatedStorage
	:WaitForChild("GameShared")
	:WaitForChild("Pets")
	:WaitForChild("Client")

local PetSlot2Controller =
	require(clientFolder:WaitForChild("PetSlot2Controller"))

local PetFrankViewportController =
	require(clientFolder:WaitForChild("PetFrankViewportController"))

PetSlot2Controller.Start()
PetFrankViewportController.Start()