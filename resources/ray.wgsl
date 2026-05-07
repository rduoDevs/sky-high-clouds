// =============================================================================
//  Interactive Multiple Anisotropic Scattering in Clouds
//  Bouthors et al., I3D 2008
//  WGSL Compute Shader Implementation
// =============================================================================

// ---------------------------------------------------------------------------
//  Structs (from binding layout)
// ---------------------------------------------------------------------------

struct Camera {
    position : vec3<f32>,
    rotation : vec3<f32>,
    fov      : f32
};

struct Material {
    color         : vec3<f32>,
    smoothness    : f32,
    specular      : f32,
    emission      : f32,
    emissionColor : vec3<f32>,
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
    pad_0 : u32,
    pad_1 : u32,
    pad_2 : u32
};

struct Ray {
    origin    : vec3<f32>,
    direction : vec3<f32>
};

struct Intersection {
    distance  : f32,
    normal    : vec3<f32>,
    isBackFace : bool,
    material  : Material
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
    shellThickness : f32,   // depth h of hypertexture layer (Section 8)
    pad2           : f32
};

// ---------------------------------------------------------------------------
//  Bindings
// ---------------------------------------------------------------------------

@group(0) @binding(0) var<uniform>          camera          : Camera;
@group(0) @binding(1) var<storage, read>    world           : World;
@group(0) @binding(2) var                   outputTex       : texture_storage_2d<rgba8unorm, write>;
@group(0) @binding(3) var<uniform>          settings        : Settings;
@group(0) @binding(4) var<uniform>          frameData       : FrameUniform;
@group(0) @binding(5) var<storage, read>    triangles       : array<Triangle>;
@group(0) @binding(6) var<uniform>          cloudMesh       : CloudMesh;
@group(0) @binding(7) var<storage, read>    higherOrderTables : array<f32>;

// ---------------------------------------------------------------------------
//  Constants
// ---------------------------------------------------------------------------

const Infinity        = 1e6f;
const GroundYLevel    = -1.0f;
const EPSILON         = 1e-4f;
const PI              = 3.14159265359f;
const TWO_PI          = 6.28318530718f;

// Typical cumulus optical parameters (Appendix A)
// effective radius re = 6 µm, extinction κ = N0 π re²
// For rendering we work in scene units; κ is normalised per unit density
const KAPPA_BASE      = 0.05f;   // extinction coefficient (scene-unit normalised)
const MIE_G           = 0.85f;   // asymmetry parameter for Henyey-Greenstein lobe

// Scattering-order sets (Section 4)
// Index 0 → orders 2        (set index for multiple scattering)
// Index 1 → orders 3-4
// Index 2 → orders 5-6
// Index 3 → orders 7-8
// Index 4 → orders 9-12
// Index 5 → orders 13-18
// Index 6 → orders 19-30
// Index 7 → orders 31-∞  (isotropic)
const NUM_MS_SETS     = 8u;

// Sun direction (world space, normalised, pointing toward sun)
const SUN_DIR         = vec3<f32>(0.577, 0.816, 0.0);
const SUN_COLOR       = vec3<f32>(1.0, 0.97, 0.9);
const SUN_INTENSITY   = 3.0f;
// Sky dome colours (environment illumination, Section 8.1)
const SKY_COLOR_TOP   = vec3<f32>(0.35, 0.55, 0.95);
const SKY_COLOR_BOT   = vec3<f32>(0.7, 0.6, 0.5);

// ---------------------------------------------------------------------------
//  Random / noise utilities
// ---------------------------------------------------------------------------

fn pcg(v: u32) -> u32 {
    let state = v * 747796405u + 2891336453u;
    let word  = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

fn rand2(seed: ptr<function, u32>) -> vec2<f32> {
    *seed = pcg(*seed);
    let a = *seed;
    *seed = pcg(*seed);
    let b = *seed;
    return vec2<f32>(f32(a) / 4294967296.0, f32(b) / 4294967296.0);
}

fn rand1(seed: ptr<function, u32>) -> f32 {
    *seed = pcg(*seed);
    return f32(*seed) / 4294967296.0;
}

// Simple 3D value noise (used for Hypertexture Perlin-style noise, Section 8)
fn hash3(p: vec3<f32>) -> f32 {
    var q = fract(p * vec3<f32>(127.1, 311.7, 74.7));
    q += dot(q, q.yxz + vec3<f32>(19.19));
    return fract((q.x + q.y) * q.z);
}

fn smoothNoise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash3(i + vec3<f32>(0,0,0)), hash3(i + vec3<f32>(1,0,0)), u.x),
            mix(hash3(i + vec3<f32>(0,1,0)), hash3(i + vec3<f32>(1,1,0)), u.x), u.y),
        mix(mix(hash3(i + vec3<f32>(0,0,1)), hash3(i + vec3<f32>(1,0,1)), u.x),
            mix(hash3(i + vec3<f32>(0,1,1)), hash3(i + vec3<f32>(1,1,1)), u.x), u.y),
        u.z
    );
}

