-- PetRenderer_StableSideFollower
-- Cliente: clon visual unico, sin prompts E/F, con seguimiento suave y slot al lado al estar quieto.
-- PetClient y PetFollower deben permanecer desactivados.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local PetConfigs = require(ReplicatedStorage:WaitForChild("PetConfigs"))
local localPlayer = Players.LocalPlayer

local RENDER_NAME = "PetRendererStableSideFollower"
local OLD_RENDER_NAMES = {
	"PetRendererFluidFollower",
	"PetRendererSmoothAdoptStyle",
	"PetRendererBulkMoveTo",
}

local CLIENT_OBJECT_ATTRIBUTE = "ClientPetVisual"
local SCAN_INTERVAL = 0.2
local MIN_DT = 1 / 240
local MAX_DT = 1 / 30
local SNAP_DISTANCE = 85
local SPAWN_DURATION = 0.58
local DESPAWN_DURATION = 0.40
local SPAWN_START_SCALE = 0.54
local SPAWN_OVERSHOOT_SCALE = 1.12
local DESPAWN_END_SCALE = 0.52
local SPECIALS = { "Eat", "Celebrate", "Dig" }

local IDLE_SIDE_OFFSET = 2.55
local IDLE_BACK_OFFSET = 0.35
local MOVE_SIDE_OFFSET = 1.85
local MOVE_BACK_OFFSET = 3.15
local MIN_OWNER_DISTANCE = 2.25
local OBSTACLE_CHECK_HEIGHT = 1.8
local AVOIDANCE_EXTRA_SIDE = 2.1
local AVOIDANCE_EXTRA_BACK = 1.6

local states = {}
local activeVisualKeys = {}
local scanElapsed = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function getNumber(config, key, fallback)
	local value = config and config[key]
	if typeof(value) == "number" then
		return value
	end
	return fallback
end

local function responseAlpha(speed, dt)
	return 1 - math.exp(-math.max(speed, 0) * dt)
end

local function smootherStep(t)
	t = math.clamp(t, 0, 1)
	return t * t * t * (t * (t * 6 - 15) + 10)
end

local function flatUnit(vector, fallback)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude > 0.001 then
		return flat.Unit
	end
	return fallback or Vector3.new(0, 0, -1)
end

local function smoothDampVector(current, target, currentVelocity, smoothTime, maxSpeed, dt)
	smoothTime = math.max(0.0001, smoothTime)
	local omega = 2 / smoothTime
	local x = omega * dt
	local exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
	local change = current - target
	local originalTarget = target
	local maxChange = maxSpeed * smoothTime

	if change.Magnitude > maxChange then
		change = change.Unit * maxChange
	end

	target = current - change
	local temp = (currentVelocity + change * omega) * dt
	local newVelocity = (currentVelocity - temp * omega) * exp
	local output = target + (change + temp) * exp

	if (originalTarget - current):Dot(output - originalTarget) > 0 then
		output = originalTarget
		newVelocity = Vector3.zero
	end

	return output, newVelocity
end

local function setModelLocalTransparency(model, alpha)
	alpha = math.clamp(alpha, 0, 1)
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("BasePart") then
			object.LocalTransparencyModifier = alpha
		elseif object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam") then
			object.Enabled = alpha < 0.98
		end
	end
end

local function hideModelLocally(model)
	local saved = {}
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("BasePart") then
			table.insert(saved, { object = object, property = "LocalTransparencyModifier", value = object.LocalTransparencyModifier })
			object.LocalTransparencyModifier = 1
		elseif object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam") then
			table.insert(saved, { object = object, property = "Enabled", value = object.Enabled })
			object.Enabled = false
		end
	end
	return saved
end

local function restoreSavedProperties(saved)
	for _, item in ipairs(saved or {}) do
		local object = item.object
		if object and object.Parent then
			pcall(function()
				object[item.property] = item.value
			end)
		end
	end
end

local function cleanClone(model)
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("Script") or object:IsA("LocalScript") or object:IsA("ModuleScript") then
			object:Destroy()
		elseif object:IsA("ProximityPrompt") then
			object:Destroy()
		end
	end
end

local function configureVisualModel(model, root, humanoid)
	model.PrimaryPart = root
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("BasePart") then
			object.Anchored = object == root
			object.CanCollide = false
			object.CanTouch = false
			object.CanQuery = false
			object.Massless = true
			object.CastShadow = false
			object.AssemblyLinearVelocity = Vector3.zero
			object.AssemblyAngularVelocity = Vector3.zero
		elseif object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam") then
			object.Enabled = true
		end
	end

	pcall(function()
		humanoid.EvaluateStateMachine = false
	end)
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
end

local function createVisualModel(sourcePet)
	local oldArchivable = sourcePet.Archivable
	sourcePet.Archivable = true
	local ok, visual = pcall(function()
		return sourcePet:Clone()
	end)
	sourcePet.Archivable = oldArchivable

	if not ok or not visual then
		return nil
	end

	visual.Name = sourcePet.Name .. "_ClientVisual"
	visual:SetAttribute(CLIENT_OBJECT_ATTRIBUTE, true)
	cleanClone(visual)
	visual.Parent = workspace
	visual:PivotTo(sourcePet:GetPivot())
	setModelLocalTransparency(visual, 1)
	return visual
end

local function stopTracks(state)
	for _, track in pairs(state.tracks or {}) do
		pcall(function()
			track:Stop(0.1)
		end)
	end
	state.currentTrack = nil
	state.currentTrackName = nil
end

local function clearIdleLayers(state, fadeTime)
	fadeTime = fadeTime or 0.08
	state.proceduralIdleActive = false
	state.afkSequenceStartedAt = nil
	state.afk2Started = nil

	local afkTrack = state.tracks and state.tracks.AFK
	if afkTrack then
		afkTrack:AdjustSpeed(1)
		if afkTrack.IsPlaying then
			afkTrack:Stop(fadeTime)
		end
	end

	local afk2Track = state.tracks and state.tracks.AFK2
	if afk2Track then
		afk2Track:AdjustSpeed(1)
		if afk2Track.IsPlaying then
			afk2Track:Stop(fadeTime)
		end
	end

	if state.currentTrack == afkTrack or state.currentTrack == afk2Track then
		state.currentTrack = nil
		state.currentTrackName = nil
	end
end

local function playTrack(state, name, fadeTime)
	local track = state.tracks and state.tracks[name]
	if not track then
		return nil
	end
	if state.currentTrack == track then
		if not track.IsPlaying then
			track:Play(fadeTime or 0.12)
		end
		return track
	end
	if state.currentTrack then
		state.currentTrack:Stop(fadeTime or 0.12)
	end
	state.currentTrack = track
	state.currentTrackName = name
	track:Play(fadeTime or 0.12)
	return track
end

