Hello, I am an automated registration bot. I help manage the registration process by checking your registration against a set of [AutoMerge guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/). If all these guidelines are met, this pull request will be merged automatically, completing your registration. It is **strongly recommended** to follow the guidelines, since otherwise the pull request needs to be manually reviewed and merged by a human.

## 1. [AutoMerge Guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/) are all met! ✅

Your new version registration met all of the guidelines for auto-merging and is scheduled to be merged in the next round (~20 minutes).

## 2. Code changes since last version

Code changes from v1.0.0: 

```sh
❯ git diff-tree --shortstat 999513b7dea8ac17359ed50ae8ea089e4464e35e 62389eeff14780bfe55195b7204c0d8738436d64
 12 files changed, 325 insertions(+), 121 deletions(-)
```


<details><summary>Click to expand full patch diff</summary>

```diff
❯ git diff-tree --patch 999513b7dea8ac17359ed50ae8ea089e4464e35e 62389eeff14780bfe55195b7204c0d8738436d64
diff --git a/.github/workflows/CI.yml b/.github/workflows/CI.yml
new file mode 100644
index 0000000..4d42e84
--- /dev/null
+++ b/.github/workflows/CI.yml
@@ -0,0 +1,52 @@
+name: CI
+on:
+  push:
+    branches:
+      - main
+    tags: '*'
+  pull_request:
+concurrency:
+  # Skip intermediate builds: always.
+  # Cancel intermediate builds: only if it is a pull request build.
+  group: ${{ github.workflow }}-${{ github.ref }}
+  cancel-in-progress: ${{ startsWith(github.ref, 'refs/pull/') }}
+jobs:
+  test:
+    name: Julia ${{ matrix.version }} - ${{ matrix.os }} - ${{ matrix.arch }} - ${{ github.event_name }}
+    runs-on: ${{ matrix.os }}
+    strategy:
+      fail-fast: false
+      matrix:
+        version:
+          - '1.0'
+          - '1.6'
+          - 'lts'
+          - '1'
+          - 'nightly'
+        os:
+          - ubuntu-latest
+        arch:
+          - x64
+    steps:
+      - uses: actions/checkout@v2
+      - uses: julia-actions/setup-julia@v2
+        with:
+          version: ${{ matrix.version }}
+          arch: ${{ matrix.arch }}
+      - uses: actions/cache@v1
+        env:
+          cache-name: cache-artifacts
+        with:
+          path: ~/.julia/artifacts
+          key: ${{ runner.os }}-test-${{ env.cache-name }}-${{ hashFiles('**/Project.toml') }}
+          restore-keys: |
+            ${{ runner.os }}-test-${{ env.cache-name }}-
+            ${{ runner.os }}-test-
+            ${{ runner.os }}-
+      - uses: julia-actions/julia-buildpkg@v1
+      - uses: julia-actions/julia-runtest@v1
+      - uses: julia-actions/julia-processcoverage@v1
+      - uses: codecov/codecov-action@v2
+        with:
+          files: lcov.info
+          
diff --git a/.github/workflows/TagBot.yml b/.github/workflows/TagBot.yml
new file mode 100644
index 0000000..d77d3a0
--- /dev/null
+++ b/.github/workflows/TagBot.yml
@@ -0,0 +1,11 @@
+name: TagBot
+on:
+  schedule:
+    - cron: 0 * * * *
+jobs:
+  TagBot:
+    runs-on: ubuntu-latest
+    steps:
+      - uses: JuliaRegistries/TagBot@v1
+        with:
+          token: ${{ secrets.GITHUB_TOKEN }}
diff --git a/.travis.yml b/.travis.yml
deleted file mode 100644
index 7c3c2e3..0000000
--- a/.travis.yml
+++ /dev/null
@@ -1,14 +0,0 @@
-language: julia
-os:
-  - linux
-  - osx
-julia:
-  - 0.7
-  - 1.0
-  - nightly
-notifications:
-  email: false
-# uncomment the following lines to override the default test script
-#script:
-#  - if [[ -a .git/shallow ]]; then git fetch --unshallow; fi
-#  - julia --check-bounds=yes -e 'Pkg.clone(pwd()); Pkg.build("Requires"); Pkg.test("Requires"; coverage=true)'
diff --git a/LICENSE.md b/LICENSE.md
index 3e5e249..1f5a1ee 100644
--- a/LICENSE.md
+++ b/LICENSE.md
@@ -1,6 +1,6 @@
 The Requires.jl package is licensed under the MIT "Expat" License:
 
-> Copyright (c) 2014: Mike Innes.
+> Copyright (c) 2014: Mike Innes, Julia Computing & contributors.
 >
 > Permission is hereby granted, free of charge, to any person obtaining
 > a copy of this software and associated documentation files (the
diff --git a/Project.toml b/Project.toml
index aec247c..6d023b4 100644
--- a/Project.toml
+++ b/Project.toml
@@ -1,6 +1,6 @@
 name = "Requires"
 uuid = "ae029012-a4dd-5104-9daa-d747884805df"
-version = "1.0.0"
+version = "1.3.1"
 
 [deps]
 UUIDs = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"
@@ -10,7 +10,8 @@ julia = "0.7, 1"
 
 [extras]
 Colors = "5ae59095-9a9b-59fe-a467-6f913c188581"
+Example = "7876af07-990d-54b4-ab0e-23690620f79a"
 Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
 
 [targets]
-test = ["Test", "Colors"]
+test = ["Test", "Colors", "Example"]
diff --git a/README.md b/README.md
index 686fdf2..de30640 100644
--- a/README.md
+++ b/README.md
@@ -2,13 +2,17 @@
 
 For older versions of Julia, see https://github.com/MikeInnes/Requires.jl/blob/5683745f03cbea41f6f053182461173e236fdd94/README.md
 
+For Julia 1.9 and higher, Package Extensions is preferable;
+see
+[the Julia manual](https://docs.julialang.org/en/v1/manual/code-loading/#man-extensions).
+
 # Requires.jl
 
 [![Build Status](https://travis-ci.org/MikeInnes/Requires.jl.svg?branch=master)](https://travis-ci.org/MikeInnes/Requires.jl)
 
 *Requires* is a Julia package that will magically make loading packages
 faster, maybe. It supports specifying glue code in packages which will
-load automatically when a another package is loaded, so that explicit
+load automatically when another package is loaded, so that explicit
 dependencies (and long load times) can be avoided.
 
 Suppose you've written a package called `MyPkg`. `MyPkg` has core functionality that it always provides;
@@ -58,6 +62,8 @@ if you wish to exploit precompilation for the new code.
 
 In the `@require` block, or any included files, you can use or import the package, but note that you must use the syntax `using .Gadfly` or `import .Gadfly`, rather than the usual syntax. Otherwise you will get a warning about Gadfly not being in dependencies.
 
+`@require`d packages can be added to the `test` environment of a Julia project for integration tests, or directly to the project to document compatible versions in the `[compat]` section of `Project.toml`.
+
 ## Demo
 
 For a complete demo, consider the following file named `"Reqs.jl"`:
diff --git a/src/Requires.jl b/src/Requires.jl
index 3af59c0..f39fe69 100644
--- a/src/Requires.jl
+++ b/src/Requires.jl
@@ -1,7 +1,49 @@
 module Requires
 
+if isdefined(Base, :Experimental) && isdefined(Base.Experimental, Symbol("@compiler_options"))
+    @eval Base.Experimental.@compiler_options compile=min optimize=0 infer=false
+end
+
 using UUIDs
 
+function _include_path(relpath::String)
+    # Reproduces include()'s runtime relative path logic
+    # See Base._include_dependency()
+    prev = Base.source_path(nothing)
+    if prev === nothing
+        path = abspath(relpath)
+    else
+        path = normpath(joinpath(dirname(prev), relpath))
+    end
+end
+
+"""
+    @include("somefile.jl")
+
+Behaves like `include`, but caches the target file content at macro expansion
+time, and uses this as a fallback when the file doesn't exist at runtime. This
+is useful when compiling a sysimg. The argument `"somefile.jl"` must be a
+string literal, not an expression.
+
+`@require` blocks insert this automatically when you use `include`.
+"""
+macro include(relpath::String)
+    compiletime_path = joinpath(dirname(String(__source__.file)), relpath)
+    s = String(read(compiletime_path))
+    quote
+        # NB: Runtime include path may differ from the compile-time macro
+        # expansion path if the source has been relocated.
+        runtime_path = _include_path($relpath)
+        if isfile(runtime_path)
+            # NB: For Revise compatibility, include($relpath) needs to be
+            # emitted where $relpath is a string *literal*.
+            $(esc(:(include($relpath))))
+        else
+            include_string($__module__, $s, $relpath)
+        end
+    end
+end
+
 include("init.jl")
 include("require.jl")
 
@@ -10,11 +52,21 @@ function __init__()
 end
 
 if isprecompiling()
-    @assert precompile(loadpkg, (Base.PkgId,))
-    @assert precompile(withpath, (Any, String))
-    @assert precompile(err, (Any, Module, String))
-    @assert precompile(parsepkg, (Expr,))
-    @assert precompile(listenpkg, (Any, Base.PkgId))
+    precompile(loadpkg, (Base.PkgId,)) || @warn "Requires failed to precompile `loadpkg`"
+    precompile(withpath, (Any, String)) || @warn "Requires failed to precompile `withpath`"
+    precompile(err, (Any, Module, String, String, Int)) || @warn "Requires failed to precompile `err`"
+    precompile(err, (Any, Module, String, String, Nothing)) || @warn "Requires failed to precompile `err`"
+    precompile(parsepkg, (Expr,)) || @warn "Requires failed to precompile `parsepkg`"
+    precompile(listenpkg, (Any, Base.PkgId)) || @warn "Requires failed to precompile `listenpkg`"
+    precompile(callbacks, (Base.PkgId,)) || @warn "Requires failed to precompile `callbacks`"
+    precompile(withnotifications, (String, Module, String, String, Expr)) || @warn "Requires failed to precompile `withnotifications`"
+    precompile(replace_include, (Expr, LineNumberNode)) || @warn "Requires failed to precompile `replace_include`"
+    precompile(getfield(Requires, Symbol("@require")), (LineNumberNode, Module, Expr, Any)) || @warn "Requires failed to precompile `@require`"
+
+    precompile(_include_path, (String,)) || @warn "Requires failed to precompile `_include_path`"
+    precompile(getfield(Requires, Symbol("@include")), (LineNumberNode, Module, String)) || @warn "Requires failed to precompile `@include`"
+
+    precompile(__init__, ()) || @warn "Requires failed to precompile `__init__`"
 end
 
 end # module
diff --git a/src/require.jl b/src/require.jl
index cc4d466..f36823f 100644
--- a/src/require.jl
+++ b/src/require.jl
@@ -1,21 +1,26 @@
-using Base: PkgId, loaded_modules, package_callbacks, @get!
+using Base: PkgId, loaded_modules, package_callbacks
 using Base.Meta: isexpr
+if isdefined(Base, :mapany)
+  const mapany = Base.mapany
+else
+  mapany(f, A::AbstractVector) = map!(f, Vector{Any}(undef, length(A)), A)
+end
 
 export @require
 
 isprecompiling() = ccall(:jl_generating_output, Cint, ()) == 1
 
-loaded(pkg) = haskey(Base.loaded_modules, pkg)
+loaded(pkg::PkgId) = haskey(Base.loaded_modules, pkg)
 
 const notified_pkgs = [Base.PkgId(UUID(0x295af30fe4ad537b898300126c2a3abe), "Revise")]
 
 const _callbacks = Dict{PkgId, Vector{Function}}()
-callbacks(pkg) = @get!(_callbacks, pkg, [])
+callbacks(pkg::PkgId) = get!(Vector{Function}, _callbacks, pkg)
 
-listenpkg(@nospecialize(f), pkg) =
+listenpkg(@nospecialize(f), pkg::PkgId) =
   loaded(pkg) ? f() : push!(callbacks(pkg), f)
 
-function loadpkg(pkg)
+function loadpkg(pkg::PkgId)
   if haskey(_callbacks, pkg)
     fs = _callbacks[pkg]
     delete!(_callbacks, pkg)
@@ -23,7 +28,7 @@ function loadpkg(pkg)
   end
 end
 
-function withpath(@nospecialize(f), path)
+function withpath(@nospecialize(f), path::String)
   tls = task_local_storage()
   hassource = haskey(tls, :SOURCE_PATH)
   hassource && (path′ = tls[:SOURCE_PATH])
@@ -37,32 +42,31 @@ function withpath(@nospecialize(f), path)
   end
 end
 
-function err(@nospecialize(f), listener, mod)
+function err(@nospecialize(f), listener::Module, modname::String, file::String, line)
   try
-    f()
-  catch e
-    @warn """
-      Error requiring $mod from $listener:
-      $(sprint(showerror, e, catch_backtrace()))
-      """
+    t = @elapsed ret = f()
+    @debug "Requires conditionally ran code in $t seconds: `$listener` detected `$modname`" _file = file _line = line
+    ret
+  catch exc
+    @warn "Error requiring `$modname` from `$listener`" exception=(exc,catch_backtrace())
   end
 end
 
-function parsepkg(ex)
+function parsepkg(ex::Expr)
   isexpr(ex, :(=)) || @goto fail
   mod, id = ex.args
   (mod isa Symbol && id isa String) || @goto fail
-  return id, String(mod)
+  return id::String, String(mod::Symbol)
   @label fail
   error("Requires syntax is: `@require Pkg=\"uuid\"`")
 end
 
