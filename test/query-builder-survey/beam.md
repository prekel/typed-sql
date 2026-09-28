<!-- SPDX-License-Identifier: MIT -->

# Сценарии запросов из Beam

**Желаемый таргет: 20 сценариев — 5 обычных и 15 сложных.** Каталог включает пять обычных и пятнадцать сложных сценариев.

Источники — [руководство Beam](https://haskell-beam.github.io/beam/user-guide/queries/) и его [примеры на базе Chinook](https://haskell-beam.github.io/beam/user-guide/queries/relationships/). Запросы и SQL сокращены и адаптированы. В примерах используется схема `Customer`, `Invoice`, `InvoiceLine`, `Album` из Chinook и имя базы `chinookDb` из руководства. Синтаксис соответствует Beam 0.10.

Код примеров Beam распространяется по [MIT](https://haskell-beam.github.io/beam/about/license/). В конце файла приведено уведомление об авторских правах и лицензии. Это независимая подборка; указание источника не означает одобрения со стороны авторов Beam.

OCaml-примеры typed-sql приведены для BE-01–BE-20. BE-09 воспроизводит `RANK` коррелированным `COUNT(DISTINCT Total)`; оконный синтаксис в ядро не добавляется.

В новых примерах с `as_ @Int32` предполагаются расширение `TypeApplications` и импорт `Int32` из `Data.Int`.

## Общие descriptors typed-sql для BE-01–BE-20

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
  let nullable_country_column = Column.nullable_v_exn table "Country" Db_type.text
  let id row = Expr.column row id_column
  let nullable_id row = Expr.nullable_column row id_column
  let first_name row = Expr.column row first_name_column
  let last_name row = Expr.column row last_name_column
  let country row = Expr.column row country_column
  let nullable_country row = Expr.column row nullable_country_column
end

module Invoice = struct
  type row

  let table : row Table.t = Table.v_exn "Invoice"
  let id_column = Column.v_exn table "InvoiceId" Db_type.int
  let customer_id_column = Column.v_exn table "CustomerId" Db_type.int
  let total_column = Column.v_exn table "Total" Db_type.float
  let id row = Expr.column row id_column
  let nullable_id row = Expr.nullable_column row id_column
  let customer_id row = Expr.column row customer_id_column
  let total row = Expr.column row total_column
end

module Invoice_line = struct
  type row

  let table : row Table.t = Table.v_exn "InvoiceLine"
  let id_column = Column.v_exn table "InvoiceLineId" Db_type.int
  let invoice_id_column = Column.v_exn table "InvoiceId" Db_type.int
  let id row = Expr.column row id_column
  let invoice_id row = Expr.column row invoice_id_column
end

module Album = struct
  type row

  let table : row Table.t = Table.v_exn "Album"
  let id_column = Column.v_exn table "AlbumId" Db_type.int
  let title_column = Column.v_exn table "Title" Db_type.text
  let id row = Expr.column row id_column
  let title row = Expr.column row title_column
end

module Invoice_counts = struct
  type row

  let table : row Table.t = Table.v_exn "invoice_counts"
  let customer_id_column = Column.v_exn table "CustomerId" Db_type.int
  let count_column = Column.v_exn table "invoice_count" Db_type.int64
  let customer_id row = Expr.column row customer_id_column
  let count row = Expr.column row count_column
  let projection row = Projection.pair (customer_id row) (count row)
end
```

Общие descriptors используются во всех typed-sql примерах этого файла.

### BE-01. Фильтр и проекция

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
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

#### OCaml (typed-sql)

```ocaml
let beam01 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Customer.table
      |> where (fun customer -> Customer.country customer =$ "USA")
      |> select (fun customer ->
        Projection.pair (Customer.first_name customer) (Customer.last_name customer))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql beam01);;
SELECT
  t0."FirstName",
  t0."LastName"
FROM "Customer" AS t0
WHERE
  (t0."Country" = $1)
```


### BE-02. Составной предикат

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
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

#### OCaml (typed-sql)

```ocaml
let beam02 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Customer.table
      |> where (fun customer ->
        (Customer.first_name customer =~$ "Jo%") &&.
        ((Customer.country customer =$ "USA") ||.
         (Customer.country customer =$ "Canada")))
      |> select (fun customer ->
        Projection.pair (Customer.id customer) (Customer.first_name customer))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql beam02);;
