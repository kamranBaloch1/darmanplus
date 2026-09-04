import Link from "next/link";

const cards = [
  {
    title: "Privacy Policy",
    description: "Understand what information Darman collects, why it is used, how it is protected, and the choices available to you.",
    href: "/privacy-policy",
    label: "Read privacy policy",
  },
  {
    title: "Terms & Conditions",
    description: "Review the rules for patient and doctor accounts, consultations, payments, communications, and responsible platform use.",
    href: "/terms-and-conditions",
    label: "Read terms",
  },
  {
    title: "Delete your account",
    description: "Start an account-deletion request, see what will be deleted, and understand which records may need to be retained.",
    href: "/delete-account",
    label: "Start deletion request",
  },
];

export default function Home() {
  return (
    <>
      <section className="page-width home-hero-inner">
        <h1>Darman legal centre</h1>
        <p>Find Darman&apos;s privacy policy, terms of service, and account-deletion information here.</p>
        <div className="hero-actions">
          <Link className="button button-primary" href="/privacy-policy">Read privacy policy</Link>
          <Link className="button button-secondary" href="/delete-account">Delete an account</Link>
        </div>
      </section>

      <section className="page-width legal-hub" aria-labelledby="legal-resources">
        <h2 id="legal-resources">Legal resources</h2>
        <div className="resource-grid">
          {cards.map((card) => (
            <article className="resource-card" key={card.href}>
              <h3>{card.title}</h3>
              <p>{card.description}</p>
              <Link href={card.href}>{card.label} →</Link>
            </article>
          ))}
        </div>
      </section>
    </>
  );
}