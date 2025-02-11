using Bonito
using Oxygen
using HTTP
using WGLMakie


@get "/" function(req::HTTP.Request)
    app = App() do
        xs = Observable([0])
        ys = Observable([0])
        counter = Observable(0)
        @async begin
            while true
                sleep(1)
                cur_xs = xs[]
                cur_ys = ys[]
                push!(cur_xs, cur_xs[end] + 1)
                push!(cur_ys, counter[])
                if length(cur_xs) > 10
                    popfirst!(cur_xs)
                    popfirst!(cur_ys)
                end
                notify(xs)
                notify(ys)
            end
        end
        button = Bonito.Button("increment")
        on(button.value) do click::Bool
            counter[] += 1
        end
        f = Figure()
        ax = Axis(f[1, 1])
        lines!(ax, xs, ys)
        on(ys) do _
            WGLMakie.autolimits!(ax)
            return nothing
        end
        DOM.div(DOM.h2(counter), button, DOM.div(f))
    end
    return Oxygen.html(app)
end


Oxygen.setup_bonito_connection(Oxygen.CONTEXT[]; setup_all=true)

serve()
