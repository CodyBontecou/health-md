import { forwardRef, useEffect, useId, useRef, type ButtonHTMLAttributes, type ReactNode } from "react";
import { createPortal } from "react-dom";

export function SafeText({ children }: { children: string }): ReactNode {
  return <span>{children}</span>;
}

export const Button = forwardRef<HTMLButtonElement, ButtonHTMLAttributes<HTMLButtonElement>>(function Button(props, ref) {
  return <button ref={ref} {...props} className={["button", props.className].filter(Boolean).join(" ")} />;
});

export function StatusBadge({ children }: { children: string }): ReactNode {
  return <span className="status-badge"><SafeText>{children.replaceAll("_", " ")}</SafeText></span>;
}

export function Notice({ title, children, tone = "neutral", role }: { title: string; children: ReactNode; tone?: "neutral" | "attention"; role?: "alert" | "status" }): ReactNode {
  return <section className={`notice notice-${tone}`} role={role} aria-labelledby={`${slug(title)}-notice`}><h2 id={`${slug(title)}-notice`} className="notice-title">{title}</h2><div>{children}</div></section>;
}

export function StatePanel({ state, title, children }: { state: "loading" | "empty" | "error" | "denied" | "stale"; title: string; children?: ReactNode }): ReactNode {
  return <Notice title={title} tone={state === "error" || state === "stale" ? "attention" : "neutral"} role={state === "error" ? "alert" : "status"}><p>{children ?? stateCopy[state]}</p></Notice>;
}

export interface FieldError { field: string; code: string; message?: string }
export function ErrorSummary({ errors }: { errors: readonly FieldError[] }): ReactNode {
  const summary = useRef<HTMLElement>(null);
  useEffect(() => { if (errors.length > 0) summary.current?.focus(); }, [errors]);
  if (errors.length === 0) return null;
  return <section ref={summary} className="error-summary" role="alert" aria-labelledby="error-summary-title" tabIndex={-1}><h2 id="error-summary-title">Resolve these blocking issues</h2><ul>{errors.map((error, index) => <li key={`${error.field}-${error.code}-${index}`}><a href={`#${fieldId(error.field)}`} onClick={event => { event.preventDefault(); document.getElementById(fieldId(error.field))?.focus(); }}>{error.message ?? validationMessage(error.code)} <span className="code">({error.code})</span></a></li>)}</ul></section>;
}

export function TextField({ name, label, value, onChange, error, hint, maxLength, type = "text" }: { name: string; label: string; value: string; onChange: (value: string) => void; error?: string | undefined; hint?: string; maxLength?: number; type?: "text" | "date" | "time" | "number" }): ReactNode {
  const id = fieldId(name); const hintId = `${id}-hint`; const errorId = `${id}-error`;
  return <div className="field"><label htmlFor={id}>{label}</label>{hint ? <span id={hintId} className="hint">{hint}</span> : null}<input id={id} name={name} type={type} value={value} maxLength={maxLength} aria-invalid={Boolean(error)} aria-describedby={[hint ? hintId : "", error ? errorId : ""].filter(Boolean).join(" ") || undefined} onChange={event => onChange(event.currentTarget.value)} />{error ? <span id={errorId} className="field-error">{error}</span> : null}</div>;
}

export function SelectField({ name, label, value, onChange, options, hint }: { name: string; label: string; value: string; onChange: (value: string) => void; options: readonly { value: string; label: string }[]; hint?: string }): ReactNode {
  const id = fieldId(name);
  return <div className="field"><label htmlFor={id}>{label}</label>{hint ? <span id={`${id}-hint`} className="hint">{hint}</span> : null}<select id={id} value={value} aria-describedby={hint ? `${id}-hint` : undefined} onChange={event => onChange(event.currentTarget.value)}>{options.map(option => <option key={option.value} value={option.value}>{option.label}</option>)}</select></div>;
}

export function RadioGroup({ name, label, value, onChange, options, hint }: { name: string; label: string; value: string; onChange: (value: string) => void; options: readonly { value: string; label: string }[]; hint?: string }): ReactNode {
  const legendId = `${fieldId(name)}-legend`;
  return <fieldset id={fieldId(name)} tabIndex={-1} className="field"><legend id={legendId}>{label}</legend>{hint ? <p className="hint">{hint}</p> : null}<div className="radio-list">{options.map(option => <label key={option.value}><input type="radio" name={name} value={option.value} checked={value === option.value} onChange={() => onChange(option.value)} /> {option.label}</label>)}</div></fieldset>;
}

export function DataTable({ caption, headers, rows }: { caption: string; headers: readonly string[]; rows: readonly (readonly ReactNode[])[] }): ReactNode {
  return <div className="table-wrap" tabIndex={0} role="region" aria-label={caption}><table><caption>{caption}</caption><thead><tr>{headers.map(header => <th scope="col" key={header}>{header}</th>)}</tr></thead><tbody>{rows.map((row, index) => <tr key={index}>{row.map((cell, cellIndex) => cellIndex === 0 ? <th scope="row" key={cellIndex}>{cell}</th> : <td key={cellIndex}>{cell}</td>)}</tr>)}</tbody></table></div>;
}

