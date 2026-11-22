local ADDON, ns = ...
local L = ns.L

-- Text for the Health tab and first-run screen. Sources are listed so players can check the claims.
ns.D = ns.D or {}
ns.D.HEALTH = {
  pitch = {
    L["Every 30 minutes you sit, a 2-minute Walkabout comes due. Ignoring it never builds debt; it just grows, to 5 minutes at most."],
    L["Playing fills Rage: a full bar every 90 minutes, faster from quests, dings, deaths and bosses, with repeats worth less. A full bar earns a Feat of Strength, at most one per 45 minutes, delivered with your next Walkabout."],
    L["Feats pick the muscles you've rested longest, and no muscle group gets more than 1.5 sets in any hour or 6 in a day. Anything due in combat or a dungeon waits in your Totem until you're free."],
  },
  why = {
    { head = L["Why every 30 minutes?"],
      body = L["Long unbroken sitting is linked to worse blood sugar, blood pressure and long-term health. Studies that break up sitting every 30 minutes with a few minutes of light movement (walking, squats, calf raises) show clear improvements, even during evening sitting."] },
    { head = L["What counts?"],
      body = L["Moving counts; just standing up helps less. A short walk, marching in place, squats or calf raises all work. Five minutes every half hour showed the biggest blood-sugar benefit in one trial; one minute an hour still helped blood pressure."] },
    { head = L["Weekly targets"],
      body = L["The WHO recommends 150-300 minutes of moderate activity a week plus muscle strengthening on 2 or more days, and limiting sitting time in general. Walkabouts and Feats are 'exercise snacks' that add up, not a replacement for a proper workout."] },
    { head = L["Long sessions"],
      body = L["Doctors have reported blood clots in legs after marathon gaming sessions. Calf raises and short walks keep the blood moving, which is why Walkabouts get longer when you've been rooted for a while."] },
  },
  sources = {
    "Duran AT, ..., Diaz KM (2023). Breaking up prolonged sitting to improve cardiometabolic risk: dose-response analysis of a randomized crossover trial. Medicine & Science in Sports & Exercise.",
    "Gale JT et al. (2023). Breaking up evening sitting with resistance activity improves postprandial glycemic response. Medicine & Science in Sports & Exercise.",
    "Bailey DP, Locke CD (2015). Breaking up prolonged sitting with light-intensity walking improves postprandial glycemia, but breaking up sitting with standing does not. J Sci Med Sport.",
    "Diaz KM et al. (2017). Patterns of sedentary behavior and mortality in U.S. middle-aged and older adults. Annals of Internal Medicine.",
    "Ekelund U et al. (2019). Dose-response associations between accelerometry measured physical activity and sedentary time and all cause mortality. BMJ.",
    "Bull FC et al. (2020). World Health Organization 2020 guidelines on physical activity and sedentary behaviour. Br J Sports Med.",
    "Stamatakis E et al. (2022). Association of wearable device-measured vigorous intermittent lifestyle physical activity with mortality. Nature Medicine.",
    "Case report (2013). Extensive deep vein thrombosis following prolonged gaming ('gamer's thrombosis'). Journal of Medical Case Reports.",
  },
  disclaimer = L["Strong Like Tauren is a game add-on, not medical advice. Check with a doctor if you have health conditions, start easy, and stop anything that hurts. Skipping is always fine."],
}
