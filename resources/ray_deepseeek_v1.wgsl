//==============================================================================
// COMPLETE BOUTHORS CLOUD RENDERING IMPLEMENTATION
//==============================================================================

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
    pad_0 : u32,
    pad_1 : u32
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

//==============================================================================
// CONSTANTS
//==============================================================================
const Infinity = 1e6;
const EPSILON = 1e-4;
const PI = 3.14159265359;

const GroundYLevel = -1.0;

const NoMaterial = Material(vec3<f32>(0.0), 0.0, 0.0, 0.0, vec3<f32>(0.0), 0.0);
const GroundMaterial1 = Material(vec3<f32>(0.39, 0.25, 0.09), 0.0, 0.0, 0.0, vec3<f32>(0.0), 0.0);
const GroundMaterial2 = Material(vec3<f32>(0.0, 0.39, 0.0), 0.0, 0.0, 0.0, vec3<f32>(0.0), 0.0);
const NoIntersection = Intersection(Infinity, vec3<f32>(0.0), false, NoMaterial);

//==============================================================================
// BINDINGS
//==============================================================================
@group(0) @binding(0) var<uniform> camera : Camera;
@group(0) @binding(1) var<storage, read> world : World;
@group(0) @binding(2) var outputTex : texture_storage_2d<rgba8unorm, write>;
@group(0) @binding(3) var<uniform> settings : Settings;
@group(0) @binding(4) var<uniform> frameData : FrameUniform;
@group(0) @binding(5) var<storage, read> triangles: array<Triangle>;
@group(0) @binding(6) var<uniform> cloudMesh: CloudMesh;
@group(0) @binding(7) var<storage, read> higherOrderTables: array<f32>;

//==============================================================================
// TABLE SAMPLING CONFIGURATION
//==============================================================================
const HO_W: u32 = 64u;
const HO_H: u32 = 64u;
const HO_LAYER_COUNT: u32 = 49u;

// Table layout for each scattering order set (0-6 for orders 1-30+)
// | A | B1 | B2 | C | D | P | X |
// Each has 7 textures
const TABLE_A_OFFSET: u32 = 0u;
const TABLE_B1_OFFSET: u32 = 7u;
const TABLE_B2_OFFSET: u32 = 14u;
const TABLE_C_OFFSET: u32 = 21u;
const TABLE_D_OFFSET: u32 = 28u;
const TABLE_P_OFFSET: u32 = 35u;
const TABLE_X_OFFSET: u32 = 42u;

//==============================================================================
// RANDOM NUMBER GENERATION
//==============================================================================
var<private> rngState: u32;

fn initRNG(seed: u32) {
    rngState = seed;
}

