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
using UUIDs: UUID

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

if VERSION >= v"1.11"
    eval(Meta.parse("""
    public check_pr, merge_prs, TagBot, AutoMergeConfiguration, RegistryConfiguration, CheckPRConfiguration, MergePRsConfiguration, general_registry_config, read_config, write_config,
        Guideline, ProjectInfo, GitHubAutoMergeData, NewPackage, NewVersion, get_automerge_guidelines, check!, passed, message,
        guideline_registry_consistency_tests_pass, guideline_compat_for_julia, guideline_compat_for_all_deps,
        guideline_patch_release_does_not_narrow_julia_compat, guideline_name_length, guideline_name_ascii, guideline_julia_name_check,
        guideline_name_match_check, guideline_project_toml_check, guideline_uuid_match_check, guideline_uuid_sanity_check,
        guideline_breaking_explanation, guideline_distance_check, guideline_name_identifier, guideline_normal_capitalization,
        guideline_repo_url_requirement, guideline_sequential_version_number, guideline_standard_initial_version_number,
        guideline_version_number_no_prerelease, guideline_version_number_no_build, guideline_code_can_be_downloaded,
        guideline_src_names_OK, guideline_version_has_osi_license, guideline_version_can_be_pkg_added,
        guideline_version_can_be_imported, guideline_pr_only_changes_allowed_files,
        guideline_allowed_jll_nonrecursive_dependencies, guideline_dependency_confusion
    """))
end

end # module
