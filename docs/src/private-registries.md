```@meta
CurrentModule = RegistryCI
```

# Using RegistryCI on your own package registry

In order to create and maintain a custom Julia registry, you can use [LocalRegistry.jl](https://github.com/GunnarFarneback/LocalRegistry.jl).
After you have the registry configured, you can setup CI using RegistryCI by following how it is used in the
[General registry](https://github.com/JuliaRegistries/General).

## Basic configuration

You will first need to copy the `.ci` folder in the root of the General registry to the root of your own registry. This folder contains some resources required for the RegistryCI package to work and update itself.

Next, you will need to copy the `ci.yml` and `update_manifest.yml` workflow files.

The `ci.yml` file should be modified as follows if you have packages in your registry that depend on packages in the General registry.
If the packages in your registry depend on packages in other registries, they should also be added to `registry_deps`
```diff
- run: julia --project=.ci/ --color=yes -e 'import RegistryCI; RegistryCI.test()'

+ run: julia --project=.ci/ --color=yes -e 'import RegistryCI; RegistryCI.test(registry_deps=["https://github.com/JuliaRegistries/General"])'
```

You can optionally use the registry name instead of the URL:
```diff
- run: julia --project=.ci/ --color=yes -e 'import RegistryCI; RegistryCI.test()'
+ run: julia --project=.ci/ --color=yes -e 'import RegistryCI; RegistryCI.test(registry_deps=["General"])'
```
This way Julia Pkg will download registry from Julia pkg server. If you host a private pkg server in your local network(e.g., enterprise network with firewall) and properly
set up the environment variable `JULIA_PKG_SERVER`, then the network traffic doesn't need to pass through the proxy.

!!! warning
  Registry fetched from Julia pkg server currently has some observable latency(e.g., hours). Check [here](https://github.com/JuliaRegistries/General/issues/16777) for more information.

The self-update mechanism mentioned above uses a `TAGBOT_TOKEN` secret in order to create a pull request with the update.
This secret is a [personal access token](https://help.github.com/en/github/authenticating-to-github/creating-a-personal-access-token-for-the-command-line#creating-a-token) which must have the `repo` scope enabled.
To create the repository secret follow the instructions [here](https://help.github.com/en/actions/automating-your-workflow-with-github-actions/creating-and-using-encrypted-secrets#creating-encrypted-secrets). Use the name `TAGBOT_TOKEN` and the new PAT as the value.

## TagBot triggers

If you want to use TagBot in the packages that you register in your registry, you need to also copy the `TagBotTriggers.yml` file.
That workflow file also needs the `TAGBOT_TOKEN` secret mentioned above.
In the `TagBot.yml` workflows of the registered packages you will also need to add the `registry` input as stated in the [TagBot readme](https://github.com/JuliaRegistries/TagBot#custom-registries)

```
with:
  token: ${{ secrets.GITHUB_TOKEN }}
  registry: MyOrg/MyRegistry
```

## AutoMerge support

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
    registry = "MyOrg/MyRegistry",
    tagbot_enabled = true,
    authorized_authors = String["TrustedUser"],
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
