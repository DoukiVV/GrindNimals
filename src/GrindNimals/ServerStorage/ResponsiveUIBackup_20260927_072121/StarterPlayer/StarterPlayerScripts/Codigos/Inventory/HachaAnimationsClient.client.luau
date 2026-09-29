--============================================================
-- HACHAS - EQUIPAR / DESEQUIPAR CENTRAL V5
--
-- TIPO:
-- LocalScript
--
-- UBICACION:
-- StarterPlayer > StarterPlayerScripts > HachaAnimationsClient
--
-- IMPORTANTE:
-- La animacion de TALAR ahora pertenece a TreeChopClient.
--
-- Quitamos temporalmente:
--   SOSTENER 74608948544094
--   ATACAR   121538855198975
--
-- porque tu Output confirma:
--   121538855198975 = experiencia SIN permiso
--   74608948544094  = Length 0
--
-- Así evitamos conflictos y errores mientras talas.
--============================================================

local Players = game:GetService("Players")

local player=Players.LocalPlayer
local backpack=player:WaitForChild("Backpack")

local SOUND_VOLUME=0.22
local EQUIP_ANIMATION_ID="rbxassetid://90367603598475"

local animation=Instance.new("Animation")
animation.Name="AxeEquip"
animation.AnimationId=EQUIP_ANIMATION_ID

local connected={}
local states={}

local function isAxe(tool)
	return tool
		and tool:IsA("Tool")
		and tool.Name:lower():match("^hacha")~=nil
end

local function getAnimator()
	local character=player.Character
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end

	local animator=humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator=Instance.new("Animator")
		animator.Parent=humanoid
	end
	return animator
end

local function playSound(tool,name)
	local sound=tool:FindFirstChild(name,true)
	if not sound or not sound:IsA("Sound") then return end

	sound.Volume=SOUND_VOLUME
	pcall(function()
		sound:Stop()
		sound.TimePosition=0
		sound:Play()
	end)
end

local function stopTrack(track)
	if track then
		pcall(function() track:Stop(0.08) end)
	end
end

local function connect(tool)
	if not isAxe(tool) or connected[tool] then return end

	local state={track=nil}
	states[tool]=state
	local list={}

	table.insert(list,tool.Equipped:Connect(function()
		playSound(tool,"Equipar")

		local animator=getAnimator()
		if not animator then return end

		stopTrack(state.track)

		local ok,track=pcall(function()
			return animator:LoadAnimation(animation)
		end)

		if ok and track then
			track.Priority=Enum.AnimationPriority.Action4
			track.Looped=false
			track:Play(0.05)
			state.track=track

			task.delay(1,function()
				if track and track.Length<=0 then
					warn("[HachaAnimations] EQUIPAR tiene Length 0. ID:",EQUIP_ANIMATION_ID)
				end
			end)
		end
	end))

	table.insert(list,tool.Unequipped:Connect(function()
		stopTrack(state.track)
		state.track=nil
		playSound(tool,"Desequipar")
	end))

	connected[tool]=list
end

local function scan(container)
	for _,child in ipairs(container:GetChildren()) do
		connect(child)
	end
end

scan(backpack)
backpack.ChildAdded:Connect(connect)

local function characterAdded(character)
	scan(character)
	character.ChildAdded:Connect(connect)
end

if player.Character then characterAdded(player.Character) end
player.CharacterAdded:Connect(characterAdded)