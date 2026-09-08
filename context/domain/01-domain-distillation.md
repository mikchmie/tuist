---
title: Domain Distillation — Test Run Analytics (tuist test)
created: 2026-09-08
type: domain-distillation
---

# Domain Distillation: Test Run Analytics

## KROK 0 — Odkrycie kontekstu

**Czego NIE znaleziono:** `context/foundation/` nie zawiera `prd.md` ani `tech-stack.md` — katalog istnieje (`context/foundation/README.md`), ale jest pusty poza konwencją. To monorepo (patrz `AGENTS.md` root) bez jednego dokumentu wizji produktu spisanego jako PRD.

**Co posłużyło jako materiał źródłowy zamiast tego** (zgodnie z instrukcją KROK 0 — brak PRD odnotowany jako ograniczenie, oparto się o README + kod + istniejące artefakty badawcze repo):

1. `README.md:18-39` (root) — jedyny opis pozycjonowania produktu ("Tuist is a virtual platform team for Swift app devs", lista 7 "solutions": Generated projects, Cache, Selective testing, Registry, Build insights, Bundle insights, Previews).
2. `context/map/repo-map.md` — artefakt onboardingowy (git activity + graf importów CLI), wskazuje `cli/Sources/TuistKit/Services/TestService.swift` jako strefę ryzyka #1 repo (§4).
3. `context/changes/test-service-analysis/research.md` — pełne trasowanie e2e przepływu `tuist test` (CLI → serwer → ClickHouse → dashboard), z tabelą pokrycia testów i blast radius. Twierdzenia strukturalne w tym dokumencie zostały tam zweryfikowane przez `ast-grep 0.45.3` (sekcja "Weryfikacja strukturalna").
4. `context/changes/refactor-opportunities/research.md` — kontynuacja: klasyfikacja długu technicznego na kandydatów strukturalnych, z osią historii (`git log`) i wykonalności. Twierdzenia ponownie zweryfikowane niezależnie na innym commicie (sekcja "Weryfikacja twierdzeń").

**Decyzja o zakresie:** repo to monorepo wielu produktów (CLI Swift, serwer Elixir, cache, registry, kura...). Żaden pojedynczy dokument nie opisuje całej domeny biznesowej Tuist. Spośród dostępnych źródeł jeden obszar ma wyjątkowo gęstą, dwukrotnie zweryfikowaną wiedzę domenową: **przepływ `tuist test` i jego serwerowy odpowiednik analityki testów** (`Tuist.Tests`, `Tuist.Shards`). Ta destylacja skupia się na tym bounded contexcie — nie na całym Tuiście — i cytuje wyłącznie pliki bezpośrednio zweryfikowane (w tej sesji lub we wskazanych, ast-grep-zweryfikowanych badaniach źródłowych, zawsze oznaczone przy cytacie).

**Stack tego obszaru:** CLI Swift (`cli/Sources/TuistKit/Services/TestService.swift`, `cli/Sources/TuistTestCommand/`) ↔ serwer Elixir/Phoenix (`server/lib/tuist/tests.ex`, `server/lib/tuist/shards.ex`) ↔ ClickHouse (`Tuist.IngestRepo`/`Tuist.ClickHouseRepo`, tabele `test_runs`, `shard_plans`, `shard_runs`) ↔ LiveView dashboard (`server/lib/tuist_web/live/tests_live.ex`).

---

## KROK 1 — Ubiquitous Language

