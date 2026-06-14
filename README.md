# AuditViewer

**Turn any company, product, market or technology into a complete strategic dossier — in minutes, with one line.**

*🇫🇷 [Lire ce README en français](README.fr.md)*

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Web-blue)
![Works with](https://img.shields.io/badge/AI-Claude%20Code%20%7C%20Gemini-7c3aed)

---

You type a name — `Tesla`, `Notion`, `the LLM market`, `Société Générale`. A few minutes later you have a structured, sourced, fact-checked research dossier worth what a consulting firm would bill thousands for: history, market sizing, technology, pricing, competition, financials, outlook — each figure backed by a dated source.

AuditViewer is **an AI strategic-research assistant** made of three parts that work together:

| Part | What it is | For whom |
|---|---|---|
| 🧠 **`audit-report` skill** | The engine. One command that researches a topic and writes a full dossier. | Anyone with Claude Code or Gemini |
| 🌐 **Web viewer** | A browser app to launch, watch, and read audits live. | Users who prefer a web UI |
| 🖥️ **macOS app** | A native Mac app to read, compare and explore audits as a knowledge map. | Mac users |

![Audit-Report: your AI strategic-consulting partner](images/Audit-Report__AI_Strategic_Consulting.png)

---

## Why it exists

Researching a company or a market properly is slow, repetitive work: dozens of searches, cross-checking numbers, chasing official filings, separating fact from hype, then assembling it all into something readable. AuditViewer does that legwork for you and hands back a **decision-ready document**, not a pile of browser tabs.

It is built around one principle: **every number is sourced and dated.** The AI is explicitly instructed never to invent figures, to tag each source as *Official / Analyst / Press*, to flag data older than a year, and to cross-check the key numbers against at least two independent sources.

## What you actually get

Run one command and you get a folder of ready-to-read documents:

| File | What's inside |
|---|---|
| **Executive summary** | One page: key facts, headline figures, verdict |
| **History** | Origins, milestones, pivots, acquisitions, controversies |
| **Market** | Market size (TAM/SAM/SOM), growth, geography, regulation |
| **Technology** | Product, architecture, features, differentiators, patents |
| **Pricing** | Price tiers, business model, sector comparison |
| **Competition** | Competitive map, market shares, positioning, SWOT |
| **Financials** | Revenue, funding, valuation, key metrics |
| **Outlook** | Roadmap, weak signals, risks, scenarios |
| **Full report** | Everything merged into one paginated, shareable document |

Optional add-ons let you generate a dedicated **SWOT**, an **ESG / sustainability** chapter, an **HR & culture** chapter, or a single-page **brief**.

👉 See a real example and a guided walkthrough in **[the getting-started guide](docs/getting-started.md)**.

## Who it's for

- **Decision-makers & analysts** — due diligence before an investment, competitive monitoring, market studies. Get in minutes what normally takes days of desk research. → [Use cases](docs/use-cases.md)
- **Curious non-experts** — understand a company, a product or an industry without wading through jargon. The reports read like a briefing, not a spreadsheet.
- **Developers & contributors** — the skill speaks a documented, versioned [machine contract](ARCHITECTURE.md) so you can build your own tools on top of it.

---

## How it works, in three steps

1. **You ask.** `/audit-report Tesla` — optionally choosing depth, language, and extra chapters.
2. **The AI investigates.** It does a quick reconnaissance, confirms the scope with you, then researches each dimension in parallel, fact-checks the key numbers, and assembles the report.
3. **You read & explore.** Open the folder directly, or use the web viewer / Mac app to follow progress live, browse chapters, and see how audits connect to each other.

A deeper, still-non-technical explanation lives in **[How it works](docs/how-it-works.md)**.

---

## Quick start

> New to this? Start with the **[getting-started guide](docs/getting-started.md)** — it assumes no technical background.

### 1 — The `audit-report` skill (the engine)

Requires [Claude Code](https://claude.com/claude-code) or Gemini.

```bash
./install.sh            # install for Claude Code (~/.claude/skills)
./install.sh --gemini   # install for Gemini (~/.gemini/config/skills)
./install.sh --copy     # copy instead of symlink
```

Then, inside your AI assistant:

```bash
/audit-report Apple
/audit-report "Tesla Model Y"
/audit-report "the LLM market" --lang en
/audit-report Notion --depth quick
```

Reference: [`skills/audit-report/SKILL.md`](skills/audit-report/SKILL.md).

### 2 — The web viewer

Requires [Node.js](https://nodejs.org/).

```bash
cd web
npm install
npm run dev    # backend on :3001, frontend on :5173 → open http://localhost:5173
```

Want to try it immediately with bundled sample data?

```bash
AUDITS_ROOT=../viewer-fixtures npm run dev
```

Details: [`web/README.md`](web/README.md).

### 3 — The macOS app

Requires macOS 15+ and the Swift toolchain.

```bash
cd mac
./build.sh
open build/AuditViewer.app
```

Details: [`mac/README.md`](mac/README.md).

---

## Documentation

| Guide | For |
|---|---|
| [Getting started](docs/getting-started.md) | Your first audit, step by step — no jargon |
| [Use cases](docs/use-cases.md) | Concrete scenarios by profession |
| [How it works](docs/how-it-works.md) | The concepts, in plain language |
| [FAQ](docs/faq.md) | Common questions answered |
| [Glossary](docs/glossary.md) | Every technical term, demystified |
| [Architecture](ARCHITECTURE.md) | The machine contract, for developers |

French versions live under [`docs/fr/`](docs/fr/).

---

## Under the hood: the machine contract

The three apps stay in sync because the skill writes its output as a **deterministic, versioned "machine contract" (v1)**: a real-time event stream (`_events.jsonl`), a two-way control channel (`_control.json`), an interactive question/answer cycle, and canonical structured outputs (`_manifest.json`, `_data.json`, `_sources.json`). Any tool that reads this contract can display or drive an audit.

![Machine Contract v1](images/SkillAuditReport___Contrat_Machine_V1.png)

Full specification: [ARCHITECTURE.md](ARCHITECTURE.md).

### Repository layout

| Folder | Role |
|---|---|
| `skills/audit-report/` | The AI audit skill (Claude Code / Gemini) |
| `web/` | Web viewer & control UI (Node + React) |
| `mac/` | Native macOS app (SwiftUI) |
| `docs/` | User documentation (this guide set) |
| `images/` | Illustrations used in the docs |

### Cross-platform

The same machine contract runs everywhere; only the internal execution engine differs.

| Platform | Recommended mode | Mechanism |
|---|---|---|
| **Claude Code** | `parallel` or `sequential` | Multi-agent orchestration |
| **Gemini / Antigravity** | `solo` | Single large-context run |

---

## License

[MIT](LICENSE) © 2026 Vincent Lauriat.
