-- axe shop probe: dump every shop, its AxeId, and the price the game now asks
local Players = game:GetService("Players")
local CS = game:GetService("CollectionService")
local plr = Players.LocalPlayer
local RS = game:GetService("ReplicatedStorage")
local AxeConfig = require(RS.Modules.Lumber.AxeConfig)
local AxePrice = require(RS.Modules.Lumber.AxePrice)
local lines = {}

-- every AxeView prompt, with the price the game would charge right now
local shops = {}
for _, prompt in ipairs(CS:GetTagged("AxeView")) do
	local id = prompt:GetAttribute("AxeId")
	local model = prompt:FindFirstAncestorOfClass("Model")
	if id and model then
		local pos = model:GetPivot().Position
		local cfg = AxeConfig[id]
		local base_price = cfg and cfg.Price or -1
		local disp = cfg and cfg.DisplayName or id
		local ok, live = pcall(function() return AxePrice.For(id, {}) end)
		table.insert(shops, {
			id = id, disp = disp, base = base_price,
			live = (ok and live) or -1,
			x = math.floor(pos.X), y = math.floor(pos.Y), z = math.floor(pos.Z),
		})
	end
end
table.sort(shops, function(a, b)
	if a.live ~= b.live then return a.live < b.live end
	return a.id < b.id
end)

for _, s in ipairs(shops) do
	local delta = s.live - s.base
	local mark = (delta ~= 0) and ("%+d"):format(delta) or ""
	table.insert(lines, ("%-22s %-18s %10s %10s %8s  %d,%d,%d"):format(
		s.id, s.disp, tostring(s.base), tostring(s.live), mark, s.x, s.y, s.z))
end

table.insert(lines, "")
table.insert(lines, "raw AxeConfig prices:")
local raw = {}
for id, cfg in pairs(AxeConfig) do
	if type(cfg) == "table" and cfg.Price then
		table.insert(raw, ("%s=%s (P%.1f S%.1f)"):format(id, tostring(cfg.Price), cfg.Power or 0, cfg.Speed or 0))
	end
end
table.sort(raw)
for i, r in ipairs(raw) do
	if i <= 20 then table.insert(lines, "  " .. r) end
end

table.insert(lines, "")
table.insert(lines, "player: Level=" .. tostring(plr.leaderstats.Level.Value) ..
	" Bloodline=" .. tostring(plr:GetAttribute("Bloodline") or "?") ..
	" Company=" .. tostring(plr:GetAttribute("Company") or "?") ..
	" CompanyRole=" .. tostring(plr:GetAttribute("CompanyRole") or "?"))

getgenv().__AxeDump = table.concat(lines, "\n")
return "ok " .. #shops