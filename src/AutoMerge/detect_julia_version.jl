

function detect_julia_version(registry_head, pkg, version)
    uuid, package_repo, subdir, tree_hash_from_toml = parse_registry_pkg_info(
        registry_head, pkg, version
    )

    destination = mktempdir()    
    try
        load_files_from_url_and_tree_hash(identity, destination, package_repo, tree_hash_from_toml)
    catch e
        @error "error cloning package!" error=(e, catch_backtrace())
        return nothing
    end

    project_path = joinpath(destination, "Project.toml")
    if !isfile(project_path)
        @error "Project.toml not found at $(project_path)" 
        return nothing
    end

    project = Pkg.Types.read_project(project_path)
    
    julia_compat = get(project.compat, "julia", nothing)

    if julia_compat === nothing
        @error "No Julia compat found" 
        return nothing
    end

    versions = get_julia_versions()
    possible_versions = find_compatible_versions(versions, julia_compat)
    if isempty(possible_versions)
        @error "Julia compat $(julia_compat) not compatible with any known versions $(versions)"
        return nothing
    end

    return maximum(possible_versions)
end


function find_compatible_versions(versions, compat)
    # Branch on before/after <https://github.com/JuliaLang/julia/pull/40422>
    # which pulled in <https://github.com/JuliaLang/Pkg.jl/pull/2480>
    if VERSION < v"1.7.0-DEV.909"
        if isempty(compat)
            return String[]
        end
        semver = Pkg.Types.semver_spec(compat)
    else
        semver = compat.val
    end
    return filter(in(semver), versions)
end

function get_julia_versions()
    io = IOBuffer()
    Downloads.download("https://julialang-s3.julialang.org/bin/versions.json", io)
    seekstart(io)
    json = JSON3.read(io)
    versions = sort(VersionNumber.(String.(keys(json))))
    filter!(v -> v >= v"1" && isempty(v.build) && isempty(v.prerelease),
            versions)
    return versions
end
