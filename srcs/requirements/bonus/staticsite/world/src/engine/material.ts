// One shader for every voxel mesh. The broad light (sky, ground, a key) is
// computed per vertex from the face normal (six possible values) and baked AO:
// on SwiftShader an unlit material ran 26–33% faster than Lambert (research,
// 2026-10-28). What makes it a lit place is per pixel, and bounded: the
// MAX_LAMPS nearest lamps (lamps.ts) pool light on the street and the walls,
// glass and brass reflect the sky and catch the lamps, every voxel has its own
// shade, and the fog brightens toward the key light. Colour comes from a
// 16-entry palette, so a level re-tints by uniforms alone; emissive materials
// are HDR (above 1) so the bloom pass picks them out.
//
// The city's fold ("the street rolls up into a wall, then overhead") happens
// here too: past the hinge Z0, positions roll up a cylinder of radius R by up
// to uFold radians and continue along its tangent. The broad light follows the
// folded normal; lamps, reflections and the view are worked out in the
// unfolded grid frame (vLocal, vNormal0), so the pools of light fold with the
// street, and the turning corridor's lamps turn with it.
import { Color, ShaderMaterial, Vector3, Vector4 } from 'three'
import { flickerAt, MAX_FLICKERS, MAX_LAMPS, type Lamp } from './lamps'
import { MAT, MATERIAL_COUNT } from './voxels'

export type Palette = Record<number, string>

export type Light = {
    sky: string
    skyI: number
    ground: string
    groundI: number
    key: string
    keyI: number
    keyDir: [number, number, number]
    ambient: number
    fog: string
    fogNear: number
    fogFar: number
    lit: number // share of glass panes that stay dark (1 = none lit)
    glow: string
    scatter: number // how much the fog brightens toward the key light
    reflectTop: string // what glass and brass reflect: the sky, high and low
    reflectLow: string
}

/** The fold, for every shader that has to bend with the street (voxels, the
 *  traffic): uFold radians of roll past the hinge uZ0, radius uR. */
export const FOLD_GLSL = /* glsl */ `
uniform float uFold;
uniform float uZ0;
uniform float uR;

float foldAngle(vec3 p) { return clamp((p.z - uZ0) / uR, 0.0, uFold); }

vec3 foldPos(vec3 p) {
    float d = p.z - uZ0;
    if (d <= 0.0 || uFold <= 0.0) return p;
    float a = foldAngle(p);
    float e = max(d - uR * uFold, 0.0);
    float r = uR - p.y;
    return vec3(p.x, uR - r * cos(a) + e * sin(a), uZ0 + r * sin(a) + e * cos(a));
}

vec3 foldDir(vec3 n, float a) { return vec3(n.x, n.z * sin(a) + n.y * cos(a), n.z * cos(a) - n.y * sin(a)); }
`

const vertex = /* glsl */ `
attribute float aAo;
attribute float aFace;
attribute float aMat;
uniform vec3 uPalette[${MATERIAL_COUNT}];
uniform float uEmit[${MATERIAL_COUNT}];
uniform vec3 uSky;
uniform vec3 uGround;
uniform vec3 uKey;
uniform vec3 uKeyDir;
uniform float uAmbient;
uniform float uLocalLight;
varying vec3 vColor;
varying vec3 vAlbedo;
varying float vEmit;
varying vec3 vLocal;
varying vec3 vNormal0;
varying float vMat;
varying vec3 vView;
varying vec3 vWorld;

const vec3 NORMALS[6] = vec3[6](vec3(1., 0., 0.), vec3(-1., 0., 0.), vec3(0., 1., 0.), vec3(0., -1., 0.), vec3(0., 0., 1.), vec3(0., 0., -1.));

${FOLD_GLSL}

void main() {
    int f = int(aFace + 0.5);
    int m = int(aMat + 0.5);
    vec3 n0 = NORMALS[f];
    vec3 p = uFold > 0.0 ? foldPos(position) : position;
    vec3 nf = uFold > 0.0 ? foldDir(n0, foldAngle(position)) : n0;
    vec4 world = modelMatrix * vec4(p, 1.0);
    vec4 mv = viewMatrix * world;
    gl_Position = projectionMatrix * mv;
    float ao = aAo < 0.5 ? 0.45 : aAo < 1.5 ? 0.65 : aAo < 2.5 ? 0.82 : 1.0;
    // The broad light follows the folded face (the street rolled overhead
    // faces down and darkens); the turning corridor carries its own.
    vec3 wn = uLocalLight > 0.5 ? nf : normalize(mat3(modelMatrix) * nf);
    vec3 light = uSky * max(wn.y, 0.0) + uGround * max(-wn.y, 0.0) + uKey * max(dot(wn, uKeyDir), 0.0) + vec3(uAmbient);
    vec3 base = uPalette[m];
    float e = uEmit[m];
    vEmit = e;
    vAlbedo = base * ao;
    vColor = e > 0.0 ? base * e : vAlbedo * light;
    vLocal = position;
    vNormal0 = n0;
    vMat = aMat;
    // The view-space position, not its length: a greedy quad can run the
    // length of a street, and a length interpolated between its corners is
    // far too large halfway along (the near pavement came out fully fogged).
    vView = mv.xyz;
    vWorld = world.xyz;
}
`

