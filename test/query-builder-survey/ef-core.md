# Сценарии запросов из EF Core

## Уведомление о лицензии примеров кода

The MIT License (MIT)

Copyright (c) Microsoft Corporation

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial
portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


50 сценариев по [документации EF Core](https://learn.microsoft.com/en-us/ef/core/) (доступ 28.09.2026). LINQ и SQL сокращены и адаптированы. SQL показывает существенную форму перевода, а не точный лог конкретной версии провайдера. Квадратные скобки и `@parameter` относятся к SQL Server; EF-10 использует синтаксис PostgreSQL, как в источнике. Условия переноса зависят от версии EF Core и провайдера, поэтому при дальнейшем сравнении нужно фиксировать оба.

**Желаемый таргет: 50–70 сценариев.**

Текст документации Microsoft / .NET team распространяется по [CC BY 4.0](https://github.com/dotnet/EntityFramework.Docs/blob/main/LICENSE), а [примеры кода — по MIT](https://github.com/dotnet/EntityFramework.Docs/blob/main/LICENSE-CODE), © Microsoft Corporation. Здесь примеры сокращены, проекции упрощены и добавлены критерии проверки. Уведомление MIT приведено в начале файла. Ссылки в каждой карточке ведут к разделу с контекстом.

Используются модели примеров `Blog`, `Post`, `Contributor` и `Book`. Карточки взяты из разных разделов документации; одноимённые модели не образуют единую схему. Для outer join и загрузки коллекций нужна фикстура с пустой коллекцией. Для клиентских операций проверять и SQL, и итоговый результат.

Для сценариев с OCaml-примером ✓ приведены typed-sql реализации и SQL компилятора. Для карточек с ✗ указано ограничение публичного API. EF-27 реализован через коррелированный счётчик строк перед каждой публикацией. В блоках «SQL typed-sql» первая строка запускает компилятор, остальные строки — его вывод. Запустить проверку можно командой `opam exec -- dune runtest test/query-builder-survey`.

Статусы в карточках: `✓` — подтверждено; `✗` — условие не выполнено; `—` — не оценивалось. «Семантика» учитывает входные параметры, результат, `NULL` и заданный порядок относительно серверного запроса в карточке; клиентская сборка объектов EF Core сюда не входит. «Без доработок» относится к публичному API typed-sql, а не к необходимости улучшить пример. Реализуемость оценивается после попытки написать OCaml-код.

## Общие дескрипторы

Эти descriptors используются во всех typed-sql примерах этого файла.

```ocaml
open! Base
open Typed_sql
open Infix

module Blog = struct
  type row

  let table : row Table.t = Table.v_exn "Blogs"
  let id_column = Column.v_exn table "BlogId" Db_type.int64
  let url_column = Column.v_exn table "Url" Db_type.text
  let nullable_url_column = Column.nullable_v_exn table "NullableUrl" Db_type.text
  let rating_column = Column.v_exn table "Rating" Db_type.int
  let is_deleted_column = Column.v_exn table "IsDeleted" Db_type.bool
  let id row = Expr.column row id_column
  let url row = Expr.column row url_column
  let nullable_url row = Expr.column row nullable_url_column
  let rating row = Expr.column row rating_column
  let is_deleted row = Expr.column row is_deleted_column
end

module Post = struct
  type row

  let table : row Table.t = Table.v_exn "Posts"
  let id_column = Column.v_exn table "PostId" Db_type.int64
  let blog_id_column = Column.v_exn table "BlogId" Db_type.int64
  let date_column = Column.v_exn table "Date" Db_type.timestamp
  let title_column = Column.v_exn table "Title" Db_type.text
  let rating_column = Column.v_exn table "Rating" Db_type.int
  let author_id_column = Column.v_exn table "AuthorId" Db_type.int64
  let optional_rating_column = Column.nullable_v_exn table "OptionalRating" Db_type.int
  let id row = Expr.column row id_column
  let blog_id row = Expr.column row blog_id_column
  let date row = Expr.column row date_column
  let title row = Expr.column row title_column
  let rating row = Expr.column row rating_column
  let author_id row = Expr.column row author_id_column
  let nullable_author_id row = Expr.nullable_column row author_id_column
  let optional_rating row = Expr.column row optional_rating_column
  let nullable_id row = Expr.nullable_column row id_column
end

module Author = struct
  type row

  let table : row Table.t = Table.v_exn "Authors"
  let id_column = Column.v_exn table "AuthorId" Db_type.int64
  let name_column = Column.v_exn table "Name" Db_type.text
  let id row = Expr.column row id_column
  let nullable_id row = Expr.nullable_column row id_column
  let name row = Expr.column row name_column
end

module Contributor = struct
  type row

  let table : row Table.t = Table.v_exn "Contributors"
  let id_column = Column.v_exn table "Id" Db_type.int64
  let blog_id_column = Column.v_exn table "BlogId" Db_type.int64
  let id row = Expr.column row id_column
  let blog_id row = Expr.column row blog_id_column
  let nullable_id row = Expr.nullable_column row id_column
end

module Book = struct
  type row

  let table : row Table.t = Table.v_exn "Books"
  let id_column = Column.v_exn table "Id" Db_type.int64
  let price_column = Column.v_exn table "Price" Db_type.int
  let author_id_column = Column.v_exn table "AuthorId" Db_type.int64
  let id row = Expr.column row id_column
  let price row = Expr.column row price_column
  let author_id row = Expr.column row author_id_column
end
```

### EF-01. Страница через OFFSET

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: `skip` и `take` передаются через валидируемые runtime input.
- Источник: [offset pagination](https://learn.microsoft.com/en-us/ef/core/querying/pagination#offset-pagination).
- Проверяет: порядок и границы страницы.

```sql
SELECT [p].[PostId] FROM [Posts] AS [p]
ORDER BY [p].[PostId]
OFFSET @skip ROWS FETCH NEXT @take ROWS ONLY
```

```csharp
var page = await context.Posts
    .OrderBy(p => p.PostId)
    .Skip(skip)
    .Take(take)
    .Select(p => p.PostId)
    .ToListAsync();
```

#### OCaml (typed-sql)

typed-sql рендерит portable PostgreSQL SQL; значения страницы остаются runtime input.

```ocaml
# let ef01 =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let open Parameters.Let_syntax in
    let+ skip = params.non_negative_int ~name:"skip" ~get:(fun (skip, _) -> skip)
    and+ take = params.non_negative_int ~name:"take" ~get:(fun (_, take) -> take) in
    params.query_many
      Query.(
        from Post.table
        |> order_by Post.id `Asc
        |> Query.limit_param take
        |> Query.offset_param skip
        |> select (fun post -> Projection.expr (Post.id post))))
val ef01 : (int * int, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ~input:(20, 10) ef01);;
SELECT
  t0."PostId"
FROM "Posts" AS t0
ORDER BY
  t0."PostId" ASC
LIMIT $1
OFFSET $2
```

### EF-02. Keyset по двум колонкам

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: `lastDate`, `lastId` и `take` передаются через runtime input.
- Источник: [multiple pagination keys](https://learn.microsoft.com/en-us/ef/core/querying/pagination#multiple-pagination-keys).
- Проверяет: лексикографический фильтр с составным порядком и дублирующимися датами.

```sql
SELECT [p].[PostId], [p].[Date] FROM [Posts] AS [p]
WHERE [p].[Date] > @lastDate
   OR ([p].[Date] = @lastDate AND [p].[PostId] > @lastId)
ORDER BY [p].[Date], [p].[PostId]
OFFSET 0 ROWS FETCH NEXT @take ROWS ONLY
```

```csharp
var page = await context.Posts
    .OrderBy(p => p.Date)
    .ThenBy(p => p.PostId)
    .Where(p => p.Date > lastDate ||
                (p.Date == lastDate && p.PostId > lastId))
    .Take(take)
    .Select(p => new { p.PostId, p.Date })
    .ToListAsync();
```

#### OCaml (typed-sql)

Порядок по дате и ключу задаёт лексикографическое условие для следующей страницы.

```ocaml
let last_date = Ptime.of_date_time ((2020, 1, 1), ((0, 0, 0), 0)) |> Option.value_exn
```

```ocaml
# let ef02 =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let open Parameters.Let_syntax in
    let+ last_date =
      params.expr Db_type.timestamp ~get:(fun (last_date, _, _) -> last_date)
    and+ last_id = params.expr Db_type.int64 ~get:(fun (_, last_id, _) -> last_id)
    and+ take = params.non_negative_int ~name:"take" ~get:(fun (_, _, take) -> take) in
    params.query_many
      Query.(
        from Post.table
        |> where (fun post ->
          Post.date post
          >. last_date
          ||. (Post.date post =. last_date &&. (Post.id post >. last_id)))
        |> order_by Post.date `Asc
        |> order_by Post.id `Asc
        |> Query.limit_param take
        |> select (fun post ->
          let open Projection.Let_syntax in
          let+ projected_left = Projection.expr (Post.id post)
          and+ projected_right = Projection.expr (Post.date post) in
          projected_left, projected_right)))
val ef02 :
  (Ptime.t * int64 * int, (int64 * Ptime.t) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Stdlib.print_endline
    (Statement.sql_exn ~dialect:Postgresql ~input:(last_date, 55L, 10) ef02);;
SELECT
  t0."PostId",
  t0."Date"
FROM "Posts" AS t0
WHERE
  (
    (t0."Date" > $1)
    OR (
      (t0."Date" = $1)
      AND (t0."PostId" > $2)
    )
  )
ORDER BY
  t0."Date" ASC,
  t0."PostId" ASC
LIMIT $3
```

### EF-03. INNER JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Join](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators#join).
- Проверяет: соединение по ключу и число результирующих строк.

```sql
SELECT [b].[BlogId], [p].[PostId]
FROM [Blogs] AS [b]
INNER JOIN [Posts] AS [p] ON [b].[BlogId] = [p].[BlogId]
```

```csharp
var query =
    from b in context.Blogs
    join p in context.Posts on b.BlogId equals p.BlogId
    select new { b.BlogId, p.PostId };
```

#### OCaml (typed-sql)

Соединение строится по внешнему ключу BlogId.

```ocaml
# let ef03 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> inner_join Post.table ~on:(fun blog post -> Blog.id blog =. Post.blog_id post)
      |> select (fun (blog, post) ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Blog.id blog)
        and+ projected_right = Projection.expr (Post.id post) in
        projected_left, projected_right))
