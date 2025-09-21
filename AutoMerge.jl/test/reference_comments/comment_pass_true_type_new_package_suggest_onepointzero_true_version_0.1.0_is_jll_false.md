Hello, I am an automated registration bot. I help manage the registration process by checking your registration against a set of [AutoMerge guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/). If all these guidelines are met, this pull request will be merged automatically, completing your registration. It is **strongly recommended** to follow the guidelines, since otherwise the pull request needs to be manually reviewed and merged by a human.

## 1. New package registration

Please make sure that you have read the [package naming guidelines](https://julialang.github.io/Pkg.jl/dev/creating-packages/#Package-naming-guidelines-1).

## 2. [AutoMerge Guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/) are all met! ✅

Your new package registration met all of the guidelines for auto-merging and is scheduled to be merged when the mandatory waiting period (3 days) has elapsed.

## 3. Declare v1.0?

On a separate note, I see that you are registering a release with a version number of the form `v0.X.Y`.

Does your package have a stable public API? If so, then it's time for you to register version `v1.0.0` of your package. (This is not a requirement. It's just a recommendation.)

If your package does not yet have a stable public API, then of course you are not yet ready to release version `v1.0.0`.

## 4. To pause or stop registration

If you want to prevent this pull request from being auto-merged, simply leave a comment. If you want to post a comment without blocking auto-merging, you must include the text `[noblock]` in your comment.

_Tip: You can edit blocking comments to add `[noblock]` in order to unblock auto-merging._

<!-- [noblock] -->