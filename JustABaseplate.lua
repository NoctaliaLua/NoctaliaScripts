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
	Main = Window:AddTab("Main"),
	Configs = Window:AddTab("Configs"),
}

-- ============================================================================
-- CHAT HELPERS
-- ============================================================================
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ChatInputBarConfiguration.TextBox is nil until the bar has been used, so fall back to the CoreGui chat
local function GetChatBox()
	local config = TextChatService:FindFirstChild("ChatInputBarConfiguration")
	if config and config.TextBox then
		return config.TextBox
	end

	local experienceChat = game:GetService("CoreGui"):FindFirstChild("ExperienceChat")
	return experienceChat and experienceChat:FindFirstChild("TextBox", true)
end

-- Types the message into the real chat bar and presses enter, exactly like typing it by hand
local function TypeChat(message)
	local box = GetChatBox()
	assert(box, "chat bar not found")

	box:CaptureFocus()
	task.wait(0.05)
	box.Text = message
	task.wait(0.05)

	-- a real Return key press while the box is focused is what actually submits the message
	local pressed = pcall(function()
		local vim = game:GetService("VirtualInputManager")
		vim:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
		task.wait(0.02)
		vim:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
	end)

	if not pressed then
		if keypress and keyrelease then
			keypress(0x0D)
			task.wait(0.02)
			keyrelease(0x0D)
		elseif firesignal then
			firesignal(box.FocusLost, true)
		end
	end
end

