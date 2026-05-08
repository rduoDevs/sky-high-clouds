//structs
struct Camera {
    position : vec3<f32>,
    rotation : vec3<f32>,
    fov      : f32
};

struct Material {
    color           : vec3<f32>,
    smoothness      : f32,
    specular        : f32,
    emission        : f32,
    emissionColor   : vec3<f32>,
    refractiveIndex : f32
};

struct Sphere {
    center   : vec3<f32>,
    radius   : f32,
    material : Material
};

struct World {
    spheres : array<Sphere, 2>
};

struct FrameUniform {
    frameCount : u32,
    pad_0      : u32,
    pad_1      : u32,
    pad_2      : u32
};

struct Ray {
    origin    : vec3<f32>,
    direction : vec3<f32>
};

struct Intersection {
    distance   : f32,
    normal     : vec3<f32>,
    isBackFace : bool,
    material   : Material
};

struct Settings {
    maxBounces          : u32,
    antiAliasingSamples : u32,
    scatteringOrderMask : u32,
    pad_0               : u32
};

struct Triangle {
    v0 : vec3<f32>, pad0 : f32,
    v1 : vec3<f32>, pad1 : f32,
    v2 : vec3<f32>, pad2 : f32,
    normal : vec3<f32>, pad3 : f32
};

struct CloudMesh {
    boundsMin      : vec3<f32>, pad0 : f32,
    boundsMax      : vec3<f32>, pad1 : f32,
    triangleOffset : u32,
    triangleCount  : u32,
    shellThickness : f32,
    pad2           : f32
};

struct TriHit { t: f32, n: vec3<f32> };

struct InsideHit {
    t   : f32,
    n   : vec3<f32>,
    hit : bool
};

struct MeshHit {
    tEntry : f32,
    tExit  : f32,
    nEntry : vec3<f32>,
    nExit  : vec3<f32>,
    hit    : bool
};

struct OrderSetInfo {
    minOrder    : f32,
    maxOrder    : f32,
    isIsotropic : bool
};

struct Collector {
    center : vec3<f32>,
    sigma  : f32
};

struct CollectorResult {
    worldPos : vec3<f32>,
    sigma    : f32,
    T        : f32
};

//binds

@group(0) @binding(0) var<uniform>       camera            : Camera;
@group(0) @binding(1) var<storage, read> world             : World;
@group(0) @binding(2) var                outputTex         : texture_storage_2d<rgba8unorm, write>;
@group(0) @binding(3) var<uniform>       settings          : Settings;
@group(0) @binding(4) var<uniform>       frameData         : FrameUniform;
@group(0) @binding(5) var<storage, read> triangles         : array<Triangle>;
@group(0) @binding(6) var<uniform>       cloudMesh         : CloudMesh;
@group(0) @binding(7) var<storage, read> higherOrderTables : array<f32>;

//const

const Infinity     = 1e6f;
const GroundYLevel = -1.0f;
const EPSILON      = 1e-4f;
const PI           = 3.14159265359f;
const TWO_PI       = 6.28318530718f;

const EXTINCTION_FACTOR = 0.017f;
const MIE_G      = 0.75f;

const NUM_MS_SETS = 8u;

const SUN_DIR       = vec3<f32>(0.577, 0.816, 0.0);
const SUN_COLOR     = vec3<f32>(1.0,0.98,0.96);
const SUN_INTENSITY = 3.0f;
const SKY_COLOR_TOP = vec3<f32>(0.35, 0.55, 0.95);
const SKY_COLOR_BOT = vec3<f32>(0.2, 0.1, 0.0);

const SCALE: f32 = 100.0;

const HO_W           : u32 = 64u;
const HO_H           : u32 = 64u;
const HO_LAYER_COUNT : u32 = 49u;
const HO_ORDER_COUNT : u32 = 7u;

// Domain bounds from LogGaussAniso_Params_*.txt, ordered as: 1, 2, 3, 4-5, 6-8, 9-14, 15+
const T_MIN_BY_ORDER = array<f32, 7>(50.0, 50.0, 50.0, 10.0, 10.0,   50.0,   50.0);
const T_MAX_BY_ORDER = array<f32, 7>(500.0, 500.0, 500.0, 500.0, 500.0, 1000.0, 5000.0);
const MU_V_MIN     : f32 = -1.0;
const MU_V_MAX     : f32 =  1.0;
const MU_L_MIN     : f32 =  0.05;
const MU_L_MAX     : f32 =  1.0;
const PSI_COS_MIN  : f32 = -1.0;
const PSI_COS_MAX  : f32 =  1.0;

const MAX_COLLECTOR_ITERS = 10u;
const SS_SAMPLES          = 16u;
const OPACITY_SAMPLES     = 32u;

// ---------------------------------------------------------------------------
//  Random / noise utilities
// ---------------------------------------------------------------------------

