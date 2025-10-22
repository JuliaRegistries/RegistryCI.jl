@static if Base.VERSION >= v"1.7.0-"
    const isless_ll = Pkg.Versions.isless_ll
    const isless_uu = Pkg.Versions.isless_uu
else
    const isless_ll = Pkg.Types.isless_ll
    const isless_uu = Pkg.Types.isless_uu
end

function difference(x::VersionNumber, y::VersionNumber)
    if y.major > x.major
        return VersionNumber(y.major - x.major, y.minor, y.patch)
    elseif y.minor > x.minor
        return VersionNumber(y.major - x.major, y.minor - x.minor, y.patch)
    elseif y.patch > x.patch
        return VersionNumber(y.major - x.major, y.minor - x.minor, y.patch - x.patch)
    else
        msg = "first argument $(x) must be strictly less than the second argument $(y)"
        @warn msg x y
        return ErrorCannotComputeVersionDifference(msg)
    end
end

function leftmost_nonzero(v::VersionNumber)::Symbol
    if v.major != 0
        return :major
    elseif v.minor != 0
        return :minor
    elseif v.patch != 0
        return :patch
    else
        throw(ArgumentError("there are no nonzero components"))
    end
end

function is_breaking(a::VersionNumber, b::VersionNumber)::Bool
    if a < b
        a_leftmost_nonzero = leftmost_nonzero(a)
        if a_leftmost_nonzero == :major
            if a.major == b.major
                return false # major stayed the same nonzero value => nonbreaking
            else
                return true # major increased => breaking
            end
        elseif a_leftmost_nonzero == :minor
            if a.major == b.major
                if a.minor == b.minor
                    return false # major stayed 0, minor stayed the same nonzero value, patch increased => nonbreaking
                else
                    return true  # major stayed 0 and minor increased => breaking
                end
            else
                return true # major increased => breaking
            end
        else
            always_assert(a_leftmost_nonzero == :patch)
            if a.major == b.major
                if a.minor == b.minor
                    # this corresponds to 0.0.1 -> 0.0.2
                    # set it to true if 0.0.1 -> 0.0.2 should be breaking
                    # set it to false if 0.0.1 -> 0.0.2 should be non-breaking
                    return true # major stayed 0, minor stayed 0, patch increased
                else
                    return true # major stayed 0 and minor increased => breaking
                end
            else
                return true # major increased => breaking
            end
        end
    else
        throw(
            ArgumentError("first argument must be strictly less than the second argument")
        )
    end
end

function all_versions(pkg::String, registry::RegistryInstance)
    info = get_package_info(registry, pkg)
    return collect(keys(info.version_info))
end

all_versions(pkg::String, registry::AbstractString) = all_versions(pkg, RegistryInstance(registry))

function latest_version(pkg::String, registry::RegistryInstance)
    return maximum(all_versions(pkg, registry))
end

latest_version(pkg::String, registry::AbstractString) = latest_version(pkg, RegistryInstance(registry))

function julia_compat(pkg::String, version::VersionNumber, registry::RegistryInstance)
    compat = get_compat_for_version(registry, pkg, version)
    julia_ranges = Pkg.Versions.VersionRange[]
    for (name, spec) in compat
        if lowercase(strip(name)) == "julia"
            append!(julia_ranges, spec.ranges)
        end
    end
    return isempty(julia_ranges) ? [Pkg.Versions.VersionRange("* - *")] : julia_ranges
end

julia_compat(pkg::String, version::VersionNumber, registry::AbstractString) =
    julia_compat(pkg, version, RegistryInstance(registry))

function _has_upper_bound(r::Pkg.Types.VersionRange)
    a = r.upper != Pkg.Types.VersionBound("*")
    b = r.upper != Pkg.Types.VersionBound("0")
    c = !(Base.VersionNumber(0, typemax(Base.VInt), typemax(Base.VInt)) in r)
    d =
        !(
            Base.VersionNumber(
                typemax(Base.VInt), typemax(Base.VInt), typemax(Base.VInt)
            ) in r
        )
    e = !(typemax(Base.VersionNumber) in r)
    result = a && b && c && d && e
    return result
end

function range_did_not_narrow(r1::Pkg.Types.VersionRange, r2::Pkg.Types.VersionRange)
    result = !isless_ll(r1.lower, r2.lower) && !isless_uu(r2.upper, r1.upper)
    return result
end

function range_did_not_narrow(
    v1::Vector{Pkg.Types.VersionRange}, v2::Vector{Pkg.Types.VersionRange}
)
    @debug("", v1, v2, repr(v1), repr(v2))
    if isempty(v1) || isempty(v2)
        return false
    else
        n_1 = length(v1)
        n_2 = length(v2)
        results = falses(n_1, n_2) # v1 along the rows, v2 along the columns
        for i in 1:n_1
            for j in 1:n_2
                results[i, j] = range_did_not_narrow(v1[i], v2[j])
            end
        end
        @debug("", results, repr(results))
        return all(results)
    end
end

thispatch(v::VersionNumber) = VersionNumber(v.major, v.minor, v.patch)
thisminor(v::VersionNumber) = VersionNumber(v.major, v.minor, 0)
thismajor(v::VersionNumber) = VersionNumber(v.major, 0, 0)

function nextpatch(v::VersionNumber)
    return v < thispatch(v) ? thispatch(v) : VersionNumber(v.major, v.minor, v.patch + 1)
end
function nextminor(v::VersionNumber)
    return v < thisminor(v) ? thisminor(v) : VersionNumber(v.major, v.minor + 1, 0)
end
function nextmajor(v::VersionNumber)
    return v < thismajor(v) ? thismajor(v) : VersionNumber(v.major + 1, 0, 0)
end
