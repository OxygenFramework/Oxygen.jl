module Extractors

using HTTP
using Dates
using StructTypes
# using CodeTracking: code_string
using ..Util: text, json, partialjson, parseparam, formdata, queryparams
using ..Reflection: struct_builder
using ..Types

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

struct PartialJson{T} <: FromRequestContent
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
        impl = Base.which(validate, (T,))
        throw(ArgumentError("Validation failed for $name: $T \n|> $instance \n|> $impl"))
    end
end

"""
Returns a function which is used to extract a JSON object from a request
and convert it into a custom struct
"""
function extractor(param::Param{Json{T}}, request::HTTP.Request) :: Json{T} where {T}
    instance = json(request, T)
    valid_instance = try_validate(param.name, instance)
    return Json{T}(valid_instance)
end

function extractor(param::Param{PartialJson{T}}, request::HTTP.Request) :: PartialJson{T} where {T}
    instance = partialjson(request, name, T)
    valid_instance = try_validate(param.name, instance)
    return PartialJson{T}(valid_instance)
end


"""
Returns a function which is used to extract the body from a request 
and convert it into a custom struct
"""
function extractor(param::Param{Body{T}}, request::HTTP.Request) :: Body{T} where {T}
    instance = parseparam(T, text(request); escape=false)
    valid_instance = try_validate(param.name, instance)
    return Body{T}(valid_instance)
end

"""
Returns a function which is used to extract a Form from a request
and convert it into a custom struct
"""
function extractor(param::Param{Form{T}}, request::HTTP.Request) :: Form{T} where {T}
    form = formdata(request)
    instance = struct_builder(T, form)
    valid_instance = try_validate(param.name, instance)
    return Form{T}(valid_instance) 
end

"""
Returns a function which is used to extract path parameters from a request
and convert it into a custom struct
"""
function extractor(param::Param{Path{T}}, request::HTTP.Request) :: Path{T} where {T}
    params = HTTP.getparams(request)
    instance = struct_builder(T, params)
    valid_instance = try_validate(param.name, instance)
    return Path{T}(valid_instance)
end

"""
Returns a function which is used to extract query parameters from a request
and convert it into a custom struct
"""
function extractor(param::Param{Query{T}}, request::HTTP.Request) :: Query{T} where {T}
    params = queryparams(request)
    instance = struct_builder(T, params)
    valid_instance = try_validate(param.name, instance)
    return Query{T}(valid_instance)
end

"""
Returns a function which is used to extract Headrs from a request
and convert it into a custom struct
"""
function extractor(param::Param{Header{T}}, headers::HTTP.Request) :: Header{T}  where {T}
    headers = Dict(string(k) => string(v) for (k,v) in HTTP.headers(request))
    instance = struct_builder(T, headers)
    valid_instance = try_validate(param.name, instance)
    return Header{T}(valid_instance)
end

end