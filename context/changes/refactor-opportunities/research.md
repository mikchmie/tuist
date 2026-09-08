---
date: 2026-09-08T09:07:43+02:00
researcher: Mikołaj Chmielewski
git_commit: 7d0e3f0341f3f93b78f1a06b66c82498bcf18f90
branch: 10x-devs
repository: tuist
topic: "Refactor opportunities z analizy TestService (dług techniczny → priorytety)"
tags: [research, codebase, cli, testservice, technical-debt, refactor-opportunities]
status: complete
last_updated: 2026-09-08
last_updated_by: Mikołaj Chmielewski
---

# Research: Refactor opportunities z analizy TestService

**Date**: 2026-09-08T09:07:43+02:00
**Researcher**: Mikołaj Chmielewski
**Git Commit**: 7d0e3f0341f3f93b78f1a06b66c82498bcf18f90
**Branch**: 10x-devs
**Repository**: tuist

## Research Question

> Priorytetowa analiza: mamy `context/changes/test-service-analysis/research.md` — zapis długu technicznego i ryzyk strukturalnych `TestService.swift`. Ta zmiana odpowiada na pytanie, które tamta analiza celowo zostawiła otwarte: **które z tych problemów warto naprawić, w jakim docelowym kształcie i w jakiej kolejności.**
>
> Metoda: wypisać każdy problem z raportu niezależnie od etykiety, sklasyfikować (KANDYDAT = naprawa zmieniłaby strukturę kodu; wszystko inne = wejście do oceny wykonalności), zbadać każdego kandydata trzema osiami (obecny kształt / historia i intencjonalność / wykonalność migracji), i zamknąć rankingiem 2-3 najmocniejszych opcji z trade-offami. Wyłącznie eksploracja — zero zmian w kodzie, zero decyzji.

## Summary

Z 14 problemów odnotowanych w `test-service-analysis/research.md` (dowolna etykieta: dług, ryzyko, luka, martwy kod) **3 kwalifikują się jako KANDYDACI** — ich naprawa zmieniłaby strukturę kodu produkcyjnego. Pozostałe 11 to luki w testach lub niezweryfikowana wiedza (magazyn danych shardingu) — wejście do oceny kosztu, nie samodzielne refaktoryzacje.

Wszystkie 3 kandydaty zostały zbadane trzema niezależnymi agentami (obecny kształt / historia / wykonalność) i **wszystkie 3 trafiają do rankingu** poniżej — żaden nie został odrzucony na etapie badania, różnią się tylko dźwignią i kolejnością.

Najważniejsze ustalenie zmieniające obraz z pierwotnego raportu: duplikat `XcodeBuildTestCommandService.swift` **nie jest przypadkową kopią `TestService.swift`** — to świadomie wydzielona, osobna komenda (`tuist xcodebuild test`) dla projektów Xcode *niegenerowanych* przez Tuist, rozdzielona od `tuist test` z konkretnego powodu (brak grafu Tuist do przejścia). Przypadkowa jest **duplikacja logiki między nimi** (15 z 16 identycznych zależności, całe metody skopiowane), nie sam fakt istnienia dwóch komend.

## Klasyfikacja problemów (audyt)

| # | Problem (z raportu) | Klasyfikacja | Uzasadnienie |
|---|---|---|---|
| 1 | `onlyQuarantinedTestsFailed` — mock zawsze `false`, kontynuacja kwarantanny nieprzetestowana | Nie-kandydat | Luka testowa, nie struktura produkcyjna |
| 2 | `.remote` upload (`uploadResultBundle`) nieprzetestowany | Nie-kandydat | Luka testowa |
| 3 | Wszystkie ścieżki błędów uploadu nieprzetestowane | Nie-kandydat | Luka testowa |
| 4 | `schemeWithoutTestableTargets`/`unspecifiedPlatform` throws nieprzetestowane integracyjnie | Nie-kandydat | Luka testowa |
| 5 | `resolveTestProductsPath` fallback nieprzetestowany | Nie-kandydat | Luka testowa |
| 6 | `generateOnly` nigdy nie wywołane z `true` | Nie-kandydat | Luka testowa (ew. martwa ścieżka produkcyjna — otwarte pytanie z pierwotnego raportu, nierozstrzygnięte) |
| 7 | Testy jako wyłącznie "wiring tests" (24 mocki) | Nie-kandydat | Konsekwencja rozmiaru god-service (→ Kandydat A), nie osobna naprawa strukturalna |
| 8 | Niezweryfikowany magazyn stanu shardingu (Postgres/ClickHouse) | Nie-kandydat | Luka wiedzy, wejście do oceny kosztu Kandydata A (facet sharding) |
| 9 | **`XcodeBuildTestCommandService.swift` jako niekontrolowany duplikat** | **KANDYDAT A** | Naprawa (wspólny orkiestrator) zmienia strukturę dwóch plików |
| 10 | **God-service — 2322 linie, 27 zależności, bus factor 1** | **KANDYDAT A** | Ta sama oś naprawy co #9 — jeden zbieżny target shape |
| 11 | **Brak wspólnej abstrakcji "pre-run server round-trip" (kwarantanna + sharding)** | **KANDYDAT A** | Ta sama oś naprawy co #9 — raport łączy to wprost z #9 ("przy okazji punktu 2") |
| 12 | **Martwy kod** — 5 nieosiągalnych metod + `passedValue` zduplikowane w 4 plikach | **KANDYDAT B** | Usunięcie/dedup zmienia strukturę pliku (nawet jeśli mechaniczne) |
| 13 | **Bezpośrednia konstrukcja `Components.Schemas.ShardPlan`** (`TestService.swift:1479`) | **KANDYDAT C** | Zamknięcie szwu wymaga nowej metody na protokole serwisowym — zmiana struktury |
| 14 | Diament `XcodeGraph`/mapper (z `repo-map.md`, poza zakresem TestService) | Poza zakresem | Nie dotyczy `TestService.swift`; nie badane w tej zmianie |

