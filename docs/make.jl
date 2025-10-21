using RegistryCI
using AutoMerge
using Documenter

makedocs(;
    modules=[RegistryCI, AutoMerge],
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
        "Configuration" => "configuration.md",
        "Using RegistryCI on your own package registry" => "private-registries.md",
        "Public API" => "public.md",
        "Regexes" => "regexes.md",
        "Internals (Private)" => "internals.md",
        "Migration Guide (AutoMerge v1)" => "migration-v1.md",
    ],
)

deploydocs(; repo="github.com/JuliaRegistries/RegistryCI.jl", push_preview=false)
