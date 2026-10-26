CREATE SCHEMA custom_type_test;
CREATE DOMAIN custom_type_test.typ123 AS text;
CREATE TYPE custom_type_test.mood123 AS ENUM ('ready', 'done');
CREATE TYPE custom_type_test.point123 AS (x integer, y integer);
CREATE TABLE custom_type_test.items (
  value custom_type_test.typ123[] NOT NULL,
  optional_value custom_type_test.typ123[]
);
INSERT INTO custom_type_test.items VALUES ('{alpha,NULL}', NULL);
