Hello, I am an automated registration bot. I help manage the registration process by checking your registration against a set of [AutoMerge guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/). If all these guidelines are met, this pull request will be merged automatically, completing your registration. It is **strongly recommended** to follow the guidelines, since otherwise the pull request needs to be manually reviewed and merged by a human.

## 1. [AutoMerge Guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/) are all met! ✅

Your new version registration met all of the guidelines for auto-merging and is scheduled to be merged in the next round (~20 minutes).

## 2. Code changes since last version

Code changes from v1.0.0: 

```sh
❯ git diff-tree --stat 999513b7dea8ac17359ed50ae8ea089e4464e35e 62389eeff14780bfe55195b7204c0d8738436d64
 .github/workflows/CI.yml        | 52 ++++++++++++++++++++++++++++++++++
 .github/workflows/TagBot.yml    | 11 +++++++
 .travis.yml                     | 14 ---------
 LICENSE.md                      |  2 +-
 Project.toml                    |  5 ++--
 README.md                       |  8 +++++-
 src/Requires.jl                 | 62 ++++++++++++++++++++++++++++++++++++----
 src/require.jl                  | 63 ++++++++++++++++++++++++++---------------
 test/Project.toml               |  1 +
 test/pkgs/NotifyMe/Project.toml |  8 ++++++
 ...
 12 files changed, 325 insertions(+), 121 deletions(-)
```

[View full diff](https://github.com/MikeInnes/Requires.jl/compare/c5789cdabf3918ac058a4a469cee3fda163765f3...999513b7dea8ac17359ed50ae8ea089e4464e35e)

## 3. To pause or stop registration

If you want to prevent this pull request from being auto-merged, simply leave a comment. If you want to post a comment without blocking auto-merging, you must include the text `[noblock]` in your comment.

_Tip: You can edit blocking comments to add `[noblock]` in order to unblock auto-merging._

<!-- [noblock] -->