fn pcg(v: u32) -> u32 {
    let state = v * 747796405u + 2891336453u;
    let word  = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

fn rand2(seed: ptr<function, u32>) -> vec2<f32> {
    *seed = pcg(*seed); let a = *seed;
    *seed = pcg(*seed); let b = *seed;
    return vec2<f32>(f32(a) / 4294967296.0, f32(b) / 4294967296.0);
}

fn rand1(seed: ptr<function, u32>) -> f32 {
    *seed = pcg(*seed);
    return f32(*seed) / 4294967296.0;
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xxy + p3.yzz) * p3.zxy);
}

fn hash1(p: vec3<f32>) -> f32 { return hash3(p).x; }

fn perlin3D(p: vec3<f32>) -> f32 {
    let pi = floor(p);
    let pf = fract(p);
    let u  = pf * pf * (3.0 - 2.0 * pf);

    let c000 = dot(hash3(pi + vec3<f32>(0.0, 0.0, 0.0)) - 0.5, pf - vec3<f32>(0.0, 0.0, 0.0));
    let c001 = dot(hash3(pi + vec3<f32>(0.0, 0.0, 1.0)) - 0.5, pf - vec3<f32>(0.0, 0.0, 1.0));
    let c010 = dot(hash3(pi + vec3<f32>(0.0, 1.0, 0.0)) - 0.5, pf - vec3<f32>(0.0, 1.0, 0.0));
    let c011 = dot(hash3(pi + vec3<f32>(0.0, 1.0, 1.0)) - 0.5, pf - vec3<f32>(0.0, 1.0, 1.0));
    let c100 = dot(hash3(pi + vec3<f32>(1.0, 0.0, 0.0)) - 0.5, pf - vec3<f32>(1.0, 0.0, 0.0));
    let c101 = dot(hash3(pi + vec3<f32>(1.0, 0.0, 1.0)) - 0.5, pf - vec3<f32>(1.0, 0.0, 1.0));
    let c110 = dot(hash3(pi + vec3<f32>(1.0, 1.0, 0.0)) - 0.5, pf - vec3<f32>(1.0, 1.0, 0.0));
    let c111 = dot(hash3(pi + vec3<f32>(1.0, 1.0, 1.0)) - 0.5, pf - vec3<f32>(1.0, 1.0, 1.0));

    let x00 = mix(c000, c100, u.x);
    let x01 = mix(c001, c101, u.x);
    let x10 = mix(c010, c110, u.x);
    let x11 = mix(c011, c111, u.x);
    let y0  = mix(x00, x10, u.y);
    let y1  = mix(x01, x11, u.y);
    return mix(y0, y1, u.z);
}

fn smoothNoise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash1(i + vec3<f32>(0,0,0)), hash1(i + vec3<f32>(1,0,0)), u.x),
            mix(hash1(i + vec3<f32>(0,1,0)), hash1(i + vec3<f32>(1,1,0)), u.x), u.y),
        mix(mix(hash1(i + vec3<f32>(0,0,1)), hash1(i + vec3<f32>(1,0,1)), u.x),
            mix(hash1(i + vec3<f32>(0,1,1)), hash1(i + vec3<f32>(1,1,1)), u.x), u.y),
        u.z
    );
}

fn fbm(p: vec3<f32>) -> f32 {
    var val  = 0.0f;
    var amp  = 0.5f;
    var freq = 1.0f;
    for (var i = 0; i < 5; i++) {
        val  += amp * perlin3D(p * freq);
        amp  *= 0.5;
        freq *= 2.1;
    }
    return val;
}

fn worley3D(p: vec3<f32>) -> f32 {
    let pi = floor(p);
    let pf = fract(p);

    var minDist = 1.0;

    for (var x = -1; x <= 1; x++) {
        for (var y = -1; y <= 1; y++) {
            for (var z = -1; z <= 1; z++) {
                let neighbor = vec3<f32>(f32(x), f32(y), f32(z));
                let cellPos = pi + neighbor;
                let randomPoint = hash3(cellPos);

                let diff = neighbor + randomPoint - pf;
                let dist = length(diff);

                minDist = min(minDist, dist);
            }
        }
    }

    return clamp(minDist, 0.0, 1.0);
}

fn worleyFbm(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    var norm = 0.0;

    for (var i = 0; i < 3; i++) {
        value += amplitude * worley3D(p * frequency);
        norm += amplitude;

        frequency *= 2.0;
        amplitude *= 0.5;
    }

    return clamp(value / max(norm, 1e-5), 0.0, 1.0);
}


// ---------------------------------------------------------------------------
//  Phase functions
// ---------------------------------------------------------------------------

fn phaseHG(cosTheta: f32, g: f32) -> f32 {
    let g2    = g * g;
    let denom = 1.0 + g2 - 2.0 * g * cosTheta;
    return (1.0 - g2) / (4.0 * PI * pow(denom, 1.5));
}

fn miePhaseFn(cosTheta: f32) -> f32 {
    let peak = 0.51 * phaseHG(cosTheta, 0.99);
    let lobe = 0.48 * phaseHG(cosTheta, 0.85);
    let back = 0.01 * phaseHG(cosTheta, -0.3);
    return peak + lobe + back;
}