fn pcgHash(input: u32) -> u32 {
    var state = input * 747796405u + 2891336453u;
    var word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

fn randomFloat() -> f32 {
    rngState = pcgHash(rngState);
    return f32(rngState) / 4294967296.0;
}

fn randomFloatRange(min: f32, max: f32) -> f32 {
    return min + (max - min) * randomFloat();
}

//==============================================================================
// UTILITY FUNCTIONS
//==============================================================================
fn sampleFromTable(layer: u32, uv: vec2<f32>) -> f32 {
    let u = clamp(uv.x, 0.0, 1.0);
    let v = clamp(uv.y, 0.0, 1.0);
    let x = min(u32(floor(u * f32(HO_W))), HO_W - 1u);
    let y = min(u32(floor(v * f32(HO_H))), HO_H - 1u);
    let idx = layer * (HO_W * HO_H) + y * HO_W + x;
    return higherOrderTables[idx];
}

fn tToUv(orderSet: i32, t: f32) -> f32 {
    // Map slab thickness to UV based on order set (from paper)
    if (orderSet < 3) {
        return clamp((t - 50.0) / 450.0, 0.0, 1.0);
    } else if (orderSet < 5) {
        return clamp((t - 10.0) / 490.0, 0.0, 1.0);
    } else if (orderSet < 6) {
        return clamp((t - 50.0) / 950.0, 0.0, 1.0);
    } else {
        return clamp((t - 50.0) / 4950.0, 0.0, 1.0);
    }
}

fn muVToUv(orderSet: i32, mu_V: f32) -> f32 {
    return clamp((mu_V + 1.0) / 2.0, 0.0, 1.0);
}

fn muLToUv(orderSet: i32, mu_L: f32) -> f32 {
    return clamp((mu_L - 0.05) / 0.95, 0.0, 1.0);
}

fn thetaToUv(orderSet: i32, theta: f32) -> f32 {
    return clamp((cos(theta) + 1.0) * 0.5, 0.0, 1.0);
}

//==============================================================================
// TEXTURE SAMPLING FOR EACH COMPONENT
//==============================================================================
fn sampleTexA(orderSet: i32, t: f32, mu_V: f32) -> f32 {
    let uv = vec2<f32>(tToUv(orderSet, t), muVToUv(orderSet, mu_V));
    let layer = TABLE_A_OFFSET + u32(orderSet);
    return sampleFromTable(layer, uv);
}

fn sampleTexB1(orderSet: i32, t: f32, mu_V: f32) -> f32 {
    let uv = vec2<f32>(tToUv(orderSet, t), muVToUv(orderSet, mu_V));
    let layer = TABLE_B1_OFFSET + u32(orderSet);
    return sampleFromTable(layer, uv);
}

fn sampleTexB2(orderSet: i32, t: f32, mu_L: f32) -> f32 {
    let uv = vec2<f32>(tToUv(orderSet, t), muLToUv(orderSet, mu_L));
    let layer = TABLE_B2_OFFSET + u32(orderSet);
    return sampleFromTable(layer, uv);
}

fn sampleTexC(orderSet: i32, t: f32, mu_V: f32) -> f32 {
    let uv = vec2<f32>(tToUv(orderSet, t), muVToUv(orderSet, mu_V));
    let layer = TABLE_C_OFFSET + u32(orderSet);
    return sampleFromTable(layer, uv);
}

fn sampleTexD(orderSet: i32, t: f32, mu_V: f32) -> f32 {
    let uv = vec2<f32>(tToUv(orderSet, t), muVToUv(orderSet, mu_V));
    let layer = TABLE_D_OFFSET + u32(orderSet);
    return sampleFromTable(layer, uv);
}

fn sampleTexP(orderSet: i32, t: f32, theta: f32) -> f32 {
    let uv = vec2<f32>(tToUv(orderSet, t), thetaToUv(orderSet, theta));
    let layer = TABLE_P_OFFSET + u32(orderSet);
    return sampleFromTable(layer, uv);
}

fn sampleTexX(orderSet: i32, t: f32, mu_L: f32) -> f32 {
    let uv = vec2<f32>(tToUv(orderSet, t), muLToUv(orderSet, mu_L));
    let layer = TABLE_X_OFFSET + u32(orderSet);
    return sampleFromTable(layer, uv);
}

fn sampleTexB(orderSet: i32, t: f32, mu_V: f32, mu_L: f32) -> f32 {
    return sampleTexB1(orderSet, t, mu_V) - sampleTexB2(orderSet, t, mu_L);
}

//==============================================================================
// RAY-TRIANGLE INTERSECTION
//==============================================================================
fn intersectTriangle(ray: Ray, triangle: Triangle) -> Intersection {
    let edge1 = triangle.v1 - triangle.v0;
    let edge2 = triangle.v2 - triangle.v0;
    let h = cross(ray.direction, edge2);
    let a = dot(edge1, h);
    
    if (abs(a) < EPSILON) {
        return NoIntersection;
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
        let isBackFace = dot(ray.direction, normal) > 0.0;
        
        if (isBackFace) {
            normal = -normal;
        }
        
        return Intersection(t, normal, isBackFace, NoMaterial);
    }
    
    return NoIntersection;
}

//==============================================================================
// CLOUD MESH INTERSECTION - GETS BOTH ENTRY AND EXIT
//==============================================================================
struct IntersectionPair {
    entry: Intersection,
    exit: Intersection
};
fn getCloudEntryExit(ray: Ray, mesh: CloudMesh) -> IntersectionPair {
    var entry = NoIntersection;
    var exit = NoIntersection;
    
    for (var i = 0u; i < mesh.triangleCount; i++) {
        let triangle = triangles[mesh.triangleOffset + i];
        let hit = intersectTriangle(ray, triangle);
        
        if (hit.distance > EPSILON) {
            if (hit.distance < entry.distance) {
                exit = entry;
                entry = hit;
            } else if (hit.distance < exit.distance) {
                exit = hit;
            }
        }
    }
    
    return IntersectionPair(entry, exit);
}

fn getClosestIntersection(ray: Ray, mesh: CloudMesh) -> Intersection {
    var closest = NoIntersection;
    
    for (var i = 0u; i < mesh.triangleCount; i++) {
        let triangle = triangles[mesh.triangleOffset + i];
        let hit = intersectTriangle(ray, triangle);
        
        if (hit.distance < closest.distance) {
            closest = hit;
        }
    }
    
    return closest;
}

//==============================================================================
// CORRECTED BOUTHORS IMPLEMENTATION
//==============================================================================

fn bouthorsScattering(
    entryPoint: vec3<f32>,
    exitPoint: vec3<f32>,
    entryNormal: vec3<f32>,
    viewDir: vec3<f32>,
    lightDir: vec3<f32>
) -> f32 {
    
    var totalTransport = 0.0;
    let pathLength = distance(entryPoint, exitPoint);
    
    // Sample along the ray path through the cloud
    let numSamples = 10;
    let stepSize = pathLength / f32(numSamples);
    
    for (var sampleIdx = 0; sampleIdx < numSamples; sampleIdx++) {
        let t = (f32(sampleIdx) + 0.5) * stepSize;
        let point = entryPoint + viewDir * t;
        
        // Get normal at this point (interpolate or use nearest)
        var pointNormal = entryNormal;
        
        // Find thickness at this point (remaining cloud depth along normal)
        let interiorDir = -pointNormal;
        let thicknessRay = Ray(point + interiorDir * EPSILON, interiorDir);
        let thicknessHit = getClosestIntersection(thicknessRay, cloudMesh);
        var slabThickness = 500.0;
        if (thicknessHit.distance != Infinity && thicknessHit.distance > EPSILON) {
            slabThickness = thicknessHit.distance;
        }
        slabThickness = clamp(slabThickness, 10.0, 5000.0);
        
        // Find depth from lit surface at this point
        let depthRay = Ray(point - lightDir * EPSILON, -lightDir);
        let depthHit = getClosestIntersection(depthRay, cloudMesh);
        var depth = 0.0;
        if (depthHit.distance != Infinity && depthHit.distance > EPSILON) {
            depth = depthHit.distance;
        }
        depth = clamp(depth, 0.0, slabThickness);
        
        // Calculate angles
        let slabNormal = normalize(pointNormal);
        let omega_V = normalize(viewDir);
        let omega_L = normalize(lightDir);
        
        let phi_V = acos(clamp(dot(-slabNormal, omega_V), -1.0, 1.0));
        let mu_V = cos(phi_V);
        
        let phi_L = acos(clamp(dot(slabNormal, omega_L), -1.0, 1.0));
        let mu_L = cos(phi_L);

        if mu_L < 0 {
            return 0.0; // Light is below the surface, no contribution
        } else {
            return 1.0;
        }
        
        // Projected angles
        let omega_V_proj = normalize(omega_V - dot(omega_V, -slabNormal) * -slabNormal);
        let omega_L_proj = normalize(omega_L - dot(omega_L, slabNormal) * slabNormal);
        var psi_V = 0.0;
        if (length(omega_V_proj) > EPSILON && length(omega_L_proj) > EPSILON) {
            psi_V = acos(clamp(dot(omega_V_proj, omega_L_proj), -1.0, 1.0));
        }
        
        // Sum scattering orders
        var pointTransport = 0.0;
        for (var orderSet = 0; orderSet < 7; orderSet++) {
            let A = sampleTexA(orderSet, slabThickness, mu_V);
            let B = sampleTexB(orderSet, slabThickness, mu_V, mu_L);
            let C = sampleTexC(orderSet, slabThickness, mu_V);
            let D = sampleTexD(orderSet, slabThickness, mu_V);
            let P = sampleTexP(orderSet, slabThickness, psi_V);
            let X = sampleTexX(orderSet, slabThickness, mu_L);
            
            // Avoid log of negative or zero
            let logNumerator = log(max(depth + D, 0.001));
            let logDenominator = log(max(B + D, 0.001));
            let depthFactor = logNumerator / logDenominator;
            
            let diff = max(depth - B, -10.0);
            let gaussian = exp(-(diff * diff) / (2.0 * max(C * C, 0.001)));
            
            let transport = P * A * X * max(mu_L, 0.0) * depthFactor * gaussian;
            pointTransport += transport;
        }
        
        // Accumulate with transmittance along view path
        let tau = 0.05 * pointTransport; // Extinction coefficient
        let transmittanceToEntry = exp(-tau * t);
        
        totalTransport += pointTransport * transmittanceToEntry * stepSize;
    }
    
    return clamp(totalTransport / 10.0, 0.0, 5.0);
}
fn bouthorsScattering2(
    point: vec3<f32>,           // Point on cloud surface (entry point)
    pointNormal: vec3<f32>,     // Surface normal at that point
    viewDir: vec3<f32>,
    lightDir: vec3<f32>
) -> f32 {
    
    var totalTransport = 0.0;
    
    // STEP 1: Slab thickness t - go through cloud from entry point
    let interiorDir = -pointNormal;
    let thicknessRay = Ray(point + interiorDir * EPSILON, interiorDir);
    let thicknessHit = getClosestIntersection(thicknessRay, cloudMesh);
    var t = 500.0; // Fallback
    if (thicknessHit.distance != Infinity && thicknessHit.distance > EPSILON) {
        t = thicknessHit.distance;
    }
    t = clamp(t, 10.0, 5000.0);
    
    // STEP 2: Depth d - distance from point to LIT surface (top of cloud)
    // Cast ray upward (assuming lit surface is top of cloud)
    let litSurfaceNormal = vec3<f32>(0.0, 1.0, 0.0); // Upward
    let toLitSurface = Ray(point - litSurfaceNormal * EPSILON, -litSurfaceNormal);
    let litHit = getClosestIntersection(toLitSurface, cloudMesh);
    var d = 0.0;
    if (litHit.distance != Infinity && litHit.distance > EPSILON) {
        d = litHit.distance;
    } else {
        // Point might be on lit surface itself
        d = 0.0;
    }
    d = clamp(d, 0.0, t);
    
    // STEP 3: Angles - ALL using the point's surface normal
    let phi_V = acos(clamp(dot(-pointNormal, viewDir), -1.0, 1.0));
    let mu_V = cos(phi_V);
    
    // Light angle - constant for entire cloud (sun elevation)
    let phi_L = acos(clamp(dot(litSurfaceNormal, lightDir), -1.0, 1.0));
    let mu_L = cos(phi_L);
    
    // Azimuth angle - project onto plane defined by pointNormal
    let viewProj = normalize(viewDir - dot(viewDir, -pointNormal) * -pointNormal);
    let lightProj = normalize(lightDir - dot(lightDir, -pointNormal) * -pointNormal);
    var psi_V = 0.0;
    if (length(viewProj) > EPSILON && length(lightProj) > EPSILON) {
        psi_V = acos(clamp(dot(viewProj, lightProj), -1.0, 1.0));
    }
    
    // STEP 4: Sum scattering orders - ONE lookup per order, NOT ray marching
    for (var orderSet = 0; orderSet < 7; orderSet++) {
        let A = sampleTexA(orderSet, t, mu_V);
        let B = sampleTexB(orderSet, t, mu_V, mu_L);
        let C = sampleTexC(orderSet, t, mu_V);
        let D = sampleTexD(orderSet, t, mu_V);
        let P = sampleTexP(orderSet, t, psi_V);
        let X = sampleTexX(orderSet, t, mu_L);
        
        // Equation from paper - gives TOTAL transport for this order set
        let logNum = log(max(d + D, 1e-6));
        let logDen = log(max(B + D, 1e-6));
        let depthFactor = logNum / logDen;
        let gaussian = exp(-pow(d - B, 2.0) / (2.0 * max(C * C, 1e-6)));
        
        let transport = P * A * X * mu_L * depthFactor * gaussian;
        totalTransport += transport;
    }
    
    // The result is already integrated through the slab - no marching needed!
    return totalTransport / 3.0f;
}

//==============================================================================
// RAY CASTING
//==============================================================================
fn createRay(uv: vec2<f32>, size: vec2<f32>) -> Ray {
    var ndc = uv * 2.0 - 1.0;
    let aspectRatio = size.x / size.y;
    ndc.x *= aspectRatio;
    
    let fovScale = tan(radians(camera.fov) * 0.5);
    ndc *= fovScale;
    
    let rayDirCamera = normalize(vec3<f32>(ndc.x, ndc.y, -1.0));
    
    // Apply camera rotation (yaw around Y, pitch around X)
    let yaw = camera.rotation.y;
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

fn getSkyColor(ray: Ray) -> vec3<f32> {
    let t = 0.5 * (ray.direction.y + 1.0);
    
    if (ray.direction.y < 0.0) {
        // Ground to horizon
        return mix(vec3<f32>(0.39, 0.25, 0.09), vec3<f32>(0.7, 0.8, 1.0), t);
    } else {
        // Horizon to sky
        // add the sun as a very bright spot in the sky
        
        // return mix(vec3<f32>(0.7, 0.8, 1.0), vec3<f32>(0.4, 0.6, 1.0), t);

        let sunIntensity = max(dot(ray.direction, SUN_DIR), 0.0);
        let sunColor = vec3<f32>(1.0, 0.9, 0.7) * pow(sunIntensity, 100.0);
        let skyColor = mix(vec3<f32>(0.7, 0.8, 1.0), vec3<f32>(0.4, 0.6, 1.0), t);
        return skyColor + sunColor;

    }
}

fn intersectGround(ray: Ray) -> Intersection {
    let t = (GroundYLevel - ray.origin.y) / ray.direction.y;
    
    if (t > EPSILON) {
        let intersectionX = ray.origin.x + t * ray.direction.x;
        let intersectionZ = ray.origin.z + t * ray.direction.z;
        
        var material = GroundMaterial1;
        let tileX = i32(floor(abs(intersectionX)));
        let tileZ = i32(floor(abs(intersectionZ)));
        
        if ((tileX & 1) != (tileZ & 1)) {
            material = GroundMaterial2;
        }
        
        return Intersection(t, vec3<f32>(0.0, 1.0, 0.0), false, material);
    }
    
    return NoIntersection;
}

const SUN_DIR = normalize(vec3<f32>(0.5, 1.0, 0.3));

// Modified castRay to work with volume sampling
fn castRay(ray: Ray) -> vec3<f32> {
    // Find entry and exit points in cloud
    let entryExit = getCloudEntryExit(ray, cloudMesh);
    let entryDist = entryExit.entry.distance;
    let exitDist = entryExit.exit.distance;
    
    if (entryDist == Infinity) {
        return getSkyColor(ray);
    }
    
    let entryPoint = ray.origin + ray.direction * entryDist;
    if exitDist == Infinity {
        return vec3<f32>(1.0, 0.0, 0.0); // Red for debugging
    }
    let exitPoint = ray.origin + ray.direction * exitDist;
    
    // Get normal at entry point
    let entryHit = getClosestIntersection(ray, cloudMesh);
    let entryNormal = entryHit.normal;
    
    // Calculate scattering through the volume
    // let scattering = bouthorsScattering(
    //     entryPoint,
    //     exitPoint,
    //     entryNormal,
    //     ray.direction,
    //     SUN_DIR
    // );

    let noise = perlin3D(entryPoint * 10.0 + vec3<f32>(0.0, f32(frameData.frameCount) * 0.01, 0.0)) * 0.5 + 0.5;
    let perturbedNormal = normalize(entryNormal + (noise - 0.5) * 0.2); // Add some noise to the normal for detail

        let scattering = bouthorsScattering2(
        entryPoint,
        perturbedNormal,
        ray.direction,
        SUN_DIR
    );
    
    // Base cloud color
    let cloudColor = vec3<f32>(0.95, 0.92, 0.88);
    let radiance = cloudColor * scattering;
    
    // Add some sky at the horizon
    // let skyContrib = getSkyColor(ray) * 0.15;
    
    return radiance;
}


//==============================================================================
// PERLIN NOISE FOR SURFACE DETAIL (OPTIONAL)
//==============================================================================
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, vec3<f32>(p3.y, p3.z, p3.x) + 33.33);
    return fract((vec3<f32>(p3.x, p3.x, p3.y) + vec3<f32>(p3.y, p3.z, p3.z)) * vec3<f32>(p3.z, p3.x, p3.y));
}

