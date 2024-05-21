-- PID: VZwiXGRxD5SMd9yAdQj2VsQ_PdLXqAH0fhyROcFDoGo
LatestGameState = {}  -- Stores all game data
InAction = false     -- Prevents your bot from doing multiple actions

colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}


-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Decide the next action based on player proximity, energy, health, and game map analysis.
-- Prioritize targets based on health (weaker first), distance (closer first), and strategic positions.
-- Analyze the map for chokepoints or advantageous positions.
function decideNextAction()
  local player = LatestGameState.Players[ao.id]
  local targetInRange = false
  local bestTarget = nil  -- Stores the ID of the best target player (considering health, distance, energy)
  
  -- Find closest and most strategic target
  for target, state in pairs(LatestGameState.Players) do
    if target ~= ao.id and inRange(player.x, player.y, state.x, state.y, 1) then
      targetInRange = true
      if not bestTarget or (state.health < bestTarget.health and state.energy > bestTarget.energy) or (state.health == bestTarget.health and state.energy > bestTarget.energy and inRange(player.x, player.y, state.x, state.y, 1) < inRange(player.x, player.y, bestTarget.x, bestTarget.y, 1)) then
        bestTarget = state
      end
    end
  end

  if player.energy > 5 and targetInRange then
    print(colors.red .. "Player in range. Attacking." .. colors.reset)
    ao.send({  -- Attack the closest player with all your energy.
      Target = Game,
      Action = "PlayerAttack",
      Player = ao.id,
      AttackEnergy = tostring(player.energy),
    })
  else
    print(colors.red .. "No player in range or low energy. Moving strategically." .. colors.reset)
    
    -- Map analysis for strategic movement
    local directionStrategic = {"Up", "Down", "Left", "Right"}
    local bestDirection = nil
    local highestScore = -math.huge
    
    for _, direction in ipairs(directionStrategic) do
      local newX, newY = player.x, player.y
      if direction == "Up" then
        newY = newY - 1
      elseif direction == "Down" then
        newY = newY + 1
      elseif direction == "Left" then
        newX = newX - 1
      elseif direction == "Right" then
        newX = newX + 1
      end
      
      -- Score calculation for the new position
      local score = 0
      for target, state in pairs(LatestGameState.Players) do
        if target ~= ao.id then
          local distance = math.abs(newX - state.x) + math.abs(newY - state.y)
          if distance == 1 then
            score = score - 10 -- Penalize being close to an enemy
          else
            score = score + 5 -- Reward being further from enemies
          end
        end
      end
      
      if score > highestScore then
        highestScore = score
        bestDirection = direction
      end
    end
    
    ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = bestDirection})
  end
  InAction = false -- Reset the "InAction" flag
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true -- InAction logic added
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then -- InAction logic added
      print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- Handler to trigger game state updates.
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then -- InAction logic added
      InAction = true -- InAction logic added
      print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000"})
  end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print 'LatestGameState' for detailed view.")
  end
)

-- Handler to decide the next best action.
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then
      InAction = false -- InAction logic added
      return
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)

-- Handler to automatically attack when hit by another player.
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction then -- InAction logic added
      InAction = true -- InAction logic added
      local playerEnergy = LatestGameState.Players[ao.id].energy
      if playerEnergy == nil then
        print(colors.red .. "Unable to read energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
      elseif playerEnergy == 0 then
        print(colors.red .. "Player has insufficient energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
      else
        print(colors.red .. "Returning attack." .. colors.reset)
        ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy)})
      end
      InAction = false -- InAction logic added
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)
