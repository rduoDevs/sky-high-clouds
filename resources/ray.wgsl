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

@group(0) @binding(5) var<storage, read> triangles: array<Triangle>;
@group(0) @binding(6) var<uniform> cloudMesh: CloudMesh;

const Infinity = 1e6;
const GroundYLevel = -1.0;
const NoMaterial = Material(vec3<f32>(0.0), 0.0, 0.0, 0.0, vec3<f32>(0.0), 0.0);
const GroundMaterial1 = Material(vec3<f32>(0.5, 0.5, 0.5), 0.0, 0.0, 0.0, vec3<f32>(0.0), 0.0);
const GroundMaterial2 = Material(vec3<f32>(0.3, 0.3, 0.3), 0.0, 0.0, 0.0, vec3<f32>(0.0), 0.0);
const NoIntersection = Intersection(Infinity, vec3<f32>(0.0), false, NoMaterial);
const EPSILON = 1e-4;
const PI = 3.14159265359;

@group(0) @binding(0) var<uniform> camera : Camera;
@group(0) @binding(1) var<storage, read> world : World;
@group(0) @binding(2) var outputTex : texture_storage_2d<rgba8unorm, write>;
@group(0) @binding(3) var<uniform> settings : Settings;
@group(0) @binding(4) var<uniform> frameData : FrameUniform;

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

// ============= Cloud Volume Functions =============

// Mie scattering approximation
fn henyeyGreenstein(cosTheta: f32, g: f32) -> f32 {
    let g2 = g * g;
    let denom = 1.0 + g2 - 2.0 * g * cosTheta;
    return (1.0 - g2) / (4.0 * PI * pow(denom, 1.5));
}

// Cloud density function - uses noise within sphere bounds
fn cloudDensityAtPoint(pos: vec3<f32>) -> f32 {
    let expandMin = cloudMesh.boundsMin - vec3<f32>(cloudMesh.shellThickness);
    let expandMax = cloudMesh.boundsMax + vec3<f32>(cloudMesh.shellThickness);
    if (any(pos < expandMin) || any(pos > expandMax)) {
        return 0.0;
    }

    let dist = distanceToMesh(pos);
    if (dist > cloudMesh.shellThickness) {
        return 0.0;
    }

    let surfaceFactor = 1.0 - smoothstep(0.0, cloudMesh.shellThickness, dist);
    let time = f32(frameData.frameCount) * 0.06;
    let windOffset = vec3<f32>(time * 0.5, time * 0.2, time * 0.3);
    let baseNoise = fbm(pos * 0.8 + windOffset)+0.1;
    let detail = perlin3D(pos * 2.0 + windOffset * 2.0) * 0.15;
    let density = surfaceFactor * (baseNoise + detail);
    return density * 10.0;
}

//legacy; for sphere-bounded cloud
fn intersectCloudSphere(ray: Ray, center: vec3<f32>, radius: f32) -> vec2<f32> {
    let oc = ray.origin - center;
    let a = dot(ray.direction, ray.direction);
    let b = 2.0 * dot(oc, ray.direction);
    let c = dot(oc, oc) - radius * radius;
    let discriminant = b * b - 4.0 * a * c;

    if (discriminant < 0.0) {
        return vec2<f32>(-1.0, -1.0); // No intersection
    }

    let sqrtDisc = sqrt(discriminant);
    let t1 = (-b - sqrtDisc) / (2.0 * a);
    let t2 = (-b + sqrtDisc) / (2.0 * a);

    if (t2 < 0.0) {
        return vec2<f32>(-1.0, -1.0); // Behind camera
    }

    let tmin = max(t1, 0.0);
    let tmax = t2;

    return vec2<f32>(tmin, tmax);
}

fn sampleCloudLighting(pos: vec3<f32>, sunDir: vec3<f32>) -> f32 {
    let lightStepSize = 0.15;
    let lightSteps = 6;
    var transmittance = 1.0;
    for (var i = 0; i < lightSteps; i++) {
        let lightPos = pos + sunDir * f32(i) * lightStepSize;
        let density = cloudDensityAtPoint(lightPos);
        transmittance *= exp(-density * lightStepSize * 0.8);
        if (transmittance < 0.01) {
            break;
        }
    }

    return transmittance;
}

