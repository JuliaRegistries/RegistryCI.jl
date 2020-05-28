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
        message = string("The following dependencies ",
                         "do not have a ",
                         "compat entry that has ",
                         "an upper bound: ",
                         join(bad_dependencies,
                              ", "),
                         ". You may find ",
                         "[CompatHelper]",
                         "(https://github.com/bcbi/CompatHelper.jl) ",
                         "helpful for keeping ",
                         "your compat entries ",
                         "up-to-date.",
                         "Note: If your package works for the current version `x.y.z` of a dependency `foo`, ",
                         "then a compat entry `foo = x.y.z` implies a compatibility upper bound ",
                         "for packages following semver. You can additionally include earlier versions ",
                         "your package is compatible with. ",
                         "See https://julialang.github.io/Pkg.jl/v1/compatibility/ for details.")
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

function meets_normal_capitalization(pkg)
    meets_this_guideline = occursin(r"^[A-Z]\w*[a-z]\w*[0-9]?$", pkg)
    if meets_this_guideline
        return true, ""
    else
        return false, "Name does not meet all of the following: starts with an uppercase letter, ASCII alphanumerics only, not all letters are uppercase.**"
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

function meets_version_can_be_pkg_added(working_directory::String,
                                        pkg::String,
                                        version::VersionNumber;
                                        registry_deps::Vector{<:AbstractString} = String[])
    pkg_add_command = _generate_pkg_add_command(pkg,
                                                version)
    _registry_deps = convert(Vector{String}, registry_deps)
    code = """
        import Pkg;
        Pkg.pkg"add HTTP";
        using HTTP;
        is_valid_url(str::AbstractString) = !isempty(HTTP.URI(str).scheme) && isvalid(HTTP.URI(str));
        Pkg.Registry.add(Pkg.RegistrySpec(path=\"$(working_directory)\"));
        _registry_deps = $(_registry_deps);
        for regdep in _registry_deps
            if is_valid_url(regdep)
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
    code = """
        import Pkg;
        Pkg.pkg"add HTTP";
        using HTTP;
        is_valid_url(str::AbstractString) = !isempty(HTTP.URI(str).scheme) && isvalid(HTTP.URI(str));
        Pkg.Registry.add(Pkg.RegistrySpec(path=\"$(working_directory)\"));
        _registry_deps = $(_registry_deps);
        for regdep in _registry_deps
            if is_valid_url(regdep)
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
    # our token. So we only pass five environment variables:
    # 1. PATH. If we don't pass PATH, things break. And PATH should not contain any
    #    sensitive information.
    # 2. PYTHON. We set PYTHON to the empty string. This forces any packages that use
    #    PyCall to install their own version of Python instead of using the system
    #    Python.
    # 3. JULIA_DEPOT_PATH. We set JULIA_DEPOT_PATH to the temporary directory that
    #    we created. This is because we don't want the child process using our
    #    real Julia depot. So we set up a fake depot for the child process to use.
    # 4. R_HOME. We set R_HOME to "*".
    # 5. JULIA_PKG_SERVER. If it's set, it is delegated to the child process.
    env = Dict("PATH" => ENV["PATH"],
               "PYTHON" => "",
               "JULIA_DEPOT_PATH" => tmp_dir_2,
               "R_HOME" => "*",
    )
    if haskey(ENV, "JULIA_PKG_SERVER")
        env["JULIA_PKG_SERVER"] = ENV["JULIA_PKG_SERVER"]
    end
    if haskey(ENV, "HTTPS_PROXY")
        env["HTTPS_PROXY"] = ENV["HTTPS_PROXY"]
    end
    if haskey(ENV, "HTTP_PROXY")
        env["HTTP_PROXY"] = ENV["HTTP_PROXY"]
    end
    cmd = Cmd(`$(Base.julia_cmd()) -e $(code)`;
              env = env)
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
    rm(tmp_dir_1; force = true, recursive = true)
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
