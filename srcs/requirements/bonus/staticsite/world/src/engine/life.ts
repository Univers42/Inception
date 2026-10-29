// What moves in the world when the visitor does not: motes drifting in the
// light, traffic on the avenue, shafts under the corridor's lamps, birds over
// limbo's drowned towers, the spinning top's shadow. Each is one draw
// call whose motion is computed in its vertex shader from uTime, so animating
// it costs a uniform write per frame and no buffer upload.
import {
    AdditiveBlending,
    BoxGeometry,
    BufferAttribute,
    BufferGeometry,
    CircleGeometry,
    Color,
    ConeGeometry,
    DoubleSide,
    InstancedMesh,
    Matrix4,
    InstancedBufferAttribute,
    InstancedBufferGeometry,
    Mesh,
    Points,
    ShaderMaterial,
    Vector3,
} from 'three'
import type { Lamp } from './lamps'
import { FOLD_GLSL } from './material'
import { rng } from './noise'

export type MoteLook = { color: string; power: number; size: number; drift: [number, number, number] }

/** Motes in a box that travels with the camera: each wraps round the eye, so
 *  a fixed number of points fills any distance walked. */
export function motes(count: number): Points<BufferGeometry, ShaderMaterial> {
    const r = rng(11)
    const seeds = new Float32Array(count * 3)
    const phase = new Float32Array(count)
    for (let i = 0; i < count; i++) {
        seeds[i * 3] = r()
        seeds[i * 3 + 1] = r()
        seeds[i * 3 + 2] = r()
        phase[i] = r()
    }
    const g = new BufferGeometry()
    g.setAttribute('position', new BufferAttribute(seeds, 3))
    g.setAttribute('aPhase', new BufferAttribute(phase, 1))
    const material = new ShaderMaterial({
        transparent: true,
        depthWrite: false,
        blending: AdditiveBlending,
        uniforms: {
            uTime: { value: 0 },
            uEye: { value: new Vector3() },
            uBox: { value: new Vector3(36, 16, 36) },
            uDrift: { value: new Vector3() },
            uColor: { value: new Color() },
            uSize: { value: 1 },
            uScale: { value: 1 },
        },
        vertexShader: /* glsl */ `
            attribute float aPhase;
            uniform float uTime;
            uniform vec3 uEye;
            uniform vec3 uBox;
            uniform vec3 uDrift;
            uniform float uSize;
            uniform float uScale;
            varying float vAlpha;
            void main() {
                float t = uTime + aPhase * 50.0;
                vec3 p = position * uBox + uDrift * uTime
                       + vec3(sin(t * 0.31), sin(t * 0.47) * 0.6, cos(t * 0.27)) * 0.8;
                p = mod(p - uEye, uBox) - uBox * 0.5 + uEye;
                vec4 mv = viewMatrix * vec4(p, 1.0);
                gl_Position = projectionMatrix * mv;
                float d = max(-mv.z, 0.3);
                gl_PointSize = clamp(uSize * uScale * 26.0 / d, 0.0, 9.0);
                // fade at the edge of the box, so the wrap never shows; twinkle
                float edge = 1.0 - smoothstep(0.25, 0.5, length((p - uEye) / uBox));
                vAlpha = edge * smoothstep(0.3, 1.5, d) * (0.55 + 0.45 * sin(t * (1.3 + aPhase)));
            }`,
        fragmentShader: /* glsl */ `
            uniform vec3 uColor;
            varying float vAlpha;
            void main() {
                vec2 q = gl_PointCoord - 0.5;
                float soft = 1.0 - smoothstep(0.15, 0.5, length(q));
                gl_FragColor = vec4(uColor * vAlpha * soft, 1.0);
            }`,
    })
    const points = new Points(g, material)
    points.frustumCulled = false
    return points
}

export function setMotes(m: Points<BufferGeometry, ShaderMaterial>, look: MoteLook): void {
    const u = m.material.uniforms
    u.uColor.value.set(look.color).multiplyScalar(look.power)
    u.uSize.value = look.size
    u.uDrift.value.set(...look.drift)
}

export type TrafficLook = { fog: string; fogNear: number; fogFar: number }

/** Cars on the avenue, one instanced box each: a dark body with two lamps on
 *  each end, white in front and red behind, so the lane coming toward the
 *  camera shows headlights and the other taillights. A whole box lit read as
 *  a glowing slab beside the camera. They run the whole avenue, so past the
 *  hinge they drive up the folded street. */
