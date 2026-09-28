<!-- SPDX-License-Identifier: BSD-3-Clause -->

# Сценарии запросов из Esqueleto

**Желаемый таргет: 20 сценариев — 5 обычных и 15 сложных.** Сейчас заведены все 20 сценариев.

Источник — [документация `Database.Esqueleto.Experimental`](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html), версия Esqueleto 3.6.0.0. Примеры сокращены и адаптированы. Схема следует документации: `Person(name, age)` и `BlogPost(title, authorId)`; `age` nullable. SQL показывает существенную форму запросов.

Пакет Esqueleto распространяется по [BSD-3-Clause](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0). В конце файла приведено уведомление об авторских правах и лицензии. Это независимая подборка; указание источника не означает одобрения со стороны авторов Esqueleto.

Для EQ-01–EQ-18 и EQ-20 приведены реализации через публичный API typed-sql; EQ-19 требует блокировки строк, которых нет в публичном API. OCaml-блоки с реализациями typed-sql исполняются через MDX.

```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

import Data.Text (Text)
import Database.Esqueleto.Experimental
```

## Общие дескрипторы typed-sql

```ocaml
open! Base
open Typed_sql
open Infix

module Eq_person = struct
  type row

  let table : row Table.t = Table.v_exn "person"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let age_column = Column.v_exn table "age" (Db_type.option Db_type.int)
  let id row = Expr.column row id_column
  let name row = Expr.column row name_column
  let age row = Expr.column row age_column
end

module Eq_blog_post = struct
  type row

  let table : row Table.t = Table.v_exn "blog_post"
  let id_column = Column.v_exn table "id" Db_type.int64
  let title_column = Column.v_exn table "title" Db_type.text
  let author_id_column = Column.v_exn table "author_id" Db_type.int64
  let id row = Expr.column row id_column
  let title row = Expr.column row title_column
  let author_id row = Expr.column row author_id_column
  let nullable_title row = Expr.nullable_column row title_column
end

module Eq_post_counts = struct
  type row

  let table : row Table.t = Table.v_exn "post_counts"
  let author_id_column = Column.v_exn table "author_id" Db_type.int64
  let post_count_column = Column.v_exn table "post_count" Db_type.int64
  let author_id row = Expr.column row author_id_column
  let post_count row = Expr.column row post_count_column
end
```

### EQ-01. Фильтр и проекция

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Example 1: Simple select](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:select).
- Проверяет: фильтр по имени и проекцию идентификатора с именем.

```sql
SELECT id, name
FROM person
WHERE name = ?
```

```haskell
select $ do
  person <- from $ table @Person
  where_ (person ^. PersonName ==. val "John")
  pure (person ^. PersonId, person ^. PersonName)
```

#### OCaml (typed-sql)

```ocaml
let esqueleto01 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Eq_person.table
      |> where (fun person -> Eq_person.name person =$ "John")
      |> select (fun person ->
        Projection.pair (Eq_person.id person) (Eq_person.name person))))
```


#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql esqueleto01);;
SELECT
  t0."id",
  t0."name"
FROM "person" AS t0
WHERE
  (t0."name" = $1)
```

### EQ-02. Составной предикат с nullable-колонкой

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [basic expressions and predicates](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html).
- Проверяет: сравнение nullable-возраста и группировку `AND`/`OR`.

```sql
SELECT id, name
FROM person
WHERE age >= 18 AND (name = ? OR name = ?)
```

```haskell
select $ do
  person <- from $ table @Person
  where_ $
    person ^. PersonAge >=. just (val 18) &&.
    (person ^. PersonName ==. val "John" ||.
     person ^. PersonName ==. val "Jane")
  pure (person ^. PersonId, person ^. PersonName)
```

#### OCaml (typed-sql)

```ocaml
let esqueleto02 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Eq_person.table
      |> where (fun person ->
        (Eq_person.age person >=. Expr.constant (Db_type.option Db_type.int) (Some 18)) &&.
        ((Eq_person.name person =$ "John") ||. (Eq_person.name person =$ "Jane")))
      |> select (fun person ->
        Projection.pair (Eq_person.id person) (Eq_person.name person))))
