using Pkg: Pkg
# import GitCommand
using HTTP: HTTP
using RegistryTools: RegistryTools
using Test: Test

function gather_stdlib_uuids()
    return Set{Base.UUID}(x for x in keys(RegistryTools.stdlibs()))
end

@static if Base.VERSION >= v"1.7.0-"
    const collect_registries = Pkg.Registry.reachable_registries
else
    const collect_registries = Pkg.Types.collect_registries
end

is_valid_url(str::AbstractString) = !isempty(HTTP.URI(str).scheme) && isvalid(HTTP.URI(str))

function _include_this_registry(
    registry_spec, registry_deps_names::Vector{<:AbstractString}
)
    all_fieldvalues = []
    for fieldname in [:name, :repo, :url]
        if hasproperty(registry_spec, fieldname)
            fieldvalue = getproperty(registry_spec, fieldname)
            if fieldvalue isa AbstractString
                push!(all_fieldvalues, fieldvalue)
            end
        end
    end
    for fieldvalue in all_fieldvalues
        for registry_deps_name in registry_deps_names
            if strip(fieldvalue) == strip(registry_deps_name)
                return true
            end
            if strip(fieldvalue) == strip("$(registry_deps_name).git")
                return true
            end
            if strip("$(fieldvalue).git") == strip(registry_deps_name)
                return true
            end
        end
    end
    return false
end

# For when you have a registry that has packages with dependencies obtained from
# another dependency registry. For example, packages registered at the BioJuliaRegistry
# that have General dependencies. BJW.
function load_registry_dep_uuids(registry_deps_names::Vector{<:AbstractString}=String[])
    return with_temp_depot() do
        # Get the registries!
        for repo_spec in registry_deps_names
            if is_valid_url(repo_spec)
                Pkg.Registry.add(Pkg.RegistrySpec(; url=repo_spec))
            else
                Pkg.Registry.add(repo_spec)
            end
        end
        # Now use the RegistrySpec's to find the Project.toml's. I know
        # .julia/registires/XYZ/ABC is the most likely place, but this way the
        # function never has to assume. BJW.
        extrauuids = Set{Base.UUID}()
        for spec in collect_registries()
            if _include_this_registry(spec, registry_deps_names)
                reg = Pkg.TOML.parsefile(joinpath(spec.path, "Registry.toml"))
                for x in keys(reg["packages"])
                    push!(extrauuids, Base.UUID(x))
                end
            end
        end
        return extrauuids
    end
end

#########################
# Testing of registries #
#########################

function load_package_data(
    ::Type{T}, path::String, versions::Vector{VersionNumber}
) where {T}
    compressed = Pkg.TOML.parsefile(path)
    compressed = convert(Dict{String,Dict{String,Union{String,Vector{String}}}}, compressed)
    uncompressed = Dict{VersionNumber,Dict{String,T}}()
    # Many of the entries are repeated so we keep a cache so there is no need to re-create
    # a bunch of identical objects
    cache = Dict{String,T}()
    vsorted = sort(versions)
    for (vers, data) in compressed
        vs = Pkg.Types.VersionRange(vers)
        first = length(vsorted) + 1
        # We find the first and last version that are in the range
        # and since the versions are sorted, all versions in between are sorted
        for i in eachindex(vsorted)
            v = vsorted[i]
            v in vs && (first = i; break)
        end
        last = 0
        for i in reverse(eachindex(vsorted))
            v = vsorted[i]
            v in vs && (last = i; break)
        end
        for i in first:last
            v = vsorted[i]
            uv = get!(() -> Dict{String,T}(), uncompressed, v)
            for (key, value) in data
                if haskey(uv, key)
                    error("Overlapping ranges for $(key) in $(repr(path)) for version $v.")
                else
                    Tvalue = if value isa String
                        Tvalue = get!(() -> T(value), cache, value)
                    else
                        Tvalue = T(value)
                    end
                    uv[key] = Tvalue
                end
            end
        end
    end
    return uncompressed
end

function load_deps(depsfile, versions)
    r =
        load_package_data(Base.UUID, depsfile, versions) isa
        Dict{VersionNumber,Dict{String,Base.UUID}}
    return r
end

function load_compat(compatfile, versions)
    r =
        load_package_data(Pkg.Types.VersionSpec, compatfile, versions) isa
        Dict{VersionNumber,Dict{String,Pkg.Types.VersionSpec}}
    return r
end

