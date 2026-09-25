# typed-sql

`typed-sql` — backend-independent typed relational query DSL для OCaml.
`Statement.t` служит единым объектом выполнения. Фиксированная форма SQL
проверяется и компилируется при инициализации OCaml-модуля; динамическая форма
может безопасно строиться из типизированного input при каждом вызове.

Текущий срез поддерживает типизированные `SELECT` с joins, derived tables,
CTE, portable set operations, выражениями, aggregates, `GROUP BY`, correlated
subqueries и вложенными коллекциями, calendar date, timestamp и UUID. DML
включает multi-row `INSERT`, portable UPSERT, scoped `UPDATE`/`DELETE`,
`DEFAULT`, `UPDATE FROM`, условные assignments и `RETURNING`.
Пакет `typed-sql-caqti-lwt` содержит адаптеры Caqti для PostgreSQL и SQLite и
умеет читать их схему; `typed-sql-pgocaml-lwt` содержит PostgreSQL-адаптер для
PG'OCaml. Runtime-набор проверен на PostgreSQL 18.6 через оба адаптера; другие
major versions PostgreSQL пока не проверены.

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

type find_people =
  { name : string
  ; maximum_rows : int
  }

let find_people =
  Statement.Portable.query_many_exn (fun params ->
    let name = params.column Person.name_col ~get:(fun input -> input.name) in
    let maximum_rows =
      params.non_negative_int
        ~name:"maximum_rows"
        ~get:(fun input -> input.maximum_rows)
    in
    Query.(
      from Person.table
      |> where (fun person -> Person.name person =. name)
      |> order_by (fun person -> Person.id person) `Asc
      |> limit_param maximum_rows
      |> select (fun person ->
        Projection.pair (Person.id person) (Person.name person))))
```

`Query.(...)` локально открывает только query-builder и сохраняет видимой
границу DSL. `select` ставится последним: он задаёт projection и превращает
builder в готовый `Result_query.t`.

Callback `query_many_exn` вызывается один раз во время создания значения.
`params.column` выводит SQL-тип из descriptor колонки, поэтому отдельный
аппликативный список параметров не нужен. Для статического statement
`Statement.sql` возвращает канонический SQL без input: он читает заранее
скомпилированный template и не запускает parameter getters. Если передать
`~input`, getters и проверки параметров выполняются так же, как перед запуском
через adapter. Значения в SQL не интерполируются:

Операторы с `$`, `Expr.constant`, `Insert.set` и `Update.set` захватывают
константы времени создания statement. Меняющиеся между вызовами значения
вводятся через `params` и используются как expressions операторами с точкой.
Input может быть обычным кортежем, кортежем с метками или record; полные
варианты приведены в [документации](doc/statement_inputs.mld).

Если input задаёт саму структуру запроса, например рекурсивный язык предикатов
или список переменной длины для `IN`, используется
`Statement.Dynamic.Portable`. Callback получает input целиком; DSL всё равно
создаёт bind parameters и компилирует portable SQL для dialect соединения.
Подробный пример находится в
[документации динамических statements](doc/dynamic_statements.mld).

```ocaml
let sql =
  Statement.sql
    ~dialect:Dialect.Postgresql
    find_people
```

```sql
SELECT
  t0."id",
  t0."name"
FROM "people" AS t0
WHERE
  (t0."name" = $1)
ORDER BY
  t0."id" ASC
LIMIT $2
```

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

## Вложенные коллекции

`Query.multiset` превращает завершённый SELECT в одну типизированную
projection со списком строк. Вложенный запрос может ссылаться на источники
внешнего запроса, а `Projection.map` продолжает декодировать каждый элемент:

```ocaml
let people_with_departments =
  Query.(
    from Person.table
    |> select (fun person ->
      let departments =
        Query.(
          from Department.table
          |> where (fun department ->
            Department.person_id department =. Person.id person)
          |> order_by Department.name `Asc
          |> select (fun department -> Projection.expr (Department.name department)))
      in
      Projection.both
        (Projection.expr (Person.name person))
        (Query.multiset departments)))
```

`Projection.multiset_agg` собирает строки текущей aggregate-группы. Его
`order_by` задаёт гарантированный порядок списка, а `filter` позволяет убрать
пустую сторону `LEFT JOIN`:

```ocaml
Projection.multiset_agg
  ~filter:(Comment.article_id comment =. Article.id article)
  ~order_by:[ Aggregate_order.asc (Comment.created_at comment) ]
  (Comment.projection comment)
