local ADDON, ns = ...
local L = ns.L

-- Built-in exercise library.
--   kind  "r" = reps, "s" = seconds          std  amount for one standard set at 100% (Grunt)
--   g     muscle-group weights (capped groups: legs, push, pull, core, cardio)
--   int   intensity l/m/v                     rest minimum seconds before the same exercise again
--   side  "leg" | "side": two-sided; the amount is reps PER leg / PER side (10 means 10 each; never doubled
--         internally, always shown as "x10 each leg"). Absent = not sided. Reps only.
--   walk  true = a Walkabout move (timed by the health dose, not scaled by tier)
--   flags jump / floor / wrist / seated       needs equipment key (see C.EQUIP)
--   tags  Rage flavors this exercise fits (death, boss, quest, zone, hearth)
local I = "Interface\\Icons\\"

ns.D = ns.D or {}
ns.D.EXERCISES = {
  -- Walkabout moves -----------------------------------------------------------------------------
  { id = "walk", name = L["Walk around"], pun = L["Mulgore Stroll"], kind = "s", std = 120, lo = 60, hi = 600,
    desc = L["Walk around your home: stairs, kitchen, a lap of the room. Look out a window and sip some water."],
    g = { walk = 1, legs = 0.1 }, int = "l", walk = true, rest = 0, tags = { hearth = true, zone = true },
    icon = I .. "Ability_Tracking" },
  { id = "march", name = L["March in place"], pun = L["Kodo March"], kind = "s", std = 120, lo = 60, hi = 600,
    desc = L["March in place with your knees up and arms swinging. Look far away while you do it."],
    g = { walk = 1, legs = 0.1 }, int = "l", walk = true, rest = 0, tags = { zone = true },
    icon = I .. "Ability_Mount_Kodo_02" },
  { id = "shuffle", name = L["Calf raises & squats"], pun = L["Hoof & Squat Shuffle"], kind = "s", std = 120, lo = 60, hi = 600,
    desc = L["Alternate 10 calf raises and 5 easy squats until the timer ends."],
    g = { walk = 0.6, legs = 0.1 }, int = "l", walk = true, rest = 0, tags = { boss = true },
    icon = I .. "INV_Misc_Foot_Kodo" },
  { id = "stretch", name = L["Standing stretches"], pun = L["Earthmother's Stretch"], kind = "s", std = 120, lo = 60, hi = 600,
    desc = L["Hip flexors, hamstrings, a chest opener and wrists. Hold each stretch about 20 seconds."],
    g = { mobility = 1 }, int = "l", walk = true, rest = 0, icon = I .. "Spell_Nature_Regeneration" },
  { id = "stairs", name = L["Stair walk"], pun = L["Thunder Bluff Elevator"], kind = "s", std = 120, lo = 60, hi = 600,
    desc = L["Walk up and down the stairs at an easy pace."], needs = "stairs",
    g = { walk = 1, legs = 0.15 }, int = "l", walk = true, rest = 0, icon = I .. "Ability_Hunter_Pathfinding" },
  { id = "wrist", name = L["Wrist & hand stretch"], pun = L["Unclench the Mouse Paw"], kind = "s", std = 120, lo = 60, hi = 600,
    desc = L["Wrist circles, finger spreads, then stretch each forearm both ways."],
    g = { mobility = 1 }, int = "l", walk = true, rest = 0, flags = { seated = true },
    icon = I .. "INV_Gauntlets_04" },
  { id = "neck", name = L["Neck & shoulder rolls"], pun = L["Look for Rares"], kind = "s", std = 120, lo = 60, hi = 600,
    desc = L["Slow neck turns and shoulder rolls, then look at something far away for 20 seconds."],
    g = { mobility = 1 }, int = "l", walk = true, rest = 0, flags = { seated = true },
    icon = I .. "Ability_Hunter_EagleEye" },

  -- Legs ----------------------------------------------------------------------------------------
  { id = "squat", name = L["Squats"], pun = L["Kodo Squats"], kind = "r", std = 15, lo = 3, hi = 100,
    desc = L["Feet shoulder-width, sit back like there's a chair behind you, chest up."],
    g = { legs = 1, core = 0.1 }, int = "m", rest = 1800, tags = { boss = true }, icon = I .. "Spell_Nature_Strength" },
  { id = "lunge", name = L["Lunges"], pun = L["Charge Lunges"], kind = "r", std = 10, lo = 2, hi = 60, side = "leg",
    desc = L["Alternating lunges. The number is per leg."],
    g = { legs = 1 }, int = "m", rest = 1800, tags = { boss = true }, icon = I .. "Ability_Warrior_Charge" },
  { id = "wallsit", name = L["Wall sit"], pun = L["Totem Stance"], kind = "s", std = 30, lo = 10, hi = 180,
    desc = L["Back flat against a wall, thighs parallel to the floor. Stand still like a totem."], needs = "wall",
    g = { legs = 1 }, int = "m", rest = 1800, tags = { boss = true }, icon = I .. "Spell_Nature_StoneSkinTotem" },
  { id = "calfraise", name = L["Calf raises"], pun = L["Hoof Raises"], kind = "r", std = 25, lo = 5, hi = 100,
    desc = L["Rise onto your toes, pause, lower slowly. Hold a wall for balance if you like."],
    g = { legs = 0.5 }, int = "l", rest = 900, tags = { hearth = true }, icon = I .. "INV_Misc_Foot_Kodo" },
  { id = "bridge", name = L["Glute bridges"], pun = L["Stampede Bridges"], kind = "r", std = 15, lo = 3, hi = 60,
    desc = L["Lie on your back, knees bent, and drive your hips up. Squeeze at the top."],
    g = { legs = 0.6, core = 0.4 }, int = "l", rest = 1800, flags = { floor = true }, icon = I .. "Ability_Mount_Kodo_01" },

  -- Push ----------------------------------------------------------------------------------------
  { id = "pushup", name = L["Push-ups"], pun = L["Earthshaker Push-ups"], kind = "r", std = 10, lo = 1, hi = 100,
    desc = L["Body in a straight line, lower your chest to a fist's height off the floor. Knees down is fine."],
    g = { push = 1, core = 0.2 }, int = "m", rest = 1800, flags = { floor = true, wrist = true }, tags = { quest = true },
    icon = I .. "Spell_Nature_Earthquake" },
  { id = "deskpushup", name = L["Desk push-ups"], pun = L["Counter Push-ups"], kind = "r", std = 12, lo = 2, hi = 100,
    desc = L["Hands on a sturdy desk or counter edge, body straight, lower your chest to the edge."],
    g = { push = 1 }, int = "l", rest = 1800, flags = { wrist = true }, tags = { quest = true },
    icon = I .. "Ability_Warrior_Sunder" },
  { id = "dips", name = L["Chair dips"], pun = L["Moonwell Dips"], kind = "r", std = 10, lo = 2, hi = 60,
    desc = L["Hands on the front edge of a sturdy chair, lower until your elbows reach 90 degrees."], needs = "chair",
    g = { push = 1 }, int = "m", rest = 1800, flags = { wrist = true }, icon = I .. "Spell_Holy_ElunesGrace" },
  { id = "press", name = L["Dumbbell press"], pun = L["Totem Lift"], kind = "r", std = 12, lo = 2, hi = 60,
    desc = L["Press the dumbbells overhead, then lower them slowly to your shoulders."], needs = "dumbbells",
    g = { push = 1 }, int = "m", rest = 1800, icon = I .. "Spell_Nature_StrengthOfEarthTotem02" },

  -- Pull ----------------------------------------------------------------------------------------
  { id = "pullup", name = L["Pull-ups"], pun = L["Zeppelin Hang"], kind = "r", std = 5, lo = 1, hi = 50,
    desc = L["Full hang to chin over the bar. Negatives or a dead hang count on tough days."], needs = "bar",
    g = { pull = 1, core = 0.2 }, int = "v", rest = 1800, icon = I .. "INV_Misc_Gear_01" },
  { id = "bandrow", name = L["Band rows"], pun = L["Kodo Rows"], kind = "r", std = 15, lo = 3, hi = 60,
    desc = L["Anchor the band at chest height and row your elbows back, squeezing your shoulder blades."], needs = "band",
    g = { pull = 1 }, int = "m", rest = 1800, icon = I .. "Spell_Nature_EarthBind" },
  { id = "superman", name = L["Supermans"], pun = L["Wind Rider Lifts"], kind = "r", std = 12, lo = 3, hi = 60,
    desc = L["Lie face down, lift arms and legs together, hold two seconds, lower."],
    g = { pull = 0.7, core = 0.5 }, int = "l", rest = 1800, flags = { floor = true },
    icon = I .. "Ability_Hunter_Pet_WindSerpent" },

  -- Core ----------------------------------------------------------------------------------------
  { id = "plank", name = L["Plank"], pun = L["Shield Wall"], kind = "s", std = 30, lo = 10, hi = 300,
    desc = L["Forearms down, body straight from head to heels. Breathe."],
    g = { core = 1, push = 0.2 }, int = "m", rest = 1800, flags = { floor = true, wrist = true }, tags = { quest = true },
    icon = I .. "Ability_Warrior_ShieldWall" },
  { id = "crunch", name = L["Crunches"], pun = L["Battle Shout Crunches"], kind = "r", std = 15, lo = 3, hi = 100,
    desc = L["Knees bent, curl your shoulders off the floor, lower slowly."],
    g = { core = 1 }, int = "l", rest = 1800, flags = { floor = true }, tags = { quest = true },
    icon = I .. "Ability_Warrior_BattleShout" },
  { id = "twist", name = L["Standing torso twists"], pun = L["Whirlwind"], kind = "r", std = 10, lo = 3, hi = 50, side = "side",
    desc = L["Feet planted, rotate side to side with your arms relaxed. The number is per side."],
    g = { core = 0.6, mobility = 0.4 }, int = "l", rest = 900, tags = { quest = true }, icon = I .. "Ability_Whirlwind" },

  -- Cardio --------------------------------------------------------------------------------------
  { id = "jacks", name = L["Jumping jacks"], pun = L["War Stomp"], kind = "r", std = 25, lo = 5, hi = 150,
    desc = L["Classic jumping jacks. Land softly."],
    g = { cardio = 1 }, int = "m", rest = 1800, flags = { jump = true }, tags = { death = true }, icon = I .. "Ability_WarStomp" },
  { id = "lowjacks", name = L["Step jacks"], pun = L["Quiet Stomp"], kind = "r", std = 12, lo = 3, hi = 75, side = "side",
    desc = L["Step one foot out as your arms go up, alternate sides. The number is per side. No jumping, neighbor-friendly."],
    g = { cardio = 1 }, int = "l", rest = 1800, tags = { death = true }, icon = I .. "Spell_Nature_Tranquility" },
  { id = "highknees", name = L["High knees"], pun = L["Plainsrunning"], kind = "s", std = 30, lo = 10, hi = 120,
    desc = L["Run in place, driving your knees up to hip height."],
    g = { cardio = 1, legs = 0.2 }, int = "v", rest = 1800, flags = { jump = true }, tags = { death = true, zone = true },
    icon = I .. "Ability_Druid_Dash" },
  { id = "climbers", name = L["Mountain climbers"], pun = L["Thunder Bluff Climbers"], kind = "r", std = 10, lo = 2, hi = 50, side = "side",
    desc = L["From a high plank, drive your knees toward your chest. The number is per knee."],
    g = { cardio = 0.6, core = 0.6 }, int = "v", rest = 1800, flags = { floor = true, wrist = true },
    tags = { death = true, zone = true }, icon = I .. "Spell_Nature_Lightning" },
  { id = "burpees", name = L["Burpees"], pun = L["Spirit Healer's Penance"], kind = "r", std = 8, lo = 1, hi = 50,
    desc = L["Squat, hands down, step or jump back to a plank, come back up, reach high."],
    g = { cardio = 1, legs = 0.4, push = 0.4 }, int = "v", rest = 1800,
    flags = { floor = true, jump = true, wrist = true }, tags = { death = true }, icon = I .. "Spell_Holy_Resurrection" },
}
