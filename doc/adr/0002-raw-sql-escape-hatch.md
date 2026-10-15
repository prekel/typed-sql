# ADR 0002: границы Raw SQL escape hatch

- Статус: обсуждается; публичного API пока нет
- Дата: 25 сентября 2026 года
- Связанные решения: [ADR 0001](0001-static-statement-api.md)

## Контекст

DSL покрывает запросы, для которых можно проверить типы выражений, область
видимости источников и возможности диалекта. Прикладному запросу может
понадобиться SQL-конструкция, которой в DSL ещё нет. Отдельный escape hatch
позволит выполнить такой запрос без строки, в которую интерполированы значения.
Он не делает произвольный SQL безопасным или семантически переносимым.

Исходный план предлагал `Unsafe.expr` с шаблоном и типизированными частями.
Текущий `Statement` уже разделяет SQL template и bind values, а Caqti и
PG'OCaml выполняют один `Statement.t`. Помимо неподдержанного DSL синтаксиса,
raw API нужен для постепенной миграции PG’OCaml quotations на `Result_query.t`
с последующим выполнением через обычный `Statement` и выбранный adapter.
Общую форму API ещё предстоит выбрать по требованиям этих потребителей.

## Выбранные рамки

- [x] Нужны оба уровня: raw expression/condition внутри обычного DSL и целый
  raw SELECT или DML, когда не хватает конструкций самого запроса.
- [x] Автор явно выбирает PostgreSQL, SQLite или portable. Выбор отражается в
  dialect requirement; SQLite не принимает PostgreSQL-only фрагмент и наоборот.
  Объявление portable означает ответственность автора за семантику SQL в обеих
  базах, а не автоматическую проверку эквивалентности.
- [x] Целые raw statements проходят через существующий `Statement.t` и
  `Statement.sql`/adapter `run`. Отдельный публичный метод выполнения адаптера
  не нужен.
- [x] Пользовательские значения остаются типизированными bind parameters.
  Доверенный SQL-текст видимо помечается как unsafe; значения input нельзя
  вставлять в него строковой конкатенацией.
- [x] Сейчас фиксируем решение в ADR и оставляем пункт roadmap открытым.
  Реализация начнётся после выбора конкретного запроса и оставшихся контрактов.

## Потребитель: query/command quotations с `Expr.t` для миграции

В [roadmap совместимого PPX](../ppx_roadmap.md) выбрано направление
`[%pgsql.query ...]` / `[%pgsql.query.object ...]` → `Result_query.t` и отдельное
command-направление → `Command.t`. Это будущий API, ещё не реализация.
Metadata поступают из одной из двух независимых ветвей: собственного SQL
parser/inference по snapshot v3 или SQL cache Prepare/Describe. Cache-ветвь
не требует разбора SQL и вывода типов собственным frontend.

Подстановки query quotations принимают `Expr.t`, представляющие bind parameters
или constants. Quotation используется прямо внутри `params.query_many`
с локальными `Expr.t` из `let%map.Parameters`; отдельный builder не требуется:

```ocaml
type input =
  { status : string
  ; limit : int64
  }

let find_statement =
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let%map.Parameters status =
      params.expr Db_type.text ~get:(fun input -> input.status)
    and limit =
      params.expr Db_type.int64 ~get:(fun input -> input.limit)
    in
    params.query_many
      [%pgsql.query.object
        "SELECT id, name FROM people WHERE status = $status LIMIT $limit"])
```

Query строится из symbolic bind slots при определении Statement.
Готовый план переиспользуется, getters читают новые значения input при каждом
выполнении. Соединение и эффект выполнения не входят в query. Для этого пути
не нужен `Statement.Dynamic`; создание builder/Statement при каждом вызове
прикладной функции по-прежнему повторяло бы компиляцию. `Expr.constant` явно
захватывает значение времени определения Statement и остаётся SQL bind.
Quotation также можно вынести в функцию с именованными аргументами `Expr.t`,
если её нужно переиспользовать; это не требование API.

Первая версия holes принимает результаты `params.expr`, `params.column` и
`Expr.constant`; nullable slots требуют отдельного явного контракта. Raw API
проверяет точные SQL-descriptors и принадлежность slots текущему Statement.
Произвольные `Expr.lower`, arithmetic и column references в holes отложены:
для них нужны expression rendering, source scope и соответствие metadata
результата. Совпадения OCaml-типов для этого недостаточно.

Raw SELECT использует `Result_query.select`, DML RETURNING —
`Result_query.returning`, DML без результата — `Command.t`. Для cache-ветви
предстоит определить явный контракт kind: наличие row description само по себе
не различает SELECT и DML RETURNING. Не выполнять пользовательский SQL ради
классификации. Без доказательства кардинальности использовать `query_many`
или runtime `expect_one/optional`.

Отдельные `[%pgsql.statement ...]` / `[%pgsql.statement.object ...]` отложены.
К ним следует возвращаться при практическом ограничении query/command вместе
с `Statement.with_parameters`; специальный синтаксис input сейчас не выбран
и не является условием переиспользования плана.

Пакет `typed-sql-ppx` использует descriptors/codecs typed-sql и не зависит от
PGOCaml, включая generated-код. Сканер, логические metadata и генерация raw API
могут быть общими; собственный parser нужен только snapshot-ветви. Подготовка
кеша остаётся отдельным online-инструментом. Совместимый выполняющий PPX
сохраняет PG’OCaml codecs; различия `int32`/`int`, CalendarLib и других
представлений нужно явно учитывать при миграции.

