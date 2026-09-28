-- ============================================================
-- YBA Controller v7.3 (Kavo UI + Working AutoSell)
-- ============================================================
print("[YBA Controller] Загрузка v7.3...")
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()

-- ============================================================
-- 1. НАСТРОЙКИ
-- ============================================================
local TARGET_ITEMS = {
    "Rokakaka", "Lucky Arrow", "Caesar's Headband", "Clackers",
    "Ancient Scroll", "Diamond", "Dio's Diary", "Gold Coin",
    "Lucky Stone Mask", "Mysterious Arrow", "Pure Rokakaka",
    "Quinton's Glove", "Rib Cage of The Saint's Corpse",
    "Steel Ball", "Stone Mask", "Zeppeli's Hat",
}

local LUCKY_ARROW_PRICE = 75000
local PICKUP_COOLDOWN = 0.5
local SELL_COOLDOWN = 5  -- Проверка продажи раз в 5 секунд

local State = {
    ESP = true,
    AutoFarm = false,
    AutoSell = false,
    Noclip = false,
    Speed = false,
    AutoBuyLucky = false,
    FlySpeed = 80,
    PickupRange = 5,
    WalkSpeed = 30,
}

-- ============================================================
-- 2. СЕРВИСЫ
-- ============================================================
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- 3. ESP
-- ============================================================
local espObjects = {}

local function createESP(part, itemName)
    if not part or espObjects[part] then return end
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "YBA_ItemESP"
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = part
    billboard.Parent = part

    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = itemName
    textLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    textLabel.TextStrokeTransparency = 0
    textLabel.TextScaled = true
    textLabel.Font = Enum.Font.SourceSansBold
    textLabel.Parent = billboard
    espObjects[part] = billboard
end

local function clearAllESP()
    for _, gui in pairs(espObjects) do
        if gui and gui.Parent then gui:Destroy() end
    end
    espObjects = {}
end

local function getValidItems()
    local validItems = {}
    local itemsFolder = Workspace:FindFirstChild("Item_Spawns")
    if not itemsFolder then return validItems end
    local items = itemsFolder:FindFirstChild("Items")
    if not items then return validItems end

    for _, model in ipairs(items:GetChildren()) do
        if model:IsA("Model") then
            local prompt = model:FindFirstChildOfClass("ProximityPrompt")
            if prompt and prompt.ActionText == "Pick Up" then
                local itemName = prompt.ObjectText
                local mesh = model:FindFirstChildOfClass("MeshPart") or model:FindFirstChildOfClass("BasePart")
                if mesh and mesh.Transparency < 1 then
                    table.insert(validItems, {model = model, prompt = prompt, mesh = mesh, name = itemName})
                end
            end
        end
    end
    return validItems
end

local function scanForItems()
    if not State.ESP then return end
    local items = getValidItems()
    for _, data in ipairs(items) do
        for _, targetName in ipairs(TARGET_ITEMS) do
            if string.find(data.name:lower(), targetName:lower(), 1, true) then
                createESP(data.mesh, data.name)
                break
            end
        end
    end
end

local function cleanupESP()
    for part, gui in pairs(espObjects) do
        if not part or not part.Parent or part.Transparency >= 1 then
            gui:Destroy()
            espObjects[part] = nil
        end
    end
end

-- ============================================================
-- 4. AUTOFARM
-- ============================================================
local function findNearestItem()
    local char = LocalPlayer.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end

    local nearest, minDist = nil, math.huge
    local items = getValidItems()
    for _, data in ipairs(items) do
        for _, targetName in ipairs(TARGET_ITEMS) do
            if string.find(data.name:lower(), targetName:lower(), 1, true) then
                local dist = (data.mesh.Position - root.Position).Magnitude
                if dist < minDist then
                    nearest, minDist = data, dist
                end
                break
            end
        end
    end
    return nearest
end

local flyConnection = nil
local cachedTarget = nil
local lastScanTime = 0
local lastPickupTime = 0

