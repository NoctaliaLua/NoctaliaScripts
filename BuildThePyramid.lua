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
-- MAIN TAB (UI)
-- ============================================================================
local PyramidGroup = Tabs.MainTab:AddLeftGroupbox("Pyramid")

PyramidGroup:AddToggle("AutoFarmEnabled", { Text = "Auto Farm", Default = false })
local FarmDepBox = PyramidGroup:AddDependencyBox()
FarmDepBox:AddToggle("AutoFarmNotify", { Text = "Notify", Default = false })
FarmDepBox:AddToggle("InstantPickup", { Text = "Instant pickup", Default = false, Tooltip = "May cause lag", Warning = true })
FarmDepBox:AddSlider("TweenSpeed", { Text = "Tween speed", Default = 150, Min = 1, Max = 500, Rounding = 0 })

PyramidGroup:AddDivider()

PyramidGroup:AddToggle("AutoPickupEnabled", { Text = "Auto Pickup", Default = false })
local PickupDepBox = PyramidGroup:AddDependencyBox()
PickupDepBox:AddToggle("AutoPickupNotify", { Text = "Notify", Default = false })

FarmDepBox:SetupDependencies({ { Toggles.AutoFarmEnabled, true } })
PickupDepBox:SetupDependencies({ { Toggles.AutoPickupEnabled, true } })

local ShopGroup = Tabs.MainTab:AddRightGroupbox("Shop")

ShopGroup:AddToggle("BuyBulkPickup", { Text = "Buy Bulk Pickup", Default = false })
local BulkPickupDepBox = ShopGroup:AddDependencyBox()
BulkPickupDepBox:AddToggle("BuyBulkPickupNotify", { Text = "Notify", Default = false })

ShopGroup:AddToggle("BuyBulkPlace", { Text = "Buy Bulk Place", Default = false })
local BulkPlaceDepBox = ShopGroup:AddDependencyBox()
BulkPlaceDepBox:AddToggle("BuyBulkPlaceNotify", { Text = "Notify", Default = false })

ShopGroup:AddToggle("BuyPlacementRange", { Text = "Buy Placement Range", Default = false })
local PlacementRangeDepBox = ShopGroup:AddDependencyBox()
PlacementRangeDepBox:AddToggle("BuyPlacementRangeNotify", { Text = "Notify", Default = false })

BulkPickupDepBox:SetupDependencies({ { Toggles.BuyBulkPickup, true } })
BulkPlaceDepBox:SetupDependencies({ { Toggles.BuyBulkPlace, true } })
PlacementRangeDepBox:SetupDependencies({ { Toggles.BuyPlacementRange, true } })

-- ============================================================================
-- MAIN TAB (LOGIC)
-- ============================================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local player = Players.LocalPlayer

local Services = ReplicatedStorage.Packages._Index["sleitnick_knit@1.7.0"].knit.Services
local Pickup = Services.BookService.RF.Pickup
local PurchaseUpgrade = Services.DataService.RF.PurchaseUpgrade

-- Settings
local CORNER_A     = Vector3.new(117, 4, 200)   -- sweep corners (layer 1)
local CORNER_B     = Vector3.new(433, 4, -115)
local PICKUP_POS   = Vector3.new(-247, -3, 42)
local LAYER_STEP   = 3      -- studs up per layer (Y)
local LAYER_INSET  = 3      -- studs removed from each side per layer (X/Z)
local ROW_SPACING  = 40     -- distance between sweep rows; lower = more coverage
local SWEEP_SPEED  = 150    -- studs per second
local LOOP_DELAY   = 0.001  -- effectively one frame
local BUY_DELAY    = 0.25   -- seconds between successful purchases
local RETRY_DELAY  = 1      -- seconds to wait after a failed purchase

-- Fast pickup settings
local E_PRESSES_PER_TICK = 5   -- simulated E clicks per frame
local MAX_INFLIGHT       = 8   -- max Pickup remotes waiting on the server at once

-- Helpers
local function On(name)
    return Toggles[name] ~= nil and Toggles[name].Value == true
