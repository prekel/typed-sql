# Дорожная карта

После стабилизации typed SELECT вертикальный срез расширяется в таком порядке:

1. INNER/LEFT JOIN и nullable table references;
2. INSERT/UPDATE/DELETE и общий Projection для RETURNING;
3. subqueries, EXISTS и CTE;
4. aggregates, GROUP BY и HAVING;
5. PostgreSQL/SQLite schema introspection и code generation;
6. compilation cache и explicit parameter slots;
7. PG'OCaml backend;
8. PPX только как sugar над стабильным ручным API.
