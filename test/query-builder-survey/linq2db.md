<!-- SPDX-License-Identifier: MIT -->

# Сценарии запросов из LINQ to DB

Пять сценариев по [руководствам LINQ to DB](https://linq2db.github.io/) (доступ 28.09.2026). Примеры C# сокращены и адаптированы; SQL показывает структуру запроса. Для каждого сценария приведены реализация на typed-sql и SQL, полученный его компилятором для PostgreSQL.

Источник: проект LINQ to DB, лицензия [MIT](https://github.com/linq2db/linq2db/blob/master/LICENSE). Используется схема `author(id, name)` и `book(id, author_id, title, published_in)`. Идентификаторы и годы имеют тип `int64`.

В блоках «SQL typed-sql» первая строка запускает компилятор, остальные строки — его вывод. Выполнить сценарии можно командой `opam exec -- dune runtest test/query-builder-survey`.

## Общие дескрипторы для LD-01–LD-05

```ocaml
open! Base
open Typed_sql
open Infix

module Author = struct
  type row

  let table : row Table.t = Table.v_exn "author"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let id row = Expr.column row id_column
  let name row = Expr.column row name_column
end

module Book = struct
  type row

  let table : row Table.t = Table.v_exn "book"
  let id_column = Column.v_exn table "id" Db_type.int64
  let author_id_column = Column.v_exn table "author_id" Db_type.int64
  let title_column = Column.v_exn table "title" Db_type.text
  let published_in_column = Column.v_exn table "published_in" Db_type.int64
  let id row = Expr.column row id_column
  let author_id row = Expr.column row author_id_column
  let title row = Expr.column row title_column
  let published_in row = Expr.column row published_in_column
end

module Recent_book = struct
  type row

  let table : row Table.t = Table.v_exn "recent_books"
  let id_column = Column.v_exn table "id" Db_type.int64
  let title_column = Column.v_exn table "title" Db_type.text
  let id row = Expr.column row id_column
  let title row = Expr.column row title_column
  let projection row = Projection.pair (id row) (title row)
end
```

### LD-01. Фильтр, проекция и сортировка

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [LINQ to DB: rich querying API](https://linq2db.github.io/).
- Проверяет: сравнение с bind-параметром, проекцию и сортировку по убыванию.

```sql
SELECT b.id, b.title
FROM book AS b
WHERE b.published_in > @minYear
ORDER BY b.published_in DESC
```

```csharp
var query = from b in db.GetTable<Book>()
            where b.PublishedIn > minYear
            orderby b.PublishedIn descending
            select new { b.Id, b.Title };
```

#### OCaml (typed-sql)

Год передаётся statement как типизированный bind-параметр.

```ocaml
let ld01 =
  Statement.Portable.query_many_exn (fun params ->
    let minimum_year = params.expr Db_type.int64 ~get:Fn.id in
    Query.(
      from Book.table
      |> where (fun book -> Book.published_in book >. minimum_year)
      |> order_by Book.published_in `Desc
      |> select (fun book ->
        Projection.pair (Book.id book) (Book.title book))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ld01);;
SELECT
  t0."id",
  t0."title"
FROM "book" AS t0
WHERE
  (t0."published_in" > $1)
ORDER BY
  t0."published_in" DESC
```

### LD-02. INNER JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Join Operators](https://linq2db.github.io/articles/sql/Join-Operators.html).
- Проверяет: внутреннее соединение книг с авторами по внешнему ключу.

```sql
SELECT a.name, b.title
FROM author AS a
INNER JOIN book AS b ON b.author_id = a.id
```

```csharp
var query = from a in db.GetTable<Author>()
            join b in db.GetTable<Book>() on a.Id equals b.AuthorId
            select new { a.Name, b.Title };
```

#### OCaml (typed-sql)

```ocaml
let ld02 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Author.table
      |> inner_join Book.table ~on:(fun author book ->
        Book.author_id book =. Author.id author)
      |> select (fun (author, book) ->
        Projection.pair (Author.name author) (Book.title book))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ld02);;
SELECT
  t0."name",
  t1."title"
FROM "author" AS t0
INNER JOIN "book" AS t1
  ON (t1."author_id" = t0."id")
```

### LD-03. Группировка и HAVING

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Queryable.GroupBy](https://learn.microsoft.com/en-us/dotnet/api/system.linq.queryable.groupby).
- Проверяет: подсчёт книг на автора и фильтрацию групп.

```sql
SELECT b.author_id, COUNT(*)
FROM book AS b
GROUP BY b.author_id
HAVING COUNT(*) >= @minimumCount
ORDER BY b.author_id
```

```csharp
var query = from b in db.GetTable<Book>()
            group b by b.AuthorId into g
            where g.Count() >= minimumCount
            orderby g.Key
            select new { AuthorId = g.Key, Count = g.Count() };
```

#### OCaml (typed-sql)

```ocaml
let ld03 =
  Statement.Portable.query_many_exn (fun params ->
    let minimum_count = params.expr Db_type.int64 ~get:Fn.id in
    Query.(
      from Book.table
      |> group_by Book.author_id
      |> having (fun _ -> Expr.count_all >=. minimum_count)
      |> order_by Book.author_id `Asc
      |> select (fun book ->
        Projection.pair (Book.author_id book) Expr.count_all)))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ld03);;
SELECT
  t0."author_id",
  COUNT(*)
FROM "book" AS t0
GROUP BY
  t0."author_id"
HAVING
  (COUNT(*) >= $1)
ORDER BY
  t0."author_id" ASC
```

### LD-04. CTE

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Common Table Expressions](https://linq2db.github.io/articles/sql/CTE.html).
- Проверяет: именованное промежуточное отношение, построенное из SELECT.

```sql
WITH recent_books AS (
  SELECT b.id, b.title
  FROM book AS b
  WHERE b.published_in > 2000
)
SELECT r.id, r.title
FROM recent_books AS r
```

```csharp
var recent = db.GetTable<Book>()
    .Where(b => b.PublishedIn > 2000)
    .Select(b => new { b.Id, b.Title })
    .AsCte("recent_books");
var query = from b in recent select new { b.Id, b.Title };
```

#### OCaml (typed-sql)

```ocaml
let ld04_relation =
  Derived_table.create
    ~table:Recent_book.table
    ~columns:Recent_book.projection
    Query.(
      from Book.table
      |> where (fun book -> Book.published_in book >$ 2000L)
      |> select (fun book ->
        Projection.pair (Book.id book) (Book.title book)))

let ld04 =
  Statement.Portable.query_many_exn (fun _ ->
    Cte.with_result (Cte.select ld04_relation) ~f:(fun recent_books ->
      Query.(
        from_cte recent_books
        |> select Recent_book.projection)))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ld04);;
WITH
  "c0" (
    "id",
    "title"
  ) AS (
    SELECT
      t0."id",
      t0."title"
    FROM "book" AS t0
    WHERE
      (t0."published_in" > $1)
  )
SELECT
  t0."id",
  t0."title"
FROM "c0" AS t0
```

### LD-05. Коррелированный EXISTS

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Queryable.Any](https://learn.microsoft.com/en-us/dotnet/api/system.linq.queryable.any).
- Проверяет: выбрать авторов, у которых есть хотя бы одна книга.

```sql
SELECT a.id, a.name
FROM author AS a
WHERE EXISTS (
  SELECT 1 FROM book AS b WHERE b.author_id = a.id
)
```

```csharp
var query = db.GetTable<Author>()
    .Where(a => db.GetTable<Book>().Any(b => b.AuthorId == a.Id))
    .Select(a => new { a.Id, a.Name });
```

#### OCaml (typed-sql)

Внутренний SELECT захватывает строку автора из внешнего запроса.

```ocaml
let ld05 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Author.table
      |> where (fun author ->
        exists
          (from Book.table
           |> where (fun book ->
             Book.author_id book =. Author.id author)))
      |> select (fun author ->
        Projection.pair (Author.id author) (Author.name author))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ld05);;
SELECT
  t0."id",
  t0."name"
FROM "author" AS t0
WHERE
  (EXISTS (
    SELECT
      1
    FROM "book" AS t1
    WHERE
      (t1."author_id" = t0."id")
  ))
```
