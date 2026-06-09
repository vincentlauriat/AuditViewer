import { useEffect, useMemo, useState } from "react";
import type {
  AuditData,
  AuditEvent,
  AuditSummary,
  Manifest,
  Source,
} from "../shared/contract.ts";
import { api, subscribeEvents } from "./api.ts";
import { Kpis } from "./components/Kpis.tsx";
import { Sources } from "./components/Sources.tsx";
import { Timeline } from "./components/Timeline.tsx";
import { Markdown } from "./components/Markdown.tsx";
import { Settings } from "./components/Settings.tsx";

type Tab = "synthese" | "dimensions" | "sources" | "timeline" | "rapport";

const statusPill = (s?: string) =>
  s === "complete" ? "ok" : s === "canceled" ? "ko" : s === "partial" ? "warn" : "";

export function App() {
  const [audits, setAudits] = useState<AuditSummary[]>([]);
  const [slug, setSlug] = useState<string | null>(null);
  const [showSettings, setShowSettings] = useState(false);

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
      </aside>
      <main className="main">{slug ? <AuditView slug={slug} /> : <div className="empty">Sélectionnez un audit.</div>}</main>
      {showSettings ? (
        <Settings onClose={() => setShowSettings(false)} onSaved={reloadAudits} />
      ) : null}
    </div>
  );
}

function AuditView({ slug }: { slug: string }) {
  const [manifest, setManifest] = useState<Manifest | null>(null);
  const [data, setData] = useState<AuditData | null>(null);
  const [sources, setSources] = useState<Source[]>([]);
  const [events, setEvents] = useState<AuditEvent[]>([]);
  const [tab, setTab] = useState<Tab>("synthese");

  useEffect(() => {
    setManifest(null);
    setData(null);
    setSources([]);
    setEvents([]);
    setTab("synthese");
    api.manifest(slug).then(setManifest).catch(() => {});
    api.data(slug).then(setData).catch(() => {});
    api.sources(slug).then((s) => setSources(s.sources ?? [])).catch(() => {});
    const unsub = subscribeEvents(slug, (ev) => setEvents((prev) => [...prev, ev]));
    return unsub;
  }, [slug]);

  const progress = useMemo(() => {
    const last = [...events].reverse().find((e) => e.type === "progress");
    if (last) return Number(last.pct) || 0;
    if (manifest?.status === "complete") return 100;
    return 0;
  }, [events, manifest]);

  const running = manifest
    ? manifest.status !== "complete" && manifest.status !== "canceled"
    : !events.some((e) => e.type === "audit_complete" || e.type === "audit_canceled");

  const dimFiles =
    manifest?.dimensions?.map((d) => d.file) ??
    manifest?.files?.filter((f) => f.kind === "dimension").map((f) => f.name) ??
    [];

  if (!manifest) return <div className="empty">Chargement de l'audit…</div>;

  return (
    <>
      <header className="audit-header">
        <div className="ah-top">
          <h2>{manifest.subject}</h2>
          <span className={`pill ${statusPill(manifest.status)}`}>
            {running ? "en cours" : manifest.status}
          </span>
        </div>
        <div className="ah-meta">
          {manifest.subject_type ? <span>{manifest.subject_type}</span> : null}
          <span>profondeur : {manifest.depth}</span>
          <span>mode : {manifest.mode}</span>
          <span>{manifest.audit_date}</span>
          <span>{manifest.sources_count ?? sources.length} sources</span>
          {manifest.options?.length ? <span>options : {manifest.options.join(", ")}</span> : null}
        </div>
        <div className="progress">
          <div className="progress-bar" style={{ width: `${progress}%` }} />
          <span className="progress-label">{progress}%</span>
        </div>
      </header>

      <nav className="tabs">
        {([
          ["synthese", "Synthèse"],
          ["dimensions", "Dimensions"],
          ["sources", `Sources (${sources.length})`],
          ["timeline", `Timeline (${events.length})`],
          ["rapport", "Rapport"],
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
            <Markdown slug={slug} file="00_RESUME_EXECUTIF.md" />
          </>
        )}
        {tab === "dimensions" && <Dimensions slug={slug} files={dimFiles} />}
        {tab === "sources" && <Sources sources={sources} />}
        {tab === "timeline" && <Timeline events={events} />}
        {tab === "rapport" && <Markdown slug={slug} file={manifest.report_file ?? "RAPPORT_COMPLET.md"} />}
      </section>
    </>
  );
}

function Dimensions({ slug, files }: { slug: string; files: string[] }) {
  const [active, setActive] = useState(files[0] ?? "");
  useEffect(() => setActive(files[0] ?? ""), [slug, files.join(",")]);
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
