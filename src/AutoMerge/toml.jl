function maybe_parse_toml(directory::AbstractString, file::AbstractString)
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
    full_path = joinpath(directory, file)
    if !ispath(full_path)
        @warn "TOML file does not exist; returning an empty dict" directory file full_path
        return Dict()
    end
    return Pkg.TOML.parsefile(full_path)
end
