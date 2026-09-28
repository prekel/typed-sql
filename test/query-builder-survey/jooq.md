<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Сценарии запросов из jOOQ

Подборка 45 сценариев из [руководства пользователя jOOQ 3.21](https://www.jooq.org/doc/3.21/manual/). Это каталог для последующего включения запросов в общий набор автоматических тестов. Он не претендует на полный список возможностей jOOQ.

**Желаемый таргет: 60–100 сценариев.**

Источник: *The jOOQ User Manual*, © 2009–2026 Data Geekery GmbH, лицензия [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Запросы отобраны, сокращены и местами адаптированы; ссылки ведут к исходным разделам. Этот файл с адаптациями распространяется на условиях CC BY-SA 4.0. Указание источника не означает одобрения со стороны jOOQ или Data Geekery GmbH.

Для запросов используется схема примеров jOOQ: `AUTHOR`, `BOOK`, `LANGUAGE`, `BOOK_STORE` и `BOOK_TO_BOOK_STORE`. Состав и примерные данные описаны в [разделе о sample database](https://www.jooq.org/doc/3.21/manual/getting-started/sample-database/). Значения в SQL показаны для ясности; при переносе нужно проверить, что значения остаются bind-параметрами.

Для JQ-16–JQ-45 сохраняется эта схема и используются две дополнительные фикстуры: BOOK_ARCHIVE (ID, TITLE, ARCHIVED_AT), где ID сопоставим с BOOK.ID, а ARCHIVED_AT допускает NULL; и DIRECTORY (ID, PARENT_ID, LABEL) с корнем и несколькими уровнями потомков. Для проверки сортировки NULLS LAST нужны строки архива как с NULL, так и с ненулевым ARCHIVED_AT.

Записи, где синтаксис является синтетическим расширением jOOQ, требуют проверки сгенерированного SQL; приведённая там форма SQL может не исполняться напрямую.

Для JQ-01–JQ-10 и JQ-12–JQ-15 приведены реализации на typed-sql и SQL, полученный его компилятором; JQ-11 пока не выражается публичным API. JQ-16–JQ-45 приведены как сценарии для сравнения SQL и Java DSL jOOQ без реализации на typed-sql. В блоках «SQL typed-sql» первая строка запускает компилятор, остальные строки — его вывод. OCaml-блоки выполняются через MDX: `opam exec -- dune runtest test/query-builder-survey`; проверка подтверждает построение запросов typed-sql и вывод SQL.

В карточках JQ-01–JQ-15 статусы означают: `✓` — подтверждено; `✗` — условие не выполнено; `—` — не оценивалось. «Семантика» учитывает входные параметры, результат, `NULL` и заданный порядок относительно адаптированного сценария в этой карточке. «Без доработок» относится к публичному API typed-sql, а не к необходимости улучшить пример. Реализуемость оценивается после попытки написать OCaml-код.

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
  let id row = Expr.column row id_column
  let author_id row = Expr.column row author_id_column
  let title row = Expr.column row title_column
  let published_in row = Expr.column row published_in_column
  let nullable_id row = Expr.nullable_column row id_column
  let nullable_title row = Expr.nullable_column row title_column
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
- Семантика: ✗
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

- OCaml-пример: ✗
- Реализуемость: ✗
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [Window PARTITION BY](https://www.jooq.org/doc/3.21/manual/sql-building/column-expressions/window-functions/window-partition/).
- Проверяет: значение по группе рядом с каждой исходной строкой.

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

Оконные выражения (`OVER (PARTITION BY ...)`) отсутствуют в публичном API и semantic AST typed-sql. Сценарий нельзя выразить без расширения DSL.

## Вложенные коллекции

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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

### JQ-17. CROSS JOIN двух отношений

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [CROSS JOIN](https://www.jooq.org/doc/3.21/manual/sql-building/table-expressions/joined-tables/join-type-cross/).
- Проверяет: декартово произведение таблиц и его размер до применения последующих фильтров.

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

### JQ-18. JOIN USING с общей колонкой

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [USING clause](https://www.jooq.org/doc/3.21/manual/sql-building/table-expressions/joined-tables/join-predicate-using/).
- Проверяет: соединение по одноимённому ключу и использование общей колонки в USING.

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

### JQ-19. LATERAL: книга с максимальным ID для каждого автора с книгами

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [LATERAL](https://www.jooq.org/doc/3.21/manual/sql-building/table-expressions/joined-tables/join-mode-lateral/).
- Проверяет: корреляцию правой табличной функции с текущим автором и выбор не более одной книги на автора.

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

### JQ-20. VALUES как табличный источник

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [VALUES table constructor](https://www.jooq.org/doc/3.21/manual/sql-building/table-expressions/values/).
- Проверяет: использование набора констант как relation с именованной колонкой.

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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [WITH RECURSIVE](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/with-recursive-clause/).
- Проверяет: anchor member, рекурсивное соединение с предыдущим уровнем и глубину узла.

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

### JQ-22. SELECT DISTINCT по внешнему ключу

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

### JQ-23. DISTINCT ON: первая книга каждого языка

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [SELECT DISTINCT ON](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/select-clause/select-clause-distinct-on/).
- Проверяет: выбор первой строки каждой группы согласно явному порядку.

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

### JQ-24. CASE для классификации книг

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

### JQ-25. Сортировка NULLS LAST

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [ORDER BY clause](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/order-by-clause/order-by-nulls-ordering/).
- Проверяет: явное положение NULL относительно ненулевых значений.

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

### JQ-26. FETCH FIRST WITH TIES

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [WITH TIES clause](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/with-ties-clause/).
- Проверяет: включение всех строк, связанных с последней строкой ограниченной страницы по ключу сортировки.

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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

### JQ-28. Сравнение row value expressions

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [Row value expressions](https://www.jooq.org/doc/3.21/manual/sql-building/column-expressions/row-value-expressions/).
- Проверяет: лексикографическое сравнение пары значений в одном предикате.

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

### JQ-29. GROUP BY ROLLUP для подытогов

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [GROUP BY ROLLUP](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/group-by-clause/group-by-rollup/).
- Проверяет: группы по автору и году, подытоги по автору и общий итог.

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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [Aggregate FILTER](https://www.jooq.org/doc/3.21/manual/sql-building/column-expressions/aggregate-functions/aggregate-filter/).
- Проверяет: несколько агрегатов над одной группой с разными условиями отбора.

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

### JQ-31. Оконная сумма с явным frame

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [Window frame clause](https://www.jooq.org/doc/3.21/manual/sql-building/column-expressions/window-functions/window-frame/).
- Проверяет: накопительный агрегат отдельно для каждого автора в порядке ID книги.

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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [QUALIFY clause](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/qualify-clause/).
- Проверяет: фильтрацию по оконной функции после вычисления ROW_NUMBER.

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

### JQ-33. INTERSECT двух выборок

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

### JQ-34. EXCEPT для разности выборок

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

### JQ-35. LISTAGG с порядком элементов

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [LISTAGG](https://www.jooq.org/doc/3.21/manual/sql-building/column-expressions/aggregate-functions/listagg-function/).
- Проверяет: сбор строк группы в строку и детерминированный порядок внутри агрегата.

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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [INSERT .. SELECT](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/insert-statement/insert-select/).
- Проверяет: вставку набора строк, выбранного из другой таблицы.

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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

### JQ-38. UPDATE с выражением от прежнего значения

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

### JQ-39. DELETE USING

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [DELETE .. USING](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/delete-statement/delete-using/).
- Проверяет: удаление целевых строк по условию, зависящему от соединённой таблицы.

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

### JQ-40. MERGE с UPDATE и INSERT

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [MERGE statement](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/merge-statement/).
- Проверяет: обновление совпавшей архивной строки и вставку строки, которой ещё нет в целевой таблице.

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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

### JQ-42. Конкурентный выбор строк с SKIP LOCKED

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [FOR UPDATE clause](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/for-update-clause/).
- Проверяет: блокировку только выбранных строк и пропуск уже заблокированных строк в другой транзакции; показана форма PostgreSQL.

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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [GROUP BY CUBE](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/select-statement/group-by-clause/group-by-cube/).
- Проверяет: детализацию, два вида промежуточных итогов и общий итог в одном наборе; в фикстуре исходные ключи не содержат `NULL`, поэтому он обозначает свернутую размерность.

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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

### JQ-45. INSERT из SELECT с пропуском конфликтов

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [INSERT statement](https://www.jooq.org/doc/3.21/manual/sql-building/sql-statements/insert-statement/), раздел `ON CONFLICT`.
- Проверяет: вставку набора старых книг в архив и пропуск уже архивированных ID без обновления их заголовков; показана форма PostgreSQL.

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
