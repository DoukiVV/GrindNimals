--============================================================
-- PetConfigs
-- Tipo: ModuleScript
-- Ubicacion:
-- ReplicatedStorage > GameShared > Pets > PetConfigs
--
-- Configuracion compartida de mascotas.
-- Conserva el comportamiento FINAL de tu PetConfigs anterior.
--============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local petsFolder = script.Parent
local PetDefaults = require(petsFolder:WaitForChild("PetDefaults"))

local PetConfigs = {}

local function add(name, config)
	PetConfigs[name] = PetDefaults.Apply(config)
end

add("Huron", {
	Walk = "rbxassetid://107956799447038",
	Sleep = "rbxassetid://90805147728586",
	Jump = "rbxassetid://75740283792667",
	Eat = "rbxassetid://97587839677949",
	Dig = "rbxassetid://134078092705158",
	Celebrate = "rbxassetid://107334345792420",
	AFK = "rbxassetid://80836958951413",

	Flying = false,
	GroundOffset = 1.19,
	FollowDistance = 2.35,
	SideOffset = 1.90,
	LeadTime = 0.045,
	FollowSmoothTime = 0.12,
	MaxFollowSpeed = 62,
	RotationSpeed = 14,
	SlotTurnSpeed = 14,
	VelocitySmoothSpeed = 12,
	VerticalResponseSpeed = 15,
	GroundResponseSpeed = 14,
	GroundDeadband = 0.06,
})

add("Oveja", {
	Walk = "rbxassetid://95823895461748",
	Sleep = "rbxassetid://104759470412563",
	Jump = "rbxassetid://122296470703896",
	Eat = "rbxassetid://99318367678565",
	Dig = "rbxassetid://100877008135825",
	Celebrate = "rbxassetid://117545576014671",
	AFK = "rbxassetid://70601312688541",

	Flying = false,
	GroundOffset = 1.16,
	TrailDelay = 0.16,
	FollowDistance = 3.30,
	SideOffset = 1.80,
	LeadTime = 0,
	FollowSmoothTime = 0.09,
	FollowResponseSpeed = 13,
	MaxFollowSpeed = 65,
	VelocitySmoothSpeed = 15,
	SlotTurnSpeed = 14,
	RotationSpeed = 14,
	VerticalResponseSpeed = 14,
	GroundResponseSpeed = 12,
	GroundDeadband = 0.05,
})

add("PezDorado", {
	Walk = "rbxassetid://139685752581011",
	Sleep = "rbxassetid://109376664594631",
	Jump = "rbxassetid://108065218675664",
	Eat = "rbxassetid://109726874528559",
	Dig = "rbxassetid://75868276345599",
	Celebrate = "rbxassetid://117537527453545",
	AFK = "rbxassetid://137359828606349",

	Flying = true,
	AlwaysFloat = true,
	FlyHeight = 4.5,
	FlyBobSpeed = 1.4,
	FlyBobAmp = 0.08,
	FollowDistance = 2.35,
	SideOffset = 2.00,
	LeadTime = 0.05,
	FollowSmoothTime = 0.12,
	MaxFollowSpeed = 65,
	RotationSpeed = 14,
	SlotTurnSpeed = 14,
	VelocitySmoothSpeed = 11,
	VerticalResponseSpeed = 10,
})

add("Hamster", {
	Walk = "rbxassetid://137651983463128",
	Sleep = "rbxassetid://121320015825848",
	Jump = "rbxassetid://103884325038741",
	Eat = "rbxassetid://117926144147289",
	Dig = "rbxassetid://105864818910538",
	Celebrate = "rbxassetid://122985438417163",
	AFK = "rbxassetid://120969975329374",

	Flying = false,
	GroundOffset = 0.60,
	FollowDistance = 2.00,
	SideOffset = 1.70,
	LeadTime = 0.04,
	FollowSmoothTime = 0.10,
	MaxFollowSpeed = 68,
	RotationSpeed = 15,
	SlotTurnSpeed = 15,
	VelocitySmoothSpeed = 13,
	VerticalResponseSpeed = 16,
	GroundResponseSpeed = 15,
	GroundDeadband = 0.05,
})

add("Tortuga", {
	Walk = "rbxassetid://84831836518715",
	Sleep = "rbxassetid://120880996545406",
	Jump = "rbxassetid://74419313993862",
	Eat = "rbxassetid://112417226089222",
	Dig = "rbxassetid://113772863290468",
	Celebrate = "rbxassetid://135943296244785",
	AFK = "rbxassetid://82619201072923",

	Flying = false,
	GroundOffset = 1.34,
	FollowDistance = 2.50,
	SideOffset = 2.00,
	LeadTime = 0.035,
	FollowSmoothTime = 0.15,
	MaxFollowSpeed = 56,
	RotationSpeed = 11,
	SlotTurnSpeed = 11,
	VelocitySmoothSpeed = 10,
	VerticalResponseSpeed = 13,
	GroundResponseSpeed = 12,
	GroundDeadband = 0.08,
})

