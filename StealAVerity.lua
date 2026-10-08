local repo = "https://raw.githubusercontent.com/NoctaliaLua/MatchaLib/main/"

local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

local Players = game:GetService("Players")

Library.ShowToggleFrameInKeybinds = true
Library.NotifySide = "Left"

local MarketplaceService = game:GetService("MarketplaceService")

local GameName = "Unknown"

local Success, Info = pcall(function()
    return MarketplaceService:GetProductInfo(game.PlaceId)
end)

if Success and Info and Info.Name then
    GameName = Info.Name
end

if GameName == "Unknown" or GameName == "Ugc" then
    pcall(function()
        local Data = game:GetService("HttpService"):JSONDecode(game:HttpGet("https://games.roblox.com/v1/games?universeIds=" .. game.GameId))
        if Data and Data.data and Data.data[1] and Data.data[1].name then
            GameName = Data.data[1].name
        end
    end)
end

local Window = Library:CreateWindow({
	Title = "Noctalia",
	Subtitle = "Interface",
	Badge = "Pro",

	-- Username defaults to the local player's name; pass `Username = "..."` to override it
	FooterLeft = "Connected",
	FooterCenter = GameName,
	FooterRightLabel = "Build:",
	FooterRightValue = os.date("%b ") .. tonumber(os.date("%d")) .. os.date(" %Y"),

	Size = UDim2.fromOffset(605, 970),
	Center = true,
	AutoShow = true,
	Resizable = true,
	UnlockMouseWhileOpen = true,
	NotifySide = "Left",
	TabPadding = 8,
	MenuFadeTime = 0.2
})

local Tabs = {
    MainTab = Window:AddTab("Main"),
    Configs = Window:AddTab("Configs"),
}

-- ============================================================================
-- SERVICES / HELPERS
-- ============================================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local player = Players.LocalPlayer

local function On(name)
    return Toggles[name] ~= nil and Toggles[name].Value == true
end

local function GetHRP()
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function TeleportTo(pos)
    local hrp = GetHRP()
    if hrp then
        hrp.CFrame = CFrame.new(pos)
        hrp.AssemblyLinearVelocity = Vector3.zero
    end
end

local function InBase()
    return workspace:FindFirstChild("BaseRuntime") ~= nil
end

local function InBoss()
    return workspace:FindFirstChild("BossRuntime") ~= nil
end

-- Waits for a remote in the background and connects to its OnClientEvent
local function ListenRemote(name, callback)
    task.spawn(function()
        local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
        local remote = remotes and remotes:WaitForChild(name, 30)
        if not remote then
            warn("Remote not found: " .. name)
            return
        end
        local conn = remote.OnClientEvent:Connect(callback)
        Library:OnUnload(function()
            conn:Disconnect()
        end)
    end)
end

local function FireRemote(name, ...)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local remote = remotes and remotes:FindFirstChild(name)
    if remote then
        firesignal(remote.OnClientEvent, ...)
    end
end

-- ============================================================================
-- UI
-- ============================================================================
local MainTabbox = Tabs.MainTab:AddLeftTabbox()
local MainBox = MainTabbox:AddTab("Main")
local BossBox = MainTabbox:AddTab("Boss")

MainBox:AddToggle("FasterWin", {
    Text = "Faster Win",
    Default = false,
    Tooltip = "Buggy",
    Warning = true,
})
MainBox:AddToggle("FastPickup", { Text = "Fast pickup", Default = false })

BossBox:AddToggle("InstantBoxSteal", { Text = "Instant box steal", Default = false })
BossBox:AddToggle("AutoProtect", { Text = "Auto protect", Default = false })

local MiscGroup = Tabs.MainTab:AddRightGroupbox("Misc")

MiscGroup:AddToggle("Esp", { Text = "Esp", Default = false }):AddColorPicker("EspColor", {
    Default = Color3.new(1, 1, 1),
    Title = "Esp color",
})

MiscGroup:AddButton("Infinite Yield", function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
end)

