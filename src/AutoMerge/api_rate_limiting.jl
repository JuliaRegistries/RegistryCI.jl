function my_retry(f::Function, num_retries::Integer = 1)
    result = retry(f, delays=ExponentialBackOff(n=num_retries))()
    return result
end

function my_retry_suppress_exceptions(f::Function, num_retries::Integer = 1)
    result = try
        my_retry(f, num_retries)
    catch ex
        showerror(stderr, ex)
        Base.show_backtrace(stderr, catch_backtrace())
        println(stderr)
        nothing
    end
    return result
end
