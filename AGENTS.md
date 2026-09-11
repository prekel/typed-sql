# Инструкции для агентов

## Область проекта

- `lib/` — backend-independent ядро typed relational query DSL. Оно не должно
  зависеть от Caqti, Lwt или конкретного драйвера базы данных.
- `caqti-lwt/` — единственное место для зависимости от Caqti и Lwt.
- `test/` — regression, property, golden и compile-fail тесты ядра.
- `caqti-lwt/test/` — интеграционные тесты через SQLite `:memory:`.
- `doc/` — odoc-документация архитектуры и публичного API.
- `benchmark/` — небольшие воспроизводимые benchmark без внешней БД.
- Метаданные пакетов задаются в `dune-project`; сгенерированные `.opam` вручную
  не редактируются.

## Общие принципы

- Используй `.ocamlformat` как единственный источник правил форматирования.
- Предпочитай простой читаемый код, небольшие связные модули и явные
  инварианты. Не добавляй абстракции без практической необходимости.
- По умолчанию используй immutable-данные.
- Во всех новых `.ml` и `.mli` используй `open! Base`. К функциям Stdlib
  обращайся явно через `Stdlib`.
- Основной тип модуля называй `t`, сигнатуру — `S`, функтор — `Make`.
- Для ожидаемых ошибок публичного API используй `option` или `Result.t`;
  throwing-вариант при необходимости называй с суффиксом `_exn`.
- Для последовательных вычислений в `Result.t` используй `let%bind` и
  `let%map` из `Result.Let_syntax`; не записывай такие цепочки через
  `Result.bind` и вложенные callbacks.
- Публичный API и odoc-комментарии размещай в `.mli`. Комментарии должны
  объяснять ограничения и инварианты, а не пересказывать код.

## Инварианты typed-sql

- Query — immutable deferred value; connection и эффект выполнения не входят в
  ядро или semantic AST.
- SQL identifiers происходят только из проверенных descriptors и экранируются
  dialect renderer. Пользовательские значения всегда остаются bind parameters.
- Semantic AST хранит source identity, но не SQL aliases. Compiler назначает
  aliases и parameter indices детерминированно.
- Совместимость типов выражений проверяется при построении DSL. Принадлежность
  column source текущему запросу дополнительно проверяется compiler.
- Не используй `Obj.magic`, unchecked casts или строковую конкатенацию для
  обхода типовой модели.
- Compiler и Caqti dialect callback должны быть чистыми. Shape не включает
  parameter values, generative source IDs, connections или generated aliases.
- Unsupported dialect и некорректный AST возвращаются как явные ошибки; не
  генерируй приблизительно эквивалентный SQL.
- `typed-sql-caqti-lwt` преобразует backend-neutral descriptors на границе и не
  меняет query semantics.

## Тесты и проверки

- Основные команды: `make build`, `make test`, `make fmt`.
- `make coverage` измеряет только реализацию `Typed_sql` через публичный API,
  property tests и SQLite `:memory:`. Не используй `typed-sql.private`,
  `typed-sql.backend`, раскрытие новых элементов API или coverage suppression
  ради увеличения процента. Минимальный порог — 97% сырого покрытия.
- Для печатаемого SQL и diagnostics используй небольшие отдельные
  `ppx_expect` snapshots.
- В expect-тестах ставь `[%expect ...]` сразу после каждого вывода, в том
  числе после вызова helper, который печатает. Не объединяй вывод нескольких
  проверок в один snapshot.
- Для булевых свойств используй `let%test`, для проверок с assertions и
  последовательностью действий — `let%test_unit`. Не печатай `true`, `false`,
  счётчики или маркеры вроде `valid`/`rejected` ради expect-snapshot.
- Не продвигай snapshots и форматирование автоматически во время обычной
  проверки.
- Изменение публичного контракта сопровождай regression или compile-fail test.
- Portable SQL проверяй одинаковыми golden cases для PostgreSQL и SQLite.
- Integration tests по умолчанию используют SQLite `:memory:` и не требуют
  внешнего сервиса.

## Правила репозитория

- Markdown пиши на русском, текст в коде — на английском.
- Не добавляй CI без отдельного запроса.
- Не запускай `git commit` самостоятельно.
