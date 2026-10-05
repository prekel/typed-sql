<!-- SPDX-License-Identifier: MIT -->

# Сценарии запросов из SQLAlchemy

## Уведомление о лицензии источника

Copyright 2005-2026 SQLAlchemy authors and contributors <see AUTHORS file>.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


50 сценариев по [SQLAlchemy 2.0 Unified Tutorial](https://docs.sqlalchemy.org/en/20/tutorial/) и документации SQLAlchemy Core (доступ 28.09.2026). Использован SQLAlchemy Core. Примеры сокращены и адаптированы; SQL показывает ожидаемую структуру запроса, а не точный вывод компилятора. Имена bind-параметров могут отличаться у разных диалектов.

**Желаемый таргет: 50–70 сценариев.**

Источник примеров: SQLAlchemy authors and contributors, © 2005–2026, [лицензия MIT](https://github.com/sqlalchemy/sqlalchemy/blob/main/LICENSE). Уведомление о лицензии приведено в начале файла. Схема tutorial: `user_account(id, name, fullname)` и `address(id, user_id, email_address)`. Для проверки пустых результатов нужна учётная запись без адресов.

Для сценариев с OCaml-примером ✓ приведены typed-sql реализации и SQL компилятора. В блоках «SQL typed-sql» первая строка запускает компилятор, остальные строки — его вывод. Запустить проверку можно командой `opam exec -- dune runtest test/query-builder-survey`.

Статусы в карточках: `✓` — подтверждено; `✗` — условие не выполнено; `—` — не оценивалось. «Семантика» учитывает входные параметры, результат, `NULL` и заданный порядок относительно сценария в карточке. «Без доработок» относится к публичному API typed-sql, а не к необходимости улучшить пример. Реализуемость оценивается после попытки написать OCaml-код.

## Общие дескрипторы для SA-01–SA-50

Эти descriptors используются во всех typed-sql примерах этого файла.

```ocaml
open! Base
open Typed_sql
open Infix

module User_account = struct
  type row

  let table : row Table.t = Table.v_exn "user_account"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let fullname_column = Column.nullable_v_exn table "fullname" Db_type.text
  let id row = Expr.column row id_column
  let name row = Expr.column row name_column
  let fullname row = Expr.column row fullname_column
  let nullable_id row = Expr.nullable_column row id_column
end

module Address = struct
  type row

  let table : row Table.t = Table.v_exn "address"
  let id_column = Column.v_exn table "id" Db_type.int64
  let user_id_column = Column.v_exn table "user_id" Db_type.int64
  let email_column = Column.v_exn table "email_address" Db_type.text
  let user_id row = Expr.column row user_id_column
  let id row = Expr.column row id_column
  let email row = Expr.column row email_column
  let nullable_email row = Expr.nullable_column row email_column
  let nullable_id row = Expr.nullable_column row id_column
end

module Selected_ids = struct
  type row

  let table : row Table.t = Table.v_exn "selected_ids"
  let id_column = Column.v_exn table "id" Db_type.int64
  let id row = Expr.column row id_column
end
```

### SA-01. Фильтр и проекция

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: `name` передаётся через runtime input.
- Источник: [SELECT и WHERE](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#the-where-clause).
- Проверяет: выбор двух колонок с bind-параметром.

```sql
SELECT user_account.id, user_account.name
FROM user_account
WHERE user_account.name = :name
```

```python
stmt = select(user_table.c.id, user_table.c.name).where(
    user_table.c.name == name
)
```

#### OCaml (typed-sql)

Bind-значение сравнивается с выражением колонки; проекция декодируется в пару.

```ocaml
# let sqlalchemy01 =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let open Parameters.Let_syntax in
    let+ name = params.expr Db_type.text ~get:Fn.id in
    params.query_many
      Query.(
        from User_account.table
        |> where (fun user -> User_account.name user =. name)
        |> select (fun user ->
          let open Projection.Let_syntax in
          let+ projected_left = Projection.expr (User_account.id user)
          and+ projected_right = Projection.expr (User_account.name user) in
          projected_left, projected_right)))
val sqlalchemy01 : (string, (int64 * string) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ~input:"sandy" sqlalchemy01);;
SELECT
  t0."id",
  t0."name"
FROM "user_account" AS t0
WHERE
  (t0."name" = $1)
```

### SA-02. Составной предикат

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: `name1`, `name2` и `min_id` передаются через runtime input.
- Источник: [WHERE clause](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#the-where-clause).
- Проверяет: группировку `OR` внутри `AND`.

```sql
SELECT user_account.id
FROM user_account
WHERE (user_account.name = :name1 OR user_account.name = :name2)
  AND user_account.id > :min_id
```

```python
stmt = select(user_table.c.id).where(
    or_(user_table.c.name == name1, user_table.c.name == name2),
    user_table.c.id > min_id,
)
```

#### OCaml (typed-sql)

OR-группа явно вложена в AND-группу.

```ocaml
# let sqlalchemy02 =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let open Parameters.Let_syntax in
    let+ name1 = params.expr Db_type.text ~get:(fun (name1, _, _) -> name1)
    and+ name2 = params.expr Db_type.text ~get:(fun (_, name2, _) -> name2)
    and+ min_id = params.expr Db_type.int64 ~get:(fun (_, _, min_id) -> min_id) in
    params.query_many
      Query.(
        from User_account.table
        |> where (fun user ->
          User_account.name user
          =. name1
          ||. (User_account.name user =. name2)
          &&. (User_account.id user >. min_id))
        |> select (fun user -> Projection.expr (User_account.id user))))
val sqlalchemy02 :
  (string * string * int64, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Stdlib.print_endline
    (Statement.sql_exn ~dialect:Postgresql ~input:("sandy", "spongebob", 1L) sqlalchemy02);;
SELECT
  t0."id"
FROM "user_account" AS t0
WHERE
  (
    (
      (t0."name" = $1)
      OR (t0."name" = $2)
    )
    AND (t0."id" > $3)
  )
```

### SA-03. Сортировка и страница

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: `page_size` и `page_offset` передаются через валидируемые runtime input.
- Источник: [ORDER BY](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#order-by), [limit/offset](https://docs.sqlalchemy.org/en/20/core/selectable.html#sqlalchemy.sql.expression.GenerativeSelect.limit).
- Проверяет: устойчивый порядок, `LIMIT` и `OFFSET`.

```sql
SELECT user_account.id, user_account.name
FROM user_account
ORDER BY user_account.id
LIMIT :limit OFFSET :offset
```

```python
stmt = (
    select(user_table.c.id, user_table.c.name)
    .order_by(user_table.c.id)
    .limit(page_size)
    .offset(page_offset)
)
```

#### OCaml (typed-sql)

Порядок по уникальному id задаёт стабильную страницу.

```ocaml
# let sqlalchemy03 =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let open Parameters.Let_syntax in
    let+ page_size =
      params.non_negative_int ~name:"page_size" ~get:(fun (page_size, _) -> page_size)
    and+ page_offset =
      params.non_negative_int ~name:"page_offset" ~get:(fun (_, page_offset) ->
        page_offset)
    in
    params.query_many
      Query.(
        from User_account.table
        |> order_by User_account.id `Asc
        |> Query.limit_param page_size
        |> Query.offset_param page_offset
        |> select (fun user ->
          let open Projection.Let_syntax in
          let+ projected_left = Projection.expr (User_account.id user)
          and+ projected_right = Projection.expr (User_account.name user) in
          projected_left, projected_right)))
val sqlalchemy03 :
  (int * int, (int64 * string) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Stdlib.print_endline
    (Statement.sql_exn ~dialect:Postgresql ~input:(10, 20) sqlalchemy03);;
SELECT
  t0."id",
  t0."name"
FROM "user_account" AS t0
ORDER BY
  t0."id" ASC
LIMIT $1
OFFSET $2
```

### SA-04. INNER JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: Предикат JOIN задан явно вместо вывода по foreign key.
- Источник: [explicit JOIN](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#explicit-from-clauses-and-joins).
- Проверяет: связь таблиц по внешнему ключу.

```sql
SELECT user_account.name, address.email_address
FROM user_account
JOIN address ON user_account.id = address.user_id
```

```python
stmt = (
    select(user_table.c.name, address_table.c.email_address)
    .join_from(user_table, address_table)
)
```

#### OCaml (typed-sql)

Foreign key связь задаётся явно через callback JOIN.

```ocaml
# let sqlalchemy04 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from User_account.table
      |> inner_join Address.table ~on:(fun user address ->
        User_account.id user =. Address.user_id address)
      |> select (fun (user, address) ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (User_account.name user)
        and+ projected_right = Projection.expr (Address.email address) in
        projected_left, projected_right))
val sqlalchemy04 : (unit, (string * string) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy04);;
SELECT
  t0."name",
  t1."email_address"
FROM "user_account" AS t0
INNER JOIN "address" AS t1
  ON (t0."id" = t1."user_id")
```

### SA-05. LEFT OUTER JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [OUTER JOIN](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#outer-and-full-join).
- Проверяет: сохранение учётной записи без адреса и nullable-поле.

```sql
SELECT user_account.name, address.email_address
FROM user_account
LEFT OUTER JOIN address ON user_account.id = address.user_id
```

```python
stmt = (
    select(user_table.c.name, address_table.c.email_address)
    .join_from(user_table, address_table, isouter=True)
)
```

#### OCaml (typed-sql)

Nullable-колонка адреса в результате имеет тип string option.

```ocaml
# let sqlalchemy05 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from User_account.table
      |> left_join Address.table ~on:(fun user address ->
        User_account.id user =. Address.user_id address)
      |> select (fun (user, address) ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (User_account.name user)
        and+ projected_right = Projection.expr (Address.nullable_email address) in
        projected_left, projected_right))
val sqlalchemy05 :
  (unit, (string * string option) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy05);;
SELECT
  t0."name",
  t1."email_address"
FROM "user_account" AS t0
LEFT JOIN "address" AS t1
  ON (t0."id" = t1."user_id")
```

### SA-06. GROUP BY и HAVING

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [aggregate functions with GROUP BY/HAVING](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#aggregate-functions-with-group-by-having).
- Проверяет: фильтрацию агрегированных групп.

```sql
SELECT address.user_id, COUNT(address.id) AS address_count
FROM address
GROUP BY address.user_id
HAVING COUNT(address.id) > :min_count
```

```python
stmt = (
    select(
        address_table.c.user_id,
        func.count(address_table.c.id).label("address_count"),
    )
    .group_by(address_table.c.user_id)
    .having(func.count(address_table.c.id) > min_count)
)
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy06 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Address.table
      |> group_by Address.user_id
      |> having (fun _ -> Expr.count_all >=$ 2L)
      |> order_by Address.user_id `Asc
      |> select (fun address ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Address.user_id address)
        and+ projected_right = Projection.expr Expr.count_all in
        projected_left, projected_right))
val sqlalchemy06 : (unit, (int64 * int64) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy06);;
SELECT
  t0."user_id",
  COUNT(*)
FROM "address" AS t0
GROUP BY
  t0."user_id"
HAVING
  (COUNT(*) >= $1)
ORDER BY
  t0."user_id" ASC
```

### SA-07. Коррелированный scalar subquery

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [scalar and correlated subqueries](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#scalar-and-correlated-subqueries).
- Проверяет: число связанных строк, включая ноль.

```sql
SELECT user_account.id,
       (SELECT COUNT(address.id)
        FROM address
        WHERE address.user_id = user_account.id) AS address_count
FROM user_account
```

```python
address_count = (
    select(func.count(address_table.c.id))
    .where(address_table.c.user_id == user_table.c.id)
    .scalar_subquery()
)
stmt = select(user_table.c.id, address_count.label("address_count"))
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy07 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from User_account.table
      |> select (fun user ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (User_account.id user)
        and+ projected_right =
          Projection.expr
            (Expr.scalar_subquery
               Query.(
                 from Address.table
                 |> where (fun address -> Address.user_id address =. User_account.id user)
                 |> select_scalar (fun _ -> Expr.count_all)))
        in
        projected_left, projected_right))
val sqlalchemy07 :
  (unit, (int64 * int64 option) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy07);;
SELECT
  t0."id",
  (
    SELECT
      COUNT(*)
    FROM "address" AS t1
    WHERE
      (t1."user_id" = t0."id")
  )
FROM "user_account" AS t0
```

### SA-08. Коррелированный EXISTS

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [EXISTS subqueries](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#exists-subqueries).
- Проверяет: фильтрацию без дублирования внешних строк.

```sql
SELECT user_account.id
FROM user_account
WHERE EXISTS (
  SELECT address.id FROM address
  WHERE address.user_id = user_account.id
)
```

```python
has_address = (
    select(address_table.c.id)
    .where(address_table.c.user_id == user_table.c.id)
    .exists()
)
stmt = select(user_table.c.id).where(has_address)
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy08 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from User_account.table
      |> where (fun user ->
        exists
          Query.(
            from Address.table
            |> where (fun address -> Address.user_id address =. User_account.id user)))
      |> select (fun user ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (User_account.id user)
        and+ projected_right = Projection.expr (User_account.name user) in
        projected_left, projected_right))
val sqlalchemy08 : (unit, (int64 * string) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy08);;
SELECT
  t0."id",
  t0."name"
FROM "user_account" AS t0
WHERE
  (EXISTS (
    SELECT
      1
    FROM "address" AS t1
    WHERE
      (t1."user_id" = t0."id")
  ))
```

### SA-09. Derived table

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [subqueries and CTEs](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#subqueries-and-ctes).
- Проверяет: агрегированный подзапрос в `FROM`.

```sql
SELECT counts.user_id, counts.address_count
FROM (
  SELECT address.user_id, COUNT(address.id) AS address_count
  FROM address GROUP BY address.user_id
) AS counts
WHERE counts.address_count > :min_count
```

```python
counts = (
    select(
        address_table.c.user_id,
        func.count(address_table.c.id).label("address_count"),
    )
    .group_by(address_table.c.user_id)
    .subquery("counts")
)
stmt = select(counts.c.user_id, counts.c.address_count).where(
    counts.c.address_count > min_count
)
```

#### OCaml (typed-sql, inferred relation)

```ocaml
let sqlalchemy09_counts =
  Query.(
    from Address.table
    |> group_by Address.user_id
    |> select_relation (fun address ->
      Derived_table.Fields.pair (Address.user_id address) Expr.count_all))
;;
```

```ocaml
# let sqlalchemy09 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from_relation sqlalchemy09_counts
      |> order_by fst `Asc
      |> select (fun (user_id, count) ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr user_id
        and+ projected_right = Projection.expr count in
        projected_left, projected_right))
val sqlalchemy09 : (unit, (int64 * int64) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy09);;
SELECT
  t0."field_1",
  t0."field_2"
FROM (
  SELECT
    t1."user_id" AS "field_1",
    COUNT(*) AS "field_2"
  FROM "address" AS t1
  GROUP BY
    t1."user_id"
) AS t0
ORDER BY
  t0."field_1" ASC
```

### SA-10. CTE

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [common table expressions](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#common-table-expressions-ctes).
- Проверяет: именованный источник строк и обращение к его колонкам.

```sql
WITH counts AS (
  SELECT address.user_id, COUNT(address.id) AS address_count
  FROM address GROUP BY address.user_id
)
SELECT counts.user_id, counts.address_count
FROM counts
```

```python
counts = (
    select(
        address_table.c.user_id,
        func.count(address_table.c.id).label("address_count"),
    )
    .group_by(address_table.c.user_id)
    .cte("counts")
)
stmt = select(counts.c.user_id, counts.c.address_count)
```

#### OCaml (typed-sql, CTE)

```ocaml
let sqlalchemy10_relation =
  Derived_table.create
    ~table:User_account.table
    ~columns:(fun user ->
      let open Projection.Let_syntax in
      let+ projected_left = Projection.expr (User_account.id user)
      and+ projected_right = Projection.expr (User_account.name user) in
      projected_left, projected_right)
    Query.(
      from User_account.table
      |> where (fun user -> User_account.id user >$ 10L)
      |> select (fun user ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (User_account.id user)
        and+ projected_right = Projection.expr (User_account.name user) in
        projected_left, projected_right))
;;

let sqlalchemy10_cte = Cte.select sqlalchemy10_relation
```

```ocaml
# let sqlalchemy10 =
  Statement.query_many
    ~dialect:Dialect.portable
    (Cte.with_result sqlalchemy10_cte ~f:(fun selected ->
       Query.(
         from_cte selected
         |> order_by User_account.id `Asc
         |> select (fun user ->
           let open Projection.Let_syntax in
           let+ projected_left = Projection.expr (User_account.id user)
           and+ projected_right = Projection.expr (User_account.name user) in
           projected_left, projected_right))))
val sqlalchemy10 : (unit, (int64 * string) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy10);;
WITH
  "c0" (
    "id",
    "name"
  ) AS (
    SELECT
      t0."id",
      t0."name"
    FROM "user_account" AS t0
    WHERE
      (t0."id" > $1)
  )
SELECT
  t0."id",
  t0."name"
FROM "c0" AS t0
ORDER BY
  t0."id" ASC
```

### SA-11. UNION

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [UNION and other set operations](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#union-union-all-and-other-set-operations).
- Проверяет: одинаковую проекцию двух запросов и удаление дублей.

```sql
SELECT user_account.id FROM user_account WHERE user_account.name = :name1
UNION
SELECT user_account.id FROM user_account WHERE user_account.name = :name2
```

```python
stmt = union(
    select(user_table.c.id).where(user_table.c.name == name1),
    select(user_table.c.id).where(user_table.c.name == name2),
)
```

#### OCaml (typed-sql)

```ocaml
let sqlalchemy11_left =
  Query.(
    from User_account.table
    |> where (fun user -> User_account.name user =$ "sandy")
    |> select (fun user -> Projection.expr (User_account.id user)))
;;

let sqlalchemy11_right =
  Query.(
    from User_account.table
    |> where (fun user -> User_account.name user =$ "spongebob")
    |> select (fun user -> Projection.expr (User_account.id user)))
;;
```

```ocaml
# let sqlalchemy11 =
  Statement.query_many
    ~dialect:Dialect.portable
    (Query.union sqlalchemy11_left sqlalchemy11_right)
val sqlalchemy11 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy11);;
SELECT *
FROM (
  SELECT
    t0."id"
  FROM "user_account" AS t0
  WHERE
    (t0."name" = $1)
) AS s0
UNION
SELECT *
FROM (
  SELECT
    t0."id"
  FROM "user_account" AS t0
  WHERE
    (t0."name" = $2)
) AS s0
```

### SA-12. Оконная функция

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✓)
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [using window functions](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#using-window-functions).
- Проверяет: нумерацию адресов внутри каждого `user_id`; уникальный ID задаёт стабильный порядок, пользователь без адресов не возвращается.
- Замечание: `ROW_NUMBER()` заменён коррелированным `COUNT(id <= current_id)` плюс сортировка по ID.
- Ограничение: Публичное ядро не содержит оконных функций; нумерацию `ROW_NUMBER()` нельзя получить в том же SQL statement.

```sql
SELECT address.user_id, address.email_address,
       ROW_NUMBER() OVER (
         PARTITION BY address.user_id ORDER BY address.id
       ) AS address_number
FROM address
```

```python
stmt = select(
    address_table.c.user_id,
    address_table.c.email_address,
    func.row_number()
        .over(
            partition_by=address_table.c.user_id,
            order_by=address_table.c.id,
        )
        .label("address_number"),
)
```

### SA-13. INSERT RETURNING

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [INSERT and RETURNING](https://docs.sqlalchemy.org/en/20/tutorial/data_insert.html#insert-returning).
- Проверяет: возврат данных вставленной строки; синтаксис `RETURNING` зависит от диалекта.

```sql
INSERT INTO user_account (name, fullname)
VALUES (:name, :fullname)
RETURNING user_account.id
```

```python
stmt = (
    insert(user_table)
    .values(name=name, fullname=fullname)
    .returning(user_table.c.id)
)
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy13 =
  Statement.query_many
    ~dialect:Dialect.portable
    Insert.(
      into User_account.table
      |> set User_account.name_column "sandy"
      |> returning (fun user -> Projection.expr (User_account.id user)))
val sqlalchemy13 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy13);;
INSERT INTO "user_account" (
  "name"
)
VALUES
  ($1)
RETURNING
  "id"
```

### SA-14. Коррелированный UPDATE

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [correlated updates](https://docs.sqlalchemy.org/en/20/tutorial/data_update.html#correlated-updates).
- Проверяет: scalar subquery в `SET` и `NULL` при отсутствии адреса.

```sql
UPDATE user_account
SET fullname = (
  SELECT address.email_address FROM address
  WHERE address.user_id = user_account.id
  ORDER BY address.id LIMIT :limit
)
```

```python
first_email = (
    select(address_table.c.email_address)
    .where(address_table.c.user_id == user_table.c.id)
    .order_by(address_table.c.id)
    .limit(1)
    .scalar_subquery()
)
stmt = update(user_table).values(fullname=first_email)
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy14 =
  Statement.command
    ~dialect:Dialect.portable
    Update.(
      table User_account.table
      |> from User_account.table ~f:(fun target source update ->
        update
        |> set_expr
             User_account.fullname_column
             (Expr.scalar_subquery_nullable
                Query.(
                  from Address.table
                  |> where (fun address ->
                    Address.user_id address =. User_account.id target)
                  |> order_by Address.id `Asc
                  |> limit_one
                  |> select_scalar (fun address ->
                    Expr.to_nullable (Address.email address))))
        |> where (fun _ -> User_account.id target =. User_account.id source))
      |> all_rows
      |> command)
val sqlalchemy14 : (unit, Affected_rows.t, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy14);;
UPDATE "user_account" AS t0
SET
  "fullname" = (
    SELECT
      t2."email_address"
    FROM "address" AS t2
    WHERE
      (t2."user_id" = t0."id")
    ORDER BY
      t2."id" ASC
    LIMIT 1
  )
FROM "user_account" AS t1
```

### SA-15. DELETE RETURNING

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [DELETE](https://docs.sqlalchemy.org/en/20/tutorial/data_update.html#the-delete-sql-expression-construct), [RETURNING](https://docs.sqlalchemy.org/en/20/tutorial/data_update.html#using-returning-with-update-delete).
- Проверяет: условное удаление и возвращаемые значения; `RETURNING` зависит от диалекта.

```sql
DELETE FROM address
WHERE address.user_id = :user_id
RETURNING address.id
```

```python
stmt = (
    delete(address_table)
    .where(address_table.c.user_id == user_id)
    .returning(address_table.c.id)
)
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy15 =
  Statement.query_many
    ~dialect:Dialect.portable
    Delete.(
      from Address.table
      |> where (fun address -> Address.user_id address =$ 1L)
      |> returning (fun address -> Projection.expr (Address.id address)))
val sqlalchemy15 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy15);;
DELETE FROM "address"
WHERE
  ("user_id" = $1)
RETURNING
  "id"
```

### SA-16. DISTINCT

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [DISTINCT](https://docs.sqlalchemy.org/en/20/core/selectable.html#sqlalchemy.sql.expression.Select.distinct).
- Проверяет: удаление повторов в проекции.

```sql
SELECT DISTINCT address.user_id
FROM address
```

```python
stmt = select(address_table.c.user_id).distinct()
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy16 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Address.table
      |> distinct
      |> select (fun address -> Projection.expr (Address.user_id address)))
val sqlalchemy16 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy16);;
SELECT DISTINCT
  t0."user_id"
FROM "address" AS t0
```

### SA-17. Фильтр IN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [оператор IN](https://docs.sqlalchemy.org/en/20/core/operators.html#in-comparisons).
- Проверяет: сравнение колонки с набором значений.

```sql
SELECT user_account.id
FROM user_account
WHERE user_account.name IN (:name_1, :name_2)
```

```python
stmt = select(user_table.c.id).where(
    user_table.c.name.in_(["sandy", "spongebob"])
)
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy17 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from User_account.table
      |> where (fun user -> Expr.in_ (User_account.name user) [ "sandy"; "spongebob" ])
      |> select (fun user -> Projection.expr (User_account.id user)))
val sqlalchemy17 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy17);;
SELECT
  t0."id"
FROM "user_account" AS t0
WHERE
  (t0."name" IN (
    $1,
    $2
  ))
```

### SA-18. Сопоставление шаблону LIKE

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [строковые операторы](https://docs.sqlalchemy.org/en/20/core/operators.html#string-comparisons).
- Проверяет: шаблонное сравнение строкового значения с bind-параметром.

```sql
SELECT user_account.id
FROM user_account
WHERE user_account.name LIKE :name_pattern
```

```python
stmt = select(user_table.c.id).where(user_table.c.name.like(name_pattern))
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy18 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from User_account.table
      |> where (fun user -> User_account.name user =~$ "%sandy%")
      |> select (fun user -> Projection.expr (User_account.id user)))
