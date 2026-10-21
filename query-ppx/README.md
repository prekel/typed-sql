# SQL quotations из кеша для typed-sql

Экспериментальный пакет `typed-sql-ppx` строит запросы для существующих
adapters typed-sql. Сборка и LSP не подключаются к PostgreSQL. Здесь используется
только кеш Prepare/Describe; snapshot схемы не подходит. Пакет доступен
начиная с v0.5.1; используйте одинаковую версию ядра, schema, PPX,
online-инструмента и выбранного adapter. API остаётся экспериментальным.

- `[%pgsql.query "..."]` → `Result_query.t`, scalar или tuple.
- `[%pgsql.query.object "..."]` → `Result_query.t`, объект с методами полей.
- `[%pgsql.command "..."]` → `Command.t` для INSERT/UPDATE/DELETE без RETURNING.
- `[%pgsql.statement "..."]` → `Statement.t` с runtime input, scalar/tuple-строками
  или `Affected_rows.t` для DML без RETURNING.
- `[%pgsql.statement.object "..."]` → `Statement.t` с runtime input и списком объектов.

SELECT и INSERT/UPDATE/DELETE RETURNING различаются по kind в кеше v2.
SQL имеет статическую форму. Подстановки `$name`, `$?name` и `${expression}`
в `.query` и `.command` принимают `Expr.t`, представляющие bind slot или
`Expr.constant`; в `.statement` — обычные OCaml-значения. Колонки,
вычисляемые SQL expressions, native `$1` и динамические lists не поддерживаются.

## Подключение

Для подготовки установите `typed-sql-pgocaml-ppx`: он предоставляет
`typed-sql-pgocaml-queries`. Выполните миграции тестовой БД и подготовьте кеш
для исходников одной библиотеки приложения. Shell glob раскрывается до вызова
инструмента; не захватывайте `_build` или библиотеки другой БД:

```bash
shopt -s globstar nullglob
sources=(src/db/**/*.ml)
typed-sql-pgocaml-queries prepare --output src/db/queries.json "${sources[@]}"
```

