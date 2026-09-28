<!-- SPDX-License-Identifier: MIT -->

# Сценарии запросов из SqlKata

Пять сценариев по [документации SqlKata](https://sqlkata.com/docs) (доступ 28.09.2026). Примеры C# сокращены и адаптированы. Для каждого сценария приведены реализация на typed-sql и SQL, полученный его компилятором для PostgreSQL.

Источник: проект SqlKata, лицензия [MIT](https://github.com/sqlkata/querybuilder/blob/main/LICENSE). Используется схема `author(id, name)` и `book(id, author_id, title, published_in)`; идентификаторы и годы имеют тип `int64`.

В блоках «SQL typed-sql» первая строка запускает компилятор, остальные строки — его вывод. Выполнить сценарии можно командой `opam exec -- dune runtest test/query-builder-survey`.

## Общие дескрипторы для SK-01–SK-05

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

module Book_counts = struct
  type row

  let table : row Table.t = Table.v_exn "book_counts"
  let author_id_column = Column.v_exn table "author_id" Db_type.int64
  let book_count_column = Column.v_exn table "book_count" Db_type.int64
  let author_id row = Expr.column row author_id_column
  let book_count row = Expr.column row book_count_column
  let projection row = Projection.pair (author_id row) (book_count row)
end
```

### SK-01. Фильтр и проекция

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Where](https://sqlkata.com/docs/where).
- Проверяет: выбрать издания после заданного года и вернуть заголовки.

```sql
SELECT id, title
FROM book
WHERE published_in > @minYear
```

```csharp
var query = new Query("book")
    .Select("id", "title")
    .Where("published_in", ">", minYear);
```

#### OCaml (typed-sql)

```ocaml
let sk01 =
  Statement.Portable.query_many_exn (fun params ->
    let minimum_year = params.expr Db_type.int64 ~get:Fn.id in
    Query.(
      from Book.table
      |> where (fun book -> Book.published_in book >. minimum_year)
      |> select (fun book ->
        Projection.pair (Book.id book) (Book.title book))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql sk01);;
SELECT
  t0."id",
  t0."title"
FROM "book" AS t0
WHERE
  (t0."published_in" > $1)
```

### SK-02. Условный фильтр

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Advanced: conditional clauses](https://sqlkata.com/docs/advanced).
- Проверяет: добавление условия только если параметр задан.

```sql
SELECT id
FROM book
-- при minYear = 2000:
WHERE published_in >= @minYear
-- при отсутствии minYear предложение WHERE опускается
```

```csharp
var query = new Query("book")
    .Select("id")
    .When(minYear.HasValue,
        q => q.Where("published_in", ">=", minYear.Value));
```

#### OCaml (typed-sql)

`where_opt` меняет форму SQL, поэтому запрос строится динамически.

```ocaml
let sk02 =
  Statement.Dynamic.Portable.query_many (fun minimum_year ->
    Query.(
      from Book.table
      |> where_opt minimum_year ~f:(fun book year ->
        Book.published_in book >=$ year)
      |> select (fun book -> Projection.expr (Book.id book))))
```

#### SQL typed-sql (PostgreSQL, фильтр есть)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:(Some 2000L) sk02);;
SELECT
  t0."id"
FROM "book" AS t0
WHERE
  (t0."published_in" >= $1)
```

#### SQL typed-sql (PostgreSQL, фильтра нет)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:None sk02);;
SELECT
  t0."id"
FROM "book" AS t0
```

### SK-03. Сгруппированное условие

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Nested where conditions](https://sqlkata.com/docs/where#nested-conditions).
- Проверяет: `OR` внутри группы условий `AND`.

```sql
SELECT id
FROM book
WHERE (published_in = @year OR title = @title)
  AND author_id > @authorId
```

```csharp
var query = new Query("book")
    .Select("id")
    .Where(q => q.Where("published_in", 2000)
                .OrWhere("title", "Typed SQL"))
    .Where("author_id", ">", 10);
```

#### OCaml (typed-sql)

```ocaml
let sk03 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Book.table
      |> where (fun book ->
        ((Book.published_in book =$ 2000L)
         ||. (Book.title book =$ "Typed SQL"))
        &&. (Book.author_id book >$ 10L))
      |> select (fun book -> Projection.expr (Book.id book))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql sk03);;
SELECT
  t0."id"
FROM "book" AS t0
WHERE
  (
    (
      (t0."published_in" = $1)
      OR (t0."title" = $2)
    )
    AND (t0."author_id" > $3)
  )
```

### SK-04. JOIN и страница

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Join](https://sqlkata.com/docs/join), [limit and offset](https://sqlkata.com/docs/limit).
- Проверяет: соединение с авторами и страницу с сортировкой.

```sql
SELECT author.name, book.title
FROM book
INNER JOIN author ON author.id = book.author_id
ORDER BY book.id
LIMIT 10 OFFSET 20
```

```csharp
var query = new Query("book")
    .Join("author", "author.id", "book.author_id")
    .Select("author.name", "book.title")
    .OrderBy("book.id")
    .Limit(10)
    .Offset(20);
```

#### OCaml (typed-sql)

```ocaml
let sk04 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Book.table
      |> inner_join Author.table ~on:(fun book author ->
        Book.author_id book =. Author.id author)
      |> order_by (fun (book, _author) -> Book.id book) `Asc
      |> limit 10
      |> offset 20
      |> select (fun (book, author) ->
        Projection.pair (Author.name author) (Book.title book))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql sk04);;
SELECT
  t1."name",
  t0."title"
FROM "book" AS t0
INNER JOIN "author" AS t1
  ON (t0."author_id" = t1."id")
ORDER BY
  t0."id" ASC
LIMIT 10
OFFSET 20
```

### SK-05. CTE с агрегацией и фильтром групп

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Common Table Expressions](https://sqlkata.com/docs/cte), [Having](https://sqlkata.com/docs/having).
- Проверяет: объявление CTE с количеством книг по автору и использование CTE.

```sql
WITH book_counts AS (
  SELECT author_id, COUNT(*) AS book_count
  FROM book
  GROUP BY author_id
  HAVING COUNT(*) >= @minimumCount
)
SELECT author_id, book_count
FROM book_counts
```

```csharp
var bookCounts = new Query("book")
    .Select("author_id")
    .SelectRaw("COUNT(*) AS book_count")
    .GroupBy("author_id")
    .HavingRaw("COUNT(*) >= ?", minimumCount);
var query = new Query()
    .With("book_counts", bookCounts)
    .From("book_counts")
    .Select("author_id", "book_count");
```

#### OCaml (typed-sql)

```ocaml
let sk05 =
  Statement.Portable.query_many_exn (fun params ->
    let minimum_count = params.expr Db_type.int64 ~get:Fn.id in
    let book_counts_relation =
      Derived_table.create
        ~table:Book_counts.table
        ~columns:Book_counts.projection
        Query.(
          from Book.table
          |> group_by Book.author_id
          |> having (fun _ -> Expr.count_all >=. minimum_count)
          |> select (fun book ->
            Projection.pair (Book.author_id book) Expr.count_all))
    in
    Cte.with_result (Cte.select book_counts_relation) ~f:(fun book_counts ->
      Query.(
        from_cte book_counts
        |> select Book_counts.projection)))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql sk05);;
WITH
  "c0" (
    "author_id",
    "book_count"
  ) AS (
    SELECT
      t0."author_id",
      COUNT(*)
    FROM "book" AS t0
    GROUP BY
      t0."author_id"
    HAVING
      (COUNT(*) >= $1)
  )
SELECT
  t0."author_id",
  t0."book_count"
FROM "c0" AS t0
```
