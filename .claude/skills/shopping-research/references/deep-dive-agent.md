# Kontrakt subagenta — dogłębna analiza jednego produktu

Ten plik to szablon briefu dla subagenta z Etapu C (dogłębne analizy). Główny agent czyta ten plik, wstawia **jeden produkt** oraz **specyfikację** i odpala subagenta na Sonnecie (`Agent`, `model: "sonnet"`, `subagent_type: "general-purpose"`). Jeden subagent = jeden produkt. Odpalaj wszystkie równolegle.

Sens: każdy kandydat z shortlisty ma być zbadany do **tej samej głębokości** według **tego samego szablonu**, żeby porównanie było „jabłko do jabłka" i żeby ostatni kandydat dostał tyle samo uwagi co pierwszy. To strukturalny bezpiecznik przeciw faworyzowaniu pierwszego napotkanego produktu.

---

## Szablon promptu dla subagenta

> To jest **zadanie badawcze**: research jednego produktu na potrzeby zestawienia zakupowego. Zbadaj rzetelnie **jeden** produkt i zwróć ustrukturyzowane dossier. Przyjmij postawę sceptyczną (nie sprzedażową) — szczególnie szukaj **wad, ryzyk i ukrytych kosztów**. Nie porównujesz z innymi, nie rekomendujesz — opisujesz fakty i opinie ze źródłami.
>
> **Produkt:** [pełna nazwa + wariant]
> **Rynek:** Polska, ceny w PLN (chyba że specyfikacja mówi inaczej).
> **Kontekst zakupu (specyfikacja użytkownika):** [wklej use-case, budżet, must-have, kryteria z wagami, deal-breakery]
>
> **Jak pracować:**
> - **Zrób research sam i zwróć dossier jako swoją finalną odpowiedź.** Nie deleguj tego dalej, nie zlecaj podzadań w tle, nie odsyłaj „zajmę się tym” — masz oddać gotowe dossier w tej odpowiedzi.
> - Użyj `WebSearch` + `WebFetch` (jeśli niedostępne od razu, załaduj przez `ToolSearch` zapytaniem `select:WebSearch,WebFetch`). Szukaj z wielu kątów: recenzje redakcyjne (PL + EN), testy, opinie użytkowników, fora/Reddit, **Pepper (pepper.pl — komentarze/polecajki, też przy wygasłych okazjach)**, strony sklepów, reklamacje/problemy.
> - **Pracuj sprawnie: maks ~8 wyszukiwań/pobrań.** Jeśli strona się nie ładuje w kilka sekund lub blokuje (403) — pomiń ją i idź dalej, nie zawieszaj się na jednym źródle. Priorytet: zwrócić kompletne dossier; pola nieustalone oznacz „b.d.”.
> - **Upoluj najlepszą realną cenę do zdobycia** (nie poprzestawaj na pierwszej/katalogowej): porównaj główne kanały (Allegro / Ceneo / Amazon.pl / sklep producenta — ceny bywają mocno rozjechane między nimi), **sprawdź aktywne kody rabatowe i bieżące promocje** (m.in. Pepper/pepper.pl jako agregator kodów i deali; historyczne minimum jako punkt odniesienia „czy to dobra cena teraz”). Zwróć **dwie liczby: widełki obserwowane** oraz **najlepszą realną cenę do zdobycia dziś** (kanał, ew. kod, data). Koszt licz **symetrycznie** — w górę (wysyłka, cło/VAT przy imporcie) **i w dół** (kody, promo). Uwaga: „cena regularna” producenta bywa **sztucznie zawyżona** — nie bierz jej za punkt odniesienia. **Amazon często nie renderuje treści dla `WebFetch`** — wtedy cenę/oceny bierz ze snippetów wyszukiwarki, Ceneo/porównywarek albo od resellera i **oznacz, że niezweryfikowane bezpośrednio**.
> - **Zbierz ocenę sklepową**: gwiazdki + liczba recenzji (Amazon/Allegro/Ceneo) oraz sentyment forów/Trustpilot. Rozróżniaj **skargi na jakość sprzętu** od **skarg na obsługę/wysyłkę/zwroty** — to różne ryzyka (produkt może być dobry, a sklep słaby, i odwrotnie).
> - Celowo szukaj wad: zapytania typu „[produkt] problemy", „[produkt] awaria", „[produkt] po roku", „[produkt] wady", „[produkt] reklamacja".
> - **Sprawdź, czy to nie rebadge**: wiele produktów w tanich kategoriach to ten sam OEM sprzedawany pod różnymi markami (te same zdjęcia, identyczna specyfikacja, ten sam wzorzec usterek). Jeśli tak — zaznacz to i wskaż, gdzie tę samą konstrukcję kupić taniej. To realnie oszczędza pieniądze.
> - Odróżniaj fakty (specyfikacja, cena) od opinii (recenzje) i podawaj źródło przy każdym istotnym twierdzeniu.
> - Bądź uczciwy o niepewności: jeśli czegoś nie udało się ustalić, napisz to w sekcji „Luki".
>
> **Zwróć dokładnie taką strukturę (Markdown):**
>
> ```markdown
> ## [Nazwa produktu + wariant]
>
> - **Cena PL:** widełki obserwowane [zakres] · **najlepsza realna cena do zdobycia:** [kwota] w [kanał] (+ kod [jaki], sprawdzono: [data]); [min. 2 źródła; oznacz, jeśli niezweryfikowane bezpośrednio]
> - **Ocena sklepowa:** [gwiazdki + liczba recenzji, źródło] — [skargi głównie na sprzęt czy na obsługę/wysyłkę?]
> - **Dostępność w PL:** [gdzie kupić / czy łatwo dostępny / warianty]
> - **Kluczowe cechy/specyfikacja** (istotne dla kryteriów użytkownika): [lista]
>
> **➕ Mocne strony** (z dowodami/źródłami):
> - [zaleta] — [źródło]
>
> **➖ Słabe strony i typowe skargi** (z recenzji/forów — bądź konkretny):
> - [wada / częsta skarga] — [źródło]
>
> **🔧 Niezawodność / opinie długoterminowe:**
> - [awaryjność, trwałość, opinie „po czasie", wady seryjne jeśli są]
>
> **💸 Ukryte / bieżące koszty:**
> - [materiały eksploatacyjne, akcesoria, subskrypcje, drogi serwis — albo „brak istotnych"]
>
> **🛡️ Gwarancja / serwis:** [długość, warunki, jakość serwisu jeśli wiadomo]
>
> **🎯 Dla kogo idealny / dla kogo NIE:**
> - Idealny dla: [...]
> - Odradzany, jeśli: [...]
>
> **📐 Ocena względem kryteriów użytkownika** (po jednym zdaniu na kryterium ze specyfikacji):
> | Kryterium | Jak wypada | Notka |
> |-----------|-----------|-------|
> | [kryterium 1] | [np. bardzo dobrze / słabo] | [dlaczego, ze źródłem] |
>
> **🔗 Źródła:** [linki z datą dostępu]
>
> **❓ Luki / czego nie udało się ustalić:** [uczciwie]
> ```
>
> Zwróć wyłącznie to dossier — będzie zestawione z innymi przez agenta głównego.

