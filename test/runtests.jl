module RunTests 

include("constants.jl"); using .Constants

#### Extension Tests ####

include("extensions/templatingtests.jl")
include("extensions/protobuf/protobuftests.jl")
include("extensions/cairomakietests.jl")
include("extensions/wglmakietests.jl")
include("extensions/bonitotests.jl")

#### Sepcial Handler Tests ####

include("ssetests.jl") # Causing issues
include("websockettests.jl")
include("streamingtests.jl")
include("handlertests.jl")

# #### Core Tests ####
include("test_reexports.jl")
include("precompilationtest.jl")
include("extractortests.jl")
include("reflectiontests.jl")
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
include("middlewaretests.jl")
include("originaltests.jl")

#### Scenario Tests ####
include("./scenarios/thunderingherd.jl")

end 
