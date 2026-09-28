<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Сценарии запросов из jOOQ

Подборка 60 сценариев из [руководства пользователя jOOQ 3.21](https://www.jooq.org/doc/3.21/manual/). Это каталог для последующего включения запросов в общий набор автоматических тестов. Он не претендует на полный список возможностей jOOQ.

**Желаемый таргет: 60–100 сценариев.**

Источник: *The jOOQ User Manual*, © 2009–2026 Data Geekery GmbH, лицензия [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Запросы отобраны, сокращены и местами адаптированы; ссылки ведут к исходным разделам. Этот файл с адаптациями распространяется на условиях CC BY-SA 4.0. Указание источника не означает одобрения со стороны jOOQ или Data Geekery GmbH.

Для запросов используется схема примеров jOOQ: `AUTHOR`, `BOOK`, `LANGUAGE`, `BOOK_STORE` и `BOOK_TO_BOOK_STORE`. Состав и примерные данные описаны в [разделе о sample database](https://www.jooq.org/doc/3.21/manual/getting-started/sample-database/). Значения в SQL показаны для ясности; при переносе нужно проверить, что значения остаются bind-параметрами.

Для JQ-16–JQ-60 сохраняется эта схема и используются две дополнительные фикстуры: BOOK_ARCHIVE (ID, TITLE, ARCHIVED_AT), где ID сопоставим с BOOK.ID, а ARCHIVED_AT допускает NULL; и DIRECTORY (ID, PARENT_ID, LABEL) с корнем и несколькими уровнями потомков. Для проверки сортировки NULLS LAST нужны строки архива как с NULL, так и с ненулевым ARCHIVED_AT.

Записи, где синтаксис является синтетическим расширением jOOQ, требуют проверки сгенерированного SQL; приведённая там форма SQL может не исполняться напрямую.

Для сценариев с OCaml-примером ✓ приведены typed-sql реализации и SQL компилятора; карточки с ✗ указывают конкретное ограничение публичного API. JQ-11 воспроизводит оконный count коррелированным scalar subquery, JQ-21 использует рекурсивный CTE. В блоках «SQL typed-sql» первая строка запускает компилятор, остальные строки — его вывод. OCaml-блоки выполняются через MDX: `opam exec -- dune runtest test/query-builder-survey`; проверка подтверждает построение запросов typed-sql и вывод SQL.

Во всех карточках статусы означают: `✓` — подтверждено; `✗` — условие не выполнено; `—` — не оценивалось. «Семантика» учитывает входные параметры, результат, `NULL` и заданный порядок относительно адаптированного сценария в этой карточке. «Без доработок» относится к публичному API typed-sql, а не к необходимости улучшить пример. Реализуемость оценивается после попытки написать OCaml-код.

## Общие дескрипторы typed-sql

Здесь используются таблицы `author` и `book`. Компилятор экранирует имена и назначает алиасы.

```ocaml
open! Base
open Typed_sql
open Infix

module Author = struct
  type row

  let table : row Table.t = Table.v_exn "author"
  let id_column = Column.v_exn table "id" Db_type.int
  let first_name_column = Column.v_exn table "first_name" Db_type.text
  let last_name_column = Column.v_exn table "last_name" Db_type.text
  let id row = Expr.column row id_column
  let first_name row = Expr.column row first_name_column
  let last_name row = Expr.column row last_name_column
end

module Book = struct
  type row

  let table : row Table.t = Table.v_exn "book"
  let id_column = Column.v_exn table "id" Db_type.int
  let author_id_column = Column.v_exn table "author_id" Db_type.int
  let title_column = Column.v_exn table "title" Db_type.text
  let published_in_column = Column.v_exn table "published_in" Db_type.int
  let language_id_column = Column.v_exn table "language_id" Db_type.int
  let id row = Expr.column row id_column
  let author_id row = Expr.column row author_id_column
  let title row = Expr.column row title_column
  let published_in row = Expr.column row published_in_column
  let language_id row = Expr.column row language_id_column
  let nullable_id row = Expr.nullable_column row id_column
  let nullable_title row = Expr.nullable_column row title_column
end

module Language = struct
  type row

  let table : row Table.t = Table.v_exn "language"
  let cd_column = Column.v_exn table "cd" Db_type.text
  let cd row = Expr.column row cd_column
end

module Book_archive = struct
  type row

  let table : row Table.t = Table.v_exn "book_archive"
  let id_column = Column.v_exn table "id" Db_type.int
  let title_column = Column.v_exn table "title" Db_type.text
  let archived_at_column = Column.nullable_v_exn table "archived_at" Db_type.timestamp
  let id row = Expr.column row id_column
  let title row = Expr.column row title_column
  let archived_at row = Expr.column row archived_at_column
end

module Directory = struct
  type row

  let table : row Table.t = Table.v_exn "directory"
  let id_column = Column.v_exn table "id" Db_type.int
  let parent_id_column = Column.nullable_v_exn table "parent_id" Db_type.int
  let label_column = Column.v_exn table "label" Db_type.text
  let id row = Expr.column row id_column
  let parent_id row = Expr.column row parent_id_column
  let label row = Expr.column row label_column
end

module Directory_tree = struct
  type row

  let table : row Table.t = Table.v_exn "directory_tree"
  let id_column = Column.v_exn table "id" Db_type.int
  let parent_id_column = Column.nullable_v_exn table "parent_id" Db_type.int
  let label_column = Column.v_exn table "label" Db_type.text
  let depth_column = Column.v_exn table "depth" Db_type.int
  let id row = Expr.column row id_column
  let parent_id row = Expr.column row parent_id_column
  let label row = Expr.column row label_column
  let depth row = Expr.column row depth_column
end
```

## SELECT и фильтрация

### JQ-01. Фильтр, JOIN, группировка, сортировка и страница

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [SELECT from a complex table expression](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/).
- Проверяет: композицию основных SELECT-клауз и сохранение порядка применения `LIMIT`/`OFFSET`.

```sql
SELECT AUTHOR.FIRST_NAME, AUTHOR.LAST_NAME, COUNT(*)
FROM AUTHOR
JOIN BOOK ON BOOK.AUTHOR_ID = AUTHOR.ID
WHERE BOOK.PUBLISHED_IN > 1940
GROUP BY AUTHOR.FIRST_NAME, AUTHOR.LAST_NAME
HAVING COUNT(*) > 0
ORDER BY AUTHOR.LAST_NAME ASC
LIMIT 2
OFFSET 1
```

```java
create.select(AUTHOR.FIRST_NAME, AUTHOR.LAST_NAME, count())
      .from(AUTHOR)
      .join(BOOK).on(BOOK.AUTHOR_ID.eq(AUTHOR.ID))
      .where(BOOK.PUBLISHED_IN.gt(1940))
      .groupBy(AUTHOR.FIRST_NAME, AUTHOR.LAST_NAME)
      .having(count().gt(0))
      .orderBy(AUTHOR.LAST_NAME.asc())
      .limit(2)
      .offset(1)
      .fetch();
```

Запрос адаптирован по примеру руководства: исключены `FOR UPDATE` и `NULLS FIRST`, чтобы сначала сравнить переносимую часть.

#### OCaml (typed-sql)

`Query.group_by` вызывается по одному разу для каждого ключа. `COUNT(*)` в `HAVING` и проекции относится к группе. Год и порог числа книг остаются bind-значениями.

```ocaml
let jq01 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Author.table
      |> inner_join Book.table ~on:(fun author book ->
        Book.author_id book =. Author.id author)
      |> where (fun (_author, book) -> Book.published_in book >$ 1940)
      |> group_by (fun (author, _book) -> Author.first_name author)
      |> group_by (fun (author, _book) -> Author.last_name author)
      |> having (fun _ -> Expr.count_all >$ 0L)
      |> order_by (fun (author, _book) -> Author.last_name author) `Asc
      |> limit 2
      |> offset 1
      |> select (fun (author, _book) ->
        Projection.map3
          ~f:(fun first last count -> first, last, count)
          (Projection.expr (Author.first_name author))
          (Projection.expr (Author.last_name author))
          (Projection.expr Expr.count_all))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq01);;
SELECT
  t0."first_name",
  t0."last_name",
  COUNT(*)
FROM "author" AS t0
INNER JOIN "book" AS t1
  ON (t1."author_id" = t0."id")
WHERE
  (t1."published_in" > $1)
GROUP BY
  t0."first_name",
  t0."last_name"
HAVING
  (COUNT(*) > $2)
ORDER BY
  t0."last_name" ASC
LIMIT 2
OFFSET 1
```

### JQ-02. Условный предикат и форма запроса

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Optional conditional expressions](https://www.jooq.org/doc/3.21/manual/sql-building/dynamic-sql/no-condition/).
- Проверяет: включение/исключение условия и соответствующее изменение SQL.

```sql
-- Filter enabled
SELECT BOOK.ID
FROM BOOK
WHERE BOOK.ID = 10

-- Filter omitted
SELECT BOOK.ID
FROM BOOK
```

```java
create.select(BOOK.ID)
      .from(BOOK)
      .where(hasId ? BOOK.ID.eq(10) : noCondition())
      .fetch();
```

#### OCaml (typed-sql)

`where_opt` добавляет условие только при `Some`. Поэтому здесь используется `Statement.Dynamic.Portable`: форма SQL зависит от входа. Для двух заранее известных вариантов можно также создать два статических statements.

```ocaml
let jq02 =
  Statement.Dynamic.Portable.query_many (fun book_id ->
    Query.(
      from Book.table
      |> where_opt book_id ~f:(fun book id -> Book.id book =$ id)
      |> select (fun book -> Projection.expr (Book.id book))))
```

#### SQL typed-sql (PostgreSQL, фильтр есть)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:(Some 10) jq02);;
SELECT
  t0."id"
FROM "book" AS t0
WHERE
  (t0."id" = $1)
```

#### SQL typed-sql (PostgreSQL, фильтр отсутствует)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:None jq02);;
SELECT
  t0."id"
FROM "book" AS t0
```

#### SQL typed-sql (SQLite, фильтр есть)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite ~input:(Some 10) jq02);;
SELECT
  t0."id"
FROM "book" AS t0
WHERE
  (t0."id" = ?1)
```

#### SQL typed-sql (SQLite, фильтр отсутствует)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Sqlite ~input:None jq02);;
SELECT
  t0."id"
FROM "book" AS t0
```

### JQ-03. LEFT JOIN с отсутствующей правой строкой

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [JOIN operator](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/from-clause/join-clause/).
- Проверяет: сохранение левой строки без совпадения и nullable-поля правой стороны.

```sql
SELECT AUTHOR.ID, BOOK.ID, BOOK.TITLE
FROM AUTHOR
LEFT JOIN BOOK ON BOOK.AUTHOR_ID = AUTHOR.ID
ORDER BY AUTHOR.ID, BOOK.ID
```

```java
create.select(AUTHOR.ID, BOOK.ID, BOOK.TITLE)
      .from(AUTHOR)
      .leftJoin(BOOK).on(BOOK.AUTHOR_ID.eq(AUTHOR.ID))
      .orderBy(AUTHOR.ID, BOOK.ID)
      .fetch();
```

Для фикстуры нужно добавить автора без книг, иначе сценарий не проверяет null-extension.

#### OCaml (typed-sql)

После `left_join` дескриптор `Book` становится nullable. Поля книги выбираются через `Expr.nullable_column`; для автора без книг они декодируются как `None`.

```ocaml
let jq03 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Author.table
      |> left_join Book.table ~on:(fun author book ->
        Book.author_id book =. Author.id author)
      |> order_by (fun (author, _book) -> Author.id author) `Asc
      |> order_by (fun (_author, book) -> Book.nullable_id book) `Asc
      |> select (fun (author, book) ->
        Projection.map3
          ~f:(fun author_id book_id title -> author_id, book_id, title)
          (Projection.expr (Author.id author))
          (Projection.expr (Book.nullable_id book))
          (Projection.expr (Book.nullable_title book)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq03);;
SELECT
  t0."id",
  t1."id",
  t1."title"
FROM "author" AS t0
LEFT JOIN "book" AS t1
  ON (t1."author_id" = t0."id")
ORDER BY
  t0."id" ASC,
  t1."id" ASC
```

### JQ-04. Коррелированный EXISTS

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: Проверяется `WHERE EXISTS`; `EXISTS` в проекции здесь не проверяется.
- Источник: [EXISTS predicate](https://www.jooq.org/doc/3.21/manual/sql-building/conditional-expressions/exists-predicate/).
- Проверяет: корреляцию подзапроса и фильтрацию по наличию связанных строк.

```sql
SELECT AUTHOR.ID, AUTHOR.LAST_NAME
FROM AUTHOR
WHERE EXISTS (
  SELECT 1
  FROM BOOK
  WHERE BOOK.AUTHOR_ID = AUTHOR.ID
)
```

```java
create.select(AUTHOR.ID, AUTHOR.LAST_NAME)
      .from(AUTHOR)
      .whereExists(selectOne()
          .from(BOOK)
          .where(BOOK.AUTHOR_ID.eq(AUTHOR.ID)))
      .fetch();
```

Отрицательный вариант и DSL anti join приведены отдельно в JQ-16.

#### OCaml (typed-sql)

Внутренний запрос захватывает `author` из внешнего callback. `Query.exists` получает незавершённый SELECT и сам формирует `SELECT 1`.

```ocaml
let jq04 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Author.table
      |> where (fun author ->
        Query.exists
          Query.(
            from Book.table
            |> where (fun book -> Book.author_id book =. Author.id author)))
      |> select (fun author ->
        Projection.pair (Author.id author) (Author.last_name author))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq04);;
SELECT
  t0."id",
  t0."last_name"
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

### JQ-05. Коррелированный scalar subquery в projection

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Scalar subqueries](https://www.jooq.org/doc/3.21/manual/sql-building/column-expressions/scalar-subqueries/).
- Проверяет: scalar aggregate-подзапрос, корреляцию к внешней строке и результат для автора без книг.

```sql
SELECT AUTHOR.ID,
       (
         SELECT COUNT(*)
         FROM BOOK
         WHERE BOOK.AUTHOR_ID = AUTHOR.ID
       ) AS BOOK_COUNT
FROM AUTHOR
ORDER BY AUTHOR.ID
```

```java
create.select(
          AUTHOR.ID,
          field(selectCount()
              .from(BOOK)
              .where(BOOK.AUTHOR_ID.eq(AUTHOR.ID)))
              .as("book_count"))
      .from(AUTHOR)
      .orderBy(AUTHOR.ID)
      .fetch();
```

#### OCaml (typed-sql)

`Expr.scalar_subquery` возвращает `int64 option`: тип учитывает возможность отсутствия строки у произвольного scalar SELECT. У `COUNT(*)` без группировки строка есть даже при нуле книг; decoder здесь преобразует `None` в `0L`.

```ocaml
let jq05 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Author.table
      |> order_by Author.id `Asc
      |> select (fun author ->
        let count =
          Query.(
            from Book.table
            |> where (fun book -> Book.author_id book =. Author.id author)
            |> select_scalar (fun _ -> Expr.count_all))
        in
        Projection.map2
          ~f:(fun author_id count -> author_id, Option.value count ~default:0L)
          (Projection.expr (Author.id author))
          (Projection.expr (Expr.scalar_subquery count)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq05);;
SELECT
  t0."id",
  (
    SELECT
      COUNT(*)
    FROM "book" AS t1
    WHERE
      (t1."author_id" = t0."id")
  )
FROM "author" AS t0
ORDER BY
  t0."id" ASC
```

### JQ-06. Derived table с агрегатом

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Derived tables](https://www.jooq.org/doc/3.21/manual/sql-building/table-expressions/derived-tables/).
- Проверяет: использование результата одного SELECT как relation во внешнем SELECT.

```sql
SELECT NESTED.AUTHOR_ID, NESTED.BOOKS
FROM (
  SELECT BOOK.AUTHOR_ID, COUNT(*) AS BOOKS
  FROM BOOK
  GROUP BY BOOK.AUTHOR_ID
) AS NESTED
ORDER BY NESTED.BOOKS DESC
```

```java
Table<?> nested = create.select(BOOK.AUTHOR_ID, count().as("books"))
                        .from(BOOK)
                        .groupBy(BOOK.AUTHOR_ID)
                        .asTable("nested");

create.select(nested.fields())
      .from(nested)
      .orderBy(nested.field("books", Integer.class).desc())
      .fetch();
```

#### OCaml (typed-sql)

`select_relation` выводит типизированные поля derived relation из SQL-выражений. Поскольку имена выводятся структурно, в данном запросе поля relation называются `field_1` и `field_2`.

```ocaml
let jq06_relation =
  Query.(
    from Book.table
    |> group_by Book.author_id
    |> select_relation (fun book ->
      Derived_table.Fields.pair
        (Book.author_id book)
        Expr.count_all))

let jq06 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from_relation jq06_relation
      |> order_by (fun (_author_id, books) -> books) `Desc
      |> select (fun fields ->
        let author_id, books = fields in
        Projection.pair author_id books)))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq06);;
SELECT
  t0."field_1",
  t0."field_2"
FROM (
  SELECT
    t1."author_id" AS "field_1",
    COUNT(*) AS "field_2"
  FROM "book" AS t1
  GROUP BY
    t1."author_id"
) AS t0
ORDER BY
  t0."field_2" DESC
```

### JQ-07. CTE, используемый как relation

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [The WITH clause](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/with-clause/).
- Проверяет: объявление CTE и обращение к нему во внешнем SELECT.

```sql
WITH BOOK_COUNTS (AUTHOR_ID, BOOKS) AS (
  SELECT BOOK.AUTHOR_ID, COUNT(*)
  FROM BOOK
  GROUP BY BOOK.AUTHOR_ID
)
SELECT AUTHOR_ID, BOOKS
FROM BOOK_COUNTS
WHERE BOOKS > 1
ORDER BY AUTHOR_ID
```

```java
CommonTableExpression<Record2<Integer, Integer>> bookCounts =
    name("book_counts").fields("author_id", "books")
        .as(select(BOOK.AUTHOR_ID, count())
            .from(BOOK)
            .groupBy(BOOK.AUTHOR_ID));

create.with(bookCounts)
      .select(bookCounts.field("author_id", Integer.class),
              bookCounts.field("books", Integer.class))
      .from(bookCounts)
      .where(bookCounts.field("books", Integer.class).gt(1))
      .orderBy(bookCounts.field("author_id"))
      .fetch();
```

#### OCaml (typed-sql)

CTE использует типизированные поля derived relation. Порог остаётся bind-значением.

```ocaml
module Book_count = struct
  type row

  let table : row Table.t = Table.v_exn "book_counts"
  let author_id_column = Column.v_exn table "author_id" Db_type.int
  let books_column = Column.v_exn table "books" Db_type.int64
  let author_id row = Expr.column row author_id_column
  let books row = Expr.column row books_column
end

let jq07_relation =
  Derived_table.create
    ~table:Book_count.table
    ~columns:(fun row -> Projection.pair (Book_count.author_id row) (Book_count.books row))
    Query.(
      from Book.table
      |> group_by Book.author_id
      |> select (fun book -> Projection.pair (Book.author_id book) Expr.count_all))

let jq07_cte = Cte.select jq07_relation

let jq07 =
  Statement.Portable.query_many_exn (fun _ ->
    Cte.with_result jq07_cte ~f:(fun book_counts ->
      Query.(
        from_cte book_counts
        |> where (fun counts -> Book_count.books counts >$ 1L)
        |> order_by Book_count.author_id `Asc
        |> select (fun counts ->
          Projection.pair (Book_count.author_id counts) (Book_count.books counts)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq07);;
WITH
  "c0" (
    "author_id",
    "books"
  ) AS (
    SELECT
      t0."author_id",
      COUNT(*)
    FROM "book" AS t0
    GROUP BY
      t0."author_id"
  )
SELECT
  t0."author_id",
  t0."books"
FROM "c0" AS t0
WHERE
  (t0."books" > $1)
ORDER BY
  t0."author_id" ASC
```

### JQ-08. UNION двух SELECT

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✗ (добавлено в роадмап ✗)
- Без доработок typed-sql: ✗
- Источник: [Set operations](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/set-operations/).
- Проверяет: объединение строк с удалением дубликатов, одинаковую степень и типы колонок.

```sql
SELECT BOOK.ID
FROM BOOK
WHERE BOOK.PUBLISHED_IN <= 1950
UNION
SELECT BOOK.ID
FROM BOOK
WHERE BOOK.TITLE LIKE 'A%'
ORDER BY ID
```

```java
select(BOOK.ID)
    .from(BOOK)
    .where(BOOK.PUBLISHED_IN.le(1950))
    .union(select(BOOK.ID)
        .from(BOOK)
        .where(BOOK.TITLE.like("A%")))
    .orderBy(BOOK.ID)
    .fetch();
```

#### OCaml (typed-sql)

Обе ветви проецируют один и тот же тип. `Query.union` удаляет дубликаты.

```ocaml
let jq08 =
  Statement.Portable.query_many_exn (fun _ ->
    let by_year =
      Query.(
        from Book.table
        |> where (fun book -> Book.published_in book <=$ 1950)
        |> select (fun book -> Projection.expr (Book.id book)))
    in
    let by_title =
      Query.(
        from Book.table
        |> where (fun book -> Book.title book =~$ "A%")
        |> select (fun book -> Projection.expr (Book.id book)))
    in
    Query.union by_year by_title)
```

Обе ветви используют те же фильтры, что и исходный сценарий. Финальный `ORDER BY` пока нельзя задать через публичный API после `Query.union`.

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq08);;
SELECT *
FROM (
  SELECT
    t0."id"
  FROM "book" AS t0
  WHERE
    (t0."published_in" <= $1)
) AS s0
UNION
SELECT *
FROM (
  SELECT
    t0."id"
  FROM "book" AS t0
  WHERE
    (t0."title" LIKE $2)
) AS s0
```

`Query.union` возвращает готовый результат и пока не предоставляет общий `ORDER BY` после объединения. Сортировка из исходного примера не выражается текущим публичным API.

## Агрегация и аналитика

### JQ-09. GROUP BY и HAVING

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [HAVING clause](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/having-clause/).
- Проверяет: количество строк в каждой группе и фильтр уже сформированных групп.

```sql
SELECT BOOK.AUTHOR_ID, COUNT(*)
FROM BOOK
GROUP BY BOOK.AUTHOR_ID
HAVING COUNT(*) >= 2
```

```java
create.select(BOOK.AUTHOR_ID, count())
      .from(BOOK)
      .groupBy(BOOK.AUTHOR_ID)
      .having(count().ge(2))
      .fetch();
```

#### OCaml (typed-sql)

```ocaml
let jq09 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Book.table
      |> group_by Book.author_id
      |> having (fun _ -> Expr.count_all >=$ 2L)
      |> select (fun book ->
        Projection.pair (Book.author_id book) Expr.count_all)))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq09);;
SELECT
  t0."author_id",
  COUNT(*)
FROM "book" AS t0
GROUP BY
  t0."author_id"
HAVING
  (COUNT(*) >= $1)
```

### JQ-10. HAVING без GROUP BY и cardinality агрегата

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [HAVING clause](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/having-clause/).
- Проверяет: агрегат над всей входной relation и то, что `HAVING` может убрать единственную агрегатную строку.

```sql
SELECT COUNT(*)
FROM BOOK
HAVING COUNT(*) >= 4
```

```java
create.select(count())
      .from(BOOK)
      .having(count().ge(4))
      .fetch();
```

Проверить обе стороны условия: результат содержит одну строку, когда условие истинно, и ноль строк, когда оно ложно.

#### OCaml (typed-sql)

`HAVING` без `GROUP BY` соответствует PostgreSQL-специфичному расширению typed-sql. Здесь используется `query_many`, потому что `HAVING` может убрать агрегатную строку.

```ocaml
let jq10 =
  Statement.For_dialect.query_many_exn ~dialect:Dialect.postgresql (fun _ ->
    Query.(
      from Book.table
      |> Postgresql.Query.having (fun _ -> Expr.count_all >=$ 4L)
      |> select (fun _ -> Projection.expr Expr.count_all)))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq10);;
SELECT
  COUNT(*)
FROM "book" AS t0
HAVING
  (COUNT(*) >= $1)
```

### JQ-11. Оконный агрегат без схлопывания строк

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Window PARTITION BY](https://www.jooq.org/doc/3.21/manual/sql-building/column-expressions/window-functions/window-partition/).
- Проверяет: значение по группе рядом с каждой исходной строкой.
- Замечание: оконный `COUNT(*) OVER (PARTITION BY ...)` заменён коррелированным scalar count; набор строк и значение агрегата совпадают.

```sql
SELECT BOOK.ID,
       BOOK.AUTHOR_ID,
       COUNT(*) OVER (PARTITION BY BOOK.AUTHOR_ID)
FROM BOOK
ORDER BY BOOK.ID
```

```java
create.select(
          BOOK.ID,
          BOOK.AUTHOR_ID,
          count().over(partitionBy(BOOK.AUTHOR_ID)))
      .from(BOOK)
      .orderBy(BOOK.ID)
      .fetch();
```

Оконный синтаксис не генерируется; результат воспроизведён коррелированным COUNT.

## Вложенные коллекции

#### OCaml (typed-sql, коррелированный счётчик)

```ocaml
let jq11 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Book.table
      |> order_by Book.id `Asc
      |> select (fun book ->
        Projection.map3
          ~f:(fun id author_id count -> id, author_id, count)
          (Projection.expr (Book.id book))
          (Projection.expr (Book.author_id book))
          (Projection.expr
             (Expr.coalesce
                (Expr.scalar_subquery
                   (Query.(
                     from Book.table
                     |> where (fun same_author -> Book.author_id same_author =. Book.author_id book)
                     |> select_scalar (fun _ -> Expr.count_all))))
                ~default:(Expr.constant Db_type.int64 0L))))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq11);;
SELECT
  t0."id",
  t0."author_id",
  COALESCE((SELECT COUNT(*) FROM "book" AS t1 WHERE (t1."author_id" = t0."author_id")), $1)
FROM "book" AS t0
ORDER BY
  t0."id" ASC
```

### JQ-12. MULTISET из коррелированного подзапроса

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [MULTISET value constructor](https://www.jooq.org/doc/3.21/manual/sql-building/column-expressions/multiset-value-constructor/).
- Проверяет: вложенную коллекцию книг для каждой строки автора, в том числе пустую коллекцию.

```sql
SELECT AUTHOR.ID,
       MULTISET(
         SELECT BOOK.ID, BOOK.TITLE
         FROM BOOK
         WHERE BOOK.AUTHOR_ID = AUTHOR.ID
       ) AS BOOKS
FROM AUTHOR
ORDER BY AUTHOR.ID
```

```java
create.select(
          AUTHOR.ID,
          multiset(select(BOOK.ID, BOOK.TITLE)
              .from(BOOK)
              .where(BOOK.AUTHOR_ID.eq(AUTHOR.ID)))
              .as("books"))
      .from(AUTHOR)
      .orderBy(AUTHOR.ID)
      .fetch();
```

`MULTISET` здесь — синтетическая форма jOOQ. При проверке нужно выполнять SQL, который jOOQ генерирует для выбранной СУБД, и сравнивать вложенный результат, включая пустую коллекцию.

#### OCaml (typed-sql)

`Query.multiset` создаёт вложенный результат-список; пустой подзапрос декодируется как пустой список.

```ocaml
let jq12 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Author.table
      |> order_by Author.id `Asc
      |> select (fun author ->
        Projection.map2
          ~f:(fun id books -> id, books)
          (Projection.expr (Author.id author))
          (Query.multiset
             Query.(
               from Book.table
               |> where (fun book -> Book.author_id book =. Author.id author)
               |> select (fun book ->
                 Projection.pair (Book.id book) (Book.title book)))))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq12);;
SELECT
  t0."id",
  CAST((SELECT COALESCE(JSONB_AGG(JSONB_BUILD_ARRAY(m0."v0", m0."v1")), JSONB_BUILD_ARRAY())
  FROM LATERAL (
    SELECT
      t1."id" AS "v0",
      t1."title" AS "v1"
    FROM "book" AS t1
    WHERE
      (t1."author_id" = t0."id")
  ) AS m0) AS TEXT)
FROM "author" AS t0
ORDER BY
  t0."id" ASC
```

### JQ-13. MULTISET_AGG по группе

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [MULTISET_AGG](https://www.jooq.org/doc/3.21/manual/sql-building/column-expressions/aggregate-functions/multiset-agg-function/).
- Проверяет: сбор полей строк текущей группы во вложенную коллекцию.

```sql
SELECT AUTHOR.ID,
       MULTISET_AGG(BOOK.ID, BOOK.TITLE)
FROM AUTHOR
JOIN BOOK ON BOOK.AUTHOR_ID = AUTHOR.ID
GROUP BY AUTHOR.ID
ORDER BY AUTHOR.ID
```

```java
create.select(
          AUTHOR.ID,
          multisetAgg(BOOK.ID, BOOK.TITLE).as("books"))
      .from(AUTHOR)
      .join(BOOK).on(BOOK.AUTHOR_ID.eq(AUTHOR.ID))
      .groupBy(AUTHOR.ID)
      .orderBy(AUTHOR.ID)
      .fetch();
```

Это также синтетический оператор jOOQ. Проверять состав коллекции и дубликаты: порядок элементов запрос не задаёт. Чтобы проверить пустую коллекцию, нужен вариант с авторами без книг и соответствующей семантикой outer join/filter.

#### OCaml (typed-sql)

Для воспроизводимости typed-sql упорядочивает элементы по book id; исходный запрос порядок не задаёт. Как в исходном INNER JOIN, авторы без книг не дают группу.

```ocaml
let jq13 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Author.table
      |> inner_join Book.table ~on:(fun author book ->
        Book.author_id book =. Author.id author)
      |> group_by (fun (author, _book) -> Author.id author)
      |> order_by (fun (author, _book) -> Author.id author) `Asc
      |> select (fun (author, book) ->
        Projection.map2
          ~f:(fun id books -> id, books)
          (Projection.expr (Author.id author))
          (Projection.multiset_agg
             ~order_by:[ Aggregate_order.asc (Book.id book) ]
             (Projection.pair (Book.id book) (Book.title book))))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq13);;
SELECT
  t0."id",
  CAST(
    COALESCE(
      JSONB_AGG(
        JSONB_BUILD_ARRAY(
          t1."id",
          t1."title"
        )
        ORDER BY t1."id" ASC
      ),
      JSONB_BUILD_ARRAY()
    )
    AS TEXT
  )
FROM "author" AS t0
INNER JOIN "book" AS t1
  ON (t1."author_id" = t0."id")
GROUP BY
  t0."id"
ORDER BY
  t0."id" ASC
```

## Изменение данных

### JQ-14. INSERT ON CONFLICT DO UPDATE

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [INSERT statement](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/insert-statement/), раздел `ON CONFLICT`.
- Проверяет: вставку новой строки и обновление уже существующей по уникальному ключу.

```sql
INSERT INTO AUTHOR (ID, LAST_NAME)
VALUES (3, 'Koontz')
ON CONFLICT (ID)
DO UPDATE SET LAST_NAME = 'Koontz'
```

```java
create.insertInto(AUTHOR, AUTHOR.ID, AUTHOR.LAST_NAME)
      .values(3, "Koontz")
      .onConflict(AUTHOR.ID)
      .doUpdate()
      .set(AUTHOR.LAST_NAME, "Koontz")
      .execute();
```

#### OCaml (typed-sql)

```ocaml
let jq14 =
  Statement.Portable.command_exn (fun _ ->
    let target = Insert.Conflict_target.column Author.id_column in
    Insert.(
      into Author.table
      |> set Author.id_column 3
      |> set Author.last_name_column "Koontz"
      |> on_conflict target
      |> do_update (fun ~existing:_ ~excluded:_ ->
        Conflict_update.empty
        |> Conflict_update.set Author.last_name_column "Koontz")
      |> command))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq14);;
INSERT INTO "author" AS t0 (
  "id",
  "last_name"
)
VALUES
  ($1, $2)
ON CONFLICT (
  "id"
)
DO UPDATE
SET
  "last_name" = $3
```

### JQ-15. UPDATE с FROM

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [UPDATE .. FROM](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/update-statement/update-from/).
- Проверяет: обновление целевой строки по join-предикату с другой таблицей.

```sql
UPDATE BOOK_ARCHIVE
SET TITLE = BOOK.TITLE
FROM BOOK
WHERE BOOK_ARCHIVE.ID = BOOK.ID
```

```java
create.update(BOOK_ARCHIVE)
      .set(BOOK_ARCHIVE.TITLE, BOOK.TITLE)
      .from(BOOK)
      .where(BOOK_ARCHIVE.ID.eq(BOOK.ID))
      .execute();
```

Для этого сценария нужна дополнительная таблица `BOOK_ARCHIVE` с подходящими ключами и как минимум одной совпадающей и одной несовпадающей строкой.

#### OCaml (typed-sql)

Для этого сценария вводится типизированный descriptor дополнительной таблицы `book_archive`, соответствующий `BOOK_ARCHIVE` из примера.

```ocaml
module Book_archive = struct
  type row

  let table : row Table.t = Table.v_exn "book_archive"
  let id_column = Column.v_exn table "id" Db_type.int
  let title_column = Column.v_exn table "title" Db_type.text
end

let jq15 =
  Statement.Portable.command_exn (fun _ ->
    Update.(
      table Book_archive.table
      |> from Book.table ~f:(fun target source update ->
        update
        |> set_expr Book_archive.title_column (Book.title source)
        |> where (fun _ -> Expr.column target Book_archive.id_column =. Book.id source))
      |> command))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq15);;
