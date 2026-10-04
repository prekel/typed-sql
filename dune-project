(lang dune 3.14)

(using mdx 0.4)

(name typed-sql)

(version 0.4.3)

(generate_opam_files true)

(source
 (github prekel/typed-sql))

(authors "Vladislav Prekel")

(maintainers "Vladislav Prekel")

(license MIT)

(package
 (name typed-sql)
 (synopsis "Typed relational query DSL for OCaml")
 (description
  "A backend-independent OCaml DSL for typed relational statements with static and dynamic compilation.")
 (depends
  (ocaml (>= 4.14.1))
  base
  zarith
  ptime
  yojson
  ppx_let
  ppx_sexp_conv
  (ppx_fields_conv :with-test)
  (qcheck :with-test)
  (ipaddr :with-test)
  (mdx :with-test)
  (ppx_expect :with-test)
  (bisect_ppx :with-dev-setup)
  (ocamlformat (and (= 0.29.0) :with-dev-setup))
  (ocaml-lsp-server :with-dev-setup))
 (tags
  (database sql query dsl postgresql sqlite)))

(package
 (name typed-sql-caqti-lwt)
 (synopsis "Caqti Lwt execution backend for typed-sql")
 (description
  "An Lwt adapter that runs typed-sql statements through Caqti PostgreSQL and SQLite connections.")
 (depends
  (ocaml (>= 4.14.1))
  (typed-sql (= :version))
  base
  ptime
  yojson
  ppx_let
  (caqti (and (>= 3.0.0) (< 3.1.0~)))
  (caqti-lwt (and (>= 3.0.0) (< 3.1.0~)))
  lwt
  base-unix
  (caqti-driver-sqlite3 :with-test)
  caqti-driver-postgresql
  uri)
 (tags
  (database sql caqti lwt postgresql sqlite)))

(package
 (name typed-sql-pgocaml-lwt)
 (synopsis "PG'OCaml Lwt execution backend for typed-sql")
 (description
  "An Lwt adapter that runs typed-sql statements through PG'OCaml on PostgreSQL.")
 (depends
  (ocaml (>= 4.14.1))
  (typed-sql (= :version))
  base
  ptime
  ppx_let
  lwt
  uri
  (pgocaml (>= 4.3.0)))
 (tags
  (database sql pgocaml lwt postgresql)))

(package
 (name typed-sql-schema)
 (synopsis "Schema metadata, snapshots and code generation for typed-sql")
 (description
  "Build-time schema metadata and OCaml descriptor generation for typed-sql.")
 (depends
  (ocaml (>= 4.14.1))
  (typed-sql (= :version))
  base
  yojson
  ppx_let
  (ppx_expect :with-test)
  (ipaddr :with-test)
  (zarith :with-test))
 (tags
  (database sql schema codegen)))

(package
 (name typed-sql-schema-caqti-lwt)
 (synopsis "Caqti Lwt schema introspection for typed-sql")
 (description
  "PostgreSQL and SQLite schema introspection and snapshot dumping through Caqti Lwt.")
 (depends
  (ocaml (>= 4.14.1))
  (typed-sql-schema (= :version))
  base
  ppx_let
  (caqti (and (>= 3.0.0) (< 3.1.0~)))
  (caqti-lwt (and (>= 3.0.0) (< 3.1.0~)))
  lwt
  caqti-driver-postgresql
  (caqti-driver-sqlite3 :with-test)
  uri)
 (tags
  (database sql schema caqti lwt postgresql sqlite)))

(package
 (name typed-sql-schema-pgocaml-lwt)
 (synopsis "PG'OCaml Lwt schema introspection for typed-sql")
 (description
  "PostgreSQL schema introspection and snapshot dumping through PG'OCaml Lwt.")
 (depends
  (ocaml (>= 4.14.1))
  (typed-sql-schema (= :version))
  (typed-sql-pgocaml-lwt (= :version))
  base
  ppx_let
  lwt
  uri
  (pgocaml (>= 4.3.0)))
 (tags
  (database sql schema pgocaml lwt postgresql)))
