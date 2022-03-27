#include "shared\utilities.fx"

#define ENVMAP_TYPE(env_map_type) ENVMAP_TYPE_##env_map_type
#define ENVMAP_TYPE_none 0
#define ENVMAP_TYPE_per_pixel 1
#define ENVMAP_TYPE_dynamic 2
#define ENVMAP_TYPE_from_flat_texture 3

#define CALC_ENVMAP(env_map_type) calc_environment_map_##env_map_type##_ps

float3 env_tint_color;
//float3 env_glancing_tint_color;
float env_bias;								// ###ctchou $TODO replace this - use roughness instead

float3 env_topcoat_color;
float env_topcoat_bias;
//float env_roughness_scale;
float env_roughness_offset;

float offset_env_reflection_lod(float base_roughness)
{
    return (base_roughness+(env_roughness_offset-0.5)*2)*4;
}

#if ENVMAP_TYPE(envmap_type) == ENVMAP_TYPE_none
float3 calc_environment_map_none_ps(
	in float3 view_dir,
	in float3 normal,
	in float3 reflect_dir,
	in float4 specular_reflectance_and_roughness,
	in float3 low_frequency_specular_color,
	in bool imposter_capturing_in_progresss)
{
	return float3(0.0f, 0.0f, 0.0f);
}
#endif // ENVMAP_TYPE_none

#if ENVMAP_TYPE(envmap_type) == ENVMAP_TYPE_per_pixel
samplerCUBE environment_map : register(s1);		// test
float3 calc_environment_map_per_pixel_ps(
	in float3 view_dir,
	in float3 normal,
	in float3 reflect_dir,
	in float4 specular_reflectance_and_roughness,
	in float3 low_frequency_specular_color,
	in bool imposter_capturing_in_progresss)
{
	reflect_dir.y= -reflect_dir.y;
	
	float4 reflection;
#ifdef pc	
	reflection= texCUBE(environment_map, reflect_dir);
#else
	float base_lod= 0.0f;
	float lod= max(base_lod, offset_env_reflection_lod(0));	

	if (imposter_capturing_in_progresss)
	{
		lod+= 7;
	}

	reflection= texCUBElod(environment_map, float4(reflect_dir, lod));

#endif
	return reflection.rgb * specular_reflectance_and_roughness.xyz * low_frequency_specular_color * env_tint_color * reflection.a;
}
#endif // ENVMAP_TYPE_per_pixel

#if ENVMAP_TYPE(envmap_type) == ENVMAP_TYPE_per_pixel_mip
samplerCUBE environment_map : register(s1);		// test
float3 calc_environment_map_per_pixel_mip_ps(
	in float3 view_dir,
	in float3 normal,
	in float3 reflect_dir,
	in float4 specular_reflectance_and_roughness,
	in float3 low_frequency_specular_color,
	in bool imposter_capturing_in_progresss)
{
	reflect_dir.y= -reflect_dir.y;
	float4 reflection;
	reflection= texCUBE(environment_map, reflect_dir);


	// special code for imposter capturing
	if (imposter_capturing_in_progresss)
	{
		reflection= texCUBElod(environment_map, float4(reflect_dir, 7));
	}


	return reflection.rgb * specular_reflectance_and_roughness.xyz * low_frequency_specular_color * env_tint_color * reflection.a;
}
#endif // ENVMAP_TYPE_per_pixel_mip

#if ENVMAP_TYPE(envmap_type) == ENVMAP_TYPE_dynamic

