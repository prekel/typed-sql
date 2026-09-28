<!-- SPDX-License-Identifier: MIT -->

# Сценарии запросов из SQLAlchemy

40 сценариев по [SQLAlchemy 2.0 Unified Tutorial](https://docs.sqlalchemy.org/en/20/tutorial/) и документации SQLAlchemy Core (доступ 28.09.2026). Использован SQLAlchemy Core. Примеры сокращены и адаптированы; SQL показывает ожидаемую структуру запроса, а не точный вывод компилятора. Имена bind-параметров могут отличаться у разных диалектов.

**Желаемый таргет: 50–70 сценариев.**

Источник примеров: SQLAlchemy authors and contributors, © 2005–2026, [лицензия MIT](https://github.com/sqlalchemy/sqlalchemy/blob/main/LICENSE). Уведомление о лицензии приведено в конце файла. Схема tutorial: `user_account(id, name, fullname)` и `address(id, user_id, email_address)`. Для проверки пустых результатов нужна учётная запись без адресов.

Для SA-01–SA-05 ниже добавлены реализация на typed-sql и SQL, полученный её компилятором. В блоках «SQL typed-sql» первая строка запускает компилятор, остальные строки — его вывод. Запустить проверку можно командой `opam exec -- dune runtest test/query-builder-survey`.

Статусы в карточках: `✓` — подтверждено; `✗` — условие не выполнено; `—` — не оценивалось. «Семантика» учитывает входные параметры, результат, `NULL` и заданный порядок относительно сценария в карточке. «Без доработок» относится к публичному API typed-sql, а не к необходимости улучшить пример. Реализуемость оценивается после попытки написать OCaml-код.

## Общие дескрипторы для SA-01–SA-05

Эти descriptors используются во всех пяти примерах этого файла.

```ocaml
open! Base
open Typed_sql
open Infix

module User_account = struct
  type row

  let table : row Table.t = Table.v_exn "user_account"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let id row = Expr.column row id_column
  let name row = Expr.column row name_column
end

module Address = struct
  type row

  let table : row Table.t = Table.v_exn "address"
  let id_column = Column.v_exn table "id" Db_type.int64
  let user_id_column = Column.v_exn table "user_id" Db_type.int64
  let email_column = Column.v_exn table "email_address" Db_type.text
  let user_id row = Expr.column row user_id_column
  let email row = Expr.column row email_column
  let nullable_email row = Expr.nullable_column row email_column
end
```

### SA-01. Фильтр и проекция

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✗
- Без доработок typed-sql: ✓
- Замечание: `name` заменён фиксированным значением `sandy`.
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

#### OCaml (typed-sql)

Bind-значение сравнивается с выражением колонки; проекция декодируется в пару.

```ocaml
let sqlalchemy01 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from User_account.table
      |> where (fun user -> User_account.name user =$ "sandy")
      |> select (fun user ->
        Projection.pair (User_account.id user) (User_account.name user))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql sqlalchemy01);;
SELECT
  t0."id",
  t0."name"
FROM "user_account" AS t0
WHERE
  (t0."name" = $1)
```

### SA-02. Составной предикат

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✗
- Без доработок typed-sql: ✓
- Замечание: `name1`, `name2` и `min_id` заменены фиксированными значениями.
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

#### OCaml (typed-sql)

OR-группа явно вложена в AND-группу.

```ocaml
let sqlalchemy02 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from User_account.table
      |> where (fun user ->
        ((User_account.name user =$ "sandy")
         ||. (User_account.name user =$ "spongebob"))
        &&. (User_account.id user >$ 1L))
      |> select (fun user -> Projection.expr (User_account.id user))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql sqlalchemy02);;
SELECT
  t0."id"
FROM "user_account" AS t0
WHERE
  (
    (
      (t0."name" = $1)
      OR (t0."name" = $2)
    )
    AND (t0."id" > $3)
  )
```

### SA-03. Сортировка и страница

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✗
- Без доработок typed-sql: ✓
- Замечание: `page_size` и `page_offset` заменены фиксированными значениями.
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

#### OCaml (typed-sql)

Порядок по уникальному id задаёт стабильную страницу.

```ocaml
let sqlalchemy03 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from User_account.table
      |> order_by User_account.id `Asc
      |> limit 10
      |> offset 20
      |> select (fun user ->
        Projection.pair (User_account.id user) (User_account.name user))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql sqlalchemy03);;
SELECT
  t0."id",
  t0."name"
FROM "user_account" AS t0
ORDER BY
  t0."id" ASC
LIMIT 10
OFFSET 20
```

### SA-04. INNER JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Замечание: Предикат JOIN задан явно вместо вывода по foreign key.
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

#### OCaml (typed-sql)

Foreign key связь задаётся явно через callback JOIN.

```ocaml
let sqlalchemy04 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from User_account.table
      |> inner_join Address.table ~on:(fun user address ->
        User_account.id user =. Address.user_id address)
      |> select (fun (user, address) ->
        Projection.pair (User_account.name user) (Address.email address))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql sqlalchemy04);;