local function loadAnimations(state)
	state.tracks = {}
	state.animationInstances = {}

	local animator = state.humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = state.humanoid
	end

	local animationAssets = {}
	for animationName, assetId in pairs(state.config) do
		if type(assetId) == "string" and string.find(assetId, "rbxassetid://", 1, true) == 1 then
			local existingTrack = animationAssets[assetId]
			if existingTrack then
				state.tracks[animationName] = existingTrack
				continue
			end
			local animation = Instance.new("Animation")
			animation.Name = "ClientPet_" .. animationName
			animation.AnimationId = assetId
			animation.Parent = animator
			table.insert(state.animationInstances, animation)

			local ok, track = pcall(function()
				return animator:LoadAnimation(animation)
			end)
			if ok and track then
				track.Looped = true
				animationAssets[assetId] = track
				if animationName == "Walk" or animationName == "Fly" then
					track.Priority = Enum.AnimationPriority.Movement
				elseif animationName == "AFK" then
					track.Priority = Enum.AnimationPriority.Idle
					if state.config.AFK2 then
						track.Looped = false
					end
				elseif animationName == "AFK2" then
					track.Priority = Enum.AnimationPriority.Action4
				else
					track.Priority = Enum.AnimationPriority.Action
				end
				state.tracks[animationName] = track
			end
		end
	end
end

local function scheduleSpecial(state, now)
	state.nextSpecialAt = now + math.random(10, 18)
end

local function findMotor(model, targetName)
	local normalizedTarget = string.lower(string.gsub(targetName, "%s+", ""))
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("Motor6D") then
			local normalizedName = string.lower(string.gsub(object.Name, "%s+", ""))
			if normalizedName == normalizedTarget then
				return object
			end
		end
	end
	return nil
end

local function setupProceduralIdle(state)
	if state.config.ProceduralPeckIdle ~= true then
		return
	end

	local wingMotors = {}
	for _, object in ipairs(state.visualModel:GetDescendants()) do
		if object:IsA("Motor6D") and string.find(string.lower(object.Name), "ala", 1, true) then
			table.insert(wingMotors, object)
		end
	end

	state.proceduralIdle = {
		head = findMotor(state.visualModel, "cabeza"),
		beak = findMotor(state.visualModel, "Pico"),
		wings = wingMotors,
	}
end

local function updateProceduralIdle(state, now)
	local proceduralIdle = state.proceduralIdle
	if not proceduralIdle then
		return
	end

	if not state.proceduralIdleActive then
		if state.proceduralIdleWasActive then
			if proceduralIdle.head then
				proceduralIdle.head.Transform = CFrame.identity
			end
			if proceduralIdle.beak then
				proceduralIdle.beak.Transform = CFrame.identity
			end
			for _, motor in ipairs(proceduralIdle.wings) do
				motor.Transform = CFrame.identity
			end
			state.proceduralIdleWasActive = false
		end
		return
	end

	state.proceduralIdleWasActive = true
	local elapsed = now - (state.afkSequenceStartedAt or now)
	local cycle = (elapsed * 1.35) % 1
	local dip = 0
	if cycle < 0.18 then
		dip = smootherStep(cycle / 0.18)
	elseif cycle < 0.34 then
		dip = 1 - smootherStep((cycle - 0.18) / 0.16)
	end
	local breathe = math.sin(now * 2.1) * 0.035
	local tinyLook = math.sin(now * 0.9) * 0.045

	if proceduralIdle.head then
		proceduralIdle.head.Transform = CFrame.Angles(math.rad(-17) * dip + breathe, tinyLook, math.rad(3) * dip)
	end
	if proceduralIdle.beak then
		proceduralIdle.beak.Transform = CFrame.Angles(math.rad(9) * dip, 0, 0)
	end
	for index, motor in ipairs(proceduralIdle.wings) do
		local side = index % 2 == 0 and -1 or 1
		motor.Transform = CFrame.Angles(math.rad(3) * dip, 0, math.rad(5 * side) * dip)
	end
end

