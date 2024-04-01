LatestGameState = LatestGameState or nil
InAction = false -- Prevents the agent from taking multiple actions at once.

Logs = Logs or {}

colors = {
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    reset = "\27[0m",
    gray = "\27[90m"
}

Width = 40 -- Width of the grid
Height = 40 -- Height of the grid

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
    Logs[msg] = Logs[msg] or {}
    table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

local function nearestEnemy(x, y)
    local minDistance = math.huge
    local nearest = nil

    for target, state in pairs(LatestGameState.Players) do
        local distance = math.sqrt((state.x - x)^2 + (state.y - y)^2)
        if target ~= ao.id and distance < minDistance then
            minDistance = distance
            nearest = state
        end
    end
    print(colors.red .. "nearest target: (" .. nearest.x .. "," .. nearest.y .. ")" .. colors.reset)

    return nearest
end


function getDirection(currentPoint, targetPoint)
    local direction = {}

    if targetPoint.y > currentPoint.y then
        table.insert(direction, "Down")
    elseif targetPoint.y < currentPoint.y then
        table.insert(direction, "Up")
    end

    if targetPoint.x > currentPoint.x then
        table.insert(direction, "Right")
    elseif targetPoint.x < currentPoint.x then
        table.insert(direction, "Left")
    end

    return table.concat(direction)
end

-- Decides the next action based on player proximity and energy.
-- If any player is within range, it initiates an attack; otherwise, moves to nearest player.
function decideNextAction()
    local player = LatestGameState.Players[ao.id]
    local targetInRange = false

        local nearest = nearestEnemy(player.x, player.y)
        if inRange(player.x, player.y, nearest.x, nearest.y, 1) then
            targetInRange = true
        end

    if player.energy > 5 and targetInRange then
        print(colors.red .. "Player in range. Attacking." .. colors.reset)
        ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(player.energy) })
    else
        local direction = getDirection(player, nearest)
        ao.send({ Target = Game, Action = "PlayerMove", Player = ao.id, Direction =  direction})
        print(colors.red .. "(" .. player.x .. "," .. player.y .. ") No player in range or insufficient energy. Moving " .. direction .. colors.reset)
    end
    -- InAction = false -- InAction logic added
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
    "PrintAnnouncements",
    Handlers.utils.hasMatchingTag("Action", "Announcement"),
    function(msg)
        if msg.Event == "Started-Waiting-Period" then
            ao.send({ Target = ao.id, Action = "AutoPay" })
        elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
            --   InAction = true -- InAction logic added
            ao.send({ Target = Game, Action = "GetGameState" })
        elseif InAction then -- InAction logic added
            print("Previous action still in progress. Skipping action.")
        end
        print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
    end
)

-- Handler to trigger game state updates.
Handlers.add(
    "GetGameStateOnTick",
    Handlers.utils.hasMatchingTag("Action", "Tick"),
    function()
        if not InAction then -- InAction logic added
            -- InAction = true -- InAction logic added
            print(colors.gray .. "Getting game state..." .. colors.reset)
            ao.send({ Target = Game, Action = "GetGameState" })
        else
            print("Previous action still in progress. Skipping Tick.")
        end
    end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
    "AutoPay",
    Handlers.utils.hasMatchingTag("Action", "AutoPay"),
    function(msg)
        print("Auto-paying confirmation fees.")
        ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000" })
    end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
    "UpdateGameState",
    Handlers.utils.hasMatchingTag("Action", "GameState"),
    function(msg)
        local json = require("json")
        LatestGameState = json.decode(msg.Data)
        ao.send({ Target = ao.id, Action = "UpdatedGameState" })
        print("Game state updated. Print \'LatestGameState\' for detailed view.")
    end
)

local function isInGame()
    for target, state in pairs(LatestGameState.Players) do
        if target == ao.id then
            return true
        end
    end
    return false
end
-- Handler to decide the next best action.
Handlers.add(
    "decideNextAction",
    Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
    function()
        print("UpdatedGameState")
        if LatestGameState.GameMode ~= "Playing" then
            -- InAction = false -- InAction logic added
            print("Game is waiting")
            return
        end
        if isInGame() then
            print("Deciding next action.")
            decideNextAction()
            ao.send({ Target = ao.id, Action = "Tick" })
        else
            print("Is not in game.")
        end
    end
)

-- Handler to automatically attack when hit by another player.
Handlers.add(
    "ReturnAttack",
    Handlers.utils.hasMatchingTag("Action", "Hit"),
    function(msg)
        if not InAction then -- InAction logic added
            -- InAction = true -- InAction logic added
            local playerEnergy = LatestGameState.Players[ao.id].energy
            if playerEnergy == undefined then
                print(colors.red .. "Unable to read energy." .. colors.reset)
                ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy." })
            elseif playerEnergy == 0 then
                print(colors.red .. "Player has insufficient energy." .. colors.reset)
                ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Player has no energy." })
            else
                print(colors.red .. "Returning attack." .. colors.reset)
                ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy) })
            end
            -- InAction = false -- InAction logic added
            ao.send({ Target = ao.id, Action = "Tick" })
        else
            print("Previous action still in progress. Skipping Hit.")
        end
    end
)
