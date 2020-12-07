import HTTP

function meets_compat_for_all_deps(working_directory::AbstractString, pkg, version)
    deps = Pkg.TOML.parsefile(joinpath(working_directory, uppercase(pkg[1:1]), pkg, "Deps.toml"))
    compat = Pkg.TOML.parsefile(joinpath(working_directory, uppercase(pkg[1:1]), pkg, "Compat.toml"))
    # First, we construct a Dict in which the keys are the package's
    # dependencies, and the value is always false.
    dep_has_compat_with_upper_bound = Dict{String, Bool}()
    @debug("We always have julia as a dependency")
    dep_has_compat_with_upper_bound["julia"] = false
    for version_range in keys(deps)
        if version in Pkg.Types.VersionRange(version_range)
            for name in keys(deps[version_range])
                if (!is_jll_name(name)) & (!is_julia_stdlib(name))
                    @debug("Found a new (non-stdlib non-JLL) dependency: $(name)")
                    dep_has_compat_with_upper_bound[name] = false
                end
            end
        end
    end
    # Now, we go through all the compat entries. If a dependency has a compat
    # entry with an upper bound, we change the corresponding value in the Dict
    # to true.
    for version_range in keys(compat)
        if version in Pkg.Types.VersionRange(version_range)
            for compat_entry in compat[version_range]
                name = compat_entry[1]
                value = compat_entry[2]
                if value isa Vector
                    if !isempty(value)
                        value_ranges = Pkg.Types.VersionRange.(value)
                        each_range_has_upper_bound = _has_upper_bound.(value_ranges)
                        if all(each_range_has_upper_bound)
                            @debug("Dependency \"$(name)\" has compat entries that all have upper bounds")
                            dep_has_compat_with_upper_bound[name] = true
                        end
                    end
                else
                    value_range = Pkg.Types.VersionRange(value)
                    if _has_upper_bound(value_range)
                        @debug("Dependency \"$(name)\" has a compat entry with an upper bound")
                        dep_has_compat_with_upper_bound[name] = true
                    end
                end
            end
        end
    end
    meets_this_guideline = all(values(dep_has_compat_with_upper_bound))
    if meets_this_guideline
        return true, ""
    else
        bad_dependencies = Vector{String}()
        for name in keys(dep_has_compat_with_upper_bound)
            if !(dep_has_compat_with_upper_bound[name])
                @error("Dependency \"$(name)\" does not have a compat entry that has an upper bound")
                push!(bad_dependencies, name)
            end
        end
        sort!(bad_dependencies)
        message = string(
            "The following dependencies do not have a `[compat]` entry ",
            "that is upper-bounded and only includes a finite number ",
            "of breaking releases: ",
            join(bad_dependencies, ", ")
        )
        return false, message
    end
end

function meets_patch_release_does_not_narrow_julia_compat(pkg::String,
                                                          new_version::VersionNumber;
                                                          registry_head::String,
                                                          registry_master::String)
    old_version = latest_version(pkg, registry_master)
    julia_compats_for_old_version = julia_compat(pkg, old_version, registry_master)
    julia_compats_for_new_version = julia_compat(pkg, new_version, registry_head)
    if Set(julia_compats_for_old_version) == Set(julia_compats_for_new_version)
        return true, ""
    end
    meets_this_guideline = range_did_not_narrow(julia_compats_for_old_version, julia_compats_for_new_version)
    if meets_this_guideline
        return true, ""
    else
        if (old_version >= v"1") || (new_version >= v"1")
            msg = string("A patch release is not allowed to narrow the ",
                         "supported ranges of Julia versions. ",
                         "The ranges have changed from ",
                         "$(julia_compats_for_old_version) ",
                         "(in $(old_version)) ",
                         "to $(julia_compats_for_new_version) ",
                         "(in $(new_version)).")
            return false, msg
        else
            @info("Narrows Julia compat, but it's OK since package is pre-1.0")
            return true, ""
        end
    end
end

function meets_name_length(pkg)
    meets_this_guideline = length(pkg) >= 5
    if meets_this_guideline
        return true, ""
    else
        return false, "Name is not at least five characters long"
    end
end

function meets_name_ascii(pkg)
    if isascii(pkg)
        return true, ""
    else
        return false, "Name is not ASCII"
    end
end

function meets_julia_name_check(pkg)
    if occursin("julia", lowercase(pkg))
        return false, "Lowercase package name $(lowercase(pkg)) contains the string \"julia\"."
    elseif startswith(pkg, "Ju")
        return false, "Package name starts with \"Ju\"."
    else
        return true, ""
    end
