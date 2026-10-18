-- Foresters AutoFarm (dev) — attach + chop + hop
-- target modes: Nearest / Rarest / Heaviest / Biggest / Any
-- flow: equip axe, noclip, hug trunk, StartChop, hold MinDuration, FinishChop, hop

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local plr = Players.LocalPlayer

for _, n in ipairs({"FarmUI", "ForestersFarmUI", "ForestersChopUI", "AutoFarm"}) do
	local g = plr.PlayerGui:FindFirstChild(n)
	if g then g:Destroy() end
end

----------------------------------------------------------------------
-- services
----------------------------------------------------------------------
local Knit = require(RS:WaitForChild("Packages"):WaitForChild("Knit"))
pcall(function() Knit.Start() end)
local TreeService = Knit.GetService("TreeService")

local WoodConfig = require(RS.Modules.Lumber.WoodConfig)
local tierCache = {}
local function tier_of(rarity)
	if tierCache[rarity] == nil then
		local ok, info = pcall(function() return WoodConfig.GetRarity(rarity) end)
		tierCache[rarity] = (ok and info and info.Tier) or 0
	end
	return tierCache[rarity]
end

local MARK = 1        -- quality arg: 1.0 gives the shortest server MinDuration
local BLOCK_TIME = 3  -- seconds a bad tree is skipped
local HUG_OFFSET = 5  -- studs from the trunk pivot; the proven-reachable distance
local MODES = {"Nearest", "Rarest", "Heaviest", "Biggest", "Any"}

-- shared state: re-running this script must kill any previous farm loop
local S = getgenv().__AutoFarmState
if not S then
	S = {running = false, token = 0}
	getgenv().__AutoFarmState = S
end
S.token += 1
local MY_TOKEN = S.token
S.running = false -- orphan any previous instance
task.wait(0.25)

local modeIndex = 1
local blocked = {}
local stats = {felled = 0, failed = 0, startedAt = 0}

local function is_owner()
	return S.token == MY_TOKEN
end

local function is_running()
	return S.running and is_owner()
end

----------------------------------------------------------------------
-- character helpers
----------------------------------------------------------------------
local function character()
	return plr.Character or plr.CharacterAdded:Wait()
end

local function root()
	local char = plr.Character
	return char and char:FindFirstChild("HumanoidRootPart") or nil
end

local function noclip(on)
	local char = plr.Character
	if not char then return end
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then d.CanCollide = not on end
	end
end

-- keep the axe in hand; the server rejects chops otherwise
local function equip_axe()
	local char = plr.Character
	if not char then return false end
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") and c.Name:match("Axe") then return true end
	end
	local backpack = plr:FindFirstChild("Backpack")
	if not backpack then return false end
	local axe
	for _, c in ipairs(backpack:GetChildren()) do
		if c:IsA("Tool") and c.Name:match("Axe") then axe = c break end
	end
	if not axe then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return false end
	pcall(function() hum:EquipTool(axe) end)
	task.wait(0.15)
	return char:FindFirstChild(axe.Name) ~= nil
end

-- hug the trunk: unanchored so the server keeps seeing our position
local function pin(tree)
	local hrp = root()
	if not hrp then return end
	hrp.CFrame = tree:GetPivot() * CFrame.new(0, 0, HUG_OFFSET)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

----------------------------------------------------------------------
-- selection
----------------------------------------------------------------------
local function is_live(tree)
	local st = tree:GetAttribute("State")
	if st == "Ready" then return true end
	if st == "Locked" and tree:GetAttribute("LockedBy") == plr.UserId then return true end
	return false
end

local function candidates()
	local folder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Trees")
	local out = {}
	if not folder then return out end
	local now = os.clock()
	for _, t in ipairs(folder:GetChildren()) do
		if is_live(t) and (blocked[t] == nil or blocked[t] < now) then
			table.insert(out, t)
		end
	end
	return out
end

