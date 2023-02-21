function assert_allowed_to_not_exist(full_path::AbstractString)
    file = basename(full_path)
    allowed_filenames = (
        "Compat.toml",
        "WeakCompat.toml",
        "Deps.toml",
        "WeakDeps.toml",
    )
    if !(file in allowed_filenames)
        msg = "Filename is not in the allowed list: $(file)"
        throw(ErrorException(msg))
    end
    return nothing
end

maybe_parse_toml(f::AbstractString) = ispath(f) ? Pkg.TOML.parsefile(f) : Dict{String, Any}()
