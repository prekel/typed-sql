# typed-sql

`typed-sql` — backend-independent typed relational query DSL для OCaml. Query
строится как immutable deferred value, компилируется в dialect-specific SQL и
только затем передаётся execution backend.

Текущий срез поддерживает типизированные `SELECT` с joins, portable
выражениями, aggregates, `GROUP BY`, correlated subqueries, calendar date,
timestamp и UUID. DML
включает multi-row `INSERT`, portable UPSERT, scoped
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

`Compiled_query.sql` возвращает тот же канонический многострочный SQL, который
execution adapter отправляет в базу. Значения не интерполируются и остаются
bind parameters:

```sql
SELECT
  t0."id",
  t0."name"
FROM "people" AS t0
WHERE
  (t0."name" = $1)
ORDER BY
  t0."id" ASC
LIMIT 100
```

Для вывода в formatter доступен `Compiled_query.pp`; он печатает в точности
результат `Compiled_query.sql`. Для DML такое же соглашение действует у
`Compiled_command.sql` и `Compiled_command.pp`.

Scalar subquery выражает возможное отсутствие строки через `option` и требует
явного доказательства cardinality: `LIMIT 0`/`LIMIT 1` либо aggregate без
`GROUP BY`. Например:

```ocaml
let department_name person =
  Expr.scalar_subquery
    Query.(
      from Department.table
      |> where (fun department -> Department.person_id department =. Person.id person)
      |> limit 1
      |> select_scalar Department.name)
```

Для уже nullable expression есть `Expr.scalar_subquery_nullable`: SQL не
различает отсутствие строки и строку с `NULL`, поэтому оба случая дают `None`.

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

Для атомарного insert-or-update задаётся непустой conflict target. Callback
получает типизированные ссылки на существующую строку и на предложенную SQL
строку `excluded`:

```ocaml
let upsert_person id name =
  let target = Insert.Conflict_target.column Person.id_col in
  Insert.(
    into Person.table
    |> set Person.id_col id
    |> set Person.name_col name
    |> on_conflict target
    |> do_update (fun ~existing ~excluded ->
      Conflict_update.(
        empty
        |> set_expr Person.name_col (Person.name excluded)
        |> where (Person.name existing <>. Person.name excluded)))
    |> returning (fun person ->
      Projection.pair (Person.id person) (Person.name person)))
```

Составной target записывается как
`Insert.Conflict_target.(column first_col |> add second_col)`. Вместо
`do_update` можно завершить target-specific политику через `do_nothing`.

`Conflict_update.where` ограничивает обновление при конфликте; обычную вставку
он не фильтрует. Повторные условия объединяются через `AND`. Если условие
ложно или равно SQL NULL, строка не обновляется и не попадает в `RETURNING` —
для одной строки используйте `fetch_opt`. Без `where` обновляется каждая
конфликтующая строка. `set_opt` и `set_expr_opt` пропускают `None`;
`set_opt nullable_col (Some None)` записывает NULL.

Conflict target описывает колонки уникального ключа. Наличие подходящего
ограничения проверяет БД; partial indexes и именованные constraints пока не
входят в этот API. Compiler дополнительно проверяет, что target и update
assignments принадлежат таблице INSERT, даже если разные descriptors используют
один phantom-тип. В multi-row UPSERT не следует повторять один конфликтующий
ключ: PostgreSQL отклоняет повторное обновление одной строки в одном запросе.

Операции, семантика которых отсутствует в выбранном dialect, возвращают
`Compile_error.Unsupported_operation` до rendering.

Query не содержит connection или `Lwt.t`. Materialization выполняется отдельно:

```ocaml
Typed_sql_caqti_lwt.fetch ~conn (query "Ada")
```

Чтобы найти запросы, на которых заметна стоимость DSL compilation, Caqti
adapter принимает необязательный observer. Встроенный profiler ограничивает
число хранимых SQL shapes и строит отчёт по суммарному времени локальной
подготовки:

```ocaml
let profiler = Typed_sql_caqti_lwt.Profiler.create ()
let observer = Typed_sql_caqti_lwt.Profiler.observer profiler

let fetch_person conn name =
  Typed_sql_caqti_lwt.fetch_one
    ~observer
    ~name:"people.by_name"
    ~conn
    (query name)

let print_profile () =
  Stdlib.Format.printf
    "%a%!"
    Typed_sql_caqti_lwt.Profiler.pp
    (Typed_sql_caqti_lwt.Profiler.snapshot profiler)
```

Событие отдельно измеряет compilation, подготовку Caqti request, database
round trip и декодирование. Большое время `database` следует разбирать через
план SQL и индексы. Накопленное `compile` показывает верхнюю границу выигрыша
от заранее созданного `Compiled_query`:

```ocaml
let compiled =
  Typed_sql.Compiler.compile ~dialect:Typed_sql.Dialect.Sqlite (query "Ada")

let fetch_compiled conn =
  match compiled with
  | Error error -> Lwt.return (Error (Typed_sql_caqti_lwt.Compile error))
  | Ok query -> Typed_sql_caqti_lwt.fetch_one_compiled ~conn query
```

`Compiled_query` содержит конкретные bind values. Для одной формы запроса с
меняющимися значениями нужен будущий `Prepared_query`; параметризованный запрос
нельзя заменить одним `Compiled_query` без изменения результата.

Транзакционная граница также принадлежит adapter:

```ocaml
Typed_sql_caqti_lwt.transaction ~conn ~f:(fun conn ->
  Typed_sql_caqti_lwt.execute ~conn insert_once
  |> Lwt.map (Result.map ~f:(fun _ -> ())))
```

При изменении схемы Caqti adapter получает metadata, которую можно сохранить
как JSON snapshot:

```ocaml
Typed_sql_caqti_lwt.Schema.introspect ~conn
|> Lwt.map
     (Result.map ~f:(fun schema ->
        Stdlib.Out_channel.with_open_bin "schema.json" (fun channel ->
          Stdlib.output_string channel (Schema_snapshot.to_string schema))))
```

Snapshot хранится в репозитории. Установленный вместе с `typed-sql` CLI читает
его без подключения к базе и выводит OCaml source:

```sh
typed-sql-codegen schema.json > schema.ml
typed-sql-codegen - < schema.json > schema.ml
```

В Dune можно генерировать модуль при изменении snapshot:

```lisp
(rule
 (target schema.ml)
 (deps schema.json)
 (action
  (with-stdout-to %{target}
   (run %{bin:typed-sql-codegen} %{dep:schema.json}))))
```

Библиотека, компилирующая `schema.ml`, должна зависеть от `base` и `typed-sql`
и использовать `(preprocess (pps ppx_let))`. Можно также хранить готовый `.ml`
в репозитории. Generator добавляет необходимые
`open`, а совпавшие после нормализации OCaml-имена получают стабильные суффиксы
`_2`, `_3` в порядке schema IR.

Формат JSON и обработка ошибок описаны в
[doc/schema_snapshot.md](doc/schema_snapshot.md). Получение схемы и применение
миграций запускаются отдельно от обычной сборки.

Неизвестные database types сохраняются как `Schema_ir.Unsupported`, и generator
возвращает ошибку вместо выбора неточного codec.

Весь API приложения с документацией находится в
[`lib/typed_sql.mli`](lib/typed_sql.mli): схема, выражения, запросы, компиляция,
канонический SQL, printers и ошибки. Для приложения достаточно библиотеки
`typed-sql` и выбранного execution adapter.

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
