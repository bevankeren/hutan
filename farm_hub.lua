-- Blizzard farm hub for Foresters — OuroFlow UI (Airflow fork, joustingmatch/-3)
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
-- The fork adds native two-column groupboxes, self-refreshing statuses and
-- rich-text labels, which replaces the old single-column tabs plus the
-- compact_tab surgery this script used to perform on its own UI.
local Airflow = loadstring(game:HttpGet("https://raw.githubusercontent.com/joustingmatch/-3/refs/heads/main/Source.luau"))()

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
-- ESP settings live here and are read by the loops every tick, so slider and
-- dropdown changes apply without restarting any overlay
S.esp = S.esp or {}
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
-- Trees are tagged with rich-text billboards, never Highlights (Roblox renders
-- at most ~31 Highlights at once and a forest has far more trees than that).
-- Each tag reads the live game data: species in the rarity's own colour, worth
-- in a money band (grey → lime → gold → pink as the price climbs), rarity,
-- mutations by name, distance, and a red X when the held axe cannot fell the
-- tree at all. Players get a Highlight plus a name+distance tag that turns red
-- inside the panic radius. Merchants get gold tags. Every visual knob lives in
-- S.esp and is read per tick, so UI changes land without restarting overlays.

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

-- colour helpers ------------------------------------------------------------

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

-- money bands: the eye reads price classes faster than exact numbers, and the
-- exact number is on the tag anyway
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

-- billboard factory ----------------------------------------------------------

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

-- refresh an existing tag in place (text + size + range) instead of rebuilding
local function esp_refresh_tag(bb, richText)
	if not bb or not bb.Parent then return end
	pcall(function()
		bb.MaxDistance = espCfg.maxDist
		local t = bb.Text
		t.TextSize = espCfg.textSize
		t.Text = richText
	end)
end

-- tag text builders ----------------------------------------------------------

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
		local muts = t:GetAttribute("Mutations")
		if type(muts) == "table" then
			for _, idx in ipairs(muts) do
				local mi = mutation_info(idx)
				if mi then
					l2[#l2+1] = ('<font color="%s">%s</font>'):format(
						hex(mi.Color or Color3.new(1, 1, 1)), mi.Name:sub(1, 5))
				end
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

-- overlays -------------------------------------------------------------------

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
			for _, d in ipairs(workspace:GetDescendants()) do
				if d:IsA("Model") and d.Name:lower():match("merchant") and not seen[d] then
					local ok, pos = pcall(function() return d:GetPivot().Position end)
					if ok and pos then
						seen[d] = true
						local dist = (pos - myRoot.Position).Magnitude
						if dist <= espCfg.maxDist then
							local tag = ESP.merchTags[d]
							-- the travelling merchant is the bare "Merchant" model
							-- (the notice calls her Miku); permanent ones are
							-- "<Name> the Merchant", so trim to the first name
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
	-- every overlay off: no reason to keep the join/leave/respawn listeners
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

-- The ladder is built once at load: shop positions come from AxeView-tagged
-- prompts and prices from AxePrice. The UI statuses below read it on their
-- refresh timers, so it has to exist before the UI block.
local ladder = axe_ladder()
local axeRows = {}

----------------------------------------------------------------------
-- ui
----------------------------------------------------------------------
local Window = Airflow:CreateWindow({
	Name = "Blizzard",
	LoadingSubtitle = "Foresters",
	Icon = "trees",
	ToggleUIKeybind = "RightShift",
	Size = UDim2.fromOffset(760, 340),
	Density = "Compact",
	ConfigurationSaving = {Enabled = true, FolderName = "ForestersHub"},
})
-- remember it so the next run unloads exactly this window and nothing else
S.window = Window

-- No clamp_window here any more. The old hack fought the original Airflow's
-- centring with a reposition loop; the fork scales itself to the screen
-- (AdaptiveSize) and keeps its own margins, so the fight is gone.

local farmTab = Window:CreateTab({Name = "Farm", Icon = "tree-pine"})
local axeTab = Window:CreateTab({Name = "Axes", Icon = "axe"})
local legitTab = Window:CreateTab({Name = "Legit", Icon = "shield"})
local espTab = Window:CreateTab({Name = "ESP", Icon = "eye"})

