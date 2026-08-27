import type { Metadata } from "next";
import { SUPPORT_EMAIL } from "../lib/site";

export const metadata: Metadata = {
  title: "Delete Account",
  description: "Request deletion of a Darman patient or doctor account.",
};

const deletionSubject = encodeURIComponent("Darman account deletion request");
const deletionBody = encodeURIComponent(
  "Hello Darman Support,\n\nI want to permanently delete my Darman account.\n\nFull name:\nRegistered phone number:\nAccount type (Patient or Doctor):\n\nI understand that account deletion is permanent."
);

const steps = [
  {
    number: "01",
    title: "We verify your account",
    body: "Darman may contact your registered phone number or email to confirm that you own the account.",
  },
  {
    number: "02",
    title: "We process the deletion",
    body: "Verified requests are completed within 30 days. Your login access, profile details, notification tokens, and eligible uploaded content are deleted.",
  },
  {
    number: "03",
    title: "Required records may remain",
    body: "Some consultation, payment, fraud-prevention, dispute, or medical records may be retained where the law requires it, then deleted or anonymised once that requirement ends.",
  },
];

export default function DeleteAccountPage() {
  const deletionEmail = `mailto:${SUPPORT_EMAIL}?subject=${deletionSubject}&body=${deletionBody}`;

  return (
    <section className="page-width simple-delete-page">
      <div className="simple-delete-heading">
        <div className="eyebrow danger"><span /> Account deletion</div>
        <h1>Delete your Darman account</h1>
        <p>
          To permanently delete your patient or doctor account, send a request from the email below.
        </p>
      </div>

      <div className="delete-email-card">
        <h2>Email us to delete your account</h2>
        <p>Please include:</p>
        <ul>
          <li>Your full name</li>
          <li>Your registered phone number</li>
          <li>Account type — Patient or Doctor</li>
        </ul>
        <a className="button button-danger" href={deletionEmail}>
          Email {SUPPORT_EMAIL} <span aria-hidden="true">→</span>
        </a>
       
      </div>

      <div className="simple-delete-info">
        {steps.map((step) => (
          <article key={step.number}>
            <span>{step.number}</span>
            <div>
              <h2>{step.title}</h2>
              <p>{step.body}</p>
            </div>
          </article>
        ))}
      </div>

      <div className="simple-delete-note">
        <strong>Important:</strong> deleting the Darman app from your phone does not delete your account or your data. You must send the deletion request above.
      </div>
    </section>
  );
}