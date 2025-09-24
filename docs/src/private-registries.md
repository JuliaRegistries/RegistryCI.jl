```@meta
CurrentModule = RegistryCI
```

# Using RegistryCI on your own package registry

In order to create and maintain a custom Julia registry, you can use [LocalRegistry.jl](https://github.com/GunnarFarneback/LocalRegistry.jl).
After you have the registry configured, you can setup CI using RegistryCI by following how it is used in the
[General registry](https://github.com/JuliaRegistries/General).

## Basic configuration

You will first need to copy the `.ci` folder in the root of the General registry to the root of your own registry. This folder contains some resources required for the RegistryCI package to work and update itself. If you do not need AutoMerge support, there is no need to copy the
`stopwatch.jl` file in the `.ci` folder.

Next, you will need to copy the `registry-consistency-ci.yml` and `update_manifest.yml` workflow files.

The `registry-consistency-ci.yml` file should be modified as follows if you have packages in your registry that depend on packages in the General registry.
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
If Julia pkg server is available and recognized, then the Julia Pkg will try to download registry from it. This can be useful to reduce the
unnecessary network traffic, for example, if you host a private pkg server in your local network(e.g., enterprise network with firewall)
and properly set up the environment variable `JULIA_PKG_SERVER`, then the network traffic doesn't need to pass through the proxy to GitHub.

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
using AutoMerge
using AutoMerge: AutoMergeConfiguration
using Dates
config = AutoMergeConfiguration(; config_settings...)
AutoMerge.run(config)
```
where `config_settings` must set all of the required fields from [`AutoMergeConfiguration`](@ref) (and optionally the settings with default values too). One can refer to [`AutoMerge.GENERAL_AUTOMERGE_CONFIG`](@ref) to see the settings that General uses. If one wants to opt-in to following the same rules as General (which may change in non-breaking releases of AutoMerge.jl), one can directly set `config = AutoMerge.GENERAL_AUTOMERGE_CONFIG`, and pass keyword arguments to `run` to override specific values.

Most importantly, the following configuration settings must be updated for your registry:
```
registry = "MyOrg/MyRegistry",
authorized_authors = String["TrustedUser"],
```

You will also have to make the following change in `.ci/stopwatch.jl`

```diff
- registry = GitHub.Repo("JuliaRegistries/General")
+ registry = GitHub.Repo("MyOrg/MyRegistry")
```

## Note regarding private registries

In the case of a private registry, you might get permission errors when executing the `instantiate.sh` script.
In that case you will also have to add the following
```diff
  - run: chmod 400 .ci/Project.toml
  - run: chmod 400 .ci/Manifest.toml
+ - run: chmod +x .ci/instantiate.sh
```
in `registry-consistency-ci.yml` and also `TagBotTriggers.yml` and `automerge.yml` (in which the above appears twice) files if those features are used.

## Author approval workflow support

Some guidelines allow the person invoking registration (typically the package author) to "approve" AutoMerge even if the guideline is not passing. This is facilitated by a labelling workflow `author_approval.yml` that must run on the registry in order to translate author-approval comments into labels that AutoMerge can use. The [General registry's workflows](https://github.com/JuliaRegistries/General/tree/master/.github/workflows) should once again be used as an example.
