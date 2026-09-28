<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Сценарии запросов из jOOQ

Начальная выборка сценариев из [руководства пользователя jOOQ 3.21](https://www.jooq.org/doc/3.21/manual/). Это каталог для последующего переноса запросов в общий regression-набор. Он не претендует на полный список возможностей jOOQ.

Источник: *The jOOQ User Manual*, © 2009–2026 Data Geekery GmbH, лицензия [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Запросы отобраны, сокращены и местами адаптированы; ссылки ведут к исходным разделам. Этот файл с адаптациями распространяется на условиях CC BY-SA 4.0. Указание источника не означает одобрения со стороны jOOQ или Data Geekery GmbH.

Для запросов используется схема примеров jOOQ: `AUTHOR`, `BOOK`, `LANGUAGE`, `BOOK_STORE` и `BOOK_TO_BOOK_STORE`. Состав и примерные данные описаны в [разделе о sample database](https://www.jooq.org/doc/3.21/manual/getting-started/sample-database/). Значения в SQL показаны для ясности; при переносе нужно проверить, что значения остаются bind-параметрами.

Отмечать `[x]` следует после того, как сценарий перенесён в regression-набор и проверен на заявленных диалектах. Записи, где синтаксис является синтетическим расширением jOOQ, требуют проверки сгенерированного SQL; приведённая там форма SQL может не исполняться напрямую.

## SELECT и фильтрация

### JQ-01. Фильтр, JOIN, группировка, сортировка и страница

- [ ] Перенесено в regression-набор.
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

### JQ-02. Условный предикат и форма запроса

- [ ] Перенесено в regression-набор.
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

### JQ-03. LEFT JOIN с отсутствующей правой строкой

- [ ] Перенесено в regression-набор.
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

### JQ-04. Коррелированный EXISTS

- [ ] Перенесено в regression-набор.
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

Отдельным вариантом того же сценария стоит проверить `NOT EXISTS`.

### JQ-05. Коррелированный scalar subquery в projection

- [ ] Перенесено в regression-набор.
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

### JQ-06. Derived table с агрегатом

- [ ] Перенесено в regression-набор.
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

- [ ] Перенесено в regression-набор.
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

- [ ] Перенесено в regression-набор.
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

- [ ] Перенесено в regression-набор.
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

- [ ] Перенесено в regression-набор.
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

- [ ] Перенесено в regression-набор.
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

- [ ] Перенесено в regression-набор.
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

- [ ] Перенесено в regression-набор.
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

- [ ] Перенесено в regression-набор.
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

- [ ] Перенесено в regression-набор.
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
