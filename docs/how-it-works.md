# How it works

A plain-language tour of what happens between *"`/audit-report Tesla`"* and *"here's your dossier."* No code, no jargon — and where a technical term is unavoidable, it links to the [glossary](glossary.md).

---

## The big idea

Think of AuditViewer as **a junior research analyst that never gets tired.** You give it a subject; it does the same disciplined legwork a good analyst would — search broadly, read the important sources, write down where each fact came from, double-check the critical numbers — and hands you a clean, structured report.

The difference from asking a chatbot "tell me about Tesla" is **method and proof.** A chatbot answers from memory and can blur fact with guesswork. AuditViewer searches the live web, **sources every figure with a link and a date**, labels how reliable each source is, and refuses to invent numbers it can't find.

---

## The seven dimensions

A real audit looks at a subject from several angles. AuditViewer always covers these seven (a "quick" audit covers the first four):

| Dimension | The question it answers |
|---|---|
| **History** | Where did this come from, and what shaped it? |
| **Market** | How big is the field, who's in it, where is it growing? |
| **Technology** | What is it actually, and what makes it different? |
| **Pricing** | How does it make money, and how does that compare? |
| **Competition** | Who else is in the race, and who's winning? |
| **Financials** | Is it healthy — revenue, funding, valuation? |
| **Outlook** | Where is this heading, and what could go wrong? |

You can add **SWOT**, **ESG / sustainability**, and **HR & culture** chapters on demand.

---

## The five stages of an audit

### 1. Reconnaissance
Before any deep work, the AI runs a few broad searches to *frame* the subject: is "Jaguar" the car maker or the animal? Is "Notion" the software, or something else? It identifies the type of subject, the key players, and the right vocabulary for later searches.

### 2. Confirmation (you stay in control)
It then shows you what it understood and **asks before spending real effort**: *Launch the research, adjust the focus, or cancel?* This checkpoint means you never waste a long run on a misunderstood topic.

### 3. Research, dimension by dimension
For each dimension, the AI runs targeted searches, reads the best sources, and writes that chapter. As it works it follows strict **quality rules**:

- Every figure carries a **source link and a publication date**.
- Sources are tagged **[Official]**, **[Analyst]**, or **[Press]** so you can judge reliability at a glance.
- Anything older than a year is flagged ⚠️.
- It never fabricates: if a number isn't public, it says so.

Depending on your assistant, these chapters are researched **in parallel** (several "sub-analysts" at once, faster) or **one at a time** (more cross-referenced). You don't have to choose — it picks a sensible default.

### 4. Fact-checking
A dedicated pass pulls the 5–10 most important numbers (revenue, valuation, market share…) and re-verifies each against **at least two independent sources**. Contradictions are surfaced explicitly rather than quietly averaged away.

### 5. Assembly
Finally it writes the one-page **executive summary**, merges every chapter into a single shareable **full report**, and de-duplicates the source list so each reference appears once.

---

## Why you can trust the numbers

Trust comes from process, and the process is deliberately strict:

- **Sourced or it doesn't ship.** Each quantitative claim links to where it came from.
- **Reliability is visible.** The Official / Analyst / Press tags let you weigh a claim yourself.
- **Freshness is visible.** Stale data is marked, not hidden.
- **Estimates are labelled.** A guess is never dressed up as a fact.
- **Key numbers are cross-checked.** The figures that matter most get a second and third opinion.

This is the same discipline a consulting team applies — encoded as rules the AI must follow on every run.

---

## The three apps, one shared language

You can read an audit as plain files. But the **web viewer** and **macOS app** add live progress, comfortable reading, and a map of how audits relate.

They all understand the same thing because the skill writes its output as a **machine contract** — a small, stable set of files with a fixed structure:

- a live **event stream** so a viewer can show progress in real time;
- a **control channel** so a viewer can pause, resume, cancel, or re-run a chapter;
- a **question/answer** exchange so the AI can ask you something mid-run through the UI;
- and **structured summaries** (the manifest, the key figures, the source index) that any tool can read.

Because this contract is documented and versioned, anyone can build their own viewer or automation on top of it. The full specification is in **[ARCHITECTURE.md](../ARCHITECTURE.md)** — that one is for developers.

---

## Works with Claude and Gemini

The engine adapts to your assistant:

- **Claude Code** can spin up several research sub-agents at once — fast, parallel audits.
- **Gemini** (and similar) runs everything in a single large context — the skill detects this automatically and switches to "solo" mode, so you get the same report either way.

---

Next: see it applied to real situations → **[Use cases](use-cases.md)**.
