/* ===========================================================================
   LAB513 - 03_generate_embeddings.sql   (TEMPLATE)
   Generates a 1,536-dim embedding for every FAQ question by calling the
   Azure OpenAI embeddings deployment (text-embedding-3-small) from T-SQL via
   sp_invoke_external_rest_endpoint, then stores it in dbo.FAQ_Embeddings.

   Placeholders @@EMBED_URL@@ and @@AI_KEY@@ are substituted by deploy.sh
   (rendered copy is written to lab513/.generated/03_generate_embeddings.sql).

   Requires: Azure SQL Database able to call external REST endpoints (GA).
   The api-key is inlined here for lab simplicity; for production use a
   DATABASE SCOPED CREDENTIAL instead of embedding the key in the script.
   =========================================================================== */

SET NOCOUNT ON;

DELETE FROM dbo.FAQ_Embeddings;

DECLARE @id       INT,
        @q        NVARCHAR(1000),
        @payload  NVARCHAR(MAX),
        @response NVARCHAR(MAX),
        @vec      VECTOR(1536),
        @headers  NVARCHAR(MAX) = N'{"api-key": "@@AI_KEY@@"}';

DECLARE faq_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT faq_id, question FROM dbo.FAQ_Content ORDER BY faq_id;

OPEN faq_cur;
FETCH NEXT FROM faq_cur INTO @id, @q;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @payload = N'{"input":"' + STRING_ESCAPE(@q, 'json') + N'"}';

    EXEC sp_invoke_external_rest_endpoint
        @method   = 'POST',
        @url      = N'@@EMBED_URL@@',
        @headers  = @headers,
        @payload  = @payload,
        @response = @response OUTPUT;

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
