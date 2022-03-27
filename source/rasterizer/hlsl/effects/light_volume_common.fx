// These are the constants which we don't want to overwrite.  They need to 
// be declared here, whether or not we use them, so that the shader compiler 
// will not auto-assign things to them.

#ifndef pc

#include "effects\function.fx"	// For evaluating Guerilla functions

#define _register_group_properties		3
#define _register_group_memexport		4

// Match with c_light_volume_gpu anonymous enum
#define k_profiles_per_row	16 
#define k_row_count			128 
static int2 g_buffer_dims= int2(k_profiles_per_row, k_row_count);

extern float4 g_hidden_from_compiler;

// Match with the fields of c_light_volume_gpu::s_layout.
struct s_profile_state
{
	float3	m_position;
	float	m_percentile;
	float4	m_color;
	float	m_thickness;
	float	m_intensity;
};

#ifdef READ_DISABLE_FOR_DEBUGGING
// Choose something which won't cause the profile lifetime to be up...
extern float4 unknown_value : register(k_register_camera_forward);
#endif

s_profile_state read_profile_state(int index)
{
	s_profile_state STATE;
	
#ifndef READ_DISABLE_FOR_DEBUGGING
	// Match with c_light_volume_gpu::e_state, and with c_light_volume_gpu::queue_profile().
	// Note that because of format specifications, state fields must be carefully assigned 
	// to an appropriate sample.
	float4 pos_sample;
	float4 misc_sample_2x16f;
	float4 col_sample;

	asm {
		vfetch pos_sample, index.x, position
		vfetch misc_sample_2x16f, index.x, texcoord0
		vfetch col_sample, index.x, color
	};
#else
	float4 pos_sample= unknown_value;
	float4 misc_sample_2x16f= unknown_value;
	float4 col_sample= unknown_value;
#endif

	// This code basically compiles away, since it's absorbed into the
	// compiler's register mapping.
	STATE.m_position= pos_sample.xyz;			// s_gpu_storage_4x32f
	STATE.m_percentile= pos_sample.w;
	STATE.m_thickness= misc_sample_2x16f.x;			// s_gpu_storage_4x16f
	STATE.m_intensity= misc_sample_2x16f.y;
	STATE.m_color= col_sample;					// s_gpu_storage_argb8
	
	return STATE;
}

#ifdef MEMEXPORT_ENABLED

// Match with c_light_volume_gpu::e_state.
#define _state_pos			0
#define _state_misc_2x16f	1
#define _state_col			2
#define _state_max			3

// Match with s_memexport in s_gpu_layout<t_num_states>::set_memexport()
struct s_memexport
{
	float4 m_stream_constant;
	float2 m_stride_offset;
};

BEGIN_REGISTER_GROUP(memexport)
extern s_memexport g_all_memexport[_state_max];
END_REGISTER_GROUP(memexport)

// The including function must define the stride_offset and stream_constant registers.
void write_profile_state(s_profile_state STATE, int index)
{
	static float4 stream_helper= {0, 1, 0, 0};
	float4 export[_state_max];

	// This code basically compiles away, since it's absorbed into the
	// compiler's register mapping.
	export[_state_pos]= float4(STATE.m_position, STATE.m_percentile);
	export[_state_misc_2x16f]= float4(STATE.m_thickness, STATE.m_intensity, 0.0f, 0.0f);
	export[_state_col]= float4(STATE.m_color);
#ifndef WRITE_DISABLE_FOR_PROFILING
    // Store result.  Some of these writes are not needed by all clients
    // (eg. rnd should only be written by spawn, not update).
    for (int state= 0; state< _state_max; ++state)
    {
		int state_index= index * g_all_memexport[state].m_stride_offset.x + g_all_memexport[state].m_stride_offset.y;
		float4 stream_constant= g_all_memexport[state].m_stream_constant;
		float4 export= export[state];
		asm {
		alloc export=1
			mad eA, state_index, stream_helper, stream_constant
			mov eM0, export
		};
    }
    // This is a workaround for a bug in >=Profile builds.  Without it, we get occasional 
    // bogus memexports from nowhere during effect-heavy scenes.
	asm {
	alloc export=1
		mad eA.xyzw, g_hidden_from_compiler.y, g_hidden_from_compiler.yyyy, g_hidden_from_compiler.yyyy
	};
	asm {
	alloc export=1
		mad eA.xyzw, g_hidden_from_compiler.z, g_hidden_from_compiler.zzzz, g_hidden_from_compiler.zzzz
	};
#else	// do only enough writing to keep from culling any ALU calculations
	float4 all_export= float4(0,0,0,0);
    for (int state= 0; state< _state_max; ++state)
    {
		all_export+= export[state];
    }
	int state_index= index * g_all_memexport[0].m_stride_offset.x + g_all_memexport[0].m_stride_offset.y;
	float4 stream_constant= g_all_memexport[0].m_stream_constant;
	asm {
	alloc export=1
		mad eA, state_index, stream_helper, stream_constant
		mov eM0, all_export
	};
#endif
}

