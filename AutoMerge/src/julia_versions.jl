function get_compatible_julia_binaries(julia_compat::AbstractVector{Pkg.Versions.VersionRange}, min_version::VersionNumber)::Vector{Tuple{Cmd, String}}
    # "stable" = non-prerelease
    stables_and_prereleases = DownloadJuliaVersions._compatible_julia_versions(julia_compat; include_prereleases = true)
    stables_only            = DownloadJuliaVersions._compatible_julia_versions(julia_compat; include_prereleases = false)
    filter!(x -> x >= min_version, stables_and_prereleases)
    filter!(x -> x >= min_version, stables_only)

    if isempty(stables_and_prereleases)
        # In this case, there are no compatible stables, and there are no compatible prereleases
        # So we return an empty list.
        return []
    end

    if isempty(stables_only)
        # In this case, there are no compatible stables, but there is at least one compatible prerelease
        # So, for this case, let's just return the highest compatible prerelease
        highest_compatible_prerelease = maximum(stables_and_prereleases)
        return [(julia_binary_cmd(highest_compatible_prerelease), "Julia $(highest_compatible_prerelease) (only compatible version)")]
    end

    # In this case, there is at least one compatible stable
    # So we won't return any prereleases, we'll only return stables
    highest_compatible_stable = maximum(stables_only)
    lowest_compatible_stable = minimum(stables_only)
    if lowest_compatible_stable == highest_compatible_stable
        return [(julia_binary_cmd(highest_compatible_stable), "Julia $(highest_compatible_stable) (only compatible version)")]
    end
    binaries = [
        (julia_binary_cmd(lowest_compatible_stable), "Julia $(lowest_compatible_stable) (lowest compatible version)"),
        (julia_binary_cmd(highest_compatible_stable), "Julia $(highest_compatible_stable) (highest compatible version)"),
    ]
    return binaries
end
