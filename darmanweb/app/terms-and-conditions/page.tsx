import type { Metadata } from "next";
import Link from "next/link";
import { Callout, LegalHero, LegalLayout, LegalSection, type TocItem } from "../_components/legal";
import { LEGAL_EFFECTIVE_DATE, SUPPORT_EMAIL } from "../lib/site";

export const metadata: Metadata = {
  title: "Terms & Conditions",
  description: "Terms governing patient and doctor use of Darman.",
};

const toc: TocItem[] = [
  { id: "acceptance", label: "Acceptance and eligibility" },
  { id: "accounts", label: "Accounts and verification" },
  { id: "platform", label: "Nature of the platform" },
  { id: "consultations", label: "Bookings and consultations" },
  { id: "payments", label: "Fees, wallet, and refunds" },
  { id: "communications", label: "Calls, chat, and content" },
  { id: "conduct", label: "Acceptable use" },
  { id: "privacy", label: "Privacy and permissions" },
  { id: "termination", label: "Suspension and deletion" },
  { id: "disclaimers", label: "Disclaimers and liability" },
  { id: "law", label: "Law and contact" },
];

export default function TermsPage() {
  return (
    <>
      <LegalHero
        label="Service agreement"
        title="Terms & Conditions"
        intro="These terms set the ground rules for using Darman as a patient or healthcare professional. Please read them before creating an account or booking a consultation."
        effectiveDate={LEGAL_EFFECTIVE_DATE}
      />
      <LegalLayout toc={toc}>
        <Callout tone="amber">
          <strong>Medical emergency?</strong> Darman is not an emergency or ambulance service. If you have severe symptoms or believe someone is in danger, contact local emergency services or visit the nearest emergency department now.
        </Callout>

        <LegalSection id="acceptance" title="1. Acceptance and eligibility">
          <p>Darman is a product of <strong>FindUs (Private) Limited</strong>. These Terms & Conditions form the agreement between you and FindUs (Private) Limited for using the Darman mobile application, website, and related services. By creating an account, accessing, or using Darman, you agree to these Terms and our <Link href="/privacy-policy">Privacy Policy</Link>. You can learn more about FindUs (Private) Limited at <a href="https://findus.com.pk" target="_blank" rel="noopener noreferrer">findus.com.pk</a>.</p>
          <p>You must be at least 18 years old, or the age of majority where you live, and legally capable of entering this agreement to create your own account. Darman is not directed at children. If you use Darman for a minor or dependent person, you confirm that you are their parent, legal guardian, or otherwise authorised to act for them and consent to relevant care and data processing on their behalf.</p>
          <p>If you do not agree, please do not use Darman. Additional terms disclosed for a particular feature, provider, or transaction also apply.</p>
        </LegalSection>

        <LegalSection id="accounts" title="2. Accounts and verification">
          <ul>
            <li>Provide accurate, complete, and current information and keep your registered phone number and profile up to date.</li>
            <li>Keep one-time passwords and account access secure. You are responsible for activity on your account unless you promptly report unauthorised access.</li>
            <li>Maintain one personal account unless Darman expressly permits otherwise. Do not impersonate another person or create an account using information you are not authorised to use.</li>
            <li>Darman may verify phone numbers, identity, professional credentials, licences, qualifications, and other information. Verification indicates that specified checks were completed; it is not a guarantee of a doctor&apos;s competence, outcome, or suitability for every patient.</li>
          </ul>
          <h3>Doctors</h3>
          <p>A doctor must hold all licences, registrations, qualifications, permissions, and insurance required to practise and provide each service offered through Darman. Doctors must keep credentials current, act within their competence and permitted jurisdiction, protect patient confidentiality, maintain required records, communicate fees clearly, and follow professional and legal standards.</p>
          <h3>Patients</h3>
          <p>Patients must provide information that is accurate and relevant to care, disclose allergies, medications, symptoms, and history when appropriate, follow reasonable consultation instructions, and seek in-person or emergency help when advised. Withholding important information may affect care.</p>
        </LegalSection>

        <LegalSection id="platform" title="3. Nature of the platform">
          <p>Darman provides technology for discovering healthcare professionals, requesting appointments, communicating, holding remote consultations, and managing related transactions. Healthcare professionals are independent providers responsible for clinical judgement, diagnosis, advice, treatment, prescriptions, referrals, follow-up, professional records, and regulatory compliance.</p>
          <p>Darman does not practise medicine, issue diagnoses, prescribe treatment, or guarantee a particular provider, response time, clinical result, or that remote care is suitable for every condition. Information in the app or on the website is general and is not a substitute for personalised medical advice.</p>
          <Callout>
            A doctor may decide that a remote consultation is insufficient and ask you to attend an in-person clinic, obtain tests, contact another provider, or seek urgent care.
          </Callout>
        </LegalSection>

        <LegalSection id="consultations" title="4. Bookings and consultations">
          <ul>
            <li>A booking request is not confirmed until the app shows confirmation. Availability and times may change.</li>
            <li>Join on time, use a safe and private setting, maintain a suitable internet connection, and ensure your camera or microphone works when needed.</li>
            <li>Doctors and patients should give reasonable notice when cancelling or rescheduling. Late attendance, no-shows, or technical failures may affect completion or refund eligibility.</li>
            <li>Do not record, photograph, stream, publish, or share a consultation without the prior consent of everyone involved and compliance with applicable law.</li>
            <li>Prescriptions, medical certificates, or referrals are issued only when the healthcare professional considers them clinically appropriate and legally permitted.</li>
          </ul>
          <p>In case of a technical failure, contact support promptly with the booking reference and relevant details, but do not email unnecessary medical information.</p>
        </LegalSection>

        <LegalSection id="payments" title="5. Fees, wallet, cancellations, and refunds">
          <p>Prices, provider fees, taxes, and any service charges shown before confirmation form part of the transaction. You authorise Darman and its payment providers to process the selected payment and any disclosed wallet reservation. Keep payment and wallet activity lawful and funded.</p>
          <p>Cancellation, no-show, and refund eligibility may depend on the timing of cancellation, consultation status, provider actions, technical evidence, applicable law, and any policy shown at checkout. Approved refunds may return to the original payment method or Darman wallet and can take time to appear due to payment-provider processing.</p>
          <p>Wallet value is for permitted Darman transactions, is not a bank account, does not earn interest, and is not transferable or redeemable for cash except where Darman states otherwise or applicable law requires. Errors, duplicate charges, or unauthorised transactions should be reported promptly.</p>
        </LegalSection>

        <LegalSection id="communications" title="6. Calls, chat, reviews, and user content">
          <p>You retain ownership of content you submit. You grant Darman a limited, non-exclusive licence to host, store, reproduce, transmit, display, and process that content only as needed to operate, secure, support, and improve the Services and comply with law.</p>
          <p>You are responsible for having the right to upload or share content. Do not share another person&apos;s medical records, images, identity documents, or private communications without lawful authority. Reviews must reflect genuine experiences and must not include threats, discrimination, confidential medical details, manipulated ratings, or false statements.</p>
          <p>Darman may moderate, restrict, preserve, or remove content; limit communication; and investigate reports when reasonably necessary for safety, legal compliance, or enforcement. Users should use available report or block features and contact support about abuse. Darman may notify authorities when required or when there is a credible safety risk.</p>
        </LegalSection>

        <LegalSection id="conduct" title="7. Acceptable use">
          <p>You must not:</p>
          <ul>
            <li>harass, threaten, exploit, discriminate against, deceive, or endanger another person;</li>
            <li>submit unlawful, sexually exploitative, hateful, violent, fraudulent, infringing, or malicious content;</li>
            <li>seek controlled medicines, false documents, fraudulent refunds, or services for an unlawful purpose;</li>
            <li>interfere with calls, security, authentication, infrastructure, or another user&apos;s account;</li>
            <li>scrape data, reverse engineer protected parts of the Services, introduce malware, automate abusive access, or bypass technical restrictions;</li>
            <li>use Darman to provide healthcare without required credentials or outside permitted scope or jurisdiction; or</li>
            <li>use confidential or personal information obtained through Darman for advertising, solicitation, stalking, or any purpose unrelated to legitimate care.</li>
          </ul>
        </LegalSection>

        <LegalSection id="privacy" title="8. Privacy, security, and device permissions">
          <p>Our <Link href="/privacy-policy">Privacy Policy</Link> explains how information is collected, used, shared, retained, and deleted. You authorise processing necessary to operate the features you choose. Camera, microphone, notifications, photos, files, and Bluetooth audio permissions are optional at the device level, but related features may not work if permission is denied.</p>
          <p>Keep sensitive health discussions private, verify the identity of the intended recipient before sending information, and notify support if you suspect unauthorised access or an incorrectly addressed message.</p>
        </LegalSection>

        <LegalSection id="termination" title="9. Suspension, termination, and account deletion">
          <p>You may stop using Darman at any time and may request deletion through the <Link href="/delete-account">account-deletion page</Link>. Deleting the app alone does not cancel bookings or delete your account.</p>
          <p>Darman may warn, restrict, suspend, or terminate access when reasonably necessary to protect users, investigate fraud or credential issues, comply with law, address non-payment, respond to prolonged inactivity, or enforce these Terms. Where appropriate, we will give notice and an opportunity to respond. Serious safety, fraud, or legal risks may require immediate action.</p>
          <p>Terms concerning payments owed, intellectual property, privacy, records, disclaimers, liability, disputes, and other provisions that logically continue will survive termination.</p>
        </LegalSection>

        <LegalSection id="disclaimers" title="10. Availability, disclaimers, and liability">
          <p>The Services are provided on an “as available” basis. To the extent permitted by law, Darman disclaims implied warranties of uninterrupted availability, error-free operation, fitness for a particular medical purpose, and outcomes from independent healthcare services. Temporary interruption may result from connectivity, maintenance, provider systems, emergencies, or events beyond reasonable control.</p>
          <p>Nothing in these Terms excludes rights or liability that cannot legally be excluded, including liability for fraud, wilful misconduct, or death or personal injury where exclusion is prohibited. Subject to those limits, Darman is not responsible for indirect, incidental, special, punitive, or consequential losses, lost data or profit, or independent clinical decisions. Any monetary limitation will be applied only to the extent lawful and fair in the circumstances.</p>
          <p>You remain responsible for your own unlawful conduct and may be required to reimburse reasonable losses arising from your material violation of these Terms, infringement of another person&apos;s rights, or misuse of the Services, to the extent permitted by law.</p>
        </LegalSection>

        <LegalSection id="law" title="11. Changes, governing law, and contact">
          <p>We may update these Terms to reflect changes in the Services, law, safety requirements, or business operations. The effective date identifies the latest version. Material changes will receive appropriate notice, and continued use after they take effect means you accept the revised Terms where permitted by law.</p>
          <p>These Terms are governed by the laws of Pakistan, without limiting mandatory consumer or privacy rights that apply to you. Parties should first try to resolve a dispute through support. Any unresolved dispute will be handled by a court with lawful jurisdiction, unless applicable law requires another process.</p>
          <p>Questions or notices may be sent to <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>. If one part of these Terms is unenforceable, the remaining parts continue. Failure to enforce a provision once is not a waiver. You may not transfer your account or agreement without permission; Darman may transfer the agreement as part of a legitimate business reorganisation with continued protection of your rights.</p>
        </LegalSection>
      </LegalLayout>
    </>
  );
}