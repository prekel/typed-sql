<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Сценарии запросов из SeaQuery

**Желаемый таргет: 20 сценариев — 5 обычных и 15 сложных.** Сейчас заведены пять обычных сценариев; сложные будут отобраны следующим этапом.

Источники — [раздел Query Select](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html) документации SeaQuery и [руководство SeaORM](https://www.sea-ql.org/sea-orm-tutorial/ch01-08-sql-with-sea-query.html) (доступ 28.09.2026). Примеры сокращены и адаптированы под схему `users(id, name, country)` и `posts(id, user_id, title)`. SQL приведён в форме PostgreSQL; `build(PostgresQueryBuilder)` также возвращает значения отдельно от SQL.

SeaQuery распространяется по [MIT или Apache-2.0](https://github.com/SeaQL/sea-query#license). Здесь используется вариант MIT для уведомления об авторских правах. Примеры кода адаптированы; указание источника не означает одобрения со стороны SeaQL.

OCaml-реализации typed-sql в этом файле пока нет.

```rust
use sea_query::{Expr, Iden, JoinType, Order, PostgresQueryBuilder, Query};

#[derive(Iden)]
enum Users {
    Table,
    Id,
    Name,
    Country,
}

#[derive(Iden)]
enum Posts {
    Table,
    Id,
    UserId,
    Title,
}
```

### SQ-01. Фильтр и проекция

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [SelectStatement examples](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html).
- Проверяет: проекцию двух колонок и условие по стране.

```sql
SELECT users.id, users.name
FROM users
WHERE users.country = $1
```

```rust
let query = Query::select()
    .column((Users::Table, Users::Id))
    .column((Users::Table, Users::Name))
    .from(Users::Table)
    .and_where(Expr::col((Users::Table, Users::Country)).eq(country))
    .to_owned();

let (sql, values) = query.build(PostgresQueryBuilder);
```

### SQ-02. Несколько фильтров

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [WHERE conditions](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html).
- Проверяет: объединение условий через последовательные `and_where`.

```sql
SELECT users.id, users.name
FROM users
WHERE users.country = $1 AND users.name LIKE $2
```

```rust
let query = Query::select()
    .column((Users::Table, Users::Id))
    .column((Users::Table, Users::Name))
    .from(Users::Table)
    .and_where(Expr::col((Users::Table, Users::Country)).eq(country))
    .and_where(Expr::col((Users::Table, Users::Name)).like(name_pattern))
    .to_owned();

let (sql, values) = query.build(PostgresQueryBuilder);
```

### SQ-03. Сортировка и страница

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [order_by, limit, offset](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html).
- Проверяет: сортировку по ключу перед ограничением и смещением.

```sql
SELECT users.id, users.name
FROM users
ORDER BY users.id ASC
LIMIT 10 OFFSET 20
```

```rust
let query = Query::select()
    .column((Users::Table, Users::Id))
    .column((Users::Table, Users::Name))
    .from(Users::Table)
    .order_by((Users::Id, Order::Asc))
    .limit(10)
    .offset(20)
    .to_owned();

let (sql, values) = query.build(PostgresQueryBuilder);
```

### SQ-04. INNER JOIN

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [join](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html#method.join).
- Проверяет: JOIN с явно заданным условием.

```sql
SELECT users.id, posts.title
FROM users
INNER JOIN posts ON users.id = posts.user_id
```

```rust
let query = Query::select()
    .column((Users::Table, Users::Id))
    .column((Posts::Table, Posts::Title))
    .from(Users::Table)
    .join(
        JoinType::InnerJoin,
        Posts::Table,
        Expr::col((Users::Table, Users::Id))
            .equals((Posts::Table, Posts::UserId)),
    )
    .to_owned();

let (sql, values) = query.build(PostgresQueryBuilder);
```

### SQ-05. LEFT JOIN с отсутствующей правой строкой

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [left_join](https://docs.rs/sea-query/latest/sea_query/query/struct.SelectStatement.html#method.left_join).
- Проверяет: сохранение пользователя без постов.

```sql
SELECT users.id, posts.title
FROM users
LEFT JOIN posts ON users.id = posts.user_id
```

```rust
let query = Query::select()
    .column((Users::Table, Users::Id))
    .column((Posts::Table, Posts::Title))
    .from(Users::Table)
    .left_join(
        Posts::Table,
        Expr::col((Users::Table, Users::Id))
            .equals((Posts::Table, Posts::UserId)),
    )
    .to_owned();

let (sql, values) = query.build(PostgresQueryBuilder);
```

## Уведомление о лицензии

The MIT License (MIT)

Copyright (c) 2020 Tsang Hao Fung

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