end

local function Notify(toggleName, text)
    if On(toggleName) then
        Library:Notify(text, 3)
    end
end

local function GetCapacity()
    local label = player.PlayerGui:FindFirstChild("ScreenGui")
    label = label and label:FindFirstChild("CenterLeft")
    label = label and label:FindFirstChild("LeftSideBar")
    label = label and label:FindFirstChild("StrengthCounter")
    label = label and label:FindFirstChild("Readout")
    label = label and label:FindFirstChild("Detail")
    label = label and label:FindFirstChild("TextLabel")
    if not label then return nil, nil end

    local text = label.Text:gsub(",", "")
    local cur, max = text:match("(%d+)%s*/%s*(%d+)")
    return tonumber(cur), tonumber(max)
end

-- Optional: return the player's current currency as a number so the cost of an
-- upgrade can be measured (before minus after). Left as nil until you tell me
-- where the game shows your money.
local function GetCurrency()
    return nil
end

-- Any extra number/string fields the purchase result contains (e.g. cost, price)
local function ExtraFields(res)
    local parts = {}
    for k, v in pairs(res) do
        if k ~= "ok" and k ~= "level" and k ~= "upgradeId" and k ~= "reason"
            and (type(v) == "number" or type(v) == "string") then
            table.insert(parts, ("%s=%s"):format(tostring(k), tostring(v)))
        end
    end
    table.sort(parts)
    return #parts > 0 and (", " .. table.concat(parts, ", ")) or ""
end

-- Watches capacity and reports what changed. Increases count as picked up,
-- decreases count as placed. Grouped into one notification per interval,
-- because pickups happen every frame and one notification each would flood the screen.
local NOTIFY_INTERVAL = 1.5

task.spawn(function()
    local lastCur
    local picked, placed, lastSend = 0, 0, tick()

    while not Library.Unloaded do
        local cur, max = GetCapacity()
        if cur then
            if lastCur then
                if cur > lastCur then
                    picked += cur - lastCur
                elseif cur < lastCur then
                    placed += lastCur - cur
                end
            end
            lastCur = cur
        end

        if tick() - lastSend >= NOTIFY_INTERVAL then
            lastSend = tick()
            local farmOn, pickupOn = On("AutoFarmEnabled"), On("AutoPickupEnabled")
            local capText = (cur and max) and (" (capacity %d/%d)"):format(cur, max) or ""

            if picked > 0 and ((farmOn and On("AutoFarmNotify")) or (pickupOn and On("AutoPickupNotify"))) then
                Library:Notify(("Picked up %d%s"):format(picked, capText), 3)
            end
            if placed > 0 and farmOn and On("AutoFarmNotify") then
                Library:Notify(("Placed %d%s"):format(placed, capText), 3)
            end
            picked, placed = 0, 0
        end

        task.wait(0.05)
    end
end)

local function GetRegion()
    local regions = workspace:FindFirstChild("Regions")
    return regions and regions:FindFirstChild("Region:Quarry")
end

local function DoPickup()
    local region = GetRegion()
    if region then
        pcall(function()
            Pickup:InvokeServer(region)
        end)
    end
end

