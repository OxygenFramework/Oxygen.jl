# Standard setup script for running isolated Oxygen tests ou starting repl with development environment to test code
# Usage: run in repl: julia -t auto --project=test/dev_project -i test/common_setup.jl
#    or use this setup in a specific file: julia -t auto --project=test/dev_project test/extensions/cryptotests.jl

using Pkg

# The project is already activated via --project=test
# Ensure Oxygen points to the local source
# We use absolute path derived from the script location to avoid CWD issues
project_root = dirname(@__DIR__)
Pkg.develop(PackageSpec(path=project_root))
Pkg.instantiate()

# Load common test modules
using Test
using Oxygen
using Dates
using JSON
using HTTP

# Include project-specific test utilities
include("test_utils.jl")
using .TestUtils

# Helper to trigger extensions
# Usage: trigger_extension("OpenSSL")
function trigger_extension(pkg_name::String)
    eval(Meta.parse("using $pkg_name"))
    println("Triggered extension for $pkg_name")
end

println("✓ Test environment initialized with project from test/Project.toml")

