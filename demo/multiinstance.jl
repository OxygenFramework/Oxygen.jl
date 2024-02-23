module MultiInstanceDemo

module A
    using Oxygen; @oxidise

    @get "/" function()
        text("server A")
    end

    @get "/another" function()
        text("another route in server A")
    end
end

module B
    using Oxygen; @oxidise

    @get "/" function()
        text("server B")
    end
end

try 
    A.serve(port=8001, async=true)
    B.serve(port=8002, async=false)
finally
    A.terminate()
    B.terminate()
end

end