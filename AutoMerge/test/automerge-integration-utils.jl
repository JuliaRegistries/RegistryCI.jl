using Dates
# using GitCommand
using GitHub
using JSON
using Pkg
using Printf
using AutoMerge
using Test
using TimeZones


const timestamp_regex = r"integration\/(\d\d\d\d-\d\d-\d\d-\d\d-\d\d-\d\d-\d\d\d)\/"

function wait_pr_compute_mergeability(
    api::GitHub.GitHubAPI,
    repo::GitHub.Repo,
    pr::GitHub.PullRequest;
    auth::GitHub.Authorization,
)
    while !(pr.mergeable isa Bool)
        sleep(5)
        pr = GitHub.pull_request(api, repo, pr.number; auth=auth)
    end
    return pr
end

function templates(parts...)
    this_filename = @__FILE__
    test_directory = dirname(this_filename)
    templates_directory = joinpath(test_directory, "templates")
    result = joinpath(templates_directory, parts...)
    return result
end

function get_random_number_from_system()
    result =
        parse(Int, strip(read(pipeline(`cat /dev/random`, `od -vAn -N4 -D`), String)))::Int
    return result
end

function my_two_datetimes_now()
    _now_utc = now(tz"UTC")
    _now_et = astimezone(_now_zdt, tz"America/New_York")
    return _now_utc, _now_et
end

function my_two_times_now()
    _now_utc, _now_et = my_two_datetimes_now()
    utc_string = @sprintf "%02d:%02d UTC" hour(_now_utc) minute(_now_utc)
    et_string = @sprintf "%02d:%02d %s" hour(_now_et) minute(_now_et) _now_et.zone.name
    return result = "$(et_string) ($(utc_string))"
end

function utc_to_string(zdt::ZonedDateTime)
    zdt_as_utc = astimezone(zdt, tz"UTC")
    y = year(zdt_as_utc)
    m = month(zdt_as_utc)
    d = day(zdt_as_utc)
    h = hour(zdt_as_utc)
    mi = minute(zdt_as_utc)
    s = second(zdt_as_utc)
    ms = millisecond(zdt_as_utc)
    result = @sprintf "%04d-%02d-%02d-%02d-%02d-%02d-%03d" y m d h mi s ms
    return result
end

function string_to_utc(s::AbstractString)
    dt = parse(DateTime, s, dateformat"yyyy-mm-dd-HH-MM-SS-sss")
    return ZonedDateTime(dt, tz"UTC")
end

function list_all_origin_branches(git_repo_dir; GIT)
    result = Vector{String}(undef, 0)
    original_working_directory = pwd()
    cd(git_repo_dir)
    a = try
        read(`$(GIT) branch -a`, String)
    catch
        ""
    end
    b = split(strip(a), '\n')
    b_length = length(b)
    c = Vector{String}(undef, b_length)
    for i in 1:b_length
        c[i] = strip(strip(strip(b[i]), '*'))
        c[i] = first(split(c[i], "->"))
        c[i] = strip(c[i])
    end
    my_regex = r"^remotes\/origin\/(.*)$"
    for i in 1:b_length
        if occursin(my_regex, c[i])
            m = match(my_regex, c[i])
            if m[1] != "HEAD"
                push!(result, m[1])
            end
        end
    end
    cd(original_working_directory)
    return result
end

function get_age_of_commit(commit)
    commit_date_string = strip(read(`git show -s --format=%cI $(commit)`, String))
    commit_date = TimeZones.ZonedDateTime(commit_date_string, "yyyy-mm-ddTHH:MM:SSzzzz")
    now = TimeZones.ZonedDateTime(TimeZones.now(), TimeZones.localzone())
    age = max(now - commit_date, Dates.Millisecond(0))
    return age
end

function delete_old_pull_request_branches(AUTOMERGE_INTEGRATION_TEST_REPO, older_than; GIT)
    with_cloned_repo(AUTOMERGE_INTEGRATION_TEST_REPO; GIT=GIT) do git_repo_dir
        cd(git_repo_dir)
        all_origin_branches =
            list_all_origin_branches(git_repo_dir; GIT=GIT)::Vector{String}
        for branch_name in all_origin_branches
            if occursin(timestamp_regex, branch_name)
                commit = strip(read(`git rev-parse origin/$(branch_name)`, String))
                age = get_age_of_commit(commit)
                if age >= older_than
                    try
                        run(`$(GIT) push origin --delete $(branch_name)`)
                    catch ex
                        @info "Encountered an error while trying to delete branch" exception = (
                            ex, catch_backtrace()
                        ) branch_name
                    end
                end
            end
        end
    end
    return nothing
end

