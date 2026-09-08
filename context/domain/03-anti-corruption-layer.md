---
title: Anti-Corruption Layer — OpenAPI Wire Types in Test Run / Shard Domain Logic
created: 2026-09-08
type: refactor-plan
---

# Plan refaktoru: Anti-Corruption Layer dla wygenerowanych typów OpenAPI

> Ten dokument to **PLAN**, nie implementacja. Żaden plik produkcyjny nie został zmodyfikowany w trakcie jego powstawania. Kontynuuje `context/domain/01-domain-distillation.md` (destylacja domenowa `tuist test`) i `context/domain/02-invariant-aggregate-refactor.md` (agregat-strażnik po stronie serwera) na tym samym bounded contexcie, ale zmienia oś: zamiast niezmienników biznesowych, szuka **przeciekających zależności zewnętrznych przez granice warstw**.

---

## KROK 0 — Odkrycie kontekstu

**PRD/tech-stack:** `context/foundation/` nadal nie zawiera `prd.md` ani `tech-stack.md` (zweryfikowane w tej sesji — jedyny plik to `context/foundation/README.md`, konwencja katalogu). Jak w `01-domain-distillation.md:11` i `02-invariant-aggregate-refactor.md:15`, brak formalnej wizji produktu jest trwałym ograniczeniem tego repo.

**Deklaracje o wymienialności komponentów — znalezione w tej sesji:**

1. `CLAUDE.md:126-128` (root, sekcja "OpenAPI Code Generation"): *"The server's OpenAPI spec and CLI Swift client code are regenerated with: `mise run generate-api-cli-code` (...) This exports the spec to `cli/Sources/TuistServer/OpenAPI/server.yml` and regenerates `Types.swift` and `Client.swift` (...) Do not edit `server.yml`, `Types.swift`, or `Client.swift` manually — update the controller schemas in the server and regenerate."* — to jednoznaczna deklaracja: kształt wygenerowanych typów (`Components.Schemas.*`, `Operations.*`) jest **mechanicznie odtwarzalny i zmienny**, sterowany przez zespół serwerowy, nie stabilnym kontraktem, na którym wolno budować logikę biznesową CLI wprost.
2. `cli/Sources/TuistKit/AGENTS.md` (sekcja "Boundaries"): *"Keep orchestration here; domain logic lives in feature modules (...) Avoid direct file system or graph logic that belongs in `TuistCore`, `TuistGenerator`, or `TuistSupport`."* i (sekcja "Related Context"): *"Server integration: `cli/Sources/TuistServer/AGENTS.md`"* — deklaruje `TuistKit` jako warstwę orkiestracji, nie integracji z serwerem; integracja serwerowa jest wydzielona do osobnego modułu.
3. `cli/Sources/TuistServer/AGENTS.md` (sekcja "Responsibilities"): *"Map CLI actions to server operations (projects, previews, analytics, registry)."* — `TuistServer` deklaruje się jako warstwa **mapująca** (czyli tłumacząca), nie jako warstwa, której typy mają swobodnie przepływać dalej.

**Stack tego obszaru** (zweryfikowany w tej sesji): CLI Swift, dwa moduły SPM: `TuistServer` (klient wygenerowany z `server.yml` przez `swift-openapi-generator`, katalog `cli/Sources/TuistServer/{OpenAPI,Services,Models,Client}`) i `TuistKit` (orkiestracja komend, `cli/Sources/TuistKit/Services/`). Zależność zewnętrzna w centrum tej analizy: **wygenerowany klient OpenAPI** (`Components.Schemas.*`, `Operations.*` z `cli/Sources/TuistServer/OpenAPI/Types.swift`).

**Zakres:** ten sam bounded context co `01`/`02` — `tuist test` i sharding (`Test Run`, `Shard Plan`, `Shard`, `Shard Granularity` — pojęcia już nazwane w `01-domain-distillation.md:30-41`). Wybór zawężenia: wstępny przegląd (KROK 1 niżej) objął też kandydata po stronie serwera (Elixir/`ExAws.S3`); po klasyfikacji (KROK 2) okazał się słabszy niż kandydat CLI — oba są udokumentowane poniżej, zgodnie z wymogiem "nie zakładaj z góry".

---

## KROK 1 — Identyfikacja przeciekających zależności

Przegląd objął dwóch kandydatów zbadanych z porównywalną głębokością, plus krótki, jawnie oznaczony jako płytki, przegląd trzeciego (Stripe) w celu wykluczenia go bez fałszywej pewności.

### Kandydat A — `ExAws.S3` (serwer, Elixir): dwie niezależne rekonstrukcje tego samego klienta S3