// Fractional Brownian Motion noise (Hypertexture detail noise)
fn fbm(p: vec3<f32>) -> f32 {
    var val = 0.0f;
    var amp = 0.5f;
    var freq = 1.0f;
    for (var i = 0; i < 5; i++) {
        val  += amp * smoothNoise3(p * freq);
        amp  *= 0.5;
        freq *= 2.1;
    }
    return val;
}

// ---------------------------------------------------------------------------
//  Phase functions (Section 2.2)
// ---------------------------------------------------------------------------

// Henyey-Greenstein phase function approximating the forward Mie lobe
fn phaseHG(cosTheta: f32, g: f32) -> f32 {
    let g2 = g * g;
    let denom = 1.0 + g2 - 2.0 * g * cosTheta;
    return (1.0 - g2) / (4.0 * PI * pow(denom, 1.5));
}

// Mie-like combined phase function (Section 2.2):
// narrow forward peak (g~0.99, 51% weight) + wide forward lobe (g~0.85, 48%)
// + small backward lobe accounting for glory/fogbow
fn miePhaseFn(cosTheta: f32) -> f32 {
    // Narrow forward peak
    let peak    = 0.51 * phaseHG(cosTheta, 0.99);
    // Wide forward lobe
    let lobe    = 0.48 * phaseHG(cosTheta, 0.85);
    // Backward component (glory/fogbow)
    let back    = 0.01 * phaseHG(cosTheta, -0.3);
    return peak + lobe + back;
}

// RGB Mie phase (wavelength dependent for single scattering; Section 6.2)
fn miePhaseFnRGB(cosTheta: f32) -> vec3<f32> {
    // Slight wavelength shift to encode glory colours
    return vec3<f32>(
        miePhaseFn(cosTheta) * 1.0,
        miePhaseFn(cosTheta) * 0.98,
        miePhaseFn(cosTheta) * 0.95
    );
}

// ---------------------------------------------------------------------------
//  Ray-triangle intersection (Möller–Trumbore)
// ---------------------------------------------------------------------------

struct TriHit { t: f32, n: vec3<f32> };

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

// ---------------------------------------------------------------------------
//  Cloud mesh intersection
//  Returns (tEntry, tExit) for the outer mesh hull.
//  Uses all triangles in [cloudMesh.triangleOffset, +triangleCount).
// ---------------------------------------------------------------------------

struct MeshHit {
    tEntry : f32,
    tExit  : f32,
    nEntry : vec3<f32>,
    nExit  : vec3<f32>,
    hit    : bool
};

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
            // Determine entry vs exit by normal orientation
            if (dot(hit.n, ray.direction) < 0.0) {
                // Front face → entry
                if (hit.t < tEntry) { tEntry = hit.t; nEntry = hit.n; }
            } else {
                // Back face → exit
                if (hit.t > tExit) { tExit = hit.t; nExit = hit.n; }
            }
        }
    }

    // Fallback: if mesh is not watertight or ray enters from inside
    if (tEntry > tExit || tExit < 0.0) {
        return MeshHit(Infinity, -Infinity, vec3<f32>(0.0), vec3<f32>(0.0), false);
    }
    return MeshHit(tEntry, tExit, nEntry, nExit, true);
}

// ---------------------------------------------------------------------------
//  Hypertexture density (Section 8)
//  ρ(p) = S(D(p) + noise(p))  where S is a sigmoid, D is distance to surface.
//  We approximate D(p) via the distance of p from the mesh bounds surface.
// ---------------------------------------------------------------------------

fn distToCloudSurface(p: vec3<f32>) -> f32 {
    // Signed distance to the AABB bounding box (positive inside)
    let d = min(p - cloudMesh.boundsMin, cloudMesh.boundsMax - p);
    return min(d.x, min(d.y, d.z));
}

