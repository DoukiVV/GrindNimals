--============================================================
-- AxeInventoryLobbyService - ORGANIZADO
-- Tipo: ModuleScript
--
-- Este modulo conserva la logica del script original.
-- Se inicia desde un bootstrap pequeno en ServerScriptService.
--============================================================

local AxeInventoryLobbyService = {}
local started = false

function AxeInventoryLobbyService.Start()
	if started then
		return
	end
	started = true

	--============================================================
	-- AXE INVENTORY LOBBY V1
	--
	-- UBICACION:
	-- ServerScriptService > AxeInventoryLobbyServer
	--
	-- OBJETIVO:
	-- Cargar en el LOBBY las mismas hachas compradas en el Bosque.
	--
	-- IMPORTANTE:
	-- - Usa el MISMO DataStore de Lex:
	--     LexAxeStacksV1
	-- - NO necesita que exista el NPC Lex en el Lobby.
	-- - NO crea tienda.
	-- - NO modifica las cantidades guardadas.
	-- - Solo restaura los stacks fisicos maximo x99.
	--
	-- NECESITA:
	-- ReplicatedStorage > Hachas
	-- con las mismas plantillas del Bosque.
	--============================================================

	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local DataStoreService = game:GetService("DataStoreService")

	local STACK_DATASTORE_NAME = "LexAxeStacksV1"
	local OLD_DATASTORE_NAME = "LexOwnedAxesV1"

	local STACK_LIMIT = 99
	local MAX_TOTAL_PER_AXE = 9999

	local AXES = {
		Wood = {
			DisplayName = "Hacha de madera",
			TemplateName = "Hacha de Madera",
		},
		Copper = {
			DisplayName = "Hacha de cobre",
			TemplateName = "Hacha de Cobre",
		},
		Iron = {
			DisplayName = "Hacha de Hierro",
			TemplateName = "Hacha de Hierro",
		},
		Crystal = {
			DisplayName = "Hacha de cristal turbio",
			TemplateName = "Hacha de Cristal",
		},
		Quartz = {
			DisplayName = "Hacha de cuarzo",
			TemplateName = "Hacha de Cuarzo",
		},
		Hematite = {
			DisplayName = "Hacha de Hematita",
			TemplateName = "Hacha de Hematita",
		},
		Obsidian = {
			DisplayName = "Hacha de obsidiana",
			TemplateName = "Hacha de Obsidiana",
		},
		Serpentine = {
			DisplayName = "Hacha de serpentina",
			TemplateName = "Hacha de Serpentina",
		},
	}

	local AXE_ORDER = {
		"Wood",
		"Copper",
		"Iron",
		"Crystal",
		"Quartz",
		"Hematite",
		"Obsidian",
		"Serpentine",
	}

	local stackStore =
		DataStoreService:GetDataStore(
			STACK_DATASTORE_NAME
		)

	local oldStore =
		DataStoreService:GetDataStore(
			OLD_DATASTORE_NAME
		)

	local countCache = {}
	local loadedPlayers = {}
	local syncingPlayers = {}

	--============================================================
	-- HACHAS
	--============================================================

	local axeFolder =
		ReplicatedStorage:FindFirstChild(
			"Hachas"
		)

	if
		not axeFolder
		or not axeFolder:IsA("Folder")
	then
		error(
			"[AxeLobby] Falta ReplicatedStorage > Hachas. "
				.. "Copia la carpeta Hachas completa desde el Bosque al Lobby."
		)
	end

	local function normalizeName(text)
		text = tostring(text or "")

		local replacements = {
			["á"] = "a",
			["é"] = "e",
			["í"] = "i",
			["ó"] = "o",
			["ú"] = "u",
			["Á"] = "a",
			["É"] = "e",
			["Í"] = "i",
			["Ó"] = "o",
			["Ú"] = "u",
			["ñ"] = "n",
			["Ñ"] = "n",
		}

		for old, new in pairs(
			replacements
			) do
			text =
				text:gsub(
					old,
					new
				)
		end

		text = text:lower()
		text = text:gsub("%s+", "")
		text = text:gsub("[_%-%.,]", "")

		return text
	end

	local function clampAmount(value)
		return math.clamp(
			math.floor(
				tonumber(value)
					or 0
			),
			0,
			MAX_TOTAL_PER_AXE
		)
	end

	local function findAxeTemplate(
		templateName
	)
		local exact =
			axeFolder:FindFirstChild(
				templateName
			)

		if exact then
			return exact
		end

		local wanted =
			normalizeName(
				templateName
			)

		for _, object in ipairs(
			axeFolder:GetChildren()
			) do
			if
				normalizeName(
					object.Name
				) == wanted
			then
				return object
			end
		end

		return nil
	end

	local function getAxeIdForTool(
		tool
	)
		if
			not tool
			or not tool:IsA("Tool")
		then
			return nil
		end

		local attr =
			tool:GetAttribute(
				"AxeId"
			)

		if
			typeof(attr) == "string"
			and AXES[attr]
		then
			return attr
		end

		local normalized =
			normalizeName(
				tool.Name
			)

		for axeId, data in pairs(
			AXES
			) do
			local template =
				findAxeTemplate(
					data.TemplateName
				)

			local templateName =
				template
				and template.Name
				or data.TemplateName

			if
				normalizeName(
					templateName
				) == normalized
			then
				return axeId
			end
		end

		return nil
	end

	local function applyAxeAttributes(
		tool,
		axeId,
		amount
	)
		local data =
			AXES[axeId]

		if not data then
			return
		end

		amount =
			math.clamp(
				math.floor(
					tonumber(amount)
					or 1
				),
				1,
				STACK_LIMIT
			)

		tool:SetAttribute(
			"LexAxeManaged",
			true
		)

		tool:SetAttribute(
			"IsAxe",
			true
		)

		tool:SetAttribute(
			"AxeId",
			axeId
		)

		tool:SetAttribute(
			"AxeStackQuantity",
			amount
		)

		tool:SetAttribute(
			"Cantidad",
			amount
		)

		tool:SetAttribute(
			"ItemType",
			"Tool"
		)

		tool:SetAttribute(
			"ItemName",
			data.DisplayName
		)

		tool:SetAttribute(
			"BackpackDisplayName",
			data.DisplayName
		)

		tool.CanBeDropped =
			false
	end

	--============================================================
	-- DATASTORE
	--============================================================

	local function sanitizeCounts(raw)
		local source =
			typeof(raw) == "table"
			and (
				typeof(raw.Counts) == "table"
				and raw.Counts
				or raw
			)
			or {}

		local result = {}

		for axeId in pairs(
			AXES
			) do
			local value =
				source[axeId]

			if value == true then
				result[axeId] =
					1
			else
				local amount =
					clampAmount(
						value
					)

				if amount > 0 then
					result[axeId] =
						amount
				end
			end
		end

		return result
	end

	local function loadCounts(
		player
	)
		if loadedPlayers[player] then
			return
		end

		local key =
			"Player_"
			.. tostring(
				player.UserId
			)

		local counts = {}

		local successNew, rawNew =
			pcall(function()
				return stackStore:GetAsync(
					key
				)
			end)

		if
			successNew
			and typeof(rawNew) == "table"
		then
			counts =
				sanitizeCounts(
					rawNew
				)
		elseif not successNew then
			warn(
				"[AxeLobby] Error leyendo LexAxeStacksV1:",
				player.Name,
				rawNew
			)
		end

		-- Compatibilidad con datos viejos V3.
		if next(counts) == nil then
			local successOld, rawOld =
				pcall(function()
					return oldStore:GetAsync(
						key
					)
				end)

			if
				successOld
				and typeof(rawOld) == "table"
			then
				for axeId, owned in pairs(
					rawOld
					) do
					if
						AXES[axeId]
						and owned == true
					then
						counts[axeId] =
							1
					end
				end
			elseif not successOld then
				warn(
					"[AxeLobby] Error leyendo LexOwnedAxesV1:",
					player.Name,
					rawOld
				)
			end
		end

		countCache[player] =
			counts

		loadedPlayers[player] =
			true

		local total = 0

		for _, amount in pairs(
			counts
			) do
			total +=
				clampAmount(
					amount
				)
		end
	end

	--============================================================
	-- STACKS FISICOS
	--============================================================

	local function clearStarterGearAxes(
		player,
		axeId
	)
		local starterGear =
			player:FindFirstChild(
				"StarterGear"
			)

		if not starterGear then
			return
		end

		for _, child in ipairs(
			starterGear:GetChildren()
			) do
			if
				child:IsA("Tool")
				and getAxeIdForTool(
					child
				) == axeId
			then
				child:Destroy()
			end
		end
	end

	local function collectPlayerAxeTools(
		player,
		axeId
	)
		local tools = {}

		local function add(
			container
		)
			if not container then
				return
			end

			for _, child in ipairs(
				container:GetChildren()
				) do
				if
					child:IsA("Tool")
					and getAxeIdForTool(
						child
					) == axeId
				then
					table.insert(
						tools,
						child
					)
				end
			end
		end

		add(
			player.Character
		)

		add(
			player:FindFirstChildOfClass(
				"Backpack"
			)
		)

		return tools
	end

	local function syncAxeStacks(
		player,
		axeId
	)
		local data =
			AXES[axeId]

		if not data then
			return
		end

		local backpack =
			player:FindFirstChildOfClass(
				"Backpack"
			)

		if not backpack then
			return
		end

		local template =
			findAxeTemplate(
				data.TemplateName
			)

		if
			not template
			or not template:IsA("Tool")
		then
			warn(
				"[AxeLobby] Falta Tool:",
				data.TemplateName
			)

			return
		end

		local counts =
			countCache[player]
			or {}

		local target =
			clampAmount(
				counts[axeId]
			)

		local existing =
			collectPlayerAxeTools(
				player,
				axeId
			)

		local needed =
			target > 0
			and math.ceil(
				target
				/ STACK_LIMIT
			)
			or 0

		for index = 1, needed do
			local amount =
				math.min(
					STACK_LIMIT,
					target
					- (
						(index - 1)
						* STACK_LIMIT
					)
				)

			local tool =
				existing[index]

			if
				not tool
				or not tool.Parent
			then
				tool =
					template:Clone()

				tool.Parent =
					backpack
			end

			applyAxeAttributes(
				tool,
				axeId,
				amount
			)
		end

		for index =
			needed + 1,
			#existing
		do
			local tool =
				existing[index]

			if
				tool
				and tool.Parent
			then
				tool:Destroy()
			end
		end

		clearStarterGearAxes(
			player,
			axeId
		)
	end

	local function syncAllAxeStacks(
		player
	)
		if syncingPlayers[player] then
			return
		end

		if not loadedPlayers[player] then
			return
		end

		local backpack =
			player:FindFirstChildOfClass(
				"Backpack"
			)

		if not backpack then
			return
		end

		syncingPlayers[player] =
			true

		for _, axeId in ipairs(
			AXE_ORDER
			) do
			syncAxeStacks(
				player,
				axeId
			)
		end

		syncingPlayers[player] =
			nil
	end

	local function scheduleSync(
		player,
		delayTime
	)
		task.delay(
			delayTime
				or 0.35,
			function()
				if
					player.Parent
					== Players
				then
					syncAllAxeStacks(
						player
					)
				end
			end
		)
	end

	--============================================================
	-- JUGADORES
	--============================================================

	local function setupPlayer(
		player
	)
		task.spawn(function()
			loadCounts(
				player
			)

			player:WaitForChild(
				"Backpack"
			)

			scheduleSync(
				player,
				0.45
			)
		end)

		player.CharacterAdded:Connect(
			function()
				scheduleSync(
					player,
					0.60
				)
			end
		)

		player.ChildAdded:Connect(
			function(child)
				if child:IsA("Backpack") then
					scheduleSync(
						player,
						0.25
					)
				end
			end
		)
	end

	for _, player in ipairs(
		Players:GetPlayers()
		) do
		setupPlayer(
			player
		)
	end

	Players.PlayerAdded:Connect(
		setupPlayer
	)

	Players.PlayerRemoving:Connect(
		function(player)
			countCache[player] =
				nil

			loadedPlayers[player] =
				nil

			syncingPlayers[player] =
				nil
		end
	)
end

return AxeInventoryLobbyService
