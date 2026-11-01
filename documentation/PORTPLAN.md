# Portplan: Glimpse_Professions (Angeln) → Bobber's Journal

Quelle (unverändert, nur Referenz): `/mnt/project-files/reference/glimpse-professions/`.
Der Glimpse-Code ist laut Sven auf WoW Forever getestet. Retail ist **nicht geprüft**; "Retail?" heißt: muss im Spiel/gegen Blizzard-Quelltext geklärt werden.

## Abhängigkeiten von Glimpse (Core ist nicht im ZIP)
`AceAddon/AceEvent/AceLocale/AceConfig`, `GlimpseDB` (Namespaces mit Count/GetCounts/GetZones/Locations), `Glimpse.IDs` (ZoneKey, Where, DescribeItem), `RegisterDoubleClick` (Secure-Button-Verteiler), `AddTooltipLine/Separator`, `IsSecret`, `Print`, `GatheringData`.
Ace3 ist hier verboten, daher wird alles durch eigene Helfer ersetzt.

## Status je Datei
| Glimpse-Datei | Zweck | Ziel | Status | Retail? |
|---|---|---|---|---|
| FishingRecord | Würfe/Fänge zählen | Modules/Tracker + Core/DB | **portiert** (Mock-Test, nicht im Spiel) | ja, Fischen läuft in Retail anders (Sven) |
| FishingCatches | Fangliste je Zone im Tooltip | Modules/Tooltip | offen, Daten über API.GetZoneFish | Tooltip ja |
| FishingStats | Zähler im Tooltip, Zeiträume | Modules/Tooltip | offen (Tagesdaten in DB vorhanden) | ja |
| Fishing.lua | Tooltip Fischen-Zauber, Fertigkeit/Boni | Modules/Tooltip | **teilportiert** (Fertigkeit, Zähler, Fangliste; Köder-/Buff-Aufteilung fehlt) | prüfen |
| FishingGear/Buffs/Lure | Angel, Köder, Buffs erkennen | Modules/Gear | offen | Köder-System in Retail anders? |
| FishingLureWarn | Köder-Warnung | Modules/Gear | offen | s. o. |
| FishingBobberAnchor/Hud | Schwimmer-Tooltip | Modules/Bobber | **neu gebaut** ereignisbasiert, eigener Positionsmodus; Anker am Mauszeiger entfällt | Retail? |
| FishingCast + FishingGear | Doppelklick-Auswerfen, Waffenwechsel | Modules/Cast, Core/Helper/Gear | **portiert** (Mock-Test), Auto-Köder fehlt noch | Retail? |
| DoubleClick* (Glimpse-Core) | Verteiler, Secure-Button | Modules/DoubleClick | **portiert** (Mock-Test), Optionsseite fehlt noch; Referenz: `reference/glimpse-doubleclick/` | Retail? |
| FishingJournal | Fischsuche automatisch an | Modules/Gear | offen | Retail? |
| FishingEvents/Sources | Debug-Hilfen | entfällt / Debug-Modul | – | – |
| Recipes* | Rezeptprüfung beim Händler | Modules/Recipes | offen, Händlerliste je Zone neu | Händler-API prüfen |

## Datenbank (BobbersJournal_DB, Version 1)
Siehe Kopfkommentar in `Core/DB.lua`. Kern: `world[zone]` (kontoweit: Fische mit Drops/Menge, **spots[]** = markierte Angelplätze mit Fischzahlen je Platz) und `chars[guid]` (Zähler, Tage). Jeder Eintrag trägt eine Flavor-Maske (1 Forever, 2 Retail, 3 beide), erkannt über `C_ClassTalents` (nur Retail), nicht über Versionsnummer.
Die alte Glimpse-Datenbank wird nicht migriert (andere Struktur, kein Zugriff auf deren Format).

## Neue Funktionen (offen)
Buch-Optik (Blizzard-Vorlagen aus wow-ui-source), Suche, Lesezeichen, Händlerliste je Zone (Kochrezepte mit Fisch, Schwimmer, Zubehör), Orts-Markierung auf der Karte (HereBeDragons optional).