`server/lib/tuist/storage.ex` jest zadeklarowanym właścicielem dostępu do object storage — `server/lib/tuist/storage/AGENTS.md:3`: *"This context owns object storage access (S3-compatible and Azure Blob)."* — i faktycznie dysponuje portem dwóch backendów: `storage.ex:52-72` (`presigned_url/3`) rozgałęzia się na `:azure_blob` (deleguje do `Tuist.Storage.AzureBlob`) vs `:s3` (woła `ExAws.S3.presigned_url/5` wprost), zweryfikowane bezpośrednio w tej sesji.

Mimo tej deklaracji, `server/lib/tuist/registry/s3.ex:1-10` (moduledoc, zweryfikowane w tej sesji) sam przyznaje się do duplikacji: *"Server uses `Tuist.Storage` for account-scoped artifact buckets; this module is the parallel surface for the registry bucket (...) The standalone registry pod has its own equivalent (`TuistRegistry.S3`)."* — czyli **trzy** niezależne implementacje tego samego wzorca (upload/download/delete/list na `ExAws.S3`), z których jedna (`Tuist.Registry.S3`) jest w tym samym procesie Elixir co `Tuist.Storage`.

Pliki, które "znają" surowe operacje `ExAws.S3.*` (zweryfikowane w tej sesji, `grep -rln "ExAws.S3" server/lib --include="*.ex"`):
- `server/lib/tuist/storage.ex` (deklarowany właściciel)
- `server/lib/tuist/registry/s3.ex` (równoległa implementacja, `s3.ex:12,31,43,73,101,131,179,209,214`)
- `server/lib/tuist/registry/swift/sync_cursor.ex:14,38` — buduje surowe operacje `ExAws.S3.get_object/put_object` samodzielnie, nie przez wygodne funkcje `Tuist.Registry.S3`
- `server/lib/tuist/registry/swift/lock.ex:37,82,102` — jw.
- `server/lib/tuist/minio_bucket_creator.ex:34,43` (narzędzie deweloperskie/seed, mniejsza waga produkcyjna)

**Rozsmarowanie:** 4 pliki produkcyjne, 2 poddomeny (`Storage` i `Registry`) w jednym procesie OTP. **Wymienialność:** deklarowana wprost dla `Storage` (S3 ↔ Azure Blob), ale `Registry.S3`/`sync_cursor.ex`/`lock.ex` są nieodwracalnie związane z `ExAws`/S3 — nie da się przełączyć registry bucket na Azure Blob bez osobnej pracy, mimo że dokładnie ten problem `Tuist.Storage` już rozwiązał obok.

### Kandydat B — `Components.Schemas.*` / `Operations.*` (CLI, Swift): wygenerowany klient OpenAPI w logice domenowej

Zweryfikowane w tej sesji (`grep -rl "Components\.Schemas\|Operations\." cli/Sources/TuistKit/{Services,Extensions} -r`) — 6 plików w `TuistKit` (warstwa orkiestracji per `TuistKit/AGENTS.md`, nie warstwa integracji serwerowej) odwołuje się bezpośrednio do typów wygenerowanych z `server.yml`:

| Plik | Cytat (plik:linia) | Rola |
|---|---|---|
| `cli/Sources/TuistKit/Extensions/ShardGranularity+ExpressibleByArgument.swift:4` | `public typealias ShardGranularity = Components.Schemas.CreateShardPlanParams.granularityPayload` | Pojęcie domenowe "Shard Granularity" (nazwane w `01-domain-distillation.md:35`) **nie ma własnego typu** — jest aliasem wygenerowanego enuma, w warstwie parsowania argumentów CLI |
| `cli/Sources/TuistKit/Services/Sharding/ShardPlanService.swift:32,118` | `protocol ShardPlanServicing { func plan(...) async throws -> Components.Schemas.ShardPlan }` | Publiczny protokół warstwy orkiestracji zwraca surowy DTO |
| `cli/Sources/TuistKit/Services/Sharding/ShardMatrixOutputService.swift:12,27,61,166` | `func output(_ shardPlan: Components.Schemas.ShardPlan) async throws` | Warstwa formatowania wyjścia (zapis JSON do pliku) przyjmuje surowy DTO jako parametr |
| `cli/Sources/TuistKit/Services/TestService.swift:1479-1485` | `Components.Schemas.ShardPlan(id: "", reference: "", shard_count: 0, shards: [], upload_url: "")` | Logika domenowa **konstruuje fikcyjną instancję** DTO biblioteki, by wyrazić "brak planu shardu" |
| `cli/Sources/TuistKit/Services/TestCaseListService.swift:17,33` | `state: Operations.listTestCases.Input.Query.statePayload` | Parametr wejściowy protokołu domenowego to typ zapytania HTTP wygenerowany z operacji |
| `cli/Sources/TuistKit/Services/InspectResultBundleService.swift:47,58,114,190,268,313,314` | `-> Components.Schemas.RunsTest`, `[String: Components.Schemas.RunsTest.test_case_runsPayloadPayload]` | Zwracany typ i klucz słownika w logice łączenia wyników testów z serwerem to zagnieżdżony typ wygenerowany |

