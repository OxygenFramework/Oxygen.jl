# Oxygen.jl Code Style Guide

This guide describes the conventions used by the Oxygen.jl codebase. The goal is consistency and readability, not reformatting for its own sake. Match the surrounding file when it is already consistent with this guide. New
code and code you are already changing should follow the guide exactly.

## 1. Guiding principles

- Optimize for the reader. Code is read far more often than it is written.
- Keep the public API small and documented. Keep internal helpers internal.
- Make concurrency and error handling explicit; do not hide them behind clever
  abstractions.
- Prefer simple, direct Julia over metaprogramming. Use macros only where the
  public API requires them (routing macros, string macros, extensions).
- A performance-sensitive path may trade elegance for speed, but the reason must
  be stated in a comment.

## 2. Formatting

- Use UTF-8, LF line endings, and a final newline.
- Indent with four spaces. Never use tabs.
- Treat 150 columns as the soft limit. Break long argument lists, chains, and
  conditions. Long string literals, URLs, docstring examples, and generated
  output may exceed it. Do not split a single message or string literal with
  `*` just to satisfy the limit; keep the message intact and break at the
  argument boundary instead.
- Put one statement per line. Semicolons are only acceptable for the established
  `include("file.jl"); using .Name` pattern and similar one-line module wiring.
- Use one blank line between methods and logical blocks. Use two blank lines
  between major sections of a file.
- Put spaces around binary operators and assignment (`x = y`). In parameter
  lists and call sites, keyword arguments use `key=value`; in aligned
  configuration blocks (multi-line keyword tables), use `key :: Type = default`.
  Use a space after commas, never before.
- Do not put a space before a call parenthesis: `f(x)`, not `f (x)`.
- Do not pad inside parentheses, brackets, or braces.
- Write control flow with a space after the keyword: `if cond`, `elseif cond`,
  `while cond`, `for item in items`, `catch error`.
- For type annotations:
  - Function parameters use no inner spaces: `func(req::HTTP.Request)`.
  - Return type annotations use spaces around `::` after the closing
    parenthesis: `func(req::HTTP.Request) :: HTTP.Response`.
  - Struct fields use spaces around `::` and are aligned within the struct:

    ```julia
    struct HTTPTransaction
        ip            :: String
        uri           :: String
        timestamp     :: DateTime
        duration      :: Float64
        success       :: Bool
        status        :: Int16
        error_message :: Nullable{String}
    end
    ```

  - Keep multi-line keyword-argument blocks aligned when they form a table:

    ```julia
    function RateLimiter(;
        rate_limit        :: Int = 100,
        window            :: Period = Minute(1),
        cleanup_period    :: Period = Minute(10),
        cleanup_threshold :: Period = Minute(10),
        auto_extract_ip   :: Bool = true,
        exempt_paths      :: Vector{String} = String[])
    ```

- Trailing commas are allowed in multi-line argument lists and collection
  literals when each item is on its own line; they improve diffs. Do not add
  them to single-line calls.
- Do not align `=` across unrelated statements; alignment is for struct fields
  and compact keyword blocks, not for general assignments.

## 3. Naming

- Modules, types, structs, and modules-in-files: `PascalCase`
  (`ServerContext`, `RateLimiterMiddleware`, `MetricsCache`).
- Functions and variables: `snake_case` (`join_url_path`, `has_mcp_content`,
  `history_lock`).
- Constants and immutable global values: `UPPER_SNAKE_CASE`
  (`HTTP_METHODS`, `STREAM_BUFFER_SIZE`, `SWEEP_INTERVAL`).
- Predicates read as questions and return `Bool`: `isopen`, `isnothing`,
  `hasdefault`, `isbodyparam`, `has_mcp_content`.
- Mutating functions end in `!`: `push!`, `register!`, `cancel_stream!`,
  `empty!`.
- Acronyms stay uppercase in type and constant names: `HTTP`, `MCP`, `CORS`,
  `SSE`, `IP`. Use the natural word form in mixed-case identifiers
  (`MCPContext`, `SSEEvent`, `ExtractIP`, `CORSMiddleware`).
- Internal helpers do not use a leading underscore. Keep them unexported.
- Use conventional short names only for their conventional roles:
  `req`, `resp`, `ctx`, `stream`, `func`, `handle`, `handler`, `params`,
  `i`/`j` for indices, `k`/`v` for pairs.
- File names are `snake_case.jl` and describe the content; module entry files
  use the module name (`context.jl` contains `AppContext` is an existing
  exception, not a pattern to copy).
