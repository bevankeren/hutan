-- v6: TreeFelled signal lives ON the Knit service object — capture its payload
local plr = game:GetService("Players").LocalPlayer
local RS = game:GetService("ReplicatedStorage")
local Knit = require(RS.Packages.Knit)
pcall(function() Knit.Start() end)
local TreeService = Knit.GetService("TreeService")
local WC = require(RS.Modules.Lumber.WoodConfig)
local T = {}
getgenv().__PT6 = T
local function log(k, v) T[k] = v end

local okC, sig = pcall(function() return TreeService.TreeFelled end)
if okC and sig then
	log("signal", typeof(sig))
	sig:Connect(function(...)
		local payload = { ... }
		local parts = {}
		for i, v in ipairs(payload) do
			if typeof(v) == "Instance" then
				parts[#parts+1] = "Inst:" .. v.Name
			elseif type(v) == "table" then
				local kv = {}
				for k2, v2 in pairs(v) do kv[#kv+1] = tostring(k2) .. "=" .. tostring(v2) end
				parts[#parts+1] = "{" .. table.concat(kv, ","):sub(1, 240) .. "}"
			else
				parts[#parts+1] = tostring(v)
			end
		end
		T[#T+1] = table.concat(parts, " ;; "):sub(1, 320)
	end)
else
	log("signal", "none: " .. tostring(sig))
end

local char = plr.Character
local mr = char and char:FindFirstChild("HumanoidRootPart")
local trees = workspace.Map.Trees
if not mr or not trees then log("err", "no char/trees") return end
local target, nearP
for _, t in ipairs(trees:GetChildren()) do
	if t:IsA("Model") and t:FindFirstChild("Trunk") and t:GetAttribute("State") == "Ready" then
		local w = tonumber(t:GetAttribute("Weight")) or 0
		local muts = type(t:GetAttribute("Mutations")) == "table" and #t:GetAttribute("Mutations") or 0
		if w >= 30000 and muts == 0 then
			local n = 9999
			for _, p in ipairs(game.Players:GetPlayers()) do
				if p ~= plr and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
					local d = (t.Trunk.Position - p.Character.HumanoidRootPart.Position).Magnitude
					if d < n then n = d end
				end
			end
			if n > 60 and (not target or w > (tonumber(target:GetAttribute("Weight")) or 0)) then
				target = t nearP = n
			end
		end
	end
end
if not target then log("err", "no quiet tree") return end

local rarity = target:GetAttribute("Rarity")
local rm = 1
for _, r in ipairs(WC.Rarities) do
	if r.Name == rarity then rm = r.ValueMultiplier or 1 end
end
local weight = tonumber(target:GetAttribute("Weight")) or 0
log("tree", ("%s %s %s sc=%.3f w=%d nearP=%dm"):format(
	target:GetAttribute("Wood"), rarity, target:GetAttribute("Biome"),
	tonumber(target:GetAttribute("Scale")) or 0, weight, math.floor(nearP)))
log("est", math.floor(weight * rm))

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
local fell = false
for _ = 1, 16 do
	task.wait(0.5)
	if target:GetAttribute("State") == "Felled" then fell = true break end
end
log("felled", fell)
task.wait(5)
log("done", true)
