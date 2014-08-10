print ('[puckwars] puckwars.lua' )

USE_LOBBY=false
THINK_TIME = 0.1

STARTING_GOLD = 1000
MAX_KILLS = 10
MAX_LEVEL = 25

-- Fill this table up with the required XP per level if you want to change it
XP_PER_LEVEL_TABLE = {}
for i=1,MAX_LEVEL do
  XP_PER_LEVEL_TABLE[i] = i * 100
end

-- Generated from template

if puck_wars_mode == nil then
    print ( '[puckwars] creating puckwars game mode' )
    --puck_wars_mode = {}
    --puck_wars_mode.szEntityClassName = "puckwars"
    --puck_wars_mode.szNativeClassName = "dota_base_game_mode"
    --puck_wars_mode.__index = puck_wars_mode
    puck_wars_mode = class({})
end

function puck_wars_mode:InitGameMode()
    print( "Template addon is loaded." )
    
end

GameMode = nil

function puck_wars_mode:new( o )
  print ( '[puckwars] puck_wars_mode:new' )
  o = o or {}
  setmetatable( o, puck_wars_mode )
  return o
end

function puck_wars_mode:InitGameMode()
  puck_wars_mode = self
  print('[puckwars] Starting to load PuckWars gamemode...')

  -- Setup rules
  GameRules:SetHeroRespawnEnabled( true )
  GameRules:SetUseUniversalShopMode( true )
  GameRules:SetSameHeroSelectionEnabled( false )
  GameRules:SetHeroSelectionTime( 30.0 )
  GameRules:SetPreGameTime( 30.0)
  GameRules:SetPostGameTime( 60.0 )
  GameRules:SetTreeRegrowTime( 60.0 )
  GameRules:SetUseCustomHeroXPValues ( true )
  --GameRules:SetGoldPerTick(0)
  print('[puckwars] Rules set')

  InitLogFile( "log/puckwars.txt","")

  -- Hooks
  ListenToGameEvent('entity_killed', Dynamic_Wrap(puck_wars_mode, 'OnEntityKilled'), self)  
  ListenToGameEvent('player_connect_full', Dynamic_Wrap(puck_wars_mode, 'AutoAssignPlayer'), self)
  ListenToGameEvent('player_disconnect', Dynamic_Wrap(puck_wars_mode, 'CleanupPlayer'), self)
  ListenToGameEvent('dota_item_purchased', Dynamic_Wrap(puck_wars_mode, 'ShopReplacement'), self)
  ListenToGameEvent('player_say', Dynamic_Wrap(puck_wars_mode, 'PlayerSay'), self)
  ListenToGameEvent('player_connect', Dynamic_Wrap(puck_wars_mode, 'PlayerConnect'), self)
  --ListenToGameEvent('player_info', Dynamic_Wrap(puck_wars_mode, 'PlayerInfo'), self)
  ListenToGameEvent('dota_player_used_ability', Dynamic_Wrap(puck_wars_mode, 'AbilityUsed'), self)
  ListenToGameEvent('npc_spawned', Dynamic_Wrap(puck_wars_mode, 'Spawn'), self)

  -- Change random seed
  local timeTxt = string.gsub(string.gsub(GetSystemTime(), ':', ''), '0','')
  math.randomseed(tonumber(timeTxt))

  -- timers
  self.timers = {}

  -- userID map
  self.vUserNames = {}
  self.vUserIds = {}
  self.vSteamIds = {}
  self.vBots = {}
  self.vBroadcasters = {}

  self.vPlayers = {}
  self.vRadiant = {}
  self.vDire = {}
  self.scoreRadiant = 0
  self.scoreDire = 0

  -- Active Hero Map
  self.vPlayerHeroData = {}
  print('[puckwars] values set')

  print('[puckwars] Done precaching!') 

  print('[puckwars] Done loading PuckWars gamemode!\n\n')
end

function puck_wars_mode:CaptureGameMode()
  if GameMode == nil then
    -- Set GameMode parameters
    GameMode = GameRules:GetGameModeEntity()        
    -- Disables recommended items...though I don't think it works
    GameMode:SetRecommendedItemsDisabled( true )
    -- Override the normal camera distance.  Usual is 1134
    GameMode:SetCameraDistanceOverride( 1504.0 )
    -- Set Buyback options
    GameMode:SetCustomBuybackCostEnabled( true )
    GameMode:SetCustomBuybackCooldownEnabled( true )
    GameMode:SetBuybackEnabled( false )
    -- Override the top bar values to show your own settings instead of total deaths
    GameMode:SetTopBarTeamValuesOverride ( true )
    -- Use custom hero level maximum and your own XP per level
    GameMode:SetUseCustomHeroLevels ( true )
    GameMode:SetCustomXPRequiredToReachNextLevel( XP_PER_LEVEL_TABLE )
    -- Chage the minimap icon size
    GameRules:SetHeroMinimapIconSize( 500 )
    GameMode:SetTopBarTeamValuesOverride ( true )

    print( '[puckwars] Beginning Think' ) 
    GameMode:SetContextThink("PuckWarsThink", Dynamic_Wrap( puck_wars_mode, 'Think' ), 0.1 )

    --GameRules:GetGameModeEntity():SetThink( "Think", self, "GlobalThink", 2 )

  end 
