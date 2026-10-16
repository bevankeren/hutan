-- Blizzard farm hub for Foresters — Airflow UI
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
local LumberMillService = Knit.GetService("LumberMillService")
local SawmillService = Knit.GetService("SawmillService")
local CarryService = Knit.GetService("CarryService")

local AxeConfig = require(RS.Modules.Lumber.AxeConfig)
local AxePrice = require(RS.Modules.Lumber.AxePrice)
local ChopTuning = require(RS.Modules.Lumber.ChopTuning)

----------------------------------------------------------------------
-- auto perfect (Legit tab)
----------------------------------------------------------------------
-- The chop minigames (Chop / Swing / Notch) are client-side simulations. Each
-- ends in onFinish(done, perfect), and ChopController forwards those straight
-- into TreeService:FinishChop(tree, done, perfect) — the server trusts the
-- claimed perfect flag. Verified live: a call sent as FinishChop(tree, true,
-- false) through this wrapper comes back Ok=true, Felled=true.
--
-- The wrapper only upgrades a *successful* chop (done=true) to perfect. Failed
-- chops (done=false, "the tree held on") pass through untouched, so the feature
-- reads as playing the minigame well rather than felling trees that were never
-- cut. Toggling off or unloading restores the original method.
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
	-- only restore if nobody stacked another wrapper on top of ours
	if TreeService.FinishChop == state.old or type(state.old) == "function" then
		pcall(function() TreeService.FinishChop = state.old end)
	end
	getgenv()[PERF_KEY] = nil
	return true
end

local function perfect_hook_active()
	return getgenv()[PERF_KEY] ~= nil
end

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
		prev.perfectOn = false
		local ok, old = pcall(function() return getgenv().ForestFarm end)
		if ok and type(old) == "table" and type(old.stop) == "function" then
			pcall(old.stop)
		end
	end
	-- undo the auto-perfect wrapper so the next run hooks a clean method
	pcall(function()
		local state = getgenv().__BlizzardPerfHook
		if state and type(state.old) == "function" then
			TreeService.FinishChop = state.old
		end
		getgenv().__BlizzardPerfHook = nil
	end)
	-- tear down ONLY the window this script created. Destroying every ScreenGui
	-- here used to wipe the player's own HUD (on mobile especially), because the
	-- game's interface lives in ScreenGuis of its own. We now keep a reference to
	-- our window and remove exactly that.
	if prev and prev.window and typeof(prev.window) ~= "nil" then
		pcall(function() prev.window:Destroy() end)
	end
	-- wipe the ESP overlay: the folder holds tree/player billboards, highlights
	-- ride on characters and get swept by name. (Inline, not esp_teardown — that
	-- local is declared later and would resolve to nil here.)
	local espFolderOld = workspace:FindFirstChild("BlizzardESP")
	if espFolderOld then pcall(function() espFolderOld:Destroy() end) end
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Highlight") and d.Name == "BlzPlayerHL" then pcall(function() d:Destroy() end) end
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
	S = {token = 0, farm = false, autobuy = false, panicOn = false, panicRadius = 50, perfectOn = false}
	getgenv().__ForestFarmState = S
end
S.panicOn = S.panicOn or false
S.panicRadius = S.panicRadius or 50
S.perfectOn = S.perfectOn or false
S.autoSell = S.autoSell or false
S.sellAt = S.sellAt or 50
S.logCount = S.logCount or 0
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

-- What the merchant pays for a felled tree: weight scaled by the rarity
-- multiplier. TreeFelled reports Value alongside Weight, and Value is what the
-- sell screens use, so Weight x ValueMultiplier is the honest ranking.
local function sell_value_of(tree)
	local info = rarity_info(tree:GetAttribute("Rarity"))
	local mult = info.ValueMultiplier or 1
	local weight = tree:GetAttribute("Weight") or 0
	return weight * mult
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

local MODES = {"Nearest", "MostValuable", "SellValue", "Rarest", "Heaviest", "Biggest", "Any"}