val ef03 : (unit, (int64 * int64) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef03);;
SELECT
  t0."BlogId",
  t1."PostId"
FROM "Blogs" AS t0
INNER JOIN "Posts" AS t1
  ON (t0."BlogId" = t1."BlogId")
```

### EF-04. LEFT JOIN через GroupJoin

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [left join](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators#left-join).
- Проверяет: `DefaultIfEmpty` и строку для блога без постов.

```sql
SELECT [b].[BlogId], [p].[PostId]
FROM [Blogs] AS [b]
LEFT JOIN [Posts] AS [p] ON [b].[BlogId] = [p].[BlogId]
```

```csharp
var query =
    from b in context.Blogs
    join p in context.Posts on b.BlogId equals p.BlogId into posts
    from p in posts.DefaultIfEmpty()
    select new { b.BlogId, PostId = p == null ? (int?)null : p.PostId };
```

#### OCaml (typed-sql)

Правый ключ выбирается как option, чтобы представить blog без поста.

```ocaml
# let ef04 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> left_join Post.table ~on:(fun blog post -> Blog.id blog =. Post.blog_id post)
      |> select (fun (blog, post) ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Blog.id blog)
        and+ projected_right = Projection.expr (Post.nullable_id post) in
        projected_left, projected_right))
val ef04 : (unit, (int64 * int64 option) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef04);;
SELECT
  t0."BlogId",
  t1."PostId"
FROM "Blogs" AS t0
LEFT JOIN "Posts" AS t1
  ON (t0."BlogId" = t1."BlogId")
```

### EF-05. CROSS JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [SelectMany without outer reference](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators#collection-selector-doesnt-reference-outer).
- Проверяет: декартово произведение двух источников.

```sql
SELECT [b].[BlogId], [p].[PostId]
FROM [Blogs] AS [b]
CROSS JOIN [Posts] AS [p]
```

```csharp
var query =
    from b in context.Blogs
    from p in context.Posts
    select new { b.BlogId, p.PostId };
```

#### OCaml (typed-sql)

`cross_join` добавляет второй табличный источник без условия соединения.

```ocaml
# let ef05 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> cross_join Post.table
      |> select (fun (blog, post) ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Blog.id blog)
        and+ projected_right = Projection.expr (Post.id post) in
        projected_left, projected_right))
val ef05 : (unit, (int64 * int64) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef05);;
SELECT
  t0."BlogId",
  t1."PostId"
FROM "Blogs" AS t0
CROSS JOIN "Posts" AS t1
```

### EF-06. Коррелированный selector как JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [collection selector references outer in WHERE](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators#collection-selector-references-outer-in-a-where-clause).
- Проверяет: перевод ссылки на внешнюю строку в условие соединения.

```sql
SELECT [b].[BlogId], [p].[PostId]
FROM [Blogs] AS [b]
INNER JOIN [Posts] AS [p] ON [b].[BlogId] = [p].[BlogId]
```

```csharp
var query =
    from b in context.Blogs
    from p in context.Posts.Where(p => p.BlogId == b.BlogId)
    select new { b.BlogId, p.PostId };
```

#### OCaml (typed-sql)

Условие коррелированного коллекционного selector выражается обычным `INNER JOIN` по внешнему ключу.

```ocaml
# let ef06 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> inner_join Post.table ~on:(fun blog post -> Blog.id blog =. Post.blog_id post)
      |> select (fun (blog, post) ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Blog.id blog)
        and+ projected_right = Projection.expr (Post.id post) in
        projected_left, projected_right))
val ef06 : (unit, (int64 * int64) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef06);;
SELECT
  t0."BlogId",
  t1."PostId"
FROM "Blogs" AS t0
INNER JOIN "Posts" AS t1
  ON (t0."BlogId" = t1."BlogId")
```

### EF-07. Коррелированная проекция как APPLY

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✗
- Источник: [collection selector references outer outside WHERE](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators#collection-selector-references-outer-in-a-non-where-case).
- Проверяет: зависимый источник и границу переносимости; SQLite не поддерживает `APPLY`.

```sql
SELECT [b].[BlogId], ([b].[Url] + N'=>') + [p].[Title] AS [text]
FROM [Blogs] AS [b]
CROSS APPLY [Posts] AS [p]
```

```csharp
var query =
    from b in context.Blogs
    from text in context.Posts.Select(p => b.Url + "=>" + p.Title)
    select new { b.BlogId, text };
```

#### OCaml (typed-sql)

`CROSS APPLY` здесь создаёт строку для каждой пары `Blog`/`Post`, а коррелированное выражение только вычисляет текст. Декартово произведение с конкатенацией имеет ту же семантику результата. DSL не моделирует `APPLY` как отдельную реляционную операцию, поэтому SQL форма и её ограничения по провайдерам не совпадают.

```ocaml
# let ef07 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> inner_join Post.table ~on:(fun _blog _post -> Condition.true_)
      |> select (fun (blog, post) ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Blog.id blog)
        and+ projected_right =
          Projection.expr
            (Expr.concat (Expr.concat_value (Blog.url blog) "=>") (Post.title post))
        in
        projected_left, projected_right))
val ef07 : (unit, (int64 * string) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef07);;
SELECT
  t0."BlogId",
  ((t0."Url" || $1) || t1."Title")
FROM "Blogs" AS t0
INNER JOIN "Posts" AS t1
  ON TRUE
```

### EF-08. GROUP BY с COUNT

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [GroupBy](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators#groupby).
- Проверяет: серверную агрегацию и отсутствие группы для пустого источника.

```sql
SELECT [p].[AuthorId], COUNT(*) AS [Count]
FROM [Posts] AS [p]
GROUP BY [p].[AuthorId]
```

```csharp
var query = context.Posts
    .GroupBy(p => p.AuthorId)
    .Select(g => new { AuthorId = g.Key, Count = g.Count() });
```

#### OCaml (typed-sql)

```ocaml
# let ef08 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Post.table
      |> group_by Post.author_id
      |> select (fun post ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Post.author_id post)
        and+ projected_right = Projection.expr Expr.count_all in
        projected_left, projected_right))
val ef08 : (unit, (int64 * int64) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef08);;
SELECT
  t0."AuthorId",
  COUNT(*)
FROM "Posts" AS t0
GROUP BY
  t0."AuthorId"
```

### EF-09. HAVING после группировки

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [GroupBy with aggregate predicate](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators#groupby).
- Проверяет: применение условия к группе, затем сортировку.

```sql
SELECT [p].[AuthorId], COUNT(*) AS [Count]
FROM [Posts] AS [p]
GROUP BY [p].[AuthorId]
HAVING COUNT(*) > @minCount
ORDER BY [p].[AuthorId]
```

```csharp
var query = context.Posts
    .GroupBy(p => p.AuthorId)
    .Where(g => g.Count() > minCount)
    .OrderBy(g => g.Key)
    .Select(g => new { AuthorId = g.Key, Count = g.Count() });
```

#### OCaml (typed-sql)

```ocaml
# let ef09 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Post.table
      |> group_by Post.author_id
      |> having (fun _ -> Expr.count_all >$ 2L)
      |> order_by Post.author_id `Asc
      |> select (fun post ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Post.author_id post)
        and+ projected_right = Projection.expr Expr.count_all in
        projected_left, projected_right))
val ef09 : (unit, (int64 * int64) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef09);;
SELECT
  t0."AuthorId",
  COUNT(*)
FROM "Posts" AS t0
GROUP BY
  t0."AuthorId"
HAVING
  (COUNT(*) > $1)
ORDER BY
  t0."AuthorId" ASC
```

### EF-10. Подзапрос в IN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [EF Core 8: better use of IN queries](https://learn.microsoft.com/en-us/ef/core/what-is-new/ef-core-8.0/whatsnew#better-use-of-in-queries).
- Проверяет: `Contains` с подзапросом и устранение корреляции. SQL в источнике дан для PostgreSQL.

```sql
SELECT b."Id", b."Name"
FROM "Blogs" AS b
WHERE b."Id" IN (SELECT p."BlogId" FROM "Posts" AS p)
```

```csharp
var blogs = await context.Blogs
    .Where(b => context.Posts.Select(p => p.BlogId).Contains(b.Id))
    .ToListAsync();
```

#### OCaml (typed-sql)

`Query.in_subquery` сохраняет подзапрос как SQL `IN`, без клиентской материализации списка.

```ocaml
# let ef10 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> where (fun blog ->
        let post_blog_ids = Query.(from Post.table |> select_scalar Post.blog_id) in
        Query.in_subquery (Blog.id blog) post_blog_ids)
      |> select (fun blog -> Projection.expr (Blog.id blog)))
val ef10 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef10);;
SELECT
  t0."BlogId"
FROM "Blogs" AS t0
WHERE
  (t0."BlogId" IN (
    SELECT
      t1."BlogId"
    FROM "Posts" AS t1
  ))
```

