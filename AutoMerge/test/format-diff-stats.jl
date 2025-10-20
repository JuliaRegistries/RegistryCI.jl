using Test
using AutoMerge

# Here we test `AutoMerge.format_diff_stats`
# We want to check a variety of properties about each test-case,
# so we group the properties into a `TestProps` struct, then iterate
# over test-cases and verify each property.

# Expected properties for each test case
Base.@kwdef struct TestProps
    has_inline_diff::Bool = false
    has_details::Bool = false
    has_stat::Bool = false
    has_shortstat::Bool = false
    has_omitted_msg::Bool = false
    has_utf8_msg::Bool = false
    # number of backticks in diff fence, or nothing if not checking:
    diff_fence_count::Union{Int,Nothing} = nothing
    # number of backticks in sh fence, or nothing if not checking:
    sh_fence_count::Union{Int,Nothing} = nothing
end

# Property checker helpers
has_inline_diff(r) = occursin("```diff", r) && !occursin("<details>", r)
has_details(r) = occursin("<details>", r)
has_stat(r) = occursin("❯ git diff-tree --stat", r)
has_shortstat(r) = occursin("❯ git diff-tree --shortstat", r)
has_omitted_msg(r) = occursin("over limit of 50k", r)
has_utf8_msg(r) = occursin("not valid UTF-8", r)
check_fences(r, n, lang) = occursin("`"^n * lang, r) && !occursin("`"^(n+1) * lang, r)

# Test case runner
function check_properties(result, props::TestProps)
    checks = [
        ("has_inline_diff", has_inline_diff(result), props.has_inline_diff),
        ("has_details", has_details(result), props.has_details),
        ("has_stat", has_stat(result), props.has_stat),
        ("has_shortstat", has_shortstat(result), props.has_shortstat),
        ("has_omitted_msg", has_omitted_msg(result), props.has_omitted_msg),
        ("has_utf8_msg", has_utf8_msg(result), props.has_utf8_msg),
    ]

    for (name, actual, expected) in checks
        if actual != expected
            return false, "Property $name failed: expected $expected, got $actual"
        end
    end

    # Check diff fence count if specified
    if props.diff_fence_count !== nothing
        if !check_fences(result, props.diff_fence_count, "diff")
            return false, "Expected $(props.diff_fence_count) backticks in diff fence in comment:\n\n$result"
        end
    end

    # Check sh fence count if specified
    if props.sh_fence_count !== nothing
        if !check_fences(result, props.sh_fence_count, "sh")
            return false, "Expected $(props.sh_fence_count) backticks in sh fence for in comment:\n\n$result"
        end
    end

    return true, ""
end