end

function puck_wars_mode:AbilityUsed(keys)
  print('[puckwars] AbilityUsed')
  PrintTable(keys)
  local ply = EntIndexToHScript(keys.player)
  local unit = ply:GetAssignedHero()
  if unit:IsRealHero() then
    local max = unit:GetMaxMana()
    local curr = unit:GetMana()
    if max - curr ~= 0 then
      unit:GiveMana(max - curr)
    end
  end
end

function puck_wars_mode:Spawn( keys )
  print('[puckwars] Spawned')
  local unit = EntIndexToHScript(keys.entindex)
  if unit:IsRealHero() then
    if unit:GetLevel() < 6 then
      unit:AddExperience(600, false)
    end
  end
end

-- Cleanup a player when they leave
function puck_wars_mode:CleanupPlayer(keys)
  print('[puckwars] Player Disconnected ' .. tostring(keys.userid))
end

function puck_wars_mode:CloseServer()
  -- Just exit
  SendToServerConsole('exit')
end

function puck_wars_mode:PlayerConnect(keys)
  print('[puckwars] PlayerConnect')
  PrintTable(keys)
  
  -- Fill in the usernames for this userID
  self.vUserNames[keys.userid] = keys.name
  if keys.bot == 1 then
    -- This user is a Bot, so add it to the bots table
    self.vBots[keys.userid] = 1
  end
end

local hook = nil
local attach = 0
local controlPoints = {}
local particleEffect = ""

function puck_wars_mode:PlayerSay(keys)
  print ('[puckwars] PlayerSay')
  PrintTable(keys)
  
  -- Get the player entity for the user speaking
  local ply = self.vUserIds[keys.userid]
  if ply == nil then
    return
  end
  
  -- Get the player ID for the user speaking
  local plyID = ply:GetPlayerID()
  if not PlayerResource:IsValidPlayer(plyID) then
    return
  end
  
  -- Should have a valid, in-game player saying something at this point
  -- The text the person said
  local text = keys.text
  
  -- Match the text against something
  local matchA, matchB = string.match(text, "^-swap%s+(%d)%s+(%d)")
  if matchA ~= nil and matchB ~= nil then
    -- Act on the match
  end
  
end

