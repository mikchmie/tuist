# Structure: warstwy, cykle i testowalność w `cli/` (Tuist CLI, Swift)

Analiza struktury pakietów Swift w repo, oparta na `swift package dump-package` i skrzyżowana z danymi aktywności z [`artifact-1-territory.md`](./artifact-1-territory.md). Zakres: wyłącznie moduły Swift (`cli/`, `swifterpm/`, `assets/`) — bez serwera Elixir, cache'a, frontendów itd.

## Metodologia

Trzy manifesty w repo zdumpowane poleceniem `swift package dump-package`:

- `./Package.swift` (root, pakiet `tuist`) — 98 targetów, 50 zależności zewnętrznych, 21 produktów. Dump zakończony sukcesem.
- `swifterpm/Package.swift` — 3 targety, 5 zależności zewnętrznych. Dump zakończony sukcesem.
- `assets/Package.swift` — **dump zakończony błędem**: `swift-tools-version: 3.1.0`, niewspierana przez obecny toolchain. Plik zawiera tylko `import PackageDescription`, bez definicji pakietu (patrz sekcja e).

Na podstawie JSON-a z roota zbudowano graf: węzły = targety, krawędzie = deklaracje `dependencies:` (`target`, `byName`, `product`). Dalsze kroki:

- **Warstwy architektoniczne** — topologiczna głębokość każdego targetu (`layer(n) = 0` jeśli `fan_out(n) == 0`, inaczej `1 + max(layer(dep))` po wszystkich zależnościach) + rola wynikająca z konwencji nazewnictwa (`*Command`, agregatory, root kompozycji, wsparcie testowe).
- **Cykle** — algorytm Tarjana (silnie spójne składowe) na pełnym grafie 98 węzłów / 526 krawędzi.
- **Testowalność** — ukierunkowane `grep` w gorących katalogach z sekcji (c)/(d) `artifact-1-territory.md`: `static let shared`, `static var`, `FileManager.default`, `Date()`, `Process`/shell-out, gęstość `@Mockable`/mocków w testach, sygnatury `init(...)`.

## a) Graf zależności — podstawowe liczby (pakiet root)

| Metryka | Wartość |
|---|---|
| Targety | 98 (76 `regular`, 18 `test`, 4 `executable`) |
| Wewnętrzne krawędzie (target ↔ target) | 526 |
| Zależności zewnętrzne | 50 (41 zakres semver, 7 `exact`, 2 lokalne bez wersji) |
| `swift-tools-version` | 6.1.0 |
| Platforma | macOS 15.0 |

Top 5 wg fan-in (liczba targetów zależnych): `TuistSupport` 38, `TuistServer` 36, `TuistEnvironment` 35, `TuistLogging` 31, `TuistConstants` 27. Najwyższy fan-out: `TuistKit` — 54 zależności, najwyższy w repo.

## b) Warstwy architektoniczne (wyznaczone z topologii + konwencji nazewnictwa)

| Warstwa | Głębokość topologiczna | Rola | Przykładowe targety |
|---|---|---|---|
| 0 — Fundament | 0–1 | Czyste utility, brak logiki domenowej | `TuistConstants`, `TuistEnvironment`, `TuistLogging`, `TuistAlert`, `TuistEnvKey`, `TuistConfig` |
| 1 — Model domeny | 0–2 | Typy reprezentujące projekt Xcode | `XcodeGraph`, `XcodeGraphMapper`, `XcodeMetadata`, `ProjectDescription` |
| 2 — Usługi platformowe | 3–4 | Dostęp do świata zewnętrznego (FS, OIDC, Android) + `TuistSupport` jako fasada | `TuistRootDirectoryLocator`, `TuistOIDC`, `TuistSupport` |
| 3 — Rdzeń i integracje | 5–6 | Logika domenowa + integracje (Git, CI, xcresult) | `TuistCore`, `TuistHTTP`, `TuistLoader`, `TuistHasher`, `TuistScaffold` |
| 4 — Usługi aplikacyjne | 7–9 | Duże silniki funkcjonalne | `TuistServer`, `TuistConfigLoader`, `TuistPlugin`, `TuistCache`, `TuistGenerator`, `TuistDependencies`, `TuistCAS` |
| 5 — Komendy/Features | fan-in ≈0–3 | Jedna komenda CLI = jeden target | 20 targetów `*Command` |
| 6 — Root kompozycji | najwyżej | Spina komendy w binarkę | `tuist`, `tuistbenchmark`, `tuistfixturegenerator` |

