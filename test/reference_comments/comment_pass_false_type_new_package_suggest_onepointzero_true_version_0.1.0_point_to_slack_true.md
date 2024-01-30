Your `new package` pull request does not meet the guidelines for auto-merging. Please make sure that you have read the [General registry README](https://github.com/JuliaRegistries/General/blob/master/README.md) and the [AutoMerge guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/). The following guidelines were not met:

- no

Note that the guidelines are only required for the pull request to be merged automatically. However, it is **strongly recommended** to follow them, since otherwise the pull request needs to be manually reviewed and merged by a human.

After you have fixed the AutoMerge issues, simply retrigger Registrator, which will automatically update this pull request. You do not need to change the version number in your `Project.toml` file (unless of course the AutoMerge issue is that you skipped a version number, in which case you should change the version number).

If you do not want to fix the AutoMerge issues, please post a comment explaining why you would like this pull request to be manually merged. Then, send a message to the `#pkg-registration` channel in the [Julia Slack](https://julialang.org/slack/) to ask for help. Include a link to this pull request.

Since you are registering a new package, please make sure that you have also read the package naming guidelines: https://pkgdocs.julialang.org/v1/creating-packages/#Package-naming-guidelines



---
If you want to prevent this pull request from being auto-merged, simply leave a comment. If you want to post a comment without blocking auto-merging, you must include the text `[noblock]` in your comment. You can edit blocking comments, adding `[noblock]` to them in order to unblock auto-merging.

---
On a separate note, I see that you are registering a release with a version number of the form `v0.X.Y`.

Does your package have a stable public API? If so, then it's time for you to register version `v1.0.0` of your package. (This is not a requirement. It's just a recommendation.)

If your package does not yet have a stable public API, then of course you are not yet ready to release version `v1.0.0`.
<!-- [noblock] -->