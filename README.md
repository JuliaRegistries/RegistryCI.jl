# RegistryCI.jl

| Category          | Status                                                                                                             |
| ----------------- | ------------------------------------------------------------------------------------------------------------------ |
| Unit Tests        | [![Continuous Integration (Unit Tests)][ci-unit-img]][ci-unit-url]                                                 |
| Integration Tests | [![Continuous Integration (Integration Tests)][ci-integration-img]][ci-integration-url]                            |
| Documentation     | [![Documentation (stable)][docs-stable-img]][docs-stable-url] [![Documentation (dev)][docs-dev-img]][docs-dev-url] |
| Code Coverage     | [![Code Coverage][codecov-img]][codecov-url]                                                                       |
| Style Guide       | [![Style Guide][bluestyle-img]][bluestyle-url]                                                                     |

[docs-stable-img]: https://img.shields.io/badge/docs-stable-blue.svg "Documentation (stable)"
[docs-stable-url]: https://JuliaRegistries.github.io/RegistryCI.jl/stable
[docs-dev-img]: https://img.shields.io/badge/docs-dev-blue.svg "Documentation (dev)"
[docs-dev-url]: https://JuliaRegistries.github.io/RegistryCI.jl/dev
[ci-unit-img]: https://github.com/JuliaRegistries/RegistryCI.jl/workflows/CI%20(unit%20tests)/badge.svg?branch=master "Continuous Integration (Unit Tests)"
[ci-unit-url]: https://github.com/JuliaRegistries/RegistryCI.jl/actions?query=workflow%3A%22CI+%28unit+tests%29%22
[ci-integration-img]: https://github.com/JuliaRegistries/RegistryCI.jl/workflows/CI%20(integration%20tests)/badge.svg?branch=master "Continuous Integration (Integration Tests)"
[ci-integration-url]: https://github.com/JuliaRegistries/RegistryCI.jl/actions?query=workflow%3A%22CI+%28integration+tests%29%22
[codecov-img]: https://codecov.io/gh/JuliaRegistries/RegistryCI.jl/branch/master/graph/badge.svg "Code Coverage"
[codecov-url]: https://codecov.io/gh/JuliaRegistries/RegistryCI.jl/branch/master
[bluestyle-img]: https://img.shields.io/badge/code%20style-blue-4495d1.svg "Blue Style"
[bluestyle-url]: https://github.com/invenia/BlueStyle

This repository contains two Julia packages:

- **RegistryCI.jl** - Registry consistency testing tools for Julia package registries
- **AutoMerge.jl** - Automatic merging (automerge) of pull requests and TagBot functionality for Julia package registries

Starting with RegistryCI v11.0, the automerge and TagBot functionality has been moved to the separate AutoMerge.jl package. RegistryCI.jl now focuses solely on registry testing.

Please see the [documentation](https://JuliaRegistries.github.io/RegistryCI.jl/stable) for both packages.
