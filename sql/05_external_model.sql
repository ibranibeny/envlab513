/* ===========================================================================
   05_external_model.sql  -  Register the Azure OpenAI embedding deployment as a
   named EXTERNAL MODEL so the modern AI_GENERATE_EMBEDDINGS(... USE MODEL
   [text-embedding-3-small]) syntax works (used by GitHub Copilot in Exercise 2).

   Without this object, a query that calls
       AI_GENERATE_EMBEDDINGS(@q USE MODEL [text-embedding-3-small])
   fails with: Msg 15151 "Cannot find the external model 'text-embedding-3-small'".

   Placeholders @@EMBED_URL@@ / @@AI_ACCOUNT_URL@@ are substituted by deploy.sh.
   Authentication uses the SQL server's MANAGED IDENTITY (token, no api-key) via
   the DATABASE SCOPED CREDENTIAL created in 03_generate_embeddings.sql, so this
   script must run AFTER 03.
   =========================================================================== */

SET NOCOUNT ON;

IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'text-embedding-3-small')
    DROP EXTERNAL MODEL [text-embedding-3-small];

CREATE EXTERNAL MODEL [text-embedding-3-small]
WITH (
    LOCATION   = '@@EMBED_URL@@',
    API_FORMAT = 'Azure OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    MODEL      = 'text-embedding-3-small',
    CREDENTIAL = [@@AI_ACCOUNT_URL@@]
);
GO

PRINT 'External model ready: text-embedding-3-small';
GO
