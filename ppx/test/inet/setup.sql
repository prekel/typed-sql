CREATE DOMAIN public.ppx_inet_domain AS inet;
CREATE TABLE public.ppx_inet_table (
  address inet NOT NULL,
  optional_address inet
);
INSERT INTO public.ppx_inet_table VALUES ('192.0.2.129/24', NULL);