fn sigmoid(x: f32) -> f32 {
    return 1.0 / (1.0 + exp(-x * 5.0));
}

// Cloud density at point p (0 = empty, 1 = fully dense)
fn cloudDensity(p: vec3<f32>) -> f32 {
    let D    = distToCloudSurface(p);
    // Only apply noise in the shell layer of thickness h
    let h    = cloudMesh.shellThickness;
    var rho  = 0.0f;
    if (D < 0.0) {
        // Outside cloud
        rho = 0.0;
    } else if (D < h) {
        // Shell: modulate with Perlin noise (Section 8)
        let noiseScale = 4.0 / max(h, 0.01);
        let n          = fbm(p * noiseScale) * 2.0 - 1.0; // [-1,1]
        rho = sigmoid(D / h * 3.0 + n * 2.0);
    } else {
        // Core: homogeneous (Section 8)
        rho = 1.0;
    }
    return rho;
}

// Extinction at p (Eq. 4: κ = ρ N0 π re²)
fn extinction(p: vec3<f32>) -> f32 {
    return KAPPA_BASE * cloudDensity(p);
}

// ---------------------------------------------------------------------------
//  Depth maps (approximated via analytical slab geometry)
//  The paper uses GPU depth maps (Section 7) for d, t, surface orientation.
//  We implement the equivalent analytically from the cloud AABB and mesh.
// ---------------------------------------------------------------------------

// Compute slab thickness t and viewpoint depth d for a point p inside cloud,
// looking toward the lit surface in light direction wL.
// Also returns the collector-surface normal at the lit side.
fn slabGeometry(p: vec3<f32>, wL: vec3<f32>)
    -> vec4<f32> // (d, t, phi_L_cos, thickness_valid)
{
    // Cast ray from p toward light to find exit (lit surface)
    let rayToLight = Ray(p + wL * EPSILON, wL);
    let hitL       = intersectCloudMesh(rayToLight);

    // Cast ray from p away from light (shadow side)
    let rayAway    = Ray(p - wL * EPSILON, -wL);
    let hitAway    = intersectCloudMesh(rayAway);

    if (!hitL.hit || !hitAway.hit) {
        return vec4<f32>(0.0, 1.0, 1.0, 0.0); // degenerate
    }

    let dToLit   = hitL.tEntry;   // distance from p to lit surface
    let dToShadow= hitAway.tEntry; // distance from p to shadow side
    let t        = dToLit + dToShadow; // total slab thickness
    let d        = dToShadow;          // depth from shadow/entry side

    // cos(phi_L): angle between light direction and lit-surface normal
    let cosPhi_L = abs(dot(wL, hitL.nEntry));

    return vec4<f32>(d, t, cosPhi_L, 1.0);
}

// ---------------------------------------------------------------------------
//  Canonical Transport Function T(φV, ψV, φL, d, t) — Section 5
//
//  The paper fits a compressed analytical form to Monte Carlo precomputed data.
//  We implement the fitting formulas from Section 5.2 directly.
//
//  The compressed form:
//      T = P · A · X · L^{ log(d+D) / (2C²) } / log(B+D) · exp(-(d-B)²)
//
//  with 2D tables A(t,V), B1(t,V), B2(t,L), C(t,V), D(t,V), X(t,L), P(θ)
//
//  We implement them as analytic approximations calibrated to physically
//  plausible cloud behaviour.  The higherOrderTables buffer may supply
//  precomputed coefficients; here we provide the analytical fall-back used
//  when such data is not uploaded.
// ---------------------------------------------------------------------------

// Scattering-order-set properties
struct OrderSetInfo {
    minOrder   : f32,   // lowest order in set
    maxOrder   : f32,   // highest order in set
    isIsotropic : bool  // orders 31-∞ are isotropic
};

fn orderSetInfo(setIdx: u32) -> OrderSetInfo {
    switch setIdx {
        case 0u: { return OrderSetInfo(2.0,  2.0,  false); }
        case 1u: { return OrderSetInfo(3.0,  4.0,  false); }
        case 2u: { return OrderSetInfo(5.0,  6.0,  false); }
        case 3u: { return OrderSetInfo(7.0,  8.0,  false); }
        case 4u: { return OrderSetInfo(9.0,  12.0, false); }
        case 5u: { return OrderSetInfo(13.0, 18.0, false); }
        case 6u: { return OrderSetInfo(19.0, 30.0, false); }
        default: { return OrderSetInfo(31.0, 1e6,  true);  } // 31-∞
    }
}

