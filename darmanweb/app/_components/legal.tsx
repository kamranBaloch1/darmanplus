import type { ReactNode } from "react";

export type TocItem = { id: string; label: string };

export function LegalHero({ label, title, intro, effectiveDate }: {
  label: string;
  title: string;
  intro: string;
  effectiveDate: string;
}) {
  return (
    <section className="legal-hero">
      <div className="page-width legal-hero-inner">
        <div className="eyebrow light"><span /> {label}</div>
        <h1>{title}</h1>
        <p>{intro}</p>
        <div className="effective-date"><span>Effective date</span><strong>{effectiveDate}</strong></div>
      </div>
    </section>
  );
}

export function LegalLayout({ toc, children }: { toc: TocItem[]; children: ReactNode }) {
  return (
    <div className="page-width legal-layout">
      <aside className="toc" aria-label="On this page">
        <span>On this page</span>
        <ol>{toc.map((item) => <li key={item.id}><a href={`#${item.id}`}>{item.label}</a></li>)}</ol>
      </aside>
      <article className="legal-content">{children}</article>
    </div>
  );
}

export function LegalSection({ id, title, children }: { id: string; title: string; children: ReactNode }) {
  return <section id={id} className="legal-section"><h2>{title}</h2>{children}</section>;
}

export function Callout({ children, tone = "blue" }: { children: ReactNode; tone?: "blue" | "amber" | "green" }) {
  return <div className={`callout callout-${tone}`}>{children}</div>;
}