fn distanceToTriangle(p: vec3<f32>, tri: Triangle) -> f32 {
    let edge0 = tri.v1 - tri.v0;
    let edge1 = tri.v2 - tri.v0;
    let v0p   = tri.v0 - p;

    let a = dot(edge0, edge0);
    let b = dot(edge0, edge1);
    let c = dot(edge1, edge1);
    let d = dot(edge0, v0p);
    let e = dot(edge1, v0p);

    let det = a * c - b * b;
    var s = b * e - c * d;
    var t = b * d - a * e;

    if (s + t <= det) {
        if (s < 0.0) {
            if (t < 0.0) {
                if (d < 0.0) { s = clamp(-d / a, 0.0, 1.0); t = 0.0; }
                else         { s = 0.0; t = clamp(-e / c, 0.0, 1.0); }
            } else {
                s = 0.0; t = clamp(-e / c, 0.0, 1.0);
            }
        } else if (t < 0.0) {
            s = clamp(-d / a, 0.0, 1.0); t = 0.0;
        } else {
            let invDet = 1.0 / det;
            s = s * invDet; t = t * invDet;
        }
    } else {
        if (s < 0.0) {
            let tmp0 = b + d;
            let tmp1 = c + e;
            if (tmp1 > tmp0) {
                let numer = tmp1 - tmp0;
                let denom = a - 2.0 * b + c;
                s = clamp(numer / denom, 0.0, 1.0); t = 1.0 - s;
            } else {
                s = 0.0; t = clamp(-e / c, 0.0, 1.0);
            }
        } else if (t < 0.0) {
            let tmp0 = b + e;
            let tmp1 = a + d;
            if (tmp1 > tmp0) {
                let numer = tmp1 - tmp0;
                let denom = a - 2.0 * b + c;
                t = clamp(numer / denom, 0.0, 1.0); s = 1.0 - t;
            } else {
                t = 0.0; s = clamp(-d / a, 0.0, 1.0);
            }
        } else {
            let numer = c + e - b - d;
            if (numer <= 0.0) { s = 0.0; }
            else {
                let denom = a - 2.0 * b + c;
                s = clamp(numer / denom, 0.0, 1.0);
            }
            t = 1.0 - s;
        }
    }

    let closest = tri.v0 + s * edge0 + t * edge1;
    return length(p - closest);
}

fn distanceToMesh(p: vec3<f32>) -> f32 {
    var minDist = 1e6;
    for (var i = 0u; i < cloudMesh.triangleCount; i = i + 1u) {
        let d = distanceToTriangle(p, triangles[cloudMesh.triangleOffset + i]);
        minDist = min(minDist, d);
    }
    return minDist;
}

fn intersectAABB(ray: Ray, bMin: vec3<f32>, bMax: vec3<f32>) -> vec2<f32> {
    let invDir = 1.0 / ray.direction;
    let t0 = (bMin - ray.origin) * invDir;
    let t1 = (bMax - ray.origin) * invDir;
    let tmin = min(t0, t1);
    let tmax = max(t0, t1);
    let tNear = max(max(tmin.x, tmin.y), tmin.z);
    let tFar  = min(min(tmax.x, tmax.y), tmax.z);
    if (tNear > tFar || tFar < 0.0) {
        return vec2<f32>(-1.0, -1.0);
    }
    return vec2<f32>(max(tNear, 0.0), tFar);
}

fn raymarchCloudMesh(ray: Ray, tmin: f32, tmax: f32) -> vec4<f32> {
    let sunDir = normalize(vec3<f32>(0.5, 1.0, 0.3));
    let sunColor = vec3<f32>(1.2,1.2,1.2) * 15.0;
    let ambientColor = vec3<f32>(1.2, 1.0,1.0);
    let stepSize = 0.025;
    let extinction = 0.8;
    let scattering = 1.5;
    let g = 0.7;

    var color = vec3<f32>(0.0);
    var transmittance = 1.0;
    var t = tmin;

    while (t < tmax && transmittance > 0.01) {
        let pos = ray.origin + ray.direction * t;
        let density = cloudDensityAtPoint(pos);
        if (density > 0.001) {
            let sampleT = exp(-density * stepSize * extinction);
            let cosTheta = dot(ray.direction, sunDir);
            let phase = henyeyGreenstein(cosTheta, g);
            let lightEnergy = sampleCloudLighting(pos, sunDir);
            let scattered = sunColor * density * scattering * phase * lightEnergy;
            let ambient = ambientColor * density * 0.5;
            color += (scattered + ambient) * transmittance * stepSize;
            transmittance *= sampleT;
        }
        t += stepSize;
    }
    return vec4<f32>(color, 1.0 - transmittance);
}

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

fn intersectSphere(ray : Ray, sphere : Sphere) -> Intersection {
    let oc = ray.origin - sphere.center;
    let a = dot(ray.direction, ray.direction);
    let b = 2.0 * dot(oc, ray.direction);
    let c = dot(oc, oc) - sphere.radius * sphere.radius;
    let discriminant = b*b - 4.0*a*c;
    if (discriminant < 0.0) {
        return NoIntersection;
    } else {
        let t1 = (-b + sqrt(discriminant)) / (2.0*a);
        let t2 = (-b - sqrt(discriminant)) / (2.0*a);
        let minT = min(t1, t2);
        let maxT = max(t1, t2);

        // Use the closest positive t value
        var t = minT;
        if (t < EPSILON) {
            t = maxT;
        }
        if (t < EPSILON) {
            return NoIntersection;
        }

        let hitPoint = ray.origin + t * ray.direction;
        var normal = normalize(hitPoint - sphere.center);
        var isBackFace = dot(ray.direction, normal) > 0.0;
        if (isBackFace) {
            normal = -normal;
        }
        return Intersection(t, normal, isBackFace, sphere.material);
    }
}

