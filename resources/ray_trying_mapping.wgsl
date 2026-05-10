struct Camera {
    position : vec3<f32>,
    rotation : vec3<f32>,
    fov      : f32
};

struct Material {
    color : vec3<f32>,
    smoothness : f32,
    specular : f32,
    emission : f32,
    emissionColor : vec3<f32>,
    refractiveIndex : f32
};

struct Sphere {
    center : vec3<f32>,
    radius : f32,
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
    origin : vec3<f32>,
    direction : vec3<f32>
};

struct Intersection {
    distance : f32,
    normal : vec3<f32>,
    isBackFace : bool,
    material : Material
};

struct Settings {
    maxBounces : u32,
    antiAliasingSamples : u32,
    scatteringOrderMask : u32,
    pad_0 : u32
};

struct Triangle {
    v0: vec3<f32>, pad0: f32,
    v1: vec3<f32>, pad1: f32,
    v2: vec3<f32>, pad2: f32,
    normal: vec3<f32>, pad3: f32
};

struct CloudMesh {
    boundsMin: vec3<f32>, pad0: f32,
    boundsMax: vec3<f32>, pad1: f32,
    triangleOffset: u32,
    triangleCount: u32,
    shellThickness: f32,
    pad2: f32
};

@group(0) @binding(5) var<storage, read> triangles: array<Triangle>;
@group(0) @binding(6) var<uniform> cloudMesh: CloudMesh;

const Infinity = 1e6;
const GroundYLevel = -1.0;
const NoMaterial = Material(vec3<f32>(0.0), 0.0, 0.0, 0.0, vec3<f32>(0.0), 0.0);
//  rgb(100,65,23)
const GroundMaterial1 = Material(vec3<f32>(0.39, 0.25, 0.09), 0.0, 0.0, 0.0, vec3<f32>(0.0), 0.0);
//  rgb(0,100,0)
const GroundMaterial2 = Material(vec3<f32>(0.0, 0.39, 0.0), 0.0, 0.0, 0.0, vec3<f32>(0.0), 0.0);
const NoIntersection = Intersection(Infinity, vec3<f32>(0.0), false, NoMaterial);
const EPSILON = 1e-4;
const PI = 3.14159265359;

@group(0) @binding(0) var<uniform> camera : Camera;
@group(0) @binding(1) var<storage, read> world : World;
@group(0) @binding(2) var outputTex : texture_storage_2d<rgba8unorm, write>;
@group(0) @binding(3) var<uniform> settings : Settings;
@group(0) @binding(4) var<uniform> frameData : FrameUniform;

// lookups for higher orders
// Packed as a single storage buffer: layers * WIDTH * HEIGHT floats
@group(0) @binding(7) var<storage, read> higherOrderTables: array<f32>;

const HO_W: u32 = 64u;
const HO_H: u32 = 64u;
const HO_LAYER_COUNT: u32 = 49u;
const HO_ORDER_COUNT: u32 = 7u;

// Domain bounds from LogGaussAniso_Params_*.txt, ordered as:
// 1, 2, 3, 4-5, 6-8, 9-14, 15p
const T_MIN_BY_ORDER = array<f32, 7>(50.0, 50.0, 50.0, 10.0, 10.0, 50.0, 50.0);
const T_MAX_BY_ORDER = array<f32, 7>(500.0, 500.0, 500.0, 500.0, 500.0, 1000.0, 5000.0);
const MU_V_MIN: f32 = -1.0;
const MU_V_MAX: f32 = 1.0;
const MU_L_MIN: f32 = 0.05;
const MU_L_MAX: f32 = 1.0;
const PSI_COS_MIN: f32 = -1.0;
const PSI_COS_MAX: f32 = 1.0;

fn clampOrderIndex(order: i32) -> u32 {
    let idx = select(0u, u32(order), order >= 0);
    return min(idx, HO_ORDER_COUNT - 1u);
}

fn normalizeToUnit(v: f32, minV: f32, maxV: f32) -> f32 {
    let denom = max(maxV - minV, 1e-6);
    return clamp((v - minV) / denom, 0.0, 1.0);
}

fn tableAt(layer: u32, x: u32, y: u32) -> f32 {
    let safeLayer = min(layer, HO_LAYER_COUNT - 1u);
    let idx = safeLayer * (HO_W * HO_H) + y * HO_W + x;
    return higherOrderTables[idx];
}

