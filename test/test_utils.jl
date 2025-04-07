module TestUtils
using Test

export @test_has_key_and_values

"""
    test_has_key_and_values(dict, key, values)

Asserts that the passed dictionary both safely contains the specified key, and the value
of that field is a collection which contains all of the passed values. 
It may contain more additional values.
"""
macro test_has_key_and_values(dict, key, values)
    quote
        local keyVal = $(esc(key))
        local dictVal = $(esc(dict))
        local testValues = $(esc(values))
        @test haskey(dictVal, keyVal)
        @test all( x -> x in dictVal[keyVal], testValues)
    end
end

end # module