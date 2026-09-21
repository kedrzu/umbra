#!/usr/bin/env python3
"""Publish - publikowanie dokumentow (HTML / Markdown / folderow) na Cloudflare Pages.

Jeden projekt Pages = jedna subdomena = wiele NIEZALEZNYCH podfolderow:
kazdy dokument dostaje wlasny slug i zyje pod <BASE_URL>/<slug>/. Zrodlem prawdy
jest lokalne lustro (`published/`), bo Pages deployuje caly katalog naraz -
wrangler liczy hashe i wysyla tylko brakujace pliki, wiec dorzucenie jednego
dokumentu nie rusza pozostalych.

Adres wybiera wywolujacy (--slug). Serwis ma noindex i robots.txt, a strona glowna
NIE listuje dokumentow - ale to nie jest autoryzacja: kto ma link, ten wejdzie.
Tresc, ktora nie powinna byc do zgadniecia, dostaje slug z dolosowanym sufiksem
(to decyzja o tresci, nie mechanika skryptu); zwykly dokument moze miec czytelny
adres, ktory da sie podac przez telefon.

Jak `ledger.py` i `todoist.py`: NIE MA podkomendy `delete`. `unpublish` przenosi
dokument do `published/.trash/`, wiec tresc zostaje na dysku.

    publish.py add ./dokumentacja/ --slug garderoba        # czytelny adres /garderoba/
    publish.py add ./wyniki.md --slug wyniki-7f3a91c4      # nieodgadywalny (sufiks dolosowany
                                                           # przez WYWOLUJACEGO, nie skrypt)
    publish.py add ./apka/ --spa                           # folder, routing po stronie klienta
    publish.py find garderoba                              # czy to juz wisi i pod czym
    publish.py list
    publish.py update garderoba                            # odswiez z zapamietanego zrodla
    publish.py unpublish garderoba
    publish.py deploy                                      # redeploy calego lustra
"""

from __future__ import annotations

import argparse
import datetime as dt
import fnmatch
import html
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = REPO_ROOT / "scripts" / "publish.env"
VAULT_ROOT = REPO_ROOT / "obsidian"


class PublishError(Exception):
    pass


# --------------------------------------------------------------------------
# Konfiguracja

def load_config() -> dict[str, str]:
    """Czyta scripts/publish.env (proste KEY="value"), bez odpalania shella."""
    cfg: dict[str, str] = {}
    if not ENV_FILE.is_file():
        raise PublishError(f"Brak {ENV_FILE}. Odpal ./setup-publishing.sh")
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        cfg[key.strip()] = value.strip().strip('"').strip("'")
    return cfg


def load_credentials() -> tuple[str, str]:
    """Token i account id: najpierw srodowisko, potem .env repo."""
    token = os.environ.get("CLOUDFLARE_API_TOKEN", "").strip()
    account = os.environ.get("CLOUDFLARE_ACCOUNT_ID", "").strip()
    env_path = REPO_ROOT / ".env"
    if env_path.is_file() and (not token or not account):
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if "=" not in line or line.startswith("#"):
                continue
            key, value = line.split("=", 1)
            value = value.strip().strip('"').strip("'")
            if key.strip() == "CLOUDFLARE_API_TOKEN" and not token:
                token = value
            elif key.strip() == "CLOUDFLARE_ACCOUNT_ID" and not account:
                account = value
    if not token or not account:
        raise PublishError(
            "Brak CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID w .env.\n"
            "Wyklikaj token (dash.cloudflare.com -> My Profile -> API Tokens -> Custom,\n"
            "uprawnienie Account -> Cloudflare Pages -> Edit) i odpal ./setup-publishing.sh"
        )
    return token, account


CFG = load_config()
# STATE_ROOT trzyma manifest i kosz, SITE_ROOT to JEDYNY katalog wysylany na Pages.
# Rozdzial jest istotny: manifest to lista wszystkich slugow, a cala ochrona opiera
# sie na tym, ze slugow nie da sie poznac. Kosz z tego samego powodu nie moze tam byc.
STATE_ROOT = REPO_ROOT / CFG.get("STATE_DIR", "published")
SITE_ROOT = STATE_ROOT / "site"
MANIFEST_PATH = STATE_ROOT / "manifest.json"
BASE_URL = CFG.get("BASE_URL", "").rstrip("/")


# --------------------------------------------------------------------------
# Manifest

def load_manifest() -> dict[str, Any]:
    if not MANIFEST_PATH.is_file():
        return {"documents": []}
    data = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    data.setdefault("documents", [])
    return data


