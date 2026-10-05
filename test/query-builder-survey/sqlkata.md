<!-- SPDX-License-Identifier: MIT -->

  # Сценарии запросов из SqlKata

Десять сценариев по [документации SqlKata](https://sqlkata.com/docs) (доступ 28.09.2026). Примеры C# сокращены и адаптированы. Для поддерживаемых сценариев приведены реализация на typed-sql и SQL, полученный его компилятором для PostgreSQL.

Источник: проект SqlKata, лицензия [MIT](https://github.com/sqlkata/querybuilder/blob/main/LICENSE). Используется схема `author(id, name)` и `book(id, author_id, title, published_in)`; для SK-09 добавлена таблица `book_archive` с теми же колонками, что у `book`. Идентификаторы и годы имеют тип `int64`.

В блоках «SQL typed-sql» первая строка запускает компилятор, остальные строки — его вывод. Выполнить сценарии можно командой `opam exec -- dune runtest test/query-builder-survey`.

## Общие дескрипторы для SK-01–SK-10

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

module Book_archive = struct
  type row

  let table : row Table.t = Table.v_exn "book_archive"
  let id_column = Column.v_exn table "id" Db_type.int64
  let author_id_column = Column.v_exn table "author_id" Db_type.int64
  let title_column = Column.v_exn table "title" Db_type.text
  let published_in_column = Column.v_exn table "published_in" Db_type.int64
end

module Book_counts = struct
  type row

  let table : row Table.t = Table.v_exn "book_counts"
  let author_id_column = Column.v_exn table "author_id" Db_type.int64
  let book_count_column = Column.v_exn table "book_count" Db_type.int64
  let author_id row = Expr.column row author_id_column
  let book_count row = Expr.column row book_count_column

  let projection row =
    let open Projection.Let_syntax in
    let+ projected_left = Projection.expr (author_id row)
    and+ projected_right = Projection.expr (book_count row) in
    projected_left, projected_right
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
# let sk01 =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let open Parameters.Let_syntax in
    let+ minimum_year = params.expr Db_type.int64 ~get:Fn.id in
    params.query_many
      Query.(
        from Book.table
        |> where (fun book -> Book.published_in book >. minimum_year)
        |> select (fun book ->
          let open Projection.Let_syntax in
          let+ projected_left = Projection.expr (Book.id book)
          and+ projected_right = Projection.expr (Book.title book) in
          projected_left, projected_right)))
val sk01 : (int64, (int64 * string) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sk01);;
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
# let sk02 =
  Statement.Dynamic.query_many ~dialect:Dialect.portable (fun minimum_year ->
    Query.(
      from Book.table
      |> where_opt minimum_year ~f:(fun book year -> Book.published_in book >=$ year)
      |> select (fun book -> Projection.expr (Book.id book))))
val sk02 : (int64 option, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL, фильтр есть)

```ocaml
# let () =
  Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ~input:(Some 2000L) sk02);;
SELECT
  t0."id"
FROM "book" AS t0
WHERE
  (t0."published_in" >= $1)
```

#### SQL typed-sql (PostgreSQL, фильтра нет)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ~input:None sk02);;
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
# let sk03 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Book.table
      |> where (fun book ->
        Book.published_in book
        =$ 2000L
        ||. (Book.title book =$ "Typed SQL")
        &&. (Book.author_id book >$ 10L))
      |> select (fun book -> Projection.expr (Book.id book)))
val sk03 : (unit, int64 list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sk03);;
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
# let sk04 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Book.table
      |> inner_join Author.table ~on:(fun book author ->
        Book.author_id book =. Author.id author)
      |> order_by (fun (book, _author) -> Book.id book) `Asc
      |> limit 10
      |> offset 20
      |> select (fun (book, author) ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Author.name author)
        and+ projected_right = Projection.expr (Book.title book) in
        projected_left, projected_right))
val sk04 : (unit, (string * string) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sk04);;
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
# let sk05 =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let open Parameters.Let_syntax in
    let+ minimum_count = params.expr Db_type.int64 ~get:Fn.id in
    params.query_many
      (let book_counts_relation =
         Derived_table.create
           ~table:Book_counts.table
           ~columns:Book_counts.projection
           Query.(
             from Book.table
             |> group_by Book.author_id
             |> having (fun _ -> Expr.count_all >=. minimum_count)
             |> select (fun book ->
               let open Projection.Let_syntax in
               let+ projected_left = Projection.expr (Book.author_id book)
               and+ projected_right = Projection.expr Expr.count_all in
               projected_left, projected_right))
       in
       Cte.with_result (Cte.select book_counts_relation) ~f:(fun book_counts ->
         Query.(from_cte book_counts |> select Book_counts.projection))))
val sk05 : (int64, (int64 * int64) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sk05);;
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

### SK-06. Авторы без книг через NOT EXISTS

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Where Exists](https://sqlkata.com/docs/where#where-exists).
- Проверяет: корреляцию по двум колонкам и сохранение авторов без книг; `EXISTS` не должен размножать внешние строки.

```sql
SELECT id, name
FROM author
WHERE NOT EXISTS (
  SELECT 1 FROM book WHERE book.author_id = author.id LIMIT 1
)
```

```csharp
var query = new Query("author")
    .Select("id", "name")
    .WhereNotExists(q => q.From("book")
        .WhereColumns("book.author_id", "=", "author.id"));