-- With "Hide commands" on, messages get the "/e" prefix and are typed through the chat bar (other players
-- don't see them). With it off they are sent as plain chat via SendAsync, which other players can see.
local function SendChat(message)
	local hide = Toggles.HideCommands and Toggles.HideCommands.Value

	local ok, err = pcall(function()
		if hide and TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
			TypeChat("/e " .. message)
		elseif TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
			local channels = TextChatService:WaitForChild("TextChannels", 5)
			local channel = channels and (channels:FindFirstChild("RBXGeneral") or channels:FindFirstChildWhichIsA("TextChannel"))
			channel:SendAsync(message)
		else
			ReplicatedStorage:WaitForChild("DefaultChatSystemChatEvents", 5).SayMessageRequest:FireServer(message, "All")
		end
	end)

	if not ok then
		warn("SendChat failed: " .. tostring(err))
		Library:Notify("Chat send failed: " .. tostring(err), 5)
	end
end

local function LoadHats(ids)
	task.spawn(function()
		SendChat("-ch")
		task.wait(0.3)
		SendChat("-pd")
		task.wait(0.3)
		SendChat("-gh " .. ids)
	end)
end

local function RunScript(url)
	local ok, err = pcall(function()
		loadstring(game:HttpGet(url))()
	end)
	if not ok then
		warn("Script failed to load: " .. tostring(err))
		Library:Notify("Script failed to load", 3)
	end
end

-- ============================================================================
-- DATA
-- ============================================================================
local HatIds = {
	["Star Glitcher"] = "93353641033633 17374846953 74541822200094 17374851733 5316539421 17387616772 138530087864684 17401151565 5316479641 87719366970131 138364679836274 5316549755 5699795428 119197587423705",
	["Hacklord"] = "17387616772 138849171376550 131444470246920 103376121931963 17374846953 103346369289447 100335781540492 5268720002 17401151565 17374851733",
	["Dual Sword"] = "93353641033633 17374846953 119197587423705 17374851733 74541822200094 5316549755 138364679836274 17387616772 138530087864684 87719366970131 17401151565 5316539421",
	["Goner"] = "17401151565 138364679836274 17822749561 17374851733 17374846953 17770317484 17835236579 17772174303 17387616772 17822722698",
	["Neptunian V"] = "93353641033633 138364679836274 17374851733 17374846953 74541822200094 119197587423705 17401151565 138530087864684 87719366970131 17387616772 5268602207",
	["Lightning Cannon"] = "93353641033633 17374846953 17374851733 74541822200094 116940095199813 117311153426168 138364679836274 138530087864684 87719366970131 119197587423705 17387616772 17401151565 4504231783",
	["Sin Dragon"] = "113048125789248 17374851733 17374846953 17401151565 138364679836274 17387616772 93353641033633 3756389957 16755111087 117186631495734 14959586922 132770514241770 111793953309477 87719366970131",
}

local Scripts = {
	["Star Glitcher"] = function()
		RunScript("https://rawscripts.net/raw/Universal-Script-Star-glitcher-by-Black-Hat-63129")
	end,
	["Hacklord"] = function()
		local url = "https://raw.githubusercontent.com/BloxinStud10/24-Hours/refs/heads/main/Obfuscations/Hacklord.luau"
		if makefolder or writefile then
			if not isfolder("24_HOURS") then makefolder("24_HOURS") end
			if not isfolder("24_HOURS/Loadstrings") then makefolder("24_HOURS/Loadstrings") end
			writefile("24_HOURS/Loadstrings/Hacklord", game:HttpGet(url))
			loadfile("24_HOURS/Loadstrings/Hacklord")()
		else
			loadstring(game:HttpGet(url))()
		end
	end,
	["Dual Sword"] = function()
		local urls = {
			"https://raw.githubusercontent.com/BloxinStud10/24-Hours/refs/heads/main/Obfuscations/DualSolarisV2.luau",
			"https://cdn.jsdelivr.net/gh/BloxinStud10/24-Hours@main/Obfuscations/DualSolarisV2.luau",
		}
		local request_ = (syn and syn.request) or request
		local source

		for _, url in next, urls do
			if request_ then
				local ok, res = pcall(request_, { Method = "GET", Url = url })
				if ok and res then
					source = res.Body
					break
				end
			else
				local ok, res = pcall(game.HttpGetAsync, game, url)
				if ok and res then
					source = res
					break
				end
			end
		end

		if source then
			loadstring(source)()
		else
			warn("Http buggin")
			Library:Notify("Dual Sword failed to download", 3)
		end
	end,
	["Goner"] = function()
		RunScript("https://raw.githubusercontent.com/GenesisFE/Genesis/main/Obfuscations/Goner")
	end,
	["Neptunian V"] = function()
		RunScript("https://raw.githubusercontent.com/GenesisFE/Genesis/main/Obfuscations/Neptunian%20V")
	end,
	["Lightning Cannon"] = function()
		RunScript("https://raw.githubusercontent.com/GenesisFE/Genesis/main/Obfuscations/Lightning%20Cannon")
	end,
	["Sin Dragon"] = function()
		RunScript("https://raw.githubusercontent.com/GenesisFE/Genesis/main/Obfuscations/Sin%20Dragon")
	end,
}

-- ============================================================================
-- UI
-- ============================================================================
local QuickGroup = Tabs.Main:AddRightGroupbox("Quick Commands")

for _, Entry in ipairs({
	{ "Rejoin", "-rj" },
	{ "Reset", "-re" },
	{ "Force Reset", "-pd ! -re" },
	{ "Remove Accessories", "-ch" },
	{ "Sit", "-sit" },
	{ "Dummy", "-dummy" },
	{ "R15", "-r15" },
	{ "R6", "-r6" },
	{ "Save Hats", "-sh" },
}) do
	QuickGroup:AddButton(Entry[1], function()
		SendChat(Entry[2])
	end)
end

QuickGroup:AddDivider()
QuickGroup:AddToggle("HideCommands", {
	Text = "Hide commands",
	Default = false,
	Tooltip = "Types commands as /e through the chat bar so others can't see them",
})

local HatsGroup = Tabs.Main:AddLeftGroupbox("Load Hats")
local ScriptsGroup = Tabs.Main:AddLeftGroupbox("Load Scripts")

local Order = {
	"Star Glitcher",
	"Hacklord",
	"Dual Sword",
	false, -- separator
	"Goner",
	"Neptunian V",
	"Lightning Cannon",
	"Sin Dragon",
}

for _, Name in ipairs(Order) do
	if not Name then
		HatsGroup:AddDivider()
		ScriptsGroup:AddDivider()
	else
		HatsGroup:AddButton(Name, function()
			LoadHats(HatIds[Name])
		end)

		ScriptsGroup:AddButton(Name, function()
			task.spawn(Scripts[Name])
		end)
	end
end

--// Watermark \\--
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
