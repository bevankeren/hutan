-- Foresters farm hub (dev) — Airflow UI
-- features: stealth autofarm (attach + chop + hop) and axe auto-buy
-- tree states / axe shop data are read from the game at runtime
--
-- Re-running this file UNLOADS the previous copy first: the old UI is destroyed,
-- its loops are signalled dead, and the character is handed back in a normal
-- state. Without that, stacked copies keep moving the same character and the
-- stale loops fight the new one, which shows up as phantom hops and chops that
-- never land.

----------------------------------------------------------------------
-- library + services
----------------------------------------------------------------------
local Airflow = loadstring(game:HttpGet("https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/refs/heads/main/Source.luau"))()

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local plr = Players.LocalPlayer

local Knit = require(RS:WaitForChild("Packages"):WaitForChild("Knit"))
pcall(function() Knit.Start() end)
local TreeService = Knit.GetService("TreeService")
local AxeService = Knit.GetService("AxeService")

local AxeConfig = require(RS.Modules.Lumber.AxeConfig)
local AxePrice = require(RS.Modules.Lumber.AxePrice)
local ChopTuning = require(RS.Modules.Lumber.ChopTuning)

----------------------------------------------------------------------
-- unload any previous run
----------------------------------------------------------------------
do
	local prev = getgenv().__ForestFarmState
	if prev then
		-- flip the token so any live loop from the previous copy exits on its
		-- next check, then stop its work flags outright
		prev.token = (prev.token or 0) + 1
		prev.farm = false
		prev.autobuy = false
		local ok, old = pcall(function() return getgenv().ForestFarm end)
		if ok and type(old) == "table" and type(old.stop) == "function" then
			pcall(old.stop)
		end
	end
	-- tear down ONLY the window this script created. Destroying every ScreenGui
	-- here used to wipe the player's own HUD (on mobile especially), because the
	-- game's interface lives in ScreenGuis of its own. We now keep a reference to
	-- our window and remove exactly that.
	if prev and prev.window and typeof(prev.window) ~= "nil" then
		pcall(function() prev.window:Destroy() end)
	end
	-- belt-and-braces fallback: if the window reference was lost, remove any
	-- ScreenGui whose name matches Airflow's window naming, and nothing else.
	local gui = plr:FindFirstChild("PlayerGui")
	if gui then
		for _, g in ipairs(gui:GetChildren()) do
			if g:IsA("ScreenGui") and g.Name:match("Airflow") then
				pcall(function() g:Destroy() end)
			end
		end
	end
	-- hand the character back in a normal state
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

----------------------------------------------------------------------
-- shared state (a re-run must kill every previous loop)
----------------------------------------------------------------------
local S = getgenv().__ForestFarmState
if not S then
	S = {token = 0, farm = false, autobuy = false}
	getgenv().__ForestFarmState = S
end
S.token += 1
local MY_TOKEN = S.token
S.farm = false
S.autobuy = false
task.wait(0.2)

local function alive()
	return S.token == MY_TOKEN
end

----------------------------------------------------------------------
-- character / stealth
----------------------------------------------------------------------
local savedCollide = setmetatable({}, {__mode = "k"})
local noclipOn = false

local function set_prop(part, prop, value, ok)
	pcall(function() part[prop] = value end)
end

-- one pass is not enough: the Humanoid re-solidifies parts while grounded,
-- so this is driven from RenderStepped while the farm runs
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
		-- stop the engine from re-grounding us through terrain
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
	for d in pairs(savedCollide) do
		if d.Parent then d.CanCollide = true end
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

-- Where to stand while chopping.
--
-- Grounded, a few studs off the trunk, facing it. That is the only arrangement
-- verified end to end: StartChop ok -> FinishChop ok -> state=Felled.
--
-- The character is deliberately NOT anchored. The server rejects StartChop from
-- an anchored position — every anchored attempt was refused with "Get closer to
-- the tree" at a correct 5-stud distance, while the same spot with a free
-- character went through. So: set the CFrame, zero the velocity, ask at once.
--
-- Note the reach gate is measured against the pivot HORIZONTALLY, and the game's
-- own ChopLeash yanks the character back to the reach boundary every frame
-- anyway, so standing further out is pointless: the leash pulls you in.
local HUG_OFFSET = 5
local STAND_HEIGHT = 1

local attachYaw = 0

