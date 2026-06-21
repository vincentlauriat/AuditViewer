#!/usr/bin/env python3
"""auditv — lecteur CLI des dossiers d'audit générés par /audit-report.

Zéro dépendance (stdlib uniquement). Trois modes :

    auditv                      liste tous les audits du répertoire
    auditv <sujet|slug>         fiche synthèse d'un audit
    auditv <slug> <dim>         rendu markdown d'une dimension (ou 'report')
    auditv --search <terme>     recherche plein-texte dans tous les audits

Voir --help pour le détail. Conçu pour les dossiers `audit-{slug}/` contenant
`_manifest.json`, `_data.json` et les fichiers `NN_*.md`.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import textwrap
import unicodedata

# ─────────────────────────────────────────────────────────── couleurs ANSI ──

class C:
    RESET = "\033[0m"; BOLD = "\033[1m"; DIM = "\033[2m"; ITAL = "\033[3m"
    UND = "\033[4m"
    RED = "\033[31m"; GREEN = "\033[32m"; YELLOW = "\033[33m"; BLUE = "\033[34m"
    MAGENTA = "\033[35m"; CYAN = "\033[36m"; GREY = "\033[90m"
    BBLUE = "\033[94m"; BCYAN = "\033[96m"; BGREEN = "\033[92m"; BYELLOW = "\033[93m"


_USE_COLOR = True


def enable_color(flag: bool) -> None:
    global _USE_COLOR
    _USE_COLOR = flag


def col(s: str, *codes: str) -> str:
    if not _USE_COLOR or not codes:
        return s
    return "".join(codes) + s + C.RESET


def term_width(default: int = 100) -> int:
    try:
        w = shutil.get_terminal_size((default, 24)).columns
    except Exception:
        w = default
    return max(40, min(w, 120))


# ─────────────────────────────────────────────────────────── découverte ──

def resolve_root(explicit: str | None) -> str:
    candidates = []
    if explicit:
        candidates.append(explicit)
    candidates.append(os.getcwd())
    candidates.append(os.path.expanduser("~/Documents/Research"))
    for c in candidates:
        if c and os.path.isdir(c) and find_audit_dirs(c):
            return os.path.abspath(c)
    # rien trouvé : retourner le premier candidat valable comme dossier
    for c in candidates:
        if c and os.path.isdir(c):
            return os.path.abspath(c)
    return os.path.abspath(explicit or os.getcwd())


def find_audit_dirs(root: str) -> list[str]:
    out = []
    try:
        for name in os.listdir(root):
            if not name.startswith("audit-"):
                continue
            path = os.path.join(root, name)
            if not os.path.isdir(path):
                continue
            # un audit = a un manifest, ou au moins des fichiers NN_*.md
            if os.path.exists(os.path.join(path, "_manifest.json")) or \
               any(re.match(r"\d\d_.*\.md$", f) for f in os.listdir(path)):
                out.append(path)
    except FileNotFoundError:
        pass
    return sorted(out)


def slugify(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    s = re.sub(r"[^a-zA-Z0-9]+", "-", s).strip("-").lower()
    return s or "sujet"


def load_manifest(audit_dir: str) -> dict:
    p = os.path.join(audit_dir, "_manifest.json")
    if os.path.exists(p):
        try:
            return json.load(open(p, encoding="utf-8"))
        except Exception:
            pass
    return {}


def audit_slug(audit_dir: str) -> str:
    return os.path.basename(audit_dir)[len("audit-"):]


def get_subject(audit_dir: str, manifest: dict) -> str:
    s = manifest.get("subject")
    if s:
        return s
    p = os.path.join(audit_dir, "00_RESUME_EXECUTIF.md")
    if os.path.exists(p):
        head = open(p, encoding="utf-8").read()[:800]
        m = re.search(r'^subject:\s*"?([^"\n]+)"?', head, re.M)
        if m:
            return m.group(1).strip()
        m = re.search(r"^#\s+(.*)$", head, re.M)
        if m:
            return re.split(r"\s*[—–-]\s*", m.group(1))[0].strip()
    return audit_slug(audit_dir).replace("-", " ").title()


def resolve_audit(root: str, query: str) -> tuple[str | None, list[str]]:
    """Retourne (audit_dir, candidats). audit_dir non-None si résolution unique."""
    dirs = find_audit_dirs(root)
    by_slug = {audit_slug(d): d for d in dirs}

    # 1. correspondance exacte sur le slug calculé
    q_slug = slugify(query)
    if q_slug in by_slug:
        return by_slug[q_slug], []
    # 2. correspondance exacte sur le nom de dossier fourni tel quel
    direct = os.path.join(root, query if query.startswith("audit-") else f"audit-{query}")
    if os.path.isdir(direct) and direct in dirs:
        return direct, []

    # 3. sous-chaîne sur les slugs
    sub = [d for s, d in by_slug.items() if q_slug and q_slug in s]
    if len(sub) == 1:
        return sub[0], []
    if len(sub) > 1:
        return None, sorted(sub)

    # 4. recherche sur le sujet du manifest (insensible casse/accents)
    qnorm = slugify(query)
    subj = []
    for d in dirs:
        m = load_manifest(d)
        if slugify(m.get("subject", "")).find(qnorm) >= 0 and qnorm:
            subj.append(d)
    if len(subj) == 1:
        return subj[0], []
    if len(subj) > 1:
        return None, sorted(subj)

    return None, []


# ───────────────────────────────────────────────────── résolution dimension ──

DIM_ALIASES = {
    "resume": "00", "summary": "00", "exec": "00",
    "histo": "01", "history": "01", "historique": "01",
    "marche": "02", "market": "02",
    "tech": "03", "technique": "03", "technical": "03",
    "prix": "04", "tarif": "04", "tarification": "04", "pricing": "04",
    "conc": "05", "concurrence": "05", "competition": "05",
    "fin": "06", "financier": "06", "financial": "06",
    "futur": "07", "future": "07", "outlook": "07",
    "esg": "08",
    "swot": "09",
    "rh": "10", "hr": "10",
}


def list_md_files(audit_dir: str) -> list[str]:
    return sorted(f for f in os.listdir(audit_dir) if re.match(r"\d\d_.*\.md$", f))


def resolve_dimension(audit_dir: str, arg: str) -> str | None:
    files = list_md_files(audit_dir)
    a = slugify(arg)

    if a in ("report", "complet", "full", "rapport", "all"):
        rc = os.path.join(audit_dir, "RAPPORT_COMPLET.md")
        return rc if os.path.exists(rc) else None
    if a in ("changelog", "change"):
        cl = os.path.join(audit_dir, "CHANGELOG.md")
        return cl if os.path.exists(cl) else None
    if a in ("factcheck", "fact", "verif"):
        fc = os.path.join(audit_dir, "_factcheck.md")
        return fc if os.path.exists(fc) else None

    # numéro à deux chiffres ou alias → numéro
    num = None
    if re.fullmatch(r"\d{1,2}", arg):
        num = arg.zfill(2)
    elif a in DIM_ALIASES:
        num = DIM_ALIASES[a]
    if num:
        for f in files:
            if f.startswith(num + "_"):
                return os.path.join(audit_dir, f)
        return None

    # sous-chaîne sur le nom de fichier
    matches = [f for f in files if a and a in slugify(f)]
    if len(matches) == 1:
        return os.path.join(audit_dir, matches[0])
    return None


# ───────────────────────────────────────────────────────── rendu markdown ──

EXTERNAL_RENDERERS = (
    ("glow", ["glow", "-s", "dark", "-w", "{w}", "{f}"]),
    ("bat", ["bat", "--style=plain", "--language=markdown", "--paging=never", "{f}"]),
)


def find_external_renderer():
    for name, tmpl in EXTERNAL_RENDERERS:
        if shutil.which(name):
            return name, tmpl
    return None


def render_file(path: str, raw: bool, force_internal: bool) -> str:
    text = open(path, encoding="utf-8").read()
    text = strip_vault_nav(text)
    if raw:
        return text
    if not force_internal and _USE_COLOR:
        ext = find_external_renderer()
        if ext:
            name, tmpl = ext
            w = str(term_width())
            cmd = [a.format(w=w, f=path) for a in tmpl]
            try:
                # passer le texte nettoyé via stdin n'est pas possible pour glow -w {f};
                # on rend le fichier tel quel (le nav vault est anecdotique)
                r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
                if r.returncode == 0 and r.stdout.strip():
                    return r.stdout
            except Exception:
                pass
    return render_markdown_ansi(text)


def strip_yaml_blocks(text: str) -> str:
    """Retire les blocs frontmatter YAML (--- … ---), en tête ou insérés au
    milieu (cas du RAPPORT_COMPLET fusionné). Un bloc n'est retiré que si toutes
    ses lignes non vides ressemblent à du YAML (`clé: valeur`), pour ne jamais
    avaler du contenu encadré de règles horizontales."""
    lines = text.split("\n")
    out: list[str] = []
    i = 0
    while i < len(lines):
        if lines[i].strip() == "---":
            j = i + 1
            block = []
            while j < len(lines) and lines[j].strip() != "---":
                block.append(lines[j])
                j += 1
            closed = j < len(lines)
            yaml_line = re.compile(r"^[\w.-]+:\s")
            is_yaml = (
                closed
                and any(yaml_line.match(b) for b in block)          # ≥1 vraie clé
                and all((not b.strip()) or yaml_line.match(b) for b in block)
            )
            if closed and is_yaml:
                i = j + 1  # sauter le bloc entier, fermeture comprise
                continue
        out.append(lines[i])
        i += 1
    return "\n".join(out)


def strip_vault_nav(text: str) -> str:
    text = strip_yaml_blocks(text)
    text = re.split(r"\n-+\n<!-- vault-nav -->", text)[0]
    text = re.split(r"\n<!-- vault-nav -->", text)[0]
    return text.rstrip() + "\n"


def _inline(s: str) -> str:
    """Mise en forme inline : gras, code, liens, tags de source, alertes."""
    # liens [txt](url) → txt souligné + url grise
    def link(m):
        return col(m.group(1), C.BCYAN, C.UND) + col(" ‹" + m.group(2) + "›", C.GREY)
    s = re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", link, s)
    # gras **...**
    s = re.sub(r"\*\*([^*]+)\*\*", lambda m: col(m.group(1), C.BOLD), s)
    # code `...`
    s = re.sub(r"`([^`]+)`", lambda m: col(m.group(1), C.YELLOW), s)
    # tags de source
    s = s.replace("[Officielle]", col("[Officielle]", C.BGREEN, C.BOLD))
    s = s.replace("[Analyste]", col("[Analyste]", C.BBLUE, C.BOLD))
    s = s.replace("[Presse]", col("[Presse]", C.MAGENTA, C.BOLD))
    # alerte
    s = s.replace("⚠️", col("⚠️", C.BYELLOW))
    return s


def render_markdown_ansi(text: str) -> str:
    width = term_width()
    out: list[str] = []
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i].rstrip("\n")
        stripped = line.strip()

        # tableau : bloc de lignes consécutives commençant par |
        if stripped.startswith("|"):
            block = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                block.append(lines[i].strip())
                i += 1
            out.append(render_table(block, width))
            continue

        # titres
        m = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if m:
            level = len(m.group(1))
            txt = _inline(m.group(2))
            if level == 1:
                out.append("")
                out.append(col(txt.upper(), C.BOLD, C.BCYAN))
                out.append(col("═" * min(len(m.group(2)), width), C.CYAN))
            elif level == 2:
                out.append("")
                out.append(col("▌ " + txt, C.BOLD, C.BBLUE))
            else:
                out.append("")
                out.append(col("• " + txt, C.BOLD))
            i += 1
            continue

        # règle horizontale
        if re.fullmatch(r"-{3,}|\*{3,}|_{3,}", stripped):
            out.append(col("─" * width, C.GREY))
            i += 1
            continue

        # citation
        if stripped.startswith(">"):
            q = _inline(stripped[1:].strip())
            for w in textwrap.wrap(q, width - 4) or [""]:
                out.append(col("  ┃ ", C.GREY) + col(w, C.DIM))
            i += 1
            continue

        # listes
        lm = re.match(r"^(\s*)([-*+]|\d+\.)\s+(.*)$", line)
        if lm:
            indent = len(lm.group(1))
            bullet = "•" if lm.group(2) in "-*+" else lm.group(2)
            body = _inline(lm.group(3))
            prefix = " " * indent + col(bullet, C.CYAN) + " "
            wrapped = textwrap.wrap(body, max(20, width - len(prefix))) or [""]
            out.append(prefix + wrapped[0])
            for w in wrapped[1:]:
                out.append(" " * (indent + 2) + w)
            i += 1
            continue

        # paragraphe
        if stripped == "":
            out.append("")
        else:
            for w in textwrap.wrap(_inline(stripped), width) or [""]:
                out.append(w)
        i += 1

    # compresser les lignes vides multiples
    res = []
    blank = False
    for l in out:
        if l == "":
            if blank:
                continue
            blank = True
        else:
            blank = False
        res.append(l)
    return "\n".join(res)


def _vis_len(s: str) -> int:
    return len(re.sub(r"\033\[[0-9;]*m", "", s))


def render_table(block: list[str], width: int) -> str:
    rows = []
    for ln in block:
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        rows.append(cells)
    # repérer/retirer la ligne séparatrice ---|---
    body = []
    sep_idx = None
    for idx, r in enumerate(rows):
        if all(re.fullmatch(r":?-{2,}:?", c) for c in r if c) and any(r):
            sep_idx = idx
            continue
        body.append(r)
    if not body:
        return ""
    ncol = max(len(r) for r in body)
    for r in body:
        r += [""] * (ncol - len(r))

    # largeur naturelle de chaque colonne
    natural = [0] * ncol
    for r in body:
        for c in range(ncol):
            natural[c] = max(natural[c], min(_vis_len(r[c]), 60))
    pad = 3 * ncol + 1
    avail = width - pad
    if sum(natural) > avail and sum(natural) > 0:
        # répartir proportionnellement, mini 6
        scale = avail / sum(natural)
        widths = [max(6, int(n * scale)) for n in natural]
    else:
        widths = [max(3, n) for n in natural]

    header = body[0] if sep_idx is not None else None
    data = body[1:] if sep_idx is not None else body

    def fmt_row(cells, is_header):
        wrapped_cells = []
        for c in range(ncol):
            raw = cells[c]
            styled = _inline(raw)
            # textwrap sur le texte brut, puis ré-appliquer l'inline ligne à ligne
            plain = re.sub(r"\033\[[0-9;]*m", "", styled)
            wlines = textwrap.wrap(plain, widths[c]) or [""]
            if is_header:
                wlines = [col(x, C.BOLD, C.BBLUE) for x in wlines]
            else:
                wlines = [_inline(x) for x in wlines]
            wrapped_cells.append(wlines)
        h = max(len(w) for w in wrapped_cells)
        out_lines = []
        for li in range(h):
            parts = []
            for c in range(ncol):
                seg = wrapped_cells[c][li] if li < len(wrapped_cells[c]) else ""
                parts.append(seg + " " * (widths[c] - _vis_len(seg)))
            out_lines.append(col(" │ ", C.GREY).join([""] + parts + [""]).rstrip())
        return "\n".join(out_lines)

    lines = []
    table_w = sum(widths) + 3 * ncol + 1
    if header:
        lines.append(fmt_row(header, True))
        lines.append(col(" " + "─" * (table_w - 1), C.GREY))
    for r in data:
        lines.append(fmt_row(r, False))
    return "\n".join(lines)


# ───────────────────────────────────────────────────────────── modes ──

def cmd_list(root: str) -> int:
    dirs = find_audit_dirs(root)
    if not dirs:
        print(col(f"Aucun audit trouvé dans {root}", C.YELLOW))
        print(col("Astuce : --root <chemin> ou lance depuis le dossier des audits.", C.GREY))
        return 1
    print(col(f"\n  {len(dirs)} audits — {root}\n", C.BOLD, C.BCYAN))
    rows = [["SLUG", "SUJET", "TYPE", "DATE", "SRC", "ÉTAT"]]
    for d in dirs:
        m = load_manifest(d)
        rows.append([
            audit_slug(d),
            get_subject(d, m)[:32],
            (m.get("subject_type") or "")[:10],
            m.get("audit_date") or "",
            str(m.get("sources_count") or ""),
            (m.get("status") or "")[:8],
        ])
    widths = [max(len(r[c]) for r in rows) for c in range(6)]
    for ri, r in enumerate(rows):
        cells = [r[c].ljust(widths[c]) for c in range(6)]
        line = "  " + "  ".join(cells)
        if ri == 0:
            print(col(line, C.BOLD, C.GREY))
            print(col("  " + "─" * (len(line) - 2), C.GREY))
        else:
            slug = col(cells[0], C.BCYAN)
            state = cells[5]
            if r[5] == "complete":
                state = col(cells[5], C.GREEN)
            elif r[5] in ("partial", "canceled"):
                state = col(cells[5], C.YELLOW)
            print("  " + "  ".join([slug, cells[1], col(cells[2], C.GREY),
                                    cells[3], col(cells[4], C.DIM), state]))
    print(col("\n  → auditv <slug>            fiche synthèse", C.GREY))
    print(col("  → auditv <slug> <dim>      ouvrir une dimension", C.GREY))
    print(col("  → auditv --search <terme>  rechercher\n", C.GREY))
    return 0


def cmd_card(root: str, audit_dir: str) -> int:
    m = load_manifest(audit_dir)
    slug = audit_slug(audit_dir)
    subject = get_subject(audit_dir, m)
    width = term_width()

    print()
    print("  " + col(subject.upper(), C.BOLD, C.BCYAN))
    meta = "  ·  ".join(filter(None, [
        m.get("subject_type", ""),
        (f"audit {m.get('audit_date')}" if m.get("audit_date") else ""),
        (f"{m.get('sources_count')} sources" if m.get("sources_count") else ""),
        (f"depth {m.get('depth')}" if m.get("depth") else ""),
        (("options: " + ", ".join(m.get("options", []))) if m.get("options") else ""),
    ]))
    if meta:
        print("  " + col(meta, C.GREY))
    print(col("  " + "─" * (width - 4), C.CYAN))

    # KPIs
    data = {}
    dp = os.path.join(audit_dir, "_data.json")
    if os.path.exists(dp):
        try:
            data = json.load(open(dp, encoding="utf-8"))
        except Exception:
            data = {}
    kpis = data.get("kpis", [])
    if kpis:
        print(col("\n  CHIFFRES CLÉS", C.BOLD, C.BBLUE))
        for k in kpis[:14]:
            label = (k.get("label") or k.get("key") or "")[:46]
            val = f"{k.get('value','')}"
            unit = k.get("unit", "")
            _skip = ("date", "version", "rating", "event", "license", "factor", "price")
            if unit and unit not in _skip and unit.lower() not in val.lower():
                val = f"{val} {unit}"
            period = k.get("period", "")
            est = col(" ~est", C.DIM) if k.get("estimated") else ""
            line = "  " + col("·", C.CYAN) + " " + label.ljust(46) + " "
            line += col(val, C.BOLD)
            if period:
                line += col(f"  ({period})", C.GREY)
            line += est
            print(line)
        if len(kpis) > 14:
            print(col(f"    … +{len(kpis)-14} autres KPIs (voir une dimension)", C.GREY))

    # Verdict (depuis 00_RESUME)
    verdict = extract_section(os.path.join(audit_dir, "00_RESUME_EXECUTIF.md"),
                              ("verdict",))
    if verdict:
        print(col("\n  VERDICT", C.BOLD, C.BBLUE))
        for para in verdict.split("\n"):
            for w in textwrap.wrap(_inline(para.strip()), width - 4) or [""]:
                print("  " + w)

    # Dimensions disponibles
    files = list_md_files(audit_dir)
    if files:
        print(col("\n  DIMENSIONS", C.BOLD, C.BBLUE))
        names = []
        for f in files:
            num = f[:2]
            nm = re.sub(r"^\d\d_|\.md$", "", f).replace("_", " ").title()
            names.append(col(num, C.BCYAN) + " " + nm)
        # afficher en colonnes
        colw = max(_vis_len(n) for n in names) + 3
        per = max(1, (width - 2) // colw)
        for r in range(0, len(names), per):
            print("  " + "".join(n + " " * (colw - _vis_len(n)) for n in names[r:r+per]))
    extras = [f for f in ("RAPPORT_COMPLET.md", "CHANGELOG.md", "_factcheck.md")
              if os.path.exists(os.path.join(audit_dir, f))]
    if extras:
        tags = {"RAPPORT_COMPLET.md": "report", "CHANGELOG.md": "changelog",
                "_factcheck.md": "factcheck"}
        print(col("  + ", C.GREY) + col("  ".join(tags[e] for e in extras), C.GREY))
    print(col(f"\n  → auditv {slug} <dim>   ex: auditv {slug} 00\n", C.GREY))
    return 0


def extract_section(path: str, names: tuple[str, ...]) -> str:
    if not os.path.exists(path):
        return ""
    text = open(path, encoding="utf-8").read()
    lines = text.split("\n")
    capturing = False
    buf = []
    for ln in lines:
        m = re.match(r"^#{1,6}\s+(.*)$", ln.strip())
        if m:
            if capturing:
                break
            title = slugify(m.group(1))
            if any(n in title for n in names):
                capturing = True
                continue
        elif capturing:
            if ln.strip().startswith("---"):
                break
            buf.append(ln)
    return "\n".join(buf).strip()


def cmd_render(audit_dir: str, dim_arg: str, raw: bool, force_internal: bool) -> int:
    path = resolve_dimension(audit_dir, dim_arg)
    if not path:
        print(col(f"Dimension '{dim_arg}' introuvable dans {audit_slug(audit_dir)}.",
                  C.YELLOW))
        files = list_md_files(audit_dir)
        print(col("Disponibles : " + ", ".join(f[:2] for f in files) +
                  ", report, changelog, factcheck", C.GREY))
        return 1
    print(render_file(path, raw, force_internal))
    return 0


def cmd_search(root: str, term: str, scope: str | None, raw: bool) -> int:
    dirs = find_audit_dirs(root)
    if scope:
        d, cands = resolve_audit(root, scope)
        if d:
            dirs = [d]
        elif cands:
            print(col("Plusieurs audits correspondent : " +
                      ", ".join(audit_slug(c) for c in cands), C.YELLOW))
            return 1
        else:
            # Périmètre fourni mais introuvable : ne pas retomber silencieusement
            # sur une recherche globale (résultats trompeurs).
            print(col(f"Aucun audit ne correspond au périmètre '{scope}'.", C.YELLOW))
            return 1
    rx = re.compile(re.escape(term), re.IGNORECASE)
    total = 0
    for d in dirs:
        hits = []
        for f in sorted(os.listdir(d)):
            if not f.endswith(".md"):
                continue
            try:
                for ln in open(os.path.join(d, f), encoding="utf-8"):
                    if rx.search(ln):
                        hits.append((f, ln.strip()))
            except Exception:
                continue
        if hits:
            total += len(hits)
            print(col(f"\n▌ {audit_slug(d)}", C.BOLD, C.BCYAN) +
                  col(f"  ({len(hits)})", C.GREY))
            for f, ln in hits[:8]:
                snippet = ln if len(ln) <= 110 else ln[:107] + "…"
                if not raw:
                    snippet = rx.sub(lambda m: col(m.group(0), C.BOLD, C.YELLOW), snippet)
                    snippet = _inline(snippet)
                print("  " + col(f[:18].ljust(18), C.GREY) + " " + snippet)
            if len(hits) > 8:
                print(col(f"  … +{len(hits)-8} autres occurrences", C.GREY))
    if total == 0:
        print(col(f"Aucune occurrence de « {term} ».", C.YELLOW))
        return 1
    print(col(f"\n{total} occurrences.\n", C.GREY))
    return 0


# ───────────────────────────────────────────────────────────── main ──

def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(
        prog="auditv",
        description="Lecteur CLI des dossiers d'audit générés par /audit-report.",
        epilog="Exemples : auditv · auditv mlx · auditv mlx 03 · "
               "auditv --search gemini",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("subject", nargs="?", help="sujet ou slug de l'audit")
    p.add_argument("dimension", nargs="?",
                   help="dimension : 00–10, un nom (marche, swot…), ou report/changelog/factcheck")
    p.add_argument("--search", metavar="TERME", help="recherche plein-texte")
    p.add_argument("--root", metavar="CHEMIN", help="dossier contenant les audit-*/")
    p.add_argument("--raw", action="store_true", help="markdown brut, sans couleurs ni rendu")
    p.add_argument("--internal", action="store_true",
                   help="forcer le rendu interne (ignorer glow/bat)")
    p.add_argument("--no-color", action="store_true", help="désactiver les couleurs")
    args = p.parse_args(argv)

    use_color = sys.stdout.isatty() and not args.no_color and not args.raw \
        and os.environ.get("NO_COLOR") is None
    enable_color(use_color)

    root = resolve_root(args.root)

    if args.search:
        return cmd_search(root, args.search, args.subject, args.raw)

    if not args.subject:
        return cmd_list(root)

    audit_dir, cands = resolve_audit(root, args.subject)
    if not audit_dir:
        if cands:
            print(col(f"« {args.subject} » correspond à plusieurs audits :", C.YELLOW))
            for c in cands:
                print("  " + col(audit_slug(c), C.BCYAN))
            return 1
        print(col(f"Aucun audit pour « {args.subject} » dans {root}.", C.YELLOW))
        print(col("→ auditv   (sans argument) pour lister les audits.", C.GREY))
        return 1

    if args.dimension:
        return cmd_render(audit_dir, args.dimension, args.raw, args.internal)
    return cmd_card(root, audit_dir)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except BrokenPipeError:
        try:
            sys.stdout.close()
        except Exception:
            pass
        sys.exit(0)
    except KeyboardInterrupt:
        sys.exit(130)