```


#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql esqueleto02);;
SELECT
  t0."id",
  t0."name"
FROM "person" AS t0
WHERE
  (
    (t0."age" >= $1)
    AND (
      (t0."name" = $2)
      OR (t0."name" = $3)
    )
  )
```

### EQ-03. Сортировка и страница

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [ordering and pagination](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html).
- Проверяет: порядок по имени перед применением `LIMIT` и `OFFSET`.

```sql
SELECT id, name
FROM person
ORDER BY name ASC
LIMIT 10 OFFSET 20
```

```haskell
select $ do
  person <- from $ table @Person
  orderBy [asc (person ^. PersonName)]
  limit 10
  offset 20
  pure (person ^. PersonId, person ^. PersonName)
```

#### OCaml (typed-sql)

```ocaml
let esqueleto03 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Eq_person.table
      |> order_by Eq_person.name `Asc
      |> limit 10
      |> offset 20
      |> select (fun person ->
        Projection.pair (Eq_person.id person) (Eq_person.name person))))
```


#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql esqueleto03);;
SELECT
  t0."id",
  t0."name"
FROM "person" AS t0
ORDER BY
  t0."name" ASC
LIMIT 10
OFFSET 20
```

### EQ-04. INNER JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Example 2: Select with join](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:innerJoin).
- Проверяет: связь поста с автором.

```sql
SELECT person.id, blog_post.id
FROM person
INNER JOIN blog_post ON blog_post.author_id = person.id
```

```haskell
select $ do
  (person :& post) <-
    from $ table @Person
      `innerJoin` table @BlogPost
      `on` (\(person :& post) -> person ^. PersonId ==. post ^. BlogPostAuthorId)
  pure (person ^. PersonId, post ^. BlogPostId)
```

#### OCaml (typed-sql)

```ocaml
let esqueleto04 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Eq_person.table
      |> inner_join Eq_blog_post.table ~on:(fun person post ->
        Eq_person.id person =. Eq_blog_post.author_id post)
      |> select (fun (person, post) ->
        Projection.pair (Eq_person.id person) (Eq_blog_post.id post))))
```


#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql esqueleto04);;
SELECT
  t0."id",
  t1."id"
FROM "person" AS t0
INNER JOIN "blog_post" AS t1
  ON (t0."id" = t1."author_id")
```

### EQ-05. LEFT JOIN с отсутствующей правой строкой

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Example 2: Select with join](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:leftJoin).
- Проверяет: сохранение человека без постов и nullable-сторону результата.

```sql
SELECT person.id, blog_post.id
FROM person
LEFT JOIN blog_post ON blog_post.author_id = person.id
```

```haskell
select $ do
  (person :& post) <-
    from $ table @Person
      `leftJoin` table @BlogPost
      `on` (\(person :& post) -> just (person ^. PersonId) ==. post ?. BlogPostAuthorId)
  pure (person ^. PersonId, post ?. BlogPostId)
```

#### OCaml (typed-sql)

```ocaml
let esqueleto05 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Eq_person.table
      |> left_join Eq_blog_post.table ~on:(fun person post ->
        Eq_person.id person =. Eq_blog_post.author_id post)
      |> select (fun (person, post) ->
        Projection.pair
          (Eq_person.id person)
          (Expr.nullable_column post Eq_blog_post.id_column))))
```


#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql esqueleto05);;
SELECT
  t0."id",
  t1."id"
FROM "person" AS t0
LEFT JOIN "blog_post" AS t1
  ON (t0."id" = t1."author_id")
```

### EQ-06. Группировка авторов с HAVING

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [`groupBy`, `having` и `count`](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:having).
- Проверяет: подсчёт постов каждого автора и фильтр по агрегату после группировки.

```sql
SELECT author_id, COUNT(id)
FROM blog_post
GROUP BY author_id
HAVING COUNT(id) > ?
```

```haskell
select $ do
  post <- from $ table @BlogPost
  groupBy (post ^. BlogPostAuthorId)
  having (count (post ^. BlogPostId) >. val (2 :: Int))
  pure (post ^. BlogPostAuthorId, count (post ^. BlogPostId))
```

#### OCaml (typed-sql)