float3 calc_environment_map_dynamic_ps(
	in float3 view_dir,
	in float3 normal,
	in float3 reflect_dir,
	in float4 specular_reflectance_and_roughness,
	in float3 low_frequency_specular_color,
	in bool imposter_capturing_in_progresss)
{
	reflect_dir.y= -reflect_dir.y;
	
	float4 reflection_0, reflection_1;
	
#ifdef pc
	float grad_x= length(ddx(reflect_dir));
	float grad_y= length(ddy(reflect_dir));
	float base_lod= 6.0f * sqrt(max(grad_x, grad_y)) - 0.6f;
	float lod= max(base_lod, offset_env_reflection_lod(specular_reflectance_and_roughness.w ));
	
	reflection_0= 0; 
	reflection_1= 0; 
	
	float3 reflection=  (reflection_0.rgb*reflection_0.rgb * reflection_0.a * 64.0f);
	
#else	// xenon
	float grad_x= 0.0f;
	float grad_y= 0.0f;
	float base_lod= 0.0f;

	float lod= max(base_lod, offset_env_reflection_lod(specular_reflectance_and_roughness.w));

	reflection_0= texCUBElod(dynamic_environment_map_0, float4(reflect_dir, lod + dynamic_environment_blend.x));
	
#ifdef must_be_environment
	float3 reflection=  (reflection_0.rgb*reflection_0.rgb * reflection_0.a);
#else // !environment
    reflection_1= texCUBElod(dynamic_environment_map_1, float4(reflect_dir, lod + dynamic_environment_blend.y));
	float3 reflection=  (reflection_0.rgb*reflection_0.rgb * reflection_0.a) * dynamic_environment_blend.w + 
						(reflection_1.rgb*reflection_1.rgb * reflection_1.a) * (1.0f-dynamic_environment_blend.w);
#endif // !environment
#endif

	// assume the average intensity of dynamic cubemap is 1
	if (imposter_capturing_in_progresss)
	{
		reflection= 1.0f;
	}

	return reflection * specular_reflectance_and_roughness.xyz * env_tint_color * low_frequency_specular_color;
	
//	return float3(lod, lod, lod) / 6.0f;
}
#endif // ENVMAP_TYPE_dynamic

#if ENVMAP_TYPE(envmap_type) == ENVMAP_TYPE_from_flat_texture

sampler2D flat_environment_map;
float4 flat_envmap_matrix_x;		// envmap rotation matrix, dot xyz with world direction returns envmap.X					w component ignored
float4 flat_envmap_matrix_y;		// envmap rotation matrix, dot xyz with world direction returns envmap.Y					w component ignored
float4 flat_envmap_matrix_z;		// envmap rotation matrix, dot xyz with world direction returns envmap.Z (-1 = forward)		w component ignored
float hemisphere_percentage;

// ###ctchou $HACK $E3 bloom override
float4 env_bloom_override;		// input		[R, G, B tint, alpha = percentage]
float env_bloom_override_intensity;		// input
float3 env_bloom_override_output;				// output
#define BLOOM_OVERRIDE env_bloom_override_output


float3 calc_environment_map_from_flat_texture_ps(
	in float3 view_dir,
	in float3 normal,
	in float3 reflect_dir,								// normalized
	in float4 specular_reflectance_and_roughness,
	in float3 low_frequency_specular_color,
	in bool imposter_capturing_in_progresss)
{
	float3 reflection= float3(1.0f, 0.0f, 0.0f);

	// fisheye projection	
	float3 envmap_dir;
	envmap_dir.x= dot(reflect_dir, flat_envmap_matrix_x.xyz);
	envmap_dir.y= dot(reflect_dir, flat_envmap_matrix_y.xyz);
	envmap_dir.z= dot(reflect_dir, flat_envmap_matrix_z.xyz);
	
	float radius= sqrt((envmap_dir.z+1.0f)/hemisphere_percentage);							// 1.0 = radius of texture (along X/Y axis)
																							// ###ctchou $PERF we could put the (+1.0f)/hemisphere percentage into the dot product with Z by modifying flat_envmap_matrix_z - but would require combining shader parameters
	
	float2 texcoord= envmap_dir.xy * radius / sqrt(dot(envmap_dir.xy, envmap_dir.xy));		// normalize x/y vector, and scale by radius to get fisheye projection
	texcoord= (1.0f+texcoord)*0.5f;															// convert to texture coordinate space (0..1)

	reflection= tex2D(flat_environment_map, texcoord);
	
	// ###ctchou $HACK $E3 bloom override
#ifndef pc
	BLOOM_OVERRIDE= max(color_to_intensity(reflection.rgb)-env_bloom_override.a, 0.0f) * env_bloom_override.rgb * env_bloom_override_intensity * g_exposure.rrr;
#endif
	
/*	// perspective projection
	float3 texcoord;
	texcoord.z= dot(reflect_dir, flat_envmap_matrix_w.xyz);					// ###ctchou $TODO $PERF pass the transformed point from the vertex shader
	if (texcoord.z < -0.001f)
	{
		texcoord.x= dot(reflect_dir, flat_envmap_matrix_x.xyz);
		texcoord.y= dot(reflect_dir, flat_envmap_matrix_y.xyz);
		reflection= tex2D(flat_environment_map, texcoord.xy / texcoord.z);
	}
*/
	return reflection * specular_reflectance_and_roughness.xyz * env_tint_color;
}

#endif // ENVMAP_TYPE_from_flat_texture