Для композиции raw/DSL нужны set operations, derived tables и CTE через
проверенные descriptors выходных колонок. Object output является decoder,
а не описанием relation fields. Compiler проверяет позиции вложения и SQL-типы,
назначает bind indices детерминированно, сохраняет shared slots и независимость
параметров разных запросов. Значения не входят в SQL или shape.

Инструкция миграции сохраняет object → record converters там, где совпадают
типы методов, затем показывает query с `Expr.t`, статический Statement и DSL.
Проверки охватывают getter timing, переиспользование плана, оба источника типов,
Caqti PostgreSQL и PG’OCaml adapter, сборку без PGOCaml и PostgreSQL requirements.
Переход на Caqti не делает PostgreSQL SQL совместимым с SQLite. Отдельно
документируются исключения PG’OCaml / `Result.t` adapters и `unit` / `Affected_rows.t`.

Динамические lists, произвольные expression holes и Custom Type Conversions
не входят в первый сценарий. Эти требования не выбирают окончательную форму
общего raw API для expressions или portable SQL.

## Открытые решения

Варианты общего raw API ниже пока не выбраны. Перед реализацией нужной части
API необходимо закрыть относящиеся к ней пункты на конкретном сценарии;
остальные решения могут оставаться открытыми.

### Форма SQL и подстановок

- [ ] **Список частей:** доверенный SQL-текст, bind, выражение DSL и проверенный
  идентификатор чередуются как значения отдельного типа. Renderer назначает
  индексы параметров и aliases в порядке обхода. Нет собственного синтаксиса
  плейсхолдеров, но длинный SQL становится многословным.
- [ ] **Шаблон с именованными или позиционными holes:** SQL читается одной
  строкой, а отдельный список задаёт типизированные части. Потребуются правила
  для повторных holes, пропусков, escaping и ошибок разбора. Нельзя спутать
  holes API с `$1`, `?1` и похожим синтаксисом самого SQL.

В обоих вариантах надо определить, как вставлять column/table identifiers без
обхода проверенных descriptors, как запрещать неверную область видимости
выражения DSL, как повторно использовать один bind slot и что делать с
literal placeholder или пользовательской строкой внутри доверенного SQL-текста.
Текстовый фрагмент остаётся явной unsafe-границей: библиотека не сможет
доказать безопасность SQL, собранного приложением из непроверенных строк.

### Встраивание и результат

- [ ] Решить, каким внутренним узлом представлять raw expression и condition,
  чтобы тип результата был задан через `Db_type.t`, а compiler проверял
  вложенные DSL expressions, их source scope и dialect requirement. Raw текст
  при этом остаётся непрозрачным для aggregate validator.
- [ ] Решить, как задавать колонки целого raw SELECT. Основной кандидат —
  отдельное аппликативное описание полей через `Db_type.t` и `map`, которое
  использует существующие decoder и adapter codecs. Нужно определить поведение
  при несовпадении фактического числа или database-типов колонок.
- [ ] Определить cardinality целого raw SELECT. Без доказательства от DSL
  `query_many` может возвращать список, а `expect_one`/`expect_optional` —
  проверять число строк при выполнении. Нужны ли конструкторы с заявленной
  статической кардинальностью, пока не решено.
- [x] Для query quotations raw builder возвращает `Result_query.t` и принимает
  bind/constant `Expr.t`. Переиспользуемый Statement строится обычным
  `Statement.with_parameters`; прямые statement quotations отложены.
  DML без результата требует `Command.t`; точный API его quotation ещё
  предстоит определить.
- [ ] Для общего raw API за пределами первого статического PPX-сценария
  решить, нужен ли dynamic вариант для SQL shape, зависящей от input. Для portable raw statement нужно
  выбрать: один текст для двух диалектов или явно заданная пара текстов.
- [ ] Определить ошибки определения statement: пустой шаблон, неверные holes,
  неподдерживаемый диалект и несовместимые result codecs. Сформировать shape
  только из SQL-структуры и типов, без значений bind parameters и соединения.

## Как может выглядеть использование

Ниже — эскиз варианта со списком частей. Имена и сигнатуры **не утверждены**:
они показывают границу между доверенным SQL и bind/DSL выражениями.

```ocaml
Raw_sql.Postgresql.expr Db_type.timestamp
  [ Sql "date_trunc("
  ; Bind (Expr.constant Db_type.text "day")
  ; Sql ", "
  ; Expression (Event.occurred_at event)
  ; Sql ")"
  ]
```

Для целого SELECT автор должен также описать порядок и типы результата.
Вручную raw builder получает typed binds и описание полей с decoder;
query quotation генерирует их по metadata из snapshot inference или SQL cache. Результат —
`Result_query.t`, который можно компоновать с DSL до создания Statement.

`Raw_sql.Postgresql`, `Raw_sql.Sqlite` и `Raw_sql.Portable` в этом эскизе
означают явный выбор dialect. `Bind` получает значение с `Db_type.t`, compiler
назначает `$n` или `?n`, а adapter кодирует его при выполнении. DML с
`RETURNING` относится к row-returning варианту. Точные конструкторы raw API
ещё предстоит определить и документировать в `typed_sql.mli`.

## Условие для перехода к реализации

Нужен конкретный сценарий: запрос, который нельзя удобно выразить текущим DSL,
либо миграция PPX quotations через описанный выше режим. Для выбранного
сценария зафиксировать SQL для PostgreSQL и/или SQLite, типы input и результата
и требуемую кардинальность. На нём следует закрыть необходимые вопросы выше,
затем проверить SQL snapshots, binding, применимые проверки source scope и
выполнение через существующие adapters. Ближайший шаг — минимальный raw
SELECT API, возвращающий `Result_query.t`, с ручными проверками через Caqti
и в композиции с DSL; генерация PPX следует после него. До реализации ADR
не меняет публичный контракт.
