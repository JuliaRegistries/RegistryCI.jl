# The actual relative path of the package as specified in the `Registry.toml` file.
function get_package_relpath_in_registry(; package_name::String, registry_path::String)
    registry_toml_file_name = joinpath(registry_path, "Registry.toml")
    registry_toml_parsed = TOML.parsefile(registry_toml_file_name)
    all_packages = registry_toml_parsed["packages"]
    all_package_names_and_paths = map(x -> (x["name"], x["path"]), values(all_packages))
    matching_package_indices = findall(
        getindex.(all_package_names_and_paths, 1) .== package_name
    )
    num_indices = length(matching_package_indices)
    (num_indices == 0) &&
        throw(ErrorException("no package found with the name $(package_name)"))
    (num_indices != 1) && throw(
        ErrorException(
            "multiple ($(num_indices)) packages found with the name $(package_name)"
        ),
    )
    single_matching_index = only(matching_package_indices)
    single_matching_package = all_package_names_and_paths[single_matching_index]
    _pkgname, _pkgrelpath = single_matching_package
    always_assert(_pkgname == package_name)
    _pkgrelpath::String
    return _pkgrelpath
end

# What the relative path of the package *should* be, in theory.
# This function should ONLY be used in the
# "PR only changes a subset of the allowed files" check.
# For all other uses, you shoud use the `get_package_relpath_in_registry`
# function instead.
function _get_package_relpath_per_name_scheme(; package_name::String)
    return RegistryTools.package_relpath(package_name)
end
