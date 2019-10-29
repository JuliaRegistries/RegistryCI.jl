struct AlwaysAssertionError <: Exception
    msg::AbstractString
end
AlwaysAssertionError() = AlwaysAssertionError("")

# The documentation for the `@assert` macro says: "Warning: An assert might be
# disabled at various optimization levels."
# Therefore, we have the `@always_assert` macro. `@always_assert` is like
# `@assert`, except that `@always_assert` will always run and will never be
# disabled.
macro always_assert(ex)
    result = quote
        if $(ex)
            nothing
        else
            throw(AlwaysAssertionError($(string(ex))))
        end
    end
    return result
end
