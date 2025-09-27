function parse_registry_toml(registry_dir, path_components...; allow_missing = false)
    path = joinpath(registry_dir, path_components...)
    isfile(path) && return TOML.parsefile(path)
    allow_missing && return Dict{String, Any}()
    error("Registry file $path does not exist in $(registry_dir).")
end