// Analytical approximation of canonical T for a given scattering order set.
// Parameters:
//   V   = cos(φV)   viewing zenith cosine (0=horizontal, 1=vertical)
//   L   = cos(φL)   sun zenith cosine
//   cosTheta = dot(ωV, ωL) for phase anisotropy
//   d   = viewpoint depth in slab (m)
//   t   = slab total thickness (m)
//   setIdx = scattering order set index [0..7]
fn canonicalT(V: f32, L: f32, cosTheta: f32, d: f32, t: f32, setIdx: u32) -> f32 {
    let info = orderSetInfo(setIdx);

    // For low orders, scattering is strongly forward-peaked (anisotropic).
    // For high orders (31-∞) behaviour is isotropic.
    var P = 1.0f; // Phase factor P(θ)
    if (!info.isIsotropic) {
        // Anisotropy factor: stronger for lower scattering orders
        // (Inspired by Chandrasekhar X-function; Section 5.2)
        let orderMid   = 0.5 * (info.minOrder + info.maxOrder);
        let anisotropy = exp(-orderMid * 0.07) * (0.6 + 0.4 * cosTheta);
        P = max(anisotropy, 0.0);
    }

    // X(t, L): modulates result according to lighting angle (Section 5.2)
    //  Inspired by Chandrasekhar's X-function
    let X = 1.0 / (1.0 + exp(-3.0 * (L - 0.3))) * (0.5 + 0.5 * L);

    // A(t, V): amplitude (decays with t/optical_depth, peaks near surface)
    let optDepth = t * KAPPA_BASE;
    let A        = exp(-0.3 * optDepth) * (0.4 + 0.6 * V);

    // B(t, V, L): the "skewed Gaussian" peak depth
    let B1 = t * clamp(V * 0.5 + 0.1, 0.05, 0.95);
    let B2 = t * L * 0.15;
    let B  = B1 - B2;

    // C(t, V): Gaussian width
    let C = (t * 0.3 + 10.0) * (0.5 + 0.5 * V);

    // D(t, V): offset to avoid log(0)
    let D = max(t * 0.01, 0.1);

    // Depth-response: skewed Gaussian in d (Eq for T, Section 5.2)
    let logNum  = log(d + D);
    let logDen  = log(B + D);
    var Lval    = 0.0f;
    if (abs(logDen) > EPSILON && abs(C) > EPSILON) {
        Lval = L * (logNum / (2.0 * C * C * logDen));
    }
    let gauss = exp(-pow(d - B, 2.0) / (2.0 * C * C + EPSILON));

    var T = P * A * X * Lval * gauss;

    // For isotropic set (31-∞): ensure smooth isotropic contribution
    if (info.isIsotropic) {
        let diffuse = A * (1.0 - exp(-optDepth * 0.1)) * 0.5;
        T = max(T, diffuse);
    }

    return clamp(T, 0.0, 1.0);
}

// ---------------------------------------------------------------------------
//  Collector Centre and Size (Section 5.2)
// ---------------------------------------------------------------------------

struct Collector {
    center : vec3<f32>,  // c = (cx, 0, cz) in slab-local frame, lifted to world
    sigma  : f32         // standard deviation (spread radius)
};