local function pick(mode)
	local list = candidates()
	if #list == 0 then return nil end
	local hrp = root()
	local origin = hrp and hrp.Position or Vector3.zero

	local function dist(t)
		local d = (t:GetPivot().Position - origin) * Vector3.new(1, 0, 1)
		return d.Magnitude
	end

	if mode == "Nearest" then
		table.sort(list, function(a, b) return dist(a) < dist(b) end)
	elseif mode == "Rarest" then
		table.sort(list, function(a, b)
			local ta, tb = tier_of(a:GetAttribute("Rarity")), tier_of(b:GetAttribute("Rarity"))
			if ta ~= tb then return ta > tb end
			return (a:GetAttribute("Weight") or 0) > (b:GetAttribute("Weight") or 0)
		end)
	elseif mode == "Heaviest" then
		table.sort(list, function(a, b)
			local wa, wb = a:GetAttribute("Weight") or 0, b:GetAttribute("Weight") or 0
			if wa ~= wb then return wa > wb end
			return (a:GetAttribute("TreeId") or 0) < (b:GetAttribute("TreeId") or 0)
		end)
	elseif mode == "Biggest" then
		table.sort(list, function(a, b)
			local sa, sb = a:GetAttribute("Scale") or 0, b:GetAttribute("Scale") or 0
			if sa ~= sb then return sa > sb end
			return (a:GetAttribute("TreeId") or 0) < (b:GetAttribute("TreeId") or 0)
		end)
	end
	return list[1]
end

----------------------------------------------------------------------
-- promise bridge
----------------------------------------------------------------------
local function await(promise, timeout)
	local done, result = false, nil
	promise:andThen(function(v)
		result = v
		done = true
	end, function(e)
		result = {Ok = false, Reason = tostring(e)}
		done = true
	end)
	local t0 = os.clock()
	timeout = timeout or 8
	while not done and os.clock() - t0 < timeout do
		task.wait(0.03)
	end
	if not done then return {Ok = false, Reason = "timeout"} end
	return result
end

----------------------------------------------------------------------
-- one tree
----------------------------------------------------------------------
local function chop_tree(tree)
	equip_axe()
	pin(tree)
	task.wait(0.12)

	local session = await(TreeService:StartChop(tree, MARK))
	if type(session) ~= "table" or not session.Ok then
		return false, (type(session) == "table" and session.Reason) or "start failed"
	end

	local hold = ((session.Params and session.Params.MinDuration) or 3.5) + 0.08
	local t0 = os.clock()
	while os.clock() - t0 < hold do
		if not running then
			pcall(function() TreeService:CancelChop(tree) end)
			return false, "cancelled"
		end
		pin(tree) -- stay glued to the trunk while the session runs
		task.wait(0.05)
	end

	local finish = await(TreeService:FinishChop(tree, true, false))
	if type(finish) ~= "table" or not finish.Ok then
		pcall(function() TreeService:CancelChop(tree) end)
		return false, (type(finish) == "table" and finish.Reason) or "finish failed"
	end

	return true, finish.Felled and "felled" or "held"
end

----------------------------------------------------------------------
-- ui
----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "AutoFarm"
gui.ResetOnSpawn = false
gui.Parent = plr:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 246, 0, 152)
frame.Position = UDim2.new(0.02, 0, 0.3, 0)
frame.BackgroundColor3 = Color3.fromRGB(20, 22, 27)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local header = Instance.new("TextLabel")
header.Size = UDim2.new(1, 0, 0, 22)
header.BackgroundColor3 = Color3.fromRGB(34, 38, 47)
header.Text = "  AutoFarm"
header.TextColor3 = Color3.fromRGB(235, 235, 235)
header.Font = Enum.Font.GothamBold
header.TextSize = 13
header.TextXAlignment = Enum.TextXAlignment.Left
header.Parent = frame

local modeBtn = Instance.new("TextButton")
modeBtn.Size = UDim2.new(0, 112, 0, 22)
modeBtn.Position = UDim2.new(0, 10, 0, 30)
modeBtn.BackgroundColor3 = Color3.fromRGB(48, 54, 66)
modeBtn.TextColor3 = Color3.fromRGB(225, 225, 225)
modeBtn.Font = Enum.Font.GothamBold
modeBtn.TextSize = 12
modeBtn.Text = MODES[modeIndex]
modeBtn.Parent = frame

