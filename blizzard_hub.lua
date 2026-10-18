-- Blizzard Hub loader — Foresters
-- target: Roblox executor, autoexec friendly
-- pulls the latest farm_hub.lua from main and runs it

local RAW = "https://raw.githubusercontent.com/bevankeren/foresters/main/farm_hub.lua"
local VERSION = "1.0"

if _G.__BLIZZARD_HUB_UNLOAD then
	pcall(_G.__BLIZZARD_HUB_UNLOAD)
	_G.__BLIZZARD_HUB_UNLOAD = nil
	task.wait(0.15)
end

local ok_http, src = pcall(function()
	return game:HttpGet(RAW)
end)
if not ok_http or type(src) ~= "string" or #src < 100 then
	warn("[Blizzard Hub] fetch failed: " .. tostring(src))
	return
end

local ok_parse, fn = pcall(function() return loadstring(src, "blizzard_hub") end)
if not ok_parse or type(fn) ~= "function" then
	warn("[Blizzard Hub] parse failed: " .. tostring(fn))
	return
end

local ok_run, err = pcall(fn)
if not ok_run then
	warn("[Blizzard Hub] runtime error: " .. tostring(err))
	return
end

print(("[Blizzard Hub] loaded v%s | %d bytes"):format(VERSION, #src))
