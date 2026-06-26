local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "tg: @sigmatik323",
    LoadingTitle = "tg: @sigmatik323",
    LoadingSubtitle = "by sigmatik323",
    Theme = "Default",
    DisableRayfieldPrompts = true,
    DisableBuildWarnings = true,
    ConfigurationSaving = {
        Enabled = false,
        FolderName = nil,
        FileName = "ROB_IT_Security_Test"
    },
    KeySystem = false
})

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local VirtualUser = game:GetService("VirtualUser")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AdminRemotes = ReplicatedStorage:FindFirstChild("AdminRemotes")

local TestResults = {}
local AllLogs = {}

local function AddToLog(text)
    table.insert(AllLogs, text)
end

local function Log(category, message, success)
    local status = success and "✅" or "❌"
    table.insert(TestResults, {Category = category, Message = message, Success = success})
    local logLine = string.format("[%s] %s: %s", status, category, message)
    print(logLine)
    AddToLog(logLine)
end

local function LogPrint(text)
    print(text)
    AddToLog(text)
end

local function SafeCall(func)
    local success, result = pcall(func)
    return success, result
end

spawn(function()
    while true do
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
        wait(60)
    end
end)

local CriticalTab = Window:CreateTab("🔴 Critical", "alert-triangle")

CriticalTab:CreateSection("Admin Remotes Test")

CriticalTab:CreateButton({
    Name = "Test AdminRemotes Existence",
    Callback = function()
        if AdminRemotes then
            Log("AdminRemotes", "AdminRemotes FOUND in ReplicatedStorage - VULNERABLE", false)
            Rayfield:Notify({
                Title = "CRITICAL",
                Content = "AdminRemotes visible to client!",
                Duration = 5
            })
        else
            Log("AdminRemotes", "AdminRemotes not found - possibly secure", true)
        end
    end
})

CriticalTab:CreateButton({
    Name = "Test GetProfile",
    Callback = function()
        if AdminRemotes and AdminRemotes:FindFirstChild("GetProfile") then
            local success, result = SafeCall(function()
                return AdminRemotes.GetProfile:InvokeServer(LocalPlayer.UserId)
            end)
            if success and result then
                Log("GetProfile", "Profile data accessible: " .. tostring(type(result)), false)
                Rayfield:Notify({
                    Title = "VULNERABLE",
                    Content = "GetProfile returned data!",
                    Duration = 5
                })
            else
                Log("GetProfile", "GetProfile blocked or validated", true)
            end
        else
            Log("GetProfile", "GetProfile not found", true)
        end
    end
})

CriticalTab:CreateButton({
    Name = "Test UpdateData (READ ONLY)",
    Callback = function()
        if AdminRemotes and AdminRemotes:FindFirstChild("UpdateData") then
            Log("UpdateData", "UpdateData Remote EXISTS and is visible to client", false)
            Rayfield:Notify({
                Title = "WARNING",
                Content = "UpdateData remote is accessible!",
                Duration = 5
            })
        else
            Log("UpdateData", "UpdateData not visible", true)
        end
    end
})

CriticalTab:CreateSection("Purchase Validation Tests")

CriticalTab:CreateButton({
    Name = "List All Purchase Remotes",
    Callback = function()
        local purchaseRemotes = {}
        for _, v in pairs(Remotes:GetDescendants()) do
            if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
                if string.find(v.Name:lower(), "purchase") or string.find(v.Name:lower(), "buy") then
                    table.insert(purchaseRemotes, v:GetFullName())
                end
            end
        end
        for _, path in ipairs(purchaseRemotes) do
            print("[PURCHASE REMOTE] " .. path)
        end
        Rayfield:Notify({
            Title = "Purchase Remotes",
            Content = "Found " .. #purchaseRemotes .. " purchase remotes. Check console.",
            Duration = 5
        })
    end
})

CriticalTab:CreateButton({
    Name = "Test FreeGift Spam Protection",
    Callback = function()
        local freeGift = Remotes:FindFirstChild("FreeGift")
        if freeGift then
            local successCount = 0
            for i = 1, 5 do
                local success = SafeCall(function()
                    freeGift:FireServer()
                end)
                if success then successCount = successCount + 1 end
                wait(0.1)
            end
            if successCount >= 5 then
                Log("FreeGift", "No rate limiting detected - sent 5 requests in 0.5s", false)
            else
                Log("FreeGift", "Some requests blocked", true)
            end
        else
            Log("FreeGift", "FreeGift remote not found", true)
        end
    end
})

local MediumTab = Window:CreateTab("🟡 Medium", "alert-circle")

