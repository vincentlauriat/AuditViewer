# Glossary

Plain-language definitions of every term you might meet in this project. Sorted alphabetically.

---

**Audit** — Here, a complete research dossier on one subject: a folder of documents covering history, market, technology, pricing, competition, financials, and outlook. Not a financial/accounting audit in the strict sense — closer to what a consulting firm calls a "deep dive."

**Audit folder** — The output of one run, e.g. `audit-tesla/`. It holds the report chapters (Markdown) and a few structured data files. You own it entirely; it's just files on your disk.

**Bonjour** — Apple's zero-configuration networking technology for finding services on a local network without typing addresses. The Apple TV viewer uses it to discover the Mac that's sharing audits, so it can connect automatically.

**Claude Code** — Anthropic's AI assistant for the terminal and editors. The recommended environment to run the `audit-report` skill. <https://claude.com/claude-code>

**Depth (`--depth`)** — How thorough the research is. `quick` = faster, ~10 sources, 4 dimensions. `full` = the default, ~30+ sources, 7 dimensions.

**Dimension** — One angle of analysis. The seven standard dimensions are History, Market, Technology, Pricing, Competition, Financials, and Outlook. Optional ones: ESG, HR.

**ESG** — Environmental, Social, and Governance. A lens for assessing a company's sustainability and ethics (carbon footprint, board governance, controversies). Added with `--esg`.

**Executive summary** — The one-page overview at the front of every audit (`00_RESUME_EXECUTIF.md`): key facts, headline figures, and a verdict. Read this first.

**Fact-check** — A verification pass that re-checks the most important numbers against at least two independent sources and flags contradictions. Produces `_factcheck.md`.

**Gemini** — Google's AI assistant. Supported via "solo" mode; install with `./install.sh --gemini`.

**Local network** — Your home or office Wi-Fi/wired network. The Apple TV (tvOS) viewer reads audits over the local network from the Mac that shares them — the data never leaves your network and never touches the cloud.

**Machine contract** — The fixed, versioned structure the skill uses for its output, so the viewers (and any other tool) can read and drive audits reliably. Includes the event stream, control channel, and structured JSON files. Full spec in [ARCHITECTURE.md](../ARCHITECTURE.md). Developer-facing — you never edit these by hand.

**Manifest (`_manifest.json`)** — A small index file listing everything an audit produced and its final status. The "table of contents" the apps read to understand an audit.

**Markdown (`.md`)** — A simple text format for documents. Opens in any editor, on GitHub, or in a Markdown reader. All audit chapters are Markdown.

**Mode (`--mode`)** — How the research is executed. `parallel` = several research sub-agents at once (fastest). `sequential` = one at a time (more cross-referenced). `solo` = no sub-agents, one continuous run (used automatically on Gemini).

**Node.js** — The runtime needed to run the web viewer. Free download at <https://nodejs.org/>.

**Reconnaissance** — The quick first pass where the AI frames your subject before deep research, and confirms the scope with you. Recorded in `_recon.json`.

**Skill** — A packaged command for an AI assistant. `audit-report` is the skill that powers everything here; you trigger it with `/audit-report`.

**Slug** — A simplified, file-safe version of your subject used to name the folder. "Société Générale" becomes `societe-generale`. Computed the same way every time so tools can predict it.

**Source tag** — A label on each source indicating reliability: **[Official]** (filings, press releases, IR pages), **[Analyst]** (research firms), **[Press]** (media).

**SSE (Server-Sent Events)** — The technical mechanism the web viewer uses to receive live updates while an audit runs. You don't interact with it directly; it's why progress appears in real time.

**Stale data** — Information older than a year, flagged with ⚠️ so you know to treat it with caution.

**SWOT** — Strengths, Weaknesses, Opportunities, Threats: a classic strategy framework. Added as a dedicated chapter with `--swot`.

**TAM / SAM / SOM** — Three ways to size a market. **TAM** (Total Addressable Market) = the whole pie. **SAM** (Serviceable Available Market) = the slice you could realistically serve. **SOM** (Serviceable Obtainable Market) = the slice you could realistically win. Standard vocabulary in market analysis.

**Verbose (`--verbose`)** — An option that shows every search and source as the audit runs, instead of just the final result.

**Viewer** — One of the optional apps for reading and running audits: the **web viewer** (browser), the **macOS app** (native Mac), the **iOS / iPadOS reader** (iPhone & iPad) and the **Apple TV (tvOS) viewer** (big screen, reads over the local network). All are optional — audits are readable as plain files without them.