add("Conejo", {
	Walk = "rbxassetid://83838925484453",
	Sleep = "rbxassetid://123161623749006",
	Jump = "rbxassetid://100920497143078",
	Eat = "rbxassetid://80165275566980",
	Dig = "rbxassetid://96974496732361",
	Celebrate = "rbxassetid://112069550830825",
	AFK = "rbxassetid://116453515157495",

	Flying = false,
	GroundOffset = 0.99,
	FollowDistance = 2.20,
	SideOffset = 1.80,
	LeadTime = 0.045,
	FollowSmoothTime = 0.105,
	MaxFollowSpeed = 68,
	RotationSpeed = 15,
	SlotTurnSpeed = 15,
	VelocitySmoothSpeed = 13,
	VerticalResponseSpeed = 16,
	GroundResponseSpeed = 15,
	GroundDeadband = 0.05,
})

add("Gato", {
	Walk = "rbxassetid://126284294369244",
	Sleep = "rbxassetid://138979966517502",
	Jump = "rbxassetid://118536247530930",
	Eat = "rbxassetid://78227995076701",
	Dig = "rbxassetid://73116630846659",
	Celebrate = "rbxassetid://97822665648915",
	AFK = "rbxassetid://90989534843355",

	Flying = false,
	GroundOffset = 1.12,
	FollowDistance = 2.25,
	SideOffset = 1.90,
	LeadTime = 0.045,
	FollowSmoothTime = 0.11,
	MaxFollowSpeed = 64,
	RotationSpeed = 14,
	SlotTurnSpeed = 14,
	VelocitySmoothSpeed = 12,
	VerticalResponseSpeed = 15,
	GroundResponseSpeed = 14,
	GroundDeadband = 0.06,
})

add("Perico", {
	Walk = "rbxassetid://121350070746583",
	Sleep = "rbxassetid://123872709396156",
	Fly = "rbxassetid://77324811711174",
	Eat = "rbxassetid://73506341590325",
	Dig = "rbxassetid://82333382046358",
	Celebrate = "rbxassetid://139851173631170",
	AFK = "rbxassetid://75993556890001",
	AFK2 = "rbxassetid://96798006458508",

	AFK2Only = false,
	ProceduralPeckIdle = false,
	AFKIntroDuration = 0.45,
	AFK2Weight = 0.85,
	DisableIdleSpecials = true,

	Flying = true,
	FlyHeight = 1.45,
	FlyStartTime = 0,
	FlyLoopResetTime = 0,
	FlyTakeoffResponse = 5.5,
	FlyLandResponse = 18,
	FlyAnimFadeIn = 0.20,
	FlyAnimFadeOut = 0.16,
	FlyBobSpeed = 1.6,
	FlyBobAmp = 0.07,
	FollowDistance = 2.20,
	SideOffset = 1.90,
	LeadTime = 0.045,
	FollowSmoothTime = 0.10,
	MaxFollowSpeed = 72,
	RotationSpeed = 15,
	SlotTurnSpeed = 15,
	VelocitySmoothSpeed = 12,
	VerticalResponseSpeed = 11,

	LandWhenIdle = true,
	GroundOffset = 0.94,
	LandDelay = 0.40,
	LandDistance = 1.00,
	LandTakeoffDistance = 1.60,
	GroundResponseSpeed = 14,
	GroundDeadband = 0.06,
})

add("Perro", {
	Walk = "rbxassetid://103075949730879",
	Sleep = "rbxassetid://93000281783617",
	Jump = "rbxassetid://130298574585845",
	Eat = "rbxassetid://100966634557377",
	Dig = "rbxassetid://132582127598773",
	Celebrate = "rbxassetid://126199315087921",
	AFK = "rbxassetid://97965000610476",

	Flying = false,
	GroundOffset = 1.22,
	FollowDistance = 2.50,
	SideOffset = 2.00,
	LeadTime = 0.045,
	FollowSmoothTime = 0.125,
	MaxFollowSpeed = 62,
	RotationSpeed = 13,
	SlotTurnSpeed = 13,
	VelocitySmoothSpeed = 12,
	VerticalResponseSpeed = 15,
	GroundResponseSpeed = 14,
	GroundDeadband = 0.06,
})

add("HuevoBrizabelle", {
	Walk = "rbxassetid://77769558750997",
	Celebrate = "rbxassetid://105255804146095",

	Flying = false,
	GroundOffset = 2.36,
	FollowDistance = 2.25,
	SideOffset = 1.85,
	LeadTime = 0.035,
	FollowSmoothTime = 0.10,
	MaxFollowSpeed = 68,
	RotationSpeed = 14,
	SlotTurnSpeed = 14,
	VelocitySmoothSpeed = 12,
	VerticalResponseSpeed = 14,
	GroundResponseSpeed = 12,
	GroundDeadband = 0.06,
	UseBoundingGroundCorrection = true,
	GroundClearance = 0.12,
	StopMovementAnimationWhenIdle = true,
	DisableIdleSpecials = true,
})

--============================================================
-- ALIAS COMPATIBLES CON TODO TU SISTEMA ACTUAL
-- Comparten la MISMA tabla, igual que antes.
--============================================================

PetConfigs["Pajarillo"] = PetConfigs["Perico"]
PetConfigs["Pez dorado"] = PetConfigs["PezDorado"]
PetConfigs["Oveja de rosario"] = PetConfigs["Oveja"]
PetConfigs["Huevo Mascota"] = PetConfigs["HuevoBrizabelle"]

return PetConfigs