| Pojęcie | Definicja | Cytat źródłowy | Gdzie żyje w kodzie |
|---|---|---|---|
| **Test Run** | Pojedyncza egzekucja testów projektu, zapisywana jako wiersz encji ClickHouse. | `server/lib/tuist/tests/test.ex:3-4`: *"A test run represents a single test execution of a project. This is a ClickHouse entity that stores test run data."* | `server/lib/tuist/tests/test.ex:28` (`schema "test_runs"`), tworzony przez `Tuist.Tests.create_test/1` (`tests.ex:478`) |
| **Test Processing Mode** | Tryb decydujący, *gdzie* parsowany jest `.xcresult` i co trafia na serwer: `local` (CLI parsuje lokalnie), `remote` (serwer parsuje przez natywny NIF), `off` (brak uploadu). Domyślnie `remote` dla `*.tuist.dev`/`localhost`, `local` dla self-hosted. | `cli/Sources/TuistKit/Services/TestProcessingMode.swift:9-12`: *"Defaults to .remote for tuist-hosted instances and .local for self-hosted ones, so self-hosted servers keep parsing xcresults locally unless they explicitly opt in."* | `TestProcessingMode.swift:4-19` (enum + `default(for:)`, zweryfikowane bezpośrednio w tej sesji) |
| **Kwarantanna testu / Quarantined Test** | Test oznaczony po stronie serwera jako `muted` lub `skipped`; CLI pobiera tę listę przed uruchomieniem i traktuje niepowodzenia testów w kwarantannie jako niekrytyczne. | `test-service-analysis/research.md:50` (opis efektu round-tripu), zweryfikowane bezpośrednio: `cli/Sources/TuistKit/Services/TestQuarantineService.swift:8-20` (protokół `markQuarantinedTests`/`onlyQuarantinedTestsFailed`) | `TestQuarantineService.swift:23-86` (implementacja, zweryfikowana w tej sesji) |
| **`onlyQuarantinedTestsFailed`** | Predykat: run ma niepowodzenia I wszystkie niepowodzenia są w kwarantannie. | Nazwa i sygnatura wprost w kodzie | `TestQuarantineService.swift:56-61` i `:64-74` (dwie przeciążone implementacje, zweryfikowane w tej sesji); wywołanie decyzyjne `TestService.swift:1391` (zweryfikowane w tej sesji: `if testQuarantineService.onlyQuarantinedTestsFailed(...) { return true }` — połyka błąd) |
| **Shard / Shard Plan / Shard Run** | Podział zestawu testów na porcje wykonywane równolegle na wielu runnerach CI. `Shard Plan` to serwerowy plan (bin-packing wg historycznej analityki), `Shard Run` to raport pojedynczego shardu z powrotem do serwera. | `test-service-analysis/research.md:53`: *"serwer aktywnie steruje wykonaniem CLI (przydział shardów na podstawie historycznej analityki czasu trwania testów)"* | `server/lib/tuist/shards/shard_plan.ex:2-4` (*"A shard plan represents a test sharding plan for distributing tests across multiple CI runners. This is a ClickHouse entity."*, zweryfikowane w tej sesji), `shard_run.ex:1-16` (zweryfikowane w tej sesji), CLI: `cli/Sources/TuistKit/Services/Sharding/ShardPlanService.swift:104-195` (zweryfikowane w tej sesji) |
| **Shard Granularity** | Poziom, na którym dzielony jest plan shardu: `module` (domyślnie) albo `suite`. | `server/lib/tuist/shards/shard_plan.ex:15` (`field :granularity, ..., default: "module"`) i `:46` (`validate_inclusion(:granularity, ["module", "suite"])`) — zweryfikowane w tej sesji | jw. |
| **Selective Testing** | Osobna pętla cache: hash sukcesu testu per-target zapisywany do binary cache, nie do sklepu analityki. Pozwala pominąć niezmienione targety. | `test-service-analysis/research.md:62`: *"zapisują hash sukcesu testu per-target do cache storage (binary cache, nie do sklepu analityki testów)"* | `TestService.swift:1130-1160`, `:1653` wg research.md (nie zweryfikowane bezpośrednio w tej sesji — patrz KROK 4/Open Questions) |
| **Result Bundle (`.xcresult`)** | Natywny artefakt Xcode z wynikami testów; parsowany albo lokalnie (Swift), albo przez dedykowany serwerowy NIF na macOS. | `test-service-analysis/research.md:145`: *"tryb .local i .remote różnią się (...) gdzie faktycznie żyje parsowanie .xcresult — CLI (.local) vs. dedykowany serwerowy NIF na macOS (.remote)"* | `server/native/xcresult_nif/` (wg `AGENTS.md` root), `server/lib/tuist/tests/workers/process_xcresult_worker.ex` |
| **Test Case Run / Test Module Run / Test Suite Run** | Fan-out encji podrzędnych do `Test Run`: wynik pojedynczego przypadku testowego / modułu / suity. | `server/lib/tuist/tests/test.ex:59-60` (`has_many :test_case_runs`, `has_many :run_destinations`) — zweryfikowane w tej sesji | `test.ex:59` |
| **Flaky Test / `is_flaky`** | Test, który w obrębie jednego runu CI ma niespójny wynik między powtórzeniami; run jest oznaczany `is_flaky: true`, jeśli wykryto taki przypadek na CI. | `server/lib/tuist/tests.ex:504-512` (zweryfikowane w tej sesji: `has_flaky_tests and is_ci → Map.put(attrs, :is_flaky, true)`) | `test.ex:36` (`field :is_flaky, :boolean, default: false`) |
| **Status testu (enum zamknięty)** | Jeden z: `success`, `failure`, `skipped`, `in_progress`, `processing`, `failed_processing`. | `server/lib/tuist/tests/test.ex:106` (zweryfikowane w tej sesji: `validate_inclusion(:status, [...])`) | jw. — patrz też KROK 3, ograniczona egzekwowalność |
| **Build System** | Jeden z: `xcode`, `gradle`, `bazel` — `Test Run` jest z definicji schematu wieloplatformowy, nie tylko Xcode. | `test.ex:107` (zweryfikowane w tej sesji: `validate_inclusion(:build_system, ["xcode", "gradle", "bazel"])`) | jw. — patrz KROK 4, rozjazd z zakresem zbadanym w research.md |
| **Stale Run Window (6h)** | Okno czasowe, po którym run zawieszony w `in_progress` jest uznawany za porzucony i wymuszany na `failure`. | `server/lib/tuist/tests.ex:4395-4397` (zweryfikowane w tej sesji: *"How long a run is given to hear from every shard before it is presumed abandoned"*) | `tests.ex:150-152` (`@stale_run_window_hours 6`), `tests.ex:4404` (`expire_stale_in_progress_test_runs/0`) |
| **`TestExecutionOrchestrator`** (proponowana nazwa) | Docelowy, jeszcze nieistniejący typ mający przejąć wspólną logikę `TestService`/`XcodeBuildTestCommandService`. | `refactor-opportunities/research.md:92,153`: *"Wspólny TestExecutionOrchestrator (...) w TuistKit"* | **BRAK w kodzie** — to rekomendacja z badania refaktoru, nie istniejący byt |

