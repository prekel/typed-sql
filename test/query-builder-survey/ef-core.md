# Сценарии запросов из EF Core

Первые 15 сценариев из [документации EF Core](https://learn.microsoft.com/en-us/ef/core/) (доступ 28.09.2026). LINQ и SQL сокращены и адаптированы. SQL показывает существенную форму перевода, а не точный лог конкретной версии провайдера. Квадратные скобки и `@parameter` относятся к SQL Server; EF-10 использует синтаксис PostgreSQL, как в источнике. Условия переноса зависят от версии EF Core и провайдера, поэтому при дальнейшем сравнении нужно фиксировать оба.

**Желаемый таргет: 50–70 сценариев.**

Текст документации Microsoft / .NET team распространяется по [CC BY 4.0](https://github.com/dotnet/EntityFramework.Docs/blob/main/LICENSE), а [примеры кода — по MIT](https://github.com/dotnet/EntityFramework.Docs/blob/main/LICENSE-CODE), © Microsoft Corporation. Здесь примеры сокращены, проекции упрощены и добавлены критерии проверки. Уведомление MIT приведено в конце файла. Ссылки в каждой карточке ведут к разделу с контекстом.

Используются модели примеров `Blog`, `Post`, `Contributor` и `Book`. Карточки взяты из разных разделов документации; одноимённые модели не образуют единую схему. Для outer join и загрузки коллекций нужна фикстура с пустой коллекцией. Для клиентских операций проверять и SQL, и итоговый результат.

Для всех сценариев, которые поддерживает текущий публичный API, ниже добавлены реализации на typed-sql и SQL, полученный компилятором. Для частично поддерживаемых сценариев отдельно описаны границы совпадения. В блоках «SQL typed-sql» первая строка запускает компилятор, остальные строки — его вывод. Запустить проверку можно командой `opam exec -- dune runtest test/query-builder-survey`.

Статусы в карточках: `✓` — подтверждено; `✗` — условие не выполнено; `—` — не оценивалось. «Семантика» учитывает входные параметры, результат, `NULL` и заданный порядок относительно серверного запроса в карточке; клиентская сборка объектов EF Core сюда не входит. «Без доработок» относится к публичному API typed-sql, а не к необходимости улучшить пример. Реализуемость оценивается после попытки написать OCaml-код.

## Общие дескрипторы

Эти descriptors используются во всех пяти примерах этого файла.

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
- Семантика: ✗
- Без доработок typed-sql: ✓
- Замечание: `skip` и `take` заменены фиксированными `20` и `10`.
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

typed-sql рендерит portable PostgreSQL SQL. Здесь OFFSET и LIMIT задаются значениями при построении запроса.

```ocaml
let ef01 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Post.table
      |> order_by Post.id `Asc
      |> limit 10
      |> offset 20
      |> select (fun post -> Projection.expr (Post.id post))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef01);;
SELECT
  t0."PostId"
FROM "Posts" AS t0
ORDER BY
  t0."PostId" ASC
LIMIT 10
OFFSET 20
```

### EF-02. Keyset по двум колонкам

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✗
- Без доработок typed-sql: ✓
- Замечание: `lastDate`, `lastId` и `take` заменены фиксированными значениями.
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
let last_date =
  Ptime.of_date_time ((2020, 1, 1), ((0, 0, 0), 0)) |> Option.value_exn

let ef02 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Post.table
      |> where (fun post ->
        (Post.date post >$ last_date)
        ||. ((Post.date post =$ last_date) &&. (Post.id post >$ 55L)))
      |> order_by Post.date `Asc
      |> order_by Post.id `Asc
      |> limit 10
      |> select (fun post -> Projection.pair (Post.id post) (Post.date post))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef02);;
SELECT
  t0."PostId",
  t0."Date"
FROM "Posts" AS t0
WHERE
  (
    (t0."Date" > $1)
    OR (
      (t0."Date" = $2)
      AND (t0."PostId" > $3)
    )
  )
ORDER BY
  t0."Date" ASC,
  t0."PostId" ASC
LIMIT 10
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
let ef03 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Blog.table
      |> inner_join Post.table ~on:(fun blog post ->
        Blog.id blog =. Post.blog_id post)
      |> select (fun (blog, post) ->
        Projection.pair (Blog.id blog) (Post.id post))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef03);;
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
let ef04 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Blog.table
      |> left_join Post.table ~on:(fun blog post ->
        Blog.id blog =. Post.blog_id post)
      |> select (fun (blog, post) ->
        Projection.pair (Blog.id blog) (Post.nullable_id post))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef04);;
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
- Замечание: `INNER JOIN ... ON TRUE` вместо `CROSS JOIN`; строки совпадают.
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

В текущем DSL нет отдельного cross_join. Условие TRUE даёт то же декартово множество строк, но компилятор выводит INNER JOIN ... ON TRUE.

```ocaml
let ef05 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Blog.table
      |> inner_join Post.table ~on:(fun _blog _post -> Condition.true_)
      |> select (fun (blog, post) ->
        Projection.pair (Blog.id blog) (Post.id post))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef05);;