### EF-11. GroupBy с финальной группировкой на клиенте

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✗ (добавлено в роадмап ✓)
- Без доработок typed-sql: ✓
- Источник: [GroupBy without aggregate](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators#groupby).
- Проверяет: различие между SQL-строками и итоговыми группами; EF Core 7+ собирает группы после чтения.
- Ограничение: OCaml выражает чтение строк и сортировку; финальная сборка групп остаётся клиентской.

```sql
SELECT [b].[Price], [b].[Id], [b].[AuthorId]
FROM [Books] AS [b]
ORDER BY [b].[Price]
```

```csharp
var groups = await context.Books
    .GroupBy(b => b.Price)
    .ToListAsync();
```

В SQL нет `GROUP BY`: группировка здесь выполняется после получения строк.

typed-sql может выразить серверную выборку строк и сортировку, но ядро не выполняет последующую группировку в памяти. Поэтому клиентская часть сценария остаётся вне покрытия.

#### OCaml (typed-sql, только серверная часть)

```ocaml
# let ef11 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Book.table
      |> order_by Book.price `Asc
      |> select (fun book ->
        let open Projection.Let_syntax in
        let+ price = Projection.expr (Book.price book)
        and+ id = Projection.expr (Book.id book)
        and+ author_id = Projection.expr (Book.author_id book) in
        price, id, author_id))
val ef11 : (unit, (int * int64 * int64) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef11);;
SELECT
  t0."Price",
  t0."Id",
  t0."AuthorId"
FROM "Books" AS t0
ORDER BY
  t0."Price" ASC
```

### EF-12. Include двух соседних коллекций

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✗ (добавлено в роадмап ✓)
- Без доработок typed-sql: ✗
- Источник: [cartesian explosion](https://learn.microsoft.com/en-us/ef/core/querying/single-split-queries#cartesian-explosion).
- Проверяет: два `LEFT JOIN`, умножение строк на сервере и сборку двух коллекций на клиенте.

```sql
SELECT [b].[Id], [p].[Id], [c].[Id]
FROM [Blogs] AS [b]
LEFT JOIN [Posts] AS [p] ON [b].[Id] = [p].[BlogId]
LEFT JOIN [Contributors] AS [c] ON [b].[Id] = [c].[BlogId]
ORDER BY [b].[Id], [p].[Id]
```

```csharp
var blogs = await context.Blogs
    .Include(b => b.Posts)
    .Include(b => b.Contributors)
    .ToListAsync();
```

#### OCaml (typed-sql, серверная форма)

Запрос выражает обе LEFT JOIN и серверное умножение строк. typed-sql не материализует сущности и не устраняет повторяющиеся элементы навигационных коллекций, поэтому итоговые объектные коллекции EF Core здесь не воспроизводятся.

```ocaml
# let ef12 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> left_join Post.table ~on:(fun blog post -> Blog.id blog =. Post.blog_id post)
      |> left_join Contributor.table ~on:(fun (blog, _post) contributor ->
        Blog.id blog =. Contributor.blog_id contributor)
      |> order_by (fun ((blog, _post), _contributor) -> Blog.id blog) `Asc
      |> order_by (fun ((_blog, post), _contributor) -> Post.nullable_id post) `Asc
      |> select (fun ((blog, post), contributor) ->
        let open Projection.Let_syntax in
        let+ blog_id = Projection.expr (Blog.id blog)
        and+ post_id = Projection.expr (Post.nullable_id post)
        and+ contributor_id = Projection.expr (Contributor.nullable_id contributor) in
        blog_id, post_id, contributor_id))
val ef12 :
  (unit, (int64 * int64 option * int64 option) list, Dialect.both)
  Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef12);;
SELECT
  t0."BlogId",
  t1."PostId",
  t2."Id"
FROM "Blogs" AS t0
LEFT JOIN "Posts" AS t1
  ON (t0."BlogId" = t1."BlogId")
LEFT JOIN "Contributors" AS t2
  ON (t0."BlogId" = t2."BlogId")
ORDER BY
  t0."BlogId" ASC,
  t1."PostId" ASC
```

### EF-13. Split query для коллекции

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✗ (добавлено в роадмап ✓)
- Без доработок typed-sql: ✗
- Источник: [split queries](https://learn.microsoft.com/en-us/ef/core/querying/single-split-queries#split-queries).
- Проверяет: два серверных запроса, порядок строк и сборку коллекции на клиенте.

```sql
SELECT [b].[BlogId] FROM [Blogs] AS [b] ORDER BY [b].[BlogId];

SELECT [p].[PostId], [p].[BlogId], [b].[BlogId]
FROM [Blogs] AS [b]
INNER JOIN [Posts] AS [p] ON [b].[BlogId] = [p].[BlogId]
ORDER BY [b].[BlogId];
```

```csharp
var blogs = await context.Blogs
    .Include(b => b.Posts)
    .AsSplitQuery()
    .ToListAsync();
```

#### OCaml (typed-sql, два отдельных statement)

Ядро строит оба SQL statement, но не связывает их в split-query execution и не собирает дочерние строки в объектные коллекции.

```ocaml
# let ef13_blogs =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> order_by Blog.id `Asc
      |> select (fun blog -> Projection.expr (Blog.id blog)))
val ef13_blogs : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

```ocaml
# let ef13_posts =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> inner_join Post.table ~on:(fun blog post -> Blog.id blog =. Post.blog_id post)
      |> order_by (fun (blog, _post) -> Blog.id blog) `Asc
      |> select (fun (blog, post) ->
        let open Projection.Let_syntax in
        let+ post_id = Projection.expr (Post.id post)
        and+ post_blog_id = Projection.expr (Post.blog_id post)
        and+ blog_id = Projection.expr (Blog.id blog) in
        post_id, post_blog_id, blog_id))
val ef13_posts :
  (unit, (int64 * int64 * int64) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef13_blogs);;
SELECT
  t0."BlogId"
FROM "Blogs" AS t0
ORDER BY
  t0."BlogId" ASC
```

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef13_posts);;
SELECT
  t1."PostId",
  t1."BlogId",
  t0."BlogId"
FROM "Blogs" AS t0
INNER JOIN "Posts" AS t1
  ON (t0."BlogId" = t1."BlogId")
ORDER BY
  t0."BlogId" ASC
```

