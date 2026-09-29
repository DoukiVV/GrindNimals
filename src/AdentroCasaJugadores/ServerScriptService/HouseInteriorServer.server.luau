--!strict
--[[
	HouseInteriorServer V6.7 COMPLETO - Backpack Bridge + carga única

	Tipo:
		Script

	Ubicación:
		AdentroCasaJugadores
		> ServerScriptService
		> HouseInteriorServer

	Incluye:
	- Compra, colocación, movimiento y borrado de muebles.
	- Guardado por UserId con CFrame relativo a la casa.
	- Restauración de muebles predeterminados para jugadores nuevos.
	- Colisión física de muebles durante el juego normal.
	- Conservación de Seat > Script y Seat > sitanim.
	- Alfombras debajo de otros muebles.
	- Maceta, Lampara pequeña y Television sobre mesas permitidas.
	- Bombilla y Luz plana ocultas y bloqueadas para compra.
	- Validación de límites, apoyo y colisión desde el servidor.
	- No sobrescribe los cultivos del jardín.
]]

---------------------------------------------------------------------
-- SERVICIOS
---------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")

--============================================================
-- XP POR ACCIONES DEL JUEGO
-- Busca el sistema central de nivel en el servidor.
-- Si AwardGameAction no existe todavía, usa AwardPlayerXP como respaldo.
--============================================================
local function awardGameActionXP(player, actionName, fallbackXP)
	if not player or player.Parent ~= Players then
		return
	end

	local actionEvent = ReplicatedStorage:FindFirstChild("AwardGameAction")
	if actionEvent and actionEvent:IsA("BindableEvent") then
		actionEvent:Fire(player, actionName)
		return
	end

	local xpEvent = ReplicatedStorage:FindFirstChild("AwardPlayerXP")
	if xpEvent and xpEvent:IsA("BindableEvent") then
		xpEvent:Fire(player, fallbackXP, actionName)
	end
end


---------------------------------------------------------------------
-- CONFIGURACIÓN
---------------------------------------------------------------------

local REMOTE_FOLDER_NAME = "HouseCustomizationRemotes"

local HOUSE_PRESENCE_CHANNEL = "HousePresenceUpdated_v1"
local FURNITURE_STORE =
	DataStoreService:GetDataStore("PlayerInteriorFurniture_v8")

local FURNITURE_SCHEMA_VERSION = 4
local FURNITURE_WALL_TOLERANCE = 0.03
local FLOOR_RAY_DISTANCE = 4
local MAX_FURNITURE_PER_HOUSE = 250

local PLACE_COOLDOWN = 0.35
local MOVE_COOLDOWN = 0.08
local DELETE_COOLDOWN = 0.20
local AUTOSAVE_INTERVAL = 30
local SAVE_DEBOUNCE = 1.5

---------------------------------------------------------------------
-- CARPETAS
---------------------------------------------------------------------

local casasFolder = Workspace:WaitForChild("Casas")
local templateFolder = Workspace:WaitForChild("Muebles")

---------------------------------------------------------------------
-- REMOTOS
---------------------------------------------------------------------

local remotes = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER_NAME)

if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = REMOTE_FOLDER_NAME
	remotes.Parent = ReplicatedStorage
end

local function ensureRemote(
	className: string,
	name: string
): Instance
	local object = remotes:FindFirstChild(name)

	if object and object.ClassName ~= className then
		object:Destroy()
		object = nil
	end

	if not object then
		object = Instance.new(className)
		object.Name = name
		object.Parent = remotes
	end

	return object
end

local GetCatalog =
	ensureRemote("RemoteFunction", "GetCatalog")
:: RemoteFunction

local GetHouseInfo =
	ensureRemote("RemoteFunction", "GetHouseInfo")
:: RemoteFunction

local PlaceFurniture =
	ensureRemote("RemoteEvent", "PlaceFurniture")
:: RemoteEvent

local MoveFurniture =
	ensureRemote("RemoteEvent", "MoveFurniture")
:: RemoteEvent

local DeleteFurniture =
	ensureRemote("RemoteEvent", "DeleteFurniture")
:: RemoteEvent

local FurniturePlaced =
	ensureRemote("RemoteEvent", "FurniturePlaced")
:: RemoteEvent

-- V6.7:
-- HouseEditorClientV4 ya esperaba estos dos RemoteFunctions,
-- pero V6.6 nunca los creaba. Eso causaba Infinite yield.
local StorePlacedFurniture =
	ensureRemote("RemoteFunction", "StorePlacedFurniture")
:: RemoteFunction

local PlaceInventoryFurniture =
	ensureRemote("RemoteFunction", "PlaceInventoryFurniture")
:: RemoteFunction

local Notify =
	ensureRemote("RemoteEvent", "Notify")
:: RemoteEvent

-- HousePaintServer y el sistema de ampliación pueden conectar estos
-- remotos sin que este Script duplique su lógica.
ensureRemote("RemoteEvent", "ApplySurface")
ensureRemote("RemoteEvent", "UpgradeHouse")

---------------------------------------------------------------------
-- ESTADO
---------------------------------------------------------------------

local playerHouse: {[number]: number} = {}
local defaultFurnitureByHouse: {[number]: {any}} = {}
local lastActionAt: {[number]: {[string]: number}} = {}
local dirtyPlayers: {[number]: boolean} = {}
local pendingSaveTokens: {[number]: number} = {}
local loadedPlayers: {[number]: boolean} = {}
local loadingPlayers: {[number]: boolean} = {}
local savingPlayers: {[number]: boolean} = {}
local Geometry: {[string]: any} = {}

---------------------------------------------------------------------
-- UTILIDADES
---------------------------------------------------------------------

local function trim(value: any): string
	return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function cleanFurnitureRuleName(value: any): string
	local name = tostring(value or ""):lower()

	name = name:gsub("á", "a")
	name = name:gsub("é", "e")
	name = name:gsub("í", "i")
	name = name:gsub("ó", "o")
	name = name:gsub("ú", "u")
	name = name:gsub("ü", "u")
	name = name:gsub("ñ", "n")
	name = name:gsub("^%s+", "")
	name = name:gsub("%s+$", "")
	name = name:gsub("%s+", " ")

	return name
end

local function furnitureRuleName(
	item: Instance?
): string
	if not item then
		return ""
	end

	return cleanFurnitureRuleName(
		item:GetAttribute("CatalogName")
			or item.Name
	)
end

local function isCarpetFurniture(value: any): boolean
	local name = cleanFurnitureRuleName(value)

	-- El MeshPart del catálogo está nombrado "Alfombra". Se conserva compatibilidad con "Alfrombra" para datos viejos.
	-- Se aceptan las dos variantes para no depender del nombre corregido.
	return name:find(
		"alfombra",
		1,
		true
	) ~= nil
		or name:find(
			"alfrombra",
			1,
			true
		) ~= nil
end

local function isStackableFurniture(value: any): boolean
	local name = cleanFurnitureRuleName(value)

	-- Nombres reales del catálogo:
	-- Maseta, Lampara y Television pequeña.
	return name == "maceta"
		or name == "maseta"
		or name == "lampara"
		or name == "lampara pequena"
		or name == "television"
		or name == "television pequena"
		or name == "tv"
end

local function isAllowedStackSupport(
	childValue: any,
	supportValue: any
): boolean
	if not isStackableFurniture(childValue) then
		return false
	end

	local support =
		cleanFurnitureRuleName(supportValue)

	return support == "mesa"
		or support == "mesa mediana"
		or support == "mesa grande"
		or support == "mueble pequeno"
		or support:match("^mesa%s") ~= nil
end

local function isHiddenCatalogFurniture(
	value: any
): boolean
	local name = cleanFurnitureRuleName(value)

	return name == "bombilla"
		or name == "luz plana"
end

-- Precio devuelto al vender cada mueble.
-- Se aceptan variantes de nombres que ya existen en Workspace.
local SELL_REFUND_BY_NAME: {[string]: number} = {
	["alfombra"] = 13,
	["alfrombra"] = 13,

	["cama"] = 30,
	["cama para mascota"] = 18,

	["estante"] = 60,
	["estufa"] = 55,
	["lavamanos"] = 20,

	["lampara"] = 10,
	["lampara pequena"] = 10,
	["lampara grande"] = 20,

	["lavadora"] = 50,

	["maceta"] = 5,
	["maseta"] = 5,

	["mesa"] = 30,
	["mesa media"] = 40,
	["mesa mediana"] = 40,

	["mueble pequeno"] = 18,

	["refrigerador"] = 65,
	["refrigerador moderno"] = 75,

	["retrete"] = 30,
	["silla"] = 20,
	["silla moderna"] = 20,
	["sillon"] = 20,
	["sofa"] = 45,

	["television"] = 20,
	["television pequeno"] = 20,
	["television pequena"] = 20,
	["tv"] = 20,
}

local function sellRefundForItem(
	item: Instance
): number?
	local name =
		cleanFurnitureRuleName(
			item:GetAttribute("CatalogName")
			or item.Name
		)

	return SELL_REFUND_BY_NAME[name]
end

local function isFiniteNumber(
	value: number
): boolean
	return value == value
		and value > -math.huge
		and value < math.huge
end

local function isValidCFrame(
	value: any
): boolean
	if typeof(value) ~= "CFrame" then
		return false
	end

	for _, component in ipairs({
		value:GetComponents(),
		}) do
		if not isFiniteNumber(component) then
			return false
		end
	end

	return true
end

local function cframeToArray(
	cf: CFrame
): {number}
	return {cf:GetComponents()}
end

local function arrayToCFrame(
	value: any
): CFrame?
	if type(value) ~= "table"
		or #value ~= 12
	then
		return nil
	end

	for _, component in ipairs(value) do
		if type(component) ~= "number"
			or not isFiniteNumber(component)
		then
			return nil
		end
	end

	return CFrame.new(table.unpack(value))
end

local function houseNumberFromName(
	name: string
): number?
	return tonumber(
		tostring(name):match("(%d+)$")
	)
end

local function houseForNumber(
	number: number?
): Model?
	if not number then
		return nil
	end

	local house =
		casasFolder:FindFirstChild(
			"Casa" .. tostring(number)
		)
		or casasFolder:FindFirstChild(
			"Casa " .. tostring(number)
		)

	return house
		and house:IsA("Model")
		and house
		or nil
end