```

Обе операции возвращают пустой список при отсутствии строк и поддерживают
рекурсивные коллекции. JSON-массивы используются только как переносимый
внутренний формат между PostgreSQL или SQLite и decoder. Для ordered
`multiset_agg` требуется SQLite 3.45 или новее. Бинарные поля пока не
поддерживаются внутри коллекций.

## Составные отношения, операции множеств и CTE

Для промежуточной relation её SQL-поля можно описать прямо в завершающем
`Query.select_relation`. Типы выводятся из expressions, SQL-имена назначаются
детерминированно, а `Query.from_relation` возвращает expressions той же
структуры:

```ocaml
let active_people =
  Query.(
    from Person.table
    |> where (fun person -> Person.name person =$ "Ada")
    |> select_relation (fun person ->
      Derived_table.Fields.pair (Person.id person) (Person.name person)))

let query =
  Query.(
    from_relation active_people
    |> where (fun (id, _name) -> id >$ 10L)
    |> select (fun (id, name) -> Projection.pair id name))
```

`Derived_table.Fields` намеренно не имеет аналога `Projection.map`: результат
произвольного OCaml-преобразования нельзя снова представить как SQL-поля.
`Fields.expr` и `Fields.both` позволяют собирать структурные описания большей
глубины. Такие relation также принимают `Query.inner_join_relation`,
`Query.left_join_relation` и `Update.from_relation`.

Когда нужны заданные вручную SQL-имена и descriptors, низкоуровневый
`Derived_table.create` связывает готовый `SELECT` с `Table.t` и `Column.t`.
Такой результат передаётся в `Query.from_derived`, join-варианты или
`Update.from_derived`. Компилятор проверяет прямые колонки descriptor,
уникальность имён и совпадение database-типов с projection внутреннего
`SELECT`.

`Query.union`, `Query.union_all`, `Query.intersect` и `Query.except` работают
для двух завершённых `SELECT` с одинаковой последовательностью database-типов.
Операции portable для PostgreSQL и SQLite. PostgreSQL-варианты
`Postgresql.Query.intersect_all` и `Postgresql.Query.except_all` добавляют
требование PostgreSQL к statement. Каждый operand set operation renderer
оборачивает в derived branch, поэтому локальные `ORDER BY`, `LIMIT` и `OFFSET`
сохраняют семантику до объединения результатов.

`Cte.select` создаёт именованную relation из derived table, а
`Cte.with_result` и `Cte.with_command` делают её handle видимым только внутри
callback внешнего `SELECT`, DML с `RETURNING` или команды. Handle используется
через `Query.from_cte`/join-варианты и `Update.from_cte`. `Cte.recursive`
задаёт anchor и recursive step с единственной типизированной self-reference;
вариант рекурсии выбирается через `` `Union`` или `` `Union_all``.

Для non-recursive SELECT CTE `Cte.select` принимает hints
`` `Materialized`` и `` `Not_materialized``. Они доступны в PostgreSQL и в
SQLite версии 3.35 или новее; более старый SQLite эти hints не поддерживает.
Data-modifying CTE оформляются только через `Postgresql.Cte.returning` и
`Postgresql.Cte.command`, поэтому требуют PostgreSQL уже в типе statement и не
имеют SQLite-замены. Первый вариант открывает relation из `RETURNING` внешнему
statement, второй выполняется только ради эффекта.

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
  Statement.Portable.command_exn (fun _ ->
    Insert.(
      into Person.table
      |> set Person.id_col 1L
      |> set Person.name_col "Ada"
      |> on_conflict_do_nothing
      |> command))
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
для одной строки используйте `Statement.Portable.expect_optional_exn`. Без
`where` обновляется каждая
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

`Statement` не содержит connection или `Lwt.t`. Выполнение имеет один API для
любой cardinality и для команд:

```ocaml
Typed_sql_caqti_lwt.run
  ~conn
  find_people
  { name = "Ada"; maximum_rows = 100 }
```

Чтобы найти запросы, на которых заметна стоимость DSL compilation, Caqti
adapter принимает необязательный observer. Встроенный profiler ограничивает
число хранимых SQL shapes и строит отчёт по суммарному времени локальной
подготовки:

```ocaml
let profiler = Typed_sql_caqti_lwt.Profiler.create ()
let observer = Typed_sql_caqti_lwt.Profiler.observer profiler

let fetch_people conn input =
  Typed_sql_caqti_lwt.run
    ~observer
    ~name:"people.by_name"
    ~conn
    find_people
    input

let print_profile () =
  Stdlib.Format.printf
    "%a%!"
    Typed_sql_caqti_lwt.Profiler.pp
    (Typed_sql_caqti_lwt.Profiler.snapshot profiler)