#endif	//#ifdef MEMEXPORT_ENABLED

// Match with c_light_volume_definition::e_appearance_flags

// Match with c_light_volume_state::e_input
#define _profile_percentile			0	//_profile_percentile
#define _game_time					1	//_game_time
#define _system_age					2	//_system_age 
#define _light_volume_random		3	//_light_volume_random 
#define _light_volume_correlation_1	4	//_light_volume_correlation_1
#define _light_volume_correlation_2	5	//_light_volume_correlation_2
#define _system_lod					6	//_system_lod 
#define _effect_a_scale				7	//_effect_a_scale
#define _effect_b_scale				8	//_effect_b_scale
#define _invalid					9	//_invalid
#define _state_total_count			10	//k_total_count
		
// Match with s_overall_state in c_light_volume_gpu::set_shader_state()
struct s_gpu_single_state
{
	float m_value;
};
struct s_overall_state
{
	float m_appearance_flags;
	float m_brightness_ratio;
	float m_offset;
	float m_num_profiles;
	float m_profile_distance;
	float m_profile_length;
	float3 m_origin;
	float3 m_direction;
	s_gpu_single_state m_inputs[_state_total_count];
};

extern s_overall_state g_all_state;

// Match with c_editable_property_base::e_output_modifier
#define _modifier_none			0	//_output_modifier_none
#define _modifier_add			1	//_output_modifier_add
#define _modifier_multiply		2	//_output_modifier_multiply

float get_state_value(const s_profile_state profile_state, int index)
{
	if (index== _profile_percentile)
	{
		return profile_state.m_percentile;
	}
	else	// a state which is independent of profile
	{
		return g_all_state.m_inputs[index].m_value;
	}
}

// Match with s_gpu_property.  
// The s_property struct is implemented internally with bitfields to save constant space.
// The EXTRACT_BITS macro should take 2-5 assembly instructions depending on whether the bits
// lie at the beginning/middle/end of the allowed range.
struct s_property 
{
	float4 m_innards;
};
float get_constant_value(s_property p)		{ return p.m_innards.x; }
int get_is_constant(s_property p)			{ return EXTRACT_BITS(p.m_innards.y, 21, 22); }	// 1 bit always
int get_function_index_green(s_property p)	{ return EXTRACT_BITS(p.m_innards.z, 17, 22); }	// 5 bits often	
int get_input_index_green(s_property p)		{ return EXTRACT_BITS(p.m_innards.w, 17, 22); }	// 5 bits often	
int get_function_index_red(s_property p)	{ return EXTRACT_BITS(p.m_innards.y, 0, 5); }	// 5 bits often	
int get_input_index_red(s_property p)		{ return EXTRACT_BITS(p.m_innards.y, 5, 10); }	// 5 bits rarely	
int get_color_index_lo(s_property p)		{ return EXTRACT_BITS(p.m_innards.w, 0, 3); }	// 3 bits rarely	
int get_color_index_hi(s_property p)		{ return EXTRACT_BITS(p.m_innards.w, 3, 6); }	// 3 bits rarely	
int get_modifier_index(s_property p)		{ return EXTRACT_BITS(p.m_innards.z, 0, 2); }	// 2 bits often	
int get_input_index_modifier(s_property p)	{ return EXTRACT_BITS(p.m_innards.z, 2, 7); }	// 5 bits rarely	