def save_manifest(data: dict[str, Any]) -> None:
    STATE_ROOT.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def find_doc(manifest: dict[str, Any], slug: str) -> dict[str, Any] | None:
    for doc in manifest["documents"]:
        if doc["slug"] == slug:
            return doc
    return None


def now() -> str:
    return dt.datetime.now().isoformat(timespec="seconds")


def find_by_source(manifest: dict[str, Any], source: Path) -> dict[str, Any] | None:
    """Czy ten sam material juz gdzies wisi? Porownujemy sciezke rzeczywista,
    zeby dowiazania symboliczne (vault!) nie robily z jednego zrodla dwoch."""
    target = os.path.realpath(source)
    for doc in manifest["documents"]:
        if os.path.realpath(doc.get("source", "")) == target:
            return doc
    return None


def adopt_from_marker(manifest: dict[str, Any], source: Path) -> dict[str, Any] | None:
    """Manifest przepadl, ale marker przy zrodle pamieta slug - odtwarzamy wpis,
    zeby publikacja wrocila pod stary adres zamiast dostac nowy."""
    key = marker_key(source)
    for entry in read_marker(source).get("published", []):
        if entry.get("source") != key or entry.get("unpublished") or not entry.get("slug"):
            continue
        doc = {
            "slug": entry["slug"],
            "title": entry.get("title") or source.name,
            "kind": "folder" if source.is_dir() else "html",
            "spa": entry.get("spa", False),
            "ignore": entry.get("ignore", []),
            "source": str(source),
            "created": entry.get("created", now()),
            "updated": now(),
            "url": f"{BASE_URL}/{entry['slug']}/",
        }
        manifest["documents"].append(doc)
        return doc
    return None


# --------------------------------------------------------------------------
# Slug

PL_CHARS = {
    "ą": "a", "ć": "c", "ę": "e", "ł": "l", "ń": "n",
    "ó": "o", "ś": "s", "ź": "z", "ż": "z",
    "Ą": "A", "Ć": "C", "Ę": "E", "Ł": "L", "Ń": "N",
    "Ó": "O", "Ś": "S", "Ź": "Z", "Ż": "Z",
}


def slugify(text: str, limit: int = 40) -> str:
    for src, dst in PL_CHARS.items():
        text = text.replace(src, dst)
    text = re.sub(r"[^A-Za-z0-9]+", "-", text).strip("-").lower()
    text = re.sub(r"-{2,}", "-", text)[:limit].strip("-")
    return text or "dokument"


def make_slug(base: str, manifest: dict[str, Any]) -> str:
    """Slug jest DECYZJA WYWOLUJACEGO, nie polityka skryptu.

    Czytelny adres (`/garderoba/`) jest lepszy wszedzie tam, gdzie ktos go przepisze
    z kartki albo poda przez telefon. Nieodgadywalny (`/wyniki-7f3a91c4/`) ma sens
    tam, gdzie tresc nie powinna byc do zgadniecia - ale to ocena tresci, ktorej
    skrypt nie zrobi za Ciebie. Chcesz losowy? Dolosuj go sam i podaj w --slug;
    manifest i marker przy zrodle go zapamietaja.
    """
    slug = slugify(base)
    taken = find_doc(manifest, slug)
    if taken:
        raise PublishError(
            f"Slug '{slug}' jest juz zajety przez: {taken['title']} "
            f"(zrodlo: {taken.get('source', '?')}).\n"
            "Podaj inny --slug albo zaktualizuj tamta publikacje "
            f"(publish.py update {slug} <sciezka>)."
        )
    if (SITE_ROOT / slug).exists():
        raise PublishError(f"Katalog '{slug}' juz istnieje w lustrze - wybierz inny slug.")
    return slug


# Smieci warsztatowe, ktore nikogo po drugiej stronie linku nie interesuja,
# a potrafia wazyc wiecej niz sam dokument.
DEFAULT_IGNORES = ["__pycache__", "*.pyc", "*.pyo", "node_modules", ".git", ".venv",
                   "*.egg-info", ".DS_Store", ".publish.json"]

MARKER_NAME = ".publish.json"


def is_ignored(name: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(name, pat) for pat in patterns)


# --------------------------------------------------------------------------
# Marker w zrodle - pamiec sluga PRZY projekcie
#
# Manifest wie, co jest opublikowane, ale zyje w tym repo. Marker `.publish.json`
# lezy przy samym dokumencie, wiec jedzie razem z projektem i przezywa utrate lustra.
# Dzieki niemu kolejna publikacja tego samego materialu trafia pod TEN SAM adres -
# link, ktory ktos juz dostal, nie umiera przy aktualizacji.

