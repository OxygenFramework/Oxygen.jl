# JSON Schema generation for tool and prompt arguments.
# Included into `MCP.Serialization` by `../serialization.jl`.

# ----------------------------------------------------------------------------
# Shared helpers
# ----------------------------------------------------------------------------

# Copy any keyed container (`Dict`, `NamedTuple`, ...) into a `Dict{String,Any}`
# with stringified keys. The MCP wire layer accepts symbol- and string-keyed
# input uniformly, so validation and serialization normalize through here.
string_keyed(entries) :: Dict{String,Any} =
    Dict{String,Any}(String(key) => value for (key, value) in pairs(entries))

# ----------------------------------------------------------------------------
# Schema generation
# ----------------------------------------------------------------------------

# Rewrite the OpenAPI component refs emitted by `AutoDoc.convertobject!` into
# self-contained `$defs` refs (JSON Schema 2020-12).
function rewrite_refs!(value)
    if value isa AbstractDict
        for (key, item) in value
            if key == "\$ref" && item isa AbstractString
                value[key] = replace(item, "#/components/schemas/" => "#/\$defs/")
            else
                rewrite_refs!(item)
            end
        end
    elseif value isa AbstractVector
        for item in value
            rewrite_refs!(item)
        end
    end
    return value
end

"""
    typeschema(T) -> (schema, defs)

Build a self-contained JSON Schema fragment for the Julia type `T`. Any nested
struct definitions are returned in `defs` and referenced via `#/\$defs/<Name>`.
"""
function typeschema(T::Type)
    defs = Dict{String,Any}()
    nullable = AutoDoc.is_nullable_union(T)
    resolved = AutoDoc.resolve_union_type(T)

    if resolved === Union{} || resolved === Core.TypeofBottom
        resolved = T
    end

    schema = build_typeschema(resolved, defs)
    if nullable
        schema["nullable"] = true
    end
    return schema, defs
end

function build_typeschema(T::Type, defs::Dict{String,Any})
    T = AutoDoc.unwrap_type(T)

    if T isa Union
        return build_unionschema(T, defs)
    elseif T <: Enum
        # Enum names are the wire form (the JSON-body convention); integer
        # values stay an accepted input for backwards compatibility.
        return Dict{String,Any}(
            "type" => "string",
            "enum" => [string(instance) for instance in Base.Enums.instances(T)],
        )
    elseif AutoDoc.is_custom_struct(T)
        local_defs = Dict{String,Any}()
        AutoDoc.convertobject!(T, local_defs; enum_wire=:string)
        for (_, value) in local_defs
            rewrite_refs!(value)
        end
        merge!(defs, local_defs)
        return Dict{String,Any}("\$ref" => "#/\$defs/$(nameof(T))")
    elseif T <: AbstractArray
        elem = AutoDoc.get_element_type(T)
        item_schema, item_defs = typeschema(elem)
        merge!(defs, item_defs)
        return Dict{String,Any}("type" => "array", "items" => item_schema)
    elseif T <: AbstractDict
        schema = Dict{String,Any}("type" => "object")
        value_type = Reflection.dict_valtype(T)
        if value_type !== Any
            value_schema, value_defs = typeschema(value_type)
            merge!(defs, value_defs)
            schema["additionalProperties"] = value_schema
        end
        return schema
    else
        schema = Dict{String,Any}("type" => AutoDoc.gettype(T))
        format = AutoDoc.getformat(T)
        if !isnothing(format)
            schema["format"] = format
        end
        return schema
    end
end

# Schema for a Union type: one member keeps its schema (marked `nullable` when
# the union admits Nothing/Missing), several members become `anyOf`.
function build_unionschema(T::Union, defs::Dict{String,Any})
    members = Dict{String,Any}[]
    nullable = false

    for member in Base.uniontypes(T)
        if member === Nothing || member === Missing
            nullable = true
        else
            push!(members, build_typeschema(member, defs))
        end
    end

    if isempty(members)
        return Dict{String,Any}()
    end
    schema = length(members) == 1 ? members[1] : Dict{String,Any}("anyOf" => members)
    if nullable
        schema["nullable"] = true
    end
    return schema
end

function paramschema(p::MCPParam)
    schema, defs = typeschema(p.param.type)
    if !isempty(p.description)
        schema["description"] = p.description
    end
    if p.param.hasdefault
        default = p.param.default
        schema["default"] = default isa Enum ? string(default) : default
    end
    return schema, defs
end

"""
    inputschema(tool::MCPTool) :: Dict

The JSON Schema describing a tool's expected arguments. Built once at
registration (see `inputschema(::Vector{MCPParam})`) and cached on the tool: the
schema cannot change after registration, and regenerating it means re-reflecting
every custom struct parameter on every `tools/list`.
"""
inputschema(tool::MCPTool) :: Dict{String,Any} = tool.input_schema

function inputschema(params::Vector{MCPParam}) :: Dict{String,Any}
    if isempty(params)
        return Dict{String,Any}("type" => "object", "additionalProperties" => false)
    end

    properties = Dict{String,Any}()
    required = String[]
    defs = Dict{String,Any}()

    for p in params
        name = p.wirename
        schema, pdefs = paramschema(p)
        properties[name] = schema
        merge!(defs, pdefs)
        if isrequired(p.param)
            push!(required, name)
        end
    end

    result = Dict{String,Any}("type" => "object", "properties" => properties)
    if !isempty(required)
        result["required"] = required
    end
    if !isempty(defs)
        result["\$defs"] = defs
    end
    return result
end