SELECT
  t0."name",
  t1."email_address"
FROM "user_account" AS t0
INNER JOIN "address" AS t1
  ON (t0."id" = t1."user_id")
```

### SA-05. LEFT OUTER JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
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

#### OCaml (typed-sql)

Nullable-колонка адреса в результате имеет тип string option.

```ocaml
let sqlalchemy05 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from User_account.table
      |> left_join Address.table ~on:(fun user address ->
        User_account.id user =. Address.user_id address)
      |> select (fun (user, address) ->
        Projection.pair (User_account.name user) (Address.nullable_email address))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql sqlalchemy05);;
SELECT
  t0."name",
  t1."email_address"
FROM "user_account" AS t0
LEFT JOIN "address" AS t1
  ON (t0."id" = t1."user_id")
```

### SA-06. GROUP BY и HAVING

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
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

### SA-16. DISTINCT

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [DISTINCT](https://docs.sqlalchemy.org/en/20/core/selectable.html#sqlalchemy.sql.expression.Select.distinct).
- Проверяет: удаление повторов в проекции.

```sql
SELECT DISTINCT address.user_id
FROM address
```

```python
stmt = select(address_table.c.user_id).distinct()
```

### SA-17. Фильтр IN

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [оператор IN](https://docs.sqlalchemy.org/en/20/core/operators.html#in-comparisons).
- Проверяет: сравнение колонки с набором значений.

```sql
SELECT user_account.id
FROM user_account
WHERE user_account.name IN (:name_1, :name_2)
```

```python
stmt = select(user_table.c.id).where(
    user_table.c.name.in_(["sandy", "spongebob"])
)
```

### SA-18. Сопоставление шаблону LIKE

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [строковые операторы](https://docs.sqlalchemy.org/en/20/core/operators.html#string-comparisons).
- Проверяет: шаблонное сравнение строкового значения с bind-параметром.

```sql
SELECT user_account.id
FROM user_account
WHERE user_account.name LIKE :name_pattern
```

```python
stmt = select(user_table.c.id).where(user_table.c.name.like(name_pattern))
```

### SA-19. Проверка IS NULL

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [операторы сравнения с NULL](https://docs.sqlalchemy.org/en/20/core/operators.html#identity-comparisons).
- Проверяет: предикат `IS NULL`, а не сравнение через `= NULL`.

```sql
SELECT address.id
FROM address
WHERE address.email_address IS NULL
```

```python
stmt = select(address_table.c.id).where(address_table.c.email_address.is_(None))
```

### SA-20. Условное выражение CASE

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [условные выражения](https://docs.sqlalchemy.org/en/20/core/sqlelement.html#sqlalchemy.sql.expression.case).
- Проверяет: выражение CASE в списке проекции.

```sql
SELECT user_account.id,
       CASE WHEN user_account.name = :name_1 THEN :label_1 ELSE :label_2 END AS category
FROM user_account
```

```python
category = case(
    (user_table.c.name == "sandy", "matched"),
    else_="other",
).label("category")
stmt = select(user_table.c.id, category)
```

### SA-21. Сортировка NULLS LAST

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [модификаторы ORDER BY](https://docs.sqlalchemy.org/en/20/core/sqlelement.html#sqlalchemy.sql.expression.nulls_last).
- Проверяет: явное положение `NULL` при сортировке.

```sql
SELECT address.id, address.email_address
FROM address
ORDER BY address.email_address ASC NULLS LAST
```

```python
stmt = select(address_table.c.id, address_table.c.email_address).order_by(
    address_table.c.email_address.asc().nulls_last()
)
```

### SA-22. Self join через alias

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [псевдонимы таблиц](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#using-aliases).
- Проверяет: два независимых псевдонима одной таблицы в JOIN.

```sql
SELECT user_account.name, related_user.name
FROM user_account
JOIN user_account AS related_user
  ON user_account.id < related_user.id
