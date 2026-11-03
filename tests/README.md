# Rauchtest für Bobber's Journal (ohne WoW-Client)

Lädt das Addon (Reihenfolge aus BobbersJournal.xml) in einer simulierten Forever- oder Retail-Umgebung (lupa, Lua 5.5), feuert
Login und typische Events und ruft `/bob`, `/bob options`, `/bob probe`, `/bob export` auf. Alle Fehler werden gesammelt.

    cd tests
    python3 run.py forever     # oder: retail
    python3 scenario.py        # Forever: Wurf, Fang, Fehlwurf, Skill über GetSkillLineInfo

Grenzen: Die Umgebung ist ein Modell (Stubs für Frames und APIs), kein echter Client. Sie findet Ladefehler, nil-Aufrufe und
Logikfehler, aber keine Fehler durch echte API-Unterschiede. Pfad ADDON_DIR steht in run.py und scenario.py.
