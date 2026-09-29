--============================================================
-- DAY NIGHT CYCLE SERVER V5 - SIN TOCAR LIGHTING
--
-- UBICACION:
-- ServerScriptService > DayNightCycleServer
-- TIPO:
-- Script
--
-- IMPORTANTE:
-- El servidor YA NO modifica Lighting.
--
-- Solo controla:
-- - WorldTime.ClockTime
-- - WorldTime.Phase
-- - WorldTime.GlobalDay
-- - WorldTime.PhaseTimeRemaining
-- - dias personales
-- - /day
-- - /night
-- - /auto
-- - /fly
--
-- DayNightLightingClient es el UNICO encargado
-- de modificar Lighting visualmente.
--============================================================

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

--============================================================
-- ADMINS
--============================================================

local ADMIN_USER_IDS = {
	[2763635937] = true,
	[1075477843] = true,
}

local function isAdmin(player)
	return player ~= nil
		and ADMIN_USER_IDS[player.UserId] == true
end

--============================================================
-- CONFIGURACION
--============================================================

local DAY_SECONDS = 30 * 60
local NIGHT_SECONDS = 5 * 60
local TOTAL_SECONDS = DAY_SECONDS + NIGHT_SECONDS

local DAY_START = 6
local NIGHT_START = 18
local NIGHT_END = 30

local ADMIN_DAY_CLOCK = 10.5
local ADMIN_NIGHT_CLOCK = 0

-- Solo actualizamos los valores replicados 2 veces por segundo.
local UPDATE_STEP = 0.5

-- Mantiene el reloj global avanzando aunque el servidor se cierre.
local WORLD_TIME_EPOCH = 1786414908

--============================================================
-- DATASTORE
--============================================================

local dayStore =
	DataStoreService:GetDataStore("PlayerWorldDaysV1")

--============================================================
-- WORLDTIME
--============================================================

local worldTime =
	ReplicatedStorage:FindFirstChild("WorldTime")

if not worldTime then
	worldTime = Instance.new("Folder")
	worldTime.Name = "WorldTime"
	worldTime.Parent = ReplicatedStorage
end

local function getValue(className, name, defaultValue)
	local value = worldTime:FindFirstChild(name)

	if value and not value:IsA(className) then
		value:Destroy()
		value = nil
	end

	if not value then
		value = Instance.new(className)
		value.Name = name
		value.Value = defaultValue
		value.Parent = worldTime
	end

	return value
end

local globalClockValue =
	getValue(
		"NumberValue",
		"ClockTime",
		DAY_START
	)

local globalPhaseValue =
	getValue(
		"StringValue",
		"Phase",
		"Dia"
	)

local globalDayValue =
	getValue(
		"IntValue",
		"GlobalDay",
		1
	)

local phaseTimeRemainingValue =
	getValue(
		"NumberValue",
		"PhaseTimeRemaining",
		DAY_SECONDS
	)

local adminTimeOverrideValue =
	getValue(
		"StringValue",
		"AdminTimeOverride",
		"Auto"
	)

--============================================================
-- ADMIN TIME
--============================================================

local adminTimeMode = "Auto"

adminTimeOverrideValue.Value = "Auto"

local function setAdminTimeMode(player, mode)
	if not isAdmin(player) then
		return false
	end

	if
		mode ~= "Auto"
		and mode ~= "Dia"
		and mode ~= "Noche"
	then
		return false
	end

	adminTimeMode = mode
	adminTimeOverrideValue.Value = mode

	if mode == "Dia" then

		globalClockValue.Value =
			ADMIN_DAY_CLOCK

		globalPhaseValue.Value =
			"Dia"

		phaseTimeRemainingValue.Value = 0

		print(
			"[DayNightCycle] "
				.. player.Name
				.. " forzo DIA con /day"
		)

	elseif mode == "Noche" then

		globalClockValue.Value =
			ADMIN_NIGHT_CLOCK

		globalPhaseValue.Value =
			"Noche"

		phaseTimeRemainingValue.Value = 0

		print(
			"[DayNightCycle] "
				.. player.Name
				.. " forzo NOCHE con /night"
		)

	else

		print(
			"[DayNightCycle] "
				.. player.Name
				.. " regreso a AUTOMATICO con /auto"
		)

	end

	return true