local function resolveHouseNumber(
	player: Player
): number
	local cached = playerHouse[player.UserId]

	if cached and houseForNumber(cached) then
		return cached
	end

	local attributeNumber =
		tonumber(player:GetAttribute("HouseNumber"))
		or tonumber(
			player:GetAttribute(
				"InteriorSlotNumber"
			)
		)

	if attributeNumber
		and houseForNumber(attributeNumber)
	then
		playerHouse[player.UserId] =
			attributeNumber

		return attributeNumber
	end

	-- Respaldo únicamente para pruebas directas en Studio.
	for _, house in ipairs(
		casasFolder:GetChildren()
		) do
		if house:IsA("Model") then
			local number =
				houseNumberFromName(house.Name)

			if number then
				playerHouse[player.UserId] = number
				player:SetAttribute(
					"HouseNumber",
					number
				)
				return number
			end
		end
	end

	playerHouse[player.UserId] = 1
	player:SetAttribute("HouseNumber", 1)

	return 1
end

local function houseForPlayer(
	player: Player
): (Model?, number)
	local number = resolveHouseNumber(player)
	return houseForNumber(number), number
end

local function furnitureFolderForHouse(
	house: Model?
): Folder?
	if not house then
		return nil
	end

	local casaPartes =
		house:FindFirstChild("CasaPartes")

	if not casaPartes then
		return nil
	end

	local folder =
		casaPartes:FindFirstChild("Muebles")

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Muebles"
		folder.Parent = casaPartes
	end

	return folder:IsA("Folder")
		and folder
		or nil
end

local function playerOwnsHouse(
	player: Player,
	house: Model
): boolean
	local ownerId =
		tonumber(
			house:GetAttribute(
				"RuntimeOwnerUserId"
			)
		)

	-- Permite pruebas directas si todavía no existe el atributo.
	return ownerId == nil
		or ownerId == 0
		or ownerId == player.UserId
end

local function notify(
	player: Player,
	text: string
)
	Notify:FireClient(player, tostring(text))
end

local function actionAllowed(
	player: Player,
	actionName: string,
	cooldown: number
): boolean
	local userState =
		lastActionAt[player.UserId]

	if not userState then
		userState = {}
		lastActionAt[player.UserId] = userState
	end

	local now = os.clock()
	local last = userState[actionName] or 0

	if now - last < cooldown then
		return false
	end

	userState[actionName] = now
	return true
end

---------------------------------------------------------------------
-- LÍMITES DE LA CASA
---------------------------------------------------------------------

local function getBuildBounds(
	house: Model
): (CFrame?, Vector3?)
	local casaPartes =
		house:FindFirstChild("CasaPartes")

	local partes =
		casaPartes
		and casaPartes:FindFirstChild("Partes")

	if partes then
		local floorPart: BasePart? = nil
		local roofPart: BasePart? = nil

		for _, part in ipairs(
			partes:GetDescendants()
			) do
			if part:IsA("BasePart")
				and part.Size.Y <= 1.6
			then
				if not floorPart
					or part.Position.Y
					< floorPart.Position.Y
				then
					floorPart = part
				end

				if not roofPart
					or part.Position.Y
					> roofPart.Position.Y
				then
					roofPart = part
				end
			end
		end

		if floorPart then
			local floorTopY =
				floorPart.Position.Y
				+ floorPart.Size.Y * 0.5

			local roofY =
				roofPart
				and (
					roofPart.Position.Y
					+ roofPart.Size.Y * 0.5
				)
				or (floorTopY + 12)

			local centerY =
				(floorTopY + roofY) * 0.5

			local rotationOnly =
				floorPart.CFrame
			- floorPart.CFrame.Position

			local boundsCFrame =
				CFrame.new(
					floorPart.Position.X,
					centerY,
					floorPart.Position.Z
				)
				* rotationOnly

			local boundsSize =
				Vector3.new(
					floorPart.Size.X,
					math.max(
						8,
						roofY - floorTopY
					),
					floorPart.Size.Z
				)

			return boundsCFrame, boundsSize
		end
	end

	return house:GetBoundingBox()
end

local function getStructureFolder(
	house: Model
): Instance
	local casaPartes =
		house:FindFirstChild("CasaPartes")

	local partes =
		casaPartes
		and casaPartes:FindFirstChild("Partes")

	return partes or casaPartes or house
end

function Geometry.boxAabbInFrame(
	boxCf: CFrame,
	boxSize: Vector3,
	frame: CFrame
): (Vector3, Vector3)
	local minimum =
		Vector3.new(
			math.huge,
			math.huge,
			math.huge
		)

	local maximum =
		Vector3.new(
			-math.huge,
			-math.huge,
			-math.huge
		)

	for _, sx in ipairs({-1, 1}) do
		for _, sy in ipairs({-1, 1}) do
			for _, sz in ipairs({-1, 1}) do
				local worldPoint =
					boxCf:PointToWorldSpace(
						Vector3.new(
							boxSize.X * 0.5 * sx,
							boxSize.Y * 0.5 * sy,
							boxSize.Z * 0.5 * sz
						)
					)

				local point =
					frame:PointToObjectSpace(
						worldPoint
					)

				minimum = Vector3.new(
					math.min(minimum.X, point.X),
					math.min(minimum.Y, point.Y),
					math.min(minimum.Z, point.Z)
				)

				maximum = Vector3.new(
					math.max(maximum.X, point.X),
					math.max(maximum.Y, point.Y),
					math.max(maximum.Z, point.Z)
				)
			end
		end
	end

	return minimum, maximum
end

function Geometry.structurePathName(
	part: BasePart,
	stopAt: Instance?
): string
	local text = part.Name:lower()
	local current = part.Parent

	while current and current ~= stopAt do
		text =
			text
			.. " "
			.. current.Name:lower()

		current = current.Parent
	end

	return text
end

function Geometry.getInteriorLimits(
	house: Model
): any
	local boundsCf, boundsSize =
		getBuildBounds(house)

	if not boundsCf or not boundsSize then
		return nil
	end

	local limits = {
		CFrame = boundsCf,
		Size = boundsSize,
		MinX = -boundsSize.X * 0.5,
		MaxX = boundsSize.X * 0.5,
		MinZ = -boundsSize.Z * 0.5,
		MaxZ = boundsSize.Z * 0.5,
		FloorY =
			boundsCf.Position.Y
		- boundsSize.Y * 0.5,
		CeilingY =
			boundsCf.Position.Y
			+ boundsSize.Y * 0.5,
	}

	local structure =
		getStructureFolder(house)

	local foundMinX = false
	local foundMaxX = false
	local foundMinZ = false
	local foundMaxZ = false

	for _, part in ipairs(
		structure:GetDescendants()
		) do
		if part:IsA("BasePart") then
			local pathName =
				Geometry.structurePathName(
					part,
					structure.Parent
				)

			local isFloorOrRoof =
				pathName:find(
					"piso",
					1,
					true
				) ~= nil
				or pathName:find(
					"floor",
					1,
					true
				) ~= nil
				or pathName:find(
					"suelo",
					1,
					true
				) ~= nil
				or pathName:find(
					"techo",
					1,
					true
				) ~= nil
				or pathName:find(
					"roof",
					1,
					true
				) ~= nil

			if not isFloorOrRoof then
				local partMin, partMax =
					Geometry.boxAabbInFrame(
						part.CFrame,
						part.Size,
						boundsCf
					)

				local extent =
					partMax - partMin

				local center =
					(partMin + partMax) * 0.5

				if extent.Y > 2.25 then
					local nearXEdge =
						math.abs(center.X)
						> boundsSize.X * 0.28

					local nearZEdge =
						math.abs(center.Z)
						> boundsSize.Z * 0.28

					if nearXEdge
						and extent.X
						<= math.max(
							3,
							extent.Z * 0.55
						)
					then
						if center.X > 0 then
							limits.MaxX =
								math.min(
									limits.MaxX,
									partMin.X
								)
							foundMaxX = true
						else
							limits.MinX =
								math.max(
									limits.MinX,
									partMax.X
								)
							foundMinX = true
						end
					end

					if nearZEdge
						and extent.Z
						<= math.max(
							3,
							extent.X * 0.55
						)
					then
						if center.Z > 0 then
							limits.MaxZ =
								math.min(
									limits.MaxZ,
									partMin.Z
								)
							foundMaxZ = true
						else
							limits.MinZ =
								math.max(
									limits.MinZ,
									partMax.Z
								)
							foundMinZ = true
						end
					end
				end
			end
		end
	end

	if not foundMinX then
		limits.MinX = -boundsSize.X * 0.5
	end

	if not foundMaxX then
		limits.MaxX = boundsSize.X * 0.5
	end

	if not foundMinZ then
		limits.MinZ = -boundsSize.Z * 0.5
	end

	if not foundMaxZ then
		limits.MaxZ = boundsSize.Z * 0.5
	end

	if limits.MaxX - limits.MinX < 4 then
		limits.MinX = -boundsSize.X * 0.5
		limits.MaxX = boundsSize.X * 0.5
	end

	if limits.MaxZ - limits.MinZ < 4 then
		limits.MinZ = -boundsSize.Z * 0.5
		limits.MaxZ = boundsSize.Z * 0.5
	end

	return limits
end

function Geometry.isStructureBlocker(
	part: BasePart,
	house: Model,
	limits: any
): boolean
	local structure =
		getStructureFolder(house)

	if not part:IsDescendantOf(structure) then
		return false
	end

	local pathName =
		Geometry.structurePathName(
			part,
			structure.Parent
		)

	if pathName:find("piso", 1, true)
		or pathName:find("floor", 1, true)
		or pathName:find("suelo", 1, true)
		or pathName:find("techo", 1, true)
		or pathName:find("roof", 1, true)
	then
		return false
	end

	local partMin, partMax =
		Geometry.boxAabbInFrame(
			part.CFrame,
			part.Size,
			limits.CFrame
		)

	local extent = partMax - partMin
	local centerY =
		(partMin.Y + partMax.Y) * 0.5

	if extent.Y <= 1.8
		and (
			centerY
				< -limits.Size.Y * 0.18
				or centerY
				> limits.Size.Y * 0.18
		)
	then
		return false
	end

	return extent.Y > 2
		or pathName:find(
			"pared",
			1,
			true
		) ~= nil
		or pathName:find(
			"wall",
			1,
			true
		) ~= nil
		or pathName:find(
			"puerta",
			1,
			true
		) ~= nil
		or pathName:find(
			"door",
			1,
			true
		) ~= nil
		or pathName:find(
			"ventana",
			1,
			true
		) ~= nil
		or pathName:find(
			"window",
			1,
			true
		) ~= nil
end

