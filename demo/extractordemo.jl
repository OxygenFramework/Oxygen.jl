module BankingAppDemo
using JSON3

include("../src/Oxygen.jl")
using .Oxygen
using StructTypes

struct Address
    street::String
    city::String
    state::String
    zip_code::String
    country::String
end

struct User
    id::Int
    first_name::String
    last_name::String
    email::String
    address::Address
end

struct BankAccount
    id::Int
    account_number::String
    account_type::String
    balance::Float64
    user::User
end


@get "/" function()
    return "Welcome to the Banking App Demo"
end

"""
Setup User related routes
"""

user = router("/user", tags=["user"])

@post user("/json") function(req, data::Json{User})
    return data.payload
end

@post user("/form") function(req, data::Form{User})
    return data.payload
end

@post user("/headers") function(req, data::Header{User})
    return data.payload
end


"""
Setup Account related routes
"""

acct = router("/account", tags=["account"])

@post acct("/json") function(req, data::Json{BankAccount})
    return data.payload
end

@post acct("/form") function(req, data::Form{BankAccount})
    return data.payload
end

@post acct("/headers") function(req, data::Header{BankAccount})
    return data.payload
end

serve()

end