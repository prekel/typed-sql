Я бы строил это не как «ORM для OCaml», а как **typed relational query DSL**: по философии ближе к jOOQ, с deferred execution из EF, некоторыми type-system идеями Sequoia и Caqti как нижним execution/driver layer.

Целевая картинка:

```text
                    ┌────────────────────────────┐
                    │ Generated schema           │
                    │ Cpe.table / Cpe.id / ...   │
                    └──────────────┬─────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────┐
│                     Typed Query DSL                         │
│                                                             │
│ Db_type<'a>                                                 │
│ Column<'row,'a> → Expr<'a> → Condition                      │
│                         ↓                                   │
│ Table → Select / Join / Group / Insert / Update / Delete    │
│                         ↓                                   │
│                   Projection<'a>                            │
│                         ↓                                   │
│                     Query<'a>                               │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
                 dialect-independent AST
                            │
                   normalize / validate
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
      PostgreSQL lowering            SQLite lowering
              │                           │
              └─────────────┬─────────────┘
                            ▼
                     Caqti request
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
          PostgreSQL                    SQLite
```

И принципиально я бы **не делал EF-клон**. EF хорош как источник идей про `IQueryable`, deferred execution и query-shape cache. jOOQ гораздо лучше подходит как основная модель SQL DSL. Sequoia показывает, какие гарантии реально можно вытянуть из type system OCaml. Caqti уже решает низкоуровневую portability между PostgreSQL/SQLite и типизированное выполнение запросов. Caqti сам прямо позиционирует себя как возможную основу для более высокоуровневых query builders/code generators. ([GitHub][1])

---

# 1. Что именно заимствовать откуда

| Источник                | Что брать                                                                                                                  | Что **не** брать                                                               |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| **jOOQ**                | `Field<T>`, `Table`, typed projections, schema codegen, QueryPart AST, bind values, dialect lowering, SQL-first philosophy | Java `*Step`-иерархию и её многословность                                      |
| **EF Core**             | deferred execution, composable query object, query shape vs parameter values, compiled-query cache                         | change tracking, navigation magic, LINQ-expression translation всей программы  |
| **Sequoia**             | типобезопасность выражений, source membership, FK metadata, идея спрятать type-level механику через PPX                    | публичные `There / Skip`, запрет arbitrary JOIN conditions, архитектурные хаки |
| **Caqti**               | execution, Lwt, PostgreSQL + SQLite drivers, typed encoding/decoding, prepared request lifecycle, dialect info             | SQL builder — Caqti специально этим не занимается                              |
| **обычные компиляторы** | typed frontend → IR → normalization → dialect lowering → rendering                                                         | смешивание AST и SQL-string building                                           |

jOOQ сам описывает SQL DSL как type-safe AST, причём code generation связывает API с реальной схемой БД; `QueryPart` является общей composable единицей, отвечающей за rendering/binding. ([jOOQ][2])

Sequoia уже доказывает, что в OCaml можно типами запрещать несовместимые выражения и обращения к таблицам, которых нет в `FROM/JOIN`. Но для этого она приходит к `There`, `Skip There` и т. п., а PPX затем скрывает этот boilerplate. Она также намеренно разрешает JOIN только через заранее объявленные FK; README прямо перечисляет отсутствие arbitrary join expressions как ограничение. ([GitHub][3])

---

# 2. Сначала зафиксировать scope проекта

Для первой нормальной версии я бы **не пытался реализовать весь SQL**.

Нужен такой portable core:

```text
SELECT
FROM
INNER / LEFT JOIN
WHERE
ORDER BY
LIMIT / OFFSET

INSERT
UPDATE
DELETE

RETURNING

AND / OR / NOT
= <> < <= > >=
IS NULL
IN
LIKE

COUNT / SUM / AVG / MIN / MAX
GROUP BY
HAVING

subquery
EXISTS
```

И отдельно PostgreSQL extensions:

```text
ILIKE
DISTINCT ON
ON CONFLICT
JSONB
ARRAY
ANY / ALL
INET / CIDR
range
PG enums
DML in CTE
...
```

SQLite extensions аналогично живут отдельно.

**Не делать в первой версии:**

* entity tracking;
* lazy loading;
* unit-of-work ORM;
* migrations;
* relationships уровня `cpe.user.name`;
* LINQ-подобную трансляцию произвольных OCaml-функций;
* PPX quotations.

Это всё можно добавить потом. Сначала должен получиться хороший **typed jOOQ for OCaml**.

---

# 3. Базовый слой: `Db_type<'a>`

Это надо сделать **раньше AST**.

Не:

```ocaml
type param =
  | Int of int
  | String of string
  | Bool of bool
```

а:

```ocaml
module Db_type : sig
  type 'a t

  val int : int t
  val int64 : int64 t
  val float : float t
  val text : string t
  val bool : bool t
  val bytes : bytes t

  val option : 'a t -> 'a option t

  val map
    :  encode:('b -> 'a)
    -> decode:('a -> ('b, string) Result.t)
    -> 'a t
    -> 'b t
end
```

Например:

```ocaml
let cpe_type =
  Db_type.map
    Db_type.text
    ~encode:Cpe_type.to_string
    ~decode:Cpe_type.of_string
```

Тогда:

```ocaml
Cpe.typ : Cpe.row_ref -> Cpe_type.t Expr.t
```

а не `string Expr.t`.

Это jOOQ-like идея `DataType<T>` + converters, только в OCaml она получается естественнее благодаря параметрическим типам. jOOQ тоже отделяет database representation от пользовательского типа через converters. ([jOOQ][4])

Внутри понадобится existential:

```ocaml
type packed_value =
  | Value : 'a Db_type.t * 'a -> packed_value
```

Для динамического набора параметров.

---

# 4. Typed `Column` и `Expr`

Следующий фундамент:

```ocaml
module Column : sig
  type ('row, 'a) t
end

module Expr : sig
  type 'a t

  val param : 'a Db_type.t -> 'a -> 'a t

  val eq : 'a t -> 'a t -> Condition.t
  val neq : 'a t -> 'a t -> Condition.t

  val lt : 'a Comparable.t -> 'a t -> 'a t -> Condition.t
  ...
end
```

Но публично хочется jOOQ-like удобство:

```ocaml
Cpe.id c =: id
Cpe.typ c =: `Router
Cpe.name c |> like: "%foo%"
```

То есть сделать две формы:

```ocaml
val eq : 'a Expr.t -> 'a Expr.t -> Condition.t

val eq_value : 'a Expr.t -> 'a -> Condition.t
```

`eq_value lhs x` берёт `Db_type` самого `lhs` и автоматически делает bind parameter.

Тогда:

```ocaml
Cpe.typ c =: typ
```

строит AST:

```text
Eq
├── Column(cpe.typ)
└── Bind(Cpe_type.db_type, typ)
```

а не вставляет значение в SQL.

jOOQ работает по той же идее: значение в `BOOK.ID.eq(5)` концептуально становится bind-value expression, а numbering параметров DSL ведёт сам. ([jOOQ][5])

---

# 5. `Condition` лучше отделить от `bool Expr.t`

Я бы сделал:

```ocaml
type Condition.t
```

вместо:

```ocaml
bool Expr.t
```

Причина — SQL boolean logic не полностью совпадает с OCaml `bool`, особенно с NULL.

Например:

```ocaml
Expr.eq :
  'a Expr.t ->
  'a Expr.t ->
  Condition.t
