# TODO: Add a more thorough explanation of the dependency confusion
# vulnerability and how this guideline mitigates it.

const guideline_dependency_confusion = Guideline(;
    info="No UUID conflict with other registries.",
    docs=nothing,
    check=data ->
        has_no_dependency_confusion(data.pkg, data.registry_head, data.public_registries),
)

# TODO: Needs a strategy to handle connection failures for the public
# registries. Preferably they should also be cloned only once and then
# just updated to mitigate the effect of them being temporarily
# offline. This could be implemented with the help of the Scratch
# package, but requires Julia >= 1.5.
function has_no_dependency_confusion(pkg, registry_head, public_registries)
    pkg_info = parse_registry_pkg_info(registry_head, pkg)
    uuid = pkg_info.uuid
    package_repo = pkg_info.repo
    for repo in public_registries
        try
            registry_path = clone_repo(repo)
            registry = RegistryInstance(registry_path)
            if haskey(registry.pkgs, uuid)
                message = string(
                    "UUID $uuid conflicts with the package ",
                    registry.pkgs[uuid].name,
                    " in registry ",
                    registry.name,
                    " at $repo. ",
                    "This could be a dependency confusion attack.",
                )
                # Conflict detected. This is benign if the package name
                # *and* the package URL matches.
                if registry.pkgs[uuid].name != pkg
                    return false, message
                end
                other_package_repo = get_package_info(registry, uuid).repo
                if package_repo != other_package_repo
                    return false, message
                end
            end
        catch
            message = string(
                "Failed to clone public registry $(repo) for a check against dependency confusion.\n",
                "This is an internal issue with the AutoMerge process and has nothing to do with ", "the package being registered but requires manual intervention before AutoMerge ",
                "can be resumed.",
            )
            return false, message
        end
    end

    return true, ""
end