fn miePhaseFnRGB(cosTheta: f32) -> vec3<f32> {
    return vec3<f32>(
        miePhaseFn(cosTheta) * 1.0,
        miePhaseFn(cosTheta) * 0.98,
        miePhaseFn(cosTheta) * 0.95
    );
}

// ---------------------------------------------------------------------------
//  Ray-triangle / mesh intersection
// ---------------------------------------------------------------------------

fn rayTriIntersect(ray: Ray, tri: Triangle) -> TriHit {
    let e1 = tri.v1 - tri.v0;
    let e2 = tri.v2 - tri.v0;
    let h  = cross(ray.direction, e2);
    let a  = dot(e1, h);
    if (abs(a) < EPSILON) { return TriHit(Infinity, vec3<f32>(0.0)); }
    let f  = 1.0 / a;
    let s  = ray.origin - tri.v0;
    let u  = f * dot(s, h);
    if (u < 0.0 || u > 1.0) { return TriHit(Infinity, vec3<f32>(0.0)); }
    let q  = cross(s, e1);
    let v  = f * dot(ray.direction, q);
    if (v < 0.0 || u + v > 1.0) { return TriHit(Infinity, vec3<f32>(0.0)); }
    let t  = f * dot(e2, q);
    if (t < EPSILON) { return TriHit(Infinity, vec3<f32>(0.0)); }
    return TriHit(t, tri.normal);
}

fn intersectFromInside(ray: Ray) -> InsideHit {
    var tFirst = Infinity;
    var nFirst = vec3<f32>(0.0);
    let offset = cloudMesh.triangleOffset;
    let count  = cloudMesh.triangleCount;
    for (var i = 0u; i < count; i++) {
        let tri = triangles[offset + i];
        let hit = rayTriIntersect(ray, tri);
        if (hit.t < tFirst) {
            tFirst = hit.t;
            nFirst = hit.n;
        }
    }
    return InsideHit(tFirst, nFirst, tFirst < Infinity);
}

fn intersectCloudMesh(ray: Ray) -> MeshHit {
    var tEntry = Infinity;
    var tExit  = -Infinity;
    var nEntry = vec3<f32>(0.0);
    var nExit  = vec3<f32>(0.0);
    let offset = cloudMesh.triangleOffset;
    let count  = cloudMesh.triangleCount;

    for (var i = 0u; i < count; i++) {
        let tri = triangles[offset + i];
        let hit = rayTriIntersect(ray, tri);
        if (hit.t < Infinity) {
            if (dot(hit.n, ray.direction) < 0.0) {
                if (hit.t < tEntry) { tEntry = hit.t; nEntry = hit.n; }
            } else {
                if (hit.t > tExit)  { tExit  = hit.t; nExit  = hit.n; }
            }
        }
    }

    if (tEntry > tExit || tExit < 0.0) {
        let inside = intersectFromInside(ray);
        if (!inside.hit) {
            return MeshHit(Infinity, -Infinity, vec3<f32>(0.0), vec3<f32>(0.0), false);
        }
        return MeshHit(inside.t, inside.t, inside.n, inside.n, true);
    }

    return MeshHit(tEntry, tExit, nEntry, nExit, true);
}

// ---------------------------------------------------------------------------
//  Hypertexture density / extinction / shadow
// ---------------------------------------------------------------------------


fn closestPointOnTriangle(
    p : vec3<f32>,
    a : vec3<f32>,
    b : vec3<f32>,
    c : vec3<f32>
) -> vec3<f32> {

    let ab = b - a;
    let ac = c - a;
    let ap = p - a;

    let d1 = dot(ab, ap);
    let d2 = dot(ac, ap);

    // barycentric region outside A
    if (d1 <= 0.0 && d2 <= 0.0) {
        return a;
    }

    let bp = p - b;
    let d3 = dot(ab, bp);
    let d4 = dot(ac, bp);

    // outside B
    if (d3 >= 0.0 && d4 <= d3) {
        return b;
    }

    // edge AB
    let vc = d1 * d4 - d3 * d2;
    if (vc <= 0.0 && d1 >= 0.0 && d3 <= 0.0) {
        let v = d1 / (d1 - d3);
        return a + v * ab;
    }

    let cp = p - c;
    let d5 = dot(ab, cp);
    let d6 = dot(ac, cp);

    // outside C
    if (d6 >= 0.0 && d5 <= d6) {
        return c;
    }

    // edge AC
    let vb = d5 * d2 - d1 * d6;
    if (vb <= 0.0 && d2 >= 0.0 && d6 <= 0.0) {
        let w = d2 / (d2 - d6);
        return a + w * ac;
    }

    // edge BC
    let va = d3 * d6 - d5 * d4;
    if (va <= 0.0 && (d4 - d3) >= 0.0 && (d5 - d6) >= 0.0) {
        let w = (d4 - d3) / ((d4 - d3) + (d5 - d6));
        return b + w * (c - b);
    }

    // inside face region
    let denom = 1.0 / (va + vb + vc);
    let v = vb * denom;
    let w = vc * denom;

    return a + ab * v + ac * w;
}