Kandydaci #9/#10/#11 są zbieżne (ten sam fix rozwiązuje wszystkie trzy) — poniżej traktowane łącznie jako **Kandydat A**.

---

## Kandydat A: TestService.swift jako god-service z niekontrolowanym duplikatem

### Obecny kształt (z dowodami)

`TestService.swift` to pojedynczy `public struct TestService` (`TestService.swift:107`, evidence) — jeden typ, jeden plik, brak `extension TestService` gdziekolwiek indziej w repo (zweryfikowane grepem repo-wide, evidence). 27 wstrzykiwanych zależności (`TestService.swift:108-134`, evidence, dokładnie 27 `private let`). `run()` (od linii 219) rozciąga się na: walidację parametrów, ładowanie configu, pobranie kwarantanny, dispatch shardów, generowanie grafu (349-368), rozwiązanie schematu (405-492), wykonanie testów (523-548), zapis bundla (560-570), zapis grafu selective-testing i planu shardów (572-600+) — evidence, jeden `run()` obejmuje walidację, I/O sieciowe, generowanie projektu, sharding, wykonanie i upload.

`XcodeBuildTestCommandService.swift` (494 linie) — osobny `struct` w tym samym module (`TuistKit`), 16 wstrzykiwanych zależności (`:23-38`, evidence). **15 z tych 16 (93.75% ≈ 94%) ma odpowiednik w 27 zależnościach `TestService`** — potwierdzone diffem nazw (evidence, jedyny wyjątek: `uniqueIDGenerator`, `:27`). To nie tylko wspólne typy — duplikacja obejmuje całe metody:
- `captureTestRunReport`: `TestService.swift:1975-1983` vs `:453-461` — ciała identyczne co do linii (evidence).
- `passedValue`: `TestService.swift:2170-2175` vs `:351-358` — identyczne 5 linii (evidence).
- `uploadResultBundleIfNeeded`: `TestService.swift:2015-2070` vs `:395-448` — ten sam trójstanowy `switch mode`, ten sam wzorzec `RunMetadataStorage`/alert (evidence, drobna rozbieżność: `TestService` ma dodatkowy guard `action != .build`).
- `processBuildRun`/`uploadBuildRunIfNeeded`: `:265-290` vs `TestService.swift:1985-2013` — te same wywołania `xcActivityLogController`/`uploadBuildRunService` (evidence).
- `loadQuarantinedTests` (`:463-493`) vs `fetchQuarantinedTests` (`TestService.swift:617-649`) — strukturalnie identyczne implementacje: ten sam `async let muted/skipped`, ten sam komunikat logu, ten sam catch-i-ostrzeż wzorzec (evidence).

**Brak wspólnej abstrakcji "pre-run server round-trip":** `fetchQuarantinedTests` zależy od `testCaseListService: TestCaseListServicing`; `ShardPlanService.plan(...)` zależy od zupełnie innego zestawu serwisów. Zero wspólnego protokołu/typu bazowego (evidence, grep po `Planning`/`PreRun`/`Prefetch` w `cli/Sources/TuistKit` — brak wyników).

### Werdykt intencjonalności

**Mieszany, rozłożony na trzy warstwy tego samego problemu:**

