# The ERA5 soil discretization, with the values from WeatherQuest
# `interpolate.jl`

# WeatherQuest `interpolate.jl`
# ============================================================================

"""
ERA5 soil layer midpoint depths [m].
"""
const SOIL_LAYER_MIDPOINTS = [0.035, 0.175, 0.64, 1.945]

"""
ERA5 soil layer top depths [m].
"""
const SOIL_LAYER_TOPS = [0.0, 0.07, 0.28, 1.00]

"""
ERA5 soil layer bottom depths [m].
"""
const SOIL_LAYER_BOTTOMS = [0.07, 0.28, 1.00, 2.89]

"""
The `z` coordinate of the 3D soil files: negative depths in increasing order,
so index 1 is the deepest layer.
"""
const SOIL_Z = -reverse(SOIL_LAYER_MIDPOINTS)

"""
Reverse the layer dimension of a `(lon, lat, layer)` array to match the
`SOIL_Z` order, which puts the deepest layer first.
"""
soil_layers_to_z(field) = reverse(field; dims = 3)

const SOIL_Z_ATTRIB = Dict(
    "standard_name" => "depth",
    "long_name" => "Soil depth (negative below surface)",
    "units" => "m",
    "axis" => "Z",
)
