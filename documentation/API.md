# API

Global: `BobbersJournalAPI` (auch `BobbersJournal.API`). `API.VERSION = 1`. Alle Rückgaben sind Kopien.
Zone = uiMapID, in Instanzen `-instanceID`. `flavor` optional: `API.FOREVER`=1, `API.RETAIL`=2, `API.BOTH`=3 (Standard: laufender Client).
Koordinaten sind kartennormiert (0..1).

| Funktion | Rückgabe |
|---|---|
| `IsReady()` | true, sobald die DB geladen ist |
| `GetFlavor()` | Maske des laufenden Clients |
| `GetZoneFish(zone, flavor)` | `{ {itemID, drops, chance, avgQuantity}, ... }` nach Häufigkeit |
| `GetFishZones(itemID, flavor)` | `{ {zone, drops, chance}, ... }` |
| `GetZoneSpots(zone, itemID, flavor)` | `{ {x, y, count, fish={[itemID]=n}}, ... }` |
| `GetZoneCatches(zone)` | Beutefenster der Zone (Nenner der Chance) |
| `GetCaught(itemID, allChars)` | gefangene Menge |
| `GetTotals(zone)` | `{cast, catch, abort}` des Charakters |
| `Listen(fn)` | `fn("CATCH", zone, {[itemID]=qty})` / `fn("CAST", zone, outcome)` |

Stand: ungetestet im Spiel (nur Mock-Test).

Weitere Funktionen: `GetFishList(flavor)`, `GetZoneList(flavor)`, `GetZoneName(zone)`, `IsBookmarked(kind, id)`, `SetBookmark(kind, id, on)` (kind = "fish" oder "zone", kontoweit in `BobbersJournal_DB.bookmarks`). Listener-Ereignis zusätzlich `"BOOKMARK"`.

Datenerfassung: `GetLog(limit)` (neueste zuerst), `GetItemMeta(itemID)`, `GetLureStats()`, `GetFishingTime(zone, allChars)`. Felder des Logs stehen im Kopfkommentar von `Core/DB.lua`. Wetter wird nicht erfasst (keine API gefunden, die in beiden Clients existiert).

Buffs: `GetBuffStats()` liefert je Buff Anzahl, letzten Bonus und Quellen (item, quest, spell, other, unknown) sowie Items. Listener-Ereignis `"BUFF"`.
