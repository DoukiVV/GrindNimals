-- GrindNimals UI audit (Studio only). Observational: never moves, scales or edits GUIs.
-- Run Play in the device emulator, filter Studio Output by [GN-UI-AUDIT],
-- then copy the lines into the chat to diagnose the real UI owners.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local Players = game:GetService("Players")
local player = Players.LocalPlayer
if not player then
	return
end

local playerGui = player:WaitForChild("PlayerGui")

local function nameMatches(name)
	name = string.lower(name)
	for _, token in ipairs({
		"dinero", "diamond", "diamante", "money", "currency",
		"backpack", "mochila", "hotbar", "quick", "slot",
		"inventory", "inventario", "hud", "avatar", "ajustes",
		"config", "trade", "trato", "clock", "reloj",
	}) do
		if string.find(name, token, 1, true) then
			return true
		end
	end
	return false
end

local function localScaleInfo(obj)
	local scales = {}
	for _, child in ipairs(obj:GetChildren()) do
		if child:IsA("UIScale") then
			table.insert(scales, child.Name .. "=" .. string.format("%.3f", child.Scale))
		end
	end
	return table.concat(scales, ",")
end

local function screenName(obj)
	local current = obj
	while current and current ~= playerGui do
		if current:IsA("ScreenGui") then
			return current.Name
		end
		current = current.Parent
	end
	return "unknown"
end

local function describe(obj)
	local absolute = obj.AbsoluteSize
	local pos = obj.AbsolutePosition
	return string.format(
		"%s <%s> screen=%s parent=%s pos=%s size=%s anchor=(%.2f,%.2f) abs=(%d,%d %dx%d) visible=%s scales=[%s]",
		obj:GetFullName(),
		obj.ClassName,
		screenName(obj),
		obj.Parent and obj.Parent.Name or "nil",
		tostring(obj.Position),
		tostring(obj.Size),
		obj.AnchorPoint.X,
		obj.AnchorPoint.Y,
		math.floor(pos.X), math.floor(pos.Y),
		math.floor(absolute.X), math.floor(absolute.Y),
		tostring(obj.Visible),
		localScaleInfo(obj)
	)
end

local function snapshot()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.zero
	print(string.format("[GN-UI-AUDIT] START viewport=%dx%d deviceTouch=%s",
		math.floor(viewport.X), math.floor(viewport.Y),
		tostring(game:GetService("UserInputService").TouchEnabled)
	))

	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") then
			local ok, inset = pcall(function()
				return tostring(child.ScreenInsets)
			end)
			print(string.format(
				"[GN-UI-AUDIT] SCREEN %s enabled=%s inset=%s ignoreInset=%s",
				child.Name, tostring(child.Enabled),
				ok and inset or "unavailable", tostring(child.IgnoreGuiInset)
			))
		end
	end

	local guiCount = 0
	for _, obj in ipairs(playerGui:GetDescendants()) do
		if obj:IsA("GuiObject") then
			local relevant = nameMatches(obj.Name)
			if not relevant and (obj:IsA("TextLabel") or obj:IsA("TextButton")) then
				local value = tostring(obj.Text):gsub("%s+", "")
				local bottom = obj.AbsolutePosition.Y > viewport.Y * 0.6
				relevant = bottom and (value == "1" or value == "2" or value == "3")
			end

			if relevant then
				guiCount += 1
				if guiCount <= 65 then
					print("[GN-UI-AUDIT] GUI " .. describe(obj))
					if obj.Parent and obj.Parent:IsA("GuiObject") then
						print("[GN-UI-AUDIT]   PARENT " .. describe(obj.Parent))
					end
				end
			end
		end
	end
	print(string.format("[GN-UI-AUDIT] matchedGuiCount=%d (first 65 printed)", guiCount))

	local scriptCount = 0
	for _, root in ipairs({
		playerGui, player:FindFirstChild("PlayerScripts"), game:GetService("StarterGui"),
		game:GetService("StarterPlayer"),
	}) do
		if root then
			for _, obj in ipairs(root:GetDescendants()) do
				if obj:IsA("LocalScript") and nameMatches(obj.Name) then
					scriptCount += 1
					if scriptCount <= 50 then
						print("[GN-UI-AUDIT] SCRIPT " .. obj:GetFullName() ..
							" enabled=" .. tostring(obj.Enabled))
					end
				end
			end
		end
	end

	print(string.format("[GN-UI-AUDIT] matchedScriptCount=%d", scriptCount))
	print("[GN-UI-AUDIT] END")
end

task.wait(7)
snapshot()