local function updateAnimation(state, isMoving, ownerSpeed, petSpeed, now, dt, playerMoving)
	local flightHeld = state.flightAnimationHoldUntil and now < state.flightAnimationHoldUntil

	-- Una mascota puede seguir flotando físicamente (AlwaysFloat),
	-- pero su animación Fly/Walk solo debe reproducirse cuando realmente se mueve.
	-- Esto permite que PezDorado use AFK al quedarse quieto.
	local flyingActive =
		state.config.Flying == true
		and isMoving == true
		and ((state.flightBlend or 0) > 0.12 or flightHeld)
	local adminOverride = state.ownerId == localPlayer.UserId and localPlayer:GetAttribute("AdminPetAnimationOverride") or ""
	if typeof(adminOverride) ~= "string" then
		adminOverride = ""
	end

	local adminAnimationSpeed = state.ownerId == localPlayer.UserId and localPlayer:GetAttribute("AdminPetAnimationSpeed") or 1
	if typeof(adminAnimationSpeed) ~= "number" then
		adminAnimationSpeed = 1
	end

	if adminOverride ~= "" and state.tracks[adminOverride] then
		if state.adminAnimationOverride ~= adminOverride then
			clearIdleLayers(state, 0.04)
			state.adminAnimationOverride = adminOverride
		end
		state.specialUntil = nil
		scheduleSpecial(state, now)
		local overrideTrack = playTrack(state, adminOverride, 0.08)
		if overrideTrack then
			overrideTrack.Looped = true
			overrideTrack:AdjustSpeed(math.clamp(adminAnimationSpeed, 0, 2))
			overrideTrack:AdjustWeight(1, 0.04)
		end
		return
	elseif state.adminAnimationOverride then
		clearIdleLayers(state, 0.06)
		state.adminAnimationOverride = nil
	end

	if flyingActive then
		clearIdleLayers(state, 0.06)
		state.specialUntil = nil
		scheduleSpecial(state, now)
		local movementTrack = playTrack(state, state.tracks.Fly and "Fly" or "Walk", getNumber(state.config, "FlyAnimFadeIn", 0.18))
		if movementTrack then
			local startTime = getNumber(state.config, "FlyStartTime", 0)
			local resetTime = getNumber(state.config, "FlyLoopResetTime", startTime)
			if startTime > 0 and movementTrack.TimePosition < startTime then
				movementTrack.TimePosition = startTime
			elseif resetTime > 0 and movementTrack.TimePosition < resetTime then
				movementTrack.TimePosition = resetTime
			end
		end

		local targetSpeed = math.clamp(math.max(ownerSpeed, petSpeed, 6) / 11, 0.82, 1.28)
		state.animationSpeed += (targetSpeed - state.animationSpeed) * responseAlpha(6, dt)
		movementTrack = state.tracks.Fly or state.tracks.Walk
		if movementTrack and math.abs(state.animationSpeed - (state.lastAppliedAnimationSpeed or 0)) > 0.05 then
			movementTrack:AdjustSpeed(state.animationSpeed)
			state.lastAppliedAnimationSpeed = state.animationSpeed
		end
		return
	elseif isMoving then
		clearIdleLayers(state, 0.08)
		state.specialUntil = nil
		scheduleSpecial(state, now)
		playTrack(state, "Walk", 0.14)

		local targetSpeed = math.clamp(math.max(ownerSpeed, petSpeed, 6) / 11, 0.82, 1.28)
		state.animationSpeed += (targetSpeed - state.animationSpeed) * responseAlpha(6, dt)
		local movementTrack = flyingActive and (state.tracks.Fly or state.tracks.Walk) or state.tracks.Walk
		if movementTrack and math.abs(state.animationSpeed - (state.lastAppliedAnimationSpeed or 0)) > 0.05 then
			movementTrack:AdjustSpeed(state.animationSpeed)
			state.lastAppliedAnimationSpeed = state.animationSpeed
		end
		return
	end

	if state.config.DisableIdleSpecials == true then
		state.specialUntil = nil
	else
		if state.specialUntil then
			if now < state.specialUntil then
				return
			end
			state.specialUntil = nil
			scheduleSpecial(state, now)
		end

		if now >= state.nextSpecialAt then
			local options = {}
			for _, name in ipairs(SPECIALS) do
				if state.tracks[name] then
					table.insert(options, name)
				end
			end
			if #options > 0 then
				local selected = options[math.random(1, #options)]
				state.specialUntil = now + getNumber(state.config, "SpecialDuration", 2.4)
				clearIdleLayers(state, 0.08)
				playTrack(state, selected, 0.16)
				return
			end
			scheduleSpecial(state, now)
		end
	end

	if state.config.StopMovementAnimationWhenIdle == true and not playerMoving and not state.tracks.AFK then
		clearIdleLayers(state, 0.08)
		if state.currentTrack then
			state.currentTrack:Stop(0.12)
			state.currentTrack = nil
			state.currentTrackName = nil
		end
		return
	end

	if state.config.ProceduralPeckIdle == true then
		if not state.proceduralIdleActive then
			stopTracks(state)
			state.afkSequenceStartedAt = now
		end
		state.afk2Started = nil
		state.proceduralIdleActive = true
		return
	end

	if state.config.AFK2Only == true and state.tracks.AFK2 then
		local afkTrack = state.tracks.AFK
		if afkTrack and afkTrack.IsPlaying then
			afkTrack:Stop(0.08)
		end
		state.afkSequenceStartedAt = nil
		local afk2Track = playTrack(state, "AFK2", 0.10)
		if afk2Track then
			afk2Track.Looped = true
			afk2Track:AdjustSpeed(1)
			afk2Track:AdjustWeight(1, 0.06)
		end
		return
	end

	if state.tracks.AFK2 then
		local introTrack = state.tracks.AFK
		local introDuration = getNumber(state.config, "AFKIntroDuration", 1.25)
		if introTrack and introTrack.Length > 0 then
			introDuration = math.min(introDuration, math.max(introTrack.Length - 0.05, 0.1))
		end

		if not state.afkSequenceStartedAt then
			state.afkSequenceStartedAt = now
			state.afk2Started = nil
			playTrack(state, "AFK", 0.16)
			return
		end

		if now - state.afkSequenceStartedAt >= introDuration then
			local afkTrack = state.tracks.AFK
			local afk2Track = state.tracks.AFK2
			if not state.afk2Started then
				if afkTrack then
					if not afkTrack.IsPlaying then
						afkTrack:Play(0.04)
					end
					local holdTime = introDuration
					if afkTrack.Length > 0 then
						holdTime = math.clamp(introDuration, 0.05, math.max(afkTrack.Length - 0.05, 0.05))
					end
					afkTrack.TimePosition = holdTime
					afkTrack:AdjustSpeed(0)
					afkTrack:AdjustWeight(1, 0.08)
				end
				if afk2Track then
					afk2Track.Looped = true
					afk2Track.TimePosition = 0
					afk2Track:Play(0.08)
					afk2Track:AdjustSpeed(1)
					afk2Track:AdjustWeight(getNumber(state.config, "AFK2Weight", 0.85), 0.06)
				end
				state.currentTrack = afk2Track or afkTrack
				state.currentTrackName = afk2Track and "AFK2" or "AFK"
				state.afk2Started = true
			elseif afk2Track then
				if not afk2Track.IsPlaying then
					afk2Track:Play(0.08)
				end
				afk2Track:AdjustSpeed(1)
				afk2Track:AdjustWeight(getNumber(state.config, "AFK2Weight", 0.85), 0.06)
			end
		else
			playTrack(state, "AFK", 0.16)
		end
		return
	end

	playTrack(state, "AFK", 0.16)
end

local function getVisualTorso(model)
	return model and model:FindFirstChild("Torso", true)
end

local function isEggPetType(petType)
	return petType == "Huevo Mascota" or petType == "Huevo" or petType == "HuevoBrizabelle"
end

local function getOwnerEggValue(state)
	local owner = state.owner or Players:GetPlayerByUserId(state.ownerId)
	if not owner then
		return nil
	end
	state.owner = owner
	local container = owner:FindFirstChild("TradePetsInventory")
	if not container then
		return nil
	end
	for _, child in ipairs(container:GetChildren()) do
		if (child:IsA("IntValue") or child:IsA("NumberValue")) and (child.Name == "Huevo Mascota" or child.Name == "HuevoBrizabelle" or child:GetAttribute("ItemName") == "Huevo Mascota" or child:GetAttribute("ItemName") == "HuevoBrizabelle") then
			return child
		end
	end
	return nil
end

local function getOwnerPetValue(ownerId, petType)
	local owner = Players:GetPlayerByUserId(ownerId)
	local container = owner and owner:FindFirstChild("TradePetsInventory")
	if not container then
		return nil
	end
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("IntValue") or child:IsA("NumberValue") then
			local itemName = tostring(child:GetAttribute("ItemName") or child.Name)
			if child.Name == petType or itemName == petType then
				return child
			end
		end
	end
	return nil
end

local function isOwnerPetResting(ownerId, petType)
	if isEggPetType(petType) then
		return false
	end
	local petValue = getOwnerPetValue(ownerId, petType)
	return petValue and petValue:GetAttribute("Resting") == true or false
end

local function isEggDirty(state)
	local eggValue = getOwnerEggValue(state)
	if eggValue then
		return eggValue:GetAttribute("Dirty") == true
	end
	return state.sourcePet and state.sourcePet:GetAttribute("DirtyEggVisual") == true
end

local function emitEggPoof(state, colorA, colorB, amount)
	local torso = getVisualTorso(state.visualModel) or state.root
	if not torso or not torso:IsA("BasePart") then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "EggPoof"
	attachment.Parent = torso

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "SoftPoof"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colorA),
		ColorSequenceKeypoint.new(1, colorB),
	})
	emitter.LightEmission = 0.12
	emitter.LightInfluence = 0.7
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(0.35, 0.28),
		NumberSequenceKeypoint.new(1, 0.04),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(0.7, 0.28),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.38, 0.72)
	emitter.Speed = NumberRange.new(2.2, 5.2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 1.1, 0)
	emitter.Drag = 5
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(amount or 28)
	Debris:AddItem(attachment, 1)
end

