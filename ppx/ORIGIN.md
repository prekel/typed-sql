# Происхождение реализации

Генерация runtime-вызовов и эвристика nullability в `expand.ml` адаптированы из
[pgocaml_ppx 4.4.0](https://github.com/darioteixeira/pgocaml/blob/v4.4.0/ppx/ppx_pgsql.ml).
Copyright (C) 2005–2016 Richard Jones and other authors. Пакет распространяется
под GNU Library General Public License версии 2 или позднее; текст лицензии
находится в [COPYING](COPYING). Лицензия основного ядра остаётся MIT.

Поддержка OCaml quoted strings при разборе аргументов перенесена по
[PR #80](https://github.com/darioteixeira/pgocaml/pull/80), автор Voronar,
commit `4462561`. Pattern адаптирован к AST текущего `ppxlib`. Регрессионные
тесты сохраняют отдельные проверки обычных и delimited strings.

SQL parser и разрешение metadata написаны для ограниченного offline SELECT.
Этот пакет не включает online-интроспекцию upstream и не обращается к БД при
компиляции. Поддержанное подмножество описано в [руководстве](../doc/ppx.md).
