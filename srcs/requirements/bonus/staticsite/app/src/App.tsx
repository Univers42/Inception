import { useState } from 'react'
import { MotionConfig } from 'framer-motion'
import { Navbar } from './components/Navbar'
import { Levels } from './components/Levels'
import { Stack } from './components/Stack'
import { Numbers } from './components/Numbers'
import { Journal } from './components/Journal'
import { Footer } from './components/Footer'

export function App() {
    const [spins, setSpins] = useState(0)
    return (
        <MotionConfig reducedMotion="user">
            <a href="#main" className="skip-link">Skip to content</a>
            <Navbar spins={spins} />
            <main id="main">
                <h1 className="sr-only">Inception: a hand-built Docker infrastructure, three levels deep</h1>
                <Levels onLevelChange={() => setSpins((n) => n + 1)} />
                <Stack />
                <Numbers />
                <Journal />
            </main>
            <Footer />
        </MotionConfig>
    )
}
