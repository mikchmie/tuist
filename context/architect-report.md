---
title: Raport architektoniczny — Moduł 4 (10xArchitect)
created: 2026-09-08
type: module-summary
---

# Raport architektoniczny — Moduł 4

> Źródła: `context/map/repo-map.md` (L2), `context/changes/test-service-analysis/research.md` (L3), `context/changes/refactor-opportunities/{research,plan}.md` (L4), `context/domain/{01,02,03}-*.md` (L5). Każde twierdzenie liczbowe pochodzi z tych artefaktów, nie z pamięci o kodzie.

## 1. Opisane projekty

**Wszystkie artefakty modułu 4 powstały na jednym repozytorium: [tuist](https://github.com/tuist/tuist) (monorepo).** Potwierdzenie: frontmatter `repository: tuist` w obu `research.md` (L3, L4) oraz jawny zakres `AGENTS.md`/`repo-map.md` w L2 i L5. **Nie ma tu drugiego projektu** — artefakty różnią się nie repo, tylko poziomem zejścia (repo → plik → refaktor → domena).

| | Repo | Stack | Skala (orientacyjnie, wg artefaktu) |
|---|---|---|---|
| L2 | `tuist` | Swift CLI + Elixir/Phoenix (serwer, cache, registry) + Rust (kura) + Helm/K8s | `cli/` = 98 targetów SPM, 526 krawędzi grafu importów; najaktywniejsze katalogi 12 mies.: `server/lib/tuist_web/live` (1419 zmian), `cli/Sources/TuistKit` (991), `cache/lib/cache` (538) |
| L3 | `tuist` (commit `92e9a72f`) | Swift (`TuistKit`) ↔ Elixir/Phoenix ↔ ClickHouse | `TestService.swift` = 2322 linie, 27 zależności; test 7002 linie, 24 mocki, >150 testów |
| L4 | `tuist` (commit `7d0e3f03`, weryfikacja `32cf7eb6`) | Swift (`TuistKit`, `TuistAutomation`, `TuistSupport`) | 14 problemów → 3 kandydatów strukturalnych; bliźniak `XcodeBuildTestCommandService` = 494 linie, 16 zależności, 8 testów/573 linie |
| L5 | `tuist` | Elixir/Phoenix + ClickHouse (serwer) i Swift (CLI) | `tests.ex` ~4400 linii; `shards.ex` 866 linii (nieprzeczytane w całości); 6 warstw przecieku wire-types w CLI |

**BRAK artefaktu:** `context/foundation/prd.md` i `tech-stack.md` nie istnieją (odnotowane w L5 dwukrotnie) — klasyfikacja Core/Supporting w L5 stoi na README, nie na PRD.

## 2. Mapa projektu (L2)

1. **Dwie strefy o nierównej widoczności.** Dla `cli/` istnieje zweryfikowany graf importów (`swift package dump-package`, 98/526, zero cykli — SwiftPM je wyklucza). Dla całej strony Elixir (`server/`, `cache/`, `registry/`, `kura/`) **nie zbudowano żadnego grafu** — to `unknown`, nie "brak sprzężeń". Ryzyko refaktoru tam jest z definicji niezmierzone.
2. **Strefa ryzyka #1: `cli/Sources/TuistKit/Services/TestService.swift`** — najgorętszy plik CLI (73 zmiany/12 mies.), god-service, 56/74 commitów od jednej osoby (Marek Fořt). To ona stała się punktem wejścia do L3.
3. **Lokalne centra (fan-in):** `TuistSupport` (38), `TuistServer` (36), `TuistEnvironment` (35), `TuistLogging` (31). Anty-centrum: `TuistKit` jako hub o fan-out 54 — topologicznie leży *nad* warstwą komend, semantycznie powinien pod nią; w repo współistnieją dwa modele warstwowania (`*Command` → usługi → rdzeń vs. `*Command` → `TuistKit` → prawie wszystko).
4. **Entry pointy:** `cli/Package.swift` (cały graf naraz), `server/lib/tuist_web/router.ex` (zweryfikowany prawdziwy węzeł architektoniczny: 43 obszary, 152 zmiany, brak dominującego commita — w odróżnieniu od `mise.toml`, który dotyka tyle samo obszarów, ale mechanicznie).
5. **Najważniejszy unknown organizacyjny:** bus factor — Marek Fořt i Pedro Piñera to jedyne dwie osoby pokrywające wszystkie 5 zbadanych obszarów ryzyka w `cli/`; dla stref serwerowych (3, 4, 6) artefakt **nie ma danych o kontrybutorach** w ogóle.

## 3. Analiza ficzera (L3)

**Co badałem i dlaczego:** przepływ `tuist test` — bo mapa (§4) wskazała `TestService.swift` jako strefę ryzyka #1, a jednocześnie `tuist test` był najgorętszym *tematem* roku po obu stronach stacku (Q3 w CLI, `server/lib/tuist/tests.ex` po stronie serwera). Badanie zamyka też część luki "brak grafu Elixira" dla tego jednego przepływu.

**Feature overview.** Wejściem jest komenda CLI (`TestRunCommand.swift:410-466` → `TestService.run(...)`); przed uruchomieniem CLI robi round-trip po listę testów w kwarantannie i (opcjonalnie) po plan shardów, który serwer wylicza bin-packingiem z historycznej analityki. Stan zmienia się w dwóch miejscach: w blob storage (surowy `.xcresult` w trybie `.remote`) i w **ClickHouse** — tabela `test_runs` + fan-out `test_case_runs`/`test_module_runs`/`test_suite_runs` przez `TestsController.create/2` → `Tuist.Tests.create_test/1` (nie Postgres — to ustalenie zamknęło jeden unknown z mapy). Wraca id runu i URL dashboardu wypisany użytkownikowi; w trybie `.remote` worker Oban na flocie macOS dopisuje ostateczny wynik, nadpisując placeholder `"processing"`.

**Technical debt — 3 najważniejsze:**
1. **Nieprzetestowana kontynuacja kwarantanny** (`TestService.swift:1391-1393`) — sedno funkcji ("run nie wywraca się, gdy zawiodły tylko testy w kwarantannie") jest zaimplementowane, ale mock `onlyQuarantinedTestsFailed` zwraca `false` we **wszystkich 5** miejscach pliku testowego (**potwierdzone ast-grep 0.45.3**, linie 160-164, 4115, 4217, 4471). Regresja przeszłaby CI niezauważona.
2. **Ukryty bliźniak `XcodeBuildTestCommandService.swift`** — dzieli **15 z 16 własnych zależności (94%)** z `TestService` (**ast-grep; pierwotne oszacowanie "~14" zostało wzmocnione, nie osłabione**) i współzmienia się w 36% commitów. Logika uploadu/kwarantanny/shardingu jest synchronizowana ręcznie w dwóch miejscach.
3. **Blast radius wychodzi poza CLI:** zmiana kształtu przepływu ciągnie za sobą wygenerowany klient OpenAPI (14/73 commitów, sparowane w 100%), klaster shardingu (3 serwisy), `server/lib/tuist/{tests,shards}.ex` (7 i 5/73) oraz migracje ClickHouse (7/73). Granica OpenAPI jest niemal czysta — z **jednym wyjątkiem obalonym przez ast-grep**: `TestService.swift:1479` konstruuje `Components.Schemas.ShardPlan` wprost.

## 4. Plan refaktoryzacji (L4)

**Co refaktoryzowane:** kandydaci **B i C** z rankingu. B — usunięcie klastra 5 nieosiągalnych metod (`TestService.swift:2239-2309`) i dedup `passedValue` (4 identyczne kopie, 2 moduły) do jednej `public` funkcji w `TuistSupport`. C — domknięcie szwu OpenAPI: `ShardMatrixOutputServicing` zyskuje domyślne `outputEmpty()`, a `TestService.swift` przestaje dotykać typów generowanych (docelowo `grep` = 0 trafień).

**Czego świadomie NIE robimy:** Kandydata A (wspólny `TestExecutionOrchestrator`), mimo że ranking stawia go na #1 pod względem dźwigni — bo wymaga najpierw domknięcia pokrycia po stronie bliźniaka (8 testów/573 linie, zero testów akceptacyjnych) i zawiera **realną decyzję behawioralną**: rozjazd guardu `action != .build` w `uploadResultBundleIfNeeded`, której ten plan nie podejmuje. Poza zakresem także 8 luk testowych z tabeli klasyfikacji i jakakolwiek zmiana w `server.yml`/`Types.swift` (pliki generowane).

**Fazy (jeden PR, fazy niezależne kodowo):**
- **Faza 1** — usuń martwy klaster + własną kopię `passedValue` z `TestService.swift`. *Weryfikacja: auto* (build, `mise run lint`, `TestServiceTests`, grep na osierocone referencje) **+ ręczna** (smoke `tuist test`).
- **Faza 2** — jedna implementacja `passedValue` w `TuistSupport`, 3 lokalne kopie skasowane, call-site'y bez zmian. *Weryfikacja: auto* (4 targetowane suity + 3 nowe testy kontraktowe, grep „dokładnie jedna implementacja") **+ ręczna** (`tuist test` i `tuist xcodebuild test/build` z flagami przelotowymi).
- **Faza 3** — `outputEmpty()` w serwisie, przełączony call-site w `TestService`. *Weryfikacja: wyłącznie auto* — 4 istniejące testy (asertują kształt, nie sposób konstrukcji) + 1 nowy test na konkretnym serwisie + `TestAcceptanceTests`; ręcznej **świadomie brak**, bo ścieżka jest osiągalna tylko przez „zero testów do uruchomienia" + `--build-only`.

## 5. Domena wg DDD (L5)

**Ubiquitous language (5 kluczowych):** *Test Run* (jeden wiersz ClickHouse `test_runs`), *Test Processing Mode* (`local`/`remote`/`off` — decyduje, **gdzie** parsowany jest `.xcresult`), *Quarantined Test* (`muted`/`skipped`, sterowane serwerowo), *Shard Plan / Shard Run* (plan bin-packingu vs. raport pojedynczego shardu), *Shard Granularity* (`module`|`suite`).

**Najważniejsze rozjazdy model-vs-kod:** (a) `Test Run` ma **drugiego, niezbadanego producenta** — `Tuist.Bazel.TestReportIngestor`; schemat od początku przewiduje `build_system ∈ {xcode, gradle, bazel}`, choć cała analiza L3 opisuje tylko ścieżkę Xcode (L5-02 częściowo to zamknęło: ścieżka Bazel idzie przez jedyną w pełni zwalidowaną ścieżkę zapisu). (b) README nazywa „Build insights" jedną cechą, kod ma dwa odrębne agregaty (`test_runs` vs. `Tuist.Builds`) połączone nullowalnym FK. (c) Pojęcie *Shard Granularity* **nie ma własnego typu w CLI** — jest aliasem wygenerowanego enuma OpenAPI, w warstwie parsowania argumentów.

**Niezmiennik #1 i jego agregat:** integralność **statusu scalonego Test Run** (N1+N2+N4+N7), agregat: *Sharded Test Run* (`Tuist.Tests.Test` + podrzędne `ShardRun`). Reguła: status terminalny tylko gdy wszystkie shardy zaraportowały **lub** którykolwiek zgłosił terminalną porażkę; inaczej `in_progress`, domykane 6-godzinnym reaperem. Diagnoza: **3 z 4 ścieżek zapisu omijają changeset** (`insert_all`), `ShardRun` nie ma changesetu w ogóle, `compute_final_shard_status` cicho zwraca `"success"` dla nieznanego statusu, a dashboard maluje nierozpoznany status kolorem sukcesu i nie liczy go w żadnym liczniku.

**Anti-Corruption Layer:** przecieka **wygenerowany klient OpenAPI** (`Components.Schemas.*`/`Operations.*`) — przez **4 role warstwowe / 12 plików**: parsowanie argumentów CLI, orkiestracja (`TestService`), formatowanie wyjścia (`ShardMatrixOutputService`) i sama warstwa integracji (6 serwisów `TuistServer`, które łamią własny, istniejący już wzorzec `Server*`). Najgorszy pojedynczy przypadek: **fałszywy ACL** — `ServerTestRun` to goły `typealias` do wire-payloadu, nazwa udaje izolację, której nie ma. To samo pojęcie „Test Run" ma dziś **3 różne kształty Swift**.

## 6. Decyzje, które należą do mnie

AI dostarczyło skanów i list; wybory zakresu były moje. W przeszłości kontrybuowałem do CLI, więc analizę postanowiłem skupić na tym obszarze projektu. **Po pierwsze**, mapa wskazała sześć stref ryzyka — zszedłem do `TestService`, bo tylko tam graf, historia gita i temat roku wskazywały to samo miejsce, świadomie zostawiając strefę „Elixir bez grafu" jako niezmierzoną. **Po drugie**, kazałem weryfikować każde twierdzenie strukturalne ast-grepem zamiast ufać odczytom sub-agentów — i to się opłaciło: obaliło „czystą granicę OpenAPI" (jedno realne trafienie na `:1479`), doprecyzowało martwy klaster i **wzmocniło** dowód duplikacji z ~14/27 do 15/16. **Po trzecie**, wbrew rankingowi dźwigni odłożyłem Kandydata A i wziąłem do planu B+C — bo A wymaga najpierw utworzenia nietrywialnej siatki testowej po stronie bliźniaka; wolałem wysłać dwie zmiany o zerowym ryzyku niż jedną dużą bez detektora regresji. **Po czwarte**, w warstwie DDD nie przyjąłem rankingu z własnej wcześniejszej destylacji: przesunąłem #1 z kwarantanny (Core, ale **poprawnie działa** — ryzyko przyszłe) na integralność statusu (Core i **dziś naruszalna** — 3/4 ścieżki bez walidacji), zmieniając kryterium z „brak testu" na „brak egzekwowania w kodzie". **Po piąte**, przy ACL odrzuciłem kandydata `ExAws.S3` na rzecz wygenerowanych typów OpenAPI — bo źródło zmiany leży poza CLI i zmienia się rutynowo, a fałszywy ACL jest groźniejszy niż jawny brak izolacji.