### EF-14. ExecuteUpdate с коррелированным агрегатом

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓ (числовой CAST зависит от провайдера)
- Без доработок typed-sql: ✓
- Источник: [updating from related entities](https://learn.microsoft.com/en-us/ef/core/saving/execute-insert-update-delete#navigations-and-related-entities).
- Проверяет: выражение для `SET` на основе связанных строк и поведение при пустой коллекции.
- Ограничение: округление, переполнение и точность CAST определяются провайдером; пустая коллекция вызывает ошибку NOT NULL при выполнении.

```sql
UPDATE [b]
SET [b].[Rating] = CAST((
  SELECT AVG(CAST([p].[Rating] AS float))
  FROM [Post] AS [p]
  WHERE [p].[BlogId] = [b].[Id]
) AS int)
FROM [Blogs] AS [b]
```

```csharp
await context.Blogs
    .Select(b => new {
        Blog = b,
        NewRating = b.Posts.Average(p => p.Rating)
    })
    .ExecuteUpdateAsync(setters =>
        setters.SetProperty(x => x.Blog.Rating, x => x.NewRating));
```

`AVG` игнорирует `NULL`; пустая коллекция и коллекция только из `NULL` дают `NULL`. `set_nullable_expr` явно разрешает присваивание nullable-выражения колонке `NOT NULL`: запрос компилируется, а БД возвращает ошибку ограничения через канал ошибок адаптера. Неуспешный UPDATE не меняет данные. Для nullable-колонки применяется обычный `set_expr`.

Переносимый `avg_int` преобразует вход в floating-point. PostgreSQL-семейство `Postgresql.Numeric.avg_int` сохраняет точный `numeric` результат. Числовой `CAST` использует семантику выбранной БД: округление, переполнение и потеря точности не унифицируются.

#### OCaml (typed-sql)

```ocaml
# let ef14 =
  Statement.command
    ~dialect:Dialect.portable
    Update.(
      table Blog.table
      |> with_target ~f:(fun blog update ->
        let average =
          Query.(
            from Post.table
            |> where (fun post -> Post.blog_id post =. Blog.id blog)
            |> select_scalar (fun post -> Expr.avg_int (Post.rating post)))
        in
        update
        |> set_nullable_expr
             Blog.rating_column
             (Expr.cast_float_to_int_nullable (Expr.scalar_subquery_nullable average)))
      |> all_rows
      |> command)
val ef14 : (unit, Affected_rows.t, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ~input:() ef14);;
UPDATE "Blogs" AS t0
SET
  "Rating" = CAST((
    SELECT
      AVG(CAST(t1."Rating" AS double precision))
    FROM "Posts" AS t1
    WHERE
      (t1."BlogId" = t0."BlogId")
  ) AS integer)
```

### EF-15. ExecuteDelete

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [ExecuteDelete](https://learn.microsoft.com/en-us/ef/core/saving/execute-insert-update-delete#executedelete).
- Проверяет: массовое условное удаление без загрузки сущностей.

```sql
DELETE FROM [b]
FROM [Blogs] AS [b]
WHERE [b].[Rating] < @threshold
```

```csharp
await context.Blogs
    .Where(b => b.Rating < threshold)
    .ExecuteDeleteAsync();
```

#### OCaml (typed-sql)

```ocaml
# let ef15 =
  Statement.command
    ~dialect:Dialect.portable
    Delete.(from Blog.table |> where (fun blog -> Blog.rating blog <$ 3) |> command)
val ef15 : (unit, Affected_rows.t, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef15);;
DELETE FROM "Blogs"
WHERE
  ("Rating" < $1)
```

## Дополнительные сценарии

Карточки EF-16–EF-40 расширяют каталог новыми формами LINQ, материализации и provider-specific SQL; для каждой карточки оценена применимость typed-sql.

### EF-16. Проекция только нужных столбцов

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Efficient Querying: project only properties you need](https://learn.microsoft.com/en-us/ef/core/performance/efficient-querying#project-only-properties-you-need).
- Проверяет: отсутствие загрузки остальных столбцов сущности.

```sql
SELECT [b].[BlogId], [b].[Url]
FROM [Blogs] AS [b]
```

```csharp
var blogs = await context.Blogs
    .Select(b => new { b.BlogId, b.Url })
    .ToListAsync();
```

#### OCaml (typed-sql)

```ocaml
# let ef16 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> select (fun blog ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Blog.id blog)
        and+ projected_right = Projection.expr (Blog.url blog) in
        projected_left, projected_right))
val ef16 : (unit, (int64 * string) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef16);;
SELECT
  t0."BlogId",
  t0."Url"
FROM "Blogs" AS t0
```

### EF-17. StartsWith и индексируемый префикс

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Efficient Querying: use indexes properly](https://learn.microsoft.com/en-us/ef/core/performance/efficient-querying#use-indexes-properly).
- Проверяет: перевод префиксного поиска и отличие от поиска с ведущим wildcard.

```sql
SELECT [b].[BlogId], [b].[Url]
FROM [Blogs] AS [b]
WHERE [b].[Url] LIKE N'https://example.%'
```

```csharp
var blogs = await context.Blogs
    .Where(b => b.Url.StartsWith("https://example."))
    .ToListAsync();
```

Точный шаблон и параметризация зависят от провайдера; сравнить план с `EndsWith` или `Contains` на той же колонке.

#### OCaml (typed-sql)

`LIKE` поддерживается, а `%` остаётся частью bind-параметра pattern. Этот конкретный pattern эквивалентен StartsWith для префикса без SQL wildcard-символов.

```ocaml
# let ef17 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> where (fun blog -> Blog.url blog =~$ "https://example.%")
      |> select (fun blog ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Blog.id blog)
        and+ projected_right = Projection.expr (Blog.url blog) in
        projected_left, projected_right))
val ef17 : (unit, (int64 * string) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef17);;
SELECT
  t0."BlogId",
  t0."Url"
FROM "Blogs" AS t0
WHERE
  (t0."Url" LIKE $1)
```

### EF-18. Any как EXISTS

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Efficient Querying: limit resultset size](https://learn.microsoft.com/en-us/ef/core/performance/efficient-querying#limit-the-resultset-size).
- Проверяет: булев результат существования связанной строки без загрузки коллекции.

```sql
SELECT CASE
  WHEN EXISTS (
    SELECT 1
    FROM [Posts] AS [p]
    WHERE [p].[BlogId] = [b].[BlogId])
  THEN CAST(1 AS bit) ELSE CAST(0 AS bit)
END
FROM [Blogs] AS [b]
```

```csharp
var hasPosts = await context.Blogs
    .Select(b => context.Posts.Any(p => p.BlogId == b.BlogId))
    .ToListAsync();
```

#### OCaml (typed-sql)

`Query.exists_expr` возвращает не-`NULL` `bool` и выражает проекцию напрямую.

```ocaml
# let ef18 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> select (fun blog ->
        Projection.expr
          (Query.exists_expr
             Query.(
               from Post.table |> where (fun post -> Post.blog_id post =. Blog.id blog)))))
val ef18 : (unit, bool list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef18);;
SELECT
  (EXISTS (
    SELECT
      1
    FROM "Posts" AS t1
    WHERE
      (t1."BlogId" = t0."BlogId")
  ))
FROM "Blogs" AS t0
```

### EF-19. All как NOT EXISTS нарушения предиката

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Complex Query Operators](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators).
- Проверяет: пустую коллекцию (для неё `All` возвращает `true`) и перевод отрицания.

```sql
SELECT CASE
  WHEN NOT EXISTS (
    SELECT 1
    FROM [Posts] AS [p]
    WHERE [p].[BlogId] = [b].[BlogId]
      AND [p].[Rating] <= 3)
  THEN CAST(1 AS bit) ELSE CAST(0 AS bit)
END
FROM [Blogs] AS [b]
```

```csharp
var allPopular = await context.Blogs
    .Select(b => b.Posts.All(p => p.Rating > 3))
    .ToListAsync();
```

#### OCaml (typed-sql)

`NOT EXISTS` нарушающего предикат поста сохраняет vacuous truth для блога без постов.

```ocaml
# let ef19 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> select (fun blog ->
        Projection.expr
          (Expr.case
             [ ( Query.not_exists
                   Query.(
                     from Post.table
                     |> where (fun post ->
                       Post.blog_id post =. Blog.id blog &&. (Post.rating post <=$ 3)))
               , Expr.constant Db_type.bool true )
             ]
             ~else_:(Expr.constant Db_type.bool false))))
val ef19 : (unit, bool list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef19);;
SELECT
  (CASE
    WHEN (NOT EXISTS (
      SELECT
        1
      FROM "Posts" AS t1
      WHERE
        (
          (t1."BlogId" = t0."BlogId")
          AND (t1."Rating" <= $1)
        )
    )) THEN $2
    ELSE $3
  END)
FROM "Blogs" AS t0
```

### EF-20. DISTINCT после проекции

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Efficient Querying](https://learn.microsoft.com/en-us/ef/core/performance/efficient-querying).
- Проверяет: устранение дубликатов по набору спроецированных значений.

```sql
SELECT DISTINCT [p].[AuthorId]
FROM [Posts] AS [p]
```

```csharp
var authorIds = await context.Posts
    .Select(p => p.AuthorId)
    .Distinct()
    .ToListAsync();
```

#### OCaml (typed-sql)

```ocaml
# let ef20 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Post.table
      |> distinct
      |> select (fun post -> Projection.expr (Post.author_id post)))
val ef20 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef20);;
SELECT DISTINCT
  t0."AuthorId"
FROM "Posts" AS t0
```

### EF-21. Счётчик строк без материализации

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Complex Query Operators: aggregate functions](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators#aggregate-functions).
- Проверяет: серверный `COUNT(*)` и скалярный результат.

```sql
SELECT COUNT(*)
FROM [Posts] AS [p]
WHERE [p].[BlogId] = @blogId
```

```csharp
var count = await context.Posts
    .CountAsync(p => p.BlogId == blogId);
```

#### OCaml (typed-sql)

```ocaml
# let ef21 =
  Statement.query_one
    ~dialect:Dialect.portable
    Query.Aggregate.(
      from Post.table
      |> where (fun post -> Post.blog_id post =$ 7L)
      |> Query.aggregate_one (fun _ -> Aggregate_projection.count_all))
val ef21 : (unit, int64, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef21);;
SELECT
  COUNT(*)
FROM "Posts" AS t0
WHERE
  (t0."BlogId" = $1)
```

### EF-22. Последняя запись с FirstOrDefault

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Efficient Querying: limit resultset size](https://learn.microsoft.com/en-us/ef/core/performance/efficient-querying#limit-the-resultset-size).
- Проверяет: выбор первой строки после обратной сортировки и `null`, если строк нет.

```sql
SELECT TOP(1) [p].[PostId], [p].[Title], [p].[Date]
FROM [Posts] AS [p]
WHERE [p].[BlogId] = @blogId
ORDER BY [p].[Date] DESC, [p].[PostId] DESC
```

```csharp
var latest = await context.Posts
    .Where(p => p.BlogId == blogId)
    .OrderByDescending(p => p.Date)
    .ThenByDescending(p => p.PostId)
    .Select(p => new { p.PostId, p.Title, p.Date })
    .FirstOrDefaultAsync();
```

#### OCaml (typed-sql)

`limit_one` доказывает верхнюю границу, а `params.query_optional` возвращает `None` при отсутствии подходящей строки.

```ocaml
# let ef22 =
  Statement.query_optional
    ~dialect:Dialect.portable
    Query.(
      from Post.table
      |> where (fun post -> Post.blog_id post =$ 7L)
      |> order_by Post.date `Desc
      |> order_by Post.id `Desc
      |> limit_one
      |> select (fun post ->
        let open Projection.Let_syntax in
        let+ id = Projection.expr (Post.id post)
        and+ title = Projection.expr (Post.title post)
        and+ date = Projection.expr (Post.date post) in
        id, title, date))
val ef22 :
  (unit, (int64 * string * Ptime.t) option, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef22);;
SELECT
  t0."PostId",
  t0."Title",
  t0."Date"
FROM "Posts" AS t0
WHERE
  (t0."BlogId" = $1)
ORDER BY
  t0."Date" DESC,
  t0."PostId" DESC
LIMIT $2
```

### EF-23. Равенство nullable-значений

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Query null semantics](https://learn.microsoft.com/en-us/ef/core/querying/null-comparisons).
- Проверяет: сравнение nullable колонок и компенсацию различий трёхзначной логики SQL и C#.

```sql
SELECT [p].[PostId]
FROM [Posts] AS [p]
WHERE [p].[OptionalRating] = @rating
   OR ([p].[OptionalRating] IS NULL AND @rating IS NULL)
```

```csharp
int? rating = requestedRating;
var posts = await context.Posts
    .Where(p => p.OptionalRating == rating)
    .Select(p => p.PostId)
    .ToListAsync();
```

Форма SQL зависит от nullability модели и `UseRelationalNulls`.

#### OCaml (typed-sql)

`is_distinct_from` даёт portable null-safe сравнение; его отрицание совпадает с C# nullable equality. SQL shape отличается от компенсационного OR, который может выбрать EF Core.

```ocaml
# let ef23 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Post.table
      |> where (fun post ->
        Condition.not_
          (Expr.is_distinct_from
             (Post.optional_rating post)
             (Expr.constant (Db_type.option Db_type.int) (Some 3))))
      |> select (fun post -> Projection.expr (Post.id post)))
val ef23 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef23);;
SELECT
  t0."PostId"
FROM "Posts" AS t0
WHERE
  (NOT (t0."OptionalRating" IS DISTINCT FROM $1))
```

### EF-24. Null-coalescing в проекции

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Database Functions](https://learn.microsoft.com/en-us/ef/core/querying/database-functions).
- Проверяет: перевод оператора `??` в SQL `COALESCE`.

```sql
SELECT COALESCE([b].[NullableUrl], N'(missing)')
FROM [Blogs] AS [b]
```

```csharp
var urls = await context.Blogs
    .Select(b => b.NullableUrl ?? "(missing)")
    .ToListAsync();
```

#### OCaml (typed-sql)

```ocaml
# let ef24 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> select (fun blog ->
        Projection.expr
          (Expr.coalesce
             (Blog.nullable_url blog)
             ~default:(Expr.constant Db_type.text "(missing)"))))
val ef24 : (unit, string list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef24);;
SELECT
  COALESCE(t0."NullableUrl", $1)
FROM "Blogs" AS t0
```

### EF-25. Условная проекция в CASE

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Client vs. Server Evaluation](https://learn.microsoft.com/en-us/ef/core/querying/client-eval).
- Проверяет: исполнение сравнения и выбора результата на сервере.

```sql
SELECT CASE WHEN [b].[Rating] >= 4
            THEN N'popular'
            ELSE N'other' END
FROM [Blogs] AS [b]
```

```csharp
var labels = await context.Blogs
    .Select(b => b.Rating >= 4 ? "popular" : "other")
    .ToListAsync();
```

#### OCaml (typed-sql)

```ocaml
# let ef25 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> select (fun blog ->
        Projection.expr
          (Expr.case
             [ Blog.rating blog >=$ 4, Expr.constant Db_type.text "popular" ]
             ~else_:(Expr.constant Db_type.text "other"))))
val ef25 : (unit, string list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef25);;
SELECT
  (CASE
    WHEN (t0."Rating" >= $1) THEN $2
    ELSE $3
  END)
FROM "Blogs" AS t0
```

### EF-26. Глобальный фильтр soft delete

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Global Query Filters](https://learn.microsoft.com/en-us/ef/core/querying/filters#basic-example---soft-deletion).
- Проверяет: автоматическое добавление фильтра модели и его отключение через `IgnoreQueryFilters`.

```sql
SELECT [b].[BlogId], [b].[Url]
FROM [Blogs] AS [b]
WHERE [b].[IsDeleted] = CAST(0 AS bit)
```

```csharp
modelBuilder.Entity<Blog>()
    .HasQueryFilter(b => !b.IsDeleted);

var visibleBlogs = await context.Blogs.ToListAsync();
var allBlogs = await context.Blogs.IgnoreQueryFilters().ToListAsync();
```

Второй запрос проверяет снятие model-level фильтра; его SQL не содержит предиката `IsDeleted`.

#### OCaml (typed-sql, явный фильтр запроса)

typed-sql не имеет model-level global filters. Эквивалентный предикат можно добавить явно в каждый запрос:

```ocaml
# let ef26 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> where (fun blog -> Blog.is_deleted blog =$ false)
      |> select (fun blog ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Blog.id blog)
        and+ projected_right = Projection.expr (Blog.url blog) in
        projected_left, projected_right))
val ef26 : (unit, (int64 * string) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef26);;
SELECT
  t0."BlogId",
  t0."Url"
FROM "Blogs" AS t0
WHERE
  (t0."IsDeleted" = $1)
```

### EF-27. Filtered Include для коллекции

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✗ (добавлено в роадмап ✓)
- Без доработок typed-sql: ✓
- Источник: [Eager Loading: filtered include](https://learn.microsoft.com/en-us/ef/core/querying/related-data/eager#filtered-include).
- Проверяет: фильтрацию, сортировку и ограничение элементов включённой коллекции.
- Замечание: per-blog top 5 выражен коррелированным COUNT строк, отсортированных раньше по Title DESC, PostId DESC; typed-sql возвращает плоские строки и не собирает navigation collection.

```sql
SELECT [b].[BlogId], [b].[Url], [t].[PostId], [t].[BlogId], [t].[Title]
FROM [Blogs] AS [b]
LEFT JOIN (
  SELECT [t0].[PostId], [t0].[BlogId], [t0].[Title]
  FROM (
    SELECT [p].[PostId], [p].[BlogId], [p].[Title],
      ROW_NUMBER() OVER(PARTITION BY [p].[BlogId] ORDER BY [p].[Title] DESC, [p].[PostId] DESC) AS [row]
    FROM [Posts] AS [p]
    WHERE [p].[Rating] >= 4
  ) AS [t0]
  WHERE [t0].[row] <= 5
) AS [t] ON [b].[BlogId] = [t].[BlogId]
ORDER BY [b].[BlogId], [t].[PostId], [t].[Title] DESC
```

```csharp
var blogs = await context.Blogs
    .Include(b => b.Posts
        .Where(p => p.Rating >= 4)
        .OrderByDescending(p => p.Title)
        .ThenByDescending(p => p.PostId)
        .Take(5))
    .ToListAsync();
```

Провайдер может использовать `ROW_NUMBER` или `APPLY` для per-blog `Take(5)`; конкретная форма SQL зависит от провайдера.

#### OCaml (typed-sql, per-blog top-N через COUNT)

```ocaml
# let ef27 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> left_join Post.table ~on:(fun blog post ->
        let preceding_count =
          Query.(
            from Post.table
            |> where (fun candidate ->
              Post.blog_id candidate
              =. Blog.id blog
              &&. (Post.rating candidate >=$ 4)
              &&. (Post.title candidate
                   >. Post.title post
                   ||. (Post.title candidate
                        =. Post.title post
                        &&. (Post.id candidate >. Post.id post))))
            |> select_scalar (fun _ -> Expr.count_all))
        in
        let preceding =
          Expr.coalesce
            (Expr.scalar_subquery preceding_count)
            ~default:(Expr.constant Db_type.int64 0L)
        in
        Blog.id blog
        =. Post.blog_id post
        &&. (Post.rating post >=$ 4)
        &&. (preceding <$ 5L))
      |> order_by (fun (blog, _post) -> Blog.id blog) `Asc
      |> order_by (fun (_blog, post) -> Post.nullable_id post) `Asc
      |> order_by (fun (_blog, post) -> Expr.nullable_column post Post.title_column) `Desc
      |> select (fun (blog, post) ->
        let open Projection.Let_syntax in
        let+ blog_fields =
          let open Projection.Let_syntax in
          let+ projected_left = Projection.expr (Blog.id blog)
          and+ projected_right = Projection.expr (Blog.url blog) in
          projected_left, projected_right
        and+ post_fields =
          let open Projection.Let_syntax in
          let+ projected_left = Projection.expr (Post.nullable_id post)
          and+ projected_right =
            Projection.expr (Expr.nullable_column post Post.blog_id_column)
          in
          projected_left, projected_right
        and+ title = Projection.expr (Expr.nullable_column post Post.title_column) in
        blog_fields, post_fields, title))
val ef27 :
  (unit,
   ((int64 * string) * (int64 option * int64 option) * string option) list,
   Dialect.both)
  Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef27);;