SELECT
  t0."CustomerId",
  t0."FirstName"
FROM "Customer" AS t0
WHERE
  (
    (t0."FirstName" LIKE $1)
    AND (
      (t0."Country" = $2)
      OR (t0."Country" = $3)
    )
  )
```

### BE-03. Сортировка и страница

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
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

#### OCaml (typed-sql)

```ocaml
let beam03 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Album.table
      |> order_by Album.title `Asc
      |> limit 10
      |> offset 20
      |> select (fun album -> Projection.pair (Album.id album) (Album.title album))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql beam03);;
SELECT
  t0."AlbumId",
  t0."Title"
FROM "Album" AS t0
ORDER BY
  t0."Title" ASC
LIMIT 10
OFFSET 20
```


### BE-04. INNER JOIN

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
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

#### OCaml (typed-sql)

```ocaml
let beam04 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Invoice.table
      |> inner_join Invoice_line.table ~on:(fun invoice line ->
        Invoice_line.invoice_id line =. Invoice.id invoice)
      |> select (fun (invoice, line) ->
        Projection.pair (Invoice.id invoice) (Invoice_line.id line))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql beam04);;
SELECT
  t0."InvoiceId",
  t1."InvoiceLineId"
FROM "Invoice" AS t0
INNER JOIN "InvoiceLine" AS t1
  ON (t1."InvoiceId" = t0."InvoiceId")
```


### BE-05. LEFT JOIN с отсутствующей правой строкой

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
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

#### OCaml (typed-sql)

```ocaml
let beam05 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Customer.table
      |> left_join Invoice.table ~on:(fun customer invoice ->
        Invoice.customer_id invoice =. Customer.id customer)
      |> select (fun (customer, invoice) ->
        Projection.pair (Customer.id customer) (Invoice.nullable_id invoice))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql beam05);;
SELECT
  t0."CustomerId",
  t1."InvoiceId"
FROM "Customer" AS t0
LEFT JOIN "Invoice" AS t1
  ON (t1."CustomerId" = t0."CustomerId")
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

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [window functions](https://haskell-beam.github.io/beam/user-guide/queries/window-functions/).
- Проверяет: оконный `RANK` по сумме счета без схлопывания строк; равные суммы получают одинаковый ранг.
- Замечание: оконный `RANK` заменён `1 + COUNT(DISTINCT Total)` для больших сумм; равные суммы получают одинаковый ранг.

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

#### OCaml (typed-sql, коррелированный агрегат)

```ocaml
let be09 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Invoice.table
      |> select (fun invoice ->
        Projection.pair
          (Invoice.id invoice)
          Expr.Int64.(
            Expr.coalesce
              (Expr.scalar_subquery
                 (Query.(
                   from Invoice.table
                   |> where (fun other ->
                     (Invoice.customer_id other =. Invoice.customer_id invoice)
                     &&. (Invoice.total other >. Invoice.total invoice))
                   |> select_scalar (fun other -> Expr.count_distinct (Invoice.total other)))))
              ~default:(Expr.constant Db_type.int64 0L)
            +. Expr.constant Db_type.int64 1L))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql be09);;
SELECT
  t0."InvoiceId",
  (COALESCE((SELECT COUNT(DISTINCT t1."Total") FROM "Invoice" AS t1 WHERE ((t1."CustomerId" = t0."CustomerId") AND (t1."Total" > t0."Total"))), $1) + $2)
