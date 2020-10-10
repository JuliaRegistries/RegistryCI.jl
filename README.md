# RegistryCI.jl

[![Build Status](https://travis-ci.com/JuliaRegistries/RegistryCI.jl.svg?branch=master)](https://travis-ci.com/JuliaRegistries/RegistryCI.jl/branches)
[![Codecov](https://codecov.io/gh/JuliaRegistries/RegistryCI.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/JuliaRegistries/RegistryCI.jl/branch/master)

RegistryCI provides continuous integration (CI) tools, including automated testing and automatic merging (automerge) of pull requests.

The [General](https://github.com/JuliaRegistries/General) registry uses RegistryCI.

You can also use RegistryCI for your own Julia package registry.

## Automatic merging guidelines

These guidelines are intended not as requirements for packages but as very conservative guidelines, which, if your new package or new version of a package meets them, it may be automatically merged.

Note that commenting on a pull request will automatically disable automerging on that pull request. Therefore, if you want to leave a comment on a pull request but you still want that pull request to be automerged, please include the text `[noblock]` in your comment.

### New package

1. Normal capitalization

    The package name should match `r"^[A-Z]\w*[a-z]\w*[0-9]?$"`, i.e. start with a capital letter, contain ASCII alphanumerics only, contain at 1 lowercase letter.

2. Not too short

    At least five letters. *You can register names shorter than this, but doing so requires someone to approve.*

3. Standard initial version number: one of `0.0.1`, `0.1.0`, `1.0.0`.

4. Package name is not too similar to an existing package's name.

    We currently test this via three checks:
    
    - requiring that the [Damerau–Levenshtein distance](https://en.wikipedia.org/wiki/Damerau%E2%80%93Levenshtein_distance) between the package name and the name of any existing package is at least 3
    - requiring that the Damerau–Levenshtein distance between the lowercased version of a package name and the lowercased version of the name of any existing package is at least 2
    - requiring that a visual distance from [VisualStringDistances.jl](https://github.com/ericphanson/VisualStringDistances.jl) between the package name and any existing package exceeds a certain a hand-chosen threshold.

    These tolerances and methodology are subject to change in order to improve the process.

    To test yourself that a tentative package name, say `MyPackage` meets these checks, you can use the following code (after adding the RegistryCI package to your Julia environment):

    ```julia
    using RegistryCI
    using RegistryCI.AutoMerge
    all_pkg_names = AutoMerge.get_all_non_jll_package_names(path_to_registry)
    AutoMerge.meets_distance_check("MyPackage", all_pkg_names)
    ```

    where `path_to_registry` is a path to the folder containing the registry of interest. For the General Julia registry, usually `path_to_registry = joinpath(DEPOT_PATH[1], "registries", "General")` if you haven't changed your `DEPOT_PATH`. This will return a boolean, indicating whether or not your tentative package name passed the check, as well as a string, indicating what the problem is in the event the check did not pass.


Reminder: these automerge guidelines are deliberately conservative: it is very possible for a perfectly good name to not pass the automatic checks and require manually merging. They simply exist to provide a fast path so that manual review is not required for every new package.

### New version of an existing package

1. Sequential version number

    If the last version was `1.2.3` then the next can be `1.2.4`, `1.3.0` or `2.0.0`.

2. [Compat entries](https://julialang.github.io/Pkg.jl/v1/compatibility/) for all dependencies.

    - all `[deps]` should also have `[compat]` entries (and Julia itself)
    - `[compat]` entries should have upper bounds

    Compat entries are not required for standard libraries. For the time being, compat entries are not required for JLL dependencies because they often have non-standard version numbering schemes; however, this may change in the future.

3. Version can be installed

    Given the proposed changes to the registry, can we resolve and install the new version of the package?

4. Version can be loaded

    Once it's been installed (and built?), can we load the code?

## RegistryCI.jl integration tests

For instructions on how to run the RegistryCI.jl integration tests on your local machine, see [`INTEGRATION_TESTS.md`](INTEGRATION_TESTS.md).

## TeamCity support

There is support also for TeamCity, but it does not work out-of the box, it requires Pull Request build feature to be added, and passing few build variables as environment variables.

To make it work in TeamCity, see [this Kotlin DSL snippet](teamcity_settings.kts) and put following parts into your DSL/add them in GUI.

## Acknowledgements

Dilum Aluthge would like to acknowledge the following:
- This work was supported in part by National Institutes of Health grants U54GM115677, R01LM011963, and R25MH116440. The content is solely the responsibility of the authors and does not necessarily represent the official views of the National Institutes of Health.