UPDATE "book_archive" AS t0
SET
  "title" = t1."title"
FROM "book" AS t1
WHERE
  (t0."id" = t1."id")
```


## JOIN и табличные выражения

### JQ-16. ANTI JOIN: авторы без книг

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [ANTI JOIN](https://www.jooq.org/doc/3.21/manual/sql-building/table-expressions/joined-tables/join-type-anti/).
- Проверяет: выбор автора без книг без размножения строк и корректность отрицательной проверки существования.

```sql
SELECT AUTHOR.ID, AUTHOR.LAST_NAME
FROM AUTHOR
WHERE NOT EXISTS (
  SELECT 1
  FROM BOOK
  WHERE BOOK.AUTHOR_ID = AUTHOR.ID
)
ORDER BY AUTHOR.ID
```

```java
create.select(AUTHOR.ID, AUTHOR.LAST_NAME)
      .from(AUTHOR)
      .leftAntiJoin(BOOK).on(BOOK.AUTHOR_ID.eq(AUTHOR.ID))
      .orderBy(AUTHOR.ID)
      .fetch();
```

Фикстура должна содержать хотя бы одного автора без книг и одного автора с книгами.

#### OCaml (typed-sql)

```ocaml
let jq16 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Author.table
      |> where (fun author ->
        not_exists
          (Query.(
            from Book.table
            |> where (fun book -> Book.author_id book =. Author.id author))))
      |> order_by Author.id `Asc
      |> select (fun author -> Projection.pair (Author.id author) (Author.last_name author))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq16);;
SELECT
  t0."id",
  t0."last_name"
FROM "author" AS t0
WHERE
  NOT EXISTS (
    SELECT 1
    FROM "book" AS t1
    WHERE
      (t1."author_id" = t0."id")
  )
ORDER BY
  t0."id" ASC
```