```

```python
related_user = user_table.alias("related_user")
stmt = select(user_table.c.name, related_user.c.name).join_from(
    user_table,
    related_user,
    user_table.c.id < related_user.c.id,
)
```

### SA-23. CROSS JOIN

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [FROM с несколькими источниками](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#explicit-from-clauses-and-joins).
- Проверяет: декартово произведение строк двух таблиц.

```sql
SELECT user_account.id, address.id
FROM user_account, address
```

```python
stmt = select(user_table.c.id, address_table.c.id).select_from(
    user_table, address_table
)
```

### SA-24. FULL OUTER JOIN

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [OUTER и FULL JOIN](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#outer-and-full-join).
- Проверяет: сохранение несопоставленных строк обеих таблиц; поддержка зависит от СУБД.

```sql
SELECT user_account.id, address.id
FROM user_account
FULL OUTER JOIN address ON user_account.id = address.user_id
```

```python
stmt = select(user_table.c.id, address_table.c.id).join_from(
    user_table,
    address_table,
    user_table.c.id == address_table.c.user_id,
    full=True,
)
```

### SA-25. Коррелированный LATERAL-подзапрос

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [LATERAL correlation](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#lateral-correlation).
- Проверяет: выбор первой связанной строки через подзапрос, коррелированный с текущей строкой пользователя.

```sql
SELECT user_account.id, latest_address.email_address
FROM user_account
LEFT JOIN LATERAL (
  SELECT address.email_address
  FROM address
  WHERE address.user_id = user_account.id
  ORDER BY address.id DESC
  LIMIT 1
) AS latest_address ON true
```

```python
latest_address = (
    select(address_table.c.email_address.label("email_address"))
    .where(address_table.c.user_id == user_table.c.id)
    .order_by(address_table.c.id.desc())
    .limit(1)
    .lateral("latest_address")
)
stmt = select(user_table.c.id, latest_address.c.email_address).select_from(
    user_table.outerjoin(latest_address, true())
)
```

### SA-26. UNION ALL

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [UNION и другие set operations](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#union-union-all-and-other-set-operations).
- Проверяет: объединение результатов без удаления повторов.

```sql
SELECT user_account.id FROM user_account WHERE user_account.name = :name_1
UNION ALL
SELECT user_account.id FROM user_account WHERE user_account.name = :name_2
```

```python
stmt = union_all(
    select(user_table.c.id).where(user_table.c.name == "sandy"),
    select(user_table.c.id).where(user_table.c.name == "spongebob"),
)
```

### SA-27. INTERSECT

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [UNION и другие set operations](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#union-union-all-and-other-set-operations).
- Проверяет: пересечение результатов запросов с совместимыми проекциями.

```sql
SELECT address.user_id FROM address WHERE address.email_address LIKE :pattern_1
INTERSECT
SELECT address.user_id FROM address WHERE address.id > :id_1
```

```python
stmt = intersect(
    select(address_table.c.user_id).where(
        address_table.c.email_address.like(email_pattern)
    ),
    select(address_table.c.user_id).where(address_table.c.id > min_address_id),
)
```

### SA-28. EXCEPT

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [UNION и другие set operations](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#union-union-all-and-other-set-operations).
- Проверяет: строки первого результата, отсутствующие во втором; поддержка зависит от СУБД.

```sql
SELECT user_account.id FROM user_account
EXCEPT
SELECT address.user_id FROM address
```

```python
stmt = except_(
    select(user_table.c.id),
    select(address_table.c.user_id),
)
```

### SA-29. VALUES как источник строк

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [конструктор VALUES](https://docs.sqlalchemy.org/en/20/core/selectable.html#sqlalchemy.sql.expression.values).
- Проверяет: использование набора заданных значений как FROM-источника.

```sql
SELECT selected_ids.id
FROM (VALUES (:id_1), (:id_2)) AS selected_ids(id)
```

```python
selected_ids = values(
    column("id", Integer), name="selected_ids"
).data([(1,), (2,)]).alias()
stmt = select(selected_ids.c.id)
```

### SA-30. Рекурсивный CTE

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [рекурсивные CTE](https://docs.sqlalchemy.org/en/20/core/selectable.html#sqlalchemy.sql.expression.HasCTE.cte).
- Проверяет: рекурсивное расширение результата с условием завершения.

```sql
WITH RECURSIVE nums(n) AS (
  SELECT :start
  UNION ALL
  SELECT nums.n + :step FROM nums WHERE nums.n < :upper_bound
)
SELECT nums.n FROM nums
```

```python
nums = select(literal(1).label("n")).cte("nums", recursive=True)
nums_step = nums.alias("nums_step")
nums = nums.union_all(
    select((nums_step.c.n + 1).label("n")).where(nums_step.c.n < 5)
)
stmt = select(nums.c.n)
```

### SA-31. Многострочный INSERT

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [INSERT с несколькими значениями](https://docs.sqlalchemy.org/en/20/tutorial/data_insert.html#insert-usually-generates-the-values-clause-automatically).
- Проверяет: вставку нескольких строк одной конструкцией; синтаксис зависит от диалекта.

```sql
INSERT INTO user_account (name, fullname)
VALUES (:name_1, :fullname_1), (:name_2, :fullname_2)
```

```python
stmt = insert(user_table).values(
    [
        {"name": "sandy", "fullname": "Sandy Cheeks"},
        {"name": "spongebob", "fullname": "Spongebob Squarepants"},
    ]
)
```

### SA-32. INSERT из SELECT

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [INSERT FROM SELECT](https://docs.sqlalchemy.org/en/20/tutorial/data_insert.html#insertfromselect).
- Проверяет: вставку результата запроса с соответствующим списком целевых колонок.

```sql
INSERT INTO address (user_id, email_address)
SELECT user_account.id, :email
FROM user_account
WHERE user_account.name = :name
```

```python
source = select(user_table.c.id, bindparam("email")).where(
    user_table.c.name == bindparam("name")
)
stmt = insert(address_table).from_select(
    ["user_id", "email_address"], source
)
```

### SA-33. UPDATE ... FROM

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [UPDATE с дополнительными FROM-таблицами](https://docs.sqlalchemy.org/en/20/tutorial/data_update.html#update-from).
- Проверяет: обновление по совпадению с другой таблицей; SQL-форма зависит от СУБД.

```sql
UPDATE user_account
SET fullname = address.email_address
FROM address
WHERE user_account.id = address.user_id
```

```python
stmt = (
    update(user_table)
    .where(user_table.c.id == address_table.c.user_id)
    .values(fullname=address_table.c.email_address)
)
```

### SA-34. DELETE ... USING

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [DELETE с дополнительными FROM-таблицами](https://docs.sqlalchemy.org/en/20/tutorial/data_update.html#multiple-table-deletes).
- Проверяет: удаление по условию, связанному с другой таблицей; форма `USING` зависит от СУБД.

```sql
DELETE FROM address
USING user_account
WHERE address.user_id = user_account.id
  AND user_account.name = :name