MediumTab:CreateSection("Quest/Achievement Tests")

MediumTab:CreateButton({
    Name = "Test ClaimAchievement Existence",
    Callback = function()
        local claimAchievement = Remotes:FindFirstChild("ClaimAchievement")
        if claimAchievement then
            Log("ClaimAchievement", "Remote exists and is callable", false)
            Rayfield:Notify({
                Title = "Achievement Remote",
                Content = "ClaimAchievement is accessible",
                Duration = 3
            })
        else
            Log("ClaimAchievement", "Not found", true)
        end
    end
})

MediumTab:CreateButton({
    Name = "Test ClaimQuestReward Existence",
    Callback = function()
        local claimQuest = Remotes:FindFirstChild("ClaimQuestReward")
        if claimQuest then
            Log("ClaimQuestReward", "Remote exists and is callable", false)
        else
            Log("ClaimQuestReward", "Not found", true)
        end
    end
})

MediumTab:CreateButton({
    Name = "Test UpdateQuest Existence",
    Callback = function()
        local updateQuest = Remotes:FindFirstChild("UpdateQuest")
        if updateQuest then
            Log("UpdateQuest", "Remote exists - check if progress can be set by client", false)
        else
            Log("UpdateQuest", "Not found", true)
        end
    end
})

MediumTab:CreateSection("Equip Validation Tests")

MediumTab:CreateButton({
    Name = "List All Equip Remotes",
    Callback = function()
        local equipRemotes = {}
        for _, v in pairs(Remotes:GetDescendants()) do
            if v:IsA("RemoteEvent") then
                if string.find(v.Name:lower(), "equip") then
                    table.insert(equipRemotes, v:GetFullName())
                end
            end
        end
        for _, path in ipairs(equipRemotes) do
            print("[EQUIP REMOTE] " .. path)
        end
        Rayfield:Notify({
            Title = "Equip Remotes",
            Content = "Found " .. #equipRemotes .. " equip remotes",
            Duration = 3
        })
    end
})

MediumTab:CreateSection("Message/Queue Tests")

MediumTab:CreateButton({
    Name = "Test HostMessage Existence",
    Callback = function()
        local hostMessage = Remotes:FindFirstChild("HostMessage")
        if hostMessage then
            Log("HostMessage", "HostMessage remote accessible to all clients", false)
        else
            Log("HostMessage", "Not found", true)
        end
    end
})

MediumTab:CreateButton({
    Name = "Test LoadingGameQueue",
    Callback = function()
        local queue = Remotes:FindFirstChild("LoadingGameQueue")
        if queue then
            Log("LoadingGameQueue", "Queue remote accessible", false)
        else
            Log("LoadingGameQueue", "Not found", true)
        end
    end
})

local AnalysisTab = Window:CreateTab("📊 Analysis", "bar-chart")

AnalysisTab:CreateSection("Full Remote Scan")

