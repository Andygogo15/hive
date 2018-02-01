SELECT 'Upgrading MetaStore schema from 2.3.0 to 3.0.0' AS MESSAGE;

-- :r 026-HIVE-16556.mssql.sql
CREATE TABLE METASTORE_DB_PROPERTIES (
  PROPERTY_KEY VARCHAR(255) NOT NULL,
  PROPERTY_VALUE VARCHAR(1000) NOT NULL,
  DESCRIPTION VARCHAR(1000)
);

ALTER TABLE METASTORE_DB_PROPERTIES ADD CONSTRAINT PROPERTY_KEY_PK PRIMARY KEY (PROPERTY_KEY);

--:r 027-HIVE-16575.mssql.sql
CREATE INDEX CONSTRAINTS_CONSTRAINT_TYPE_INDEX ON KEY_CONSTRAINTS(CONSTRAINT_TYPE);

--:r 028-HIVE-16922.mssql.sql
UPDATE SERDE_PARAMS
SET PARAM_KEY='collection.delim'
WHERE PARAM_KEY='colelction.delim';

--:r 029-HIVE-16997.mssql.sql
ALTER TABLE PART_COL_STATS ADD BIT_VECTOR VARBINARY(MAX);
ALTER TABLE TAB_COL_STATS ADD BIT_VECTOR VARBINARY(MAX);

--:r 030-HIVE-16886.mssql.sql
INSERT INTO NOTIFICATION_SEQUENCE (NNI_ID, NEXT_EVENT_ID) SELECT 1,1 WHERE NOT EXISTS (SELECT NEXT_EVENT_ID FROM NOTIFICATION_SEQUENCE);

--:r 031-HIVE-17566.mssql.sql
CREATE TABLE WM_RESOURCEPLAN
(
    RP_ID bigint NOT NULL,
    "NAME" nvarchar(128) NOT NULL,
    QUERY_PARALLELISM int,
    STATUS nvarchar(20) NOT NULL,
    DEFAULT_POOL_ID bigint
);

ALTER TABLE WM_RESOURCEPLAN ADD CONSTRAINT WM_RESOURCEPLAN_PK PRIMARY KEY (RP_ID);

CREATE UNIQUE INDEX UNIQUE_WM_RESOURCEPLAN ON WM_RESOURCEPLAN ("NAME");


CREATE TABLE WM_POOL
(
    POOL_ID bigint NOT NULL,
    RP_ID bigint NOT NULL,
    PATH nvarchar(1024) NOT NULL,
    ALLOC_FRACTION float,
    QUERY_PARALLELISM int,
    SCHEDULING_POLICY nvarchar(1024)
);

ALTER TABLE WM_POOL ADD CONSTRAINT WM_POOL_PK PRIMARY KEY (POOL_ID);

CREATE UNIQUE INDEX UNIQUE_WM_POOL ON WM_POOL (RP_ID, PATH);
ALTER TABLE WM_POOL ADD CONSTRAINT WM_POOL_FK1 FOREIGN KEY (RP_ID) REFERENCES WM_RESOURCEPLAN (RP_ID);


CREATE TABLE WM_TRIGGER
(
    TRIGGER_ID bigint NOT NULL,
    RP_ID bigint NOT NULL,
    "NAME" nvarchar(128) NOT NULL,
    TRIGGER_EXPRESSION nvarchar(1024),
    ACTION_EXPRESSION nvarchar(1024),
    IS_IN_UNMANAGED bit NOT NULL DEFAULT 0
);

ALTER TABLE WM_TRIGGER ADD CONSTRAINT WM_TRIGGER_PK PRIMARY KEY (TRIGGER_ID);

CREATE UNIQUE INDEX UNIQUE_WM_TRIGGER ON WM_TRIGGER (RP_ID, "NAME");

ALTER TABLE WM_TRIGGER ADD CONSTRAINT WM_TRIGGER_FK1 FOREIGN KEY (RP_ID) REFERENCES WM_RESOURCEPLAN (RP_ID);


CREATE TABLE WM_POOL_TO_TRIGGER
(
    POOL_ID bigint NOT NULL,
    TRIGGER_ID bigint NOT NULL
);

ALTER TABLE WM_POOL_TO_TRIGGER ADD CONSTRAINT WM_POOL_TO_TRIGGER_PK PRIMARY KEY (POOL_ID, TRIGGER_ID);

ALTER TABLE WM_POOL_TO_TRIGGER ADD CONSTRAINT WM_POOL_TO_TRIGGER_FK1 FOREIGN KEY (POOL_ID) REFERENCES WM_POOL (POOL_ID);

ALTER TABLE WM_POOL_TO_TRIGGER ADD CONSTRAINT WM_POOL_TO_TRIGGER_FK2 FOREIGN KEY (TRIGGER_ID) REFERENCES WM_TRIGGER (TRIGGER_ID);


CREATE TABLE WM_MAPPING
(
    MAPPING_ID bigint NOT NULL,
    RP_ID bigint NOT NULL,
    ENTITY_TYPE nvarchar(128) NOT NULL,
    ENTITY_NAME nvarchar(128) NOT NULL,
    POOL_ID bigint,
    ORDERING int
);