Если SQL создаёт другой PPX, добавьте одинаковый `--pp COMMAND` в `prepare`
и `check`. Сборщик применит preprocessing до поиска quotations; обычная
сборка должна раскрывать те же fragments. Подключение standalone-драйвера
с `preprocess_impl` описано в [инструкции](../ppx/TRY_IN_APP.md#sql-из-другого-ppx).

После изменения SQL или схемы повторите `prepare`. `check --cache` проверяет
актуальность кеша с доступом к БД. Пользовательский SQL при подготовке не
выполняется. Кеш v1 нужно обновить: новый PPX требует kind и placement из v2.
В кеше нет OID, значений input или credentials. При выполнении сохраняйте
совместимые schema/search_path и роль: сохранённые metadata не меняют
разрешение неквалифицированных имён на соединении.

В `src/db/dune`:

```lisp
(rule
 (target app_queries_ppx.ml)
 (deps queries.json)
 (action
  (with-stdout-to %{target}
   (run typed-sql-pgocaml-queries codegen --target typed-sql-ppx %{dep:queries.json}))))

(library
 (name app_queries_ppx)
 (kind ppx_rewriter)
 (modules app_queries_ppx)
 (libraries base typed-sql-ppx))

(library
 (name app_db)
 (modules people)
 (libraries base typed-sql typed-sql-caqti-lwt)
 (preprocess (pps ppx_let app_queries_ppx)))
```

`typed-sql-ppx`, его runtime и `typed-sql-ppx.cache` не зависят от PGOCaml.
Online-инструмент зависит от PGOCaml, включая показанный Dune codegen.
Для среды сборки без PGOCaml заранее сохраните сгенерированный
`app_queries_ppx.ml` в исходниках и уберите rule. JSON уже встроен в этот модуль;
раскрытие quotations не читает файлы по относительным путям.

## Прямой Statement с runtime input

Quotation задаёт готовый Statement на уровне модуля. Pattern после `fun`
описывает input при запуске; SQL и metadata определяют типы параметров:

```ocaml
type find_input = { id : int; name : string }

let find =
  [%pgsql.statement.object
    fun { id; name } ->
      "SELECT id, name FROM people WHERE id = $id AND name = $name"]

let insert =
  [%pgsql.statement
    fun (id, name) ->
      "INSERT INTO people (id, name) VALUES ($id, $name) RETURNING id, name"]

let delete =
  [%pgsql.statement fun id -> "DELETE FROM people WHERE id = $id"]

let optional_name =
  [%pgsql.statement fun name -> "SELECT $?name::text AS name"]
```

`find` имеет тип ``(find_input, < id : ...; name : ... > list, [`Postgresql]) Statement.t``.
Запуск: `Adapter.run ~conn find { id; name }`. `insert` принимает пару
`int * string`, `delete` — `int`, `optional_name` — `string option`.
Функция внутри quotation — синтаксис объявления input, а не функция,
возвращающая Statement. PPX генерирует `Statement.with_parameters`, typed
bind slots и getters; SQL компилируется один раз при определении Statement.
При каждом запуске getters читают новый input без перестроения запроса.
Подстановки остаются bind parameters; значения не попадают в SQL.

Можно использовать `${input.id}` с `fun (input : find_input) -> ...` или
вычисление `${expression}` над входами. Вычисление выполняется при binding,
а не при определении Statement. `Expr.t` в input не требуется. Точные
OCaml-типы следуют metadata кеша, включая optional, enum/domain и arrays.
Для параметризованного SQL input-pattern обязателен: неявного захвата
локальных значений нет. Поддерживается один неименованный аргумент `fun`;
несколько полей передаются записью или tuple.

`.statement` возвращает список scalar/tuple-строк для SELECT и RETURNING
либо `Affected_rows.t` для DML без RETURNING. `.statement.object` требует
строки результата. Флаг `"nullable-results"` ставится после `->` перед SQL.
Для SQL без параметров input-pattern отклоняется; используйте короткую форму
`let all = [%pgsql.statement "SELECT id FROM people"]` с input `unit`.

Для композиции запросов с DSL используйте `.query` / `.command` и явный
`Statement.with_parameters`, как показано ниже.

## Статический Statement с input

```ocaml
open! Base
open Typed_sql

type input = { status : string; limit : int64 }

let find =
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let%map.Parameters status =
      params.expr Db_type.text ~get:(fun input -> input.status)
    and limit = params.expr Db_type.int64 ~get:(fun input -> input.limit) in
    params.query_many
      [%pgsql.query.object
        "SELECT id, name FROM people WHERE status = $status LIMIT $limit"])
```

`Adapter.run ~conn find { status; limit }` читает input через getters.
Запрос и план строятся при определении `find`, повторной компиляции нет.
Отдельный `Statement.Dynamic` не нужен. Выносите функцию-builder с именованными
аргументами `Expr.t`, если хотите переиспользовать запрос; сам Statement
сохраняйте снаружи прикладной функции.

Например, функцию с именованными `Expr.t` можно записать так:

```ocaml
let people_query ~status ~limit =
  [%pgsql.query.object
    "SELECT id, name FROM people WHERE status = $status LIMIT $limit"]
```

Внутри `let%map.Parameters` передайте её результат в
`params.query_many (people_query ~status ~limit)`.

Для SQL NULL используйте `params.expr (Db_type.option Db_type.text)` и `$?name`.
Для `params.optional_expr` передавайте `Optional_parameter.nullable_expr parameter`.
Nullable Expr в `$name` не принимается. Flag `"nullable-results"` перед SQL
делает все выходные поля optional; по умолчанию nullability берётся из Describe
по контракту PG’OCaml. Для expressions без column origin результат optional.
Эта эвристика не доказывает nullability произвольного SQL, например outer JOIN.

```ocaml
let remove =
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let%map.Parameters id = params.expr Db_type.int ~get:Fn.id in
    params.command [%pgsql.command "DELETE FROM people WHERE id = $id"])
```

INSERT/UPDATE/DELETE RETURNING используйте через `.query` или `.query.object`.
Команды возвращают `Affected_rows.t`. Ошибки выполнения adapters возвращают
через `Result.t`. Raw queries имеют cardinality many; `Statement.expect_one`
и `Statement.expect_optional` проверяют число строк при выполнении.

## Композиция с query builder

Обычные SELECT можно объединять с DSL через `Query.union_all`, использовать
в `Derived_table.create` и `Cte.select`, задав точные descriptors выходных
колонок. Object output описывает decoder, а relation fields задаются отдельно.
Descriptor сравнивается по SQL-типу, одного совпадения OCaml-типов недостаточно.
Данные, SQL aliases и bind indices обрабатывает обычный compiler.

SELECT с data-modifying CTE или внешним row lock помечается top-level-only: вложение
в derived table, UNION или multiset отклоняется. DML RETURNING имеет отдельный
kind и может стать `Postgresql.Cte.returning`; DML без результата —
`Postgresql.Cte.command`. Присоединение DSL CTE снаружи top-level-only raw SQL
пока отклоняется. Неизвестные формы WITH, MERGE и utility statements отклоняются
новым PPX; серверная поддержка SQL сама по себе не делает их композиционными.
Row locks внутри вложенных SELECT и читающих CTE не накладывают этот запрет
на внешний SELECT; data-modifying CTE сохраняют ограничение.

Raw SQL остаётся PostgreSQL-only и при использовании Caqti. SQLite не принимает
эти запросы. Общее API ручных fragments — `Raw_sql.Postgresql`: `unsafe_sql`,
`bind`, `select`, `returning`, `command`; positional output задаёт аппликативный
`Raw_sql.Output`. Автор ручного raw SQL отвечает за синтаксис и output metadata;
fragments не должны содержать собственных placeholders или терминаторов.

## Миграция с pgocaml_ppx

1. Сначала замените выполняющий PPX на совместимый offline
   `typed-sql-pgocaml-ppx`, сохранив quotations, соединения, deriving и
   `List.map results ~f:t_of_pgocaml`: [инструкция](../ppx/TRY_IN_APP.md).
2. Для одного запроса подготовьте кеш v2 и подключите новый пакет. Замените
   `%pgsql.object dbh` на `%pgsql.query.object`, значения — на `Expr.t` и создайте
   статический Statement, как выше. Выполняйте через adapter на том же соединении
   и в той же транзакции. PGOCaml adapter поддерживает существующий модуль через
   `Typed_sql_pgocaml_lwt.Make (PGOCaml)`.
   При переносе по одному запросу оставьте оба PPX в Dune:
   `(pps ppx_let legacy_queries_ppx app_queries_ppx)`. Первый provider
   регистрирует metadata в `Typed_sql_pgocaml_ppx`, второй — в `Typed_sql_ppx`;
   их registry независимы. Для legacy provider можно использовать snapshot
   или codegen кеша без `--target`. Один кеш v2 пригоден для обоих codegen.
   В приложении пока остаются runtime dependencies старых quotations.

3. Сохраните object → record converter, если типы методов совпадают. Здесь `int4`
   — `int`, а не `int32`; numeric — `Decimal.t`; date — `Date.t`; timestamptz —
   `Ptime.t`; timestamp — `Local_timestamp.t`; interval — `Interval.t`; arrays —
   `Pg_array.t`. Enum — string с named descriptor, domain — named descriptor
   базового представления. Для их input используйте такой же
   `Db_type.Postgresql.named`, а не обычный text/int. Native `int2`, `float4`,
   `varchar`, `bpchar`, `time` тоже сохраняют named descriptor при обычном
   OCaml-представлении int/float/string. Если metadata требуют такой тип,
   задайте его в `params.expr` явно; одного совпадения OCaml-типа недостаточно.
   Custom converters отсутствуют.
4. При необходимости смените adapter на Caqti PostgreSQL. Query/Statement
   остаются прежними. Добавьте обработку `Result.t` и `Affected_rows.t`.
5. Переписывайте отдельные запросы на DSL, сохраняя Statement input.
   Перенос object → record в `Projection.map` убирает промежуточный объект:

```ocaml
Query.(
  from People.table
  |> select (fun person ->
    Projection.map (People.projection person) ~f:record_of_fields))
```

Исполняемые примеры композиции и выполнения обоими adapters находятся в
[test](test/queries.ml) и [integration test](test/postgresql_test.ml).
Snapshot-frontend для новых quotations, произвольные expression holes,
динамические lists отложены в
[roadmap](../doc/ppx_roadmap.md). Custom Type Conversions требуют отдельного согласия.