fn pointInsideCloudMesh(p: vec3<f32>) -> bool {
    // Cast in a non-axis-aligned direction to reduce edge/vertex degeneracies.
    let dir = normalize(vec3<f32>(0.754877, 0.569840, 0.322570));
    let ray = Ray(p + dir * EPSILON, dir);

    var hits = 0u;
    let offset = cloudMesh.triangleOffset;
    let count  = cloudMesh.triangleCount;

    for (var i = 0u; i < count; i++) {
        let tri = triangles[offset + i];
        let hit = rayTriIntersect(ray, tri);

        if (hit.t < Infinity) {
            hits += 1u;
        }
    }

    return (hits & 1u) == 1u;
}

fn distToCloudSurface(p: vec3<f32>) -> f32 {
    var minDist = Infinity;

    let offset = cloudMesh.triangleOffset;
    let count  = cloudMesh.triangleCount;

    for (var i = 0u; i < count; i++) {
        let tri = triangles[offset + i];
        let closest = closestPointOnTriangle(p, tri.v0, tri.v1, tri.v2);
        let dist = distance(p, closest);

        if (dist < minDist) {
            minDist = dist;
        }
    }

    if (pointInsideCloudMesh(p)) {
        return -minDist;
    }

    return minDist;
}


fn sigmoid(x: f32) -> f32 {
    return 1.0 / (1.0 + exp(-x * 5.0));
}

fn getTime() -> f32 {
    return f32(frameData.frameCount) * 0.016667;
}

fn cloudDensity(p: vec3<f32>) -> f32 {
    let time = getTime();

    let driftFast = vec3<f32>(time * 0.08, time * 0.02, time * 0.05) * vec3<f32>(10.0,10.0,10.0);
    let driftSlow = vec3<f32>(time * 0.03, time * 0.015, time * 0.02);

    let D = distToCloudSurface(p);
    let h = max(cloudMesh.shellThickness, 0.01);

    if (D > 0.0) {
        return 0.0;
    }

    let depth = -D;
    let edge = clamp(depth / h, 0.0, 1.0);

    let macroPerlin = clamp(0.5 + fbm(p * 0.18 + driftFast) * 1.35, 0.0, 1.0);
    let macroWorley = 1.0 - worleyFbm(p * 0.2 + driftFast * 0.6);
    let billow = clamp(mix(macroPerlin, macroWorley, 0.5), 0.0, 1.0);

    let shellPerlin = fbm(p * (4.0 / h) + driftFast) * 2.0 - 1.0;
    let shellWorley = 1.0 - worleyFbm(p * (1.7 / h) + driftFast * 0.8);

    var rho = 0.0;

    if (depth < h) {
        let shellNoise = shellPerlin * 0.85 + shellWorley * 0.75;
        rho = sigmoid(edge * 3.0 + shellNoise * 1.25);
    } else {
        // Avoid a fully saturated core; keep some cellular variation inside.
        rho = 0.65 + billow * 0.35;
    }

    // Erode mostly near the boundary, preserving the core.
    let erosion = (1.0 - shellWorley) * (1.0 - edge) * 0.35;
    rho = max(rho - erosion, 0.0);

    let breathe = 0.85 + 0.15 * sin(time * 0.30);
    rho *= mix(0.75, 1.25, billow) * breathe;

    return clamp(rho, 0.0, 1.0);
}


fn extinction(p: vec3<f32>) -> f32 {
    return EXTINCTION_FACTOR * cloudDensity(p) * SCALE;
}

fn shadowOpticalDepth(p: vec3<f32>, wL: vec3<f32>) -> f32 {
    let shadowRay = Ray(p + wL * EPSILON, wL);
    let exit      = intersectFromInside(shadowRay);
    if (!exit.hit) { return 0.0; }

    const SAMPLES = 8u;
    let stepSize = exit.t / f32(SAMPLES);
    var depth    = 0.0f;
    for (var i = 0u; i < SAMPLES; i++) {
        let s    = (f32(i) + 0.5) * stepSize;
        let pSmp = p + wL * s;
        depth   += extinction(pSmp) * stepSize;
    }
    return depth;
}

// ---------------------------------------------------------------------------
//  Slab geometry (paper §7 — depth d from lit side, slab thickness t)
// ---------------------------------------------------------------------------

fn slabGeometry(p: vec3<f32>, wL: vec3<f32>) -> vec4<f32> {
    let toLit    = intersectFromInside(Ray(p + wL * EPSILON,  wL));
    let toShadow = intersectFromInside(Ray(p - wL * EPSILON, -wL));

    if (!toLit.hit || !toShadow.hit) {
        return vec4<f32>(0.0, 1.0, 1.0, 0.0);
    }

    let dToLit    = toLit.t;
    let dToShadow = toShadow.t;
    let t         = dToLit + dToShadow;
    let d         = dToLit;
    let cosPhi_L  = abs(dot(wL, toLit.n));
    return vec4<f32>(d, t, cosPhi_L, 1.0);
}