function Geometry.hasStructureOverlap(
	house: Model,
	item: Instance
): boolean
	local limits =
		Geometry.getInteriorLimits(house)

	if not limits then
		return true
	end

	local structure =
		getStructureFolder(house)

	local params = OverlapParams.new()
	params.FilterType =
		Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {
		structure,
	}
	params.MaxParts = 300

	local function checkPart(
		part: BasePart
	): boolean
		if part.Transparency >= 0.995
			and not part:IsA("Seat")
		then
			return false
		end

		local querySize =
			Vector3.new(
				math.max(
					0.05,
					part.Size.X - 0.08
				),
				math.max(
					0.05,
					part.Size.Y - 0.08
				),
				math.max(
					0.05,
					part.Size.Z - 0.08
				)
			)

		for _, hit in ipairs(
			Workspace:GetPartBoundsInBox(
				part.CFrame,
				querySize,
				params
			)
			) do
			if hit:IsA("BasePart")
				and Geometry.isStructureBlocker(
					hit,
					house,
					limits
				)
			then
				return true
			end
		end

		return false
	end

	if item:IsA("BasePart")
		and checkPart(item)
	then
		return true
	end

	for _, part in ipairs(
		item:GetDescendants()
		) do
		if part:IsA("BasePart")
			and checkPart(part)
		then
			return true
		end
	end

	return false
end


---------------------------------------------------------------------
-- MUEBLES Y PLANTILLAS
---------------------------------------------------------------------

local function getPivot(
	item: Instance
): CFrame?
	if item:IsA("Model") then
		return item:GetPivot()
	elseif item:IsA("BasePart") then
		return item.CFrame
	end

	return nil
end

local function setPivot(
	item: Instance,
	cf: CFrame
)
	if item:IsA("Model") then
		item:PivotTo(cf)
	elseif item:IsA("BasePart") then
		item.CFrame = cf
	end
end

local function itemBounds(
	item: Instance
): (CFrame?, Vector3?)
	if item:IsA("Model") then
		return item:GetBoundingBox()
	elseif item:IsA("BasePart") then
		return item.CFrame, item.Size
	end

	return nil, nil
end

local function isIgnoredCarpetPart(
	part: BasePart
): boolean
	local name =
		cleanFurnitureRuleName(part.Name)

	local helperName =
		name:find("hitbox", 1, true) ~= nil
		or name:find("collision", 1, true) ~= nil
		or name:find("collider", 1, true) ~= nil
		or name:find("bounds", 1, true) ~= nil
		or name:find("bounding", 1, true) ~= nil
		or name:find("pivot", 1, true) ~= nil
		or name:find("marker", 1, true) ~= nil
		or name:find("helper", 1, true) ~= nil
		or name:find("spawn", 1, true) ~= nil

	return helperName
		or part.Transparency >= 0.90
end

local function carpetExtentsInFrame(
	item: Instance,
	frameCf: CFrame
): (Vector3?, Vector3?)
	local minimum =
		Vector3.new(
			math.huge,
			math.huge,
			math.huge
		)

	local maximum =
		Vector3.new(
			-math.huge,
			-math.huge,
			-math.huge
		)

	local found = false

	local function includePart(
		part: BasePart
	)
		if isIgnoredCarpetPart(part) then
			return
		end

		local half = part.Size * 0.5

		for _, sx in ipairs({-1, 1}) do
			for _, sy in ipairs({-1, 1}) do
				for _, sz in ipairs({-1, 1}) do
					local worldPoint =
						part.CFrame:PointToWorldSpace(
							Vector3.new(
								half.X * sx,
								half.Y * sy,
								half.Z * sz
							)
						)

					local point =
						frameCf:PointToObjectSpace(
							worldPoint
						)

					minimum = Vector3.new(
						math.min(
							minimum.X,
							point.X
						),
						math.min(
							minimum.Y,
							point.Y
						),
						math.min(
							minimum.Z,
							point.Z
						)
					)

					maximum = Vector3.new(
						math.max(
							maximum.X,
							point.X
						),
						math.max(
							maximum.Y,
							point.Y
						),
						math.max(
							maximum.Z,
							point.Z
						)
					)

					found = true
				end
			end
		end
	end

	if item:IsA("BasePart") then
		includePart(item)
	else
		for _, object in ipairs(
			item:GetDescendants()
			) do
			if object:IsA("BasePart") then
				includePart(object)
			end
		end
	end

	if not found then
		local boundsCf, boundsSize =
			itemBounds(item)

		if boundsCf and boundsSize then
			return Geometry.boxAabbInFrame(
				boundsCf,
				boundsSize,
				frameCf
			)
		end

		return nil, nil
	end

	return minimum, maximum
end

local function isSlimWallFurniture(
	item: Instance
): boolean
	-- Conservado por compatibilidad. V5.3 nunca altera el tamaño del modelo.
	return false
end

local function normalizedBoundsSize(
	item: Instance,
	size: Vector3
): Vector3
	return size
end

local function normalizeFurniturePart(
	part: BasePart,
	item: Instance
)
	-- No modificar Size: el clon debe ser idéntico a Workspace > Muebles.
	return
end

local function prepFurniture(
	item: Instance
)
	local itemIsCarpet =
		isCarpetFurniture(
			furnitureRuleName(item)
		)

	local function preparePart(
		part: BasePart
	)
		normalizeFurniturePart(part, item)

		part.Anchored = true
		part.CanQuery = true

		-- La alfombra es una decoración de piso: puede quedar debajo
		-- de muebles y no debe levantar ni bloquear al jugador.
		if itemIsCarpet then
			part.CanCollide = false
			part.CanTouch = false

			-- Las piezas auxiliares de la alfombra no participan
			-- en raycasts ni consultas de volumen.
			part.CanQuery =
				not isIgnoredCarpetPart(part)

			return
		end

		-- Los Seat siempre deben conservar colisión y contacto.
		if part:IsA("Seat")
			or part:IsA("VehicleSeat")
		then
			part.CanCollide = true
			part.CanTouch = true
			return
		end

		local lowerName = part.Name:lower()

		local helperPart =
			lowerName:find(
				"pivot",
				1,
				true
			) ~= nil
			or lowerName:find(
				"marker",
				1,
				true
			) ~= nil
			or lowerName:find(
				"spawn",
				1,
				true
			) ~= nil
			or lowerName:find(
				"helper",
				1,
				true
			) ~= nil

		local shouldCollide =
			part.Transparency < 0.95
			and not helperPart

		part.CanCollide = shouldCollide
		part.CanTouch = shouldCollide
	end

	for _, object in ipairs(
		item:GetDescendants()
		) do
		if object:IsA("BaseScript") then
			local parent = object.Parent

			local isSeatScript =
				parent ~= nil
				and (
					parent:IsA("Seat")
					or parent:IsA("VehicleSeat")
				)

			-- Mantiene activo únicamente el Script de Seat.sitanim.
			object.Disabled = not isSeatScript
		elseif object:IsA("BasePart") then
			preparePart(object)
		end
	end

	if item:IsA("BasePart") then
		preparePart(item)
	end
end

local function findTemplate(
	name: string
): Instance?
	local cleanName = trim(name)

	if cleanName == "" then
		return nil
	end

	for _, child in ipairs(
		templateFolder:GetChildren()
		) do
		if (
			child:IsA("Model")
				or child:IsA("BasePart")
			)
				and trim(child.Name) == cleanName
		then
			return child
		end
	end

	return nil
end

local function findFurnitureById(
	folder: Folder,
	id: string
): Instance?
	for _, item in ipairs(
		folder:GetChildren()
		) do
		if item:GetAttribute(
			"EditableFurnitureId"
			) == id
		then
			return item
		end
	end

	return nil
end

local function furnitureOwnerFromPart(
	folder: Folder,
	part: BasePart
): Instance?
	local current: Instance? = part

	while current
		and current.Parent ~= folder
	do
		current = current.Parent
	end

	if current and current.Parent == folder then
		return current
	end

	return nil
end

---------------------------------------------------------------------
-- CATÁLOGO Y COSTOS
---------------------------------------------------------------------

local function templateCosts(
	template: Instance
): (number, number)
	local dollars =
		tonumber(
			template:GetAttribute("Dolares")
			or template:GetAttribute("Price")
			or template:GetAttribute("Precio")
		)
		or 0

	local wood =
		tonumber(
			template:GetAttribute("Madera")
			or template:GetAttribute("Wood")
		)
		or 0

	return math.max(
		0,
		math.floor(dollars)
	), math.max(
		0,
		math.floor(wood)
	)
end

local function findNumericStat(
	player: Player,
	names: {string}
): (IntValue | NumberValue)?
	local leaderstats =
		player:FindFirstChild("leaderstats")

	if not leaderstats then
		return nil
	end

	for _, name in ipairs(names) do
		local value =
			leaderstats:FindFirstChild(name)

		if value
			and (
				value:IsA("IntValue")
					or value:IsA("NumberValue")
			)
		then
			return value
		end
	end

	return nil
end

local function playerMoneyValue(
	player: Player
): (IntValue | NumberValue)?
	local existing =
		findNumericStat(
			player,
			{
				"Dolares",
				"Dólares",
				"Dollars",
				"Cash",
				"Money",
				"Dinero",
			}
		)

	if existing then
		return existing
	end

	-- El sistema de venta no debe depender de que AdminMoneyServer
	-- haya creado la moneda primero.
	local leaderstats =
		player:FindFirstChild("leaderstats")

	if leaderstats
		and not leaderstats:IsA("Folder")
	then
		leaderstats:Destroy()
		leaderstats = nil
	end

	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local dollars = Instance.new("NumberValue")
	dollars.Name = "Dolares"
	dollars.Value = 0
	dollars.Parent = leaderstats

	print(
		"[HouseInteriorsServer] Se creó leaderstats.Dolares para "
			.. player.Name
	)

	return dollars
end

local function woodLeaderstat(
	player: Player
): (IntValue | NumberValue)?
	return findNumericStat(
		player,
		{"Madera", "Wood"}
	)
end

local function toolWoodAmount(
	tool: Tool
): number
	if tool:GetAttribute("EsMadera") ~= true
		and not tool.Name:match("^Madera x%d+")
		and tool.Name:lower() ~= "madera"
	then
		return 0
	end

	return math.max(
		0,
		math.floor(
			tonumber(
				tool:GetAttribute("Cantidad")
			)
				or tonumber(
					tool.Name:match(
						"^Madera x(%d+)"
					)
				)
				or 1
		)
	)
end

local function collectWoodTools(
	player: Player
): ({Tool}, number)
	local tools: {Tool} = {}
	local total = 0

	local function scan(
		container: Instance?
	)
		if not container then
			return
		end

		for _, child in ipairs(
			container:GetChildren()
			) do
			if child:IsA("Tool") then
				local amount =
					toolWoodAmount(child)

				if amount > 0 then
					table.insert(tools, child)
					total += amount
				end
			end
		end
	end

	scan(
		player:FindFirstChildOfClass(
			"Backpack"
		)
	)
	scan(player.Character)

	return tools, total
end

local function playerWoodTotal(
	player: Player
): number
	local stat = woodLeaderstat(player)
	local _, toolTotal =
		collectWoodTools(player)

	return (
		stat and tonumber(stat.Value) or 0
	) + toolTotal
end