Po stronie `TuistServer` (moduł, który per `TuistServer/AGENTS.md` ma "Map CLI actions to server operations" — czyli być granicą), zweryfikowano w tej sesji, że **nie ma jednego spójnego wzorca** — część serwisów już konwertuje do typu domenowego, część nie:

| Serwis (`cli/Sources/TuistServer/Services/`) | Zwracany typ | Status |
|---|---|---|
| `CreateTestService.swift:32` | `Components.Schemas.RunsTest` | **surowy DTO** |
| `GetShardService.swift:13,48` | `Components.Schemas.Shard` | **surowy DTO** |
| `CreateShardPlanService.swift:19,22,64,67` | `Components.Schemas.ShardPlan` (zwracany), `Components.Schemas.CreateShardPlanParams.granularityPayload` (wejście) | **surowy DTO** (in i out) |
| `ListTestCaseRunsService.swift:16,56,98,105,121` | `Components.Schemas.TestCaseRunsList` | **surowy DTO**, dodatkowo plik rozszerza sam typ wygenerowany (`extension Components.Schemas.TestCaseRunsList`, `:98`) zamiast opakowywać go |
| `ListTestRunsService.swift:16,57` | `Operations.listTestRuns.Output.Ok.Body.jsonPayload` | **surowy DTO — inny typ niż powyższe**, mimo że reprezentuje ten sam koncept "Test Run" |
| `GetTestRunService.swift:6` | `public typealias ServerTestRun = Operations.getTestRun.Output.Ok.Body.jsonPayload` | **fałszywy ACL** — nazwa sugeruje domenowy wrapper (konwencja `Server*` z `TuistServer/Models/`, patrz niżej), ale to gołe przenazwanie (`typealias`) wygenerowanego typu, zero mapowania |
| `TuistServer/Services/GetShardService.swift`, `CreateTestService.swift` (kontrast) | — | `TuistServer/Models/` (`ServerBuild.swift`, `ServerCacheArtifact.swift`, `ServerPreview.swift`, `ServerProject.swift`, 15 innych — zweryfikowane w tej sesji, `ls cli/Sources/TuistServer/Models`) pokazuje, że **wzorzec opakowywania już istnieje w repo** dla innych konceptów, po prostu nie zastosowano go tu |

`ServerBuild.swift:26-43` (zweryfikowane w tej sesji) to konkretny, działający przykład wzorca, którego brakuje dla Test Run/Shard: `init?(_ build: Components.Schemas.RunsBuild)` mapuje enum wygenerowany (`build.status: .success/.failure/.processing/.failed_processing`) na własny, węższy enum domenowy `ServerBuildStatus` — zauważalnie **węższy** niż wire enum, bo domena buildów nie potrzebuje wszystkich wire-values.

**Rozsmarowanie:** 6 plików `TuistKit` (warstwa orkiestracji/CLI-argumentów/formatowania wyjścia) + co najmniej 6 plików `TuistServer` (warstwa integracji), **3 różne reprezentacje tego samego pojęcia domenowego "Test Run"** (`Components.Schemas.RunsTest`, `Operations.listTestRuns.Output.Ok.Body.jsonPayload`, fałszywy `ServerTestRun`). **Wymienialność:** deklarowana explicite przez `CLAUDE.md:126-128` (typy są mechanicznie regenerowane, nie stabilnym kontraktem), naruszona przez głębokie, strukturalne odwołania w 6 plikach `TuistKit` do zagnieżdżonych payloadów (`RunsTest.test_case_runsPayloadPayload`, `CreateShardPlanParams.granularityPayload`).

### Kandydat C — Stripe (serwer, Elixir): przegląd płytki, wykluczony

`grep -rln "Stripe\." server/lib/tuist --include="*.ex"` → 6 plików; `grep -rln "Stripe\." server/lib/tuist_web --include="*.ex"` → 3 pliki (zweryfikowane w tej sesji, tylko liczbowo — treść nieprzeczytana). Sygnał istnieje (przeciek domena→web), ale bez przeczytania treści nie da się ocenić rozsmarowania ani egzekwowalności — odnotowane jako możliwy przyszły kandydat, nie klasyfikowane dalej w tym dokumencie.

---

## KROK 2 — Klasyfikacja i wybór #1