-function withnotifications(args...)
+function withnotifications(@nospecialize(args...))
   for id in notified_pkgs
     if loaded(id)
       mod = Base.root_module(id)
       if isdefined(mod, :add_require)
-        add_require = getfield(mod, :add_require)
+        add_require = getfield(mod, :add_require)::Function
         add_require(args...)
       end
     end
@@ -70,23 +74,36 @@ function withnotifications(args...)
   return nothing
 end
 
-macro require(pkg, expr)
+function replace_include(ex::Expr, source::LineNumberNode)
+  if ex.head == :call && ex.args[1] === :include && ex.args[2] isa String
+    return Expr(:macrocall, :($Requires.$(Symbol("@include"))), source, ex.args[2]::String)
+  end
+  return Expr(ex.head, (mapany(ex.args) do arg
+    isa(arg, Expr) ? replace_include(arg, source) : arg
+  end)...)
+end
+
+macro require(pkg::Union{Symbol,Expr}, expr)
   pkg isa Symbol &&
     return Expr(:macrocall, Symbol("@warn"), __source__,
                 "Requires now needs a UUID; please see the readme for changes in 0.7.")
-  id, modname = parsepkg(pkg)
-  pkg = :(Base.PkgId(Base.UUID($id), $modname))
+  idstr, modname = parsepkg(pkg)
+  pkg = :(Base.PkgId(Base.UUID($idstr), $modname))
+  expr = isa(expr, Expr) ? replace_include(expr, __source__) : expr
+  expr = macroexpand(__module__, expr)
+  srcfile = string(__source__.file)
+  srcline = __source__.line
   quote
     if !isprecompiling()
       listenpkg($pkg) do
