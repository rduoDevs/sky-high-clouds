//==============================================================================
// BOUTHORS CLOUD RENDERING IMPLEMENTATION
// Multiple Anisotropic Scattering in Clouds using Collector Area Method
//==============================================================================

struct Camera {
    position: vec3<f32>,
    rotation: vec3<f32>,
    fov: f32,
};

struct Material {
    color: vec3<f32>,
    smoothness: f32,
    specular: f32,
    emission: f32,
    emissionColor: vec3<f32>,
    refractiveIndex: f32,
};

struct Sphere {
    center: vec3<f32>,
    radius: f32,
    material: Material,
};

struct World {
    spheres: array<Sphere, 2>,
};

struct FrameUniform {
    frameCount: u32,
    pad_0: u32,
    pad_1: u32,
    pad_2: u32,
};

struct Ray {
    origin: vec3<f32>,
    direction: vec3<f32>,
};

struct Intersection {
    distance: f32,
    normal: vec3<f32>,
    isBackFace: bool,
    material: Material,
};

struct Settings {
    maxBounces: u32,
    antiAliasingSamples: u32,
    pad_0: u32,
    pad_1: u32,
};

struct Triangle {
    v0: vec3<f32>,
    pad0: f32,
    v1: vec3<f32>,
    pad1: f32,
    v2: vec3<f32>,
    pad2: f32,
    normal: vec3<f32>,
    pad3: f32,
};

struct CloudMesh {
    boundsMin: vec3<f32>,
    pad0: f32,
    boundsMax: vec3<f32>,
    pad1: f32,
    triangleOffset: u32,
    triangleCount: u32,
    shellThickness: f32,
    pad2: f32,
};

//==============================================================================
// CONSTANTS
//==============================================================================
const INFINITY = 1e6;
const EPSILON = 1e-4;
const PI = 3.14159265359;
const GROUND_Y_LEVEL = -1.0;

// Scattering order sets (8 groups)
const ORDER_SET_COUNT = 8u;
const ORDER_SET_STARTS: array<u32, 8> = array<u32, 8>(1u, 2u, 3u, 5u, 7u, 9u, 13u, 19u);
const ORDER_SET_ENDS: array<u32, 8> = array<u32, 8>(1u, 2u, 4u, 6u, 8u, 12u, 18u, 30u);
const ORDER_SET_IS_ISOTROPIC: array<bool, 8> = array<bool, 8>(false, false, false, false, false, false, false, true);

// Table sampling configuration
const HO_W: u32 = 64u;
const HO_H: u32 = 64u;
const HO_LAYER_COUNT: u32 = 49u;

// Table offsets
const TABLE_A_OFFSET: u32 = 0u;
const TABLE_B1_OFFSET: u32 = 7u;
const TABLE_B2_OFFSET: u32 = 14u;
const TABLE_C_OFFSET: u32 = 21u;
const TABLE_D_OFFSET: u32 = 28u;
const TABLE_P_OFFSET: u32 = 35u;
const TABLE_X_OFFSET: u32 = 42u;

//==============================================================================
// MATERIALS
//==============================================================================
const NO_MATERIAL = Material(vec3<f32>(0.0), 0.0, 0.0, 0.0, vec3<f32>(0.0), 0.0);
const GROUND_MATERIAL_1 = Material(vec3<f32>(0.39, 0.25, 0.09), 0.0, 0.0, 0.0, vec3<f32>(0.0), 0.0);
const GROUND_MATERIAL_2 = Material(vec3<f32>(0.0, 0.39, 0.0), 0.0, 0.0, 0.0, vec3<f32>(0.0), 0.0);
const NO_INTERSECTION = Intersection(INFINITY, vec3<f32>(0.0), false, NO_MATERIAL);