- Avoid shadowing `Base` names. If unavoidable, qualify the use and add a
  comment explaining why. The conventional `error` binding in `catch error` and
  in error-handling helpers is allowed.

## 4. Modules and file organization

- Each file owns one concern. Coordinating modules include child files and
  re-export them when they are part of the public surface.

  ```julia
  module Middleware
  using Reexport

  include("middleware/extract_ip.jl"); @reexport using .ExtractIPMiddleware
  include("middleware/rate_limiter.jl"); @reexport using .RateLimiterMiddleware
  end
  ```

- Include dependencies before dependents. Leaf modules (no internal
  dependencies) load first and are marked as such in a comment when useful.
- Import packages and standard libraries first, then internal modules, separated
  by a blank line. Prefer narrow imports (`using HTTP: Request, Response`) when
  only a few names are needed.
- Use `import` when adding methods to another module's function; use `using`
  when consuming names.
- Use relative imports inside the package: `using ..Types: Nullable`,
  `import ...Reflection: Param`.
- Use `@reexport` only for modules that are deliberately part of the public
  API. Do not re-export implementation details.
- A file may begin with a short header comment describing the module; the
  `module Name` declaration follows it. Modules end with a bare `end`. Add the
  header comment when the purpose is not obvious.
- Keep top-level side effects out of module bodies. Runtime initialization
  belongs in `__init__` or an explicit setup function.

## 5. Types and state

- Prefer immutable `struct`s. Use `mutable struct` only when mutation is part of
  the design; document the synchronization strategy for shared mutable state.
- Use `@kwdef` for configuration and context structs with defaults:

  ```julia
  @kwdef struct LifecycleMiddleware
      middleware  :: Function
      on_startup  :: Union{Function,Nothing} = nothing
      on_shutdown :: Union{Function,Nothing} = nothing
  end
  ```

- Annotate struct fields with concrete types. Avoid `Any` unless the field is
  intentionally dynamic (for example, a lazily initialized cache or an opaque
  protocol value); explain it in a comment.
- Prefer `Nullable{T}` (`Union{T, Nothing}`) for optional values in the package's
  own types. Use `missing` only where the codebase already distinguishes
  "unset" from "nothing".
- Give non-obvious fields an inline comment. Do not comment fields whose names
  already explain them.
- Use `Ref{T}` for mutable state stored in an otherwise immutable context
  object, and initialize it explicitly.
- Implement `Base` behavior deliberately (`Base.show`, `Base.close`,
  `Base.isopen`, `Base.wait`) rather than inventing parallel methods.

## 6. Functions and methods

- Use a full `function ... end` definition for multi-statement bodies. Short
  forwarding methods may use the one-line form:

  ```julia
  stoptasks(context::ServerContext) = Oxygen.Core.stoptasks(context.tasks)
  terminate() = terminate(CONTEXT[])
  ```

- Prefer guard clauses and early returns over deep nesting:

  ```julia
  function starttasks(tasks::TasksContext)
      isempty(tasks.registered_tasks) && return
      # ...
  end
  ```

- Use explicit `return` in multi-statement functions. This is the dominant style
  in the codebase and makes the exit points obvious.
- Annotate return types at public boundaries and wherever the annotation
  documents an important guarantee. Do not annotate every internal helper.
- Put the semicolon before keyword arguments, and give defaults the same type as
  the parameter when the annotation is present.
- When a method name is long, or a signature does not fit on one line, put the
  method name and opening `(` on the first line, then one argument per line,
  indented four spaces. Do not keep some arguments on the opening line. Put the
  closing `)` and any return annotation or `=` on the same line as the final
  argument. Separate the signature from the body with one blank line:

  ```julia
  function resource_list(
      entries::Dict{String,MCPResource},
      key::String;
      spec::Val=LATEST_LEGACY_SPEC) :: Dict{String,Any}

      items = [resource_entry(entries[uri]; spec=spec) for uri in sort(collect(keys(entries)))]
      return list_result(key, items; spec=spec)
  end
  ```

  Short-form methods keep their body on the line directly after `=`:

  ```julia
  handle_method(
      spec::Val,
      ::Val{:resources_list},
      ctx::ServerContext,
      req::Union{Nothing,HTTP.Request},
      id,
      params,
      raw::String;
      session=nothing) = result_response(ctx, id, resources_list(ctx; spec=spec); spec=spec)
  ```

