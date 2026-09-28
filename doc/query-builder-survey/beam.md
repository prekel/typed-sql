<!-- SPDX-License-Identifier: MIT -->

# Сценарии запросов из Beam

**Желаемый таргет: 20 сценариев — 5 обычных и 15 сложных.** Сейчас заведены пять обычных сценариев; сложные будут отобраны следующим этапом.

Источники — [руководство Beam](https://haskell-beam.github.io/beam/user-guide/queries/) и его [примеры на базе Chinook](https://haskell-beam.github.io/beam/user-guide/queries/relationships/). Запросы и SQL сокращены и адаптированы. В примерах используется схема `Customer`, `Invoice`, `InvoiceLine`, `Album` из Chinook и имя базы `chinookDb` из руководства. Синтаксис соответствует Beam 0.10.

Код примеров Beam распространяется по [MIT](https://haskell-beam.github.io/beam/about/license/). В конце файла приведено уведомление об авторских правах и лицензии. Это независимая подборка; указание источника не означает одобрения со стороны авторов Beam.

OCaml-реализации typed-sql в этом файле пока нет.

### BE-01. Фильтр и проекция

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [basic queries: filtering and projecting](https://haskell-beam.github.io/beam/user-guide/queries/basic/).
- Проверяет: фильтр по стране и выбор двух полей.

```sql
SELECT FirstName, LastName
FROM Customer
WHERE Country = ?
```

```haskell
select $
  fmap (\customer -> (customerFirstName customer, customerLastName customer)) $
    filter_ (\customer -> customerCountry customer ==. val_ "USA") $
      all_ (customer chinookDb)
```

### BE-02. Составной предикат

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [basic queries: filtering](https://haskell-beam.github.io/beam/user-guide/queries/basic/).
- Проверяет: `AND` с вложенной группой `OR`.

```sql
SELECT CustomerId, FirstName
FROM Customer
WHERE FirstName LIKE ? AND (Country = ? OR Country = ?)
```

```haskell
select $
  fmap (\customer -> (customerId customer, customerFirstName customer)) $
    filter_ (\customer ->
      customerFirstName customer `like_` "Jo%" &&.
      (customerCountry customer ==. val_ "USA" ||.
       customerCountry customer ==. val_ "Canada")) $
      all_ (customer chinookDb)
```

### BE-03. Сортировка и страница

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [ordering](https://haskell-beam.github.io/beam/user-guide/queries/ordering/).
- Проверяет: стабильную сортировку до применения `LIMIT` и `OFFSET`.

```sql
SELECT AlbumId, Title
FROM Album
ORDER BY Title ASC
LIMIT 10 OFFSET 20
```

```haskell
select $
  limit_ 10 $
    offset_ 20 $
      orderBy_ (asc_ . albumTitle) $
        fmap (\album -> (albumId album, albumTitle album)) $
          all_ (album chinookDb)
```

### BE-04. INNER JOIN

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [relationships](https://haskell-beam.github.io/beam/user-guide/queries/relationships/).
- Проверяет: соединение счетов с их строками.

```sql
SELECT Invoice.InvoiceId, InvoiceLine.InvoiceLineId
FROM Invoice
INNER JOIN InvoiceLine ON InvoiceLine.InvoiceId = Invoice.InvoiceId
```

```haskell
select $ do
  invoice <- all_ (invoice chinookDb)
  line <- all_ (invoiceLine chinookDb)
  guard_ (invoiceLineInvoice line ==. primaryKey invoice)
  pure (invoiceId invoice, invoiceLineId line)
```

### BE-05. LEFT JOIN с отсутствующей правой строкой

- OCaml-пример: ✗
- Реализуемость: —
- Семантика: —
- Без доработок typed-sql: —
- Источник: [left and right joins](https://haskell-beam.github.io/beam/user-guide/queries/relationships/#left-and-right-joins).
- Проверяет: сохранение покупателя без счета и nullable-сторону результата.

```sql
SELECT Customer.CustomerId, Invoice.InvoiceId
FROM Customer
LEFT JOIN Invoice ON Invoice.CustomerId = Customer.CustomerId
```

```haskell
select $ do
  customer <- all_ (customer chinookDb)
  invoice <- leftJoin_ (all_ (invoice chinookDb)) $ \invoice ->
    invoiceCustomer invoice ==. primaryKey customer
  pure (customerId customer, invoice)
```

## Уведомление о лицензии

The MIT License (MIT)

Copyright (c) 2015-2018 Travis Athougies and the Beam Authors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
