local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager") 

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
local backpack = player:WaitForChild("Backpack")
local playerGui = player:WaitForChild("PlayerGui")
local playerStats = player:WaitForChild("Data")
local playerCodes = player:WaitForChild("Codes") -- Code Folder

local ServerHandler = ReplicatedStorage:WaitForChild("Game")
    :WaitForChild("Remotes")
    :WaitForChild("ServerHandler")
local CodesRemote = ReplicatedStorage:WaitForChild("Game")
    :WaitForChild("Remotes")
    :WaitForChild("Codes")

-- Farm Variables
local autoFarmEnabled = false
local autoDungeonEnabled = false
local autoAwakenEnabled = false
local connections = {}
local selectedNPCs = {}
local manualNPCs = {}
local currentStyles = {}
local currentStyleIndex = 1
local cycleTime = 5
local skillKeys = {"E", "Z", "X", "C", "T"}

local excludedStyles = {
    ["Flight"] = true,
    ["Teleporter"] = true
}

-- Update character vars on respawn
player.CharacterAdded:Connect(function(newChar)
    character = newChar
    humanoid = newChar:WaitForChild("Humanoid")
    humanoidRootPart = newChar:WaitForChild("HumanoidRootPart")
    playerGui = player:WaitForChild("PlayerGui")
end)

-- Window Setup
local Window = Fluent:CreateWindow({
    Title = "Anime Spirits",
    SubTitle = "Luceeal",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true, 
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl 
})

