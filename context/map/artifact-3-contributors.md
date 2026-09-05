# Contributors: kluczowi kontrybutorzy w obszarach ryzyka `cli/` (ostatnie 12 miesięcy)

Kontynuacja [`artifact-1-territory.md`](./artifact-1-territory.md) i [`artifact-2-structure.md`](./artifact-2-structure.md). Dla pięciu zidentyfikowanych obszarów Swift w `cli/`, które mogą wymagać kontaktu z kontrybutorami przed dalszymi zmianami (refaktor, decyzja architektoniczna, ocena bezpieczeństwa usunięcia), zmapowano realnych autorów commitów z ostatnich 12 miesięcy (2025-09-05 → 2026-09-05) i skategoryzowano ich aktywność tematycznie.

## Metodologia

`git log --since="12 months ago" --format='%an|%ae|%s'` dla ścieżek:
- `cli/Sources/TuistKit/Services/TestService.swift`
- `cli/Sources/TuistKit`
- `cli/Sources/TuistLoader/SwiftPackageManager/PackageInfoMapper.swift`
- `cli/Sources/TuistLoader/Loaders/PackageInfoLoader.swift`
- `cli/Sources/TuistDependencies`
- `cli/Sources/TuistExtension`

**Filtrowanie botów/agentów:** sprawdzono pełną listę 33 unikalnych par autor/email pod kątem kont automatyzacji (`dependabot`, `renovate`, `tuistit`, `github-actions[bot]`) oraz autorów typu "Claude"/"Codex"/"Copilot" bez wyraźnego autorstwa człowieka w polu `Author`. **Nie znaleziono żadnego** — wszystkie konta to identyfikowalne osoby (część pod pełnym imieniem i nazwiskiem, część pod nickiem GitHub). Commity współautorskie z agentami (`Co-Authored-By: Claude/Codex`) nie były odrębnie wykluczane, bo autorstwo `git` (pole `Author`) pozostaje ludzkie we wszystkich sprawdzonych przypadkach.

Klasyfikacja tematyczna: ręczny przegląd treści commitów (`%s`) per autor, wspierany grepem po słowach kluczowych (`shard`, `cache`, `xcresult`, `inspect`, `package|SwiftPM`, `registry`, `graph`, `generat`, `hash`).

## 1. `TuistKit/Services/TestService.swift`

| Kontrybutor | Commity | Tematyka |
|---|---:|---|
| **Marek Fořt** | 56 | Zdecydowany właściciel: sharding testów, selective testing, planowanie suite'ów po historii serwera, obsługa xcresult/result bundle, integracja z cache'em testów |
| **Pedro Piñera** | 13 | Wsparcie architektoniczne wokół integracji z SwiftPM/generacją w kontekście testów |
| Eduardo Nunes | 2 | Wąska nisza: `--no-upload` dla selective-testing hashes, wykluczanie targetów pominiętych przez test plan |
| Irena Lee | 1 | Deduplikacja logów selective-testing |
| Roman Anpilov | 1 | Flaga `--skip-unit-tests` |
| Curtis Ying | 1 | UI listy muted/skipped test cases |

**Kontakt:** Marek Fořt — jedyny, kto zna całość pliku; pozostali trafiają tylko po konkretny, wąski temat.

## 2. `TuistKit` (cały moduł-hub)

| Kontrybutor | Commity | Tematyka |
|---|---:|---|
| **Marek Fořt** | 187 | Cache hashing/analytics (48 commitów z "cache"), sharding (29), inspect/build analytics (12), xcresult (10), edge case'y SwiftPM (14) |
| **Pedro Piñera** | 84+3 | Mapowanie/generacja pakietów SwiftPM (29), moduł cache (24), opcje generacji projektu (10) |
| Hilton Campbell | 7-8 | Wyspecjalizowany w `tuist inspect` — redundant dependencies, cache profiles |
| Christoph Schmatzler | 5 | Cache jako produkt: remote cache cleaning, custom cache endpoints, API+CLI parami z `cache/` |
| wojmangh | 2 | Edge case'y SDK/platform (xcframeworks, Catalyst) |

