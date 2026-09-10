# typed-sql

`typed-sql` — backend-independent typed relational query DSL для OCaml. Query
строится как immutable deferred value, компилируется в dialect-specific SQL и
только затем передаётся execution backend.

Текущий срез поддерживает типизированные `SELECT` с `INNER JOIN` и `LEFT JOIN`,
`WHERE`, `ORDER BY`, `LIMIT` и `OFFSET`, а также single-row `INSERT`, `UPDATE`,
`DELETE` и `RETURNING`. Пакет `typed-sql-caqti-lwt` выполняет запросы через
Caqti для PostgreSQL и SQLite; `typed-sql-pgocaml-lwt` — через PG'OCaml для
PostgreSQL.

```ocaml
open Typed_sql
open Expr.Infix

module Person = struct
  type row

  let table : row Table.t = Table.v_exn "people"
  let id_col = Column.v_exn table "id" Db_type.int64
  let name_col = Column.v_exn table "name" Db_type.text
  let id row = Expr.column row id_col
  let name row = Expr.column row name_col

  let projection row =
    Projection.map2
      (fun id name -> id, name)
      (Projection.expr (id row))
      (Projection.expr (name row))
end

let query name =
  Query.from Person.table ~select:Person.projection
  |> Query.where (fun row -> Person.name row =$ name)
  |> Query.order_by (fun row -> Person.id row) `Asc
  |> Query.limit 100
```

Query не содержит connection или `Lwt.t`. Materialization выполняется отдельно:

```ocaml
Typed_sql_caqti_lwt.fetch ~conn (query "Ada" |> Query.to_result)
```

## Сборка

Проект использует локальный switch OCaml 5.5.1:

```sh
make create_switch
make deps_all
make check
make release-check
```

SQLite integration tests используют `sqlite3::memory:`. PostgreSQL compiler,
Caqti dialect branch и PG'OCaml adapter собираются без подключения к внешнему
PostgreSQL server.
На Ubuntu для сборки SQLite driver нужен системный пакет `libsqlite3-dev`.