def marker_dir(source: Path) -> Path:
    return source if source.is_dir() else source.parent


def marker_key(source: Path) -> str:
    return "." if source.is_dir() else source.name


def read_marker(source: Path) -> dict[str, Any]:
    path = marker_dir(source) / MARKER_NAME
    if not path.is_file():
        return {"published": []}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except ValueError:
        return {"published": []}
    data.setdefault("published", [])
    return data


def write_marker(source: Path, doc: dict[str, Any], removed: bool = False) -> None:
    path = marker_dir(source) / MARKER_NAME
    data = read_marker(source)
    key = marker_key(source)
    entry = next((e for e in data["published"] if e.get("source") == key), None)
    if entry is None:
        entry = {"source": key, "created": doc["created"]}
        data["published"].append(entry)
    entry.update({
        "slug": doc["slug"],
        "title": doc["title"],
        "url": doc["url"],
        "spa": doc.get("spa", False),
        "ignore": doc.get("ignore", []),
        "updated": doc["updated"],
    })
    entry["unpublished"] = doc.get("unpublished")
    header = ("Publikacja tego materialu - zapisane przez scripts/publish.py w repo umbra.\n"
              "Dzieki temu plikowi kolejna publikacja trafia pod TEN SAM adres.")
    data["_info"] = header
    try:
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except OSError as exc:
        # Cicha porazka bylaby najgorsza: manifest pamieta slug tylko dopoki zyje
        # lustro, a marker jest kopia, ktora jedzie z projektem. Jesli go nie ma,
        # wywolujacy musi o tym wiedziec i dopisac go innym narzedziem.
        print(f"uwaga: nie zapisano {path} ({exc.strerror}) - slug '{doc['slug']}' "
              f"pamieta tylko manifest", file=sys.stderr)


# --------------------------------------------------------------------------
# Markdown -> HTML

def _md_renderer():
    """markdown-it-py + pygments. Gdy ich nie ma, wchodzimy przez `uv run --with`."""
    try:
        from markdown_it import MarkdownIt
    except ImportError:
        if os.environ.get("PUBLISH_UV_REEXEC"):
            raise PublishError(
                "Brak markdown-it-py. Zainstaluj uv (brew install uv) albo:\n"
                "  pip install markdown-it-py pygments"
            )
        env = dict(os.environ, PUBLISH_UV_REEXEC="1")
        env.setdefault("UV_CACHE_DIR", os.environ.get("TMPDIR", "/tmp") + "/uv-cache")
        uv = shutil.which("uv")
        if not uv:
            raise PublishError(
                "Brak markdown-it-py i brak uv. `brew install uv` albo "
                "`pip install markdown-it-py pygments`"
            )
        os.execve(uv, [uv, "run", "--quiet", "--with", "markdown-it-py", "--with",
                       "pygments", "python3", str(Path(__file__).resolve()),
                       *sys.argv[1:]], env)

    def highlight(code: str, lang: str, _attrs: str) -> str:
        try:
            from pygments import highlight as pyg_highlight
            from pygments.formatters import HtmlFormatter
            from pygments.lexers import get_lexer_by_name, guess_lexer
        except ImportError:
            return ""
        try:
            lexer = get_lexer_by_name(lang) if lang else guess_lexer(code)
        except Exception:
            return ""
        return pyg_highlight(code, lexer, HtmlFormatter(nowrap=True))

    md = MarkdownIt("commonmark", {"html": True, "linkify": False, "highlight": highlight})
    md.enable(["table", "strikethrough"])
    return md


FRONT_MATTER = re.compile(r"\A---\r?\n(.*?)\r?\n---\r?\n", re.DOTALL)
WIKILINK = re.compile(r"(?<!\!)\[\[([^\]\|]+)(?:\|([^\]]+))?\]\]")
EMBED = re.compile(r"!\[\[([^\]\|]+)(?:\|([^\]]+))?\]\]")


def strip_front_matter(text: str) -> tuple[str, dict[str, str]]:
    meta: dict[str, str] = {}
    match = FRONT_MATTER.match(text)
    if not match:
        return text, meta
    for line in match.group(1).splitlines():
        if ":" in line and not line.startswith((" ", "-", "\t")):
            key, value = line.split(":", 1)
            meta[key.strip()] = value.strip().strip('"').strip("'")
    return text[match.end():], meta