---

## KROK 2 — Klasyfikacja subdomen: Core / Supporting / Generic

Kryterium: `README.md:22-30` wymienia 7 nazwanych "solutions" produktu — traktuję to jako najbliższy dostępny substytut sekcji "success criteria"/wizji (brak PRD, patrz KROK 0).

| Obszar | Kategoria | Uzasadnienie |
|---|---|---|
| **Sharding sterowany historyczną analityką** (`Tuist.Shards`, bin-packing wg czasu trwania testów) | **Core** | Nie jest wymieniony wprost w README, ale to unikalna logika decyzyjna serwera nad danymi historycznymi klienta ("Build insights", `README.md:28`) — to właśnie ten typ inteligencji ponad surowym `xcodebuild`, który stanowi przewagę ("actionable insights (...) to make informed decisions"). Zaimplementowane, nie deklaratywne — `server/lib/tuist/shards/bin_packer.ex`, `analytics.ex`. |
| **Kwarantanna testów** (mute/skip sterowane serwerowo) | **Core** | Bezpośrednio realizuje obietnicę "stay focused and productive" (`README.md:20`) — usuwa szum niestabilnych testów z pętli deweloperskiej. Logika biznesowa nietrywialna (`TestQuarantineService.swift`), nie prosta flaga. |
| **Selective testing (hash-based skip)** | **Core** | Wymienione wprost i osobno w README jako nazwana "solution": `README.md:26` — *"Run tests faster by selecting them based on the file changes."* |
| **Scalanie shardów w jeden logiczny Test Run** (`create_or_update_sharded_test`, KROK 3) | **Core** | To najbardziej złożona, autorska logika domenowa w całym obszarze (merge statusów, mapowanie plan→run, obsługa spóźnionych/zaginionych shardów) — nie da się kupić generycznie, bo zależy od modelu domeny Tuist. |
| **Test Run Analytics / dashboard** (`tests_live.ex`, agregaty czasu trwania) | **Core** | Wprost nazwane w README: "Build insights" (`:28`) — *"Get actionable insights from your projects, builds, and test runs to make informed decisions."* |
| **Parsowanie `.xcresult`** (lokalne i serwerowe NIF) | **Supporting** | Niezbędne, by dane w ogóle trafiły do warstwy Core (analytics/sharding), ale samo w sobie jest odwzorowaniem formatu Apple, nie różnicuje produktu — Apple mogłoby zmienić format i logika pozostałaby czysto techniczna. |
| **Upload artefaktów (multipart, blob storage)** | **Generic** | Standardowy wzorzec S3-multipart-upload — brak logiki domenowej Tuist; `AnalyticsArtifactUploadService.swift`, `MultipartUploadArtifactService`. |
| **Klient OpenAPI (`Components.Schemas.*`)** | **Generic** | Generowany mechanicznie z `server.yml` (`CLAUDE.md` zabrania ręcznej edycji) — czysta infrastruktura integracyjna. |
| **Wykrywanie środowiska CI** (`CIControlling`, GitHub/GitLab/CircleCI/Buildkite/Codemagic) | **Generic** | Rozpoznawanie znanych zmiennych środowiskowych dostawców CI — odtwarzalne przez dowolne narzędzie, zero unikalnej wiedzy domenowej Tuist. |
| **Wykonanie `xcodebuild`** | **Supporting** | Konieczne dla działania funkcji core, ale samo wywołanie narzędzia Apple nie jest przewagą Tuist — przewaga zaczyna się dopiero w tym, co Tuist robi z wynikiem (sharding, kwarantanna, analytics). |

