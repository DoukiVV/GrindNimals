--============================================================
-- DAY NIGHT LIGHTING CLIENT V4
-- UN SOLO DUEÑO DE LIGHTING
--
-- UBICACION:
-- StarterPlayer > StarterPlayerScripts > DayNightLightingClient
-- TIPO:
-- LocalScript
--
-- CORRIGE:
-- - Parpadeo del personaje.
-- - Conflicto servidor/cliente.
-- - Flash de DIA al entrar durante NOCHE.
-- - ClockTime que antes se quedaba en 10.5/3.2.
-- - Transicion por medianoche.
--============================================================

local Lighting =
	game:GetService("Lighting")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local RunService =
	game:GetService("RunService")

--============================================================
-- WORLDTIME
--============================================================

local worldTime =
	ReplicatedStorage:WaitForChild(
		"WorldTime"
	)

local clockValue =
	worldTime:WaitForChild(
		"ClockTime"
	)

local phaseValue =
	worldTime:WaitForChild(
		"Phase"
	)

--============================================================
-- DIA
--============================================================

local DAY_BRIGHTNESS = 3
local DAY_DIFFUSE = 0.65
local DAY_SPECULAR = 0.55
local DAY_EXPOSURE = 0

local DAY_AMBIENT =
	Color3.fromRGB(
		128,
		128,
		128
	)

local DAY_OUTDOOR_AMBIENT =
	Color3.fromRGB(
		128,
		128,
		128
	)

local DAY_FOG_COLOR =
	Color3.fromRGB(
		205,
		225,
		255
	)

local DAY_FOG_END =
	100000

--============================================================
-- NOCHE
--============================================================

local NIGHT_BRIGHTNESS = 2.45
local NIGHT_DIFFUSE = 0.58
local NIGHT_SPECULAR = 0.50
local NIGHT_EXPOSURE = 0.02

local NIGHT_AMBIENT =
	Color3.fromRGB(
		112,
		122,
		146
	)

local NIGHT_OUTDOOR_AMBIENT =
	Color3.fromRGB(
		102,
		112,
		137
	)

local NIGHT_FOG_COLOR =
	Color3.fromRGB(
		72,
		86,
		118
	)

local NIGHT_FOG_END =
	900

--============================================================
-- ATMOSPHERE
--============================================================

local atmosphere =
	Lighting:FindFirstChildOfClass(
		"Atmosphere"
	)

if not atmosphere then

	atmosphere =
		Instance.new("Atmosphere")

	atmosphere.Name =
		"WorldAtmosphere"

	atmosphere.Parent =
		Lighting

end

local DAY_ATMOS_DENSITY = 0.18
local NIGHT_ATMOS_DENSITY = 0.22

local DAY_ATMOS_HAZE = 1.4
local NIGHT_ATMOS_HAZE = 1.9

local DAY_ATMOS_COLOR =
	Color3.fromRGB(
		199,
		222,
		255
	)

local NIGHT_ATMOS_COLOR =
	Color3.fromRGB(
		94,
		108,
		140
	)

local DAY_ATMOS_DECAY =
	Color3.fromRGB(
		104,
		124,
		152
	)

local NIGHT_ATMOS_DECAY =
	Color3.fromRGB(
		70,
		84,
		115
	)

--============================================================
-- TRANSICION
--============================================================

local TRANSITION_SPEED = 1.25
local CLOCK_SPEED = 3

--============================================================
-- HELPERS
--============================================================

local function getAlpha(
	deltaTime,
	speed
)

	return
		1
	- math.exp(
		-deltaTime
			* speed
	)
end

local function approachNumber(
	current,
	target,
	deltaTime,
	speed
)

	local alpha =
		getAlpha(
			deltaTime,
			speed
		)

	return
		current
		+ (
			target
			- current
		)
		* alpha
end

local function approachColor(
	current,
	target,
	deltaTime,
	speed
)

	return current:Lerp(
		target,
		getAlpha(
			deltaTime,
			speed
		)
	)
