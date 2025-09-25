const _toml_cache = Dict{String, Any}()

# Cache parsed toml files for efficiency.
# Important: Do not mutate the returned data, as it will corrupt the cache.
function parse_registry_toml(registry_dir, path_components...; allow_missing = false)
    path = joinpath(registry_dir, path_components...)
    get!(_toml_cache, path) do
        if isfile(path)
            TOML.parsefile(path)
        elseif allow_missing
            Dict{String, Any}()
        else
            error("Registry file $path does not exist in $(registry_dir).")
        end
    end
end