---

## KROK 3 — Kandydaci na agregaty i ich niezmienniki

### Agregat 1: Sharded Test Run (scalony z wielu Shard Run)

**Niezmiennik:** status scalonego runu jest `success` tylko wtedy, gdy **wszystkie** shardy zaraportowały I żaden nie zawiódł terminalnie; **dowolny** shard z terminalnym statusem porażki (`failed_processing`/`failure`) natychmiast decyduje o statusie runu, bez czekania na brakujące shardy; w przeciwnym razie run pozostaje `in_progress`.

> *Cytat ze źródła (komentarz w kodzie, `server/lib/tuist/tests.ex:839-844`, zweryfikowane bezpośrednio w tej sesji):* "A shard whose report never reaches the server holds the merged run at `in_progress` until the six-hour reaper runs (...) A failure any shard reported is terminal, so it decides the merged run without waiting for the missing reports. Only success still needs every shard to have reported."

**Status egzekwowania:** **EGZEKWOWANY w kodzie**, dokładnie zgodnie z opisem: `tests.ex:845-852` (`merged_shard_status/3`), zweryfikowane bezpośrednio w tej sesji:
```
if reported_count >= expected_shard_count or Enum.any?(latest_statuses, &(&1 in @terminal_shard_failure_statuses)) do
  compute_final_shard_status(latest_statuses)
else
  "in_progress"
end
```
Domknięcie cyklu życia: run zawieszony w `in_progress` dłużej niż `@stale_run_window_hours` (6h, `tests.ex:151-152`) jest wymuszany na `failure` przez `expire_stale_in_progress_test_runs/0` (`tests.ex:4404-4452`, zweryfikowane bezpośrednio) — bez tego mechanizmu niezmiennik "run zawsze osiąga stan terminalny" byłby złamany dla zaginionych shardów.

**Drugi niezmiennik tego agregatu — mapowanie plan→run jest jednoznaczne:** *"`shard_runs` is the only authority on which run a plan's shards report into"* (`tests.ex:618-621`, zweryfikowane w tej sesji). Pierwszy zaraportowany shard "rezerwuje" mapowanie (`mapped_shard_test_run_id`, `tests.ex:766-770`) zanim wiersz `Test` w ogóle istnieje — świadoma decyzja przeciw race condition przy współbieżnym raportowaniu wielu shardów (`tests.ex:619-621`: *"a report that dies in between leaves a pointer the next shard rebuilds through, rather than a run no later shard can find"*).

### Agregat 2: Test Run — walidacja statusu

**Niezmiennik deklarowany:** `status` musi być jednym z 6 dozwolonych wartości (`test.ex:106`).