-- Moving an anchored part does not replicate, so the server's reach check keeps
-- seeing the OLD position. Releasing the anchor and waiting lets physics drag us
-- off instead. The sequence that works is: unanchor, set CFrame, zero velocity,
-- then ask immediately with no yield in between.
--
-- Collisions are deliberately left ALONE. No-clip is what the server rejects.
local function attach(tree, anchor, reroll)
	local root = hrp()
	if not root or not tree or not tree.Parent then return end
	if reroll then attachYaw = math.random() * math.pi * 2 end
	local base = tree:GetPivot()
	local stand = base * (CFrame.Angles(0, attachYaw, 0) * CFrame.new(0, STAND_HEIGHT, HUG_OFFSET))
	local facing = CFrame.lookAt(stand.Position, base.Position)
	root.Anchored = false
	root.CFrame = facing
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	-- never anchor: an anchored root is refused by the server's reach check
end

local function set_anchored(state)
	local root = hrp()
	if root then root.Anchored = state end
end

-- keep a tool in hand; the server rejects chops otherwise.
-- anchoring drops the tool, so this must run AFTER any anchor change
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
			pcall(function() hum:EquipTool(c) end)
			for _ = 1, 12 do
				if held() then return true end
				task.wait(0.05)
			end
		end
	end
	return held()
end

-- tools also drop on teleport/respawn; re-equip right before every chop
local function ensure_axe_for_chop()
	if equip_axe() then return true end
	task.wait(0.15)
	return equip_axe()
end

----------------------------------------------------------------------
-- promise bridge
----------------------------------------------------------------------
-- Knit methods normally return a Promise, but not always: a call can resolve to
-- a plain value, or hand back an Instance (StartChop answering with the tree),
-- and calling :andThen on one of those raises
--   "Trying to call method on object of type: `Model` with incorrect arguments"
-- at hundreds of times a second inside the farm loop. So accept anything: use
-- andThen when it exists, otherwise treat the value as the settled result, and
-- treat a thrown call as a failure instead of killing the loop.
local function await(promise, timeout)
	if promise == nil then return {Ok = false, Reason = "nil result"} end
	if type(promise) ~= "table" and typeof(promise) ~= "Instance" then
		return {Ok = true, Value = promise}
	end
	if promise.Ok ~= nil then return promise end
	if type(promise.andThen) ~= "function" then
		-- already a plain value/instance: that IS the answer
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
		-- not actually a promise after all
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

-- same idea, but also survives the call itself throwing
local function call(service, method, ...)
	local args = {...}
	local ok, res = pcall(function()
		return service[method](service, table.unpack(args))
	end)
	if not ok then return {Ok = false, Reason = tostring(res)} end
	return await(res)
end

----------------------------------------------------------------------
-- trees
----------------------------------------------------------------------
local WoodConfig = require(RS.Modules.Lumber.WoodConfig)
local tierCache = {}
local function rarity_info(rarity)
	if tierCache[rarity] == nil then
		local ok, info = pcall(function() return WoodConfig.GetRarity(rarity) end)
		tierCache[rarity] = (ok and info) or {Tier = 0, ValueMultiplier = 1}
	end
	return tierCache[rarity]
end
local function tier_of(rarity)
	return rarity_info(rarity).Tier or 0
end

-- what a tree is actually worth: the game scales value by the rarity multiplier
-- (1 for Common up to 1500 for Secret), then by size, then mutations on top.
-- Rarer really does mean more money, so this is the ranking that pays.
local function value_of(tree)
	local info = rarity_info(tree:GetAttribute("Rarity"))
	local mult = info.ValueMultiplier or 1
	local scale = tree:GetAttribute("Scale") or 1
	local muts = tree:GetAttribute("Mutations")
	local mutBonus = 1
	if type(muts) == "table" then
		for _ in pairs(muts) do mutBonus += 0.5 end
	end
	return mult * scale * mutBonus
end

local function is_live(tree)
	local st = tree:GetAttribute("State")
	if st == "Ready" then return true end
	if st == "Locked" and tree:GetAttribute("LockedBy") == plr.UserId then return true end
	return false
end

-- Can this axe fell this tree AT ALL?
--
-- ChopTuning.Pressure returns BeyondReach (3) when the island's toughness exceeds
-- the axe's power. Measured with a Golden Axe (power 2.10): StarterForest 1.00,
-- BirchHills 1.70, PalmCove 2.10, SnowyPines 2.70 all chop; DustyMesa 2.80 and
-- RedwoodGrove 3.40 both return 3, which means the tree cannot be felled at all
-- with that axe — not slowly, but never. RedwoodGrove is where the rarest
-- species live, so a rarity-first picker would otherwise spend the whole run
-- hammering trees that refuse every single time.
local function held_axe_id()
	local char = plr.Character
	if not char then return nil end
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") and c.Name:match("Axe") then return c.Name end
	end
	return nil
