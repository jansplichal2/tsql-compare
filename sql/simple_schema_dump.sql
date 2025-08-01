/* ---------------------------------------------------------------------------
   simple_schema_dump-SQL Server 2012 edition
   Re-implements STRING_AGG (…) WITHIN GROUP with STUFF + FOR XML PATH
   ---------------------------------------------------------------------------*/
WITH vars AS
(
    SELECT DB_NAME() AS v_SchemaName
),

/* ---------------------------------------------------------------------------
   1.  Tables / views that belong to the current DB
   ---------------------------------------------------------------------------*/
baseTbl AS
(
    SELECT  TABLE_CATALOG AS SchemaName,
            table_type,
            table_name
    FROM    INFORMATION_SCHEMA.TABLES
    WHERE   TABLE_CATALOG = (SELECT v_SchemaName FROM vars)
),

/* ---------------------------------------------------------------------------
   2.  One row per table / view just to say “it exists”
   ---------------------------------------------------------------------------*/
metaForTbl AS
(
    SELECT  t.SchemaName,
            t.table_name                                                    AS TableName,
            '(' + CASE WHEN t.table_type = 'BASE TABLE' THEN 'Table'
                        WHEN t.table_type = 'VIEW'       THEN 'View'
                        ELSE 'UK' END + ')'                                   AS ObjectType,
            t.table_name                                                    AS ObjectName,
            '(Exists)'                                                      AS PropertyName,
            ' '                                                             AS PropertyValue
    FROM    baseTbl t
),

/* ---------------------------------------------------------------------------
   3-a. Column data-type
   ---------------------------------------------------------------------------*/
metaForCol_dataType AS
(
    SELECT  ft.SchemaName,
            ft.table_name                                                   AS TableName,
            'Column'                                                        AS ObjectType,
            tut.column_name                                                 AS ObjectName,
            '2'                                                             AS PropertyName,
            /* VARCHAR(10), NUMERIC(18,2), DATETIME(3) … */
            COALESCE(tut.data_type,'unknown') + '('
            + CASE WHEN tut.CHARACTER_MAXIMUM_LENGTH IS NOT NULL
                   THEN CAST(tut.CHARACTER_MAXIMUM_LENGTH AS varchar(10)) ELSE '' END
            + CASE WHEN tut.DATA_TYPE IN ('date','datetime')
                   THEN ',' + CAST(tut.DATETIME_PRECISION AS varchar(10))
                   WHEN tut.NUMERIC_PRECISION IS NULL
                   THEN ''
                   ELSE ',' + CAST(tut.NUMERIC_PRECISION AS varchar(10))
              END
            + CASE WHEN tut.NUMERIC_SCALE IS NOT NULL
                   THEN ',' + CAST(tut.NUMERIC_SCALE AS varchar(10)) ELSE '' END
            + ')'                                                            AS PropertyValue
    FROM    INFORMATION_SCHEMA.COLUMNS tut
    JOIN    baseTbl ft
           ON ft.SchemaName = tut.TABLE_CATALOG
          AND ft.table_name  = tut.table_name
),

/* ---------------------------------------------------------------------------
   3-b. Column NULL / NOT NULL
   ---------------------------------------------------------------------------*/
metaForCol_nullable AS
(
    SELECT  ft.SchemaName,
            ft.table_name                                                   AS TableName,
            'Column'                                                        AS ObjectType,
            tut.column_name                                                 AS ObjectName,
            '3'                                                             AS PropertyName,
            CASE WHEN tut.IS_NULLABLE = 'YES' THEN 'NULL' ELSE 'NOT NULL' END
                                                                            AS PropertyValue
    FROM    INFORMATION_SCHEMA.COLUMNS tut
    JOIN    baseTbl ft
           ON ft.SchemaName = tut.TABLE_CATALOG
          AND ft.table_name  = tut.table_name
),

/* ---------------------------------------------------------------------------
   3-c. Column ordinal position
   ---------------------------------------------------------------------------*/
metaForCol_ordpos AS
(
    SELECT  ft.SchemaName,
            ft.table_name                                                   AS TableName,
            'Column'                                                        AS ObjectType,
            tut.column_name                                                 AS ObjectName,
            '1'                                                             AS PropertyName,
            RIGHT('000' + CAST(tut.ORDINAL_POSITION AS varchar(3)),3)       AS PropertyValue
    FROM    INFORMATION_SCHEMA.COLUMNS tut
    JOIN    baseTbl ft
           ON ft.SchemaName = tut.TABLE_CATALOG
          AND ft.table_name  = tut.table_name
),

/* ---------------------------------------------------------------------------
   3-d.  Put the three column-level bits together
   ---------------------------------------------------------------------------*/
