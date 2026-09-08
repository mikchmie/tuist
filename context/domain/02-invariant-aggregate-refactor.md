---
title: Invariant Aggregate Refactor — Test Run Status Integrity
created: 2026-09-08
type: refactor-plan
---

# Plan refaktoru: agregat-strażnik dla statusu Test Run

> Ten dokument to **PLAN**, nie implementacja. Żaden plik produkcyjny nie został zmodyfikowany w trakcie jego powstawania. Kontynuuje `context/domain/01-domain-distillation.md` (destylacja domenowa `tuist test`) na tym samym bounded contexcie, ale idzie głębiej: wybiera JEDEN niezmiennik i projektuje jego strażnika.

---

## KROK 0 — Odkrycie kontekstu

**PRD/tech-stack:** `context/foundation/` nadal nie zawiera `prd.md` ani `tech-stack.md` (tylko `README.md` z konwencją katalogu — zweryfikowane w tej sesji, `context/foundation/README.md:1-15`). Brak wizji produktu spisanej formalnie potwierdza się jako trwałe ograniczenie tego repo, nie przeoczenie poprzedniej sesji.

**Punkt startowy:** `context/domain/01-domain-distillation.md`, w szczególności KROK 3 (kandydaci na agregaty) i KROK 5 (ranking refaktoru), które już zidentyfikowały ten sam obszar — `tuist test` / analitykę testów — jako gęsty w niezmienniki i słabo egzekwowany w kilku miejscach. Ta sesja **nie przyjmuje ślepo** rankingu z KROK 5 tamtego dokumentu; poniżej (KROK 1-2) budowana jest niezależna lista niezmienników i osobna klasyfikacja wg kryteriów tego zadania (core / rozsmarowanie / egzekwowalność), a rozbieżności z poprzednim rankingiem są jawnie odnotowane.

**Stack obszaru** (zweryfikowany ponownie w tej sesji): CLI Swift (`cli/Sources/TuistKit/Services/TestService.swift`) → API Elixir/Phoenix (`server/lib/tuist_web/controllers/api/{tests,runs,shards,analytics}_controller.ex`, walidacja `OpenApiSpex`/`TuistWeb.Plugs.CastAndValidate`) → domena (`server/lib/tuist/tests.ex`, `server/lib/tuist/shards.ex`) → ClickHouse (`Tuist.IngestRepo`, tabele `test_runs`, `shard_runs`) → LiveView dashboard (`server/lib/tuist_web/live/tests_live.ex`, `test_run_live.ex`). Wszystkie cytaty poniżej są odczytane bezpośrednio w tej sesji na bieżącym stanie drzewa (`fd71de4f53`), chyba że jawnie oznaczone jako pochodzące z `01-domain-distillation.md`.

---

## KROK 1 — Identyfikacja niezmienników biznesowych

| # | Niezmiennik | Źródło / cytat |
|---|---|---|
| N1 | Scalony status `Test Run` musi zawsze należeć do zbioru `{success, failure, skipped, in_progress, processing, failed_processing}`. | `server/lib/tuist/tests/test.ex:106` (`validate_inclusion(:status, [...])`, zweryfikowane w tej sesji) |
| N2 | Status scalonego, shardowanego runu jest terminalny (`success`/`failure`/`failed_processing`) tylko gdy wszystkie shardy zaraportowały LUB jakikolwiek shard zgłosił terminalną porażkę; w przeciwnym razie run zostaje `in_progress`. | `server/lib/tuist/tests.ex:839-852` (`merged_shard_status/3`, komentarz i implementacja, zweryfikowane w tej sesji) |
| N3 | Run zawieszony w `in_progress` dłużej niż 6h jest wymuszany na `failure` (run zawsze osiąga stan terminalny). | `server/lib/tuist/tests.ex:4404-4452` (`expire_stale_in_progress_test_runs/0`, zweryfikowane w tej sesji) |
| N4 | `shard_runs` jest jedynym źródłem prawdy o tym, do którego runu raportują shardy danego planu; pierwszy zaraportowany shard rezerwuje to mapowanie. | `server/lib/tuist/tests.ex:618-622` (komentarz + `mapped_shard_test_run_id/2`, zweryfikowane w tej sesji) |
| N5 | `ShardPlan.granularity` ∈ `{module, suite}`. | `server/lib/tuist/shards/shard_plan.ex:27-47` (zweryfikowane w tej sesji) |
| N6 | Niepowodzenie testu jest "połykane" (build kontynuuje) wtedy i tylko wtedy, gdy WSZYSTKIE nieudane testy są w kwarantannie. | `cli/Sources/TuistKit/Services/TestService.swift:1391` (zweryfikowane w tej sesji) |
| N7 | `shard_index` raportowanego shardu musi mieścić się w `0..(shard_count - 1)` planu, do którego należy. | Wywnioskowane z modelu (`shard_plan.shard_count`, `server/lib/tuist/tests.ex:612`) — **nigdzie explicite nie egzekwowane, patrz KROK 3** |