-- Server hop (Infinite Yield style): joins a random non-full public server
MiscGroup:AddButton("Server switch", function()
    local HttpService = game:GetService("HttpService")
    local TeleportService = game:GetService("TeleportService")

    local ok, servers = pcall(function()
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId)
        return HttpService:JSONDecode(game:HttpGet(url))
    end)

    if not (ok and servers and servers.data) then
        Library:Notify("Couldn't fetch servers", 3)
        return
    end

    local candidates = {}
    for _, server in ipairs(servers.data) do
        if server.id ~= game.JobId and server.playing and server.maxPlayers and server.playing < server.maxPlayers then
            table.insert(candidates, server.id)
        end
    end

    if #candidates == 0 then
        Library:Notify("No other servers found", 3)
        return
    end

    Library:Notify("Switching server...", 3)
    TeleportService:TeleportToPlaceInstance(game.PlaceId, candidates[math.random(#candidates)], player)
end)

MiscGroup:AddButton("Remove Obstacles", function()
    if not InBase() then
        Library:Notify("BaseRuntime not found", 3)
        return
    end

    local decorations = workspace:FindFirstChild("Decorations")
    if not decorations then
        Library:Notify("Decorations not found", 3)
        return
    end

    local names = {}
    for i = 1, 14 do
        names["Area" .. i] = true
    end

    local removed = 0
    for _, child in ipairs(decorations:GetChildren()) do
        if child:IsA("Folder") and names[child.Name] then
            child:Destroy()
            removed += 1
        end
    end
    Library:Notify(("Removed %d folders"):format(removed), 3)
end)

-- ============================================================================
-- FASTER WIN
-- CarryChanged (box picked up) arms the teleport. The first AreaEntered for
-- area4..area1 then teleports to the drop point and fires "spawn". The area
-- teleport stays disabled until CarryChanged fires again.
-- ============================================================================
local WIN_POS = Vector3.new(153, 3, -62)
local areaArmed = false
local AREAS = { area4 = true, area3 = true, area2 = true, area1 = true }

Toggles.FasterWin:OnChanged(function()
    areaArmed = false
    if Toggles.FasterWin.Value and not InBase() then
        Library:Notify("Faster Win: BaseRuntime not found", 3)
    end
end)

ListenRemote("CarryChanged", function()
    if On("FasterWin") and InBase() then
        areaArmed = true
    end
end)

ListenRemote("AreaEntered", function(area)
    if not (On("FasterWin") and InBase()) then return end
    if not (areaArmed and AREAS[area]) then return end

    areaArmed = false
    TeleportTo(WIN_POS)
    FireRemote("AreaEntered", "spawn")
end)

-- ============================================================================
-- FAST PICKUP (Infinite Yield "Instant Prompt": HoldDuration = 0 on every prompt)
-- ============================================================================
local promptConn

local function MakeInstant(prompt)
    if prompt:IsA("ProximityPrompt") then
        if prompt:GetAttribute("HoldDurationOld") == nil then
            prompt:SetAttribute("HoldDurationOld", prompt.HoldDuration)
        end
        prompt.HoldDuration = 0
    end
end

Toggles.FastPickup:OnChanged(function()
    if promptConn then
        promptConn:Disconnect()
        promptConn = nil
    end

    if Toggles.FastPickup.Value then
        for _, v in ipairs(workspace:GetDescendants()) do
            MakeInstant(v)
        end
        promptConn = workspace.DescendantAdded:Connect(MakeInstant)
    else
        for _, v in ipairs(workspace:GetDescendants()) do
            if v:IsA("ProximityPrompt") then
                local old = v:GetAttribute("HoldDurationOld")
                if old ~= nil then
                    v.HoldDuration = old
                    v:SetAttribute("HoldDurationOld", nil)
                end
            end
        end
    end
end)

Library:OnUnload(function()
    if promptConn then
        promptConn:Disconnect()
    end
end)

-- ============================================================================
-- INSTANT BOX STEAL
-- ============================================================================
local STEAL_POS = Vector3.new(4, 3, -24)

Toggles.InstantBoxSteal:OnChanged(function()
    if Toggles.InstantBoxSteal.Value and not InBoss() then
        Library:Notify("Instant box steal: BossRuntime not found", 3)
    end
end)

ListenRemote("CarryChanged", function()
    if On("InstantBoxSteal") and InBoss() then
        TeleportTo(STEAL_POS)
    end
end)

-- ============================================================================
-- AUTO PROTECT
-- ============================================================================
local PROTECT_POS = Vector3.new(-81, 3, -149)
local BOSS_ATTACKS = {
    BossBlink = 3.5,
    BossCharge = 4,
    BossDive = 2.5,
    BossBomb = 4,
    BossSlam = 2.5,
    BossNuke = 5,
}

local returnAt = 0
local returning = false

local function TeleportToBoss()
    local runtime = workspace:FindFirstChild("BossRuntime")
    local boss = runtime and runtime:FindFirstChild("Boss")
    if not boss then return end

    local hrp = GetHRP()
    if not hrp then return end

    local cf = boss:IsA("Model") and boss:GetPivot() or boss:IsA("BasePart") and boss.CFrame
    if cf then
        hrp.CFrame = cf
        hrp.AssemblyLinearVelocity = Vector3.zero
    end
end

Toggles.AutoProtect:OnChanged(function()
    if Toggles.AutoProtect.Value and not InBoss() then
        Library:Notify("Auto protect: BossRuntime not found", 3)
    end
end)

for remoteName, duration in pairs(BOSS_ATTACKS) do
    ListenRemote(remoteName, function()
        if not (On("AutoProtect") and InBoss()) then return end

        TeleportTo(PROTECT_POS)
        -- overlapping attacks extend the time spent away
        returnAt = math.max(returnAt, tick() + duration)

        if returning then return end
        returning = true
        task.spawn(function()
            while tick() < returnAt and not Library.Unloaded do
                if not On("AutoProtect") then break end
                task.wait(0.05)
            end
            returning = false
            if On("AutoProtect") then
                TeleportToBoss()
            end
        end)
    end)
end

-- ============================================================================
-- ESP (Infinite Yield "chams": always-on-top box adornments on every part)
-- ============================================================================
local EspFolder = Instance.new("Folder")
EspFolder.Name = "NoctaliaEsp"
EspFolder.Parent = (gethui and gethui()) or CoreGui

local espConns = {}

local function ClearEsp()
    EspFolder:ClearAllChildren()
end

local function AddChams(character)
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            local box = Instance.new("BoxHandleAdornment")
            box.Name = "Chams"
            box.Adornee = part
            box.AlwaysOnTop = true
            box.ZIndex = 10
            box.Size = part.Size
            box.Transparency = 0.5
            box.Color3 = Options.EspColor.Value
            box.Parent = EspFolder
        end
    end
end

local function TrackPlayer(plr)
    if plr == player then return end
    if plr.Character then
        AddChams(plr.Character)
    end
    table.insert(espConns, plr.CharacterAdded:Connect(function(char)
        task.wait(0.5) -- let the character's parts load in
        if On("Esp") then
            AddChams(char)
        end
    end))
end

local function DisableEsp()
    for _, c in ipairs(espConns) do
        c:Disconnect()
    end
    table.clear(espConns)
    ClearEsp()
end

Toggles.Esp:OnChanged(function()
    DisableEsp()
    if Toggles.Esp.Value then
        for _, plr in ipairs(Players:GetPlayers()) do
            TrackPlayer(plr)
        end
        table.insert(espConns, Players.PlayerAdded:Connect(TrackPlayer))
    end
end)

Options.EspColor:OnChanged(function()
    for _, box in ipairs(EspFolder:GetChildren()) do
        box.Color3 = Options.EspColor.Value
    end
end)

Library:OnUnload(function()
    DisableEsp()
    EspFolder:Destroy()
end)
-- ============================================================================
-- UI SETTINGS & WATERMARK
-- (Watermark groupbox is built BEFORE SaveManager loads so saved values apply)
-- ============================================================================
local StartTime = tick()

local FrameTimer = tick()
local FrameCounter = 0;
local FPS = 60;
local LastUpdate = 0
local GetPing = (function() return math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()) end)
local CanDoPing = pcall(function() return GetPing(); end)

local function IsOn(Idx)
	return Toggles[Idx] ~= nil and Toggles[Idx].Value == true
end

local function FormatUptime(Seconds)
	Seconds = math.floor(Seconds)
	return ("%02d %02d %02d"):format(math.floor(Seconds / 3600), math.floor(Seconds / 60) % 60, Seconds % 60)
end

Library:SetWatermarkTitle("Noctalia", "Pro")

local WatermarkConnection = game:GetService("RunService").RenderStepped:Connect(function()
	FrameCounter += 1;

	if (tick() - FrameTimer) >= 1 then
		FPS = FrameCounter;
		FrameTimer = tick();
		FrameCounter = 0;
	end;

	if (tick() - LastUpdate) < 0.2 then
		return
	end
	LastUpdate = tick()

	local Segments = {}

	if IsOn("WatermarkUser") then table.insert(Segments, { Text = Players.LocalPlayer.Name, Bold = true }) end
	if IsOn("WatermarkGame") then table.insert(Segments, GameName) end
	if IsOn("WatermarkFps") then table.insert(Segments, { Text = tostring(math.floor(FPS)), Suffix = "FPS", Color = "OnlineColor" }) end
	if IsOn("WatermarkPing") and CanDoPing then table.insert(Segments, { Text = tostring(GetPing()), Suffix = "ms" }) end
	if IsOn("WatermarkTime") then table.insert(Segments, os.date("%H %M %S")) end
	if IsOn("WatermarkUptime") then table.insert(Segments, FormatUptime(tick() - StartTime)) end

	Library:SetWatermarkVisibility(IsOn("WatermarkEnabled"))
	Library:SetWatermarkSegments(Segments)
end);
Library:OnUnload(function()
	WatermarkConnection:Disconnect()

	print("Unloaded!")
	Library.Unloaded = true
end)

--// Configs \\--
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("MyScriptHub")
SaveManager:SetFolder("MyScriptHub/specific-game")
SaveManager:SetSubFolder("specific-place")

-- built first so the Configuration box sits at the top of the right column
SaveManager:BuildConfigSection(Tabs.Configs)

local MenuGroup = Tabs.Configs:AddLeftGroupbox("Menu")

MenuGroup:AddToggle("KeybindMenuOpen", { Default = Library.KeybindFrame.Visible, Text = "Open Keybind Menu", Callback = function(value) Library.KeybindFrame.Visible = value end})
MenuGroup:AddToggle("KeybindNotification", {Text = "Keybind notification", Default = false, Callback = function(Value) Library.KeybindNotification = Value end})
MenuGroup:AddToggle("BlurEnabled", {Text = "Blur", Default = false, Callback = function(Value) Library:SetBlur(Value) end})
MenuGroup:AddToggle("DarkOverlay", {Text = "Dark", Default = true, Callback = function(Value) Library:SetDark(Value) end})
MenuGroup:AddToggle("SnowEffect", {Text = "Snow", Default = true, Callback = function(Value) Library:SetSnow(Value) end})
MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
MenuGroup:AddButton("Unload", function() Library:Unload() end)

Library.ToggleKeybind = Options.MenuKeybind

local SoundGroup = Tabs.Configs:AddRightGroupbox("Sounds")

SoundGroup:AddToggle("UISound", {
	Text = "Ui sound",
	Default = true,
	Callback = function(Value)
		Library.UISound = Value
	end
})

SoundGroup:AddToggle("KeybindSound", {
	Text = "Keybind sound",
	Default = false,
	Callback = function(Value)
		Library.KeybindSound = Value
	end
})

local WatermarkGroup = Tabs.Configs:AddRightGroupbox("Watermark")

for _, Entry in ipairs({
	{ "WatermarkEnabled", "Enabled", true },
	{ "WatermarkUser", "User", true },
	{ "WatermarkGame", "Game", false },
	{ "WatermarkFps", "Fps", true },
	{ "WatermarkPing", "Ping", false },
	{ "WatermarkTime", "Time", true },
	{ "WatermarkUptime", "Uptime", false },
}) do
	WatermarkGroup:AddToggle(Entry[1], { Text = Entry[2], Default = Entry[3] })
end

ThemeManager:ApplyToTab(Tabs.Configs)

SaveManager:LoadAutoloadConfig()