metaAllCols AS
(
    /* feeder UNION that every later self-reference can see */
    SELECT * FROM metaForCol_dataType
    UNION ALL
    SELECT * FROM metaForCol_nullable
    UNION ALL
    SELECT * FROM metaForCol_ordpos
),
/* aggregate column properties per column, replacing STRING_AGG */
metaAllCols_agg AS
(
    SELECT  mc.schemaname,
            mc.tablename,
            mc.objecttype,
            mc.objectname,
            'Properties'                                                    AS propertyname,
            STUFF
            (   (   SELECT  ' | ' + mc2.propertyvalue
                    FROM    metaAllCols mc2
                    WHERE   mc2.schemaname  = mc.schemaname
                      AND   mc2.tablename   = mc.tablename
                      AND   mc2.objecttype  = mc.objecttype
                      AND   mc2.objectname  = mc.objectname
                    ORDER BY mc2.propertyname,
                             mc2.propertyvalue
                    FOR XML PATH(''), TYPE
                ).value('.','nvarchar(max)')
              ,1,3,'')                                                      AS propertyvalue
    FROM    metaAllCols mc
    GROUP BY mc.schemaname,
             mc.tablename,
             mc.objecttype,
             mc.objectname
),

/* ---------------------------------------------------------------------------
   4.  PK / FK / UNIQUE constraints
   ---------------------------------------------------------------------------*/
metaForKeys AS
(
    SELECT  cons.TABLE_CATALOG                                              AS SchemaName,
            cons.TABLE_NAME                                                 AS TableName,
            CASE WHEN cons.constraint_type = 'PRIMARY KEY' THEN 'PKey'
                 WHEN cons.constraint_type = 'UNIQUE'       THEN 'UKey'
                 WHEN cons.constraint_type = 'FOREIGN KEY'  THEN 'FKey'
                 ELSE 'X' END                                              AS ObjectType,
            cons.constraint_name                                            AS ObjectName,
            'FieldList'                                                     AS PropertyName,
            /* STRING_AGG replacement */
            STUFF
            (   (   SELECT  ',' + kcu2.COLUMN_NAME
                    FROM    INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu2
                    WHERE   kcu2.TABLE_CATALOG   = cons.TABLE_CATALOG
                      AND   kcu2.TABLE_NAME      = cons.TABLE_NAME
                      AND   kcu2.CONSTRAINT_NAME = cons.CONSTRAINT_NAME
                    ORDER BY kcu2.ORDINAL_POSITION
                    FOR XML PATH(''), TYPE
                ).value('.','nvarchar(max)')
              ,1,1,'')                                                      AS PropertyValue
    FROM    INFORMATION_SCHEMA.TABLE_CONSTRAINTS      cons
    WHERE   cons.TABLE_CATALOG = (SELECT v_SchemaName FROM vars)
      AND   cons.TABLE_NAME    IN (SELECT DISTINCT table_name FROM baseTbl)
      AND   cons.constraint_type IN ('PRIMARY KEY','FOREIGN KEY','UNIQUE')
),

/* ---------------------------------------------------------------------------
   5.  Non-unique, non-PK indexes
   ---------------------------------------------------------------------------*/
metaForIdxs AS
(
    SELECT  (SELECT v_SchemaName FROM vars)                                 AS SchemaName,
            o.name                                                         AS TableName,
            'Index'                                                        AS ObjectType,
            i.name                                                         AS ObjectName,
            'FieldList'                                                    AS PropertyName,
            /* STRING_AGG replacement */
            STUFF
            (   (   SELECT  ',' + c2.name
                    FROM    sys.index_columns  ic2
                    JOIN    sys.columns       c2
                           ON c2.object_id  = ic2.object_id
                          AND c2.column_id  = ic2.column_id
                    WHERE   ic2.object_id    = i.object_id
                      AND   ic2.index_id     = i.index_id
                    ORDER BY ic2.key_ordinal
                    FOR XML PATH(''), TYPE
                ).value('.','nvarchar(max)')
              ,1,1,'')                                                      AS PropertyValue
    FROM    sys.indexes               i
    JOIN    sys.objects               o  ON o.object_id = i.object_id
    WHERE   i.type          = 2      /* non-clustered */
      AND   i.is_unique     = 0
      AND   i.is_primary_key= 0
      AND   o.type          = 'U'
),

/* ---------------------------------------------------------------------------
   6.  Union everything together
   ---------------------------------------------------------------------------*/
allMetadata AS
(
    SELECT * FROM metaForTbl
    UNION ALL
    SELECT * FROM metaAllCols_agg
    UNION ALL
    SELECT * FROM metaForKeys
    UNION ALL
    SELECT * FROM metaForIdxs
)

/* ---------------------------------------------------------------------------
   7.  Final projection
   ---------------------------------------------------------------------------*/
SELECT  CASE WHEN objecttype IN ('(Table)','(View)')
            THEN schemaname ELSE ' ' END                                    AS schema_nm,
        CASE WHEN objecttype IN ('(Table)','(View)')
            THEN tablename  ELSE ' ' END                                    AS tbl_nm,
        objecttype                                                          AS obj_typ,
        objectname                                                          AS obj_nm,
        propertyvalue                                                       AS properties
FROM    allMetadata
ORDER BY schemaname,
         tablename,
         objecttype,
         CASE WHEN objecttype='Column' THEN propertyvalue ELSE ' ' END,
         objectname;