### JQ-17. CROSS JOIN двух отношений

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [CROSS JOIN](https://www.jooq.org/doc/3.21/manual/sql-building/table-expressions/joined-tables/join-type-cross/).
- Проверяет: декартово произведение таблиц и его размер до применения последующих фильтров.
- Ограничение: Typed-sql выражает декартово произведение через `INNER JOIN ON TRUE`; отдельного конструктора `CROSS JOIN` нет.

```sql
SELECT AUTHOR.ID, LANGUAGE.CD
FROM AUTHOR
CROSS JOIN LANGUAGE
ORDER BY AUTHOR.ID, LANGUAGE.CD
```

```java
create.select(AUTHOR.ID, LANGUAGE.CD)
      .from(AUTHOR)
      .crossJoin(LANGUAGE)
      .orderBy(AUTHOR.ID, LANGUAGE.CD)
      .fetch();
```

#### OCaml (typed-sql)

Декартово произведение задаётся `INNER JOIN ON TRUE`; SQL форма отличается от `CROSS JOIN`, результат совпадает.

```ocaml
let jq17 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Author.table
      |> inner_join Language.table ~on:(fun _ _ -> Condition.true_)
      |> order_by (fun (author, _language) -> Author.id author) `Asc
      |> order_by (fun (_author, language) -> Language.cd language) `Asc
      |> select (fun (author, language) ->
        Projection.pair (Author.id author) (Language.cd language))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq17);;
SELECT
  t0."id",
  t1."cd"
FROM "author" AS t0
INNER JOIN "language" AS t1
  ON TRUE
ORDER BY
  t0."id" ASC,
  t1."cd" ASC
```

### JQ-18. JOIN USING с общей колонкой

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [USING clause](https://www.jooq.org/doc/3.21/manual/sql-building/table-expressions/joined-tables/join-predicate-using/).
- Проверяет: соединение по одноимённому ключу и использование общей колонки в USING.
- Ограничение: Публичный API принимает typed `ON`, но не сохраняет специальную форму `USING`.

```sql
SELECT BOOK.ID, BOOK.TITLE, BOOK_ARCHIVE.ARCHIVED_AT
FROM BOOK
JOIN BOOK_ARCHIVE USING (ID)
ORDER BY BOOK.ID
```

```java
create.select(BOOK.ID, BOOK.TITLE, BOOK_ARCHIVE.ARCHIVED_AT)
      .from(BOOK)
      .join(BOOK_ARCHIVE).using(BOOK.ID)
      .orderBy(BOOK.ID)
      .fetch();
```

Для проверки результата в BOOK_ARCHIVE нужны как совпадающие с BOOK.ID, так и отсутствующие там ключи.

#### OCaml (typed-sql)

```ocaml
let jq18 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Author.table
      |> inner_join Book.table ~on:(fun author book -> Author.id author =. Book.author_id book)
      |> select (fun (author, book) ->
        Projection.pair (Author.id author) (Book.title book))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq18);;
SELECT
  t0."id",
  t1."title"
FROM "author" AS t0
INNER JOIN "book" AS t1
  ON (t0."id" = t1."author_id")
```

### JQ-19. LATERAL: книга с максимальным ID для каждого автора с книгами

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [LATERAL](https://www.jooq.org/doc/3.21/manual/sql-building/table-expressions/joined-tables/join-mode-lateral/).
- Проверяет: корреляцию правой табличной функции с текущим автором и выбор не более одной книги на автора.
- Ограничение: LATERAL заменён коррелированным scalar subquery с сортировкой и `LIMIT 1`; результирующие строки совпадают.

```sql
SELECT AUTHOR.ID, RECENT_BOOK.ID, RECENT_BOOK.TITLE
FROM AUTHOR
CROSS JOIN LATERAL (
  SELECT BOOK.ID, BOOK.TITLE
  FROM BOOK
  WHERE BOOK.AUTHOR_ID = AUTHOR.ID
  ORDER BY BOOK.ID DESC
  FETCH FIRST 1 ROW ONLY
) AS RECENT_BOOK
ORDER BY AUTHOR.ID
```

```java
Table<?> recentBook =
    lateral(select(BOOK.ID.as("id"), BOOK.TITLE.as("title"))
        .from(BOOK)
        .where(BOOK.AUTHOR_ID.eq(AUTHOR.ID))
        .orderBy(BOOK.ID.desc())
        .limit(1))
    .as("recent_book");

create.select(
          AUTHOR.ID,
          recentBook.field("id", Integer.class),
          recentBook.field("title", String.class))
      .from(AUTHOR, recentBook)
      .orderBy(AUTHOR.ID)
      .fetch();
```

CROSS JOIN LATERAL возвращает только авторов, для которых подзапрос нашёл книгу.

#### OCaml (typed-sql, коррелированный scalar subquery)

```ocaml
let jq19 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Author.table
      |> inner_join Book.table ~on:(fun author book -> Author.id author =. Book.author_id book)
      |> where (fun (author, book) ->
        Book.id book =.
        Expr.coalesce
          (Expr.scalar_subquery_nullable
             (Query.(
               from Book.table
               |> where (fun candidate -> Book.author_id candidate =. Author.id author)
               |> order_by Book.id `Desc
               |> limit_one
               |> select_scalar Book.id)))
          ~default:(Expr.constant Db_type.int (-1)))
      |> select (fun (author, book) -> Projection.pair (Author.id author) (Book.id book))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq19);;
