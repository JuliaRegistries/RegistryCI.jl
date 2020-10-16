module AutoMerge

import Dates
# import GitCommand
import GitHub
import HTTP
import LibGit2
import Pkg
import TimeZones
import JSON
import VisualStringDistances
import StringDistances
import TOML
import Printf
import RegistryTools
import ..RegistryCI

include("assert.jl")

include("types.jl")

include("ciservice.jl")
include("public.jl")

include("api_rate_limiting.jl")
include("automerge_comment.jl")
include("changed_files.jl")
include("cron.jl")
include("github.jl")
include("guidelines.jl")
include("jll.jl")
include("new-package.jl")
include("new-version.jl")
include("pull-requests.jl")
include("semver.jl")
include("util.jl")

end # module
