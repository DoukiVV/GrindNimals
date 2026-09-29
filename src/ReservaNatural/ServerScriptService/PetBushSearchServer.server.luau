--============================================================
-- PET BUSH SEARCH SERVER V2.6 - ESPERA REAL DE 10 SEGUNDOS
--
-- UBICACION:
-- ServerScriptService > PetBushSearchServer
--
-- NECESITA:
-- Workspace > Arbustos
--   Arbusto roble
--   Arbusto abedul
--   Arbusto abeto
--
-- Player.SeedInventory del sistema optimizado de semillas.
--
-- FUNCION:
-- - BUSCAR queda activo hasta volver a presionar el boton.
-- - Mascota va a un arbusto.
-- - Escarba 2 segundos.
-- - Entrega x1-x3 de UNA semilla.
-- - Espera 10 segundos.
-- - Va a otro arbusto.
-- - No toca la camara ni el menu R.
--============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

--============================================================
-- PUENTE TUTORIAL
--============================================================
local function fireTutorialAction(player, actionName, payload)
	if not player or player.Parent ~= Players then return false end
	local tutorialSystem = ReplicatedStorage:FindFirstChild("TutorialSystem")
	local tutorialRemotes = tutorialSystem and tutorialSystem:FindFirstChild("Remotes")
	local action = tutorialRemotes and tutorialRemotes:FindFirstChild("ActionCompleted")
	if action and action:IsA("BindableEvent") then
		action:Fire(player, actionName, payload or {})
		return true
	end
	return false
end

--============================================================
-- CONFIG
--============================================================

local DIG_SECONDS = 2
local NEXT_SEARCH_DELAY = 10

-- La mascota ya NO se irá atravesando medio mapa.
local SEARCH_RADIUS = 42

-- Si el jugador se aleja del arbusto mientras la mascota va hacia él,
-- ese objetivo se cancela y se busca otro cercano.
local TARGET_KEEP_RADIUS = 52
local MAX_PLAYER_TARGET_DISTANCE = 58
local TARGET_TIMEOUT = 24

local REWARD_MIN = 1
local REWARD_MAX = 3

-- Evita elegir inmediatamente el mismo arbusto.
local BUSH_REUSE_COOLDOWN = 25

-- La habilidad natural de cada especie aumenta el peso de
-- sus semillas favoritas. Este era el valor base que dejamos:
-- IMPORTANTE V2.4:
-- Ya NO existe un +20% base inventado.
-- El aumento para las semillas favoritas de cada mascota viene
-- ÚNICAMENTE del pañuelo indicado por el usuario.
-- Sin pañuelo = +0% extra.

-- Tus valores suman 105, así que se usan como pesos relativos.
-- PESOS EXACTOS dados por el usuario.
-- Total = 105, así que Roblox los usa como pesos relativos.
local RARITY_WEIGHTS = {
	Comun = 35,
	Raro = 20,
	["Muy Raro"] = 30,
	Epico = 15,
	Legendario = 5,
}

local SCARF_BONUS = {
	Base = 0,
	Comun = 2,           -- gris
	["Poco comun"] = 4,  -- verde
	Raro = 6,            -- azul
	Epico = 6,           -- morado
	Legendario = 8,      -- dorado
}

--============================================================
-- SEMILLAS
--============================================================

local SEEDS = {
	SandiaNegra = {
		Display = "Sandía Negra",
		Rarity = "Legendario",
		Aliases = {"SandiaNegra", "Sandia Negra", "Sandía Negra"},
	},
	MelonVerde = {
		Display = "Melón Verde",
		Rarity = "Legendario",
		Aliases = {"MelonVerde", "Melon Verde", "Melón Verde"},
	},
	PinaRosa = {
		Display = "Piña Rosa",
		Rarity = "Legendario",
		Aliases = {"PinaRosa", "Pina Rosa", "Piña Rosa"},
	},
	FresaRosa = {
		Display = "Fresa Rosa",
		Rarity = "Legendario",
		Aliases = {"FresaRosa", "Fresa Rosa"},
	},

	Sandia = {
		Display = "Sandía",
		Rarity = "Epico",
		Aliases = {"Sandia", "Sandía"},
	},
	Melon = {
		Display = "Melón",
		Rarity = "Epico",
		Aliases = {"Melon", "Melón"},
	},
	Durian = {
		Display = "Durian",
		Rarity = "Epico",
		Aliases = {"Durian"},
	},
	Cacao = {
		Display = "Cacao",
		Rarity = "Epico",
		Aliases = {"Cacao"},
	},
	TrufaBlanca = {
		Display = "Trufa Blanca",
		Rarity = "Epico",
		Aliases = {"TrufaBlanca", "Trufa Blanca"},
	},
	Mangostan = {
		Display = "Mangostán",
		Rarity = "Epico",
		Aliases = {"Mangostan", "Mangostán"},
	},
	Coco = {
		Display = "Coco",
		Rarity = "Epico",
		Aliases = {"Coco"},
	},
	Calabaza = {
		Display = "Calabaza",
		Rarity = "Epico",
		Aliases = {"Calabaza"},
	},
	Pina = {
		Display = "Piña",
		Rarity = "Epico",
		Aliases = {"Pina", "Piña"},
	},

	Yuca = {
		Display = "Yuca",
		Rarity = "Muy Raro",
		Aliases = {"Yuca"},
	},
	TrufaNegra = {
		Display = "Trufa Negra",
		Rarity = "Muy Raro",
		Aliases = {"TrufaNegra", "Trufa Negra"},
	},
	Lichi = {
		Display = "Lichi",
		Rarity = "Muy Raro",
		Aliases = {"Lichi"},
	},
	FrutaDragon = {
		Display = "Fruta del Dragón",
		Rarity = "Muy Raro",
		Aliases = {"FrutaDragon", "Fruta del Dragon", "Fruta del Dragón"},
	},
	Carambola = {
		Display = "Carambola",
		Rarity = "Muy Raro",
		Aliases = {"Carambola", "Fruta estrella", "FrutaEstrella"},
	},
	Alcachofa = {
		Display = "Alcachofa",
		Rarity = "Muy Raro",
		Aliases = {"Alcachofa"},
	},

	Platano = {
		Display = "Plátano",
		Rarity = "Raro",
		Aliases = {"Platano", "Plátano"},
	},
	Fresa = {
		Display = "Fresa",
		Rarity = "Raro",
		Aliases = {"Fresa"},
	},
	Mango = {
		Display = "Mango",
		Rarity = "Raro",
		Aliases = {"Mango"},
	},
	Granada = {
		Display = "Granada",
		Rarity = "Raro",
		Aliases = {"Granada"},
	},
	Higo = {
		Display = "Higo",
		Rarity = "Raro",
		Aliases = {"Higo"},
	},
	Remolacha = {
		Display = "Remolacha",
		Rarity = "Raro",
		Aliases = {"Remolacha"},
	},
	LechugaMorada = {
		Display = "Lechuga Morada",
		Rarity = "Raro",
		Aliases = {"LechugaMorada", "Lechuga Morada"},
	},
	ColMorada = {
		Display = "Col Morada",
		Rarity = "Raro",
		Aliases = {"ColMorada", "Col Morada"},
	},

	Zanahoria = {
		Display = "Zanahoria",
		Rarity = "Comun",
		Aliases = {"Zanahoria"},
	},
	Papa = {
		Display = "Papa",
		Rarity = "Comun",
		Aliases = {"Papa"},
	},
	Lechuga = {
		Display = "Lechuga",
		Rarity = "Comun",
		Aliases = {"Lechuga"},
	},
	Col = {
		Display = "Col",
		Rarity = "Comun",
		Aliases = {"Col"},
	},
	Cebolla = {
		Display = "Cebolla",
		Rarity = "Comun",
		Aliases = {"Cebolla"},
	},
	Manzana = {
		Display = "Manzana",
		Rarity = "Comun",
		Aliases = {"Manzana"},
	},
	Naranja = {
		Display = "Naranja",
		Rarity = "Comun",
		Aliases = {"Naranja"},
	},
	Trigo = {
		Display = "Trigo",
		Rarity = "Comun",
		Aliases = {"Trigo"},
	},
}