Oś poprzeczna (nie warstwa): wsparcie testowe (`TuistTesting`, `TuistEnvironmentTesting`, `TuistNooraTesting`, `TuistAcceptanceTesting` + 18 targetów `*Tests`).

**Anomalia — `TuistKit` i `TuistExtension`.** Oba topologicznie leżą *nad* warstwą komend (fan-out 54 i 6), ale semantycznie powinny leżeć pod nią lub nie istnieć jako osobna warstwa — to pozostałość sprzed podziału na `*Command`. W repo współistnieją dwa modele warstwowania: "czysty" (Command → Usługi aplikacyjne → Rdzeń → Fundament, np. `TuistCacheCommand`, `TuistBazelCommand`) i "stary" (Command → `TuistKit` → prawie wszystko, np. `TuistTestCommand`, `TuistBuildCommand`, `TuistGenerateCommand`, `TuistRunCommand`, `TuistInspectCommand`, `TuistShareCommand`, `TuistAcceptanceTesting`).

## c) Weryfikacja granic warstw

- **Warstwy 0–3 → Warstwa 4: 0 naruszeń** na 46 sprawdzonych targetach (potwierdzone programowo na pełnym grafie 526 krawędzi). SwiftPM strukturalnie to wymusza, ale zweryfikowano, nie założono.
- **Warstwa 4 nie jest płaska** — ma wewnętrzną hierarchię 3 poziomów: `TuistServer`/`TuistConfigLoader`/`TuistPlugin` (topo 7) → `TuistCache`/`TuistGenerator`/`TuistDependencies` (topo 8) → `TuistCAS` (topo 9).
- **`TuistGenerator` → `TuistServer`** — bezpośrednia krawędź między dwoma niezależnie najaktywniejszymi obszarami roku (Q2 refaktor grafu projektu — 131 zmian; Q4 `TuistServer`/Services — 116 zmian, najwyższe w roku).
- **`TuistDependencies` → `TuistPlugin` → `TuistScaffold`/`TuistHTTP`** — "cichy pasażer": `TuistDependencies` ma fan-in 1 (tylko `TuistKit`) i nie występuje w żadnym top-10 z mapy terytorium, ale łańcuchowo zależy od miejsc, które mogą się zmienić bez jego udziału.
- **`TuistCAS` → `TuistServer` + `TuistCache`** — szczyt Warstwy 4 zależy od dwóch pozostałych członków tej samej nominalnej warstwy.

## d) Cykle

**Zero cykli formalnych.** Algorytm Tarjana na pełnym grafie (98 węzłów, 526 krawędzi) zwraca 98 silnie spójnych składowych, wszystkie rozmiaru 1. SwiftPM strukturalnie uniemożliwia cykle na poziomie deklaracji `dependencies:` — potwierdzone, nie założone.

Realne ryzyko leży w **efektywnych cyklach / gęstym sprzężeniu**, nie w formalnych cyklach:

| Wzorzec | Dowód | Dlaczego to działa jak cykl |
|---|---|---|
| `TuistKit` jako hub | 7 targetów (`tuist`, `TuistBuildCommand`, `TuistGenerateCommand`, `TuistTestCommand`, `TuistShareCommand`, `TuistRunCommand`, `TuistInspectCommand`, `TuistAcceptanceTesting`) zależy wprost od `TuistKit` (fan-out 54) | Zmiana w `TuistKit` ryzykuje przetestowaniem niemal wszystkich aktywnych komend naraz |
| `TuistExtension` jako drugi hub | Jeden target zależy od 6 aktywnych obszarów: `TuistCache`, `TuistCore`, `TuistGenerator`, `TuistHasher`, `TuistServer`, `XcodeGraph` | Zmiana w dowolnym z sześciu może wymusić dostosowanie `TuistExtension` |
| Diament `XcodeGraph`/`XcodeGraphMapper`/`XcodeMetadata` | `TuistCore` zależy jednocześnie bezpośrednio od `XcodeGraph` i od `XcodeMetadata`, a `XcodeMetadata` samo zależy od `XcodeGraph` | Zmiana typu w `XcodeGraph` może wymagać koordynacji w 3 miejscach naraz |
| Zduplikowany fundament `TuistCacheCommand`/`TuistBazelCommand` | Niemal identyczny zestaw zależności (`TuistServer`, `TuistConfigLoader`, `TuistCAS`, `TuistAlert`, `TuistHTTP`...) bez wspólnego kodu | Poprawka fundamentu musi być weryfikowana osobno w obu miejscach |