```

```python
stmt = delete(address_table).where(
    address_table.c.user_id == user_table.c.id,
    user_table.c.name == name,
)
```

### SA-35. PostgreSQL UPSERT через ON CONFLICT

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [PostgreSQL ON CONFLICT](https://docs.sqlalchemy.org/en/20/dialects/postgresql.html#insert-on-conflict-upsert).
- Проверяет: вставку новой строки или обновление fullname при конфликте уникального имени.

```sql
INSERT INTO user_account (name, fullname)
VALUES (:name, :fullname)
ON CONFLICT (name) DO UPDATE SET fullname = excluded.fullname
```

```python
insert_stmt = pg_insert(user_table).values(name=name, fullname=fullname)
stmt = insert_stmt.on_conflict_do_update(
    index_elements=[user_table.c.name],
    set_={"fullname": insert_stmt.excluded.fullname},
)
```

### SA-36. Пользователи без адресов через NOT EXISTS

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [EXISTS subqueries](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#exists-subqueries).
- Проверяет: отрицание коррелированного `EXISTS` и сохранение пользователей с пустой коллекцией адресов.

```sql
SELECT user_account.id, user_account.name
FROM user_account
WHERE NOT EXISTS (
  SELECT address.id FROM address
  WHERE address.user_id = user_account.id
)
```

```python
addresses = (
    select(address_table.c.id)
    .where(address_table.c.user_id == user_table.c.id)
    .exists()
)
stmt = select(user_table.c.id, user_table.c.name).where(~addresses)
```

### SA-37. Условный агрегат FILTER после LEFT JOIN

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [Special modifiers: FILTER](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#special-modifiers-within-group-filter).
- Проверяет: подсчёт только адресов с нужным доменом и ноль для пользователя без адресов; форма SQL показана для PostgreSQL.

```sql
SELECT user_account.id,
       COUNT(address.id) FILTER (
         WHERE address.email_address LIKE :pattern
       ) AS matched