AnalysisTab:CreateButton({
    Name = "Scan All RemoteEvents",
    Callback = function()
        local remoteEvents = {}
        for _, v in pairs(ReplicatedStorage:GetDescendants()) do
            if v:IsA("RemoteEvent") then
                table.insert(remoteEvents, v:GetFullName())
            end
        end
        print("========== REMOTE EVENTS ==========")
        for _, path in ipairs(remoteEvents) do
            print(path)
        end
        print("Total: " .. #remoteEvents)
        Rayfield:Notify({
            Title = "Remote Events",
            Content = "Found " .. #remoteEvents .. " RemoteEvents. Check console.",
            Duration = 5
        })
    end
})

AnalysisTab:CreateButton({
    Name = "Scan All RemoteFunctions",
    Callback = function()
        local remoteFunctions = {}
        for _, v in pairs(ReplicatedStorage:GetDescendants()) do
            if v:IsA("RemoteFunction") then
                table.insert(remoteFunctions, v:GetFullName())
            end
        end
        print("========== REMOTE FUNCTIONS ==========")
        for _, path in ipairs(remoteFunctions) do
            print(path)
        end
        print("Total: " .. #remoteFunctions)
        Rayfield:Notify({
            Title = "Remote Functions",
            Content = "Found " .. #remoteFunctions .. " RemoteFunctions. Check console.",
            Duration = 5
        })
    end
})

AnalysisTab:CreateButton({
    Name = "Check Sensitive Folders",
    Callback = function()
        local sensitiveChecks = {
            {"AdminRemotes", ReplicatedStorage:FindFirstChild("AdminRemotes")},
            {"Classes", ReplicatedStorage:FindFirstChild("Classes")},
            {"Bags", ReplicatedStorage:FindFirstChild("Bags")},
            {"ItemInfo Module", ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("ItemInfo")},
            {"PadsData", ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("PadsData")},
            {"Crypto Modules", ReplicatedStorage:FindFirstChild("UserGenerated") and ReplicatedStorage.UserGenerated:FindFirstChild("IO") and ReplicatedStorage.UserGenerated.IO:FindFirstChild("Crypto")}
        }
        
        print("========== SENSITIVE FOLDER CHECK ==========")
        for _, check in ipairs(sensitiveChecks) do
            local name, exists = check[1], check[2]
            local status = exists and "⚠️ EXPOSED" or "✅ NOT FOUND"
            print(string.format("%s: %s", name, status))
        end
    end
})

AnalysisTab:CreateSection("Test Results")

AnalysisTab:CreateButton({
    Name = "Show All Test Results",
    Callback = function()
        print("========== TEST RESULTS ==========")
        local vulnerable = 0
        local secure = 0
        for _, result in ipairs(TestResults) do
            local status = result.Success and "✅ SECURE" or "❌ VULNERABLE"
            print(string.format("[%s] %s: %s", result.Category, status, result.Message))
            if result.Success then
                secure = secure + 1
            else
                vulnerable = vulnerable + 1
            end
        end
        print(string.format("\nSUMMARY: %d Secure, %d Vulnerable", secure, vulnerable))
        Rayfield:Notify({
            Title = "Test Summary",
            Content = string.format("%d Secure, %d Vulnerable", secure, vulnerable),
            Duration = 5
        })
    end
})

AnalysisTab:CreateButton({
    Name = "Export Results to Console",
    Callback = function()
        print("\n\n========== SECURITY AUDIT EXPORT ==========")
        print("Game: ROB_IT")
        print("Date: " .. os.date("%Y-%m-%d %H:%M:%S"))
        print("Tester: " .. LocalPlayer.Name)
        print("")
        
        if AdminRemotes then
            print("⚠️ CRITICAL: AdminRemotes folder is visible in ReplicatedStorage!")
            if AdminRemotes:FindFirstChild("GetProfile") then
                print("   - GetProfile (RemoteFunction) - Can retrieve player data")
            end
            if AdminRemotes:FindFirstChild("UpdateData") then
                print("   - UpdateData (RemoteEvent) - Can potentially modify data")
            end
            if AdminRemotes:FindFirstChild("SaveFullProfile") then
                print("   - SaveFullProfile (RemoteEvent) - Can potentially save profiles")
            end
        end
        
        print("\nREMOTES FOLDER CONTENTS:")
        for _, v in pairs(Remotes:GetChildren()) do
            print("   - " .. v.Name .. " [" .. v.ClassName .. "]")
        end
        
        print("\n========== END EXPORT ==========\n")
    end
})

local TalentTab = Window:CreateTab("🎭 Talents", "star")

TalentTab:CreateSection("Talent System Tests")

TalentTab:CreateButton({
    Name = "Check UnlockTalentClass",
    Callback = function()
        local unlock = Remotes:FindFirstChild("UnlockTalentClass")
        if unlock then
            Log("UnlockTalentClass", "Talent unlock remote accessible", false)
            
            local reroll = unlock:FindFirstChild("RerollTalent")
            if reroll then
                Log("RerollTalent", "Reroll remote also accessible", false)
            end
        else
            Log("UnlockTalentClass", "Not found", true)
        end
    end
})

TalentTab:CreateButton({
    Name = "List Available Classes",
    Callback = function()
        local classes = ReplicatedStorage:FindFirstChild("Classes")
        if classes then
            print("========== AVAILABLE CLASSES ==========")
            for _, class in pairs(classes:GetChildren()) do
                print("   - " .. class.Name)
            end
            Rayfield:Notify({
                Title = "Classes Found",
                Content = "Found " .. #classes:GetChildren() .. " class models. Check console.",
                Duration = 3
            })
        else
            print("Classes folder not found")
        end
    end
})

TalentTab:CreateButton({
    Name = "List Available Bags",
    Callback = function()
        local bags = ReplicatedStorage:FindFirstChild("Bags")
        if bags then
            print("========== AVAILABLE BAGS ==========")
            for _, bag in pairs(bags:GetChildren()) do
                print("   - " .. bag.Name)
            end
            Rayfield:Notify({
                Title = "Bags Found",
                Content = "Found " .. #bags:GetChildren() .. " bag models. Check console.",
                Duration = 3
            })
        else
            LogPrint("Bags folder not found")
        end
    end
})

local ExportTab = Window:CreateTab("📋 Export", "clipboard")

ExportTab:CreateSection("Run All Tests")

ExportTab:CreateButton({
    Name = "🚀 RUN ALL TESTS",
    Callback = function()
        AllLogs = {}
        TestResults = {}
        
        AddToLog("╔══════════════════════════════════════════════════════════════╗")
        AddToLog("║           ROB_IT SECURITY AUDIT - FULL TEST                  ║")
        AddToLog("╠══════════════════════════════════════════════════════════════╣")
        AddToLog("║ Game: ROB_IT")
        AddToLog("║ Date: " .. os.date("%Y-%m-%d %H:%M:%S"))
        AddToLog("║ Tester: " .. LocalPlayer.Name)
        AddToLog("║ UserId: " .. LocalPlayer.UserId)
        AddToLog("╚══════════════════════════════════════════════════════════════╝")
        AddToLog("")
        
        AddToLog("═══════════ CRITICAL TESTS ═══════════")
        
        if AdminRemotes then
            Log("AdminRemotes", "AdminRemotes FOUND in ReplicatedStorage - VULNERABLE", false)
            if AdminRemotes:FindFirstChild("GetProfile") then
                Log("GetProfile", "GetProfile RemoteFunction EXISTS", false)
            end
            if AdminRemotes:FindFirstChild("UpdateData") then
                Log("UpdateData", "UpdateData RemoteEvent EXISTS", false)
            end
            if AdminRemotes:FindFirstChild("SaveFullProfile") then
                Log("SaveFullProfile", "SaveFullProfile RemoteEvent EXISTS", false)
            end
        else
            Log("AdminRemotes", "AdminRemotes not found - possibly secure", true)
        end
        
        local freeGift = Remotes:FindFirstChild("FreeGift")
        if freeGift then
            Log("FreeGift", "FreeGift remote accessible", false)
        else
            Log("FreeGift", "FreeGift not found", true)
        end
        
        AddToLog("")
        AddToLog("═══════════ MEDIUM TESTS ═══════════")
        
        local claimAchievement = Remotes:FindFirstChild("ClaimAchievement")
        if claimAchievement then
            Log("ClaimAchievement", "Remote exists and is callable", false)
        else
            Log("ClaimAchievement", "Not found", true)
        end
        
        local claimQuest = Remotes:FindFirstChild("ClaimQuestReward")
        if claimQuest then
            Log("ClaimQuestReward", "Remote exists and is callable", false)
        else
            Log("ClaimQuestReward", "Not found", true)
        end
        
        local updateQuest = Remotes:FindFirstChild("UpdateQuest")
        if updateQuest then
            Log("UpdateQuest", "Remote exists - check if progress can be set by client", false)
        else
            Log("UpdateQuest", "Not found", true)
        end
        
        local hostMessage = Remotes:FindFirstChild("HostMessage")
        if hostMessage then
            Log("HostMessage", "HostMessage remote accessible to all clients", false)
        else
            Log("HostMessage", "Not found", true)
        end
        
        local queue = Remotes:FindFirstChild("LoadingGameQueue")
        if queue then
            Log("LoadingGameQueue", "Queue remote accessible", false)
        else
            Log("LoadingGameQueue", "Not found", true)
        end
        
        local unlock = Remotes:FindFirstChild("UnlockTalentClass")
        if unlock then
            Log("UnlockTalentClass", "Talent unlock remote accessible", false)
            local reroll = unlock:FindFirstChild("RerollTalent")
            if reroll then
                Log("RerollTalent", "Reroll remote also accessible", false)
            end
        else
            Log("UnlockTalentClass", "Not found", true)
        end
        
        AddToLog("")
        AddToLog("═══════════ REMOTE SCAN ═══════════")
        
        local remoteEvents = {}
        local remoteFunctions = {}
        for _, v in pairs(ReplicatedStorage:GetDescendants()) do
            if v:IsA("RemoteEvent") then
                table.insert(remoteEvents, v:GetFullName())
            elseif v:IsA("RemoteFunction") then
                table.insert(remoteFunctions, v:GetFullName())
            end
        end
        
        AddToLog("Total RemoteEvents: " .. #remoteEvents)
        AddToLog("Total RemoteFunctions: " .. #remoteFunctions)
        
        AddToLog("")
        AddToLog("═══════════ SENSITIVE FOLDERS ═══════════")
        
        local sensitiveChecks = {
            {"AdminRemotes", ReplicatedStorage:FindFirstChild("AdminRemotes")},
            {"Classes", ReplicatedStorage:FindFirstChild("Classes")},
            {"Bags", ReplicatedStorage:FindFirstChild("Bags")},
            {"ItemInfo", ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("ItemInfo")},
            {"Crypto", ReplicatedStorage:FindFirstChild("UserGenerated") and ReplicatedStorage.UserGenerated:FindFirstChild("IO") and ReplicatedStorage.UserGenerated.IO:FindFirstChild("Crypto")}
        }
        
        for _, check in ipairs(sensitiveChecks) do
            local name, exists = check[1], check[2]
            local status = exists and "⚠️ EXPOSED" or "✅ NOT FOUND"
            AddToLog(string.format("  %s: %s", name, status))
        end
        
        AddToLog("")
        AddToLog("═══════════ ALL REMOTE EVENTS ═══════════")
        for _, path in ipairs(remoteEvents) do
            AddToLog("  " .. path)
        end
        
        AddToLog("")
        AddToLog("═══════════ ALL REMOTE FUNCTIONS ═══════════")
        for _, path in ipairs(remoteFunctions) do
            AddToLog("  " .. path)
        end
        
        AddToLog("")
        AddToLog("═══════════ CLASSES FOUND ═══════════")
        local classes = ReplicatedStorage:FindFirstChild("Classes")
        if classes then
            for _, class in pairs(classes:GetChildren()) do
                AddToLog("  - " .. class.Name)
            end
        end
        
        AddToLog("")
        AddToLog("═══════════ BAGS FOUND ═══════════")
        local bags = ReplicatedStorage:FindFirstChild("Bags")
        if bags then
            for _, bag in pairs(bags:GetChildren()) do
                AddToLog("  - " .. bag.Name)
            end
        end
        
        AddToLog("")
        AddToLog("═══════════ SUMMARY ═══════════")
        local vulnerable = 0
        local secure = 0
        for _, result in ipairs(TestResults) do
            if result.Success then
                secure = secure + 1
            else
                vulnerable = vulnerable + 1
            end
        end
        AddToLog(string.format("✅ Secure: %d", secure))
        AddToLog(string.format("❌ Vulnerable: %d", vulnerable))
        AddToLog("")
        AddToLog("═══════════ END OF REPORT ═══════════")
        
        Rayfield:Notify({
            Title = "All Tests Complete",
            Content = string.format("Secure: %d, Vulnerable: %d - Use Export to copy", secure, vulnerable),
            Duration = 5
        })
    end
})

ExportTab:CreateSection("Export Logs")

ExportTab:CreateButton({
    Name = "📋 COPY TO CLIPBOARD",
    Callback = function()
        local fullLog = table.concat(AllLogs, "\n")
        
        if setclipboard then
            setclipboard(fullLog)
            Rayfield:Notify({
                Title = "Copied!",
                Content = "All logs copied to clipboard (" .. #AllLogs .. " lines)",
                Duration = 3
            })
        elseif toclipboard then
            toclipboard(fullLog)
            Rayfield:Notify({
                Title = "Copied!",
                Content = "All logs copied to clipboard (" .. #AllLogs .. " lines)",
                Duration = 3
            })
        else
            Rayfield:Notify({
                Title = "Error",
                Content = "Clipboard not supported. Check console (F9).",
                Duration = 5
            })
            print("\n\n")
            print("╔══════════════════════════════════════════════════════════════╗")
            print("║         COPY EVERYTHING BELOW THIS LINE                      ║")
            print("╚══════════════════════════════════════════════════════════════╝")
            print("")
            for _, line in ipairs(AllLogs) do
                print(line)
            end
            print("")
            print("╔══════════════════════════════════════════════════════════════╗")
            print("║         COPY EVERYTHING ABOVE THIS LINE                      ║")
            print("╚══════════════════════════════════════════════════════════════╝")
            print("\n\n")
        end
    end
})

ExportTab:CreateButton({
    Name = "🔄 Clear All Logs",
    Callback = function()
        AllLogs = {}
        TestResults = {}
        Rayfield:Notify({
            Title = "Logs Cleared",
            Content = "All logs have been cleared",
            Duration = 3
        })
    end
})

ExportTab:CreateLabel("Total Logs: " .. #AllLogs)

Rayfield:Notify({
    Title = "Security Test Loaded",
    Content = "Use tabs to run vulnerability tests",
    Duration = 5
})

print("========================================")
print("ROB_IT Security Test Script Loaded")
print("by sigmatik323")
print("========================================")