fn intersectWorld(ray : Ray) -> Intersection {
    var closestIntersection = NoIntersection;
    for (var i = 0u; i < 2u; i++) {
        let sphere = world.spheres[i];
        let intersection = intersectSphere(ray, sphere);
        if (intersection.distance < closestIntersection.distance) {
            closestIntersection = intersection;
        }
    }

    let groundIntersection = intersectGridGround(ray);
    if (groundIntersection.distance < closestIntersection.distance) {
        closestIntersection = groundIntersection;
    }

    return closestIntersection;
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

fn getSkyBoxColor(ray : Ray) -> vec3<f32> {
    let t = 0.5 * (ray.direction.y + 1.0);
    return mix(vec3<f32>(1.0, 0.9, 1.0), vec3<f32>(0.7, 0.8, 1.0), t);
}

fn calculateLight(ray : Ray, intersection : Intersection) -> vec3<f32> {
    var lightColor = vec3<f32>(0.0);
    for (var i = 0u; i < 2u; i++) {
        let sphere = world.spheres[i];
        if (sphere.material.emission > 0.0) {
            let lightDir = normalize(sphere.center - intersection.distance * ray.direction + ray.origin);
            let lightDist = distance(sphere.center, intersection.distance * ray.direction + ray.origin);
            let shadowRay = Ray(intersection.distance * ray.direction + ray.origin, lightDir);
            let shadowIntersection = intersectWorld(shadowRay);
            if (shadowIntersection.distance > lightDist) {
                let diffuse = max(dot(intersection.normal, lightDir), 0.0);
                lightColor += sphere.material.emissionColor * diffuse / (lightDist * lightDist);
            }
        }
    }
    return lightColor;
}

fn getNextRay(ray : Ray, intersection : Intersection) -> Ray {
    if (intersection.material.refractiveIndex > 0.0) {
        return calculateRefractedRay(ray, intersection);
    }
    let reflectionDir = hemisphereRandom(intersection.normal);
    var newOrigin = intersection.distance * ray.direction + ray.origin;
    newOrigin += intersection.normal * EPSILON;
    return Ray(newOrigin, reflectionDir);
}

fn calculateRefractedRay(ray : Ray, intersection : Intersection) -> Ray {
    var n1 = 1.0;
    var n2 = intersection.material.refractiveIndex;
    if (intersection.isBackFace) {
        n2 = 1.0;
        n1 = intersection.material.refractiveIndex;
    }

    let n = n1 / n2;
    let cosI = -dot(intersection.normal, ray.direction);
    let sinT2 = n * n * (1.0 - cosI * cosI);
    if (sinT2 > 1.0) {
        let reflectDir = reflect(ray.direction, intersection.normal);
        var newOrigin = intersection.distance * ray.direction + ray.origin;
        newOrigin += intersection.normal * EPSILON;
        return Ray(newOrigin, reflectDir);
    } else {
        let cosT = sqrt(1.0 - sinT2);
        let refractDir = n * ray.direction + (n * cosI - cosT) * intersection.normal;
        var newOrigin = intersection.distance * ray.direction + ray.origin;
        newOrigin -= intersection.normal * EPSILON;
        return Ray(newOrigin, refractDir);
    }
}

fn hemisphereRandom(normal : vec3<f32>) -> vec3<f32> {
    let u1 = randomFloat();
    let u2 = randomFloat();

    let r = sqrt(u1);
    let theta = 2.0 * PI * u2;

    let x = r * cos(theta);
    let y = r * sin(theta);
    let z = sqrt(max(0.0, 1.0 - u1));

    var tangent : vec3<f32>;
    if (abs(normal.x) > abs(normal.z)) {
        tangent = normalize(vec3<f32>(-normal.y, normal.x, 0.0));
    } else {
        tangent = normalize(vec3<f32>(0.0, -normal.z, normal.y));
    }
    let bitangent = cross(normal, tangent);

    return normalize(x * tangent + y * bitangent + z * normal);
}

fn castRay(ray: Ray) -> vec3<f32> {
    var radiance = vec3<f32>(0.0);
    var throughput = vec3<f32>(1.0);

    let expandMin = cloudMesh.boundsMin - vec3<f32>(cloudMesh.shellThickness);
    let expandMax = cloudMesh.boundsMax + vec3<f32>(cloudMesh.shellThickness);
    let hit = intersectAABB(ray, expandMin, expandMax);

    if (hit.x >= 0.0) {
        let result = raymarchCloudMesh(ray, hit.x, hit.y);
        radiance += result.rgb * throughput;
        throughput *= (1.0 - result.a);
    }

    radiance += getSkyBoxColor(ray) * throughput;
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
