// The world: one renderer, three scenes (the folding city, the turning
// corridor, limbo's shore with its sea and the totem), one camera that the
// scroll position flies along camera.ts's path.
//
// Native scroll stays the input (the page scrolls as a document; nothing is
// hijacked). Only the camera is smoothed: it chases the scroll target with an
// exponential ease, so a fast flick reads as a fast walk, never a teleport,
// except across chapters, where the veil covers the jump.
//
// Light: the lamps are point lights (material.ts), emissives are HDR, and on
// the GPU tier a bloom pass and a neutral tone map turn them into glow. That
// tier is also always alive while the page is visible: windows switch, the
// sea moves, stars turn. The software tier draws on demand (a frame only while
// the camera moves or the top spins), so a page left alone costs it nothing.
import {
    BackSide,
    BufferAttribute,
    BufferGeometry,
    Color,
    Group,
    HalfFloatType,
    Mesh,
    NeutralToneMapping,
    PerspectiveCamera,
    PlaneGeometry,
    Scene,
    ShaderMaterial,
    SphereGeometry,
    SRGBColorSpace,
    Vector2,
    Vector3,
    WebGLRenderer,
    WebGLRenderTarget,
} from 'three'
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js'
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js'
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js'
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js'
import type { Built, BuildRequest } from './build.worker'
import type { MeshData } from './mesher'
import { CHAPTERS, shotAt, totemSpot, type Scene as SceneName, type Shot } from './camera'
import { setLamps, voxelMaterial, type Light, type Palette } from './material'
import { birds, contactShadow, lightShafts, motes, setMotes, traffic, type MoteLook } from './life'
import { MAX_LAMPS, nearestLamps, type Lamp } from './lamps'
import { transitionPass, type Transition } from './transition'
import { CITY, cityLamps } from './levels/city'
import { HALL, hallLamps } from './levels/hallway'
import { LIMBO, shore } from './levels/limbo'
import { MAT } from './voxels'

export type WorldOptions = {
    canvas: HTMLCanvasElement
    tier: 'gpu' | 'software'
    reducedMotion: boolean
    onReady: () => void
    onVeil: (dark: number, bright: number) => void
    onFail: (reason: string) => void
}

export type World = {
    setTarget: (x: number) => void
    setReducedMotion: (on: boolean) => void
    dispose: () => void
}