end

damerau_levenshtein(name1, name2) = StringDistances.DamerauLevenshtein()(name1, name2)
sqrt_normalized_vd(name1, name2) = VisualStringDistances.visual_distance(name1, name2; normalize=x -> 5 + sqrt(x))

function meets_distance_check(pkg_name, other_packages; DL_lowercase_cutoff = 1, DL_cutoff = 2, sqrt_normalized_vd_cutoff = 2.5, comment_collapse_cutoff = 10)
    problem_messages = Tuple{String, Tuple{Float64, Float64, Float64}}[]
    for other_pkg in other_packages
        if pkg_name == other_pkg
            # We short-circuit in this case; more information doesn't help.
            return  (false, "Package name already exists in the registry.")
        elseif lowercase(pkg_name) == lowercase(other_pkg)
            # We'll sort this first
            push!(problem_messages, ("Package name matches existing package name $(other_pkg) up to case.", (0,0,0)))
        else
            msg = ""

            # Distance check 1: DL distance
            dl = damerau_levenshtein(pkg_name, other_pkg)
            if dl <= DL_cutoff
                msg = string(msg, " Damerau-Levenshtein distance $dl is at or below cutoff of $(DL_cutoff).")
            end

            # Distance check 2: lowercase DL distance
            dl_lowercase = damerau_levenshtein(lowercase(pkg_name), lowercase(other_pkg))
            if dl_lowercase <= DL_lowercase_cutoff
                msg = string(msg, " Damerau-Levenshtein distance $(dl_lowercase) between lowercased names is at or below cutoff of $(DL_lowercase_cutoff).")
            end

            # Distance check 3: normalized visual distance,
            # gated by a `dl` check for speed.
            if (sqrt_normalized_vd_cutoff > 0 && dl <= 4)
                nrm_vd = sqrt_normalized_vd(pkg_name, other_pkg)
                if nrm_vd <= sqrt_normalized_vd_cutoff
                    msg = string(msg, " Normalized visual distance ", Printf.@sprintf("%.2f", nrm_vd), " is at or below cutoff of ", Printf.@sprintf("%.2f", sqrt_normalized_vd_cutoff), ".")
                end
            else
                # need to choose something for sorting purposes
                nrm_vd = 10.0
            end

            if msg != ""
                # We must have found a clash.
                push!(problem_messages, (string("Similar to $(other_pkg).", msg), (dl, dl_lowercase, nrm_vd)))
            end
        end
    end

    isempty(problem_messages) && return (true, "")
    sort!(problem_messages, by = Base.tail)
    message = string("Package name similar to $(length(problem_messages)) existing package",
                    length(problem_messages) > 1 ? "s" : "", ".\n")
    if length(problem_messages) > comment_collapse_cutoff
        message *=  """
                    <details>
                    <summary>Similar package names</summary>

                    """
    end
    message *= join(join.(zip(1:length(problem_messages), first.(problem_messages)), Ref(". ")), '\n')
    if length(problem_messages) > comment_collapse_cutoff
        message *=  "\n</details>\n"
    end
    return (false, message)
end

function meets_normal_capitalization(pkg)
    meets_this_guideline = occursin(r"^[A-Z]\w*[a-z]\w*[0-9]?$", pkg)
    if meets_this_guideline
        return true, ""
    else
        return false, "Name does not meet all of the following: starts with an uppercase letter, ASCII alphanumerics only, not all letters are uppercase."
    end
end

function meets_repo_url_requirement(pkg::String; registry_head::String)
    url = Pkg.TOML.parsefile(joinpath(registry_head, uppercase(pkg[1:1]), pkg, "Package.toml"))["repo"]
    meets_this_guideline = url_has_correct_ending(url, pkg)
    if meets_this_guideline
        return true, ""
    else
        return false, "Repo URL does not end with /name.jl.git, where name is the package name"
    end
end

function _invalid_sequential_version(reason::AbstractString)
    return false, "Does not meet sequential version number guideline: $reason", :invalid
end

function _valid_change(old_version::VersionNumber, new_version::VersionNumber)
    diff = difference(old_version, new_version)
    @debug("Difference between versions: ", old_version, new_version, diff)
    if diff == v"0.0.1"
        return true, "", :patch
    elseif diff == v"0.1.0"
        return true, "", :minor
    elseif diff == v"1.0.0"
        return true, "", :major
    else
        return _invalid_sequential_version("increment is not one of: 0.0.1, 0.1.0, 1.0.0")
    end