val sqlalchemy18 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy18);;
SELECT
  t0."id"
FROM "user_account" AS t0
WHERE
  (t0."name" LIKE $1)
```

### SA-19. Проверка IS NULL

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [операторы сравнения с NULL](https://docs.sqlalchemy.org/en/20/core/operators.html#identity-comparisons).
- Проверяет: предикат `IS NULL`, а не сравнение через `= NULL`.

```sql
SELECT address.id
FROM address
WHERE address.email_address IS NULL
```

```python
stmt = select(address_table.c.id).where(address_table.c.email_address.is_(None))
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy19 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Address.table
      |> where (fun address -> Expr.is_null (Expr.to_nullable (Address.email address)))
      |> select (fun address -> Projection.expr (Address.id address)))
val sqlalchemy19 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy19);;
SELECT
  t0."id"
FROM "address" AS t0
WHERE
  (t0."email_address" IS NULL)
```

### SA-20. Условное выражение CASE

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [условные выражения](https://docs.sqlalchemy.org/en/20/core/sqlelement.html#sqlalchemy.sql.expression.case).
- Проверяет: выражение CASE в списке проекции.

```sql
SELECT user_account.id,
       CASE WHEN user_account.name = :name_1 THEN :label_1 ELSE :label_2 END AS category
FROM user_account
```

```python
category = case(
    (user_table.c.name == "sandy", "matched"),
    else_="other",
).label("category")
stmt = select(user_table.c.id, category)
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy20 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from User_account.table
      |> select (fun user ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (User_account.id user)
        and+ projected_right =
          Projection.expr
            (Expr.case
               [ User_account.name user =$ "sandy", Expr.constant Db_type.text "matched" ]
               ~else_:(Expr.constant Db_type.text "other"))
        in
        projected_left, projected_right))
