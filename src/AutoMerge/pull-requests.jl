const new_package_title_regex = r"^New package: (\w*) v(.*)"

const new_version_title_regex = r"^New version: (\w*) v(.*)"

const commit_regex = r"\n- Commit: (\w*)\n"

is_new_package(pull_request::GitHub.PullRequest) = occursin(new_package_title_regex, title(pull_request))

is_new_version(pull_request::GitHub.PullRequest) = occursin(new_version_title_regex, title(pull_request))

function check_authorization(pkg, pr_author_login, authorized_authors,
                             authorized_authors_special_jll_exceptions,
                             error_exit_if_automerge_not_applicable)
    if pr_author_login ∉ vcat(authorized_authors,
                              authorized_authors_special_jll_exceptions)
        throw_not_automerge_applicable(
            AutoMergeAuthorNotAuthorized,
            "Author $(pr_author_login) is not authorized to automerge. Exiting...";
            error_exit_if_automerge_not_applicable = error_exit_if_automerge_not_applicable
        )
        return :not_authorized
    end

    # A JLL-only author (e.g. `jlbuild`) is not allowed to register
    # non-JLL packages.
    this_is_jll_package = is_jll_name(pkg)
    if (!this_is_jll_package && pr_author_login ∉ authorized_authors)
        throw_not_automerge_applicable(
            AutoMergeAuthorNotAuthorized,
            "This package is not a JLL package. Author $(pr_author_login) is not authorized to register non-JLL packages. Exiting...";
            error_exit_if_automerge_not_applicable = error_exit_if_automerge_not_applicable
        )
        return :not_authorized
    end

    if pr_author_login ∈ authorized_authors_special_jll_exceptions
        return :jll
    end

    return :normal
end

function parse_pull_request_title(::NewVersion,
                                  pull_request::GitHub.PullRequest)
    m = match(new_version_title_regex, title(pull_request))
    pkg = convert(String, m.captures[1])::String
    version = VersionNumber(m.captures[2])
    return pkg, version
end

function commit_from_pull_request_body(pull_request::GitHub.PullRequest)
    pr_body = body(pull_request)
    m = match(commit_regex, string("\n", pr_body, "\n"))
    return convert(String, m.captures[1])::String
end

function parse_pull_request_title(::NewPackage,
                                  pull_request::GitHub.PullRequest)
    m = match(new_package_title_regex, title(pull_request))
    pkg = convert(String, m.captures[1])::String
    version = VersionNumber(m.captures[2])
    return pkg, version
end

function pull_request_build(api::GitHub.GitHubAPI,
                            pr_number::Integer,
                            current_pr_head_commit_sha::String,
                            registry::GitHub.Repo,
                            registry_head::String;
                            whoami::String,
                            auth::GitHub.Authorization,
                            authorized_authors::Vector{String},
                            authorized_authors_special_jll_exceptions::Vector{String},
                            error_exit_if_automerge_not_applicable = error_exit_if_automerge_not_applicable,
                            master_branch::String,
                            master_branch_is_default_branch::Bool,
                            suggest_onepointzero::Bool,
                            registry_deps::Vector{<:AbstractString} = String[],
                            check_license::Bool,
                            public_registries::Vector{<:AbstractString} = String[],
                            read_only::Bool)::Nothing
    pr = my_retry(() -> GitHub.pull_request(api, registry, pr_number; auth=auth))
    _github_api_pr_head_commit_sha = pull_request_head_sha(pr)
    if current_pr_head_commit_sha != _github_api_pr_head_commit_sha
        throw(AutoMergeShaMismatch("Current commit sha (\"$(current_pr_head_commit_sha)\") does not match what the GitHub API tells us (\"$(_github_api_pr_head_commit_sha)\")"))
    end
    result = pull_request_build(api,
                                pr,
                                current_pr_head_commit_sha,
                                registry,
                                registry_head;
                                auth=auth,
                                authorized_authors=authorized_authors,
                                authorized_authors_special_jll_exceptions=authorized_authors_special_jll_exceptions,
                                error_exit_if_automerge_not_applicable = error_exit_if_automerge_not_applicable,
                                master_branch=master_branch,
                                master_branch_is_default_branch=master_branch_is_default_branch,
                                suggest_onepointzero=suggest_onepointzero,
                                whoami=whoami,
                                registry_deps=registry_deps,
                                check_license=check_license,
                                public_registries=public_registries,
                                read_only=read_only)
    return result
end

function pull_request_build(api::GitHub.GitHubAPI,
                            pr::GitHub.PullRequest,
                            current_pr_head_commit_sha::String,
                            registry::GitHub.Repo,
                            registry_head::String;
                            auth::GitHub.Authorization,
                            authorized_authors::Vector{String},
                            authorized_authors_special_jll_exceptions::Vector{String},
                            error_exit_if_automerge_not_applicable::Bool,
                            master_branch::String,
                            master_branch_is_default_branch::Bool,
                            suggest_onepointzero::Bool,
                            whoami::String,
                            registry_deps::Vector{<:AbstractString} = String[],
                            check_license::Bool,
                            public_registries::Vector{<:AbstractString} = String[],
                            read_only::Bool)::Nothing
    # 1. Check if the PR is open, if not quit.
    # 2. Determine if it is a new package or new version of an
    #    existing package, if neither quit.
    # 3. Check if the author is authorized, if not quit.
    # 4. Call the appropriate method for new package or new version.
    if !is_open(pr)
        throw_not_automerge_applicable(
            AutoMergePullRequestNotOpen,
            "The pull request is not open. Exiting...";
            error_exit_if_automerge_not_applicable = error_exit_if_automerge_not_applicable
        )
        return nothing
    end

    if is_new_package(pr)
        registration_type = NewPackage()
    elseif is_new_version(pr)
        registration_type = NewVersion()
    else
        throw_not_automerge_applicable(
            AutoMergeNeitherNewPackageNorNewVersion,
            "Neither a new package nor a new version. Exiting...";
            error_exit_if_automerge_not_applicable = error_exit_if_automerge_not_applicable,
        )
        return nothing
    end

    pkg, version = parse_pull_request_title(registration_type, pr)
    pr_author_login = author_login(pr)
    authorization = check_authorization(pkg, pr_author_login,
                                        authorized_authors,
                                        authorized_authors_special_jll_exceptions,
                                        error_exit_if_automerge_not_applicable)

    if authorization == :not_authorized
        return nothing
    end

    registry_master = clone_repo(registry)
    if !master_branch_is_default_branch
        checkout_branch(registry_master, master_branch)
    end
    data = GitHubAutoMergeData(;api = api,
                               registration_type = registration_type,
                               pr = pr,
                               pkg = pkg,
                               version = version,
                               current_pr_head_commit_sha = current_pr_head_commit_sha,
                               registry = registry,
                               auth = auth,
                               authorization = authorization,
                               registry_head = registry_head,
                               registry_master = registry_master,
                               suggest_onepointzero = suggest_onepointzero,
                               whoami = whoami,
                               registry_deps = registry_deps,
                               public_registries = public_registries,
                               read_only = read_only)
    pull_request_build(data, registration_type; check_license=check_license)
    rm(registry_master; force = true, recursive = true)
    return nothing
end
