module TestUtils
using Test

export values_present
export value_absent

"""
    values_present(dict, key, values)

Asserts that the passed dictionary both safely contains the specified key, 
and all the passed values are found in that collection. 
Collection may contain additional values.
"""
function values_present(dict, key, values)
    return haskey(dict, key) && all( x -> x in dict[key], values)
end

"""
    value_absent(dict, key, value)

Tests that specified value is not found in the collection referencecd
by the key on the dict, or that key's value in Dict is missing.
"""
function value_absent(dict, key, value)
    if(!haskey(dict, key))
        return true
    end
    return !any( x -> x == value, dict[key])
end

end # module