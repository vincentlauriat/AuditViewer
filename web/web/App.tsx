import { useEffect, useMemo, useState } from "react";
import { useTheme } from "./useTheme.ts";
import type { Theme } from "./useTheme.ts";
import type {
  AuditData,
  AuditEvent,
  AuditSummary,
  Manifest,
  Recon,
  Source,
} from "../shared/contract.ts";
import { api, subscribeEvents } from "./api.ts";
import { Kpis } from "./components/Kpis.tsx";
import { Sources } from "./components/Sources.tsx";
import { Timeline } from "./components/Timeline.tsx";
import { Markdown } from "./components/Markdown.tsx";
import { Settings } from "./components/Settings.tsx";
import { NewAudit } from "./components/NewAudit.tsx";
import { QuestionModal } from "./components/QuestionModal.tsx";
import { ControlBar } from "./components/ControlBar.tsx";
import { Graph } from "./components/Graph.tsx";
import type { Question } from "../shared/contract.ts";

type Tab = "synthese" | "dimensions" | "sources" | "timeline" | "rapport" | "graphe";

const statusPill = (s?: string) =>
  s === "complete" ? "ok" : s === "canceled" ? "ko" : s === "partial" ? "warn" : "";

export function App() {
  const [audits, setAudits] = useState<AuditSummary[]>([]);
  const [slug, setSlug] = useState<string | null>(null);
  const [showSettings, setShowSettings] = useState(false);
  const [showNew, setShowNew] = useState(false);
  const [theme, setTheme] = useTheme();

  const reloadAudits = () =>
    api.audits().then((a) => {
      setAudits(a);
      setSlug((cur) => cur ?? (a.length ? a[0].slug : null));
    });

  useEffect(() => {
    reloadAudits();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div className="app">
      <aside className="sidebar">
        <h1 className="brand">
          <span className="brand-mark">◎</span> AuditViewer
        </h1>
        <button className="new-audit-btn" onClick={() => setShowNew(true)}>
          + Nouvel audit
        </button>
        <div className="sidebar-label">Audits</div>
        <ul className="audit-list">
          {audits.map((a) => (
            <li
              key={a.slug}
              className={a.slug === slug ? "active" : ""}
              onClick={() => setSlug(a.slug)}
            >
              <div className="al-subject">{a.subject}</div>
              <div className="al-meta">
                {a.subject_type ? <span className="al-type">{a.subject_type}</span> : null}
                {a.status ? <span className={`dot ${statusPill(a.status)}`} /> : null}
                {a.audit_date ? <span className="al-date">{a.audit_date}</span> : null}
              </div>
            </li>
          ))}
          {!audits.length ? <li className="empty">Aucun audit trouvé.</li> : null}
        </ul>
        <button className="settings-btn" onClick={() => setShowSettings(true)} title="Réglages">
          <span aria-hidden>⚙</span> Réglages
        </button>
        <div className="theme-row">
          {(["dark", "auto", "light"] as Theme[]).map(t => (
            <button key={t} className={`theme-btn${theme === t ? " active" : ""}`} onClick={() => setTheme(t)}>
              {t === "dark" ? "Sombre" : t === "light" ? "Clair" : "Auto"}
            </button>
          ))}
        </div>
      </aside>
      <main className="main">{slug ? <AuditView slug={slug} /> : <div className="empty">Sélectionnez un audit.</div>}</main>
      {showSettings ? (
        <Settings onClose={() => setShowSettings(false)} onSaved={reloadAudits} />
      ) : null}
      {showNew ? (
        <NewAudit
          onClose={() => setShowNew(false)}
          onLaunched={(s) => {
            setShowNew(false);
            setSlug(s);
            reloadAudits();
          }}
        />
      ) : null}
    </div>
  );
}

function AuditView({ slug }: { slug: string }) {
  const [manifest, setManifest] = useState<Manifest | null>(null);
  const [recon, setRecon] = useState<Recon | null>(null);
  const [files, setFiles] = useState<string[]>([]);
  const [data, setData] = useState<AuditData | null>(null);
  const [sources, setSources] = useState<Source[]>([]);
  const [events, setEvents] = useState<AuditEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<Tab>("synthese");
  const [question, setQuestion] = useState<Question | null>(null);
  const [focusDimFile, setFocusDimFile] = useState<string | undefined>();

  useEffect(() => {
    setManifest(null);
    setRecon(null);
    setFiles([]);
    setData(null);
    setSources([]);
    setEvents([]);
    setLoading(true);
    setTab("synthese");
    setQuestion(null);
    let cancelled = false;
    void (async () => {
      const [m, r, f, d, s, q] = await Promise.allSettled([
        api.manifest(slug),
        api.recon(slug),
        api.files(slug),
        api.data(slug),
        api.sources(slug),
        api.question(slug),
      ]);
      if (cancelled) return;
      if (m.status === "fulfilled") setManifest(m.value);
      if (r.status === "fulfilled") setRecon(r.value);
      if (f.status === "fulfilled") setFiles(f.value.files);
      if (d.status === "fulfilled") setData(d.value);
      if (s.status === "fulfilled") setSources(s.value.sources ?? []);
      if (q.status === "fulfilled" && !("question" in q.value)) setQuestion(q.value);
      setLoading(false);
    })();
    const unsub = subscribeEvents(slug, (ev) => {
      setEvents((prev) => [...prev, ev]);
      if (ev.type === "question") {
        api
          .question(slug)
          .then((q) => setQuestion("question" in q ? null : q))
          .catch(() => {});
      } else if (ev.type === "answer") {
        setQuestion(null);
      }
    });
    return () => {
      cancelled = true;
      unsub();
    };
  }, [slug]);

  // Modèle de vue unifié : manifest si présent, sinon synthèse depuis recon + fichiers.
  const mdFiles = files.filter((f) => /\.md$/i.test(f));
  const dimFiles =
    manifest?.dimensions?.map((d) => d.file) ??
    mdFiles.filter((f) => /^\d{2}_/.test(f) && !/^00_/.test(f)).sort();
  const summaryFile = files.find((f) => /^00_.*\.md$/i.test(f));
  const reportFile = manifest?.report_file ?? files.find((f) => /^RAPPORT_COMPLET\.md$/i.test(f));
  const subject = manifest?.subject ?? recon?.subject ?? slug;
  const subjectType = manifest?.subject_type ?? recon?.subject_type;
  const depth = manifest?.depth ?? recon?.depth;
  const auditDate = manifest?.audit_date ?? recon?.audit_date;
  const sourcesCount = manifest?.sources_count ?? recon?.sources_count ?? sources.length;
  const options = manifest?.options ?? [];

  const liveFinished = events.some(
    (e) => e.type === "audit_complete" || e.type === "audit_canceled",
  );
  const liveRunning = events.length > 0 && !liveFinished;
  const running = manifest
    ? manifest.status !== "complete" && manifest.status !== "canceled"
    : liveRunning;
  const status = manifest?.status ?? (liveRunning ? "en cours" : "archivé");

  const progress = useMemo(() => {
    const last = [...events].reverse().find((e) => e.type === "progress");
    if (last) return Number(last.pct) || 0;
    if (!running) return 100;
    return 0;
  }, [events, running]);

  if (loading) return <div className="empty">Chargement de l'audit…</div>;
  if (!manifest && !recon && !mdFiles.length && !events.length) {
    return <div className="empty">Audit vide ou illisible.</div>;
  }

  const showProgress = running || events.length > 0;

  return (
    <>
      <header className="audit-header">
        <div className="ah-top">
          <h2>{subject}</h2>
          <span className={`pill ${statusPill(manifest?.status)}`}>{running ? "en cours" : status}</span>
          {running ? <ControlBar slug={slug} /> : null}
        </div>
        <div className="ah-meta">
          {subjectType ? <span>{subjectType}</span> : null}
          {depth ? <span>profondeur : {depth}</span> : null}
          {manifest?.mode ? <span>mode : {manifest.mode}</span> : null}
          {auditDate ? <span>{auditDate}</span> : null}
          <span>{sourcesCount} sources</span>
          {options.length ? <span>options : {options.join(", ")}</span> : null}
          {!manifest ? <span className="legacy-tag">format legacy</span> : null}
        </div>
        {showProgress ? (
          <div className="progress">
            <div className="progress-bar" style={{ width: `${progress}%` }} />
            <span className="progress-label">{progress}%</span>
          </div>
        ) : null}
      </header>

      <nav className="tabs">
        {([
          ["synthese", "Synthèse"],
          ["dimensions", `Dimensions (${dimFiles.length})`],
          ["sources", `Sources (${sources.length})`],
          ["timeline", `Timeline (${events.length})`],
          ["rapport", "Rapport"],
          ["graphe", "Graphe"],
        ] as [Tab, string][]).map(([id, label]) => (
          <button key={id} className={tab === id ? "active" : ""} onClick={() => setTab(id)}>
            {label}
          </button>
        ))}
      </nav>

      <section className="content">
        {tab === "synthese" && (
          <>
            {data ? <Kpis data={data} sources={sources} /> : null}
            {summaryFile ? (
              <Markdown slug={slug} file={summaryFile} />
            ) : (
              <div className="empty">Pas de résumé exécutif.</div>
            )}
          </>
        )}
        {tab === "dimensions" && <Dimensions slug={slug} files={dimFiles} open={focusDimFile} />}
        {tab === "sources" && <Sources sources={sources} />}
        {tab === "timeline" && <Timeline events={events} />}
        {tab === "rapport" &&
          (reportFile ? (
            <Markdown slug={slug} file={reportFile} />
          ) : (
            <div className="empty">Pas de rapport complet.</div>
          ))}
        {tab === "graphe" && (
          <Graph
            manifest={manifest}
            sources={sources}
            dimFiles={dimFiles}
            subject={subject}
            onDimOpen={(key) => {
              const file =
                manifest?.dimensions?.find(d => d.key === key)?.file ??
                dimFiles.find(f => f.replace(/^\d+_/, "").replace(/\.md$/i, "").toLowerCase() === key);
              setFocusDimFile(file);
              setTab("dimensions");
            }}
          />
        )}
      </section>
      {question && running ? <QuestionModal slug={slug} question={question} /> : null}
    </>
  );
}

function Dimensions({ slug, files, open }: { slug: string; files: string[]; open?: string }) {
  const [active, setActive] = useState(files[0] ?? "");
  useEffect(() => setActive(files[0] ?? ""), [slug, files.join(",")]);
  useEffect(() => { if (open) setActive(open); }, [open]);
  if (!files.length) return <div className="empty">Aucune dimension.</div>;
  return (
    <div className="dimensions">
      <div className="dim-tabs">
        {files.map((f) => (
          <button key={f} className={f === active ? "active" : ""} onClick={() => setActive(f)}>
            {f.replace(/^\d+_/, "").replace(/\.md$/, "")}
          </button>
        ))}
      </div>
      {active ? <Markdown slug={slug} file={active} /> : null}
    </div>
  );
}