SELECT
  t0."BlogId",
  t0."Url",
  t1."PostId",
  t1."BlogId",
  t1."Title"
FROM "Blogs" AS t0
LEFT JOIN "Posts" AS t1
  ON (
    (t0."BlogId" = t1."BlogId")
    AND (t1."Rating" >= $1)
    AND (COALESCE((
      SELECT
        COUNT(*)
      FROM "Posts" AS t2
      WHERE
        (
          (t2."BlogId" = t0."BlogId")
          AND (t2."Rating" >= $2)
          AND (
            (t2."Title" > t1."Title")
            OR (
              (t2."Title" = t1."Title")
              AND (t2."PostId" > t1."PostId")
            )
          )
        )
    ), $3) < $4)
  )
ORDER BY
  t0."BlogId" ASC,
  t1."PostId" ASC,
  t1."Title" DESC
```

### EF-28. Include и ThenInclude

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✗ (добавлено в роадмап ✓)
- Без доработок typed-sql: ✓
- Источник: [Eager Loading: including multiple levels](https://learn.microsoft.com/en-us/ef/core/querying/related-data/eager#including-multiple-levels).
- Проверяет: загрузку цепочки Blog → Posts → Author одним запросом.
- Ограничение: typed-sql строит плоский набор строк с двумя LEFT JOIN; сущности EF и identity resolution не материализуются.

```sql
SELECT [b].[BlogId], [p].[PostId], [a].[AuthorId], [a].[Name]
FROM [Blogs] AS [b]
LEFT JOIN [Posts] AS [p] ON [b].[BlogId] = [p].[BlogId]
LEFT JOIN [Authors] AS [a] ON [p].[AuthorId] = [a].[AuthorId]
ORDER BY [b].[BlogId], [p].[PostId]
```

```csharp
var blogs = await context.Blogs
    .Include(b => b.Posts)
    .ThenInclude(p => p.Author)
    .ToListAsync();
```

#### OCaml (typed-sql, серверная форма)

Здесь строится плоский набор строк с двумя JOIN; материализацию графа навигаций выполняет EF Core, а typed-sql её не моделирует.

```ocaml
# let ef28 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> left_join Post.table ~on:(fun blog post -> Blog.id blog =. Post.blog_id post)
      |> left_join Author.table ~on:(fun (_blog, post) author ->
        Post.nullable_author_id post =. Expr.to_nullable (Author.id author))
      |> order_by (fun ((blog, _post), _author) -> Blog.id blog) `Asc
      |> order_by (fun ((_blog, post), _author) -> Post.nullable_id post) `Asc
      |> select (fun ((blog, post), author) ->
        let open Projection.Let_syntax in
        let+ blog_and_post =
          let open Projection.Let_syntax in
          let+ projected_left = Projection.expr (Blog.id blog)
          and+ projected_right = Projection.expr (Post.nullable_id post) in
          projected_left, projected_right
        and+ author_fields =
          let open Projection.Let_syntax in
          let+ projected_left = Projection.expr (Author.nullable_id author)
          and+ projected_right =
            Projection.expr (Expr.nullable_column author Author.name_column)
          in
          projected_left, projected_right
        in
        blog_and_post, author_fields))