local function spawnDirtyBurst(state)
	local anchor = state.root or getVisualTorso(state.visualModel) or (state.visualModel and state.visualModel:FindFirstChildWhichIsA("BasePart", true))
	if state and state.visualModel then
		state.visualModel:SetAttribute("DirtyBurstRequestedAt", os.clock())
		state.visualModel:SetAttribute("DirtyBurstAnchor", anchor and anchor:GetFullName() or "none")
	end
	if not anchor or not anchor:IsA("BasePart") then
		return
	end

	local center = anchor.Position
	state.dirtyBurstParticlesAliveUntil = os.clock() + 0.9
	for index = 1, 18 do
		local particle = Instance.new("Part")
		particle.Name = "DirtyEggBurstParticle"
		particle.Shape = Enum.PartType.Ball
		particle.Anchored = true
		particle.CanCollide = false
		particle.CanTouch = false
		particle.CanQuery = false
		particle.CastShadow = false
		particle.Material = Enum.Material.SmoothPlastic
		particle.Color = (index % 3 == 0) and Color3.fromRGB(74, 48, 26) or Color3.fromRGB(130, 86, 39)
		local size = (index % 4 == 0) and 0.18 or 0.105
		particle.Size = Vector3.new(size, size, size)
		local angle = (index / 18) * math.pi * 2
		local radius = 0.28 + (index % 5) * 0.08
		local startOffset = Vector3.new(math.cos(angle) * radius, -0.05 + (index % 4) * 0.08, math.sin(angle) * radius)
		local endOffset = Vector3.new(math.cos(angle) * (1.0 + (index % 3) * 0.18), 0.25 + (index % 5) * 0.12, math.sin(angle) * (1.0 + (index % 4) * 0.13))
		particle.CFrame = CFrame.new(center + startOffset)
		particle.Transparency = 0.08
		particle.Parent = workspace
		local tween = TweenService:Create(
			particle,
			TweenInfo.new(0.48 + (index % 5) * 0.055, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(center + endOffset), Transparency = 1, Size = Vector3.new(size * 0.35, size * 0.35, size * 0.35) }
		)
		tween:Play()
		task.delay(0.85, function()
			if particle and particle.Parent then
				particle:Destroy()
			end
		end)
	end
end

local function spawnEggAppearBurst(state)
	emitEggPoof(state, Color3.fromRGB(255, 244, 205), Color3.fromRGB(170, 215, 255), 34)
end

local function spawnEggStoreBurst(state)
	emitEggPoof(state, Color3.fromRGB(190, 225, 255), Color3.fromRGB(255, 255, 255), 24)
end

local function setVisualScale(state, relativeScale)
	if not state.visualModel or not state.visualModel.Parent then
		return
	end
	local baseScale = state.visualBaseScale or 1
	local targetScale = baseScale * math.max(0.05, relativeScale)
	if math.abs(targetScale - (state.lastVisualScale or baseScale)) < 0.006 then
		return
	end
	state.lastVisualScale = targetScale
	pcall(function()
		state.visualModel:ScaleTo(targetScale)
	end)
end

local function getSpawnVisual(progress)
	progress = math.clamp(progress, 0, 1)
	if progress < 0.56 then
		local t = smootherStep(progress / 0.56)
		return SPAWN_START_SCALE + (SPAWN_OVERSHOOT_SCALE - SPAWN_START_SCALE) * t, -0.42 + 0.56 * t
	elseif progress < 0.78 then
		local t = smootherStep((progress - 0.56) / 0.22)
		return SPAWN_OVERSHOOT_SCALE + (0.96 - SPAWN_OVERSHOOT_SCALE) * t, 0.14 - 0.10 * t
	end
	local t = smootherStep((progress - 0.78) / 0.22)
	return 0.96 + (1 - 0.96) * t, 0.04 * (1 - t)
end

local function getDespawnVisual(progress)
	progress = math.clamp(progress, 0, 1)
	if progress < 0.28 then
		local t = smootherStep(progress / 0.28)
		return 1 + 0.07 * t, -0.04 * t
	end
	local t = smootherStep((progress - 0.28) / 0.72)
	return 1.07 + (DESPAWN_END_SCALE - 1.07) * t, -0.04 + 0.82 * t
end

local function getDirtyEggTorsoTemplate()
	local dirtyTemplate = workspace:FindFirstChild("Huevo sucio")
	return dirtyTemplate and (dirtyTemplate:FindFirstChild("Huevo Sucio", true) or dirtyTemplate:FindFirstChildWhichIsA("BasePart", true)) or nil
end

local function visualLooksDirty(state)
	local torso = getVisualTorso(state.visualModel)
	local dirtyTorso = getDirtyEggTorsoTemplate()
	if torso and dirtyTorso and torso:IsA("MeshPart") and dirtyTorso:IsA("MeshPart") then
		return torso.MeshId == dirtyTorso.MeshId
	end
	return state.visualDirtyAppearance == true
end

local function getEggAppearanceTemplate(state)
	local useDirty = isEggDirty(state)
	if useDirty then
		local dirtyTorso = getDirtyEggTorsoTemplate()
		if dirtyTorso then
			return dirtyTorso, true
		end
	else
		local petsFolder = ReplicatedStorage:FindFirstChild("Mascotas")
		local cleanTemplate = petsFolder and (petsFolder:FindFirstChild("Huevo Mascota") or petsFolder:FindFirstChild("Huevo") or petsFolder:FindFirstChild("HuevoBrizabelle"))
		local cleanTorso = getVisualTorso(cleanTemplate)
		if cleanTorso then
			return cleanTorso, false
		end
	end

	return getVisualTorso(state.sourcePet), useDirty
end

local function syncEggAppearanceFromSource(state, withEffect)
	local wasDirty = state and visualLooksDirty(state) == true
	if not state or not isEggPetType(state.petType) or not state.sourcePet or not state.visualModel or not state.root then
		return
	end

	local sourceTorso, useDirty = getEggAppearanceTemplate(state)
	local oldTorso = getVisualTorso(state.visualModel)
	if not sourceTorso or not oldTorso or not sourceTorso:IsA("BasePart") or not oldTorso:IsA("BasePart") then
		return
	end

	if state.appearanceTransition and state.appearanceTransition.oldTorso and state.appearanceTransition.oldTorso.Parent then
		state.appearanceTransition.oldTorso:Destroy()
	end
	state.appearanceTransition = nil

	for _, object in ipairs(state.visualModel:GetDescendants()) do
		if object:IsA("BasePart") and object.Name == "TorsoTransitionOld" then
			object:Destroy()
		end
	end

	local newTorso = sourceTorso:Clone()
	cleanClone(newTorso)
	newTorso.Name = "Torso"
	newTorso.CFrame = oldTorso.CFrame
	newTorso.Anchored = oldTorso.Anchored
	newTorso.CanCollide = false
	newTorso.CanTouch = false
	newTorso.CanQuery = false
	newTorso.Massless = true
	newTorso.CastShadow = oldTorso.CastShadow
	newTorso.LocalTransparencyModifier = 1 - math.clamp(state.renderAlpha or 1, 0, 1)
	newTorso.Parent = oldTorso.Parent

	for _, joint in ipairs(state.root:GetChildren()) do
		if joint:IsA("Motor6D") and joint.Part1 == oldTorso then
			joint.Part1 = newTorso
		end
	end

	oldTorso:Destroy()
	state.lastSourceTorso = getVisualTorso(state.sourcePet)
	state.visualDirtyAppearance = useDirty == true
	if withEffect and useDirty and not wasDirty then
		spawnDirtyBurst(state)
	end
end

local function requestEggAppearanceSync(state, delay)
	if not state or not isEggPetType(state.petType) then
		return
	end
	local now = os.clock()
	state.appearanceSyncAt = now + (delay or 0.05)
	state.appearanceSyncUntil = now + 1.25
end

local function updatePendingEggAppearanceSync(state, now)
	if not state.appearanceSyncAt or now < state.appearanceSyncAt then
		return
	end
	if state.appearanceSyncUntil and now > state.appearanceSyncUntil then
		state.appearanceSyncAt = nil
		state.appearanceSyncUntil = nil
		return
	end

	local useDirty = isEggDirty(state)
	if useDirty == state.visualDirtyAppearance then
		state.appearanceSyncAt = nil
		state.appearanceSyncUntil = nil
		return
	end

	state.appearanceSyncAt = nil
	state.appearanceSyncUntil = nil
	syncEggAppearanceFromSource(state, true)