// ---------------------------------------------------------------------------
//  Canonical Transport Function — table sampling and analytic form (§5)
// ---------------------------------------------------------------------------

fn orderSetInfo(setIdx: u32) -> OrderSetInfo {
    switch setIdx {
        case 0u: { return OrderSetInfo(2.0,  2.0,  false); }
        case 1u: { return OrderSetInfo(3.0,  4.0,  false); }
        case 2u: { return OrderSetInfo(5.0,  6.0,  false); }
        case 3u: { return OrderSetInfo(7.0,  8.0,  false); }
        case 4u: { return OrderSetInfo(9.0,  12.0, false); }
        case 5u: { return OrderSetInfo(13.0, 18.0, false); }
        case 6u: { return OrderSetInfo(19.0, 30.0, false); }
        default: { return OrderSetInfo(31.0, 1e6,  true);  }
    }
}

fn normalizeToUnit(v: f32, minV: f32, maxV: f32) -> f32 {
    let denom = max(maxV - minV, 1e-6);
    return clamp((v - minV) / denom, 0.0, 1.0);
}

fn clampTableIdx(tableIdx: u32) -> u32 {
    return min(tableIdx, HO_ORDER_COUNT - 1u);
}

// Tables encode order bins {1, 2, 3, 4-5, 6-8, 9-14, 15+}.
// MS skips order 1 (single scattering), so set 0 → table 1.
fn setToTableIdx(setIdx: u32) -> u32 {
    return clampTableIdx(setIdx + 1u);
}

fn t_to_uv_for_table(tableIdx: u32, t: f32) -> f32 {
    let idx = clampTableIdx(tableIdx);
    return normalizeToUnit(t, T_MIN_BY_ORDER[idx] / SCALE, T_MAX_BY_ORDER[idx] / SCALE);
}

fn mu_V_to_uv(mu_V: f32)   -> f32 { return normalizeToUnit(mu_V,        MU_V_MIN,    MU_V_MAX); }
fn mu_L_to_uv(mu_L: f32)   -> f32 { return normalizeToUnit(mu_L,        MU_L_MIN,    MU_L_MAX); }
fn theta_to_uv(theta: f32) -> f32 { return normalizeToUnit(-cos(theta), PSI_COS_MIN, PSI_COS_MAX); }

fn tableAt(layer: u32, x: u32, y: u32) -> f32 {
    let safeLayer = min(layer, HO_LAYER_COUNT - 1u);
    let idx = safeLayer * (HO_W * HO_H) + y * HO_W + x;
    return higherOrderTables[idx];
}

fn sampleFromTable(layer: u32, uv: vec2<f32>) -> f32 {
    let u = clamp(uv.x, 0.0, 1.0);
    let v = clamp(uv.y, 0.0, 1.0);
    let fx = u * f32(HO_W - 1u);
    let fy = v * f32(HO_H - 1u);
    let x0 = u32(floor(fx));
    let y0 = u32(floor(fy));
    let x1 = min(x0 + 1u, HO_W - 1u);
    let y1 = min(y0 + 1u, HO_H - 1u);
    let tx = fx - f32(x0);
    let ty = fy - f32(y0);
    let v00 = tableAt(layer, x0, y0);
    let v10 = tableAt(layer, x1, y0);
    let v01 = tableAt(layer, x0, y1);
    let v11 = tableAt(layer, x1, y1);
    let vx0 = mix(v00, v10, tx);
    let vx1 = mix(v01, v11, tx);
    return mix(vx0, vx1, ty);
}

fn sampleTexA(tableIdx: u32, t: f32, mu_V: f32) -> f32 {
    let uv = vec2<f32>(t_to_uv_for_table(tableIdx, t), mu_V_to_uv(mu_V));
    return sampleFromTable(tableIdx, uv);
}

fn sampleTexB(tableIdx: u32, t: f32, mu_V: f32, mu_L: f32) -> f32 {
    let tu  = t_to_uv_for_table(tableIdx, t);
    let uv1 = vec2<f32>(tu, mu_V_to_uv(mu_V));
    let uv2 = vec2<f32>(tu, mu_L_to_uv(mu_L));
    return sampleFromTable(7u  + tableIdx, uv1)
         - sampleFromTable(14u + tableIdx, uv2);
}

fn sampleTexC(tableIdx: u32, t: f32, mu_V: f32) -> f32 {
    let uv = vec2<f32>(t_to_uv_for_table(tableIdx, t), mu_V_to_uv(mu_V));
    return sampleFromTable(21u + tableIdx, uv);
}

