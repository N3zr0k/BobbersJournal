# Developer

- Module: `BobbersJournal:RegisterModule(name)` mit optionalen `OnInitialize` / `OnEnable`.
- Ereignisse: `BobbersJournal:RegisterEvent(event, key, fn)`; `fn(event, ...)`, Fehler werden abgefangen (`BobbersJournal.lastError`).
- Daten: `Core/DB.lua` (Schema im Kopfkommentar), Schreiben nur durch das Tracker-Modul.
- Öffentliche Schnittstelle für andere Addons: siehe `API.md`.
- Ladereihenfolge: `BobbersJournal.xml`.

## Libraries
Eingebettet in `BobbersJournal/Libs/` (nicht bearbeiten), geladen über `Libs/Libs.xml`: LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0. Der Code nutzt sie nur über `LibStub(name, true)`. Fehlen sie, gibt es kein Minimap-Icon (kein Rückfall).
