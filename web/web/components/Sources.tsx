import type { Source } from "../../shared/contract.ts";

const tagClass: Record<string, string> = {
  Officielle: "src-off",
  Analyste: "src-ana",
  Presse: "src-press",
};

export function Sources({ sources }: { sources: Source[] }) {
  if (!sources.length) return <div className="empty">Aucune source structurée.</div>;
  return (
    <table className="sources">
      <thead>
        <tr>
          <th>#</th>
          <th>Source</th>
          <th>Type</th>
          <th>Date</th>
          <th>Dimensions</th>
        </tr>
      </thead>
      <tbody>
        {sources.map((s) => (
          <tr key={s.id} className={s.stale ? "stale" : ""}>
            <td className="num">{s.id}</td>
            <td>
              <a href={s.url} target="_blank" rel="noreferrer">
                {s.title}
              </a>
            </td>
            <td>
              <span className={`src-tag ${tagClass[s.tag] ?? ""}`}>{s.tag}</span>
            </td>
            <td className="nowrap">
              {s.date ?? "—"}
              {s.stale ? <span title="Donnée de plus d'un an"> ⚠️</span> : null}
            </td>
            <td className="dims">{s.dimensions?.join(", ")}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
