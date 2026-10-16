CREATE TABLE typed_sql_query_items (id integer PRIMARY KEY, name text NOT NULL);
CREATE TYPE typed_sql_query_mood AS ENUM ('ready', 'done');
CREATE DOMAIN typed_sql_query_tag AS integer CHECK (VALUE > 0);

CREATE TABLE typed_sql_query_json (id integer PRIMARY KEY, value jsonb);
INSERT INTO typed_sql_query_json VALUES
  (1, 'null'), (2, NULL), (3, '{"a":1}'), (4, '"text"'),
  (5, '[1]'), (6, 'true'), (7, '42');