Niezmienniki N1, N2, N4 i N7 dotyczą **tego samego agregatu koncepcyjnego** — scalonego Test Run zbudowanego z raportów shardów — i są ze sobą sprzężone: N2 (reguła scalania) operuje na danych, których poprawność zależy od N1 (poszczególne statusy shardów są prawidłowe) i N7 (indeksy shardów są prawidłowe). To sprzężenie jest kluczowe dla KROK 2.

---

## KROK 2 — Klasyfikacja i wybór #1

Trzy osie oceny (wg zadania): **(a) core** — jak bardzo niezmiennik jest sensem produktu; **(b) rozsmarowanie** — w ilu warstwach/plikach żyje; **(c) egzekwowalność** — enforced / tylko deklarowany / naruszalny.

| Niezmiennik | (a) Core | (b) Rozsmarowanie | (c) Egzekwowalność |
|---|---|---|---|
| **N1+N2+N4+N7 (status scalonego Test Run)** | **Bardzo wysoki** — to dokładnie to, co PR-check/dashboard czyta, by zdecydować pass/fail. Cała obietnica "actionable insights" (`README.md:28`, cyt. w `01-domain-distillation.md:57`) stoi na tym, że status jest wiarygodny. | **Bardzo wysokie** — OpenAPI schema (granica HTTP) → Ecto changeset `Test` (domena) → schemat `ShardRun` (BRAK changesetu) → 4 niezależne ścieżki zapisu w `tests.ex` → ClickHouse (brak CHECK constraints) → LiveView dashboard (renderowanie). 6 różnych warstw/plików. | **Naruszalny w praktyce** — patrz KROK 3: 3 z 4 ścieżek zapisu `Test` omijają walidację, `ShardRun` nie ma żadnej walidacji w ogóle, dashboard cicho "połyka" nieznany status jako sukces. |
| N3 (stale-run reaper) | Wysoki — gwarantuje, że run zawsze osiąga stan terminalny. | Niskie — jedna funkcja, jedna ścieżka. | Częściowo naruszalny (ta sama `insert_all`, patrz KROK 3), ale ryzyko wąskie: literał `"failure"` jest stały w kodzie, nie obliczany dynamicznie. |
| N5 (granularity) | Średni — techniczny parametr planowania, nie widoczny wprost w README. | Niskie — jeden changeset, jedna ścieżka tworzenia (zweryfikowane w tej sesji: `shard_plan.ex` jest jedynym miejscem walidującym `granularity`, a `Shards.create_shard_plan/2` w `shards.ex:32` jest jedynym wywołującym). | W pełni egzekwowany. |
| N6 (kwarantanna) | Bardzo wysoki — nazwana wprost przewaga produktu. | Niskie — jedno wywołanie decyzyjne (`TestService.swift:1391`), sama predykatowa logika żyje w jednym pliku (`TestQuarantineService.swift`). | **Poprawnie zaimplementowany i częściowo przetestowany** — w tej sesji zweryfikowano, że `TestQuarantineServiceTests.swift:167-304` testuje samą funkcję `onlyQuarantinedTestsFailed` bezpośrednio (true/false, w tym przypadki mieszane). Luka jest węższa niż sugerował `01-domain-distillation.md:96`: to integracja w `TestServiceTests.swift` zawsze stubuje wynik na `false` (zweryfikowane w tej sesji: `TestServiceTests.swift:160-161,4115,4217,4471` — wszystkie `willReturn(false)`), więc gałąź "połknij awarię" (`TestService.swift:1391-1393`) nie ma pokrycia integracyjnego. To realne ryzyko regresji, ale nie jest to dziś **żywa luka w produkcji** — logika działa poprawnie, tylko nie jest chroniona przed przyszłą zmianą. |
| N7 (zakres shard_index) | Średni-wysoki — błędny indeks psuje mapowanie N4. | Niskie — jedno miejsce potencjalnej walidacji. | Brak walidacji w ogóle (patrz KROK 3), ale dziś jedyny producent to zaufany klient CLI. |

**Wybór #1: N1+N2+N4+N7 — integralność statusu scalonego Test Run.**

**Uzasadnienie:** to jedyny niezmiennik, który jest jednocześnie najbardziej core (dosłownie definiuje, co znaczy "test przeszedł") I najsłabiej egzekwowany (rozsiany na 6 warstw, z których połowa nie ma żadnej bramki walidacyjnej). N6 (kwarantanna) jest równie core, ale jest dziś poprawnie zaimplementowany — ryzyko jest przyszłe (regresja bez testu), nie bieżące (naruszenie na produkcji). N1-grupa ma **żywe, dziś istniejące** dziury: `ShardRun` nie ma żadnego changesetu, a 3 z 4 ścieżek zapisu `Test` idą przez `insert_all` z pominięciem walidacji. To odróżnia ten wybór od rankingu `01-domain-distillation.md:121-125`, który postawił kwarantannę na #1 kryterium "Core + brak testu"; tu kryterium jest "Core + brak egzekwowania w kodzie", co przesuwa wybór na status scalonego runu (co zresztą tamten dokument sam zidentyfikował jako Agregat 1+2, `01-domain-distillation.md:68-90`, ale ocenił Agregat 1 jako "EGZEKWOWANY" — ta sesja pokazuje, że ta ocena była niepełna, bo nie objęła `ShardRun`, patrz KROK 3).

