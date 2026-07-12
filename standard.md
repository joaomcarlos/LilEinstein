# Coding standard

## Default variables

res = function internal result array which is to be returned
item = the current item in the result array
prop = a short lived array of properties
tech_name = LuaTechnology.name (or LuaTechnologyPrototype.name)

## References to in game classes

- Variables in lowercase refer to a live class
- Variables in UPPERCASE refer to a prototype
  p = LuaPlayer
  f = LuaForce
  t = LuaTechnology
  T = LuaTechnologyPrototype
  pre_req_tech = LuaTechnology.prerequisite
  PRE_REQ_TECH = LuaTechnologyPrototype.prerequisite
  next_tech = LuaTechnology.successor
  NEXT_TECH = LuaTechnologyPrototype.successor

## References to mod structures

-- Meta
meta = env.tech_meta{}
meta_cur = meta[tech_name]
meta_next = meta[<t.successor>]
meta_pre = meta[<t.prerequisite>]

-- Tech state
tech_state_ext = tech.state_ext
tech_state_cur = tech_state_ext[tech_name]
tech_state_next = tech_state_ext[<t.successor>]
tech_state_pre = tech_state_ext[<t.prerequisite>]

-- Queue
queue_names = the actual force's queue{"tech-1", ...} array
queued_tech = a single queued "tech-1"

## Init & structure

- Control inits storage, storage.forces and storage.players
- Control init triggers <module>.init including force/player
- Control on_force/on_player triggers <module>.init_force/init_player
- <module>.init does *not* trigger <module>.init_force/init_player

## Data model

storage.<module>.<key> = {...}
storage.forces[force_index].<module>.<key> = {...}
storage.players[player_index].<module>.<key> = {...}

## Module order/dependencies

- Control

* lib

- const, util

* model
  -- env, state
  --- tech
  ---- queue
  ----- cmd (lab?)
* view
  ---- gui (analyzer, builder, components, ...)