export function traffic(count: number, lanes: [number, number], length: number, look: TrafficLook): Mesh<InstancedBufferGeometry, ShaderMaterial> {
    const box = new BoxGeometry(0.9, 0.42, 1.8)
    const g = new InstancedBufferGeometry()
    g.index = box.index
    g.setAttribute('position', box.getAttribute('position'))
    g.setAttribute('normal', box.getAttribute('normal'))
    const r = rng(23)
    const cars = new Float32Array(count * 3)
    for (let i = 0; i < count; i++) {
        const away = i % 2 === 0
        cars[i * 3] = (away ? lanes[1] : lanes[0]) + (r() - 0.5) * 1.2
        cars[i * 3 + 1] = r() * length
        cars[i * 3 + 2] = (away ? 1 : -1) * (6 + r() * 9)
    }
    g.setAttribute('aCar', new InstancedBufferAttribute(cars, 3))
    g.instanceCount = count
    const material = new ShaderMaterial({
        uniforms: {
            uTime: { value: 0 },
            uLength: { value: length },
            uHead: { value: new Color('#fff1d8').multiplyScalar(4) },
            uTail: { value: new Color('#ff3b2a').multiplyScalar(6) },
            uBody: { value: new Color('#11161f') },
            uFog: { value: new Color(look.fog) },
            uFogNear: { value: look.fogNear },
            uFogFar: { value: look.fogFar },
            uFold: { value: 0 },
            uZ0: { value: 0 },
            uR: { value: 30 },
        },
        vertexShader: /* glsl */ `
            attribute vec3 aCar;
            uniform float uTime;
            uniform float uLength;
            ${FOLD_GLSL}
            varying vec3 vBox;
            varying float vEnd;
            varying vec3 vView;
            void main() {
                float dir = sign(aCar.z);
                float z = mod(aCar.y + aCar.z * uTime, uLength);
                // the box faces its way of travel: turned half round for the
                // oncoming lane (a mirror would reverse the winding, and the
                // culled front left the inside of the back face showing)
                vec3 q = vec3(position.x * dir, position.y, position.z * dir);
                vec3 p = foldPos(q + vec3(aCar.x, 1.25, z));
                vec4 mv = viewMatrix * modelMatrix * vec4(p, 1.0);
                gl_Position = projectionMatrix * mv;
                vBox = position;
                vEnd = normal.z;
                vView = mv.xyz;
            }`,
        fragmentShader: /* glsl */ `
            uniform vec3 uHead;
            uniform vec3 uTail;
            uniform vec3 uBody;
            uniform vec3 uFog;
            uniform float uFogNear;
            uniform float uFogFar;
            varying vec3 vBox;
            varying float vEnd;
            varying vec3 vView;
            void main() {
                // two lamps per end face, near the corners (per fragment: the
                // box's vertices are all corners, outside every lamp)
                float lamp = step(0.18, abs(vBox.x)) * step(abs(vBox.x), 0.4) * step(-0.02, vBox.y) * step(vBox.y, 0.14);
                vec3 c = abs(vEnd) > 0.5 && lamp > 0.5 ? (vEnd > 0.0 ? uHead : uTail) : uBody;
                gl_FragColor = vec4(mix(c, uFog, smoothstep(uFogNear, uFogFar, length(vView))), 1.0);
                #include <tonemapping_fragment>
                #include <colorspace_fragment>
            }`,
    })
    const mesh = new Mesh(g, material)
    mesh.frustumCulled = false
    return mesh
}

/** A soft dark disc under the spinning top: without it the top floated. */
export function contactShadow(radius: number): Mesh<CircleGeometry, ShaderMaterial> {
    const material = new ShaderMaterial({
        transparent: true,
        depthWrite: false,
        uniforms: { uStrength: { value: 0.5 } },
        vertexShader: /* glsl */ `
            varying vec2 vUv;
            void main() {
                vUv = uv;
                gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
            }`,
        fragmentShader: /* glsl */ `
            uniform float uStrength;
            varying vec2 vUv;
            void main() {
                float r = length(vUv - 0.5) * 2.0;
                gl_FragColor = vec4(0.0, 0.0, 0.0, uStrength * pow(1.0 - clamp(r, 0.0, 1.0), 2.0));
            }`,
    })
    const disc = new Mesh(new CircleGeometry(radius, 32), material)
    disc.rotation.x = -Math.PI / 2
    return disc
}

/** A cone of light under each lamp, apex at the lamp: additive, brightest near
 *  the lamp and toward the cone's axis, so its edges dissolve instead of
 *  showing a surface. Placed in the level's grid frame (the caller parents it
 *  where the level's mesh is), so the corridor's turn carries the shafts. */