function empty_git_repo(git_repo_dir::AbstractString)
    original_working_directory = pwd()
    cd(git_repo_dir)
    for x in readdir(git_repo_dir)
        if x != ".git"
            path = joinpath(git_repo_dir, x)
            rm(path; force=true, recursive=true)
        end
    end
    cd(original_working_directory)
    return nothing
end

function with_temp_dir(f)
    original_working_directory = pwd()
    tmp_dir = mktempdir()
    atexit(() -> rm(tmp_dir; force=true, recursive=true))
    cd(tmp_dir)
    result = f(tmp_dir)
    cd(original_working_directory)
    rm(tmp_dir; force=true, recursive=true)
    return result
end

function with_cloned_repo(f, repo_url; GIT)
    original_working_directory = pwd()
    result = with_temp_dir() do dir
        git_repo_dir = joinpath(dir, "REPO")
        cd(dir)
        try
            run(`$(GIT) clone $(repo_url) REPO`)
        catch
        end
        cd(git_repo_dir)
        return f(git_repo_dir)
    end
    cd(original_working_directory)
    return result
end

function get_git_current_head(dir)
    original_working_directory = pwd()
    cd(dir)
    result = convert(String, strip(read(`git rev-parse HEAD`, String)))::String
    cd(original_working_directory)
    return result
end

function with_pr_merge_commit(
    f::Function, pr::GitHub.PullRequest, repo_url::AbstractString; GIT
)
    original_working_directory = pwd()
    result = with_cloned_repo(repo_url; GIT=GIT) do git_repo_dir
        cd(git_repo_dir)
        number = pr.number
        run(`$(GIT) fetch origin +refs/pull/$(number)/merge`)
        run(`$(GIT) checkout -qf FETCH_HEAD`)
        head = get_git_current_head(git_repo_dir)
        merge_commit_sha = pr.merge_commit_sha
        @test strip(head) == strip(merge_commit_sha)
        return f(git_repo_dir)
    end
    cd(original_working_directory)
    return result
end

function _generate_branch_name(name::AbstractString)
    sleep(0.1)
    _now_utc = now(tz"UTC")
    _now_utc_string = utc_to_string(_now_utc)
    b = "integration/$(_now_utc_string)/$(rand(UInt32))/$(name)"
    sleep(0.1)
    return b
end

function generate_branch(
    name::AbstractString,
    path_to_content::AbstractString,
    parent_branch::AbstractString="master";
    GIT,
    repo_url,
)
    original_working_directory = pwd()
    b = _generate_branch_name(name)
    with_cloned_repo(repo_url; GIT=GIT) do git_repo_dir
        cd(git_repo_dir)
        run(`$(GIT) checkout $(parent_branch)`)
        run(`$(GIT) branch $(b)`)
        run(`$(GIT) checkout $(b)`)
        empty_git_repo(git_repo_dir)
        for x in readdir(path_to_content)
            src = joinpath(path_to_content, x)
            dst = joinpath(git_repo_dir, x)
            rm(dst; force=true, recursive=true)
            cp(src, dst; force=true)
        end
        cd(git_repo_dir)
        try
            run(`$(GIT) add -A`)
        catch
        end
        try
            run(`$(GIT) commit -m "Automatic commit - AutoMerge integration tests"`)
        catch
        end
        try
            run(`$(GIT) push origin $(b)`)
        catch
        end
        cd(original_working_directory)
        rm(git_repo_dir; force=true, recursive=true)
    end
    return b
end

function generate_master_branch(
    path_to_content::AbstractString, parent_branch::AbstractString="master"; GIT, repo_url
)
    name = "master"
    b = generate_branch(name, path_to_content, parent_branch; GIT=GIT, repo_url=repo_url)
    return b
end

function generate_feature_branch(
    path_to_content::AbstractString, parent_branch::AbstractString; GIT, repo_url
)
    name = "feature"
    b = generate_branch(name, path_to_content, parent_branch; GIT=GIT, repo_url=repo_url)
    return b
end

function with_master_branch(
    f::Function,
    path_to_content::AbstractString,
    parent_branch::AbstractString;
    GIT,
    repo_url,
)
    b = generate_master_branch(path_to_content, parent_branch; GIT=GIT, repo_url=repo_url)
    result = f(b)
    return result
end

function with_feature_branch(
    f::Function,
    path_to_content::AbstractString,
    parent_branch::AbstractString;
    GIT,
    repo_url,
)
    b = generate_feature_branch(path_to_content, parent_branch; GIT=GIT, repo_url=repo_url)
    result = f(b)
    return result
end

function generate_public_registry(public_dir::AbstractString, GIT)
    public_git_repo = mktempdir()
    cp(templates(public_dir), public_git_repo; force=true)
    run(`$(GIT) -C $(public_git_repo) init`)
    run(`$(GIT) -C $(public_git_repo) add .`)
    run(`$(GIT) -C $(public_git_repo) commit -m "create"`)
    return public_git_repo
end