```

а:

```ocaml
Condition.and_
Condition.or_
Condition.not_
```

Отдельно:

```ocaml
Expr.is_null :
  'a option Expr.t ->
  Condition.t
```

Это также удобно для dynamic filters:

```ocaml
Condition.all : Condition.t list -> Condition.t
Condition.any : Condition.t list -> Condition.t
```

---

# 6. Не хранить SQL alias прямо в поле

Раньше мы рассматривали:

```ocaml
{ alias = "c1"; name = "name" }
```

Для серьёзной библиотеки я бы так **не делал**.

Вместо этого:

```ocaml
type source_id = int

type 'row table_ref =
  { source : source_id
  ; table : 'row Table.t
  }
```

AST колонки:

```text
Column {
  source = #4;
  column = Cpe.name;
}
```

А renderer сам назначает:

```text
#4 → t0
#7 → t1
```

и выдаёт:

```sql
t0.name
```

Это важно для:

* self-join;
* composing queries;
* subqueries;
* deterministic SQL;
* query cache;
* alpha-renaming.

Alias — **деталь rendering**, а не semantic AST.

У jOOQ render context тоже занимается состоянием rendering, включая alias generation и bind index. ([jOOQ][6])

---

# 7. Table descriptors

Сначала таблицы можно объявлять вручную:

```ocaml
module Cpe = struct
  type row

  let table =
    Table.v "cpes"

  let id_col =
    Column.v table "id" Db_type.int64

  let name_col =
    Column.v table "name" Db_type.text

  let type_col =
    Column.v table "type" Cpe_type.db_type

  let id r =
    Expr.column r id_col

  let name r =
    Expr.column r name_col

  let typ r =
    Expr.column r type_col
end
```

`Column` должен быть связан с конкретным phantom `'row`:

```ocaml
('row, 'a) Column.t
```

Это автоматически запрещает что-то вроде:

```ocaml
Expr.column user_ref Cpe.id_col
```

потому что `User.row <> Cpe.row`.

---

# 8. `Projection<'a>` — одна из самых важных частей

Не привязывай `Query.t` к entity.

Запрос:

```sql
SELECT id
```

должен иметь тип:

```ocaml
int64 Query.t
```

а:

```sql
SELECT id, name
```

например:

```ocaml
(int64 * string) Query.t
```

Для этого:

```ocaml
module Projection : sig
  type 'a t

  val expr : 'a Expr.t -> 'a t

  val map :
    ('a -> 'b) ->
    'a t ->
    'b t

  val map2 :
    ('a -> 'b -> 'c) ->
    'a t ->
    'b t ->
    'c t

  val map3 : ...
end
```

Например codegen создаёт:

```ocaml
let projection c =
  Projection.map3
    (fun id name typ ->
       { Cpe.id; name; typ })
    (Projection.expr (id c))
    (Projection.expr (name c))
    (Projection.expr (typ c))
```

И:

```ocaml
Cpe.projection c : Cpe.t Projection.t
```

`Projection` одновременно описывает:

1. выражения в `SELECT`;
2. их порядок;
3. типы колонок;
4. decoder результата.

Это OCaml-версия jOOQ `Record<T...>`, но без `Record1 ... Record22`.

---

# 9. Центральный аналог `IQueryable`

Вот здесь берём основную идею из EF.

Я бы сделал:

```ocaml
type ('ctx, 'result) Query.t
```

где:

* `'ctx` — доступные table references;
* `'result` — тип результата.

Например:

```ocaml
Cpe.query ()
```

имеет:

```ocaml
(Cpe.row Table_ref.t, Cpe.t) Query.t
```

Сам объект просто содержит AST.

Никакой БД.

Никакого Lwt.

Никакого исполнения.

Это ровно та полезная часть модели EF: LINQ operators строят in-memory representation, а фактический запрос выполняется только при materialization (`ToList`, `Single`, и т.п.). ([Microsoft Learn][7])

API:

```ocaml
val where :
  ('ctx -> Condition.t) ->
  ('ctx, 'a) Query.t ->
  ('ctx, 'a) Query.t

val select :
  ('ctx -> 'b Projection.t) ->
  ('ctx, 'a) Query.t ->
  ('ctx, 'b) Query.t

val order_by :
  ('ctx -> 'a Expr.t) ->
  direction ->
  ('ctx, 'r) Query.t ->
  ('ctx, 'r) Query.t

val limit :
  int ->
  ('ctx, 'a) Query.t ->
  ('ctx, 'a) Query.t
```

Тогда:

```ocaml
Cpe.query ()
|> Query.where (fun c ->
     Cpe.typ c =: `Router)
|> Query.order_by (fun c ->
     Cpe.name c)
     `Asc
|> Query.limit 100
```

всё ещё просто **значение**.

---

# 10. Dynamic filters должны быть естественной операцией

Специальный:

```ocaml
val where_opt
  :  'p option
  -> f:('ctx -> 'p -> Condition.t)
  -> ('ctx, 'a) Query.t
  -> ('ctx, 'a) Query.t
```

И твой CPE:

```ocaml
let list ?name ?typ () =
  Cpe.query ()
  |> Query.where_opt name
       ~f:(fun c name ->
         Cpe.name c |> Expr.ilike_value ("%" ^ name ^ "%"))
  |> Query.where_opt typ
       ~f:(fun c typ ->
         Cpe.typ c =: typ)
```

Теперь:

```ocaml
CpeRepo.list ~name ()
```

возвращает запрос.

Следующий слой может ещё добавить:

```ocaml
CpeRepo.list ~name ()
|> Query.where (fun c ->
     Cpe.deleted c =: false)
|> Query.limit 20
```

И лишь потом:

```ocaml
Db.fetch ~conn q
```

Это именно та семантика `IQueryable`, которая тебе нужна.

---

# 11. JOIN: взять лучшее одновременно из jOOQ и Sequoia

Не повторять ограничение Sequoia «JOIN только по FK».

Нужен general join:

```ocaml
val inner_join
  :  'r Table.t
  -> on:('ctx -> 'r Table_ref.t -> Condition.t)
  -> ('ctx, 'a) Query.t
  -> ('ctx * 'r Table_ref.t, 'a) Query.t
```

Использование:

```ocaml
Cpe.query ()
|> Query.inner_join Site.table
     ~on:(fun c s ->
       Cpe.site_id c =. Site.id s)
```

После него context:

```ocaml
Cpe.ref * Site.ref
```

и:

```ocaml
|> Query.where (fun (c, s) ->
     Site.name s =: "Moscow")
```

Но одновременно стоит генерировать FK metadata:

```ocaml
Cpe.site :
  (Cpe.row, Site.row) Foreign_key.t
```

