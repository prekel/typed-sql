# Сценарии запросов из EF Core

Первые 15 сценариев из [документации EF Core](https://learn.microsoft.com/en-us/ef/core/) (доступ 28.09.2026). LINQ и SQL сокращены и адаптированы. SQL показывает существенную форму перевода, а не точный лог конкретной версии провайдера. Квадратные скобки и `@parameter` относятся к SQL Server; EF-10 использует синтаксис PostgreSQL, как в источнике. Условия переноса зависят от версии EF Core и провайдера, поэтому при дальнейшем сравнении нужно фиксировать оба.

**Желаемый таргет: 50–70 сценариев.**

Текст документации Microsoft / .NET team распространяется по [CC BY 4.0](https://github.com/dotnet/EntityFramework.Docs/blob/main/LICENSE), а [примеры кода — по MIT](https://github.com/dotnet/EntityFramework.Docs/blob/main/LICENSE-CODE), © Microsoft Corporation. Здесь примеры сокращены, проекции упрощены и добавлены критерии проверки. Уведомление MIT приведено в конце файла. Ссылки в каждой карточке ведут к разделу с контекстом.

Используются модели примеров `Blog`, `Post`, `Contributor` и `Book`. Карточки взяты из разных разделов документации; одноимённые модели не образуют единую схему. Для outer join и загрузки коллекций нужна фикстура с пустой коллекцией. Для клиентских операций проверять и SQL, и итоговый результат.

Для EF-01–EF-05 ниже добавлены реализация на typed-sql и SQL, полученный её компилятором. В блоках «SQL typed-sql» первая строка запускает компилятор, остальные строки — его вывод. Запустить проверку можно командой `opam exec -- dune runtest doc/query-builder-survey`.

Статусы в карточках: `✓` — подтверждено; `✗` — условие не выполнено; `—` — не оценивалось. «Семантика» учитывает входные параметры, результат, `NULL` и заданный порядок относительно серверного запроса в карточке; клиентская сборка объектов EF Core сюда не входит. «Без доработок» относится к публичному API typed-sql, а не к необходимости улучшить пример. Реализуемость оценивается после попытки написать OCaml-код.

## Общие дескрипторы для EF-01–EF-05

Эти descriptors используются во всех пяти примерах этого файла.

```ocaml
open! Base
open Typed_sql
open Infix

module Blog = struct
  type row

  let table : row Table.t = Table.v_exn "Blogs"
  let id_column = Column.v_exn table "BlogId" Db_type.int64
  let id row = Expr.column row id_column
end

module Post = struct
  type row

  let table : row Table.t = Table.v_exn "Posts"
  let id_column = Column.v_exn table "PostId" Db_type.int64
  let blog_id_column = Column.v_exn table "BlogId" Db_type.int64
  let date_column = Column.v_exn table "Date" Db_type.timestamp
  let id row = Expr.column row id_column
  let blog_id row = Expr.column row blog_id_column
  let date row = Expr.column row date_column
  let nullable_id row = Expr.nullable_column row id_column
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

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —

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

### EF-07. Коррелированная проекция как APPLY

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —

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

### EF-08. GROUP BY с COUNT

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —

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

### EF-09. HAVING после группировки

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —

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

### EF-10. Подзапрос в IN

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —

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

### EF-12. Include двух соседних коллекций

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —

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

### EF-13. Split query для коллекции

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —

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

### EF-14. ExecuteUpdate с коррелированным агрегатом

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —

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

### EF-15. ExecuteDelete

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —

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