-        $withnotifications($(string(__source__.file)), $__module__, $id, $modname, $(esc(Expr(:quote, expr))))
-        withpath($(string(__source__.file))) do
-          err($__module__, $modname) do
+        withpath($srcfile) do
+          err($__module__, $modname, $srcfile, $srcline) do
             $(esc(:(eval($(Expr(:quote, Expr(:block,
                                             :(const $(Symbol(modname)) = Base.require($pkg)),
                                             expr)))))))
           end
         end
+        $withnotifications($srcfile, $__module__, $idstr, $modname, $(esc(Expr(:quote, expr))))
       end
     end
   end
diff --git a/test/Project.toml b/test/Project.toml
index 6c65255..f9d1df1 100644
--- a/test/Project.toml
+++ b/test/Project.toml
@@ -1,3 +1,4 @@
 [deps]
 Colors = "5ae59095-9a9b-59fe-a467-6f913c188581"
+Example = "7876af07-990d-54b4-ab0e-23690620f79a"
 Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
diff --git a/test/pkgs/NotifyMe/Project.toml b/test/pkgs/NotifyMe/Project.toml
new file mode 100644
index 0000000..626c8bf
--- /dev/null
+++ b/test/pkgs/NotifyMe/Project.toml
@@ -0,0 +1,8 @@
+name = "NotifyMe"
+uuid = "545cf9b9-f575-4090-a54a-9a5287d37f74"
+authors = ["Tim Holy <tim.holy@gmail.com>"]
+version = "0.1.0"
+
+[deps]
+Requires = "ae029012-a4dd-5104-9daa-d747884805df"
+UUIDs = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"
diff --git a/test/pkgs/NotifyMe/src/NotifyMe.jl b/test/pkgs/NotifyMe/src/NotifyMe.jl
new file mode 100644
index 0000000..5238261
--- /dev/null
+++ b/test/pkgs/NotifyMe/src/NotifyMe.jl
@@ -0,0 +1,12 @@
+module NotifyMe
+
+using Requires, UUIDs
+
+const notified_args = []
+add_require(args...) = push!(notified_args, args)
+
+function __init__()
+    push!(Requires.notified_pkgs, Base.PkgId(UUID(0x545cf9b9f5754090a54a9a5287d37f74), "NotifyMe"))
+end
+
+end # module
diff --git a/test/runtests.jl b/test/runtests.jl
index d7d40d5..9eb276e 100644
--- a/test/runtests.jl
+++ b/test/runtests.jl
@@ -42,82 +42,140 @@ end
     end
 end
 