local BUSH_SEEDS = {
	Roble = {
		"SandiaNegra",
		"Sandia",
		"Melon",
		"Durian",
		"Platano",
		"Fresa",
		"Mango",
		"Zanahoria",
		"Papa",
		"Lechuga",
		"Col",
		"Cebolla",
		"Manzana",
		"Naranja",
		"Trigo",
	},

	Abedul = {
		"MelonVerde",
		"Cacao",
		"TrufaBlanca",
		"Mangostan",
		"Yuca",
		"TrufaNegra",
		"Lichi",
		"Granada",
		"Higo",
		"Remolacha",
	},

	Abeto = {
		"PinaRosa",
		"FresaRosa",
		"Coco",
		"Calabaza",
		"Pina",
		"FrutaDragon",
		"Carambola",
		"Alcachofa",
		"LechugaMorada",
		"ColMorada",
	},
}

local function printExactDropPools()
	print(
		"[PetBushSearch] POOLS EXACTOS |",
		"Roble:", #BUSH_SEEDS.Roble,
		"| Abedul:", #BUSH_SEEDS.Abedul,
		"| Abeto:", #BUSH_SEEDS.Abeto
	)

	print(
		"[PetBushSearch] RAREZAS | Comun 35 | Raro 20 | Muy Raro 30 | Epico 15 | Legendario 5"
	)

	print(
		"[PetBushSearch] CANTIDAD POR ARBUSTO | x1-x3"
	)

	print(
		"[PetBushSearch] PAÑUELOS | Base +0 | Gris +2 | Verde +4 | Azul +6 | Morado +6 | Dorado +8 | SOLO semillas favoritas"
	)
end

printExactDropPools()

--============================================================
-- HABILIDADES
--============================================================

-- Semillas favoritas EXACTAS.
-- El pañuelo aumenta SOLAMENTE la probabilidad de estas semillas.
-- No altera la probabilidad base de la rareza.
local PET_FAVORITES = {
	Perro = {
		Manzana = true,
		Naranja = true,
		Cebolla = true,
	},

	Gato = {
		Lechuga = true,
		Col = true,
		Trigo = true,
	},

	Conejo = {
		Remolacha = true,
		ColMorada = true,
		LechugaMorada = true,
	},

	Perico = {
		Platano = true,
		Mango = true,
		Granada = true,
	},

	Tortuga = {
		FrutaDragon = true,
		Carambola = true,
		Lichi = true,
	},

	Hamster = {
		TrufaNegra = true,
		Alcachofa = true,
		Yuca = true,
	},

	Huron = {
		Sandia = true,
		Melon = true,
		Calabaza = true,
	},

	PezDorado = {
		TrufaBlanca = true,
		Pina = true,
		Mangostan = true,
	},

	Oveja = {
		MelonVerde = true,
		SandiaNegra = true,
	},
}

--============================================================
-- REMOTES
--============================================================

local system =
	ReplicatedStorage:FindFirstChild(
		"PetBushSearchSystem"
	)

if not system then
	system =
		Instance.new(
			"Folder"
		)

	system.Name =
		"PetBushSearchSystem"

	system.Parent =
		ReplicatedStorage
end

local function getRemoteEvent(name)
	local remote =
		system:FindFirstChild(name)

	if
		remote
		and remote:IsA("RemoteEvent")
	then
		return remote
	end

	if remote then
		remote:Destroy()
	end

	remote =
		Instance.new("RemoteEvent")

	remote.Name =
		name

	remote.Parent =
		system

	return remote
end

local function getRemoteFunction(name)
	local remote =
		system:FindFirstChild(name)

	if
		remote
		and remote:IsA("RemoteFunction")
	then
		return remote
	end

	if remote then
		remote:Destroy()
	end

	remote =
		Instance.new("RemoteFunction")

	remote.Name =
		name

	remote.Parent =
		system

	return remote
end

local ToggleSearch =
	getRemoteFunction(
		"ToggleSearch"
	)

local ArrivedAtBush =
	getRemoteEvent(
		"ArrivedAtBush"
	)

local RewardFound =
	getRemoteEvent(
		"RewardFound"
	)

local SearchStatus =
	getRemoteEvent(
		"SearchStatus"
	)

