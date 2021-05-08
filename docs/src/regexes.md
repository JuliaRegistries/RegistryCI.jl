```@meta
CurrentModule = RegistryCI
```

# Regexes

In order for AutoMerge to work, each pull request (PR) must match the following
regular expressions:

```@eval
import RegistryCI
import Markdown

Base.@kwdef struct TableRow
    regex::Regex
    regex_str::String
    pr_field::String
    pr_type::String
    example::String
end

escape_pipes(str::String) = replace(str, "|" => "\\|")

function table_row(; regex::Regex,
                     pr_field::String,
                     pr_type::String,
                     example::String)
    regex_str = regex |> Base.repr |> escape_pipes
    result = TableRow(;
            regex,
            regex_str,
            pr_field,
            pr_type,
            example,
        )
    return result
end

const row_1 = table_row(;
    regex = RegistryCI.AutoMerge.new_package_title_regex,
    pr_field = "PR title",
    pr_type = "New packages",
    example = "New package: HelloWorld v1.2.3",
)

const row_2 = table_row(;
    regex = RegistryCI.AutoMerge.new_version_title_regex,
    pr_field = "PR title",
    pr_type = "New versions",
    example = "New version: HelloWorld----- v1.2.3",
)

const row_3 = table_row(;
    regex = RegistryCI.AutoMerge.commit_regex,
    pr_field = "PR body",
    pr_type = "All",
    example = "* Commit: mycommithash123",
)

const rows = [
    row_1,
    row_2,
    row_3,
]

for row in rows
    regex_occurs_in_example = occursin(row.regex, row.example)
    if !regex_occurs_in_example
        @error("Regex does not occur in example", row.regex, row.example)
        throw(ErrorException("Regex `$(row.regex)` does not occur in example \"$(row.example)\""))
    end
end

const markdown_lines = String[
    "| Regex | Field | PR Type | Example |",
    "| ----- | ----- | ------- | ------- |",
]

for row in rows
    line = "| `$(row.regex_str)` | $(row.pr_field) | $(row.pr_type) | `$(row.example)` |"
    push!(markdown_lines, line)
end

const markdown_string = join(markdown_lines, "\n")
const markdown_parsed = Markdown.parse(markdown_string)

return markdown_parsed
```
