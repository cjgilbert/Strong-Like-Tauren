local ADDON, ns = ...
local L = ns.L

-- Flavor lines, picked at random per situation. %s placeholders are noted per table.
ns.D = ns.D or {}
ns.D.QUIPS = {
  due = {
    L["Zug zug. Time to move."],
    L["Your Tauren senses are tingling: Walkabout time."],
    L["The Earthmother calls. Stretch those hooves."],
    L["Stand up, champion. The plains await."],
    L["Even Cairne got up from his chair now and then."],
  },
  rooted = { -- %d = stacks
    L["Rooted (x%d). Break free!"],
    L["You are Rooted (x%d). Not even Entangling Roots lasts this long."],
  },
  feat = {
    L["Rage full! A Feat of Strength awaits."],
    L["Feat of Strength unlocked. Lok'tar!"],
    L["Your Rage overflows. Channel it."],
  },
  flavor = {
    death  = L["The Spirit Healer demands penance."],
    boss   = L["Loot squats: the boss dropped your legs day."],
    level  = L["DING! Celebrate with a bigger set."],
    zone   = L["New lands, new steps. Explorer's March."],
    hearth = L["Hearth to the kitchen: grab some water."],
    quest  = L["Quest reward: one Feat of Strength."],
  },
  done = {
    L["Strong like Tauren!"],
    L["Lok'tar ogar!"],
    L["Zug zug."],
    L["You feel stronger. (Strength +1. Not really. But really.)"],
    L["Earthmother's Vigor washes over you."],
    L["Work complete!"],
  },
  skip = {
    L["At least I have chicken."],
    L["No shame. The plains will wait."],
    L["Skipped. Leeroy would be proud. Maybe."],
  },
  snooze = { -- %d = minutes
    L["Time is money, friend! Snoozed %d min."],
    L["Five more minutes, mon. (Okay, %d.)"],
  },
  rageCapped = { -- %s = time left
    L["Rage capped. Feat in %s."],
  },
  taxi = {
    L["Flight time! Perfect for a quick Walkabout."],
    L["Wind rider's got the reins. Your legs are free."],
  },
  rest = {
    L["You feel rested. So do your legs. Use them."],
    L["A cozy inn. A perfect moment to move."],
  },
  leave = {
    L["Dungeon cleared? Body next."],
    L["You made it out. Now stretch it out."],
  },
  awayAsk = {
    L["Welcome back! Did you get up while you were away?"],
  },
  awayCredit = {
    L["Welcome back! Counted that as a break."],
  },
  early = {
    L["Good moment for an early Walkabout?"],
  },
  paused = {
    L["Reminders paused. The Totem keeps watch quietly."],
  },
  hello = {
    L["Strong Like Tauren loaded. Type /tauren. Lok'tar!"],
  },
}
