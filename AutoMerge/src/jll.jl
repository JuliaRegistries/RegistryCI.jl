function is_jll_name(name::AbstractString)::Bool
    return endswith(name, "_jll")
end

function _get_all_dependencies_nonrecursive(registry::RegistryInstance, pkg, version)
    # Get dependencies for this version using helper
    deps_dict = get_deps_for_version(registry, pkg, version)

    # Return just the dependency names
    return collect(keys(deps_dict))
end

_get_all_dependencies_nonrecursive(registry::AbstractString, pkg, version) =
    _get_all_dependencies_nonrecursive(RegistryInstance(registry), pkg, version)


const guideline_allowed_jll_nonrecursive_dependencies = Guideline(;
    info="If this is a JLL package, only deps are Pkg, Libdl, and other JLL packages",
    docs=nothing,
    check=data -> meets_allowed_jll_nonrecursive_dependencies(
        data.registry_head, data.pkg, data.version
    ),
)

function meets_allowed_jll_nonrecursive_dependencies(
    registry::RegistryInstance, pkg, version
)
    # If you are a JLL package, you are only allowed to have five kinds of dependencies:
    # 1. Pkg
    # 2. Libdl
    # 3. Artifacts
    # 4. JLLWrappers
    # 5. LazyArtifacts
    # 6. TOML
    # 8. MPIPreferences
    # 7. other JLL packages
    all_dependencies = _get_all_dependencies_nonrecursive(registry, pkg, version)
    allowed_dependencies = ("Pkg", "Libdl", "Artifacts", "JLLWrappers", "LazyArtifacts", "TOML", "MPIPreferences")
    for dep in all_dependencies
        if dep ∉ allowed_dependencies && !is_jll_name(dep)
            return false,
            "JLL packages are only allowed to depend on $(join(allowed_dependencies, ", ")) and other JLL packages"
        end
    end
    return true, ""
end

meets_allowed_jll_nonrecursive_dependencies(registry::AbstractString, pkg, version) =
    meets_allowed_jll_nonrecursive_dependencies(RegistryInstance(registry), pkg, version)