def resolve_asset(name: str, source_dir: Path) -> Path | None:
    """Szuka pliku obok dokumentu, potem po nazwie w vaulcie (embed obsidianowy)."""
    candidate = (source_dir / name).resolve()
    if candidate.is_file():
        return candidate
    if VAULT_ROOT.exists():
        matches = sorted(VAULT_ROOT.rglob(Path(name).name))
        for match in matches:
            if match.is_file():
                return match
    return None


def preprocess_obsidian(text: str, source_dir: Path, target_dir: Path) -> str:
    """Wikilinki -> czysty tekst (prowadza donikad), embedy -> skopiowany obrazek."""

    def on_embed(match: re.Match) -> str:
        name = match.group(1).strip()
        alt = (match.group(2) or Path(name).stem).strip()
        asset = resolve_asset(name, source_dir)
        if not asset:
            return f"*(brak zalacznika: {name})*"
        dest_name = slugify(asset.stem) + asset.suffix.lower()
        shutil.copy2(asset, target_dir / dest_name)
        return f"![{alt}]({dest_name})"

    def on_link(match: re.Match) -> str:
        return (match.group(2) or match.group(1)).strip()

    return WIKILINK.sub(on_link, EMBED.sub(on_embed, text))


REL_REF = re.compile(r'(src|href)="([^"]+)"')


def copy_local_assets(html_text: str, source_dir: Path, target_dir: Path) -> None:
    """Dociaga pliki, do ktorych dokument sie odwoluje wzglednie (obrazki, css)."""
    for _attr, ref in REL_REF.findall(html_text):
        if re.match(r"^(https?:|mailto:|tel:|data:|#|/)", ref):
            continue
        ref_path = ref.split("#", 1)[0].split("?", 1)[0]
        if not ref_path:
            continue
        src = (source_dir / ref_path).resolve()
        if not src.is_file():
            continue
        dest = (target_dir / ref_path).resolve()
        if not dest.is_relative_to(target_dir.resolve()):
            continue  # ../ w dokumencie nie moze pisac poza jego folder
        dest.parent.mkdir(parents=True, exist_ok=True)
        if not dest.exists():
            shutil.copy2(src, dest)


PAGE_CSS = """
:root { color-scheme: light dark; --fg:#1b1b1f; --bg:#fff; --muted:#5b616e;
        --line:#e3e5ea; --accent:#2b5fd9; --code-bg:#f5f6f8; }
@media (prefers-color-scheme: dark) {
  :root { --fg:#e6e7ea; --bg:#16171a; --muted:#9aa0ac; --line:#2c2e33;
          --accent:#7aa2f7; --code-bg:#1e2025; }
}
* { box-sizing: border-box; }
body { margin:0; padding:3rem 1.25rem 6rem; background:var(--bg); color:var(--fg);
       font:17px/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
       -webkit-text-size-adjust:100%; }
main { max-width:44rem; margin:0 auto; }
h1,h2,h3,h4 { line-height:1.25; margin:2.2em 0 .6em; font-weight:650; }
h1 { font-size:2rem; margin-top:0; }
h2 { font-size:1.45rem; padding-bottom:.25em; border-bottom:1px solid var(--line); }
h3 { font-size:1.15rem; }
p, ul, ol, blockquote, table, pre { margin:0 0 1.1em; }
a { color:var(--accent); text-underline-offset:2px; }
ul, ol { padding-left:1.4em; }
li + li { margin-top:.3em; }
blockquote { margin-left:0; padding:.2em 0 .2em 1em; border-left:3px solid var(--line);
             color:var(--muted); }
code { font:0.88em/1.5 ui-monospace, SFMono-Regular, Menlo, monospace;
       background:var(--code-bg); padding:.15em .35em; border-radius:4px; }
pre { background:var(--code-bg); padding:1em; border-radius:8px; overflow-x:auto; }
pre code { background:none; padding:0; }
table { border-collapse:collapse; width:100%; font-size:.95em; display:block; overflow-x:auto; }
th, td { border:1px solid var(--line); padding:.5em .7em; text-align:left; }
th { background:var(--code-bg); font-weight:600; }
img { max-width:100%; height:auto; border-radius:6px; }
hr { border:0; border-top:1px solid var(--line); margin:2.5em 0; }
footer { max-width:44rem; margin:4rem auto 0; padding-top:1.2em; border-top:1px solid var(--line);
         color:var(--muted); font-size:.85em; }
pre .k, pre .kd, pre .kn, pre .ow { color:#a626a4; font-weight:600; }
pre .s, pre .s1, pre .s2, pre .sb, pre .sd, pre .se { color:#50a14f; }
pre .c, pre .c1, pre .cm, pre .cs { color:var(--muted); font-style:italic; }
pre .n, pre .nb, pre .nc, pre .nf, pre .nn { color:#4078f2; }
pre .m, pre .mi, pre .mf { color:#986801; }
@media (prefers-color-scheme: dark) {
  pre .k, pre .kd, pre .kn, pre .ow { color:#c678dd; }
  pre .s, pre .s1, pre .s2, pre .sb, pre .sd, pre .se { color:#98c379; }
  pre .n, pre .nb, pre .nc, pre .nf, pre .nn { color:#61afef; }
  pre .m, pre .mi, pre .mf { color:#d19a66; }
}
"""


