import type { AuditData, Source } from "../../shared/contract.ts";

export function Kpis({ data, sources }: { data: AuditData; sources: Source[] }) {
  const byId = new Map(sources.map((s) => [s.id, s]));
  if (!data.kpis?.length) return <div className="empty">Aucun KPI structuré.</div>;
  return (
    <div className="kpi-grid">
      {data.kpis.map((k) => {
        const src = k.source_id != null ? byId.get(k.source_id) : undefined;
        return (
          <div className="kpi-card" key={k.key}>
            <div className="kpi-value">
              {k.value ?? "—"}
              {k.unit ? <span className="kpi-unit"> {k.unit}</span> : null}
            </div>
            <div className="kpi-label">{k.label}</div>
            <div className="kpi-meta">
              {k.period ? <span className="kpi-period">{k.period}</span> : null}
              {k.estimated ? <span className="tag tag-est">estimé</span> : <span className="tag tag-off">officiel</span>}
            </div>
            {src ? (
              <a className="kpi-src" href={src.url} target="_blank" rel="noreferrer" title={src.title}>
                ↗ {src.tag}
              </a>
            ) : null}
          </div>
        );
      })}
    </div>
  );
}