end

local function hasDirtyBurst(state)
	if not state or not state.visualModel then
		return false
	end
	if state.dirtyBurstParticlesAliveUntil and os.clock() < state.dirtyBurstParticlesAliveUntil then
		return true
	end
	return state.visualModel:FindFirstChild("DirtyEggBurst", true) ~= nil
end

local function requestDirtyBurst(state, force)
	if not state or not isEggPetType(state.petType) then
		return
	end
	local now = os.clock()
	if not force and state.lastDirtyBurstAt and now - state.lastDirtyBurstAt < 0.35 then
		return
	end
	state.lastDirtyBurstAt = now
	state.dirtyBurstRetryUntil = now + 0.65
	if state.visualModel then
		state.visualModel:SetAttribute("DirtyBurstPassedCooldownAt", now)
	end
	spawnDirtyBurst(state)
end

local function bindEggValueDirty(state)
	if state.eggValueConnection then
		state.eggValueConnection:Disconnect()
		state.eggValueConnection = nil
	end

	local eggValue = getOwnerEggValue(state)
	if not eggValue then
		return
	end

	state.eggValue = eggValue
	state.eggValueConnection = eggValue:GetAttributeChangedSignal("Dirty"):Connect(function()
		if eggValue:GetAttribute("Dirty") == true then
			requestDirtyBurst(state, true)
			state.dirtySwapNotBefore = os.clock() + 0.36
		else
			state.dirtySwapNotBefore = nil
		end
		requestEggAppearanceSync(state, 0)
	end)
end

local function ensureEggAppearanceCurrent(state)
	if not state or not isEggPetType(state.petType) or not state.visualModel then
		return
	end
	local wantedDirty = isEggDirty(state)
	local actualDirty = visualLooksDirty(state)
	local now = os.clock()
	if not wantedDirty then
		state.dirtyEffectShownForState = false
		state.dirtyBurstRetryUntil = nil
		state.dirtyBurstParticlesAliveUntil = nil
		state.dirtySwapNotBefore = nil
	elseif not hasDirtyBurst(state) and (not state.lastDirtyBurstAt or now - state.lastDirtyBurstAt > 1.15) then
		state.dirtyEffectShownForState = true
		state.dirtySwapNotBefore = state.dirtySwapNotBefore or (now + 0.36)
		requestDirtyBurst(state, true)
	end
	state.lastWantedDirty = wantedDirty
	state.visualModel:SetAttribute("EggWantedDirty", wantedDirty)
	state.visualModel:SetAttribute("EggActualDirty", actualDirty)
	if wantedDirty ~= actualDirty then
		if wantedDirty and state.dirtySwapNotBefore and now < state.dirtySwapNotBefore then
			state.appearanceSyncAt = now + 0.03
			state.appearanceSyncUntil = now + 0.6
			return
		end
		state.visualModel:SetAttribute("EggSyncRequestedAt", os.clock())
		syncEggAppearanceFromSource(state, wantedDirty)
	else
		state.visualDirtyAppearance = wantedDirty
	end
end

local function updateEggAppearanceTransition(state, now)
	local transition = state.appearanceTransition
	if not transition then
		return
	end

	local oldTorso = transition.oldTorso
	local newTorso = transition.newTorso
	if not newTorso or not newTorso.Parent then
		if oldTorso and oldTorso.Parent then
			oldTorso:Destroy()
		end
		state.appearanceTransition = nil
		return
	end

	local progress = smootherStep((now - transition.startedAt) / transition.duration)
	local baseTransparency = 1 - math.clamp(state.renderAlpha or 1, 0, 1)
	newTorso.LocalTransparencyModifier = baseTransparency + (1 - baseTransparency) * (1 - progress)

	if oldTorso and oldTorso.Parent then
		oldTorso.CFrame = newTorso.CFrame
		oldTorso.LocalTransparencyModifier = baseTransparency + (1 - baseTransparency) * progress
	end

	if progress >= 1 then
		newTorso.LocalTransparencyModifier = baseTransparency
		if oldTorso and oldTorso.Parent then
			oldTorso:Destroy()
		end
		state.appearanceTransition = nil
	end
end

local function getOwnerRig(state)
	local owner = state.owner
	if not owner or not owner.Parent then
		owner = Players:GetPlayerByUserId(state.ownerId)
		state.owner = owner
	end
	if not owner then
		return nil, nil, nil
	end

	local character = owner.Character
	if not character or not character.Parent then
		return nil, nil, nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return nil, nil, nil
	end
	return character, root, humanoid
end

local function getGroundY(state, ownerCharacter, ownerRoot, position)
	rayParams.FilterDescendantsInstances = {
		ownerCharacter,
		state.sourcePet,
		state.visualModel,
	}

	local originY = math.max(ownerRoot.Position.Y, position.Y) + 10
	local hit = workspace:Raycast(Vector3.new(position.X, originY, position.Z), Vector3.new(0, -80, 0), rayParams)
	if hit then
		return hit.Position.Y + getNumber(state.config, "GroundOffset", 0)
	end
	return state.groundY or ownerRoot.Position.Y - 3 + getNumber(state.config, "GroundOffset", 0)
end

local function pathIsBlocked(state, ownerCharacter, fromPosition, toPosition)
	local from = Vector3.new(fromPosition.X, fromPosition.Y + OBSTACLE_CHECK_HEIGHT, fromPosition.Z)
	local to = Vector3.new(toPosition.X, from.Y, toPosition.Z)
	local direction = to - from
	if direction.Magnitude < 1 then
		return false
	end

	rayParams.FilterDescendantsInstances = {
		ownerCharacter,
		state.sourcePet,
		state.visualModel,
	}

	local hit = workspace:Raycast(from, direction, rayParams)
	return hit ~= nil
end

local function beginDespawn(sourcePet)
	local state = states[sourcePet]
	if not state or state.despawning then
		return
	end
	state.despawning = true
	state.despawnStartedAt = os.clock()
	if isEggPetType(state.petType) then
		spawnEggStoreBurst(state)
	end
	state.sourcePet = nil
	stopTracks(state)
end

local function destroyState(sourcePet, state)
	if state.visualKey and activeVisualKeys[state.visualKey] == sourcePet then
		activeVisualKeys[state.visualKey] = nil
	end
	if state.appearanceConnection then
		state.appearanceConnection:Disconnect()
		state.appearanceConnection = nil
	end
	if state.sourceDescendantConnection then
		state.sourceDescendantConnection:Disconnect()
		state.sourceDescendantConnection = nil
	end
	if state.dirtyAppearanceConnection then
		state.dirtyAppearanceConnection:Disconnect()
		state.dirtyAppearanceConnection = nil
	end
	if state.eggValueConnection then
		state.eggValueConnection:Disconnect()
		state.eggValueConnection = nil
	end
	if state.ownerInventoryConnection then
		state.ownerInventoryConnection:Disconnect()
		state.ownerInventoryConnection = nil
	end
	if state.appearanceTransition and state.appearanceTransition.oldTorso and state.appearanceTransition.oldTorso.Parent then
		state.appearanceTransition.oldTorso:Destroy()
	end
	state.appearanceTransition = nil
	stopTracks(state)
	for _, animation in ipairs(state.animationInstances or {}) do
		if animation.Parent then
			animation:Destroy()
		end
	end
	if state.visualModel and state.visualModel.Parent then
		state.visualModel:Destroy()
	end
	restoreSavedProperties(state.savedSourceProperties)
	states[sourcePet] = nil
