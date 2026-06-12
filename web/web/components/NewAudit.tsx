import { useState } from "react";
import type { LaunchRequest } from "../../shared/contract.ts";
import { api } from "../api.ts";

/** Modale « Nouvel audit » : formulaire → POST /launch → sélection du slug créé. */
export function NewAudit({
  onClose,
  onLaunched,
}: {
  onClose: () => void;
  onLaunched: (slug: string) => void;
}) {
  const [subject, setSubject] = useState("");
  const [depth, setDepth] = useState<"full" | "quick">("full");
  const [mode, setMode] = useState<"parallel" | "sequential" | "solo">("parallel");
  const [options, setOptions] = useState<Record<string, boolean>>({
    swot: false,
    esg: false,
    rh: false,
  });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const toggle = (k: string) => setOptions((o) => ({ ...o, [k]: !o[k] }));

  const submit = async () => {
    if (!subject.trim()) return;
    setBusy(true);
    setErr(null);
    const req: LaunchRequest = {
      subject: subject.trim(),
      depth,
      mode,
      options: Object.keys(options).filter((k) => options[k]),
    };
    try {
      const { slug } = await api.launch(req);
      onLaunched(slug);
    } catch (e) {
      setErr(e instanceof Error ? e.message : "Échec du lancement.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3 className="modal-title">Nouvel audit</h3>

        <label className="field-label" htmlFor="na-subject">
          Sujet
        </label>
        <input
          id="na-subject"
          className="field-input"
          type="text"
          value={subject}
          autoFocus
          onChange={(e) => setSubject(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && submit()}
          placeholder="Ex : Tesla Model Y"
        />

        <div className="field-row">
          <div>
            <label className="field-label" htmlFor="na-depth">
              Profondeur
            </label>
            <select
              id="na-depth"
              className="field-input"
              value={depth}
              onChange={(e) => setDepth(e.target.value as "full" | "quick")}
            >
              <option value="full">full</option>
              <option value="quick">quick</option>
            </select>
          </div>
          <div>
            <label className="field-label" htmlFor="na-mode">
              Mode
            </label>
            <select
              id="na-mode"
              className="field-input"
              value={mode}
              onChange={(e) =>
                setMode(e.target.value as "parallel" | "sequential" | "solo")
              }
            >
              <option value="parallel">parallel</option>
              <option value="sequential">sequential</option>
              <option value="solo">solo</option>
            </select>
          </div>
        </div>

        <div className="field-checks">
          {(["swot", "esg", "rh"] as const).map((k) => (
            <label key={k} className="check">
              <input type="checkbox" checked={options[k]} onChange={() => toggle(k)} />
              {k.toUpperCase()}
            </label>
          ))}
        </div>

        {err ? <p className="field-msg ko">{err}</p> : null}

        <div className="modal-actions">
          <button className="btn-ghost" onClick={onClose}>
            Annuler
          </button>
          <button className="btn-primary" disabled={busy || !subject.trim()} onClick={submit}>
            {busy ? "Lancement…" : "Lancer l'audit"}
          </button>
        </div>
      </div>
    </div>
  );
}