| Kryterium | Kandydat A (`ExAws.S3`, serwer) | Kandydat B (`Components.Schemas`/`Operations`, CLI) |
|---|---|---|
| (a) Liczba warstw/plików | 4 pliki produkcyjne, 2 poddomeny, **1 warstwa koncepcyjna** (wszystkie to moduły serwisowe/infrastrukturalne tego samego rodzaju — żaden nie jest warstwą UI/prezentacji) | 6 plików `TuistKit` (orkiestracja + parsowanie argumentów CLI + formatowanie wyjścia JSON — **3 różne role warstwowe**) + 6 plików `TuistServer` (warstwa integracji) = 12 plików, **4 role warstwowe** |
| (b) Ryzyko/koszt wymiany biblioteki dziś | Średnie — `ExAws` to jedna biblioteka HTTP-S3; wymiana dotyka 4 pliki o podobnym kształcie (wszystkie wołają `ExAws.S3.*` bezpośrednio, względnie jednorodnie) | Wysokie — wymiana generatora OpenAPI (`swift-openapi-generator`) albo nawet **rutynowa** zmiana schematu w serwerze (dodanie/zmiana pola w `server.yml`, coś co `CLAUDE.md:126-128` opisuje jako normalny, częsty proces) może zmienić kształt `RunsTest`/`ShardPlan`/`granularityPayload` i złamać kompilację lub zachowanie w 6 plikach `TuistKit`, które nie mają żadnej izolacji |
| (c) Rozjazd deklaracji vs kod | `storage/AGENTS.md:3` deklaruje `Storage` jako właściciela — kod **częściowo** to respektuje (sam `Storage` jest czysty), ale **obok** niego żyje inny moduł, który nie respektuje tej własności wcale | `CLAUDE.md:126-128` deklaruje wprost mechaniczną, częstą regenerowalność — kod **głęboko** ignoruje to w warstwie, która per `TuistKit/AGENTS.md` i `TuistServer/AGENTS.md` **nie powinna** w ogóle stykać się z tymi typami |
| Dodatkowy sygnał | — | **Fałszywy ACL** (`ServerTestRun` = goły `typealias`, `GetTestRunService.swift:6`) — najbardziej niebezpieczny podtyp przecieku: udaje izolację, więc żaden przyszły czytelnik/refaktorujący nie ma powodu podejrzewać dziury tam, gdzie nazwa sugeruje, że już jest bezpiecznie |

**Wybór #1: Kandydat B — `Components.Schemas.*`/`Operations.*` w logice domenowej/orkiestracyjnej CLI.**

**Uzasadnienie:** Kandydat B wygrywa na wszystkich trzech osiach. (a) Dotyka więcej ról warstwowych — nie tylko dwóch równoległych implementacji tego samego rodzaju, ale trzech różnych *rodzajów* warstw (parsowanie argumentów, orkiestracja, serializacja wyjścia) plus samą warstwę integracji, która sama sobie przeczy (6 z ok. 20 serwisów `TuistServer` łamie własny wzorzec `Server*`, potwierdzony istnieniem `TuistServer/Models/`). (b) Ryzyko wymiany/zmiany jest tu wyższe, bo źródło zmiany (serwer, `server.yml`) jest w innym repozytorium logicznym niż konsument (CLI) i zmienia się rutynowo, nie hipotetycznie. (c) Rozjazd intencja-vs-kod jest udokumentowany wprost i dwukrotnie (`CLAUDE.md` + dwa `AGENTS.md`), a mimo to złamany głębiej niż u Kandydata A. Dodatkowo Kandydat B zawiera przypadek jakościowo gorszy niż cokolwiek w Kandydacie A: fałszywy ACL, który tworzy złudne poczucie bezpieczeństwa.

---

## KROK 3 — Diagnoza

### Duplikacja: trzy niezależne kształty tego samego pojęcia "Test Run"

1. `Components.Schemas.RunsTest` — zwracany przez `CreateTestService.swift:32` i głęboko konsumowany w `InspectResultBundleService.swift:47,58,114,190` (`TuistKit`).
2. `Operations.listTestRuns.Output.Ok.Body.jsonPayload` — zwracany przez `ListTestRunsService.swift:16,57`. Strukturalnie **inny typ Swift** niż (1), mimo że oba reprezentują listę/instancję tego samego bytu domenowego "Test Run" nazwanego w `01-domain-distillation.md:30`.
3. `ServerTestRun` (`GetTestRunService.swift:6`) — `typealias` do `Operations.getTestRun.Output.Ok.Body.jsonPayload`, **trzeci** odrębny typ Swift, opakowany nazwą sugerującą domenowy model, ale bez żadnej konwersji.

Każdy z tych trzech typów ma osobny zestaw pól i osobne enumy zagnieżdżone (np. `RunsTest.test_case_runsPayloadPayload` vs analogiczne pole w pozostałych dwóch) — konsument w `TuistKit` musi znać, który z trzech kształtów dostał, w zależności OD TEGO, KTÓRY endpoint zawołał, mimo że koncepcyjnie operuje na jednym pojęciu domenowym.

### Przecięcie granic: warstwa orkiestracji fabrykuje DTO biblioteki

