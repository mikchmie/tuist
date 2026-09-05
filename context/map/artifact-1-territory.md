# Territory: aktywność w repo Tuist (ostatnie 12 miesięcy)

Analiza `git log` z ostatnich 12 miesięcy (okno: 2025-09-03 → 2026-09-03), mająca odpowiedzieć na pytanie "gdzie realnie dzieje się praca w tym repo". Metodologia i wyniki poniżej, żeby dało się je odtworzyć lub rozbudować.

## Metodologia i filtrowanie szumu

Surowe dane: `git log --since="12 months ago" --name-only` → ~48k zmian plików w ~4141 commitach. Po odfiltrowaniu szumu zostało ~28.5k realnych zmian.

Odfiltrowane kategorie (potwierdzone, nie tylko domysł — sprawdzone commit-po-commicie):
- **Lockfile'y / manifesty zależności**: `mise.lock`, `Package.resolved`, `*.lock`, `package-lock.json`
- **Auto-generowane wersje/release**: `mise.toml`, `CHANGELOG.md`, `Constants.swift` (TuistConstants/TuistSupport) — bumpowane mechanicznie przy każdym `[Release]`
- **Wygenerowany kod z OpenAPI**: `cli/Sources/TuistServer/OpenAPI/{Types,Client}.swift`, `server.yml` — CLAUDE.md zabrania ręcznej edycji, generowane z serwera
- **Configi CI/infra**: `.github/workflows/*`, `infra/helm/tuist/values-*.yaml`, `server/mix.exs`, `server/config/*.exs`
- **Tłumaczenia**: `.po`/`.pot`, oraz całe drzewa językowe inne niż `en` (`docs/docs/<lang>`, `server/priv/docs/<lang>`) — zgodnie z regułą repo "nie ruszaj treści w innych językach"; `.po` edytuje wyłącznie bot `tuistit`
- **Snapshoty/fixture binarne**: `cli/Tests/Fixtures/**` (blob-y `.xcresult`: sqlite3, plist, opaque refs)
- **"Złote" wygenerowane przykłady**: `examples/xcode/**` — checked-in referencyjne projekty Xcode (`generated_*`), aktualizowane mechanicznie przy każdej zmianie logiki generowania (funkcjonalnie snapshoty)
- **`cli/Fixtures/**`**: dodatkowo wykluczone przy analizie kwartalnej — 2261 z 2636 zmian pochodziło z jednego mechanicznego commita (#8962, "rename fixtures to examples", 2307 plików, same usunięcia)
- **`cli/TuistCacheEE`**: pusty katalog / wskaźnik submodułu — zmiany to bump referencji, nie kod

## a) Top 10 obszarów aktywności — całe repo

| # | Ścieżka | Zmiany | Co to jest |
|---|---|---|---|
| 1 | `server/lib/tuist_web/live` | 1419 | LiveView-y dashboardu (Phoenix) |
| 2 | `server/test/tuist_web` | 1014 | Testy warstwy web serwera |
| 3 | `cli/Sources/TuistKit` | 991 | Komendy/serwisy CLI |
| 4 | `server/lib/tuist_web/controllers` | 567 | Kontrolery API/HTML serwera |
| 5 | `cache/lib/cache` | 538 | Logika serwisu cache |
| 6 | `cli/Sources/XcodeGraph` | 463 | Model grafu projektu Xcode w CLI |
| 7 | `server/assets/app` | 437 | Frontend dashboardu (TS/JS) |
| 8 | `server/lib/tuist_web/marketing` | 430 | Strona marketingowa (LiveView) |
| 9 | `infra/helm/tuist/templates` | 428 | Szablony Helm (K8s manifesty) |
| 10 | `server/priv/docs/en` | 426 | Treść dokumentacji (EN) |

Top-level dla porównania (zbyt ogólne): `server` (12687), `cli` (6559), `infra` (2719), `cache` (1366), `kura` (1086), `noora` (945).

## b) Top 10 plików — całe repo

| # | Plik | Zmiany |
|---|---|---|
| 1 | `server/lib/tuist_web/router.ex` | 152 |
| 2 | `server/lib/tuist/tests.ex` | 116 |
| 3 | `server/data-export.md` | 115 (wysoko z powodu reguły procesowej CLAUDE.md — aktualizacja przy każdej zmianie schematu, nie organiczna złożoność) |
| 4 | `server/lib/tuist/environment.ex` | 105 |
| 5 | `Tuist/ProjectDescriptionHelpers/Module.swift` | 91 |
| 6 | `server/lib/tuist.ex` | 85 |
| 7 | `server/test/test_helper.exs` | 81 |
| 8 | `server/priv/repo/seeds.exs` | 77 |
| 9 | `cli/Sources/TuistKit/Services/TestService.swift` | 73 |
| 10 | `server/test/tuist/tests_test.exs` | 71 |

**Wniosek:** `tuist test` / test analytics (xcresult, runy testów) to najgorętszy obszar całego roku — widoczne zarówno po stronie serwera (`tests.ex`), jak i CLI (`TestService.swift`).

## c) Drill-down: podfoldery `cli/` (Swift)

Dodatkowo wykluczono `cli/TuistCacheEE` (submodule pointer).

| # | Ścieżka | Zmiany |
|---|---|---|
| 1 | `cli/Tests/TuistKitTests` | 571 |
| 2 | `cli/Sources/TuistKit/Services` | 539 |
| 3 | `cli/Sources/TuistServer/Services` | 405 |
| 4 | `cli/Fixtures` | 384 (test fixture manifesty, nie prod. kod) |
| 5 | `cli/Sources/TuistGenerator` | 323 |
| 6 | `cli/Sources/TuistLoader` | 295 |
| 7 | `cli/Sources/TuistKit/Commands` | 268 |
| 8 | `cli/Sources/XcodeGraph/Tests` | 237 |
| 9 | `cli/Sources/XcodeGraph/Sources` | 217 |
| 10 | `cli/Tests/TuistGeneratorTests` | 204 |

Top pliki w `cli/`: `TestService.swift` (73), `PackageInfoMapper.swift` (61, integracja SwiftPM), `TestServiceTests.swift` (60), `PackageInfoMapperTests.swift` (52), `GenerateAcceptanceTests.swift` (48), `ResourcesProjectMapper.swift` (42), `GraphTraverser.swift` (38), `ListBundlesService.swift` (31).

## d) Trend kwartalny (nacisk pracy w `cli/` w czasie)

Okna trailing: Q1 (2025-09-03→12-03), Q2 (12-03→2026-03-03), Q3 (03-03→06-03), Q4 (06-03→09-03, bieżący).

| moduł | Q1 | Q2 | Q3 | Q4 |
|---|---:|---:|---:|---:|
| `Tests/TuistKitTests` | 60 | 226 | 175 | 110 |
| `TuistKit/Services` | 55 | 249 | 153 | 82 |
| `TuistServer/Services` | 39 | 184 | 66 | **116** |
| `TuistGenerator` | 31 | 131 | 100 | 61 |
| `TuistLoader` | 36 | 91 | 105 | 63 |
| `XcodeGraph/*` | 0 | 303 | 131 | 20 |
| `TuistCache` | 5 | 36 | 3 | **61** |

**Fale tematyczne, sekwencyjne, nie równoległe:**
- **Q1** — build/inspect analytics (`CreateBuildService`, `XCActivityLogController`, `InspectBuildCommandService`)
- **Q2** — duży refaktor grafu projektu (`GraphTraverser`, `ResourcesProjectMapper`) + vendorowanie `XcodeGraph` jako osobnego pakietu (PR #9616, 2026-02-26; stąd skok 0→163/140)
- **Q3** — ostry zwrot w stronę `tuist test` (`TestService.swift` 38 zmian w kwartale — najbardziej skoncentrowany kwartał roku)
- **Q4** — SwiftPM (`PackageInfoMapper`) + odbicie `TuistServer/Services` i `TuistCache` (oba najwyższe w całym roku)

## e) Sprzężenia (co-occurrence) modułów w `cli/`

Na 1165 commitach dotykających `cli/` (648 z ≥2 modułami):

**Top pary:** `TuistKit/Services` ↔ `Tests/TuistKitTests` (163), `TuistGenerator` ↔ `Tests/TuistGeneratorTests` (131), `TuistLoader` ↔ `Tests/TuistLoaderTests` (111), `TuistKit/Commands` ↔ `TuistKit/Services` (62), `TuistKit/Services` ↔ `TuistServer/Services` (52).

**Top trójka:** `TuistKit/Commands` + `TuistKit/Services` + `Tests/TuistKitTests` (56) — "kanoniczny kształt" commita dodającego/zmieniającego komendę CLI.

**Wnioski dla top 3:**
- **`Tests/TuistKitTests`** — dobra dyscyplina: zmiana kodu i test niemal zawsze w tym samym commicie, rzadko izolowane do jednej warstwy.
- **`TuistKit/Services`** — architektoniczny hub: leży między `Commands` (CLI-facing) a `TuistServer/Services` (API-facing).
- **`TuistServer/Services`** — silniej sprzężone z modułami CLI niż z własnymi testami (`TuistServerTests` tylko 23) → rozwój klienta API napędzany odgórnie potrzebami CLI, nie API-first.

## f) "Wspólny mianownik" — plik łączący najwięcej obszarów (całe repo, bez filtrów)

Dla każdego pliku policzono, z iloma różnymi katalogami top-level współwystępuje w tym samym commicie:

| Plik | Liczba obszarów | Commity | Charakter |
|---|---:|---:|---|
| `mise.toml` | 43 | 412 | **Szum mechaniczny** — centralny manifest wersji monorepo, bumpowany w każdym commicie `[Release]` razem z niemal wszystkimi katalogami |
| `server/lib/tuist_web/router.ex` | 43 | 152 | **Realne sprzężenie** — zweryfikowane: brak jednego dominującego commita (max 10 obszarów/commit), rozłożone na dziesiątki PR-ów. Naturalny centralny punkt, przez który przechodzi każda nowa funkcja dashboardu/API |
| `mise.lock`, `Package.resolved`, `Package.swift`, `.github/workflows/release.yml`, OpenAPI `Types/Client.swift` | 29–37 | — | Ta sama mechanika release'owa co `mise.toml` |

**Wniosek:** hipoteza (config/tłumaczenia/generowane jako "wspólny mianownik") potwierdzona dla `mise.toml` i całej rodziny plików release'owych — to szum wart dalszego filtrowania. `router.ex` to wyjątek: prawdziwy węzeł architektoniczny, nie artefakt.

## g) Weryfikacja istnienia plików (na HEAD)

Sprawdzono `git ls-files` dla ~35 plików wymienionych w tej analizie. **2 nie istnieją już pod starą ścieżką** (obie to przenosiny, nie usunięcia):

| Stara ścieżka | Co się stało | Nowa ścieżka |
|---|---|---|
| `cli/Sources/TuistKit/Services/Inspect/InspectBuildCommandService.swift` | Wydzielony do osobnego pakietu | `cli/Sources/TuistInspectCommand/Services/InspectBuildCommandService.swift` |
| `.github/workflows/release.yml` | Rozbity na workflow per komponent (PR #11309) | `.github/workflows/cli-release.yml`, `gradle-release.yml`, `app-release.yml`, itd. |

Pozostałe pliki (`TestService.swift`, `GraphTraverser.swift`, `PackageInfoMapper.swift`, `router.ex`, `ListBundlesService.swift`, `mise.toml` i reszta) — potwierdzone jako aktualnie śledzone pod tymi samymi ścieżkami, bezpieczne do cytowania w dalszej analizie.
