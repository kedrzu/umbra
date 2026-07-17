# Kontrakt subagenta — Atrakcje / Plan dnia

Ten plik to szablon briefu dla subagenta researchującego **co robić na miejscu** — atrakcje, doświadczenia, jedzenie, wydarzenia — i przygotowującego surowce pod itinerariusz. Główny agent czyta plik, wstawia parametry ze specyfikacji i odpala subagenta na Sonnecie (`Agent`, `model: "sonnet"`, `subagent_type: "general-purpose"`), równolegle z resztą.

Sens: dostarczyć **bogaty, pogrupowany geograficznie** zestaw rzeczy do zrobienia, dopasowany do stylu, składu i pory roku — z jasnym oznaczeniem, **co wymaga wcześniejszej rezerwacji** i **ile czasu zajmuje** — żeby główny agent mógł złożyć spójny plan dzień-po-dniu.

---

## Szablon promptu dla subagenta

> To jest **zadanie badawcze**: research atrakcji i jedzenia na potrzeby planu podróży. Zwróć dossier jako **finalną odpowiedź**. Nie deleguj dalej. Nie rezerwujesz niczego.
>
> **Miejsce:** [miasto/region] · **Termin:** [daty — uwzględnij porę roku/sezon] · **Długość:** [N dni]
> **Skład:** [dorośli, dzieci: wiek] · **Styl i tempo:** [zwiedzanie/wypoczynek/aktywnie/kulinarnie] · [napięty / luz]
> **Must-do / see / eat:** [życzenia użytkownika] · **Unikać:** [deal-breakery]
> **Budżet na atrakcje (jeśli podany):** [..]
>
> **Jak pracować:**
> - `WebSearch`/`WebFetch` (`ToolSearch` `select:WebSearch,WebFetch`) — przewodniki, blogi podróżnicze (PL + EN), „top things to do", „[miasto] with kids", listy restauracji (lokalne, nie tylko turystyczne pułapki), Reddit/fora, oficjalne strony atrakcji (godziny, bilety). Przeglądarka (Playwright) pomocna do stron biletowych, które nie renderują się w `WebFetch`.
> - **Limit ~8 wyszukiwań.** Blokującą/wolną stronę pomiń. Pola nieustalone → „b.d.".
> - Dobieraj **pod styl, skład i porę roku** — inne rzeczy dla rodziny z małym dzieckiem, inne dla pary na city break kulinarnym; sprawdź, co jest czynne/sensowne w danym sezonie (upał, pora deszczowa, zima).
>
> **Dla każdej pozycji ustal:** czym jest i dla kogo, **rejon/dzielnica** (do grupowania geograficznego), **czas trwania**, orientacyjna **cena biletu/wstępu**, **czy wymaga rezerwacji z wyprzedzeniem** (i jak bardzo), **godziny/dni otwarcia** (uwaga na dzień zamknięcia w tygodniu), sezonowość.
>
> **Pokryj kategorie** (adaptacyjnie do stylu): must-see/ikony, mniej oczywiste/lokalne perełki, aktywności/doświadczenia, jedzenie (śniadanie/lunch/kolacja + konkretne polecane miejsca), wydarzenia w terminie (festiwale, mecze, koncerty), opcje na złą pogodę, coś dla dzieci jeśli dotyczy, 1–2 pomysły na wycieczkę jednodniową w okolicę.
>
> **Zwróć dokładnie taką strukturę (Markdown):**
>
> ```markdown
> ## Atrakcje i jedzenie: [miasto]
>
> ### 🎯 Atrakcje / doświadczenia
> | Pozycja | Rejon | Czas | Cena | Rezerwacja z góry? | Godziny / uwagi |
> |---------|-------|------|------|--------------------|-----------------|
> | [..] | [..] | [..] | [..] | [tak/nie — jak pilnie] | [dzień zamknięcia, sezon] |
>
> ### 🍽️ Jedzenie (polecane, lokalne)
> - **[Nazwa]** — [rejon] · [typ/danie] · [poziom cen] · [rezerwacja?] · [dlaczego warto]
>
> ### 🎉 Wydarzenia w terminie / sezonowość
> - [festiwal/mecz/koncert w [daty] — czy warto/wpływa na tłumy i ceny]
>
> ### 🌧️ Na złą pogodę / 👶 dla dzieci (jeśli dotyczy)
> - [..]
>
> ### 🚌 Wycieczki jednodniowe w okolicę
> - [miejsce — jak dojechać, ile czasu, dla kogo]
>
> ### 🗺️ Grupowanie geograficzne (podpowiedź pod plan dnia)
> - **[Rejon A]:** [atrakcje/jedzenie, które warto zrobić tego samego dnia]
> - **[Rejon B]:** [..]
>
> **🎟️ Bezwzględnie zarezerwuj z wyprzedzeniem:** [lista pozycji, które się wyprzedają]
> **🔗 Źródła:** [linki z datą]
> **❓ Luki:** [czego nie udało się ustalić]
> ```
>
> Zwróć wyłącznie to dossier.

---

## Wskazówki dla agenta głównego przy składaniu briefu

- Przekaż **styl, skład i tempo** dokładnie — to one decydują o doborze (kulinarnie vs muzea vs plaża vs z dzieckiem).
- **Sekcja „Grupowanie geograficzne" jest kluczowa** — na jej podstawie budujesz itinerariusz dzień-po-dniu bez skakania po mieście.
- Zwróć uwagę na **dzień zamknięcia** popularnych atrakcji (np. muzea w poniedziałki) przy układaniu dni.
- Framuj jako **zadanie badawcze**. **Obsłuż maruderów** (re-run lub sam).
