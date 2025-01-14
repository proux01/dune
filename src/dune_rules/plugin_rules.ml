open! Stdune
open Dune_file.Plugin
open! Dune_engine

let meta_file ~dir { name; libraries = _; site = _, (pkg, site); _ } =
  Path.Build.L.relative dir
    [ ".site"
    ; Package.Name.to_string pkg
    ; Section.Site.to_string site
    ; Package.Name.to_string name
    ; Findlib.meta_fn
    ]

let resolve_libs ~sctx t =
  Resolve.List.map t.libraries
    ~f:(Lib.DB.resolve (Super_context.public_libs sctx))

let setup_rules ~sctx ~dir t =
  let meta = meta_file ~dir t in
  Super_context.add_rule sctx ~dir
    (Action_builder.write_file_dyn meta
       (Resolve.read
          (let open Resolve.O in
          let+ requires = resolve_libs ~sctx t in
          let meta =
            { Meta.name = None
            ; entries =
                [ Gen_meta.requires
                    (Lib_name.Set.of_list_map ~f:Lib.name requires)
                ]
            }
          in
          Format.asprintf "%a" Pp.to_fmt
            (Pp.vbox (Pp.seq (Meta.pp meta.entries) Pp.cut)))))

let install_rules ~sctx ~dir ({ name; site = loc, (pkg, site); _ } as t) =
  if t.optional && Resolve.is_error (resolve_libs ~sctx t) then
    []
  else
    let meta = meta_file ~dir t in
    [ ( Some loc
      , Install.Entry.make_with_site
          ~dst:(sprintf "%s/%s" (Package.Name.to_string name) Findlib.meta_fn)
          (Site { pkg; site })
          (Super_context.get_site_of_packages sctx)
          meta )
    ]
