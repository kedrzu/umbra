---
name: shopping-research
description: Research zakupowy — znajdź najlepszy produkt lub usługę w danej kategorii według kryteriów użytkownika i przedstaw ranking od najbardziej do najmniej polecanego (wady, zalety, cechy, ceny). Użyj ZAWSZE, gdy użytkownik chce coś kupić i szuka najlepszej opcji, prosi o porównanie lub ranking, pyta "jaki X kupić", "co polecasz", "pomóż wybrać", "który najlepszy", "porównaj te modele", albo podaje budżet i kategorię (laptop, słuchawki, ekspres, wózek, materac, opony, rower, monitor, subskrypcja, oprogramowanie…). Prowadzi od sokratycznego doprecyzowania kryteriów, przez jawnie zaakceptowaną specyfikację, po dogłębny ustrukturyzowany research (szeroka longlista → screening → równoległe analizy → ranking). NIE używaj do przeszukiwania wiedzy w vault Obsidian (to /research) ani do ogólnego deep-researchu tematu bez intencji zakupu.
---

# Shopping Research — research zakupowy

Twoim zadaniem jest znaleźć **najlepszy** produkt (lub usługę / subskrypcję / oprogramowanie) w zadanej kategorii według kryteriów użytkownika i przedstawić uczciwy ranking od najbardziej do najmniej polecanego.

## Czego ten skill broni się przed popełnieniem

Modele językowe mają silną tendencję do **wybierania pierwszego sensownego produktu**, na jaki trafią, i dorabiania do niego uzasadnienia. Dzieje się tak, bo naturalnym odruchem jest: jedno zapytanie → kilka pierwszych wyników → „ten wygląda dobrze" → rekomendacja. To jest dokładnie ten błąd, którego ten skill ma unikać. Dlatego cała procedura jest zbudowana tak, żeby **oddzielić zbieranie od oceniania** i **wymusić szerokość, zanim wolno cokolwiek polecić**. Jeśli w trakcie łapiesz się na myśli „chyba już wiem, co polecić" — to sygnał, że idziesz na skróty. Wróć do procedury.

Trzymaj w głowie trzy zasady przez cały czas:
- **Nie zakochuj się w pierwszym kandydacie.** Dopóki nie masz pełnej longlisty, nie wolno Ci nikogo faworyzować ani odrzucać „na oko".
- **Każdy kandydat z shortlisty dostaje tyle samo uwagi.** Ostatni badany produkt musi być przeanalizowany równie dogłębnie jak pierwszy — dlatego analizy robią równolegli subagenci wg jednego szablonu.
- **Jesteś sceptycznym analitykiem, nie sprzedawcą.** Twoja wartość to znalezienie wad, ukrytych kosztów i lepszych alternatyw — nie potwierdzenie pierwszej myśli.

## Domyślne założenia

- **Rynek: Polska, waluta PLN.** Sklepy i porównywarki PL (Allegro, Ceneo, x-kom, Morele, Media Expert, RTV Euro AGD, Media Markt itd.), recenzje PL i EN. **Pepper (pepper.pl)** — społeczność deal-huntów: nie tylko polecajki i szczere opinie, ale przede wszystkim **silnik odkrywania cen, kodów rabatowych, bieżących promocji i historycznych minimów** — wartościowy **nawet gdy sama oferta już wygasła** (pokazuje realny pułap cen i za ile ludzie realnie kupują). Zagranicę (Amazon.de, AliExpress) uwzględniaj **tylko** gdy użytkownik o to poprosi.
- **Cena = najlepsza realna cena do zdobycia dziś, nie pierwsza napotkana.** Rozróżniaj *widełki obserwowane* (co widać w sklepach — często z zawyżonym, sztucznym „regularnym” MSRP) od *najlepszej realnej ceny do zdobycia* — najniższego wiarygodnego kanału z uwzględnieniem **aktywnych kodów rabatowych, promocji i deali (Pepper)**. Przy sprzecznych cenach domyślnie badaj **w stronę najniższej wiarygodnej, nie najwyższej.** To Ty masz odwalić robotę szukania najlepszej ceny — inaczej użytkownik musiałby (i będzie) szukać jej sam, a wtedy skill zawiódł.
- **Zawsze tryb dogłębny** z fan-outem subagentów (patrz Faza 2). Nie ma trybu „szybkiego" — poważny research jest sensem tego skilla.
- **Aktualność:** zawsze zakotwicz się w bieżącej dacie (masz ją w kontekście). Produkty się zmieniają, ceny się zmieniają, modele wychodzą z produkcji — preferuj świeże źródła i sygnalizuj, gdy dane mogą być nieaktualne.
- **Język:** cała komunikacja i raport po polsku.