val ef28 :
  (unit, ((int64 * int64 option) * (int64 option * string option)) list,
   Dialect.both)
  Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef28);;
SELECT
  t0."BlogId",
  t1."PostId",
  t2."AuthorId",
  t2."Name"
FROM "Blogs" AS t0
LEFT JOIN "Posts" AS t1
  ON (t0."BlogId" = t1."BlogId")
LEFT JOIN "Authors" AS t2
  ON (t1."AuthorId" = t2."AuthorId")
ORDER BY
  t0."BlogId" ASC,
  t1."PostId" ASC
```

### EF-29. Tracking и AsNoTracking

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✗ (добавлено в роадмап ✓)
- Без доработок typed-sql: ✗
- Источник: [Tracking vs. No-Tracking Queries](https://learn.microsoft.com/en-us/ef/core/querying/tracking).
- Проверяет: одинаковый серверный запрос при разной работе change tracker и identity resolution.
- Ограничение: SQL выборка выражается полностью, но change tracker и identity resolution относятся к работе EF Core после чтения строк.

```sql
SELECT [b].[BlogId], [b].[Rating], [b].[Url]
FROM [Blogs] AS [b]
```

```csharp
var tracked = await context.Blogs.ToListAsync();
var readOnly = await context.Blogs.AsNoTracking().ToListAsync();
```

SQL может совпадать; сравнить tracking state, идентичность повторяющихся сущностей и результат при уже отслеживаемых объектах.

typed-sql может построить сам rowset, но tracking, identity resolution и attach состояния находятся вне backend-independent ядра. Семантическую часть этой карточки через typed-sql выразить нельзя.

#### OCaml (typed-sql, серверная форма)

```ocaml
# let ef29 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> select (fun blog ->
        let open Projection.Let_syntax in
        let+ id = Projection.expr (Blog.id blog)
        and+ rating = Projection.expr (Blog.rating blog)
        and+ url = Projection.expr (Blog.url blog) in
        id, rating, url))
val ef29 : (unit, (int64 * int * string) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef29);;
SELECT
  t0."BlogId",
  t0."Rating",
  t0."Url"
FROM "Blogs" AS t0
```

### EF-30. Клиентский helper в верхней проекции

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Client vs. Server Evaluation](https://learn.microsoft.com/en-us/ef/core/querying/client-eval#client-evaluation-in-the-top-level-projection).
- Проверяет: вычисление на сервере выбранных данных и вызов helper после чтения строки.

```sql
SELECT [b].[BlogId], [b].[Url]
FROM [Blogs] AS [b]
ORDER BY [b].[Rating] DESC
```

```csharp
var blogs = await context.Blogs
    .OrderByDescending(b => b.Rating)
    .Select(b => new { b.BlogId, Url = StandardizeUrl(b.Url) })
    .ToListAsync();
```

`StandardizeUrl` выполняется клиентом; результатный SQL не содержит вызова этого метода.

#### OCaml (typed-sql, серверная выборка и клиентский этап)

```ocaml
# let ef30_query =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> order_by (fun blog -> Blog.rating blog) `Desc
      |> select (fun blog ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Blog.id blog)
        and+ projected_right = Projection.expr (Blog.url blog) in
        projected_left, projected_right))
val ef30_query : (unit, (int64 * string) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef30_query);;
SELECT
  t0."BlogId",
  t0."Url"
FROM "Blogs" AS t0
ORDER BY
  t0."Rating" DESC
```

### EF-31. Непереводимый helper в WHERE

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✓)
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [Client vs. Server Evaluation: unsupported client evaluation](https://learn.microsoft.com/en-us/ef/core/querying/client-eval#unsupported-client-evaluation).
- Проверяет: исключение при непереводимом выражении вне верхней проекции, вместо незаметной клиентской фильтрации.
- Ограничение: Произвольный OCaml helper нельзя переводить в SQL; typed-sql строит запросы, а не воспроизводит исключение EF Core при трансляции.

```csharp
var blogs = await context.Blogs
    .Where(b => StandardizeUrl(b.Url) == requestedUrl)
    .ToListAsync();
```

Для актуального EF Core ожидается ошибка трансляции до выполнения запроса. Отдельный вариант с `AsEnumerable()` проверяет явный переход к клиентской фильтрации и риск загрузки всей таблицы.

### EF-32. Contains по параметрической коллекции (EF Core 8)

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [What's New in EF Core 8: primitive collections](https://learn.microsoft.com/en-us/ef/core/what-is-new/ef-core-8.0/whatsnew#primitive-collections).
- Проверяет: передачу списка одним JSON параметром, кэшируемую форму SQL и зависимость от уровня совместимости SQL Server.
- Ограничение: `Expr.in_` сохраняет результат Contains, но передаёт элементы отдельными bind-параметрами вместо одного JSON-параметра EF Core 8.

```sql
SELECT [w].[Name]
FROM [Walks] AS [w]
WHERE EXISTS (
  SELECT 1
  FROM OpenJson(@__terrains_0) AS [t]
  WHERE CAST([t].[value] AS int) = [w].[Terrain])
```

```csharp
var terrains = new[] { Terrain.River, Terrain.Beach, Terrain.Park };
var walks = await context.Walks
    .Where(w => terrains.Contains(w.Terrain))
    .Select(w => w.Name)
    .ToListAsync();
```

#### OCaml (typed-sql, список как набор bind-значений)

```ocaml
# let ef32 =
  Statement.Dynamic.query_many ~dialect:Dialect.portable (fun terrain_ids ->
    Query.(
      from Book.table
      |> where (fun book -> Expr.in_ (Book.author_id book) terrain_ids)
      |> select (fun book -> Projection.expr (Book.id book))))
val ef32 : (int64 list, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ~input:[ 1L; 5L; 4L ] ef32);;
SELECT
  t0."Id"
FROM "Books" AS t0
WHERE
  (t0."AuthorId" IN (
    $1,
    $2,
    $3
  ))
```

Список значений и фильтр выражаются typed-sql, но форма отличается от EF Core 8: это динамическое число bind-параметров, а не один JSON параметр с `OPENJSON`.

`OpenJson` требует SQL Server 2016 / compatibility level 130 или выше; поведение зависит от версии EF Core и настроек провайдера.

### EF-33. Поиск элемента в JSON-коллекции колонки

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✓)
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [What's New in EF Core 8: primitive collections](https://learn.microsoft.com/en-us/ef/core/what-is-new/ef-core-8.0/whatsnew#primitive-collections-in-json-columns).
- Проверяет: разворачивание JSON массива колонки и сравнение с параметром.
- Ограничение: В публичном DSL нет табличной функции `OPENJSON` для чтения элементов JSON-массива из каждой строки.

```sql
SELECT [p].[Name]
FROM [Pubs] AS [p]
WHERE EXISTS (
  SELECT 1
  FROM OpenJson([p].[Beers]) AS [b]
  WHERE [b].[value] = @__beer_0)
```

```csharp
var beer = "Heineken";
var pubs = await context.Pubs
    .Where(p => p.Beers.Contains(beer))
    .Select(p => p.Name)
    .ToListAsync();
```

### EF-34. CLR-метод, отображённый в SQL UDF

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✓)
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [User-defined function mapping](https://learn.microsoft.com/en-us/ef/core/querying/user-defined-function-mapping#mapping-a-method-to-a-sql-function).
- Проверяет: отображение метода модели на схематизированную скалярную SQL-функцию.
- Ограничение: Публичный API не имеет дескриптора SQL UDF или конструктора вызова произвольной схемной функции.

```sql
SELECT [b].[BlogId], [b].[Rating], [b].[Url]
FROM [Blogs] AS [b]
WHERE [dbo].[CommentedPostCountForBlog]([b].[BlogId]) > 1
```

```csharp
var blogs = await context.Blogs
    .Where(b => context.CommentedPostCountForBlog(b.BlogId) > 1)
    .ToListAsync();
```

CLR-метод должен быть зарегистрирован через `HasDbFunction`; его тело не вызывается при серверной трансляции.

### EF-35. FromSql с LINQ-композицией

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✓)
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [SQL Queries: composing with LINQ](https://learn.microsoft.com/en-us/ef/core/querying/sql-queries#composing-with-linq).
- Проверяет: обёртку raw SQL как подзапрос и добавление LINQ фильтра и сортировки снаружи.
- Ограничение: Публичный API не принимает raw SQL как typed relation, которую можно обернуть внешним SELECT.

```sql
SELECT [b].[BlogId], [b].[Rating], [b].[Url]
FROM (
  SELECT * FROM dbo.SearchBlogs(@p0)
) AS [b]
WHERE [b].[Rating] > 3
ORDER BY [b].[Rating] DESC
```

```csharp
var searchTerm = "Lorem ipsum";
var blogs = await context.Blogs
    .FromSql($"SELECT * FROM dbo.SearchBlogs({searchTerm})")
    .Where(b => b.Rating > 3)
    .OrderByDescending(b => b.Rating)
    .ToListAsync();
```

Композиция возможна только поверх composable SQL; SQL Server не позволяет оборачивать хранимую процедуру как подзапрос.

### EF-36. UNION блогов и авторов популярных постов

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [LINQ `Union`](https://learn.microsoft.com/en-us/dotnet/api/system.linq.queryable.union).
- Проверяет: одинаковую проекцию `BlogId` в двух ветвях и устранение повторений после объединения.

```sql
SELECT [b].[BlogId] FROM [Blogs] AS [b] WHERE [b].[Rating] >= 5
UNION
SELECT [p].[BlogId] FROM [Posts] AS [p] WHERE [p].[Rating] >= 5
```

```csharp
var blogIds = await context.Blogs
    .Where(b => b.Rating >= 5)
    .Select(b => b.BlogId)
    .Union(context.Posts
        .Where(p => p.Rating >= 5)
        .Select(p => p.BlogId))
    .ToListAsync();