**Status egzekwowania: CZĘŚCIOWO IGNOROWANY.** Walidacja żyje wyłącznie w `Test.create_changeset/2` (`test.ex:65-109`). Ścieżka tworzenia nowego, niesharded runu (`create_new_test`, `tests.ex:514-516`) przechodzi przez ten changeset — **egzekwowana**. Ale ścieżka scalania shardów (`tests.ex:721-727`, zweryfikowane bezpośrednio w tej sesji) buduje `update_attrs` jako gołą mapę i wywołuje `IngestRepo.insert_all(Test, [update_attrs])` — `insert_all` **omija changeset całkowicie**. Ten sam wzorzec powtarza się w `expire_stale_in_progress_test_runs/0` (`tests.ex:4444-4452`) — status `"failure"` jest wstawiany wprost przez `insert_all`, też bez przejścia przez walidację. Faktyczna gwarancja "status zawsze należy do zbioru 6 wartości" trzyma się wyłącznie dyscypliny programisty w tych dwóch miejscach, nie typu ani bazy danych (ClickHouse nie ma CHECK constraints).

### Agregat 3: Kwarantanna — kontynuacja runu

**Niezmiennik:** niepowodzenie schematu testowego jest "połykane" (build/test kontynuuje) wtedy i tylko wtedy, gdy WSZYSTKIE nieudane testy są w kwarantannie.

**Status egzekwowania:** deklarowany i egzekwowany w kodzie produkcyjnym (`TestService.swift:1391-1393`, zweryfikowane bezpośrednio w tej sesji — patrz KROK 1), ale **niezweryfikowany przez żaden test** — ustalenie z `test-service-analysis/research.md:160` (zweryfikowane tam przez ast-grep: mock `onlyQuarantinedTestsFailed` zwraca `false` we wszystkich 5 miejscach pliku testowego, linie 160-164, 4115, 4217, 4471). To najostrzejszy przypadek w tym obszarze domeny: **kod egzekwuje niezmiennik, ale nic nie chroni go przed regresją.**

### Agregat 4: Shard Plan — granularność

**Niezmiennik:** `granularity` ∈ {`module`, `suite`}.

**Status egzekwowania:** egzekwowany przez `Ecto.Changeset.validate_inclusion` w `ShardPlan.create_changeset/2` (`shard_plan.ex:27-47`, zweryfikowane bezpośrednio w tej sesji) — **jedyna** ścieżka tworzenia `ShardPlan` w kodzie zweryfikowanym w tej sesji przechodzi przez ten changeset (w przeciwieństwie do Agregatu 2, nie znaleziono tu odpowiednika `insert_all` omijającego walidację — ale nie przeszukano całego `shards.ex` w tej sesji, patrz Ograniczenia).

---

## KROK 4 — Rozjazdy MODEL vs KOD

