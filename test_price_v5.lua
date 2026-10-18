-- v5: spy every payload on the Knit TreeService remote during a chop
local plr = game:GetService("Players").LocalPlayer
local RS = game:GetService("ReplicatedStorage")
local Knit = require(RS.Packages.Knit)
pcall(function() Knit.Start() end)
local TreeService = Knit.GetService("TreeService")
local T = {}
getgenv().__PT5 = T
local function log(k, v) T[k] = v end

-- locate the service remote (name == "TreeService", any class with OnClientEvent)
local remote
local function hunt(parent, depth)
	if remote or depth > 6 then return end
	for _, c in ipairs(parent:GetChildren()) do
		if c.Name == "TreeService" and type(c.OnClientEvent) == "RBXScriptSignal" then
			remote = c
			return
		end
		if c ~= game then hunt(c, depth + 1) end
		if remote then return end
	end
end
hunt(RS, 0)
if not remote then
	for _, d in ipairs(game:GetDescendants()) do
		if d.Name == "TreeService" and d:IsA("RemoteEvent") then
			remote = d
			break
		end
	end
end
if not remote then log("remote", "NOT FOUND") return end
log("remote", remote:GetFullName():sub(1, 90))
remote.OnClientEvent:Connect(function(...)
	local payload = { ... }
	local parts = {}
	for i, v in ipairs(payload) do
		if typeof(v) == "Instance" then
			parts[#parts+1] = "Inst:" .. v.Name
		elseif type(v) == "table" then
			local kv = {}
			for k2, v2 in pairs(v) do kv[#kv+1] = tostring(k2) .. "=" .. tostring(v2) end
			parts[#parts+1] = "{" .. table.concat(kv, ","):sub(1, 200) .. "}"
		else
			parts[#parts+1] = tostring(v)
		end
	end
	T[#T+1] = table.concat(parts, " ;; "):sub(1, 280)
end)

-- chop the nearest quiet Ready tree
local char = plr.Character
local mr = char and char:FindFirstChild("HumanoidRootPart")
local trees = workspace.Map.Trees
if not mr or not trees then log("err", "no char/trees") return end
local target, bestD
for _, t in ipairs(trees:GetChildren()) do
	if t:IsA("Model") and t:FindFirstChild("Trunk") and t:GetAttribute("State") == "Ready" then
		local muts = type(t:GetAttribute("Mutations")) == "table" and #t:GetAttribute("Mutations") or 0
		if muts == 0 then
			local d = (t.Trunk.Position - mr.Position).Magnitude
			local n = 9999
			for _, p in ipairs(game.Players:GetPlayers()) do
				if p ~= plr and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
					local pd = (t.Trunk.Position - p.Character.HumanoidRootPart.Position).Magnitude
					if pd < n then n = pd end
				end
			end
			if n > 60 and d < (bestD or 1e9) then
				target = t bestD = d
			end
		end
	end
end
if not target then log("err", "no quiet tree") return end
log("tree", ("%s w=%d sc=%s"):format(target:GetAttribute("Wood"),
	tonumber(target:GetAttribute("Weight")) or 0, tostring(target:GetAttribute("Scale"))))

local axe
for _, c in ipairs(char:GetChildren()) do
	if c:IsA("Tool") and c.Name:match("Axe") then axe = c.Name end
end
if not axe then
	for _, c in ipairs(plr.Backpack:GetChildren()) do
		if c:IsA("Tool") and c.Name:match("Axe") then c.Parent = char axe = c.Name break end
	end
end
if not axe then log("err", "no axe") return end

local base = target:GetPivot().Position
mr.CFrame = CFrame.new(base + Vector3.new(0, 3, 5))
mr.AssemblyLinearVelocity = Vector3.zero
task.wait(0.6)
pcall(function() TreeService:StartChop(target, 1):await() end)
task.wait(2.2)
pcall(function() TreeService:FinishChop(target, true, false):await() end)
task.wait(8)
log("done", true)