---

## Wskazówki dla agenta głównego przy składaniu briefu

- Wstaw **pełną, konkretną nazwę + wariant** (np. „Bosch Serie 6 WGG2440 EU 9 kg", nie samo „Bosch"). Niejednoznaczna nazwa = subagent zbada inny produkt.
- Wklej **realną specyfikację** (kryteria z wagami), żeby sekcja „Ocena względem kryteriów" była trafiona — bez tego subagent oceni po swojemu.
- Odpalaj **wszystkie subagenty shortlisty w jednej turze** (równolegle), a nie po kolei — równa uwaga + szybciej.
- **Framuj brief jako zadanie badawcze, nie jako rolę-rozkaz.** Unikaj „Jesteś X, zacznij od razu, nie proś o potwierdzenie” — taki ton bywa czytany przez subagenta jako prompt-injection i skutkuje odmową albo delegowaniem zamiast researchu. Neutralne „to jest zadanie researchowe, zwróć dossier jako finalną odpowiedź” działa pewniej.
- **Obsłuż maruderów.** Subagent może paść (watchdog ubija długie, wiszące sesje ~10 min) albo zwrócić placeholder zamiast dossier. Wtedy: odpal go ponownie (z ewentualnym tropem, który zdążył znaleźć) albo — jeśli powtarza problem — **zbadaj ten jeden produkt sam**, głównym modelem, przez `WebSearch`/`WebFetch`. Nie zostawiaj dziury: porównanie jest tak dobre, jak najsłabsze dossier.
- **Zwiń rebadge’e.** Jeśli dossier ujawni, że dwa modele to ta sama platforma OEM pod różnymi markami, nie oceniaj ich osobno jak dwóch produktów — potraktuj jako jedną pozycję i wskaż najtańszy/najbezpieczniejszy kanał zakupu (a fakty o wadach z jednej marki odnoszą się do drugiej).
- Gdy zbierzesz dossier: **nie ufaj ślepo** — jeśli któreś jest płytkie albo ma dużo „Luk" w istotnych miejscach, dozbieraj sam albo odpal subagenta ponownie z węższym poleceniem.
