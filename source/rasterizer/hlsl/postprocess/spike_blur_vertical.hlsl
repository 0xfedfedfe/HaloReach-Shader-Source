//#line 2 "source\rasterizer\hlsl\spike_blur_vertical.hlsl"

#define USE_CUSTOM_POSTPROCESS_CONSTANTS

#include "hlsl_vertex_types.fx"
#include "shared\utilities.fx"
#include "postprocess\postprocess.fx"
//@generate screen

sampler2D source_sampler : register(s0);

PIXEL_CONSTANT(float2, source_pixel_size,	POSTPROCESS_PIXELSIZE_PIXEL_CONSTANT);		// texcoord size of a single pixel (1 / (width-1), 1/(height-1))
PIXEL_CONSTANT(float4, offset_delta,		POSTPROCESS_DEFAULT_PIXEL_CONSTANT);		// float offset_x, float offset_y (should be a multiple of source_pixel_size.y), float delta_x
PIXEL_CONSTANT(float3, initial_color,		POSTPROCESS_EXTRA_PIXEL_CONSTANT_0);		// initial RGB scales (at offset_x,offset_y)
PIXEL_CONSTANT(float3, delta_color,			POSTPROCESS_EXTRA_PIXEL_CONSTANT_1);		// scale for RGB per sample (multiplies previous color at each delta_x offset)
PIXEL_CONSTANT(float2, texture_size,		POSTPROCESS_EXTRA_PIXEL_CONSTANT_2);		// size of the texture, in pixels

float3 get_pixel_linear_x(float2 tex_coord)		// linear in X, point in Y
{
	tex_coord.x= (tex_coord.x / source_pixel_size.x) - 0.5;
	float2 texel0= float2(floor(tex_coord.x), tex_coord.y);

	float4 blend;
	blend.xy= tex_coord - texel0;
	blend.zw= 1.0 - blend.xy;

	texel0.x= (texel0.x + 0.5)* source_pixel_size.x;

	float2 texel1= texel0;
	texel1.x += source_pixel_size.x;

	float3 color=	blend.z * convert_from_bloom_buffer(tex2D(source_sampler, texel0))+
					blend.x * convert_from_bloom_buffer(tex2D(source_sampler, texel1));

	return color;
}

float4 default_ps(screen_output IN) : COLOR
{
	float2 sample0= IN.texcoord + offset_delta.xy;

	float3 color_scale= initial_color;

	float3 color= color_scale * get_pixel_linear_x(sample0);
	
	for (int y= 1; y < 8; y++)
	{
		color_scale *= delta_color;
		sample0.xy += offset_delta.zw;
		color += color_scale * get_pixel_linear_x(sample0);
	}

	return convert_to_bloom_buffer(color);
}
