

//
// WATERFALL
//

sampler		waterfall_base_mask;
float4		waterfall_base_mask_xform;
sampler		waterfall_layer0;
float4		waterfall_layer0_xform;
sampler		waterfall_layer1;
float4		waterfall_layer1_xform;
sampler		waterfall_layer2;
float4		waterfall_layer2_xform;

float		transparency_frothy_weight;
float		transparency_base_weight;
float		transparency_bias;

void calc_albedo_waterfall_ps(
	in float2 texcoord,
	out float4 albedo,
	in float3 normal)
{
	float4 base_mask=		tex2D(waterfall_base_mask,	transform_texcoord(texcoord,	waterfall_base_mask_xform));
	float4 layer0=			tex2D(waterfall_layer0,		transform_texcoord(texcoord,	waterfall_layer0_xform));
	float4 layer1=			tex2D(waterfall_layer1,		transform_texcoord(texcoord,	waterfall_layer1_xform));
	float4 layer2=			tex2D(waterfall_layer2,		transform_texcoord(texcoord,	waterfall_layer2_xform));

/*
	float4 layer01=			lerp(layer0, layer1, layer1.w);														// alpha blend layer 1 on top of layer 0
	float4 layer012=		lerp(layer01, layer2, layer2.w);													// alpha blend layer 2 on top of that
	albedo.rgb=				layer012.rgb * base_mask.rgb;														// multiply base color on top
	albedo.w=				base_mask.w * clamp(layer01.a - 0.3f);																		// transparency comes only from base mask
*/

	float4 frothy_color=		(layer0 * layer1 * layer2);
	float frothy_transparency=	layer1.a + layer0.a + layer2.a;

	albedo.rgb=		frothy_color * base_mask.rgb;
	albedo.a=		clamp(transparency_frothy_weight*frothy_transparency + transparency_base_weight*base_mask.a + transparency_bias, 0.0f, 1.0f);
	
	apply_pc_albedo_modifier(albedo, normal);
}


//

