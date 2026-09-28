<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Сценарии запросов из Diesel

**Желаемый таргет: 20 сценариев — 5 обычных и 15 сложных.** Сейчас заведены пять обычных сценариев; сложные будут отобраны следующим этапом.

Источники — [All About Selects](https://diesel.rs/guides/all-about-selects/) и [Relations](https://diesel.rs/guides/relations/) из документации Diesel (доступ 28.09.2026). Примеры и SQL сокращены и адаптированы под схему `users(id, name)` и `posts(id, user_id, title)`. Для JOIN предполагается объявленная Diesel-связь `posts.user_id -> users.id`.

Diesel распространяется по [MIT или Apache-2.0](https://github.com/diesel-rs/diesel#license). Здесь используется вариант MIT для уведомления об авторских правах. Примеры кода адаптированы; указание источника не означает одобрения со стороны авторов Diesel.

OCaml-реализации typed-sql в этом файле пока нет.

```rust
use diesel::prelude::*;

diesel::table! {
    users (id) {
        id -> Integer,
        name -> Text,
    }
}

diesel::table! {
    posts (id) {
        id -> Integer,
        user_id -> Integer,
        title -> Text,
    }
}

diesel::joinable!(posts -> users (user_id));
diesel::allow_tables_to_appear_in_same_query!(users, posts);
```

### DI-01. Фильтр и проекция

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [All About Selects: Query Building](https://diesel.rs/guides/all-about-selects/).
- Проверяет: выбор идентификатора и имени по bind-параметру.

```sql
SELECT id, name
FROM users
WHERE name = $1
```

```rust
let rows = users::table
    .filter(users::name.eq(name))
    .select((users::id, users::name))
    .load::<(i32, String)>(connection)?;
```

### DI-02. Несколько фильтров

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [All About Selects: Filtering](https://diesel.rs/guides/all-about-selects/).
- Проверяет: композицию фильтров через последовательные вызовы `filter`.

```sql
SELECT id, name
FROM users
WHERE id > $1 AND name LIKE $2
```

```rust
let rows = users::table
    .filter(users::id.gt(min_id))
    .filter(users::name.like(name_pattern))
    .select((users::id, users::name))
    .load::<(i32, String)>(connection)?;
```

### DI-03. Сортировка и страница

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [QueryDsl](https://docs.diesel.rs/master/diesel/query_dsl/trait.QueryDsl.html).
- Проверяет: сортировку до ограничения и смещения результата.

```sql
SELECT id, name
FROM users
ORDER BY id ASC
LIMIT $1 OFFSET $2
```

```rust
let rows = users::table
    .order(users::id.asc())
    .limit(page_size)
    .offset(page_offset)
    .select((users::id, users::name))
    .load::<(i32, String)>(connection)?;
```

### DI-04. INNER JOIN

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [Relations: inner joins](https://diesel.rs/guides/relations/).
- Проверяет: JOIN по объявленной внешней связи.

```sql
SELECT users.id, posts.title
FROM users
INNER JOIN posts ON posts.user_id = users.id
```

```rust
let rows = users::table
    .inner_join(posts::table)
    .select((users::id, posts::title))
    .load::<(i32, String)>(connection)?;
```

### DI-05. LEFT JOIN с отсутствующей правой строкой

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [Relations: left joins](https://diesel.rs/guides/relations/).
- Проверяет: сохранение пользователя без постов и nullable-колонку справа.

```sql
SELECT users.id, posts.id
FROM users
LEFT JOIN posts ON posts.user_id = users.id
```

```rust
let rows = users::table
    .left_join(posts::table)
    .select((users::id, posts::id.nullable()))
    .load::<(i32, Option<i32>)>(connection)?;
```

## Уведомление о лицензии

The MIT License (MIT)

2015-2021 Sean Griffin, 2018-2021 Diesel Core Team

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
