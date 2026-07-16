---
name: time-analysis
description: Analiza wykorzystania czasu na podstawie głosowych wpisów w Dzienniku (./obsidian/Dziennik/). Odtwarza chronologiczny log aktywności minuta po minucie, sam wyłania kategorie z realnych czynności i deterministycznym skryptem liczy ile czasu poszło na co (per dzień, kategoria, pora dnia), a na końcu daje analizę i wnioski. Użyj gdy użytkownik chce zobaczyć "na co schodzi mi czas", "gdzie uciekają godziny", zrobić sobie podsumowanie/coaching czasowy, przeanalizować dziennik, porównać dni lub tygodnie. To narzędzie analityczne — NIE do pisania nowych wpisów ani do dziennego briefingu (to /daily-briefing).
---

# Analiza Czasu

Z surowych, głosowych notatek w Dzienniku odtwarzasz **na co realnie schodzi czas** i wyciągasz z tego wnioski. Proces jest **dwuetapowy**: najpierw precyzyjny log (chronologia + minuty), dopiero potem kategorie i statystyki. Raport zapisujesz w trzech częściach do osobnego folderu, z timestampem, żeby dało się wracać i porównywać przebiegi.

## Vault Obsidian

**WAŻNE**: Wszystkie pliki są w vault Obsidian (`./obsidian/`), NIE w lokalnym folderze projektu! `./obsidian/` to **symlink** — Glob może nie działać, używaj `Bash(ls ...)`.

- **Źródło**: `./obsidian/Dziennik/YYYY-MM-DD.md` — jeden plik na dzień, wpisy w formacie `## HH:MM` + tekst.
- **Wynik**: `./obsidian/Asystent/AnalizaCzasu/` — tu zapisujesz artefakty (folder utwórz przy pierwszym przebiegu).

## Uwaga o skrypcie (świadome odstępstwo)

Pozostałe skille w tym repo są jednoplikowe, bez skryptów. Ten **celowo** dołącza `scripts/time_aggregate.py`. Powód: **LLM jest słaby w arytmetyce**, a tu trzeba sumować dziesiątki przedziałów minut, liczyć procenty, wykrywać nakładki i dziury. Dlatego podział ról jest twardy:

- **Model robi całą interpretację** — czyta notatki, odtwarza oś czasu, nadaje kategorie.
- **Skrypt robi całą matematykę i walidację** — zero wiedzy domenowej, zero liczenia "w pamięci".

Nigdy nie licz sum/procentów ręcznie. Zawsze przepuść log przez skrypt i raportuj jego liczby.

## Narzędzia

| Operacja | Narzędzie |
|----------|-----------|
| Lista dni w Dzienniku / poprzednich analiz | `Bash(ls ./obsidian/Dziennik/)`, `Bash(ls ./obsidian/Asystent/AnalizaCzasu/)` — NIE Glob! |
| Czytanie wpisów dnia | `Read` |
| Zapis logu modelu (JSON) i raportów (MD) | `Write` |
| Agregacja + walidacja (arytmetyka) | `Bash(python3 .claude/skills/time-analysis/scripts/time_aggregate.py ...)` |
| (opcjonalnie) kontekst osób/projektów | `qmd` (MCP) |

## Zasada dwuetapowa (DLACZEGO)

- **Etap 1 = LOG**: chronologia aktywności z minutami. Surowa rekonstrukcja faktów, bez kategoryzowania.
- **Etap 2 = KATEGORIE**: dopiero patrząc na gotowy log, wyłaniasz zestaw kategorii **z realnych czynności** (nie z gotowej listy) i przypisujesz każdy wiersz.

Rozdzielenie jest świadome: gdybyś kategoryzował od razu, naginałbyś fakty pod z góry przyjęte szufladki. Najpierw ustal **co i ile**, potem **jak to pogrupować**.

## Metodyka Etapu 1 — rekonstrukcja osi czasu (serce skilla)

Notatki są **retrospektywne i nierówne**: `## HH:MM` to moment *podyktowania* notatki, a jej tekst opisuje to, co działo się w **luce od poprzedniej notatki** (czasem rekapituluje kilka godzin naraz). Twoje zadanie: zamienić to w nienakładającą się oś czasu z minutami.

