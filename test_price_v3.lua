-- v3: fell a big quiet Redwood, VACUUM all logs on site, quote the true total,
-- then sell at the merchant and read the payout. Multiple-return-safe reads.
local plr = game:GetService("Players").LocalPlayer
local RS = game:GetService("ReplicatedStorage")
local Knit = require(RS.Packages.Knit)
pcall(function() Knit.Start() end)
local TreeService = Knit.GetService("TreeService")
local LumberMillService = Knit.GetService("LumberMillService")
local WC = require(RS.Modules.Lumber.WoodConfig)
local T = {}
getgenv().__PT3 = T
local function log(k, v) T[k] = v end
local function quoteRead()
	local got
	pcall(function()
		LumberMillService:Quote():andThen(function(v) got = v end)
	end)
	local t0 = os.clock()
	while not got and os.clock() - t0 < 3 do task.wait(0.05) end
	return type(got) == "table" and got or nil
end

local char = plr.Character
local mr = char and char:FindFirstChild("HumanoidRootPart")
local trees = workspace.Map.Trees
if not mr or not trees then log("err", "no char/trees") return end

-- quiet big Ready tree: Redwood first, else the heaviest available
local nearOf = function(t)
	local n = 9999
	for _, p in ipairs(game.Players:GetPlayers()) do
		if p ~= plr and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
			local d = (t.Trunk.Position - p.Character.HumanoidRootPart.Position).Magnitude
			if d < n then n = d end
		end
	end
	return n
end
local target, nearP
for _, t in ipairs(trees:GetChildren()) do
	if t:IsA("Model") and t:FindFirstChild("Trunk") and t:GetAttribute("State") == "Ready" then
		local w = tonumber(t:GetAttribute("Weight")) or 0
		local muts = type(t:GetAttribute("Mutations")) == "table" and #t:GetAttribute("Mutations") or 0
		if w >= 150000 and muts == 0 then
			local np = nearOf(t)
			if np > 60 and (not nearP or w > (tonumber(target and target:GetAttribute("Weight")) or 0)) then
				target = t nearP = np
			end
		end
	end
end
if not target then log("err", "no quiet big tree") return end

local rarity = target:GetAttribute("Rarity")
local rm = 1
for _, r in ipairs(WC.Rarities) do
	if r.Name == rarity then rm = r.ValueMultiplier or 1 end
end
local weight = tonumber(target:GetAttribute("Weight")) or 0
local scale = tonumber(target:GetAttribute("Scale")) or 0
log("tree", ("%s %s %s sc=%.3f w=%d nearP=%dm"):format(
	target:GetAttribute("Wood"), rarity, target:GetAttribute("Biome"), scale, weight, math.floor(nearP)))
log("est", math.floor(weight * rm))
log("bucks0", plr.leaderstats and plr.leaderstats.Bucks and plr.leaderstats.Bucks.Value or -1)
local q0 = quoteRead()
log("q0", q0 and ("%d/$%d"):format(q0.Count, q0.Worth) or "?")

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
log("axe", axe)

-- fell
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
if not fell then return end

-- vacuum: sweep the fell site for 12s while segments drop
task.spawn(function()
	local offs = {Vector3.new(0,4,0), Vector3.new(10,4,0), Vector3.new(-10,4,0), Vector3.new(0,4,10),
		Vector3.new(0,4,-10), Vector3.new(16,4,0), Vector3.new(-16,4,0), Vector3.new(0,4,16), Vector3.new(0,4,-16)}
	for i = 1, 3 do
		for _, off in ipairs(offs) do
			mr.CFrame = CFrame.new(base + off)
			mr.AssemblyLinearVelocity = Vector3.zero
			task.wait(0.45)
		end
	end
end)
task.wait(13)
local q1 = quoteRead()
log("q1", q1 and ("%d/$%d"):format(q1.Count, q1.Worth) or "?")
log("perLog", (q1 and q1.Count or 0) > 0 and math.floor(q1.Worth / q1.Count) or 0)

-- sell at nearest merchant NPC
local npcs = workspace.Map:FindFirstChild("NPCs")
local mpos
if npcs then
	local best
	for _, m in ipairs(npcs:GetChildren()) do
		if m.Name:find("Merchant") and m:FindFirstChild("HumanoidRootPart") then
			local d = (m.HumanoidRootPart.Position - mr.Position).Magnitude
			if not best or d < best then best = d mpos = m.HumanoidRootPart.Position end
		end
	end
end
if mpos then
	mr.CFrame = CFrame.new(mpos + Vector3.new(0, 3, 5))
	mr.AssemblyLinearVelocity = Vector3.zero
	task.wait(1.2)
end
local gotSell
pcall(function()
	LumberMillService:SellTrees("All"):andThen(function(v) gotSell = v end)
end)
task.wait(1)
local gotSell2
pcall(function()
	LumberMillService:SellTrees("Held"):andThen(function(v) gotSell2 = v end)
end)
task.wait(1.5)
local q2 = quoteRead()
log("sell1", tostring(gotSell))
log("sell2", tostring(gotSell2))
log("q2", q2 and ("%d/$%d"):format(q2.Count, q2.Worth) or "?")
log("bucks1", plr.leaderstats and plr.leaderstats.Bucks and plr.leaderstats.Bucks.Value or -1)
log("done", true)
