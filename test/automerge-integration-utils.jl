using Dates
using GitHub
using Pkg
using Printf
using RegistryCI
using Test
using TimeZones

const AutoMerge = RegistryCI.AutoMerge

const timestamp_regex = r"integration\/(\d\d\d\d-\d\d-\d\d-\d\d-\d\d-\d\d-\d\d\d)\/"

function wait_pr_compute_mergeability(repo::GitHub.Repo, pr::GitHub.PullRequest; auth::GitHub.Authorization)
    while !(pr.mergeable isa Bool)
        sleep(5)
        pr = GitHub.pull_request(repo, pr.number; auth = auth)
    end
    return pr
end

function close_all_pull_requests(repo::GitHub.Repo;
                                 auth::GitHub.Authorization,
                                 state::String)
    all_pull_requests = AutoMerge.get_all_pull_requests(repo,
                                                        state;
                                                        auth = auth)
    for pr in all_pull_requests
        try
            GitHub.close_pull_request(repo, pr)
        catch
        end
    end
    return nothing
end

function templates(parts...)
    this_filename = @__FILE__
    test_directory = dirname(this_filename)
    templates_directory = joinpath(test_directory, "templates")
    result = joinpath(templates_directory, parts...)
    return result
end

function get_random_number_from_system()
    result = parse(Int, strip(read(pipeline(`cat /dev/random`, `od -vAn -N4 -D`), String)))::Int
    return result
end

function my_two_datetimes_now()
    _now_zdt = now_localzone()
    _now_utc = astimezone(_now_zdt, tz"UTC")
    _now_et = astimezone(_now_zdt, tz"America/New_York")
    return _now_utc, _now_et
end

function my_two_times_now()
    _now_utc, _now_et = my_two_datetimes_now()
    utc_string = @sprintf "%02d:%02d UTC" Hour(_now_utc).value Minute(_now_utc).value
    et_string = @sprintf "%02d:%02d %s" Hour(_now_et).value Minute(_now_et).value _now_et.zone.name
    result = "$(et_string) ($(utc_string))"
end

@inline now_localzone() = now(localzone())

function utc_to_string(zdt::ZonedDateTime)
    zdt_as_utc = astimezone(zdt, tz"UTC")
    year = Year(zdt_as_utc.utc_datetime).value
    month = Month(zdt_as_utc.utc_datetime).value
    day = Day(zdt_as_utc.utc_datetime).value
    hour = Hour(zdt_as_utc.utc_datetime).value
    minute = Minute(zdt_as_utc.utc_datetime).value
    second = Second(zdt_as_utc.utc_datetime).value
    millisecond = Millisecond(zdt_as_utc.utc_datetime).value
    result = @sprintf "%04d-%02d-%02d-%02d-%02d-%02d-%03d" year month day hour minute second millisecond
    return result
end

function string_to_utc(s::AbstractString)
    df = DateFormat("yyyy-mm-dd-HH-MM-SS-sss")
    dt = DateTime(s, df)
    zdt = ZonedDateTime(dt, tz"UTC")
    return zdt
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
    for i = 1:b_length
        c[i] = strip(strip(strip(b[i]), '*'))
        c[i] = first(split(c[i], "->"))
        c[i] = strip(c[i])
    end
    my_regex = r"^remotes\/origin\/(.*)$"
    for i = 1:b_length
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

function delete_stale_branches(AUTOMERGE_INTEGRATION_TEST_REPO; GIT)
    with_cloned_repo(AUTOMERGE_INTEGRATION_TEST_REPO; GIT = GIT) do git_repo_dir
        cd(git_repo_dir)
        all_origin_branches = list_all_origin_branches(git_repo_dir; GIT=GIT)::Vector{String}
        for b in all_origin_branches
            if occursin(timestamp_regex, b)
                try
                    run(`$(GIT) push origin --delete $(b)`)
                catch
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
            rm(path; force = true, recursive = true)
        end
    end
    cd(original_working_directory)
    return nothing
end

function with_temp_dir(f)
    original_working_directory = pwd()
    tmp_dir = mktempdir()
    atexit(() -> rm(tmp_dir; force = true, recursive = true))
    cd(tmp_dir)
    result = f(tmp_dir)
    cd(original_working_directory)
    rm(tmp_dir; force = true, recursive = true)
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

function with_pr_merge_commit(f::Function,
                              pr::GitHub.PullRequest,
                              repo_url::AbstractString;
                              GIT)
    original_working_directory = pwd()
    result = with_cloned_repo(repo_url; GIT = GIT) do git_repo_dir
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
    _now = now_localzone()
    _now_utc_string = utc_to_string(_now)
    b = "integration/$(_now_utc_string)/$(rand(UInt32))/$(name)"
    sleep(0.1)
    return b
end

function generate_branch(name::AbstractString,
                         path_to_content::AbstractString,
                         parent_branch::AbstractString = "master";
                         GIT,
                         repo_url)
    original_working_directory = pwd()
    b = _generate_branch_name(name)
    with_cloned_repo(repo_url; GIT = GIT) do git_repo_dir
        cd(git_repo_dir)
        run(`$(GIT) checkout $(parent_branch)`)
        run(`$(GIT) branch $(b)`)
        run(`$(GIT) checkout $(b)`)
        empty_git_repo(git_repo_dir)
        for x in readdir(path_to_content)
            src = joinpath(path_to_content, x)
            dst = joinpath(git_repo_dir, x)
            rm(dst; force = true, recursive = true)
            cp(src, dst; force = true)
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
        rm(git_repo_dir; force = true, recursive = true)
    end
    return b
end

function generate_master_branch(path_to_content::AbstractString,
                                parent_branch::AbstractString = "master";
                                GIT,
                                repo_url)
    name = "master"
    b = generate_branch(name, path_to_content, parent_branch; GIT = GIT, repo_url = repo_url)
    return b
end

function generate_feature_branch(path_to_content::AbstractString,
                                 parent_branch::AbstractString;
                                 GIT,
                                 repo_url)
    name = "feature"
    b = generate_branch(name,
                        path_to_content,
                        parent_branch;
                        GIT = GIT,
                        repo_url = repo_url)
    return b
end

function with_master_branch(f::Function,
                            path_to_content::AbstractString,
                            parent_branch::AbstractString;
                            GIT,
                            repo_url)
    b = generate_master_branch(path_to_content,
                               parent_branch;
                               GIT = GIT,
                               repo_url = repo_url)
    result = f(b)
    return result
end

function with_feature_branch(f::Function,
                             path_to_content::AbstractString,
                             parent_branch::AbstractString;
                             GIT,
                             repo_url)
    b = generate_feature_branch(path_to_content,
                                parent_branch;
                                GIT = GIT,
                                repo_url = repo_url)
    result = f(b)
    return result
end
