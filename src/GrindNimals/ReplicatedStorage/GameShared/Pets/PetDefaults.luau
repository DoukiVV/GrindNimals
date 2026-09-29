--============================================================
-- PetDefaults
-- Tipo: ModuleScript
-- Ubicacion:
-- ReplicatedStorage > GameShared > Pets > PetDefaults
--
-- IMPORTANTE:
-- Estos valores reproducen EXACTAMENTE el comportamiento final
-- que tenia tu PetConfigs anterior despues de su "for".
--============================================================

local PetDefaults = {}

function PetDefaults.Apply(config)
	-- Copiar para no modificar accidentalmente una tabla compartida.
	local result = {}

	for key, value in pairs(config or {}) do
		result[key] = value
	end

	-- Mismos overrides globales de tu PetConfigs actual.
	result.MoveSmoothTime = 0.075
	result.IdleSmoothTime = 0.15
	result.MaxFollowSpeed = 110
	result.CatchupSpeedBonus = 60
	result.OwnerDeltaMatch = 1
	result.MoveBackOffset = 0.10
	result.MoveSideOffset = math.max(result.SideOffset or 2.85, 2.85)
	result.IdleSideOffset = 2.95
	result.IdleBackOffset = 0.05
	result.MinOwnerDistance = 2.55
	result.GroundRayInterval = result.GroundRayInterval or (1 / 18)
	result.GroundResponseSpeed = math.min(result.GroundResponseSpeed or 12, 12)
	result.GroundDeadband = math.max(result.GroundDeadband or 0.07, 0.07)
	result.DisableIdleSpecials = true
	result.FlyLandResponse = 26
	result.FlyTakeoffResponse = 9
	result.FlyBobAmp = math.min(result.FlyBobAmp or 0.03, 0.03)

	return result
end

return PetDefaults
