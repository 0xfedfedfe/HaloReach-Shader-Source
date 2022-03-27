//#line 2 "source\rasterizer\hlsl\stencil_stipple.hlsl"

#include "hlsl_vertex_types.fx"
//@generate screen

float block_size : register(c80);
bool odd_bits : register(b1);

struct screen_output
{
	float4 HPosition	:POSITION;
};

screen_output default_vs(vertex_type IN)
{
    screen_output OUT;

    OUT.HPosition.xy= IN.position;
    OUT.HPosition.zw= 0.5f;

    return OUT;
}

float4 default_ps(float2 position : VPOS) : COLOR0
{
    // calculate which block we are in, modulo 2
    float2 block_position= floor(fmod(position / block_size, 2.0f));
    float bit;
    
    if (odd_bits)
    {		
		// odd bits are (X xor Y)
		bit= abs(block_position.x - block_position.y);
	}
	else
	{    
		// even bits are just the Y block position
		bit= block_position.y;
	}

    // clip pixel if bit is less than 0.5
    clip(bit - 0.5f);
    
    return(float4(0.f, 0.f, 0.f, 0.f));               
}