@testset "format_diff_stats" begin
    old_sha = "abc123"
    new_sha = "def456"

    # Default stat values
    default_stat = " file.txt | 1 +\n 1 file changed, 1 insertion(+)"
    default_shortstat = " 1 file changed, 1 insertion(+)"

    test_cases = [
        # Inline display tests
        (name = "Basic inline",
         full_diff = "simple diff",
         stat = default_stat,
         shortstat = default_shortstat,
         props = TestProps(has_inline_diff=true, diff_fence_count=3)),

        (name = "12 lines boundary",
         full_diff = join(["line $i" for i in 1:12], "\n"),
         stat = default_stat,
         shortstat = default_shortstat,
         props = TestProps(has_inline_diff=true)),

        (name = "2399 chars boundary",
         full_diff = "x"^2399,
         stat = default_stat,
         shortstat = default_shortstat,
         props = TestProps(has_inline_diff=true)),

        (name = "Empty diff",
         full_diff = "",
         stat = "",
         shortstat = "",
         props = TestProps(has_inline_diff=true)),

        # Details block tests
        (name = "13 lines → details",
         full_diff = join(["line $i" for i in 1:13], "\n"),
         stat = default_stat,
         shortstat = default_shortstat,
         props = TestProps(has_details=true, has_stat=true, sh_fence_count=3)),

        (name = "2400 chars → details",
         full_diff = "x"^2400,
         stat = default_stat,
         shortstat = default_shortstat,
         props = TestProps(has_details=true, has_stat=true, sh_fence_count=3)),

        # Stat vs shortstat tests
        (name = "Long stat → shortstat",
         full_diff = join(["line $i" for i in 1:20], "\n"),
         stat = join([" file$i.txt | 1 +" for i in 1:13], "\n") * "\n 13 files changed",
         shortstat = " 13 files changed",
         props = TestProps(has_details=true, has_shortstat=true, sh_fence_count=3)),

        (name = "12-line stat → show stat",
         full_diff = join(["line $i" for i in 1:20], "\n"),
         stat = join([" file$i.txt | 1 +" for i in 1:11], "\n") * "\n 11 files changed",
         shortstat = " 11 files changed",
         props = TestProps(has_details=true, has_stat=true, sh_fence_count=3)),

        # Large diff tests
        (name = "50k chars → include",
         full_diff = "x"^50_000,
         stat = default_stat,
         shortstat = default_shortstat,
         props = TestProps(has_details=true, has_stat=true, sh_fence_count=3)),

        (name = "50,001 chars → omit",
         full_diff = "x"^50_001,
         stat = default_stat,
         shortstat = default_shortstat,
         props = TestProps(has_omitted_msg=true, has_stat=true, sh_fence_count=3)),

        # Invalid UTF-8 tests
        (name = "Invalid UTF-8 → message",
         full_diff = String([0xff, 0xfe, 0xfd]),
         stat = default_stat,
         shortstat = default_shortstat,
         props = TestProps(has_utf8_msg=true, has_stat=true, sh_fence_count=3)),

        # Fence escaping tests
        (name = "No backticks → ```",
         full_diff = "simple",
         stat = default_stat,
         shortstat = default_shortstat,
         props = TestProps(has_inline_diff=true, diff_fence_count=3)),

        (name = "Single backtick → ``",
         full_diff = "has ` backtick",
         stat = default_stat,
         shortstat = default_shortstat,
         props = TestProps(has_inline_diff=true, diff_fence_count=3)),

        (name = "Triple backticks → ````",
         full_diff = "```code```",
         stat = default_stat,
         shortstat = default_shortstat,
         props = TestProps(has_inline_diff=true, diff_fence_count=4)),

        (name = "Four backticks → `````",
         full_diff = "````code````",
         stat = default_stat,
         shortstat = default_shortstat,
         props = TestProps(has_inline_diff=true, diff_fence_count=5)),

        (name = "Fence escaping in details",
         full_diff = join(["line $i```" for i in 1:20], "\n"),
         stat = default_stat,
         shortstat = default_shortstat,
         props = TestProps(has_details=true, has_stat=true, diff_fence_count=4, sh_fence_count=3)),

        (name = "Fence escaping in stat",
         full_diff = join(["line $i" for i in 1:20], "\n"),
         stat = " file````.txt | 1 +\n 1 file changed, 1 insertion(+)",
         shortstat = default_shortstat,
         props = TestProps(has_details=true, has_stat=true, diff_fence_count=3, sh_fence_count=5)),

        # Combined scenarios
        (name = "50k with long stat → shortstat + details",
         full_diff = "z"^50_000,
         stat = join([" file$i.txt | 100 +" * "+"^10 for i in 1:20], "\n") * "\n 20 files changed",
         shortstat = " 20 files changed",
         props = TestProps(has_details=true, has_shortstat=true, sh_fence_count=3)),

        (name = "Invalid UTF-8 with long stat → shortstat",
         full_diff = String([0xff, 0xfe, 0xfd]),
         stat = join([" file$i.txt | 1 +" for i in 1:15], "\n") * "\n 15 files changed",
         shortstat = " 15 files changed",
         props = TestProps(has_utf8_msg=true, has_shortstat=true, sh_fence_count=3)),
    ]

    @testset "$(tc.name)" for tc in test_cases
        result = AutoMerge.format_diff_stats(tc.full_diff, tc.stat, tc.shortstat;
                                             old_tree_sha=old_sha, new_tree_sha=new_sha)
        success, msg = check_properties(result, tc.props)

        @test success || error(msg)
    end
end
