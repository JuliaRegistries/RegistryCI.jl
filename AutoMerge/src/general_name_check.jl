module GeneralNameCheck

using RegistryInstances: reachable_registries
using ..AutoMerge: meets_name_length, meets_name_ascii, meets_julia_name_check,
                   meets_name_match_check, meets_distance_check,
                   meets_name_is_identifier, meets_normal_capitalization

function @main(ARGS)
    if length(ARGS) != 1
        return fatal("Usage: general_name_check <Package Name>")
    end
    name = only(ARGS)
    general = get_general_registry()
    isnothing(general) && return fatal("Could not find the General registry.")
    run_name_checks(name, general)
    return 0
end

function get_general_registry()
    general_uuid = Base.UUID("23338594-aafe-5451-b93e-139f81909106")
    registries = filter(x -> x.uuid == general_uuid, reachable_registries())
    isempty(registries) && return nothing
    return only(registries)
end

const name_checks =
    [("Name is a valid identifier.",
      "Name is not a valid identifier:",
      (pkgname, _) -> meets_name_is_identifier(pkgname)),

     ("Name only contains ascii characters.",
      "Name contains non-ascii characters:",
      (pkgname, _) -> meets_name_ascii(pkgname)),

     ("Name is not already registered.",
      "Name matches registered package up to capitalization:",
      (pkgname, general) -> meets_name_match_check(pkgname, general)),

     ("Name is at least five characters.",
      "Name is shorter than five characters:",
      (pkgname, _) -> meets_name_length(pkgname)),

     ("Name passes julia redundancy check.",
      "Name fails julia redundancy check:",
      (pkgname, _) -> meets_julia_name_check(pkgname)),

     ("Name has normal capitalization.",
      "Name does not have normal capitalization:",
      (pkgname, _) -> meets_normal_capitalization(pkgname)),

     ("No name similarity found.",
      "Name similarities found:",
      (pkgname, general) ->
          meets_distance_check(pkgname, general;
                               comment_collapse_cutoff = typemax(Int)))]

function run_name_checks(pkgname, general)
    for (pass_message, fail_message, func) in name_checks
        passed, message = func(pkgname, general)
        if passed
            printstyled("✔", color = :green)
            println(" ", pass_message)
        else
            printstyled("✖", color = :red)
            println(" ", fail_message)
            println(extra_indent(message))
        end
    end
end

function fatal(message::AbstractString)
    printstyled(stderr, "ERROR: ", color = :red)
    println(stderr, message)
    return 1
end

function extra_indent(s, n = 2)
    return join(" "^n .* eachsplit(s, "\n"), "\n")
end

end

# Speed up the CLI by precompiling the main entry point.
precompile(Tuple{typeof(AutoMerge.GeneralNameCheck.main), Array{String, 1}})
