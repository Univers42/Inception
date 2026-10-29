import { LINKS } from '../content'
import { Totem } from './Totem'

export function Footer() {
    return (
        <footer className="border-t border-line">
            <div className="mx-auto flex max-w-6xl flex-col gap-6 px-6 py-10 md:flex-row md:items-center md:justify-between md:px-10">
                <p className="flex items-center gap-3 text-sm text-muted">
                    <Totem size={18} />
                    Inception · dlesieur · 42
                </p>
                <ul className="flex flex-wrap gap-x-6 gap-y-2 text-sm">
                    <li><a className="text-muted hover:text-text" href={LINKS.deeper}>Deeper</a></li>
                    <li><a className="text-muted hover:text-text" href={LINKS.blog}>Blog</a></li>
                    <li><a className="text-muted hover:text-text" href={LINKS.wiki}>Wiki</a></li>
                    <li><a className="text-muted hover:text-text" href={LINKS.lab}>Lab</a></li>
                    <li><a className="text-muted hover:text-text" href="/wp-admin/">Admin</a></li>
                </ul>
                <p className="font-code text-[0.75rem] text-faint">TLS 1.2/1.3 · port 443 only</p>
            </div>
        </footer>
    )
}