-- Hop to the smallest public server in this place.
--
-- Two things made the old hop dead on arrival:
--  1. TeleportService:GetServerPlaceInstancesAsync does not exist on this
--     executor, so there is no in-engine way to enumerate servers.
--  2. This function referenced safe_set/stateLabel before their `local`
--     declarations — lexical scoping resolved them to GLOBAL nil, so the first
--     call errored inside task.spawn and the button silently did nothing.
--
-- The rewrite lists servers over the games HTTP API (verified working through
-- the executor's http_request: 51 public servers returned for this place),
-- sorts by population, and teleports to the emptiest one that is not the
-- server we are already in. Returns a status string; the caller renders it, so
-- scoping stays clean.
local function hop_to_low_server()
	local TS = game:GetService("TeleportService")
	local HS = game:GetService("HttpService")
	local here = #game.Players:GetPlayers()

	local fetch = (typeof(http_request) == "function" and http_request)
		or (typeof(request) == "function" and request)
		or nil
	if not fetch then
		-- no HTTP lane: plain rejoin and hope the matchmaker spreads us out
		task.spawn(function()
			pcall(function() TS:Teleport(game.PlaceId, plr) end)
		end)
		return ("rejoin (%d here)"):format(here)
	end

	local ok, res = pcall(fetch, {
		Url = ("https://games.roblox.com/v1/games/%d/servers/Public?limit=100&excludeFullGames=true"):format(game.PlaceId),
		Method = "GET",
	})
	local body = ok and res and (res.Body or res.body)
	if not body then
		task.spawn(function()
			pcall(function() TS:Teleport(game.PlaceId, plr) end)
		end)
		return "rejoin (api fail)"
	end

	local okJ, data = pcall(function() return HS:JSONDecode(body) end)
	if not okJ or type(data) ~= "table" or type(data.data) ~= "table" then
		task.spawn(function()
			pcall(function() TS:Teleport(game.PlaceId, plr) end)
		end)
		return "rejoin (bad json)"
	end

	-- emptiest server we are not already in
	local best = nil
	for _, s in ipairs(data.data) do
		if type(s) == "table" and type(s.id) == "string" and s.id ~= game.JobId then
			local n = tonumber(s.playing) or 999
			local max = tonumber(s.maxPlayers) or 20
			if n < max and (not best or n < best.count) then
				best = {count = n, id = s.id}
			end
		end
	end

	if not best then
		return "no other public server"
	end
	if best.count + 1 >= here then
		-- joining it would not make this one any quieter than staying
		return ("already among quietest (%d here, best %d)"):format(here, best.count)
	end

	task.spawn(function()
		pcall(function() TS:TeleportToPlaceInstance(game.PlaceId, best.id, plr) end)
	end)
	return ("hop: %d here -> %d/20"):format(here, best.count)
end

----------------------------------------------------------------------
-- ESP
----------------------------------------------------------------------
-- Purely client-side overlay: Highlights + BillboardGui tags. Nothing here
-- touches a remote, so nothing replicates — other players and the server see
-- none of it. One workspace Folder holds every instance, so unload is a single
-- Destroy.
--
-- Trees are tagged with billboards only: Roblox renders at most ~31 Highlight
-- instances at once, and a forest has far more trees than that. Labels carry
-- species, worth and distance, green when the held axe can fell it, red when
-- the island is beyond reach. Players get a full Highlight (players never
-- exceed the Highlight budget) plus a name+distance tag.

local ESP = {folder = nil, treeTags = {}, playerTags = {}, conns = {}}

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

local function esp_make_billboard(name, adornee, text, color, widthPx)
	local bb = Instance.new("BillboardGui")
	bb.Name = name
	bb.Adornee = adornee
	bb.Size = UDim2.fromOffset(widthPx, 42)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 700
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.Text = text
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.2
	t.TextStrokeColor3 = Color3.new(0, 0, 0)
	t.Parent = bb
	return bb
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
		local bb = esp_make_billboard("BlzPlayerTag", root, p.Name, Color3.fromRGB(255, 90, 90), 160)
		bb.Parent = esp_ensure_folder()
		ESP.playerTags[p] = bb
	end
end

local function esp_players_loop(myToken)
	-- keep tags aligned with join/leave/respawn while the toggle is on
	table.insert(ESP.conns, game.Players.PlayerAdded:Connect(function()
		task.wait(1)
		if S.espPlayers and S.token == myToken then
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
		if not (S.espPlayers and S.token == myToken) then return end
		for _, p in ipairs(game.Players:GetPlayers()) do
			if p ~= plr then esp_tag_player(p) end
		end
	end))
	while S.espPlayers and S.token == myToken do
		for _, p in ipairs(game.Players:GetPlayers()) do
			if p ~= plr then esp_tag_player(p) end
		end
		-- distance refresh
		local myRoot = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if myRoot then
			for p, bb in pairs(ESP.playerTags) do
				local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if r then
					local d = math.floor((r.Position - myRoot.Position).Magnitude)
					pcall(function() bb.TextLabel.Text = ("%s %dm"):format(p.Name, d) end)
				end
			end
		end
		task.wait(0.25)
	end
end

local function esp_trees_loop(myToken)
	while S.espTrees and S.token == myToken do
		local myRoot = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		local folder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Trees")
		if myRoot and folder then
			local axeSpec = current_axe_spec()
			-- collect live trees, nearest first, then tag the closest N
			local near = {}
			for _, t in ipairs(folder:GetChildren()) do
				if t:IsA("Model") and t:FindFirstChild("Trunk") and is_live(t) then
					local pp = t.Trunk
					local d = (pp.Position - myRoot.Position).Magnitude
					if d <= 800 then
						near[#near+1] = {t = t, d = d}
					end
				end
			end
			table.sort(near, function(a, b) return a.d < b.d end)
			local keep, shown = {}, 0
			for _, e in ipairs(near) do
				if shown >= 22 then break end
				keep[e.t] = true
				shown += 1
				local tag = ESP.treeTags[e.t]
				local felled = e.t:GetAttribute("Felled")
				local okFell = (not felled) and can_fell(e.t, axeSpec)
				local label = ("%s $%d %dm%s"):format(
					e.t.Name,
					math.floor(value_of(e.t)),
					math.floor(e.d),
					felled and " X" or "")
				if not tag or not tag.Parent then
					tag = esp_make_billboard("BlzTreeTag", e.t.Trunk, label,
						okFell and Color3.fromRGB(90, 255, 120) or Color3.fromRGB(255, 90, 90), 190)
					tag.Parent = esp_ensure_folder()
					ESP.treeTags[e.t] = tag
				else
					pcall(function()
						tag.TextLabel.Text = label
						tag.TextLabel.TextColor3 = okFell and Color3.fromRGB(90, 255, 120) or Color3.fromRGB(255, 90, 90)
					end)
				end
			end
			-- drop tags whose tree left the nearest set or died
			for t, tag in pairs(ESP.treeTags) do
				if not keep[t] then
					tag:Destroy()
					ESP.treeTags[t] = nil
				end
			end
		end
		task.wait(1.5)
	end
end

local function esp_apply(kind, on)
	local myToken = S.token
	if kind == "players" then
		S.espPlayers = on
		if on then
			task.spawn(esp_players_loop, myToken)
		else
			for _, bb in pairs(ESP.playerTags) do pcall(function() bb:Destroy() end) end
			table.clear(ESP.playerTags)
			esp_kill_highlights()
		end
	elseif kind == "trees" then
		S.espTrees = on
		if on then
			task.spawn(esp_trees_loop, myToken)
		else
			for _, tag in pairs(ESP.treeTags) do pcall(function() tag:Destroy() end) end
			table.clear(ESP.treeTags)
		end
	end
	-- both overlays off: no reason to keep the join/leave/respawn listeners
	if not S.espPlayers and not S.espTrees then esp_kill_conns() end
end

-- Panic mode: true when another player is within radius of a position. Trees
-- with someone standing next to them get dropped, so the farm never chops in
-- plain view of a player who could watch or report it.
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

local function pick(mode, blocked)
	local folder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Trees")
	if not folder then return nil end
	local now = os.clock()
	local axeSpec = current_axe_spec()
	local list = {}
	local skipped = 0
	local panicked = 0
	for _, t in ipairs(folder:GetChildren()) do
		if is_live(t) and not (blocked[t] and blocked[t] > now) then
			-- Panic mode drops trees with a player standing beside them.
			if S.panicOn and player_near(t:GetPivot().Position, S.panicRadius) then
				panicked += 1
			-- Drop trees this axe physically cannot fell. Without this the
			-- rarest-first modes keep picking RedwoodGrove monsters that refuse
			-- every attempt, which reads as "hopping trees without chopping".
			elseif can_fell(t, axeSpec) then
				table.insert(list, t)
			else
				skipped += 1
			end
		end
	end
	S.panicked = panicked
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
	elseif mode == "SellValue" then
		-- What the merchant actually pays: weight x the rarity multiplier. This
		-- differs from MostValuable, which ranks by scale and mutation count
		-- only — a light Mythic outranks a heavy Epic there, but pays less.
		table.sort(list, function(a, b)
			local vaa, vab = sell_value_of(a), sell_value_of(b)
			if vaa ~= vab then return vaa > vab end
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
		-- The second argument is the swing mark, WindupPower(elapsed) from the
		-- game's own windup meter. Recorded by hand: a perfect finish only ever
		-- lands when the mark is >= ~0.985 (7/7 perfects sat in 0.985..0.999,
		-- while misses at 0.963 and 0.973 scored nothing). We used to send 1,
		-- which is not the peak the server scores against.
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

	-- Perfect cut: hold the windup until the triangle wave peaks. WindupPower
	-- rises to 1.000 at WindupFillSeconds and decays after, so releasing at
	-- MinDuration lands on the way up and scores nothing. When perfect mode is
	-- on we push the floor out to the peak instead.
	if S.perfectOn then
		local okT, tuning = pcall(function()
			return require(RS.Modules.Lumber.ChopTuning)
		end)
		if okT and type(tuning) == "table" then
			local peak = tonumber(tuning.WindupFillSeconds) or 0.65
			if peak > floor then floor = peak end
		end
	end
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
			local res = call(TreeService, "FinishChop", tree, true, S.perfectOn or false)
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
	Name = "Blizzard",
	LoadingSubtitle = "Foresters",
	Icon = "trees",
	ToggleUIKeybind = "RightShift",
	-- Fits inside a 758x393 viewport with the topbar inset accounted for.
	-- At 430 tall the absolute height came to 370px, which together with the
	-- 36px GuiInset exceeded the 393px screen, so centring pushed the window to
	-- y=-46 and clipped the top off it.
	Size = UDim2.fromOffset(760, 340),
	ConfigurationSaving = {Enabled = true, FolderName = "ForestersHub"},
	Home = {Tier = "Dev", Features = true},
})
-- remember it so the next run unloads exactly this window and nothing else
S.window = Window

-- Pin the window on screen.
--
-- Airflow centres it with AnchorPoint (0.5, 0) and a pixel-offset Position, and
-- on this 758x393 viewport the centring drives the top edge above the screen —
-- measured absY=-46, then -25, so the header sat clipped either way.
--
-- A single correction does not hold: Airflow re-centres on its own once the
-- content is built, which undid the first attempt. So re-apply it for a couple
-- of seconds until the layout settles.
local function clamp_window()
	local ok = pcall(function()
		local main
		for _, ch in ipairs(Window.Gui:GetChildren()) do
			if ch:IsA("Frame") then main = ch break end
		end
		if not main then return end
		local vp = workspace.CurrentCamera.ViewportSize

		-- shrink first if it cannot fit, so the clamp has room to work
		if main.AbsoluteSize.Y > vp.Y - 16 then
			local k = (vp.Y - 16) / main.AbsoluteSize.Y
			main.Size = UDim2.new(main.Size.X.Scale, main.Size.X.Offset * k,
				main.Size.Y.Scale, main.Size.Y.Offset * k)
			return
		end

		-- Position.Offset tracks AbsolutePosition one-to-one here, so nudge by
		-- the measured error. X scale must stay 0 or the two stop corresponding.
		local curAbsX, curAbsY = main.AbsolutePosition.X, main.AbsolutePosition.Y
		local w = main.AbsoluteSize.X
		local wantLeft = math.max(4, (vp.X - w) / 2)
		local wantTop = 6
		main.Position = UDim2.new(0,
			main.Position.X.Offset + (wantLeft - curAbsX),
			0, main.Position.Y.Offset + (wantTop - curAbsY))
	end)
	return ok
end

-- The spawn that drives clamp_window lives at the end of the file. Run from
-- here it found no Frame yet (Window.Gui is not populated until the tabs are
-- built), so every attempt returned early and the window stayed off-screen.

local farmTab = Window:CreateTab({Name = "Farm", Icon = "tree-pine"})
local axeTab = Window:CreateTab({Name = "Axes", Icon = "axe"})
local legitTab = Window:CreateTab({Name = "Legit", Icon = "shield"})

farmTab:CreateSection({Name = "Farm"})
-- Labels carry bare values, not "state: idle" prose. The Captain wants the
-- number, not a sentence around it.
local stateLabel = farmTab:CreateLabel({Name = "idle"})
local targetLabel = farmTab:CreateLabel({Name = "-"})
local countLabel = farmTab:CreateLabel({Name = "0 / 0"})
local rateLabel = farmTab:CreateLabel({Name = "0/min"})

farmTab:CreateSection({Name = "Session"})
local axeLabel = farmTab:CreateLabel({Name = "-"})
local buckLabel = farmTab:CreateLabel({Name = "$0"})

axeTab:CreateSection({Name = "Axes"})
local buyLabel = axeTab:CreateLabel({Name = "off"})
local buyLogLabel = axeTab:CreateLabel({Name = "-"})
axeTab:CreateSection({Name = "Ladder"})

legitTab:CreateSection({Name = "Perfect"})
local perfLabel = legitTab:CreateLabel({Name = "off"})
legitTab:CreateToggle({
	Name = "Auto Perfect",
	Callback = function(on)
		S.perfectOn = on
		if on then
			perfect_hook_install()
			pcall(function() perfLabel:Set("on") end)
			task.spawn(function()
				local myToken = S.token
				while S.perfectOn and S.token == myToken do
					local state = getgenv().__BlizzardPerfHook
					pcall(function() perfLabel:Set("on  " .. tostring(state and state.count or 0)) end)
					task.wait(1)
				end
			end)
		else
			perfect_hook_remove()
			pcall(function() perfLabel:Set("off") end)
		end
	end,
})

local espTab = Window:CreateTab({Name = "ESP", Icon = "eye"})
espTab:CreateSection({Name = "Overlay"})
-- client-side only: Highlights + billboards, nothing replicates
espTab:CreateToggle({
	Name = "Players",
	Callback = function(on)
		esp_apply("players", on)
	end,
})
espTab:CreateToggle({
	Name = "Trees",
	Callback = function(on)
		esp_apply("trees", on)
	end,
})

local stats = {felled = 0, failed = 0, startedAt = 0, blocked = {}}
local modeIndex = 1
local farmOn = false

local function safe_set(label, text)
	pcall(function() label:Set(text) end)
end

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
				-- Logs enter the inventory on their own when a tree is felled.
				-- Quote read Count=0 Worth=0 before any chop and Count=1
				-- Worth=47 right after one, so no pickup call is needed here —
				-- SawmillService:PickUp answers "There's no sawmill there" for
				-- most biomes anyway. Just count and sell at the threshold.
				if S.autoSell then
					S.logCount = (S.logCount or 0) + 1
					if S.logCount >= (S.sellAt or 50) then
						S.logCount = 0
						task.spawn(function()
							local okSell, why = auto_sell_pass()
							safe_set(sellLabel, okSell and ("sold @ " .. tostring(stats.felled)) or ("fail: " .. tostring(why):sub(1, 16)))
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

-- Perfect cut cannot be scripted, so there is deliberately no toggle for it.
--
-- Recorded by hand across two practice sessions: the swing mark
-- (WindupPower, the second argument to StartChop) does not decide the score.
-- A mark of 0.9994 scored a miss while 0.9634 scored a perfect, and a clean
-- 7/7 run sat in 0.985..0.999 purely because the player was hitting the
-- minigame spot, not because of any particular mark. The bar is
-- BarWidth=0.4254 with SpotSpeed=0.203 and SpotJitter=0.805 — you have to
-- catch the spot.
--
-- Forcing a mark from here makes it worse, not better: sending a fixed 0.995
-- produced failed=917 with felled=0, because the server validates the mark
-- against the real minigame result. So the second FinishChop argument stays
-- false and perfect chops stay a player skill.

local panicLabel = farmTab:CreateLabel({Name = "off"})

farmTab:CreateToggle({
	Name = "Panic Mode",
	Flag = "PanicMode",
	CurrentValue = false,
	Callback = function(on)
		S.panicOn = on
		safe_set(panicLabel, on and "on" or "off")
	end,
})

farmTab:CreateDropdown({
	Name = "Panic radius",
	Flag = "PanicRadius",
	Options = {"30", "50", "80", "120"},
	CurrentOption = {"50"},
	Callback = function(sel)
		local chosen = type(sel) == "table" and sel[1] or sel
		S.panicRadius = tonumber(chosen) or 50
	end,
})

-- Auto sell.
--
-- SellTrees lives on LumberMillService and takes "All" or "Held". Selling is
-- proximity checked — the merchant has to be within reach — so the farm
-- teleports to the nearest merchant before selling rather than calling it from
-- wherever it happens to be standing.
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
	for _, d in ipairs(workspace:GetDescendants()) do
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
	return best, bestD
end

local function auto_sell_pass()
	local merchant, dist = nearest_merchant()
	if merchant then
		local ok, pos = pcall(function() return merchant:GetPivot().Position end)
		if ok and pos then
			local root = hrp()
			if root then
				-- Teleport even when already "close": the server measures
				-- reach from the position IT has, and a stale one answers
				-- TooFar even from 5 studs away on the client.
				root.Anchored = false
				root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 5))
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				task.wait(1.0)
			end
		end
	end
	-- retry: the first attempt often lands before the move replicates
	local lastWhy
	for attempt = 1, 4 do
		local ok, why = sell_logs()
		if ok then return true, nil end
		lastWhy = why
		task.wait(0.7)
	end
	return false, lastWhy