--============================================================
-- HELPERS
--============================================================

local random =
	Random.new()

local function normalize(value)
	local text =
		tostring(
			value
			or ""
		)

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

	text =
		text:lower()

	text =
		text:gsub(
			"[%s_%-%./]+",
			""
		)

	return text
end

local function canonicalPetType(value)
	local key =
		normalize(
			value
		)

	if
		key == "pajarillo"
		or key == "perico"
	then
		return "Perico"
	elseif key == "pezdorado" then
		return "PezDorado"
	elseif
		key == "ovejaderosario"
		or key == "oveja"
	then
		return "Oveja"
	elseif key == "huron" then
		return "Huron"
	elseif key == "hamster" then
		return "Hamster"
	elseif key == "tortuga" then
		return "Tortuga"
	elseif key == "conejo" then
		return "Conejo"
	elseif key == "gato" then
		return "Gato"
	elseif key == "perro" then
		return "Perro"
	elseif
		key == "huevobrizabelle"
		or key == "huevomascota"
	then
		return "HuevoBrizabelle"
	end

	return tostring(
		value
			or ""
	)
end

local function canonicalTier(value)
	local key =
		normalize(
			value
		)

	if
		key == ""
		or key == "base"
	then
		return "Base"
	elseif
		key == "comun"
		or key == "gris"
	then
		return "Comun"
	elseif
		key == "pococomun"
		or key == "verde"
	then
		return "Poco comun"
	elseif
		key == "raro"
		or key == "azul"
	then
		return "Raro"
	elseif
		key == "epico"
		or key == "morado"
	then
		return "Epico"
	elseif
		key == "legendario"
		or key == "dorado"
	then
		return "Legendario"
	end

	return "Base"
end

local function getPlayerRoot(player)
	local character =
		player.Character

	return
		character
		and character:FindFirstChild(
			"HumanoidRootPart"
		)
end

local function getServerPet(player)
	for _, model in ipairs(
		Workspace:GetChildren()
		) do
		if
			model:IsA("Model")
			and model:GetAttribute(
				"ClientPetVisual"
			) ~= true
				and model:GetAttribute(
					"Owner"
				) == player.UserId
				and model:GetAttribute(
					"Resting"
				) ~= true
				and typeof(
					model:GetAttribute(
						"PetType"
					)
				) == "string"
		then
			return model
		end
	end

	return nil
end

local function getPetTypeAndTier(player)
	local pet =
		getServerPet(
			player
		)

	if not pet then
		return nil, nil, nil
	end

	local petType =
		canonicalPetType(
			pet:GetAttribute(
				"PetType"
			)
		)

	local tier =
		pet:GetAttribute(
			"PetTier"
		)
		or pet:GetAttribute(
			"Tier"
		)
		or pet:GetAttribute(
			"Rarity"
		)
		or pet:GetAttribute(
			"Rareza"
		)
		or player:GetAttribute(
			"SelectedBackpackPetTier"
		)
		or "Base"

	return
		pet,
		petType,
		canonicalTier(
			tier
		)
end

local function getObjectPosition(object)
	if
		not object
		or not object.Parent
	then
		return nil
	end

	if object:IsA("BasePart") then
		return object.Position
	elseif object:IsA("Model") then
		return object:GetPivot().Position
	end

	return nil
end

local function getObjectSize(object)
	if object:IsA("BasePart") then
		return object.Size
	elseif object:IsA("Model") then
		local _, size =
			object:GetBoundingBox()

		return size
	end

	return Vector3.new(2, 2, 2)
end

local function flatUnit(vector, fallback)
	local flat =
		Vector3.new(
			vector.X,
			0,
			vector.Z
		)

	if flat.Magnitude > 0.001 then
		return flat.Unit
	end

	return
		fallback
		or Vector3.new(
			1,
			0,
			0
		)
end

--============================================================
-- ARBUSTOS
--============================================================

local bushesRoot =
	Workspace:WaitForChild(
		"Arbustos"
	)

local bushes = {}

local function classifyBushGroup(object)
	local key =
		normalize(
			object.Name
		)

	if
		key:find(
			"roble",
			1,
			true
		)
	then
		return "Roble"
	elseif
		key:find(
			"abedul",
			1,
			true
		)
			or key:find(
				"abeldul",
				1,
				true
			)
	then
		return "Abedul"
	elseif
		key:find(
			"abeto",
			1,
			true
		)
	then
		return "Abeto"
	end

	return nil
end

local function hasPart(object)
	if object:IsA("BasePart") then
		return true
	end

	return
		object:FindFirstChildWhichIsA(
			"BasePart",
			true
		)
		~= nil
end

local function scanBushes()
	table.clear(
		bushes
	)

	local counts = {
		Roble = 0,
		Abedul = 0,
		Abeto = 0,
	}

	for _, group in ipairs(
		bushesRoot:GetChildren()
		) do
		local bushType =
			classifyBushGroup(
				group
			)

		if bushType then
			local addedModel =
				false

			for _, child in ipairs(
				group:GetChildren()
				) do
				if
					child:IsA("Model")
					and hasPart(
						child
					)
				then
					table.insert(
						bushes,
						{
							Object = child,
							Type = bushType,
						}
					)

					counts[bushType] +=
						1

					addedModel =
						true
				end
			end

			if not addedModel then
				for _, child in ipairs(
					group:GetChildren()
					) do
					if child:IsA("BasePart") then
						table.insert(
							bushes,
							{
								Object = child,
								Type = bushType,
							}
						)

						counts[bushType] +=
							1
					end
				end
			end

			if
				not addedModel
				and #group:GetChildren() == 0
				and (
					group:IsA("Model")
						or group:IsA("BasePart")
				)
					and hasPart(
						group
					)
			then
				table.insert(
					bushes,
					{
						Object = group,
						Type = bushType,
					}
				)

				counts[bushType] +=
					1
			end
		end
	end

	print(
		"[PetBushSearch] Arbustos | total:",
		#bushes,
		"| Roble:",
		counts.Roble,
		"| Abedul:",
		counts.Abedul,
		"| Abeto:",
		counts.Abeto
	)
end

scanBushes()

bushesRoot.ChildAdded:Connect(function()
	task.delay(
		0.25,
		scanBushes
	)
end)

