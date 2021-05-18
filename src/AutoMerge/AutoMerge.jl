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
import LicenseCheck
import TOML
import Printf
import RegistryTools
import ..RegistryCI
import Tar

include("types.jl")
include("ciservice.jl")

include("api_rate_limiting.jl")
include("assert.jl")
include("automerge_comment.jl")
include("changed_files.jl")
include("cron.jl")
include("dependency_confusion.jl")
include("github.jl")
include("guidelines.jl")
include("jll.jl")
include("not_automerge_applicable.jl")
include("package_path_in_registry.jl")
include("public.jl")
include("pull_requests.jl")
include("semver.jl")
include("update_status.jl")
include("util.jl")

end # module