end

-- the spec shape ChopTuning expects, built from whatever is in hand
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
	if not ok then return true end -- unknown shape: do not block on a guess
	return pressure < ChopTuning.BeyondReach
end

-- Ask the server's own formula how long this chop will take, rather than
-- assuming one fixed hold for every tree.
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

local MODES = {"Nearest", "MostValuable", "Rarest", "Heaviest", "Biggest", "Any"}

local function pick(mode, blocked)
	local folder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Trees")
	if not folder then return nil end
	local now = os.clock()
	local axeSpec = current_axe_spec()
	local list = {}
	local skipped = 0
	for _, t in ipairs(folder:GetChildren()) do
		if is_live(t) and not (blocked[t] and blocked[t] > now) then
			-- Drop trees this axe physically cannot fell. Without this the
			-- rarest-first modes keep picking RedwoodGrove monsters that refuse
			-- every attempt, which reads as "hopping trees without chopping".
			if can_fell(t, axeSpec) then
				table.insert(list, t)
			else
				skipped += 1
			end
		end
	end
	S.skipped = skipped
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
		-- rarest and richest first: value, then rarity tier, then closer wins ties
		table.sort(list, function(a, b)
			local va, vb = value_of(a), value_of(b)
			if va ~= vb then return va > vb end
			local ta, tb = tier_of(a:GetAttribute("Rarity")), tier_of(b:GetAttribute("Rarity"))
			if ta ~= tb then return ta > tb end
			return dist(a) < dist(b)
		end)
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

-- one tree: teleport under it, hold the server's minimum session, finish.
--
-- Every exit path releases the server-side lock. A session left open wedges the
-- loop into "hop forever, never chop" because each new StartChop is refused.
--
-- Teleporting far can arrive before the move replicates, so the first StartChop
-- is sometimes refused with "Get closer" even though the position is correct —
-- confirmed intermittent at a fixed spot. A short retry covers it; only give up
-- after the position has been re-asserted and still refused.
local function chop_tree(tree)
	if not tree or not tree.Parent then return false, "tree gone" end
	ensure_axe_for_chop()
	attach(tree, true, true)
	ensure_axe_for_chop()

	local session
	for attempt = 1, 4 do
		if not tree.Parent then return false, "tree gone" end
		attach(tree, true)
		ensure_axe_for_chop()
		local root = hrp()
		-- guarded: the tree can be felled by someone else between pick and chop
		local okPivot, base = pcall(function() return tree:GetPivot() end)
		if root and okPivot and base then
			S.preChop = ("a%d pivotY=%d nowY=%d d3=%.1f"):format(
				attempt, math.floor(base.Position.Y), math.floor(root.Position.Y),
				(root.Position - base.Position).Magnitude)
		end
		session = call(TreeService, "StartChop", tree, 1)
		if type(session) == "table" and session.Ok then break end
		if tostring(session and session.Reason) == "Get closer to the tree" then
			task.wait(0.1 * attempt)
		else
			break -- a real refusal (wrong axe, locked, not live) — move on
		end
	end
	if type(session) ~= "table" or not session.Ok then
		-- Do NOT call CancelChop here. Cancelling locks the tree on the server,
		-- and a locked tree refuses every later attempt — which is exactly what
		-- made the farm fell one tree and then hop forever. Just walk away.
		return false, (type(session) == "table" and session.Reason) or "start failed"
	end

	-- Wait for the tree to actually come down instead of guessing a hold time.
	--
	-- Chop hardness is not uniform: IslandToughness runs 1.0 (StarterForest) to
	-- 3.4 (RedwoodGrove), and rarity/size hardness multiply on top, so any single
	-- hardcoded duration is wrong for most trees — too short and we leave before
	-- the tree falls, too long and every easy tree wastes the difference. The
	-- server reports progress itself, so poll it and stop the moment it is done.
	--
	-- Params.MinDuration is still honoured as a floor, because calling FinishChop
	-- too early is rejected outright.
	local floor = (session.Params and session.Params.MinDuration) or 1.2
	local t0 = os.clock()
	local finish, last
	while true do
		if not S.farm or not alive() then
			-- only a real stop cancels, and even then we leave the tree alone:
			-- the server releases the lock on its own once the session times out
			return false, "cancelled"
		end
		-- keep the character pinned; the client leash also pulls us in, and
		-- letting velocity build up fights it
		if tree.Parent then
			local root = hrp()
			if root then
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		else
			-- the tree is gone from the world: nothing left to finish
			return true, "felled"
		end

		local elapsed = os.clock() - t0
		if elapsed >= floor then
			local res = call(TreeService, "FinishChop", tree, true, false)
			if type(res) == "table" and res.Ok then
				finish = res
				break
			end
			last = type(res) == "table" and res.Reason or "finish failed"
			-- still too early / not ready: keep holding rather than bailing
			if tostring(last):lower():match("fast") or tostring(last):lower():match("early") then
				-- fall through and hold longer
			elseif tostring(last) == "NotFelled" or tostring(last):lower():match("not") then
				-- more chopping needed; keep going
			else
				-- a hard refusal: stop and let the loop retry. No CancelChop —
				-- that is what locked trees and wedged the farm.
				return false, tostring(last)
			end
		end

		-- generous ceiling so a wedged tree cannot stall the whole run
		if elapsed > 25 then
			return false, "timed out: " .. tostring(last)
		end
		task.wait(0.08)
	end

	return true, (finish and finish.Felled) and "felled" or "held"
