import { useState } from "react";
import type { ControlAction } from "../../shared/contract.ts";
import { api } from "../api.ts";

/** Barre de contrôle d'un audit en cours : Pause / Reprendre / Annuler. */
export function ControlBar({ slug }: { slug: string }) {
  const [paused, setPaused] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const send = async (action: ControlAction) => {
    setBusy(true);
    setErr(null);
    try {
      await api.control(slug, action);
      if (action === "pause") setPaused(true);
      if (action === "resume") setPaused(false);
    } catch (e) {
      setErr(e instanceof Error ? e.message : "Échec.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="control-bar">
      {paused ? (
        <button className="btn-ghost" disabled={busy} onClick={() => send("resume")}>
          ▶ Reprendre
        </button>
      ) : (
        <button className="btn-ghost" disabled={busy} onClick={() => send("pause")}>
          ⏸ Pause
        </button>
      )}
      <button className="btn-danger" disabled={busy} onClick={() => send("cancel")}>
        ⏹ Annuler
      </button>
      {err ? <span className="field-msg ko">{err}</span> : null}
    </div>
  );
}
