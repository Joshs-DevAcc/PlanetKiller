shader_type spatial;
// Terrain look. The mesh gives each vertex:
//   COLOR   = the rock/soil color around it (already blended smoothly)
//   CUSTOM0 = ore color * ore amount (rgb) and ore amount (a)
// Here we add world-space noise for surface detail and draw ore as
// shiny flecks embedded in the rock instead of a flat smear of color.

render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float detail_strength : hint_range(0.0, 1.0) = 0.35;
uniform float fleck_scale = 10.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec4 ore;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
	               mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
	               mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	ore = CUSTOM0;
}

void fragment() {
	vec3 base = COLOR.rgb;
	// Large soft patches plus fine grain.
	float broad = fbm(world_pos * 0.35);
	float grain = noise(world_pos * 6.0);
	float detail = mix(1.0, (0.75 + 0.5 * broad) * (0.9 + 0.2 * grain), detail_strength * 2.0);
	vec3 col = base * detail;

	// Darken crevices a little using the normal (fake ambient occlusion for overhangs).
	col *= mix(0.78, 1.0, clamp(world_normal.y * 0.5 + 0.5, 0.0, 1.0));

	float rough = 0.9;
	float metal = 0.0;
	vec3 glow = vec3(0.0);

	float amount = ore.a;
	if (amount > 0.01) {
		vec3 ore_col = ore.rgb / amount;
		// Flecks: blobs of noise that get denser where there is more ore.
		float n = noise(world_pos * fleck_scale) * 0.65 + noise(world_pos * fleck_scale * 2.7) * 0.35;
		float edge = 0.74 - amount * 0.2;
		float fleck = smoothstep(edge, edge + 0.03, n);
		float sparkle = pow(noise(world_pos * 22.0), 10.0) * 8.0;
		// Darker rim around each fleck so it reads as embedded in the rock.
		float rim = smoothstep(edge - 0.06, edge, n) * (1.0 - fleck);
		col *= 1.0 - rim * 0.35;
		col = mix(col, ore_col * (0.6 + 0.3 * grain), fleck);
		rough = mix(rough, 0.3, fleck);
		metal = mix(metal, 0.3, fleck);
		glow = ore_col * fleck * sparkle * 0.15;
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = glow;
}
