local ADDON, ns = ...
local L = ns.L

-- Achievement definitions. Types:
--   walks n       completed Walkabouts          ex x n     lifetime amount of exercise x (reps or seconds)
--   feats n       completed Feat exercises      streak n   best daily streak
--   rep n         reputation points             distinct n different exercises ever completed
--   dailies n     daily quests completed       doubles n  completed Double Feats (any slot done or partial)
ns.D = ns.D or {}
ns.D.ACHIEVEMENTS = {
  { id = "first_walk",  type = "walks",    n = 1,     name = L["First Steps"],             desc = L["Complete your first Walkabout."] },
  { id = "walks_100",   type = "walks",    n = 100,   name = L["Plainsrunner"],            desc = L["Complete 100 Walkabouts."] },
  { id = "walks_500",   type = "walks",    n = 500,   name = L["The Long Walk to Thunder Bluff"], desc = L["Complete 500 Walkabouts."] },
  { id = "first_daily", type = "dailies",  n = 1,     name = L["Answered the Call"],       desc = L["Complete [Daily] Earthmother's Calling."] },
  { id = "feats_10",    type = "feats",    n = 10,    name = L["Feats of Strength"],       desc = L["Complete 10 Feat of Strength exercises."] },
  { id = "feats_100",   type = "feats",    n = 100,   name = L["Chieftain's Regimen"],     desc = L["Complete 100 Feat of Strength exercises."] },
  { id = "double_1",    type = "doubles",  n = 1,     name = L["Unbridled Rage"],          desc = L["Complete your first Double Feat of Strength."] },
  { id = "double_10",   type = "doubles",  n = 10,    name = L["Berserker"],               desc = L["Complete 10 Double Feats of Strength."] },
  { id = "squat_1000",  type = "ex", x = "squat",    n = 1000, name = L["Kodo Thighs"],    desc = L["Do 1,000 squats."] },
  { id = "pushup_1000", type = "ex", x = "pushup",   n = 1000, name = L["Earthshaker"],    desc = L["Do 1,000 push-ups."] },
  { id = "plank_600",   type = "ex", x = "plank",    n = 600,  name = L["Shield Wall"],    desc = L["Hold planks for 10 minutes in total."] },
  { id = "burpee_100",  type = "ex", x = "burpees",  n = 100,  name = L["Spirit Healer's Regular"], desc = L["Do 100 burpees."] },
  { id = "pullup_100",  type = "ex", x = "pullup",   n = 100,  name = L["Zeppelin Captain"], desc = L["Do 100 pull-ups."] },
  { id = "variety_10",  type = "distinct", n = 10,    name = L["Jack of All Trades"],      desc = L["Complete 10 different exercises."] },
  { id = "streak_7",    type = "streak",   n = 7,     name = L["Week of the Earthmother"], desc = L["Reach a 7-day streak."] },
  { id = "streak_30",   type = "streak",   n = 30,    name = L["Moon of the Earthmother"], desc = L["Reach a 30-day streak."] },
  { id = "rep_friendly",type = "rep",      n = 6000,  name = L["Friend of the Club"],      desc = L["Reach Friendly with the Bloodhoof Athletic Club."] },
  { id = "rep_revered", type = "rep",      n = 24000, name = L["Revered Regular"],         desc = L["Reach Revered with the Bloodhoof Athletic Club."] },
  { id = "rep_exalted", type = "rep",      n = 45000, name = L["Strong Like Tauren"],      desc = L["Reach Exalted with the Bloodhoof Athletic Club."] },
}
