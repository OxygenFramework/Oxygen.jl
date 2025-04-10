module TestUtils
using Test

export has_property
export values_present
export value_absent
export value_count

"""
    values_present(dict, key, values)

Asserts that the passed dictionary both safely contains the specified key, 
and all the passed values are found in that collection. 
Collection may contain additional values.
"""
function values_present(dict, key, values)
    return haskey(dict, key) && all(x -> x in dict[key], values)
end

"""
    value_count(dict,key,value)
Returns occurence count of value in collection specified by key
"""
function value_count(dict, key, value)
    if(!haskey(dict,key))
        return 0
    end
    return count(x -> x == value,dict[key])
end

"""
    value_absent(dict, key, value)

Tests that specified value is not found in the collection referencecd
by the key on the dict, or that key's value in Dict is missing.
"""
function value_absent(dict, key, value)
    if (!haskey(dict, key))
        return true
    end
    return !any(x -> x == value, dict[key])
end

"""
    has_property(object, propertyName)

Test that generated OpenAPI schema object defintion has the specified property.
Safely check that `properties` key exists on dictionary first
"""
function has_property(object::Dict, propertyName::String)
    return haskey(object, "properties") && haskey(object["properties"], propertyName)
end

end # module