local function canAfford(
	player: Player,
	dollars: number,
	wood: number
): (boolean, string?)
	local money = playerMoneyValue(player)

	local currentMoney =
		money and tonumber(money.Value) or 0

	local currentWood =
		playerWoodTotal(player)

	if currentMoney < dollars then
		return false,
			"No tienes suficientes dolares."
	end

	if currentWood < wood then
		return false,
			"No tienes suficiente madera."
	end

	return true, nil
end

local function consumeWood(
	player: Player,
	requested: number
): boolean
	local remaining = requested

	if remaining <= 0 then
		return true
	end

	local stat = woodLeaderstat(player)

	if stat then
		local available =
			math.max(
				0,
				tonumber(stat.Value) or 0
			)

		local consumed =
			math.min(available, remaining)

		stat.Value = available - consumed
		remaining -= consumed
	end

	if remaining <= 0 then
		return true
	end

	local tools =
		select(1, collectWoodTools(player))

	for _, tool in ipairs(tools) do
		if remaining <= 0 then
			break
		end

		if tool.Parent then
			local amount =
				toolWoodAmount(tool)

			local consumed =
				math.min(amount, remaining)

			local left = amount - consumed
			remaining -= consumed

			if left <= 0 then
				tool:Destroy()
			else
				tool:SetAttribute(
					"Cantidad",
					left
				)
				tool.Name =
					"Madera x"
					.. tostring(left)
			end
		end
	end

	return remaining <= 0
end

local function chargePlayer(
	player: Player,
	dollars: number,
	wood: number
): boolean
	local affordable =
		select(
			1,
			canAfford(
				player,
				dollars,
				wood
			)
		)

	if not affordable then
		return false
	end

	local money = playerMoneyValue(player)

	if dollars > 0 and not money then
		return false
	end

	local oldMoney =
		money and tonumber(money.Value) or 0

	if money then
		money.Value = oldMoney - dollars
	end

	if not consumeWood(player, wood) then
		if money then
			money.Value = oldMoney
		end

		return false
	end

	return true
end

---------------------------------------------------------------------
-- VALIDACIÓN ESPACIAL
---------------------------------------------------------------------

local function isInsideHouseBounds(
	house: Model,
	item: Instance
): boolean
	local itemCFrame, rawSize =
		itemBounds(item)

	local limits =
		Geometry.getInteriorLimits(house)

	if not itemCFrame
		or not rawSize
		or not limits
	then
		return false
	end

	local minimum, maximum =
		Geometry.boxAabbInFrame(
			itemCFrame,
			rawSize,
			limits.CFrame
		)

	-- Una pequeña tolerancia permite tocar la pared sin atravesarla.
	local epsilon =
		FURNITURE_WALL_TOLERANCE

	return minimum.X
		>= limits.MinX - epsilon
		and maximum.X
		<= limits.MaxX + epsilon
		and minimum.Z
		>= limits.MinZ - epsilon
		and maximum.Z
		<= limits.MaxZ + epsilon
		and minimum.Y
		>= -limits.Size.Y * 0.5 - 0.25
		and maximum.Y
		<= limits.Size.Y * 0.5 + 0.25
end

local function hasFurnitureCollision(
	folder: Folder,
	item: Instance,
	ignoreId: string?
): boolean
	local itemName =
		furnitureRuleName(item)

	-- La alfombra puede quedar debajo de cualquier mueble.
	if isCarpetFurniture(itemName) then
		return false
	end

	local itemBoundsCf, itemBoundsSize =
		itemBounds(item)

	if not itemBoundsCf
		or not itemBoundsSize
	then
		return true
	end

	local itemBottom =
		itemBoundsCf.Position.Y
	- itemBoundsSize.Y * 0.5

	local params = OverlapParams.new()
	params.FilterType =
		Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {
		folder,
	}
	params.MaxParts = 400

	local function checkPart(
		part: BasePart
	): boolean
		if part.Transparency >= 0.995
			and not part:IsA("Seat")
		then
			return false
		end

		-- Se reduce unas centésimas para que dos superficies puedan tocarse.
		local querySize =
			Vector3.new(
				math.max(
					0.05,
					part.Size.X - 0.08
				),
				math.max(
					0.05,
					part.Size.Y - 0.08
				),
				math.max(
					0.05,
					part.Size.Z - 0.08
				)
			)

		for _, hit in ipairs(
			Workspace:GetPartBoundsInBox(
				part.CFrame,
				querySize,
				params
			)
			) do
			if hit.Transparency < 0.995
				or hit:IsA("Seat")
			then
				local owner =
					furnitureOwnerFromPart(
						folder,
						hit
					)

				if owner
					and owner ~= item
					and owner:GetAttribute(
						"EditableFurnitureId"
					) ~= ignoreId
				then
					local ownerName =
						furnitureRuleName(owner)

					if not isCarpetFurniture(
						ownerName
						) then
						local allowedStack = false

						if isAllowedStackSupport(
							itemName,
							ownerName
							) then
							local ownerCf, ownerSize =
								itemBounds(owner)

							if ownerCf and ownerSize then
								local ownerTop =
									ownerCf.Position.Y
									+ ownerSize.Y * 0.5

								local itemCenterLocal =
									ownerCf:PointToObjectSpace(
										itemBoundsCf.Position
									)

								local horizontallyOnSupport =
									math.abs(itemCenterLocal.X)
									<= ownerSize.X * 0.5 + 0.20
									and math.abs(itemCenterLocal.Z)
									<= ownerSize.Z * 0.5 + 0.20

								allowedStack =
									horizontallyOnSupport
									and itemBottom
									>= ownerTop - 0.45
									and itemBottom
									<= ownerTop + 1.00
							end
						end

						if not allowedStack then
							return true
						end
					end
				end
			end
		end

		return false
	end

	if item:IsA("BasePart")
		and checkPart(item)
	then
		return true
	end

	for _, part in ipairs(
		item:GetDescendants()
		) do
		if part:IsA("BasePart")
			and checkPart(part)
		then
			return true
		end
	end

	return false
end

local function floorRaySamples(
	boundsCFrame: CFrame,
	size: Vector3
): {Vector3}
	local y = -size.Y * 0.5 + 0.2
	local x = math.max(0, size.X * 0.42)
	local z = math.max(0, size.Z * 0.42)

	return {
		boundsCFrame:PointToWorldSpace(
			Vector3.new(0, y, 0)
		),

		boundsCFrame:PointToWorldSpace(
			Vector3.new(x, y, z)
		),

		boundsCFrame:PointToWorldSpace(
			Vector3.new(-x, y, z)
		),

		boundsCFrame:PointToWorldSpace(
			Vector3.new(x, y, -z)
		),

		boundsCFrame:PointToWorldSpace(
			Vector3.new(-x, y, -z)
		),
	}
end


local function findAllowedStackSupport(
	folder: Folder,
	item: Instance,
	ignoreId: string?
): Instance?
	local itemName =
		furnitureRuleName(item)

	if not isStackableFurniture(itemName) then
		return nil
	end

	local itemCf, itemSize =
		itemBounds(item)

	if not itemCf or not itemSize then
		return nil
	end

	local itemBottom =
		itemCf.Position.Y
	- itemSize.Y * 0.5

	for _, support in ipairs(
		folder:GetChildren()
		) do
		if support ~= item
			and support:GetAttribute(
				"EditableFurnitureId"
			) ~= ignoreId
				and isAllowedStackSupport(
					itemName,
					furnitureRuleName(support)
				)
		then
			local supportCf, supportSize =
				itemBounds(support)

			if supportCf and supportSize then
				local supportTopPoint =
					supportCf:PointToWorldSpace(
						Vector3.new(
							0,
							supportSize.Y * 0.5,
							0
						)
					)

				local centerLocal =
					supportCf:PointToObjectSpace(
						itemCf.Position
					)

				-- Permite un voladizo moderado sobre Mueble pequeño
				-- y mesas angostas.
				local maxX =
					supportSize.X * 0.5
				- itemSize.X * 0.30
					+ 0.12

				local maxZ =
					supportSize.Z * 0.5
				- itemSize.Z * 0.30
					+ 0.12

				local horizontallyInside =
					math.abs(centerLocal.X)
					<= math.max(0.08, maxX)
					and math.abs(centerLocal.Z)
					<= math.max(0.08, maxZ)

				local touchingTop =
					math.abs(
						itemBottom
						- supportTopPoint.Y
					) <= 0.65

				if horizontallyInside
					and touchingTop
				then
					return support
				end
			end
		end
	end

	return nil
end

local function supportCarriesFurniture(
	support: Instance,
	child: Instance,
	verticalLimit: number
): boolean
	if not isAllowedStackSupport(
		furnitureRuleName(child),
		furnitureRuleName(support)
		) then
		return false
	end

	local supportCf, supportSize = itemBounds(support)
	local childCf, childSize = itemBounds(child)
	if not supportCf or not supportSize or not childCf or not childSize then
		return false
	end

	local supportTop = supportCf:PointToWorldSpace(Vector3.new(0, supportSize.Y * 0.5, 0)).Y
	local childBottom = childCf.Position.Y - childSize.Y * 0.5
	local centerLocal = supportCf:PointToObjectSpace(childCf.Position)
	local maxX = supportSize.X * 0.5 - childSize.X * 0.20 + 0.35
	local maxZ = supportSize.Z * 0.5 - childSize.Z * 0.20 + 0.35

	local horizontallyInside = math.abs(centerLocal.X) <= math.max(0.15, maxX)
		and math.abs(centerLocal.Z) <= math.max(0.15, maxZ)

	local verticallyAbove = childBottom >= supportTop - 1.25
		and childBottom <= supportTop + verticalLimit

	return horizontallyInside and verticallyAbove
end

local function carriedFurnitureForMove(
	folder: Folder,
	support: Instance,
	supportId: string
): {{Item: Instance, OldCFrame: CFrame}}
	local carried = {}

	for _, other in ipairs(folder:GetChildren()) do
		if other ~= support
			and other:GetAttribute("EditableFurnitureId") ~= supportId
			and supportCarriesFurniture(support, other, 1.25)
		then
			local otherCFrame = getPivot(other)
			if otherCFrame then
				table.insert(carried, {
					Item = other,
					OldCFrame = otherCFrame,
				})
			end
		end
	end

	return carried
end

local function carriedFurnitureForSupportRemoval(
	folder: Folder,
	support: Instance,
	supportId: string
): {{Item: Instance, OldCFrame: CFrame}}
	local carried = {}

	for _, other in ipairs(folder:GetChildren()) do
		if other ~= support
			and other:GetAttribute("EditableFurnitureId") ~= supportId
			and supportCarriesFurniture(support, other, 12)
		then
			local otherCFrame = getPivot(other)
			if otherCFrame then
				table.insert(carried, {
					Item = other,
					OldCFrame = otherCFrame,
				})
			end
		end
	end

	return carried
