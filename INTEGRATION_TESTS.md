# Integration tests for RegistryCI.jl

## How to run the integration tests on your local machine

You may find it helpful to set up your own test repo and run the integration tests on your local machine. Here are the steps:

1. Set up a test repository, i.e. create a new public GitHub repository for testing purposes. For this example, suppose that this repo is called `MY_GITHUB_USERNAME/MY_REGISTRYCI_TEST_REPO`.

2. Make sure that there is some content in the `master` branch of `MY_GITHUB_USERNAME/MY_REGISTRYCI_TEST_REPO`. Perhaps just a `README.md` file with a single word or something like that.

3. Set the environment variable: `export AUTOMERGE_INTEGRATION_TEST_REPO="MY_GITHUB_USERNAME/MY_REGISTRYCI_TEST_REPO"`

4. Set the environment variable: `export AUTOMERGE_RUN_INTEGRATION_TESTS="true"`

5. Go to https://github.com/settings/tokens and generate a new GitHub personal access token. The token only needs the `repo` and `public_repo` permissions - you can uncheck all other permissions. Save that token somewhere - I recommend saving the token in a secure location like a password manager.

6. Set the environment variable containing your GitHub personal access token: `export BCBI_TEST_USER_GITHUB_TOKEN="YOUR_GITHUB_PERSONAL_ACCESS_TOKEN"`

7. Run the package tests `Pkg.test("RegistryCI")`. Watch the logs - you should see the message `Running the AutoMerge.jl integration tests`, which confirms that you are running the integration tests.
