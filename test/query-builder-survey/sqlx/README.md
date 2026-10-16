<!-- SPDX-License-Identifier: MIT -->

# Сценарии запросов из SQLx

40 сценариев для **SQLx 0.9.0**, backend `postgres`, PostgreSQL 18.6.
Пять базовых сценариев и 35 сложных. Схема: `users(id, name, age, parent_id)`
и `posts(id, user_id, title, score)`, см. [DDL](setup.sql).
Примеры написаны для этого обзора по официальному API;
[SQLx распространяется по MIT или Apache-2.0](https://github.com/transact-rs/sqlx/tree/v0.9.0).

SQLx — SQL toolkit: статический SQL проверяют macros, runtime-запросы можно
собирать через `QueryBuilder`. Здесь SX-01–SX-30 используют cached PPX typed-sql,
а SX-31–SX-40 сопоставляют сборку SQLx по частям с ручным `Raw_sql.Postgresql`.
Это сравнение запросов, параметров и типов результата, а не ORM или скорости.

Источники: [query!](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html),
[query_as!](https://docs.rs/sqlx/0.9.0/sqlx/macro.query_as.html),
[query_scalar!](https://docs.rs/sqlx/0.9.0/sqlx/macro.query_scalar.html),
[QueryBuilder](https://docs.rs/sqlx/0.9.0/sqlx/struct.QueryBuilder.html),
[PostgreSQL types](https://docs.rs/sqlx/0.9.0/sqlx/postgres/types/index.html).
Источники SQLx проверены 16.10.2026; SQL адаптирован под общую схему.

## Что проверяется

OCaml-реализации компилируются в библиотеку `Sqlx_survey`.
Блоки с `file`/`part` проверяют соответствие документации исходникам;
следующие за ними REPL-блоки исполняют библиотеку и проверяют SQL snapshots.
Rust-примеры справочные: Cargo и выполнение запросов не входят в MDX.

- OCaml-пример: ✓ — библиотека собирается.
- Реализуемость: ✓ — запрос выражен существующим публичным API.
- Семантика: ✓ — SQL typed-sql соответствует SQL сценария SQLx по смыслу
  запроса, параметрам, обработке NULL и заданному порядку.
- Без доработок typed-sql: ✓ — ядро и публичный API не меняются.

Семантика оценивается сопоставлением SQL из сценария SQLx с SQL, который
выдаёт typed-sql. Различия форматирования и эквивалентные CAST bind-параметров
допустимы; выполнение через СУБД для этой оценки не требуется.

В каждом сценарии есть отдельный SQL snapshot. Все пользовательские значения
остаются bind-параметрами. Для динамических форм показан конкретный вход;
дополнительные ветви проверяет [survey_test.ml](survey_test.ml).
Стабильный порядок задаётся явно, кроме DML RETURNING: его порядок не гарантирован.

## Типы и offline metadata

На стороне SQLx macros требуют доступ к схеме или подготовленный каталог `.sqlx`:
`cargo sqlx prepare`, затем сборка с `SQLX_OFFLINE=true`.
Это кеш Describe metadata, а не кеш результатов. Prepared statements на соединении
кешируются отдельно. `QueryBuilder` не проверяет SQL во время компиляции.
См. [offline mode](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html#offline-mode)
и [sqlx-cli](https://github.com/transact-rs/sqlx/blob/v0.9.0/sqlx-cli/README.md).

Typed-sql использует подготовленный [кеш v2](queries.json), встроенный в
PPX-provider. Quotations `.statement` задают готовый Statement с runtime input;
значения при запуске не требуют повторной компиляции статического SQL.
`int4` отображается в OCaml `int`, в Rust — `i32`; `int8`, COUNT, ROW_NUMBER
и SUM(integer) — в `int64`/`i64`. PostgreSQL-массивы используют `Pg_array.t`; compiler добавляет явный CAST
к массивным bind holes. Поэтому snapshots SX-23–SX-24 содержат дополнительный
CAST относительно исходного SQL.
Nullable-параметры — `option`/`Option`, NULL не равен отсутствию фильтра.
Повтор `$boundary` в quotation создаёт два слота с одинаковым getter;
SX-14 сохраняет эту форму и на стороне SQLx.

Cached PPX использует nullability из Describe по эвристике PG’OCaml.
Для вычисляемых выражений результат обычно optional; это не доказательство
nullability произвольного SQL. В SX-05 и SX-22 `"nullable-results"` явно делает
**все** поля optional, включая левый `id`. SQLx может сохранить левый `id`
как `i32`; значения SQL совпадают, но представления результата различаются.
В этих двух Rust-примерах показан статический `query_as` без macro с явным типом
правой optional-колонки: он также не выполняет compile-time проверку SQL.

`fetch_all` сопоставляется со списком строк, `execute` — с `Affected_rows.t`.
`fetch_one` SQLx берёт первую строку и сообщает ошибку при отсутствии;
`Statement.expect_one` typed-sql требует ровно одну строку. Аналогично
`fetch_optional` не доказывает уникальность, а `expect_optional` проверяет максимум
одну строку. В карточках используются списки, чтобы не подменять эти контракты.

## Воспроизведение

Обычная проверка не требует PostgreSQL, PGOCaml или Rust:

<!-- $MDX skip -->
```sh
opam exec -- dune runtest test/query-builder-survey
```

Для подготовки metadata нужен пакет `typed-sql-pgocaml-ppx` с online-инструментом,
а также локальные PostgreSQL binaries. Скрипт создаёт временный кластер, роль
`typed_sql_survey` и схему, получает Describe без выполнения пользовательского SQL,
затем удаляет кластер. Это отдельная операция, не часть `runtest`:

<!-- $MDX skip -->
```sh
bash test/query-builder-survey/sqlx/cache.sh prepare
bash test/query-builder-survey/sqlx/cache.sh check
```

Метаданные подготовлены PostgreSQL 18.6. Все сценарии PostgreSQL-only:
поддержка PostgreSQL, MySQL/MariaDB и SQLite в SQLx не делает этот SQL переносимым.
Ручной raw SQL не проверяет синтаксис и выводит типы из явно заданного Output;
compiler проверяет descriptors bind-параметров, индексы и размещение запроса.
Для FOR UPDATE нужен контекст транзакции при выполнении.

## Общие определения

Rust-блоки предполагают async-контекст, `pool: PgPool` и входы с именами из SQL.
Целые входы имеют тип `i32`, LIMIT/OFFSET и сравнения COUNT — `i64`, текст —
`String`/`&str`, nullable age — `Option<i32>`; массивы — `Vec<i32>`/`Vec<String>`.
Для SX-24 массивы имеют одинаковую длину: UNNEST иначе дополняет короткий NULL.

```rust
use sqlx::{PgPool, Postgres, QueryBuilder};

struct User { id: i32, name: String }
enum Sort { NameAsc, NameDesc }
enum Condition { MinId(i32), NameLike(String) }
```

```ocaml
open! Base
open Typed_sql
module Q = Sqlx_survey.Queries
module D = Sqlx_survey.Dynamic

let array values =
  Pg_array.create
    ~dimensions:[ List.length values ]
    ~lower_bounds:[ 1 ]
    ~elements:(List.map values ~f:Option.some)
  |> Result.ok_or_failwith
;;

let int_array = array
let text_array = array
```

В ручных примерах `text` принимает только доверенный SQL, `int` и `string`
создают bind holes, `select` и `select_ids` задают точные output descriptors;
`separated` соединяет списки fragments неизменяемыми списками.
Общие определения из [dynamic.ml](dynamic.ml):

<!-- $MDX file=dynamic.ml,part=helpers -->
```ocaml
module Raw = Raw_sql.Postgresql

type sort =
  | Name_asc
  | Name_desc

type condition =
  | Min_id of int
  | Name_like of string

type field =
  | Name of string
  | Age of int option

let text = Raw.unsafe_sql
let int value = Raw.bind Db_type.int (Expr.constant Db_type.int value)
let string value = Raw.bind Db_type.text (Expr.constant Db_type.text value)
let id_output = Raw_sql.Output.field ~name:(Identifier.of_string_exn "id") Db_type.int

let user_output =
  let%map.Raw_sql.Output id = id_output
  and name = Raw_sql.Output.field ~name:(Identifier.of_string_exn "name") Db_type.text in
  id, name
;;

let separated ~sep lists = List.concat (List.intersperse lists ~sep:[ text sep ])
let select parts = Raw.select ~output:user_output parts
let select_ids parts = Raw.select ~output:id_output parts
let rows_required = Error "rows must not be empty"
```

### SX-01. Фильтр и проекция

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: Фильтр и проекция с сохранением параметров и структуры SQL.

```sql
SELECT id, name FROM users WHERE name = $1 ORDER BY id
```

```rust
let rows = sqlx::query!(
    "SELECT id, name FROM users WHERE name = $1 ORDER BY id", name
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx01 -->
```ocaml
let sx01 =
  [%pgsql.statement.object
    fun name -> "SELECT id, name FROM users WHERE name = $name ORDER BY id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:"Ada" Q.sx01 |> Stdlib.print_endline;;
SELECT id, name FROM users WHERE name = $1 ORDER BY id
```

### SX-02. Составной фильтр и именованная строка

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query_as](https://docs.rs/sqlx/0.9.0/sqlx/macro.query_as.html).
- Проверяет: Составной фильтр и именованная строка с сохранением параметров и структуры SQL.

```sql
SELECT id, name FROM users WHERE id > $1 AND name LIKE $2 ORDER BY id
```

```rust
let rows = sqlx::query_as!(
    User, "SELECT id, name FROM users WHERE id > $1 AND name LIKE $2 ORDER BY id", min_id, pattern
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx02 -->
```ocaml
let sx02 =
  [%pgsql.statement
    fun (min_id, pattern) ->
      "SELECT id, name FROM users WHERE id > $min_id AND name LIKE $pattern ORDER BY id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Statement.sql_exn ~dialect:Postgresql ~input:(1, "A%") Q.sx02 |> Stdlib.print_endline;;
SELECT id, name FROM users WHERE id > $1 AND name LIKE $2 ORDER BY id
```

### SX-03. Сортировка и пагинация

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: Сортировка и пагинация с сохранением параметров и структуры SQL.

```sql
SELECT id, name FROM users ORDER BY name, id LIMIT $1 OFFSET $2
```

```rust
let rows = sqlx::query!(
    "SELECT id, name FROM users ORDER BY name, id LIMIT $1 OFFSET $2", limit, offset
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx03 -->
```ocaml
let sx03 =
  [%pgsql.statement
    fun (limit, offset) ->
      "SELECT id, name FROM users ORDER BY name, id LIMIT $limit OFFSET $offset"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Statement.sql_exn ~dialect:Postgresql ~input:(10L, 20L) Q.sx03 |> Stdlib.print_endline;;
SELECT id, name FROM users ORDER BY name, id LIMIT $1 OFFSET $2
```

### SX-04. INNER JOIN

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: INNER JOIN с сохранением параметров и структуры SQL.

```sql
SELECT u.id, p.title FROM users u JOIN posts p ON p.user_id = u.id WHERE p.score >= $1 ORDER BY u.id, p.id
```

```rust
let rows = sqlx::query!(
    "SELECT u.id, p.title FROM users u JOIN posts p ON p.user_id = u.id WHERE p.score >= $1 ORDER BY u.id, p.id", score
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx04 -->
```ocaml
let sx04 =
  [%pgsql.statement
    fun score ->
      "SELECT u.id, p.title FROM users u JOIN posts p ON p.user_id = u.id WHERE p.score >= $score ORDER BY u.id, p.id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:5 Q.sx04 |> Stdlib.print_endline;;
SELECT u.id, p.title FROM users u JOIN posts p ON p.user_id = u.id WHERE p.score >= $1 ORDER BY u.id, p.id
```

### SX-05. LEFT JOIN и NULL справа

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [runtime](https://docs.rs/sqlx/0.9.0/sqlx/fn.query_as.html).
- Проверяет: Правое post_id nullable; флаг PPX делает optional также левый id.

```sql
SELECT u.id, p.id AS post_id FROM users u LEFT JOIN posts p ON p.user_id = u.id ORDER BY u.id, p.id
```

```rust
let rows = sqlx::query_as::<_, (i32, Option<i32>)>(
    "SELECT u.id, p.id AS post_id FROM users u LEFT JOIN posts p ON p.user_id = u.id ORDER BY u.id, p.id"
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx05 -->
```ocaml
let sx05 =
  [%pgsql.statement
    "nullable-results"
      "SELECT u.id, p.id AS post_id FROM users u LEFT JOIN posts p ON p.user_id = u.id ORDER BY u.id, p.id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:() Q.sx05 |> Stdlib.print_endline;;
SELECT u.id, p.id AS post_id FROM users u LEFT JOIN posts p ON p.user_id = u.id ORDER BY u.id, p.id
```

### SX-06. Nullable-параметр

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: None означает поиск SQL NULL через IS NOT DISTINCT FROM, а не пропуск WHERE.

```sql
SELECT id, name FROM users WHERE age IS NOT DISTINCT FROM $1 ORDER BY id
```

```rust
let rows = sqlx::query!(
    "SELECT id, name FROM users WHERE age IS NOT DISTINCT FROM $1 ORDER BY id", age
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx06 -->
```ocaml
let sx06 =
  [%pgsql.statement
    fun age ->
      "SELECT id, name FROM users WHERE age IS NOT DISTINCT FROM $?age ORDER BY id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:None Q.sx06 |> Stdlib.print_endline;;
SELECT id, name FROM users WHERE age IS NOT DISTINCT FROM $1 ORDER BY id
```

### SX-07. CASE по nullable-колонке

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: CASE по nullable-колонке с сохранением параметров и структуры SQL.

```sql
SELECT id, CASE WHEN age IS NULL THEN 'unknown' WHEN age >= $1 THEN 'adult' ELSE 'child' END AS category FROM users ORDER BY id
```

```rust
let rows = sqlx::query!(
    "SELECT id, CASE WHEN age IS NULL THEN 'unknown' WHEN age >= $1 THEN 'adult' ELSE 'child' END AS category FROM users ORDER BY id", adult
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx07 -->
```ocaml
let sx07 =
  [%pgsql.statement
    fun adult ->
      "SELECT id, CASE WHEN age IS NULL THEN 'unknown' WHEN age >= $adult THEN 'adult' ELSE 'child' END AS category FROM users ORDER BY id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:18 Q.sx07 |> Stdlib.print_endline;;
SELECT id, CASE WHEN age IS NULL THEN 'unknown' WHEN age >= $1 THEN 'adult' ELSE 'child' END AS category FROM users ORDER BY id
```

### SX-08. GROUP BY и COUNT

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: COUNT возвращает int8; metadata вычисляемого поля допускают NULL консервативно.

```sql
SELECT user_id, COUNT(*) AS total FROM posts GROUP BY user_id ORDER BY user_id
```

```rust
let rows = sqlx::query!(
    "SELECT user_id, COUNT(*) AS total FROM posts GROUP BY user_id ORDER BY user_id"
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx08 -->
```ocaml
let sx08 =
  [%pgsql.statement
    "SELECT user_id, COUNT(*) AS total FROM posts GROUP BY user_id ORDER BY user_id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:() Q.sx08 |> Stdlib.print_endline;;
SELECT user_id, COUNT(*) AS total FROM posts GROUP BY user_id ORDER BY user_id
```

### SX-09. HAVING

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: HAVING с сохранением параметров и структуры SQL.

```sql
SELECT user_id, COUNT(*) AS total FROM posts GROUP BY user_id HAVING COUNT(*) >= $1 ORDER BY user_id
```

```rust
let rows = sqlx::query!(
    "SELECT user_id, COUNT(*) AS total FROM posts GROUP BY user_id HAVING COUNT(*) >= $1 ORDER BY user_id", minimum
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx09 -->
```ocaml
let sx09 =
  [%pgsql.statement
    fun minimum ->
      "SELECT user_id, COUNT(*) AS total FROM posts GROUP BY user_id HAVING COUNT(*) >= $minimum ORDER BY user_id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:2L Q.sx09 |> Stdlib.print_endline;;
SELECT user_id, COUNT(*) AS total FROM posts GROUP BY user_id HAVING COUNT(*) >= $1 ORDER BY user_id
```

### SX-10. Коррелированный EXISTS

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query_scalar](https://docs.rs/sqlx/0.9.0/sqlx/macro.query_scalar.html).
- Проверяет: Коррелированный EXISTS с сохранением параметров и структуры SQL.

```sql
SELECT u.id FROM users u WHERE EXISTS (SELECT 1 FROM posts p WHERE p.user_id = u.id AND p.score > $1) ORDER BY u.id
```

```rust
let rows = sqlx::query_scalar!(
    "SELECT u.id FROM users u WHERE EXISTS (SELECT 1 FROM posts p WHERE p.user_id = u.id AND p.score > $1) ORDER BY u.id", score
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx10 -->
```ocaml
let sx10 =
  [%pgsql.statement
    fun score ->
      "SELECT u.id FROM users u WHERE EXISTS (SELECT 1 FROM posts p WHERE p.user_id = u.id AND p.score > $score) ORDER BY u.id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:5 Q.sx10 |> Stdlib.print_endline;;
SELECT u.id FROM users u WHERE EXISTS (SELECT 1 FROM posts p WHERE p.user_id = u.id AND p.score > $1) ORDER BY u.id
```

### SX-11. NOT EXISTS

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query_scalar](https://docs.rs/sqlx/0.9.0/sqlx/macro.query_scalar.html).
- Проверяет: NOT EXISTS с сохранением параметров и структуры SQL.

```sql
SELECT u.id FROM users u WHERE NOT EXISTS (SELECT 1 FROM posts p WHERE p.user_id = u.id) ORDER BY u.id
```

```rust
let rows = sqlx::query_scalar!(
    "SELECT u.id FROM users u WHERE NOT EXISTS (SELECT 1 FROM posts p WHERE p.user_id = u.id) ORDER BY u.id"
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx11 -->
```ocaml
let sx11 =
  [%pgsql.statement
    "SELECT u.id FROM users u WHERE NOT EXISTS (SELECT 1 FROM posts p WHERE p.user_id = u.id) ORDER BY u.id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:() Q.sx11 |> Stdlib.print_endline;;
SELECT u.id FROM users u WHERE NOT EXISTS (SELECT 1 FROM posts p WHERE p.user_id = u.id) ORDER BY u.id
```

### SX-12. Scalar subquery

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: Счётчик включает ноль для пользователя без публикаций; output int8 optional по metadata.

```sql
SELECT u.id, (SELECT COUNT(*) FROM posts p WHERE p.user_id = u.id) AS total FROM users u ORDER BY u.id
```

```rust
let rows = sqlx::query!(
    "SELECT u.id, (SELECT COUNT(*) FROM posts p WHERE p.user_id = u.id) AS total FROM users u ORDER BY u.id"
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx12 -->
```ocaml
let sx12 =
  [%pgsql.statement
    "SELECT u.id, (SELECT COUNT(*) FROM posts p WHERE p.user_id = u.id) AS total FROM users u ORDER BY u.id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:() Q.sx12 |> Stdlib.print_endline;;
SELECT u.id, (SELECT COUNT(*) FROM posts p WHERE p.user_id = u.id) AS total FROM users u ORDER BY u.id
```

### SX-13. Агрегатный подзапрос в FROM

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: Агрегатный подзапрос в FROM с сохранением параметров и структуры SQL.

```sql
SELECT u.id, s.total FROM users u JOIN (SELECT user_id, SUM(score) AS total FROM posts GROUP BY user_id) s ON s.user_id = u.id ORDER BY u.id
```

```rust
let rows = sqlx::query!(
    "SELECT u.id, s.total FROM users u JOIN (SELECT user_id, SUM(score) AS total FROM posts GROUP BY user_id) s ON s.user_id = u.id ORDER BY u.id"
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx13 -->
```ocaml
let sx13 =
  [%pgsql.statement
    "SELECT u.id, s.total FROM users u JOIN (SELECT user_id, SUM(score) AS total FROM posts GROUP BY user_id) s ON s.user_id = u.id ORDER BY u.id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:() Q.sx13 |> Stdlib.print_endline;;
SELECT u.id, s.total FROM users u JOIN (SELECT user_id, SUM(score) AS total FROM posts GROUP BY user_id) s ON s.user_id = u.id ORDER BY u.id
```

### SX-14. UNION ALL

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: UNION ALL с сохранением параметров и структуры SQL.

```sql
SELECT id FROM users WHERE id < $1 UNION ALL SELECT user_id AS id FROM posts WHERE user_id >= $2 ORDER BY id
```

```rust
let rows = sqlx::query!(
    "SELECT id FROM users WHERE id < $1 UNION ALL SELECT user_id AS id FROM posts WHERE user_id >= $2 ORDER BY id", boundary, boundary
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx14 -->
```ocaml
let sx14 =
  [%pgsql.statement
    fun boundary ->
      "SELECT id FROM users WHERE id < $boundary UNION ALL SELECT user_id AS id FROM posts WHERE user_id >= $boundary ORDER BY id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:3 Q.sx14 |> Stdlib.print_endline;;
SELECT id FROM users WHERE id < $1 UNION ALL SELECT user_id AS id FROM posts WHERE user_id >= $2 ORDER BY id
```

### SX-15. INTERSECT

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query_scalar](https://docs.rs/sqlx/0.9.0/sqlx/macro.query_scalar.html).
- Проверяет: INTERSECT с сохранением параметров и структуры SQL.

```sql
SELECT id FROM users INTERSECT SELECT user_id AS id FROM posts ORDER BY id
```

```rust
let rows = sqlx::query_scalar!(
    "SELECT id FROM users INTERSECT SELECT user_id AS id FROM posts ORDER BY id"
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx15 -->
```ocaml
let sx15 =
  [%pgsql.statement
    "SELECT id FROM users INTERSECT SELECT user_id AS id FROM posts ORDER BY id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:() Q.sx15 |> Stdlib.print_endline;;
SELECT id FROM users INTERSECT SELECT user_id AS id FROM posts ORDER BY id
```

### SX-16. EXCEPT

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query_scalar](https://docs.rs/sqlx/0.9.0/sqlx/macro.query_scalar.html).
- Проверяет: EXCEPT с сохранением параметров и структуры SQL.

```sql
SELECT id FROM users EXCEPT SELECT user_id AS id FROM posts ORDER BY id
```

```rust
let rows = sqlx::query_scalar!(
    "SELECT id FROM users EXCEPT SELECT user_id AS id FROM posts ORDER BY id"
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx16 -->
```ocaml
let sx16 =
  [%pgsql.statement
    "SELECT id FROM users EXCEPT SELECT user_id AS id FROM posts ORDER BY id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:() Q.sx16 |> Stdlib.print_endline;;
SELECT id FROM users EXCEPT SELECT user_id AS id FROM posts ORDER BY id
```

### SX-17. Читающий CTE

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: Читающий CTE с сохранением параметров и структуры SQL.

```sql
WITH popular AS (SELECT user_id FROM posts GROUP BY user_id HAVING COUNT(*) >= $1) SELECT u.id, u.name FROM users u JOIN popular p ON p.user_id = u.id ORDER BY u.id
```

```rust
let rows = sqlx::query!(
    "WITH popular AS (SELECT user_id FROM posts GROUP BY user_id HAVING COUNT(*) >= $1) SELECT u.id, u.name FROM users u JOIN popular p ON p.user_id = u.id ORDER BY u.id", minimum
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx17 -->
```ocaml
let sx17 =
  [%pgsql.statement
    fun minimum ->
      "WITH popular AS (SELECT user_id FROM posts GROUP BY user_id HAVING COUNT(*) >= $minimum) SELECT u.id, u.name FROM users u JOIN popular p ON p.user_id = u.id ORDER BY u.id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:2L Q.sx17 |> Stdlib.print_endline;;
WITH popular AS (SELECT user_id FROM posts GROUP BY user_id HAVING COUNT(*) >= $1) SELECT u.id, u.name FROM users u JOIN popular p ON p.user_id = u.id ORDER BY u.id
```

### SX-18. Рекурсивный CTE

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query_scalar](https://docs.rs/sqlx/0.9.0/sqlx/macro.query_scalar.html).
- Проверяет: Для схемы предполагается дерево без циклов; UNION ALL сам по себе циклы не останавливает.

```sql
WITH RECURSIVE tree AS (SELECT id, parent_id FROM users WHERE id = $1 UNION ALL SELECT u.id, u.parent_id FROM users u JOIN tree t ON u.parent_id = t.id) SELECT id FROM tree ORDER BY id
```

```rust
let rows = sqlx::query_scalar!(
    "WITH RECURSIVE tree AS (SELECT id, parent_id FROM users WHERE id = $1 UNION ALL SELECT u.id, u.parent_id FROM users u JOIN tree t ON u.parent_id = t.id) SELECT id FROM tree ORDER BY id", root
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx18 -->
```ocaml
let sx18 =
  [%pgsql.statement
    fun root ->
      "WITH RECURSIVE tree AS (SELECT id, parent_id FROM users WHERE id = $root UNION ALL SELECT u.id, u.parent_id FROM users u JOIN tree t ON u.parent_id = t.id) SELECT id FROM tree ORDER BY id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:1 Q.sx18 |> Stdlib.print_endline;;
WITH RECURSIVE tree AS (SELECT id, parent_id FROM users WHERE id = $1 UNION ALL SELECT u.id, u.parent_id FROM users u JOIN tree t ON u.parent_id = t.id) SELECT id FROM tree ORDER BY id
```

### SX-19. ROW_NUMBER внутри автора

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: ROW_NUMBER имеет тип int8; id разрешает равенство score внутри группы.

```sql
SELECT id, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY score DESC, id) AS rank FROM posts ORDER BY user_id, rank
```

```rust
let rows = sqlx::query!(
    "SELECT id, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY score DESC, id) AS rank FROM posts ORDER BY user_id, rank"
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx19 -->
```ocaml
let sx19 =
  [%pgsql.statement
    "SELECT id, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY score DESC, id) AS rank FROM posts ORDER BY user_id, rank"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:() Q.sx19 |> Stdlib.print_endline;;
SELECT id, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY score DESC, id) AS rank FROM posts ORDER BY user_id, rank
```

### SX-20. Оконная сумма с frame

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: SUM(integer) имеет тип int8; frame включает текущую строку.

```sql
SELECT id, SUM(score) OVER (PARTITION BY user_id ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total FROM posts ORDER BY user_id, id
```

```rust
let rows = sqlx::query!(
    "SELECT id, SUM(score) OVER (PARTITION BY user_id ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total FROM posts ORDER BY user_id, id"
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx20 -->
```ocaml
let sx20 =
  [%pgsql.statement
    "SELECT id, SUM(score) OVER (PARTITION BY user_id ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total FROM posts ORDER BY user_id, id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:() Q.sx20 |> Stdlib.print_endline;;
SELECT id, SUM(score) OVER (PARTITION BY user_id ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total FROM posts ORDER BY user_id, id
```

### SX-21. DISTINCT ON

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: DISTINCT ON с сохранением параметров и структуры SQL.

```sql
SELECT DISTINCT ON (user_id) user_id, id, title FROM posts ORDER BY user_id, score DESC, id
```

```rust
let rows = sqlx::query!(
    "SELECT DISTINCT ON (user_id) user_id, id, title FROM posts ORDER BY user_id, score DESC, id"
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx21 -->
```ocaml
let sx21 =
  [%pgsql.statement
    "SELECT DISTINCT ON (user_id) user_id, id, title FROM posts ORDER BY user_id, score DESC, id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:() Q.sx21 |> Stdlib.print_endline;;
SELECT DISTINCT ON (user_id) user_id, id, title FROM posts ORDER BY user_id, score DESC, id
```

### SX-22. LEFT JOIN LATERAL

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [runtime_lateral](https://docs.rs/sqlx/0.9.0/sqlx/fn.query_as.html).
- Проверяет: Нет публикации — NULL title; PPX консервативно делает optional оба поля.

```sql
SELECT u.id, p.title FROM users u LEFT JOIN LATERAL (SELECT title FROM posts WHERE user_id = u.id ORDER BY score DESC, id LIMIT 1) p ON TRUE ORDER BY u.id
```

```rust
let rows = sqlx::query_as::<_, (i32, Option<String>)>(
    "SELECT u.id, p.title FROM users u LEFT JOIN LATERAL (SELECT title FROM posts WHERE user_id = u.id ORDER BY score DESC, id LIMIT 1) p ON TRUE ORDER BY u.id"
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx22 -->
```ocaml
let sx22 =
  [%pgsql.statement
    "nullable-results"
      "SELECT u.id, p.title FROM users u LEFT JOIN LATERAL (SELECT title FROM posts WHERE user_id = u.id ORDER BY score DESC, id LIMIT 1) p ON TRUE ORDER BY u.id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:() Q.sx22 |> Stdlib.print_endline;;
SELECT u.id, p.title FROM users u LEFT JOIN LATERAL (SELECT title FROM posts WHERE user_id = u.id ORDER BY score DESC, id LIMIT 1) p ON TRUE ORDER BY u.id
```

### SX-23. Массив и ANY

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: Длина массива не меняет форму SQL; пустой массив даёт пустой результат.

```sql
SELECT id, name FROM users WHERE id = ANY($1::int4[]) ORDER BY id
```

```rust
let rows = sqlx::query!(
    "SELECT id, name FROM users WHERE id = ANY($1::int4[]) ORDER BY id", &ids[..]
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx23 -->
```ocaml
let sx23 =
  [%pgsql.statement
    fun ids -> "SELECT id, name FROM users WHERE id = ANY($ids::int4[]) ORDER BY id"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Statement.sql_exn ~dialect:Postgresql ~input:(int_array [ 1; 3 ]) Q.sx23
  |> Stdlib.print_endline;;
SELECT id, name FROM users WHERE id = ANY(CAST($1 AS integer[])::int4[]) ORDER BY id
```

### SX-24. INSERT из UNNEST

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: Два массива одинаковой длины; RETURNING не гарантирует порядок строк.

```sql
INSERT INTO users (id, name) SELECT * FROM UNNEST($1::int4[], $2::text[]) RETURNING id, name
```

```rust
let rows = sqlx::query!(
    "INSERT INTO users (id, name) SELECT * FROM UNNEST($1::int4[], $2::text[]) RETURNING id, name", &ids[..], &names[..]
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx24 -->
```ocaml
let sx24 =
  [%pgsql.statement
    fun (ids, names) ->
      "INSERT INTO users (id, name) SELECT * FROM UNNEST($ids::int4[], $names::text[]) RETURNING id, name"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Statement.sql_exn
    ~dialect:Postgresql
    ~input:(int_array [ 4; 5 ], text_array [ "Dan"; "Eve" ])
    Q.sx24
  |> Stdlib.print_endline;;
INSERT INTO users (id, name) SELECT * FROM UNNEST(CAST($1 AS integer[])::int4[], CAST($2 AS text[])::text[]) RETURNING id, name
```

### SX-25. INSERT RETURNING

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: INSERT RETURNING с сохранением параметров и структуры SQL.

```sql
INSERT INTO users (id, name) VALUES ($1, $2) RETURNING id, name
```

```rust
let rows = sqlx::query!(
    "INSERT INTO users (id, name) VALUES ($1, $2) RETURNING id, name", id, name
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx25 -->
```ocaml
let sx25 =
  [%pgsql.statement
    fun (id, name) ->
      "INSERT INTO users (id, name) VALUES ($id, $name) RETURNING id, name"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Statement.sql_exn ~dialect:Postgresql ~input:(4, "Dan") Q.sx25 |> Stdlib.print_endline;;
INSERT INTO users (id, name) VALUES ($1, $2) RETURNING id, name
```

### SX-26. UPSERT

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: UPSERT с сохранением параметров и структуры SQL.

```sql
INSERT INTO users (id, name) VALUES ($1, $2) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name RETURNING id, name
```

```rust
let rows = sqlx::query!(
    "INSERT INTO users (id, name) VALUES ($1, $2) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name RETURNING id, name", id, name
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx26 -->
```ocaml
let sx26 =
  [%pgsql.statement
    fun (id, name) ->
      "INSERT INTO users (id, name) VALUES ($id, $name) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name RETURNING id, name"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Statement.sql_exn ~dialect:Postgresql ~input:(1, "Ada") Q.sx26 |> Stdlib.print_endline;;
INSERT INTO users (id, name) VALUES ($1, $2) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name RETURNING id, name
```

### SX-27. UPDATE RETURNING

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: UPDATE RETURNING с сохранением параметров и структуры SQL.

```sql
UPDATE posts SET score = score + $1 WHERE user_id = $2 RETURNING id, score
```

```rust
let rows = sqlx::query!(
    "UPDATE posts SET score = score + $1 WHERE user_id = $2 RETURNING id, score", increment, user_id
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx27 -->
```ocaml
let sx27 =
  [%pgsql.statement
    fun (increment, user_id) ->
      "UPDATE posts SET score = score + $increment WHERE user_id = $user_id RETURNING id, score"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Statement.sql_exn ~dialect:Postgresql ~input:(2, 1) Q.sx27 |> Stdlib.print_endline;;
UPDATE posts SET score = score + $1 WHERE user_id = $2 RETURNING id, score
```

### SX-28. DELETE без RETURNING

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: Без RETURNING результат typed-sql — Affected_rows.t, SQLx — PgQueryResult.

```sql
DELETE FROM posts WHERE score < $1
```

```rust
let result = sqlx::query!(
    "DELETE FROM posts WHERE score < $1", minimum
).execute(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx28 -->
```ocaml
let sx28 = [%pgsql.statement fun minimum -> "DELETE FROM posts WHERE score < $minimum"]
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:0 Q.sx28 |> Stdlib.print_endline;;
DELETE FROM posts WHERE score < $1
```

### SX-29. UPDATE FROM

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query](https://docs.rs/sqlx/0.9.0/sqlx/macro.query.html).
- Проверяет: UPDATE FROM с сохранением параметров и структуры SQL.

```sql
UPDATE posts p SET score = $1 FROM users u WHERE p.user_id = u.id AND u.name = $2 RETURNING p.id, p.score
```

```rust
let rows = sqlx::query!(
    "UPDATE posts p SET score = $1 FROM users u WHERE p.user_id = u.id AND u.name = $2 RETURNING p.id, p.score", score, name
).fetch_all(&pool).await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx29 -->
```ocaml
let sx29 =
  [%pgsql.statement
    fun (score, name) ->
      "UPDATE posts p SET score = $score FROM users u WHERE p.user_id = u.id AND u.name = $name RETURNING p.id, p.score"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Statement.sql_exn ~dialect:Postgresql ~input:(10, "Ada") Q.sx29 |> Stdlib.print_endline;;
UPDATE posts p SET score = $1 FROM users u WHERE p.user_id = u.id AND u.name = $2 RETURNING p.id, p.score
```

### SX-30. FOR UPDATE SKIP LOCKED

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: статический SQL → cached PPX.
- Источник API: [query_scalar](https://docs.rs/sqlx/0.9.0/sqlx/macro.query_scalar.html).
- Проверяет: Выполнение требует транзакции; cached metadata помечают запрос top-level-only.

```sql
SELECT id FROM posts WHERE score < $1 ORDER BY id LIMIT $2 FOR UPDATE SKIP LOCKED
```

```rust
let mut tx = pool.begin().await?;
let rows = sqlx::query_scalar!(
    "SELECT id FROM posts WHERE score < $1 ORDER BY id LIMIT $2 FOR UPDATE SKIP LOCKED", maximum, limit
).fetch_all(&mut *tx).await?;
// Process the selected rows while their locks are still held.
tx.commit().await?;
```

#### OCaml (cached PPX)

<!-- $MDX file=queries.ml,part=sx30 -->
```ocaml
let sx30 =
  [%pgsql.statement
    fun (maximum, limit) ->
      "SELECT id FROM posts WHERE score < $maximum ORDER BY id LIMIT $limit FOR UPDATE SKIP LOCKED"]
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Statement.sql_exn ~dialect:Postgresql ~input:(10, 2L) Q.sx30 |> Stdlib.print_endline;;
SELECT id FROM posts WHERE score < $1 ORDER BY id LIMIT $2 FOR UPDATE SKIP LOCKED
```

### SX-31. Необязательный WHERE

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: SQLx QueryBuilder → ручной raw SQL.
- Источник API: [QueryBuilder](https://docs.rs/sqlx/0.9.0/sqlx/struct.QueryBuilder.html).
- Проверяет: Изменение runtime input изменяет форму SQL; проекция сохраняет тип.

```sql
SELECT id, name FROM users WHERE name = $1 ORDER BY id
```

```rust
let mut q = QueryBuilder::<Postgres>::new("SELECT id, name FROM users");
if let Some(name) = name { q.push(" WHERE name = ").push_bind(name); }
q.push(" ORDER BY id");
let rows = q.build_query_as::<(i32, String)>().fetch_all(&pool).await?;
```

#### OCaml (raw SQL)

<!-- $MDX file=dynamic.ml,part=sx31 -->
```ocaml
let sx31 =
  Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun name ->
    select
      ([ text "SELECT id, name FROM users" ]
       @ (match name with
          | None -> []
          | Some name -> [ text " WHERE name = "; string name ])
       @ [ text " ORDER BY id" ]))
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Statement.sql_exn ~dialect:Postgresql ~input:(Some "Ada") D.sx31 |> Stdlib.print_endline;;
SELECT id, name FROM users WHERE name = $1 ORDER BY id
```

### SX-32. Переменный набор сгруппированных условий

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: SQLx QueryBuilder → ручной raw SQL.
- Источник API: [QueryBuilder](https://docs.rs/sqlx/0.9.0/sqlx/struct.QueryBuilder.html).
- Проверяет: Изменение runtime input изменяет форму SQL; проекция сохраняет тип.

```sql
SELECT id, name FROM users WHERE (id > $1 OR name LIKE $2) ORDER BY id
```

```rust
let mut q = QueryBuilder::<Postgres>::new("SELECT id, name FROM users");
if !conditions.is_empty() {
    q.push(" WHERE (");
    let mut terms = q.separated(" OR ");
    for condition in conditions {
        match condition {
            Condition::MinId(id) => { terms.push("id > ").push_bind_unseparated(id); }
            Condition::NameLike(name) => { terms.push("name LIKE ").push_bind_unseparated(name); }
        }
    }
    q.push(")");
}
q.push(" ORDER BY id");
let rows = q.build_query_as::<(i32, String)>().fetch_all(&pool).await?;
```

#### OCaml (raw SQL)

<!-- $MDX file=dynamic.ml,part=sx32 -->
```ocaml
let sx32 =
  Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun conditions ->
    let predicates =
      List.map conditions ~f:(function
        | Min_id value -> [ text "id > "; int value ]
        | Name_like value -> [ text "name LIKE "; string value ])
    in
    select
      ([ text "SELECT id, name FROM users" ]
       @ (match predicates with
          | [] -> []
          | _ -> [ text " WHERE (" ] @ separated ~sep:" OR " predicates @ [ text ")" ])
       @ [ text " ORDER BY id" ]))
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Statement.sql_exn ~dialect:Postgresql ~input:[ D.Min_id 1; D.Name_like "A%" ] D.sx32
  |> Stdlib.print_endline;;
SELECT id, name FROM users WHERE (id > $1 OR name LIKE $2) ORDER BY id
```

### SX-33. IN переменной длины

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: SQLx QueryBuilder → ручной raw SQL.
- Источник API: [QueryBuilder](https://docs.rs/sqlx/0.9.0/sqlx/struct.QueryBuilder.html).
- Проверяет: Пустой список означает FALSE, а не IN ().

```sql
SELECT id, name FROM users WHERE id IN ($1, $2) ORDER BY id
```

```rust
let mut q = QueryBuilder::<Postgres>::new("SELECT id, name FROM users WHERE ");
if ids.is_empty() { q.push("FALSE"); } else {
    q.push("id IN (");
    let mut values = q.separated(", ");
    for id in ids { values.push_bind(id); }
    q.push(")");
}
q.push(" ORDER BY id");
let rows = q.build_query_as::<(i32, String)>().fetch_all(&pool).await?;
```

#### OCaml (raw SQL)

<!-- $MDX file=dynamic.ml,part=sx33 -->
```ocaml
let sx33 =
  Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun ids ->
    let predicate =
      match ids with
      | [] -> [ text "FALSE" ]
      | _ ->
        [ text "id IN (" ]
        @ separated ~sep:", " (List.map ids ~f:(fun id -> [ int id ]))
        @ [ text ")" ]
    in
    select
      ([ text "SELECT id, name FROM users WHERE " ] @ predicate @ [ text " ORDER BY id" ]))
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Statement.sql_exn ~dialect:Postgresql ~input:[ 1; 3 ] D.sx33 |> Stdlib.print_endline;;
SELECT id, name FROM users WHERE id IN ($1, $2) ORDER BY id
```

### SX-34. Tuple IN

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: SQLx QueryBuilder → ручной raw SQL.
- Источник API: [QueryBuilder](https://docs.rs/sqlx/0.9.0/sqlx/struct.QueryBuilder.html).
- Проверяет: Пустой набор ключей означает FALSE.

```sql
SELECT id, name FROM users WHERE (id, name) IN (($1, $2), ($3, $4)) ORDER BY id
```

```rust
let mut q = QueryBuilder::<Postgres>::new("SELECT id, name FROM users WHERE ");
if keys.is_empty() { q.push("FALSE"); } else {
    q.push("(id, name) IN ");
    q.push_tuples(keys, |mut tuple, (id, name)| {
        tuple.push_bind(id).push_bind(name);
    });
}
q.push(" ORDER BY id");
let rows = q.build_query_as::<(i32, String)>().fetch_all(&pool).await?;
```

#### OCaml (raw SQL)

<!-- $MDX file=dynamic.ml,part=sx34 -->
```ocaml
let sx34 =
  Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun keys ->
    let predicate =
      match keys with
      | [] -> [ text "FALSE" ]
      | _ ->
        [ text "(id, name) IN (" ]
        @ separated
            ~sep:", "
            (List.map keys ~f:(fun (id, name) ->
               [ text "("; int id; text ", "; string name; text ")" ]))
        @ [ text ")" ]
    in
    select
      ([ text "SELECT id, name FROM users WHERE " ] @ predicate @ [ text " ORDER BY id" ]))
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Statement.sql_exn ~dialect:Postgresql ~input:[ 1, "Ada"; 3, "Cal" ] D.sx34
  |> Stdlib.print_endline;;
SELECT id, name FROM users WHERE (id, name) IN (($1, $2), ($3, $4)) ORDER BY id
```

### SX-35. Выбор сортировки

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: SQLx QueryBuilder → ручной raw SQL.
- Источник API: [QueryBuilder](https://docs.rs/sqlx/0.9.0/sqlx/struct.QueryBuilder.html).
- Проверяет: Сортировка выбирается закрытым enum; пользовательская строка в SQL не вставляется.

```sql
SELECT id, name FROM users ORDER BY name DESC, id
```

```rust
let mut q = QueryBuilder::<Postgres>::new("SELECT id, name FROM users ORDER BY ");
q.push(match sort { Sort::NameAsc => "name ASC, id", Sort::NameDesc => "name DESC, id" });
let rows = q.build_query_as::<(i32, String)>().fetch_all(&pool).await?;
```

#### OCaml (raw SQL)

<!-- $MDX file=dynamic.ml,part=sx35 -->
```ocaml
let sx35 =
  Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun sort ->
    select
      [ text "SELECT id, name FROM users ORDER BY "
      ; text
          (match sort with
           | Name_asc -> "name ASC, id"
           | Name_desc -> "name DESC, id")
      ])
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Statement.sql_exn ~dialect:Postgresql ~input:D.Name_desc D.sx35 |> Stdlib.print_endline;;
SELECT id, name FROM users ORDER BY name DESC, id
```

### SX-36. Условный JOIN с фиксированной проекцией

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: SQLx QueryBuilder → ручной raw SQL.
- Источник API: [QueryBuilder](https://docs.rs/sqlx/0.9.0/sqlx/struct.QueryBuilder.html).
- Проверяет: Изменение runtime input изменяет форму SQL; проекция сохраняет тип.

```sql
SELECT DISTINCT u.id, u.name FROM users u JOIN posts p ON p.user_id = u.id ORDER BY u.id
```

```rust
let mut q = QueryBuilder::<Postgres>::new("SELECT DISTINCT u.id, u.name FROM users u");
if with_posts { q.push(" JOIN posts p ON p.user_id = u.id"); }
q.push(" ORDER BY u.id");
let rows = q.build_query_as::<(i32, String)>().fetch_all(&pool).await?;
```

#### OCaml (raw SQL)

<!-- $MDX file=dynamic.ml,part=sx36 -->
```ocaml
let sx36 =
  Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun with_posts ->
    select
      ([ text "SELECT DISTINCT u.id, u.name FROM users u" ]
       @ (if with_posts then
            [ text " JOIN posts p ON p.user_id = u.id" ]
          else
            [])
       @ [ text " ORDER BY u.id" ]))
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Statement.sql_exn ~dialect:Postgresql ~input:true D.sx36 |> Stdlib.print_endline;;
SELECT DISTINCT u.id, u.name FROM users u JOIN posts p ON p.user_id = u.id ORDER BY u.id
```

### SX-37. Переменное число ветвей UNION ALL

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: SQLx QueryBuilder → ручной raw SQL.
- Источник API: [QueryBuilder](https://docs.rs/sqlx/0.9.0/sqlx/struct.QueryBuilder.html).
- Проверяет: Пустой набор ветвей даёт SELECT с FALSE; UNION ALL сохраняет повторы.

```sql
SELECT id FROM users WHERE name = $1 UNION ALL SELECT id FROM users WHERE name = $2 ORDER BY id
```

```rust
let mut q = QueryBuilder::<Postgres>::new("");
if names.is_empty() { q.push("SELECT id FROM users WHERE FALSE"); } else {
    let mut branches = q.separated(" UNION ALL ");
    for name in names {
        branches.push("SELECT id FROM users WHERE name = ").push_bind_unseparated(name);
    }
}
q.push(" ORDER BY id");
let rows = q.build_query_scalar::<i32>().fetch_all(&pool).await?;
```

#### OCaml (raw SQL)

<!-- $MDX file=dynamic.ml,part=sx37 -->
```ocaml
let sx37 =
  Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun names ->
    let branches =
      List.map names ~f:(fun name ->
        [ text "SELECT id FROM users WHERE name = "; string name ])
    in
    select_ids
      (match branches with
       | [] -> [ text "SELECT id FROM users WHERE FALSE ORDER BY id" ]
       | _ -> separated ~sep:" UNION ALL " branches @ [ text " ORDER BY id" ]))
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Statement.sql_exn ~dialect:Postgresql ~input:[ "Ada"; "Cal" ] D.sx37
  |> Stdlib.print_endline;;
SELECT id FROM users WHERE name = $1 UNION ALL SELECT id FROM users WHERE name = $2 ORDER BY id
```

### SX-38. Пакетный INSERT VALUES

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: SQLx QueryBuilder → ручной raw SQL.
- Источник API: [QueryBuilder](https://docs.rs/sqlx/0.9.0/sqlx/struct.QueryBuilder.html).
- Проверяет: Пустой batch отклоняется до построения Statement; большой batch ограничивается лимитом bind-параметров СУБД.

```sql
INSERT INTO users (id, name) VALUES ($1, $2), ($3, $4)
```

```rust
if rows.is_empty() { return Err("rows must not be empty".into()); }
let mut q = QueryBuilder::<Postgres>::new("INSERT INTO users (id, name) ");
q.push_values(rows, |mut tuple, (id, name)| { tuple.push_bind(id).push_bind(name); });
let result = q.build().execute(&pool).await?;
```

#### OCaml (raw SQL)

<!-- $MDX file=dynamic.ml,part=sx38 -->
```ocaml
let sx38 rows =
  match rows with
  | [] -> rows_required
  | _ ->
    Ok
      (Statement.Dynamic.command ~dialect:Dialect.postgresql (fun () ->
         Raw.command
           ([ text "INSERT INTO users (id, name) VALUES " ]
            @ separated
                ~sep:", "
                (List.map rows ~f:(fun (id, name) ->
                   [ text "("; int id; text ", "; string name; text ")" ])))))
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Statement.sql_exn
    ~dialect:Postgresql
    ~input:()
    (Result.ok_or_failwith (D.sx38 [ 4, "Dan"; 5, "Eve" ]))
  |> Stdlib.print_endline;;
INSERT INTO users (id, name) VALUES ($1, $2), ($3, $4)
```

### SX-39. UPDATE с переменным набором SET

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: SQLx QueryBuilder → ручной raw SQL.
- Источник API: [QueryBuilder](https://docs.rs/sqlx/0.9.0/sqlx/struct.QueryBuilder.html).
- Проверяет: None пропускает поле; Some None устанавливает age в NULL. Пустой SET отклоняется.

```sql
UPDATE users SET name = $1, age = $2 WHERE id = $3 RETURNING id, name
```

```rust
// name: Option<String>, age: Option<Option<i32>>; None omits the field.
if name.is_none() && age.is_none() { return Err("at least one SET field is required".into()); }
let mut q = QueryBuilder::<Postgres>::new("UPDATE users SET ");
{
    let mut fields = q.separated(", ");
    if let Some(name) = name { fields.push("name = ").push_bind_unseparated(name); }
    if let Some(age) = age { fields.push("age = ").push_bind_unseparated(age); }
}
q.push(" WHERE id = ").push_bind(id).push(" RETURNING id, name");
let rows = q.build_query_as::<(i32, String)>().fetch_all(&pool).await?;
```

#### OCaml (raw SQL)

<!-- $MDX file=dynamic.ml,part=sx39 -->
```ocaml
let sx39 ~id ~name ~age =
  let fields =
    Option.to_list (Option.map name ~f:(fun value -> Name value))
    @ Option.to_list (Option.map age ~f:(fun value -> Age value))
  in
  match fields with
  | [] -> Error "at least one SET field is required"
  | _ ->
    Ok
      (Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun () ->
         let assignments =
           List.map fields ~f:(function
             | Name value -> [ text "name = "; string value ]
             | Age value ->
               [ text "age = "
               ; Raw.bind
                   (Db_type.option Db_type.int)
                   (Expr.constant (Db_type.option Db_type.int) value)
               ])
         in
         Raw.returning
           ~output:user_output
           ([ text "UPDATE users SET " ]
            @ separated ~sep:", " assignments
            @ [ text " WHERE id = "; int id; text " RETURNING id, name" ])))
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Statement.sql_exn
    ~dialect:Postgresql
    ~input:()
    (Result.ok_or_failwith (D.sx39 ~id:1 ~name:(Some "Ada") ~age:(Some None)))
  |> Stdlib.print_endline;;
UPDATE users SET name = $1, age = $2 WHERE id = $3 RETURNING id, name
```

### SX-40. Пакетный UPDATE FROM VALUES

- OCaml-пример: ✓; реализуемость: ✓; семантика: ✓; без доработок: ✓.
- Подход: SQLx QueryBuilder → ручной raw SQL.
- Источник API: [QueryBuilder](https://docs.rs/sqlx/0.9.0/sqlx/struct.QueryBuilder.html).
- Проверяет: Пустой batch отклоняется; id внутри batch должны быть уникальными, иначе UPDATE FROM неоднозначен.

```sql
UPDATE users u SET name = v.name FROM (VALUES ($1::int4, $2::text), ($3::int4, $4::text)) AS v(id, name) WHERE u.id = v.id RETURNING u.id, u.name
```

```rust
if rows.is_empty() { return Err("rows must not be empty".into()); }
let mut q = QueryBuilder::<Postgres>::new("UPDATE users u SET name = v.name FROM (");
q.push_values(rows, |mut tuple, (id, name)| {
    tuple.push_bind(id).push_unseparated("::int4");
    tuple.push_bind(name).push_unseparated("::text");
});
q.push(") AS v(id, name) WHERE u.id = v.id RETURNING u.id, u.name");
let rows = q.build_query_as::<(i32, String)>().fetch_all(&pool).await?;
```

#### OCaml (raw SQL)

<!-- $MDX file=dynamic.ml,part=sx40 -->
```ocaml
let sx40 rows =
  match rows with
  | [] -> rows_required
  | _ ->
    Ok
      (Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun () ->
         Raw.returning
           ~output:user_output
           ([ text "UPDATE users u SET name = v.name FROM (VALUES " ]
            @ separated
                ~sep:", "
                (List.map rows ~f:(fun (id, name) ->
                   [ text "("; int id; text "::int4, "; string name; text "::text)" ]))
            @ [ text ") AS v(id, name) WHERE u.id = v.id RETURNING u.id, u.name" ])))
;;
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Statement.sql_exn
    ~dialect:Postgresql
    ~input:()
    (Result.ok_or_failwith (D.sx40 [ 1, "Ada"; 2, "Bob" ]))
  |> Stdlib.print_endline;;
UPDATE users u SET name = v.name FROM (VALUES ($1::int4, $2::text), ($3::int4, $4::text)) AS v(id, name) WHERE u.id = v.id RETURNING u.id, u.name
```
