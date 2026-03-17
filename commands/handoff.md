# .claude/commands/handoff.md

Vytvoř soubor docs/handoff.md s tímto obsahem:

## Handoff — $ARGUMENTS

### Datum
Aktuální datum a čas.

### Co bylo uděláno
Shrň dokončenou práci v této session.

### Rozpracované
Co je rozděláno a v jakém stavu.

### Další kroky
Konkrétní kroky k dokončení.

### Změněné soubory
Seznam souborů s krátkým popisem změn.

### Gotchas
Problémy na které jsme narazili a jak je řešit.

### Kontext
Důležité rozhodnutí a důvody proč jsme je udělali.

Pak commitni: git add -A && git commit -m "handoff: $ARGUMENTS"
