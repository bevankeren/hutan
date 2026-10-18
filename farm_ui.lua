-- Foresters farm UI (dev) — UI builds first, services resolved on demand
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local plr = Players.LocalPlayer

local old = plr.PlayerGui:FindFirstChild("FarmUI")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "FarmUI"
gui.ResetOnSpawn = false
gui.Parent = plr:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 250, 0, 320)
frame.Position = UDim2.new(0.02, 0, 0.28, 0)
frame.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
frame.BorderSizePixel = 0
frame.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 24)
title.BackgroundColor3 = Color3.fromRGB(38, 42, 52)
title.Text = "Foresters Farm (dev)"
title.TextColor3 = Color3.fromRGB(230, 230, 230)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 34)
status.Position = UDim2.new(0, 10, 0, 30)
status.BackgroundTransparency = 1
status.Text = "boot"
status.TextColor3 = Color3.fromRGB(170, 210, 170)
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextWrapped = true
status.Parent = frame

local function button(text, y, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -20, 0, 26)
	b.Position = UDim2.new(0, 10, 0, y)
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.Text = text
	b.Parent = frame
	return b
end

-- lazy service lookup
local TreeService
local function svc()
	if not TreeService then
		local Knit = require(RS:WaitForChild("Packages"):WaitForChild("Knit"))
		TreeService = Knit.GetService("TreeService")
	end
	return TreeService
end

local function remote(name)
	local r = RS:FindFirstChild(name, true)
	if not r then error("remote missing: " .. name) end
	return r
end

local function readyTrees()
	local out = {}
	local map = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Trees")
	if not folder then return out end
	for _, t in ipairs(folder:GetChildren()) do
		local st = t:GetAttribute("State")
		if st == "Ready" or (st == "Locked" and t:GetAttribute("LockedBy") == plr.UserId) then
			table.insert(out, t)
		end
	end
	return out
end

local function await(p)
	local done, res, err = false, nil, nil
	p:andThen(function(r) res = r; done = true end, function(e) err = e; done = true end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < 8 do task.wait() end
	if err then error(tostring(err)) end
	return res
end

local function chopOnce()
	local trees = readyTrees()
	local tree = trees[1]
	if not tree then return false, "no ready tree" end
	local char = plr.Character or plr.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart")
	hrp.CFrame = tree:GetPivot() * CFrame.new(0, 0, 5)
	hrp.AssemblyLinearVelocity = Vector3.zero
	task.wait(0.15)
	local s = await(svc():StartChop(tree, 0.9999))
	if type(s) ~= "table" or not s.Ok then
		return false, (type(s) == "table" and s.Reason) or "start fail"
	end
	-- server enforces a minimum session duration; hold it, then finish
	local hold = (s.Params and s.Params.MinDuration or 3.5) + 0.12
	local t0 = os.clock()
	while os.clock() - t0 < hold do task.wait(0.05) end
	local f = await(svc():FinishChop(tree, true, false))
	if type(f) ~= "table" or not f.Ok then
		pcall(function() svc():CancelChop(tree) end)
		return false, (type(f) == "table" and f.Reason) or "finish fail"
	end
	return true, f.Felled and "felled" or "held"
end

local auto = false

local countBox = Instance.new("TextBox")
countBox.Size = UDim2.new(1, -20, 0, 24)
countBox.Position = UDim2.new(0, 10, 0, 68)
countBox.BackgroundColor3 = Color3.fromRGB(38, 42, 52)
countBox.TextColor3 = Color3.fromRGB(230, 230, 230)
countBox.Font = Enum.Font.Gotham
countBox.TextSize = 13
countBox.Text = "5"
countBox.ClearTextOnFocus = false
countBox.Parent = frame

button("Chop xN", 98, Color3.fromRGB(60, 130, 80)).MouseButton1Click:Connect(function()
	if auto then return end
	local n = math.clamp(tonumber(countBox.Text) or 1, 1, 500)
	task.spawn(function()
		for i = 1, n do
			local ok, msg = chopOnce()
			status.Text = ("%d/%d %s"):format(i, n, tostring(msg))
			if not ok then break end
			task.wait(0.12)
		end
		status.Text = "chop done"
	end)
end)

button("Auto chop: OFF", 130, Color3.fromRGB(90, 130, 60)).MouseButton1Click:Connect(function(btn)
	auto = not auto
	btn.Text = auto and "Auto chop: ON" or "Auto chop: OFF"
	if auto then
		task.spawn(function()
			while auto do
				local ok, msg = chopOnce()
				status.Text = tostring(msg)
				if not ok then task.wait(0.4) end
				task.wait(0.12)
			end
		end)
	end
end)

button("Pickup logs", 162, Color3.fromRGB(130, 100, 60)).MouseButton1Click:Connect(function()
	task.spawn(function()
		local ok, res = pcall(function() return remote("PickUp"):InvokeServer("OakIsland") end)
		status.Text = "pickup " .. tostring(ok) .. " " .. tostring(res)
	end)
end)

button("Run saw cycle", 194, Color3.fromRGB(100, 80, 130)).MouseButton1Click:Connect(function()
	task.spawn(function()
		pcall(function() remote("StartSaw"):InvokeServer("OakIsland") end)
		task.wait(0.3)
		pcall(function() remote("Hold"):InvokeServer(2) end)
		task.wait(0.3)
		local ok, res = pcall(function() return remote("FinishSaw"):InvokeServer(0.995) end)
		status.Text = "saw " .. tostring(ok) .. " " .. tostring(res)
	end)
end)

button("Quote + Sell all", 226, Color3.fromRGB(80, 120, 140)).MouseButton1Click:Connect(function()
	task.spawn(function()
		local okQ, rQ = pcall(function() return remote("Quote"):InvokeServer("All") end)
		task.wait(0.2)
		local okS, rS = pcall(function() return remote("SellTrees"):InvokeServer("All") end)
		status.Text = "sell " .. tostring(okS) .. " " .. tostring(rS or rQ)
	end)
end)

button("Refresh tree count", 258, Color3.fromRGB(70, 80, 100)).MouseButton1Click:Connect(function()
	status.Text = "ready trees: " .. #readyTrees()
end)

status.Text = "ready - trees: " .. #readyTrees()
print("[FarmUI] loaded")