SELECT
  t0."id",
  t1."id"
FROM "author" AS t0
INNER JOIN "book" AS t1
  ON (t0."id" = t1."author_id")
WHERE
  (t1."id" = (
    SELECT
      t2."id"
    FROM "book" AS t2
    WHERE
      (t2."author_id" = t0."id")
    ORDER BY
      t2."id" DESC
    LIMIT 1
  ))
```

### JQ-20. VALUES как табличный источник

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✗)
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [VALUES table constructor](https://www.jooq.org/doc/3.21/manual/sql-building/table-expressions/values/).
- Проверяет: использование набора констант как relation с именованной колонкой.
- Ограничение: Публичное ядро не предоставляет `VALUES` как FROM-источник; отдельные скалярные SELECT нельзя передать в `FROM` без relation descriptor.

```sql
SELECT THRESHOLDS.MIN_YEAR, BOOK.ID
FROM (VALUES (1940), (1950)) AS THRESHOLDS(MIN_YEAR)
JOIN BOOK ON BOOK.PUBLISHED_IN >= THRESHOLDS.MIN_YEAR
ORDER BY THRESHOLDS.MIN_YEAR, BOOK.ID
```

```java
Table<?> thresholds =
    values(row(1940), row(1950))
        .as("thresholds", "min_year");

Field<Integer> minYear = thresholds.field("min_year", Integer.class);

create.select(minYear, BOOK.ID)
      .from(thresholds)
      .join(BOOK).on(BOOK.PUBLISHED_IN.ge(minYear))
      .orderBy(minYear, BOOK.ID)
      .fetch();
```

## Формы SELECT и выражения

### JQ-21. Рекурсивный CTE для дерева каталогов

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [WITH RECURSIVE](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/with-recursive-clause/).
- Проверяет: anchor member, рекурсивное соединение с родителем и накопление глубины до каждого узла.
- Замечание: `depth` — вычисляемое поле рекурсивного CTE; исходная таблица DIRECTORY его не хранит.

```sql
WITH RECURSIVE DIRECTORY_TREE (ID, PARENT_ID, DEPTH) AS (
  SELECT DIRECTORY.ID, DIRECTORY.PARENT_ID, 0
  FROM DIRECTORY
  WHERE DIRECTORY.PARENT_ID IS NULL
  UNION ALL
  SELECT DIRECTORY.ID, DIRECTORY.PARENT_ID, DIRECTORY_TREE.DEPTH + 1
  FROM DIRECTORY_TREE
  JOIN DIRECTORY ON DIRECTORY.PARENT_ID = DIRECTORY_TREE.ID
)
SELECT ID, PARENT_ID, DEPTH
FROM DIRECTORY_TREE
ORDER BY DEPTH, ID
```

```java
Table<Record> treeRef = table(name("directory_tree")).as("tree");
Field<Integer> treeId = treeRef.field("id", Integer.class);
Field<Integer> treeDepth = treeRef.field("depth", Integer.class);

CommonTableExpression<Record3<Integer, Integer, Integer>> directoryTree =
    name("directory_tree")
        .fields("id", "parent_id", "depth")
        .as(select(DIRECTORY.ID, DIRECTORY.PARENT_ID, val(0))
            .from(DIRECTORY)
            .where(DIRECTORY.PARENT_ID.isNull())
            .unionAll(
                select(DIRECTORY.ID, DIRECTORY.PARENT_ID, treeDepth.add(1))
                    .from(treeRef)
                    .join(DIRECTORY).on(DIRECTORY.PARENT_ID.eq(treeId))));

create.withRecursive(directoryTree)
      .selectFrom(directoryTree)
      .orderBy(directoryTree.field("depth", Integer.class),
               directoryTree.field("id", Integer.class))
      .fetch();
```

Для завершения рекурсии в фикстуре нужен конечный набор узлов без циклов.

#### OCaml (typed-sql, рекурсивный CTE)

```ocaml
let jq21_fields ~directory_id ~parent_id ~label ~depth =
  Projection.map3
    ~f:(fun id parent fields -> id, parent, fields)
    directory_id
    parent_id
    (Projection.pair label depth)

let jq21_columns directory =
  jq21_fields
    ~directory_id:(Projection.expr (Directory_tree.id directory))
    ~parent_id:(Projection.expr (Directory_tree.parent_id directory))
    ~label:(Projection.expr (Directory_tree.label directory))
    ~depth:(Projection.expr (Directory_tree.depth directory))

let jq21_anchor =
  Derived_table.create
    ~table:Directory_tree.table
    ~columns:jq21_columns
    Query.(
      from Directory.table
      |> where (fun directory -> Expr.is_null (Directory.parent_id directory))
      |> select (fun directory ->
        jq21_fields
          ~directory_id:(Projection.expr (Directory.id directory))
          ~parent_id:(Projection.expr (Directory.parent_id directory))
          ~label:(Projection.expr (Directory.label directory))
          ~depth:(Projection.expr (Expr.constant Db_type.int 0))))

let jq21 =
  let definition =
    Cte.recursive
      ~union:`Union_all
      ~anchor:jq21_anchor
      ~step:(fun directory_cte ->
        Derived_table.create
          ~table:Directory_tree.table
          ~columns:jq21_columns
          Query.(
            from Directory.table
            |> inner_join_cte directory_cte ~on:(fun directory parent ->
              Directory.parent_id directory =. Expr.to_nullable (Directory_tree.id parent))
            |> select (fun (directory, parent) ->
              jq21_fields
                ~directory_id:(Projection.expr (Directory.id directory))
                ~parent_id:(Projection.expr (Directory.parent_id directory))
                ~label:(Projection.expr (Directory.label directory))
                ~depth:(Projection.expr Expr.Int.Infix.(Directory_tree.depth parent +. Expr.constant Db_type.int 1)))))
  in
  Statement.Portable.query_many_exn (fun _ ->
    Cte.with_result definition ~f:(fun directory_cte ->
      Query.(
        from_cte directory_cte
        |> order_by Directory_tree.depth `Asc
        |> order_by Directory_tree.id `Asc
        |> select (fun directory -> jq21_columns directory))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq21);;
WITH RECURSIVE
  "c0" (
    "id",
    "parent_id",
    "label",
    "depth"
  ) AS (
    SELECT
      t0."id",
      t0."parent_id",
      t0."label",
      $1
    FROM "directory" AS t0
    WHERE
      (t0."parent_id" IS NULL)
    UNION ALL
    SELECT
      t0."id",
      t0."parent_id",
      t0."label",
      (t1."depth" + $2)
    FROM "directory" AS t0
    INNER JOIN "c0" AS t1
      ON (t0."parent_id" = t1."id")
  )
SELECT
  t0."id",
  t0."parent_id",
  t0."label",
  t0."depth"
FROM "c0" AS t0
ORDER BY
  t0."depth" ASC,
  t0."id" ASC
```

### JQ-22. SELECT DISTINCT по внешнему ключу

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [SELECT DISTINCT](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/select-clause/select-clause-distinct/).
- Проверяет: удаление дубликатов в результате проекции.

```sql
SELECT DISTINCT BOOK.AUTHOR_ID
FROM BOOK
ORDER BY BOOK.AUTHOR_ID
```

```java
create.select(BOOK.AUTHOR_ID)
      .distinct()
      .from(BOOK)
      .orderBy(BOOK.AUTHOR_ID)
      .fetch();
```

