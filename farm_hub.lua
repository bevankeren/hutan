
local Airflow = loadstring(game:HttpGet("https://raw.githubusercontent.com/joustingmatch/-3/refs/heads/main/Source.luau"))()
-- *Airflow.Flags is per library instance, so expose this one: the config sync reads
-- the same table that actually owns the elements' flags*
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

local AxeConfig = require(RS.Modules.Lumber.AxeConfig)
local AxePrice = require(RS.Modules.Lumber.AxePrice)
local ChopTuning = require(RS.Modules.Lumber.ChopTuning)

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
		local ok, old = pcall(function() return getgenv().ForestFarm end)
		if ok and type(old) == "table" and type(old.stop) == "function" then
			pcall(old.stop)
		end
	end
	pcall(function()
		local state = getgenv().__BlizzardPerfHook
		if state and type(state.old) == "function" then
			TreeService.FinishChop = state.old
		end
		getgenv().__BlizzardPerfHook = nil
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
S.esp = S.esp or {}
-- farm filter: only chop trees at or above this rarity tier
if type(S.minTier) ~= "number" then S.minTier = 0 end
S.refreshRate = tonumber(S.refreshRate) or 1
S.topSort = type(S.topSort) == "string" and S.topSort or "Money"
S.minValue = tonumber(S.minValue) or 0
S.maxRows = tonumber(S.maxRows) or 8
S.weightValue = type(S.weightValue) == "number" and S.weightValue or 0.6
S.includeGrowing = S.includeGrowing == true
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

local HUG_OFFSET = 5
local STAND_HEIGHT = 1

local attachYaw = 0

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
			pcall(function() hum:EquipTool(c) end)
			for _ = 1, 12 do
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

-- *calibrated live against LumberMillService:Quote deltas — payout is linear in Weight,
-- and slope/PricePerTonne measured 1.797..1.828 across four biomes = WoodConfig.ValueScale*
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

-- rarity ladder straight out of the game's config, ordered by Tier
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

-- *Mutations is a comma-separated STRING on live trees ("Golden"), not a table —
-- the old build only read tables, so every mutation bonus and chance was silently dropped*
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

-- Weight is kilograms: /1000 lands exactly on the species' Tonnes figure
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

-- *real spawn odds straight from the game's own TreeRoll — no more invented 1/N*
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

-- *Growing trees keep their full Rarity/Weight/Scale attributes, so a Mythic can be
-- scouted before it is choppable. GrowStart is an os.time() epoch stamp, GrowSeconds
-- the duration — both verified against live trees.*
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

-- what the table may show: Ready, our own Locked, and Growing when the toggle is on
local function is_candidate(tree)
	if is_live(tree) then return true end
	return S.includeGrowing and is_growing(tree)
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

-- *"chance gede tp harga sampah" — a 1-in-a-million tree worth nothing is worth nothing, and a
-- heavy Common worth $40 beats a Mythic worth $30. Smart mode ranks by expected value per chop
-- (real price, real spawn odds), blended with rarity so a Mythic never loses to an Uncommon
-- by a hair. weightValue = 0 -> pure money, 1 -> pure rarity.*
local function top_score(t)
	local money = tree_value(t, S.perfectOn)
	if money <= 0 then return -1e18, money, 0 end
	-- *floor of $1: sub-dollar weed trees are never worth a teleport, and they were
	-- polluting the table whenever a big-odds roll landed on one*
	if money < 1 then return -1e17 + money, money, tree_odds(t) end
	local odds = tree_odds(t)
	local rare = 1 + tier_of(t:GetAttribute("Rarity"))
	local w = math.clamp(tonumber(S.weightValue) or 0.6, 0, 1)
	local moneyTerm = math.log10(1 + money)
	local rareTerm = math.log10(1 + odds) * 0.35 + math.log10(rare) * 2
	return (1 - w) * moneyTerm + w * rareTerm, money, odds
end

local function hop_to_low_server()
	local TS = game:GetService("TeleportService")
	local HS = game:GetService("HttpService")
	local here = #game.Players:GetPlayers()

	local fetch = (typeof(http_request) == "function" and http_request)
		or (typeof(request) == "function" and request)
		or nil
	if not fetch then
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
		return ("already among quietest (%d here, best %d)"):format(here, best.count)
	end

	task.spawn(function()
		pcall(function() TS:TeleportToPlaceInstance(game.PlaceId, best.id, plr) end)
	end)
	return ("hop: %d here -> %d/20"):format(here, best.count)
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
		-- *Mutations is a comma-separated string on live trees, so the old
		-- type(muts)=="table" guard silently hid every mutation tag*
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
			for _, d in ipairs(workspace:GetDescendants()) do
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
			if not passes_rarity(t) then
				-- *this is the bug the Captain saw: an Uncommon outranking a Mythic.
				-- the floor drops it out of the pool entirely before any sorting.*
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
			break
		end
	end
	if type(session) ~= "table" or not session.Ok then
		return false, (type(session) == "table" and session.Reason) or "start failed"
	end

	local floor = (session.Params and session.Params.MinDuration) or 1.2

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
		if (not S.farm and not S.sniping) or not alive() then
			return false, "cancelled"
		end
		if tree.Parent then
			local root = hrp()
			if root then
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		else
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
			if tostring(last):lower():match("fast") or tostring(last):lower():match("early") then
			elseif tostring(last) == "NotFelled" or tostring(last):lower():match("not") then
			else
				return false, tostring(last)
			end
		end

		if elapsed > 25 then
			return false, "timed out: " .. tostring(last)
		end
		task.wait(0.08)
	end

	return true, (finish and finish.Felled) and "felled" or "held"
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

local function buy_axe(axe)
	travel_to(axe.pos)
	local res = call(AxeService, "BuyAxe", axe.id)
	if type(res) == "table" and res.Ok then
		call(AxeService, "EquipAxe", axe.id)
		return true, "bought + equipped " .. axe.name
	end
	return false, (type(res) == "table" and res.Reason) or "buy failed"
end

local ladder = axe_ladder()
local axeRows = {}

local function teleport_to(pos, offset)
	local root = hrp()
	if not root or not pos then return false end
	root.Anchored = false
	root.CFrame = CFrame.new(pos + (offset or Vector3.new(0, 3, 4)))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

local Window = Airflow:CreateWindow({
	Name = "Blizzard",
	LoadingSubtitle = "Foresters",
	Icon = "trees",
	ToggleUIKeybind = "RightShift",
	AdaptiveSize = false,
	UIScale = 1.2,
	Density = "Default",
	Size = UDim2.fromOffset(585, 290),
	ConfigurationSaving = {Enabled = true, FolderName = "ForestersHub"},
})
S.window = Window

local farmTab = Window:CreateTab({Name = "Farm", Icon = "tree-pine"})
local axeTab = Window:CreateTab({Name = "Axes", Icon = "axe"})
local legitTab = Window:CreateTab({Name = "Legit", Icon = "shield"})
local espTab = Window:CreateTab({Name = "ESP", Icon = "eye"})
local settingsTab = Window:CreateTab({Name = "Settings", Icon = "settings"})

local gbConfig = settingsTab:CreateGroupbox({Name = "Configs", Side = "Left"})
local gbTheme = settingsTab:CreateGroupbox({Name = "Theme", Side = "Right"})

local gbTop = farmTab:CreateGroupbox({Name = "Top wood", Side = "Left"})
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
				-- *growing target: teleport now and camp it, so we chop the instant it
				-- flips to Ready instead of losing it to whoever wanders past*
				if is_growing(t) then
					safe_set(topLabel, ("camping %s — %s"):format(woodName, fmt_remaining(grow_remaining(t))))
					task.spawn(function()
						local okP, result = pcall(function()
							teleport_to(t.Trunk.Position, Vector3.new(0, 3, 5))
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
						local good, why = false, "threw"
						if okP then
							good, why = result, nil
							if type(result) == "table" then good, why = true, nil end
						end
						if good then
							safe_set(topLabel, ("sniped %s"):format(woodName))
						else
							safe_set(topLabel, ("fail: %s"):format(tostring(okP and why or result):sub(1, 22)))
						end
						S.sniping = false
					end)
					return
				end
				safe_set(topLabel, "sniping " .. woodName .. "…")
				task.spawn(function()
					local good, result
					local okP = pcall(function()
						local pos = t.Trunk.Position
						teleport_to(pos, Vector3.new(0, 3, 5))
						task.wait(0.4)
						good, result = chop_tree(t)
					end)
					if okP and good then
						safe_set(topLabel, ("sniped %s"):format(woodName))
					else
						safe_set(topLabel, "fail: " .. tostring(okP and result or "chop threw"):sub(1, 18))
					end
					S.sniping = false
				end)
			end,
		})
		-- *hidden rows are destroyed rather than left blank, so shrinking the count
		-- leaves no dead buttons between the last result and the controls below*
		pcall(function() row.button:SetVisible(false) end)
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
local panicLabel = gbFarm:CreateStatus({
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

local axeLabel = gbSession:CreateStatus({Name = "Axe", Style = "Row", Value = "-"})
local buckLabel = gbSession:CreateStatus({Name = "Bucks", Style = "Row", Value = "$0"})
local sellLabel = gbSession:CreateLabel("off")
local hopLabel = gbServer:CreateLabel("idle")
local questLabel = gbQuest:CreateLabel("-")

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
				if root.Position.Y < -100 then
					root.CFrame = CFrame.new(root.Position.X, 60, root.Position.Z)
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

-- *the rarity floor: an Uncommon can no longer outrank a Mythic, because below-tier
-- trees are dropped from the pool before anything is sorted*
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

-- *chance-vs-money dial: 0 chases raw $, 1 chases rarity, 0.6 is the balanced default*
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
	Range = {1, 5},
	Increment = 1,
	CurrentValue = S.refreshRate or 1,
	Suffix = "s",
	Flag = "RefreshRate",
	Callback = function(n) S.refreshRate = n end,
})