чтобы иметь sugar:

```ocaml
|> Query.join_fk Cpe.site
```

То есть:

* arbitrary joins — **jOOQ/SQL**;
* checked FK convenience — **Sequoia**.

Sequoia хорошо показывает ценность typed FK metadata, но её запрет произвольного `ON` я бы сознательно не повторял. ([GitHub][3])

---

# 12. Scope safety: делать в два этапа

Здесь OCaml становится интересным.

## V1

`Table_ref.t` создаётся только Query builder'ом.

Конструктор скрыт:

```ocaml
type 'row Table_ref.t
```

И внутри expression сохраняется `source_id`.

При compile:

```text
validate:
  every Column(source_id, ...)
  must reference a source visible
  at this point
```

Таким образом странное использование ref другого запроса ловится как library error.

В обычном API такое почти невозможно случайно сделать, потому что refs пользователь получает через callbacks:

```ocaml
fun c -> ...
fun (c,s) -> ...
```

## V2

Если захочется **абсолютной compile-time гарантии**, уже потом можно взять механизм Sequoia:

```text
source-list witness
There
Skip There
Skip (Skip There)
...
```

но держать его **только внутри библиотеки/PPX**.

Пользователь никогда не должен видеть:

```ocaml
field User.name (Skip (Skip There))
```

PPX может подставлять witnesses автоматически — собственно Sequoia уже показывает жизнеспособность именно этого подхода. ([GitHub][3])

---

# 13. Внутренний AST лучше сделать почти нетипизированным

Это может показаться странным, но я бы **не тащил GADT через весь compiler**.

Публично:

```ocaml
'a Expr.t
'a Projection.t
('ctx, 'a) Query.t
```

А внутри:

```ocaml
type expr =
  | Column of source_id * column_id
  | Param of packed_value
  | Eq of expr * expr
  | And of expr * expr
  | Like of expr * expr
  | Function of function_id * expr list
  | ...
```

Публичный `'a Expr.t`:

```ocaml
type 'a Expr.t =
  private
  { node : Ast.expr
  ; typ : 'a Db_type.t
  }
```

То есть type checking происходит **при построении**:

```ocaml
Expr.eq :
  'a Expr.t ->
  'a Expr.t ->
  Condition.t
```

После этого AST можно type-erase.

Это резко упрощает:

* visitor;
* normalizer;
* dialect lowering;
* debug printer;
* hashing;
* rewriting.

Именно такую границу я считаю оптимальной для OCaml.

---

# 14. AST должен быть immutable и composable

Структура примерно:

```ocaml
type select =
  { from : source
  ; joins : join list
  ; where : condition option
  ; group_by : expr list
  ; having : condition option
  ; projection : expr list
  ; order_by : order list
  ; limit : expr option
  ; offset : expr option
  }
```

Все:

```ocaml
Query.where
Query.join
Query.limit
```

возвращают новое значение.

Это сильно проще модели mutable query builder.

jOOQ-подобную идею `QueryPart` стоит взять как архитектурную: AST состоит из composable SQL fragments, а единый context занимается rendering и bind state. ([jOOQ][2])

---

# 15. SELECT и RETURNING должны использовать один `Projection`

Это один из самых сильных архитектурных моментов.

Если есть:

```ocaml
Cpe.projection : Cpe.ref -> Cpe.t Projection.t
```

она должна работать и здесь:

```ocaml
Query.select Cpe.projection
```

и здесь:

```ocaml
Insert.returning Cpe.projection
```

и:

```ocaml
Update.returning Cpe.projection
```

и:

```ocaml
Delete.returning Cpe.projection
```

PostgreSQL в `UPDATE ... RETURNING` использует output list той же природы, что и `SELECT` output list. ([PostgreSQL][8])

---

# 16. DML API

### INSERT

```ocaml
Cpe.insert ()
|> Insert.set Cpe.name "router-1"
|> Insert.set Cpe.typ `Router
```

до `RETURNING` это:

```ocaml
Cpe.row Insert.t
```

После:

```ocaml
|> Insert.returning Cpe.projection
```

получаем:

```ocaml
Cpe.t Result_query.t
```

Исполнение:

```ocaml
Db.fetch_one ~conn
```

### UPDATE

```ocaml
Cpe.update ()
|> Update.set Cpe.name "router-2"
|> Update.where (fun c ->
     Cpe.id c =: id)
|> Update.returning Cpe.projection
|> Db.fetch_one ~conn
```

### DELETE

```ocaml
Cpe.delete ()
|> Delete.where (fun c ->
     Cpe.id c =: id)
|> Delete.returning (fun c ->
     Projection.expr (Cpe.id c))
|> Db.fetch
```

Без `returning`:

```ocaml
Db.execute :
  Command.t ->
  affected_count Lwt.t
```

С `RETURNING`:

```ocaml
Db.fetch :
  'a Result_query.t ->
  'a list Lwt.t
```

---

# 17. INSERT required columns — не надо пытаться решить GADT'ами сразу

Можно теоретически закодировать state:

```text
missing-name
missing-type
...
```

и разрешить `execute` только когда заполнены все обязательные columns.

Я бы этого **не делал**.

Лучше codegen генерирует typed insert input:

```ocaml
module Cpe.Insert_input : sig
  type t

  val v
    :  name:string
    -> typ:Cpe_type.t
    -> ?description:string
    -> unit
    -> t
end
```

и:

```ocaml
Cpe.insert (Cpe.Insert_input.v ...)
```

Это намного проще.

---

# 18. GROUP BY делать только после SELECT/JOIN/DML

Вот здесь type system быстро усложняется.

Для первой версии:

```ocaml
Query.group_by :
  ('ctx -> 'a Projection.t) ->
  ('ctx,'r) Query.t ->
  ...
```

и AST validator проверяет:

> SELECT expression после GROUP BY либо group key, либо aggregate expression.

Следующим этапом уже можно ввести:

```ocaml
'a Aggregate.t
```

и:

```ocaml
Aggregate.count
Aggregate.sum
Aggregate.avg
Aggregate.key
```

чтобы:

```ocaml
Grouped.select
```

вообще не принимал обычный row expression.

Не стоит начинать разработку именно отсюда.

---

# 19. Multi-database: semantic AST → dialect lowering

Это основная модель jOOQ для нескольких SQL dialects: один DSL, а rendering зависит от `SQLDialect`; часть операций универсальна, часть поддерживается лишь некоторыми dialects. ([jOOQ][9])

У тебя:

```ocaml
module Dialect : sig
  type t =
    | PostgreSQL
    | SQLite
end
```

Но renderer лучше разбить:

```text
AST
 ↓
Validate
 ↓
Lower(Dialect)
 ↓
Rendered SQL IR
 ↓
