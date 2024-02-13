module DynamicHeadersDemo

using Oxygen
using HTTP

get("/") do req::HTTP.Request
    return "hello world!"
end

# This function allows us to customize the headers on our static & dynamic resources
function customize_headers(route::String, content_type::String, headers::Vector)
    return [headers; "My-Header" => "hello world!"]
end

staticfiles("content", set_headers=customize_headers)

serve()

end