bushesRoot.ChildRemoved:Connect(function()
	task.delay(
		0.25,
		scanBushes
	)
end)

--============================================================
-- TEMPLATES DE SEMILLA
--============================================================

local seedFolder =
	ServerStorage
	:WaitForChild("Item")
	:WaitForChild("Semillas")

local aliasToSeed = {}

for seedKey, data in pairs(
	SEEDS
	) do
	aliasToSeed[
	normalize(
		seedKey
	)
	] =
		seedKey

	for _, alias in ipairs(
		data.Aliases
			or {}
		) do
		aliasToSeed[
		normalize(
			alias
		)
		] =
			seedKey
	end
end

local function stripSeedPrefix(value)
	local key =
		normalize(
			value
		)

	if
		key:sub(
			1,
			9
		) == "semillade"
	then
		key =
			key:sub(
				10
			)
	elseif
		key:sub(
			1,
			7
		) == "semilla"
	then
		key =
			key:sub(
				8
			)
	end

	return key
end

local function seedKeyFromTool(tool)
	if not tool:IsA("Tool") then
		return nil
	end

	for _, value in ipairs({
		tool:GetAttribute("SeedCropName"),
		tool:GetAttribute("ItemName"),
		tool:GetAttribute("BackpackDisplayName"),
		tool.Name,
		}) do
		if typeof(value) == "string" then
			local key =
				stripSeedPrefix(
					value
				)

			local exact =
				aliasToSeed[
			key
			]

			if exact then
				return exact
			end
		end
	end

	return nil
end

--============================================================
-- NOMBRES REALES DE TOOLS EN TU ServerStorage
--
-- La captura confirma que varias semillas NO se llaman simplemente
-- "Semilla<Nombre>":
--   BrotePlatanero
--   EsporasTrufaBlanca
--   EsporasTrufaNegra
--   SemillaDeDurian
--   SemillaDeFrutadelDragon
--   SemillaMangostán
--   SemillaPiña
-- etc.
--
-- Por eso V2.2 busca primero por estos nombres reales y después
-- usa atributos/normalización como respaldo.
--============================================================

local TEMPLATE_NAME_ALIASES = {
	Platano = {
		"BrotePlatanero",
		"SemillaPlatano",
		"SemillaPlátano",
	},

	TrufaBlanca = {
		"EsporasTrufaBlanca",
		"SemillaTrufaBlanca",
	},

	TrufaNegra = {
		"EsporasTrufaNegra",
		"SemillaTrufaNegra",
	},

	Durian = {
		"SemillaDeDurian",
		"SemillaDurian",
	},

	FrutaDragon = {
		"SemillaDeFrutadelDragon",
		"SemillaDeFrutaDelDragon",
		"SemillaFrutaDragon",
	},

	Mango = {
		"SemillaMango",
		"SemillaDeMango",
	},

	Mangostan = {
		"SemillaMangostán",
		"SemillaMangostan",
	},

	Pina = {
		"SemillaPiña",
		"SemillaPina",
	},

	Melon = {
		"SemillaMelon",
		"SemillaMelón",
	},

	MelonVerde = {
		"SemillaMelonVerde",
		"SemillaMelónVerde",
	},

	Alcachofa = {"SemillaAlcachofa"},
	Cacao = {"SemillaCacao"},
	Calabaza = {"SemillaCalabaza"},
	Carambola = {"SemillaCarambola"},
	Cebolla = {"SemillaCebolla"},
	Col = {"SemillaCol"},
	ColMorada = {"SemillaColMorada"},
	Coco = {"SemillaCoco"},
	Fresa = {"SemillaFresa"},
	Granada = {"SemillaGranada"},
	Higo = {"SemillaHigo"},
	Lechuga = {"SemillaLechuga"},
	LechugaMorada = {"SemillaLechugaMorada"},
	Lichi = {"SemillaLichi"},
	Manzana = {"SemillaManzana"},
	Naranja = {"SemillaNaranja"},
	Papa = {"SemillaPapa"},
	Remolacha = {"SemillaRemolacha"},
	Sandia = {"SemillaSandia", "SemillaSandía"},
	SandiaNegra = {"SemillaSandiaNegra", "SemillaSandíaNegra"},
	Trigo = {"SemillaTrigo"},
	Yuca = {"SemillaYuca"},
	Zanahoria = {"SemillaZanahoria"},

	-- Solo se usa si realmente existe en ServerStorage.
	-- NO hacemos pasar FresaBlanca por FresaRosa.
	FresaRosa = {"SemillaFresaRosa"},

	PinaRosa = {
		"SemillaPiñaRosa",
		"SemillaPinaRosa",
	},
}

local templateCache = {}

local function findSeedTemplate(seedKey)
	local cached =
		templateCache[
	seedKey
	]

	if
		cached
		and cached.Parent
	then
		return cached
	end

	-- 1) Nombre REAL conocido.
	for _, realName in ipairs(
		TEMPLATE_NAME_ALIASES[
		seedKey
		]
			or {}
		) do
		local direct =
			seedFolder:FindFirstChild(
				realName,
				true
			)

		if
			direct
			and direct:IsA("Tool")
		then
			templateCache[
			seedKey
			] =
				direct

			return direct
		end
	end

	-- 2) Atributos del Tool / nombres normalizados.
	for _, object in ipairs(
		seedFolder:GetDescendants()
		) do
		if
			object:IsA("Tool")
			and seedKeyFromTool(
				object
			) == seedKey
		then
			templateCache[
			seedKey
			] =
				object

			return object
		end
	end

	-- 3) Respaldo por nombre normalizado de los aliases reales.
	local wanted = {}

	for _, realName in ipairs(
		TEMPLATE_NAME_ALIASES[
		seedKey
		]
			or {}
		) do
		wanted[
		normalize(
			realName
		)
		] =
			true
	end

	for _, object in ipairs(
		seedFolder:GetDescendants()
		) do
		if
			object:IsA("Tool")
			and wanted[
			normalize(
				object.Name
			)
			]
		then
			templateCache[
			seedKey
			] =
				object

			return object
		end
	end

	return nil
end

