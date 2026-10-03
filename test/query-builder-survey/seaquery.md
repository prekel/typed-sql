<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Сценарии запросов из SeaQuery

**Желаемый таргет: 20 сценариев — 5 обычных и 15 сложных.** Каталог включает пять обычных и пятнадцать сложных сценариев.

Источники — [раздел Query Select](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html) документации SeaQuery и [руководство SeaORM](https://www.sea-ql.org/sea-orm-tutorial/ch01-08-sql-with-sea-query.html) (доступ 28.09.2026). Примеры сокращены и адаптированы под схему `users(id, name, country)` и `posts(id, user_id, title)`. SQL приведён в форме PostgreSQL; `build(PostgresQueryBuilder)` также возвращает значения отдельно от SQL.

SeaQuery распространяется по [MIT или Apache-2.0](https://github.com/SeaQL/sea-query#license). Здесь используется вариант MIT для уведомления об авторских правах. Примеры кода адаптированы; указание источника не означает одобрения со стороны SeaQL.

Для SQ-01–SQ-20 приведены реализации через публичный API typed-sql и SQL компилятора. SQ-10 воспроизводит оконный count коррелированным scalar subquery.

```rust
use sea_query::{Cond, Expr, Iden, JoinType, OnConflict, Order, PostgresQueryBuilder, Query, UnionType, WindowStatement};

#[derive(Iden)]
enum Users {
    Table,
    Id,
    Name,
    Country,
}

#[derive(Iden)]
enum Posts {
    Table,
    Id,
    UserId,
    Title,
}
```

## Общие descriptors typed-sql

```ocaml
open! Base
open Typed_sql
open Infix

module Users = struct
  type row

  let table : row Table.t = Table.v_exn "users"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let country_column = Column.v_exn table "country" Db_type.text
  let id row = Expr.column row id_column
  let name row = Expr.column row name_column
  let country row = Expr.column row country_column
end

module Posts = struct
  type row

  let table : row Table.t = Table.v_exn "posts"
  let id_column = Column.v_exn table "id" Db_type.int64
  let user_id_column = Column.v_exn table "user_id" Db_type.int64
  let title_column = Column.v_exn table "title" Db_type.text
  let id row = Expr.column row id_column
  let nullable_id row = Expr.nullable_column row id_column
  let user_id row = Expr.column row user_id_column
  let title row = Expr.column row title_column
  let nullable_title row = Expr.nullable_column row title_column
end
```

Для OCaml-примеров ниже SQL в блоках «SQL typed-sql» показывает результат компиляции для PostgreSQL.

### SQ-01. Фильтр и проекция

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [SelectStatement examples](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html).
- Проверяет: проекцию двух колонок и условие по стране.

```sql
SELECT users.id, users.name
FROM users
WHERE users.country = $1
```

```rust
let query = Query::select()
    .column((Users::Table, Users::Id))
    .column((Users::Table, Users::Name))
    .from(Users::Table)
    .and_where(Expr::col((Users::Table, Users::Country)).eq(country))
    .to_owned();

let (sql, values) = query.build(PostgresQueryBuilder);
```

#### OCaml (typed-sql)

```ocaml
let seaquery01 =
  Statement.query_many ~dialect:Dialect.portable (
    Query.(
      from Users.table
      |> where (fun user -> Users.country user =$ "US")
      |> select (fun user ->
        Projection.pair (Users.id user) (Users.name user))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql seaquery01);;
SELECT
  t0."id",
  t0."name"
FROM "users" AS t0
WHERE
  (t0."country" = $1)
```

### SQ-02. Несколько фильтров

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [WHERE conditions](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html).
- Проверяет: объединение условий через последовательные `and_where`.

```sql
SELECT users.id, users.name
FROM users
WHERE users.country = $1 AND users.name LIKE $2
```

```rust
let query = Query::select()
    .column((Users::Table, Users::Id))
    .column((Users::Table, Users::Name))
    .from(Users::Table)
    .and_where(Expr::col((Users::Table, Users::Country)).eq(country))
    .and_where(Expr::col((Users::Table, Users::Name)).like(name_pattern))
    .to_owned();

let (sql, values) = query.build(PostgresQueryBuilder);
```

#### OCaml (typed-sql)

```ocaml
let seaquery02 =
  Statement.query_many ~dialect:Dialect.portable (
    Query.(
      from Users.table
      |> where (fun user ->
        (Users.country user =$ "US") &&.
        (Users.name user =~$ "A%"))
      |> select (fun user ->
        Projection.pair (Users.id user) (Users.name user))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql seaquery02);;
SELECT
  t0."id",
  t0."name"
FROM "users" AS t0
WHERE
  (
    (t0."country" = $1)
    AND (t0."name" LIKE $2)
  )
```

### SQ-03. Сортировка и страница

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [order_by, limit, offset](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html).
- Проверяет: сортировку по ключу перед ограничением и смещением.

```sql
SELECT users.id, users.name
FROM users
ORDER BY users.id ASC
LIMIT 10 OFFSET 20
```

```rust
let query = Query::select()
    .column((Users::Table, Users::Id))
    .column((Users::Table, Users::Name))
    .from(Users::Table)
    .order_by((Users::Id, Order::Asc))
    .limit(10)
    .offset(20)
    .to_owned();

let (sql, values) = query.build(PostgresQueryBuilder);
```

#### OCaml (typed-sql)

```ocaml
let seaquery03 =
  Statement.query_many ~dialect:Dialect.portable (
    Query.(
      from Users.table
      |> order_by Users.id `Asc
      |> limit 10
      |> offset 20
      |> select (fun user ->
        Projection.pair (Users.id user) (Users.name user))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql seaquery03);;
SELECT
  t0."id",
  t0."name"
FROM "users" AS t0
ORDER BY
  t0."id" ASC
LIMIT 10
OFFSET 20
```

### SQ-04. INNER JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [join](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html#method.join).
- Проверяет: JOIN с явно заданным условием.

```sql
SELECT users.id, posts.title
FROM users
INNER JOIN posts ON users.id = posts.user_id
```

```rust
let query = Query::select()
    .column((Users::Table, Users::Id))
    .column((Posts::Table, Posts::Title))
    .from(Users::Table)
    .join(
        JoinType::InnerJoin,
        Posts::Table,
        Expr::col((Users::Table, Users::Id))
            .equals((Posts::Table, Posts::UserId)),
    )
    .to_owned();

let (sql, values) = query.build(PostgresQueryBuilder);
```

#### OCaml (typed-sql)

```ocaml
let seaquery04 =
  Statement.query_many ~dialect:Dialect.portable (
    Query.(
      from Users.table
      |> inner_join Posts.table ~on:(fun user post ->
        Users.id user =. Posts.user_id post)
      |> select (fun (user, post) ->
        Projection.pair (Users.id user) (Posts.title post))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql seaquery04);;
SELECT
  t0."id",
  t1."title"
FROM "users" AS t0
INNER JOIN "posts" AS t1
  ON (t0."id" = t1."user_id")
```

### SQ-05. LEFT JOIN с отсутствующей правой строкой

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [left_join](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html#method.left_join).
- Проверяет: сохранение пользователя без постов.

```sql
SELECT users.id, posts.title
FROM users
LEFT JOIN posts ON users.id = posts.user_id
```

```rust
let query = Query::select()
    .column((Users::Table, Users::Id))
    .column((Posts::Table, Posts::Title))
    .from(Users::Table)
    .left_join(
        Posts::Table,
        Expr::col((Users::Table, Users::Id))
            .equals((Posts::Table, Posts::UserId)),
    )
    .to_owned();

let (sql, values) = query.build(PostgresQueryBuilder);
```

#### OCaml (typed-sql)

Посты справа nullable из-за `LEFT JOIN`, поэтому проекция использует nullable-аксессор.

```ocaml
let seaquery05 =
  Statement.query_many ~dialect:Dialect.portable (
    Query.(
      from Users.table
      |> left_join Posts.table ~on:(fun user post ->
        Users.id user =. Posts.user_id post)
      |> select (fun (user, post) ->
        Projection.pair (Users.id user) (Posts.nullable_title post))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql seaquery05);;
SELECT
  t0."id",
  t1."title"
FROM "users" AS t0
LEFT JOIN "posts" AS t1
  ON (t0."id" = t1."user_id")
```

### SQ-06. Группировка с HAVING после JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [group_by_col](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html#method.group_by_col), [and_having](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html#method.and_having).
- Проверяет: подсчёт постов каждого пользователя из заданной страны, фильтр по агрегату и порядок по `users.id`.

```sql
SELECT users.id, COUNT(posts.id) AS post_count
FROM users
INNER JOIN posts ON users.id = posts.user_id
WHERE users.country = $1
GROUP BY users.id
HAVING COUNT(posts.id) >= $2
ORDER BY users.id ASC
```

```rust
let query = Query::select()
    .column((Users::Table, Users::Id))
    .expr_as(Expr::col((Posts::Table, Posts::Id)).count(), "post_count")
    .from(Users::Table)
    .inner_join(
        Posts::Table,
        Expr::col((Users::Table, Users::Id))
            .equals((Posts::Table, Posts::UserId)),
    )
    .and_where(Expr::col((Users::Table, Users::Country)).eq(country))
    .group_by_col((Users::Table, Users::Id))
    .and_having(Expr::col((Posts::Table, Posts::Id)).count().gte(min_posts))
    .order_by((Users::Table, Users::Id), Order::Asc)
    .to_owned();

let (sql, values) = query.build(PostgresQueryBuilder);
```

#### OCaml (typed-sql)

```ocaml
let seaquery06 =
  Statement.query_many ~dialect:Dialect.portable (
    Query.(
      from Users.table
      |> inner_join Posts.table ~on:(fun user post ->
        Users.id user =. Posts.user_id post)
      |> where (fun (user, _post) -> Users.country user =$ "US")
      |> group_by (fun (user, _post) -> Users.id user)
      |> having (fun (_user, post) ->
        Expr.count (Posts.id post) >=$ 2L)
      |> order_by (fun (user, _post) -> Users.id user) `Asc
      |> select (fun (user, post) ->
        Projection.pair (Users.id user) (Expr.count (Posts.id post)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql seaquery06);;
SELECT
  t0."id",
  COUNT(t1."id")
FROM "users" AS t0
INNER JOIN "posts" AS t1
  ON (t0."id" = t1."user_id")
WHERE
  (t0."country" = $1)
GROUP BY
  t0."id"
HAVING
  (COUNT(t1."id") >= $2)
ORDER BY
  t0."id" ASC
```

### SQ-07. Коррелированный EXISTS

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Expr::exists](https://docs.rs/sea-query/latest/sea_query/expr/type.SimpleExpr.html#method.exists).
- Проверяет: выбор пользователя только при наличии поста с подходящим заголовком; связь с внешним `users.id` находится внутри подзапроса.

```sql
SELECT users.id, users.name
FROM users
WHERE EXISTS (
  SELECT posts.id
  FROM posts
  WHERE posts.user_id = users.id AND posts.title LIKE $1
)
```

```rust
let matching_posts = Query::select()
    .column((Posts::Table, Posts::Id))
    .from(Posts::Table)
    .and_where(
        Expr::col((Posts::Table, Posts::UserId))
            .equals((Users::Table, Users::Id)),
    )
    .and_where(Expr::col((Posts::Table, Posts::Title)).like(title_pattern))
    .to_owned();

let query = Query::select()
    .column((Users::Table, Users::Id))
    .column((Users::Table, Users::Name))
    .from(Users::Table)
    .and_where(Expr::exists(matching_posts))
    .to_owned();

let (sql, values) = query.build(PostgresQueryBuilder);
```

#### OCaml (typed-sql)

Внутренний запрос захватывает ссылку на `user` из внешнего SELECT.

```ocaml
let seaquery07 =
  Statement.query_many ~dialect:Dialect.portable (
    Query.(
      from Users.table
      |> where (fun user ->
        Query.exists
          Query.(
            from Posts.table
            |> where (fun post ->
              (Posts.user_id post =. Users.id user)
              &&. (Posts.title post =~$ "SQL%"))))
      |> select (fun user ->
        Projection.pair (Users.id user) (Users.name user))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql seaquery07);;
SELECT
  t0."id",
  t0."name"
FROM "users" AS t0
WHERE
  (EXISTS (
    SELECT
      1
    FROM "posts" AS t1
    WHERE
      (
        (t1."user_id" = t0."id")
        AND (t1."title" LIKE $1)
      )
  ))
```

### SQ-08. JOIN с агрегирующим подзапросом

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [join_subquery](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html#method.join_subquery).
- Проверяет: агрегат в производной таблице, обращение к её alias и фильтр по вычисленному значению.

```sql
SELECT users.id, post_totals.post_count
FROM users
INNER JOIN (
  SELECT posts.user_id, COUNT(posts.id) AS post_count
  FROM posts
  GROUP BY posts.user_id
) AS post_totals ON users.id = post_totals.user_id
WHERE post_totals.post_count >= $1
```

```rust
let post_totals = Query::select()
    .column((Posts::Table, Posts::UserId))
    .expr_as(Expr::col((Posts::Table, Posts::Id)).count(), "post_count")
    .from(Posts::Table)
    .group_by_col((Posts::Table, Posts::UserId))
    .to_owned();

let query = Query::select()
    .column((Users::Table, Users::Id))
    .column(("post_totals", "post_count"))
    .from(Users::Table)
    .join_subquery(
        JoinType::InnerJoin,
        post_totals,
        "post_totals",
        Expr::col((Users::Table, Users::Id))
            .equals(("post_totals", "user_id")),
    )
    .and_where(Expr::col(("post_totals", "post_count")).gte(min_posts))
    .to_owned();

let (sql, values) = query.build(PostgresQueryBuilder);
```

#### OCaml (typed-sql)

`select_relation` сохраняет типизированные выражения агрегирующего подзапроса для внешнего JOIN.

```ocaml
let seaquery08_counts =
  Query.(
    from Posts.table
    |> group_by (fun post -> Posts.user_id post)
    |> select_relation (fun post ->
      Derived_table.Fields.pair
        (Posts.user_id post)
        Expr.count_all))

let seaquery08 =
  Statement.query_many ~dialect:Dialect.portable (
    Query.(
      from Users.table
      |> inner_join_relation seaquery08_counts ~on:(fun user (post_user_id, _count) ->
        Users.id user =. post_user_id)
      |> where (fun (_user, (_post_user_id, post_count)) -> post_count >=$ 2L)
      |> select (fun (user, (_post_user_id, post_count)) ->
        Projection.pair (Users.id user) post_count)))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql seaquery08);;
SELECT
  t0."id",
  t1."field_2"
FROM "users" AS t0
INNER JOIN (
  SELECT
    t2."user_id" AS "field_1",
    COUNT(*) AS "field_2"
  FROM "posts" AS t2
  GROUP BY
    t2."user_id"
) AS t1
  ON (t0."id" = t1."field_1")
WHERE
  (t1."field_2" >= $1)
```

### SQ-09. UNION ALL двух выборок

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [union](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html#method.union).
- Проверяет: одинаковую проекцию в обеих ветвях, порядок bind-параметров и сохранение повторов при `UNION ALL`.

```sql
SELECT users.id, users.name FROM users WHERE users.country = $1
UNION ALL
(SELECT users.id, users.name FROM users WHERE users.country = $2)
```

```rust
let second_country = Query::select()
    .column((Users::Table, Users::Id))
    .column((Users::Table, Users::Name))
    .from(Users::Table)
    .and_where(Expr::col((Users::Table, Users::Country)).eq(country_b))
    .to_owned();

let query = Query::select()
    .column((Users::Table, Users::Id))
    .column((Users::Table, Users::Name))
    .from(Users::Table)
    .and_where(Expr::col((Users::Table, Users::Country)).eq(country_a))
    .union(UnionType::All, second_country)
    .to_owned();

let (sql, values) = query.build(PostgresQueryBuilder);
```

#### OCaml (typed-sql)

```ocaml
let seaquery09 =
  Statement.query_many ~dialect:Dialect.portable (
    let by_country country =
      Query.(
        from Users.table
        |> where (fun user -> Users.country user =$ country)
        |> select (fun user ->
          Projection.pair (Users.id user) (Users.name user)))
    in
    Query.union_all (by_country "US") (by_country "CA"))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql seaquery09);;
SELECT *
FROM (
  SELECT
    t0."id",
    t0."name"
  FROM "users" AS t0
  WHERE
    (t0."country" = $1)
) AS s0
UNION ALL
SELECT *
FROM (
  SELECT
    t0."id",
    t0."name"
  FROM "users" AS t0
  WHERE
    (t0."country" = $2)
) AS s0
```

### SQ-10. Оконный подсчёт постов

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [expr_window_as](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html#method.expr_window_as).
- Проверяет: число постов пользователя рядом с каждой строкой без свёртывания строк в группы.
- Замечание: число строк в партиции получено коррелированным `COUNT(*)`; для каждой исходной строки сохраняется то же значение.

```sql
SELECT posts.id, posts.user_id,
       COUNT(posts.id) OVER (PARTITION BY posts.user_id) AS post_count
FROM posts
ORDER BY posts.user_id ASC, posts.id ASC
```

```rust
let query = Query::select()
    .column((Posts::Table, Posts::Id))
    .column((Posts::Table, Posts::UserId))
    .expr_window_as(
        Expr::col((Posts::Table, Posts::Id)).count(),
        WindowStatement::partition_by((Posts::Table, Posts::UserId)),
        "post_count",
    )
    .from(Posts::Table)
    .order_by((Posts::Table, Posts::UserId), Order::Asc)
    .order_by((Posts::Table, Posts::Id), Order::Asc)
    .to_owned();

let (sql, values) = query.build(PostgresQueryBuilder);
```

Оконный синтаксис не генерируется; тот же построчный результат строится коррелированным COUNT.

#### OCaml (typed-sql, коррелированный счётчик)

```ocaml
let seaquery10 =
  Statement.query_many ~dialect:Dialect.portable (
    Query.(
      from Posts.table
      |> order_by Posts.user_id `Asc
      |> order_by Posts.id `Asc
      |> select (fun post ->
        Projection.map3
          ~f:(fun id user_id count -> id, user_id, count)
          (Projection.expr (Posts.id post))
          (Projection.expr (Posts.user_id post))
          (Projection.expr
             (Expr.coalesce
                (Expr.scalar_subquery
                   (Query.(
                     from Posts.table
                     |> where (fun same_user -> Posts.user_id same_user =. Posts.user_id post)
                     |> select_scalar (fun _ -> Expr.count_all))))
                ~default:(Expr.constant Db_type.int64 0L))))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql seaquery10);;
SELECT
  t0."id",
  t0."user_id",
  COALESCE((
    SELECT
      COUNT(*)
    FROM "posts" AS t1
    WHERE
      (t1."user_id" = t0."user_id")
  ), $1)
FROM "posts" AS t0
ORDER BY
  t0."user_id" ASC,
  t0."id" ASC
```

### SQ-11. Пользователи без постов через NOT EXISTS

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [`Expr::not_exists`](https://docs.rs/sea-query/latest/sea_query/expr/type.SimpleExpr.html#method.not_exists).
- Проверяет: корреляцию по `user_id` и сохранение пользователей без постов без дублирования строк.

```sql
SELECT "users"."id", "users"."name"
FROM "users"
WHERE NOT EXISTS (
  SELECT "posts"."id" FROM "posts"
  WHERE "posts"."user_id" = "users"."id"
)
```

```rust
let posts_for_user = Query::select()
    .column((Posts::Table, Posts::Id))
    .from(Posts::Table)
    .and_where(Expr::col((Posts::Table, Posts::UserId))
        .equals((Users::Table, Users::Id)))
    .to_owned();
let query = Query::select()
    .columns([(Users::Table, Users::Id), (Users::Table, Users::Name)])
    .from(Users::Table)
    .and_where(Expr::not_exists(posts_for_user))
    .to_owned();
let (sql, values) = query.build(PostgresQueryBuilder);
```

#### OCaml (typed-sql)

```ocaml
let seaquery11 =
  Statement.query_many ~dialect:Dialect.portable (
    Query.(
      from Users.table
      |> where (fun user ->
        not_exists
          (from Posts.table
           |> where (fun post -> Posts.user_id post =. Users.id user)))
      |> select (fun user -> Projection.pair (Users.id user) (Users.name user))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql seaquery11);;
SELECT
  t0."id",
  t0."name"
FROM "users" AS t0
WHERE
  (NOT EXISTS (
    SELECT
      1
    FROM "posts" AS t1
    WHERE
      (t1."user_id" = t0."id")
  ))
```


### SQ-12. Последний пост каждого пользователя через DISTINCT ON

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: `DISTINCT ON` эмулирован через anti-`EXISTS` при уникальном `posts.id`.
- Источник: [`distinct_on`](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html#method.distinct_on).
- Проверяет: левый префикс `ORDER BY` совпадает с ключом `DISTINCT ON`, а `id DESC` выбирает последнюю строку в группе; PostgreSQL-специфично.

```sql
SELECT DISTINCT ON ("posts"."user_id")
       "posts"."user_id", "posts"."id", "posts"."title"
FROM "posts"
ORDER BY "posts"."user_id" ASC, "posts"."id" DESC
```

```rust
let query = Query::select()
    .distinct_on([(Posts::Table, Posts::UserId)])
    .columns([
        (Posts::Table, Posts::UserId),
        (Posts::Table, Posts::Id),
        (Posts::Table, Posts::Title),
    ])
    .from(Posts::Table)
    .order_by((Posts::Table, Posts::UserId), Order::Asc)
    .order_by((Posts::Table, Posts::Id), Order::Desc)
    .to_owned();
let (sql, values) = query.build(PostgresQueryBuilder);
```

#### OCaml (typed-sql)

`DISTINCT ON` заменён на anti-`EXISTS`; при уникальном `posts.id` выбирается пост пользователя с наибольшим ID.

```ocaml
let seaquery12 =
  Statement.query_many ~dialect:Dialect.portable (
    Query.(
      from Posts.table
      |> where (fun post ->
        not_exists
          (from Posts.table
           |> where (fun newer ->
             (Posts.user_id newer =. Posts.user_id post)
             &&. (Posts.id newer >. Posts.id post))))
      |> order_by Posts.user_id `Asc
      |> order_by Posts.id `Desc
      |> select (fun post ->
        Projection.map2
          ~f:(fun user_id (id, title) -> user_id, id, title)
          (Projection.expr (Posts.user_id post))
          (Projection.pair (Posts.id post) (Posts.title post)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql seaquery12);;
SELECT
  t0."user_id",
  t0."id",
  t0."title"
FROM "posts" AS t0
WHERE
  (NOT EXISTS (
    SELECT
      1
    FROM "posts" AS t1
    WHERE
      (
        (t1."user_id" = t0."user_id")
        AND (t1."id" > t0."id")
      )
  ))
ORDER BY
  t0."user_id" ASC,
  t0."id" DESC
```


### SQ-13. Вложенные группы условий AND и OR

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [`cond_where`](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html#method.cond_where).
- Проверяет: скобки вокруг альтернативных префиксов имени под общим условием страны и порядок bind-параметров.

```sql
SELECT "users"."id"
FROM "users"
WHERE "users"."country" = $1
  AND ("users"."name" LIKE $2 OR "users"."name" LIKE $3)
```

```rust
let query = Query::select()
    .column((Users::Table, Users::Id))
    .from(Users::Table)
    .cond_where(Cond::all()
        .add(Expr::col((Users::Table, Users::Country)).eq("USA"))
        .add(Cond::any()
            .add(Expr::col((Users::Table, Users::Name)).like("A%"))
            .add(Expr::col((Users::Table, Users::Name)).like("B%"))))
    .to_owned();
let (sql, values) = query.build(PostgresQueryBuilder);
```

#### OCaml (typed-sql)

```ocaml
let seaquery13 =
  Statement.query_many ~dialect:Dialect.portable (
    Query.(
      from Users.table
      |> where (fun user ->
        (Users.country user =$ "USA") &&.
        ((Users.name user =~$ "A%") ||. (Users.name user =~$ "B%")))
      |> select (fun user -> Projection.expr (Users.id user))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql seaquery13);;
SELECT
  t0."id"
FROM "users" AS t0
WHERE
  (
    (t0."country" = $1)
    AND (
      (t0."name" LIKE $2)
      OR (t0."name" LIKE $3)
    )
  )
```


### SQ-14. INSERT ON CONFLICT с обновлением заголовка

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [`OnConflict`](https://docs.rs/sea-query/latest/sea_query/query/struct.OnConflict.html).
- Проверяет: вставку нового поста и обновление только `title` из `EXCLUDED` при конфликте по `id`.

```sql
INSERT INTO "posts" ("id", "user_id", "title")
VALUES ($1, $2, $3)
ON CONFLICT ("id") DO UPDATE SET "title" = "excluded"."title"
```

```rust
let query = Query::insert()
    .into_table(Posts::Table)
    .columns([Posts::Id, Posts::UserId, Posts::Title])
    .values_panic([post_id.into(), user_id.into(), title.into()])
    .on_conflict(OnConflict::column(Posts::Id)
        .update_column(Posts::Title)
        .to_owned())
    .to_owned();
let (sql, values) = query.build(PostgresQueryBuilder);
```

#### OCaml (typed-sql)

```ocaml
let seaquery14 =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let open Statement.Parameters.Let_syntax in
    let+ id = params.expr Db_type.int64 ~get:(fun (id, _, _) -> id)
    and+ user_id = params.expr Db_type.int64 ~get:(fun (_, user_id, _) -> user_id)
    and+ title = params.expr Db_type.text ~get:(fun (_, _, title) -> title) in
    params.command (
    Insert.(
      into Posts.table
      |> set_expr Posts.id_column id
      |> set_expr Posts.user_id_column user_id
      |> set_expr Posts.title_column title
      |> on_conflict (Conflict_target.column Posts.id_column)
      |> do_update (fun ~existing:_ ~excluded ->
        Conflict_update.empty
        |> Conflict_update.set_expr Posts.title_column (Posts.title excluded))
      |> command)))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql seaquery14);;
INSERT INTO "posts" AS t0 (
  "id",
  "user_id",
  "title"
)
VALUES
  ($1, $2, $3)
ON CONFLICT (
  "id"
)
DO UPDATE
SET
  "title" = excluded."title"
```


### SQ-15. UPDATE с RETURNING изменённых ID

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [`UpdateStatement::returning_col`](https://docs.rs/sea-query/latest/sea_query/query/struct.UpdateStatement.html#method.returning_col).
- Проверяет: обновление всех постов пользователя одним оператором и возврат только реально изменённых идентификаторов.

```sql
UPDATE "posts" SET "title" = $1
WHERE "user_id" = $2
RETURNING "id"
```

```rust
let query = Query::update()
    .table(Posts::Table)
    .value(Posts::Title, new_title)
    .and_where(Expr::col(Posts::UserId).eq(user_id))
    .returning_col(Posts::Id)
    .to_owned();
let (sql, values) = query.build(PostgresQueryBuilder);
```

#### OCaml (typed-sql)

```ocaml
let seaquery15 =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let open Statement.Parameters.Let_syntax in
    let+ title = params.expr Db_type.text ~get:(fun (title, _) -> title)
    and+ user_id = params.expr Db_type.int64 ~get:(fun (_, user_id) -> user_id) in
    params.query_many (
    Update.(
      table Posts.table
      |> set_expr Posts.title_column title
      |> where (fun post -> Posts.user_id post =. user_id)
      |> returning (fun post -> Projection.expr (Posts.id post)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql seaquery15);;
UPDATE "posts"
SET
  "title" = $1
WHERE
  ("user_id" = $2)
RETURNING
  "id"
```


## Уведомление о лицензии

The MIT License (MIT)

Copyright (c) 2020 Tsang Hao Fung

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


### SQ-16. Подсчёт совпавших публикаций по пользователю

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [SeaQuery select and aggregate](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html).
- Проверяет: `LEFT JOIN`, фильтр внутри ON и count ненулевых ID.

```sql
SELECT users.id, COUNT(posts.id)
FROM users LEFT JOIN posts
  ON posts.user_id = users.id AND posts.title LIKE '%guide%'
GROUP BY users.id
```

#### OCaml (typed-sql)

```ocaml
let seaquery16 =
  Statement.query_many ~dialect:Dialect.portable (
    Query.(
      from Users.table
      |> left_join Posts.table ~on:(fun user post -> (Users.id user =. Posts.user_id post) &&. (Posts.title post =~$ "%guide%"))
      |> group_by (fun (user, _post) -> Users.id user)
      |> select (fun (user, post) -> Projection.pair (Users.id user) (Expr.count (Posts.nullable_id post)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql seaquery16);;
SELECT
  t0."id",
  COUNT(t1."id")
FROM "users" AS t0
LEFT JOIN "posts" AS t1
  ON (
    (t0."id" = t1."user_id")
    AND (t1."title" LIKE $1)
  )
GROUP BY
  t0."id"
```

### SQ-17. CTE с отфильтрованными пользователями

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [SeaQuery common table expressions](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html).
- Проверяет: фильтр в CTE и сортировку через его typed handle.

```sql
WITH selected_users AS (SELECT id, name FROM users WHERE id > 10)
SELECT id, name FROM selected_users ORDER BY id
```

#### OCaml (typed-sql)

```ocaml
let seaquery17_relation =
  Derived_table.create
    ~table:Users.table
    ~columns:(fun user -> Projection.pair (Users.id user) (Users.name user))
    Query.(from Users.table |> where (fun user -> Users.id user >$ 10L) |> select (fun user -> Projection.pair (Users.id user) (Users.name user)))
let seaquery17_cte = Cte.select seaquery17_relation
let seaquery17 =
  Statement.query_many ~dialect:Dialect.portable (
    Cte.with_result seaquery17_cte ~f:(fun selected ->
      Query.(from_cte selected |> order_by Users.id `Asc |> select (fun user -> Projection.pair (Users.id user) (Users.name user)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql seaquery17);;
WITH
  "c0" (
    "id",
    "name"
  ) AS (
    SELECT
      t0."id",
      t0."name"
    FROM "users" AS t0
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

### SQ-18. UPSERT с обновлением только при новом заголовке

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [SeaQuery OnConflict](https://docs.rs/sea-query/latest/sea_query/query/struct.OnConflict.html).
- Проверяет: conflict target и условие изменения конфликтующей строки.

```sql
INSERT INTO posts (id, user_id, title) VALUES (8, 2, 'Revised')
ON CONFLICT (id) DO UPDATE SET title = EXCLUDED.title
WHERE posts.title IS DISTINCT FROM EXCLUDED.title
```

#### OCaml (typed-sql)

```ocaml
let seaquery18 =
  Statement.command ~dialect:Dialect.portable (
    Insert.(
      into Posts.table
      |> set Posts.id_column 8L
      |> set Posts.user_id_column 2L
      |> set Posts.title_column "Revised"
      |> on_conflict (Conflict_target.column Posts.id_column)
      |> do_update (fun ~existing ~excluded ->
        Conflict_update.empty
        |> Conflict_update.set_expr Posts.title_column (Posts.title excluded)
        |> Conflict_update.where (Expr.is_distinct_from (Posts.title existing) (Posts.title excluded)))
      |> command))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql seaquery18);;
INSERT INTO "posts" AS t0 (
  "id",
  "user_id",
  "title"
)
VALUES
  ($1, $2, $3)
ON CONFLICT (
  "id"
)
DO UPDATE
SET
  "title" = excluded."title"
WHERE
  (t0."title" IS DISTINCT FROM excluded."title")
```

### SQ-19. UPDATE FROM с возвратом изменённой строки

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [SeaQuery update statement](https://docs.rs/sea-query/latest/sea_query/query/struct.UpdateStatement.html).
- Проверяет: update target, join predicate, фильтр пользователя и `RETURNING`.

```sql
UPDATE posts SET title = users.name
FROM users WHERE users.id = posts.user_id AND users.id = 2
RETURNING posts.id
```

#### OCaml (typed-sql)

```ocaml
let seaquery19 =
  Statement.query_many ~dialect:Dialect.portable (
    Update.(
      table Posts.table
      |> from Users.table ~f:(fun post user update ->
        update
        |> set_expr Posts.title_column (Users.name user)
        |> where (fun _ -> (Posts.user_id post =. Users.id user) &&. (Users.id user =$ 2L)))
      |> returning (fun post -> Projection.expr (Posts.id post))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql seaquery19);;
UPDATE "posts" AS t0
SET
  "title" = t1."name"
FROM "users" AS t1
WHERE
  (
    (t0."user_id" = t1."id")
    AND (t1."id" = $1)
  )
RETURNING
  t0."id"
```

### SQ-20. Пользователи без публикаций через EXCEPT

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [SeaQuery set operations](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html).
- Проверяет: set difference между всеми ID и ID авторов публикаций.

```sql
SELECT id FROM users EXCEPT SELECT user_id FROM posts
```

#### OCaml (typed-sql)

```ocaml
let seaquery20_users = Query.(from Users.table |> select (fun user -> Projection.expr (Users.id user)))
let seaquery20_posts = Query.(from Posts.table |> select (fun post -> Projection.expr (Posts.user_id post)))
let seaquery20 = Statement.query_many ~dialect:Dialect.portable (Query.except seaquery20_users seaquery20_posts)
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql seaquery20);;
SELECT *
FROM (
  SELECT
    t0."id"
  FROM "users" AS t0
) AS s0
EXCEPT
SELECT *
FROM (
  SELECT
    t0."user_id"
  FROM "posts" AS t0
) AS s0
```
