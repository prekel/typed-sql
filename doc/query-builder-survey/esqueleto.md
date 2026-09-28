<!-- SPDX-License-Identifier: BSD-3-Clause -->

# Сценарии запросов из Esqueleto

**Желаемый таргет: 20 сценариев — 5 обычных и 15 сложных.** Сейчас заведены пять обычных сценариев; сложные будут отобраны следующим этапом.

Источник — [документация `Database.Esqueleto.Experimental`](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html), версия Esqueleto 3.6.0.0. Примеры сокращены и адаптированы. Схема следует документации: `Person(name, age)` и `BlogPost(title, authorId)`; `age` nullable. SQL показывает существенную форму запросов.

Пакет Esqueleto распространяется по [BSD-3-Clause](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0). В конце файла приведено уведомление об авторских правах и лицензии. Это независимая подборка; указание источника не означает одобрения со стороны авторов Esqueleto.

OCaml-реализации typed-sql в этом файле пока нет.

```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

import Database.Esqueleto.Experimental
```

### EQ-01. Фильтр и проекция

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [Example 1: Simple select](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:select).
- Проверяет: фильтр по имени и проекцию идентификатора с именем.

```sql
SELECT id, name
FROM person
WHERE name = ?
```

```haskell
select $ do
  person <- from $ table @Person
  where_ (person ^. PersonName ==. val "John")
  pure (person ^. PersonId, person ^. PersonName)
```

### EQ-02. Составной предикат с nullable-колонкой

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [basic expressions and predicates](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html).
- Проверяет: сравнение nullable-возраста и группировку `AND`/`OR`.

```sql
SELECT id, name
FROM person
WHERE age >= 18 AND (name = ? OR name = ?)
```

```haskell
select $ do
  person <- from $ table @Person
  where_ $
    person ^. PersonAge >=. just (val 18) &&.
    (person ^. PersonName ==. val "John" ||.
     person ^. PersonName ==. val "Jane")
  pure (person ^. PersonId, person ^. PersonName)
```

### EQ-03. Сортировка и страница

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [ordering and pagination](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html).
- Проверяет: порядок по имени перед применением `LIMIT` и `OFFSET`.

```sql
SELECT id, name
FROM person
ORDER BY name ASC
LIMIT 10 OFFSET 20
```

```haskell
select $ do
  person <- from $ table @Person
  orderBy [asc (person ^. PersonName)]
  limit 10
  offset 20
  pure (person ^. PersonId, person ^. PersonName)
```

### EQ-04. INNER JOIN

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [Example 2: Select with join](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:innerJoin).
- Проверяет: связь поста с автором.

```sql
SELECT person.id, blog_post.id
FROM person
INNER JOIN blog_post ON blog_post.author_id = person.id
```

```haskell
select $ do
  (person :& post) <-
    from $ table @Person
      `innerJoin` table @BlogPost
      `on` (\(person :& post) -> person ^. PersonId ==. post ^. BlogPostAuthorId)
  pure (person ^. PersonId, post ^. BlogPostId)
```

### EQ-05. LEFT JOIN с отсутствующей правой строкой

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [Example 2: Select with join](https://hackage-content.haskell.org/package/esqueleto-3.6.0.0/docs/Database-Esqueleto-Experimental.html#v:leftJoin).
- Проверяет: сохранение человека без постов и nullable-сторону результата.

```sql
SELECT person.id, blog_post.id
FROM person
LEFT JOIN blog_post ON blog_post.author_id = person.id
```

```haskell
select $ do
  (person :& post) <-
    from $ table @Person
      `leftJoin` table @BlogPost
      `on` (\(person :& post) -> just (person ^. PersonId) ==. post ?. BlogPostAuthorId)
  pure (person ^. PersonId, post ?. BlogPostId)
```

## Уведомление о лицензии

Copyright (c) 2012–2016 Felipe Almeida Lessa

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