export function lightShafts(lamps: Lamp[], height: number, radius: number, color: string, strength: number): InstancedMesh<ConeGeometry, ShaderMaterial> {
    const cone = new ConeGeometry(radius, height, 28, 1, true)
    cone.translate(0, -height / 2, 0)
    const material = new ShaderMaterial({
        transparent: true,
        depthWrite: false,
        side: DoubleSide,
        blending: AdditiveBlending,
        uniforms: { uColor: { value: new Color(color).multiplyScalar(strength) } },
        vertexShader: /* glsl */ `
            varying float vDown;
            varying float vFacing;
            void main() {
                vec4 mv = viewMatrix * modelMatrix * instanceMatrix * vec4(position, 1.0);
                gl_Position = projectionMatrix * mv;
                vec3 n = normalize(mat3(viewMatrix) * mat3(modelMatrix) * mat3(instanceMatrix) * normal);
                vFacing = abs(dot(n, normalize(-mv.xyz)));
                vDown = uv.y;
            }`,
        fragmentShader: /* glsl */ `
            uniform vec3 uColor;
            varying float vDown;
            varying float vFacing;
            void main() {
                float a = pow(vFacing, 2.0) * (0.15 + 0.85 * pow(vDown, 1.6));
                gl_FragColor = vec4(uColor * a, 1.0);
            }`,
    })
    const mesh = new InstancedMesh(cone, material, lamps.length)
    const m = new Matrix4()
    lamps.forEach((l, i) => mesh.setMatrixAt(i, m.makeTranslation(l.x, l.y, l.z)))
    mesh.frustumCulled = false
    return mesh
}

/** Birds wheeling over a point: each a V of two triangles whose tips flap,
 *  flying a circle of its own radius, height and speed. */
export function birds(count: number, center: Vector3, fog: string, fogNear: number, fogFar: number): Mesh<InstancedBufferGeometry, ShaderMaterial> {
    const g = new InstancedBufferGeometry()
    // nose, tail, tip: the left wing then the right
    const v = [0, 0, 0.3, 0, 0, -0.25, -1, 0, -0.15, 0, 0, 0.3, 1, 0, -0.15, 0, 0, -0.25]
    g.setAttribute('position', new BufferAttribute(new Float32Array(v), 3))
    g.setAttribute('aTip', new BufferAttribute(new Float32Array([0, 0, 1, 0, 1, 0]), 1))
    const r = rng(31)
    const flock = new Float32Array(count * 4)
    for (let i = 0; i < count; i++) {
        flock[i * 4] = 7 + r() * 20
        flock[i * 4 + 1] = 16 + r() * 16
        flock[i * 4 + 2] = r() * Math.PI * 2
        flock[i * 4 + 3] = (r() < 0.5 ? -1 : 1) * (0.12 + r() * 0.12)
    }
    g.setAttribute('aBird', new InstancedBufferAttribute(flock, 4))
    g.instanceCount = count
    const material = new ShaderMaterial({
        side: DoubleSide,
        uniforms: {
            uTime: { value: 0 },
            uCenter: { value: center },
            uBody: { value: new Color('#3a3f4a') },
            uFog: { value: new Color(fog) },
            uFogNear: { value: fogNear },
            uFogFar: { value: fogFar },
        },
        vertexShader: /* glsl */ `
            attribute float aTip;
            attribute vec4 aBird;
            uniform float uTime;
            uniform vec3 uCenter;
            varying vec3 vView;
            void main() {
                float a = aBird.z + uTime * aBird.w;
                vec3 at = uCenter + vec3(cos(a) * aBird.x, aBird.y + sin(uTime * 0.4 + aBird.z) * 1.2, sin(a) * aBird.x);
                vec3 fwd = normalize(vec3(-sin(a), 0.0, cos(a))) * sign(aBird.w);
                vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
                float flap = aTip * sin(uTime * 7.0 + aBird.z * 10.0) * 0.55;
                vec3 p = at + (side * position.x + vec3(0.0, flap, 0.0) + fwd * position.z) * 0.75;
                vec4 mv = viewMatrix * vec4(p, 1.0);
                gl_Position = projectionMatrix * mv;
                vView = mv.xyz;
            }`,
        fragmentShader: /* glsl */ `
            uniform vec3 uBody;
            uniform vec3 uFog;
            uniform float uFogNear;
            uniform float uFogFar;
            varying vec3 vView;
            void main() {
                gl_FragColor = vec4(mix(uBody, uFog, smoothstep(uFogNear, uFogFar, length(vView))), 1.0);
                #include <tonemapping_fragment>
                #include <colorspace_fragment>
            }`,
    })
    const mesh = new Mesh(g, material)
    mesh.frustumCulled = false
    return mesh
}