FROM "Invoice" AS t0
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

### BE-11. Уникальные страны покупателей со счетами

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [More complex SELECTs](https://haskell-beam.github.io/beam/user-guide/queries/select/), [relationships](https://haskell-beam.github.io/beam/user-guide/queries/relationships/).
- Проверяет: `DISTINCT` после коррелированного `EXISTS`; несколько счетов одного покупателя и несколько покупателей из одной страны дают одну страну.

```sql
SELECT DISTINCT c.Country
FROM Customer AS c
WHERE EXISTS (
  SELECT 1 FROM Invoice AS i WHERE i.CustomerId = c.CustomerId
)
```

```haskell
select $ nub_ $ do
  c <- all_ (customer chinookDb)
  guard_ $ exists_ $ do
    i <- all_ (invoice chinookDb)
    guard_ (invoiceCustomer i ==. primaryKey c)
    pure (invoiceId i)
  pure (customerCountry c)
```

#### OCaml (typed-sql)

```ocaml
let beam11 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Customer.table
      |> where (fun customer ->
        exists
          (from Invoice.table
           |> where (fun invoice ->
             Invoice.customer_id invoice =. Customer.id customer)))
      |> distinct
      |> select (fun customer -> Projection.expr (Customer.country customer))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql beam11);;
SELECT DISTINCT
  t0."Country"
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


### BE-12. Покупатели без счетов из выбранной страны

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Beam tutorial: `NOT EXISTS`](https://haskell-beam.github.io/beam/tutorials/tutorial3/).
- Проверяет: антисоединение через `NOT EXISTS`, включая покупателей без единого счета; фильтр страны остаётся во внешнем запросе.

```sql
SELECT c.CustomerId, c.FirstName
FROM Customer AS c
WHERE c.Country = ?
  AND NOT EXISTS (
    SELECT 1 FROM Invoice AS i WHERE i.CustomerId = c.CustomerId
  )
```

```haskell
select $ do
  c <- all_ (customer chinookDb)
  guard_ (customerCountry c ==. val_ "USA")
  guard_ $ not_ $ exists_ $ do
    i <- all_ (invoice chinookDb)
    guard_ (invoiceCustomer i ==. primaryKey c)
    pure (invoiceId i)
  pure (customerId c, customerFirstName c)
```

#### OCaml (typed-sql)

```ocaml
let beam12 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Customer.table
      |> where (fun customer ->
        (Customer.country customer =$ "USA") &&.
        not_exists
          (from Invoice.table
           |> where (fun invoice ->
             Invoice.customer_id invoice =. Customer.id customer)))
      |> select (fun customer ->
        Projection.pair (Customer.id customer) (Customer.first_name customer))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql beam12);;
SELECT
  t0."CustomerId",
  t0."FirstName"
FROM "Customer" AS t0
WHERE
  (
    (t0."Country" = $1)
    AND (NOT EXISTS (
      SELECT
        1
      FROM "Invoice" AS t1
      WHERE
        (t1."CustomerId" = t0."CustomerId")
    ))
  )
```


### BE-13. Число разных покупателей со счетами по странам

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Aggregates: `COUNT(DISTINCT ...)`](https://haskell-beam.github.io/beam/user-guide/queries/aggregates/).
- Проверяет: `COUNT(DISTINCT CustomerId)` после соединения, чтобы повторные счета не увеличивали число покупателей в стране.

```sql
SELECT c.Country, COUNT(DISTINCT c.CustomerId) AS customer_count
FROM Customer AS c
JOIN Invoice AS i ON i.CustomerId = c.CustomerId
GROUP BY c.Country
```

```haskell
select $
  aggregate_ (\(c, _) ->
    ( group_ (customerCountry c)
    , as_ @Int32 $ countOver_ distinctInGroup_ (customerId c) )) $ do
      c <- all_ (customer chinookDb)
      i <- all_ (invoice chinookDb)
      guard_ (invoiceCustomer i ==. primaryKey c)
      pure (c, i)
