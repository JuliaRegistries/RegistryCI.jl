function maybe_parse_toml(full_path::AbstractString)
    file = basename(pathfull_path)
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
    if !ispath(full_path)
        @warn "TOML file does not exist; returning an empty dict" directory file full_path
        return Dict()
    end
    return Pkg.TOML.parsefile(full_path)
end