```ocaml
let esqueleto06 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Eq_blog_post.table
      |> group_by Eq_blog_post.author_id
      |> having (fun post -> Expr.count (Eq_blog_post.id post) >$ 2L)
      |> select (fun post ->
        Projection.pair
          (Eq_blog_post.author_id post)
          (Expr.count (Eq_blog_post.id post)))))
```


#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql esqueleto06);;
SELECT
  t0."author_id",
  COUNT(t0."id")
FROM "blog_post" AS t0
GROUP BY
  t0."author_id"
HAVING
  (COUNT(t0."id") > $1)
```

### EQ-07. Коррелированный EXISTS с фильтром постов

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [`exists`](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:exists).
- Проверяет: ссылку подзапроса на внешнего человека и наличие хотя бы одного подходящего поста.

```sql
SELECT person.id, person.name
FROM person
WHERE EXISTS (
  SELECT 1
  FROM blog_post
  WHERE blog_post.author_id = person.id
    AND blog_post.title LIKE ?
)
```

```haskell
select $ do
  person <- from $ table @Person
  where_ $ exists $ do
    post <- from $ table @BlogPost
    where_ $
      post ^. BlogPostAuthorId ==. person ^. PersonId &&.
      post ^. BlogPostTitle `like` val "SQL%"
    pure ()
  pure (person ^. PersonId, person ^. PersonName)
```

#### OCaml (typed-sql)

```ocaml
let esqueleto07 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Eq_person.table
      |> where (fun person ->
        exists
          (Query.from Eq_blog_post.table
           |> Query.where (fun post ->
             (Eq_blog_post.author_id post =. Eq_person.id person) &&.
             (Eq_blog_post.title post =~$ "SQL%"))))
      |> select (fun person ->
        Projection.pair (Eq_person.id person) (Eq_person.name person))))
```


#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql esqueleto07);;
SELECT
  t0."id",
  t0."name"
FROM "person" AS t0
WHERE
  (EXISTS (
    SELECT
      1
    FROM "blog_post" AS t1
    WHERE
      (
        (t1."author_id" = t0."id")
        AND (t1."title" LIKE $1)
      )
  ))
```

### EQ-08. Коррелированный подсчёт постов, включая ноль

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [`subSelectCount`](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:subSelectCount).
- Проверяет: скалярный агрегат по связанной таблице без исключения людей, у которых нет постов.

```sql
SELECT person.id,
       (SELECT COUNT(*)
        FROM blog_post
        WHERE blog_post.author_id = person.id) AS post_count
FROM person
```

```haskell
select $ do
  person <- from $ table @Person
  let postCount = subSelectCount $ do
        post <- from $ table @BlogPost
        where_ (post ^. BlogPostAuthorId ==. person ^. PersonId)
        pure ()
  pure (person ^. PersonId, postCount :: SqlExpr (Value Int))
```

#### OCaml (typed-sql)

`COUNT(*)` возвращает строку даже при отсутствии постов. `scalar_subquery` учитывает
в типе возможность пустого подзапроса, поэтому decoder преобразует `None` в `0L`.

```ocaml
let esqueleto08 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Eq_person.table
      |> select (fun person ->
        let post_count =
          Query.(
            from Eq_blog_post.table
            |> where (fun post -> Eq_blog_post.author_id post =. Eq_person.id person)
            |> select_scalar (fun _ -> Expr.count_all))
        in
        Projection.map2
          ~f:(fun person_id count -> person_id, Option.value count ~default:0L)
          (Projection.expr (Eq_person.id person))
          (Projection.expr (Expr.scalar_subquery post_count)))))
```


#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql esqueleto08);;
SELECT
  t0."id",
  (
    SELECT
      COUNT(*)
    FROM "blog_post" AS t1
    WHERE
      (t1."author_id" = t0."id")
  )