-- *growing trees keep their Rarity/Weight/Size, so a Mythic can be scouted before it
-- ripens: rows show a countdown and snipe camps the tree until it flips to Ready*
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
				root.Anchored = false
				root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 5))
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
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

gbServer:CreateButton({
	Name = "Hop to low server",
	Callback = function()
		task.spawn(function()
			local msg = hop_to_low_server()
			safe_set(hopLabel, msg)
		end)
	end,
})
gbServer:CreateLabel("server listed via games API")

local function claim_all_quests()
	local RS = game:GetService("ReplicatedStorage")
	local Knit = require(RS.Packages.Knit)
	local QC = require(RS.Modules.QuestConfig)
	local QS = Knit.GetService("QuestService")

	local claimed, notready, far = 0, 0, 0
	local notes = {}

	for _, line in ipairs(QC.Lines) do
		pcall(function() QS:Meet(line.Id) end)
		local acc = call(QS, "Accept", line.Id)
		if type(acc) == "table" and acc.Ok then
			table.insert(notes, "accept " .. tostring(line.Id))
		end
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

local autobuyOn = false

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

local function find_miku()
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
	for _, p in ipairs(game.Players:GetPlayers()) do
		if p ~= plr
			and (string.lower(p.Name):match("miku") or string.lower(p.DisplayName):match("miku")) then
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root then return root.Position, "player " .. p.Name end
		end
	end
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

