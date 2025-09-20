module RegistryCI

# import GitCommand

include("registry_testing.jl")
include("utils.jl")

# Give a nicer warning to users for the big move in v11
struct MovedFunctionality
    name::String
end
struct MovedFunctionalityException <: Exception
    msg::String
end
Base.showerror(io::IO, e::MovedFunctionalityException) = print(io, "MovedFunctionalityException: ", e.msg)

const AutoMerge = MovedFunctionality("AutoMerge")
const TagBot = MovedFunctionality("TagBot")
function throw_error(a::MovedFunctionality)
    name = getfield(a, :name)
    if name == "AutoMerge"
        throw(MovedFunctionalityException("RegistryCI.AutoMerge has been moved to its own package, AutoMerge.jl. The API of AutoMerge v1.0 matches that of RegistryCI.AutoMerge v10.10.4."))
    elseif name == "TagBot"
        throw(MovedFunctionalityException("RegistryCI.TagBot has been moved to a new package, AutoMerge.jl. The API of AutoMerge.TagBot v1.0 matches that of RegistryCI.TagBot v10.10.4."))
    else
        @assert false
    end
end

Base.getproperty(a::MovedFunctionality, ::Symbol) = throw_error(a)
Base.show(::IO, a::MovedFunctionality) = throw_error(a)
end # module
