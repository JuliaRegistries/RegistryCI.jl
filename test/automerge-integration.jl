include("automerge-integration-utils.jl")

a = get_random_number_from_system()
b = get_random_number_from_system()
c = get_random_number_from_system()
d = get_random_number_from_system()

@info("A random number from the system: $(a)")
@info("A random number from the system: $(b)")
@info("A random number from the system: $(c)")
@info("A random number from the system: $(d)")

AUTOMERGE_INTEGRATION_TEST_REPO = ENV["AUTOMERGE_INTEGRATION_TEST_REPO"]::String
TEST_USER_GITHUB_TOKEN = ENV["BCBI_TEST_USER_GITHUB_TOKEN"]::String
GIT = "git"
auth = GitHub.authenticate(TEST_USER_GITHUB_TOKEN)
whoami = RegistryCI.AutoMerge.username(auth)
repo_url_without_auth = "https://github.com/$(AUTOMERGE_INTEGRATION_TEST_REPO)"
repo_url_with_auth = "https://$(whoami):$(TEST_USER_GITHUB_TOKEN)@github.com/$(AUTOMERGE_INTEGRATION_TEST_REPO)"
repo = GitHub.repo(AUTOMERGE_INTEGRATION_TEST_REPO; auth = auth)
@test success(`$(GIT) --version`)
@info("Authenticated to GitHub as \"$(whoami)\"")