end

local function getVisualKey(ownerId, petType)
	return tostring(ownerId) .. ":" .. tostring(petType or "")
end

local function clearDuplicateVisuals(ownerId, petType, keepSource)
	local visualKey =
		getVisualKey(
			ownerId,
			petType
		)

	-- Un jugador solo tiene un follower visual activo.
	-- Al cambiar de huevo -> mascota o de un tier -> otro,
	-- quitar inmediatamente el visual anterior.
	for sourcePet, state in pairs(states) do
		if sourcePet ~= keepSource
			and state.ownerId == ownerId then

			destroyState(
				sourcePet,
				state
			)
		end
	end

	for _, model in ipairs(
		workspace:GetChildren()
		) do
		if model:IsA("Model")
			and model:GetAttribute(
				CLIENT_OBJECT_ATTRIBUTE
			) == true
				and model:GetAttribute(
					"Owner"
				) == ownerId then

			model:Destroy()
		end
	end

	-- Limpiar cualquier key visual anterior del mismo jugador.
	local prefix =
		tostring(ownerId)
		.. ":"

	for key in pairs(
		activeVisualKeys
		) do
		if string.sub(
			key,
			1,
			#prefix
			) == prefix then

			activeVisualKeys[key] = nil
		end
	end

	activeVisualKeys[visualKey] =
		keepSource

	return visualKey
end

local function tryRegisterPet(sourcePet)
	if states[sourcePet] or not sourcePet:IsA("Model") or sourcePet.Parent ~= workspace or sourcePet:GetAttribute(CLIENT_OBJECT_ATTRIBUTE) == true then
		return
	end

	local ownerId = sourcePet:GetAttribute("Owner")
	local petType = sourcePet:GetAttribute("PetType")
	local config = petType and PetConfigs[petType]
	if typeof(ownerId) ~= "number" or not config then
		return
	end

	if isOwnerPetResting(ownerId, petType) or sourcePet:GetAttribute("Resting") == true then
		return
	end

	local visualKey = clearDuplicateVisuals(ownerId, petType, sourcePet)
	if activeVisualKeys[visualKey] ~= sourcePet then
		return
	end

	local visualModel = createVisualModel(sourcePet)
	if not visualModel then
		return
	end

	local root = visualModel:FindFirstChild("HumanoidRootPart") or visualModel.PrimaryPart or visualModel:FindFirstChildWhichIsA("BasePart")
	local humanoid = visualModel:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		visualModel:Destroy()
		return
	end

	configureVisualModel(visualModel, root, humanoid)
	local savedSourceProperties = hideModelLocally(sourcePet)
	local owner = Players:GetPlayerByUserId(ownerId)
	local ownerRoot = owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
	local initialForward = ownerRoot and flatUnit(ownerRoot.CFrame.LookVector, Vector3.new(0, 0, -1)) or flatUnit(root.CFrame.LookVector, Vector3.new(0, 0, -1))
	local now = os.clock()

	local state = {
		sourcePet = sourcePet,
		ownerId = ownerId,
		owner = owner,
		petType = petType,
		visualKey = visualKey,
		config = config,
		visualModel = visualModel,
		root = root,
		humanoid = humanoid,
		savedSourceProperties = savedSourceProperties,
		position = root.Position,
		positionVelocity = Vector3.zero,
		forward = initialForward,
		ownerForward = initialForward,
		groundY = nil,
		lastOwnerPosition = ownerRoot and ownerRoot.Position or root.Position,
		lastPosition = root.Position,
		idleBlend = 0,
		moving = false,
		idleTime = 0,
		landed = false,
		flightBlend = config.Flying == true and 1 or 0,
		spawnedAt = now,
		renderAlpha = 0,
		visualBaseScale = 1,
		lastVisualScale = 1,
		tracks = {},
		animationInstances = {},
		currentTrack = nil,
		currentTrackName = nil,
		animationSpeed = 1,
		lastAppliedAnimationSpeed = 0,
		specialUntil = nil,
		nextSpecialAt = now + math.random(10, 18),
	}

	pcall(function()
		state.visualBaseScale = visualModel:GetScale()
		state.lastVisualScale = state.visualBaseScale
	end)
	state.appearanceVersion = tonumber(sourcePet:GetAttribute("EggAppearanceVersion")) or 0
	if isEggPetType(petType) then
		state.lastSourceTorso = getVisualTorso(sourcePet)
		state.visualDirtyAppearance = isEggDirty(state)
		state.appearanceConnection = sourcePet:GetAttributeChangedSignal("EggAppearanceVersion"):Connect(function()
			local nextVersion = tonumber(sourcePet:GetAttribute("EggAppearanceVersion")) or 0
			if nextVersion ~= state.appearanceVersion then
				state.appearanceVersion = nextVersion
				requestEggAppearanceSync(state, 0)
			end
		end)
		state.dirtyAppearanceConnection = sourcePet:GetAttributeChangedSignal("DirtyEggVisual"):Connect(function()
			if sourcePet:GetAttribute("DirtyEggVisual") == true then
				requestDirtyBurst(state)
			end
			requestEggAppearanceSync(state, 0)
		end)
		state.sourceDescendantConnection = sourcePet.DescendantAdded:Connect(function(object)
			if object:IsA("BasePart") then
				object.LocalTransparencyModifier = 1
				if object.Name == "Torso" then
					requestEggAppearanceSync(state, 0)
				end
			end
		end)
		bindEggValueDirty(state)
		local inventory = state.owner and state.owner:FindFirstChild("TradePetsInventory")
		if inventory then
			state.ownerInventoryConnection = inventory.ChildAdded:Connect(function()
				task.defer(function()
					bindEggValueDirty(state)
					requestEggAppearanceSync(state, 0)
				end)
			end)
		end
		syncEggAppearanceFromSource(state, false)
	end

	states[sourcePet] = state
	loadAnimations(state)
	setupProceduralIdle(state)
	playTrack(state, "AFK", 0.05)
end

local function scanPets()
	for sourcePet, state in pairs(states) do
		if sourcePet.Parent ~= workspace and not state.despawning then
			beginDespawn(sourcePet)
		end
	end
	for _, object in ipairs(workspace:GetChildren()) do
		tryRegisterPet(object)
	end
end