```

#### OCaml (typed-sql)

```ocaml
let ef36_blogs =
  Query.(
    from Blog.table
    |> where (fun blog -> Blog.rating blog >$ 5)
    |> select (fun blog -> Projection.expr (Blog.id blog)))
;;

let ef36_posts =
  Query.(
    from Post.table
    |> where (fun post -> Post.rating post >$ 5)
    |> select (fun post -> Projection.expr (Post.blog_id post)))
;;
```

```ocaml
# let ef36 =
  Statement.query_many ~dialect:Dialect.portable (Query.union ef36_blogs ef36_posts)
val ef36 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef36);;
SELECT *
FROM (
  SELECT
    t0."BlogId"
  FROM "Blogs" AS t0
  WHERE
    (t0."Rating" > $1)
) AS s0
UNION
SELECT *
FROM (
  SELECT
    t0."BlogId"
  FROM "Posts" AS t0
  WHERE
    (t0."Rating" > $2)
) AS s0
```

### EF-37. ExecuteUpdate с прежним значением колонки

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [ExecuteUpdate: referencing the existing property value](https://learn.microsoft.com/en-us/ef/core/saving/execute-insert-update-delete#referencing-the-existing-property-value).
- Проверяет: однократный серверный UPDATE и вычисление нового `Rating` из прежнего значения для каждой подходящей строки.
- Ограничение: Для доступа к старому значению используется typed UPDATE self-join по первичному ключу; выражение Rating + 1 остаётся на сервере.

```sql
UPDATE [b]
SET [b].[Rating] = [b].[Rating] + 1
FROM [Blogs] AS [b]
WHERE [b].[Rating] < 3
```

```csharp
var changed = await context.Blogs
    .Where(b => b.Rating < 3)
    .ExecuteUpdateAsync(setters => setters
        .SetProperty(b => b.Rating, b => b.Rating + 1));
```

#### OCaml (typed-sql)

```ocaml
# let ef37 =
  Statement.command
    ~dialect:Dialect.portable
    Update.(
      table Blog.table
      |> from Blog.table ~f:(fun target source update ->
        update
        |> set_expr
             Blog.rating_column
             Expr.Int.Infix.(Blog.rating target +. Expr.constant Db_type.int 1)
        |> where (fun _ -> Blog.id target =. Blog.id source))
      |> where (fun target -> Blog.rating target <$ 3)
      |> command)
val ef37 : (unit, Affected_rows.t, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef37);;
UPDATE "Blogs" AS t0
SET
  "Rating" = (t0."Rating" + $1)
FROM "Blogs" AS t1
WHERE
  (
    (t0."BlogId" = t1."BlogId")
    AND (t0."Rating" < $2)
  )
```

### EF-38. Сравнение с явным правилом сопоставления строк

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✓)
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [Collations and case sensitivity](https://learn.microsoft.com/en-us/ef/core/miscellaneous/collations-and-case-sensitivity).
- Проверяет: применение явного правила сопоставления только к сравнению `Url`; совпадение зависит от регистра в SQL Server.
- Ограничение: DSL не поддерживает выражение `COLLATE` и выбор collation для отдельного сравнения.

```sql
SELECT [b].[BlogId], [b].[Url]
FROM [Blogs] AS [b]
WHERE [b].[Url] COLLATE SQL_Latin1_General_CP1_CS_AS = @url
```

```csharp
var blogs = await context.Blogs
    .Where(b => EF.Functions.Collate(
        b.Url, "SQL_Latin1_General_CP1_CS_AS") == url)
    .Select(b => new { b.BlogId, b.Url })
    .ToListAsync();
```

### EF-39. Снимок temporal-таблицы на момент времени

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✓)
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [SQL Server temporal tables](https://learn.microsoft.com/en-us/ef/core/providers/sql-server/temporal-tables#querying-historical-data).
- Проверяет: `FOR SYSTEM_TIME AS OF` с UTC-моментом и фильтр по ключу поверх исторической версии строки.
- Ограничение: Синтаксис SQL Server `FOR SYSTEM_TIME AS OF` задаётся между именем таблицы и алиасом и сейчас отсутствует в renderer.

```sql
SELECT [b].[BlogId], [b].[Url], [b].[Rating]
FROM [Blogs] FOR SYSTEM_TIME AS OF @point AS [b]
WHERE [b].[BlogId] = @blogId
```

```csharp
var point = new DateTime(2024, 1, 1, 0, 0, 0, DateTimeKind.Utc);
var snapshot = await context.Blogs
    .TemporalAsOf(point)
    .Where(b => b.BlogId == blogId)
    .Select(b => new { b.BlogId, b.Url, b.Rating })
    .SingleOrDefaultAsync();
```

Для EF-39 таблица `Blogs` в фикстуре должна быть настроена как темпоральная таблица.

### EF-40. LIKE с экранированным процентом

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✓)
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [SQL Server function mappings](https://learn.microsoft.com/en-us/ef/core/providers/sql-server/functions).
- Проверяет: поиск буквального `100%` в начале заголовка, где первый `%` экранирован, а последний остаётся wildcard.
- Ограничение: DSL поддерживает LIKE, но не `ESCAPE`; без него обратный слеш не гарантирует поиск буквального `%` во всех диалектах.

```sql
SELECT [p].[PostId], [p].[Title]
FROM [Posts] AS [p]
WHERE [p].[Title] LIKE @pattern ESCAPE @escape
```

```csharp
var pattern = @"100\%%";
var posts = await context.Posts
    .Where(p => EF.Functions.Like(p.Title, pattern, @"\"))
    .Select(p => new { p.PostId, p.Title })
    .ToListAsync();
```
### EF-41. Проекция публикаций с фильтром и составной сортировкой


- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Efficient Querying](https://learn.microsoft.com/en-us/ef/core/performance/efficient-querying).
- Проверяет: фильтр рейтинга, tie-break по ключу и ограничение результата.

```sql
SELECT PostId, BlogId, Title FROM Posts
WHERE Rating >= @minimum ORDER BY Rating DESC, PostId LIMIT @take
```

```csharp
var posts = await context.Posts.Where(p => p.Rating >= minimum)
    .OrderByDescending(p => p.Rating).ThenBy(p => p.PostId).Take(take)
    .Select(p => new { p.PostId, p.BlogId, p.Title }).ToListAsync();
```

#### OCaml (typed-sql)

```ocaml
# let ef41 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Post.table
      |> where (fun post -> Post.rating post >=$ 4)
      |> order_by Post.rating `Desc
      |> order_by Post.id `Asc
      |> limit 10
      |> select (fun post ->
        let open Projection.Let_syntax in
        let+ id = Projection.expr (Post.id post)
        and+ blog_id = Projection.expr (Post.blog_id post)
        and+ title = Projection.expr (Post.title post) in
        id, blog_id, title))
val ef41 : (unit, (int64 * int64 * string) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef41);;
SELECT
  t0."PostId",
  t0."BlogId",
  t0."Title"
FROM "Posts" AS t0
WHERE
  (t0."Rating" >= $1)
ORDER BY
  t0."Rating" DESC,
  t0."PostId" ASC
LIMIT $2
```

### EF-42. Максимальная дата публикации для блога

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Complex Query Operators](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators).
- Проверяет: коррелированный nullable scalar subquery с `MAX`.

```sql
SELECT BlogId,
  (SELECT MAX(Date) FROM Posts WHERE Posts.BlogId = Blogs.BlogId)
FROM Blogs
```

```csharp
var result = await context.Blogs.Select(b => new {
    b.BlogId,
    Latest = b.Posts.Max(p => (DateTime?)p.Date)
}).ToListAsync();
```

#### OCaml (typed-sql)

```ocaml
# let ef42 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> select (fun blog ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Blog.id blog)
        and+ projected_right =
          Projection.expr
            (Expr.scalar_subquery
               Query.(
                 from Post.table
                 |> where (fun post -> Post.blog_id post =. Blog.id blog)
                 |> select_scalar (fun post ->
                   Expr.max Db_type.Orderable.timestamp (Post.date post))))
        in
        projected_left, projected_right))
val ef42 :
  (unit, (int64 * Ptime.t option option) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef42);;
SELECT
  t0."BlogId",
  (
    SELECT
      MAX(t1."Date")
    FROM "Posts" AS t1
    WHERE
      (t1."BlogId" = t0."BlogId")
  )
FROM "Blogs" AS t0
```

### EF-43. DISTINCT авторы после фильтра публикаций

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Efficient Querying](https://learn.microsoft.com/en-us/ef/core/performance/efficient-querying).
- Проверяет: фильтрацию перед distinct-проекцией и порядок ключей.

```sql
SELECT DISTINCT AuthorId FROM Posts WHERE Rating >= @minimum ORDER BY AuthorId
```

```csharp
var ids = await context.Posts.Where(p => p.Rating >= minimum)
    .Select(p => p.AuthorId).Distinct().OrderBy(id => id).ToListAsync();
```

#### OCaml (typed-sql)

```ocaml
# let ef43 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Post.table
      |> where (fun post -> Post.rating post >=$ 4)
      |> distinct
      |> order_by Post.author_id `Asc
      |> select (fun post -> Projection.expr (Post.author_id post)))
val ef43 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef43);;
SELECT DISTINCT
  t0."AuthorId"
FROM "Posts" AS t0
WHERE
  (t0."Rating" >= $1)
ORDER BY
  t0."AuthorId" ASC
```

### EF-44. Книги, у которых нет автора с заданным именем

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Complex Query Operators](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators).
- Проверяет: коррелированный `NOT EXISTS` по отношению авторов.

