function throw_not_automerge_applicable(::Type{EXCEPTION_TYPE},
                                        message::String;
                                        error_exit_if_automerge_not_applicable::Bool) where {EXCEPTION_TYPE}
    try
        throw(EXCEPTION_TYPE(message))
    catch ex
        @error "" exception=(ex, catch_backtrace())
        if error_exit_if_automerge_not_applicable
            rethrow()
        end
    end
    return nothing
end