local function computeDesiredPosition(state, ownerCharacter, ownerRoot, ownerHumanoid, ownerSpeed, playerMoving, dt)
	local rawForward = flatUnit(ownerRoot.CFrame.LookVector, state.ownerForward)
	state.ownerForward = flatUnit(state.ownerForward:Lerp(rawForward, responseAlpha(playerMoving and 22 or 12, dt)), rawForward)

	local forward = state.ownerForward
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local targetIdleBlend = playerMoving and 0 or 1
	state.idleBlend += (targetIdleBlend - state.idleBlend) * responseAlpha(playerMoving and 7 or 4.5, dt)

	local moveDistance = getNumber(state.config, "MoveBackOffset", MOVE_BACK_OFFSET)
	local moveSide = getNumber(state.config, "MoveSideOffset", MOVE_SIDE_OFFSET)
	local idleSide = getNumber(state.config, "IdleSideOffset", IDLE_SIDE_OFFSET)
	local idleBack = getNumber(state.config, "IdleBackOffset", IDLE_BACK_OFFSET)

	local speedBlend = math.clamp(ownerSpeed / 16, 0, 1)
	local movingSlot = ownerRoot.Position - forward * moveDistance * speedBlend + right * moveSide
	local idleSlot = ownerRoot.Position - forward * idleBack + right * idleSide
	local desired = movingSlot:Lerp(idleSlot, state.idleBlend)

	if pathIsBlocked(state, ownerCharacter, ownerRoot.Position, desired) then
		local blend = state.idleBlend
		local candidates = {
			ownerRoot.Position - forward * (moveDistance + AVOIDANCE_EXTRA_BACK) + right * (moveSide + AVOIDANCE_EXTRA_SIDE),
			ownerRoot.Position - forward * (moveDistance + AVOIDANCE_EXTRA_BACK) - right * (moveSide + AVOIDANCE_EXTRA_SIDE),
			ownerRoot.Position - forward * idleBack + right * (idleSide + AVOIDANCE_EXTRA_SIDE),
			ownerRoot.Position - forward * idleBack - right * (idleSide + AVOIDANCE_EXTRA_SIDE),
		}

		for _, candidate in ipairs(candidates) do
			local blendedCandidate = candidate:Lerp(desired, 1 - math.clamp(blend, 0, 1) * 0.35)
			if not pathIsBlocked(state, ownerCharacter, ownerRoot.Position, blendedCandidate) then
				desired = blendedCandidate
				break
			end
		end
	end

	local away = Vector3.new(desired.X - ownerRoot.Position.X, 0, desired.Z - ownerRoot.Position.Z)
	local minDistance = getNumber(state.config, "MinOwnerDistance", MIN_OWNER_DISTANCE)
	if away.Magnitude < minDistance then
		away = flatUnit(away, right) * minDistance
		desired = Vector3.new(ownerRoot.Position.X + away.X, desired.Y, ownerRoot.Position.Z + away.Z)
	end

	return desired, forward
end

local function updateDespawn(state, now)
	local rawProgress = math.clamp((now - state.despawnStartedAt) / DESPAWN_DURATION, 0, 1)
	state.renderAlpha = rawProgress < 0.86 and 1 or 0
	local scale, yOffset = getDespawnVisual(rawProgress)
	setVisualScale(state, scale)
	if state.root and state.root.Parent then
		local renderPosition = state.position + Vector3.new(0, yOffset, 0)
		state.root.CFrame = CFrame.lookAt(renderPosition, renderPosition + state.forward)
		setModelLocalTransparency(state.visualModel, 1 - state.renderAlpha)
	end
	return rawProgress < 1
end

