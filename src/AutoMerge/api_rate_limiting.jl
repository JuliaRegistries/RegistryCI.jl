function my_retry(f::Function; n=1, first_delay=10, factor=2, kwargs...)
    result = retry(f; delays=ExponentialBackOff(; n=n, first_delay=first_delay, factor=factor, kwargs...))()
    return result
end

function my_retry_suppress_exceptions(f::Function; kwargs...)
    result = try
        my_retry(f; kwargs...)
    catch ex
        showerror(stderr, ex)
        Base.show_backtrace(stderr, catch_backtrace())
        println(stderr)
        nothing
    end
    return result
end
