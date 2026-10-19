local Airflow = loadstring(game:HttpGet("https://raw.githubusercontent.com/joustingmatch/-3/refs/heads/main/Source.luau"))()
getgenv().__Airflow = Airflow

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local plr = Players.LocalPlayer

local Knit = require(RS:WaitForChild("Packages"):WaitForChild("Knit"))
pcall(function() Knit.Start() end)
local TreeService = Knit.GetService("TreeService")
local AxeService = Knit.GetService("AxeService")
local LumberMillService = Knit.GetService("LumberMillService")
local SawmillService = Knit.GetService("SawmillService")
local CarryService = Knit.GetService("CarryService")
local QuestService = Knit.GetService("QuestService")
local QuestSpotService = Knit.GetService("QuestSpotService")

local AxeConfig = require(RS.Modules.Lumber.AxeConfig)
local AxePrice = require(RS.Modules.Lumber.AxePrice)
local ChopTuning = require(RS.Modules.Lumber.ChopTuning)

if not getgenv().__BlizzardCrashGuardHook and hookmetamethod then
	local PROTECTED_PARTS = {
		Head = function(m) return m:FindFirstChild("Head") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart") end,
		HumanoidRootPart = function(m) return m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart") end,
		Torso = function(m) return m:FindFirstChild("Torso") or m:FindFirstChild("UpperTorso") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart") end,
		UpperTorso = function(m) return m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart") end,
		Humanoid = function(m) return m:FindFirstChildOfClass("Humanoid") end,
	}
	local oldIndex
	local ok, hook = pcall(function()
		return hookmetamethod(game, "__index", newcclosure(function(self, key)
			local resolver = PROTECTED_PARTS[key]
			if resolver and typeof(self) == "Instance" and self:IsA("Model") then
				local part = resolver(self)
				if part ~= nil then
					return part
				end
				return nil
			end
			return oldIndex(self, key)
		end))
	end)
	if ok and hook then
		oldIndex = hook
		getgenv().__BlizzardCrashGuardHook = oldIndex
	end
end

local PERF_KEY = "__BlizzardPerfHook"

local function perfect_hook_install()
	if getgenv()[PERF_KEY] then return true end
	local old = TreeService.FinishChop
	local state = {old = old, count = 0}
	TreeService.FinishChop = function(self, tree, done, perfect, ...)
		if done and not perfect then
			perfect = true
			state.count += 1
		end
		return old(self, tree, done, perfect, ...)
	end
	getgenv()[PERF_KEY] = state
	return true
end

local function perfect_hook_remove()
	local state = getgenv()[PERF_KEY]
	if not state then return false end
	if TreeService.FinishChop == state.old or type(state.old) == "function" then
		pcall(function() TreeService.FinishChop = state.old end)
	end
	getgenv()[PERF_KEY] = nil
	return true
end

local function perfect_hook_active()
	return getgenv()[PERF_KEY] ~= nil
end

do
	local prev = getgenv().__ForestFarmState
	if prev then
		prev.token = (prev.token or 0) + 1
		prev.farm = false
		prev.autobuy = false
		prev.perfectOn = false
		prev.levelingOn = false
		local ok, old = pcall(function() return getgenv().ForestFarm end)
		if ok and type(old) == "table" and type(old.stop) == "function" then
			pcall(old.stop)
		end
	end
	pcall(function()
		if getgenv().__OldWindupPower and ChopTuning then
			ChopTuning.WindupPower = getgenv().__OldWindupPower
			getgenv().__OldWindupPower = nil
		end
		local state = getgenv().__BlizzardPerfHook
		if state and type(state.old) == "function" then
			TreeService.FinishChop = state.old
		end
		getgenv().__BlizzardPerfHook = nil
		if getgenv().__BlizzardHideOverheadConn then
			pcall(function() getgenv().__BlizzardHideOverheadConn:Disconnect() end)
			getgenv().__BlizzardHideOverheadConn = nil
		end
		if getgenv().__BlizzardHideOverheadPropConn then
			pcall(function() getgenv().__BlizzardHideOverheadPropConn:Disconnect() end)
			getgenv().__BlizzardHideOverheadPropConn = nil
		end
		if getgenv().__BlizzardHideLeaderboardConn then
			pcall(function() getgenv().__BlizzardHideLeaderboardConn:Disconnect() end)
			getgenv().__BlizzardHideLeaderboardConn = nil
		end
		local pgui = plr:FindFirstChild("PlayerGui")
		local rw = pgui and pgui:FindFirstChild("ReactWorld")
		local tag = rw and rw:FindFirstChild("Overhead" .. tostring(plr.UserId))
		if tag and tag:IsA("BillboardGui") then
			pcall(function()
				tag.Enabled = true
				local card = tag:FindFirstChild("Content") and tag.Content:FindFirstChild("Card")
				local content = card and card:FindFirstChild("Content")
				local nameLabel = content and content:FindFirstChild("Name")
				if nameLabel and nameLabel:IsA("TextLabel") then
					local g = nameLabel:FindFirstChild("BlizzardGlimmer")
					if g then g:Destroy() end
					nameLabel.TextColor3 = Color3.fromRGB(232, 232, 232)
					nameLabel.Text = plr.DisplayName
				end
			end)
		end
		local cg = game:GetService("CoreGui")
		local pl = cg:FindFirstChild("PlayerList")
		local entry = pl and pl:FindFirstChild("PlayerEntry_" .. tostring(plr.UserId), true)
		local pNameFrame = entry and entry:FindFirstChild("PlayerName", true)
		local leadLabel = pNameFrame and pNameFrame:FindFirstChildOfClass("TextLabel")
		if leadLabel then
			pcall(function()
				local g = leadLabel:FindFirstChild("BlizzardGlimmer")
				if g then g:Destroy() end
				leadLabel.TextColor3 = Color3.fromRGB(247, 247, 248)
				leadLabel.Text = plr.DisplayName
			end)
		end
	end)
	if prev and prev.window and typeof(prev.window) ~= "nil" then
		pcall(function() prev.window:Destroy() end)
	end
	local espFolderOld = workspace:FindFirstChild("BlizzardESP")
	if espFolderOld then pcall(function() espFolderOld:Destroy() end) end
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Highlight") and d.Name == "BlzPlayerHL" then pcall(function() d:Destroy() end) end
	end
	local gui = plr:FindFirstChild("PlayerGui")
	if gui then
		for _, g in ipairs(gui:GetChildren()) do
			if g:IsA("ScreenGui") and g.Name:match("Airflow") then
				pcall(function() g:Destroy() end)
			end
		end
	end
	local char = plr.Character
	if char then
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			pcall(function()
				root.Anchored = false
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end)
		end
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") then pcall(function() d.CanCollide = true end) end
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then pcall(function() hum.AutoRotate = true end) end
	end
	task.wait(0.25)
end

local S = getgenv().__ForestFarmState
if not S then
	S = {token = 0, farm = false, autobuy = false, panicOn = false, panicRadius = 50, perfectOn = false}
	getgenv().__ForestFarmState = S
end
S.panicOn = S.panicOn or false
S.panicRadius = S.panicRadius or 50
S.perfectOn = S.perfectOn or false
S.autoSell = S.autoSell or false
S.sellAt = S.sellAt or 50
S.logCount = S.logCount or 0
if S.hideIngameName == nil then S.hideIngameName = true end
S.esp = S.esp or {}
if type(S.minTier) ~= "number" then S.minTier = 0 end
S.refreshRate = tonumber(S.refreshRate) or 10
S.topSort = type(S.topSort) == "string" and S.topSort or "Money"
S.minValue = tonumber(S.minValue) or 0
S.maxRows = tonumber(S.maxRows) or 8
S.weightValue = type(S.weightValue) == "number" and S.weightValue or 0.6
S.includeGrowing = S.includeGrowing == true
S.sameIslandOnly = S.sameIslandOnly == true
S.moveMode = (S.moveMode == "bike") and "bike" or "respawn"
S.respawnDelay = 0.15
do
	local e = S.esp
	e.players = e.players or false
	e.trees = e.trees or false
	e.merchants = e.merchants or false
	e.maxDist = e.maxDist or 800
	e.maxTags = e.maxTags or 22
	e.textSize = e.textSize or 13
	e.showRarity = e.showRarity ~= false
	e.showMutations = e.showMutations ~= false
	e.showDist = e.showDist ~= false
	e.hideUnfellable = e.hideUnfellable or false
	e.valueColor = e.valueColor or "Bands"
end
S.token += 1
local MY_TOKEN = S.token
S.farm = false
S.autobuy = false
task.wait(0.2)

local function alive()
	return S.token == MY_TOKEN
end

local savedCollide = setmetatable({}, {__mode = "k"})
local noclipOn = false

local function set_prop(part, prop, value, ok)
	pcall(function() part[prop] = value end)
end

local function noclip_pass()
	local char = plr.Character
	if not char then return end
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide then
			if savedCollide[d] == nil then savedCollide[d] = true end
			d.CanCollide = false
		end
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		for _, st in ipairs({
			Enum.HumanoidStateType.Landed,
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.Ragdoll,
			Enum.HumanoidStateType.PlatformStanding,
		}) do
			pcall(function() hum:SetStateEnabled(st, false) end)
		end
	end
end

local function restore_collide()
	local char = plr.Character
	if not char then return end
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = true
			savedCollide[d] = nil
		end
	end
	for d in pairs(savedCollide) do
		if d.Parent then d.CanCollide = true end
		savedCollide[d] = nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		for _, st in ipairs({
			Enum.HumanoidStateType.Landed,
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.Ragdoll,
			Enum.HumanoidStateType.PlatformStanding,
		}) do
			pcall(function() hum:SetStateEnabled(st, true) end)
		end
	end
end

local function hrp()
	local char = plr.Character
	return char and char:FindFirstChild("HumanoidRootPart") or nil
end

local SNAP_STEP = 15
local SNAP_PAUSE = 0.05
local STAND_HEIGHT = 0.5

local WALK = {
	legTimeout = 8,
	active = false,
	stripped = nil,
	label = nil,
}
getgenv().__ForestFarmWalk = WALK

function WALK.noclip(state)
	local char = plr.Character
	if not char then return end
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") then pcall(function() p.CanCollide = state end) end
	end
	if state then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			for _, st in ipairs({
				Enum.HumanoidStateType.Landed,
				Enum.HumanoidStateType.FallingDown,
				Enum.HumanoidStateType.Ragdoll,
				Enum.HumanoidStateType.PlatformStanding,
			}) do
				pcall(function() hum:SetStateEnabled(st, true) end)
			end
			pcall(function() hum.AutoRotate = true end)
		end
	end
end