В фикстуре у одного автора должно быть несколько книг, чтобы DISTINCT удалил повтор.

#### OCaml (typed-sql)

```ocaml
let jq22 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Book.table
      |> distinct
      |> select (fun book -> Projection.expr (Book.author_id book))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq22);;
SELECT DISTINCT
  t0."author_id"
FROM "book" AS t0
```

### JQ-23. DISTINCT ON: первая книга каждого языка

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [SELECT DISTINCT ON](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/select-clause/select-clause-distinct-on/).
- Проверяет: выбор первой строки каждой группы согласно явному порядку.
- Ограничение: `DISTINCT ON` выражен коррелированным `NOT EXISTS` с тем же tie-break; форма SQL отличается, результат совпадает при уникальном ID.

```sql
SELECT DISTINCT ON (BOOK.LANGUAGE_ID) BOOK.LANGUAGE_ID, BOOK.ID, BOOK.TITLE
FROM BOOK
ORDER BY BOOK.LANGUAGE_ID, BOOK.ID
```

```java
create.select(BOOK.LANGUAGE_ID, BOOK.ID, BOOK.TITLE)
      .distinctOn(BOOK.LANGUAGE_ID)
      .from(BOOK)
      .orderBy(BOOK.LANGUAGE_ID, BOOK.ID)
      .fetch();
```

DISTINCT ON является расширением PostgreSQL; для других диалектов jOOQ может эмулировать его через оконную функцию.

#### OCaml (typed-sql, anti-exists emulation)

Для каждого языка оставляется книга, перед которой нет книги с меньшим годом, а при равенстве — с меньшим ID.

```ocaml
let jq23 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Book.table
      |> where (fun book ->
        not_exists
          (Query.(
            from Book.table
            |> where (fun earlier ->
              (Book.language_id earlier =. Book.language_id book)
              &&. ((Book.published_in earlier <. Book.published_in book)
                   ||. ((Book.published_in earlier =. Book.published_in book)
                        &&. (Book.id earlier <. Book.id book)))))))
      |> order_by Book.language_id `Asc
      |> select (fun book -> Projection.pair (Book.language_id book) (Book.id book))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq23);;
SELECT
  t0."language_id",
  t0."id"
FROM "book" AS t0
WHERE
  NOT EXISTS (
    SELECT 1
    FROM "book" AS t1
    WHERE
      ((t1."language_id" = t0."language_id") AND ((t1."published_in" < t0."published_in") OR ((t1."published_in" = t0."published_in") AND (t1."id" < t0."id"))))
  )
ORDER BY
  t0."language_id" ASC
```

### JQ-24. CASE для классификации книг

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [CASE expression](https://www.jooq.org/doc/3.21/manual/sql-building/column-expressions/case-expressions/).
- Проверяет: типизированное условное выражение в проекции и значение ветви ELSE.

```sql
SELECT BOOK.ID,
       CASE WHEN BOOK.PUBLISHED_IN <= 1950 THEN 'classic'
            ELSE 'modern'
       END AS ERA
FROM BOOK
ORDER BY BOOK.ID
```

```java
create.select(
          BOOK.ID,
          when(BOOK.PUBLISHED_IN.le(1950), "classic")
              .otherwise("modern").as("era"))
      .from(BOOK)
      .orderBy(BOOK.ID)
      .fetch();
```

#### OCaml (typed-sql)

```ocaml
let jq24 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Book.table
      |> select (fun book ->
        Projection.pair
          (Book.id book)
          (Expr.case
             [ Book.published_in book <$ 1950,
               Expr.constant Db_type.text "classic" ]
             ~else_:(Expr.constant Db_type.text "modern")))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq24);;
SELECT
  t0."id",
  CASE WHEN (t0."published_in" < $1) THEN $2 ELSE $3 END
FROM "book" AS t0
```

### JQ-25. Сортировка NULLS LAST

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [ORDER BY clause](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/order-by-clause/order-by-nulls-ordering/).
- Проверяет: явное положение NULL относительно ненулевых значений.
- Ограничение: NULLS LAST реализован portable `CASE` ключом сортировки, а не специальной клаузой диалекта.

```sql
SELECT BOOK_ARCHIVE.ID, BOOK_ARCHIVE.ARCHIVED_AT
FROM BOOK_ARCHIVE
ORDER BY BOOK_ARCHIVE.ARCHIVED_AT ASC NULLS LAST, BOOK_ARCHIVE.ID
```

```java
create.select(BOOK_ARCHIVE.ID, BOOK_ARCHIVE.ARCHIVED_AT)
      .from(BOOK_ARCHIVE)
      .orderBy(BOOK_ARCHIVE.ARCHIVED_AT.asc().nullsLast(),
               BOOK_ARCHIVE.ID.asc())
      .fetch();
```

#### OCaml (typed-sql, CASE-сортировка)

```ocaml
let jq25 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Book_archive.table
      |> order_by (fun archive ->
        Expr.case
          [ Expr.is_null (Book_archive.archived_at archive),
            Expr.constant Db_type.int 1 ]
          ~else_:(Expr.constant Db_type.int 0)) `Asc
      |> order_by Book_archive.archived_at `Asc
      |> select (fun archive -> Projection.pair (Book_archive.id archive) (Book_archive.archived_at archive))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq25);;
SELECT
  t0."id",
  t0."archived_at"
FROM "book_archive" AS t0
ORDER BY
  CASE WHEN (t0."archived_at" IS NULL) THEN $1 ELSE $2 END ASC,
  t0."archived_at" ASC
```

### JQ-26. FETCH FIRST WITH TIES

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✗)
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [WITH TIES clause](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/with-ties-clause/).
- Проверяет: включение всех строк, связанных с последней строкой ограниченной страницы по ключу сортировки.
- Ограничение: Без оконного ранга или `FETCH WITH TIES` ядро не может сохранить динамическую границу всех строк, равных последнему ключу страницы.

```sql
SELECT BOOK.ID, BOOK.PUBLISHED_IN
FROM BOOK
ORDER BY BOOK.PUBLISHED_IN
FETCH FIRST 2 ROWS WITH TIES
```

```java
create.select(BOOK.ID, BOOK.PUBLISHED_IN)
      .from(BOOK)
      .orderBy(BOOK.PUBLISHED_IN)
      .limit(2).withTies()
      .fetch();
```

Чтобы отличить WITH TIES от обычного LIMIT, две или более книги должны иметь одинаковый PUBLISHED_IN на границе страницы.

### JQ-27. IN с подзапросом

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [IN predicate](https://www.jooq.org/doc/3.21/manual/sql-building/conditional-expressions/in-predicate/).
- Проверяет: фильтрацию по множеству значений, полученному из отдельного SELECT.

```sql
SELECT BOOK.ID, BOOK.TITLE
FROM BOOK
WHERE BOOK.LANGUAGE_ID IN (
  SELECT LANGUAGE.ID
  FROM LANGUAGE
  WHERE LANGUAGE.CD = 'en'
)
ORDER BY BOOK.ID
```

```java
create.select(BOOK.ID, BOOK.TITLE)
      .from(BOOK)
      .where(BOOK.LANGUAGE_ID.in(
          select(LANGUAGE.ID)
              .from(LANGUAGE)
              .where(LANGUAGE.CD.eq("en"))))
      .orderBy(BOOK.ID)
      .fetch();
```

#### OCaml (typed-sql)

```ocaml
let jq27 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Author.table
      |> where (fun author ->
        let prolific_authors =
          Query.(
            from Book.table
            |> where (fun book -> Book.published_in book >$ 2000)
            |> select_scalar Book.author_id)
        in
        in_subquery (Author.id author) prolific_authors)
      |> select (fun author -> Projection.expr (Author.id author))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq27);;
SELECT
  t0."id"
FROM "author" AS t0
WHERE
  (t0."id" IN (
    SELECT
      t1."author_id"
    FROM "book" AS t1
    WHERE
      (t1."published_in" > $1)
  ))
```

### JQ-28. Сравнение row value expressions

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Row value expressions](https://www.jooq.org/doc/3.21/manual/sql-building/column-expressions/row-value-expressions/).
- Проверяет: лексикографическое сравнение пары значений в одном предикате.
- Ограничение: Row-value сравнение раскрыто в эквивалентный лексикографический предикат `OR`/`AND`.

```sql
SELECT BOOK.ID, BOOK.PUBLISHED_IN
FROM BOOK
WHERE (BOOK.PUBLISHED_IN, BOOK.ID) > (1950, 10)
ORDER BY BOOK.PUBLISHED_IN, BOOK.ID
```

```java
create.select(BOOK.ID, BOOK.PUBLISHED_IN)
      .from(BOOK)
      .where(row(BOOK.PUBLISHED_IN, BOOK.ID).gt(row(1950, 10)))
      .orderBy(BOOK.PUBLISHED_IN, BOOK.ID)
      .fetch();
```

## Агрегация, окна и операции над множествами

#### OCaml (typed-sql, лексикографическая форма)

```ocaml
let jq28 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Book.table
      |> where (fun book ->
        (Book.published_in book >$ 1950)
        ||. ((Book.published_in book =$ 1950) &&. (Book.id book >$ 100)))
      |> select (fun book -> Projection.pair (Book.published_in book) (Book.id book))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq28);;
SELECT
  t0."published_in",
  t0."id"
FROM "book" AS t0
WHERE
  ((t0."published_in" > $1) OR ((t0."published_in" = $2) AND (t0."id" > $3)))
```

### JQ-29. GROUP BY ROLLUP для подытогов

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✗)
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [GROUP BY ROLLUP](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/group-by-clause/group-by-rollup/).
- Проверяет: группы по автору и году, подытоги по автору и общий итог.
- Ограничение: Публичный API не выражает `ROLLUP` или grouping sets; обычная группировка не создаст строки подытогов.

```sql
SELECT BOOK.AUTHOR_ID, BOOK.PUBLISHED_IN, COUNT(*)
FROM BOOK
GROUP BY ROLLUP (BOOK.AUTHOR_ID, BOOK.PUBLISHED_IN)
ORDER BY BOOK.AUTHOR_ID, BOOK.PUBLISHED_IN
```

```java
create.select(BOOK.AUTHOR_ID, BOOK.PUBLISHED_IN, count())
      .from(BOOK)
      .groupBy(rollup(BOOK.AUTHOR_ID, BOOK.PUBLISHED_IN))
      .orderBy(BOOK.AUTHOR_ID, BOOK.PUBLISHED_IN)
      .fetch();
```

Для проверки всех уровней свёртки нужны несколько авторов и несколько лет публикации; сравнить группы по ключам, подытоги по автору и общий итог.

### JQ-30. FILTER для условного агрегата

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Aggregate FILTER](https://www.jooq.org/doc/3.21/manual/sql-building/column-expressions/aggregate-functions/aggregate-filter/).
- Проверяет: несколько агрегатов над одной группой с разными условиями отбора.
- Ограничение: Условный агрегат выражен как `SUM(CASE ...)`; отдельного aggregate `FILTER` в текущем API нет.

```sql
SELECT BOOK.AUTHOR_ID,
       COUNT(*),
       COUNT(*) FILTER (WHERE BOOK.TITLE LIKE 'A%')
FROM BOOK
GROUP BY BOOK.AUTHOR_ID
ORDER BY BOOK.AUTHOR_ID
```

```java
create.select(
          BOOK.AUTHOR_ID,
          count(),
          count().filterWhere(BOOK.TITLE.like("A%")))
      .from(BOOK)
      .groupBy(BOOK.AUTHOR_ID)
      .orderBy(BOOK.AUTHOR_ID)
      .fetch();
```

В диалектах без нативного FILTER jOOQ может использовать эквивалентное условное выражение внутри агрегата.

#### OCaml (typed-sql, CASE внутри агрегата)

```ocaml
let jq30 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Book.table
      |> group_by Book.author_id
      |> select (fun book ->
        Projection.pair
          (Book.author_id book)
          (Expr.sum_int
             (Expr.case
                [ Book.published_in book >$ 2000,
                  Expr.constant Db_type.int 1 ]
                ~else_:(Expr.constant Db_type.int 0))))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq30);;
