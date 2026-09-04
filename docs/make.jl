using Documenter
using InitialConditions

makedocs(
    modules = [InitialConditions, InitialConditions.ERA5],
    # The shared helpers at the top level are internal, so they are
    # deliberately absent from the manual
    warnonly = [:missing_docs],
    authors = "Climate Modelling Alliance",
    sitename = "InitialConditions.jl",
    format = Documenter.HTML(),
    pages = ["Home" => "index.md"],
)

deploydocs(
    repo = "github.com/CliMA/InitialConditions.jl.git",
    devbranch = "main",
    push_preview = true,
    forcepush = true,
)
