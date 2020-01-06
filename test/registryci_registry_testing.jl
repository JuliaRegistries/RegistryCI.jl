using Dates
using GitCommand
using GitHub
using JSON
using Pkg
using Printf
using RegistryCI
using Test
using TimeZones

const AutoMerge = RegistryCI.AutoMerge

const path = joinpath(DEPOT_PATH[1], "registries", "General")
RegistryCI.test(path)

# Test the BioJuliaRegistry
Pkg.Registry.add("https://github.com/BioJulia/BioJuliaRegistry.git")
# Test this will validate the BioJuliaRegistry, when providing General as an
# optional dependency. BJW.
RegistryCI.test(joinpath(DEPOT_PATH[1], "registries", "BioJuliaRegistry"), ["https://github.com/JuliaRegistries/General.git"])