FROM "person" AS t0
```

### EQ-09. IN с подзапросом идентификаторов авторов

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [`subSelectList`](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:subSelectList).
- Проверяет: типизированное множество ключей из подзапроса и фильтр людей по нему.

```sql
SELECT person.id, person.name
FROM person
WHERE person.id IN (
  SELECT blog_post.author_id
  FROM blog_post
  WHERE blog_post.title LIKE ?
)
```

```haskell
select $ do
  person <- from $ table @Person
  where_ $ person ^. PersonId `in_` subSelectList (do
    post <- from $ table @BlogPost
    where_ (post ^. BlogPostTitle `like` val "SQL%")
    pure (post ^. BlogPostAuthorId))
  pure (person ^. PersonId, person ^. PersonName)
```

#### OCaml (typed-sql)

```ocaml
let esqueleto09 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Eq_person.table
      |> where (fun person ->
        in_subquery
          (Eq_person.id person)
          (Query.(
             from Eq_blog_post.table
             |> where (fun post -> Eq_blog_post.title post =~$ "SQL%")
             |> select_scalar Eq_blog_post.author_id)))
      |> select (fun person ->
        Projection.pair (Eq_person.id person) (Eq_person.name person))))
```


#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql esqueleto09);;
SELECT
  t0."id",
  t0."name"
FROM "person" AS t0
WHERE
  (t0."id" IN (
    SELECT
      t1."author_id"
    FROM "blog_post" AS t1
    WHERE
      (t1."title" LIKE $1)
  ))
```

### EQ-10. Агрегирующий подзапрос в FROM

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [`selectQuery`](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:selectQuery).
- Проверяет: повторное обращение к агрегату как к колонке производной таблицы.

```sql
SELECT post_counts.author_id, post_counts.post_count
FROM (
  SELECT author_id, COUNT(id) AS post_count
  FROM blog_post
  GROUP BY author_id
) AS post_counts
WHERE post_counts.post_count > ?
```

```haskell
select $ do
  (authorId, postCount) <- from $ selectQuery $ do
    post <- from $ table @BlogPost
    groupBy (post ^. BlogPostAuthorId)
    pure (post ^. BlogPostAuthorId, count (post ^. BlogPostId))
  where_ (postCount >. val (2 :: Int))
  pure (authorId, postCount)
```

#### OCaml (typed-sql)

```ocaml
let esqueleto10_counts =
  Query.(
    from Eq_blog_post.table
    |> group_by Eq_blog_post.author_id
    |> select_relation (fun post ->
      Derived_table.Fields.pair
        (Eq_blog_post.author_id post)
        (Expr.count (Eq_blog_post.id post))))

let esqueleto10 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from_relation esqueleto10_counts
      |> where (fun (_author_id, post_count) -> post_count >$ 2L)
      |> select (fun (author_id, post_count) ->
        Projection.pair author_id post_count)))
```


#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql esqueleto10);;
SELECT
  t0."field_1",
  t0."field_2"
FROM (
  SELECT
    t1."author_id" AS "field_1",
    COUNT(t1."id") AS "field_2"
  FROM "blog_post" AS t1
  GROUP BY
    t1."author_id"
) AS t0
WHERE
  (t0."field_2" > $1)
```

### EQ-11. UNION ALL с сохранением повторений

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [`unionAll_`](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:unionAll_).
- Проверяет: объединение двух однотипных выборок с сохранением человека, подходящего под оба фильтра, дважды.

```sql
SELECT name FROM person WHERE name LIKE ?
UNION ALL
SELECT name FROM person WHERE name LIKE ?
```

```haskell
select $ do
  name <- from $
    (do
      person <- from $ table @Person
      where_ (person ^. PersonName `like` val "A%")
      pure (person ^. PersonName))
    `unionAll_`
    (do
      person <- from $ table @Person
      where_ (person ^. PersonName `like` val "%a")
      pure (person ^. PersonName))
  pure name
```

#### OCaml (typed-sql)

```ocaml
let esqueleto11_by_name pattern =
  Query.(
    from Eq_person.table
    |> where (fun person -> Eq_person.name person =~$ pattern)
    |> select (fun person -> Projection.expr (Eq_person.name person)))

let esqueleto11 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.union_all (esqueleto11_by_name "A%") (esqueleto11_by_name "%a"))
```


#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql esqueleto11);;
SELECT *
FROM (
  SELECT
    t0."name"
  FROM "person" AS t0
  WHERE
    (t0."name" LIKE $1)
) AS s0
UNION ALL
SELECT *
FROM (
  SELECT
    t0."name"
  FROM "person" AS t0
  WHERE
    (t0."name" LIKE $2)
) AS s0
```

