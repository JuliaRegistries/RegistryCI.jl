using Dates
using GitHub
using Printf
using TimeZones

const timestamp_regex = r"integration\/(\d\d\d\d-\d\d-\d\d-\d\d-\d\d-\d\d-\d\d\d)\/"

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
    with_temp_dir() do dir
        cd(dir)
        git_repo_dir = joinpath(dir, "REPO")
        try
            run(`$(GIT) clone $(AUTOMERGE_INTEGRATION_TEST_REPO) REPO`)
        catch
        end
        cd(git_repo_dir)
        all_origin_branches = list_all_origin_branches(git_repo_dir; GIT=GIT)::Vector{String}
        for b in all_origin_branches
            if occursin(timestamp_regex, b)
                try
                    run(`$(GIT) push origin --delete $(b)`)
                catch
                end
                try
                    run(`$(GIT) push origin :$(b)`)
                catch
                end
            end
        end
    end
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
