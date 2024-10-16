module Extractors

using JSON3
using Base: @kwdef
using HTTP
using Dates
using StructTypes

using ..Util: text, json, formdata, parseparam
using ..Reflection: struct_builder, extract_struct_info
using ..Errors: ValidationError
using ..Types

export Extractor, extract, validate, extracttype, isextractor, isreqparam, isbodyparam,
    Path, Query, Header, Json, JsonFragment, Form, Body

abstract type Extractor{T} end

"""
Given a classname, build a new Extractor class
"""
macro extractor(class_name)
    quote
        struct $(Symbol(class_name)){T} <: Extractor{T} 
            payload::Union{T, Nothing}
            validate::Union{Function, Nothing}
            type::Type{T}
        
            # Only pass a validator
            $(Symbol(class_name)){T}(f::Function) where T = new{T}(nothing, f, T)

            # Pass Type for payload
            $(Symbol(class_name))(::Type{T}) where T = new{T}(nothing, nothing, T)

            # Pass Type for payload & validator
            $(Symbol(class_name))(::Type{T}, f::Function) where T = new{T}(nothing, f, T)

            # Pass object directly
            $(Symbol(class_name))(payload::T) where T = new{T}(payload, nothing, T)

            # Pass object directly & validator
            $(Symbol(class_name))(payload::T, f::Function) where T = new{T}(payload, f, T)
            
        end
    end |> esc
end

## RequestParts Extractors

@extractor Path
@extractor Query
@extractor Header

## RequestContent Extractors

@extractor Json
@extractor JsonFragment
@extractor Form
@extractor Body

function extracttype(::Type{U}) where {T, U <: Extractor{T}}
    return T
end

function isextractor(::Param{T}) where {T}
    return T <: Extractor
end

function isreqparam(::Param{U}) where {T, U <: Extractor{T}}
    return U <: Union{Path{T}, Query{T}, Header{T}}
end

function isbodyparam(::Param{U}) where {T, U <: Extractor{T}}
    return U <: Union{Json{T}, JsonFragment{T}, Form{T}, Body{T}}
end

# Generic validation function - if no validate function is defined for a type, return true
validate(type::T) where {T} = true

"""
This function will try to validate an instance of a type using both global and local validators. 
If both validators pass, the instance is returned. If either fails, an ArgumentError is thrown.
"""
function try_validate(param::Param{U}, instance::T) :: T where {T, U <: Extractor{T}}

    # Case 1: Use global validate function - returns true if one isn't defined for this type
    if !validate(instance)
        impl = Base.which(validate, (T,))
        throw(ValidationError("Validation failed for $(param.name): $T \n|> $instance \n|> $impl"))   
    end

    # Case 2: Use custom validate function from an Extractor (if defined)
    if param.hasdefault && param.default isa U && !isnothing(param.default.validate)
        if !param.default.validate(instance)
            impl = Base.which(param.default.validate, (T,))
            throw(ValidationError("Validation failed for $(param.name): $T \n|> $instance \n|> $impl"))
        end
    end
    
    return instance
end

"""
A helper utility function to safely extract data from a function. If the function fails, a ValidationError is thrown
which is caught and results with a 400 status code.
"""
function safe_extract(f::Function, param::Param{U}) :: T where {T, U <: Extractor{T}} 
    try 
        return f()
    catch
        throw(ValidationError("Failed to serialize data for | parameter: $(param.name) | extractor: $U | type: $T"))
    end
end

"""
Extracts a JSON object from a request and converts it into a custom struct
"""
function extract(param::Param{Json{T}}, request::LazyRequest) :: Json{T} where {T}
    instance = safe_extract(param) do 
        JSON3.read(textbody(request), T) 
    end
    valid_instance = try_validate(param, instance)
    return Json(valid_instance)
end

"""
Extracts a part of a json object from the body of a request and converts it into a custom struct
"""
function extract(param::Param{JsonFragment{T}}, request::LazyRequest) :: JsonFragment{T} where {T}
    body = Types.jsonbody(request)[param.name]
    instance = safe_extract(param) do 
        struct_builder(T, body) 
    end
    valid_instance = try_validate(param, instance)
    return JsonFragment(valid_instance)
end

"""
Extracts the body from a request and convert it into a custom type
"""
function extract(param::Param{Body{T}}, request::LazyRequest) :: Body{T} where {T}
    instance = safe_extract(param) do 
        parseparam(T, textbody(request); escape=false) 
    end
    valid_instance = try_validate(param, instance)
    return Body(valid_instance)
end

"""
Extracts a Form from a request and converts it into a custom struct
"""
function extract(param::Param{Form{T}}, request::LazyRequest) :: Form{T} where {T}
    form = Types.formbody(request)
    instance = safe_extract(param) do 
        struct_builder(T, form) 
    end
    valid_instance = try_validate(param, instance)
    return Form(valid_instance) 
end

"""
Extracts path parameters from a request and convert it into a custom struct
"""
function extract(param::Param{Path{T}}, request::LazyRequest) :: Path{T} where {T}
    params = Types.pathparams(request)
    instance = safe_extract(param) do 
        struct_builder(T, params) 
    end
    valid_instance = try_validate(param, instance)
    return Path(valid_instance)
end

"""
Extracts query parameters from a request and convert it into a custom struct
"""
function extract(param::Param{Query{T}}, request::LazyRequest) :: Query{T} where {T}
    params = Types.queryvars(request)
    instance = safe_extract(param) do 
        struct_builder(T, params) 
    end
    valid_instance = try_validate(param, instance)
    return Query(valid_instance)
end

"""
Extracts Headers from a request and convert it into a custom struct
"""
function extract(param::Param{Header{T}}, request::LazyRequest) :: Header{T}  where {T}
    headers = Types.headers(request)
    instance = safe_extract(param) do 
        struct_builder(T, headers) 
    end
    valid_instance = try_validate(param, instance)
    return Header(valid_instance)
end

end