**Zasada przewodnia — luka między nagłówkami to budżet czasu, który musisz zachować.** Nagłówek `## HH:MM` jest twardym faktem zegarowym. Tekst pod nim wypełnia okno *[poprzedni nagłówek → ten nagłówek]*. Suma minut aktywności w danej luce **nie może przekroczyć** jej długości. To zamienia luźne wspominanie w problem ograniczonej alokacji i powstrzymuje przed zawyżaniem.

Pryncypia (rozumuj nimi, to nie sztywne reguły):

1. **Segmentuj na luki.** Wypisz nagłówki dnia po kolei, policz długość każdej luki — to budżet do rozdania.

2. **Drabina dowodów przy alokacji budżetu:**
   - **(a) Jawne czasy wygrywają.** "przez 45 minut", "pół godziny" (=30), "godzinę i 10 minut" (=70), "jakieś 16 minut". Wstaw je pierwsze, odejmij od budżetu.
   - **(b) Kotwice zegarowe w tekście — MIĘKKIE.** "o 13:00 zrobiłem kawę", "wróciłem około 12:20". Użyj ich do **uporządkowania i ograniczenia** odcinków, ale przy konflikcie **wygrywa nagłówek** — transkrypcja głosowa myli zegar ("za 10:06", "etność 19:20"). Niepewną kotwicę cytuj w `evidence`, daj `confidence: low`.
   - **(c) Resztę budżetu rozdziel wg priorów** tego użytkownika: sesja pracy Pomodoro ≈ 45 min, medytacja ≈ 30, spacer z psem ≈ 15–25, posiłek ≈ 20–30, kawa/krzątanie ≈ 5–15, przejścia/„ogarnięcie" ≈ 5. Priory pochodzą z jego nawyków i czynią podział obronnym, nie losowym.

3. **Multitasking = jeden span, jedna kategoria główna, reszta jako tagi.** "pracowałem idąc na bieżni przez 45 minut" → jeden 45-min wiersz, `primary` = praca, `concurrent: ["bieżnia"]`. Minuty liczą się **raz**, do kategorii primary. Nigdy nie rób dwóch osobnych wierszy dla równoległych czynności — to gwarantuje brak podwójnego liczenia.

4. **Rekapy wielogodzinne = mini-oś w luce.** Gdy jeden wpis streszcza kilka godzin, wyciągnij z prozy wszystkie pod-kotwice, zbuduj wewnątrz luki małą oś czasu tą samą drabiną dowodów i wyemituj kilka wierszy, których minuty sumują się do długości luki.

5. **Refleksje / emocje / cytaty = `duration_min: 0`, `type: reflection`.** Notatka będąca komentarzem z medytacji, przemyśleniem, cytatem z książki czy przetwarzaniem emocji to dyktowanie, które działo się *w trakcie* już policzonej czynności albo jest chwilowe. Zachowaj jej treść (przyda się w Części 3 — nastrój, energia), ale **nie konkuruje o budżet**.

6. **Sen = span przed pierwszym wpisem dnia** (`type: sleep`). To zwykle największy blok. Jeśli znasz wczorajsze „idę spać", policz od niego; jak nie — od domyślnej długości nocy i oznacz `confidence: low`. To **jedyny** wiersz, który może przekraczać północ (`end < start`).

7. **Ostatni wpis dnia jest przyszłościowy.** "idę spać", "wychodzę z psem" opisuje to, co *dopiero nastąpi*. Nie licz ogona po ostatnim nagłówku — zamknij dzień, ewentualny ogon oznacz `type: untracked`.

8. **Nie dopychaj.** Jeśli po alokacji w luce zostaje wolny budżet — zostaw go jako wiersz `type: untracked`, nie rozdmuchuj czynności. Sam fakt „2h dziennie bez wytłumaczenia" to wartościowy insight. (Skrypt i tak wykryje dziury między wierszami; lepiej je nazwać świadomie.)

9. **Self-report to cross-check, nie wejście.** "przepracowałem dziś łącznie 4,5h w 6 sesjach" → nie steruj tym alokacją, ale zapisz w `self_reported`. Skrypt policzy rozjazd deklaracji vs rekonstrukcji — rozbieżność bywa najciekawsza.

10. **Każdy wiersz ma `confidence` i `evidence`.** `evidence` = krótki cytat z notatki, który uzasadnia wiersz. `confidence`: `high` (jawny czas / mocna kotwica), `medium` (silny prior), `low` (zgadywanka). Dzięki temu log jest audytowalny, a Część 3 może ważyć wnioski pewnością.

