# Registry helper functions - abstraction layer over RegistryInstances.jl

import Base: merge!

# Get package info (repo, subdir, versions, compat, deps) by UUID or name
function get_package_info(registry::RegistryInstance, pkg::Union{UUID, AbstractString})
    if pkg isa AbstractString
        # Find UUID by name
        for (uuid, entry) in registry.pkgs
            if entry.name == pkg
                return registry_info(registry.pkgs[uuid])
            end
        end
        error("Package $pkg not found in registry $(registry.name)")
    else
        # pkg is UUID
        if !haskey(registry.pkgs, pkg)
            error("Package with UUID $pkg not found in registry $(registry.name)")
        end
        return registry_info(registry.pkgs[pkg])
    end
end

# Get compat entries for a specific version
function get_compat_for_version(
    registry::RegistryInstance,
    pkg::Union{UUID, AbstractString},
    version::VersionNumber
)
    info = get_package_info(registry, pkg)
    result = Dict{String, Pkg.Versions.VersionSpec}()
    for (version_range, compat_dict) in info.compat
        if version in version_range
            merge!(result, compat_dict)
        end
    end
    return result
end

# Get dependencies for a specific version
function get_deps_for_version(
    registry::RegistryInstance,
    pkg::Union{UUID, AbstractString},
    version::VersionNumber
)
    info = get_package_info(registry, pkg)
    result = Dict{String, UUID}()
    for (version_range, deps_dict) in info.deps
        if version in version_range
            merge!(result, deps_dict)
        end
    end
    return result
end