fn sampleTexD(tableIdx: u32, t: f32, mu_V: f32) -> f32 {
    let uv = vec2<f32>(t_to_uv_for_table(tableIdx, t), mu_V_to_uv(mu_V));
    return sampleFromTable(28u + tableIdx, uv);
}

fn sampleTexP(tableIdx: u32, t: f32, theta: f32) -> f32 {
    let uv = vec2<f32>(t_to_uv_for_table(tableIdx, t), theta_to_uv(theta));
    return sampleFromTable(35u + tableIdx, uv);
}

fn sampleTexX(tableIdx: u32, t: f32, mu_L: f32) -> f32 {
    let uv = vec2<f32>(t_to_uv_for_table(tableIdx, t), mu_L_to_uv(mu_L));
    return sampleFromTable(42u + tableIdx, uv);
}

fn canonicalT(V: f32, L: f32, cosTheta: f32, d: f32, t: f32, setIdx: u32) -> f32 {
    let tableIdx = setToTableIdx(setIdx);

    let A = sampleTexA(tableIdx, t, V);
    let B = sampleTexB(tableIdx, t, V, L);
    let C = max(sampleTexC(tableIdx, t, V), 0.01);
    let D = max(sampleTexD(tableIdx, t, V), 0.01);
    let P = sampleTexP(tableIdx, t, acos(clamp(cosTheta, -1.0, 1.0)));
    let X = sampleTexX(tableIdx, t, L);

    let exponent  = log(d + D) / (2.0 * C * C);
    let logDen    = max(log(B + D), EPSILON);
    let Lsafe     = max(L, EPSILON);
    let powerTerm = pow(Lsafe, exponent);
    let gauss     = exp(-pow(d - B, 2.0) / (2.0 * C * C));

    let T = P * A * X * powerTerm * gauss / logDen;
    return max(T, 0.0);
}

// ---------------------------------------------------------------------------
//  Collector centre & size, iterative collector finding (§5.2 / §6.1)
// ---------------------------------------------------------------------------

fn canonicalCollector(V: f32, L: f32, psiV: f32, d: f32, t: f32, setIdx: u32) -> Collector {
    let E  = 1.0 / max(V, 0.1);
    let Fx = 0.2 * V;
    let Gx = 1.2;
    let Hx = 0.05;
    let phiL_rad = acos(clamp(L, -1.0, 1.0));
    let Ax = Fx * sin(psiV) * sin(Gx * phiL_rad);
    let Bx = Hx * sin(psiV) * sin(phiL_rad);
    let cx = Ax * log(1.0 + E * d) + Bx;

    let I  = 0.1;
    let J  = 0.3;
    let K  = 1.5;
    let Lc = 0.05;
    let M  = 0.0;
    let N  = 0.2;
    let Az = I + J * (cos(psiV) * sin(K * phiL_rad) + Lc * phiL_rad);
    let Bz = M + N * cos(psiV) * L;
    let cz = Az * log(1.0 + E * d) + Bz;

    let info     = orderSetInfo(setIdx);
    let orderMid = 0.5 * (info.minOrder + info.maxOrder);
    let spread   = 1.0 + log(orderMid + 1.0) * 0.5;
    let Oc = 0.5  * spread;
    let Qc = 0.01 * spread;
    let Rc = 0.5;
    let Sc = 0.3  * spread;
    let Tc = 0.005;
    let sigma = Oc + Qc * t * log(1.0 + Rc * d) + Sc * log(1.0 + Tc * t);

    return Collector(vec3<f32>(cx, 0.0, cz), max(sigma, 0.5));
}

fn findCollector(p: vec3<f32>, wV: vec3<f32>, wL: vec3<f32>, setIdx: u32) -> CollectorResult {
    let up    = vec3<f32>(0.0, 1.0, 0.0);
    let zAxis = normalize(wL);
    let xAxis = normalize(cross(up, zAxis) + vec3<f32>(EPSILON));
    let yAxis = normalize(cross(zAxis, xAxis));

    let wV_local = vec3<f32>(dot(wV, xAxis), dot(wV, yAxis), dot(wV, zAxis));
    let V_cos    = abs(wV_local.z);
    let psiV     = atan2(wV_local.x, wV_local.y);
    let cosTheta = dot(wV, wL);

    let geom  = slabGeometry(p, wL);
    let d0    = geom.x;
    let t0    = geom.y;
    let L_cos = geom.z;

    var c_world  = p + wL * d0;
    var sigma    = 50.0f;
    var T_result = -1.0f;

    for (var iter = 0u; iter < MAX_COLLECTOR_ITERS; iter++) {
        let rayLight = Ray(c_world - wL * sigma, wL);
        let hitLight = intersectCloudMesh(rayLight);
        var c_proj = c_world;
        var n_proj = wL;
        if (hitLight.hit) {
            c_proj = rayLight.origin + wL * hitLight.tEntry;
            n_proj = hitLight.nEntry;
        } else {
            let rayAway = Ray(c_world + wL * sigma, -wL);
            let hitAway = intersectCloudMesh(rayAway);
            if (hitAway.hit) {
                c_proj = rayAway.origin - wL * hitAway.tEntry;
                n_proj = -hitAway.nEntry;
            }
        }

        let geomC = slabGeometry(c_proj, wL);
        let d_c   = geomC.x;
        let t_c   = geomC.y;

        let col_canonical = canonicalCollector(V_cos, L_cos, psiV, d_c, t_c, setIdx);
        let c_new_local = col_canonical.center;
        let c_new_world = c_proj
            + c_new_local.x * xAxis
            + c_new_local.y * yAxis
            + c_new_local.z * zAxis;
        let sigma_new = col_canonical.sigma;

        let step      = c_new_world - c_world;
        let stepLen   = length(step);
        var c_clamped = c_new_world;
        if (stepLen > sigma_new) {
            c_clamped = c_world + normalize(step) * sigma_new;
        }

        if (stepLen < 0.01 * sigma_new) {
            c_world  = c_clamped;
            sigma    = sigma_new;
            T_result = canonicalT(V_cos, L_cos, cosTheta, d_c, t_c, setIdx);
            break;
        }
        if (iter == MAX_COLLECTOR_ITERS - 1u) {
            T_result = canonicalT(V_cos, L_cos, cosTheta, d_c, t_c, setIdx);
        }

        c_world = c_clamped;
        sigma   = sigma_new;
    }

    return CollectorResult(c_world, sigma, T_result);
}

