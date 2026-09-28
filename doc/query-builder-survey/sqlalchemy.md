<!-- SPDX-License-Identifier: MIT -->

# Сценарии запросов из SQLAlchemy

Первые 15 сценариев по [SQLAlchemy 2.0 Unified Tutorial](https://docs.sqlalchemy.org/en/20/tutorial/) (доступ 28.09.2026). Использован SQLAlchemy Core. Примеры сокращены и адаптированы; SQL показывает ожидаемую структуру запроса, а не точный вывод компилятора. Имена bind-параметров могут отличаться у разных диалектов.

Источник примеров: SQLAlchemy authors and contributors, © 2005–2026, [лицензия MIT](https://github.com/sqlalchemy/sqlalchemy/blob/main/LICENSE). Уведомление о лицензии приведено в конце файла. Схема tutorial: `user_account(id, name, fullname)` и `address(id, user_id, email_address)`. Для проверки пустых результатов нужна учётная запись без адресов.

Отмечать `[x]` следует после переноса сценария в regression-набор и выполнения на заявленных диалектах.

### SA-01. Фильтр и проекция

- [ ] Перенесено в regression-набор.
- Источник: [SELECT и WHERE](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#the-where-clause).
- Проверяет: выбор двух колонок с bind-параметром.

```sql
SELECT user_account.id, user_account.name
FROM user_account
WHERE user_account.name = :name
```

```python
stmt = select(user_table.c.id, user_table.c.name).where(
    user_table.c.name == name
)
```

### SA-02. Составной предикат

- [ ] Перенесено в regression-набор.
- Источник: [WHERE clause](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#the-where-clause).
- Проверяет: группировку `OR` внутри `AND`.

```sql
SELECT user_account.id
FROM user_account
WHERE (user_account.name = :name1 OR user_account.name = :name2)
  AND user_account.id > :min_id
```

```python
stmt = select(user_table.c.id).where(
    or_(user_table.c.name == name1, user_table.c.name == name2),
    user_table.c.id > min_id,
)
```

### SA-03. Сортировка и страница

- [ ] Перенесено в regression-набор.
- Источник: [ORDER BY](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#order-by), [limit/offset](https://docs.sqlalchemy.org/en/20/core/selectable.html#sqlalchemy.sql.expression.GenerativeSelect.limit).
- Проверяет: устойчивый порядок, `LIMIT` и `OFFSET`.

```sql
SELECT user_account.id, user_account.name
FROM user_account
ORDER BY user_account.id
LIMIT :limit OFFSET :offset
```

```python
stmt = (
    select(user_table.c.id, user_table.c.name)
    .order_by(user_table.c.id)
    .limit(page_size)
    .offset(page_offset)
)
```

### SA-04. INNER JOIN

- [ ] Перенесено в regression-набор.
- Источник: [explicit JOIN](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#explicit-from-clauses-and-joins).
- Проверяет: связь таблиц по внешнему ключу.

```sql
SELECT user_account.name, address.email_address
FROM user_account
JOIN address ON user_account.id = address.user_id
```

```python
stmt = (
    select(user_table.c.name, address_table.c.email_address)
    .join_from(user_table, address_table)
)
```

### SA-05. LEFT OUTER JOIN

- [ ] Перенесено в regression-набор.
- Источник: [OUTER JOIN](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#outer-and-full-join).
- Проверяет: сохранение учётной записи без адреса и nullable-поле.

```sql
SELECT user_account.name, address.email_address
FROM user_account
LEFT OUTER JOIN address ON user_account.id = address.user_id
```

```python
stmt = (
    select(user_table.c.name, address_table.c.email_address)
    .join_from(user_table, address_table, isouter=True)
)
```

### SA-06. GROUP BY и HAVING

- [ ] Перенесено в regression-набор.
- Источник: [aggregate functions with GROUP BY/HAVING](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#aggregate-functions-with-group-by-having).
- Проверяет: фильтрацию агрегированных групп.

```sql
SELECT address.user_id, COUNT(address.id) AS address_count
FROM address
GROUP BY address.user_id
HAVING COUNT(address.id) > :min_count
```

```python
stmt = (
    select(
        address_table.c.user_id,
        func.count(address_table.c.id).label("address_count"),
    )
    .group_by(address_table.c.user_id)
    .having(func.count(address_table.c.id) > min_count)
)
```

### SA-07. Коррелированный scalar subquery

- [ ] Перенесено в regression-набор.
- Источник: [scalar and correlated subqueries](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#scalar-and-correlated-subqueries).
- Проверяет: число связанных строк, включая ноль.

```sql
SELECT user_account.id,
       (SELECT COUNT(address.id)
        FROM address
        WHERE address.user_id = user_account.id) AS address_count
FROM user_account
```

```python
address_count = (
    select(func.count(address_table.c.id))
    .where(address_table.c.user_id == user_table.c.id)
    .scalar_subquery()
)
stmt = select(user_table.c.id, address_count.label("address_count"))
```

### SA-08. Коррелированный EXISTS

- [ ] Перенесено в regression-набор.
- Источник: [EXISTS subqueries](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#exists-subqueries).
- Проверяет: фильтрацию без дублирования внешних строк.

```sql
SELECT user_account.id
FROM user_account
WHERE EXISTS (
  SELECT address.id FROM address
  WHERE address.user_id = user_account.id
)
```

```python
has_address = (
    select(address_table.c.id)
    .where(address_table.c.user_id == user_table.c.id)
    .exists()
)
stmt = select(user_table.c.id).where(has_address)
```

### SA-09. Derived table

- [ ] Перенесено в regression-набор.
- Источник: [subqueries and CTEs](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#subqueries-and-ctes).
- Проверяет: агрегированный подзапрос в `FROM`.

```sql
SELECT counts.user_id, counts.address_count
FROM (
  SELECT address.user_id, COUNT(address.id) AS address_count
  FROM address GROUP BY address.user_id
) AS counts
WHERE counts.address_count > :min_count
```

```python
counts = (
    select(
        address_table.c.user_id,
        func.count(address_table.c.id).label("address_count"),
    )
    .group_by(address_table.c.user_id)
    .subquery("counts")
)
stmt = select(counts.c.user_id, counts.c.address_count).where(
    counts.c.address_count > min_count
)
```

### SA-10. CTE

- [ ] Перенесено в regression-набор.
- Источник: [common table expressions](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#common-table-expressions-ctes).
- Проверяет: именованный источник строк и обращение к его колонкам.

```sql
WITH counts AS (
  SELECT address.user_id, COUNT(address.id) AS address_count
  FROM address GROUP BY address.user_id
)
SELECT counts.user_id, counts.address_count
FROM counts
```

```python
counts = (
    select(
        address_table.c.user_id,
        func.count(address_table.c.id).label("address_count"),
    )
    .group_by(address_table.c.user_id)
    .cte("counts")
)
stmt = select(counts.c.user_id, counts.c.address_count)
```

### SA-11. UNION

- [ ] Перенесено в regression-набор.
- Источник: [UNION and other set operations](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#union-union-all-and-other-set-operations).
- Проверяет: одинаковую проекцию двух запросов и удаление дублей.

```sql
SELECT user_account.id FROM user_account WHERE user_account.name = :name1
UNION
SELECT user_account.id FROM user_account WHERE user_account.name = :name2
```

```python
stmt = union(
    select(user_table.c.id).where(user_table.c.name == name1),
    select(user_table.c.id).where(user_table.c.name == name2),
)
```

### SA-12. Оконная функция

- [ ] Перенесено в regression-набор.
- Источник: [using window functions](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#using-window-functions).
- Проверяет: нумерацию строк внутри группы без схлопывания результата.

```sql
SELECT address.user_id, address.email_address,
       ROW_NUMBER() OVER (
         PARTITION BY address.user_id ORDER BY address.id
       ) AS address_number
FROM address
```

```python
stmt = select(
    address_table.c.user_id,
    address_table.c.email_address,
    func.row_number()
        .over(
            partition_by=address_table.c.user_id,
            order_by=address_table.c.id,
        )
        .label("address_number"),
)
```

### SA-13. INSERT RETURNING

- [ ] Перенесено в regression-набор.
- Источник: [INSERT and RETURNING](https://docs.sqlalchemy.org/en/20/tutorial/data_insert.html#insert-returning).
- Проверяет: возврат данных вставленной строки; синтаксис `RETURNING` зависит от диалекта.

```sql
INSERT INTO user_account (name, fullname)
VALUES (:name, :fullname)
RETURNING user_account.id
```

```python
stmt = (
    insert(user_table)
    .values(name=name, fullname=fullname)
    .returning(user_table.c.id)
)
```

### SA-14. Коррелированный UPDATE

- [ ] Перенесено в regression-набор.
- Источник: [correlated updates](https://docs.sqlalchemy.org/en/20/tutorial/data_update.html#correlated-updates).
- Проверяет: scalar subquery в `SET` и `NULL` при отсутствии адреса.

```sql
UPDATE user_account
SET fullname = (
  SELECT address.email_address FROM address
  WHERE address.user_id = user_account.id
  ORDER BY address.id LIMIT :limit
)
```

```python
first_email = (
    select(address_table.c.email_address)
    .where(address_table.c.user_id == user_table.c.id)
    .order_by(address_table.c.id)
    .limit(1)
    .scalar_subquery()
)
stmt = update(user_table).values(fullname=first_email)
```

### SA-15. DELETE RETURNING

- [ ] Перенесено в regression-набор.
- Источник: [DELETE](https://docs.sqlalchemy.org/en/20/tutorial/data_update.html#the-delete-sql-expression-construct), [RETURNING](https://docs.sqlalchemy.org/en/20/tutorial/data_update.html#using-returning-with-update-delete).
- Проверяет: условное удаление и возвращаемые значения; `RETURNING` зависит от диалекта.

```sql
DELETE FROM address
WHERE address.user_id = :user_id
RETURNING address.id
```

```python
stmt = (
    delete(address_table)
    .where(address_table.c.user_id == user_id)
    .returning(address_table.c.id)
)
```

## Уведомление о лицензии источника

Copyright 2005-2026 SQLAlchemy authors and contributors <see AUTHORS file>.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