def wrap_html(title: str, body: str, generated: str) -> str:
    return f"""<!doctype html>
<html lang="pl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow, noarchive">
<title>{html.escape(title)}</title>
<style>{PAGE_CSS}</style>
</head>
<body>
<main>
{body}
</main>
<footer>{html.escape(title)} &middot; {generated}</footer>
</body>
</html>
"""


def render_markdown(source: Path, target_dir: Path,
                    title_override: str | None) -> tuple[str, str]:
    md = _md_renderer()
    raw = source.read_text(encoding="utf-8")
    text, meta = strip_front_matter(raw)
    text = preprocess_obsidian(text, source.parent, target_dir)
    body = md.render(text)

    title = title_override or meta.get("title") or meta.get("tytul") or ""
    if not title:
        heading = re.search(r"^#\s+(.+)$", text, re.MULTILINE)
        title = heading.group(1).strip() if heading else source.stem
    copy_local_assets(body, source.parent, target_dir)
    return wrap_html(title, body, dt.date.today().isoformat()), title


# --------------------------------------------------------------------------
# Budowanie dokumentu

def needs_markdown(source: Path) -> bool:
    if source.is_dir():
        return any(source.rglob("*.md")) or any(source.rglob("*.markdown"))
    return source.suffix.lower() in (".md", ".markdown")


def build_document(source: Path, target_dir: Path, title_override: str | None,
                   ignores: list[str] | None = None) -> tuple[str, str]:
    """Zwraca (kind, title). Tworzy target_dir z gotowa trescia."""
    ignores = DEFAULT_IGNORES + list(ignores or [])
    target_dir.mkdir(parents=True, exist_ok=False)

    if source.is_dir():
        def copy_tree(src: Path, dst: Path) -> None:
            dst.mkdir(parents=True, exist_ok=True)
            for item in sorted(src.iterdir()):
                if item.name.startswith(".") or is_ignored(item.name, ignores):
                    continue
                if item.is_dir():
                    copy_tree(item, dst / item.name)
                else:
                    shutil.copy2(item, dst / item.name)

        copy_tree(source, target_dir)
        # .md w folderze renderujemy obok oryginalu, zeby dalo sie w nie kliknac
        for md_file in sorted(target_dir.rglob("*.md")):
            rendered, _ = render_markdown(md_file, md_file.parent, None)
            md_file.with_suffix(".html").write_text(rendered, encoding="utf-8")
        if not (target_dir / "index.html").is_file():
            for fallback in ("index.md", "README.md", "readme.md"):
                candidate = target_dir / fallback
                if candidate.with_suffix(".html").is_file():
                    shutil.copy2(candidate.with_suffix(".html"), target_dir / "index.html")
                    break
        if not (target_dir / "index.html").is_file():
            shutil.rmtree(target_dir)
            raise PublishError(
                f"Folder {source} nie ma index.html ani index.md/README.md - "
                "Pages nie wiedzialoby, co pokazac pod adresem dokumentu."
            )
        title = title_override or source.name
        return "folder", title

    suffix = source.suffix.lower()
    if suffix in (".md", ".markdown"):
        rendered, title = render_markdown(source, target_dir, title_override)
        (target_dir / "index.html").write_text(rendered, encoding="utf-8")
        return "markdown", title
    if suffix in (".html", ".htm"):
        shutil.copy2(source, target_dir / "index.html")
        text = source.read_text(encoding="utf-8", errors="replace")
        copy_local_assets(text, source.parent, target_dir)
        match = re.search(r"<title[^>]*>(.*?)</title>", text, re.IGNORECASE | re.DOTALL)
        title = title_override or (match.group(1).strip() if match else source.stem)
        return "html", title

    raise PublishError(
        f"Nieobslugiwany typ: {source.name}. Przyjmuje .md, .html albo folder z index.html"
    )


