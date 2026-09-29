--!strict
-- ============================================================
-- HousePaintServer_Multiplayer_V4_8
-- Tipo: Script
-- Ubicación: AdentroCasaJugadores > ServerScriptService
--
-- Funciones:
-- 1. Recibe ApplySurface desde HouseEditorClientV4.
-- 2. Aplica color/material únicamente al slot interior del jugador.
-- 3. Guarda por UserId, no por Casa1/Casa2.
-- 4. Escribe en PlayerHouseCustomization_v6 y HouseData_v1 para que
--    CasaJugadores pueda restaurar los colores exteriores.
-- 5. Carga la pintura guardada al entrar al interior.
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")

local REMOTE_FOLDER_NAME = "HouseCustomizationRemotes"
local CUSTOMIZATION_STORE =
	DataStoreService:GetDataStore("PlayerHouseCustomization_v6")
local LEGACY_HOUSE_STORE =
	DataStoreService:GetDataStore("HouseData_v1")
local HOUSE_PAINT_CHANNEL = "HousePaintUpdated_v4"

local casasFolder = Workspace:WaitForChild("Casas")
local casaExtFolder = Workspace:FindFirstChild("CasaExt")
local remotes = ReplicatedStorage:WaitForChild(REMOTE_FOLDER_NAME)

local ApplySurface = remotes:WaitForChild("ApplySurface") :: RemoteEvent
local Notify = remotes:FindFirstChild("Notify") :: RemoteEvent?

local ALLOWED_SURFACES = {
	Pared = true,
	Techo = true,
	Piso = true,
	Puerta = true,
}

local MATERIALS: {[string]: Enum.Material} = {
	Concreto = Enum.Material.Concrete,
	Ladrillo = Enum.Material.Brick,
	Madera = Enum.Material.Wood,
	Piedra = Enum.Material.Slate,
	Liso = Enum.Material.SmoothPlastic,
	Metal = Enum.Material.Metal,
	Marmol = Enum.Material.Marble,
	Tejas = Enum.Material.RoofShingles,
}

local DEFAULT_SURFACES = {
	Pared = {
		Color = {R = 0.70, G = 0.50, B = 0.30},
		Material = "Liso",
	},
	Techo = {
		Color = {R = 0.20, G = 0.20, B = 0.20},
		Material = "Liso",
	},
	Piso = {
		Color = {R = 0.55, G = 0.42, B = 0.28},
		Material = "Madera",
	},
	Puerta = {
		Color = {R = 0.36, G = 0.20, B = 0.11},
		Material = "Madera",
	},
}

local lastApplyAt: {[number]: number} = {}
local cachedSurfaceData: {[number]: any} = {}

local function notify(player: Player, text: string)
	if Notify then
		Notify:FireClient(player, text)
	end
end

local function slotNumberForPlayer(player: Player): number?
	return tonumber(player:GetAttribute("InteriorSlotNumber"))
		or tonumber(player:GetAttribute("HouseNumber"))
end

local function houseForPlayer(player: Player): Model?
	local slot = slotNumberForPlayer(player)
	if not slot then return nil end

	local house =
		casasFolder:FindFirstChild("Casa" .. tostring(slot))
		or casasFolder:FindFirstChild("Casa " .. tostring(slot))

	return house and house:IsA("Model") and house or nil
end

local function exteriorPreviewForPlayer(player: Player): Model?
	local slot = slotNumberForPlayer(player)
	if not slot or not casaExtFolder then return nil end

	local preview =
		casaExtFolder:FindFirstChild("Casa Jugador" .. tostring(slot))
		or casaExtFolder:FindFirstChild("CasaJugador" .. tostring(slot))
		or casaExtFolder:FindFirstChild("Casa " .. tostring(slot))
		or casaExtFolder:FindFirstChild("Casa" .. tostring(slot))

	return preview and preview:IsA("Model") and preview or nil
end

local function colorToTable(color: Color3)
	return {
		R = color.R,
		G = color.G,
		B = color.B,
	}
end

