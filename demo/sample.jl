module SampleDemo


include("../src/Oxygen.jl"); using .Oxygen
using HTTP
using JSON3

export terminate


@staticfiles("content")

@get "/terminate" function()
    terminate()
end

serve()

end