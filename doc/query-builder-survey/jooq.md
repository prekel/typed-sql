<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Сценарии запросов из jOOQ

Начальная выборка сценариев из [руководства пользователя jOOQ 3.21](https://www.jooq.org/doc/3.21/manual/). Это каталог для последующего включения запросов в общий набор автоматических тестов. Он не претендует на полный список возможностей jOOQ.

**Желаемый таргет: 60–100 сценариев.**

Источник: *The jOOQ User Manual*, © 2009–2026 Data Geekery GmbH, лицензия [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Запросы отобраны, сокращены и местами адаптированы; ссылки ведут к исходным разделам. Этот файл с адаптациями распространяется на условиях CC BY-SA 4.0. Указание источника не означает одобрения со стороны jOOQ или Data Geekery GmbH.

Для запросов используется схема примеров jOOQ: `AUTHOR`, `BOOK`, `LANGUAGE`, `BOOK_STORE` и `BOOK_TO_BOOK_STORE`. Состав и примерные данные описаны в [разделе о sample database](https://www.jooq.org/doc/3.21/manual/getting-started/sample-database/). Значения в SQL показаны для ясности; при переносе нужно проверить, что значения остаются bind-параметрами.

Записи, где синтаксис является синтетическим расширением jOOQ, требуют проверки сгенерированного SQL; приведённая там форма SQL может не исполняться напрямую.

Для JQ-01–JQ-05 ниже приведены реализация на typed-sql и SQL, полученный её компилятором. В блоках «SQL typed-sql» первая строка запускает компилятор, остальные строки — его вывод. OCaml-блоки выполняются через MDX: `opam exec -- dune runtest doc/query-builder-survey`. Проверка MDX подтверждает построение запроса и вывод SQL.

Статусы в карточках: `✓` — подтверждено; `✗` — условие не выполнено; `—` — не оценивалось. «Семантика» учитывает входные параметры, результат, `NULL` и заданный порядок относительно адаптированного сценария в этой карточке. «Без доработок» относится к публичному API typed-sql, а не к необходимости улучшить пример. Реализуемость оценивается после попытки написать OCaml-код.

## Общие дескрипторы для JQ-01–JQ-05

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

```
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

Отдельным вариантом того же сценария стоит проверить `NOT EXISTS`.

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

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —

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
      .orderBy(nested.field("books"))
      .fetch();
```

### JQ-07. CTE, используемый как relation

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —

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

### JQ-08. UNION двух SELECT

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —

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

## Агрегация и аналитика

### JQ-09. GROUP BY и HAVING

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —

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

### JQ-10. HAVING без GROUP BY и cardinality агрегата

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —

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

### JQ-11. Оконный агрегат без схлопывания строк

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —

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

## Вложенные коллекции

### JQ-12. MULTISET из коррелированного подзапроса

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —

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

### JQ-13. MULTISET_AGG по группе

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —

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

Это также синтетический jOOQ operator; отдельно проверить дубликаты и порядок элементов. Чтобы проверить пустую коллекцию, нужен вариант с авторами без книг и соответствующей семантикой outer join/filter.

## Изменение данных

### JQ-14. INSERT ON CONFLICT DO UPDATE

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —

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

### JQ-15. UPDATE с FROM

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —

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