function WALK.strip()
	if WALK.stripped then return end
	WALK.stripped = {}
	local map = workspace:FindFirstChild("Map")
	if not map then WALK.stripped = nil return end
	for _, d in ipairs(map:GetDescendants()) do
		if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail")
			or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then
			if d.Enabled then
				WALK.stripped[#WALK.stripped + 1] = d
				pcall(function() d.Enabled = false end)
			end
		end
	end
end

function WALK.unstrip()
	if not WALK.stripped then return end
	for _, d in ipairs(WALK.stripped) do
		if d.Parent then pcall(function() d.Enabled = true end) end
	end
	WALK.stripped = nil
end

function WALK.stand()
	local char = plr.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (root and hum) then return end
	if root.CFrame.UpVector.Y > 0.85 then return end

	local p = root.Position
	root.CFrame = CFrame.new(p.X, p.Y + 2.5, p.Z)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
	task.wait(0.5)
end

function WALK.respawnJump(dest)
	local char = plr.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (root and hum) then return false, "no character" end

	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {char, workspace.Map:FindFirstChild("Trees")}
	rp.IgnoreWater = true
	local g = workspace:Raycast(Vector3.new(dest.X, dest.Y + 200, dest.Z), Vector3.new(0, -400, 0), rp)
	local landY = (g and g.Position.Y + 3.0) or math.max(dest.Y + 3.0, 5)
	local landPos = Vector3.new(dest.X, landY, dest.Z)

	local got = nil
	local conn
	local done = false
	conn = plr.CharacterAdded:Connect(function(ch)
		if done then return end
		done = true
		got = ch
	end)

	pcall(function() hum.Health = 0 end)

	local deadline = os.clock() + 12
	while not got and os.clock() < deadline do task.wait(0.05) end
	if conn then pcall(function() conn:Disconnect() end) end
	if not got then return false, "respawn timeout" end

	local newRoot
	local w = 0
	while not newRoot and w < 6 do
		task.wait(0.02)
		w += 0.02
		newRoot = got:FindFirstChild("HumanoidRootPart")
	end
	if not newRoot then return false, "no root after respawn" end

	local delay = tonumber(S.respawnDelay) or 0.15
	if delay > 0 then task.wait(delay) end

	newRoot.CFrame = CFrame.new(landPos)
	newRoot.AssemblyLinearVelocity = Vector3.zero
	newRoot.AssemblyAngularVelocity = Vector3.zero

	for _, p in ipairs(got:GetDescendants()) do
		if p:IsA("BasePart") then pcall(function() p.CanCollide = true end) end
	end
	local newHum = got:FindFirstChildOfClass("Humanoid")
	if newHum then
		for _, st in ipairs({
			Enum.HumanoidStateType.Landed,
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.Ragdoll,
			Enum.HumanoidStateType.PlatformStanding,
		}) do
			pcall(function() newHum:SetStateEnabled(st, true) end)
		end
		pcall(function() newHum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
	end

	task.wait(0.25)
	local held = (newRoot.Position - landPos).Magnitude <= 40

	if newHum then
		local hasAxe = false
		for _, c in ipairs(got:GetChildren()) do
			if c:IsA("Tool") and c.Name:match("Axe") then hasAxe = true break end
		end
		if not hasAxe then
			local bp = plr:FindFirstChild("Backpack")
			if bp then
				for _, c in ipairs(bp:GetChildren()) do
					if c:IsA("Tool") and c.Name:match("Axe") then
						local id = c:GetAttribute("AxeId")
						if id then pcall(function() call(AxeService, "EquipAxe", id) end) end
						for _ = 1, 16 do
							for _, h in ipairs(got:GetChildren()) do
								if h:IsA("Tool") and h.Name:match("Axe") then hasAxe = true break end
							end
							if hasAxe then break end
							task.wait(0.05)
						end
						if not hasAxe then pcall(function() newHum:EquipTool(c) end) end
						break
					end
				end
			end
		end
	end

	return held, held and "landed" or "drifted"
end

function WALK.bikeJump(dest)
	local char = plr.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (root and hum) then return false, "no character" end

	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {char, workspace.Map:FindFirstChild("Trees")}
	rp.IgnoreWater = true
	local g = workspace:Raycast(Vector3.new(dest.X, dest.Y + 200, dest.Z), Vector3.new(0, -400, 0), rp)
	local landY = (g and g.Position.Y + 3.0) or math.max(dest.Y + 3.0, 5)
	local landPos = Vector3.new(dest.X, landY, dest.Z)
	local landCF = CFrame.new(landPos)

	local okBgs, bgs = pcall(function() return Knit.GetService("BikeGarageService") end)
	local okBs, bs = pcall(function() return Knit.GetService("BikeService") end)

	if hum.Sit then
		hum.Sit = false
		pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
		task.wait(0.2)
	end

	local bikeTool = nil
	if char then
		for _, c in ipairs(char:GetChildren()) do
			if c:IsA("Tool") and (c:GetAttribute("BikeId") or c.Name:lower():match("bike")) then
				bikeTool = c
				break
			end
		end
	end
	if not bikeTool then
		local bp = plr:FindFirstChild("Backpack")
		if bp then
			for _, c in ipairs(bp:GetChildren()) do
				if c:IsA("Tool") and (c:GetAttribute("BikeId") or c.Name:lower():match("bike")) then
					bikeTool = c
					break
				end
			end
		end
	end

	local bikeId = bikeTool and (bikeTool:GetAttribute("BikeId") or bikeTool.Name) or "MountainBike"
	if okBgs and bgs and bgs.Summon then
		pcall(function() bgs:Summon(bikeId) end)
	elseif bikeTool and hum then
		pcall(function() hum:EquipTool(bikeTool) end)
	end

	local bikes = workspace:FindFirstChild("Bikes")
	local myBike = nil
	local t0 = os.clock()
	while os.clock() - t0 < 2.5 do
		if bikes then
			for _, b in ipairs(bikes:GetChildren()) do
				if b:GetAttribute("Owner") == plr.UserId then
					myBike = b
					break
				end
			end
		end
		if myBike then break end
		task.wait(0.05)
	end
	if not myBike then return false, "bike spawn timeout" end

	local token = myBike:GetAttribute("Token")
	local chassis = myBike:FindFirstChild("Chassis") or myBike.PrimaryPart
	local seat = myBike:FindFirstChild("Seat")

	task.spawn(function()
		if okBs and bs and bs.Ride and token then
			pcall(function() bs:Ride(token) end)
		elseif seat and (seat:IsA("Seat") or seat:IsA("VehicleSeat")) then
			pcall(function() seat:Sit(hum) end)
		end
	end)

	task.wait(0.04)
	for _ = 1, 4 do
		if chassis then
			chassis.CFrame = landCF
			chassis.AssemblyLinearVelocity = Vector3.zero
		end
		if root then
			root.CFrame = landCF
			root.AssemblyLinearVelocity = Vector3.zero
		end
		task.wait(0.03)
	end

	task.wait(0.12)
	if hum.Sit then
		hum.Sit = false
		pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
	end
	if okBs and bs and bs.PutAway then
		pcall(function() bs:PutAway() end)
	end

	if root then
		root.CFrame = landCF
		root.AssemblyLinearVelocity = Vector3.zero
	end
	task.wait(0.1)

	local held = root and (root.Position - landPos).Magnitude <= 40
	return held, held and "landed" or "drifted"
end

function WALK.leg(target, speed)
	local char = plr.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (root and hum) then return false end

	WALK.stand()
	WALK.noclip(true)
	pcall(function() hum.WalkSpeed = speed end)
	pcall(function() hum:MoveTo(target) end)

	local deadline = os.clock() + WALK.legTimeout
	local lastPos = root.Position
	local stall = 0
	local unsticking = false

	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {char}

	while os.clock() < deadline do
		if not alive() then return false end
		task.wait(0.1)

		local now = root.Position
		local moved = (now - lastPos).Magnitude
		lastPos = now

		if (now - target).Magnitude <= 9 then return true end

		if moved < 0.5 then
			stall += 1
			if stall >= 8 and not unsticking then
				unsticking = true
				WALK.noclip(false)
				task.wait(0.35)
				WALK.noclip(true)
				pcall(function() hum:MoveTo(target) end)
				stall = 0
				unsticking = false
			elseif stall >= 22 then
				return false
			end
		else
			stall = 0
		end
	end
	return (root.Position - target).Magnitude <= 12
end

function WALK.go(dest)
	local char = plr.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (root and hum) then return false, "no character" end
	if WALK.active then return false, "already walking" end

	WALK.active = true
	local speed = math.clamp(tonumber(S.walkSpeed) or 32, 16, 120)
	local strip = S.walkStripMap ~= false

	WALK.stand()
	if strip then WALK.strip() end

	local ok, reached = pcall(function()
		local pf = game:GetService("PathfindingService")
		local dist = (dest - root.Position).Magnitude

		if dist <= 40 then
			for _ = 1, 2 do
				if WALK.leg(dest, speed) then return true end
			end
			return (root.Position - dest).Magnitude <= 8
		end

		local path = pf:CreatePath({
			AgentRadius = 2.5,
			AgentHeight = 5,
			AgentCanJump = true,
			AgentJumpHeight = 7,
			AgentMaxSlope = 60,
			WaypointSpacing = 8,
		})

		local computed = false
		for _ = 1, 3 do
			local okC = pcall(function()
				path:ComputeAsync(root.Position, dest)
			end)
			if okC and path.Status == Enum.PathStatus.Success then
				computed = true
				break
			end
			task.wait(0.3)
		end

		if not computed then
			for _ = 1, 2 do
				if WALK.leg(dest, speed) then return true end
			end
			return (root.Position - dest).Magnitude <= 10
		end

		local waypoints = path:GetWaypoints()
		local i = 2
		local recomputes = 0
		while i <= #waypoints do
			if not alive() then return false end
			local wp = waypoints[i]
			if wp.Action == Enum.PathWaypointAction.Jump then
				pcall(function() hum.Jump = true end)
			end
			if WALK.leg(wp.Position, speed) then
				i += 1
			else
				recomputes += 1
				if recomputes > 4 then
					return (root.Position - dest).Magnitude <= 30
				end
				local okR = pcall(function()
					path:ComputeAsync(root.Position, dest)
				end)
				if okR and path.Status == Enum.PathStatus.Success then
					waypoints = path:GetWaypoints()
					i = 2
					task.wait(0.15)
				else
					for _ = 1, 3 do
						if WALK.leg(dest, speed) then return true end
					end
					return (root.Position - dest).Magnitude <= 30
				end
			end
		end
		for _ = 1, 3 do
			if (root.Position - dest).Magnitude <= 12 then return true end
			WALK.leg(dest, speed)
		end
		return (root.Position - dest).Magnitude <= 20
	end)

	WALK.noclip(true)
	if strip then
		task.wait(0.1)
		WALK.unstrip()
	end
	pcall(function() hum:MoveTo(root.Position) end)
	pcall(function() hum.WalkSpeed = 16 end)
	WALK.active = false

	if not ok then return false, tostring(reached) end
	return reached == true
end

local MOVE_SPEED = 60
local CHUNK_STUDS = 120
local STREAM_WAIT = 0.25

local function wait_for_stream(pos)
	local ok = pcall(function() workspace:RequestStreamAroundAsync(pos) end)
	task.wait(ok and STREAM_WAIT or 0.1)
end

local function teleport_to(pos, offset, finalFacing)
	local root = hrp()
	if not root or not pos then return false end
	local dest = pos + (offset or Vector3.new(0, 1, 4))
	local from = root.Position
	local delta = dest - from
	local dist = delta.Magnitude

	if dist <= 8 then
		root.CFrame = finalFacing or CFrame.new(dest)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		task.wait(0.1)
		return true
	end

	if S.moveMode == "bike" then
		local okB, whyB = WALK.bikeJump(dest)
		if okB then
			if finalFacing then
				local r2 = hrp()
				if r2 then r2.CFrame = CFrame.new(r2.Position) * (finalFacing - finalFacing.Position) end
			end
			return true
		end
		local okR, whyR = WALK.respawnJump(dest)
		if okR then
			if finalFacing then
				local r2 = hrp()
				if r2 then r2.CFrame = CFrame.new(r2.Position) * (finalFacing - finalFacing.Position) end
			end
			return true
		end
		return false, "bike/respawn failed: " .. tostring(whyB)
	else
		local okR, whyR = WALK.respawnJump(dest)
		if okR then
			if finalFacing then
				local r2 = hrp()
				if r2 then r2.CFrame = CFrame.new(r2.Position) * (finalFacing - finalFacing.Position) end
			end
			return true
		end
	end
end

local function get_tree_stand(tree, fromPos, forceRandom)
	local base = tree:GetPivot()
	local basePos = base.Position
	local trunkWidth = tonumber(tree:GetAttribute("TrunkWidth"))
	local trunkRadius = 2.0
	if trunkWidth and trunkWidth > 0 then
		trunkRadius = trunkWidth / 2
	else
		local trunk = tree:FindFirstChild("Trunk") or tree:FindFirstChild("Wood") or tree.PrimaryPart
		if trunk and trunk:IsA("BasePart") then
			trunkRadius = math.max(trunk.Size.X, trunk.Size.Z) / 2
		end
	end
	local safeDist = math.clamp(trunkRadius + 3.0, 4.5, 26.0)

	local dir
	if forceRandom then
		local ang = math.random() * math.pi * 2
		dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
	elseif fromPos then
		local delta = fromPos - basePos
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude > 0.5 then
			dir = flat.Unit
		end
	end
	if not dir then
		dir = (base.LookVector * Vector3.new(1, 0, 1)).Unit
		if dir.Magnitude < 0.1 then dir = Vector3.new(0, 0, 1) end
	end

	local standPos = basePos + dir * safeDist
	local facing = CFrame.lookAt(Vector3.new(standPos.X, basePos.Y + STAND_HEIGHT, standPos.Z), basePos)
	return standPos, facing, safeDist
end

local function attach(tree, anchor, reroll)
	local root = hrp()
	if not root or not tree or not tree.Parent then return end
	local base = tree:GetPivot()
	local basePos = base.Position

	local standPos, facing, safeDist = get_tree_stand(tree, root.Position, reroll)

	local curDelta = root.Position - basePos
	local curDistHoriz = Vector3.new(curDelta.X, 0, curDelta.Z).Magnitude
	local reach = 12.0
	pcall(function()
		if ChopTuning and ChopTuning.ReachOf then
			reach = ChopTuning.ReachOf(tree) or 12.0
		end
	end)

	if not reroll and curDistHoriz <= reach and curDistHoriz >= math.max(safeDist - 2.0, 2.5) and math.abs(root.Position.Y - basePos.Y) < 18 then
		root.Anchored = false
		root.CFrame = CFrame.lookAt(root.Position, Vector3.new(basePos.X, root.Position.Y, basePos.Z))
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		return
	end

	local dist = (standPos - root.Position).Magnitude
	if dist > 8 or reroll then
		teleport_to(standPos, Vector3.zero, facing)
	else
		root.Anchored = false
		root.CFrame = facing
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

local function set_anchored(state)
	local root = hrp()
	if root then root.Anchored = state end
end

local function equip_axe()
	local char = plr.Character
	if not char then return false end
	local function held()
		for _, c in ipairs(char:GetChildren()) do
			if c:IsA("Tool") and c.Name:match("Axe") then return true end
		end
		return false
	end
	if held() then return true end
	local backpack = plr:FindFirstChild("Backpack")
	if not backpack then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return false end

	for _, c in ipairs(backpack:GetChildren()) do
		if c:IsA("Tool") and c.Name:match("Axe") then
			local axeId = c:GetAttribute("AxeId")
			if axeId then
				pcall(function() call(AxeService, "EquipAxe", axeId) end)
				for _ = 1, 16 do
					if held() then return true end
					task.wait(0.05)
				end
			end
			pcall(function() hum:EquipTool(c) end)
			for _ = 1, 16 do
				if held() then return true end
				task.wait(0.05)
			end
		end
	end
	return held()
end

local function ensure_axe_for_chop()
	if equip_axe() then return true end
	task.wait(0.15)
	return equip_axe()
end

local function await(promise, timeout)
	if promise == nil then return {Ok = false, Reason = "nil result"} end
	if type(promise) ~= "table" and typeof(promise) ~= "Instance" then
		return {Ok = true, Value = promise}
	end
	if promise.Ok ~= nil then return promise end
	if type(promise.andThen) ~= "function" then
		return {Ok = true, Value = promise}
	end

	local done, result = false, nil
	local ok = pcall(function()
		promise:andThen(function(v)
			result = v
			done = true
		end, function(e)
			result = {Ok = false, Reason = tostring(e)}
			done = true
		end)
	end)
	if not ok then
		return {Ok = true, Value = promise}
	end

	local t0 = os.clock()
	timeout = timeout or 8
	while not done and os.clock() - t0 < timeout do
		task.wait(0.03)
	end
	if not done then return {Ok = false, Reason = "timeout"} end
	return result
end

local function call(service, method, ...)
	local args = {...}
	local ok, res = pcall(function()
		return service[method](service, table.unpack(args))
	end)
	if not ok then return {Ok = false, Reason = tostring(res)} end
	return await(res)
end

local WoodConfig = require(RS.Modules.Lumber.WoodConfig)
local okSC, SpeciesConfig = pcall(function() return require(RS.Modules.Lumber.SpeciesConfig) end)
if not okSC or type(SpeciesConfig) ~= "table" then SpeciesConfig = nil end
local okTR, TreeRoll = pcall(function() return require(RS.Modules.Lumber.TreeRoll) end)
if not okTR or type(TreeRoll) ~= "table" then TreeRoll = nil end

local VALUE_SCALE = tonumber(WoodConfig.ValueScale) or 1.8
local PERFECT_MULT = tonumber(WoodConfig.PerfectValueMultiplier) or 1.2

local tierCache = {}
local function rarity_info(rarity)
	if tierCache[rarity] == nil then
		local ok, info = pcall(function() return WoodConfig.GetRarity(rarity) end)
		tierCache[rarity] = (ok and type(info) == "table" and info) or {Tier = 0, ValueMultiplier = 1, Chance = 1}
	end
	return tierCache[rarity]
end
local function tier_of(rarity)
	return tonumber(rarity_info(rarity).Tier) or 0
end

local RARITY_ORDER, RARITY_TIER = {}, {}
do
	local list = {}
	for _, r in ipairs(WoodConfig.Rarities or {}) do
		if type(r) == "table" and r.Name then
			list[#list+1] = {name = tostring(r.Name), tier = tonumber(r.Tier) or 0}
		end
	end
	table.sort(list, function(a, b) return a.tier < b.tier end)
	for _, r in ipairs(list) do
		RARITY_ORDER[#RARITY_ORDER+1] = r.name
		RARITY_TIER[r.name] = r.tier
	end
	if #RARITY_ORDER == 0 then
		RARITY_ORDER = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret"}
		for i, n in ipairs(RARITY_ORDER) do RARITY_TIER[n] = i - 1 end
	end
end
local MIN_RARITY_OPTIONS = {"Any"}
for _, n in ipairs(RARITY_ORDER) do MIN_RARITY_OPTIONS[#MIN_RARITY_OPTIONS+1] = n end

local sizeMultCache = {}
local function size_mult(name)
	if not name then return 1 end
	if sizeMultCache[name] ~= nil then return sizeMultCache[name] end
	local m = 1
	for _, z in ipairs(WoodConfig.Sizes or {}) do
		if type(z) == "table" and z.Name == name then
			m = tonumber(z.ValueMultiplier) or 1
			break
		end
	end
	sizeMultCache[name] = m
	return m
end

local function mutation_names(tree)
	local raw = tree:GetAttribute("Mutations")
	local out = {}
	if type(raw) == "string" then
		if raw ~= "" then
			for name in string.gmatch(raw, "[^,%s]+") do out[#out+1] = name end
		end
	elseif type(raw) == "table" then
		for _, v in ipairs(raw) do
			if type(v) == "string" then
				out[#out+1] = v
			elseif tonumber(v) and type(WoodConfig.Mutations) == "table" then
				local m = WoodConfig.Mutations[tonumber(v)]
				if type(m) == "table" and m.Name then out[#out+1] = tostring(m.Name) end
			end
		end
	end
	return out
end

local function mutation_mult(tree)
	local mult = 1
	for _, name in ipairs(mutation_names(tree)) do
		local ok, info = pcall(function() return WoodConfig.GetMutation(name) end)
		if ok and type(info) == "table" and tonumber(info.ValueMultiplier) then
			mult = mult * info.ValueMultiplier
		end
	end
	return mult
end

local pptCache = {}
local function price_per_tonne(biome)
	if not biome then return 0 end
	if pptCache[biome] ~= nil then return pptCache[biome] end
	local ppt = 0
	if SpeciesConfig and type(SpeciesConfig.PricePerTonne) == "function" then
		local ok, v = pcall(function() return SpeciesConfig.PricePerTonne(biome) end)
		if ok and tonumber(v) then ppt = tonumber(v) end
	end
	if ppt == 0 and type(WoodConfig.Biomes) == "table" then
		local b = WoodConfig.Biomes[biome]
		if type(b) == "table" and tonumber(b.PricePerTonne) then ppt = tonumber(b.PricePerTonne) end
	end
	pptCache[biome] = ppt
	return ppt
end

local function tonnes_of(t)
	return (tonumber(t:GetAttribute("Weight")) or 0) / 1000
end

local function tree_value(t, withPerfect)
	local base = tonnes_of(t) * price_per_tonne(t:GetAttribute("Biome")) * VALUE_SCALE
	local rvm = tonumber(rarity_info(t:GetAttribute("Rarity")).ValueMultiplier) or 1
	local perfect = withPerfect and PERFECT_MULT or 1
	return base * rvm * size_mult(t:GetAttribute("Size")) * mutation_mult(t) * perfect
end

local function value_of(tree)
	return tree_value(tree, S.perfectOn)
end

local function sell_value_of(tree)
	return tree_value(tree, S.perfectOn)
end

local function tree_odds(t)
	if TreeRoll and type(TreeRoll.OneIn) == "function" then
		local ok, n = pcall(function()
			return TreeRoll.OneIn(t:GetAttribute("Biome"), t:GetAttribute("Rarity"),
				t:GetAttribute("Size"), mutation_names(t))
		end)
		if ok and tonumber(n) and tonumber(n) > 0 then return tonumber(n) end
	end
	local chance = 1
	local okC, rc = pcall(function()
		return WoodConfig.RarityChance(t:GetAttribute("Biome"), t:GetAttribute("Rarity"))
	end)
	if okC and tonumber(rc) and tonumber(rc) > 0 then
		chance = chance * tonumber(rc)
	else
		chance = chance * (tonumber(rarity_info(t:GetAttribute("Rarity")).Chance) or 1)
	end
	local okS, sc = pcall(function() return WoodConfig.ScaleChance(tonumber(t:GetAttribute("Scale")) or 1) end)
	if okS and tonumber(sc) and tonumber(sc) > 0 then chance = chance * tonumber(sc) end
	for _, name in ipairs(mutation_names(t)) do
		local okM, mi = pcall(function() return WoodConfig.GetMutation(name) end)
		if okM and type(mi) == "table" and tonumber(mi.Chance) and tonumber(mi.Chance) > 0 then
			chance = chance * tonumber(mi.Chance)
		end
	end
	if chance <= 0 then chance = 1e-9 end
	return 1 / chance
end

local function tree_price(t)
	return tree_value(t, S.perfectOn)
end

local function passes_rarity(t)
	return tier_of(t:GetAttribute("Rarity")) >= (S.minTier or 0)
end

local function tree_size_label(t)
	local scale = tonumber(t:GetAttribute("Scale"))
	if not scale then return "" end
	local okL, label = pcall(function() return WoodConfig.SizeAt(scale) end)
	if okL and type(label) == "string" then return label end
	return ""
end

local function is_live(tree)
	local st = tree:GetAttribute("State")
	if st == "Ready" then return true end
	if st == "Locked" and tree:GetAttribute("LockedBy") == plr.UserId then return true end
	return false
end

local function is_growing(tree)
	return tree:GetAttribute("State") == "Growing"
end

local function grow_remaining(tree)
	local start = tonumber(tree:GetAttribute("GrowStart"))
	local dur = tonumber(tree:GetAttribute("GrowSeconds"))
	if not start or not dur then return nil end
	return (start + dur) - os.time()
end

local function fmt_remaining(sec)
	if sec == nil then return "?" end
	if sec <= 0 then return "now" end
	if sec < 60 then return ("%ds"):format(math.floor(sec + 0.5)) end
	local m = math.floor(sec / 60)
	local s = math.floor(sec % 60)
	return ("%dm%02ds"):format(m, s)
end

local ISLAND_BOUNDS = {
	{Folder = "OakIsland", Biome = "StarterForest", X = 84.5, Z = -562.1, HalfW = 292, HalfD = 202},
	{Folder = "BirchIsland", Biome = "BirchHills", X = 711.9, Z = -569.2, HalfW = 212, HalfD = 321},
	{Folder = "CrescentIsland", Biome = "PalmCove", X = 104.1, Z = 145.9, HalfW = 290, HalfD = 303},
	{Folder = "SnowyPines", Biome = "SnowyPines", X = 1361.1, Z = -626.4, HalfW = 278, HalfD = 294},
	{Folder = "DustyMesa", Biome = "DustyMesa", X = -626.1, Z = 341.1, HalfW = 254, HalfD = 314},
	{Folder = "RedwoodGrove", Biome = "RedwoodGrove", X = -8.9, Z = -1216.7, HalfW = 226, HalfD = 226},
}

local function current_island_biome()
	local root = hrp()
	if not root then return nil end
	local pos = root.Position
	for _, isl in ipairs(ISLAND_BOUNDS) do
		if pos.X >= (isl.X - isl.HalfW) and pos.X <= (isl.X + isl.HalfW) and pos.Z >= (isl.Z - isl.HalfD) and pos.Z <= (isl.Z + isl.HalfD) then
			return isl.Biome, isl.Folder
		end
	end
	return nil, nil
end

local function on_same_island(tree)
	local myBiome = current_island_biome()
	if not myBiome then return true end
	local tBiome = tree:GetAttribute("Biome")
	return tBiome == myBiome
end

local function is_candidate(tree)
	if not is_live(tree) and not (S.includeGrowing and is_growing(tree)) then
		return false
	end
	if S.sameIslandOnly and not on_same_island(tree) then
		return false
	end
	return true
end

local function held_axe_id()
	local char = plr.Character
	if not char then return nil end
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") and c.Name:match("Axe") then return c.Name end
	end
	return nil
end

local function current_axe_spec()
	local id = held_axe_id()
	if not id then return nil end
	local cfg = AxeConfig[id]
	if type(cfg) ~= "table" then return nil end
	return {
		Power = cfg.Power or 1,
		Speed = cfg.Speed or 1,
		HitPower = cfg.HitPower or 1,
		PerfectWindow = cfg.PerfectWindow or 1,
		ExtraReach = cfg.ExtraReach or 0,
	}
end

local function can_fell(tree, axeSpec)
	if not axeSpec then return true end
	local ok, pressure = pcall(function()
		return ChopTuning.Pressure(
			tree:GetAttribute("Biome"),
			tree:GetAttribute("Rarity"),
			tree:GetAttribute("Size"),
			axeSpec)
	end)
	if not ok then return true end
	return pressure < ChopTuning.BeyondReach
end

local function chop_seconds(tree, axeSpec)
	if not axeSpec then return nil end
	local ok, res = pcall(function()
		return ChopTuning.Compute(
			tree:GetAttribute("Rarity"),
			tree:GetAttribute("Size"),
			axeSpec,
			tree:GetAttribute("Biome"),
			1, nil)
	end)
	if ok and type(res) == "table" and res.MinDuration then return res.MinDuration end
	return nil
end

local MODES = {"Smart", "MostValuable", "Rarest", "SellValue", "Heaviest", "Biggest", "Nearest", "Any"}

local function top_score(t)
	local money = tree_value(t, S.perfectOn)
	if money <= 0 then return -1e18, money, 0 end
	if money < 1 then return -1e17 + money, money, tree_odds(t) end
	local odds = tree_odds(t)
	local rare = 1 + tier_of(t:GetAttribute("Rarity"))
	local w = math.clamp(tonumber(S.weightValue) or 0.6, 0, 1)
	local moneyTerm = math.log10(1 + money)
	local rareTerm = math.log10(1 + odds) * 0.35 + math.log10(rare) * 2
	return (1 - w) * moneyTerm + w * rareTerm, money, odds
end

local ESP = {folder = nil, treeTags = {}, playerTags = {}, merchTags = {}, conns = {}, counts = {}}
local espCfg = S.esp

local function esp_ensure_folder()
	if ESP.folder and ESP.folder.Parent then return ESP.folder end
	local f = workspace:FindFirstChild("BlizzardESP")
	if not f then
		f = Instance.new("Folder")
		f.Name = "BlizzardESP"
		f.Parent = workspace
	end
	ESP.folder = f
	return f
end

local function esp_kill_conns()
	for _, c in ipairs(ESP.conns) do pcall(function() c:Disconnect() end) end
	ESP.conns = {}
end

local function esp_kill_highlights()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Highlight") and d.Name == "BlzPlayerHL" then d:Destroy() end
	end
end

local rarColorCache = {}
local function rarity_color(name)
	if not name then return Color3.fromRGB(200, 200, 200) end
	local c = rarColorCache[name]
	if c then return c end
	local ok, info = pcall(function() return WoodConfig.GetRarity(name) end)
	c = (ok and type(info) == "table" and info.Color) or Color3.fromRGB(200, 200, 200)
	rarColorCache[name] = c
	return c
end

local mutCache
local function mutation_info(idx)
	if mutCache == nil then
		mutCache = {}
		pcall(function()
			for k, v in pairs(WoodConfig.Mutations) do
				if type(v) == "table" and v.Name then
					mutCache[tonumber(k)] = {Name = tostring(v.Name), Color = v.Color}
				end
			end
		end)
	end
	return mutCache[idx]
end

local function hex(c)
	return ("#%02x%02x%02x"):format(
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5))
end

local MUTED_HEX = "#9aa0a6"
local DANGER_HEX = "#ff5a5a"
local SHOP_HEX = "#ffcd40"

local function value_band(v)
	if v >= 100000 then return Color3.fromRGB(255, 90, 140) end
	if v >= 10000 then return Color3.fromRGB(255, 205, 64) end
	if v >= 1000 then return Color3.fromRGB(150, 235, 90) end
	return Color3.fromRGB(210, 210, 210)
end

local function fmt_val(v)
	if v >= 1e6 then return ("$%.2gm"):format(v / 1e6) end
	if v >= 1e4 then return ("$%.0fk"):format(v / 1e3) end
	if v >= 1e3 then return ("$%.1fk"):format(v / 1e3) end
	return ("$%d"):format(math.floor(v))
end

local function esp_billboard(tagName, adornee, richText)
	local wide = 178 + espCfg.textSize * 3
	local bb = Instance.new("BillboardGui")
	bb.Name = tagName
	bb.Adornee = adornee
	bb.Size = UDim2.fromOffset(wide, espCfg.textSize * 2 + 10)
	bb.StudsOffset = Vector3.new(0, 3.4, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = espCfg.maxDist
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamMedium
	t.RichText = true
	t.TextSize = espCfg.textSize
	t.Text = richText
	t.TextColor3 = Color3.fromRGB(235, 235, 235)
	t.TextStrokeTransparency = 0.35
	t.TextStrokeColor3 = Color3.new(0, 0, 0)
	t.TextWrapped = false
	t.Parent = bb
	return bb
end

local function esp_refresh_tag(bb, richText)
	if not bb or not bb.Parent then return end
	pcall(function()
		bb.MaxDistance = espCfg.maxDist
		local t = bb.Text
		t.TextSize = espCfg.textSize
		t.Text = richText
	end)
end

local function esp_tree_text(t, dist, okFell)
	local wood = t:GetAttribute("Wood") or t.Name
	local rarity = t:GetAttribute("Rarity")
	local rc = rarity_color(rarity)
	local vc = (espCfg.valueColor == "Rarity") and rc or value_band(value_of(t))
	local l1 = {}
	l1[#l1+1] = ('<font color="%s">%s</font>'):format(hex(rc), wood)
	l1[#l1+1] = ('<b><font color="%s">%s</font></b>'):format(hex(vc), fmt_val(value_of(t)))
	if espCfg.showDist then
		l1[#l1+1] = ('<font color="%s">%dm</font>'):format(MUTED_HEX, math.floor(dist))
	end
	local l2 = {}
	if espCfg.showRarity and rarity then
		l2[#l2+1] = ('<font color="%s">%s</font>'):format(hex(rc), rarity:sub(1, 4))
	end
	if espCfg.showMutations then
		for _, name in ipairs(mutation_names(t)) do
			local ok, mi = pcall(function() return WoodConfig.GetMutation(name) end)
			if ok and type(mi) == "table" then
				l2[#l2+1] = ('<font color="%s">%s</font>'):format(
					hex(mi.Color or Color3.new(1, 1, 1)), tostring(mi.Name):sub(1, 5))
			end
		end
	end
	if not okFell then
		l2[#l2+1] = ('<font color="%s">X no-axe</font>'):format(DANGER_HEX)
	end
	local line2 = table.concat(l2, " ")
	return table.concat(l1, "  ") .. (line2 ~= "" and ("\n" .. line2) or "")
end

local function esp_player_text(p, dist)
	local col = dist <= (S.panicRadius or 50) and DANGER_HEX or nil
	local name = ('<b><font color="%s">%s</font></b>'):format(col or "#f2f2f2", p.DisplayName)
	if espCfg.showDist then
		return ("%s  <font color=\"%s\">%dm</font>"):format(name, MUTED_HEX, math.floor(dist))
	end
	return name
end

local function esp_merchant_text(dist, label)
	local who = ('<b><font color="%s">%s</font></b>'):format(SHOP_HEX, label or "Merchant")
	if espCfg.showDist then
		return ("%s  <font color=\"%s\">%dm</font>"):format(who, MUTED_HEX, math.floor(dist))
	end
	return who
end

local function esp_tag_player(p)
	local char = p.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if not char:FindFirstChild("BlzPlayerHL") then
		local hl = Instance.new("Highlight")
		hl.Name = "BlzPlayerHL"
		hl.FillColor = Color3.fromRGB(255, 70, 70)
		hl.OutlineColor = Color3.new(1, 1, 1)
		hl.FillTransparency = 0.65
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Adornee = char
		hl.Parent = char
	end
	if not ESP.playerTags[p] then
		local bb = esp_billboard("BlzPlayerTag", root, esp_player_text(p, 0))
		bb.Parent = esp_ensure_folder()
		ESP.playerTags[p] = bb
	end
end

local function esp_players_loop(myToken)
	table.insert(ESP.conns, game.Players.PlayerAdded:Connect(function()
		task.wait(1)
		if S.esp.players and S.token == myToken then
			for _, p in ipairs(game.Players:GetPlayers()) do
				if p ~= plr then esp_tag_player(p) end
			end
		end
	end))
	table.insert(ESP.conns, game.Players.PlayerRemoving:Connect(function(p)
		local bb = ESP.playerTags[p]
		if bb then bb:Destroy() end
		ESP.playerTags[p] = nil
	end))
	table.insert(ESP.conns, plr.CharacterAdded:Connect(function()
		task.wait(1)
		if not (S.esp.players and S.token == myToken) then return end
		for _, p in ipairs(game.Players:GetPlayers()) do
			if p ~= plr then esp_tag_player(p) end
		end
	end))
	while S.esp.players and S.token == myToken do
		local myRoot = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		local seen = 0
		for _, p in ipairs(game.Players:GetPlayers()) do
			if p ~= plr then
				esp_tag_player(p)
				seen += 1
				local bb = ESP.playerTags[p]
				local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if bb and myRoot and r then
					local d = (r.Position - myRoot.Position).Magnitude
					esp_refresh_tag(bb, esp_player_text(p, d))
				end
			end
		end
		ESP.counts.players = seen
		task.wait(0.25)
	end
end

local function esp_trees_loop(myToken)
	while S.esp.trees and S.token == myToken do
		local myRoot = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		local folder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Trees")
		if myRoot and folder then
			local axeSpec = current_axe_spec()
			local near = {}
			local liveCount = 0
			for _, t in ipairs(folder:GetChildren()) do
				if t:IsA("Model") and t:FindFirstChild("Trunk") and is_live(t) then
					liveCount += 1
					local d = (t.Trunk.Position - myRoot.Position).Magnitude
					if d <= espCfg.maxDist then
						near[#near+1] = {t = t, d = d}
					end
				end
			end
			table.sort(near, function(a, b) return a.d < b.d end)
			local keep, shown = {}, 0
			for _, e in ipairs(near) do
				if shown >= espCfg.maxTags then break end
				local okFell = can_fell(e.t, axeSpec)
				if espCfg.hideUnfellable and not okFell then
					continue
				end
				keep[e.t] = true
				shown += 1
				local text = esp_tree_text(e.t, e.d, okFell)
				local tag = ESP.treeTags[e.t]
				if not tag or not tag.Parent then
					tag = esp_billboard("BlzTreeTag", e.t.Trunk, text)
					tag.Parent = esp_ensure_folder()
					ESP.treeTags[e.t] = tag
				else
					esp_refresh_tag(tag, text)
				end
			end
			for t, tag in pairs(ESP.treeTags) do
				if not keep[t] then
					tag:Destroy()
					ESP.treeTags[t] = nil
				end
			end
			ESP.counts.trees = liveCount
			ESP.counts.treeTags = shown
		end
		task.wait(1.5)
	end
end

local function esp_merchants_loop(myToken)
	while S.esp.merchants and S.token == myToken do
		local myRoot = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if myRoot then
			local seen = {}
			local npcRoot = workspace.Map and workspace.Map:FindFirstChild("NPCs")
			local roots = npcRoot and {npcRoot} or {}
			if workspace.Map then
				local wanderer = workspace.Map:FindFirstChild("Wanderer")
				if wanderer then roots[#roots+1] = wanderer end
			end
			for _, root in ipairs(roots) do
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("Model") and d.Name:lower():match("merchant") and not seen[d] then
					local ok, pos = pcall(function() return d:GetPivot().Position end)
					if ok and pos then
						seen[d] = true
						local dist = (pos - myRoot.Position).Magnitude
						if dist <= espCfg.maxDist then
							local tag = ESP.merchTags[d]
							local label = "Merchant"
							if d.Name == "Merchant" then
								label = "Miku"
							elseif d.Name:match("^(.-) the Merchant$") then
								label = d.Name:match("^(.-) the Merchant$")
							end
							local text = esp_merchant_text(dist, label)
							if not tag or not tag.Parent then
								tag = esp_billboard("BlzShopTag", d, text)
								tag.Parent = esp_ensure_folder()
								ESP.merchTags[d] = tag
							else
								esp_refresh_tag(tag, text)
							end
						end
					end
				end
			end
			end
			for m, tag in pairs(ESP.merchTags) do
				if not seen[m] then
					tag:Destroy()
					ESP.merchTags[m] = nil
				end
			end
			ESP.counts.shops = 0
			for _ in pairs(ESP.merchTags) do ESP.counts.shops += 1 end
		end
		task.wait(1.5)
	end
end

local function esp_apply(kind, on)
	local myToken = S.token
	local cfg = S.esp
	if kind == "players" then
		cfg.players = on
		if on then
			task.spawn(esp_players_loop, myToken)
		else
			for _, bb in pairs(ESP.playerTags) do pcall(function() bb:Destroy() end) end
			table.clear(ESP.playerTags)
			esp_kill_highlights()
			ESP.counts.players = nil
		end
	elseif kind == "trees" then
		cfg.trees = on
		if on then
			task.spawn(esp_trees_loop, myToken)
		else
			for _, tag in pairs(ESP.treeTags) do pcall(function() tag:Destroy() end) end
			table.clear(ESP.treeTags)
			ESP.counts.trees = nil
			ESP.counts.treeTags = nil
		end
	elseif kind == "merchants" then
		cfg.merchants = on
		if on then
			task.spawn(esp_merchants_loop, myToken)
		else
			for _, tag in pairs(ESP.merchTags) do pcall(function() tag:Destroy() end) end
			table.clear(ESP.merchTags)
			ESP.counts.shops = nil
		end
	end
	if not cfg.players and not cfg.trees and not cfg.merchants then esp_kill_conns() end
end

local function esp_counts_text()
	local c = ESP.counts
	local f = ESP.folder
	local tags = 0
	if f then for _ in ipairs(f:GetChildren()) do tags += 1 end end
	local bits = {}
	bits[#bits+1] = ("tags <Accent>%d</Accent>"):format(tags)
	if c.treeTags then bits[#bits+1] = ("trees <Accent>%d</Accent>"):format(c.trees or 0) end
	if c.players then bits[#bits+1] = ("players <Accent>%d</Accent>"):format(c.players) end
	if c.shops then bits[#bits+1] = ("shops <Accent>%d</Accent>"):format(c.shops) end
	if #bits == 0 then return "<Muted>overlay off</Muted>" end
	return table.concat(bits, "  ·  ")
end

local function player_near(pos, radius)
	for _, p in ipairs(game.Players:GetPlayers()) do
		if p ~= plr then
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local d = (root.Position - pos) * Vector3.new(1, 0, 1)
				if d.Magnitude <= radius then return true end
			end
		end
	end
	return false
end

local function nearest_player_dist(pos)
	local best, who = math.huge, nil
	for _, p in ipairs(game.Players:GetPlayers()) do
		if p ~= plr then
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local d = (root.Position - pos) * Vector3.new(1, 0, 1)
				if d.Magnitude < best then best, who = d.Magnitude, p end
			end
		end
	end
	return best, who
end

local function pick(mode, blocked)
	local folder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Trees")
	if not folder then return nil end
	local now = os.clock()
	local axeSpec = current_axe_spec()
	local minTier = tonumber(S.minTier) or 0
	local list = {}
	local skipped, panicked, filtered = 0, 0, 0
	for _, t in ipairs(folder:GetChildren()) do
		if is_live(t) and not (blocked[t] and blocked[t] > now) then
			if S.sameIslandOnly and not on_same_island(t) then
				filtered += 1
			elseif not passes_rarity(t) then
				filtered += 1
			elseif S.panicOn and player_near(t:GetPivot().Position, S.panicRadius) then
				panicked += 1
			elseif can_fell(t, axeSpec) then
				table.insert(list, t)
			else
				skipped += 1
			end
		end
	end
	S.panicked = panicked
	S.skipped = skipped
	S.filtered = filtered
	if #list == 0 then return nil end

	local root = hrp()
	local origin = root and root.Position or Vector3.zero
	local function dist(t)
		local d = (t:GetPivot().Position - origin) * Vector3.new(1, 0, 1)
		return d.Magnitude
	end

	if mode == "Nearest" then
		table.sort(list, function(a, b) return dist(a) < dist(b) end)
	elseif mode == "MostValuable" then
		table.sort(list, function(a, b)
			local va, vb = tree_value(a, S.perfectOn), tree_value(b, S.perfectOn)
			if va ~= vb then return va > vb end
			return dist(a) < dist(b)
		end)
	elseif mode == "SellValue" then
		table.sort(list, function(a, b)
			local vaa, vab = sell_value_of(a), sell_value_of(b)
			if vaa ~= vab then return vaa > vab end
			return dist(a) < dist(b)
		end)
	elseif mode == "Rarest" then
		table.sort(list, function(a, b)
			local ta, tb = tier_of(a:GetAttribute("Rarity")), tier_of(b:GetAttribute("Rarity"))
			if ta ~= tb then return ta > tb end
			local va, vb = tree_value(a, S.perfectOn), tree_value(b, S.perfectOn)
			if va ~= vb then return va > vb end
			return dist(a) < dist(b)
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
	elseif mode == "Smart" then
		table.sort(list, function(a, b)
			local sa, sb = top_score(a), top_score(b)
			if sa ~= sb then return sa > sb end
			return dist(a) < dist(b)
		end)
	end
	return list[1]
end

local function settle_on_ground()
	local root = hrp()
	local char = plr.Character
	if not root or not char then return end
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") then pcall(function() p.CanCollide = true end) end
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Landed, true) end)
		pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true) end)
		pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {char, workspace.Map:FindFirstChild("Trees")}
	rp.IgnoreWater = true
	local pos = root.Position
	local ray = workspace:Raycast(Vector3.new(pos.X, pos.Y + 80, pos.Z), Vector3.new(0, -220, 0), rp)
	if ray then
		local groundY = ray.Position.Y + 3.0
		if math.abs(pos.Y - groundY) > 0.6 then
			root.CFrame = CFrame.new(pos.X, groundY, pos.Z) * (root.CFrame - root.CFrame.Position)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			task.wait(0.15)
		end
	end
end

local function chop_tree(tree)
	if not tree or not tree.Parent then return false, "tree gone" end
	ensure_axe_for_chop()
	attach(tree, true, false)
	ensure_axe_for_chop()
	settle_on_ground()

	local char = plr.Character
	local axeTool = nil
	if char then
		for _, c in ipairs(char:GetChildren()) do
			if c:IsA("Tool") and c.Name:match("Axe") then axeTool = c break end
		end
	end
	if not axeTool then
		return false, "no axe equipped"
	end

	local okCC, ChopController = pcall(function() return Knit.GetController("ChopController") end)
	local okCS, ChopState = pcall(function() return require(plr.PlayerScripts.Source.state.ChopState) end)
	local GuiService = game:GetService("GuiService")

	if not (okCC and okCS and ChopController and ChopState) then
		return false, "controllers missing"
	end

	local trunk = tree:FindFirstChild("Trunk") or tree.PrimaryPart or tree:GetPivot()
	local trunkPos = trunk.Position
	local cam = workspace.CurrentCamera
	if cam then
		cam.CFrame = CFrame.lookAt(cam.CFrame.Position, trunkPos)
	end
	task.wait(0.05)
	local vp = cam and cam:WorldToViewportPoint(trunkPos) or Vector3.new(200, 200, 0)
	local screenPos = Vector2.new(vp.X, vp.Y) - GuiService:GetGuiInset()

	ChopController:BeginWindup(axeTool, screenPos)
	local fillSec = (ChopTuning and tonumber(ChopTuning.WindupFillSeconds)) or 0.65
	task.wait(fillSec)
	ChopController:ReleaseWindup()

	local sessionStarted = false
	for _ = 1, 30 do
		if not alive() or (not S.farm and not S.sniping) then
			pcall(function() ChopController:Cancel() end)
			return false, "cancelled"
		end
		if ChopState.session() ~= nil then
			sessionStarted = true
			break
		end
		task.wait(0.05)
	end

	if not sessionStarted then
		pcall(function() ChopController:Cancel() end)
		return false, "session failed to start"
	end

	local t0 = os.clock()
	local maxDuration = 15
	local session = ChopState.session()
	if session and session.Params and session.Params.MinDuration then
		maxDuration = math.max(12, session.Params.MinDuration + 6)
	end

	while os.clock() - t0 < maxDuration and ChopState.session() ~= nil do
		if not alive() or (not S.farm and not S.sniping) then
			pcall(function() ChopController:Cancel() end)
			return false, "cancelled"
		end
		local rw = plr.PlayerGui:FindFirstChild("ReactWorld")
		if rw then
			for _, dot in ipairs(rw:GetChildren()) do
				if dot.Name:match("Dot") then
					local hitBtn = dot:FindFirstChild("Hit", true)
					local ring = dot:FindFirstChild("Area", true) and dot.Area:FindFirstChild("Ring", true)
					local stroke = ring and ring:FindFirstChild("Square", true) and ring.Square:FindFirstChild("Ring", true) and ring.Square.Ring:FindFirstChild("Stroke", true)
					if hitBtn and stroke then
						local c = stroke.Color
						if c.G > 0.8 and c.R < 0.75 then
							local fakeInput = {
								UserInputType = Enum.UserInputType.MouseButton1,
								Position = Vector3.new(hitBtn.AbsolutePosition.X, hitBtn.AbsolutePosition.Y, 0)
							}
							pcall(function()
								firesignal(hitBtn.InputBegan, fakeInput, false)
							end)
							task.wait(0.12) -- debounce
							break
						end
					end
				end
			end
		end
		task.wait(0.015)
	end

	task.wait(0.6)
	local isFelled = (not tree.Parent) or (tree:GetAttribute("State") == "Felled")

	if ChopState.session() ~= nil then
		pcall(function() ChopController:Cancel() end)
		task.wait(0.15)
	end

	return isFelled, isFelled and "felled" or "held"
end

local function owned_axes()
	local out = {}
	local char = plr.Character
	if char then
		for _, c in ipairs(char:GetChildren()) do
			if c:IsA("Tool") then out[c.Name] = true end
		end
	end
	local bp = plr:FindFirstChild("Backpack")
	if bp then
		for _, c in ipairs(bp:GetChildren()) do
			if c:IsA("Tool") then out[c.Name] = true end
		end
	end
	return out
end

local function equipped_axe()
	local char = plr.Character
	if not char then return nil end
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") and c.Name:match("Axe") then return c.Name end
	end
	return nil
end

local AXE_FALLBACK_COORDS = {
	IronAxe = Vector3.new(-114.5, 24.5, -512.0),
	Hatchet = Vector3.new(-100.4, 23.7, -508.7),
	SteelAxe = Vector3.new(649.5, 6.5, -595.0),
	RangersAxe = Vector3.new(647.8, 5.9, -596.8),
	GoldenAxe = Vector3.new(192.0, 12.2, -47.6),
	DriftwoodAxe = Vector3.new(191.3, 11.3, -50.4),
	ProspectorsAxe = Vector3.new(-552.4, 11.6, 299.7),
	ThunderheadAxe = Vector3.new(-59.2, 27.5, -584.6),
	TimberAxe = Vector3.new(26.0, 7.5, -1038.4),
}

local function fmt_price(n)
	n = tonumber(n) or 0
	if n >= 1e6 then
		local m = n / 1e6
		if m == math.floor(m) then return ("$%dm"):format(m) end
		return ("$%.1fm"):format(m):gsub("%.0m", "m")
	elseif n >= 1e3 then
		local k = n / 1e3
		if k == math.floor(k) then return ("$%dk"):format(k) end
		return ("$%.1fk"):format(k):gsub("%.0k", "k")
	end
	return ("$%d"):format(n)
end

local function axe_ladder()
	local shops = {}
	for _, prompt in ipairs(CS:GetTagged("AxeView")) do
		local id = prompt:GetAttribute("AxeId")
		local model = prompt:FindFirstAncestorOfClass("Model")
		if id and model then
			shops[id] = model:GetPivot().Position
		end
	end
	local list = {}
	for id, cfg in pairs(AxeConfig) do
		local shopPos = shops[id] or AXE_FALLBACK_COORDS[id]
		if type(cfg) == "table" and shopPos then
			local ok, price = pcall(function() return AxePrice.For(id, {}) end)
			table.insert(list, {
				id = id,
				name = tostring(cfg.DisplayName or id),
				price = ok and price or (cfg.Price or 0),
				level = cfg.Level or 1,
				power = cfg.Power or 0,
				speed = cfg.Speed or 0,
				luck = cfg.Luck or 0,
				pos = shopPos,
			})
		end
	end
	table.sort(list, function(a, b) return a.price < b.price end)
	return list
end

local function bucks()
	local ls = plr:FindFirstChild("leaderstats")
	local b = ls and ls:FindFirstChild("Bucks")
	return b and b.Value or 0
end

local function buy_axe(axe)
	teleport_to(axe.pos, Vector3.new(0, 3, 4))
	local res = call(AxeService, "BuyAxe", axe.id)
	if type(res) == "table" and res.Ok then
		call(AxeService, "EquipAxe", axe.id)
		return true, "bought + equipped " .. axe.name
	end
	return false, (type(res) == "table" and res.Reason) or "buy failed"
end

local ladder = axe_ladder()
local axeRows = {}

local BLIZZARD_SCHEME = {
	Background = Color3.fromRGB(15, 18, 26),
	Surface = Color3.fromRGB(18, 22, 31),
	Surface2 = Color3.fromRGB(22, 26, 37),
	Surface3 = Color3.fromRGB(37, 44, 60),
	Stroke = Color3.fromRGB(34, 40, 55),
	StrokeHover = Color3.fromRGB(58, 92, 104),
	Accent = Color3.fromRGB(100, 205, 215),
	AccentDark = Color3.fromRGB(14, 18, 30),
	Text = Color3.fromRGB(228, 232, 242),
	Muted = Color3.fromRGB(116, 126, 148),
	Warning = Color3.fromRGB(240, 176, 108),
	Success = Color3.fromRGB(150, 220, 170),
	Error = Color3.fromRGB(240, 120, 120),
}
pcall(function() Airflow:SetTheme(BLIZZARD_SCHEME) end)
pcall(function() Airflow:SetDefaultTheme(BLIZZARD_SCHEME) end)

local VISUAL = {
	fpsBoost = false,
	ultraFps = false,
	superUltraFps = false,
}

function VISUAL.setFpsBoost(on)
	VISUAL.fpsBoost = on
	local Lighting = game:GetService("Lighting")
	if on then
		pcall(function()
			Lighting.GlobalShadows = false
			Lighting.FogEnd = 9e9
			Lighting.ShadowSoftness = 0
			for _, v in ipairs(Lighting:GetChildren()) do
				if v:IsA("PostEffect") or v:IsA("Atmosphere") or v:IsA("Sky") then
					v.Enabled = false
				end
			end
			local terrain = workspace:FindFirstChildOfClass("Terrain")
			if terrain then
				terrain.Decoration = false
				terrain.WaterWaveSize = 0
				terrain.WaterWaveSpeed = 0
				terrain.WaterReflectance = 0
			end
		end)
	else
		pcall(function()
			Lighting.GlobalShadows = true
			Lighting.FogEnd = 1000
			for _, v in ipairs(Lighting:GetChildren()) do
				if v:IsA("PostEffect") or v:IsA("Atmosphere") or v:IsA("Sky") then
					v.Enabled = true
				end
			end
		end)
	end
end

function VISUAL.setUltraFps(on)
	VISUAL.ultraFps = on
	VISUAL.setFpsBoost(on)
	if on then
		task.spawn(function()
			local count = 0
			for _, d in ipairs(workspace:GetDescendants()) do
				if not VISUAL.ultraFps then break end
				if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail")
					or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then
					pcall(function() d.Enabled = false end)
				elseif d:IsA("Decal") or d:IsA("Texture") then
					pcall(function() d.Transparency = 1 end)
				elseif d:IsA("BasePart") then
					pcall(function()
						d.CastShadow = false
						d.Material = Enum.Material.SmoothPlastic
						d.Reflectance = 0
					end)
				end
				count += 1
				if count % 400 == 0 then
					task.wait()
				end
			end
		end)
	else
		task.spawn(function()
			local count = 0
			for _, d in ipairs(workspace:GetDescendants()) do
				if VISUAL.ultraFps then break end
				if d:IsA("Decal") or d:IsA("Texture") then
					pcall(function() d.Transparency = 0 end)
				end
				count += 1
				if count % 400 == 0 then
					task.wait()
				end
			end
		end)
	end
end

function VISUAL.setSuperUltraFps(on)
	VISUAL.superUltraFps = on
	VISUAL.setUltraFps(on)
	if on then
		pcall(function()
			pcall(function() settings().Rendering.QualityLevel = 1 end)
			local Lighting = game:GetService("Lighting")
			Lighting.Brightness = 2
			Lighting.ClockTime = 14
			Lighting.Ambient = Color3.fromRGB(150, 150, 150)
			Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 150)
		end)
	end
end

local SPOOF_NAME = "Blizzard Hub"

local function apply_glimmer(lbl)
	if not lbl or not lbl:IsA("TextLabel") then return end
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	if lbl:FindFirstChild("BlizzardGlimmer") then return end

	local grad = Instance.new("UIGradient")
	grad.Name = "BlizzardGlimmer"
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.0, Color3.fromRGB(168, 85, 247)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(216, 180, 254)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.7, Color3.fromRGB(216, 180, 254)),
		ColorSequenceKeypoint.new(1.0, Color3.fromRGB(168, 85, 247)),
	})
	grad.Offset = Vector2.new(-1, 0)
	grad.Parent = lbl

	local tw = game:GetService("TweenService"):Create(
		grad,
		TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false),
		{Offset = Vector2.new(1, 0)}
	)
	tw:Play()
end

local function remove_glimmer(lbl, origColor)
	if not lbl or not lbl:IsA("TextLabel") then return end
	local oldGrad = lbl:FindFirstChild("BlizzardGlimmer")
	if oldGrad then pcall(function() oldGrad:Destroy() end) end
	if origColor then lbl.TextColor3 = origColor end
end

function S.set_hide_ingame_name(on)
	S.hideIngameName = on
	local targetName = on and SPOOF_NAME or plr.DisplayName

	local function apply_overhead()
		local pgui = plr:FindFirstChild("PlayerGui")
		local rw = pgui and pgui:FindFirstChild("ReactWorld")
		local tag = rw and rw:FindFirstChild("Overhead" .. tostring(plr.UserId))
		if tag and tag:IsA("BillboardGui") then
			tag.Enabled = true
			local card = tag:FindFirstChild("Content") and tag.Content:FindFirstChild("Card")
			local content = card and card:FindFirstChild("Content")
			local nameLabel = content and content:FindFirstChild("Name")
			if nameLabel and nameLabel:IsA("TextLabel") then
				if on then
					if nameLabel.Text ~= targetName then
						nameLabel.Text = targetName
					end
					apply_glimmer(nameLabel)
					if not getgenv().__BlizzardHideOverheadPropConn then
						local inChange = false
						getgenv().__BlizzardHideOverheadPropConn = nameLabel:GetPropertyChangedSignal("Text"):Connect(function()
							if inChange then return end
							if S.hideIngameName and nameLabel.Text ~= SPOOF_NAME then
								inChange = true
								pcall(function() nameLabel.Text = SPOOF_NAME end)
								inChange = false
							end
						end)
					end
				else
					if getgenv().__BlizzardHideOverheadPropConn then
						pcall(function() getgenv().__BlizzardHideOverheadPropConn:Disconnect() end)
						getgenv().__BlizzardHideOverheadPropConn = nil
					end
					remove_glimmer(nameLabel, Color3.fromRGB(232, 232, 232))
					nameLabel.Text = targetName
				end
			end
		end
	end

	pcall(apply_overhead)

	local pgui = plr:FindFirstChild("PlayerGui")
	local rw = pgui and pgui:FindFirstChild("ReactWorld")
	if on then
		if not getgenv().__BlizzardHideOverheadConn and rw then
			getgenv().__BlizzardHideOverheadConn = rw.DescendantAdded:Connect(function(desc)
				if S.hideIngameName and desc:IsA("TextLabel") and desc.Name == "Name" then
					local tag = rw:FindFirstChild("Overhead" .. tostring(plr.UserId))
					if tag and desc:IsDescendantOf(tag) then
						task.defer(apply_overhead)
					end
				end
			end)
		end
	else
		if getgenv().__BlizzardHideOverheadConn then
			pcall(function() getgenv().__BlizzardHideOverheadConn:Disconnect() end)
			getgenv().__BlizzardHideOverheadConn = nil
		end
	end

	local function apply_leaderboard()
		local cg = game:GetService("CoreGui")
		local pl = cg:FindFirstChild("PlayerList")
		if not pl then return end
		local entry = pl:FindFirstChild("PlayerEntry_" .. tostring(plr.UserId), true)
		local pNameFrame = entry and entry:FindFirstChild("PlayerName", true)
		local leadLabel = pNameFrame and pNameFrame:FindFirstChildOfClass("TextLabel")
		if leadLabel then
			if on then
				leadLabel.Text = targetName
				apply_glimmer(leadLabel)
			else
				remove_glimmer(leadLabel, Color3.fromRGB(247, 247, 248))
				leadLabel.Text = targetName
			end
		end
	end

	pcall(apply_leaderboard)

	local cg = game:GetService("CoreGui")
	local pl = cg:FindFirstChild("PlayerList")
	if on then
		if not getgenv().__BlizzardHideLeaderboardConn and pl then
			getgenv().__BlizzardHideLeaderboardConn = pl.DescendantAdded:Connect(function(desc)
				if S.hideIngameName and desc.Name == ("PlayerEntry_" .. tostring(plr.UserId)) then
					task.defer(apply_leaderboard)
				end
			end)
		end
	else
		if getgenv().__BlizzardHideLeaderboardConn then
			pcall(function() getgenv().__BlizzardHideLeaderboardConn:Disconnect() end)
			getgenv().__BlizzardHideLeaderboardConn = nil
		end
	end
end

local Window = Airflow:CreateWindow({
	Name = "Blizzard Hub",
	LoadingSubtitle = "Foresters",
	Icon = "rbxassetid://74093118428711",
	ToggleUIKeybind = "RightShift",
	Backdrop = {Weather = "None", Tint = 0.45},
	AdaptiveSize = false,
	UIScale = 1,
	Density = "Default",
	Size = UDim2.fromOffset(700, 430),
	ConfigurationSaving = {Enabled = true, FolderName = "ForestersHub"},
})
S.window = Window

do
	local discordTab = Window:CreateTab({Name = "Discord", Icon = "message-square"})
	local gbDiscord = discordTab:CreateGroupbox({Name = "Discord", Side = "Left"})
	local gbChangelog = discordTab:CreateGroupbox({Name = "Changelog", Side = "Right"})

	gbDiscord:CreateLabel("Join our community:")
	gbDiscord:CreateInput({
		Name = "Invite Link",
		Default = "https://discord.gg/C56zw6khS8",
		Placeholder = "https://discord.gg/C56zw6khS8",
		Callback = function() end,
	})
	gbDiscord:CreateButton({
		Name = "Copy Discord Link",
		Callback = function()
			pcall(function()
				local link = "https://discord.gg/C56zw6khS8"
				if setclipboard then
					setclipboard(link)
				elseif toclipboard then
					toclipboard(link)
				elseif syn and syn.write_clipboard then
					syn.write_clipboard(link)
				end
				Window:Notify({Title = "Discord", Content = "Invite link copied to clipboard!", Duration = 3})
			end)
		end,
	})

	gbChangelog:CreateParagraph({
		Title = "Latest Updates",
		Content = "—",
	})
end

local farmTab = Window:CreateTab({Name = "Farm", Icon = "tree-pine"})
local levelingTab = Window:CreateTab({Name = "Leveling", Icon = "trending-up"})
local questTab = Window:CreateTab({Name = "Quest", Icon = "scroll"})
local teleportTab = Window:CreateTab({Name = "Teleport", Icon = "map-pin"})
local axeTab = Window:CreateTab({Name = "Axes", Icon = "axe"})
local visualTab = Window:CreateTab({Name = "Visual", Icon = "eye"})
local panicTab = Window:CreateTab({Name = "Panic", Icon = "shield-alert"})
local settingsTab = Window:CreateTab({Name = "Settings", Icon = "settings"})

local gbTop = farmTab:CreateGroupbox({Name = "Top wood", Side = "Left"})
local gbFarm = farmTab:CreateGroupbox({Name = "Farming", Side = "Left"})
local gbSession = farmTab:CreateGroupbox({Name = "Session", Side = "Right"})
local gbMove = farmTab:CreateGroupbox({Name = "Movement", Side = "Right"})

local gbAxes = axeTab:CreateGroupbox({Name = "Shop", Side = "Left"})
local gbLadder = axeTab:CreateGroupbox({Name = "Buy ladder", Side = "Right"})

local gbVisualPerf = visualTab:CreateGroupbox({Name = "Performance", Side = "Left"})
local gbEsp = visualTab:CreateGroupbox({Name = "Overlay", Side = "Left"})
local gbEspStyle = visualTab:CreateGroupbox({Name = "Style", Side = "Right"})

local gbPanic = panicTab:CreateGroupbox({Name = "Panic Mode", Side = "Left"})
local gbPanicStatus = panicTab:CreateGroupbox({Name = "Status", Side = "Right"})

local stats = {felled = 0, failed = 0, startedAt = 0, blocked = {}}
local modeIndex = 1
local farmOn = false

local function safe_set(label, text)
	pcall(function() label:Set(text) end)
end

S.sniping = false
getgenv().__TopErr = nil
local MAX_TOP_ROWS = 12
local topLabel, topRows = nil, {}
local okTop, errTop = pcall(function()
	topLabel = gbTop:CreateLabel("idle — live ranking")
	for i = 1, MAX_TOP_ROWS do
		local row = {tree = nil}
		topRows[i] = row
		row.button = gbTop:CreateButton({
			Name = "…",
			Callback = function()
				local t = row.tree
				if S.sniping then return end
				if not (t and t.Parent and t:FindFirstChild("Trunk") and is_candidate(t)) then
					safe_set(topLabel, "gone — pick another")
					return
				end
				S.sniping = true
				local woodName = tostring(t:GetAttribute("Wood") or t:GetAttribute("Species") or t.Name)
				if is_growing(t) then
					safe_set(topLabel, ("camping %s — %s"):format(woodName, fmt_remaining(grow_remaining(t))))
					task.spawn(function()
						local okP, felled, why = pcall(function()
							local standPos, facing = get_tree_stand(t, hrp() and hrp().Position)
							local okTp, errTp = teleport_to(standPos, Vector3.zero, facing)
							if not okTp then
								return false, errTp or "teleport blocked"
							end
							task.wait(0.4)
							local deadline = os.clock() + math.max(grow_remaining(t) or 0, 0) + 30
							while t.Parent and os.clock() < deadline do
								if not is_growing(t) then break end
								local left = grow_remaining(t)
								if left and left > 0 then
									safe_set(topLabel, ("waiting %s — %s"):format(woodName, fmt_remaining(left)))
								end
								task.wait(0.5)
							end
							if not (t.Parent and is_live(t)) then
								return false, "grew but not choppable"
							end
							return chop_tree(t)
						end)
						if okP and felled then
							safe_set(topLabel, ("sniped %s"):format(woodName))
						else
							safe_set(topLabel, ("fail: %s"):format(tostring(okP and why or felled):sub(1, 22)))
						end
						S.sniping = false
					end)
					return
				end
				safe_set(topLabel, "sniping " .. woodName .. "…")
				task.spawn(function()
					local okP, felled, why = pcall(function()
						local standPos, facing = get_tree_stand(t, hrp() and hrp().Position)
						local okTp, errTp = teleport_to(standPos, Vector3.zero, facing)
						if not okTp then
							return false, errTp or "teleport blocked"
						end
						task.wait(0.4)
						return chop_tree(t)
					end)
					if okP and felled then
						safe_set(topLabel, ("sniped %s"):format(woodName))
					else
						safe_set(topLabel, ("fail: %s"):format(tostring(okP and why or felled):sub(1, 20)))
					end
					S.sniping = false
				end)
			end,
		})
		pcall(function() row.button:SetVisible(false) end)
		pcall(function()
			local title = row.button._title
			title.Size = UDim2.new(1, -8, 1, 0)
			title.AnchorPoint = Vector2.new(0, 0.5)
			title.Position = UDim2.new(0, 4, 0.5, 0)
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextYAlignment = Enum.TextYAlignment.Center
			title.TextTruncate = Enum.TextTruncate.AtEllipsis
			title.TextWrapped = false
			title.RichText = true
		end)
	end
	getgenv().__TopRows = nil
	getgenv().__TopRowsV2 = topRows
	getgenv().__TopLabel = topLabel
end)
if not okTop then getgenv().__TopErr = tostring(errTop) end

local stateLabel = gbFarm:CreateStatus({Name = "State", Style = "Dot", Value = "idle"})
local targetLabel = gbFarm:CreateLabel("-")
local countLabel = gbFarm:CreateStatus({Name = "Chopped", Style = "Row", Value = "0 / 0"})
local rateLabel = gbFarm:CreateStatus({Name = "Rate", Style = "Row", Value = "0/min"})
local axeLabel = gbSession:CreateStatus({Name = "Axe", Style = "Row", Value = "-"})
local buckLabel = gbSession:CreateStatus({Name = "Bucks", Style = "Row", Value = "$0"})
local sellLabel = gbSession:CreateLabel("off")

local buyLabel = gbAxes:CreateStatus({Name = "Auto buy", Style = "Row", Value = "off"})
local buyLogLabel = gbAxes:CreateLabel("-")
gbAxes:CreateStatus({
	Name = "Equipped",
	Style = "Row",
	UpdateRate = 2,
	Update = function()
		local eq = equipped_axe()
		if not eq then return "none", "Muted" end
		local cfg = AxeConfig[eq]
		return (cfg and cfg.DisplayName or eq) .. "  P" .. tostring(cfg and cfg.Power or "?"), "Success"
	end,
})
gbAxes:CreateStatus({
	Name = "Owned",
	Style = "Row",
	UpdateRate = 2,
	Update = function()
		local n = 0
		for _ in pairs(owned_axes()) do n += 1 end
		return ("%d / %d"):format(n, #ladder)
	end,
})
gbAxes:CreateStatus({
	Name = "Next target",
	Style = "Row",
	UpdateRate = 2,
	Update = function()
		local own = owned_axes()
		for _, axe in ipairs(ladder) do
			if not own[axe.id] then
				local b = bucks()
				if b >= axe.price then
					return ("%s %s Lv.%s ready"):format(axe.name, fmt_price(axe.price), tostring(axe.level or 1)), "Success"
				end
				return ("%s %s Lv.%s · %d%% saved"):format(
					axe.name, fmt_price(axe.price), tostring(axe.level or 1), math.floor(math.min(b / axe.price, 1) * 100)), "Warning"
			end
		end
		return "ladder complete", "Success"
	end,
})

local panicLabel = gbPanicStatus:CreateStatus({
	Name = "Nearest",
	Style = "Dot",
	UpdateRate = 1,
	Update = function()
		if not S.panicOn then return "off", "Muted" end
		local myRoot = hrp()
		if not myRoot then return "no char", "Warning" end
		local d, who = nearest_player_dist(myRoot.Position)
		if d <= (S.panicRadius or 50) then
			return ("! %s %dm"):format(who and who.DisplayName or "?", math.floor(d)), "Error"
		end
		return ("%dm"):format(math.floor(d)), "Success"
	end,
})

gbPanicStatus:CreateStatus({
	Name = "Action",
	Style = "Row",
	UpdateRate = 1,
	Update = function()
		if not S.panicOn then return "inactive", "Muted" end
		if S.panicWho then
			return ("paused (%s)"):format(tostring(S.panicWho)), "Warning"
		end
		return "monitoring", "Success"
	end,
})

gbPanic:CreateToggle({
	Name = "Panic Mode",
	Flag = "PanicMode",
	CurrentValue = S.panicOn or false,
	Callback = function(on)
		S.panicOn = on
	end,
})

gbPanic:CreateSlider({
	Name = "Panic radius",
	Range = {30, 150},
	Increment = 5,
	CurrentValue = S.panicRadius or 50,
	Suffix = " studs",
	Flag = "PanicRadius",
	Callback = function(n)
		S.panicRadius = n
	end,
})

gbVisualPerf:CreateToggle({
	Name = "FPS Boost",
	Flag = "FpsBoost",
	CurrentValue = false,
	Callback = function(on)
		VISUAL.setFpsBoost(on)
	end,
})

gbVisualPerf:CreateToggle({
	Name = "Ultra FPS Boost",
	Flag = "UltraFps",
	CurrentValue = false,
	Callback = function(on)
		VISUAL.setUltraFps(on)
	end,
})

gbVisualPerf:CreateToggle({
	Name = "Super Ultra FPS Boost",
	Flag = "SuperUltraFps",
	CurrentValue = false,
	Callback = function(on)
		VISUAL.setSuperUltraFps(on)
	end,
})

gbEsp:CreateToggle({
	Name = "Players",
	Flag = "EspPlayers",
	CurrentValue = false,
	Callback = function(on)
		esp_apply("players", on)
	end,
})
gbEsp:CreateToggle({
	Name = "Trees",
	Flag = "EspTrees",
	CurrentValue = false,
	Callback = function(on)
		esp_apply("trees", on)
	end,
})
gbEsp:CreateToggle({
	Name = "Merchants",
	Flag = "EspMerchants",
	CurrentValue = false,
	Callback = function(on)
		esp_apply("merchants", on)
	end,
})
gbEsp:CreateStatus({
	Name = "Live",
	Style = "Row",
	Update = esp_counts_text,
})

gbEspStyle:CreateSlider({
	Name = "Max distance",
	Range = {100, 1500},
	Increment = 50,
	CurrentValue = espCfg.maxDist,
	Suffix = " studs",
	Flag = "EspMaxDist",
	Callback = function(n) espCfg.maxDist = n end,
})
gbEspStyle:CreateSlider({
	Name = "Max tags",
	Range = {5, 40},
	Increment = 1,
	CurrentValue = espCfg.maxTags,
	Flag = "EspMaxTags",
	Callback = function(n) espCfg.maxTags = n end,
})
gbEspStyle:CreateSlider({
	Name = "Text size",
	Range = {10, 18},
	Increment = 1,
	CurrentValue = espCfg.textSize,
	Flag = "EspTextSize",
	Callback = function(n) espCfg.textSize = n end,
})
gbEspStyle:CreateDropdown({
	Name = "$ colour",
	Flag = "EspValueColor",
	Options = {"Bands", "Rarity"},
	CurrentOption = espCfg.valueColor,
	Callback = function(sel)
		local chosen = type(sel) == "table" and sel[1] or sel
		espCfg.valueColor = chosen == "Rarity" and "Rarity" or "Bands"
	end,
})
gbEspStyle:CreateToggle({
	Name = "Show rarity",
	Flag = "EspRarity",
	CurrentValue = espCfg.showRarity,
	Callback = function(on) espCfg.showRarity = on end,
})
gbEspStyle:CreateToggle({
	Name = "Show mutations",
	Flag = "EspMutations",
	CurrentValue = espCfg.showMutations,
	Callback = function(on) espCfg.showMutations = on end,
})
gbEspStyle:CreateToggle({
	Name = "Show distance",
	Flag = "EspDist",
	CurrentValue = espCfg.showDist,
	Callback = function(on) espCfg.showDist = on end,
})
gbEspStyle:CreateToggle({
	Name = "Hide unfellable",
	Flag = "EspHideUnfellable",
	CurrentValue = espCfg.hideUnfellable,
	Callback = function(on) espCfg.hideUnfellable = on end,
})

local function refresh_axe_info()
	local eq = equipped_axe()
	local cfg = eq and AxeConfig[eq]
	safe_set(axeLabel, eq and ((cfg and cfg.DisplayName or eq) .. "  " .. tostring(cfg and cfg.Power or "?")) or "none")
	safe_set(buckLabel, "$" .. tostring(bucks()))
end

local function rate()
	if stats.startedAt == 0 or stats.felled == 0 then return 0 end
	local mins = (os.clock() - stats.startedAt) / 60
	if mins <= 0 then return 0 end
	return stats.felled / mins
end

local function refresh_state()
	safe_set(stateLabel, farmOn and "RUNNING" or "idle")
	safe_set(countLabel, ("%d / %d"):format(stats.felled, stats.failed))
	safe_set(rateLabel, ("%.1f/min"):format(rate()))
end

local lastTargetText = nil
local function set_target_text(text)
	if text == lastTargetText then return end
	lastTargetText = text
	safe_set(targetLabel, text)
end

local farmToggle
local function set_farm(on)
	farmOn = on
	S.farm = on
	if farmToggle then farmToggle:Set(on) end
	if not on then
		noclipOn = false
		set_anchored(false)
		restore_collide()
		refresh_state()
		return
	end

	stats.felled = 0
	stats.failed = 0
	stats.startedAt = os.clock()
	stats.blocked = {}
	noclipOn = false
	restore_collide()
	refresh_state()

	task.spawn(function()
		while S.farm and alive() do
			local ok, msg = pcall(function()
				if S.panicOn then
					local myRoot = hrp()
					if myRoot then
						local d, who = nearest_player_dist(myRoot.Position)
						if d <= (S.panicRadius or 50) then
							S.panicClearAt = nil
							S.panicWho = who and who.DisplayName
							task.wait(0.5)
							return ("panic: %s %dm"):format(tostring(S.panicWho), math.floor(d))
						end
						if not S.panicClearAt then S.panicClearAt = os.clock() end
						if os.clock() - S.panicClearAt < 5 then
							task.wait(0.3)
							return "panic cooldown"
						end
					end
				end
				if S.selling then
					task.wait(0.25)
					return "selling in progress"
				end
				local mode = MODES[modeIndex]
				local root = hrp()
				if not root then
					return "no character"
				end
				if root.Position.Y < -20 then
					local char = plr.Character
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					if hum then
						pcall(function() hum.Health = 0 end)
						task.wait(1.5)
					end
					return "void recovery respawn"
				end
				local tree = pick(mode, stats.blocked)
				if not tree then
					set_target_text("-")
					task.wait(0.5)
					return "no tree ready"
				end
				set_target_text(tostring(tree:GetAttribute("Species") or tree.Name))
				local good, result = chop_tree(tree)
				if not good then
					stats.blocked[tree] = os.clock() + 2.5
					stats.failed += 1
					local root = hrp()
					local base = tree.Parent and tree:GetPivot()
					S.lastFail = ("%s | %s | state=%s | dist=%s | y=%s"):format(
						tostring(result),
						tostring(tree.Name),
						tostring(tree:GetAttribute("State")),
						(base and root) and string.format("%.1f", (root.Position - base.Position).Magnitude) or "?",
						root and math.floor(root.Position.Y) or "?")
					return tostring(result)
				end
				stats.felled += 1
				S.lastFail = nil
				refresh_axe_info()
				if S.autoSell and not S.selling then
					local held
					local okQ, q = pcall(function() return call(LumberMillService, "Quote") end)
					if okQ and type(q) == "table" and type(q.Count) == "number" then
						held = q.Count
						S.logCount = held
					else
						S.logCount = (S.logCount or 0) + 1
						held = S.logCount
					end
					safe_set(sellLabel, ("%d / %d"):format(held, S.sellAt or 50))
					if held >= (S.sellAt or 50) then
						S.selling = true
						safe_set(sellLabel, "selling…")
						task.spawn(function()
							local okP, r1, r2 = pcall(auto_sell_pass)
							local okSell, why
							if okP then
								okSell, why = r1, r2
							else
								okSell, why = false, tostring(r1)
							end
							if okSell then S.logCount = 0 end
							safe_set(sellLabel, okSell and "sold" or ("fail: " .. tostring(why):sub(1, 16)))
							S.selling = false
						end)
					end
				end
				return tostring(result)
			end)
			if not ok then
				stats.failed += 1
				S.lastFail = "loop error: " .. tostring(msg)
			end
			refresh_state()
			task.wait(0.02)
		end
	end)
	refresh_state()
end

farmToggle = gbFarm:CreateToggle({
	Name = "Auto Farm",
	Flag = "AutoFarm",
	CurrentValue = false,
	Callback = function(on) set_farm(on) end,
})

gbFarm:CreateDropdown({
	Name = "Target class",
	Flag = "TargetMode",
	Options = MODES,
	CurrentOption = MODES[1],
	Callback = function(sel)
		local chosen = type(sel) == "table" and sel[1] or sel
		for i, m in ipairs(MODES) do
			if m == chosen then modeIndex = i end
		end
	end,
})

gbFarm:CreateDropdown({
	Name = "Min rarity",
	Flag = "MinRarity",
	Options = MIN_RARITY_OPTIONS,
	CurrentOption = MIN_RARITY_OPTIONS[(S.minTier or 0) + 1] or "Any",
	Callback = function(sel)
		local chosen = type(sel) == "table" and sel[1] or sel
		local tier = 0
		if chosen ~= "Any" then
			tier = RARITY_TIER[chosen] or 0
		end
		S.minTier = tier
	end,
})

gbFarm:CreateSlider({
	Name = "Min value",
	Range = {0, 100000},
	Increment = 500,
	CurrentValue = S.minValue or 0,
	Suffix = "$",
	Flag = "MinValue",
	Callback = function(n) S.minValue = n end,
})

gbFarm:CreateDropdown({
	Name = "Top sort",
	Flag = "TopSort",
	Options = {"Money", "Rarity", "Odds"},
	CurrentOption = S.topSort or "Money",
	Callback = function(sel)
		local chosen = type(sel) == "table" and sel[1] or sel
		S.topSort = (chosen == "Rarity" or chosen == "Odds") and chosen or "Money"
	end,
})

gbFarm:CreateSlider({
	Name = "Top rows",
	Range = {3, 12},
	Increment = 1,
	CurrentValue = S.maxRows or 8,
	Flag = "TopRows",
	Callback = function(n) S.maxRows = n end,
})

gbFarm:CreateSlider({
	Name = "Chance vs money",
	Range = {0, 100},
	Increment = 5,
	CurrentValue = math.floor((S.weightValue or 0.6) * 100),
	Suffix = "%",
	Flag = "WeightValue",
	Callback = function(n) S.weightValue = (tonumber(n) or 60) / 100 end,
})

gbFarm:CreateSlider({
	Name = "Refresh every",
	Range = {1, 20},
	Increment = 1,
	CurrentValue = S.refreshRate or 10,
	Suffix = "s",
	Flag = "RefreshRate",
	Callback = function(n) S.refreshRate = n end,
})

gbFarm:CreateToggle({
	Name = "Include growing",
	Flag = "IncludeGrowing",
	CurrentValue = S.includeGrowing or false,
	Callback = function(on)
		S.includeGrowing = on
		if topLabel then
			safe_set(topLabel, on and "growing trees included" or "growing trees hidden")
		end
	end,
})

gbFarm:CreateToggle({
	Name = "Same island only",
	Flag = "SameIslandOnly",
	CurrentValue = S.sameIslandOnly == true,
	Callback = function(on)
		S.sameIslandOnly = on
		if topLabel then
			safe_set(topLabel, on and "locked to current island" or "all islands shown")
		end
	end,
})

WALK.label = gbMove:CreateLabel("mode: " .. (S.moveMode == "bike" and "bike tp (wip)" or "respawn tp"))

gbMove:CreateDropdown({
	Name = "Movement Method",
	Flag = "MovementMethod",
	Options = {"Respawn TP", "Bike TP (WIP)"},
	CurrentOption = (S.moveMode == "bike") and "Bike TP (WIP)" or "Respawn TP",
	Callback = function(sel)
		local chosen = type(sel) == "table" and sel[1] or sel
		if chosen == "Bike TP (WIP)" then
			S.moveMode = "bike"
			safe_set(WALK.label, "mode: bike tp (wip)")
		else
			S.moveMode = "respawn"
			safe_set(WALK.label, "mode: respawn tp")
		end
	end,
})

local function sell_logs()
	local res = call(LumberMillService, "SellTrees", "All")
	if type(res) == "table" and res.Ok then return true end
	local res2 = call(LumberMillService, "SellTrees", "Held")
	if type(res2) == "table" and res2.Ok then return true end
	return false, type(res) == "table" and res.Reason or "sell refused"
end

local function nearest_merchant()
	local best, bestD = nil, math.huge
	local root = hrp()
	if not root then return nil end
	local roots = {}
	local map = workspace:FindFirstChild("Map")
	if map then
		local npcs = map:FindFirstChild("NPCs")
		if npcs then roots[#roots+1] = npcs end
		local wanderer = map:FindFirstChild("Wanderer")
		if wanderer then roots[#roots+1] = wanderer end
	end
	if #roots == 0 then roots = {workspace} end
	for _, container in ipairs(roots) do
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("Model") and d.Name:lower():match("merchant") then
			local ok, pos = pcall(function() return d:GetPivot().Position end)
			if ok and pos then
				local dist = (pos - root.Position).Magnitude
				if dist < bestD then best, bestD = d, dist end
			end
		end
		if d:IsA("BasePart") and d.Name:lower():match("merchant") then
			local dist = (d.Position - root.Position).Magnitude
			if dist < bestD then best, bestD = d, dist end
		end
	end
	end
	return best, bestD
end

local function auto_sell_pass()
	local merchant, dist = nearest_merchant()
	if merchant then
		local ok, pos = pcall(function() return merchant:GetPivot().Position end)
		if ok and pos then
			local root = hrp()
			if root then
				teleport_to(pos, Vector3.new(0, 3, 4))
				task.wait(1.0)
			end
		end
	end
	local lastWhy
	for attempt = 1, 4 do
		local ok, why = sell_logs()
		if ok then return true, nil end
		lastWhy = why
		task.wait(0.7)
	end
	return false, lastWhy
end

gbSession:CreateToggle({
	Name = "Auto Sell",
	Flag = "AutoSell",
	CurrentValue = false,
	Callback = function(on)
		S.autoSell = on
		safe_set(sellLabel, on and ("at " .. tostring(S.sellAt)) or "off")
	end,
})

gbSession:CreateSlider({
	Name = "Sell at logs",
	Range = {10, 200},
	Increment = 10,
	CurrentValue = S.sellAt or 50,
	Suffix = " logs",
	Flag = "SellAt",
	Callback = function(n)
		S.sellAt = n
		if S.autoSell then safe_set(sellLabel, "at " .. tostring(n)) end
	end,
})

gbSession:CreateButton({
	Name = "Sell now",
	Callback = function()
		task.spawn(function()
			local ok, why = auto_sell_pass()
			safe_set(sellLabel, ok and "sold" or ("fail: " .. tostring(why):sub(1, 20)))
		end)
	end,
})

local autobuyOn = false

local function refresh_ladder()
	local own = owned_axes()
	local eq = equipped_axe()
	for _, row in ipairs(axeRows) do
		local isOwned = own[row.axe.id] == true
		local tag = isOwned and (eq == row.axe.id and "  [equipped]" or "  [owned]") or ""
		row.button:SetText(("%s  %s  Lv.%s  power %.1f%s"):format(row.axe.name, fmt_price(row.axe.price), tostring(row.axe.level or 1), row.axe.power, tag))
		pcall(function() row.button:SetDisabled(isOwned) end)
	end
	refresh_axe_info()
end

for _, axe in ipairs(ladder) do
	local button = gbLadder:CreateButton({
		Name = ("%s  %s  Lv.%s  power %.1f"):format(axe.name, fmt_price(axe.price), tostring(axe.level or 1), axe.power),
		Callback = function()
			task.spawn(function()
				buyLabel:Set("auto buy: manual")
				local ok, msg = buy_axe(axe)
				buyLogLabel:Set("last: " .. tostring(msg))
				refresh_ladder()
			end)
		end,
	})
	table.insert(axeRows, {axe = axe, button = button})
end

local function next_target()
	local own = owned_axes()
	for _, axe in ipairs(ladder) do
		if not own[axe.id] and bucks() >= axe.price then
			return axe
		end
	end
	return nil
end

gbAxes:CreateToggle({
	Name = "Auto buy next affordable",
	Flag = "AutoBuy",
	CurrentValue = false,
	Callback = function(on)
		autobuyOn = on
		S.autobuy = on
		buyLabel:Set("auto buy: " .. (on and "ON" or "off"))
		if not on then return end
		task.spawn(function()
			while S.autobuy and alive() do
				local axe = next_target()
				if not axe then
					buyLogLabel:Set("last: nothing affordable left")
					task.wait(3)
				else
					buyLogLabel:Set("last: buying " .. axe.name)
					local ok, msg = buy_axe(axe)
					buyLogLabel:Set("last: " .. tostring(msg))
					refresh_ladder()
					task.wait(0.6)
				end
			end
		end)
	end,
})

gbAxes:CreateButton({
	Name = "Equip best owned axe",
	Callback = function()
		task.spawn(function()
			local own = owned_axes()
			local best
			for _, axe in ipairs(ladder) do
				if own[axe.id] then best = axe end
			end
			if not best then
				buyLogLabel:Set("last: no owned axe found")
				return
			end
			local res = call(AxeService, "EquipAxe", best.id)
			buyLogLabel:Set("last: " .. ((type(res) == "table" and res.Ok) and ("equipped " .. best.name) or "equip failed"))
			refresh_ladder()
		end)
	end,
})

local function init_leveling_module()
	local gbLevelControls = levelingTab:CreateGroupbox({Name = "Leveling Autofarm", Side = "Left"})
	local gbLevelStatus = levelingTab:CreateGroupbox({Name = "Status & Target", Side = "Right"})

	local REDWOOD_BOUNDS = {minX = -220, maxX = 220, minZ = -1450, maxZ = -700}
	local REDWOOD_SPAWN = Vector3.new(2, 5, -1051)

	local function is_in_redwood(pos)
		if not pos then return false end
		return pos.X >= REDWOOD_BOUNDS.minX and pos.X <= REDWOOD_BOUNDS.maxX and pos.Z >= REDWOOD_BOUNDS.minZ and pos.Z <= REDWOOD_BOUNDS.maxZ
	end

	local levelStateLabel = gbLevelStatus:CreateStatus({Name = "State", Style = "Dot", Value = "idle"})
	local levelTargetLabel = gbLevelStatus:CreateLabel("target: -")
	local levelFelledLabel = gbLevelStatus:CreateStatus({Name = "Chopped", Style = "Row", Value = "0 trees"})
	local levelRateLabel = gbLevelStatus:CreateStatus({Name = "Rate", Style = "Row", Value = "0/min"})

	local felledCount = 0
	local startTime = 0
	local levelSpeed = 24
	local autoLevelingToggle = nil
	local unreachable = {}
	local currentAbortFlag = false
	local failcheckEnabled = true

	local function update_stats()
		levelFelledLabel:Set(tostring(felledCount) .. " trees")
		if startTime > 0 and felledCount > 0 then
			local mins = (os.clock() - startTime) / 60
			if mins > 0.05 then
				local rate = math.floor(felledCount / mins + 0.5)
				levelRateLabel:Set(tostring(rate) .. "/min")
			end
		end
	end

	local function safe_horiz_unit(v, fallback)
		if not v then return fallback or Vector3.new(0, 0, -1) end
		local h = Vector3.new(v.X, 0, v.Z)
		if h.Magnitude > 0.05 then
			return h.Unit
		end
		return fallback or Vector3.new(0, 0, -1)
	end

	local function make_spatial_params(char, extraExclude)
		local params = RaycastParams.new()
		local list = {char}
		if extraExclude then
			table.insert(list, extraExclude)
		end
		params.FilterDescendantsInstances = list
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.IgnoreWater = false
		return params
	end

	local function probe_ground(pos, rayParams)
		local ray = workspace:Raycast(pos + Vector3.new(0, 15, 0), Vector3.new(0, -35, 0), rayParams)
		if not ray then return nil end
		if ray.Material == Enum.Material.Water or ray.Position.Y < 3.2 then return nil end
		if ray.Normal.Y < 0.64 then return nil end
		return ray.Position, ray
	end

	local function has_ground_los(fromPos, toPos, rayParams)
		local delta = toPos - fromPos
		if delta.Magnitude < 0.8 then return true end
		if math.abs(delta.Y) > 2.2 then return false end

		local waistFrom = fromPos + Vector3.new(0, 0.8, 0)
		local waistTo = toPos + Vector3.new(0, 0.8, 0)
		local waistRay = workspace:Raycast(waistFrom, waistTo - waistFrom, rayParams)
		if waistRay then return false end

		local kneeFrom = fromPos - Vector3.new(0, 0.8, 0)
		local kneeTo = toPos - Vector3.new(0, 0.8, 0)
		local kneeRay = workspace:Raycast(kneeFrom, kneeTo - kneeFrom, rayParams)
		if kneeRay then return false end

		return true
	end

	local function evaluate_spatial_steering(curPos, desiredDir, rayParams, extraEx)
		local candidateDegs = {0, 20, -20, 42, -42, 65, -65, 90, -90, 120, -120}
		local horizDesired = safe_horiz_unit(desiredDir, Vector3.new(0, 0, -1))
		local bestDir = horizDesired
		local bestScore = -math.huge

		for _, deg in ipairs(candidateDegs) do
			local rad = math.rad(deg)
			local dir = Vector3.new(
				horizDesired.X * math.cos(rad) - horizDesired.Z * math.sin(rad),
				0,
				horizDesired.X * math.sin(rad) + horizDesired.Z * math.cos(rad)
			).Unit

			local goalScore = dir:Dot(horizDesired) * 2.0
			local penalty = 0

			local chestRay = workspace:Raycast(curPos + Vector3.new(0, 0.5, 0), dir * 5.2, rayParams)
			if chestRay then
				local dist = math.max(chestRay.Distance, 0.4)
				local isNpc = chestRay.Instance and (chestRay.Instance:IsDescendantOf(workspace.Map.NPCs) or game.Players:GetPlayerFromCharacter(chestRay.Instance.Parent))
				if isNpc then
					penalty += 45.0 / dist
				else
					penalty += 16.0 / dist
				end
			end

			local headRay = workspace:Raycast(curPos + Vector3.new(0, 2.2, 0), dir * 4.2, rayParams)
			if headRay then
				penalty += 8.0 / math.max(headRay.Distance, 0.4)
			end

			local probePt = curPos + dir * 3.6 + Vector3.new(0, 1.0, 0)
			local downRay = workspace:Raycast(probePt, Vector3.new(0, -9.0, 0), rayParams)
			if not downRay or downRay.Material == Enum.Material.Water or downRay.Position.Y < 3.2 then
				penalty += 150.0
			elseif downRay.Normal.Y < 0.64 then
				penalty += 60.0
			end

			local score = goalScore - penalty
			if score > bestScore then
				bestScore = score
				bestDir = dir
			end
		end

		return bestDir
	end

	local function find_walkable_stand(tree, myPos)
		local treePivot = tree:GetPivot().Position
		local trunkWidth = tonumber(tree:GetAttribute("TrunkWidth")) or 3.5
		local trunkRadius = math.max(trunkWidth / 2, 2.0)

		local reach = 13.0
		pcall(function()
			if ChopTuning and ChopTuning.ReachOf then
				reach = ChopTuning.ReachOf(tree) or 13.0
			end
		end)

		local safeDist = math.clamp((trunkRadius + reach) * 0.5, trunkRadius + 2.4, reach - 2.5)

		local pf = game:GetService("PathfindingService")
		local delta = myPos - treePivot
		local primaryAngle = math.atan2(delta.Z, delta.X)
		local angleOffsets = {0, math.pi/6, -math.pi/6, math.pi/3, -math.pi/3, math.pi/2, -math.pi/2, 2*math.pi/3, -2*math.pi/3, 5*math.pi/6, -5*math.pi/6, math.pi}

		local bestStand, bestPath = nil, nil
		local minCost = math.huge

		local char = plr.Character
		local rayParams = make_spatial_params(char, tree)

		for _, off in ipairs(angleOffsets) do
			local ang = primaryAngle + off
			local candPos = treePivot + Vector3.new(math.cos(ang), 0, math.sin(ang)) * safeDist
			local groundY, gRay = probe_ground(candPos, rayParams)
			if groundY then
				local standPos = Vector3.new(candPos.X, groundY.Y + 2.8, candPos.Z)
				local path = pf:CreatePath({
					AgentRadius = 2.4,
					AgentHeight = 5.0,
					AgentCanJump = true,
					AgentJumpHeight = 3.5,
					AgentMaxSlope = 45,
					WaypointSpacing = 4.0,
					Costs = {
						Water = math.huge,
					}
				})
				local ok = pcall(function() path:ComputeAsync(myPos, standPos) end)
				if ok and path.Status == Enum.PathStatus.Success then
					local wps = path:GetWaypoints()
					if #wps >= 2 then
						local validPath = true
						for k = 1, #wps - 1 do
							local yDelta = wps[k+1].Position.Y - wps[k].Position.Y
							if yDelta > 4.5 then
								validPath = false
								break
							end
						end
						if validPath and #wps < minCost then
							minCost = #wps
							bestStand = standPos
							bestPath = path
							if #wps <= 6 then break end
						end
					end
				end
			end
		end

		return bestStand, bestPath
	end

	local function smart_walk_spatial(path, targetPos, speed, stopDist, treeTarget)
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not (root and hum) then return false, "no character" end

		speed = math.clamp(tonumber(speed or levelSpeed or 24) or 24, 16, 24)
		stopDist = stopDist or 2.8
		hum.WalkSpeed = speed
		hum.AutoRotate = true

		local waypoints = path:GetWaypoints()
		if not waypoints or #waypoints == 0 then return false, "no waypoints" end

		local treePivot = treeTarget and treeTarget.Parent and treeTarget:GetPivot().Position
		local reach = 13.0
		pcall(function()
			if treeTarget and treeTarget.Parent and ChopTuning and ChopTuning.ReachOf then
				reach = ChopTuning.ReachOf(treeTarget) or 13.0
			end
		end)

		local rayParams = make_spatial_params(char, treeTarget)

		local currIdx = 2
		local lastPos = root.Position
		local stallCount = 0
		local waterTime = 0
		local tStart = os.clock()
		local maxTravelTime = math.max(12, (#waypoints * 0.45) + 6)
		local pf = game:GetService("PathfindingService")

		while currIdx <= #waypoints and (os.clock() - tStart < maxTravelTime) do
			if not alive() or not S.levelingOn then return false end
			if currentAbortFlag then
				currentAbortFlag = false
				return false, "watchdog abort"
			end
			hum.WalkSpeed = speed

			local curPos = root.Position

			-- Validate that tree still exists
			if treeTarget and not (treeTarget.Parent and is_live(treeTarget)) then
				return false, "tree gone"
			end

			if treePivot then
				local horizDist = ((curPos - treePivot) * Vector3.new(1, 0, 1)).Magnitude
				local yDist = math.abs(curPos.Y - treePivot.Y)
				if horizDist <= (reach - 1.8) and yDist <= 8.0 then
					return true
				end
			end

			if (curPos - targetPos).Magnitude <= stopDist then
				return true
			end

			if hum:GetState() == Enum.HumanoidStateType.Swimming or curPos.Y < 3.5 then
				waterTime += 0.04
				pcall(function() hum.Jump = true end)
				hum:MoveTo(REDWOOD_SPAWN)
				if waterTime >= 1.2 then
					WALK.respawnJump(REDWOOD_SPAWN)
					return false, "water recovery"
				end
				task.wait(0.04)
				continue
			else
				waterTime = 0
			end

			-- String Pulling with Bounds Safety
			local lookIdx = currIdx
			for j = math.min(currIdx + 4, #waypoints), currIdx + 1, -1 do
				local candPos = waypoints[j].Position
				if has_ground_los(curPos, candPos, rayParams) then
					lookIdx = j
					break
				end
			end
			currIdx = math.clamp(lookIdx, 1, #waypoints)
			local targetWp = waypoints[currIdx]
			if not targetWp then break end

			local moveVector = (targetWp.Position - curPos) * Vector3.new(1, 0, 1)
			local forwardUnit = safe_horiz_unit(moveVector, root.CFrame.LookVector)

			-- Step-Up Auto Jump Feeler
			local kneeRay = workspace:Raycast(curPos - Vector3.new(0, 1.0, 0), forwardUnit * 3.5, rayParams)
			local chestRay = workspace:Raycast(curPos + Vector3.new(0, 0.6, 0), forwardUnit * 3.5, rayParams)
			local headRay = workspace:Raycast(curPos + Vector3.new(0, 2.2, 0), forwardUnit * 3.5, rayParams)

			if kneeRay and not chestRay then
				pcall(function() hum.Jump = true end)
			elseif chestRay and not headRay then
				local checkSurface = workspace:Raycast(curPos + forwardUnit * 2.8 + Vector3.new(0, 4.0, 0), Vector3.new(0, -6.0, 0), rayParams)
				if checkSurface and checkSurface.Position.Y - curPos.Y <= 3.8 and checkSurface.Normal.Y >= 0.7 then
					pcall(function() hum.Jump = true end)
				end
			end

			if targetWp.Action == Enum.PathWaypointAction.Jump then
				pcall(function() hum.Jump = true end)
			end

			local evaluatedDir = evaluate_spatial_steering(curPos, forwardUnit, rayParams, treeTarget)
			hum:MoveTo(curPos + evaluatedDir * 7.0)

			task.wait(0.04)

			local wpDistHoriz = ((root.Position - targetWp.Position) * Vector3.new(1, 0, 1)).Magnitude
			local wpDistY = math.abs(root.Position.Y - targetWp.Position.Y)
			if wpDistHoriz <= 3.2 and wpDistY <= 4.0 then
				currIdx += 1
			end

			-- Advanced Multi-tier De-Wedge with Burst Noclip
			if (root.Position - lastPos).Magnitude < 0.22 then
				stallCount += 1
				if stallCount == 3 then
					pcall(function() hum.Jump = true end)
				elseif stallCount == 6 then
					local sideVec = Vector3.new(-root.CFrame.LookVector.Z, 0, root.CFrame.LookVector.X) * (math.random() > 0.5 and 4.5 or -4.5)
					hum:MoveTo(root.Position + sideVec)
					pcall(function() hum.Jump = true end)
					task.wait(0.12)
				elseif stallCount >= 10 and stallCount <= 13 then
					-- Reverse step & jump to unpin from obstacle collision without noclip
					local bwd = -root.CFrame.LookVector * 4.0
					hum:MoveTo(root.Position + bwd)
					pcall(function() hum.Jump = true end)
					task.wait(0.15)
				elseif stallCount == 14 then
					local ok, newPath = pcall(function()
						local p = pf:CreatePath({
							AgentRadius = 3.2,
							AgentHeight = 5.0,
							AgentCanJump = true,
							AgentJumpHeight = 3.5,
							AgentMaxSlope = 45,
							WaypointSpacing = 4.0,
							Costs = { Water = math.huge }
						})
						p:ComputeAsync(root.Position, targetPos)
						return p
					end)
					if ok and newPath and newPath.Status == Enum.PathStatus.Success then
						waypoints = newPath:GetWaypoints()
						currIdx = 2
					end
				elseif stallCount == 20 then
					local bwd = -root.CFrame.LookVector * 5.5
					hum:MoveTo(root.Position + bwd)
					pcall(function() hum.Jump = true end)
					task.wait(0.2)
				elseif stallCount >= 28 then
					return false, "stuck"
				end
			else
				stallCount = 0
				lastPos = root.Position
			end
		end

		hum:MoveTo(targetPos)
		local tEnd = os.clock()
		while os.clock() - tEnd < 1.0 do
			if treePivot and ((root.Position - treePivot) * Vector3.new(1, 0, 1)).Magnitude <= (reach - 1.5) then
				return true
			end
			if (root.Position - targetPos).Magnitude <= stopDist + 1.2 then
				return true
			end
			task.wait(0.05)
		end

		if treePivot and ((root.Position - treePivot) * Vector3.new(1, 0, 1)).Magnitude <= reach then
			return true
		end
		return (root.Position - targetPos).Magnitude <= stopDist + 2.0
	end

	local function leveling_chop(tree)
		if not tree or not tree.Parent then return false, "tree gone" end
		ensure_axe_for_chop()
		settle_on_ground()

		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local axeTool = nil
		if char then
			for _, c in ipairs(char:GetChildren()) do
				if c:IsA("Tool") and c.Name:match("Axe") then axeTool = c break end
			end
		end
		if not axeTool then return false, "no axe equipped" end

		local okCC, ChopController = pcall(function() return Knit.GetController("ChopController") end)
		local okCS, ChopState = pcall(function() return require(plr.PlayerScripts.Source.state.ChopState) end)
		local GuiService = game:GetService("GuiService")
		if not (okCC and okCS and ChopController and ChopState) then
			return false, "controllers missing"
		end

		local animConn = nil
		local hum = char:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if animator then
			for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
				local tn = t.Name:lower()
				if tn:match("axe") or tn:match("swing") or tn:match("chop") or tn:match("windup") then
					t:Stop(0)
				end
			end
			animConn = animator.AnimationPlayed:Connect(function(track)
				local tn = track.Name:lower()
				if tn:match("axe") or tn:match("swing") or tn:match("chop") or tn:match("windup") then
					task.defer(function() track:Stop(0) end)
				end
			end)
		end

		local treePivot = tree:GetPivot().Position
		local trunk = tree:FindFirstChild("Trunk") or tree.PrimaryPart or tree
		local trunkPos = trunk:IsA("BasePart") and trunk.Position or treePivot

		if root then
			root.CFrame = CFrame.lookAt(root.Position, Vector3.new(trunkPos.X, root.Position.Y, trunkPos.Z))
		end

		local cam = workspace.CurrentCamera
		local aimPos = Vector3.new(trunkPos.X, root and root.Position.Y + 1.2 or trunkPos.Y, trunkPos.Z)
		if cam then
			cam.CFrame = CFrame.lookAt(cam.CFrame.Position, aimPos)
		end
		task.wait(0.04)

		local vp = cam and cam:WorldToViewportPoint(aimPos) or Vector3.new(200, 200, 0)
		local screenPos = Vector2.new(vp.X, vp.Y) - GuiService:GetGuiInset()

		ChopController:BeginWindup(axeTool, screenPos)
		local fillSec = (ChopTuning and tonumber(ChopTuning.WindupFillSeconds)) or 0.65
		task.wait(fillSec)
		ChopController:ReleaseWindup()

		local sessionStarted = false
		for _ = 1, 26 do
			if not alive() or not S.levelingOn then
				pcall(function() ChopController:Cancel() end)
				if animConn then pcall(function() animConn:Disconnect() end) end
				return false, "cancelled"
			end
			if ChopState.session() ~= nil then
				sessionStarted = true
				break
			end
			task.wait(0.04)
		end

		if not sessionStarted and root then
			local closerPos = root.Position + (Vector3.new(trunkPos.X, root.Position.Y, trunkPos.Z) - root.Position).Unit * 1.8
			root.CFrame = CFrame.lookAt(closerPos, Vector3.new(trunkPos.X, closerPos.Y, trunkPos.Z))
			task.wait(0.04)
			if cam then cam.CFrame = CFrame.lookAt(cam.CFrame.Position, aimPos) end
			local vp2 = cam and cam:WorldToViewportPoint(aimPos) or Vector3.new(200, 200, 0)
			ChopController:BeginWindup(axeTool, Vector2.new(vp2.X, vp2.Y) - GuiService:GetGuiInset())
			task.wait(fillSec)
			ChopController:ReleaseWindup()
			for _ = 1, 16 do
				if not alive() or not S.levelingOn then
					pcall(function() ChopController:Cancel() end)
					if animConn then pcall(function() animConn:Disconnect() end) end
					return false, "cancelled"
				end
				if ChopState.session() ~= nil then
					sessionStarted = true
					break
				end
				task.wait(0.04)
			end
		end

		if not sessionStarted then
			pcall(function() ChopController:Cancel() end)
			if animConn then pcall(function() animConn:Disconnect() end) end
			return false, "session failed"
		end

		local t0 = os.clock()
		local maxDuration = 18
		local session = ChopState.session()
		if session and session.Params and session.Params.MinDuration then
			maxDuration = math.max(12, session.Params.MinDuration + 6)
		end

		while os.clock() - t0 < maxDuration and ChopState.session() ~= nil do
			if not alive() or not S.levelingOn then
				pcall(function() ChopController:Cancel() end)
				if animConn then pcall(function() animConn:Disconnect() end) end
				return false, "cancelled"
			end
			local rw = plr.PlayerGui:FindFirstChild("ReactWorld")
			if rw then
				for _, dot in ipairs(rw:GetChildren()) do
					if dot.Name:match("Dot") then
						local hitBtn = dot:FindFirstChild("Hit", true)
						local ring = dot:FindFirstChild("Area", true) and dot.Area:FindFirstChild("Ring", true)
						local stroke = ring and ring:FindFirstChild("Square", true) and ring.Square:FindFirstChild("Ring", true) and ring.Square.Ring:FindFirstChild("Stroke", true)
						if hitBtn and stroke then
							local c = stroke.Color
							if c.G > 0.8 and c.R < 0.75 then
								local fakeInput = {
									UserInputType = Enum.UserInputType.MouseButton1,
									Position = Vector3.new(hitBtn.AbsolutePosition.X, hitBtn.AbsolutePosition.Y, 0)
								}
								pcall(function() firesignal(hitBtn.InputBegan, fakeInput, false) end)
								task.wait(0.05)
								break
							end
						end
					end
				end
			end
			if (not tree.Parent) or (tree:GetAttribute("State") == "Felled") then
				break
			end
			task.wait(0.015)
		end

		task.wait(0.3)
		if animConn then pcall(function() animConn:Disconnect() end) end
		local isFelled = (not tree.Parent) or (tree:GetAttribute("State") == "Felled")
		if ChopState.session() ~= nil then
			pcall(function() ChopController:Cancel() end)
			task.wait(0.1)
		end
		return isFelled, isFelled and "felled" or "held"
	end

	local function get_best_redwood_tree()
		local myRoot = hrp()
		if not myRoot then return nil end
		local myPos = myRoot.Position
		local trees = workspace.Map:FindFirstChild("Trees")
		if not trees then return nil end

		local now = os.clock()
		local candidates = {}
		for _, t in ipairs(trees:GetChildren()) do
			if is_live(t) and not is_growing(t) and not (unreachable[t] and now < unreachable[t]) then
				local tp = t:GetPivot().Position
				if is_in_redwood(tp) then
					if tp.Y <= 22 and (t.Name:match("Redwood") or t.Name == "PacificMadrone") then
						local horizDist = math.sqrt((tp.X - myPos.X)^2 + (tp.Z - myPos.Z)^2)
						local yDiff = math.abs(tp.Y - myPos.Y)
						local spatialDist = horizDist + (yDiff > 4.5 and (yDiff * 4.0) or 0)
						local score, money, odds = top_score(t)
						local travelSec = spatialDist / math.max(levelSpeed, 16)
						local efficiency = score / (1 + travelSec * 0.15)
						table.insert(candidates, {tree = t, dist = horizDist, eff = efficiency, name = t.Name})
					end
				end
			end
		end
		if #candidates == 0 then return nil end
		table.sort(candidates, function(a, b) return a.eff > b.eff end)
		return candidates[1].tree, candidates[1]
	end

	local function start_leveling_loop()
		-- 1. Main Farming Loop
		task.spawn(function()
			startTime = os.clock()
			felledCount = 0
			table.clear(unreachable)
			update_stats()
			currentAbortFlag = false

			while S.levelingOn and alive() do
				local okLoop, errLoop = pcall(function()
					local myRoot = hrp()
					if not myRoot then
						levelStateLabel:Set("no char", "Warning")
						task.wait(0.5)
						return
					end

					if not is_in_redwood(myRoot.Position) then
						S.levelingOn = false
						if autoLevelingToggle then
							pcall(function() autoLevelingToggle:Set(false) end)
						end
						levelStateLabel:Set("outside redwood", "Error")
						levelTargetLabel:Set("Must be in Redwood Grove!")
						Window:Notify({
							Title = "Leveling Farm",
							Content = "Auto Leveling stopped: You are outside Redwood Grove! Teleport there first.",
							Duration = 4,
						})
						return
					end

					local target, info = get_best_redwood_tree()
					if not target then
						table.clear(unreachable)
						levelStateLabel:Set("scanning trees", "Warning")
						levelTargetLabel:Set("searching...")
						task.wait(1.5)
						return
					end

					local standPos, path = find_walkable_stand(target, myRoot.Position)
					if not (standPos and path) then
						unreachable[target] = os.clock() + 20
						levelStateLabel:Set("rerouting", "Warning")
						task.wait(0.2)
						return
					end

					levelTargetLabel:Set(tostring(info.name) .. " (" .. tostring(math.floor(info.dist)) .. "m)")
					levelStateLabel:Set("walking", "Warning")

					local reached, why = smart_walk_spatial(path, standPos, levelSpeed, 2.8, target)
					if not S.levelingOn or not alive() then return end

					if not reached then
						unreachable[target] = os.clock() + 20
						levelStateLabel:Set("path failed", "Warning")
						task.wait(0.2)
						return
					end

					if target.Parent and is_live(target) then
						levelStateLabel:Set("chopping", "Success")
						local felled, chopWhy = leveling_chop(target)
						if felled then
							felledCount += 1
							update_stats()
						else
							unreachable[target] = os.clock() + 15
						end
					end
				end)

				if not okLoop then
					warn("[Leveling] Loop error recovered:", errLoop)
					task.wait(0.5)
				end

				task.wait(0.2)
			end

			levelStateLabel:Set("idle", "Muted")
			levelTargetLabel:Set("-")
		end)

		-- 2. Dedicated Watchdog Failcheck System (Self-Healing Unstuck & Emergency Respawn)
		task.spawn(function()
			local stuckSecs = 0
			local lastPos = nil
			while S.levelingOn and alive() do
				task.wait(1.0)
				if not failcheckEnabled or not S.levelingOn then continue end

				local myRoot = hrp()
				local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
				if myRoot and hum then
					local curPos = myRoot.Position
					local isChopping = false
					pcall(function()
						local okCS, ChopState = pcall(function() return require(plr.PlayerScripts.Source.state.ChopState) end)
						if okCS and ChopState and ChopState.session() ~= nil then
							isChopping = true
						end
					end)

					if isChopping then
						stuckSecs = 0
						lastPos = curPos
					else
						local dMoved = lastPos and (curPos - lastPos).Magnitude or 10
						if dMoved < 1.8 then
							stuckSecs += 1
							-- Tier 1 (3s stuck): Jump and side-hop
							if stuckSecs == 3 then
								pcall(function() hum.Jump = true end)
								local sideVec = Vector3.new(-myRoot.CFrame.LookVector.Z, 0, root and root.CFrame.LookVector.X or 1) * 4.5
								hum:MoveTo(curPos + sideVec)
							-- Tier 2 (7s stuck): Diagonal back-step & jump to dislodge without noclip
							elseif stuckSecs == 7 then
								local bwdDiag = (-myRoot.CFrame.LookVector * 4.5) + (Vector3.new(-myRoot.CFrame.LookVector.Z, 0, myRoot.CFrame.LookVector.X) * 3.5)
								hum:MoveTo(curPos + bwdDiag)
								pcall(function() hum.Jump = true end)
								task.wait(0.2)
							-- Tier 3 (14s stuck): Force abort current path & switch target
							elseif stuckSecs == 14 then
								currentAbortFlag = true
								levelStateLabel:Set("rerouting (stuck)", "Warning")
							-- Tier 4 (25s stuck): EMERGENCY FAILCHECK RESPAWN TO REDWOOD GROVE
							elseif stuckSecs >= 25 then
								levelStateLabel:Set("respawn failcheck", "Warning")
								levelTargetLabel:Set("unsticking via respawn...")
								currentAbortFlag = true
								table.clear(unreachable)
								stuckSecs = 0
								WALK.respawnJump(REDWOOD_SPAWN)
								task.wait(1.0)
							end
						else
							stuckSecs = 0
							lastPos = curPos
						end
					end
				end
			end
		end)
	end

	autoLevelingToggle = gbLevelControls:CreateToggle({
		Name = "Auto Leveling (Redwood Only)",
		Flag = "AutoLevelingRedwood",
		CurrentValue = false,
		Callback = function(val)
			if val then
				local myRoot = hrp()
				if not myRoot or not is_in_redwood(myRoot.Position) then
					task.defer(function()
						if autoLevelingToggle then pcall(function() autoLevelingToggle:Set(false) end) end
					end)
					levelStateLabel:Set("outside redwood", "Error")
					levelTargetLabel:Set("Must be in Redwood Grove!")
					Window:Notify({
						Title = "Leveling Farm",
						Content = "Cannot start: You must be inside Redwood Grove!",
						Duration = 4,
					})
					return
				end
				S.levelingOn = true
				start_leveling_loop()
			else
				S.levelingOn = false
			end
		end,
	})

	gbLevelControls:CreateSlider({
		Name = "Walk Speed",
		Flag = "LevelingWalkSpeed",
		Range = {16, 24},
		Increment = 1,
		CurrentValue = 24,
		Callback = function(val)
			levelSpeed = math.clamp(tonumber(val) or 24, 16, 24)
		end,
	})

	gbLevelControls:CreateToggle({
		Name = "Stuck Failcheck (Respawn Unstick)",
		Flag = "LevelingFailcheck",
		CurrentValue = true,
		Callback = function(val)
			failcheckEnabled = val
		end,
	})

	gbLevelControls:CreateButton({
		Name = "Teleport to Redwood Grove",
		Callback = function()
			task.spawn(function()
				levelStateLabel:Set("teleporting...", "Warning")
				local ok, err = WALK.respawnJump(REDWOOD_SPAWN)
				if ok then
					levelStateLabel:Set("arrived at redwood", "Success")
					levelTargetLabel:Set("Ready to farm!")
				else
					levelStateLabel:Set("tp failed", "Error")
				end
			end)
		end,
	})

	gbLevelControls:CreateParagraph({
		Title = "Redwood Leveling Specs",
		Content = "Exclusively targets high-XP Redwood trees. Spatial Navigation with Whisker Radar, Context-Based Steering, Line-of-Sight String Pulling, Step-Up Auto Jump, Anti-Drowning, Watchdog Failcheck, and Elevation Awareness.",
	})
end
init_leveling_module()

local function init_quest_module()
	local gbQuestControls = questTab:CreateGroupbox({Name = "Quest Controls", Side = "Left"})
	local gbQuestStatus = questTab:CreateGroupbox({Name = "Status & Target", Side = "Right"})

	local DataController = nil
	pcall(function() DataController = Knit.GetController("DataController") end)
	local QuestConfig = nil
	pcall(function() QuestConfig = require(RS.Modules.QuestConfig) end)

	local qState = {
		running = false,
		autoAccept = true,
		autoHandIn = true,
		targetLine = "All",
		walkThreshold = 150,
		walkSpeed = 22,
	}

	local NPC_MAP = {
		OldJack = Vector3.new(-67, 27.25, -576),
		Linnea = Vector3.new(704, 24.3, -588),
		Coral = Vector3.new(78, 20.5, 142),
		Frost = Vector3.new(1385, 23.8, -604),
		Dale = Vector3.new(-536, 11.3, 357),
		Thorne = Vector3.new(-12, 12.8, -1220),
		Pip = Vector3.new(668, 17.3, -540),
		Hattie = Vector3.new(649, 8.0, -521),
		Walt = Vector3.new(-224, 6.9, -591),
		Wren = Vector3.new(-135, 15.2, -525),
		Seraphine = Vector3.new(-25, 78.6, -558),
		Enchanter = Vector3.new(-25, 78.6, -558),
		Thicket = Vector3.new(-26, 76.6, -553),
		TumbleweedTom = Vector3.new(-522, 11.3, 330),
		Gus = Vector3.new(-648, 12.5, 315),
		Ansel = Vector3.new(-42, 13.5, -1250),
		Iris = Vector3.new(35, 12.8, -1185),
		Halvard = Vector3.new(1340, 22.1, -650),
		Remy = Vector3.new(125, 18.2, 180),
		Marta = Vector3.new(90, 19.5, 120),
		OrchardKeeper = Vector3.new(-546, 18.5, -553),
		Merchant = Vector3.new(642.75, 6.14, -625.73),
		LumberMerchant = Vector3.new(-60.6, 28.1, -552.8),
		Sawmill = Vector3.new(-53.23, 26.58, -539.49),
	}

	local function get_npc_position(npcId)
		if not npcId then return nil, nil end
		local folder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("NPCs")
		if folder then
			for _, m in ipairs(folder:GetDescendants()) do
				if m:IsA("Model") and (m:GetAttribute("NpcId") == npcId or m.Name == npcId) then
					local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
					if root then return root.Position, m end
				end
			end
		end
		if NPC_MAP[npcId] then
			return NPC_MAP[npcId], nil
		end
		return nil, nil
	end

	-- UI Elements
	local stateLabel = gbQuestStatus:CreateStatus({Name = "State", Style = "Dot", Value = "idle"})
	local lineLabel = gbQuestStatus:CreateStatus({Name = "Line", Style = "Row", Value = "-"})
	local questLabel = gbQuestStatus:CreateStatus({Name = "Quest", Style = "Row", Value = "-"})
	local objLabel = gbQuestStatus:CreateLabel("-")
	local progLabel = gbQuestStatus:CreateStatus({Name = "Progress", Style = "Row", Value = "-"})
	local destLabel = gbQuestStatus:CreateLabel("-")
	local actionLabel = gbQuestStatus:CreateLabel("Ready")

	local function safe_set(item, val, optStyle)
		pcall(function() item:Set(val, optStyle) end)
	end

	local function smart_quest_walk(destPos, speed, stopDist)
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not (root and hum) then return false, "no character" end

		speed = math.clamp(tonumber(speed or qState.walkSpeed or 22) or 22, 16, 24)
		stopDist = stopDist or 5.0
		hum.WalkSpeed = speed
		hum.AutoRotate = true

		local pf = game:GetService("PathfindingService")
		local path = pf:CreatePath({
			AgentRadius = 2.4,
			AgentHeight = 5.0,
			AgentCanJump = true,
			AgentJumpHeight = 3.5,
			AgentMaxSlope = 45,
			WaypointSpacing = 4.0,
			Costs = { Water = math.huge }
		})

		local ok = pcall(function() path:ComputeAsync(root.Position, destPos) end)
		if not ok or path.Status ~= Enum.PathStatus.Success then
			local t0 = os.clock()
			while (root.Position - destPos).Magnitude > stopDist and (os.clock() - t0 < 8) and qState.running and alive() do
				hum.WalkSpeed = speed
				hum:MoveTo(destPos)
				task.wait(0.1)
			end
			return (root.Position - destPos).Magnitude <= (stopDist + 2)
		end

		local waypoints = path:GetWaypoints()
		if not waypoints or #waypoints == 0 then return false end

		local currIdx = 2
		local lastPos = root.Position
		local stallTime = 0
		local tStart = os.clock()
		local maxTime = math.max(12, (#waypoints * 0.45) + 6)

		while currIdx <= #waypoints and (os.clock() - tStart < maxTime) and qState.running and alive() do
			hum.WalkSpeed = speed
			local curPos = root.Position
			if (curPos - destPos).Magnitude <= stopDist then
				return true
			end

			if (curPos - lastPos).Magnitude < 0.4 then
				stallTime += 0.08
				if stallTime >= 0.8 and stallTime < 2.0 then
					pcall(function() hum.Jump = true end)
					local right = root.CFrame.RightVector
					hum:MoveTo(curPos + right * 4.0)
					task.wait(0.12)
				elseif stallTime >= 2.0 and stallTime < 4.5 then
					pcall(function() hum.Jump = true end)
					local bwd = (-root.CFrame.LookVector * 5.0) + (root.CFrame.RightVector * 3.5)
					hum:MoveTo(curPos + bwd)
					task.wait(0.18)
				elseif stallTime >= 4.5 and stallTime < 7.5 then
					pcall(function() hum.Jump = true end)
					hum:MoveTo(curPos - root.CFrame.LookVector * 6.0)
					task.wait(0.22)
				elseif stallTime >= 7.5 then
					safe_set(actionLabel, "Stuck detected! Unstick respawn...")
					WALK.respawnJump(destPos)
					return false, "watchdog respawn unstick"
				end
			else
				stallTime = 0
				lastPos = curPos
			end

			local wp = waypoints[currIdx]
			local wpPos = wp.Position
			local horizDist = math.sqrt((curPos.X - wpPos.X)^2 + (curPos.Z - wpPos.Z)^2)
			local yDiff = wpPos.Y - curPos.Y

			if yDiff > 1.2 and yDiff <= 4.0 then
				pcall(function() hum.Jump = true end)
			end

			hum:MoveTo(wpPos)
			if horizDist <= 3.2 then
				currIdx += 1
			end
			task.wait(0.04)
		end
		return (root.Position - destPos).Magnitude <= (stopDist + 2.5)
	end

	local function travel_to(destPos, stopDist)
		local root = hrp()
		if not root then return false end
		local dist = (destPos - root.Position).Magnitude
		local threshold = tonumber(qState.walkThreshold) or 150
		stopDist = stopDist or 5.0

		if dist > threshold then
			safe_set(stateLabel, "respawn tp", "Warning")
			safe_set(actionLabel, ("Respawn TP (%.0fm > %dm)..."):format(dist, threshold))
			local okTp = WALK.respawnJump(destPos)
			task.wait(0.5)
			root = hrp()
			if not root then return false end
		end

		local remainDist = (destPos - root.Position).Magnitude
		if remainDist > stopDist then
			safe_set(stateLabel, "walking", "Warning")
			safe_set(actionLabel, ("Walking legit (%.0fm @ %d)..."):format(remainDist, qState.walkSpeed))
			return smart_quest_walk(destPos, qState.walkSpeed, stopDist)
		end
		return true
	end

	local function find_quest_tree(obj)
		local folder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Trees")
		if not folder then return nil, 0 end
		local myRoot = hrp()
		local myPos = myRoot and myRoot.Position or Vector3.zero
		local bestTree, bestDist = nil, math.huge

		for _, t in ipairs(folder:GetChildren()) do
			if is_live(t) and not is_growing(t) then
				local matches = true
				if QuestConfig and QuestConfig.TreeInfo and QuestConfig.Matches then
					local okMatch, res = pcall(function()
						local info = QuestConfig.TreeInfo(t)
						return QuestConfig.Matches(obj, info)
					end)
					if okMatch then matches = res end
				else
					if obj.Species and t:GetAttribute("Species") ~= obj.Species and t.Name ~= obj.Species then
						matches = false
					end
					if obj.Biome and t:GetAttribute("Biome") ~= obj.Biome then
						matches = false
					end
				end
				if matches then
					local tp = t:GetPivot().Position
					local d = (tp - myPos).Magnitude
					if d < bestDist then
						bestDist = d
						bestTree = t
					end
				end
			end
		end
		return bestTree, bestDist
	end

	local function find_quest_spot(spotName)
		if not spotName then return nil end
		local folder = workspace:FindFirstChild("Map")
		if folder then
			for _, d in ipairs(folder:GetDescendants()) do
				if d.Name == spotName or d:GetAttribute("Spot") == spotName then
					local p = d:IsA("BasePart") and d.Position or (d:IsA("Model") and d:GetPivot().Position)
					if p then return p, d end
				end
			end
		end
		return nil, nil
	end

	local function try_accept_line(line)
		if not line then return false end
		local okCall = pcall(function()
			local res = QuestService:Accept(line.Id)
			if res and type(res) == "table" and res.await then res:await() end
		end)
		if not okCall then
			pcall(function()
				local rf = RS.Packages._Index["sleitnick_knit@1.4.7"].knit.Services.QuestService.RF:FindFirstChild("Accept")
				if rf then rf:InvokeServer(line.Id) end
			end)
		end
		return true
	end

	local function try_hand_in_line(line)
		if not line then return false end
		local okCall = pcall(function()
			local res = QuestService:HandIn(line.Id)
			if res and type(res) == "table" and res.await then res:await() end
		end)
		if not okCall then
			pcall(function()
				local rf = RS.Packages._Index["sleitnick_knit@1.4.7"].knit.Services.QuestService.RF:FindFirstChild("HandIn")
				if rf then rf:InvokeServer(line.Id) end
			end)
		end
		return true
	end

	local function start_quest_loop()
		task.spawn(function()
			while qState.running and alive() do
				local okLoop, errLoop = pcall(function()
					local myRoot = hrp()
					if not myRoot then
						safe_set(stateLabel, "no char", "Warning")
						task.wait(0.5)
						return
					end

					if not DataController then
						pcall(function() DataController = Knit.GetController("DataController") end)
					end
					if not QuestConfig then
						pcall(function() QuestConfig = require(RS.Modules.QuestConfig) end)
					end

					local data = nil
					pcall(function() data = DataController:GetCurrentPlayerData() end)
					if not data or type(data) ~= "table" or not data.Quests then
						safe_set(stateLabel, "no data", "Warning")
						safe_set(actionLabel, "Waiting for player data...")
						task.wait(1.0)
						return
					end

					local lines = QuestConfig and QuestConfig.Lines or {}
					local activeLine = nil
					local activeQuest = nil
					local isReadyToHandIn = false

					for _, line in ipairs(lines) do
						local matchFilter = (qState.targetLine == "All")
							or (qState.targetLine == line.Id)
							or (qState.targetLine == line.Name)
							or (line.Name and line.Name:find(qState.targetLine))

						if matchFilter then
							local lState = QuestConfig.LineState(data.Quests, line, data.Level)
							if lState == "Active" then
								local q = QuestConfig.ActiveQuest(data.Quests, line.Id)
								if q then
									local ready = QuestConfig.Ready(data, line.Id)
									if ready then
										activeLine = line
										activeQuest = q
										isReadyToHandIn = true
										break
									elseif not activeLine then
										activeLine = line
										activeQuest = q
										isReadyToHandIn = false
									end
								end
							end
						end
					end

					-- 1. If quest is READY to Hand In: Complete it!
					if activeLine and activeQuest and isReadyToHandIn then
						safe_set(lineLabel, tostring(activeLine.Name or activeLine.Id))
						safe_set(questLabel, tostring(activeQuest.Title or activeQuest.Id))
						safe_set(objLabel, "All objectives met! Hand in ready.")
						safe_set(progLabel, "100% (Ready)", "Success")

						if qState.autoHandIn then
							local targetNpc = QuestConfig.HandInNpc(activeQuest) or activeLine.Npc
							local npcPos = get_npc_position(targetNpc)
							if npcPos then
								safe_set(destLabel, ("NPC: %s"):format(tostring(targetNpc)))
								safe_set(actionLabel, ("Traveling to %s to complete..."):format(tostring(targetNpc)))
								local arrived = travel_to(npcPos, 8.0)
								if arrived then
									safe_set(stateLabel, "handing in", "Success")
									safe_set(actionLabel, ("Completing %s..."):format(tostring(activeQuest.Title)))
									task.wait(0.4)
									try_hand_in_line(activeLine)
									task.wait(0.8)
									safe_set(stateLabel, "complete", "Success")
									safe_set(actionLabel, ("Claimed: %s"):format(tostring(activeQuest.Title)))
									Window:Notify({
										Title = "Quest Completed!",
										Content = ("Turned in: %s"):format(tostring(activeQuest.Title)),
										Duration = 4,
									})
								end
							end
						else
							safe_set(stateLabel, "ready hand in", "Success")
							safe_set(actionLabel, "Auto Hand In is off. Ready to turn in.")
						end
						task.wait(1.0)
						return
					end

					-- 2. If active quest in progress: Work on undone objectives!
					if activeLine and activeQuest and not isReadyToHandIn then
						safe_set(lineLabel, tostring(activeLine.Name or activeLine.Id))
						safe_set(questLabel, tostring(activeQuest.Title or activeQuest.Id))

						local objs = activeQuest.Objectives or {}
						local progList = QuestConfig.Progress(data, activeLine.Id) or {}
						local targetObj = nil
						local targetObjIdx = 1

						for idx, obj in ipairs(objs) do
							local needed = QuestConfig.Needed and QuestConfig.Needed(obj) or (tonumber(obj.Count) or 1)
							local current = tonumber(progList[idx]) or 0
							if current < needed then
								targetObj = obj
								targetObjIdx = idx
								safe_set(objLabel, tostring(obj.Text or "In progress"))
								safe_set(progLabel, ("%d / %d"):format(current, needed), "Warning")
								break
							end
						end

						if not targetObj and #objs > 0 then
							targetObj = objs[1]
							safe_set(objLabel, tostring(targetObj.Text or "In progress"))
							safe_set(progLabel, "Working...", "Warning")
						end

						if targetObj then
							local ev = targetObj.Event
							if ev == "Fell" then
								local tree, dist = find_quest_tree(targetObj)
								if tree then
									safe_set(destLabel, ("Tree: %s (%.0fm)"):format(tree.Name, dist))
									safe_set(actionLabel, ("Moving to tree (%.0fm)..."):format(dist))
									local tp = tree:GetPivot().Position
									local arrived = travel_to(tp, 12.0)
									if arrived and qState.running and alive() then
										safe_set(stateLabel, "chopping", "Warning")
										safe_set(actionLabel, ("Chopping %s..."):format(tree.Name))
										chop_tree(tree)
									end
								else
									safe_set(destLabel, "Searching trees...")
									safe_set(actionLabel, "No matching tree found nearby. Waiting...")
									task.wait(2.0)
								end
							elseif ev == "Saw" then
								local char = plr.Character
								local carried = char and char:FindFirstChild("CarriedTree")
								local sawbladePos = Vector3.new(-53.23, 26.58, -539.49)
								local prompt = nil
								local folder = workspace:FindFirstChild("Map")
								if folder then
									for _, m in ipairs(folder:GetDescendants()) do
										if m:IsA("Model") and m.Name == "Sawblade" then
											local pp = m:FindFirstChildWhichIsA("ProximityPrompt", true)
											local bp = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
											if bp then
												sawbladePos = bp.Position
												prompt = pp
												break
											end
										end
									end
								end

								if not carried then
									safe_set(destLabel, "Tree (for Sawmill)")
									safe_set(actionLabel, "Chopping tree to bring to Sawmill...")
									local tree, dist = find_quest_tree(targetObj)
									if tree then
										local tp = tree:GetPivot().Position
										local arrived = travel_to(tp, 12.0)
										if arrived and qState.running and alive() then
											safe_set(stateLabel, "chopping", "Warning")
											safe_set(actionLabel, ("Chopping %s..."):format(tree.Name))
											chop_tree(tree)
											task.wait(0.4)
											safe_set(actionLabel, "Picking up felled tree...")
											pcall(function()
												local CarryService = Knit.GetService("CarryService")
												CarryService:Hold(tree)
											end)
											pcall(function()
												local CarryController = Knit.GetController("CarryController")
												if CarryController and CarryController.Toggle then CarryController:Toggle() end
											end)
											task.wait(0.5)
										end
									else
										safe_set(actionLabel, "Waiting for tree to spawn for sawmill...")
										task.wait(2.0)
									end
								else
									safe_set(destLabel, "Sawblade")
									safe_set(actionLabel, "Carrying tree to Sawblade...")
									local arrived = travel_to(sawbladePos, 6.0)
									if arrived and qState.running and alive() then
										safe_set(stateLabel, "sawing", "Warning")
										safe_set(actionLabel, "Operating Sawmill...")
										task.wait(0.3)
										if prompt and fireproximityprompt then
											pcall(function() fireproximityprompt(prompt) end)
										end
										pcall(function()
											local SawmillController = Knit.GetController("SawmillController")
											if SawmillController and SawmillController._saw then
												local mill = prompt and prompt:FindFirstAncestorOfClass("Model")
												SawmillController:_saw(mill)
											end
										end)
										task.wait(0.6)
										pcall(function()
											local SawmillController = Knit.GetController("SawmillController")
											if SawmillController and SawmillController.Finish then
												local mill = prompt and prompt:FindFirstAncestorOfClass("Model")
												SawmillController:Finish(mill, 1.0)
											end
										end)
										pcall(function()
											local SawmillService = Knit.GetService("SawmillService")
											if SawmillService then
												local res = SawmillService:FinishSaw("OakIsland", 1.0)
												if res and res.await then res:await() end
											end
										end)
										task.wait(1.2)
										local pickupPrompt = prompt and prompt.Parent and prompt.Parent.Parent and prompt.Parent.Parent:FindFirstChild("PickupPrompt", true)
										if pickupPrompt and pickupPrompt.Enabled and fireproximityprompt then
											pcall(function() fireproximityprompt(pickupPrompt) end)
										end
										safe_set(actionLabel, "Tree sawed into planks successfully!")
										task.wait(0.5)
									end
								end
							elseif ev == "Sell" or ev == "Haggle" then
								safe_set(destLabel, "Lumber Merchant")
								safe_set(actionLabel, "Moving to Merchant to sell / haggle...")
								local merchPos = NPC_MAP.LumberMerchant
								local arrived = travel_to(merchPos, 8.0)
								if arrived then
									safe_set(stateLabel, "selling", "Warning")
									safe_set(actionLabel, "Haggling & selling lumber...")
									task.wait(0.3)
									pcall(function()
										local LumberMillService = Knit.GetService("LumberMillService")
										local res = LumberMillService:Haggle()
										if res and res.await then res:await() end
									end)
									task.wait(0.4)
									auto_sell_pass()
									task.wait(1.0)
								end
							elseif targetObj.Spot then
								local spotPos, spotPart = find_quest_spot(targetObj.Spot)
								if spotPos then
									safe_set(destLabel, ("Spot: %s"):format(targetObj.Spot))
									safe_set(actionLabel, ("Moving to spot: %s..."):format(targetObj.Spot))
									local arrived = travel_to(spotPos, 6.0)
									if arrived then
										safe_set(stateLabel, "picking", "Warning")
										safe_set(actionLabel, ("Collecting %s..."):format(targetObj.Spot))
										pcall(function() QuestSpotService:Pick(targetObj.Spot) end)
										task.wait(1.0)
									end
								else
									safe_set(destLabel, ("Spot: %s (unknown)"):format(targetObj.Spot))
									safe_set(actionLabel, "Searching for quest spot...")
									task.wait(2.0)
								end
							elseif targetObj.Talk or targetObj.HandIn then
								local talkNpc = targetObj.HandIn or activeLine.Npc
								local npcPos = get_npc_position(talkNpc)
								if npcPos then
									safe_set(destLabel, ("Talk to: %s"):format(tostring(talkNpc)))
									safe_set(actionLabel, ("Moving to %s to talk..."):format(tostring(talkNpc)))
									local arrived = travel_to(npcPos, 8.0)
									if arrived then
										safe_set(stateLabel, "talking", "Warning")
										safe_set(actionLabel, ("Talking to %s..."):format(tostring(talkNpc)))
										pcall(function() QuestService:Ask(activeLine.Id, 1) end)
										task.wait(1.0)
									end
								end
							else
								safe_set(actionLabel, "Objective in progress...")
								task.wait(1.5)
							end
						end
						task.wait(0.5)
						return
					end

					-- 3. If no active quest: Check for available questlines to accept!
					if qState.autoAccept then
						local foundAvailable = nil
						for _, line in ipairs(lines) do
							local matchFilter = (qState.targetLine == "All")
								or (qState.targetLine == line.Id)
								or (qState.targetLine == line.Name)
								or (line.Name and line.Name:find(qState.targetLine))

							if matchFilter then
								local lState = QuestConfig.LineState(data.Quests, line, data.Level)
								if lState == "Available" then
									foundAvailable = line
									break
								end
							end
						end

						if foundAvailable then
							safe_set(lineLabel, tostring(foundAvailable.Name or foundAvailable.Id))
							safe_set(questLabel, "Available to accept")
							safe_set(objLabel, "Accepting questline...")
							safe_set(progLabel, "Not started", "Warning")
							safe_set(stateLabel, "accepting", "Warning")
							safe_set(actionLabel, ("Accepting: %s..."):format(tostring(foundAvailable.Name)))

							local npcPos = get_npc_position(foundAvailable.Npc)
							if npcPos then
								safe_set(destLabel, ("NPC: %s"):format(tostring(foundAvailable.Npc)))
								local dist = (npcPos - myRoot.Position).Magnitude
								if dist > 20 then
									travel_to(npcPos, 10.0)
								end
							end
							task.wait(0.4)
							try_accept_line(foundAvailable)
							task.wait(1.0)
							safe_set(actionLabel, ("Accepted %s!"):format(tostring(foundAvailable.Name)))
							return
						end
					end

					safe_set(stateLabel, "idle")
					safe_set(actionLabel, "No quests available or target lines completed.")
					task.wait(2.0)
				end)

				if not okLoop then
					safe_set(stateLabel, "error", "Error")
					safe_set(actionLabel, ("Loop err: %s"):format(tostring(errLoop):sub(1, 28)))
					task.wait(1.5)
				end
			end
			safe_set(stateLabel, "idle")
			safe_set(actionLabel, "Auto Quest stopped.")
		end)
	end

	-- UI Controls
	local autoQuestToggle
	autoQuestToggle = gbQuestControls:CreateToggle({
		Name = "Auto Quest",
		Flag = "AutoQuest",
		CurrentValue = false,
		Callback = function(on)
			qState.running = on
			if on then
				safe_set(stateLabel, "running", "Success")
				safe_set(actionLabel, "Starting quest engine...")
				start_quest_loop()
			else
				safe_set(stateLabel, "idle")
				safe_set(actionLabel, "Auto Quest stopped.")
			end
		end,
	})

	gbQuestControls:CreateToggle({
		Name = "Auto Accept Available Quests",
		Flag = "QuestAutoAccept",
		CurrentValue = true,
		Callback = function(on)
			qState.autoAccept = on
		end,
	})

	gbQuestControls:CreateToggle({
		Name = "Auto Complete / Hand In",
		Flag = "QuestAutoHandIn",
		CurrentValue = true,
		Callback = function(on)
			qState.autoHandIn = on
		end,
	})

	gbQuestControls:CreateDropdown({
		Name = "Target Questline",
		Flag = "QuestTargetLine",
		Options = {
			"All",
			"Old Jack",
			"Linnea",
			"Coral",
			"Frost",
			"Dale",
			"Thorne",
			"Pip",
			"Thicket",
			"Wanderer",
		},
		CurrentOption = {"All"},
		Callback = function(sel)
			local chosen = type(sel) == "table" and sel[1] or sel
			qState.targetLine = chosen or "All"
		end,
	})

	gbQuestControls:CreateSlider({
		Name = "Walk vs Respawn Distance",
		Range = {50, 400},
		Increment = 10,
		CurrentValue = 150,
		Suffix = " studs",
		Flag = "QuestWalkThreshold",
		Callback = function(n)
			qState.walkThreshold = tonumber(n) or 150
		end,
	})

	gbQuestControls:CreateSlider({
		Name = "Walk Speed",
		Range = {16, 24},
		Increment = 1,
		CurrentValue = 22,
		Suffix = " studs/s",
		Flag = "QuestWalkSpeed",
		Callback = function(n)
			qState.walkSpeed = math.clamp(tonumber(n) or 22, 16, 24)
		end,
	})

	gbQuestControls:CreateButton({
		Name = "Complete / Hand In Active Quest Now",
		Callback = function()
			task.spawn(function()
				if not DataController then pcall(function() DataController = Knit.GetController("DataController") end) end
				if not QuestConfig then pcall(function() QuestConfig = require(RS.Modules.QuestConfig) end) end
				local data = nil
				pcall(function() data = DataController:GetCurrentPlayerData() end)
				if not data or not data.Quests then
					Window:Notify({Title = "Hand In", Content = "Cannot read quest data!", Duration = 3})
					return
				end
				for _, line in ipairs(QuestConfig.Lines or {}) do
					if QuestConfig.Ready(data, line.Id) then
						local q = QuestConfig.ActiveQuest(data.Quests, line.Id)
						local targetNpc = QuestConfig.HandInNpc(q) or line.Npc
						local npcPos = get_npc_position(targetNpc)
						if npcPos then
							travel_to(npcPos, 8.0)
						end
						task.wait(0.4)
						try_hand_in_line(line)
						Window:Notify({Title = "Quest Completed!", Content = "Turned in: " .. tostring(q and q.Title or line.Id), Duration = 4})
						return
					end
				end
				Window:Notify({Title = "Hand In", Content = "No quests ready to hand in.", Duration = 3})
			end)
		end,
	})

	gbQuestControls:CreateButton({
		Name = "Accept Available Quests Now",
		Callback = function()
			task.spawn(function()
				if not DataController then pcall(function() DataController = Knit.GetController("DataController") end) end
				if not QuestConfig then pcall(function() QuestConfig = require(RS.Modules.QuestConfig) end) end
				local data = nil
				pcall(function() data = DataController:GetCurrentPlayerData() end)
				if not data or not data.Quests then return end
				local count = 0
				for _, line in ipairs(QuestConfig.Lines or {}) do
					if QuestConfig.LineState(data.Quests, line, data.Level) == "Available" then
						try_accept_line(line)
						count += 1
					end
				end
				Window:Notify({Title = "Accept Quests", Content = ("Accepted %d available quest(s)."):format(count), Duration = 3})
			end)
		end,
	})

	gbQuestControls:CreateParagraph({
		Title = "Smart Hybrid Movement",
		Content = "Jarak dekat (<= threshold) ditempuh dengan jalan kaki normal legit tanpa noclip agar aman dari kick anticheat. Jarak jauh (> threshold) ditempuh instan via Respawn TP langsung ke target.",
	})
end
init_quest_module()

local function init_teleport_module()
	local gbTeleportArea = teleportTab:CreateGroupbox({Name = "Islands & Areas", Side = "Left"})
	local gbTeleportNPC = teleportTab:CreateGroupbox({Name = "NPCs & Merchants", Side = "Right"})

	local TELEPORT_AREAS = {
		{name = "Oak Island (Spawn)", folder = "OakIsland", pos = Vector3.new(-98, 24, -558)},
		{name = "Birch Island", folder = "BirchIsland", pos = Vector3.new(645, 4, -591)},
		{name = "Crescent Island", folder = "CrescentIsland", pos = Vector3.new(182, 9, -44)},
		{name = "Snowy Pines", folder = "SnowyPines", pos = Vector3.new(1241, 10, -580)},
		{name = "Dusty Mesa", folder = "DustyMesa", pos = Vector3.new(-541, 8, 310)},
		{name = "Redwood Grove", folder = "RedwoodGrove", pos = Vector3.new(2, 5, -1051)},
		{name = "Orchard Island", folder = "OrchardIsland", pos = Vector3.new(-560, 15, -541)},
		{name = "Merchant Camp", folder = "MerchantCamp", pos = Vector3.new(207, 4, -126)},
	}

	local function get_area_pos(areaName)
		local map = workspace:FindFirstChild("Map")
		for _, a in ipairs(TELEPORT_AREAS) do
			if a.name == areaName then
				if map then
					local f = map:FindFirstChild(a.folder)
					if f then
						local tp = f:FindFirstChild("TeleportPoint")
						if tp and tp:IsA("BasePart") then
							return tp.Position
						elseif f:IsA("Model") then
							local ok, p = pcall(function() return f:GetPivot().Position end)
							if ok and p then return p end
						end
					end
				end
				return a.pos
			end
		end
		return nil
	end

	local AREA_OPTIONS = {}
	for _, a in ipairs(TELEPORT_AREAS) do
		table.insert(AREA_OPTIONS, a.name)
	end

	local selectedArea = AREA_OPTIONS[1]
	local areaStatusLabel = gbTeleportArea:CreateLabel("status: idle")

	gbTeleportArea:CreateDropdown({
		Name = "Select Destination",
		Flag = "TeleportDestination",
		Options = AREA_OPTIONS,
		CurrentOption = selectedArea,
		Callback = function(sel)
			selectedArea = sel
		end,
	})

	gbTeleportArea:CreateButton({
		Name = "Teleport to Area",
		Callback = function()
			task.spawn(function()
				local destPos = get_area_pos(selectedArea)
				if not destPos then
					areaStatusLabel:Set("status: area not found")
					return
				end
				areaStatusLabel:Set("status: teleporting to " .. tostring(selectedArea) .. "…")
				local ok, err = WALK.respawnJump(destPos)
				if ok then
					areaStatusLabel:Set("status: arrived at " .. tostring(selectedArea))
				else
					areaStatusLabel:Set("status: tp failed (" .. tostring(err or "err") .. ")")
				end
			end)
		end,
	})

	local mikuLabel = gbTeleportNPC:CreateLabel("miku: not scanned yet")

	local function find_miku()
		local map = workspace:FindFirstChild("Map")
		local npcs = map and map:FindFirstChild("NPCs")
		if npcs then
			local m = npcs:FindFirstChild("Merchant")
			if m and m:IsA("Model") then
				local root = m:FindFirstChild("HumanoidRootPart")
				if root then return root.Position, "Miku (travelling merchant)" end
				local ok, pos = pcall(function() return m:GetPivot().Position end)
				if ok and pos then return pos, "Miku (travelling merchant)" end
			end
		end
		local wanderer = map and map:FindFirstChild("Wanderer")
		if wanderer and wanderer:IsA("Model") then
			local root = wanderer:FindFirstChild("HumanoidRootPart")
			if root then return root.Position, "Wanderer" end
			local ok, pos = pcall(function() return wanderer:GetPivot().Position end)
			if ok and pos then return pos, "Wanderer" end
		end
		for _, p in ipairs(game.Players:GetPlayers()) do
			if p ~= plr and (string.lower(p.Name):match("miku") or string.lower(p.DisplayName):match("miku")) then
				local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if root then return root.Position, "player " .. p.Name end
			end
		end
		return nil, nil
	end

	gbTeleportNPC:CreateButton({
		Name = "Scan Miku",
		Callback = function()
			local pos, who = find_miku()
			if not pos then
				mikuLabel:Set("miku: not spawned (try again later)")
			else
				mikuLabel:Set("miku: found -> " .. tostring(who))
			end
		end,
	})

	gbTeleportNPC:CreateButton({
		Name = "TP to Miku",
		Callback = function()
			task.spawn(function()
				local pos, who = find_miku()
				if not pos then
					mikuLabel:Set("miku: not spawned (try again later)")
					return
				end
				mikuLabel:Set("miku: teleporting…")
				local ok, err = WALK.respawnJump(pos)
				mikuLabel:Set(ok and ("miku: tp -> " .. who) or ("miku: tp failed (" .. tostring(err or "err") .. ")"))
			end)
		end,
	})
end
init_teleport_module()

gbAxes:CreateParagraph({
	Title = "How buying works",
	Content = "The server rejects purchases unless you are standing at the shop, so auto buy travels to the axe's island stall first.",
})

RunService.RenderStepped:Connect(function()
	if noclipOn and alive() then
		noclip_pass()
	end
end)

plr.CharacterAdded:Connect(function()
	if S.farm and alive() then
		task.wait(0.4)
		noclipOn = false
		restore_collide()
		equip_axe()
	end
	if S.hideIngameName then
		task.delay(0.5, function()
			if S.hideIngameName and S.set_hide_ingame_name then
				S.set_hide_ingame_name(true)
			end
		end)
	end
end)

task.spawn(function()
	while alive() do
		task.wait(2)
		pcall(refresh_axe_info)
	end
end)

getgenv().ForestFarm = {
	start = function(mode)
		if mode then
			for i, m in ipairs(MODES) do
				if m == mode then modeIndex = i end
			end
		end
		set_farm(true)
	end,
	stop = function()
		set_farm(false)
		task.spawn(function()
			local char = plr.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				pcall(function()
					root.Anchored = false
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
				end)
			end
		end)
	end,
	buy = function(id)
		for _, axe in ipairs(ladder) do
			if axe.id == id then return buy_axe(axe) end
		end
		return false, "unknown axe " .. tostring(id)
	end,
	ladder = function() return ladder end,
	state = function()
		return {farm = S.farm, autobuy = S.autobuy, felled = stats.felled,
			failed = stats.failed, rate = rate(), mode = MODES[modeIndex], bucks = bucks()}
	end,
	sell = function() return auto_sell_pass() end,
	quote = function()
		local q = call(LumberMillService, "Quote")
		if type(q) == "table" then
			return {count = q.Count, worth = q.Worth, total = q.Total}
		end
		return nil
	end,
}

refresh_state()
refresh_axe_info()
refresh_ladder()

local function fmt_odds(n)
	if n >= 1e6 then return ("1/%.1fm"):format(n / 1e6) end
	if n >= 1e3 then return ("1/%.0fk"):format(n / 1e3) end
	return ("1/%d"):format(math.floor(n + 0.5))
end

local function top_wood_row_text(t, dist)
	local wood = t:GetAttribute("Wood") or t:GetAttribute("Species") or t.Name
	local rarity = tostring(t:GetAttribute("Rarity") or "?")
	local money = tree_value(t, S.perfectOn)
	local odds = tree_odds(t)
	local size = t:GetAttribute("Size")
	local sizeTxt = (size and size ~= "" and size ~= "Normal") and ("  " .. tostring(size)) or ""
	local names = mutation_names(t)
	local mutTxt = #names > 0 and ("  +" .. table.concat(names, "+")) or ""
	local d = dist and ("  %dm"):format(dist) or ""
	local growing = is_growing(t)
	local status = growing and ("  ⏳ Growing %s"):format(fmt_remaining(grow_remaining(t))) or ""
	return ("%s · %s · %s · %s%s%s%s%s"):format(
		rarity, fmt_val(money), wood, fmt_odds(odds), sizeTxt, mutTxt, status, d)
end

local function visible_top_rows()
	local n = math.floor(tonumber(S.maxRows) or 8)
	return math.clamp(n, 1, MAX_TOP_ROWS)
end

local lastTopLabelText = nil

local rowState = {}

local function rank_key(t)
	if S.topSort == "Odds" then
		return math.floor(tree_odds(t) * 20) / 20
	elseif S.topSort == "Rarity" then
		return tier_of(t:GetAttribute("Rarity")) * 1000 + math.floor(tree_value(t, S.perfectOn) / 50)
	end
	return math.floor(top_score(t) * 100) / 100
end

local function tree_sort_id(t)
	return tonumber(t:GetAttribute("TreeId")) or 0
end

local RANK_EPSILON = 0.02
local lastOrder = {}
local lastGoodList = nil

local function apply_hysteresis(sorted)
	local out = {}
	local used = {}
	for pos, id in ipairs(lastOrder) do
		if pos > #sorted then break end
		local inc = nil
		for _, t in ipairs(sorted) do
			if not used[t] and tree_sort_id(t) == id then inc = t break end
		end
		if not inc then continue end
		local challenger = nil
		for _, t in ipairs(sorted) do
			if not used[t] and tree_sort_id(t) ~= id then challenger = t break end
		end
		if challenger and (rank_key(challenger) - rank_key(inc)) > RANK_EPSILON then
			out[pos] = challenger
			used[challenger] = true
		else
			out[pos] = inc
			used[inc] = true
		end
	end
	for _, t in ipairs(sorted) do
		if not used[t] then
			out[#out+1] = t
			used[t] = true
		end
	end
	lastOrder = {}
	for _, t in ipairs(out) do lastOrder[#lastOrder+1] = tree_sort_id(t) end
	return out
end

task.spawn(function()
	local myToken = S.token
	while alive() and S.token == myToken do
		local rows = getgenv().__TopRowsV2
		local folder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Trees")
		if rows and folder then
			local myRoot = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			local minValue = tonumber(S.minValue) or 0
			local list = {}
			for _, t in ipairs(folder:GetChildren()) do
				if t:IsA("Model") and t:FindFirstChild("Trunk") and is_candidate(t) and passes_rarity(t) then
					local v = tree_value(t, S.perfectOn)
					if v >= minValue and v >= 1 then
						list[#list+1] = t
					end
				end
			end
			table.sort(list, function(a, b)
				local ka, kb = rank_key(a), rank_key(b)
				if ka ~= kb then return ka > kb end
				return tree_sort_id(a) < tree_sort_id(b)
			end)
			list = apply_hysteresis(list)
			if #list > 0 then
				lastGoodList = list
			elseif lastGoodList and #lastGoodList > 0 then
				list = lastGoodList
			end
			local want = visible_top_rows()
			for i = 1, MAX_TOP_ROWS do
				local row = rows[i]
				if not row then break end
				local st = rowState[i]
				if not st then
					st = {tree = nil, text = nil, visible = nil, disabled = nil}
					rowState[i] = st
				end
				local t = i <= want and list[i] or nil
				local show = i <= want
				if st.visible ~= show then
					pcall(function() row.button:SetVisible(show) end)
					st.visible = show
				end
				row.tree = t
				if t then
					local d
					if myRoot and t:FindFirstChild("Trunk") then
						d = math.floor((t.Trunk.Position - myRoot.Position).Magnitude / 10) * 10
					end
					local text = top_wood_row_text(t, d)
					if st.text ~= text then
						pcall(function() row.button:SetText(text) end)
						st.text = text
					end
					local dis = is_growing(t)
					if st.disabled ~= dis then
						pcall(function() row.button:SetDisabled(dis) end)
						st.disabled = dis
					end
					st.tree = t
				else
					if st.text ~= "—" then
						pcall(function() row.button:SetText("—") end)
						st.text = "—"
					end
					if st.disabled ~= true then
						pcall(function() row.button:SetDisabled(true) end)
						st.disabled = true
					end
					st.tree = nil
				end
			end
			if topLabel then
				local mode = (S.topSort == "Odds" and "by odds") or (S.topSort == "Rarity" and "by rarity") or "by value"
				local growing = 0
				for _, t in ipairs(list) do if is_growing(t) then growing += 1 end end
				local growTxt = growing > 0 and (" · %d growing"):format(growing) or ""
				local txt = ("%d shown · %d live%s · %s · %.1fs"):format(
					math.min(want, #list), #list, growTxt, mode, tonumber(S.refreshRate) or 10)
				if lastTopLabelText ~= txt then
					lastTopLabelText = txt
					safe_set(topLabel, txt)
				end
			end
		end
		task.wait(math.clamp(tonumber(S.refreshRate) or 10, 0.25, 20))
	end
end)

pcall(function()
	settingsTab:CreateConfigManager({Name = "Configs", Side = "Left"})
end)
pcall(function()
	settingsTab:CreateThemeManager({Name = "Themes", Side = "Right"})
end)
pcall(function()
	local gbControls = settingsTab:CreateGroupbox({Name = "Hub Controls", Side = "Left"})
	gbControls:CreateLabel("Toggle UI: RightShift")
	gbControls:CreateToggle({
		Name = "Hide In-Game Name",
		Flag = "HideIngameName",
		Default = (S.hideIngameName ~= false),
		Callback = function(val)
			if S.set_hide_ingame_name then
				S.set_hide_ingame_name(val)
			end
		end,
	})
	gbControls:CreateButton({
		Name = "Unload Hub",
		Callback = function()
			pcall(function()
				if ForestFarm and ForestFarm.stop then ForestFarm.stop() end
				if S.set_hide_ingame_name then S.set_hide_ingame_name(false) end
				Window:Destroy()
			end)
		end,
	})
end)

local function sync_state_from_flags()
	local F = Airflow.Flags
	if type(F) ~= "table" or not next(F) then
		F = getgenv().__Airflow and getgenv().__Airflow.Flags
	end
	if type(F) ~= "table" then return end
	local function val(flag)
		local f = F[flag]
		if not f then return nil end
		if type(f.Get) == "function" then
			local ok, v = pcall(function() return f.Get() end)
			if ok and v ~= nil then return v end
		end
		if type(f.GetOptions) == "function" then
			local okO, opts = pcall(function() return f.GetOptions(f) end)
			if okO and type(opts) == "table" then
				local scan = {}
				for k, v in pairs(f) do
					if type(v) == "string" then scan[v] = true end
				end
				for _, o in ipairs(opts) do
					if scan[tostring(o)] then return tostring(o) end
				end
				for k, v in pairs(f) do
					local n = tonumber(v)
					if n and opts[math.floor(n)] and type(k) == "string" and k:match("[Ii]ndex") then
						return tostring(opts[math.floor(n)])
					end
				end
			end
		end
		return nil
	end
	local v = val("MinRarity")
	if type(v) == "string" then
		S.minTier = (v == "Any") and 0 or (RARITY_TIER[v] or 0)
	elseif type(v) == "table" and v[1] then
		S.minTier = (v[1] == "Any") and 0 or (RARITY_TIER[v[1]] or 0)
	end
	v = val("TargetMode")
	if type(v) == "string" then
		for i, m in ipairs(MODES) do if m == v then modeIndex = i end end
	elseif type(v) == "table" and v[1] then
		for i, m in ipairs(MODES) do if m == v[1] then modeIndex = i end end
	end
	v = val("MinValue")
	if tonumber(v) then S.minValue = tonumber(v) end
	v = val("TopSort")
	if type(v) == "string" then
		S.topSort = (v == "Rarity" or v == "Odds") and v or "Money"
	elseif type(v) == "table" and v[1] then
		S.topSort = (v[1] == "Rarity" or v[1] == "Odds") and v[1] or "Money"
	end
	v = val("TopRows")
	if tonumber(v) then S.maxRows = tonumber(v) end
	v = val("WeightValue")
	if tonumber(v) then S.weightValue = tonumber(v) / 100 end
	v = val("RefreshRate")
	if tonumber(v) then S.refreshRate = tonumber(v) end
	v = val("IncludeGrowing")
	if type(v) == "boolean" then S.includeGrowing = v end
	v = val("SameIslandOnly")
	if type(v) == "boolean" then S.sameIslandOnly = v end
	v = val("MovementMethod")
	if type(v) == "string" then
		S.moveMode = (v == "Bike TP (WIP)") and "bike" or "respawn"
	elseif type(v) == "table" and v[1] then
		S.moveMode = (v[1] == "Bike TP (WIP)") and "bike" or "respawn"
	end
	v = val("FpsBoost")
	if type(v) == "boolean" and v ~= VISUAL.fpsBoost then VISUAL.setFpsBoost(v) end
	v = val("UltraFps")
	if type(v) == "boolean" and v ~= VISUAL.ultraFps then VISUAL.setUltraFps(v) end
	v = val("SuperUltraFps")
	if type(v) == "boolean" and v ~= VISUAL.superUltraFps then VISUAL.setSuperUltraFps(v) end
	local e = S.esp
	v = val("EspMaxDist")
	if tonumber(v) then e.maxDist = tonumber(v) end
	v = val("EspMaxTags")
	if tonumber(v) then e.maxTags = tonumber(v) end
	v = val("EspTextSize")
	if tonumber(v) then e.textSize = tonumber(v) end
	v = val("EspValueColor")
	if type(v) == "string" then
		e.valueColor = (v == "Rarity") and "Rarity" or "Bands"
	elseif type(v) == "table" and v[1] then
		e.valueColor = (v[1] == "Rarity") and "Rarity" or "Bands"
	end
	v = val("EspRarity")
	if type(v) == "boolean" then e.showRarity = v end
	v = val("EspMutations")
	if type(v) == "boolean" then e.showMutations = v end
	v = val("EspDist")
	if type(v) == "boolean" then e.showDist = v end
	v = val("EspHideUnfellable")
	if type(v) == "boolean" then e.hideUnfellable = v end
	v = val("EspPlayers")
	if type(v) == "boolean" and v ~= e.players then esp_apply("players", v) end
	v = val("EspTrees")
	if type(v) == "boolean" and v ~= e.trees then esp_apply("trees", v) end
	v = val("EspMerchants")
	if type(v) == "boolean" and v ~= e.merchants then esp_apply("merchants", v) end
	v = val("HideIngameName")
	if type(v) == "boolean" and v ~= S.hideIngameName and S.set_hide_ingame_name then
		S.set_hide_ingame_name(v)
	end
end

pcall(function()
	Window:OnConfigChanged(function()
		pcall(sync_state_from_flags)
	end)
end)

pcall(function() Window:LoadAutoload() end)
pcall(sync_state_from_flags)
if S.hideIngameName and S.set_hide_ingame_name then
	pcall(function() S.set_hide_ingame_name(true) end)
end

pcall(function()
	Window:Notify({Title = "Blizzard", Content = "Farm hub ready", Duration = 4})
end)
print("[Blizzard] loaded")