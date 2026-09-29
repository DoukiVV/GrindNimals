local UserInputService=game:GetService("UserInputService")
local ContextActionService=game:GetService("ContextActionService")
local Players=game:GetService("Players")
local LocalPlayer=Players.LocalPlayer
local humanoid=nil
local touchSprintEnabled=false
local NORMAL_SPEED=18
local RUN_SPEED=35
local function setRunning(e) if humanoid then humanoid.WalkSpeed=e and RUN_SPEED or NORMAL_SPEED end end
local function setupHumanoid() local ch=LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait() humanoid=ch:FindFirstChildOfClass("Humanoid") setRunning(false) end
LocalPlayer.CharacterAdded:Connect(function() touchSprintEnabled=false setupHumanoid() end)
setupHumanoid()
local function handleRunAction(_,state,input) if UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end local touch=input and input.UserInputType==Enum.UserInputType.Touch if touch then if state==Enum.UserInputState.Begin then touchSprintEnabled=not touchSprintEnabled setRunning(touchSprintEnabled) end return Enum.ContextActionResult.Sink end if state==Enum.UserInputState.Begin then setRunning(true) return Enum.ContextActionResult.Sink elseif state==Enum.UserInputState.End or state==Enum.UserInputState.Cancel then setRunning(false) return Enum.ContextActionResult.Sink end return Enum.ContextActionResult.Pass end
ContextActionService:BindActionAtPriority("RunDeviceAction",handleRunAction,true,4000,Enum.KeyCode.LeftShift,Enum.KeyCode.ButtonL3,Enum.KeyCode.ButtonR2)
pcall(function() ContextActionService:SetTitle("RunDeviceAction","Correr") ContextActionService:SetPosition("RunDeviceAction",UDim2.new(1,-86,1,-252)) end)
