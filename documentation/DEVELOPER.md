# Developer

- Module: `BobbersJournal:RegisterModule(name)` mit optionalen `OnInitialize` / `OnEnable`.
- Ereignisse: `BobbersJournal:RegisterEvent(event, key, fn)`; `fn(event, ...)`, Fehler werden abgefangen (`BobbersJournal.lastError`).
- Daten: `Core/DB.lua` (Schema im Kopfkommentar), Schreiben nur durch das Tracker-Modul.
- Öffentliche Schnittstelle für andere Addons: siehe `API.md`.
- Ladereihenfolge: `BobbersJournal.xml`.
- Mitgelieferte Listen: `Modules/Data/Retail/` und `Modules/Data/Forever/` mit `Fishs.lua` (`Catalog.AddFish(level, mask, {itemIDs})`), `Vendors.lua` (`Catalog.AddVendor(npcID, {n, map, x, y, trainer, items})`) und `Recipes.lua` (`Catalog.AddRecipe(recipeID, name, {fishItemIDs})`). Jede Datei tut nur auf ihrem Client etwas. Händler und Rezepte werden mit den im Spiel gesammelten Daten der Datenbank zusammengeführt (die Datenbank gewinnt).

## Libraries
Eingebettet in `BobbersJournal/Libs/` (nicht bearbeiten), geladen über `Libs/Libs.xml`: LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0. Der Code nutzt sie nur über `LibStub(name, true)`. Fehlen sie, gibt es kein Minimap-Icon (kein Rückfall).

## Number display

All value and percent texts come from `ns.Format` (`Core/Helper/Format.lua`): `Value(count, fraction, plain)` gives "24 (15 %)" (count white, percent Bobber beige), `Percent(fraction, plain)` and `Count(n, plain)`. `plain = true` is for pages on parchment. Change colours and the percent notation in that file only.