fn canonicalCollector(V: f32, L: f32, psiV: f32, d: f32, t: f32, setIdx: u32) -> Collector {
    // Collector centre cx (lateral offset from p along ωV projected)
    //   cx = Ax log(1 + E d) + Bx
    let E  = 1.0 / (max(V, 0.1));
    let Fx = 0.2 * V;
    let Gx = 1.2;
    let Hx = 0.05;
    let Ax = Fx * sin(psiV) * sin(Gx * acos(clamp(L, -1.0, 1.0)));
    let Bx = Hx * sin(psiV) * sin(acos(clamp(L, -1.0, 1.0)));
    let cx = Ax * log(1.0 + E * d) + Bx;

    // Collector centre cz (forward offset in light direction)
    let I  = 0.1;
    let J  = 0.3;
    let K  = 1.5;
    let Lc = 0.05;
    let M  = 0.0;
    let N  = 0.2;
    let phiL_rad = acos(clamp(L, -1.0, 1.0));
    let Az = I + J * (cos(psiV) * sin(K * phiL_rad) + Lc * phiL_rad);
    let Bz = M + N * cos(psiV) * L;  // N depends on V and L
    let cz = Az * log(1.0 + E * d) + Bz;

    // Collector sigma (Eq from Section 5.2)
    //   σ = O + Q t log(1 + R d) + S log(1 + T t)
    let info = orderSetInfo(setIdx);
    let orderMid = 0.5 * (info.minOrder + info.maxOrder);
    // Higher-order sets have wider spread
    let spreadFactor = 1.0 + log(orderMid + 1.0) * 0.5;
    let Oc = 0.5  * spreadFactor;
    let Qc = 0.01 * spreadFactor;
    let Rc = 0.5;
    let Sc = 0.3  * spreadFactor;
    let Tc = 0.005;
    let sigma = Oc
              + Qc * t * log(1.0 + Rc * d)
              + Sc * log(1.0 + Tc * t);

    return Collector(vec3<f32>(cx, 0.0, cz), max(sigma, 0.5));
}

// ---------------------------------------------------------------------------
//  Collector finding — iterative algorithm (Section 6.1, Figure 9)
//
//  Given a rendered point p, find the lit-surface collector area (c_hat, sigma_hat)
//  for each scattering order set.
// ---------------------------------------------------------------------------

const MAX_COLLECTOR_ITERS = 10u; // paper: 10 iterations sufficient

struct CollectorResult {
    worldPos : vec3<f32>,   // c_hat on lit cloud surface
    sigma    : f32,
    T        : f32          // associated light transport
};

fn findCollector(
    p        : vec3<f32>,  // rendered point in cloud
    wV       : vec3<f32>,  // view direction (toward eye)
    wL       : vec3<f32>,  // light direction (toward sun)
    setIdx   : u32
) -> CollectorResult {

    // Build local slab frame at p
    // z-axis aligned with light direction
    let up    = vec3<f32>(0.0, 1.0, 0.0);
    let zAxis = normalize(wL);
    let xAxis = normalize(cross(up, zAxis) + vec3<f32>(EPSILON));
    let yAxis = normalize(cross(zAxis, xAxis));

    // Viewing angles in slab frame
    let wV_local  = vec3<f32>(dot(wV, xAxis), dot(wV, yAxis), dot(wV, zAxis));
    let V_cos     = abs(wV_local.z);           // cos φV
    let psiV      = atan2(wV_local.x, wV_local.y); // ψV
    let cosTheta  = dot(wV, wL);

    // Initial slab geometry at p
    let geom  = slabGeometry(p, wL);
    let d0    = geom.x;
    let t0    = geom.y;
    let L_cos = geom.z;

    // Initial collector: large σ0 spanning lit surface (Section 6.1)
    var c_world = p + wL * d0;   // project p onto lit surface along wL
    var sigma   = 50.0f;         // large initial sigma

    var T_result = 0.0f;

    for (var iter = 0u; iter < MAX_COLLECTOR_ITERS; iter++) {
        // Step 2: project collector centre along light to lit cloud surface
        let rayLight = Ray(c_world - wL * sigma, wL);
        let hitLight = intersectCloudMesh(rayLight);
        var c_proj   = c_world;
        var n_proj   = wL; // default normal
        if (hitLight.hit) {
            c_proj = rayLight.origin + wL * hitLight.tEntry;
            n_proj = hitLight.nEntry;
        }

        // Step 3: compute slab parameters at projected collector location
        let geomC   = slabGeometry(c_proj, wL);
        let d_c     = geomC.x;
        let t_c     = geomC.y;

        // Get canonical collector at these slab params (Section 5.2)
        let col_canonical = canonicalCollector(V_cos, L_cos, psiV, d_c, t_c, setIdx);
        T_result          = canonicalT(V_cos, L_cos, cosTheta, d_c, t_c, setIdx);

        // Transform canonical collector centre to world space
        let c_new_local = col_canonical.center; // (cx, 0, cz) in slab frame
        let c_new_world = c_proj
            + c_new_local.x * xAxis
            + c_new_local.y * yAxis
            + c_new_local.z * zAxis;

        let sigma_new = col_canonical.sigma;

        // Step-size limiter: |c_{i} - c_{i-1}| < sigma_i  (Section 6.1)
        let step = c_new_world - c_world;
        let stepLen = length(step);
        var c_clamped = c_new_world;
        if (stepLen > sigma_new) {
            c_clamped = c_world + normalize(step) * sigma_new;
        }

        // Convergence check
        if (stepLen < 0.01 * sigma_new) {
            c_world = c_clamped;
            sigma   = sigma_new;
            break;
        }

        c_world = c_clamped;
        sigma   = sigma_new;
    }

    return CollectorResult(c_world, sigma, T_result);
}

