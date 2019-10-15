import GeneralRegistryCI
const path = joinpath(DEPOT_PATH[1], "registries", "General")
GeneralRegistryCI.test(path)
include("automerge-runtests.jl")
