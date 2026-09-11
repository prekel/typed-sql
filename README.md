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
open Infix

module Person = struct
  type row

  let table : row Table.t = Table.v_exn "people"
  let id_col = Column.v_exn table "id" Db_type.int64
  let name_col = Column.v_exn table "name" Db_type.text
  let id row = Expr.column row id_col
  let name row = Expr.column row name_col
end

let query name =
  Query.(
    from Person.table
    |> where (fun person -> Person.name person =$ name)
    |> order_by (fun person -> Person.id person) `Asc
    |> limit 100
    |> select (fun person -> Projection.pair (Person.id person) (Person.name person)))
```

`Query.(...)` локально открывает только query-builder и сохраняет видимой
границу DSL. `select` ставится последним: он задаёт projection и превращает
builder в готовый `Result_query.t`.

Query не содержит connection или `Lwt.t`. Materialization выполняется отдельно:

```ocaml
Typed_sql_caqti_lwt.fetch ~conn (query "Ada")
```

Весь API приложения с документацией находится в
[`lib/typed_sql.mli`](lib/typed_sql.mli): схема, выражения, запросы, компиляция,
SQL и ошибки. Для приложения достаточно библиотеки `typed-sql` и выбранного
execution adapter.

Авторы адаптеров используют отдельную библиотеку `typed-sql.backend` и
[`backend/typed_sql_backend.mli`](backend/typed_sql_backend.mli): параметры,
codec, шаблоны, shape и декодеры. Она принимает результаты обычного
`Typed_sql.Compiler` без преобразований.

Внутренняя `typed-sql.private` содержит реализацию только в `.ml`, включая AST
и этапы compiler. White-box тесты используют её напрямую; этот интерфейс не
имеет гарантий совместимости.

## Сборка

Проект использует локальный switch OCaml 5.5.1:

```sh
make create_switch
make deps_all
make check
make release-check
make coverage
```

SQLite integration tests используют `sqlite3::memory:`. PostgreSQL compiler,
Caqti dialect branch и PG'OCaml adapter собираются без подключения к внешнему
PostgreSQL server.
На Ubuntu для сборки SQLite driver нужен системный пакет `libsqlite3-dev`.

`make coverage` измеряет реализацию `Typed_sql` через публичный API приложения:
запускает public inline tests, QCheck properties и SQLite `:memory:` integration
test. White-box tests и `typed-sql.backend` в этот прогон не входят. Команда
требует не менее 97% сырого покрытия и создаёт HTML-отчёт в
`_coverage/html/index.html`. Для OCaml 5.5.1 `make deps_all` временно закрепляет
`bisect_ppx` на upstream commit с поддержкой актуального `ppxlib`.
