```@meta
CurrentModule = RegistryCI
```

# Regexes

In order for AutoMerge to work, each pull request (PR) must match the following
regular expressions:

```@eval
import RegistryCI
import Markdown

const AutoMerge = RegistryCI.AutoMerge

escape_pipes(str::String) = replace(str, "|" => "\\|")

const new_package_title_regex = AutoMerge.new_package_title_regex |> repr |> escape_pipes
const new_version_title_regex = AutoMerge.new_version_title_regex |> repr |> escape_pipes
const commit_regex            = AutoMerge.commit_regex            |> repr |> escape_pipes

const markdown_lines = String[
    "| Regex                        | Field    | PR Type      | Example                          |",
    "| ---------------------------- | -------- | ------------ | -------------------------------- |",
    "| `$(new_package_title_regex)` | PR title | New packages | `New package: HelloWorld v1.2.3` |",
    "| `$(new_version_title_regex)` | PR title | New versions | `New version: HelloWorld v1.2.3` |",
    "| `$(commit_regex)`            | PR body  | All          | `* Commit: mycommithash123`      |",
]

const markdown_string = join(markdown_lines, "\n")
const markdown_parsed = Markdown.parse(markdown_string)

return markdown_parsed
```