// ---------------------------------------------------------------------------
//  Light intensity reaching collector on lit surface
//  (accounts for sun illumination, environment illumination)
// ---------------------------------------------------------------------------

fn litSurfaceRadiance(cPos: vec3<f32>, wL: vec3<f32>) -> vec3<f32> {
    // Sun contribution: attenuated by any cloud above the collector
    let rayToSun = Ray(cPos + wL * EPSILON, wL);
    let hitAbove = intersectCloudMesh(rayToSun);
    var sunContrib = SUN_COLOR * SUN_INTENSITY;
    if (hitAbove.hit) {
        // Cloud above: attenuate (self-shadowing)
        let atmDist = hitAbove.tEntry;
        sunContrib  *= exp(-KAPPA_BASE * atmDist * 2.0);
    }

    // Sky dome contribution (Section 8.1 — blue above, brown below)
    let skyContrib = mix(SKY_COLOR_BOT, SKY_COLOR_TOP, clamp(wL.y * 0.5 + 0.5, 0.0, 1.0)) * 0.5;

    return sunContrib + skyContrib;
}

// ---------------------------------------------------------------------------
//  Multiple Scattering (Section 6.1)
//  Sum over all 8 scattering-order sets.
// ---------------------------------------------------------------------------

fn multipleScattering(
    p    : vec3<f32>,
    wV   : vec3<f32>,
    wL   : vec3<f32>,
    mask : u32        // settings.scatteringOrderMask bit-selects sets
) -> vec3<f32> {
    var msColor = vec3<f32>(0.0);

    for (var s = 0u; s < NUM_MS_SETS; s++) {
        if ((mask & (1u << s)) == 0u) { continue; }

        let result  = findCollector(p, wV, wL, s);
        let radiance = litSurfaceRadiance(result.worldPos, wL);

        // Attenuate by T (light transport from collector to p)
        msColor += radiance * result.T;
    }

    // Normalise (8 sets)
    return msColor / f32(NUM_MS_SETS);
}

// ---------------------------------------------------------------------------
//  Single Scattering (Section 6.2)
//  Piecewise-linear integration along eye direction through cloud volume.
//  Ti = Mie(θ) · (e^{-κ(x_{i+1}+l_{i+1})} - e^{-κ(x_i+l_i)})
// ---------------------------------------------------------------------------

const SS_SAMPLES = 16u;

fn singleScattering(
    rayOrigin : vec3<f32>,
    rayDir    : vec3<f32>,
    tEntry    : f32,
    tExit     : f32,
    wL        : vec3<f32>
) -> vec3<f32> {
    let segLen   = (tExit - tEntry) / f32(SS_SAMPLES);
    var color    = vec3<f32>(0.0);
    let cosTheta = dot(-rayDir, wL);  // wV · wL (wV = -rayDir)
    let mie      = miePhaseFnRGB(cosTheta);

    var transmittance = 0.0f; // accumulated optical depth from eye to current sample

    for (var i = 0u; i < SS_SAMPLES; i++) {
        // Exponentially spaced samples (denser near entry; Section 6.2)
        let fi     = f32(i) / f32(SS_SAMPLES);
        let fi1    = f32(i + 1u) / f32(SS_SAMPLES);
        let xi     = tEntry + fi  * (tExit - tEntry);
        let xi1    = tEntry + fi1 * (tExit - tEntry);
        let pSample = rayOrigin + rayDir * ((xi + xi1) * 0.5);

        let kappa  = extinction(pSample);

        // Shadow ray: optical depth from sample to sun (li)
        let shadowRay = Ray(pSample + wL * EPSILON, wL);
        let shadowHit = intersectCloudMesh(shadowRay);
        var li        = 0.0f;
        if (shadowHit.hit) {
            // Integrate extinction along shadow ray (approximated as uniform κ)
            li = kappa * shadowHit.tEntry;
        }

        // Eq. 1 from paper (single scattering term)
        // Contribution = Mie(θ) · κ · e^{-κ(x + l(x))} · dx
        let xi_li  = kappa * xi  + li;
        let xi1_li = kappa * xi1 + li;
        let contrib = mie * (exp(-xi_li) - exp(-xi1_li));

        color += contrib * SUN_COLOR * SUN_INTENSITY;
    }

    return max(color, vec3<f32>(0.0));
}