val sqlalchemy20 : (unit, (int64 * string) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy20);;
SELECT
  t0."id",
  (CASE
    WHEN (t0."name" = $1) THEN $2
    ELSE $3
  END)
FROM "user_account" AS t0
```

### SA-21. Сортировка NULLS LAST

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [модификаторы ORDER BY](https://docs.sqlalchemy.org/en/20/core/sqlelement.html#sqlalchemy.sql.expression.nulls_last).
- Проверяет: явное положение `NULL` при сортировке.
- Ограничение: Положение NULL задаётся portable `CASE` ключом сортировки вместо специального `NULLS LAST`.

```sql
SELECT address.id, address.email_address
FROM address
ORDER BY address.email_address ASC NULLS LAST
```

```python
stmt = select(address_table.c.id, address_table.c.email_address).order_by(
    address_table.c.email_address.asc().nulls_last()
)
```

#### OCaml (typed-sql, CASE-сортировка)

```ocaml
# let sqlalchemy21 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Address.table
      |> order_by
           (fun address ->
              Expr.case
                [ ( Expr.is_null (Expr.to_nullable (Address.email address))
                  , Expr.constant Db_type.int 1 )
                ]
                ~else_:(Expr.constant Db_type.int 0))
           `Asc
      |> order_by (fun address -> Expr.to_nullable (Address.email address)) `Asc
      |> select (fun address ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Address.id address)
        and+ projected_right =
          Projection.expr (Expr.to_nullable (Address.email address))
        in
        projected_left, projected_right))