**Kontakt:** Marek i Pedro pokrywają 90%+ obszaru, ale **Hilton Campbell** to jedyny realny adres do `tuist inspect`, a **Christoph Schmatzler** — do integracji cache CLI ↔ `cache/` serwis.

## 3. `PackageInfoMapper.swift` / `PackageInfoLoader.swift`

| Kontrybutor | Commity | Tematyka |
|---|---:|---|
| **Pedro Piñera** | 34 | Właściciel domeny SwiftPM mapping: plugin product graphs, macro targets, modulemaps, Swift versions/traits, package accessors |
| Marek Fořt | 16 | Wsparcie, przecinające się z cache hashingiem dla pakietów |
| Seungju Lee | 2 | Optymalizacje wydajności (dictionary/set lookup w mapperze) |
| Loupehope | 2 | Rozwiązywanie typu produktu SPM, XCFramework force-loading |
| YoHan Cho | 1 | SE-0162 — custom SPM target layouts |
| Vijay Tholpadi | 1 | Cykliczna zależność, gdy target SPM owija zewnętrzny produkt o tej samej nazwie |

**Kontakt:** Pedro Piñera jednoznacznie — to jego domena od lat.

## 4. `TuistDependencies`

| Kontrybutor | Commity | Tematyka |
|---|---:|---|
| **Pedro Piñera** | 5 | Koordynacja odczytów grafu SwiftPM, namespacing artefaktów zależności, filtrowanie destination Catalyst |
| **Marek Fořt** | 3 | Relokacja projektów registry, wsparcie Linuksa dla auth/cache |
| Marquez Kim | 1 | Orphan local SPM tests — przecięcie linkable dependency destinations |
| sabade-omkar | 1 | Zachowanie test targetów dla lokalnych pakietów SPM |

**Kontakt:** Pedro/Marek jako generaliści; **Marquez Kim i sabade-omkar** to jedyne osoby, które w ogóle dotknęły przypadku "lokalny pakiet SPM + testy" — warto ich zapytać, jeśli temat kontaktu dotyczy właśnie tej niszy.

## 5. `TuistExtension`

| Kontrybutor | Commity | Tematyka |
|---|---:|---|
| Marek Fořt | 2 | Flaga `--cache-warm-no-upload`, wsparcie Linuksa dla cache/auth |
| Pedro Piñera | 1 | Konfiguracja scratch directory dla cache warm |
| gnejfejf2 | 1 | Opcja `--cache-profile` z wykluczeniami sterowanymi profilem |

**Korekta względem `artifact-2-structure.md`:** commity pokazują, że `TuistExtension` to w praktyce wyłącznie powierzchnia CLI dla **konfiguracji `cache warm`** (nie ogólny hub 6 obszarów, jak sugerowała sama topologia grafu zależności) — nikt nie ma tu >2 commitów w roku, więc brak wyraźnego "właściciela"; Marek Fořt jako ostatni i najczęstszy autor to najbliższy kandydat na pierwszy kontakt, ale trafność jest niska.

## Podsumowanie międzyobszarowe

Marek Fořt i Pedro Piñera to jedyne dwie osoby z pełnym pokryciem wszystkich pięciu obszarów — ale ich specjalizacje się rozjeżdżają:
- **Marek Fořt** — testy/sharding/selective-testing, cache hashing i analityka, xcresult/result bundle, `tuist inspect`.
- **Pedro Piñera** — mapowanie i generacja SwiftPM, moduł cache (warm/binary), koordynacja grafu zależności.

Reszta listy to zewnętrzni kontrybutorzy z pojedynczymi, bardzo wąskimi commitami — wartościowi tylko wtedy, gdy temat kontaktu pokrywa się dokładnie z ich commitem:
- Lokalne pakiety SPM + testy → Marquez Kim / sabade-omkar
- `tuist inspect` → Hilton Campbell
- Cache CLI ↔ serwis `cache/` → Christoph Schmatzler
- Wydajność `PackageInfoMapper` → Seungju Lee
- Selective-testing edge case'y → Eduardo Nunes