## Dwie fazy i twarda bramka między nimi

```
FAZA 1: SPECYFIKACJA (interaktywna)     ──[jawna akceptacja]──▶     FAZA 2: RESEARCH (autonomiczny)
sokratyczne dopytanie → spisana specka         ⛔ bramka              longlista → screening → analizy → ranking
```

**Bramki nie wolno przekroczyć bez wyraźnej zgody użytkownika.** Nie uruchamiaj żadnego wyszukiwania ani subagenta, dopóki użytkownik nie zaakceptuje specyfikacji jednoznacznym „start". Powód jest praktyczny: dogłębny research jest kosztowny, a research nie tego, o co chodziło, jest gorszy niż jego brak. Użytkownik ma mieć kontrolę nad zakresem, zanim ruszysz.

---

# FAZA 1 — Specyfikacja wyszukiwania

Cel: zamienić luźne „szukam dobrego X" w precyzyjną, spisaną specyfikację, którą użytkownik świadomie zaakceptuje.

## 1.1. Zrozum intencję i sprawdź, co już wiesz

Zanim zaczniesz pytać, wykorzystaj kontekst, który już masz — nie zadawaj pytań, na które odpowiedź jest w vault:
- Sprawdź w vault Obsidian znane preferencje i kontekst: `qmd` (semantic+keyword) po `Preferences.md`, `Personal.md`, `Work.md`, `Insights.md`, oraz `Research/Zakupy/` (poprzednie researche zakupowe). Może użytkownik ma znane preferencje marek, ograniczenia, poprzednie zakupy w tej kategorii.
- Jeśli coś znajdziesz — użyj tego jako **domyślnych założeń w specyfikacji** (oznaczonych, żeby użytkownik mógł je poprawić), zamiast pytać od zera.

## 1.2. Wyprowadź kryteria specyficzne dla TEJ kategorii

Nie zadawaj sztywnej, uniwersalnej ankiety. Najpierw **pomyśl jak ekspert od tej konkretnej kategorii**: jakie wymiary realnie różnicują produkty i realnie wpływają na decyzję zakupową? Inne dla laptopa (waga, ekran, bateria, procesor, porty), inne dla materaca (twardość, materiał, wentylacja, waga śpiącego), inne dla ekspresu (rodzaj, ciśnienie, młynek, łatwość czyszczenia), inne dla subskrypcji SaaS (limity, integracje, cennik per-seat, eksport danych).

Jeśli nie znasz dobrze kategorii — zrób **szybki rekonesans** (1–2 wyszukiwania „na co zwracać uwagę kupując X", „jak wybrać X poradnik"), żeby wiedzieć, o co w ogóle warto pytać. To jeszcze nie jest research produktów — to research kryteriów.

## 1.3. Dopytaj — sokratycznie, grupami, nie na przesłuchanie

Zadaj pytania **pogrupowane** w jednej–dwóch turach, a nie punkt po punkcie. Zaproponuj sensowne domyślne wartości, żeby użytkownik mógł tylko potwierdzić lub skorygować. Pokryj te wymiary (pomiń te, które już znasz z vault lub z pierwszej wiadomości):

