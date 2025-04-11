"""
This module holds all the partial function & struct definitions for all package extensions
"""

export ProtoBuffer, protobuf
export mustache, otera
export png, svg, pdf
export setup_bonito_connection, mk_bonito_websocket_handler

# Serialization extension definitions
function protobuf end
struct ProtoBuffer{T} <: Extractor{T}
    payload::T
end

# Templating extension definitions
function mustache end
function otera end

# Plotting extension definitions
function png end
function svg end
function pdf end

# Bonito extension definitions
function setup_bonito_connection end
function mk_bonito_websocket_handler end
const BONITO_OFFLINE::Ref{Bool} = Ref(true)