| # | Dokument mówi (MODEL) | Kod robi (KOD) | Dowód |
|---|---|---|---|
| 1 | `refactor-opportunities/research.md:218,268` zostawia jako **Open Question**: *"Czy server/lib/tuist/shards/shard_plan.ex/shard_run.ex zapisują do Postgresa czy ClickHouse — nierozstrzygnięte"* | Kod jednoznacznie odpowiada: **ClickHouse**, wprost udokumentowane w `@moduledoc` obu plików. | `shard_plan.ex:2-5`: *"This is a ClickHouse entity."*; `shard_run.ex` używa tych samych typów `Ch` co `test.ex` (potwierdzone `Test`, ClickHouse). Zweryfikowane bezpośrednio w tej sesji. |
| 2 | `test-service-analysis/research.md` (cały dokument, Feature overview §1-12) opisuje `tuist test`/`TestService.swift` jako pełny obraz tego, jak powstaje `Test Run` — analiza nie wspomina żadnej ścieżki poza Xcode. | `Tuist.Tests.create_test/1` (ten sam agregat, ten sam `test_runs`) ma **drugiego, niezależnego producenta**: `Tuist.Bazel.TestReportIngestor.ingest/4` (`server/lib/tuist/bazel/test_report_ingestor.ex:37`, zweryfikowane bezpośrednio w tej sesji: `Tests.create_test(attributes)`). Schemat `Test` już przewiduje to wprost — `build_system` ∈ {`xcode`,`gradle`,`bazel`} (`test.ex:107`) i osobne FK `gradle_build_id`/`bazel_invocation_id` (`test.ex:44-45`). | `test_report_ingestor.ex:1,37`; `test.ex:44-45,107`. Zweryfikowane bezpośrednio w tej sesji. |
| 3 | README (`:28`) nazywa "Build insights" jako **jedną** cechę produktu, obejmującą projekty/buildy/testy. | Kod modeluje `Test Run` i `Build Run` jako **odrębne agregaty** w odrębnych tabelach ClickHouse (`test_runs` vs. tabela buildów w `Tuist.Builds`), połączone wyłącznie opcjonalnym FK `build_run_id` (`test.ex:43,56` — `Nullable(UUID)`, `belongs_to :build_run`). Nie ma wspólnego "Insights" agregatu w kodzie — to etykieta marketingowa nad dwoma niezależnymi bounded contextami. | `test.ex:43,56`. Zweryfikowane bezpośrednio w tej sesji (istnienie osobnego `Tuist.Builds` potwierdzone przez `Mimic.copy(Tuist.Builds)` w `server/test/test_helper.exs`, oraz `belongs_to` w schemacie). |
| 4 | `refactor-opportunities/research.md:87` twierdzi: *"4 mechanizmy domenowe (kwarantanna, plan shardu, wykonanie shardu, upload) są już izolowane za nazwanymi protokołami"* — sugeruje czystą separację pojęć po stronie CLI. | Prawdziwe dla strony CLI (protokoły `TestQuarantineServicing`/`ShardPlanServicing`/`ShardServicing`/`UploadResultBundleServicing`), ale po stronie serwera te same pojęcia (kwarantanna i sharding) **nie mają żadnej wspólnej abstrakcji** — potwierdzone przez sam dokument źródłowy (`refactor-opportunities/research.md:74`: *"Zero wspólnego protokołu/typu bazowego"*). To nie jest sprzeczność między dokumentami a kodem, ale rozjazd między **poziomem** separacji: CLI ma czyste szwy interfejsowe, serwer ma tylko organizacyjną bliskość plików (`shards.ex` obok `tests.ex`) bez typu wyrażającego wspólne pojęcie "pre-run server round-trip". | `refactor-opportunities/research.md:74,87` (cytaty z dokumentu źródłowego, tam już ast-grep-zweryfikowane). |

---

## KROK 5 — Ranking refaktoru

Kryterium: wartość = jak rdzeniowy (Core, KROK 2) jest niezmiennik chroniony/naruszony; ryzyko = jak słabo jest dziś egzekwowany (KROK 3) lub jak duży jest rozjazd wiedzy (KROK 4).

### #1 do refaktoru: domknięcie osłony testowej niezmiennika kwarantanny (Agregat 3)

**Dlaczego #1:** to jedyny przypadek w tym obszarze, gdzie niezmiennik jest jednocześnie (a) **Core** — kwarantanna to nazwana wprost przewaga produktu (KROK 2), (b) **poprawnie zaimplementowany** (`TestService.swift:1391-1393`), ale (c) **zerowo chroniony** — wszystkie 5 miejsc testowych w pliku 7002-liniowym stubują dokładnie tę gałąź na stałą `false` (`test-service-analysis/research.md:160`, ast-grep-zweryfikowane tam). Regresja tej logiki (np. przy okazji refaktoru Kandydata A z `refactor-opportunities/research.md`) przeszłaby przez CI niezauważona — a to nie jest hipotetyczne ryzyko, tylko literalnie pierwszy krok-prerekwyzyt, który samo badanie refaktoru już zidentyfikowało jako blokujący (`refactor-opportunities/research.md:93,160-164`: *"Domknąć luki testowe (...) kontynuacja kwarantanny=true (...) przed jakąkolwiek ekstrakcją"*).

**Nie jest to nowe odkrycie tej destylacji** — jest to potwierdzenie z zupełnie innej strony (analiza pojęć domenowych vs. analiza długu technicznego) tego samego wniosku: ten sam niezmiennik wypada na szczyt obu rankingów, co wzmacnia pewność, że to właściwy priorytet.