def regenerate_redirects(manifest: dict[str, Any]) -> None:
    """SPA-owe slugi dostaja fallback; reszta serwisu bez zmian."""
    lines = [
        "# Generowane przez scripts/publish.py - nie edytuj recznie.",
        "# Fallback tylko dla dokumentow dodanych z --spa (routing po stronie klienta).",
    ]
    for doc in manifest["documents"]:
        if doc.get("spa"):
            lines.append(f"/{doc['slug']}/* /{doc['slug']}/index.html 200")
    (SITE_ROOT / "_redirects").write_text("\n".join(lines) + "\n", encoding="utf-8")


# --------------------------------------------------------------------------
# Deploy

def production_branch(token: str, account: str) -> str:
    """Galaz produkcyjna projektu - MUSI sie zgadzac, inaczej deploy ladu je jako
    *preview* pod losowym adresem <hash>.<projekt>.pages.dev, a produkcyjny URL
    zostaje stary. Projekt zalozony recznie w dashboardzie bywa ustawiony na inna
    galaz niz `main`, wiec nie zgadujemy - pytamy API."""
    url = (f"https://api.cloudflare.com/client/v4/accounts/{account}"
           f"/pages/projects/{CFG['PAGES_PROJECT']}")
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            raise PublishError(
                f"Projekt Pages '{CFG['PAGES_PROJECT']}' nie istnieje na tym koncie.\n"
                "Zaloz go (./setup-publishing.sh albo recznie w dashboardzie) lub popraw\n"
                "PAGES_PROJECT w scripts/publish.env."
            ) from None
        raise PublishError(f"API Cloudflare: HTTP {exc.code} {exc.reason}") from None
    except urllib.error.URLError as exc:
        raise PublishError(f"Brak polaczenia z API Cloudflare: {exc.reason}") from None
    return (data.get("result") or {}).get("production_branch") or "main"


def deploy(quiet: bool = False) -> str:
    token, account = load_credentials()
    if not SITE_ROOT.is_dir():
        raise PublishError(f"Brak lustra {SITE_ROOT}. Odpal ./setup-publishing.sh")
    branch = production_branch(token, account)
    cmd = [
        "npx", "--yes", f"wrangler@{CFG.get('WRANGLER_VERSION', '4')}",
        "pages", "deploy", str(SITE_ROOT),
        "--project-name", CFG["PAGES_PROJECT"],
        "--branch", branch,
        "--commit-dirty=true",
    ]
    env = dict(os.environ, CLOUDFLARE_API_TOKEN=token, CLOUDFLARE_ACCOUNT_ID=account)
    proc = subprocess.run(cmd, env=env, capture_output=True, text=True)
    output = (proc.stdout or "") + (proc.stderr or "")
    if proc.returncode != 0:
        raise PublishError(f"Deploy nie powiodl sie:\n{output.strip()[-2000:]}")
    if not quiet:
        for line in output.splitlines():
            if "pages.dev" in line or "Uploading" in line or "files already" in line:
                print("  " + line.strip())
    return output


# --------------------------------------------------------------------------
# Podkomendy

def write_document(source: Path, slug: str, args: argparse.Namespace,
                   manifest: dict[str, Any], existing: dict[str, Any] | None) -> dict[str, Any]:
    """Buduje tresc pod danym slugiem. Poprzednia wersja (jesli byla) ladu je w koszu,
    nie w /dev/null - historia publikacji bywa potrzebna, gdy ktos pyta 'co mu wyslales'."""
    target = SITE_ROOT / slug
    ignores = list(args.ignore or []) or (existing or {}).get("ignore", [])

    if needs_markdown(source):
        _md_renderer()  # ewentualny re-exec przez uv PRZED tworzeniem czegokolwiek

    backup = None
    if target.exists():
        backup = trash_dir() / f"{slug}-{dt.datetime.now():%Y%m%d-%H%M%S}"
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(target), str(backup))

    # Odswiezenie tresci nie moze gubic tytulu nadanego przy publikacji - bez tego
    # `update` po cichu zamienialby "Garderoba - dokumentacja techniczna" na nazwe folderu.
    title_hint = args.title or (existing or {}).get("title")
    try:
        kind, title = build_document(source, target, title_hint, ignores)
    except Exception:
        shutil.rmtree(target, ignore_errors=True)
        if backup is not None:
            shutil.move(str(backup), str(target))  # nieudana aktualizacja nie zdejmuje starej wersji
        raise

    doc = existing if existing is not None else {"slug": slug, "created": now()}
    doc.update({
        "title": title,
        "kind": kind,
        "spa": bool(getattr(args, "spa", False)) or doc.get("spa", False),
        "ignore": ignores,
        "source": str(source),
        "updated": now(),
        "url": f"{BASE_URL}/{slug}/",
    })
    doc.pop("unpublished", None)
    if existing is None:
        manifest["documents"].append(doc)
    save_manifest(manifest)
    regenerate_redirects(manifest)
    write_marker(source, doc)
    return doc


