--set up primary key for moma
ALTER TABLE moma ADD PRIMARY KEY (object_id);

--create columns for new values
ALTER TABLE luw19.moma
ADD COLUMN nationality TEXT,
ADD COLUMN birth_place TEXT,
ADD COLUMN birth_date INTEGER,
ADD COLUMN death_date INTEGER;

-- perform update moma table
WITH splitted_data AS (
SELECT title,
       detail[1] AS nationality,
       detail[4] AS birth_place,
       detail[5] AS birth_date,
       detail[6] AS death_date,
       object_id
FROM (SELECT luw19.moma.*,
             regexp_matches(luw19.moma.artist_bio, '\(([^),]+),?\s?(born )?(([^\.]+)\.? )?(\d{4})?(\d{4})?\)') as detail
      FROM luw19.moma
     ) t
)
UPDATE luw19.moma
SET
  nationality = val.nationality,
  birth_place = val.birth_place,
  birth_date = val.birth_date :: INTEGER,
  death_date = val.death_date :: INTEGER
FROM (
       SELECT
         nationality,
         birth_place,
         birth_date,
         death_date,
         object_id
       FROM splitted_data
     ) AS val
WHERE luw19.moma.object_id = val.object_id;
--dropping old column
ALTER TABLE luw19.moma
  DROP artist_bio;

--creating artist table
CREATE TABLE artists (artist VARCHAR(100) PRIMARY KEY , nationality VARCHAR(100), birth_place VARCHAR(100), birth_date INTEGER, death_date INTEGER);
INSERT INTO artists (artist, nationality, birth_place, birth_date, death_date)
    SELECT DISTINCT artist,
      nationality,
      birth_place,
      birth_date,
      death_date
        FROM luw19.moma;

--dropping old values
ALTER TABLE luw19.moma
  DROP artist,
  DROP nationality,
  DROP birth_date,
  DROP birth_place,
  DROP death_date;



--creating table which will hold a media
CREATE TABLE materials (object_id INTEGER, PRIMARY KEY (object_id));
INSERT INTO materials(object_id)
    SELECT object_id FROM moma;
ALTER TABLE materials ADD COLUMN media_id INTEGER;
--creating and splitting media table
CREATE TABLE media (object_id INTEGER,medium VARCHAR(1500));
--inserting values
INSERT INTO media(object_id,medium)
    SELECT object_id,
      regexp_split_to_table("medium", '(([,;] (?!printed))|[,;]? and )') "medium"
FROM luw19.moma;
--adding a primary key for that table
ALTER TABLE media ADD COLUMN media_id SERIAL PRIMARY KEY;
--update materials from media
UPDATE materials
SET media_id=media.media_id
FROM media WHERE materials.object_id=media.object_id;

--dropping object_id
ALTER TABLE media DROP object_id;


-- dimensions table with splitted dimensions as dimension_id
CREATE TABLE dimensions
  AS
  --splitting dimensions
WITH splitted_dimension AS (
        SELECT luw19.moma.moma_number
        , regexp_replace(moma.moma_number, '([0-9\.]+\.)([0-9]+)-([0-9]+)', e'\\1', e'g') AS dimension_id
        , regexp_replace(moma.moma_number, '([0-9\.]+\.)([0-9]+)-([0-9]+)', e'\\2', e'g') AS dimension
        , regexp_replace(moma.moma_number, '([0-9\.]+\.)([0-9]+)-([0-9]+)', e'\\3', e'g') AS object
        , moma.dimensions
        , moma.object_id
        FROM luw19.moma
        )
  SELECT a1.moma_number
       , a1.dimension_id || generate_series( a1.dimension::integer, a1.object::integer)::TEXT AS dimension_id
       , a1.dimensions, a1.object_id
FROM splitted_dimension a1
WHERE a1.dimension <> a1.dimension_id
UNION ALL
SELECT a0.moma_number
        , a0.dimension_id AS dimension_id
        , a0.dimensions, a0.object_id
FROM splitted_dimension a0
WHERE a0.dimension = a0.dimension_id;