const fragment = /* glsl */ `
#define MAX_LAMPS ${MAX_LAMPS}
#define MAX_FLICKERS ${MAX_FLICKERS}
uniform vec3 uFog;
uniform float uFogNear;
uniform float uFogFar;
uniform float uLit;
uniform vec3 uGlow;
uniform vec3 uKey;
uniform vec3 uKeyDir;
uniform vec3 uKeyWorld;
uniform float uScatter;
uniform vec3 uReflectTop;
uniform vec3 uReflectLow;
uniform vec3 uCamLocal;
uniform float uTime;
uniform int uLampCount;
uniform vec3 uLampPos[MAX_LAMPS];
uniform vec3 uLampColor[MAX_LAMPS];
uniform float uLampRange[MAX_LAMPS];
uniform int uFlickerCount;
uniform vec4 uFlicker[MAX_FLICKERS];
varying vec3 vColor;
varying vec3 vAlbedo;
varying float vEmit;
varying vec3 vLocal;
varying vec3 vNormal0;
varying float vMat;
varying vec3 vView;
varying vec3 vWorld;

float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }

void main() {
    vec3 c = vColor;
    vec3 n = vNormal0;
    vec3 cell = floor(vLocal - n * 0.5);
    vec3 V = normalize(uCamLocal - vLocal);
    bool glass = abs(vMat - ${MAT.glass}.0) < 0.5;
    bool metal = abs(vMat - ${MAT.brass}.0) < 0.5;

    // a failing lamp's bulb dims with the light it casts (setLamps)
    if (vEmit > 0.0) {
        for (int i = 0; i < MAX_FLICKERS; i++) {
            if (i >= uFlickerCount) break;
            if (all(lessThan(abs(cell - uFlicker[i].xyz), vec3(0.5)))) c *= uFlicker[i].w;
        }
    }
    if (vEmit <= 0.0) {
        // every voxel its own shade: one flat colour per material read as plastic
        float tone = 0.93 + 0.14 * hash(cell + 0.37);
        c *= tone;
        // the nearest lamps, in the grid frame
        vec3 pool = vec3(0.0);
        vec3 shine = vec3(0.0);
        for (int i = 0; i < MAX_LAMPS; i++) {
            if (i >= uLampCount) break;
            vec3 L = uLampPos[i] - vLocal;
            float d = length(L);
            L /= d;
            float w = clamp(1.0 - pow(d / uLampRange[i], 4.0), 0.0, 1.0);
            float fall = w * w / (1.0 + d * d);
            pool += uLampColor[i] * max(dot(n, L), 0.0) * fall;
            shine += uLampColor[i] * pow(max(dot(reflect(-L, n), V), 0.0), 48.0) * fall;
        }
        c += vAlbedo * tone * pool;
        if (glass || metal) {
            // glass and brass reflect the sky at a grazing angle, and catch
            // the key light and the lamps as highlights
            float fres = 0.04 + 0.96 * pow(1.0 - max(dot(n, V), 0.0), 4.0);
            vec3 R = reflect(-V, n);
            vec3 sky = mix(uReflectLow, uReflectTop, smoothstep(-0.1, 0.6, R.y));
            float k = metal ? 0.35 : 0.6;
            c = mix(c, sky, fres * k) + shine * (metal ? 2.2 : 1.4);
            c += uKey * pow(max(dot(R, uKeyDir), 0.0), metal ? 24.0 : 90.0) * (metal ? 1.4 : 2.5);
        }
    }

    // Glass curtain walls: a lattice of panes on the vertical faces, a share
    // of them lit, a few switching on and off over the evening. The cell comes
    // from the unfolded position, half a voxel inside the face, so the pattern
    // does not slide when the street folds.
    if (glass && abs(n.y) < 0.5) {
        vec2 w = abs(n.x) > 0.5 ? vLocal.zy : vLocal.xy;
        vec2 f = fract(w);
        float pane = step(0.16, f.x) * step(f.x, 0.84) * step(0.2, f.y) * step(f.y, 0.8);
        float phase = hash(cell + 7.1) > 0.88 ? floor(uTime / (9.0 + 14.0 * hash(cell + 2.3)) + hash(cell)) : 0.0;
        float lit = step(uLit, hash(cell + phase * 0.173));
        c = mix(c, c * 0.5, pane) + uGlow * pane * lit * (0.9 + 0.5 * hash(cell + 4.4));
    }

    // fog, brighter toward the key light: the haze is lit from one side
    vec3 dir = normalize(vWorld - cameraPosition);
    vec3 fog = uFog + uKey * uScatter * pow(max(dot(dir, uKeyWorld), 0.0), 6.0);
    float fogged = smoothstep(uFogNear, uFogFar, length(vView));
    c = mix(c, fog, fogged);
    // 8-bit output bands the long fog gradients: one step of noise hides it.
    c += (hash(vec3(gl_FragCoord.xy, 1.0)) - 0.5) / 255.0;
    gl_FragColor = vec4(c, 1.0);
    #include <tonemapping_fragment>
    #include <colorspace_fragment>
}
`

