local TutorialConfig = {}

--============================================================
-- GRINDNIMALS TUTORIAL V6.0 - FLECHAS 3D DIRECTAS
-- V5 usa un DataStore nuevo para que TODOS los jugadores
-- empiecen el tutorial desde cero una sola vez.
--============================================================

TutorialConfig.DEBUG_TUTORIAL = true
TutorialConfig.TUTORIAL_VERSION = 54
TutorialConfig.DATASTORE_NAME = "GrindNimalsTutorialV54"
TutorialConfig.FIRST_STEP = "START_BRIZABELLE"

-- Pon aqui tus UserIds si quieres usar /tutorial fuera de Studio.
TutorialConfig.ADMIN_USER_IDS = {2763635937, 1075477843}

TutorialConfig.COLORS = {
	Panel = Color3.fromRGB(204, 144, 71),
	Cream = Color3.fromRGB(255, 232, 190),
	Card = Color3.fromRGB(245, 216, 176),
	Dark = Color3.fromRGB(82, 45, 24),
	Text = Color3.fromRGB(55, 31, 18),
	Green = Color3.fromRGB(85, 168, 77),
	Gold = Color3.fromRGB(236, 180, 65),
	Red = Color3.fromRGB(186, 88, 82),
}

-- Flechas fisicas que forman el camino hasta el objetivo.
TutorialConfig.ROUTE = {
	Enabled = true,

	-- V5.9: flechas 3D individuales. Sin Beam y sin Pathfinding.
	Color = Color3.fromRGB(249, 241, 0),

	-- Separacion y cantidad visible.
	Spacing = 5.2,
	MaxArrows = 18,
	StartOffset = 4.5,
	StopBeforeTarget = 10,

	-- Movimiento de las flechas hacia el objetivo.
	FlowSpeed = 3.0,

	-- Altura sobre el suelo y frecuencia de raycast.
	GroundOffset = 0.18,
	GroundRefreshSeconds = 0.08,

	-- Al estar cerca, desaparece TODA la ruta.
	HideDistance = 18,

	-- Si un TP mueve al jugador de golpe, borra cualquier altura cacheada.
	TeleportJumpDistance = 18,
}

-- El cliente primero intenta las rutas exactas y, si no existen,
-- busca recursivamente el ultimo nombre.
TutorialConfig.GuiTargets = {
	PetSearchButton = {
		Candidates = {
			{"PetBushSearchGui", "SearchButton"},
			{"PetBushSearchGui", "Main", "SearchButton"},
			{"PetBushSearchGui", "Panel", "SearchButton"},
		},
		DescendantName = "SearchButton",
	},
}

TutorialConfig.Worlds = {
	Lobby = {PlaceIds = {106198712137089}},
	NaturalReserve = {PlaceIds = {80507069544050}},
	-- CasaJugadores no necesita PlaceId para validar el paso.
	-- Solo copia TutorialSystem + TutorialServer + TutorialClient alli.
	PlayerHouse = {PlaceIds = {}},
}

TutorialConfig.HelpSections = {
	{Title = "Primer huevo", Body = "Ve con Brizabelle. El primer huevo del tutorial es gratis una sola vez."},
	{Title = "Frank", Body = "Frank te ensena como mejorar mascotas para aumentar sus habilidades."},
	{Title = "Cuidados", Body = "Abre el menu con R. El huevo necesita dormir y banarse; para acariciarlo manten presionado."},
	{Title = "Casa Jugadores", Body = "Lleva el huevo a Casa Jugadores y deja que descanse cuando tenga sueno."},
	{Title = "Reserva Natural", Body = "En la tienda del bosque Lex te regala tu primera Hacha de Madera."},
	{Title = "Madera", Body = "Tala un arbol real usando el sistema del bosque."},
	{Title = "Busqueda", Body = "Activa el modo busqueda de tu mascota para encontrar semillas."},
}

