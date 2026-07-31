import SafeTestsets: @safetestset

@safetestset "Unit tests" begin
    include("unit_tests.jl")
end
