# RegistryCI.jl

[![Build Status](https://travis-ci.com/JuliaRegistries/RegistryCI.jl.svg?branch=master)](https://travis-ci.com/JuliaRegistries/RegistryCI.jl/branches)
[![Codecov](https://codecov.io/gh/JuliaRegistries/RegistryCI.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/JuliaRegistries/RegistryCI.jl/branch/master)

RegistryCI provides continuous integration (CI) tools, including automated testing and automatic merging (automerge) of pull requests.

The [General](https://github.com/JuliaRegistries/General) registry uses RegistryCI.

You can also use RegistryCI for your own Julia package registry.

## Automatic merging guidelines

For the list of automatic merging guidelines, please see the [General registry README](https://github.com/JuliaRegistries/General/blob/master/README.md#automatic-merging-of-pull-requests).

## RegistryCI.jl integration tests

For instructions on how to run the RegistryCI.jl integration tests on your local machine, see [`INTEGRATION_TESTS.md`](INTEGRATION_TESTS.md).

## TeamCity support

There is support also for TeamCity, but it does not work out-of the box, it requires Pull Request build feature to be added, and passing few build variables as environment variables.

To make it work in TeamCity, see [this Kotlin DSL snippet](teamcity_settings.kts) and put following parts into your DSL/add them in GUI.

## Acknowledgements

Dilum Aluthge would like to acknowledge the following:
- This work was supported in part by National Institutes of Health grants U54GM115677, R01LM011963, and R25MH116440. The content is solely the responsibility of the authors and does not necessarily represent the official views of the National Institutes of Health.
