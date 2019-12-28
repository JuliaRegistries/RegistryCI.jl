import Pkg
import GitCommand
import Test

function gather_stdlib_uuids()
    if VERSION < v"1.1"
        return Set{Base.UUID}(x for x in keys(Pkg.Types.gather_stdlib_uuids()))
    else
        return Set{Base.UUID}(x for x in keys(Pkg.Types.stdlib()))
    end
end

#########################
# Testing of registries #
#########################

"""
    test(path)

Run various checks on the registry located at `path`.
Checks for example that all files are parsable and
understandable by Pkg and consistency between Registry.toml
and each Package.toml.
"""
function test(path=pwd())
    Test.@testset "(Registry|Package|Versions|Deps|Compat).toml" begin; cd(path) do
        reg = Pkg.TOML.parsefile("Registry.toml")
        reguuids = Set{Base.UUID}(Base.UUID(x) for x in keys(reg["packages"]))
        stdlibuuids = gather_stdlib_uuids()
        alluuids = reguuids ∪ stdlibuuids

        # Test that each entry in Registry.toml has a corresponding Package.toml
        # at the expected path with the correct uuid and name
        for (uuid, data) in reg["packages"]
            # Package.toml testing
            pkg = Pkg.TOML.parsefile(abspath(data["path"], "Package.toml"))
            Test.@test Base.UUID(uuid) == Base.UUID(pkg["uuid"])
            Test.@test data["name"] == pkg["name"]
            Test.@test Base.isidentifier(data["name"])
            Test.@test haskey(pkg, "repo")

            # Versions.toml testing
            vers = Pkg.TOML.parsefile(abspath(data["path"], "Versions.toml"))
            for (v, data) in vers
                Test.@test VersionNumber(v) isa VersionNumber
                Test.@test haskey(data, "git-tree-sha1")
            end

            # Deps.toml testing
            depsfile = abspath(data["path"], "Deps.toml")
            if isfile(depsfile)
                deps = Pkg.TOML.parsefile(depsfile)
                # Require all deps to exist in the General registry or be a stdlib
                depuuids = Set{Base.UUID}(Base.UUID(x) for (_, d) in deps for (_, x) in d)
                Test.@test depuuids ⊆ alluuids
                # Test that the way Pkg loads this data works
                Test.@test Pkg.Operations.load_package_data_raw(Base.UUID, depsfile) isa
                    Dict{Pkg.Types.VersionRange,Dict{String,Base.UUID}}
            end

            # Compat.toml testing
            compatfile = abspath(data["path"], "Compat.toml")
            if isfile(compatfile)
                compat = Pkg.TOML.parsefile(compatfile)
                # Test that all names with compat is a dependency
                compatnames = Set{String}(x for (_, d) in compat for (x, _) in d)
                if !(isempty(compatnames) || (length(compatnames)== 1 && "julia" in compatnames))
                    depnames = Set{String}(x for (_, d) in Pkg.TOML.parsefile(depsfile) for (x, _) in d)
                    push!(depnames, "julia") # All packages has an implicit dependency on julia
                    @assert compatnames ⊆ depnames
                end
                # Test that the way Pkg loads this data works
                Test.@test Pkg.Operations.load_package_data_raw(Pkg.Types.VersionSpec, compatfile) isa
                    Dict{Pkg.Types.VersionRange,Dict{String,Pkg.Types.VersionSpec}}
            end
        end
    end end
    return
end