SELECT
  t0."author_id",
  SUM(CASE WHEN (t0."published_in" > $1) THEN $2 ELSE $3 END)
FROM "book" AS t0
GROUP BY
  t0."author_id"
```

### JQ-31. Оконная сумма с явным frame

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✗)
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [Window frame clause](https://www.jooq.org/doc/3.21/manual/sql-building/column-expressions/window-functions/window-frame/).
- Проверяет: накопительный агрегат отдельно для каждого автора в порядке ID книги.
- Ограничение: Публичный API не содержит оконных функций и определения оконного frame.

```sql
SELECT BOOK.AUTHOR_ID, BOOK.ID,
       SUM(BOOK.ID) OVER (
         PARTITION BY BOOK.AUTHOR_ID
         ORDER BY BOOK.ID
         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS RUNNING_ID_SUM
FROM BOOK
ORDER BY BOOK.AUTHOR_ID, BOOK.ID
```

```java
create.select(
          BOOK.AUTHOR_ID,
          BOOK.ID,
          sum(BOOK.ID)
              .over(partitionBy(BOOK.AUTHOR_ID)
                  .orderBy(BOOK.ID)
                  .rowsBetweenUnboundedPreceding()
                  .andCurrentRow())
              .as("running_id_sum"))
      .from(BOOK)
      .orderBy(BOOK.AUTHOR_ID, BOOK.ID)
      .fetch();
```

### JQ-32. QUALIFY для top-per-group

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [QUALIFY clause](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/qualify-clause/).
- Проверяет: фильтрацию по оконной функции после вычисления ROW_NUMBER.
- Ограничение: `QUALIFY ROW_NUMBER() = 1` заменён `NOT EXISTS` по более поздней книге; ID разрешает равенство года.

```sql
SELECT BOOK.LANGUAGE_ID, BOOK.ID, BOOK.TITLE
FROM BOOK
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY BOOK.LANGUAGE_ID
  ORDER BY BOOK.ID
) = 1
ORDER BY BOOK.LANGUAGE_ID, BOOK.ID
```

```java
create.select(BOOK.LANGUAGE_ID, BOOK.ID, BOOK.TITLE)
      .from(BOOK)
      .qualify(rowNumber()
          .over(partitionBy(BOOK.LANGUAGE_ID).orderBy(BOOK.ID))
          .eq(1))
      .orderBy(BOOK.LANGUAGE_ID, BOOK.ID)
      .fetch();
```

QUALIFY доступен не во всех СУБД; jOOQ поддерживает его как DSL-операцию и может по настройке переписать запрос через derived table.

#### OCaml (typed-sql, NOT EXISTS emulation)

```ocaml
let jq32 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Book.table
      |> where (fun book ->
        not_exists
          (Query.(
            from Book.table
            |> where (fun newer ->
              (Book.author_id newer =. Book.author_id book)
              &&. ((Book.published_in newer >. Book.published_in book)
                   ||. ((Book.published_in newer =. Book.published_in book)
                        &&. (Book.id newer >. Book.id book)))))))
      |> select (fun book -> Projection.pair (Book.author_id book) (Book.id book))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq32);;
SELECT
  t0."author_id",
  t0."id"
FROM "book" AS t0
WHERE
  NOT EXISTS (
    SELECT 1
    FROM "book" AS t1
    WHERE
      ((t1."author_id" = t0."author_id") AND ((t1."published_in" > t0."published_in") OR ((t1."published_in" = t0."published_in") AND (t1."id" > t0."id"))))
  )
```

### JQ-33. INTERSECT двух выборок

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Set operations](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/set-operations/).
- Проверяет: пересечение результатов с одинаковой формой проекции и удаление дубликатов.

```sql
SELECT BOOK.ID
FROM BOOK
WHERE BOOK.PUBLISHED_IN <= 1950
INTERSECT
SELECT BOOK.ID
FROM BOOK
WHERE BOOK.TITLE LIKE 'A%'
ORDER BY ID
```

```java
select(BOOK.ID)
    .from(BOOK)
    .where(BOOK.PUBLISHED_IN.le(1950))
    .intersect(select(BOOK.ID)
        .from(BOOK)
        .where(BOOK.TITLE.like("A%")))
    .orderBy(BOOK.ID)
    .fetch();
```

#### OCaml (typed-sql)

```ocaml
let jq33_left =
  Query.(
    from Book.table
    |> where (fun book -> Book.published_in book <$ 1950)
    |> select (fun book -> Projection.expr (Book.author_id book)))

let jq33_right =
  Query.(
    from Book.table
    |> where (fun book -> Book.published_in book >$ 2000)
    |> select (fun book -> Projection.expr (Book.author_id book)))

let jq33 = Statement.Portable.query_many_exn (fun _ -> Query.intersect jq33_left jq33_right)
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq33);;
SELECT
  t0."author_id"
FROM "book" AS t0
WHERE
  (t0."published_in" < $1)
INTERSECT
SELECT
  t0."author_id"
FROM "book" AS t0
WHERE
  (t0."published_in" > $2)
```

### JQ-34. EXCEPT для разности выборок

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Set operations](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/set-operations/).
- Проверяет: удаление из первого результата строк, присутствующих во втором.

```sql
SELECT BOOK.ID
FROM BOOK
WHERE BOOK.PUBLISHED_IN <= 1950
EXCEPT
SELECT BOOK.ID
FROM BOOK
WHERE BOOK.TITLE LIKE 'A%'
ORDER BY ID
```

```java
select(BOOK.ID)
    .from(BOOK)
    .where(BOOK.PUBLISHED_IN.le(1950))
    .except(select(BOOK.ID)
        .from(BOOK)
        .where(BOOK.TITLE.like("A%")))
    .orderBy(BOOK.ID)
    .fetch();
```

#### OCaml (typed-sql)

```ocaml
let jq34_left =
  Query.(
    from Author.table
    |> select (fun author -> Projection.expr (Author.id author)))

let jq34_right =
  Query.(
    from Book.table
    |> where (fun book -> Book.published_in book >$ 2000)
    |> select (fun book -> Projection.expr (Book.author_id book)))

let jq34 = Statement.Portable.query_many_exn (fun _ -> Query.except jq34_left jq34_right)
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq34);;
SELECT
  t0."id"
FROM "author" AS t0
EXCEPT
SELECT
  t0."author_id"
FROM "book" AS t0
WHERE
  (t0."published_in" > $1)
```

### JQ-35. LISTAGG с порядком элементов

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✗)
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [LISTAGG](https://www.jooq.org/doc/3.21/manual/sql-building/column-expressions/aggregate-functions/listagg-function/).
- Проверяет: сбор строк группы в строку и детерминированный порядок внутри агрегата.
- Ограничение: Нет строкового агрегата `LISTAGG`/`STRING_AGG` с aggregate-local `ORDER BY`; список строк не совпадает с одной результирующей строкой.

```sql
SELECT BOOK.AUTHOR_ID,
       LISTAGG(BOOK.TITLE, ', ') WITHIN GROUP (ORDER BY BOOK.ID)
FROM BOOK
GROUP BY BOOK.AUTHOR_ID
ORDER BY BOOK.AUTHOR_ID
```

```java
create.select(
          BOOK.AUTHOR_ID,
          listAgg(BOOK.TITLE, ", ").withinGroupOrderBy(BOOK.ID))
      .from(BOOK)
      .groupBy(BOOK.AUTHOR_ID)
      .orderBy(BOOK.AUTHOR_ID)
      .fetch();
```

## Дополнительные DML-сценарии

### JQ-36. INSERT .. SELECT

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✗)
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [INSERT .. SELECT](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/insert-statement/insert-select/).
- Проверяет: вставку набора строк, выбранного из другой таблицы.
- Ограничение: `Insert` принимает VALUES-строки; публичного `INSERT ... SELECT` конструктора нет.

```sql
INSERT INTO BOOK_ARCHIVE (ID, TITLE)
SELECT BOOK.ID, BOOK.TITLE
FROM BOOK
WHERE BOOK.PUBLISHED_IN < 1900
```

```java
create.insertInto(BOOK_ARCHIVE, BOOK_ARCHIVE.ID, BOOK_ARCHIVE.TITLE)
      .select(select(BOOK.ID, BOOK.TITLE)
          .from(BOOK)
          .where(BOOK.PUBLISHED_IN.lt(1900)))
      .execute();
```

### JQ-37. INSERT RETURNING

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [INSERT .. RETURNING](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/insert-statement/insert-returning/).
- Проверяет: получение сгенерированного ID вставленной строки без отдельного SELECT в пользовательском коде.

```sql
INSERT INTO AUTHOR (FIRST_NAME, LAST_NAME)
VALUES ('Terry', 'Pratchett')
RETURNING ID
```

```java
Record1<Integer> inserted =
    create.insertInto(AUTHOR, AUTHOR.FIRST_NAME, AUTHOR.LAST_NAME)
          .values("Terry", "Pratchett")
          .returningResult(AUTHOR.ID)
          .fetchOne();
```

Получение generated key зависит от диалекта; jOOQ может использовать поддерживаемый драйвером механизм вместо буквального RETURNING.

#### OCaml (typed-sql)

```ocaml
let jq37 =
  Statement.Portable.query_many_exn (fun _ ->
    Insert.(
      into Book.table
      |> set Book.title_column "New title"
      |> set Book.author_id_column 1
      |> returning (fun book -> Projection.pair (Book.id book) (Book.title book))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq37);;
INSERT INTO "book" ("title", "author_id")
VALUES ($1, $2)
RETURNING
  "id",
  "title"
```

### JQ-38. UPDATE с выражением от прежнего значения

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [UPDATE statement](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/update-statement/).
- Проверяет: вычисление нового значения на стороне SQL и ограничение обновляемых строк.

```sql
UPDATE BOOK
SET PUBLISHED_IN = PUBLISHED_IN + 1
WHERE ID = 10
```

```java
create.update(BOOK)
      .set(BOOK.PUBLISHED_IN, BOOK.PUBLISHED_IN.add(1))
      .where(BOOK.ID.eq(10))
      .execute();
```

#### OCaml (typed-sql)

```ocaml
let jq38 =
  Statement.Portable.command_exn (fun _ ->
    Update.(
      table Book.table
      |> from Book.table ~f:(fun target source update ->
        update
        |> set_expr Book.published_in_column
          Expr.Int.Infix.(Book.published_in target +. Expr.constant Db_type.int 1)
        |> where (fun _ -> Book.id target =. Book.id source))
      |> where (fun book -> Book.published_in book <$ 1950)
      |> command))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq38);;
UPDATE "book" AS t0
SET "published_in" = (t1."published_in" + $1)
FROM "book" AS t1
WHERE
  ((t0."id" = t1."id") AND (t0."published_in" < $2))
```

### JQ-39. DELETE USING

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [DELETE .. USING](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/delete-statement/delete-using/).
- Проверяет: удаление целевых строк по условию, зависящему от соединённой таблицы.
- Ограничение: `DELETE ... USING` выражен эквивалентным коррелированным `WHERE EXISTS`; отдельного API для USING нет.

```sql
DELETE FROM BOOK_ARCHIVE
USING BOOK
WHERE BOOK_ARCHIVE.ID = BOOK.ID
  AND BOOK.PUBLISHED_IN < 1900
```

```java
create.deleteFrom(BOOK_ARCHIVE)
      .using(BOOK)
      .where(BOOK_ARCHIVE.ID.eq(BOOK.ID)
          .and(BOOK.PUBLISHED_IN.lt(1900)))
      .execute();
```

Для проверки нужны совпадающие архивные записи с книгами до и после граничного года.

#### OCaml (typed-sql, WHERE EXISTS эквивалент)

```ocaml
let jq39 =
  Statement.Portable.command_exn (fun _ ->
    Delete.(
      from Book.table
      |> where (fun book ->
        Query.exists
          (Query.(
            from Author.table
            |> where (fun author -> Author.id author =. Book.author_id book))))
      |> command))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq39);;
DELETE FROM "book" AS t0
WHERE
  EXISTS (
    SELECT 1
    FROM "author" AS t1
    WHERE
      (t1."id" = t0."author_id")
  )