`TestService.swift:1479-1485` (zweryfikowane w tej sesji):
```
try await shardMatrixOutputService.output(
    Components.Schemas.ShardPlan(
        id: "",
        reference: "",
        shard_count: 0,
        shards: [],
        upload_url: ""
    )
)
```
Zachowanie ("opublikuj pusty shard matrix, gdy build-only sharding run nie ma testów") jest udokumentowane jako celowe w `TuistKit/AGENTS.md` (sekcja Invariants, ostatni punkt: *"A build-only sharding run must also publish it when emitting an empty shard matrix, because no test job will follow."*) — to nie jest błąd logiki biznesowej. Problem jest inny: **mechanizm** wyrażenia "brak planu" to instancja DTO biblioteki wypełniona sentinelami (`id: ""`, `shard_count: 0`), a nie `nil`/domenowy enum `.none`. Gdyby wygenerowany typ `ShardPlan` kiedykolwiek dodał nowe wymagane pole (rutynowa zmiana `server.yml`, `CLAUDE.md:126-128`), ten konstruktor przestaje się kompilować w miejscu, które koncepcyjnie nie ma nic wspólnego z kształtem odpowiedzi HTTP.

### Fałszywy ACL — najgroźniejszy pojedynczy przypadek

`GetTestRunService.swift:6`: `public typealias ServerTestRun = Operations.getTestRun.Output.Ok.Body.jsonPayload`.

Skontrastowane z prawdziwym wzorcem, `ServerBuild.swift:11-43` (zweryfikowane w tej sesji): `struct ServerBuild: Codable` z `init?(_ build: Components.Schemas.RunsBuild)`, który explicite mapuje wire-enum na węższy domenowy `ServerBuildStatus`. Nazwa `ServerTestRun` podąża za tą samą konwencją nazewniczą (`Server` + koncept), więc każdy czytelnik kodu w `TuistKit`, widząc `-> ServerTestRun` w sygnaturze, ma uzasadnione prawo założyć, że dostaje opakowany typ domenowy — a dostaje surowy, wygenerowany JSON payload. To odwrotność bezpiecznego ACL: bezpieczeństwo pozorne jest gorsze niż jego brak, bo usypia czujność przy przyszłych zmianach.

### Rozjazd MODEL vs KOD

| # | Dokument mówi | Kod robi | Dowód |
|---|---|---|---|
| 1 | `CLAUDE.md:126-128`: typy `Types.swift`/`Client.swift` są mechanicznie regenerowane z `server.yml`, edytowane wyłącznie przez regenerację — sugeruje, że są ulotnym detalem transportu, nie stabilnym API do budowania logiki na nim | `ShardGranularity+ExpressibleByArgument.swift:4` czyni jeden z tych typów (`CreateShardPlanParams.granularityPayload`) **publicznym aliasem domenowego pojęcia** (`ShardGranularity`) używanym w parsowaniu argumentów CLI — najbardziej user-facing warstwie ze wszystkich | Zweryfikowane bezpośrednio w tej sesji |
| 2 | `TuistServer/AGENTS.md` ("Responsibilities"): moduł ma "Map CLI actions to server operations" — deklaruje rolę tłumacza | `CreateTestService.swift:32`, `GetShardService.swift:13,48`, `CreateShardPlanService.swift:22,67`, `ListTestCaseRunsService.swift:16,56` zwracają surowe `Components.Schemas.*` bez mapowania — moduł deklaruje tłumaczenie, ale w tych 4 serwisach go nie wykonuje | Zweryfikowane bezpośrednio w tej sesji |
| 3 | `TuistKit/AGENTS.md` ("Boundaries"): "Keep orchestration here; domain logic lives in feature modules" — sugeruje `TuistKit` ma pozostać cienką warstwą orkiestracji nad domenowymi abstrakcjami | `InspectResultBundleService.swift` (7 wystąpień, `:47,58,114,190,268,313,314`) i `ShardMatrixOutputService.swift` (4 wystąpienia, `:12,27,61,166`) budują logikę bezpośrednio na zagnieżdżonych typach wygenerowanych (`RunsTest.test_case_runsPayloadPayload`), nie na abstrakcji domenowej | Zweryfikowane bezpośrednio w tej sesji |

---

## KROK 4 — Projekt ACL

### Wybór granicy i nazw

Kontynuacja słownika z `01-domain-distillation.md:30-41`: domenowe pojęcia już nazwane tam (**Test Run**, **Shard**, **Shard Plan**, **Shard Granularity**) dostają teraz swoje własne typy Swift, niezależne od `Components.Schemas`/`Operations`. Wzorzec **nie jest nowy w repo** — `TuistServer/Models/ServerBuild.swift` już go realizuje dla `Build`; ten refaktor rozszerza istniejącą konwencję na `Test Run`/`Shard`/`Shard Plan`, zamiast wymyślać nową.

Jedno zastrzeżenie nazewnicze: nazwa `ServerTestRun` jest dziś zajęta przez fałszywy `typealias` (`GetTestRunService.swift:6`) — w ramach tego refaktoru ta nazwa zostaje **odzyskana** dla prawdziwego typu domenowego (krok 5, faza 1), nie dodawana jako nowa obok niej.

