module Instances

using RelocatableFolders

export instance


function escape_path_if_windows(path::String)
    return Sys.iswindows() ? replace(path, "\\" => "\\\\") : path
end

function fullpath(path::AbstractString) :: String
    absolute_path = @path abspath(joinpath(@__DIR__, path))
    return absolute_path |> String |> escape_path_if_windows
end

function extract_filename(include_str::String, include_regex::Regex)
    # Regular expression to match the pattern include("filename")
    match_result = match(include_regex, include_str)
    if match_result !== nothing
        return match_result.captures[1]  # Return the captured filename
    end
end

function preprocess_includes(content::String, include_regex::Regex = r"include\(\"(.*)\"\)")

    # Function to replace include calls with absolute paths
    function replace_include(match)
        # Extract the path from the match
        path = extract_filename(String(match), include_regex)
        absolute_path = fullpath(path)
        # Return the updated include call
        return "include(\"$absolute_path\")"
    end

    # Replace all include calls in the content
    return replace(content, include_regex => replace_include)
end

"""
    load(path::String)

Load a module from a file specified by `path`. The file should define a module.
The module is loaded into the current scope under the name `custom_module`.
"""

function load(path::String)

    absolute_path = fullpath(path)

    !isfile(absolute_path) && throw("not a valid file")
    
    # Read the file content
    content = read(absolute_path, String)

    # Preprocess includes to adjust paths
    processed_content = preprocess_includes(content)

    quote
        # Execute the preprocessed content
        custom_module = include_string(@__MODULE__, $(processed_content))
        using .custom_module
    end
end


"""
    instance()
Create a new self-containedinstance of the Oxygen module. 
This done by creating a new unique module at runtime and loading the Oxygen module into it.
This results in a unique instance of the Oxygen module that can be used independently.
"""
function instance()
    # Create the module definition with the macro call for the function definition
    mod_def = Expr(:module, false, gensym(),
        Expr(:block,
            :(using Base),
            load("Oxygen.jl")
        )
    )
    # Evaluate the module definition to actually create it
    return eval(mod_def)
end


end