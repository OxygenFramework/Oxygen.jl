module Util 

    export countargs, getvarname, getvartype

    # Count the number of args in a functions signature
    function countargs(func::Function)
        local method = first(methods(func))
        return length(method.sig.parameters) - 1
    end

    function getvarname(key)
        return lowercase(split(key, ":")[1])
    end

    function getvartype(value)
        variableType = lowercase(split(value, ":")[2])
        typeconverters = [
            ("int", Int64),
            ("float", Float64),
            ("bool", Bool)
        ]
        for (name, type) in typeconverters
            if variableType == name
                return (x) -> parse(type, x)
            end
        end
        return (x) -> x
    end

end