local function updatePet(state, rawDt, now)
	if state.despawning then
		return updateDespawn(state, now)
	end

	if not state.sourcePet or state.sourcePet.Parent ~= workspace or not state.visualModel or state.visualModel.Parent ~= workspace or not state.root or not state.root.Parent then
		return false
	end
	if isOwnerPetResting(state.ownerId, state.petType) or state.sourcePet:GetAttribute("Resting") == true then
		return false
	end

	local dt = math.clamp(rawDt, MIN_DT, MAX_DT)
	state.lastDt = dt
	local ownerCharacter, ownerRoot, ownerHumanoid = getOwnerRig(state)
	if not ownerRoot then
		return true
	end

	local ownerVelocity = ownerRoot.AssemblyLinearVelocity
	local flatOwnerVelocity = Vector3.new(ownerVelocity.X, 0, ownerVelocity.Z)
	local ownerSpeed = flatOwnerVelocity.Magnitude
	local wantsToMove = ownerHumanoid.MoveDirection.Magnitude > 0.05
	local playerMoving = wantsToMove or ownerSpeed > 0.45

	local ownerDelta = ownerRoot.Position - (state.lastOwnerPosition or ownerRoot.Position)
	local flatOwnerDelta = Vector3.new(ownerDelta.X, 0, ownerDelta.Z)
	if playerMoving and flatOwnerDelta.Magnitude < 8 then
		state.position += flatOwnerDelta * getNumber(state.config, "OwnerDeltaMatch", 1)
	end
	state.lastOwnerPosition = ownerRoot.Position

	local desiredPosition, ownerForward = computeDesiredPosition(state, ownerCharacter, ownerRoot, ownerHumanoid, ownerSpeed, playerMoving, dt)

	local horizontalError = Vector3.new(desiredPosition.X - state.position.X, 0, desiredPosition.Z - state.position.Z).Magnitude
	local flying = state.config.Flying == true
	if flying and not wantsToMove then
		playerMoving = false
	end
	local rawGroundY = getGroundY(state, ownerCharacter, ownerRoot, desiredPosition)
	if state.groundY == nil or math.abs(rawGroundY - state.groundY) > 6 then
		state.groundY = rawGroundY
	else
		state.groundY += (rawGroundY - state.groundY) * responseAlpha(getNumber(state.config, "GroundResponseSpeed", 10), dt)
	end

	if flying then
		if wantsToMove or state.config.AlwaysFloat == true then
			state.flightAnimationHoldUntil = now + 0.18
		else
			state.flightAnimationHoldUntil = nil
			state.specialUntil = nil
			-- updateAnimation controla la secuencia AFK -> AFK2; forzar AFK aqui reiniciaba el picoteo.
		end

		if state.config.AlwaysFloat == true then
			state.flightBlend = 1
		elseif wantsToMove then
			state.flightBlend += (1 - state.flightBlend) * responseAlpha(getNumber(state.config, "FlyTakeoffResponse", 5.5), dt)
		else
			state.flightBlend = 0
		end
	else
		state.flightBlend = 0
	end

	local bob = 0
	if flying then
		bob = math.sin(now * getNumber(state.config, "FlyBobSpeed", 1.35) + state.ownerId % 17) * getNumber(state.config, "FlyBobAmp", 0.045) * state.flightBlend
	end
	local targetY = state.groundY + getNumber(state.config, "FlyHeight", 1.55) * state.flightBlend + bob

	desiredPosition = Vector3.new(desiredPosition.X, targetY, desiredPosition.Z)
	if flying and not wantsToMove and state.config.AlwaysFloat ~= true then
		state.position = Vector3.new(state.position.X, state.groundY, state.position.Z)
		desiredPosition = Vector3.new(desiredPosition.X, state.groundY, desiredPosition.Z)
		state.positionVelocity = Vector3.new(state.positionVelocity.X, 0, state.positionVelocity.Z)
	end
	local distance = (desiredPosition - state.position).Magnitude
	if distance > SNAP_DISTANCE then
		state.position = desiredPosition
		state.positionVelocity = Vector3.zero
	else
		local smoothTime = playerMoving and getNumber(state.config, "MoveSmoothTime", 0.075) or getNumber(state.config, "IdleSmoothTime", 0.15)
		local maxSpeed = math.max(getNumber(state.config, "MaxFollowSpeed", 110), ownerSpeed + getNumber(state.config, "CatchupSpeedBonus", 60))
		state.position, state.positionVelocity = smoothDampVector(state.position, desiredPosition, state.positionVelocity, smoothTime, maxSpeed, dt)
	end

	local ownerPlanar = Vector3.new(ownerRoot.Position.X, 0, ownerRoot.Position.Z)
	local petPlanar = Vector3.new(state.position.X, 0, state.position.Z)
	local ownerToPet = petPlanar - ownerPlanar
	local minOwnerDistance = getNumber(state.config, "MinOwnerDistance", MIN_OWNER_DISTANCE)
	if ownerToPet.Magnitude < minOwnerDistance then
		local pushDirection = flatUnit(ownerToPet, Vector3.new(-ownerForward.Z, 0, ownerForward.X))
		local corrected = Vector3.new(
			ownerRoot.Position.X + pushDirection.X * minOwnerDistance,
			state.position.Y,
			ownerRoot.Position.Z + pushDirection.Z * minOwnerDistance
		)
		state.position = state.position:Lerp(corrected, responseAlpha(24, dt))
		state.positionVelocity *= 0.35
	end

	local actualMove = state.position - state.lastPosition
	local planarMove = Vector3.new(actualMove.X, 0, actualMove.Z)

	-- La mascota puede desplazarse lateralmente para acomodarse,
	-- pero ya NO gira hacia la dirección de ese desplazamiento.
	-- Siempre mantiene el mismo frente que el jugador.
	local desiredLook = ownerForward

	state.forward = flatUnit(
		state.forward:Lerp(
			desiredLook,
			responseAlpha(playerMoving and 9 or 7, dt)
		),
		desiredLook
	)

	state.root.CFrame = CFrame.lookAt(state.position, state.position + state.forward)

	local petSpeed = planarMove.Magnitude / math.max(dt, MIN_DT)
	local isMoving
	if state.moving then
		isMoving = playerMoving or petSpeed > 0.10 or horizontalError > 0.14
	else
		isMoving = playerMoving or petSpeed > 0.28 or horizontalError > 0.32
	end
	if flying and not wantsToMove then
		if state.config.AlwaysFloat == true then
			-- El pez sigue flotando, pero si el jugador está quieto
			-- las pequeñas correcciones/bob no cuentan como movimiento.
			isMoving = false
			state.specialUntil = nil
		elseif (state.flightBlend or 0) <= 0.12 then
			isMoving = false
			state.specialUntil = nil
		end
	end

	if state.config.StopMovementAnimationWhenIdle == true and not playerMoving then
		isMoving = false
	end
	state.moving = isMoving

	if state.sourcePet:GetAttribute("IsMoving") ~= isMoving then
		state.sourcePet:SetAttribute("IsMoving", isMoving)
	end

	updateAnimation(state, isMoving, ownerSpeed, petSpeed, now, dt, playerMoving)
	updateProceduralIdle(state, now)

	if state.config.UseBoundingGroundCorrection == true then
		local boundsCFrame, boundsSize = state.visualModel:GetBoundingBox()
		local boundsBottomY = boundsCFrame.Position.Y - boundsSize.Y * 0.5
		rayParams.FilterDescendantsInstances = {
			ownerCharacter,
			state.sourcePet,
			state.visualModel,
		}
		local probeHeight = math.max(boundsSize.Y + 4, 8)
		local hit = workspace:Raycast(
			Vector3.new(boundsCFrame.Position.X, state.position.Y + probeHeight * 0.5, boundsCFrame.Position.Z),
			Vector3.new(0, -probeHeight - 8, 0),
			rayParams
		)
		if hit then
			local targetBottomY = hit.Position.Y + getNumber(state.config, "GroundClearance", 0.02)
			local yCorrection = targetBottomY - boundsBottomY
			if math.abs(yCorrection) > 0.01 and math.abs(yCorrection) < 4 then
				state.position += Vector3.new(0, yCorrection, 0)
				state.root.CFrame = CFrame.lookAt(state.position, state.position + state.forward)
			end
		end
	end

	state.lastPosition = state.position

	local rawSpawnProgress = math.clamp((now - state.spawnedAt) / SPAWN_DURATION, 0, 1)
	local spawnVisible = rawSpawnProgress >= 0.035 and 1 or 0
	state.renderAlpha = math.max(state.renderAlpha or 0, spawnVisible)
	local visualScale, spawnYOffset = getSpawnVisual(rawSpawnProgress)
	setVisualScale(state, visualScale)
	if state.root and state.root.Parent then
		local renderPosition = state.position + Vector3.new(0, spawnYOffset, 0)
		state.root.CFrame = CFrame.lookAt(renderPosition, renderPosition + state.forward)
	end
	updatePendingEggAppearanceSync(state, now)
	ensureEggAppearanceCurrent(state)
	setModelLocalTransparency(state.visualModel, 1 - state.renderAlpha)
	updateEggAppearanceTransition(state, now)
	return true
end

local function destroyLocalOwnerVisuals()
	for sourcePet, state in pairs(states) do
		if state.ownerId == localPlayer.UserId then
			destroyState(sourcePet, state)
		end
	end
	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model") and model:GetAttribute(CLIENT_OBJECT_ATTRIBUTE) == true and model:GetAttribute("Owner") == localPlayer.UserId then
			model:Destroy()
		end
	end
end

localPlayer.CharacterAdded:Connect(function()
	task.defer(destroyLocalOwnerVisuals)
end)

destroyLocalOwnerVisuals()

workspace.ChildAdded:Connect(function(object)
	task.defer(tryRegisterPet, object)
end)

workspace.ChildRemoved:Connect(function(object)
	local state =
		states[object]

	if state then
		local replacementExists =
			false

		for _, candidate in ipairs(
			workspace:GetChildren()
			) do
			if candidate:IsA("Model")
				and candidate ~= object
				and candidate:GetAttribute(
					CLIENT_OBJECT_ATTRIBUTE
				) ~= true
					and candidate:GetAttribute(
						"Owner"
					) == state.ownerId
					and candidate:GetAttribute(
						"PetType"
					) ~= nil then

				replacementExists = true
				break
			end
		end

		if replacementExists
			or isOwnerPetResting(
				state.ownerId,
				state.petType
			)
				or object:GetAttribute(
					"Resting"
				) == true then

			-- Si ya llegó la nueva mascota/tier,
			-- no animar la vieja encima de ella.
			destroyState(
				object,
				state
			)
		else
			beginDespawn(object)
		end
	end
end)

scanPets()

for _, name in ipairs(OLD_RENDER_NAMES) do
	RunService:UnbindFromRenderStep(name)
end
RunService:UnbindFromRenderStep(RENDER_NAME)
RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Last.Value, function(rawDt)
	local now = os.clock()
	scanElapsed += rawDt
	if scanElapsed >= SCAN_INTERVAL then
		scanElapsed = 0
		scanPets()
	end

	local toDestroy = {}
	for sourcePet, state in pairs(states) do
		local ok, keep = pcall(updatePet, state, rawDt, now)
		if not ok then
			warn("[PetRenderer] Error:", keep)
			beginDespawn(sourcePet)
		elseif not keep then
			table.insert(toDestroy, { sourcePet, state })
		end
	end

	for _, item in ipairs(toDestroy) do
		destroyState(item[1], item[2])
	end
end)

warn("[PetRenderer] V6 VISUAL UNICO activo | cambios de mascota/tier sin clones superpuestos.")