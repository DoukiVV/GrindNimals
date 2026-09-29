local tool = script.Parent

tool.Equipped:Connect(function()
	task.wait()
	tool.Parent = tool.Parent.Parent:FindFirstChild("Backpack")
end)