---

## KROK 3 — Diagnoza wybranego niezmiennika

### Mapa warstw i ich rola dzisiaj

```
Klient (CLI/Bazel) → [A] OpenAPI/Plug walidacja → [B] Tuist.Tests (logika domenowa)
                                                        ├─ [C] Test.create_changeset (deklaracja N1)
                                                        ├─ [D] ShardRun (BRAK deklaracji)
                                                        └─ [E] merged_shard_status/compute_final_shard_status (logika N2)
                                                             → [F] IngestRepo (ClickHouse, brak CHECK constraints)
                                                                  → [G] tests_live.ex (dashboard, renderowanie)
```

### [A] Granica HTTP — częściowo chroni, ale tylko wartości bezpośrednio od klienta

`cli/Sources/TuistServer/OpenAPI/server.yml:190-198` deklaruje `status` jako enum 5-wartościowy (`success, failure, skipped, processing, failed_processing` — bez `in_progress`, bo to wartość czysto serwerowa). To samo pole request body zawiera `shard_index`/`shard_plan_id` (`server.yml:170-180`), więc jest to wspólny schemat dla runu pojedynczego i raportu shardu. `server/lib/tuist_web/controllers/api/runs_controller.ex:26` podłącza `TuistWeb.Plugs.CastAndValidate` przed `def create/2` (`runs_controller.ex:780`) — **zweryfikowane w tej sesji**: klient wysyłający nieprawidłowy string w `status` jest odrzucony, zanim dane dotrą do `Tuist.Tests`.

**To jest walidacja DTO na granicy transportu, nie walidacja agregatu domenowego.** Nie chroni: (1) wartości obliczanych wewnątrz serwera (`merged_status`, status z reapera), (2) żadnego przyszłego drugiego producenta, który ominie ten konkretny endpoint/plug, (3) samego faktu, że dane w ClickHouse mogą być zapisane przez ścieżkę, która tej walidacji nigdy nie przechodzi (patrz [D], [E] niżej).

### [C] `Test.create_changeset` — deklarowany, ale egzekwowany tylko na 1 z 4 ścieżek zapisu

`test.ex:106`: `validate_inclusion(:status, ["success", "failure", "skipped", "in_progress", "processing", "failed_processing"])`.

| Ścieżka zapisu do `test_runs` | Przechodzi przez `Test.create_changeset`? | Dowód |
|---|---|---|
| `create_new_test/3` — nowy, nieshardowany run (i pierwszy shard planu) | **TAK** | `tests.ex:514-516`: `%Test{} \|> Test.create_changeset(attrs) \|> IngestRepo.insert()` |
| `create_or_update_sharded_test/1` — scalenie kolejnego shardu w istniejący run | **NIE** | `tests.ex:721-727`: `update_attrs` budowany jako gołą mapą (`Map.from_struct/1` + `Map.drop/2`), potem `IngestRepo.insert_all(Test, [update_attrs])` — `insert_all` nie wywołuje żadnego changesetu |
| `mark_test_run_as_flaky/2` — oznaczenie runu jako flaky w tle | **NIE** | `tests.ex:885-891`: identyczny wzorzec (`Map.from_struct` → `insert_all`) |
| `expire_stale_in_progress_test_runs/0` — reaper 6h | **NIE** | `tests.ex:4444-4452`: identyczny wzorzec |

**Konsekwencja:** deklaracja "status ∈ 6 wartości" trzyma się wyłącznie poprawności funkcji `merged_shard_status/3`/`compute_final_shard_status/1` (`tests.ex:845-860`) i literału `"failure"` w reaperze — nie chroni jej żaden typ ani baza danych. ClickHouse (`Ch` types, `LowCardinality(String)`) to optymalizacja pamięciowa, nie constraint — nie ma odpowiednika `CHECK` z Postgresa.

### [D] `ShardRun` — brak jakiejkolwiek deklaracji, nie tylko brak egzekwowania

`server/lib/tuist/shards/shard_run.ex:1-16` — cały plik. Brak `import Ecto.Changeset`, brak funkcji `create_changeset/2`, `status` to gołe pole `Ch, type: "LowCardinality(String)"` (linia 11) bez żadnego ograniczenia wartości.