//==============================================================================
// BINDINGS
//==============================================================================
@group(0) @binding(0) var<uniform> camera: Camera;
@group(0) @binding(1) var<storage, read> world: World;
@group(0) @binding(2) var outputTex: texture_storage_2d<rgba8unorm, write>;
@group(0) @binding(3) var<uniform> settings: Settings;
@group(0) @binding(4) var<uniform> frameData: FrameUniform;
@group(0) @binding(5) var<storage, read> triangles: array<Triangle>;
@group(0) @binding(6) var<uniform> cloudMesh: CloudMesh;
@group(0) @binding(7) var<storage, read> higherOrderTables: array<f32>;

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

fn intersectSphere(ray: Ray, sphere: Sphere) -> Intersection {
    let oc = ray.origin - sphere.center;
    let b = dot(oc, ray.direction);
    let c = dot(oc, oc) - sphere.radius * sphere.radius;
    let discriminant = b * b - c;
    
    if discriminant < 0.0 {
        return NO_INTERSECTION;
    }
    
    let sqrtD = sqrt(discriminant);
    let t1 = -b - sqrtD;
    let t2 = -b + sqrtD;
    let t = select(t1, t2, t1 < EPSILON && t2 > EPSILON);
    
    if t < EPSILON {
        return NO_INTERSECTION;
    }
    
    let hitPoint = ray.origin + ray.direction * t;
    let normal = (hitPoint - sphere.center) / sphere.radius;
    let isBackFace = dot(normal, ray.direction) > 0.0;
    
    return Intersection(t, normal, isBackFace, sphere.material);
}

fn intersectMesh(ray: Ray) -> Intersection {
    var closestHit = NO_INTERSECTION;
    
    for (var i = 0u; i < cloudMesh.triangleCount; i++) {
        let tri = triangles[cloudMesh.triangleOffset + i];
        let hit = intersectTriangle(ray, tri);
        if hit.distance < closestHit.distance {
            closestHit = hit;
        }
    }
    
    return closestHit;
}

fn intersectTriangle(ray: Ray, tri: Triangle) -> Intersection {
    let edge1 = tri.v1 - tri.v0;
    let edge2 = tri.v2 - tri.v0;
    let h = cross(ray.direction, edge2);
    let a = dot(edge1, h);
    
    if abs(a) < EPSILON {
        return NO_INTERSECTION;
    }
    
    let f = 1.0 / a;
    let s = ray.origin - tri.v0;
    let u = f * dot(s, h);
    
    if u < 0.0 || u > 1.0 {
        return NO_INTERSECTION;
    }
    
    let q = cross(s, edge1);
    let v = f * dot(ray.direction, q);
    
    if v < 0.0 || u + v > 1.0 {
        return NO_INTERSECTION;
    }
    
    let t = f * dot(edge2, q);
    
    if t > EPSILON {
        let isBackFace = dot(tri.normal, ray.direction) > 0.0;
        return Intersection(t, tri.normal, isBackFace, NO_MATERIAL);
    }
    
    return NO_INTERSECTION;
}

fn getRayDirection(uv: vec2<f32>, camera: Camera, size: vec2<f32>) -> vec3<f32> {
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

    return dir;
}

//==============================================================================
// SINGLE SCATTERING (Mie phase function)
//==============================================================================

fn miePhaseFunction(cosTheta: f32) -> vec3<f32> {
    // Approximate Mie phase function with glory and fogbow features
    // Forward peak (narrow)
    let forwardNarrow = pow(1.0 - cosTheta, 1.5) * 0.51;
    // Forward lobe (wide)
    let forwardWide = pow(1.0 + cosTheta, 0.33) * 0.48;
    // Backward peaks (glory and fogbow)
    var backward = 0.0;
    if cosTheta < -0.9 {
        backward = 0.02; // Glory peak
    } else if cosTheta < -0.5 {
        backward = 0.01; // Fogbow
    }
    
    let intensity = (forwardNarrow + forwardWide + backward) * 0.25;
    return vec3<f32>(intensity * 0.8, intensity * 0.9, intensity);
}

