local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- =======================
-- SAFETY FIX (For "Attempt to call nil value" error)
-- =======================
local fireproximityprompt = fireproximityprompt or function(obj)
    if obj:IsA("ProximityPrompt") then
        if obj.Fire then
            obj:Fire()
        elseif obj.InputHoldBegin then
            obj:InputHoldBegin()
            task.wait(obj.HoldDuration or 0)
            obj:InputHoldEnd()
        else
            -- Fallback: Teleport extremely close to trigger automatic interaction if game allows
            game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = obj.Parent:GetPivot()
        end
    end
end

-- =======================
-- SERVICES
-- =======================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager") 
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
local playerGui = player:WaitForChild("PlayerGui")
local playerStats = player:WaitForChild("Data")
local playerCodes = player:WaitForChild("Codes") 

local ServerHandler = ReplicatedStorage:WaitForChild("Game"):WaitForChild("Remotes"):WaitForChild("ServerHandler")
local CodesRemote = ReplicatedStorage:WaitForChild("Game"):WaitForChild("Remotes"):WaitForChild("Codes")
local EffectsFolder = Workspace:WaitForChild("Effects")

-- Arise Info Module --
local AriseInfoModule = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("AriseInfo")
local AriseData = require(AriseInfoModule)

-- =======================
-- VARIABLES
-- =======================
local autoFarmEnabled = false
local autoDungeonEnabled = false
local autoAwakenEnabled = false
local autoSpecEnabled = false
local autoAriseEnabled = false 
local connections = {}
local selectedNPCs = {}
local manualNPCs = {}
local selectedAriseMonsters = {} 
local currentStyles = {}
local selectedFarmStyles = {} 
local currentStyleIndex = 1
local cycleTime = 5
local skillKeys = {"E", "Z", "X", "C", "T"}
local awakenThread = nil
local specThread = nil
local farmThread = nil
local weaponCycleThread = nil
local characterConnection = nil

local excludedStyles = {
    ["Flight"] = true,
    ["Teleporter"] = true
}

-- Performance optimization variables
local targetCache = {}
local lastCacheUpdate = 0
local CACHE_REFRESH_INTERVAL = 2

-- Cleanup function to prevent memory leaks
local function cleanupAllThreads()
    -- Cancel all active threads
    if farmThread then
        task.cancel(farmThread)
        farmThread = nil
    end
    if weaponCycleThread then
        task.cancel(weaponCycleThread)
        weaponCycleThread = nil
    end
    if awakenThread then
        task.cancel(awakenThread)
        awakenThread = nil
    end
    if specThread then
        task.cancel(specThread)
        specThread = nil
    end
    
    -- Disconnect all connections
    for _, conn in pairs(connections) do
        if conn and typeof(conn) == "RBXScriptConnection" then
            conn:Disconnect()
        end
    end
    connections = {}
    
    -- Clear target cache
    targetCache = {}
    lastCacheUpdate = 0
end

-- Helpers --
local function getAriseList()
    local list = {}
    if AriseData then
        for name, _ in pairs(AriseData) do
            table.insert(list, name)
        end
    end
    table.sort(list)
    return list
end

local function getLoadoutList()
    local list = {}
    if playerStats then
        if playerStats:FindFirstChild("MeleeEquipped") and playerStats.MeleeEquipped.Value ~= "None" then
            table.insert(list, playerStats.MeleeEquipped.Value)
        end
        if playerStats.CurrentSoul.Value ~= "None" then table.insert(list, playerStats.CurrentSoul.Value) end
        if playerStats.SwordEquipped.Value ~= "None" then table.insert(list, playerStats.SwordEquipped.Value) end
    end
    return list
end