local function startAutoFarm()
    if flyConnection then return end
    flyConnection = RunService.Heartbeat:Connect(function(dt)
        if not State.AutoFarm then return end
        local char = LocalPlayer.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end

        if tick() - lastPickupTime < PICKUP_COOLDOWN then
            root.AssemblyLinearVelocity = Vector3.zero
            return
        end

        local now = tick()
        if now - lastScanTime > 0.5 or not cachedTarget or not cachedTarget.mesh.Parent then
            cachedTarget = findNearestItem()
            lastScanTime = now
        end

        local target = cachedTarget
        if not target then return end

        local targetPos = target.mesh.Position
        local dist = (targetPos - root.Position).Magnitude

        if dist <= State.PickupRange then
            root.AssemblyLinearVelocity = Vector3.zero
            if fireproximityprompt then
                pcall(function() fireproximityprompt(target.prompt) end)
                print("[AutoFarm] Подобрал: " .. target.name)
                lastPickupTime = tick()
            end
            cachedTarget = nil
            lastScanTime = 0
            return
        end

        local dir = targetPos - root.Position
        local step = math.min(State.FlySpeed * dt, dist - (State.PickupRange - 0.5))
        if step > 0 then
            local newPos = root.Position + dir.Unit * step
            root.CFrame = CFrame.new(newPos, newPos + dir.Unit)
            root.AssemblyLinearVelocity = Vector3.zero
        end
    end)
end

local function stopAutoFarm()
    if flyConnection then flyConnection:Disconnect(); flyConnection = nil end
    cachedTarget = nil
    lastScanTime = 0
    local char = LocalPlayer.Character
    if char then
        local root = char:FindFirstChild("HumanoidRootPart")
        if root then root.AssemblyLinearVelocity = Vector3.zero end
    end
end

-- ============================================================
-- 5. AUTOSELL (ИСПРАВЛЕНО)
-- ============================================================

local function hasItemsInBackpack()
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return false end
    for _, item in ipairs(backpack:GetChildren()) do
        if item:IsA("Tool") then return true end
    end
    return false
end

-- Поиск торговца: ищем в Workspace.Dialogues модель с ProximityPrompt "Interact"
local function findMerchant()
    local dialogues = Workspace:FindFirstChild("Dialogues")
    if dialogues then
        for _, obj in ipairs(dialogues:GetChildren()) do
            if obj:IsA("Model") then
                local prompt = obj:FindFirstChildOfClass("ProximityPrompt")
                if prompt and prompt.ActionText == "Interact" then
                    return obj, prompt
                end
            end
        end
    end
    -- Запасной поиск по всему Workspace
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:lower():find("merchant") then
            local prompt = obj:FindFirstChildOfClass("ProximityPrompt")
            if prompt then return obj, prompt end
        end
    end
    return nil, nil
end

-- Телепорт к торговцу
local function teleportToMerchant(merchant)
    if not merchant then return end
    local char = LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local pos = nil
    if merchant:IsA("Model") then
        if merchant.PrimaryPart then
            pos = merchant.PrimaryPart.Position
        else
            local part = merchant:FindFirstChildWhichIsA("BasePart")
            if part then pos = part.Position end
        end
    end
    if pos then
        root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 3))
    end
end

-- Нажатие кнопки "I'll sell ALL of these"
local function clickSellAllButton()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return false end
    
    for _, gui in ipairs(playerGui:GetChildren()) do
        for _, obj in ipairs(gui:GetDescendants()) do
            if obj:IsA("TextButton") then
                local txt = (obj.Text or ""):lower()
                if txt:find("sell") and txt:find("all") then
                    pcall(function() obj:Fire("MouseButton1Click") end)
                    pcall(function() obj:Fire("MouseButton1Down") end)
                    pcall(function() obj:Fire("MouseButton1Up") end)
                    print("[AutoSell] Нажал: " .. obj.Text)
                    return true
                end
            end
        end
    end
    return false
end

local lastSellAttempt = 0

