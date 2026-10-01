BEGIN;

CREATE TYPE public.mood AS ENUM ('happy', 'sad');
CREATE DOMAIN public.username AS varchar(32);
CREATE DOMAIN public.host AS inet;
CREATE DOMAIN public.rational AS text;
CREATE DOMAIN public.geometry AS text;

CREATE TABLE public."USER PROFILE" (
  id bigint NOT NULL
);

CREATE TABLE public.advanced (
  local_value timestamp without time zone NOT NULL,
  float_value timestamp without time zone NOT NULL,
  duration interval NOT NULL,
  payload json NOT NULL,
  payload_binary jsonb NOT NULL,
  mood public.mood NOT NULL,
  username public.username NOT NULL,
  host public.host NOT NULL,
  inet_value inet NOT NULL,
  small_value integer NOT NULL,
  numbers integer[] NOT NULL,
  rational_value public.rational NOT NULL,
  geometry_value public.geometry NOT NULL
);

CREATE TABLE public."table" (
  id bigint NOT NULL
);

CREATE TABLE public.typed_sql_codegen (
  id bigint NOT NULL
);

CREATE TABLE public."user-profile" (
  id bigint NOT NULL,
  "id-column" integer NOT NULL,
  "display-name" text NOT NULL,
  display_name text NOT NULL,
  "display.name" text NOT NULL,
  "table" boolean NOT NULL,
  "published-on" date NOT NULL,
  "created-at" timestamp with time zone NOT NULL,
  "external-id" uuid NOT NULL,
  reference text NOT NULL,
  "return" text NOT NULL,
  land text NOT NULL,
  "_" text NOT NULL,
  map text NOT NULL,
  total numeric NOT NULL
);

CREATE TABLE public.user_profile (
  id bigint NOT NULL
);

COMMIT;