TutorialConfig.Steps = {
	{
		Id = "START_BRIZABELLE",
		ObjectiveText = "COMPRA TU PRIMER HUEVO MASCOTA",
		World = "Lobby",
		Type = "PROXIMITY_PROMPT",
		Title = "Ve a comprar tu primer huevo mascota",
		Description = "Sigue el Camino Guia de Flechas hasta Brizabelle y habla con ella.",
		Target = {
			PathCandidates = {
				{"Workspace", "Granja", "Brizabelle", "Brizabelle"},
				{"Workspace", "Granja", "Brizabelle"},
			},
			SearchNames = {"Brizabelle"},
			PromptName = "BrizabelleEggPrompt",
			Label = "BRIZABELLE",
		},
		Arrow = true,
		Route = true,
		Highlight = true,
		Next = "BUY_FREE_EGG",
	},
	{
		Id = "BUY_FREE_EGG",
		ObjectiveText = "OBTEN GRATIS TU PRIMER HUEVO MASCOTA",
		World = "Lobby",
		Type = "CUSTOM_EVENT",
		Title = "Tu primer huevo es gratis",
		Description = "Obtiene tu primer Huevo Mascota. Este primero cuesta $0; despues vuelve a costar $1,500.",
		UiTarget = {
			Candidates = {
				{"BrizabelleEggGui", "ShopPanel", "BuyHoldButton"},
				{"BrizabelleEggGui", "BuyHoldButton"},
			},
			DescendantName = "BuyHoldButton",
		},
		RequiredAction = "FREE_EGG_CLAIMED",
		Next = "GO_FRANK",
	},
	{
		Id = "GO_FRANK",
		ObjectiveText = "HABLA CON FRANK",
		World = "Lobby",
		Type = "PROXIMITY_PROMPT",
		Title = "Ahora ve con Frank",
		Description = "Sigue el Camino Guia de Flechas. Frank puede mejorar tus mascotas y aumentar sus habilidades.",
		Target = {
			PathCandidates = {
				{"Workspace", "Granja", "Frank"},
				{"Workspace", "Frank"},
			},
			SearchNames = {"Frank"},
			PromptName = "PetUpgradePrompt",
			Label = "FRANK",
		},
		Arrow = true,
		Route = true,
		Highlight = true,
		Next = "FRANK_EXAMPLE",
	},
	{
		Id = "FRANK_EXAMPLE",
		ObjectiveText = "APRENDE COMO SE MEJORAN LAS MASCOTAS",
		World = "Lobby",
		Type = "CUSTOM_EVENT",
		Title = "Ejemplo de mejora con Frank",
		Description = "Frank te mostrara un ejemplo. No necesitas sacar una mascota ni gastar materiales durante esta explicacion.",
		RequiredAction = "FRANK_DEMO_DONE",
		Next = "PET_MENU_R",
	},
	{
		Id = "PET_MENU_R",
		ObjectiveText = "PRESIONA R PARA ABRIR EL MENU DE TU MASCOTA",
		World = "Lobby",
		Type = "CUSTOM_EVENT",
		Title = "Abre el menu de tu mascota",
		Description = "Presiona R para abrir el menu de tu mascota y conocer como funciona tu huevo.",
		RequiredAction = "PET_MENU_OPENED",
		Next = "PET_MENU_NEEDS",
	},
	{
		Id = "PET_MENU_NEEDS",
		ObjectiveText = "ACARICIA A TU HUEVO MASCOTA",
		World = "Lobby",
		Type = "CUSTOM_EVENT",
		Title = "Aprende como funciona tu huevo mascota",
		Description = "Lee la explicacion y, sin cerrar el menu, manten presionado sobre tu huevo para acariciarlo.",
		RequiredAction = "PET_CARE_USED",
		Next = "GO_FOREST_PORTAL",
	},
	{
		Id = "GO_PLAYER_HOUSE",
		ObjectiveText = "VE A CASA JUGADORES",
		World = "Lobby",
		Type = "PORTAL",
		Title = "Lleva a tu huevo a Casa Jugadores",
		Description = "Sigue las flechas hasta el portal de Casa Jugadores para que tu huevo pueda descansar.",
		Target = {
			PathCandidates = {
				{"Workspace", "Portales ", "Portal Casas", "TpCasa"},
				{"Workspace", "Portales ", "Portal Casas"},
				{"Workspace", "Portales", "Portal Casas", "TpCasa"},
				{"Workspace", "Portales", "Portal Casas"},
			},
			SearchNames = {"TpCasa", "Portal Casas"},
			Label = "CASA JUGADORES",
		},
		Arrow = true,
		Route = true,
		Highlight = true,
		AdvanceOnReach = true,
		Radius = 6,
		SaveNextBeforeTeleport = "HOUSE_REST",
		Next = "HOUSE_REST",
	},
	{
		Id = "HOUSE_REST",
		ObjectiveText = "HAZ QUE TU HUEVO DESCANSE",
		World = "PlayerHouse",
		Type = "CUSTOM_EVENT",
		Title = "Deja descansar a tu huevo",
		Description = "Haz que tu huevo mascota duerma en Casa Jugadores. Este paso solo avanza cuando el descanso se completa de verdad.",
		RequiredAction = "PET_SLEPT",
		Next = "GO_FOREST_PORTAL",
	},
	{
		Id = "GO_FOREST_PORTAL",
		ObjectiveText = "VE AL BOSQUE",
		World = "Lobby",
		Type = "PORTAL",
		Title = "Ve al Bosque",
		Description = "Sigue la guia de flechas hasta el Portal Bosque.",
		Target = {
			-- IMPORTANTE: solo usamos el portal correcto.
			-- No usar Portales Jardin ni nombres parecidos.
			Path = {"Workspace", "Portales", "Portal Bosque"},
			PathCandidates = {
				{"Workspace", "Portales", "Portal Bosque"},
			},
			SearchNames = {"Portal Bosque"},
			Label = "BOSQUE",
		},
		Arrow = true,
		Route = true,
		Highlight = true,
		AdvanceOnReach = true,
		Radius = 6,
		SaveNextBeforeTeleport = "RESERVE_ENTER_SHOP",
		Next = "RESERVE_ENTER_SHOP",
	},
	{
		Id = "RESERVE_ENTER_SHOP",
		ObjectiveText = "HABLA CON LEX",
		World = "NaturalReserve",
		Type = "PROXIMITY_PROMPT",
		Title = "Entra a la tienda y habla con Lex",
		Description = "Sigue el Camino Guia de Flechas hasta Lex. El te dara tu primera Hacha de Madera.",
		Target = {
			PathCandidates = {
				{"Workspace", "Casa bosque"},
				{"Workspace", "Interior casa bosque"},
			},
			SearchNames = {"Lex", "Casa bosque", "Interior casa bosque"},
			PromptName = "LexAxeShopPrompt",
			Label = "LEX",
		},
		Arrow = true,
		Route = true,
		Highlight = true,
		Next = "LEX_FREE_AXE",
	},
	{
		Id = "LEX_FREE_AXE",
		ObjectiveText = "RECIBE TU HACHA DE MADERA",
		World = "NaturalReserve",
		Type = "CUSTOM_EVENT",
		Title = "Tu primera Hacha de Madera",
		Description = "Lex te regalara una Hacha de Madera. Recibela para comenzar a talar.",
		RequiredAction = "FREE_AXE_CLAIMED",
		Next = "CHOP_FIRST_TREE",
	},
	{
		Id = "CHOP_FIRST_TREE",
		ObjectiveText = "TALA TU PRIMER ARBOL",
		World = "NaturalReserve",
		Type = "WOOD_ACTION",
		Title = "Tala tu primer arbol",
		Description = "Sal de la tienda, sigue las flechas hasta un arbol y talalo por completo.",
		Target = {
			PathCandidates = {
				{"Workspace", "Arboles"},
				{"Workspace", "Trees"},
			},
			SearchNames = {"Arboles", "Trees"},
			Label = "ARBOL",
		},
		Arrow = true,
		Route = true,
		Highlight = true,
		RequiredAction = "WOOD_CHOPPED",
		Next = "ACTIVATE_PET_SEARCH",
	},
	{
		Id = "ACTIVATE_PET_SEARCH",
		ObjectiveText = "ACTIVA EL MODO BUSQUEDA",
		World = "NaturalReserve",
		Type = "PET_ACTION",
		Title = "Activa el modo busqueda",
		Description = "Da click en el boton de busqueda que aparece sobre tu mascota y deja que termine de buscar.",
		GuiTarget = "PetSearchButton",
		RequiredAction = "PET_SEARCH_DONE",
		Next = "TUTORIAL_COMPLETE",
	},
	{
		Id = "TUTORIAL_COMPLETE",
		ObjectiveText = "TUTORIAL COMPLETADO",
		World = "NaturalReserve",
		Type = "INFO",
		Title = "Tutorial Completado",
		Description = "Ya sabes lo necesario para comenzar. Ahora puedes explorar el mundo de GrindNimals.",
		ButtonText = "EMPEZAR",
		CompleteTutorial = true,
		PanelPosition = "Center",
	},
}

return TutorialConfig