-- Simulated E click (local, doesn't wait on the server)
local function PressE()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
end

local function PressEMany()
    for _ = 1, E_PRESSES_PER_TICK do
        PressE()
    end
end

-- Fires the Pickup remote in its own thread so the loop never waits on ping.
-- MAX_INFLIGHT caps how many can be pending at once.
local inflight = 0
local function DoPickupAsync()
    if inflight >= MAX_INFLIGHT then return end
    local region = GetRegion()
    if not region then return end
    inflight += 1
    task.spawn(function()
        pcall(function()
            Pickup:InvokeServer(region)
        end)
        inflight -= 1
    end)
end

-- E click spam + pickup remote, without blocking
local function FastPickup()
    PressEMany()
    DoPickupAsync()
end

-- ----------------------------------------------------------------------------
-- Auto Buy upgrades
-- ----------------------------------------------------------------------------
local UPGRADES = {
    { id = "bulkPickup",     name = "Bulk Pickup",     toggle = "BuyBulkPickup",     notify = "BuyBulkPickupNotify" },
    { id = "bulkPlace",      name = "Bulk Place",      toggle = "BuyBulkPlace",      notify = "BuyBulkPlaceNotify" },
    { id = "placementRange", name = "Placement Range", toggle = "BuyPlacementRange", notify = "BuyPlacementRangeNotify" },
}

for _, up in ipairs(UPGRADES) do
    task.spawn(function()
        local maxed = false
        local lastReason = nil
        local wasOn = false

        while not Library.Unloaded do
            local enabled = On(up.toggle)

            -- Re-enabling the toggle clears the "maxed" state
            if enabled and not wasOn then
                maxed, lastReason = false, nil
            end
            wasOn = enabled

            local wait = 0.2
            if enabled and not maxed then
                local before = GetCurrency()
                local ok, res = pcall(function()
                    return PurchaseUpgrade:InvokeServer(up.id)
                end)

                if ok and type(res) == "table" and res.ok then
                    lastReason = nil

                    local costText = ""
                    if before then
                        task.wait(0.1) -- let the currency display update
                        local after = GetCurrency()
                        if after then
                            costText = ", cost " .. tostring(before - after)
                        end
                    end

                    Notify(up.notify, ("%s bought: level %s%s%s"):format(
                        up.name, tostring(res.level), costText, ExtraFields(res)))
                    wait = BUY_DELAY
                else
                    local reason = (ok and type(res) == "table" and tostring(res.reason)) or "no response"
                    if reason:lower():find("max") then
                        maxed = true
                        Notify(up.notify, up.name .. " is maxed")
                    elseif reason ~= lastReason then
                        lastReason = reason
                        Notify(up.notify, ("%s: %s"):format(up.name, reason))
                    end
                    wait = RETRY_DELAY
                end
            end

            task.wait(wait)
        end
    end)
end

-- ----------------------------------------------------------------------------
-- Auto Pickup (E click spam + non-blocking Pickup remote)
-- ----------------------------------------------------------------------------
Toggles.AutoPickupEnabled:OnChanged(function()
    Notify("AutoPickupNotify", Toggles.AutoPickupEnabled.Value and "Auto Pickup enabled" or "Auto Pickup disabled")
end)

task.spawn(function()
    while not Library.Unloaded do
        -- Auto Farm already does its own picking up, so skip while it's on
        if On("AutoPickupEnabled") and not On("AutoFarmEnabled") then
            FastPickup()
        end
        task.wait(LOOP_DELAY)
    end
end)

-- ----------------------------------------------------------------------------
-- Auto Farm: pickup -> teleport to pyramid -> sweep + spam E -> repeat
-- ----------------------------------------------------------------------------
local function GetCurrentLayer()
    local cover = workspace:FindFirstChild("ClientPyramidCover")
    local lowest
    if cover then
        for _, child in ipairs(cover:GetChildren()) do
            local n = tonumber(child.Name:match("^Layer(%d+)$"))
            if n and (not lowest or n < lowest) then
                lowest = n
            end
        end
    end
    return lowest
end

local EMPTY_TOP    = Vector3.new(278, 150, 39)
local EMPTY_BOTTOM = Vector3.new(278, 0, 39)
local emptyGoingDown = true

-- Back-and-forth (snake) path, shrunk 3 studs per side and raised 3 studs per layer
local function BuildPath(layer)
    local inset = LAYER_INSET * layer

    local minX = math.min(CORNER_A.X, CORNER_B.X) + inset
    local maxX = math.max(CORNER_A.X, CORNER_B.X) - inset
    local minZ = math.min(CORNER_A.Z, CORNER_B.Z) + inset
    local maxZ = math.max(CORNER_A.Z, CORNER_B.Z) - inset
    if minX > maxX then minX, maxX = (minX + maxX) / 2, (minX + maxX) / 2 end
    if minZ > maxZ then minZ, maxZ = (minZ + maxZ) / 2, (minZ + maxZ) / 2 end

    local y = CORNER_A.Y + LAYER_STEP * (layer - 1)
    local columns = math.max(1, math.ceil((maxX - minX) / ROW_SPACING))

    local points, flip = {}, false
    for i = 0, columns do
        local x = minX + (maxX - minX) * (i / columns)
        local a, b = Vector3.new(x, y, minZ), Vector3.new(x, y, maxZ)
        if flip then a, b = b, a end
        table.insert(points, a)
        table.insert(points, b)
        flip = not flip
    end
    return points
end

local function TeleportTo(pos)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and (hrp.Position - pos).Magnitude > 1 then
        hrp.CFrame = CFrame.new(pos)
    end
end

local state = "pickup" -- "pickup" until full, then "deposit" until empty
local path, pathLayer, idx, lastPos
local resumePending = false

Toggles.AutoFarmEnabled:OnChanged(function()
    Notify("AutoFarmNotify", Toggles.AutoFarmEnabled.Value and "Auto Farm enabled" or "Auto Farm disabled")
end)

local sweepConn = RunService.Heartbeat:Connect(function(dt)
    if Library.Unloaded or not On("AutoFarmEnabled") or state ~= "deposit" then return end

    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    -- New layer detected: rebuild the path and start from the beginning
    local layer = GetCurrentLayer()

    -- No layer yet: bob up and down while E keeps spamming until one appears
    if not layer then
        path, pathLayer, idx = nil, nil, nil
        if resumePending then
            hrp.CFrame = CFrame.new(lastPos or EMPTY_TOP)
            resumePending = false
        end

        local target = emptyGoingDown and EMPTY_BOTTOM or EMPTY_TOP
        local delta = target - hrp.Position
        local step = Options.TweenSpeed.Value * dt
        if delta.Magnitude <= step then
            hrp.CFrame = CFrame.new(target)
            emptyGoingDown = not emptyGoingDown
        else
            hrp.CFrame = CFrame.new(hrp.Position + delta.Unit * step)
        end

        hrp.AssemblyLinearVelocity = Vector3.zero
        lastPos = hrp.Position
        return
    end

    if layer ~= pathLayer then
        path, pathLayer, idx = BuildPath(layer), layer, 1
        lastPos = nil
        resumePending = false
        hrp.CFrame = CFrame.new(path[1])
        Notify("AutoFarmNotify", "Building layer " .. layer)
    end

    -- Back from a pickup trip: jump to where the sweep stopped
    if resumePending then
        hrp.CFrame = CFrame.new(lastPos or path[idx])
        resumePending = false
    end

    local target = path[idx]
    local delta = target - hrp.Position
    local step = Options.TweenSpeed.Value * dt

    if delta.Magnitude <= step then
        hrp.CFrame = CFrame.new(target)
        if idx >= #path then
            idx = 1 -- full pass done but layer not finished: start over
            hrp.CFrame = CFrame.new(path[1])
        else
            idx += 1
        end
    else
        hrp.CFrame = CFrame.new(hrp.Position + delta.Unit * step)
    end

    hrp.AssemblyLinearVelocity = Vector3.zero
    lastPos = hrp.Position
end)

Library:OnUnload(function()
    sweepConn:Disconnect()
end)

task.spawn(function()
    while not Library.Unloaded do
        if On("AutoFarmEnabled") then
            local current, max = GetCapacity()

            if current and max then
                if state == "pickup" and current >= max then
                    state = "deposit"
                    resumePending = true
                    Notify("AutoFarmNotify", "Capacity full - building")
                elseif state == "deposit" and current <= 0 then
                    state = "pickup"
                    Notify("AutoFarmNotify", "Capacity empty - picking up")
                end

                if state == "deposit" then
                    PressEMany()
                else
                    TeleportTo(PICKUP_POS)
                    if On("InstantPickup") then
                        FastPickup()
                    else
                        DoPickupAsync()
                    end
                end
            end
        end
        task.wait(LOOP_DELAY)
    end
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