```sql
SELECT Id, Price FROM Books
WHERE NOT EXISTS (SELECT 1 FROM Authors WHERE Authors.AuthorId = Books.AuthorId AND Name = @name)
```

```csharp
var books = await context.Books.Where(b => !context.Authors
    .Any(a => a.AuthorId == b.AuthorId && a.Name == name)).ToListAsync();
```

#### OCaml (typed-sql)

```ocaml
# let ef44 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Book.table
      |> where (fun book ->
        not_exists
          Query.(
            from Author.table
            |> where (fun author ->
              Author.id author =. Book.author_id book &&. (Author.name author =$ "Ada"))))
      |> select (fun book ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Book.id book)
        and+ projected_right = Projection.expr (Book.price book) in
        projected_left, projected_right))
val ef44 : (unit, (int64 * int) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef44);;
SELECT
  t0."Id",
  t0."Price"
FROM "Books" AS t0
WHERE
  (NOT EXISTS (
    SELECT
      1
    FROM "Authors" AS t1
    WHERE
      (
        (t1."AuthorId" = t0."AuthorId")
        AND (t1."Name" = $1)
      )
  ))
```

### EF-45. Условный DELETE с возвратом удалённых ключей

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [ExecuteDelete](https://learn.microsoft.com/en-us/ef/core/saving/execute-insert-update-delete#executedelete).
- Проверяет: массовое удаление по фильтру без загрузки сущностей.

```sql
DELETE FROM Posts WHERE Rating < @threshold
```

```csharp
var removed = await context.Posts.Where(p => p.Rating < threshold).ExecuteDeleteAsync();
```

#### OCaml (typed-sql)

```ocaml
# let ef45 =
  Statement.command
    ~dialect:Dialect.portable
    Delete.(from Post.table |> where (fun post -> Post.rating post <$ 2) |> command)
val ef45 : (unit, Affected_rows.t, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef45);;
DELETE FROM "Posts"
WHERE
  ("Rating" < $1)
```

### EF-46. Фильтр по набору author ID

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [LINQ Contains](https://learn.microsoft.com/en-us/ef/core/what-is-new/ef-core-8.0/whatsnew#better-use-of-in-queries).
- Проверяет: membership по нескольким значениям и проекцию только нужных столбцов.

```sql
SELECT PostId, AuthorId FROM Posts WHERE AuthorId IN (@id1, @id2)
```

```csharp
var posts = await context.Posts.Where(p => authorIds.Contains(p.AuthorId))
    .Select(p => new { p.PostId, p.AuthorId }).ToListAsync();
```

#### OCaml (typed-sql)

```ocaml
# let ef46 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Post.table
      |> where (fun post -> Expr.in_ (Post.author_id post) [ 1L; 2L ])
      |> select (fun post ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Post.id post)
        and+ projected_right = Projection.expr (Post.author_id post) in
        projected_left, projected_right))
val ef46 : (unit, (int64 * int64) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef46);;
SELECT
  t0."PostId",
  t0."AuthorId"
FROM "Posts" AS t0
WHERE
  (t0."AuthorId" IN (
    $1,
    $2
  ))
```

### EF-47. Постраничная выборка с nullable-значением по умолчанию

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Database functions](https://learn.microsoft.com/en-us/ef/core/querying/database-functions).
- Проверяет: `COALESCE`, стабильный порядок и ограничение числа строк.

```sql
SELECT BlogId, COALESCE(NullableUrl, N'(missing)')
FROM Blogs ORDER BY BlogId OFFSET 5 ROWS FETCH NEXT 10 ROWS ONLY
```

```csharp
var page = await context.Blogs.OrderBy(b => b.BlogId).Skip(5).Take(10)
    .Select(b => new { b.BlogId, Url = b.NullableUrl ?? "(missing)" }).ToListAsync();
```

#### OCaml (typed-sql)

```ocaml
# let ef47 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> order_by Blog.id `Asc
      |> limit 10
      |> offset 5
      |> select (fun blog ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Blog.id blog)
        and+ projected_right =
          Projection.expr
            (Expr.coalesce
               (Blog.nullable_url blog)
               ~default:(Expr.constant Db_type.text "(missing)"))
        in
        projected_left, projected_right))
val ef47 : (unit, (int64 * string) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef47);;
SELECT
  t0."BlogId",
  COALESCE(t0."NullableUrl", $1)
FROM "Blogs" AS t0
ORDER BY
  t0."BlogId" ASC
LIMIT $2
OFFSET $3
```

### EF-48. CTE с рейтингом блога

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Complex Query Operators](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators).
- Проверяет: CTE relation, внешний фильтр и сортировку.

```sql
WITH selected AS (SELECT BlogId, Rating FROM Blogs WHERE Rating >= 4)
SELECT BlogId, Rating FROM selected ORDER BY Rating DESC
```

```csharp
var blogs = await context.Blogs.Where(b => b.Rating >= 4)
    .OrderByDescending(b => b.Rating).Select(b => new { b.BlogId, b.Rating }).ToListAsync();
```

#### OCaml (typed-sql)

```ocaml
let ef48_relation =
  Derived_table.create
    ~table:Blog.table
    ~columns:(fun blog ->
      let open Projection.Let_syntax in
      let+ projected_left = Projection.expr (Blog.id blog)
      and+ projected_right = Projection.expr (Blog.rating blog) in
      projected_left, projected_right)
    Query.(
      from Blog.table
      |> where (fun blog -> Blog.rating blog >=$ 4)
      |> select (fun blog ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Blog.id blog)
        and+ projected_right = Projection.expr (Blog.rating blog) in
        projected_left, projected_right))
;;

let ef48_cte = Cte.select ef48_relation
```

```ocaml
# let ef48 =
  Statement.query_many
    ~dialect:Dialect.portable
    (Cte.with_result ef48_cte ~f:(fun selected ->
       Query.(
         from_cte selected
         |> order_by Blog.rating `Desc
         |> select (fun blog ->
           let open Projection.Let_syntax in
           let+ projected_left = Projection.expr (Blog.id blog)
           and+ projected_right = Projection.expr (Blog.rating blog) in
           projected_left, projected_right))))
val ef48 : (unit, (int64 * int) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef48);;
WITH
  "c0" (
    "BlogId",
    "Rating"
  ) AS (
    SELECT
      t0."BlogId",
      t0."Rating"
    FROM "Blogs" AS t0
    WHERE
      (t0."Rating" >= $1)
  )
SELECT
  t0."BlogId",
  t0."Rating"
FROM "c0" AS t0
ORDER BY
  t0."Rating" DESC
```

### EF-49. UNION ALL идентификаторов блогов и публикаций

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [LINQ Concat](https://learn.microsoft.com/en-us/dotnet/api/system.linq.queryable.concat).
- Проверяет: совместимую проекцию и сохранение дублей через `UNION ALL`.

```sql
SELECT BlogId FROM Blogs WHERE Rating >= 4
UNION ALL SELECT BlogId FROM Posts WHERE Rating >= 4
```

```csharp
var ids = context.Blogs.Where(b => b.Rating >= 4).Select(b => b.BlogId)
    .Concat(context.Posts.Where(p => p.Rating >= 4).Select(p => p.BlogId));
```

#### OCaml (typed-sql)

```ocaml
let ef49_blogs =
  Query.(
    from Blog.table
    |> where (fun blog -> Blog.rating blog >=$ 4)
    |> select (fun blog -> Projection.expr (Blog.id blog)))
;;

let ef49_posts =
  Query.(
    from Post.table
    |> where (fun post -> Post.rating post >=$ 4)
    |> select (fun post -> Projection.expr (Post.blog_id post)))
;;
```

```ocaml
# let ef49 =
  Statement.query_many ~dialect:Dialect.portable (Query.union_all ef49_blogs ef49_posts)
val ef49 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef49);;
SELECT *
FROM (
  SELECT
    t0."BlogId"
  FROM "Blogs" AS t0
  WHERE
    (t0."Rating" >= $1)
) AS s0
UNION ALL
SELECT *
FROM (
  SELECT
    t0."BlogId"
  FROM "Posts" AS t0
  WHERE
    (t0."Rating" >= $2)
) AS s0
```

### EF-50. Блоги минимум с двумя публикациями

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [aggregate functions](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators#aggregate-functions).
- Проверяет: LEFT JOIN, подсчёт дочерних строк, HAVING и сортировку.

```sql
SELECT Blogs.BlogId, COUNT(Posts.PostId)
FROM Blogs LEFT JOIN Posts ON Posts.BlogId = Blogs.BlogId
GROUP BY Blogs.BlogId HAVING COUNT(Posts.PostId) >= 2 ORDER BY Blogs.BlogId
```

```csharp
var counts = await context.Blogs.Select(b => new { b.BlogId, Count = b.Posts.Count() })
    .Where(x => x.Count >= 2).OrderBy(x => x.BlogId).ToListAsync();
```

#### OCaml (typed-sql)

```ocaml
# let ef50 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Blog.table
      |> left_join Post.table ~on:(fun blog post -> Blog.id blog =. Post.blog_id post)
      |> group_by (fun (blog, _post) -> Blog.id blog)
      |> having (fun (_blog, post) -> Expr.count (Post.nullable_id post) >=$ 2L)
      |> order_by (fun (blog, _post) -> Blog.id blog) `Asc
      |> select (fun (blog, post) ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Blog.id blog)
        and+ projected_right = Projection.expr (Expr.count (Post.nullable_id post)) in
        projected_left, projected_right))
val ef50 : (unit, (int64 * int64) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ef50);;
SELECT
  t0."BlogId",
  COUNT(t1."PostId")
FROM "Blogs" AS t0
LEFT JOIN "Posts" AS t1
  ON (t0."BlogId" = t1."BlogId")
GROUP BY
  t0."BlogId"
HAVING
  (COUNT(t1."PostId") >= $1)
ORDER BY
  t0."BlogId" ASC
```
