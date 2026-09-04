import SafeTestsets: @safetestset

@safetestset "Unit tests" begin
    include("unit_tests.jl")
end

# Skips itself unless ERA5_NETWORK_TESTS=true, because it needs CDS
# credentials and a CDS request can queue for hours
@safetestset "Network tests" begin
    include("network_tests.jl")
end