-- Search-enabled dropdown helper
local function createSearchableDropdown(section, config)
    local allValues = config.Values or {}
    local currentSearch = ""
    
    -- Create search input
    local searchInput = section:AddInput(config.Title .. "_Search", {
        Title = "🔍 Search " .. config.Title,
        Default = "",
        Placeholder = "Type to filter...",
        Callback = function(text)
            currentSearch = text:lower()
            if currentSearch == "" then
                config.Dropdown:SetValues(allValues)
            else
                local filtered = {}
                for _, value in pairs(allValues) do
                    if string.find(value:lower(), currentSearch) then
                        table.insert(filtered, value)
                    end
                end
                config.Dropdown:SetValues(filtered)
            end
        end
    })
    
    -- Create actual dropdown
    local dropdown = section:AddDropdown(config.Name, {
        Title = config.Title,
        Values = allValues,
        Multi = config.Multi or false,
        Default = config.Default or (config.Multi and {} or nil),
        Callback = config.Callback
    })
    
    -- Store dropdown reference for external updates
    config.Dropdown = dropdown
    config.SearchInput = searchInput
    
    -- Return both for external control
    return dropdown, searchInput, function(newValues)
        allValues = newValues
        if currentSearch == "" then
            dropdown:SetValues(allValues)
        else
            local filtered = {}
            for _, value in pairs(allValues) do
                if string.find(value:lower(), currentSearch) then
                    table.insert(filtered, value)
                end
            end
            dropdown:SetValues(filtered)
        end
    end
end

-- Update character vars on respawn WITH CLEANUP --
if characterConnection then
    characterConnection:Disconnect()
end

characterConnection = player.CharacterAdded:Connect(function(newChar)
    -- Clean up everything from previous life
    cleanupAllThreads()
    
    -- Update character references
    character = newChar
    humanoid = newChar:WaitForChild("Humanoid")
    humanoidRootPart = newChar:WaitForChild("HumanoidRootPart")
    playerGui = player:WaitForChild("PlayerGui")
    
    -- Restart enabled features
    if wsEnabled or jpEnabled then
        startMovementLoop()
    end
    if antiAfkEnabled then
        startAntiAfk()
    end
end)

-- =======================
-- WINDOW SETUP
-- =======================
local Window = Fluent:CreateWindow({
    Title = "Anime Spirits",
    SubTitle = "Luceeal Fix - Optimized",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true, 
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl 
})