end

local function restoreCarriedFurniture(
	carried: {{Item: Instance, OldCFrame: CFrame}}
)
	for _, entry in ipairs(carried) do
		if entry.Item and entry.Item.Parent then
			setPivot(entry.Item, entry.OldCFrame)
		end
	end
end
local function floorPivotForItem(
	item: Instance,
	pivotCFrame: CFrame,
	floorY: number
): CFrame?
	local boundsCFrame, boundsSize = itemBounds(item)
	if not boundsCFrame or not boundsSize then
		return nil
	end

	local bottomY = boundsCFrame.Position.Y - boundsSize.Y * 0.5
	local pivotToBottom = pivotCFrame.Position.Y - bottomY
	return CFrame.new(
		pivotCFrame.Position.X,
		floorY + pivotToBottom,
		pivotCFrame.Position.Z
	) * pivotCFrame.Rotation
end

local function lowerCarriedFurnitureAfterSupportRemoved(
	house: Model,
	folder: Folder,
	carried: {{Item: Instance, OldCFrame: CFrame}}
)
	if #carried == 0 then
		return
	end

	local houseCFrame, houseSize = getBuildBounds(house)
	if not houseCFrame or not houseSize then
		restoreCarriedFurniture(carried)
		return
	end

	local floorY = houseCFrame.Position.Y - houseSize.Y * 0.5 + 0.08
	local offsets = {
		Vector3.zero,
		Vector3.new(0.75, 0, 0),
		Vector3.new(-0.75, 0, 0),
		Vector3.new(0, 0, 0.75),
		Vector3.new(0, 0, -0.75),
		Vector3.new(0.75, 0, 0.75),
		Vector3.new(-0.75, 0, 0.75),
		Vector3.new(0.75, 0, -0.75),
		Vector3.new(-0.75, 0, -0.75),
		Vector3.new(1.35, 0, 0),
		Vector3.new(-1.35, 0, 0),
		Vector3.new(0, 0, 1.35),
		Vector3.new(0, 0, -1.35),
	}

	for _, entry in ipairs(carried) do
		local child = entry.Item
		local oldCFrame = entry.OldCFrame
		if child and child.Parent and oldCFrame then
			local placed = false

			for _, offset in ipairs(offsets) do
				local baseCFrame = oldCFrame + offset
				local candidate = floorPivotForItem(child, baseCFrame, floorY)
				if candidate then
					candidate = candidate
					setPivot(child, candidate)

					local childId = child:GetAttribute("EditableFurnitureId")
					local valid = select(1, placementIsValid(
						house,
						folder,
						child,
						type(childId) == "string" and childId or nil
						))

					if valid then
						placed = true
						break
					end
				end
			end

			if not placed then
				local fallback = floorPivotForItem(child, oldCFrame, floorY)
				if fallback then
					setPivot(child, fallback)
				else
					setPivot(child, oldCFrame)
				end
			end
		end
	end
end

local function hasFloorSupport(
	house: Model,
	folder: Folder,
	item: Instance
): boolean
	local boundsCFrame, rawSize =
		itemBounds(item)

	local houseCFrame, houseSize =
		getBuildBounds(house)

	if not boundsCFrame
		or not rawSize
		or not houseCFrame
		or not houseSize
	then
		return false
	end

	local size =
		normalizedBoundsSize(item, rawSize)

	local itemName =
		furnitureRuleName(item)

	local stackable =
		isStackableFurniture(itemName)

	-- Tus muebles son MeshParts directos. La validación se hace por
	-- CFrame y Size, sin depender del CollisionFidelity ni de raycasts.
	if stackable
		and findAllowedStackSupport(
			folder,
			item,
			item:GetAttribute(
				"EditableFurnitureId"
			)
		)
	then
		return true
	end

	local raycastParams =
		RaycastParams.new()

	raycastParams.FilterType =
		Enum.RaycastFilterType.Exclude

	raycastParams.IgnoreWater = true

	local ignore: {Instance} = {item}
	local itemIsCarpet =
		isCarpetFurniture(itemName)

	if itemIsCarpet then
		-- La alfombra pertenece al piso y puede quedar debajo de
		-- mesas, sofás, camas y cualquier otro mueble.
		-- Se ignora toda la carpeta para que las patas no bloqueen
		-- los rayos que comprueban el soporte del piso.
		table.insert(ignore, folder)
	else
		-- Las alfombras tampoco deben impedir que los muebles
		-- normales detecten el piso que existe debajo.
		for _, furniture in ipairs(
			folder:GetChildren()
			) do
			if isCarpetFurniture(
				furnitureRuleName(furniture)
				) then
				table.insert(ignore, furniture)
			end
		end
	end

	for _, otherPlayer in ipairs(
		Players:GetPlayers()
		) do
		if otherPlayer.Character then
			table.insert(
				ignore,
				otherPlayer.Character
			)
		end
	end

	raycastParams.FilterDescendantsInstances =
		ignore

	local structureFolder =
		getStructureFolder(house)

	local function validSupport(
		result: RaycastResult?
	): boolean
		if not result
			or not result.Instance
		then
			return false
		end

		local hit = result.Instance

		if hit:IsA("BasePart") then
			local owner =
				furnitureOwnerFromPart(
					folder,
					hit
				)

			if owner then
				return stackable
					and isAllowedStackSupport(
						itemName,
						furnitureRuleName(owner)
					)
			end
		end

		return hit:IsDescendantOf(
			structureFolder
		)
			and result.Normal.Y > 0.35
	end

	local supportedSamples = 0
	local centerSupported = false

	for index, sample in ipairs(
		floorRaySamples(
			boundsCFrame,
			size
		)
		) do
		local origin =
			sample + Vector3.new(0, 0.30, 0)

		local result =
			Workspace:Raycast(
				origin,
				Vector3.new(
					0,
					-FLOOR_RAY_DISTANCE,
					0
				),
				raycastParams
			)

		if validSupport(result) then
			supportedSamples += 1

			if index == 1 then
				centerSupported = true
			end
		end
	end

	return centerSupported
		and (
			stackable
			or supportedSamples >= 3
		)
end

local function boxTouchesItem(itemCf: CFrame, itemSize: Vector3, boxCf: CFrame, boxSize: Vector3, buffer: number): boolean
	local localPosition = boxCf:PointToObjectSpace(itemCf.Position)
	local protectedSize = boxSize + Vector3.new(buffer * 2, 6, buffer * 2)
	return math.abs(localPosition.X) <= protectedSize.X * 0.5 + itemSize.X * 0.5
		and math.abs(localPosition.Y) <= protectedSize.Y * 0.5 + itemSize.Y * 0.5
		and math.abs(localPosition.Z) <= protectedSize.Z * 0.5 + itemSize.Z * 0.5
end

local function touchesTeleportDoorZone(house: Model, item: Instance): boolean
	local itemCf, itemSize = itemBounds(item)
	local doorTps = house:FindFirstChild("DoorTps")
	if not itemCf or not itemSize or not doorTps then
		return false
	end

	local buffer = 6
	for _, door in ipairs(doorTps:GetChildren()) do
		if door:IsA("Model") then
			local doorCf, doorSize = door:GetBoundingBox()
			local protectedSize = Vector3.new(math.max(doorSize.X, 8), math.max(doorSize.Y, 10), math.max(doorSize.Z, 8))
			if boxTouchesItem(itemCf, itemSize, doorCf, protectedSize, buffer) then
				return true
			end
		end

		local trigger = door:FindFirstChild("MuroNegro", true)
		if trigger and trigger:IsA("BasePart") then
			local protectedSize = Vector3.new(math.max(trigger.Size.X, 8), math.max(trigger.Size.Y, 10), math.max(trigger.Size.Z, 8))
			if boxTouchesItem(itemCf, itemSize, trigger.CFrame, protectedSize, buffer) then
				return true
			end
		end
	end

	for _, name in ipairs({"SpawnEntradaPoint", "SpawnJardinPoint", "SpawnPoint"}) do
		local spawnPart = house:FindFirstChild(name, true)
		if spawnPart and spawnPart:IsA("BasePart") then
			if boxTouchesItem(itemCf, itemSize, spawnPart.CFrame, Vector3.new(8, 8, 8), buffer * 0.5) then
				return true
			end
		end
	end

	return false
end

local function placementIsValid(
	house: Model,
	folder: Folder,
	item: Instance,
	ignoreId: string?
): (boolean, string?)
	local itemName =
		furnitureRuleName(item)

	if touchesTeleportDoorZone(house, item) then
		return false,
			"Deja libre la puerta y la zona de teleport."
	end

	-- La alfombra ignora por completo otros muebles y sus hitboxes.
	-- Se valida únicamente con sus partes visibles contra el área interior
	-- de la casa y contra la altura del piso.
	if isCarpetFurniture(itemName) then
		local limits =
			Geometry.getInteriorLimits(house)

		local houseCFrame, houseSize =
			getBuildBounds(house)

		if not limits
			or not houseCFrame
			or not houseSize
		then
			return false,
				"No se pudo validar la alfombra."
		end

		local minimum, maximum =
			carpetExtentsInFrame(
				item,
				limits.CFrame
			)

		if not minimum or not maximum then
			return false,
				"No se pudo validar la alfombra."
		end

		local epsilon = 0.04

		if minimum.X < limits.MinX - epsilon
			or maximum.X > limits.MaxX + epsilon
			or minimum.Z < limits.MinZ - epsilon
			or maximum.Z > limits.MaxZ + epsilon
		then
			return false,
				"La alfombra esta atravesando una pared."
		end

		local floorTop =
			houseCFrame.Position.Y
		- houseSize.Y * 0.5

		local visibleBottomWorld =
			limits.CFrame:PointToWorldSpace(
				Vector3.new(
					0,
					minimum.Y,
					0
				)
			).Y

		if math.abs(
			visibleBottomWorld - floorTop
			) > 0.50
		then
			return false,
				"La alfombra debe colocarse sobre el piso."
		end

		return true, nil
	end

	if not isInsideHouseBounds(
		house,
		item
		) then
		return false,
			"El mueble esta atravesando una pared."
	end

	if Geometry.hasStructureOverlap(
		house,
		item
		) then
		return false,
			"El mueble esta atravesando una pared."
	end

	local itemName =
		furnitureRuleName(item)

	local directSupport =
		findAllowedStackSupport(
			folder,
			item,
			ignoreId
		)

	if isStackableFurniture(itemName)
		and directSupport
	then
		-- La mesa es un contacto permitido. La comprobación siguiente
		-- todavía rechaza cualquier otro mueble que choque con el objeto.
	elseif not hasFloorSupport(
		house,
		folder,
		item
		) then
		return false,
			"El mueble no tiene una superficie valida debajo."
	end

	if hasFurnitureCollision(
		folder,
		item,
		ignoreId
		) then
		return false,
			"El mueble esta chocando con otro mueble."
	end

	return true, nil