def cmd_add(args: argparse.Namespace) -> int:
    source = Path(args.path).expanduser().resolve()
    if not source.exists():
        raise PublishError(f"Nie ma takiej sciezki: {source}")
    manifest = load_manifest()

    # Bez jawnego --slug traktujemy to jako "opublikuj ten material": jesli juz gdzies
    # wisi, odswiezamy go POD TYM SAMYM adresem, zamiast mnozyc linki do tej samej rzeczy.
    # Jawny --slug znaczy "chce go wlasnie tu" i jest silniejszy od tego domyslu.
    existing = None
    if not args.slug:
        existing = find_by_source(manifest, source) or adopt_from_marker(manifest, source)
    else:
        by_slug = find_doc(manifest, slugify(args.slug))
        if by_slug and os.path.realpath(by_slug.get("source", "")) == os.path.realpath(source):
            existing = by_slug

    if existing:
        slug = existing["slug"]
    else:
        slug = make_slug(args.slug or (source.name if source.is_dir() else source.stem), manifest)

    doc = write_document(source, slug, args, manifest, existing)

    if not args.no_deploy:
        deploy(quiet=args.quiet)
    if existing:
        print(f"{doc['url']}  (aktualizacja istniejacej publikacji - ten sam adres)")
    else:
        print(doc["url"])
    return 0


def cmd_update(args: argparse.Namespace) -> int:
    manifest = load_manifest()
    doc = find_doc(manifest, args.slug)
    if not doc:
        raise PublishError(f"Nie znam sluga: {args.slug}")
    source = Path(args.path).expanduser().resolve() if args.path else Path(doc["source"])
    if not source.exists():
        raise PublishError(f"Nie ma takiej sciezki: {source}")

    doc = write_document(source, args.slug, args, manifest, doc)
    if not args.no_deploy:
        deploy(quiet=args.quiet)
    print(doc["url"])
    return 0


def trash_dir() -> Path:
    return STATE_ROOT / "trash"  # poza katalogiem deployu - nie trafia do sieci


def cmd_unpublish(args: argparse.Namespace) -> int:
    manifest = load_manifest()
    doc = find_doc(manifest, args.slug)
    if not doc:
        raise PublishError(f"Nie znam sluga: {args.slug}")
    target = SITE_ROOT / args.slug
    dest = trash_dir() / f"{args.slug}-{dt.datetime.now():%Y%m%d-%H%M%S}"
    dest.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        shutil.move(str(target), str(dest))  # NIE kasujemy - tresc zostaje w koszu

    manifest["documents"] = [d for d in manifest["documents"] if d["slug"] != args.slug]
    doc["unpublished"] = now()
    doc["trash"] = str(dest)
    manifest.setdefault("trash", []).append(doc)
    save_manifest(manifest)
    regenerate_redirects(manifest)

    source = Path(doc.get("source", ""))
    if source.exists():
        write_marker(source, doc)  # marker ma wiedziec, ze to juz nie wisi

    if not args.no_deploy:
        deploy(quiet=args.quiet)
    print(f"zdjete: {doc['url']}  (tresc w {dest})")
    return 0


def cmd_list(args: argparse.Namespace) -> int:
    manifest = load_manifest()
    docs = manifest["documents"]
    if args.format == "json":
        print(json.dumps(docs, ensure_ascii=False, indent=2))
        return 0
    if not docs:
        print("(nic nie opublikowano)")
        return 0
    rows = [
        {
            "slug": d["slug"],
            "tytul": d["title"][:40],
            "typ": d["kind"] + (" spa" if d.get("spa") else ""),
            "zmieniono": d["updated"][:10],
            "zrodlo": Path(d.get("source", "")).name,
            "url": d["url"],
        }
        for d in docs
    ]
    headers = list(rows[0])
    widths = {h: max(len(h), *(len(str(r[h])) for r in rows)) for h in headers}
    print(" | ".join(h.ljust(widths[h]) for h in headers))
    print("-+-".join("-" * widths[h] for h in headers))
    for row in rows:
        print(" | ".join(str(row[h]).ljust(widths[h]) for h in headers))
    return 0


