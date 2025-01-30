module TimeZonesExt

import Base
import HTTP
import TimeZones: ZonedDateTime, ISOZonedDateTimeFormat
import Oxygen

function Base.parse(::Type{ZonedDateTime}, str::String)
    return ZonedDateTime(str, ISOZonedDateTimeFormat)
end

function Oxygen.parseparam(::Type{T}, str::String; escape=true) where {T <: ZonedDateTime}
    return parse(T, escape ? HTTP.unescapeuri(str) : str)
end

end