### EQ-12. INTERSECT для пересечения наборов ключей

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [`intersect_`](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:intersect_).
- Проверяет: пересечение взрослых людей с авторами постов по одному типу ключа и устранение дубликатов.

```sql
SELECT id FROM person WHERE age >= ?
INTERSECT
SELECT author_id FROM blog_post WHERE title LIKE ?
```

```haskell
select $ do
  personId <- from $
    (do
      person <- from $ table @Person
      where_ (person ^. PersonAge >=. just (val 18))
      pure (person ^. PersonId))
    `intersect_`
    (do
      post <- from $ table @BlogPost
      where_ (post ^. BlogPostTitle `like` val "SQL%")
      pure (post ^. BlogPostAuthorId))
  pure personId
```

#### OCaml (typed-sql)

```ocaml
let esqueleto12_adults =
  Query.(
    from Eq_person.table
    |> where (fun person ->
      Eq_person.age person >=. Expr.constant (Db_type.option Db_type.int) (Some 18))
    |> select (fun person -> Projection.expr (Eq_person.id person)))

let esqueleto12_sql_authors =
  Query.(
    from Eq_blog_post.table
    |> where (fun post -> Eq_blog_post.title post =~$ "SQL%")
    |> select (fun post -> Projection.expr (Eq_blog_post.author_id post)))

let esqueleto12 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.intersect esqueleto12_adults esqueleto12_sql_authors)
```


#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql esqueleto12);;
SELECT *
FROM (
  SELECT
    t0."id"
  FROM "person" AS t0
  WHERE
    (t0."age" >= $1)
) AS s0
INTERSECT
SELECT *
FROM (
  SELECT
    t0."author_id"
  FROM "blog_post" AS t0
  WHERE
    (t0."title" LIKE $2)
) AS s0
```

### EQ-13. EXCEPT для исключения авторов

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [`except_`](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:except_).
- Проверяет: разность множеств ключей и устранение повторений, возникающих у авторов нескольких постов.

```sql
SELECT id FROM person WHERE age >= ?
EXCEPT
SELECT author_id FROM blog_post WHERE title LIKE ?
```

```haskell
select $ do
  personId <- from $
    (do
      person <- from $ table @Person
      where_ (person ^. PersonAge >=. just (val 18))
      pure (person ^. PersonId))
    `except_`
    (do
      post <- from $ table @BlogPost
      where_ (post ^. BlogPostTitle `like` val "SQL%")
      pure (post ^. BlogPostAuthorId))
  pure personId
```

#### OCaml (typed-sql)

Используются обе выборки, объявленные в EQ-12; `except` устраняет дубликаты.

```ocaml
let esqueleto13 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.except esqueleto12_adults esqueleto12_sql_authors)
```


#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql esqueleto13);;
SELECT *
FROM (
  SELECT
    t0."id"
  FROM "person" AS t0
  WHERE
    (t0."age" >= $1)
) AS s0
EXCEPT
SELECT *
FROM (
  SELECT
    t0."author_id"
  FROM "blog_post" AS t0
  WHERE
    (t0."title" LIKE $2)
) AS s0
```

### EQ-14. Соединение с агрегирующим CTE

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [`with`](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:with).
- Проверяет: объявление именованного промежуточного запроса, соединение с исходной таблицей и фильтр по вычисленному столбцу.

```sql
WITH post_counts AS (
  SELECT author_id, COUNT(id) AS post_count
  FROM blog_post
  GROUP BY author_id
)
SELECT person.name, post_counts.post_count
FROM person
INNER JOIN post_counts ON post_counts.author_id = person.id
WHERE post_counts.post_count > ?
```

```haskell
select $ do
  postCounts <- with $ do
    post <- from $ table @BlogPost
    groupBy (post ^. BlogPostAuthorId)
    pure (post ^. BlogPostAuthorId, count (post ^. BlogPostId))
  (person :& (authorId, postCount)) <-
    from $ table @Person
      `innerJoin` postCounts
      `on` (\(person :& (authorId, _)) -> person ^. PersonId ==. authorId)
  where_ (postCount >. val (2 :: Int))
  pure (person ^. PersonName, postCount)
```