-@testset "Requires" begin
-    mktempdir() do pkgsdir
-        cd(pkgsdir) do
-            npcdir = joinpath("FooNPC", "src")
-            mkpath(npcdir)
-            cd(npcdir) do
-                writepkg("FooNPC", false, false)
-            end
-            npcdir = joinpath("FooPC", "src")
-            mkpath(npcdir)
-            cd(npcdir) do
-                writepkg("FooPC", true, false)
-            end
-            npcdir = joinpath("FooSubNPC", "src")
-            mkpath(npcdir)
-            cd(npcdir) do
-                writepkg("FooSubNPC", false, true)
-            end
-            npcdir = joinpath("FooSubPC", "src")
-            mkpath(npcdir)
-            cd(npcdir) do
-                writepkg("FooSubPC", true, true)
-            end
-        end
-        push!(LOAD_PATH, pkgsdir)
-
-        @eval using FooNPC
-        @test !FooNPC.flag
-        @eval using FooPC
-        @test !FooPC.flag
-        @eval using FooSubNPC
-        @test !(:SubModule in names(FooSubNPC))
-        @eval using FooSubPC
-        @test !(:SubModule in names(FooSubPC))
-
-        @eval using Colors
-
-        @test FooNPC.flag
-        @test FooPC.flag
-        @test :SubModule in names(FooSubNPC)
-        @test FooSubNPC.SubModule.flag
-        @test :SubModule in names(FooSubPC)
-        @test FooSubPC.SubModule.flag
-
-        cd(pkgsdir) do
-            npcdir = joinpath("FooAfterNPC", "src")
-            mkpath(npcdir)
-            cd(npcdir) do
-                writepkg("FooAfterNPC", false, false)
-            end
-            pcidr = joinpath("FooAfterPC", "src")
-            mkpath(pcidr)
-            cd(pcidr) do
-                writepkg("FooAfterPC", true, false)
-            end
-            sanpcdir = joinpath("FooSubAfterNPC", "src")
-            mkpath(sanpcdir)
-            cd(sanpcdir) do
-                writepkg("FooSubAfterNPC", false, true)
-            end
-            sapcdir = joinpath("FooSubAfterPC", "src")
-            mkpath(sapcdir)
-            cd(sapcdir) do
-                writepkg("FooSubAfterPC", true, true)
+pkgsdir = mktempdir()
+cd(pkgsdir) do
+    npcdir = joinpath("FooNPC", "src")
+    mkpath(npcdir)
+    cd(npcdir) do
+        writepkg("FooNPC", false, false)
+    end
+    npcdir = joinpath("FooPC", "src")
+    mkpath(npcdir)
+    cd(npcdir) do
+        writepkg("FooPC", true, false)
+    end
+    npcdir = joinpath("FooSubNPC", "src")
+    mkpath(npcdir)
+    cd(npcdir) do
+        writepkg("FooSubNPC", false, true)
+    end
+    npcdir = joinpath("FooSubPC", "src")
+    mkpath(npcdir)
+    cd(npcdir) do
+        writepkg("FooSubPC", true, true)
+    end
+    npcdir = joinpath("CachedIncludeTest", "src")
+    mkpath(npcdir)
+    cd(npcdir) do
+        writepkg("CachedIncludeTest", true, true)
+        submod_file = abspath("CachedIncludeTest_submod.jl")
+        @test isfile(submod_file)
+        global rm_CachedIncludeTest_submod_file = ()->rm(submod_file)
+    end
+end
+push!(LOAD_PATH, pkgsdir)
+
+using FooNPC
+@test !FooNPC.flag
+using FooPC
+@test !FooPC.flag
+using FooSubNPC
+@test !(:SubModule in names(FooSubNPC))
+using FooSubPC
+@test !(:SubModule in names(FooSubPC))
+using CachedIncludeTest
+# Test that the content of the file which defines
+# CachedIncludeTest.SubModule is cached by `@require` so it can be used
+# even when the file itself is removed.
+rm_CachedIncludeTest_submod_file()
+@test !(:SubModule in names(CachedIncludeTest))
+
+using Colors
+
+@test FooNPC.flag
+@test FooPC.flag
+@test :SubModule in names(FooSubNPC)
+@test FooSubNPC.SubModule.flag
+@test :SubModule in names(FooSubPC)
+@test FooSubPC.SubModule.flag
+@test :SubModule in names(CachedIncludeTest)
+
+cd(pkgsdir) do
+    npcdir = joinpath("FooAfterNPC", "src")
+    mkpath(npcdir)
+    cd(npcdir) do
+        writepkg("FooAfterNPC", false, false)
+    end
+    pcidr = joinpath("FooAfterPC", "src")
+    mkpath(pcidr)
+    cd(pcidr) do
+        writepkg("FooAfterPC", true, false)
+    end
+    sanpcdir = joinpath("FooSubAfterNPC", "src")
+    mkpath(sanpcdir)
+    cd(sanpcdir) do
+        writepkg("FooSubAfterNPC", false, true)
+    end
+    sapcdir = joinpath("FooSubAfterPC", "src")
+    mkpath(sapcdir)
+    cd(sapcdir) do
+        writepkg("FooSubAfterPC", true, true)
+    end
+end
+
+using FooAfterNPC
+using FooAfterPC
+using FooSubAfterNPC
+using FooSubAfterPC
+
+pop!(LOAD_PATH)
+
+@test FooAfterNPC.flag
+@test FooAfterPC.flag
+@test :SubModule in names(FooSubAfterNPC)
+@test FooSubAfterNPC.SubModule.flag
+@test :SubModule in names(FooSubAfterPC)
+@test FooSubAfterPC.SubModule.flag
+
+module EvalModule end
+
+@testset "Notifications" begin
+push!(LOAD_PATH, joinpath(@__DIR__, "pkgs"))
+using NotifyMe
+
+pkgdir = mktempdir()
+ndir = joinpath("NotifyTarget", "src")
+cd(pkgsdir) do
+    mkpath(ndir)
+    cd(ndir) do
+        open("NotifyTarget.jl", "w") do io
+            println(io, """
+            module NotifyTarget
+                using Requires
+                function __init__()
+                    @require Example="7876af07-990d-54b4-ab0e-23690620f79a" begin
+                        f(x) = 2x
+                    end
+                end
             end
+            """)
         end