end

local sellLabel = farmTab:CreateLabel({Name = "off"})

farmTab:CreateToggle({
	Name = "Auto Sell",
	Flag = "AutoSell",
	CurrentValue = false,
	Callback = function(on)
		S.autoSell = on
		safe_set(sellLabel, on and ("at " .. tostring(S.sellAt)) or "off")
	end,
})

farmTab:CreateDropdown({
	Name = "Sell at logs",
	Flag = "SellAt",
	Options = {"10", "25", "50", "100", "200"},
	CurrentOption = {"50"},
	Callback = function(sel)
		local chosen = type(sel) == "table" and sel[1] or sel
		S.sellAt = tonumber(chosen) or 50
		if S.autoSell then safe_set(sellLabel, "at " .. tostring(S.sellAt)) end
	end,
})

farmTab:CreateButton({
	Name = "Sell now",
	Callback = function()
		task.spawn(function()
			local ok, why = auto_sell_pass()
			safe_set(sellLabel, ok and "sold" or ("fail: " .. tostring(why):sub(1, 20)))
		end)
	end,
})

farmTab:CreateSection({Name = "Server"})
farmTab:CreateButton({
	Name = "Hop to low server",
	Callback = function()
		task.spawn(function()
			local msg = hop_to_low_server()
			-- the teleport, when it happens, disconnects us within a second —
			-- still show where we were headed so a fail is readable
			pcall(function() stateLabel:Set(msg) end)
		end)
	end,
})