export function ConfirmationDialog({ open, title, confirmLabel, onConfirm, onCancel, children, returnFocus }: { open: boolean; title: string; confirmLabel: string; onConfirm: () => void; onCancel: () => void; children: ReactNode; returnFocus?: HTMLElement | null }): ReactNode {
  const backdrop = useRef<HTMLDivElement>(null); const panel = useRef<HTMLDivElement>(null); const heading = useId();
  const cancelRef = useRef(onCancel); cancelRef.current = onCancel;
  const confirmRef = useRef(onConfirm); confirmRef.current = onConfirm;
  useEffect(() => {
    if (!open) return;
    const previous = returnFocus ?? document.activeElement as HTMLElement | null;
    const backgrounds = [...document.body.children].filter(element => element !== backdrop.current);
    const priorState = backgrounds.map(element => ({ hidden: element.getAttribute("aria-hidden"), inertAttribute: element.hasAttribute("inert"), inertProperty: (element as HTMLElement).inert }));
    backgrounds.forEach(element => { element.setAttribute("aria-hidden", "true"); element.setAttribute("inert", ""); (element as HTMLElement).inert = true; });
    panel.current?.querySelector<HTMLElement>("button, [href], input, select, textarea, [tabindex]:not([tabindex='-1'])")?.focus();
    const keydown = (event: KeyboardEvent) => {
      if (event.key === "Escape") { event.preventDefault(); cancelRef.current(); return; }
      if (event.key !== "Tab") return;
      const focusable = [...(panel.current?.querySelectorAll<HTMLElement>("button:not(:disabled), [href], input:not(:disabled), select:not(:disabled), textarea:not(:disabled), [tabindex]:not([tabindex='-1'])") ?? [])];
      if (focusable.length === 0) { event.preventDefault(); return; }
      const first = focusable[0]!; const last = focusable.at(-1)!;
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    };
    document.addEventListener("keydown", keydown);
    return () => {
      document.removeEventListener("keydown", keydown);
      backgrounds.forEach((element, index) => { const prior = priorState[index]!; (element as HTMLElement).inert = prior.inertProperty; if (prior.inertAttribute) element.setAttribute("inert", ""); else element.removeAttribute("inert"); if (prior.hidden == null) element.removeAttribute("aria-hidden"); else element.setAttribute("aria-hidden", prior.hidden); });
      previous?.focus();
    };
  }, [open, returnFocus]);
  if (!open) return null;
  return createPortal(<div ref={backdrop} className="dialog-backdrop" data-modal-portal="true"><div ref={panel} className="dialog" role="dialog" aria-modal="true" aria-labelledby={heading}><h2 id={heading}>{title}</h2>{children}<div className="button-row"><Button onClick={() => cancelRef.current()}>Keep current state</Button><Button className="button-primary" onClick={() => confirmRef.current()}>{confirmLabel}</Button></div></div></div>, document.body);
}

export function Pagination({ page, hasNext, onPrevious, onNext }: { page: number; hasNext: boolean; onPrevious: () => void; onNext: () => void }): ReactNode {
  return <nav className="pagination" aria-label="Pagination"><Button disabled={page === 1} onClick={onPrevious}>Previous page</Button><span aria-live="polite">Page {page}</span><Button disabled={!hasNext} onClick={onNext}>Next page</Button></nav>;
}

export function LiveRegion({ message }: { message: string }): ReactNode { return <div className="visually-hidden" aria-live="polite" aria-atomic="true">{message}</div>; }
export function PrintOnly({ children }: { children: ReactNode }): ReactNode { return <div className="print-only">{children}</div>; }
export function ScreenOnly({ children }: { children: ReactNode }): ReactNode { return <div className="screen-only">{children}</div>; }

export function fieldId(field: string): string { const target = field === "period.timezoneRule" ? "period" : field; return `field-${target.replace(/[^a-z0-9_-]+/gi, "-")}`; }
function slug(value: string): string { return value.toLowerCase().replace(/[^a-z0-9]+/g, "-"); }
function validationMessage(code: string): string {
  const messages: Record<string, string> = {
    fixed_period_invalid: "Enter a valid start date before the exclusive end date.", relative_days_invalid: "Enter a positive whole number of completed days.", finite_fixed_bounds_required: "This context requires explicit finite fixed dates.", window_cardinality_invalid: "Provide the exact number of named windows for this schedule.", window_overlap: "Named windows must not overlap.", window_count_invalid: "Minimum count must be a positive whole number.", relative_acceptance_unresolved: "Relative dates remain unresolved until patient acceptance; issuance is blocked.", dst_materialization_unresolved: "DST window materialization is not approved; issuance is blocked.", cadence_anchor_unresolved: "This cadence anchor is unresolved in the draft contract; issuance is blocked.", overnight_window_unresolved: "Overnight windows are unresolved; issuance is blocked.", touching_window_unresolved: "Touching window endpoints are unresolved; issuance is blocked.", html_not_allowed: "HTML is not allowed in plain-text instructions.", markdown_not_allowed: "Markdown is not allowed in plain-text instructions.", link_not_allowed: "Links are not allowed in instructions.", stale_revision: "The record changed. Refresh before trying again.",
  };
  return messages[code] ?? "The server rejected this field. Review it before continuing.";
}
const stateCopy = { loading: "Loading synthetic content…", empty: "No synthetic records match this view.", error: "The synthetic operation could not be completed.", denied: "This capability is not available for the signed-in role.", stale: "The server record changed. Refresh before continuing." } as const;