def cmd_info(args: argparse.Namespace) -> int:
    manifest = load_manifest()
    doc = find_doc(manifest, args.slug)
    if not doc:
        raise PublishError(f"Nie znam sluga: {args.slug}")
    files = sorted(p.relative_to(SITE_ROOT / args.slug).as_posix()
                   for p in (SITE_ROOT / args.slug).rglob("*") if p.is_file())
    print(json.dumps({**doc, "files": files}, ensure_ascii=False, indent=2))
    return 0


def cmd_find(args: argparse.Namespace) -> int:
    """Czy to bylo juz publikowane i pod jakim adresem? Pytanie, ktore pada zawsze,
    gdy material sie zmienil i trzeba go odswiezyc BEZ generowania nowego linku."""
    needle = args.query.lower()
    manifest = load_manifest()
    hits = [d for d in manifest["documents"]
            if needle in d["slug"].lower()
            or needle in d["title"].lower()
            or needle in d.get("source", "").lower()]
    if not hits:
        path = Path(args.query).expanduser()
        if path.exists():
            for entry in read_marker(path.resolve()).get("published", []):
                if not entry.get("unpublished"):
                    hits.append({**entry, "slug": entry.get("slug", ""),
                                 "source": str(path), "kind": "(z markera)"})
    print(json.dumps(hits, ensure_ascii=False, indent=2))
    return 0


def cmd_deploy(args: argparse.Namespace) -> int:
    manifest = load_manifest()
    regenerate_redirects(manifest)
    deploy(quiet=args.quiet)
    print(BASE_URL + "/")
    return 0


# --------------------------------------------------------------------------
# CLI

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Publikowanie dokumentow na Cloudflare Pages (jedna subdomena, wiele podfolderow)"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_add = sub.add_parser("add", help="opublikuj plik .md/.html albo folder")
    p_add.add_argument("path")
    p_add.add_argument("--slug", metavar="ADRES",
                       help="adres dokumentu: <BASE_URL>/<slug>/. Bierzemy doslownie "
                            "(tylko normalizacja do a-z0-9-). Bez tego: nazwa pliku/folderu, "
                            "a gdy to zrodlo juz wisi - jego dotychczasowy adres")
    p_add.add_argument("--title", help="tytul dokumentu")
    p_add.add_argument("--spa", action="store_true", help="routing po stronie klienta (fallback do index.html)")
    p_add.add_argument("--ignore", action="append", metavar="WZORZEC",
                       help="pomin pliki/katalogi (mozna powtarzac); smieci budowania sa pomijane zawsze")
    p_add.add_argument("--no-deploy", action="store_true", help="tylko lustro, deploy pozniej")
    p_add.add_argument("--quiet", action="store_true")
    p_add.set_defaults(func=cmd_add)

    p_update = sub.add_parser("update", help="podmien tresc pod tym samym adresem")
    p_update.add_argument("slug")
    p_update.add_argument("path", nargs="?", help="domyslnie: zrodlo zapamietane przy publikacji")
    p_update.add_argument("--title")
    p_update.add_argument("--ignore", action="append", metavar="WZORZEC")
    p_update.add_argument("--no-deploy", action="store_true")
    p_update.add_argument("--quiet", action="store_true")
    p_update.set_defaults(func=cmd_update)

    p_unpub = sub.add_parser("unpublish", help="zdejmij dokument (tresc ladnie do .trash/)")
    p_unpub.add_argument("slug")
    p_unpub.add_argument("--no-deploy", action="store_true")
    p_unpub.add_argument("--quiet", action="store_true")
    p_unpub.set_defaults(func=cmd_unpublish)

    p_list = sub.add_parser("list", help="co jest opublikowane (bez ruchu sieciowego)")
    p_list.add_argument("--format", choices=["table", "json"], default="table")
    p_list.set_defaults(func=cmd_list)

    p_find = sub.add_parser("find", help="czy to juz bylo publikowane? (slug, tytul, sciezka zrodla)")
    p_find.add_argument("query")
    p_find.set_defaults(func=cmd_find)

    p_info = sub.add_parser("info", help="szczegoly jednego dokumentu")
    p_info.add_argument("slug")
    p_info.set_defaults(func=cmd_info)

    p_deploy = sub.add_parser("deploy", help="redeploy calego lustra (naprawczy)")
    p_deploy.add_argument("--quiet", action="store_true")
    p_deploy.set_defaults(func=cmd_deploy)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except PublishError as exc:
        print(f"blad: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
