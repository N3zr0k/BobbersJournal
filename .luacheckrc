std = "lua51"
max_line_length = false
codes = true
exclude_files = { "BobbersJournal/Libs/", "tests/" }
-- WoW API globals are not listed one by one; unknown globals are not reported.
ignore = { "113", "212", "213", "311", "431", "432", "542" }
globals = { "BobbersJournal_DB", "BobbersJournal_Settings", "BobbersJournalAPI" }
