local repo = "https://raw.githubusercontent.com/NoctaliaLua/MatchaLib/main/"

local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

local Players = game:GetService("Players")

Library.ShowToggleFrameInKeybinds = true
Library.NotifySide = "Left"

local Window = Library:CreateWindow({
	Title = "Noctalia",
	Subtitle = "Interface",
	Badge = "Pro",

	FooterLeft = "Connected",
	FooterCenter = "Collect 1 Million Items",
	FooterRightLabel = "Build:",
	FooterRightValue = os.date("%b ") .. tonumber(os.date("%d")) .. os.date(" %Y"),

	Size = UDim2.fromOffset(605, 400),
	Center = true,
	AutoShow = true,
	Resizable = true,
	UnlockMouseWhileOpen = true,
	NotifySide = "Left",
	TabPadding = 8,
	MenuFadeTime = 0.2
})

local Tabs = {
	Main = Window:AddTab("Main"),
	Configs = Window:AddTab("Configs"),
}

-- ============================================================================
-- MAIN TAB (UI)
-- ============================================================================
local SweepGroup = Tabs.Main:AddLeftGroupbox("Sweep")

SweepGroup:AddToggle("SweepEnabled", { Text = "Enabled", Default = false }):AddKeyPicker("SweepKeybind", {
	Default = "L",
	Mode = "Toggle",
	SyncToggleState = true,
	Text = "Sweep",
})
SweepGroup:AddSlider("SweepSpeed", { Text = "Walkspeed multiplier", Default = 2, Min = 1, Max = 10, Rounding = 1, Suffix = "x" })

-- ============================================================================
-- MAIN TAB (LOGIC)
-- ============================================================================
local player = Players.LocalPlayer

local MIN_X, MAX_X = -35, 35
local MIN_Z, MAX_Z = -35, 35
local Y = 16
local ROW_STEP = 5

local START = Vector3.new(MIN_X, Y, MAX_Z)

-- Snake path: down each row along Z, step 5 studs along X, come back along the next row
local Path = {}
local forward = true
for x = MIN_X, MAX_X, ROW_STEP do
	local a, b = MAX_Z, MIN_Z
	if not forward then a, b = b, a end
	table.insert(Path, Vector3.new(x, Y, a))
	table.insert(Path, Vector3.new(x, Y, b))
	forward = not forward
end

local ARRIVE_DISTANCE = 2   -- horizontal studs from the target that count as arrived
local BASE_WALKSPEED = 16

local function GetHumanoid()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function ResetWalkSpeed()
	local humanoid = GetHumanoid()
	if humanoid then
		humanoid.WalkSpeed = BASE_WALKSPEED
		humanoid:MoveTo(humanoid.RootPart and humanoid.RootPart.Position or Vector3.zero)
	end
end

-- Walks the humanoid to pos at base walkspeed * slider; returns false if disabled or the character went away
local function WalkTo(pos)
	local humanoid = GetHumanoid()
	local root = humanoid and humanoid.RootPart
	if not root then return false end

	-- timeout so a blocked path can't hang the loop forever
	local deadline = os.clock() + ((root.Position - pos) * Vector3.new(1, 0, 1)).Magnitude / (BASE_WALKSPEED * Options.SweepSpeed.Value) + 3

	while Toggles.SweepEnabled.Value and not Library.Unloaded do
		humanoid = GetHumanoid()
		root = humanoid and humanoid.RootPart
		if not root or humanoid.Health <= 0 then return false end

		if ((root.Position - pos) * Vector3.new(1, 0, 1)).Magnitude <= ARRIVE_DISTANCE or os.clock() > deadline then
			return true
		end

		humanoid.WalkSpeed = BASE_WALKSPEED * Options.SweepSpeed.Value
		humanoid:MoveTo(pos)
		task.wait()
	end

	return false
end

Toggles.SweepEnabled:OnChanged(function()
	if not Toggles.SweepEnabled.Value then
		ResetWalkSpeed()
	end
end)

Library:OnUnload(function()
	ResetWalkSpeed()
	Library.Unloaded = true
end)

task.spawn(function()
	while not Library.Unloaded do
		if Toggles.SweepEnabled.Value and GetHumanoid() then
			-- walk to the start (also the "walk back" after a finished sweep), then run the whole path
			local ok = WalkTo(START)

			if ok then
				for _, point in ipairs(Path) do
					if not WalkTo(point) then break end
				end
			end
		else
			task.wait(0.1)
		end
		task.wait()
	end
end)

-- ============================================================================
-- CONFIGS TAB
-- ============================================================================
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("MyScriptHub")
SaveManager:SetFolder("MyScriptHub/collect-1-million-items")

SaveManager:BuildConfigSection(Tabs.Configs)

local MenuGroup = Tabs.Configs:AddLeftGroupbox("Menu")

MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
MenuGroup:AddButton("Unload", function() Library:Unload() end)

Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:ApplyToTab(Tabs.Configs)

SaveManager:LoadAutoloadConfig()