// ── looks, from srcs/design/tokens.css ────────────────────────────────────
const CITY_PALETTE: Palette = {
    [MAT.concrete]: '#56627a',
    [MAT.glass]: '#5b7896',
    [MAT.street]: '#1b2230',
    [MAT.brass]: '#c9862a',
    [MAT.trim]: '#2e384a',
    [MAT.lamp]: '#f0b45a',
    [MAT.sign]: '#ffd28a',
}
const CITY_LIGHT: Light = {
    sky: '#8db4d8', skyI: 1.25, ground: '#1a2230', groundI: 0.5, key: '#f0b45a', keyI: 0.75,
    keyDir: [-0.7, 0.35, 0.3], ambient: 0.28, fog: '#131c2a', fogNear: 30, fogFar: 175, lit: 0.7, glow: '#f0b45a',
    scatter: 0.1, reflectTop: '#1c2a40', reflectLow: '#4a4a52',
}
const HALL_PALETTE: Palette = {
    [MAT.wall]: '#4f807a',
    [MAT.wood]: '#7a4c33',
    [MAT.carpetA]: '#1f6f66',
    [MAT.carpetB]: '#13262a',
    [MAT.trim]: '#2a313d',
    [MAT.brass]: '#d39236',
    [MAT.lamp]: '#ffd08a',
    [MAT.sign]: '#f0b45a',
    [MAT.window]: '#fff3dc',
}
const HALL_LIGHT: Light = {
    sky: '#ffd9a0', skyI: 0.9, ground: '#5cc2b4', groundI: 0.35, key: '#5cc2b4', keyI: 0.35,
    keyDir: [0.4, 0.2, 1], ambient: 0.42, fog: '#0d1417', fogNear: 4, fogFar: 64, lit: 1, glow: '#f0b45a',
    scatter: 0, reflectTop: '#3a3226', reflectLow: '#1a2422',
}
const LIMBO_PALETTE: Palette = {
    [MAT.limestone]: '#c4a77d',
    [MAT.weathered]: '#8f9cb0',
    [MAT.trim]: '#a88e68',
    [MAT.paper]: '#b3a790',
    [MAT.brass]: '#f0b45a',
    [MAT.sign]: '#ffcf7a',
}
// A top face sums sky + key·0.51 + ambient: kept near 1.15 so the pale
// promenade stops short of white (at 1.7 it clipped to a blank wedge).
const LIMBO_LIGHT: Light = {
    sky: '#e9eef5', skyI: 0.6, ground: '#74829a', groundI: 0.35, key: '#fff1d6', keyI: 0.62,
    keyDir: [0.25, 0.5, 0.8], ambient: 0.3, fog: '#bdb9ae', fogNear: 26, fogFar: 160, lit: 1, glow: '#f0b45a',
    scatter: 0.3, reflectTop: '#c9d1da', reflectLow: '#e8dfcf',
}
// HDR: above 1, so the bloom pass takes them and the tone map keeps a hue
const EMISSIVE = { [MAT.lamp]: 4, [MAT.sign]: 3.4, [MAT.window]: 3.6 }
const SKY: Record<SceneName, [string, string]> = {
    city: ['#05080d', '#22324a'],
    hall: ['#0d1417', '#0d1417'],
    limbo: ['#c9d1da', '#e8dfcf'],
}
// The one light in each sky: a moon over the avenue (where the surface's
// camera looks), limbo's low sun over the sea, the key light's direction.
type Orb = { dir: [number, number, number]; color: string; power: number; size: number; glow: number; stars: number }
const ORB: Record<SceneName, Orb> = {
    city: { dir: [0.22, 0.4, 1], color: '#dfe8ff', power: 3, size: 0.99965, glow: 0.35, stars: 1 },
    hall: { dir: [0, 1, 0], color: '#000000', power: 0, size: 1, glow: 0, stars: 0 },
    limbo: { dir: [0.25, 0.5, 0.8], color: '#fff1d6', power: 7, size: 0.99975, glow: 1, stars: 0 },
}
// What drifts in the air: warm dust under the city's lamps and the corridor's,
// spray blown off limbo's sea.
const MOTES: Record<SceneName, MoteLook> = {
    city: { color: '#ffd9a0', power: 1.3, size: 1, drift: [0, -0.06, 0.12] },
    hall: { color: '#ffe2b8', power: 1.1, size: 0.75, drift: [0, 0.04, 0] },
    limbo: { color: '#ffffff', power: 0.8, size: 1.2, drift: [1.6, 0.12, 0.7] },
}
// [strength, radius, threshold] of the bloom, per scene: limbo's sky is near
// white already, so its threshold sits above it
const BLOOM: Record<SceneName, [number, number, number]> = {
    city: [0.55, 0.45, 0.95],
    hall: [0.45, 0.4, 1],
    limbo: [0.3, 0.4, 1.15],
}

function geometryOf(m: MeshData): BufferGeometry {
    const g = new BufferGeometry()
    g.setAttribute('position', new BufferAttribute(m.position, 3))
    g.setAttribute('aAo', new BufferAttribute(m.ao, 1))
    g.setAttribute('aFace', new BufferAttribute(m.face, 1))
    g.setAttribute('aMat', new BufferAttribute(m.mat, 1))
    g.setIndex(new BufferAttribute(m.index, 1))
    g.computeBoundingSphere()
    return g
}

