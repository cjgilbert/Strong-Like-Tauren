local ADDON, ns = ...

-- Locale table. English text is written inline as L["..."]; a missing key simply returns the key,
-- so enUS needs no entries. To translate, add Locales/<locale>.lua (listed after this file in the TOC)
-- that fills ns.L with translations when GetLocale() matches.
ns.L = setmetatable({}, { __index = function(_, key) return key end })
