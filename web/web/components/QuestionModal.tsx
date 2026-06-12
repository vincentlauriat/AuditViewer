import { useState } from "react";
import type { Question } from "../../shared/contract.ts";
import { api } from "../api.ts";

/** Modale de question : affiche les options ; un clic poste la réponse. */
export function QuestionModal({
  slug,
  question,
}: {
  slug: string;
  question: Question;
}) {
  const [busy, setBusy] = useState<string | null>(null);
  const [free, setFree] = useState("");
  const [err, setErr] = useState<string | null>(null);

  const answer = async (value: string) => {
    setBusy(value);
    setErr(null);
    try {
      await api.answer(slug, value, question.id);
      // La modale disparaît à l'event SSE "answer" (géré par le parent).
    } catch (e) {
      setErr(e instanceof Error ? e.message : "Échec de l'envoi.");
      setBusy(null);
    }
  };

  const options = question.options ?? [];

  return (
    <div className="modal-backdrop">
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3 className="modal-title">Question de l'audit</h3>
        <p className="question-text">{question.text}</p>
        {options.length ? (
          <div className="question-options">
            {options.map((opt) => (
              <button
                key={opt}
                className="btn-option"
                disabled={busy !== null}
                onClick={() => answer(opt)}
              >
                {opt}
              </button>
            ))}
          </div>
        ) : (
          <div className="question-free">
            <input
              className="field-input"
              type="text"
              value={free}
              autoFocus
              onChange={(e) => setFree(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && free.trim() && answer(free.trim())}
              placeholder="Votre réponse…"
            />
            <button
              className="btn-primary"
              disabled={busy !== null || !free.trim()}
              onClick={() => answer(free.trim())}
            >
              Répondre
            </button>
          </div>
        )}
        {err ? <p className="field-msg ko">{err}</p> : null}
      </div>
    </div>
  );
}
