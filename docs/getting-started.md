# Getting started

This guide takes you from zero to your first finished audit. **No technical background required.** If a word looks unfamiliar, check the [glossary](glossary.md).

---

## What you'll need

AuditViewer's engine runs *inside* an AI assistant. You need **one** of these:

- **[Claude Code](https://claude.com/claude-code)** — recommended, supports every feature.
- **Gemini** (Google's AI coding assistant) — supported in "solo" mode.

That's the only hard requirement. The web viewer, the Mac app, the iOS/iPadOS reader and the Apple TV (tvOS) viewer are **optional** ways to read your audits more comfortably — you can skip them at first.

---

## Step 1 — Install the audit engine

Download (or clone) this project, open a terminal in its folder, and run:

```bash
./install.sh
```

That's it. This tells your AI assistant about the new `/audit-report` command. Using Gemini instead? Run `./install.sh --gemini`.

To check it worked, open your assistant and type:

```bash
/audit-report --help
```

You should see a help screen listing the options.

---

## Step 2 — Run your first audit

Pick any subject — a company, a product, a market, a technology — and ask for it:

```bash
/audit-report Notion
```

Here's what happens, and what you'll see:

1. **Reconnaissance.** The AI does a few quick searches to understand your topic (Is "Notion" the software company? Which market? Which competitors?).
2. **Confirmation.** It shows you what it found and asks: *"Shall I launch the full research?"* This is your chance to redirect it before it spends time. Choose **Launch**.
3. **Research.** It investigates each angle — history, market, technology, pricing, competition, financials, outlook — gathering and dating sources as it goes.
4. **Fact-check.** It re-verifies the most important numbers against independent sources and flags any contradictions.
5. **Assembly.** It writes the executive summary and merges everything into a single full report.

When it's done, you'll have a new folder named `audit-notion/` containing all the documents.

> **Tip — go faster or deeper:**
> - `/audit-report Notion --depth quick` — a lighter, faster pass (~10 sources).
> - `/audit-report Notion --depth full` — the thorough default (~30+ sources).
> - `/audit-report Notion --brief` — just a one-page brief, nothing else.

---

## Step 3 — Read the result

Open the `audit-notion/` folder. Start with **`00_RESUME_EXECUTIF.md`** (the executive summary) for the one-page overview, then dive into any chapter that interests you. **`RAPPORT_COMPLET.md`** is the full report, ready to share or print.

Every Markdown file (`.md`) opens in any text editor, on GitHub, or in a Markdown reader. But the viewers below make it nicer.

---

## Step 4 (optional) — Use the viewers

### Web viewer — read and launch audits in your browser

If you have [Node.js](https://nodejs.org/) installed:

```bash
cd web
npm install
npm run dev
```

Open **http://localhost:5173**. You can browse your audits, watch one run **live**, answer the AI's questions, and even start a new audit from a form — no terminal needed after this.

Just want to see what it looks like, with sample data included in the project?


### macOS app — a native reading experience

On a Mac (macOS 15+) with the Swift toolchain:

```bash
cd mac
./build.sh
open build/AuditViewer.app
```

The Mac app adds a rich Markdown view and an **Obsidian-style map** that shows how your audits connect through shared sources and people.

### iOS / iPadOS reader — your audits on the go

A native **read-only** app for iPhone & iPad. Build it from source (iOS 17+, Xcode + [XcodeGen](https://github.com/yonaskolb/XcodeGen)):

```bash
cd mac
xcodegen generate
xcodebuild -scheme AuditViewerIOS -destination 'generic/platform=iOS Simulator' build
```

On first launch, tap **Choose the Research folder…** and pick your `Research` folder in the **Files** app (iCloud Drive or "On My iPhone"). The app remembers it and lets you browse each audit's summary, dimensions, sources and full report.

### Apple TV (tvOS) viewer — your audits on the big screen

A native **read-only** app for Apple TV, made for showing an audit on a large screen during a meeting or boardroom presentation. The Apple TV can't store files or reach iCloud Drive, so it reads your audits **over the local network**: the Mac app shares its `Research` folder, and the Apple TV discovers it automatically.

Build it from source (tvOS 17+, Xcode + [XcodeGen](https://github.com/yonaskolb/XcodeGen)):

```bash
cd mac
./tvos/build.sh
```

This builds and runs the `AuditViewerTVOS` target in the tvOS Simulator. To run it on a real Apple TV paired to Xcode over Wi-Fi, pass its device UDID:

```bash
./tvos/build.sh <UDID>
```

To make audits appear on the TV, two things must be on:

1. **On the Mac:** open the app's settings and turn on **Share on the local network** (off by default). A status indicator confirms sharing is active.
2. **On the Apple TV:** on first launch, allow **Local Network** access when prompted. The viewer then discovers the Mac automatically and — if there's only one — connects to it, letting you browse each audit's summary, dimensions, sources and full report with the Siri Remote.

Everything stays on your local network; nothing goes to the cloud.

---

## Common options at a glance

| You want… | Add this |
|---|---|
| The report in French | `--lang fr` |
| A faster, lighter audit | `--depth quick` |
| Just a one-page brief | `--brief` |
| A dedicated SWOT analysis | `--swot` |
| An ESG / sustainability chapter | `--esg` |
| An HR & culture chapter | `--rh` |
| A "sources to watch" section | `--watch` |
| To see every search live | `--verbose` |

Combine them freely, e.g. `/audit-report "Mistral AI" --depth full --swot --verbose`.

---

## Where to go next

- Curious *why* the reports are trustworthy? → [How it works](how-it-works.md)
- Want ideas for your own situation? → [Use cases](use-cases.md)
- Stuck on something? → [FAQ](faq.md)