```

### JQ-40. MERGE с UPDATE и INSERT

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✗)
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [MERGE statement](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/merge-statement/).
- Проверяет: обновление совпавшей архивной строки и вставку строки, которой ещё нет в целевой таблице.
- Ограничение: Публичный API поддерживает `ON CONFLICT`, но не стандартизованный `MERGE` с ветвями matched/not matched.

```sql
MERGE INTO BOOK_ARCHIVE
USING BOOK ON BOOK_ARCHIVE.ID = BOOK.ID
WHEN MATCHED THEN
  UPDATE SET TITLE = BOOK.TITLE
WHEN NOT MATCHED THEN
  INSERT (ID, TITLE) VALUES (BOOK.ID, BOOK.TITLE)
```

```java
create.mergeInto(BOOK_ARCHIVE)
      .using(BOOK)
      .on(BOOK_ARCHIVE.ID.eq(BOOK.ID))
      .whenMatchedThenUpdate()
      .set(BOOK_ARCHIVE.TITLE, BOOK.TITLE)
      .whenNotMatchedThenInsert(BOOK_ARCHIVE.ID, BOOK_ARCHIVE.TITLE)
      .values(BOOK.ID, BOOK.TITLE)
      .execute();
```

Фикстура должна содержать как совпадающий ID, который обновится, так и ID, который будет вставлен.

## Дополнительные SELECT-сценарии

### JQ-41. Keyset-страница по году и ID

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [SEEK clause](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/seek-clause/).
- Проверяет: лексикографическую границу по двум ключам, устойчивую сортировку и отсутствие повторов при переходе к следующей странице.

```sql
SELECT BOOK.ID, BOOK.TITLE, BOOK.PUBLISHED_IN
FROM BOOK
WHERE (BOOK.PUBLISHED_IN, BOOK.ID) > (?, ?)
ORDER BY BOOK.PUBLISHED_IN ASC, BOOK.ID ASC
LIMIT 10
```

```java
create.select(BOOK.ID, BOOK.TITLE, BOOK.PUBLISHED_IN)
      .from(BOOK)
      .orderBy(BOOK.PUBLISHED_IN.asc(), BOOK.ID.asc())
      .seek(lastYear, lastId)
      .limit(10)
      .fetch();
```

#### OCaml (typed-sql)

```ocaml
let jq41 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Book.table
      |> where (fun book ->
        (Book.published_in book >$ 2000)
        ||. ((Book.published_in book =$ 2000) &&. (Book.id book >$ 100)))
      |> order_by Book.published_in `Asc
      |> order_by Book.id `Asc
      |> limit 20
      |> select (fun book ->
        Projection.map3
          ~f:(fun year id title -> year, id, title)
          (Projection.expr (Book.published_in book))
          (Projection.expr (Book.id book))
          (Projection.expr (Book.title book)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq41);;
SELECT
  t0."published_in",
  t0."id",
  t0."title"
FROM "book" AS t0
WHERE
  ((t0."published_in" > $1) OR ((t0."published_in" = $2) AND (t0."id" > $3)))
ORDER BY
  t0."published_in" ASC,
  t0."id" ASC
LIMIT 20
```

### JQ-42. Конкурентный выбор строк с SKIP LOCKED

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✗)
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [FOR UPDATE clause](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/for-update-clause/).
- Проверяет: блокировку только выбранных строк и пропуск уже заблокированных строк в другой транзакции; показана форма PostgreSQL.
- Ограничение: Публичный SELECT builder не имеет `FOR UPDATE` или политики `SKIP LOCKED`; это влияет на конкурентную семантику.

```sql
SELECT BOOK.ID, BOOK.TITLE
FROM BOOK
WHERE BOOK.PUBLISHED_IN < ?
ORDER BY BOOK.ID ASC
LIMIT 5
FOR UPDATE SKIP LOCKED
```

```java
create.select(BOOK.ID, BOOK.TITLE)
      .from(BOOK)
      .where(BOOK.PUBLISHED_IN.lt(cutoffYear))
      .orderBy(BOOK.ID.asc())
      .limit(5)
      .forUpdate()
      .skipLocked()
      .fetch();
```

### JQ-43. CUBE по автору и году издания

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✗)
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [GROUP BY CUBE](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/group-by-clause/group-by-cube/).
- Проверяет: детализацию, два вида промежуточных итогов и общий итог в одном наборе; в фикстуре исходные ключи не содержат `NULL`, поэтому он обозначает свернутую размерность.
- Ограничение: Публичный API не выражает `CUBE`/grouping sets; добавление нескольких обычных GROUP BY ключей не создаёт подытоги.

```sql
SELECT BOOK.AUTHOR_ID, BOOK.PUBLISHED_IN, COUNT(*)
FROM BOOK
GROUP BY CUBE (BOOK.AUTHOR_ID, BOOK.PUBLISHED_IN)
```

```java
create.select(BOOK.AUTHOR_ID, BOOK.PUBLISHED_IN, count())
      .from(BOOK)
      .groupBy(cube(BOOK.AUTHOR_ID, BOOK.PUBLISHED_IN))
      .fetch();
```

## Команды с RETURNING и обработкой конфликтов

### JQ-44. DELETE RETURNING удалённых архивных записей

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [DELETE RETURNING](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/delete-statement/delete-returning/).
- Проверяет: возврат `ID` и `TITLE` только у строк, реально удалённых по `IS NULL`; показана форма PostgreSQL.

```sql
DELETE FROM BOOK_ARCHIVE
WHERE BOOK_ARCHIVE.ARCHIVED_AT IS NULL
RETURNING BOOK_ARCHIVE.ID, BOOK_ARCHIVE.TITLE
```

```java
create.deleteFrom(BOOK_ARCHIVE)
      .where(BOOK_ARCHIVE.ARCHIVED_AT.isNull())
      .returningResult(BOOK_ARCHIVE.ID, BOOK_ARCHIVE.TITLE)
      .fetch();
```

#### OCaml (typed-sql)

```ocaml
let jq44 =
  Statement.Portable.query_many_exn (fun _ ->
    Delete.(
      from Book_archive.table
      |> where (fun archive -> Expr.is_null (Book_archive.archived_at archive))
      |> returning (fun archive -> Projection.pair (Book_archive.id archive) (Book_archive.title archive))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq44);;
DELETE FROM "book_archive"
WHERE
  ("archived_at" IS NULL)
RETURNING
  "id",
  "title"
```

### JQ-45. INSERT из SELECT с пропуском конфликтов

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✗)
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [INSERT statement](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/insert-statement/), раздел `ON CONFLICT`.
- Проверяет: вставку набора старых книг в архив и пропуск уже архивированных ID без обновления их заголовков; показана форма PostgreSQL.
- Ограничение: UPSERT conflict action поддержан, но источник `INSERT ... SELECT` отсутствует в публичном API.

```sql
INSERT INTO BOOK_ARCHIVE (ID, TITLE)
SELECT BOOK.ID, BOOK.TITLE
FROM BOOK
WHERE BOOK.PUBLISHED_IN < ?
ON CONFLICT (ID) DO NOTHING
```

```java
create.insertInto(BOOK_ARCHIVE, BOOK_ARCHIVE.ID, BOOK_ARCHIVE.TITLE)
      .select(create.select(BOOK.ID, BOOK.TITLE)
                    .from(BOOK)
                    .where(BOOK.PUBLISHED_IN.lt(cutoffYear)))
      .onConflict(BOOK_ARCHIVE.ID)
      .doNothing()
      .execute();
```


### JQ-46. Nullable-фильтр с null-safe сравнением

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [NULL predicates](https://www.jooq.org/doc/3.21/manual/sql-building/conditional-expressions/null-predicate/).
- Проверяет: поиск значения с определённой обработкой SQL `NULL`.

```sql
SELECT BOOK_ARCHIVE.ID
FROM BOOK_ARCHIVE
WHERE BOOK_ARCHIVE.ARCHIVED_AT IS NULL
```

#### OCaml (typed-sql)

```ocaml
let jq46 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Book_archive.table
      |> where (fun archive -> Expr.is_null (Book_archive.archived_at archive))
      |> select (fun archive -> Projection.expr (Book_archive.id archive))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq46);;
SELECT
  t0."id"
FROM "book_archive" AS t0
WHERE
  (t0."archived_at" IS NULL)
```

### JQ-47. Scalar aggregate с COALESCE

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [aggregate functions](https://www.jooq.org/doc/3.21/manual/sql-building/column-expressions/aggregate-functions/).
- Проверяет: скалярный `COUNT` и явное значение по умолчанию для пустой выборки.

```sql
SELECT COALESCE((SELECT COUNT(*) FROM BOOK WHERE AUTHOR_ID = 1), 0)
```

#### OCaml (typed-sql)

```ocaml
let jq47 =
  Statement.Portable.query_one_exn (fun _ ->
    Query.select_one
      (Expr.coalesce
         (Expr.scalar_subquery
            (Query.(
              from Book.table
              |> where (fun book -> Book.author_id book =$ 1)
              |> select_scalar (fun _ -> Expr.count_all))))
         ~default:(Expr.constant Db_type.int64 0L)))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq47);;
SELECT
  COALESCE((
    SELECT
      COUNT(*)
    FROM "book" AS t0
    WHERE
      (t0."author_id" = $1)
  ), $2)
```

### JQ-48. CTE с ограниченным списком авторов

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [common table expressions](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/with-clause/).
- Проверяет: именованный CTE, фильтр внутри и чтение результата во внешнем запросе.

```sql
WITH selected_authors AS (
  SELECT ID, LAST_NAME FROM AUTHOR WHERE ID > 10
)
SELECT ID, LAST_NAME FROM selected_authors ORDER BY ID
```

#### OCaml (typed-sql)

```ocaml
let jq48_relation =
  Derived_table.create
    ~table:Author.table
    ~columns:(fun author -> Projection.pair (Author.id author) (Author.last_name author))
    Query.(
      from Author.table
      |> where (fun author -> Author.id author >$ 10)
      |> select (fun author -> Projection.pair (Author.id author) (Author.last_name author)))

let jq48_cte = Cte.select jq48_relation