local function printTemplateStatus()
	local found =
		0

	local missing = {}

	for seedKey, data in pairs(
		SEEDS
		) do
		if findSeedTemplate(seedKey) then
			found +=
				1
		else
			table.insert(
				missing,
				data.Display
			)
		end
	end

	table.sort(
		missing
	)

	print(
		"[PetBushSearch] TEMPLATES | encontrados:",
		found,
		"| faltan:",
		#missing
	)

	if #missing > 0 then
		warn(
			"[PetBushSearch] TEMPLATES FALTANTES:",
			table.concat(
				missing,
				", "
			)
		)
	end
end

printTemplateStatus()

--============================================================
-- INVENTARIO OPTIMIZADO
--============================================================
--============================================================

local function awardSeed(
	player,
	seedKey,
	amount
)
	--========================================================
	-- COMPATIBILIDAD REAL CON SeedInventorySaveServer V9
	--
	-- V9 NO usa Player.SeedInventory.
	-- V9 guarda las semillas como Tools APILADOS x1-x99 dentro
	-- del Backpack/Character usando:
	--
	-- SeedStackQuantity
	-- Cantidad
	-- IsSeed
	-- ItemType
	-- ItemName
	-- SeedCropName
	--
	-- Por eso esta recompensa crea UN SOLO Tool x1-x3 y V9
	-- automáticamente lo detecta, compacta y guarda.
	--========================================================

	if
		player:GetAttribute(
			"SeedInventoryLoaded"
		) ~= true
	then
		return
			false,
			"Tu inventario de semillas todavía está cargando."
	end

	local data =
		SEEDS[
	seedKey
	]

	if not data then
		return
			false,
			"Semilla no configurada."
	end

	local template =
		findSeedTemplate(
			seedKey
		)

	if not template then
		return
			false,
			"Falta el Tool de "
			.. data.Display
			.. " en ServerStorage > Item > Semillas."
	end

	local backpack =
		player:FindFirstChildOfClass(
			"Backpack"
		)
		or player:WaitForChild(
			"Backpack",
			5
		)

	if not backpack then
		return
			false,
			"No se encontró el Backpack del jugador."
	end

	amount =
		math.clamp(
			math.floor(
				tonumber(
					amount
				)
				or 1
			),
			1,
			99
		)

	-- Clonamos UNA sola semilla física.
	-- El atributo SeedStackQuantity representa la cantidad lógica.
	local rewardTool =
		template:Clone()

	local itemName =
		rewardTool:GetAttribute(
			"ItemName"
		)

	if
		typeof(itemName) ~= "string"
		or itemName == ""
	then
		itemName =
			template:GetAttribute(
				"ItemName"
			)
	end

	if
		typeof(itemName) ~= "string"
		or itemName == ""
	then
		itemName =
			template.Name
	end

	local cropName =
		template:GetAttribute(
			"SeedCropName"
		)

	if
		typeof(cropName) ~= "string"
		or cropName == ""
	then
		cropName =
			seedKey
	end

	rewardTool:SetAttribute(
		"ItemName",
		itemName
	)

	rewardTool:SetAttribute(
		"ItemType",
		"Cultivo"
	)

	rewardTool:SetAttribute(
		"IsSeed",
		true
	)

	rewardTool:SetAttribute(
		"SeedCropName",
		cropName
	)

	rewardTool:SetAttribute(
		"SeedStackQuantity",
		amount
	)

	rewardTool:SetAttribute(
		"Cantidad",
		amount
	)

	rewardTool:SetAttribute(
		"SeedRarity",
		data.Rarity
	)

	local display =
		rewardTool:GetAttribute(
			"BackpackDisplayName"
		)

	if
		typeof(display) ~= "string"
		or display == ""
	then
		rewardTool:SetAttribute(
			"BackpackDisplayName",
			"Semilla "
				.. data.Display
		)
	end

	-- Parent AL FINAL:
	-- SeedSaveV9 escucha Backpack.ChildAdded y, al aparecer,
	-- registra el stack, actualiza el total, lo compacta y lo guarda.
	rewardTool.Parent =
		backpack

	-- Atributo auxiliar para UI/refresco; no interviene en DataStore.
	player:SetAttribute(
		"SeedInventoryRevision",
		(
			tonumber(
				player:GetAttribute(
					"SeedInventoryRevision"
				)
			)
				or 0
		)
			+ 1
	)

	print(
		"[PetBushSearch] STACK ENTREGADO A V9 |",
		player.Name,
		"|",
		template.Name,
		"| x"
			.. tostring(
				amount
			)
	)

	return
		true,
		template.TextureId
		or ""
end

--============================================================
-- GUARDADO
--
-- No hacemos SetAsync/UpdateAsync aquí.
-- SeedInventorySaveServer V9 escucha Backpack.ChildAdded y
-- automáticamente:
-- 1. registra el nuevo stack,
-- 2. actualiza su conteo lógico,
-- 3. compacta,
-- 4. guarda con su propio debounce.
--
-- Esto evita duplicar requests al DataStore.
--============================================================

local function queueSeedSave(_player)
	-- Intencionalmente vacío.
	-- El guardado pertenece a SeedInventorySaveServer V9.
end

--============================================================
-- PROBABILIDADES
--============================================================