local Tabs = {
    Combat = Window:AddTab({ Title = "Combat", Icon = "sword" }),
    Arise = Window:AddTab({ Title = "Arise", Icon = "skull" }), 
    Utility = Window:AddTab({ Title = "Utility", Icon = "wrench" }), 
    Teleport = Window:AddTab({ Title = "Teleport", Icon = "map" }),
    Performance = Window:AddTab({ Title = "Performance", Icon = "bar-chart" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

local Options = Fluent.Options

-- =======================
-- LOGIC FUNCTIONS
-- =======================

-- Efficient Anti AFK --
local antiAfkEnabled = false
local antiAfkThread = nil
local ANTI_AFK_INTERVAL = 180 

local function startAntiAfk()
    -- Always stop existing thread first
    if antiAfkThread then
        task.cancel(antiAfkThread)
        antiAfkThread = nil
    end
    
    if not antiAfkEnabled then return end
    
    antiAfkThread = task.spawn(function()
        while antiAfkEnabled do
            task.wait(ANTI_AFK_INTERVAL)
            if not antiAfkEnabled then break end
            
            pcall(function()
                VirtualUser:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
                task.wait(0.1)
                VirtualUser:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
            end)
        end
        antiAfkThread = nil
    end)
end

local function stopAntiAfk()
    antiAfkEnabled = false
    if antiAfkThread then
        task.cancel(antiAfkThread)
        antiAfkThread = nil
    end
end

-- OPTIMIZED: Target Cache System with Dead NPC Cleanup --
local function updateTargetCache()
    targetCache = {}
    local potentialFolders = {
        Workspace:FindFirstChild("NPC's"),
        Workspace:FindFirstChild("Boss"),
        Workspace:FindFirstChild("NPCs")
    }

    for _, folder in pairs(potentialFolders) do
        if folder then
            for _, npc in pairs(folder:GetChildren()) do 
                if npc:IsA("Model") 
                and npc:FindFirstChild("Humanoid") 
                and npc.Humanoid.Health > 0 
                and npc:FindFirstChild("HumanoidRootPart") then
                    table.insert(targetCache, npc)
                end
            end
        end
    end
end

-- OPTIMIZED: Targeting (Uses Cache with validation) --
local function getClosestTarget()
    -- Refresh cache if needed
    if os.clock() - lastCacheUpdate > CACHE_REFRESH_INTERVAL then
        updateTargetCache()
        lastCacheUpdate = os.clock()
    end

    local closest, bestDist = nil, math.huge
    local myPos = humanoidRootPart.Position

    -- Clean up invalid targets while searching
    local validCache = {}
    for _, npc in pairs(targetCache) do
        -- Validate NPC still exists and is alive
        if npc and npc.Parent and npc:FindFirstChild("Humanoid") and npc.Humanoid.Health > 0 then
            table.insert(validCache, npc)
            
            local valid = false
            if autoDungeonEnabled then
                valid = true
            elseif table.find(selectedNPCs, npc.Name) or table.find(manualNPCs, npc.Name) then
                valid = true
            end

            if valid then
                local dist = (myPos - npc.HumanoidRootPart.Position).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    closest = npc
                end
            end
        end
    end
    
    -- Update cache with only valid targets
    targetCache = validCache
    
    return closest
end

-- =======================
-- ARISE LOGIC (OPTIMIZED)
-- =======================
local function processAriseEntity(child)
    if not autoAriseEnabled then return end
    if table.find(selectedAriseMonsters, child.Name) then
        local prompt = child:WaitForChild("Arise", 3)
        if prompt then
            -- Teleport logic
            if child:IsA("BasePart") then
                humanoidRootPart.CFrame = child.CFrame * CFrame.new(0, 5, 0)
            elseif child:IsA("Model") then
                local pivot = child:GetPivot()
                if pivot then humanoidRootPart.CFrame = pivot * CFrame.new(0, 5, 0) end
            end
             
            task.wait(0.3)
            fireproximityprompt(prompt)
        end
    end
end
EffectsFolder.ChildAdded:Connect(processAriseEntity)


-- =======================
-- UTILITY TAB
-- =======================
local UtilityGeneral = Tabs.Utility:AddSection("General")

UtilityGeneral:AddButton({
    Title = "Redeem All Codes",
    Description = "Scans player data for codes and redeems them",
    Callback = function()
        task.spawn(function()
            if playerCodes then
                local children = playerCodes:GetChildren()
                if #children == 0 then
                      Fluent:Notify({Title="Codes", Content="No codes found.", Duration=3})
                      return
                end
                
                Fluent:Notify({Title="Codes", Content="Redeeming " .. #children .. " codes...", Duration=3})
                for _, codeObj in pairs(children) do
                    CodesRemote:InvokeServer(codeObj.Name)
                    task.wait(0.1) 
                end
                Fluent:Notify({Title="Codes", Content="Completed!", Duration=3})
            end
        end)
    end
})

local UtilityPlayer = Tabs.Utility:AddSection("Player Movement")

-- Variables for movement
local wsEnabled = false
local wsValue = 16
local jpEnabled = false
local jpValue = 50
local infJumpEnabled = false
local movementThread = nil

-- OPTIMIZED: Movement Loop (Only runs when enabled)
local function startMovementLoop()
    if movementThread then return end
    movementThread = task.spawn(function()
        while wsEnabled or jpEnabled do
            task.wait(0.5) 
            if humanoid then
                if wsEnabled and humanoid.WalkSpeed ~= wsValue then
                    humanoid.WalkSpeed = wsValue
                end
                if jpEnabled and humanoid.JumpPower ~= jpValue then
                    humanoid.UseJumpPower = true
                    humanoid.JumpPower = jpValue
                end
            end
        end
        movementThread = nil
    end)
end

local function stopMovementLoop()
    if movementThread then
        task.cancel(movementThread)
        movementThread = nil
    end
end

UserInputService.JumpRequest:Connect(function()
    if infJumpEnabled and humanoid then
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

UtilityPlayer:AddToggle("InfiniteJump", {
    Title = "Infinite Jump",
    Default = false,
    Callback = function(v) infJumpEnabled = v end
})

UtilityPlayer:AddToggle("WalkSpeedToggle", {
    Title = "Enable WalkSpeed",
    Default = false,
    Callback = function(v) 
        wsEnabled = v 
        if v then
            startMovementLoop()
        elseif not jpEnabled then
            stopMovementLoop()
        end
        if not v and humanoid then humanoid.WalkSpeed = 16 end
    end
})

UtilityPlayer:AddSlider("WalkSpeedSlider", {
    Title = "WalkSpeed Amount",
    Description = "Adjust your speed",
    Default = 16,
    Min = 16,
    Max = 300,
    Rounding = 0,
    Callback = function(v) wsValue = v end
})

UtilityPlayer:AddToggle("JumpPowerToggle", {
    Title = "Enable JumpPower",
    Default = false,
    Callback = function(v) 
        jpEnabled = v 
        if v then
            startMovementLoop()
        elseif not wsEnabled then
            stopMovementLoop()
        end
        if not v and humanoid then humanoid.JumpPower = 50 end
    end
})

UtilityPlayer:AddSlider("JumpPowerSlider", {
    Title = "JumpPower Amount",
    Description = "Adjust your jump height",
    Default = 50,
    Min = 50,
    Max = 300,
    Rounding = 0,
    Callback = function(v) jpValue = v end
})


local UtilityAFK = Tabs.Utility:AddSection("AFK")

UtilityAFK:AddToggle("AntiAFK", {
    Title = "Anti AFK",
    Description = "Prevents idle kick",
    Default = false,
    Callback = function(v)
        antiAfkEnabled = v
        if v then startAntiAfk() else stopAntiAfk() end
    end
})

-- =======================
-- PERFORMANCE TAB
-- =======================
local PerfSection = Tabs.Performance:AddSection("Rendering")

PerfSection:AddToggle("RenderToggle", {
    Title = "Disable 3D Rendering",
    Description = "Turns screen black to save CPU/GPU. Good for AFK.",
    Default = false,
    Callback = function(v)
        RunService:Set3dRenderingEnabled(not v)
    end
})

-- =======================
-- ARISE TAB
-- =======================
local AriseSection = Tabs.Arise:AddSection("Auto Arise Configuration")

local AriseDropdown, AriseSearch, updateAriseList = createSearchableDropdown(AriseSection, {
    Name = "AriseSelector",
    Title = "Monsters to Arise",
    Values = getAriseList(),
    Multi = true,
    Default = {},
    Callback = function(v)
        selectedAriseMonsters = {}
        for name, selected in pairs(v) do
            if selected then table.insert(selectedAriseMonsters, name) end
        end
    end
})

AriseSection:AddButton({
    Title = "Refresh List",
    Callback = function()
        updateAriseList(getAriseList())
    end
})

AriseSection:AddToggle("AutoArise", {
    Title = "Enable Auto Arise",
    Description = "Automatically teleports to and arises selected monsters",
    Default = false,
    Callback = function(v)
        autoAriseEnabled = v
        if v then
            -- Initial scan for existing effects
            for _, child in pairs(EffectsFolder:GetChildren()) do
                processAriseEntity(child)
            end
        end
    end
})


-- =======================
-- COMBAT TAB
-- =======================
local DungeonSection = Tabs.Combat:AddSection("Dungeon Mode")

DungeonSection:AddToggle("AutoDungeon", {
    Title = "Auto Dungeon",
    Default = false,
    Callback = function(v) autoDungeonEnabled = v end
})

local CombatUtilitySection = Tabs.Combat:AddSection("Combat Tools")

CombatUtilitySection:AddToggle("AutoAwaken", {
    Title = "Auto Awaken",
    Description = "Spams awaken",
    Default = false,
    Callback = function(v)
        autoAwakenEnabled = v
        
        -- Stop existing thread
        if awakenThread then
            task.cancel(awakenThread)
            awakenThread = nil
        end
        
        -- Start new thread if enabled
        if v then
            awakenThread = task.spawn(function()
                while autoAwakenEnabled do
                    ServerHandler:FireServer("Awaken")
                    task.wait(5)  -- Increased to 5 seconds (more realistic cooldown)
                end
                awakenThread = nil
            end)
        end
    end
})

CombatUtilitySection:AddToggle("AutoSpec", {
    Title = "Auto Use Spec (Aim Forward)",
    Description = "Fires spec where you look immediately",
    Default = false,
    Callback = function(v)
        autoSpecEnabled = v
        
        -- Stop existing thread
        if specThread then
            task.cancel(specThread)
            specThread = nil
        end
        
        -- Start new thread if enabled
        if v then
            specThread = task.spawn(function()
                while autoSpecEnabled do
                    if playerStats:FindFirstChild("CurrentSpec") then
                        local currentSpec = playerStats.CurrentSpec.Value
                        if currentSpec and currentSpec ~= "None" then
                            local forwardPos = humanoidRootPart.Position + (humanoidRootPart.CFrame.LookVector * 50)
                            local args = { "Specs", currentSpec, forwardPos }
                            ServerHandler:FireServer(unpack(args))
                        end
                    end
                    task.wait(1)  -- Increased from 0.5 to 1 second
                end
                specThread = nil
            end)
        end
    end
})

-- Auto Buff --
CombatUtilitySection:AddButton({
    Title = "Cast Buffs & Shadows",
    Description = "Use V Skill of Soul, Weapons, And Fighting Style Then Use Specs",
    Callback = function()
        task.spawn(function()
            Fluent:Notify({Title="Status", Content="Starting Buff Sequence...", Duration=3})
             
            -- Trigger Shadow
            local args = { true }
            local r1 = ReplicatedStorage:FindFirstChild("CommandUnspawnUnits")
            if r1 then r1:FireServer(unpack(args)) end
            task.wait(0.2)
            local r2 = ReplicatedStorage:FindFirstChild("CommandAttack")
            if r2 then r2:FireServer(unpack(args)) end

            -- Cycle Weapons
            local myTools = {}
            local currentBackpack = player.Backpack
            
            for _, t in pairs(currentBackpack:GetChildren()) do table.insert(myTools, t) end
            for _, t in pairs(character:GetChildren()) do if t:IsA("Tool") then table.insert(myTools, t) end end
             
            for _, tool in pairs(myTools) do
                if tool:IsA("Tool") and not excludedStyles[tool.Name] then
                    humanoid:EquipTool(tool)
                    task.wait(0.8) 
                     
                    local targetPos = humanoidRootPart.Position + humanoidRootPart.CFrame.LookVector * 10
                    local lookCF = CFrame.lookAt(humanoidRootPart.Position, targetPos)

                    ServerHandler:FireServer("SkillsControl", tool.Name, "V", "Hold")
                    ServerHandler:FireServer("SkillsControl", tool.Name, "V", "Release", nil, lookCF)

                    -- Trigger Spec if available
                    if playerGui:FindFirstChild("HUD") then
                        local slots = playerGui.HUD:FindFirstChild("SpecialSkills") and playerGui.HUD.SpecialSkills:FindFirstChild("Slots")
                        if slots then
                            local specName = nil
                            for _, frame in pairs(slots:GetChildren()) do
                                if frame:IsA("Frame") and frame.Name ~= "UIGridLayout" then 
                                    specName = frame.Name; break 
                                end
                            end
                            if specName then
                                ServerHandler:FireServer("Specs", specName, targetPos)
                            end
                        end
                    end
                     
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.V, false, game)
                    task.wait(0.1)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.V, false, game)
                    task.wait(5) 
                end
            end
            Fluent:Notify({Title="Status", Content="Buff Sequence Complete!", Duration=5})
        end)
    end
})

local TargetSection = Tabs.Combat:AddSection("Targeting")

local TargetDropdown, TargetSearch, updateTargetList = createSearchableDropdown(TargetSection, {
    Name = "SelectedNPCs",
    Title = "Monsters",
    Values = {},
    Multi = true,
    Default = {},
    Callback = function(v)
        selectedNPCs = {}
        for name, selected in pairs(v) do
            if selected then table.insert(selectedNPCs, name) end
        end
    end
})

TargetSection:AddButton({
    Title = "Refresh Monsters List",
    Callback = function()
        local list = {}
        local seen = {}
        for _, f in pairs({ workspace:FindFirstChild("NPC's"), workspace:FindFirstChild("Boss") }) do
            if f then
                for _, c in pairs(f:GetChildren()) do 
                    if c:IsA("Model") and c:FindFirstChild("Humanoid") then
                        if not seen[c.Name] then
                            seen[c.Name] = true
                            table.insert(list, c.Name)
                        end
                    end
                end
            end
        end
        table.sort(list)
        updateTargetList(list)
    end
})

TargetSection:AddInput("ManualInput", {
    Title = "Manual Input",
    Default = "",
    Placeholder = "Enemy1, Enemy2",
    Callback = function(text)
        manualNPCs = {}
        for name in string.gmatch(text, "[^,]+") do
            table.insert(manualNPCs, string.gsub(name, "^%s*(.-)%s*$", "%1"))
        end
    end
})

local FarmSection = Tabs.Combat:AddSection("Execution")

FarmSection:AddInput("CycleTime", {
    Title = "Cycle Time (sec)",
    Default = "5",
    Numeric = true,
    Callback = function(text)
        cycleTime = tonumber(text) or 5
    end
})

local StyleSelector, StyleSearch, updateStyleList = createSearchableDropdown(FarmSection, {
    Name = "StyleSelector",
    Title = "Weapons to Use",
    Values = getLoadoutList(),
    Multi = true,
    Default = {},
    Callback = function(v)
        selectedFarmStyles = {}
        for name, selected in pairs(v) do
            if selected then table.insert(selectedFarmStyles, name) end
        end
    end
})

FarmSection:AddButton({
    Title = "Refresh Weapons",
    Callback = function() 
        updateStyleList(getLoadoutList())
    end
})

-- OPTIMIZED: Auto Farm (Uses task.spawn loop instead of Heartbeat)
local FarmToggle = FarmSection:AddToggle("AutoFarm", {
    Title = "Enable Auto Farm",
    Default = false,
    Callback = function(enabled)
        autoFarmEnabled = enabled

        -- CLEANUP OLD THREADS FIRST
        if farmThread then
            task.cancel(farmThread)
            farmThread = nil
        end
        if weaponCycleThread then
            task.cancel(weaponCycleThread)
            weaponCycleThread = nil
        end

        if enabled then
            currentStyles = {}
            currentStyleIndex = 1
            local seen = {}
            
            local currentBackpack = player.Backpack 

            if #selectedFarmStyles == 0 then
                Fluent:Notify({ Title = "Error", Content = "Select weapons in dropdown!", Duration = 5 })
                Options.AutoFarm:SetValue(false)
                return
            end

            for _, styleName in pairs(selectedFarmStyles) do
                local tool = currentBackpack:FindFirstChild(styleName) or character:FindFirstChild(styleName)
                if tool then 
                    if not seen[tool.Name] then
                        seen[tool.Name] = true
                        table.insert(currentStyles, tool.Name)
                    end
                end
            end

            -- Fallback Fuzzy Search if exact match fails
            if #currentStyles == 0 then
                for _, styleName in pairs(selectedFarmStyles) do
                     for _, item in pairs(currentBackpack:GetChildren()) do
                        if item:IsA("Tool") and string.find(item.Name, styleName) then
                             if not seen[item.Name] then
                                seen[item.Name] = true
                                table.insert(currentStyles, item.Name)
                             end
                        end
                     end
                end
            end

            if #currentStyles == 0 then
                Fluent:Notify({ Title = "Error", Content = "Weapons not found in inventory!", Duration = 5 })
                Options.AutoFarm:SetValue(false)
                return
            end

            local firstTool = currentBackpack:FindFirstChild(currentStyles[1])
            if firstTool then humanoid:EquipTool(firstTool) end

            -- MAIN FARM LOOP (Optimized - 10 ticks per second instead of 60+)
            farmThread = task.spawn(function()
                while autoFarmEnabled do
                    pcall(function()
                        local target = getClosestTarget()
                        if target and target:FindFirstChild("HumanoidRootPart") then
                            local targetPos = target.HumanoidRootPart.Position
                            local tpCF = target.HumanoidRootPart.CFrame * CFrame.new(0, 0, 2)
                            humanoidRootPart.CFrame = CFrame.lookAt(tpCF.Position, targetPos)

                            local style = currentStyles[currentStyleIndex]
                            if style then
                                for _, key in ipairs(skillKeys) do
                                    ServerHandler:FireServer("SkillsControl", style, key, "Hold")
                                    ServerHandler:FireServer("SkillsControl", style, key, "Release", targetPos, CFrame.lookAt(humanoidRootPart.Position, targetPos))
                                end
                                for i = 1, 3 do
                                    ServerHandler:FireServer("CombatControl", style, 1, false)
                                end
                            end
                        end
                    end)
                    task.wait(0.1) -- 10 ticks per second (reduced from 60+)
                end
                farmThread = nil
            end)

            -- Weapon cycling thread
            weaponCycleThread = task.spawn(function()
                while autoFarmEnabled do
                    task.wait(cycleTime)
                    if not autoFarmEnabled then break end
                    
                    pcall(function()
                        currentStyleIndex = (currentStyleIndex % #currentStyles) + 1
                        local toolName = currentStyles[currentStyleIndex]
                        local tool = player.Backpack:FindFirstChild(toolName)
                        if tool then humanoid:EquipTool(tool) end
                    end)
                end
                weaponCycleThread = nil
            end)
        end
    end
})


-- =======================
-- TELEPORT TAB
-- =======================
local IslandSection = Tabs.Teleport:AddSection("Islands")
local spawnPointsFolder = workspace:WaitForChild("SpawnPoints", 10)
local selectedIsland = nil

local function getIslandList()
    local names = {}
    if spawnPointsFolder then
        for _, child in pairs(spawnPointsFolder:GetChildren()) do
            if child:IsA("BasePart") or child:IsA("SpawnLocation") then
                table.insert(names, child.Name)
            end
        end
        table.sort(names)
    end
    return names
end

local IslandDropdown, IslandSearch, updateIslandList = createSearchableDropdown(IslandSection, {
    Name = "IslandSelect",
    Title = "Island",
    Values = getIslandList(),
    Multi = false,
    Default = nil,
    Callback = function(value) 
        selectedIsland = value 
    end
})

IslandSection:AddButton({
    Title = "Teleport to Island",
    Callback = function()
        if not selectedIsland then 
            Fluent:Notify({Title="Error", Content="Select an island first!", Duration=3}) 
            return 
        end
        local target = spawnPointsFolder:FindFirstChild(selectedIsland)
        if target then
            humanoidRootPart.CFrame = target.CFrame + Vector3.new(0, 5, 0)
            Fluent:Notify({Title="Teleported", Content="Arrived at "..selectedIsland, Duration=3})
        end
    end
})

IslandSection:AddButton({
    Title = "Refresh Islands",
    Callback = function() 
        updateIslandList(getIslandList())
    end
})

local DungeonTeleSection = Tabs.Teleport:AddSection("Dungeons")
local dungeonMap = {}
local selectedDungeon = nil

local function getDungeonList()
    dungeonMap = {}
    local names = {}
    local dungeonFolder = workspace:FindFirstChild("DungeonTeleporters")
    if dungeonFolder then
        for _, model in pairs(dungeonFolder:GetChildren()) do
            local success, dungeonName = pcall(function()
                return model.TeleportingZone.AboveUi.Frame.DungeonType.Text
            end)
            if success and dungeonName and dungeonName ~= "" then
                dungeonMap[dungeonName] = model
                if not table.find(names, dungeonName) then
                    table.insert(names, dungeonName)
                end
            end
        end
    end
    table.sort(names)
    return names
end

local DungeonDropdown, DungeonSearch, updateDungeonList = createSearchableDropdown(DungeonTeleSection, {
    Name = "DungeonSelect",
    Title = "Dungeon",
    Values = getDungeonList(),
    Multi = false,
    Default = nil,
    Callback = function(value) 
        selectedDungeon = value 
    end
})

DungeonTeleSection:AddButton({
    Title = "Teleport to Dungeon",
    Callback = function()
        if not selectedDungeon then
            Fluent:Notify({Title="Error", Content="Select a dungeon first!", Duration=3})
            return
        end
        local model = dungeonMap[selectedDungeon]
        if model then
            humanoidRootPart.CFrame = model:GetPivot() * CFrame.new(0, 5, 0)
            Fluent:Notify({Title="Teleported", Content="Arrived at "..selectedDungeon, Duration=3})
        end
    end
})

DungeonTeleSection:AddButton({
    Title = "Refresh Dungeons",
    Callback = function() 
        updateDungeonList(getDungeonList())
    end
})

-- =======================
-- FINALIZATION
-- =======================
Window:SelectTab(1)
Fluent:Notify({
    Title = "Loaded",
    Content = "Luceeal Hub Loaded Successfully (Optimized)",
    Duration = 5
})

SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)
Window:SelectTab(1)

-- =======================
-- TOGGLE BUTTON (GUI)
-- =======================
if CoreGui:FindFirstChild("LuceealHubToggle") then
    CoreGui.LuceealHubToggle:Destroy()
end

local ToggleGui = Instance.new("ScreenGui")
local ToggleBtn = Instance.new("ImageButton") 
local UICorner = Instance.new("UICorner")

ToggleGui.Name = "LuceealHubToggle"
ToggleGui.Parent = CoreGui
ToggleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

ToggleBtn.Name = "ToggleButton"
ToggleBtn.Parent = ToggleGui
ToggleBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.BackgroundTransparency = 1 
ToggleBtn.Position = UDim2.new(0, 10, 0.5, 0)
ToggleBtn.Size = UDim2.new(0, 50, 0, 50) 

ToggleBtn.Image = "rbxassetid://97358295911421"

ToggleBtn.Draggable = true
ToggleBtn.AutoButtonColor = true

UICorner.CornerRadius = UDim.new(0, 12)
UICorner.Parent = ToggleBtn

ToggleBtn.MouseButton1Click:Connect(function()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftControl, false, game)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftControl, false, game)
end)
