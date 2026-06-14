# FAQ

Short answers to the questions people ask most. Still stuck? Open an issue on the repository.

---

### What exactly is AuditViewer?
A tool that turns a single request — like `/audit-report Tesla` — into a complete, sourced research dossier on any company, product, market, or technology. It comes with two optional viewers (a web app and a macOS app) to read and run audits comfortably. See [How it works](how-it-works.md).

### Do I need to be technical to use it?
No. If you can install one app and type a command, you can run an audit. The [getting-started guide](getting-started.md) assumes zero background. The viewers let you do everything from a graphical interface afterwards.

### What do I need to install?
At minimum, an AI assistant the skill runs inside: **[Claude Code](https://claude.com/claude-code)** (recommended) or **Gemini**. The web viewer additionally needs [Node.js](https://nodejs.org/); the Mac app needs macOS 15+ and the Swift toolchain. Both viewers are optional.

### Does it cost anything?
The project itself is free and open-source ([MIT license](../LICENSE)). Running audits consumes usage from your AI assistant (Claude Code or Gemini), which has its own pricing. A "quick" audit uses far fewer resources than a "full" one.

### How long does an audit take?
Usually a few minutes. A `--depth quick` audit (~10 sources, 4 dimensions) is faster; a `--depth full` audit (~30+ sources, 7 dimensions) is more thorough. You see progress the whole time.

### Can I trust the numbers?
The skill is built to be trustworthy: every figure carries a **source link and a date**, sources are tagged **Official / Analyst / Press**, stale data is flagged, estimates are labelled as such, and the key numbers are **cross-checked against at least two independent sources**. It is instructed never to invent a figure. That said, treat it as an excellent first draft — for high-stakes decisions, verify the critical claims yourself using the provided sources.

### What languages can the report be in?
By default the report is written in **English**; add `--lang fr` for French. The AI reads sources in any language and writes the report in the one you ask for.

### Which subjects work best?
Companies, products, markets, technologies, and sectors — anything with a public footprint. Well-known subjects yield the richest audits. Very obscure or private subjects will produce thinner reports, and the skill will tell you when data isn't publicly available rather than guess.

### What if my topic is ambiguous (e.g. "Jaguar")?
The reconnaissance step catches this. If the name genuinely maps to several unrelated things, the AI asks you which one you mean before doing the deep work.

### Can I focus on just one aspect?
Yes. Use `--focus <aspect>` (e.g. `--focus financials`) to go deeper on one angle, or `--brief` to get only a one-page summary. You can also add `--swot`, `--esg`, or `--rh` chapters.

### Can I update an audit later?
Yes. Re-run the same subject and the skill detects the existing audit, offering to **update** it — and produces a `CHANGELOG.md` of what changed. Ideal for monitoring over time.

### Where are my audits stored?
In a folder per audit (e.g. `audit-tesla/`), under your chosen audits directory (by default `~/Documents/Research`). They're plain Markdown and JSON files you fully own — readable anywhere, with or without the viewers.

### Do the viewers send my data anywhere?
No. The viewers read audit folders on your own machine. The only external calls are the web searches your AI assistant makes while researching.

### It works with Claude — does it work with Gemini?
Yes. The skill detects when sub-agents aren't available and automatically switches to "solo" mode, producing the same report. Install with `./install.sh --gemini`.

### How is this different from just asking ChatGPT/Claude "tell me about X"?
A chat answer comes from the model's memory and blends fact with approximation. An audit searches the **live web**, sources and dates every figure, fact-checks the key ones, and delivers a **structured, multi-chapter document** you can share. It's the difference between a verbal answer and a research report.

### I'm a developer — can I build on top of it?
Absolutely. The skill writes a documented, versioned **[machine contract](../ARCHITECTURE.md)** (event stream, control channel, structured JSON). Read those files to display, drive, or integrate audits into your own tools.

### How do I report a bug or contribute?
Open an issue or a pull request on the repository. Component-specific notes live in [`web/README.md`](../web/README.md), [`mac/README.md`](../mac/README.md), and [`skills/audit-report/SKILL.md`](../skills/audit-report/SKILL.md).