--selecting non-unique values and giving them a selected index
with stats as (
    SELECT "dimension_id",
           "object_id",
           row_number() over (partition by "dimension_id" order by object_id) as rn
    FROM dimensions
)
UPDATE dimensions
   SET "dimension_id" = CASE WHEN s.rn > 1 THEN s."dimension_id" || '-' || s.rn
                   ELSE s."dimension_id"
              END
  FROM stats s
 WHERE S."dimension_id" = dimensions."dimension_id"
   AND S."object_id" = dimensions."object_id";

--adding dimension_id column to materials
ALTER TABLE materials ADD COLUMN dimension_id TEXT;
--update column to hold dimension_id
UPDATE materials
SET dimension_id=dimensions.dimension_id
FROM dimensions WHERE dimensions.object_id=materials.object_id;

--creating a classification table
--CREATE TABLE classification (moma_number VARCHAR(20), classification VARCHAR(100), department VARCHAR(100), date_acquired DATE, curator_approved VARCHAR, PRIMARY KEY (moma_number));
--INSERT INTO classification (moma_number, classification, department, date_acquired, curator_approved)
--    SELECT moma_number,
--      classification,
--      department,
--      date_acquired,
--      curator_approved
--FROM moma;

--ALTER TABLE moma
--  DROP curator_approved,
--  DROP date_acquired,
--DROP classification,
--DROP department;
ALTER TABLE moma DROP moma_number;
-- creating table classifications for the distinct department
CREATE TABLE classifications (classification VARCHAR(100) PRIMARY KEY, department VARCHAR(100));
INSERT INTO classifications (classification, department)
    SELECT DISTINCT classification,department
      FROM moma;
ALTER TABLE moma DROP department;

--forcing to set up foreign keys for artists
ALTER TABLE moma
ADD CONSTRAINT artists_artist_pk
FOREIGN KEY (artist)
REFERENCES artists
ON DELETE CASCADE;

--forcing to set up foreign keys for moma->materials
ALTER TABLE moma
ADD CONSTRAINT moma_materials_fk
FOREIGN KEY (object_id)
REFERENCES materials(object_id)
ON DELETE CASCADE;

--forcing to set up foreign keys for moma->classification
ALTER TABLE moma
ADD CONSTRAINT moma_classification_fk
FOREIGN KEY (moma_number)
REFERENCES classification(moma_number)
ON DELETE CASCADE;

-- forcing to set up foreign keys for classification
ALTER TABLE moma
ADD CONSTRAINT classification_pkey
FOREIGN KEY (moma_number)
REFERENCES classification
ON DELETE CASCADE;

-- forcing to set up foreign keys for dimensions
ALTER TABLE dimensions
ADD CONSTRAINT moma_moma_number_pk
FOREIGN KEY (object_id)
REFERENCES moma
ON DELETE CASCADE;

-- forcing to set up foreign keys for material
ALTER TABLE dimensions
ADD CONSTRAINT moma_dimensions_fk
FOREIGN KEY (object_id)
REFERENCES moma (object_id)
ON DELETE CASCADE;
-- next one
ALTER TABLE moma
ADD CONSTRAINT material3_pkey
FOREIGN KEY (object_id)
REFERENCES materials
ON DELETE CASCADE;


-- query to find a title and department for Yoko Ono.
WITH yoko AS (
SELECT title,object_id
  FROM moma
  WHERE artist = 'Yoko Ono'
)
SELECT
    moma.title, classifications.department
FROM
    yoko
    INNER JOIN moma on moma.object_id=yoko.object_id
    INNER JOIN classifications ON moma.classification = classifications.classification;


-- 2nd Query

SELECT
  media_id,
  department
FROM (SELECT media_id, classification FROM materials
         LEFT JOIN moma ON materials.object_id = moma.object_id)
  AS media_with_classifications
  LEFT JOIN classifications ON media_with_classifications.classification = classifications.classification;


SELECT  artist, count(*) AS works, array_agg(distinct year order by year asc)
FROM (SELECT
  media_id,
  department
FROM (SELECT media_id, classification FROM materials
         LEFT JOIN moma ON materials.object_id = moma.object_id)
  AS media_with_classifications
  LEFT JOIN classifications ON media_with_classifications.classification = classifications.classification)t
JOIN artists ON moma.artist = artists.artist
  JOIN moma ON moma.object_id=materials.object_id
GROUP BY artist ORDER BY works DESC LIMIT 10;
