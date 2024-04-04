module RunTests 

include("constants.jl"); using .Constants

#### Extension Tests ####

include("extensions/templatingtests.jl")
include("extensions/cairomakietests.jl")
include("extensions/wglmakietests.jl")
include("extensions/bonitotests.jl")
include("extensions/protobuf/protobuftests.jl")

#### Sepcial Handler Tests ####

include("ssetests.jl")
include("websockettests.jl")
include("streamingtests.jl")
include("handlertests.jl")

#### Core Tests ####

include("shadowingtests.jl")
include("metricstests.jl")
include("routingfunctionstests.jl")
include("rendertests.jl")
include("bodyparsertests.jl")
include("crontests.jl")
include("oxidise.jl")
include("instancetests.jl")
include("paralleltests.jl")
include("taskmanagement.jl")
include("cronmanagement.jl")
include("originaltests.jl")

end 
