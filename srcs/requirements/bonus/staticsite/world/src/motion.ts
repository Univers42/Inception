// Motion on or off. Off when the system asks for reduced motion, or when the
// reader flips the switch in the navigation (WCAG 2.2.2: anything that moves
// can be paused). Off means: no camera travel, no turning corridor, no
// spinning top; each chapter shows one still frame.
type Listener = (reduced: boolean) => void

const KEY = 'deeper-motion'
const listeners = new Set<Listener>()
let reduced = false
let started = false

function apply(next: boolean) {
    reduced = next
    document.documentElement.dataset.motion = next ? 'off' : 'on'
    listeners.forEach((fn) => fn(next))
}

function start() {
    if (started) return
    started = true
    const query = window.matchMedia('(prefers-reduced-motion: reduce)')
    let saved: string | null = null
    try {
        saved = localStorage.getItem(KEY)
    } catch {
        saved = null
    }
    apply(saved ? saved === 'off' : query.matches)
    query.addEventListener('change', (e) => apply(e.matches))
}

export function onMotion(fn: Listener): () => void {
    start()
    listeners.add(fn)
    fn(reduced)
    return () => {
        listeners.delete(fn)
    }
}

export function toggleMotion(): void {
    start()
    try {
        localStorage.setItem(KEY, reduced ? 'on' : 'off')
    } catch {
        // a private window: the switch still works for this visit
    }
    apply(!reduced)
}