```

Событие измеряет подготовку Caqti request, database round trip и декодирование.
Для dynamic statement построение DSL и compilation происходят до начала
события и поэтому в него не входят. Большое время `database` следует разбирать
через план SQL и индексы.

Транзакционная граница также принадлежит adapter:

```ocaml
Typed_sql_caqti_lwt.transaction ~conn ~f:(fun conn ->
  Typed_sql_caqti_lwt.run ~conn insert_once ()
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
[`lib/typed_sql.mli`](lib/typed_sql.mli): схема, выражения, запросы, статические
и динамические statements, канонический SQL и ошибки. Для приложения достаточно библиотеки
`typed-sql` и выбранного execution adapter.

Авторы адаптеров используют отдельную библиотеку `typed-sql.backend` и
[`backend/typed_sql_backend.mli`](backend/typed_sql_backend.mli): параметры,
codec, шаблоны, shape и декодеры. Она разрешает `Statement.t` для dialect
соединения и получает план с текущими bind values.

Почему `Statement` стал единственным execution API и какие варианты
рассматривались, описано в
[`doc/adr/0001-static-statement-api.md`](doc/adr/0001-static-statement-api.md).

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

SQLite integration tests используют `sqlite3::memory:`. Отдельный
`make test-postgres` создаёт временный кластер PostgreSQL 18 на локальном Unix
socket, запускает Caqti и PG'OCaml integration tests, включая общие SQL golden
cases на PostgreSQL и SQLite, и удаляет кластер после прогона. Нужны утилиты
PostgreSQL 18 (`pg_config`, `initdb`, `pg_ctl`, `createdb`, `psql`), opam-пакет
`caqti-driver-postgresql` и системная библиотека разработки `libpq`.
На Ubuntu для сборки SQLite driver нужен системный пакет `libsqlite3-dev`.

Проверен PostgreSQL 18.6. Nullable scalar subquery возвращает `None` как при
отсутствии строки, так и при SQL `NULL` в найденной строке. PG'OCaml сообщает
число затронутых строк как `Affected_rows.Unknown`. Native PostgreSQL JSON и
array codecs остаются за пределами portable API; вложенные коллекции проходят
через JSON transport адаптера.

### Prepared statements

`Statement.t` хранит скомпилированную форму SQL в OCaml; подготовленный запрос
базы данных живёт отдельно на конкретном connection. Caqti adapter создаёт
`Request.Dynamic`: драйвер PostgreSQL подготавливает SQL при первом вызове и
повторно использует его через кэш connection. Драйвер SQLite аналогично
сохраняет `sqlite3_stmt` и выполняет его повторно после reset. Кэш Caqti
ограничен: его стандартная ёмкость для dynamic requests — 32, она настраивается
через `Caqti.Connect.Config.dynamic_prepare_capacity`.

PG'OCaml `run` по умолчанию вызывает `prepare` для каждого выполнения.
Для часто вызываемого statement можно создать явный кэш на одном connection:

```ocaml
let open Lwt.Syntax in
let module Adapter = Typed_sql_pgocaml_lwt in
let cache =
  match Adapter.Prepared_cache.create ~capacity:32 ~conn () with
  | Ok cache -> cache
  | Error error -> failwith (Adapter.error_to_string error)
in
Lwt.finalize
  (fun () -> Adapter.Prepared_cache.run cache statement input)
  (fun () ->
    let* closed = Adapter.Prepared_cache.close cache in
    match closed with
    | Ok () -> Lwt.return_unit
    | Error error -> Lwt.fail_with (Adapter.error_to_string error))
```

Ключ кэша включает SQL и упорядоченные PostgreSQL-типы параметров. При
вытеснении и `close` адаптер закрывает именованные statements на сервере.
После изменения схемы создайте новый кэш; для нового connection также нужен
новый кэш. Временный PostgreSQL 18.6 дал 1,96× для 2000 повторов простого
запроса через PG'OCaml adapter (0,510 с без кэша, 0,260 с с кэшем). Повторить
замер можно командой `TYPED_SQL_PREPARE_BENCH=1 make test-postgres`.

`make coverage` измеряет реализацию `Typed_sql` через публичный API приложения:
запускает public inline tests, QCheck properties и SQLite `:memory:` integration
test. White-box tests и `typed-sql.backend` в этот прогон не входят. Порог равен
97%, HTML-отчёт создаётся в `_coverage/public/html/index.html`.

`make coverage-all` добавляет backend и private suites, требует не менее 99% и
пишет отчёт в `_coverage/all/html/index.html`. Для локального switch с OCaml
5.1.1 `make deps_all` закрепляет `bisect_ppx` на upstream commit, совместимом с
используемым `ppxlib`.