SELECT
  t0."BlogId",
  t1."PostId"
FROM "Blogs" AS t0
INNER JOIN "Posts" AS t1
  ON TRUE
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
let ef06 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Blog.table
      |> inner_join Post.table ~on:(fun blog post ->
        Blog.id blog =. Post.blog_id post)
      |> select (fun (blog, post) ->
        Projection.pair (Blog.id blog) (Post.id post))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef06);;
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
let ef07 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Blog.table
      |> inner_join Post.table ~on:(fun _blog _post -> Condition.true_)
      |> select (fun (blog, post) ->
        Projection.pair
          (Blog.id blog)
          (Expr.concat
             (Expr.concat_value (Blog.url blog) "=>")
             (Post.title post)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef07);;
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
let ef08 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Post.table
      |> group_by Post.author_id
      |> select (fun post ->
        Projection.pair (Post.author_id post) Expr.count_all)))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef08);;
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
let ef09 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Post.table
      |> group_by Post.author_id
      |> having (fun _ -> Expr.count_all >$ 2L)
      |> order_by Post.author_id `Asc
      |> select (fun post ->
        Projection.pair (Post.author_id post) Expr.count_all)))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef09);;
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
let ef10 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Blog.table
      |> where (fun blog ->
        let post_blog_ids =
          Query.(
            from Post.table
            |> select_scalar Post.blog_id)
        in
        Query.in_subquery (Blog.id blog) post_blog_ids)
      |> select (fun blog -> Projection.expr (Blog.id blog))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef10);;
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

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [GroupBy without aggregate](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators#groupby).
- Проверяет: различие между SQL-строками и итоговыми группами; EF Core 7+ собирает группы после чтения.

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
let ef11 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Book.table
      |> order_by Book.price `Asc
      |> select (fun book ->
        Projection.map3
          ~f:(fun price id author_id -> price, id, author_id)
          (Projection.expr (Book.price book))
          (Projection.expr (Book.id book))
          (Projection.expr (Book.author_id book)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef11);;
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
- Семантика: ✗
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
let ef12 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Blog.table
      |> left_join Post.table ~on:(fun blog post ->
        Blog.id blog =. Post.blog_id post)
      |> left_join Contributor.table ~on:(fun (blog, _post) contributor ->
        Blog.id blog =. Contributor.blog_id contributor)
      |> order_by (fun ((blog, _post), _contributor) -> Blog.id blog) `Asc
      |> order_by (fun ((_blog, post), _contributor) -> Post.nullable_id post) `Asc
      |> select (fun ((blog, post), contributor) ->
        Projection.map3
          ~f:(fun blog_id post_id contributor_id -> blog_id, post_id, contributor_id)
          (Projection.expr (Blog.id blog))
          (Projection.expr (Post.nullable_id post))
          (Projection.expr (Contributor.nullable_id contributor)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef12);;
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
- Семантика: ✗
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
let ef13_blogs =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Blog.table
      |> order_by Blog.id `Asc
      |> select (fun blog -> Projection.expr (Blog.id blog))))

let ef13_posts =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Blog.table
      |> inner_join Post.table ~on:(fun blog post ->
        Blog.id blog =. Post.blog_id post)
      |> order_by (fun (blog, _post) -> Blog.id blog) `Asc
      |> select (fun (blog, post) ->
        Projection.map3
          ~f:(fun post_id post_blog_id blog_id -> post_id, post_blog_id, blog_id)
          (Projection.expr (Post.id post))
          (Projection.expr (Post.blog_id post))
          (Projection.expr (Blog.id blog)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef13_blogs);;
SELECT
  t0."BlogId"
FROM "Blogs" AS t0
ORDER BY
  t0."BlogId" ASC
```

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef13_posts);;
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

- OCaml-пример: ✗
- Реализуемость: ✗
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [updating from related entities](https://learn.microsoft.com/en-us/ef/core/saving/execute-insert-update-delete#navigations-and-related-entities).
- Проверяет: выражение для `SET` на основе связанных строк и поведение при пустой коллекции.

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

Пример зависит от приведения типов у провайдера и может потребовать отдельной проверки пустой коллекции.

Текущий API не содержит `AVG` или преобразования типов для выражений. Воспроизвести выражение `SET` с таким агрегатом без расширения DSL нельзя.

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
let ef15 =
  Statement.Portable.command_exn (fun _ ->
    Delete.(
      from Blog.table
      |> where (fun blog -> Blog.rating blog <$ 3)
      |> command))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef15);;
DELETE FROM "Blogs"
WHERE
  ("Rating" < $1)
```

## Дополнительные сценарии

Карточки EF-16–EF-35 расширяют каталог новыми формами LINQ, материализации и provider-specific SQL. Для них намеренно не приводятся OCaml-примеры и не оценивается поддержка typed-sql.

### EF-16. Проекция только нужных столбцов

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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
let ef16 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Blog.table
      |> select (fun blog -> Projection.pair (Blog.id blog) (Blog.url blog))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef16);;
SELECT
  t0."BlogId",
  t0."Url"
FROM "Blogs" AS t0
```

### EF-17. StartsWith и индексируемый префикс

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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
let ef17 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Blog.table
      |> where (fun blog -> Blog.url blog =~$ "https://example.%")
      |> select (fun blog -> Projection.pair (Blog.id blog) (Blog.url blog))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef17);;
SELECT
  t0."BlogId",
  t0."Url"
FROM "Blogs" AS t0
WHERE
  (t0."Url" LIKE $1)
```

### EF-18. Any как EXISTS

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

Условие существования помещено в `CASE`, чтобы проекция оставалась списком bool, как в LINQ-примере.

```ocaml
let ef18 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Blog.table
      |> select (fun blog ->
        Projection.expr
          (Expr.case
             [ ( Query.exists
                   Query.(
                     from Post.table
                     |> where (fun post -> Post.blog_id post =. Blog.id blog))
               , Expr.constant Db_type.bool true ) ]
             ~else_:(Expr.constant Db_type.bool false)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef18);;
SELECT
  (CASE
    WHEN (EXISTS (
      SELECT
        1
      FROM "Posts" AS t1
      WHERE
        (t1."BlogId" = t0."BlogId")
    )) THEN $1
    ELSE $2
  END)
FROM "Blogs" AS t0
```

### EF-19. All как NOT EXISTS нарушения предиката

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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
let ef19 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Blog.table
      |> select (fun blog ->
        Projection.expr
          (Expr.case
             [ ( Query.not_exists
                   Query.(
                     from Post.table
                     |> where (fun post ->
                       (Post.blog_id post =. Blog.id blog) &&. (Post.rating post <=$ 3)))
               , Expr.constant Db_type.bool true ) ]
             ~else_:(Expr.constant Db_type.bool false)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef19);;
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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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
let ef20 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Post.table
      |> distinct
      |> select (fun post -> Projection.expr (Post.author_id post))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef20);;
SELECT DISTINCT
  t0."AuthorId"
FROM "Posts" AS t0
```

### EF-21. Счётчик строк без материализации

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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
let ef21 =
  Statement.Portable.query_one_exn (fun _ ->
    Query.Aggregate.(
      from Post.table
      |> where (fun post -> Post.blog_id post =$ 7L)
      |> Query.aggregate_one (fun _ -> Aggregate_projection.count_all)))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef21);;
SELECT
  COUNT(*)
FROM "Posts" AS t0
WHERE
  (t0."BlogId" = $1)
```

### EF-22. Последняя запись с FirstOrDefault

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

`limit_one` доказывает верхнюю границу, а `query_optional_exn` возвращает `None` при отсутствии подходящей строки.

```ocaml
let ef22 =
  Statement.Portable.query_optional_exn (fun _ ->
    Query.(
      from Post.table
      |> where (fun post -> Post.blog_id post =$ 7L)
      |> order_by Post.date `Desc
      |> order_by Post.id `Desc
      |> limit_one
      |> select (fun post ->
        Projection.map3
          ~f:(fun id title date -> id, title, date)
          (Projection.expr (Post.id post))
          (Projection.expr (Post.title post))
          (Projection.expr (Post.date post)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef22);;
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
LIMIT 1
```

### EF-23. Равенство nullable-значений

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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
let ef23 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Post.table
      |> where (fun post ->
        Condition.not_
          (Expr.is_distinct_from
             (Post.optional_rating post)
             (Expr.constant (Db_type.option Db_type.int) (Some 3))))
      |> select (fun post -> Projection.expr (Post.id post))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef23);;
SELECT
  t0."PostId"
FROM "Posts" AS t0
WHERE
  (NOT (t0."OptionalRating" IS DISTINCT FROM $1))
```

### EF-24. Null-coalescing в проекции

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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
let ef24 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Blog.table
      |> select (fun blog ->
        Projection.expr
          (Expr.coalesce
             (Blog.nullable_url blog)
             ~default:(Expr.constant Db_type.text "(missing)")))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef24);;
SELECT
  COALESCE(t0."NullableUrl", $1)
FROM "Blogs" AS t0
```

### EF-25. Условная проекция в CASE

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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
let ef25 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Blog.table
      |> select (fun blog ->
        Projection.expr
          (Expr.case
             [ (Blog.rating blog >=$ 4, Expr.constant Db_type.text "popular") ]
             ~else_:(Expr.constant Db_type.text "other")))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef25);;