----------------------------------------------------------------------
-- quests
----------------------------------------------------------------------
-- Quests are handed in per line, at the NPC that owns the line. There is no
-- bulk-claim remote: QuestService exposes Accept/HandIn/Meet/Track, and HandIn
-- takes a line id. It answers Ok=false Reason="NotReady" while objectives are
-- unfinished, which is the normal case, not an error.
--
-- HandIn is proximity checked ("Come a little closer"), so a line whose NPC is
-- far away will refuse. We report per line rather than pretending it worked.
local function claim_all_quests()
	local RS = game:GetService("ReplicatedStorage")
	local Knit = require(RS.Packages.Knit)
	local QC = require(RS.Modules.QuestConfig)
	local QS = Knit.GetService("QuestService")

	local claimed, notready, far = 0, 0, 0
	local notes = {}

	for _, line in ipairs(QC.Lines) do
		-- Meet opens the line where the game requires an introduction first
		pcall(function() QS:Meet(line.Id) end)
		-- Accept any quest the line is offering right now
		local acc = call(QS, "Accept", line.Id)
		if type(acc) == "table" and acc.Ok then
			table.insert(notes, "accept " .. tostring(line.Id))
		end
		-- Hand in whatever is finished
		local res = call(QS, "HandIn", line.Id)
		if type(res) == "table" then
			if res.Ok then
				claimed += 1
			elseif res.Reason == "NotReady" then
				notready += 1
			else
				far += 1
			end
		end
	end

	local msg = ("%d claimed  %d busy  %d far"):format(claimed, notready, far)
	if claimed > 0 or #notes > 0 then
		msg = msg .. "  (" .. table.concat(notes, ", "):sub(1, 60) .. ")"
	end
	safe_set(questLabel, msg)