```

#### OCaml (typed-sql)

```ocaml
# let sk06 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Author.table
      |> where (fun author ->
        not_exists
          (from Book.table |> where (fun book -> Book.author_id book =. Author.id author)))
      |> select (fun author ->
        let open Projection.Let_syntax in
        let+ projected_left = Projection.expr (Author.id author)
        and+ projected_right = Projection.expr (Author.name author) in
        projected_left, projected_right))
val sk06 : (unit, (int64 * string) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sk06);;
SELECT
  t0."id",
  t0."name"
FROM "author" AS t0
WHERE
  (NOT EXISTS (
    SELECT
      1
    FROM "book" AS t1
    WHERE
      (t1."author_id" = t0."id")
  ))
```

### SK-07. Коррелированный подсчёт книг в проекции

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Select from a sub query](https://sqlkata.com/docs/select#sub-query).
- Проверяет: скалярный агрегат для каждого автора и ноль для автора без книг.

```sql
SELECT author.id, author.name,
       (SELECT COUNT(*) FROM book
        WHERE book.author_id = author.id) AS book_count
FROM author
```

```csharp
var countBooks = new Query("book")
    .WhereColumns("book.author_id", "=", "author.id")
    .AsCount();
var query = new Query("author")
    .Select("author.id", "author.name")
    .Select(countBooks, "book_count");
```

#### OCaml (typed-sql)

`COUNT(*)` в scalar subquery возвращает ноль и для автора без книг.

```ocaml
# let sk07 =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(
      from Author.table
      |> select (fun author ->
        let book_count =
          Query.(
            from Book.table
            |> where (fun book -> Book.author_id book =. Author.id author)
            |> select_scalar (fun _ -> Expr.count_all))
        in
        let open Projection.Let_syntax in
        let+ author_id, name =
          let open Projection.Let_syntax in
          let+ projected_left = Projection.expr (Author.id author)
          and+ projected_right = Projection.expr (Author.name author) in
          projected_left, projected_right
        and+ count =
          Projection.expr
            (Expr.coalesce
               (Expr.scalar_subquery book_count)
               ~default:(Expr.constant Db_type.int64 0L))
        in
        author_id, name, count))
val sk07 : (unit, (int64 * string * int64) list, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sk07);;
SELECT
  t0."id",
  t0."name",
  COALESCE((
    SELECT
      COUNT(*)
    FROM "book" AS t1
    WHERE
      (t1."author_id" = t0."id")
  ), $1)
FROM "author" AS t0
```

### SK-08. UNION ALL с повторениями на границе года

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Combining Multiple Queries](https://sqlkata.com/docs/combine).
- Проверяет: одинаковую форму обеих ветвей и сохранение двух копий книги за 2000 год.

```sql
SELECT id, author_id FROM book WHERE published_in <= @year
UNION ALL
SELECT id, author_id FROM book WHERE published_in >= @year
```

```csharp
var before = new Query("book")
    .Select("id", "author_id")
    .Where("published_in", "<=", 2000L);
var after = new Query("book")
    .Select("id", "author_id")
    .Where("published_in", ">=", 2000L);
var query = before.UnionAll(after);
```

#### OCaml (typed-sql)

```ocaml
# let sk08 =
  Statement.query_many
    ~dialect:Dialect.portable
    (let before =
       Query.(
         from Book.table
         |> where (fun book -> Book.published_in book <=$ 2000L)
         |> select (fun book ->
           let open Projection.Let_syntax in
           let+ projected_left = Projection.expr (Book.id book)
           and+ projected_right = Projection.expr (Book.author_id book) in
           projected_left, projected_right))
     in
     let after =
       Query.(
         from Book.table
         |> where (fun book -> Book.published_in book >=$ 2000L)
         |> select (fun book ->
           let open Projection.Let_syntax in
           let+ projected_left = Projection.expr (Book.id book)
           and+ projected_right = Projection.expr (Book.author_id book) in
           projected_left, projected_right))
     in
     Query.union_all before after)
