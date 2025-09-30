using juliaup_jll: juliaup, julia

# Cache of available Julia versions, looked up with juliaup.
const available_julia_versions = VersionNumber[]

const version_re = r"^(\d+\.\d+\.\d+(-[\w\d]+)?)$"

# Find all available Julia versions by running `juliaup list` and
# parsing the output.
#
# This is inherently brittle with respect to the details of the
# juliaup printing. It would be better if juliaup had an option to
# output the versions in a stable machine-readable format, but for now
# we'll have to do with this.
function find_available_julia_versions()
    if isempty(available_julia_versions)
        Base.run(`$(juliaup()) update`)
        for line in readlines(`$(juliaup()) list`)
            # Lines look similar to
            # " 1.11.6               1.11.6+0.x64.linux.gnu"
            # Extract the first part, "1.11.6".
            line = first(split(strip(line)))

            # Ignore all 0.x versions.
            startswith(line, "0.") && continue

            m = match(version_re, line)
            if !isnothing(m)
                version = VersionNumber(m.captures[1])
                push!(available_julia_versions, version)
            end
        end
        # The number of available julia versions is assumed to be
        # monotonically increasing. On 2025-09-30, when 1.12.0-rc3 was
        # the highest available version, there were 126 available
        # versions by this count. Should this number ever decrease,
        # the only explanations are that either juliaup printing has
        # changed so that we misinterpret the output or that juliaup
        # has changed what versions it lists. Either way it needs
        # investigation, so better error here. (This does not cover
        # everything but at least provides a simple sanity check. Feel
        # free to increase this threshold over time.)
        #
        # However, this version count is platform dependent. The
        # number above is for 64-bit Linux. Since this is run in
        # production for the General registry on that platform, we
        # only perform the sanity check in that case rather than
        # trying to adapt the threshold per platform.
        #
        # Note: In case an emergency fix or workaround is needed, it
        # might help to pin juliaup_jll to an earlier version.
        if Sys.MACHINE == "x86_64-linux-gnu" && length(available_julia_versions) < 126
            error("Internal error. Parsing of juliaup output might be outdated.")
        end
    end
    return available_julia_versions
end

function get_julia_binary(version, kind)
    Base.run(`$(juliaup()) add $(version)`)
    # Disable adjust_LIBPATH since we are calling a standalone Julia
    # installation. Otherwise libraries may mismatch.
    cmd = `$(julia(adjust_LIBPATH = false)) +$(version)`
    text = "julia $(version) ($kind compatible version)"
    return cmd, text
end

function get_compatible_julia_binaries(julia_compat, min_version)
    all_versions = find_available_julia_versions()
    filter!(>=(min_version), all_versions)

    all_releases = filter(v -> isempty(v.prerelease), all_versions)

    all_compatible_versions = filter(v -> any(in.(v, julia_compat)), all_versions)
    all_compatible_releases = filter(v -> any(in.(v, julia_compat)), all_releases)
    binaries = Tuple{Cmd, String}[]

    if isempty(all_compatible_versions)
        return binaries
    end

    # Find the lowest compatible version.
    lowest_compat = minimum(all_compatible_versions)
    # But we rather want the highest compatible version with the same
    # major.minor.
    a = lowest_compat.major
    b = lowest_compat.minor
    same_major_minor = v -> (v.major == a && v.minor == b)
    lowest_compat = maximum(filter(same_major_minor, all_compatible_versions))

    # Find the highest compatible version. Only consider pre-releases
    # if there is no compatible release.
    if isempty(all_compatible_releases)
        highest_compat = maximum(all_compatible_versions)
    else
        highest_compat = maximum(all_compatible_releases)
    end

    if lowest_compat == highest_compat
        push!(binaries, get_julia_binary(lowest_compat, "only"))
    else
        push!(binaries, get_julia_binary(lowest_compat, "lowest"))
        push!(binaries, get_julia_binary(highest_compat, "highest"))
    end

    return binaries
end
