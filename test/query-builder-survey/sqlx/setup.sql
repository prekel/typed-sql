CREATE TABLE users (
  id integer PRIMARY KEY,
  name text NOT NULL,
  age integer,
  parent_id integer REFERENCES users (id)
);
CREATE TABLE posts (
  id integer PRIMARY KEY,
  user_id integer NOT NULL REFERENCES users (id),
  title text NOT NULL,
  score integer NOT NULL
);
