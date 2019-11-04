struct AlwaysAssertionError <: Exception
    msg::String
end
AlwaysAssertionError() = AlwaysAssertionError("")

# The documentation for the `@assert` macro says: "Warning: An assert might be
# disabled at various optimization levels."
# Therefore, we have the `always_assert` function. `always_assert` is like
# `@assert`, except that `always_assert` will always run and will never be
# disabled.
function always_assert(cond::Bool)
    cond || throw(AlwaysAssertionError())
    return nothing
end
