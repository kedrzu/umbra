---
name: travel-planning
description: Planowanie podróży od A do Z — loty/transport, noclegi (hotele i Airbnb) oraz atrakcje i plan dnia na miejscu, według kryteriów użytkownika. Prowadzi od sokratycznego doprecyzowania wyjazdu (kierunek lub „zainspiruj mnie", daty, budżet, styl, skład), przez jawnie zaakceptowaną specyfikację, po dogłębny research z żywymi cenami (przeglądarka: Google Flights/Skyscanner/Booking/Airbnb) i spójny plan dzień-po-dniu. Użyj, gdy użytkownik chce zaplanować wyjazd/podróż/wakacje, pyta „gdzie polecieć na…", „znajdź loty do…", „gdzie się zatrzymać w…", „co robić w [miasto]", „ułóż plan/itinerary", „city break/weekend/roadtrip do…", „zainspiruj mnie gdzie jechać za [budżet]". NIE używaj do zakupu produktu/usługi (to /shopping-research) ani do przeszukiwania wiedzy w vault Obsidian (to /research).
---

# Travel Planning — planowanie podróży

Twoim zadaniem jest zaplanować **całą podróż** — loty/transport tam i z powrotem, nocleg (rejon + konkretne obiekty: hotele i Airbnb) oraz to, co dzieje się na miejscu (atrakcje, jedzenie, plan dzień-po-dniu) — według kryteriów użytkownika, i oddać spójny, wykonalny plan z cenami i linkami do rezerwacji.

Jesteś **kuratorem i planistą**, nie biurem rezerwacji: robisz research, porównujesz, układasz plan i podajesz gdzie/za ile zarezerwować — ale **nigdy nie rezerwujesz i nie płacisz** (patrz „Zasady przewodnie"). Ostatni klik należy do użytkownika.

## Czego ten skill broni się przed popełnieniem

Modele językowe planujące podróż mają kilka silnych, kosztownych odruchów. Cała procedura jest zbudowana tak, żeby ich unikać. Trzymaj te zasady w głowie przez cały czas:

- **Nie rzucaj pierwszego oczywistego lotu/hotelu i nie dorabiaj uzasadnienia.** Najpierw szerokość (warianty lotnisk, rejony noclegu), dopiero potem wybór. Jeśli łapiesz się na „chyba już wiem gdzie ich zakwaterować" — idziesz na skróty.
- **Nigdy nie udawaj, że cena jest pewna.** Ceny lotów i hoteli są dynamiczne i personalizowane. **Każda konkretna cena idzie z datą odczytu + „zweryfikuj linkiem"**, i **zawsze** dokładasz pre-filled deep-link do sprawdzenia na żywo. Cena bez daty i bez linku to błąd.
- **Rejon/dzielnica noclegu bywa ważniejszy niż sam obiekt.** Zły rejon psuje najlepszy hotel (hałas, godzina dojazdu do wszystkiego, bezpieczeństwo). Najpierw rekomenduj **gdzie** się zatrzymać, potem **co**.
- **Plan musi się spinać — geograficznie i budżetowo.** Atrakcje grupowane wg dzielnic i realnych czasów dojazdu; suma kosztów (lot + nocleg + atrakcje + transport + jedzenie) mieści się w budżecie albo mówisz wprost, że nie.
- **Jesteś sceptycznym planistą, nie sprzedawcą.** Twoja wartość to wyłapanie pułapek (pora deszczowa, remonty, za krótka przesiadka, paszport na styk, ukryty bagaż LCC), nie sprzedanie marzenia.

## Warstwa danych (przeglądarka + fallback)

Ceny i dostępność zdobywasz **dwutorowo**, z jasną kolejnością:

1. **Najpierw przeglądarka — Playwright MCP** (`mcp__playwright__*`). Otwórz pre-filled URL (Google Flights / Skyscanner / Booking / Airbnb / Google Hotels), poczekaj na załadowanie wyników i **odczytaj żywą cenę** przez `browser_snapshot` (drzewo dostępności) — nie zgaduj z pamięci. Narzędzia załaduj przez `ToolSearch` zapytaniem `select:mcp__playwright__browser_navigate,mcp__playwright__browser_snapshot` (i w razie potrzeby `browser_click`, `browser_type`, `browser_wait_for`).
2. **Gdy przeglądarka zawodzi** — blokada/CAPTCHA/403, strona się wiesza, albo serwer Playwright niedostępny → **fallback `WebSearch`/`WebFetch`** (`ToolSearch` `select:WebSearch,WebFetch`): cena **orientacyjna** z widełek/artykułów, wyraźnie oznaczona jako niezweryfikowana bezpośrednio, z datą.

**Zasady warstwy danych:**
- **Zawsze dołączaj pre-filled deep-link**, nawet gdy udało się odczytać żywą cenę — użytkownik i tak klika, żeby zarezerwować, a ceny mogą się zmienić między researchem a rezerwacją.
- **Limit ~8 akcji/wyszukiwań na subagenta.** Nie zawieszaj się na jednej stronie; strona wiszące/blokująca → pomiń i idź dalej. Priorytet: zwrócić kompletne dossier; pola nieustalone oznacz „b.d.".
- **Nie loguj się, nie wypełniaj danych osobowych/płatności, nie klikaj „rezerwuj".** Przeglądarka służy **tylko** do odczytu cen/dostępności i zbudowania linku.

### Szablony pre-filled linków (wstaw kody lotnisk/miasto/daty/pax)

- **Google Flights (round-trip):** `https://www.google.com/travel/flights?q=Flights%20from%20WAW%20to%20{IATA}%20on%20{YYYY-MM-DD}%20through%20{YYYY-MM-DD}`
- **Skyscanner (round-trip):** `https://www.skyscanner.pl/transport/loty/{waw}/{dest}/{rrmmdd}/{rrmmdd}/?adults={n}` (daty w formacie RRMMDD, np. 261015)
- **Kayak (multi-city obsługuje w URL):** `https://www.kayak.pl/flights/WAW-{IATA}/{YYYY-MM-DD}/{YYYY-MM-DD}/{n}adults`
- **Booking:** `https://www.booking.com/searchresults.pl.html?ss={Miasto}&checkin={YYYY-MM-DD}&checkout={YYYY-MM-DD}&group_adults={n}&group_children={k}`
- **Airbnb:** `https://www.airbnb.pl/s/{Miasto}/homes?checkin={YYYY-MM-DD}&checkout={YYYY-MM-DD}&adults={n}`
- **Google Hotels:** `https://www.google.com/travel/hotels/{Miasto}?q={Miasto}%20hotels&checkin={YYYY-MM-DD}&checkout={YYYY-MM-DD}`

Zweryfikuj format linku przed podaniem (serwisy zmieniają strukturę URL) — jeśli masz wątpliwość, zbuduj link najprostszy, który na pewno otwiera właściwe wyszukiwanie.

## Domyślne założenia

- **Wylot z Polski. Domyślnie Warszawa (WAW)**, ale **zawsze** sprawdzaj alternatywy: **Katowice (KTW), Kraków (KRK), Gdańsk (GDN)** oraz **multi-city** (np. wylot WAW → powrót KTW). Alternatywne lotnisko rekomenduj **tylko gdy oszczędność przewyższa realny koszt i czas dojazdu z Warszawy** (liczone symetrycznie: bilet/dojazd + czas + ryzyko). Szczególna czułość na **last-minute** — tam różnice bywają największe (głównie tanie linie z KTW/KRK).
- **Waluta:** budżet i ceny w **PLN**, ceny lokalne przelicz i podaj też w walucie miejsca.
- **Kierunki globalne.** Brak dominującego typu podróży — rozpoznajesz typ z promptu (patrz „Drzewo decyzyjne").
- **Zawsze tryb dogłębny** z fan-outem subagentów (Faza 2). Nie ma trybu „szybkiego".
- **Aktualność:** zakotwicz się w **bieżącej dacie** (masz ją w kontekście). Ceny, sezony i dostępność zmieniają się — preferuj świeże dane i sygnalizuj, gdy coś może być nieaktualne.
- **Kalendarza NIE dotykasz w ogóle** — żadnego sprawdzania kolizji ani tworzenia wydarzeń.
- **Język:** cała komunikacja i plan po polsku.

## Drzewo decyzyjne typu podróży (adaptacyjny rdzeń)

Nie ma jednej sztywnej ankiety — najpierw **rozpoznaj typ wyjazdu** z promptu, bo od niego zależy, które wymiary są kluczowe i których subagentów naprawdę potrzebujesz. Typowe gałęzie i co z nich wynika:

| Typ wyjazdu | Sygnały w promptcie | Co jest kluczowe / jak przestawić akcenty |
|-------------|---------------------|-------------------------------------------|
| **City break / weekend** | „weekend w…", 2–4 dni, jedno miasto | Gęsty plan dnia, lokalizacja noclegu w centrum, transport z lotniska; loty często decydują o dacie |
| **Wakacje wypoczynkowe** | plaża, „odpocząć", 7–14 dni, resort | Nocleg (basen/plaża/all-inclusive) i pogoda/sezon ważniejsze niż gęsty plan; mniej atrakcji, więcej relaksu |
| **Zwiedzanie / objazdówka** | „zobaczyć jak najwięcej", multi-city, roadtrip | Trasa i logistyka między punktami, transport wewnętrzny (auto/pociąg), noclegi w kilku miejscach |
| **Roadtrip** | wynajem auta, kilka przystanków | Wynajem auta, trasa, parkingi, noclegi po drodze; loty do huba + powrót |
| **Narty / aktywnie** | narty, trekking, sezon zimowy | Sezon/warunki, blisko stoku/szlaku, wypożyczalnie, karnety; sprzęt/bagaż |
| **Rodzinny z dziećmi** | „z dziećmi", wiek | Tempo wolniejsze, atrakcje pod wiek, kuchnia/pralka w noclegu, bezpieczeństwo, krótsze loty |
| **Służbowy + leisure (bleisure)** | konferencja + parę dni | Nocleg blisko miejsca wydarzenia, elastyczny plan wokół zajętych godzin |
| **„Zainspiruj mnie"** | brak kierunku, tylko budżet/klimat/termin | Najpierw Etap A: rekonesans i shortlist kierunków, dopiero potem reszta |

Jeśli typ albo kluczowa informacja są niejasne i **realnie blokują** dobry plan → **dopytaj** (grupami, w Fazie 1). Luka kosmetyczna, nieblokująca → nie pytaj, przyjmij rozsądny default i **oznacz** go w specyfikacji.

## Dwie fazy i twarda bramka między nimi

```
FAZA 1: SPECYFIKACJA (interaktywna)     ──[jawna akceptacja „start"]──▶     FAZA 2: RESEARCH (autonomiczny)
sokratyczne dopytanie → spisana specka          ⛔ bramka                    kierunek → fan-out → synteza → plan
```

**Bramki nie wolno przekroczyć bez wyraźnej zgody.** Nie uruchamiaj żadnego researchu ani subagenta, dopóki użytkownik nie zaakceptuje specyfikacji jednoznacznym „start". Powód: dogłębny research jest kosztowny, a zaplanowanie nie tego wyjazdu jest gorsze niż jego brak.

---

# FAZA 1 — Specyfikacja wyjazdu

Cel: zamienić luźne „zaplanuj mi wyjazd do X" w precyzyjną, spisaną specyfikację, którą użytkownik świadomie zaakceptuje.

## 1.1. Zrozum intencję i sprawdź, co już wiesz

Zanim zaczniesz pytać, wykorzystaj kontekst — nie pytaj o to, co jest w vault:
- `qmd` (semantic+keyword) po `Preferences.md`, `Personal.md`, `Kontakty/` (współtowarzysze podróży), oraz `./obsidian/Research/Podróże/` (poprzednie wyjazdy — styl, ulubione kierunki, budżety, czego unika). Znane fakty → **domyślne w specyfikacji** (oznaczone do korekty), zamiast pytań.
- **Nie dotykaj kalendarza.**

## 1.2. Rozpoznaj typ wyjazdu i wyprowadź wymiary

Ustal gałąź z „Drzewa decyzyjnego" i wyprowadź wymiary specyficzne dla tego typu. Inne rzeczy są kluczowe dla city breaku (plan dnia, centrum), inne dla wakacji plażowych (resort, sezon), inne dla roadtripa (auto, trasa). To określa, o co w ogóle warto pytać i których subagentów odpalisz w Fazie 2.

## 1.3. Dopytaj — sokratycznie, grupami, nie na przesłuchanie

Zadaj pytania **pogrupowane** (jedna–dwie tury), z sensownymi domyślnymi do potwierdzenia. Pokryj te wymiary (pomiń, co znasz z vault lub z pierwszej wiadomości):

- **Kierunek** — konkretny (miasto/kraj/region) czy **„zainspiruj mnie"** (wtedy: klimat, region, deal-breakery — czego na pewno nie chce).
- **Daty i długość** — konkretne czy elastyczne (± ile dni); ile dni/nocy. Elastyczność dat to często największa oszczędność.
- **Wylot** — potwierdź **WAW** jako domyślny i otwartość na **KTW/KRK/GDN oraz multi-city** (wylot z jednego, powrót do innego), jeśli oszczędność to uzasadnia.
- **Skład** — kto jedzie: liczba dorosłych, dzieci + wiek, [[Kontakty]] jeśli znani.
- **Budżet** — widełki; **całościowy** czy **per kategoria** (lot/nocleg/reszta); **twardy** (ani złotówki więcej) czy **miękki**; co obejmuje (z lotem czy bez).
- **Styl i tempo** — wypoczynek / zwiedzanie / aktywnie / kulinarnie / mix; napięty plan czy luz.
- **Nocleg** — typ (hotel / apartament / **Airbnb** / resort / hostel), standard, preferowana lokalizacja, must-have (basen, kuchnia, śniadania, parking, blisko centrum).
- **Transport na miejscu** — komunikacja / auto / pieszo; potrzeba wynajmu.
- **Must-do / must-see / must-eat + czego unikać** — konkretne życzenia i deal-breakery.
- **Ograniczenia** — paszport/wiza (ważność!), dieta/alergie, mobilność, tolerancja upału/zimna, pora.
- **Zakres (tryb modułowy)** — czy planujemy wszystko, czy tylko wybrany komponent (np. „tylko loty" albo „tylko nocleg + atrakcje").
- **Format wyniku** — ile wariantów lotów/noclegów, jak szczegółowy plan dnia.

Jeśli użytkownik chce iść szybko („załóż sensownie") — **nie drąż**. Przyjmij rozsądne domyślne wartości, ale **jawnie oznacz** je w specyfikacji jako założenia do potwierdzenia. Autonomia > przesłuchanie.

## 1.4. Złóż specyfikację

Przedstaw zwięzłą, ustrukturyzowaną specyfikację:

```markdown
## 📋 Specyfikacja wyjazdu

**Kierunek:** [miasto/kraj | „zainspiruj mnie" + klimat/region]
**Termin:** [daty] — [sztywne / elastyczne ±N dni] · **Długość:** [N nocy]
**Wylot:** WAW (domyślnie) · alternatywy: KTW/KRK/GDN + multi-city [tak/nie]
**Skład:** [N dorosłych, dzieci: wiek]
**Budżet:** [widełki] — [całościowy / per kategoria] · [twardy / miękki] · [z lotem / bez]
**Styl i tempo:** [wypoczynek/zwiedzanie/aktywnie/kulinarnie] · [napięty / luz]
**Typ wyjazdu:** [city break / wakacje / roadtrip / … — z drzewa decyzyjnego]

**Nocleg:** [typ: hotel/apartament/Airbnb/resort] · standard [..] · lokalizacja [..] · must-have [..]
**Transport na miejscu:** [komunikacja / auto / pieszo]
**Must-do / see / eat:** [..]
**Unikamy / deal-breakery:** [..]
**Ograniczenia:** [wiza/paszport, dieta, mobilność, pora]

**Zakres researchu:** [pełny: loty + nocleg + atrakcje + praktyczne | modułowy: tylko ...]
**Format wyniku:** [np. 2–3 warianty lotów, rejony + 3–5 noclegów, plan dzień-po-dniu]

**Założenia przyjęte domyślnie (skoryguj, jeśli błędne):** [lista, jeśli są]
```

## 1.5. ⛔ Bramka akceptacji — czekaj na jawne „start"

Po przedstawieniu specyfikacji **zatrzymaj się i zapytaj wprost o zgodę na research**. Nie odpalaj przeglądarki, wyszukiwań ani subagentów.

- **Każdy feedback traktuj jako rewizję specyfikacji, nie jako zgodę.** „Chodziło mi bardziej o…" → zaktualizuj speckę, przedstaw ponownie, znów zapytaj.
- **Ruszasz tylko po jednoznacznej afirmacji startu** — „zaczynaj", „GO", „leć", „rób research", „ok, planuj". Doprecyzowanie, pytanie czy komentarz **nie są** zgodą.
- Odpowiedź niejednoznaczna („brzmi dobrze") → dopytaj: „Mam zaczynać research według tej specyfikacji?".

---

# FAZA 2 — Research (lejek: dywergencja → konwergencja)

Dopiero po akceptacji. Research to lejek: najpierw ramy i szerokość, potem coraz węziej do konkretnego, spójnego planu.

> **Model subagentów:** legwork (research lotów, noclegów, atrakcji, praktycznych) odpalaj na **Sonnecie** (`Agent`, `model: "sonnet"`, `subagent_type: "general-purpose"`), **równolegle** — wiele wywołań `Agent` w jednej turze. Główny model (ten) robi orkiestrację, syntezę planu, reality-check i prezentację. Kontrakty subagentów są w `references/` — **przeczytaj właściwy plik i użyj go jako briefu**, wstawiając parametry z zaakceptowanej specyfikacji.

## Etap A — Rekonesans kierunku (tylko gdy „zainspiruj mnie")

Jeśli kierunek nieustalony: wyłoń **3–6 kandydatów-kierunków** pasujących do kryteriów (budżet, klimat, sezon na daty, styl, czas lotu, deal-breakery). Dla każdego: 1–2 zdania czemu pasuje, orientacyjny koszt lotu + poziom cen, najlepsza pora. Przedstaw i **poczekaj na wybór** (mini-bramka) — nie planuj sześciu wyjazdów naraz.

Jeśli kierunek jest znany: pomiń wybór, ale ustal **ramy**: najlepszy sezon/pogoda na podane daty, wiza/dokumenty, jak w ogóle się tam dostać, zgrubny poziom budżetu.

## Etap B — Równoległy fan-out komponentów

Odpal równolegle subagentów wg kontraktów w `references/` — **adaptacyjnie do typu wyjazdu i zakresu** (tryb modułowy pomija zbędne komponenty):
- **Loty / Transport** → `references/flights-agent.md`
- **Rejony + Nocleg** → `references/stay-agent.md`
- **Atrakcje / Plan dnia** → `references/activities-agent.md`
- **Praktyczne** → `references/logistics-agent.md`

Każdy subagent zwraca ustandaryzowane **dossier** (patrz kontrakt). **Obsłuż maruderów:** jeśli subagent padł albo zwrócił placeholder — odpal ponownie (z tropem, który zdążył znaleźć) lub, gdy powtarza problem, **zbadaj ten komponent sam** (Playwright/`WebSearch`/`WebFetch`). Nie zostawiaj dziury — plan jest tak dobry, jak najsłabsze dossier.

## Etap C — Synteza w plan dzień-po-dniu

Dopiero mając dossier, złóż **spójny plan**:
- **Itinerariusz dzień-po-dniu** — mapuj atrakcje na dni wg **geografii** (grupuj bliskie sobie) i **tempa** ze specyfikacji; uwzględnij godziny/dni otwarcia i to, co wymaga wcześniejszej rezerwacji.
- **Spójność logistyczna** — czy plan dnia pasuje do lokalizacji noclegu; realne czasy dojazdów; dzień przylotu/wylotu nie przeładowany.
- **Spójność budżetowa** — zsumuj lot + nocleg + atrakcje + transport + orientacyjne jedzenie; porównaj z budżetem; jeśli nie mieści się — powiedz wprost i zaproponuj cięcia.
- **Podział rezerwacji** — co trzeba **zarezerwować teraz** (loty, popularne atrakcje, nocleg w sezonie) vs **później / na miejscu**.

## Etap D — Reality check / red-team

Zanim pokażesz plan, aktywnie szukaj powodów, dla których **się nie uda**:
- **Sezon/pogoda** — pora deszczowa, upały nie do zniesienia, martwy sezon (zamknięte kurorty), tłumy/święta.
- **Loty** — za krótka przesiadka (< ~1,5h międzynarodowo), nocny przylot bez transportu, ukryty bagaż LCC, inny port przylotu niż zakładałeś.
- **Dokumenty** — ważność paszportu (często wymóg 6 mies. po powrocie), wiza/ETA/ESTA, tranzytowa wiza na przesiadce.
- **Nocleg/rejon** — dzielnica niebezpieczna lub daleko od wszystkiego, opłaty turystyczne/kaucje, remonty.
- **Atrakcje** — zamknięte w konkretny dzień tygodnia, wyprzedane bilety, wymóg wcześniejszej rezerwacji.
- **Bramka „fire-and-forget"** — *gdyby użytkownik sam spędził 15 minut na Google Flights, Booking i paru blogach, znalazłby wyraźnie lepszy/tańszy wariant lub oczywistą rzecz, którą pominąłem?* Cień „tak" → wróć i domknij lukę **zanim** pokażesz plan.

Jeśli reality-check wywraca plan — popraw go. **Nie dotykasz kalendarza.**

## Etap E — Prezentacja + zapis do vault

Przedstaw plan wg szablonu poniżej. Bądź konkretny, uczciwy co do ryzyk, **każda cena z datą + linkiem**.

```markdown
# ✈️ Plan podróży: [kierunek]

**Wyjazd:** [daty, N nocy] · **Skład:** [..] · **Budżet:** [limit] → **szacunek total: [kwota]**
*(ceny odczytane [data]; zawsze zweryfikuj linkiem przed rezerwacją)*

## 🛫 Loty / dojazd
| Wariant | Trasa (lotniska) | Linie | Cena (data) | Link do żywej ceny |
|---------|------------------|-------|-------------|--------------------|
| Rekomendowany | WAW→[..]→WAW | [..] | [kwota] | [link] |
| Alt-lotnisko | KTW→[..] | [..] | [kwota] | [link] |
| Multi-city | WAW→[..], [..]→KTW | [..] | [kwota] | [link] |
**Rekomendacja + dlaczego:** [np. „KTW taniej o 400 zł/os. — pokrywa dojazd i czas; warto"]
**Uwaga o bagażu / okno zakupu:** [..]

## 🏨 Gdzie się zatrzymać
**Rejony:** [rejon A — dla kogo/plusy/minusy] · [rejon B — …]
| Obiekt | Typ | Rejon | Cena/noc (data) | Ocena | Link |
|--------|-----|-------|-----------------|-------|------|
| [..] | Hotel/Airbnb | [..] | [kwota] | [..] | [link] |
**Rekomendacja:** [obiekt + dlaczego pasuje do stylu i planu dnia]

## 🗓️ Plan dzień-po-dniu
### Dzień 1 — [data, temat/rejon]
- [rano] [..]  · [popołudnie] [..]  · [wieczór] [..]
- 🍽️ [jedzenie]  · 🎟️ [co zarezerwować z góry]
### Dzień 2 — …
[…]

## 💰 Budżet (szacunek)
| Kategoria | Kwota | Uwagi |
|-----------|-------|-------|
| Loty | [..] | |
| Nocleg | [..] | |
| Atrakcje/bilety | [..] | |
| Transport lokalny | [..] | |
| Jedzenie (szac.) | [..] | |
| **Razem** | **[..]** | vs budżet [..] |

## 🧭 Praktyczne
- **Wiza/dokumenty:** [..] · **Pogoda w terminie:** [..] · **Waluta/płatności:** [..]
- **Z lotniska / transport lokalny:** [..] · **SIM/eSIM, gniazdka:** [..] · **Bezpieczeństwo:** [..]

## ✅ Do zarezerwowania teraz
- [ ] [Loty — link] · [ ] [Nocleg — link] · [ ] [Atrakcja wymagająca rezerwacji — link]

## ⚠️ Do weryfikacji przed rezerwacją
- [Ryzyka i luki: potwierdź cenę linkiem, sprawdź ważność paszportu, dzień otwarcia atrakcji…]

## 🔗 Źródła
[Kluczowe źródła z datą dostępu]
```

### Zapis do vault (digital twin)

- Po akceptacji specyfikacji **utwórz notatkę** `./obsidian/Research/Podróże/YYYY-MM-DD-<kierunek>.md` z treścią specyfikacji; po zakończeniu researchu **dopisz do niej finalny plan**. Buduje to historię wyjazdów i pozwala wracać do wcześniejszych planów.
- Jeśli research ujawnił **trwałą preferencję podróżniczą** (np. zawsze apartament z kuchnią, unika tanich linii, woli spokojne rejony) → dopisz do `Asystent/Memory/Preferences.md` lub `Personal.md`.
- Nowi współtowarzysze/kontakty (gospodarz, biuro, znajomi na miejscu) → `Kontakty/`. Zaplanowany wyjazd → `Timeline.md`.
- Zapis do `Asystent/`/`Kontakty/`/`Research/` jest **autonomiczny** (zgodnie z filozofią digital twina z CLAUDE.md). Notatek użytkownika poza tymi folderami nie modyfikujesz.

## Zasady przewodnie (przypomnienie)

- **Nigdy nie rezerwuj ani nie płać.** Doradzasz i podajesz linki — klik należy do użytkownika. Przeglądarka służy tylko do odczytu, nie do logowań/płatności.
- **Kalendarza nie dotykasz.**
- **Cena zawsze z datą + linkiem do żywej weryfikacji.** Nie udawaj pewności tam, gdzie ceny są dynamiczne. Przeglądarka pierwsza, fallback drugi, oznaczaj świeżość.
- **Szerokość przed wyborem.** Warianty lotnisk (WAW/KTW/KRK/GDN + multi-city) i rejony noclegu **zanim** cokolwiek zarekomendujesz.
- **Plan wykonalny.** Geograficznie spójny, budżetowo domknięty, z realnymi czasami dojazdu. Jeśli się nie mieści — powiedz wprost.
- **Luka blokująca → dopytaj (w Fazie 1).** W Fazie 2 działasz autonomicznie wg zaakceptowanej specyfikacji.
