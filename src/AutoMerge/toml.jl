function maybe_parse_toml(full_path::AbstractString)
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
    return ispath(full_path) ? Pkg.TOML.parsefile(full_path) : Dict{String, Any}()
end