fn perlin3D(p: vec3<f32>) -> f32 {
    let pi = floor(p);
    let pf = fract(p);
    let u = pf * pf * (3.0 - 2.0 * pf);
    
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
    
    let y0 = mix(x00, x10, u.y);
    let y1 = mix(x01, x11, u.y);
    
    return mix(y0, y1, u.z);
}

//==============================================================================
// MAIN COMPUTE SHADER
//==============================================================================
@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let size = textureDimensions(outputTex);
    
    if (gid.x >= size.x || gid.y >= size.y) {
        return;
    }
    
    // Initialize RNG for this pixel
    let pixelIndex = gid.y * size.x + gid.x;
    let rngSeed = pixelIndex * 747796405u + 2891336453u + frameData.frameCount;
    initRNG(rngSeed);
    
    // Calculate UV coordinates
    var uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(size);
    uv.y = 1.0 - uv.y;
    
    // Anti-aliasing
    let samples = settings.antiAliasingSamples;
    var finalColor = vec3<f32>(0.0);
    let pixelSize = 1.0 / vec2<f32>(size);
    
    for (var i = 0u; i < samples; i++) {
        for (var j = 0u; j < samples; j++) {
            let jitter = vec2<f32>(randomFloat(), randomFloat()) * 0.5;
            let sampleUV = uv + (vec2<f32>(f32(i), f32(j)) + jitter) * pixelSize / vec2<f32>(f32(samples));
            
            let ray = createRay(sampleUV, vec2<f32>(size));
            let color = castRay(ray);
            finalColor += color;
        }
    }
    
    let sampleCount = f32(samples * samples);
    finalColor /= sampleCount;
    
    textureStore(outputTex, vec2<i32>(gid.xy), vec4<f32>(finalColor, 1.0));
}