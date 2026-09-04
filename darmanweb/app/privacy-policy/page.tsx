import type { Metadata } from "next";
import Link from "next/link";
import { Callout, LegalHero, LegalLayout, LegalSection, type TocItem } from "../_components/legal";
import { LEGAL_EFFECTIVE_DATE, SUPPORT_EMAIL } from "../lib/site";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: "How Darman collects, uses, shares, protects, retains, and deletes personal and health information.",
};

const toc: TocItem[] = [
  { id: "scope", label: "Scope" },
  { id: "overview", label: "Data safety overview" },
  { id: "information", label: "Information we collect" },
  { id: "use", label: "How we use information" },
  { id: "sharing", label: "How we share information" },
  { id: "permissions", label: "Device permissions" },
  { id: "retention", label: "Retention and deletion" },
  { id: "security", label: "Security and international transfers" },
  { id: "choices", label: "Your rights and choices" },
  { id: "children", label: "Children and dependent patients" },
  { id: "changes", label: "Changes and contact" },
];

export default function PrivacyPolicyPage() {
  return (
    <>
      <LegalHero
        label="Your information"
        title="Privacy Policy"
        intro="This policy explains what Darman collects, how we use and protect it, when it may be shared, and how you can control, export, or delete your information."
        effectiveDate={LEGAL_EFFECTIVE_DATE}
      />
      <LegalLayout toc={toc}>
        <Callout tone="green">
          <strong>Our commitment.</strong> Darman does not sell personal or health information, does not share it for cross-context behavioral advertising, and does not use it to serve targeted ads. We collect only what is needed to provide and secure our healthcare services, and we give you clear controls to access, export, or delete your data.
        </Callout>

        <LegalSection id="scope" title="1. Scope and who we are">
          <p>Darman is a product of <strong>FindUs (Private) Limited</strong>. This Privacy Policy applies to the Darman mobile application, this website, and related patient, doctor, consultation, communication, and support services. FindUs (Private) Limited operates these services and is who we're referring to throughout this policy.</p>
          <p>You can learn more about FindUs (Private) Limited at <a href="https://findus.com.pk" target="_blank" rel="noopener noreferrer">findus.com.pk</a>.</p>
          <p>Darman connects patients with healthcare professionals. While we verify doctor credentials before they appear on Darman, the professional advice, diagnosis, and treatment a doctor provides are their own responsibility, and doctors remain subject to any additional legal duties that apply to medical records and patient confidentiality in their profession.</p>
        </LegalSection>

        <LegalSection id="overview" title="2. Data safety overview">
          <p>Health-related information is sensitive. Here is a short summary before the full details below:</p>
          <div className="definition-grid">
            <div><strong>What we collect</strong><p>Account details, doctor verification data, booking and consultation content, communications and media you send, payment records, and basic device/usage data.</p></div>
            <div><strong>Why</strong><p>To operate accounts, verify doctors, run bookings and consultations, process payments, provide support, and keep the Services safe and reliable.</p></div>
            <div><strong>Who it's shared with</strong><p>The doctor or patient in your consultation, service providers who help us run the Services, and parties required by law — never sold, and never shared for ad targeting.</p></div>
            <div><strong>Encryption</strong><p>Data is encrypted in transit. Sensitive data is encrypted at rest where our infrastructure providers support it.</p></div>
            <div><strong>Your control</strong><p>You can request access, correction, export, or deletion of your data at any time. See “Your rights and choices” below.</p></div>
            <div><strong>Advertising</strong><p>We do not use an advertising ID, and we do not build advertising profiles from your health or account data.</p></div>
          </div>
        </LegalSection>

        <LegalSection id="information" title="3. Information we collect">
          <h3>Information you provide</h3>
          <ul>
            <li><strong>Account and identity data:</strong> phone number, one-time-password verification, name, email where provided, account role, gender, date of birth, and profile image.</li>
            <li><strong>Doctor profile and verification data:</strong> professional title, specialization, qualifications, licence or registration number, experience, consultation fee, biography, introduction media, identity or credential documents, verification status, availability, ratings, and reviews.</li>
            <li><strong>Consultation and booking data (sensitive health information):</strong> doctor and patient details, appointment date and time, booking status, consultation notes or information you choose to share, and service history. Treat this as health information under applicable law; we apply additional care to how it is stored, accessed, and shared.</li>
            <li><strong>Communications and media:</strong> chat messages, images, videos, voice messages, files, call metadata, reports, reviews, and support correspondence. Audio or video calls are transmitted to enable the consultation; Darman does not intentionally record call content unless users are clearly notified and any required consent is obtained.</li>
            <li><strong>Payment and wallet data:</strong> consultation charges, wallet balances, reserved amounts, refunds, and transaction records. Payment providers may collect payment credentials directly under their own policies; Darman does not store full card numbers.</li>
          </ul>
          <h3>Information collected automatically</h3>
          <ul>
            <li><strong>Device and app data:</strong> device identifiers, push-notification tokens, operating system, app version, language, IP address, timestamps, diagnostic logs, crash information, and security events.</li>
            <li><strong>Usage data:</strong> screens or features used, account activity, booking and call events, and interactions needed to operate, secure, and improve the Services.</li>
          </ul>
          <p>We collect camera, microphone, photo, video, or file data only when you use a feature that needs it or grant the relevant permission. Darman does not access contacts, precise location, SMS, or call-log data, and does not use an advertising identifier.</p>
        </LegalSection>

        <LegalSection id="use" title="4. How we use information">
          <p>We process information as necessary to provide the Services, with your consent where required, for legitimate safety and operational purposes, and to meet legal obligations. Uses include:</p>
          <ul>
            <li>creating, authenticating, and managing patient and doctor accounts;</li>
            <li>reviewing doctor credentials and showing verified professional profiles;</li>
            <li>matching users, scheduling consultations, enabling calls and chat, and delivering notifications;</li>
            <li>processing charges, wallet activity, refunds, and financial reconciliation;</li>
            <li>providing customer support and handling account-deletion, privacy, safety, and dispute requests;</li>
            <li>preventing fraud, impersonation, harassment, abuse, security incidents, and violations of our Terms;</li>
            <li>maintaining, diagnosing, measuring, and improving the reliability and accessibility of Darman; and</li>
            <li>complying with professional, tax, accounting, court, regulatory, and other lawful requirements.</li>
          </ul>
          <p>We do not use consultation notes, medical, or health information for advertising, and we do not build advertising or marketing profiles from it. We will ask for permission before using sensitive information for a materially different purpose where the law requires it.</p>
        </LegalSection>

        <LegalSection id="sharing" title="5. How we share information">
          <p>We share only what is reasonably necessary, and we never sell personal or health information. Categories of recipients:</p>
          <ul>
            <li><strong>Between patients and doctors:</strong> profile, booking, consultation, availability, rating, and communication information needed to arrange and deliver care.</li>
            <li><strong>Service providers (processors):</strong> infrastructure, authentication, storage, notifications, calls, messaging, verification, diagnostics, support, and payment services. Current technology providers may include Supabase, Google Firebase, Agora, and Twilio. They may only use information to provide these services to us and process it under contractual confidentiality and security obligations.</li>
            <li><strong>Safety and legal compliance:</strong> authorities, courts, regulators, professional bodies, or affected parties when reasonably necessary to comply with law, protect life or safety, investigate misconduct, enforce our Terms, or defend legal rights.</li>
            <li><strong>Business changes:</strong> a successor or adviser in connection with a merger, financing, reorganisation, or sale, subject to appropriate confidentiality and continued protection.</li>
            <li><strong>With your direction:</strong> another person or service when you ask us to share information or clearly consent.</li>
          </ul>
          <p>Public doctor profiles and user-submitted ratings or reviews may be visible to other Darman users. Do not include unnecessary health or identifying information in public content.</p>
        </LegalSection>

        <LegalSection id="permissions" title="6. Device permissions">
          <p>Darman requests device permissions only when a specific feature needs them, and each permission can be turned off at any time in your device settings.</p>
          <div className="definition-grid">
            <div><strong>Camera</strong><p>Profile photos, doctor verification, chat media, and video consultations.</p></div>
            <div><strong>Microphone</strong><p>Voice messages and audio or video consultations.</p></div>
            <div><strong>Photos &amp; files</strong><p>Choosing and sending profile, credential, consultation, or chat media.</p></div>
            <div><strong>Notifications</strong><p>Messages, incoming calls, appointments, status changes, and service alerts.</p></div>
            <div><strong>Nearby audio devices</strong><p>Connecting supported Bluetooth headsets during calls on relevant Android versions.</p></div>
          </div>
          <p>Some features will not work without the permission they require. We do not request contacts, precise location, SMS, or call-log access.</p>
        </LegalSection>

        <LegalSection id="retention" title="7. Retention and deletion">
          <p>We keep information only for as long as needed to provide the Services, maintain account and transaction integrity, resolve disputes, protect users, enforce agreements, and meet medical, professional, tax, accounting, or other legal obligations. Retention periods vary by record type and applicable law.</p>
          <p>When information is no longer required, we delete it, anonymise it, or securely isolate it until deletion is possible. Encrypted backups may retain residual copies for a limited period before routine overwrite. Anonymised information that can no longer identify you may be retained for service analysis.</p>
          <p>You can request account deletion at any time through our <Link href="/delete-account">account-deletion page</Link>. This removes your account and associated personal data, subject to the legal retention exceptions above. Deleting the app from a device does not delete the account.</p>
        </LegalSection>

        <LegalSection id="security" title="8. Security and international transfers">
          <p>We use reasonable administrative, technical, and organisational safeguards designed to protect information, including access controls, authenticated services, encryption in transit, restricted storage, and monitoring. No internet or storage system is completely secure, so we cannot guarantee absolute security.</p>
          <p>Our providers may process information in countries other than your own. Where required, we use appropriate contractual or legal safeguards for cross-border processing. Never share a one-time password, password, or account-access code with another person — Darman staff will never ask you for it.</p>
        </LegalSection>

        <LegalSection id="choices" title="9. Your rights and choices">
          <p>Depending on applicable law, you may ask to access, correct, update, export, restrict, object to processing of, or delete your personal information, and you may withdraw consent where processing relies on consent. You can update some profile details in the app and control device permissions through system settings.</p>
          <p>To protect users, we may verify your identity and account ownership before completing a request. Some rights are subject to lawful exceptions, including records that must be retained for care, fraud prevention, financial reporting, disputes, or legal compliance.</p>
          <p>Send a privacy request to <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>. We will respond within the period required by applicable law.</p>
        </LegalSection>

        <LegalSection id="children" title="10. Children and dependent patients">
          <p>Darman accounts are intended for people legally able to agree to these terms and are not directed at children. A parent or legal guardian must manage an account or provide consent when required for a minor or dependent patient. Do not create an independent child account or submit a child&apos;s information without appropriate authority. If we learn that a child&apos;s account or information was created without appropriate consent, we will take steps to remove it. Contact us if you believe a child&apos;s information was provided improperly.</p>
        </LegalSection>

        <LegalSection id="changes" title="11. Changes and contact">
          <p>We may update this policy when our Services, providers, or legal obligations change. The effective date at the top shows the latest revision. If a change materially affects your rights, we will provide appropriate notice through the app, website, or registered contact details before it takes effect.</p>
          <p>Questions, complaints, and privacy requests can be sent to <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>. Include the phone number registered to your account, but never include a password or one-time verification code.</p>
        </LegalSection>
      </LegalLayout>
    </>
  );
}