## Kontrakt model ↔ skrypt

Po Etapie 1+2 zbuduj **jeden JSON** i zapisz go jako `*.log.json`. To wejście skryptu.

```jsonc
{
  "schema_version": 1,
  "generated_at": "2026-06-18T11:30:00",          // weź realny timestamp z Bash(date)
  "range": { "start": "2026-06-15", "end": "2026-06-17" },
  "warnings": ["2026-06-16: brak pliku dnia"],     // np. dni bez notatek
  "categories": [                                   // WYŁONIONE z aktywności, nie narzucone
    { "id": "praca",     "label": "Praca (Pomodoro)" },
    { "id": "medytacja", "label": "Medytacja" },
    { "id": "pies",      "label": "Pies / spacery" },
    { "id": "sen",       "label": "Sen" },
    { "id": "refleksja", "label": "Refleksja / journaling", "zero_time": true }
  ],
  "days": [
    {
      "date": "2026-06-17",
      "weekday": "Wt",
      "self_reported": [ { "text": "pracowałem ~4h", "category": "praca", "minutes": 240 } ],
      "log": [
        {
          "id": "2026-06-17-001",
          "start": "10:48", "end": "11:33", "duration_min": 45,
          "category": "praca",
          "primary": "Praca — review kodu",
          "concurrent": ["bieżnia"],
          "type": "activity",            // activity | sleep | reflection | untracked
          "confidence": "high",          // high | medium | low
          "evidence": "pracowałem idąc na bieżni przez 45 minut",
          "source_header": "11:33"
        }
        // ... kolejne wiersze; w obrębie luki minuty sumują się do jej długości
      ]
    }
  ]
}
```

Reguły pól (skrypt je egzekwuje):
- `duration_min` = liczba minut wyliczona z `start`/`end` (skrypt przelicza i flaguje rozjazd > 1 min).
- `concurrent[]` to **tagi opisowe** — nigdy nie wnoszą minut do sum.
- `type: "reflection"` ⇒ `duration_min: 0`.
- `type: "untracked"` jest dozwolony i pożądany (reszta budżetu, ogon dnia).
- Tylko `type: "sleep"` może mieć `end < start` (przekroczenie północy). Dla innych typów to błąd → skrypt zwróci kod ≠ 0.
- `category` każdego wiersza activity/sleep musi istnieć w `categories`.

## Proces

1. **Ustal zakres.** Pobierz najpierw „dzisiaj": `Bash(date "+%Y-%m-%d")` oraz timestamp uruchomienia: `Bash(date "+%Y%m%d-%H%M")` i `Bash(date "+%Y-%m-%dT%H:%M:%S")`.
   - **Analizuj wyłącznie pełne (zakończone) dni — koniec zakresu to najpóźniej WCZORAJ.** Dzień `>= dzisiaj` jest poza zakresem: dzień się jeszcze nie skończył, Dziennik ma wpisy tylko do bieżącej chwili, więc alokacja luk czasowych (serce Etapu 1) nie miałaby pełnego budżetu doby. Co gorsza — gdybyś policzył dziś niepełny dzień, **kursor przyrostowy przesunie się za niego i pełna wersja nigdy nie zostanie doanalizowana**. Dlatego dzisiaj zawsze czeka na jutro. Nie komentuj „dzień X niepełny" — po prostu go nie bierz.
   - **Domyślnie — przyrostowo:** `ls ./obsidian/Asystent/AnalizaCzasu/`. Kursor wyznacz po analizie o **najpóźniejszym `zakres` (end)** w frontmatterze (NIE po najnowszym `run` — backfill o starszym/równym zakresie nie może cofać kursora). Start = dzień po tym `end`. Koniec = **min(najnowszy dzień w Dzienniku, wczoraj)**.
   - **Self-heal starych analiz:** jeśli wybrana analiza ma `zakres.end >= data(run)` (czyli liczyła własny, wtedy-niepełny dzień), **włącz ten `end` ponownie** do nowego zakresu (start = `end`, nie `end + 1`) — był niepełny, gdy go policzono, więc należy mu się uczciwa, całodniowa analiza.
   - **Brak nowych pełnych dni** (start > koniec — wszystko do wczoraj już przeliczone): zakończ grzecznie komunikatem „brak nowych pełnych dni — najnowszy pełny dzień (`<data>`) już przeanalizowany". Nie analizuj dzisiaj „na zapas".
   - **Jawny zakres od użytkownika wygrywa** nad regułą „do wczoraj". Jeśli obejmuje dzisiaj — wykonaj, ale dopisz w raporcie notkę, że ostatni dzień jest niepełny (świadomy wybór użytkownika).
   - **Pierwszy przebieg** (folder pusty/nie istnieje) — cały dostępny Dziennik **do wczoraj włącznie**.