- For more than three keyword arguments, put one per line. Align the `=` column
  when the names are part of one configuration table.
- Avoid positional boolean flags. Prefer a keyword such as `catch_errors=true`.
- Use `do` blocks for callback-style APIs; put the callback function first in
  the signature so `do` reads naturally.
- Prefer `something(x, default)`, `isnothing(x)`, and `ismissing(x)` over
  identity comparisons with `nothing`/`missing`.
- Use `===` for identity checks and `==` for value checks. Be explicit about
  which one the code needs.
- Avoid `eval` and `@eval` at runtime. If a macro or generated function is
  required, keep the generated surface small and document the expansion.
- Keep hot paths allocation-light. If a branch is written for performance,
  say why in a comment (see `get_invoker_strategy` in `handlers.jl`).

## 7. Docstrings

- Every exported function, type, macro, constant, and non-obvious internal
  helper gets a docstring.
- Use the following shape. The signature line is indented four spaces, followed
  by a blank line and prose.

  ````julia
  """
      join_url_path(prefix::Union{String,Nothing}, route::String)::String

  Combine a URL prefix and route, avoiding duplicate slashes.

  # Arguments
  - `prefix`: The prefix, or `nothing`.
  - `route`: The route, with or without a leading slash.

  # Returns
  The combined path as a `String`.

  # Example
  ```julia
  join_url_path("/api", "/users") # "/api/users"
  ```
  """
  ````

- Constant docstrings are the exception: the binding name already identifies the
  constant, so omit the name line and the leading blank line. Start the prose
  directly:

  ```julia
  """
  Interval between keep-alive comments on an idle SSE stream.
  """
  const SSE_KEEPALIVE_SECONDS = 3
  ```

- Start the description with a short sentence. Use `# Arguments`, `# Returns`,
  and `# Example` when they add information; omit empty sections.
- Use backticks for code identifiers and fenced `julia` blocks for examples.
  Reference another name with the backticked name alone (`adopt_channel`); do
  not use `@ref` cross-reference syntax.
- Use `raw"""` when a docstring contains dollar signs or backslashes that Julia
  would otherwise interpolate.
- Do not restate the signature in prose. Explain behavior, edge cases, and side
  effects instead.

## 8. Comments

- Comments explain *why*, not *what*. The code already says what it does.
- Write comments as full sentences with sentence case and punctuation:

  ```julia
  # The local reference lets us wait on this specific server call, because a
  # newer serve() may replace the shared server instance before shutdown.
  ```

- Place a comment above the code it describes, separated by a blank line when
  it introduces a block.
- Use section dividers for long files:

  ```julia
  # ---------------------------------------------------------------------------
  # Incremental metrics cache
  # ---------------------------------------------------------------------------
  ```

- Use `# TODO: ...` or `# FIXME: ...` with enough context to act on. Do not add
  commented-out code or stale notes.
- Keep comments accurate when changing the code. A wrong comment is worse than
  no comment.

## 9. Error handling

- Define domain-specific exceptions as subtypes of `Exception` and implement
  `Base.showerror`:

  ```julia
  struct ValidationError <: Exception
      msg::String
      cause::Union{Nothing, Exception}
  end

  function Base.showerror(io::IO, e::ValidationError)
      print(io, "Validation Error: $(e.msg)")
  end
  ```

- Use `ArgumentError` for invalid arguments and configuration, and `ErrorException`
  (via `error`) only for unrecoverable internal invariants.
- Do not swallow exceptions. Either handle a specific expected failure, rethrow
  with context, or log and return a well-defined fallback.
- Catch as `catch error` when the exception is used (the codebase convention)
  and log with the stack trace. A bare `catch` is acceptable for deliberate
  best-effort cleanup, but add a comment explaining why the failure is ignored.

  ```julia
  catch error
      @error "Failed to register MCP tool for route: $route" exception=(error, catch_backtrace())
  end
  ```

- Use `try/finally` for cleanup (locks, streams, tasks, server state).
- Validate inputs at module boundaries (public functions, HTTP handlers,
  route registration) and let internal code assume the invariants hold.

## 10. Logging

- Use `@info` for lifecycle events, `@warn` for recoverable problems, and
  `@error` for failures that need attention.
- Include the operation and the relevant identifier in the message. Pass
  structured values as metadata when they are not part of the sentence.
- Do not use `println` in library code. The server banner and CLI-style output
  in `core.jl`, `cron.jl`, and `repeattasks.jl` are the existing exceptions.
