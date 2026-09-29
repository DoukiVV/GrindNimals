-- ModuleScript: WorldConfig
-- Ubicación: ServerStorage > WorldConfig

local WorldConfig = {}

WorldConfig.Worlds = {
	CasaJugadores = {
		DisplayName = "Casas",
		PlaceId = 111508734059307,
	},

	AdentroCasaJugadores = {
		DisplayName = "Tu casa",
		PlaceId = 98220869827344,
	},

	ReservaNatural = {
		DisplayName = "Reserva natural",
		PlaceId = 80507069544050,
	},
}

function WorldConfig.GetWorld(worldName)
	return WorldConfig.Worlds[worldName]
end

function WorldConfig.GetPlaceId(worldName)
	local world = WorldConfig.Worlds[worldName]

	if not world then
		return nil
	end

	return world.PlaceId
end

function WorldConfig.GetDisplayName(worldName)
	local world = WorldConfig.Worlds[worldName]

	if not world then
		return worldName
	end

	return world.DisplayName
end

return WorldConfig