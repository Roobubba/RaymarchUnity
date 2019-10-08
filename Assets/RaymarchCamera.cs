using System.Collections.Generic;
using Unity.Mathematics;
using UnityEngine;

[RequireComponent(typeof(Camera))]
public class RaymarchCamera : SceneViewFilter
{
	[Header("RaymarchDataTesting")]
	//Simple buffer of spheres to get raymarching setup.
	[SerializeField]
	private List<float4> sphereList;

	private ComputeBuffer sphereBuffer;
	public ComputeBuffer SphereBuffer
	{
		get
		{
			if (sphereBuffer == null)
			{
				sphereBuffer = new ComputeBuffer(sphereList.Count, sizeof(float) * 4);
				sphereBuffer.SetData(sphereList);
			}
			return sphereBuffer;
		}
	}

	private void OnDestroy()
	{
		if (sphereBuffer.IsValid())
			sphereBuffer.Dispose();
	}


	[Header("Raymarching Options")]
	[SerializeField]
	private int _MaxIterations;
	[SerializeField]
	private float _MaxDistance;
	[SerializeField]
	private float _Accuracy;

	[Header("Directional Light")]
	public Transform _DirectionalLight;
	public Color _LightColour;
	public float _LightIntensity;

	[Header("Shadows")]
	[Range(0, 4)]
	public float _ShadowIntensity;
	[Range(1, 128)]
	public float _ShadowPenumbra;
	public Vector2 _ShadowDistance;

	[Header("AmbientOcclusion")]
	[Range(0,1)]
	[SerializeField]
	private float _AmbientOcclusionIntensity;
	[Range(0.01f, 10f)]
	[SerializeField]
	private float _AmbientOcclusionStepSize;
	[Range(0,5)]
	[SerializeField]
	private int _AmbientOcclusionIterations;

	[Header("Reflections")]
	[Range(0,2)]
	[SerializeField]
	private int _ReflectionCount;
	[Range(0, 1)]
	[SerializeField]
	private float _ReflectionIntensity;
	[Range(0, 1)]
	[SerializeField]
	private float _EnvironmentReflectionIntensity;
	[SerializeField]
	private Cubemap _ReflectionCube;

	[Header("Colours")]
	public Color _GroundColour;
	public Color _SphereColour = new Color(0.5f, 0.5f, 0.5f, 1f);
	[Range(0,4)]
	public float _ColourIntensity;

	[Header("Signed Distance Fields")]

	[SerializeField]
	private float _SphereSmooth;
	[SerializeField]
	private float _DegreeRotation;

	[SerializeField]
	private Shader shader;
	
	public Material RaymarchMaterial
	{
		get
		{
			if (!raymarchMaterial && shader)
			{
				raymarchMaterial = new Material(shader);
				raymarchMaterial.hideFlags = HideFlags.HideAndDontSave;
			}
			return raymarchMaterial;
		}
	}

	private Material raymarchMaterial;

	public Camera RaymarchingCamera
	{
		get
		{
			if (!raymarchingCamera)
			{
				raymarchingCamera = GetComponent<Camera>();
			}

			return raymarchingCamera;
		}
	}
	private Camera raymarchingCamera;