#### OCaml (typed-sql)

```ocaml
let esqueleto14_relation =
  Derived_table.create
    ~table:Eq_post_counts.table
    ~columns:(fun counts ->
      Projection.pair
        (Eq_post_counts.author_id counts)
        (Eq_post_counts.post_count counts))
    Query.(
      from Eq_blog_post.table
      |> group_by Eq_blog_post.author_id
      |> select (fun post ->
        Projection.pair
          (Eq_blog_post.author_id post)
          (Expr.count (Eq_blog_post.id post))))

let esqueleto14_cte = Cte.select esqueleto14_relation

let esqueleto14 =
  Statement.Portable.query_many_exn (fun _ ->
    Cte.with_result esqueleto14_cte ~f:(fun post_counts ->
      Query.(
        from Eq_person.table
        |> inner_join_cte post_counts ~on:(fun person counts ->
          Eq_person.id person =. Eq_post_counts.author_id counts)
        |> where (fun (_person, counts) -> Eq_post_counts.post_count counts >$ 2L)
        |> select (fun (person, counts) ->
          Projection.pair
            (Eq_person.name person)
            (Eq_post_counts.post_count counts)))))
```


#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql esqueleto14);;
WITH
  "c0" (
    "author_id",
    "post_count"
  ) AS (
    SELECT
      t0."author_id",
      COUNT(t0."id")
    FROM "blog_post" AS t0
    GROUP BY
      t0."author_id"
  )
SELECT
  t0."name",
  t1."post_count"
FROM "person" AS t0
INNER JOIN "c0" AS t1
  ON (t0."id" = t1."author_id")
WHERE
  (t1."post_count" > $1)
```

### EQ-15. CASE с nullable-возрастом

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [`case_`](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:case_).
- Проверяет: порядок ветвей `CASE`, отдельную обработку `NULL` и проекцию вычисленного значения.

```sql
SELECT id,
       CASE
         WHEN age IS NULL THEN ?
         WHEN age >= ? THEN ?
         ELSE ?
       END AS age_group
FROM person
```

```haskell
select $ do
  person <- from $ table @Person
  let age = person ^. PersonAge
      ageGroup = case_
        [ (isNothing age, val ("unknown" :: Text))
        , (age >=. just (val 18), val "adult")
        ]
        (val "minor")
  pure (person ^. PersonId, ageGroup)
```

#### OCaml (typed-sql)

```ocaml
let esqueleto15 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Eq_person.table
      |> select (fun person ->
        let age = Eq_person.age person in
        Projection.pair
          (Eq_person.id person)
          (Expr.case
             [ (Expr.is_null age, Expr.constant Db_type.text "unknown")
             ; ( age >=. Expr.constant (Db_type.option Db_type.int) (Some 18)
               , Expr.constant Db_type.text "adult" )
             ]
             ~else_:(Expr.constant Db_type.text "minor")))))
```


#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql esqueleto15);;
SELECT
  t0."id",
  (CASE
    WHEN (t0."age" IS NULL) THEN $1
    WHEN (t0."age" >= $2) THEN $3
    ELSE $4
  END)
FROM "person" AS t0
```

### EQ-16. DISTINCT имён авторов с постами

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [`distinct`](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:distinct), [JOIN](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:innerJoin).
- Проверяет: устранение повторений уже после соединения; одно имя может принадлежать нескольким авторам.

```sql
SELECT DISTINCT p.name
FROM person AS p
JOIN blog_post AS bp ON bp.author_id = p.id
```

```haskell
select $ distinct $ do
  (person :& post) <- from $
    table @Person
    `innerJoin` table @BlogPost
    `on` (\(p :& bp) -> p ^. PersonId ==. bp ^. BlogPostAuthorId)
  pure (person ^. PersonName)
```

#### OCaml (typed-sql)