//==============================================================================
// CANONICAL TRANSPORT FUNCTIONS (from 5D table compression)
//==============================================================================

struct CanonicalParams {
    phiV: f32,   // Viewing azimuth angle
    psiV: f32,   // Viewing polar angle  
    phiL: f32,   // Lighting elevation angle
    d: f32,      // Viewpoint depth
    t: f32,      // Slab thickness
    orderSet: u32,
};

struct CollectorResult {
    center: vec3<f32>,
    sigma: f32,
    transport: f32,
};

fn getTableValue(tableOffset: u32, layer: u32, u: f32, v: f32) -> f32 {
    let idx = tableOffset + layer;
    return sampleFromTable(idx, vec2<f32>(u, v));
}

fn computeTransportT(params: CanonicalParams) -> f32 {
    let V = cos(params.phiV);
    let L = cos(params.phiL);
    let cosTheta = cos(params.phiV - params.phiL);
    
    // Sample 2D tables for parameters
    let normD = clamp(params.d / 2000.0, 0.0, 1.0);
    let normT = clamp(params.t / 2000.0, 0.0, 1.0);
    let normV = clamp((V + 1.0) * 0.5, 0.0, 1.0);
    let normL = clamp((L + 1.0) * 0.5, 0.0, 1.0);
    
    var A = getTableValue(TABLE_A_OFFSET, params.orderSet, normT, normV);
    var B1 = getTableValue(TABLE_B1_OFFSET, params.orderSet, normT, normV);
    var B2 = getTableValue(TABLE_B2_OFFSET, params.orderSet, normT, normL);
    var C = getTableValue(TABLE_C_OFFSET, params.orderSet, normT, normV);
    var D = getTableValue(TABLE_D_OFFSET, params.orderSet, normT, normV);
    var P = getTableValue(TABLE_P_OFFSET, params.orderSet, normV, normL);
    var X = getTableValue(TABLE_X_OFFSET, params.orderSet, normT, normL);
    
    // Isotropic case (orders 31+)
    if ORDER_SET_IS_ISOTROPIC[params.orderSet] {
        P = 1.0;
    }
    
    let logTerm = log(params.d + D) / (2.0 * C * C);
    let expTerm = exp(-pow(params.d - (B1 - B2), 2.0) / (2.0 * C * C));
    
    return P * A * X * L * logTerm * expTerm;
}

fn computeCollectorCenter(params: CanonicalParams) -> vec3<f32> {
    let V = cos(params.phiV);
    let normV = clamp((V + 1.0) * 0.5, 0.0, 1.0);
    let sinPsiV = sin(params.psiV);
    let cosPsiV = cos(params.psiV);
    let sinPhiL = sin(params.phiL);
    let cosPhiL = cos(params.phiL);
    
    // Table-sampled coefficients (simplified - full implementation would use 2D tables)
    let E = 0.01 * (1.0 + V);
    let F = 0.5 * (1.0 - normV);
    let G = 1.0 + normV;
    let H = 0.3 * sinPsiV;
    let I = 0.1 * normV;
    let J = 0.2;
    let K = 1.5;
    let L_const = 0.1;
    let M = 0.2 * normV;
    let N = 0.5 * (1.0 + cos(params.phiL) * normV);
    
    let dNorm = clamp(params.d / 1000.0, 0.0, 1.0);
    
    let cx = F * sin(params.psiV) * sin(G * params.phiL) * log(1.0 + E * params.d) + H * sin(params.psiV) * sin(params.phiL);
    let cz = (I + J * (cosPsiV * sin(K * params.phiL) + L_const * params.phiL)) * log(1.0 + E * params.d) + M + N * cosPsiV;
    
    return vec3<f32>(cx, 0.0, cz);
}