end

-- ClockTime necesita tratamiento especial.
-- Por ejemplo 23.9 -> 0.1 no debe recorrer
-- hacia atras todo el dia.

local function approachClock(
	current,
	target,
	deltaTime
)

	current %= 24
	target %= 24

	local difference =
		(
			target
			- current
			+ 12
		)
		% 24
	- 12

	local alpha =
		getAlpha(
			deltaTime,
			CLOCK_SPEED
		)

	return
		(
			current
			+ difference
			* alpha
		)
		% 24
end

--============================================================
-- LEER ESTADO REAL ANTES DE MOSTRAR NADA
--============================================================

local startingNight =
	phaseValue.Value == "Noche"

local currentClock =
	tonumber(clockValue.Value)
	or 10.5

local currentBrightness =
	startingNight
	and NIGHT_BRIGHTNESS
	or DAY_BRIGHTNESS

local currentDiffuse =
	startingNight
	and NIGHT_DIFFUSE
	or DAY_DIFFUSE

local currentSpecular =
	startingNight
	and NIGHT_SPECULAR
	or DAY_SPECULAR

local currentExposure =
	startingNight
	and NIGHT_EXPOSURE
	or DAY_EXPOSURE

local currentAmbient =
	startingNight
	and NIGHT_AMBIENT
	or DAY_AMBIENT

local currentOutdoorAmbient =
	startingNight
	and NIGHT_OUTDOOR_AMBIENT
	or DAY_OUTDOOR_AMBIENT

local currentFogColor =
	startingNight
	and NIGHT_FOG_COLOR
	or DAY_FOG_COLOR

local currentFogEnd =
	startingNight
	and NIGHT_FOG_END
	or DAY_FOG_END

local currentAtmosDensity =
	startingNight
	and NIGHT_ATMOS_DENSITY
	or DAY_ATMOS_DENSITY

local currentAtmosHaze =
	startingNight
	and NIGHT_ATMOS_HAZE
	or DAY_ATMOS_HAZE

local currentAtmosColor =
	startingNight
	and NIGHT_ATMOS_COLOR
	or DAY_ATMOS_COLOR

local currentAtmosDecay =
	startingNight
	and NIGHT_ATMOS_DECAY
	or DAY_ATMOS_DECAY

--============================================================
-- APLICACION INICIAL
--
-- IMPORTANTE:
-- Ya NO ponemos DIA obligatoriamente al arrancar.
--============================================================

Lighting.ClockTime =
	currentClock

Lighting.Brightness =
	currentBrightness

Lighting.EnvironmentDiffuseScale =
	currentDiffuse

Lighting.EnvironmentSpecularScale =
	currentSpecular

Lighting.ExposureCompensation =
	currentExposure

Lighting.Ambient =
	currentAmbient

Lighting.OutdoorAmbient =
	currentOutdoorAmbient

Lighting.FogStart = 0

Lighting.FogColor =
	currentFogColor

Lighting.FogEnd =
	currentFogEnd

atmosphere.Density =
	currentAtmosDensity

atmosphere.Haze =
	currentAtmosHaze

atmosphere.Color =
	currentAtmosColor

atmosphere.Decay =
	currentAtmosDecay

--============================================================
-- LOOP VISUAL
--============================================================