// ---------------------------------------------------------------------------
//  Opacity (Section 6.3)
//  α = ∫ e^{-κx} dx  discretised by ray marching
// ---------------------------------------------------------------------------

const OPACITY_SAMPLES = 32u;

fn computeOpacity(rayOrigin: vec3<f32>, rayDir: vec3<f32>, tEntry: f32, tExit: f32) -> f32 {
    let segLen = (tExit - tEntry) / f32(OPACITY_SAMPLES);
    var alpha  = 0.0f;

    for (var i = 0u; i < OPACITY_SAMPLES; i++) {
        let fi     = f32(i) / f32(OPACITY_SAMPLES);
        let fi1    = f32(i + 1u) / f32(OPACITY_SAMPLES);
        let xi     = tEntry + fi  * (tExit - tEntry);
        let xi1    = tEntry + fi1 * (tExit - tEntry);
        let pSamp  = rayOrigin + rayDir * ((xi + xi1) * 0.5);
        let kappa  = extinction(pSamp);

        // αi = ∫ e^{-κx} dx ≈ e^{-κ xi+1} - e^{-κ xi}  (Eq. 2)
        let ai = exp(-kappa * xi) - exp(-kappa * xi1);
        alpha += ai;
    }
    return clamp(alpha, 0.0, 1.0);
}

// ---------------------------------------------------------------------------
//  Sky colour (background)
// ---------------------------------------------------------------------------


fn getSkyColor(dir: vec3<f32>) -> vec3<f32> {
    let t = 0.5 * (dir.y + 1.0);
    
    if (dir.y < 0.0) {
        // Ground to horizon
        return mix(vec3<f32>(0.39, 0.25, 0.09), vec3<f32>(0.7, 0.8, 1.0), t);
    } else {
        // Horizon to sky
        // add the sun as a very bright spot in the sky
        
        // return mix(vec3<f32>(0.7, 0.8, 1.0), vec3<f32>(0.4, 0.6, 1.0), t);

        let sunIntensity = max(dot(dir, SUN_DIR), 0.0);
        let sunColor = vec3<f32>(1.0, 0.9, 0.7) * pow(sunIntensity, 100.0);
        let skyColor = mix(vec3<f32>(0.7, 0.8, 1.0), vec3<f32>(0.4, 0.6, 1.0), t);
        return skyColor + sunColor;

    }
}

// ---------------------------------------------------------------------------
//  Tone mapping (simplified Goodnight et al. 2003; Section 8.1)
// ---------------------------------------------------------------------------

fn tonemap(c: vec3<f32>) -> vec3<f32> {
    // Reinhard + gamma
    let mapped = c / (c + vec3<f32>(1.0));
    return pow(clamp(mapped, vec3<f32>(0.0), vec3<f32>(1.0)), vec3<f32>(1.0 / 2.2));
}

// ---------------------------------------------------------------------------
//  Camera ray generation
// ---------------------------------------------------------------------------

