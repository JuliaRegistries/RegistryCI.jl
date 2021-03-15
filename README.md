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

## Using RegistryCI on your own package registry

In order to create and maintain a custom Julia registry, you can use [LocalRegistry.jl](https://github.com/GunnarFarneback/LocalRegistry.jl).
After you have the registry configured, you can setup CI using RegistryCI by following how it is used in the
[General registry](https://github.com/JuliaRegistries/General).

### Basic configuration

You will first need to copy the `.ci` folder in the root of the General registry to the root of your own registry. This folder contains some resources required for the RegistryCI package to work and update itself.

Next, you will need to copy the `ci.yml` and `remember_to_update_registryci.yml` workflow files.

The `ci.yml` file should be modified as follows if you have packages in your registry that depend on packages in the General registry.
If the packages in your registry depend on packages in other registries, they should also be added to `registry_deps`
```diff
- run: julia --project=.ci/ --color=yes -e 'import RegistryCI; RegistryCI.test()'

+ run: julia --project=.ci/ --color=yes -e 'import RegistryCI; RegistryCI.test(registry_deps=["https://github.com/JuliaRegistries/General"])'
```

In the `remember_to_update_registryci.yml` file, the `"${{ github.repository }}" == "JuliaRegistries/General"` condition should be removed in order for the auto-update of RegistryCI to be enabled.
```diff
- run: julia -e 'include(".ci/remember_to_update_registryci.jl"); "${{ github.repository }}" == "JuliaRegistries/General" && RememberToUpdateRegistryCI.main(".ci"; registry = "${{ github.repository }}", cc_usernames = String[], old_julia_version = v"1.5.3")'

+ run: julia -e 'include(".ci/remember_to_update_registryci.jl"); RememberToUpdateRegistryCI.main(".ci"; registry = "${{ github.repository }}", cc_usernames = String[], old_julia_version = v"1.5.3")'
```

The self-update mechanism mentioned above uses a `TAGBOT_TOKEN` secret in order to create a pull request with the update.
This secret is a [personal access token](https://help.github.com/en/github/authenticating-to-github/creating-a-personal-access-token-for-the-command-line#creating-a-token) which must have the `repo` scope enabled.
To create the repository secret follow the instructions [here](https://help.github.com/en/actions/automating-your-workflow-with-github-actions/creating-and-using-encrypted-secrets#creating-encrypted-secrets). Use the name `TAGBOT_TOKEN` and the new PAT as the value.

### TagBot triggers

If you want to use TagBot in the packages that you register in your registry, you need to also copy the `TagBotTriggers.yml` file.
That workflow file also needs the `TAGBOT_TOKEN` secret mentioned above.
In the `TagBot.yml` workflows of the registered packages you will also need to add the `registry` input as stated in the [TagBot readme](https://github.com/JuliaRegistries/TagBot#custom-registries)

```
with:
  token: ${{ secrets.GITHUB_TOKEN }}
  registry: MyOrg/MyRegistry
```

### AutoMerge support

In order to enable automerge support, you will also have to copy the `automerge.yml` file and change the `AutoMerge` invocation appropriately

```julia
using RegistryCI
using Dates
    RegistryCI.AutoMerge.run(
    merge_new_packages = ENV["MERGE_NEW_PACKAGES"] == "true",
    merge_new_versions = ENV["MERGE_NEW_VERSIONS"] == "true",
    new_package_waiting_period = Day(3),
    new_jll_package_waiting_period = Minute(20),
    new_version_waiting_period = Minute(10),
    new_jll_version_waiting_period = Minute(10),
    registry = "JuliaRegistries/General",
    tagbot_enabled = true,
    authorized_authors = String["JuliaRegistrator"],
    authorized_authors_special_jll_exceptions = String[""],
    suggest_onepointzero = false,
    additional_statuses = String[],
    additional_check_runs = String[],
    check_license = true,
    public_registries = String["https://github.com/HolyLab/HolyLabRegistry"],
)
```
Most importantly, the following should be changed
```
registry = "MyOrg/MyRegistry",
authorized_authors = String["TrustedUser"],
```

## Acknowledgements

Dilum Aluthge would like to acknowledge the following:
- This work was supported in part by National Institutes of Health grants U54GM115677, R01LM011963, and R25MH116440. The content is solely the responsibility of the authors and does not necessarily represent the official views of the National Institutes of Health.
