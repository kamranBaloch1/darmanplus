
import type { Metadata } from "next";
import Link from "next/link";
import { Callout, LegalHero, LegalLayout, LegalSection, type TocItem } from "../_components/legal";
import { LEGAL_EFFECTIVE_DATE, SUPPORT_EMAIL } from "../lib/site";

export const metadata: Metadata = {
  title: "Refund & Cancellation Policy",
  description:
    "Darman's policy for consultation cancellations, wallet payments, refunds, failed payments, and doctor consultation charges.",
};

const toc: TocItem[] = [
  { id: "scope", label: "Scope and who we are" },
  { id: "payments", label: "How payments work" },
  { id: "wallet", label: "Patient wallet" },
  { id: "cancellations", label: "Consultation cancellations" },
  { id: "doctor-cancellations", label: "Doctor cancellations" },
  { id: "no-show", label: "Missed consultations" },
  { id: "refunds", label: "Refunds" },
  { id: "failed-payments", label: "Failed or duplicate payments" },
  { id: "refund-process", label: "Refund request process" },
  { id: "doctor-wallet", label: "Doctor wallet" },
  { id: "non-refundable", label: "Non-refundable situations" },
  { id: "disputes", label: "Payment disputes" },
  { id: "changes", label: "Changes and contact" },
];


