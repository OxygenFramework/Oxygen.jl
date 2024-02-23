module OxidiseDemo

using Oxygen; @oxidise

@get("/") do req
    "home" 
end

@get("/nihao") do req
    "你好"
end

@get "/greet" function()
    "hello world!"
end

@get "/saluer" () -> begin
    "Bonjour le monde!"
end

@get "/saludar" () -> "¡Hola Mundo!"
@get "/salutare" f() = "ciao mondo!"

serve()

end