-- Two columns are native in the fork: groupboxes dock Left/Right, which is
-- what the old compact_tab surgery was imitating by hand.
local gbFarm = farmTab:CreateGroupbox({Name = "Farming", Side = "Left"})
local gbQuest = farmTab:CreateGroupbox({Name = "Quests", Side = "Left"})
local gbSession = farmTab:CreateGroupbox({Name = "Session", Side = "Right"})
local gbServer = farmTab:CreateGroupbox({Name = "Server", Side = "Right"})

local gbAxes = axeTab:CreateGroupbox({Name = "Shop", Side = "Left"})
local gbLadder = axeTab:CreateGroupbox({Name = "Buy ladder", Side = "Right"})
local gbUtil = axeTab:CreateGroupbox({Name = "Utilities", Side = "Left"})

local gbPerfect = legitTab:CreateGroupbox({Name = "Perfect", Side = "Left"})

local gbEsp = espTab:CreateGroupbox({Name = "Overlay", Side = "Left"})
local gbEspStyle = espTab:CreateGroupbox({Name = "Style", Side = "Right"})

-- loop counters must exist before the UI closures below read them
local stats = {felled = 0, failed = 0, startedAt = 0, blocked = {}}
local modeIndex = 1
local farmOn = false

local function safe_set(label, text)
	pcall(function() label:Set(text) end)
end

-- Labels carry bare values, not "state: idle" prose. The Captain wants the
-- number, not a sentence around it.
local stateLabel = gbFarm:CreateStatus({Name = "State", Style = "Dot", Value = "idle"})
local targetLabel = gbFarm:CreateLabel("-")
local countLabel = gbFarm:CreateStatus({Name = "Chopped", Style = "Row", Value = "0 / 0"})
local rateLabel = gbFarm:CreateStatus({Name = "Rate", Style = "Row", Value = "0/min"})

local axeLabel = gbSession:CreateStatus({Name = "Axe", Style = "Row", Value = "-"})
local buckLabel = gbSession:CreateStatus({Name = "Bucks", Style = "Row", Value = "$0"})
local sellLabel = gbSession:CreateLabel("off")
local hopLabel = gbServer:CreateLabel("idle")
local questLabel = gbQuest:CreateLabel("-")

local buyLabel = gbAxes:CreateStatus({Name = "Auto buy", Style = "Row", Value = "off"})
local buyLogLabel = gbAxes:CreateLabel("-")
-- live shop snapshot, refreshed by the fork's status timers (all reads are
-- client-side: character scan, leaderstats, the prebuilt ladder table)
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
					return ("%s $%d ready"):format(axe.name, axe.price), "Success"
				end
				return ("%s $%d · %d%% saved"):format(
					axe.name, axe.price, math.floor(math.min(b / axe.price, 1) * 100)), "Warning"
			end
		end
		return "ladder complete", "Success"
	end,
})
local mikuLabel = gbUtil:CreateLabel("miku: not scanned yet")

local perfLabel = gbPerfect:CreateStatus({Name = "Auto Perfect", Style = "Row", Value = "off"})

