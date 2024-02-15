module Constants
using RelocatableFolders
export DATA_PATH

# Generate a reliable path to our internal data folder that works when the 
# package is used with PackageCompiler.jl
const DATA_PATH = @path abspath(joinpath(@__DIR__, "..", "data"))

end