local function tableToColor(value: any, fallback: Color3): Color3
	if type(value) ~= "table" then
		return fallback
	end

	return Color3.new(
		math.clamp(tonumber(value.R) or fallback.R, 0, 1),
		math.clamp(tonumber(value.G) or fallback.G, 0, 1),
		math.clamp(tonumber(value.B) or fallback.B, 0, 1)
	)
end

local function defaultColor(surface: string): Color3
	local data = DEFAULT_SURFACES[surface]
	return Color3.new(data.Color.R, data.Color.G, data.Color.B)
end

local function normalizeSurfaceData(data: any)
	local result = {
		Surface = {},
	}

	local source =
		type(data) == "table"
		and type(data.Surface) == "table"
		and data.Surface
		or {}

	for surface, fallback in pairs(DEFAULT_SURFACES) do
		local entry =
			type(source[surface]) == "table"
			and source[surface]
			or {}

		local color = tableToColor(entry.Color, defaultColor(surface))
		local materialName =
			type(entry.Material) == "string"
			and MATERIALS[entry.Material]
			and entry.Material
			or fallback.Material

		result.Surface[surface] = {
			Color = colorToTable(color),
			Material = materialName,
		}
	end

	return result
end

local function nameContainsAny(text: string, words: {string}): boolean
	for _, word in ipairs(words) do
		if string.find(text, word, 1, true) then
			return true
		end
	end
	return false
end

local function isDoorUnion(part: BasePart, house: Model): boolean
	local current: Instance? = part

	while current and current ~= house do
		if current.Name == "DoorSpawn"
			or current.Name == "DoorGarden"
			or current.Name == "DoorTps"
		then
			return false
		end
		current = current.Parent
	end

	if part.Name ~= "Union" then
		return false
	end

	local parent = part.Parent
	if parent and parent.Name == "Puerta" then
		return true
	end

	-- Respaldo para CasaExt > Door > Puerta > Doorframe > Puerta > Union.
	return part:FindFirstAncestor("Door") ~= nil
end

local function hasAncestorNamed(instance: Instance, targetName: string, stopAt: Instance?): boolean
	local current = instance.Parent

	while current and current ~= stopAt do
		if current.Name == targetName then
			return true
		end
		current = current.Parent
	end

	return false
end

local function isInteriorDoorPiece(part: BasePart, house: Model): boolean
	local inDoorSpawn = hasAncestorNamed(part, "DoorSpawn", house)
	local inDoorGarden = hasAncestorNamed(part, "DoorGarden", house)

	if not inDoorSpawn and not inDoorGarden then
		return false
	end

	if not hasAncestorNamed(part, "PuertaDesign", house) then
		return false
	end

	-- La hoja visible está formada por:
	-- 1. El BasePart llamado "Puerta".
	-- 2. La Union que está dentro de ese BasePart.
	if part.Name == "Puerta" then
		return true
	end

	if part.Name == "Union"
		and part.Parent
		and part.Parent.Name == "Puerta"
	then
		return true
	end

	return false
end