	private void OnRenderImage(RenderTexture source, RenderTexture destination)
	{
		if (!RaymarchMaterial)
		{
			Graphics.Blit(source, destination);
			return;
		}

		//Then we are testing out the new raymarching data input Texture3D so need to set up the shader details differently:
		//Camera Setup
		RaymarchMaterial.SetMatrix("_CamFrustum", CamFrustum(RaymarchingCamera));
		RaymarchMaterial.SetMatrix("_CamToWorld", RaymarchingCamera.cameraToWorldMatrix);

		//Raymarching setup
		RaymarchMaterial.SetInt("_MaxIterations", _MaxIterations);
		RaymarchMaterial.SetFloat("_MaxDistance", _MaxDistance);
		RaymarchMaterial.SetFloat("_Accuracy", _Accuracy);

		//Light
		RaymarchMaterial.SetVector("_LightDirection", _DirectionalLight ? _DirectionalLight.forward : Vector3.down);
		RaymarchMaterial.SetColor("_LightColour", _LightColour);
		RaymarchMaterial.SetFloat("_LightIntensity", _LightIntensity);

		//Shadow
		RaymarchMaterial.SetFloat("_ShadowIntensity", _ShadowIntensity);
		RaymarchMaterial.SetVector("_ShadowDistance", _ShadowDistance);
		RaymarchMaterial.SetFloat("_ShadowPenumbra", _ShadowPenumbra);

		//AO
		RaymarchMaterial.SetFloat("_AmbientOcclusionIntensity", _AmbientOcclusionIntensity);
		RaymarchMaterial.SetFloat("_AmbientOcclusionStepSize", _AmbientOcclusionStepSize);
		RaymarchMaterial.SetInt("_AmbientOcclusionIterations", _AmbientOcclusionIterations);

		//Reflections
		RaymarchMaterial.SetFloat("_ReflectionIntensity", _ReflectionIntensity);
		RaymarchMaterial.SetFloat("_EnvironmentReflectionIntensity", _EnvironmentReflectionIntensity);
		RaymarchMaterial.SetInt("_ReflectionCount", _ReflectionCount);
		RaymarchMaterial.SetTexture("_ReflectionCube", _ReflectionCube);

		//Refactoring Scene Colour
		RaymarchMaterial.SetColor("_GroundColour", _GroundColour);
		RaymarchMaterial.SetFloat("_ColourIntensity", _ColourIntensity);
		RaymarchMaterial.SetColor("_TestColour", _SphereColour);

		//SDF
		RaymarchMaterial.SetFloat("_SphereSmooth", _SphereSmooth);

		RaymarchMaterial.SetBuffer("_SphereBuffer", SphereBuffer);
		RaymarchMaterial.SetInt("_SphereBufferLength", SphereBuffer.count);

		RenderTexture.active = destination;
		RaymarchMaterial.SetTexture("_MainTex", source);
		GL.PushMatrix();
		GL.LoadOrtho();
		RaymarchMaterial.SetPass(0);
		GL.Begin(GL.QUADS);

		//bottomLeft
		GL.MultiTexCoord2(0, 0.0f, 0.0f);
		GL.Vertex3(0.0f, 0.0f, 3.0f);
		//bottomRight
		GL.MultiTexCoord2(0, 1.0f, 0.0f);
		GL.Vertex3(1.0f, 0.0f, 2.0f);
		//topRight
		GL.MultiTexCoord2(0, 1.0f, 1.0f);
		GL.Vertex3(1.0f, 1.0f, 1.0f);
		//topLeft
		GL.MultiTexCoord2(0, 0.0f, 1.0f);
		GL.Vertex3(0.0f, 1.0f, 0.0f);

		GL.End();
		GL.PopMatrix();
	}

	private Matrix4x4 CamFrustum(Camera cam)
	{
		Matrix4x4 frustum = Matrix4x4.identity;
		float fov = Mathf.Tan((cam.fieldOfView * 0.5f) * Mathf.Deg2Rad);

		Vector3 goUp = Vector3.up * fov;
		Vector3 goRight = Vector3.right * fov * cam.aspect;

		Vector3 topLeft = (-Vector3.forward - goRight + goUp);
		Vector3 topRight = (-Vector3.forward + goRight + goUp);
		Vector3 bottomRight = (-Vector3.forward + goRight - goUp);
		Vector3 bottomLeft = (-Vector3.forward - goRight - goUp);

		frustum.SetRow(0, topLeft);
		frustum.SetRow(1, topRight);
		frustum.SetRow(2, bottomRight);
		frustum.SetRow(3, bottomLeft);

		return frustum;
	}

}
