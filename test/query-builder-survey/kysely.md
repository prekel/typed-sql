<!-- SPDX-License-Identifier: MIT -->

# Сценарии запросов из Kysely

Первые 50 сценариев по [API Kysely](https://kysely-org.github.io/kysely-apidoc/) (доступ 28.09.2026). Примеры сокращены и адаптированы. Это каталог кандидатов для автоматических тестов запросов; приведённый SQL показывает ожидаемую форму для PostgreSQL, а не побайтовый снимок вывода Kysely. Плейсхолдеры `$1`, `$2` и далее обозначают bind-параметры.

**Желаемый таргет: 50–70 сценариев.**

Источник примеров: Kysely, © 2022 Sami Koskimäki, [лицензия MIT](https://github.com/kysely-org/kysely/blob/master/LICENSE). Копирайт и текст разрешения приведены в конце файла. Схема: `person(id PK generated, first_name, last_name, age, manager_id, profile JSONB)`, `pet(id PK generated, owner_id, name, species)` и `person_import(id PK, first_name, last_name, age)`. `manager_id`, `last_name` и `profile` допускают `NULL`; для `pet.name` задано ограничение уникальности. Для проверки nullable-результатов нужна персона без питомцев.

Переносимы между PostgreSQL и SQLite 3.46 сценарии KY-16, KY-18–KY-25, KY-27–KY-33, KY-36–KY-40 и KY-43–KY-46. Сценарии KY-17, KY-26, KY-34–KY-35, KY-41–KY-42 и KY-47–KY-50 используют возможности отдельных диалектов.

Для KY-01–KY-05 ниже добавлены реализация на typed-sql и SQL, полученный её компилятором. Для KY-06–KY-50 добавлены OCaml-примеры там, где запрос или эквивалентная ему семантика выразимы текущим публичным API. Блоки отмечают эмуляции, которые используют другой SQL-приём. В блоках «SQL typed-sql» первая строка запускает компилятор, остальные строки — его вывод. Запустить проверку документа можно командой `opam exec -- dune runtest test/query-builder-survey`.

Статусы в карточках: `✓` — запрос выражен текущим API и его семантика сверена по коду; `✗` — условие не выполнено; `—` — не оценивалось. MDX-команда проверяет OCaml-примеры и снимки сгенерированного SQL; она не выполняет запросы на сервере базы данных. «Семантика» учитывает входные параметры, результат, `NULL` и заданный порядок относительно сценария в карточке. «Без доработок» относится к публичному API typed-sql, а не к необходимости улучшить пример. Реализуемость оценивается после попытки написать OCaml-код.

## Общие дескрипторы для KY-01–KY-50

`Person` и `Pet` используются во всех сценариях; `Pet_counts` и `Descendants` описывают выходные поля derived table и recursive CTE.

```ocaml
open! Base
open Typed_sql
open Infix

module Person = struct
  type row

  let table : row Table.t = Table.v_exn "person"
  let id_column = Column.v_exn table "id" Db_type.int64
  let first_name_column = Column.v_exn table "first_name" Db_type.text
  let last_name_column = Column.v_exn table "last_name" Db_type.text
  let age_column = Column.v_exn table "age" Db_type.int
  let manager_id_column = Column.v_exn table "manager_id" (Db_type.option Db_type.int64)
  let id row = Expr.column row id_column
  let first_name row = Expr.column row first_name_column
  let last_name row = Expr.column row last_name_column
  let age row = Expr.column row age_column
  let manager_id row = Expr.column row manager_id_column
  let nullable_last_name row = Expr.to_nullable (last_name row)
end

module Person_import = struct
  type row

  let table : row Table.t = Table.v_exn "person_import"
  let id_column = Column.v_exn table "id" Db_type.int64
  let first_name_column = Column.v_exn table "first_name" Db_type.text
  let last_name_column = Column.v_exn table "last_name" Db_type.text
  let age_column = Column.v_exn table "age" Db_type.int
  let id row = Expr.column row id_column
  let first_name row = Expr.column row first_name_column
  let last_name row = Expr.column row last_name_column
  let age row = Expr.column row age_column
end

module Pet = struct
  type row

  let table : row Table.t = Table.v_exn "pet"
  let id_column = Column.v_exn table "id" Db_type.int64
  let owner_id_column = Column.v_exn table "owner_id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let species_column = Column.v_exn table "species" Db_type.text
  let id row = Expr.column row id_column
  let owner_id row = Expr.column row owner_id_column
  let name row = Expr.column row name_column
  let species row = Expr.column row species_column
  let nullable_name row = Expr.nullable_column row name_column
end

module Pet_counts = struct
  type row

  let table : row Table.t = Table.v_exn "pet_counts"
  let owner_id_column = Column.v_exn table "owner_id" Db_type.int64
  let pet_count_column = Column.v_exn table "pet_count" Db_type.int64
  let owner_id row = Expr.column row owner_id_column
  let pet_count row = Expr.column row pet_count_column
  let projection row = Projection.pair (owner_id row) (pet_count row)
end

module Descendants = struct
  type row

  let table : row Table.t = Table.v_exn "descendants"
  let id_column = Column.v_exn table "id" Db_type.int64
  let manager_id_column = Column.v_exn table "manager_id" (Db_type.option Db_type.int64)
  let id row = Expr.column row id_column
  let manager_id row = Expr.column row manager_id_column
  let projection row = Projection.pair (id row) (manager_id row)
end

```

### KY-01. Фильтр и проекция

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: `minAge` передаётся через runtime input.
- Источник: [select](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#select), [where](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#where).
- Проверяет: проекцию и bind-параметр.

```sql
SELECT "id", "first_name" FROM "person" WHERE "age" >= $1
```

```typescript
await db.selectFrom('person')
  .select(['id', 'first_name'])
  .where('age', '>=', minAge)
  .execute()
```

#### OCaml (typed-sql)

Фильтр по возрасту остаётся bind-параметром; проекция сохраняет обе колонки.

```ocaml
let kysely01 =
  Statement.Portable.query_many_exn (fun params ->
    let min_age = params.expr Db_type.int ~get:Fn.id in
    Query.(
      from Person.table
      |> where (fun person -> Person.age person >=. min_age)
      |> select (fun person ->
        Projection.pair (Person.id person) (Person.first_name person))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:18 kysely01);;
SELECT
  t0."id",
  t0."first_name"
FROM "person" AS t0
WHERE
  (t0."age" >= $1)
```

### KY-02. Условный фильтр

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [динамическая композиция WHERE](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#where).
- Проверяет: две формы запроса при наличии и отсутствии фильтра.

```sql
SELECT "id" FROM "person"
-- When minAge is defined:
SELECT "id" FROM "person" WHERE "age" >= $1
```

```typescript
let query = db.selectFrom('person').select('id')
if (minAge !== undefined) {
  query = query.where('age', '>=', minAge)
}
await query.execute()
```

#### OCaml (typed-sql)

Опциональный фильтр меняет форму SQL, поэтому используется динамический statement. MDX печатает оба варианта.

```ocaml
let kysely02 =
  Statement.Dynamic.Portable.query_many (fun minimum_age ->
    Query.(
      from Person.table
      |> where_opt minimum_age ~f:(fun person age -> Person.age person >=$ age)
      |> select (fun person -> Projection.expr (Person.id person))))
```

#### SQL typed-sql (PostgreSQL, фильтр есть)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:(Some 18) kysely02);;
SELECT
  t0."id"
FROM "person" AS t0
WHERE
  (t0."age" >= $1)
```

#### SQL typed-sql (PostgreSQL, фильтр отсутствует)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:None kysely02);;
SELECT
  t0."id"
FROM "person" AS t0
```

### KY-03. Вложенные AND и OR

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: `young`, `old` и `surname` передаются через runtime input.
- Источник: [ExpressionBuilder](https://kysely-org.github.io/kysely-apidoc/interfaces/ExpressionBuilder.html).
- Проверяет: приоритет и группировку предикатов.

```sql
SELECT "id" FROM "person"
WHERE ("age" < $1 OR "age" > $2) AND "last_name" = $3
```

```typescript
await db.selectFrom('person')
  .select('id')
  .where((eb) => eb.and([
    eb.or([eb('age', '<', young), eb('age', '>', old)]),
    eb('last_name', '=', surname),
  ]))
  .execute()
```

#### OCaml (typed-sql)

Условия собраны с явными скобками: OR остаётся внутри AND.

```ocaml
let kysely03 =
  Statement.Portable.query_many_exn (fun params ->
    let young = params.expr Db_type.int ~get:(fun (young, _, _) -> young) in
    let old = params.expr Db_type.int ~get:(fun (_, old, _) -> old) in
    let surname = params.expr Db_type.text ~get:(fun (_, _, surname) -> surname) in
    Query.(
      from Person.table
      |> where (fun person ->
        ((Person.age person <. young) ||. (Person.age person >. old))
        &&. (Person.last_name person =. surname))
      |> select (fun person -> Projection.expr (Person.id person))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:(18, 65, "Smith") kysely03);;
SELECT
  t0."id"
FROM "person" AS t0
WHERE
  (
    (
      (t0."age" < $1)
      OR (t0."age" > $2)
    )
    AND (t0."last_name" = $3)
  )
```

### KY-04. INNER JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [innerJoin](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#innerJoin).
- Проверяет: связь двух таблиц и квалификацию одинаковых имён колонок.

```sql
SELECT "person"."id", "pet"."name"
FROM "person"
INNER JOIN "pet" ON "pet"."owner_id" = "person"."id"
```

```typescript
await db.selectFrom('person')
  .innerJoin('pet', 'pet.owner_id', 'person.id')
  .select(['person.id', 'pet.name'])
  .execute()
```

#### OCaml (typed-sql)

Обе таблицы имеют собственные типизированные ссылки; одинаковые имена колонок не требуют ручного alias.

```ocaml
let kysely04 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Person.table
      |> inner_join Pet.table ~on:(fun person pet ->
        Pet.owner_id pet =. Person.id person)
      |> select (fun (person, pet) ->
        Projection.pair (Person.id person) (Pet.name pet))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely04);;
SELECT
  t0."id",
  t1."name"
FROM "person" AS t0
INNER JOIN "pet" AS t1
  ON (t1."owner_id" = t0."id")
```

### KY-05. LEFT JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [leftJoin](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#leftJoin).
- Проверяет: сохранение персоны без питомца и nullable-правую сторону.

```sql
SELECT "person"."id", "pet"."name"
FROM "person"
LEFT JOIN "pet" ON "pet"."owner_id" = "person"."id"
```

```typescript
await db.selectFrom('person')
  .leftJoin('pet', 'pet.owner_id', 'person.id')
  .select(['person.id', 'pet.name'])
  .execute()
```

#### OCaml (typed-sql)

После LEFT JOIN имя питомца становится nullable в OCaml-типе результата.

```ocaml
let kysely05 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Person.table
      |> left_join Pet.table ~on:(fun person pet ->
        Pet.owner_id pet =. Person.id person)
      |> select (fun (person, pet) ->
        Projection.pair (Person.id person) (Pet.nullable_name pet))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely05);;
SELECT
  t0."id",
  t1."name"
FROM "person" AS t0
LEFT JOIN "pet" AS t1
  ON (t1."owner_id" = t0."id")
```

### KY-06. Группировка и HAVING

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [groupBy](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#groupBy), [having](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#having).
- Проверяет: агрегат в проекции и предикате группы.

```sql
SELECT "owner_id", COUNT("id") AS "pet_count"
FROM "pet"
GROUP BY "owner_id"
HAVING COUNT("id") > $1
```

```typescript
await db.selectFrom('pet')
  .select((eb) => [
    'owner_id',
    eb.fn.count<number>('id').as('pet_count'),
  ])
  .groupBy('owner_id')
  .having((eb) => eb.fn.count('id'), '>', minCount)
  .execute()
```

#### OCaml (typed-sql)

`HAVING` сравнивает агрегат с runtime bind-параметром.

```ocaml
let kysely06 =
  Statement.Portable.query_many_exn (fun params ->
    let minimum_count = params.expr Db_type.int64 ~get:Fn.id in
    Query.(
      from Pet.table
      |> group_by Pet.owner_id
      |> having (fun pet -> Expr.count (Pet.id pet) >. minimum_count)
      |> select (fun pet ->
        Projection.map2
          ~f:(fun owner_id count -> owner_id, count)
          (Projection.expr (Pet.owner_id pet))
          (Projection.expr (Expr.count (Pet.id pet))))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely06);;
SELECT
  t0."owner_id",
  COUNT(t0."id")
FROM "pet" AS t0
GROUP BY
  t0."owner_id"
HAVING
  (COUNT(t0."id") > $1)
```
### KY-07. Коррелированный scalar subquery

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [select с подзапросом](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#select).
- Проверяет: обращение к внешней строке и ноль вместо NULL для пустой группы.

```sql
SELECT "person"."id",
       (SELECT COUNT("pet"."id") FROM "pet"
        WHERE "pet"."owner_id" = "person"."id") AS "pet_count"
FROM "person"
```

```typescript
await db.selectFrom('person')
  .select((eb) => [
    'person.id',
    eb.selectFrom('pet')
      .select((inner) => inner.fn.count<number>('pet.id').as('pet_count'))
      .whereRef('pet.owner_id', '=', 'person.id')
      .as('pet_count'),
  ])
  .execute()
```

#### OCaml (typed-sql)

Глобальная агрегатная scalar query возвращает `0` для владельца без питомцев.

```ocaml
let kysely07 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Person.table
      |> select (fun person ->
        let pet_count =
          Query.(
            from Pet.table
            |> where (fun pet -> Pet.owner_id pet =. Person.id person)
            |> select_scalar (fun pet -> Expr.count (Pet.id pet)))
        in
        Projection.map2
          ~f:(fun id count -> id, count)
          (Projection.expr (Person.id person))
          (Projection.expr
             (Expr.coalesce
                (Expr.scalar_subquery pet_count)
                ~default:(Expr.constant Db_type.int64 0L))))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely07);;
SELECT
  t0."id",
  COALESCE((
    SELECT
      COUNT(t1."id")
    FROM "pet" AS t1
    WHERE
      (t1."owner_id" = t0."id")
  ), $1)
FROM "person" AS t0
```
### KY-08. Коррелированный EXISTS

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [exists](https://kysely-org.github.io/kysely-apidoc/interfaces/ExpressionBuilder.html#exists).
- Проверяет: фильтр по наличию связанной строки.

```sql
SELECT "person"."id"
FROM "person"
WHERE EXISTS (
  SELECT "pet"."id" FROM "pet"
  WHERE "pet"."owner_id" = "person"."id"
)
```

```typescript
await db.selectFrom('person')
  .select('person.id')
  .where((eb) => eb.exists(
    eb.selectFrom('pet')
      .select('pet.id')
      .whereRef('pet.owner_id', '=', 'person.id')
  ))
  .execute()
```

#### OCaml (typed-sql)

`Query.exists` оставляет по одной строке на человека независимо от числа питомцев.

```ocaml
let kysely08 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Person.table
      |> where (fun person ->
        exists
          (from Pet.table
           |> where (fun pet -> Pet.owner_id pet =. Person.id person)))
      |> select (fun person -> Projection.expr (Person.id person))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely08);;
SELECT
  t0."id"
FROM "person" AS t0
WHERE
  (EXISTS (
    SELECT
      1
    FROM "pet" AS t1
    WHERE
      (t1."owner_id" = t0."id")
  ))
```
### KY-09. Derived table

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [selectFrom](https://kysely-org.github.io/kysely-apidoc/classes/Kysely.html#selectFrom), [as](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#as).
- Проверяет: агрегированный подзапрос как источник строк.

```sql
SELECT "counts"."owner_id", "counts"."pet_count"
FROM (
  SELECT "owner_id", COUNT("id") AS "pet_count"
  FROM "pet" GROUP BY "owner_id"
) AS "counts"
WHERE "counts"."pet_count" > $1
```

```typescript
const counts = db.selectFrom('pet')
  .select((eb) => [
    'owner_id',
    eb.fn.count<number>('id').as('pet_count'),
  ])
  .groupBy('owner_id')
  .as('counts')

await db.selectFrom(counts)
  .select(['counts.owner_id', 'counts.pet_count'])
  .where('counts.pet_count', '>', minCount)
  .execute()
```

#### OCaml (typed-sql)

Агрегированный SELECT становится derived relation с проверенным описанием полей.

```ocaml
let kysely09 =
  Statement.Portable.query_many_exn (fun params ->
    let minimum_count = params.expr Db_type.int64 ~get:Fn.id in
    let counts =
      Derived_table.create
        ~table:Pet_counts.table
        ~columns:Pet_counts.projection
        Query.(
          from Pet.table
          |> group_by Pet.owner_id
          |> select (fun pet ->
            Projection.pair (Pet.owner_id pet) (Expr.count (Pet.id pet))))
    in
    Query.(
      from_derived counts
      |> where (fun count -> Pet_counts.pet_count count >. minimum_count)
      |> select (fun count -> Pet_counts.projection count)))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely09);;
SELECT
  t0."owner_id",
  t0."pet_count"
FROM (
  SELECT
    t1."owner_id" AS "owner_id",
    COUNT(t1."id") AS "pet_count"
  FROM "pet" AS t1
  GROUP BY
    t1."owner_id"
) AS t0
WHERE
  (t0."pet_count" > $1)
```
### KY-10. CTE

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [with](https://kysely-org.github.io/kysely-apidoc/classes/Kysely.html#with).
- Проверяет: объявление и использование именованного запроса.

```sql
WITH "older_people" AS (
  SELECT "id", "first_name" FROM "person" WHERE "age" >= $1
)
SELECT "id", "first_name" FROM "older_people"
```

```typescript
await db.with('older_people', (db) =>
    db.selectFrom('person')
      .select(['id', 'first_name'])
      .where('age', '>=', minAge))
  .selectFrom('older_people')
  .select(['id', 'first_name'])
  .execute()
```

#### OCaml (typed-sql)

CTE объявляется из typed derived relation и доступен только внутри callback.

```ocaml
let kysely10 =
  Statement.Portable.query_many_exn (fun params ->
    let minimum_age = params.expr Db_type.int ~get:Fn.id in
    let older_people =
      Derived_table.create
        ~table:Person.table
        ~columns:(fun person ->
          Projection.pair (Person.id person) (Person.first_name person))
        Query.(
          from Person.table
          |> where (fun person -> Person.age person >=. minimum_age)
          |> select (fun person ->
            Projection.pair (Person.id person) (Person.first_name person)))
    in
    Cte.with_result (Cte.select older_people) ~f:(fun older_people ->
      Query.(
        from_cte older_people
        |> select (fun person ->
          Projection.pair (Person.id person) (Person.first_name person)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely10);;
WITH
  "c0" (
    "id",
    "first_name"
  ) AS (
    SELECT
      t0."id",
      t0."first_name"
    FROM "person" AS t0
    WHERE
      (t0."age" >= $1)
  )
SELECT
  t0."id",
  t0."first_name"
FROM "c0" AS t0
```
### KY-11. UNION

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [union](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#union).
- Проверяет: совместимость проекций и удаление дублей.

```sql
SELECT "first_name" AS "name" FROM "person"
UNION
SELECT "name" FROM "pet"
```

```typescript
await db.selectFrom('person')
  .select('first_name as name')
  .union(db.selectFrom('pet').select('name'))
  .execute()
```

#### OCaml (typed-sql)

```ocaml
let kysely11 =
  Statement.Portable.query_many_exn (fun _ ->
    let people =
      Query.(from Person.table |> select (fun person -> Projection.expr (Person.first_name person)))
    in
    let pets =
      Query.(from Pet.table |> select (fun pet -> Projection.expr (Pet.name pet)))
    in
    Query.union people pets)
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely11);;
SELECT *
FROM (
  SELECT
    t0."first_name"
  FROM "person" AS t0
) AS s0
UNION
SELECT *
FROM (
  SELECT
    t0."name"
  FROM "pet" AS t0
) AS s0
```
### KY-12. Оконный агрегат

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: Оконная форма не строится публичным API; коррелированный `COUNT` вычисляет то же число для каждой строки.
- Источник: [over](https://kysely-org.github.io/kysely-apidoc/interfaces/AggregateFunctionBuilder.html#over).
- Проверяет: число питомцев в каждой группе без схлопывания строк.

```sql
SELECT "id", "owner_id",
       COUNT("id") OVER (PARTITION BY "owner_id") AS "owner_pet_count"
FROM "pet"
```

```typescript
await db.selectFrom('pet')
  .select((eb) => [
    'id',
    'owner_id',
    eb.fn.count<number>('id')
      .over((ob) => ob.partitionBy('owner_id'))
      .as('owner_pet_count'),
  ])
  .execute()
```

#### OCaml (typed-sql)

Оконный `COUNT` заменён коррелированным scalar aggregate; для каждой строки получается тот же count по владельцу.

```ocaml
let kysely12 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Pet.table
      |> select (fun pet ->
        let owner_count =
          Query.(
            from Pet.table
            |> where (fun other -> Pet.owner_id other =. Pet.owner_id pet)
            |> select_scalar (fun other -> Expr.count (Pet.id other)))
        in
        Projection.map2
          ~f:(fun (id, owner_id) count -> id, owner_id, count)
          (Projection.pair (Pet.id pet) (Pet.owner_id pet))
          (Projection.expr
             (Expr.coalesce
                (Expr.scalar_subquery owner_count)
                ~default:(Expr.constant Db_type.int64 0L))))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely12);;
SELECT
  t0."id",
  t0."owner_id",
  COALESCE((
    SELECT
      COUNT(t1."id")
    FROM "pet" AS t1
    WHERE
      (t1."owner_id" = t0."owner_id")
  ), $1)
FROM "pet" AS t0
```
### KY-13. INSERT RETURNING

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [insertInto](https://kysely-org.github.io/kysely-apidoc/classes/Kysely.html#insertInto), [returning](https://kysely-org.github.io/kysely-apidoc/interfaces/InsertQueryBuilder.html#returning).
- Проверяет: вставку со значениями и возвращаемыми колонками.

```sql
INSERT INTO "person" ("first_name", "last_name", "age")
VALUES ($1, $2, $3)
RETURNING "id", "first_name"
```

```typescript
await db.insertInto('person')
  .values({ first_name: firstName, last_name: lastName, age })
  .returning(['id', 'first_name'])
  .executeTakeFirstOrThrow()
```

#### OCaml (typed-sql)

Runtime значения вставки объявлены typed bind-параметрами.

```ocaml
let kysely13 =
  Statement.Portable.expect_one_exn (fun params ->
    let first_name = params.expr Db_type.text ~get:(fun (first_name, _, _) -> first_name) in
    let last_name = params.expr Db_type.text ~get:(fun (_, last_name, _) -> last_name) in
    let age = params.expr Db_type.int ~get:(fun (_, _, age) -> age) in
    Insert.(
      into Person.table
      |> set_expr Person.first_name_column first_name
      |> set_expr Person.last_name_column last_name
      |> set_expr Person.age_column age
      |> returning (fun person -> Projection.pair (Person.id person) (Person.first_name person))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely13);;
INSERT INTO "person" (
  "first_name",
  "last_name",
  "age"
)
VALUES
  ($1, $2, $3)
RETURNING
  "id",
  "first_name"
```
### KY-14. UPDATE RETURNING

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: `UPDATE` использует self-join по уникальному `person.id`, потому что выражение арифметики требует видимого источника строки.
- Источник: [updateTable](https://kysely-org.github.io/kysely-apidoc/classes/Kysely.html#updateTable), [returning](https://kysely-org.github.io/kysely-apidoc/interfaces/UpdateQueryBuilder.html#returning).
- Проверяет: арифметическое обновление и возвращаемую строку.

```sql
UPDATE "person" SET "age" = "age" + $1
WHERE "id" = $2
RETURNING "id", "age"
```

```typescript
await db.updateTable('person')
  .set((eb) => ({ age: eb('age', '+', years) }))
  .where('id', '=', personId)
  .returning(['id', 'age'])
  .executeTakeFirst()
```

#### OCaml (typed-sql)

Чтобы сослаться на обновляемую строку, пример self-joins таблицу по первичному ключу в `UPDATE FROM`.

```ocaml
let kysely14 =
  Statement.Portable.expect_optional_exn (fun params ->
    let person_id = params.expr Db_type.int64 ~get:(fun (person_id, _) -> person_id) in
    let years = params.expr Db_type.int ~get:(fun (_, years) -> years) in
    Update.(
      table Person.table
      |> from Person.table ~f:(fun _target source update ->
        let open Expr.Int.Infix in
        update
        |> set_expr Person.age_column (Person.age source +. years)
        |> where (fun target ->
          (Person.id target =. person_id) &&. (Person.id target =. Person.id source)))
      |> returning (fun person -> Projection.pair (Person.id person) (Person.age person))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely14);;
UPDATE "person" AS t0
SET
  "age" = (t1."age" + $1)
FROM "person" AS t1
WHERE
  (
    (t0."id" = $2)
    AND (t0."id" = t1."id")
  )
RETURNING
  t0."id",
  t0."age"
```
### KY-15. DELETE RETURNING

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [deleteFrom](https://kysely-org.github.io/kysely-apidoc/classes/Kysely.html#deleteFrom), [returning](https://kysely-org.github.io/kysely-apidoc/interfaces/DeleteQueryBuilder.html#returning).
- Проверяет: удаление и данные удалённой строки.

```sql
DELETE FROM "pet" WHERE "id" = $1 RETURNING "id", "name"
```

```typescript
await db.deleteFrom('pet')
  .where('id', '=', petId)
  .returning(['id', 'name'])
  .executeTakeFirst()
```

#### OCaml (typed-sql)

```ocaml
let kysely15 =
  Statement.Portable.expect_optional_exn (fun params ->
    let pet_id = params.column Pet.id_column ~get:Fn.id in
    Delete.(
      from Pet.table
      |> where (fun pet -> Pet.id pet =. pet_id)
      |> returning (fun pet -> Projection.pair (Pet.id pet) (Pet.name pet))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely15);;
DELETE FROM "pet"
WHERE
  ("id" = $1)
RETURNING
  "id",
  "name"
```
### KY-16. DISTINCT

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [distinct](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#distinct).
- Проверяет: удаление повторов после проекции.

```sql
SELECT DISTINCT "species"
FROM "pet"
WHERE "owner_id" = $1
```

```typescript
await db.selectFrom('pet')
  .select('species')
  .where('owner_id', '=', ownerId)
  .distinct()
  .execute()
```

#### OCaml (typed-sql)

```ocaml
let kysely16 =
  Statement.Portable.query_many_exn (fun params ->
    let owner_id = params.column Pet.owner_id_column ~get:Fn.id in
    Query.(
      from Pet.table
      |> where (fun pet -> Pet.owner_id pet =. owner_id)
      |> distinct
      |> select (fun pet -> Projection.expr (Pet.species pet))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely16);;
SELECT DISTINCT
  t0."species"
FROM "pet" AS t0
WHERE
  (t0."owner_id" = $1)
```
### KY-17. DISTINCT ON: первая строка в каждой группе

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: Эмуляция через anti-exists эквивалентна при уникальном `pet.id`; SQL `DISTINCT ON` не генерируется.
- Источник: [distinctOn](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#distinctOn).
- Проверяет: выбор последнего питомца владельца; SQL-форма специфична для PostgreSQL.

```sql
SELECT DISTINCT ON ("owner_id") "owner_id", "id", "name"
FROM "pet"
ORDER BY "owner_id", "id" DESC
```

```typescript
await db.selectFrom('pet')
  .distinctOn('owner_id')
  .select(['owner_id', 'id', 'name'])
  .orderBy('owner_id')
  .orderBy('id', 'desc')
  .execute()
```

#### OCaml (typed-sql)

`DISTINCT ON` выражен через anti-exists: выбирается строка с максимальным `id` владельца и сохраняется порядок исходного результата.

```ocaml
let kysely17 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Pet.table
      |> where (fun pet ->
        not_exists
          (from Pet.table
           |> where (fun newer ->
             (Pet.owner_id newer =. Pet.owner_id pet) &&. (Pet.id newer >. Pet.id pet))))
      |> order_by Pet.owner_id `Asc
      |> order_by Pet.id `Desc
      |> select (fun pet ->
        Projection.map2
          ~f:(fun owner_id (id, name) -> owner_id, id, name)
          (Projection.expr (Pet.owner_id pet))
          (Projection.pair (Pet.id pet) (Pet.name pet)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely17);;
SELECT
  t0."owner_id",
  t0."id",
  t0."name"
FROM "pet" AS t0
WHERE
  (NOT EXISTS (
    SELECT
      1
    FROM "pet" AS t1
    WHERE
      (
        (t1."owner_id" = t0."owner_id")
        AND (t1."id" > t0."id")
      )
  ))
ORDER BY
  t0."owner_id" ASC,
  t0."id" DESC
```
### KY-18. CASE и COALESCE в проекции

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [case и coalesce](https://kysely-org.github.io/kysely-apidoc/interfaces/ExpressionBuilder.html#case).
- Проверяет: условное вычисление и подстановку значения для nullable-колонки.

```sql
SELECT
  "id",
  CASE WHEN "age" >= $1 THEN $2 ELSE $3 END AS "age_group",
  COALESCE("last_name", "first_name") AS "display_name"
FROM "person"
```

```typescript
await db.selectFrom('person')
  .select((eb) => [
    'id',
    eb.case()
      .when('age', '>=', 18)
      .then('adult')
      .else('minor')
      .end()
      .as('age_group'),
    eb.fn.coalesce('last_name', 'first_name').as('display_name'),
  ])
  .execute()
```

#### OCaml (typed-sql)

```ocaml
let kysely18 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Person.table
      |> select (fun person ->
        Projection.map3
          ~f:(fun id age_group display_name -> id, age_group, display_name)
          (Projection.expr (Person.id person))
          (Projection.expr
             (Expr.case
                [ Person.age person >=$ 18, Expr.constant Db_type.text "adult" ]
                ~else_:(Expr.constant Db_type.text "minor")))
          (Projection.expr
             (Expr.coalesce
                (Person.nullable_last_name person)
                ~default:(Person.first_name person))))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely18);;
SELECT
  t0."id",
  (CASE
    WHEN (t0."age" >= $1) THEN $2
    ELSE $3
  END),
  COALESCE(t0."last_name", t0."first_name")
FROM "person" AS t0
```
### KY-19. Проверка NULL через IS NULL

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [where](https://kysely-org.github.io/kysely-apidoc/interfaces/WhereInterface.html#where).
- Проверяет: SQL-проверку отсутствующего значения без обычного сравнения с NULL.

```sql
SELECT "id", "first_name"
FROM "person"
WHERE "last_name" IS NULL
```

```typescript
await db.selectFrom('person')
  .select(['id', 'first_name'])
  .where('last_name', 'is', null)
  .execute()
```

#### OCaml (typed-sql)

```ocaml
let kysely19 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Person.table
      |> where (fun person -> Expr.is_null (Person.nullable_last_name person))
      |> select (fun person -> Projection.pair (Person.id person) (Person.first_name person))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely19);;
SELECT
  t0."id",
  t0."first_name"
FROM "person" AS t0
WHERE
  (t0."last_name" IS NULL)
```
### KY-20. IN со списком и пустым входом

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [HandleEmptyInListsPlugin](https://kysely-org.github.io/kysely-apidoc/classes/HandleEmptyInListsPlugin.html), [where](https://kysely-org.github.io/kysely-apidoc/interfaces/WhereInterface.html#where).
- Проверяет: список bind-значений и явно настроенное поведение для пустого списка. В примере db настроен с plugin-стратегией, заменяющей пустой IN на ложное условие; без такой стратегии Kysely может сгенерировать IN с пустыми скобками.

```sql
-- personIds = [1, 2]
SELECT "id" FROM "person" WHERE "id" IN ($1, $2)

-- personIds = []
SELECT "id" FROM "person" WHERE 1 = 0
```

```typescript
const personIds = [1, 2]

await db.selectFrom('person')
  .select('id')
  .where('id', 'in', personIds)
  .execute()
```

#### OCaml (typed-sql)

`Expr.in_` передаёт каждый элемент как bind-параметр, а пустой список нормализуется в `FALSE`.

```ocaml
let kysely20 =
  Statement.Dynamic.Portable.query_many (fun person_ids ->
    Query.(
      from Person.table
      |> where (fun person -> Expr.in_ (Person.id person) person_ids)
      |> select (fun person -> Projection.expr (Person.id person))))
```

#### SQL typed-sql (PostgreSQL, non-empty list)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:[ 1L; 2L ] kysely20);;
SELECT
  t0."id"
FROM "person" AS t0
WHERE
  (t0."id" IN (
    $1,
    $2
  ))
```

#### SQL typed-sql (PostgreSQL, empty list)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:[] kysely20);;
SELECT
  t0."id"
FROM "person" AS t0
WHERE
  FALSE
```
### KY-21. Keyset-пагинация по двум колонкам

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [where и ExpressionBuilder](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#where).
- Проверяет: лексикографическое продолжение после составного курсора и стабильный порядок страницы.

```sql
SELECT "id", "last_name"
FROM "person"
WHERE
  "last_name" IS NOT NULL
  AND (
    "last_name" > $1
    OR ("last_name" = $2 AND "id" > $3)
  )
ORDER BY "last_name", "id"
LIMIT $4
```

```typescript
await db.selectFrom('person')
  .select(['id', 'last_name'])
  .where('last_name', 'is not', null)
  .where((eb) => eb.or([
    eb('last_name', '>', cursor.lastName),
    eb.and([
      eb('last_name', '=', cursor.lastName),
      eb('id', '>', cursor.id),
    ]),
  ]))
  .orderBy('last_name')
  .orderBy('id')
  .limit(pageSize)
  .execute()
```

#### OCaml (typed-sql)

Фильтр исключает `NULL` до лексикографического сравнения и сохраняет порядок курсора.

```ocaml
let kysely21 =
  Statement.Dynamic.Portable.query_many (fun (last_name, id, page_size) ->
    Query.(
      from Person.table
      |> where (fun person ->
        Expr.is_not_null (Person.nullable_last_name person)
        &&. ((Person.last_name person >$ last_name)
             ||. ((Person.last_name person =$ last_name) &&. (Person.id person >$ id))))
      |> order_by Person.last_name `Asc
      |> order_by Person.id `Asc
      |> limit page_size
      |> select (fun person -> Projection.pair (Person.id person) (Person.last_name person))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:("Smith", 10L, 20) kysely21);;
SELECT
  t0."id",
  t0."last_name"
FROM "person" AS t0
WHERE
  (
    (t0."last_name" IS NOT NULL)
    AND (
      (t0."last_name" > $1)
      OR (
        (t0."last_name" = $2)
        AND (t0."id" > $3)
      )
    )
  )
ORDER BY
  t0."last_name" ASC,
  t0."id" ASC
LIMIT 20
```
### KY-22. Условная проекция через $if

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: `Statement.choose` выбирает один из двух фиксированных SQL-планов; отсутствие поля нормализовано в `age = None`.
- Источник: [$if](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#$if).
- Проверяет: добавление опциональной колонки и соответствующий ей тип результата.

```sql
-- includeAge = true
SELECT "id", "age" FROM "person"

-- includeAge = false
SELECT "id" FROM "person"
```

```typescript
await db.selectFrom('person')
  .select('id')
  .$if(includeAge, (query) => query.select('age'))
  .execute()
```

#### OCaml (typed-sql)

Обе ветви возвращают общий OCaml-тип; ветвь без `age` проецирует типизированный `NULL`.

```ocaml
type kysely_person_with_optional_age =
  { person_id : int64
  ; person_age : int option
  }

let kysely22_with_age =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Person.table
      |> select (fun person ->
        Projection.map2
          ~f:(fun person_id person_age -> { person_id; person_age })
          (Projection.expr (Person.id person))
          (Projection.expr (Expr.to_nullable (Person.age person))))))

let kysely22_without_age =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Person.table
      |> select (fun person ->
        Projection.map2
          ~f:(fun person_id person_age -> { person_id; person_age })
          (Projection.expr (Person.id person))
          (Projection.expr (Expr.constant (Db_type.option Db_type.int) None)))))

let kysely22 =
  Statement.choose
    ~when_:Fn.id
    ~if_true:kysely22_with_age
    ~if_false:kysely22_without_age
```

#### SQL typed-sql (PostgreSQL, age включён)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:true kysely22);;
SELECT
  t0."id",
  t0."age"
FROM "person" AS t0
```

#### SQL typed-sql (PostgreSQL, age отсутствует)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:false kysely22);;
SELECT
  t0."id",
  $1
FROM "person" AS t0
```
### KY-23. Динамическая сортировка по разрешённой колонке

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [DynamicModule](https://kysely-org.github.io/kysely-apidoc/classes/DynamicModule.html).
- Проверяет: динамическую ссылку на идентификатор. Вход сортировки предварительно ограничен разрешённым набором колонок.

```sql
-- sortBy = 'age'
SELECT "id", "age" FROM "person" ORDER BY "age"

-- sortBy = 'id'
SELECT "id", "age" FROM "person" ORDER BY "id"
```

```typescript
const orderColumn =
  sortBy === 'age' ? db.dynamic.ref('age') : db.dynamic.ref('id')

await db.selectFrom('person')
  .select(['id', 'age'])
  .orderBy(orderColumn)
  .execute()
```

#### OCaml (typed-sql)

Разрешённые идентификаторы выбираются по закрытому variant; пользовательская строка не попадает в SQL.

```ocaml
let kysely23 =
  Statement.Dynamic.Portable.query_many (fun sort_by ->
    match sort_by with
    | `Age ->
      Query.(
        from Person.table
        |> order_by Person.age `Asc
        |> select (fun person -> Projection.pair (Person.id person) (Person.age person)))
    | `Id ->
      Query.(
        from Person.table
        |> order_by Person.id `Asc
        |> select (fun person -> Projection.pair (Person.id person) (Person.age person))))
```

#### SQL typed-sql (PostgreSQL, сортировка по age)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:`Age kysely23);;
SELECT
  t0."id",
  t0."age"
FROM "person" AS t0
ORDER BY
  t0."age" ASC
```

#### SQL typed-sql (PostgreSQL, сортировка по id)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:`Id kysely23);;
SELECT
  t0."id",
  t0."age"
FROM "person" AS t0
ORDER BY
  t0."id" ASC
```
### KY-24. CROSS JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: `INNER JOIN ON TRUE` имеет семантику декартова произведения.
- Источник: [crossJoin](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#crossJoin).
- Проверяет: декартово произведение и квалификацию колонок из двух таблиц.

```sql
SELECT "person"."id", "pet"."name"
FROM "person"
CROSS JOIN "pet"
WHERE "person"."id" = $1
```

```typescript
await db.selectFrom('person')
  .crossJoin('pet')
  .select(['person.id', 'pet.name'])
  .where('person.id', '=', personId)
  .execute()
```

#### OCaml (typed-sql)

Декартово произведение строится как `INNER JOIN ON TRUE`; результат эквивалентен `CROSS JOIN`.

```ocaml
let kysely24 =
  Statement.Portable.query_many_exn (fun params ->
    let person_id = params.column Person.id_column ~get:Fn.id in
    Query.(
      from Person.table
      |> inner_join Pet.table ~on:(fun _person _pet -> Condition.true_)
      |> where (fun (person, _) -> Person.id person =. person_id)
      |> select (fun (person, pet) -> Projection.pair (Person.id person) (Pet.name pet))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely24);;
SELECT
  t0."id",
  t1."name"
FROM "person" AS t0
INNER JOIN "pet" AS t1
  ON TRUE
WHERE
  (t0."id" = $1)
```
### KY-25. FULL OUTER JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: Эмуляция через два `LEFT JOIN` и `UNION ALL` сохраняет совпавшие пары и строки без пары с обеих сторон.
- Источник: [fullJoin](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#fullJoin).
- Проверяет: сохранение строк без совпадения с обеих сторон. Поддержка SQLite зависит от версии; в проектной SQLite 3.46.1 этот синтаксис доступен.

```sql
SELECT "person"."id", "pet"."id", "pet"."name"
FROM "person"
FULL OUTER JOIN "pet" ON "pet"."owner_id" = "person"."id"
```

```typescript
await db.selectFrom('person')
  .fullJoin('pet', 'pet.owner_id', 'person.id')
  .select(['person.id as person_id', 'pet.id as pet_id', 'pet.name'])
  .execute()
```

#### OCaml (typed-sql)

`FULL OUTER JOIN` собран из `LEFT JOIN` и второй ветви с несопоставленными питомцами. Предполагаются уникальные ключи `person.id` и `pet.id`.

```ocaml
let kysely25 =
  Statement.Portable.query_many_exn (fun _ ->
    let people_with_pets =
      Query.(
        from Person.table
        |> left_join Pet.table ~on:(fun person pet -> Pet.owner_id pet =. Person.id person)
        |> select (fun (person, pet) ->
          Projection.map2
            ~f:(fun person_id (pet_id, name) -> person_id, pet_id, name)
            (Projection.expr (Expr.to_nullable (Person.id person)))
            (Projection.pair
               (Expr.nullable_column pet Pet.id_column)
               (Pet.nullable_name pet))))
    in
    let pets_without_people =
      Query.(
        from Pet.table
        |> left_join Person.table ~on:(fun pet person -> Pet.owner_id pet =. Person.id person)
        |> where (fun (_, person) ->
          Expr.is_null (Expr.nullable_column person Person.id_column))
        |> select (fun (pet, _) ->
          Projection.map2
            ~f:(fun person_id (pet_id, name) -> person_id, pet_id, name)
            (Projection.expr (Expr.constant (Db_type.option Db_type.int64) None))
            (Projection.pair (Expr.to_nullable (Pet.id pet)) (Expr.to_nullable (Pet.name pet)))))
    in
    Query.union_all people_with_pets pets_without_people)
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely25);;
SELECT *
FROM (
  SELECT
    t0."id",
    t1."id",
    t1."name"
  FROM "person" AS t0
  LEFT JOIN "pet" AS t1
    ON (t1."owner_id" = t0."id")
) AS s0
UNION ALL
SELECT *
FROM (
  SELECT
    $1,
    t0."id",
    t0."name"
  FROM "pet" AS t0
  LEFT JOIN "person" AS t1
    ON (t0."owner_id" = t1."id")
  WHERE
    (t1."id" IS NULL)
) AS s0
```
### KY-26. LEFT JOIN LATERAL с последней связанной строкой

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: Вместо `LATERAL` используется scalar subquery с `LIMIT 1`; если связанной строки нет, результат будет `NULL`.
- Источник: [leftJoinLateral](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#leftJoinLateral).
- Проверяет: коррелированный подзапрос в FROM и сохранение владельца без питомцев. Сценарий специфичен для поддерживающих LATERAL диалектов.

```sql
SELECT "person"."id", "latest_pet"."name"
FROM "person"
LEFT JOIN LATERAL (
  SELECT "pet"."name"
  FROM "pet"
  WHERE "pet"."owner_id" = "person"."id"
  ORDER BY "pet"."id" DESC
  LIMIT 1
) AS "latest_pet" ON TRUE
```

```typescript
await db.selectFrom('person')
  .leftJoinLateral(
    (eb) => eb.selectFrom('pet')
      .select('name')
      .whereRef('pet.owner_id', '=', 'person.id')
      .orderBy('id', 'desc')
      .limit(1)
      .as('latest_pet'),
    (join) => join.onTrue(),
  )
  .select(['person.id', 'latest_pet.name'])
  .execute()
```

#### OCaml (typed-sql)

Коррелированный scalar subquery с `LIMIT 1` возвращает `NULL`, если у человека нет питомцев; он заменяет `LEFT JOIN LATERAL`.

```ocaml
let kysely26 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Person.table
      |> select (fun person ->
        let latest_pet =
          Query.(
            from Pet.table
            |> where (fun pet -> Pet.owner_id pet =. Person.id person)
            |> order_by Pet.id `Desc
            |> limit_one
            |> select_scalar Pet.name)
        in
        Projection.map2
          ~f:(fun id name -> id, name)
          (Projection.expr (Person.id person))
          (Projection.expr (Expr.scalar_subquery latest_pet)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely26);;
SELECT
  t0."id",
  (
    SELECT
      t1."name"
    FROM "pet" AS t1
    WHERE
      (t1."owner_id" = t0."id")
    ORDER BY
      t1."id" DESC
    LIMIT 1
  )
FROM "person" AS t0
```
### KY-27. Коррелированный NOT EXISTS

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [exists и not](https://kysely-org.github.io/kysely-apidoc/interfaces/ExpressionBuilder.html#exists).
- Проверяет: anti-join без размножения строк при нескольких совпадающих питомцах.

```sql
SELECT "person"."id"
FROM "person"
WHERE NOT EXISTS (
  SELECT "pet"."id"
  FROM "pet"
  WHERE "pet"."owner_id" = "person"."id"
)
```

```typescript
await db.selectFrom('person')
  .select('person.id')
  .where((eb) => eb.not(
    eb.exists(
      eb.selectFrom('pet')
        .select('pet.id')
        .whereRef('pet.owner_id', '=', 'person.id'),
    ),
  ))
  .execute()
```

#### OCaml (typed-sql)

```ocaml
let kysely27 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Person.table
      |> where (fun person ->
        not_exists
          (from Pet.table
           |> where (fun pet -> Pet.owner_id pet =. Person.id person)))
      |> select (fun person -> Projection.expr (Person.id person))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely27);;
SELECT
  t0."id"
FROM "person" AS t0
WHERE
  (NOT EXISTS (
    SELECT
      1
    FROM "pet" AS t1
    WHERE
      (t1."owner_id" = t0."id")
  ))
```
### KY-28. Несколько агрегатов с FILTER

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: `FILTER` заменён на `COUNT(CASE ...)`; для категорий из примера количество совпадает.
- Источник: [filterWhere](https://kysely-org.github.io/kysely-apidoc/classes/AggregateFunctionBuilder.html#filterWhere).
- Проверяет: условную агрегацию нескольких категорий в одной строке результата.

```sql
SELECT
  COUNT("id") FILTER (WHERE "species" = $1) AS "cat_count",
  COUNT("id") FILTER (WHERE "species" = $2) AS "dog_count"
FROM "pet"
```

```typescript
await db.selectFrom('pet')
  .select((eb) => [
    eb.fn.count<number>('id')
      .filterWhere('species', '=', 'cat')
      .as('cat_count'),
    eb.fn.count<number>('id')
      .filterWhere('species', '=', 'dog')
      .as('dog_count'),
  ])
  .executeTakeFirstOrThrow()
```

#### OCaml (typed-sql)

`COUNT(*) FILTER` выражен как `COUNT(CASE ...)`: совпавший `id` остаётся non-NULL, остальные строки превращаются в `NULL`.

```ocaml
let kysely28 =
  Statement.Portable.query_one_exn (fun _ ->
    Query.Aggregate.(from Pet.table)
    |> Query.aggregate_one (fun pet ->
      let count_when species =
        Aggregate_projection.count
          (Expr.case
             [ Pet.species pet =$ species, Expr.to_nullable (Pet.id pet) ]
             ~else_:(Expr.constant (Db_type.option Db_type.int64) None))
      in
      Aggregate_projection.both (count_when "cat") (count_when "dog")))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely28);;
SELECT
  COUNT((CASE
    WHEN (t0."species" = $1) THEN t0."id"
    ELSE $2
  END)),
  COUNT((CASE
    WHEN (t0."species" = $3) THEN t0."id"
    ELSE $4
  END))
FROM "pet" AS t0
```
### KY-29. Группировка по нескольким колонкам и COUNT DISTINCT

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [groupBy](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#groupBy), [distinct aggregate](https://kysely-org.github.io/kysely-apidoc/classes/AggregateFunctionBuilder.html#distinct).
- Проверяет: несколько ключей группы и подсчёт уникальных владельцев в каждой группе.

```sql
SELECT "person"."age", "pet"."species",
       COUNT(DISTINCT "pet"."owner_id") AS "owner_count"
FROM "person"
INNER JOIN "pet" ON "pet"."owner_id" = "person"."id"
GROUP BY "person"."age", "pet"."species"
```

```typescript
await db.selectFrom('person')
  .innerJoin('pet', 'pet.owner_id', 'person.id')
  .select((eb) => [
    'person.age',
    'pet.species',
    eb.fn.count<number>('pet.owner_id').distinct().as('owner_count'),
  ])
  .groupBy(['person.age', 'pet.species'])
  .execute()
```

#### OCaml (typed-sql)

```ocaml
let kysely29 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Person.table
      |> inner_join Pet.table ~on:(fun person pet -> Pet.owner_id pet =. Person.id person)
      |> group_by (fun (person, _) -> Person.age person)
      |> group_by (fun (_, pet) -> Pet.species pet)
      |> select (fun (person, pet) ->
        Projection.map3
          ~f:(fun age species owners -> age, species, owners)
          (Projection.expr (Person.age person))
          (Projection.expr (Pet.species pet))
          (Projection.expr (Expr.count_distinct (Pet.owner_id pet))))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely29);;
SELECT
  t0."age",
  t1."species",
  COUNT(DISTINCT t1."owner_id")
FROM "person" AS t0
INNER JOIN "pet" AS t1
  ON (t1."owner_id" = t0."id")
GROUP BY
  t0."age",
  t1."species"
```
### KY-30. Кардинальность глобального COUNT на пустом наборе

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [countAll](https://kysely-org.github.io/kysely-apidoc/interfaces/FunctionModule.html#countAll).
- Проверяет: агрегат без GROUP BY возвращает одну строку со значением 0, даже если фильтр не нашёл строк.

```sql
SELECT COUNT(*) AS "pet_count"
FROM "pet"
WHERE "id" < 0
```

```typescript
await db.selectFrom('pet')
  .select((eb) => eb.fn.countAll<number>().as('pet_count'))
  .where('id', '<', 0)
  .executeTakeFirstOrThrow()
```

#### OCaml (typed-sql)

Ungrouped aggregate имеет exactly-one cardinality даже при пустом входе; `COUNT(*)` вернёт `0`.

```ocaml
let kysely30 =
  Statement.Portable.query_one_exn (fun _ ->
    Query.Aggregate.(
      from Pet.table
      |> where (fun pet -> Pet.id pet <$ 0L))
    |> Query.aggregate_one (fun _ -> Aggregate_projection.count_all))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely30);;
SELECT
  COUNT(*)
FROM "pet" AS t0
WHERE
  (t0."id" < $1)
```
### KY-31. ROW_NUMBER для первой строки каждой группы

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: Anti-exists эквивалентен `ROW_NUMBER() = 1`, поскольку `pet.id` уникален; окно не генерируется.
- Источник: [rowNumber и over](https://kysely-org.github.io/kysely-apidoc/interfaces/FunctionModule.html#rowNumber), [CTE](https://kysely-org.github.io/kysely-apidoc/classes/Kysely.html#with).
- Проверяет: оконную нумерацию строк и последующую фильтрацию ранга без схлопывания данных.

```sql
WITH "ranked_pets" AS (
  SELECT "id", "owner_id", "name",
         ROW_NUMBER() OVER (
           PARTITION BY "owner_id" ORDER BY "id" DESC
         ) AS "row_number"
  FROM "pet"
)
SELECT "owner_id", "id", "name"
FROM "ranked_pets"
WHERE "row_number" = 1
```

```typescript
await db.with('ranked_pets', (db) =>
    db.selectFrom('pet')
      .select(['id', 'owner_id', 'name'])
      .select((eb) => eb.fn.rowNumber()
        .over((ob) => ob.partitionBy('owner_id').orderBy('id', 'desc'))
        .as('row_number')))
  .selectFrom('ranked_pets')
  .select(['owner_id', 'id', 'name'])
  .where('row_number', '=', 1)
  .execute()
```

#### OCaml (typed-sql)

Так как `id` уникален, `ROW_NUMBER() = 1` для каждого владельца эквивалентен выбору строки, для которой не существует более новой.

```ocaml
let kysely31 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Pet.table
      |> where (fun pet ->
        not_exists
          (from Pet.table
           |> where (fun newer ->
             (Pet.owner_id newer =. Pet.owner_id pet) &&. (Pet.id newer >. Pet.id pet))))
      |> select (fun pet ->
        Projection.map2
          ~f:(fun owner_id (id, name) -> owner_id, id, name)
          (Projection.expr (Pet.owner_id pet))
          (Projection.pair (Pet.id pet) (Pet.name pet)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely31);;
SELECT
  t0."owner_id",
  t0."id",
  t0."name"
FROM "pet" AS t0
WHERE
  (NOT EXISTS (
    SELECT
      1
    FROM "pet" AS t1
    WHERE
      (
        (t1."owner_id" = t0."owner_id")
        AND (t1."id" > t0."id")
      )
  ))
```
### KY-32. Накопительная оконная сумма

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✓)
- Семантика: ✗ (добавлено в роадмап ✓)
- Без доработок typed-sql: ✗
- Ограничение: В публичном API нет оконных функций; эмуляция потребовала бы других SQL-возможностей и дополнительных ограничений.
- Источник: [over](https://kysely-org.github.io/kysely-apidoc/classes/AggregateFunctionBuilder.html#over).
- Проверяет: вычисление running total внутри владельца с сохранением каждой строки.

```sql
SELECT "id", "owner_id",
       SUM("id") OVER (
         PARTITION BY "owner_id" ORDER BY "id"
       ) AS "running_id_sum"
FROM "pet"
```

```typescript
await db.selectFrom('pet')
  .select(['id', 'owner_id'])
  .select((eb) => eb.fn.sum<number>('id')
    .over((ob) => ob.partitionBy('owner_id').orderBy('id'))
    .as('running_id_sum'))
  .execute()
```

### KY-33. Рекурсивный CTE для дерева владельцев

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [withRecursive](https://kysely-org.github.io/kysely-apidoc/classes/Kysely.html#withRecursive).
- Проверяет: рекурсивное расширение потомков через nullable manager_id.

```sql
WITH RECURSIVE "descendants" ("id", "manager_id") AS (
  SELECT "id", "manager_id"
  FROM "person"
  WHERE "id" = $1
  UNION ALL
  SELECT "person"."id", "person"."manager_id"
  FROM "person"
  INNER JOIN "descendants" ON "person"."manager_id" = "descendants"."id"
)
SELECT "id", "manager_id"
FROM "descendants"
```

```typescript
await db.withRecursive('descendants', (db) =>
    db.selectFrom('person')
      .select(['id', 'manager_id'])
      .where('id', '=', rootId)
      .unionAll(
        db.selectFrom('person')
          .innerJoin('descendants', 'person.manager_id', 'descendants.id')
          .select(['person.id', 'person.manager_id']),
      ))
  .selectFrom('descendants')
  .select(['id', 'manager_id'])
  .execute()
```

#### OCaml (typed-sql)

```ocaml
let kysely33 =
  Statement.Dynamic.Portable.query_many (fun root_id ->
    let relation query =
      Derived_table.create
        ~table:Descendants.table
        ~columns:Descendants.projection
        query
    in
    let anchor =
      relation
        Query.(
          from Person.table
          |> where (fun person -> Person.id person =$ root_id)
          |> select (fun person ->
            Projection.pair (Person.id person) (Person.manager_id person)))
    in
    let descendants =
      Cte.recursive
        ~union:`Union_all
        ~anchor
        ~step:(fun descendants ->
          relation
            Query.(
              from Person.table
              |> inner_join_cte descendants ~on:(fun person ancestor ->
                Person.manager_id person =. Expr.to_nullable (Descendants.id ancestor))
              |> select (fun (person, _) ->
                Projection.pair (Person.id person) (Person.manager_id person))))
    in
    Cte.with_result descendants ~f:(fun descendants ->
      Query.(
        from_cte descendants
        |> select (fun person -> Descendants.projection person))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:1L kysely33);;
WITH RECURSIVE
  "c0" (
    "id",
    "manager_id"
  ) AS (
    SELECT
      t0."id",
      t0."manager_id"
    FROM "person" AS t0
    WHERE
      (t0."id" = $1)
    UNION ALL
    SELECT
      t0."id",
      t0."manager_id"
    FROM "person" AS t0
    INNER JOIN "c0" AS t1
      ON (t0."manager_id" = t1."id")
  )
SELECT
  t0."id",
  t0."manager_id"
FROM "c0" AS t0
```
### KY-34. MATERIALIZED CTE

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [with и CTEBuilder.materialized](https://kysely-org.github.io/kysely-apidoc/classes/Kysely.html#with).
- Проверяет: передачу планировщику PostgreSQL явного указания материализовать CTE.

```sql
WITH "older_people" AS MATERIALIZED (
  SELECT "id", "age"
  FROM "person"
  WHERE "age" >= $1
)
SELECT "id", "age"
FROM "older_people"
```

```typescript
await db.with(
    (cte) => cte('older_people').materialized(),
    (db) => db.selectFrom('person')
      .select(['id', 'age'])
      .where('age', '>=', minAge),
  )
  .selectFrom('older_people')
  .select(['id', 'age'])
  .execute()
```

#### OCaml (typed-sql)

```ocaml
let kysely34 =
  Statement.Portable.query_many_exn (fun params ->
    let minimum_age = params.expr Db_type.int ~get:Fn.id in
    let older_people =
      Derived_table.create
        ~table:Person.table
        ~columns:(fun person -> Projection.pair (Person.id person) (Person.age person))
        Query.(
          from Person.table
          |> where (fun person -> Person.age person >=. minimum_age)
          |> select (fun person -> Projection.pair (Person.id person) (Person.age person)))
    in
    Cte.with_result (Cte.select ~materialization:`Materialized older_people)
      ~f:(fun older_people ->
        Query.(
          from_cte older_people
          |> select (fun person -> Projection.pair (Person.id person) (Person.age person)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely34);;
WITH
  "c0" (
    "id",
    "age"
  ) AS MATERIALIZED (
    SELECT
      t0."id",
      t0."age"
    FROM "person" AS t0
    WHERE
      (t0."age" >= $1)
  )
SELECT
  t0."id",
  t0."age"
FROM "c0" AS t0
```
### KY-35. DML CTE с DELETE RETURNING

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: Поддерживается как PostgreSQL-only DML CTE через `Postgresql.Cte.returning`.
- Источник: [with](https://kysely-org.github.io/kysely-apidoc/classes/Kysely.html#with), [DELETE RETURNING](https://kysely-org.github.io/kysely-apidoc/classes/DeleteQueryBuilder.html#returning).
- Проверяет: использование набора удалённых строк как источника следующего SELECT; сценарий специфичен для PostgreSQL.

```sql
WITH "deleted_pets" AS (
  DELETE FROM "pet"
  WHERE "id" = $1
  RETURNING "id", "name"
)
SELECT "id", "name"
FROM "deleted_pets"
```

```typescript
await db.with('deleted_pets', (db) =>
    db.deleteFrom('pet')
      .where('id', '=', petId)
      .returning(['id', 'name']))
  .selectFrom('deleted_pets')
  .select(['id', 'name'])
  .execute()
```

#### OCaml (typed-sql)

```ocaml
let kysely35 =
  Statement.For_dialect.query_many_exn ~dialect:Dialect.postgresql (fun params ->
    let pet_id = params.column Pet.id_column ~get:Fn.id in
    let deleted_pets =
      Delete.(
        from Pet.table
        |> where (fun pet -> Pet.id pet =. pet_id)
        |> returning (fun pet -> Projection.pair (Pet.id pet) (Pet.name pet)))
    in
    Cte.with_result
      (Postgresql.Cte.returning
         ~table:Pet.table
         ~columns:(fun pet -> Projection.pair (Pet.id pet) (Pet.name pet))
         deleted_pets)
      ~f:(fun deleted ->
        Query.(
          from_cte deleted
          |> select (fun pet -> Projection.pair (Pet.id pet) (Pet.name pet)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely35);;
WITH
  "c0" (
    "id",
    "name"
  ) AS (
    DELETE FROM "pet"
    WHERE
      ("id" = $1)
    RETURNING
      "id",
      "name"
  )
SELECT
  t0."id",
  t0."name"
FROM "c0" AS t0
```
### KY-36. UNION ALL

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [unionAll](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#unionAll).
- Проверяет: объединение результатов с сохранением дублей.

```sql
SELECT "first_name" AS "name" FROM "person"
UNION ALL
SELECT "name" FROM "pet"
```

```typescript
await db.selectFrom('person')
  .select('first_name as name')
  .unionAll(db.selectFrom('pet').select('name'))
  .execute()
```

#### OCaml (typed-sql)

```ocaml
let kysely36 =
  Statement.Portable.query_many_exn (fun _ ->
    let people = Query.(from Person.table |> select (fun person -> Projection.expr (Person.first_name person))) in
    let pets = Query.(from Pet.table |> select (fun pet -> Projection.expr (Pet.name pet))) in
    Query.union_all people pets)
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely36);;
SELECT *
FROM (
  SELECT
    t0."first_name"
  FROM "person" AS t0
) AS s0
UNION ALL
SELECT *
FROM (
  SELECT
    t0."name"
  FROM "pet" AS t0
) AS s0
```
### KY-37. INTERSECT

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [intersect](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#intersect).
- Проверяет: пересечение двух наборов и удаление повторяющихся строк.

```sql
SELECT "first_name" AS "name" FROM "person"
INTERSECT
SELECT "name" FROM "pet"
```

```typescript
await db.selectFrom('person')
  .select('first_name as name')
  .intersect(db.selectFrom('pet').select('name'))
  .execute()
```

#### OCaml (typed-sql)

```ocaml
let kysely37 =
  Statement.Portable.query_many_exn (fun _ ->
    let people = Query.(from Person.table |> select (fun person -> Projection.expr (Person.first_name person))) in
    let pets = Query.(from Pet.table |> select (fun pet -> Projection.expr (Pet.name pet))) in
    Query.intersect people pets)
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely37);;
SELECT *
FROM (
  SELECT
    t0."first_name"
  FROM "person" AS t0
) AS s0
INTERSECT
SELECT *
FROM (
  SELECT
    t0."name"
  FROM "pet" AS t0
) AS s0
```
### KY-38. EXCEPT

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [except](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#except).
- Проверяет: исключение строк правого запроса из левого набора.

```sql
SELECT "first_name" AS "name" FROM "person"
EXCEPT
SELECT "name" FROM "pet"
```

```typescript
await db.selectFrom('person')
  .select('first_name as name')
  .except(db.selectFrom('pet').select('name'))
  .execute()
```

#### OCaml (typed-sql)

```ocaml
let kysely38 =
  Statement.Portable.query_many_exn (fun _ ->
    let people = Query.(from Person.table |> select (fun person -> Projection.expr (Person.first_name person))) in
    let pets = Query.(from Pet.table |> select (fun pet -> Projection.expr (Pet.name pet))) in
    Query.except people pets)
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely38);;
SELECT *
FROM (
  SELECT
    t0."first_name"
  FROM "person" AS t0
) AS s0
EXCEPT
SELECT *
FROM (
  SELECT
    t0."name"
  FROM "pet" AS t0
) AS s0
```
### KY-39. Коррелированный scalar subquery в ORDER BY

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [orderBy с подзапросом](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#orderBy).
- Проверяет: сортировку внешнего результата по первой связанной строке и порядок NULL при отсутствии питомца.

```sql
SELECT "person"."id", "person"."first_name"
FROM "person"
ORDER BY (
  SELECT "pet"."name"
  FROM "pet"
  WHERE "pet"."owner_id" = "person"."id"
  ORDER BY "pet"."id"
  LIMIT 1
)
```

```typescript
await db.selectFrom('person')
  .select(['person.id', 'person.first_name'])
  .orderBy((eb) => eb.selectFrom('pet')
    .select('pet.name')
    .whereRef('pet.owner_id', '=', 'person.id')
    .orderBy('pet.id')
    .limit(1))
  .execute()
```

#### OCaml (typed-sql)

Scalar подзапрос сохраняет `NULL` для человека без питомцев; его значение используется как ключ сортировки.

```ocaml
let kysely39 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Person.table
      |> order_by
           (fun person ->
             let first_pet =
               Query.(
                 from Pet.table
                 |> where (fun pet -> Pet.owner_id pet =. Person.id person)
                 |> order_by Pet.id `Asc
                 |> limit_one
                 |> select_scalar Pet.name)
             in
             Expr.scalar_subquery first_pet)
           `Asc
      |> select (fun person -> Projection.pair (Person.id person) (Person.first_name person))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely39);;
SELECT
  t0."id",
  t0."first_name"
FROM "person" AS t0
ORDER BY
  (
    SELECT
      t1."name"
    FROM "pet" AS t1
    WHERE
      (t1."owner_id" = t0."id")
    ORDER BY
      t1."id" ASC
    LIMIT 1
  ) ASC
```
### KY-40. SQL template tag с bind-значением

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [sql template tag](https://kysely-org.github.io/kysely-apidoc/interfaces/Sql.html).
- Проверяет: raw SQL-выражение с отдельно переданным bind-значением и явной ссылкой на колонку.

```sql
SELECT "id"
FROM "person"
WHERE upper("first_name") = $1
```

```typescript
import { sql } from 'kysely'

await db.selectFrom('person')
  .select('id')
  .where(sql<boolean>`upper(¤{sql.ref('first_name')}) = ¤{name.toUpperCase()}`)
  .execute()
```

#### OCaml (typed-sql)

Верхний регистр параметра вычисляется до bind; для этого примера предполагаются ASCII-имена.

```ocaml
let kysely40 =
  Statement.Portable.query_many_exn (fun params ->
    let uppercase_name =
      params.expr Db_type.text ~get:Stdlib.String.uppercase_ascii
    in
    Query.(
      from Person.table
      |> where (fun person -> Expr.upper (Person.first_name person) =. uppercase_name)
      |> select (fun person -> Projection.expr (Person.id person))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely40);;
SELECT
  t0."id"
FROM "person" AS t0
WHERE
  (UPPER(t0."first_name") = $1)
```
### KY-41. Извлечение поля из JSONB

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✓)
- Семантика: ✗ (добавлено в роадмап ✓)
- Без доработок typed-sql: ✗
- Ограничение: В typed-sql пока нет типизированных JSONB path/extraction expressions.
- Источник: [JSON reference expressions](https://kysely-org.github.io/kysely-apidoc/interfaces/ExpressionBuilder.html#ref).
- Проверяет: JSON-оператор PostgreSQL и bind-параметр справа от оператора.

```sql
SELECT "id", "profile"->>'nickname' AS "nickname"
FROM "person"
WHERE "profile"->>'nickname' = $1
```

```typescript
await db.selectFrom('person')
  .select(['id', (eb) =>
    eb.ref('profile', '->>').key('nickname').as('nickname'),
  ])
  .where((eb) => eb(
    eb.ref('profile', '->>').key('nickname'),
    '=',
    nickname,
  ))
  .execute()
```

### KY-42. Коррелированный JSON-массив в проекции

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: Вместо PostgreSQL JSON array helper используется упорядоченный `multiset_agg`; он декодирует элементы в типизированный список OCaml.
- Источник: [jsonArrayFrom](https://kysely-org.github.io/kysely-apidoc/functions/helpers_postgres.jsonArrayFrom.html).
- Проверяет: вложенную коллекцию, пустой массив при отсутствии питомцев и декодирование JSON-результата.

```sql
SELECT
  "person"."id",
  (
    SELECT COALESCE(json_agg(agg), '[]')
    FROM (
      SELECT "pet"."id", "pet"."name"
      FROM "pet"
      WHERE "pet"."owner_id" = "person"."id"
      ORDER BY "pet"."id"
    ) AS agg
  ) AS "pets"
FROM "person"
```

```typescript
import { jsonArrayFrom } from 'kysely/helpers/postgres'

await db.selectFrom('person')
  .select([
    'person.id',
    jsonArrayFrom(
      db.selectFrom('pet')
        .select(['pet.id', 'pet.name'])
        .whereRef('pet.owner_id', '=', 'person.id')
        .orderBy('pet.id'),
    ).as('pets'),
  ])
  .execute()
```

#### OCaml (typed-sql)

`multiset_agg` возвращает отсортированный список typed значений; SQL JSON здесь служит транспортом, а результат декодируется в OCaml-список.

```ocaml
type kysely_pet_summary =
  { pet_id : int64
  ; pet_name : string
  }

let kysely42 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Person.table
      |> left_join Pet.table ~on:(fun person pet -> Pet.owner_id pet =. Person.id person)
      |> group_by (fun (person, _) -> Person.id person)
      |> select (fun (person, pet) ->
        let pets =
          Projection.multiset_agg
            ~filter:(Expr.is_not_null (Expr.nullable_column pet Pet.id_column))
            ~order_by:[ Aggregate_order.asc (Expr.nullable_column pet Pet.id_column) ]
            (Projection.pair
               (Expr.nullable_column pet Pet.id_column)
               (Pet.nullable_name pet))
        in
        Projection.map2
          ~f:(fun person_id rows ->
            ( person_id
            , List.map rows ~f:(fun (pet_id, pet_name) ->
                { pet_id = Option.value_exn pet_id
                ; pet_name = Option.value_exn pet_name
                }) ))
          (Projection.expr (Person.id person))
          pets)))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely42);;
SELECT
  t0."id",
  CAST(
    COALESCE(
      JSONB_AGG(
        JSONB_BUILD_ARRAY(
          t1."id",
          t1."name"
        )
        ORDER BY t1."id" ASC
      ) FILTER (
        WHERE (t1."id" IS NOT NULL)
      ),
      JSONB_BUILD_ARRAY()
    )
    AS TEXT
  )
FROM "person" AS t0
LEFT JOIN "pet" AS t1
  ON (t1."owner_id" = t0."id")
GROUP BY
  t0."id"
```
### KY-43. INSERT нескольких строк

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [values](https://kysely-org.github.io/kysely-apidoc/classes/InsertQueryBuilder.html#values).
- Проверяет: несколько наборов bind-значений в одном операторе.

```sql
INSERT INTO "pet" ("name", "species", "owner_id")
VALUES ($1, $2, $3), ($4, $5, $6)
```

```typescript
await db.insertInto('pet')
  .values([
    { name: 'Milo', species: 'cat', owner_id: 1 },
    { name: 'Rex', species: 'dog', owner_id: 2 },
  ])
  .execute()
```

#### OCaml (typed-sql)

Динамический statement строит по одной одинаковой строке INSERT на каждый входной tuple.

```ocaml
let kysely43 =
  Statement.Dynamic.Portable.command (fun rows ->
    let row_builders =
      List.map rows ~f:(fun (owner_id, name, species) row ->
        Insert.(
          row
          |> set Pet.name_column name
          |> set Pet.species_column species
          |> set Pet.owner_id_column owner_id))
    in
    Insert.command (Insert.rows Pet.table row_builders))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:[ 1L, "Milo", "cat"; 2L, "Rex", "dog" ] kysely43);;
INSERT INTO "pet" (
  "name",
  "species",
  "owner_id"
)
VALUES
  ($1, $2, $3),
  ($4, $5, $6)
```
### KY-44. INSERT из SELECT

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [expression](https://kysely-org.github.io/kysely-apidoc/classes/InsertQueryBuilder.html#expression).
- Проверяет: перенос набора строк между отношениями с совпадающей формой проекции.

```sql
INSERT INTO "person" ("id", "first_name", "last_name", "age")
SELECT "id", "first_name", "last_name", "age"
FROM "person_import"
WHERE "age" >= $1
```

```typescript
await db.insertInto('person')
  .columns(['id', 'first_name', 'last_name', 'age'])
  .expression(
    db.selectFrom('person_import')
      .select(['id', 'first_name', 'last_name', 'age'])
      .where('age', '>=', minAge),
  )
  .execute()
```

#### OCaml (typed-sql)

```ocaml
let kysely44_columns =
  Insert.Columns.(
    column Person.id_column
    |> add Person.first_name_column
    |> add Person.last_name_column
    |> add Person.age_column)

let kysely44 =
  Statement.Portable.command_exn (fun params ->
    let min_age = params.expr Db_type.int ~get:Fn.id in
    let source =
      Query.(
        from Person_import.table
        |> where (fun person -> Person_import.age person >=. min_age)
        |> select (fun person ->
          Projection.both
            (Projection.pair
               (Person_import.id person)
               (Person_import.first_name person))
            (Projection.pair
               (Person_import.last_name person)
               (Person_import.age person))))
    in
    Insert.(into Person.table |> from_select kysely44_columns source |> command))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:18 kysely44);;
INSERT INTO "person" (
  "id",
  "first_name",
  "last_name",
  "age"
)
SELECT
  t0."id",
  t0."first_name",
  t0."last_name",
  t0."age"
FROM "person_import" AS t0
WHERE
  (t0."age" >= $1)
```

### KY-45. ON CONFLICT DO NOTHING

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [onConflict и doNothing](https://kysely-org.github.io/kysely-apidoc/classes/InsertQueryBuilder.html#onConflict).
- Проверяет: conflict target по уникальному pet.name и пропуск конфликтующей вставки.

```sql
INSERT INTO "pet" ("name", "species", "owner_id")
VALUES ($1, $2, $3)
ON CONFLICT ("name") DO NOTHING
```

```typescript
await db.insertInto('pet')
  .values({ name: 'Milo', species: 'cat', owner_id: 1 })
  .onConflict((oc) => oc.column('name').doNothing())
  .execute()
```

#### OCaml (typed-sql)

```ocaml
let kysely45 =
  Statement.Portable.command_exn (fun params ->
    let name = params.expr Db_type.text ~get:(fun (name, _, _) -> name) in
    let species = params.expr Db_type.text ~get:(fun (_, species, _) -> species) in
    let owner_id = params.expr Db_type.int64 ~get:(fun (_, _, owner_id) -> owner_id) in
    Insert.(
      into Pet.table
      |> set_expr Pet.name_column name
      |> set_expr Pet.species_column species
      |> set_expr Pet.owner_id_column owner_id
      |> on_conflict (Conflict_target.column Pet.name_column)
      |> do_nothing
      |> command))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely45);;
INSERT INTO "pet" (
  "name",
  "species",
  "owner_id"
)
VALUES
  ($1, $2, $3)
ON CONFLICT (
  "name"
)
DO NOTHING
```
### KY-46. Условный upsert с excluded и RETURNING

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [onConflict](https://kysely-org.github.io/kysely-apidoc/classes/InsertQueryBuilder.html#onConflict), [whereRef](https://kysely-org.github.io/kysely-apidoc/classes/OnConflictBuilder.html).
- Проверяет: ссылку на виртуальную строку excluded, условие обновления и возвращаемую строку.

```sql
INSERT INTO "pet" ("name", "species", "owner_id")
VALUES ($1, $2, $3)
ON CONFLICT ("name") DO UPDATE
SET "species" = "excluded"."species"
WHERE "excluded"."species" <> "pet"."species"
RETURNING "id", "name", "species"
```

```typescript
await db.insertInto('pet')
  .values({ name: petName, species, owner_id: ownerId })
  .onConflict((oc) => oc.column('name')
    .doUpdateSet({
      species: (eb) => eb.ref('excluded.species'),
    })
    .whereRef('excluded.species', '!=', 'pet.species'))
  .returning(['id', 'name', 'species'])
  .executeTakeFirst()
```

#### OCaml (typed-sql)

```ocaml
let kysely46 =
  Statement.Portable.expect_optional_exn (fun params ->
    let name = params.expr Db_type.text ~get:(fun (name, _, _) -> name) in
    let species = params.expr Db_type.text ~get:(fun (_, species, _) -> species) in
    let owner_id = params.expr Db_type.int64 ~get:(fun (_, _, owner_id) -> owner_id) in
    Insert.(
      into Pet.table
      |> set_expr Pet.name_column name
      |> set_expr Pet.species_column species
      |> set_expr Pet.owner_id_column owner_id
      |> on_conflict (Conflict_target.column Pet.name_column)
      |> do_update (fun ~existing ~excluded ->
        Conflict_update.empty
        |> Conflict_update.set_expr Pet.species_column (Pet.species excluded)
        |> Conflict_update.where (Pet.species excluded <>. Pet.species existing))
      |> returning (fun pet ->
        Projection.map2
          ~f:(fun id (name, species) -> id, name, species)
          (Projection.expr (Pet.id pet))
          (Projection.pair (Pet.name pet) (Pet.species pet)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely46);;
INSERT INTO "pet" AS t0 (
  "name",
  "species",
  "owner_id"
)
VALUES
  ($1, $2, $3)
ON CONFLICT (
  "name"
)
DO UPDATE
SET
  "species" = excluded."species"
WHERE
  (excluded."species" <> t0."species")
RETURNING
  "id",
  "name",
  "species"
```
### KY-47. FOR UPDATE SKIP LOCKED

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✓)
- Семантика: ✗ (добавлено в роадмап ✓)
- Без доработок typed-sql: ✗
- Ограничение: В публичном API пока нет `FOR UPDATE` и `SKIP LOCKED`.
- Источник: [forUpdate и skipLocked](https://kysely-org.github.io/kysely-apidoc/interfaces/SelectQueryBuilder.html#forUpdate).
- Проверяет: выбор незаблокированной строки очереди. Сценарий специфичен для СУБД, поддерживающих блокировки строк.

```sql
SELECT "id", "name"
FROM "pet"
WHERE "owner_id" = $1
ORDER BY "id"
LIMIT 1
FOR UPDATE SKIP LOCKED
```

```typescript
await db.selectFrom('pet')
  .select(['id', 'name'])
  .where('owner_id', '=', ownerId)
  .orderBy('id')
  .limit(1)
  .forUpdate()
  .skipLocked()
  .executeTakeFirst()
```

### KY-48. UPDATE FROM

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [UpdateQueryBuilder.from](https://kysely-org.github.io/kysely-apidoc/classes/UpdateQueryBuilder.html#from).
- Проверяет: обновление значения по совпавшей строке другой таблицы. API поддерживается отдельными диалектами, включая PostgreSQL.

```sql
UPDATE "person"
SET "first_name" = "pet"."name"
FROM "pet"
WHERE "person"."id" = $1
  AND "pet"."owner_id" = "person"."id"
```

```typescript
await db.updateTable('person')
  .from('pet')
  .set({ first_name: (eb) => eb.ref('pet.name') })
  .where('person.id', '=', personId)
  .whereRef('pet.owner_id', '=', 'person.id')
  .execute()
```

#### OCaml (typed-sql)

`Update.from` задаёт источник значения; связь и фильтр обновляемой строки проверяются через unique `person.id`.

```ocaml
let kysely48 =
  Statement.Portable.command_exn (fun params ->
    let person_id = params.expr Db_type.int64 ~get:Fn.id in
    Update.(
      table Person.table
      |> from Pet.table ~f:(fun _target pet update ->
        update
        |> set_expr Person.first_name_column (Pet.name pet)
        |> where (fun person ->
          (Person.id person =. person_id) &&. (Pet.owner_id pet =. Person.id person)))
      |> command))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely48);;
UPDATE "person" AS t0
SET
  "first_name" = t1."name"
FROM "pet" AS t1
WHERE
  (
    (t0."id" = $1)
    AND (t1."owner_id" = t0."id")
  )
```
### KY-49. DELETE USING

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: `DELETE USING` переписан в коррелированный `EXISTS`; уникальный ключ владельца сохраняет семантику.
- Источник: [using](https://kysely-org.github.io/kysely-apidoc/classes/DeleteQueryBuilder.html#using).
- Проверяет: удаление по условию на связанной таблице и RETURNING удалённых строк; диалектный SQL.

```sql
DELETE FROM "pet"
USING "person"
WHERE "pet"."owner_id" = "person"."id"
  AND "person"."age" < $1
RETURNING "pet"."id", "pet"."name"
```

```typescript
await db.deleteFrom('pet')
  .using('person')
  .whereRef('pet.owner_id', '=', 'person.id')
  .where('person.age', '<', maxOwnerAge)
  .returning(['pet.id', 'pet.name'])
  .execute()
```

#### OCaml (typed-sql)

`DELETE USING` переписан как `DELETE ... WHERE EXISTS`; уникальный `person.id` сохраняет набор удаляемых питомцев.

```ocaml
let kysely49 =
  Statement.Portable.query_many_exn (fun params ->
    let maximum_age = params.expr Db_type.int ~get:Fn.id in
    Delete.(
      from Pet.table
      |> where (fun pet ->
        Query.exists
          Query.(
            from Person.table
            |> where (fun person ->
              (Person.id person =. Pet.owner_id pet) &&. (Person.age person <. maximum_age))))
      |> returning (fun pet -> Projection.pair (Pet.id pet) (Pet.name pet))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql kysely49);;
DELETE FROM "pet"
WHERE
  (EXISTS (
    SELECT
      1
    FROM "person" AS t1
    WHERE
      (
        (t1."id" = "owner_id")
        AND (t1."age" < $1)
      )
  ))
RETURNING
  "id",
  "name"
```
### KY-50. MERGE из таблицы импорта

- OCaml-пример: ✗
- Реализуемость: ✗ (добавлено в роадмап ✓)
- Семантика: ✗ (добавлено в роадмап ✓)
- Без доработок typed-sql: ✗
- Ограничение: В публичном API пока нет `MERGE`; разбиение на команды не сохраняло бы атомарность исходного оператора.
- Источник: [mergeInto](https://kysely-org.github.io/kysely-apidoc/classes/QueryCreator.html#mergeInto), [MergeQueryBuilder](https://kysely-org.github.io/kysely-apidoc/classes/MergeQueryBuilder.html).
- Проверяет: ветви WHEN MATCHED UPDATE и WHEN NOT MATCHED INSERT. Для PostgreSQL требуется версия 15 или новее.

```sql
MERGE INTO "person"
USING "person_import" ON "person_import"."id" = "person"."id"
WHEN MATCHED THEN
  UPDATE SET
    "first_name" = "person_import"."first_name",
    "last_name" = "person_import"."last_name",
    "age" = "person_import"."age"
WHEN NOT MATCHED THEN
  INSERT ("id", "first_name", "last_name", "age")
  VALUES (
    "person_import"."id",
    "person_import"."first_name",
    "person_import"."last_name",
    "person_import"."age"
  )
```

```typescript
await db.mergeInto('person')
  .using('person_import', 'person_import.id', 'person.id')
  .whenMatched()
  .thenUpdateSet({
    first_name: (eb) => eb.ref('person_import.first_name'),
    last_name: (eb) => eb.ref('person_import.last_name'),
    age: (eb) => eb.ref('person_import.age'),
  })
  .whenNotMatched()
  .thenInsertValues(({ ref }) => ({
    id: ref('person_import.id'),
    first_name: ref('person_import.first_name'),
    last_name: ref('person_import.last_name'),
    age: ref('person_import.age'),
  }))
  .execute()
```

## Уведомление о лицензии источника

The MIT License (MIT)

Copyright (c) 2022 Sami Koskimäki

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
