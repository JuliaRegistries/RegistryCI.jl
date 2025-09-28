module AutoMerge

using Dates: Dates
# import GitCommand
using GitHub: GitHub
using HTTP: HTTP
using LibGit2: LibGit2
using Pkg: Pkg
using TimeZones: TimeZones
using JSON: JSON
using VisualStringDistances: VisualStringDistances
using StringDistances: StringDistances
using LicenseCheck: LicenseCheck
using TOML: TOML
using Printf: Printf
using RegistryTools: RegistryTools
using Tar: Tar
using RegistryCI: RegistryCI

if VERSION >= v"1.11.0-DEV.469"
    eval(Meta.parse("""
    public check_pr, merge_prs, TagBot
    """))
end

include("TagBot/TagBot.jl")

include("types.jl")
include("ciservice.jl")

include("api_rate_limiting.jl")
include("assert.jl")
include("automerge_comment.jl")
include("changed_files.jl")
include("cron.jl")
include("dates.jl")
include("dependency_confusion.jl")
include("github.jl")
include("guidelines.jl")
include("jll.jl")
include("juliaup.jl")
include("not_automerge_applicable.jl")
include("package_path_in_registry.jl")
include("public.jl")
include("pull_requests.jl")
include("semver.jl")
include("toml.jl")
include("update_status.jl")
include("util.jl")

end # module