2. **Wylistuj i wczytaj dni.** `ls ./obsidian/Dziennik/`, ustal które pliki wpadają w zakres. Brakujące dni → do `warnings` (nie interpoluj!). Każdy dzień `Read`.

3. **Etap 1 — zrekonstruuj oś czasu** każdego dnia wg metodyki powyżej. Myśl luka-po-luce.

4. **Etap 2 — wyłoń kategorie** patrząc na gotowy log całego zakresu (np. praca, medytacja, pies, rodzina, trening, posiłki, sen, rozrywka, refleksja). Przypisz `category` do każdego wiersza. Refleksjom daj kategorię z `zero_time: true`.

5. **Zbuduj JSON i zapisz** jako `*.log.json` (`Write`, nazewnictwo niżej).

6. **Odpal skrypt:**
   ```
   python3 .claude/skills/time-analysis/scripts/time_aggregate.py \
     --in <ścieżka>.log.json --out <ścieżka>.results.json --pretty
   ```

7. **Przeczytaj podsumowanie ze stdout + `results.json`.** Jeśli skrypt zgłasza `nakładki`, duże `rozjazdy duration_min`, `nieznane kategorie` albo podejrzanie wielkie dziury — **popraw Etap 1/JSON i odpal skrypt ponownie**. Kod wyjścia ≠ 0 = wejście do poprawy, nie idź dalej bez liczb.

8. **Złóż trzy raporty** (`Write`) wg szablonów poniżej, używając **liczb ze skryptu** (nie licz sam).

9. **Pokaż użytkownikowi skrót**: najważniejsze sumy, 2–3 nieoczywiste wzorce, pokrycie, oraz ścieżki do zapisanych plików.

## Artefakty (folder + nazewnictwo)

Folder: `./obsidian/Asystent/AnalizaCzasu/`. Per przebieg, zachowywane na stałe (timestamp w nazwie pozwala trzymać kilka analiz tego samego zakresu obok siebie):

```
Analiza-<start>_<end>--run-<YYYYMMDD-HHMM>-1-log.md
Analiza-<start>_<end>--run-<YYYYMMDD-HHMM>-2-kategorie.md
Analiza-<start>_<end>--run-<YYYYMMDD-HHMM>-3-analiza.md
Analiza-<start>_<end>--run-<YYYYMMDD-HHMM>.log.json       # dane modelu (reprodukowalność)
Analiza-<start>_<end>--run-<YYYYMMDD-HHMM>.results.json   # liczby ze skryptu
```

Każdy plik `.md` zaczyna się frontmatterem (pozwala odczytać zakres przy następnym przyrostowym przebiegu i indeksować w Dataview/Bases):

```yaml
---
typ: analiza-czasu
zakres: 2026-06-15..2026-06-17
run: 2026-06-18T11:30:00
czesc: log            # log | kategorie | analiza
pokrycie_pct: 94.2    # z results.json (to samo we wszystkich 3 plikach)
---
```

## Szablon — Część 1: Szczegółowy log

```markdown
# Analiza czasu — log szczegółowy (2026-06-15..2026-06-17)

> Co i ile, minuta po minucie. Kotwice z notatek; `confidence` mówi jak pewny jest wiersz.

## 2026-06-17 (Wtorek)

| Start | Koniec | Min | Kategoria | Aktywność | Równolegle | Pewność |
|-------|--------|-----|-----------|-----------|------------|---------|
| 00:00 | 07:49 | 469 | Sen | Sen | — | medium |
| 10:48 | 11:33 | 45 | Praca | Review kodu | bieżnia | high |
| 11:33 | 12:10 | 37 | — | *(nieprzypisane)* | — | — |
| ... | ... | ... | ... | ... | ... | ... |

*Refleksje (czas 0):* 16:29 — napięcie po sprzeczce z Magdą; 18:33 — cytat z „Umysłu oświeconego".

## 2026-06-16 (Poniedziałek)
*(brak pliku Dziennika — dzień pominięty)*

...
```