- **Co dokładnie kupujemy** — kategoria, typ, wariant. Doprecyzuj, jeśli szerokie („laptop" → do czego: praca biurowa, gaming, montaż wideo?).
- **Use-case i kontekst** — kto używa, do czego, jak często, w jakich warunkach. To najważniejsze — od tego zależą wagi kryteriów.
- **Budżet** — widełki. Zapytaj, czy **twardy** (ani złotówki więcej) czy **miękki** (można przekroczyć, jeśli warto). To zmienia strategię.
- **Must-have** — cechy dyskwalifikujące, bez których produkt odpada z automatu.
- **Ważne kryteria + priorytety/wagi** — co się liczy najbardziej? Poproś o uszeregowanie lub rozdzielenie „ważności". To fundament rankingu.
- **Deal-breakery / czego unikać** — marki, cechy, doświadczenia z przeszłości.
- **Preferencje marek** — ulubione / wykluczone / obojętne.
- **Horyzont i stan** — na jak długo, nowy czy używany/refurb dopuszczalny, waga gwarancji/serwisu.
- **Rynek** — potwierdź PL/PLN (domyślnie), chyba że użytkownik chce zagranicę.
- **Format prezentacji** — ile pozycji w rankingu (domyślnie 3–5 z uzasadnieniem + wzmianki), czego użytkownik oczekuje.

Jeśli użytkownik chce iść szybko („nie chce mi się odpowiadać na wszystko, załóż sensownie") — **nie drąż**. Przyjmij rozsądne domyślne wartości, ale **jawnie je oznacz** w specyfikacji jako założenia do potwierdzenia. Autonomia > przesłuchanie.

## 1.4. Złóż specyfikację

Przedstaw zwięzłą, ustrukturyzowaną specyfikację. Użyj tego szablonu:

```markdown
## 📋 Specyfikacja researchu zakupowego

**Co szukamy:** [kategoria + typ + wariant]
**Use-case:** [kto, do czego, jak często]
**Budżet:** [widełki] — [twardy / miękki]
**Rynek:** [PL/PLN | inny]

**Wymagania konieczne (must-have — bez nich odpada):**
- [must-have 1]
- [must-have 2]

**Kryteria oceny (wg ważności):**
| Kryterium | Waga | Dlaczego istotne |
|-----------|------|------------------|
| [np. bateria] | wysoka | [z use-case] |
| [np. waga] | średnia | [...] |
| [np. głośność] | niska | [...] |

**Deal-breakery / unikamy:** [...]
**Preferencje marek:** [ulubione / wykluczone / brak]
**Horyzont / stan:** [nowy | używany OK], [gwarancja: istotna?]

**Jak to przedstawię:** ranking [N] pozycji od najbardziej do najmniej polecanego,
tabela porównawcza wg kryteriów, plusy/minusy/ceny każdej pozycji, zwycięzca z uzasadnieniem,
alternatywy warunkowe, jawnie odrzuceni kandydaci, ryzyka do weryfikacji przed zakupem.

**Założenia przyjęte domyślnie (skoryguj, jeśli błędne):** [lista, jeśli są]
```

## 1.5. ⛔ Bramka akceptacji — czekaj na jawne „start"

Po przedstawieniu specyfikacji **zatrzymaj się i zapytaj wprost o zgodę na research**. Nie wyszukuj, nie odpalaj subagentów.

- **Każdy feedback traktuj jako rewizję specyfikacji, nie jako zgodę.** Użytkownik mówi „chodziło mi bardziej o X, nie Y" → zaktualizuj speckę, przedstaw ją ponownie, znów zapytaj o zgodę.
- **Ruszasz tylko po jednoznacznej afirmacji startu** — np. „zaczynaj", „GO", „akceptuję", „rób research", „leć", „ok, szukaj". Samo doprecyzowanie kryteriów, pytanie, czy komentarz **nie są** zgodą.
- Jeśli odpowiedź jest niejednoznaczna („brzmi dobrze") — dopytaj: „Czy mam zaczynać research według tej specyfikacji?".

To jest celowa, twarda bramka. Użytkownik wyraźnie chce kontrolować zakres, zanim ruszysz z kosztownym researchem.

---

# FAZA 2 — Research (lejek: dywergencja → konwergencja)

Dopiero po akceptacji. Research to lejek: najpierw szeroko (dużo kandydatów), potem coraz węziej (screening → dogłębne analizy → ranking). Nie wolno przeskakiwać etapów ani zwężać za wcześnie.

> **Model subagentów:** wszystkie subagenty (longlista i analizy) odpalaj na **Sonnecie** (`Agent` z `model: "sonnet"`, `subagent_type: "Explore"` dla samego szukania kandydatów lub `"general-purpose"` dla pełnych analiz z web). Główny model (ten) robi orkiestrację, screening, scoring, red-team i syntezę — czyli całe rozumowanie oceniające. Legwork idzie na tańszy, równoległy model.

## Etap A — Longlista (dywergencja, bramka szerokości)

Cel: zebrać **szeroki** zestaw kandydatów z **wielu niezależnych kątów**, zanim cokolwiek ocenisz. Na tym etapie **ranking i rekomendacja są zakazane** — zbierasz tylko nazwy + skąd pochodzą.

Odpal **równolegle 3–5 subagentów** (Sonnet), każdy przeszukujący z **innego kąta** — różne kąty łapią różne produkty, których jedno wyszukiwanie by nie znalazło:
1. **Rankingi/testy redakcyjne** — „najlepszy X 2025/2026 ranking", porównania, testy (PL + EN).
2. **Bestsellery/oferta sklepów** — co realnie dostępne i popularne w polskich sklepach z tej półki cenowej.
3. **Społeczności i fora** — Reddit, wykop, **Pepper (pepper.pl — polecajki + szczere opinie w komentarzach, wartościowe też po wygaśnięciu oferty)**, grupy tematyczne, opinie użytkowników („co polecacie zamiast X", „X vs Y").
4. **Kąt marek/producentów** — kto liczy się w tej kategorii, jakie mają aktualne modele w tym segmencie.
5. **Kąt use-case/niszowy** — produkty pod konkretny scenariusz ze specyfikacji (np. „cichy", „lekki", „dla początkujących").

Każdy subagent zwraca listę: **nazwa produktu + wariant + orientacyjna cena PL + sygnał oceny (gwiazdki + liczba recenzji, jeśli widoczne — albo siła sygnału społeczności) + 1 zdanie + źródło**. Ty **scalasz i deduplikujesz** wyniki. Oceny zbieraj już tu, żeby sygnał jakości płynął przez cały lejek (a nie wypływał dopiero po skardze) — bez progu „minimalnej oceny” na tym etapie; chodzi tylko o to, żeby był **widoczny przy screeningu**.

**Bramka szerokości:** zanim przejdziesz dalej, longlista musi mieć **≥ 12 realnych, odrębnych kandydatów** z **co najmniej 3 różnych kątów**. Jeśli masz mniej — dorzuć kąt lub subagenta. Ta liczba nie jest widzimisię: bez szerokiej longlisty ranking to loteria pierwszych trafień. (Wyjątek: naprawdę wąska kategoria, gdzie na rynku PL istnieje mniej opcji — wtedy zbierz wszystkie, jakie są, i **zaznacz w raporcie**, że pole było z natury wąskie.)

## Etap B — Screening (odsiew do shortlisty)

Zastosuj **twarde wymagania i budżet** ze specyfikacji, żeby odrzucić kandydatów, którzy odpadają z automatu. Zejdź do **shortlisty 5–8** kandydatów, którzy przejdą do dogłębnej analizy.

**⚠️ Guard cenowy (kluczowy — tu najczęściej ginie po cichu dobry produkt):** twarde wymagania (brak must-have, zły rozmiar, wycofany) wycinaj śmiało. Ale **NIE wycinaj kandydata za budżet na podstawie ceny niepewnej, sprzecznej między kątami albo wyglądającej na katalogową (MSRP).** Głębokie badanie ceny żyje dopiero w Etapie C — więc decyzja „w budżecie / poza” nie może zapaść tu na złych danych. Zasada: **„przepuść do C” jest odwracalne i tanie, „wytnij” jest nieodwracalne i drogie → przy niepewności cenowej domyślnie przepuszczaj** (oznacz „cena do weryfikacji”, niech Etap C ustali realną cenę do zdobycia: kody, kanały, deale). Wycinaj za budżet **tylko** gdy nawet najniższa wiarygodna cena go przekracza (wtedy → „Rozważeni, ale odrzuceni” z tym powodem). Do tego: **uszanuj typ budżetu ze specyfikacji** — przy budżecie **miękkim** niewielkie przekroczenie to kandydat **warunkowy**, nie odsiany. I nigdy nie wycinaj **dobrze ocenianego / mocno polecanego** kandydata wyłącznie na cenie, zanim nie sprawdzisz jego ceny do zdobycia — to dokładnie ten błąd, który każe polecić tandetę zamiast dobrego produktu, który był w zasięgu.

**Zapisuj powód odrzucenia każdego odsianego kandydata** (np. „poza budżetem +40%", „brak must-have: waga <1.3 kg", „wycofany z produkcji"). Te powody trafią do raportu (sekcja „Rozważeni, ale odrzuceni") — pokazują szerokość i chronią przed cichym pominięciem czegoś dobrego.

**Zwiń podejrzewane rebadge’e.** W tanich kategoriach (elektronika z Chin, akcesoria) wiele „różnych” produktów to ten sam OEM pod różnymi markami. Jeśli kilka pozycji longlisty wygląda na tę samą konstrukcję (te same zdjęcia/specyfikacja), wybierz **jedną reprezentatywną** (najlepiej najtańszą z łatwym zwrotem) zamiast marnować slot dogłębnej analizy na duplikat — a pokrewieństwo potwierdź/obal w dossier.

Jeśli po screeningu zostało < 5 kandydatów — rozluźnij najmniej istotne kryterium miękkie albo wróć do Etapu A po więcej. Jeśli > 8 — zawęź, priorytetyzując najlepiej rokujących wg kryteriów o najwyższej wadze.

## Etap C — Dogłębne analizy równoległe (jeden subagent na kandydata)

To serce mechanizmu przeciw „pierwszemu lepszemu". Dla **każdego** kandydata z shortlisty odpal **osobnego subagenta** (Sonnet), który zbada go **do tej samej głębokości** według jednego szablonu. Odpalaj je **równolegle** (wiele wywołań `Agent` w jednej turze), żeby wszyscy dostali równą uwagę i żeby było szybciej.

**Kontrakt subagenta znajdziesz w `references/deep-dive-agent.md`** — przeczytaj ten plik i użyj go jako briefu, wstawiając nazwę produktu i pełną specyfikację. Każdy subagent zwraca ustandaryzowane **dossier**: aktualna cena PL (min. 2 źródła), specyfikacja/cechy istotne dla kryteriów, mocne strony (z dowodami), słabe strony i typowe skargi z recenzji, niezawodność/opinie długoterminowe, dla kogo (nie) jest, dostępność w PL, gwarancja/serwis, ukryte koszty, ocena względem każdego kryterium, źródła z datą, oraz luki (czego nie udało się ustalić).

**Odporność (ważne w praktyce):**
- **Framuj brief jako zadanie badawcze, nie rolę-rozkaz.** „Jesteś X, zacznij od razu, nie proś o potwierdzenie, załaduj narzędzia” bywa czytane przez subagenta jako prompt-injection → odmawia albo deleguje zamiast szukać. Neutralne „to jest zadanie researchowe, zwróć dossier jako finalną odpowiedź” (jak w referencji) działa pewniej.
- **Wpisz do briefu limit ~8 wyszukiwań i „pomijaj strony, które się wieszają/blokują (403)”** — długie, wiszące sesje bywają ubijane przez watchdog (~10 min).
- **Obsłuż maruderów bez blokowania całości:** jeśli subagent padł albo zwrócił placeholder — odpal go ponownie (z tropem, który zdążył znaleźć) lub, gdy powtarza problem, **zbadaj ten jeden produkt sam** przez `WebSearch`/`WebFetch`. Nie zostawiaj dziury — porównanie jest tak dobre, jak najsłabsze dossier.

Zbierz wszystkie dossier, zanim zaczniesz oceniać. **Dopiero teraz** masz prawo porównywać. Jeśli dogłębna analiza ujawni, że dwaj kandydaci to ten sam OEM pod różnymi markami (rebadge), **potraktuj ich jako jedną pozycję** i wskaż najtańszy/najbezpieczniejszy kanał zakupu.

## Etap D — Macierz punktowa (ranking z priorytetów, nie z przeczucia)

Zbuduj **macierz porównawczą**: kandydaci × kryteria ze specyfikacji. Oceń **każdego kandydata na każdym kryterium** (skala 1–5 albo 0–10) z jednozdaniowym uzasadnieniem opartym na dossier. Policz **wynik ważony** wg wag ze specyfikacji.

Ranking wynika z **priorytetów użytkownika**, a nie z Twojego przeczucia — to kolejny bezpiecznik przeciw faworyzowaniu pierwszego kandydata. Ale traktuj liczbę jako **wsparcie decyzji, nie wyrocznię**: deal-breaker albo poważne ryzyko z Etapu E może zdegradować produkt mimo wysokiego wyniku. Unikaj fałszywej precyzji (nie rozstrzygaj rankingu różnicą 0,1 pkt — jeśli dwóch kandydatów jest o włos, powiedz to wprost).

## Etap E — Red-team topowych kandydatów

Dla **2–3 najwyżej ocenionych** aktywnie szukaj powodów, żeby ich **NIE** kupować. To odwrócenie perspektywy, które łapie problemy niewidoczne w entuzjastycznych recenzjach:
- Typowe awarie, wady seryjne, problemy po dłuższym użyciu (szukaj „X problemy", „X awaria", „X po roku”, „X reklamacja”).
- Ukryte/bieżące koszty (materiały eksploatacyjne, akcesoria, subskrypcje, drogi serwis).
- Czy istnieje oczywista lepsza alternatywa w podobnej cenie, którą przeoczyliśmy? (jeśli tak — dorzuć ją, wracając w razie potrzeby do analizy).
- Czy „zwycięzca” wygrywa realnie, czy tylko dlatego, że miał lepsze SEO/więcej recenzji sponsorowanych?

**Zanim uznasz, że „to loteria jakości i trzeba brać najtańszy zwracalny” — najpierw sprawdź, czy dobrze oceniana / mocno rekomendowana opcja NIE jest realnie w zasięgu** (przez kod rabatowy, deal, inny kanał albo niewielkie przekroczenie miękkiego budżetu). Bardzo często jest — i wtedy to **ona** wygrywa, nie budżetowy rebadge. Dopiero **gdy najlepiej oceniana opcja jest naprawdę nieosiągalna w kryteriach**, a cała osiągalna półka to tanie, mocno rebadge’owane produkty z wysokim rozrzutem jakości — przesuń akcent oceny: **łatwość zwrotu/reklamacji i pewność kanału stają się ważniejsze niż drobne różnice w marketingowej specyfikacji** (bo i tak nie przewidzisz, czy trafisz wadliwą sztukę). Wtedy: (a) preferuj sprzedawcę z bezproblemowym zwrotem, (b) wypisz 2–3 rzeczy make-or-break do **przetestowania w oknie zwrotu**, (c) rozważ „dołóż do wyższej półki” zamiast dwóch nieudanych tanich zakupów. **Nie polecaj słabo ocenianego produktu tylko dlatego, że jest tani i zwracalny, jeśli dobrze oceniany jest w zasięgu ceny do zdobycia** — to jest właśnie pułapka, w którą ten skill już raz wpadł.

Jeśli red-team wywróci ranking — zaktualizuj go. Lepiej przestawić kolejność teraz niż polecić wadliwy produkt.

## Etap F — Prezentacja wyników

**⛔ Bramka kompletności „fire-and-forget” (zanim pokażesz cokolwiek):** zrób **test pilnego kupującego** — *gdyby zdeterminowany kupujący spędził 10 minut na Pepper.pl, Amazon.pl i Ceneo, czy znalazłby coś wyraźnie lepszego, taniej albo lepiej ocenianego, czego w moim rankingu nie ma?* Jeśli masz choćby cień „tak” — **wróć** do longlisty / screeningu / researchu ceny i domknij lukę, **zanim** przedstawisz raport. Sensem tego skilla jest, żeby użytkownik **nie musiał** robić tego sam; jeśli zrobiłby to i znalazł coś lepszego, skill zawiódł. To obowiązkowa, wzmocniona wersja pytania z red-teamu o „przeoczoną lepszą alternatywę”.

Przedstaw wynik wg poniższego szablonu. Ranking **od najbardziej do najmniej polecanego**. Bądź konkretny, uczciwy co do wad, i zawsze podawaj ceny i źródła.

```markdown
# 🛒 Research zakupowy: [kategoria]

**Czego szukaliśmy:** [1–2 zdania skrótu specyfikacji: use-case, budżet, kluczowe kryteria]
**Przebadano:** [N] kandydatów → shortlista [M] → poniższy ranking. *(rynek PL, ceny na [data])*

## 🏆 Ranking

### 1. [Nazwa produktu] — [najlepsza realna cena + jak ją zdobyć: kanał/kod] ⭐ NAJLEPSZY WYBÓR
**Dla kogo:** [jednozdaniowy werdykt — dla kogo to najlepsza opcja]
**➕ Plusy:** [konkretne, wg kryteriów]
**➖ Minusy:** [uczciwie — każdy produkt jakieś ma]
**Kluczowe cechy:** [istotne dla kryteriów]
**Cena:** [najlepsza realna cena do zdobycia + kanał/kod] (widełki obserwowane: [...]) · **Ocena sklepowa:** [gwiazdki/liczba] · **Wynik ważony:** [...] · **Ukryte koszty:** [...] · **Gwarancja:** [...]
**Źródła:** [linki]

### 2. [Nazwa] — [cena] 🥈 [np. NAJLEPSZY STOSUNEK CENA/JAKOŚĆ]
[jak wyżej]

### 3. [Nazwa] — [cena]
[jak wyżej]

## 📊 Tabela porównawcza
| Kryterium (waga) | Produkt 1 | Produkt 2 | Produkt 3 |
|------------------|-----------|-----------|-----------|
| [kryterium] | [ocena/notka] | ... | ... |
| **Cena** | ... | ... | ... |
| **Wynik ważony** | ... | ... | ... |

## 🎯 Werdykt
**Dlaczego #1, a nie #2:** [konkretne uzasadnienie oparte na kryteriach użytkownika]
**Kiedy wybrać inaczej:**
- Jeśli [budżet niższy / zależy Ci głównie na X] → **[alternatywa]**
- Jeśli [inny scenariusz] → **[alternatywa]**

## ❌ Rozważeni, ale odrzuceni
- **[Produkt]** — [powód: poza budżetem / brak must-have / wycofany / słaba niezawodność]

## ⚠️ Do weryfikacji przed zakupem
- [Ryzyka, luki w danych, rzeczy do sprawdzenia — np. „potwierdź aktualną cenę, bywa promocja”, „sprawdź dostępność wariantu X”]

## ✅ Co sprawdziłem, żeby nic lepszego nie umknęło
- [Krótki dowód „fire-and-forget”: jakie kanały cenowe (Amazon/Allegro/Ceneo/producent), czy szukałem kodów/promocji/deali (Pepper), czy sprawdziłem oceny — żeby użytkownik wiedział, że nie znajdzie lepiej sam]

## 🔗 Źródła
[Lista kluczowych źródeł z datami]
```

---

## Zapis do vault (digital twin)

Po zaakceptowaniu specyfikacji **utwórz notatkę** w `./obsidian/Research/Zakupy/YYYY-MM-DD-<kategoria>.md` z zawartością specyfikacji, a po zakończeniu researchu **dopisz do niej finalny raport**. To buduje historię decyzji zakupowych i pozwala wracać do wcześniejszych analiz.

Jeśli w trakcie research ujawnił **trwałą preferencję** użytkownika (np. konsekwentnie wyklucza jakąś markę, priorytetyzuje ciszę/wagę, kupuje tylko z gwarancją door-to-door) — dopisz to do `./obsidian/Asystent/Memory/Preferences.md` lub `Personal.md`, zgodnie z filozofią digital twina z CLAUDE.md. Zapis do `Asystent/` jest autonomiczny.

## Zasady przewodnie (przypomnienie)

- **Uczciwość ponad entuzjazm.** Każdy produkt ma wady — jeśli ich nie widzisz, szukałeś za płytko. Nie sprzedajesz, doradzasz.
- **Zawsze ceny i źródła, zawsze aktualne — i aktywnie poluj na najlepszą realną cenę do zdobycia** (kody, kanały, deale), nie poprzestawaj na pierwszej/katalogowej. Cross-check w ≥2 źródłach, sygnalizuj promocje i wahania, oznacz dane, które mogą być nieaktualne. **Zanim wytniesz kandydata za budżet — sprawdź, czy nie kupisz go taniej (kod/kanał/deal).**
- **Szerokość przed oceną.** Longlista i równoległe analizy istnieją po to, żeby ranking nie był loterią pierwszych trafień. Nie skracaj lejka.
- **Luka blokująca → dopytaj (w Fazie 1).** Jeśli w trakcie budowy specyfikacji trafisz na coś, co zna tylko użytkownik i co realnie zmienia kierunek researchu — dopytaj, zanim ruszysz. W Fazie 2 działasz już autonomicznie wg zaakceptowanej specyfikacji.
```