local function chooseRewardSeed(
	bushType,
	petType,
	petTier
)
	local seedList =
		BUSH_SEEDS[
	bushType
	]

	if
		not seedList
		or #seedList == 0
	then
		return nil
	end

	--========================================================
	-- PASO 1: AGRUPAR SOLO SEMILLAS REALES POR RAREZA
	--========================================================

	local byRarity = {}

	for _, seedKey in ipairs(
		seedList
		) do
		local data =
			SEEDS[
		seedKey
		]

		if
			data
			and findSeedTemplate(
				seedKey
			)
		then
			byRarity[
			data.Rarity
			] =
				byRarity[
			data.Rarity
			]
				or {}

			table.insert(
				byRarity[
				data.Rarity
				],
				seedKey
			)
		end
	end

	--========================================================
	-- PASO 2: ELEGIR RAREZA
	--
	-- Los pesos de rareza son SIEMPRE:
	-- Comun       35
	-- Raro        20
	-- Muy Raro    30
	-- Epico       15
	-- Legendario   5
	--
	-- El pañuelo NO modifica este roll.
	--
	-- Como suman 105 y además cada tipo de arbusto no tiene
	-- todas las rarezas, se normalizan entre las rarezas que
	-- realmente existen en ese arbusto.
	--========================================================

	local rarityOrder = {
		"Comun",
		"Raro",
		"Muy Raro",
		"Epico",
		"Legendario",
	}

	local totalRarityWeight =
		0

	local rarityRollTable = {}

	for _, rarity in ipairs(
		rarityOrder
		) do
		local candidates =
			byRarity[
		rarity
		]

		if
			candidates
			and #candidates > 0
		then
			local weight =
				RARITY_WEIGHTS[
			rarity
			]
				or 0

			if weight > 0 then
				totalRarityWeight +=
					weight

				table.insert(
					rarityRollTable,
					{
						Rarity =
							rarity,
						EndWeight =
							totalRarityWeight,
					}
				)
			end
		end
	end

	if totalRarityWeight <= 0 then
		return nil
	end

	local rarityRoll =
		random:NextNumber(
			0,
			totalRarityWeight
		)

	local chosenRarity =
		rarityRollTable[
	#rarityRollTable
	].Rarity

	for _, entry in ipairs(
		rarityRollTable
		) do
		if
			rarityRoll
			<= entry.EndWeight
		then
			chosenRarity =
				entry.Rarity

			break
		end
	end

	local candidates =
		byRarity[
	chosenRarity
	]

	if
		not candidates
		or #candidates == 0
	then
		return nil
	end

	--========================================================
	-- PASO 3: ELEGIR SEMILLA DENTRO DE ESA RAREZA
	--
	-- Aquí SÍ entra la habilidad de la mascota.
	--
	-- Ejemplo:
	-- Gato = Lechuga, Col, Trigo.
	--
	-- Si el Gato tiene pañuelo dorado (+8%), esas semillas
	-- reciben 1.08 de peso, mientras las demás reciben 1.00.
	--
	-- Esto NO convierte una Común en más probable que una
	-- Legendaria: la rareza ya fue elegida en el paso anterior.
	--========================================================

	local favorites =
		PET_FAVORITES[
	canonicalPetType(
		petType
	)
	]
		or {}

	local scarfBonus =
		SCARF_BONUS[
	canonicalTier(
		petTier
	)
	]
		or 0

	local totalSeedWeight =
		0

	local seedRollTable = {}

	for _, seedKey in ipairs(
		candidates
		) do
		local weight =
			1

		if favorites[seedKey] then
			weight *=
				1
				+ (
					scarfBonus
					/ 100
				)
		end

		totalSeedWeight +=
			weight

		table.insert(
			seedRollTable,
			{
				SeedKey =
					seedKey,
				EndWeight =
					totalSeedWeight,
				Favorite =
					favorites[
				seedKey
				] == true,
			}
		)
	end

	local seedRoll =
		random:NextNumber(
			0,
			totalSeedWeight
		)

	local chosen =
		seedRollTable[
	#seedRollTable
	]

	for _, entry in ipairs(
		seedRollTable
		) do
		if
			seedRoll
			<= entry.EndWeight
		then
			chosen =
				entry

			break
		end
	end

	print(
		"[PetBushSearch] ROLL |",
		bushType,
		"| rareza:",
		chosenRarity,
		"| semilla:",
		SEEDS[
		chosen.SeedKey
		].Display,
		"| favorita:",
		tostring(
			chosen.Favorite
		),
		"| pañuelo:+"
			.. tostring(
				scarfBonus
			)
			.. "%"
	)

	return
		chosen.SeedKey
end

--============================================================
-- ESTADO
--============================================================

local states = {}

local function getState(player)
	local state =
		states[
	player
	]

	if state then
		return state
	end

	state = {
		Active = false,
		Token = 0,
		Target = nil,
		TargetType = nil,
		TargetPosition = nil,
		LookPosition = nil,
		AssignedAt = 0,
		Digging = false,
		Waiting = false,
		RecentBushes = {},
		LastArrivalAt = 0,
	}

	states[
	player
	] =
		state

	return state
end

local function setCommonAttributes(
	player,
	state
)
	player:SetAttribute(
		"PetBushSearchActive",
		state.Active
	)

	player:SetAttribute(
		"PetBushSearchToken",
		state.Token
	)

	player:SetAttribute(
		"PetBushDigging",
		state.Digging
	)

	player:SetAttribute(
		"PetBushWaiting",
		state.Waiting
	)
end

local function clearTarget(
	player,
	state
)
	state.Target =
		nil

	state.TargetType =
		nil

	state.TargetPosition =
		nil

	state.LookPosition =
		nil

	state.Digging =
		false

	player:SetAttribute(
		"PetBushTargetPosition",
		nil
	)

	player:SetAttribute(
		"PetBushLookPosition",
		nil
	)

	player:SetAttribute(
		"PetBushTargetType",
		nil
	)

	player:SetAttribute(
		"PetBushDigging",
		false
	)
end

local function disableSearch(
	player,
	message
)
	local state =
		getState(
			player
		)

	state.Active =
		false

	state.Waiting =
		false

	state.Token +=
		1

	clearTarget(
		player,
		state
	)

	setCommonAttributes(
		player,
		state
	)

	if message then
		SearchStatus:FireClient(
			player,
			message
		)
	end
end

local function cleanupRecent(
	state
)
	local now =
		os.clock()

	for bush, expiresAt in pairs(
		state.RecentBushes
		) do
		if
			not bush.Parent
			or expiresAt <= now
		then
			state.RecentBushes[
			bush
			] =
				nil
		end
	end
end

local function getSearchPoint(
	playerRoot,
	bush
)
	local bushPosition =
		getObjectPosition(
			bush
		)

	if not bushPosition then
		return nil, nil
	end

	local size =
		getObjectSize(
			bush
		)

	local radius =
		math.clamp(
			math.max(
				size.X,
				size.Z
			)
			* 0.5,
			0.7,
			2.8
		)

	local away =
		flatUnit(
			playerRoot.Position
			- bushPosition,
			Vector3.new(
				1,
				0,
				0
			)
		)

	local target =
		bushPosition
		+ away
		* (
			radius
			+ 0.85
		)

	return
		Vector3.new(
			target.X,
			bushPosition.Y,
			target.Z
		),
		bushPosition
