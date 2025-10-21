# Migration Guide: Upgrading to AutoMerge v1

AutoMerge v1 replaces the single `AutoMerge.run()` function with two separate entrypoints with different privilege levels. This guide will help you migrate from the pre-v1 API to the new v1 API.

!!! note "AutoMerge is now a standalone package"
    Prior to v1, AutoMerge was a submodule of RegistryCI.jl. As of v1, AutoMerge has been split into its own independent package with its own versioning and release cycle.

## Key Changes in v1

1. **Split Entrypoints**: The single `AutoMerge.run()` function has been replaced with two separate functions:
   - `AutoMerge.check_pr()`: Validates pull requests (runs untrusted code, minimal permissions)
   - `AutoMerge.merge_prs()`: Merges approved pull requests (elevated permissions, no untrusted code)

2. **Configuration Structs**: Keyword arguments are now organized into three configuration structs:
   - `RegistryConfiguration`: Shared registry settings
   - `CheckPRConfiguration`: PR validation settings
   - `MergePRsConfiguration`: PR merging settings

3. **Environment Variables**: Token configuration has changed:
   - Pre-v1: Single `GITHUB_TOKEN` or custom token variable
   - v1: Two separate tokens with different permission levels:
     - `AUTOMERGE_GITHUB_TOKEN`: For PR checking (read access + commit status)
     - `AUTOMERGE_MERGE_TOKEN`: For PR merging (write access)

## Migration Steps

### Step 1: Update Your Configuration

The recommended approach is to use TOML configuration files. You can create a configuration file for your registry based on the General registry configuration:

```julia
using AutoMerge

# Create a template configuration file
config = AutoMerge.general_registry_config()
AutoMerge.write_config("MyRegistry.AutoMerge.toml", config)
```

Then customize the TOML file for your registry's needs. See the [Configuration](configuration.md) page for details on all available configuration options for:
- [`RegistryConfiguration`](configuration.md#AutoMerge.RegistryConfiguration) - shared registry settings
- [`CheckPRConfiguration`](configuration.md#AutoMerge.CheckPRConfiguration) - PR validation settings
- [`MergePRsConfiguration`](configuration.md#AutoMerge.MergePRsConfiguration) - PR merging settings

!!! warning "Time Period Changes"
    In v1, time periods are now specified in **minutes** (`Minute` type) instead of arbitrary `Period` types. Field names have been updated from `*_period` to `*_minutes`. For example:
    - `new_package_waiting_period = Day(3)` becomes `new_package_waiting_minutes = Minute(Day(3))`
    - `new_version_waiting_period = Minute(10)` becomes `new_version_waiting_minutes = Minute(10)`

### Step 2: Update Environment Variables for Separate Jobs

**Important:** The two entrypoints should run in **separate GitHub Actions jobs** with different environment variables to ensure tokens are only exposed to the operations that need them.

- **PR Check Job**: Only needs `AUTOMERGE_GITHUB_TOKEN` (read access + commit status)
- **PR Merge Job**: Needs both `AUTOMERGE_GITHUB_TOKEN` and `AUTOMERGE_MERGE_TOKEN` (write access)

This separation ensures that:
1. The PR checking job (which runs untrusted code) never has access to the merge token
2. The principle of least privilege is maintained

!!! note "Token Permissions"
    - `AUTOMERGE_GITHUB_TOKEN` needs `repo:status` permission and read access to PRs
    - `AUTOMERGE_MERGE_TOKEN` needs write access to the repository

    For most registries, you can use `secrets.GITHUB_TOKEN` for `AUTOMERGE_GITHUB_TOKEN` and a more privileged token (like `secrets.TAGBOT_TOKEN`) for `AUTOMERGE_MERGE_TOKEN`.

### Step 3: Update GitHub Workflow Files

Create separate jobs for PR checking and PR merging:

**After (v1):**
```yaml
jobs:
  AutoMerge-PR-Check:
    runs-on: ubuntu-latest
    steps:
      # ... setup steps ...
      - name: AutoMerge PR Check
        env:
          AUTOMERGE_GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          config = AutoMerge.read_config("MyRegistry.AutoMerge.toml")
          AutoMerge.check_pr(config.registry_config, config.check_pr_config)
        shell: julia --color=yes --project=.ci/ {0}

  AutoMerge-PR-Merge:
    runs-on: ubuntu-latest
    steps:
      # ... setup steps ...
      - name: AutoMerge PR Merge
        env:
          AUTOMERGE_GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          AUTOMERGE_MERGE_TOKEN: ${{ secrets.TAGBOT_TOKEN }}
        run: |
          config = AutoMerge.read_config("MyRegistry.AutoMerge.toml")
          AutoMerge.merge_prs(config.registry_config, config.merge_prs_config)
        shell: julia --color=yes --project=.ci/ {0}
```

See the [Configuration](configuration.md#ci-workflow-integration) page for a complete example workflow file with proper job separation and conditional execution.