- **Sam podział `TestService`/`XcodeBuildTestCommandService` — świadome ograniczenie.** `XcodeBuildTestCommandService` (jako `XcodeBuildService.swift`) powstał 2025-02-10 (`003a46065c`, #7287) — **ponad 4 lata po** `TestService.swift` (2020-10-26, `c3de526717`). Commit jawnie tłumaczy cel: nowa komenda (`tuist xcodebuild`) dla projektów Xcode **niegenerowanych** przez Tuist — brak grafu do przejścia, inny przypadek użycia niż `tuist test`. To nie kopiuj-wklej `TestService.swift`, to równoległa komenda zbudowana z realnego powodu. 2025-04-22 (`54c4e85885`, #7516) nastąpił świadomy podział wg czasownika xcodebuild (`Build`/`Test`/`Archive`/`BuildForTesting`) — stąd współdzielone helpery między `XcodeBuildBuildCommandService` i `XcodeBuildTestCommandService` (wspólny rodowód, nie niezależne kopiowanie).
- **Duplikacja logiki MIĘDZY bliźniakami — przypadkowa złożoność.** Brak jakiegokolwiek komentarza uzasadniającego duplikację (evidence, grep po `duplicat|shared|why.*separate|intentional` — zero trafień w obu plikach). `cli/AGENTS.md` nazywa dziś `TuistKit` "legacy — unikać nowego kodu", ale ten wpis dodano 2026-01-22 (`4812545d10`), pięć lat po `TestService.swift` i ~11 miesięcy po podziale `XcodeBuild*` — to retrospektywne uznanie stanu, nie dowód pierwotnej intencji.
- **Rozmiar god-service — przypadkowa złożoność.** 174 commity dotykające `TestService.swift` (`git log --follow`), potwierdzone niezależnie przez `repo-map.md` (73 zmiany/12 mies., najgorętszy plik CLI). Sharding dodany jako jedna skoncentrowana funkcja (`212bec212a`, 2026-03-23, #9796), po czym nastąpił **5-miesięczny ogon** ~15+ commitów naprawczych (błędy destination, referencji shardu, granularności). Brak jakiegokolwiek commita, który świadomie wydzieliłby odpowiedzialności z tego pliku poza niekompletnym cleanupem opisanym w Kandydacie B.
- **Brak wspólnej abstrakcji kwarantanna/sharding — przypadkowa złożoność.** `TestQuarantineService.swift` (2026-03-24, `c65de1b73f`, #9978) i `ShardPlanService.swift`/`ShardService.swift` (2026-03-23, `212bec212a`, #9796) powstały **jeden dzień od siebie, ten sam autor** (Marek Fořt). Zero wzajemnych referencji w kodzie (evidence, grep `quarantine`/`shard` krzyżowo — zero trafień). Wspólna abstrakcja była realna do rozważenia, ale nic na to nie wskazuje, że ktokolwiek próbował.

### Notatki o wykonalności

To jest ekstrakcja strukturalna, **nie** przeprojektowanie pojęć biznesowych — potwierdzone: 4 mechanizmy domenowe (kwarantanna, plan shardu, wykonanie shardu, upload) są już izolowane za nazwanymi protokołami (`TestQuarantineServicing`, `ShardPlanServicing`, `ShardServicing`, `UploadResultBundleServicing`); problemem nie jest niejasność pojęć, tylko dwie niezależne kopie tej samej sekwencji wywołań.

- **Istniejąca vs. nowa abstrakcja:** Brak kontenera DI — oba structy używają zwykłej iniekcji przez konstruktor z domyślnymi parametrami (evidence, `TestService.swift:149-177`, `XcodeBuildTestCommandService.swift:40-74`) — mechanicznie łatwe do współdzielenia, bo nowy typ orkiestratora może użyć dokładnie tego samego wzorca. 15 z 16 potrzebnych protokołów już istnieje i nie wymaga przeprojektowania; nowy jest tylko sam typ orkiestratora i jego sekwencja wywołań.
- **Asymetria osłon testowych — kluczowe ryzyko migracji:** `TestServiceTests.swift` ma 7002 linie, >150 testów. `XcodeBuildTestCommandServiceTests.swift` ma **tylko 8 testów na 573 liniach** (evidence). W tych 8: kontynuacja kwarantanny nigdy nie jest asertowana jako `true`, sharding ma dokładnie 1 test (tylko przekazywanie argumentu), `.remote`-mode upload nigdy nie jest weryfikowany jako wywołany. **Te same 3 luki co w pierwotnym raporcie dla `TestService`, ale z dużo cieńszą siecią bezpieczeństwa.**
- **CI:** `cli/Tests/TuistAutomationAcceptanceTests/TestAcceptanceTests.swift` (452 linie) ma **prawdziwy round-trip shardingu wobec żywego serwera** (`shard_with_remote_test_products`, `shard_with_local_test_products`, `:337-452`) — realna osłona wiring dla strony `TestService`. **Zero** takiej osłony dla `XcodeBuildTestCommandService` — brak jakiegokolwiek testu akceptacyjnego.
- **Target shape (nazwa, bez projektowania w głąb):** Wspólny `TestExecutionOrchestrator` (lub podobnie nazwany typ wewnętrzny w `TuistKit`) przejmujący 15 wspólnych kolaboratorów i sekwencję post-xcodebuild (parsuj → oznacz kwarantannę → uploaduj → sprawdź kontynuację).
- **Pierwszy krok-prerekwizyt:** Domknąć luki testowe `XcodeBuildTestCommandServiceTests.swift` (kontynuacja kwarantanny=true, weryfikacja `.remote` upload, pełny cykl shardu) **przed** jakąkolwiek ekstrakcją — inaczej refaktor nie ma detektora regresji po stronie bliźniaka. To czysto dopisanie testów, zero zmian produkcyjnych, może wysłać się osobno i natychmiast. Drugim, niezależnym najmniejszym krokiem jest wydzielenie wyłącznie wzorca "pre-run server round-trip" dla kwarantanny+shardingu (dotyka tylko `fetchQuarantinedTests`/`loadQuarantinedTests`) — nie blokuje ani nie jest blokowane przez większą unifikację uploadu/kontynuacji, może iść jako osobny PR w dowolnej kolejności.

---

## Kandydat B: Klaster martwego kodu

### Obecny kształt (z dowodami)

`TestService.swift:2239-2309` — `xcodebuildDestination` (2239-2265), `simulatorPlatform` (2267-2270), `xcodebuildPlatform` (2272-2287), `hasConcreteDevice` (2289-2292), `xcodebuildDestinationParameter` (2294-2309) — evidence, linie zgodne z pierwotnym raportem, brak dryfu. Grep repo-wide: `xcodebuildDestination`, `simulatorPlatform`, `hasConcreteDevice` mają **zero** wywołań gdziekolwiek (evidence). `xcodebuildPlatform` ma jedno wywołanie — z wnętrza martwego `simulatorPlatform` (evidence). `xcodebuildDestinationParameter` ma dwa wywołania — oba z wnętrza martwego klastra (evidence). Cały klaster jest tranzytywnie nieosiągalny z `run()`.

`passedValue` — 4 identyczne kopie: `TestService.swift:2170`, `XcodeBuildBuildCommandService.swift:289`, `XcodeBuildTestCommandService.swift:351`, `cli/Sources/TuistAutomation/XcodeBuild/XcodeBuildArgumentParser.swift:48` (evidence, ciała identyczne). Czwarta kopia żyje w **innym module** (`TuistAutomation`, nie `TuistKit`) — evidence, `Package.swift:1318-1372` potwierdza `TuistKit` zależy od `TuistAutomation` (kierunek jednostronny).

### Werdykt intencjonalności

**Przypadkowa złożoność — potwierdzony niekompletny cleanup, nie spekulacyjny martwy kod.**

Klaster (`xcodebuildDestination` i in.) powstał **razem z żywymi wywołującymi** w `e9ada0dbbe` (2026-06-15, #11216) — nie był spekulacyjny. `a99aab2244` (2026-07-01, #11581, "plan suite shards from server-side history instead of booting every test bundle") **usunął łańcuch wywołań** (`shardPlanDestination` i pośrednie), ale **nie usunął** pięciu funkcji liściastych, które ten łańcuch wyłącznie zasilał — evidence z `git log -S`/`git show`. Klasyczny niekompletny cleanup: architektura się zmieniła (nie trzeba już rozwiązywać konkretnego simulator destination), ale pomocnicze funkcje zostały.

`passedValue`: chronologia (`git log -S`) pokazuje, że 3 z 4 kopii mają wspólny rodowód z podziału komend `XcodeBuild*` (2025-02 → 2025-04, evidence). Czwarta, w `TestService.swift`, powstała **13 miesięcy później** (2026-03-24, `847a45f8bc`, #9986) jako niezależna, zbieżna kopia-wklej tego samego 5-liniowego idiomu — mimo że `TestService.swift` **już importuje `TuistAutomation`**, gdzie istniejąca implementacja była dostępna do reużycia (evidence). Brak komentarza/uzasadnienia dla utrzymania osobnej kopii.

### Notatki o wykonalności

**Bardzo niski koszt/ryzyko, potwierdzone.**

- Usunięcie 5-metodowego klastra: zero-ryzykowna operacja mechaniczna — potwierdzone ponownie grepem (zero callerów zewnętrznych, wszystkie metody `private`, więc strukturalnie niedostępne spoza `TestService.swift` niezależnie od granic modułów; `app/`/`android/` to odrębne ekosystemy niepodłączone do tego `Package.swift`).
- Dedup `passedValue`: nie wymaga nowego targetu. `TuistKit` zależy od `TuistAutomation`, oba zależą od `TuistSupport` (fan-in 38 wg `repo-map.md`, potwierdzone też w `Package.swift:1339`/`:1480`) — naturalne miejsce na jedną wspólną implementację. `TuistSupport` obecnie nie ma odpowiednika (evidence, grep brak wyników).
- **Pierwszy krok-prerekwizyt:** Usunąć klaster 5 metod + nieużywaną kopię `passedValue` w `TestService.swift` jednym mechanicznym PR-em (bramkowanym tylko przez `cli-lint`/`cli-unit-tests` przechodzące kompilacją). Dedup pozostałych 3 kopii `passedValue` do `TuistSupport` to osobny, mały follow-up. Oba kroki niezależne od Kandydata A i C, mogą wysłać się natychmiast.

---

## Kandydat C: Bezpośrednia konstrukcja `Components.Schemas.ShardPlan` (wyjątek od czystej granicy OpenAPI)

### Obecny kształt (z dowodami)

`TestService.swift:1476-1488` (`outputEmptyShardMatrixIfNeeded`) — evidence, jedyne miejsce w pliku, gdzie konstruowany jest bezpośrednio wygenerowany typ `Components.Schemas.*`/`Operations.*` (potwierdzone grepem — dokładnie 1 trafienie, `:1479`, zgodne z pierwotnym raportem, brak dryfu linii). Metoda buduje placeholder: `Components.Schemas.ShardPlan(id: "", reference: "", shard_count: 0, shards: [], upload_url: "")`.

Ważne doprecyzowanie względem pierwotnego raportu: **protokoły serwisowe w tej warstwie same są już zbudowane na surowym typie generowanym.** `ShardMatrixOutputServicing.output(_ shardPlan: Components.Schemas.ShardPlan)` (`ShardMatrixOutputService.swift:11-13`) i `ShardPlanServicing.plan(...) -> Components.Schemas.ShardPlan` (`ShardPlanService.swift:17-33`) — evidence. To nie jest odosobniony wyciek do skądinąd czystej abstrakcji; to szew, który od początku nie miał wejścia nie-generowanego dla przypadku "brak planu do zwrócenia".

### Werdykt intencjonalności

**Mieszany, z przechyłem w stronę przypadkowej złożoności w warstwie implementacji** — zachowanie uzasadnione, forma niedokumentowana i krucha.

Konstrukcja powstała jako bugfix (`336c2775a5`, 2026-04-08, #10205) łatający lukę, gdzie selective testing pomijające wszystkie testy zostawiało downstream konsumenta bez artefaktu. **Następnego dnia** (`817a632ac5`, 2026-04-09, #10220) trzeba było wydzielić helper i dodać go do dwóch pominiętych wcześniej miejsc — pierwszy fix był niekompletny. `4d03d52ab3` (2026-06-19, #11360) musiał dopisać pole `upload_url: ""`, gdy serwerowy schemat zyskał wymagane pole — bezpośredni dowód, że ręczna konstrukcja tworzy ciągły koszt utrzymania przy każdej zmianie schematu OpenAPI. `d353b74416` (2026-09-04, #12866) dodał kolejne miejsce wywołania plus komentarz tłumaczący **cel** (sentinel "brak joba testowego"), ale nie tłumaczący, **czemu** ominięto szew serwisowy. Cztery łatki w 5 miesięcy, brak języka "temp"/"TODO" w żadnym commicie — to nie porzucony placeholder, to nikt nie cofnął się po 2. czy 3. łatce, żeby wprowadzić właściwą fabrykę.

### Notatki o wykonalności

Mały, w pełni samodzielny fix, **niezależny od Kandydata A** (`XcodeBuildTestCommandService` nigdy nie referencjonuje `ShardMatrixOutputServicing` — evidence).

- Zamknięcie szwu: dodać drugą metodę do `ShardMatrixOutputServicing`/`ShardMatrixOutputService` (np. `outputEmpty()`), budującą placeholder wewnętrznie; `TestService.outputEmptyShardMatrixIfNeeded` wywołuje ją zamiast konstruować typ ręcznie. Protokół jest `public`, ale konsumowany wyłącznie wewnątrz `TuistKit` dziś (evidence, grep — tylko `TestService.swift` i `ShardPlanService.swift` go referencjonują) — poszerzenie powierzchni o jedną metodę niesie znikome ryzyko kompatybilności w obrębie repo.
- **Osłona testowa lepsza niż sugerował pierwotny raport:** 4 dedykowane testy (`TestServiceTests.swift:1261,1265,1269,1277`) asertują `shard_count == 0 && shards.isEmpty` na wywołaniu `shardMatrixOutputService.output(...)` — evidence. Testy sprawdzają kształt wyniku, nie sposób konstrukcji, więc przejdą niezmienione po refaktorze — realny detektor regresji już istnieje.
- **Pierwszy krok-prerekwizyt:** Dodać nową metodę do `ShardMatrixOutputServicing` + przełączyć jedno miejsce wywołania w `TestService.swift`. Jeden mały, samodzielny PR, dobrze pokryty istniejącymi testami. Może wysłać się przed, po lub równolegle z Kandydatem A/B — brak zależności kolejności.

---

## Refactor opportunities (ranking)

Kryterium rankingu: dźwignia = koszt długu (jak bardzo obecny kształt boli/kosztuje) względem kosztu zmiany (jak trudna/ryzykowna jest naprawa), oceniane na podstawie dowodów z trzech osi badania.

### 1. Kandydat A — Wspólny orkiestrator wykonania testów (największa dźwignia, największe ryzyko)

**Obecny → docelowy kształt:** Dwa niezależne structy (`TestService`, `XcodeBuildTestCommandService`) duplikujące 15/16 zależności i całe metody (upload, kwarantanna, sharding, activity-log) → wspólny wewnętrzny typ (`TestExecutionOrchestrator` lub podobny) w `TuistKit`, przejmujący te 15 kolaboratorów i wspólną sekwencję post-xcodebuild; oba wywołujące structy redukują się do warstwy specyficznej dla siebie (dla `TestService`: generowanie grafu/Tuist-specific; dla `XcodeBuildTestCommandService`: wejście dla projektów niegenerowanych).

**Czemu na 1. miejscu (koszt długu vs koszt zmiany):** Największy udokumentowany koszt długu — 36% co-change między plikami (z pierwotnego raportu), bus factor 1 na najgorętszym pliku CLI, i **jedyny** kandydat, gdzie duplikacja obejmuje logikę biznesową (kwarantanna, upload, sharding), nie tylko boilerplate. Koszt zmiany jest realny, ale zmierzony i zsekwencjonowany: konkretna, nazwana luka (8 testów/573 linii bez pokrycia kontynuacji kwarantanny i uploadu `.remote` po stronie bliźniaka, zero testów akceptacyjnych) — to nie "unknown ryzyko", to zmierzone ryzyko z jasnym pierwszym krokiem, który je neutralizuje przed dotknięciem produkcji.

**Blast radius:** `XcodeBuildTestCommandService.swift` + jego 8 testów (bezpośrednio dotknięte); `TestService.swift` (usunięcie duplikowanych metod); `cli-unit-tests` (oba pliki testowe pod `TuistUnitTests`); `cli-acceptance-tests` — pokrywa stronę `TestService`/sharding (`TestAcceptanceTests.swift:337-452`), ale **nie** pokrywa `XcodeBuildTestCommandService` wcale, co samo w sobie jest częścią kosztu zmiany do zaadresowania w kroku 0.

**Szkic ścieżki inkrementalnej:**
1. Domknąć luki testowe `XcodeBuildTestCommandServiceTests.swift` (kontynuacja kwarantanny=true, `.remote` upload, pełny cykl shardu) — zero zmian produkcyjnych.
2. Wydzielić wyłącznie wzorzec "pre-run server round-trip" (kwarantanna + sharding) — węższy, niezależny krok.
3. Wydzielić wspólny orkiestrator dla sekwencji post-xcodebuild (upload/kontynuacja) — największy krok, teraz osłonięty krokiem 1.

**Pierwszy krok-prerekwizyt:** Krok 1 powyżej — dopisanie testów do `XcodeBuildTestCommandServiceTests.swift`, bez dotykania kodu produkcyjnego.

### 2. Kandydat C — Zamknięcie szwu OpenAPI w `outputEmptyShardMatrixIfNeeded` (najlepszy stosunek wartości do kosztu)

**Obecny → docelowy kształt:** `TestService.swift:1479` ręcznie konstruuje `Components.Schemas.ShardPlan(...)` → `ShardMatrixOutputServicing` zyskuje metodę `outputEmpty()` (lub równoważną), budującą placeholder wewnętrznie; `TestService.swift` przestaje dotykać wygenerowanego typu bezpośrednio.

**Czemu na 2. miejscu:** Udokumentowany, powtarzalny koszt długu — 4 łatki w 5 miesięcy, w tym jedna wymuszona zmianą schematu serwera (dowód na realne sprzężenie, nie teoretyczne ryzyko). Koszt zmiany jest najniższy z trzech kandydatów: jeden plik, jedno miejsce wywołania, 4 istniejące testy już asertujące na kształcie wyniku (nie sposobie konstrukcji) — praktycznie darmowa siatka bezpieczeństwa. W pełni niezależny od Kandydata A.

**Blast radius:** `ShardMatrixOutputService.swift` (nowa metoda), `TestService.swift:1476-1488` (jedno wywołanie). Zero dotknięcia `XcodeBuildTestCommandService.swift` (nie referencjonuje tego protokołu).

**Szkic ścieżki inkrementalnej:** Jeden PR — dodaj metodę, przełącz wywołanie, uruchom istniejące 4 testy bez zmian.

**Pierwszy krok-prerekwizyt:** Brak — gotowe do realizacji od razu, żadnych zależności blokujących.

### 3. Kandydat B — Usunięcie klastra martwego kodu (najniższe ryzyko, najniższa strategiczna waga)

**Obecny → docelowy kształt:** 5 nieosiągalnych metod (`TestService.swift:2239-2309`) + `passedValue` zduplikowane w 4 plikach/2 modułach → metody usunięte; `passedValue` istnieje raz w `TuistSupport` (fan-in 38, już współdzielony przodek `TuistKit` i `TuistAutomation`).

**Czemu na 3. miejscu:** Zero-ryzykowna, w pełni zmierzona operacja (potwierdzone dwukrotnie: przez pierwotny raport i niezależnie przez to badanie) — ale koszt długu jest niski: to bloat pliku i jeden akt niekompletnego cleanupu, nie aktywnie mylące ani ryzykowne dla przyszłych zmian w tym samym stopniu co Kandydat A. Najlepszy "zrób to teraz" kandydat, ale nie najważniejszy strategicznie.

**Blast radius:** `TestService.swift` (usunięcie 5 metod), `XcodeBuildBuildCommandService.swift`/`XcodeBuildTestCommandService.swift`/`XcodeBuildArgumentParser.swift` (przełączenie na wspólną implementację w `TuistSupport`) — bramkowane wyłącznie przez `cli-lint`/`cli-unit-tests`.

**Szkic ścieżki inkrementalnej:** (1) Usuń klaster 5 metod + nieużywaną kopię `passedValue` w `TestService.swift` — jeden mechaniczny PR. (2) Osobny follow-up: dodaj `passedValue` do `TuistSupport`, przełącz 3 pozostałe miejsca wywołania.

**Pierwszy krok-prerekwizyt:** Brak — gotowe do realizacji od razu, niezależnie od A i C.

---

## Kandydaci rozważeni i odrzuceni (na etapie klasyfikacji)

Żaden ze zidentyfikowanych 3 kandydatów strukturalnych nie został odrzucony z rankingu — wszystkie trzy trafiły powyżej. Odrzucone na wcześniejszym etapie (klasyfikacji "czy to w ogóle kandydat") zostały problemy, które **nie są strukturalne z definicji zadanej na wejściu tej analizy** (naprawa nie zmienia struktury kodu produkcyjnego):

- **Nieprzetestowana kontynuacja kwarantanny, `.remote` upload, ścieżki błędów, `schemeWithoutTestableTargets`/`unspecifiedPlatform`, `resolveTestProductsPath` fallback, `generateOnly`** — wszystkie to luki testowe. Naprawa = dopisanie testów, nie zmiana struktury produkcyjnej. Zachowane jako wejście do oceny wykonalności Kandydata A (ta sama luka pojawia się ponownie, głębsza, po stronie `XcodeBuildTestCommandService`).
- **"Testy jako wyłącznie wiring tests" (24 mocki)** — konsekwencja rozmiaru god-service (Kandydat A), nie osobny problem strukturalny; jego naprawa to efekt uboczny ekstrakcji orkiestratora, nie samodzielna interwencja.
- **Niezweryfikowany magazyn stanu shardingu (Postgres vs. ClickHouse)** — luka wiedzy, nie problem strukturalny. Pozostaje `unknown`; istotne jako wejście do oceny blast radius, gdyby Kandydat A dotknął kiedyś warstwy serwerowej shardingu (nie dotyka w zakresie tego rankingu — cała praca A/B/C jest po stronie CLI).
- **`generateOnly` jako potencjalnie martwa ścieżka produkcyjna** (nie tylko nieprzetestowana) — otwarte pytanie z pierwotnego raportu, nierozstrzygnięte w tym badaniu (nie było w zakresie 3 wybranych kandydatów). Pozostaje `unknown`.

## Code References

- `cli/Sources/TuistKit/Services/TestService.swift:107-134` — deklaracja struct + 27 zależności
- `cli/Sources/TuistKit/Services/TestService.swift:617-649` — `fetchQuarantinedTests`
- `cli/Sources/TuistKit/Services/TestService.swift:1476-1488` — `outputEmptyShardMatrixIfNeeded` (Kandydat C)
- `cli/Sources/TuistKit/Services/TestService.swift:1975-1983`, `:1985-2013`, `:2015-2070` — metody duplikowane z bliźniakiem (Kandydat A)
- `cli/Sources/TuistKit/Services/TestService.swift:2170-2175` — `passedValue` (Kandydat B)
- `cli/Sources/TuistKit/Services/TestService.swift:2239-2309` — klaster martwego kodu (Kandydat B)
- `cli/Sources/TuistKit/Services/XcodeBuild/XcodeBuildTestCommandService.swift:23-38` — 16 zależności bliźniaka
- `cli/Sources/TuistKit/Services/XcodeBuild/XcodeBuildTestCommandService.swift:351-358`, `:395-448`, `:453-461`, `:463-493` — metody duplikowane
- `cli/Sources/TuistKit/Services/XcodeBuild/XcodeBuildBuildCommandService.swift:289-297` — `passedValue` (kopia 2)
- `cli/Sources/TuistAutomation/XcodeBuild/XcodeBuildArgumentParser.swift:48-56` — `passedValue` (kopia 3, inny moduł)
- `cli/Sources/TuistKit/Services/Sharding/ShardMatrixOutputService.swift:11-13` — `ShardMatrixOutputServicing` protokół
- `cli/Sources/TuistKit/Services/Sharding/ShardPlanService.swift:17-33`, `:72,87,99,192` — `ShardPlanServicing`, jedyny drugi konsument `ShardMatrixOutputServicing`
- `cli/Sources/TuistKit/Services/TestQuarantineService.swift:7` — `TestQuarantineServicing`
- `cli/Tests/TuistKitTests/Services/TestServiceTests.swift:1261,1265,1269,1277` — testy `outputEmptyShardMatrixIfNeeded`
- `cli/Tests/TuistKitTests/Services/XcodeBuild/XcodeBuildTestCommandServiceTests.swift` (573 linii, 8 testów) — cienka osłona bliźniaka
- `cli/Tests/TuistAutomationAcceptanceTests/TestAcceptanceTests.swift:337-452` — jedyne testy akceptacyjne shardingu (tylko strona `TestService`)
- `Package.swift:1318-1372` (`TuistKit`), `:1472-1480` (`TuistAutomation`) — granice modułów, zależność `TuistKit → TuistAutomation → TuistSupport`
- `cli/AGENTS.md` — sekcja "Legacy Modules", nazywa `TuistKit` jako obszar do unikania w nowym kodzie (dodane 2026-01-22, `4812545d10`)
- `.github/workflows/cli.yml` — guardrails CI: `cli-lint`, `cli-unit-tests` (`tuist test TuistUnitTests`), `cli-acceptance-tests` (sharded), `cli-linux-*`

## Historical Context (from prior changes)

- `context/changes/test-service-analysis/research.md` — pierwotna analiza e2e/luk testowych/blast radius dla `TestService.swift`; ta zmiana buduje bezpośrednio na jej ustaleniach jako zebranych dowodach, weryfikuje je ponownie w kodzie i uzupełnia o oś historii/intencjonalności oraz wykonalności migracji, których tamten raport celowo nie obejmował.
- `context/map/repo-map.md` (+ `artifact-1-territory.md`, `artifact-2-structure.md`, `artifact-3-contributors.md`) — użyte jako priory: potwierdzają `TestService.swift` jako strefę ryzyka #1 (73 zmiany/12 mies., bus factor), `TuistSupport` jako fan-in 38 (uzasadnienie miejsca na dedup `passedValue` w Kandydacie B), oraz status `TuistKit` jako modułu-huba.

## Related Research

- `context/changes/test-service-analysis/research.md` — źródłowa analiza długu technicznego, na której bazuje ta zmiana.

## Open Questions

1. Czy `generateOnly` (nigdy nie wywołane z `true` w testach) jest martwą ścieżką produkcyjną, czy tylko nieprzetestowaną — nierozstrzygnięte, poza zakresem 3 wybranych kandydatów (patrz: pierwotny raport, Open Question #4).
2. Czy `server/lib/tuist/shards/shard_plan.ex`/`shard_run.ex` zapisują do Postgresa czy ClickHouse — nierozstrzygnięte, istotne tylko gdyby przyszła iteracja Kandydata A rozszerzyła zakres o stronę serwerową (poza zakresem obecnego rankingu, który jest wyłącznie CLI).
3. Czy dokładny mechanizm złożenia schematu `TuistUnitTests` (statyczny xctestplan vs. dynamicznie generowany przez Tuist) — niezweryfikowane przez agenta wykonalności; nie wpływa na ranking, ale warto potwierdzić przed etapem planowania Kandydata A.
4. Czy `ShardMatrixOutputServicing`, mimo `public`, ma jakiegokolwiek konsumenta poza tym repozytorium — niezweryfikowane; jeśli `TuistKit` nie jest publikowany jako zewnętrzna biblioteka (nic w `Package.swift` na to nie wskazuje), ryzyko kompatybilności dla Kandydata C jest znikome, ale nie zostało to formalnie potwierdzone.