fn computeCollectorSigma(params: CanonicalParams) -> f32 {
    // Constants per scattering order set (precomputed)
    let O: array<f32, 8> = array<f32, 8>(20.0, 30.0, 40.0, 50.0, 60.0, 80.0, 100.0, 150.0);
    let Q: array<f32, 8> = array<f32, 8>(0.5, 0.4, 0.3, 0.25, 0.2, 0.15, 0.1, 0.05);
    let R: array<f32, 8> = array<f32, 8>(0.01, 0.008, 0.006, 0.005, 0.004, 0.003, 0.002, 0.001);
    let S: array<f32, 8> = array<f32, 8>(10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 50.0);
    let T_const: array<f32, 8> = array<f32, 8>(0.005, 0.004, 0.003, 0.0025, 0.002, 0.0015, 0.001, 0.0005);
    
    return O[params.orderSet] + Q[params.orderSet] * params.t * log(1.0 + R[params.orderSet] * params.d) + S[params.orderSet] * log(1.0 + T_const[params.orderSet] * params.t);
}

//==============================================================================
// COLLECTOR FINDING ALGORITHM (Fixed-point iteration)
//==============================================================================

fn findCollector(p: vec3<f32>, viewDir: vec3<f32>, lightDir: vec3<f32>, orderSet: u32, ) -> CollectorResult {
    var c = p;  // Initial collector center
    var sigma = 200.0;  // Initial large collector size
    var prevC = c;
    var converged = false;
    var iter = 0u;
    
    while iter < 10u && !converged {
        // Step 1: Project collector onto cloud surface in light direction
        let cRay = Ray(c + lightDir * EPSILON, lightDir);
        let cHit = intersectMesh(cRay);
        var cPrime = c;
        if cHit.distance < INFINITY {
            cPrime = c + lightDir * (cHit.distance - EPSILON);
        }
        
        // Compute local slab parameters
        let d = distance(p, cPrime);
        let t = 1000.0; // Placeholder thickness
        
        // Compute angles in local reference frame
        let localDir = normalize(cPrime - p);
        let phiV = acos(dot(viewDir, localDir));
        let psiV = acos(dot(normalize(cross(viewDir, localDir)), lightDir));
        let phiL = acos(dot(lightDir, localDir));
        
        let params = CanonicalParams(phiV, psiV, phiL, d, t, orderSet);
        
        // Get canonical collector for this configuration
        let newCenter = computeCollectorCenter(params);
        let newSigma = computeCollectorSigma(params);
        
        // Apply damping for stability
        let stepLimit = sigma;
        var step = newCenter - c;
        if length(step) > stepLimit {
            step = normalize(step) * stepLimit;
        }
        c = c + step * 0.5;
        sigma = mix(sigma, newSigma, 0.5);
        
        // Check convergence
        if distance(c, prevC) < sigma * 0.01 {
            converged = true;
        }
        
        prevC = c;
        iter++;
    }
    
    let transport = computeTransportT(CanonicalParams(acos(dot(viewDir, normalize(c - p))), 
                                                       acos(dot(lightDir, normalize(c - p))),
                                                       acos(dot(lightDir, viewDir)),
                                                       distance(p, c), 1000.0, orderSet));
    
    return CollectorResult(c, sigma, transport);
}

//==============================================================================
// MULTIPLE SCATTERING COMPUTATION
//==============================================================================

fn computeMultipleScattering(p: vec3<f32>, viewDir: vec3<f32>, lightDir: vec3<f32>, lightIntensity: vec3<f32>) -> vec3<f32> {
    var result = vec3<f32>(0.0);
    
    for (var orderSet = 0u; orderSet < ORDER_SET_COUNT; orderSet++) {
        // Placeholder depth map
        // var dummyDepth: texture_depth_2d;
        
        let collector = findCollector(p, viewDir, lightDir, orderSet);
        
        // Weight by scattering order count in this set
        let orderCount = ORDER_SET_ENDS[orderSet] - ORDER_SET_STARTS[orderSet] + 1;
        let orderWeight = f32(orderCount);
        
        result += lightIntensity * collector.transport * orderWeight * 0.1;
    }
    
    return result;
}

