module RegistryCI

# import GitCommand

include("TagBot/TagBot.jl")
include("AutoMerge/AutoMerge.jl")
include("registry_testing.jl")
include("utils.jl")

end # module