val sk08 : (unit, (int64 * int64) list, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sk08);;
SELECT *
FROM (
  SELECT
    t0."id",
    t0."author_id"
  FROM "book" AS t0
  WHERE
    (t0."published_in" <= $1)
) AS s0
UNION ALL
SELECT *
FROM (
  SELECT
    t0."id",
    t0."author_id"
  FROM "book" AS t0
  WHERE
    (t0."published_in" >= $2)
) AS s0
```

### SK-09. INSERT в архив из SELECT

- OCaml-пример: ✓
- Реализуемость: ✓ (добавлено в роадмап ✓)
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Insert from Query](https://sqlkata.com/docs/update#insert-from-query).
- Проверяет: согласование порядка четырёх колонок в INSERT и SELECT и перенос только книг до заданного года.

```sql
INSERT INTO book_archive (id, author_id, title, published_in)
SELECT id, author_id, title, published_in
FROM book WHERE published_in < @cutoff
```

```csharp
var source = new Query("book")
    .Select("id", "author_id", "title", "published_in")
    .Where("published_in", "<", cutoff);
var query = new Query("book_archive")
    .AsInsert(new[] { "id", "author_id", "title", "published_in" }, source);
```

#### OCaml (typed-sql)

```ocaml
# let sk09 =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let open Parameters.Let_syntax in
    let+ cutoff = params.expr Db_type.int64 ~get:Fn.id in
    params.command
      (let source =
         Query.(
           from Book.table
           |> where (fun book -> Book.published_in book <. cutoff)
           |> select (fun book ->
             let open Projection.Let_syntax in
             let+ id, author_id =
               let open Projection.Let_syntax in
               let+ projected_left = Projection.expr (Book.id book)
               and+ projected_right = Projection.expr (Book.author_id book) in
               projected_left, projected_right
             and+ title, published_in =
               let open Projection.Let_syntax in
               let+ projected_left = Projection.expr (Book.title book)
               and+ projected_right = Projection.expr (Book.published_in book) in
               projected_left, projected_right
             in
             id, author_id, title, published_in))
       in
       let columns =
         Insert.Columns.(
           column Book_archive.id_column
           |> add Book_archive.author_id_column
           |> add Book_archive.title_column
           |> add Book_archive.published_in_column)
       in
       Insert.(into Book_archive.table |> from_select columns source |> command)))
val sk09 : (int64, Affected_rows.t, Dialect.both) Statement.t = <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql ~input:1990L sk09);;
INSERT INTO "book_archive" (
  "id",
  "author_id",
  "title",
  "published_in"
)
SELECT
  t0."id",
  t0."author_id",
  t0."title",
  t0."published_in"
FROM "book" AS t0
WHERE
  (t0."published_in" < $1)
```

### SK-10. Условный UPDATE нескольких строк

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Insert, Update and Delete](https://sqlkata.com/docs/update#update).
- Проверяет: сохранение обоих предикатов в UPDATE и передачу нового заголовка отдельно от SQL.

```sql
UPDATE book SET title = @newTitle
WHERE author_id = @authorId AND published_in < @cutoff
```

```csharp
var query = new Query("book")
    .Where("author_id", authorId)
    .Where("published_in", "<", cutoff)
    .AsUpdate(new { title = newTitle });
```

#### OCaml (typed-sql)

```ocaml
# let sk10 =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let open Parameters.Let_syntax in
    let+ title = params.expr Db_type.text ~get:(fun (title, _, _) -> title)
    and+ author_id = params.expr Db_type.int64 ~get:(fun (_, author_id, _) -> author_id)
    and+ cutoff = params.expr Db_type.int64 ~get:(fun (_, _, cutoff) -> cutoff) in
    params.command
      Update.(
        table Book.table
        |> set_expr Book.title_column title
        |> where (fun book ->
          Book.author_id book =. author_id &&. (Book.published_in book <. cutoff))
        |> command))
val sk10 :
  (string * int64 * int64, Affected_rows.t, Dialect.both) Statement.t =
  <abstr>
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Postgresql sk10);;
UPDATE "book"
SET
  "title" = $1
WHERE
  (
    ("author_id" = $2)
    AND ("published_in" < $3)
  )
```
