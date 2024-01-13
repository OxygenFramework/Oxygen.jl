using Requires

function __init__()

    ################################################################
    #                       Templating Extensions                  #
    ################################################################
    @require Mustache="ffc61752-8dc7-55ee-8c37-f3e9cdd09e70" include("templating/mustache.jl")
    @require OteraEngine="b2d7f28f-acd6-4007-8b26-bc27716e5513" include("templating/oteraengine.jl")

end