### Nowe typy domenowe (żyją w `TuistServer/Models/`, obok `ServerBuild.swift`)

```swift
// TuistServer/Models/ServerTestRun.swift
public enum ServerTestRunStatus: String, Codable {
    case success, failure, skipped, inProgress = "in_progress",
         processing, failedProcessing = "failed_processing"
}

public struct ServerTestRun: Codable {
    public let id: String
    public let status: ServerTestRunStatus?
    public let isFlaky: Bool
    // ...pola potrzebne konsumentom w TuistKit, nie 1:1 z wire shape...

    // JEDYNE miejsce, które zna kształt `Components.Schemas.RunsTest`
    init?(_ test: Components.Schemas.RunsTest) { /* mapowanie enumów jak w ServerBuild.swift:31-42 */ }

    // JEDYNE miejsce, które zna kształt `Operations.listTestRuns.Output.Ok.Body.jsonPayload`
    init?(_ payload: Operations.listTestRuns.Output.Ok.Body.jsonPayload) { /* mapowanie na to samo ServerTestRun */ }

    // JEDYNE miejsce, które zna kształt `Operations.getTestRun.Output.Ok.Body.jsonPayload`
    init?(_ payload: Operations.getTestRun.Output.Ok.Body.jsonPayload) { /* mapowanie na to samo ServerTestRun */ }
}
```

```swift
// TuistServer/Models/ServerShardPlan.swift
public enum ServerShardGranularity: String, Codable { case module, suite }

public struct ServerShardPlan: Codable {
    public let id: String
    public let reference: String
    public let shardCount: Int
    public let shards: [ServerShard]
    public let uploadURL: URL?

    init?(_ plan: Components.Schemas.ShardPlan) { /* ... */ }

    /// Zastępuje sentinel `Components.Schemas.ShardPlan(id: "", ...)` z TestService.swift:1479 —
    /// "brak planu" staje się `nil` na wywołaniu strony (Optional<ServerShardPlan>), nie fikcyjną instancją.
}

public struct ServerShard: Codable {
    public let index: Int
    public let status: ServerTestRunStatus?
    init?(_ shard: Components.Schemas.Shard) { /* ... */ }
}
```

Trzy różne wygenerowane kształty (`RunsTest`, `Operations.listTestRuns...jsonPayload`, `Operations.getTestRun...jsonPayload`) mapują się na **jeden** `ServerTestRun` — to jest właściwe miejsce, gdzie te trzy reprezentacje przestają być trzema, dokładnie zgodnie z regułą "jeden domenowy byt = jedno miejsce wiedzy o jego kształcie".

### Wąski port (protokół domenowy)

`ShardGranularity` (dziś: `typealias` do wire enuma, `ShardGranularity+ExpressibleByArgument.swift:4`) staje się własnym typem:

```swift
// TuistCore/Models/ShardGranularity.swift (obok TestIdentifier.swift, ten sam katalog/konwencja)
public enum ShardGranularity: String, ExpressibleByArgument {
    case module, suite
}
```

`ShardPlanServicing` (`ShardPlanService.swift:17-33`) i `UploadResultBundleServicing`/`ShardMatrixOutputService`'s `output(_:)` (`ShardMatrixOutputService.swift:12`) zmieniają sygnatury z `Components.Schemas.ShardPlan`/`RunsTest` na `ServerShardPlan`/`ServerTestRun`. `TuistServer`-owe serwisy (`CreateTestService`, `GetShardService`, `CreateShardPlanService`, `ListTestCaseRunsService`, `ListTestRunsService`, `GetTestRunService`) stają się adapterami: wołają wygenerowany klient, potem mapują wynik przez `ServerTestRun.init?`/`ServerShardPlan.init?`/`ServerShard.init?` przed zwróceniem.

### Pseudokod ścieżki `TestService.swift:1479` po refaktorze

```swift
private func outputEmptyShardMatrixIfNeeded(isSharding: Bool, action: XcodeBuildTestAction) async throws {
    if isSharding, action == .build {
        try await shardMatrixOutputService.output(nil) // ServerShardPlan? zamiast fikcyjnej instancji
    }
}
```
`ShardMatrixOutputService.output(_: ServerShardPlan?)` decyduje samo, jak wyrenderować "brak planu" (np. pusta tablica JSON) — logika sentinela przenosi się z `TestService` (orkiestracja) do miejsca, które faktycznie odpowiada za format wyjścia.

---

## KROK 5 — Dowód izolacji + before/after

### Lista: które pliki dziś znają `Components.Schemas`/`Operations`, które przestaną