local runBtn = Instance.new("TextButton")
runBtn.Size = UDim2.new(0, 110, 0, 22)
runBtn.Position = UDim2.new(0, 126, 0, 30)
runBtn.BackgroundColor3 = Color3.fromRGB(52, 120, 74)
runBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
runBtn.Font = Enum.Font.GothamBold
runBtn.TextSize = 12
runBtn.Text = "START"
runBtn.Parent = frame

local info = Instance.new("TextLabel")
info.Size = UDim2.new(1, -20, 0, 92)
info.Position = UDim2.new(0, 10, 0, 56)
info.BackgroundTransparency = 1
info.TextColor3 = Color3.fromRGB(190, 195, 205)
info.Font = Enum.Font.Gotham
info.TextSize = 11
info.TextXAlignment = Enum.TextXAlignment.Left
info.TextYAlignment = Enum.TextYAlignment.Top
info.TextWrapped = true
info.Text = "idle"
info.Parent = frame

local current = "-"
local lastMsg = "idle"

local function rate()
	if stats.startedAt == 0 or stats.felled == 0 then return 0 end
	local mins = (os.clock() - stats.startedAt) / 60
	if mins <= 0 then return 0 end
	return stats.felled / mins
end

local function refresh()
	info.Text = ("state: %s   mode: %s\nfelled: %d   fail: %d   %.1f/min\nlast: %s\ntarget: %s")
		:format(running and "RUNNING" or "stopped", MODES[modeIndex],
			stats.felled, stats.failed, rate(), lastMsg, current)
end

local function set_running(on)
	running = on
	runBtn.Text = on and "STOP" or "START"
	runBtn.BackgroundColor3 = on and Color3.fromRGB(150, 60, 60) or Color3.fromRGB(52, 120, 74)
	if not on then
		noclip(false)
		lastMsg = "stopped"
		refresh()
		return
	end

	stats.startedAt = os.clock()
	stats.felled = 0
	stats.failed = 0
	noclip(true)
	task.spawn(function()
		while running do
			local ok, msg = pcall(function()
				local mode = MODES[modeIndex]
				local tree = pick(mode)
				if not tree then
					current = "-"
					return "no tree ready"
				end
				current = tostring(tree:GetAttribute("Species") or tree.Name)
				local good, result = chop_tree(tree)
				if not good then
					blocked[tree] = os.clock() + BLOCK_TIME
					stats.failed += 1
					return tostring(result)
				end
				stats.felled += 1
				return tostring(result)
			end)
			lastMsg = ok and tostring(msg) or ("err: " .. tostring(msg))
			refresh()
			task.wait(0.02)
		end
	end)
	refresh()
end

modeBtn.MouseButton1Click:Connect(function()
	modeIndex = modeIndex % #MODES + 1
	modeBtn.Text = MODES[modeIndex]
	refresh()
end)

runBtn.MouseButton1Click:Connect(function()
	set_running(not running)
end)

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.RightShift then
		set_running(not running)
	end
end)

plr.CharacterAdded:Connect(function()
	if running then
		task.wait(0.5)
		noclip(true)
		equip_axe()
	end
end)

-- handles for remote driving / debugging
getgenv().AutoFarm = {
	start = function(mode)
		if mode then
			for i, m in ipairs(MODES) do
				if m == mode then modeIndex = i end
			end
			modeBtn.Text = MODES[modeIndex]
		end
		set_running(true)
	end,
	stop = function() set_running(false) end,
	state = function()
		return {running = running, mode = MODES[modeIndex], felled = stats.felled,
			failed = stats.failed, last = lastMsg, target = current, rate = rate()}
	end,
	modes = MODES,
}

refresh()
print("[AutoFarm] loaded - RightShift toggles, mode button cycles target class")
