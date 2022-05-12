module Util 

    # Count the number of args in a functions signature
    function countargs(func::Function)
        local method = first(methods(func))
        return length(method.sig.parameters) - 1
    end

end