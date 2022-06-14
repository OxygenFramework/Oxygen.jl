module More 

using Oxygen

@get "/more" function()
    return "this is from another file!"
end


@get "another" () -> "another route"


end 