# Use cases

AuditViewer is useful any time you need to understand something *thoroughly and quickly*. Here are concrete scenarios, grouped by who you are.

---

## For decision-makers & analysts

### Due diligence before an investment
You're considering backing — or buying shares in — a company. Before the meeting, you want the full picture: how it makes money, who it competes with, whether the financials hold up.

```bash
/audit-report "Mistral AI" --depth full --swot
```

You get history, market sizing, technology, financials, a competitive map, and a dedicated SWOT — each figure sourced and dated. What used to be two days of desk research becomes a coffee break.

### Competitive monitoring
You need to keep tabs on a rival's moves, pricing changes, and roadmap.

```bash
/audit-report "Figma" --focus pricing --watch
```

The `--watch` option adds a curated "sources to watch" list so you can keep following the story after the audit. Re-running the audit later produces a **changelog** of what moved.

### Market study
You're entering — or sizing — a new market.

```bash
/audit-report "the European EV charging market" --depth full
```

Market size (TAM/SAM/SOM), growth rates, regulation, geography, and the main players, assembled into one briefing.

---

## For curious non-experts

### Understand a company you're about to join
Got a job interview? Walk in informed.

```bash
/audit-report "Datadog" --rh
```

The `--rh` option adds an HR & culture chapter (headcount trends, Glassdoor sentiment, hiring direction) on top of the standard business picture — exactly what you'd want to know before signing.

### Make a confident purchase decision
Choosing a tool, a car, a service? Get the unbiased lay of the land.

```bash
/audit-report "Tesla Model Y" --depth quick
```

A fast pass that maps the product, its pricing, and its alternatives — without the marketing gloss.

### Just learn about something properly
A technology, a trend, an industry you keep hearing about.

```bash
/audit-report "retrieval-augmented generation"
```

A structured primer that goes well beyond a single search, with sources you can follow to go deeper.

---

## For developers & contributors

### Build your own viewer or automation
The skill emits a documented, versioned **[machine contract](../ARCHITECTURE.md)**: a live event stream, a control channel, and structured JSON outputs. Anything that reads those files can display or drive an audit — dashboards, Slack bots, CI pipelines, your own UI.

### Integrate audits into a product
Launch audits headlessly (the web backend already does this with `claude -p`), follow progress through the event stream, and consume the structured `_data.json` / `_sources.json` to feed your own database or report templates.

### Run it where you work
Claude Code, Gemini, or any assistant that can map the generic tool concepts the skill describes. The contract is identical across platforms — only the execution engine changes.

---

## A pattern worth knowing: keep audits fresh

Because each audit lives in its own folder and records how it was made, you can **re-run it weeks later** on the same subject. The skill detects the existing audit and offers to *update* it — producing a `CHANGELOG.md` that tells you exactly what changed since last time. Great for quarterly reviews or tracking a fast-moving competitor.

---

Need a hand getting started? → [Getting started](getting-started.md) · [FAQ](faq.md)
