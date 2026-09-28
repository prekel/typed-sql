<!-- SPDX-License-Identifier: MIT -->

# Сценарии запросов из Kysely

Первые 15 сценариев по [API Kysely](https://kysely-org.github.io/kysely-apidoc/) (доступ 28.09.2026). Примеры сокращены и адаптированы. Это каталог кандидатов для regression-набора; приведённый SQL показывает ожидаемую форму для PostgreSQL, а не побайтовый снимок вывода Kysely. Плейсхолдеры `$1`, `$2` и далее обозначают bind-параметры.

Источник примеров: Kysely, © 2022 Sami Koskimäki, [лицензия MIT](https://github.com/kysely-org/kysely/blob/master/LICENSE). Копирайт и текст разрешения приведены в конце файла. Схема: `person(id, first_name, last_name, age)` и `pet(id, owner_id, name, species)`. Для проверки nullable-результатов нужна персона без питомцев.

Отмечать `[x]` следует после переноса сценария в regression-набор и выполнения на заявленных диалектах.

### KY-01. Фильтр и проекция

- [ ] Перенесено в regression-набор.
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

### KY-02. Условный фильтр

- [ ] Перенесено в regression-набор.
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

### KY-03. Вложенные AND и OR

- [ ] Перенесено в regression-набор.
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

### KY-04. INNER JOIN

- [ ] Перенесено в regression-набор.
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

### KY-05. LEFT JOIN

- [ ] Перенесено в regression-набор.
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

### KY-06. Группировка и HAVING

- [ ] Перенесено в regression-набор.
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

### KY-07. Коррелированный scalar subquery

- [ ] Перенесено в regression-набор.
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

### KY-08. Коррелированный EXISTS

- [ ] Перенесено в regression-набор.
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

### KY-09. Derived table

- [ ] Перенесено в regression-набор.
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

### KY-10. CTE

- [ ] Перенесено в regression-набор.
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

### KY-11. UNION

- [ ] Перенесено в regression-набор.
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

### KY-12. Оконный агрегат

- [ ] Перенесено в regression-набор.
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

### KY-13. INSERT RETURNING

- [ ] Перенесено в regression-набор.
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

### KY-14. UPDATE RETURNING

- [ ] Перенесено в regression-набор.
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

### KY-15. DELETE RETURNING

- [ ] Перенесено в regression-набор.
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
