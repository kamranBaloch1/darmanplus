import Image from "next/image";
import Link from "next/link";
import { SUPPORT_EMAIL } from "../lib/site";

export function Brand() {
  return (
    <Link className="brand" href="/" aria-label="Darman home">
      <Image
        className="brand-logo"
        src="/darman-logo.png"
        alt="Darman"
        width={148}
        height={40}
        priority
      />
    </Link>
  );
}

export function SiteHeader() {
  return (
    <header className="site-header">
      <div className="page-width header-inner">
        <Brand />
        <nav aria-label="Legal pages">
          <Link href="/privacy-policy">Privacy</Link>
          <Link href="/terms-and-conditions">Terms</Link>
          <Link className="header-cta" href="/delete-account">Delete account</Link>
        </nav>
      </div>
    </header>
  );
}

export function SiteFooter() {
  return (
    <footer className="site-footer">
      <div className="page-width footer-main">
        <div>
          <Brand />
          <p>Care, made simpler. Connecting patients and healthcare professionals.</p>
        </div>
        <div className="footer-links">
          <div>
            <span>Legal</span>
            <Link href="/privacy-policy">Privacy Policy</Link>
            <Link href="/terms-and-conditions">Terms & Conditions</Link>
            <Link href="/delete-account">Delete Account</Link>
          </div>
          <div>
            <span>Support</span>
            <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>
          </div>
        </div>
      </div>
      <div className="page-width footer-bottom">
        <span>© {new Date().getFullYear()} Darman. All rights reserved.</span>
        <span>Made for better care.</span>
      </div>
    </footer>
  );
}
