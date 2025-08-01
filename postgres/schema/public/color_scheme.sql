CREATE TABLE public.color_scheme (
    id serial PRIMARY KEY,

    primary100 text NOT NULL,
	primary200 text NOT NULL,
	primary300 text NOT NULL,
	primary400 text NOT NULL,
	primary500 text NOT NULL,
	primary600 text NOT NULL,
	primary700 text NOT NULL,
	primary800 text NOT NULL,
	primary900 text NOT NULL,

	accent100 text NOT NULL,
	accent200 text NOT NULL,
	accent300 text NOT NULL,
	accent400 text NOT NULL,
	accent500 text NOT NULL,
	accent600 text NOT NULL,
	accent700 text NOT NULL,
	accent800 text NOT NULL,
	accent900 text NOT NULL,

    created_at created_time NOT NULL
);

COMMENT ON COLUMN public.color_scheme.created_at IS 'Creation time of object.';