function skyDome(): Mesh<SphereGeometry, ShaderMaterial> {
    const material = new ShaderMaterial({
        side: BackSide,
        depthWrite: false,
        uniforms: {
            uTop: { value: new Color() },
            uHorizon: { value: new Color() },
            uOrbDir: { value: new Vector3(0, 1, 0) },
            uOrb: { value: new Color() },
            uOrbSize: { value: 1 },
            uGlow: { value: 0 },
            uStars: { value: 0 },
            uTime: { value: 0 },
        },
        vertexShader: /* glsl */ `
            varying vec3 vDir;
            void main() {
                vDir = position;
                vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
                gl_Position = p.xyww;
            }`,
        fragmentShader: /* glsl */ `
            uniform vec3 uTop;
            uniform vec3 uHorizon;
            uniform vec3 uOrbDir;
            uniform vec3 uOrb;
            uniform float uOrbSize;
            uniform float uGlow;
            uniform float uStars;
            uniform float uTime;
            varying vec3 vDir;
            float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
            void main() {
                vec3 d = normalize(vDir);
                vec3 c = mix(uHorizon, uTop, smoothstep(-0.05, 0.6, d.y));
                float a = max(dot(d, uOrbDir), 0.0);
                c += uOrb * (smoothstep(uOrbSize, uOrbSize + 0.00012, a) + uGlow * (pow(a, 300.0) * 0.6 + pow(a, 24.0) * 0.12 + pow(a, 4.0) * 0.04));
                // square stars, one per cell of the sky: they suit the voxels
                vec3 q = floor(d * 240.0);
                float h = hash(q);
                float star = uStars * step(0.9968, h) * smoothstep(0.04, 0.4, d.y);
                c += vec3(0.85, 0.92, 1.0) * star * (0.7 + 0.3 * sin(uTime * (0.8 + 3.0 * fract(h * 57.0)) + h * 40.0)) * (0.8 + 2.4 * fract(h * 91.0));
                gl_FragColor = vec4(c, 1.0);
                #include <tonemapping_fragment>
                #include <colorspace_fragment>
            }`,
    })
    const dome = new Mesh(new SphereGeometry(400, 32, 16), material)
    dome.renderOrder = -1
    dome.frustumCulled = false
    return dome
}