// Sample from packed table buffer using normalized UV and layer index
fn sampleFromTable(layer: u32, uv: vec2<f32>) -> f32 {
    // Bilinear interpolation to mimic GLSL linear texture sampling.
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

const collectorPosition = vec3f(1,1,1);
const sunDir = normalize(vec3<f32>(0.5, 1.0, 0.3));

// canonical transport function <T,c,sigma>(phi_L,phi_V,psi_V,t,d)
// mu_V = cos(phi_V), mu_L = cos(phi_L)

struct collectorDelta{
    phi_L: f32,     // 90deg - Angle of inclination between the collector area and the sun
    phi_V: f32,     // Viewpoint pitch offset from directly perpendicular to the slab surface
    psi_V: f32,     // Viewpoint rotation offset from the sun direction
    // t: f32,         // Total slab thickness
    d: f32,         // depth of point p into the slab
}

// Get the 5 parameterizing variables for this given viewing position and collector location
fn getCollectorDelta(p: vec3<f32>, omega_V: vec3<f32>, omega_L: vec3<f32>, c: vec3<f32>, c_normal: vec3<f32>) -> collectorDelta {
    // 
    var cd = collectorDelta(0,0,0,0);
    cd.phi_L = acos(dot(normalize(c_normal), normalize(omega_L)));
    cd.phi_V = acos(dot(normalize(-c_normal), normalize(omega_V)));

    // extract perpendicular components and find the angle between them to find total viewpoint deviance from sun direction
    let omega_V_perp = omega_V - (dot(omega_V, -c_normal) * -c_normal);
    let omega_L_perp = omega_L - (dot(omega_L, c_normal) * c_normal);

    cd.psi_V = acos(dot(normalize(omega_V_perp), normalize(omega_L_perp)));

    // find p distance into the slab

    let d_non_perp = c - p;

    let d = dot(d_non_perp, c_normal) * c_normal;

    cd.d = length(d);

    return cd;
}

fn mu_V_to_uv(order: i32, mu_V: f32) -> f32 {
    _ = order;
    return normalizeToUnit(mu_V, MU_V_MIN, MU_V_MAX);
}

// theta effectively translates to phi_V... I think
fn theta_to_uv(order: i32, theta: f32) -> f32 {
    _ = order;
    // Params files use [-1,1] for this axis, so map cos(theta) into that domain.
    return normalizeToUnit(-cos(theta), PSI_COS_MIN, PSI_COS_MAX);
}

// Mu_L is only the upper half of the angle range as the light source is assumed to be above the cloud
fn mu_L_to_uv(order: i32, mu_L: f32) -> f32 {
    _ = order;
    return normalizeToUnit(mu_L, MU_L_MIN, MU_L_MAX);
}

fn t_to_uv(order: i32, t: f32) -> f32 {
    let idx = clampOrderIndex(order);
    return normalizeToUnit(t, T_MIN_BY_ORDER[idx], T_MAX_BY_ORDER[idx]);
}

// Helper function to convert normalized UV coordinates to texture coordinates
// uvToTexCoord removed — sampling now uses packed float tables via sampleFromTable()

// When indexing the texture array, the array is laid out as such
// | A | B1 | B2 | C | D | P | X |
// Each of these sections is 7 images (1,2,3,4-5,6-8,9-14) orders of scattering

// Clips input values and samples texture A at the specified index. Texture A has to do with the peak values of the scattering.
fn sampleTexA(order: i32, t:f32, mu_V: f32) -> f32 {
    var uv = vec2f(0);
    uv[0] = t_to_uv(order, t);
    uv[1] = mu_V_to_uv(order, mu_V);
    return sampleFromTable(u32(order), uv);
}

// Clips input values and samples textures B1 and B2 at the specified index. (B1 - B2) corresponds with Peak Location.
fn sampleTexB(order: i32, t: f32, mu_V: f32, mu_L: f32) -> f32 {
    var uv1 = vec2f(0);
    var uv2 = vec2f(0);
    uv1[0] = t_to_uv(order, t);
    uv2[0] = t_to_uv(order, t);

    uv1[1] = mu_V_to_uv(order, mu_V);
    uv2[1] = mu_L_to_uv(order, mu_L);

    let idx1 = 7u + u32(order);
    let idx2 = 14u + u32(order);
    // B1 - B2
    return sampleFromTable(idx1, uv1) - sampleFromTable(idx2, uv2);
}

// Clips input values and samples texture C at the specified index. C corresponds with Broadness.
fn sampleTexC(order: i32, t:f32, mu_V: f32) -> f32 {
    var uv = vec2f(0);
    uv[0] = t_to_uv(order, t);
    uv[1] = mu_V_to_uv(order, mu_V);
    let idx = 21u + u32(order);
    return sampleFromTable(idx, uv);
}

// Clips input values and samples texture D at the specified index. D corresponds with Lograrithmic Behaviour.
fn sampleTexD(order: i32, t: f32, mu_V: f32) -> f32 {
    var uv = vec2f(0);
    uv[0] = t_to_uv(order, t);
    uv[1] = mu_V_to_uv(order, mu_V);
    let idx = 28u + u32(order);
    return sampleFromTable(idx, uv);
}

// Clips input values and samples texture P at the specified index. P corresponds with the overall Anisotropy of the scattering. 
fn sampleTexP(order: i32, t:f32, theta: f32) -> f32 {
    var uv = vec2f(0);
    uv[0] = t_to_uv(order, t);
    uv[1] = theta_to_uv(order, theta);
    let idx = 35u + u32(order);
    return sampleFromTable(idx, uv);
}

// Clips input values and samples texture X at the specified index. Texture X has to do with the peak values of the scattering.
fn sampleTexX(order: i32, t:f32, mu_L: f32) -> f32 {
    var uv = vec2f(0);
    uv[0] = t_to_uv(order, t);
    uv[1] = mu_L_to_uv(order, mu_L);
    let idx = 42u + u32(order);
    return sampleFromTable(idx, uv);
}

// TODO: Find depth of cloud mesh from every given point
fn bouthorsScattering(position: vec3<f32>, normal: vec3<f32>, rayDirection: vec3<f32>) -> f32 {
    var transport = 0.0f;
    
    // 1. Slab thickness t - MUST have cloud mesh thickness at this point
    // Cast ray from position through the cloud along the normal direction
    let thicknessRay = Ray(position - normal * EPSILON, -normal);
    let thicknessIntersection = intersectMesh(thicknessRay, cloudMesh);
    var t = 500.0; // Default fallback
    if (thicknessIntersection.distance != Infinity && thicknessIntersection.distance > EPSILON) {
        t = thicknessIntersection.distance;
    }
    
    // 2. Depth d - distance from lit surface to point p
    // Cast ray from position BACK towards light source
    let depthRay = Ray(position - sunDir * EPSILON, -sunDir);
    let depthIntersection = intersectMesh(depthRay, cloudMesh);
    var d = t; // Default to max thickness
    if (depthIntersection.distance != Infinity && depthIntersection.distance > EPSILON) {
        d = depthIntersection.distance;
    }
    
    // 3. Angles (using slab normal)
    let omega_V = normalize(camera.position - position);
    let collectorNormal = normal; // Simplified: use intersection normal
    
    let phi_V = acos(dot(-collectorNormal, omega_V)); // View angle
    let phi_L = acos(dot(collectorNormal, sunDir));   // Light angle
    let mu_V = cos(phi_V);
    let mu_L = cos(phi_L);
    
    // Perpendicular angle psi_V
    let omega_V_perp = omega_V - dot(omega_V, -collectorNormal) * -collectorNormal;
    let omega_L_perp = sunDir - dot(sunDir, collectorNormal) * collectorNormal;
    var psi_V = 0.0;
    if (length(omega_V_perp) > EPSILON && length(omega_L_perp) > EPSILON) {
        psi_V = acos(clamp(dot(normalize(omega_V_perp), normalize(omega_L_perp)), -1.0, 1.0));
    }
    
    // 4. Sum over enabled scattering orders (1..7 mapped to indices 0..6)
    for (var orderSet = 0u; orderSet < 7u; orderSet++) {
        if ((settings.scatteringOrderMask & (1u << orderSet)) == 0u) {
            continue;
        }
        let order = i32(orderSet);
        let a = sampleTexA(order, t, mu_V);
        let b = sampleTexB(order, t, mu_V, mu_L);
        let c = sampleTexC(order, t, mu_V);
        let d_param = sampleTexD(order, t, mu_V);
        let p = sampleTexP(order, t, psi_V);
        let x = sampleTexX(order, t, mu_L);
        
        // Paper Equation (Section 5.2)
        let numerator = log(d + d_param);
        let denominator = log(b + d_param);
        let depthFactor = numerator / denominator;
        let gaussian = exp(-pow(d - b, 2.0) / (2.0 * c * c));
        
        // let t_for_order = p * a * x * mu_L * depthFactor * gaussian;
        // let t_for_order = p * a * x * mu_L * depthFactor;
    
    // Test each component separately
    // return a;        // Test A texture
    // return b;        // Test B texture  
    // return c;        // Test C texture
    // return p;        // Test P texture
    // return a * p;    // Test combination
    
    // let t_for_order = p * a * x * mu_L * ((log(deltaStruct.d + d))/(log(b + d))) * exp(-1 * (pow(deltaStruct.d - b,2.0)/pow(2 * c,2.0)));
        let t_for_order = p * a * x * mu_L * depthFactor * gaussian;

        transport += t_for_order;
    }
    
    return transport;
}

// PCG random number generator state
var<private> rngState: u32;

// Initialize RNG with seed
fn initRNG(seed: u32) {
    rngState = seed;
}

// PCG hash function for random number generation
fn pcgHash(input: u32) -> u32 {
    var state = input * 747796405u + 2891336453u;
    var word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

// Generate random float in [0, 1)
fn randomFloat() -> f32 {
    rngState = pcgHash(rngState);
    return f32(rngState) / 4294967296.0;
}

// Generate random float in [min, max)
fn randomFloatRange(min: f32, max: f32) -> f32 {
    return min + (max - min) * randomFloat();
}

fn randomNormal() -> f32 {
    // Box-Muller transform
    let u1 = randomFloat();
    let u2 = randomFloat();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * PI * u2);
}

// Generate random vector in unit sphere
fn randomInUnitSphere() -> vec3<f32> {
    let x = randomNormal();
    let y = randomNormal();
    let z = randomNormal();
    return normalize(vec3<f32>(x, y, z));
}

// Generate random unit vector
fn randomUnitVector() -> vec3<f32> {
    return normalize(randomInUnitSphere());
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(vec3<f32>(p.x, p.y, p.z) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, vec3<f32>(p3.y, p3.z, p3.x) + 33.33);
    return fract((vec3<f32>(p3.x, p3.x, p3.y) + vec3<f32>(p3.y, p3.z, p3.z)) * vec3<f32>(p3.z, p3.x, p3.y));
}

fn perlin3D(p: vec3<f32>) -> f32 {
    let pi = floor(p);
    let pf = fract(p);

    // Smoothstep interpolation
    let u = pf * pf * (3.0 - 2.0 * pf);

    // 8 corners of the cube
    let c000 = dot(hash3(pi + vec3<f32>(0.0, 0.0, 0.0)) - 0.5, pf - vec3<f32>(0.0, 0.0, 0.0));
    let c001 = dot(hash3(pi + vec3<f32>(0.0, 0.0, 1.0)) - 0.5, pf - vec3<f32>(0.0, 0.0, 1.0));
    let c010 = dot(hash3(pi + vec3<f32>(0.0, 1.0, 0.0)) - 0.5, pf - vec3<f32>(0.0, 1.0, 0.0));
    let c011 = dot(hash3(pi + vec3<f32>(0.0, 1.0, 1.0)) - 0.5, pf - vec3<f32>(0.0, 1.0, 1.0));
    let c100 = dot(hash3(pi + vec3<f32>(1.0, 0.0, 0.0)) - 0.5, pf - vec3<f32>(1.0, 0.0, 0.0));
    let c101 = dot(hash3(pi + vec3<f32>(1.0, 0.0, 1.0)) - 0.5, pf - vec3<f32>(1.0, 0.0, 1.0));
    let c110 = dot(hash3(pi + vec3<f32>(1.0, 1.0, 0.0)) - 0.5, pf - vec3<f32>(1.0, 1.0, 0.0));
    let c111 = dot(hash3(pi + vec3<f32>(1.0, 1.0, 1.0)) - 0.5, pf - vec3<f32>(1.0, 1.0, 1.0));

    // Trilinear interpolation
    let x00 = mix(c000, c100, u.x);
    let x01 = mix(c001, c101, u.x);
    let x10 = mix(c010, c110, u.x);
    let x11 = mix(c011, c111, u.x);

    let y0 = mix(x00, x10, u.y);
    let y1 = mix(x01, x11, u.y);

    return mix(y0, y1, u.z);
}

// Fractional Brownian Motion for more detailed noise
fn fbm(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    var pos = p;

    for (var i = 0; i < 4; i++) {
        value += amplitude * perlin3D(pos * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }

    return value;
}

fn worley3D(p: vec3<f32>) -> f32 {
    let pi = floor(p);
    let pf = fract(p);

    var minDist = 1.0;

    // Check neighboring cells
    for (var x = -1; x <= 1; x++) {
        for (var y = -1; y <= 1; y++) {
            for (var z = -1; z <= 1; z++) {
                let neighbor = vec3<f32>(f32(x), f32(y), f32(z));
                let cellPos = pi + neighbor;

                // Random point in this cell
                let randomPoint = hash3(cellPos);

                // Distance to this point
                let diff = neighbor + randomPoint - pf;
                let dist = length(diff);

                minDist = min(minDist, dist);
            }
        }
    }

    return minDist;
}

fn worleyFbm(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;

    for (var i = 0; i < 3; i++) {
        value += amplitude * worley3D(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }

    return value;
}

fn intersectTriangle(ray: Ray, triangle: Triangle) -> Intersection {
    let edge1 = triangle.v1 - triangle.v0;
    let edge2 = triangle.v2 - triangle.v0;
    let h = cross(ray.direction, edge2);
    let a = dot(edge1, h);
    if (abs(a) < EPSILON) {
        return NoIntersection; // Ray is parallel to triangle
    }
    let f = 1.0 / a;
    let s = ray.origin - triangle.v0;
    let u = f * dot(s, h);
    if (u < 0.0 || u > 1.0) {
        return NoIntersection;
    }
    let q = cross(s, edge1);
    let v = f * dot(ray.direction, q);
    if (v < 0.0 || u + v > 1.0) {
        return NoIntersection;
    }
    let t = f * dot(edge2, q);
    if (t > EPSILON) {
        let hitPoint = ray.origin + t * ray.direction;
        var normal = normalize(triangle.normal);
        var isBackFace = dot(ray.direction, normal) > 0.0;
        if (isBackFace) {
            normal = -normal;
        }
        return Intersection(t, normal, isBackFace, NoMaterial);
    } else {
        return NoIntersection; // Line intersection but not a ray intersection
    }
}

fn intersectMesh(ray: Ray, mesh: CloudMesh) -> Intersection {
    var closestIntersection = NoIntersection;
    for (var i = 0u; i < mesh.triangleCount; i++) {
        let triangle = triangles[mesh.triangleOffset + i];
        let intersection = intersectTriangle(ray, triangle);
        if (intersection.distance < closestIntersection.distance) {
            closestIntersection = intersection;
        }
    }
    return closestIntersection;
}

fn getSkyBoxColor(ray: Ray) -> vec3<f32> {
    let t = 0.5 * (ray.direction.y + 1.0);
    
    if (ray.direction.y < 0.0) {
        // Ground to horizon
        return mix(vec3<f32>(0.39, 0.25, 0.09), vec3<f32>(0.7, 0.8, 1.0), t);
    } else {
        // Horizon to sky
        // add the sun as a very bright spot in the sky
        
        // return mix(vec3<f32>(0.7, 0.8, 1.0), vec3<f32>(0.4, 0.6, 1.0), t);

        let sunIntensity = max(dot(ray.direction, sunDir), 0.0);
        let sunColor = vec3<f32>(1.0, 0.9, 0.7) * pow(sunIntensity, 100.0);
        let skyColor = mix(vec3<f32>(0.7, 0.8, 1.0), vec3<f32>(0.4, 0.6, 1.0), t);
        return skyColor + sunColor;

    }
}

// fn intersectEnvironment(ray: Ray) -> Intersection {
//     let groundIntersection = intersectGridGround(ray);
//     if (groundIntersection.distance < NoIntersection.distance) {
//         return groundIntersection;
//     }
//     return NoIntersection;
// }


fn createRay(uv : vec2<f32>, size : vec2<f32>) -> Ray {
    // ndc
    var ndc = uv * 2.0 - 1.0;

    // scale for aspect ratio
    let aspectRatio = size.x / size.y;
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

fn intersectGridGround(ray : Ray) -> Intersection {
    let t = (GroundYLevel - ray.origin.y) / ray.direction.y;
    if (t > 0.0) {
        let intersectionX = ray.origin.x + t * ray.direction.x;
        let intersectionZ = ray.origin.z + t * ray.direction.z;
        var material: Material = GroundMaterial1;
        let tileX = i32(floor(abs(intersectionX)));
        let tileZ = i32(floor(abs(intersectionZ)));
        if ((tileX & 1) != (tileZ & 1)) {
            material = GroundMaterial2;
        }
        return Intersection(t, vec3<f32>(0.0, 1.0, 0.0), false, material);
    } else {
        return NoIntersection;
    }
}

fn calculateLight(ray : Ray, intersection : Intersection) -> vec3<f32> {
    let intersectionPosition = ray.origin + ray.direction * intersection.distance;
    
    // // DEBUG: Test table sampling directly
    // let testVal = sampleFromTable(0u, vec2<f32>(0.5, 0.5));
    
    // // If testVal is 0 or NaN, tables aren't loaded
    // if (testVal <= 0.0 || testVal != testVal) {
    //     return vec3<f32>(0.5, 0.0, 0.0); // Red = table data error
    // }
    
    // offset normal by perlin noise for more interesting visuals
    let noise = perlin3D(intersectionPosition) * 0.5 + 0.5; // + vec3<f32>(0.0, frameData.frameCount as f32 * 0.01, 0.0)) * 0.5 + 0.5;
    let perturbedNormal = normalize(intersection.normal + (noise - 0.5) * 0.5);
    // return vec3<f32>(noise); // Green = normal noise visualization

    let light = bouthorsScattering(intersectionPosition, intersection.normal, ray.direction);
    
    // // // Clamp to [0,1] for visualization
    // // let normalized = clamp(light / 1000.0, 0.0, 1.0);
    // // return vec3<f32>(normalized);

    return vec3<f32>(light); // Scale down for visualization
}

fn castRay(ray: Ray) -> vec3<f32> {
    var radiance = vec3<f32>(0.0);
    var throughput = vec3<f32>(1.0);

    // if (hit.x >= 0.0) {
    //     let result = raymarchCloudMesh(ray, hit.x, hit.y);
    //     radiance += result.rgb * throughput;
    //     throughput *= (1.0 - result.a);
    // }

    // radiance += getSkyBoxColor(ray) * throughput;
    // return radiance;

    // for (var bounce = 0u; bounce < settings.maxBounces; bounce++) {
    let intersection = intersectMesh(ray, cloudMesh);
    if (intersection.distance == Infinity) {
        radiance += getSkyBoxColor(ray) * throughput;
        return radiance;
    }

    radiance += calculateLight(ray, intersection) * throughput;

        // // For simplicity, we only handle diffuse reflection here
        // let newDir = normalize(intersection.normal + randomUnitVector());
        // ray = Ray(ray.origin + ray.direction * intersection.distance + intersection.normal * EPSILON, newDir);
        // throughput *= 0.5; // Assume 50% energy loss on each bounce
    // }

    return radiance;
}

fn fakeAntiAliasing(uv : vec2<f32>, size : vec2<f32>) -> vec3<f32> {
    let samples = settings.antiAliasingSamples;
    var color = vec3<f32>(0.0);
    let pixelSize = 1.0 / size;
    for (var i = 0u; i < samples; i++) {
        for (var j = 0u; j < samples; j++) {
            let uvShift = vec2<f32>(f32(i) / f32(samples), f32(j) / f32(samples)) * pixelSize;
            let randomShift = vec2<f32>(randomFloat(), randomFloat()) * pixelSize * 0.2;
            let uvShiftFinal = uvShift + randomShift;
            let ray = createRay(uv + uvShiftFinal, size);
            color += castRay(ray);
        }
    }
    let samplesF = f32(samples);
    return color / vec3<f32>(samplesF * samplesF);
}

@compute @workgroup_size(8,8)
fn main(@builtin(global_invocation_id) gid : vec3<u32>) {
    let size = textureDimensions(outputTex);
    if (gid.x >= size.x || gid.y >= size.y) {
        return;
    }

    let pixelIndex = gid.y * size.x + gid.x;
    let rngSeed = pixelIndex * 747796405u + 2891336453u + frameData.frameCount;
    initRNG(rngSeed);

    var uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(size);
    uv.y = 1.0 - uv.y;

    let color = fakeAntiAliasing(uv, vec2<f32>(size));

    textureStore(outputTex, vec2<i32>(gid.xy), vec4<f32>(color, 1.0));
}
