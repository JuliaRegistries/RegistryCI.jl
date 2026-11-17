# Integration tests for RegistryCI.jl

## Why the integration tests use a global lock

The AutoMerge integration tests perform real GitHub operations such as creating pull requests and comments. Those "create content" operations are subject to GitHub rate limits and abuse-prevention throttling.

As documented in [issue #589](https://github.com/JuliaRegistries/RegistryCI.jl/issues/589), running multiple integration-test jobs at the same time makes those throttles much more likely. The current workflow therefore serializes the real integration-test runs with a shared concurrency group so only one job uses the test registry at a time.

PR [#654](https://github.com/JuliaRegistries/RegistryCI.jl/pull/654) tried removing that concurrency group after a `GitHub.jl` upgrade improved retry handling. In practice, that still led to rate limits being hit so quickly that GitHub asked the jobs to wait 20 to 30 minutes. The conclusion from [the latest comment on issue #589](https://github.com/JuliaRegistries/RegistryCI.jl/issues/589#issuecomment-4094808230) is that we still need to keep the global lock.

The current CI policy in `.github/workflows/ci_integration.yml` is:

1. `pull_request` runs are placeholders only, so the required check can be green without running the real integration tests on every PR build.
2. The real integration tests run only on `merge_group`, `push` to `master`, and `workflow_dispatch`.
3. Those real runs share the `integration-tests-global-lock` concurrency group.

If an integration-test job appears to be stuck, it may simply be waiting for the shared lock instead of failing.

## How to run the integration tests on your local machine

You may find it helpful to set up your own test repo and run the integration tests on your local machine. Here are the steps:

1. Set up a test repository, i.e. create a new public GitHub repository for testing purposes. For this example, suppose that this repo is called `MY_GITHUB_USERNAME/MY_REGISTRYCI_TEST_REPO`.

2. Make sure that there is some content in the `master` branch of `MY_GITHUB_USERNAME/MY_REGISTRYCI_TEST_REPO`. Perhaps just a `README.md` file with a single word or something like that.

3. Set the environment variable: `export AUTOMERGE_INTEGRATION_TEST_REPO="MY_GITHUB_USERNAME/MY_REGISTRYCI_TEST_REPO"`

4. Set the environment variable: `export AUTOMERGE_RUN_INTEGRATION_TESTS="true"`

5. Go to https://github.com/settings/tokens and generate a new GitHub personal access token. The token only needs the `repo` and `public_repo` permissions - you can uncheck all other permissions. Save that token somewhere - I recommend saving the token in a secure location like a password manager.

6. Set the environment variable containing your GitHub personal access token: `export BCBI_TEST_USER_GITHUB_TOKEN="YOUR_GITHUB_PERSONAL_ACCESS_TOKEN"`

7. Run the package tests `Pkg.test("RegistryCI")`. Watch the logs - you should see the message `Running the AutoMerge.jl integration tests`, which confirms that you are running the integration tests.