//==============================================================================
// SINGLE SCATTERING COMPUTATION (Ray marching through cloud)
//==============================================================================

fn computeSingleScattering(ray: Ray, lightDir: vec3<f32>, lightIntensity: vec3<f32>) -> vec3<f32> {
    var result = vec3<f32>(0.0);
    let numSteps = 32u;
    let stepSize = 50.0;  // meters per step
    let extinction = 0.05;  // Extinction coefficient
    
    for (var step = 0u; step < numSteps; step++) {
        let t = f32(step) * stepSize;
        let point = ray.origin + ray.direction * t;
        
        // Check if inside cloud bounds
        if point.x < cloudMesh.boundsMin.x || point.x > cloudMesh.boundsMax.x ||
           point.y < cloudMesh.boundsMin.y || point.y > cloudMesh.boundsMax.y ||
           point.z < cloudMesh.boundsMin.z || point.z > cloudMesh.boundsMax.z {
            continue;
        }
        
        // Compute phase function angle
        let cosTheta = dot(ray.direction, lightDir);
        let phase = miePhaseFunction(cosTheta);
        
        // Attenuation along path
        let attenuation = exp(-extinction * t);
        
        result += lightIntensity * phase * attenuation * stepSize * extinction;
    }
    
    return result * 0.01;
}

//==============================================================================
// OPACITY COMPUTATION (Ray marching through volume)
//==============================================================================

fn computeOpacity(ray: Ray, maxDistance: f32) -> f32 {
    var opacity = 0.0;
    let numSteps = 64u;
    let stepSize = maxDistance / f32(numSteps);
    let extinction = 0.05;
    
    for (var step = 0u; step < numSteps; step++) {
        let t = f32(step) * stepSize;
        if t > maxDistance {
            break;
        }
        
        let point = ray.origin + ray.direction * t;
        
        // Check if inside cloud bounds with procedural density (Hypertexture)
        var density = 0.0;
        if point.x >= cloudMesh.boundsMin.x && point.x <= cloudMesh.boundsMax.x &&
           point.y >= cloudMesh.boundsMin.y && point.y <= cloudMesh.boundsMax.y &&
           point.z >= cloudMesh.boundsMin.z && point.z <= cloudMesh.boundsMax.z {
            // Procedural noise for cloud detail
            let tDelta = f32(frameData.frameCount) * 0.001;
            let noise1 = sin(point.x * 0.05 + tDelta) * sin(point.y * 0.05) * sin(point.z * 0.05);
            let noise2 = sin(point.x * 0.1 + tDelta * 1.3) * cos(point.y * 0.08) * sin(point.z * 0.12);
            let noise3 = sin(point.x * 0.2 + tDelta * 0.7) * sin(point.y * 0.15 + tDelta) * cos(point.z * 0.18);
            let noise = (noise1 + noise2 + noise3) * 0.33;
            
            // Sigmoid function for sharp boundary
            let shellDist = min(point.y - cloudMesh.boundsMin.y, cloudMesh.boundsMax.y - point.y);
            density = 1.0 / (1.0 + exp(-(shellDist - 10.0) * 0.2 + noise * 5.0));
            density = clamp(density, 0.0, 1.0);
        }
        
        let stepOpacity = 1.0 - exp(-extinction * density * stepSize);
        opacity = opacity + (1.0 - opacity) * stepOpacity;
        
        if opacity >= 0.99 {
            break;
        }
    }
    
    return opacity;
}

//==============================================================================
// ENVIRONMENT ILLUMINATION
//==============================================================================