val sqlalchemy21 :
  (unit, (int64 * string option) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy21);;
SELECT
  t0."id",
  t0."email_address"
FROM "address" AS t0
ORDER BY
  (CASE
    WHEN (t0."email_address" IS NULL) THEN $1
    ELSE $2
  END) ASC,
  t0."email_address" ASC
```

### SA-22. Self join через alias

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [псевдонимы таблиц](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#using-aliases).
- Проверяет: два независимых псевдонима одной таблицы в JOIN.

```sql
SELECT user_account.name, related_user.name
FROM user_account
JOIN user_account AS related_user
  ON user_account.id < related_user.id
```

```python
related_user = user_table.alias("related_user")
stmt = select(user_table.c.name, related_user.c.name).join_from(
    user_table,
    related_user,
    user_table.c.id < related_user.c.id,
)
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy22 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from User_account.table
      |> inner_join User_account.table ~on:(fun user related ->
        User_account.id user <. User_account.id related)
      |> select (fun (user, related) ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (User_account.name user)
        and+ projected_right = Projection.expr (User_account.name related) in
        projected_left, projected_right))
val sqlalchemy22 : (unit, (string * string) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy22);;
SELECT
  t0."name",
  t1."name"
FROM "user_account" AS t0
INNER JOIN "user_account" AS t1
  ON (t0."id" < t1."id")
```

### SA-23. CROSS JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [FROM с несколькими источниками](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#explicit-from-clauses-and-joins).
- Проверяет: декартово произведение строк двух таблиц.
- Ограничение: Декартово произведение выражено через `INNER JOIN ON TRUE`, отдельного `CROSS JOIN` builder нет.

```sql
SELECT user_account.id, address.id
FROM user_account, address
```

```python
stmt = select(user_table.c.id, address_table.c.id).select_from(
    user_table, address_table
)
```

#### OCaml (typed-sql)

Декартово произведение задано как `INNER JOIN ON TRUE`, с тем же набором пар строк.

```ocaml
# let sqlalchemy23 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from User_account.table
      |> inner_join Address.table ~on:(fun _ _ -> Condition.true_)
      |> select (fun (user, address) ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (User_account.id user)
        and+ projected_right = Projection.expr (Address.id address) in
        projected_left, projected_right))
val sqlalchemy23 : (unit, (int64 * int64) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy23);;
SELECT
  t0."id",
  t1."id"
FROM "user_account" AS t0
INNER JOIN "address" AS t1
  ON TRUE
```

### SA-24. FULL OUTER JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [OUTER и FULL JOIN](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#outer-and-full-join).
- Проверяет: сохранение несопоставленных строк обеих таблиц; поддержка зависит от СУБД.
- Ограничение: Результат FULL OUTER JOIN собран через `UNION ALL` двух LEFT JOIN; реализация предполагает уникальный ключ с каждой стороны, поэтому unmatched строк не дублируются.

```sql
SELECT user_account.id, address.id
FROM user_account
FULL OUTER JOIN address ON user_account.id = address.user_id
```

```python
stmt = select(user_table.c.id, address_table.c.id).join_from(
    user_table,
    address_table,
    user_table.c.id == address_table.c.user_id,
    full=True,
)
```

#### OCaml (typed-sql, две LEFT JOIN ветви)

```ocaml
let sqlalchemy24_left =
  Query.(
    from User_account.table
    |> left_join Address.table ~on:(fun user address ->
      User_account.id user =. Address.user_id address)
    |> select (fun (user, address) ->
      let open Projection.Let_syntax in
      let+ projected_left = Projection.expr (Expr.to_nullable (User_account.id user))
      and+ projected_right = Projection.expr (Address.nullable_id address) in
      projected_left, projected_right))
;;

let sqlalchemy24_right =
  Query.(
    from Address.table
    |> left_join User_account.table ~on:(fun address user ->
      User_account.id user =. Address.user_id address)
    |> select (fun (address, user) ->
      let open Projection.Let_syntax in
      let+ projected_left = Projection.expr (User_account.nullable_id user)
      and+ projected_right = Projection.expr (Expr.to_nullable (Address.id address)) in
      projected_left, projected_right))
;;
```

```ocaml
# let sqlalchemy24 =
  Statement.query_many
    ~dialect:Dialect.portable
    (Query.union_all sqlalchemy24_left sqlalchemy24_right)
val sqlalchemy24 :
  (unit, (int64 option * int64 option) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy24);;
