<!-- SPDX-License-Identifier: MIT -->

# Сценарии запросов из Beam

**Желаемый таргет: 20 сценариев — 5 обычных и 15 сложных.** Сейчас заведены пять обычных и пять сложных сценариев.

Источники — [руководство Beam](https://haskell-beam.github.io/beam/user-guide/queries/) и его [примеры на базе Chinook](https://haskell-beam.github.io/beam/user-guide/queries/relationships/). Запросы и SQL сокращены и адаптированы. В примерах используется схема `Customer`, `Invoice`, `InvoiceLine`, `Album` из Chinook и имя базы `chinookDb` из руководства. Синтаксис соответствует Beam 0.10.

Код примеров Beam распространяется по [MIT](https://haskell-beam.github.io/beam/about/license/). В конце файла приведено уведомление об авторских правах и лицензии. Это независимая подборка; указание источника не означает одобрения со стороны авторов Beam.

OCaml-примеры typed-sql добавлены для BE-06–BE-08 и BE-10. BE-09 требует оконных выражений, которых пока нет в DSL.

В новых примерах с `as_ @Int32` предполагаются расширение `TypeApplications` и импорт `Int32` из `Data.Int`.

## Общие descriptors typed-sql для BE-06–BE-10

```ocaml
open! Base
open Typed_sql
open Infix

module Customer = struct
  type row

  let table : row Table.t = Table.v_exn "Customer"
  let id_column = Column.v_exn table "CustomerId" Db_type.int
  let first_name_column = Column.v_exn table "FirstName" Db_type.text
  let last_name_column = Column.v_exn table "LastName" Db_type.text
  let country_column = Column.v_exn table "Country" Db_type.text
  let id row = Expr.column row id_column
  let first_name row = Expr.column row first_name_column
  let last_name row = Expr.column row last_name_column
  let country row = Expr.column row country_column
end

module Invoice = struct
  type row

  let table : row Table.t = Table.v_exn "Invoice"
  let id_column = Column.v_exn table "InvoiceId" Db_type.int
  let customer_id_column = Column.v_exn table "CustomerId" Db_type.int
  let id row = Expr.column row id_column
  let customer_id row = Expr.column row customer_id_column
end
```

Общие descriptors используются в примерах BE-06–BE-08 и BE-10.

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

### BE-06. GROUP BY и HAVING по числу счетов

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [aggregates: GROUP BY и HAVING](https://haskell-beam.github.io/beam/user-guide/queries/aggregates/).
- Проверяет: группировку по покупателю и фильтрацию после подсчёта счетов.

```sql
SELECT Invoice.CustomerId, COUNT(*) AS invoice_count
FROM Invoice
GROUP BY Invoice.CustomerId
HAVING COUNT(*) > 1
```

```haskell
select $
  filter_ (\(_, invoiceCount) -> invoiceCount >. 1) $
    aggregate_ (\i ->
      ( group_ (invoiceCustomer i)
      , as_ @Int32 countAll_ )) $
        all_ (invoice chinookDb)
```

#### OCaml (typed-sql)

```ocaml
let beam06 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Invoice.table
      |> group_by Invoice.customer_id
      |> having (fun _ -> Expr.count_all >$ 1L)
      |> select (fun invoice ->
        Projection.pair (Invoice.customer_id invoice) Expr.count_all)))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql beam06);;
SELECT
  t0."CustomerId",
  COUNT(*)
FROM "Invoice" AS t0
GROUP BY
  t0."CustomerId"
HAVING
  (COUNT(*) > $1)
```

### BE-07. Коррелированный EXISTS

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [подзапросы в выражениях](https://haskell-beam.github.io/beam/user-guide/expressions/#subqueries), [пример с EXISTS](https://haskell-beam.github.io/beam/tutorials/tutorial3/).
- Проверяет: отбор покупателей со счетами без размножения строк покупателя.

```sql
SELECT Customer.CustomerId, Customer.LastName
FROM Customer
WHERE EXISTS (
  SELECT Invoice.InvoiceId
  FROM Invoice
  WHERE Invoice.CustomerId = Customer.CustomerId
)
```

```haskell
select $ do
  customer <- all_ (customer chinookDb)
  guard_ $ exists_ $ do
    inv <- all_ (invoice chinookDb)
    guard_ (invoiceCustomer inv ==. primaryKey customer)
    pure (invoiceId inv)
  pure (customerId customer, customerLastName customer)
```

#### OCaml (typed-sql)

Внутренний `EXISTS` использует колонку покупателя из внешнего SELECT.

```ocaml
let beam07 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Customer.table
      |> where (fun customer ->
        exists
          Query.(
            from Invoice.table
            |> where (fun invoice ->
              Invoice.customer_id invoice =. Customer.id customer)))
      |> select (fun customer ->
        Projection.pair (Customer.id customer) (Customer.last_name customer))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql beam07);;
SELECT
  t0."CustomerId",
  t0."LastName"
FROM "Customer" AS t0
WHERE
  (EXISTS (
    SELECT
      1
    FROM "Invoice" AS t1
    WHERE
      (t1."CustomerId" = t0."CustomerId")
  ))
```

### BE-08. Агрегатный подзапрос в FROM

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [подзапросы в JOIN](https://haskell-beam.github.io/beam/user-guide/queries/relationships/#subqueries), [агрегация](https://haskell-beam.github.io/beam/user-guide/queries/aggregates/).
- Проверяет: использование числа счетов из отдельного агрегатного источника при соединении с покупателями.

```sql
SELECT Customer.CustomerId, invoice_counts.invoice_count
FROM Customer
JOIN (
  SELECT Invoice.CustomerId, COUNT(*) AS invoice_count
  FROM Invoice
  GROUP BY Invoice.CustomerId
) AS invoice_counts
  ON invoice_counts.CustomerId = Customer.CustomerId
```

```haskell
select $ do
  customer <- all_ (customer chinookDb)
  (customerKey, invoiceCount) <-
    subselect_ $
      aggregate_ (\i ->
        ( group_ (invoiceCustomer i)
        , as_ @Int32 countAll_ )) $
          all_ (invoice chinookDb)
  guard_ (customerKey ==. primaryKey customer)
  pure (customerId customer, invoiceCount)
```

#### OCaml (typed-sql)

`select_relation` задаёт агрегирующую derived table; внешний запрос соединяет её с покупателями.

```ocaml
let beam08_invoice_counts =
  Query.(
    from Invoice.table
    |> group_by Invoice.customer_id
    |> select_relation (fun invoice ->
      Derived_table.Fields.pair
        (Invoice.customer_id invoice)
        Expr.count_all))

let beam08 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Customer.table
      |> inner_join_relation beam08_invoice_counts
           ~on:(fun customer (invoice_customer_id, _invoice_count) ->
             Customer.id customer =. invoice_customer_id)
      |> select (fun (customer, (_invoice_customer_id, invoice_count)) ->
        Projection.pair (Customer.id customer) invoice_count)))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql beam08);;
SELECT
  t0."CustomerId",
  t1."field_2"
FROM "Customer" AS t0
INNER JOIN (
  SELECT
    t2."CustomerId" AS "field_1",
    COUNT(*) AS "field_2"
  FROM "Invoice" AS t2
  GROUP BY
    t2."CustomerId"
) AS t1
  ON (t0."CustomerId" = t1."field_1")
```

### BE-09. Ранг счета внутри покупателя

- OCaml-пример: ✗
- Реализуемость: ✗
- Семантика: —
- Без доработок typed-sql: ✗
- Источник: [window functions](https://haskell-beam.github.io/beam/user-guide/queries/window-functions/).
- Проверяет: оконный `RANK` по сумме счета без схлопывания строк; равные суммы получают одинаковый ранг.

`OVER (PARTITION BY ... ORDER BY ...)` отсутствует в публичном API и semantic AST typed-sql.

```sql
SELECT Invoice.InvoiceId,
       RANK() OVER (
         PARTITION BY Invoice.CustomerId
         ORDER BY Invoice.Total DESC
       ) AS invoice_rank
FROM Invoice
```

```haskell
select $
  fmap (\(i, invoiceRank) -> (invoiceId i, invoiceRank)) $
    withWindow_
      (\i -> frame_
        (partitionBy_ (invoiceCustomer i))
        (orderPartitionBy_ (desc_ (invoiceTotal i)))
        noBounds_)
      (\i w -> (i, as_ @Int32 rank_ `over_` w))
      (all_ (invoice chinookDb))
```

### BE-10. Вложенные INTERSECT и EXCEPT

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [combining queries](https://haskell-beam.github.io/beam/user-guide/queries/combining-queries/).
- Проверяет: пересечение имён и фамилий с последующим исключением имён покупателей из США; вложенность должна сохраняться при компиляции для разных диалектов.

```sql
(SELECT Customer.FirstName FROM Customer
 INTERSECT
 SELECT Customer.LastName FROM Customer)
EXCEPT
SELECT Customer.FirstName FROM Customer WHERE Customer.Country = ?
```

```haskell
let firstNames =
      fmap customerFirstName (all_ (customer chinookDb))
    lastNames =
      fmap customerLastName (all_ (customer chinookDb))
    usaFirstNames =
      fmap customerFirstName $
        filter_ (\c -> customerCountry c ==. val_ "USA") $
          all_ (customer chinookDb)
in select $
     (firstNames `intersect_` lastNames) `except_` usaFirstNames
```

#### OCaml (typed-sql)

Обе операции набора поддерживаются portable-компилятором; все ветви возвращают текст.

```ocaml
let beam10_names select_name =
  Query.(
    from Customer.table
    |> select (fun customer -> Projection.expr (select_name customer)))

let beam10_first_names = beam10_names Customer.first_name
let beam10_last_names = beam10_names Customer.last_name

let beam10_usa_first_names =
  Query.(
    from Customer.table
    |> where (fun customer -> Customer.country customer =$ "USA")
    |> select (fun customer -> Projection.expr (Customer.first_name customer)))

let beam10 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.except
      (Query.intersect beam10_first_names beam10_last_names)
      beam10_usa_first_names)
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql beam10);;
SELECT *
FROM (
  SELECT *
  FROM (
    SELECT
      t0."FirstName"
    FROM "Customer" AS t0
  ) AS s0
  INTERSECT
  SELECT *
  FROM (
    SELECT
      t0."LastName"
    FROM "Customer" AS t0
  ) AS s0
) AS s0
EXCEPT
SELECT *
FROM (
  SELECT
    t0."FirstName"
  FROM "Customer" AS t0
  WHERE
    (t0."Country" = $1)
) AS s0
```

## Уведомление о лицензии

The MIT License (MIT)

Copyright (c) 2015-2018 Travis Athougies and the Beam Authors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