| Plik | Dziś zna wire types? | Po refaktorze zna? |
|---|---|---|
| `TuistServer/Models/ServerTestRun.swift` (nowy) | — | **TAK — jedyne uprawnione miejsce** dla 3 kształtów Test Run |
| `TuistServer/Models/ServerShardPlan.swift` (nowy) | — | **TAK — jedyne uprawnione miejsce** dla `ShardPlan`/`Shard` |
| `TuistServer/Services/CreateTestService.swift` | TAK (`:32`) | NIE — woła `ServerTestRun.init?`, zwraca `ServerTestRun` |
| `TuistServer/Services/GetShardService.swift` | TAK (`:13,48`) | NIE |
| `TuistServer/Services/CreateShardPlanService.swift` | TAK (`:19,22,64,67`) | NIE (przyjmuje `ServerShardGranularity`, zwraca `ServerShardPlan`) |
| `TuistServer/Services/ListTestCaseRunsService.swift` | TAK (`:16,56,98,105,121`) | NIE (traci `extension Components.Schemas.*`, dostaje `ServerTestCaseRunsList`) |
| `TuistServer/Services/ListTestRunsService.swift` | TAK (`:16,57`) | NIE |
| `TuistServer/Services/GetTestRunService.swift` | TAK (fałszywy alias, `:6`) | NIE — `ServerTestRun` przestaje być aliasem, staje się prawdziwym typem |
| `TuistKit/Extensions/ShardGranularity+ExpressibleByArgument.swift` | TAK (`:4`) | NIE — plik prawdopodobnie usuwalny, `ShardGranularity` żyje w `TuistCore` |
| `TuistKit/Services/Sharding/ShardPlanService.swift` | TAK (`:32,118`) | NIE |
| `TuistKit/Services/Sharding/ShardMatrixOutputService.swift` | TAK (`:12,27,61,166`) | NIE |
| `TuistKit/Services/TestService.swift` | TAK (`:1479`) | NIE |
| `TuistKit/Services/TestCaseListService.swift` | TAK (`:17,33`) | NIE (przyjmuje domenowy enum stanu zamiast `Operations.listTestCases.Input.Query.statePayload`) |
| `TuistKit/Services/InspectResultBundleService.swift` | TAK (7×) | NIE |

**Kryterium sukcesu (KROK 6):** po refaktorze `grep -rn "Components\.Schemas\|Operations\." cli/Sources/TuistServer/Models cli/Sources/TuistServer/Services cli/Sources/TuistKit` zwraca dopasowania **wyłącznie** w plikach `TuistServer/Models/Server*.swift` (i w `TuistServer/OpenAPI/{Types,Client}.swift`, poza zakresem — to sam wygenerowany kod) — zero w `TuistServer/Services/*` i zero w `TuistKit/**`.

### Before/after (zduplikowane miejsca)

| Miejsce | Dziś | Po refaktorze |
|---|---|---|
| Reprezentacja "Test Run" | 3 niezależne typy Swift (`RunsTest`, `Operations.listTestRuns...jsonPayload`, `ServerTestRun`-jako-alias) | 1 typ (`ServerTestRun`), 3 prywatne inicjalizatory mapujące |
| `ServerTestRun` nazwa | Fałszywy ACL (`typealias`) | Prawdziwy ACL (`struct` + `init?`) |
| "Brak planu shardu" | Fikcyjna instancja `Components.Schemas.ShardPlan(id: "", ...)` | `Optional<ServerShardPlan>.none` |
| `ShardGranularity` | Alias wire enuma w warstwie parsowania argumentów | Własny `enum` w `TuistCore/Models/`, jak `TestIdentifier` |
| Warstwa UI/wyjścia (`ShardMatrixOutputService`) | Dostaje surowy DTO biblioteki | Dostaje gotowy `ServerShardPlan?` — dokładnie sformułowanie z zadania: *"warstwa UI dostaje gotowe dane domenowe, nie surowy obiekt biblioteki"* |

### Otwarte pytania rozstrzygnięte wg dokumentacji biblioteki

- **Czy `init?` (failable) czy `init` (non-throwing) w mapowaniu?** `ServerBuild.swift:26-29` (precedens w repo) używa `init?` i zwraca `nil`, gdy `URL(string:)` się nie powiedzie — decyzja: nowe typy powielają ten wzorzec (failable), bo `swift-openapi-generator` nie gwarantuje, że string-typowane pola wire (np. `url`) są zawsze parsowalne jako silniejszy typ Swift; to jest dokładnie ten rodzaj decyzji specyficznej dla kontraktu biblioteki, którą zadanie każe zakodować w ACL, nie w warstwie API — tu jest zakodowana w `TuistServer/Models/`, wołający (`TuistKit`) dostaje `Optional`, nie musi znać przyczyny.

---

## KROK 6 — Weryfikacja i plan faz

### Kryterium weryfikacji