fn getEnvironmentIllumination(dir: vec3<f32>) -> vec3<f32> {
    // Sky color based on direction
    let skyZenith = vec3<f32>(0.4, 0.6, 0.9);
    let skyHorizon = vec3<f32>(0.8, 0.7, 0.6);
    let up = vec3<f32>(0.0, 1.0, 0.0);
    let t = clamp((dot(dir, up) + 1.0) * 0.5, 0.0, 1.0);
    return mix(skyHorizon, skyZenith, t);
}

//==============================================================================
// MAIN COMPUTE SHADER
//==============================================================================

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(outputTex);
    if id.x >= dimensions.x || id.y >= dimensions.y {
        return;
    }
    
    let uv = vec2<f32>(f32(id.x) / f32(dimensions.x), f32(id.y) / f32(dimensions.y));
    let aspect = f32(dimensions.x) / f32(dimensions.y);
    
    // Anti-aliasing via jittered sampling
    var finalColor = vec3<f32>(0.0);
    let samples = max(1u, settings.antiAliasingSamples);

    let size = vec2<f32>(f32(dimensions.x), f32(dimensions.y));
    
    for (var sample = 0u; sample < samples; sample++) {
        let jitterX = (f32(sample) / f32(samples)) * 0.5 - 0.25;
        let jitterY = (f32(sample) / f32(samples)) * 0.5 - 0.25;
        let sampleUV = uv + vec2<f32>(jitterX / f32(dimensions.x), jitterY / f32(dimensions.y));
        
        // Generate camera ray
        let rayDir = getRayDirection(sampleUV, camera, size);
        let ray = Ray(camera.position, rayDir);
        
        // Light direction (sun)
        let lightDir = normalize(vec3<f32>(0.5, 0.8, 0.3));
        let lightIntensity = vec3<f32>(1.0, 0.95, 0.85);
        
        // Find cloud intersection
        var cloudHit = false;
        var hitPoint = vec3<f32>(0.0);
        var hitDistance = INFINITY;
        
        // Check against cloud mesh bounding box
        let boxMin = cloudMesh.boundsMin;
        let boxMax = cloudMesh.boundsMax;
        let invDir = 1.0 / ray.direction;
        let t1 = (boxMin - ray.origin) * invDir;
        let t2 = (boxMax - ray.origin) * invDir;
        let tMin = max(min(t1.x, t2.x), max(min(t1.y, t2.y), min(t1.z, t2.z)));
        let tMax = min(max(t1.x, t2.x), min(max(t1.y, t2.y), max(t1.z, t2.z)));
        
        if tMin < tMax && tMax > 0.0 {
            cloudHit = true;
            hitDistance = max(tMin, 0.0);
            hitPoint = ray.origin + ray.direction * hitDistance;
        }
        
        if !cloudHit {
            // No cloud - show sky/environment
            finalColor += getEnvironmentIllumination(rayDir);
            continue;
        }
        
        // Compute single scattering contribution (first order)
        let singleScatter = computeSingleScattering(ray, lightDir, lightIntensity);
        
        // Compute multiple scattering (orders 2+)
        let multipleScatter = computeMultipleScattering(hitPoint, rayDir, lightDir, lightIntensity);
        
        // Compute opacity for compositing
        let cloudRay = Ray(hitPoint, rayDir);
        let opacity = computeOpacity(cloudRay, 500.0);
        
        // Environment illumination through cloud
        let environment = getEnvironmentIllumination(rayDir);
        
        // Composite final color
        let scatteredLight = singleScatter + multipleScatter;
        var color = mix(environment, scatteredLight, opacity);
        
        // Tone mapping (simplified Reinhard)
        color = color / (color + vec3<f32>(1.0));
        
        // Gamma correction
        color = pow(color, vec3<f32>(1.0 / 2.2));
        
        finalColor += color;
    }
    
    finalColor /= f32(samples);
    
    // Write to output texture
    textureStore(outputTex, vec2<i32>(i32(id.x), i32(id.y)), vec4<f32>(finalColor, 1.0));
}