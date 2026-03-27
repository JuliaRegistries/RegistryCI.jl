# The actual relative path of the package as specified in the `Registry.toml` file.
function get_package_relpath_in_registry(; package_name::String, registry_path::String)
    registry = RegistryInstance(registry_path)
    # Find the package entry by name and return its path
    for (uuid, entry) in registry.pkgs
        if entry.name == package_name
            return entry.path
        end
    end
    error("Package $package_name not found in registry $(registry.name)")
end

# What the relative path of the package *should* be, in theory.
# This function should ONLY be used in the
# "PR only changes a subset of the allowed files" check.
# For all other uses, you shoud use the `get_package_relpath_in_registry`
# function instead.
function _get_package_relpath_per_name_scheme(; package_name::String)
    return RegistryTools.package_relpath(package_name)
end
