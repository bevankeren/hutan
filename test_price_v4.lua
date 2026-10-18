-- v4: capture the server's own TreeFelled payload (it reports the REAL value)
-- then compare against the weight x rarity-mult estimate
local plr = game:GetService("Players").LocalPlayer
local RS = game:GetService("ReplicatedStorage")
local Knit = require(RS.Packages.Knit)
pcall(function() Knit.Start() end)
local TreeService = Knit.GetService("TreeService")
local WC = require(RS.Modules.Lumber.WoodConfig)
local T = {}
getgenv().__PT4 = T
local function log(k, v) T[k] = v end

-- find the TreeFelled remote (Knit posts service events under Knit's remotes)
local remote
local function hunt(parent, depth)
	if remote or depth > 3 then return end
	for _, c in ipairs(parent:GetChildren()) do
		if c:IsA("RemoteEvent") and c.Name:lower():find("felled") then
			remote = c
			return
		end
		if c:IsA("RemoteEvent") and c.Name:lower():find("tree") then
			remote = remote or c
		end
		hunt(c, depth + 1)
	end
end
hunt(RS.Packages, 0)
if not remote then
	-- Knit hides service remotes per-service; scan RS broadly
	hunt(RS, 0)
end
if remote then
	log("remote", remote:GetFullName():sub(1, 90))
	remote.OnClientEvent:Connect(function(...)
		local payload = { ... }
		T.felledEvt = {}
		for i, v in ipairs(payload) do
			if type(v) == "table" then
				local parts = {}
				for k2, v2 in pairs(v) do parts[#parts+1] = tostring(k2) .. "=" .. tostring(v2) end
				T.felledEvt[#T.felledEvt+1] = "{" .. table.concat(parts, ","):sub(1, 160) .. "}"
			else
				T.felledEvt[#T.felledEvt+1] = tostring(v)
			end
		end
	end)
else
	log("remote", "NOT FOUND")
end

-- pick the biggest quiet Ready tree
local char = plr.Character
local mr = char and char:FindFirstChild("HumanoidRootPart")
local trees = workspace.Map.Trees
if not mr or not trees then log("err", "no char/trees") return end
local target, nearP
for _, t in ipairs(trees:GetChildren()) do
	if t:IsA("Model") and t:FindFirstChild("Trunk") and t:GetAttribute("State") == "Ready" then
		local w = tonumber(t:GetAttribute("Weight")) or 0
		local muts = type(t:GetAttribute("Mutations")) == "table" and #t:GetAttribute("Mutations") or 0
		if w >= 60000 and muts == 0 then
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

-- axe
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
local okS, s = pcall(function() return TreeService:StartChop(target, 1):await() end)
log("start", tostring(okS and tostring(s) or ("ERR " .. tostring(s))))
task.wait(2.2)
local okF, f = pcall(function() return TreeService:FinishChop(target, true, false):await() end)
log("finish", tostring(okF and tostring(f) or ("ERR " .. tostring(f))))
local fell = false
for _ = 1, 16 do
	task.wait(0.5)
	if target:GetAttribute("State") == "Felled" then fell = true break end
end
log("felled", fell)
-- give the event a beat, then hold position so logs auto-collect too
task.wait(6)
local q
pcall(function()
	Knit.GetService("LumberMillService"):Quote():andThen(function(v) q = v end)
end)
task.wait(1.2)
log("quote", type(q) == "table" and ("%d/$%d"):format(q.Count, q.Worth) or tostring(q))
log("done", true)