SELECT
  (CASE
    WHEN (t0."Rating" >= $1) THEN $2
    ELSE $3
  END)
FROM "Blogs" AS t0
```

### EF-26. Глобальный фильтр soft delete

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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
let ef26 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Blog.table
      |> where (fun blog -> Blog.is_deleted blog =$ false)
      |> select (fun blog -> Projection.pair (Blog.id blog) (Blog.url blog))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef26);;
SELECT
  t0."BlogId",
  t0."Url"
FROM "Blogs" AS t0
WHERE
  (t0."IsDeleted" = $1)
```

### EF-27. Filtered Include для коллекции

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [Eager Loading: filtered include](https://learn.microsoft.com/en-us/ef/core/querying/related-data/eager#filtered-include).
- Проверяет: фильтрацию, сортировку и ограничение элементов включённой коллекции.

```sql
SELECT [b].[BlogId], [b].[Url], [t].[PostId], [t].[BlogId], [t].[Title]
FROM [Blogs] AS [b]
LEFT JOIN (
  SELECT [t0].[PostId], [t0].[BlogId], [t0].[Title]
  FROM (
    SELECT [p].[PostId], [p].[BlogId], [p].[Title],
      ROW_NUMBER() OVER(PARTITION BY [p].[BlogId] ORDER BY [p].[Title] DESC) AS [row]
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
        .Take(5))
    .ToListAsync();
```

Провайдер может использовать `ROW_NUMBER` или `APPLY` для per-blog `Take(5)`; проверять конкретный SQL отдельно.

#### OCaml (typed-sql, фильтр без per-blog Take)

Фильтр размещён в `ON`, поэтому блог сохраняется даже при отсутствии подходящих постов. API не поддерживает per-parent `Take(5)` без оконной функции.

```ocaml
let ef27 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Blog.table
      |> left_join Post.table ~on:(fun blog post ->
        (Blog.id blog =. Post.blog_id post) &&. (Post.rating post >=$ 4))
      |> order_by (fun (blog, _post) -> Blog.id blog) `Asc
      |> select (fun (blog, post) ->
        Projection.pair (Blog.id blog) (Post.nullable_id post))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef27);;