## e) Dług i anomalie w manifestach

- **`assets/Package.swift` — martwy manifest.** `swift-tools-version: 3.1.0` (niewspierany), zawiera tylko `import PackageDescription`, ostatnio dotknięty w 2020. Katalog `assets/` to w praktyce zbiór statycznych obrazków (favicon, loga), nie realny moduł Swift. Kandydat do usunięcia.
- **7 zależności root przypiętych `exact`** (bez zakresu semver, nie dostają automatycznych patchy): `apple.swift-protobuf` (1.38.1), `leif-ibsen.SwiftECC` (5.5.0), `stencilproject.Stencil` (0.15.1), `swiftGen.StencilSwiftKit` (2.10.1), `swiftGen.SwiftGen` (6.6.2), `swiftlang.swift-subprocess` (0.4.0), `tuist.GraphViz` (0.4.2).
- **`swifterpm/` — osobna filozofia wersjonowania.** Wszystkie 5 zależności przypięte `exact` (kontrast z rootem: 41/50 na zakresach). Zero sprzężenia z pakietem root (fan-in = 0 w obu kierunkach) — to faktycznie osobny produkt we wspólnym repo.

## f) Ryzyka testowalności (moduły Swift)

Konwencja DI (protokoły + `@Mockable`) jest wszechobecna w CLI, więc nic nie jest "niemożliwe do zmockowania" — problem leży w liczbie współpracowników na serwis i w miejscach opakowujących realny proces zewnętrzny/system plików.

| Plik/moduł | Sygnał ryzyka | Rekomendowana strategia |
|---|---|---|
| `TuistKit/Services/TestService.swift` (#1 najgorętszy plik `cli/` — 73 zmiany) | 17 wstrzykiwanych protokołów w `init`; test (`TestServiceTests.swift`, 7002 linii) deklaruje 24 osobne mocki | Unit — pilny kandydat do rozbicia na mniejsze serwisy; boilerplate mocków rośnie z każdą zmianą |
| `TuistLoader/Loaders/PackageInfoLoader.swift`, `ManifestLoader.swift` (Q4 hot: `PackageInfoMapper.swift` — 61 zmian) | Realnie shellują do `swift package dump-package`; wzorzec `fileSystem: FileSysteming = FileSystem()` jako domyślny argument | Integracyjny — `PackageInfoMapperTests.swift` już testuje samo mapowanie na fixture'ach JSON, ale sam loader wymaga realnego toolchaina |
| Gorące obszary Swift ogółem (`TuistKit`, `TuistServer`, `TuistGenerator`, `TuistLoader`, `TuistCore`, `XcodeGraph`) | 94 wystąpienia `static var` (po odfiltrowaniu oczywistych false-positive) | Wymaga ręcznego przeglądu — potencjalny współdzielony stan między testami |
| `TuistServer/Services` (Q4 najgorętsze w roku — 116 zmian) | 91 plików, 431 wystąpień `init(`, ale 0 bezpośrednich konstrukcji `Client(serverURL:...)` (klient wstrzykiwany centralnie) | Niezweryfikowane, czy pojedyncze serwisy nie powielają wzorca „god service” z `TestService` |
| `XcodeGraph` (cały moduł) | 75 plików modelu importuje tylko `Foundation`+`Path`, zero typów platformowych | Niskie ryzyko — czysty model wartości, unit bez zastrzeżeń |

## g) Otwarte pytania / co dalej

- Cykle na poziomie plików/importów **wewnątrz** jednego targetu (np. w `TuistKit/Services` vs `TuistKit/Commands`) — poza zasięgiem `dump-package`, który widzi tylko granice targetów.
- Ranking liczby wstrzykiwanych protokołów per plik w `TuistKit/Services` i `TuistServer/Services` — sprawdzić, czy wzorzec „god service” z `TestService` powtarza się gdzie indziej.
- Czy `TestServiceTests.swift` ma wspólny builder/fixture do konstrukcji 24 mocków, czy każdy test powtarza cały setup.
- Czy dla `PackageInfoLoader`/`ManifestLoader` istnieją testy inne niż testy samego mapowania (`PackageInfoMapperTests`) — czy pokrycie faktycznie sięga warstwy wywołania procesu.
- Czy warto formalnie rozbić „Warstwę 4” na nazwane pod-warstwy (np. „4a — klienci”, „4b — orkiestracja”), żeby wewnętrzna hierarchia (sekcja c) była widoczna, a nie ukryta w jednym worku.
