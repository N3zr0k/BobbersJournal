# Bobber's Journal

Angel-Tagebuch und Verbesserungen für den Beruf Angeln in World of Warcraft (WoW Forever und Retail).

> **Status 0.1.0-alpha.1:** Alles ist bisher nur per Mock-Test geprüft, **nicht im Spielclient**. Es kann Fehler geben.

## Funktionen
- **Fangdaten:** Würfe, Fänge, Fehlwürfe, Gebiet und Subzone, Koordinaten, Köder, Angelfertigkeit, Serverstunde, Angelzeit und Angelbuffs mit Quelle. Beifang wird mit Item-Klasse gespeichert.
- **Journal im Buchdesign:** Fische, Gebiete (Fangorte und Chancen), Suche und Lesezeichen. Händlerliste folgt.
- **Auswerfen per Doppelklick oder Taste** (standardmäßig aus). Auf Forever optional mit Waffenwechsel: Waffen merken, Angel anlegen, nach 5 m oder nach dem Kampf zurück.
- **Tooltip** am Zauber „Fischen“: Fertigkeit, Zähler und Fangliste der Zone. Retail zeigt zusätzlich die Fertigkeit je Erweiterung.
- **Schwimmer-Anzeige:** transparent mit Logo, frei verschiebbar (Optionen → Position bearbeiten).
- **Minimap-Icon** und Eintrag im Addon-Compartment.
- **API für andere Addons:** `BobbersJournalAPI`, siehe `documentation/API.md`.

## Bedienung
- `/bob` öffnet das Journal, `/bob options` die Einstellungen, `/bob probe` zeigt Fertigkeitsdaten für Fehlerberichte.
- Taste fürs Auswerfen: Optionen → Tastaturbelegung → AddOns.

## Installation
Ordner `BobbersJournal` nach `Interface/AddOns` kopieren.

## Daten
Gespeichert in `BobbersJournal_DB` (Fangdaten, Lesezeichen) und `BobbersJournal_Settings` (Einstellungen), beide kontoweit.

## Entwickler
`documentation/DEVELOPER.md`, `documentation/API.md`, `documentation/PORTPLAN.md`. Basis ist der Angel-Code aus Glimpse: Professions.

## Lizenz
Alle Rechte vorbehalten (siehe `LICENSE`).