RunService.RenderStepped:Connect(
	function(deltaTime)

		local isNight =
			phaseValue.Value
			== "Noche"

		-- El servidor SOLO nos dice la hora.
		local targetClock =
			tonumber(
				clockValue.Value
			)
			or currentClock

		local targetBrightness =
			isNight
			and NIGHT_BRIGHTNESS
			or DAY_BRIGHTNESS

		local targetDiffuse =
			isNight
			and NIGHT_DIFFUSE
			or DAY_DIFFUSE

		local targetSpecular =
			isNight
			and NIGHT_SPECULAR
			or DAY_SPECULAR

		local targetExposure =
			isNight
			and NIGHT_EXPOSURE
			or DAY_EXPOSURE

		local targetAmbient =
			isNight
			and NIGHT_AMBIENT
			or DAY_AMBIENT

		local targetOutdoorAmbient =
			isNight
			and NIGHT_OUTDOOR_AMBIENT
			or DAY_OUTDOOR_AMBIENT

		local targetFogColor =
			isNight
			and NIGHT_FOG_COLOR
			or DAY_FOG_COLOR

		local targetFogEnd =
			isNight
			and NIGHT_FOG_END
			or DAY_FOG_END

		local targetAtmosDensity =
			isNight
			and NIGHT_ATMOS_DENSITY
			or DAY_ATMOS_DENSITY

		local targetAtmosHaze =
			isNight
			and NIGHT_ATMOS_HAZE
			or DAY_ATMOS_HAZE

		local targetAtmosColor =
			isNight
			and NIGHT_ATMOS_COLOR
			or DAY_ATMOS_COLOR

		local targetAtmosDecay =
			isNight
			and NIGHT_ATMOS_DECAY
			or DAY_ATMOS_DECAY

		--============================================
		-- SUAVIZAR
		--============================================

		currentClock =
			approachClock(
				currentClock,
				targetClock,
				deltaTime
			)

		currentBrightness =
			approachNumber(
				currentBrightness,
				targetBrightness,
				deltaTime,
				TRANSITION_SPEED
			)

		currentDiffuse =
			approachNumber(
				currentDiffuse,
				targetDiffuse,
				deltaTime,
				TRANSITION_SPEED
			)

		currentSpecular =
			approachNumber(
				currentSpecular,
				targetSpecular,
				deltaTime,
				TRANSITION_SPEED
			)

		currentExposure =
			approachNumber(
				currentExposure,
				targetExposure,
				deltaTime,
				TRANSITION_SPEED
			)

		currentFogEnd =
			approachNumber(
				currentFogEnd,
				targetFogEnd,
				deltaTime,
				TRANSITION_SPEED
			)

		currentAtmosDensity =
			approachNumber(
				currentAtmosDensity,
				targetAtmosDensity,
				deltaTime,
				TRANSITION_SPEED
			)

		currentAtmosHaze =
			approachNumber(
				currentAtmosHaze,
				targetAtmosHaze,
				deltaTime,
				TRANSITION_SPEED
			)

		currentAmbient =
			approachColor(
				currentAmbient,
				targetAmbient,
				deltaTime,
				TRANSITION_SPEED
			)

		currentOutdoorAmbient =
			approachColor(
				currentOutdoorAmbient,
				targetOutdoorAmbient,
				deltaTime,
				TRANSITION_SPEED
			)

		currentFogColor =
			approachColor(
				currentFogColor,
				targetFogColor,
				deltaTime,
				TRANSITION_SPEED
			)

		currentAtmosColor =
			approachColor(
				currentAtmosColor,
				targetAtmosColor,
				deltaTime,
				TRANSITION_SPEED
			)

		currentAtmosDecay =
			approachColor(
				currentAtmosDecay,
				targetAtmosDecay,
				deltaTime,
				TRANSITION_SPEED
			)

		--============================================
		-- LIGHTING
		--============================================

		Lighting.ClockTime =
			currentClock

		Lighting.Brightness =
			currentBrightness

		Lighting.EnvironmentDiffuseScale =
			currentDiffuse

		Lighting.EnvironmentSpecularScale =
			currentSpecular

		Lighting.ExposureCompensation =
			currentExposure

		Lighting.Ambient =
			currentAmbient

		Lighting.OutdoorAmbient =
			currentOutdoorAmbient

		Lighting.FogStart = 0

		Lighting.FogColor =
			currentFogColor

		Lighting.FogEnd =
			currentFogEnd

		atmosphere.Density =
			currentAtmosDensity

		atmosphere.Haze =
			currentAtmosHaze

		atmosphere.Color =
			currentAtmosColor

		atmosphere.Decay =
			currentAtmosDecay
	end
)