## Szablon — Część 2: Widok kategorii

```markdown
# Analiza czasu — kategorie i statystyki (2026-06-15..2026-06-17)

> Wszystkie liczby pochodzą ze skryptu (results.json). Procenty liczone od czasu *tracked*.

## Sumy per kategoria
| Kategoria | Godziny | % tracked |
|-----------|---------|-----------|
| Sen | 22.5 | 31.0 |
| Praca | 13.5 | 18.6 |
| ... | ... | ... |

Tracked łącznie: **X h** · Untracked: **Y min** · Pokrycie: **Z%**

## Macierz dzień × kategoria (minuty)
| data | Praca | Medytacja | Pies | ... |
|------|-------|-----------|------|-----|
| 2026-06-17 | 540 | 30 | 60 | ... |
| ... | | | | |

## Rozbicie na pory dnia (minuty)
| Blok | Praca | Medytacja | ... |
|------|-------|-----------|-----|
| Rano (05–09) | ... | ... | |
| Przedpołudnie (09–12) | ... | | |
| Popołudnie (12–17) | ... | | |
| Wieczór (17–22) | ... | | |
| Noc (22–05) | ... | | |
```

## Szablon — Część 3: Analiza i wnioski

```markdown
# Analiza czasu — wnioski (2026-06-15..2026-06-17)

## Co zajmuje najwięcej czasu
[Narracja oparta o sumy ze skryptu.]

## Nieoczywiste wzorce
- [np. praca skupiona przed południem, popołudnia rozproszone; rozrywka rośnie wieczorami]
- [korelacje z nastrojem/energią wyłuskane z refleksji]

## Czas nieprzypisany
[Ile godzin untracked i kiedy — gdzie „uciekają" godziny.]

## Self-report vs rzeczywistość
[Rozjazd z `checks.self_report_drift` — np. „czułeś 4,5h pracy, log pokazuje 3,8h".]

## Sygnał nastroju / energii
[Z refleksji: napięcia, satysfakcja, zmęczenie — powiązane z porami/czynnościami.]

## Wnioski do działania
1. [Konkretny, wykonalny krok.]
2. [...]
```

## Zasady

- **Arytmetyka tylko przez skrypt.** Nigdy nie sumuj minut ani procentów „w pamięci".
- **Nie podwajaj czasu.** Multitasking = jeden span (`primary` + `concurrent[]`).
- **Nie wymyślaj minut.** Nieznane → `type: untracked`. Brak danych za dzień → `warnings`, nie interpolacja.
- **Kotwice w tekście są miękkie**, nagłówek `## HH:MM` jest twardy (transkrypcja myli zegar).
- **Kategorie wyłaniaj z danych** w Etapie 2 — nie narzucaj gotowej taksonomii.
- **Analizuj wyłącznie zakończone dni** — domyślnie kończ na wczoraj, dzisiejszy dzień pomijaj (niepełny + paliłby się w kursorze przyrostowym). Wyjątek: użytkownik jawnie poprosił o zakres obejmujący dziś.
- **Zachowuj wszystkie pliki** (timestamp w nazwie) — stare analizy zostają do porównań, niczego nie nadpisuj.
- **Każdy wiersz** ma `evidence` (cytat) i `confidence`.
- Jeśli skrypt zwróci kod ≠ 0 lub poważne flagi — popraw log i odpal ponownie, zanim napiszesz raport.
- **Luka kontekstowa** (protokół CLAUDE.md „Luki kontekstowe"): nieznana czynność / osoba / miejsce / kryptonim we wpisie, której nie umiesz skategoryzować → najpierw `grep` po Dzienniku i `qmd` po vault. Jeśli dalej ślepo i to realnie utrudnia kategoryzację — **zbierz niejasności i zapytaj zbiorczo** (na końcu, nie przerywaj rekonstrukcji per wpis), potem **utrwal** (osoba → `Kontakty/`, reszta → `Insights.md`). Read-only Dziennika to nie zmienia — piszesz tylko do pamięci i `AnalizaCzasu/`.
- To analiza **read-only** Dziennika — nie edytujesz wpisów użytkownika, piszesz wyłącznie do `Asystent/AnalizaCzasu/`.