- Emoji are reserved for the user-facing server banner, not diagnostics.
- Never log secrets, full authorization headers, or request bodies.

## 11. Concurrency and shared state

- Document the lock-ordering rule at the top of a module that takes more than
  one lock. State which locks may be held together.
- Keep critical sections short. Do not perform I/O, call user callbacks, or
  acquire another subsystem's lock while holding a lock.
- Use `lock(l) do ... end` when possible; when locking manually, unlock in a
  `finally` block.
- Use `Threads.@spawn` for work that should run on another thread and `@async`
  for cooperative I/O concurrency. Use `errormonitor` or an explicit
  `try/finally` for background tasks.
- Use `Threads.Atomic`, `Ref`, or a lock for shared flags. Never mutate shared
  containers without synchronization.
- Make cancellation cooperative: check the cancellation flag in loops and let
  blocked operations unwind with the package's cancellation exception.
- Avoid `sleep` for synchronization. If a polling loop is unavoidable, document
  the interval and the reason, and check cancellation each iteration.
- A server or task started by a function must have a documented shutdown path.

## 12. Tests

- One test file per feature area, wrapped in a module named `<Feature>Tests`:

  ```julia
  module ExtractorTests

  using Base: @kwdef
  using Test
  using HTTP
  using Oxygen; @oxidize
  using ..Constants

  @testset "JSON extract" begin
      # ...
  end

  end
  ```

- Include every new test file from `test/runtests.jl` (or the appropriate
  extension runner) in the relevant section.
- Use descriptive `@testset` names; nest testsets for sub-behaviors. One test
  should exercise one behavior.
- Prefer direct assertions: `@test x == y`, `@test x isa T`, `@test isnothing(x)`,
  `@test occursin(needle, haystack)`, and `@test_throws ErrorType expr`.
- Test the public contract and the regression being fixed, not private
  implementation details. Add a comment naming the issue for tricky regressions.
- Use the shared helpers in `test/test_utils.jl` instead of duplicating assertion
  utilities.
- Keep tests deterministic. Prefer an ephemeral port and a local server over a
  fixed port; always shut down servers, tasks, and cron jobs in `finally`.
- Avoid `sleep` as a synchronization mechanism. If a test must wait, poll with a
  bounded timeout and a clear failure message.
- Do not leave debug prints, commented-out tests, or disabled tests in the
  suite. Use `@test_broken` with a comment only for a known, tracked limitation.

## 13. Extensions

- Name extension modules `<Dependency>Ext` and put them in `ext/`.
- Declare the empty function/type surface in `src/exts.jl`, then add methods in
  the extension module:

  ```julia
  module ProtoBufExt

  import HTTP
  import Oxygen: ProtoBuffer, protobuf
  import Oxygen.Reflection: Param
  import ProtoBuf: encode, decode

  export protobuf, extract

  end
  ```

- Import only the bindings the extension extends or consumes. Do not reach into
  another extension's internals.
- Optional dependencies must only be referenced inside the corresponding
  extension, never in `src/`.
- Add the extension test under `test/extensions/` and include it from
  `runtests.jl`.

## 14. Public API, deprecation, and documentation

- Every exported name is documented. Group related exports with a comment in the
  module's export block:

  ```julia
  export  @oxidize, @get, @post,
          # Util
          redirect, formdata,
          # Middleware
          BearerAuth, Cors, RateLimiter
  ```

- Additions are backward compatible: add keyword arguments with defaults instead
  of changing positional signatures.
- Deprecations live in `src/deprecated.jl`, emit a `@warn` naming the
  replacement, and keep working for a release cycle.
- User-facing documentation lives in `docs/src/`; docstrings are the source of
  truth for API behavior. Keep both in sync.
- Use ATX headings (`#`, `##`) and fenced code blocks with a language tag in
  Markdown files.

## 15. Review checklist

Before considering a change complete:

- [ ] The change follows the formatting and naming rules above.
- [ ] New public names are exported intentionally and documented.
- [ ] New internal helpers are not exported.
- [ ] Error paths log or propagate with context; cleanup runs in `finally`.
- [ ] Shared state is locked or atomic, and lock ordering is respected.
- [ ] Background tasks and servers have a shutdown path.
- [ ] Tests cover the new behavior and any regression, and the file is included
      in the runner.
- [ ] `julia --project -e 'using Pkg; Pkg.test()'` passes.
- [ ] Documentation examples remain valid under `doctest`.