`insert_shard_run/7` (`tests.ex:862-877`) zapisuje `status: status` wprost z parametru pochodzącego od klienta (`shard_status = Map.get(attrs, :status, "success")`, `tests.ex:615`) — dla zaufanego klienta CLI ta wartość akurat przeszła przez granicę [A], ale **domena sama w sobie nie ma żadnej drugiej linii obrony**, gdyby [A] kiedyś nie zadziałała (np. inny endpoint, migracja danych, ręczny skrypt operacyjny).

To jest różnica jakościowa względem `Test`: `Test` ma DEKLAROWANY, ale omijany niezmiennik; `ShardRun` **nie deklaruje niezmiennika w ogóle** — nie ma go czego omijać.

### [E] Logika scalania cicho "połyka" nieznany status jako sukces

`tests.ex:854-859`:
```elixir
defp compute_final_shard_status(latest_statuses) do
  cond do
    "failed_processing" in latest_statuses -> "failed_processing"
    "failure" in latest_statuses -> "failure"
    true -> "success"
  end
end
```

Gałąź `true -> "success"` (linia 858) jest domyślna — jeśli `latest_statuses` zawiera cokolwiek poza dwoma rozpoznanymi literałami porażki (literówka wprowadzona przy przyszłej zmianie, nowa wartość statusu dodana do enuma bez aktualizacji tej funkcji, uszkodzone dane), scalony run zostaje uznany za `"success"` **bez żadnego ostrzeżenia, wyjątku czy logu**. To wprost narusza wymaganą w tym zadaniu zasadę fail-fast — nielegalny/nieoczekiwany stan nie zatrzymuje operacji, tylko cicho przechodzi dalej jako najbardziej optymistyczny możliwy wynik.

### [B] Kruche dopasowanie wzorca zamiast strażnika — `MatchError` zamiast nazwanego błędu domenowego

`tests.ex:611`: `{:ok, shard_plan} = Shards.get_shard_plan(shard_plan_id)`. `Shards.get_shard_plan/1` (`shards.ex:100-105`) zwraca `{:error, :not_found}` dla nieistniejącego planu (zweryfikowane w tej sesji). Raport shardu odwołujący się do planu, który wygasł/nie istnieje, dziś **crashuje** (`MatchError`) zamiast zwrócić kontrolowaną odpowiedź 4xx z nazwanym powodem. To jest "fail-fast" w sensie "zatrzymuje", ale nie w sensie "czytelny błąd domenowy" — dokładnie to, co KROK 4 ma naprawić.

### [G] Dashboard — brak walidacji przy odczycie, cichy fallback koloruje anomalię jako sukces

`server/lib/tuist_web/live/tests_live.ex:322-328`:
```elixir
color =
  cond do
    run.status == "success" -> "var:noora-chart-primary"
    run.status == "failure" -> "var:noora-chart-destructive"
    run.status == "skipped" -> "var:noora-chart-warning"
    true -> "var:noora-chart-primary"
  end
```
Gałąź domyślna (linia 327) używa **tego samego koloru** (`var:noora-chart-primary`) co jawna gałąź `"success"` (linia 324). Każdy nierozpoznany status (włącznie z `in_progress`/`processing`/`failed_processing`, które w tym konkretnym widoku są już odfiltrowane przez `tests_live.ex:294-296`, ale NIE są odfiltrowane gdziekolwiek indziej w kodzie w sposób, który gwarantowałby, że tu nigdy nie dotrą) zostałby narysowany jako "zielony" punkt na wykresie. Dodatkowo `failed_test_runs_count`/`passed_test_runs_count` (`tests_live.ex:340-341`) liczą przez dokładne dopasowanie stringów — nierozpoznany status nie trafia do ŻADNEGO licznika, znikając bezszelestnie z obu sum, mimo że nadal jest wyświetlany na wykresie jako "pass"-kolorowany punkt danych. `test_status_label/2` (`tests_live.ex:498`: `String.capitalize(status)`) renderuje dowolny string bez walidacji.

Klient (przeglądarka/LiveView) jest tu jedynym miejscem, które w ogóle "reaguje" na wartość statusu — i reaguje źle: nie ostrzega, tylko dezinformuje w stronę "wszystko OK".

### Sprawdzone i wykluczone: producent Bazel (koryguje otwarte pytanie z `01-domain-distillation.md:131-133,143`)

`server/lib/tuist/bazel/test_report_ingestor.ex:108-131` (`test_attributes/4`) **nigdy nie ustawia `:shard_plan_id`** w atrybutach przekazywanych do `Tests.create_test/1` — więc zawsze trafia do `create_new_test/3`, jedynej w pełni zwalidowanej ścieżki (patrz [C] wyżej). Status obliczany przez `test_status/2` (`test_report_ingestor.ex:136-140`) zwraca wyłącznie `"failure"`/`"skipped"`/`"success"` — podzbiór dozwolonych wartości. **Wniosek zweryfikowany bezpośrednio w tej sesji: ścieżka Bazel nie stanowi dziś ryzyka dla tego niezmiennika**, w przeciwieństwie do tego, co `01-domain-distillation.md` zostawiło jako otwarte pytanie.

