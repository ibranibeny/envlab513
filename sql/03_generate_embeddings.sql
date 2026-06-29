/* ===========================================================================
   LAB513 - 03_generate_embeddings.sql   (TEMPLATE - Managed Identity / token auth)
   Generates a 1,536-dim embedding for every FAQ question by calling the
   Azure OpenAI embeddings deployment (text-embedding-3-small) from T-SQL via
   sp_invoke_external_rest_endpoint, then stores it in dbo.FAQ_Embeddings.

   Authentication: Microsoft Entra token via the Azure SQL server's
   system-assigned MANAGED IDENTITY (no api-key). The server identity must hold
   the "Cognitive Services OpenAI User" role on the AI Foundry account.

   Placeholders substituted by deploy.sh (rendered copy written to
   lab513/.generated/03_generate_embeddings.sql):
     @@AI_ACCOUNT_URL@@  e.g. https://aif-lab513-xxxx.cognitiveservices.azure.com
     @@EMBED_URL@@       full embeddings endpoint (same host + /openai/...).
   The DATABASE SCOPED CREDENTIAL name MUST be a URL prefix of @@EMBED_URL@@.
   =========================================================================== */

SET NOCOUNT ON;

-- A database master key is required to protect the DATABASE SCOPED CREDENTIAL secret.
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE [name] = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'@@MASTER_KEY_PWD@@';

-- Managed-identity credential scoped to the Azure OpenAI endpoint (token auth).
IF EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = N'@@AI_ACCOUNT_URL@@')
    DROP DATABASE SCOPED CREDENTIAL [@@AI_ACCOUNT_URL@@];
CREATE DATABASE SCOPED CREDENTIAL [@@AI_ACCOUNT_URL@@]
    WITH IDENTITY = 'Managed Identity',
         SECRET   = '{"resourceid": "https://cognitiveservices.azure.com"}';

DELETE FROM dbo.FAQ_Embeddings;

DECLARE @id       INT,
        @q        NVARCHAR(1000),
        @payload  NVARCHAR(MAX),
        @response NVARCHAR(MAX),
        @vec      VECTOR(1536);

DECLARE faq_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT faq_id, question FROM dbo.FAQ_Content ORDER BY faq_id;

OPEN faq_cur;
FETCH NEXT FROM faq_cur INTO @id, @q;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @payload = N'{"input":"' + STRING_ESCAPE(@q, 'json') + N'"}';

    EXEC sp_invoke_external_rest_endpoint
        @method     = 'POST',
        @url        = N'@@EMBED_URL@@',
        @credential = [@@AI_ACCOUNT_URL@@],
        @payload    = @payload,
        @response   = @response OUTPUT;

    -- Embeddings response body is under $.result; the vector is data[0].embedding.
    SET @vec = CAST(JSON_QUERY(@response, '$.result.data[0].embedding') AS VECTOR(1536));

    INSERT INTO dbo.FAQ_Embeddings (faq_id, question_embedding)
    VALUES (@id, @vec);

    FETCH NEXT FROM faq_cur INTO @id, @q;
END

CLOSE faq_cur;
DEALLOCATE faq_cur;

-- Both counts should match (Exercise 1, Task 4).
SELECT
    (SELECT COUNT(*) FROM dbo.FAQ_Content)    AS faq_count,
    (SELECT COUNT(*) FROM dbo.FAQ_Embeddings) AS embedding_count;
GO
