local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TutorialShared = {}

local function normalized(text)
	text = tostring(text or "")
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	return string.lower(text)
end

local function findChildFlexible(parent, wanted)
	if not parent then return nil end
	local exact = parent:FindFirstChild(wanted)
	if exact then return exact end

	local key = normalized(wanted)
	for _, child in ipairs(parent:GetChildren()) do
		if normalized(child.Name) == key then
			return child
		end
	end
	return nil
end

function TutorialShared.BuildStepMap(config)
	local map, order = {}, {}
	for i, step in ipairs(config.Steps) do
		step.Index = i
		map[step.Id] = step
		order[i] = step.Id
	end
	return map, order
end

function TutorialShared.ResolvePath(path, player)
	if typeof(path) ~= "table" or #path == 0 then return nil end

	local current
	local first = path[1]
	if first == "Workspace" then
		current = workspace
	elseif first == "ReplicatedStorage" then
		current = ReplicatedStorage
	elseif first == "StarterGui" then
		current = game:GetService("StarterGui")
	elseif first == "PlayerGui" and player then
		current = player:FindFirstChildOfClass("PlayerGui")
	else
		current = game:FindFirstChild(tostring(first))
	end

	if not current then return nil end
	for i = 2, #path do
		current = findChildFlexible(current, path[i])
		if not current then return nil end
	end
	return current
end

function TutorialShared.FindDescendantByName(root, name, className)
	if not root or not name then return nil end
	local key = normalized(name)
	for _, item in ipairs(root:GetDescendants()) do
		if normalized(item.Name) == key and (not className or item:IsA(className)) then
			return item
		end
	end
	return nil
end

local function findBySearchNames(names)
	if typeof(names) ~= "table" then return nil end
	for _, name in ipairs(names) do
		local direct = findChildFlexible(workspace, name)
		if direct then return direct end
		local recursive = TutorialShared.FindDescendantByName(workspace, name)
		if recursive then return recursive end
	end
	return nil
end

local function findPromptInside(root, promptName)
	if not root or not promptName then return nil end
	local key = normalized(promptName)
	if root:IsA("ProximityPrompt") and normalized(root.Name) == key then
		return root
	end
	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("ProximityPrompt") and normalized(item.Name) == key then
			return item
		end
	end
	return nil
end

local function targetFromPrompt(promptName)
	if not promptName then return nil end
	local key = normalized(promptName)
	for _, item in ipairs(workspace:GetDescendants()) do
		if item:IsA("ProximityPrompt") and normalized(item.Name) == key then
			-- El prompt es el ancla mas confiable. Si pertenece a un NPC,
			-- usamos el modelo mas cercano; si no, usamos la pieza padre.
			local parent = item.Parent
			local model = parent and parent:FindFirstAncestorOfClass("Model")
			return model or parent or item
		end
	end
	return nil
end

function TutorialShared.FindTarget(step, player)
	if not step then return nil end

	if step.DynamicTarget == "PlayerHouse" then
		local houses = workspace:FindFirstChild("Casas") or workspace:FindFirstChild("Houses") or workspace:FindFirstChild("PlayerHouses")
		if houses then
			for _, house in ipairs(houses:GetChildren()) do
				if house:GetAttribute("OwnerUserId") == player.UserId or house:GetAttribute("Owner") == player.Name then
					return house
				end
			end
		end
	elseif step.DynamicTarget == "PlayerHouseDoor" then
		local house = TutorialShared.FindTarget({DynamicTarget = "PlayerHouse"}, player)
		return house and (TutorialShared.FindDescendantByName(house, "Door") or TutorialShared.FindDescendantByName(house, "Entrada") or house)
	elseif step.DynamicTarget == "PlayerGarden" then
		local house = TutorialShared.FindTarget({DynamicTarget = "PlayerHouse"}, player)
		return house and (TutorialShared.FindDescendantByName(house, "Jardin") or TutorialShared.FindDescendantByName(house, "Garden") or house)
	end

	local target = step.Target
	if not target then return nil end

	-- 1) Rutas exactas, pero si el paso declara PromptName comprobamos
	-- que realmente sea el NPC/objeto que contiene ese prompt.
	if target.PathCandidates then
		for _, path in ipairs(target.PathCandidates) do
			local found = TutorialShared.ResolvePath(path, player)
			if found then
				if not target.PromptName or findPromptInside(found, target.PromptName) then
					return found
				end
			end
		end
	end

	if target.Path then
		local found = TutorialShared.ResolvePath(target.Path, player)
		if found and (not target.PromptName or findPromptInside(found, target.PromptName)) then
			return found
		end
	end

	-- 2) Respaldo fuerte: encuentra el ProximityPrompt real sin importar
	-- en que carpeta del mapa se encuentre Brizabelle/Frank/Lex.
	if target.PromptName then
		local byPrompt = targetFromPrompt(target.PromptName)
		if byPrompt then return byPrompt end
	end

	-- 3) Ultimo respaldo por nombre.
	return findBySearchNames(target.SearchNames)
end

local function nearestBasePart(root, origin)
	local best, bestDistance
	if root:IsA("BasePart") then return root end

	local candidates = {}
	if root:IsA("Model") then
		if root.PrimaryPart then return root.PrimaryPart end
		local hrp = root:FindFirstChild("HumanoidRootPart", true)
		if hrp and hrp:IsA("BasePart") then return hrp end
	end

	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("BasePart") then
			table.insert(candidates, item)
		end
	end

	if not origin then return candidates[1] end
	for _, part in ipairs(candidates) do
		local d = (part.Position - origin).Magnitude
		if not bestDistance or d < bestDistance then
			best, bestDistance = part, d
		end
	end
	return best
end

function TutorialShared.GetAdornee(target, origin)
	if not target then return nil end
	if target:IsA("Attachment") then return target.Parent end
	return nearestBasePart(target, origin)
end

function TutorialShared.GetWorldPosition(target, origin)
	local part = TutorialShared.GetAdornee(target, origin)
	if part and part:IsA("BasePart") then return part.Position end
	return nil
end

function TutorialShared.DistanceToCharacter(player, target)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return math.huge end
	local pos = TutorialShared.GetWorldPosition(target, root.Position)
	if pos then return (root.Position - pos).Magnitude end
	return math.huge
end

local function resolveGuiPath(player, path)
	if typeof(path) ~= "table" then return nil end
	local current = player:FindFirstChildOfClass("PlayerGui")
	if not current then return nil end
	for _, name in ipairs(path) do
		current = findChildFlexible(current, name)
		if not current then return nil end
	end
	return current
end

function TutorialShared.FindGuiObject(player, descriptor)
	if typeof(descriptor) == "table" and descriptor.Candidates then
		for _, path in ipairs(descriptor.Candidates) do
			local found = resolveGuiPath(player, path)
			if found then return found end
		end
		if descriptor.DescendantName then
			local pg = player:FindFirstChildOfClass("PlayerGui")
			return pg and TutorialShared.FindDescendantByName(pg, descriptor.DescendantName)
		end
		return nil
	end

	if typeof(descriptor) == "table" and descriptor.Path then
		local found = resolveGuiPath(player, descriptor.Path)
		if found then return found end
		if descriptor.DescendantName then
			local pg = player:FindFirstChildOfClass("PlayerGui")
			return pg and TutorialShared.FindDescendantByName(pg, descriptor.DescendantName)
		end
		return nil
	end

	if typeof(descriptor) == "table" then
		return resolveGuiPath(player, descriptor)
	end

	return nil
end

return TutorialShared
