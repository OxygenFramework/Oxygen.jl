# RFC 6570 URI-template parsing and matching for resource registrations.
# Included into `MCP.Resources` by `../resources.jl`.

# ----------------------------------------------------------------------------
# URI templates (RFC 6570: simple `{var}` and reserved `{+var}` expansion)
# ----------------------------------------------------------------------------

# Template expressions are matched whole so nested/operator forms (`{?var}`,
# `{#var}`, `{var*}`) fall through to the validation errors below. The `+` of a
# reserved expansion is the only operator accepted.
const TEMPLATE_EXPRESSION = r"\{([^{}]*)\}"

# Template variables double as handler argument names, so they must be valid
# Julia identifiers. The optional leading `+` selects reserved expansion.
const TEMPLATE_VARIABLE = r"^(\+?)([A-Za-z_][A-Za-z0-9_]*)\z"

# One validated template expression: `name` is the bare variable name and
# `reserved` records whether the `+` operator was used.
struct TemplateVariable
    name     :: String
    reserved :: Bool
end

"""
    template_variables(uri) :: Vector{TemplateVariable}

Parse an MCP resource URI template, in order. Simple `{var}` expansions capture
a single path segment (RFC 6570 percent-encodes `/` inside the value); reserved
`{+var}` expansions capture across `/`, so nested paths can be served. Anything
else (other operators, empty names, unbalanced braces) is rejected with an
`ArgumentError`.
"""
function template_variables(uri::String)::Vector{TemplateVariable}
    variables = TemplateVariable[]
    for matched in eachmatch(TEMPLATE_EXPRESSION, uri)
        expression = String(matched.captures[1])
        parsed = match(TEMPLATE_VARIABLE, expression)
        if isnothing(parsed)
            throw(ArgumentError(
                "Invalid MCP resource template expression `{$expression}`: only simple " *
                "`{name}` and reserved `{+name}` expansions with identifier-safe names are supported"))
        end
        name = String(parsed.captures[2])
        reserved = !isempty(parsed.captures[1])
        if any(variable -> variable.name == name, variables)
            throw(ArgumentError("Duplicate MCP resource template variable `{$name}`"))
        end
        push!(variables, TemplateVariable(name, reserved))
    end

    # Whatever text the expressions leave behind decides whether the braces were
    # balanced: `{a{b}}` still carries a `{` once `{b}` is removed.
    remainder = replace(uri, TEMPLATE_EXPRESSION => "")
    if occursin('{', remainder) || occursin('}', remainder)
        throw(ArgumentError("Malformed MCP resource template URI `$uri`: unbalanced braces"))
    end

    return variables
end

"""
    template_vars(uri) :: Vector{String}

The variable names of a resource URI template, in order. See `template_variables`
for the full parse.
"""
template_vars(uri::String)::Vector{String} = [variable.name for variable in template_variables(uri)]

function escape_regex(literal::AbstractString)::String
    return replace(literal, r"([\\^$.|?*+()\[\]{}])" => s"\\\1")
end

# Compile a template into an anchored regex whose positional capture groups
# correspond, in order, to `variables`. Literal segments are matched verbatim; a
# simple variable captures a single path segment (RFC 6570 encodes `/` inside the
# value), while a reserved variable captures any run (`.+`), so an empty path
# cannot match. Greedy reserved captures resolve multiple-variable templates
# against the last possible separator, which is deterministic.
function compile_template(uri::String, variables::Vector{TemplateVariable})::Regex
    buffer = IOBuffer()
    write(buffer, "^")
    position = 1
    for (matched, variable) in zip(eachmatch(TEMPLATE_EXPRESSION, uri), variables)
        write(buffer, escape_regex(uri[position:(matched.offset - 1)]))
        write(buffer, variable.reserved ? "(.+)" : "([^/]+)")
        position = matched.offset + ncodeunits(matched.match)
    end
    write(buffer, escape_regex(uri[position:end]))
    write(buffer, "\$")
    return Regex(String(take!(buffer)))
end

"""
    match_template(resource, uri) :: Union{Nothing,Dict{String,Any}}

Match a requested URI against a registered template, returning the decoded
template variables as a client-argument dictionary, or `nothing` when the URI
does not fit the template.
"""
function match_template(resource::MCPResource, uri::String)::Union{Nothing,Dict{String,Any}}
    pattern = resource.pattern
    if isnothing(pattern)
        return nothing
    end

    matched = match(pattern, uri)
    if isnothing(matched)
        return nothing
    end

    arguments = Dict{String,Any}()
    for (index, variable) in enumerate(resource.vars)
        capture = try
            HTTP.unescapeuri(matched.captures[index])
        catch
            # A malformed percent-escape (`%`, `%2`, `%zz`, ...) cannot name
            # this resource; leave it unmatched so the read ends as the era's
            # not-found error instead of crashing the request.
            return nothing
        end
        arguments[variable] = capture
    end
    return arguments
end