local function autoSellItems()
    if not State.AutoSell then return end
    if not hasItemsInBackpack() then return end
    if tick() - lastSellAttempt < SELL_COOLDOWN then return end
    lastSellAttempt = tick()
    
    print("[AutoSell] Есть предметы. Ищу торговца...")
    local merchant, prompt = findMerchant()
    if not merchant then
        print("[AutoSell] Торговец не найден.")
        return
    end
    print("[AutoSell] Найден торговец: " .. merchant:GetFullName())
    
    -- 1. Подлетаем к торговцу
    teleportToMerchant(merchant)
    task.wait(0.5)
    
    -- 2. Открываем диалог
    print("[AutoSell] Открываю диалог...")
    pcall(function() fireproximityprompt(prompt) end)
    task.wait(1) -- Ждем, пока GUI загрузится
    
    -- 3. Нажимаем кнопку продажи
    local clicked = clickSellAllButton()
    if clicked then
        print("[AutoSell] Продажа выполнена.")
    else
        print("[AutoSell] Кнопка 'Sell ALL' не найдена. Проверьте, открылся ли диалог.")
    end
end

-- ============================================================
-- 6. АВТОПОКУПКА LUCKY ARROW
-- ============================================================
local function getPlayerMoney()
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        local cash = leaderstats:FindFirstChild("Cash") or leaderstats:FindFirstChild("Money")
        if cash and cash:IsA("IntValue") then return cash.Value end
    end
    local attr = LocalPlayer:GetAttribute("Money") or LocalPlayer:GetAttribute("Cash")
    if typeof(attr) == "number" then return attr end
    return nil
end

local function findSellRemote()
    local plr = LocalPlayer
    if plr and plr.Character then
        for _, obj in pairs(plr.Character:GetChildren()) do
            if obj:IsA("RemoteEvent") then return obj end
        end
    end
    local places = { Workspace, game:GetService("ReplicatedStorage") }
    for _, place in pairs(places) do
        if place then
            for _, obj in pairs(place:GetDescendants()) do
                if obj:IsA("RemoteEvent") then
                    local n = obj.Name:lower()
                    if n:find("remote") or n:find("sell") or n:find("server") then
                        return obj
                    end
                end
            end
        end
    end
    return nil
end

local function buyLuckyArrow()
    local char = LocalPlayer.Character
    if not char then return false end
    local money = getPlayerMoney()
    if money == nil or money < LUCKY_ARROW_PRICE then return false end
    local remote = char:FindFirstChild("RemoteEvent") or findSellRemote()
    if not remote then return false end
    local args = {"PurchaseShopItem", {["ItemName"] = "Lucky Arrow"}, 1, 2}
    local success = pcall(function() remote:FireServer(unpack(args)) end)
    if success then print(string.format("[AutoBuy] Куплен Lucky Arrow. Баланс: $%d", money)) end
    return success
end

-- ============================================================
-- 7. NOCLIP & SPEED
-- ============================================================
local noclipConnection = nil
local function applyNoclip()
    local char = LocalPlayer.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
    end
end

local function startNoclip()
    if noclipConnection then return end
    noclipConnection = RunService.Stepped:Connect(function()
        if State.Noclip then pcall(applyNoclip) end
    end)
end

local function stopNoclip()
    if noclipConnection then noclipConnection:Disconnect(); noclipConnection = nil end
    local char = LocalPlayer.Character
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = true end
        end
    end
end

local function applySpeed()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then hum.WalkSpeed = State.Speed and State.WalkSpeed or 16 end
end

-- ============================================================
-- 8. ЦИКЛЫ
-- ============================================================
task.spawn(function()
    while task.wait(3) do
        if State.ESP then pcall(scanForItems); pcall(cleanupESP) end
    end
end)

task.spawn(function()
    while task.wait(2) do pcall(autoSellItems) end
end)

task.spawn(function()
    while task.wait(5) do
        if State.AutoBuyLucky then pcall(buyLuckyArrow) end
    end
end)

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if State.Noclip then applyNoclip() end
    if State.Speed then applySpeed() end
end)

-- ============================================================
-- 9. KAVO UI
-- ============================================================
local Window = Library.CreateLib("YBA Controller | v7.3", "BloodTheme")

local FarmTab = Window:NewTab("AutoFarm")
local FarmSection = FarmTab:NewSection("Автоматизация")

