import { Chapters } from './components/Chapters'
import { DepthGauge } from './components/DepthGauge'
import { Nav } from './components/Nav'
import { Stage } from './components/Stage'
import { LINKS } from './content'

export function App() {
    return (
        <>
            <a className="skip" href="#content">
                Skip to the text
            </a>
            <Stage />
            <Nav />
            <DepthGauge />
            <main id="content">
                <Chapters />
            </main>
            <footer className="foot">
                <p>Inception · dlesieur · 42 — built from the repository, served by nginx, no PHP on this page.</p>
                <p>
                    <a href={LINKS.landing}>Landing</a> · <a href={LINKS.blog}>Blog</a> · <a href={LINKS.wiki}>Wiki</a> ·{' '}
                    <a href={LINKS.lab}>Lab</a> · <a href={LINKS.admin}>Sign in</a>
                </p>
            </footer>
        </>
    )
}