ALTER TABLE WM_MAPPING ADD CONSTRAINT WM_MAPPING_PK PRIMARY KEY (MAPPING_ID);

CREATE UNIQUE INDEX UNIQUE_WM_MAPPING ON WM_MAPPING (RP_ID, ENTITY_TYPE, ENTITY_NAME);

ALTER TABLE WM_MAPPING ADD CONSTRAINT WM_MAPPING_FK1 FOREIGN KEY (RP_ID) REFERENCES WM_RESOURCEPLAN (RP_ID);

ALTER TABLE WM_MAPPING ADD CONSTRAINT WM_MAPPING_FK2 FOREIGN KEY (POOL_ID) REFERENCES WM_POOL (POOL_ID);

-- Upgrades for Schema Registry objects
ALTER TABLE "SERDES" ADD "DESCRIPTION" nvarchar(4000);
ALTER TABLE "SERDES" ADD "SERIALIZER_CLASS" nvarchar(4000);
ALTER TABLE "SERDES" ADD "DESERIALIZER_CLASS" nvarchar(4000);
ALTER TABLE "SERDES" ADD "SERDE_TYPE" int;

CREATE TABLE "I_SCHEMA" (
  "SCHEMA_ID" bigint primary key,
  "SCHEMA_TYPE" int not null,
  "NAME" nvarchar(256) unique,
  "DB_ID" bigint references "DBS" ("DB_ID"),
  "COMPATIBILITY" int not null,
  "VALIDATION_LEVEL" int not null,
  "CAN_EVOLVE" bit not null,
  "SCHEMA_GROUP" nvarchar(256),
  "DESCRIPTION" nvarchar(4000),
);

CREATE TABLE "SCHEMA_VERSION" (
  "SCHEMA_VERSION_ID" bigint primary key,
  "SCHEMA_ID" bigint references "I_SCHEMA" ("SCHEMA_ID"),
  "VERSION" int not null,
  "CREATED_AT" bigint not null,
  "CD_ID" bigint references "CDS" ("CD_ID"),
  "STATE" int not null,
  "DESCRIPTION" nvarchar(4000),
  "SCHEMA_TEXT" varchar(max),
  "FINGERPRINT" nvarchar(256),
  "SCHEMA_VERSION_NAME" nvarchar(256),
  "SERDE_ID" bigint references "SERDES" ("SERDE_ID"),
  unique ("SCHEMA_ID", "VERSION")
);

UPDATE VERSION SET SCHEMA_VERSION='3.0.0', VERSION_COMMENT='Hive release version 3.0.0' where VER_ID=1;
SELECT 'Finished upgrading MetaStore schema from 2.3.0 to 3.0.0' AS MESSAGE;

-- 033-HIVE-14498
CREATE TABLE MV_CREATION_METADATA
(
    MV_CREATION_METADATA_ID bigint NOT NULL,
    DB_NAME nvarchar(128) NOT NULL,
    TBL_NAME nvarchar(256) NOT NULL,
    TXN_LIST text NULL
);

CREATE TABLE MV_TABLES_USED
(
    MV_CREATION_METADATA_ID bigint NOT NULL,
    TBL_ID bigint NOT NULL
);

ALTER TABLE MV_CREATION_METADATA ADD CONSTRAINT MV_CREATION_METADATA_PK PRIMARY KEY (MV_CREATION_METADATA_ID);

CREATE INDEX MV_UNIQUE_TABLE ON MV_CREATION_METADATA (TBL_NAME,DB_NAME);

ALTER TABLE MV_TABLES_USED ADD FOREIGN KEY(MV_CREATION_METADATA_ID) REFERENCES MV_CREATION_METADATA (MV_CREATION_METADATA_ID);

ALTER TABLE MV_TABLES_USED ADD FOREIGN KEY(TBL_ID) REFERENCES TBLS (TBL_ID);

ALTER TABLE COMPLETED_TXN_COMPONENTS ADD CTC_TIMESTAMP datetime2 NOT NULL DEFAULT(CURRENT_TIMESTAMP);
CREATE INDEX COMPLETED_TXN_COMPONENTS_IDX ON COMPLETED_TXN_COMPONENTS (CTC_DATABASE, CTC_TABLE, CTC_PARTITION);

-- 034-HIVE-18489.mssql.sql
UPDATE FUNC_RU
  SET RESOURCE_URI = 's3a' + SUBSTRING(RESOURCE_URI, 4, LEN(RESOURCE_URI))
  WHERE RESOURCE_URI LIKE 's3n://%' ;

UPDATE SKEWED_COL_VALUE_LOC_MAP
  SET LOCATION = 's3a' + SUBSTRING(LOCATION, 4, LEN(LOCATION))
  WHERE LOCATION LIKE 's3n://%' ;

UPDATE SDS
  SET LOCATION = 's3a' + SUBSTRING(LOCATION, 4, LEN(LOCATION))
  WHERE LOCATION LIKE 's3n://%' ;

UPDATE DBS
  SET DB_LOCATION_URI = 's3a' + SUBSTRING(DB_LOCATION_URI, 4, LEN(DB_LOCATION_URI))
  WHERE DB_LOCATION_URI LIKE 's3n://%' ;