// Match with e_property in c_light_volume_gpu::set_shader_functions().
#define _index_profile_thickness			0
#define _index_profile_color				1
#define _index_profile_alpha				2
#define _index_profile_intensity			3
#define _index_max							4

BEGIN_REGISTER_GROUP(properties)
extern s_property g_all_properties[_index_max];
END_REGISTER_GROUP(properties)

// This generates multiple inlined calls to evaluate and get_state_value, which are 
// large functions.  If the inlining becomes an issue, we can use the loop 
// trick documented below.
float profile_evaluate(const s_profile_state profile_state, int type)
{
	s_property property= g_all_properties[type];
	if (get_is_constant(property))
	{
		return get_constant_value(property);
	}
	else
	{
		float input= get_state_value(profile_state, get_input_index_green(property));
		float output;
		if (get_function_index_red(property)!= _type_identity)	// hack for ranged, since 0 isn't used
		{
			float interpolate= get_state_value(profile_state, get_input_index_red(property));
			output= evaluate_scalar_ranged(get_function_index_green(property), get_function_index_red(property), input, 
				interpolate);
		}
		else
		{
			output= evaluate_scalar(get_function_index_green(property), input);
		}
		if (get_modifier_index(property)!= _modifier_none)
		{
			float modify_by= get_state_value(profile_state, get_input_index_modifier(property));
			if (get_modifier_index(property)== _modifier_add)
			{
				output+= modify_by;
			}
			else // if (get_modifier_index(property)== _modifier_multiply)
			{
				output*= modify_by;
			}
		}
		return output;
	}
}

float3 light_volume_map_to_color_range(int type, float scalar)
{
	s_property property= g_all_properties[type];
	return map_to_color_range(get_color_index_lo(property), get_color_index_hi(property), scalar);
}

float2 light_volume_map_to_point2d_range(int type, float scalar)
{
	s_property property= g_all_properties[type];
	return map_to_point2d_range(get_color_index_lo(property), get_color_index_hi(property), scalar);
}

float2 light_volume_map_to_vector2d_range(int type, float scalar)
{
	s_property property= g_all_properties[type];
	return map_to_vector2d_range(get_color_index_lo(property), get_color_index_hi(property), scalar);
}

float3 light_volume_map_to_vector3d_range(int type, float scalar)
{
	s_property property= g_all_properties[type];
	return map_to_vector3d_range(get_color_index_lo(property), get_color_index_hi(property), scalar);
}

typedef float preevaluated_functions[_index_max];
preevaluated_functions preevaluate_light_volume_functions(s_profile_state STATE)
{
	// The explicit initializations below are necessary to avoid uninitialized
	// variable errors.  I believe the excess initializations are stripped out.
	float pre_evaluated_scalar[_index_max]= {0, 0, 0, 0, };
	[loop]
	for (int loop_counter= 0; loop_counter< _index_max; ++loop_counter)
	{
		pre_evaluated_scalar[loop_counter]= profile_evaluate(STATE, loop_counter);
	}

	return pre_evaluated_scalar;
}

// Match with s_strip in c_light_volume_gpu::set_shader_strip()
#define k_max_rows_per_strip	8 
struct s_strip
{
	float m_total_profile_count;
	float m_row[k_max_rows_per_strip];
};

extern s_strip g_strip;

// Take the index from the vertex input semantic and translate it into the actual lookup 
// index in the vertex buffer.
int profile_index_to_buffer_index( int profile_index )
{
	// ###ctchou $TODO FUCKED BY NEW XDK COMPILER -- TURNING OFF OPTIMIZATIONS
	[noExpressionOptimizations]

	int light_volume_row= round(profile_index / k_profiles_per_row);
	int profile_index_within_row= round(profile_index % k_profiles_per_row);
	int buffer_row= g_strip.m_row[light_volume_row];
	
	return buffer_row * k_profiles_per_row + profile_index_within_row;
}

#endif	// #ifndef pc