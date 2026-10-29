// The page's position in the descent, read from native scrolling.
//
// x = chapter index + how far through that chapter (0..1). Each chapter is a
// tall <section>; its fraction is how much of it has scrolled past the top of
// the viewport. Written as --t on the section (CSS fades its text plate) and
// as data-chapter on <html> (CSS and the depth gauge), then handed to anyone
// subscribed, the 3D world first. One measurement per animation frame.
export type Progress = { x: number; chapter: number }
type Listener = (p: Progress) => void

const listeners = new Set<Listener>()
let state: Progress = { x: 0, chapter: 0 }

export function subscribe(fn: Listener): () => void {
    listeners.add(fn)
    fn(state)
    return () => {
        listeners.delete(fn)
    }
}

export function trackScroll(sections: HTMLElement[]): () => void {
    let queued = false
    const measure = () => {
        queued = false
        const vh = window.innerHeight
        let chapter = 0
        let x = 0
        sections.forEach((section, i) => {
            const r = section.getBoundingClientRect()
            const t = Math.min(1, Math.max(0, -r.top / Math.max(1, r.height - vh)))
            section.style.setProperty('--t', t.toFixed(4))
            if (r.top <= 1) {
                chapter = i
                x = i + t
            }
        })
        if (chapter !== state.chapter) document.documentElement.dataset.chapter = String(chapter)
        state = { x, chapter }
        listeners.forEach((fn) => fn(state))
    }
    const queue = () => {
        if (queued) return
        queued = true
        requestAnimationFrame(measure)
    }
    window.addEventListener('scroll', queue, { passive: true })
    window.addEventListener('resize', queue)
    measure()
    return () => {
        window.removeEventListener('scroll', queue)
        window.removeEventListener('resize', queue)
    }
}