local function classifyPart(part: BasePart, house: Model): string?
	if part.Name == "MuroNegro" then
		return nil
	end

	if part:FindFirstAncestor("HouseSafetyBounds") then
		return nil
	end

	local isExteriorPreview =
		house.Parent ~= nil
		and house.Parent.Name == "CasaExt"

	-----------------------------------------------------------------
	-- PUERTAS DE CASAS INTERIORES
	-----------------------------------------------------------------
	if not isExteriorPreview then
		if isInteriorDoorPiece(part, house) then
			return "Puerta"
		end

		-- No pintar marcos, bisagras, Parts auxiliares ni triggers.
		if hasAncestorNamed(part, "DoorSpawn", house)
			or hasAncestorNamed(part, "DoorGarden", house)
			or hasAncestorNamed(part, "DoorTps", house)
		then
			return nil
		end
	end

	-----------------------------------------------------------------
	-- PUERTA DE CASAEXT
	-- CasaExt > Casa JugadorN > Door > Puerta > Doorframe > Puerta
	-- La hoja visible puede incluir el BasePart "Puerta" y la "Union".
	-----------------------------------------------------------------
	if isExteriorPreview and hasAncestorNamed(part, "Door", house) then
		if part.Name == "Union" then
			return "Puerta"
		end

		if part.Name == "Puerta"
			and part:IsA("BasePart")
			and hasAncestorNamed(part, "Doorframe", house)
		then
			return "Puerta"
		end

		-- No pintar marco, Hinge, Part ni MuroNegro.
		return nil
	end

	-----------------------------------------------------------------
	-- PARED / TECHO / PISO
	-----------------------------------------------------------------
	local parentName = part.Parent and part.Parent.Name or ""
	local text = string.lower(part.Name .. " " .. parentName)

	if nameContainsAny(text, {"techo", "roof", "tejado"}) then
		return "Techo"
	end

	if nameContainsAny(text, {"piso", "floor", "suelo"}) then
		return "Piso"
	end

	if nameContainsAny(text, {"pared", "paredes", "wall", "muro"}) then
		return "Pared"
	end

	local current: Instance? = part.Parent
	for _ = 1, 7 do
		if not current or current == house then
			break
		end

		local lower = string.lower(current.Name)

		if nameContainsAny(lower, {"techo", "roof", "tejado"}) then
			return "Techo"
		elseif nameContainsAny(lower, {"piso", "floor", "suelo"}) then
			return "Piso"
		elseif nameContainsAny(lower, {"pared", "paredes", "wall", "muro"}) then
			return "Pared"
		end

		current = current.Parent
	end

	return nil
end

local function applyOneSurface(
	house: Model,
	surface: string,
	color: Color3,
	materialName: string
): number
	local material = MATERIALS[materialName]
	if not material then
		return 0
	end

	local changed = 0

	for _, object in ipairs(house:GetDescendants()) do
		if object:IsA("BasePart")
			and classifyPart(object, house) == surface
		then
			-- Las UnionOperation pueden ignorar Color si UsePartColor=false.
			if object:IsA("UnionOperation") then
				object.UsePartColor = true
			end

			object.Color = color
			object.Material = material
			changed += 1
		end
	end

	return changed
end

local function applyAllSavedSurfaces(player: Player)
	local house = houseForPlayer(player)
	local exteriorPreview = exteriorPreviewForPlayer(player)

	if not house and not exteriorPreview then
		return
	end

	local data = cachedSurfaceData[player.UserId]
	if not data then
		return
	end

	for surface, entry in pairs(data.Surface) do
		local color = tableToColor(entry.Color, defaultColor(surface))

		if house then
			applyOneSurface(house, surface, color, entry.Material)
		end

		if exteriorPreview then
			applyOneSurface(exteriorPreview, surface, color, entry.Material)
		end
	end
end

local function publishPaintUpdate(
	player: Player,
	surface: string,
	entry: any
)
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:PublishAsync(
				HOUSE_PAINT_CHANNEL,
				{
					UserId = player.UserId,
					Surface = surface,
					Color = entry.Color,
					Material = entry.Material,
					UpdatedAt = os.time(),
				}
			)
		end)

		if not ok then
			warn("[HousePaint] No se pudo publicar actualización en vivo: "
				.. tostring(err))
		end
	end)
end

local function saveSurfaceData(player: Player, data: any)
	cachedSurfaceData[player.UserId] = data

	local userId = player.UserId

	task.spawn(function()
		local okCustom, customError = pcall(function()
			CUSTOMIZATION_STORE:UpdateAsync(
				"user_" .. tostring(userId),
				function(current)
					current = type(current) == "table" and current or {}
					current.Surface = data.Surface
					current.UpdatedAt = os.time()
					return current
				end
			)
		end)

		if not okCustom then
			warn("[HousePaint] Error guardando PlayerHouseCustomization_v6: "
				.. tostring(customError))
		end

		-- Compatibilidad con HouseSystem de CasaJugadores.
		local okLegacy, legacyError = pcall(function()
			LEGACY_HOUSE_STORE:UpdateAsync(
				"Player_" .. tostring(userId),
				function(current)
					current = type(current) == "table" and current or {}

					for surface, entry in pairs(data.Surface) do
						local colorKey = surface .. "Color"
						local materialKey = surface .. "Material"
						local material = MATERIALS[entry.Material]

						current[colorKey] = entry.Color
						current[materialKey] =
							material and material.Value
							or Enum.Material.SmoothPlastic.Value
					end

					return current
				end
			)
		end)

		if not okLegacy then
			warn("[HousePaint] Error guardando HouseData_v1: "
				.. tostring(legacyError))
		end
	end)
