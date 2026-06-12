import type { AuditEvent } from "../../shared/contract.ts";

const ICON: Record<string, string> = {
  audit_start: "▶",
  phase_start: "◆",
  phase_done: "◇",
  dimension_start: "○",
  dimension_done: "●",
  progress: "▭",
  file_written: "✎",
  question: "?",
  answer: "↩",
  error: "✕",
  audit_complete: "✔",
  audit_canceled: "⊘",
};

const fmt = (ts: string) => (ts.length >= 19 ? ts.slice(11, 19) : ts);

export function Timeline({ events }: { events: AuditEvent[] }) {
  if (!events.length) return <div className="empty">Aucun événement.</div>;
  return (
    <ol className="timeline">
      {events.map((e, i) => {
        const detail = Object.entries(e)
          .filter(([k]) => !["v", "ts", "type"].includes(k))
          .map(([k, val]) => `${k}=${String(val)}`)
          .join("  ");
        return (
          <li key={i} className={`tl-${e.type}`}>
            <span className="tl-time">{fmt(e.ts)}</span>
            <span className="tl-icon">{ICON[e.type] ?? "·"}</span>
            <span className="tl-type">{e.type}</span>
            <span className="tl-detail">{detail}</span>
          </li>
        );
      })}
    </ol>
  );
}