end

function meets_sequential_version_number(existing::Vector{VersionNumber}, ver::VersionNumber)
    always_assert(!isempty(existing))
    if ver in existing
        return _invalid_sequential_version("version $ver already exists")
    end
    issorted(existing) || (existing = sort(existing))
    idx = searchsortedlast(existing, ver)
    idx > 0 || return _invalid_sequential_version("version $ver less than least existing version $(existing[1])")
    prv = existing[idx]
    always_assert(ver != prv)
    nxt = thismajor(ver) != thismajor(prv) ? nextmajor(prv) :
          thisminor(ver) != thisminor(prv) ? nextminor(prv) : nextpatch(prv)
    ver <= nxt || return _invalid_sequential_version("version $ver skips over $nxt")
    return _valid_change(prv, ver)
end

function _has_no_prerelease_data(version)
    result = version.prerelease == ()
    return result
end
function _has_no_build_data(version)
    result = version.build == ()
    return result
end
_has_prerelease_data(version) = !( _has_no_prerelease_data(version) )
_has_build_data(version) = !( _has_no_build_data(version) )
_has_prerelease_andor_build_data(version) = _has_prerelease_data(version) || _has_build_data(version)

function meets_sequential_version_number(pkg::String,
                                         new_version::VersionNumber;
                                         registry_head::String,
                                         registry_master::String)
    if _has_prerelease_andor_build_data(new_version)
        return false, "Version number is not allowed to contain prerelease or build data", :invalid
    end
    _all_versions = all_versions(pkg, registry_master)
    return meets_sequential_version_number(_all_versions, new_version)
end

function meets_standard_initial_version_number(version)
    if _has_prerelease_andor_build_data(version)
        return false, "Version number is not allowed to contain prerelease or build data"
    end
    meets_this_guideline = version == v"0.0.1" || version == v"0.1.0" || version == v"1.0.0" || _is_x_0_0(version)
    if meets_this_guideline
        return true, ""
    else
        return false, "Version number is not 0.0.1, 0.1.0, 1.0.0, or X.0.0"
    end
end

function _is_x_0_0(version::VersionNumber)
    if _has_prerelease_andor_build_data(version)
        return false
    end
    result = (version.major >= 1) && (version.minor == 0) && (version.patch == 0)
    return result
end

function _generate_pkg_add_command(pkg::String,
                                   version::VersionNumber)::String
    return "Pkg.add(Pkg.PackageSpec(name=\"$(pkg)\", version=v\"$(string(version))\"));"
end

is_valid_url(str::AbstractString) = !isempty(HTTP.URI(str).scheme) && isvalid(HTTP.URI(str))

function meets_version_can_be_pkg_added(working_directory::String,
                                        pkg::String,
                                        version::VersionNumber;
                                        registry_deps::Vector{<:AbstractString} = String[])
    pkg_add_command = _generate_pkg_add_command(pkg,
                                                version)
    _registry_deps = convert(Vector{String}, registry_deps)
    _registry_deps_is_valid_url = Vector{Bool}(undef, length(_registry_deps))
    for i = 1:length(_registry_deps)
        _registry_deps_is_valid_url[i] = is_valid_url(_registry_deps[i])
    end
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
        """
    before_message = "Attempting to `Pkg.add` the package"
    success_message = "Successfully `Pkg.add`ed the package"
    success_return_1 = true
    success_return_2 = ""
    failure_message = "Was not able to successfully `Pkg.add` the package"
    failure_return_1 = false
    failure_return_2 = string("I was not able to install the package ",
                              "(i.e. `Pkg.add(\"$(pkg)\")` failed). ",
                              "See the CI logs for details.")
    return _run_pkg_commands(working_directory,
                             pkg,
                             version;
                             code = code,
                             before_message = before_message,
                             success_message = success_message,
                             success_return_1 = success_return_1,
                             success_return_2 = success_return_2,
                             failure_message = failure_message,
                             failure_return_1 = failure_return_1,
                             failure_return_2 = failure_return_2)
end

function meets_version_can_be_imported(working_directory::String,
                                       pkg::String,
                                       version::VersionNumber;
                                       registry_deps::Vector{<:AbstractString} = String[])
    pkg_add_command = _generate_pkg_add_command(pkg,
                                                version)
    _registry_deps = convert(Vector{String}, registry_deps)
    _registry_deps_is_valid_url = Vector{Bool}(undef, length(_registry_deps))
    for i = 1:length(_registry_deps)
        _registry_deps_is_valid_url[i] = is_valid_url(_registry_deps[i])
    end
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
        import $(pkg);
        @info("Successfully `import`ed package");
        """
    before_message = "Attempting to `import` the package"
    success_message = "Successfully `import`ed the package"
    success_return_1 = true
    success_return_2 = ""
    failure_message = "Was not able to successfully `import` the package"
    failure_return_1 = false
    failure_return_2 = string("I was not able to load the package ",
                              "(i.e. `import $(pkg)` failed). ",
                              "See the CI logs for details.")
    return _run_pkg_commands(working_directory,
                             pkg,
                             version;
                             code = code,
                             before_message = before_message,
                             success_message = success_message,
                             success_return_1 = success_return_1,
                             success_return_2 = success_return_2,
                             failure_message = failure_message,
                             failure_return_1 = failure_return_1,
                             failure_return_2 = failure_return_2)