end

local function chooseBush(
	player,
	state
)
	cleanupRecent(
		state
	)

	local root =
		getPlayerRoot(
			player
		)

	if not root then
		return nil
	end

	local best =
		nil

	local bestDistance =
		math.huge

	local fallback =
		nil

	local fallbackDistance =
		math.huge

	for _, entry in ipairs(
		bushes
		) do
		local bush =
			entry.Object

		if
			bush
			and bush.Parent
		then
			local position =
				getObjectPosition(
					bush
				)

			if position then
				local distance =
					(
						root.Position
						- position
					).Magnitude

				if
					distance
					<= SEARCH_RADIUS
				then
					if distance < fallbackDistance then
						fallback =
							entry

						fallbackDistance =
							distance
					end

					if
						not state.RecentBushes[
						bush
						]
							and distance
							< bestDistance
					then
						best =
							entry

						bestDistance =
							distance
					end
				end
			end
		end
	end

	return
		best
		or fallback
end

local assignNextBush

assignNextBush =
	function(
		player,
		state
	)
	if
		not state.Active
		or player.Parent
		~= Players
	then
		return
	end

	-- V2.6 FIX CRITICO:
	-- Durante la espera de 10 segundos NO se puede asignar otro arbusto,
	-- aunque exista un task.delay viejo, un reintento o cualquier otra
	-- llamada pendiente a assignNextBush.
	if state.Waiting == true then
		return
	end

	if
		player:GetAttribute(
			"PetCareMenuOpen"
		) == true
	then
		task.delay(
			1,
			function()
				if
					player.Parent == Players
					and state.Active
				then
					assignNextBush(
						player,
						state
					)
				end
			end
		)

		return
	end

	local pet, petType =
		getPetTypeAndTier(
			player
		)

	if not pet then
		SearchStatus:FireClient(
			player,
			"Modo BUSCAR activo. Saca una mascota para continuar."
		)

		task.delay(
			2,
			function()
				if
					player.Parent == Players
					and state.Active
				then
					assignNextBush(
						player,
						state
					)
				end
			end
		)

		return
	end

	if petType == "HuevoBrizabelle" then
		SearchStatus:FireClient(
			player,
			"El huevo todavía no puede buscar semillas."
		)

		task.delay(
			2,
			function()
				if
					player.Parent == Players
					and state.Active
				then
					assignNextBush(
						player,
						state
					)
				end
			end
		)

		return
	end

	local entry =
		chooseBush(
			player,
			state
		)

	if not entry then
		SearchStatus:FireClient(
			player,
			"No hay arbustos cerca. El modo BUSCAR sigue activo."
		)

		task.delay(
			3,
			function()
				if
					player.Parent == Players
					and state.Active
				then
					assignNextBush(
						player,
						state
					)
				end
			end
		)

		return
	end

	local root =
		getPlayerRoot(
			player
		)

	if not root then
		return
	end

	local targetPosition, lookPosition =
		getSearchPoint(
			root,
			entry.Object
		)

	if not targetPosition then
		return
	end

	state.Token +=
		1

	state.Target =
		entry.Object

	state.TargetType =
		entry.Type

	state.TargetPosition =
		targetPosition

	state.LookPosition =
		lookPosition

	state.AssignedAt =
		os.clock()

	state.Digging =
		false

	state.Waiting =
		false

	setCommonAttributes(
		player,
		state
	)

	player:SetAttribute(
		"PetBushTargetPosition",
		targetPosition
	)

	player:SetAttribute(
		"PetBushLookPosition",
		lookPosition
	)

	player:SetAttribute(
		"PetBushTargetType",
		entry.Type
	)

	print(
		"[PetBushSearch] OBJETIVO |",
		player.Name,
		"|",
		entry.Type,
		"| token:",
		state.Token
	)
end

local function finishDig(
	player,
	state,
	token
)
	if
		not state.Active
		or state.Token ~= token
		or not state.Digging
		or not state.Target
		or not state.Target.Parent
	then
		return
	end

	local _, petType, petTier =
		getPetTypeAndTier(
			player
		)

	if not petType then
		state.Digging =
			false

		player:SetAttribute(
			"PetBushDigging",
			false
		)

		task.delay(
			1,
			function()
				if state.Active then
					assignNextBush(
						player,
						state
					)
				end
			end
		)

		return
	end

	local seedKey =
		chooseRewardSeed(
			state.TargetType,
			petType,
			petTier
		)

	if not seedKey then
		state.Digging =
			false

		player:SetAttribute(
			"PetBushDigging",
			false
		)

		return
	end

	local amount =
		random:NextInteger(
			REWARD_MIN,
			REWARD_MAX
		)

	local ok, iconOrError =
		awardSeed(
			player,
			seedKey,
			amount
		)

	if not ok then
		warn(
			"[PetBushSearch] PREMIO FALLÓ |",
			player.Name,
			"|",
			iconOrError
		)

		SearchStatus:FireClient(
			player,
			"No pude agregar la semilla: "
				.. tostring(
					iconOrError
				)
		)

		state.Digging =
			false

		player:SetAttribute(
			"PetBushDigging",
			false
		)

		task.delay(
			3,
			function()
				if state.Active then
					assignNextBush(
						player,
						state
					)
				end
			end
		)

		return
	end

	local oldTarget =
		state.Target

	state.RecentBushes[
	oldTarget
	] =
		os.clock()
		+ BUSH_REUSE_COOLDOWN

	local data =
		SEEDS[
	seedKey
	]

	RewardFound:FireClient(
		player,
		{
			SeedKey = seedKey,
			Display = data.Display,
			Rarity = data.Rarity,
			Amount = amount,
			Icon = iconOrError or "",
			NextSearchSeconds = NEXT_SEARCH_DELAY,
		}
	)

	-- La busqueda del tutorial cuenta como completada solamente cuando
	-- la mascota termina una busqueda REAL y recibe una semilla.
	fireTutorialAction(player, "PET_SEARCH_DONE", {
		SeedKey = seedKey,
		Rarity = data.Rarity,
		Amount = amount,
	})

	print(
		"[PetBushSearch] PREMIO |",
		player.Name,
		"|",
		data.Display,
		"| x"
			.. tostring(
				amount
			),
		"|",
		data.Rarity,
		"| mascota:",
		petType,
		"| tier:",
		petTier
	)

	queueSeedSave(
		player
	)

	-- V2.6:
	-- Invalida callbacks/llegadas del arbusto que acaba de terminar.
	state.Token +=
		1

	state.Waiting =
		true

	clearTarget(
		player,
		state
	)

	setCommonAttributes(
		player,
		state
	)

	print(
		"[PetBushSearch] ESPERA |",
		player.Name,
		"| siguiente busqueda en",
		NEXT_SEARCH_DELAY,
		"segundos"
	)

	task.delay(
		NEXT_SEARCH_DELAY,
		function()
			if
				player.Parent == Players
				and state.Active
			then
				state.Waiting =
					false

				setCommonAttributes(
					player,
					state
				)

				assignNextBush(
					player,
					state
				)
			end
		end
	)