```ocaml
let esqueleto16 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Eq_person.table
      |> inner_join Eq_blog_post.table ~on:(fun person post ->
        Eq_person.id person =. Eq_blog_post.author_id post)
      |> distinct
      |> select (fun (person, _) -> Projection.expr (Eq_person.name person))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql esqueleto16);;
SELECT DISTINCT
  t0."name"
FROM "person" AS t0
INNER JOIN "blog_post" AS t1
  ON (t0."id" = t1."author_id")
```


### EQ-17. Последний пост каждого автора через LEFT JOIN LATERAL

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [`leftJoinLateral`](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:leftJoinLateral).
- Проверяет: корреляцию подзапроса с автором, ограничение до одного поста и `NULL` для автора без постов.

```sql
SELECT p.id, latest.title
FROM person AS p
LEFT JOIN LATERAL (
  SELECT bp.title FROM blog_post AS bp
  WHERE bp.author_id = p.id
  ORDER BY bp.id DESC
  LIMIT 1
) AS latest ON TRUE
```

```haskell
select $ do
  (person :& latestTitle) <- from $
    table @Person
    `leftJoinLateral`
      ( \p -> do
          post <- from $ table @BlogPost
          where_ (post ^. BlogPostAuthorId ==. p ^. PersonId)
          orderBy [desc (post ^. BlogPostId)]
          limit 1
          pure (post ^. BlogPostTitle)
      , \_ -> val True
      )
  pure (person ^. PersonId, latestTitle)
```

#### OCaml (typed-sql)

`LEFT JOIN LATERAL` представлен коррелированным scalar subquery; `LIMIT 1` и сортировка сохраняют выбор последнего поста, а отсутствие постов даёт `NULL`.

```ocaml
let esqueleto17 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Eq_person.table
      |> select (fun person ->
        let latest_title =
          Query.(
            from Eq_blog_post.table
            |> where (fun post -> Eq_blog_post.author_id post =. Eq_person.id person)
            |> order_by Eq_blog_post.id `Desc
            |> limit 1
            |> select_scalar Eq_blog_post.title)
        in
        Projection.pair
          (Eq_person.id person)
          (Expr.scalar_subquery latest_title))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql esqueleto17);;
SELECT
  t0."id",
  (
    SELECT
      t1."title"
    FROM "blog_post" AS t1
    WHERE
      (t1."author_id" = t0."id")
    ORDER BY
      t1."id" DESC
    LIMIT 1
  )
FROM "person" AS t0
```


### EQ-18. FULL OUTER JOIN авторов и постов

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [`fullOuterJoin`](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:fullOuterJoin).
- Проверяет: nullable-поля обеих сторон и сохранение строк без совпадения, если такие есть; нужен PostgreSQL или другой поддерживающий `FULL JOIN` диалект.

```sql
SELECT p.name, bp.title
FROM person AS p
FULL OUTER JOIN blog_post AS bp ON p.id = bp.author_id
```

```haskell
select $ do
  (person :& post) <- from $
    table @Person
    `fullOuterJoin` table @BlogPost
    `on` (\(p :& bp) -> p ?. PersonId ==. bp ?. BlogPostAuthorId)
  pure (person ?. PersonName, post ?. BlogPostTitle)
```

#### OCaml (typed-sql)

`FULL OUTER JOIN` построен из двух `LEFT JOIN`: вторая ветвь добавляет только посты без автора.

```ocaml
let esqueleto18_people =
  Query.(
    from Eq_person.table
    |> left_join Eq_blog_post.table ~on:(fun person post ->
      Eq_person.id person =. Eq_blog_post.author_id post)
    |> select (fun (person, post) ->
      Projection.pair
        (Expr.to_nullable (Eq_person.name person))
        (Expr.nullable_column post Eq_blog_post.title_column)))

let esqueleto18_orphan_posts =
  Query.(
    from Eq_blog_post.table
    |> left_join Eq_person.table ~on:(fun post person ->
      Eq_person.id person =. Eq_blog_post.author_id post)
    |> where (fun (_post, person) ->
      Expr.is_null (Expr.nullable_column person Eq_person.id_column))
    |> select (fun (post, person) ->
      Projection.pair
        (Expr.nullable_column person Eq_person.name_column)
        (Expr.to_nullable (Eq_blog_post.title post))))

