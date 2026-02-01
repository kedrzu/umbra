# Caracas - Przewodnik Instalacji

Krok po kroku jak skonfigurować osobistego asystenta AI z funkcją **Digital Twin**.

---

## Koncepcja: Digital Twin

Caracas to nie tylko manager zadań - to **cyfrowy bliźniak**, kompleksowy model Twojego życia.

### Czym jest Digital Twin?

Asystent aktywnie buduje pełny obraz Twojego życia zawodowego i osobistego:

- **Ludzie** - głębokie profile wszystkich kontaktów, relacje między nimi, historia komunikacji
- **Projekty** - wszystkie inicjatywy zawodowe i osobiste, z pełnym kontekstem i timeline'em
- **Praca** - kontekst zawodowy: firma, zespół, cele, wyzwania, kariera
- **Życie osobiste** - rodzina, zainteresowania, wartości, cele życiowe
- **Wzorce** - jak pracujesz, komunikujesz się, podejmujesz decyzje
- **Spostrzeżenia** - połączone kropki, zauważone zależności
- **Historia** - ważne daty, kamienie milowe, timeline życia

### Jak to działa?

Asystent **aktywnie wyciąga informacje** z każdej interakcji:

1. Gdy przeglądasz email - uczy się o ludziach i projektach
2. Gdy sprawdzasz kalendarz - buduje mapę relacji i wzorców
3. Gdy omawiasz zadania - aktualizuje status projektów

**To nie jest pasywne notatki** - asystent proaktywnie łączy informacje i buduje coraz głębsze zrozumienie Twojego świata.

### Po co?

Dzięki Digital Twin asystent może:

- Przypomnieć Ci o urodzinach kolegi wspomnianego w emailu
- Zauważyć że projekt wymaga uwagi bo deadline się zbliża
- Połączyć emaila od osoby A z projektem prowadzonym przez osobę B
- Zaproponować fokus na podstawie Twoich wzorców produktywności
- Być prawdziwie pomocnym partnerem, nie tylko narzędziem

---

## Wymagania wstępne

### Zainstaluj Node.js

```bash
brew install node
```

Sprawdź wersję (wymagana 18+):
```bash
node --version
```

### Zainstaluj Claude Code

```bash
npm install -g @anthropic-ai/claude-code
```

### (Opcjonalnie) Zainstaluj qmd dla szybkiego wyszukiwania

```bash
brew install bun
bun install -g github:tobi/qmd
```

---

## Krok 1: Zbuduj serwer Obsidian

Serwer MCP dla Obsidian zapewnia bezpieczny dostęp do vault'a z separacją uprawnień.

```bash
cd /Users/kedrzu/conductor/workspaces/umbra/caracas/mcp-servers/obsidian-vault
npm install
npm run build
```

Sprawdź czy się zbudowało:
```bash
ls dist/index.js
```

---

## Krok 2: Skonfiguruj qmd (opcjonalne)

qmd zapewnia błyskawiczne wyszukiwanie w vault'cie (BM25 + semantic search).

### Dodaj vault jako kolekcję

```bash
qmd collection add "/Users/kedrzu/Library/Mobile Documents/iCloud~md~obsidian/Documents/kedrzu" --name obsidian
```

### Wygeneruj embeddingi

```bash
qmd embed
```

> To może potrwać kilka minut przy dużym vault'cie.

### Przetestuj

```bash
qmd search "test" --collection obsidian
```

---

## Krok 3: Skonfiguruj Gmail

### Utwórz projekt Google Cloud