end

--============================================================
-- COMANDOS
--============================================================

local function createAdminCommand(
	name,
	primaryAlias,
	secondaryAlias,
	mode
)

	local old =
		TextChatService:FindFirstChild(name)

	if old then
		old:Destroy()
	end

	local command =
		Instance.new("TextChatCommand")

	command.Name = name
	command.PrimaryAlias = primaryAlias

	if secondaryAlias and secondaryAlias ~= "" then
		command.SecondaryAlias =
			secondaryAlias
	end

	command.Parent =
		TextChatService

	command.Triggered:Connect(
		function(textSource)

			if not textSource then
				return
			end

			local player =
				Players:GetPlayerByUserId(
					textSource.UserId
				)

			if not isAdmin(player) then
				return
			end

			setAdminTimeMode(
				player,
				mode
			)

		end
	)
end

createAdminCommand(
	"AdminDayCommand",
	"/day",
	nil,
	"Dia"
)

createAdminCommand(
	"AdminNightCommand",
	"/night",
	nil,
	"Noche"
)

createAdminCommand(
	"AdminAutoTimeCommand",
	"/auto",
	nil,
	"Auto"
)

--============================================================
-- /FLY
--============================================================

local adminFlyRemote =
	ReplicatedStorage:FindFirstChild(
		"AdminFlyChatToggle"
	)

if
	adminFlyRemote
	and not adminFlyRemote:IsA("RemoteEvent")
then

	adminFlyRemote:Destroy()
	adminFlyRemote = nil

end

if not adminFlyRemote then

	adminFlyRemote =
		Instance.new("RemoteEvent")

	adminFlyRemote.Name =
		"AdminFlyChatToggle"

	adminFlyRemote.Parent =
		ReplicatedStorage

end

local oldFlyCommand =
	TextChatService:FindFirstChild(
		"AdminFlyCommand"
	)

if oldFlyCommand then
	oldFlyCommand:Destroy()
end

local flyCommand =
	Instance.new("TextChatCommand")

flyCommand.Name =
	"AdminFlyCommand"

flyCommand.PrimaryAlias =
	"/fly"

flyCommand.Parent =
	TextChatService

flyCommand.Triggered:Connect(
	function(textSource)

		if not textSource then
			return
		end

		local player =
			Players:GetPlayerByUserId(
				textSource.UserId
			)

		if not isAdmin(player) then
			return
		end

		adminFlyRemote:FireClient(player)

	end
)

--============================================================
-- TIEMPO
--============================================================

local function lerp(a, b, alpha)
	return a + (b - a) * alpha
end

local function getCycle(elapsed)

	local cycleTime =
		elapsed % TOTAL_SECONDS

	local completedGlobalDays =
		math.floor(
			elapsed / TOTAL_SECONDS
		)

	local clock
	local isNight

	if cycleTime < DAY_SECONDS then

		local alpha =
			cycleTime / DAY_SECONDS

		clock =
			lerp(
				DAY_START,
				NIGHT_START,
				alpha
			)

		isNight = false

	else

		local alpha =
			(
				cycleTime
				- DAY_SECONDS
			)
			/ NIGHT_SECONDS

		clock =
			lerp(
				NIGHT_START,
				NIGHT_END,
				alpha
			)
			% 24

		isNight = true

	end

	return
		clock,
		isNight,
		completedGlobalDays,
		cycleTime
end

local function getRemainingSeconds(
	cycleTime
)

	if cycleTime < DAY_SECONDS then

		return
			DAY_SECONDS
		- cycleTime

	end

	return
		TOTAL_SECONDS
	- cycleTime
end

--============================================================
-- DIAS PERSONALES
--============================================================

local playerStates = {}

local function loadSavedDay(player)

	local success, savedValue =
		pcall(function()

			return dayStore:GetAsync(
				tostring(player.UserId)
			)

		end)

	if
		success
		and typeof(savedValue) == "number"
		and savedValue >= 1
	then

		return
			math.floor(savedValue)

	end

	return 1
end