### #2 do refaktoru: egzekwowanie statusu `Test Run` na ścieżce scalania shardów (Agregat 2)

**Dlaczego #2:** wyższa wartość rdzeniowa niż ranking Kandydata C z `refactor-opportunities/research.md` (tam: zamknięcie jednego wycieku typu OpenAPI) — bo dotyczy integralności **centralnej encji** całej domeny (`Test Run`, status widoczny bezpośrednio na dashboardzie), nie efektu ubocznego jednej metody pomocniczej. Ryzyko jest realne, choć węższe niż #1: `insert_all` omijający `Test.create_changeset` (`tests.ex:721-727`, `:4444-4452`) oznacza, że literówka lub nowa wartość statusu wprowadzona w logice scalania (`merged_shard_status/3`, `compute_final_shard_status/1`) trafi do ClickHouse bez żadnej walidacji — a ClickHouse sam w sobie nie ma CHECK constraints, więc nie ma żadnej drugiej linii obrony. Naprawa (przepuszczenie `update_attrs` przez zmieniony `Test.create_changeset`, albo wydzielenie osobnej, świadomie węższej walidacji dla ścieżki update) jest lokalna i nisko-ryzykowna względem #1 (nie wymaga zmiany zachowania biznesowego, tylko dodania bramki).

### #3 do refaktoru: zbadanie ścieżki Bazel jako drugiego producenta agregatu `Test Run` (KROK 4, #2)

**Dlaczego #3:** to nie jest błąd do naprawienia, tylko **luka wiedzy** o realnym ryzyku — istniejące badania (`test-service-analysis/research.md`, `refactor-opportunities/research.md`) w ogóle nie objęły `Tuist.Bazel.TestReportIngestor`. Nie wiadomo, czy ta ścieżka respektuje te same niezmienniki (np. czy Bazel-owe testy mogą w ogóle trafić do kwarantanny/shardingu, czy status z tej ścieżki też pomija changeset tak jak ścieżka #2). Rekomendacja: rozszerzyć zakres kolejnego badania (`research.md`) o `server/lib/tuist/bazel/test_report_ingestor.ex`, zanim jakikolwiek refaktor Agregatu 1/2 założy, że jedynym producentem `Test Run` jest `tuist test`.

---

## Ograniczenia tej destylacji

- **Brak PRD/wizji produktu** — klasyfikacja Core/Supporting/Generic (KROK 2) oparta jest na README (marketing/pozycjonowanie), nie na formalnych success criteria. To słabszy grunt niż PRD i powinno być zweryfikowane z kimś odpowiedzialnym za produkt, jeśli decyzje mają się na tym opierać.
- **Zakres celowo zawężony** do `tuist test`/analityki testów — nie jest to destylacja całej domeny Tuist (generowanie projektów, cache binarny, registry, previews pozostają poza zakresem tego dokumentu).
- **Selective testing** (KROK 1) nie zostało zweryfikowane bezpośrednio w tej sesji — cytat pochodzi z `test-service-analysis/research.md`, które samo odnotowuje to jako Open Question (dokładne miejsce odczytu hasha nie zlokalizowane).
- **`shards.ex` (866 linii) nie zostało przeczytane w całości** w tej sesji — czytano wyłącznie `shard_plan.ex`, `shard_run.ex` i fragmenty `tests.ex` istotne dla wykrytych niezmienników. Możliwe, że istnieją dodatkowe niezmienniki lub więcej przypadków omijania walidacji, których ta destylacja nie wychwyciła.
- **`Tuist.Bazel.TestReportIngestor` i `Tuist.Gradle`** zostały wykryte grepem jako istniejące, ale nie przeanalizowane w głębi (patrz KROK 5 #3) — to świadomie zostawiona luka, nie przeoczenie.
- Wszystkie liczby/twierdzenia strukturalne oznaczone jako pochodzące z `research.md` były tam niezależnie zweryfikowane przez `ast-grep` (dwukrotnie, na dwóch różnych commitach) — traktowane tu jako wiarygodne źródło wtórne, nie zweryfikowane ponownie w tej sesji, chyba że jawnie oznaczono "zweryfikowane bezpośrednio w tej sesji".