end

---------------------------------------------------------------------
-- INSTANCIACIÓN
---------------------------------------------------------------------

local function spawnFurniture(
	folder: Folder,
	name: string,
	cf: CFrame,
	id: string?,
	defaultKey: string?
): Instance?
	local template = findTemplate(name)

	if not template then
		return nil
	end

	local item = template:Clone()
	item.Name = trim(name)

	item:SetAttribute(
		"CatalogName",
		trim(name)
	)

	item:SetAttribute(
		"EditableFurnitureId",
		id or HttpService:GenerateGUID(false)
	)

	if defaultKey then
		item:SetAttribute(
			"DefaultTemplateKey",
			defaultKey
		)
	end

	prepFurniture(item)
	item.Parent = folder
	setPivot(item, cf)

	return item
end

local function spawnDefaultFurniture(
	folder: Folder,
	entry: any,
	cf: CFrame,
	id: string?
): Instance?
	if not entry or not entry.Template then
		return nil
	end

	local item = entry.Template:Clone()

	item.Name =
		trim(entry.Name or item.Name)

	item:SetAttribute(
		"CatalogName",
		trim(entry.Name or item.Name)
	)

	item:SetAttribute(
		"EditableFurnitureId",
		id or HttpService:GenerateGUID(false)
	)

	item:SetAttribute(
		"DefaultTemplateKey",
		entry.Key
	)

	prepFurniture(item)
	item.Parent = folder
	setPivot(item, cf)

	return item
end

local function clearFurniture(
	folder: Folder
)
	for _, child in ipairs(
		folder:GetChildren()
		) do
		child:Destroy()
	end
end

---------------------------------------------------------------------
-- MUEBLES PREDETERMINADOS
---------------------------------------------------------------------

local function assignDefaultIds(
	house: Model
)
	local folder =
		furnitureFolderForHouse(house)

	if not folder then
		return
	end

	for _, item in ipairs(
		folder:GetChildren()
		) do
		if not item:GetAttribute(
			"EditableFurnitureId"
			) then
			item:SetAttribute(
				"EditableFurnitureId",
				"default_"
					.. HttpService:GenerateGUID(
						false
					)
			)
		end

		item:SetAttribute(
			"CatalogName",
			item:GetAttribute("CatalogName")
				or item.Name
		)

		prepFurniture(item)
	end
end

local function captureDefaults(
	house: Model
)
	local number =
		houseNumberFromName(house.Name)

	local folder =
		furnitureFolderForHouse(house)

	local houseCFrame =
		select(1, getBuildBounds(house))

	if not number
		or not folder
		or not houseCFrame
	then
		return
	end

	assignDefaultIds(house)

	local defaults = {}

	for index, item in ipairs(
		folder:GetChildren()
		) do
		local cf = getPivot(item)

		if cf then
			local name =
				tostring(
					item:GetAttribute(
						"CatalogName"
					)
					or item.Name
				)

			local key =
				tostring(number)
				.. ":"
				.. tostring(index)
				.. ":"
				.. trim(name)

			local localCFrame =
				houseCFrame:ToObjectSpace(cf)

			item:SetAttribute(
				"DefaultTemplateKey",
				key
			)

			local template = item:Clone()
			template.Parent = nil

			table.insert(defaults, {
				Key = key,
				Name = name,
				LocalCFrame =
					cframeToArray(localCFrame),
				Template = template,
			})
		end
	end

	defaultFurnitureByHouse[number] =
		defaults
end

local function findDefaultEntry(
	number: number,
	key: string?
): any
	if not key then
		return nil
	end

	local defaults =
		defaultFurnitureByHouse[number]

	if not defaults then
		return nil
	end

	for _, entry in ipairs(defaults) do
		if entry.Key == key then
			return entry
		end
	end

	return nil
end
local function findDefaultEntryByName(
	number: number,
	name: any
): any
	local defaults =
		defaultFurnitureByHouse[number]

	if not defaults then
		return nil
	end

	local target = string.lower(trim(tostring(name or "")))
	if target == "" then
		return nil
	end

	for _, entry in ipairs(defaults) do
		if string.lower(trim(tostring(entry.Name or ""))) == target then
			return entry
		end
	end

	return nil
end

---------------------------------------------------------------------
-- SERIALIZACIÓN Y DATASTORE
---------------------------------------------------------------------

local function serializeFurniture(
	house: Model,
	folder: Folder
): {any}
	local items = {}

	local houseCFrame =
		select(1, getBuildBounds(house))

	if not houseCFrame then
		return items
	end

	for _, item in ipairs(
		folder:GetChildren()
		) do
		local id =
			item:GetAttribute(
				"EditableFurnitureId"
			)

		local name =
			item:GetAttribute("CatalogName")
			or item.Name

		local cf = getPivot(item)

		if type(id) == "string"
			and id ~= ""
			and cf
		then
			local localCFrame =
				houseCFrame:ToObjectSpace(cf)

			table.insert(items, {
				Id = id,
				Name = trim(name),
				DefaultKey =
					item:GetAttribute(
						"DefaultTemplateKey"
					),
				LocalCFrame =
					cframeToArray(localCFrame),
			})
		end
	end

	return items
end

local function buildSavePayload(
	player: Player
): any?
	local house, number =
		houseForPlayer(player)

	local folder =
		furnitureFolderForHouse(house)

	if not house or not folder then
		return nil
	end

	return {
		SchemaVersion =
			FURNITURE_SCHEMA_VERSION,

		HouseNumber = number,
		HasSavedLayout = true,
		UpdatedAt = os.time(),

		Items =
			serializeFurniture(
				house,
				folder
			),
	}
end

local function saveFurnitureNow(
	player: Player
): boolean
	local userId = player.UserId
	local waitStarted = os.clock()

	while savingPlayers[userId]
		and os.clock() - waitStarted < 5
	do
		task.wait(0.05)
	end

	local payload = buildSavePayload(player)

	if not payload then
		return false
	end

	savingPlayers[userId] = true

	local success, saveError = pcall(function()
		FURNITURE_STORE:UpdateAsync(
			"user_" .. tostring(userId),
			function()
				return payload
			end
		)
	end)

	savingPlayers[userId] = nil

	if success then
		dirtyPlayers[userId] = nil

		print(string.format(
			"[HouseInteriorsServer] Muebles guardados para %s: %d",
			player.Name,
			#payload.Items
			))

		return true
	end

	warn(
		"[HouseInteriorsServer] No se pudieron guardar los muebles de "
			.. player.Name
			.. ": "
			.. tostring(saveError)
	)

	return false
end

local function scheduleSave(
	player: Player
)
	dirtyPlayers[player.UserId] = true

	local token =
		(pendingSaveTokens[player.UserId] or 0)
		+ 1

	pendingSaveTokens[player.UserId] = token

	task.delay(SAVE_DEBOUNCE, function()
		if not player.Parent then
			return
		end

		if pendingSaveTokens[player.UserId]
			~= token
		then
			return
		end

		pendingSaveTokens[player.UserId] = nil
		saveFurnitureNow(player)
	end)
end

local function loadRawFurnitureData(
	player: Player
): any?
	local success, data = pcall(function()
		return FURNITURE_STORE:GetAsync(
			"user_" .. tostring(player.UserId)
		)
	end)

	if not success then
		warn(
			"[HouseInteriorsServer] No se pudieron cargar los muebles de "
				.. player.Name
		)

		return nil
	end

	return type(data) == "table"
		and data
		or nil
end

local function entryWorldCFrame(
	entry: any,
	schemaVersion: number,
	houseCFrame: CFrame
): CFrame?
	if schemaVersion >= 4 then
		local localCFrame =
			arrayToCFrame(entry.LocalCFrame)

		return localCFrame
			and houseCFrame:ToWorldSpace(
				localCFrame
			)
			or nil
	end

	-- Compatibilidad con el schema v3.
	return arrayToCFrame(entry.CFrame)
end

local function repairUnsupportedStackables(
	house: Model,
	folder: Folder
)
	local houseCFrame, houseSize = getBuildBounds(house)
	if not houseCFrame or not houseSize then
		return
	end

	local floorY = houseCFrame.Position.Y - houseSize.Y * 0.5 + 0.08

	for _, item in ipairs(folder:GetChildren()) do
		if isStackableFurniture(furnitureRuleName(item)) then
			local id = item:GetAttribute("EditableFurnitureId")
			local hasSupport = findAllowedStackSupport(
				folder,
				item,
				type(id) == "string" and id or nil
			) ~= nil

			local boundsCFrame, boundsSize = itemBounds(item)
			local bottomY = boundsCFrame and boundsSize and (boundsCFrame.Position.Y - boundsSize.Y * 0.5) or floorY

			if not hasSupport and bottomY > floorY + 1.2 then
				local pivot = getPivot(item)
				local floorPivot = pivot and floorPivotForItem(item, pivot, floorY)
				if floorPivot then
					setPivot(item, floorPivot)
				end
			end
		end
	end
end

local function loadFurniture(
	player: Player,
	house: Model,
	number: number
)
	local folder =
		furnitureFolderForHouse(house)

	local houseCFrame =
		select(1, getBuildBounds(house))

	if not folder or not houseCFrame then
		return
	end

	local data =
		loadRawFurnitureData(player)

	local schemaVersion =
		type(data) == "table"
		and tonumber(data.SchemaVersion)
		or 0

	local hasSavedLayout =
		type(data) == "table"
		and type(data.Items) == "table"
		and (
			data.HasSavedLayout == true
			or schemaVersion == 3
			or schemaVersion
			== FURNITURE_SCHEMA_VERSION
		)

	clearFurniture(folder)

	if hasSavedLayout then
		local loadedItems: {Instance} = {}

		-- Primero crea todos los muebles. Después valida.
		-- Esto permite restaurar objetos colocados sobre mesas.
		for _, entry in ipairs(data.Items) do
			if type(entry) == "table"
				and type(entry.Name) == "string"
			then
				local worldCFrame =
					entryWorldCFrame(
						entry,
						schemaVersion,
						houseCFrame
					)

				if worldCFrame
					and isValidCFrame(worldCFrame)
				then
					local defaultEntry =
						findDefaultEntry(
							number,
							entry.DefaultKey
						)

					local item =
						defaultEntry
						and spawnDefaultFurniture(
							folder,
							defaultEntry,
							worldCFrame,
							entry.Id
						)
						or spawnFurniture(
							folder,
							entry.Name,
							worldCFrame,
							entry.Id,
							entry.DefaultKey
						)

					if item then
						table.insert(
							loadedItems,
							item
						)
					end
				end
			end
		end

		repairUnsupportedStackables(house, folder)

		for _, item in ipairs(loadedItems) do
			local valid =
				select(
					1,
					placementIsValid(
						house,
						folder,
						item,
						item:GetAttribute(
							"EditableFurnitureId"
						)
					)
				)

			if not valid then
				local defaultKey = item:GetAttribute("DefaultTemplateKey")
				local defaultEntry = type(defaultKey) == "string"
					and findDefaultEntry(number, defaultKey)
					or nil
				defaultEntry = defaultEntry
					or findDefaultEntryByName(
						number,
						item:GetAttribute("CatalogName") or item.Name
					)
				local defaultCFrame = defaultEntry
					and arrayToCFrame(defaultEntry.LocalCFrame)
					or nil

				if defaultEntry and defaultCFrame then
					setPivot(item, houseCFrame:ToWorldSpace(defaultCFrame))
					dirtyPlayers[player.UserId] = true
				else
					warn(
						"[HouseInteriorsServer] Se omitió una posición inválida guardada: "
							.. item.Name
					)
					item:Destroy()
				end
			end
		end
	else
		-- Jugador nuevo: usa la distribución predeterminada.
		for _, entry in ipairs(
			defaultFurnitureByHouse[number]
				or {}
			) do
			local localCFrame =
				arrayToCFrame(entry.LocalCFrame)

			if localCFrame then
				spawnDefaultFurniture(
					folder,
					entry,
					houseCFrame:ToWorldSpace(
						localCFrame
					),
					nil
				)
			end
		end
	end

	loadedPlayers[player.UserId] = true

