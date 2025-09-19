module RegistryCI

# import GitCommand

include("TagBot/TagBot.jl")
include("AutoMerge/AutoMerge.jl")
include("utils.jl")

# Re-export the test function from RegistryTesting subpackage
# Note: RegistryTesting is included as a subdir dependency
import RegistryTesting

const test = RegistryTesting.test
const load_registry_dep_uuids = RegistryTesting.load_registry_dep_uuids

end # module
