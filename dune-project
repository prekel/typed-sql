(lang dune 3.23)

(name typed-sql)

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
  "A backend-independent OCaml DSL for constructing, validating, and compiling typed relational queries.")
 (depends
  (ocaml (>= 5.5.1))
  base
  ppx_let
  (qcheck :with-test)
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
  "An Lwt adapter that executes typed-sql queries through Caqti PostgreSQL and SQLite connections.")
 (depends
  (ocaml (>= 5.5.1))
  (typed-sql (= :version))
  base
  ppx_let
  (caqti (and (>= 3.0.0) (< 3.1.0~)))
  (caqti-lwt (and (>= 3.0.0) (< 3.1.0~)))
  lwt
  (caqti-driver-sqlite3 :with-test)
  (uri :with-test))
 (tags
  (database sql caqti lwt postgresql sqlite)))

(package
 (name typed-sql-pgocaml-lwt)
 (synopsis "PG'OCaml Lwt execution backend for typed-sql")
 (description
  "An Lwt adapter that executes typed-sql queries through PG'OCaml on PostgreSQL.")
 (depends
  (ocaml (>= 5.5.1))
  (typed-sql (= :version))
  base
  ppx_let
  lwt
  (pgocaml (>= 4.4.0)))
 (tags
  (database sql pgocaml lwt postgresql)))
