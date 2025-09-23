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
    uuid, package_repo = parse_registry_pkg_info(registry_head, pkg)
    for repo in public_registries
        try
            registry = clone_repo(repo)
            registry_toml = TOML.parsefile(joinpath(registry, "Registry.toml"))
            packages = registry_toml["packages"]
            if haskey(packages, uuid)
                message = string(
                    "UUID $uuid conflicts with the package ",
                    packages[uuid]["name"],
                    " in registry ",
                    registry_toml["name"],
                    " at $repo. ",
                    "This could be a dependency confusion attack.",
                )
                # Conflict detected. This is benign if the package name
                # *and* the package URL matches.
                if packages[uuid]["name"] != pkg
                    return false, message
                end
                package_path = packages[uuid]["path"]
                other_package_repo = TOML.parsefile(
                    joinpath(registry, package_path, "Package.toml")
                )["repo"]
                if package_repo != other_package_repo
                    return false, message
                end
            end
        catch
            message = string(
                "Failed to clone public registry $(repo) for a check against dependency confusion.\n",
                "This is an internal issue with the AutoMerge process and has nothing to do with "."the package being registered but requires manual intervention before AutoMerge ",
                "can be resumed.",
            )
            return false, message
        end
    end

    return true, ""
end
