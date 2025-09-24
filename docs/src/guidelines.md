```@meta
CurrentModule = RegistryCI
```

# Automatic merging guidelines

These are the guidelines that a pull request must pass in order to be automatically merged.

All of those guidelines are enabled on the General registry (see [`AutoMerge.GENERAL_AUTOMERGE_CONFIG`](@ref) for the precise configuration of AutoMerge used by General).

For other registries, some of these guidelines can be disabled.

## New packages

```@eval
import RegistryCI
import AutoMerge
import Markdown

function guidelines_to_markdown_output(guidelines_function::Function)
    guidelines = guidelines_function(
        registration_type;
        check_license = true,
        check_breaking_explanation = true,
        this_is_jll_package = false,
        this_pr_can_use_special_jll_exceptions = false,
        use_distance_check = false,
        package_author_approved = false,
    )
    filter!(x -> !(x[1] isa Symbol), guidelines)
    filter!(x -> !(x[1].docs isa Nothing), guidelines)
    docs = [rstrip(x[1].docs) for x in guidelines]
    output_string = join(string.(collect(1:length(docs)), Ref(". "), docs), "\n")
    output_markdown = Markdown.parse(output_string)
    return output_markdown
end

const guidelines_function = AutoMerge.get_automerge_guidelines
const registration_type = AutoMerge.NewPackage()
const output_markdown = guidelines_to_markdown_output(guidelines_function)

return output_markdown
```

## New versions of existing packages

```@eval
import RegistryCI
import AutoMerge
import Markdown

function guidelines_to_markdown_output(guidelines_function::Function)
    guidelines = guidelines_function(
        registration_type;
        check_license = true,
        check_breaking_explanation = true,
        this_is_jll_package = false,
        this_pr_can_use_special_jll_exceptions = false,
        use_distance_check = false,
        package_author_approved = false,
    )
    filter!(x -> !(x[1] isa Symbol), guidelines)
    filter!(x -> !(x[1].docs isa Nothing), guidelines)
    docs = [rstrip(x[1].docs) for x in guidelines]
    output_string = join(string.(collect(1:length(docs)), Ref(". "), docs), "\n")
    output_markdown = Markdown.parse(output_string)
    return output_markdown
end

const guidelines_function = AutoMerge.get_automerge_guidelines
const registration_type = AutoMerge.NewVersion()
const output_markdown = guidelines_to_markdown_output(guidelines_function)

return output_markdown
```

## Additional information

### Upper-bounded `[compat]` entries

For example, the following `[compat]` entries meet the criteria for automatic merging:
```toml
[compat]
PackageA = "1"          # [1.0.0, 2.0.0), has upper bound (good)
PackageB = "0.1, 0.2"   # [0.1.0, 0.3.0), has upper bound (good)
```
The following `[compat]` entries do NOT meet the criteria for automatic merging:
```toml
[compat]
PackageC = ">=3"        # [3.0.0, ∞), no upper bound (bad)
PackageD = ">=0.4, <1"  # [0, ∞), no lower bound, no upper bound (very bad)
```
Please note: each `[compat]` entry must include only a finite number of breaking releases. Therefore, the following `[compat]` entries do NOT meet the criteria for automatic merging:
```toml
[compat]
PackageE = "0"          # includes infinitely many breaking 0.x releases of PackageE (bad)
PackageF = "0.2 - 0"    # includes infinitely many breaking 0.x releases of PackageF (bad)
PackageG = "0.2 - 1"    # includes infinitely many breaking 0.x releases of PackageG (bad)
```
See [Pkg's documentation](https://julialang.github.io/Pkg.jl/v1/compatibility/) for specification of `[compat]` entries in your
`Project.toml` file.

(**Note:** JLL dependencies are excluded from this criterion because they often have non-standard version numbering schemes; however, this may change in the future.)

You may find [CompatHelper.jl](https://github.com/bcbi/CompatHelper.jl) and [PackageCompatUI.jl](https://github.com/GunnarFarneback/PackageCompatUI.jl) helpful for maintaining up-to-date `[compat]` entries.

### Name similarity distance check

These checks and tolerances are subject to change in order to improve the
process.

To test yourself that a tentative package name, say `MyPackage` meets these
checks, you can use the following code (after adding the RegistryCI package
to your Julia environment):

```@example
using RegistryCI, RegistryInstances
using AutoMerge
path_to_registry = joinpath(DEPOT_PATH[1], "registries", "General.toml")
all_pkg_names = AutoMerge.get_all_non_jll_package_names(RegistryInstance(path_to_registry))
AutoMerge.meets_distance_check("MyPackage123", all_pkg_names)
```

where `path_to_registry` is a path to the registry of
interest. For the General Julia registry, usually `path_to_registry =
joinpath(DEPOT_PATH[1], "registries", "General.toml")` if you haven't changed
your `DEPOT_PATH` (or `path_to_registry =
joinpath(DEPOT_PATH[1], "registries", "General")` if you have an uncompressed registry at the directory there). This will return a boolean, indicating whether or not
your tentative package name passed the check, as well as a string,
indicating what the problem is in the event the check did not pass.

Note that these automerge guidelines are deliberately conservative: it is
very possible for a perfectly good name to not pass the automatic checks and
require manual merging. They simply exist to provide a fast path so that
manual review is not required for every new package.

### Providing and updating release notes

When invoking a registration with the `@JuliaRegister` bot, release notes can be added in the form
```
@JuliaRegistrator register

Release notes:

## Breaking changes

- Explanation of breaking change, ideally with upgrade tips
- ...
```

These can also be added/updated on the General PR by re-invoking with the above.

Doing this has two benefits:
 - helps explanations during the registration process, especially for breaking changes
 - release notes are picked up by TagBot such that they are added to the new release on the original repo

Automerge is disabled for breaking changes where release notes are not provided mentioning "breaking" (or "changelog" if there is a repository file that you prefer to direct users to).

## List of all GitHub PR labels that can influence AutoMerge

AutoMerge reads certain labels on GitHub registration pull requests to influence its decisions.
Specifically, these labels are:

* `Override AutoMerge: name similarity is okay`
    * This label can be manually applied by folks with triage-level access to the registry repository.
    * AutoMerge skips the "name similarity check" on new package registration PRs with this label.
* `Override AutoMerge: package author approved`
    * This label can be manually applied, but typically is applied by a separate Github Actions workflow which monitors the PR for comments by the package author, and applies this label if they write `[merge approved]`.
    * This label currently only skips the "sequential version number" check in new versions. In the future, the author-approval mechanism may be used for other checks (on both "new version" registrations and also "new package" registrations).
        * When AutoMerge fails a check that can be skipped by author-approval, it will mention so in the comment, and direct authors to comment `[merge approved]` if they want to skip the check.