-- *rows now lead with rarity and real money, because "1/N" alone made a 1-in-a-million
-- $6 tree outrank a $10k Mythic — the exact "halusinasi" the Captain called out*
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
	-- *a growing tree can't be chopped yet, so it carries its countdown instead of
	-- pretending to be snipeable — TP there early, then wait it out*
	local status = growing and ("  ⏳ Growing %s"):format(fmt_remaining(grow_remaining(t))) or ""
	return ("%s · %s · %s · %s%s%s%s%s"):format(
		rarity, fmt_val(money), wood, fmt_odds(odds), sizeTxt, mutTxt, status, d)
end

local function visible_top_rows()
	local n = math.floor(tonumber(S.maxRows) or 8)
	return math.clamp(n, 1, MAX_TOP_ROWS)
end

local lastTopLabelText = nil

-- *stable rendering: the old build reassigned every row by index each tick and called
-- SetText unconditionally, so a one-place shift in the ranking rewrote all 12 rows and
-- the whole table flashed. This diffs against what is already on screen and only
-- touches rows whose tree, text, visibility or disabled state actually changed.*
local rowState = {}

-- quantised so near-ties stop trading places every tick; TreeId is the fixed tiebreak
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

-- *hysteresis: a challenger must beat the incumbent by a margin before it takes the
-- slot. Without this, two near-equal trees swap places on every 1s tick and the table
-- crawls even though nothing meaningful changed.*
local RANK_EPSILON = 0.02
local lastOrder = {}
local lastGoodList = nil

