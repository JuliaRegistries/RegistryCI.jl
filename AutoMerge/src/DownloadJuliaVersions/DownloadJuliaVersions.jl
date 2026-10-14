module DownloadJuliaVersions

# The public API of the DownloadJuliaVersions module consists only of the following five public functions:
if VERSION >= v"1.11"
    eval(Meta.parse("""
    public supported_julia_versions,
           compatible_julia_versions,
           julia_binary,
           julia_binary_cmd,
           update_versions_json
    """))
end

import Artifacts
import Downloads
import JSON
import Pkg
import Scratch
import Tar

# julia +1.12 --project
#
# import Revise
# import AutoMerge
# using AutoMerge: DownloadJuliaVersions
#
# DownloadJuliaVersions.__init__()
#
# DownloadJuliaVersions.supported_julia_versions()
# DownloadJuliaVersions.compatible_julia_versions("1.10")
# DownloadJuliaVersions.julia_binary(v"1.7.1")
# DownloadJuliaVersions.julia_binary_cmd(v"1.7.1")
# run(`$(DownloadJuliaVersions.julia_binary_cmd(v"1.7.1")) --version`)
#
# DownloadJuliaVersions.update_versions_json()

# These three are defined in __init__()
const GLOBAL_LOCK = Ref{ReentrantLock}()
const DID_DOWNLOAD_VERSIONS_JSON_THIS_SESSION = Ref{Bool}()
const DOWNLOAD_CACHE = Ref{String}()

# This one is defined in _ensure_versions_json()
const SUPPORTED_TARBALL_DICT = Ref{Dict{VersionNumber, JSON.Object}}()

function __init__()
    GLOBAL_LOCK[] = ReentrantLock()
    DID_DOWNLOAD_VERSIONS_JSON_THIS_SESSION[] = false
    cache_scheme = "v1" # our own internal scheme version number
    DOWNLOAD_CACHE[] = Scratch.@get_scratch!("DOWNLOAD_CACHE-$cache_scheme")
    return nothing
end

### BEGIN public interface

"""
    supported_julia_versions(; include_prereleases=false) -> Vector{VersionNumber}

Return the list of Julia versions that are supported on this platform.

Set `include_prereleases=true` to include prereleases.
"""
function supported_julia_versions(; include_prereleases = false)::Vector{VersionNumber}
    supported_tarball_dict = _supported_julia_tarballs_dict()
    supported_versions = collect(keys(supported_tarball_dict))
    if !include_prereleases
        filter!(ver -> ver.prerelease == (), supported_versions)
    end
    sort!(unique!(supported_versions))
    return supported_versions
end

"""
    compatible_julia_versions(compat_entry::AbstractString; include_prereleases=false) -> Vector{VersionNumber}

Return the list of Julia versions that are supported on this platform and are compatible with
the provided `[compat]` entry.

Set `include_prereleases=true` to include prereleases.
"""
function compatible_julia_versions(julia_compat_entry::AbstractString; include_prereleases = false)::Vector{VersionNumber}
    spec = Pkg.Types.semver_spec(julia_compat_entry)
    return _compatible_julia_versions(spec; include_prereleases)
end

"""
    julia_binary_cmd(ver::VersionNumber) -> Cmd


Returns a `Cmd` with the file path of the Julia executable for the specified Julia version.

If the specified Julia version has not been downloaded yet, this function will download it.
"""
function julia_binary_cmd(ver::VersionNumber)::Cmd
    return Cmd([julia_binary(ver)])
end

"""
    julia_binary(ver::VersionNumber) -> String

Returns a string with the file path of the Julia executable for the specified Julia version.

If the specified Julia version has not been downloaded yet, this function will download it.
"""
function julia_binary(ver::VersionNumber)::String
    _ensure_julia_version_downloaded(ver)
    return _julia_executable_location(ver)
end

"""
    update_versions_json() -> Nothing

Update the locally-cached `versions.json` file. Usually, this is done automatically,
and so most users will never need to run this function manually.
"""
function update_versions_json()
    _ensure_versions_json(; explicitly_requested = true, throw_on_error = true)
    return nothing
end

### END public interface

# The `_compatible_julia_versions` function is NOT public.
# However, AutoMerge uses it, in the `AutoMerge.get_compatible_julia_binaries` function.
# So avoid breaking it.
function _compatible_julia_versions(julia_compat_spec::Pkg.Types.VersionSpec; include_prereleases = false)
    compatible_versions = supported_julia_versions(; include_prereleases)
    filter!(ver -> ver in julia_compat_spec, compatible_versions)
    return compatible_versions
end
function _compatible_julia_versions(julia_compat_ranges::AbstractVector{Pkg.Versions.VersionRange}; include_prereleases = false)
    spec = Pkg.Versions.VersionSpec(julia_compat_ranges)
    return _compatible_julia_versions(spec; include_prereleases)
end

function _cachepath_versions_json()
    cache = lock(GLOBAL_LOCK[]) do
        DOWNLOAD_CACHE[]
    end
    return joinpath(cache, "versions.json")
end