Caqti.Template.Query
```

Например semantic AST:

```text
Case_insensitive_like(name, param)
```

Postgres lowering:

```sql
name ILIKE $1
```

SQLite lowering потенциально:

```sql
lower(name) LIKE lower(?1)
```

Если семантики нельзя корректно воспроизвести, надо:

```ocaml
Error (`Unsupported_feature ...)
```

а не генерировать что-то «примерно такое же».

jOOQ тоже отдельно фиксирует unsupported dialect cases вместо притворства, что любой SQL syntax переносим. ([jOOQ][10])

---

# 20. Portable и vendor-specific API лучше разделить namespace'ами

Например:

```ocaml
Sql.Expr
Sql.Query
Sql.Insert
```

portable.

А:

```ocaml
Postgres.Expr.ilike
Postgres.Expr.jsonb_get
Postgres.Expr.array_contains
Postgres.distinct_on
Postgres.on_conflict
```

специфично PG.

То есть пользователь видит прямо в исходнике:

```ocaml
Postgres.Jsonb.contains ...
```

и понимает:

> этот repository не portable.

Это гораздо лучше хитрой phantom capability lattice в v1.

---

# 21. `RETURNING`: общий feature, но с capability validation

Современный SQLite поддерживает `RETURNING` у top-level `INSERT`, `UPDATE`, `DELETE`, поэтому эту операцию вполне можно положить в portable DSL. Но SQLite не позволяет использовать такой DML+RETURNING как subquery/CTE source, в отличие от PostgreSQL. ([SQLite][11])

Следовательно:

```ocaml
Insert.returning
Update.returning
Delete.returning
```

— portable.

А:

```text
WITH deleted AS (
  DELETE ...
  RETURNING ...
)
SELECT ...
```

— PG-only.

Именно так должен выглядеть capability layer.

---

# 22. Caqti стоит использовать ниже query compiler

Здесь у тебя очень удачно совпадают задачи.

Caqti уже:

* работает с PostgreSQL;
* работает с SQLite;
* даёт Lwt;
* содержит type descriptors для parameters/results;
* предоставляет dialect info;
* умеет driver-independent parameter syntax;
* управляет prepared queries. ([GitHub][1])

То есть:

```text
твоя библиотека
    ↓
Caqti
    ↓
Postgres / SQLite
```

а не:

```text
твоя библиотека
 ├── libpq вручную
 └── sqlite3 вручную
```

---

# 23. Причём Caqti 3 особенно хорошо ложится сюда

У нынешнего Caqti 3 `Template.Request.create` принимает функцию:

```text
Dialect.t -> Template.Query.t
```

то есть request **сам может генерировать SQL по dialect текущего connection**. Также у него есть prepare policies `Direct`, `Dynamic`, `Static`, а dialect-specific query generator внутри memoized небольшим LRU. ([OCaml][12])

Это почти идеально для твоего слоя.

Примерно:

```ocaml
let to_caqti_request query =
  Caqti.Template.Request.create
    `Dynamic
    request_type
    (fun dialect ->
       query
       |> Compiler.compile dialect
       |> Compiler.to_caqti_query)
```

Тогда connection сам определит:

```text
PostgreSQL
```

или:

```text
SQLite
```

---

# 24. Caqti dynamic params уже показывает нужный existential pattern

Для dynamically generated SQL число и типы параметров тоже динамичны.

Документация Caqti прямо показывает паттерн:

```ocaml
type t =
  | Pack : 'a Caqti_type.t * 'a -> t
```

с постепенным построением параметрического product type. ([OCaml][13])

То есть наш:

```ocaml
packed_value list
```

на adapter boundary превращается в Caqti typed parameter bundle.

Не надо изобретать unsafe `Obj.t`.

---

# 25. Codegen — после работающего ручного API

Сначала:

```ocaml
Column.v
Table.v
```

руками.

После стабилизации API сделать:

```text
sqlgen
```

который introspect'ит схему и генерирует:

```text
cpe_table.ml
cpe_table.mli
site_table.ml
...
```

Вдохновение прямо jOOQ: его code generator reverse-engineer'ит database schema в typed tables/records/relations, а изменение схемы затем приводит к compile errors в использующем её Java-коде. ([jOOQ][4])

Генерировать надо:

```ocaml
module Cpe : sig
  type row

  val table : row Table.t

  val id_col :
    (row, Cpe_id.t) Column.t

  val name_col :
    (row, string) Column.t

  val typ_col :
    (row, Cpe_type.t) Column.t

  val id :
    row Table_ref.t -> Cpe_id.t Expr.t

  val name :
    row Table_ref.t -> string Expr.t

  val typ :
    row Table_ref.t -> Cpe_type.t Expr.t

  val projection :
    row Table_ref.t -> Cpe.t Projection.t
end
```

Плюс:

```text
PK
FK
UNIQUE
nullable
default
generated
identity
```

metadata.

---

# 26. Отдельный dialect-neutral `Schema_ir`

Чтобы codegen тоже не зависел напрямую от PG:

```ocaml
type schema =
  { tables : table list
  ; enums : ...
  }

type column =
  { name : string
  ; logical_type : logical_type
  ; nullable : bool
  ; default : ...
  }
```

Тогда:

```text
Postgres introspector ──┐
                       ├→ Schema_ir → OCaml generator
SQLite introspector  ───┘
```

А позже этот же IR можно использовать для migrations/schema validation.

---

# 27. Dynamic filtering по произвольному полю

После фиксированных:

```text
?name=
?type=
```

можно добавить fully dynamic API:

```text
?filter=name:eq:foo
?filter=type:eq:router
```

Типобезопасность сохраняется existential'ом:

```ocaml
type 'row filterable =
  | Filterable :
      { expr : 'row Table_ref.t -> 'a Expr.t
      ; typ : 'a Db_type.t
      ; ops : 'a Filter_op.t list
      }
      -> 'row filterable
```

Generated registry:

```ocaml
Cpe.Filters.name
Cpe.Filters.typ
```

После lookup строки `"name"` получаем packed typed descriptor, парсим input через соответствующий `Db_type`, а потом строим normal typed condition.

То есть пользовательская строка **никогда не становится SQL identifier напрямую**.

---

# 28. Endpoint DSL и SQL DSL держать раздельно

Твой:

```ocaml
D.query
D.param
D.Request
D.Response
```

я бы **не связывал напрямую с SQL library**.

HTTP отвечает за:

```text
string query parameter
       ↓
validated OCaml value
```

Repository отвечает:

```text
OCaml value
       ↓
typed Condition
```

И handler:

```ocaml
@@ fun _req name typ () ->
  let q =
    CpeRepo.list ()
    |> Query.where_opt name
         ~f:(fun c name ->
           Cpe.name c |> Expr.ilike_value ("%" ^ name ^ "%"))
    |> Query.where_opt typ
         ~f:(fun c typ ->
           Cpe.typ c =: typ)
    |> Query.limit 100
  in
  Db.with_transaction @@ fun conn ->
    Db.fetch ~conn q
```

Либо repository сам принимает filters:

```ocaml
type filters =
  { name : string option
  ; typ : Cpe_type.t option
  }

let list filters =
  Cpe.query ()
  |> ...
```

Но результат всё равно:

```ocaml
(Cpe.ref, Cpe.t) Query.t
```

а не `Lwt.t`.

---

# 29. Compilation pipeline

Я бы сделал явные стадии:

```text
Typed DSL
    ↓
AST
    ↓
validate
    ↓
normalize
    ↓
dialect lowering
    ↓
render
    ↓
Compiled_query
```

`Compiled_query`:

```ocaml
type 'a t =
  { sql : Caqti.Template.Query.t
  ; params : Packed_params.t
  ; decoder : 'a Decoder.t
  ; shape : Shape.t
  }
```

### Normalize

Сразу реализовать:

```text
AND(TRUE,x) → x
AND list flatten
OR list flatten
NOT NOT x → x
empty WHERE → none
deterministic aliases
deterministic parameter order
```

Позже:

```text
IN [] → FALSE
constant folding
predicate normalization
subquery flattening
```

---

# 30. Query cache — взять модель EF, но добавить не сразу

EF Core кэширует compilation result **по форме expression tree**, так что разные parameter values могут использовать одну compilation result. Он отдельно предупреждает, что плохо построенные dynamic expression trees с constants создают новые shapes и портят cache hit rate. ([Microsoft Learn][14])

У тебя:

```text
Cpe.name = "foo"
```

и:

```text
Cpe.name = "bar"
```

должны иметь одинаковый:

```text
Shape.t
```

Например:

```text
Eq(
  Column(Cpe.name),
  Param(Text)
)
```

Без значения `"foo"`.

Cache key:

```text
dialect
+
normalized AST shape
+
parameter types
+
projection shape
```

Не включать:

```text
parameter values
generated aliases
connection
```

---

# 31. Cache надо разделить на два разных уровня

### Query compilation cache

```text
AST shape
   ↓
SQL template + binding plan + decoder plan
```

Это EF-inspired.

### Prepared statement cache

```text
SQL template
   ↓
DB prepared statement
```

Это driver/database layer.

Не смешивать их.

jOOQ, например, автоматически использует bind values, но сам не держит PreparedStatement cache. ([jOOQ][15])

Caqti 3 уже предоставляет prepare policies, поэтому я бы **сначала вообще положился на Caqti**, а собственный compilation LRU добавил только после benchmarks. `Dynamic` готовит запрос на connection и освобождает его после GC request object, `Static` предназначен для действительно статических запросов. ([OCaml][12])

---

# 32. Explicit compiled queries — позже, аналог `EF.CompileQuery`

После обычного cache можно сделать:

```ocaml
Compiled.create
  (fun ~typ ->
     Cpe.query ()
     |> Query.where (fun c ->
          Cpe.typ c =: typ))
```

Но настоящий быстрый compiled API лучше строить через **parameter slots**, а не actual values:

```ocaml
let typ = Param.create Cpe_type.db_type

let template =
  Cpe.query ()
  |> Query.where (fun c ->
       Cpe.typ c =. Param.expr typ)
  |> Compiled.create
```

Выполнение:

```ocaml
Compiled.fetch
  ~conn
  template
  [ Param.bind typ `Router ]
```

Тогда AST вообще не перестраивается.

Это уже настоящий аналог `EF.CompileQuery`.

---

# 33. Но не надо чрезмерно оптимизировать query shapes под Postgres

Не стоит автоматически превращать:

```ocaml
where_opt name
```

в:

```sql
WHERE ($1 IS NULL OR name = $1)
```

только ради одного cache entry.

Пусть:

```text
без name
с name
```

будут двумя shapes.

PostgreSQL prepared statements могут использовать generic или parameter-specific custom plans, так что стабильность SQL shape не автоматически означает оптимальный execution plan. ([PostgreSQL][16])

То есть оптимизировать это после `EXPLAIN ANALYZE`, а не архитектурно заранее.

---

# 34. Raw SQL escape hatch нужен обязательно

Любой DSL рано или поздно чего-то не умеет.

Вдохновиться jOOQ Plain SQL QueryParts: он позволяет вставлять raw templates, но отдельно предупреждает об injection risk. ([jOOQ][17])

У тебя:

```ocaml
Unsafe.expr
  :  'a Db_type.t
  -> template:string
  -> Query_part.t list
  -> 'a Expr.t
```

Лучше не:

```ocaml
Unsafe.expr ("foo " ^ user_input)
```

а:

```ocaml
Unsafe.expr
  ~template:"date_trunc({0}, {1})"
  [ Bind period
  ; Expr timestamp
  ]
```

И namespace именно `Unsafe`/`Raw_sql`, чтобы это было видно на code review.

---

# 35. PPX только после стабилизации API

Первый API должен быть хорошим и без PPX.

Потом можно сделать:

```ocaml
module%sql Cpe = struct
  type t =
    { id : int64 [@pk]
    ; name : string
    ; typ : Cpe_type.t [@db.type Cpe_type.db_type]
    }
end
```

И PPX генерирует:

```text
table
columns
projection
decoder
insert input
FKs
```

Но **PPX не должен быть фундаментом query semantics**.

Sequoia хорошо демонстрирует PPX именно как sugar над type machinery — это разумная модель. ([GitHub][3])

---

# 36. Тестирование здесь критично

Я бы заложил пять видов тестов.

### Compile-fail tests

Такое не компилируется:

```ocaml
Cpe.id c =. Cpe.name c
```

```ocaml
Update.set Cpe.id "hello"
```

```ocaml
Expr.add
  (Cpe.name c)
  (Expr.int 42)
```

### Golden rendering tests

Один AST:

```ocaml
Cpe.typ c =: `Router
```

Postgres:

```sql
... WHERE t0.type = $1
```

SQLite:

```sql
... WHERE t0.type = ?1
```

### Integration tests

Одинаковая test schema:

```text
PostgreSQL
SQLite :memory:
```

одни и те же portable queries дают одинаковые значения.

### Property tests

Через QCheck:

```text
число bind nodes == число params
bind order deterministic
rendering никогда не inline'ит bound string
normalization idempotent
```

### SQL injection tests

Например value:

```text
'; DROP TABLE cpes; --
```

должен остаться одним bind value, а SQL template не меняться.

---

# 37. Как я бы разбил repository

Примерно:

```text
lib/
  core/
    db_type.ml
    name.ml
    table.ml
    column.ml
    table_ref.ml
    expr.ml
    condition.ml
    projection.ml

  ast/
    ast.ml
    validate.ml
    normalize.ml
    shape.ml

  query/
    query.ml
    select.ml
    join.ml
    group.ml
    insert.ml
    update.ml
    delete.ml
    returning.ml

  dialect/
    dialect.ml

    postgres/
      postgres.ml
      postgres_expr.ml
      postgres_type.ml
      postgres_lower.ml

    sqlite/
      sqlite.ml
      sqlite_expr.ml
      sqlite_type.ml
      sqlite_lower.ml

  compiler/
    lower.ml
    render.ml
    compiled_query.ml

  execution/
    caqti_adapter.ml
    db.ml

  codegen/
    schema_ir.ml
    postgres_introspect.ml
    sqlite_introspect.ml
    ocaml_codegen.ml

  ppx/
    ...

test/
  compile_fail/
  postgres/
  sqlite/
  portable/
  golden/
```

---

# 38. Порядок реализации

Я бы шёл именно в таком порядке:

### Milestone 1 — typed expression core

Реализовать:

```text
Db_type
Table
Column
Table_ref
Expr
Condition
Param
```

Без SQL execution.

Цель:

```ocaml
Cpe.id c =: 42L
```

строит корректное typed AST.

---

### Milestone 2 — Projection + SELECT

Реализовать:

```text
Projection
FROM
WHERE
SELECT
ORDER BY
LIMIT/OFFSET
```

И получить:

```ocaml
Cpe.query ()
|> where ...
|> select ...
```

---

### Milestone 3 — PostgreSQL compiler

Только Postgres.

Получать:

```text
AST → SQL + typed params
```

Сначала без cache.

---

### Milestone 4 — Caqti execution

Сделать:

```ocaml
Db.fetch
Db.fetch_one
Db.fetch_opt
Db.execute
```

и Lwt.

На этом этапе уже переписать один реальный `CpeRepo`.

---

### Milestone 5 — dynamic filters

Добавить:

```ocaml
where_opt
Condition.all
Condition.any
```

и переписать твой `/cpes?name=&type=`.

На этом этапе ты уже получишь практически полезный аналог `IQueryable`.

---

### Milestone 6 — JOIN

Сначала:

```text
INNER JOIN
LEFT JOIN
arbitrary ON
self join
```

Затем:

```text
FK metadata
join_fk
```

---

### Milestone 7 — SQLite lowering

Только теперь.

Прогнать всю portable integration suite одновременно через PostgreSQL и SQLite.

Это заставит архитектуру dialect layer проявить реальные проблемы.

---

### Milestone 8 — DML

```text
INSERT
UPDATE
DELETE
assignments
RETURNING
affected rows
```

С reuse существующих:

```text
Expr
Condition
Projection
Param
```

---

### Milestone 9 — subqueries

```text
EXISTS
IN query
scalar subquery
derived table
CTE
```

После этого модель становится действительно мощной.

---

### Milestone 10 — GROUP BY / aggregates

Сначала AST validator.

Потом, если хочется максимальной static safety:

```text
Grouped_query
Aggregate_expr
```

---

### Milestone 11 — schema generator

Убрать ручные:

```ocaml
Column.v ...
```

и генерировать их из схемы.

Это момент, где библиотека начнёт реально ощущаться как jOOQ.

---

### Milestone 12 — cache

Добавить:

```text
Shape
Normalizer
LRU compilation cache
metrics
```

После того как AST уже стабилен.

---

### Milestone 13 — explicit compiled queries

Аналог:

```text
EF.CompileQuery
```

с typed parameter slots.

---

### Milestone 14 — PPX

Только здесь.

Спрятать boilerplate schema definitions и, если понадобится, type-level source witnesses.

---

# 39. Как должен выглядеть конечный `CpeRepo`

В идеале вообще примерно так:

```ocaml
module CpeRepo = struct
  type filters =
    { name : string option
    ; typ : Cpe_type.t option
    }

  let query () =
    Query.from
      Cpe.table
      ~select:Cpe.projection

  let list filters =
    query ()
    |> Query.where_opt filters.name
         ~f:(fun c name ->
           Cpe.name c
           |> Expr.ci_like_value ("%" ^ name ^ "%"))
    |> Query.where_opt filters.typ
         ~f:(fun c typ ->
           Cpe.typ c =: typ)
end
```

Endpoint:

```ocaml
@@ fun _req name typ () ->
  let query =
    CpeRepo.list { name; typ }
    |> Query.order_by
         (fun c -> Cpe.name c)
         `Asc
    |> Query.limit 100
  in
  Db.with_transaction @@ fun conn ->
    Db.fetch ~conn query
```

И другой consumer спокойно делает:

```ocaml
CpeRepo.list filters
|> Query.where (fun c ->
     Cpe.enabled c =: true)
```

до исполнения.

---

# 40. В какой пропорции здесь EF / jOOQ / Sequoia

Если свести архитектуру к одной формуле, я бы сказал:

```text
              jOOQ
               │
       SQL AST / Fields / Codegen
       Dialects / Projections
               │
               ▼
    ┌───────────────────────────┐
    │   твой OCaml query DSL    │
    └───────────────────────────┘
       ▲          ▲           ▲
       │          │           │
      EF       Sequoia      Caqti
       │          │           │
 deferred    OCaml type    execution
 execution    safety       multi-DB
 query cache  + PPX        Lwt/codecs
```

По ощущениям я бы проектировал его как **60% jOOQ, 20% EF, 10% Sequoia, 10% Caqti/compiler design**.

И главное отличие от Sequoia: **не пытаться выиграть все гарантии type system'ом сразу**. Главное отличие от EF: **не скрывать SQL за object graph**. Главное отличие от jOOQ: использовать возможности OCaml так, чтобы DSL был immutable, компактным и имел нормальные algebraic abstractions вместо огромной Java type hierarchy.

Это, на мой взгляд, направление, из которого может получиться не просто локальный helper для `CpeRepo`, а вполне самостоятельная OCaml-библиотека уровня **«jOOQ Core для OCaml поверх Caqti»**. ([jOOQ][18])

[1]: https://github.com/paurkedal/ocaml-caqti?utm_source=chatgpt.com "GitHub - paurkedal/ocaml-caqti: Cooperative-threaded access to relational data · GitHub"
[2]: https://www.jooq.org/doc/latest/manual/sql-building/queryparts/?utm_source=chatgpt.com "QueryParts"
[3]: https://github.com/andrenth/sequoia "GitHub - andrenth/sequoia: OCaml type-safe query builder with syntax tree extension · GitHub"
[4]: https://www.jooq.org/doc/latest/manual/code-generation/?utm_source=chatgpt.com "Code generation"
[5]: https://www.jooq.org/doc/latest/manual/sql-building/bind-values/indexed-parameters/?utm_source=chatgpt.com "Indexed parameters"
[6]: https://www.jooq.org/doc/latest/manual/sql-building/queryparts/sql-rendering/?utm_source=chatgpt.com "SQL rendering"
[7]: https://learn.microsoft.com/en-us/ef/core/querying/how-query-works?utm_source=chatgpt.com "How Queries Work - EF Core | Microsoft Learn"
[8]: https://www.postgresql.org/docs/current/sql-update.html?utm_source=chatgpt.com "PostgreSQL: Documentation: 18: UPDATE"
[9]: https://www.jooq.org/doc/latest/manual/sql-building/dsl-context/sql-dialects/?utm_source=chatgpt.com "SQL Dialect"
[10]: https://www.jooq.org/doc/latest/manual/sql-building/column-expressions/string-functions/translate-function/?utm_source=chatgpt.com "The TRANSLATE function"
[11]: https://www.sqlite.org/lang_returning.html?utm_source=chatgpt.com "RETURNING"
[12]: https://ocaml.org/p/caqti/3.0.0/doc/caqti/Caqti/Template/Request/index.html?utm_source=chatgpt.com "caqti 3.0.0 · OCaml Package"
[13]: https://ocaml.org/p/caqti/3.0.0/doc/caqti.classic/Caqti_request/index.html?utm_source=chatgpt.com "caqti 3.0.0 · OCaml Package"
[14]: https://learn.microsoft.com/ru-ru/ef/core/performance/advanced-performance-topics?utm_source=chatgpt.com "Темы по продвинутой производительности — EF Core | Microsoft Learn"
[15]: https://www.jooq.org/doc/latest/manual/sql-building/bind-values/?utm_source=chatgpt.com "Bind values and parameters"
[16]: https://www.postgresql.org/docs/current/sql-prepare.html?utm_source=chatgpt.com "PostgreSQL: Documentation: 18: PREPARE"
[17]: https://www.jooq.org/doc/latest/manual/sql-building/queryparts/plain-sql-queryparts/?utm_source=chatgpt.com "Plain SQL QueryParts"
[18]: https://www.jooq.org/doc/latest/manual/sql-building/?utm_source=chatgpt.com "SQL building"



>а можно два бекенда, кроме caqti ещё pgocaml?

Да. Причём я бы **сразу проектировал execution layer так, чтобы Caqti был не “частью query model”, а одним из backend'ов**, а PG'OCaml — вторым.

То есть не:

```text
Query AST
  ↓
Caqti
  ↓
Postgres / SQLite
```

а:

```text
                     typed Query AST
                           │
                    compile / lower
                           │
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
        Caqti backend              PG'OCaml backend
              │                         │
       PostgreSQL/SQLite             PostgreSQL
```

Это вполне реалистично. PG'OCaml актуально доступен как отдельный PostgreSQL client, говорит с сервером по wire protocol напрямую, а не через `libpq`, и его базовый интерфейс синхронный, хотя библиотека допускает другие concurrency implementations через `THREAD`. ([OCaml][1])

## Главное: разделить **Dialect** и **Backend**

Это две разные вещи.

`Dialect` отвечает только за:

> Как семантический SQL AST превратить в SQL конкретной СУБД?

```ocaml
module type DIALECT = sig
  type t

  val render : Ast.query -> Rendered.t
end
```

Например:

```text
Postgres dialect
SQLite dialect
```

А `Backend` отвечает:

> Как SQL + параметры физически отправить в БД и прочитать результат?

```ocaml
module type BACKEND = sig
  type connection
  type error
  type 'a io

  val fetch
    :  connection
    -> 'a Compiled.t
    -> ('a list, error) result io

  val fetch_one
    :  connection
    -> 'a Compiled.t
    -> ('a, error) result io

  val execute
    :  connection
    -> Command.compiled
    -> (int, error) result io
end
```

И тогда:

```text
Dialect.Postgres
Dialect.SQLite

Backend.Caqti
Backend.Pgocaml
```

— независимые понятия.

---

## Матрица возможностей будет такой

| Backend    | PostgreSQL | SQLite |
| ---------- | ---------: | -----: |
| `Caqti`    |         да |     да |
| `PG'OCaml` |         да |    нет |

Caqti сам является multi-database abstraction и сейчас имеет PostgreSQL и SQLite drivers; его `Request` объединяет query generator, parameter encoder и row decoder. ([OCaml][2])

PG'OCaml, наоборот, намеренно только PostgreSQL; его документация прямо говорит, что другие БД он не поддерживает. ([OCaml][3])

Поэтому архитектурно:

```text
Query
 │
 ├── Postgres.compile
 │       ├── Caqti.execute
 │       └── Pgocaml.execute
 │
 └── Sqlite.compile
         └── Caqti.execute
```

---

# Не позволяй compiler'у генерировать `Caqti_type.t`

Это поправка к предыдущему плану.

Если хочешь два backend'а, то вот это:

```ocaml
type 'a compiled =
  { sql : Caqti.Template.Query.t
  ; params : ...
  ; decoder : ...
  }
```

уже **слишком Caqti-specific**.

Нужно своё backend-neutral представление:

```ocaml
module Compiled : sig
  type 'a t =
    { sql : string
    ; params : Packed_param.t array
    ; decoder : 'a Decoder.t
    }
end
```

Например:

```ocaml
type packed_param =
  | Param : 'a Db_type.t * 'a -> packed_param
```

А decoder:

```ocaml
type 'a decoder
```

тоже твой собственный.

Только затем adapter преобразует их:

```text
Db_type.t
  ├──→ Caqti_type.t
  └──→ PG'OCaml parameter encoding

Decoder.t
  ├──→ Caqti decoder
  └──→ PG'OCaml row decoder
```

Это очень важная граница.

---

# Я бы вообще сделал три IR

Лучше так:

```text
Typed query
    ↓
SQL AST
    ↓
dialect compiler
    ↓
Rendered_query
    ↓
backend adapter
```

Где:

```ocaml
type 'a rendered_query =
  { sql : string
  ; params : Packed_param.t array
  ; result : 'a Decoder.t
  ; cardinality : cardinality
  }
```

`cardinality`:

```ocaml
type cardinality =
  | Zero
  | One
  | Zero_or_one
  | Many
```

Или типизированно:

```ocaml
type _ cardinality =
  | Exec : int cardinality
  | One : 'a cardinality
  | Option : 'a option cardinality
  | Many : 'a list cardinality
```

Backend занимается только этой структурой.

---

# `Db_type` становится ещё важнее

Например:

```ocaml
type _ Db_type.t =
  | Int : int t
  | Int64 : int64 t
  | Text : string t
  | Bool : bool t
  | Float : float t
  | Bytes : bytes t
  | Option : 'a t -> 'a option t
  | Custom :
      { repr : 'a t
      ; encode : 'b -> 'a
      ; decode : 'a -> ('b, string) result
      }
      -> 'b t
```

Для backend'ов:

```ocaml
module Caqti_codec = struct
  val type_ : 'a Db_type.t -> 'a Caqti_type.t
end
```

и отдельно:

```ocaml
module Pgocaml_codec = struct
  val encode :
    'a Db_type.t ->
    'a ->
    Pgocaml_param.t

  val decode :
    'a Db_type.t ->
    Pgocaml_value.t ->
    ('a, string) result
end
```

Сам query builder при этом вообще не знает ни о Caqti, ни о PG'OCaml.

---

# Проблема: PG'OCaml PPX тебе здесь почти не нужен

PG'OCaml интересен тем, что его PPX умеет compile-time typechecking SQL против настоящей PostgreSQL schema; документация указывает, что для этого ему нужна доступная БД во время компиляции. ([OCaml][1])

Но в твоей архитектуре типизацию SQL уже обеспечивает **твой DSL**.

Поэтому использовать:

```ocaml
[%pgsql ...]
```

для сгенерированного runtime SQL особо не получится и смысла мало.

Тебе нужен именно **runtime API PG'OCaml**:

```text
prepare
bind
execute
fetch rows
```

а не его PPX.

То есть PG'OCaml выступает у тебя как:

> PostgreSQL wire-protocol execution engine.

Это даже архитектурно чище.

---

# Backend API я бы сделал таким

Например:

```ocaml
module type BACKEND = sig
  type conn
  type error
  type 'a io

  val dialect : Dialect.t

  val execute
    :  conn
    -> Command.t
    -> (int, error) Result.t io

  val fetch
    :  conn
    -> 'a Query.compiled
    -> ('a list, error) Result.t io

  val fetch_opt
    :  conn
    -> 'a Query.compiled
    -> ('a option, error) Result.t io

  val fetch_one
    :  conn
    -> 'a Query.compiled
    -> ('a, error) Result.t io
end
```

Но `dialect` даже можно вынести из backend и передавать явно.

---

# И тут возникает вопрос Lwt

У тебя приложение сейчас Lwt.

Caqti умеет concurrency-specific connectors и нормально ложится на Lwt. PG'OCaml по умолчанию предоставляет синхронный интерфейс, но его generic layer параметризуется concurrency implementation через `THREAD`. ([OCaml][4])

Поэтому есть два варианта.

### Вариант 1 — backend interface фиксирован на Lwt

Для твоего проекта, скорее всего, лучший вариант:

```ocaml
module type BACKEND = sig
  type conn
  type error

  val fetch :
    conn ->
    'a Compiled.t ->
    ('a list, error) result Lwt.t
end
```

`Caqti_backend` естественно реализует это.

Для `PG'OCaml` либо используешь Lwt-compatible instantiation его generic layer, если она подходит твоей версии/стеку, либо делаешь адаптер вокруг выбранного execution model.

### Вариант 2 — абстрагировать effect

Можно:

```ocaml
module type IO = sig
  type 'a t
  val return : 'a -> 'a t
  val bind : 'a t -> ('a -> 'b t) -> 'b t
end
```

и backend:

```ocaml
module Make_backend (IO : IO) ...
```

Но я бы **не стал** делать это сразу.

У тебя весь HTTP framework уже Lwt. Абстракция над monad только усложнит библиотеку без практической выгоды.

---

# Ещё важнее — connection не должен жить в Query

То есть категорически не:

```ocaml
CpeRepo.query ~conn
```

а:

```ocaml
let q =
  CpeRepo.query ()
  |> Query.where ...
```

и только потом:

```ocaml
Caqti_backend.fetch conn q
```

или:

```ocaml
Pgocaml_backend.fetch conn q
```

Таким образом буквально **один объект Query** можно исполнить обоими backend'ами:

```ocaml
let q =
  CpeRepo.list { name = Some "foo"; typ = None }
```

В тесте:

```ocaml
let%lwt a =
  Caqti_backend.fetch caqti_conn q
in

let%lwt b =
  Pgocaml_backend.fetch pg_conn q
in

assert (List.equal Cpe.equal a b)
```

Очень полезно для cross-backend tests.

---

# А кто выбирает dialect?

Можно сделать очень чисто:

```ocaml
Backend.fetch
```

сам знает dialect своей connection.

```ocaml
module Caqti_pg = Backend.Make(struct
  let dialect = Dialect.Postgres
  ...
end)

module Caqti_sqlite = Backend.Make(struct
  let dialect = Dialect.Sqlite
  ...
end)

module Pgocaml = Backend.Make(struct
  let dialect = Dialect.Postgres
  ...
end)
```

То есть:

```text
Caqti/Postgres → Postgres compiler
Caqti/SQLite   → SQLite compiler
PG'OCaml       → Postgres compiler
```

SQL compiler вообще не дублируется.

---

# Prepared statements тоже должны быть backend-specific

Это ещё одна причина правильно разделить слои.

У Caqti уже существует собственная модель request templates и prepare policies; запрос может быть подготовлен и закэширован на connection в зависимости от policy и driver support. ([OCaml][2])

У PG'OCaml будет свой механизм работы с prepared statements.

Поэтому:

```text
Query compilation cache
```

общий:

```text
AST shape
  ↓
Rendered SQL + parameter layout
```

а:

```text
Prepared statement cache
```

принадлежит конкретному backend'у:

```text
Caqti backend
    └─ Caqti prepared request

PG'OCaml backend
    └─ PG prepared statement
```

Не надо пытаться унифицировать prepared-statement handle.

---

# Структура проекта тогда немного меняется

Я бы сделал:

```text
lib/
  core/
    db_type.ml
    table.ml
    column.ml
    expr.ml
    condition.ml
    projection.ml

  query/
    select.ml
    insert.ml
    update.ml
    delete.ml
    query.ml

  ast/
    ast.ml
    normalize.ml
    validate.ml
    shape.ml

  dialect/
    dialect.ml

    postgres/
      compiler.ml
      postgres_type.ml
      postgres_expr.ml

    sqlite/
      compiler.ml
      sqlite_type.ml
      sqlite_expr.ml

  compiled/
    param.ml
    decoder.ml
    rendered_query.ml

  backend/
    backend_intf.ml

    caqti/
      caqti_backend.ml
      caqti_codec.ml

    pgocaml/
      pgocaml_backend.ml
      pgocaml_codec.ml

  codegen/
    ...
```

Dependency graph:

```text
core
 ↓
query / ast
 ↓
dialect
 ↓
compiled
 ↓
┌──────────────┐
│              │
caqti       pgocaml
```

Причём **никакой зависимости на Caqti/PG'OCaml выше `backend/`**.

---

## Это даже лучше как дизайн библиотеки

Потому что тогда позже можно добавить:

```text
Backend_postgresql_ocaml
Backend_pgx
Backend_eio_pg
```

не трогая:

```text
Expr
Query
Join
Group_by
Postgres.Compiler
```

А Caqti уже сейчас имеет в своей экосистеме несколько drivers, включая PostgreSQL, SQLite и экспериментальный PostgreSQL driver поверх `pgx`, что хорошо показывает полезность такого separation. ([OCaml][5])

Так что я бы скорректировал предыдущую архитектуру именно так: **Caqti — первый execution backend, PG'OCaml — второй; PostgreSQL/SQLite — dialect'ы, а не backend'ы.** Это важное различие.

[1]: https://ocaml.org/p/pgocaml/latest/README.html?utm_source=chatgpt.com "pgocaml 4.4.0 (latest) · OCaml Package"
[2]: https://ocaml.org/p/caqti/3.0.0/doc/caqti/Caqti/Template/Request/index.html?utm_source=chatgpt.com "caqti 3.0.0 · OCaml Package"
[3]: https://ocaml.org/p/pgocaml/latest?utm_source=chatgpt.com "pgocaml 4.4.0 (latest) · OCaml Package"
[4]: https://ocaml.org/p/pgocaml/latest/pgocaml/PGOCaml/index.html?utm_source=chatgpt.com "pgocaml 4.4.0 (latest) · OCaml Package"
[5]: https://ocaml.org/p/caqti/latest/README.html?utm_source=chatgpt.com "caqti 3.0.0 (latest) · OCaml Package"