end

---------------------------------------------------------------------
-- PRESENCIA
---------------------------------------------------------------------

-- GardenPlantingSystem es el único sistema que guarda los cultivos.
-- Esta función existe por compatibilidad, pero no escribe DataStore.
local function publishGardenPreview(
	player: Player,
	immediate: boolean
)
	return
end

local function publishPresence(
	player: Player,
	online: boolean
)
	local _, number = houseForPlayer(player)

	if not number then
		return
	end

	local payload = {
		UserId = player.UserId,
		Name = player.Name,
		DisplayName = player.DisplayName,
		HouseNumber = number,
		Online = online == true,
		UpdatedAt = os.time(),
	}

	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:PublishAsync(
				HOUSE_PRESENCE_CHANNEL,
				payload
			)
		end)

		if not ok then
			warn(
				"[HouseInteriorsServer] No se pudo publicar presencia: "
					.. tostring(err)
			)
		end
	end)
end

---------------------------------------------------------------------
-- LIMPIEZA DE BARRERAS ANTIGUAS
---------------------------------------------------------------------

local function ensureSafetyBounds(
	house: Model
)
	-- Las versiones anteriores creaban cuatro paredes invisibles
	-- con CanCollide=true alrededor de toda la casa.
	--
	-- Esas paredes también cerraban los huecos de:
	-- CasaN > DoorTps > DoorSpawn
	-- CasaN > DoorTps > DoorGarden
	--
	-- HouseDoorPairTravelSystem ya controla los límites y los viajes,
	-- por lo que aquí únicamente eliminamos cualquier barrera antigua.
	local existing =
		house:FindFirstChild(
			"HouseSafetyBounds"
		)

	if existing then
		existing:Destroy()
	end
end

---------------------------------------------------------------------
-- INICIALIZACIÓN DE CASAS
---------------------------------------------------------------------

for _, house in ipairs(
	casasFolder:GetChildren()
	) do
	if house:IsA("Model") then
		captureDefaults(house)
		ensureSafetyBounds(house)
	end
end

casasFolder.ChildAdded:Connect(
	function(child)
		if not child:IsA("Model") then
			return
		end

		task.wait(0.25)
		captureDefaults(child)
		ensureSafetyBounds(child)
	end
)

---------------------------------------------------------------------
-- BRIDGE DE MOCHILA DE MUEBLES V6.7
---------------------------------------------------------------------

local function getFurnitureBackpackBridge(): BindableFunction?
	local bridge =
		ServerStorage:FindFirstChild(
			"FurnitureBackpackBridge"
		)

	if bridge
		and bridge:IsA("BindableFunction") then

		return bridge
	end

	return nil
end

local function backpackBridgeInvoke(
	action: string,
	player: Player,
	furnitureName: string?,
	amount: number?
): (boolean, any)
	local bridge =
		getFurnitureBackpackBridge()

	if not bridge then
		return false,
			"FurnitureBackpackServer no está activo en este Place."
	end

	local ok, a, b =
		pcall(function()
			return bridge:Invoke(
				action,
				player,
				furnitureName,
				amount
			)
		end)

	if not ok then
		warn(
			"[HouseInteriorsServer] FurnitureBackpackBridge falló: "
				.. tostring(a)
		)

		return false,
			"No se pudo acceder a la mochila de muebles."
	end

	return a == true, b
end

---------------------------------------------------------------------
-- CATÁLOGO
---------------------------------------------------------------------

GetCatalog.OnServerInvoke =
	function(player: Player)
		local catalog = {}

		for _, item in ipairs(
			templateFolder:GetChildren()
			) do
			if (
				item:IsA("Model")
				or item:IsA("BasePart")
				)
				and not isHiddenCatalogFurniture(
					item.Name
				)
			then
				local dollars, wood =
				templateCosts(item)

				table.insert(catalog, {
					Name = trim(item.Name),
					Price = dollars,
					Dolares = dollars,
					Madera = wood,
				})
			end
		end

		table.sort(
			catalog,
			function(a, b)
				return a.Name < b.Name
			end
		)

		return catalog
	end

GetHouseInfo.OnServerInvoke =
	function(player: Player)
		local _, number =
		houseForPlayer(player)

		return {
			HouseNumber = number,
			FurnitureLoaded =
			loadedPlayers[player.UserId]
			== true,
			MaxFurniture =
			MAX_FURNITURE_PER_HOUSE,
		}
	end

---------------------------------------------------------------------
-- COMPRAR Y COLOCAR
---------------------------------------------------------------------

PlaceFurniture.OnServerEvent:Connect(
	function(
		player: Player,
		name: any,
		requestedCFrame: any
	)
		if not actionAllowed(
			player,
			"Place",
			PLACE_COOLDOWN
			) then
			return
		end

		if type(name) ~= "string"
			or not isValidCFrame(
				requestedCFrame
			)
		then
			return
		end

		if isHiddenCatalogFurniture(name) then
			notify(
				player,
				"Ese objeto no se puede comprar."
			)
			return
		end

		local house = houseForPlayer(player)
		local folder =
			furnitureFolderForHouse(house)

		local template = findTemplate(name)

		if not house
			or not folder
			or not template
		then
			notify(
				player,
				"No pude encontrar ese mueble."
			)
			return
		end

		if not playerOwnsHouse(player, house) then
			notify(
				player,
				"Este interior no te pertenece."
			)
			return
		end

		if #folder:GetChildren()
			>= MAX_FURNITURE_PER_HOUSE
		then
			notify(
				player,
				"Alcanzaste el limite de muebles de la casa."
			)
			return
		end

		local dollars, wood =
			templateCosts(template)

		local affordable, reason =
			canAfford(
				player,
				dollars,
				wood
			)

		if not affordable then
			notify(
				player,
				reason
					or "No puedes comprar ese mueble."
			)
			return
		end

		local id =
			HttpService:GenerateGUID(false)

		local item =
			spawnFurniture(
				folder,
				name,
				requestedCFrame,
				id,
				nil
			)

		if not item then
			notify(
				player,
				"No pude crear ese mueble."
			)
			return
		end

		local valid, invalidReason =
			placementIsValid(
				house,
				folder,
				item,
				id
			)

		if not valid then
			warn(string.format(
				"[HouseInteriorsServer] Compra rechazada: jugador=%s objeto=%s razon=%s",
				player.Name,
				tostring(name),
				tostring(invalidReason)
				))

			item:Destroy()

			notify(
				player,
				invalidReason
					or "No se puede colocar ahi."
			)
			return
		end

		if not chargePlayer(
			player,
			dollars,
			wood
			) then
			item:Destroy()

			notify(
				player,
				"No se pudo completar la compra."
			)
			return
		end

		scheduleSave(player)

		FurniturePlaced:FireClient(
			player,
			id,
			item.Name
		)

		-- XP sólo por una compra real.
		-- Mover, rotar, guardar o volver a colocar desde backpack NO da XP.
		awardGameActionXP(player, "BuyFurniture", 3)

		notify(
			player,
			"Mueble comprado y colocado."
		)
	end
)

---------------------------------------------------------------------
-- GUARDAR MUEBLE COLOCADO EN BACKPACK
---------------------------------------------------------------------

StorePlacedFurniture.OnServerInvoke =
	function(
		player: Player,
		id: any
	)
	if not actionAllowed(
		player,
		"StorePlaced",
		0.25
		) then
		return false,
			"Espera un momento."
	end

	if type(id) ~= "string"
		or id == ""
	then
		return false,
			"Mueble inválido."
	end

	local house =
		houseForPlayer(player)

	local folder =
		furnitureFolderForHouse(house)

	if not house
		or not folder then

		return false,
			"No encontré tu casa."
	end

	if not playerOwnsHouse(
		player,
		house
		) then
		return false,
			"Este interior no te pertenece."
	end

	local item =
		findFurnitureById(
			folder,
			id
		)

	if not item then
		return false,
			"No encontré el mueble seleccionado."
	end

	local furnitureName =
		trim(
			item:GetAttribute(
				"CatalogName"
			)
			or item.Name
		)

	if furnitureName == ""
		or not findTemplate(
			furnitureName
		) then
		return false,
			"Ese mueble no existe en el catálogo."
	end

	-- Primero guardar online en la mochila.
	-- Solo después quitamos el mueble de la casa.
	local stored,
		storeMessage =
		backpackBridgeInvoke(
			"Add",
			player,
			furnitureName,
			1
		)

	if not stored then
		return false,
			storeMessage
			or "No se pudo guardar el mueble."
	end

	local carried =
		carriedFurnitureForSupportRemoval(
			folder,
			item,
			id
		)

	item:Destroy()

	lowerCarriedFurnitureAfterSupportRemoved(
		house,
		folder,
		carried
	)

	scheduleSave(player)

	return true,
		"Guardaste "
		.. furnitureName
		.. " en tu mochila."
end

---------------------------------------------------------------------
-- COLOCAR MUEBLE DESDE BACKPACK
---------------------------------------------------------------------

