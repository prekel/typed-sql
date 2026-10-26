# Происхождение реализации

Генерация runtime-вызовов и эвристика nullability в `expand.ml` и команде
`bin/typed_sql_pgocaml_queries.ml` адаптированы из
[pgocaml_ppx 4.4.0](https://github.com/darioteixeira/pgocaml/blob/v4.4.0/ppx/ppx_pgsql.ml).
Copyright (C) 2005–2016 Richard Jones and other authors. Пакет распространяется
под GNU Library General Public License версии 2 или позднее; текст лицензии
находится в [COPYING](COPYING). Лицензия основного ядра остаётся MIT.

Поддержка OCaml quoted strings при разборе аргументов перенесена по
[PR #80](https://github.com/darioteixeira/pgocaml/pull/80), автор Voronar,
commit `4462561`. Pattern находится в `quotation.ml` и адаптирован к AST ppxlib.

Команда подготовки описывает запросы через Prepare/Describe и каталоги
PostgreSQL. Структурные codecs, логический кеш, metadata и helpers одномерных
arrays написаны для этого проекта. При компиляции пакет не обращается к БД.

Общий scanner и логический кеш находятся в `typed-sql-ppx.cache`. Обработка
payload в [query_source.ml](../query-ppx/cache/query_source.ml) сохраняет ту же
шапку происхождения и LGPL-лицензию. Выполняющий PPX вычисляет PG’OCaml codecs
из логических типов. [Контракт и ограничения](../doc/ppx.md).