// ---------------------------------------------------------------------------
//  Lit-surface radiance and scattering integrators
// ---------------------------------------------------------------------------

fn litSurfaceRadiance(cPos: vec3<f32>, wL: vec3<f32>) -> vec3<f32> {
    let rayToSun = Ray(cPos + wL * EPSILON, wL);
    let hitAbove = intersectCloudMesh(rayToSun);
    var sunContrib = SUN_COLOR * SUN_INTENSITY;
    if (hitAbove.hit) {
        let atmDist = hitAbove.tEntry;
        sunContrib *= exp(-EXTINCTION_FACTOR * atmDist * 2.0);
    }
    let skyContrib = mix(SKY_COLOR_BOT, SKY_COLOR_TOP,
                         clamp(wL.y * 0.5 + 0.5, 0.0, 1.0)) * 0.5;
    return sunContrib + skyContrib;
}

fn multipleScattering(p: vec3<f32>, wV: vec3<f32>, wL: vec3<f32>, mask: u32) -> vec3<f32> {
    var msColor = vec3<f32>(0.0);
    for (var s = 0u; s < NUM_MS_SETS; s++) {
        if ((mask & (1u << s)) == 0u) { continue; }
        let result   = findCollector(p, wV, wL, s);
        let radiance = litSurfaceRadiance(result.worldPos, wL);
        msColor += radiance * result.T;
    }
    return msColor;
}

fn singleScattering(rayOrigin: vec3<f32>, rayDir: vec3<f32>,
                    tEntry: f32, tExit: f32, wL: vec3<f32>) -> vec3<f32> {
    var color    = vec3<f32>(0.0);
    let cosTheta = dot(-rayDir, wL);
    let mie      = miePhaseFnRGB(cosTheta);

    var viewOpticalDepth = 0.0f;

    for (var i = 0u; i < SS_SAMPLES; i++) {
        let fi  = f32(i)        / f32(SS_SAMPLES);
        let fi1 = f32(i + 1u)   / f32(SS_SAMPLES);
        let dx  = (fi1 - fi) * (tExit - tEntry);
        let xi  = tEntry + fi  * (tExit - tEntry);
        let xi1 = tEntry + fi1 * (tExit - tEntry);
        let pSample = rayOrigin + rayDir * ((xi + xi1) * 0.5);

        let kappa     = extinction(pSample);
        let shadowRay = Ray(pSample + wL * EPSILON, wL);
        let shadowHit = intersectCloudMesh(shadowRay);
        var li = 0.0f;
        if (shadowHit.hit) {
            li = shadowOpticalDepth(pSample, wL);
        }

        let local_xi  = viewOpticalDepth;
        let local_xi1 = viewOpticalDepth + kappa * dx;
        let xi_li     = local_xi  + li;
        let xi1_li    = local_xi1 + li;
        let contrib   = mie * (exp(-xi_li) - exp(-xi1_li));

        color += contrib * SUN_COLOR * SUN_INTENSITY;
        viewOpticalDepth = local_xi1;
    }
    return max(color, vec3<f32>(0.0));
}

fn computeOpacity(rayOrigin: vec3<f32>, rayDir: vec3<f32>, tEntry: f32, tExit: f32) -> f32 {
    let stepSize = (tExit - tEntry) / f32(OPACITY_SAMPLES);
    var opticalDepth = 0.0f;
    for (var i = 0u; i < OPACITY_SAMPLES; i++) {
        let fi    = (f32(i) + 0.5) / f32(OPACITY_SAMPLES);
        let dSamp = tEntry + fi * (tExit - tEntry);
        let pSamp = rayOrigin + rayDir * dSamp;
        opticalDepth += extinction(pSamp) * stepSize;
    }
    return clamp(1.0 - exp(-opticalDepth), 0.0, 1.0);
}

