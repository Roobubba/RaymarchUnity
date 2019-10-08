Shader "Hidden/RaymarchTestTextureShader"
{
	Properties
	{
		_MainTex("Texture", 2D) = "white" {}
	}

	SubShader
	{
		// No culling or depth
		Cull Off ZWrite Off ZTest Always

		Pass
		{
			CGPROGRAM

			#pragma vertex vert
			#pragma fragment frag
			#pragma target 5.0

			#include "UnityCG.cginc"
			#include "DistanceFunctions.cginc"

			sampler2D _MainTex;

			uniform StructuredBuffer<float4> _SphereBuffer;
			uniform int _SphereBufferLength;

			//Raymarching Setup
			uniform sampler2D _CameraDepthTexture;
			uniform float4x4 _CamFrustum, _CamToWorld;
			uniform int _MaxIterations;
			uniform float _MaxDistance, _Accuracy;

			//Colour
			uniform fixed4 _GroundColour;
			uniform fixed4 _TestColour;
			uniform float _ColourIntensity;

			//Light
			uniform float3 _LightDirection, _LightColour;
			uniform float _LightIntensity;

			//Shadow
			uniform float2 _ShadowDistance;
			uniform float _ShadowIntensity, _ShadowPenumbra;

			//AmbientOcclusion
			uniform float _AmbientOcclusionStepSize, _AmbientOcclusionIntensity;
			uniform int _AmbientOcclusionIterations;

			//Reflections
			uniform int _ReflectionCount;
			uniform float _ReflectionIntensity, _EnvironmentReflectionIntensity;
			uniform samplerCUBE _ReflectionCube;

			//SDF
			uniform float _SphereSmooth;

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
				float3 ray : TEXCOORD1;
			};

			v2f vert(appdata v)
			{
				v2f o;
				half index = v.vertex.z;
				v.vertex.z = 0;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				o.ray = _CamFrustum[(int)index].xyz;
				o.ray /= abs(o.ray.z);
				o.ray = mul(_CamToWorld, o.ray);

				return o;
			}

			float4 distanceField(float3 p)
			{
				float4 Sphere = float4(_TestColour.rgb, sdSphere(p - _SphereBuffer[0].xyz, _SphereBuffer[0].w * 0.5));
				for (int i = 1; i < _SphereBufferLength; i++)
				{
					float4 SphereAdd = float4(_TestColour.rgb, sdSphere(p - _SphereBuffer[i].xyz, _SphereBuffer[i].w * 0.5));
					Sphere = opSmoothUnion(Sphere, SphereAdd, _SphereSmooth);
				}
				return Sphere;
			}

			float3 getNormal(float3 p)
			{
				//need the normal, so we're going to calculate distance field +/- offsets. Can this be sped up for the sphere case - even with smoothing?
				//Sure we can reduce the number of calls to distanceField by taking the pos - atomCentre as the normal and lerping between this and neighbouring atoms' values
				// TODO: optimisation here
				const float2 offset = float2(0.001, 0.0);
				float3 n = float3
					(distanceField(p + offset.xyy).w - distanceField(p - offset.xyy).w,
						distanceField(p + offset.yxy).w - distanceField(p - offset.yxy).w,
					distanceField(p + offset.yyx).w - distanceField(p - offset.yyx).w);
				return normalize(n);
			}

			float HardShadow(float3 ro, float3 rd, float minT, float maxT)
			{
				for (float t = minT; t < maxT;)
				{
					float h = distanceField(ro + rd * t).w;
					if (h < 0.001)
					{
						return 0.0;
					}
					t += h;
				}
				return 1.0;
			}

			float SoftShadow(float3 ro, float3 rd, float minT, float maxT, float k)
			{
				float result = 1.0;

				for (float t = minT; t < maxT;)
				{
					float h = distanceField(ro + rd * t).w;
					if (h < 0.001)
					{
						return 0.0;
					}
					result = min(result, k * h / t);
					t += h;
				}
				return result;
			}

			float AmbientOcclusion(float3 p, float3 n)
			{
				float step = _AmbientOcclusionStepSize;
				float ao = 0.0;
				float dist;
				for (int i = 1; i <= _AmbientOcclusionIterations; i++)
				{
					dist = step * i;
					ao += max(0.0, (dist - distanceField(p + n * dist).w) / dist);
				}
				return (1.0 - ao * _AmbientOcclusionIntensity);
			}

			float3 Shading(float3 p, float3 n, fixed3 c)
			{
				float3 result;

				//Diffuse Colour
				float3 colour = c.rgb * _ColourIntensity;

				//Directional Light
				float3 light = (_LightColour * dot(-_LightDirection, n) * 0.5 + 0.5) * _LightIntensity;

				//Shadows
				float shadow = SoftShadow(p, -_LightDirection, _ShadowDistance.x, _ShadowDistance.y, _ShadowPenumbra) * 0.5 + 0.5;
				shadow = max(0.0, pow(shadow, _ShadowIntensity));

				//Ambient Occlusion
				float ao = AmbientOcclusion(p, n);

				result = colour * light * shadow * ao;

				return result;
			}

			bool raymarching(float3 ro, float3 rd, float depth, float maxDistance, int maxIterations, inout float3 p, inout fixed3 dColour)
			{
				bool hit;
				float t = 0; // distance travelled along ray direction

				for (int i = 0; i < maxIterations; i++)
				{
					if (t > maxDistance || t >= depth)
					{
						//Background
						hit = false;
						break;
					}

					p = ro + rd * t;

					//check SDF for a hit

					float4 d = distanceField(p);

					//if we hit something
					if (d.w < _Accuracy)
					{
						dColour = d.rgb;
						hit = true;
						break;
					}
					t += d.w;

				}

				return hit;
			}

			fixed4 frag(v2f i) : SV_Target
			{
				float depth = LinearEyeDepth(tex2D(_CameraDepthTexture, i.uv).r);
				depth *= length(i.ray);
				fixed3 col = tex2D(_MainTex, i.uv);
				float3 rayDirection = normalize(i.ray.xyz);
				float3 rayOrigin = _WorldSpaceCameraPos;
				fixed4 result;
				float3 hitPosition;
				fixed3 dColour;

				bool hit = raymarching(rayOrigin, rayDirection, depth, _MaxDistance, _MaxIterations, hitPosition, dColour);

				if (hit)
				{
					//Do shading
					float3 n = getNormal(hitPosition);
					float3 s = Shading(hitPosition, n, dColour);
					result = fixed4(s, 1);
					result += fixed4(texCUBE(_ReflectionCube, n).rgb * _EnvironmentReflectionIntensity * _ReflectionIntensity, 0);

					//Reflection
					if (_ReflectionCount > 0)
					{
						rayDirection = normalize(reflect(rayDirection, n));
						rayOrigin = hitPosition + (rayDirection * 0.01);
						hit = raymarching(rayOrigin, rayDirection, _MaxDistance, _MaxDistance * 0.5, _MaxIterations / (uint) 2, hitPosition, dColour);
						if (hit)
						{
							float3 n = getNormal(hitPosition);
							float3 s = Shading(hitPosition, n, dColour);
							result += fixed4(s * _ReflectionIntensity, 0);
							if (_ReflectionCount > 1)
							{
								rayDirection = normalize(reflect(rayDirection, n));
								rayOrigin = hitPosition + (rayDirection * 0.01);
								hit = raymarching(rayOrigin, rayDirection, _MaxDistance, _MaxDistance * 0.25, _MaxIterations / (uint) 4, hitPosition, dColour);
								if (hit)
								{
									float3 n = getNormal(hitPosition);
									float3 s = Shading(hitPosition, n, dColour);
									result += fixed4(s * _ReflectionIntensity * 0.5, 0);
								}
							}
						}
					}
				}
				else
				{
					result = fixed4(0, 0, 0, 0);
				}

				return fixed4(col * (1.0 - result.w) + result.xyz * result.w, 1.0);
			}
			ENDCG
		}
	}
}
