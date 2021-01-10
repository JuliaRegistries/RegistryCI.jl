function throw_not_automerge_applicable(::Type{E},
                                        condition::Bool,
                                        message::String;
                                        error_exit_if_automerge_not_applicable::Bool) where {E}
    if condition
        try
            throw(E(message))
        catch ex
            @error "" exception=(ex, catch_backtrace())
            if error_exit_if_automerge_not_applicable
                rethrow()
            end
        end
    end
    return nothing
end