```

#### OCaml (typed-sql)

```ocaml
let beam13 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Customer.table
      |> inner_join Invoice.table ~on:(fun customer invoice ->
        Customer.id customer =. Invoice.customer_id invoice)
      |> group_by (fun (customer, _) -> Customer.country customer)
      |> select (fun (customer, _) ->
        Projection.map2
          ~f:(fun country customer_count -> country, customer_count)
          (Projection.expr (Customer.country customer))
          (Projection.expr (Expr.count_distinct (Customer.id customer))))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql beam13);;
SELECT
  t0."Country",
  COUNT(DISTINCT t0."CustomerId")
FROM "Customer" AS t0
INNER JOIN "Invoice" AS t1
  ON (t0."CustomerId" = t1."CustomerId")
GROUP BY
  t0."Country"
```


### BE-14. Повторное использование агрегата через CTE

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Common table expressions](https://haskell-beam.github.io/beam/user-guide/queries/common-table-expressions/).
- Проверяет: `selectWith` и `reuse` для агрегата, соединение CTE с покупателями и внешний фильтр по рассчитанному числу счетов.

```sql
WITH invoice_counts AS (
  SELECT CustomerId, COUNT(*) AS invoice_count
  FROM Invoice
  GROUP BY CustomerId
)
SELECT c.CustomerId, ic.invoice_count
FROM Customer AS c
JOIN invoice_counts AS ic ON ic.CustomerId = c.CustomerId
WHERE ic.invoice_count >= 3
```

```haskell
selectWith $ do
  invoiceCounts <- selecting $
    aggregate_ (\i ->
      ( group_ (invoiceCustomer i)
      , as_ @Int32 countAll_ )) $
        all_ (invoice chinookDb)
  pure $ do
    (customerKey, invoiceCount) <- reuse invoiceCounts
    c <- all_ (customer chinookDb)
    guard_ (customerKey ==. primaryKey c)
    guard_ (invoiceCount >=. 3)
    pure (customerId c, invoiceCount)
```

#### OCaml (typed-sql)

```ocaml
let beam14_counts_relation =
  Derived_table.create
    ~table:Invoice_counts.table
    ~columns:Invoice_counts.projection
    Query.(
      from Invoice.table
      |> group_by Invoice.customer_id
      |> select (fun invoice ->
        Projection.pair (Invoice.customer_id invoice) Expr.count_all))

