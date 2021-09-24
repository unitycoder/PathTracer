#ifndef TRACER_FUNCTIONS
#define TRACER_FUNCTIONS

#include "global.hlsl"
#include "structures.hlsl"
#include "random.hlsl"

Camera CreateCamera()
{
    Camera camera;
    camera.fov = _CameraInfo.x;
    camera.focalDist = _CameraInfo.y;
    camera.aperture = _CameraInfo.z;
    camera.ratio = _CameraInfo.w;
    camera.offset = _PixelOffset;
    camera.forward = _CameraForward;
    camera.right = _CameraRight;
    camera.up = _CameraUp;
    camera.pos = _CameraPos;
    return camera;
}

Ray CreateRay(float3 origin, float3 direction)
{
    Ray ray;
    ray.origin = origin;
    ray.dir = direction;
    ray.energy = 1.0;
    return ray;
}

Ray CreateCameraRay(Camera camera, float2 uv, float2 dims)
{
    //float3 origin = mul(_CameraToWorld, float4(0.0, 0.0, 0.0, 1.0)).xyz;
    //float3 direction = mul(_CameraProjInv, float4(uv, 0.0, 1.0)).xyz;
    //direction = mul(_CameraToWorld, float4(direction, 0.0)).xyz;
    //direction = normalize(direction);
    //return CreateRay(origin, direction);
    
    // reference: https://github.com/knightcrawler25/GLSL-PathTracer/blob/master/src/shaders/preview.glsl
    //float2 d = 2.0 * (uv + camera.offset) / dims - 1.0;
    //float scale = tan(camera.fov * 0.5f);
    //d.x *= scale;
    //d.y *= camera.ratio * scale;
    //float3 direction = normalize(d.x * camera.right + d.y * camera.up + camera.forward);
    //float3 focalPoint = direction * camera.focalDist;
    //float cam_r1 = rand() * PI * 2.0;
    //float cam_r2 = rand() * camera.aperture;
    //float3 randomAperturePos = (cos(cam_r1) * camera.right + sin(cam_r1) * camera.up) * sqrt(cam_r2);
    //float3 finalRayDir = normalize(focalPoint - randomAperturePos);
    //return CreateRay(camera.pos + randomAperturePos, finalRayDir);
    
    float2 d = 2.0 * (uv + camera.offset) / dims - 1.0;
    float scale = tan(camera.fov * 0.5f);
    d.x *= scale;
    d.y *= camera.ratio * scale;
    float3 direction = normalize(d.x * camera.right + d.y * camera.up + camera.forward);
    return CreateRay(camera.pos, direction);
}

Colors CreateColors(float3 baseColor, float3 emission, float metallic)
{
    const float alpha = 0.04;
    Colors colors;
    colors.albedo = lerp(baseColor * (1.0 - alpha), 0.0, metallic);
    colors.specular = lerp(alpha, baseColor, metallic);
    colors.emission = emission;
    return colors;
}

HitInfo CreateHitInfo()
{
    HitInfo hit;
    hit.dist = 1.#INF;
    hit.pos = 0.0;
    hit.norm = 0.0;
    hit.colors = CreateColors(0.0, 0.0, 0.0);
    hit.smoothness = 0.0;
    hit.mode = 0.0;
    return hit;
}

// return true if it is backface
bool CullFace(float3 norm, float3 eye, float3 pos)
{
    return dot(norm, (eye - pos)) < 0.0;
}

// create new sample direction in a hemisphere
float3 SampleHemisphere1(float3 norm, float alpha = 0.0)
{
    float cosTheta = pow(rand(), 1.0 / (1.0 + alpha));
    float sinTheta = sqrt(max(0.0, 1.0 - cosTheta * cosTheta));
    float phi = 2.0 * PI * rand();
    float3 tangentSpaceDir = float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);
    // from tangent space to world space
    float3 helper = float3(1, 0, 0);
    if (abs(norm.x) > 0.99)
        helper = float3(0, 0, 1);
    float3 tangent = normalize(cross(norm, helper));
    float3 binormal = normalize(cross(norm, tangent));
    // get new direction
    return mul(tangentSpaceDir, float3x3(tangent, binormal, norm));
}

// reference: https://github.com/LWJGL/lwjgl3-demos/blob/main/res/org/lwjgl/demo/opengl/raytracing/randomCommon.glsl
float3 SampleHemisphere2(float3 norm)
{
    float angle = rand() * 2.0 * PI;
    float u = rand() * 2.0 - 1.0;
    float sqrtMinusU2 = sqrt(1.0 - u * u);
    float3 v = float3(sqrtMinusU2 * cos(angle), sqrtMinusU2 * sin(angle), u);
    return v * sign(dot(v, norm));
}

float3 SampleHemisphere3(float3 norm, float alpha = 0.0)
{
    float3 randomVec = float3(rand(), rand(), rand());
    float r = pow(randomVec.x, 1.0 / (1.0 + alpha));
    float angle = randomVec.y * 2.0 * PI;
    float sr = sqrt(1.0 - r * r);
    float3 ph = float3(sr * cos(angle), sr * sin(angle), r);
    float3 tangent = normalize(randomVec * 2.0 - 1.0);
    float3 bitangent = normalize(cross(tangent, norm));
    tangent = normalize(cross(bitangent, norm));
    return mul(ph, float3x3(tangent, bitangent, norm));
}

// reference: https://www.scratchapixel.com/lessons/3d-basic-rendering/introduction-to-shading/reflection-refraction-fresnel
float Fresnel(float3 dir, float3 norm, float ior)
{
    float cosi = clamp(dot(dir, norm), -1.0, 1.0);
    float etai, etat;
    if(cosi > 0.0)
    {
        etai = ior;
        etat = 1.0;
    }
    else
    {
        etai = 1.0;
        etat = ior;
    }
    float sint = etai / etat * sqrt(1.0 - cosi * cosi);
    if(sint >= 1.0)
    {
        return 1.0;
    }
    else
    {
        float cost = sqrt(max(0.0, 1.0 - sint * sint));
        cosi = abs(cosi);
        float Rs = ((etat * cosi) - (etai * cost)) / ((etat * cosi) + (etai * cost));
        float Rp = ((etai * cosi) - (etat * cost)) / ((etai * cosi) + (etat * cost));
        return (Rs * Rs + Rp * Rp) / 2.0;
    }
}

// prepare a new ray when entering a BLAS tree
Ray PrepareTreeEnterRay(Ray ray, int transformIdx)
{
    float4x4 worldToLocal = _Transforms[transformIdx * 2 + 1];
    float3 origin = mul(worldToLocal, float4(ray.origin, 1.0)).xyz;
    float3 dir = normalize(mul(worldToLocal, float4(ray.dir, 0.0)).xyz);
    return CreateRay(origin, dir);
}

void PrepareTreeEnterHit(Ray rayLocal, inout HitInfo hit, int transformIdx)
{
    float4x4 worldToLocal = _Transforms[transformIdx * 2 + 1];
    if (hit.dist < 1.#INF)
    {
        hit.pos = mul(worldToLocal, float4(hit.pos, 1.0)).xyz;
        hit.dist = length(hit.pos - rayLocal.origin);
    }
}

// update a hit info after exiting a BLAS tree
void PrepareTreeExit(Ray rayWorld, inout HitInfo hit, int transformIdx)
{
    float4x4 localToWorld = _Transforms[transformIdx * 2];
    if (hit.dist < 1.#INF)
    {
        hit.pos = mul(localToWorld, float4(hit.pos, 1.0)).xyz;
        hit.dist = length(hit.pos - rayWorld.origin);
    }
}
#endif