-- self-contained price-accuracy test: quiet tree -> estimate -> chop -> sell
-- writes every number into getgenv().__PriceTest as it goes
local plr = game:GetService("Players").LocalPlayer
local RS = game:GetService("ReplicatedStorage")
local Knit = require(RS:WaitForChild("Packages"):WaitForChild("Knit"))
pcall(function() Knit.Start() end)
local TreeService = Knit.GetService("TreeService")
local WC = require(RS.Modules.Lumber.WoodConfig)
local FF = getgenv().ForestFarm
local T = {}
getgenv().__PriceTest = T
local function log(k, v) T[k] = v end

local char = plr.Character
local mr = char and char:FindFirstChild("HumanoidRootPart")
local folder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Trees")
if not mr or not folder then log("err", "no char/folder") return end

-- candidates: Ready, far from every other player, unmutated for a clean read
local cands = {}
for _, t in ipairs(folder:GetChildren()) do
	if t:IsA("Model") and t:FindFirstChild("Trunk") and t:GetAttribute("State") == "Ready" then
		local nearP = 9999
		for _, p in ipairs(game.Players:GetPlayers()) do
			if p ~= plr and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
				local d = (t.Trunk.Position - p.Character.HumanoidRootPart.Position).Magnitude
				if d < nearP then nearP = d end
			end
		end
		if nearP > 60 then
			local muts = t:GetAttribute("Mutations")
			local mutCount = type(muts) == "table" and #muts or 0
			cands[#cands+1] = {t = t, nearP = nearP, muts = mutCount,
				weight = tonumber(t:GetAttribute("Weight")) or 0}
		end
	end
end
table.sort(cands, function(a, b)
	if a.muts ~= b.muts then return a.muts < b.muts end
	return a.weight > b.weight
end)
local target = cands[1] and cands[1].t
if not target then log("err", "no quiet candidate") return end

-- record + estimate
local rarity = target:GetAttribute("Rarity")
local rm = 1
for _, r in ipairs(WC.Rarities) do
	if r.Name == rarity then rm = r.ValueMultiplier or 1 end
end
local mutMult = 1
local muts = target:GetAttribute("Mutations")
if type(muts) == "table" then
	for _, idx in ipairs(muts) do
		local m = tonumber(idx) and WC.Mutations[tonumber(idx)]
		if type(m) == "table" and tonumber(m.ValueMultiplier) then
			mutMult = mutMult * m.ValueMultiplier
		end
	end
end
local weight = tonumber(target:GetAttribute("Weight")) or 0
T.tree = ("%s %s %s sc=%.3f w=%.0f muts=%d nearP=%dm"):format(
	target:GetAttribute("Wood"), rarity, target:GetAttribute("Biome"),
	tonumber(target:GetAttribute("Scale")) or 0, weight,
	type(muts) == "table" and #muts or 0, math.floor(cands[1].nearP))
T.est = math.floor(weight * rm * mutMult)
log("bucks0", plr.leaderstats and plr.leaderstats.Bucks and plr.leaderstats.Bucks.Value or -1)
local okQ, q0 = pcall(function() return FF.quote() end)
T.q0 = okQ and type(q0) == "table" and (tostring(q0.Count) .. "/$" .. tostring(q0.Worth)) or tostring(q0)

-- equip axe
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

-- stand at the trunk
local base = target:GetPivot().Position
mr.CFrame = CFrame.new(base + Vector3.new(0, 3, 5))
mr.AssemblyLinearVelocity = Vector3.zero
task.wait(0.6)

-- chop: StartChop resolves to plain true on success, no session payload
local okS, s = pcall(function() return TreeService:StartChop(target, 1):await() end)
T.start = tostring(okS and tostring(s) or ("ERR " .. tostring(s)))
if okS and s == false then log("err", "StartChop false") return end
task.wait(2.2)
local okF, f = pcall(function() return TreeService:FinishChop(target, true, false):await() end)
T.finish = tostring(okF and tostring(f) or ("ERR " .. tostring(f)))

-- poll felled
local fell = false
for _ = 1, 16 do
	task.wait(0.5)
	if target:GetAttribute("State") == "Felled" then fell = true break end
end
log("felled", fell)

-- let logs land in inventory, then quote the held worth
task.wait(3)
local okQ2, q1 = pcall(function() return FF.quote() end)
T.q1 = okQ2 and type(q1) == "table" and (tostring(q1.Count) .. "/$" .. tostring(q1.Worth)) or tostring(q1)

-- sell at the nearest merchant, then read the payout
local npcs = workspace.Map:FindFirstChild("NPCs")
local merch, mpos
if npcs then
	for _, m in ipairs(npcs:GetChildren()) do
		if m.Name:find("Merchant") and m:FindFirstChild("HumanoidRootPart") then
			merch = m mpos = m.HumanoidRootPart.Position break
		end
	end
end
if merch then
	mr.CFrame = CFrame.new(mpos + Vector3.new(0, 3, 5))
	mr.AssemblyLinearVelocity = Vector3.zero
	task.wait(1)
end
local okSell, sell = pcall(function() return FF.sell() end)
T.sell = tostring(okSell and tostring(sell) or ("ERR " .. tostring(sell)))
task.wait(1.5)
local okQ3, q2 = pcall(function() return FF.quote() end)
T.q2 = okQ3 and type(q2) == "table" and (tostring(q2.Count) .. "/$" .. tostring(q2.Worth)) or tostring(q2)
log("bucks1", plr.leaderstats and plr.leaderstats.Bucks and plr.leaderstats.Bucks.Value or -1)
log("done", true)
