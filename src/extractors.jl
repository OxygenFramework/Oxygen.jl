module Extractors

using HTTP
using Dates
using CodeTracking: code_string
using ..Util: text, json, parseparam, formdata, queryparams
using ..Reflection: struct_builder

export Extractor, FromRequestParts, FromRequestContent,
        Path, Query, Header, Json, Form, Body,
        extractor, validate

abstract type Extractor end
abstract type FromRequestParts <: Extractor end
abstract type FromRequestContent <: Extractor end

## RequestParts Extractors

struct Path{T} <: FromRequestParts
    payload::T
end

struct Query{T} <: FromRequestParts
    payload::T
end

struct Header{T} <: FromRequestParts
    payload::T
end

## RequestContent Extractors

struct Json{T} <: FromRequestContent
    payload::T
end

struct Form{T} <: FromRequestContent
    payload::T
end

struct Body{T} <: FromRequestContent
    payload::T
end

# Generic validation function - if no validate function is defined for a type, return true
validate(type::T) where {T} = true

function try_validate(name::Symbol, instance::T) :: T where {T}
    if validate(instance)
        return instance
    else
        # Figure out which validator failed and convert the function to a string
        impl = code_string(validate, (T,))
        throw(ArgumentError("Validation failed for $name: $T \n|> $instance \n|> $impl"))
    end
end

"""
Returns a function which is used to extract a JSON object from a request
and convert it into a custom struct
"""
function extractor(::Type{Json{T}}, name::Symbol) :: Function where {T}
    return function extract(request::HTTP.Request) :: Json{T} 
        instance = json(request, T)
        valid_instance = try_validate(name, instance)
        return Json{T}(valid_instance)
    end
end

"""
Returns a function which is used to extract the body from a request 
and convert it into a custom struct
"""
function extractor(::Type{Body{T}}, name::Symbol) :: Function where {T}
    return function extract(request::HTTP.Request) :: Body{T} 
        instance = parseparam(T, text(request); escape=false)
        valid_instance = try_validate(name, instance)
        return Body{T}(valid_instance)
    end
end

"""
Returns a function which is used to extract a Form from a request
and convert it into a custom struct
"""
function extractor(::Type{Form{T}}, name::Symbol) :: Function where {T}
    builder = struct_builder(T)
    return function extract(request::HTTP.Request) :: Form{T} 
        form = formdata(request)
        instance = builder(form)
        valid_instance = try_validate(name, instance)
        return Form{T}(valid_instance)
    end
end

"""
Returns a function which is used to extract path parameters from a request
and convert it into a custom struct
"""
function extractor(::Type{Path{T}}, name::Symbol) :: Function where {T}
    builder = struct_builder(T)
    return function extract(request::HTTP.Request) :: Path{T} 
        params = HTTP.getparams(request)
        instance = builder(params)
        valid_instance = try_validate(name, instance)
        return Path{T}(valid_instance)
    end
end

"""
Returns a function which is used to extract query parameters from a request
and convert it into a custom struct
"""
function extractor(::Type{Query{T}}, name::Symbol) :: Function where {T}
    builder = struct_builder(T)
    return function extract(request::HTTP.Request) :: Query{T} 
        params = queryparams(request)
        instance = builder(params)
        valid_instance = try_validate(name, instance)
        return Query{T}(valid_instance)
    end
end

"""
Returns a function which is used to extract Headrs from a request
and convert it into a custom struct
"""
function extractor(::Type{Header{T}}, name::Symbol) :: Function where {T}
    builder = struct_builder(T)
    return function extract(request::HTTP.Request) :: Header{T} 
        params = Dict(string(k) => string(v) for (k,v) in HTTP.headers(request))
        instance = builder(params)
        valid_instance = try_validate(name, instance)
        return Header{T}(valid_instance)
    end
end



end