--============================================================
-- LOBBY SEED TOOL CLEANER V1
--
-- UBICACION:
-- ServerScriptService > LobbySeedToolCleaner
-- TIPO: Script
--
-- SOLO PARA EL LOBBY.
--
-- PROBLEMA QUE CORRIGE:
-- SemillaManzana.LocalScript intenta encontrar:
-- Workspace.CultivarTerreno
--
-- El Lobby NO tiene terreno para plantar, asi que ese LocalScript
-- no debe ejecutarse aqui.
--
-- Este script elimina SOLO LocalScripts/Scripts dentro de las
-- Tools de semillas en el Lobby.
--
-- NO elimina las semillas ni cambia sus stacks/atributos.
--============================================================

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local itemFolder =
	ServerStorage:WaitForChild("Item")

local seedFolder =
	itemFolder:WaitForChild("Semillas")

local function cleanTool(tool)
	if not tool
		or not tool:IsA("Tool")
	then
		return
	end

	for _, object in ipairs(
		tool:GetDescendants()
		) do
		if object:IsA("LocalScript")
			or object:IsA("Script")
		then
			object:Destroy()
		end
	end
end

-- Limpiar plantillas del Lobby.
for _, object in ipairs(
	seedFolder:GetDescendants()
	) do
	if object:IsA("Tool") then
		cleanTool(object)
	end
end

seedFolder.DescendantAdded:Connect(
	function(object)
		if object:IsA("Tool") then
			task.defer(
				cleanTool,
				object
			)
		end
	end
)

local function watchContainer(container)
	if not container then
		return
	end

	for _, child in ipairs(
		container:GetChildren()
		) do
		if child:IsA("Tool")
			and child:GetAttribute("IsSeed") == true
		then
			cleanTool(child)
		end
	end

	container.ChildAdded:Connect(
		function(child)
			if child:IsA("Tool")
				and (
					child:GetAttribute("IsSeed") == true
						or child:GetAttribute("SeedCropName") ~= nil
				)
			then
				task.defer(
					cleanTool,
					child
				)
			end
		end
	)
end

local function setupPlayer(player)
	local backpack =
		player:WaitForChild(
			"Backpack"
		)

	watchContainer(
		backpack
	)

	player.CharacterAdded:Connect(
		function(character)
			watchContainer(
				character
			)
		end
	)

	player.ChildAdded:Connect(
		function(child)
			if child:IsA("Backpack") then
				watchContainer(
					child
				)
			end
		end
	)
end

for _, player in ipairs(
	Players:GetPlayers()
	) do
	task.spawn(
		setupPlayer,
		player
	)
end

Players.PlayerAdded:Connect(
	function(player)
		task.spawn(
			setupPlayer,
			player
		)
	end
)