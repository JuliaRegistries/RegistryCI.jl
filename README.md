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

    The package name should match `r"^[A-Z]\w*[a-z][0-9]?$"`, i.e. start with a capital letter, contain ASCII alphanumerics only, end in lowercase.

2. Not too short

    At least five letters. *You can register names shorter than this, but doing so requires someone to approve.*

3. Standard initial version number: one of `0.0.1`, `0.1.0`, `1.0.0`.

4. Repo URL ends with `/$name.jl.git` where `name` is the package name.

### New version of an existing package

1. Sequential version number

    If the last version was `1.2.3` then the next can be `1.2.4`, `1.3.0` or `2.0.0`.

2. [Compat entries](https://julialang.github.io/Pkg.jl/v1/compatibility/) for all dependencies.

    - all `[deps]` should also have `[compat]` entries (and Julia itself)
    - `[compat]` entries should have upper bounds

    Compat entries are not required for standard libraries.

3. Version can be installed

    Given the proposed changes to the registry, can we resolve and install the new version of the package?

4. Version can be loaded

    Once it's been installed (and built?), can we load the code?

## Acknowledgements

Dilum Aluthge would like to acknowledge the following:
- This work was supported in part by National Institutes of Health grants U54GM115677, R01LM011963, and R25MH116440. The content is solely the responsibility of the authors and does not necessarily represent the official views of the National Institutes of Health.
