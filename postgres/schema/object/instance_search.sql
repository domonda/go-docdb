CREATE TABLE object.instance_search (
    instance_id UUID PRIMARY KEY NOT NULL REFERENCES object.instance(id) ON DELETE CASCADE,
    searchtext TSVECTOR NOT NULL
);

CREATE INDEX instance_search_searchtext_idx ON object.instance_search USING GIN (searchtext);