end

local function beginDig(
	player,
	state,
	token
)
	if
		not state
		or not state.Active
		or state.Digging
		or state.Waiting
		or state.Token
		~= tonumber(
			token
		)
			or not state.Target
			or not state.Target.Parent
	then
		return
	end

	local root =
		getPlayerRoot(
			player
		)

	if not root then
		return
	end

	local targetPosition =
		state.TargetPosition

	if
		not targetPosition
		or (
			root.Position
			- targetPosition
		).Magnitude
			> MAX_PLAYER_TARGET_DISTANCE
	then
		return
	end

	-- Anti-spam.
	if
		os.clock()
		- state.LastArrivalAt
			< 0.8
	then
		return
	end

	state.LastArrivalAt =
		os.clock()

	state.Digging =
		true

	player:SetAttribute(
		"PetBushDigging",
		true
	)

	print(
		"[PetBushSearch] DIG 2s |",
		player.Name,
		"|",
		state.TargetType,
		"| token:",
		state.Token
	)

	task.delay(
		DIG_SECONDS,
		function()
			if
				player.Parent == Players
			then
				finishDig(
					player,
					state,
					token
				)
			end
		end
	)
end

--============================================================
-- REMOTES
--============================================================

ToggleSearch.OnServerInvoke =
	function(player)
		local state =
		getState(
			player
		)

		if state.Active then
			disableSearch(
				player,
				"Modo BUSCAR desactivado."
			)

			print(
				"[PetBushSearch] DESACTIVADO |",
				player.Name
			)

			return {
				Ok = true,
				Active = false,
			}
		end

		if
			player:GetAttribute(
				"SeedInventoryLoaded"
			) ~= true
		then
			return {
				Ok = false,
				Active = false,
				Message =
				"Espera a que cargue tu inventario de semillas.",
			}
		end

		local _, petType =
		getPetTypeAndTier(
			player
		)

		if not petType then
			return {
				Ok = false,
				Active = false,
				Message =
				"Primero saca una mascota.",
			}
		end

		if petType == "HuevoBrizabelle" then
			return {
				Ok = false,
				Active = false,
				Message =
				"El huevo todavía no puede buscar semillas.",
			}
		end

		if #bushes <= 0 then
			return {
				Ok = false,
				Active = false,
				Message =
				"No encontré arbustos en Workspace > Arbustos.",
			}
		end

		state.Active =
		true

		state.Waiting =
		false

		state.Digging =
		false

		state.Token +=
		1

		setCommonAttributes(
			player,
			state
		)

		assignNextBush(
			player,
			state
		)

		print(
			"[PetBushSearch] ACTIVADO |",
			player.Name,
			"| mascota:",
			petType
		)

		return {
			Ok = true,
			Active = true,
		}
	end

ArrivedAtBush.OnServerEvent:Connect(
	function(
		player,
		token
	)
		beginDig(
			player,
			states[
			player
			],
			token
		)
	end
)

--============================================================
-- MONITOR
--============================================================

task.spawn(function()
	while true do
		task.wait(
			1
		)

		local now =
			os.clock()

		for player, state in pairs(
			states
			) do
			if
				state.Active
				and player.Parent
				== Players
			then
				-- Si el dueño se movió y el arbusto objetivo ya quedó lejos,
				-- la mascota NO continúa corriendo hacia él.
				if
					state.Target
					and not state.Digging
					and not state.Waiting
				then
					local playerRoot =
						getPlayerRoot(
							player
						)

					local targetPosition =
						state.TargetPosition

					if
						playerRoot
						and typeof(targetPosition)
						== "Vector3"
						and (
							playerRoot.Position
							- targetPosition
						).Magnitude
							> TARGET_KEEP_RADIUS
					then
						print(
							"[PetBushSearch] OBJETIVO CAMBIADO POR DISTANCIA |",
							player.Name
						)

						state.Token +=
							1

						clearTarget(
							player,
							state
						)

						setCommonAttributes(
							player,
							state
						)

						assignNextBush(
							player,
							state
						)

						continue
					end
				end

				if
					state.Target
					and not state.Digging
					and not state.Waiting
					and now
					- state.AssignedAt
						> TARGET_TIMEOUT
				then
					print(
						"[PetBushSearch] OBJETIVO EXPIRÓ |",
						player.Name
					)

					state.Token +=
						1

					clearTarget(
						player,
						state
					)

					setCommonAttributes(
						player,
						state
					)

					assignNextBush(
						player,
						state
					)
				end
			end
		end
	end
end)

--============================================================
-- PLAYER
--============================================================

local function setupPlayer(player)
	local state =
		getState(
			player
		)

	state.Active =
		false

	setCommonAttributes(
		player,
		state
	)

	clearTarget(
		player,
		state
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
		states[
		player
		] =
			nil

		saveQueued[
		player
		] =
			nil
	end
)

print(
	"[PetBushSearch] SERVER V2.6 ACTIVO | ESPERA REAL 10s + bloqueo de reintentos viejos | radio 42 studs + objetivo cercano + pañuelo favoritas | "
		.. "Dig 2s | espera 10s | x1-x3 | "
		.. "premio directo a Player.SeedInventory."
)
