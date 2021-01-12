# This is a somewhat artificial guideline that always fails. The point
# is the messages.
const guideline_jll_only_authorization =
    Guideline("JLL-only authors cannot register non-JLL packages.",
              data -> (false, "This package is not a JLL package. The author of this pull request is not authorized to register non-JLL packages."))

function is_jll_name(name::AbstractString)::Bool
    return endswith(name, "_jll")
end

function _get_all_dependencies_nonrecursive(working_directory::AbstractString,
                                            pkg,
                                            version)
    all_dependencies = String[]
    deps = Pkg.TOML.parsefile(joinpath(working_directory, uppercase(pkg[1:1]), pkg, "Deps.toml"))
    for version_range in keys(deps)
        if version in Pkg.Types.VersionRange(version_range)
            for name in keys(deps[version_range])
                push!(all_dependencies, name)
            end
        end
    end
    unique!(all_dependencies)
    return all_dependencies
end

const guideline_allowed_jll_nonrecursive_dependencies =
    Guideline("If this is a JLL package, only deps are Pkg, Libdl, and other JLL packages",
              data -> meets_allowed_jll_nonrecursive_dependencies(data.registry_head,
                                                                  data.pkg,
                                                                  data.version))

function meets_allowed_jll_nonrecursive_dependencies(working_directory::AbstractString,
                                                     pkg,
                                                     version)
    # If you are a JLL package, you are only allowed to have five kinds of dependencies:
    # 1. Pkg
    # 2. Libdl
    # 3. Artifacts
    # 4. JLLWrappers
    # 5. other JLL packages
    all_dependencies = _get_all_dependencies_nonrecursive(working_directory,
                                                          pkg,
                                                          version)
    for dep in all_dependencies
        if dep ∉ ("Pkg", "Libdl", "Artifacts", "JLLWrappers") && !is_jll_name(dep)
            return false, "JLL packages are only allowed to depend on Pkg, Libdl, Artifacts, JLLWrappers and other JLL packages"
        end
    end
    return true, ""
end