let jq48 =
  Statement.Portable.query_many_exn (fun _ ->
    Cte.with_result jq48_cte ~f:(fun selected ->
      Query.(
        from_cte selected
        |> order_by Author.id `Asc
        |> select (fun author -> Projection.pair (Author.id author) (Author.last_name author)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq48);;
WITH
  "c0" (
    "id",
    "last_name"
  ) AS (
    SELECT
      t0."id",
      t0."last_name"
    FROM "author" AS t0
    WHERE
      (t0."id" > $1)
  )
SELECT
  t0."id",
  t0."last_name"
FROM "c0" AS t0
ORDER BY
  t0."id" ASC
```

### JQ-49. UPSERT с возвратом изменённой строки

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [INSERT .. ON CONFLICT](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/insert-statement/insert-on-conflict/).
- Проверяет: conflict target, присваивание из `excluded` и `RETURNING`.

```sql
INSERT INTO BOOK (ID, TITLE, AUTHOR_ID) VALUES (9, 'Updated', 1)
ON CONFLICT (ID) DO UPDATE SET TITLE = EXCLUDED.TITLE
RETURNING ID, TITLE
```

#### OCaml (typed-sql)

```ocaml
let jq49 =
  Statement.Portable.query_many_exn (fun _ ->
    Insert.(
      into Book.table
      |> set Book.id_column 9
      |> set Book.title_column "Updated"
      |> set Book.author_id_column 1
      |> on_conflict (Conflict_target.column Book.id_column)
      |> do_update (fun ~existing:_ ~excluded ->
        Conflict_update.set_expr Book.title_column (Book.title excluded) Conflict_update.empty)
      |> returning (fun book -> Projection.pair (Book.id book) (Book.title book))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq49);;
INSERT INTO "book" ("id", "title", "author_id")
VALUES ($1, $2, $3)
ON CONFLICT ("id") DO UPDATE SET "title" = EXCLUDED."title"
RETURNING
  "id",
  "title"
```

### JQ-50. Условное ограничение по году

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [dynamic SQL](https://www.jooq.org/doc/3.21/manual/sql-building/dynamic-sql/).
- Проверяет: добавление предиката через `where_opt` и сортировку результата.

```sql
SELECT ID, TITLE FROM BOOK WHERE PUBLISHED_IN >= 2000 ORDER BY ID
```

#### OCaml (typed-sql)

```ocaml
let jq50 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Book.table
      |> where_opt (Some 2000) ~f:(fun book year -> Book.published_in book >=$ year)
      |> order_by Book.id `Asc
      |> select (fun book -> Projection.pair (Book.id book) (Book.title book))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq50);;
SELECT
  t0."id",
  t0."title"
FROM "book" AS t0
WHERE
  (t0."published_in" >= $1)
ORDER BY
  t0."id" ASC
```

### JQ-51. Счётчик книг после LEFT JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [outer joins](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/join-clause/).
- Проверяет: сохранение авторов без книг и подсчёт только ненулевых ID книги.

```sql
SELECT AUTHOR.ID, COUNT(BOOK.ID)
FROM AUTHOR LEFT JOIN BOOK ON BOOK.AUTHOR_ID = AUTHOR.ID
GROUP BY AUTHOR.ID
```

#### OCaml (typed-sql)

```ocaml
let jq51 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Author.table
      |> left_join Book.table ~on:(fun author book -> Author.id author =. Book.author_id book)
      |> group_by (fun (author, _book) -> Author.id author)
      |> select (fun (author, book) ->
        Projection.pair (Author.id author) (Expr.count (Book.nullable_id book)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq51);;
SELECT
  t0."id",
  COUNT(t1."id")
FROM "author" AS t0
LEFT JOIN "book" AS t1
  ON (t0."id" = t1."author_id")
GROUP BY
  t0."id"
```

### JQ-52. Фильтр NOT IN по значениям

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [IN predicate](https://www.jooq.org/doc/3.21/manual/sql-building/conditional-expressions/in-predicate/).
- Проверяет: исключение списка ID с bind-параметрами.

```sql
SELECT ID FROM BOOK WHERE ID NOT IN (1, 2, 3)
```

#### OCaml (typed-sql)

```ocaml
let jq52 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Book.table
      |> where (fun book -> Expr.not_in (Book.id book) [ 1; 2; 3 ])
      |> select (fun book -> Projection.expr (Book.id book))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq52);;
SELECT
  t0."id"
FROM "book" AS t0
WHERE
  (t0."id" NOT IN ($1, $2, $3))
```

### JQ-53. Группировка и порог числа книг

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [GROUP BY and HAVING](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/group-by-clause/).
- Проверяет: соединение, группировку по автору, агрегатный фильтр и порядок.

```sql
SELECT AUTHOR.ID, COUNT(*) FROM AUTHOR JOIN BOOK ON BOOK.AUTHOR_ID = AUTHOR.ID
GROUP BY AUTHOR.ID HAVING COUNT(*) >= 2 ORDER BY AUTHOR.ID
```

#### OCaml (typed-sql)

```ocaml
let jq53 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Author.table
      |> inner_join Book.table ~on:(fun author book -> Author.id author =. Book.author_id book)
      |> group_by (fun (author, _book) -> Author.id author)
      |> having (fun _ -> Expr.count_all >=$ 2L)
      |> order_by (fun (author, _book) -> Author.id author) `Asc
      |> select (fun (author, _book) -> Projection.pair (Author.id author) Expr.count_all)))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq53);;
SELECT
  t0."id",
  COUNT(*)
FROM "author" AS t0
INNER JOIN "book" AS t1
  ON (t0."id" = t1."author_id")
GROUP BY
  t0."id"
HAVING
  (COUNT(*) >= $1)
ORDER BY
  t0."id" ASC
```

### JQ-54. Условная метка в проекции

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [CASE expressions](https://www.jooq.org/doc/3.21/manual/sql-building/column-expressions/case-expressions/).
- Проверяет: типизированный CASE и фильтрацию исходных строк.

```sql
SELECT ID, CASE WHEN PUBLISHED_IN >= 2000 THEN 'recent' ELSE 'older' END
FROM BOOK WHERE AUTHOR_ID = 1
```

#### OCaml (typed-sql)

```ocaml
let jq54 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Book.table
      |> where (fun book -> Book.author_id book =$ 1)
      |> select (fun book ->
        Projection.pair
          (Book.id book)
          (Expr.case
             [ Book.published_in book >=$ 2000,
               Expr.constant Db_type.text "recent" ]
             ~else_:(Expr.constant Db_type.text "older")))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq54);;
SELECT
  t0."id",
  CASE WHEN (t0."published_in" >= $1) THEN $2 ELSE $3 END
FROM "book" AS t0
WHERE
  (t0."author_id" = $4)
```

### JQ-55. UPDATE RETURNING с фильтром по году

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [UPDATE .. RETURNING](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/update-statement/).
- Проверяет: серверное изменение строк и возврат ключей с новыми значениями.

```sql
UPDATE BOOK SET PUBLISHED_IN = 2020 WHERE PUBLISHED_IN < 1900 RETURNING ID, PUBLISHED_IN
```

#### OCaml (typed-sql)

```ocaml
let jq55 =
  Statement.Portable.query_many_exn (fun _ ->
    Update.(
      table Book.table
      |> set Book.published_in_column 2020
      |> where (fun book -> Book.published_in book <$ 1900)
      |> returning (fun book -> Projection.pair (Book.id book) (Book.published_in book))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq55);;
UPDATE "book"
SET "published_in" = $1
WHERE
  ("published_in" < $2)
RETURNING
  "id",
  "published_in"
```

### JQ-56. Многострочный INSERT

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [INSERT values](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/insert-statement/).
- Проверяет: одинаковый набор колонок в двух строках одной команды.

```sql
INSERT INTO BOOK (ID, TITLE, AUTHOR_ID) VALUES (101, 'A', 1), (102, 'B', 1)
```

#### OCaml (typed-sql)

```ocaml
let jq56 =
  Statement.Portable.command_exn (fun _ ->
    Insert.rows Book.table
      [ (fun row -> row |> Insert.set Book.id_column 101 |> Insert.set Book.title_column "A" |> Insert.set Book.author_id_column 1)
      ; (fun row -> row |> Insert.set Book.id_column 102 |> Insert.set Book.title_column "B" |> Insert.set Book.author_id_column 1)
      ]
    |> Insert.command)
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq56);;
INSERT INTO "book" ("id", "title", "author_id")
VALUES ($1, $2, $3), ($4, $5, $6)
```

### JQ-57. UNION ALL сохраняет повторы

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [UNION ALL](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/set-operations/).
- Проверяет: объединение результатов без дедупликации.

```sql
SELECT AUTHOR_ID FROM BOOK WHERE PUBLISHED_IN < 1950
UNION ALL SELECT AUTHOR_ID FROM BOOK WHERE PUBLISHED_IN > 2000
```

#### OCaml (typed-sql)

```ocaml
let jq57_old = Query.(from Book.table |> where (fun book -> Book.published_in book <$ 1950) |> select (fun book -> Projection.expr (Book.author_id book)))
let jq57_new = Query.(from Book.table |> where (fun book -> Book.published_in book >$ 2000) |> select (fun book -> Projection.expr (Book.author_id book)))
let jq57 = Statement.Portable.query_many_exn (fun _ -> Query.union_all jq57_old jq57_new)
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq57);;
SELECT
  t0."author_id"
FROM "book" AS t0
WHERE
  (t0."published_in" < $1)
UNION ALL
SELECT
  t0."author_id"
FROM "book" AS t0
WHERE
  (t0."published_in" > $2)
```

### JQ-58. Книги дешевле максимального ID в группе

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [scalar subqueries](https://www.jooq.org/doc/3.21/manual/sql-building/column-expressions/scalar-subqueries/).
- Проверяет: коррелированный scalar aggregate, `COALESCE` и фильтр внешней строки.

```sql
SELECT ID, AUTHOR_ID FROM BOOK
WHERE ID < (SELECT MAX(ID) FROM BOOK AS B2 WHERE B2.AUTHOR_ID = BOOK.AUTHOR_ID)
```

#### OCaml (typed-sql)

```ocaml
let jq58 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Book.table
      |> where (fun book ->
        Book.id book <.
        Expr.coalesce
          (Expr.scalar_subquery_nullable
             (Query.(
               from Book.table
               |> where (fun other -> Book.author_id other =. Book.author_id book)
               |> select_scalar (fun other -> Expr.max Db_type.Orderable.int (Book.id other)))))
          ~default:(Expr.constant Db_type.int Int.max_value))
      |> select (fun book -> Projection.pair (Book.id book) (Book.author_id book))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq58);;
SELECT
  t0."id",
  t0."author_id"
FROM "book" AS t0
WHERE
  (t0."id" < COALESCE((
    SELECT
      MAX(t1."id")
    FROM "book" AS t1
    WHERE
      (t1."author_id" = t0."author_id")
  ), $1))
```

### JQ-59. Авторы с книгой до 1950 без книги после 2000

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [EXISTS predicate](https://www.jooq.org/doc/3.21/manual/sql-building/conditional-expressions/exists-predicate/).
- Проверяет: совместное применение положительного и отрицательного коррелированных EXISTS.

```sql
SELECT ID FROM AUTHOR
WHERE EXISTS (SELECT 1 FROM BOOK WHERE AUTHOR_ID = AUTHOR.ID AND PUBLISHED_IN < 1950)
AND NOT EXISTS (SELECT 1 FROM BOOK WHERE AUTHOR_ID = AUTHOR.ID AND PUBLISHED_IN > 2000)
```

#### OCaml (typed-sql)

```ocaml
let jq59 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Author.table
      |> where (fun author ->
        let has_old_book =
          Query.exists
            (Query.(
              from Book.table
              |> where (fun book ->
                (Book.author_id book =. Author.id author)
                &&. (Book.published_in book <$ 1950)))
        in
        let lacks_recent_book =
          Query.not_exists
            (Query.(
              from Book.table
              |> where (fun book ->
                (Book.author_id book =. Author.id author)
                &&. (Book.published_in book >$ 2000)))
        in
        has_old_book &&. lacks_recent_book)
      |> select (fun author -> Projection.expr (Author.id author))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq59);;
SELECT
  t0."id"
FROM "author" AS t0
WHERE
  (EXISTS (
    SELECT 1 FROM "book" AS t1 WHERE ((t1."author_id" = t0."id") AND (t1."published_in" < $1))
  ) AND NOT EXISTS (
    SELECT 1 FROM "book" AS t2 WHERE ((t2."author_id" = t0."id") AND (t2."published_in" > $2))
  ))
```

### JQ-60. JOIN, группировка, HAVING и стабильная страница

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [SELECT statement](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/).
- Проверяет: соединение, диапазон года, агрегатный порог, составной порядок и пагинацию.

```sql
SELECT AUTHOR.ID, COUNT(*) FROM AUTHOR JOIN BOOK ON BOOK.AUTHOR_ID = AUTHOR.ID
WHERE BOOK.PUBLISHED_IN >= 1950 GROUP BY AUTHOR.ID HAVING COUNT(*) > 1
ORDER BY AUTHOR.ID LIMIT 10 OFFSET 5
```

#### OCaml (typed-sql)

```ocaml
let jq60 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Author.table
      |> inner_join Book.table ~on:(fun author book -> Author.id author =. Book.author_id book)
      |> where (fun (_author, book) -> Book.published_in book >=$ 1950)
      |> group_by (fun (author, _book) -> Author.id author)
      |> having (fun _ -> Expr.count_all >$ 1L)
      |> order_by (fun (author, _book) -> Author.id author) `Asc
      |> limit 10
      |> offset 5
      |> select (fun (author, _book) -> Projection.pair (Author.id author) Expr.count_all)))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql jq60);;
SELECT
  t0."id",
  COUNT(*)
FROM "author" AS t0
INNER JOIN "book" AS t1
  ON (t0."id" = t1."author_id")
WHERE
  (t1."published_in" >= $1)
GROUP BY
  t0."id"
HAVING
  (COUNT(*) > $2)
ORDER BY
  t0."id" ASC
LIMIT 10
OFFSET 5
```
