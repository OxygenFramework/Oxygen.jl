using Requires

################################################################
#                       Templating Plugins                     #
################################################################

function __init__()
    @require Mustache="ffc61752-8dc7-55ee-8c37-f3e9cdd09e70" begin
        include("templating/mustache.jl"); using .MustacheTemplating
        export mustache
    end
    
    @require OteraEngine="b2d7f28f-acd6-4007-8b26-bc27716e5513" begin
        include("templating/oteraengine.jl"); using .OteraEngineTemplating
        export otera
    end
end
