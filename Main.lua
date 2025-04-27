local AllIDs = {}
local foundAnything = ""
local actualHour = os.date("!*t").hour
local Deleted = false
local S_T = game:GetService("TeleportService")
local S_H = game:GetService("HttpService")

local FileSuccess = pcall(function()
    AllIDs = S_H:JSONDecode(readfile("server-hop-temp.json"))
end)
if not FileSuccess then
    AllIDs = {actualHour}
    pcall(function()
        writefile("server-hop-temp.json", S_H:JSONEncode(AllIDs))
    end)
end

local function TPReturner(placeId, sorting)
    if sorting == 'Asc' then sorting = 1 else sorting = 2 end
    print("Using sortOrder: " .. sorting)

    local Site
    local success, response = pcall(function()
        local url = 'https://games.roblox.com/v1/games/' .. placeId .. '/servers/Public?sortOrder=' .. sorting .. '&excludeFullGames=true&limit=100'
		if foundAnything ~= "" then
            url = url .. '&cursor=' .. foundAnything
        end
        print("Fetching servers with URL: " .. url)
        local httpResponse = game:HttpGet(url)
        return S_H:JSONDecode(httpResponse)
    end)

    if not success then
        if string.match(response, "429") then
            warn("Rate limit exceeded, backing off for 30 seconds")
            task.wait(30)
            return false
        end
        warn("Failed to fetch servers: " .. tostring(response))
        return false
    end

    Site = response
    if Site.nextPageCursor and Site.nextPageCursor ~= "null" and Site.nextPageCursor ~= nil then
        foundAnything = Site.nextPageCursor
        print("Next page cursor: " .. foundAnything)
    else
        foundAnything = ""
        print("No more server pages available")
    end

    local ID = ""
    local num = 0
    for _, v in pairs(Site.data or {}) do
        local Possible = true
        ID = tostring(v.id)
        if tonumber(v.maxPlayers) > tonumber(v.playing) then
            for _, Existing in pairs(AllIDs) do
                if num ~= 0 then
                    if ID == tostring(Existing) then
                        Possible = false
                    end
                else
                    if tonumber(actualHour) ~= tonumber(Existing) then
                        pcall(function()
                            delfile("server-hop-temp.json")
                            AllIDs = {actualHour}
                            writefile("server-hop-temp.json", S_H:JSONEncode(AllIDs))
                            Deleted = true
                            print("Reset JSON file due to new hour")
                        end)
                    end
                end
                num = num + 1
            end
            if Possible then
                print("Found possible server: " .. ID)
                table.insert(AllIDs, ID)
                pcall(function()
                    writefile("server-hop-temp.json", S_H:JSONEncode(AllIDs))
                    print("Added server to JSON: " .. ID)
                end)
                local teleportSuccess, teleportResult = pcall(function()
                    S_T:TeleportToPlaceInstance(placeId, ID, game.Players.LocalPlayer)
                end)
                if teleportSuccess then
                    print("Teleporting to server: " .. ID .. " (" .. v.playing .. "/" .. v.maxPlayers .. " players)")
                    task.wait(6)
                    return true
                else
                    warn("Teleport failed: " .. tostring(teleportResult))
                end
            end
        end
    end

    if foundAnything == "" and #(Site.data or {}) == 0 then
        pcall(function()
            delfile("server-hop-temp.json")
            AllIDs = {actualHour}
            writefile("server-hop-temp.json", S_H:JSONEncode(AllIDs))
            Deleted = true
            print("No more servers found, reset JSON file")
        end)
    end

    return false
end

local module = {}

function module:Teleport(placeId, sorting)
    foundAnything = ""
    local maxAttempts = 20
    local attempt = 1
    local backoff = 5

    while attempt <= maxAttempts do
        print("Teleport attempt " .. attempt .. " for PlaceId: " .. placeId .. " with sortOrder: " .. (sorting or "Asc"))
        local success, result = pcall(function()
            return TPReturner(placeId, sorting)
        end)
        if success and result then
            break
        end
        if foundAnything == "" and Deleted then
            print("Restarting server search after JSON reset")
            Deleted = false
        end
        attempt = attempt + 1
        print("Waiting " .. backoff .. " seconds before next attempt")
        task.wait(backoff)
        backoff = math.min(backoff * 1.5, 60)
    end

    if attempt > maxAttempts then
        warn("Teleport failed after " .. maxAttempts .. " attempts")
        local oppositeSort = (sorting == "Asc") and "Desc" or "Asc"
        print("Trying fallback with sortOrder: " .. oppositeSort)
        attempt = 1
        foundAnything = ""
        Deleted = false
        backoff = 5
        while attempt <= maxAttempts do
            print("Fallback attempt " .. attempt .. " with sortOrder: " .. oppositeSort)
            local success, result = pcall(function()
                return TPReturner(placeId, oppositeSort)
            end)
            if success and result then
                break
            end
            if foundAnything == "" and Deleted then
                print("Restarting server search after JSON reset in fallback")
                Deleted = false
            end
            attempt = attempt + 1
            print("Waiting " .. backoff .. " seconds before next attempt")
            task.wait(backoff)
            backoff = math.min(backoff * 1.5, 60)
        end
        if attempt > maxAttempts then
            warn("Fallback teleport failed after " .. maxAttempts .. " attempts")
        end
    end
end

return module