1. Wejdź na [Google Cloud Console](https://console.cloud.google.com/)
2. Utwórz nowy projekt: **"Caracas Assistant"**
3. Przejdź do **APIs & Services → Library**
4. Wyszukaj **Gmail API** i włącz

### Skonfiguruj OAuth

1. **APIs & Services → Credentials**
2. **Create Credentials → OAuth 2.0 Client ID**
3. Typ aplikacji: **Desktop app**
4. Nazwa: **"Caracas"**
5. Pobierz JSON

### Zapisz credentials

```bash
mkdir -p ~/.config/caracas
mv ~/Downloads/client_secret_*.json ~/.config/caracas/gmail-credentials.json
```

### Skonfiguruj OAuth Consent Screen

1. **APIs & Services → OAuth consent screen**
2. Dodaj scopes:
   - `gmail.readonly` - czytanie maili
   - `gmail.compose` - tworzenie szkiców
   - `gmail.labels` - zarządzanie etykietami

> **WAŻNE**: NIE dodawaj `gmail.send` - to celowe ograniczenie bezpieczeństwa.

### Zainstaluj Gmail MCP server

Użyj [PaulFidika/gmail-mcp-server](https://github.com/PaulFidika/gmail-mcp-server) lub innego kompatybilnego:

```bash
cd ~/Projects
git clone https://github.com/PaulFidika/gmail-mcp-server.git
cd gmail-mcp-server
npm install
npm run build
```

### Zaktualizuj .mcp.json

Zmień ścieżkę w `.mcp.json`:

```json
"gmail": {
  "command": "node",
  "args": ["/Users/kedrzu/Projects/gmail-mcp-server/dist/index.js"],
  "env": {
    "GMAIL_CREDENTIALS_PATH": "${HOME}/.config/caracas/gmail-credentials.json",
    "GMAIL_TOKENS_PATH": "${HOME}/.config/caracas/gmail-tokens.json"
  }
}
```

---

## Krok 4: Skonfiguruj Google Calendar

Kalendarz używa `@nspady/google-calendar-mcp` który jest już skonfigurowany w `.mcp.json`.

### Pierwsza autoryzacja

Przy pierwszym użyciu kalendarza w Claude Code:

1. Serwer otworzy przeglądarkę
2. Zaloguj się na konto Google
3. Zezwól na dostęp
4. Powtórz dla każdego konta (personal, work)

### Dodawanie kolejnych kont

W Claude Code powiedz:
```
Dodaj moje drugie konto Google do kalendarza
```

Asystent użyje `manage-accounts` aby dodać kolejne konto.

---

## Krok 5: Skonfiguruj Todoist

Todoist używa oficjalnego hostowanego endpointu - nie wymaga lokalnej konfiguracji.

### Pierwsza autoryzacja

Przy pierwszym użyciu Todoist w Claude Code:

1. Pojawi się link do autoryzacji
2. Otwórz link w przeglądarce
3. Zaloguj się do Todoist
4. Zezwól na dostęp

Gotowe - tokeny zostaną zapisane automatycznie.

---

## Krok 6: Uruchom i przetestuj

### Uruchom Claude Code

```bash
cd /Users/kedrzu/conductor/workspaces/umbra/caracas
claude
```

### Testy podstawowe

| Co przetestować | Komenda | Oczekiwany wynik |
|-----------------|---------|------------------|
| Obsidian - odczyt | `Przeczytaj AI/Memory/People.md` | Zawartość pliku |
| Obsidian - zapis | `Zapisz notatkę testową w AI/Drafts/test.md` | Sukces |
| Kalendarz | `Pokaż moje dzisiejsze wydarzenia` | Lista wydarzeń |
| Todoist | `Pokaż moje zadania` | Lista zadań |
| Gmail | `Ile mam nieprzeczytanych maili?` | Liczba maili |

### Test zabezpieczeń

| Co przetestować | Komenda | Oczekiwany wynik |
|-----------------|---------|------------------|
| Blokada wysyłania | `Wyślij maila do X` | Odmowa |
| Blokada usuwania | `Usuń to zadanie` | Odmowa |
| Blokada modyfikacji | `Zmień nazwę wydarzenia` | Odmowa |

### Test skilli

```
/daily-dashboard
```

Powinno wygenerować `Inbox/Dashboard-YYYY-MM-DD.md`.

---

## Struktura plików

Po instalacji masz:

```
caracas/
├── CLAUDE.md                 # Instrukcje asystenta
├── .mcp.json                 # Konfiguracja serwerów MCP
├── .claude/
│   ├── settings.json         # Reguły uprawnień
│   └── skills/               # Skille
│       ├── inbox-review/
│       ├── email-analysis/
│       ├── unsubscribe-review/
│       ├── daily-dashboard/
│       ├── daily-planning/
│       ├── weekly-review/
│       ├── research/
│       ├── memory-update/
│       └── do-your-job/
├── mcp-servers/
│   └── obsidian-vault/       # Własny serwer MCP
└── scripts/
    └── setup.sh
```

Vault Obsidian:

```
kedrzu/
├── AI/                       # Folder asystenta (pełny dostęp)
│   ├── Memory/               # DIGITAL TWIN - model Twojego życia
│   │   ├── People.md         # INDEKS ludzi (linki do szczegółów)
│   │   ├── People/           # Szczegółowe profile osób
│   │   │   ├── _TEMPLATE.md  # Szablon dla nowych osób
│   │   │   └── Jan-Kowalski.md
│   │   ├── Projects.md       # INDEKS projektów (linki do szczegółów)
│   │   ├── Projects/         # Szczegółowe profile projektów
│   │   │   ├── _TEMPLATE.md  # Szablon dla nowych projektów
│   │   │   └── Project-Alpha.md
│   │   ├── Work.md           # Kontekst zawodowy
│   │   ├── Personal.md       # Kontekst osobisty
│   │   ├── Preferences.md    # Wzorce zachowań i preferencje
│   │   ├── Insights.md       # Spostrzeżenia i połączone kropki
│   │   └── Timeline.md       # Ważne daty i kamienie milowe
│   ├── Drafts/
│   ├── Research/
│   └── SessionLogs/
├── Inbox/                    # Twoje notatki (append-only dla AI)
├── Projekty/
├── Obszary/
├── Zasoby/
└── Archiwum/                 # (read-only dla AI)
```

**Dlaczego indeks + osobne pliki?**

Ludzie i projekty mogą rosnąć do setek wpisów. Struktura indeks + szczegóły:
- Pozwala szybko przeskanować listę
- Umożliwia głębokie profile bez zaśmiecania
- Lepiej działa z wyszukiwaniem Obsidian
- Ułatwia cross-referencje między plikami

---

## Dostępne skille

| Skill | Co robi |
|-------|---------|
| `/inbox-review` | Przegląd skrzynki email |
| `/email-analysis` | Analiza wzorców i projektowanie workflow |
| `/unsubscribe-review` | Czyszczenie subskrypcji |
| `/daily-dashboard` | Generuje dashboard dnia w Obsidian |
| `/daily-planning` | Poranne planowanie |
| `/weekly-review` | Tygodniowy przegląd |
| `/research [temat]` | Szukanie w vault'cie |
| `/memory-update [info]` | Zapisz do pamięci |
| `/do-your-job` | Pełna rutyna asystenta |

---

## Rozwiązywanie problemów

### "MCP server nie startuje"

```bash
# Sprawdź logi
claude --mcp-debug

# Przebuduj serwer
cd mcp-servers/obsidian-vault && npm run build
```

### "qmd nie działa"

```bash
# Sprawdź status
qmd status

# Przebuduj indeks
qmd embed --force
```

### "OAuth nie działa"

```bash
# Usuń tokeny i zacznij od nowa
rm ~/.config/caracas/*-tokens.json
```

### "Brak dostępu do kalendarza/Todoist"

Przy pierwszym użyciu musisz przejść autoryzację w przeglądarce. Claude Code pokaże link.

---

## Bezpieczeństwo

### Co asystent MOŻE robić

- Czytać maile, kalendarz, zadania
- Tworzyć szkice maili (bez wysyłania)
- Tworzyć nowe zadania i wydarzenia
- Pisać do folderu `AI/` w Obsidian
- Dopisywać do twoich notatek (append-only)

### Czego asystent NIE MOŻE robić

- Wysyłać maili
- Usuwać czegokolwiek
- Modyfikować istniejących zadań/wydarzeń
- Nadpisywać twoich notatek
- Czytać plików poza vault'em

### Warstwy zabezpieczeń

1. **OAuth scopes** - Gmail nie ma uprawnienia do wysyłania
2. **MCP tool filtering** - Kalendarz ma whitelist dozwolonych narzędzi
3. **Claude Code permissions** - `settings.json` blokuje niebezpieczne operacje
4. **CLAUDE.md** - Instrukcje behawioralne

---

## Aktualizacje

### Aktualizacja qmd

```bash
# Odśwież indeks (zalecane codziennie)
qmd embed
```

### Aktualizacja serwera Obsidian

```bash
cd mcp-servers/obsidian-vault
npm run build
```

---

*Gotowe! Uruchom `claude` w katalogu projektu i zacznij korzystać z asystenta.*