end

----------------------------------------------------------------------
-- axe data + shop
----------------------------------------------------------------------
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

-- every axe worth buying, cheapest first, with the shop that sells it
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
		if type(cfg) == "table" and shops[id] then
			local ok, price = pcall(function() return AxePrice.For(id, {}) end)
			table.insert(list, {
				id = id,
				name = tostring(cfg.DisplayName or id),
				price = ok and price or (cfg.Price or 0),
				power = cfg.Power or 0,
				speed = cfg.Speed or 0,
				luck = cfg.Luck or 0,
				pos = shops[id],
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

local function travel_to(pos)
	local root = hrp()
	if not root then return end
	root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 4))
	root.AssemblyLinearVelocity = Vector3.zero
	task.wait(0.5)
end

-- shop is proximity-gated (server answers "NotHere" otherwise), so we travel
local function buy_axe(axe)
	travel_to(axe.pos)
	local res = call(AxeService, "BuyAxe", axe.id)
	if type(res) == "table" and res.Ok then
		call(AxeService, "EquipAxe", axe.id)
		return true, "bought + equipped " .. axe.name
	end
	return false, (type(res) == "table" and res.Reason) or "buy failed"
end

----------------------------------------------------------------------
-- ui
----------------------------------------------------------------------
local Window = Airflow:CreateWindow({
	Name = "Foresters",
	LoadingSubtitle = "farm dev",
	Icon = "trees",
	ToggleUIKeybind = "RightShift",
	Size = UDim2.fromOffset(620, 460),
	ConfigurationSaving = {Enabled = true, FolderName = "ForestersHub"},
	Home = {Tier = "Dev", Features = true},
})
-- remember it so the next run unloads exactly this window and nothing else
S.window = Window

local farmTab = Window:CreateTab({Name = "Farm", Icon = "tree-pine"})
local axeTab = Window:CreateTab({Name = "Axes", Icon = "axe"})

farmTab:CreateSection({Name = "Auto Farm"})
local stateLabel = farmTab:CreateLabel({Name = "state: idle"})
local targetLabel = farmTab:CreateLabel({Name = "target: -"})
local countLabel = farmTab:CreateLabel({Name = "felled: 0   failed: 0"})
local rateLabel = farmTab:CreateLabel({Name = "rate: 0/min"})

farmTab:CreateSection({Name = "Session"})
local axeLabel = farmTab:CreateLabel({Name = "axe: -"})
local buckLabel = farmTab:CreateLabel({Name = "bucks: -"})

axeTab:CreateSection({Name = "Buy Axes (cheap to expensive)"})
local buyLabel = axeTab:CreateLabel({Name = "auto buy: off"})
local buyLogLabel = axeTab:CreateLabel({Name = "last: -"})
axeTab:CreateSection({Name = "Ladder"})

local stats = {felled = 0, failed = 0, startedAt = 0, blocked = {}}
local modeIndex = 1
local farmOn = false

local function safe_set(label, text)
	pcall(function() label:Set(text) end)
end

local function refresh_axe_info()
	local eq = equipped_axe()
	local cfg = eq and AxeConfig[eq]
	safe_set(axeLabel, "axe: " .. (eq and ((cfg and cfg.DisplayName or eq) .. "  power " .. tostring(cfg and cfg.Power or "?")) or "none"))
	safe_set(buckLabel, "bucks: $" .. tostring(bucks()))
end

