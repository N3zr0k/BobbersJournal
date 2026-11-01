# Farbschema Bobber's Journal

Einzige Quelle im Code: `BobbersJournal/Core/Helper/Colors.lua`. Farben nur dort definieren.
Vollständige Vorgabe von Sven: `/mnt/project-files/reference/FARBSHEMA-original.md` (inkl. Logo-Regeln und Dateiliste).

| Name im Code | HEX | Verwendung |
|---|---|---|
| `ocean` | `#0E3A5A` | Hauptfarbe, dunkle Hintergründe, Panels |
| `aqua` | `#22B3A7` | Akzente, aktive Tabs, Auswahl, Überschriften im Tooltip |
| `parchment` | `#D9B382` | Journal-Seiten, Sekundärtext |
| `leather` | `#6B4A2E` | Rahmen, Trenner |
| `sand` | `#F1E6D2` | Haupttext auf dunklem Grund |
| `red` | `#E64545` | sparsam: außergewöhnliche Fänge, Hinweise |

Logo und Icon bleiben unverändert (keine neuen Formen, Farben, Effekte). Die gelieferten PNGs müssen für WoW als TGA vorliegen (Media/), siehe PORTPLAN.

## Icons (Media/, TGA 32 Bit, je 64/128/256 px)
Bobber, Book, Equipment, Fish, Frameless (Logo), Settings, Statistik, Zones. Pfade zentral in `Core/Helper/Icons.lua`. Eingebaut: Frameless (Addon-Liste, Journal, HUD, Optionen), Fish/Zones/Book (Journal-Reiter), Bobber/Statistik/Fish (Optionen-Überschriften). Noch ungenutzt: Equipment (zurückgestelltes Feature), Settings (Broker-Menü).