local Tabs = {
    Info = Window:AddTab({ Title = "Info", Icon = "info" }),
    Combat = Window:AddTab({ Title = "Combat", Icon = "sword" }),
    Utility = Window:AddTab({ Title = "Utility", Icon = "wrench" }), -- [NEW TAB]
    Teleport = Window:AddTab({ Title = "Teleport", Icon = "map" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

local Options = Fluent.Options

-- ==========================================
-- [[ INFO TAB LOGIC ]]
-- ==========================================

local InfoPlayerSection = Tabs.Info:AddSection("Player Stats")
local PlayerParagraph = InfoPlayerSection:AddParagraph({ Title = "Player Details", Content = "Loading..." })

local InfoStatSection = Tabs.Info:AddSection("Combat Stats (Base + Boost)")
local StatParagraph = InfoStatSection:AddParagraph({ Title = "Attributes", Content = "Loading..." })

task.spawn(function()
    while true do
        task.wait(1)
        if playerStats then
            pcall(function()
                local lvl = playerStats.Level.Value
                local perk = playerStats.Perk.Value
                local soul = playerStats.CurrentSoul.Value
                local spec = playerStats.CurrentSpec.Value
                local sword = playerStats.SwordEquipped.Value

                PlayerParagraph:SetDesc(
                    "Level: " .. tostring(lvl) .. "\n" ..
                    "Perk: " .. tostring(perk) .. "\n" ..
                    "Soul: " .. tostring(soul) .. "\n" ..
                    "Spec: " .. tostring(spec) .. "\n" ..
                    "Sword: " .. tostring(sword)
                )

                local str = playerStats.Strength.Value
                local strBoost = playerStats.StrengthBoost.Value
                local def = playerStats.Defense.Value
                local defBoost = playerStats.DefenseBoost.Value
                local soulStat = playerStats.Soul.Value
                local soulBoost = playerStats.SoulBoost.Value
                local swdStat = playerStats.Sword.Value
                local swdBoost = playerStats.SwordBoost.Value
                local stam = playerStats.Stamina.Value

                StatParagraph:SetDesc(
                    "Strength: " .. str .. " + " .. strBoost .. "\n" ..
                    "Defense: " .. def .. " + " .. defBoost .. "\n" ..
                    "Soul: " .. soulStat .. " + " .. soulBoost .. "\n" ..
                    "Sword: " .. swdStat .. " + " .. swdBoost .. "\n" ..
                    "Stamina: " .. stam
                )
            end)
        end
    end
end)

-- Anti AFK
local antiAfkEnabled = false
local antiAfkThread
local ANTI_AFK_INTERVAL = 180 

local function startAntiAfk()
    if antiAfkThread then return end
    antiAfkThread = task.spawn(function()
        while antiAfkEnabled do
            task.wait(ANTI_AFK_INTERVAL)
            if not antiAfkEnabled then break end
            VirtualUser:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
            task.wait(0.1)
            VirtualUser:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        end
    end)
end

local function stopAntiAfk()
    antiAfkEnabled = false
    antiAfkThread = nil
end

-- Targeting
local function getClosestTarget()
    local folders = {
        workspace:FindFirstChild("NPC's"),
        workspace:FindFirstChild("Boss"),
        workspace:FindFirstChild("NPCs")
    }

    local closest, bestDist = nil, math.huge
    for _, folder in pairs(folders) do
        if folder then
            for _, npc in pairs(folder:GetDescendants()) do
                if npc:IsA("Model")
                and npc:FindFirstChild("Humanoid")
                and npc.Humanoid.Health > 0
                and npc:FindFirstChild("HumanoidRootPart") then

                    local valid = false
                    if autoDungeonEnabled then
                        valid = true
                    elseif table.find(selectedNPCs, npc.Name)
                        or table.find(manualNPCs, npc.Name) then
                        valid = true
                    end

                    if valid then
                        local dist = (humanoidRootPart.Position - npc.HumanoidRootPart.Position).Magnitude
                        if dist < bestDist then
                            bestDist = dist
                            closest = npc
                        end
                    end
                end
            end
        end
    end
    return closest
end

local function stopAllSkills()
    for _, t in pairs(character:GetChildren()) do
        if t:IsA("Tool") then
            for _, key in ipairs(skillKeys) do
                ServerHandler:FireServer("SkillsControl", t.Name, key, "Release")
            end
        end
    end
end

-- ==========================================
-- [[ UI CONSTRUCTION ]]
-- ==========================================

-- [[ UTILITY TAB (NEW) ]]
local UtilityGeneral = Tabs.Utility:AddSection("General")

UtilityGeneral:AddButton({
    Title = "Redeem All Codes",
    Description = "Scans player data for codes and redeems them",
    Callback = function()
        task.spawn(function()
            if playerCodes then
                local children = playerCodes:GetChildren()
                if #children == 0 then
                     Fluent:Notify({Title="Codes", Content="No codes found to redeem.", Duration=3})
                     return
                end
                
                Fluent:Notify({Title="Codes", Content="Redeeming " .. #children .. " codes...", Duration=3})
                
                for _, codeObj in pairs(children) do
                    local codeName = codeObj.Name
                    -- Fire remote
                    CodesRemote:InvokeServer(codeName)
                    task.wait(0.1) -- Small delay to prevent spam kick
                end
                
                Fluent:Notify({Title="Codes", Content="All codes processed!", Duration=3})
            else
                Fluent:Notify({Title="Error", Content="Codes folder not found.", Duration=3})
            end
        end)
    end
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

-- [[ COMBAT TAB ]]
local DungeonSection = Tabs.Combat:AddSection("Dungeon Mode")

DungeonSection:AddToggle("AutoDungeon", {
    Title = "Auto Dungeon",
    Default = false,
    Callback = function(v)
        autoDungeonEnabled = v
    end
})

local CombatUtilitySection = Tabs.Combat:AddSection("Combat Tools")

CombatUtilitySection:AddToggle("AutoAwaken", {
    Title = "Auto Awaken",
    Description = "Spams awaken",
    Default = false,
    Callback = function(v)
        autoAwakenEnabled = v
        if v then
            task.spawn(function()
                while autoAwakenEnabled do
                    ServerHandler:FireServer("Awaken")
                    task.wait(2)
                end
            end)
        end
    end
})

-- Single Button for Buff & Shadow
CombatUtilitySection:AddButton({
    Title = "Cast Buffs & Shadows",
    Description = "Use V Skill of Souk, Weapons, And Fighting Style Then Use Specs",
    Callback = function()
        task.spawn(function()
            Fluent:Notify({Title="Status", Content="Starting Buff Sequence...", Duration=3})
            
            -- 1. Trigger Shadow (Once)
            local args = { true }
            local r1 = ReplicatedStorage:FindFirstChild("CommandUnspawnUnits")
            if r1 then r1:FireServer(unpack(args)) end
            task.wait(0.2)
            local r2 = ReplicatedStorage:FindFirstChild("CommandAttack")
            if r2 then r2:FireServer(unpack(args)) end

            -- 2. Cycle Weapons (Once)
            local myTools = {}
            for _, t in pairs(backpack:GetChildren()) do table.insert(myTools, t) end
            for _, t in pairs(character:GetChildren()) do if t:IsA("Tool") then table.insert(myTools, t) end end
            
            for _, tool in pairs(myTools) do
                if tool:IsA("Tool") and not excludedStyles[tool.Name] then
                    
                    humanoid:EquipTool(tool)
                    task.wait(0.8) 
                    
                    local targetPos = humanoidRootPart.Position + humanoidRootPart.CFrame.LookVector * 10
                    local lookCF = CFrame.lookAt(humanoidRootPart.Position, targetPos)

                    ServerHandler:FireServer("SkillsControl", tool.Name, "V", "Hold")
                    ServerHandler:FireServer("SkillsControl", tool.Name, "V", "Release", nil, lookCF)

                    local specName = nil
                    local slots = playerGui:FindFirstChild("HUD") and playerGui.HUD:FindFirstChild("SpecialSkills") and playerGui.HUD.SpecialSkills:FindFirstChild("Slots")
                    
                    if slots then
                        for _, frame in pairs(slots:GetChildren()) do
                            if frame:IsA("Frame") and frame.Name ~= "UIGridLayout" then 
                                specName = frame.Name
                                break 
                            end
                        end
                    end

                    if specName then
                        local specArgs = { "Specs", specName, targetPos }
                        ServerHandler:FireServer(unpack(specArgs))
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

local TargetDropdown = TargetSection:AddDropdown("SelectedNPCs", {
    Title = "Auto Selection",
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
    Title = "Refresh Target List",
    Callback = function()
        local list = {}
        local seen = {}
        for _, f in pairs({ workspace:FindFirstChild("NPC's"), workspace:FindFirstChild("Boss") }) do
            if f then
                for _, c in pairs(f:GetDescendants()) do
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
        TargetDropdown:SetValues(list)
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

local FarmToggle = FarmSection:AddToggle("AutoFarm", {
    Title = "Enable Auto Farm",
    Default = false,
    Callback = function(enabled)
        autoFarmEnabled = enabled

        if enabled then
            currentStyles = {}
            currentStyleIndex = 1
            local seen = {}
            
            for _, container in pairs({backpack, character}) do
                for _, tool in pairs(container:GetChildren()) do
                    if tool:IsA("Tool") and not excludedStyles[tool.Name] and not seen[tool.Name] then
                        seen[tool.Name] = true
                        table.insert(currentStyles, tool.Name)
                    end
                end
            end

            if #currentStyles == 0 then
                Fluent:Notify({ Title = "Error", Content = "No valid styles found!", Duration = 5 })
                Options.AutoFarm:SetValue(false)
                return
            end

            local firstTool = backpack:FindFirstChild(currentStyles[1])
            if firstTool then humanoid:EquipTool(firstTool) end

            connections.farm = RunService.Heartbeat:Connect(function()
                if not autoFarmEnabled then return end
                local target = getClosestTarget()
                if not target then return end

                local targetPos = target.HumanoidRootPart.Position
                local tpCF = target.HumanoidRootPart.CFrame * CFrame.new(0, 8, 3)
                humanoidRootPart.CFrame = CFrame.lookAt(tpCF.Position, targetPos)

                local style = currentStyles[currentStyleIndex]
                if style then
                    for _, key in ipairs(skillKeys) do
                        ServerHandler:FireServer("SkillsControl", style, key, "Hold")
                        ServerHandler:FireServer("SkillsControl", style, key, "Release", nil, CFrame.lookAt(humanoidRootPart.Position, targetPos))
                    end
                    for i = 1, 3 do
                        ServerHandler:FireServer("CombatControl", style, 1, false)
                    end
                end
            end)

            task.spawn(function()
                while autoFarmEnabled do
                    task.wait(cycleTime)
                    if not autoFarmEnabled then break end
                    currentStyleIndex = (currentStyleIndex % #currentStyles) + 1
                    local toolName = currentStyles[currentStyleIndex]
                    local tool = backpack:FindFirstChild(toolName)
                    if tool then humanoid:EquipTool(tool) end
                end
            end)
        else
            if connections.farm then connections.farm:Disconnect() end
            stopAllSkills()
        end
    end
})


-- [[ TELEPORT TAB ]]
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

local IslandDropdown = IslandSection:AddDropdown("IslandSelect", {
    Title = "Select Island",
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
        IslandDropdown:SetValues(getIslandList())
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

local DungeonDropdown = DungeonTeleSection:AddDropdown("DungeonSelect", {
    Title = "Select Dungeon",
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
        else
            Fluent:Notify({Title="Error", Content="Dungeon not found, refresh list.", Duration=3})
        end
    end
})

DungeonTeleSection:AddButton({
    Title = "Refresh Dungeons",
    Callback = function()
        DungeonDropdown:SetValues(getDungeonList())
    end
})

-- Finalization
Window:SelectTab(1)
Fluent:Notify({
    Title = "Loaded",
    Content = "Script Loaded Successfully",
    Duration = 5
})

SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)
Window:SelectTab(1)
