module TimeZonesExt

import HTTP
import TimeZones: ZonedDateTime, ISOZonedDateTimeFormat
import Oxygen.Core.Types: Nullable
import Oxygen.Core.Util: parseparam
import Oxygen.Core.AutoDoc: is_custom_struct, gettype, getformat

export parseparam, is_custom_struct, gettype, getformat

####################################
# Util parsing overloads           #
####################################

function parseparam(::Type{T}, str::String; escape=true) where {T <: ZonedDateTime}
    return parse(T, escape ? HTTP.unescapeuri(str) : str)
end

####################################
# AutoDoc Overloads                #
####################################

is_custom_struct(::Type{ZonedDateTime}) :: Bool = false
gettype(::Type{ZonedDateTime}) :: String = "string"
getformat(::Type{ZonedDateTime}) :: Nullable{String} = "date-time"

end