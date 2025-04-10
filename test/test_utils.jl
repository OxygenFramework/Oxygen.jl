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
    esc(quote
        @test haskey($dict, $key)
        @test all( x -> x in $dict[$key], $values)
    end)
end

end # module