SELECT
  t0."BlogId",
  t1."PostId"
FROM "Blogs" AS t0
LEFT JOIN "Posts" AS t1
  ON (
    (t0."BlogId" = t1."BlogId")
    AND (t1."Rating" >= $1)
  )
ORDER BY
  t0."BlogId" ASC
```

### EF-28. Include и ThenInclude

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [Eager Loading: including multiple levels](https://learn.microsoft.com/en-us/ef/core/querying/related-data/eager#including-multiple-levels).
- Проверяет: загрузку цепочки Blog → Posts → Author одним запросом.

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
let ef28 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Blog.table
      |> left_join Post.table ~on:(fun blog post ->
        Blog.id blog =. Post.blog_id post)
      |> left_join Author.table ~on:(fun ((_blog, post)) author ->
        Post.nullable_author_id post =. Expr.to_nullable (Author.id author))
      |> order_by (fun ((blog, _post), _author) -> Blog.id blog) `Asc
      |> order_by (fun ((_blog, post), _author) -> Post.nullable_id post) `Asc
      |> select (fun ((_blog, post), author) ->
        Projection.pair (Post.nullable_id post) (Author.nullable_id author))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef28);;
SELECT
  t1."PostId",
  t2."AuthorId"
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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [Tracking vs. No-Tracking Queries](https://learn.microsoft.com/en-us/ef/core/querying/tracking).
- Проверяет: одинаковый серверный запрос при разной работе change tracker и identity resolution.

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

### EF-30. Клиентский helper в верхней проекции

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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
let ef30_query =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Blog.table
      |> order_by (fun blog -> Blog.rating blog) `Desc
      |> select (fun blog -> Projection.pair (Blog.id blog) (Blog.url blog))))

