CREATE SCHEMA query_cache_test;
CREATE TYPE query_cache_test.mood AS ENUM ('happy', 'sad');
CREATE DOMAIN query_cache_test.tag AS integer CHECK (VALUE > 0);
CREATE TABLE query_cache_test.people (
  id integer PRIMARY KEY,
  name text NOT NULL,
  note text,
  mood query_cache_test.mood NOT NULL,
  tag query_cache_test.tag NOT NULL,
  nums integer[] NOT NULL
);
INSERT INTO query_cache_test.people VALUES (1, 'Ada', NULL, 'happy', 10, '{1,NULL}');
