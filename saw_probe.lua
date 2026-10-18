-- saw probe: find logs in backpack, then measure FinishSaw minimum duration
local Players = game:GetService("Players")
local CS = game:GetService("CollectionService")
local plr = Players.LocalPlayer
local RS = game:GetService("ReplicatedStorage")
local Knit = require(RS.Packages.Knit)
local CarryService = Knit.GetService("CarryService")
local SawmillService = Knit.GetService("SawmillService")
local out = {}

local function await(promise, timeout)
	if promise == nil then return {Ok=false, Reason="nil"} end
	if type(promise) ~= "table" then return {Ok=true, Value=promise} end
	if promise.Ok ~= nil then return promise end
	if type(promise.andThen) ~= "function" then return {Ok=true, Value=promise} end
	local done, result = false, nil
	pcall(function()
		promise:andThen(function(v) result = v done = true end,
			function(e) result = {Ok=false, Reason=tostring(e)} done = true end)
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < (timeout or 8) do task.wait(0.03) end
	return done and result or {Ok=false, Reason="timeout"}
end

local function call(svc, method, ...)
	local args = {...}
	local ok, res = pcall(function() return svc[method](svc, table.unpack(args)) end)
	if not ok then return {Ok=false, Reason=tostring(res)} end
	return await(res)
end

local function hrp()
	local char = plr.Character
	return char and char:FindFirstChild("HumanoidRootPart") or nil
end

-- 1) what's in the backpack? look for logs
local bp = plr:FindFirstChild("Backpack")
local logs = {}
if bp then
	for _, c in ipairs(bp:GetChildren()) do
		local attrs = {}
		for k, v in pairs(c:GetAttributes()) do table.insert(attrs, k .. "=" .. tostring(v)) end
		table.sort(attrs)
		table.insert(logs, c.Name .. " [" .. table.concat(attrs, " ") .. "]")
	end
end
out[#out+1] = "backpack (" .. #logs .. "):"
for i, l in ipairs(logs) do
	if i <= 12 then table.insert(out, "  " .. l) end
end

-- 2) nearest sawmill + its MillId
local root = hrp()
local mills = {}
for _, obj in ipairs(CS:GetTagged("Sawmill")) do
	local model = obj:IsA("Model") and obj or obj:FindFirstAncestorOfClass("Model")
	if model then
		local p = model:GetPivot().Position
		local id = model:GetAttribute("MillId") or obj:GetAttribute("MillId") or "?"
		table.insert(mills, {pos = p, id = id, model = model})
	end
end
table.sort(mills, function(a, b)
	return (a.pos - root.Position).Magnitude < (b.pos - root.Position).Magnitude
end)
out[#out+1] = "mills sorted nearest-first:"
for i, m in ipairs(mills) do
	if i <= 6 then
		table.insert(out, ("  %d: MillId=%s @ %d,%d,%d (%.0f studs)"):format(
			i, tostring(m.id), m.pos.X, m.pos.Y, m.pos.Z, (m.pos - root.Position).Magnitude))
	end
end

-- 3) teleport to the nearest mill and try the cycle
if mills[1] then
	local mill = mills[1]
	local stand = mill.pos + Vector3.new(0, 1, 4)
	root.Anchored = false
	root.CFrame = CFrame.lookAt(stand, mill.pos)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	task.wait(0.7)

	local h = call(CarryService, "Hold", 2)
	out[#out+1] = "Hold(2)=" .. tostring(h.Ok) .. " " .. tostring(h.Reason or "")
	local s = call(SawmillService, "StartSaw", mill.id)
	out[#out+1] = "StartSaw(" .. tostring(mill.id) .. ")=" .. tostring(s.Ok) .. " " .. tostring(s.Reason or "")
	if s.Ok then
		-- sweep the wait before FinishSaw to find the minimum
		for _, delay in ipairs({0.3, 0.6, 1.0, 1.5, 2.2, 3.0}) do
			task.wait(delay == 0.3 and 0.3 or delay - 0.3)
			local f = call(SawmillService, "FinishSaw", 1)
			out[#out+1] = ("FinishSaw after ~%.1fs = %s %s"):format(delay, tostring(f.Ok), tostring(f.Reason or ""):sub(0, 34))
			if f.Ok then
				local pk = call(SawmillService, "PickUp", mill.id)
				out[#out+1] = "PickUp=" .. tostring(pk.Ok) .. " " .. tostring(pk.Reason or ""):sub(0, 40)
				break
			end
			task.wait(0.4)
		end
	else
		-- maybe it needs a log held; try equipping one from the backpack
		if bp then
			for _, c in ipairs(bp:GetChildren()) do
				if c:IsA("Tool") and c.Name:match("Log") then
					plr.Character.Humanoid:EquipTool(c)
					task.wait(0.3)
					break
				end
			end
		end
		local s2 = call(SawmillService, "StartSaw", mill.id)
		out[#out+1] = "StartSaw(2nd)=" .. tostring(s2.Ok) .. " " .. tostring(s2.Reason or "")
	end
end
root.Anchored = false
return table.concat(out, "\n")