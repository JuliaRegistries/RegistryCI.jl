module JuliaupExt

using juliaup_jll: juliaup, julia
import RegistryCI.AutoMerge

function __init__()
    AutoMerge.guideline_version_can_be_imported_trampoline[] =
        guideline_version_can_be_imported_v2
end

# Cache of available Julia versions, looked up with juliaup.
const available_julia_versions = VersionNumber[]

const version_re = r"^(\d+\.\d+\.\d+(-[\w\d]+)?)$"

function find_available_julia_versions()
    if isempty(available_julia_versions)
        run(`$(juliaup()) update`)
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
    run(`$(juliaup()) add $(version)`)
    cmd = `$(julia()) +$(version)`
    text = "julia $(version) ($kind compatible version)"
    return cmd, text
end


function get_compatible_julia_versions(julia_compat)
    all_versions = find_available_julia_versions()
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

# Fills the same purpose as `guideline_version_can_be_imported` but
# tries to import the package with the lowest and highest compatible
# Julia versions, rather than with the version being used to run
# Automerge.
const guideline_version_can_be_imported_v2 = AutoMerge.Guideline(;
    info="Version can be `import`ed",
    docs="Package loading: The package should be loadable (`import PackageName`).",
    check=data -> meets_version_can_be_imported_v2(
        data.registry_head,
        data.pkg,
        data.version;
        registry_deps=data.registry_deps,
        environment_variables_to_pass=data.environment_variables_to_pass,
    ),
)

function meets_version_can_be_imported_v2(
    working_directory::String,
    pkg::String,
    version::VersionNumber;
    registry_deps::Vector{<:AbstractString}=String[],
    environment_variables_to_pass::Vector{String},
)
    pkg_add_command = AutoMerge._generate_pkg_add_command(pkg, version)
    _registry_deps = convert(Vector{String}, registry_deps)
    _registry_deps_is_valid_url = AutoMerge.is_valid_url.(_registry_deps)
    code = """
        import Pkg;
        Pkg.Registry.add(Pkg.RegistrySpec(path=\"$(working_directory)\"));
        _registry_deps = $(_registry_deps);
        _registry_deps_is_valid_url = $(_registry_deps_is_valid_url);
        for i = 1:length(_registry_deps)
            regdep = _registry_deps[i]
            if _registry_deps_is_valid_url[i]
                Pkg.Registry.add(Pkg.RegistrySpec(url = regdep))
            else
                Pkg.Registry.add(regdep)
            end
        end
        @info("Attempting to `Pkg.add` package...");
        $(pkg_add_command)
        @info("Successfully `Pkg.add`ed package");
        @info("Attempting to `import` package");
        Pkg.precompile()
        import $(pkg);
        @info("Successfully `import`ed package");
        """

    julia_compat = AutoMerge.julia_compat(pkg, version, working_directory)
    julia_versions = get_compatible_julia_versions(julia_compat)
    if isempty(julia_versions)
        @error "Was not able to find a compatible Julia version. julia_compat: $(julia_compat)"
        return false, "I was not able to find a compatible Julia version. See the AutoMerge logs for details."
    end
    for (binary, version_text) in julia_versions
        cmd_ran_successfully = AutoMerge._run_pkg_commands(
            working_directory,
            pkg,
            version;
            binary=binary,
            code=code,
            before_message="Attempting to `import` the package on $(version_text)",
            environment_variables_to_pass=environment_variables_to_pass,
        )

        if cmd_ran_successfully
            @info "Successfully `import`ed the package on $(version_text)"
        else
            @error "Was not able to successfully `import` the package on $(version_text)"
            return false,
            string(
                "I was not able to load the package on $(version_text)",
                "(i.e. `import $(pkg)` failed). ",
                "See the AutoMerge logs for details.",
            )
        end
    end
    return true, ""
end


end