# Source: https://github.com/JuliaCI/rootfs-images
# https://github.com/JuliaCI/rootfs-images/blob/40538d27427843eaf0a67da8239c422160e495b3/src/test_img/test.jl#L23-L43
# License: MIT
function _ensure_artifact_exists_locally(; tree_hash::Base.SHA1, tarball_url::AbstractString, tarball_hash::AbstractString)
    if !Pkg.Artifacts.artifact_exists(tree_hash)
        @info("Artifact did not exist locally, downloading from: $tarball_url")
        return_value = Pkg.Artifacts.download_artifact(tree_hash, tarball_url, tarball_hash; verbose=true)
        if return_value !== true
            (return_value isa Bool) || throw(return_value)
            error("Download was not a success")
        end
    end
    if !Pkg.Artifacts.artifact_exists(tree_hash)
        error("Could not download and extract the artifact from $tarball_url")
    end
    return nothing
end

function _ensure_versions_json(; explicitly_requested = false, throw_on_error = false)
    lock(GLOBAL_LOCK[]) do
        if DID_DOWNLOAD_VERSIONS_JSON_THIS_SESSION[] && !explicitly_requested
            return nothing # return from inside the `lock() do ... end` block
        end
        dest = _cachepath_versions_json()
        tmpfile = try
            # https://github.com/JuliaLang/VersionsJSONUtil.jl
            # TODO: Switch to the official upstream URL:
            # https://julialang-s3.julialang.org/bin/versions.json
            Downloads.download("https://raw.githubusercontent.com/DilumAluthge/test-versions-json/refs/heads/main/versions.json")
        catch ex
            if throw_on_error || !(ex isa Downloads.RequestError)
                error("Encountered an error while trying to update `versions.json`")
            else
                @warn "Ignoring an error while trying to update `versions.json`: $ex"
            end
            nothing
        end
        if tmpfile !== nothing
            mkpath(dirname(dest))
            cp(tmpfile, dest; force = true)
            DID_DOWNLOAD_VERSIONS_JSON_THIS_SESSION[] = true
        end
        versions_json_parsed = JSON.parsefile(dest)
        if isempty(versions_json_parsed)
            error("Tried to parse `versions.json`, but it was empty")
        end
        SUPPORTED_TARBALL_DICT[] = _generate_supported_julia_tarballs_dict(versions_json_parsed)
    end
    return nothing
end

# "supported" = we have native Julia binaries for this platform AND we have a .tar.gz available
# "compatible" = everything in "supported" AND it's compatible with the specified Julia compat entry

_this_host() = Base.BinaryPlatforms.HostPlatform()
function _generate_supported_julia_tarballs_dict(versions_json_parsed::JSON.Object)
    this_host = _this_host()
    supported_tarball_dict = Dict{VersionNumber, JSON.Object}()
    for (verstr, info) in versions_json_parsed
        for file in info.files
            plat = parse(Base.BinaryPlatforms.Platform, file.triplet)
            if Base.BinaryPlatforms.platforms_match(this_host, plat) && (file.extension == "tar.gz")
                ver = VersionNumber(verstr)
                broken_on_apple_silicon_macos = [
                    # Versions.json claims that we have native builds for the following
                    # versions on Apple Silicon macOS. However, the binaries aren't
                    # actually runnable. We need to fix this in upstream versions.json,
                    # but for now we hardcode the list here and exclude them.
                    v"1.7.0-beta3",
                    v"1.7.0-beta4",
                    v"1.7.0-rc1",
                    v"1.7.0-rc2",
                    v"1.7.0-rc3",
                    v"1.7.0",
                    # 1.7.1 and later work just fine
                ]
                if !(Sys.isapple() && (Sys.ARCH == :aarch64) && (ver in broken_on_apple_silicon_macos))
                    supported_tarball_dict[ver] = file
                end
            end
        end
    end
    return supported_tarball_dict
end

function _supported_julia_tarballs_dict()
    dict = lock(GLOBAL_LOCK[]) do
        _ensure_versions_json()
        SUPPORTED_TARBALL_DICT[]
    end
    return dict
end

function _single_tarball_info(ver::VersionNumber)
    supported_tarball_dict = _supported_julia_tarballs_dict()
    if !haskey(supported_tarball_dict, ver)
        error("Julia version $ver does not have a supported tarball for this host $(_this_host())")
    end
    tarball_info = supported_tarball_dict[ver]
    return tarball_info
end

function _julia_version_to_treehash(ver::VersionNumber)
    tarball_file_info = _single_tarball_info(ver)
    treehash = Base.SHA1(tarball_file_info["git-tree-sha1"])
    return treehash
end

function _julia_executable_location(ver::VersionNumber)
    treehash = _julia_version_to_treehash(ver)
    parent_dir = Artifacts.artifact_path(treehash)
    subdir = only(readdir(parent_dir))
    if subdir != "julia-$ver"
        @warn "Expected subdir to be named `julia-$ver`, but got `$subdir`"
    end
    julia_executable = joinpath(
        parent_dir,
        subdir,
        "bin",
        Sys.iswindows() ? "julia.exe" : "julia"
    )
    return julia_executable
end

function _ensure_julia_version_downloaded(ver::VersionNumber)
    tarball_file_info = _single_tarball_info(ver)
    tree_hash = Base.SHA1(tarball_file_info["git-tree-sha1"])
    tarball_url = tarball_file_info.url
    tarball_hash = tarball_file_info.sha256
    _ensure_artifact_exists_locally(; tree_hash, tarball_url, tarball_hash)
    if !isfile(_julia_executable_location(ver))
        error("The Julia $ver executable seems to be missing")
    end
end

end # module