local function apply_hysteresis(sorted)
	local out = {}
	local used = {}
	-- incumbents keep their slot unless clearly beaten
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
	-- fill any remaining slots in sorted order
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
					-- *sub-dollar trees are always junk regardless of the slider*
					if v >= minValue and v >= 1 then
						list[#list+1] = t
					end
				end
			end
			table.sort(list, function(a, b)
				local ka, kb = rank_key(a), rank_key(b)
				if ka ~= kb then return ka > kb end
				-- *stable tiebreak: TreeId never changes, so equal ranks never swap*
				return tree_sort_id(a) < tree_sort_id(b)
			end)
			list = apply_hysteresis(list)
			-- *a transient read that yields nothing must not blank a populated table:
			-- keep the previous list rather than flashing empty rows*
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
					-- *distance rounded to 10 studs so walking doesn't churn the text*
					local d
					if myRoot and t:FindFirstChild("Trunk") then
						d = math.floor((t.Trunk.Position - myRoot.Position).Magnitude / 10) * 10
					end
					local text = top_wood_row_text(t, d)
					if st.text ~= text then
						pcall(function() row.button:SetText(text) end)
						st.text = text
					end
					-- *a growing row would fail StartChop, so grey it out until it ripens*
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
					math.min(want, #list), #list, growTxt, mode, tonumber(S.refreshRate) or 1)
				if lastTopLabelText ~= txt then
					lastTopLabelText = txt
					safe_set(topLabel, txt)
				end
			end
		end
		task.wait(math.clamp(tonumber(S.refreshRate) or 1, 0.25, 10))
	end
end)

-- *config + theme managers use the library's own save system: every element with a
-- Flag is written to ForestersHub/<name>.json, autoload included*
pcall(function()
	settingsTab:CreateConfigManager({Name = "Configs", Side = "Left"})
end)
pcall(function()
	settingsTab:CreateThemeManager({Name = "Themes", Side = "Right"})
end)

-- *S is the value the farm loops actually read, and it is seeded before the UI exists.
-- A loaded config only fires each element's Callback, so without this the restored
-- values never reach S and the running farm silently keeps the defaults.*
local function sync_state_from_flags()
	local F = Airflow.Flags
	if type(F) ~= "table" or not next(F) then
		F = getgenv().__Airflow and getgenv().__Airflow.Flags
	end
	if type(F) ~= "table" then return end
	local function val(flag)
		local f = F[flag]
		if not f or type(f.Get) ~= "function" then return nil end
		local ok, v = pcall(function() return f:Get() end)
		return ok and v or nil
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
	v = val("PanicMode")
	if type(v) == "boolean" then S.panicOn = v end
	v = val("PanicRadius")
	if tonumber(v) then S.panicRadius = tonumber(v) end
	v = val("AutoSell")
	if type(v) == "boolean" then S.autoSell = v end
	v = val("SellAt")
	if tonumber(v) then S.sellAt = tonumber(v) end
	v = val("AutoPerfect")
	if type(v) == "boolean" then
		S.perfectOn = v
		if v then perfect_hook_install() else perfect_hook_remove() end
	end
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
end

pcall(function()
	Window:OnConfigChanged(function()
		pcall(sync_state_from_flags)
	end)
end)

-- *LoadAutoload can run before every element exists, so it goes last and syncs after*
pcall(function() Window:LoadAutoload() end)
pcall(sync_state_from_flags)

pcall(function()
	Window:Notify({Title = "Blizzard", Content = "Farm hub ready", Duration = 4})
end)
print("[Blizzard] loaded")