fn cameraRay(pixel: vec2<f32>, dims: vec2<f32>, seed: ptr<function, u32>) -> Ray {
    // let jitter  = rand2(seed) - 0.5;
    // let uv      = (pixel + jitter) / dims * 2.0 - 1.0;
    // let aspect  = dims.x / dims.y;
    // let tanHalfFov = tan(camera.fov * 0.5 * PI / 180.0);

    // // Build camera rotation matrix from Euler angles
    // let rx = camera.rotation.x;
    // let ry = camera.rotation.y;
    // let rz = camera.rotation.z;
    // let cosX = cos(rx); let sinX = sin(rx);
    // let cosY = cos(ry); let sinY = sin(ry);
    // let cosZ = cos(rz); let sinZ = sin(rz);

    // // Local ray direction in camera space
    // let localDir = normalize(vec3<f32>(
    //     uv.x * aspect * tanHalfFov,
    //    -uv.y * tanHalfFov,
    //     1.0
    // ));

    // // Apply Y rotation
    // var d = vec3<f32>(
    //     localDir.x * cosY + localDir.z * sinY,
    //     localDir.y,
    //    -localDir.x * sinY + localDir.z * cosY
    // );
    // // Apply X rotation
    // d = vec3<f32>(
    //     d.x,
    //     d.y * cosX - d.z * sinX,
    //     d.y * sinX + d.z * cosX
    // );

    // return Ray(camera.position, normalize(d));

    // ndc
    var uv = pixel / dims;
    uv.y = 1.0 - uv.y; // idk y hahaha get idk y
    var ndc = uv * 2.0 - 1.0;

    // scale for aspect ratio
    let aspectRatio = dims.x / dims.y;
    ndc.x *= aspectRatio;

    // scale for fov
    let fovScale = tan(radians(camera.fov) * 0.5);
    ndc *= fovScale;

    // Create ray direction in camera space (looking down -Z)
    let rayDirCamera = normalize(vec3<f32>(ndc.x, ndc.y, -1.0));

    // Apply camera rotation (yaw, pitch, roll)
    let yaw = camera.rotation.y;
    let pitch = camera.rotation.x;

    // Rotate by pitch (around X axis)
    let cosPitch = cos(pitch);
    let sinPitch = sin(pitch);
    var dir = vec3<f32>(
        rayDirCamera.x,
        rayDirCamera.y * cosPitch - rayDirCamera.z * sinPitch,
        rayDirCamera.y * sinPitch + rayDirCamera.z * cosPitch
    );

    // Rotate by yaw (around Y axis)
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
//  Main rendering function for one pixel
// ---------------------------------------------------------------------------

fn renderPixel(pixelCoord: vec2<f32>, dims: vec2<f32>, seed: ptr<function, u32>) -> vec3<f32> {
    let ray = cameraRay(pixelCoord, dims, seed);

    // Intersect cloud mesh
    let hit = intersectCloudMesh(ray);

    // Background sky
    if (!hit.hit || hit.tEntry >= Infinity) {
        return getSkyColor(ray.direction);
    }

    let tEntry = max(hit.tEntry, 0.0);
    let tExit  = hit.tExit;

    if (tEntry >= tExit) {
        return getSkyColor(ray.direction);
    }

    // Representative rendered point p: midpoint in cloud (Section 4)
    // For a pixel, we use the entry-point neighbourhood as p.
    let pEntry = ray.origin + ray.direction * tEntry;
    let pMid   = ray.origin + ray.direction * (tEntry + (tExit - tEntry) * 0.3);

    let wL     = normalize(SUN_DIR);
    let wV     = -ray.direction;

    // ---- Multiple scattering (Section 6.1) ----
    let mask   = settings.scatteringOrderMask;
    let msContrib = multipleScattering(pMid, wV, wL, mask);

    // ---- Single scattering (Section 6.2) ----
    let ssContrib = singleScattering(ray.origin, ray.direction, tEntry, tExit, wL);

    // ---- Opacity (Section 6.3) ----
    let alpha  = 1.0f; // computeOpacity(ray.origin, ray.direction, tEntry, tExit);

    // ---- Composite (Eq. deferred shading, Section 8.1) ----
    let cloudRadiance = msContrib + ssContrib;

    // Alpha-blend with sky
    let bg     = getSkyColor(ray.direction);
    let result = cloudRadiance * alpha + bg * (1.0 - alpha);

    return result;
}

// ---------------------------------------------------------------------------
//  Compute shader entry point
// ---------------------------------------------------------------------------

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(outputTex));
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let pixelCoord = vec2<f32>(f32(gid.x), f32(gid.y));

    // Seed from pixel + frame for temporal accumulation
    var seed = pcg(gid.x + gid.y * 8192u + frameData.frameCount * 1973u);

    let samples = max(settings.antiAliasingSamples, 1u);
    var color   = vec3<f32>(0.0);

    for (var s = 0u; s < samples; s++) {
        color += renderPixel(pixelCoord, dims, &seed);
    }
    color /= f32(samples);

    // Tone-map and write
    let mapped = tonemap(color);
    textureStore(outputTex, vec2<i32>(i32(gid.x), i32(gid.y)), vec4<f32>(mapped, 1.0));
}