export default function RefundPolicyPage() {
  return (
    <>
      <LegalHero
        label="Payments & refunds"
        title="Refund & Cancellation Policy"
        intro="This policy explains how consultation cancellations, wallet payments, refunds, failed transactions, and doctor consultation charges are handled on Darman."
        effectiveDate={LEGAL_EFFECTIVE_DATE}
      />

      <LegalLayout toc={toc}>
        <Callout tone="green">
          <strong>Our approach.</strong> Darman aims to make consultation payments
          and refunds clear and fair. Patient payments are handled through the
          Darman wallet, while consultation earnings are credited to the
          applicable doctor's Darman wallet after a completed consultation.
        </Callout>

        <LegalSection id="scope" title="1. Scope and who we are">
          <p>
            Darman is a product of <strong>FindUs (Private) Limited</strong>.
            This Refund & Cancellation Policy applies to the Darman mobile
            application, website, patient accounts, doctor accounts,
            consultations, wallet transactions, and related payment and
            support services.
          </p>

          <p>
            FindUs (Private) Limited operates Darman and is responsible for the
            Darman platform and the payment and wallet functionality described
            in this policy.
          </p>

          <p>
            This policy applies only to Darman services. Other products or
            services operated by FindUs (Private) Limited may have separate
            payment, cancellation, and refund policies.
          </p>
        </LegalSection>

        <LegalSection id="payments" title="2. How payments work">
          <p>
            Patients may add funds to their Darman wallet using the payment
            methods made available through Darman. Wallet funds may then be
            used to pay for eligible doctor consultations booked through the
            platform.
          </p>

          <p>
            When a consultation is completed, the applicable consultation
            amount may be deducted from the patient's available wallet balance
            and credited to the doctor's Darman wallet, subject to the
            applicable platform rules, transaction status, and any applicable
            adjustments.
          </p>

          <p>
            Darman does not treat a wallet top-up as payment for a particular
            doctor or consultation until the funds are used for an eligible
            transaction.
          </p>

          <p>
            Consultation fees are displayed or communicated before the
            consultation is confirmed where the relevant information is
            available.
          </p>
        </LegalSection>

        <LegalSection id="wallet" title="3. Patient wallet">
          <p>
            The Darman patient wallet is an in-app balance used for eligible
            Darman payments. Wallet funds are separate from your bank account
            or payment card and are recorded in Darman's transaction system.
          </p>

          <p>
            A wallet top-up increases the available balance in your Darman
            account. It does not by itself create a consultation booking or
            guarantee that a particular doctor will be available.
          </p>

          <p>
            You are responsible for reviewing your wallet balance and
            transaction history and for reporting any transaction that appears
            incorrect, duplicated, unauthorised, or incomplete.
          </p>

          <p>
            Darman may restrict wallet activity where reasonably necessary to
            prevent fraud, abuse, unauthorised transactions, chargebacks,
            security incidents, or violations of the Terms.
          </p>
        </LegalSection>

        <LegalSection id="cancellations" title="4. Patient consultation cancellations">
          <p>
            Patients may cancel a consultation where the cancellation option
            is available in Darman.
          </p>

          <p>
            Whether a cancelled consultation is eligible for a refund or
            wallet reversal may depend on when the cancellation occurs and
            whether the consultation has already started or been completed.
          </p>

          <p>
            If a consultation is cancelled before the doctor has started the
            consultation and the applicable cancellation conditions are met,
            Darman may return the applicable amount to the patient's Darman
            wallet.
          </p>

          <p>
            Once a consultation has started, cancellation may not qualify for
            a refund unless Darman determines that a refund is appropriate
            based on the circumstances.
          </p>

          <p>
            Darman may apply reasonable cancellation rules to protect doctors
            from repeated or late cancellations while maintaining appropriate
            protections for patients.
          </p>
        </LegalSection>

        <LegalSection id="doctor-cancellations" title="5. Doctor cancellations">
          <p>
            Doctors are expected to attend and conduct consultations that they
            have accepted and scheduled through Darman.
          </p>

          <p>
            If a doctor cancels a consultation before it takes place, or is
            unable to provide the consultation for a reason attributable to the
            doctor, Darman may return the applicable consultation amount to
            the patient's Darman wallet.
          </p>

          <p>
            Where appropriate, Darman may also take action under its doctor
            terms, including reviewing the doctor's availability, account
            status, or eligibility to receive future consultation requests.
          </p>

          <p>
            A doctor cancellation does not normally result in a patient losing
            the consultation amount when the consultation was not provided.
          </p>
        </LegalSection>

        <LegalSection id="no-show" title="6. Missed consultations">
          <p>
            Patients and doctors are expected to be available at the agreed
            consultation time and to use the Darman application or the
            applicable communication method provided for the consultation.
          </p>

          <p>
            If a patient does not attend or cannot be reached for a scheduled
            consultation, the consultation may be treated as a missed
            consultation and may not automatically qualify for a refund.
          </p>

          <p>
            If a doctor does not attend or cannot be reached, the patient
            should report the issue to Darman as soon as reasonably possible.
            Darman may review the consultation records and determine whether
            the consultation amount should be returned to the patient wallet.
          </p>

          <p>
            Exceptional circumstances may be considered individually.
          </p>
        </LegalSection>

        <LegalSection id="refunds" title="7. Refunds">
          <p>
            Where Darman determines that a refund is appropriate, the refund
            will generally be credited to the patient's Darman wallet unless
            another refund method is required or approved.
          </p>

          <p>
            Refunds may be considered for situations such as a doctor
            cancelling a consultation, a consultation not being provided due
            to a technical or platform issue, an incorrect consultation
            charge, or another verified payment or service issue.
          </p>

          <p>
            A refund is not guaranteed merely because a patient is dissatisfied
            with a consultation. Darman may review the circumstances,
            consultation status, relevant communications, and available
            transaction records before making a decision.
          </p>

          <p>
            Where a consultation was properly provided by the doctor, the
            consultation charge will generally not be refundable solely because
            the patient disagrees with the doctor's professional opinion,
            diagnosis, recommendation, or treatment.
          </p>

          <p>
            Darman does not control the professional medical judgment of
            doctors. Concerns about medical advice should be raised through
            the appropriate support or professional channels where applicable.
          </p>
        </LegalSection>

        <LegalSection id="failed-payments" title="8. Failed or duplicate payments">
          <p>
            If a wallet top-up or other payment appears to have failed but
            money was deducted from the patient's bank account or payment
            method, the patient should first allow the payment provider's
            normal processing or reversal period to complete.
          </p>

          <p>
            If the amount does not appear in the Darman wallet or is not
            automatically reversed within the applicable period, contact
            Darman support with the transaction details.
          </p>

          <p>
            If a payment appears to have been charged more than once for the
            same transaction, Darman may review the transaction records and,
            where a duplicate charge is confirmed, return the applicable
            amount to the patient's Darman wallet or through another
            appropriate refund method.
          </p>

          <p>
            Payment providers may apply their own processing, settlement, or
            reversal timelines. Darman may need to coordinate with the
            applicable payment provider before resolving a disputed
            transaction.
          </p>
        </LegalSection>

        <LegalSection id="refund-process" title="9. Refund request process">
          <p>
            To request assistance with a refund, cancellation, wallet
            transaction, or consultation payment, contact Darman at{" "}
            <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>.
          </p>

          <p>
            Please include the phone number registered to your Darman account,
            consultation or booking details, transaction date, amount, doctor
            information where relevant, and a clear description of the issue.
          </p>

          <p>
            You may also be asked to provide transaction references, payment
            confirmation, screenshots, or other information reasonably needed
            to investigate the request.
          </p>

          <p>
            Never send your password, one-time verification code, full card
            number, CVV, or other account-access credentials when submitting a
            support request.
          </p>

          <p>
            Darman may verify account ownership before processing a refund or
            changing wallet-related information.
          </p>
        </LegalSection>

        <LegalSection id="doctor-wallet" title="10. Doctor wallet">
          <p>
            Doctor wallets are separate from patient wallets. Amounts
            attributable to completed consultations may be credited to the
            doctor's Darman wallet according to the applicable consultation
            and platform rules.
          </p>

          <p>
            Doctor wallet balances may be subject to adjustments resulting
            from refunds, reversals, disputed transactions, fraud reviews,
            incorrect credits, or other legitimate account corrections.
          </p>

          <p>
            Doctors may request withdrawal of an eligible wallet balance using
            the withdrawal method made available by Darman, subject to
            applicable verification, account status, transaction review, and
            withdrawal requirements.
          </p>

          <p>
            Darman may delay or restrict a withdrawal where reasonably
            necessary to investigate a disputed transaction, suspected fraud,
            security issue, incorrect credit, or legal or compliance
            requirement.
          </p>
        </LegalSection>

        <LegalSection id="non-refundable" title="11. Non-refundable situations">
          <p>
            A refund may not be available where:
          </p>

          <ul>
            <li>
              the consultation was completed and the service was provided as
              booked;
            </li>
            <li>
              the patient voluntarily cancels after the consultation has
              started;
            </li>
            <li>
              the patient misses a scheduled consultation without an eligible
              cancellation reason;
            </li>
            <li>
              the request is based only on dissatisfaction with a doctor's
              professional opinion or medical recommendation;
            </li>
            <li>
              the claimed payment or consultation issue cannot reasonably be
              verified;
            </li>
            <li>
              the transaction has already been appropriately refunded or
              reversed; or
            </li>
            <li>
              the refund request is otherwise excluded by applicable terms or
              law.
            </li>
          </ul>

          <p>
            These situations do not limit any rights or remedies that cannot
            legally be excluded under applicable law.
          </p>
        </LegalSection>

        <LegalSection id="disputes" title="12. Payment disputes">
          <p>
            If you believe that a wallet transaction, consultation charge,
            refund, or withdrawal is incorrect, contact Darman promptly so we
            can review the relevant records.
          </p>

          <p>
            Darman may review wallet activity, consultation status, booking
            records, payment-provider information, communications, and other
            relevant records when investigating a dispute.
          </p>

          <p>
            Where a payment provider, bank, or other financial institution is
            involved, resolution may also depend on that provider's
            processing and dispute procedures.
          </p>

          <p>
            Nothing in this policy limits any rights or remedies available to
            patients, doctors, or other users under applicable law.
          </p>
        </LegalSection>

        <LegalSection id="changes" title="13. Changes and contact">
          <p>
            We may update this Refund & Cancellation Policy when our Services,
            payment arrangements, wallet functionality, doctor policies, or
            legal obligations change.
          </p>

          <p>
            The effective date at the top of this page shows the latest
            revision. If a material change affects how refunds or payments are
            handled, we will provide appropriate notice through the Darman
            application, website, or other appropriate communication channel.
          </p>

          <p>
            Questions, complaints, and refund requests can be sent to{" "}
            <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>.
          </p>

          <p>
            For account-security reasons, never include your password or
            one-time verification code in a support request.
          </p>
        </LegalSection>
      </LegalLayout>
    </>
  );
}