FROM user_account
LEFT JOIN address ON address.user_id = user_account.id
GROUP BY user_account.id
```

```python
stmt = (
    select(
        user_table.c.id,
        func.count(address_table.c.id)
        .filter(address_table.c.email_address.like(pattern))
        .label("matched"),
    )
    .outerjoin(address_table, address_table.c.user_id == user_table.c.id)
    .group_by(user_table.c.id)
)
```

### SA-38. Последний адрес каждого пользователя через ROW_NUMBER

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [Window Functions](https://docs.sqlalchemy.org/en/20/tutorial/data_select.html#window-functions).
- Проверяет: нумерацию адресов внутри каждого `user_id` и фильтр номера во внешнем запросе; пользователь без адресов не возвращается.

```sql
SELECT user_account.name, ranked.email_address
FROM user_account
JOIN (
  SELECT address.user_id, address.email_address,
         ROW_NUMBER() OVER (
           PARTITION BY address.user_id ORDER BY address.id DESC
         ) AS row_no
  FROM address
) AS ranked ON ranked.user_id = user_account.id
WHERE ranked.row_no = 1
```

```python
ranked = (
    select(
        address_table.c.user_id,
        address_table.c.email_address,
        func.row_number().over(
            partition_by=address_table.c.user_id,
            order_by=address_table.c.id.desc(),
        ).label("row_no"),
    )
    .subquery("ranked")
)
stmt = (
    select(user_table.c.name, ranked.c.email_address)
    .join(ranked, ranked.c.user_id == user_table.c.id)
    .where(ranked.c.row_no == 1)
)
```

### SA-39. Страница строк с FOR UPDATE SKIP LOCKED

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [`Select.with_for_update`](https://docs.sqlalchemy.org/en/20/core/selectable.html#sqlalchemy.sql.expression.Select.with_for_update).
- Проверяет: блокировку выбранных строк в транзакции и пропуск строк, уже заблокированных другим читателем; форма PostgreSQL.

```sql
SELECT user_account.id, user_account.name
FROM user_account
ORDER BY user_account.id
LIMIT :limit
FOR UPDATE OF user_account SKIP LOCKED
```

```python
stmt = (
    select(user_table.c.id, user_table.c.name)
    .order_by(user_table.c.id)
    .limit(10)
    .with_for_update(skip_locked=True, of=user_table)
)
```

### SA-40. UPDATE RETURNING как источник CTE

- OCaml-пример: —
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [CTE with DML](https://docs.sqlalchemy.org/en/20/core/selectable.html#sqlalchemy.sql.expression.HasCTE.cte).
- Проверяет: выполнение UPDATE ровно один раз и чтение его `RETURNING`-строк через внешний SELECT; требуется PostgreSQL.

```sql
WITH updated AS (
  UPDATE user_account
  SET fullname = :fullname
  WHERE name = :name
  RETURNING id, fullname
)
SELECT updated.id, updated.fullname FROM updated
```

```python
updated = (
    update(user_table)
    .where(user_table.c.name == "sandy")
    .values(fullname="Sandra")
    .returning(user_table.c.id, user_table.c.fullname)
    .cte("updated")
)
stmt = select(updated.c.id, updated.c.fullname)
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