SELECT *
FROM (
  SELECT
    t0."id",
    t1."id"
  FROM "user_account" AS t0
  LEFT JOIN "address" AS t1
    ON (t0."id" = t1."user_id")
) AS s0
UNION ALL
SELECT *
FROM (
  SELECT
    t1."id",
    t0."id"
  FROM "address" AS t0
  LEFT JOIN "user_account" AS t1
    ON (t1."id" = t0."user_id")
) AS s0
```

### SA-25. Коррелированный LATERAL-подзапрос

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [LATERAL correlation](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#lateral-correlation).
- Проверяет: выбор первой связанной строки через подзапрос, коррелированный с текущей строкой пользователя.
- Ограничение: LATERAL выражен коррелированным scalar subquery с `LIMIT 1`; выбранное значение совпадает.

```sql
SELECT user_account.id, latest_address.email_address
FROM user_account
LEFT JOIN LATERAL (
  SELECT address.email_address
  FROM address
  WHERE address.user_id = user_account.id
  ORDER BY address.id DESC
  LIMIT 1
) AS latest_address ON true
```

```python
latest_address = (
    select(address_table.c.email_address.label("email_address"))
    .where(address_table.c.user_id == user_table.c.id)
    .order_by(address_table.c.id.desc())
    .limit(1)
    .lateral("latest_address")
)
stmt = select(user_table.c.id, latest_address.c.email_address).select_from(
    user_table.outerjoin(latest_address, true())
)
```

#### OCaml (typed-sql, scalar subquery)

```ocaml
# let sqlalchemy25 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from User_account.table
      |> select (fun user ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (User_account.id user)
        and+ projected_right =
          Projection.expr
            (Expr.scalar_subquery_nullable
               Query.(
                 from Address.table
                 |> where (fun address -> Address.user_id address =. User_account.id user)
                 |> order_by Address.id `Desc
                 |> limit_one
                 |> select_scalar (fun address ->
                   Expr.to_nullable (Address.email address))))
        in
        projected_left, projected_right))
val sqlalchemy25 :
  (unit, (int64 * string option) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy25);;
SELECT
  t0."id",
  (
    SELECT
      t1."email_address"
    FROM "address" AS t1
    WHERE
      (t1."user_id" = t0."id")
    ORDER BY
      t1."id" DESC
    LIMIT 1
  )
FROM "user_account" AS t0
```

### SA-26. UNION ALL

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [UNION и другие set operations](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#union-union-all-and-other-set-operations).
- Проверяет: объединение результатов без удаления повторов.

```sql
SELECT user_account.id FROM user_account WHERE user_account.name = :name_1
UNION ALL
SELECT user_account.id FROM user_account WHERE user_account.name = :name_2
```

```python
stmt = union_all(
    select(user_table.c.id).where(user_table.c.name == "sandy"),
    select(user_table.c.id).where(user_table.c.name == "spongebob"),
)
```

#### OCaml (typed-sql)

```ocaml
let sqlalchemy26_left =
  Query.(
    from User_account.table
    |> where (fun user -> User_account.name user =$ "sandy")
    |> select (fun user -> Projection.expr (User_account.id user)))
;;

let sqlalchemy26_right =
  Query.(
    from User_account.table
    |> where (fun user -> User_account.name user =$ "spongebob")
    |> select (fun user -> Projection.expr (User_account.id user)))
;;
```

```ocaml
# let sqlalchemy26 =
  Statement.query_many
    ~dialect:Dialect.portable
    (Query.union_all sqlalchemy26_left sqlalchemy26_right)
val sqlalchemy26 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy26);;
SELECT *
FROM (
  SELECT
    t0."id"
  FROM "user_account" AS t0
  WHERE
    (t0."name" = $1)
) AS s0
UNION ALL
SELECT *
FROM (
  SELECT
    t0."id"
  FROM "user_account" AS t0
  WHERE
    (t0."name" = $2)
) AS s0
```

### SA-27. INTERSECT

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [UNION и другие set operations](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#union-union-all-and-other-set-operations).
- Проверяет: пересечение результатов запросов с совместимыми проекциями.

```sql
SELECT address.user_id FROM address WHERE address.email_address LIKE :pattern_1
INTERSECT
SELECT address.user_id FROM address WHERE address.id > :id_1
```

```python
stmt = intersect(
    select(address_table.c.user_id).where(
        address_table.c.email_address.like(email_pattern)
    ),
    select(address_table.c.user_id).where(address_table.c.id > min_address_id),
)
```

#### OCaml (typed-sql)

```ocaml
let sqlalchemy27_left =
  Query.(
    from Address.table
    |> where (fun address -> Address.email address =~$ "%@example.com")
    |> select (fun address -> Projection.expr (Address.user_id address)))
;;

let sqlalchemy27_right =
  Query.(
    from Address.table
    |> where (fun address -> Address.id address >$ 10L)
    |> select (fun address -> Projection.expr (Address.user_id address)))
;;
```

```ocaml
# let sqlalchemy27 =
  Statement.query_many
    ~dialect:Dialect.portable
    (Query.intersect sqlalchemy27_left sqlalchemy27_right)
val sqlalchemy27 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy27);;
SELECT *
FROM (
  SELECT
    t0."user_id"
  FROM "address" AS t0
  WHERE
    (t0."email_address" LIKE $1)
) AS s0
INTERSECT
SELECT *
FROM (
  SELECT
    t0."user_id"
  FROM "address" AS t0
  WHERE
    (t0."id" > $2)
) AS s0
```

### SA-28. EXCEPT

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [UNION и другие set operations](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#union-union-all-and-other-set-operations).
- Проверяет: строки первого результата, отсутствующие во втором; поддержка зависит от СУБД.

```sql
SELECT user_account.id FROM user_account
EXCEPT
SELECT address.user_id FROM address
```

```python
stmt = except_(
    select(user_table.c.id),
    select(address_table.c.user_id),
)
```

#### OCaml (typed-sql)

```ocaml
let sqlalchemy28_users =
  Query.(
    from User_account.table |> select (fun user -> Projection.expr (User_account.id user)))
;;

let sqlalchemy28_addresses =
  Query.(
    from Address.table
    |> select (fun address -> Projection.expr (Address.user_id address)))
;;
```

```ocaml
# let sqlalchemy28 =
  Statement.query_many
    ~dialect:Dialect.portable
    (Query.except sqlalchemy28_users sqlalchemy28_addresses)
val sqlalchemy28 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy28);;
SELECT *
FROM (
  SELECT
    t0."id"
  FROM "user_account" AS t0
) AS s0
EXCEPT
SELECT *
FROM (
  SELECT
    t0."user_id"
  FROM "address" AS t0
) AS s0
```

### SA-29. VALUES как источник строк

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [конструктор VALUES](https://docs.sqlalchemy.org/en/20/core/selectable.html#sqlalchemy.sql.expression.values).
- Проверяет: использование набора заданных значений как FROM-источника.
- Ограничение: relation требует descriptors колонок; compiler проверяет ширину и database types каждой строки. Для динамической формы ошибки возвращаются при compilation.

```sql
SELECT selected_ids.id
FROM (VALUES (:id_1), (:id_2)) AS selected_ids(id)
```

```python
selected_ids = values(
    column("id", Integer), name="selected_ids"
).data([(1,), (2,)]).alias()
stmt = select(selected_ids.c.id)
```

```ocaml
let selected_ids =
  Values.create
    ~table:Selected_ids.table
    ~columns:(fun selected -> Projection.expr (Selected_ids.id selected))
    ~first:(Values.Row.expr (Expr.constant Db_type.int64 1L))
    ~rest:[ Values.Row.expr (Expr.constant Db_type.int64 2L) ]
;;

let query =
  Query.(
    from_values selected_ids
    |> select (fun selected -> Projection.expr (Selected_ids.id selected)))
;;
```

### SA-30. Рекурсивный CTE

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [рекурсивные CTE](https://docs.sqlalchemy.org/en/20/core/selectable.html#sqlalchemy.sql.expression.HasCTE.cte).
- Проверяет: литеральный anchor без `FROM` и рекурсивное расширение до верхней границы.

```sql
WITH RECURSIVE nums(n) AS (
  SELECT :start
  UNION ALL
  SELECT nums.n + :step FROM nums WHERE nums.n < :upper_bound
)
SELECT nums.n FROM nums
```

```python
nums = select(literal(1).label("n")).cte("nums", recursive=True)
nums_step = nums.alias("nums_step")
nums = nums.union_all(
    select((nums_step.c.n + 1).label("n")).where(nums_step.c.n < 5)
)
stmt = select(nums.c.n)
```

#### OCaml (typed-sql, рекурсивный CTE)

```ocaml
let sqlalchemy30_anchor = Query.select_one_relation (Expr.constant Db_type.int64 1L)
```

```ocaml
# let sqlalchemy30 =
  let definition =
    Cte.recursive_relation
      ~union:`Union_all
      ~anchor:sqlalchemy30_anchor
      ~step:(fun numbers ->
        Query.(
          from_cte_relation numbers
          |> where (fun number -> number <$ 5L)
          |> select_relation (fun number ->
            Derived_table.Fields.expr
              Expr.Int64.Infix.(number +. Expr.constant Db_type.int64 1L))))
  in
  Statement.query_many
    ~dialect:Dialect.portable
    (Cte.with_result definition ~f:(fun numbers ->
       Query.(from_cte_relation numbers |> select Projection.expr)))
val sqlalchemy30 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy30);;
WITH RECURSIVE
  "c0" (
    "field_1"
  ) AS (
    SELECT
      $1
    UNION ALL
    SELECT
      (t0."field_1" + $2)
    FROM "c0" AS t0
    WHERE
      (t0."field_1" < $3)
  )
SELECT
  t0."field_1"
FROM "c0" AS t0
```

### SA-31. Многострочный INSERT

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [INSERT с несколькими значениями](https://docs.sqlalchemy.org/en/20/tutorial/data_insert.html#insert-usually-generates-the-values-clause-automatically).
- Проверяет: вставку нескольких строк одной конструкцией; синтаксис зависит от диалекта.

```sql
INSERT INTO user_account (name, fullname)
VALUES (:name_1, :fullname_1), (:name_2, :fullname_2)
```

```python
stmt = insert(user_table).values(
    [
        {"name": "sandy", "fullname": "Sandy Cheeks"},
        {"name": "spongebob", "fullname": "Spongebob Squarepants"},
    ]
)
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy31 =
  Statement.command
    ~dialect:Dialect.portable
    (Insert.rows
       User_account.table
       [ (fun row ->
           row
           |> Insert.set User_account.name_column "sandy"
           |> Insert.set User_account.fullname_column (Some "Sandy Cheeks"))
       ; (fun row ->
           row
           |> Insert.set User_account.name_column "spongebob"
           |> Insert.set User_account.fullname_column (Some "SpongeBob SquarePants"))
       ]
     |> Insert.command)
val sqlalchemy31 : (unit, Affected_rows.t, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy31);;
INSERT INTO "user_account" (
  "name",
  "fullname"
)
VALUES
  ($1, $2),
  ($3, $4)
```

### SA-32. INSERT из SELECT

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [INSERT FROM SELECT](https://docs.sqlalchemy.org/en/20/tutorial/data_insert.html#insertfromselect).
- Проверяет: вставку результата запроса с соответствующим списком целевых колонок.

```sql
INSERT INTO address (user_id, email_address)
SELECT user_account.id, :email
FROM user_account
WHERE user_account.name = :name
```

```python
source = select(user_table.c.id, bindparam("email")).where(
    user_table.c.name == bindparam("name")
)
stmt = insert(address_table).from_select(
    ["user_id", "email_address"], source
)
```

#### OCaml (typed-sql)

```ocaml
let sqlalchemy32_columns =
  Insert.Columns.(column Address.user_id_column |> add Address.email_column)
;;
```

```ocaml
# let sqlalchemy32 =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let open Parameters.Let_syntax in
    let+ email = params.expr Db_type.text ~get:(fun (email, _) -> email)
    and+ name = params.expr Db_type.text ~get:(fun (_, name) -> name) in
    params.command
      (let source =
         Query.(
           from User_account.table
           |> where (fun user -> User_account.name user =. name)
           |> select (fun user ->
             let open Projection.Let_syntax in
             let+ projected_left = Projection.expr (User_account.id user)
             and+ projected_right = Projection.expr email in
             projected_left, projected_right))
       in
       Insert.(into Address.table |> from_select sqlalchemy32_columns source |> command)))
val sqlalchemy32 :
  (string * string, Affected_rows.t, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Stdlib.print_endline
    (Statement.sql_exn
       ~dialect:Postgresql
       ~input:("sandy@example.com", "sandy")
       sqlalchemy32);;
INSERT INTO "address" (
  "user_id",
  "email_address"
)
SELECT
  t0."id",
  $1
FROM "user_account" AS t0
WHERE
  (t0."name" = $2)
```

### SA-33. UPDATE ... FROM

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✗
- Источник: [UPDATE с дополнительными FROM-таблицами](https://docs.sqlalchemy.org/en/20/tutorial/data_update.html#update-from).
- Проверяет: обновление по совпадению с другой таблицей; SQL-форма зависит от СУБД.
- Ограничение: Значение из связанной таблицы задаётся в `UPDATE ... FROM`; синтаксис совпадает с PostgreSQL формой.

```sql
UPDATE user_account
SET fullname = address.email_address
FROM address
WHERE user_account.id = address.user_id
```

```python
stmt = (
    update(user_table)
    .where(user_table.c.id == address_table.c.user_id)
    .values(fullname=address_table.c.email_address)
)
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy33 =
  Statement.command
    ~dialect:Dialect.portable
    Update.(
      table User_account.table
      |> from Address.table ~f:(fun user address update ->
        update
        |> set_expr
             User_account.fullname_column
             (Expr.to_nullable (Address.email address))
        |> where (fun _ -> User_account.id user =. Address.user_id address))
      |> command)
val sqlalchemy33 : (unit, Affected_rows.t, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy33);;
UPDATE "user_account" AS t0
SET
  "fullname" = t1."email_address"
FROM "address" AS t1
WHERE
  (t0."id" = t1."user_id")
```

### SA-34. DELETE ... USING

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [DELETE с дополнительными FROM-таблицами](https://docs.sqlalchemy.org/en/20/tutorial/data_update.html#multiple-table-deletes).
- Проверяет: удаление по условию, связанному с другой таблицей; форма `USING` зависит от СУБД.
- Ограничение: DELETE с `USING` переписан как коррелированный `WHERE EXISTS`; совпадает по строкам при уникальном User ID.

```sql
DELETE FROM address
USING user_account
WHERE address.user_id = user_account.id
  AND user_account.name = :name
```

```python
stmt = delete(address_table).where(
    address_table.c.user_id == user_table.c.id,
    user_table.c.name == name,
)
```

#### OCaml (typed-sql, EXISTS-equivalent)

```ocaml
# let sqlalchemy34 =
  Statement.command
    ~dialect:Dialect.portable
    Delete.(
      from Address.table
      |> where (fun address ->
        Query.exists
          Query.(
            from User_account.table
            |> where (fun user ->
              User_account.id user
              =. Address.user_id address
              &&. (User_account.name user =$ "sandy"))))
      |> command)
val sqlalchemy34 : (unit, Affected_rows.t, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy34);;
DELETE FROM "address"
WHERE
  (EXISTS (
    SELECT
      1
    FROM "user_account" AS t1
    WHERE
      (
        (t1."id" = "user_id")
        AND (t1."name" = $1)
      )
  ))
```

### SA-35. PostgreSQL UPSERT через ON CONFLICT

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [PostgreSQL ON CONFLICT](https://docs.sqlalchemy.org/en/20/dialects/postgresql.html#insert-on-conflict-upsert).
- Проверяет: вставку новой строки или обновление fullname при конфликте уникального имени.

```sql
INSERT INTO user_account (name, fullname)
VALUES (:name, :fullname)
ON CONFLICT (name) DO UPDATE SET fullname = excluded.fullname
```

```python
insert_stmt = pg_insert(user_table).values(name=name, fullname=fullname)
stmt = insert_stmt.on_conflict_do_update(
    index_elements=[user_table.c.name],
    set_={"fullname": insert_stmt.excluded.fullname},
)
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy35 =
  Statement.command
    ~dialect:Dialect.portable
    Insert.(
      into User_account.table
      |> set User_account.name_column "sandy"
      |> set User_account.fullname_column (Some "Sandy Cheeks")
      |> on_conflict (Conflict_target.column User_account.name_column)
      |> do_update (fun ~existing:_ ~excluded ->
        Conflict_update.set_expr
          User_account.fullname_column
          (User_account.fullname excluded)
          Conflict_update.empty)
      |> command)
val sqlalchemy35 : (unit, Affected_rows.t, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy35);;
INSERT INTO "user_account" AS t0 (
  "name",
  "fullname"
)
VALUES
  ($1, $2)
ON CONFLICT (
  "name"
)
DO UPDATE
SET
  "fullname" = excluded."fullname"
```

### SA-36. Пользователи без адресов через NOT EXISTS

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [EXISTS subqueries](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#exists-subqueries).
- Проверяет: отрицание коррелированного `EXISTS` и сохранение пользователей с пустой коллекцией адресов.

```sql
SELECT user_account.id, user_account.name
FROM user_account
WHERE NOT EXISTS (
  SELECT address.id FROM address
  WHERE address.user_id = user_account.id
)
```

```python
addresses = (
    select(address_table.c.id)
    .where(address_table.c.user_id == user_table.c.id)
    .exists()
)
stmt = select(user_table.c.id, user_table.c.name).where(~addresses)
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy36 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from User_account.table
      |> where (fun user ->
        not_exists
          Query.(
            from Address.table
            |> where (fun address -> Address.user_id address =. User_account.id user)))
      |> select (fun user ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (User_account.id user)
        and+ projected_right = Projection.expr (User_account.name user) in
        projected_left, projected_right))
val sqlalchemy36 : (unit, (int64 * string) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy36);;
SELECT
  t0."id",
  t0."name"
FROM "user_account" AS t0
WHERE
  (NOT EXISTS (
    SELECT
      1
    FROM "address" AS t1
    WHERE
      (t1."user_id" = t0."id")
  ))
```

### SA-37. Условный агрегат FILTER после LEFT JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Special modifiers: FILTER](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#special-modifiers-within-group-filter).
- Проверяет: подсчёт только адресов с нужным доменом и ноль для пользователя без адресов; форма SQL показана для PostgreSQL.
- Ограничение: Эквивалентный фильтр перенесён в `LEFT JOIN ON`, затем считается ненулевой ID; для каждой строки пользователя получается тот же count.

```sql
SELECT user_account.id,
       COUNT(address.id) FILTER (
         WHERE address.email_address LIKE :pattern
       ) AS matched
FROM user_account
LEFT JOIN address ON address.user_id = user_account.id
GROUP BY user_account.id
```

```python
stmt = (
    select(
        user_table.c.id,
        func.count(address_table.c.id)
        .filter(address_table.c.email_address.like(pattern))
        .label("matched"),
    )
    .outerjoin(address_table, address_table.c.user_id == user_table.c.id)
    .group_by(user_table.c.id)
)
```

#### OCaml (typed-sql, фильтр в ON)

Условие домена перенесено в `ON`, после чего COUNT по nullable ID возвращает ноль и для пользователя без совпавших адресов.

```ocaml
# let sqlalchemy37 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from User_account.table
      |> left_join Address.table ~on:(fun user address ->
        User_account.id user
        =. Address.user_id address
        &&. (Address.email address =~$ "%@example.com"))
      |> group_by (fun (user, _address) -> User_account.id user)
      |> select (fun (user, address) ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (User_account.id user)
        and+ projected_right =
          Projection.expr (Expr.count (Address.nullable_id address))
        in
        projected_left, projected_right))
val sqlalchemy37 : (unit, (int64 * int64) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy37);;
SELECT
  t0."id",
  COUNT(t1."id")
FROM "user_account" AS t0
LEFT JOIN "address" AS t1
  ON (
    (t0."id" = t1."user_id")
    AND (t1."email_address" LIKE $1)
  )
GROUP BY
  t0."id"
```

### SA-38. Последний адрес каждого пользователя через ROW_NUMBER

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Window Functions](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#window-functions).
- Проверяет: нумерацию адресов внутри каждого `user_id` и фильтр номера во внешнем запросе; пользователь без адресов не возвращается.
- Ограничение: Уникальный address ID позволяет заменить `ROW_NUMBER() = 1` анти-подзапросом на более высокий ID.

```sql
SELECT user_account.name, ranked.email_address
FROM user_account
JOIN (
  SELECT address.user_id, address.email_address,
         ROW_NUMBER() OVER (
           PARTITION BY address.user_id ORDER BY address.id DESC
         ) AS row_no
  FROM address
) AS ranked ON ranked.user_id = user_account.id
WHERE ranked.row_no = 1
```

```python
ranked = (
    select(
        address_table.c.user_id,
        address_table.c.email_address,
        func.row_number().over(
            partition_by=address_table.c.user_id,
            order_by=address_table.c.id.desc(),
        ).label("row_no"),
    )
    .subquery("ranked")
)
stmt = (
    select(user_table.c.name, ranked.c.email_address)
    .join(ranked, ranked.c.user_id == user_table.c.id)
    .where(ranked.c.row_no == 1)
)
```

#### OCaml (typed-sql, NOT EXISTS эквивалент)

Уникальный монотонный `address.id` задаёт тот же последний адрес пользователя без оконной функции.

```ocaml
# let sqlalchemy38 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Address.table
      |> where (fun address ->
        not_exists
          Query.(
            from Address.table
            |> where (fun newer ->
              Address.user_id newer
              =. Address.user_id address
              &&. (Address.id newer >. Address.id address))))
      |> inner_join User_account.table ~on:(fun address user ->
        Address.user_id address =. User_account.id user)
      |> select (fun (address, user) ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (User_account.name user)
        and+ projected_right = Projection.expr (Address.email address) in
        projected_left, projected_right))
val sqlalchemy38 : (unit, (string * string) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy38);;
SELECT
  t1."name",
  t0."email_address"
FROM "address" AS t0
INNER JOIN "user_account" AS t1
  ON (t0."user_id" = t1."id")
WHERE
  (NOT EXISTS (
    SELECT
      1
    FROM "address" AS t2
    WHERE
      (
        (t2."user_id" = t0."user_id")
        AND (t2."id" > t0."id")
      )
  ))
```

### SA-39. Страница строк с FOR UPDATE SKIP LOCKED

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [`Select.with_for_update`](https://docs.sqlalchemy.org/en/20/core/selectable.html#sqlalchemy.sql.expression.Select.with_for_update).
- Проверяет: блокировку выбранных строк в транзакции и пропуск строк, уже заблокированных другим читателем; форма PostgreSQL.

```sql
SELECT user_account.id, user_account.name
FROM user_account
ORDER BY user_account.id
LIMIT :limit
FOR UPDATE OF user_account SKIP LOCKED
```

```python
stmt = (
    select(user_table.c.id, user_table.c.name)
    .order_by(user_table.c.id)
    .limit(10)
    .with_for_update(skip_locked=True, of=user_table)
)
```

#### OCaml (typed-sql)

`OF` выбирает источник по query-local ссылке; compiler подставляет его SQL alias.

```ocaml
# let sqlalchemy39 =
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let open Parameters.Let_syntax in
    let+ page_size = params.non_negative_int ~name:"page_size" ~get:Fn.id in
    params.query_many
      Query.(
        from User_account.table
        |> order_by User_account.id `Asc
        |> limit_param page_size
        |> Postgresql.Query.for_update
             ~of_:(fun user -> [ Postgresql.Query.target user ])
             ~skip_locked:true
        |> select (fun user ->
          let open Projection.Let_syntax in
          let+ projected_left = Projection.expr (User_account.id user)
          and+ projected_right = Projection.expr (User_account.name user) in
          projected_left, projected_right)))
val sqlalchemy39 : (int, (int64 * string) list, [ `Postgresql ]) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ~input:10 sqlalchemy39);;
SELECT
  t0."id",
  t0."name"
FROM "user_account" AS t0
ORDER BY
  t0."id" ASC
LIMIT $1
FOR UPDATE OF t0 SKIP LOCKED
```

### SA-40. UPDATE RETURNING как источник CTE

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: `Postgresql.Cte.returning` связывает `UPDATE ... RETURNING` с типизированным источником внешнего `SELECT`; SQLite не поддерживает data-modifying CTE.
- Источник: [CTE with DML](https://docs.sqlalchemy.org/en/20/core/selectable.html#sqlalchemy.sql.expression.HasCTE.cte).
- Проверяет: выполнение UPDATE ровно один раз и чтение его `RETURNING`-строк через внешний SELECT; требуется PostgreSQL.

```sql
WITH updated AS (
  UPDATE user_account
  SET fullname = :fullname
  WHERE name = :name
  RETURNING id, fullname
)
SELECT updated.id, updated.fullname FROM updated
```

```python
updated = (
    update(user_table)
    .where(user_table.c.name == "sandy")
    .values(fullname="Sandra")
    .returning(user_table.c.id, user_table.c.fullname)
    .cte("updated")
)
stmt = select(updated.c.id, updated.c.fullname)
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy40 =
  Statement.query_many
    ~dialect:Dialect.postgresql
    (let updated =
       Update.(
         table User_account.table
         |> set User_account.fullname_column (Some "Sandra")
         |> where (fun user ->
           User_account.name user =. Expr.constant Db_type.text "sandy")
         |> returning (fun user ->
           let open Projection.Let_syntax in
           let+ projected_left = Projection.expr (User_account.id user)
           and+ projected_right = Projection.expr (User_account.fullname user) in
           projected_left, projected_right))
     in
     Cte.with_result
       (Postgresql.Cte.returning
          ~table:User_account.table
          ~columns:(fun user ->
            let open Projection.Let_syntax in
            let+ projected_left = Projection.expr (User_account.id user)
            and+ projected_right = Projection.expr (User_account.fullname user) in
            projected_left, projected_right)
          updated)
       ~f:(fun updated ->
         Query.(
           from_cte updated
           |> select (fun user ->
             let open Projection.Let_syntax in
             let+ projected_left = Projection.expr (User_account.id user)
             and+ projected_right = Projection.expr (User_account.fullname user) in
             projected_left, projected_right))))
val sqlalchemy40 :
  (unit, (int64 * string option) list, [ `Postgresql ]) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy40);;
WITH
  "c0" (
    "id",
    "fullname"
  ) AS (
    UPDATE "user_account"
    SET
      "fullname" = $1
    WHERE
      ("name" = $2)
    RETURNING
      "id",
      "fullname"
  )
SELECT
  t0."id",
  t0."fullname"
FROM "c0" AS t0
```
### SA-41. Необязательный фильтр по имени и минимальному ID


- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [dynamic WHERE criteria](https://docs.sqlalchemy.org/en/20/orm/queryguide/select.html#the-where-clause).
- Проверяет: независимое добавление условий и стабильный порядок результата.

```sql
SELECT id, name FROM user_account
WHERE name = :name AND id >= :minimum_id ORDER BY id
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy41 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from User_account.table
      |> where_opt (Some "sandy") ~f:(fun user name -> User_account.name user =$ name)
      |> where_opt (Some 1L) ~f:(fun user minimum_id ->
        User_account.id user >=$ minimum_id)
      |> order_by User_account.id `Asc
      |> select (fun user ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (User_account.id user)
        and+ projected_right = Projection.expr (User_account.name user) in
        projected_left, projected_right))
val sqlalchemy41 : (unit, (int64 * string) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy41);;
SELECT
  t0."id",
  t0."name"
FROM "user_account" AS t0
WHERE
  (
    (t0."name" = $1)
    AND (t0."id" >= $2)
  )
ORDER BY
  t0."id" ASC
```

### SA-42. EXISTS и NOT EXISTS для проверки двух условий

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [EXISTS subqueries](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#exists-subqueries).
- Проверяет: наличие адреса одного домена и отсутствие адреса другого домена у того же пользователя.

```sql
SELECT id FROM user_account
WHERE EXISTS (SELECT 1 FROM address WHERE user_id = user_account.id AND email_address LIKE '%@example.com')
  AND NOT EXISTS (SELECT 1 FROM address WHERE user_id = user_account.id AND email_address LIKE '%@blocked.test')
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy42 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from User_account.table
      |> where (fun user ->
        let has_allowed_domain =
          Query.exists
            Query.(
              from Address.table
              |> where (fun address ->
                Address.user_id address
                =. User_account.id user
                &&. (Address.email address =~$ "%@example.com")))
        in
        let lacks_blocked_domain =
          Query.not_exists
            Query.(
              from Address.table
              |> where (fun address ->
                Address.user_id address
                =. User_account.id user
                &&. (Address.email address =~$ "%@blocked.test")))
        in
        has_allowed_domain &&. lacks_blocked_domain)
      |> select (fun user -> Projection.expr (User_account.id user)))
val sqlalchemy42 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy42);;
SELECT
  t0."id"
FROM "user_account" AS t0
WHERE
  (
    (EXISTS (
      SELECT
        1
      FROM "address" AS t1
      WHERE
        (
          (t1."user_id" = t0."id")
          AND (t1."email_address" LIKE $1)
        )
    ))
    AND (NOT EXISTS (
      SELECT
        1
      FROM "address" AS t1
      WHERE
        (
          (t1."user_id" = t0."id")
          AND (t1."email_address" LIKE $2)
        )
    ))
  )
```

### SA-43. Scalar subquery с COALESCE

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [scalar and correlated subqueries](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#scalar-and-correlated-subqueries).
- Проверяет: nullable результат связанного поиска и подстановку значения по умолчанию.

```sql
SELECT user_account.id,
       COALESCE((SELECT address.email_address FROM address WHERE address.user_id = user_account.id ORDER BY address.id LIMIT 1), '(none)')
FROM user_account
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy43 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from User_account.table
      |> select (fun user ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (User_account.id user)
        and+ projected_right =
          Projection.expr
            (Expr.coalesce
               (Expr.scalar_subquery_nullable
                  Query.(
                    from Address.table
                    |> where (fun address ->
                      Address.user_id address =. User_account.id user)
                    |> order_by Address.id `Asc
                    |> limit_one
                    |> select_scalar (fun address ->
                      Expr.to_nullable (Address.email address))))
               ~default:(Expr.constant Db_type.text "(none)"))
        in
        projected_left, projected_right))
val sqlalchemy43 : (unit, (int64 * string) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy43);;
SELECT
  t0."id",
  COALESCE((
    SELECT
      t1."email_address"
    FROM "address" AS t1
    WHERE
      (t1."user_id" = t0."id")
    ORDER BY
      t1."id" ASC
    LIMIT 1
  ), $1)
FROM "user_account" AS t0
```

### SA-44. LEFT JOIN с агрегатом и HAVING

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [aggregate functions with GROUP BY](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#aggregate-functions-with-group-by-having).
- Проверяет: сохранение пользователей без адресов и порог по числу связанных строк.

```sql
SELECT user_account.id, COUNT(address.id)
FROM user_account LEFT JOIN address ON address.user_id = user_account.id
GROUP BY user_account.id HAVING COUNT(address.id) >= 2
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy44 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from User_account.table
      |> left_join Address.table ~on:(fun user address ->
        User_account.id user =. Address.user_id address)
      |> group_by (fun (user, _address) -> User_account.id user)
      |> having (fun (user, address) -> Expr.count (Address.nullable_id address) >=$ 2L)
      |> select (fun (user, address) ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (User_account.id user)
        and+ projected_right =
          Projection.expr (Expr.count (Address.nullable_id address))
        in
        projected_left, projected_right))
val sqlalchemy44 : (unit, (int64 * int64) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy44);;
SELECT
  t0."id",
  COUNT(t1."id")
FROM "user_account" AS t0
LEFT JOIN "address" AS t1
  ON (t0."id" = t1."user_id")
GROUP BY
  t0."id"
HAVING
  (COUNT(t1."id") >= $1)
```

### SA-45. Keyset-пагинация по имени и ID

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [ordering and pagination](https://docs.sqlalchemy.org/en/20/core/selectable.html#sqlalchemy.sql.expression.GenerativeSelect.limit).
- Проверяет: лексикографический cursor, tie-break по ID и ограничение страницы.

```sql
SELECT id, name FROM user_account
WHERE name > :last_name OR (name = :last_name AND id > :last_id)
ORDER BY name, id LIMIT :page_size
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy45 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from User_account.table
      |> where (fun user ->
        User_account.name user
        >$ "sandy"
        ||. (User_account.name user =$ "sandy" &&. (User_account.id user >$ 10L)))
      |> order_by User_account.name `Asc
      |> order_by User_account.id `Asc
      |> limit 20
      |> select (fun user ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (User_account.name user)
        and+ projected_right = Projection.expr (User_account.id user) in
        projected_left, projected_right))
val sqlalchemy45 : (unit, (string * int64) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy45);;
SELECT
  t0."name",
  t0."id"
FROM "user_account" AS t0
WHERE
  (
    (t0."name" > $1)
    OR (
      (t0."name" = $2)
      AND (t0."id" > $3)
    )
  )
ORDER BY
  t0."name" ASC,
  t0."id" ASC
LIMIT 20
```

### SA-46. UPDATE со значением из связанного адреса

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [correlated updates](https://docs.sqlalchemy.org/en/20/tutorial/data_update.html#correlated-updates).
- Проверяет: связь update target с источником и изменение только совпавших пользователей.

```sql
UPDATE user_account SET fullname = address.email_address
FROM address WHERE user_account.id = address.user_id AND address.id = :address_id
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy46 =
  Statement.command
    ~dialect:Dialect.portable
    Update.(
      table User_account.table
      |> from Address.table ~f:(fun user address update ->
        update
        |> set_expr
             User_account.fullname_column
             (Expr.to_nullable (Address.email address))
        |> where (fun _ ->
          User_account.id user =. Address.user_id address &&. (Address.id address =$ 1L)))
      |> command)
val sqlalchemy46 : (unit, Affected_rows.t, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy46);;
UPDATE "user_account" AS t0
SET
  "fullname" = t1."email_address"
FROM "address" AS t1
WHERE
  (
    (t0."id" = t1."user_id")
    AND (t1."id" = $1)
  )
```

### SA-47. UPSERT только при изменении имени

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [ON CONFLICT DO UPDATE](https://docs.sqlalchemy.org/en/20/dialects/postgresql.html#insert-on-conflict-upsert).
- Проверяет: предикат ветви обновления и отдельное поведение новой строки.

```sql
INSERT INTO user_account (name, fullname) VALUES (:name, :fullname)
ON CONFLICT (name) DO UPDATE SET fullname = EXCLUDED.fullname
WHERE user_account.fullname IS DISTINCT FROM EXCLUDED.fullname
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy47 =
  Statement.command
    ~dialect:Dialect.portable
    Insert.(
      into User_account.table
      |> set User_account.name_column "sandy"
      |> set User_account.fullname_column (Some "Sandy")
      |> on_conflict (Conflict_target.column User_account.name_column)
      |> do_update (fun ~existing ~excluded ->
        Conflict_update.empty
        |> Conflict_update.set_expr
             User_account.fullname_column
             (User_account.fullname excluded)
        |> Conflict_update.where
             (Expr.is_distinct_from
                (User_account.fullname existing)
                (User_account.fullname excluded)))
      |> command)
val sqlalchemy47 : (unit, Affected_rows.t, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy47);;
INSERT INTO "user_account" AS t0 (
  "name",
  "fullname"
)
VALUES
  ($1, $2)
ON CONFLICT (
  "name"
)
DO UPDATE
SET
  "fullname" = excluded."fullname"
WHERE
  (t0."fullname" IS DISTINCT FROM excluded."fullname")
```

### SA-48. Удаление адресов с возвратом ключей

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [DELETE RETURNING](https://docs.sqlalchemy.org/en/20/tutorial/data_update.html#using-returning-with-update-delete).
- Проверяет: ограниченное удаление и идентификаторы фактически удалённых строк.

```sql
DELETE FROM address WHERE user_id = :user_id AND email_address LIKE :pattern RETURNING id
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy48 =
  Statement.query_many
    ~dialect:Dialect.portable
    Delete.(
      from Address.table
      |> where (fun address ->
        Address.user_id address =$ 1L &&. (Address.email address =~$ "%@example.com"))
      |> returning (fun address -> Projection.expr (Address.id address)))
val sqlalchemy48 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy48);;
DELETE FROM "address"
WHERE
  (
    ("user_id" = $1)
    AND ("email_address" LIKE $2)
  )
RETURNING
  "id"
```

### SA-49. Пересечение с множеством пользовательских адресов

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [set operations](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#union-union-all-and-other-set-operations).
- Проверяет: совместимые скалярные проекции для `INTERSECT` и `EXCEPT`.

```sql
(SELECT id FROM user_account INTERSECT SELECT user_id FROM address)
EXCEPT SELECT user_id FROM address WHERE email_address LIKE '%@blocked.test'
```

#### OCaml (typed-sql)

```ocaml
let sqlalchemy49_users =
  Query.(
    from User_account.table |> select (fun user -> Projection.expr (User_account.id user)))
;;

let sqlalchemy49_address_users =
  Query.(
    from Address.table
    |> select (fun address -> Projection.expr (Address.user_id address)))
;;

let sqlalchemy49_blocked =
  Query.(
    from Address.table
    |> where (fun address -> Address.email address =~$ "%@blocked.test")
    |> select (fun address -> Projection.expr (Address.user_id address)))
;;
```

```ocaml
# let sqlalchemy49 =
  Statement.query_many
    ~dialect:Dialect.portable
    (Query.except
       (Query.intersect sqlalchemy49_users sqlalchemy49_address_users)
       sqlalchemy49_blocked)
val sqlalchemy49 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy49);;
SELECT *
FROM (
  SELECT *
  FROM (
    SELECT
      t0."id"
    FROM "user_account" AS t0
  ) AS s0
  INTERSECT
  SELECT *
  FROM (
    SELECT
      t0."user_id"
    FROM "address" AS t0
  ) AS s0
) AS s0
EXCEPT
SELECT *
FROM (
  SELECT
    t0."user_id"
  FROM "address" AS t0
  WHERE
    (t0."email_address" LIKE $1)
) AS s0
```

### SA-50. Отчёт по пользователям с несколькими адресами

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [aggregate functions with GROUP BY](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#aggregate-functions-with-group-by-having).
- Проверяет: фильтр до агрегации, две сортировки, `HAVING` и ограничение результата.

```sql
SELECT user_account.id, COUNT(address.id)
FROM user_account JOIN address ON address.user_id = user_account.id
WHERE address.email_address LIKE :pattern
GROUP BY user_account.id HAVING COUNT(address.id) > 1
ORDER BY COUNT(address.id) DESC, user_account.id LIMIT 10
```

#### OCaml (typed-sql)

```ocaml
# let sqlalchemy50 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from User_account.table
      |> inner_join Address.table ~on:(fun user address ->
        User_account.id user =. Address.user_id address)
      |> where (fun (_user, address) -> Address.email address =~$ "%@example.com")
      |> group_by (fun (user, _address) -> User_account.id user)
      |> having (fun (_user, address) -> Expr.count (Address.id address) >$ 1L)
      |> order_by (fun (_user, address) -> Expr.count (Address.id address)) `Desc
      |> order_by (fun (user, _address) -> User_account.id user) `Asc
      |> limit 10
      |> select (fun (user, address) ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (User_account.id user)
        and+ projected_right = Projection.expr (Expr.count (Address.id address)) in
        projected_left, projected_right))
val sqlalchemy50 : (unit, (int64 * int64) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sqlalchemy50);;
SELECT
  t0."id",
  COUNT(t1."id")
FROM "user_account" AS t0
INNER JOIN "address" AS t1
  ON (t0."id" = t1."user_id")
WHERE
  (t1."email_address" LIKE $1)
GROUP BY
  t0."id"
HAVING
  (COUNT(t1."id") > $2)
ORDER BY
  COUNT(t1."id") DESC,
  t0."id" ASC
LIMIT 10
```
