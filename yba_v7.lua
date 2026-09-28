-- ============================================================
-- ========== 1. ЗАГРУЗКА KAVO UI =============================
-- ============================================================
print("[YBA Controller] Загрузка v7.0 (Kavo UI)...")
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()

-- ============================================================
-- ========== 2. НАСТРОЙКИ И СОСТОЯНИЕ ========================
-- ============================================================
local TARGET_ITEMS = {
    "Rokakaka", "Lucky Arrow", "Caesar's Headband", "Clackers",
    "Ancient Scroll", "Diamond", "Dio's Diary", "Gold Coin",
    "Lucky Stone Mask", "Mysterious Arrow", "Pure Rokakaka",
    "Quinton's Glove", "Rib Cage of The Saint's Corpse",
    "Steel Ball", "Stone Mask", "Zeppeli's Hat",
}

local LUCKY_ARROW_PRICE = 75000

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
-- ========== 3. СЕРВИСЫ ======================================
-- ============================================================
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- ========== 4. ESP ==========================================
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
-- ========== 5. AUTOFARM =====================================
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

local function startAutoFarm()
    if flyConnection then return end
    flyConnection = RunService.Heartbeat:Connect(function(dt)
        if not State.AutoFarm then return end
        local char = LocalPlayer.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end

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
-- ========== 6. AUTOSELL =====================================
-- ============================================================
local function autoSellItems()
    if not State.AutoSell then return end

    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local hasItems = false
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") then hasItems = true; break end
        end
    end
    if not hasItems then return end

    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    for _, gui in ipairs(playerGui:GetChildren()) do
        for _, obj in ipairs(gui:GetDescendants()) do
            if obj:IsA("TextButton") and obj.Text then
                local btnText = obj.Text:lower()
                if btnText:find("sell") and btnText:find("all") then
                    obj:Fire("MouseButton1Click")
                    print("[AutoSell] Нажал кнопку: " .. obj.Text)
                    task.wait(1)
                    return
                end
            end
        end
    end
end

-- ============================================================
-- ========== 7. АВТОПОКУПКА LUCKY ARROW ======================
-- ============================================================
local function getPlayerMoney()
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        local cash = leaderstats:FindFirstChild("Cash") or leaderstats:FindFirstChild("Money")
        if cash and cash:IsA("IntValue") then return cash.Value end
    end
    local attr = LocalPlayer:GetAttribute("Money") or LocalPlayer:GetAttribute("Cash")
    if typeof(attr) == "number" then return attr end
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if playerGui then
        local currency = playerGui:FindFirstChild("Currency")
        if currency then
            local moneyLabel = currency:FindFirstChild("Money")
            if moneyLabel and moneyLabel:IsA("TextLabel") then
                local num = tonumber(moneyLabel.Text:gsub("[^%d]", ""))
                if num then return num end
            end
        end
    end
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

    local args = {
        "PurchaseShopItem",
        {["ItemName"] = "Lucky Arrow"},
        1, 2
    }
    local success = pcall(function() remote:FireServer(unpack(args)) end)
    if success then
        print(string.format("[AutoBuy] Куплен Lucky Arrow. Баланс: $%d", money))
    end
    return success
end

-- ============================================================
-- ========== 8. NOCLIP & SPEED ===============================
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
-- ========== 9. ЦИКЛЫ ========================================
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
-- ========== 10. KAVO UI =====================================
-- ============================================================
local Window = Library.CreateLib("YBA Controller | v7.0", "BloodTheme")

-- ----- Вкладка "AutoFarm" -----
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

FarmSection:NewToggle("Авто-продажа", "Продавать предметы через кнопку 'I'll sell ALL of these'", function(v)
    State.AutoSell = v
end)

FarmSection:NewToggle("Авто-покупка Lucky Arrow", "Покупать при балансе $" .. LUCKY_ARROW_PRICE .. "+", function(v)
    State.AutoBuyLucky = v
end)

FarmSection:NewSlider("Скорость полёта", "Скорость перемещения в AutoFarm", 200, 30, function(v)
    State.FlySpeed = v
end)

FarmSection:NewSlider("Дистанция подбора", "На каком расстоянии подбирать", 10, 1, function(v)
    State.PickupRange = v
end)

-- ----- Вкладка "Visuals" -----
local VisualTab = Window:NewTab("Visuals")
local VisualSection = VisualTab:NewSection("ESP")

VisualSection:NewToggle("ESP предметов", "Подсвечивать предметы из списка", function(v)
    State.ESP = v
    if not v then clearAllESP() end
end)

-- ----- Вкладка "Movement" -----
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

-- ----- Вкладка "Items" -----
local ItemsTab = Window:NewTab("Items")
local ItemsSection = ItemsTab:NewSection("Выбор предметов для поиска")

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
    else
        print("[YBA] Уже в списке: " .. selected)
    end
end)

ItemsSection:NewButton("Очистить список", "Удалить все предметы", function()
    table.clear(TARGET_ITEMS)
    clearAllESP()
    print("[YBA] Список очищен")
end)

-- ----- Вкладка "Info" -----
local InfoTab = Window:NewTab("Info")
local InfoSection = InfoTab:NewSection("О скрипте")

InfoSection:NewLabel("YBA Controller v7.0 (Kavo UI)")
InfoSection:NewLabel("ESP ищет предметы в Item_Spawns.Items")
InfoSection:NewLabel("AutoFarm использует fireproximityprompt")
InfoSection:NewLabel("AutoSell нажимает 'I'll sell ALL of these'")
InfoSection:NewLabel("Внимание: читы могут привести к бану!")

print("[YBA Controller] v7.0 загружена. Kavo UI активен.")
