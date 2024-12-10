using Documenter, Literate, AbstractImageReconstruction

# Generate examples
OUTPUT_BASE = joinpath(@__DIR__(), "src/generated")
INPUT_BASE = joinpath(@__DIR__(), "src/literate")
for (_, dirs, _) in walkdir(INPUT_BASE)
    for dir in dirs
        OUTPUT = joinpath(OUTPUT_BASE, dir)
        INPUT = joinpath(INPUT_BASE, dir)
        for file in filter(f -> endswith(f, ".jl"), readdir(INPUT))
            Literate.markdown(joinpath(INPUT, file), OUTPUT)
        end
    end
end

makedocs(
    format = Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://github.com/JuliaImageRecon/AbstractImageReconstruction.jl",
        assets=String[],
        collapselevel=1,
    ),
    repo="https://github.com/JuliaImageRecon/AbstractImageReconstruction.jl/blob/{commit}{path}#{line}",
    modules = [AbstractImageReconstruction],
    sitename = "AbstractImageReconstruction.jl",
    authors = "Niklas Hackelberg, Tobias Knopp",
    pages = [
        "Home" => "index.md",
        "Example: Radon Reconstruction Package" => Any[
            "Introduction" => "example_intro.md",
            "Radon Data" => "generated/example/0_radon_data.md",
            "Interface" => "generated/example/1_interface.md",
            "Direct Reconstruction" => "generated/example/2_direct.md",
            "Direct Reconstruction Result" => "generated/example/3_direct_result.md",
            "Iterative Reconstruction" => "generated/example/4_iterative.md",
            "Iterative Reconstruction Result" => "generated/example/5_iterative_result.md",
        ],
        "How to" => Any[
            "Serialization" => "generated/howto/serialization.md",
            "Caching" => "generated/howto/caching.md",
            "Observables" => "generated/howto/observables.md",
        ],
        #"API Reference" => Any["Solvers" => "API/solvers.md",
        #"Regularization Terms" => "API/regularization.md"],

    ],
    pagesonly = true,
    checkdocs = :none,
    doctest   = false,
    doctestfilters = [r"(\d*)\.(\d{4})\d+"]
    )

deploydocs(repo   = "github.com/JuliaImageRecon/AbstractImageReconstruction.jl.git", push_preview = true)