FarmSection:NewToggle("★ AutoFarm", "Автоматический поиск и подбор предметов", function(v)
    State.AutoFarm = v
    if v then
        if not State.Noclip then State.Noclip = true; startNoclip() end
        startAutoFarm()
    else
        stopAutoFarm()
    end
end)

FarmSection:NewToggle("Авто-продажа", "Подлетает к торговцу и продаёт всё", function(v)
    State.AutoSell = v
    if v then print("[AutoSell] Включено. Ищем торговца в Workspace.Dialogues.") end
end)

FarmSection:NewToggle("Авто-покупка Lucky Arrow", "Покупать при балансе $" .. LUCKY_ARROW_PRICE .. "+", function(v)
    State.AutoBuyLucky = v
end)

FarmSection:NewSlider("Скорость полёта", "Скорость перемещения", 200, 30, function(v) State.FlySpeed = v end)
FarmSection:NewSlider("Дистанция подбора", "На каком расстоянии подбирать", 10, 1, function(v) State.PickupRange = v end)

local VisualTab = Window:NewTab("Visuals")
local VisualSection = VisualTab:NewSection("ESP")
VisualSection:NewToggle("ESP предметов", "Подсвечивать предметы", function(v)
    State.ESP = v
    if not v then clearAllESP() end
end)

local MoveTab = Window:NewTab("Movement")
local MoveSection = MoveTab:NewSection("Скорость и коллизии")
MoveSection:NewToggle("Noclip", "Проход сквозь стены", function(v)
    State.Noclip = v
    if v then startNoclip() else stopNoclip() end
end)
MoveSection:NewToggle("Ускорение", "Увеличить скорость ходьбы", function(v)
    State.Speed = v
    applySpeed()
end)
MoveSection:NewSlider("Скорость ходьбы", "Значение WalkSpeed", 150, 16, function(v)
    State.WalkSpeed = v
    if State.Speed then applySpeed() end
end)

local ItemsTab = Window:NewTab("Items")
local ItemsSection = ItemsTab:NewSection("Выбор предметов")
local allItems = {
    "Rokakaka", "Lucky Arrow", "Caesar's Headband", "Clackers",
    "Ancient Scroll", "Diamond", "Dio's Diary", "Gold Coin",
    "Lucky Stone Mask", "Mysterious Arrow", "Pure Rokakaka",
    "Quinton's Glove", "Rib Cage of The Saint's Corpse",
    "Steel Ball", "Stone Mask", "Zeppeli's Hat",
}
ItemsSection:NewDropdown("Добавить предмет", "Добавить в TARGET_ITEMS", allItems, function(selected)
    local exists = false
    for _, item in ipairs(TARGET_ITEMS) do
        if item:lower() == selected:lower() then exists = true; break end
    end
    if not exists then
        table.insert(TARGET_ITEMS, selected)
        print("[YBA] Добавлен: " .. selected)
    end
end)

ItemsSection:NewButton("Debug: Найти торговца", "Показать торговцев в Workspace", function()
    print("[DEBUG] Поиск торговцев...")
    local dialogues = Workspace:FindFirstChild("Dialogues")
    if dialogues then
        for _, obj in ipairs(dialogues:GetChildren()) do
            local prompt = obj:FindFirstChildOfClass("ProximityPrompt")
            if prompt then
                print("  Найден: " .. obj:GetFullName() .. " | Prompt: " .. prompt.ActionText)
            end
        end
    else
        print("  Папка Workspace.Dialogues не найдена.")
    end
end)

local InfoTab = Window:NewTab("Info")
local InfoSection = InfoTab:NewSection("О скрипте")
InfoSection:NewLabel("YBA Controller v7.3")
InfoSection:NewLabel("AutoSell: ищет торговца в Workspace.Dialogues")
InfoSection:NewLabel("Ждет 1 сек после открытия диалога")
InfoSection:NewLabel("Задержка продажи: " .. SELL_COOLDOWN .. " сек")

print("[YBA Controller] v7.3 загружена. AutoSell теперь ищет торговца правильно.")