// ---------------------------------------------------------------------------
//  Sky and tone mapping
// ---------------------------------------------------------------------------

fn getSkyColor(dir: vec3<f32>) -> vec3<f32> {
    let t = 0.5 * (dir.y + 1.0);
    if (dir.y < 0.0) {
        return mix(SKY_COLOR_BOT, vec3<f32>(0.7, 0.8, 1.0), t);
    } else {
        let sunIntensity = max(dot(dir, SUN_DIR), 0.0);
        let sunColor = vec3<f32>(1.0, 0.9, 0.7) * pow(sunIntensity, 100.0);
        let skyColor = mix(vec3<f32>(0.7, 0.8, 1.0), vec3<f32>(0.4, 0.6, 1.0), t);
        return skyColor + sunColor;
    }
}

fn tonemap(c: vec3<f32>) -> vec3<f32> {
    let mapped = c / (c + vec3<f32>(1.0));
    return pow(clamp(mapped, vec3<f32>(0.0), vec3<f32>(1.0)), vec3<f32>(1.0 / 2.2));
}

// ---------------------------------------------------------------------------
//  Camera ray
// ---------------------------------------------------------------------------

fn cameraRay(pixel: vec2<f32>, dims: vec2<f32>, seed: ptr<function, u32>) -> Ray {
    var uv = pixel / dims;
    uv.y = 1.0 - uv.y;
    var ndc = uv * 2.0 - 1.0;

    let aspectRatio = dims.x / dims.y;
    ndc.x *= aspectRatio;

    let fovScale = tan(radians(camera.fov) * 0.5);
    ndc *= fovScale;

    let rayDirCamera = normalize(vec3<f32>(ndc.x, ndc.y, -1.0));

    let yaw   = camera.rotation.y;
    let pitch = camera.rotation.x;

    let cosPitch = cos(pitch);
    let sinPitch = sin(pitch);
    var dir = vec3<f32>(
        rayDirCamera.x,
        rayDirCamera.y * cosPitch - rayDirCamera.z * sinPitch,
        rayDirCamera.y * sinPitch + rayDirCamera.z * cosPitch
    );

    let cosYaw = cos(yaw);
    let sinYaw = sin(yaw);
    dir = normalize(vec3<f32>(
        dir.x * cosYaw - dir.z * sinYaw,
        dir.y,
        dir.x * sinYaw + dir.z * cosYaw
    ));

    return Ray(camera.position, dir);
}

// ---------------------------------------------------------------------------
//  Main pixel render and entry point
// ---------------------------------------------------------------------------

fn renderPixel(pixelCoord: vec2<f32>, dims: vec2<f32>, seed: ptr<function, u32>) -> vec3<f32> {
    let ray = cameraRay(pixelCoord, dims, seed);
    let hit = intersectCloudMesh(ray);

    if (!hit.hit || hit.tEntry >= Infinity) {
        return getSkyColor(ray.direction);
    }

    let tEntry = max(hit.tEntry, 0.0);
    let tExit  = hit.tExit;
    if (tEntry >= tExit) {
        return getSkyColor(ray.direction);
    }

    let pEntry = ray.origin + ray.direction * tEntry;
    let pMid   = ray.origin + ray.direction * (tEntry + (tExit - tEntry) * 0.3);

    let wL = normalize(SUN_DIR);
    let wV = -ray.direction;

    let mask      = settings.scatteringOrderMask;
    let msContrib = multipleScattering(pEntry, wV, wL, mask);

    var ssContrib = vec3<f32>(0.0);
    if ((mask & (1u << 8u)) != 0u) {
        ssContrib = singleScattering(ray.origin, ray.direction, tEntry, tExit, wL);
    }

    let alpha         = computeOpacity(ray.origin, ray.direction, tEntry, tExit);
    let cloudRadiance = msContrib + ssContrib;
    let bg            = getSkyColor(ray.direction);
    return cloudRadiance * alpha + bg * (1.0 - alpha);
    //return vec3<f32>(computeOpacity(ray.origin, ray.direction, tEntry, tExit));

}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(outputTex));
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let pixelCoord = vec2<f32>(f32(gid.x), f32(gid.y));
    var seed = pcg(gid.x + gid.y * 8192u + frameData.frameCount * 1973u);

    let samples = max(settings.antiAliasingSamples, 1u);
    var color   = vec3<f32>(0.0);
    for (var s = 0u; s < samples; s++) {
        color += renderPixel(pixelCoord, dims, &seed);
    }
    color /= f32(samples);

    let mapped = color;
    textureStore(outputTex, vec2<i32>(i32(gid.x), i32(gid.y)), vec4<f32>(mapped, 1.0));
}
