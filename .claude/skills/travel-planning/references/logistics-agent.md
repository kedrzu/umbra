# Kontrakt subagenta — Praktyczne / Logistyka

Ten plik to szablon briefu dla subagenta researchującego **praktyczną stronę wyjazdu**: wjazd/wiza, pogoda w terminie, transport (z lotniska i lokalny), bezpieczeństwo, pieniądze, łączność, zdrowie, budżet dzienny. Główny agent czyta plik, wstawia parametry ze specyfikacji i odpala subagenta na Sonnecie (`Agent`, `model: "sonnet"`, `subagent_type: "general-purpose"`), równolegle z resztą.

Sens: wyłapać rzeczy, które **wywracają wyjazd, jeśli się je przeoczy** (nieważny paszport, wiza, pora deszczowa, brak transportu z lotniska w nocy) i dać realny szacunek kosztów życia na miejscu.

---

## Szablon promptu dla subagenta

> To jest **zadanie badawcze**: research praktycznej strony podróży. Zwróć dossier jako **finalną odpowiedź**. Nie deleguj dalej.
>
> **Kraj/miasto docelowe:** [..] · **Termin:** [daty] · **Długość:** [N dni]
> **Podróżny:** obywatel/ka **Polski** (paszport RP), chyba że powiedziano inaczej · **Skład:** [dorośli, dzieci]
> **Kontekst:** [styl wyjazdu, czy z autem, skąd przylot]
>
> **Jak pracować:**
> - `WebSearch`/`WebFetch` (`ToolSearch` `select:WebSearch,WebFetch`) — oficjalne źródła gdy się da (gov.pl/MSZ, ambasady, IATA Travel, oficjalny transport miejski), plus przewodniki. **Limit ~8 wyszukiwań.** Nieustalone → „b.d.".
> - **Zakotwicz się w dacie wyjazdu** — pogoda, sezon i wymogi wjazdowe są zależne od terminu i się zmieniają; oznacz świeżość i wskaż, żeby użytkownik potwierdził wizę/wjazd u oficjalnego źródła przed wyjazdem.
>
> **Pokryj:**
> - **Wjazd/dokumenty dla obywatela PL:** wiza / ruch bezwizowy / ETA / ESTA / e-visa; **wymagana ważność paszportu** (często 3–6 mies. po powrocie); wiza tranzytowa na przesiadce; wymogi dla dzieci; ew. bilet powrotny/potwierdzenie noclegu na granicy.
> - **Pogoda/sezon w terminie:** typowe temperatury, opady, pora deszczowa/sucha, sezon huraganów, tłumy/święta lokalne; czy to dobra pora na ten typ wyjazdu.
> - **Zdrowie:** wymagane/zalecane szczepienia, malaria, woda z kranu, ubezpieczenie/EKUZ (UE), apteczka.
> - **Transport z lotniska:** jak dojechać do centrum (pociąg/metro/autobus/taxi/transfer), koszt, czas, dostępność w nocy.
> - **Transport lokalny:** komunikacja miejska (bilety/karty turystyczne — czy się opłacają), taxi/Uber/Bolt, wynajem auta (czy potrzebny, prawo jazdy/IDP, parkowanie, płatne drogi), ruch lewostronny jeśli dotyczy.
> - **Pieniądze:** waluta i **kurs do PLN**, czy karta wszędzie działa czy potrzeba gotówki, bankomaty/prowizje, napiwki (zwyczaj i wysokość).
> - **Łączność/prąd:** eSIM/SIM (koszt danych), typ gniazdka i napięcie (czy adapter), przydatne appki lokalne.
> - **Bezpieczeństwo:** ogólny poziom, typowe oszustwa/kieszonkowcy, rejony do unikania, numery alarmowe.
> - **Budżet dzienny:** orientacyjny koszt życia (posiłki tanie/średnie, kawa, bilet komunikacji, piwo/woda) — do zsumowania budżetu przez agenta głównego.
>
> **Zwróć dokładnie taką strukturę (Markdown):**
>
> ```markdown
> ## Praktyczne: [kraj/miasto]
>
> - **🛂 Wjazd/dokumenty (paszport PL):** [wiza/bezwizowo/ETA…]; **ważność paszportu:** [wymóg]; [tranzyt, dzieci]; ⚠️ potwierdź u oficjalnego źródła przed wyjazdem
> - **🌦️ Pogoda w terminie:** [temperatury, opady, sezon, tłumy]; [czy dobra pora]
> - **💉 Zdrowie:** [szczepienia/malaria/woda/ubezpieczenie]
> - **🚕 Z lotniska:** [opcje, koszt, czas, nocą]
> - **🚌 Transport lokalny:** [komunikacja/karty, taxi-app, auto: potrzebne?/IDP/parking]
> - **💳 Pieniądze:** [waluta, kurs do PLN, karta vs gotówka, napiwki]
> - **📶 Łączność / 🔌 prąd:** [eSIM, gniazdko/adapter]
> - **🛡️ Bezpieczeństwo:** [poziom, oszustwa, rejony, numery alarmowe]
> - **💰 Budżet dzienny (orient.):** [posiłki/transport/drobne — w walucie lokalnej i PLN]
>
> **⚠️ Rzeczy krytyczne do sprawdzenia przed wyjazdem:** [paszport, wiza, szczepienia — twarde blokery]
> **🔗 Źródła:** [linki z datą]
> **❓ Luki:** [czego nie udało się ustalić]
> ```
>
> Zwróć wyłącznie to dossier.

---

## Wskazówki dla agenta głównego przy składaniu briefu

- Podaj **narodowość, jeśli inna niż PL** (współtowarzysze mogą mieć inny paszport → inne wymogi wizowe).
- **Sekcja „krytyczne do sprawdzenia" i „budżet dzienny"** trafiają wprost do reality-checku i tabeli budżetu w planie.
- Framuj jako **zadanie badawcze**. **Obsłuż maruderów** (re-run lub sam).
- Wymogi wizowe/wjazdowe **zawsze** oznaczaj jako „potwierdź u oficjalnego źródła" — bywają zmieniane i nie bierzesz za nie odpowiedzialności.