PlaceInventoryFurniture.OnServerInvoke =
	function(
		player: Player,
		name: any,
		requestedCFrame: any
	)
	if not actionAllowed(
		player,
		"PlaceInventory",
		PLACE_COOLDOWN
		) then
		return false,
			"Espera un momento."
	end

	if type(name) ~= "string"
		or not isValidCFrame(
			requestedCFrame
		)
	then
		return false,
			"Datos de colocación inválidos."
	end

	name = trim(name)

	local house =
		houseForPlayer(player)

	local folder =
		furnitureFolderForHouse(house)

	local template =
		findTemplate(name)

	if not house
		or not folder
		or not template then

		return false,
			"No pude encontrar ese mueble."
	end

	if not playerOwnsHouse(
		player,
		house
		) then
		return false,
			"Este interior no te pertenece."
	end

	if #folder:GetChildren()
		>= MAX_FURNITURE_PER_HOUSE then

		return false,
			"Alcanzaste el límite de muebles."
	end

	local hasItem,
		currentAmount =
		backpackBridgeInvoke(
			"GetAmount",
			player,
			name,
			1
		)

	if not hasItem
		or (tonumber(currentAmount) or 0) <= 0 then

		return false,
			"No tienes ese mueble en tu mochila."
	end

	local id =
		HttpService:GenerateGUID(false)

	local item =
		spawnFurniture(
			folder,
			name,
			requestedCFrame,
			id,
			nil
		)

	if not item then
		return false,
			"No pude crear el mueble."
	end

	local valid,
		invalidReason =
		placementIsValid(
			house,
			folder,
			item,
			id
		)

	if not valid then
		item:Destroy()

		return false,
			invalidReason
			or "No se puede colocar ahí."
	end

	-- Solo consumir la mochila después de validar la posición.
	local removed,
		removeMessage =
		backpackBridgeInvoke(
			"Remove",
			player,
			name,
			1
		)

	if not removed then
		item:Destroy()

		return false,
			removeMessage
			or "No se pudo usar el mueble de tu mochila."
	end

	scheduleSave(player)

	return true,
		id,
		item.Name
end

---------------------------------------------------------------------
-- MOVER Y ROTAR
---------------------------------------------------------------------

MoveFurniture.OnServerEvent:Connect(
	function(
		player: Player,
		id: any,
		requestedCFrame: any
	)
		if not actionAllowed(
			player,
			"Move",
			MOVE_COOLDOWN
			) then
			return
		end

		if type(id) ~= "string"
			or not isValidCFrame(
				requestedCFrame
			)
		then
			return
		end

		local house = houseForPlayer(player)
		local folder =
			furnitureFolderForHouse(house)

		if not house or not folder then
			return
		end

		if not playerOwnsHouse(player, house) then
			notify(
				player,
				"Este interior no te pertenece."
			)
			return
		end

		local item =
			findFurnitureById(folder, id)

		if not item then
			return
		end

		local oldCFrame = getPivot(item)

		if not oldCFrame then
			return
		end

		local carried = carriedFurnitureForSupportRemoval(folder, item, id)
		local moveDelta = requestedCFrame * oldCFrame:Inverse()

		setPivot(item, requestedCFrame)

		for _, entry in ipairs(carried) do
			if entry.Item and entry.Item.Parent then
				setPivot(entry.Item, moveDelta * entry.OldCFrame)
			end
		end

		local valid, invalidReason =
			placementIsValid(
				house,
				folder,
				item,
				id
			)

		if valid then
			for _, entry in ipairs(carried) do
				if entry.Item and entry.Item.Parent then
					local childId = entry.Item:GetAttribute("EditableFurnitureId")
					local childValid, childReason = placementIsValid(
						house,
						folder,
						entry.Item,
						type(childId) == "string" and childId or nil
					)

					if not childValid then
						valid = false
						invalidReason = childReason
						break
					end
				end
			end
		end

		if not valid then
			setPivot(item, oldCFrame)
			restoreCarriedFurniture(carried)

			notify(
				player,
				invalidReason
					or "No se puede mover el mueble ahi."
			)
			return
		end

		scheduleSave(player)
	end
)

---------------------------------------------------------------------
-- BORRAR
---------------------------------------------------------------------

DeleteFurniture.OnServerEvent:Connect(
	function(
		player: Player,
		id: any
	)
		if not actionAllowed(
			player,
			"Delete",
			DELETE_COOLDOWN
			) then
			return
		end

		if type(id) ~= "string" then
			return
		end

		local house = houseForPlayer(player)
		local folder =
			furnitureFolderForHouse(house)

		if not house or not folder then
			return
		end

		if not playerOwnsHouse(player, house) then
			notify(
				player,
				"Este interior no te pertenece."
			)
			return
		end

		local item =
			findFurnitureById(folder, id)

		if not item then
			notify(
				player,
				"No encontré el mueble seleccionado."
			)
			return
		end

		local refund =
			sellRefundForItem(item)

		if not refund then
			notify(
				player,
				"Este objeto no tiene precio de venta."
			)
			return
		end

		local moneyValue =
			playerMoneyValue(player)

		if not moneyValue then
			notify(
				player,
				"No encontré tu valor de dólares."
			)
			return
		end

		local soldName =
			tostring(
				item:GetAttribute("CatalogName")
				or item.Name
			)

		local carried = carriedFurnitureForSupportRemoval(folder, item, id)

		-- Primero elimina el mueble; después baja objetos apoyados y acredita el dinero.
		-- Todo ocurre en el servidor para evitar ventas falsas.
		item:Destroy()
		lowerCarriedFurnitureAfterSupportRemoved(house, folder, carried)
		moneyValue.Value =
			(tonumber(moneyValue.Value) or 0)
			+ refund

		scheduleSave(player)

		notify(
			player,
			string.format(
				"Vendiste %s por $%d.",
				soldName,
				refund
			)
		)

		print(string.format(
			"[HouseInteriorsServer] %s vendió %s por $%d",
			player.Name,
			soldName,
			refund
			))
	end
)

---------------------------------------------------------------------
-- JUGADORES
---------------------------------------------------------------------

local function assignAndLoadPlayer(
	player: Player
)
	local userId =
		player.UserId

	-- V6.7:
	-- PlayerAdded y HouseNumberChanged podían iniciar dos cargas
	-- al mismo tiempo antes de que loadedPlayers fuera true.
	if loadedPlayers[userId]
		or loadingPlayers[userId] then
		return
	end

	loadingPlayers[userId] = true

	-- Espera al InteriorSlotCoordinator.
	local started = os.clock()

	while player.Parent
		and not tonumber(
			player:GetAttribute("HouseNumber")
		)
			and not tonumber(
				player:GetAttribute(
					"InteriorSlotNumber"
				)
			)
			and os.clock() - started < 10
	do
		task.wait(0.10)
	end

	local house, number =
		houseForPlayer(player)

	if not player.Parent then
		loadingPlayers[userId] = nil
		return
	end

	if not house then
		loadingPlayers[userId] = nil

		warn(
			"[HouseInteriorsServer] No se encontro la casa de "
				.. player.Name
		)
		return
	end

	playerHouse[player.UserId] = number

	-- HouseDoorPairTravelSystem mantiene bloqueadas DoorSpawn y
	-- DoorGarden hasta que HouseInteriorLoaded sea true.
	player:SetAttribute(
		"HouseInteriorLoaded",
		false
	)

	loadFurniture(
		player,
		house,
		number
	)

	-- loadFurniture marca loadedPlayers=true.
	-- Liberamos el guard para futuras reasignaciones reales.
	loadingPlayers[userId] = nil

	player:SetAttribute(
		"HouseInteriorLoaded",
		true
	)

	-- InteriorSlotCoordinator usa Travelling durante la caminata inicial.
	-- No debemos cortarla; cuando ya terminó, habilitamos las puertas.
	if player:GetAttribute(
		"HouseTravelState"
		) ~= "Travelling"
	then
		player:SetAttribute(
			"HouseTravelState",
			"Ready"
		)
	end

	player:SetAttribute(
		"HouseLocation",
		"Interior"
	)

	publishPresence(player, true)
	publishGardenPreview(player, true)

	-- Una sola línea útil por jugador.
	print(
		"[HouseInteriorsServer] "
			.. player.Name
			.. " listo en Casa"
			.. tostring(number)
	)
end

local function registerPlayer(
	player: Player
)
	task.spawn(assignAndLoadPlayer, player)

	player:GetAttributeChangedSignal(
		"HouseNumber"
	):Connect(function()
		local newNumber =
			tonumber(
				player:GetAttribute(
					"HouseNumber"
				)
			)

		if not newNumber then
			return
		end

		local previousNumber =
			playerHouse[player.UserId]

		if loadedPlayers[player.UserId]
			and previousNumber
			and previousNumber ~= newNumber
		then
			-- Guarda todavía usando la casa anterior.
			saveFurnitureNow(player)
			loadedPlayers[player.UserId] = nil
			loadingPlayers[player.UserId] = nil
		end

		playerHouse[player.UserId] = newNumber

		if not loadedPlayers[player.UserId] then
			task.spawn(
				assignAndLoadPlayer,
				player
			)
		end
	end)
end

Players.PlayerAdded:Connect(registerPlayer)

Players.PlayerRemoving:Connect(
	function(player)
		if loadedPlayers[player.UserId] then
			saveFurnitureNow(player)
		end

		publishGardenPreview(player, true)
		publishPresence(player, false)

		player:SetAttribute(
			"HouseInteriorLoaded",
			false
		)

		playerHouse[player.UserId] = nil
		lastActionAt[player.UserId] = nil
		dirtyPlayers[player.UserId] = nil
		pendingSaveTokens[player.UserId] = nil
		loadedPlayers[player.UserId] = nil
		loadingPlayers[player.UserId] = nil
		savingPlayers[player.UserId] = nil
	end
)

for _, player in ipairs(
	Players:GetPlayers()
	) do
	task.spawn(registerPlayer, player)
end

---------------------------------------------------------------------
-- AUTOGUARDADO Y PRESENCIA
---------------------------------------------------------------------

task.spawn(function()
	while task.wait(AUTOSAVE_INTERVAL) do
		for _, player in ipairs(
			Players:GetPlayers()
			) do
			if dirtyPlayers[player.UserId] then
				saveFurnitureNow(player)
			end

			publishPresence(player, true)
			publishGardenPreview(player, false)
		end
	end
end)

game:BindToClose(function()
	local pending = 0

	for _, player in ipairs(
		Players:GetPlayers()
		) do
		pending += 1

		task.spawn(function()
			if loadedPlayers[player.UserId] then
				saveFurnitureNow(player)
			end

			publishGardenPreview(
				player,
				true
			)

			publishPresence(
				player,
				false
			)

			pending -= 1
		end)
	end

	local started = os.clock()

	while pending > 0
		and os.clock() - started < 8
	do
		task.wait(0.05)
	end
end)

print(
	"[HouseInteriorsServer] V6.7 listo: "
		.. "carga única + backpack bridge + muebles + Seats."
)