// Limbo's sea: one quad, everything per pixel from the world position. The
// waves exist only in the normal (a sum of travelling sines and their
// derivatives), which is what light reads: it reflects the sky by Fresnel and
// breaks the sun into glints that the bloom turns to sparkle. Surf at the mean
// shoreline, fog into the bleached horizon. Still on the software tier.
function sea(fog: Color): Mesh<PlaneGeometry, ShaderMaterial> {
    const material = new ShaderMaterial({
        uniforms: {
            uTime: { value: 0 },
            uFog: { value: fog },
            uDeep: { value: new Color('#0b2a33') },
            uShallow: { value: new Color('#3fae9f') },
            uFoam: { value: new Color('#f4efe4') },
            uTop: { value: new Color(SKY.limbo[0]) },
            uHorizon: { value: new Color(SKY.limbo[1]) },
            uSunDir: { value: new Vector3(...ORB.limbo.dir).normalize() },
            uSun: { value: new Color(ORB.limbo.color).multiplyScalar(ORB.limbo.power) },
            uShore: { value: 0 },
        },
        vertexShader: /* glsl */ `
            varying vec3 vWorld;
            void main() {
                vec4 w = modelMatrix * vec4(position, 1.0);
                vWorld = w.xyz;
                gl_Position = projectionMatrix * viewMatrix * w;
            }`,
        fragmentShader: /* glsl */ `
            uniform float uTime;
            uniform vec3 uFog;
            uniform vec3 uDeep;
            uniform vec3 uShallow;
            uniform vec3 uFoam;
            uniform vec3 uTop;
            uniform vec3 uHorizon;
            uniform vec3 uSunDir;
            uniform vec3 uSun;
            uniform float uShore;
            varying vec3 vWorld;
            // one travelling sine: amplitude a, direction k (its length the
            // spatial frequency), speed w; returns its slope
            vec2 wave(vec2 p, float a, vec2 k, float w) { return a * k * cos(dot(k, p) + w * uTime); }
            void main() {
                vec2 p = vWorld.xz;
                vec2 g = wave(p, 0.10, vec2(0.21, 0.13), 0.9) + wave(p, 0.07, vec2(-0.17, 0.29), 1.2)
                       + wave(p, 0.035, vec2(0.62, -0.41), 2.1) + wave(p, 0.02, vec2(-0.9, -0.7), 2.9)
                       + wave(p, 0.012, vec2(1.7, 1.1), 4.1);
                vec3 n = normalize(vec3(-g.x, 1.0, -g.y));
                vec3 toEye = cameraPosition - vWorld;
                float dist = length(toEye);
                vec3 V = toEye / dist;
                float fres = 0.02 + 0.98 * pow(1.0 - max(dot(n, V), 0.0), 5.0);
                vec3 R = reflect(-V, n);
                vec3 sky = mix(uHorizon, uTop, smoothstep(-0.05, 0.6, R.y));
                float off = vWorld.z - uShore;
                vec3 body = mix(uDeep, uShallow, clamp(0.55 * exp(-max(off, 0.0) * 0.1) + 0.12, 0.0, 1.0));
                float s = max(dot(R, uSunDir), 0.0);
                vec3 c = mix(body, sky, fres * 0.32) + uSun * (pow(s, 600.0) * 6.0 + pow(s, 60.0) * 0.25);
                // Surf: one broken line at the mean shoreline. The land's own
                // edge wanders ±5 voxels around it and covers the rest.
                float swell = sin(vWorld.x * 0.4 + uTime * 1.3) * 0.8 + sin(vWorld.x * 1.7 - uTime) * 0.3;
                float foam = step(abs(off - 0.8 - swell), 0.7) * step(0.35, fract(vWorld.x * 0.21 + uTime * 0.05));
                c = mix(c, uFoam, foam * 0.6);
                // Fog by the distance to this fragment, brighter toward the sun:
                // the plane is one quad, and a per-vertex distance put every
                // pixel past fogFar.
                vec3 fog = uFog + uSun * 0.1 * pow(max(dot(-V, uSunDir), 0.0), 6.0);
                c = mix(c, fog, smoothstep(24.0, 150.0, dist));
                gl_FragColor = vec4(c, 1.0);
                #include <tonemapping_fragment>
                #include <colorspace_fragment>
            }`,
    })
    const mesh = new Mesh(new PlaneGeometry(600, 300), material)
    mesh.rotation.x = -Math.PI / 2
    return mesh
}