local function rate()
	if stats.startedAt == 0 or stats.felled == 0 then return 0 end
	local mins = (os.clock() - stats.startedAt) / 60
	if mins <= 0 then return 0 end
	return stats.felled / mins
end

local function refresh_state()
	safe_set(stateLabel, "state: " .. (farmOn and "RUNNING" or "idle"))
	safe_set(countLabel, ("felled: %d   failed: %d"):format(stats.felled, stats.failed))
	safe_set(rateLabel, ("rate: %.1f/min"):format(rate()))
end

local lastTargetText = nil
local function set_target_text(text)
	if text == lastTargetText then return end
	lastTargetText = text
	safe_set(targetLabel, "target: " .. text)
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
	-- No-clip is OFF on purpose and must stay off: the server rejects StartChop
	-- from a non-collidable character, which is what produced an endless stream
	-- of "Get closer to the tree" refusals. Keep a normal, solid character.
	noclipOn = false
	restore_collide()
	refresh_state()

	task.spawn(function()
		while S.farm and alive() do
			local ok, msg = pcall(function()
				local mode = MODES[modeIndex]
				local root = hrp()
				if not root then
					return "no character"
				end
				-- if we somehow ended up under the map, pull back up immediately
				if root.Position.Y < -100 then
					root.CFrame = CFrame.new(root.Position.X, 60, root.Position.Z)
				end
				local tree = pick(mode, stats.blocked)
				if not tree then
					set_target_text("-")
					task.wait(0.5) -- nothing to do; do not spin the loop red hot
					return "no tree ready"
				end
				set_target_text(tostring(tree:GetAttribute("Species") or tree.Name))
				local good, result = chop_tree(tree)
				if not good then
					-- short bench: the position fix removed the mass-failure mode, so a
					-- refusal here usually just means the tree went busy under us
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

farmToggle = farmTab:CreateToggle({
	Name = "Auto Farm",
	Flag = "AutoFarm",
	CurrentValue = false,
	Callback = function(on) set_farm(on) end,
})

farmTab:CreateDropdown({
	Name = "Target class",
	Flag = "TargetMode",
	Options = MODES,
	CurrentOption = {MODES[1]},
	Callback = function(sel)
		local chosen = type(sel) == "table" and sel[1] or sel
		for i, m in ipairs(MODES) do
			if m == chosen then modeIndex = i end
		end
	end,
})

farmTab:CreateParagraph({
	Title = "Stealth attach",
	Content = "Hugs the trunk base with collision off and holds inside it while the chop session runs.",
})

----------------------------------------------------------------------
-- axe ladder ui
----------------------------------------------------------------------
local ladder = axe_ladder()
local axeRows = {}
local autobuyOn = false

local function refresh_ladder()
	local own = owned_axes()
	local eq = equipped_axe()
	for _, row in ipairs(axeRows) do
		local tag = own[row.axe.id] and (eq == row.axe.id and "  [equipped]" or "  [owned]") or ""
		row.button:SetText(("%s  $%d  power %.1f%s"):format(row.axe.name, row.axe.price, row.axe.power, tag))
	end
	refresh_axe_info()
end

for _, axe in ipairs(ladder) do
	local button = axeTab:CreateButton({
		Name = ("%s  $%d  power %.1f"):format(axe.name, axe.price, axe.power),
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

-- cheapest axe we do not own yet, that we can afford
local function next_target()
	local own = owned_axes()
	for _, axe in ipairs(ladder) do
		if not own[axe.id] and bucks() >= axe.price then
			return axe
		end
	end
	return nil
end

axeTab:CreateToggle({
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

axeTab:CreateButton({
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

axeTab:CreateParagraph({
	Title = "How buying works",
	Content = "The server rejects purchases unless you are standing at the shop, so auto buy travels to the axe's island stall first.",
})

----------------------------------------------------------------------
-- keep noclip alive while farming (the Humanoid re-solidifies parts)
----------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	if noclipOn and S.farm and alive() then
		noclip_pass()
	end
end)

plr.CharacterAdded:Connect(function()
	if S.farm and alive() then
		task.wait(0.6)
		noclipOn = true
		equip_axe()
	end
end)

-- periodic refresh so prices/bucks stay honest
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
		-- release the character: an anchored root never teleports again, which
		-- silently kills the next run's ability to reach any tree
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
}

refresh_state()
refresh_axe_info()
refresh_ladder()
pcall(function()
	Window:Notify({Title = "Foresters", Content = "Farm hub ready", Duration = 4})
end)
print("[FarmHub] loaded")