### Podsumowanie diagnozy

| Warstwa | Rola wobec N1/N2/N4/N7 | Status |
|---|---|---|
| OpenAPI/Plug (A) | Waliduje `status` klienta na 1 endpoincie | ✅ dla bezpośredniego wejścia klienta, ❌ dla wartości obliczanych wewnątrz serwera |
| `Test.create_changeset` (C) | Deklaruje N1 | ✅ na 1/4 ścieżek zapisu, ❌ na pozostałych 3/4 |
| `ShardRun` schema (D) | Powinna deklarować odpowiednik N1 dla statusu shardu + N7 dla indeksu | ❌ nie istnieje w ogóle |
| `merged_shard_status`/`compute_final_shard_status` (E) | Egzekwuje N2 | ✅ dla znanych wartości, ❌ cicho połyka nieznane jako "success" |
| `Shards.get_shard_plan` call site (B) | Powinna egzekwować "plan istnieje" | ⚠️ zatrzymuje (fail-fast), ale przez nieobsłużony `MatchError`, nie nazwany błąd domenowy |
| ClickHouse (F) | Ostatnia linia obrony na poziomie storage | ❌ brak CHECK constraints |
| Dashboard (G) | Powinien być odporny na anomalie w danych | ❌ cichy fallback koloruje anomalię jako sukces |

---

## KROK 4 — Projekt agregatu-strażnika

### Wybór granicy agregatu

Agregatem jest **scalony Test Run** — encja `Tuist.Tests.Test` (tabela `test_runs`) wraz z jej podrzędnymi raportami shardów (`Tuist.Shards.ShardRun`, tabela `shard_runs`), traktowanymi jako jedna spójna całość wyłącznie dla potrzeb egzekwowania niezmienników N1/N2/N4/N7. `ShardRun` **nie** staje się osobnym agregatem — jest wewnętrznym stanem agregatu `TestRun`, tak jak dziś jest wewnętrznym szczegółem implementacji `create_or_update_sharded_test/1`. To zgodne z regułą DDD "jedna transakcja biznesowa = jeden agregat": klient nigdy nie modyfikuje `ShardRun` niezależnie od decyzji o statusie runu.

Nazwa proponowanego modułu-strażnika: **`Tuist.Tests.TestRunAggregate`**. Nie zmieniam nazwy istniejącego schematu `Tuist.Tests.Test` (ryzyko przemianowania osobno od tego refaktoru, tabela `test_runs` pozostaje bez zmian) — `TestRunAggregate` staje się **jedynym** modułem uprawnionym do wołania `IngestRepo.insert/insert_all` na `Test` i `ShardRun`.

### Nowy changeset: `ShardRun.create_changeset/2` (dziś nie istnieje)

```elixir
defmodule Tuist.Shards.ShardRun do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_statuses ~w(success failure skipped processing failed_processing)

  # ...pola bez zmian...

  def create_changeset(shard_run \\ %__MODULE__{}, attrs) do
    shard_run
    |> cast(attrs, [:shard_plan_id, :project_id, :test_run_id, :shard_index, :status, :duration, :ran_at, :inserted_at])
    |> validate_required([:shard_plan_id, :project_id, :test_run_id, :shard_index, :status, :ran_at, :inserted_at])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:shard_index, greater_than_or_equal_to: 0)
  end
end
```

`@valid_statuses` celowo pomija `in_progress` — tak jak dziś OpenAPI enum (`server.yml:190-198`), bo pojedynczy shard nigdy nie jest "w toku" z perspektywy własnego raportu.

### Metody agregatu (preconditions + błędy domenowe zamiast cichej aktualizacji)

