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
    // Simple euler angle rotation - you may want to use a proper rotation matrix/quaternion
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
            // flip if inside the sphere
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
        // alternate materials
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
    return vec3<f32>(0.5, 0.7, 1.0) * (ray.direction.y + 1.0);
    // let ndc = ray.direction;
    // let uv = ndc.xy * 0.5 + 0.5;
    // return vec3<f32>(uv, 1.0);
}

fn calculateLight(ray : Ray, intersection : Intersection) -> vec3<f32> {
    // loop through all spheres and if they are light sources, add their contribution to the lighting
    // also add directional sunlight
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
    // add directional sunlight
    // let sunlightDir = normalize(vec3<f32>(1.0, -1.0, 1.0));
    // let sunlightIntensity = 1.0;
    // let diffuse = max(dot(intersection.normal, sunlightDir), 0.0);
    // lightColor += vec3<f32>(1.0, 1.0, 0.9) * diffuse * sunlightIntensity;
    return lightColor;
}

fn getNextRay(ray : Ray, intersection : Intersection) -> Ray {
    if (intersection.material.refractiveIndex > 0.0) {
        return calculateRefractedRay(ray, intersection);
    }
    // Use cosine-weighted hemisphere sampling for diffuse materials
    let reflectionDir = hemisphereRandom(intersection.normal);

    var newOrigin = intersection.distance * ray.direction + ray.origin;
    newOrigin += intersection.normal * EPSILON;
    return Ray(newOrigin, reflectionDir);
}

fn calculateRefractedRay(ray : Ray, intersection : Intersection) -> Ray {
    // use snell's law to calculate refracted ray
    var n1 = 1.0; // air
    var n2 = intersection.material.refractiveIndex;
    if (intersection.isBackFace) {
        // exiting the material
        n2 = 1.0;
        n1 = intersection.material.refractiveIndex;
    }

    let n = n1 / n2;
    let cosI = -dot(intersection.normal, ray.direction);
    let sinT2 = n * n * (1.0 - cosI * cosI);
    if (sinT2 > 1.0) {
        // total internal reflection
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
    // Cosine-weighted hemisphere sampling using proper RNG
    let u1 = randomFloat();
    let u2 = randomFloat();

    let r = sqrt(u1);
    let theta = 2.0 * PI * u2;

    let x = r * cos(theta);
    let y = r * sin(theta);
    let z = sqrt(max(0.0, 1.0 - u1));

    // Create an orthonormal basis (TBN)
    var tangent : vec3<f32>;
    if (abs(normal.x) > abs(normal.z)) {
        tangent = normalize(vec3<f32>(-normal.y, normal.x, 0.0));
    } else {
        tangent = normalize(vec3<f32>(0.0, -normal.z, normal.y));
    }
    let bitangent = cross(normal, tangent);

    // Transform sample to world space
    return normalize(x * tangent + y * bitangent + z * normal);
}

// Alternative: uniform hemisphere sampling
fn hemisphereUniform(normal: vec3<f32>) -> vec3<f32> {
    let randomDir = randomUnitVector();
    if (dot(randomDir, normal) > 0.0) {
        return randomDir;
    } else {
        return -randomDir;
    }
}

fn castRay(ray : Ray) -> vec3<f32> {
    var currentRay = ray;
    var radiance = vec3<f32>(0.0);
    var throughput = vec3<f32>(1.0);
    for (var bounce = 0u; bounce < settings.maxBounces; bounce++) {
        let intersection = intersectWorld(currentRay);
        if (intersection.distance >= Infinity) {
            radiance += getSkyBoxColor(currentRay) * throughput;
            break;
        } else {
            radiance += throughput * intersection.material.emissionColor * intersection.material.emission;
            if (intersection.material.refractiveIndex > 0.0) {
                // pass
            } else {
                throughput *= intersection.material.color;
            }
            
            currentRay = getNextRay(currentRay, intersection);
            // TODO: Add russian roulette termination
        }
    }
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

    // Initialize RNG with unique seed per pixel
    let pixelIndex = gid.y * size.x + gid.x;
    let rngSeed = pixelIndex * 747796405u + 2891336453u + frameData.frameCount;
    initRNG(rngSeed);

    var uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(size);
    uv.y = 1.0 - uv.y; // flip just cuz

    var ndc = uv * 2.0 - 1.0;

    // let ray = createRay(uv, vec2<f32>(size));
    // let color = castRay(ray);
    let color = fakeAntiAliasing(uv, vec2<f32>(size));

    textureStore(outputTex, vec2<i32>(gid.xy), vec4<f32>(color, 1.0));
}