let esqueleto18 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.union_all esqueleto18_people esqueleto18_orphan_posts)
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql esqueleto18);;
SELECT *
FROM (
  SELECT
    t0."name",
    t1."title"
  FROM "person" AS t0
  LEFT JOIN "blog_post" AS t1
    ON (t0."id" = t1."author_id")
) AS s0
UNION ALL
SELECT *
FROM (
  SELECT
    t1."name",
    t0."title"
  FROM "blog_post" AS t0
  LEFT JOIN "person" AS t1
    ON (t1."id" = t0."author_id")
  WHERE
    (t1."id" IS NULL)
) AS s0
```


### EQ-19. Захват первых незаблокированных строк

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✗)
- Семантика: —
- Без доработок typed-sql: ✗
- Замечание: публичный API typed-sql пока не моделирует `FOR UPDATE SKIP LOCKED` и блокировки транзакций.
- Источник: [`locking` и `forUpdateSkipLocked`](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:forUpdateSkipLocked).
- Проверяет: порядок `ORDER BY`, `LIMIT` и `FOR UPDATE SKIP LOCKED` при конкурирующих транзакциях; сценарий рассчитан на PostgreSQL.

```sql
SELECT p.id
FROM person AS p
ORDER BY p.id ASC
LIMIT 5
FOR UPDATE SKIP LOCKED
```

```haskell
select $ do
  person <- from $ table @Person
  orderBy [asc (person ^. PersonId)]
  limit 5
  locking forUpdateSkipLocked
  pure (person ^. PersonId)
```

### EQ-20. Вложенное объединение с последующим исключением

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Set Operations](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:except_).
- Проверяет: скобки вокруг `UNION ALL` перед `EXCEPT`; исключение удаляет все совпадения, а итоговый `EXCEPT` убирает дубликаты.

```sql
(SELECT p.id FROM person AS p WHERE p.age >= 18
 UNION ALL
 SELECT p.id FROM person AS p WHERE p.age IS NULL)
EXCEPT
SELECT p.id FROM person AS p WHERE p.name = 'blocked'
```

```haskell
select $ from $
  ((do
      person <- from $ table @Person
      where_ (person ^. PersonAge >=. just (val (18 :: Int)))
      pure (person ^. PersonId))
   `unionAll_`
   (do
      person <- from $ table @Person
      where_ (isNothing (person ^. PersonAge))
      pure (person ^. PersonId)))
  `except_`
  (do
      person <- from $ table @Person
      where_ (person ^. PersonName ==. val ("blocked" :: Text))
      pure (person ^. PersonId))
```

#### OCaml (typed-sql)

```ocaml
let esqueleto20_adults =
  Query.(
    from Eq_person.table
    |> where (fun person ->
      Eq_person.age person >=. Expr.constant (Db_type.option Db_type.int) (Some 18))
    |> select (fun person -> Projection.expr (Eq_person.id person)))

let esqueleto20_unknown_age =
  Query.(
    from Eq_person.table
    |> where (fun person -> Expr.is_null (Eq_person.age person))
    |> select (fun person -> Projection.expr (Eq_person.id person)))

let esqueleto20_blocked =
  Query.(
    from Eq_person.table
    |> where (fun person -> Eq_person.name person =$ "blocked")
    |> select (fun person -> Projection.expr (Eq_person.id person)))

let esqueleto20 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.except
      (Query.union_all esqueleto20_adults esqueleto20_unknown_age)
      esqueleto20_blocked)
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql esqueleto20);;
SELECT *
FROM (
  SELECT *
  FROM (
    SELECT
      t0."id"
    FROM "person" AS t0
    WHERE
      (t0."age" >= $1)
  ) AS s0
  UNION ALL
  SELECT *
  FROM (
    SELECT
      t0."id"
    FROM "person" AS t0
    WHERE
      (t0."age" IS NULL)
  ) AS s0
) AS s0
EXCEPT
SELECT *
FROM (
  SELECT
    t0."id"
  FROM "person" AS t0
  WHERE
    (t0."name" = $2)
) AS s0
```


## Уведомление о лицензии

Copyright (c) 2012–2016 Felipe Almeida Lessa

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