end

local function loadSurfaceData(player: Player)
	local ok, stored = pcall(function()
		return CUSTOMIZATION_STORE:GetAsync(
			"user_" .. tostring(player.UserId)
		)
	end)

	if not ok then
		warn("[HousePaint] No se pudieron cargar colores de "
			.. player.Name)
	end

	local normalized = normalizeSurfaceData(ok and stored or nil)
	cachedSurfaceData[player.UserId] = normalized

	local started = os.clock()
	while player.Parent
		and player:GetAttribute("InteriorSlotReady") ~= true
		and os.clock() - started < 12
	do
		task.wait(0.1)
	end

	applyAllSavedSurfaces(player)

	print("[HousePaint] Pintura cargada para " .. player.Name)
end

ApplySurface.OnServerEvent:Connect(function(
	player: Player,
	surface: any,
	color: any,
	materialName: any
)
	local now = os.clock()
	if now - (lastApplyAt[player.UserId] or 0) < 0.15 then
		return
	end
	lastApplyAt[player.UserId] = now

	if type(surface) ~= "string"
		or not ALLOWED_SURFACES[surface]
	then
		notify(player, "Superficie no válida.")
		return
	end

	if typeof(color) ~= "Color3" then
		notify(player, "Color no válido.")
		return
	end

	if type(materialName) ~= "string"
		or not MATERIALS[materialName]
	then
		notify(player, "Material no válido.")
		return
	end

	local house = houseForPlayer(player)
	if not house then
		notify(player, "Tu interior todavía no está listo.")
		return
	end

	if tonumber(house:GetAttribute("RuntimeOwnerUserId"))
		~= player.UserId
	then
		notify(player, "Este interior no te pertenece.")
		return
	end

	local changed = applyOneSurface(
		house,
		surface,
		color,
		materialName
	)

	local exteriorPreview = exteriorPreviewForPlayer(player)
	local previewChanged = 0

	if exteriorPreview then
		previewChanged = applyOneSurface(
			exteriorPreview,
			surface,
			color,
			materialName
		)
	end

	if changed <= 0 and previewChanged <= 0 then
		warn("[HousePaint] No se encontraron piezas para " .. surface
			.. " en el interior ni en CasaExt del slot.")
		notify(player, "No encontré piezas configuradas para " .. surface .. ".")
		return
	end

	local data =
		cachedSurfaceData[player.UserId]
		or normalizeSurfaceData(nil)

	data.Surface[surface] = {
		Color = colorToTable(color),
		Material = materialName,
	}

	saveSurfaceData(player, data)
	publishPaintUpdate(player, surface, data.Surface[surface])
	notify(player, surface .. " actualizado.")

	print(string.format(
		"[HousePaint] %s cambió %s en Casa%d (interior=%d, CasaExt=%d)",
		player.Name,
		surface,
		tonumber(player:GetAttribute("InteriorSlotNumber")) or 0,
		changed,
		previewChanged
		))
end)

local function setupPlayer(player: Player)
	task.spawn(loadSurfaceData, player)

	player:GetAttributeChangedSignal("InteriorSlotReady"):Connect(function()
		if player:GetAttribute("InteriorSlotReady") == true then
			task.delay(0.2, applyAllSavedSurfaces, player)
		end
	end)
end

Players.PlayerAdded:Connect(setupPlayer)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
	cachedSurfaceData[player.UserId] = nil
	lastApplyAt[player.UserId] = nil
end)

print("[HousePaint] Sistema de pintura multijugador V4.8 iniciado.")