```
grep -rn "Components\.Schemas\|Operations\." cli/Sources/TuistServer/Services cli/Sources/TuistKit
```
Dziś: 12 plików (6 `TuistServer/Services` + 6 `TuistKit`, patrz KROK 1/5). Po refaktorze: 0 plików — jedyne dopasowania w całym `TuistServer` ograniczone do `TuistServer/Models/Server*.swift` i wygenerowanego `OpenAPI/{Types,Client}.swift`.

### Plan faz (zgodny z konwencją TDD repo — `cli/AGENTS.md`, Swift Testing)

**Faza 1 — `ServerTestRun`/`ServerShardPlan`/`ServerShard`/`ServerShardGranularity`, test-first.**
Nowe typy w `TuistServer/Models/`, z testami mapowania (`init?` dla każdego z 3 wire-shape'ów Test Run, dla `ShardPlan`, dla `Shard`) — wzorowane na istniejących testach dla `ServerBuild` (lokalizacja niezweryfikowana w tej sesji, patrz Ograniczenia). Ta faza nie dotyka żadnego istniejącego call site — czysty dodatek.

**Faza 2 — Adaptacja serwisów `TuistServer` (6 plików).**
`CreateTestService`, `GetShardService`, `CreateShardPlanService`, `ListTestCaseRunsService`, `ListTestRunsService`, `GetTestRunService` zmieniają zwracany typ na nowy `Server*`. `GetTestRunService.swift:6` traci `typealias`, zyskuje prawdziwe mapowanie. Test-first: każdy zmieniony serwis dostaje test potwierdzający, że mapowanie zachowuje dotychczasowe dane (regresja na istniejących testach `#Mockable`-generowanych stubów).

**Faza 3 — `ShardGranularity` przenosi się do `TuistCore`.**
Usunięcie `ShardGranularity+ExpressibleByArgument.swift`, dodanie `TuistCore/Models/ShardGranularity.swift`. Aktualizacja wszystkich call site'ów (`ShardPlanService`, `CreateShardPlanService`, argument CLI).

**Faza 4 — Adaptacja `TuistKit` (6 plików).**
`ShardPlanService`, `ShardMatrixOutputService`, `TestService.swift:1479`, `TestCaseListService`, `InspectResultBundleService` zmieniają sygnatury na nowe typy domenowe. `TestService.swift:1479` traci sentinel, zyskuje `nil`. Test-first dla `TestService`/`ShardMatrixOutputService`, bo to zmiana obserwowalnego kontraktu (JSON wyjściowy pustego shard matrix musi pozostać identyczny — regresja na istniejących testach snapshot/golden, jeśli istnieją, nieweryfikowane w tej sesji).

**Faza 5 — Weryfikacja grep + usunięcie `#if DEBUG extension Components.Schemas.*` z `ListTestCaseRunsService.swift:97-156`.**
Testowe fabryki (`Components.Schemas.TestCaseRunsList.test(...)`, `:98-119` i `Components.Schemas.TestCaseRun.test(...)`, `:121-155`) przenoszą się na `ServerTestCaseRunsList.test(...)`/`ServerTestCaseRun.test(...)` w tym samym pliku lub obok nowego typu — dziś rozszerzają typ biblioteki wprost, co jest tym samym przeciekiem w kodzie testowym.

---

## Ograniczenia tej sesji

- **Lokalizacja istniejących testów dla `ServerBuild`/innych `TuistServer/Models/*` nie została zweryfikowana** w tej sesji — Faza 1 zakłada wzorowanie się na nich, ale plik testowy nie został odczytany; przed implementacją należy go zlokalizować (`grep -rl "ServerBuild" cli/Tests`).
- **Pełna zawartość `TuistServer/Models/` (19 plików) nie została przeczytana** — tylko `ServerBuild.swift` w całości; inne pliki (`ServerCacheArtifact.swift`, `ServerPreview.swift`, itd.) zostały potraktowane jako precedens na podstawie nazw i jednego przeczytanego przykładu, nie zweryfikowane każdy z osobna.
- **Kandydat C (Stripe) nie został sklasyfikowany** — tylko policzony (KROK 1), celowo pozostawiony jako przyszły kandydat, nie żeby uniknąć fałszywej pewności bez przeczytania treści plików.
- **Testy golden/snapshot dla pustego shard matrix (`TestService.swift:1479`) nie zostały zlokalizowane** — Faza 4 zakłada ich istnienie jako siatki bezpieczeństwa dla zmiany zachowania z sentinela na `nil`; jeśli nie istnieją, powinny powstać przed refaktorem tej ścieżki (test-first wymaga tego i tak).
- Ten plan **nie obejmuje** Kandydata A (`ExAws.S3`, serwer) poza jego rolą porównawczą w KROK 2 — to osobny, mniejszy pod względem rozsmarowania refaktor (ujednolicenie `Tuist.Registry.S3`/`sync_cursor.ex`/`lock.ex` pod `Tuist.Storage`), niewymagający zmian po stronie klienta.
