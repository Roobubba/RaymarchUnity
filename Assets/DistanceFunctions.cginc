// Sphere
// s: radius
float sdSphere(float3 p, float s)
{
	return length(p) - s;
}

// Plane
// n.xyz: normal of the plane (normalized)
// n.w: offset
float sdPlane(float3 p, float4 n)
{
    return dot(p, n.xyz) + n.w;
}

// Box
// b: size of box in x/y/z
float sdBox(float3 p, float3 b)
{
	float3 d = abs(p) - b;
	return min(max(d.x, max(d.y, d.z)), 0.0) +
		length(max(d, 0.0));
}

// RoundedBox
float sdRoundBox(float3 p, float3 b, float r)
{
    float3 d = abs(p) - b;
    return length(max(d, 0.0)) - r
        + min(max(d.x, max(d.y, d.z)), 0.0); // remove this line for an only partially signed sdf 
}

// BOOLEAN OPERATORS //

// Union
float4 opU(float4 d1, float4 d2)
{
    return (d1.w < d2.w) ? d1 : d2;
}

// Subtraction
float opS(float d1, float d2)
{
	return max(-d1, d2);
}

// Intersection
float opI(float d1, float d2)
{
	return max(d1, d2);
}

// Smooth Union
float4 opSmoothUnion(float4 d1, float4 d2, float k) {
    float h = clamp(0.5 + 0.5*(d2.w - d1.w) / k, 0.0, 1.0);
    float3 colour = lerp(d2.rgb, d1.rgb, h);
    float dist = lerp(d2.w, d1.w, h) - k * h*(1.0 - h);
    return float4(colour, dist);
}

// Smooth Subtraction
float opSmoothSubtraction(float d1, float d2, float k) {
    float h = clamp(0.5 - 0.5*(d2 + d1) / k, 0.0, 1.0);
    return lerp(d2, -d1, h) + k * h*(1.0 - h);
}

// Smooth Intersection
float opSmoothIntersection(float d1, float d2, float k) {
    float h = clamp(0.5 - 0.5*(d2 - d1) / k, 0.0, 1.0);
    return lerp(d2, d1, h) + k * h*(1.0 - h);
}

// Mod Position Axis
float pMod1 (inout float p, float size)
{
	float halfsize = size * 0.5;
	float c = floor((p+halfsize)/size);
	p = fmod(p+halfsize,size)-halfsize;
	p = fmod(-p+halfsize,size)-halfsize;
	return c;
}

