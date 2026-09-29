-- GrindNimals: remove the optional manual guide and its "?" button.
-- This intentionally does NOT disable the main tutorial objectives, arrows,
-- highlights, progression, or tutorial remotes.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TUTORIAL_GUI_NAME = "GrindNimalsTutorialGui"

local function belongsToTutorialGui(instance)
	local current = instance
	while current and current ~= playerGui do
		if current.Name == TUTORIAL_GUI_NAME and current:IsA("ScreenGui") then
			return true
		end
		current = current.Parent
	end
	return false
end

local function removeGuideObject(instance)
	if not instance then
		return
	end

	if (instance.Name == "HelpButton" or instance.Name == "HelpPanel")
		and belongsToTutorialGui(instance) then
		instance:Destroy()
	end
end

local function cleanExisting()
	local tutorialGui = playerGui:FindFirstChild(TUTORIAL_GUI_NAME)
	if not tutorialGui then
		return
	end

	local helpButton = tutorialGui:FindFirstChild("HelpButton", true)
	if helpButton then
		helpButton:Destroy()
	end

	local helpPanel = tutorialGui:FindFirstChild("HelpPanel", true)
	if helpPanel then
		helpPanel:Destroy()
	end
end

cleanExisting()

-- TutorialClient can recreate these objects after loading/state changes.
-- Remove them every time they appear, while leaving the rest of the tutorial alone.
playerGui.DescendantAdded:Connect(function(instance)
	if instance.Name ~= "HelpButton" and instance.Name ~= "HelpPanel" then
		return
	end

	task.defer(function()
		if instance.Parent then
			removeGuideObject(instance)
		end
	end)
end)

playerGui.ChildAdded:Connect(function(child)
	if child.Name == TUTORIAL_GUI_NAME then
		task.defer(cleanExisting)
	end
end)
