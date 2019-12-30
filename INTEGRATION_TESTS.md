# Integration tests for RegistryCI.jl

## How to run the integration tests on your local machine

You may find it helpful to set up your own test repo and run the integration tests on your local machine. Here are the steps:

1. Set up a test repository, i.e. create a new public GitHub repository for testing purposes. For this example, suppose that this repo is called `ericphanson/MY_REGISTRYCI_TEST_REPO`.

2. Make sure that there is some content in the `master` branch of `ericphanson/MY_REGISTRYCI_TEST_REPO`. Perhaps just a `README.md` file with a single word or something like that.

3. Set the environment variable: `export AUTOMERGE_INTEGRATION_TEST_REPO="ericphanson/MY_REGISTRYCI_TEST_REPO"`

4. Set the environment variable: `export AUTOMERGE_RUN_INTEGRATION_TESTS="true"`

5. Go to https://github.com/settings/tokens and generate a new GitHub personal access token. The token only needs the `repo` and `public_repo` permissions - you can uncheck all other permissions. Save that token somewhere - I recommend saving the token in a secure location like a password manager.

6. Set the environment variable containing your GitHub personal access token: `export BCBI_TEST_USER_GITHUB_TOKEN="YOUR_GITHUB_PERSONAL_ACCESS_TOKEN"`

7. Run the package tests `Pkg.test("RegistryCI")`. Watch the logs - you should see the message `Running the AutoMerge.jl integration tests`, which confirms that you are running the integration tests.

## Maintainers of the `RegistryCI.jl` package: How to run the integration tests (and merge if passing) on PRs from forks 

Suppose that the PR number is `#123`. And the PR was made by some user `THEIR_USERNAME` who has a fork at `THEIR_USERNAME/RegistryCI.jl`. And they made the PR from a branch named `THEIR_INITIALS/MY_FEATURE_BRANCH` in their fork.

1. `git clone git@github.com:JuliaRegistries/RegistryCI.jl.git`

2. `cd RegistryCI.jl`

3. `git checkout master`

4. `git checkout -B staging-pr-123 master`

5. `git fetch origin +refs/pull/123/head`

6. `git checkout -B THEIR_USERNAME--THEIR_INITIALS/MY_FEATURE_BRANCH FETCH_HEAD`

7.  `git checkout staging-pr-123`

8. `git merge --no-ff --no-edit THEIR_USERNAME--THEIR_INITIALS/MY_FEATURE_BRANCH`

9. `git push --force-with-lease origin staging-pr-123`

10. If there already exists an open pull request to merge the `staging-pr-123` branch into the `master` branch, let `#456` denote the number of this pull request, and go to step 12. If there does not exist such a pull request, go to step 11.

11. Go to `https://github.com/JuliaRegistries/RegistryCI.jl/pull/new/staging-pr-123` and create the pull request to merge the `staging-pr-123` branch into the `master` branch. Let `#456` denote the number of this new pull request. Go to step 12.

12. Recall that `#456` denotes the number of the pull request to merge the `staging-pr-123` branch into the `master` branch. Wait for all of the Travis CI tests and CodeCov status checks to finish on pull request `#456`.

13. Once all of the Travis CI tests and CodeCov status checks have finished **AND ARE PASSING (GREEN)** on pull request `#456`, merge pull request `#456`. Do not use the `Squash and merge` or `Rebase and merge` options. You must merge pull request `#456` by using the regular **`Merge pull request`** (i.e. **`Create a merge commit`**) option. This ensures that the original author (the person that made the original pull request from a fork) gets the appropriate credit.