export function voxelMaterial(palette: Palette, emissive: Record<number, number>, light: Light): ShaderMaterial {
    const pal = Array.from({ length: MATERIAL_COUNT }, (_, i) => new Color(palette[i] ?? '#ff00ff'))
    const emit = Array.from({ length: MATERIAL_COUNT }, (_, i) => emissive[i] ?? 0)
    const material = new ShaderMaterial({
        vertexShader: vertex,
        fragmentShader: fragment,
        uniforms: {
            uPalette: { value: pal },
            uEmit: { value: emit },
            uSky: { value: new Color() },
            uGround: { value: new Color() },
            uKey: { value: new Color() },
            uKeyDir: { value: new Vector3() },
            uKeyWorld: { value: new Vector3() },
            uAmbient: { value: 0 },
            uFog: { value: new Color() },
            uFogNear: { value: 0 },
            uFogFar: { value: 1 },
            uScatter: { value: 0 },
            uLit: { value: 1 },
            uGlow: { value: new Color() },
            uReflectTop: { value: new Color() },
            uReflectLow: { value: new Color() },
            uCamLocal: { value: new Vector3() },
            uTime: { value: 0 },
            uFold: { value: 0 },
            uZ0: { value: 0 },
            uR: { value: 30 },
            uLocalLight: { value: 0 },
            uLampCount: { value: 0 },
            uLampPos: { value: Array.from({ length: MAX_LAMPS }, () => new Vector3()) },
            uLampColor: { value: Array.from({ length: MAX_LAMPS }, () => new Color()) },
            uLampRange: { value: new Array<number>(MAX_LAMPS).fill(1) },
            uFlickerCount: { value: 0 },
            uFlicker: { value: Array.from({ length: MAX_FLICKERS }, () => new Vector4()) },
        },
    })
    setLight(material, light)
    return material
}

export function setLight(material: ShaderMaterial, l: Light): void {
    const u = material.uniforms
    u.uSky.value.set(l.sky).multiplyScalar(l.skyI)
    u.uGround.value.set(l.ground).multiplyScalar(l.groundI)
    u.uKey.value.set(l.key).multiplyScalar(l.keyI)
    u.uKeyDir.value.set(...l.keyDir).normalize()
    u.uKeyWorld.value.copy(u.uKeyDir.value)
    u.uAmbient.value = l.ambient
    u.uFog.value.set(l.fog)
    u.uFogNear.value = l.fogNear
    u.uFogFar.value = l.fogFar
    u.uScatter.value = l.scatter
    u.uLit.value = l.lit
    u.uGlow.value.set(l.glow)
    u.uReflectTop.value.set(l.reflectTop)
    u.uReflectLow.value.set(l.reflectLow)
}

/** Hand the shader the lamps nearest the camera (already picked), and the
 *  state of every failing lamp in the level at time t (null: hold steady). */
export function setLamps(material: ShaderMaterial, nearest: Lamp[], all: Lamp[], limit: number, t: number | null): void {
    const u = material.uniforms
    const level = (l: Lamp) => (l.flicker && t !== null ? flickerAt(l.flicker.seed, t) : 1)
    const count = Math.min(nearest.length, limit)
    for (let i = 0; i < count; i++) {
        const l = nearest[i]
        u.uLampPos.value[i].set(l.x, l.y, l.z)
        u.uLampColor.value[i].set(l.color).multiplyScalar(l.power * level(l))
        u.uLampRange.value[i] = l.range
    }
    u.uLampCount.value = count
    let f = 0
    for (const l of all) {
        if (!l.flicker || f >= MAX_FLICKERS) continue
        u.uFlicker.value[f++].set(...l.flicker.cell, level(l))
    }
    u.uFlickerCount.value = f
}