```elixir
defmodule Tuist.Tests.TestRunAggregate do
  @moduledoc """
  Jedyny moduł uprawniony do zapisu `Test`/`ShardRun`. Każda ścieżka zapisu
  przechodzi przez changeset; nielegalny stan zwraca nazwany błąd zamiast
  ciszej korekty.
  """

  alias Tuist.Tests.Test
  alias Tuist.Shards.ShardRun
  alias Tuist.Shards
  alias Tuist.Tests.Errors.{ShardPlanNotFound, ShardIndexOutOfRange, InvalidStatus}

  @doc "Tworzy nowy, nieshardowany Test Run. Zastępuje dzisiejsze create_new_test/3 dla przypadku bez planu."
  @spec start(map()) :: {:ok, Test.t()} | {:error, Ecto.Changeset.t()}
  def start(attrs)

  @doc """
  Rejestruje raport pojedynczego shardu i zwraca zaktualizowany stan
  scalonego runu. Precondition: shard_plan istnieje i shard_index mieści
  się w 0..shard_count-1.
  """
  @spec report_shard(shard_plan_id :: Ecto.UUID.t(), map()) ::
          {:ok, Test.t()}
          | {:error, ShardPlanNotFound.t()}
          | {:error, ShardIndexOutOfRange.t()}
          | {:error, Ecto.Changeset.t()}
  def report_shard(shard_plan_id, attrs) do
    with {:ok, shard_plan} <- fetch_shard_plan(shard_plan_id),
         :ok <- validate_shard_index(attrs, shard_plan),
         {:ok, shard_run_changeset} <- build_shard_run_changeset(shard_plan, attrs),
         {:ok, merged_test_changeset} <- build_merged_test_changeset(shard_plan, attrs) do
      persist_shard_report(shard_run_changeset, merged_test_changeset)
    end
  end

  @doc "Wymusza terminalny status na runach zawieszonych ponad okno reapera. Zastępuje expire_stale_in_progress_test_runs/0."
  @spec expire_stale(non_neg_integer()) :: {:ok, expired_count :: non_neg_integer()}
  def expire_stale(window_hours \\ Tuist.Tests.stale_run_window_hours())

  @doc "Oznacza run jako flaky. Zastępuje mark_test_run_as_flaky/2."
  @spec mark_flaky(Test.t(), [Ecto.UUID.t()]) :: {:ok, Test.t()} | {:error, Ecto.Changeset.t()}
  def mark_flaky(test, flaky_test_case_ids)

  # --- Wnętrze: JEDYNE miejsce z dostępem do IngestRepo dla tego agregatu ---

  defp fetch_shard_plan(shard_plan_id) do
    case Shards.get_shard_plan(shard_plan_id) do
      {:ok, plan} -> {:ok, plan}
      {:error, :not_found} -> {:error, %ShardPlanNotFound{shard_plan_id: shard_plan_id}}
    end
  end

  defp validate_shard_index(%{shard_index: index}, %{shard_count: count})
       when is_integer(index) and index >= 0 and index < count,
       do: :ok

  defp validate_shard_index(attrs, plan),
    do: {:error, %ShardIndexOutOfRange{shard_index: Map.get(attrs, :shard_index), shard_count: plan.shard_count}}

  # merged_shard_status/2 i compute_final_shard_status/1 przenoszą się tu bez
  # zmiany logiki (KROK 5), ale compute_final_shard_status/1 traci gałąź
  # domyślną "true -> success" na rzecz jawnego dopasowania + błędu:
  defp compute_final_shard_status(latest_statuses) do
    cond do
      "failed_processing" in latest_statuses -> {:ok, "failed_processing"}
      "failure" in latest_statuses -> {:ok, "success"} |> elem(1) |> then(&{:ok, &1})
      Enum.all?(latest_statuses, &(&1 == "success")) -> {:ok, "success"}
      true -> {:error, %InvalidStatus{observed: latest_statuses -- ~w(success failure failed_processing)}}
    end
  end

  # Każdy insert/insert_all w tym module idzie przez changeset — bez wyjątku.
  defp persist_shard_report(shard_run_changeset, merged_test_changeset) do
    # patrz KROK 4 "Atomowość" niżej — brak prawdziwej transakcji cross-table
    # w ClickHouse, więc kolejność zapisu i idempotentna rezerwacja
    # (mapped_shard_test_run_id, tests.ex:618-622, bez zmian) pozostają
    # jedyną linią obrony przed race condition.
  end
end
```

### Błędy domenowe (nazwane, nie generyczne)

| Błąd | Kiedy | Zastępuje |
|---|---|---|
| `Tuist.Tests.Errors.ShardPlanNotFound` | Raport shardu wskazuje na nieistniejący/wygasły `shard_plan_id` | dzisiejszy `MatchError` z `tests.ex:611` |
| `Tuist.Tests.Errors.ShardIndexOutOfRange` | `shard_index` poza `0..shard_count-1` | dziś: brak jakiejkolwiek walidacji (N7) |
| `Tuist.Tests.Errors.InvalidStatus` | `compute_final_shard_status/1` widzi status spoza znanego zbioru | dziś: cichy fallback na `"success"` (`tests.ex:858`) |
| `Ecto.Changeset` (z `Test.create_changeset`/`ShardRun.create_changeset`) | Dowolne inne naruszenie pól wymaganych/inkluzji | dziś: pomijane przez `insert_all` na 3/4 ścieżkach |

### Repozytorium

`TestRunAggregate` staje się jedynym konsumentem `IngestRepo` dla `Test`/`ShardRun` w tym bounded contexcie. Odczyty potrzebne do decyzji (`sharded_test_by_id/2`, `latest_shard_statuses/1`, `mapped_shard_test_run_id/2` — wszystkie bez zmian logiki, `tests.ex:766-837`) przenoszą się do prywatnych funkcji tego samego modułu, więc żaden inny moduł nie składa zapytań ClickHouse bezpośrednio w imieniu tego agregatu.