function puck_wars_mode:AutoAssignPlayer(keys)
  print ('[puckwars] AutoAssignPlayer')
  PrintTable(keys)
  puck_wars_mode:CaptureGameMode()
  
  local entIndex = keys.index+1
  -- The Player entity of the joining user
  local ply = EntIndexToHScript(entIndex)
  
  -- The Player ID of the joining player
  local playerID = ply:GetPlayerID()
  
  -- Update the user ID table with this user
  self.vUserIds[keys.userid] = ply

  -- Update the Steam ID table
  self.vSteamIds[PlayerResource:GetSteamAccountID(playerID)] = ply
  
  -- If the player is a broadcaster flag it in the Broadcasters table
  if PlayerResource:IsBroadcaster(playerID) then
    self.vBroadcasters[keys.userid] = 1
    return
  end
  
  -- If this player is a bot (spectator) flag it and continue on
  if self.vBots[keys.userid] ~= nil then
    --return
  end
  
  playerID = ply:GetPlayerID()
  -- Figure out if this player is just reconnecting after a disconnect
  if self.vPlayers[playerID] ~= nil then
    self.vUserIds[keys.userid] = ply
    return
  end
  
  --[[ If we're not on D2MODD.in, assign players round robin to teams
  if not USE_LOBBY and playerID == -1 then
    if #self.vRadiant > #self.vDire then
      ply:SetTeam(DOTA_TEAM_BADGUYS)
      ply:__KeyValueFromInt('teamnumber', DOTA_TEAM_BADGUYS)
      table.insert (self.vDire, ply)
    else
      ply:SetTeam(DOTA_TEAM_GOODGUYS)
      ply:__KeyValueFromInt('teamnumber', DOTA_TEAM_GOODGUYS)
      table.insert (self.vRadiant, ply)
    end
    playerID = ply:GetPlayerID()
  end]]

  --Autoassign player
  print("CREATIMNG TIMER")
  self:CreateTimer('assign_player_'..entIndex, {
  endTime = Time(),
  callback = function(puckwars, args)
    -- Make sure the game has started
    print ('ASSIGNED')
    playerID = ply:GetPlayerID()
    if GameRules:State_Get() >= DOTA_GAMERULES_STATE_PRE_GAME and playerID ~= -1 then
      -- Assign a hero to a fake client
      local heroEntity = ply:GetAssignedHero()
      if PlayerResource:IsFakeClient(playerID) then
        if heroEntity == nil then
          CreateHeroForPlayer('npc_dota_hero_axe', ply)
        else
          PlayerResource:ReplaceHeroWith(playerID, 'npc_dota_hero_axe', 0, 0)
        end
      end
      heroEntity = ply:GetAssignedHero()
      -- Check if we have a reference for this player's hero
      if heroEntity ~= nil and IsValidEntity(heroEntity) then
        -- Set up a heroTable containing the state for each player to be tracked
        local heroTable = {
          hero = heroEntity,
          nTeam = ply:GetTeam(),
          bRoundInit = false,
          name = self.vUserNames[keys.userid],
        }
        self.vPlayers[playerID] = heroTable

        --[[ Set up multiteam
        local team = "team1"
        if playerID > 3 then
          team = "team2"
        end
        print("setting " .. playerID .. " to team: " .. team)
        MultiTeam:SetPlayerTeam(playerID, team)

        local item = CreateItem("item_multiteam_action", heroEntity, heroEntity)
        --item:SetLevel(2)
        heroEntity:AddItem(item)

        if GameRules:State_Get() > DOTA_GAMERULES_STATE_PRE_GAME then
            -- This section runs if the player picks a hero after the round starts
        end
        --]]
        return
      end
    end

    return Time() + 1.0
  end
})
end

function puck_wars_mode:LoopOverPlayers(callback)
  for k, v in pairs(self.vPlayers) do
    -- Validate the player
    if IsValidEntity(v.hero) then
      -- Run the callback
      if callback(v, v.hero:GetPlayerID()) then
        break
      end
    end
  end
end

function puck_wars_mode:ShopReplacement( keys )
  print ( '[puckwars] ShopReplacement' )
  PrintTable(keys)

  -- The playerID of the hero who is buying something
  local plyID = keys.PlayerID
  if not plyID then return end

  -- The name of the item purchased
  local itemName = keys.itemname 
  
  -- The cost of the item purchased
  local itemcost = keys.itemcost
  
end

function puck_wars_mode:getItemByName( hero, name )
  -- Find item by slot
  for i=0,11 do
    local item = hero:GetItemInSlot( i )
    if item ~= nil then
      local lname = item:GetAbilityName()
      if lname == name then
        return item
      end
    end
  end

  return nil
end

function puck_wars_mode:Think()
  --[[print("THINK")
  print(puck_wars_mode.timers)
  print(3)
  PrintTable(puck_wars_mode.timers)
  print(4)
  print("---------------")]]
  -- If the game's over, it's over.
  if GameRules:State_Get() >= DOTA_GAMERULES_STATE_POST_GAME then
    return
  end

  -- Track game time, since the dt passed in to think is actually wall-clock time not simulation time.
  local now = GameRules:GetGameTime()
  --print("now: " .. now)
  if puck_wars_mode.t0 == nil then
    puck_wars_mode.t0 = now
  end
  local dt = now - puck_wars_mode.t0
  puck_wars_mode.t0 = now

  --puck_wars_mode:thinkState( dt )

  -- Process timers
  for k,v in pairs(puck_wars_mode.timers) do
    --print ("EXEC timer: " .. tostring(k))
    local bUseGameTime = false
    local bFixResolution = true
    if v.dontFixResolution and v.dontFixResolution == true then
      bFixResolution = false
    end

    if v.useGameTime and v.useGameTime == true then
      bUseGameTime = true;
    end

    local now = GameRules:GetGameTime()
    if not bUseGameTime then
      now = Time()
    end
    -- Check if the timer has finished
    if now >= v.endTime then
      -- Remove from timers list
      puck_wars_mode.timers[k] = nil

      -- Run the callback
      local status, nextCall = pcall(v.callback, puck_wars_mode, v)

      -- Make sure it worked
      if status then
        -- Check if it needs to loop
        if nextCall then
          -- Change it's end time
          if bFixResolution then
            v.endTime = v.endTime + nextCall - now
          else
            v.endTime = nextCall
          end
          puck_wars_mode.timers[k] = v
        end

      else
        -- Nope, handle the error
        puck_wars_mode:HandleEventError('Timer', k, nextCall)
      end
    end
  end

  return THINK_TIME
