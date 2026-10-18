-- Foresters: Instant Chop + Farm UI (dev)
-- TreeService via Knit, other remotes invoked directly by name.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local plr = Players.LocalPlayer

local old = plr:FindFirstChild("PlayerGui") and plr.PlayerGui:FindFirstChild("ForestersFarmUI")
if old then old:Destroy() end

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))
pcall(function() Knit.Start() end)
local okSvc, TreeService = pcall(function() return Knit.GetService("TreeService") end)
if not okSvc then
	error("[Farm] TreeService unavailable: " .. tostring(TreeService))
end

local function R(name)
	local r = ReplicatedStorage:FindFirstChild(name, true)
	if not r then error("[Farm] remote not found: " .. tostring(name)) end
	return r
end

local StartSaw = R("StartSaw")
local Hold = R("Hold")
local FinishSaw = R("FinishSaw")
local PickUp = R("PickUp")
local Quote = R("Quote")
local SellTrees = R("SellTrees")

local function readyTrees()
	local out = {}
	local folder = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("Trees")
	if not folder then return out end
	for _, t in ipairs(folder:GetChildren()) do
		local st = t:GetAttribute("State")
		local live = st == "Ready" or (st == "Locked" and t:GetAttribute("LockedBy") == plr.UserId)
		if live then table.insert(out, t) end
	end
	return out
end

local function nearestReadyTree()
	local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local best, bestDist = nil, math.huge
	for _, t in ipairs(readyTrees()) do
		local d = (t:GetPivot().Position - hrp.Position) * Vector3.new(1, 0, 1)
		d = d.Magnitude
		if d < bestDist then best, bestDist = t, d end
	end
	return best
end

local function awaitPromise(promise)
	local done = false
	local result = nil
	local err = nil
	promise:andThen(function(r)
		result = r
		done = true
	end, function(e)
		err = e
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < 10 do
		task.wait()
	end
	if err then error(err) end
	return result
end

local function startChop(tree, mark)
	return awaitPromise(TreeService:StartChop(tree, mark or 0.9999))
end

local function finishChop(tree)
	return awaitPromise(TreeService:FinishChop(tree, true, false))
end

local function teleportNear(tree)
	local char = plr.Character or plr.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart")
	hrp.CFrame = tree:GetPivot() * CFrame.new(0, 0, 5)
	hrp.AssemblyLinearVelocity = Vector3.zero
end

local function chopOnce(mark)
	local tree = readyTrees()[1] -- arbitrary ready tree; will teleport near it
	if not tree then
		return false, "no ready tree"
	end
	teleportNear(tree)
	task.wait(0.2)
	local s = startChop(tree, mark or 0.9999)
	if type(s) ~= "table" or not s.Ok then
		return false, (type(s) == "table" and s.Reason) or "StartChop failed"
	end
	task.wait(0.05)
	local f = finishChop(tree)
	if type(f) ~= "table" or not f.Ok then
		return false, (type(f) == "table" and f.Reason) or "FinishChop failed"
	end
	return true, (f.Felled and "felled" or "held")
end

local function invokeRemote(remote, ...)
	local ok, res = pcall(function() return remote:InvokeServer(...) end)
	return ok, res
end

-- UI
print("[Farm] create gui")
local gui = Instance.new("ScreenGui")
gui.Name = "ForestersFarmUI"
gui.ResetOnSpawn = false
gui.Parent = plr:WaitForChild("PlayerGui")
print("[Farm] gui parent done")

print("[Farm] create frame")
local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 260, 0, 330)
frame.Position = UDim2.new(0.02, 0, 0.25, 0)
frame.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
frame.BorderSizePixel = 0
frame.Parent = gui
print("[Farm] frame parent done, count", #gui:GetChildren())

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 24)
title.BackgroundColor3 = Color3.fromRGB(38, 42, 52)
title.Text = "Foresters Farm (dev)"
title.TextColor3 = Color3.fromRGB(230, 230, 230)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.Parent = frame

local function label(txt, y)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -20, 0, 16)
	l.Position = UDim2.new(0, 10, 0, y)
	l.BackgroundTransparency = 1
	l.Text = txt
	l.TextColor3 = Color3.fromRGB(200, 200, 200)
	l.Font = Enum.Font.Gotham
	l.TextSize = 12
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = frame
	return l
end

