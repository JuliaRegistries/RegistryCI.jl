import RegistryCI
const path = joinpath(DEPOT_PATH[1], "registries", "General")
RegistryCI.test(path)
include("automerge-runtests.jl")
