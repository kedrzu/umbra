# Kontrakt subagenta — Rejony + Nocleg

Ten plik to szablon briefu dla subagenta researchującego **gdzie się zatrzymać** (rejony/dzielnice) i **w czym** (konkretne obiekty: hotele i Airbnb/apartamenty). Główny agent czyta plik, wstawia parametry ze specyfikacji i odpala subagenta na Sonnecie (`Agent`, `model: "sonnet"`, `subagent_type: "general-purpose"`), równolegle z resztą.

Sens: **najpierw rejon, potem obiekt.** Zły rejon psuje najlepszy hotel (hałas, godzina dojazdu do wszystkiego, bezpieczeństwo). Subagent ma najpierw rozłożyć miasto/okolicę na rejony pod styl i logistykę, dopiero potem podać konkretne noclegi.

---

## Szablon promptu dla subagenta

> To jest **zadanie badawcze**: research noclegu na potrzeby planu podróży. Zbadaj rejony i konkretne obiekty, zwróć dossier jako **finalną odpowiedź**. Nie deleguj dalej. Nie rezerwujesz, nie logujesz się, nie podajesz danych — tylko odczytujesz ceny/oceny/dostępność i budujesz linki.
>
> **Miejsce:** [miasto/region docelowy]
> **Termin:** [daty] · **Długość:** [N nocy] · **Skład:** [N dorosłych, dzieci: wiek]
> **Budżet na nocleg:** [kwota/noc lub całość] · [twardy / miękki]
> **Typ i preferencje:** [hotel / apartament / **Airbnb** / resort / hostel] · standard [..] · must-have [basen/kuchnia/śniadania/parking/blisko centrum] · styl wyjazdu [city break / wypoczynek / rodzinny …]
> **Kontekst planu:** [co użytkownik chce robić — żeby rejon pasował do atrakcji/tempa]
>
> **Jak pracować (kolejność narzędzi):**
> - **Najpierw przeglądarka — Playwright MCP** (`browser_navigate` + `browser_snapshot`; `ToolSearch` `select:mcp__playwright__browser_navigate,mcp__playwright__browser_snapshot`). Otwieraj pre-filled URL-e **Booking, Airbnb, Google Hotels** z wpisanymi datami/składem, poczekaj na wyniki i **odczytaj żywe ceny i oceny ze snapshotu**.
> - **Gdy blokada / CAPTCHA / 403 / brak serwera** → `WebSearch`/`WebFetch`: ceny/oceny orientacyjne, artykuły „gdzie się zatrzymać w [miasto]", „best area to stay", fora/Reddit. Oznacz jako niezweryfikowane bezpośrednio.
> - **Limit ~8 akcji.** Blokującą stronę pomiń. Pola nieustalone → „b.d.".
>
> **Krok 1 — Rejony/dzielnice (najpierw!):** wskaż 2–4 rejony sensowne dla tego stylu i planu. Dla każdego: dla kogo, plusy, minusy, jak daleko do głównych atrakcji / centrum / lotniska, bezpieczeństwo, charakter (imprezowy/spokojny/rodzinny), orientacyjny poziom cen. To najważniejsza część — bez tego wybór obiektu jest ślepy.
>
> **Krok 2 — Konkretne obiekty:** podaj **3–5 obiektów** rozłożonych po rekomendowanych rejonach i po typach (**uwzględnij zarówno hotele, jak i Airbnb/apartamenty**, jeśli specyfikacja ich nie wyklucza). Dla każdego: nazwa, typ, rejon, cena/noc (z datą odczytu), ocena + liczba opinii, kluczowe plusy/minusy z recenzji, i **pre-filled link** (Booking/Airbnb). Rozróżniaj skargi na obiekt (brud, hałas) od skarg na lokalizację.
>
> **Pułapki, których szukaj:** ukryte opłaty (city tax, sprzątanie w Airbnb, kaucja, parking), „blisko centrum" a realnie 40 min, hałas (bar/klub/ulica/lotnisko), remonty, zła komunikacja z gospodarzem, minimalna liczba nocy, zameldowanie po godzinach.
>
> **Zwróć dokładnie taką strukturę (Markdown):**
>
> ```markdown
> ## Nocleg: [miasto]
>
> ### 🗺️ Rejony
> - **[Rejon A]** — dla kogo: [..]; ➕ [plusy]; ➖ [minusy]; dojazd do centrum/atrakcji: [..]; ceny: [poziom]
> - **[Rejon B]** — …
> **Rekomendowany rejon i dlaczego:** [pod ten styl/plan]
>
> ### 🏨 Obiekty (odczyt [data])
> | Obiekt | Typ | Rejon | Cena/noc | Ocena (liczba opinii) | Link |
> |--------|-----|-------|----------|-----------------------|------|
> | [..] | Hotel | [..] | [kwota] | [..] | [link] |
> | [..] | Airbnb/apart. | [..] | [kwota] | [..] | [link] |
>
> **Dla każdego obiektu — krótko:**
> - **[Obiekt]** — ➕ [plusy z recenzji] · ➖ [minusy/skargi] · 💸 [ukryte opłaty] · [dla kogo]
>
> **🏆 Rekomendacja:** [obiekt + dlaczego pasuje do stylu, budżetu i planu dnia]
> **⚠️ Na co uważać:** [opłaty, min. noce, lokalizacja, sezon/dostępność]
> **🔗 Źródła:** [linki z datą]
> **❓ Luki:** [czego nie udało się ustalić]
> ```
>
> Zwróć wyłącznie to dossier.

---

## Wskazówki dla agenta głównego przy składaniu briefu

- Przekaż **kontekst planu dnia** (co użytkownik będzie robił i gdzie), żeby rejon pasował geograficznie do atrakcji — nocleg i itinerariusz muszą się spinać.
- Jeśli Airbnb jest istotne (domyślnie tak) — **wyraźnie to zaznacz**, żeby subagent nie ograniczył się do hoteli.
- Framuj jako **zadanie badawcze**, nie rolę-rozkaz.
- **Obsłuż maruderów:** padł/placeholder → odpal ponownie lub zbadaj rejony sam.
