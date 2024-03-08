module RunTests 

include("constants.jl"); using .Constants

include("metricstests.jl")
include("templatingtests.jl")
include("routingfunctionstests.jl")
include("rendertests.jl")
include("cairomakietests.jl")
include("wglmakietests.jl")
include("bonitotests.jl")
include("bodyparsertests.jl")
include("crontests.jl")
include("oxidise.jl")
include("instancetests.jl")
include("paralleltests.jl")
include("taskmanagement.jl")
include("cronmanagement.jl")
include("originaltests.jl")

end 
