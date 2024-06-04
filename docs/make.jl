using RegistryCI
using Documenter

DocMeta.setdocmeta!(RegistryCI, :DocTestSetup, :(using RegistryCI); recursive=true)

makedocs(;
    modules=[RegistryCI],
    authors="Dilum Aluthge <dilum@aluthge.com>, Fredrik Ekre <ekrefredrik@gmail.com>, contributors",
    repo=Remotes.GitHub("JuliaRegistries", "RegistryCI.jl"),
    sitename="RegistryCI.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://JuliaRegistries.github.io/RegistryCI.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Automatic merging guidelines" => "guidelines.md",
        "Regexes" => "regexes.md",
        "Using RegistryCI on your own package registry" => "private-registries.md",
        "Public API" => "public.md",
        "Internals (Private)" => "internals.md",
    ],
)

deploydocs(; repo="github.com/JuliaRegistries/RegistryCI.jl", push_preview=false)
