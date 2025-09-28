# Configuration

## AutoMerge.jl

```@meta
CurrentModule = AutoMerge
```

AutoMerge.jl provides automatic merging functionality for Julia package registries. The package has been designed with security in mind, separating functionality into two distinct entrypoints with different privilege levels:

- **`check_pr`**: Validates pull requests by running untrusted code but requires only minimal GitHub permissions (commit status updates and PR read access)
- **`merge_prs`**: Merges approved pull requests but requires elevated GitHub permissions (repository write access) and does not run untrusted code

### Configuration Overview

AutoMerge uses three separate configuration objects to maintain clear separation of concerns:

```@docs
AutoMerge.RegistryConfiguration
AutoMerge.CheckPRConfiguration
AutoMerge.MergePRsConfiguration
```

The `AutoMerge.AutoMergeConfiguration` combines all 3 into one object:

```@docs
AutoMerge.AutoMergeConfiguration
```

### General Registry Configuration

The General registry provides a pre-configured setup that can be used as a reference:

```@docs
AutoMerge.general_registry_config
```

### Configuration Management

```@docs
AutoMerge.read_config
AutoMerge.write_config
```

### Basic Usage

#### Using the General Registry Configuration

For the General registry, you can use the pre-configured settings:

```julia
using AutoMerge

# Get the General registry configuration
config = AutoMerge.general_registry_config()

# For PR checking (runs untrusted code, minimal permissions)
AutoMerge.check_pr(config.registry_config, config.check_pr_config)

# For PR merging (elevated permissions, no untrusted code)
AutoMerge.merge_prs(config.registry_config, config.merge_prs_config)
```

#### Creating a Custom Configuration

For a custom registry, create a TOML configuration file. This can be based on the one used by General:

```@eval
import Markdown
str ="```toml\n" * 
    read("../../AutoMerge.jl/configs/General.AutoMerge.toml", String) *
    "\n```"
@eval Markdown.@md_str($str)
```

We suggest the naming convention `$Registry.AutoMerge.toml`.

Then use the configuration:

```julia
# Load configuration
config = AutoMerge.read_config("MyRegistry.AutoMerge.toml")

# Use in CI workflows
AutoMerge.check_pr(config.registry_config, config.check_pr_config)
AutoMerge.merge_prs(config.registry_config, config.merge_prs_config)
```

### Security Considerations

#### GitHub Token Configuration

AutoMerge uses configurable GitHub tokens with different permission requirements:

- **PR Checking Token** (`commit_status_token_name`): Requires `repo:status` permission to set commit statuses and read access to PRs. Does not need write access to the repository.
- **Merge Token** (`merge_token_name`): Requires write access to the repository to merge PRs.

By default, both tokens use the environment variable `AUTOMERGE_GITHUB_TOKEN`, but they can be configured to use different tokens:

```julia
# Use different tokens for different operations
check_pr_config = AutoMerge.CheckPRConfiguration(
    commit_status_token_name = "AUTOMERGE_CHECK_TOKEN",  # Token with repo:status permission
    # ... other settings
)

merge_prs_config = AutoMerge.MergePRsConfiguration(
    merge_token_name = "AUTOMERGE_MERGE_TOKEN",  # Token with write permission
    # ... other settings
)
```

!!! warning "Token Security"
    The `commit_status_token_name` and `merge_token_name` fields store the **names** of environment variables, not the actual token values. Never put actual GitHub tokens in configuration files!

#### Separation of Privileges

The two-entrypoint design ensures that:

1. **PR checking** (`check_pr`) runs untrusted package code during validation but only has minimal GitHub permissions
2. **PR merging** (`merge_prs`) has elevated GitHub permissions but never runs untrusted code

This separation follows the principle of least privilege and reduces the attack surface.

### CI Workflow Integration

#### GitHub Actions Example

```@eval
import Markdown
str ="```yaml\n" * 
    read("../../example_github_workflow_files/automerge.yml", String) *
    "\n```"
@eval Markdown.@md_str($str)
```
