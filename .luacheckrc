std = "lua51"
max_line_length = false
codes = true
exclude_files = { "BobbersJournal/Libs/", "tests/" }
-- WoW API globals are not listed one by one; reading unknown globals is not reported.
ignore = { "113", "212", "213", "311" }
globals = {
  "BobbersJournal_DB", "BobbersJournal_Settings", "BobbersJournalAPI",
  "SlashCmdList", "StaticPopupDialogs",
  "SLASH_BOBBERSJOURNAL1", "BINDING_HEADER_BOBBERSJOURNAL",
  "BobbersJournal_OnAddonCompartmentClick", "BobbersJournal_OnAddonCompartmentEnter", "BobbersJournal_OnAddonCompartmentLeave",
}
