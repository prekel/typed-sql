<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Сценарии запросов из Diesel

**Желаемый таргет: 20 сценариев — 5 обычных и 15 сложных.** Сейчас заведены пять обычных и десять сложных сценариев; остаётся добавить ещё пять сложных.

Источники — [All About Selects](https://diesel.rs/guides/all-about-selects/), [Relations](https://diesel.rs/guides/relations/) и API Diesel 2.3. Примеры и SQL сокращены и адаптированы под схему `users(id, name)` и `posts(id, user_id, title)`. Для JOIN предполагается объявленная Diesel-связь `posts.user_id -> users.id`; оконные функции требуют Diesel 2.3 или новее.

Diesel распространяется по [MIT или Apache-2.0](https://github.com/diesel-rs/diesel#license). Здесь используется вариант MIT для уведомления об авторских правах. Примеры кода адаптированы; указание источника не означает одобрения со стороны авторов Diesel.

Для DI-01–DI-09 приведены реализации через публичный API typed-sql и SQL компилятора для PostgreSQL. Оконные выражения DI-10 пока не входят в публичный API. DI-11–DI-15 пока приведены без реализации на typed-sql.

```rust
use diesel::prelude::*;

diesel::table! {
    users (id) {
        id -> Integer,
        name -> Text,
    }
}

diesel::table! {
    posts (id) {
        id -> Integer,
        user_id -> Integer,
        title -> Text,
    }
}

diesel::joinable!(posts -> users (user_id));
diesel::allow_tables_to_appear_in_same_query!(users, posts);
```

## Общие descriptors typed-sql

```ocaml
open! Base
open Typed_sql
open Infix

module Users = struct
  type row

  let table : row Table.t = Table.v_exn "users"
  let id_column = Column.v_exn table "id" Db_type.int
  let name_column = Column.v_exn table "name" Db_type.text
  let id row = Expr.column row id_column
  let name row = Expr.column row name_column
end

module Posts = struct
  type row

  let table : row Table.t = Table.v_exn "posts"
  let id_column = Column.v_exn table "id" Db_type.int
  let user_id_column = Column.v_exn table "user_id" Db_type.int
  let title_column = Column.v_exn table "title" Db_type.text
  let id row = Expr.column row id_column
  let user_id row = Expr.column row user_id_column
  let title row = Expr.column row title_column
  let nullable_id row = Expr.nullable_column row id_column
end
```

### DI-01. Фильтр и проекция

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: параметр `name` заменён фиксированным значением `Sean`.
- Источник: [All About Selects: Query Building](https://diesel.rs/guides/all-about-selects/).
- Проверяет: выбор идентификатора и имени по bind-параметру.

```sql
SELECT id, name
FROM users
WHERE name = $1
```

```rust
let rows = users::table
    .filter(users::name.eq(name))
    .select((users::id, users::name))
    .load::<(i32, String)>(connection)?;
```

#### OCaml (typed-sql)

```ocaml
let diesel01 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Users.table
      |> where (fun user -> Users.name user =$ "Sean")
      |> select (fun user ->
        Projection.pair (Users.id user) (Users.name user))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql diesel01);;
SELECT
  t0."id",
  t0."name"
FROM "users" AS t0
WHERE
  (t0."name" = $1)
```

### DI-02. Несколько фильтров

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: `min_id` и `name_pattern` заменены фиксированными значениями.
- Источник: [All About Selects: Filtering](https://diesel.rs/guides/all-about-selects/).
- Проверяет: композицию фильтров через последовательные вызовы `filter`.

```sql
SELECT id, name
FROM users
WHERE id > $1 AND name LIKE $2
```

```rust
let rows = users::table
    .filter(users::id.gt(min_id))
    .filter(users::name.like(name_pattern))
    .select((users::id, users::name))
    .load::<(i32, String)>(connection)?;
```

#### OCaml (typed-sql)

```ocaml
let diesel02 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Users.table
      |> where (fun user ->
        (Users.id user >$ 1) &&. (Users.name user =~$ "A%"))
      |> select (fun user ->
        Projection.pair (Users.id user) (Users.name user))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql diesel02);;
SELECT
  t0."id",
  t0."name"
FROM "users" AS t0
WHERE
  (
    (t0."id" > $1)
    AND (t0."name" LIKE $2)
  )
```

### DI-03. Сортировка и страница

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: `page_size` и `page_offset` заменены фиксированными значениями `10` и `20`.
- Источник: [QueryDsl](https://docs.diesel.rs/master/diesel/query_dsl/trait.QueryDsl.html).
- Проверяет: сортировку до ограничения и смещения результата.

```sql
SELECT id, name
FROM users
ORDER BY id ASC
LIMIT $1 OFFSET $2
```

```rust
let rows = users::table
    .order(users::id.asc())
    .limit(page_size)
    .offset(page_offset)
    .select((users::id, users::name))
    .load::<(i32, String)>(connection)?;
```

#### OCaml (typed-sql)

Здесь размер страницы и смещение заменены литералами `10` и `20`.

```ocaml
let diesel03 =
  Statement.Portable.query_many_exn (fun _ ->
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
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql diesel03);;
SELECT
  t0."id",
  t0."name"
FROM "users" AS t0
ORDER BY
  t0."id" ASC
LIMIT 10
OFFSET 20
```

### DI-04. INNER JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Relations: inner joins](https://diesel.rs/guides/relations/).
- Проверяет: JOIN по объявленной внешней связи.

```sql
SELECT users.id, posts.title
FROM users
INNER JOIN posts ON posts.user_id = users.id
```

```rust
let rows = users::table
    .inner_join(posts::table)
    .select((users::id, posts::title))
    .load::<(i32, String)>(connection)?;
```

#### OCaml (typed-sql)

```ocaml
let diesel04 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Users.table
      |> inner_join Posts.table ~on:(fun user post ->
        Users.id user =. Posts.user_id post)
      |> select (fun (user, post) ->
        Projection.pair (Users.id user) (Posts.title post))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql diesel04);;
SELECT
  t0."id",
  t1."title"
FROM "users" AS t0
INNER JOIN "posts" AS t1
  ON (t0."id" = t1."user_id")
```

### DI-05. LEFT JOIN с отсутствующей правой строкой

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Relations: left joins](https://diesel.rs/guides/relations/).
- Проверяет: сохранение пользователя без постов и nullable-колонку справа.

```sql
SELECT users.id, posts.id
FROM users
LEFT JOIN posts ON posts.user_id = users.id
```

```rust
let rows = users::table
    .left_join(posts::table)
    .select((users::id, posts::id.nullable()))
    .load::<(i32, Option<i32>)>(connection)?;
```

#### OCaml (typed-sql)

После `LEFT JOIN` идентификатор поста может быть `NULL`, поэтому в проекции используется nullable-аксессор.

```ocaml
let diesel05 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Users.table
      |> left_join Posts.table ~on:(fun user post ->
        Users.id user =. Posts.user_id post)
      |> select (fun (user, post) ->
        Projection.pair (Users.id user) (Posts.nullable_id post))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql diesel05);;
SELECT
  t0."id",
  t1."id"
FROM "users" AS t0
LEFT JOIN "posts" AS t1
  ON (t0."id" = t1."user_id")
```

### DI-06. Группировка с HAVING

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: `min_posts` заменён фиксированным значением `1`.
- Источник: [QueryDsl: group_by и having](https://docs.diesel.rs/master/diesel/query_dsl/trait.QueryDsl.html).
- Проверяет: группировку постов по пользователю и фильтрацию групп по агрегату.

```sql
SELECT users.id, COUNT(posts.id)
FROM users
INNER JOIN posts ON posts.user_id = users.id
GROUP BY users.id
HAVING COUNT(posts.id) > $1
```

```rust
let rows = users::table
    .inner_join(posts::table)
    .group_by(users::id)
    .having(diesel::dsl::count(posts::id).gt(min_posts))
    .select((users::id, diesel::dsl::count(posts::id)))
    .load::<(i32, i64)>(connection)?;
```

#### OCaml (typed-sql)

```ocaml
let diesel06 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Users.table
      |> inner_join Posts.table ~on:(fun user post ->
        Users.id user =. Posts.user_id post)
      |> group_by (fun (user, _post) -> Users.id user)
      |> having (fun (_user, post) -> Expr.count (Posts.id post) >$ 1L)
      |> select (fun (user, post) ->
        Projection.pair (Users.id user) (Expr.count (Posts.id post)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql diesel06);;
SELECT
  t0."id",
  COUNT(t1."id")
FROM "users" AS t0
INNER JOIN "posts" AS t1
  ON (t0."id" = t1."user_id")
GROUP BY
  t0."id"
HAVING
  (COUNT(t1."id") > $1)
```

### DI-07. Коррелированный EXISTS

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: `title_pattern` заменён фиксированным шаблоном `Rust%`.
- Источник: [diesel::dsl::exists](https://docs.diesel.rs/master/diesel/dsl/fn.exists.html).
- Проверяет: фильтр по наличию связанного поста без размножения строк пользователя.

```sql
SELECT users.id, users.name
FROM users
WHERE EXISTS (
  SELECT 1
  FROM posts
  WHERE posts.user_id = users.id AND posts.title LIKE $1
)
```

```rust
let rows = users::table
    .filter(diesel::dsl::exists(
        posts::table
            .filter(posts::user_id.eq(users::id))
            .filter(posts::title.like(title_pattern)),
    ))
    .select((users::id, users::name))
    .load::<(i32, String)>(connection)?;
```

#### OCaml (typed-sql)

```ocaml
let diesel07 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Users.table
      |> where (fun user ->
        Query.exists
          Query.(
            from Posts.table
            |> where (fun post ->
              (Posts.user_id post =. Users.id user)
              &&. (Posts.title post =~$ "Rust%"))))
      |> select (fun user ->
        Projection.pair (Users.id user) (Users.name user))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql diesel07);;
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

### DI-08. IN с подзапросом

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: `title_pattern` заменён фиксированным шаблоном `Rust%`.
- Источник: [ExpressionMethods: eq_any](https://docs.diesel.rs/master/diesel/expression_methods/trait.ExpressionMethods.html#method.eq_any).
- Проверяет: сравнение типа результата внешнего столбца с типом единственной колонки подзапроса.

```sql
SELECT users.id, users.name
FROM users
WHERE users.id = ANY (
  SELECT posts.user_id
  FROM posts
  WHERE posts.title LIKE $1
)
```

```rust
let post_user_ids = posts::table
    .filter(posts::title.like(title_pattern))
    .select(posts::user_id);

let rows = users::table
    .filter(users::id.eq_any(post_user_ids))
    .select((users::id, users::name))
    .load::<(i32, String)>(connection)?;
```

#### OCaml (typed-sql)

```ocaml
let diesel08 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Users.table
      |> where (fun user ->
        let post_user_ids =
          Query.(
            from Posts.table
            |> where (fun post -> Posts.title post =~$ "Rust%")
            |> select_scalar Posts.user_id)
        in
        Query.in_subquery (Users.id user) post_user_ids)
      |> select (fun user ->
        Projection.pair (Users.id user) (Users.name user))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql diesel08);;
SELECT
  t0."id",
  t0."name"
FROM "users" AS t0
WHERE
  (t0."id" IN (
    SELECT
      t1."user_id"
    FROM "posts" AS t1
    WHERE
      (t1."title" LIKE $1)
  ))
```

### DI-09. UNION ALL

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: `owner_id` и `title_pattern` заменены фиксированными значениями.
- Источник: [CombineDsl: union_all](https://docs.diesel.rs/2.3.x/diesel/query_dsl/trait.CombineDsl.html).
- Проверяет: одинаковый SQL-тип проекций и сохранение повторяющихся строк.

```sql
SELECT posts.title
FROM posts
WHERE posts.user_id = $1
UNION ALL
SELECT posts.title
FROM posts
WHERE posts.title LIKE $2
```

```rust
let by_owner = posts::table
    .filter(posts::user_id.eq(owner_id))
    .select(posts::title);

let by_title = posts::table
    .filter(posts::title.like(title_pattern))
    .select(posts::title);

let rows = by_owner
    .union_all(by_title)
    .load::<String>(connection)?;
```

#### OCaml (typed-sql)

```ocaml
let diesel09 =
  Statement.Portable.query_many_exn (fun _ ->
    let by_owner =
      Query.(
        from Posts.table
        |> where (fun post -> Posts.user_id post =$ 7)
        |> select (fun post -> Projection.expr (Posts.title post)))
    in
    let by_title =
      Query.(
        from Posts.table
        |> where (fun post -> Posts.title post =~$ "Rust%")
        |> select (fun post -> Projection.expr (Posts.title post)))
    in
    Query.union_all by_owner by_title)
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql diesel09);;
SELECT *
FROM (
  SELECT
    t0."title"
  FROM "posts" AS t0
  WHERE
    (t0."user_id" = $1)
) AS s0
UNION ALL
SELECT *
FROM (
  SELECT
    t0."title"
  FROM "posts" AS t0
  WHERE
    (t0."title" LIKE $2)
) AS s0
```

### DI-10. Оконный подсчёт постов

- OCaml-пример: ✗
- Реализуемость: ✗
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [Diesel 2.3: window functions](https://diesel.rs/news/2_3_0_release) и [WindowExpressionMethods](https://docs.diesel.rs/master/diesel/expression_methods/trait.WindowExpressionMethods.html).
- Проверяет: число постов каждого пользователя рядом с каждой строкой без схлопывания результата в группы.

```sql
SELECT posts.id, posts.user_id,
       COUNT(posts.id) OVER (PARTITION BY posts.user_id)
FROM posts
ORDER BY posts.user_id ASC, posts.id ASC
```

```rust
let rows = posts::table
    .select((
        posts::id,
        posts::user_id,
        diesel::dsl::count(posts::id).partition_by(posts::user_id),
    ))
    .order(posts::user_id.asc())
    .then_order_by(posts::id.asc())
    .load::<(i32, i32, i64)>(connection)?;
```

Оконные выражения `OVER (PARTITION BY ...)` отсутствуют в публичном API и semantic AST typed-sql, поэтому DI-10 нельзя выразить без расширения DSL.

### DI-11. Уникальные авторы постов с заданным префиксом

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [All About Selects](https://diesel.rs/guides/all-about-selects/).
- Проверяет: `DISTINCT` применяется к `user_id` после фильтра по заголовку; несколько подходящих постов одного пользователя дают одну строку.

```sql
SELECT DISTINCT posts.user_id
FROM posts
WHERE posts.title LIKE $1
ORDER BY posts.user_id ASC
```

```rust
let user_ids = posts::table
    .filter(posts::title.like(title_pattern))
    .select(posts::user_id)
    .distinct()
    .order(posts::user_id.asc())
    .load::<i32>(connection)?;
```

### DI-12. Динамические фильтры в boxed SELECT

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [Composing Applications with Diesel](https://diesel.rs/guides/composing-applications/).
- Проверяет: два независимых необязательных предиката меняют форму SQL; значения остаются параметрами, а сортировка задаёт устойчивый порядок.

```sql
SELECT posts.id, posts.title
FROM posts
WHERE posts.title LIKE $1 AND posts.id >= $2
ORDER BY posts.id ASC
-- При None для обоих параметров WHERE отсутствует.
```

```rust
let mut query = posts::table
    .select((posts::id, posts::title))
    .into_boxed::<diesel::pg::Pg>();
if let Some(pattern) = title_pattern {
    query = query.filter(posts::title.like(pattern));
}
if let Some(first_id) = min_id {
    query = query.filter(posts::id.ge(first_id));
}
let rows = query
    .order(posts::id.asc())
    .load::<(i32, String)>(connection)?;
```

### DI-13. UPSERT с новым заголовком из EXCLUDED

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [Diesel `on_conflict` и `excluded`](https://docs.diesel.rs/main/diesel/helper_types/type.OnConflict.html).
- Проверяет: вставку нового поста и обновление только заголовка при конфликте `id`; возвращается итоговая строка.

```sql
INSERT INTO posts (id, user_id, title)
VALUES ($1, $2, $3)
ON CONFLICT (id) DO UPDATE SET title = EXCLUDED.title
RETURNING id, title
```

```rust
let saved = diesel::insert_into(posts::table)
    .values((
        posts::id.eq(post_id),
        posts::user_id.eq(user_id),
        posts::title.eq(new_title),
    ))
    .on_conflict(posts::id)
    .do_update()
    .set(posts::title.eq(diesel::upsert::excluded(posts::title)))
    .returning((posts::id, posts::title))
    .get_result::<(i32, String)>(connection)?;
```

### DI-14. Массовый UPDATE с RETURNING

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [All About Updates](https://diesel.rs/guides/all-about-updates/).
- Проверяет: обновление всех постов одного пользователя одним оператором и получение только изменённых строк.

```sql
UPDATE posts SET title = $1
WHERE user_id = $2
RETURNING id, title
```

```rust
let changed = diesel::update(posts::table.filter(posts::user_id.eq(user_id)))
    .set(posts::title.eq(new_title))
    .returning((posts::id, posts::title))
    .get_results::<(i32, String)>(connection)?;
```

### DI-15. Удаление черновиков с возвратом идентификаторов

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [Diesel delete DSL](https://docs.diesel.rs/main/diesel/fn.delete.html), [RETURNING](https://diesel.rs/guides/all-about-updates/).
- Проверяет: оба условия удаления, отсутствие затронутых строк при пустом результате и `RETURNING` только удалённых идентификаторов.

```sql
DELETE FROM posts
WHERE user_id = $1 AND title LIKE $2
RETURNING id
```

```rust
let removed_ids = diesel::delete(
    posts::table
        .filter(posts::user_id.eq(user_id))
        .filter(posts::title.like("Draft%")),
)
.returning(posts::id)
.get_results::<i32>(connection)?;
```

## Уведомление о лицензии

The MIT License (MIT)

2015-2021 Sean Griffin, 2018-2021 Diesel Core Team

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