### Atomowość — ograniczenie ClickHouse, nie luka projektu

Zadanie wymaga: *"jeśli niezmiennik wymaga atomowości — pokaż, jak całość idzie w JEDNEJ transakcji."* Tu trzeba być precyzyjnym zamiast projektować fikcyjną transakcję: `IngestRepo` (ClickHouse) **nie oferuje** międzytabelowych transakcji ACID w sensie Postgresowym — potwierdza to sam istniejący komentarz w kodzie (`tests.ex:698-703`: *"The row inserted just above is not reliably read back within the same request"*). Zamknięcie tego ograniczenia "jedną transakcją" nie jest dostępne na tym storage.

Projekt agregatu odpowiada na to inaczej niż transakcją:
1. **Rezerwacja idempotentna jako prymityw współbieżności** (już poprawnie zaprojektowana, N4, `tests.ex:618-622`) — pozostaje bez zmian, bo to ona, nie transakcja, chroni przed race condition wielu współbieżnych shardów.
2. **Walidacja na każdym zapisie jako bramka niezmiennika** (KROK 4 wyżej) zamyka lukę, którą realnie da się zamknąć na tym storage — błędne dane nigdy nie trafiają do ClickHouse, niezależnie od tego, czy zapisy są atomowe względem siebie.
3. **Reconciliation job jako siatka bezpieczeństwa** (KROK 5, faza 5) — wykrywanie, nie zapobieganie, dla wąskiego okna race condition między odczytem `latest_shard_statuses/1` a zapisem `merged_status`, którego ClickHouse strukturalnie nie da się zamknąć transakcją.

### Cienkie API/route

Kontrolery (`tests_controller.ex`, `runs_controller.ex`, `shards_controller.ex`, `analytics_controller.ex`) już dziś są cienkie — wołają `Tests.create_test/1` i mapują wynik. Zmiana: `Tests.create_test/1` (fasada, zachowana dla kompatybilności wywołań) deleguje wewnętrznie do `TestRunAggregate.start/1` lub `.report_shard/2`, a kontrolery zyskują dodatkowe dopasowanie wzorca dla nowych błędów domenowych:

```elixir
case Tests.create_test(attrs) do
  {:ok, test} -> ...200/201...
  {:error, %ShardPlanNotFound{}} -> conn |> put_status(:not_found) |> json(%{message: "Shard plan not found."})
  {:error, %ShardIndexOutOfRange{} = e} -> conn |> put_status(:unprocessable_entity) |> json(%{message: to_string(e)})
  {:error, %Ecto.Changeset{} = cs} -> conn |> put_status(:unprocessable_entity) |> json(%{errors: translate_errors(cs)})
end
```

---

## KROK 5 — Before/after, plan faz, testy

### Before/after

| Miejsce | Dziś | Po refaktorze |
|---|---|---|
| `tests.ex:721-727` (scalenie shardu) | `Map.from_struct \|> IngestRepo.insert_all` — bez walidacji | `TestRunAggregate.report_shard/2` → `Test.create_changeset` (rozszerzony o tryb update) → `IngestRepo.insert_all` tylko po `changeset.valid?` |
| `tests.ex:862-877` (`insert_shard_run`) | Gołe `insert_all(ShardRun, [%{status: status, ...}])` | `ShardRun.create_changeset/2` → walidacja `status` i `shard_index` → błąd domenowy przy naruszeniu |
| `tests.ex:854-859` (`compute_final_shard_status`) | `true -> "success"` (cichy fallback) | `true -> {:error, %InvalidStatus{...}}` (jawny, zatrzymuje operację) |
| `tests.ex:611` (`{:ok, shard_plan} = ...`) | `MatchError` przy nieistniejącym planie | `{:error, %ShardPlanNotFound{}}`, zmapowany na 404 w kontrolerze |
| `tests.ex:879-893` (`mark_test_run_as_flaky`) | `insert_all` bez walidacji | `TestRunAggregate.mark_flaky/2` przez changeset |
| `tests.ex:4404-4452` (reaper) | `insert_all` bez walidacji | `TestRunAggregate.expire_stale/1` przez changeset |
| `tests_live.ex:322-328` | Nierozpoznany status → kolor sukcesu | Nierozpoznany status → osobny, wyraźnie odróżnialny kolor/etykieta "unknown" (nie znika w tle sukcesu) — pozostaje możliwe tylko jako obrona w głąb, bo po fazie 1-3 taki status nie powinien już fizycznie trafić do ClickHouse |

### Plan faz

**Faza 1 (test-first) — `ShardRun.create_changeset/2`.**
Repo ma dyscyplinę ExUnit (`server/test/test_helper.exs`) — ta faza idzie test-first.
Przypadki testowe:
- ✅ legalne: `status` w `{success, failure, skipped, processing, failed_processing}`, `shard_index >= 0` → `changeset.valid? == true`
- ❌ nielegalne: `status: "succes"` (literówka), `status: "in_progress"` (wartość zarezerwowana dla scalonego runu, niedozwolona na pojedynczym shardzie), `shard_index: -1`, brak `shard_plan_id`/`test_run_id` → `changeset.valid? == false`, konkretny błąd na właściwym polu