let ef30_standardize url = Stdlib.String.lowercase_ascii url

let ef30_client_projection rows =
  List.map rows ~f:(fun (id, url) -> id, ef30_standardize url)
```

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ef30_query);;
SELECT
  t0."BlogId",
  t0."Url"
FROM "Blogs" AS t0
ORDER BY
  t0."Rating" DESC
```

### EF-31. Непереводимый helper в WHERE

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [Client vs. Server Evaluation: unsupported client evaluation](https://learn.microsoft.com/en-us/ef/core/querying/client-eval#unsupported-client-evaluation).
- Проверяет: исключение при непереводимом выражении вне верхней проекции, вместо незаметной клиентской фильтрации.

```csharp
var blogs = await context.Blogs
    .Where(b => StandardizeUrl(b.Url) == requestedUrl)
    .ToListAsync();
```

Для актуального EF Core ожидается ошибка трансляции до выполнения запроса. Отдельный вариант с `AsEnumerable()` проверяет явный переход к клиентской фильтрации и риск загрузки всей таблицы.

### EF-32. Contains по параметрической коллекции (EF Core 8)

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [What's New in EF Core 8: primitive collections](https://learn.microsoft.com/en-us/ef/core/what-is-new/ef-core-8.0/whatsnew#primitive-collections).
- Проверяет: передачу списка одним JSON параметром, кэшируемую форму SQL и зависимость от уровня совместимости SQL Server.

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
let ef32 =
  Statement.Dynamic.Portable.query_many (fun terrain_ids ->
    Query.(
      from Book.table
      |> where (fun book -> Expr.in_ (Book.author_id book) terrain_ids)
      |> select (fun book -> Projection.expr (Book.id book))))
```

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:[ 1L; 5L; 4L ] ef32);;
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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [What's New in EF Core 8: primitive collections](https://learn.microsoft.com/en-us/ef/core/what-is-new/ef-core-8.0/whatsnew#primitive-collections-in-json-columns).
- Проверяет: разворачивание JSON массива колонки и сравнение с параметром.

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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [User-defined function mapping](https://learn.microsoft.com/en-us/ef/core/querying/user-defined-function-mapping#mapping-a-method-to-a-sql-function).
- Проверяет: отображение метода модели на схематизированную скалярную SQL-функцию.

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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [SQL Queries: composing with LINQ](https://learn.microsoft.com/en-us/ef/core/querying/sql-queries#composing-with-linq).
- Проверяет: обёртку raw SQL как подзапрос и добавление LINQ фильтра и сортировки снаружи.

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