label("Ready trees in map:", 30)
local countLbl = Instance.new("TextLabel")
countLbl.Size = UDim2.new(1, -20, 0, 16)
countLbl.Position = UDim2.new(0, 10, 0, 48)
countLbl.BackgroundTransparency = 1
countLbl.Text = tostring(#readyTrees())
countLbl.TextColor3 = Color3.fromRGB(170, 210, 170)
countLbl.Font = Enum.Font.Gotham
countLbl.TextSize = 12
countLbl.TextXAlignment = Enum.TextXAlignment.Left
countLbl.Parent = frame

label("Tree chop count:", 74)
local countBox = Instance.new("TextBox")
countBox.Size = UDim2.new(1, -20, 0, 24)
countBox.Position = UDim2.new(0, 10, 0, 92)
countBox.BackgroundColor3 = Color3.fromRGB(38, 42, 52)
countBox.TextColor3 = Color3.fromRGB(230, 230, 230)
countBox.Font = Enum.Font.Gotham
countBox.TextSize = 13
countBox.Text = "5"
countBox.ClearTextOnFocus = false
countBox.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 28)
status.Position = UDim2.new(0, 10, 0, 122)
status.BackgroundTransparency = 1
status.Text = "ready"
status.TextColor3 = Color3.fromRGB(170, 210, 170)
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextWrapped = true
status.Parent = frame

local function makeBtn(txt, y, color, cb)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -20, 0, 24)
	btn.Position = UDim2.new(0, 10, 0, y)
	btn.BackgroundColor3 = color
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 12
	btn.Text = txt
	btn.Parent = frame
	btn.MouseButton1Click:Connect(cb)
	return btn
end

makeBtn("Refresh tree count", 160, Color3.fromRGB(70, 80, 100), function()
	countLbl.Text = tostring(#readyTrees())
end)

makeBtn("Chop xN (left click)", 188, Color3.fromRGB(60, 130, 80), function()
	if _G.__farmAuto then return end
	local n = tonumber(countBox.Text) or 1
	if n < 1 then n = 1 end
	if n > 500 then n = 500 end
	task.spawn(function()
		for i = 1, n do
			countLbl.Text = tostring(#readyTrees())
			status.Text = ("chopping %d/%d ..."):format(i, n)
			local ok, msg = chopOnce(0.9999)
			print("[Farm] chop", ok, msg)
			status.Text = msg or "done"
			if not ok then break end
			task.wait(0.12)
		end
		status.Text = "chop done"
	end)
end)

makeBtn("Auto chop toggle (right click)", 216, Color3.fromRGB(90, 130, 60), function()
	_G.__farmAuto = not (_G.__farmAuto or false)
	status.Text = _G.__farmAuto and "auto-chop: ON" or "auto-chop: OFF"
	if _G.__farmAuto then
		task.spawn(function()
			while _G.__farmAuto do
				local ok, msg = chopOnce(0.9999)
				print("[Farm] auto-chop", ok, msg)
				status.Text = msg or "ok"
				task.wait(0.12)
			end
		end)
	end
end)

makeBtn("Pickup logs", 244, Color3.fromRGB(130, 100, 60), function()
	task.spawn(function()
		status.Text = "pickup..."
		local ok, res = invokeRemote(PickUp, "OakIsland")
		print("[Farm] PickUp", ok, res)
		status.Text = ok and "picked" or tostring(res)
	end)
end)

makeBtn("Run saw cycle", 272, Color3.fromRGB(100, 80, 130), function()
	task.spawn(function()
		status.Text = "start saw..."
		local ok1, r1 = invokeRemote(StartSaw, "OakIsland")
		print("[Farm] StartSaw", ok1, r1)
		task.wait(0.3)
		local ok2, r2 = invokeRemote(Hold, 2)
		print("[Farm] Hold", ok2, r2)
		task.wait(0.3)
		local ok3, r3 = invokeRemote(FinishSaw, 0.995)
		print("[Farm] FinishSaw", ok3, r3)
		status.Text = ok3 and "saw ok" or tostring(r3)
	end)
end)

makeBtn("Quote + Sell all", 300, Color3.fromRGB(80, 120, 140), function()
	task.spawn(function()
		status.Text = "quote..."
		local okQ, resQ = invokeRemote(Quote, "All")
		print("[Farm] Quote", okQ, resQ)
		task.wait(0.2)
		status.Text = "sell..."
		local okS, resS = invokeRemote(SellTrees, "All")
		print("[Farm] SellTrees", okS, resS)
		status.Text = okS and "sold" or tostring(resS)
	end)
end)

print("[Farm] UI loaded final")

