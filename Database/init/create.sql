CREATE TABLE public.users (
	id uuid DEFAULT uuidv7() NOT NULL,
	"name" varchar NOT NULL,
	CONSTRAINT users_pk PRIMARY KEY (id)
);