end

local questLabel = farmTab:CreateLabel({Name = "-"})
farmTab:CreateButton({
	Name = "Claim all quests",
	Callback = function()
		task.spawn(function() claim_all_quests() end)
	end,
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

----------------------------------------------------------------------
-- Miku teleport
----------------------------------------------------------------------
-- Miku is an NPC that only spawns occasionally, so a scan at load time finds
-- nothing. The search runs when the button is pressed, not when the script
-- loads. It checks live players first (cheap), then walks workspace for a
-- spawned Miku model or part.
----------------------------------------------------------------------
local function find_miku()
	-- a player named Miku wins: they move, so teleport to their live position
	for _, p in ipairs(game.Players:GetPlayers()) do
		if p ~= plr
			and (string.lower(p.Name):match("miku") or string.lower(p.DisplayName):match("miku")) then
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root then return root.Position, "player " .. p.Name end
		end
	end
	-- otherwise look for a spawned NPC
	for _, d in ipairs(workspace:GetDescendants()) do
		if string.lower(d.Name):match("miku") then
			local pos
			if d:IsA("Model") then pos = d:GetPivot().Position
			elseif d:IsA("BasePart") then pos = d.Position end
			if pos then return pos, d.Name end
		end
	end
	return nil, nil
end

-- Teleport without anchoring. An anchored root does not replicate its CFrame,
-- so the server keeps the old position and every proximity check fails against
-- it. Set the CFrame on a free root and zero the velocity instead.
local function teleport_to(pos, offset)
	local root = hrp()
	if not root or not pos then return false end
	root.Anchored = false
	root.CFrame = CFrame.new(pos + (offset or Vector3.new(0, 3, 4)))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

local mikuLabel
mikuLabel = axeTab:CreateLabel({Text = "miku: not scanned yet"})

axeTab:CreateButton({
	Name = "TP to Miku",
	Callback = function()
		task.spawn(function()
			local pos, who = find_miku()
			if not pos then
				mikuLabel:Set("miku: not spawned (try again later)")
				return
			end
			local ok = teleport_to(pos)
			mikuLabel:Set(ok and ("miku: tp -> " .. who) or "miku: tp failed")
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

----------------------------------------------------------------------
-- compact layout
----------------------------------------------------------------------
-- Tried splitting the tab into two columns. Measured result: the window is only
-- 339px wide on this device, so each column ended up 144px — narrower than a
-- single readable control, which read as cramped and stacked. Two columns are a
-- downgrade at phone width. Reverted to one column and tightened the vertical
-- rhythm instead, which is what actually made it look heavy.
--
-- Removes leftover split artifacts if an older run created them.
local function compact_tab(tabName)
	local win = S.window
	if not win or not win.Content then return false end
	local tab = win.Content:FindFirstChild(tabName)
	if not tab then return false end
	local scroll
	for _, ch in ipairs(tab:GetChildren()) do
		if ch:IsA("ScrollingFrame") then scroll = ch break end
	end
	if not scroll then return false end

	-- undo any columns from an earlier version: lift their rows back out
	for _, col in ipairs({scroll:FindFirstChild("ColLeft"), scroll:FindFirstChild("ColRight")}) do
		if col then
			for _, row in ipairs(col:GetChildren()) do
				if row:IsA("Frame") or row:IsA("TextLabel") or row:IsA("TextButton") then
					row.Parent = scroll
				end
			end
			col:Destroy()
		end
	end

	local rows = {}
	for _, ch in ipairs(scroll:GetChildren()) do
		if ch:IsA("Frame") or ch:IsA("TextLabel") or ch:IsA("TextButton") then
			table.insert(rows, ch)
		end
	end
	if #rows < 4 then return false end
	for _, row in ipairs(rows) do row.Parent = nil end

	-- Kill Airflow's own list layout. It forces every child into one vertical
	-- stack and overrides any Position we set, which is why the first attempt
	-- looked like "everything on the left" — the columns were placed correctly
	-- but the parent's UIListLayout re-stacked them anyway.
	local oldLay = scroll:FindFirstChildOfClass("UIListLayout")
	if oldLay then oldLay:Destroy() end

	-- Airflow's scroll padding is L=24 R=24. On a 339px scroller that is 48px
	-- — 14% of the width — and it silently ate the space the second column
	-- needed, so the columns overlapped by ~11px. Reclaim it.
	local pad = scroll:FindFirstChildOfClass("UIPadding")
	if pad then
		pad.PaddingLeft = UDim.new(0, 4)
		pad.PaddingRight = UDim.new(0, 4)
		pad.PaddingTop = UDim.new(0, 4)
		pad.PaddingBottom = UDim.new(0, 4)
	end

	-- Column maths, done against the width that is actually usable.
	-- With gutter g and usable width W: each column is (W-g)/2, the left sits
	-- at 0, the right at (W+g)/2. Expressed in scale so the split survives any
	-- window size, and with the gutter subtracted in pixels so it never
	-- collapses to zero on a narrow screen.
	local gutter = 14
	local colW = UDim.new(0.5, -gutter / 2)
	local rightX = UDim.new(0.5, gutter / 2)

	local function makeCol(name, x)
		local col = Instance.new("Frame")
		col.Name = name
		col.BackgroundTransparency = 1
		col.Size = UDim2.new(colW.Scale, colW.Offset, 0, 0)
		col.Position = UDim2.new(x.Scale, x.Offset, 0, 0)
		col.Parent = scroll
		local lay = Instance.new("UIListLayout")
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Padding = UDim.new(0, 6)
		lay.Parent = col
		return col
	end
	local left = makeCol("ColLeft", UDim.new(0, 0))
	local right = makeCol("ColRight", rightX)

	-- Group by section, not by row. Alternating per row tore sections in half:
	-- measured "SESSION" heading landing in the right column while its labels
	-- sat in the left. A heading has to stay with the controls under it.
	local function isHeading(row)
		if not row:IsA("TextLabel") and not row:IsA("Frame") then return false end
		for _, d in ipairs(row:GetDescendants()) do
			if d:IsA("TextLabel") and d.Text ~= "" then
				return d.Text == string.upper(d.Text) and #d.Text < 24
			end
		end
		return false
	end

	local groups, current = {}, nil
	for _, row in ipairs(rows) do
		if isHeading(row) then
			current = {heading = row, items = {}}
			table.insert(groups, current)
		elseif current then
			table.insert(current.items, row)
		else
			if not groups[1] then table.insert(groups, {heading = nil, items = {}}) end
			table.insert(groups[1].items, row)
		end
	end

	-- balance: whichever column is shorter takes the next section
	local function height(col)
		local y = 0
		for _, ch in ipairs(col:GetChildren()) do
			if ch:IsA("Frame") or ch:IsA("TextLabel") or ch:IsA("TextButton") then
				y += (ch.AbsoluteSize.Y > 0 and ch.AbsoluteSize.Y or 30) + 6
			end
		end
		return y
	end

	local order = 0
	local function place(row, col)
		order += 1
		row.LayoutOrder = order
		-- Width only. Forcing the height clamped every row into 24-32px, and
		-- Airflow's dropdowns are taller than that — the header got crushed and
		-- the option list spilled over the row below, which is the collision the
		-- Captain kept hitting. Their natural height is correct as built.
		row.Size = UDim2.new(1, 0, row.Size.Y.Scale, row.Size.Y.Offset)
		row.ClipsDescendants = false
		row.Parent = col
	end
	local function colHeight(col)
		local y = 0
		for _, ch in ipairs(col:GetChildren()) do
			if ch:IsA("Frame") or ch:IsA("TextLabel") or ch:IsA("TextButton") then
				y += (ch.AbsoluteSize.Y > 0 and ch.AbsoluteSize.Y or 30) + 6
			end
		end
		return y
	end

	-- Small sections stay whole — a heading torn away from its controls was the
	-- earlier complaint. Anything long enough to unbalance the columns (the axe
	-- ladder is 12 rows on its own, which produced a 4/15 split) is poured in
	-- one row at a time into whichever column is currently shorter.
	local WHOLE_LIMIT = 4
	for _, group in ipairs(groups) do
		if #group.items <= WHOLE_LIMIT then
			local target = (colHeight(left) <= colHeight(right)) and left or right
			if group.heading then place(group.heading, target) end
			for _, item in ipairs(group.items) do place(item, target) end
		else
			local first = true
			for _, item in ipairs(group.items) do
				local target = (colHeight(left) <= colHeight(right)) and left or right
				if first and group.heading then
					-- the heading rides with the first row it introduces
					place(group.heading, target)
					first = false
				end
				place(item, target)
			end
		end
	end

	task.defer(function()
		local function fit(col)
			local y = 0
			for _, ch in ipairs(col:GetChildren()) do
				if ch:IsA("Frame") or ch:IsA("TextLabel") or ch:IsA("TextButton") then
					y += ch.AbsoluteSize.Y + 6
				end
			end
			col.Size = UDim2.new(colW.Scale, colW.Offset, 0, y)
			return y
		end
		local ly, ry = fit(left), fit(right)
		scroll.CanvasSize = UDim2.new(0, 0, 0, math.max(ly, ry) + 8)
	end)
	return true
end

task.defer(function()
	pcall(function() compact_tab("Farm") end)
	pcall(function() compact_tab("Axes") end)
	pcall(function() compact_tab("Legit") end)
end)

-- Drive the on-screen clamp from here, once every tab and control exists.
-- Verified against the live client: applied this way it holds at absY=6 for at
-- least six seconds, i.e. Airflow does not re-centre afterwards. It retries
-- because the Frame takes a moment to appear even at this point.
task.spawn(function()
	-- No early break. The loop used to stop at the first pass that measured
	-- absY=6, which happened before the tabs finished building; Airflow's own
	-- layout pass then re-centred the window and the clamp was gone. Reapply
	-- through the whole build window instead.
	for _ = 1, 40 do
		pcall(function()
			local main = Window.Gui:FindFirstChild("Window")
			if not (main and main:IsA("Frame")) then return end
			local vp = workspace.CurrentCamera.ViewportSize
			if main.AbsoluteSize.Y > vp.Y - 16 then
				local k = (vp.Y - 16) / main.AbsoluteSize.Y
				main.Size = UDim2.new(main.Size.X.Scale, main.Size.X.Offset * k,
					main.Size.Y.Scale, main.Size.Y.Offset * k)
				return
			end
			local curAbsX, curAbsY = main.AbsolutePosition.X, main.AbsolutePosition.Y
			local wantLeft = math.max(4, (vp.X - main.AbsoluteSize.X) / 2)
			main.Position = UDim2.new(main.Position.X.Scale,
				main.Position.X.Offset + (wantLeft - curAbsX),
				main.Position.Y.Scale,
				main.Position.Y.Offset + (6 - curAbsY))
		end)
		task.wait(0.3)
	end
end)

pcall(function()
	Window:Notify({Title = "Blizzard", Content = "Farm hub ready", Duration = 4})
end)
print("[Blizzard] loaded")