"""
    test(path)

Run various checks on the registry located at `path`.
Checks for example that all files are parsable and
understandable by Pkg and consistency between Registry.toml
and each Package.toml.

If your registry has packages that have dependencies that are registered in other
registries elsewhere, then you may provide the github urls for those registries
using the `registry_deps` parameter.
"""
function test(path=pwd(); registry_deps::Vector{<:AbstractString}=String[])
    Test.@testset "(Registry|Package|Versions|Deps|Compat).toml" begin
        cd(path) do
            reg = Pkg.TOML.parsefile("Registry.toml")
            reguuids = Set{Base.UUID}(Base.UUID(x) for x in keys(reg["packages"]))
            stdlibuuids = gather_stdlib_uuids()
            registry_dep_uuids = load_registry_dep_uuids(registry_deps)
            alluuids = reguuids ∪ stdlibuuids ∪ registry_dep_uuids

            # Test that each entry in Registry.toml has a corresponding Package.toml
            # at the expected path with the correct uuid and name
            Test.@testset "$(get(data, "name", uuid))" for (uuid, data) in reg["packages"]
                # Package.toml testing
                pkg = Pkg.TOML.parsefile(abspath(data["path"], "Package.toml"))
                Test.@test Base.UUID(uuid) == Base.UUID(pkg["uuid"])
                Test.@test data["name"] == pkg["name"]
                Test.@test Base.isidentifier(data["name"])
                Test.@test haskey(pkg, "repo")

                # Versions.toml testing
                vers = Pkg.TOML.parsefile(abspath(data["path"], "Versions.toml"))
                vnums = VersionNumber.(keys(vers))
                for (v, data) in vers
                    Test.@test VersionNumber(v) isa VersionNumber
                    Test.@test haskey(data, "git-tree-sha1")
                end

                # Deps.toml testing
                depsfile = abspath(data["path"], "Deps.toml")
                if isfile(depsfile)
                    deps = Pkg.TOML.parsefile(depsfile)
                    # Require all deps to exist in the General registry or be a stdlib
                    depuuids = Set{Base.UUID}(
                        Base.UUID(x) for (_, d) in deps for (_, x) in d
                    )
                    if !(depuuids ⊆ alluuids)
                        msg = "It is not the case that all dependencies exist in the General registry"
                        @error msg setdiff(depuuids, alluuids)
                    end
                    Test.@test depuuids ⊆ alluuids
                    # Test that the way Pkg loads this data works
                    Test.@test load_deps(depsfile, vnums)
                    # Make sure the content roundtrips through decompression/compression
                    compressed = RegistryTools.Compress.compress(
                        depsfile, RegistryTools.Compress.load(depsfile)
                    )
                    Test.@test compressed == deps
                end

                # Compat.toml testing
                compatfile = abspath(data["path"], "Compat.toml")
                if isfile(compatfile)
                    compat = Pkg.TOML.parsefile(compatfile)
                    # Test that all names with compat is a dependency
                    compatnames = Set{String}(x for (_, d) in compat for (x, _) in d)
                    if !(
                        isempty(compatnames) ||
                        (length(compatnames) == 1 && "julia" in compatnames)
                    )
                        depnames = Set{String}(
                            x for (_, d) in Pkg.TOML.parsefile(depsfile) for (x, _) in d
                        )
                        push!(depnames, "julia") # All packages has an implicit dependency on julia
                        if !(compatnames ⊆ depnames)
                            throw(
                                ErrorException("Assertion failed: compatnames ⊆ depnames")
                            )
                        end
                    end
                    # Test that the way Pkg loads this data works
                    Test.@test load_compat(compatfile, vnums)
                    # Make sure the content roundtrips through decompression/compression.
                    # However, before we check for equality, we change the compat ranges
                    # from `String`s to `VersionRanges`.
                    compressed = RegistryTools.Compress.compress(
                        compatfile, RegistryTools.Compress.load(compatfile)
                    )
                    mapvalues = (f, dict) -> Dict(k => f(v) for (k, v) in dict)
                    f_inner = v -> Pkg.Types.VersionRange.(v)
                    f_outer = dict -> mapvalues(f_inner, dict)
                    Test.@test mapvalues(f_outer, compressed) == mapvalues(f_outer, compat)
                end
            end
            # Make sure all paths are unique
            path_parts = [splitpath(data["path"]) for (_, data) in reg["packages"]]
            for i in 1:maximum(length, path_parts)
                i_parts = Set(
                    joinpath(x[1:i]...) for
                    x in path_parts if get(x, i, nothing) !== nothing
                )
                i_parts′ = Set(
                    joinpath(lowercase.(x[1:i])...) for
                    x in path_parts if get(x, i, nothing) !== nothing
                )
                Test.@test length(i_parts) == length(i_parts′)
            end
        end
    end
    return nothing
end