end

function _run_pkg_commands(working_directory::String,
                           pkg::String,
                           version::VersionNumber;
                           code,
                           before_message,
                           success_message,
                           success_return_1,
                           success_return_2,
                           failure_message,
                           failure_return_1,
                           failure_return_2)
    original_directory = pwd()
    tmp_dir_1 = mktempdir()
    tmp_dir_2 = mktempdir()
    atexit(() -> rm(tmp_dir_1; force = true, recursive = true))
    atexit(() -> rm(tmp_dir_2; force = true, recursive = true))
    cd(tmp_dir_1)
    # We need to be careful with what environment variables we pass to the child
    # process. For example, we don't want to pass an environment variable containing
    # our GitHub token to the child process. Because if the Julia package that we are
    # testing has malicious code in its __init__() function, it could try to steal
    # our token. So we only pass these environment variables:
    # 1. HTTP_PROXY. If it's set, it is delegated to the child process.
    # 2. HTTPS_PROXY. If it's set, it is delegated to the child process.
    # 3. JULIA_DEPOT_PATH. We set JULIA_DEPOT_PATH to the temporary directory that
    #    we created. This is because we don't want the child process using our
    #    real Julia depot. So we set up a fake depot for the child process to use.
    # 4. JULIA_PKG_SERVER. If it's set, it is delegated to the child process.
    # 5. JULIA_REGISTRYCI_AUTOMERGE. We set JULIA_REGISTRYCI_AUTOMERGE to "true".
    # 6. PATH. If we don't pass PATH, things break. And PATH should not contain any
    #    sensitive information.
    # 7. PYTHON. We set PYTHON to the empty string. This forces any packages that use
    #    PyCall to install their own version of Python instead of using the system
    #    Python.
    # 8. R_HOME. We set R_HOME to "*".
    # 9. HOME. Lots of things need HOME.

    env = Dict(
        "JULIA_DEPOT_PATH" => tmp_dir_2,
        "JULIA_REGISTRYCI_AUTOMERGE" => "true",
        "PYTHON" => "",
        "R_HOME" => "*",
    )
    for k in ("HOME", "PATH", "HTTP_PROXY", "HTTPS_PROXY", "JULIA_PKG_SERVER")
        if haskey(ENV, k)
            env[k] = ENV[k]
        end
    end

    cmd = Cmd(`$(Base.julia_cmd()) -e $(code)`; env=env)

    # GUI toolkits may need a display just to load the package
    xvfb = Sys.which("xvfb-run")
    @info("xvfb: ", xvfb)
    if xvfb !== nothing
        pushfirst!(cmd.exec, "-a")
        pushfirst!(cmd.exec, xvfb)
    end
    @info(before_message)
    cmd_ran_successfully = success(pipeline(cmd, stdout=stdout, stderr=stderr))
    cd(original_directory)

    try
        chmod(tmp_dir_1, 0o700, recursive = true)
    catch
    end
    rm(tmp_dir_1; force = true, recursive = true)

    try
        chmod(tmp_dir_2, 0o700, recursive = true)
    catch
    end
    rm(tmp_dir_2; force = true, recursive = true)

    if cmd_ran_successfully
        @info(success_message)
        return success_return_1, success_return_2
    else
        @error(failure_message)
        return failure_return_1, failure_return_2
    end
end

url_has_correct_ending(url, pkg) = endswith(url, "/$(pkg).jl.git")
