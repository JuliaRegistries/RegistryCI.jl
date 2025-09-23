maybe_parse_toml(f::AbstractString) = ispath(f) ? Pkg.TOML.parsefile(f) : Dict{String, Any}()