let beam14 =
  Statement.Portable.query_many_exn (fun _ ->
    Cte.with_result (Cte.select beam14_counts_relation) ~f:(fun invoice_counts ->
      Query.(
        from Customer.table
        |> inner_join_cte invoice_counts ~on:(fun customer counts ->
          Customer.id customer =. Invoice_counts.customer_id counts)
        |> where (fun (_, counts) -> Invoice_counts.count counts >=. 3L)
        |> select (fun (customer, counts) ->
          Projection.pair (Customer.id customer) (Invoice_counts.count counts)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql beam14);;
WITH
  "c0" (
    "CustomerId",
    "invoice_count"
  ) AS (
    SELECT
      t0."CustomerId",
      COUNT(*)
    FROM "Invoice" AS t0
    GROUP BY
      t0."CustomerId"
  )
SELECT
  t0."CustomerId",
  t1."invoice_count"
FROM "Customer" AS t0
INNER JOIN "c0" AS t1
  ON (t0."CustomerId" = t1."CustomerId")
WHERE
  (t1."invoice_count" >= $1)
```


### BE-15. Три покупателя с наибольшей суммой счетов

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [Aggregates](https://haskell-beam.github.io/beam/user-guide/queries/aggregates/), [ordering and limit](https://haskell-beam.github.io/beam/user-guide/queries/ordering/).
- Проверяет: порядок `GROUP BY`, сортировки по агрегату и `LIMIT`; для граничной строки нужна фикстура без равенства сумм.

```sql
SELECT i.CustomerId, COALESCE(SUM(i.Total), 0) AS total_spent
FROM Invoice AS i
GROUP BY i.CustomerId
ORDER BY total_spent DESC
LIMIT 3
```

```haskell
select $
  limit_ 3 $
  orderBy_ (\(_, totalSpent) -> desc_ totalSpent) $
  aggregate_ (\i ->
    ( group_ (invoiceCustomer i)
    , fromMaybe_ 0 (sum_ (invoiceTotal i)) )) $
      all_ (invoice chinookDb)
```

#### OCaml (typed-sql)

`Total` объявлен как `float`; для фикстуры без равных итогов сумма определяет тот же порядок покупателей.

```ocaml
let beam15 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Invoice.table
      |> group_by Invoice.customer_id
      |> order_by (fun invoice ->
        Expr.coalesce (Expr.sum_float (Invoice.total invoice))
          ~default:(Expr.constant Db_type.float 0.)) `Desc
      |> limit 3
      |> select (fun invoice ->
        Projection.pair
          (Invoice.customer_id invoice)
          (Expr.coalesce (Expr.sum_float (Invoice.total invoice))
             ~default:(Expr.constant Db_type.float 0.)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql beam15);;
SELECT
  t0."CustomerId",
  COALESCE(SUM(t0."Total"), $1)
FROM "Invoice" AS t0
GROUP BY
  t0."CustomerId"
ORDER BY
  COALESCE(SUM(t0."Total"), $2) DESC
LIMIT 3
```


## Уведомление о лицензии

The MIT License (MIT)

Copyright (c) 2015-2018 Travis Athougies and the Beam Authors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


### BE-16. Счётчик счетов с сохранением клиентов без счетов

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [relationships and aggregation](https://haskell-beam.github.io/beam/user-guide/queries/relationships/).
- Проверяет: `LEFT JOIN`, группировку и `COUNT` только существующих счетов.

```sql
SELECT Customer.CustomerId, COUNT(Invoice.InvoiceId)
FROM Customer LEFT JOIN Invoice ON Invoice.CustomerId = Customer.CustomerId
GROUP BY Customer.CustomerId
```

#### OCaml (typed-sql)

```ocaml
let beam16 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Customer.table
      |> left_join Invoice.table ~on:(fun customer invoice -> Customer.id customer =. Invoice.customer_id invoice)
      |> group_by (fun (customer, _invoice) -> Customer.id customer)
      |> select (fun (customer, invoice) -> Projection.pair (Customer.id customer) (Expr.count (Invoice.nullable_id invoice)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql beam16);;
SELECT
  t0."CustomerId",
  COUNT(t1."InvoiceId")
FROM "Customer" AS t0
LEFT JOIN "Invoice" AS t1
  ON (t0."CustomerId" = t1."CustomerId")
GROUP BY
  t0."CustomerId"
```

### BE-17. Максимальная сумма счёта для каждого клиента

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [scalar queries](https://haskell-beam.github.io/beam/user-guide/queries/basic/).
- Проверяет: коррелированный scalar subquery и nullable результат для клиента без счетов.

```sql
SELECT Customer.CustomerId,
       (SELECT MAX(Invoice.Total) FROM Invoice WHERE Invoice.CustomerId = Customer.CustomerId)
FROM Customer
```

#### OCaml (typed-sql)

```ocaml
let beam17 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Customer.table
      |> select (fun customer ->
        Projection.pair
          (Customer.id customer)
          (Expr.scalar_subquery
             (Query.(
               from Invoice.table
               |> where (fun invoice -> Invoice.customer_id invoice =. Customer.id customer)
               |> select_scalar (fun invoice -> Expr.max Db_type.Orderable.float (Invoice.total invoice)))))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql beam17);;
SELECT
  t0."CustomerId",
  (SELECT MAX(t1."Total") FROM "Invoice" AS t1 WHERE (t1."CustomerId" = t0."CustomerId"))
FROM "Customer" AS t0
```

### BE-18. Два необязательных фильтра

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [conditional filtering](https://haskell-beam.github.io/beam/user-guide/queries/basic/).
- Проверяет: независимое включение условия по стране и началу имени.

```sql
SELECT CustomerId, FirstName, Country FROM Customer
WHERE Country = ? AND FirstName LIKE ?
```

#### OCaml (typed-sql)

```ocaml
let beam18 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Customer.table
      |> where_opt (Some "USA") ~f:(fun customer country -> Customer.country customer =$ country)
      |> where_opt (Some "A%") ~f:(fun customer pattern -> Customer.first_name customer =~$ pattern)
      |> select (fun customer -> Projection.map3 ~f:(fun id name country -> id, name, country) (Projection.expr (Customer.id customer)) (Projection.expr (Customer.first_name customer)) (Projection.expr (Customer.country customer)))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql beam18);;
SELECT
  t0."CustomerId",
  t0."FirstName",
  t0."Country"
FROM "Customer" AS t0
WHERE
  ((t0."Country" = $1) AND (t0."FirstName" LIKE $2))
```

### BE-19. Страны с более чем одной покупкой

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [grouping and aggregate filters](https://haskell-beam.github.io/beam/user-guide/queries/basic/).
- Проверяет: JOIN по клиенту, группировку по стране и `HAVING COUNT(*)`.

```sql
SELECT Customer.Country, COUNT(*)
FROM Customer JOIN Invoice ON Invoice.CustomerId = Customer.CustomerId
GROUP BY Customer.Country HAVING COUNT(*) > 1
```

#### OCaml (typed-sql)

```ocaml
let beam19 =
  Statement.Portable.query_many_exn (fun _ ->
    Query.(
      from Customer.table
      |> inner_join Invoice.table ~on:(fun customer invoice -> Customer.id customer =. Invoice.customer_id invoice)
      |> group_by (fun (customer, _invoice) -> Customer.country customer)
      |> having (fun _ -> Expr.count_all >$ 1L)
      |> order_by (fun (customer, _invoice) -> Customer.country customer) `Asc
      |> select (fun (customer, _invoice) -> Projection.pair (Customer.country customer) Expr.count_all)))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql beam19);;
SELECT
  t0."Country",
  COUNT(*)
FROM "Customer" AS t0
INNER JOIN "Invoice" AS t1
  ON (t0."CustomerId" = t1."CustomerId")
GROUP BY
  t0."Country"
HAVING
  (COUNT(*) > $1)
ORDER BY
  t0."Country" ASC
```

### BE-20. Массовое обновление счёта с возвратом ключей

- OCaml-пример: ✓
- Реализуемость: ✓
- Семантика: ✓
- Без доработок typed-sql: ✓
- Источник: [UPDATE statements](https://haskell-beam.github.io/beam/user-guide/manipulation/update/).
- Проверяет: условный UPDATE и получение ID изменённых строк.

```sql
UPDATE Invoice SET Total = 0 WHERE Total < 1 RETURNING InvoiceId
```

#### OCaml (typed-sql)

```ocaml
let beam20 =
  Statement.Portable.query_many_exn (fun _ ->
    Update.(
      table Invoice.table
      |> set Invoice.total_column 0.0
      |> where (fun invoice -> Invoice.total invoice <$ 1.0)
      |> returning (fun invoice -> Projection.expr (Invoice.id invoice))))
```

#### SQL typed-sql (PostgreSQL)

```ocaml
# let () = Stdlib.print_endline (Statement.sql_exn ~dialect:Dialect.Postgresql beam20);;
UPDATE "Invoice"
SET "Total" = $1
WHERE
  ("Total" < $2)
RETURNING
  "InvoiceId"
```
