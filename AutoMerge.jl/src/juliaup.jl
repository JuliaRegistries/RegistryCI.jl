using juliaup_jll: juliaup, julia

# Cache of available Julia versions, looked up with juliaup.
const available_julia_versions = VersionNumber[]

const version_re = r"^(\d+\.\d+\.\d+(-[\w\d]+)?)$"

# Find all available Julia version by running `juliaup list` and
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
    end
    return available_julia_versions
end

function get_julia_binary(version, kind)
    Base.run(`$(juliaup()) add $(version)`)
    cmd = `$(julia()) +$(version)`
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

    # Find the smallest compatible version.
    smallest_compat = minimum(all_compatible_versions)
    # But we rather want the highest compatible version with the same
    # major.minor.
    a = smallest_compat.major
    b = smallest_compat.minor
    same_major_minor = v -> (v.major == a && v.minor == b)
    smallest_compat = maximum(filter(same_major_minor, all_compatible_versions))

    # Find the highest compatible version. Only consider pre-releases
    # if there is no compatible release.
    if isempty(all_compatible_releases)
        highest_compat = maximum(all_compatible_versions)
    else
        highest_compat = maximum(all_compatible_releases)
    end

    if smallest_compat == highest_compat
        push!(binaries, get_julia_binary(smallest_compat, "only"))
    else
        push!(binaries, get_julia_binary(smallest_compat, "smallest"))
        push!(binaries, get_julia_binary(highest_compat, "highest"))
    end

    return binaries
end
