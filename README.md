# RegistryCI.jl

[![Continuous Integration (Unit Tests)][ci-unit-img]][ci-unit-url]
[![Continuous Integration (Integration Tests)][ci-integration-img]][ci-integration-url]
[![Code Coverage][codecov-img]][codecov-url]
[![Bors][bors-img]][bors-url]

[ci-unit-img]: https://github.com/JuliaRegistries/RegistryCI.jl/workflows/CI%20(unit%20tests)/badge.svg?branch=master "Continuous Integration (Unit Tests)"
[ci-unit-url]: https://github.com/JuliaRegistries/RegistryCI.jl/actions?query=workflow%3A%22CI+%28unit+tests%29%22
[ci-integration-img]: https://github.com/JuliaRegistries/RegistryCI.jl/workflows/CI%20(integration%20tests)/badge.svg?branch=master "Continuous Integration (Integration Tests)"
[ci-integration-url]: https://github.com/JuliaRegistries/RegistryCI.jl/actions?query=workflow%3A%22CI+%28integration+tests%29%22
[codecov-img]: https://codecov.io/gh/JuliaRegistries/RegistryCI.jl/branch/master/graph/badge.svg "Code Coverage"
[codecov-url]: https://codecov.io/gh/JuliaRegistries/RegistryCI.jl/branch/master
[bors-img]: https://bors.tech/images/badge_small.svg "Bors"
[bors-url]: https://app.bors.tech/repositories/25657

RegistryCI provides continuous integration (CI) tools, including automated testing and automatic merging (automerge) of pull requests.

The [General](https://github.com/JuliaRegistries/General) registry uses RegistryCI.

You can also use RegistryCI for your own Julia package registry.

## Automatic merging guidelines

For the list of automatic merging guidelines, please see the [General registry README](https://github.com/JuliaRegistries/General/blob/master/README.md#automatic-merging-of-pull-requests).

## RegistryCI.jl integration tests

For instructions on how to run the RegistryCI.jl integration tests on your local machine, see [`INTEGRATION_TESTS.md`](INTEGRATION_TESTS.md).

## Acknowledgements

Dilum Aluthge would like to acknowledge the following:
- This work was supported in part by National Institutes of Health grants U54GM115677, R01LM011963, and R25MH116440. The content is solely the responsibility of the authors and does not necessarily represent the official views of the National Institutes of Health.
