using Logging

function with_temp_dir(f::Function)
    original_working_directory = pwd()

    temp_dir = mktempdir()
    atexit(() -> rm(temp_dir; force=true, recursive=true))

    cd(temp_dir)
    result = f(temp_dir)

    cd(original_working_directory)
    rm(temp_dir; force=true, recursive=true)
    return result
end

function with_temp_depot(f::Function)
    original_depot_path = deepcopy(Base.DEPOT_PATH)
    result = with_temp_dir() do temp_depot
        empty!(Base.DEPOT_PATH)
        push!(Base.DEPOT_PATH, temp_depot)
        return f()
    end
    empty!(Base.DEPOT_PATH)
    for x in original_depot_path
        push!(Base.DEPOT_PATH, x)
    end
    return result
end


"""
    env_threshold_count(envvar::String, default)

Return an integer (intrerpreted as a number of lines) read
from the specified environment variable.
"""
function env_threshold_count(envvar::String, default)
        v = get(ENV, envvar, nothing)
    if v == nothing
        return default
    end
    m = match(r"(?<count>^[0-9]+)$", v)
    if m != nothing
        return parse(Int64, m["count"])
    end
    @warn "Value $v of environment variable $envvar is not a line count.  Using default of $default"
    default
end

