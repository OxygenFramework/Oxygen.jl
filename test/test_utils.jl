module TestUtils
using Test

export values_present
export value_absent
export has_property
export json_response_contains

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

"""
    json_response_contains(path_object, method, response_vals)

Test that the 200 response of type `application/json` schema contains all the properties in `response_vals`
It may contain additional properties  
"""
function json_response_contains(path_object, method, response_vals)
    test_response = path_object[lowercase(method)]["responses"]["200"]["content"]["application/json"]["schema"]
    for (key,value) in response_vals
        if(test_response[key] != value)
            throw(AssertionError("Expected $key to be $value (actually $test_response[$key])"))
        end
    end
    return true
end

end # module