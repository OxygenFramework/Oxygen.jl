module Extractors

using Base: @kwdef
using HTTP
using Dates
using StructTypes

using ..Util: text, json, partialjson, formdata, parseparam
using ..Reflection: struct_builder
using ..Types

export Extractor, extract, validate, extracttype,
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
        
            # Pass Type for payload
            $(Symbol(class_name))(::Type{T}) where T = new{T}(nothing, nothing, T)
            $(Symbol(class_name)){T}(::Type{T}) where T = new{T}(nothing, nothing, T)

            # Pass Type for payload & validator
            $(Symbol(class_name))(::Type{T}, f::Function) where T = new{T}(nothing, f, T)
            $(Symbol(class_name)){T}(::Type{T}, f::Function) where T = new{T}(nothing, f, T)

            # Pass object directly
            $(Symbol(class_name))(payload::T) where T = new{T}(payload, nothing, T)
            $(Symbol(class_name)){T}(payload::T) where T = new{T}(payload, nothing, T)

            # Pass object directly & validator
            $(Symbol(class_name))(payload::T, f::Function) where T = new{T}(payload, f, T)
            $(Symbol(class_name)){T}(payload::T, f::Function) where T = new{T}(payload, f, T)
        end
    end |> esc
end

function extracttype(::Type{U}) where {T, U <: Extractor{T}}
    return T
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
Extracts a JSON object from a request and converts it into a custom struct
"""
function extract(param::Param{Json{T}}, request::LazyRequest) :: Json{T} where {T}
    instance = json(request.request, T; content=textbody(request))
    valid_instance = try_validate(param.name, instance)
    return Json{T}(valid_instance)
end


"""
Extracts a part of a json object from the body of a request and converts it into a custom struct
"""
function extract(param::Param{JsonFragment{T}}, request::LazyRequest) :: JsonFragment{T} where {T}
    body = Types.jsonbody(request)[param.name]
    instance = struct_builder(T, body)
    valid_instance = try_validate(param.name, instance)
    return JsonFragment{T}(valid_instance)
end


"""
Extracts the body from a request and convert it into a custom type
"""
function extract(param::Param{Body{T}}, request::LazyRequest) :: Body{T} where {T}
    instance = parseparam(T, textbody(request); escape=false)
    valid_instance = try_validate(param.name, instance)
    return Body{T}(valid_instance)
end

"""
Extracts a Form from a request and converts it into a custom struct
"""
function extract(param::Param{Form{T}}, request::LazyRequest) :: Form{T} where {T}
    form = Types.formbody(request)
    instance = struct_builder(T, form)
    valid_instance = try_validate(param.name, instance)
    return Form{T}(valid_instance) 
end

"""
Extracts path parameters from a request and convert it into a custom struct
"""
function extract(param::Param{Path{T}}, request::LazyRequest) :: Path{T} where {T}
    params = Types.pathparams(request)
    instance = struct_builder(T, params)
    valid_instance = try_validate(param.name, instance)
    return Path{T}(valid_instance)
end

"""
Extracts query parameters from a request and convert it into a custom struct
"""
function extract(param::Param{Query{T}}, request::LazyRequest) :: Query{T} where {T}
    params = Types.queryvars(request)
    instance = struct_builder(T, params)
    valid_instance = try_validate(param.name, instance)
    return Query{T}(valid_instance)
end

"""
Extracts Headers from a request and convert it into a custom struct
"""
function extract(param::Param{Header{T}}, request::LazyRequest) :: Header{T}  where {T}
    headers = Types.headers(request)
    instance = struct_builder(T, headers)
    valid_instance = try_validate(param.name, instance)
    return Header{T}(valid_instance)
end

end