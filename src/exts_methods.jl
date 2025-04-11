# This file is where extension methods are coupled to global state

function setup_bonito_connection(; kwargs...)
    Oxygen.setup_bonito_connection(CONTEXT[]; kwargs...)
end
