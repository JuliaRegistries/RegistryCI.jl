using RegistryCI
using Documenter

DocMeta.setdocmeta!(RegistryCI, :DocTestSetup, :(using RegistryCI); recursive=true)

makedocs(;
    modules=[RegistryCI],
    authors="Dilum Aluthge <dilum@aluthge.com>, Fredrik Ekre <ekrefredrik@gmail.com>, contributors",
    repo="https://github.com/JuliaRegistries/RegistryCI.jl/blob/{commit}{path}#{line}",
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
    strict=true,
)

deploydocs(;
    repo="github.com/JuliaRegistries/RegistryCI.jl",
    push_preview=true, # TODO: turn this back to false
)