export function createWorld(o: WorldOptions): World {
    // No canvas MSAA: on the GPU tier the scene renders into the composer's
    // own multisampled target, and the software tier cannot afford it.
    const renderer = new WebGLRenderer({ canvas: o.canvas, antialias: false, powerPreference: 'high-performance' })
    renderer.outputColorSpace = SRGBColorSpace
    renderer.toneMapping = NeutralToneMapping
    const maxDpr = o.tier === 'gpu' ? Math.min(window.devicePixelRatio || 1, 2) : 0.6
    const minDpr = o.tier === 'gpu' ? 0.6 : 0.4
    let dpr = maxDpr
    renderer.setPixelRatio(dpr)

    const camera = new PerspectiveCamera(70, 1, 0.1, 600)
    const scene = new Scene()
    const dome = skyDome()
    scene.add(dome)

    // GPU tier: render → bloom → tone map and sRGB (OutputPass), in half
    // float so the HDR emissives survive until the bloom reads them.
    let bloom: UnrealBloomPass | null = null
    let crossing: Transition | null = null
    let composer: EffectComposer | null = null
    if (o.tier === 'gpu') {
        composer = new EffectComposer(renderer, new WebGLRenderTarget(1, 1, { type: HalfFloatType, samples: 4 }))
        composer.addPass(new RenderPass(scene, camera))
        bloom = new UnrealBloomPass(new Vector2(1, 1), ...BLOOM.city)
        composer.addPass(bloom)
        crossing = transitionPass()
        composer.addPass(crossing)
        composer.addPass(new OutputPass())
    }
    const lampLimit = o.tier === 'gpu' ? MAX_LAMPS : 4
    const LAMPS: Record<SceneName, Lamp[]> = { city: cityLamps(), hall: hallLamps(), limbo: [] }

    const cityMat = voxelMaterial(CITY_PALETTE, EMISSIVE, CITY_LIGHT)
    cityMat.uniforms.uZ0.value = CITY.z0
    cityMat.uniforms.uR.value = CITY.radius
    const hallMat = voxelMaterial(HALL_PALETTE, EMISSIVE, HALL_LIGHT)
    hallMat.uniforms.uLocalLight.value = 1
    const limboMat = voxelMaterial(LIMBO_PALETTE, EMISSIVE, LIMBO_LIGHT)
    // the top spins in its own frame: its highlights need their own camera
    const totemMat = limboMat.clone()
    const materials = [cityMat, hallMat, limboMat, totemMat]
    let hallMesh: Mesh | null = null
    let totemMesh: Mesh | null = null

    const groups: Record<SceneName, Group> = { city: new Group(), hall: new Group(), limbo: new Group() }
    const fogs: Record<SceneName, Color> = {
        city: new Color(CITY_LIGHT.fog),
        hall: new Color(HALL_LIGHT.fog),
        limbo: new Color(LIMBO_LIGHT.fog),
    }
    for (const g of Object.values(groups)) {
        g.visible = false
        scene.add(g)
    }
    const water = sea(fogs.limbo)
    water.position.set(LIMBO.sx / 2, 0.55, LIMBO.sz / 2 + 100)
    water.material.uniforms.uShore.value = shore(LIMBO.sx / 2)
    groups.limbo.add(water)
    // Traffic runs the avenue on both tiers (it says "a city" even standing
    // still), driving on the right: looking down +z, +x is screen-left, so
    // the oncoming lane is the higher x. Motes only where every frame is
    // drawn, the GPU tier.
    const cars = traffic(o.tier === 'gpu' ? 36 : 14, [52.6, 43.4], CITY.sz, CITY_LIGHT)
    cars.material.uniforms.uZ0.value = CITY.z0
    cars.material.uniforms.uR.value = CITY.radius
    groups.city.add(cars)
    const dust = o.tier === 'gpu' ? motes(1400) : null
    if (dust) scene.add(dust)
    // the corridor's ceiling lamps cast shafts, in the corridor's own frame
    const shafts = lightShafts(LAMPS.hall.filter((l) => l.y > HALL.inside.y1 - 1), HALL.inside.y1 - HALL.inside.y0, 1.7, '#ffe2b8', 0.09)
    shafts.position.set(-HALL.axis.x, -HALL.axis.y, 0)
    groups.hall.add(shafts)
    const flock = birds(o.tier === 'gpu' ? 11 : 6, new Vector3(LIMBO.sx / 2, 0, shore(LIMBO.sx / 2) + 10), LIMBO_LIGHT.fog, LIMBO_LIGHT.fogNear, LIMBO_LIGHT.fogFar)
    groups.limbo.add(flock)
    const shadow = contactShadow(1.6)
    shadow.position.copy(totemSpot()).y += 0.02
    groups.limbo.add(shadow)
    const tilt = new Group()
    const totemSpin = new Group()
    tilt.add(totemSpin)
    tilt.position.copy(totemSpot())
    groups.limbo.add(tilt)

    const ready = new Set<string>()
    const worker = new Worker(new URL('./build.worker.ts', import.meta.url), { type: 'module' })
    worker.onmessage = (e: MessageEvent<Built>) => {
        const { name, mesh } = e.data
        const geometry = geometryOf(mesh)
        if (name === 'city') {
            const m = new Mesh(geometry, cityMat)
            m.frustumCulled = false // the fold moves vertices far from the bounding sphere
            groups.city.add(m)
        } else if (name === 'hall') {
            const m = new Mesh(geometry, hallMat)
            m.position.set(-HALL.axis.x, -HALL.axis.y, 0)
            groups.hall.add(m)
            hallMesh = m
        } else if (name === 'limbo') {
            groups.limbo.add(new Mesh(geometry, limboMat))
        } else {
            const m = new Mesh(geometry, totemMat)
            m.scale.setScalar(0.22)
            m.position.set(-6.5 * 0.22, 0, -6.5 * 0.22)
            totemSpin.add(m)
            totemMesh = m
        }
        ready.add(name)
        dirty = true
        if (name === 'city') o.onReady()
    }
    worker.onerror = () => o.onFail('worker')
    worker.postMessage({ scale: 1 } satisfies BuildRequest)

    let target = 0
    let current = 0
    let reduced = o.reducedMotion
    let dirty = true
    let raf = 0
    let last = performance.now()
    let clock = 0
    let shown: SceneName | null = null

    // frame-time governor: lower the resolution while frames are slow, raise
    // it back when they are fast, and stop flipping after three changes
    let windowTime = 0
    let windowFrames = 0
    let flips = 0
    const govern = (dt: number) => {
        windowTime += dt
        windowFrames++
        if (windowTime < 1) return
        const avg = windowTime / windowFrames
        windowTime = 0
        windowFrames = 0
        if (flips >= 3) return
        const next = avg > 1 / 40 ? Math.max(minDpr, dpr - 0.25) : avg < 1 / 57 ? Math.min(maxDpr, dpr + 0.25) : dpr
        if (next !== dpr) {
            if (next > dpr) flips++
            dpr = next
            renderer.setPixelRatio(dpr)
            composer?.setPixelRatio(dpr)
            dirty = true
        }
    }

    let baseFov = 70
    const resize = () => {
        const w = o.canvas.clientWidth
        const h = o.canvas.clientHeight
        if (!w || !h) return
        renderer.setSize(w, h, false)
        composer?.setSize(w, h)
        camera.aspect = w / h
        baseFov = w / h < 0.8 ? 82 : 70
        camera.fov = baseFov
        camera.updateProjectionMatrix()
        dirty = true
    }
    const observer = new ResizeObserver(resize)
    observer.observe(o.canvas)
    resize()

    const apply = (s: Shot) => {
        if (shown !== s.scene) {
            for (const [name, g] of Object.entries(groups)) g.visible = name === s.scene
            const du = dome.material.uniforms
            du.uTop.value.set(SKY[s.scene][0])
            du.uHorizon.value.set(SKY[s.scene][1])
            const orb = ORB[s.scene]
            du.uOrbDir.value.set(...orb.dir).normalize()
            du.uOrb.value.set(orb.color).multiplyScalar(orb.power)
            du.uOrbSize.value = orb.size
            du.uGlow.value = orb.glow
            du.uStars.value = orb.stars
            if (bloom) [bloom.strength, bloom.radius, bloom.threshold] = BLOOM[s.scene]
            if (dust) setMotes(dust, MOTES[s.scene])
            scene.background = fogs[s.scene]
            dome.visible = s.scene !== 'hall'
            shown = s.scene
        }
        // The camera breathes: a slow sway, so a world left alone still moves.
        const sway = o.tier === 'gpu' && !reduced ? 1 : 0
        camera.position.copy(s.pos)
        camera.position.x += Math.sin(clock * 0.5) * 0.06 * sway
        camera.position.y += Math.sin(clock * 0.83) * 0.05 * sway
        camera.lookAt(gaze.copy(s.look).add(lean.set(Math.sin(clock * 0.31) * 0.3, Math.sin(clock * 0.43) * 0.18, 0).multiplyScalar(sway)))
        dome.position.copy(s.pos)
        cityMat.uniforms.uFold.value = s.fold
        cars.material.uniforms.uFold.value = s.fold
        if (dust) dust.material.uniforms.uEye.value.copy(camera.position)
        groups.hall.rotation.z = reduced ? 0 : s.turn
        lightFrom(s.scene)
        // falling or flooding, the view widens: speed felt at the edges
        const fov = baseFov + (reduced ? 0 : 16 * s.dark + 8 * s.bright)
        if (fov !== camera.fov) {
            camera.fov = fov
            camera.updateProjectionMatrix()
        }
        if (crossing) {
            crossing.set(s.dark, s.bright, camera.aspect, clock)
            o.onVeil(0, 0)
        } else o.onVeil(s.dark, s.bright)
    }

    const gaze = new Vector3()
    const lean = new Vector3()
    // The camera in each level's grid frame, and the lamps nearest it there.
    const eye = new Vector3()
    const lightFrom = (name: SceneName) => {
        const mat = name === 'city' ? cityMat : name === 'hall' ? hallMat : limboMat
        if (name === 'hall' && hallMesh) {
            groups.hall.updateMatrixWorld()
            hallMesh.worldToLocal(eye.copy(camera.position))
        } else eye.copy(camera.position)
        mat.uniforms.uCamLocal.value.copy(eye)
        setLamps(mat, nearestLamps(LAMPS[name], eye.x, eye.y, eye.z, lampLimit), LAMPS[name], lampLimit, o.tier === 'gpu' && !reduced ? clock : null)
        if (name === 'limbo' && totemMesh) {
            tilt.updateMatrixWorld()
            totemMesh.worldToLocal(totemMat.uniforms.uCamLocal.value.copy(camera.position))
        }
    }

    const frame = (now: number) => {
        raf = requestAnimationFrame(frame)
        const dt = Math.min(0.1, (now - last) / 1000)
        last = now
        if (document.hidden) return
        let goal = target
        if (reduced) goal = Math.min(CHAPTERS - 0.5, Math.floor(target) + 0.5)
        const gap = goal - current
        if (reduced || Math.abs(gap) > 1.2) current = goal - (reduced ? 0 : Math.sign(gap) * 0.04)
        else current += gap * (1 - Math.exp(-dt * 3.4))
        const moving = Math.abs(goal - current) > 1e-4
        const s = shotAt(current)
        const animating = !reduced && (o.tier === 'gpu' || (s.scene === 'limbo' && s.spin))
        if (!moving && !animating && !dirty) return
        dirty = false
        if (!reduced) clock += dt
        const time = o.tier === 'gpu' ? clock : 0
        for (const m of materials) m.uniforms.uTime.value = time
        dome.material.uniforms.uTime.value = time
        cars.material.uniforms.uTime.value = o.tier === 'gpu' ? clock : 0
        flock.material.uniforms.uTime.value = o.tier === 'gpu' ? clock : 0
        if (dust) {
            dust.material.uniforms.uTime.value = time
            dust.material.uniforms.uScale.value = dpr
        }
        if (s.scene === 'limbo') {
            water.material.uniforms.uTime.value = time
            totemSpin.rotation.y += reduced ? 0 : dt * 12
            tilt.rotation.z = reduced ? 0.08 : 0.1 * Math.sin(clock * 2)
            tilt.rotation.x = reduced ? 0 : 0.1 * Math.cos(clock * 2)
        }
        apply(s)
        if (!ready.has(s.scene === 'city' ? 'city' : s.scene)) return
        if (composer) composer.render(dt)
        else renderer.render(scene, camera)
        if (moving || animating) govern(dt)
    }
    raf = requestAnimationFrame(frame)

    const lost = (e: Event) => {
        e.preventDefault()
        o.onFail('context lost')
    }
    o.canvas.addEventListener('webglcontextlost', lost)

    return {
        setTarget(x) {
            target = Math.max(0, Math.min(CHAPTERS - 1e-6, x))
        },
        setReducedMotion(on) {
            reduced = on
            dirty = true
        },
        dispose() {
            cancelAnimationFrame(raf)
            observer.disconnect()
            worker.terminate()
            composer?.dispose()
            o.canvas.removeEventListener('webglcontextlost', lost)
            renderer.dispose()
        },
    }
}
