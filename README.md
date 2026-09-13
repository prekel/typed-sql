# typed-sql

`typed-sql` — backend-independent typed relational query DSL для OCaml. Query
строится как immutable deferred value, компилируется в dialect-specific SQL и
только затем передаётся execution backend.

Текущий срез поддерживает типизированные `SELECT` с joins, portable
выражениями, aggregates, `GROUP BY`, correlated subqueries, calendar date,
timestamp и UUID. DML
включает multi-row `INSERT`, portable `ON CONFLICT DO NOTHING`, scoped
`UPDATE`/`DELETE`, `DEFAULT`, `UPDATE FROM`, условные assignments и `RETURNING`.
Пакет `typed-sql-caqti-lwt` выполняет запросы через Caqti для PostgreSQL и
SQLite и умеет читать их схему; `typed-sql-pgocaml-lwt` выполняет PostgreSQL
запросы через PG'OCaml.

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

DML строится так же через локальное открытие соответствующего builder:

```ocaml
let insert =
  Insert.(
    rows
      Person.table
      [ (fun row -> row |> set Person.id_col 1L |> set Person.name_col "Ada")
      ; (fun row -> row |> set Person.id_col 2L |> set Person.name_col "Grace")
      ]
    |> command)

let rename =
  Update.(
    table Person.table
    |> set Person.name_col "Ada Lovelace"
    |> where (fun person -> Person.id person =$ 1L)
    |> command)
```

Идемпотентная вставка для поддерживаемых dialect записывается в основном API:

```ocaml
let insert_once =
  Insert.(
    into Person.table
    |> set Person.id_col 1L
    |> set Person.name_col "Ada"
    |> on_conflict_do_nothing
    |> command)
```

Операции, семантика которых отсутствует в выбранном dialect, возвращают
`Compile_error.Unsupported_operation` до rendering.

Query не содержит connection или `Lwt.t`. Materialization выполняется отдельно:

```ocaml
Typed_sql_caqti_lwt.fetch ~conn (query "Ada")
```

Транзакционная граница также принадлежит adapter:

```ocaml
Typed_sql_caqti_lwt.transaction ~conn ~f:(fun conn ->
  Typed_sql_caqti_lwt.execute ~conn insert_once
  |> Lwt.map (Result.map ~f:(fun _ -> ())))
```

Для codegen descriptors Caqti adapter строит dialect-neutral schema IR:

```ocaml
Typed_sql_caqti_lwt.Schema.introspect ~conn
|> Lwt.map (Result.bind ~f:Schema_codegen.generate)
```

Introspection запускается отдельной командой при изменении миграций или схемы,
а полученный `.ml` рекомендуется хранить в репозитории. Обычная сборка затем
компилирует этот файл и не подключается к базе. Generator добавляет необходимые
`open`, а совпавшие после нормализации OCaml-имена получают стабильные суффиксы
`_2`, `_3` в порядке schema IR.

Неизвестные database types сохраняются как `Schema_ir.Unsupported`, и generator
возвращает ошибку вместо выбора неточного codec.

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
make coverage-all
```

Benchmark compiler для маленького запроса и shapes с 20/100 условиями или
сортировками запускается отдельно:

```sh
opam exec -- dune exec benchmark/query_bench.exe
```

SQLite integration tests используют `sqlite3::memory:`. PostgreSQL compiler,
Caqti dialect branch и PG'OCaml adapter собираются без подключения к внешнему
PostgreSQL server.
На Ubuntu для сборки SQLite driver нужен системный пакет `libsqlite3-dev`.

`make coverage` измеряет реализацию `Typed_sql` через публичный API приложения:
запускает public inline tests, QCheck properties и SQLite `:memory:` integration
test. White-box tests и `typed-sql.backend` в этот прогон не входят. Порог равен
97%, HTML-отчёт создаётся в `_coverage/public/html/index.html`.

`make coverage-all` добавляет backend и private suites, требует не менее 99% и
пишет отчёт в `_coverage/all/html/index.html`. Для OCaml 5.5.1 `make deps_all`
временно закрепляет `bisect_ppx` на upstream commit с поддержкой актуального
`ppxlib`.