**Faza 2 (test-first) — `TestRunAggregate` jako jedyna brama zapisu.**
Migracja 4 ścieżek zapisu (`create_new_test`, `create_or_update_sharded_test`, `mark_test_run_as_flaky`, `expire_stale_in_progress_test_runs`) do wywołań przechodzących przez changeset. Test-first, bo to zmiana zachowania przy błędnych danych (dziś: cichy zapis; po: odrzucenie).
Przypadki testowe:
- ✅ legalne: pełny happy-path scalania 3 shardów → merged Test ma poprawny status i przechodzi przez `Test.create_changeset`
- ❌ nielegalne: wstrzyknięcie (w teście, przez mock/fake) nierozpoznanego statusu shardu do `latest_statuses` → `report_shard/2` zwraca `{:error, %InvalidStatus{}}`, **run NIE zostaje zapisany jako "success"**
- ❌ nielegalne: `shard_index` poza zakresem planu → `{:error, %ShardIndexOutOfRange{}}`, zero zapisu do ClickHouse
- ❌ nielegalne: `shard_plan_id` nieistniejącego planu → `{:error, %ShardPlanNotFound{}}`, brak `MatchError`
- Regresja: wszystkie dotychczasowe testy w `test/tuist/tests_test.exs` (jeśli istnieją, ścieżka niezweryfikowana w tej sesji — patrz Ograniczenia) muszą przejść bez zmiany oczekiwanego zachowania dla legalnych danych

**Faza 3 — mapowanie błędów domenowych na odpowiedzi HTTP w kontrolerach.**
Nie wymaga TDD w sensie red-green (to cienka warstwa mapowania), ale każdy nowy branch dostaje test kontrolera: żądanie z nieistniejącym `shard_plan_id` → `404`, nie `500`.

**Faza 4 — dashboard, obrona w głąb.**
Zamiana cichego fallbacku (`tests_live.ex:327`) na jawnie odróżnialny stan. Niski priorytet względem faz 1-3 (po ich wdrożeniu powinno być strukturalnie niemożliwe, by nierozpoznany status dotarł do ClickHouse), ale tania i warta zrobienia jako druga linia obrony.

**Faza 5 — reconciliation job (siatka bezpieczeństwa dla okna race condition).**
Okresowe zapytanie: `SELECT count() FROM test_runs WHERE status NOT IN (...)` → alert, jeśli > 0. Wykrywa, nie zapobiega — patrz KROK 4 "Atomowość".

### Nowe "load-bearing" nazwy do zarejestrowania

- `Tuist.Tests.TestRunAggregate` — jedyny moduł z prawem zapisu `Test`/`ShardRun`
- `Tuist.Shards.ShardRun.create_changeset/2` — nowa funkcja, dziś nieistniejąca
- `Tuist.Tests.Errors.ShardPlanNotFound`
- `Tuist.Tests.Errors.ShardIndexOutOfRange`
- `Tuist.Tests.Errors.InvalidStatus`

---

## Ograniczenia tej sesji

- **Nie przeszukano `test/tuist/tests_test.exs`** (ani odpowiednika) w tej sesji, więc plan faz 1-2 zakłada istnienie/nieistnienie testów bez weryfikacji — przed implementacją Fazy 2 należy najpierw odczytać ten plik, by nie duplikować/kolidować z istniejącym pokryciem.
- **`shards.ex` (866 linii) nie zostało przeczytane w całości** — czytano `create_shard_plan/2` (nagłówek), `get_shard_plan/1`, `start_upload/*`. Możliwe, że istnieją dodatkowe ścieżki zapisu do `ShardRun`/`ShardPlan` poza tymi zacytowanymi.
- **Zachowanie `TuistWeb.Plugs.CastAndValidate` przy naruszeniu enuma nie zostało zweryfikowane przez uruchomienie testu integracyjnego** w tej sesji — wniosek "odrzuca żądanie" oparty jest na standardowym zachowaniu `OpenApiSpex`/tej rodziny pluginów i obecności `plug(...)` przed akcją kontrolera, nie na zaobserwowanym requeście.
- Ten plan **nie obejmuje** niezmiennika kwarantanny (N6) poza jego rolą w KROK 2 jako punktu porównania — to osobny, mniejszy refaktor (domknięcie testu integracyjnego w `TestServiceTests.swift`), nie wymaga agregatu.
- Nazwy błędów domenowych (`ShardPlanNotFound` itd.) i dokładny kształt `TestRunAggregate` to propozycja projektowa do konsultacji z zespołem serwerowym przed implementacją — nie są jeszcze zarejestrowanym kontraktem.