local function writeSavedDay(
	player,
	dayToSave
)

	dayToSave =
		math.max(
			1,
			math.floor(
				tonumber(dayToSave)
				or 1
			)
		)

	local success, err =
		pcall(function()

			dayStore:SetAsync(
				tostring(player.UserId),
				dayToSave
			)

		end)

	if not success then

		warn(
			"[DayNightCycle] No se pudo guardar el dia de "
				.. player.Name
				.. ": "
				.. tostring(err)
		)

	end

	return success
end

local function getCompletedSessionDays(
	state
)

	local playedSeconds =
		os.clock()
	- state.joinedAt

	return
		math.floor(
			playedSeconds
			/ TOTAL_SECONDS
		)
end

local function savePlayerDay(player)

	local state =
		playerStates[player]

	if not state then
		return
	end

	local completedSessionDays =
		getCompletedSessionDays(state)

	local dayToSave =
		state.savedDay
		+ completedSessionDays

	if dayToSave > state.savedDay then

		writeSavedDay(
			player,
			dayToSave
		)

	end
end

local function setupPlayer(player)

	if playerStates[player] then
		return
	end

	local savedDay =
		loadSavedDay(player)

	local oldFolder =
		player:FindFirstChild(
			"WorldTime"
		)

	if oldFolder then
		oldFolder:Destroy()
	end

	local folder =
		Instance.new("Folder")

	folder.Name = "WorldTime"
	folder.Parent = player

	local dayValue =
		Instance.new("IntValue")

	dayValue.Name = "Day"
	dayValue.Value = savedDay
	dayValue.Parent = folder

	playerStates[player] = {

		joinedAt = os.clock(),

		savedDay = savedDay,

		lastAwardedDay =
			savedDay,

		dayValue = dayValue,

	}
end

Players.PlayerAdded:Connect(
	function(player)

		task.spawn(
			setupPlayer,
			player
		)

	end
)

for _, player in ipairs(
	Players:GetPlayers()
	) do

	task.spawn(
		setupPlayer,
		player
	)

end

Players.PlayerRemoving:Connect(
	function(player)

		savePlayerDay(player)
		playerStates[player] = nil

	end
)

game:BindToClose(
	function()

		for _, player in ipairs(
			Players:GetPlayers()
			) do

			savePlayerDay(player)

		end

	end
)

--============================================================
-- LOOP
--============================================================

local accumulator = 0

RunService.Heartbeat:Connect(
	function(deltaTime)

		accumulator += deltaTime

		if accumulator < UPDATE_STEP then
			return
		end

		accumulator = 0

		local elapsed =
			(
				DateTime.now()
				.UnixTimestampMillis
				/ 1000
			)
		- WORLD_TIME_EPOCH

		local
		clock,
		isNight,
		completedGlobalDays,
		cycleTime =
			getCycle(elapsed)

		globalDayValue.Value =
			completedGlobalDays + 1

		if adminTimeMode == "Dia" then

			globalClockValue.Value =
				ADMIN_DAY_CLOCK

			globalPhaseValue.Value =
				"Dia"

			phaseTimeRemainingValue.Value =
				0

		elseif adminTimeMode == "Noche" then

			globalClockValue.Value =
				ADMIN_NIGHT_CLOCK

			globalPhaseValue.Value =
				"Noche"

			phaseTimeRemainingValue.Value =
				0

		else

			globalClockValue.Value =
				clock

			globalPhaseValue.Value =
				isNight
				and "Noche"
				or "Dia"

			phaseTimeRemainingValue.Value =
				math.max(
					0,
					getRemainingSeconds(
						cycleTime
					)
				)

		end

		--============================================
		-- DIAS PERSONALES
		--============================================

		for player, state in pairs(
			playerStates
			) do

			if player.Parent then

				local completedSessionDays =
					getCompletedSessionDays(
						state
					)

				local currentDay =
					state.savedDay
					+ completedSessionDays

				state.dayValue.Value =
					currentDay

				if
					currentDay
					> state.lastAwardedDay
				then

					state.lastAwardedDay =
						currentDay

					writeSavedDay(
						player,
						currentDay
					)

				end
			end
		end

	end
)