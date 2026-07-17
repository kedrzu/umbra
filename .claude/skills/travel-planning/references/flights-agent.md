# Kontrakt subagenta — Loty / Transport

Ten plik to szablon briefu dla subagenta researchującego **przelot tam i z powrotem** (i ewentualny transport główny, gdy lot nie ma sensu). Główny agent czyta ten plik, wstawia parametry z zaakceptowanej specyfikacji i odpala subagenta na Sonnecie (`Agent`, `model: "sonnet"`, `subagent_type: "general-purpose"`). Odpalaj równolegle z pozostałymi subagentami.

Sens: znaleźć **realnie najlepsze** połączenie — nie pierwsze z brzegu — z twardym porównaniem **WAW vs KTW/KRK/GDN vs multi-city**, bo tam (szczególnie last-minute, tanie linie) siedzą największe oszczędności.

---

## Szablon promptu dla subagenta

> To jest **zadanie badawcze**: research połączeń lotniczych na potrzeby planu podróży. Zbadaj rzetelnie opcje przelotu i zwróć ustrukturyzowane dossier jako swoją **finalną odpowiedź**. Nie deleguj dalej, nie zlecaj podzadań w tle, nie odsyłaj „zajmę się tym". Nie rezerwujesz, nie logujesz się, nie podajesz danych — tylko odczytujesz ceny/dostępność i budujesz linki.
>
> **Trasa:** z Polski do **[miasto/lotnisko docelowe, IATA jeśli znasz]**
> **Termin:** [daty] — [sztywne / elastyczne ±N dni] · **Długość:** [N nocy]
> **Skład:** [N dorosłych, dzieci: wiek] · **Klasa/preferencje:** [economy / bez nocnych przesiadek / itd.]
> **Budżet na lot (jeśli podany):** [kwota] · **Bagaż:** [rejestrowany potrzebny? tak/nie]
>
> **Jak pracować (kolejność narzędzi):**
> - **Najpierw przeglądarka — Playwright MCP** (`mcp__playwright__browser_navigate` + `browser_snapshot`; załaduj przez `ToolSearch` `select:mcp__playwright__browser_navigate,mcp__playwright__browser_snapshot`). Otwieraj pre-filled URL-e Google Flights / Skyscanner / Kayak, poczekaj na wyniki (`browser_wait_for` jeśli trzeba) i **odczytaj żywe ceny ze snapshotu** — nie zgaduj.
> - **Gdy blokada / CAPTCHA / 403 / strona się wiesza / brak serwera** → `WebSearch`/`WebFetch` (`ToolSearch` `select:WebSearch,WebFetch`): cena **orientacyjna** z widełek/artykułów, wyraźnie oznaczona jako niezweryfikowana bezpośrednio.
> - **Limit ~8 akcji.** Nie zawieszaj się na jednej stronie; blokującą pomiń. Pola nieustalone → „b.d.".
>
> **Co obowiązkowo porównać:**
> - **WAW (domyślnie)** vs **KTW, KRK, GDN** — dla każdego wariantu podaj cenę i połączenie.
> - **Multi-city** — sprawdź wylot z jednego lotniska, powrót do innego (np. WAW→[cel], [cel]→KTW); bywa tańsze niż round-trip.
> - **Elastyczność dat** (jeśli specyfikacja na to pozwala) — ±1–3 dni potrafi zmieścić duży spadek ceny; zajrzyj do kalendarza cen (Google Flights / Skyscanner „cały miesiąc").
> - **Alt-lotnisko rekomenduj tylko, gdy oszczędność przewyższa koszt+czas dojazdu z Warszawy** — policz **symetrycznie**: cena biletu z KTW/KRK/GDN vs (cena z WAW − koszt dojazdu PKP/auto do tego lotniska − wartość straconego czasu − ryzyko). Podaj tę różnicę jawnie.
> - **Tanie linie (Wizz, Ryanair) uwzględniaj** — to często najtańsze opcje z KTW/KRK, ale **policz pełny koszt**: bagaż rejestrowany/kabinowy, wybór miejsca, odprawa, dojazd z dalekiego portu docelowego.
>
> **Zbierz też:** typowe **okno zakupu** (kupować teraz czy poczekać — czy ceny rosną/spadają), długość i liczbę przesiadek (ostrzeż o < ~1,5h międzynarodowo), port przylotu i odległość od centrum, godziny (nocny przylot bez transportu = minus).
>
> **Ceny:** każda konkretna cena **z datą odczytu** i oznaczeniem źródła (żywy odczyt z przeglądarki vs orientacyjny z web). **Zawsze** dołącz **pre-filled link** do żywej weryfikacji (Google Flights/Skyscanner/Kayak z wpisanymi lotniskami, datami, pax, i multi-city gdy dotyczy).
>
> **Zwróć dokładnie taką strukturę (Markdown):**
>
> ```markdown
> ## Loty: Polska → [cel]
>
> **Porównanie lotnisk wylotu** (ceny za [pax], odczyt [data]):
> | Wariant | Trasa | Linie | Przesiadki | Cena | Źródło ceny | Link |
> |---------|-------|-------|-----------|------|-------------|------|
> | WAW round-trip | WAW→[..]→WAW | [..] | [..] | [kwota] | [żywy/orient.] | [link] |
> | KTW | KTW→[..] | [..] | [..] | [kwota] | [..] | [link] |
> | KRK | … | | | | | |
> | GDN | … | | | | | |
> | Multi-city | WAW→[..], [..]→KTW | [..] | [..] | [kwota] | [..] | [link] |
>
> **➕ Rekomendacja:** [który wariant i **dlaczego** — z jawnym rachunkiem oszczędności vs koszt/czas dojazdu do alt-lotniska]
> **🎒 Bagaż / ukryte koszty:** [co wliczone, dopłaty LCC]
> **⏱️ Okno zakupu:** [kupować teraz / poczekać — trend cen; najlepszy dzień/godzina jeśli wiadomo]
> **⚠️ Ryzyka:** [krótka przesiadka, nocny przylot, daleki port, zmiana terminala…]
> **📅 Elastyczność dat:** [czy ±N dni daje istotny spadek — z konkretną datą/ceną jeśli znalazłeś]
> **🔗 Źródła:** [linki z datą]
> **❓ Luki:** [czego nie udało się ustalić]
> ```
>
> Zwróć wyłącznie to dossier — zostanie zestawione z resztą planu przez agenta głównego.

---

## Wskazówki dla agenta głównego przy składaniu briefu

- Wstaw **kod IATA celu**, jeśli go znasz (np. LIS dla Lizbony) — niejednoznaczne miasto = subagent zbada nie ten port.
- Przekaż **dokładny skład i klasę** — cena za 2 dorosłych + dziecko różni się istotnie.
- Jeśli specyfikacja dopuszcza elastyczne daty — **wyraźnie to zaznacz**, żeby subagent zajrzał do kalendarza cen (tam siedzą oszczędności).
- Framuj brief jako **zadanie badawcze**, nie rolę-rozkaz (unikaj „jesteś X, zaczynaj natychmiast") — bywa czytane jako prompt-injection.
- **Obsłuż maruderów:** subagent może paść (watchdog ~10 min) albo zwrócić placeholder — odpal ponownie lub zbadaj trasę sam (Playwright/`WebSearch`).