end

function puck_wars_mode:HandleEventError(name, event, err)
  -- This gets fired when an event throws an error

  -- Log to console
  print(err)

  -- Ensure we have data
  name = tostring(name or 'unknown')
  event = tostring(event or 'unknown')
  err = tostring(err or 'unknown')

  -- Tell everyone there was an error
  Say(nil, name .. ' threw an error on event '..event, false)
  Say(nil, err, false)

  -- Prevent loop arounds
  if not self.errorHandled then
    -- Store that we handled an error
    self.errorHandled = true
  end
end

function puck_wars_mode:CreateTimer(name, args)
  --[[
  args: {
  endTime = Time you want this timer to end: Time() + 30 (for 30 seconds from now),
  useGameTime = use Game Time instead of Time()
  callback = function(frota, args) to run when this timer expires,
  dontFixResolution = false
  }

  If you want your timer to loop, simply return the time of the next callback inside of your callback, for example:

  callback = function()
  return Time() + 30 -- Will fire again in 30 seconds
  end
  ]]

  if not args.endTime or not args.callback then
    print("Invalid timer created: "..name)
    return
  end

  -- Store the timer
  puck_wars_mode.timers[name] = args
end

function puck_wars_mode:RemoveTimer(name)
  -- Remove this timer
  puck_wars_mode.timers[name] = nil
end

function puck_wars_mode:RemoveTimers(killAll)
  local timers2 = {}

  -- If we shouldn't kill all timers
  if not killAll then
    -- Loop over all timers
    for k,v in pairs(puck_wars_mode.timers) do
      -- Check if it is persistant
      if v.persist then
        -- Add it to our new timer list
        timers2[k] = v
      end
    end
  end

  -- Store the new batch of timers
  puck_wars_mode.timers = timers2
end

scoreRadiant = 0
scoreDire = 0
function puck_wars_mode:OnEntityKilled( keys )
  print( '[puckwars] OnEntityKilled Called' )
  PrintTable( keys )
  
  -- The Unit that was Killed
  local killedUnit = EntIndexToHScript( keys.entindex_killed )
  -- The Killing entity
  local killerEntity = nil

  if keys.entindex_attacker ~= nil then
    killerEntity = EntIndexToHScript( keys.entindex_attacker )
  end

  -- Put code here to handle when an entity gets killed

  if killedUnit:IsRealHero() then

    local death_count_down = 5
    killedUnit:SetTimeUntilRespawn(death_count_down)

    puck_wars_mode:CreateTimer(DoUniqueString("respawn"), {
      endTime = GameRules:GetGameTime() + 1,
      useGameTime = true,
      callback = function(reflex, args)
        death_count_down = death_count_down - 1
        if death_count_down == 0 then
          killedUnit:RespawnHero(false,false,false)
          return
        else
          killedUnit:SetTimeUntilRespawn(death_count_down)
          return GameRules:GetGameTime() + 1
        end
      end
    })

    if killerEntity:IsRealHero() then
      
      killerEntity:AddExperience(20, false)
      killerEntity = EntIndexToHScript( keys.entindex_attacker )
      local killedTeam = killedUnit:GetTeam()
      local killerTeam = killerEntity:GetTeam()
      if killedTeam == DOTA_TEAM_BADGUYS then
        if killerTeam == 2 then
          self.scoreRadiant = self.scoreRadiant + 1
        end
      elseif killedTeam == DOTA_TEAM_GOODGUYS then
        if killerTeam == 3 then
          self.scoreDire = self.scoreDire + 1
        end
      end
      GameMode:SetTopBarTeamValue ( DOTA_TEAM_BADGUYS, self.scoreDire)
      GameMode:SetTopBarTeamValue ( DOTA_TEAM_GOODGUYS, self.scoreRadiant )

      if self.scoreDire >= MAX_KILLS then
        GameRules:SetGameWinner(DOTA_TEAM_BADGUYS)
        GameRules:MakeTeamLose(DOTA_TEAM_GOODGUYS)
      end
      if self.scoreRadiant >= MAX_KILLS  then
        GameRules:SetGameWinner(DOTA_TEAM_GOODGUYS)
        GameRules:MakeTeamLose(DOTA_TEAM_BADGUYS)
      end
    end
  end
end

--==================