-
-        @eval using FooAfterNPC
-        @eval using FooAfterPC
-        @eval using FooSubAfterNPC
-        @eval using FooSubAfterPC
-        @test FooAfterNPC.flag
-        @test FooAfterPC.flag
-        @test :SubModule in names(FooSubAfterNPC)
-        @test FooSubAfterNPC.SubModule.flag
-        @test :SubModule in names(FooSubAfterPC)
-        @test FooSubAfterPC.SubModule.flag
     end
 end
+push!(LOAD_PATH, pkgsdir)
+@test isempty(NotifyMe.notified_args)
+using NotifyTarget
+@test isempty(NotifyMe.notified_args)
+using Example
+@test length(NotifyMe.notified_args) == 1
+nargs = NotifyMe.notified_args[1]
+@test nargs[1] == joinpath(pkgsdir, ndir, "NotifyTarget.jl")
+@test nargs[2] == NotifyTarget
+@test nargs[3] == "7876af07-990d-54b4-ab0e-23690620f79a"
+@test nargs[4] == "Example"
+Core.eval(EvalModule, nargs[5])
+@test Base.invokelatest(EvalModule.f, 3) == 6
+
+end
+
+pop!(LOAD_PATH)
```

</details>

[View full patch diff on GitHub](https://github.com/MikeInnes/Requires.jl/compare/c5789cdabf3918ac058a4a469cee3fda163765f3...999513b7dea8ac17359ed50ae8ea089e4464e35e)

## 3. Declare v1.0?

On a separate note, I see that you are registering a release with a version number of the form `v0.X.Y`.

Does your package have a stable public API? If so, then it's time for you to register version `v1.0.0` of your package. (This is not a requirement. It's just a recommendation.)

If your package does not yet have a stable public API, then of course you are not yet ready to release version `v1.0.0`.

## 4. To pause or stop registration

If you want to prevent this pull request from being auto-merged, simply leave a comment. If you want to post a comment without blocking auto-merging, you must include the text `[noblock]` in your comment.

_Tip: You can edit blocking comments to add `[noblock]` in order to unblock auto-merging._

<!-- [noblock] -->