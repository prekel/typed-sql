# Сценарии запросов из EF Core

Первые 15 сценариев из [документации EF Core](https://learn.microsoft.com/en-us/ef/core/) (доступ 28.09.2026). LINQ и SQL сокращены и адаптированы. SQL показывает существенную форму перевода, а не точный лог конкретной версии провайдера. Квадратные скобки и `@parameter` относятся к SQL Server; EF-10 использует синтаксис PostgreSQL, как в источнике. Условия переноса зависят от версии EF Core и провайдера, поэтому при дальнейшем сравнении нужно фиксировать оба.

Текст документации Microsoft / .NET team распространяется по [CC BY 4.0](https://github.com/dotnet/EntityFramework.Docs/blob/main/LICENSE), а [примеры кода — по MIT](https://github.com/dotnet/EntityFramework.Docs/blob/main/LICENSE-CODE), © Microsoft Corporation. Здесь примеры сокращены, проекции упрощены и добавлены критерии проверки. Уведомление MIT приведено в конце файла. Ссылки в каждой карточке ведут к разделу с контекстом.

Используются модели примеров `Blog`, `Post`, `Contributor` и `Book`. Карточки взяты из разных разделов документации; одноимённые модели не образуют единую схему. Для outer join и загрузки коллекций нужна фикстура с пустой коллекцией. Отмечать `[x]` следует после переноса сценария в regression-набор и выполнения на заявленных диалектах. Для клиентских операций проверять и SQL, и итоговый результат.

### EF-01. Страница через OFFSET

- [ ] Перенесено в regression-набор.
- Источник: [offset pagination](https://learn.microsoft.com/en-us/ef/core/querying/pagination#offset-pagination).
- Проверяет: порядок и границы страницы.

```sql
SELECT [p].[PostId] FROM [Posts] AS [p]
ORDER BY [p].[PostId]
OFFSET @skip ROWS FETCH NEXT @take ROWS ONLY
```

```csharp
var page = await context.Posts
    .OrderBy(p => p.PostId)
    .Skip(skip)
    .Take(take)
    .Select(p => p.PostId)
    .ToListAsync();
```

### EF-02. Keyset по двум колонкам

- [ ] Перенесено в regression-набор.
- Источник: [multiple pagination keys](https://learn.microsoft.com/en-us/ef/core/querying/pagination#multiple-pagination-keys).
- Проверяет: лексикографический фильтр с составным порядком и дублирующимися датами.

```sql
SELECT [p].[PostId], [p].[Date] FROM [Posts] AS [p]
WHERE [p].[Date] > @lastDate
   OR ([p].[Date] = @lastDate AND [p].[PostId] > @lastId)
ORDER BY [p].[Date], [p].[PostId]
OFFSET 0 ROWS FETCH NEXT @take ROWS ONLY
```

```csharp
var page = await context.Posts
    .OrderBy(p => p.Date)
    .ThenBy(p => p.PostId)
    .Where(p => p.Date > lastDate ||
                (p.Date == lastDate && p.PostId > lastId))
    .Take(take)
    .Select(p => new { p.PostId, p.Date })
    .ToListAsync();
```

### EF-03. INNER JOIN

- [ ] Перенесено в regression-набор.
- Источник: [Join](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators#join).
- Проверяет: соединение по ключу и число результирующих строк.

```sql
SELECT [b].[BlogId], [p].[PostId]
FROM [Blogs] AS [b]
INNER JOIN [Posts] AS [p] ON [b].[BlogId] = [p].[BlogId]
```

```csharp
var query =
    from b in context.Blogs
    join p in context.Posts on b.BlogId equals p.BlogId
    select new { b.BlogId, p.PostId };
```

### EF-04. LEFT JOIN через GroupJoin

- [ ] Перенесено в regression-набор.
- Источник: [left join](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators#left-join).
- Проверяет: `DefaultIfEmpty` и строку для блога без постов.

```sql
SELECT [b].[BlogId], [p].[PostId]
FROM [Blogs] AS [b]
LEFT JOIN [Posts] AS [p] ON [b].[BlogId] = [p].[BlogId]
```

```csharp
var query =
    from b in context.Blogs
    join p in context.Posts on b.BlogId equals p.BlogId into posts
    from p in posts.DefaultIfEmpty()
    select new { b.BlogId, PostId = p == null ? (int?)null : p.PostId };
```

### EF-05. CROSS JOIN

- [ ] Перенесено в regression-набор.
- Источник: [SelectMany without outer reference](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators#collection-selector-doesnt-reference-outer).
- Проверяет: декартово произведение двух источников.

```sql
SELECT [b].[BlogId], [p].[PostId]
FROM [Blogs] AS [b]
CROSS JOIN [Posts] AS [p]
```

```csharp
var query =
    from b in context.Blogs
    from p in context.Posts
    select new { b.BlogId, p.PostId };
```

### EF-06. Коррелированный selector как JOIN

- [ ] Перенесено в regression-набор.
- Источник: [collection selector references outer in WHERE](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators#collection-selector-references-outer-in-a-where-clause).
- Проверяет: перевод ссылки на внешнюю строку в условие соединения.

```sql
SELECT [b].[BlogId], [p].[PostId]
FROM [Blogs] AS [b]
INNER JOIN [Posts] AS [p] ON [b].[BlogId] = [p].[BlogId]
```

```csharp
var query =
    from b in context.Blogs
    from p in context.Posts.Where(p => p.BlogId == b.BlogId)
    select new { b.BlogId, p.PostId };
```

### EF-07. Коррелированная проекция как APPLY

- [ ] Перенесено в regression-набор.
- Источник: [collection selector references outer outside WHERE](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators#collection-selector-references-outer-in-a-non-where-case).
- Проверяет: зависимый источник и границу переносимости; SQLite не поддерживает `APPLY`.

```sql
SELECT [b].[BlogId], ([b].[Url] + N'=>') + [p].[Title] AS [text]
FROM [Blogs] AS [b]
CROSS APPLY [Posts] AS [p]
```

```csharp
var query =
    from b in context.Blogs
    from text in context.Posts.Select(p => b.Url + "=>" + p.Title)
    select new { b.BlogId, text };
```

### EF-08. GROUP BY с COUNT

- [ ] Перенесено в regression-набор.
- Источник: [GroupBy](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators#groupby).
- Проверяет: серверную агрегацию и отсутствие группы для пустого источника.

```sql
SELECT [p].[AuthorId], COUNT(*) AS [Count]
FROM [Posts] AS [p]
GROUP BY [p].[AuthorId]
```

```csharp
var query = context.Posts
    .GroupBy(p => p.AuthorId)
    .Select(g => new { AuthorId = g.Key, Count = g.Count() });
```

### EF-09. HAVING после группировки

- [ ] Перенесено в regression-набор.
- Источник: [GroupBy with aggregate predicate](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators#groupby).
- Проверяет: применение условия к группе, затем сортировку.

```sql
SELECT [p].[AuthorId], COUNT(*) AS [Count]
FROM [Posts] AS [p]
GROUP BY [p].[AuthorId]
HAVING COUNT(*) > @minCount
ORDER BY [p].[AuthorId]
```

```csharp
var query = context.Posts
    .GroupBy(p => p.AuthorId)
    .Where(g => g.Count() > minCount)
    .OrderBy(g => g.Key)
    .Select(g => new { AuthorId = g.Key, Count = g.Count() });
```

### EF-10. Подзапрос в IN

- [ ] Перенесено в regression-набор.
- Источник: [EF Core 8: better use of IN queries](https://learn.microsoft.com/en-us/ef/core/what-is-new/ef-core-8.0/whatsnew#better-use-of-in-queries).
- Проверяет: `Contains` с подзапросом и устранение корреляции. SQL в источнике дан для PostgreSQL.

```sql
SELECT b."Id", b."Name"
FROM "Blogs" AS b
WHERE b."Id" IN (SELECT p."BlogId" FROM "Posts" AS p)
```

```csharp
var blogs = await context.Blogs
    .Where(b => context.Posts.Select(p => p.BlogId).Contains(b.Id))
    .ToListAsync();
```

### EF-11. GroupBy с финальной группировкой на клиенте

- [ ] Перенесено в regression-набор.
- Источник: [GroupBy without aggregate](https://learn.microsoft.com/en-us/ef/core/querying/complex-query-operators#groupby).
- Проверяет: различие между SQL-строками и итоговыми группами; EF Core 7+ собирает группы после чтения.

```sql
SELECT [b].[Price], [b].[Id], [b].[AuthorId]
FROM [Books] AS [b]
ORDER BY [b].[Price]
```

```csharp
var groups = await context.Books
    .GroupBy(b => b.Price)
    .ToListAsync();
```

В SQL нет `GROUP BY`: группировка здесь выполняется после получения строк.

### EF-12. Include двух соседних коллекций

- [ ] Перенесено в regression-набор.
- Источник: [cartesian explosion](https://learn.microsoft.com/en-us/ef/core/querying/single-split-queries#cartesian-explosion).
- Проверяет: два `LEFT JOIN`, умножение строк на сервере и сборку двух коллекций на клиенте.

```sql
SELECT [b].[Id], [p].[Id], [c].[Id]
FROM [Blogs] AS [b]
LEFT JOIN [Posts] AS [p] ON [b].[Id] = [p].[BlogId]
LEFT JOIN [Contributors] AS [c] ON [b].[Id] = [c].[BlogId]
ORDER BY [b].[Id], [p].[Id]
```

```csharp
var blogs = await context.Blogs
    .Include(b => b.Posts)
    .Include(b => b.Contributors)
    .ToListAsync();
```

### EF-13. Split query для коллекции

- [ ] Перенесено в regression-набор.
- Источник: [split queries](https://learn.microsoft.com/en-us/ef/core/querying/single-split-queries#split-queries).
- Проверяет: два серверных запроса, порядок строк и сборку коллекции на клиенте.

```sql
SELECT [b].[BlogId] FROM [Blogs] AS [b] ORDER BY [b].[BlogId];

SELECT [p].[PostId], [p].[BlogId], [b].[BlogId]
FROM [Blogs] AS [b]
INNER JOIN [Posts] AS [p] ON [b].[BlogId] = [p].[BlogId]
ORDER BY [b].[BlogId];
```

```csharp
var blogs = await context.Blogs
    .Include(b => b.Posts)
    .AsSplitQuery()
    .ToListAsync();
```

### EF-14. ExecuteUpdate с коррелированным агрегатом

- [ ] Перенесено в regression-набор.
- Источник: [updating from related entities](https://learn.microsoft.com/en-us/ef/core/saving/execute-insert-update-delete#navigations-and-related-entities).
- Проверяет: выражение для `SET` на основе связанных строк и поведение при пустой коллекции.

```sql
UPDATE [b]
SET [b].[Rating] = CAST((
  SELECT AVG(CAST([p].[Rating] AS float))
  FROM [Post] AS [p]
  WHERE [p].[BlogId] = [b].[Id]
) AS int)
FROM [Blogs] AS [b]
```

```csharp
await context.Blogs
    .Select(b => new {
        Blog = b,
        NewRating = b.Posts.Average(p => p.Rating)
    })
    .ExecuteUpdateAsync(setters =>
        setters.SetProperty(x => x.Blog.Rating, x => x.NewRating));
```

Пример зависит от приведения типов у провайдера и может потребовать отдельной проверки пустой коллекции.

### EF-15. ExecuteDelete

- [ ] Перенесено в regression-набор.
- Источник: [ExecuteDelete](https://learn.microsoft.com/en-us/ef/core/saving/execute-insert-update-delete#executedelete).
- Проверяет: массовое условное удаление без загрузки сущностей.

```sql
DELETE FROM [b]
FROM [Blogs] AS [b]
WHERE [b].[Rating] < @threshold
```

```csharp
await context.Blogs
    .Where(b => b.Rating < threshold)
    .ExecuteDeleteAsync();
```

## Уведомление о лицензии примеров кода

The MIT License (MIT)

Copyright (c) Microsoft Corporation

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial
portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
