import { useEffect, useState } from "react";
import type { AppConfig } from "../../shared/contract.ts";
import { api } from "../api.ts";

/** Modale de réglages : configure le répertoire racine des audits (lecture + écriture). */
export function Settings({
  onClose,
  onSaved,
}: {
  onClose: () => void;
  onSaved: () => void;
}) {
  const [config, setConfig] = useState<AppConfig | null>(null);
  const [value, setValue] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ kind: "ok" | "ko"; text: string } | null>(null);

  useEffect(() => {
    api
      .config()
      .then((c) => {
        setConfig(c);
        setValue(c.auditsRoot);
      })
      .catch(() => setMsg({ kind: "ko", text: "Config illisible." }));
  }, []);

  const save = async () => {
    setBusy(true);
    setMsg(null);
    try {
      const c = await api.setConfig(value.trim());
      setConfig(c);
      setValue(c.auditsRoot);
      setMsg({ kind: "ok", text: "Enregistré." });
      onSaved();
    } catch (e) {
      setMsg({ kind: "ko", text: e instanceof Error ? e.message : "Échec." });
    } finally {
      setBusy(false);
    }
  };

  const editable = config?.editable ?? false;

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3 className="modal-title">Réglages</h3>
        <label className="field-label" htmlFor="auditsRoot">
          Répertoire des audits
        </label>
        <input
          id="auditsRoot"
          className="field-input"
          type="text"
          value={value}
          readOnly={!editable}
          disabled={!editable}
          onChange={(e) => setValue(e.target.value)}
          placeholder="/chemin/absolu/vers/les/audits"
        />
        {config && !editable ? (
          <p className="field-hint">Imposé par AUDITS_ROOT (variable d'environnement).</p>
        ) : (
          <p className="field-hint">
            Ce dossier sert à la fois à lire les audits et à écrire les nouveaux.
          </p>
        )}
        {msg ? <p className={`field-msg ${msg.kind}`}>{msg.text}</p> : null}
        <div className="modal-actions">
          <button className="btn-ghost" onClick={onClose}>
            Fermer
          </button>
          {editable ? (
            <button className="btn-primary" disabled={busy || !value.trim()} onClick={save}>
              {busy ? "…" : "Enregistrer"}
            </button>
          ) : null}
        </div>
      </div>
    </div>
  );
}