gbPerfect:CreateToggle({
	Name = "Auto Perfect",
	Flag = "AutoPerfect",
	CurrentValue = false,
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

-- client-side only: Highlights + billboards, nothing replicates
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

-- style knobs are read by the loops every tick, so nothing needs restarting
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
	-- No-clip is OFF on purpose and must stay off: the server rejects StartChop
	-- from a non-collidable character, which is what produced an endless stream
	-- of "Get closer to the tree" refusals. Keep a normal, solid character.
	noclipOn = false
	restore_collide()
	refresh_state()

	task.spawn(function()
		while S.farm and alive() do
			local ok, msg = pcall(function()
				-- a sell pass owns the character right now (merchant teleport
				-- plus SellTrees proximity check); chopping would yank the root
				-- away mid-call and every sell would land "TooFar"
				if S.selling then
					task.wait(0.25)
					return "selling in progress"
				end
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
				-- Worth=47 right after one, so no pickup call is needed here.
				--
				-- Sell threshold counts HELD LOGS, not felled trees: one tree
				-- yields several logs, so a tree counter sold at "50" only
				-- once the inventory was well past 80. Quote.Count is the
				-- server's held-log count and is readable from anywhere; the
				-- old tree counter stays as fallback when Quote misbehaves.
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
						-- one sell pass at a time, and the farm loop stands down
						-- while it runs (see the S.selling check above): without
						-- that, every felled tree spawned another pass because
						-- Quote never dropped, and the passes fought the farm's
						-- teleports — label pinned on "selling…" forever
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
-- The Auto Perfect toggle now plays the real minigame path instead; see
-- README_LEGIT.md.

gbFarm:CreateToggle({
	Name = "Panic Mode",
	Flag = "PanicMode",
	CurrentValue = false,
	Callback = function(on)
		S.panicOn = on
	end,
})

gbFarm:CreateSlider({
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

gbServer:CreateButton({
	Name = "Hop to low server",
	Callback = function()
		task.spawn(function()
			local msg = hop_to_low_server()
			-- the teleport, when it happens, disconnects us within a second —
			-- still show where we were headed so a fail is readable
			safe_set(hopLabel, msg)
		end)
	end,
})
gbServer:CreateLabel("server listed via games API")

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

gbQuest:CreateButton({
	Name = "Claim all quests",
	Callback = function()
		task.spawn(function() claim_all_quests() end)
	end,
})

----------------------------------------------------------------------
-- axe ladder ui
----------------------------------------------------------------------
local autobuyOn = false

-- owned axes get disabled so the ladder reads as a progress bar: greyed rows
-- behind you, live rows ahead
local function refresh_ladder()
	local own = owned_axes()
	local eq = equipped_axe()
	for _, row in ipairs(axeRows) do
		local isOwned = own[row.axe.id] == true
		local tag = isOwned and (eq == row.axe.id and "  [equipped]" or "  [owned]") or ""
		row.button:SetText(("%s  $%d  power %.1f%s"):format(row.axe.name, row.axe.price, row.axe.power, tag))
		pcall(function() row.button:SetDisabled(isOwned) end)
	end
	refresh_axe_info()
end

for _, axe in ipairs(ladder) do
	local button = gbLadder:CreateButton({
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

----------------------------------------------------------------------
-- Miku teleport
----------------------------------------------------------------------
-- Miku is the travelling merchant. Verified live: her rig is parked as a
-- Model literally named "Merchant" directly under workspace.Map.NPCs while
-- her visit lasts (Humanoid + R6 parts + TalkPrompt), and the join notice
-- calls her Miku — the model itself never carries that name. The permanent
-- island merchants are named "<Name> the Merchant", so the exact child name
-- "Merchant" is unambiguous. A player named Miku is also accepted, and the
-- old workspace-wide name scan stays as a last resort.
----------------------------------------------------------------------
local function find_miku()
	-- the join notice calls her Miku, but the rig is named "Merchant".
	-- Verified live: one Model named "Merchant" sits directly under
	-- workspace.Map.NPCs while her visit lasts (R6 + HumanoidRootPart +
	-- TalkPrompt); permanent shops are "<Name> the Merchant", so the exact
	-- name is unambiguous.
	local npcs = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("NPCs")
	if npcs then
		local m = npcs:FindFirstChild("Merchant")
		if m and m:IsA("Model") then
			local root = m:FindFirstChild("HumanoidRootPart")
			if root then return root.Position, "Miku (travelling merchant)" end
			local ok, pos = pcall(function() return m:GetPivot().Position end)
			if ok and pos then return pos, "Miku (travelling merchant)" end
		end
	end
	-- a player named Miku wins too: they move, so teleport to their live position
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

gbUtil:CreateButton({
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

gbAxes:CreateParagraph({
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

pcall(function()
	Window:Notify({Title = "Blizzard", Content = "Farm hub ready", Duration = 4})
end)
print("[Blizzard] loaded")
